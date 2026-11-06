// lib/services/foreground_timer.dart
//
// A one-shot timer that only counts while the app is on screen and active
// (`AppLifecycleState.resumed`).
//
// A wall-clock timer kept running while a Face ID sheet was up (the app is
// `inactive` for the whole scan) and while the app sat in the background,
// so a watchdog armed for an order could fire before the order had even
// had its time on screen, and an order that went through after the scan
// read as stuck. This one pauses for exactly those spells.
//
// It ticks once a second and adds the tick only while the app is resumed.
// Before the first lifecycle event the app counts as resumed (the binding
// reports null then), and so does a process with no binding (tests).

import 'dart:async';

import 'package:flutter/widgets.dart';

class ForegroundTimer {
  ForegroundTimer(this.duration, this._onFire,
      {Duration tick = const Duration(seconds: 1)})
      : _tick = tick {
    _timer = Timer.periodic(_tick, (_) => _onTick());
  }

  final Duration duration;
  final void Function() _onFire;
  final Duration _tick;
  late final Timer _timer;
  Duration _counted = Duration.zero;
  bool _done = false;

  /// Foreground time counted so far.
  Duration get counted => _counted;

  bool get isActive => !_done;

  void cancel() {
    _done = true;
    _timer.cancel();
  }

  void _onTick() {
    if (_done) return;
    if (!isAppInForeground()) return;
    _counted += _tick;
    if (_counted < duration) return;
    cancel();
    _onFire();
  }

  /// Test seam: stands in for the app's lifecycle (true = resumed).
  @visibleForTesting
  static bool Function()? debugForeground;

  /// Whether the app is resumed now. A Face ID or fingerprint sheet makes
  /// it `inactive`: that time is not counted.
  static bool isAppInForeground() {
    final seam = debugForeground;
    if (seam != null) return seam();
    try {
      final state = WidgetsBinding.instance.lifecycleState;
      return state == null || state == AppLifecycleState.resumed;
    } catch (_) {
      // No binding (a plain Dart test): nothing pauses.
      return true;
    }
  }
}
