import 'package:kute/services/secure/secret_error_class.dart';

/// Result of a secure storage read. A failed read is never reported as an
/// absent item, so callers cannot mistake a Keychain or Keystore error for
/// missing data.
sealed class SecretRead {
  const SecretRead();
}

final class SecretPresent extends SecretRead {
  const SecretPresent(this.value);
  final String value;
}

final class SecretAbsent extends SecretRead {
  const SecretAbsent();
}

final class SecretFailed extends SecretRead {
  const SecretFailed(this.errorClass, this.raw, [this.stackTrace]);
  final SecretErrorClass errorClass;
  final Object raw;
  final StackTrace? stackTrace;
}

extension SecretReadValue on SecretRead {
  /// The stored value, or null when absent. A failed read rethrows its
  /// original error, matching a direct flutter_secure_storage read.
  String? valueOrThrow() => switch (this) {
        SecretPresent(:final value) => value,
        SecretAbsent() => null,
        SecretFailed(:final raw, :final stackTrace) =>
          Error.throwWithStackTrace(raw, stackTrace ?? StackTrace.current),
      };
}

/// Secure storage seam.
///
/// [write] and [delete] keep the flutter_secure_storage semantics, which on
/// iOS reach both the synced and the non-synced variant of a key. The
/// local-only operations never touch a synced iCloud Keychain twin and are
/// required for seed and PIN material.
abstract class SecretStore {
  Future<SecretRead> read({required String key});
  Future<void> write({required String key, required String value});
  Future<void> writeLocalOnly({required String key, required String value});
  Future<void> delete({required String key});
  Future<void> deleteLocalOnly({required String key});
  Future<void> deleteAllLocalOnly();
  Future<bool> containsKey({required String key});
}
