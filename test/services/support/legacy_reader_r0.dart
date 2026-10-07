// Frozen copy of AuthModel's seed readers and the biometric unlock read at
// commit 8a422018, before Phase 1a. Downgrade tests run it against storage
// written by 1a to prove the previous build still reads it. Only the storage
// access is adapted to SecretStore; never update the logic.

import 'package:kute/services/auth/pin_encryption.dart';
import 'package:kute/services/secure/secret_store.dart';

class LegacyReaderR0 {
  LegacyReaderR0({
    required SecretStore storage,
    required SecretStore synced,
    required Future<bool> Function(String mnemonic) validateMnemonic,
    this.retryDelay = const Duration(milliseconds: 500),
  })  : _storage = storage,
        _synced = synced,
        _validateMnemonic = validateMnemonic;

  final SecretStore _storage;
  final SecretStore _synced;
  final Future<bool> Function(String mnemonic) _validateMnemonic;
  final Duration retryDelay;

  static String _v2MnemonicKey(String walletId) =>
      'v2:wallet:$walletId.mnemonic';

  Future<String?> _read(String key) async =>
      (await _storage.read(key: key)).valueOrThrow();

  Future<void> setMnemonic(String walletId, String mnemonic, String pin) async {
    if (!await _validateMnemonic(mnemonic)) {
      throw Exception('Invalid mnemonic');
    }
    final encryptedMnemonic =
        await PinEncryptionHelper.encryptDataAsync(mnemonic, pin);
    await _storage.write(key: 'mnemonic_$walletId', value: encryptedMnemonic);
    await setMnemonicV2(walletId, mnemonic);
  }

  Future<void> setMnemonicV2(String walletId, String mnemonic) async {
    if (!await _validateMnemonic(mnemonic)) {
      throw Exception('Invalid mnemonic');
    }
    await _storage.write(key: _v2MnemonicKey(walletId), value: mnemonic);
  }

  Future<String?> getMnemonicV2(String walletId) async {
    final key = _v2MnemonicKey(walletId);
    final local = await _read(key);
    if (local != null && local.isNotEmpty) return local;
    final synced = (await _synced.read(key: key)).valueOrThrow();
    if (synced != null && synced.isNotEmpty) {
      await _storage.write(key: key, value: synced);
      return synced;
    }
    return null;
  }

  Future<String?> getMnemonic(String walletId, String pin) async {
    final v2 = await getMnemonicV2(walletId);
    if (v2 != null) return v2;
    return await getMnemonicWithRetry(walletId, pin);
  }

  Future<String?> getMnemonicWithRetry(String walletId, String pin) async {
    final key = 'mnemonic_$walletId';

    for (int i = 0; i < 3; i++) {
      String? encryptedData = await _read(key);

      if (encryptedData == null) {
        encryptedData = await _read('mnemonic');
        if (encryptedData != null && encryptedData.split(' ').length > 1) {
          await setMnemonic(walletId, encryptedData, pin);
          return encryptedData;
        }
      }

      if (encryptedData != null) {
        try {
          final mnemonic =
              await PinEncryptionHelper.decryptDataAsync(encryptedData, pin);

          if (PinEncryptionHelper.isLegacyFormat(encryptedData)) {
            final v2Encrypted =
                await PinEncryptionHelper.encryptDataAsync(mnemonic, pin);
            await _storage.write(key: key, value: v2Encrypted);
          }

          return mnemonic;
        } catch (_) {}
      }
      await Future.delayed(retryDelay);
    }
    return null;
  }

  /// `open_pin._checkBiometrics` read `biometric_pin` after the OS prompt.
  /// Null sent the user to the keypad (`stored_pin_null`); a value became
  /// the session PIN.
  Future<String?> biometricUnlockPin() => _read('biometric_pin');
}
