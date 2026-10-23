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
// are unavailable"), and its route catalog lists `hypercore:USDC` with no
// destinations at all. Either answer arrives before anything is signed or
// sent: the quote's refusal, or (first, in practice) the settlement
// runner's catalog check stopping on the missing pair
// (`SettlementStopped(routeUnavailable, pair_missing)`), which never gets
// as far as a quote. A withdrawal to Dollars then falls back to Circle
// CCTP out of HyperCore (lib/services/hyperliquid/cctp_withdrawal.dart):
// one `sendToEvmWithData` to the Arbitrum deposit address of a one-time
// Orchestra quote bound to the wallet's own recipient, the mint then
// submitted to Orchestra (never a standing address). A
// move straight to Bitcoin or to the wallet's own Predictions account
// (`withdrawDirect`, `hypercore:USDC → polygon:USDC.e` for Predictions)
// takes the same native-first path and the same fallback rule. Only
// when that cannot run either (paused, below the minimum, no usable
// one-time quote, a failed read, the runtime policy withholding
// `hyperliquid.withdraw`) the rail reports `RouteUnavailable`: the
// sweeper shows the cash as waiting, backs off and tries again later;
// nothing moves until the fallback can run.

import 'dart:async';

import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/helpers/auth_grant.dart' show AuthGrants, SensitiveAction;
import 'package:kute/helpers/orchestra_router.dart'
    show doubleToOrchestraAmount, orchestraAmountToDouble;
import 'package:kute/helpers/venue_intents.dart'
    show DirectLegGrants, OrchestraGrants;
import 'package:kute/models/orchestra_model.dart' show OrchestraEstimate;
import 'package:kute/models/orchestra_route_limits.dart'
    show RouteQuoteError, RouteQuoteErrorCode;
import 'package:kute/models/orchestra_routes_model.dart'
    show RouteKey, RouteUnavailableReason;
import 'package:kute/providers/hyperliquid_account_provider.dart'
    show hyperliquidAddressProvider;
import 'package:kute/providers/hyperliquid_markets_provider.dart'
    show hyperliquidTradingModelProvider;
import 'package:kute/providers/spark_address_provider.dart'
    show sparkSelfAddressProvider;
import 'package:kute/services/api/orchestra_api.dart';
import 'package:kute/services/funding/owned_address_resolver.dart'
    show ProviderReader;
import 'package:kute/services/funding/settlement_funding_outcome.dart'
    show SettlementFundingRefused;
import 'package:kute/services/funding/settlement_runner.dart'
    show
        SettlementAuthorizationIntent,
        SettlementStepUpHook,
        SettlementStopReason,
        SettlementStopped;
import 'package:kute/services/funding/spark_hypercore_funding_service.dart';
import 'package:kute/providers/polymarket_trading_provider.dart'
    show polymarketTradingProvider;
import 'package:kute/services/hyperliquid/cctp_withdrawal.dart'
    show
        CctpUnavailable,
        CctpWithdrawalResult,
        HypercoreCctpWithdrawal,
        cctpAnalyticsDestination,
        cctpRouteFor,
        hypercoreCctpWithdrawalProvider;
import 'package:kute/services/orchestra/standing_deposit_store.dart'
    show InvestingWithdrawalDestination;
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
      operationId: result.run.operation.operationId,
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
            operationId: result.run.operation.operationId,
          );
        } catch (e) {
          // Only Orchestra not offering the route itself, before anything
          // was signed, opens the fallback ([opensCctpFallback]). An
          // amount refusal stays one; a pause stays a pause.
          if (!opensCctpFallback(e)) rethrow;
          if (kDebugMode) {
            debugPrint('[investing-withdraw] direct route not offered '
                '(${e is SettlementStopped ? 'catalog' : 'quote'}); '
                'trying CCTP');
          }
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
          // A send the CCTP fallback proved never posted: its cause's
          // category, never the wrapper's name.
          SettlementFundingRefused(:final cause) =>
            TrackingService.errorCategory(cause),
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
  /// recipient is the wallet's own Spark address, reached through a
  /// one-time quote bound to it, which the fallback verifies before it
  /// signs.
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
        operationId: result.operationId,
      );
    } on CctpUnavailable catch (e) {
      if (kDebugMode) {
        debugPrint('[investing-withdraw] CCTP fallback unavailable: '
            '${e.reason.code} ($purpose)');
      }
      throw RouteUnavailable('cctp_${e.reason.code}');
    }
  }

  /// Investing cash straight to its own final destination. Bitcoin and
  /// Predictions both go native HyperCore first (→ the own Spark address,
  /// → the own Predictions account); only a confirmed unsupported route
  /// before funding ([opensCctpFallback]) opens CCTP. Other native
  /// failures never authorize another source send.
  Future<VenueMoveResult> withdrawDirect({
    required InvestingWithdrawalDestination destination,
    required double usd,
    required MoveAuthorization auth,
    String purpose = 'cash_pull',
  }) async {
    final analytics = cctpAnalyticsDestination(destination);
    // Bitcoin and Predictions go native first; anything else keeps CCTP.
    final nativeFirst =
        destination == InvestingWithdrawalDestination.bitcoin ||
            destination == InvestingWithdrawalDestination.predictions;
    var route = nativeFirst ? 'direct' : 'cctp';
    final clock = Stopwatch()..start();
    TrackingService.hyperliquidWithdrawInitiated(
      amountUsd: usd,
      destination: analytics,
      walletKind: 'hot',
      purpose: purpose,
    );
    Future<VenueMoveResult> byCctp() async {
      final CctpWithdrawalResult result;
      try {
        result = await _cctp.withdrawTo(
            destination: destination,
            usd: usd,
            stepUp: stepUpForDirect(auth, destination),
            purpose: purpose);
      } on CctpUnavailable catch (e) {
        throw DirectRouteRefused('cctp_${e.reason.code}');
      } on WalletGuardException catch (e) {
        if (e.reason == WalletGuardReason.ownAddressUnavailable) {
          throw const DirectRouteRefused('account_unavailable');
        }
        rethrow;
      } on SettlementStopped catch (e) {
        // Stopped at the approval, before the signature.
        throw DirectRouteRefused('settlement_${e.reason.name}');
      }
      return VenueMoveResult(
        quoteId: result.operationId,
        registration: result.registration,
        sentUsd: result.sentUsd,
        arrivingUsdEstimate: result.arrivingUsdEstimate,
        operationId: result.operationId,
      );
    }

    try {
      late VenueMoveResult result;
      if (nativeFirst) {
        try {
          final DirectHypercoreResult native;
          final double arrivingUsd;
          if (destination == InvestingWithdrawalDestination.bitcoin) {
            native = await _service.withdrawToSpark(
                usd: usd,
                destination: SparkFundingAsset.bitcoin,
                stepUp: stepUpForDirect(auth, destination),
                registerInBackground: true,
                purpose: purpose);
            // Native output is BTC, while this interface carries USD.
            // Match the Predictions→BTC quote/source-value convention;
            // the service's receipt retains the actual BTC output.
            arrivingUsd = (native.amountIn.toDouble() / 1e8) *
                (1 - native.run.quote.quote.combinedFeeBps / 10000);
          } else {
            native = await _service.withdrawToPredictions(
                usd: usd,
                stepUp: stepUpForDirect(auth, destination),
                registerInBackground: true,
                purpose: purpose);
            // Polygon USDC.e: the estimate is already dollars.
            arrivingUsd = native.estimatedOut;
          }
          result = VenueMoveResult(
              quoteId: native.run.quote.quoteId,
              orderId: native.run.orderId,
              registration: native.run.registration,
              sentUsd: native.amountIn.toDouble() / 1e8,
              arrivingUsdEstimate: arrivingUsd,
              operationId: native.run.operation.operationId);
        } catch (e) {
          if (!opensCctpFallback(e)) rethrow;
          route = 'cctp';
          TrackingService.hyperliquidWithdrawStep(
              step: 'cctp_fallback',
              durationMs: clock.elapsedMilliseconds,
              amountUsd: usd);
          result = await byCctp();
        }
      } else {
        result = await byCctp();
      }
      TrackingService.hyperliquidWithdrawSubmitted(
        amountUsd: result.sentUsd,
        route: route,
        destination: analytics,
        walletKind: 'hot',
        purpose: purpose,
      );
      return result;
    } catch (e) {
      TrackingService.hyperliquidWithdrawFailed(
        reason: switch (e) {
          RouteUnavailable(:final reason) => reason ?? 'route_unavailable',
          HypercoreFundingUnavailable(:final reason) => reason.code,
          SettlementStopped(:final reason) => 'settlement_${reason.name}',
          OrchestraQuoteFailure(:final routeError) =>
            routeError?.code.code ?? TrackingService.errorCategory(e),
          RouteQuoteError(:final code) => code.code,
          SettlementFundingRefused(:final cause) =>
            TrackingService.errorCategory(cause),
          _ => TrackingService.errorCategory(e),
        },
        route: route,
        amountUsd: usd,
        destination: analytics,
        walletKind: 'hot',
        purpose: purpose,
      );
      // Preserve proof of a pre-send stop without making it a route
      // refusal: the caller may offer a fresh-approved Retry, never an
      // automatic CCTP or Dollars send. Earlier unresolved operations stay
      // uncertain, as do untyped failures and nested funding-unknown causes.
      if (route == 'direct' &&
          nativeFirst &&
          (e is HypercoreFundingUnavailable ||
              e is OrchestraQuoteFailure ||
              (e is SettlementStopped &&
                  e.reason != SettlementStopReason.blockedPending))) {
        throw SettlementFundingRefused(e);
      }
      rethrow;
    }
  }

  /// [stepUpFor] for a move straight to [destination]. A user grant is
  /// checked as before. A leg of an approved action
  /// ([ApprovedLegAuthorization]) is accepted only for that destination's
  /// route, delivered to the wallet's own Spark address (Bitcoin) or its
  /// own Predictions account, and only within the leg caps the action's
  /// approval binds (`DirectLegGrants.take`). The automatic authorization
  /// never moves Investing cash anywhere but home to Dollars: refused.
  @visibleForTesting
  SettlementStepUpHook stepUpForDirect(
          MoveAuthorization auth, InvestingWithdrawalDestination destination) =>
      (intent) async {
        switch (auth) {
          case UserGrantAuthorization():
            return stepUpFor(auth)(intent);
          case SweepAuthorization():
            return false;
          case ApprovedLegAuthorization(:final grant):
            if (intent.walletId != grant.walletId ||
                intent.routeLabel != cctpRouteFor(destination).label) {
              return false;
            }
            final to = switch (destination) {
              InvestingWithdrawalDestination.bitcoin =>
                VenueCashDestination.bitcoin,
              InvestingWithdrawalDestination.predictions =>
                VenueCashDestination.predictions,
              _ => null,
            };
            if (to == null) return false;
            final recipient = recipientOf(intent);
            try {
              final bool own;
              if (destination.chain == 'spark') {
                final String? self = await _read(sparkSelfAddressProvider.future);
                own = self != null && self.isNotEmpty && recipient == self;
              } else {
                final self = await _ownPredictionsAccount();
                own = self != null &&
                    self.isNotEmpty &&
                    recipient.toLowerCase() == self.toLowerCase();
              }
              if (!own) return false;
            } catch (_) {
              return false;
            }
            // Native usdSend has no separately paid source fee. An
            // unexpected charge requires a separately reviewed policy.
            if ((intent.sourceFeeBaseUnits ?? BigInt.zero) != BigInt.zero) {
              return false;
            }
            // HyperCore USDC carries eight decimals; the caps six.
            return DirectLegGrants.take(grant,
                venue: 'investing',
                destination: to.code,
                amount:
                    (intent.amountIn + BigInt.from(99)) ~/ BigInt.from(100));
        }
      };

  Future<String?> _ownPredictionsAccount() async {
    final live =
        _read(polymarketTradingProvider).valueOrNull?.proxyWalletAddress;
    if (live != null && live.isNotEmpty) return live;
    return _read(polymarketTradingProvider.notifier).depositAddress();
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

  /// The direct route stopped because Orchestra does not offer it, before
  /// anything was signed: the quote's route refusal ([isRouteRefusal]),
  /// or the runner's catalog check finding the pair missing (Flashnet's
  /// catalog lists `hypercore:USDC` with no destinations, so this stop
  /// comes first and the quote is never asked). The one test both CCTP
  /// fallbacks (this rail and the Move sheet) open on. A stale or unread
  /// catalog, a pause, an amount refusal or a declined approval do not.
  static bool opensCctpFallback(Object e) => switch (e) {
        OrchestraQuoteFailure() => isRouteRefusal(e),
        SettlementStopped(
          reason: SettlementStopReason.routeUnavailable,
          routeReason: RouteUnavailableReason.pairMissing,
        ) =>
          true,
        _ => false,
      };

  /// Flashnet refused the route itself, not the amount: a
  /// `route_unavailable` code (which `unsupported_route` reads as), or a
  /// refusal whose text names the HyperCore-source block.
  static bool isRouteRefusal(OrchestraQuoteFailure e) {
    // A policy refusal is never a route refusal: no other rail opens on it.
    if (e.denial != null) return false;
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
          case ApprovedLegAuthorization():
            // A leg of an approved action only ever goes straight to its
            // destination ([stepUpForDirect]); home is the automatic one's.
            return false;
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
    // The route's limits are read beside the estimate, not after it.
    final limitsRead = _limits(route);
    unawaited(limitsRead.then((_) {}, onError: (Object _) {}));
    final quote =
        await _estimate(route, amount, await _recipient(deposit: deposit));
    if (quote == null) throw const RouteUnavailable('no estimate');
    final arriving = orchestraAmountToDouble(quote.estimatedOut, route.toAsset,
        chain: route.toChain);
    final fee = orchestraFeeAmount(quote).usd ?? 0;
    final limits = await limitsRead;
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

  /// No push signal from the rail itself. The credit reaches the queued
  /// order from the order's runner, the moment Orchestra's status says
  /// the move delivered, and from the venue's own ledger updates
  /// (`PendingHlOrderAutoFire.creditLanded` / `accountMoved`); the
  /// account poll is the backstop.
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

  /// How long a route's limits answer is used again. The slip's estimate
  /// reads them; the order's move asks for the minimum seconds later
  /// (`OrderFundingController`), right before it sends: the same answer,
  /// without another round trip on the order's way.
  static const Duration kLimitsFreshFor = Duration(minutes: 1);

  static final Map<String, ({HyperCoreRouteBounds bounds, DateTime at})>
      _limitsRead = {};

  /// Test seam: the clock [kLimitsFreshFor] is measured with.
  @visibleForTesting
  static DateTime Function() limitsClock = DateTime.now;

  @visibleForTesting
  static void resetLimitsCache() => _limitsRead.clear();

  static Future<HyperCoreRouteBounds?> _limitsNative(RouteKey route) async {
    final key = route.label;
    final kept = _limitsRead[key];
    final now = limitsClock();
    if (kept != null && now.difference(kept.at) < kLimitsFreshFor) {
      return kept.bounds;
    }
    final limits = await OrchestraService.getRouteLimits(route)
        .timeout(const Duration(seconds: 8), onTimeout: () => null);
    // Only an answer is kept: a failed read asks again next time.
    if (limits == null) return null;
    double? cents(int? value) => value == null ? null : value / 100;
    final bounds = (
      minUsd: cents(limits.exactInMinUsdCents ?? limits.orderMinUsdCents),
      maxUsd: cents(limits.exactInMaxUsdCents ?? limits.orderMaxUsdCents),
    );
    _limitsRead[key] = (bounds: bounds, at: limitsClock());
    return bounds;
  }
}

/// The rail Investing moves ride on.
final hyperliquidMoveRailProvider =
    Provider<HyperliquidMoveRail>((ref) => HyperCoreMoveRail(ref.read));
