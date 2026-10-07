import 'dart:async';

/// Hot signing and seed entry points a Ledger flow must never reach.
enum HotSigningAction {
  bip39MnemonicRead('bip39_mnemonic_read'),
  authMnemonicRead('auth_mnemonic_read'),
  hyperliquidHotCredentials('hyperliquid_hot_credentials'),
  polymarketHotCredentials('polymarket_hot_credentials'),
  sparkTransaction('spark_transaction'),
  onchainTransaction('onchain_transaction'),
  bdkSoftwareSign('bdk_software_sign'),

  /// The hot wallet identity signing a backend session challenge (a 401
  /// re-auth through `WalletIdentityService.buildAuthChallengeV2`).
  walletIdentitySign('wallet_identity_sign');

  const HotSigningAction(this.analyticsName);

  /// Value of the `action` property on `hot_signing_blocked`.
  final String analyticsName;
}

/// Thrown when a hot signing or seed entry point runs inside a Ledger
/// operation.
class HotSigningInLedgerScope implements Exception {
  const HotSigningInLedgerScope(this.action);

  final HotSigningAction action;

  @override
  String toString() =>
      'HotSigningInLedgerScope: ${action.analyticsName} inside a Ledger operation';
}

/// Marks the duration of a Ledger executor or funding flow so hot signing
/// entry points can refuse to run inside it. A guard, not a proof: code
/// that never calls [LedgerOperationScope.assertHotAllowed] is not covered.
class LedgerOperationScope {
  LedgerOperationScope._();

  static final Object _zoneKey = Object();

  /// Reports a blocked hot entry point, for example to emit
  /// `hot_signing_blocked`. Never receives ids or addresses.
  static void Function(HotSigningAction action)? onBlocked;

  /// Runs [body] as a Ledger operation for [walletId]. Everything [body]
  /// starts, including timers and microtasks, runs inside the scope. A
  /// nested scope for a different wallet is refused.
  static Future<T> run<T>(String walletId, Future<T> Function() body) {
    final current = currentWalletId;
    if (current != null && current != walletId) {
      return Future<T>.error(StateError(
          'A Ledger operation cannot start inside another wallet\'s operation'));
    }
    return runZoned(body, zoneValues: {_zoneKey: walletId});
  }

  /// The wallet id of the enclosing Ledger operation, or null outside one.
  static String? get currentWalletId => Zone.current[_zoneKey] as String?;

  static bool get isActive => currentWalletId != null;

  /// Called at the start of every hot signing or seed entry point. Throws
  /// [HotSigningInLedgerScope] inside a Ledger operation; does nothing
  /// outside one.
  static void assertHotAllowed(HotSigningAction action) {
    if (!isActive) return;
    try {
      onBlocked?.call(action);
    } catch (_) {}
    throw HotSigningInLedgerScope(action);
  }
}
