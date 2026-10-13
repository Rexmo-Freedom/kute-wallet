// lib/services/one_balance/predictions_venue_funder.dart
//
// Predictions' door for the one-balance layer: Dollars in (an order's
// funding leg), venue cash out (the sweeper), what is idle, what a move
// costs. Both moves are the Move sheet's own Orchestra settlements,
// copied here so the slip and the sweeper run them without a sheet:
//
//   * `fund` is `moveUsdToPredictions` (spark USDB → polygon USDC.e),
//     exactly as the Move sheet dispatches it: the same quote request, the
//     same verified quote gate, the same Activity row written before the
//     send, the same background registration. The only difference is the
//     step-up: the slip already asked for ONE approval that covers both
//     the move and the order (`PmGrants.fundedBetReview`), so the hook
//     checks that grant against the quote instead of prompting again.
//   * `sweepToDollars` is the Predictions cash-out pointed at Dollars
//     (`movePredictionsToDollars`), under `SensitiveAction.venueWithdraw`
//     for a user grant, or `SweepAuthorization.automatic` for the sweeper,
//     which `withdrawUsdc` only accepts for a quote-bound send whose
//     verified recipient is this wallet's own Spark address.
//
// Money safety: nothing leaves without a quote that passed the quote gate
// (rule 7: the recipient is the wallet's own account), the step-up hook
// refuses a quote whose recipient is not this wallet's Predictions
// account, and `RouteUnavailable` / `SettlementStopped` are thrown before
// anything is sent.
//
// Analytics: the move keeps `polymarket_deposit_*` / `polymarket_withdraw_*`
// with `purpose` (`conversion_leg` for funding, `sweep` for sweeps) so
// money is counted once; no `move_*` events. Orchestra quote flows are
// `order_funding_predictions` and `sweep_predictions` so the backend tags
// the rows.

import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/orchestra_router.dart'
    show doubleToOrchestraAmount, orchestraAmountToDouble;
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/models/affiliate_model.dart' show AffiliateService;
import 'package:kute/models/orchestra_model.dart' show OrchestraEstimate;
import 'package:kute/models/orchestra_routes_model.dart' show RouteKey;
import 'package:kute/models/settlement_operation.dart'
    show SettlementAccountKind, SettlementFlow;
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/auth_provider.dart' show sessionUnlockedProvider;
import 'package:kute/providers/hyperliquid_account_provider.dart'
    show hyperliquidAddressProvider;
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/spark_address_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/providers/transactions_provider.dart'
    show walletTransactionCacheProvider;
import 'package:kute/services/api/orchestra_api.dart' show OrchestraService;
import 'package:kute/services/background_sync_service.dart';
import 'package:kute/services/funding/hot_settlement.dart';
import 'package:kute/services/funding/owned_address_resolver.dart'
    show ProviderReader;
import 'package:kute/services/funding/settlement_registration.dart'
    show followSettlementRegistration, withSettlementOrderId;
import 'package:kute/services/funding/settlement_runner.dart';
import 'package:kute/services/funding/venue_shortfall.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/order_funding.dart'
    show OrderFundingStage, StagedVenueFunder;
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/one_balance/venue_sweeper.dart'
    show SweepableVenueFunder;
import 'package:kute/services/orchestra/orchestra_quote_guard.dart';
import 'package:kute/services/orchestra_routes.dart'
    show kOrchestraUsdAssetCode, kOrchestraUsdChain;
import 'package:kute/services/polymarket_spark_txs_service.dart';
import 'package:kute/services/tracking_service.dart';

/// Orchestra quote `flow` strings the backend tags rows by.
const String kOrderFundingPredictionsFlow = 'order_funding_predictions';
const String kSweepPredictionsFlow = 'sweep_predictions';

/// The provider `tag` each move's quote carries, by [purpose]
/// (`OrchestraQuoteRequest.tag`), so the backend files the row as an
/// order's funding leg or a sweep rather than a Move-sheet move.
const Map<String, String> kPredictionsQuoteTags = {
  'order_funding': 'kute:order_funding_predictions',
  'sweep': 'kute:sweep_predictions',
  'rollout_sweep': 'kute:rollout_sweep_predictions',
  'cash_pull': 'kute:cash_pull_predictions',
};

/// The tag for [purpose], the plain sweep tag for one not listed.
String predictionsQuoteTag(String purpose) =>
    kPredictionsQuoteTags[purpose] ?? kPredictionsQuoteTags['sweep']!;

/// The route's share of a move, as read from one estimate (the route's
/// own share, with Kute's app fee folded in when the estimate left it
/// out), and when it was read.
typedef _RouteShare = ({double fee, DateTime at, String? recipient});

/// How long one estimate's fee share stands in for the next read, so a
/// slip retyping the amount does not wait on the network every time.
const Duration _kRouteShareMaxAge = Duration(minutes: 5);

/// Smallest move the Predictions rail takes from Dollars: the app's own
/// dollar floor, above Orchestra's $0.80.
const double kPredictionsMinMoveUsd = ShortfallRules.minTopUpUsd;

class PredictionsVenueFunder
    implements
        StagedVenueFunder,
        SweepableVenueFunder,
        DirectSweepableVenueFunder {
  PredictionsVenueFunder(this._read);

  final ProviderReader _read;

  /// Test seam: stands in for Orchestra's estimate. Returns the share of
  /// a move of the given dollars the route keeps (0.006 for 0.6%).
  @visibleForTesting
  static Future<double> Function(double usd)? debugRouteShare;

  _RouteShare? _lastShare;

  // ── VenueFunder ─────────────────────────────────────────────────

  @override
  Future<VenueMoveResult> fund({
    required double usd,
    required MoveAuthorization auth,
    String purpose = 'order_funding',
  }) =>
      fundStaged(usd: usd, auth: auth, purpose: purpose);

  @override
  Future<double> idleUsd() async {
    final state = _read(polymarketTradingProvider).valueOrNull;
    if (state == null || !state.balanceKnown) return 0;
    var committed = 0.0;
    try {
      final orders =
          await _read(polymarketTradingProvider.notifier).getOpenOrders();
      for (final order in orders) {
        if (order.side.toUpperCase() != 'BUY') continue;
        final remaining = ((double.tryParse(order.originalSize) ?? 0) -
                (double.tryParse(order.sizeMatched) ?? 0))
            .clamp(0.0, double.infinity);
        committed += remaining * (double.tryParse(order.price) ?? 0);
      }
    } catch (_) {
      // Unreadable orders: nothing is counted as idle rather than money
      // a resting order still needs.
      return 0;
    }
    return (state.usdcBalance - committed).clamp(0.0, double.infinity);
  }

  @override
  Future<double> minimumUsd() async => kPredictionsMinMoveUsd;

  @override
  Future<VenueMoveQuote> estimate(double usd) async {
    final share = await _routeShare(usd);
    final arriving = usd * (1 - share);
    return VenueMoveQuote(
      arrivingUsd: arriving,
      feeUsd: usd - arriving,
      fixedCostUsd: 0,
      minUsd: kPredictionsMinMoveUsd,
      maxUsd: double.infinity,
    );
  }

  /// The share the Dollars → Predictions route keeps, from Orchestra's
  /// estimate for [usd] (Kute's fee counted on top when the estimate
  /// leaves it out, as `slipRouteFeeFrom` reads it). Falls back to the
  /// last share read within [_kRouteShareMaxAge], then to
  /// [ShortfallRules.fallbackRouteFee]. A read, never a quote.
  Future<double> _routeShare(double usd) async {
    final seam = debugRouteShare;
    if (seam != null) return seam(usd);
    // The deposit wallet the move's quote pays, as the live account has
    // it (the first answer [_ownPredictionsAccount] gives); never awaited
    // here. A share read for one recipient never stands in for another.
    String? recipient;
    try {
      recipient = OrchestraService.estimateRecipient(
          _read(polymarketTradingProvider).valueOrNull?.proxyWalletAddress);
    } catch (_) {}
    final last = _lastShare;
    final held = last != null && last.recipient == recipient ? last : null;
    try {
      final amount = doubleToOrchestraAmount(
          usd <= 0 ? kPredictionsMinMoveUsd : usd, kOrchestraUsdAssetCode,
          chain: kOrchestraUsdChain);
      final result = await OrchestraService.getEstimate(
        sourceChain: kOrchestraUsdChain,
        sourceAsset: kOrchestraUsdAssetCode,
        destinationChain: 'polygon',
        destinationAsset: 'USDC.e',
        amount: amount,
        recipientAddress: recipient,
      ).timeout(const Duration(seconds: 4));
      final est = result.data;
      if (est != null) {
        final share = routeShareFrom(est,
            sentUsd: usd,
            arrivingUsd: orchestraAmountToDouble(est.estimatedOut, 'USDC.e',
                chain: 'polygon'));
        if (share != null) {
          _lastShare =
              (fee: share, at: DateTime.now(), recipient: recipient);
          return share;
        }
      }
    } catch (_) {}
    if (held != null &&
        DateTime.now().difference(held.at) < _kRouteShareMaxAge) {
      return held.fee;
    }
    return ShortfallRules.fallbackRouteFee;
  }

  /// What one estimate says the route keeps of [sentUsd], Kute's fee
  /// included: the estimate's own share plus the app fee rate it reports
  /// when it did not take that fee out itself. Null when unusable.
  @visibleForTesting
  static double? routeShareFrom(OrchestraEstimate est,
      {required double sentUsd, required double arrivingUsd}) {
    final fee = ShortfallRules.routeFeeFrom(
        sentUsd: sentUsd, arrivingUsd: arrivingUsd);
    if (fee == null) return null;
    if (est.estimateIncludesAppFee == true) return fee;
    final bps = est.kuteAppFeeBps;
    if (bps == null || bps < 0 || bps >= 10000) return null;
    return 1 - (1 - fee) * (1 - bps / 10000);
  }

  // ── Funding: Dollars → Predictions ──────────────────────────────

  @override
  Future<VenueMoveResult> fundStaged({
    required double usd,
    required MoveAuthorization auth,
    String purpose = 'order_funding',
    void Function(OrderFundingStage stage)? onStage,
  }) async {
    if (!usd.isFinite || usd < kPredictionsMinMoveUsd) {
      throw const RouteUnavailable('below the Predictions minimum');
    }
    final amountBaseUnits = BigInt.from((usd * 1e6).round());
    final evm = await _ownPredictionsAccount();
    if (evm == null || evm.isEmpty) {
      throw const RouteUnavailable('Predictions account not ready');
    }
    TrackingService.track('polymarket_deposit_initiated', params: {
      'route': 'usd',
      'entry_source': purpose,
      'wallet_kind': 'hot',
      'venue': 'polymarket',
      'purpose': 'conversion_leg',
      ...TrackingService.moneyParams(amountUsd: usd),
    });

    var dollarsSent = false;
    String? pendingQuoteRowId;
    final read = _read;
    try {
      final sparkRefund = await read(sparkSelfAddressProvider.future);
      final runner = await HotSettlement.runner();
      final settled = await runner.run(HotSettlement.plan(
        read,
        flow: SettlementFlow.moveUsdToPredictions,
        route: RouteKey(
            fromChain: kOrchestraUsdChain,
            fromAsset: kOrchestraUsdAssetCode,
            toChain: 'polygon',
            toAsset: 'USDC.e'),
        source: SettlementAccountKind.sparkHot,
        destination: SettlementAccountKind.pmHot,
        amountUsd: usd,
        // The one approval the slip asked for covers this leg: the hook
        // checks it against the verified quote instead of prompting.
        stepUp: (intent) async => fundingAuthorized(auth, intent,
            ownAccount: evm, sessionUnlocked: _sessionUnlocked()),
        requestQuote: (key) => HotSettlement.quote(
          read,
          OrchestraQuoteRequest(
            sourceChain: kOrchestraUsdChain,
            sourceAsset: kOrchestraUsdAssetCode,
            destinationChain: 'polygon',
            destinationAsset: 'USDC.e',
            amountBaseUnits: amountBaseUnits,
            recipientAddress: evm,
            refundAddress: sparkRefund,
            recipientKind: RecipientKind.ownPmWallet,
            ownAddress: evm,
            tag: predictionsQuoteTag(purpose),
          ),
          flow: kOrderFundingPredictionsFlow,
          idempotencyKey: key,
        ),
        prepareFunding: (verifiedQuote, operationId) async {
          onStage?.call(OrderFundingStage.fund);
          final orchQuote = verifiedQuote.quote;
          final staleRowId = pendingQuoteRowId;
          if (staleRowId != null && staleRowId != orchQuote.quoteId) {
            await read(swapOrdersProvider.notifier).deleteExchange(staleRowId);
          }
          await read(swapOrdersProvider.notifier).addExchange(
              usdToPredictionsRow(
                id: orchQuote.quoteId,
                quote: verifiedQuote,
                evm: evm,
                sparkRefund: sparkRefund,
                operationId: operationId,
                walletId: read(settingsProvider).activeWalletId,
              ));
          pendingQuoteRowId = orchQuote.quoteId;
          return HotSettlement.prepareSpark(read, verifiedQuote);
        },
        registerInBackground: true,
        fund: (verifiedQuote, prepared) async {
          dollarsSent = true;
          final paymentId = await HotSettlement.sendSpark(read, prepared);
          PolymarketSparkTxsService.tag(paymentId);
          return SettlementFundingProof.spark(paymentId);
        },
      ));
      final orchQuote = settled.quote.quote;
      final sentUsd = settled.quote.amountIn.toDouble() / 1e6;
      final orderId = settled.orderId ?? orchQuote.quoteId;
      final exchange = usdToPredictionsRow(
        id: orderId,
        quote: settled.quote,
        evm: evm,
        sparkRefund: sparkRefund,
        operationId: settled.operation.operationId,
        walletId: read(settingsProvider).activeWalletId,
      );
      await read(swapOrdersProvider.notifier).addExchange(exchange);
      if (orderId != orchQuote.quoteId) {
        await read(swapOrdersProvider.notifier)
            .deleteExchange(orchQuote.quoteId);
      }
      pendingQuoteRowId = null;
      followSettlementRegistration(read, settled);
      final estOut = orchestraAmountToDouble(orchQuote.estimatedOut, 'USDC.e',
          chain: 'polygon');
      if (orderId.startsWith('ord_')) {
        // ignore: unawaited_futures
        AffiliateService.logProviderEvent(
          provider: 'orchestra',
          providerOrderId: orderId,
          status: 'pending',
          sourceAsset: kOrchestraUsdAssetCode,
          sourceAmount: sentUsd,
          destinationAsset: 'USDC',
          destinationAmount: estOut,
        );
      }
      try {
        read(walletTransactionCacheProvider.notifier).mergeSwapOrder(exchange);
      } catch (_) {}
      BackgroundSyncService().syncNow();
      read(polymarketTradingProvider.notifier).wrapIncomingUsdcEToPusd();
      withSettlementOrderId(
          settled,
          (orderId) =>
              TrackingService.track('polymarket_deposit_submitted', params: {
                'order_id': orderId,
                ...TrackingService.orchestraJoinParams(orderId),
                'venue': 'polymarket',
                'route': 'usd',
                'wallet_kind': 'hot',
                'purpose': 'conversion_leg',
                ...TrackingService.moneyParams(amountUsd: estOut),
              }));
      return VenueMoveResult(
        quoteId: orchQuote.quoteId,
        orderId: settled.orderId,
        registration: settled.registration,
        sentUsd: sentUsd,
        arrivingUsdEstimate: estOut,
      );
    } catch (e) {
      final staleRowId = pendingQuoteRowId;
      if (!dollarsSent && staleRowId != null) {
        // ignore: unawaited_futures
        read(swapOrdersProvider.notifier).deleteExchange(staleRowId);
      }
      TrackingService.track('polymarket_deposit_failed', params: {
        'venue': 'polymarket',
        'provider': 'orchestra',
        'stage': dollarsSent ? 'post_send' : 'pre_send',
        'purpose': 'conversion_leg',
        'error_category': _failReason(e),
        ...TrackingService.moneyParams(amountUsd: usd),
      });
      rethrow;
    }
  }

  /// Whether the one approval of a funded order covers this leg: a live
  /// bet grant bound to this venue and to a cap at or above what the
  /// verified quote moves, and the quote's recipient is this wallet's own
  /// Predictions account ([ownAccount]). A sweep authorization never
  /// funds a deposit. Pure, so it is tested on its own.
  @visibleForTesting
  static bool fundingAuthorized(
    MoveAuthorization auth,
    SettlementAuthorizationIntent intent, {
    required String ownAccount,
    required bool sessionUnlocked,
    DateTime? now,
  }) {
    if (!sessionUnlocked) return false;
    if (auth is! UserGrantAuthorization) return false;
    if (intent.flow != SettlementFlow.moveUsdToPredictions) return false;
    final sep = intent.destination.lastIndexOf('|');
    final recipient =
        (sep < 0 ? intent.destination : intent.destination.substring(0, sep))
            .trim()
            .toLowerCase();
    if (recipient.isEmpty || recipient != ownAccount.trim().toLowerCase()) {
      return false;
    }
    final reviewed = intent.reviewedQuote;
    if (reviewed != null &&
        reviewed.request.recipientKind != RecipientKind.ownPmWallet) {
      return false;
    }
    return PmGrants.fundingGrantCovers(auth.grant,
        amountIn: intent.amountIn, venue: IntentVenue.polymarket, now: now);
  }

  // ── Sweep: Predictions → Dollars ────────────────────────────────

  /// Brings [usd] of venue cash home to Dollars: the Move sheet's
  /// Predictions cash-out pointed at Dollars, run without a sheet. Under
  /// a [UserGrantAuthorization] the grant is a `venueWithdraw` approval
  /// checked against the quote; under [SweepAuthorization.automatic] the
  /// send is allowed only for a quote whose verified recipient is this
  /// wallet's own Spark address (`withdrawUsdc` enforces it again).
  @override
  Future<VenueMoveResult> sweepToDollars({
    required double usd,
    required MoveAuthorization auth,
    String purpose = 'sweep',
  }) async {
    if (!usd.isFinite || usd < kPredictionsMinMoveUsd) {
      throw const RouteUnavailable('below the Predictions minimum');
    }
    final read = _read;
    final pm = read(polymarketTradingProvider.notifier);
    final refundEvm = await _ownPredictionsAccount();
    if (refundEvm == null || refundEvm.isEmpty) {
      throw const RouteUnavailable('Predictions account not ready');
    }
    var usdcSent = false;
    try {
      final sparkAddress = await read(sparkSelfAddressProvider.future);
      final microUsdc = await pm.payableMicroUsdc(usd);
      AuthGrant? approved;
      final runner = await HotSettlement.runner();
      final settled = await runner.run(HotSettlement.plan(
        read,
        flow: SettlementFlow.movePredictionsToDollars,
        route: RouteKey(
            fromChain: 'polygon',
            fromAsset: 'USDC.e',
            toChain: kOrchestraUsdChain,
            toAsset: kOrchestraUsdAssetCode),
        source: SettlementAccountKind.pmHot,
        destination: SettlementAccountKind.sparkHot,
        amountUsd: usd,
        requestQuote: (key) => HotSettlement.quote(
          read,
          OrchestraQuoteRequest(
            sourceChain: 'polygon',
            sourceAsset: 'USDC.e',
            destinationChain: kOrchestraUsdChain,
            destinationAsset: kOrchestraUsdAssetCode,
            amountBaseUnits: microUsdc,
            recipientAddress: sparkAddress,
            refundAddress: refundEvm,
            recipientKind: RecipientKind.ownSpark,
            ownAddress: sparkAddress,
            tag: predictionsQuoteTag(purpose),
          ),
          flow: kSweepPredictionsFlow,
          idempotencyKey: key,
        ),
        stepUp: (intent) async {
          switch (auth) {
            case UserGrantAuthorization(:final grant):
              approved = grant;
              try {
                AuthGrants.check(
                    grant,
                    OrchestraGrants.settlement(intent,
                        action: SensitiveAction.venueWithdraw,
                        asset: 'USDC.e',
                        account: refundEvm,
                        limits: const {VenueLimit.bridged: true}));
                return true;
              } on AuthGrantException {
                return false;
              }
            case SweepAuthorization():
              return sweepAuthorized(intent,
                  sessionUnlocked: _sessionUnlocked());
            case ApprovedLegAuthorization():
              // Home to Dollars is the automatic authorization's move; a
              // leg of an approved action goes straight on ([sweepTo]).
              return false;
          }
        },
        fund: (verifiedQuote, _) async {
          usdcSent = true;
          final txHash = await pm.withdrawUsdc(
            toAddress: verifiedQuote.depositAddress,
            amount: usd,
            bridged: true,
            exactMicroUsdc: verifiedQuote.amountIn,
            grant: approved,
            sweep: auth is SweepAuthorization ? auth : null,
            sweepQuote: verifiedQuote,
          );
          return SettlementFundingProof.relayer(txHash);
        },
        registerInBackground: true,
      ));
      final orchQuote = settled.quote.quote;
      final orderId = settled.orderId ?? orchQuote.quoteId;
      final estOut = orchestraAmountToDouble(
          orchQuote.estimatedOut, kOrchestraUsdAssetCode,
          chain: kOrchestraUsdChain);
      final exchange = SwapOrder(
        id: orderId,
        coinFrom: 'USDC',
        networkFrom: 'POLYGON',
        coinTo: kOrchestraUsdAssetCode,
        networkTo: 'SPARK',
        depositAddress: orchQuote.depositAddress,
        depositAmount: usd.toStringAsFixed(2),
        withdrawalAmount: estOut.toStringAsFixed(2),
        status: 'exchanging',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        withdrawalAddress: sparkAddress,
        depositMin: '0',
        depositMax: '0',
        rate: '0',
        refundAddress: refundEvm,
        provider: 'Orchestra',
        walletId: read(settingsProvider).activeWalletId,
        operationId: settled.operation.operationId,
      );
      await read(swapOrdersProvider.notifier).addExchange(exchange);
      followSettlementRegistration(read, settled);
      if (orderId.startsWith('ord_')) {
        // ignore: unawaited_futures
        AffiliateService.logProviderEvent(
          provider: 'orchestra',
          providerOrderId: orderId,
          status: 'pending',
          sourceAsset: 'USDC',
          sourceAmount: usd,
          destinationAsset: kOrchestraUsdAssetCode,
          destinationAmount: estOut,
        );
      }
      try {
        read(walletTransactionCacheProvider.notifier).mergeSwapOrder(exchange);
      } catch (_) {}
      BackgroundSyncService().syncNow();
      withSettlementOrderId(
          settled,
          (orderId) =>
              TrackingService.track('polymarket_withdraw_submitted', params: {
                'order_id': orderId,
                ...TrackingService.orchestraJoinParams(orderId),
                'venue': 'polymarket',
                'destination': 'usd',
                'purpose': purpose,
                ...TrackingService.moneyParams(
                    amountUsd: usd, asset: 'usdc', amount: usd),
              }));
      return VenueMoveResult(
        quoteId: orchQuote.quoteId,
        orderId: settled.orderId,
        registration: settled.registration,
        sentUsd: usd,
        arrivingUsdEstimate: estOut,
        operationId: settled.operation.operationId,
      );
    } catch (e) {
      TrackingService.track('polymarket_withdraw_failed', params: {
        'venue': 'polymarket',
        'provider': 'orchestra',
        'stage': usdcSent ? 'post_send' : 'pre_send',
        'purpose': purpose,
        'error_category': _failReason(e),
        ...TrackingService.moneyParams(amountUsd: usd),
      });
      rethrow;
    }
  }

  /// Whether the sweeper may pay [intent] without a user tap: the session
  /// is unlocked, the flow is the Predictions cash-out to Dollars and the
  /// verified quote's recipient is the wallet's own Spark address. Pure.
  @visibleForTesting
  static bool sweepAuthorized(
    SettlementAuthorizationIntent intent, {
    required bool sessionUnlocked,
  }) {
    if (!sessionUnlocked) return false;
    if (intent.flow != SettlementFlow.movePredictionsToDollars) return false;
    final reviewed = intent.reviewedQuote;
    if (reviewed == null) return false;
    return reviewed.request.recipientKind == RecipientKind.ownSpark;
  }

  // ── Direct: Predictions → Bitcoin, Predictions → Investing ──────

  /// Predictions cash straight to [destination] when another action pulls
  /// it: the Predictions cash-out (the same relayer withdrawal of the
  /// bridged token to a verified quote's deposit address) quoted by
  /// Orchestra to the final destination, `polygon:USDC.e → spark:BTC` to
  /// the wallet's own Spark address or `→ hypercore:USDC` to its own
  /// Investing account. [VenueCashDestination.dollars] is
  /// [sweepToDollars]. Only under the action's approval
  /// ([ApprovedLegAuthorization]): the quote's verified recipient must be
  /// that own account and the leg inside the approval's caps
  /// ([directLegAuthorized], `DirectLegGrants.take`, and `withdrawUsdc`
  /// again). [SweepAuthorization.automatic] is refused here.
  ///
  /// Throws [DirectRouteRefused] when the route was refused before any
  /// USDC.e left (no route, a refused or unverified quote, a shut gate, an
  /// own account that cannot be read): the caller goes through Dollars.
  /// Anything after the withdrawal started is rethrown untouched.
  @override
  Future<VenueMoveResult> sweepTo({
    required VenueCashDestination destination,
    required double usd,
    required MoveAuthorization auth,
    String purpose = 'cash_pull',
  }) async {
    switch (destination) {
      case VenueCashDestination.dollars:
        return sweepToDollars(usd: usd, auth: auth, purpose: purpose);
      case VenueCashDestination.predictions:
        throw ArgumentError('Predictions cash is already in Predictions');
      case VenueCashDestination.bitcoin:
      case VenueCashDestination.investing:
        break;
    }
    if (!usd.isFinite || usd < kPredictionsMinMoveUsd) {
      throw const DirectRouteRefused('below the Predictions minimum');
    }
    final bitcoin = destination == VenueCashDestination.bitcoin;
    final toChain = bitcoin ? 'spark' : 'hypercore';
    final toAsset = bitcoin ? 'BTC' : 'USDC';
    final read = _read;
    final pm = read(polymarketTradingProvider.notifier);
    var usdcSent = false;
    try {
      final String? refundEvm;
      final String? recipient;
      final BigInt microUsdc;
      try {
        refundEvm = await _ownPredictionsAccount();
        recipient = bitcoin
            ? await read(sparkSelfAddressProvider.future)
            : await read(hyperliquidAddressProvider.future);
        microUsdc = await pm.payableMicroUsdc(usd);
      } catch (_) {
        throw const DirectRouteRefused('account_unavailable');
      }
      if (refundEvm == null ||
          refundEvm.isEmpty ||
          recipient == null ||
          recipient.isEmpty) {
        throw const DirectRouteRefused('account_unavailable');
      }
      final String ownTo = recipient;
      final String refund = refundEvm;
      AuthGrant? approved;
      final runner = await HotSettlement.runner();
      final SettlementRunResult settled;
      try {
        settled = await runner.run(HotSettlement.plan(
          read,
          flow: bitcoin
              ? SettlementFlow.moveUsdToBtc
              : SettlementFlow.movePredictionsToInvesting,
          route: RouteKey(
              fromChain: 'polygon',
              fromAsset: 'USDC.e',
              toChain: toChain,
              toAsset: toAsset),
          source: SettlementAccountKind.pmHot,
          destination: bitcoin
              ? SettlementAccountKind.sparkHot
              : SettlementAccountKind.hlHot,
          amountUsd: usd,
          requestQuote: (key) => HotSettlement.quote(
            read,
            OrchestraQuoteRequest(
              sourceChain: 'polygon',
              sourceAsset: 'USDC.e',
              destinationChain: toChain,
              destinationAsset: toAsset,
              amountBaseUnits: microUsdc,
              recipientAddress: ownTo,
              refundAddress: refund,
              recipientKind:
                  bitcoin ? RecipientKind.ownSpark : RecipientKind.ownEvm,
              ownAddress: ownTo,
              tag: predictionsQuoteTag(purpose),
            ),
            flow: kSweepPredictionsFlow,
            idempotencyKey: key,
          ),
          stepUp: (intent) async {
            switch (auth) {
              case UserGrantAuthorization(:final grant):
                approved = grant;
                try {
                  AuthGrants.check(
                      grant,
                      OrchestraGrants.settlement(intent,
                          action: SensitiveAction.venueWithdraw,
                          asset: 'USDC.e',
                          account: refund,
                          limits: const {VenueLimit.bridged: true}));
                  return true;
                } on AuthGrantException {
                  return false;
                }
              case SweepAuthorization():
                // The automatic authorization only ever brings money home
                // to Dollars; a leg anywhere else waits for the action's
                // own approval.
                return false;
              case ApprovedLegAuthorization(:final grant):
                return directLegAuthorized(intent,
                        destination: destination,
                        ownRecipient: ownTo,
                        sessionUnlocked: _sessionUnlocked()) &&
                    DirectLegGrants.take(grant,
                        venue: 'predictions',
                        destination: destination.code,
                        amount: intent.amountIn);
            }
          },
          fund: (verifiedQuote, _) async {
            usdcSent = true;
            final txHash = await pm.withdrawUsdc(
              toAddress: verifiedQuote.depositAddress,
              amount: usd,
              bridged: true,
              exactMicroUsdc: verifiedQuote.amountIn,
              grant: approved,
              sweep: auth is ApprovedLegAuthorization ? auth : null,
              sweepQuote: verifiedQuote,
            );
            return SettlementFundingProof.relayer(txHash);
          },
          registerInBackground: true,
        ));
      } catch (e) {
        // Nothing left Predictions: the route, the quote or the approval
        // refused it. The caller goes through Dollars.
        if (!usdcSent && e is! SettlementFundingUnknown) {
          throw DirectRouteRefused(_failReason(e));
        }
        rethrow;
      }
      if (bitcoin) {
        // The bitcoin delivery is this cash-out's, as on the Move sheet.
        PolymarketSparkTxsService.recordExpectedClaimDelivery(
          microUsd: BigInt.from((usd * 1e6).round()),
        );
      }
      final orchQuote = settled.quote.quote;
      final orderId = settled.orderId ?? orchQuote.quoteId;
      final estOut = orchestraAmountToDouble(orchQuote.estimatedOut, toAsset,
          chain: toChain);
      final exchange = SwapOrder(
        id: orderId,
        coinFrom: 'USDC',
        networkFrom: 'POLYGON',
        coinTo: toAsset,
        networkTo: toChain.toUpperCase(),
        depositAddress: orchQuote.depositAddress,
        depositAmount: usd.toStringAsFixed(2),
        withdrawalAmount: estOut.toStringAsFixed(bitcoin ? 8 : 2),
        status: 'exchanging',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        withdrawalAddress: ownTo,
        depositMin: '0',
        depositMax: '0',
        rate: '0',
        refundAddress: refund,
        provider: 'Orchestra',
        walletId: read(settingsProvider).activeWalletId,
        operationId: settled.operation.operationId,
      );
      await read(swapOrdersProvider.notifier).addExchange(exchange);
      followSettlementRegistration(read, settled);
      if (orderId.startsWith('ord_')) {
        // ignore: unawaited_futures
        AffiliateService.logProviderEvent(
          provider: 'orchestra',
          providerOrderId: orderId,
          status: 'pending',
          sourceAsset: 'USDC',
          sourceAmount: usd,
          destinationAsset: toAsset,
          destinationAmount: estOut,
        );
      }
      try {
        read(walletTransactionCacheProvider.notifier).mergeSwapOrder(exchange);
      } catch (_) {}
      BackgroundSyncService().syncNow();
      withSettlementOrderId(
          settled,
          (orderId) =>
              TrackingService.track('polymarket_withdraw_submitted', params: {
                'order_id': orderId,
                ...TrackingService.orchestraJoinParams(orderId),
                'venue': 'polymarket',
                'destination': bitcoin ? 'btc' : 'investing',
                'purpose': purpose,
                ...TrackingService.moneyParams(
                    amountUsd: usd, asset: 'usdc', amount: usd),
              }));
      // What lands, in dollars: Bitcoin's output is sats, so the dollar
      // figure is what left less the route's share at the quote's fee.
      final arrivingUsd = bitcoin
          ? usd * (1 - orchQuote.combinedFeeBps / 10000)
          : estOut;
      return VenueMoveResult(
        quoteId: orchQuote.quoteId,
        orderId: settled.orderId,
        registration: settled.registration,
        sentUsd: usd,
        arrivingUsdEstimate: arrivingUsd,
        operationId: settled.operation.operationId,
      );
    } catch (e) {
      TrackingService.track('polymarket_withdraw_failed', params: {
        'venue': 'polymarket',
        'provider': 'orchestra',
        'stage': usdcSent ? 'post_send' : 'pre_send',
        'purpose': purpose,
        'error_category': e is DirectRouteRefused
            ? (e.reason ?? 'route_unavailable')
            : _failReason(e),
        ...TrackingService.moneyParams(amountUsd: usd),
      });
      rethrow;
    }
  }

  /// Whether a leg of an approved action may pay [intent] when it pulls
  /// Predictions cash straight to [destination]: the session is unlocked,
  /// the flow is that destination's, and the verified quote's recipient is
  /// the wallet's own account for it ([ownRecipient]: its Spark address
  /// for Bitcoin, its Investing account otherwise). The leg caps of the
  /// action's approval are checked on top (`DirectLegGrants.take`). Pure.
  @visibleForTesting
  static bool directLegAuthorized(
    SettlementAuthorizationIntent intent, {
    required VenueCashDestination destination,
    required String ownRecipient,
    required bool sessionUnlocked,
  }) {
    if (!sessionUnlocked) return false;
    final reviewed = intent.reviewedQuote;
    if (reviewed == null) return false;
    final request = reviewed.request;
    switch (destination) {
      case VenueCashDestination.bitcoin:
        if (intent.flow != SettlementFlow.moveUsdToBtc ||
            request.recipientKind != RecipientKind.ownSpark ||
            request.destinationAsset != 'BTC') {
          return false;
        }
        return request.recipientAddress == ownRecipient;
      case VenueCashDestination.investing:
        if (intent.flow != SettlementFlow.movePredictionsToInvesting ||
            request.recipientKind != RecipientKind.ownEvm ||
            request.destinationChain != 'hypercore') {
          return false;
        }
        return request.recipientAddress.toLowerCase() ==
            ownRecipient.toLowerCase();
      case VenueCashDestination.dollars:
      case VenueCashDestination.predictions:
        return false;
    }
  }

  // ── Shared ──────────────────────────────────────────────────────

  /// The wallet's own Predictions account (the deposit wallet), read
  /// from the live state or asked for; null while it is not set up.
  Future<String?> _ownPredictionsAccount() async {
    final live = _read(polymarketTradingProvider).valueOrNull?.proxyWalletAddress;
    if (live != null && live.isNotEmpty) return live;
    try {
      return await _read(polymarketTradingProvider.notifier).depositAddress();
    } catch (_) {
      return null;
    }
  }

  bool _sessionUnlocked() {
    try {
      return _read(sessionUnlockedProvider);
    } catch (_) {
      return false;
    }
  }

  static String _failReason(Object e) =>
      (e is SettlementStopped && e.reason == SettlementStopReason.declined)
          ? 'user_cancelled'
          : TrackingService.errorCategory(e);

  /// The Activity row of a Dollars → Predictions move, exactly as the Move
  /// sheet writes it.
  @visibleForTesting
  static SwapOrder usdToPredictionsRow({
    required String id,
    required VerifiedOrchestraQuote quote,
    required String evm,
    required String sparkRefund,
    required String operationId,
    String? walletId,
  }) {
    final estOut = orchestraAmountToDouble(quote.quote.estimatedOut, 'USDC.e',
        chain: 'polygon');
    return SwapOrder(
      id: id,
      coinFrom: kOrchestraUsdAssetCode,
      networkFrom: 'SPARK',
      coinTo: 'USDC',
      networkTo: 'POLYGON',
      depositAddress: quote.depositAddress,
      depositAmount: (quote.amountIn.toDouble() / 1e6).toStringAsFixed(2),
      withdrawalAmount: estOut.toStringAsFixed(2),
      status: 'exchanging',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      withdrawalAddress: evm,
      depositMin: '0',
      depositMax: '0',
      rate: '0',
      refundAddress: sparkRefund,
      provider: 'Orchestra',
      walletId: walletId,
      operationId: operationId,
    );
  }
}

/// Predictions' funder, bound to the spending wallet's providers: the
/// order-funding door and the sweeper's door on one object.
final predictionsVenueFunderProvider =
    Provider<SweepableVenueFunder>((ref) => PredictionsVenueFunder(ref.read));

/// The venue a funder serves, for callers that index by venue.
const OneBalanceVenue kPredictionsFunderVenue = OneBalanceVenue.predictions;
