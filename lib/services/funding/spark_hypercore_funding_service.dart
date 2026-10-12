// Spark ↔ Investing (Hyperliquid) funding through Orchestra, by way of
// HyperEVM, for the spending wallet.
//
// Orchestra refuses every HyperCore-source route ("HyperCore source routes
// require independent deposit verification and are unavailable", checked
// live 2026-10-12) and its HyperCore deliveries lose about $1.20 beyond
// their fee fields. HyperEVM routes work at the quoted fee. So:
//
//  - Withdraw: quote `hyperevm:USDC → spark:USDB|BTC` (recipient: own
//    Spark address, refund: own HyperEVM address, the same EOA as the
//    Hyperliquid account). After approval: HyperCore → HyperEVM
//    (`sendAsset` to 0x2000…0000), wait for the USDC, ERC-20 transfer to
//    the quote's deposit address; the transfer hash is the proof. See
//    lib/services/hyperevm/hyperevm_withdrawal.dart.
//  - Deposit: quote `spark:USDB|BTC → hyperevm:USDC` to the own HyperEVM
//    address. After the Spark send the sweeper moves the delivered USDC
//    into HyperCore (Circle's CoreDepositWallet `depositWithAuth`). See
//    lib/services/hyperevm/hyperevm_vault.dart.
//  - Gas: a $1 HYPE float, bought only when a side runs low, folded into
//    the move's fee. See lib/services/hyperevm/hyperevm_gas_float.dart.
//
// An unavailable route stops before quoting or sending; no other chain is
// ever chosen as a fallback. The HyperCore-source path is gone for the
// spending wallet (the Ledger keeps its own flow, which the live catalogue
// now reports unavailable). If Flashnet re-enables HyperCore sources, this
// path keeps working: nothing here depends on them.

import 'dart:async';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart'
    show GetInfoRequest;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/constants/feature_flags.dart';
import 'package:kute/helpers/orchestra_router.dart'
    show orchestraAmountToDouble;
import 'package:kute/models/affiliate_model.dart' show AffiliateService;
import 'package:kute/models/orchestra_routes_model.dart' show RouteKey;
import 'package:kute/models/settlement_operation.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/breez_config_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart'
    show selectedCurrencyProvider;
import 'package:kute/providers/hyperliquid_account_provider.dart'
    show hyperliquidAddressProvider;
import 'package:kute/providers/spark_address_provider.dart'
    show sparkSelfAddressProvider;
import 'package:kute/providers/swap_orders_provider.dart'
    show swapOrdersProvider;
import 'package:kute/providers/transactions_provider.dart'
    show walletTransactionCacheProvider;
import 'package:kute/providers/usd_account_provider.dart'
    show usdBaseUnitsFromNodeInfo;
import 'package:kute/services/background_sync_service.dart';
import 'package:kute/services/funding/hot_settlement.dart';
import 'package:kute/services/funding/owned_address_resolver.dart'
    show ProviderReader;
import 'package:kute/services/funding/settlement_funding_outcome.dart';
import 'package:kute/services/funding/settlement_quote_policy.dart'
    show SettlementPayer, SettlementQuotePolicy;
import 'package:kute/services/funding/settlement_registration.dart'
    show followSettlementRegistration;
import 'package:kute/services/funding/settlement_runner.dart';
import 'package:kute/services/funding/settlement_stage.dart';
import 'package:kute/services/hyperevm/hyperevm_bridge.dart';
import 'package:kute/services/hyperevm/hyperevm_constants.dart';
import 'package:kute/services/hyperevm/hyperevm_gas_float.dart';
import 'package:kute/services/hyperevm/hyperevm_runtime.dart';
import 'package:kute/services/hyperevm/hyperevm_vault.dart';
import 'package:kute/services/hyperevm/hyperevm_withdrawal.dart';
import 'package:kute/services/hyperliquid/hyperliquid_onboarding_service.dart';
import 'package:kute/services/orchestra/orchestra_quote_gate.dart'
    show OrchestraQuoteFailure, OrchestraQuoteGate;
import 'package:kute/services/orchestra/orchestra_quote_guard.dart';
import 'package:kute/services/orchestra_routes.dart'
    show kOrchestraUsdAssetCode, kOrchestraUsdChain;
import 'package:kute/services/polymarket_spark_txs_service.dart';
import 'package:kute/services/release/route_pause_policy.dart';
import 'package:kute/services/security/wallet_guard_exception.dart';
import 'package:kute/services/tracking_service.dart';

// ─────────────────────────────── routes ───────────────────────────────
//
// The route versions keep the `spark_to_hypercore` / `hypercore_to_spark`
// prefixes Activity classifies Investing rows by; the `_hyperevm_` part
// says which way the money travelled.

const String kSparkToHypercoreRouteVersion = 'spark_to_hypercore_v1';
const String kSparkUsdToHypercoreRouteVersion = 'spark_usd_to_hypercore_v1';
const String kHypercoreToSparkRouteVersion = 'hypercore_to_spark_perps_v2';
const String kHypercoreToSparkUsdRouteVersion = 'hypercore_to_spark_usd_perps_v2';

const String kSparkToHypercoreViaEvmRouteVersion =
    'spark_to_hypercore_hyperevm_v1';
const String kSparkUsdToHypercoreViaEvmRouteVersion =
    'spark_usd_to_hypercore_hyperevm_v1';
const String kHypercoreToSparkViaEvmRouteVersion =
    'hypercore_to_spark_hyperevm_v1';
const String kHypercoreToSparkUsdViaEvmRouteVersion =
    'hypercore_to_spark_usd_hyperevm_v1';
const String kHyperEvmGasFloatRouteVersion = 'spark_to_hyperevm_gas_v1';

/// Retired HyperCore-direct routes, kept so records made before this
/// change still reconcile and read in Activity.
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
final RouteKey kHypercoreToSparkUsdRoute = RouteKey(
    fromChain: 'hypercore',
    fromAsset: 'USDC',
    toChain: kOrchestraUsdChain,
    toAsset: kOrchestraUsdAssetCode);

/// The live routes: Spark ↔ HyperEVM USDC.
final RouteKey kSparkToHyperEvmRoute = RouteKey(
    fromChain: 'spark',
    fromAsset: 'BTC',
    toChain: 'hyperevm',
    toAsset: 'USDC');
final RouteKey kSparkUsdToHyperEvmRoute = RouteKey(
    fromChain: kOrchestraUsdChain,
    fromAsset: kOrchestraUsdAssetCode,
    toChain: 'hyperevm',
    toAsset: 'USDC');
final RouteKey kHyperEvmToSparkRoute = RouteKey(
    fromChain: 'hyperevm',
    fromAsset: 'USDC',
    toChain: 'spark',
    toAsset: 'BTC');
final RouteKey kHyperEvmToSparkUsdRoute = RouteKey(
    fromChain: 'hyperevm',
    fromAsset: 'USDC',
    toChain: kOrchestraUsdChain,
    toAsset: kOrchestraUsdAssetCode);

/// Orchestra `tag` on the gas-float quote: the float is never a move of
/// its own and never revenue, so the backend files it apart from the
/// Investing moves, whose quotes carry the one-balance purpose tag
/// (`oneBalanceQuoteTag`: `kute:order_funding_investing`,
/// `kute:sweep_investing`, `kute:manual_move`, …). Categorical only.
const String kHyperEvmGasFloatTag = 'kute:gas_float';

/// Dollar-token base units per dollar (6 decimals on Orchestra).
const int _kSparkUsdScale = 1000000;

/// HyperEVM USDC base units per dollar.
const int _kHyperEvmUsdcScale = 1000000;

/// What must be left on a withdrawal quote before each HyperEVM step.
const Duration _kSendMargin = Duration(seconds: 20);

/// Which Spark balance funds a deposit, or receives a withdrawal. The UNIT
/// is part of the choice: bitcoin is quoted and sent in satoshis, dollars
/// in the dollar token's own six-decimal base units. Nothing here converts
/// between them, and a move that cannot use the named balance fails rather
/// than falling back to the other one.
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
      isBitcoin ? kSparkToHyperEvmRoute : kSparkUsdToHyperEvmRoute;

  String get hypercoreRouteVersion => isBitcoin
      ? kSparkToHypercoreViaEvmRouteVersion
      : kSparkUsdToHypercoreViaEvmRouteVersion;

  /// The reverse leg: which Spark balance a withdrawal lands in.
  RouteKey get sparkWithdrawRoute =>
      isBitcoin ? kHyperEvmToSparkRoute : kHyperEvmToSparkUsdRoute;

  String get sparkWithdrawRouteVersion => isBitcoin
      ? kHypercoreToSparkViaEvmRouteVersion
      : kHypercoreToSparkUsdViaEvmRouteVersion;

  /// Digits a withdrawal's delivered amount is written with on its
  /// Activity row: eight for bitcoin, cents for dollars.
  int get deliveredFractionDigits => isBitcoin ? 8 : 2;

  /// The settlement flow a withdrawal into this balance runs under.
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
  paused('paused'),

  /// The HYPE float for gas is short and neither Dollars nor Bitcoin can
  /// pay the $1 that refills it.
  floatUnavailable('float_unavailable'),

  /// The float could not be made ready in time (still arriving, or a
  /// transaction of the account still pending).
  floatPending('float_pending'),

  /// HyperEVM gas is in a spike.
  gasSpike('gas_spike'),

  /// HyperCore refused the HyperCore → HyperEVM transfer (for example an
  /// account mode that disables it).
  coreTransferRefused('core_transfer_refused'),

  /// The USDC moved to HyperEVM did not land in time. It is the account's
  /// own and is swept back into Investing.
  arrivalTimeout('arrival_timeout');

  const HypercoreFundingUnavailableReason(this.code);

  /// Analytics value.
  final String code;
}

/// Funding is unavailable. Nothing reached the provider and no alternate
/// chain may run.
class HypercoreFundingUnavailable implements Exception {
  const HypercoreFundingUnavailable(this.reason, {this.cause});

  final HypercoreFundingUnavailableReason reason;
  final Object? cause;

  /// The float needs about $1 more in Dollars before the move can start.
  bool get needsFloatFunds =>
      reason == HypercoreFundingUnavailableReason.floatUnavailable;

  String get message => switch (reason) {
        HypercoreFundingUnavailableReason.reverseNotReady =>
          'Investing withdrawals are not available yet.',
        HypercoreFundingUnavailableReason.accountUnavailable =>
          'Your investing account is unavailable. Try again.',
        HypercoreFundingUnavailableReason.floatUnavailable =>
          'Add about \$1 to Dollars to cover the network fee for this move. Nothing was sent.',
        _ => 'Investing funding is temporarily unavailable. Try again later.',
      };

  @override
  String toString() => message;
}

/// A run that moved funds.
class DirectHypercoreResult {
  const DirectHypercoreResult({
    required this.run,
    required this.amountIn,
    required this.estimatedOut,
  });

  final SettlementRunResult run;

  /// Base units of whatever funded the run, as quoted: sats or dollar
  /// base units (deposit), HyperEVM USDC base units (withdrawal).
  final BigInt amountIn;

  /// Estimated USDC (deposit) or, on a withdrawal, whichever Spark asset
  /// it was pointed at.
  final double estimatedOut;

  bool get registered => run.registered;
}

/// Spark balances the float may be paid from: dollar base units and sats.
typedef SparkFloatBalances = ({BigInt usdMicros, int sats});

/// Places the $1 float purchase for [source], recipient [eoa].
typedef HyperEvmFloatPurchase = Future<void> Function(
  HyperEvmFloatSource source, {
  required String eoa,
  required String sparkAddress,
  required String trigger,
});

class SparkHypercoreFundingService {
  SparkHypercoreFundingService(
    this._read, {
    this.enabled = kDirectHypercoreFundingEnabled,
    Future<SettlementRunner> Function()? runner,
    RoutePausePolicy pausePolicy = const RoutePausePolicy(),
    HyperEvmReader? reader,
    HyperEvmTxJournal? journal,
    Future<HyperEvmSigner> Function(String walletId, String address)?
        openSigner,
    HyperEvmFloatPurchase? buyFloat,
    Future<SparkFloatBalances> Function()? sparkBalances,
    double Function()? usdPerBtc,
    void Function(String address)? sweepSoon,
    DateTime Function()? clock,
    Future<void> Function(Duration)? sleep,
  })  : _runner = runner ?? HotSettlement.runner,
        _pause = pausePolicy,
        _reader = reader ?? HyperEvmReaderNative(),
        _journal = journal ?? const HiveHyperEvmTxJournal(),
        _openSignerOverride = openSigner,
        _buyFloatOverride = buyFloat,
        _sparkBalancesOverride = sparkBalances,
        _usdPerBtcOverride = usdPerBtc,
        _sweepSoonOverride = sweepSoon,
        _clock = clock ?? DateTime.now,
        _sleep = sleep;

  final ProviderReader _read;
  final bool enabled;
  final Future<SettlementRunner> Function() _runner;

  /// Remote pause switch for new Investing funding operations.
  final RoutePausePolicy _pause;
  final HyperEvmReader _reader;
  final HyperEvmTxJournal _journal;
  final Future<HyperEvmSigner> Function(String walletId, String address)?
      _openSignerOverride;
  final HyperEvmFloatPurchase? _buyFloatOverride;
  final Future<SparkFloatBalances> Function()? _sparkBalancesOverride;
  final double Function()? _usdPerBtcOverride;
  final void Function(String address)? _sweepSoonOverride;
  final DateTime Function() _clock;
  final Future<void> Function(Duration)? _sleep;

  HyperEvmFloatKeeper get _keeper => HyperEvmFloatKeeper(
      reader: _reader, journal: _journal, clock: _clock, sleep: _sleep);

  /// Whether the route can be used. False means stop, never fallback.
  Future<bool> tryDirect({required bool deposit}) async {
    try {
      await ensureAvailable(deposit: deposit);
      return true;
    } on HypercoreFundingUnavailable {
      return false;
    }
  }

  /// Rejects an unavailable route before requesting a quote or sending.
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

  /// The pinned spending wallet, or null when there is none.
  String? get spendingWalletIdOrNull {
    try {
      return HotSettlement.spendingWalletId(_read);
    } catch (_) {
      return null;
    }
  }

  void _ensureSpendingWallet(String walletId) {
    if (HotSettlement.spendingWalletId(_read) != walletId) {
      throw const WalletGuardException(WalletGuardReason.ownAddressUnavailable,
          field: 'wallet');
    }
  }

  HypercoreFundingUnavailableReason? forwardBlocker() =>
      enabled ? null : HypercoreFundingUnavailableReason.flagOff;

  HypercoreFundingUnavailableReason? reverseBlocker() =>
      enabled ? null : HypercoreFundingUnavailableReason.flagOff;

  // ─────────────────────────────── deposit ──────────────────────────────

  /// [amountBaseUnits] of the Spark [asset] to the account's HyperEVM
  /// address, swept into HyperCore once it lands. Unavailable routes stop
  /// before funds move. [onFundingStarted] runs just before the send.
  ///
  /// [amountBaseUnits] is read in [asset]'s OWN base units: satoshis for
  /// bitcoin, six-decimal base units for dollars. It is never a dollar
  /// figure and never a sat figure for the other asset.
  ///
  /// [registerInBackground] returns once the send is recorded and finishes
  /// the deposit submit afterwards; the Activity row moves to the order id
  /// when it returns.
  ///
  /// [purpose] is what the move is for — the Move sheet's own
  /// (`manual_move`), or an order's funding leg / a sweep through the
  /// one-balance rail — and picks the quote's provider tag
  /// (`kute:manual_move`, `kute:order_funding_investing`, …).
  Future<DirectHypercoreResult> depositFromSpark({
    required SparkFundingAsset asset,
    required BigInt amountBaseUnits,
    double? amountUsd,
    void Function()? onFundingStarted,
    SettlementStepUpHook? stepUp,
    bool registerInBackground = false,
    String purpose = 'manual_move',
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
    final (eoa, sparkRefund) = await _addresses('deposit', walletId);

    // The float: read before anything moves. A deposit only needs the
    // HyperEVM side (its sweep pays `depositWithAuth` gas there).
    final gas = await _gasPlan('deposit', eoa, HyperEvmMove.deposit);
    HyperEvmFloatSource? floatSource;
    if (gas.buy) {
      floatSource = await _floatSource(
        spentUsdMicros: asset.isBitcoin ? BigInt.zero : amountBaseUnits,
        spentSats: asset.isBitcoin ? amountBaseUnits.toInt() : 0,
      );
      if (floatSource == null) {
        TrackingService.hyperevmGasFloatFailed(
            stage: 'no_source', trigger: 'deposit');
        _unavailable(
            'deposit', HypercoreFundingUnavailableReason.floatUnavailable);
      }
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
          destinationChain: 'hyperevm',
          destinationAsset: 'USDC',
          amountBaseUnits: amountBaseUnits,
          recipientAddress: eoa,
          refundAddress: sparkRefund,
          recipientKind: RecipientKind.ownEvm,
          ownAddress: eoa,
          tag: oneBalanceQuoteTag(purpose, venue: 'investing'),
        ),
        flow: 'move_hyperevm_deposit',
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
        // Enables the home balance poll before the credit arrives.
        await HyperliquidOnboardingService.markEnabled(walletId);
        _ensureSpendingWallet(walletId);
        fundStarted = true;
        onFundingStarted?.call();
        final paymentId = await HotSettlement.sendSpark(_read, prepared);
        PolymarketSparkTxsService.tag(paymentId);
        return SettlementFundingProof.spark(paymentId);
      },
      // The approval covers the deposit and its fee, the float included;
      // the float is bought only after it was given.
      stepUp: stepUp == null && floatSource == null
          ? null
          : (auth) async {
              if (stepUp != null && !await stepUp(auth)) return false;
              final source = floatSource;
              if (source != null) {
                await _purchaseFloat(source,
                    eoa: eoa, sparkAddress: sparkRefund, trigger: 'deposit');
              }
              return true;
            },
      registerInBackground: registerInBackground,
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
        chain: 'hyperevm');
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
    followSettlementRegistration(_read, run);
    // Orchestra delivers to HyperEVM; the sweeper takes it into HyperCore.
    _sweepSoon(eoa);
    TrackingService.directHypercoreRoute(
        direction: 'deposit', outcome: 'hyperevm');
    return DirectHypercoreResult(
        run: run, amountIn: quote.amountIn, estimatedOut: estOut);
  }

  // ─────────────────────────────── withdraw ─────────────────────────────

  /// Investing USDC worth [usd] to the Spark wallet, through HyperEVM.
  /// Throws [HypercoreFundingUnavailable] before funds move when the
  /// route, the account or the gas float is not ready. No other chain is
  /// permitted.
  ///
  /// [destination] picks which Spark balance receives it: bitcoin (the
  /// default) or the dollar token.
  ///
  /// [registerInBackground] and [purpose] as for [depositFromSpark].
  Future<DirectHypercoreResult> withdrawToSpark({
    required double usd,
    SparkFundingAsset destination = SparkFundingAsset.bitcoin,
    required SettlementStepUpHook stepUp,
    bool registerInBackground = false,
    String purpose = 'manual_move',
  }) async {
    final blocker = reverseBlocker();
    if (blocker != null) _unavailable('withdraw', blocker);
    final walletId = HotSettlement.spendingWalletId(_read);
    await ensureAvailable(deposit: false);
    _ensureSpendingWallet(walletId);
    final (eoa, sparkAddress) = await _addresses('withdraw', walletId);
    // Six decimals: HyperEVM USDC has six, and HyperCore drops anything
    // finer on the way across.
    final amountMicros = hyperEvmUsdcMicros(usd);
    if (amountMicros <= BigInt.zero) {
      _unavailable(
          'withdraw', HypercoreFundingUnavailableReason.accountUnavailable);
    }

    // The float: both sides, read before anything moves.
    final gas = await _gasPlan('withdraw', eoa, HyperEvmMove.withdraw);
    HyperEvmFloatSource? floatSource;
    if (gas.buy) {
      floatSource =
          await _floatSource(spentUsdMicros: BigInt.zero, spentSats: 0);
      if (floatSource == null && gas.mustWait) {
        TrackingService.hyperevmGasFloatFailed(
            stage: 'no_source', trigger: 'withdraw');
        _unavailable(
            'withdraw', HypercoreFundingUnavailableReason.floatUnavailable);
      }
    }

    final settlementRunner = await _runner();
    _ensureSpendingWallet(walletId);
    String? fundingOperationId;
    var fundStarted = false;
    var staged = false;
    String? pendingRowId;
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
        final fetched = await HotSettlement.quote(
          _read,
          OrchestraQuoteRequest(
            sourceChain: 'hyperevm',
            sourceAsset: 'USDC',
            destinationChain: destination.chain,
            destinationAsset: destination.assetCode,
            amountBaseUnits: amountMicros,
            recipientAddress: sparkAddress,
            refundAddress: eoa,
            recipientKind: RecipientKind.ownSpark,
            ownAddress: sparkAddress,
            tag: oneBalanceQuoteTag(purpose, venue: 'investing'),
          ),
          flow: destination.isBitcoin
              ? 'move_hyperevm_withdraw'
              : 'move_hyperevm_withdraw_usd',
          idempotencyKey: key,
        );
        quoteSkews[fetched.quote.quoteId] = fetched.skew;
        return fetched;
      },
      prepareFunding: (quote, operationId) async {
        fundingOperationId = operationId;
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
        final id = fundingOperationId;
        if (id == null) {
          throw SettlementFundingRefused(
              StateError('Missing withdrawal operation'));
        }
        Future<void> persist(
            SettlementFunding Function(SettlementFunding current) patch) async {
          final write = await settlementRunner.store.update(
            id,
            stage: SettlementStage.broadcasting,
            patch: (current) => current.copyWith(
                funding: patch(current.funding ??
                    const SettlementFunding(kind: SettlementFundingKind.evm))),
          );
          if (!write.applied) {
            throw StateError('Withdrawal funding state changed');
          }
        }

        // Before each transfer: the quote must still have
        // [_kSendMargin] left on the provider's clock, enough for a
        // HyperEVM transfer (one-second blocks) to land inside it.
        void ensurePayable() {
          _ensureSpendingWallet(walletId);
          OrchestraQuoteGate.ensurePayable(quote,
              amountBaseUnits: quote.amountIn, now: _clock());
          final now = SettlementQuotePolicy.effectiveNow(
              _clock(), quoteSkews[quote.quoteId]);
          if (!quote.expiresAt.isAfter(now.add(_kSendMargin))) {
            throw const WalletGuardException(WalletGuardReason.quoteExpired);
          }
        }

        return HyperEvmVaultLock.run(eoa, () async {
          try {
            // The funding kind is on disk before any step, so a kill right
            // here is classified by the HyperEVM probe.
            await persist((current) =>
                current.copyWith(kind: SettlementFundingKind.evm));
            final signer = await _openSigner(walletId, eoa);
            final hash = await HyperEvmWithdrawalSteps(
              reader: _reader,
              journal: _journal,
              clock: _clock,
              sleep: _sleep,
            ).run(
              signer: signer,
              depositAddress: quote.depositAddress,
              amountMicros: quote.amountIn,
              ensurePayable: ensurePayable,
              persist: persist,
              onStep: (step, elapsed) {
                if (step == 'core_to_evm') staged = true;
                TrackingService.hyperliquidWithdrawStep(
                    step: step,
                    amountUsd: quote.amountIn.toDouble() / _kHyperEvmUsdcScale,
                    durationMs: elapsed.inMilliseconds);
              },
            );
            return SettlementFundingProof.evm(hash);
          } on SettlementFundingRefused {
            fundStarted = false;
            rethrow;
          }
        });
      },
      stepUp: (auth) async {
        final ok = await stepUp(SettlementAuthorizationIntent(
          flow: auth.flow,
          walletId: auth.walletId,
          destination: auth.destination,
          routeLabel: auth.routeLabel,
          amountIn: auth.amountIn,
          minReceive: auth.minReceive,
          maxFeeBps: auth.maxFeeBps,
          reviewedQuote: auth.reviewedQuote,
        ));
        if (!ok) return false;
        // Approved: make the float ready. A move whose gas is covered goes
        // ahead at once; one that is not waits for the $1 to land.
        if (gas.buy || gas.rebalances) {
          await _prepareFloat(
            walletId: walletId,
            eoa: eoa,
            sparkAddress: sparkAddress,
            plan: gas,
            source: floatSource,
            trigger: 'withdraw',
          );
        }
        return true;
      },
      registerInBackground: registerInBackground,
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
      // USDC already moved to HyperEVM goes back into Investing.
      if (staged || e is HyperEvmArrivalTimeout) _sweepSoon(eoa);
      final mapped = withdrawalStop(e);
      final reason = fundStarted ? null : (mapped?.reason ?? _unavailableReasonFor(e));
      if (reason != null) {
        TrackingService.directHypercoreRoute(
            direction: 'withdraw', outcome: 'unavailable_${reason.code}');
      }
      if (mapped != null) throw mapped;
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
    followSettlementRegistration(_read, run);
    TrackingService.directHypercoreRoute(
        direction: 'withdraw', outcome: 'hyperevm');
    return DirectHypercoreResult(
      run: run,
      amountIn: quote.amountIn,
      estimatedOut: orchestraAmountToDouble(
          quote.quote.estimatedOut, destination.assetCode,
          chain: destination.chain),
    );
  }

  /// A stop the person should read as "not available, nothing was sent"
  /// (or "add about $1 to Dollars"), from what the HyperEVM steps threw.
  @visibleForTesting
  static HypercoreFundingUnavailable? withdrawalStop(Object e) {
    if (e is HypercoreFundingUnavailable) return e;
    final reason = switch (e) {
      HyperEvmCoreTransferRefused() =>
        HypercoreFundingUnavailableReason.coreTransferRefused,
      HyperEvmArrivalTimeout() =>
        HypercoreFundingUnavailableReason.arrivalTimeout,
      HyperEvmGasSpike() => HypercoreFundingUnavailableReason.gasSpike,
      HyperEvmGasShort() ||
      HyperEvmTransactionPending() =>
        HypercoreFundingUnavailableReason.floatPending,
      HyperEvmFloatUnavailable(reason: 'gas_spike') =>
        HypercoreFundingUnavailableReason.gasSpike,
      HyperEvmFloatUnavailable() =>
        HypercoreFundingUnavailableReason.floatPending,
      _ => null,
    };
    return reason == null
        ? null
        : HypercoreFundingUnavailable(reason, cause: e);
  }

  // ─────────────────────────────── the float ────────────────────────────

  Future<HyperEvmGasPlan> _gasPlan(
      String direction, String eoa, HyperEvmMove move) async {
    final HyperEvmGasPlan plan;
    try {
      plan = await _keeper.plan(eoa, move);
    } catch (e) {
      // A balance or account mode that cannot be read never moves money.
      _unavailable(
          direction, HypercoreFundingUnavailableReason.accountUnavailable,
          cause: e);
    }
    if (plan.gasSpike) {
      TrackingService.hyperevmGasFloatFailed(
          stage: 'gas_spike', trigger: direction);
      _unavailable(direction, HypercoreFundingUnavailableReason.gasSpike);
    }
    return plan;
  }

  /// Dollars first, then Bitcoin, from what each balance holds beyond the
  /// move itself. Null when neither can pay the $1.
  Future<HyperEvmFloatSource?> _floatSource({
    required BigInt spentUsdMicros,
    required int spentSats,
  }) async {
    final SparkFloatBalances balances;
    try {
      balances = await (_sparkBalancesOverride ?? _readSparkBalances)();
    } catch (_) {
      return null;
    }
    final usdPerBtc = (_usdPerBtcOverride ??
        () => _read(selectedCurrencyProvider('USD')).toDouble())();
    return pickHyperEvmFloatSource(
      usdMicros: balances.usdMicros - spentUsdMicros,
      sats: balances.sats - spentSats,
      satsPerDollar: usdPerBtc > 0 ? 1e8 / usdPerBtc : 0,
    );
  }

  Future<SparkFloatBalances> _readSparkBalances() async {
    final wrapper = await _read(breezSDKProvider.future);
    final sdk = wrapper.instance;
    if (sdk == null) throw StateError('The spending wallet is disconnected.');
    final info = await sdk.getInfo(request: const GetInfoRequest());
    return (
      usdMicros: usdBaseUnitsFromNodeInfo(info),
      sats: info.balanceSats.toInt(),
    );
  }

  /// After approval: buys, waits when the move needs it, and balances the
  /// two sides. Throws [HypercoreFundingUnavailable] when the float cannot
  /// cover the move; nothing has gone to the provider then.
  Future<void> _prepareFloat({
    required String walletId,
    required String eoa,
    required String sparkAddress,
    required HyperEvmGasPlan plan,
    required HyperEvmFloatSource? source,
    required String trigger,
  }) async {
    try {
      await HyperEvmVaultLock.run(eoa, () async {
        final signer = await _openSigner(walletId, eoa);
        await _keeper.prepare(
          address: eoa,
          move: HyperEvmMove.withdraw,
          signer: signer,
          plan: source == null
              ? HyperEvmGasPlan(
                  gasSpike: plan.gasSpike,
                  buy: false,
                  mustWait: plan.mustWait,
                  toCoreWei: plan.toCoreWei,
                  toEvmCore: plan.toEvmCore)
              : plan,
          buy: () => _purchaseFloat(source!,
              eoa: eoa, sparkAddress: sparkAddress, trigger: trigger),
        );
      });
    } on HypercoreFundingUnavailable {
      rethrow;
    } on HyperEvmFloatUnavailable catch (e) {
      TrackingService.hyperevmGasFloatFailed(
          stage: e.reason, trigger: trigger, error: e);
      throw withdrawalStop(e)!;
    } catch (e) {
      // Only an optional top-up beside a covered move may fail quietly.
      if (!plan.mustWait) return;
      TrackingService.hyperevmGasFloatFailed(
          stage: 'rebalance', trigger: trigger, error: e);
      throw HypercoreFundingUnavailable(
          HypercoreFundingUnavailableReason.floatPending,
          cause: e);
    }
  }

  Future<void> _purchaseFloat(
    HyperEvmFloatSource source, {
    required String eoa,
    required String sparkAddress,
    required String trigger,
  }) async {
    try {
      await (_buyFloatOverride ?? _buyFloatNative)(source,
          eoa: eoa, sparkAddress: sparkAddress, trigger: trigger);
      TrackingService.hyperevmGasFloatBought(
          sourceAsset: source.analytics,
          trigger: trigger,
          amountUsd: HyperEvmGas.floatUsd);
    } catch (e) {
      TrackingService.hyperevmGasFloatFailed(
          stage: 'send', trigger: trigger, error: e);
      throw HypercoreFundingUnavailable(
          HypercoreFundingUnavailableReason.floatPending,
          cause: e);
    }
  }

  /// The $1 float: its own settlement operation, paid from Spark to the
  /// account's own HyperEVM address. Approval was given for the move it
  /// serves, so it asks for none. Not a move of its own: no Activity row
  /// (its Spark payment is hidden like any funding leg) and no provider
  /// revenue event.
  Future<void> _buyFloatNative(
    HyperEvmFloatSource source, {
    required String eoa,
    required String sparkAddress,
    required String trigger,
  }) async {
    final dollars = source == HyperEvmFloatSource.dollars;
    final usdPerBtc = (_usdPerBtcOverride ??
        () => _read(selectedCurrencyProvider('USD')).toDouble())();
    final sats = hyperEvmFloatSats(usdPerBtc > 0 ? 1e8 / usdPerBtc : 0);
    if (!dollars && sats == null) {
      throw const HyperEvmFloatUnavailable('no_source');
    }
    final amount = dollars ? HyperEvmGas.floatUsdMicros : BigInt.from(sats!);
    final route = RouteKey(
      fromChain: dollars ? kOrchestraUsdChain : 'spark',
      fromAsset: dollars ? kOrchestraUsdAssetCode : 'BTC',
      toChain: 'hyperevm',
      toAsset: 'HYPE',
    );
    final base = HotSettlement.plan(
      _read,
      flow: SettlementFlow.hyperevmGasFloat,
      route: route,
      source: SettlementAccountKind.sparkHot,
      destination: SettlementAccountKind.hlHot,
      amountUsd: HyperEvmGas.floatUsd,
      requestQuote: (key) => HotSettlement.quote(
        _read,
        OrchestraQuoteRequest(
          sourceChain: route.fromChain,
          sourceAsset: route.fromAsset,
          destinationChain: 'hyperevm',
          destinationAsset: 'HYPE',
          amountBaseUnits: amount,
          recipientAddress: eoa,
          refundAddress: sparkAddress,
          recipientKind: RecipientKind.ownEvm,
          ownAddress: eoa,
          tag: kHyperEvmGasFloatTag,
        ),
        flow: 'hyperevm_gas_float',
        idempotencyKey: key,
      ),
      prepareFunding: (quote, _) => HotSettlement.prepareSpark(_read, quote),
      fund: (quote, prepared) async {
        final paymentId = await HotSettlement.sendSpark(_read, prepared);
        PolymarketSparkTxsService.tag(paymentId);
        return SettlementFundingProof.spark(paymentId);
      },
      registerInBackground: true,
    );
    final run = await (await _runner()).run(_versioned(
        base, kHyperEvmGasFloatRouteVersion,
        payer: SettlementPayer.sparkHot));
    followSettlementRegistration(_read, run);
  }

  Future<HyperEvmSigner> _openSigner(String walletId, String eoa) =>
      (_openSignerOverride ??
          (walletId, address) =>
              openHyperEvmSigner(_read, walletId, address))(walletId, eoa);

  void _sweepSoon(String eoa) {
    final override = _sweepSoonOverride;
    if (override != null) {
      override(eoa);
      return;
    }
    try {
      unawaited(_read(hyperEvmSweeperProvider)
          .watch(eoa)
          .then((_) {}, onError: (_) {}));
    } catch (_) {}
  }

  // ─────────────────────────────── internals ───────────────────────────────

  Future<(String, String)> _addresses(String direction, String walletId) async {
    final String eoa;
    final String spark;
    try {
      eoa = (await _read(hyperliquidAddressProvider.future)) ?? '';
      _ensureSpendingWallet(walletId);
      spark = await _read(sparkSelfAddressProvider.future) ?? '';
      _ensureSpendingWallet(walletId);
    } catch (e) {
      _unavailable(
          direction, HypercoreFundingUnavailableReason.accountUnavailable,
          cause: e);
    }
    if (eoa.isEmpty || spark.isEmpty) {
      _unavailable(
          direction, HypercoreFundingUnavailableReason.accountUnavailable);
    }
    return (eoa, spark);
  }

  Never _unavailable(String direction, HypercoreFundingUnavailableReason reason,
      {Object? cause}) {
    TrackingService.directHypercoreRoute(
        direction: direction, outcome: 'unavailable_${reason.code}');
    throw HypercoreFundingUnavailable(reason, cause: cause);
  }

  /// Classifies failures before any funds move.
  static HypercoreFundingUnavailableReason? _unavailableReasonFor(
      Object error) {
    if (error is HypercoreFundingUnavailable) return error.reason;
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
        registerInBackground: base.registerInBackground,
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
        chain: 'hyperevm');
    return SwapOrder(
      id: id,
      coinFrom: asset.assetCode,
      networkFrom: 'SPARK',
      coinTo: 'USDC',
      // Investing, as the person sees it: the HyperEVM leg is plumbing.
      networkTo: 'HYPERCORE',
      depositAddress: quote.depositAddress,
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
          (quote.amountIn.toDouble() / _kHyperEvmUsdcScale).toStringAsFixed(2),
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

/// [usd] as HyperEVM USDC base units (six decimals), rounded to the cent
/// fraction the venue prints and never above it.
BigInt hyperEvmUsdcMicros(double usd) {
  if (!usd.isFinite || usd <= 0) return BigInt.zero;
  // Through eight decimals first, exactly as balances are read, then down
  // to six: 19.99 is 19.9899999… as a double and must stay 19.99.
  final units = BigInt.from((usd * 1e8).round());
  return units ~/ BigInt.from(100);
}

final sparkHypercoreFundingServiceProvider =
    Provider<SparkHypercoreFundingService>(
        (ref) => SparkHypercoreFundingService(
              ref.read,
              pausePolicy: ref.read(routePausePolicyProvider),
            ));
