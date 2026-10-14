// lib/services/one_balance/bitcoin_to_dollars_leg.dart
//
// Bitcoin → Dollars on the spending wallet, headless: the Orchestra leg
// `spark:BTC → spark:USDB` whose recipient AND refund are the wallet's own
// Spark address. Two callers, one code path:
//
//   * the Move sheet's Bitcoin → Investments door (`_dispatchBtcToUsd`),
//     which supplies its own quote (the typed figure grossed up) and its
//     own step-up prompt;
//   * an order slip short of the whole Investments balance, which tops
//     Dollars up from Bitcoin under the order's ONE approval
//     (`BitcoinLegGrants.stepUp`), then funds and places the order
//     (`bitcoin_funded_order.dart`).
//
// [BitcoinToDollarsLeg.send] runs the settlement (quote gate, ownership,
// step-up, payment, registration in the background) and the bookkeeping
// every Bitcoin → Dollars move has always done: the Activity row, the
// backend attribution of the real order, the fee history and the
// `convert_success` event. Nothing user-facing.
//
// [DollarsLandingWatcher] tells the chain the dollars landed as fast as
// the app can know: the order's own status read every second and the
// dollar balance rising past the quoted amount, whichever comes first,
// then a fresh token-balance read until the SDK's cache shows them.

import 'dart:async';
import 'dart:math' as math;

import 'package:kute/helpers/orchestra_router.dart'
    show orchestraAmountToDouble;
import 'package:kute/models/affiliate_model.dart' show AffiliateService;
import 'package:kute/models/orchestra_routes_model.dart' show RouteKey;
import 'package:kute/models/settlement_operation.dart'
    show SettlementAccountKind, SettlementFlow;
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/settings_provider.dart' show settingsProvider;
import 'package:kute/providers/swap_orders_provider.dart'
    show swapOrdersProvider;
import 'package:kute/providers/transactions_provider.dart'
    show walletTransactionCacheProvider;
import 'package:kute/services/api/orchestra_api.dart' show OrchestraService;
import 'package:kute/services/background_sync_service.dart';
import 'package:kute/services/fee_history_service.dart';
import 'package:kute/services/funding/conv_timing.dart';
import 'package:kute/services/funding/hot_settlement.dart';
import 'package:kute/services/funding/owned_address_resolver.dart'
    show ProviderReader;
import 'package:kute/services/funding/settlement_registration.dart'
    show followSettlementRegistration, withSettlementOrderId;
import 'package:kute/services/funding/settlement_runner.dart'
    show
        SettlementFundingProof,
        SettlementQuoteResult,
        SettlementRunResult,
        SettlementStepUpHook;
import 'package:kute/services/orchestra/arrival_target.dart';
import 'package:kute/services/orchestra/orchestra_quote_guard.dart'
    show OrchestraQuoteRequest, RecipientKind, kManualMoveQuoteTag;
import 'package:kute/services/orchestra_routes.dart'
    show kOrchestraUsdAssetCode, kOrchestraUsdChain;
import 'package:kute/services/polymarket_spark_txs_service.dart';
import 'package:kute/services/tracking_service.dart';

/// What one Bitcoin → Dollars leg sent.
class BitcoinLegSent {
  const BitcoinLegSent({
    required this.settled,
    required this.sats,
    required this.estimatedOutUsd,
    required this.minOutUsd,
  });

  final SettlementRunResult settled;

  /// The sats that left, as the verified quote asked.
  final int sats;

  /// What the quote said lands in Dollars.
  final double estimatedOutUsd;

  /// The least the quote locks (its estimate when it locks nothing).
  final double minOutUsd;

  String get quoteId => settled.quote.quoteId;
  String? get orderId => settled.orderId;
  Future<String?>? get registration => settled.registration;

  /// The Activity row's id right now (the order id once registered).
  String get rowId => settled.orderId ?? settled.quote.quoteId;
}

/// The Bitcoin → Dollars settlement, shared by the Move sheet and the
/// slips. See the file header.
abstract final class BitcoinToDollarsLeg {
  /// `spark:BTC → spark:USDB`.
  static RouteKey get route => RouteKey(
      fromChain: 'spark',
      fromAsset: 'BTC',
      toChain: kOrchestraUsdChain,
      toAsset: kOrchestraUsdAssetCode);

  /// Runs the leg: [requestQuote] supplies the verified quote (to the
  /// wallet's own Spark address [sparkAddress]), [stepUp] approves it
  /// (the Move sheet's prompt, or an order's grant), and the sats are paid
  /// to the quote's deposit address. [onSending] runs right before the
  /// payment call (funds may leave from then on). [read] is used during
  /// the run; [appRead] must outlive the caller (the background
  /// registration moves the Activity row with it).
  ///
  /// Throws whatever the runner throws: a `SettlementStopped`, a quote
  /// failure or a wallet guard before anything moved, a
  /// `SettlementFundingUnknown` when the payment's outcome is unknown.
  static Future<BitcoinLegSent> send(
    ProviderReader read, {
    required ProviderReader appRead,
    required String sparkAddress,
    required double approxUsd,
    required double usdPerBtc,
    required SettlementStepUpHook stepUp,
    required Future<SettlementQuoteResult> Function(String idempotencyKey)
        requestQuote,
    void Function()? onSending,
  }) async {
    ConvTiming.mark('BitcoinToDollarsLeg.send runner start');
    final runner = await HotSettlement.runner();
    final settled = await runner.run(HotSettlement.plan(
      read,
      flow: SettlementFlow.moveBtcToUsdc,
      route: route,
      source: SettlementAccountKind.sparkHot,
      destination: SettlementAccountKind.sparkHot,
      amountUsd: approxUsd,
      stepUp: stepUp,
      requestQuote: requestQuote,
      prepareFunding: (verifiedQuote, _) =>
          HotSettlement.prepareSpark(read, verifiedQuote),
      // The caller's wait ends once the sats left and the proof is on
      // disk; the deposit is registered in the background.
      registerInBackground: true,
      fund: (verifiedQuote, prepared) async {
        // Send the sats to the quote's deposit address. Tag the outbound
        // leg so the Activity feed tells the story once, on the exchange
        // row, instead of twice.
        onSending?.call();
        ConvTiming.mark('BitcoinToDollarsLeg.send sendSpark start');
        final paymentId = await HotSettlement.sendSpark(read, prepared);
        ConvTiming.mark('BitcoinToDollarsLeg.send sendSpark end');
        PolymarketSparkTxsService.tag(paymentId);
        return SettlementFundingProof.spark(paymentId);
      },
    ));
    final orchQuote = settled.quote.quote;
    final sats = settled.quote.amountIn.toInt();
    final orderId = settled.orderId ?? orchQuote.quoteId;
    double usdOf(String raw) => orchestraAmountToDouble(
        raw, kOrchestraUsdAssetCode,
        chain: kOrchestraUsdChain);
    final estOut = usdOf(orchQuote.estimatedOut);
    final locked = orchQuote.lockedMinAmountOut;
    final minOut = locked == null || locked.isEmpty ? estOut : usdOf(locked);

    // Record the exchange so the purchase is trackable while it settles.
    final exchange = SwapOrder(
      id: orderId,
      coinFrom: 'BTC',
      networkFrom: 'SPARK',
      coinTo: kOrchestraUsdAssetCode,
      networkTo: 'SPARK',
      depositAddress: orchQuote.depositAddress,
      depositAmount: (sats / 1e8).toStringAsFixed(8),
      withdrawalAmount: estOut.toStringAsFixed(2),
      status: 'exchanging',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      withdrawalAddress: sparkAddress,
      depositMin: '0',
      depositMax: '0',
      rate: '0',
      refundAddress: sparkAddress,
      provider: 'Orchestra',
      walletId: read(settingsProvider).activeWalletId,
      operationId: settled.operation.operationId,
    );
    await read(swapOrdersProvider.notifier).addExchange(exchange);
    // The background submit moves the row to the order id it returns.
    followSettlementRegistration(appRead, settled);
    // Backend attribution for the REAL order only — a quote id (q_…)
    // would create a row the completion can never reconcile with.
    if (orderId.startsWith('ord_')) {
      // ignore: unawaited_futures
      AffiliateService.logProviderEvent(
        provider: 'orchestra',
        providerOrderId: orderId,
        status: 'pending',
        sourceAsset: 'BTC',
        sourceAmount: sats / 1e8,
        destinationAsset: kOrchestraUsdAssetCode,
        destinationAmount: estOut,
      );
    }
    read(walletTransactionCacheProvider.notifier).mergeSwapOrder(exchange);
    BackgroundSyncService().syncNow();

    // Reported under the order id once the registration returns it.
    final feeWalletId = read(settingsProvider).activeWalletId;
    withSettlementOrderId(settled, (orderId) {
      // Orchestra's spread on the leg, against the live BTC price.
      try {
        final fairUsd = (sats / 1e8) * usdPerBtc;
        final spreadUsd = fairUsd - estOut;
        if (usdPerBtc > 0 && spreadUsd > 0) {
          FeeHistoryService.log(
            id: 'orch-$orderId',
            kind: FeeKind.orchestraSpread,
            microUsd: (spreadUsd * 1000000).round(),
            nativeAmount: spreadUsd.toStringAsFixed(6),
            nativeUnit: 'usd',
            source: 'Orchestra',
            txId: orderId,
            walletId: feeWalletId,
          );
        }
      } catch (_) {}

      TrackingService.track('convert_success', params: {
        'direction': 'btc_to_dollars',
        'amount_bucket': TrackingService.usdBucket(estOut),
        ...TrackingService.exactUsd('amount_usd', estOut),
        'order_id': orderId,
        'provider': 'orchestra',
      });
    });
    return BitcoinLegSent(
      settled: settled,
      sats: sats,
      estimatedOutUsd: estOut,
      minOutUsd: minOut > 0 ? minOut : estOut,
    );
  }

  /// A verified quote for [sats] of the wallet's own bitcoin to its own
  /// dollars ([sparkAddress] is both the recipient and the refund, read
  /// from the Spark SDK by the caller), grossed up once so that at least
  /// [targetUsd] lands, never above [maxSats]. Every quote passes the
  /// Orchestra quote gate. Returns the sats quoted and the quote.
  static Future<(int, SettlementQuoteResult)> quoteForTarget(
    ProviderReader read, {
    required int sats,
    required double targetUsd,
    required int maxSats,
    required String sparkAddress,
    required String idempotencyKey,
  }) async {
    Future<SettlementQuoteResult> quoteFor(int amountSats, String key) {
      final request = OrchestraQuoteRequest(
        sourceChain: 'spark',
        sourceAsset: 'BTC',
        destinationChain: kOrchestraUsdChain,
        destinationAsset: kOrchestraUsdAssetCode,
        amountBaseUnits: BigInt.from(amountSats),
        recipientAddress: sparkAddress,
        refundAddress: sparkAddress,
        recipientKind: RecipientKind.ownSpark,
        ownAddress: sparkAddress,
        // The same leg the Move sheet's Bitcoin → Investments door
        // quotes, filed the same way, so the backend treats it the same.
        tag: kManualMoveQuoteTag,
      );
      return HotSettlement.quote(read, request,
          flow: 'order_funding_bitcoin', idempotencyKey: key);
    }

    final first = math.min(sats, maxSats);
    var sendSats = first;
    var fetched = await quoteFor(sendSats, idempotencyKey);
    final estOut = orchestraAmountToDouble(
        fetched.quote.quote.estimatedOut, kOrchestraUsdAssetCode,
        chain: kOrchestraUsdChain);
    if (arrivalTargetShort(estOut, targetUsd)) {
      final scaled = grossUpSatsForTarget(
        sats: sendSats,
        estimatedOut: estOut,
        targetUsd: targetUsd,
        maxSats: maxSats,
      );
      if (scaled > sendSats) {
        sendSats = scaled;
        // A different request body takes its own idempotency key.
        fetched = await quoteFor(
            sendSats, OrchestraService.generateIdempotencyKey());
      }
    }
    return (sendSats, fetched);
  }
}

// ── Sizing ─────────────────────────────────────────────────────────────

/// Why a Bitcoin leg cannot fund the order, before anything is approved.
enum BitcoinLegRefusal {
  /// No bitcoin price to size it with.
  noPrice,

  /// The spending wallet's bitcoin does not cover the leg.
  insufficientBitcoin,
}

/// The Bitcoin leg an order needs, sized before the one approval.
class BitcoinLegPlan {
  const BitcoinLegPlan({
    required this.dollarsShortUsd,
    required this.targetUsd,
    required this.sats,
    required this.maxSats,
    required this.usdPerBtc,
  });

  /// What the whole Investments balance lacks for the order's move, to
  /// the cent, as the slip's button rounds it.
  final double dollarsShortUsd;

  /// What must land in Dollars: [dollarsShortUsd], never under the route's
  /// minimum. Exactly the X of "Add $X to Investments" (see
  /// [BitcoinLegRules.addUsd]); nothing is added on top.
  final double targetUsd;

  /// The sats the first quote asks for.
  final int sats;

  /// The most sats the approval lets leave (the gross-up's room), never
  /// above the wallet's bitcoin.
  final int maxSats;

  final double usdPerBtc;

  @override
  String toString() => 'BitcoinLegPlan(short: $dollarsShortUsd, '
      'target: $targetUsd, sats: $sats, max: $maxSats)';
}

/// [BitcoinLegPlan] or why there is none.
class BitcoinLegSizing {
  const BitcoinLegSizing.ok(BitcoinLegPlan this.plan) : refusal = null;
  const BitcoinLegSizing.refused(BitcoinLegRefusal this.refusal)
      : plan = null;

  final BitcoinLegPlan? plan;
  final BitcoinLegRefusal? refusal;
}

/// The Bitcoin leg's sizing rules. Pure.
abstract final class BitcoinLegRules {
  /// The leg's route minimum, the app's $1 floor for a USD leg.
  static const double routeMinimumUsd = 1.0;

  /// The route's spread assumed when no estimate could be read (Orchestra's
  /// real spread on this leg is 1-3%).
  static const double fallbackSpread = 0.03;

  /// Room above the first quote's sats the approval allows for the one
  /// gross-up re-quote.
  static const double grossUpRoom = 0.05;

  static double _ceilCents(double usd) =>
      ((usd * 100) - 1e-9).ceilToDouble() / 100;

  /// What must land for [dollarsShortUsd]: that figure rounded up to the
  /// cent, never under [routeMinimumUsd]. No buffer: the order's move
  /// already carries the funding engine's, and the rest of the order comes
  /// from Dollars and the other venue's cash. Zero for no shortfall.
  static double targetUsd(double dollarsShortUsd,
      {double routeMinimumUsd = BitcoinLegRules.routeMinimumUsd}) {
    if (!dollarsShortUsd.isFinite || dollarsShortUsd <= 1e-6) return 0;
    final min = routeMinimumUsd.isFinite && routeMinimumUsd > 0
        ? routeMinimumUsd
        : 0.0;
    return _ceilCents(math.max(_ceilCents(dollarsShortUsd), min));
  }

  /// The X of "Add $X to Investments" when the person's bitcoin pays for
  /// it: what the TOTAL Investments balance ([investmentsUsd]: Dollars plus
  /// the other venue's reachable cash) lacks for the order's move
  /// ([fundUsd]), rounded up to the cent exactly as the button rounds it
  /// (`slipDollarsShortfallUsd`), never under the route minimum. Zero when
  /// Investments cover it. The slip shows this figure and the leg lands
  /// exactly it ([BitcoinLegPlan.targetUsd]).
  static double addUsd({
    required double fundUsd,
    required double investmentsUsd,
  }) {
    if (!fundUsd.isFinite || fundUsd <= 0) return 0;
    final held = investmentsUsd.isFinite && investmentsUsd > 0
        ? investmentsUsd
        : 0.0;
    final missing = fundUsd - held;
    if (missing <= 1e-6) return 0;
    return targetUsd(((missing * 100) - 1e-9).ceilToDouble() / 100);
  }

  /// The sats a leg landing [targetUsd] at [usdPerBtc] sends on
  /// [fallbackSpread]: what the route's estimate is asked about, before it
  /// gives its own spread. Zero without a price or a target.
  static int probeSats(double targetUsd, {required double usdPerBtc}) {
    if (!usdPerBtc.isFinite || usdPerBtc <= 0) return 0;
    if (!targetUsd.isFinite || targetUsd <= 0) return 0;
    return (targetUsd / usdPerBtc * 1e8 / (1 - fallbackSpread)).ceil();
  }

  /// The leg for [dollarsShortUsd] at [usdPerBtc] with [availableSats] of
  /// spending bitcoin. [estimate], when given, is the route's estimate of
  /// what a send of the asked sats lands (the sats are then scaled from
  /// it); otherwise [fallbackSpread] stands in. Refused when the price is
  /// unknown or the bitcoin does not cover the leg. A Spark to Spark send
  /// charges no network fee, so the sats are the whole cost.
  static BitcoinLegSizing size({
    required double dollarsShortUsd,
    required double usdPerBtc,
    required int availableSats,
    double routeMinimumUsd = 1.0,
    ({int sats, double estimatedOutUsd})? estimate,
  }) {
    if (!usdPerBtc.isFinite || usdPerBtc <= 0) {
      return const BitcoinLegSizing.refused(BitcoinLegRefusal.noPrice);
    }
    final target = targetUsd(dollarsShortUsd, routeMinimumUsd: routeMinimumUsd);
    if (target <= 0) {
      return const BitcoinLegSizing.refused(
          BitcoinLegRefusal.insufficientBitcoin);
    }
    var sats = probeSats(target, usdPerBtc: usdPerBtc);
    if (estimate != null &&
        estimate.sats > 0 &&
        estimate.estimatedOutUsd.isFinite &&
        estimate.estimatedOutUsd > 0) {
      // Scaled from the route's own price point, with the arrival
      // target's buffer.
      final perSat = estimate.estimatedOutUsd / estimate.sats;
      sats = (target / perSat * kArrivalTargetBuffer).ceil();
    }
    if (sats <= 0 || sats > availableSats) {
      return const BitcoinLegSizing.refused(
          BitcoinLegRefusal.insufficientBitcoin);
    }
    final maxSats =
        math.min(availableSats, (sats * (1 + grossUpRoom)).ceil());
    return BitcoinLegSizing.ok(BitcoinLegPlan(
      dollarsShortUsd: dollarsShortUsd,
      targetUsd: target,
      sats: sats,
      maxSats: maxSats,
      usdPerBtc: usdPerBtc,
    ));
  }
}

// ── Landing ────────────────────────────────────────────────────────────

/// How a watched Bitcoin leg ended.
sealed class DollarsLandingOutcome {
  const DollarsLandingOutcome();
}

/// The dollars are in. [freshDollarsUsd] is the freshest balance read.
final class DollarsLanded extends DollarsLandingOutcome {
  const DollarsLanded({required this.byStatus, required this.freshDollarsUsd});

  /// True when the order's status said so first, false for the balance.
  final bool byStatus;
  final double freshDollarsUsd;
}

/// Orchestra failed or refunded the leg: the bitcoin goes back home.
final class DollarsLegFailed extends DollarsLandingOutcome {
  const DollarsLegFailed(this.status);
  final String status;
}

/// Nothing within the wait: the leg may still land later, in Dollars.
final class DollarsLandingTimedOut extends DollarsLandingOutcome {
  const DollarsLandingTimedOut();
}

/// Statuses that mean the dollars were delivered.
const Set<String> kOrchestraDeliveredStatuses = {
  'completed',
  'complete',
  'success',
  'settled',
  'done',
};

/// Statuses that mean the leg failed (the bitcoin is refunded).
const Set<String> kOrchestraFailedStatuses = {
  'failed',
  'refunded',
  'refund',
  'expired',
  'cancelled',
  'canceled',
};

/// The order's status as Orchestra reports it, lowercase, or null when
/// nothing was learned (a transport error, no order yet).
Future<String?> orchestraLegStatus(String id) async {
  try {
    final result = await OrchestraService.getStatus(id)
        .timeout(const Duration(seconds: 5));
    final order = result.data;
    if (!result.isSuccess || order == null || order.orderMissing) return null;
    final status = order.status.trim().toLowerCase();
    return status.isEmpty ? null : status;
  } catch (_) {
    return null;
  }
}

/// Watches one Bitcoin → Dollars leg until its dollars land. See the file
/// header. Every dependency is a function so the timing is testable.
class DollarsLandingWatcher {
  DollarsLandingWatcher({
    required this.statusOf,
    required this.dollarsNow,
    required this.freshDollars,
    required this.kickSync,
    this.dollarsChanges,
    this.pollEvery = const Duration(seconds: 1),
    this.freshEvery = const Duration(milliseconds: 300),
    this.freshFor = const Duration(seconds: 60),
    this.slowAfter = const Duration(minutes: 2),
    this.maxWait = const Duration(minutes: 12),
  });

  /// The order's status (see [orchestraLegStatus]).
  final Future<String?> Function(String id) statusOf;

  /// The dollar balance the app shows now.
  final double Function() dollarsNow;

  /// The dollar balance read fresh from the wallet, or null.
  final Future<double?> Function() freshDollars;

  /// Asks the wallet to sync its dollars; never awaited.
  final void Function() kickSync;

  /// Each new dollar balance the app shows, when it can say.
  final Stream<double>? dollarsChanges;

  final Duration pollEvery;
  final Duration freshEvery;
  final Duration freshFor;
  final Duration slowAfter;
  final Duration maxWait;

  /// Waits for the leg whose current id [id] gives (the quote id, then the
  /// order id once registered). Landed when the status reports delivery
  /// or the balance rose by [minRiseUsd] over [baselineUsd] (or reached
  /// [enoughUsd]); then the wallet is asked to sync (not awaited) and the
  /// fresh balance is read until it shows the dollars (at most
  /// [freshFor]). [onSlow] runs once after [slowAfter].
  Future<DollarsLandingOutcome> watch({
    required String Function() id,
    required double baselineUsd,
    required double minRiseUsd,
    required double enoughUsd,
    void Function()? onSlow,
  }) {
    final done = Completer<DollarsLandingOutcome>();
    var elapsed = Duration.zero;
    var slowFired = false;
    var signalled = false;
    var polling = false;
    Timer? ticker;
    StreamSubscription<double>? changes;

    bool arrived(double usd) =>
        usd.isFinite &&
        (usd + 1e-6 >= enoughUsd || usd - baselineUsd + 1e-6 >= minRiseUsd);

    void finish(DollarsLandingOutcome outcome) {
      if (done.isCompleted) return;
      ticker?.cancel();
      unawaited(changes?.cancel());
      done.complete(outcome);
    }

    Future<void> confirmFresh(bool byStatus) async {
      // The status (or the shown balance) says the money is in; the
      // controller reads the balance, so wait until the wallet's own
      // cache shows it too.
      try {
        kickSync();
      } catch (_) {}
      var best = dollarsNow();
      var waited = Duration.zero;
      while (!done.isCompleted) {
        double? fresh;
        try {
          fresh = await freshDollars();
        } catch (_) {
          fresh = null;
        }
        if (fresh != null && fresh > best) best = fresh;
        final shown = dollarsNow();
        if (shown > best) best = shown;
        if (arrived(best) || waited >= freshFor) {
          finish(DollarsLanded(byStatus: byStatus, freshDollarsUsd: best));
          return;
        }
        await Future<void>.delayed(freshEvery);
        waited += freshEvery;
      }
    }

    void signal(bool byStatus) {
      if (signalled || done.isCompleted) return;
      signalled = true;
      unawaited(confirmFresh(byStatus));
    }

    Future<void> tick() async {
      elapsed += pollEvery;
      if (!slowFired && elapsed >= slowAfter) {
        slowFired = true;
        try {
          onSlow?.call();
        } catch (_) {}
      }
      if (elapsed >= maxWait) {
        finish(const DollarsLandingTimedOut());
        return;
      }
      if (signalled) return;
      if (arrived(dollarsNow())) {
        signal(false);
        return;
      }
      if (polling) return;
      polling = true;
      try {
        final status = await statusOf(id());
        if (status != null && !done.isCompleted && !signalled) {
          if (kOrchestraDeliveredStatuses.contains(status)) {
            signal(true);
          } else if (kOrchestraFailedStatuses.contains(status)) {
            finish(DollarsLegFailed(status));
          }
        }
      } finally {
        polling = false;
      }
    }

    changes = dollarsChanges?.listen((usd) {
      if (!signalled && arrived(usd)) signal(false);
    });
    ticker = Timer.periodic(pollEvery, (_) => unawaited(tick()));
    // The first read right away: a fast leg may be in already.
    if (arrived(dollarsNow())) signal(false);
    return done.future;
  }
}
