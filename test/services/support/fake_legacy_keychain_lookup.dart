import 'package:kute/services/secure/legacy_keychain_rescue.dart';
import 'package:kute/services/secure/secret_error_class.dart';
import 'package:kute/services/secure/secret_store.dart';

import 'fake_secret_store.dart';

/// Items a 1.x build stored with `AfterFirstUnlock` instead of
/// `...ThisDeviceOnly`: the plugin-backed stores read them as absent.
const legacyAccessibility = FakeStoreOptions(accessibility: 'first_unlock');

/// [LegacyKeychainLookup] over a [FakeKeychain]: like `SecItemCopyMatching`
/// with no `kSecAttrAccessible`, it sees every item in the slot whatever
/// accessibility it was stored with. Read-only.
class FakeLegacyKeychainLookup implements LegacyKeychainLookup {
  FakeLegacyKeychainLookup(this.keychain);

  final FakeKeychain keychain;
  final reads = <String>[];

  /// When set, every read fails with it.
  Object? failure;

  @override
  Future<SecretRead> read(String account, {bool synchronizable = false}) async {
    reads.add(account);
    final failure = this.failure;
    if (failure != null) return SecretFailed(SecretErrorClass.unknown, failure);
    final value =
        synchronizable ? keychain.peekSynced(account) : keychain.peek(account);
    return value == null ? const SecretAbsent() : SecretPresent(value);
  }

  @override
  Future<List<String>> listAccounts(
      {required String prefix, bool synchronizable = false}) async {
    final failure = this.failure;
    if (failure != null) throw failure;
    final keys = synchronizable
        ? keychain.keys(options: FakeStoreOptions.synced)
        : keychain.keys();
    return keys.where((k) => k.startsWith(prefix)).toList()..sort();
  }
}
