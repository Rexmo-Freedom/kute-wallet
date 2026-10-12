// TEMPORARY debug instrumentation: times the in-app conversion from the
// confirm tap to the spinner closing. Remove this file and every
// `ConvTiming` call once the slow step is found.
import 'package:flutter/foundation.dart';

class ConvTiming {
  ConvTiming._();

  static final Stopwatch _sw = Stopwatch();
  static int _lastMs = 0;

  /// Restarts the shared stopwatch at the tap and logs [step].
  static void start([String step = 'tap']) {
    if (!kDebugMode) return;
    _sw
      ..reset()
      ..start();
    _lastMs = 0;
    debugPrint('[conv-timing] $step +0ms (0ms)');
  }

  /// Logs [step] with ms since the tap and since the previous mark. Before
  /// any tap (e.g. estimate fetches while typing) the stopwatch starts at
  /// the first mark, so the deltas still show typing time.
  static void mark(String step) {
    if (!kDebugMode) return;
    if (!_sw.isRunning) {
      _sw.start();
      _lastMs = 0;
    }
    final now = _sw.elapsedMilliseconds;
    final delta = now - _lastMs;
    _lastMs = now;
    debugPrint('[conv-timing] $step +${now}ms (${delta}ms)');
  }
}
