import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:kute/services/secure/keychain_local.dart';
import 'package:kute/services/secure/secret_error_class.dart';
import 'package:kute/services/secure/secret_store.dart';
import 'package:kute/services/secure_storage.dart';

/// [SecretStore] over a [FlutterSecureStorage] instance. Local-only
/// operations are available only when [localOnly] is set, which is the case
/// for the device-local store and never for the synced one.
class FlutterSecretStore implements SecretStore {
  const FlutterSecretStore(this.storage, {this.localOnly, this.platform});

  final FlutterSecureStorage storage;
  final KeychainLocal? localOnly;
  final TargetPlatform? platform;

  KeychainLocal get _local =>
      localOnly ??
      (throw UnsupportedError('This store has no local-only operations.'));

  @override
  Future<SecretRead> read({required String key}) async {
    try {
      final value = await storage.read(key: key);
      return value == null ? const SecretAbsent() : SecretPresent(value);
    } catch (error, stackTrace) {
      return SecretFailed(
        classifySecretError(error, platform: platform),
        error,
        stackTrace,
      );
    }
  }

  @override
  Future<void> write({required String key, required String value}) =>
      storage.write(key: key, value: value);

  @override
  Future<void> writeLocalOnly({required String key, required String value}) =>
      _local.writeLocalOnly(key: key, value: value);

  @override
  Future<void> delete({required String key}) => storage.delete(key: key);

  @override
  Future<void> deleteLocalOnly({required String key}) =>
      _local.deleteLocalOnly(key: key);

  @override
  Future<void> deleteAllLocalOnly() => _local.deleteAllLocalOnly();

  @override
  Future<bool> containsKey({required String key}) =>
      storage.containsKey(key: key);
}

/// Process-wide stores used by `AuthModel`, `PasskeyPrfService` and
/// `PasskeyService`.
abstract final class SecretStores {
  static const SecretStore _defaultLocal =
      FlutterSecretStore(secureStorage, localOnly: KeychainLocal());
  static const SecretStore _defaultSynced =
      FlutterSecretStore(syncedSecureStorage);

  static SecretStore _local = _defaultLocal;
  static SecretStore _synced = _defaultSynced;

  static SecretStore get local => _local;

  /// Read-only for seed material; see `syncedSecureStorage`.
  static SecretStore get synced => _synced;

  @visibleForTesting
  static void debugOverride({SecretStore? local, SecretStore? synced}) {
    if (local != null) _local = local;
    if (synced != null) _synced = synced;
  }

  @visibleForTesting
  static void debugReset() {
    _local = _defaultLocal;
    _synced = _defaultSynced;
  }
}
