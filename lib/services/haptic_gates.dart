// lib/services/haptic_gates.dart
//
// The pure rules that decide WHEN a haptic pattern (kute_haptics.dart) is
// due: no Flutter, no Riverpod, no clock of their own. Unit tested in
// test/services/haptic_gates_test.dart.

/// Odds ticks on the market the person is looking at: one tick when the
/// price has moved [step] (a point) from where it last ticked, and never
/// more than one per [minGapMs]. A move that lands inside the gap is not
/// lost: the anchor stays, so the next price still a point away ticks.
class OddsTickGate {
  OddsTickGate({this.step = 0.01, this.minGapMs = 1000});

  final double step;
  final int minGapMs;
  double? _anchor;
  int? _lastMs;

  /// [price] is 0..1. The first price only sets the anchor.
  bool onPrice(double price, int nowMs) {
    final anchor = _anchor;
    if (anchor == null) {
      _anchor = price;
      return false;
    }
    if ((price - anchor).abs() + 1e-9 < step) return false;
    final last = _lastMs;
    if (last != null && nowMs - last < minGapMs) return false;
    _anchor = price;
    _lastMs = nowMs;
    return true;
  }
}

/// The final-seconds heartbeat of a 5 / 15 minute round: one beat per
/// second for the last [lastSeconds], only while the person is on that
/// round's screen with the app in front and holds a position in it.
class RoundHeartbeatGate {
  RoundHeartbeatGate({this.lastSeconds = 10});

  final int lastSeconds;
  int? _lastBeat;

  bool due({
    required int secondsRemaining,
    required bool holdsPosition,
    required bool visible,
    required bool foreground,
  }) {
    if (secondsRemaining < 1 || secondsRemaining > lastSeconds) {
      // Outside the window: the next round starts clean.
      _lastBeat = null;
      return false;
    }
    if (!holdsPosition || !visible || !foreground) return false;
    if (_lastBeat == secondsRemaining) return false;
    _lastBeat = secondsRemaining;
    return true;
  }
}

enum ComboLegChange { won, lost }

/// What a combo refresh changed: a leg that was open before and is won or
/// lost now. Each leg is `(key, open, won)` with a key naming the combo
/// and the leg. A leg not seen before (the first load, a combo just
/// bought) is never a change, and a voided leg is neither.
///
/// Null when nothing resolved. One answer per refresh however many legs
/// moved: a lost leg outranks a won one (it ends the combo).
ComboLegChange? comboLegChange({
  required Map<String, bool> previousOpen,
  required Iterable<({String key, bool won, bool lost})> next,
}) {
  ComboLegChange? change;
  for (final leg in next) {
    if (previousOpen[leg.key] != true) continue;
    if (leg.lost) return ComboLegChange.lost;
    if (leg.won) change = ComboLegChange.won;
  }
  return change;
}

/// Incoming payments, once each: true when [incoming] holds a payment not
/// seen before that arrived in this session. The history that streams in
/// on the first sync or after a restore is older than [startedAt] and
/// stays quiet; so does everything in the first observation.
class IncomingPaymentGate {
  IncomingPaymentGate({
    required this.startedAt,
    this.skew = const Duration(minutes: 1),
  });

  final DateTime startedAt;

  /// Clock difference allowed between this phone and the payment's stamp.
  final Duration skew;
  final Set<String> _seen = <String>{};
  bool _seeded = false;

  bool observe(Iterable<({String id, DateTime at})> incoming) {
    var fresh = false;
    for (final p in incoming) {
      if (!_seen.add(p.id)) continue;
      if (_seeded && arrivedThisSession(p.at)) fresh = true;
    }
    _seeded = true;
    return fresh;
  }

  bool arrivedThisSession(DateTime at) => !at.isBefore(startedAt.subtract(skew));
}

/// Lets each key through once (a moment card's sequence number).
class OncePerKey<T> {
  OncePerKey({this.maxRemembered = 300});

  final int maxRemembered;
  final Set<T> _seen = <T>{};

  bool first(T key) {
    if (!_seen.add(key)) return false;
    if (_seen.length > maxRemembered) _seen.remove(_seen.first);
    return true;
  }
}
