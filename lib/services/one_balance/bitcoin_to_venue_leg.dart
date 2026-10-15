// lib/services/one_balance/bitcoin_to_venue_leg.dart
//
// Bitcoin straight into the venue (founder decision 15 October 2026: "it
// should go directly into polymarket or hyperliquid if i am there already
// and i have no usdb balance"). An order that needs Bitcoin sends it in
// ONE Orchestra order from `spark:BTC` to the wallet's own venue deposit:
//
//   * Predictions: `spark:BTC → polygon:USDC.e` to the own deposit wallet
//     (the route the Move sheet's Bitcoin → Predictions door uses), the
//     Activity row written the same way, so the background sync's
//     delivered-wrap to pUSD (`predictionsDepositNeedsWrap` →
//     `onDepositDelivered`) fires for it;
//   * Investing: `spark:BTC → hypercore:USDC` to the own Investing account
//     (`SparkHypercoreFundingService.depositFromSpark`, the route the Move
//     sheet's Bitcoin → Investing door uses).
//
// [planDirectBitcoinLeg] decides, BEFORE anything moves, whether the
// direct leg goes or the order takes the via-Dollars chain: it sizes the
// leg exactly (what Dollars and the other venue's cash do not bring, plus
// the route's spread and the arrival buffer), folds a share under the
// route's minimum, and picks direct only when it costs the person no more
// than the chain (the founder's rule: Bitcoin → Investments costs the
// same as Bitcoin → Dollars). [BitcoinToVenueLeg.send] pays only a
// verified quote the order's one approval covers
// (`BitcoinLegGrants.stepUpDirect`, single use, the own deposit pinned).
//
// No ids or addresses reach analytics from here.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable, visibleForTesting;
import 'package:kute/helpers/orchestra_router.dart'
    show orchestraAmountToDouble;
import 'package:kute/models/affiliate_model.dart' show AffiliateService;
import 'package:kute/models/orchestra_model.dart' show OrchestraEstimate;
import 'package:kute/models/orchestra_routes_model.dart' show RouteKey;
import 'package:kute/models/settlement_operation.dart'
    show SettlementAccountKind, SettlementFlow;
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/polymarket_trading_provider.dart'
    show polymarketTradingProvider;
import 'package:kute/providers/settings_provider.dart' show settingsProvider;
import 'package:kute/providers/swap_orders_provider.dart'
    show swapOrdersProvider;
import 'package:kute/providers/transactions_provider.dart'
    show walletTransactionCacheProvider;
import 'package:kute/services/api/orchestra_api.dart' show OrchestraService;
import 'package:kute/services/background_sync_service.dart';
import 'package:kute/services/funding/hot_settlement.dart';
import 'package:kute/services/funding/owned_address_resolver.dart'
    show ProviderReader;
import 'package:kute/services/funding/settlement_registration.dart'
    show followSettlementRegistration;
import 'package:kute/services/funding/settlement_runner.dart'
    show SettlementFundingProof, SettlementQuoteResult, SettlementStepUpHook;
import 'package:kute/services/funding/spark_hypercore_funding_service.dart'
    show
        SparkFundingAsset,
        kSparkToHypercoreRoute,
        sparkHypercoreFundingServiceProvider;
import 'package:kute/services/one_balance/bitcoin_to_dollars_leg.dart'
    show BitcoinLegPlan, kOrchestraDeliveredStatuses, kOrchestraFailedStatuses;
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/predictions_venue_funder.dart'
    show predictionsQuoteTag;
import 'package:kute/services/orchestra/arrival_target.dart';
import 'package:kute/services/orchestra/orchestra_quote_guard.dart'
    show OrchestraQuoteRequest, RecipientKind;
import 'package:kute/services/polymarket_spark_txs_service.dart';
import 'package:kute/services/tracking_service.dart';

/// The direct route into [venue].
RouteKey directBitcoinRouteOf(OneBalanceVenue venue) => switch (venue) {
      OneBalanceVenue.predictions => RouteKey(
          fromChain: 'spark',
          fromAsset: 'BTC',
          toChain: 'polygon',
          toAsset: 'USDC.e'),
      OneBalanceVenue.investing => kSparkToHypercoreRoute,
    };

/// The Orchestra quote `flow` of a direct leg, so the backend can tell it
/// from the Move sheet's door.
const String kOrderFundingBitcoinDirectFlow = 'order_funding_bitcoin_direct';

// ── The decision ──────────────────────────────────────────────────────

/// Why an order that needs Bitcoin takes the via-Dollars chain instead of
/// the direct leg. Fixed codes, sent as `route_reason`.
abstract final class DirectBitcoinReason {
  static const String noAddress = 'no_own_deposit';
  static const String refusedRecently = 'refused_recently';
  static const String noEstimate = 'estimate_unavailable';
  static const String costlier = 'costlier';
  static const String overCap = 'over_cap';
  static const String belowMinimum = 'below_minimum';
}

/// The legs of an order that needs Bitcoin, decided before the approval
/// is used and before anything moves.
@immutable
class DirectBitcoinPlan {
  const DirectBitcoinPlan.direct({
    required this.targetUsd,
    required this.sats,
    required this.dollarsUsd,
    required this.bitcoinShareUsd,
    required this.otherUsd,
    required this.directCostUsd,
    required this.viaCostUsd,
    this.folded = false,
  })  : route = 'direct',
        reason = null;

  const DirectBitcoinPlan.viaDollars(this.reason,
      {this.directCostUsd, this.viaCostUsd})
      : route = 'via_dollars',
        targetUsd = 0,
        sats = 0,
        dollarsUsd = 0,
        bitcoinShareUsd = 0,
        otherUsd = 0,
        folded = false;

  /// `direct` or `via_dollars`.
  final String route;
  bool get direct => route == 'direct';

  /// Why the chain ([DirectBitcoinReason]); null for direct.
  final String? reason;

  /// What the direct leg lands in the venue, in dollars.
  final double targetUsd;

  /// The sats the direct leg sends (the route's spread and the arrival
  /// buffer included).
  final int sats;

  /// What Dollars send to the venue next to it (zero when Bitcoin covers
  /// the Dollars' share too).
  final double dollarsUsd;

  /// What the venue move from Dollars ([fundUsd] in the slip's terms) no
  /// longer needs to carry because the Bitcoin leg brings it.
  final double bitcoinShareUsd;

  /// What the other venue's cash gives.
  final double otherUsd;

  /// The whole cost of each mix in dollars (sats at the wallet's price
  /// plus the Dollars spent), as compared.
  final double? directCostUsd;
  final double? viaCostUsd;

  /// The Bitcoin share was raised to the route's minimum.
  final bool folded;

  @override
  String toString() => 'DirectBitcoinPlan($route, target: $targetUsd, '
      'sats: $sats, dollars: $dollarsUsd, other: $otherUsd'
      '${reason == null ? '' : ', $reason'})';
}

double _ceilCents(double usd) => ((usd * 100) - 1e-9).ceilToDouble() / 100;

/// The rule (pure apart from the reads it is given):
///
///  1. What must land in the venue ([fundUsd] is the slip's move from
///     Dollars, so the venue's own estimate says what that move lands).
///  2. Dollars give `D = min(Dollars held, fundUsd - X)` (X is the slip's
///     Bitcoin figure in Dollars terms); the other venue gives what is
///     left (`fundUsd - X - D`, its legs land about one for one).
///  3. The direct leg lands the rest: `T = need - lands(D) - other`.
///  4. Under the direct route's minimum, T is raised to the minimum and
///     Dollars send that much less; a Dollars share left under its own
///     route minimum is dropped and Bitcoin covers it too (no Dollars
///     needed). Still under the minimum: the chain.
///  5. Sized on the route's own estimate (net of Kute's fee when the
///     estimate leaves it out) with the arrival buffer.
///  6. Direct only when its whole cost (its sats plus the Dollars it uses)
///     is no more than the chain's (the via leg's sats plus Dollars), and
///     the sats fit the approval's direct cap and the wallet.
Future<DirectBitcoinPlan> planDirectBitcoinLeg({
  required double fundUsd,
  required double addUsd,
  required double dollarsUsd,
  required BitcoinLegPlan via,
  required int availableSats,
  required int directMaxSats,
  required Future<double?> Function(double usd) venueArriving,
  required Future<double?> Function(int sats) directOutUsd,
  required Future<double> Function() directMinimumUsd,
  required double dollarsMinimumUsd,
}) async {
  final price = via.usdPerBtc;
  if (!price.isFinite || price <= 0) {
    return const DirectBitcoinPlan.viaDollars(DirectBitcoinReason.noEstimate);
  }
  final held = dollarsUsd.isFinite && dollarsUsd > 0 ? dollarsUsd : 0.0;
  final x = addUsd > 0 ? addUsd : via.targetUsd;
  var d = _ceilCents(math.min(held, math.max(0.0, fundUsd - x)));
  if (d > held) d = (held * 100).floorToDouble() / 100;
  final other = _ceilCents(math.max(0.0, fundUsd - x - d));

  // The reads, together.
  final probe = via.sats;
  final reads = await Future.wait<Object?>([
    venueArriving(fundUsd),
    d > 0 ? venueArriving(d) : Future<double?>.value(0),
    directOutUsd(probe),
    directMinimumUsd(),
  ]);
  final need = reads[0] as double?;
  var dLands = reads[1] as double?;
  final probeOut = reads[2] as double?;
  final minimum = (reads[3] as double?) ?? 1.0;
  if (need == null ||
      !need.isFinite ||
      need <= 0 ||
      dLands == null ||
      probeOut == null ||
      !probeOut.isFinite ||
      probeOut <= 0 ||
      probe <= 0) {
    return const DirectBitcoinPlan.viaDollars(DirectBitcoinReason.noEstimate);
  }
  var target = _ceilCents(math.max(0.01, need - dLands - other));
  var folded = false;
  if (target < minimum) {
    folded = true;
    final raise = minimum - target;
    target = _ceilCents(minimum);
    if (d > 0) {
      var nextD = _ceilCents(math.max(0.0, d - raise));
      if (nextD > 0 && nextD < dollarsMinimumUsd) nextD = 0;
      if (nextD <= 0) {
        // Bitcoin covers the Dollars' share as well.
        d = 0;
        dLands = 0;
        target = _ceilCents(math.max(minimum, need - other));
      } else {
        final lands = await venueArriving(nextD);
        if (lands == null) {
          return const DirectBitcoinPlan.viaDollars(
              DirectBitcoinReason.noEstimate);
        }
        d = nextD;
        dLands = lands;
        target = _ceilCents(math.max(minimum, need - lands - other));
      }
    }
  }
  if (target < minimum - 1e-9) {
    return const DirectBitcoinPlan.viaDollars(DirectBitcoinReason.belowMinimum);
  }
  final perSat = probeOut / probe;
  final sats = (target / perSat * kArrivalTargetBuffer).ceil();
  final viaD = _ceilCents(math.min(held, math.max(0.0, fundUsd - x)));
  final directCost = sats / 1e8 * price + d;
  final viaCost = via.sats / 1e8 * price + viaD;
  if (directCost > viaCost + 1e-9) {
    return DirectBitcoinPlan.viaDollars(DirectBitcoinReason.costlier,
        directCostUsd: directCost, viaCostUsd: viaCost);
  }
  if (sats <= 0 || sats > directMaxSats || sats > availableSats) {
    return DirectBitcoinPlan.viaDollars(DirectBitcoinReason.overCap,
        directCostUsd: directCost, viaCostUsd: viaCost);
  }
  return DirectBitcoinPlan.direct(
    targetUsd: target,
    sats: sats,
    dollarsUsd: d,
    bitcoinShareUsd: _ceilCents(math.max(0.0, fundUsd - d - other)),
    otherUsd: other,
    directCostUsd: directCost,
    viaCostUsd: viaCost,
    folded: folded,
  );
}

/// The most sats the approval lets a direct leg send: the via leg's cap
/// plus room for a share raised to the route's minimum (4. above).
int directMaxSatsFor(BitcoinLegPlan via, {double foldRoomUsd = 5.0}) {
  if (!via.usdPerBtc.isFinite || via.usdPerBtc <= 0) return via.maxSats;
  return via.maxSats + (foldRoomUsd / via.usdPerBtc * 1e8 * 1.05).ceil();
}

/// What a direct send of [sats] lands, net of Kute's fee when the
/// estimate leaves it out, from Orchestra's estimate for the route into
/// [venue] naming the own deposit [ownVenue] (the Investing activation is
/// priced in when the account is new). Null when it does not answer.
Future<double?> directBitcoinEstimate(OneBalanceVenue venue, int sats,
    {required String ownVenue}) async {
  final seam = debugDirectBitcoinEstimate;
  if (seam != null) return seam(venue, sats);
  if (sats <= 0) return null;
  try {
    final route = directBitcoinRouteOf(venue);
    final result = await OrchestraService.getEstimate(
      sourceChain: route.fromChain,
      sourceAsset: route.fromAsset,
      destinationChain: route.toChain,
      destinationAsset: route.toAsset,
      amount: sats.toString(),
      recipientAddress: ownVenue,
    ).timeout(const Duration(seconds: 4));
    final OrchestraEstimate? est = result.data;
    if (est == null) return null;
    final out = orchestraAmountToDouble(est.estimatedOut, route.toAsset,
        chain: route.toChain);
    if (!out.isFinite || out <= 0) return null;
    if (est.estimateIncludesAppFee == true) return out;
    final bps = est.kuteAppFeeBps ?? 0;
    if (bps < 0 || bps >= 10000) return null;
    return out * (1 - bps / 10000);
  } catch (_) {
    return null;
  }
}

/// Test seam for [directBitcoinEstimate].
@visibleForTesting
Future<double?> Function(OneBalanceVenue venue, int sats)?
    debugDirectBitcoinEstimate;

/// The direct route's minimum in dollars: Orchestra's `/limits` for it,
/// never under the app's $1 floor. The floor when the read fails.
Future<double> directBitcoinMinimumUsd(OneBalanceVenue venue) async {
  final seam = debugDirectBitcoinMinimum;
  if (seam != null) return seam(venue);
  try {
    final limits =
        await OrchestraService.getRouteLimits(directBitcoinRouteOf(venue))
            .timeout(const Duration(seconds: 4));
    final cents = <int?>[limits?.orderMinUsdCents, limits?.exactInMinUsdCents]
        .whereType<int>()
        .where((c) => c > 0);
    if (cents.isEmpty) return 1.0;
    return math.max(1.0, cents.reduce(math.max) / 100);
  } catch (_) {
    return 1.0;
  }
}

/// Test seam for [directBitcoinMinimumUsd].
@visibleForTesting
Future<double> Function(OneBalanceVenue venue)? debugDirectBitcoinMinimum;

// ── The send ──────────────────────────────────────────────────────────

/// What the direct leg handed back once its sats left.
@immutable
class DirectLegSent {
  const DirectLegSent({
    required this.quoteId,
    required this.sats,
    required this.estimatedOutUsd,
    this.orderId,
    this.registration,
  });

  final String quoteId;
  final String? orderId;
  final Future<String?>? registration;
  final int sats;

  /// What the quote said lands in the venue.
  final double estimatedOutUsd;
}

/// The direct leg's send, as a function so tests stand in for it.
/// [stepUp] approves the verified quote ([BitcoinLegGrants.stepUpDirect]);
/// [onSending] runs right before the payment.
typedef DirectLegSend = Future<DirectLegSent> Function({
  required OneBalanceVenue venue,
  required String ownVenue,
  required String ownSpark,
  required int sats,
  required double targetUsd,
  required SettlementStepUpHook stepUp,
  required void Function() onSending,
});

abstract final class BitcoinToVenueLeg {
  /// The live send. Throws whatever the settlement throws: a refusal, a
  /// quote failure or a wallet guard BEFORE anything moved (the caller
  /// falls back to the via-Dollars chain), a `SettlementFundingUnknown`
  /// when the payment's outcome is unknown.
  static DirectLegSend live(ProviderReader read) => ({
        required OneBalanceVenue venue,
        required String ownVenue,
        required String ownSpark,
        required int sats,
        required double targetUsd,
        required SettlementStepUpHook stepUp,
        required void Function() onSending,
      }) =>
          switch (venue) {
            OneBalanceVenue.predictions => _toPredictions(read,
                evm: ownVenue,
                ownSpark: ownSpark,
                sats: sats,
                targetUsd: targetUsd,
                stepUp: stepUp,
                onSending: onSending),
            OneBalanceVenue.investing => _toInvesting(read,
                sats: sats,
                targetUsd: targetUsd,
                stepUp: stepUp,
                onSending: onSending),
          };

  static Future<DirectLegSent> _toInvesting(
    ProviderReader read, {
    required int sats,
    required double targetUsd,
    required SettlementStepUpHook stepUp,
    required void Function() onSending,
  }) async {
    // The Move sheet's own Bitcoin → Investing route, under the order's
    // grant: the service resolves the own account, writes the Activity
    // row and refuses an unavailable route before anything moves.
    final result =
        await read(sparkHypercoreFundingServiceProvider).depositFromSpark(
      asset: SparkFundingAsset.bitcoin,
      amountBaseUnits: BigInt.from(sats),
      amountUsd: targetUsd,
      stepUp: stepUp,
      onFundingStarted: onSending,
      registerInBackground: true,
      purpose: 'order_funding',
    );
    return DirectLegSent(
      quoteId: result.run.quote.quoteId,
      orderId: result.run.orderId,
      registration: result.run.registration,
      sats: result.amountIn.toInt(),
      estimatedOutUsd: result.estimatedOut,
    );
  }

  static Future<DirectLegSent> _toPredictions(
    ProviderReader read, {
    required String evm,
    required String ownSpark,
    required int sats,
    required double targetUsd,
    required SettlementStepUpHook stepUp,
    required void Function() onSending,
  }) async {
    final route = directBitcoinRouteOf(OneBalanceVenue.predictions);
    TrackingService.polymarketDepositInitiated(
      route: 'btc_spending',
      amountUsd: targetUsd,
      entrySource: 'order_funding',
      walletKind: 'hot',
    );
    Future<SettlementQuoteResult> quoteFor(int amount, String key) =>
        HotSettlement.quote(
          read,
          OrchestraQuoteRequest(
            sourceChain: route.fromChain,
            sourceAsset: route.fromAsset,
            destinationChain: route.toChain,
            destinationAsset: route.toAsset,
            amountBaseUnits: BigInt.from(amount),
            recipientAddress: evm,
            refundAddress: ownSpark,
            recipientKind: RecipientKind.ownPmWallet,
            ownAddress: evm,
            tag: predictionsQuoteTag('order_funding'),
          ),
          flow: kOrderFundingBitcoinDirectFlow,
          idempotencyKey: key,
        );
    String? pendingRowId;
    var sent = false;
    final runner = await HotSettlement.runner();
    try {
      final settled = await runner.run(HotSettlement.plan(
        read,
        flow: SettlementFlow.moveBtcToPredictions,
        route: route,
        source: SettlementAccountKind.sparkHot,
        destination: SettlementAccountKind.pmHot,
        amountUsd: targetUsd,
        stepUp: stepUp,
        requestQuote: (key) async {
          var fetched = await quoteFor(sats, key);
          final out = orchestraAmountToDouble(
              fetched.quote.quote.estimatedOut, route.toAsset,
              chain: route.toChain);
          if (arrivalTargetShort(out, targetUsd)) {
            final scaled = grossUpSatsForTarget(
                sats: sats,
                estimatedOut: out,
                targetUsd: targetUsd,
                maxSats: (sats * 1.05).ceil());
            if (scaled > sats) {
              fetched = await quoteFor(
                  scaled, OrchestraService.generateIdempotencyKey());
            }
          }
          return fetched;
        },
        prepareFunding: (verified, operationId) async {
          final stale = pendingRowId;
          if (stale != null && stale != verified.quote.quoteId) {
            await read(swapOrdersProvider.notifier).deleteExchange(stale);
          }
          // The Activity row exists before any money moves.
          await read(swapOrdersProvider.notifier).addExchange(predictionsRow(
            id: verified.quote.quoteId,
            depositAddress: verified.quote.depositAddress,
            sats: verified.amountIn.toInt(),
            estimatedOut: verified.quote.estimatedOut,
            evm: evm,
            ownSpark: ownSpark,
            walletId: read(settingsProvider).activeWalletId,
            operationId: operationId,
          ));
          pendingRowId = verified.quote.quoteId;
          return HotSettlement.prepareSpark(read, verified);
        },
        registerInBackground: true,
        fund: (verified, prepared) async {
          sent = true;
          onSending();
          final paymentId = await HotSettlement.sendSpark(read, prepared);
          PolymarketSparkTxsService.tag(paymentId);
          return SettlementFundingProof.spark(paymentId);
        },
      ));
      final quote = settled.quote.quote;
      final orderId = settled.orderId ?? quote.quoteId;
      final sentSats = settled.quote.amountIn.toInt();
      final row = predictionsRow(
        id: orderId,
        depositAddress: quote.depositAddress,
        sats: sentSats,
        estimatedOut: quote.estimatedOut,
        evm: evm,
        ownSpark: ownSpark,
        walletId: read(settingsProvider).activeWalletId,
        operationId: settled.operation.operationId,
      );
      await read(swapOrdersProvider.notifier).addExchange(row);
      if (orderId != quote.quoteId) {
        await read(swapOrdersProvider.notifier).deleteExchange(quote.quoteId);
      }
      followSettlementRegistration(read, settled);
      final estOut = orchestraAmountToDouble(quote.estimatedOut, route.toAsset,
          chain: route.toChain);
      if (orderId.startsWith('ord_')) {
        // ignore: unawaited_futures
        AffiliateService.logProviderEvent(
          provider: 'orchestra',
          providerOrderId: orderId,
          status: 'pending',
          sourceAsset: 'BTC',
          sourceAmount: sentSats / 1e8,
          destinationAsset: 'USDC',
          destinationAmount: estOut,
        );
      }
      try {
        read(walletTransactionCacheProvider.notifier).mergeSwapOrder(row);
      } catch (_) {}
      BackgroundSyncService().syncNow();
      // The delivered USDC.e is converted to pUSD by the background sync
      // once the order completes (`predictionsDepositNeedsWrap`); the
      // incoming watch converts it as soon as it shows.
      read(polymarketTradingProvider.notifier).wrapIncomingUsdcEToPusd();
      return DirectLegSent(
        quoteId: quote.quoteId,
        orderId: settled.orderId,
        registration: settled.registration,
        sats: sentSats,
        estimatedOutUsd: estOut,
      );
    } catch (e) {
      final stale = pendingRowId;
      if (!sent && stale != null) {
        // ignore: unawaited_futures
        read(swapOrdersProvider.notifier).deleteExchange(stale);
      }
      rethrow;
    }
  }

  /// The Activity row of a direct Bitcoin → Predictions leg: the shape the
  /// Move sheet's door writes, which the background sync recognises as a
  /// Predictions deposit (`isPredictionsDepositOrder`) and converts to
  /// pUSD once delivered.
  static SwapOrder predictionsRow({
    required String id,
    required String depositAddress,
    required int sats,
    required String estimatedOut,
    required String evm,
    required String ownSpark,
    required String? walletId,
    required String operationId,
  }) {
    final out =
        orchestraAmountToDouble(estimatedOut, 'USDC.e', chain: 'polygon');
    return SwapOrder(
      id: id,
      coinFrom: 'BTC',
      networkFrom: 'SPARK',
      coinTo: 'USDC',
      networkTo: 'POLYGON',
      depositAddress: depositAddress,
      depositAmount: (sats / 1e8).toStringAsFixed(8),
      withdrawalAmount: out.toStringAsFixed(2),
      status: 'exchanging',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      withdrawalAddress: evm,
      depositMin: '0',
      depositMax: '0',
      rate: '0',
      refundAddress: ownSpark,
      provider: 'Orchestra',
      walletId: walletId,
      operationId: operationId,
    );
  }
}

// ── Delivery ──────────────────────────────────────────────────────────

/// How a watched Orchestra leg ended.
enum LegDelivery { delivered, failed, timedOut }

/// Follows one Orchestra leg ([id] gives its current id: the quote id,
/// then the order id once registered) until Orchestra reports it
/// delivered or failed, or [maxWait] passes. [onSlow] runs once after
/// [slowAfter].
Future<LegDelivery> watchLegDelivery({
  required String Function() id,
  required Future<String?> Function(String id) statusOf,
  Duration pollEvery = const Duration(seconds: 1),
  Duration slowAfter = const Duration(minutes: 2),
  Duration maxWait = const Duration(minutes: 12),
  void Function()? onSlow,
}) async {
  var waited = Duration.zero;
  var slow = false;
  while (waited < maxWait) {
    final status = await statusOf(id());
    if (status != null) {
      if (kOrchestraDeliveredStatuses.contains(status)) {
        return LegDelivery.delivered;
      }
      if (kOrchestraFailedStatuses.contains(status)) return LegDelivery.failed;
    }
    await Future<void>.delayed(pollEvery);
    waited += pollEvery;
    if (!slow && waited >= slowAfter) {
      slow = true;
      try {
        onSlow?.call();
      } catch (_) {}
    }
  }
  return LegDelivery.timedOut;
}
