// lib/services/one_balance/bitcoin_funded_order.dart
//
// An order slip short of the WHOLE Investments balance: one tap on "Add
// $X to Investments", ONE Face ID, then every leg at once (founder
// decisions 14 and 15 October 2026: "it should go directly into
// polymarket or hyperliquid if i am there already and i have no usdb
// balance ... we must parallelize these things decently"):
//
//   * Bitcoin → the venue in ONE Orchestra order, straight to the
//     wallet's own venue deposit (`bitcoin_to_venue_leg.dart`), sized to
//     what the other legs do not bring;
//   * Dollars → the venue for the Dollars' share, and the other venue's
//     cash (straight in where the approval binds it), started the moment
//     the Bitcoin leg's verified quote is accepted;
//   * the venue's readiness (Predictions: pUSD conversion, the spend
//     allowance, the venue's own balance; Investing: the credit where the
//     order draws from), from the first money landing;
//   * the order, placed by the venue's own autofire at a fresh price once
//     the venue can take it.
//
// The whole thing is a step graph (`money_steps.dart`) driven by ONE
// runner; the slip renders that same graph as its sub-steps and the record
// (`fundedOrdersProvider`) persists it.
//
// The direct leg goes only when it costs the person no more than the
// via-Dollars chain (`planDirectBitcoinLeg`). Otherwise, or when Orchestra
// refuses the direct route BEFORE any sats leave (no catalog, route off,
// the quote fails), the chain runs as it always did: Bitcoin → Dollars
// (`spark:BTC → spark:USDB`, own Spark), then Dollars → the venue; the
// refusal is remembered in `DirectRouteRefusals` like the other direct
// routes.
//
// The slip validates everything and asks for the one approval BEFORE any
// money moves: the order's own autofire grant, extended with the Bitcoin
// leg (`BitcoinLegGrants.limitWithDirect`: at most N sats, by the via
// route to the wallet's own Spark address or by the direct route to
// exactly the wallet's own venue deposit). This runner then works
// headless, so the slip may close at any point:
//
//   * a Bitcoin leg pays only a verified quote that grant covers
//     (`BitcoinLegGrants.stepUpDirect` / `stepUp`, single use), no prompt;
//   * the Dollars move runs under the SAME grant (`fundVenue`, the
//     controller's own Dollars check is the guard), no second prompt;
//   * the venue's autofire places the order; the runner follows it. (The
//     margin sheet runs the same chain and signs its margin change in
//     this step instead: `margin_funding.dart`.)
//
// Anything that stops after the Bitcoin left leaves the money in the venue
// (direct) or in Dollars (the chain), visible, with the order dropped and
// its approval cancelled: the slip then says where it is ("Your $X is in
// Investments. Tap to place."). A leg Orchestra refunds sends the bitcoin
// back home. A refusal before the sats leave moves nothing.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/helpers/auth_grant.dart' show AuthGrant;
import 'package:kute/helpers/venue_intents.dart' show BitcoinLegGrants;
import 'package:kute/providers/hyperliquid_account_provider.dart'
    show hyperliquidAddressProvider;
import 'package:kute/providers/polymarket_trading_provider.dart'
    show polymarketTradingProvider;
import 'package:kute/services/one_balance/bitcoin_to_venue_leg.dart';
import 'package:kute/services/one_balance/hyperliquid_venue_funder.dart'
    show hyperliquidVenueFunderProvider;
import 'package:kute/services/one_balance/money_steps.dart';
import 'package:kute/services/one_balance/investments_spendable.dart'
    show VenueCashSnapshot, venueCashSnapshotProvider;
import 'package:kute/services/one_balance/venue_readiness.dart'
    show readinessPhasesOf;
import 'package:kute/services/one_balance/predictions_venue_funder.dart'
    show kPredictionsMinMoveUsd, predictionsVenueFunderProvider;
import 'package:kute/l10n/l10n.dart';
import 'package:kute/services/funding/hot_settlement.dart' show HotSettlement;
import 'package:kute/models/breez/sdk_instance.dart'
    show ArrivalAsset, BreezSdkSpark;
import 'package:kute/models/orchestra_model.dart' show OrchestraEstimate;
import 'package:kute/providers/balance_provider.dart'
    show walletBalanceCacheProvider;
import 'package:kute/providers/breez_config_provider.dart'
    show breezSDKProvider;
import 'package:kute/providers/currency_conversions_provider.dart'
    show currencyProvider, selectedCurrencyProvider;
import 'package:kute/providers/pending_hyperliquid_order_provider.dart'
    show
        HlReadiness,
        PendingHlOrderIntent,
        PendingHlOrderStatus,
        pendingHlOrderAutoFireProvider,
        pendingHyperliquidOrderProvider;
import 'package:kute/providers/pending_polymarket_bet_provider.dart'
    show
        PendingBetIntent,
        PendingBetStatus,
        PredictionsReadiness,
        pendingPolymarketBetProvider;
import 'package:kute/providers/settings_provider.dart' show settingsProvider;
import 'package:kute/providers/spark_address_provider.dart'
    show sparkSelfAddressProvider;
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceCheckProvider, usdBalanceProvider, usdDollarsFromNodeInfo;
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/services/api/orchestra_api.dart' show OrchestraService;
import 'package:kute/services/background_sync_service.dart'
    show BackgroundSyncService;
import 'package:kute/services/funding/settlement_runner.dart'
    show SettlementFundingUnknown, SettlementStepUpHook, SettlementStopped;
import 'package:kute/services/one_balance/bitcoin_to_dollars_leg.dart';
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/order_funding.dart';
import 'package:kute/services/one_balance/venue_cash_source.dart'
    show
        DirectRouteRefusals,
        VenueCashFor,
        VenueCashPullOutcome,
        VenueCashPuller;
import 'package:kute/services/one_balance/venue_funder.dart'
    show RouteUnavailable, VenueCashDestination, VenueMoveResult;
import 'package:kute/services/orchestra/arrival_target.dart'
    show kArrivalTargetBuffer;
import 'package:kute/providers/swap_orders_provider.dart'
    show swapOrdersProvider;
import 'package:kute/services/orchestra/venue_arrivals.dart'
    show OrchestraOrderIds, VenueArrivals;
import 'package:kute/services/orchestra_routes.dart'
    show kOrchestraUsdAssetCode, kOrchestraUsdChain;
import 'package:kute/helpers/orchestra_router.dart'
    show orchestraAmountToDouble;
import 'package:kute/services/tracking_service.dart';
import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart'
    show GetInfoRequest;

/// What a Bitcoin leg handed back once its sats left.
@immutable
class BitcoinLegTicket {
  const BitcoinLegTicket({
    required this.quoteId,
    required this.sats,
    required this.estimatedOutUsd,
    required this.minOutUsd,
    this.orderId,
    this.registration,
  });

  final String quoteId;
  final String? orderId;
  final Future<String?>? registration;
  final int sats;
  final double estimatedOutUsd;
  final double minOutUsd;
}

/// Sends one Bitcoin → Dollars leg ([BitcoinToDollarsLeg.send]: quote,
/// [stepUp], payment). [onSending] runs right before the payment call.
typedef BitcoinLegSend = Future<BitcoinLegTicket> Function({
  required String sparkAddress,
  required BitcoinLegPlan plan,
  required SettlementStepUpHook stepUp,
  required void Function() onSending,
});

/// Everything the runner reads from the wallet, as functions so tests
/// can stand in for the SDK, Orchestra and the clock.
class BitcoinLegEnv {
  const BitcoinLegEnv({
    required this.ownSpark,
    required this.send,
    required this.watcher,
    required this.dollarsNow,
    required this.freshDollars,
    this.ownVenue,
    this.planDirect,
    this.sendDirect,
    this.legStatus,
    this.legPollEvery = const Duration(seconds: 1),
    this.readiness,
    this.checkDollars,
    this.legEnded,
  });

  /// The wallet's own Spark address, from the Spark SDK.
  final Future<String> Function() ownSpark;

  /// Sends the leg (quote, [stepUp], payment). [onSending] runs right
  /// before the payment call.
  final BitcoinLegSend send;

  /// A watcher for a leg whose sats left at [since].
  final DollarsLandingWatcher Function({required DateTime since}) watcher;
  final double Function() dollarsNow;
  final Future<double?> Function() freshDollars;

  /// The wallet's own deposit on a venue, read fresh (the Predictions
  /// deposit wallet, the Investing account), or null. Null: no direct leg.
  final Future<String?> Function(OneBalanceVenue venue)? ownVenue;

  /// Decides direct or via Dollars ([planDirectBitcoinLeg] on the live
  /// estimates). Null: always via Dollars.
  final Future<DirectBitcoinPlan> Function({
    required OneBalanceVenue venue,
    required double fundUsd,
    required double addUsd,
    required double dollarsUsd,
    required BitcoinLegPlan via,
    required String ownVenue,
    required int directMaxSats,
  })? planDirect;

  /// Sends the direct leg ([BitcoinToVenueLeg.live]).
  final DirectLegSend? sendDirect;

  /// An Orchestra leg's status, lowercase ([orchestraLegStatus]).
  final Future<String?> Function(String id)? legStatus;
  final Duration legPollEvery;

  /// The venue's readiness phases for the queued order, as they happen
  /// (`waiting`, `converting`, `approving`, `confirming`, `crediting`,
  /// `ready`). Null: the readiness steps follow the placement alone.
  final Stream<String> Function(OneBalanceVenue venue)? readiness;

  /// Asks the Dollars reading to catch up with the wallet now (a leg's
  /// dollars were delivered: `usdBalanceCheckProvider`). Never awaited.
  final void Function()? checkDollars;

  /// A leg's Orchestra status just said it ended (delivered or failed):
  /// [into] is the venue it delivered to, null when it delivered to
  /// Dollars or failed (its money comes home). The balances it moved are
  /// read again now instead of on the next background pass
  /// ([announceLegEnded]). Never awaited.
  final void Function(OneBalanceVenue? into)? legEnded;

  /// The live wallet.
  factory BitcoinLegEnv.live(Ref ref) {
    double dollarsNow() {
      try {
        return ref.read(usdBalanceProvider);
      } catch (_) {
        return 0;
      }
    }

    Future<double?> freshDollars() async {
      try {
        final wrapper = await ref
            .read(breezSDKProvider.future)
            .timeout(const Duration(seconds: 3));
        final sdk = wrapper.instance;
        if (sdk == null) return null;
        final info = await sdk
            .getInfo(request: const GetInfoRequest())
            .timeout(const Duration(seconds: 3));
        return usdDollarsFromNodeInfo(info);
      } catch (_) {
        return null;
      }
    }

    Stream<double> dollarsStream() {
      ProviderSubscription<double>? sub;
      late final StreamController<double> controller;
      controller = StreamController<double>(
        onListen: () {
          sub = ref.listen<double>(usdBalanceProvider, (_, next) {
            if (!controller.isClosed) controller.add(next);
          });
        },
        onCancel: () => sub?.close(),
      );
      return controller.stream;
    }

    return BitcoinLegEnv(
      ownSpark: () => ref.read(sparkSelfAddressProvider.future),
      send: ({
        required String sparkAddress,
        required BitcoinLegPlan plan,
        required SettlementStepUpHook stepUp,
        required void Function() onSending,
      }) async {
        final sent = await BitcoinToDollarsLeg.send(
          ref.read,
          appRead: ref.read,
          sparkAddress: sparkAddress,
          approxUsd: plan.targetUsd,
          usdPerBtc: plan.usdPerBtc,
          stepUp: stepUp,
          requestQuote: (key) async {
            final (_, fetched) = await BitcoinToDollarsLeg.quoteForTarget(
              ref.read,
              sats: plan.sats,
              targetUsd: plan.targetUsd,
              maxSats: plan.maxSats,
              sparkAddress: sparkAddress,
              idempotencyKey: key,
              requireFullTarget: true,
            );
            // A gross-up can hit the approval's sats cap, or the second
            // quote can move again. Never pay a quote whose output cannot
            // fund the already-approved onward move.
            final out = orchestraAmountToDouble(
                fetched.quote.quote.estimatedOut, kOrchestraUsdAssetCode,
                chain: kOrchestraUsdChain);
            if (!out.isFinite || out + 1e-6 < plan.targetUsd) {
              throw const RouteUnavailable('bitcoin_target_short');
            }
            return fetched;
          },
          onSending: onSending,
        );
        return BitcoinLegTicket(
          quoteId: sent.quoteId,
          orderId: sent.orderId,
          registration: sent.registration,
          sats: sent.sats,
          estimatedOutUsd: sent.estimatedOutUsd,
          minOutUsd: sent.minOutUsd,
        );
      },
      watcher: ({required DateTime since}) => DollarsLandingWatcher(
        statusOf: orchestraLegStatus,
        dollarsNow: dollarsNow,
        freshDollars: freshDollars,
        // The generic arrival path (ArrivalRefresher) re-reads the dollar
        // balance against its level before the sats left; asked for,
        // never waited on.
        kickSync: () => unawaited(BreezSdkSpark()
            .syncAndRefresh(asset: ArrivalAsset.dollars, since: since)),
        dollarsChanges: dollarsStream(),
      ),
      dollarsNow: dollarsNow,
      freshDollars: freshDollars,
      ownVenue: (venue) => ownVenueDeposit(ref.read, venue),
      planDirect: ({
        required OneBalanceVenue venue,
        required double fundUsd,
        required double addUsd,
        required double dollarsUsd,
        required BitcoinLegPlan via,
        required String ownVenue,
        required int directMaxSats,
      }) async {
        final funder = switch (venue) {
          OneBalanceVenue.predictions =>
            ref.read(predictionsVenueFunderProvider),
          OneBalanceVenue.investing => ref.read(hyperliquidVenueFunderProvider),
        };
        // The reviewed Investing plan already priced what its complete
        // Dollars move lands. Reuse that exact plan rather than making a
        // Bitcoin-only route depend on the Dollars endpoint answering again.
        final pending = venue == OneBalanceVenue.investing
            ? ref.read(pendingHyperliquidOrderProvider)
            : null;
        final venueTarget = pending != null &&
                (pending.fundUsd - fundUsd).abs() < 0.005 &&
                pending.arrivingUsd > 0
            ? pending.arrivingUsd
            : null;
        return planDirectBitcoinLeg(
          fundUsd: fundUsd,
          addUsd: addUsd,
          dollarsUsd: dollarsUsd,
          via: via,
          availableSats: cachedSpendingBitcoin(ref.read).sats,
          directMaxSats: directMaxSats,
          venueTargetUsd: venueTarget,
          venueArriving: (usd) async {
            try {
              final q = await funder
                  .estimate(usd)
                  .timeout(const Duration(seconds: 5));
              return q.arrivingUsd.isFinite ? q.arrivingUsd : null;
            } catch (_) {
              return null;
            }
          },
          directOutUsd: (sats) =>
              directBitcoinEstimate(venue, sats, ownVenue: ownVenue),
          directMinimumUsd: () => directBitcoinMinimumUsd(venue),
          dollarsMinimumUsd: kPredictionsMinMoveUsd,
          // Limits and both route estimates are independent reads. A cold
          // limits endpoint must not consume the entire direct-plan budget
          // before any direct estimate is even dispatched.
          readDollarsMinimumUsd: () async {
            try {
              return await funder
                  .minimumUsd()
                  .timeout(const Duration(seconds: 3));
            } catch (_) {
              return kPredictionsMinMoveUsd;
            }
          },
        );
      },
      sendDirect: BitcoinToVenueLeg.live(ref.read),
      legStatus: orchestraLegStatus,
      readiness: (venue) => venueReadinessPhases(ref, venue),
      checkDollars: () => ref.read(usdBalanceCheckProvider).request('order_leg'),
      legEnded: (into) => announceLegEnded(ref.read, into),
    );
  }
}

/// A leg's Orchestra status just said it ended (the order runner polls it
/// every second): everything that shows the money it moved reads again
/// now. Without this the swap order row (Activity, the Investments
/// header's in-flight lines and total, the Spark arrival refresh, the
/// Predictions deposit's conversion) waited for the background sync's
/// next pass to read the same status, and Investing's queued order for
/// its account poll (4 to 5 s) to see the credit.
///
///  * The row's owner, the background sync, reads the rows now (one
///    sync, shared with one already running: `BackgroundSyncService
///    .syncNow`).
///  * Delivered into Investing: the account is read again now and the
///    queued order fires on it (`PendingHlOrderAutoFire.creditLanded`).
///
/// Never throws.
void announceLegEnded(T Function<T>(ProviderListenable<T> provider) read,
    OneBalanceVenue? into) {
  try {
    BackgroundSyncService().syncNow();
  } catch (_) {}
  if (into == OneBalanceVenue.investing) {
    try {
      read(pendingHlOrderAutoFireProvider).creditLanded();
    } catch (_) {}
  }
}

/// The wallet's own deposit on [venue], as the venue's own Dollars move
/// resolves it: the Predictions deposit wallet (the live account, else
/// asked for), the Investing account. Null when it cannot be read.
Future<String?> ownVenueDeposit(
    T Function<T>(ProviderListenable<T> provider) read,
    OneBalanceVenue venue) async {
  try {
    switch (venue) {
      case OneBalanceVenue.predictions:
        final live = read(polymarketTradingProvider).valueOrNull;
        final address = live?.proxyWalletAddress;
        if (address != null && address.isNotEmpty) return address;
        final asked = await read(polymarketTradingProvider.notifier)
            .depositAddress()
            .timeout(const Duration(seconds: 8));
        return asked == null || asked.isEmpty ? null : asked;
      case OneBalanceVenue.investing:
        final address = await read(hyperliquidAddressProvider.future)
            .timeout(const Duration(seconds: 8));
        return address == null || address.isEmpty ? null : address;
    }
  } catch (_) {
    return null;
  }
}

/// The Bitcoin leg the one approval binds for an order on [venue]: the
/// via-Dollars leg to the wallet's own Spark address ([ownSpark]) and,
/// when the own venue deposit can be read, the direct leg to exactly that
/// deposit (`BitcoinLegGrants.limitWithDirect`). Reads only.
Future<Map<String, Object?>> bitcoinLegLimitFor(
  T Function<T>(ProviderListenable<T> provider) read, {
  required OneBalanceVenue venue,
  required BitcoinLegPlan leg,
  required String ownSpark,
}) async {
  final ownVenue = await ownVenueDepositFor(read, venue);
  return BitcoinLegGrants.limitWithDirect(
    maxSats: leg.maxSats,
    ownSpark: ownSpark,
    venue: venue.name,
    ownVenue: ownVenue,
    directMaxSats: directMaxSatsFor(leg),
  );
}

/// Test seam for the own-deposit read the approval pins
/// ([ownVenueDepositFor]).
@visibleForTesting
Future<String?> Function(OneBalanceVenue venue)? debugOwnVenueDeposit;

/// [ownVenueDeposit], or the test's stand-in.
Future<String?> ownVenueDepositFor(
    T Function<T>(ProviderListenable<T> provider) read, OneBalanceVenue venue) {
  final seam = debugOwnVenueDeposit;
  return seam != null ? seam(venue) : ownVenueDeposit(read, venue);
}

/// What the readiness steps follow: the queued order's readiness phase on
/// [venue] as the autofire reports it (`PendingBetIntent.readiness`,
/// `PendingHlOrderIntent.readiness`). Filled in by `venue_readiness.dart`.
Stream<String> venueReadinessPhases(Ref ref, OneBalanceVenue venue) =>
    readinessPhasesOf(ref, venue);

/// The wallet behind the runner. Overridden in tests.
final bitcoinLegEnvProvider =
    Provider<BitcoinLegEnv>((ref) => BitcoinLegEnv.live(ref));

/// How a Bitcoin-funded order ended.
enum BitcoinFundedEnd {
  /// The order was placed.
  placed,

  /// The venue did not place it (price moved, refused, the credit never
  /// came): the money stays in Investments, the slip shows the venue's
  /// own message and retry.
  placementFailed,

  /// Stopped with the money in Dollars (the venue move was refused, the
  /// dollars took too long): "Tap to place".
  ready,

  /// Orchestra failed the Bitcoin leg: the bitcoin goes back home.
  refunded,

  /// Refused before any sats left. Nothing moved.
  notSent,

  /// The payment's outcome is unknown: the reconciler resolves it.
  maybeSent,
}

/// How the venue's autofire ended for the order.
typedef BitcoinPlacementWait = Future<bool> Function(
    {required void Function() onCredited});

/// What the runner tells the venue move about the legs running next to
/// it. With a direct Bitcoin leg, Dollars send [bitcoinShareUsd] less and
/// the order waits for [bitcoinArrivingUsd] more in the venue; with the
/// chain both are zero (the Bitcoin's dollars are in Dollars by then).
@immutable
class FundingLegContext {
  const FundingLegContext({
    this.bitcoinShareUsd = 0,
    this.bitcoinArrivingUsd = 0,
    this.bitcoinSentAt,
    this.bitcoinLandedAt,
    this.onPulled,
  });

  /// Of the move into the venue (the slip's `fundUsd`), what the direct
  /// Bitcoin leg brings instead.
  final double bitcoinShareUsd;

  /// What the direct Bitcoin leg lands in the venue.
  final double bitcoinArrivingUsd;

  /// When the Bitcoin leg's sats left, and (the chain) when its dollars
  /// landed: the funnel's stage timings.
  final DateTime? bitcoinSentAt;
  final DateTime? bitcoinLandedAt;

  /// The other venue's legs, once they went: each source's step follows
  /// its own leg.
  final void Function(VenueCashPullOutcome pulled)? onPulled;
}

/// The venue move and the queued order: [controller] reads the Dollars
/// balance, [legs] says what the other legs bring. The slip's own funded
/// path, minus its prompt.
typedef FundVenue = Future<OrderFundingOutcome> Function(
    OrderFundingController controller, FundingLegContext legs);

/// What a slip hands the runner once the person approved.
class BitcoinFundedOrderRequest {
  BitcoinFundedOrderRequest({
    required this.venue,
    required this.grant,
    required this.plan,
    required this.label,
    required this.fundUsd,
    required this.readyUsd,
    required this.fundVenue,
    required this.dropOrder,
    this.entrySource,
    this.awaitPlacement,
    this.otherVenueUsed = false,
    this.bindAttempt,
    this.isCurrentAttempt,
  });

  final OneBalanceVenue venue;

  /// Whether the other venue's cash brings part of the move (only what
  /// Dollars and the Bitcoin leg cannot: [decideOrderSources]).
  final bool otherVenueUsed;

  /// The order's one approval (its autofire grant), binding the order,
  /// the funding move and the Bitcoin leg.
  final AuthGrant grant;
  final BitcoinLegPlan plan;
  final FundedOrderLabel label;

  /// The approved Dollars → venue move.
  final double fundUsd;

  /// The venue's ready cash when the order was approved.
  final double readyUsd;
  final String? entrySource;

  /// The venue move and the queued order ([FundVenue]): with a direct
  /// Bitcoin leg it starts the moment that leg's quote is accepted, for
  /// the Dollars' and the other venue's shares; with the chain once the
  /// Bitcoin's dollars landed, for the whole move.
  final FundVenue fundVenue;

  /// Drops the queued order and cancels its approval: nothing will be
  /// placed for it.
  final void Function() dropOrder;

  /// The step after the venue move, in place of the venue's own placement
  /// watch: the margin sheet signs its margin change here once the credit
  /// lands (`MarginFundingRunner`); tests stand in for it too. Null
  /// follows the venue's autofire, which places the slip's queued order.
  final BitcoinPlacementWait? awaitPlacement;

  /// Synchronously binds this graph to the approved live attempt before
  /// any funding starts. False means that attempt was replaced meanwhile.
  final bool Function(String runId)? bindAttempt;
  final bool Function()? isCurrentAttempt;
}

/// A run the slip follows: its record and its end.
class BitcoinFundedRun {
  const BitcoinFundedRun(this.id, this.ended, {this.error});
  final String id;
  final Future<BitcoinFundedEnd> ended;
  final Object? error;
}

/// The chain. See the file header.
class BitcoinFundedOrderRunner {
  BitcoinFundedOrderRunner(this._ref);

  final Ref _ref;

  /// Test seam: the clock the stage timings use.
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  /// The error the last refused leg threw, by record, for the slip's copy.
  final Map<String, Object> _errors = {};

  /// [_errors]' entry for [recordId], for a chain outside this file
  /// (venue_cash_funded_order.dart).
  void recordError(String recordId, Object e) => _errors[recordId] = e;

  /// The venue's own placement of the queued order, followed (see
  /// [_placementWait]), for a chain outside this file.
  BitcoinPlacementWait placementWaitFor(OneBalanceVenue venue,
          {void Function(String? message, String? code)? onFailed,
          String? fundedRunId}) =>
      _placementWait(venue, onFailed: onFailed, fundedRunId: fundedRunId);

  /// The words for a leg refused before anything left, if any.
  String? errorTextFor(Object e) => _errorText(e);

  /// What stopped [recordId]'s leg before anything moved, if anything.
  Object? errorOf(String recordId) => _errors[recordId];

  /// Starts the chain for [r] and returns at once: the record is written
  /// now, the chain runs on whatever happens to the slip.
  /// The slip's Add tap, past its validation and sizing: [approve] asks
  /// for the ONE approval (the order with its funding and Bitcoin legs);
  /// only a grant starts the chain ([build] turns it into the request).
  /// Declined, nothing is quoted, sent or funded, and nothing recorded.
  Future<BitcoinFundedRun?> startApproved({
    required Future<AuthGrant?> Function() approve,
    required BitcoinFundedOrderRequest? Function(AuthGrant grant) build,
  }) async {
    final grant = await approve();
    if (grant == null) return null;
    final request = build(grant);
    if (request == null || request.isCurrentAttempt?.call() == false) {
      grant.revoke();
      return null;
    }
    return start(request);
  }

  BitcoinFundedRun start(BitcoinFundedOrderRequest r) {
    if (r.isCurrentAttempt?.call() == false) {
      r.grant.revoke();
      return BitcoinFundedRun('', Future.value(BitcoinFundedEnd.notSent));
    }
    final orders = _ref.read(fundedOrdersProvider.notifier);
    final id = orders.start(r.label,
        stage: FundedOrderStage.adding, addUsd: r.plan.targetUsd);
    if (r.bindAttempt?.call(id) == false) {
      r.grant.revoke();
      orders.remove(id);
      return BitcoinFundedRun(id, Future.value(BitcoinFundedEnd.notSent));
    }
    return BitcoinFundedRun(id, _run(id, r));
  }

  Future<BitcoinFundedEnd> _run(String id, BitcoinFundedOrderRequest r) =>
      _FundedChain(this, id, r).run();

  /// An order funded from Dollars alone (no Bitcoin leg): its move left
  /// Dollars as [move]. Recorded so the Investments header names the
  /// order instead of the move, and followed to its end. Never throws.
  void followDollarsFunded(FundedOrderLabel label, VenueMoveResult move) =>
      followFunded(beginFunded(label), move: move);

  /// An order funded from Dollars or the other venue's cash, recorded the
  /// moment the person approved it ("Getting your prediction ready"), so
  /// the slip shows its steps from the first second and the Investments
  /// header names it while its money moves. Returns the record's id.
  String beginFunded(FundedOrderLabel label) => _ref
      .read(fundedOrdersProvider.notifier)
      .start(label, stage: FundedOrderStage.preparing);

  /// [id]'s money left for the venue as [move] (null: nothing had to
  /// move, or what moved is in [rowIds]): its rows name the order, and
  /// the venue's autofire is followed to the end (placing on the credit,
  /// then placed or stopped with the venue's own words). Never throws.
  void followFunded(String id,
      {VenueMoveResult? move, Set<String> rowIds = const {}}) {
    try {
      final orders = _ref.read(fundedOrdersProvider.notifier);
      final record = orders.byId(id);
      if (record == null || !record.stage.active) return;
      for (final row in {
        ...rowIds,
        if (move != null) move.quoteId,
        if (move?.orderId case final orderId?) orderId,
      }) {
        orders.addVenueRow(id, row);
      }
      final reg = move?.registration;
      if (reg != null) {
        unawaited(reg.then((orderId) {
          if (orderId != null && orderId.isNotEmpty) {
            orders.addVenueRow(id, orderId);
          }
        }).catchError((Object _) {}));
      }
      String? failedText;
      String? failedCode;
      final venue = record.label.venue;
      final credited = Completer<void>();
      final placement =
          _placementWait(venue, fundedRunId: id, onFailed: (message, code) {
        failedText = message;
        failedCode = code;
      })(onCredited: () {
        if (!credited.isCompleted) credited.complete();
        orders.setStage(id, FundedOrderStage.placing);
      }).catchError((Object _) => false);
      unawaited(placement.then((placed) {
        if (placed) {
          orders.setStage(id, FundedOrderStage.done);
          return;
        }
        orders.stop(id,
            stage: FundedOrderStage.failed,
            reason: failedCode ?? 'placement',
            moneyAt: FundedMoneyAt.venue,
            message: failedText);
      }));
      // The same step graph as an order funded from Bitcoin: the Dollars
      // leg (when one left) landing on its own, the venue's readiness, the
      // order. Legs a stopped earlier try already landed stay done.
      final env = _ref.read(bitcoinLegEnvProvider);
      var legId = move == null ? null : (move.orderId ?? move.quoteId);
      if (reg != null) {
        unawaited(reg.then((orderId) {
          if (orderId != null && orderId.isNotEmpty) legId = orderId;
        }).catchError((Object _) {}));
      }
      final graph = MoneyStepGraph([
        for (final s in record.steps.steps)
          if (s.id.startsWith('prev:')) s,
        ...fundedOrderGraph(
          venue: venue,
          orderUsd: record.label.orderUsd,
          legs: [
            if (move != null)
              MoneyStep(
                  id: FundedStepId.dollars,
                  kind: MoneyStepKind.leg,
                  from: MoneyPlace.dollars,
                  usd: (move.sentUsd * 100).roundToDouble() / 100,
                  ref: legId),
          ],
        ).steps,
      ]);
      orders.setSteps(id, graph);
      final statusOf = env.legStatus;
      unawaited(MoneyStepRunner(
        graph: graph,
        onChange: (g) => orders.setSteps(id, g),
        clock: clock,
        actionFor: (step) => switch (step.id) {
          FundedStepId.dollars => (s, update) async {
              final LegDelivery d;
              if (statusOf == null || legId == null) {
                d = await Future.any<LegDelivery>([
                  credited.future.then((_) => LegDelivery.delivered),
                  placement.then(
                      (p) => p ? LegDelivery.delivered : LegDelivery.timedOut),
                ]);
              } else {
                d = await watchLegDelivery(
                    id: () => legId!,
                    statusOf: statusOf,
                    pollEvery: env.legPollEvery);
                if (d != LegDelivery.timedOut) {
                  try {
                    env.legEnded
                        ?.call(d == LegDelivery.delivered ? venue : null);
                  } catch (_) {}
                }
              }
              return switch (d) {
                LegDelivery.delivered => MoneyStepDone(ref: legId),
                LegDelivery.failed => const MoneyStepFailed('refunded'),
                LegDelivery.timedOut => const MoneyStepFailed('timeout'),
              };
            },
          FundedStepId.convert => (s, update) => readinessPhaseStep(
              'converting', update,
              optional: true,
              phases: env.readiness?.call(venue),
              credited: credited.future,
              placement: placement,
              failedCode: () => failedCode),
          FundedStepId.approve => (s, update) => readinessPhaseStep(
              'approving', update,
              optional: true,
              phases: env.readiness?.call(venue),
              credited: credited.future,
              placement: placement,
              failedCode: () => failedCode),
          FundedStepId.confirm || FundedStepId.credit => (s, update) =>
              readinessPhaseStep(
                  step.id == FundedStepId.confirm ? 'confirming' : 'crediting',
                  update,
                  phases: env.readiness?.call(venue),
                  credited: credited.future,
                  placement: placement,
                  failedCode: () => failedCode),
          FundedStepId.place => (s, update) async => await placement
              ? const MoneyStepDone()
              : MoneyStepFailed(failedCode ?? 'placement'),
          _ => null,
        },
      ).run());
    } catch (_) {}
  }

  /// [id] stopped before its order could go, with the money at [moneyAt]
  /// ([message]: what the rail said). Never throws.
  void stopFunded(String id,
      {required String reason,
      FundedMoneyAt moneyAt = FundedMoneyAt.investments,
      String? message}) {
    try {
      _ref.read(fundedOrdersProvider.notifier).stop(id,
          stage: FundedOrderStage.failed,
          reason: reason,
          moneyAt: moneyAt,
          message: message);
    } catch (_) {}
  }

  /// Nothing happened for [id] after all (the approval went, or the
  /// button turns into the Add door): it is forgotten. Never throws.
  void dropFunded(String id) {
    try {
      _ref.read(fundedOrdersProvider.notifier).remove(id);
    } catch (_) {}
  }

  AppLocalizations _l10n() =>
      l10nForLanguage(_ref.read(settingsProvider).language);

  /// The words for a leg that was refused before anything left.
  String? _errorText(Object e) {
    try {
      return HotSettlement.messageFor(e, _l10n());
    } catch (_) {
      return null;
    }
  }

  /// Follows the venue's queued order to its end: placing is the credit,
  /// done (or awaiting the venue's confirmation) is placed, failed or
  /// cleared before either is not. [onFailed] hears the venue's own words
  /// and code when it failed.
  BitcoinPlacementWait _placementWait(OneBalanceVenue venue,
          {void Function(String? message, String? code)? onFailed,
          String? fundedRunId}) =>
      ({required void Function() onCredited}) {
        final done = Completer<bool>();
        void end(bool placed) {
          if (!done.isCompleted) done.complete(placed);
        }

        late final ProviderSubscription<void> sub;
        switch (venue) {
          case OneBalanceVenue.investing:
            sub = _ref.listen<PendingHlOrderIntent?>(
                pendingHyperliquidOrderProvider, (_, next) {
              if (next == null) return end(false);
              switch (next.status) {
                case PendingHlOrderStatus.placing:
                  if (next.readiness != HlReadiness.crediting) onCredited();
                case PendingHlOrderStatus.done:
                  end(true);
                case PendingHlOrderStatus.failed:
                  final message = next.errorMessage;
                  onFailed?.call(
                      message,
                      message != null && message == _l10n().hlFundsTimeout
                          ? 'funds_timeout'
                          : null);
                  end(false);
                case PendingHlOrderStatus.awaitingDeposit:
                case PendingHlOrderStatus.awaitingBalance:
                  break;
              }
            }, fireImmediately: true);
          case OneBalanceVenue.predictions:
            sub = _ref.listen<PendingBetIntent?>(pendingPolymarketBetProvider,
                (_, next) {
              if (next == null) return end(false);
              if (fundedRunId != null &&
                  next.fundedRunId != null &&
                  next.fundedRunId != fundedRunId) {
                return end(false);
              }
              switch (next.status) {
                case PendingBetStatus.placing:
                  if (next.readiness == null ||
                      next.readiness == PredictionsReadiness.ready) {
                    onCredited();
                  }
                case PendingBetStatus.done:
                case PendingBetStatus.awaitingConfirmation:
                  end(true);
                case PendingBetStatus.failed:
                  onFailed?.call(
                      next.errorMessage,
                      next.failureCode ??
                          (next.retryMaxPrice != null ? 'price_moved' : null));
                  end(false);
                case PendingBetStatus.awaitingDeposit:
                case PendingBetStatus.converting:
                case PendingBetStatus.awaitingBalance:
                  break;
              }
            }, fireImmediately: true);
        }
        return done.future.whenComplete(sub.close);
      };
}

final bitcoinFundedOrderRunnerProvider =
    Provider<BitcoinFundedOrderRunner>((ref) => BitcoinFundedOrderRunner(ref));

// ── Sizing from the wallet ─────────────────────────────────────────────

/// Test seam: stands in for the route's estimate of a Bitcoin leg.
@visibleForTesting
Future<double?> Function(int sats)? debugBitcoinLegEstimate;

/// Test seam: stands in for the fresh read of the spending wallet's
/// bitcoin (the SDK's `getInfo`) and the bitcoin price (a rates refresh).
/// Null from it means nothing could be read.
@visibleForTesting
Future<SpendingBitcoin?> Function()? debugFreshSpendingBitcoin;

/// The spending wallet's Spark bitcoin, in sats, and the app's bitcoin
/// price in dollars. A read, never sent anywhere.
typedef SpendingBitcoin = ({int sats, double usdPerBtc});

/// A bitcoin price a leg can be sized on. The rates read before their BTC
/// entry is known value 1 BTC at about $1 (`CurrencyState.convert`),
/// which is no price at all.
bool isUsableUsdPerBtc(double usdPerBtc) =>
    usdPerBtc.isFinite && usdPerBtc > 1000 && usdPerBtc < 10000000;

/// The spending wallet's bitcoin and price as the app holds them now (the
/// balance cache, send holds applied; the rates). Zero when unknown.
SpendingBitcoin cachedSpendingBitcoin(
    T Function<T>(ProviderListenable<T> provider) read) {
  var rate = 0.0;
  var sats = 0;
  try {
    rate = read(selectedCurrencyProvider('USD')).toDouble();
  } catch (_) {}
  try {
    final spending = pickSpendingWallet(read(settingsProvider));
    sats = spending == null
        ? 0
        : read(walletBalanceCacheProvider)[spending.id]?.sparkBitcoinbalance ??
            0;
  } catch (_) {}
  return (sats: sats, usdPerBtc: isUsableUsdPerBtc(rate) ? rate : 0.0);
}

/// The spending wallet's bitcoin read fresh, for a tap whose cached
/// figures do not cover the leg (the balance not synced yet on a cold
/// start, the price not loaded): the SDK's own `getInfo`, written through
/// the balance cache so its send holds still apply, and a rates refresh
/// when there is no usable price. Null when there is no spending wallet.
/// Never throws.
Future<SpendingBitcoin?> freshSpendingBitcoin(
    T Function<T>(ProviderListenable<T> provider) read) async {
  final seam = debugFreshSpendingBitcoin;
  if (seam != null) return seam();
  String? walletId;
  try {
    walletId = pickSpendingWallet(read(settingsProvider))?.id;
  } catch (_) {}
  if (walletId == null || walletId.isEmpty) return null;
  final spendingId = walletId;
  final cached = cachedSpendingBitcoin(read);
  Future<void> refreshPrice() async {
    try {
      await read(currencyProvider.notifier)
          .updateRates()
          .timeout(const Duration(seconds: 6));
    } catch (_) {}
  }

  Future<void> refreshSats() async {
    try {
      final wrapper = await read(breezSDKProvider.future)
          .timeout(const Duration(seconds: 8));
      final sdk = wrapper.instance;
      if (sdk == null) return;
      final info = await sdk
          .getInfo(request: const GetInfoRequest())
          .timeout(const Duration(seconds: 4));
      // Only the wallet that was asked about.
      if (pickSpendingWallet(read(settingsProvider))?.id != spendingId) return;
      if (!identical(wrapper.instance, sdk)) return;
      read(walletBalanceCacheProvider.notifier)
          .updateSparkBitcoinbalance(spendingId, info.balanceSats.toInt());
    } catch (_) {}
  }

  await Future.wait<void>([
    if (!isUsableUsdPerBtc(cached.usdPerBtc)) refreshPrice(),
    refreshSats(),
  ]);
  return cachedSpendingBitcoin(read);
}

/// The route's estimate of what [sats] of spending bitcoin land in
/// Dollars, or null when it does not answer within a few seconds.
Future<double?> _bitcoinLegEstimate(int sats) async {
  try {
    final seam = debugBitcoinLegEstimate;
    if (seam != null) return await seam(sats);
    final result = await OrchestraService.getEstimate(
      sourceChain: 'spark',
      sourceAsset: 'BTC',
      destinationChain: kOrchestraUsdChain,
      destinationAsset: kOrchestraUsdAssetCode,
      amount: sats.toString(),
    ).timeout(const Duration(seconds: 4));
    final OrchestraEstimate? est = result.data;
    if (est == null) return null;
    return orchestraAmountToDouble(est.estimatedOut, kOrchestraUsdAssetCode,
        chain: kOrchestraUsdChain);
  } catch (_) {
    return null;
  }
}

/// The leg [dollarsShortUsd] needs from [wallet]: sized on the route's own
/// estimate for that leg (its real spread, with the arrival buffer), or on
/// [BitcoinLegRules.fallbackSpread] only when the estimate does not
/// answer. The estimate is asked whether or not the fallback would fit,
/// so bitcoin that covers the leg at the route's real price is never
/// refused for a margin.
Future<BitcoinLegSizing> _sizeOn(
    SpendingBitcoin wallet, double dollarsShortUsd) async {
  if (wallet.sats <= 0) {
    return const BitcoinLegSizing.refused(
        BitcoinLegRefusal.insufficientBitcoin);
  }
  final rate = wallet.usdPerBtc;
  if (!isUsableUsdPerBtc(rate)) {
    return const BitcoinLegSizing.refused(BitcoinLegRefusal.noPrice);
  }
  final target = BitcoinLegRules.targetUsd(dollarsShortUsd);
  if (target <= 0) {
    return const BitcoinLegSizing.refused(
        BitcoinLegRefusal.insufficientBitcoin);
  }
  // Asked at what the fallback would send: an estimate is a read and
  // never needs the sats to be there.
  final probe = BitcoinLegRules.probeSats(target, usdPerBtc: rate);
  final estimatedOut = await _bitcoinLegEstimate(probe);
  return BitcoinLegRules.size(
    dollarsShortUsd: dollarsShortUsd,
    usdPerBtc: rate,
    availableSats: wallet.sats,
    estimate:
        estimatedOut == null || !estimatedOut.isFinite || estimatedOut <= 0
            ? null
            : (sats: probe, estimatedOutUsd: estimatedOut),
  );
}

/// The spending wallet's bitcoin and price, and the leg [dollarsShortUsd]
/// needs, sized on the route's own estimate when it answers within a few
/// seconds. Read fresh before choosing a source: a newly spent or empty
/// wallet must override a larger cached balance. A failed read retains
/// the last known figure; the verified send still checks actual funds.
/// A read: nothing is quoted or moved.
Future<BitcoinLegSizing> sizeBitcoinLegFor(
  T Function<T>(ProviderListenable<T> provider) read, {
  required double dollarsShortUsd,
}) async {
  final cached = cachedSpendingBitcoin(read);
  final fresh = await freshSpendingBitcoin(read);
  return _sizeOn(fresh ?? cached, dollarsShortUsd);
}

// ── The slip's decision ────────────────────────────────────────────────

/// Where a hot slip's tap goes when the whole Investments balance lacks X
/// for the order's move. One decision for the Predictions and the
/// Investing slip ([decideSlipFunding]).
enum SlipFundingRoute {
  /// The spending bitcoin covers X: one approval, then Bitcoin → Dollars →
  /// venue → order ([BitcoinFundedOrderRunner]).
  bitcoin,

  /// The bitcoin genuinely does not cover X (none, or too little once the
  /// route's spread is counted): money has to come from outside, so the
  /// slip opens the Investments Receive sheet, never the Bitcoin Move
  /// sheet.
  insufficient,

  /// Nothing could tell (no bitcoin price, even read fresh): no sheet
  /// opens and nothing moves; the slip says it did not go through.
  unavailable,
}

/// [SlipFundingRoute] for an X of [addUsd], with the sized leg when the
/// bitcoin covers it.
@immutable
class SlipFundingDecision {
  const SlipFundingDecision.bitcoin(BitcoinLegPlan this.plan, this.addUsd)
      : route = SlipFundingRoute.bitcoin;
  const SlipFundingDecision.insufficient(this.addUsd)
      : route = SlipFundingRoute.insufficient,
        plan = null;
  const SlipFundingDecision.unavailable(this.addUsd)
      : route = SlipFundingRoute.unavailable,
        plan = null;

  final SlipFundingRoute route;

  /// X: what the order's move lacks, exactly as the button names it.
  final double addUsd;

  /// The Bitcoin leg for X ([SlipFundingRoute.bitcoin] only).
  final BitcoinLegPlan? plan;

  @override
  String toString() => 'SlipFundingDecision(${route.name}, $addUsd)';
}

/// Test seam: stands in for the chain a slip's "Add" starts once
/// [decideSlipFunding] says bitcoin (the slip's confirm, its one approval
/// and the runner).
@visibleForTesting
Future<void> Function(OneBalanceVenue venue, SlipFundingDecision decision)?
    debugStartSlipBitcoinChain;

/// Runs [debugStartSlipBitcoinChain] instead of the slip's chain when a
/// test set it; true when it did. Always false in the app.
Future<bool> slipBitcoinChainStoodIn(
    OneBalanceVenue venue, SlipFundingDecision decision) async {
  final seam = debugStartSlipBitcoinChain;
  if (seam == null) return false;
  await seam(venue, decision);
  return true;
}

/// Both slips' one decision for an X of [addUsd]: the Bitcoin leg sized on
/// the spending wallet's bitcoin, read fresh when the app's figures do not
/// cover it yet ([sizeBitcoinLegFor]). Bitcoin whenever it covers X;
/// insufficient only when it genuinely does not; unavailable when no
/// price could be read. Never throws, never moves anything.
Future<SlipFundingDecision> decideSlipFunding(
  T Function<T>(ProviderListenable<T> provider) read, {
  required double addUsd,
}) async {
  if (!addUsd.isFinite || addUsd <= 0) {
    return SlipFundingDecision.insufficient(addUsd.isFinite ? addUsd : 0);
  }
  BitcoinLegSizing sizing;
  try {
    sizing = await sizeBitcoinLegFor(read, dollarsShortUsd: addUsd);
  } catch (_) {
    return SlipFundingDecision.unavailable(addUsd);
  }
  final plan = sizing.plan;
  if (plan != null) return SlipFundingDecision.bitcoin(plan, addUsd);
  return sizing.refusal == BitcoinLegRefusal.noPrice
      ? SlipFundingDecision.unavailable(addUsd)
      : SlipFundingDecision.insufficient(addUsd);
}

// ── The order of sources ────────────────────────────────────────────────

/// Where a funded order's move comes from once Dollars fall short
/// ([decideOrderSources]).
enum OrderSourceRoute {
  /// Dollars cover the move.
  dollars,

  /// Dollars and a Bitcoin leg, and the other venue's cash only for what
  /// they cannot cover ([OrderSources.otherVenueUsd]).
  bitcoin,

  /// No Bitcoin leg can help (none, under the route's minimum, or no
  /// price): Dollars and the other venue's cash cover it.
  otherVenue,

  /// Investments and Bitcoin together are short: money from outside
  /// ([OrderSources.missingUsd], what Investments lack).
  insufficient,

  /// No bitcoin price could be read and the rest of Investments is short:
  /// nothing moves.
  unavailable,

  /// The "Add $X" tap's X no longer covers what Investments lack.
  addChanged,
}

/// [decideOrderSources]' answer.
@immutable
class OrderSources {
  const OrderSources(
    this.route, {
    this.bitcoinUsd = 0,
    this.otherVenueUsd = 0,
    this.missingUsd = 0,
    this.plan,
  });

  final OrderSourceRoute route;

  /// What the Bitcoin leg lands ([OrderSourceRoute.bitcoin]): the X the
  /// chain converts.
  final double bitcoinUsd;

  /// What the other venue's cash gives (0: not used).
  final double otherVenueUsd;

  /// What Investments lack as a whole (insufficient, addChanged).
  final double missingUsd;

  /// The sized Bitcoin leg ([OrderSourceRoute.bitcoin]).
  final BitcoinLegPlan? plan;

  bool get otherVenueUsed => otherVenueUsd > 0;

  @override
  String toString() => 'OrderSources(${route.name}, bitcoin: $bitcoinUsd, '
      'other: $otherVenueUsd, missing: $missingUsd)';
}

/// The most a Bitcoin leg from [wallet] lands, in dollars: its sats at the
/// price less the route's assumed spread and the arrival buffer, to the
/// cent below. Zero without bitcoin or a usable price.
double bitcoinMaxLandingUsd(SpendingBitcoin wallet) {
  if (wallet.sats <= 0 || !isUsableUsdPerBtc(wallet.usdPerBtc)) return 0;
  final usd = wallet.sats /
      1e8 *
      wallet.usdPerBtc *
      (1 - BitcoinLegRules.fallbackSpread) /
      kArrivalTargetBuffer;
  return usd.isFinite && usd > 0 ? (usd * 100).floorToDouble() / 100 : 0;
}

/// Every funded order's sources once Dollars ([dollarsUsd]) fall short of
/// the move ([fundUsd]), in the founder's order ([planOrderSources]):
/// Dollars, then Bitcoin, and the other venue's cash ([otherVenueUsd])
/// only for what those two cannot cover. The Bitcoin leg is sized on the
/// wallet's own figures (read fresh when the app's do not cover it). An
/// "Add $X" tap passes the X it showed ([shownAddUsd]: what Investments
/// lacked) and the leg it sized for it ([sized]), reused when the leg is
/// the same. [investmentsCover]: the slip's own word on whether Dollars
/// and the other venue's cash cover the move (its funding engine's
/// buffer), else read off the figures. Never throws, never moves
/// anything.
Future<OrderSources> decideOrderSources(
  T Function<T>(ProviderListenable<T> provider) read, {
  required double fundUsd,
  required double dollarsUsd,
  required double otherVenueUsd,
  double? shownAddUsd,
  BitcoinLegPlan? sized,
  bool? investmentsCover,
}) async {
  double clean(double v) => v.isFinite && v > 0 ? v : 0;
  final fund = clean(fundUsd);
  final dollars = clean(dollarsUsd);
  final other = clean(otherVenueUsd);
  if (dollars + 1e-9 >= fund) {
    return const OrderSources(OrderSourceRoute.dollars);
  }
  // What Investments lack as a whole: the X an "Add" tap showed.
  final missing =
      BitcoinLegRules.addUsd(fundUsd: fund, investmentsUsd: dollars + other);
  if (shownAddUsd != null &&
      shownAddUsd > 0 &&
      missing > shownAddUsd + 0.005) {
    return OrderSources(OrderSourceRoute.addChanged, missingUsd: missing);
  }
  final otherCovers = investmentsCover ?? missing <= 0;

  Future<SlipFundingDecision> size(double x) async {
    final leg = sized;
    if (leg != null &&
        (leg.targetUsd - BitcoinLegRules.targetUsd(x)).abs() < 0.005) {
      return SlipFundingDecision.bitcoin(leg, x);
    }
    return decideSlipFunding(read, addUsd: x);
  }

  // Bitcoin for all Dollars lack (a rest under its minimum raised to it).
  final all = BitcoinLegRules.addUsd(fundUsd: fund, investmentsUsd: dollars);
  final first = await size(all);
  switch (first.route) {
    case SlipFundingRoute.bitcoin:
      return OrderSources(OrderSourceRoute.bitcoin,
          bitcoinUsd: all, plan: first.plan);
    case SlipFundingRoute.unavailable:
      return otherCovers
          ? OrderSources(OrderSourceRoute.otherVenue,
              otherVenueUsd: _ceilSourceCents(fund - dollars))
          : OrderSources(OrderSourceRoute.unavailable, missingUsd: missing);
    case SlipFundingRoute.insufficient:
      break;
  }
  // Bitcoin short of it: as much as it lands, the other venue the rest,
  // on the wallet's own figures.
  var wallet = cachedSpendingBitcoin(read);
  final fresh = await freshSpendingBitcoin(read);
  if (fresh != null) wallet = fresh;
  var max = bitcoinMaxLandingUsd(wallet);
  if (max > 0) {
    // The route's own price for all of it, when it answers (its real
    // spread, usually well under the assumed one).
    final out = await _bitcoinLegEstimate(wallet.sats);
    if (out != null && out.isFinite && out > 0) {
      max = ((out / kArrivalTargetBuffer) * 100 - 1e-9).floorToDouble() / 100;
    }
  }
  for (var i = 0; i < 2; i++) {
    final split = planOrderSources(
      fundUsd: fund,
      dollarsUsd: dollars,
      bitcoinMaxUsd: max,
      otherVenueUsd: other,
      bitcoinMinimumUsd: BitcoinLegRules.routeMinimumUsd,
    );
    if (!split.covers || split.bitcoinUsd <= 0) break;
    final leg = await size(split.bitcoinUsd);
    if (leg.route == SlipFundingRoute.bitcoin) {
      return OrderSources(OrderSourceRoute.bitcoin,
          bitcoinUsd: split.bitcoinUsd,
          otherVenueUsd: split.otherVenueUsd,
          plan: leg.plan);
    }
    if (leg.route == SlipFundingRoute.unavailable) break;
    // The route's own spread is wider than assumed: a little less.
    max = (split.bitcoinUsd * 0.95 * 100).floorToDouble() / 100;
  }
  if (otherCovers) {
    return OrderSources(OrderSourceRoute.otherVenue,
        otherVenueUsd: _ceilSourceCents(fund - dollars));
  }
  return OrderSources(OrderSourceRoute.insufficient, missingUsd: missing);
}

double _ceilSourceCents(double usd) =>
    ((usd * 100) - 1e-9).ceilToDouble() / 100;

/// The wallet's own Spark address for a Bitcoin leg, waited on while the
/// SDK connects (a cold start takes seconds): null only when it cannot be
/// read within [timeout]. A slip holds the provider from when its "Add"
/// shows, so the tap normally finds it ready.
Future<String?> ownSparkForBitcoinLeg(
  T Function<T>(ProviderListenable<T> provider) read, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  try {
    final address =
        await read(sparkSelfAddressProvider.future).timeout(timeout);
    return address.isEmpty ? null : address;
  } catch (_) {
    return null;
  }
}

// ── The rest of the order: the one-balance planner ─────────────────────

/// What the rest of an order funded from bitcoin takes from the other
/// venue, worked out BEFORE the one approval: the Bitcoin leg lands
/// [addUsd] in Dollars, Dollars cover what they can, and the other
/// venue's cash covers the rest of [fundUsd] (the move into [venue]). The
/// legs that can go straight into [venue] are bound into the approval
/// ([directLegs], `VenueLimit.directLegs`); the others come home to
/// Dollars under the automatic authorization. Moves nothing.
class OtherVenuePlan {
  const OtherVenuePlan({
    required this.otherUsd,
    required this.covers,
    this.directLegs,
  });

  /// What the other venue gives. Zero when Dollars and the leg cover it.
  final double otherUsd;

  /// Dollars, the Bitcoin leg and the other venue together cover the move.
  final bool covers;

  /// What the one approval binds for the legs straight into the venue.
  final Map<String, Object?>? directLegs;
}

/// The destination a move into [venue] has.
VenueCashDestination venueCashDestinationOf(OneBalanceVenue venue) =>
    switch (venue) {
      OneBalanceVenue.investing => VenueCashDestination.investing,
      OneBalanceVenue.predictions => VenueCashDestination.predictions,
    };

/// The `for` value of a move into [venue].
String venueCashForOf(OneBalanceVenue venue) => switch (venue) {
      OneBalanceVenue.investing => VenueCashFor.investing,
      OneBalanceVenue.predictions => VenueCashFor.predictions,
    };

/// See [OtherVenuePlan]. [dollarsUsd] is what Dollars hold now (before the
/// leg lands).
Future<OtherVenuePlan> planOtherVenueCash(
  VenueCashPuller puller, {
  required OneBalanceVenue venue,
  required double fundUsd,
  required double addUsd,
  required double dollarsUsd,
}) async {
  final other = fundUsd - addUsd - dollarsUsd;
  if (other <= 0.005) {
    return const OtherVenuePlan(otherUsd: 0, covers: true);
  }
  final destination = venueCashDestinationOf(venue);
  // The puller counts Dollars itself: what it is asked for is the move
  // less what the leg lands.
  final plan = await puller.plan(
    neededUsd: fundUsd - addUsd,
    exclude: venue,
    destination: destination,
  );
  return OtherVenuePlan(
    otherUsd: ((other * 100) - 1e-9).ceilToDouble() / 100,
    covers: plan.covers,
    directLegs: puller.directLegLimit(plan, destination),
  );
}

/// After the Bitcoin leg's dollars landed: the other venue's cash for the
/// rest of [fundUsd] (the one-balance puller, under the order's same
/// [grant]: legs straight into [venue] within what it binds, the others
/// home to Dollars), then [queue] the venue move from Dollars for what the
/// direct legs do not bring. When Dollars still do not cover it, nothing
/// more moves and the order is not queued: the money stays in Investments.
Future<OrderFundingOutcome> fundRestThenMove({
  required VenueCashPuller puller,
  required OneBalanceVenue venue,
  required double fundUsd,
  required double readyUsd,
  required bool needsOtherVenue,
  required AuthGrant grant,
  required Future<OrderFundingOutcome> Function({
    required double fundUsd,
    required double readyUsd,
    required double directArrivingUsd,
    String? moveId,
  }) queue,
  FundingLegContext legs = const FundingLegContext(),
}) async {
  // A direct Bitcoin leg brings its share straight into the venue: the
  // move from Dollars (and the other venue's share of it) is that much
  // smaller, and the order waits for it with the rest.
  final btcArriving =
      legs.bitcoinArrivingUsd > 0 ? legs.bitcoinArrivingUsd : 0.0;
  final fund = legs.bitcoinShareUsd > 0
      ? (((fundUsd - legs.bitcoinShareUsd) * 100).roundToDouble() / 100)
          .clamp(0.0, fundUsd)
          .toDouble()
      : fundUsd;
  if (!needsOtherVenue) {
    return queue(
        fundUsd: fund,
        readyUsd: readyUsd + btcArriving,
        directArrivingUsd: btcArriving);
  }
  VenueCashPullOutcome? pulled;
  try {
    pulled = await puller.pullShortfall(
      neededUsd: fund,
      forAction: venueCashForOf(venue),
      destination: venueCashDestinationOf(venue),
      exclude: venue,
      approval: grant,
    );
  } catch (e) {
    return OrderFundingRefused('venue_cash', error: e);
  }
  try {
    legs.onPulled?.call(pulled);
  } catch (_) {}
  if (!pulled.dollarsCover) {
    return const OrderFundingRefused('venue_cash_pending');
  }
  final direct = pulled.directArrivingUsd + pulled.alreadyDeliveredUsd;
  return queue(
    fundUsd: direct > 0 ? math.max(0.0, pulled.dollarsNeededUsd) : fund,
    readyUsd: readyUsd + direct + btcArriving,
    directArrivingUsd: pulled.directArrivingUsd + btcArriving,
    moveId: pulled.moveId,
  );
}

// ── One run: the step graph and its work ───────────────────────────────

/// Step ids of a funded order's graph.
abstract final class FundedStepId {
  static const String bitcoin = 'leg:bitcoin';
  static const String dollars = 'leg:dollars';

  /// The chain's two legs: Bitcoin → Dollars, then the whole move.
  static const String bitcoinToDollars = 'leg:bitcoin>dollars';
  static const String dollarsOnward = 'leg:dollars:onward';
  static String other(OneBalanceVenue venue) => 'leg:${venue.name}';
  static const String convert = 'ready:convert';
  static const String approve = 'ready:approve';
  static const String confirm = 'ready:confirm';
  static const String credit = 'ready:credit';
  static const String place = 'place';
}

/// The balance the other venue is, as a step's source.
MoneyPlace moneyPlaceOf(OneBalanceVenue venue) => switch (venue) {
      OneBalanceVenue.predictions => MoneyPlace.predictions,
      OneBalanceVenue.investing => MoneyPlace.investing,
    };

/// The step graph of a funded order on [venue] (see the file header):
/// [legs] first, all free to start together; the venue's readiness from
/// the first money landing (Predictions: the conversion to pUSD, the
/// spend allowance alongside the legs since it needs no money, then the
/// venue's own balance; Investing: the credit where the order draws
/// from); then the order, once readiness covers it.
MoneyStepGraph fundedOrderGraph({
  required OneBalanceVenue venue,
  required List<MoneyStep> legs,
  required double orderUsd,
}) {
  final legIds = [for (final l in legs) l.id];
  final ready = switch (venue) {
    OneBalanceVenue.predictions => [
        MoneyStep(
            id: FundedStepId.convert,
            kind: MoneyStepKind.convert,
            after: legIds,
            afterAny: true),
        const MoneyStep(id: FundedStepId.approve, kind: MoneyStepKind.approve),
        const MoneyStep(
            id: FundedStepId.confirm,
            kind: MoneyStepKind.confirm,
            after: [FundedStepId.convert, FundedStepId.approve]),
      ],
    OneBalanceVenue.investing => [
        MoneyStep(
            id: FundedStepId.credit,
            kind: MoneyStepKind.credit,
            after: legIds,
            afterAny: true),
      ],
  };
  return MoneyStepGraph([
    ...legs,
    ...ready,
    MoneyStep(
        id: FundedStepId.place,
        kind: MoneyStepKind.place,
        usd: orderUsd,
        after: [ready.last.id]),
  ]);
}

/// The readiness phases in the order the autofire walks them.
const List<String> kReadinessPhases = [
  'waiting',
  'converting',
  'approving',
  'confirming',
  'crediting',
  'ready',
];

/// One readiness phase as a step (see the file header): done once the
/// venue moved past [phase] in [phases], or credited the order, or placed
/// it; skipped when an [optional] phase was never needed; failed when the
/// order stopped (or was not placed) before it.
Future<MoneyStepOutcome> readinessPhaseStep(
  String phase,
  void Function(MoneyStep Function(MoneyStep)) update, {
  bool optional = false,
  Stream<String>? phases,
  required Future<void> credited,
  required Future<bool> placement,
  Future<void>? stopped,
  String? Function()? failedCode,
}) {
  final done = Completer<MoneyStepOutcome>();
  var seen = false;
  MoneyStepOutcome passed() =>
      seen || !optional ? const MoneyStepDone() : const MoneyStepSkipped();
  void finish(MoneyStepOutcome o) {
    if (!done.isCompleted) done.complete(o);
  }

  final at = kReadinessPhases.indexOf(phase);
  StreamSubscription<String>? sub;
  try {
    sub = phases?.listen((p) {
      final i = kReadinessPhases.indexOf(p);
      if (p == phase) {
        if (!seen) {
          seen = true;
          update((s) => s.copyWith(ref: 'seen'));
        }
      } else if (i > at) {
        finish(passed());
      }
    }, onError: (Object _) {});
  } catch (_) {}
  unawaited(credited.then((_) => finish(passed())));
  unawaited(placement.then((placed) {
    if (placed) return finish(passed());
    finish(optional && !seen
        ? const MoneyStepSkipped()
        : MoneyStepFailed(failedCode?.call() ?? 'not_ready'));
  }));
  if (stopped != null) {
    unawaited(stopped.then((_) => finish(optional && !seen
        ? const MoneyStepSkipped()
        : const MoneyStepFailed('stopped'))));
  }
  return done.future.whenComplete(() => sub?.cancel());
}

class _FundedChain {
  _FundedChain(this.runner, this.id, this.r)
      : _cashSnapshot = runner._ref.read(venueCashSnapshotProvider);

  final BitcoinFundedOrderRunner runner;
  final String id;
  final BitcoinFundedOrderRequest r;
  final VenueCashSnapshot _cashSnapshot;

  Ref get _ref => runner._ref;
  late final BitcoinLegEnv env = _ref.read(bitcoinLegEnvProvider);
  late final FundedOrdersNotifier orders =
      _ref.read(fundedOrdersProvider.notifier);
  final OrderFundingJourney journey = OrderFundingJourney.instance;
  OneBalanceVenue get venue => r.venue;
  DateTime _now() => BitcoinFundedOrderRunner.clock();

  /// Follows one leg's Orchestra order to delivery. Without a status read
  /// (a test's wallet) a leg counts as landed once the venue credited the
  /// order. [into] is the venue the leg delivers to (null: Dollars): its
  /// end is announced the moment the status says so
  /// ([BitcoinLegEnv.legEnded]).
  Future<LegDelivery> _delivery(String Function() legId,
      {void Function()? onExplicitRefund, OneBalanceVenue? into}) {
    final statusOf = env.legStatus;
    if (statusOf == null) {
      return Future.any<LegDelivery>([
        _credited.future.then((_) => LegDelivery.delivered),
        _placement.then(
            (placed) => placed ? LegDelivery.delivered : LegDelivery.timedOut),
      ]);
    }
    var refundNotified = false;
    var credited = false;
    // The venue this run funds credited the order: the money of every leg
    // into it is there, whatever Orchestra's status still says (it lags
    // the delivery by minutes at times). The leg shows landed; the row
    // keeps Orchestra's status, its journey shows the arrival.
    if (into == venue) {
      unawaited(_credited.future.then((_) => credited = true));
    }
    return watchLegDelivery(
        id: legId,
        statusOf: (id) async {
          // Ends the watch as delivered (never written anywhere).
          if (credited) return 'completed';
          final status = await statusOf(id);
          if (!refundNotified && status?.trim().toLowerCase() == 'refunded') {
            refundNotified = true;
            onExplicitRefund?.call();
          }
          if (status == null && credited) return 'completed';
          return status;
        },
        pollEvery: env.legPollEvery,
        onSlow: _slow).then((d) {
      if (credited && d == LegDelivery.delivered) _arrivalSeen(legId());
      _legEnded(d, into);
      return d;
    });
  }

  /// The venue credited the order while [legId]'s Orchestra status had not
  /// said delivered: its Activity row's journey shows the arrival
  /// ([VenueArrivals]). Only the run's one leg into the venue: with
  /// several, the credit does not say whose money it was.
  void _arrivalSeen(String legId) {
    final legsIn = orders.byId(id)?.steps.legs.length ?? 0;
    if (legsIn > 1) return;
    try {
      final rows = _ref.read(swapOrdersProvider);
      final resolved = OrchestraOrderIds.resolve(legId);
      final row = rows.where((r) => r.id == legId || r.id == resolved);
      if (row.isEmpty) {
        VenueArrivals.markIds([legId]);
      } else {
        VenueArrivals.mark(row.first);
      }
    } catch (_) {}
  }

  /// Hands a leg's end on ([BitcoinLegEnv.legEnded]): delivered into
  /// [into], or failed (the money comes home). A watch that ran out of
  /// time learned nothing.
  void _legEnded(LegDelivery d, OneBalanceVenue? into) {
    if (d == LegDelivery.timedOut) return;
    try {
      env.legEnded?.call(d == LegDelivery.delivered ? into : null);
    } catch (_) {}
  }

  /// The order's own step ended (placed or not): the slip's run is over
  /// even while a slower leg is still landing (its line keeps updating).
  final Completer<void> _placeEnded = Completer();

  String _route = MoneyRoute.viaDollars;
  DirectBitcoinPlan? _plan;
  double _baseline = 0;
  String _ownSpark = '';
  DateTime? _sentAt;
  DateTime? _landedAt;

  /// The first stop's end; the run is over for the slip from then on.
  BitcoinFundedEnd? _end;
  final Completer<BitcoinFundedEnd> _ended = Completer();
  final Completer<void> _stopped = Completer();

  /// The direct leg's verified quote was accepted (true), or the order
  /// goes via Dollars (false).
  final Completer<bool> _covered = Completer();

  /// The venue move's outcome, once it ran.
  final Completer<OrderFundingOutcome> _venueMove = Completer();
  bool _venueMoveStarted = false;

  /// The other venue's legs, once they went (null: none went).
  final Completer<VenueCashPullOutcome?> _pulled = Completer();
  final Completer<void> _credited = Completer();
  late final Future<bool> _placement;
  String? _failedText;
  String? _failedCode;

  Future<BitcoinFundedEnd> run() {
    unawaited(_go().then((end) {
      if (!_ended.isCompleted) _ended.complete(end);
    }, onError: (Object e) {
      if (!_ended.isCompleted) {
        runner._errors[id] = e;
        _ended.complete(_stop(FundedOrderStage.failed, BitcoinFundedEnd.notSent,
            reason: 'not_sent',
            category: TrackingService.errorCategory(e),
            moneyAt: FundedMoneyAt.bitcoin));
      }
    }));
    return _ended.future;
  }

  /// Stops the run with the money at [moneyAt]: the record says where, the
  /// order is dropped and its approval cancelled. The first stop wins; the
  /// legs already on their way keep landing (their lines say so).
  BitcoinFundedEnd _stop(FundedOrderStage stage, BitcoinFundedEnd end,
      {required String reason,
      String? category,
      OrderFundingStage journeyStage = OrderFundingStage.bitcoin,
      FundedMoneyAt? moneyAt,
      String? message}) {
    final already = _end;
    if (already != null) return already;
    _end = end;
    orders.stop(id,
        stage: stage, reason: reason, moneyAt: moneyAt, message: message);
    if (category != null) journey.failed(venue, journeyStage, category);
    try {
      r.dropOrder();
    } catch (_) {}
    if (!_stopped.isCompleted) _stopped.complete();
    if (!_covered.isCompleted) _covered.complete(false);
    if (!_ended.isCompleted) _ended.complete(end);
    return end;
  }

  Future<BitcoinFundedEnd> _go() async {
    // The baseline the chain's landing is measured from, read BEFORE any
    // send.
    var baseline = env.dollarsNow();
    final fresh = await env.freshDollars();
    if (fresh != null && fresh > baseline) baseline = fresh;
    _baseline = baseline;

    journey.start(
      venue,
      orderUsd: r.label.orderUsd,
      fundUsd: r.fundUsd,
      readyUsd: r.readyUsd,
      dollarsUsd: baseline,
      entrySource: r.entrySource,
      fundingSource: 'bitcoin',
      otherVenueUsed: r.otherVenueUsed,
      extra: {
        'add_usd': r.plan.targetUsd,
        'add_sats': r.plan.sats,
      },
    );

    try {
      _ownSpark = await env.ownSpark();
    } catch (e) {
      runner._errors[id] = e;
      return _stop(FundedOrderStage.failed, BitcoinFundedEnd.notSent,
          reason: 'not_sent',
          category: TrackingService.errorCategory(e),
          moneyAt: FundedMoneyAt.bitcoin,
          message: runner._errorText(e));
    }

    // Direct or via Dollars, decided before anything moves.
    final plan = await _decide();
    _plan = plan;
    _route = plan.direct ? MoneyRoute.direct : MoneyRoute.viaDollars;
    journey.setRoute(venue, _route, reason: plan.reason);

    final other = plan.direct
        ? plan.otherUsd
        : math.max(0.0, r.fundUsd - r.plan.targetUsd - baseline);
    final otherVenue = OneBalanceVenue.values.firstWhere((v) => v != venue);
    final legs = plan.direct
        ? [
            MoneyStep(
                id: FundedStepId.bitcoin,
                kind: MoneyStepKind.leg,
                from: MoneyPlace.bitcoin,
                usd: plan.targetUsd,
                route: MoneyRoute.direct),
            if (plan.dollarsUsd > 0)
              MoneyStep(
                  id: FundedStepId.dollars,
                  kind: MoneyStepKind.leg,
                  from: MoneyPlace.dollars,
                  usd: plan.dollarsUsd),
            if (other > 0.005)
              MoneyStep(
                  id: FundedStepId.other(otherVenue),
                  kind: MoneyStepKind.leg,
                  from: moneyPlaceOf(otherVenue),
                  usd: _cents(other)),
          ]
        : _viaLegs(otherVenue, other);
    // A new try keeps the legs that landed before (done, never run
    // again); only the new legs and what depends on them run.
    final carried = [
      for (final s in orders.byId(id)?.steps.steps ?? const <MoneyStep>[])
        if (s.id.startsWith('prev:')) s,
    ];
    final planned =
        fundedOrderGraph(venue: venue, legs: legs, orderUsd: r.label.orderUsd);
    final graph = MoneyStepGraph([...carried, ...planned.steps]);
    orders.setSteps(id, graph, route: _route);
    if (plan.direct) orders.setStage(id, FundedOrderStage.preparing);

    // The venue's own placement, followed from now on: it fires the
    // moment the venue can take the order, whatever leg is still landing.
    final wait = r.awaitPlacement ??
        runner._placementWait(venue, fundedRunId: id,
            onFailed: (message, code) {
          _failedText = message;
          _failedCode = code;
        });
    _placement = wait(onCredited: () {
      if (!_credited.isCompleted) _credited.complete();
      orders.setStage(id, FundedOrderStage.placing);
    }).catchError((Object _) => false);

    final steps = MoneyStepRunner(
      graph: graph,
      actionFor: _actionFor,
      onChange: (g) => orders.setSteps(id, g),
      clock: _now,
    );
    var settled = await Future.any<MoneyStepGraph?>([
      steps.run(),
      _placeEnded.future.then((_) => null),
    ]);
    settled ??= steps.graph;
    final stopped = _end;
    if (stopped != null) return stopped;
    if (settled.byId(FundedStepId.place)?.status == MoneyStepStatus.done) {
      orders.setStage(id, FundedOrderStage.done);
      return BitcoinFundedEnd.placed;
    }
    // The money reached the venue (or is on its way there): it stays as
    // its cash, available.
    orders.stop(id,
        stage: FundedOrderStage.failed,
        reason: _failedCode ?? 'placement',
        moneyAt: FundedMoneyAt.venue,
        message: _failedText);
    return BitcoinFundedEnd.placementFailed;
  }

  /// The chain's legs: Bitcoin → Dollars, then the whole move from
  /// Dollars (and the other venue's cash pulled once the dollars landed).
  List<MoneyStep> _viaLegs(OneBalanceVenue otherVenue, double other) => [
        MoneyStep(
            id: FundedStepId.bitcoinToDollars,
            kind: MoneyStepKind.leg,
            from: MoneyPlace.bitcoin,
            to: MoneyPlace.dollars,
            usd: r.plan.targetUsd,
            route: MoneyRoute.viaDollars),
        MoneyStep(
            id: FundedStepId.dollarsOnward,
            kind: MoneyStepKind.leg,
            from: MoneyPlace.dollars,
            usd: _cents(math.max(0.0, r.fundUsd - other)),
            route: MoneyRoute.viaDollars,
            after: const [FundedStepId.bitcoinToDollars]),
        if (other > 0.005)
          MoneyStep(
              id: FundedStepId.other(otherVenue),
              kind: MoneyStepKind.leg,
              from: moneyPlaceOf(otherVenue),
              usd: _cents(other),
              after: const [FundedStepId.bitcoinToDollars]),
      ];

  static double _cents(double usd) => (usd * 100).roundToDouble() / 100;

  Future<DirectBitcoinPlan> _decide() async {
    final bound = BitcoinLegGrants.directTo(r.grant);
    final planDirect = env.planDirect;
    if (bound == null || planDirect == null || env.sendDirect == null) {
      return const DirectBitcoinPlan.viaDollars(DirectBitcoinReason.noAddress);
    }
    if (DirectRouteRefusals.isBitcoinRefused(venue)) {
      return const DirectBitcoinPlan.viaDollars(
          DirectBitcoinReason.refusedRecently);
    }
    try {
      return await planDirect(
        venue: venue,
        fundUsd: r.fundUsd,
        addUsd: r.plan.targetUsd,
        dollarsUsd: _baseline,
        via: r.plan,
        ownVenue: bound,
        directMaxSats: BitcoinLegGrants.directMaxSatsOf(r.grant)?.toInt() ?? 0,
      ).timeout(const Duration(seconds: 10));
    } catch (_) {
      return const DirectBitcoinPlan.viaDollars(DirectBitcoinReason.noEstimate);
    }
  }

  MoneyStepAction? _actionFor(MoneyStep step) {
    if (step.id == FundedStepId.bitcoin) return _directBitcoin;
    if (step.id == FundedStepId.bitcoinToDollars) return _viaBitcoin;
    if (step.id == FundedStepId.dollars) return _dollars;
    if (step.id == FundedStepId.dollarsOnward) return _dollars;
    if (step.kind == MoneyStepKind.leg) return _otherLeg;
    switch (step.id) {
      case FundedStepId.convert:
        return (s, u) => _phase('converting', u, optional: true);
      case FundedStepId.approve:
        return (s, u) => _phase('approving', u, optional: true);
      case FundedStepId.confirm:
        return (s, u) => _phase('confirming', u);
      case FundedStepId.credit:
        return (s, u) => _phase('crediting', u);
      case FundedStepId.place:
        return _place;
    }
    return null;
  }

  // ── The legs ──

  void _slow() => orders.update(id, (rec) => rec.copyWith(slow: true));

  void _landed(MoneyStep step, String source) {
    final started = step.startedAt;
    if (started == null) return;
    journey.legLanded(venue, source, _now().difference(started).inMilliseconds);
  }

  void _startVenueMove(
      OrderFundingController controller, FundingLegContext legs) {
    if (_venueMoveStarted) return;
    _venueMoveStarted = true;
    Future<OrderFundingOutcome> move;
    try {
      move = r.fundVenue(controller, legs);
    } catch (e) {
      move = Future.value(
          OrderFundingRefused(TrackingService.errorCategory(e), error: e));
    }
    unawaited(move
        .then<OrderFundingOutcome>((o) => o,
            onError: (Object e) =>
                OrderFundingRefused(TrackingService.errorCategory(e), error: e))
        .then((outcome) {
      if (!_pulled.isCompleted) _pulled.complete(null);
      if (!_venueMove.isCompleted) _venueMove.complete(outcome);
    }));
  }

  void _onPulled(VenueCashPullOutcome pulled) {
    if (!_pulled.isCompleted) _pulled.complete(pulled);
  }

  /// Bitcoin straight into the venue, one Orchestra order. The other legs
  /// start the moment its verified quote is accepted; a refusal before
  /// that falls back to the chain with nothing moved.
  Future<MoneyStepOutcome> _directBitcoin(MoneyStep step,
      void Function(MoneyStep Function(MoneyStep)) update) async {
    final plan = _plan!;
    final bound = BitcoinLegGrants.directTo(r.grant);
    String? ownVenue;
    try {
      ownVenue = await env.ownVenue?.call(venue);
    } catch (_) {
      ownVenue = null;
    }
    if (ownVenue == null ||
        bound == null ||
        ownVenue.trim().toLowerCase() != bound.trim().toLowerCase()) {
      return _fallBack('account_unavailable', sticky: false);
    }
    var covered = false;
    var sending = false;
    DirectLegSent sent;
    try {
      sent = await env.sendDirect!(
        venue: venue,
        ownVenue: ownVenue,
        ownSpark: _ownSpark,
        sats: plan.sats,
        targetUsd: plan.targetUsd,
        stepUp: BitcoinLegGrants.stepUpDirect(r.grant,
            ownVenue: ownVenue, ownSpark: _ownSpark, onCovered: () {
          covered = true;
          if (!_covered.isCompleted) _covered.complete(true);
          // Every other leg starts now, next to the sats leaving.
          _startVenueMove(
              _ref.read(orderFundingControllerProvider),
              FundingLegContext(
                bitcoinShareUsd: plan.bitcoinShareUsd,
                bitcoinArrivingUsd: plan.targetUsd,
                bitcoinSentAt: _now(),
                onPulled: _onPulled,
              ));
        }),
        onSending: () {
          sending = true;
          _sentAt = _now();
          journey.bitcoinSent(venue);
        },
      );
    } catch (e) {
      if (e is SettlementFundingUnknown) {
        runner._errors[id] = e;
        _stop(FundedOrderStage.ready, BitcoinFundedEnd.maybeSent,
            reason: 'maybe_sent',
            category: 'settlement_unknown',
            message: runner._l10n().settlementFundingUnknownBody);
        return const MoneyStepFailed('maybe_sent');
      }
      if (!covered && !sending) {
        return _fallBack(_refusalCode(e), sticky: true, error: e);
      }
      runner._errors[id] = e;
      _stop(FundedOrderStage.failed, BitcoinFundedEnd.notSent,
          reason: 'not_sent',
          category: TrackingService.errorCategory(e),
          moneyAt:
              _venueMoveStarted ? FundedMoneyAt.venue : FundedMoneyAt.bitcoin,
          message: runner._errorText(e));
      return MoneyStepFailed(TrackingService.errorCategory(e));
    }
    _sentAt ??= _now();
    var legId = sent.orderId ?? sent.quoteId;
    orders.addVenueRow(id, sent.quoteId);
    if (sent.orderId != null) orders.addVenueRow(id, sent.orderId!);
    update((s) => s.copyWith(ref: legId));
    final registration = sent.registration;
    if (registration != null) {
      unawaited(registration.then((orderId) {
        if (orderId == null || orderId.isEmpty) return;
        legId = orderId;
        orders.addVenueRow(id, orderId);
        update((s) => s.copyWith(ref: orderId));
      }).catchError((Object _) {}));
    }
    final delivery = await _delivery(() => legId, into: venue);
    switch (delivery) {
      case LegDelivery.delivered:
        _landedAt = _now();
        journey.bitcoinLanded(venue);
        _landed(step, 'bitcoin');
        orders.update(id, (rec) => rec.copyWith(slow: false));
        return MoneyStepDone(ref: legId);
      case LegDelivery.failed:
        _stop(FundedOrderStage.failed, BitcoinFundedEnd.refunded,
            reason: 'refunded',
            category: 'refunded',
            moneyAt: FundedMoneyAt.bitcoin,
            message: runner._l10n().slipFundingBitcoinBack);
        return const MoneyStepFailed('refunded');
      case LegDelivery.timedOut:
        // Never placed later at a price nobody saw: the order goes, the
        // money lands in the venue whenever it does.
        _stop(FundedOrderStage.ready, BitcoinFundedEnd.ready,
            reason: 'timeout',
            category: 'timeout',
            moneyAt: FundedMoneyAt.venue);
        return const MoneyStepFailed('timeout');
    }
  }

  /// The direct route was refused before any sats left: remembered when
  /// the refusal is about the route itself, then the chain in its place.
  MoneyStepOutcome _fallBack(String reason,
      {required bool sticky, Object? error}) {
    if (sticky && DirectRouteRefusals.sticky(reason)) {
      DirectRouteRefusals.refuseBitcoin(venue);
    }
    TrackingService.track('venue_cash_direct_refused', params: {
      'venue': 'bitcoin',
      'destination': venue.name,
      'reason': reason,
      'retrying': false,
      'sticky': DirectRouteRefusals.sticky(reason),
      'amount_usd': _cents(_plan?.targetUsd ?? r.plan.targetUsd),
    });
    _route = MoneyRoute.viaDollars;
    journey.setRoute(venue, _route, reason: 'direct_refused');
    orders.update(id,
        (rec) => rec.copyWith(route: _route, stage: FundedOrderStage.adding));
    if (!_covered.isCompleted) _covered.complete(false);
    final otherVenue = OneBalanceVenue.values.firstWhere((v) => v != venue);
    final via = _viaLegs(otherVenue, _plan?.otherUsd ?? 0)
        .where((l) =>
            l.kind == MoneyStepKind.leg && l.from != moneyPlaceOf(otherVenue))
        .toList();
    return MoneyStepFellBack(reason, via);
  }

  static String _refusalCode(Object e) {
    if (e is SettlementStopped) return 'settlement_${e.reason.name}';
    final category = TrackingService.errorCategory(e);
    final t = e.runtimeType.toString().toLowerCase();
    if (t.contains('routeunavailable') || t.contains('unavailable')) {
      return 'route_unavailable';
    }
    return RegExp(r'^[a-z_]{1,48}$').hasMatch(category)
        ? category
        : 'quote_failed';
  }

  /// The chain's first leg: Bitcoin → Dollars, then (once the dollars
  /// landed) the whole move into the venue.
  Future<MoneyStepOutcome> _viaBitcoin(MoneyStep step,
      void Function(MoneyStep Function(MoneyStep)) update) async {
    if (!_covered.isCompleted) _covered.complete(false);
    DateTime? sentAt;
    BitcoinLegTicket ticket;
    try {
      ticket = await env.send(
        sparkAddress: _ownSpark,
        plan: r.plan,
        stepUp: BitcoinLegGrants.stepUp(r.grant, ownSpark: _ownSpark),
        onSending: () {
          sentAt = _now();
          _sentAt = sentAt;
          journey.bitcoinSent(venue);
        },
      );
    } catch (e) {
      runner._errors[id] = e;
      if (e is SettlementFundingUnknown) {
        // The sats may have left: never resend, never place. The
        // reconciler resolves the leg; any dollars stay in Dollars.
        _stop(FundedOrderStage.ready, BitcoinFundedEnd.maybeSent,
            reason: 'maybe_sent',
            category: 'settlement_unknown',
            message: runner._l10n().settlementFundingUnknownBody);
        return const MoneyStepFailed('maybe_sent');
      }
      _stop(FundedOrderStage.failed, BitcoinFundedEnd.notSent,
          reason: 'not_sent',
          category: TrackingService.errorCategory(e),
          moneyAt: FundedMoneyAt.bitcoin,
          message: runner._errorText(e));
      return MoneyStepFailed(TrackingService.errorCategory(e));
    }
    sentAt ??= _now();
    _sentAt = sentAt;
    orders.addBtcRow(id, ticket.quoteId);
    var legId = ticket.orderId ?? ticket.quoteId;
    if (ticket.orderId != null) orders.addBtcRow(id, ticket.orderId!);
    update((s) => s.copyWith(ref: legId));
    final registration = ticket.registration;
    if (registration != null) {
      unawaited(registration.then((orderId) {
        if (orderId == null || orderId.isEmpty) return;
        legId = orderId;
        orders.addBtcRow(id, orderId);
        update((s) => s.copyWith(ref: orderId));
      }).catchError((Object _) {}));
    }
    final landing = await env.watcher(since: sentAt!).watch(
          id: () => legId,
          baselineUsd: _baseline,
          // At least what the quote said lands, less a cent of rounding.
          minRiseUsd: math.max(0.01, ticket.minOutUsd - 0.01),
          // The leg's own target landed: what the button named.
          enoughUsd: _baseline + r.plan.targetUsd - 0.01,
          onSlow: _slow,
        );
    // Orchestra's own status said the leg ended: its row and the balances
    // are read now. A landing seen in the balance alone needs no news.
    if (landing is DollarsLegFailed ||
        (landing is DollarsLanded && landing.byStatus)) {
      try {
        env.legEnded?.call(null);
      } catch (_) {}
    }
    switch (landing) {
      case DollarsLegFailed():
        _stop(FundedOrderStage.failed, BitcoinFundedEnd.refunded,
            reason: 'refunded',
            category: 'refunded',
            moneyAt: FundedMoneyAt.bitcoin,
            message: runner._l10n().slipFundingBitcoinBack);
        return const MoneyStepFailed('refunded');
      case DollarsLandingTimedOut():
        // Never placed later at a price nobody saw: the order goes, the
        // dollars land in Dollars whenever they do.
        _stop(FundedOrderStage.ready, BitcoinFundedEnd.ready,
            reason: 'timeout',
            category: 'timeout',
            moneyAt: FundedMoneyAt.investments);
        return const MoneyStepFailed('timeout');
      case DollarsLanded(:final freshDollarsUsd):
        _landedAt = _now();
        journey.bitcoinLanded(venue);
        _landed(step, 'bitcoin');
        orders.update(
            id,
            (rec) =>
                rec.copyWith(stage: FundedOrderStage.preparing, slow: false));
        // Delivery is authoritative for the first leg, but does not make
        // a smaller cached reading spendable. Do not start a larger onward
        // leg and leave it appearing to run while the wallet lacks it.
        if (!r.otherVenueUsed &&
            math.max(env.dollarsNow(), freshDollarsUsd) + 1e-6 < r.fundUsd) {
          _stop(FundedOrderStage.ready, BitcoinFundedEnd.ready,
              reason: 'dollars_short',
              category: 'insufficient_funds',
              journeyStage: OrderFundingStage.fund,
              moneyAt: FundedMoneyAt.investments);
          return MoneyStepDone(ref: legId);
        }
        // The move into the venue under the same grant. The controller's
        // own Dollars check is the guard; it reads the fresh balance.
        final controller = _ref
            .read(orderFundingControllerProvider)
            .withDollars(() => math.max(env.dollarsNow(), freshDollarsUsd));
        _startVenueMove(
            controller,
            FundingLegContext(
                bitcoinSentAt: sentAt,
                bitcoinLandedAt: _landedAt,
                onPulled: _onPulled));
        return MoneyStepDone(ref: legId);
    }
  }

  /// Dollars → the venue: the direct mode's Dollars share (started with
  /// the Bitcoin leg's quote), or the chain's whole move (after the
  /// Bitcoin's dollars landed).
  Future<MoneyStepOutcome> _dollars(MoneyStep step,
      void Function(MoneyStep Function(MoneyStep)) update) async {
    if (step.id == FundedStepId.dollars) {
      final direct = await _covered.future;
      // Gone via Dollars: the chain's own move carries this share.
      if (!direct) return const MoneyStepSkipped();
    }
    final outcome = await Future.any<OrderFundingOutcome?>([
      _venueMove.future,
      _stopped.future.then((_) => null),
    ]);
    if (outcome == null) return const MoneyStepFailed('stopped');
    final direct = _route == MoneyRoute.direct;
    switch (outcome) {
      case OrderFundingFunded(:final move):
        orders.addVenueRow(id, move.quoteId);
        if (move.orderId != null) orders.addVenueRow(id, move.orderId!);
        var legId = move.orderId ?? move.quoteId;
        update((s) => s.copyWith(
            ref: legId, usd: move.sentUsd > 0 ? _cents(move.sentUsd) : null));
        final reg = move.registration;
        if (reg != null) {
          unawaited(reg.then((orderId) {
            if (orderId != null && orderId.isNotEmpty) {
              legId = orderId;
              orders.addVenueRow(id, orderId);
              update((s) => s.copyWith(ref: orderId));
            }
          }).catchError((Object _) {}));
        }
        final delivery = await _delivery(() => legId, into: venue);
        switch (delivery) {
          case LegDelivery.delivered:
            _landed(step, 'dollars');
            return MoneyStepDone(ref: legId);
          case LegDelivery.failed:
            // Orchestra sends the dollars back to Dollars.
            _stop(FundedOrderStage.ready, BitcoinFundedEnd.ready,
                reason: 'venue_refused',
                category: 'refunded',
                journeyStage: OrderFundingStage.fund,
                moneyAt:
                    direct ? FundedMoneyAt.venue : FundedMoneyAt.investments);
            return const MoneyStepFailed('refunded');
          case LegDelivery.timedOut:
            return const MoneyStepFailed('timeout');
        }
      case OrderFundingNotNeeded():
        return const MoneyStepSkipped();
      case OrderFundingUnconfirmed():
        return const MoneyStepDone();
      case OrderFundingRefused(:final reason, :final error):
        if (error != null) runner._errors[id] = error;
        // Nothing left Dollars: the money is in Dollars (the chain) or on
        // its way into the venue (direct), the order is not.
        _stop(FundedOrderStage.ready, BitcoinFundedEnd.ready,
            reason: 'venue_refused',
            category: reason,
            journeyStage: OrderFundingStage.fund,
            moneyAt: direct ? FundedMoneyAt.venue : FundedMoneyAt.investments);
        return MoneyStepFailed(reason);
      case OrderFundingNeedsDollars():
        _stop(FundedOrderStage.ready, BitcoinFundedEnd.ready,
            reason: 'venue_refused',
            category: 'insufficient_funds',
            journeyStage: OrderFundingStage.fund,
            moneyAt: direct ? FundedMoneyAt.venue : FundedMoneyAt.investments);
        return const MoneyStepFailed('insufficient_funds');
    }
  }

  /// The other venue's cash: done once each of its legs landed (straight
  /// into the venue, or home to Dollars for the move to carry).
  Future<MoneyStepOutcome> _otherLeg(MoneyStep step,
      void Function(MoneyStep Function(MoneyStep)) update) async {
    final pulled = await Future.any<VenueCashPullOutcome?>([
      _pulled.future,
      _stopped.future.then((_) => null),
    ]);
    if (pulled == null) {
      return MoneyStepFailed(_end != null ? 'stopped' : 'venue_cash');
    }
    final mine = [
      for (final l in pulled.legs)
        if (moneyPlaceOf(l.venue) == step.from) l
    ];
    if (mine.isEmpty || mine.every((l) => !l.ok)) {
      return const MoneyStepFailed('venue_cash');
    }
    final watches = <Future<LegDelivery>>[];
    for (final l in mine.where((l) => l.ok)) {
      final res = l.result!;
      var legId = res.orderId ?? res.quoteId;
      update((s) => s.copyWith(ref: legId));
      final reg = res.registration;
      if (reg != null) {
        unawaited(reg.then((orderId) {
          if (orderId != null && orderId.isNotEmpty) legId = orderId;
        }).catchError((Object _) {}));
      }
      watches.add(_delivery(() => legId,
          into: switch (pulled.destination) {
            VenueCashDestination.investing => OneBalanceVenue.investing,
            VenueCashDestination.predictions => OneBalanceVenue.predictions,
            _ => null,
          }, onExplicitRefund: () {
        unawaited(_cashSnapshot
            .refresh(_ref.read, settledRefs: {res.operationId ?? res.quoteId}));
      }));
    }
    final results = await Future.wait(watches);
    if (results.any((d) => d == LegDelivery.failed)) {
      return const MoneyStepFailed('refunded');
    }
    if (results.any((d) => d == LegDelivery.timedOut)) {
      return const MoneyStepFailed('timeout');
    }
    final settledRefs = {
      for (final leg in mine.where((l) => l.ok))
        leg.result!.operationId ?? leg.result!.quoteId,
    };
    if (settledRefs.isNotEmpty) {
      unawaited(_cashSnapshot.refresh(_ref.read, settledRefs: settledRefs));
    }
    _landed(step, step.from?.name ?? 'other');
    return const MoneyStepDone();
  }

  // ── Readiness and the order ──

  /// One readiness phase, as the autofire reports it: done once the venue
  /// moved past it (or placed), skipped when an [optional] phase was never
  /// needed, failed when the order stopped before it.
  Future<MoneyStepOutcome> _phase(
          String phase, void Function(MoneyStep Function(MoneyStep)) update,
          {bool optional = false}) =>
      readinessPhaseStep(
        phase,
        update,
        optional: optional,
        phases: env.readiness?.call(venue),
        credited: _credited.future,
        placement: _placement,
        stopped: _stopped.future,
        failedCode: () => _failedCode,
      );

  Future<MoneyStepOutcome> _place(MoneyStep step,
      void Function(MoneyStep Function(MoneyStep)) update) async {
    final placed = await _placement;
    // After the runner recorded this step, so the run's end reads it.
    Timer.run(() {
      if (!_placeEnded.isCompleted) _placeEnded.complete();
    });
    if (placed) return const MoneyStepDone();
    return MoneyStepFailed(
        _failedCode ?? (_end != null ? 'stopped' : 'placement'));
  }
}
