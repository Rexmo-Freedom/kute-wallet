// lib/services/hardware/ledger/ledger_polymarket_executor.dart
//
// Ledger-only Polymarket execution (Wallet hardening Phase 3, plan B9).
//
// * No signing-key parameter exists. The only signing authority is the
//   Ledger's external signer. The executor holds CLOB API HMAC credentials
//   for the Ledger wallet ID, which cannot sign orders or transfers.
// * EOA ClobAuth runs at the first trade only; credentials are
//   stored under `pm_api_credentials_<walletId>` for THIS wallet.
// * Sell is a sigType 3 order. The order ID recorded before the POST is
//   the Exchange-domain Order hash, not the TypedDataSign digest the
//   device signs, and it is checked against the response `orderID`.
// * Redeem, wrap, unwrap and withdraw go through a batch that is never
//   merged with another; every call passes `DepositWalletCallAllowlist`
//   before any prompt. Withdrawal stays behind O3.
// * Cancel follows O8: CLOB credentials only, no Ledger prompt. Copy must
//   never say the Ledger protects cancellation.
// * A legacy Safe account is read-only (O4).

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:kute/models/affiliate_model.dart' show AffiliateService;
import 'package:kute/constants/feature_flags.dart';
import 'package:kute/constants/polymarket_constants.dart';
import 'package:kute/services/hardware/evm_signing_request.dart';
import 'package:kute/services/hardware/ledger/deposit_wallet_call_allowlist.dart';
import 'package:kute/services/hardware/ledger/ledger_action_intent.dart';
import 'package:kute/services/hardware/ledger/ledger_evm_signer.dart'
    show LedgerActionGate;
import 'package:kute/services/hardware/ledger/ledger_failure.dart';
import 'package:kute/services/hardware/ledger/ledger_hyperliquid_executor.dart'
    show LedgerSubmissionUnknownException;
import 'package:kute/services/hardware/ledger/ledger_submitted_action_store.dart';
import 'package:kute/services/hardware/signing_clarity.dart';
import 'package:kute/services/polymarket/deposit_wallet_batch_signer.dart';
import 'package:kute/services/polymarket/clob_auth.dart';
import 'package:kute/services/polymarket/ledger_pm_trade.dart';
import 'package:kute/services/polymarket/polymarket_account_resolver.dart';
import 'package:kute/services/polymarket_backend_service.dart';
import 'package:kute/services/polymarket_onboarding_service.dart';
import 'package:kute/services/polymarket_order_v2.dart';
import 'package:kute/services/secure_storage.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show ApiCredentials, OrderType;
import 'package:kute/services/hardware/ledger/ledger_operation_scope.dart';

// ────────────────────────────── ports ──────────────────────────────────

abstract class LedgerPolymarketClob {
  /// Derives (or creates) CLOB API credentials from L1 ClobAuth headers.
  Future<ApiCredentials> deriveApiKey(Map<String, String> l1Headers);

  Future<Map<String, dynamic>> submitOrder({
    required ApiCredentials credentials,
    required String polyAddress,
    required SignedOrderV2 order,
    required OrderType orderType,
  });

  Future<void> cancelOrder({
    required ApiCredentials credentials,
    required String polyAddress,
    required String orderId,
  });
}

/// Authenticated reads required before a Ledger purchase. Kept separate from
/// the existing sell transport so exits do not depend on the buying surface.
abstract class LedgerPolymarketOrderReads {
  Future<Map<String, dynamic>> collateral(
      ApiCredentials credentials, String authAddress);
  Future<List<Map<String, dynamic>>> openOrders(
      ApiCredentials credentials, String authAddress);
  Future<Map<String, dynamic>?> order(
      ApiCredentials credentials, String authAddress, String orderId);
  Future<Map<String, dynamic>> submitBuyOrder({
    required ApiCredentials credentials,
    required String authAddress,
    required SignedOrderV2 order,
    required OrderType orderType,
    required void Function() beforePost,
  });
}

abstract class LedgerPolymarketRelayer {
  Future<String> executeBatch({
    required String eoa,
    required DepositWalletBatchSigner signer,
    required String wallet,
    required List<DepositWalletCall> calls,
    required int deadline,
    required Future<void> Function(String relayerNonce) beforeSubmit,
    required Future<void> Function(String relayerTxId) onSubmitted,
  });

  Future<({String state, String? hash})?> transactionState(String txId);
}

abstract class LedgerCredentialStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class HttpLedgerPolymarketClob
    implements LedgerPolymarketClob, LedgerPolymarketOrderReads {
  HttpLedgerPolymarketClob({http.Client? client}) : _client = client;

  final http.Client? _client;

  @override
  Future<ApiCredentials> deriveApiKey(Map<String, String> l1Headers) =>
      PolymarketClobAuth(client: _client).deriveOrCreate(l1Headers);

  PolymarketBackendService _service(ApiCredentials c, String polyAddress) =>
      PolymarketBackendService(
        apiKey: c.apiKey,
        secret: c.secret,
        passphrase: c.passphrase,
        walletAddress: polyAddress,
      );

  @override
  Future<Map<String, dynamic>> submitOrder({
    required ApiCredentials credentials,
    required String polyAddress,
    required SignedOrderV2 order,
    required OrderType orderType,
  }) =>
      _service(credentials, polyAddress)
          .submitOrder(signedOrder: order, orderType: orderType);

  @override
  Future<void> cancelOrder({
    required ApiCredentials credentials,
    required String polyAddress,
    required String orderId,
  }) =>
      _service(credentials, polyAddress).cancelOrder(orderId);

  @override
  Future<Map<String, dynamic>> collateral(
      ApiCredentials credentials, String authAddress) async {
    final service = _service(credentials, authAddress);
    await service.updateBalanceAllowance(
        assetType: 'COLLATERAL', signatureType: 3);
    return service.getCollateralBalanceAllowance();
  }

  @override
  Future<List<Map<String, dynamic>>> openOrders(
          ApiCredentials credentials, String authAddress) =>
      _service(credentials, authAddress).getOpenOrderData();

  @override
  Future<Map<String, dynamic>?> order(
          ApiCredentials credentials, String authAddress, String orderId) =>
      _service(credentials, authAddress).getOrderById(orderId);

  @override
  Future<Map<String, dynamic>> submitBuyOrder({
    required ApiCredentials credentials,
    required String authAddress,
    required SignedOrderV2 order,
    required OrderType orderType,
    required void Function() beforePost,
  }) =>
      _service(credentials, authAddress).submitOrder(
          signedOrder: order, orderType: orderType, beforePost: beforePost);
}

class OnboardingLedgerPolymarketRelayer implements LedgerPolymarketRelayer {
  OnboardingLedgerPolymarketRelayer([PolymarketOnboardingService? onboarding])
      : _onboarding = onboarding ?? PolymarketOnboardingService();

  final PolymarketOnboardingService _onboarding;

  @override
  Future<String> executeBatch({
    required String eoa,
    required DepositWalletBatchSigner signer,
    required String wallet,
    required List<DepositWalletCall> calls,
    required int deadline,
    required Future<void> Function(String relayerNonce) beforeSubmit,
    required Future<void> Function(String relayerTxId) onSubmitted,
  }) =>
      _onboarding.executeDepositWalletBatch(
        eoaAddress: eoa,
        signer: signer,
        walletAddress: wallet,
        calls: calls,
        deadline: deadline,
        beforeSubmit: beforeSubmit,
        onSubmitted: onSubmitted,
        requireConfirmed: true,
      );

  @override
  Future<({String state, String? hash})?> transactionState(String txId) =>
      _onboarding.relayerTransactionState(txId);
}

class SecureLedgerCredentialStorage implements LedgerCredentialStorage {
  const SecureLedgerCredentialStorage();

  @override
  Future<String?> read(String key) => secureStorage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      secureStorage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => secureStorage.delete(key: key);
}

// ──────────────────────────── exceptions ───────────────────────────────

class LedgerPolymarketAuthException implements Exception {
  const LedgerPolymarketAuthException();
}

/// The resolved account cannot act for a Ledger (legacy Safe, none, or
/// uncertain).
class LedgerPolymarketAccountUnsupportedException implements Exception {
  const LedgerPolymarketAccountUnsupportedException(this.kind);
  final PolymarketAccountKind kind;
}

class LedgerPolymarketOrderRejectedException implements Exception {
  const LedgerPolymarketOrderRejectedException(this.reason);
  final String reason;
}

class LedgerOrderIdMismatchException implements Exception {
  const LedgerOrderIdMismatchException();
}

class LedgerPmOrderResult {
  const LedgerPmOrderResult({required this.orderId, required this.status});
  final String orderId;
  final String status;
  bool get matched => status.toUpperCase() == 'MATCHED';
}

/// CLOB credential key for a wallet; identical to the hot provider's key
/// scheme and cleared by `SettingsModel.removeWallet`.
String polymarketCredentialsKey(String walletId) =>
    'pm_api_credentials_$walletId';

// ───────────────────────────── intents ─────────────────────────────────

abstract final class LedgerPolymarketIntents {
  static LedgerActionIntent buy({
    required String walletId,
    required String depositWallet,
    required String tokenId,
    required BigInt maxSpend,
    required BigInt minShares,
    required BigInt maxPriceMicros,
    required bool negRisk,
    required BigInt salt,
    required int timestampMs,
    required OrderType orderType,
    required String builderCode,
    required Map<String, String> summary,
    BigInt? feeReserve,
  }) =>
      LedgerActionIntent.create(
        walletId: walletId,
        kind: LedgerActionKind.pmOrder,
        params: {
          'side': 'BUY',
          'depositWallet': depositWallet,
          'tokenId': tokenId,
          'makerAmount': maxSpend,
          'takerAmount': minShares,
          'maxPriceMicros': maxPriceMicros,
          'negRisk': negRisk,
          'salt': salt,
          'timestampMs': timestampMs,
          'orderType': orderType.value,
          'builder': builderCode,
          'metadata': PolymarketConstants.bytes32Zero,
          // Venue fees the account must hold beside the stake. Not part of
          // the signed order; checked against cash and allowance.
          'feeReserve': feeReserve ?? BigInt.zero,
        },
        summary: summary,
        sensitive: LedgerSensitiveIntentDraft(
          action: 'pmBet',
          walletId: walletId,
          venue: 'polymarket',
          account: depositWallet,
          destination: tokenId,
          asset: 'PUSD',
          amountMax: maxSpend,
          limits: {
            'minShares': minShares,
            'maxPriceMicros': maxPriceMicros,
            'orderType': orderType.value
          },
          requiresStepUp: true,
        ),
        now: DateTime.fromMillisecondsSinceEpoch(timestampMs),
      );

  static LedgerActionIntent authenticate({
    required String walletId,
    required String depositWallet,
    required Map<String, String> summary,
  }) =>
      LedgerActionIntent.create(
        walletId: walletId,
        kind: LedgerActionKind.pmClobAuth,
        params: {'depositWallet': depositWallet, 'op': 'authenticate'},
        summary: summary,
        sensitive: LedgerSensitiveIntentDraft(
          action: 'pmBet',
          walletId: walletId,
          venue: 'polymarket',
          account: depositWallet,
          asset: 'PUSD',
          amountMax: BigInt.zero,
          requiresStepUp: false,
        ),
      );

  static LedgerActionIntent approveTrading({
    required String walletId,
    required String depositWallet,
    required BigInt amount,
    required bool negRisk,
    required Map<String, String> summary,
  }) =>
      LedgerActionIntent.create(
        walletId: walletId,
        kind: LedgerActionKind.pmDepositWalletBatch,
        params: {
          'op': 'approveTrade',
          'depositWallet': depositWallet,
          'amount': amount,
          'negRisk': negRisk
        },
        summary: summary,
        sensitive: LedgerSensitiveIntentDraft(
          action: 'pmBet',
          walletId: walletId,
          venue: 'polymarket',
          account: depositWallet,
          asset: 'PUSD',
          amountMax: amount,
          requiresStepUp: false,
        ),
      );

  /// A sigType 3 SELL of [shares] outcome tokens for at least [minProceeds]
  /// pUSD (both 6-decimal base units).
  static LedgerActionIntent sell({
    required String walletId,
    required String depositWallet,
    required String tokenId,
    required BigInt shares,
    required BigInt minProceeds,
    required bool negRisk,
    required BigInt salt,
    required int timestampMs,
    required OrderType orderType,
    required String builderCode,
    String metadata = PolymarketConstants.bytes32Zero,
    required Map<String, String> summary,
    DateTime? now,
  }) =>
      LedgerActionIntent.create(
        walletId: walletId,
        kind: LedgerActionKind.pmOrder,
        params: {
          'depositWallet': depositWallet,
          'tokenId': tokenId,
          'makerAmount': shares,
          'takerAmount': minProceeds,
          'negRisk': negRisk,
          'salt': salt,
          'timestampMs': timestampMs,
          'orderType': orderType.value,
          'builder': builderCode,
          'metadata': metadata,
        },
        summary: summary,
        sensitive: LedgerSensitiveIntentDraft(
          action: 'pmSell',
          walletId: walletId,
          venue: 'polymarket',
          account: depositWallet,
          destination: tokenId,
          asset: 'PUSD',
          amountMax: shares,
          limits: {'minReceive': minProceeds, 'orderType': orderType.value},
          requiresStepUp: true,
        ),
        now: now,
      );

  static LedgerActionIntent redeem({
    required String walletId,
    required String depositWallet,
    required String conditionId,
    required bool negRisk,
    required Map<String, String> summary,
    DateTime? now,
  }) =>
      LedgerActionIntent.create(
        walletId: walletId,
        kind: LedgerActionKind.pmDepositWalletBatch,
        params: {
          'op': 'redeem',
          'depositWallet': depositWallet,
          'conditionId': conditionId,
          'negRisk': negRisk,
        },
        summary: summary,
        sensitive: LedgerSensitiveIntentDraft(
          action: 'pmSell',
          walletId: walletId,
          venue: 'polymarket',
          account: depositWallet,
          destination: conditionId,
          asset: 'PUSD',
          amountMax: BigInt.zero,
          requiresStepUp: false,
        ),
        now: now,
      );

  /// "Make funds available": approve the onramp for exactly [amount]
  /// USDC.e, then wrap it into pUSD in the same batch.
  static LedgerActionIntent wrap({
    required String walletId,
    required String depositWallet,
    required BigInt amount,
    required Map<String, String> summary,
    DateTime? now,
  }) =>
      _collateral('wrap', walletId, depositWallet, amount, summary, now,
          action: 'venueDeposit');

  static LedgerActionIntent unwrap({
    required String walletId,
    required String depositWallet,
    required BigInt amount,
    required Map<String, String> summary,
    DateTime? now,
  }) =>
      _collateral('unwrap', walletId, depositWallet, amount, summary, now,
          action: 'venueWithdraw');

  static LedgerActionIntent _collateral(String op, String walletId,
          String depositWallet, BigInt amount, Map<String, String> summary,
          DateTime? now,
          {required String action}) =>
      LedgerActionIntent.create(
        walletId: walletId,
        kind: LedgerActionKind.pmDepositWalletBatch,
        params: {'op': op, 'depositWallet': depositWallet, 'amount': amount},
        summary: summary,
        sensitive: LedgerSensitiveIntentDraft(
          action: action,
          walletId: walletId,
          venue: 'polymarket',
          account: depositWallet,
          asset: 'USDC.e',
          amountMax: amount,
          requiresStepUp: false,
        ),
        now: now,
      );

  /// O3: USDC.e transfer to the quote-bound Orchestra deposit address.
  static LedgerActionIntent withdraw({
    required String walletId,
    required String depositWallet,
    required BigInt amount,
    required LedgerWithdrawalBinding binding,
    required Map<String, String> summary,
    DateTime? now,
  }) =>
      LedgerActionIntent.create(
        walletId: walletId,
        kind: LedgerActionKind.pmWithdrawal,
        params: {
          'depositWallet': depositWallet,
          'amount': amount,
          'depositAddress': binding.depositAddress,
          'refundAddress': binding.refundAddress,
          'recipientAddress': binding.recipientAddress,
        },
        summary: summary,
        sensitive: LedgerSensitiveIntentDraft(
          action: 'venueWithdraw',
          walletId: walletId,
          venue: 'orchestra',
          account: depositWallet,
          destination: binding.depositAddress,
          asset: 'USDC.e',
          amountMax: amount,
          limits: {'route': 'polygon_usdce_to_ledger_btc_v1'},
          requiresStepUp: true,
        ),
        now: now,
      );
}

// ──────────────────────────── executor ─────────────────────────────────

class LedgerPmSellResult {
  const LedgerPmSellResult({required this.orderId, this.status});
  final String orderId;

  /// The CLOB status (for example `matched` or `live`). "Sold" copy only on
  /// a matched status (plan B13).
  final String? status;
}

class LedgerPolymarketExecutor {
  LedgerPolymarketExecutor({
    required this.walletId,
    required this.pairedAddress,
    required EvmExternalSigner signer,
    required this.account,
    required LedgerSubmittedActionStore store,
    required LedgerPolymarketClob clob,
    required LedgerPolymarketRelayer relayer,
    LedgerCredentialStorage credentials = const SecureLedgerCredentialStorage(),
    LedgerActionGate? gate,
    this.checkCapability,
    this.withdrawEnabled = kLedgerPolymarketWithdrawEnabled,
    bool Function(String address)? belongsToLedger,
    DateTime Function()? clock,
  })  : _signer = signer,
        _store = store,
        _clob = clob,
        _relayer = relayer,
        _credentials = credentials,
        _gate = gate ??
            ((kind) => isLedgerActionAllowed(kind,
                polymarketWithdrawEnabled: withdrawEnabled)),
        _belongsToLedger = belongsToLedger ?? ((_) => false),
        _clock = clock ?? DateTime.now {
    if (!sameEvmAddress(signer.address, pairedAddress)) {
      throw ArgumentError('The Ledger signer must be the paired address');
    }
  }

  final Future<void> Function(String capability)? checkCapability;
  final String walletId;
  final String pairedAddress;
  final PolymarketLedgerAccount account;
  final bool withdrawEnabled;
  final EvmExternalSigner _signer;
  final LedgerSubmittedActionStore _store;
  final LedgerPolymarketClob _clob;
  final LedgerPolymarketRelayer _relayer;
  final LedgerCredentialStorage _credentials;
  final LedgerActionGate _gate;
  final bool Function(String address) _belongsToLedger;
  final DateTime Function() _clock;
  String? _apiKeyBoundAddress;
  static final Set<String> _busyWallets = {};

  bool get isBusy => _busyWallets.contains(account.address?.toLowerCase());

  String get _wallet {
    final address = account.address;
    if (!account.canAct || address == null) {
      throw LedgerPolymarketAccountUnsupportedException(account.kind);
    }
    return address;
  }

  // ── credentials (ClobAuth at the first trade only) ──

  Future<ApiCredentials?> _loadCredentials() async {
    final raw = await _credentials.read(polymarketCredentialsKey(walletId));
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      // Historical Ledger credentials were wallet-bound. Keep their binding
      // for existing cancellation/access until fresh credentials are needed.
      final boundAddress = PolymarketClobAuth.cachedAddress(map,
          ownerAddress: pairedAddress, depositWallet: _wallet,
          legacyWalletBinding: true);
      final ownerAddress = map['ownerAddress'];
      if (boundAddress == null ||
          (ownerAddress != null &&
           (ownerAddress is! String || !sameEvmAddress(ownerAddress, pairedAddress)))) {
        return null;
      }
      if (!['apiKey', 'secret', 'passphrase'].every(
          (key) => map[key] is String && (map[key] as String).isNotEmpty)) {
        return null;
      }
      _apiKeyBoundAddress = boundAddress;
      return ApiCredentials(
        apiKey: map['apiKey'] as String,
        secret: map['secret'] as String,
        passphrase: map['passphrase'] as String,
      );
    } catch (_) {
      return null;
    }
  }

  Future<ApiCredentials> _ensureCredentials() async {
    final existing = await _loadCredentials();
    if (existing != null &&
        sameEvmAddress(_apiKeyBoundAddress!, pairedAddress)) {
      return existing;
    }
    // Old wallet-bound credentials remain usable by cancelOrder. Before a
    // new trade, provision the documented EOA binding and replace the cache
    // only after successful authentication and storage.
    _wallet; // Resolve and validate the deposit account before prompting.
    if (!_gate(LedgerActionKind.pmClobAuth)) {
      throw const LedgerActionBlockedException(LedgerActionKind.pmClobAuth);
    }
    final timestamp = _clock().millisecondsSinceEpoch ~/ 1000;
    final headers = await PolymarketClobAuth.headers(
      externalSigner: _signer,
      address: pairedAddress,
      timestamp: timestamp,
    );
    final credentials = await _clob.deriveApiKey(headers);
    await _credentials.write(
      polymarketCredentialsKey(walletId),
      jsonEncode({
        'apiKey': credentials.apiKey,
        'secret': credentials.secret,
        'passphrase': credentials.passphrase,
        'nonce': 0,
        'ownerAddress': pairedAddress,
        'authAddress': pairedAddress,
      }),
    );
    _apiKeyBoundAddress = pairedAddress;
    return credentials;
  }

  // ── intent checks, all before any prompt ──

  void _checkIntent(LedgerActionIntent intent, LedgerActionKind kind) {
    if (intent.walletId != walletId) {
      throw const LedgerIntentMismatchException('wallet');
    }
    if (intent.kind != kind) throw const LedgerIntentMismatchException('kind');
    intent.verify();
    final wallet = _wallet;
    if (!sameEvmAddress(intent.param<String>('depositWallet'), wallet)) {
      throw const LedgerIntentMismatchException('account');
    }
  }

  Future<T> _exclusive<T>(Future<T> Function() body) async {
    final key = _wallet.toLowerCase();
    if (!_busyWallets.add(key)) throw const LedgerFailure(LedgerFailureCode.busy);
    try {
      return await LedgerOperationScope.run(walletId, body);
    } finally {
      _busyWallets.remove(key);
    }
  }

  // ── authenticated buying power and BUY ──

  LedgerPolymarketOrderReads get _orderReads {
    final clob = _clob;
    if (clob is! LedgerPolymarketOrderReads) {
      throw const LedgerPmTradeRefused(LedgerPmTradeRefusal.cashUnavailable);
    }
    return clob as LedgerPolymarketOrderReads;
  }

  Future<LedgerPmBuyingPower> _buyingPower(ApiCredentials credentials) async {
    final auth = _apiKeyBoundAddress;
    if (auth == null || !sameEvmAddress(auth, pairedAddress)) {
      throw const LedgerPolymarketAuthException();
    }
    final data = await Future.wait<Object>([
      _orderReads.collateral(credentials, auth),
      _orderReads.openOrders(credentials, auth),
    ]);
    return LedgerPmBuyingPower.fromClob(
        depositWallet: _wallet,
        collateral: data[0] as Map<String, dynamic>,
        orders: data[1] as List<Map<String, dynamic>>);
  }

  /// A screen read never asks the device for a credential signature.
  Future<LedgerPmBuyingPower?> readBuyingPower() async {
    final credentials = await _loadCredentials();
    if (credentials == null ||
        _apiKeyBoundAddress == null ||
        !sameEvmAddress(_apiKeyBoundAddress!, pairedAddress)) {
      return null;
    }
    return _buyingPower(credentials);
  }

  /// Cached credentials only: opening Orders never asks the device to sign.
  Future<List<Map<String, dynamic>>?> readOpenOrders() async {
    final credentials = await _loadCredentials();
    final auth = _apiKeyBoundAddress;
    if (credentials == null || auth == null ||
        !sameEvmAddress(auth, pairedAddress)) {
      return null;
    }
    return _orderReads.openOrders(credentials, auth);
  }

  Future<LedgerPmBuyingPower> authenticateForTrading(
      LedgerActionIntent intent) {
    _checkIntent(intent, LedgerActionKind.pmClobAuth);
    return _exclusive(() async {
      await checkCapability?.call('polymarket.trade');
      return _buyingPower(await _ensureCredentials());
    });
  }

  Future<LedgerSubmittedAction?> pendingOrder() =>
      _store.blockingPolymarketOrder(walletId);

  /// A BUY is reconstructed entirely from the reviewed intent. Fresh CLOB
  /// cash, reservations and allowances are checked before signing and again
  /// before the single POST. Unknown outcomes block subsequent orders.
  Future<LedgerPmOrderResult> buy(
    LedgerActionIntent intent, {
    required Future<void> Function() revalidate,
    required void Function() ensureCurrent,
  }) async {
    await checkCapability?.call('polymarket.trade');
    _checkIntent(intent, LedgerActionKind.pmOrder);
    if (!_gate(LedgerActionKind.pmOrder)) {
      throw const LedgerActionBlockedException(LedgerActionKind.pmOrder);
    }
    final spend = intent.param<BigInt>('makerAmount');
    final shares = intent.param<BigInt>('takerAmount');
    final price = intent.param<BigInt>('maxPriceMicros');
    if (intent.param<String>('side') != 'BUY' ||
        spend <= BigInt.zero ||
        shares <= BigInt.zero ||
        price <= BigInt.zero ||
        price >= BigInt.from(1000000) ||
        spend * BigInt.from(1000000) > shares * price) {
      throw const LedgerIntentMismatchException('buy bounds');
    }
    final orderType = OrderType.fromJson(intent.param<String>('orderType'));
    if (orderType == OrderType.gtc || orderType == OrderType.gtd) {
      await checkCapability?.call('trading.advanced');
    }
    if (orderType != OrderType.fok && orderType != OrderType.gtc) {
      throw const LedgerIntentMismatchException('buy order type');
    }
    final negRisk = intent.param<bool>('negRisk');
    final order = OrderStructV2(
        salt: intent.param<BigInt>('salt'),
        maker: _wallet,
        signer: _wallet,
        tokenId: intent.param<String>('tokenId'),
        makerAmount: spend,
        takerAmount: shares,
        side: 0,
        signatureType: 3,
        timestamp: BigInt.from(intent.param<int>('timestampMs')),
        metadata: intent.param<String>('metadata'),
        builder: intent.param<String>('builder'));
    final exchange = negRisk
        ? PolymarketConstants.negRiskExchangeAddress
        : PolymarketConstants.exchangeAddress;
    final orderId = exchangeOrderId(order, exchange);
    return _exclusive(() async {
      final LedgerSubmittedAction? pending;
      try {
        pending = await _store.blockingPolymarketOrder(walletId) ??
            await _store.blockingPolymarketBatch(walletId);
      } catch (error) {
        throw LedgerSubmissionUnknownException('pending-prediction', error);
      }
      if (pending != null) {
        throw LedgerSubmissionUnknownException(
            pending.id, StateError('Previous prediction needs review.'));
      }
      final credentials = await _ensureCredentials();
      // Intents recorded before the reserve existed carry none: they are
      // checked as before rather than refused.
      final reserved = intent.params['feeReserve'];
      final feeReserve =
          reserved is BigInt && reserved > BigInt.zero ? reserved : BigInt.zero;
      Future<void> checkCash() async {
        final power = await _buyingPower(credentials);
        if (power.spendable < spend + feeReserve) {
          throw const LedgerPmTradeRefused(
              LedgerPmTradeRefusal.insufficientCash);
        }
        if (power.allowance(negRisk) < spend + feeReserve) {
          throw const LedgerPmTradeRefused(
              LedgerPmTradeRefusal.allowanceRequired);
        }
      }

      await checkCash();
      await revalidate();
      ensureCurrent();
      final signature = await signOrderV2Poly1271(
          order: order, externalSigner: _signer, verifyingContract: exchange);
      await checkCapability?.call('polymarket.trade');
      if (orderType == OrderType.gtc || orderType == OrderType.gtd) {
        await checkCapability?.call('trading.advanced');
      }
      await checkCash();
      await revalidate();
      ensureCurrent();
      final recordId = 'pm-order-$orderId';
      await _store.recordBeforeSubmit(LedgerSubmittedAction(
          id: recordId,
          walletId: walletId,
          kind: intent.kind.name,
          paramsHash: intent.paramsHash,
          stage: LedgerSubmissionStage.submitting,
          submittedAtMs: _clock().millisecondsSinceEpoch,
          orderId: orderId));
      var postStarted = false;
      try {
        final response = await _orderReads.submitBuyOrder(
          credentials: credentials,
          authAddress: _apiKeyBoundAddress!,
          order: SignedOrderV2(order: order, signature: signature),
          orderType: orderType,
          beforePost: () {
            ensureCurrent();
            postStarted = true;
          },
        );
        final returned = (response['orderID'] ?? response['orderId'])
            ?.toString()
            .toLowerCase();
        final status = response['status']?.toString().toLowerCase();
        final refusal = response['errorMsg']?.toString() ?? '';
        if (response['success'] == false &&
            isDefinitivePolymarketOrderRejection(refusal) &&
            (returned == null || returned.isEmpty)) {
          await _store.updateStage(
              walletId, recordId, LedgerSubmissionStage.rejected, notAccepted: true);
          throw LedgerPolymarketOrderRejectedException(
              response['errorMsg']?.toString() ?? '');
        }
        if (!postStarted ||
            returned != orderId ||
            response['success'] != true ||
            !const {'matched', 'live', 'delayed', 'unmatched'}.contains(status)) {
          throw const LedgerOrderIdMismatchException();
        }
        await _store.updateStage(
            walletId, recordId, LedgerSubmissionStage.accepted);
        return LedgerPmOrderResult(orderId: orderId, status: status!);
      } on LedgerPolymarketOrderRejectedException {
        rethrow;
      } catch (error) {
        if (error is PolymarketOrderNotAcceptedException ||
            error is InvalidApiKeyException || error is GeoBlockException) {
          try {
            await _store.updateStage(walletId, recordId, LedgerSubmissionStage.rejected, notAccepted: true);
          } catch (writeError) {
            throw LedgerSubmissionUnknownException(recordId, writeError);
          }
          throw LedgerPolymarketOrderRejectedException(error.toString());
        }
        if (!postStarted) {
          await _store.updateStage(
              walletId, recordId, LedgerSubmissionStage.rejected, notAccepted: true);
          rethrow;
        }
        try {
          await _store.updateStage(
              walletId, recordId, LedgerSubmissionStage.submittedUnknown);
        } catch (_) {
          // The pre-POST record remains blocking, including failed flushes.
        }
        throw LedgerSubmissionUnknownException(recordId, error);
      }
    });
  }

  /// Authoritative read of the locally computed order ID. A 404 or unknown
  /// status leaves the journal blocked; it never authorizes a replacement.
  Future<LedgerPmOrderResult?> reconcileOrder(String recordId,
      {LedgerActionIntent? expectedIntent}) async {
    final record = await _store.get(walletId, recordId);
    if (record == null ||
        record.walletId != walletId ||
        record.kind != LedgerActionKind.pmOrder.name ||
        record.orderId == null ||
        record.id != 'pm-order-${record.orderId}' ||
        !RegExp(r'^0x[0-9a-fA-F]{64}$').hasMatch(record.orderId!)) {
      return null;
    }
    if (expectedIntent != null) {
      _checkIntent(expectedIntent, LedgerActionKind.pmOrder);
      if (record.paramsHash != expectedIntent.paramsHash) {
        throw const LedgerIntentMismatchException('order reconciliation');
      }
    }
    if (record.notAccepted) {
      await _store.updateStage(walletId, recordId, LedgerSubmissionStage.rejected, notAccepted: true);
      return LedgerPmOrderResult(orderId: record.orderId!, status: 'REJECTED');
    }
    final credentials = await _loadCredentials();
    if (credentials == null || _apiKeyBoundAddress == null) return null;
    final order = await _orderReads.order(
        credentials, _apiKeyBoundAddress!, record.orderId!);
    if (order == null) return null;
    if (order['id']?.toString().toLowerCase() !=
            record.orderId!.toLowerCase() ||
        !sameEvmAddress(order['maker_address']?.toString() ?? '', _wallet)) {
      return null;
    }
    final status = order['status']?.toString().toUpperCase();
    if (!const {
      'LIVE',
      'MATCHED',
      'DELAYED',
      'UNMATCHED',
      'CANCELED',
      'CANCELLED',
      'EXPIRED'
    }.contains(status)) {
      return null;
    }
    final matched = ledgerPmDecimalUnits(order['size_matched']);
    final cancelled =
        const {'CANCELED', 'CANCELLED', 'EXPIRED'}.contains(status) &&
            matched == BigInt.zero;
    await _store.updateStage(
        walletId,
        recordId,
        cancelled
            ? LedgerSubmissionStage.rejected
            : LedgerSubmissionStage.accepted);
    return LedgerPmOrderResult(orderId: record.orderId!, status: status!);
  }

  Future<String> approveTrading(LedgerActionIntent intent,
      {void Function()? beforeSubmit}) {
    _checkIntent(intent, LedgerActionKind.pmDepositWalletBatch);
    if (intent.param<String>('op') != 'approveTrade' ||
        intent.param<BigInt>('amount') <= BigInt.zero) {
      throw const LedgerIntentMismatchException('trade approval');
    }
    return _batch(
        intent,
        [
          (
            target: PolymarketConstants.pusdAddress,
            value: BigInt.zero,
            data: encodeApproveCall(
                intent.param<bool>('negRisk')
                    ? PolymarketConstants.negRiskExchangeAddress
                    : PolymarketConstants.exchangeAddress,
                intent.param<BigInt>('amount')),
          )
        ],
        beforeSubmit: beforeSubmit);
  }

  /// [revalidate] runs after the device signed and before anything is
  /// recorded or sent (the sheet re-reads the bid there); throwing from it
  /// sends nothing.
  Future<LedgerPmSellResult> sell(LedgerActionIntent intent,
      {Future<void> Function()? revalidate}) async {
    await checkCapability?.call('polymarket.close');
    _checkIntent(intent, LedgerActionKind.pmOrder);
    if (intent.params['side'] == 'BUY') {
      throw const LedgerIntentMismatchException('sell side');
    }
    if (!_gate(LedgerActionKind.pmOrder)) {
      throw const LedgerActionBlockedException(LedgerActionKind.pmOrder);
    }
    final wallet = _wallet;
    final order = OrderStructV2(
      salt: intent.param<BigInt>('salt'),
      maker: wallet,
      signer: wallet,
      tokenId: intent.param<String>('tokenId'),
      makerAmount: intent.param<BigInt>('makerAmount'),
      takerAmount: intent.param<BigInt>('takerAmount'),
      side: 1,
      signatureType: 3,
      timestamp: BigInt.from(intent.param<int>('timestampMs')),
      metadata: intent.param<String>('metadata'),
      builder: intent.param<String>('builder'),
    );
    final orderType = OrderType.fromJson(intent.param<String>('orderType'));
    if (orderType == OrderType.gtc || orderType == OrderType.gtd) {
      await checkCapability?.call('trading.advanced');
    }
    final verifyingContract = intent.param<bool>('negRisk')
        ? PolymarketConstants.negRiskExchangeAddress
        : PolymarketConstants.exchangeAddress;
    final orderId = exchangeOrderId(order, verifyingContract);

    return _exclusive(() async {
      final credentials = await _ensureCredentials();
      final signature = await signOrderV2Poly1271(
        order: order,
        externalSigner: _signer,
        verifyingContract: verifyingContract,
      );
      await revalidate?.call();
      final recordId = 'pm-order-$orderId';
      await _store.recordBeforeSubmit(LedgerSubmittedAction(
        id: recordId,
        walletId: walletId,
        kind: intent.kind.name,
        paramsHash: intent.paramsHash,
        stage: LedgerSubmissionStage.submitting,
        submittedAtMs: _clock().millisecondsSinceEpoch,
        orderId: orderId,
      ));

      // Use the same Kute user attribution as the spending wallet. Persist
      // before POST so an unknown submission can still match builder fills.
      await AffiliateService.logProviderEvent(
        provider: 'polymarket', providerOrderId: orderId, status: 'pending',
        sourceAsset: 'pm_shares', sourceAmount: order.makerAmount.toDouble() / 1e6,
        destinationAsset: 'USDC', destinationAmount: order.takerAmount.toDouble() / 1e6,
      );
      final Map<String, dynamic> response;
      try {
        response = await _clob.submitOrder(
          credentials: credentials,
          polyAddress: _apiKeyBoundAddress!,
          order: SignedOrderV2(order: order, signature: signature),
          orderType: orderType,
        );
      } on InvalidApiKeyException {
        await _store.updateStage(
            walletId, recordId, LedgerSubmissionStage.rejected);
        rethrow;
      } on GeoBlockException {
        await _store.updateStage(
            walletId, recordId, LedgerSubmissionStage.rejected);
        rethrow;
      } catch (error) {
        await _store.updateStage(
            walletId, recordId, LedgerSubmissionStage.submittedUnknown);
        throw LedgerSubmissionUnknownException(recordId, error);
      }

      final returned = (response['orderID'] ?? response['orderId'])?.toString();
      if (returned != null &&
          returned.isNotEmpty &&
          returned.toLowerCase() != orderId) {
        await _store.updateStage(
            walletId, recordId, LedgerSubmissionStage.orderIdMismatch);
        throw const LedgerOrderIdMismatchException();
      }
      final error = response['errorMsg']?.toString() ?? '';
      if (response['success'] == false || error.isNotEmpty) {
        await _store.updateStage(
            walletId, recordId, LedgerSubmissionStage.rejected);
        throw LedgerPolymarketOrderRejectedException(error);
      }
      await _store.updateStage(
          walletId, recordId, LedgerSubmissionStage.accepted);
      return LedgerPmSellResult(
          orderId: orderId, status: response['status']?.toString());
    });
  }

  // ── batches ──

  Future<String> redeem(LedgerActionIntent intent) {
    _checkIntent(intent, LedgerActionKind.pmDepositWalletBatch);
    if (intent.param<String>('op') != 'redeem') {
      throw const LedgerIntentMismatchException('op');
    }
    final target = intent.param<bool>('negRisk')
        ? PolymarketConstants.negRiskCtfCollateralAdapterAddress
        : PolymarketConstants.ctfCollateralAdapterAddress;
    return _batch(intent, [
      (
        target: target,
        value: BigInt.zero,
        data: encodeAdapterRedeemCall(intent.param<String>('conditionId')),
      ),
    ]);
  }

  Future<String> wrap(LedgerActionIntent intent) {
    _checkIntent(intent, LedgerActionKind.pmDepositWalletBatch);
    if (intent.param<String>('op') != 'wrap') {
      throw const LedgerIntentMismatchException('op');
    }
    final amount = intent.param<BigInt>('amount');
    return _batch(intent, [
      (
        target: PolymarketConstants.usdcEAddress,
        value: BigInt.zero,
        data: encodeApproveCall(
            PolymarketConstants.collateralOnrampAddress, amount),
      ),
      (
        target: PolymarketConstants.collateralOnrampAddress,
        value: BigInt.zero,
        data: encodeWrapCall(PolymarketConstants.usdcEAddress, _wallet, amount),
      ),
    ]);
  }

  Future<String> unwrap(
    LedgerActionIntent intent, {
    void Function()? beforeSubmit,
  }) {
    _checkIntent(intent, LedgerActionKind.pmDepositWalletBatch);
    if (intent.param<String>('op') != 'unwrap') {
      throw const LedgerIntentMismatchException('op');
    }
    return _batch(
      intent,
      [
        (
          target: PolymarketConstants.collateralOfframpAddress,
          value: BigInt.zero,
          data: encodeUnwrapCall(PolymarketConstants.usdcEAddress, _wallet,
              intent.param<BigInt>('amount')),
        ),
      ],
      beforeSubmit: beforeSubmit,
    );
  }

  /// O3. Refused before anything else while the flag is off.
  ///
  /// [beforeSubmit] runs after the Ledger signature and immediately before
  /// the relayer POST (Phase 4b late quote check). A throw aborts with
  /// nothing sent and no submission record.
  ///
  /// [onRelayerSubmitted] receives the relayer transaction id once the
  /// relayer accepted the batch and before any polling (Phase 5 plan B7),
  /// so the settlement record holds it even if the app is killed while
  /// polling. The batch is always its own relayer transaction; it is never
  /// merged with another (Phase 3 B3).
  Future<String> withdraw(
    LedgerActionIntent intent, {
    void Function()? beforeSubmit,
    Future<void> Function(String relayerTxId)? onRelayerSubmitted,
  }) {
    if (!withdrawEnabled || !_gate(LedgerActionKind.pmWithdrawal)) {
      throw const LedgerActionBlockedException(LedgerActionKind.pmWithdrawal);
    }
    _checkIntent(intent, LedgerActionKind.pmWithdrawal);
    final binding = LedgerWithdrawalBinding(
      depositAddress: intent.param<String>('depositAddress'),
      refundAddress: intent.param<String>('refundAddress'),
      recipientAddress: intent.param<String>('recipientAddress'),
    );
    return _batch(
      intent,
      [
        (
          target: PolymarketConstants.usdcEAddress,
          value: BigInt.zero,
          data: encodeTransferCall(
              binding.depositAddress, intent.param<BigInt>('amount')),
        ),
      ],
      binding: binding,
      beforeSubmit: beforeSubmit,
      onRelayerSubmitted: onRelayerSubmitted,
    );
  }

  Future<String> _batch(
    LedgerActionIntent intent,
    List<DepositWalletCall> calls, {
    LedgerWithdrawalBinding? binding,
    void Function()? beforeSubmit,
    Future<void> Function(String relayerTxId)? onRelayerSubmitted,
  }) {
    final wallet = _wallet;
    DepositWalletCallAllowlist(
      depositWallet: wallet,
      withdrawalBinding: binding,
      belongsToLedger: _belongsToLedger,
      withdrawEnabled: withdrawEnabled,
    ).validate(calls);
    final kind = depositWalletBatchKind(calls.map((c) => c.data));
    if (kind != intent.kind) throw const LedgerIntentMismatchException('kind');
    if (!_gate(kind)) throw LedgerActionBlockedException(kind);

    return _exclusive(() async {
      final LedgerSubmittedAction? pending;
      try {
        pending = await _store.blockingPolymarketBatch(walletId) ??
            await _store.blockingPolymarketOrder(walletId);
      } catch (error) {
        throw LedgerSubmissionUnknownException('pending-batch', error);
      }
      if (pending != null) {
        final LedgerSubmissionStage? stage;
        if (pending.orderId != null) {
          final result = await reconcileOrder(pending.id);
          stage = result == null ? null : (await _store.get(walletId, pending.id))?.stage;
        } else {
          stage = await reconcileBatch(pending.id);
        }
        // An accepted CLOB order is final, but a relayer batch that was only
        // accepted (or mined) can still fail: it stays unknown until the
        // relayer reports it confirmed or failed.
        if (stage == LedgerSubmissionStage.confirmed ||
            (pending.orderId != null &&
                stage == LedgerSubmissionStage.accepted) ||
            stage == LedgerSubmissionStage.rejected) {
          throw StateError('The previous transaction was '
              '${stage != LedgerSubmissionStage.rejected ? 'confirmed' : 'rejected'}. '
              'No new transaction was sent. Review again to continue.');
        }
        throw LedgerSubmissionUnknownException(pending.id,
            StateError('The previous transaction still needs confirmation.'));
      }
      await checkCapability?.call(intent.params['op'] == 'wrap'
          ? 'polymarket.deposit'
          : intent.params['op'] == 'redeem'
              ? 'polymarket.close'
              : intent.params['op'] == 'approveTrade'
                  ? 'polymarket.trade'
                  : 'polymarket.withdraw');
      String? recordId;
      var readyToSubmit = false;
      try {
        final hash = await _relayer.executeBatch(
          eoa: pairedAddress,
          signer: ExternalDepositWalletBatchSigner(_signer),
          wallet: wallet,
          calls: calls,
          deadline: _clock()
                  .add(const Duration(minutes: 10))
                  .millisecondsSinceEpoch ~/
              1000,
          beforeSubmit: (relayerNonce) async {
            // Runs before the record so a refusal leaves recordId null
            // and is rethrown as "nothing was sent".
            beforeSubmit?.call();
            final id = 'pm-batch-$relayerNonce';
            await _store.recordBeforeSubmit(LedgerSubmittedAction(
              id: id,
              walletId: walletId,
              kind: kind.name,
              paramsHash: intent.paramsHash,
              stage: LedgerSubmissionStage.submitting,
              submittedAtMs: _clock().millisecondsSinceEpoch,
              relayerNonce: relayerNonce,
            ));
            recordId = id;
            // The UI or wallet may have changed while persistence awaited.
            beforeSubmit?.call();
            readyToSubmit = true;
          },
          onSubmitted: (txId) async {
            final id = recordId;
            if (id != null) {
              await _store.updateStage(
                  walletId, id, LedgerSubmissionStage.submitting,
                  relayerTxId: txId);
            }
            try {
              await onRelayerSubmitted?.call(txId);
            } catch (_) {
              // The batch was accepted; a failed settlement write never
              // turns it into an error.
            }
          },
        );
        final id = recordId;
        if (id != null) {
          await _store.updateStage(
              walletId, id, LedgerSubmissionStage.confirmed);
        }
        return hash;
      } catch (error) {
        final id = recordId;
        if (id == null) rethrow; // nothing was sent
        if (!readyToSubmit) {
          await _store.updateStage(walletId, id, LedgerSubmissionStage.rejected, notAccepted: true);
          rethrow;
        }
        // Transport errors and their text cannot prove a signed batch failed.
        // Only reconciliation of the accepted transaction may clear uncertainty.
        await _store.updateStage(
            walletId, id, LedgerSubmissionStage.submittedUnknown);
        throw LedgerSubmissionUnknownException(id, error);
      }
    });
  }

  /// O8: cancellation uses CLOB credentials only and never prompts the
  /// Ledger. Session-level app auth applies (Phase 1 D-9).
  Future<void> cancelOrder(String orderId) async {
    await checkCapability?.call('polymarket.cancel');
    final credentials = await _loadCredentials();
    if (credentials == null) throw const LedgerPolymarketAuthException();
    await LedgerOperationScope.run(
        walletId,
        () => _clob.cancelOrder(
            credentials: credentials, polyAddress: _apiKeyBoundAddress!, orderId: orderId));
  }

  /// Reads the relayer state of an unknown batch. Never re-signs or
  /// resubmits.
  Future<LedgerSubmissionStage?> reconcileBatch(String recordId) async =>
      (await _reconcileBatchResult(recordId)).stage;

  /// Recovers the result of this exact reviewed batch without signing or
  /// resubmitting. A previous pending batch must never fund a new quote.
  /// The hash is returned only with a fresh confirmed relayer response; a
  /// cached confirmed stage alone is insufficient to recover the result.
  Future<({LedgerSubmissionStage? stage, String? hash, String? relayerTxId})>
      reconcileBatchResult(
    String recordId, {
    required LedgerActionIntent expectedIntent,
  }) =>
          _reconcileBatchResult(recordId, expectedIntent: expectedIntent);

  Future<({LedgerSubmissionStage? stage, String? hash, String? relayerTxId})>
      _reconcileBatchResult(
    String recordId, {
    LedgerActionIntent? expectedIntent,
  }) async {
    if (expectedIntent != null) {
      expectedIntent.verify();
      if (expectedIntent.walletId != walletId ||
          (expectedIntent.kind != LedgerActionKind.pmDepositWalletBatch &&
              expectedIntent.kind != LedgerActionKind.pmWithdrawal)) {
        throw const LedgerIntentMismatchException('batch reconciliation');
      }
    }
    final record = await _store.get(walletId, recordId);
    if (record != null &&
        expectedIntent != null &&
        (record.walletId != walletId ||
            record.kind != expectedIntent.kind.name ||
            record.paramsHash != expectedIntent.paramsHash)) {
      throw const LedgerIntentMismatchException('batch reconciliation');
    }
    if (record?.notAccepted == true) {
      await _store.updateStage(walletId, recordId, LedgerSubmissionStage.rejected, notAccepted: true);
      return (stage: LedgerSubmissionStage.rejected, hash: null, relayerTxId: record?.relayerTxId);
    }
    final txId = record?.relayerTxId;
    if (record == null || txId == null || txId.isEmpty) {
      return (stage: record?.stage, hash: null, relayerTxId: txId);
    }
    final state = await _relayer.transactionState(txId);
    if (state == null) {
      return (stage: record.stage, hash: null, relayerTxId: txId);
    }
    final s = state.state;
    final confirmed = const {'STATE_CONFIRMED', 'CONFIRMED', 'DONE'}.contains(s) &&
        RegExp(r'^0x[0-9a-fA-F]{64}$').hasMatch(state.hash ?? '');
    final failed = const {'STATE_FAILED', 'FAILED', 'STATE_INVALID', 'INVALID'}
        .contains(s);
    final next = confirmed
        ? LedgerSubmissionStage.confirmed
        : failed
            ? LedgerSubmissionStage.rejected
            : null;
    if (next == null) {
      return (stage: record.stage, hash: null, relayerTxId: txId);
    }
    await _store.updateStage(walletId, recordId, next);
    return (
      stage: next,
      hash: confirmed ? state.hash!.toLowerCase() : null,
      relayerTxId: txId,
    );
  }
}

/// The Exchange-domain Order hash the CLOB reports as `orderID`
/// (keccak(0x1901 ‖ exchangeDomainSeparator ‖ orderStructHash)), lowercase
/// 0x hex. For sigType 3 this is NOT the TypedDataSign digest the device
/// signs.
String exchangeOrderId(OrderStructV2 order, String verifyingContract) {
  final digest =
      orderV2TypedData(order: order, verifyingContract: verifyingContract)
          .digest;
  return '0x${digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
}
