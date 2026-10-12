// lib/services/one_balance/hyperevm_move_rail.dart
//
// The HyperEVM rail between Dollars and Investing, bound to
// `hyperliquidMoveRailProvider` in hyperliquid_move_rail.dart. A thin
// adapter: the moves themselves run in `SparkHypercoreFundingService`
// (Orchestra `spark:USDB ↔ hyperevm:USDC`, the HyperCore ↔ HyperEVM steps,
// the gas float), the reads in `HyperEvmReaderNative`, and the credit
// signal comes from the sweeper that lands deposits in HyperCore.

import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:kute/helpers/auth_grant.dart' show AuthGrants, SensitiveAction;
import 'package:kute/helpers/orchestra_router.dart'
    show doubleToOrchestraAmount, orchestraAmountToDouble;
import 'package:kute/helpers/venue_intents.dart' show OrchestraGrants;
import 'package:kute/models/orchestra_model.dart' show OrchestraEstimate;
import 'package:kute/models/orchestra_routes_model.dart' show RouteKey;
import 'package:kute/providers/hyperliquid_account_provider.dart'
    show hyperliquidAddressProvider;
import 'package:kute/services/api/orchestra_api.dart';
import 'package:kute/services/funding/owned_address_resolver.dart'
    show ProviderReader;
import 'package:kute/services/funding/settlement_runner.dart'
    show SettlementAuthorizationIntent, SettlementStepUpHook;
import 'package:kute/services/funding/spark_hypercore_funding_service.dart';
import 'package:kute/services/hyperevm/hyperevm_bridge.dart';
import 'package:kute/services/hyperevm/hyperevm_constants.dart';
import 'package:kute/services/hyperevm/hyperevm_gas_float.dart';
import 'package:kute/services/hyperevm/hyperevm_runtime.dart';
import 'package:kute/services/hyperevm/hyperevm_vault.dart';
import 'package:kute/services/one_balance/hyperliquid_move_rail.dart';
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/orchestra/orchestra_fee_amount.dart';
import 'package:kute/services/security/wallet_guard_exception.dart';

/// Orchestra's floor on every `hyperevm` route, both ways (its `/limits`,
/// read 2026-10-12: `minUsdCents` 80). The live limits are asked first;
/// this is the answer when they are unreachable.
const double kHyperEvmMinMoveUsd = 0.80;

/// The ceiling when the live limits are unreachable.
const double kHyperEvmMaxMoveUsd = 100000;

/// Live route bounds in dollars.
typedef HyperEvmRouteBounds = ({double? minUsd, double? maxUsd});

class HyperEvmMoveRail implements HyperliquidMoveRail {
  HyperEvmMoveRail(
    this._read, {
    HyperEvmReader? reader,
    Future<OrchestraEstimate?> Function(RouteKey route, String amount)?
        estimate,
    Future<HyperEvmRouteBounds?> Function(RouteKey route)? limits,
    Stream<void>? credited,
  })  : _reader = reader ?? HyperEvmReaderNative(),
        _estimate = estimate ?? _estimateNative,
        _limits = limits ?? _limitsNative,
        _credited = credited ?? hyperEvmCreditedController.stream;

  final ProviderReader _read;
  final HyperEvmReader _reader;
  final Future<OrchestraEstimate?> Function(RouteKey route, String amount)
      _estimate;
  final Future<HyperEvmRouteBounds?> Function(RouteKey route) _limits;
  final Stream<void> _credited;

  SparkHypercoreFundingService get _service =>
      _read(sparkHypercoreFundingServiceProvider);

  static RouteKey _route({required bool deposit}) =>
      deposit ? kSparkUsdToHyperEvmRoute : kHyperEvmToSparkUsdRoute;

  @override
  Future<VenueMoveResult> depositDollars({
    required double usd,
    required BigInt amountBaseUnits,
    SettlementStepUpHook? stepUp,
    String purpose = 'order_funding',
  }) async {
    // The purpose picks the quote's provider tag (an order's funding leg,
    // a sweep, the Move sheet's own); the Activity row the service writes
    // already reads as an Investing deposit.
    final result = await _unavailableAsRoute(() => _service.depositFromSpark(
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

  @override
  Future<VenueMoveResult> withdrawToDollars({
    required double usd,
    required MoveAuthorization auth,
    String purpose = 'sweep',
  }) async {
    final result = await _unavailableAsRoute(() => _service.withdrawToSpark(
          usd: usd,
          destination: SparkFundingAsset.dollars,
          stepUp: stepUpFor(auth),
          registerInBackground: true,
          purpose: purpose,
        ));
    return VenueMoveResult(
      quoteId: result.run.quote.quoteId,
      orderId: result.run.orderId,
      registration: result.run.registration,
      sentUsd: result.amountIn.toDouble() / 1e6,
      arrivingUsdEstimate: result.estimatedOut,
    );
  }

  /// A stop before anything left Dollars, in the one-balance layer's own
  /// words. The reason is the funding service's categorical code.
  static Future<T> _unavailableAsRoute<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on HypercoreFundingUnavailable catch (e) {
      throw RouteUnavailable(e.reason.code);
    } on WalletGuardException catch (e) {
      // No spending wallet or no Investing account to move from.
      if (e.reason == WalletGuardReason.ownAddressUnavailable) {
        throw const RouteUnavailable('account_unavailable');
      }
      rethrow;
    }
  }

  /// The runner's step-up hook for [auth]. A user grant is checked and
  /// consumed against the intent the quote binds to (the final recipient
  /// plus the route, never the deposit address). A sweep carries no tap:
  /// it is accepted only for the dollar route home, whose recipient the
  /// runner resolves from the wallet's own Spark address and verifies
  /// against the quote before anything leaves.
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
            return isDollarRouteHome(intent);
        }
      };

  @visibleForTesting
  static bool isDollarRouteHome(SettlementAuthorizationIntent intent) =>
      intent.routeLabel == kHyperEvmToSparkUsdRoute.label;

  /// USDC the account could send right now: withdrawable perpetuals cash
  /// plus unheld spot USDC (one shared balance on a unified account).
  @override
  Future<double> withdrawableUsd() async {
    final address = await _read(hyperliquidAddressProvider.future);
    if (address == null) return 0;
    final holdings = await _reader.core(address);
    final units = holdings.mode == HyperCoreAccountMode.unified
        ? holdings.spotUsdc
        : holdings.perpUsdc + holdings.spotUsdc;
    return units.toDouble() / 1e8;
  }

  @override
  Future<VenueMoveQuote> estimate(
      {required double usd, required bool deposit}) async {
    final route = _route(deposit: deposit);
    final amount =
        doubleToOrchestraAmount(usd, route.fromAsset, chain: route.fromChain);
    final quote = await _estimate(route, amount);
    if (quote == null) throw const RouteUnavailable('no estimate');
    final arriving = orchestraAmountToDouble(quote.estimatedOut, route.toAsset,
        chain: route.toChain);
    final fee = orchestraFeeAmount(quote).usd ?? 0;
    // The flat part: the $1 gas float when this move has to refill it.
    final fixed = await _floatFeeUsd(deposit: deposit);
    final limits = await _limits(route);
    return VenueMoveQuote(
      arrivingUsd: arriving,
      feeUsd: fee,
      fixedCostUsd: fixed,
      minUsd: limits?.minUsd ?? kHyperEvmMinMoveUsd,
      maxUsd: limits?.maxUsd ?? kHyperEvmMaxMoveUsd,
    );
  }

  @override
  Future<double> minimumUsd({required bool deposit}) async {
    final limits = await _limits(_route(deposit: deposit));
    return limits?.minUsd ?? kHyperEvmMinMoveUsd;
  }

  /// Balances the HYPE float between HyperEVM and HyperCore from what the
  /// account already holds. The $1 purchase itself stays inside a move,
  /// after the user approved that move: this never spends Dollars.
  @override
  Future<void> ensureGasFloat() async {
    final address = await _read(hyperliquidAddressProvider.future);
    if (address == null) return;
    final keeper = HyperEvmFloatKeeper(
        reader: _reader, journal: const HiveHyperEvmTxJournal());
    final plan = await keeper.plan(address, HyperEvmMove.withdraw);
    if (!plan.rebalances) return;
    final walletId = _service.spendingWalletIdOrNull;
    if (walletId == null) return;
    await HyperEvmVaultLock.run(address, () async {
      final signer = await openHyperEvmSigner(_read, walletId, address);
      await keeper.rebalance(address: address, signer: signer, plan: plan);
    });
  }

  @override
  Stream<void> get credited => _credited;

  Future<double> _floatFeeUsd({required bool deposit}) async {
    try {
      final address = await _read(hyperliquidAddressProvider.future);
      if (address == null) return 0;
      final plan = await HyperEvmFloatKeeper(
              reader: _reader, journal: const HiveHyperEvmTxJournal())
          .plan(
              address, deposit ? HyperEvmMove.deposit : HyperEvmMove.withdraw);
      return plan.buy ? HyperEvmGas.floatUsd : 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<OrchestraEstimate?> _estimateNative(
      RouteKey route, String amount) async {
    final result = await OrchestraService.getEstimate(
      sourceChain: route.fromChain,
      sourceAsset: route.fromAsset,
      destinationChain: route.toChain,
      destinationAsset: route.toAsset,
      amount: amount,
    ).timeout(const Duration(seconds: 10));
    return result.data;
  }

  static Future<HyperEvmRouteBounds?> _limitsNative(RouteKey route) async {
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
