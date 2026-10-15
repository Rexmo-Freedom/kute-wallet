// lib/services/one_balance/predictions_venue_cash_order.dart
//
// A bet funded from Dollars and the Investing cash, no Bitcoin: what the
// bet slip hands the venue-cash runner (`venue_cash_funded_order.dart`)
// once the person approved. The runner records the step graph at the
// approval and starts every source at once; this file is the bet's side
// of it, reading only the provider container so it runs whatever happens
// to the slip:
//
//  * queue: the bet waits, held (`awaitingDeposit` with its funding cap,
//    never fired), until Dollars' own share left; then it is queued
//    (`awaitingBalance`) behind that move and the Investing cash on its
//    way straight here. No Dollars share: queued at once, behind the legs.
//  * fundMore: what an Investing leg brought home to Dollars goes on into
//    Predictions under the same approval, and the queued bet waits for it
//    too (its arriving figure grows by that move).
//  * dropOrder: a stop drops the held or queued bet and cancels its
//    approval.
//
// The autofire then places the bet once Predictions hold enough (its
// readiness: the conversion to pUSD, the spend allowance, the balance).

import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/helpers/auth_grant.dart' show AuthGrant;
import 'package:kute/helpers/auth_grant_registry.dart' show AuthGrantRegistry;
import 'package:kute/providers/pending_bet_autofire.dart'
    show kPendingBetAutofireId;
import 'package:kute/providers/pending_polymarket_bet_provider.dart';
import 'package:kute/services/one_balance/funded_orders.dart'
    show FundedOrderLabel;
import 'package:kute/services/one_balance/one_balance_state.dart'
    show OneBalanceVenue;
import 'package:kute/services/one_balance/order_funding.dart';
import 'package:kute/services/one_balance/prediction_funding_ledger.dart';
import 'package:kute/services/one_balance/venue_cash_funded_order.dart'
    show VenueCashFundedRequest;
import 'package:kute/services/one_balance/venue_cash_source.dart'
    show VenueCashPlan;
import 'package:kute/services/one_balance/venue_funder.dart'
    show UserGrantAuthorization;
import 'package:kute/services/tracking_service.dart';

/// The venue-cash runner's request for [pending], approved under [grant]:
/// [legPlan] (the plan the approval bound) run exactly, [fundUsd] the
/// approved move into Predictions, [readyUsd] what Predictions held for
/// the bet at the approval ([balanceUsd] its whole cash, [incomingUsd]
/// pre-funded money still on its way).
VenueCashFundedRequest predictionsVenueCashRequest(
  ProviderContainer container, {
  required AuthGrant grant,
  required PendingBetIntent pending,
  required FundedOrderLabel label,
  required VenueCashPlan legPlan,
  required double fundUsd,
  required double requiredUsd,
  required double readyUsd,
  required double balanceUsd,
  double incomingUsd = 0,
  String? moveId,
  String? entrySource,
  String? marketKind,
}) {
  /// The bet this run queues, while it is still this run's.
  PendingBetIntent? held() {
    final current = container.read(pendingPolymarketBetProvider);
    if (current == null ||
        current.tokenId != pending.tokenId ||
        current.status == PendingBetStatus.failed ||
        current.status == PendingBetStatus.done) {
      return null;
    }
    return current;
  }

  PendingPolymarketBetNotifier notifier() =>
      container.read(pendingPolymarketBetProvider.notifier);

  // The queue below is handed what Predictions will hold with the legs
  // straight here counted; the difference is those legs.
  final approvedReadyUsd = readyUsd;

  return VenueCashFundedRequest(
    venue: OneBalanceVenue.predictions,
    grant: grant,
    label: label,
    fundUsd: fundUsd,
    readyUsd: readyUsd,
    plan: legPlan,
    moveId: moveId,
    entrySource: entrySource,
    queue: ({required double fundUsd, required double readyUsd}) async {
      final current = held();
      if (current == null) return const OrderFundingRefused('order_gone');
      // The Investing cash on its way straight here.
      final direct = math.max(0.0, readyUsd - approvedReadyUsd);
      if (fundUsd < 0.01) {
        // Nothing from Dollars: queued now, behind the legs.
        final arriving = incomingUsd + direct;
        notifier().setIntent(current.copyWith(
          status: PendingBetStatus.awaitingBalance,
          fundReadyUsd: balanceUsd,
          fundArrivingUsd: arriving > 0 ? arriving : null,
          queuedAt: DateTime.now(),
        ));
        return const OrderFundingNotNeeded();
      }
      final outcome =
          await container.read(orderFundingControllerProvider).fundAndQueue(
                venue: OneBalanceVenue.predictions,
                orderUsd: pending.amount,
                requiredUsd: requiredUsd,
                readyUsd: readyUsd,
                auth: UserGrantAuthorization(grant),
                fundUsd: fundUsd,
                entrySource: entrySource,
                marketKind: marketKind,
                continueJourney: true,
              );
      final queued = held() ?? current;
      switch (outcome) {
        case OrderFundingFunded(:final move):
          // Dollars have left: the autofire places the bet once
          // Predictions hold what they held plus this move and the legs
          // straight here.
          final quoteRef = TrackingService.orderRef(move.quoteId);
          PredictionFundingLedger.instance.sent(quoteRef, usd: move.sentUsd);
          notifier().setIntent(queued.copyWith(
            status: PendingBetStatus.awaitingBalance,
            fundQuoteRef: quoteRef,
            fundReadyUsd: balanceUsd + incomingUsd,
            fundArrivingUsd: move.arrivingUsdEstimate + direct,
            queuedAt: DateTime.now(),
          ));
        case OrderFundingNotNeeded():
          final arriving = incomingUsd + direct;
          notifier().setIntent(queued.copyWith(
            status: PendingBetStatus.awaitingBalance,
            fundReadyUsd: arriving > 0 ? balanceUsd : null,
            fundArrivingUsd: arriving > 0 ? arriving : null,
            queuedAt: DateTime.now(),
          ));
        default:
          break;
      }
      return outcome;
    },
    fundMore: (controller, usd) async {
      final outcome = await controller.fundAndQueue(
        venue: OneBalanceVenue.predictions,
        orderUsd: pending.amount,
        requiredUsd: requiredUsd,
        // The bet is queued already: this only moves what came home,
        // within what the approval binds.
        readyUsd: 0,
        auth: UserGrantAuthorization(grant),
        fundUsd: usd,
        entrySource: entrySource,
        keepUnconfirmed: true,
        continueJourney: true,
      );
      if (outcome case OrderFundingFunded(:final move)) {
        PredictionFundingLedger.instance
            .sent(TrackingService.orderRef(move.quoteId), usd: move.sentUsd);
        final queued = held();
        if (queued != null &&
            queued.status == PendingBetStatus.awaitingBalance) {
          notifier().setIntent(queued.copyWith(
              fundArrivingUsd:
                  (queued.fundArrivingUsd ?? 0) + move.arrivingUsdEstimate));
        }
      }
      return outcome;
    },
    dropOrder: () {
      final current = container.read(pendingPolymarketBetProvider);
      if (current != null &&
          current.tokenId == pending.tokenId &&
          (current.status == PendingBetStatus.awaitingDeposit ||
              current.status == PendingBetStatus.awaitingBalance)) {
        notifier().clear();
      }
      AuthGrantRegistry.instance.cancelAutofire(kPendingBetAutofireId);
      grant.revoke();
    },
  );
}
