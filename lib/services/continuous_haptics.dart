// lib/services/continuous_haptics.dart
//
// A real continuous haptic whose strength changes live, for the rubber
// band a waiting money action wears (lib/screens/shared/rubber_band_progress.dart).
// Modelled on Instagram's vanish-mode pull: a low "sprocket" rumble that
// rises while the pull tightens, a ratchet of clicks on top of it, and a
// whoosh-and-snap when it lets go.
//
// The native side is a small bridge on the `kute/continuous_haptics`
// MethodChannel:
//   * iOS (ios/Runner/ContinuousHapticsPlugin.swift): Core Haptics, one
//     looping continuous event on a CHHapticAdvancedPatternPlayer whose
//     intensity and sharpness follow live dynamic parameters; transients
//     for the ratchet, the heartbeat and the snap;
//   * Android (ContinuousHapticsPlugin.kt): a repeating amplitude waveform
//     on the Vibrator, re-issued at the new amplitude; plain pulses on a
//     phone without amplitude control.
//
// Methods: `start(intensity, sharpness)`, `update(intensity, sharpness)`,
// `stop()`, `tick(intensity, sharpness)` (one ratchet click),
// `pulse(intensity)` (one soft heartbeat beat), `snap()` (the whoosh then
// the snap, on success) and `softTap()` (a release without).
//
// Rules, enforced here so no caller can forget them:
//   * every call is fire-and-forget and never throws; a phone or platform
//     without the bridge plays nothing (the snap and the soft tap fall back
//     to the system impacts);
//   * `update` is throttled to about 30 Hz ([updateGap]);
//   * one rumble at a time: each owner (a band) starts and stops its
//     own, and the phone plays the strongest owner's level and only its
//     ratchet; another owner's stop does not touch it;
//   * the rumble stops the moment the app leaves the foreground (here, and
//     natively). Callers stop it on dispose, when a route covers them and
//     under Reduce Motion. The system haptics setting applies on its own.
//
// This is feedback, not an action: no analytics event fires here.

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// One call into the bridge, as a test sees it.
@immutable
class ContinuousHapticsCall {
  const ContinuousHapticsCall(this.method, [this.intensity, this.sharpness]);

  final String method;
  final double? intensity;
  final double? sharpness;

  @override
  String toString() => intensity == null
      ? method
      : '$method(${intensity!.toStringAsFixed(2)}'
          '${sharpness == null ? '' : ', ${sharpness!.toStringAsFixed(2)}'})';
}

abstract final class ContinuousHaptics {
  static const MethodChannel channel =
      MethodChannel('kute/continuous_haptics');

  /// The closest two live updates come: about 30 Hz.
  static const Duration updateGap = Duration(milliseconds: 33);

  /// Test seam: while set, every call is recorded here (after the
  /// throttle) instead of reaching the platform.
  @visibleForTesting
  static List<ContinuousHapticsCall>? debugLog;

  /// The owners whose rumble is wanted now, each with its level
  /// (intensity, sharpness), in the order they started. The phone plays
  /// one rumble: the strongest owner's (the leader's).
  static final Map<Object, ({double intensity, double sharpness})> _owners =
      {};

  /// When each owner's last update went out, on its own clock.
  static final Map<Object, Duration> _lastUpdate = {};

  /// When the last heartbeat beat went out (several long waits beat as
  /// one).
  static Duration? _lastPulse;

  /// The bridge is missing (a platform without it, a test): nothing is
  /// sent again.
  static bool _unavailable = false;

  static WidgetsBindingObserver? _lifecycle;
  static final Stopwatch _clock = Stopwatch();

  /// Whether a rumble is playing (for [owner], when given).
  static bool isRunning([Object? owner]) =>
      owner == null ? _owners.isNotEmpty : _owners.containsKey(owner);

  /// The owner whose level the rumble plays: the strongest, the first to
  /// start on a tie.
  static Object? get _leader {
    Object? best;
    var level = -1.0;
    for (final e in _owners.entries) {
      if (e.value.intensity > level) {
        best = e.key;
        level = e.value.intensity;
      }
    }
    return best;
  }

  /// Starts the rumble at [intensity] and [sharpness] (0..1), for
  /// [owner]. With another owner's rumble already playing, the phone
  /// keeps one rumble, at the stronger of the two.
  static void start(double intensity, double sharpness, {Object? owner}) {
    final key = owner ?? _anonymous;
    final first = _owners.isEmpty;
    _owners[key] = (intensity: _unit(intensity), sharpness: _unit(sharpness));
    _lastUpdate.remove(key);
    _watchLifecycle();
    final lead = _owners[_leader]!;
    _send(first ? 'start' : 'update', lead.intensity, lead.sharpness);
  }

  /// Moves [owner]'s rumble to [intensity] and [sharpness], smoothly. Only
  /// the leader's level reaches the phone, at most one every [updateGap]
  /// of [at] (the caller's clock, frame time for a ticker; a stopwatch
  /// otherwise); the rest are dropped, the next one carries the latest
  /// value.
  static void update(double intensity, double sharpness,
      {Object? owner, Duration? at}) {
    final key = owner ?? _anonymous;
    if (!_owners.containsKey(key)) return;
    _owners[key] = (intensity: _unit(intensity), sharpness: _unit(sharpness));
    if (!identical(_leader, key)) return;
    final now = at ?? _now();
    final last = _lastUpdate[key];
    if (last != null && now >= last && now - last < updateGap) return;
    _lastUpdate[key] = now;
    _send('update', _unit(intensity), _unit(sharpness));
  }

  /// Stops [owner]'s rumble (every rumble, without an owner). Another
  /// owner's keeps playing, at its own level.
  static void stop({Object? owner}) {
    if (owner == null) {
      if (_owners.isEmpty) return;
      _owners.clear();
      _lastUpdate.clear();
      _send('stop');
      return;
    }
    if (_owners.remove(owner) == null) return;
    _lastUpdate.remove(owner);
    _resume('stop');
  }

  /// One ratchet click over the rumble. With an [owner], only the
  /// leader's clicks play, so two bands never ratchet over each other.
  static void tick(double intensity, double sharpness, {Object? owner}) {
    if (owner != null && _owners.isNotEmpty && !identical(_leader, owner)) {
      return;
    }
    _send('tick', _unit(intensity), _unit(sharpness));
  }

  /// One soft heartbeat beat at [intensity] (a long wait's pulse). Never
  /// under a rumble, and several waits beat as one (at most one a
  /// second).
  static void pulse(double intensity, {Duration? at}) {
    if (_owners.isNotEmpty) return;
    final now = at ?? _now();
    final last = _lastPulse;
    if (last != null &&
        now >= last &&
        now - last < const Duration(milliseconds: 900)) {
      return;
    }
    _lastPulse = now;
    _send('pulse', _unit(intensity));
  }

  /// The whoosh, then the snap, at full strength: [owner]'s action went
  /// through. The phone stops the rumble for it; another owner's rumble
  /// starts again right after.
  static void snap({Object? owner}) {
    if (owner != null) {
      _owners.remove(owner);
      _lastUpdate.remove(owner);
    }
    _send('snap', null, null, HapticFeedback.heavyImpact);
    _restart();
  }

  /// One soft tap: [owner]'s band let go without the action going through.
  /// The phone stops the rumble for it; another owner's starts again.
  static void softTap({Object? owner}) {
    if (owner != null) {
      _owners.remove(owner);
      _lastUpdate.remove(owner);
    }
    _send('softTap', null, null, HapticFeedback.lightImpact);
    _restart();
  }

  @visibleForTesting
  static void debugReset() {
    _owners.clear();
    _lastUpdate.clear();
    _lastPulse = null;
    _unavailable = false;
  }

  /// After an owner left: stop when it was the last ([method]), otherwise
  /// carry on at the new leader's level.
  static void _resume(String method) {
    final lead = _leader;
    if (lead == null) {
      _send(method);
    } else {
      final level = _owners[lead]!;
      _send('update', level.intensity, level.sharpness);
    }
  }

  /// The native snap and soft tap stop the rumble: start it again for the
  /// owners still waiting.
  static void _restart() {
    final lead = _leader;
    if (lead == null) return;
    final level = _owners[lead]!;
    _lastUpdate.clear();
    _send('start', level.intensity, level.sharpness);
  }

  static final Object _anonymous = Object();

  static double _unit(double v) =>
      v.isFinite ? v.clamp(0.0, 1.0).toDouble() : 0.0;

  static Duration _now() {
    if (!_clock.isRunning) _clock.start();
    return _clock.elapsed;
  }

  static void _watchLifecycle() {
    if (_lifecycle != null) return;
    try {
      final observer = _LifecycleStop();
      WidgetsBinding.instance.addObserver(observer);
      _lifecycle = observer;
    } catch (_) {
      // No binding (a pure Dart test): the callers' own stops apply.
    }
  }

  static void _send(String method,
      [double? intensity, double? sharpness, Future<void> Function()? fallback]) {
    final log = debugLog;
    if (log != null) {
      log.add(ContinuousHapticsCall(method, intensity, sharpness));
      return;
    }
    if (_unavailable) {
      _fallback(fallback);
      return;
    }
    final args = <String, double>{
      if (intensity != null) 'intensity': intensity,
      if (sharpness != null) 'sharpness': sharpness,
    };
    try {
      channel
          .invokeMethod<void>(method, args.isEmpty ? null : args)
          .catchError((Object e) {
        if (e is MissingPluginException) _unavailable = true;
        _fallback(fallback);
      });
    } catch (_) {
      _unavailable = true;
      _fallback(fallback);
    }
  }

  static void _fallback(Future<void> Function()? fallback) {
    if (fallback == null) return;
    try {
      fallback().catchError((Object _) {});
    } catch (_) {}
  }
}

/// Stops any rumble the moment the app leaves the foreground.
class _LifecycleStop with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) ContinuousHaptics.stop();
  }
}
