// lib/services/network_change_signal.dart
//
// "The network may have changed": the one signal every region answer the
// app holds listens to (Polymarket's geoblock, Hyperliquid's legal check,
// Kute's runtime policy; see lib/services/region_freshness.dart).
//
// Two sources, debounced together:
//   * the native path listener on the `kute/network_path` EventChannel:
//     iOS `NWPathMonitor` (ios/Runner/NetworkPathPlugin.swift), Android
//     `ConnectivityManager.registerDefaultNetworkCallback`
//     (NetworkPathPlugin.kt). Both report a VPN switching on or off: on
//     iOS the VPN's virtual interface joins or leaves the path, on
//     Android the VPN becomes (or stops being) the app's default network.
//     The native side drops updates that change nothing and sends a bare
//     "changed" with no detail;
//   * the app coming back to the foreground after it was hidden or paused
//     (a VPN switched in another app, a flight landed while the phone was
//     in a pocket). A Face ID prompt or Control Center (inactive only)
//     is not a resume.
//
// A burst (Wi-Fi drops, cellular takes over, the VPN reconnects) is one
// event, [debounce] after the last of it. When both kinds land in one
// window the event is a network change.
//
// No `connectivity_plus`: the app needs one bit (something changed), not
// connectivity state, and the two native listeners are a few dozen lines
// in the style of ContinuousHapticsPlugin. A phone or test without the
// bridge sends nothing and the app falls back to resume and the tap-time
// re-check.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Why a region answer was asked again. The analytics `trigger` values.
enum RegionRecheckTrigger {
  resume('resume'),
  networkChange('network_change'),
  tap('tap'),
  startup('startup'),
  timer('timer');

  const RegionRecheckTrigger(this.id);

  /// The analytics value.
  final String id;
}

class NetworkChangeSignal with WidgetsBindingObserver {
  NetworkChangeSignal({
    Stream<Object?> Function()? nativeEvents,
    this.debounce = defaultDebounce,
  }) : _nativeEvents = nativeEvents ?? _platformEvents;

  static const EventChannel channel = EventChannel('kute/network_path');

  /// Long enough for a VPN reconnect or a Wi-Fi to cellular handover to
  /// settle, short enough that the answer is fresh before a tap.
  static const Duration defaultDebounce = Duration(milliseconds: 1500);

  static final NetworkChangeSignal instance = NetworkChangeSignal();

  static Stream<Object?> _platformEvents() => channel.receiveBroadcastStream();

  final Stream<Object?> Function() _nativeEvents;
  final Duration debounce;
  final StreamController<RegionRecheckTrigger> _changes =
      StreamController<RegionRecheckTrigger>.broadcast();
  StreamSubscription<Object?>? _native;
  Timer? _pending;
  RegionRecheckTrigger? _pendingTrigger;
  bool _started = false;
  bool _wasHidden = false;

  /// One event per settled change: [RegionRecheckTrigger.networkChange] or
  /// [RegionRecheckTrigger.resume].
  Stream<RegionRecheckTrigger> get changes => _changes.stream;

  /// Starts listening to the native bridge and the app lifecycle.
  /// Idempotent. Never throws.
  void start() {
    if (_started) return;
    _started = true;
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {}
    try {
      _native = _nativeEvents().listen(
        (_) => _schedule(RegionRecheckTrigger.networkChange),
        // No bridge (tests, an old engine): resume and the tap still
        // re-check.
        onError: (Object _) {},
      );
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _wasHidden = true;
      case AppLifecycleState.resumed:
        if (_wasHidden) {
          _wasHidden = false;
          _schedule(RegionRecheckTrigger.resume);
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  void _schedule(RegionRecheckTrigger trigger) {
    _pendingTrigger = _pendingTrigger == RegionRecheckTrigger.networkChange
        ? RegionRecheckTrigger.networkChange
        : trigger;
    _pending?.cancel();
    _pending = Timer(debounce, () {
      final settled = _pendingTrigger;
      _pendingTrigger = null;
      if (settled != null && !_changes.isClosed) _changes.add(settled);
    });
  }

  /// Test seam: a native "changed" or a resume, as if it just happened
  /// (still debounced).
  @visibleForTesting
  void debugReport(RegionRecheckTrigger trigger) => _schedule(trigger);

  @visibleForTesting
  Future<void> dispose() async {
    _pending?.cancel();
    await _native?.cancel();
    if (_started) {
      try {
        WidgetsBinding.instance.removeObserver(this);
      } catch (_) {}
    }
    await _changes.close();
  }
}
