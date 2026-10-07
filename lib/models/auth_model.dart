import 'package:kute/services/orchestra/standing_deposit_store.dart';
import 'package:kute/services/auth/pin_encryption.dart';
import 'package:kute/services/auth/pin_hash.dart';
import 'package:kute/services/onchain/native_bitcoin_primitives.dart';
import 'package:kute/services/orchestra/pending_receive_quote_cache.dart';
import 'package:kute/services/passkey_prf_service.dart';
import 'package:kute/services/passkey_service.dart';
import 'package:flutter/foundation.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';
import 'package:kute/services/secure/seed_access.dart';
import 'package:kute/services/secure/secret_store.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/services/hardware/ledger/ledger_operation_scope.dart';

export 'package:kute/services/secure/seed_access.dart';

/// Outcome of comparing a typed PIN with the stored PIN material. Only
/// [PinCheck.mismatch] may count toward the lockout.
enum PinCheck { match, mismatch, noPinMaterial, unavailable }

/// The old PIN given to [AuthModel.changePin] does not match.
class IncorrectPinException implements Exception {
  const IncorrectPinException();
  @override
  String toString() => 'IncorrectPinException';
}

/// [AuthModel.changePin] found [count] PIN-encrypted copies it cannot
/// re-encrypt, so it changed nothing.
class ChangePinBlocked implements Exception {
  const ChangePinBlocked(this.count);
  final int count;
  @override
  String toString() => 'ChangePinBlocked($count)';
}

/// AuthModel — secret-material storage layer.
///
/// Stored-seed wallets keep the on-disk copies they already have; nothing
/// here migrates or retires a copy:
///
///   * **V2 (plaintext, DEVICE-LOCAL)**: `v2:wallet:{walletId}.mnemonic` in
///     the local store. A beta build also mirrored some wallets to the
///     synced store (iCloud Keychain). That residue is still read when no
///     local copy exists, is never copied into local storage, and is never
///     deleted. The PIN is not an encryption key for V2; it is a UI gate
///     (salted hash compared via [pinMatches]).
///
///   * **V1 (legacy, PIN-encrypted, local-only)**: `mnemonic_{walletId}`, a
///     `PinEncryptionHelper` blob keyed by the user's PIN. New wallets no
///     longer get one; `changePin` re-encrypts the existing entries.
///
///   * **Root**: the pre-multi-wallet `mnemonic` key. A plaintext root is
///     copied to the wallet id on read and is never deleted.
///
/// [readMnemonic] tries V2 then falls back to V1 and the root. Seed and PIN
/// material is written and deleted with the store's local-only operations,
/// so a synced twin under the same key always survives.
class AuthModel {
  AuthModel({SecretStore? store, SecretStore? syncedStore})
      : _store = store ?? SecretStores.local,
        _syncedStore = syncedStore ?? SecretStores.synced;

  final SecretStore _store;
  final SecretStore _syncedStore;

  static const String _v2KeyPrefix = 'v2:wallet:';
  static String _v2MnemonicKey(String walletId) =>
      '$_v2KeyPrefix$walletId.mnemonic';

  Future<String?> _read(String key) async =>
      (await _store.read(key: key)).valueOrThrow();

  /// The raw PIN kept for biometric unlock of wallets that still need it.
  /// Only `BiometricPinPolicy` writes or removes it.
  Future<String?> getBiometricPin() async {
    return await _read('biometric_pin');
  }

  Future<void> deleteBiometricPin() async {
    await _store.deleteLocalOnly(key: 'biometric_pin');
  }

  Future<void> setPin(String pin) async {
    final hashedPin = PinHashHelper.hashPin(pin);
    await _store.write(key: 'pin_hash', value: hashedPin);
    await _store.deleteLocalOnly(key: 'pin');
  }

  Future<void> setPinAsync(String pin) async {
    final hashedPin = await PinHashHelper.hashPinAsync(pin);
    await _store.write(key: 'pin_hash', value: hashedPin);
    await _store.deleteLocalOnly(key: 'pin');
  }

  Future<bool> hasPinSet() async {
    final hashedPin = await _read('pin_hash');
    if (hashedPin != null) return true;

    final legacyPin = await _read('pin');
    return legacyPin != null;
  }

  Future<bool> pinMatches(String incomingPin) async {
    final hashedPin = await _read('pin_hash');
    if (hashedPin != null) {
      return PinHashHelper.verifyPin(incomingPin, hashedPin);
    }

    final legacyPin = await _read('pin');
    if (legacyPin != null && legacyPin == incomingPin) {
      await setPin(incomingPin);
      return true;
    }

    return false;
  }

  /// Same as [pinMatches] but runs the expensive PBKDF2 derivation on a
  /// background isolate (see [PinHashHelper.verifyPinAsync]). Use this on
  /// the unlock hot path so the UI thread isn't blocked while the user
  /// waits for the home screen.
  Future<bool> pinMatchesAsync(String incomingPin) async {
    final hashedPin = await _read('pin_hash');
    if (hashedPin != null) {
      return PinHashHelper.verifyPinAsync(incomingPin, hashedPin);
    }

    final legacyPin = await _read('pin');
    if (legacyPin != null && legacyPin == incomingPin) {
      await setPin(incomingPin);
      return true;
    }

    return false;
  }

  /// Compares [incomingPin] with the stored PIN material without throwing
  /// on a storage error. A legacy plaintext `pin` that matches is upgraded
  /// to `pin_hash`, as [pinMatches] does.
  Future<PinCheck> checkPin(String incomingPin) async {
    switch (await _store.read(key: 'pin_hash')) {
      case SecretFailed():
        return PinCheck.unavailable;
      case SecretPresent(:final value):
        return await PinHashHelper.verifyPinAsync(incomingPin, value)
            ? PinCheck.match
            : PinCheck.mismatch;
      case SecretAbsent():
        break;
    }
    switch (await _store.read(key: 'pin')) {
      case SecretFailed():
        return PinCheck.unavailable;
      case SecretAbsent():
        return PinCheck.noPinMaterial;
      case SecretPresent(:final value):
        if (value != incomingPin) return PinCheck.mismatch;
        await setPin(incomingPin);
        return PinCheck.match;
    }
  }

  static const String _pendingSuffix = '.next';

  Future<List<String>> _hiveWalletIds() async {
    final box = await Hive.openBox('settings');
    final rawWallets = box.get('wallets', defaultValue: []);
    return [
      if (rawWallets is List)
        for (final w in rawWallets)
          if (w is Map && w['id'] is String) w['id'] as String,
    ];
  }

  /// Every key that may hold a PIN-encrypted copy: `mnemonic_{id}` for each
  /// Hive wallet, plus the pre-multi-wallet root.
  Future<List<String>> _pinEncryptedKeyCandidates() async => [
        for (final id in await _hiveWalletIds()) 'mnemonic_$id',
        'mnemonic',
      ];

  static bool _isPlaintextRoot(String key, String value) =>
      key == 'mnemonic' && value.split(' ').length > 1;

  Future<String?> _decryptOrNull(String encrypted, String pin) async {
    try {
      return await PinEncryptionHelper.decryptDataAsync(encrypted, pin);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _presentValue(SecretStore store, String key) async =>
      switch (await store.read(key: key)) {
        SecretPresent(:final value) when value.isNotEmpty => value,
        _ => null,
      };

  /// Changes the PIN and re-encrypts every PIN-encrypted copy without a
  /// window in which a copy matches neither PIN:
  ///
  /// 1. The old PIN must match.
  /// 2. Each copy's plaintext comes from its V2 copy (local, then synced)
  ///    or from decrypting it with the old PIN. If any copy has neither,
  ///    [ChangePinBlocked] is thrown before anything is written.
  /// 3. Each copy is written under the new PIN to `{key}.next` and verified.
  /// 4. `pin_hash` is replaced.
  /// 5. `biometric_pin` is overwritten when [keepBiometricPin] returns true,
  ///    otherwise deleted.
  /// 6. Each `{key}` is replaced from `{key}.next`, verified, and the
  ///    `.next` item is deleted.
  ///
  /// A crash at any point is repaired by [recoverPendingPinChange] at the
  /// next unlock.
  Future<void> changePin(
    String oldPin,
    String newPin, {
    Future<bool> Function()? keepBiometricPin,
  }) async {
    if (await checkPin(oldPin) != PinCheck.match) {
      throw const IncorrectPinException();
    }

    final plaintexts = <String, String>{};
    var blocked = 0;
    for (final key in await _pinEncryptedKeyCandidates()) {
      final stored = await _store.read(key: key);
      if (stored is SecretAbsent) continue;
      if (stored is! SecretPresent) {
        blocked++;
        continue;
      }
      if (_isPlaintextRoot(key, stored.value)) continue;
      String? plain;
      if (key != 'mnemonic') {
        final walletKey = _v2MnemonicKey(key.substring('mnemonic_'.length));
        plain = await _presentValue(_store, walletKey) ??
            await _presentValue(_syncedStore, walletKey);
      }
      plain ??= await _decryptOrNull(stored.value, oldPin);
      if (plain == null) {
        blocked++;
      } else {
        plaintexts[key] = plain;
      }
    }
    if (blocked > 0) throw ChangePinBlocked(blocked);

    for (final entry in plaintexts.entries) {
      final pendingKey = '${entry.key}$_pendingSuffix';
      final encrypted =
          await PinEncryptionHelper.encryptDataAsync(entry.value, newPin);
      await _store.writeLocalOnly(key: pendingKey, value: encrypted);
      await _verifyEncrypted(pendingKey, newPin, entry.value);
    }

    await _store.write(
        key: 'pin_hash', value: await PinHashHelper.hashPinAsync(newPin));
    await _store.deleteLocalOnly(key: 'pin');

    if (await (keepBiometricPin?.call() ?? Future.value(true))) {
      await _store.writeLocalOnly(key: 'biometric_pin', value: newPin);
    } else {
      await _store.deleteLocalOnly(key: 'biometric_pin');
    }

    for (final entry in plaintexts.entries) {
      final pendingKey = '${entry.key}$_pendingSuffix';
      final pending = (await _store.read(key: pendingKey)).valueOrThrow();
      if (pending == null) throw StateError('Missing $pendingKey');
      await _store.writeLocalOnly(key: entry.key, value: pending);
      await _verifyEncrypted(entry.key, newPin, entry.value);
      await _store.deleteLocalOnly(key: pendingKey);
    }
  }

  Future<void> _verifyEncrypted(String key, String pin, String expected) async {
    final stored = (await _store.read(key: key)).valueOrThrow();
    if (stored == null || await _decryptOrNull(stored, pin) != expected) {
      throw StateError('Verification failed for $key');
    }
  }

  /// Finishes or discards a PIN change that did not complete. Runs only
  /// when some `{key}.next` item exists and [pin] matches `pin_hash`:
  /// - a `.next` that decrypts with [pin] replaces `{key}` unless `{key}`
  ///   already holds the same plaintext, then it is deleted;
  /// - a `.next` that does not decrypt with [pin] is deleted only when
  ///   `{key}` decrypts with [pin].
  /// Anything that decrypts with neither is left in place.
  Future<void> recoverPendingPinChange(String pin) async {
    final pending = <String, String>{};
    for (final key in await _pinEncryptedKeyCandidates()) {
      final value = await _presentValue(_store, '$key$_pendingSuffix');
      if (value != null) pending[key] = value;
    }
    if (pending.isEmpty) return;
    if (await checkPin(pin) != PinCheck.match) return;

    for (final entry in pending.entries) {
      final pendingKey = '${entry.key}$_pendingSuffix';
      final current = await _store.read(key: entry.key);
      if (current is SecretFailed) continue;
      final currentPlain = current is SecretPresent
          ? await _decryptOrNull(current.value, pin)
          : null;
      final pendingPlain = await _decryptOrNull(entry.value, pin);
      if (pendingPlain == null) {
        if (currentPlain != null) {
          await _store.deleteLocalOnly(key: pendingKey);
        }
        continue;
      }
      if (currentPlain != pendingPlain) {
        await _store.writeLocalOnly(key: entry.key, value: entry.value);
        await _verifyEncrypted(entry.key, pin, pendingPlain);
      }
      await _store.deleteLocalOnly(key: pendingKey);
    }
  }

  Future<int> getFailedAttempts() async {
    final val = await _read('failed_pin_attempts');
    return val != null ? (int.tryParse(val) ?? 0) : 0;
  }

  Future<void> setFailedAttempts(int count) async {
    await _store.write(key: 'failed_pin_attempts', value: count.toString());
  }

  Future<DateTime?> getLockoutUntil() async {
    final val = await _read('lockout_until');
    if (val == null) return null;
    return DateTime.tryParse(val);
  }

  Future<void> setLockoutUntil(DateTime time) async {
    await _store.write(key: 'lockout_until', value: time.toIso8601String());
  }

  Future<void> resetFailedAttempts() async {
    await _store.delete(key: 'failed_pin_attempts');
    await _store.delete(key: 'lockout_until');
  }

  static int getLockoutDuration(int failedAttempts) {
    switch (failedAttempts) {
      case 3:
        return 30;
      case 4:
        return 60;
      case 5:
        return 300;
      default:
        if (failedAttempts >= 6) return -1; // Wipe
        return 0;
    }
  }

  /// Stores a new wallet's seed as its V2 copy only. The 12 words are the
  /// user's backup and never leave the device: cross-device recovery is by
  /// re-entering the phrase or through the passkey, never by syncing the
  /// seed to iCloud or Google.
  Future<void> setMnemonic(String walletId, String mnemonic) =>
      setMnemonicV2(walletId, mnemonic);

  /// V2 write — plaintext mnemonic, DEVICE-LOCAL ONLY, through a local-only
  /// write so a synced twin under the same key is never purged. New wallet
  /// secrets are never pushed to synced (iCloud / Google) storage.
  Future<void> setMnemonicV2(String walletId, String mnemonic) async {
    if (!await validateMnemonic(mnemonic)) {
      throw Exception('Invalid mnemonic');
    }
    await _store.writeLocalOnly(key: _v2MnemonicKey(walletId), value: mnemonic);
  }

  /// V2 read — plaintext mnemonic. Tries device-local first, then the
  /// legacy synced (iCloud) store written by a beta build, so existing
  /// users keep access. A synced hit is returned as is: it is never copied
  /// into local storage and never deleted. Returns null when neither path
  /// has the entry (caller falls through to V1).
  Future<String?> getMnemonicV2(String walletId) async {
    LedgerOperationScope.assertHotAllowed(HotSigningAction.authMnemonicRead);
    final key = _v2MnemonicKey(walletId);
    final local = await _read(key);
    if (local != null && local.isNotEmpty) return local;
    final synced = (await _syncedStore.read(key: key)).valueOrThrow();
    if (synced != null && synced.isNotEmpty) return synced;
    return null;
  }

  /// Delay between read attempts after a storage failure.
  @visibleForTesting
  static Duration readRetryDelay = const Duration(milliseconds: 500);

  static const int _readAttempts = 3;

  /// Reads a stored wallet's seed. Passkey wallets never persist one; they
  /// go through `resolveBip39MnemonicFor`.
  ///
  /// 1. [SeedAccess.automatic] while the session is not unlocked returns
  ///    [SeedLocked] without touching storage.
  /// 2. V2 local, then V2 synced (never copied locally).
  /// 3. V1 `mnemonic_{id}`, decrypted with the typed PIN or a kept
  ///    `biometric_pin` that verifies against `pin_hash`; without either it
  ///    is [SeedLocked]. A legacy-format copy is never rewritten.
  /// 4. Root `mnemonic`: a plaintext root is copied to this wallet id and
  ///    kept; an encrypted root decrypts like V1.
  ///
  /// A failed storage read retries the sequence up to 3 times, then
  /// returns [SeedUnavailableReason.storage]. A missing copy is not retried.
  Future<SeedRead> readMnemonic(
    String walletId, {
    required SeedAccess access,
    SeedSession session = SeedSession.locked,
  }) async {
    LedgerOperationScope.assertHotAllowed(HotSigningAction.authMnemonicRead);
    if (access == SeedAccess.automatic && !session.unlocked) {
      return const SeedLocked();
    }
    for (var attempt = 1;; attempt++) {
      final result = await _readMnemonicOnce(walletId, session);
      if (result != null) return result;
      if (attempt >= _readAttempts) {
        return const SeedUnavailable(SeedUnavailableReason.storage);
      }
      await Future<void>.delayed(readRetryDelay);
    }
  }

  /// [readMnemonic] as a nullable value.
  Future<String?> getMnemonic(
    String walletId, {
    required SeedAccess access,
    SeedSession session = SeedSession.locked,
  }) async =>
      switch (await readMnemonic(walletId, access: access, session: session)) {
        SeedOk(:final value) => value,
        _ => null,
      };

  /// [readMnemonic] that throws [SeedLockedException] or
  /// [SeedUnavailableException] instead of returning them.
  Future<String> requireMnemonic(
    String walletId, {
    SeedAccess access = SeedAccess.automatic,
    required SeedSession session,
  }) async =>
      switch (await readMnemonic(walletId, access: access, session: session)) {
        SeedOk(:final value) => value,
        SeedLocked() => throw const SeedLockedException(),
        SeedUnavailable(:final reason) =>
          throw SeedUnavailableException(reason),
      };

  /// One pass over the copies. Null means a read failed before any copy
  /// resolved, so the caller retries.
  Future<SeedRead?> _readMnemonicOnce(
      String walletId, SeedSession session) async {
    var failed = false;
    final v2Key = _v2MnemonicKey(walletId);
    for (final (store, source) in [
      (_store, SeedSource.v2Local),
      (_syncedStore, SeedSource.v2Synced),
    ]) {
      switch (await store.read(key: v2Key)) {
        case SecretPresent(:final value) when value.isNotEmpty:
          return SeedOk(value, source);
        case SecretFailed():
          failed = true;
        case _:
          break;
      }
    }

    switch (await _store.read(key: 'mnemonic_$walletId')) {
      case SecretFailed():
        return null;
      case SecretPresent(:final value):
        return _decryptWithPinSource(value, session, SeedSource.v1,
            retryable: failed);
      case SecretAbsent():
        break;
    }

    switch (await _store.read(key: 'mnemonic')) {
      case SecretFailed():
        return null;
      case SecretPresent(:final value) when _isPlaintextRoot('mnemonic', value):
        if (!failed) {
          await _promoteRootMnemonic(
              walletId, value, await _v1PinSource(session));
        }
        return SeedOk(value, SeedSource.root);
      case SecretPresent(:final value):
        return _decryptWithPinSource(value, session, SeedSource.root,
            retryable: failed);
      case SecretAbsent():
        return failed
            ? null
            : const SeedUnavailable(SeedUnavailableReason.absent);
    }
  }

  Future<SeedRead?> _decryptWithPinSource(
    String encrypted,
    SeedSession session,
    SeedSource source, {
    required bool retryable,
  }) async {
    final pin = await _v1PinSource(session);
    final plain = pin == null ? null : await _decryptOrNull(encrypted, pin);
    if (plain != null) return SeedOk(plain, source);
    if (retryable) return null;
    return pin == null
        ? const SeedLocked()
        : const SeedUnavailable(SeedUnavailableReason.unreadable);
  }

  /// The PIN that decrypts PIN-encrypted copies: the typed PIN, else a kept
  /// `biometric_pin` that still verifies against the stored PIN material.
  Future<String?> _v1PinSource(SeedSession session) async {
    final typed = session.typedPin;
    if (typed != null && typed.isNotEmpty) return typed;
    final stored = await _presentValue(_store, 'biometric_pin');
    if (stored == null) return null;
    return await _verifiesWithoutWriting(stored) ? stored : null;
  }

  /// Like [checkPin] but never upgrades a legacy plaintext `pin`.
  Future<bool> _verifiesWithoutWriting(String pin) async {
    switch (await _store.read(key: 'pin_hash')) {
      case SecretPresent(:final value):
        return PinHashHelper.verifyPinAsync(pin, value);
      case SecretFailed():
        return false;
      case SecretAbsent():
        return await _presentValue(_store, 'pin') == pin;
    }
  }

  /// Copies a plaintext root seed to [walletId]: the V2 copy, and a V1 copy
  /// only when a PIN source exists. The root itself is never deleted.
  Future<void> _promoteRootMnemonic(
      String walletId, String mnemonic, String? pin) async {
    try {
      if (!await validateMnemonic(mnemonic)) return;
      if (pin != null) {
        await _store.writeLocalOnly(
          key: 'mnemonic_$walletId',
          value: await PinEncryptionHelper.encryptDataAsync(mnemonic, pin),
        );
      }
      await setMnemonicV2(walletId, mnemonic);
    } catch (_) {
      // The root still serves this read; the copy is retried next time.
    }
  }

  Future<bool> validateMnemonic(String mnemonicString) async {
    try {
      return await NativeBitcoinPrimitives.instance
          .validateMnemonic(mnemonicString);
    } catch (e) {
      return false;
    }
  }

  Future<String> generateMnemonic() =>
      NativeBitcoinPrimitives.instance.generateMnemonic();

  Future<void> setExtendedPublicKey(String walletId, String xpub) async {
    if (xpub.isEmpty) throw Exception("Invalid key");
    await _store.write(key: 'xpub_$walletId', value: xpub);
  }

  Future<String?> getExtendedPublicKey(String walletId) async {
    return await _read('xpub_$walletId');
  }

  Future<void> setExternalAddress(String walletId, String address) async {
    if (address.isEmpty) throw Exception("Invalid address");
    await _store.write(key: 'external_address_$walletId', value: address);
  }

  Future<String?> getExternalAddress(String walletId) async {
    return await _read('external_address_$walletId');
  }

  /// Deletes this wallet's device-local copies only. A synced twin of any
  /// of these keys is left in place.
  Future<void> deleteWalletMnemonic(String walletId) async {
    await _store.deleteLocalOnly(key: 'mnemonic_$walletId');
    await _store.deleteLocalOnly(key: _v2MnemonicKey(walletId));
    await _store.deleteLocalOnly(key: 'xpub_$walletId');
    await _store.deleteLocalOnly(key: 'external_address_$walletId');
  }

  /// Wipes this device: in-memory passkey seeds, every device-local secure
  /// storage item and the app's Hive boxes. Synced iCloud Keychain items
  /// are never deleted.
  Future<void> deleteAuthentication() async {
    PasskeyPrfService.clearMemory();
    PasskeyService.clearSession();
    // A native storage write may already be running when an OS ceremony is
    // cancelled. Let only those writes settle before deleting local secrets.
    await Future.wait([
      PendingReceiveQuoteCache.clear(),
      StandingDepositStore.clear(),
      PasskeyPrfService.drainPendingWrites(),
      PasskeyService.drainPendingWrites(),
    ]);
    await _store.deleteAllLocalOnly();

    await Hive.deleteBoxFromDisk('bitcoin');
    await Hive.deleteBoxFromDisk('affiliateCode');
    await Hive.deleteBoxFromDisk('breez_prefs');
    await Hive.deleteBoxFromDisk('settings');
    await Hive.deleteBoxFromDisk('bitcoinTransactions');
    await Hive.deleteBoxFromDisk('addresses');
    await Hive.deleteBoxFromDisk('provider_event_outbox_v1');
    await Hive.deleteBoxFromDisk('hyperliquid_revenue_orders_v1');
  }
}
