import 'package:kute/services/secure/secret_store.dart';

/// Wraps a [SecretStore] and appends `'$name:$key'` to [log] for every read,
/// so tests can assert which keys were read and in which order.
class RecordingSecretStore implements SecretStore {
  RecordingSecretStore(this.inner, {required this.name, required this.log});

  final SecretStore inner;
  final String name;
  final List<String> log;

  @override
  Future<SecretRead> read({required String key}) {
    log.add('$name:$key');
    return inner.read(key: key);
  }

  @override
  Future<void> write({required String key, required String value}) =>
      inner.write(key: key, value: value);

  @override
  Future<void> writeLocalOnly({required String key, required String value}) =>
      inner.writeLocalOnly(key: key, value: value);

  @override
  Future<void> delete({required String key}) => inner.delete(key: key);

  @override
  Future<void> deleteLocalOnly({required String key}) =>
      inner.deleteLocalOnly(key: key);

  @override
  Future<void> deleteAllLocalOnly() => inner.deleteAllLocalOnly();

  @override
  Future<bool> containsKey({required String key}) =>
      inner.containsKey(key: key);
}
