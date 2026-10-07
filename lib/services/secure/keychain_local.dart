import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:kute/services/secure_storage.dart';

/// Keychain writes and deletes that never touch a synced iCloud Keychain
/// twin.
///
/// The flutter_secure_storage Darwin plugin deletes both the synced and the
/// non-synced variant of a key, and a write to a key whose only item is a
/// synced twin deletes that twin before adding the local item. On iOS these
/// calls go to `SecurityNativePlugin`, which scopes every query to
/// `kSecAttrSynchronizable: false`. Android has no synced variant (both
/// instances share one prefs file), so the plugin calls are already local.
class KeychainLocal {
  const KeychainLocal({
    this.storage = secureStorage,
    this.service = AppleOptions.defaultAccountName,
    this.platform,
  });

  static const channel = MethodChannel('com.kutewallet.app/security');

  final FlutterSecureStorage storage;
  final String service;
  final TargetPlatform? platform;

  bool get _native => (platform ?? defaultTargetPlatform) == TargetPlatform.iOS;

  Future<void> writeLocalOnly({
    required String key,
    required String value,
  }) async {
    if (!_native) return storage.write(key: key, value: value);
    await channel.invokeMethod<void>('writeLocalOnly', {
      'service': service,
      'account': key,
      'value': value,
    });
  }

  Future<void> deleteLocalOnly({required String key}) async {
    if (!_native) return storage.delete(key: key);
    await channel.invokeMethod<void>('deleteLocalOnly', {
      'service': service,
      'account': key,
    });
  }

  Future<void> deleteAllLocalOnly() async {
    if (!_native) return storage.deleteAll();
    await channel.invokeMethod<void>('deleteAllLocalOnly', {
      'service': service,
    });
  }
}
