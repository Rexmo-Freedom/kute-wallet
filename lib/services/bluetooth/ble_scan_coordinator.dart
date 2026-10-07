import 'package:universal_ble/universal_ble.dart';

/// A scan lease belongs to one discovery flow, even if an old screen disposes
/// after a different flow has already started scanning.
class BleScanLease {
  final BleScanCoordinator _coordinator;
  BleScanLease._(this._coordinator);

  bool get isCurrent => identical(_coordinator._owner, this);
}

/// Serializes access to the single platform BLE scanner. Device connections and
/// characteristic subscriptions remain owned by their Ledger/Jade services.
class BleScanCoordinator {
  static final instance = BleScanCoordinator();
  final Future<void> Function() _stopRadio;
  Future<void> _tail = Future.value();
  BleScanLease? _owner;

  BleScanCoordinator({Future<void> Function()? stopRadio})
      : _stopRadio = stopRadio ?? UniversalBle.stopScan;

  BleScanLease acquire() => _owner = BleScanLease._(this);

  bool _owns(BleScanLease lease) =>
      identical(lease._coordinator, this) && identical(_owner, lease);

  Future<bool> start(BleScanLease lease, Future<void> Function() startRadio) =>
      _enqueue(() async {
        if (!_owns(lease)) return false;
        await _stopRadio();
        if (!_owns(lease)) return false;
        try {
          await startRadio();
        } catch (_) {
          try {
            await _stopRadio();
          } catch (_) {}
          rethrow;
        }
        if (!_owns(lease)) {
          // The next owner's start is queued behind us, so this cleanup cannot
          // stop their scan even when ownership changed during native startup.
          await _stopRadio();
          return false;
        }
        return true;
      });

  Future<void> stop(BleScanLease lease) {
    if (!_owns(lease)) return Future.value();
    _owner = null;
    return _enqueue(() async {
      // A newer start is responsible for replacing the old radio session.
      if (_owner == null) await _stopRadio();
    });
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final actual = _tail.then((_) => operation());
    _tail = actual.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return actual;
  }
}
