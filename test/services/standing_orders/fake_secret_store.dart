// An in-memory secret store for the standing order tests.

import 'package:kute/services/secure/secret_store.dart';

class FakeSecretStore implements SecretStore {
  final Map<String, String> values = {};
  int writes = 0;
  int deletes = 0;

  @override
  Future<bool> containsKey({required String key}) async =>
      values.containsKey(key);

  @override
  Future<void> delete({required String key}) async {
    deletes++;
    values.remove(key);
  }

  @override
  Future<void> deleteAllLocalOnly() async => values.clear();

  @override
  Future<void> deleteLocalOnly({required String key}) => delete(key: key);

  @override
  Future<SecretRead> read({required String key}) async {
    final v = values[key];
    return v == null ? const SecretAbsent() : SecretPresent(v);
  }

  @override
  Future<void> write({required String key, required String value}) async {
    writes++;
    values[key] = value;
  }

  @override
  Future<void> writeLocalOnly({required String key, required String value}) =>
      write(key: key, value: value);
}
