import 'package:kute/services/hyperliquid/trailing_stop.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/services/revenue/hyperliquid_revenue.dart';
// lib/services/hardware/ledger/ledger_hyperliquid_executor.dart
//
// Ledger-only Hyperliquid execution (Wallet hardening Phase 3, plan B9).
//
// * No signing-key parameter exists; the only authority is the Ledger's
//   external signer, pinned to the paired address.
// * Every action takes a reviewed [LedgerActionIntent]. Before any prompt
//   the executor checks the wallet, the kind, the intent hash, the release
//   gate (opaque kinds stay behind O1) and the geo and config gates.
// * After signing and before the POST, the signed action must equal the
//   one rebuilt from the intent, and a submission record is written.
// * No automatic nonce retry (one tap, one prompt). A timeout moves the
//   record to `submittedUnknown`; reconciliation reads venue state and
//   never re-signs.
// * User-signed actions use signature chain 42161 (0xa4b1, B5).
// * There is deliberately no withdrawal to Arbitrum (non-goal) and no
//   EVM bridge transaction; native withdrawals use reviewed usdSend intents.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:kute/constants/hyperliquid_constants.dart';
import 'package:kute/services/hardware/evm_signing_request.dart';
import 'package:kute/services/hardware/ledger/ledger_action_intent.dart';
import 'package:kute/services/hardware/ledger/ledger_evm_signer.dart'
    show LedgerActionGate;
import 'package:kute/services/hardware/ledger/ledger_failure.dart';
import 'package:kute/services/hardware/ledger/ledger_submitted_action_store.dart';
import 'package:kute/services/hardware/signing_clarity.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';
import 'package:kute/services/hyperliquid/hypercore_transfer_proof.dart';
import 'package:kute/services/hyperliquid/hyperliquid_rounding.dart';
import 'package:kute/services/hyperliquid/hyperliquid_signing.dart';
import 'package:kute/services/hardware/ledger/ledger_operation_scope.dart';

/// Arbitrum One; the Ledger signature chain for user-signed actions (B5).
const int kLedgerHyperliquidSignatureChainId = 42161;

class LedgerHyperliquidGeoBlockedException implements Exception {
  const LedgerHyperliquidGeoBlockedException();
}

class LedgerHyperliquidDisabledException implements Exception {
  const LedgerHyperliquidDisabledException();
}

/// The request was signed and its POST started, but no answer arrived.
/// The action may have landed; reconcile [recordId], never resubmit.
class LedgerSubmissionUnknownException implements Exception {
  const LedgerSubmissionUnknownException(this.recordId, this.cause);
  final String recordId;
  final Object cause;

  @override
  String toString() => 'LedgerSubmissionUnknownException($recordId)';
}

// ───────────────────────────── intents ─────────────────────────────────

String _micros(String usd) => decimalToBaseUnits(usd, 6).toString();

/// Builds reviewed Hyperliquid intents. Values are wire strings or
/// integers exactly as they will be signed.
abstract final class LedgerHyperliquidIntents {
  static LedgerActionIntent order({
    required String walletId,
    required String account,
    required int assetId,
    required String coin,
    required bool isBuy,
    required String px,
    required String sz,
    required String tif,
    required bool reduceOnly,
    required String cloid,
    String? builderAddress,
    int? builderFeeTenthsBp,
    required Map<String, String> summary,
    DateTime? now,
  }) {
    if (!RegExp(r'^0x[0-9a-fA-F]{32}$').hasMatch(cloid)) {
      throw ArgumentError('cloid must be 16 bytes of hex');
    }
    final pxUnits = decimalToBaseUnits(px, 8);
    final szUnits = decimalToBaseUnits(sz, 8);
    // Notional in USDC micros, rounded up.
    final scale = BigInt.from(10).pow(10);
    final notional = (pxUnits * szUnits + scale - BigInt.one) ~/ scale;
    return LedgerActionIntent.create(
      walletId: walletId,
      kind: LedgerActionKind.hlOrder,
      params: {
        'assetId': assetId,
        'coin': coin,
        'isBuy': isBuy,
        'px': px,
        'sz': sz,
        'tif': tif,
        'reduceOnly': reduceOnly,
        'cloid': cloid,
        'builderAddress': builderAddress,
        'builderFeeTenthsBp': builderFeeTenthsBp,
      },
      summary: summary,
      sensitive: LedgerSensitiveIntentDraft(
        action: 'hlOrder',
        walletId: walletId,
        venue: 'hyperliquid',
        account: account,
        destination: coin,
        asset: coin,
        amountMax: notional,
        limits: {'limitPrice': px, 'reduceOnly': reduceOnly, 'tif': tif},
        requiresStepUp: true,
      ),
      now: now,
    );
  }

  static LedgerActionIntent trailingStop({
    required String walletId,
    required String account,
    required HlMarket market,
    required bool isBuy,
    required double size,
    required HlTrailingStop trail,
    required bool reduceOnly,
    required Map<String, String> summary,
  }) {
    final sz = roundSize(size, market.szDecimals);
    final action = trail.action(
      market: market,
      isBuy: isBuy,
      size: sz,
      reduceOnly: reduceOnly,
    );
    return LedgerActionIntent.create(
      walletId: walletId,
      kind: LedgerActionKind.hlTrailingStop,
      params: {
        'assetId': market.assetId,
        'coin': market.coin,
        'isBuy': isBuy,
        'reduceOnly': reduceOnly,
        'action': action,
      },
      summary: summary,
      sensitive: LedgerSensitiveIntentDraft(
        action: 'hlOrder',
        walletId: walletId,
        venue: 'hyperliquid',
        account: account,
        destination: market.coin,
        asset: market.coin,
        amountMax: decimalToBaseUnits(sz, 8),
        limits: {'sizeUnit': 'coin_8', 'action': action},
        requiresStepUp: true,
      ),
    );
  }

  static LedgerActionIntent cancel({
    required String walletId,
    required String account,
    required int assetId,
    required String coin,
    required int oid,
    required Map<String, String> summary,
    DateTime? now,
  }) =>
      LedgerActionIntent.create(
        walletId: walletId,
        kind: LedgerActionKind.hlCancel,
        params: {'assetId': assetId, 'coin': coin, 'oid': oid},
        summary: summary,
        sensitive: LedgerSensitiveIntentDraft(
          action: 'hlOrder',
          walletId: walletId,
          venue: 'hyperliquid',
          account: account,
          destination: coin,
          asset: coin,
          amountMax: BigInt.zero,
          limits: {'oid': oid},
          requiresStepUp: false,
        ),
        now: now,
      );

  static LedgerActionIntent updateLeverage({
    required String walletId,
    required String account,
    required int assetId,
    required String coin,
    required bool isCross,
    required int leverage,
    required Map<String, String> summary,
    DateTime? now,
  }) =>
      LedgerActionIntent.create(
        walletId: walletId,
        kind: LedgerActionKind.hlUpdateLeverage,
        params: {
          'assetId': assetId,
          'coin': coin,
          'isCross': isCross,
          'leverage': leverage,
        },
        summary: summary,
        sensitive: LedgerSensitiveIntentDraft(
          action: 'hlOrder',
          walletId: walletId,
          venue: 'hyperliquid',
          account: account,
          destination: coin,
          asset: coin,
          amountMax: BigInt.zero,
          limits: {'leverage': leverage, 'isCross': isCross},
          requiresStepUp: true,
        ),
        now: now,
      );

  /// [amount] is a USDC decimal string; it is normalized to the exact wire
  /// string the exchange service signs.
  static LedgerActionIntent usdClassTransfer({
    required String walletId,
    required String account,
    required String amount,
    required bool toPerp,
    String? withdrawalQuoteId,
    required Map<String, String> summary,
    DateTime? now,
  }) {
    final wire =
        floatToWire(double.parse(double.parse(amount).toStringAsFixed(6)));
    return LedgerActionIntent.create(
      walletId: walletId,
      kind: LedgerActionKind.hlUsdClassTransfer,
      params: {'amount': wire, 'toPerp': toPerp,
        if (withdrawalQuoteId != null) 'withdrawalQuoteId': withdrawalQuoteId},
      summary: summary,
      sensitive: LedgerSensitiveIntentDraft(
        action: 'moveTransfer',
        walletId: walletId,
        venue: 'hyperliquid',
        account: account,
        asset: 'USDC',
        amountMax: BigInt.parse(_micros(wire)),
        limits: {'toPerp': toPerp,
          if (withdrawalQuoteId != null) 'withdrawalQuoteId': withdrawalQuoteId},
        requiresStepUp: false,
      ),
      now: now,
    );
  }

  /// Native USDC only. The deposit address, amount and quote remain bound to
  /// the withdrawal's fresh app approval and the Ledger signature.
  static LedgerActionIntent usdSend({
    required String walletId,
    required String account,
    required String destination,
    required BigInt amountBaseUnits,
    required String quoteId,
    BigInt? reviewedActivationFeeBaseUnits,
    required Map<String, String> summary,
    DateTime? now,
  }) {
    if (!RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(destination) ||
        sameEvmAddress(account, destination) ||
        quoteId.isEmpty) {
      throw ArgumentError('Invalid native withdrawal destination or quote');
    }
    if (reviewedActivationFeeBaseUnits != null &&
        reviewedActivationFeeBaseUnits < BigInt.zero) {
      throw ArgumentError('Invalid activation fee');
    }
    final wire = hypercorePerpUsdcWire(amountBaseUnits);
    return LedgerActionIntent.create(
      walletId: walletId,
      kind: LedgerActionKind.hlUsdSend,
      params: {
        'destination': destination.toLowerCase(),
        'amount': wire,
        'quoteId': quoteId,
        if (reviewedActivationFeeBaseUnits != null)
          'activationFeeBaseUnits': reviewedActivationFeeBaseUnits.toString(),
      },
      summary: summary,
      sensitive: LedgerSensitiveIntentDraft(
        action: 'venueWithdraw',
        walletId: walletId,
        venue: 'hyperliquid',
        account: account,
        destination: destination.toLowerCase(),
        asset: hypercoreUsdcToken,
        amountMax: amountBaseUnits,
        limits: {
          'quoteId': quoteId,
          'decimals': 8,
          'balance': 'perpetuals',
          if (reviewedActivationFeeBaseUnits != null) ...{
            'activationFeeBaseUnits': reviewedActivationFeeBaseUnits.toString(),
            'activationFeeAsset': 'USDC',
          },
        },
        requiresStepUp: true,
      ),
      now: now,
    );
  }

  /// Native USDC only. The deposit address, amount and quote remain bound to
  /// the withdrawal's fresh app approval and the Ledger signature.
  static LedgerActionIntent spotSend({
    required String walletId,
    required String account,
    required String destination,
    required BigInt amountBaseUnits,
    required String quoteId,
    BigInt? reviewedActivationFeeBaseUnits,
    required Map<String, String> summary,
    DateTime? now,
  }) {
    if (!RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(destination) ||
        sameEvmAddress(account, destination) ||
        quoteId.isEmpty) {
      throw ArgumentError('Invalid native withdrawal destination or quote');
    }
    if (reviewedActivationFeeBaseUnits != null &&
        reviewedActivationFeeBaseUnits < BigInt.zero) {
      throw ArgumentError('Invalid activation fee');
    }
    final wire = hypercoreUsdcWire(amountBaseUnits);
    return LedgerActionIntent.create(
      walletId: walletId,
      kind: LedgerActionKind.hlSpotSend,
      params: {
        'destination': destination.toLowerCase(),
        'token': hypercoreUsdcToken,
        'amount': wire,
        'quoteId': quoteId,
        if (reviewedActivationFeeBaseUnits != null)
          'activationFeeBaseUnits': reviewedActivationFeeBaseUnits.toString(),
      },
      summary: summary,
      sensitive: LedgerSensitiveIntentDraft(
        action: 'venueWithdraw',
        walletId: walletId,
        venue: 'hyperliquid',
        account: account,
        destination: destination.toLowerCase(),
        asset: hypercoreUsdcToken,
        amountMax: amountBaseUnits,
        limits: {
          'quoteId': quoteId,
          'decimals': 8,
          if (reviewedActivationFeeBaseUnits != null) ...{
            'activationFeeBaseUnits': reviewedActivationFeeBaseUnits.toString(),
            'activationFeeAsset': 'USDC',
          },
        },
        requiresStepUp: true,
      ),
      now: now,
    );
  }

  static LedgerActionIntent approveBuilderFee({
    required String walletId,
    required String account,
    required String builder,
    required String maxFeeRate,
    required Map<String, String> summary,
    DateTime? now,
  }) =>
      LedgerActionIntent.create(
        walletId: walletId,
        kind: LedgerActionKind.hlApproveBuilderFee,
        params: {'builder': builder, 'maxFeeRate': maxFeeRate},
        summary: summary,
        sensitive: LedgerSensitiveIntentDraft(
          action: 'hlOrder',
          walletId: walletId,
          venue: 'hyperliquid',
          account: account,
          destination: builder,
          asset: 'USDC',
          amountMax: BigInt.zero,
          limits: {'maxFeeRate': maxFeeRate},
          requiresStepUp: false,
        ),
        now: now,
      );
}

// ──────────────────────────── executor ─────────────────────────────────

class _ActiveAction {
  _ActiveAction(this.intent, this.expected,
      {required this.exactKeys, this.beforeSend});
  final LedgerActionIntent intent;
  final Map<String, Object?> expected;
  final bool exactKeys;
  final Future<void> Function(int nonce)? beforeSend;
  String? recordId;
}

enum LedgerReconcileOutcome { confirmed, stillUnknown, notApplicable }

class LedgerHyperliquidExecutor {
  LedgerHyperliquidExecutor({
    required this.walletId,
    required this.pairedAddress,
    required EvmExternalSigner signer,
    required LedgerSubmittedActionStore store,
    required bool Function() geoAllowed,
    bool Function()? tradingEnabled,
    bool Function()? withdrawalsEnabled,
    this.checkCapability,
    LedgerActionGate? gate,
    http.Client? httpClient,
    DateTime Function()? clock,
  })  : _store = store,
        _geoAllowed = geoAllowed,
        _tradingEnabled = tradingEnabled ?? (() => true),
        _withdrawalsEnabled = withdrawalsEnabled ?? (() => true),
        _gate = gate ?? ((kind) => isLedgerActionAllowed(kind)),
        _httpClient = httpClient,
        _clock = clock ?? DateTime.now {
    if (!sameEvmAddress(signer.address, pairedAddress)) {
      throw ArgumentError('The Ledger signer must be the paired address');
    }
    _service = HyperliquidExchangeService(
      externalSigner: signer,
      walletAddress: pairedAddress,
      signatureChainId: kLedgerHyperliquidSignatureChainId,
      allowNonceRetry: false,
      httpClient: httpClient,
      onBeforePost: _beforePost,
    );
  }

  final Future<void> Function(LedgerActionIntent intent)? checkCapability;
  final String walletId;
  final String pairedAddress;
  final LedgerSubmittedActionStore _store;
  final bool Function() _geoAllowed;
  final bool Function() _tradingEnabled;
  final bool Function() _withdrawalsEnabled;
  final LedgerActionGate _gate;
  final http.Client? _httpClient;
  final DateTime Function() _clock;
  late final HyperliquidExchangeService _service;
  _ActiveAction? _active;

  bool get isBusy => _active != null;

  Future<HlOrderResult> placeOrder(LedgerActionIntent intent) {
    final p = intent.params;
    final builderAddress = p['builderAddress'] as String?;
    final builderFee = p['builderFeeTenthsBp'] as int?;
    final builder = builderAddress == null || builderFee == null
        ? null
        : HlBuilderFee(address: builderAddress, feeTenthsBp: builderFee);
    HlOrderWire wire() => HlOrderWire(
          assetId: intent.param<int>('assetId'),
          isBuy: intent.param<bool>('isBuy'),
          px: intent.param<String>('px'),
          sz: intent.param<String>('sz'),
          reduceOnly: intent.param<bool>('reduceOnly'),
          orderType: limitOrderType(intent.param<String>('tif')),
          cloid: intent.param<String>('cloid'),
        );
    return _execute(
      intent,
      LedgerActionKind.hlOrder,
      expected: () => buildOrderAction(orders: [wire()], builder: builder),
      run: () {
        final w = wire();
        return _service.placeLimitOrder(
          assetId: w.assetId,
          isBuy: w.isBuy,
          px: w.px,
          sz: w.sz,
          tif: intent.param<String>('tif'),
          reduceOnly: w.reduceOnly,
          cloid: w.cloid,
          builder: builder,
        );
      },
      oidOf: (r) => r.oid,
    );
  }

  Future<HlOrderResult> placeTrailingStop(
    LedgerActionIntent intent, {
    required HlMarket market,
    required HlTrailingStop trail,
    required double size,
    required double referencePrice,
    void Function()? beforeSend,
  }) => _execute(
    intent,
    LedgerActionKind.hlTrailingStop,
    expected: () => Map<String, Object?>.from(intent.params['action'] as Map),
    run: () => _service.placeTrailingStopOrder(
      market: market,
      isBuy: intent.param<bool>('isBuy'),
      size: size,
      trail: trail,
      reduceOnly: intent.param<bool>('reduceOnly'),
      referencePrice: referencePrice,
      beforeSend: () {
        if (!_enabledFor(intent)) {
          throw const LedgerHyperliquidDisabledException();
        }
        beforeSend?.call();
      },
    ),
    oidOf: (r) => r.oid,
  );

  Future<void> cancelOrder(LedgerActionIntent intent) => _execute(
        intent,
        LedgerActionKind.hlCancel,
        expected: () => buildCancelAction([
          (
            assetId: intent.param<int>('assetId'),
            oid: intent.param<int>('oid')
          ),
        ]),
        run: () => _service.cancelOrder(
            assetId: intent.param<int>('assetId'),
            oid: intent.param<int>('oid')),
      );

  Future<void> updateLeverage(LedgerActionIntent intent) => _execute(
        intent,
        LedgerActionKind.hlUpdateLeverage,
        expected: () => buildUpdateLeverageAction(
          assetId: intent.param<int>('assetId'),
          isCross: intent.param<bool>('isCross'),
          leverage: intent.param<int>('leverage'),
        ),
        run: () => _service.updateLeverage(
          assetId: intent.param<int>('assetId'),
          isCross: intent.param<bool>('isCross'),
          leverage: intent.param<int>('leverage'),
        ),
      );

  Future<void> usdClassTransfer(LedgerActionIntent intent,
          {Future<void> Function(int nonce)? onBeforeSend,
          void Function()? beforeSend}) =>
      _execute(
        intent,
        LedgerActionKind.hlUsdClassTransfer,
        exactKeys: false,
        beforeSend: onBeforeSend,
        expected: () => {
          'type': 'usdClassTransfer',
          'amount': intent.param<String>('amount'),
          'toPerp': intent.param<bool>('toPerp'),
          'signatureChainId':
              '0x${kLedgerHyperliquidSignatureChainId.toRadixString(16)}',
        },
        run: () => _service.usdClassTransfer(
          amount: double.parse(intent.param<String>('amount')),
          toPerp: intent.param<bool>('toPerp'),
          beforeSend: () {
            if (!_enabledFor(intent)) {
              throw const LedgerHyperliquidDisabledException();
            }
            beforeSend?.call();
          },
        ),
      );

  Future<int> usdSend(LedgerActionIntent intent,
      {required Future<void> Function(int nonce) onBeforeSend,
      void Function()? beforeSend}) {
    return _execute(
      intent,
      LedgerActionKind.hlUsdSend,
      exactKeys: false,
      beforeSend: onBeforeSend,
      expected: () => {
        'type': 'usdSend',
        'destination': intent.param<String>('destination'),
        'amount': intent.param<String>('amount'),
        'signatureChainId':
            '0x${kLedgerHyperliquidSignatureChainId.toRadixString(16)}',
      },
      run: () => _service.usdSend(
        destination: intent.param<String>('destination'),
        amount: intent.param<String>('amount'),
        beforeSend: () {
          if (!_enabledFor(intent)) {
            throw const LedgerHyperliquidDisabledException();
          }
          beforeSend?.call();
        },
      ),
    );
  }

  Future<int> spotSend(LedgerActionIntent intent,
      {required Future<void> Function(int nonce) onBeforeSend,
      void Function()? beforeSend}) {
    if (intent.params['token'] != hypercoreUsdcToken) {
      throw const LedgerIntentMismatchException('native USDC token');
    }
    return _execute(
      intent,
      LedgerActionKind.hlSpotSend,
      exactKeys: false,
      beforeSend: onBeforeSend,
      expected: () => {
        'type': 'spotSend',
        'destination': intent.param<String>('destination'),
        'token': hypercoreUsdcToken,
        'amount': intent.param<String>('amount'),
        'signatureChainId':
            '0x${kLedgerHyperliquidSignatureChainId.toRadixString(16)}',
      },
      run: () => _service.spotSend(
        destination: intent.param<String>('destination'),
        token: hypercoreUsdcToken,
        amount: intent.param<String>('amount'),
        beforeSend: () {
          if (!_enabledFor(intent)) {
            throw const LedgerHyperliquidDisabledException();
          }
          beforeSend?.call();
        },
      ),
    );
  }

  /// O17: one explicit, readable prompt before the first Ledger order.
  Future<void> approveBuilderFee(LedgerActionIntent intent) => _execute(
        intent,
        LedgerActionKind.hlApproveBuilderFee,
        exactKeys: false,
        expected: () => {
          'type': 'approveBuilderFee',
          'builder': intent.param<String>('builder').toLowerCase(),
          'maxFeeRate': intent.param<String>('maxFeeRate'),
          'signatureChainId':
              '0x${kLedgerHyperliquidSignatureChainId.toRadixString(16)}',
        },
        run: () => _service.approveBuilderFee(
          builder: intent.param<String>('builder'),
          maxFeeRate: intent.param<String>('maxFeeRate'),
        ),
      );

  Future<T> _execute<T>(
    LedgerActionIntent intent,
    LedgerActionKind kind, {
    required Map<String, Object?> Function() expected,
    required Future<T> Function() run,
    bool exactKeys = true,
    Future<void> Function(int nonce)? beforeSend,
    int? Function(T result)? oidOf,
  }) async {
    // Everything here runs before any device prompt.
    await checkCapability?.call(intent);
    if (intent.walletId != walletId) {
      throw const LedgerIntentMismatchException('wallet');
    }
    if (intent.kind != kind) throw const LedgerIntentMismatchException('kind');
    intent.verify();
    if (intent.sensitive.account != null &&
        !sameEvmAddress(intent.sensitive.account!, pairedAddress)) {
      throw const LedgerIntentMismatchException('account');
    }
    if (!_gate(kind)) throw LedgerActionBlockedException(kind);
    if (!isExistingFundsIntent(intent) && !_geoAllowed()) {
      throw const LedgerHyperliquidGeoBlockedException();
    }
    if (!_enabledFor(intent)) throw const LedgerHyperliquidDisabledException();
    if (_active != null) throw const LedgerFailure(LedgerFailureCode.busy);

    final active = _ActiveAction(intent, expected(),
        exactKeys: exactKeys, beforeSend: beforeSend);
    _active = active;
    try {
      final result = await LedgerOperationScope.run(walletId, run);
      final id = active.recordId;
      if (id != null) {
        await _store.updateStage(walletId, id, LedgerSubmissionStage.accepted,
            oid: oidOf?.call(result));
      }
      return result;
    } on HyperliquidRejectedException {
      final id = active.recordId;
      if (id != null) {
        await _store.updateStage(walletId, id, LedgerSubmissionStage.rejected);
      }
      rethrow;
    } catch (error) {
      final id = active.recordId;
      if (id != null && error is! LedgerIntentMismatchException) {
        await _store.updateStage(
            walletId, id, LedgerSubmissionStage.submittedUnknown);
        throw LedgerSubmissionUnknownException(id, error);
      }
      rethrow;
    } finally {
      _active = null;
    }
  }

  static bool isReducingOrder(LedgerActionIntent intent) {
    if (intent.kind != LedgerActionKind.hlOrder &&
        intent.kind != LedgerActionKind.hlTrailingStop) {
      return false;
    }
    final asset = intent.params['assetId'];
    // Protocol spot ids start at 10,000; HIP-3 perp ids start at 100,000.
    return intent.params['reduceOnly'] == true ||
        (asset is int &&
            asset >= 10000 &&
            asset < 100000 &&
            intent.params['isBuy'] == false);
  }

  static bool isExistingFundsIntent(LedgerActionIntent intent) =>
      intent.kind == LedgerActionKind.hlCancel ||
      isReducingOrder(intent) ||
      intent.kind == LedgerActionKind.hlSpotSend ||
      intent.kind == LedgerActionKind.hlUsdSend ||
      (intent.kind == LedgerActionKind.hlUsdClassTransfer &&
          (intent.params['toPerp'] == false ||
           (intent.params['withdrawalQuoteId'] is String &&
            (intent.params['withdrawalQuoteId'] as String).isNotEmpty)));

  bool _enabledFor(LedgerActionIntent intent) {
    if (isExistingFundsIntent(intent)) return _withdrawalsEnabled();
    return _tradingEnabled();
  }

  Future<void> _beforePost(HlPendingPost post) async {
    final active = _active;
    if (active == null) {
      throw const LedgerIntentMismatchException('no reviewed intent');
    }
    if (!_enabledFor(active.intent)) {
      throw const LedgerHyperliquidDisabledException();
    }
    await checkCapability?.call(active.intent);
    final action = post.action;
    if (active.exactKeys &&
        action.keys
            .toSet()
            .difference(active.expected.keys.toSet())
            .isNotEmpty) {
      throw const LedgerIntentMismatchException('payload');
    }
    for (final entry in active.expected.entries) {
      if (jsonEncode(action[entry.key]) != jsonEncode(entry.value)) {
        throw const LedgerIntentMismatchException('payload');
      }
    }
    // The funding operation must durably bind the nonce and recheck quote
    // expiry after device approval before any POST can move funds.
    await active.beforeSend?.call(post.nonce);
    final id = 'hl-${post.nonce}';
    await _store.recordBeforeSubmit(LedgerSubmittedAction(
      id: id,
      walletId: walletId,
      kind: active.intent.kind.name,
      paramsHash: active.intent.paramsHash,
      stage: LedgerSubmissionStage.submitting,
      submittedAtMs: _clock().millisecondsSinceEpoch,
      nonce: post.nonce,
      cloid: active.intent.params['cloid'] as String?,
    ));
    active.recordId = id;
  }

  /// Reads venue state for an unknown submission. Never signs or posts an
  /// action. Orders reconcile through `orderStatus` by client order ID;
  /// transfers through non-funding ledger updates after the submission.
  Future<LedgerReconcileOutcome> reconcile(String recordId) async {
    final record = await _store.get(walletId, recordId);
    if (record == null) return LedgerReconcileOutcome.notApplicable;
    if (record.stage != LedgerSubmissionStage.submittedUnknown &&
        record.stage != LedgerSubmissionStage.submitting) {
      return LedgerReconcileOutcome.notApplicable;
    }
    final cloid = record.cloid;
    if (cloid != null) {
      final body = await _info({
        'type': 'orderStatus',
        'user': pairedAddress,
        'oid': cloid,
      });
      if (body is Map && body['status'] == 'order') {
        final order = body['order'];
        final oid = order is Map && order['order'] is Map
            ? (order['order']['oid'] as num?)?.toInt()
            : null;
        if (oid != null) {
          await HyperliquidRevenue.linkOrder(pairedAddress, cloid, oid);
        }
        await _store.updateStage(
            walletId, recordId, LedgerSubmissionStage.confirmed,
            oid: oid);
        return LedgerReconcileOutcome.confirmed;
      }
      return LedgerReconcileOutcome.stillUnknown;
    }
    if (record.kind != 'hlUsdClassTransfer') {
      return LedgerReconcileOutcome.stillUnknown;
    }
    const deltaType = 'accountClassTransfer';
    final body = await _info({
      'type': 'userNonFundingLedgerUpdates',
      'user': pairedAddress,
      'startTime': record.submittedAtMs - 5000,
    });
    if (body is List) {
      for (final update in body) {
        if (update is! Map || update['delta'] is! Map) continue;
        final type = (update['delta'] as Map)['type'];
        if (type == deltaType) {
          await _store.updateStage(
              walletId, recordId, LedgerSubmissionStage.confirmed);
          return LedgerReconcileOutcome.confirmed;
        }
      }
    }
    return LedgerReconcileOutcome.stillUnknown;
  }

  Future<Object?> _info(Map<String, Object?> request) async {
    const headers = {'content-type': 'application/json'};
    final body = jsonEncode(request);
    final client = _httpClient;
    final resp = await (client != null
            ? client.post(HyperliquidConstants.infoUri,
                headers: headers, body: body)
            : http.post(HyperliquidConstants.infoUri,
                headers: headers, body: body))
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      throw http.ClientException('info ${request['type']} failed');
    }
    return jsonDecode(resp.body);
  }
}
