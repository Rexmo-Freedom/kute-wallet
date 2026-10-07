import 'package:flutter/foundation.dart';
import 'package:kute/services/secure/secret_error_class.dart';
import 'package:kute/services/secure/secret_store.dart';

enum FakePlatform { darwin, android }

/// Options a fake store was opened with. On Darwin [service] is the Keychain
/// service; on Android it is the storage namespace.
class FakeStoreOptions {
  const FakeStoreOptions({
    this.service = 'flutter_secure_storage_service',
    this.synchronizable = false,
    this.accessibility = 'first_unlock_this_device',
    this.secureEnclave = false,
    this.resetOnError = false,
  });

  final String service;
  final bool synchronizable;
  final String accessibility;
  final bool secureEnclave;
  final bool resetOnError;

  static const local = FakeStoreOptions();
  static const synced =
      FakeStoreOptions(synchronizable: true, accessibility: 'first_unlock');
}

/// Thrown by every call once the injected crash point is reached, until
/// [FakeKeychain.restart].
class FakeCrash implements Exception {
  const FakeCrash();
  @override
  String toString() => 'FakeCrash';
}

@immutable
class FakeMutation {
  const FakeMutation(this.store, this.op, this.key);
  final String store;
  final String op;
  final String key;

  @override
  bool operator ==(Object other) =>
      other is FakeMutation &&
      other.store == store &&
      other.op == op &&
      other.key == key;

  @override
  int get hashCode => Object.hash(store, op, key);

  @override
  String toString() => '$store.$op($key)';
}

typedef _Slot = ({String service, String key, bool synced});

class _Item {
  const _Item(this.value, this.accessibility, this.secureEnclave);
  final String value;
  final String accessibility;
  final bool secureEnclave;
}

/// In-memory model of the platform secure storage behind every
/// [FakeSecretStore] it opens.
///
/// Darwin behaviour modelled from flutter_secure_storage_darwin 0.3.2:
/// - reads match service, key, synchronizable, accessibility and the enclave
///   flag exactly;
/// - `delete` removes the synced and the non-synced variant;
/// - `write` to a key whose only matching item is a synced twin (or an item
///   with other attributes) deletes both variants before adding;
/// - local-only operations touch only the non-synced variant.
///
/// Android keeps one item per namespace and key; synchronizable is ignored.
class FakeKeychain {
  FakeKeychain({this.platform = FakePlatform.darwin});

  final FakePlatform platform;
  final Map<_Slot, _Item> _items = {};
  final List<FakeMutation> mutations = [];
  final Map<(String, String?), Object> _readErrors = {};
  final Map<(String, String?), Object> _writeErrors = {};
  final Map<(String, String?), Object> _deleteErrors = {};
  final Map<String, String?> _enclaveReads = {};
  int? _crashAfter;
  int _mutationCount = 0;
  bool _frozen = false;

  late final FakeSecretStore local = store('local', FakeStoreOptions.local);
  late final FakeSecretStore synced = store('synced', FakeStoreOptions.synced);

  bool get crashed => _frozen;

  TargetPlatform get _targetPlatform => platform == FakePlatform.darwin
      ? TargetPlatform.iOS
      : TargetPlatform.android;

  FakeSecretStore store(
    String name, [
    FakeStoreOptions options = FakeStoreOptions.local,
  ]) =>
      FakeSecretStore._(this, name, options);

  _Slot _slot(FakeStoreOptions options, String key) => (
        service: options.service,
        key: key,
        synced: platform == FakePlatform.darwin && options.synchronizable,
      );

  /// Places an item directly, bypassing mutation counting and errors.
  void seed(
    String key,
    String value, {
    FakeStoreOptions options = FakeStoreOptions.local,
  }) {
    _items[_slot(options, key)] =
        _Item(value, options.accessibility, options.secureEnclave);
  }

  void seedSynced(String key, String value) =>
      seed(key, value, options: FakeStoreOptions.synced);

  /// The raw stored value for the slot, ignoring attribute matching.
  String? peek(String key,
          {FakeStoreOptions options = FakeStoreOptions.local}) =>
      _items[_slot(options, key)]?.value;

  String? peekSynced(String key) => peek(key, options: FakeStoreOptions.synced);

  /// Every key stored for [options]' slot family.
  Set<String> keys({FakeStoreOptions options = FakeStoreOptions.local}) {
    final synced = platform == FakePlatform.darwin && options.synchronizable;
    return {
      for (final slot in _items.keys)
        if (slot.service == options.service && slot.synced == synced) slot.key,
    };
  }

  void failRead(String store, Object error, {String? key}) =>
      _readErrors[(store, key)] = error;

  void failWrite(String store, Object error, {String? key}) =>
      _writeErrors[(store, key)] = error;

  void failDelete(String store, Object error, {String? key}) =>
      _deleteErrors[(store, key)] = error;

  void clearFailures() {
    _readErrors.clear();
    _writeErrors.clear();
    _deleteErrors.clear();
  }

  /// Secure Enclave reads of [key] succeed with [value] (null or garbage)
  /// regardless of what is stored.
  void enclaveReadReturns(String key, String? value) =>
      _enclaveReads[key] = value;

  /// The first [count] mutating calls succeed; the next one throws
  /// [FakeCrash] without applying and every later call throws too.
  void crashAfter(int count) {
    _crashAfter = count;
    _mutationCount = 0;
  }

  /// A new process: clears the crash point and unfreezes. Stored items stay.
  void restart() {
    _crashAfter = null;
    _mutationCount = 0;
    _frozen = false;
  }

  void _guard() {
    if (_frozen) throw const FakeCrash();
  }

  Object? _errorFor(
          Map<(String, String?), Object> errors, String store, String key) =>
      errors[(store, key)] ?? errors[(store, null)];

  void _removeBothVariants(String service, String key) {
    _items.remove((service: service, key: key, synced: true));
    _items.remove((service: service, key: key, synced: false));
  }

  Future<void> _mutate(
    String store,
    String op,
    String key,
    Map<(String, String?), Object> errors,
    void Function() apply,
  ) async {
    _guard();
    final error = _errorFor(errors, store, key);
    if (error != null) throw error;
    final crashAt = _crashAfter;
    if (crashAt != null && _mutationCount >= crashAt) {
      _frozen = true;
      throw const FakeCrash();
    }
    apply();
    _mutationCount++;
    mutations.add(FakeMutation(store, op, key));
  }
}

class FakeSecretStore implements SecretStore {
  FakeSecretStore._(this.keychain, this.name, this.options);

  final FakeKeychain keychain;
  final String name;
  final FakeStoreOptions options;

  bool get _darwin => keychain.platform == FakePlatform.darwin;

  void _requireLocal() {
    if (_darwin && options.synchronizable) {
      throw UnsupportedError('This store has no local-only operations.');
    }
  }

  @override
  Future<SecretRead> read({required String key}) async {
    keychain._guard();
    final error = keychain._errorFor(keychain._readErrors, name, key);
    if (error != null) {
      if (!_darwin && options.resetOnError) {
        keychain._items
            .removeWhere((slot, _) => slot.service == options.service);
        return const SecretAbsent();
      }
      return SecretFailed(
        classifySecretError(error, platform: keychain._targetPlatform),
        error,
      );
    }
    if (options.secureEnclave && keychain._enclaveReads.containsKey(key)) {
      final value = keychain._enclaveReads[key];
      return value == null ? const SecretAbsent() : SecretPresent(value);
    }
    final item = keychain._items[keychain._slot(options, key)];
    if (item == null) return const SecretAbsent();
    if (_darwin &&
        (item.accessibility != options.accessibility ||
            item.secureEnclave != options.secureEnclave)) {
      return const SecretAbsent();
    }
    return SecretPresent(item.value);
  }

  @override
  Future<void> write({required String key, required String value}) =>
      keychain._mutate(name, 'write', key, keychain._writeErrors, () {
        final slot = keychain._slot(options, key);
        if (_darwin && !options.secureEnclave) {
          final anyVariant = keychain._items.containsKey(
                  (service: options.service, key: key, synced: true)) ||
              keychain._items.containsKey(
                  (service: options.service, key: key, synced: false));
          final current = keychain._items[slot];
          final updatable = current != null &&
              current.accessibility == options.accessibility &&
              !current.secureEnclave;
          if (anyVariant && !updatable) {
            keychain._removeBothVariants(options.service, key);
          }
        }
        keychain._items[slot] =
            _Item(value, options.accessibility, options.secureEnclave);
      });

  @override
  Future<void> writeLocalOnly({required String key, required String value}) {
    _requireLocal();
    return keychain._mutate(name, 'writeLocalOnly', key, keychain._writeErrors,
        () {
      keychain._items[keychain._slot(options, key)] =
          _Item(value, options.accessibility, false);
    });
  }

  @override
  Future<void> delete({required String key}) =>
      keychain._mutate(name, 'delete', key, keychain._deleteErrors, () {
        if (_darwin) {
          keychain._removeBothVariants(options.service, key);
        } else {
          keychain._items.remove(keychain._slot(options, key));
        }
      });

  @override
  Future<void> deleteLocalOnly({required String key}) {
    _requireLocal();
    return keychain
        ._mutate(name, 'deleteLocalOnly', key, keychain._deleteErrors, () {
      keychain._items.remove(keychain._slot(options, key));
    });
  }

  @override
  Future<void> deleteAllLocalOnly() {
    _requireLocal();
    return keychain
        ._mutate(name, 'deleteAllLocalOnly', '*', keychain._deleteErrors, () {
      keychain._items.removeWhere(
          (slot, _) => slot.service == options.service && !slot.synced);
    });
  }

  @override
  Future<bool> containsKey({required String key}) async {
    keychain._guard();
    if (_darwin) {
      return keychain._items.containsKey(
              (service: options.service, key: key, synced: true)) ||
          keychain._items
              .containsKey((service: options.service, key: key, synced: false));
    }
    return keychain._items.containsKey(keychain._slot(options, key));
  }
}
