// lib/services/one_balance/hyperliquid_move_rail.dart
//
// The rail between Dollars and Investing, as the one-balance layer sees
// it. Investing's `VenueFunder`, the order slip and the sweeper call this
// and nothing else, so swapping the rail underneath changes one binding
// line in this file.
//
// The binding is `HyperCoreMoveRail`: the direct HyperCore routes through
// Orchestra, run by `SparkHypercoreFundingService`.
//
//  - In: `spark:USDB → hypercore:USDC`, delivered to the Investing
//    account itself.
//  - Out: `hypercore:USDC → spark:USDB`, a perpetuals `usdSend` to the
//    quote's HyperCore deposit address, delivered to the own Spark
//    address.
//
// Flashnet refuses every HyperCore-source route today (`unsupported_route`,
// "HyperCore source routes require independent deposit verification and
// are unavailable"). The refusal arrives with the quote, before anything
// is signed or sent. A withdrawal to Dollars then falls back to Circle
// CCTP out of HyperCore (lib/services/hyperliquid/cctp_withdrawal.dart):
// one `sendToEvmWithData` to the wallet's own Investing-withdrawal
// standing address on Arbitrum, which Orchestra converts to dollars. Only
// when that cannot run either (paused, below the minimum, the fee terms
// not verified, a failed read, the runtime policy withholding
// `hyperliquid.withdraw`) the rail reports `RouteUnavailable`: the
// sweeper shows the cash as waiting, backs off and tries again later;
// nothing moves until the fallback can run.

import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/helpers/auth_grant.dart' show AuthGrants, SensitiveAction;
import 'package:kute/helpers/orchestra_router.dart'
    show doubleToOrchestraAmount, orchestraAmountToDouble;
import 'package:kute/helpers/venue_intents.dart' show OrchestraGrants;
import 'package:kute/models/orchestra_model.dart' show OrchestraEstimate;
import 'package:kute/models/orchestra_route_limits.dart'
    show RouteQuoteError, RouteQuoteErrorCode;
import 'package:kute/models/orchestra_routes_model.dart' show RouteKey;
import 'package:kute/providers/hyperliquid_account_provider.dart'
    show hyperliquidAddressProvider;
import 'package:kute/providers/hyperliquid_markets_provider.dart'
    show hyperliquidTradingModelProvider;
import 'package:kute/providers/spark_address_provider.dart'
    show sparkSelfAddressProvider;
import 'package:kute/services/api/orchestra_api.dart';
import 'package:kute/services/funding/owned_address_resolver.dart'
    show ProviderReader;
import 'package:kute/services/funding/settlement_runner.dart'
    show
        SettlementAuthorizationIntent,
        SettlementStepUpHook,
        SettlementStopReason,
        SettlementStopped;
import 'package:kute/services/funding/spark_hypercore_funding_service.dart';
import 'package:kute/services/hyperliquid/cctp_withdrawal.dart'
    show CctpUnavailable, HypercoreCctpWithdrawal, hypercoreCctpWithdrawalProvider;
import 'package:kute/services/hyperliquid/hypercore_cash.dart'
    show hypercoreSendableUsdc;
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/orchestra/orchestra_fee_amount.dart';
import 'package:kute/services/orchestra/orchestra_quote_gate.dart'
    show OrchestraQuoteFailure;
import 'package:kute/services/security/wallet_guard_exception.dart';
import 'package:kute/services/tracking_service.dart';

/// Orchestra's floor on the direct HyperCore routes (its `/limits` for
/// `spark:USDB → hypercore:USDC`, read 2026-10-13: `minUsdCents` 80). The
/// live limits are asked first; this is the answer when they are
/// unreachable or list no route.
const double kHyperCoreMinMoveUsd = 0.80;

/// The ceiling when the live limits are unreachable.
const double kHyperCoreMaxMoveUsd = 96700;

/// Live route bounds in dollars.
typedef HyperCoreRouteBounds = ({double? minUsd, double? maxUsd});

abstract interface class HyperliquidMoveRail {
  /// Sends dollars from the spending account into the Investing venue.
  ///
  /// [amountBaseUnits] is the dollar token's six-decimal base units, the
  /// exact figure the send is made with; [usd] is the same money as a
  /// dollar figure for the record. [stepUp] asks the user for the fresh
  /// grant the settlement needs; [purpose] is recorded with the move.
  Future<VenueMoveResult> depositDollars({
    required double usd,
    required BigInt amountBaseUnits,
    SettlementStepUpHook? stepUp,
    String purpose = 'order_funding',
  });

  /// Brings venue cash back to the dollar token.
  Future<VenueMoveResult> withdrawToDollars({
    required double usd,
    required MoveAuthorization auth,
    String purpose = 'sweep',
  });

  /// Venue cash that could leave right now.
  Future<double> withdrawableUsd();

  /// What a move of [usd] would cost and deliver in the given direction.
  Future<VenueMoveQuote> estimate({required double usd, required bool deposit});

  /// Smallest move the rail accepts in the given direction.
  Future<double> minimumUsd({required bool deposit});

  /// Makes sure the rail holds enough of its own gas to carry the next
  /// move. A no-op on rails that pay fees out of the moved amount.
  Future<void> ensureGasFloat();

  /// Fires once per move the venue has credited, so the slip waiting on a
  /// deposit can place its order without polling.
  Stream<void> get credited;
}

/// The direct HyperCore rail through Orchestra.
///
/// Deposits delegate to `SparkHypercoreFundingService.depositFromSpark`
/// with the dollar token as the funding asset, withdrawals to
/// `withdrawToSpark` pointed at the dollar token, both with background
/// registration on so the result's `registration` future is the one the
/// settlement runner hands back. The quote tag follows [purpose]
/// (`kute:order_funding_investing`, `kute:sweep_investing`, …).
class HyperCoreMoveRail implements HyperliquidMoveRail {
  HyperCoreMoveRail(
    this._read, {
    Future<OrchestraEstimate?> Function(
            RouteKey route, String amount, String? recipient)?
        estimate,
    Future<HyperCoreRouteBounds?> Function(RouteKey route)? limits,
    Future<double> Function(String address)? sendableUsd,
    HypercoreCctpWithdrawal Function()? cctp,
  })  : _estimate = estimate ?? _estimateNative,
        _limits = limits ?? _limitsNative,
        _sendableUsd = sendableUsd,
        _cctpOverride = cctp;

  final ProviderReader _read;

  /// Orchestra's estimate for the route, the amount and the address the
  /// move's quote names ([_recipient]).
  final Future<OrchestraEstimate?> Function(
      RouteKey route, String amount, String? recipient) _estimate;
  final Future<HyperCoreRouteBounds?> Function(RouteKey route) _limits;
  final Future<double> Function(String address)? _sendableUsd;
  final HypercoreCctpWithdrawal Function()? _cctpOverride;

  HypercoreCctpWithdrawal get _cctp =>
      _cctpOverride?.call() ?? _read(hypercoreCctpWithdrawalProvider);

  SparkHypercoreFundingService get _service =>
      _read(sparkHypercoreFundingServiceProvider);

  static RouteKey _route({required bool deposit}) =>
      deposit ? kSparkUsdToHypercoreRoute : kHypercoreToSparkUsdRoute;

  @override
  Future<VenueMoveResult> depositDollars({
    required double usd,
    required BigInt amountBaseUnits,
    SettlementStepUpHook? stepUp,
    String purpose = 'order_funding',
  }) async {
    // The purpose picks the quote's provider tag (an order's funding leg,
    // a sweep); the Activity row the service writes already reads as an
    // Investing deposit.
    final result = await _refusalsAsRoute(() => _service.depositFromSpark(
          asset: SparkFundingAsset.dollars,
          amountBaseUnits: amountBaseUnits,
          amountUsd: usd,
          stepUp: stepUp,
          registerInBackground: true,
          purpose: purpose,
        ));
    return VenueMoveResult(
      quoteId: result.run.quote.quoteId,
      orderId: result.run.orderId,
      registration: result.run.registration,
      sentUsd: usd,
      arrivingUsdEstimate: result.estimatedOut,
    );
  }

  /// Reports the same Investing withdrawal funnel as the Move sheet's
  /// cash-out, with [purpose] (`sweep`, `rollout_sweep`) as who started
  /// it: one `hyperliquid_withdraw_initiated` (route `direct`), the
  /// `cctp_fallback` step when Orchestra refuses the route, one
  /// `hyperliquid_withdraw_submitted` with the route the money took, and
  /// `hyperliquid_withdraw_failed` when the attempt stops before that.
  /// The settlement watchers report completed/failed after submission.
  @override
  Future<VenueMoveResult> withdrawToDollars({
    required double usd,
    required MoveAuthorization auth,
    String purpose = 'sweep',
  }) async {
    var route = 'direct';
    final clock = Stopwatch()..start();
    TrackingService.hyperliquidWithdrawInitiated(
      amountUsd: usd,
      destination: 'usd',
      walletKind: 'hot',
      purpose: purpose,
    );
    try {
      final result = await _refusalsAsRoute(() async {
        try {
          final result = await _service.withdrawToSpark(
            usd: usd,
            destination: SparkFundingAsset.dollars,
            stepUp: stepUpFor(auth),
            registerInBackground: true,
            purpose: purpose,
          );
          return VenueMoveResult(
            quoteId: result.run.quote.quoteId,
            orderId: result.run.orderId,
            registration: result.run.registration,
            // HyperCore USDC carries eight decimals.
            sentUsd: result.amountIn.toDouble() / 1e8,
            arrivingUsdEstimate: result.estimatedOut,
          );
        } on OrchestraQuoteFailure catch (e) {
          // Only Orchestra refusing the route itself, before anything was
          // signed, opens the fallback. An amount refusal stays one.
          if (!isRouteRefusal(e)) rethrow;
          route = 'cctp';
          TrackingService.hyperliquidWithdrawStep(
            step: 'cctp_fallback',
            durationMs: clock.elapsedMilliseconds,
            amountUsd: usd,
          );
          return _withdrawByCctp(usd: usd, auth: auth, purpose: purpose);
        }
      });
      TrackingService.hyperliquidWithdrawSubmitted(
        amountUsd: result.sentUsd,
        route: route,
        destination: 'usd',
        walletKind: 'hot',
        purpose: purpose,
      );
      return result;
    } catch (e) {
      // A fixed code, never the error text.
      TrackingService.hyperliquidWithdrawFailed(
        reason: switch (e) {
          RouteUnavailable(:final reason) => reason ?? 'route_unavailable',
          RouteQuoteError(:final code) => code.code,
          _ => TrackingService.errorCategory(e),
        },
        route: route,
        amountUsd: usd,
        destination: 'usd',
        walletKind: 'hot',
        purpose: purpose,
      );
      rethrow;
    }
  }

  /// The CCTP fallback for [withdrawToDollars]. The same step-up hook
  /// approves it: a sweep passes only because the intent's final
  /// recipient is the wallet's own Spark address, reached through the
  /// wallet's own standing instruction, which the fallback verifies
  /// before it signs.
  Future<VenueMoveResult> _withdrawByCctp({
    required double usd,
    required MoveAuthorization auth,
    required String purpose,
  }) async {
    try {
      final result = await _cctp.withdrawToDollars(
          usd: usd, stepUp: stepUpFor(auth), purpose: purpose);
      return VenueMoveResult(
        quoteId: result.operationId,
        registration: result.registration,
        sentUsd: result.sentUsd,
        arrivingUsdEstimate: result.arrivingUsdEstimate,
      );
    } on CctpUnavailable catch (e) {
      throw RouteUnavailable('cctp_${e.reason.code}');
    }
  }

  /// A stop before anything moved, in the one-balance layer's own words.
  ///
  /// Every exception mapped here is raised before a signature or a send:
  /// the funding service's own availability stops, the runner's
  /// route-availability stop, and a quote Flashnet refused for the route
  /// (`route_unavailable`, or `unsupported_route` for a HyperCore source).
  /// An amount refusal surfaces as its [RouteQuoteError], so the sweeper
  /// can raise its floor. Anything else is rethrown untouched.
  static Future<T> _refusalsAsRoute<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on HypercoreFundingUnavailable catch (e) {
      throw RouteUnavailable(e.reason.code);
    } on SettlementStopped catch (e) {
      if (e.reason == SettlementStopReason.routeUnavailable) {
        throw const RouteUnavailable('route_unavailable');
      }
      rethrow;
    } on OrchestraQuoteFailure catch (e) {
      if (isRouteRefusal(e)) {
        throw const RouteUnavailable('route_unavailable');
      }
      final routeError = e.routeError;
      if (routeError != null) throw routeError;
      rethrow;
    } on WalletGuardException catch (e) {
      // No spending wallet or no Investing account to move from.
      if (e.reason == WalletGuardReason.ownAddressUnavailable) {
        throw const RouteUnavailable('account_unavailable');
      }
      rethrow;
    }
  }

  /// Flashnet refused the route itself, not the amount: a
  /// `route_unavailable` code (which `unsupported_route` reads as), or a
  /// refusal whose text names the HyperCore-source block. The one test
  /// both CCTP fallbacks (this rail and the Move sheet) open on.
  static bool isRouteRefusal(OrchestraQuoteFailure e) {
    if (e.routeError?.code == RouteQuoteErrorCode.routeUnavailable) {
      return true;
    }
    final text = e.message.toLowerCase();
    return text.contains('unsupported_route') ||
        text.contains('independent deposit verification') ||
        text.contains('unsupported source');
  }

  /// The runner's step-up hook for [auth]. A user grant is checked and
  /// consumed against the intent the quote binds to (the final recipient
  /// plus the route, never the deposit address). A sweep carries no tap:
  /// it is accepted only for the dollar route home, delivered to the
  /// wallet's own Spark address, which the runner has verified against the
  /// quote before it asks.
  @visibleForTesting
  SettlementStepUpHook stepUpFor(MoveAuthorization auth) => (intent) async {
        switch (auth) {
          case UserGrantAuthorization(:final grant):
            final account = await _read(hyperliquidAddressProvider.future);
            try {
              AuthGrants.consume(
                  grant,
                  OrchestraGrants.settlement(intent,
                      action: SensitiveAction.venueWithdraw,
                      asset: 'USDC',
                      account: account));
              return true;
            } catch (_) {
              return false;
            }
          case SweepAuthorization():
            if (!isDollarRouteHome(intent)) return false;
            final String? own;
            try {
              own = await _read(sparkSelfAddressProvider.future);
            } catch (_) {
              return false;
            }
            return own != null && own.isNotEmpty && recipientOf(intent) == own;
        }
      };

  @visibleForTesting
  static bool isDollarRouteHome(SettlementAuthorizationIntent intent) =>
      intent.routeLabel == kHypercoreToSparkUsdRoute.label;

  /// The recipient half of an intent's `recipient|routeVersion`.
  @visibleForTesting
  static String recipientOf(SettlementAuthorizationIntent intent) {
    final bar = intent.destination.indexOf('|');
    return bar < 0 ? intent.destination : intent.destination.substring(0, bar);
  }

  /// USDC the account could send right now: withdrawable perpetuals cash
  /// plus unheld spot USDC, as the Move sheet's Max reads it.
  @override
  Future<double> withdrawableUsd() async {
    final address = await _read(hyperliquidAddressProvider.future);
    if (address == null || address.isEmpty) return 0;
    final read = _sendableUsd;
    if (read != null) return read(address);
    final snapshot = await _read(hyperliquidTradingModelProvider)
        .getPortfolioSnapshot(address)
        .timeout(const Duration(seconds: 10));
    final usd =
        hypercoreSendableUsdc(snapshot.withdrawable, snapshot.spotBalances);
    return usd.isFinite && usd > 0 ? usd : 0;
  }

  @override
  Future<VenueMoveQuote> estimate(
      {required double usd, required bool deposit}) async {
    final route = _route(deposit: deposit);
    final amount =
        doubleToOrchestraAmount(usd, route.fromAsset, chain: route.fromChain);
    final quote =
        await _estimate(route, amount, await _recipient(deposit: deposit));
    if (quote == null) throw const RouteUnavailable('no estimate');
    final arriving = orchestraAmountToDouble(quote.estimatedOut, route.toAsset,
        chain: route.toChain);
    final fee = orchestraFeeAmount(quote).usd ?? 0;
    final limits = await _limits(route);
    return VenueMoveQuote(
      arrivingUsd: arriving,
      feeUsd: fee,
      // Nothing outside the quote: the route's costs are in its output.
      fixedCostUsd: 0,
      minUsd: limits?.minUsd ?? kHyperCoreMinMoveUsd,
      maxUsd: limits?.maxUsd ?? kHyperCoreMaxMoveUsd,
    );
  }

  @override
  Future<double> minimumUsd({required bool deposit}) async {
    final limits = await _limits(_route(deposit: deposit));
    return limits?.minUsd ?? kHyperCoreMinMoveUsd;
  }

  /// HyperCore moves pay their costs out of the moved amount.
  @override
  Future<void> ensureGasFloat() async {}

  /// No push signal: the slip's own account poll sees the credit.
  @override
  Stream<void> get credited => const Stream<void>.empty();

  /// The address the move's quote names
  /// (`SparkHypercoreFundingService.depositFromSpark` / `withdrawToSpark`):
  /// the Investing account on the way in, so an account Hyperliquid
  /// already knows is not priced with the one-time activation, and the own
  /// Spark address on the way out. Null when it cannot be read; the
  /// estimate is then asked without it.
  Future<String?> _recipient({required bool deposit}) async {
    try {
      final address = deposit
          ? _read(hyperliquidAddressProvider.future)
          : _read(sparkSelfAddressProvider.future);
      return await address.timeout(const Duration(seconds: 3));
    } catch (_) {
      return null;
    }
  }

  static Future<OrchestraEstimate?> _estimateNative(
      RouteKey route, String amount, String? recipient) async {
    final result = await OrchestraService.getEstimate(
      sourceChain: route.fromChain,
      sourceAsset: route.fromAsset,
      destinationChain: route.toChain,
      destinationAsset: route.toAsset,
      amount: amount,
      recipientAddress: recipient,
    ).timeout(const Duration(seconds: 10));
    return result.data;
  }

  static Future<HyperCoreRouteBounds?> _limitsNative(RouteKey route) async {
    final limits = await OrchestraService.getRouteLimits(route)
        .timeout(const Duration(seconds: 8), onTimeout: () => null);
    if (limits == null) return null;
    double? cents(int? value) => value == null ? null : value / 100;
    return (
      minUsd: cents(limits.exactInMinUsdCents ?? limits.orderMinUsdCents),
      maxUsd: cents(limits.exactInMaxUsdCents ?? limits.orderMaxUsdCents),
    );
  }
}

/// The rail Investing moves ride on.
final hyperliquidMoveRailProvider =
    Provider<HyperliquidMoveRail>((ref) => HyperCoreMoveRail(ref.read));
