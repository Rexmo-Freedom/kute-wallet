import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import 'package:kute/services/secure/flutter_secret_store.dart';
import 'package:kute/services/secure/secret_error_class.dart';
import 'package:kute/services/secure/secret_store.dart';
import 'package:kute/services/secure_storage.dart';

/// Cold-start state of secure storage relative to the Hive settings.
enum StorageBootState {
  /// No Hive wallets.
  fresh,

  /// Wallets and PIN material, no binding yet (first start after upgrade).
  preBinding,
  ok,

  /// The secure binding exists but Hive lost its copy.
  hiveRestoredOld,

  /// Hive and secure storage come from different installs. No wipe.
  bindingMismatch,

  /// Wallets exist but no PIN material. No keypad, no wipe.
  secretsMissing,

  /// A read failed. Retry screen, no PIN counting, no wipe.
  storageUnavailable,
}

/// Set by the splash for the rest of the process.
final storageBootStateProvider =
    StateProvider<StorageBootState?>((ref) => null);

class StorageBootResult {
  const StorageBootResult(this.state, {this.errorClass, this.failStarts = 0});

  final StorageBootState state;
  final SecretErrorClass? errorClass;

  /// Cold starts in a row that failed with a definitive error class.
  final int failStarts;

  static const int restoreAfterFailStarts = 3;

  bool get offerRestore =>
      state == StorageBootState.storageUnavailable &&
      failStarts >= restoreAfterFailStarts;
}

/// Classifies secure storage at cold start (D-21) without ever counting
/// PIN attempts or deleting anything.
///
/// Reads `kute.binding.v1`, `pin_hash` and `pin` sequentially from the
/// local store. The binding is a random 128-bit id kept both there and in
/// Hive (`settings.secure_binding_id`), so a Hive restored from another
/// install is detected before a wrong PIN could wipe this device.
class StorageBootstrap {
  StorageBootstrap({
    SecretStore? store,
    Future<Box> Function()? settingsBox,
    Random? random,
    bool? isCupertino,
    Future<bool?> Function()? isProtectedDataAvailable,
    Stream<bool>? Function()? protectedDataChanges,
    Duration protectedDataPoll = const Duration(seconds: 3),
  })  : _store = store ?? SecretStores.local,
        _settingsBox = settingsBox ?? (() => Hive.openBox('settings')),
        _random = random ?? Random.secure(),
        _isCupertino =
            isCupertino ?? defaultTargetPlatform == TargetPlatform.iOS,
        _isProtectedDataAvailable = isProtectedDataAvailable ??
            secureStorage.isCupertinoProtectedDataAvailable,
        _protectedDataChanges = protectedDataChanges ??
            (() => secureStorage.onCupertinoProtectedDataAvailabilityChanged),
        _protectedDataPoll = protectedDataPoll;

  final SecretStore _store;
  final Future<Box> Function() _settingsBox;
  final Random _random;
  final bool _isCupertino;
  final Future<bool?> Function() _isProtectedDataAvailable;
  final Stream<bool>? Function() _protectedDataChanges;
  final Duration _protectedDataPoll;

  static const String bindingKey = 'kute.binding.v1';
  static const String hiveBindingKey = 'secure_binding_id';
  static const String failStartsKey = 'storage_fail_starts';

  static bool _failureCountedThisProcess = false;

  @visibleForTesting
  static void debugResetProcess() => _failureCountedThisProcess = false;

  /// On iOS, waits while protected data is unavailable (a launch before the
  /// first unlock after reboot) and reads nothing meanwhile. Returns true
  /// when it waited.
  Future<bool> waitForProtectedData() async {
    if (!_isCupertino) return false;
    Future<bool> available() async {
      try {
        return await _isProtectedDataAvailable() != false;
      } catch (_) {
        return true;
      }
    }

    if (await available()) return false;
    final became = Completer<void>();
    final subscription = _protectedDataChanges()?.listen((value) {
      if (value && !became.isCompleted) became.complete();
    });
    try {
      while (!await available()) {
        await Future.any([became.future, Future.delayed(_protectedDataPoll)]);
      }
    } finally {
      await subscription?.cancel();
    }
    return true;
  }

  Future<StorageBootResult> classify({required bool hasWallets}) async {
    if (!hasWallets) return const StorageBootResult(StorageBootState.fresh);

    final binding = await _store.read(key: bindingKey);
    final pinHash = await _store.read(key: 'pin_hash');
    final legacyPin = await _store.read(key: 'pin');
    final box = await _settingsBox();

    final failures = [binding, pinHash, legacyPin].whereType<SecretFailed>();
    if (failures.isNotEmpty) {
      final definitive =
          failures.where((f) => f.errorClass.isDefinitive).firstOrNull;
      var failStarts = box.get(failStartsKey) as int? ?? 0;
      if (definitive != null && !_failureCountedThisProcess) {
        _failureCountedThisProcess = true;
        failStarts++;
        await box.put(failStartsKey, failStarts);
      }
      return StorageBootResult(
        StorageBootState.storageUnavailable,
        errorClass: (definitive ?? failures.first).errorClass,
        failStarts: failStarts,
      );
    }
    if (box.containsKey(failStartsKey)) await box.delete(failStartsKey);

    if (pinHash is SecretAbsent && legacyPin is SecretAbsent) {
      return const StorageBootResult(StorageBootState.secretsMissing);
    }

    final secureBinding = binding is SecretPresent ? binding.value : null;
    final hiveBinding = box.get(hiveBindingKey) as String?;
    if (secureBinding == null && hiveBinding == null) {
      try {
        await _writeBinding(box, _newBindingId());
      } catch (_) {
        // Retried on the next start; routing is unaffected.
      }
      return const StorageBootResult(StorageBootState.preBinding);
    }
    if (secureBinding != null && hiveBinding == null) {
      try {
        await box.put(hiveBindingKey, secureBinding);
      } catch (_) {}
      return const StorageBootResult(StorageBootState.hiveRestoredOld);
    }
    if (secureBinding == hiveBinding) {
      return const StorageBootResult(StorageBootState.ok);
    }
    return const StorageBootResult(StorageBootState.bindingMismatch);
  }

  /// Onboarding: a new PIN starts a new binding in both places.
  Future<void> writeNewBinding() async =>
      _writeBinding(await _settingsBox(), _newBindingId());

  Future<void> _writeBinding(Box box, String id) async {
    await _store.write(key: bindingKey, value: id);
    await box.put(hiveBindingKey, id);
  }

  String _newBindingId() => List.generate(
      16, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}
