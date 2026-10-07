import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/secure_storage.dart';

void main() {
  test('iOS local store keeps the keychain attributes existing items use', () {
    expect(secureStorage.iOptions.toMap(), {
      'accountName': 'flutter_secure_storage_service',
      'accessibility': 'first_unlock_this_device',
      'synchronizable': 'false',
      'useSecureEnclave': 'false',
    });
  });

  test('iOS synced store keeps the keychain attributes existing items use', () {
    expect(syncedSecureStorage.iOptions.toMap(), {
      'accountName': 'flutter_secure_storage_service',
      'accessibility': 'first_unlock',
      'synchronizable': 'true',
      'useSecureEnclave': 'false',
    });
  });

  test('both Android stores send identical fail-closed options', () {
    const golden = {
      'encryptedSharedPreferences': 'true',
      'resetOnError': 'false',
      'migrateOnAlgorithmChange': 'true',
      'migrateWithBackup': 'false',
      'enforceBiometrics': 'false',
      'keyCipherAlgorithm': 'RSA_ECB_OAEPwithSHA_256andMGF1Padding', // gitleaks:allow (cipher name)
      'storageCipherAlgorithm': 'AES_GCM_NoPadding',
      'biometricType': 'biometricOrDeviceCredential',
      'sharedPreferencesName': '',
      'preferencesKeyPrefix': '',
      'storageNamespace': '',
      'biometricPromptTitle': 'Authenticate to access',
      'biometricPromptSubtitle': 'Use biometrics or device credentials',
      'biometricPromptNegativeButton': 'Cancel',
    };
    expect(secureStorage.aOptions.toMap(), golden);
    expect(syncedSecureStorage.aOptions.toMap(), golden);
  });
}
