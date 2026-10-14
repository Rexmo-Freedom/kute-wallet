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
// `pulse(intensity)` (one soft heartbeat beat) and `pattern(...)` (one of
// the app's named patterns, lib/services/haptic_patterns.dart: events and
// curves for Core Haptics, the rendered waveform for Android; answers
// whether it played). [snap] and [softTap] are the band's releases:
// [HapticPatterns.success] and [HapticPatterns.softRelease].
//
// Rules, enforced here so no caller can forget them:
//   * every call is fire-and-forget and never throws; a phone or platform
//     without the bridge plays nothing (a pattern answers false, so its
//     caller falls back to the system impacts);
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
import 'package:kute/services/haptic_patterns.dart';

/// One call into the bridge, as a test sees it. A pattern's [method] is
/// what asked for it: `snap` and `softTap` (the band's releases) or
/// `pattern` (a named moment), with the [pattern] itself.
@immutable
class ContinuousHapticsCall {
  const ContinuousHapticsCall(this.method,
      [this.intensity, this.sharpness, this.pattern]);

  final String method;
  final double? intensity;
  final double? sharpness;
  final HapticPattern? pattern;

  @override
  String toString() => pattern != null
      ? '$method(${pattern!.name})'
      : intensity == null
          ? method
          : '$method(${intensity!.toStringAsFixed(2)}'
              '${sharpness == null ? '' : ', ${sharpness!.toStringAsFixed(2)}'})';
}

abstract final class ContinuousHaptics {
  static const MethodChannel channel = MethodChannel('kute/continuous_haptics');

  /// The closest two live updates come: about 30 Hz.
  static const Duration updateGap = Duration(milliseconds: 33);

  /// Test seam: while set, every call is recorded here (after the
  /// throttle) instead of reaching the platform.
  @visibleForTesting
  static List<ContinuousHapticsCall>? debugLog;

  /// The owners whose rumble is wanted now, each with its level
  /// (intensity, sharpness), in the order they started. The phone plays
  /// one rumble: the strongest owner's (the leader's).
  static final Map<Object, ({double intensity, double sharpness})> _owners = {};

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

  /// The band's release on success: [HapticPatterns.success] (the whoosh
  /// and the double snap, the family every money success shares) for
  /// [owner], whose rumble stops. Another band's rumble carries on under
  /// it (Core Haptics plays the pattern on top of it; Android's waveform
  /// picks the rumble up again after it). Without the bridge, the system's
  /// medium-then-heavy beat.
  static void snap({Object? owner}) {
    _leave(owner);
    _playPattern('snap', HapticPatterns.success, successFallback);
  }

  /// The band's release without: [HapticPatterns.softRelease] for
  /// [owner], whose rumble stops. Without the bridge, a light impact.
  static void softTap({Object? owner}) {
    _leave(owner);
    _playPattern(
        'softTap', HapticPatterns.softRelease, HapticFeedback.lightImpact);
  }

  /// Plays [pattern] natively, answering whether it played: false on a
  /// device that cannot (no Core Haptics, Android without amplitude
  /// control) or without the bridge, so the caller plays its fallback.
  /// Never throws. [logAs] names the call in [debugLog].
  static Future<bool> play(HapticPattern pattern,
      {String logAs = 'pattern'}) async {
    final log = debugLog;
    if (log != null) {
      log.add(ContinuousHapticsCall(logAs, null, null, pattern));
      return true;
    }
    if (_unavailable) return false;
    try {
      final played =
          await channel.invokeMethod<bool>('pattern', pattern.toMap());
      return played ?? false;
    } on MissingPluginException {
      _unavailable = true;
      return false;
    } catch (_) {
      return false;
    }
  }

  /// The money-success beat as the system impacts (medium, then heavy
  /// 90 ms later): what a phone that cannot play [HapticPatterns.success]
  /// feels, as before.
  static Future<void> successFallback() async {
    await HapticFeedback.mediumImpact();
    await Future<void>.delayed(const Duration(milliseconds: 90));
    await HapticFeedback.heavyImpact();
  }

  @visibleForTesting
  static void debugReset() {
    _owners.clear();
    _lastUpdate.clear();
    _lastPulse = null;
    _unavailable = false;
  }

  /// [owner] leaves before its release: its rumble stops (the phone's,
  /// when it was the last).
  static void _leave(Object? owner) {
    if (owner == null) return;
    _lastUpdate.remove(owner);
    if (_owners.remove(owner) != null) _resume('stop');
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

  static void _playPattern(
      String logAs, HapticPattern pattern, Future<void> Function() fallback) {
    play(pattern, logAs: logAs).then((played) {
      if (!played) _fallback(fallback);
    }, onError: (Object _) => _fallback(fallback));
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

  static void _send(String method, [double? intensity, double? sharpness]) {
    final log = debugLog;
    if (log != null) {
      log.add(ContinuousHapticsCall(method, intensity, sharpness));
      return;
    }
    if (_unavailable) return;
    final args = <String, double>{
      if (intensity != null) 'intensity': intensity,
      if (sharpness != null) 'sharpness': sharpness,
    };
    try {
      channel
          .invokeMethod<void>(method, args.isEmpty ? null : args)
          .catchError((Object e) {
        if (e is MissingPluginException) _unavailable = true;
      });
    } catch (_) {
      _unavailable = true;
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
