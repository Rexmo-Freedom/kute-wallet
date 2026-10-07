// Direct Spark ↔ HyperCore funding through Orchestra.
// Investing has no Arbitrum route. An unavailable native route stops before
// quoting or sending; callers must never select another chain as a fallback.
// Withdrawals transfer the pinned native spot USDC token and register the
// confirmed HyperCore ledger transaction with Orchestra.

import 'package:kute/services/hyperliquid/hypercore_activation_fee.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/constants/feature_flags.dart';
import 'package:kute/helpers/orchestra_router.dart'
    show orchestraAmountToDouble;
import 'package:kute/models/affiliate_model.dart' show AffiliateService;
import 'package:kute/models/orchestra_routes_model.dart' show RouteKey;
import 'package:kute/models/settlement_operation.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart'
    show hyperliquidAddressProvider;
import 'package:kute/providers/spark_address_provider.dart'
    show sparkSelfAddressProvider;
import 'package:kute/providers/swap_orders_provider.dart'
    show swapOrdersProvider;
import 'package:kute/providers/transactions_provider.dart'
    show walletTransactionCacheProvider;
import 'package:kute/services/background_sync_service.dart';
import 'package:kute/services/funding/hot_settlement.dart';
import 'package:kute/services/funding/hypercore_hot_source_send.dart';
import 'package:kute/services/funding/settlement_stage.dart';
import 'package:kute/services/funding/owned_address_resolver.dart'
    show ProviderReader;
import 'package:kute/services/funding/settlement_quote_policy.dart'
    show SettlementPayer, SettlementMoment, SettlementQuotePolicy;
import 'package:kute/services/funding/settlement_runner.dart';
import 'package:kute/services/funding/settlement_funding_outcome.dart';
import 'package:kute/services/orchestra/orchestra_quote_gate.dart'
    show OrchestraQuoteFailure, OrchestraQuoteGate;
import 'package:kute/services/orchestra/orchestra_quote_guard.dart';
import 'package:kute/services/orchestra_routes.dart'
    show kOrchestraUsdAssetCode, kOrchestraUsdChain;
import 'package:kute/services/polymarket_spark_txs_service.dart';
import 'package:kute/services/hyperliquid/hyperliquid_onboarding_service.dart';
import 'package:kute/services/release/route_pause_policy.dart';
import 'package:kute/services/security/wallet_guard_exception.dart';
import 'package:kute/services/tracking_service.dart';

const String kSparkToHypercoreRouteVersion = 'spark_to_hypercore_v1';
const String kSparkUsdToHypercoreRouteVersion = 'spark_usd_to_hypercore_v1';
const String kHypercoreToSparkRouteVersion = 'hypercore_to_spark_perps_v2';
const String kHypercoreToSparkUsdRouteVersion = 'hypercore_to_spark_usd_perps_v2';

final RouteKey kSparkToHypercoreRoute = RouteKey(
    fromChain: 'spark',
    fromAsset: 'BTC',
    toChain: 'hypercore',
    toAsset: 'USDC');
final RouteKey kSparkUsdToHypercoreRoute = RouteKey(
    fromChain: kOrchestraUsdChain,
    fromAsset: kOrchestraUsdAssetCode,
    toChain: 'hypercore',
    toAsset: 'USDC');
final RouteKey kHypercoreToSparkRoute = RouteKey(
    fromChain: 'hypercore',
    fromAsset: 'USDC',
    toChain: 'spark',
    toAsset: 'BTC');

/// The same withdrawal delivering the dollar token instead of bitcoin.
/// `hypercore:USDC → spark:USDB` is a fixed-input route in the live
/// catalogue, and the guard values it at par (both ends are dollars), so
/// it verifies without a bitcoin price.
final RouteKey kHypercoreToSparkUsdRoute = RouteKey(
    fromChain: 'hypercore',
    fromAsset: 'USDC',
    toChain: kOrchestraUsdChain,
    toAsset: kOrchestraUsdAssetCode);

/// HyperCore USDC base units per dollar (8 decimals on Orchestra).
const int _kHypercoreUsdcScale = 100000000;

/// Dollar-token base units per dollar (6 decimals on Orchestra).
const int _kSparkUsdScale = 1000000;

/// Which Spark balance funds a deposit. The UNIT is part of the choice,
/// which is why this is one enum and not a bare asset string: bitcoin is
/// quoted and sent in satoshis, dollars in the dollar token's own
/// six-decimal base units. Nothing in this file converts between them —
/// the caller hands over base units of the asset it names, and a deposit
/// that cannot be funded from that balance fails rather than falling back
/// to the other one.
enum SparkFundingAsset {
  bitcoin,
  dollars;

  bool get isBitcoin => this == SparkFundingAsset.bitcoin;

  String get chain => isBitcoin ? 'spark' : kOrchestraUsdChain;

  String get assetCode => isBitcoin ? 'BTC' : kOrchestraUsdAssetCode;

  /// Base units per whole unit (sats per BTC, or base units per dollar).
  int get scale => isBitcoin ? 100000000 : _kSparkUsdScale;

  /// Digits the Activity row's deposit amount is written with.
  int get rowFractionDigits => isBitcoin ? 8 : 2;

  RouteKey get hypercoreRoute =>
      isBitcoin ? kSparkToHypercoreRoute : kSparkUsdToHypercoreRoute;

  String get hypercoreRouteVersion => isBitcoin
      ? kSparkToHypercoreRouteVersion
      : kSparkUsdToHypercoreRouteVersion;

  /// The reverse leg: which Spark balance a HyperCore withdrawal lands
  /// in. Same two choices, read as the DESTINATION instead of the
  /// source.
  RouteKey get sparkWithdrawRoute =>
      isBitcoin ? kHypercoreToSparkRoute : kHypercoreToSparkUsdRoute;

  String get sparkWithdrawRouteVersion => isBitcoin
      ? kHypercoreToSparkRouteVersion
      : kHypercoreToSparkUsdRouteVersion;

  /// Digits a withdrawal's delivered amount is written with on its
  /// Activity row: eight for bitcoin, cents for dollars.
  int get deliveredFractionDigits => isBitcoin ? 8 : 2;

  /// The settlement flow a HyperCore withdrawal into this balance runs
  /// under. The delivered asset is what the operation reports as.
  SettlementFlow get sparkWithdrawFlow => isBitcoin
      ? SettlementFlow.investingToSparkDirect
      : SettlementFlow.investingToSparkUsdDirect;
}

enum HypercoreFundingUnavailableReason {
  flagOff('flag_off'),
  accountUnavailable('account_unavailable'),
  routeUnavailable('route_unavailable'),
  quoteFailed('quote_failed'),
  reverseNotReady('reverse_not_ready'),

  /// The remote `route_pause_direct_hypercore` switch is known to be on.
  paused('paused');

  const HypercoreFundingUnavailableReason(this.code);

  /// Analytics value.
  final String code;
}

/// Native funding is unavailable. No funds moved and no alternate chain may run.
class HypercoreFundingUnavailable implements Exception {
  const HypercoreFundingUnavailable(this.reason, {this.cause});

  final HypercoreFundingUnavailableReason reason;
  final Object? cause;

  String get message => switch (reason) {
        HypercoreFundingUnavailableReason.reverseNotReady =>
          'HyperCore withdrawals are not available yet.',
        HypercoreFundingUnavailableReason.accountUnavailable =>
          'Your investing account is unavailable. Try again.',
        _ => 'HyperCore funding is temporarily unavailable. Try again later.',
      };

  @override
  String toString() => message;
}

/// The HyperCore source leg of the direct reverse route for the hot
/// Hyperliquid account.
/// The production sender pays the catalog's native spot USDC token and
/// returns its canonical ledger hash after checking the exact signed action.
abstract interface class HypercoreHotSourceSend {
  bool get isReady;

  Future<BigInt> activationFeeForDestination(String depositAddress);

  /// Read-only identity checks run before the runner persists broadcasting.
  Future<void> verifyAsset();

  /// Sends [amountBaseUnits] HyperCore USDC to [depositAddress] and returns
  /// the source transaction hash.
  Future<String> sendToDeposit({
    required String depositAddress,
    required BigInt amountBaseUnits,
    required BigInt reviewedActivationFeeBaseUnits,
    required void Function() ensurePayable,
    required String quoteId,
    required String sourceAddress,
    required String walletId,
    required Future<void> Function(int nonce) onBeforeSend,
  });
}

/// A direct route run that moved funds.
class DirectHypercoreResult {
  const DirectHypercoreResult({
    required this.run,
    required this.amountIn,
    required this.estimatedOut,
  });

  final SettlementRunResult run;

  /// Base units of whatever funded the run, as quoted: sats or dollar
  /// base units (forward), HyperCore USDC base units (reverse). The
  /// caller knows which asset it asked for and must scale by that.
  final BigInt amountIn;

  /// Estimated USDC (forward) or, on a withdrawal, whichever Spark asset
  /// it was pointed at: bitcoin or the dollar token.
  final double estimatedOut;

  bool get registered => run.registered;
}

class SparkHypercoreFundingService {
  SparkHypercoreFundingService(
    this._read, {
    this.enabled = kDirectHypercoreFundingEnabled,
    HypercoreHotSourceSend? reverseSource,
    Future<SettlementRunner> Function()? runner,
    RoutePausePolicy pausePolicy = const RoutePausePolicy(),
  })  : _reverse = reverseSource ?? HypercoreHotSourceSendNative(_read),
        _runner = runner ?? HotSettlement.runner,
        _pause = pausePolicy;

  final ProviderReader _read;
  final bool enabled;
  final HypercoreHotSourceSend _reverse;
  final Future<SettlementRunner> Function() _runner;

  /// Remote pause switch for new HyperCore funding operations.
  final RoutePausePolicy _pause;

  /// Whether the native route can be used. False means stop, never fallback.
  Future<bool> tryDirect({required bool deposit}) async {
    try {
      await ensureAvailable(deposit: deposit);
      return true;
    } on HypercoreFundingUnavailable {
      return false;
    }
  }

  /// Rejects an unavailable native route before requesting a quote or sending.
  Future<void> ensureAvailable({required bool deposit}) async {
    final direction = deposit ? 'deposit' : 'withdraw';
    final blocker = deposit ? forwardBlocker() : reverseBlocker();
    if (blocker != null) _unavailable(direction, blocker);
    try {
      await _pause.ensureNewOperationAllowed(PausableRoute.directHypercore);
    } on RoutePausedException catch (e) {
      _unavailable(direction, HypercoreFundingUnavailableReason.paused,
          cause: e);
    }
  }

  void _ensureSpendingWallet(String walletId) {
    if (HotSettlement.spendingWalletId(_read) != walletId) {
      throw const WalletGuardException(WalletGuardReason.ownAddressUnavailable,
          field: 'wallet');
    }
  }

  /// Legacy records do not change the chain selected for a new deposit.
  HypercoreFundingUnavailableReason? forwardBlocker() =>
      enabled ? null : HypercoreFundingUnavailableReason.flagOff;

  HypercoreFundingUnavailableReason? reverseBlocker() {
    if (!enabled) return HypercoreFundingUnavailableReason.flagOff;
    if (!_reverse.isReady) {
      return HypercoreFundingUnavailableReason.reverseNotReady;
    }
    return null;
  }

  /// [amountBaseUnits] of the Spark [asset] to the user's HyperCore
  /// account. Unavailable routes stop before funds move.
  /// [onFundingStarted] runs just before the send.
  ///
  /// [amountBaseUnits] is read in [asset]'s OWN base units: satoshis for
  /// bitcoin, six-decimal base units for dollars. It is never a dollar
  /// figure and never a sat figure for the other asset.
  Future<DirectHypercoreResult> depositFromSpark({
    required SparkFundingAsset asset,
    required BigInt amountBaseUnits,
    double? amountUsd,
    void Function()? onFundingStarted,
    SettlementStepUpHook? stepUp,
  }) async {
    if (amountBaseUnits <= BigInt.zero) {
      _unavailable(
          'deposit', HypercoreFundingUnavailableReason.accountUnavailable);
    }
    final blocker = forwardBlocker();
    if (blocker != null) _unavailable('deposit', blocker);
    final walletId = HotSettlement.spendingWalletId(_read);
    await ensureAvailable(deposit: true);
    _ensureSpendingWallet(walletId);
    final String eoa;
    final String sparkRefund;
    try {
      eoa = (await _read(hyperliquidAddressProvider.future)) ?? '';
      _ensureSpendingWallet(walletId);
      sparkRefund = await _read(sparkSelfAddressProvider.future) ?? '';
      _ensureSpendingWallet(walletId);
    } catch (e) {
      _unavailable(
          'deposit', HypercoreFundingUnavailableReason.accountUnavailable,
          cause: e);
    }
    if (eoa.isEmpty || sparkRefund.isEmpty) {
      _unavailable(
          'deposit', HypercoreFundingUnavailableReason.accountUnavailable);
    }

    var fundStarted = false;
    String? pendingRowId;
    final base = HotSettlement.plan(
      _read,
      walletId: walletId,
      flow: SettlementFlow.sparkToInvestingDirect,
      route: asset.hypercoreRoute,
      source: SettlementAccountKind.sparkHot,
      destination: SettlementAccountKind.hlHot,
      amountUsd: amountUsd,
      requestQuote: (key) => HotSettlement.quote(
        _read,
        OrchestraQuoteRequest(
          sourceChain: asset.chain,
          sourceAsset: asset.assetCode,
          destinationChain: 'hypercore',
          destinationAsset: 'USDC',
          amountBaseUnits: amountBaseUnits,
          recipientAddress: eoa,
          refundAddress: sparkRefund,
          recipientKind: RecipientKind.ownEvm,
          ownAddress: eoa,
        ),
        flow: 'move_hypercore_direct',
        idempotencyKey: key,
      ),
      prepareFunding: (quote, operationId) async {
        final stale = pendingRowId;
        if (stale != null && stale != quote.quoteId) {
          await _read(swapOrdersProvider.notifier).deleteExchange(stale);
        }
        // The Activity row exists before any money moves.
        await _read(swapOrdersProvider.notifier).addExchange(_depositRow(
          id: quote.quoteId,
          asset: asset,
          quote: quote,
          eoa: eoa,
          sparkRefund: sparkRefund,
          walletId: walletId,
          operationId: operationId,
        ));
        pendingRowId = quote.quoteId;
        return HotSettlement.prepareSpark(_read, quote);
      },
      fund: (quote, prepared) async {
        _ensureSpendingWallet(walletId);
        // The old bridge flow enabled the home balance poll while relaying.
        // Native funding needs the same local marker before its credit arrives.
        await HyperliquidOnboardingService.markEnabled(walletId);
        _ensureSpendingWallet(walletId);
        fundStarted = true;
        onFundingStarted?.call();
        final paymentId = await HotSettlement.sendSpark(_read, prepared);
        PolymarketSparkTxsService.tag(paymentId);
        return SettlementFundingProof.spark(paymentId);
      },
      // Phase 1b: the caller's step-up grant binds here (final recipient
      // plus route, never the deposit address).
      stepUp: stepUp,
    );
    final plan = _versioned(base, asset.hypercoreRouteVersion,
        payer: SettlementPayer.sparkHot);

    final SettlementRunResult run;
    try {
      run = await (await _runner()).run(plan);
    } catch (e) {
      final stale = pendingRowId;
      if (!fundStarted && stale != null) {
        await _read(swapOrdersProvider.notifier).deleteExchange(stale);
      }
      final reason = fundStarted ? null : _unavailableReasonFor(e);
      if (reason != null) {
        TrackingService.directHypercoreRoute(
            direction: 'deposit', outcome: 'unavailable_${reason.code}');
      }
      rethrow;
    }

    final quote = run.quote;
    final orderId = run.orderId ?? quote.quoteId;
    final row = _depositRow(
      id: orderId,
      asset: asset,
      quote: quote,
      eoa: eoa,
      sparkRefund: sparkRefund,
      walletId: walletId,
      operationId: run.operation.operationId,
    );
    await _swapRow(row, replacing: quote.quoteId);
    final estOut = orchestraAmountToDouble(quote.quote.estimatedOut, 'USDC',
        chain: 'hypercore');
    if (orderId.startsWith('ord_')) {
      // ignore: unawaited_futures
      AffiliateService.logProviderEvent(
        provider: 'orchestra',
        providerOrderId: orderId,
        status: 'pending',
        sourceAsset: asset.assetCode,
        sourceAmount: quote.amountIn.toDouble() / asset.scale,
        destinationAsset: 'USDC',
        destinationAmount: estOut,
      );
    }
    TrackingService.directHypercoreRoute(
        direction: 'deposit', outcome: 'direct');
    return DirectHypercoreResult(
        run: run, amountIn: quote.amountIn, estimatedOut: estOut);
  }

  /// HyperCore USDC [usd] to the Spark wallet. Throws
  /// [HypercoreFundingUnavailable] before funds move if the native source
  /// sender is unavailable. No other chain is permitted.
  ///
  /// [destination] picks which Spark balance receives it: bitcoin (the
  /// default, and the only thing this ever delivered) or the dollar
  /// token. Nothing else about the run changes — same source, same
  /// sender, same step-up, same runner — so a caller that does not ask
  /// for dollars gets byte-for-byte the old withdrawal.
  Future<DirectHypercoreResult> withdrawToSpark({
    required double usd,
    SparkFundingAsset destination = SparkFundingAsset.bitcoin,
    required SettlementStepUpHook stepUp,
  }) async {
    final blocker = reverseBlocker();
    if (blocker != null) _unavailable('withdraw', blocker);
    final walletId = HotSettlement.spendingWalletId(_read);
    await ensureAvailable(deposit: false);
    _ensureSpendingWallet(walletId);
    final String eoa;
    final String sparkAddress;
    try {
      eoa = (await _read(hyperliquidAddressProvider.future)) ?? '';
      _ensureSpendingWallet(walletId);
      sparkAddress = await _read(sparkSelfAddressProvider.future) ?? '';
      _ensureSpendingWallet(walletId);
    } catch (e) {
      _unavailable(
          'withdraw', HypercoreFundingUnavailableReason.accountUnavailable,
          cause: e);
    }
    if (eoa.isEmpty || sparkAddress.isEmpty) {
      _unavailable(
          'withdraw', HypercoreFundingUnavailableReason.accountUnavailable);
    }
    final amount = hypercoreUsdcBaseUnits(usd);

    final settlementRunner = await _runner();
    _ensureSpendingWallet(walletId);
    String? fundingOperationId;
    var fundStarted = false;
    String? pendingRowId;
    final activationFeesByQuote = <String, BigInt>{};
    final quoteSkews = <String, Duration?>{};
    final base = HotSettlement.plan(
      _read,
      walletId: walletId,
      flow: destination.sparkWithdrawFlow,
      route: destination.sparkWithdrawRoute,
      source: SettlementAccountKind.hlHot,
      destination: SettlementAccountKind.sparkHot,
      amountUsd: usd,
      requestQuote: (key) async {
        final allocated = await quoteHypercoreBudget(
          budget: amount,
          request: (netAmount, attempt) async {
            final fetched = await HotSettlement.quote(
              _read,
              OrchestraQuoteRequest(
                sourceChain: 'hypercore',
                sourceAsset: 'USDC',
                destinationChain: destination.chain,
                destinationAsset: destination.assetCode,
                amountBaseUnits: netAmount,
                recipientAddress: sparkAddress,
                refundAddress: eoa,
                recipientKind: RecipientKind.ownSpark,
                ownAddress: sparkAddress,
              ),
              flow: destination.isBitcoin
                  ? 'move_hypercore_direct_withdraw'
                  : 'move_hypercore_direct_withdraw_usd',
              idempotencyKey: '$key:budget:$attempt',
            );
            final fee = await _reverse.activationFeeForDestination(
                fetched.quote.depositAddress);
            _ensureSpendingWallet(walletId);
            return HypercoreBudgetQuote(value: fetched,
                amount: fetched.quote.amountIn, activationFee: fee);
          },
        );
        final fetched = allocated.value;
        activationFeesByQuote[fetched.quote.quoteId] = allocated.activationFee;
        quoteSkews[fetched.quote.quoteId] = fetched.skew;
        return fetched;
      },
      prepareFunding: (quote, operationId) async {
        fundingOperationId = operationId;
        await _reverse.verifyAsset();
        _ensureSpendingWallet(walletId);
        final stale = pendingRowId;
        if (stale != null && stale != quote.quoteId) {
          await _read(swapOrdersProvider.notifier).deleteExchange(stale);
        }
        await _read(swapOrdersProvider.notifier).addExchange(_withdrawRow(
          id: quote.quoteId,
          destination: destination,
          quote: quote,
          eoa: eoa,
          sparkAddress: sparkAddress,
          walletId: walletId,
          operationId: operationId,
        ));
        pendingRowId = quote.quoteId;
        return null;
      },
      fund: (quote, _) async {
        _ensureSpendingWallet(walletId);
        fundStarted = true;
        try {
          final hash = await _reverse.sendToDeposit(
            depositAddress: quote.depositAddress,
            amountBaseUnits: quote.amountIn,
            reviewedActivationFeeBaseUnits: activationFeesByQuote[quote.quoteId]!,
            ensurePayable: () {
              _ensureSpendingWallet(walletId);
              OrchestraQuoteGate.ensurePayable(quote,
                  amountBaseUnits: quote.amountIn, now: DateTime.now());
              if (!SettlementQuotePolicy.hasMargin(
                expiresAt: quote.expiresAt,
                localNow: DateTime.now(),
                skew: quoteSkews[quote.quoteId],
                moment: SettlementMoment.beforeSend,
                payer: SettlementPayer.polygonRelayer,
              )) {
                throw const WalletGuardException(WalletGuardReason.quoteExpired);
              }
            },
            quoteId: quote.quoteId,
            sourceAddress: eoa,
            walletId: walletId,
            onBeforeSend: (nonce) async {
              final id = fundingOperationId;
              if (id == null) {
                throw StateError('Missing native funding operation');
              }
              final write = await settlementRunner.store.update(
                id,
                stage: SettlementStage.broadcasting,
                patch: (current) => current.copyWith(
                    funding: SettlementFunding(
                        kind: SettlementFundingKind.hyperliquid, hlNonce: nonce)),
              );
              if (!write.applied) {
                throw StateError('Native funding state changed');
              }
            },
          );
          return SettlementFundingProof.hyperliquid(hash);
        } on SettlementFundingRefused {
          fundStarted = false;
          rethrow;
        }
      },
      stepUp: (auth) {
        final fee = activationFeesByQuote[auth.reviewedQuote?.quoteId];
        if (fee == null) throw StateError('Missing native fee review.');
        return stepUp(SettlementAuthorizationIntent(
          flow: auth.flow,
          walletId: auth.walletId,
          destination: auth.destination,
          routeLabel: auth.routeLabel,
          amountIn: auth.amountIn,
          minReceive: auth.minReceive,
          maxFeeBps: auth.maxFeeBps,
          reviewedQuote: auth.reviewedQuote,
          // Only a charge the source actually pays on top is shown and
          // bound; a usdSend has none, so approval reads the plain amount.
          sourceFeeBaseUnits: fee > BigInt.zero ? fee : null,
          sourceFeeAsset: fee > BigInt.zero ? 'USDC' : null,
        ));
      },
    );
    final plan = _versioned(base, destination.sparkWithdrawRouteVersion,
        payer: SettlementPayer.polygonRelayer);

    final SettlementRunResult run;
    try {
      run = await settlementRunner.run(plan);
    } catch (e) {
      final stale = pendingRowId;
      if (!fundStarted && stale != null) {
        await _read(swapOrdersProvider.notifier).deleteExchange(stale);
      }
      final reason = fundStarted ? null : _unavailableReasonFor(e);
      if (reason != null) {
        TrackingService.directHypercoreRoute(
            direction: 'withdraw', outcome: 'unavailable_${reason.code}');
      }
      rethrow;
    }

    final quote = run.quote;
    final orderId = run.orderId ?? quote.quoteId;
    await _swapRow(
      _withdrawRow(
        id: orderId,
        destination: destination,
        quote: quote,
        eoa: eoa,
        sparkAddress: sparkAddress,
        walletId: walletId,
        operationId: run.operation.operationId,
      ),
      replacing: quote.quoteId,
    );
    TrackingService.directHypercoreRoute(
        direction: 'withdraw', outcome: 'direct');
    return DirectHypercoreResult(
      run: run,
      amountIn: quote.amountIn,
      estimatedOut: orchestraAmountToDouble(
          quote.quote.estimatedOut, destination.assetCode,
          chain: destination.chain),
    );
  }

  // ─────────────────────────────── internals ───────────────────────────────

  Never _unavailable(String direction, HypercoreFundingUnavailableReason reason,
      {Object? cause}) {
    TrackingService.directHypercoreRoute(
        direction: direction, outcome: 'unavailable_${reason.code}');
    throw HypercoreFundingUnavailable(reason, cause: cause);
  }

  /// Classifies native funding failures before any funds move.
  static HypercoreFundingUnavailableReason? _unavailableReasonFor(
      Object error) {
    if (error is SettlementStopped) {
      return switch (error.reason) {
        SettlementStopReason.routeUnavailable =>
          HypercoreFundingUnavailableReason.routeUnavailable,
        SettlementStopReason.quoteExpired =>
          HypercoreFundingUnavailableReason.quoteFailed,
        // An earlier operation may have moved funds, the user declined, or a
        // replaced quote needs another confirm tap. Never pay a new quote
        // in its place.
        SettlementStopReason.blockedPending ||
        SettlementStopReason.declined ||
        SettlementStopReason.quoteReplaced =>
          null,
      };
    }
    if (error is OrchestraQuoteFailure || error is WalletGuardException) {
      return HypercoreFundingUnavailableReason.quoteFailed;
    }
    return null;
  }

  static SettlementPlan _versioned(
    SettlementPlan base,
    String routeVersion, {
    required SettlementPayer payer,
  }) =>
      SettlementPlan(
        walletId: base.walletId,
        flow: base.flow,
        route: base.route,
        sourceAccount: base.sourceAccount,
        destinationAccount: base.destinationAccount,
        payer: payer,
        resolveOwnership: base.resolveOwnership,
        requestQuote: base.requestQuote,
        fund: base.fund,
        routeVersion: routeVersion,
        amountUsd: base.amountUsd,
        checkAvailability: base.checkAvailability,
        review: base.review,
        prepareFunding: base.prepareFunding,
        stepUp: base.stepUp,
      );

  SwapOrder _depositRow({
    required String id,
    required SparkFundingAsset asset,
    required VerifiedOrchestraQuote quote,
    required String eoa,
    required String sparkRefund,
    required String? walletId,
    required String operationId,
  }) {
    final estOut = orchestraAmountToDouble(quote.quote.estimatedOut, 'USDC',
        chain: 'hypercore');
    return SwapOrder(
      id: id,
      coinFrom: asset.assetCode,
      networkFrom: 'SPARK',
      coinTo: 'USDC',
      networkTo: 'HYPERCORE',
      depositAddress: quote.depositAddress,
      // The deposit leg is written in the SOURCE asset's own unit: sats
      // for bitcoin, dollars for the dollar token. Sharing one divisor
      // here is what would turn $50 into 0.0000005 BTC on the row.
      depositAmount: (quote.amountIn.toDouble() / asset.scale)
          .toStringAsFixed(asset.rowFractionDigits),
      withdrawalAmount: estOut.toStringAsFixed(2),
      status: 'exchanging',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      withdrawalAddress: eoa,
      depositMin: '0',
      depositMax: '0',
      rate: '0',
      refundAddress: sparkRefund,
      provider: 'Orchestra',
      walletId: walletId,
      operationId: operationId,
      routeVersion: asset.hypercoreRouteVersion,
    );
  }

  SwapOrder _withdrawRow({
    required String id,
    required SparkFundingAsset destination,
    required VerifiedOrchestraQuote quote,
    required String eoa,
    required String sparkAddress,
    required String? walletId,
    required String operationId,
  }) {
    final estOut = orchestraAmountToDouble(
        quote.quote.estimatedOut, destination.assetCode,
        chain: destination.chain);
    return SwapOrder(
      id: id,
      coinFrom: 'USDC',
      networkFrom: 'HYPERCORE',
      coinTo: destination.assetCode,
      networkTo: 'SPARK',
      depositAddress: quote.depositAddress,
      depositAmount:
          (quote.amountIn.toDouble() / _kHypercoreUsdcScale).toStringAsFixed(2),
      withdrawalAmount:
          estOut.toStringAsFixed(destination.deliveredFractionDigits),
      status: 'exchanging',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      withdrawalAddress: sparkAddress,
      depositMin: '0',
      depositMax: '0',
      rate: '0',
      refundAddress: eoa,
      provider: 'Orchestra',
      walletId: walletId,
      operationId: operationId,
      routeVersion: destination.sparkWithdrawRouteVersion,
    );
  }

  /// Adds the registered row, then removes the pre-send quote row (add
  /// before delete, so a kill between the writes leaves a pollable row).
  Future<void> _swapRow(SwapOrder row, {required String replacing}) async {
    final notifier = _read(swapOrdersProvider.notifier);
    await notifier.addExchange(row);
    if (row.id != replacing) await notifier.deleteExchange(replacing);
    _read(walletTransactionCacheProvider.notifier).mergeSwapOrder(row);
    BackgroundSyncService().syncNow();
  }
}

final sparkHypercoreFundingServiceProvider =
    Provider<SparkHypercoreFundingService>(
        (ref) => SparkHypercoreFundingService(
              ref.read,
              pausePolicy: ref.read(routePausePolicyProvider),
            ));
