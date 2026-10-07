// lib/services/hyperliquid/insights/hl_flow_signals.dart
//
// The market signals the Hyperliquid chart can show, computed from the
// venue's public feeds only. Pure: every clock is passed in.
//
//   * Buy/sell pressure and big trades: the public `trades` stream. Each
//     trade names its aggressor side ('B' the buyer crossed the spread,
//     'A' the seller did), so the share of notional bought against sold
//     over a rolling window says who is pressing.
//   * Funding flips: `fundingHistory` (one rate an hour).
//   * Open interest: the venue publishes no history, only the current
//     value (`activeAssetCtx`), so it is sampled while the chart is open
//     and a change is stated only once enough of it has been watched.
//   * The next funding payment: funding settles every hour on the hour.

import 'dart:collection';

import 'package:kute/services/hyperliquid/hyperliquid_websocket.dart'
    show HlTrade;

// ───────────────────────── pressure + big trades ─────────────────────────

/// The window pressure is measured over.
const Duration kHlPressureWindow = Duration(minutes: 5);

/// Fewer trades than this in the window say nothing about who presses.
const int kHlPressureMinTrades = 20;

/// A trade is big at this many times the market's median trade…
const double kHlBigTradeMultiple = 50;

/// …measured over the last this many trades, once this many were seen.
const int kHlBigTradeBaseline = 400;
const int kHlBigTradeMinBaseline = 100;

/// Big-trade markers kept. A new one past the cap replaces the smallest
/// kept, and only when it is larger.
const int kHlBigTradeMaxMarkers = 8;

/// A marker leaves after this long.
const Duration kHlBigTradeLifetime = Duration(hours: 2);

/// Who pressed over the window: the bought share of notional, 0 to 1.
class HlPressure {
  final double buyShare;
  final int trades;
  const HlPressure(this.buyShare, this.trades);
}

/// One unusually large public trade.
class HlBigTrade {
  final int timeMs;
  final double price;
  final double notional;
  final bool isBuy;
  const HlBigTrade({
    required this.timeMs,
    required this.price,
    required this.notional,
    required this.isBuy,
  });
}

/// Accumulates one market's public trades.
class HlTradeFlow {
  final Queue<({int t, double n, bool buy})> _window = Queue();
  final Queue<double> _sizes = Queue();
  final List<HlBigTrade> _big = [];
  int _newest = 0;

  /// Bumped whenever [bigTrades] changes, so a painter can key on it.
  int bigRevision = 0;

  List<HlBigTrade> get bigTrades => List.unmodifiable(_big);

  /// Feeds one trade. A trade older than the newest already seen is a
  /// replay (the stream resends recent trades on a reconnect) and is
  /// dropped.
  void add(HlTrade t) {
    final notional = t.px * t.sz;
    if (t.time <= 0 || notional <= 0 || !notional.isFinite) return;
    if (t.time < _newest) return;
    _newest = t.time;

    // The baseline first: a big trade is judged against the trades
    // before it, not against itself.
    final median = _median();
    _sizes.addLast(notional);
    if (_sizes.length > kHlBigTradeBaseline) _sizes.removeFirst();
    _window.addLast((t: t.time, n: notional, buy: t.isBuy));
    _trim(t.time);

    if (median != null && notional >= median * kHlBigTradeMultiple) {
      final marker = HlBigTrade(
        timeMs: t.time,
        price: t.px,
        notional: notional,
        isBuy: t.isBuy,
      );
      if (_big.length < kHlBigTradeMaxMarkers) {
        _big.add(marker);
        bigRevision++;
      } else {
        var smallest = 0;
        for (var i = 1; i < _big.length; i++) {
          if (_big[i].notional < _big[smallest].notional) smallest = i;
        }
        if (notional > _big[smallest].notional) {
          _big
            ..removeAt(smallest)
            ..add(marker);
          bigRevision++;
        }
      }
    }
  }

  double? _median() {
    if (_sizes.length < kHlBigTradeMinBaseline) return null;
    final sorted = _sizes.toList()..sort();
    return sorted[sorted.length ~/ 2];
  }

  void _trim(int nowMs) {
    final cutoff = nowMs - kHlPressureWindow.inMilliseconds;
    while (_window.isNotEmpty && _window.first.t < cutoff) {
      _window.removeFirst();
    }
    final before = _big.length;
    _big.removeWhere(
        (b) => nowMs - b.timeMs > kHlBigTradeLifetime.inMilliseconds);
    if (_big.length != before) bigRevision++;
  }

  /// Pressure over the window ending at [nowMs]; null while too few
  /// trades printed in it.
  HlPressure? pressure(int nowMs) {
    _trim(nowMs);
    if (_window.length < kHlPressureMinTrades) return null;
    var buy = 0.0, total = 0.0;
    for (final w in _window) {
      total += w.n;
      if (w.buy) buy += w.n;
    }
    if (total <= 0) return null;
    return HlPressure(buy / total, _window.length);
  }
}

// ───────────────────────────── funding ─────────────────────────────

/// One hourly funding rate.
typedef HlFundingPoint = ({int timeMs, double rate});

/// A flip must hold this many hours to count: the rate crossing zero for
/// an hour and back is noise.
const int kHlFundingFlipHoldHours = 3;

/// Flip markers kept, newest.
const int kHlFundingFlipMax = 6;

/// A moment funding changed sign and stayed there.
class HlFundingFlip {
  final int timeMs;

  /// True when longs started paying shorts (the rate turned positive).
  final bool longsPay;
  const HlFundingFlip(this.timeMs, {required this.longsPay});
}

/// The sign changes of [history] (oldest first) that held for
/// [kHlFundingFlipHoldHours] hours, newest [kHlFundingFlipMax].
List<HlFundingFlip> hlFundingFlips(List<HlFundingPoint> history) {
  final out = <HlFundingFlip>[];
  int? held; // the sign in force: 1 or -1
  var i = 0;
  while (i < history.length) {
    final sign = history[i].rate > 0
        ? 1
        : history[i].rate < 0
            ? -1
            : 0;
    if (sign == 0 || sign == held) {
      i++;
      continue;
    }
    // A run of the new sign, from here.
    var j = i;
    while (j < history.length &&
        (history[j].rate > 0 ? 1 : (history[j].rate < 0 ? -1 : 0)) == sign) {
      j++;
    }
    if (j - i >= kHlFundingFlipHoldHours) {
      if (held != null) {
        out.add(HlFundingFlip(history[i].timeMs, longsPay: sign > 0));
      }
      held = sign;
    }
    i = j;
  }
  return out.length > kHlFundingFlipMax
      ? out.sublist(out.length - kHlFundingFlipMax)
      : out;
}

/// The next funding settlement after [now]: the top of the next hour.
DateTime hlNextFundingTime(DateTime now) {
  final utc = now.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day, utc.hour)
      .add(const Duration(hours: 1));
}

/// What a position of [positionValue] dollars pays or receives at the
/// next settlement at the current hourly [rate]: longs pay a positive
/// rate, shorts a negative one. An estimate, since the rate moves until
/// the hour closes.
({bool pays, double amount}) hlFundingEstimate({
  required double positionValue,
  required bool isLong,
  required double rate,
}) =>
    (
      pays: isLong ? rate > 0 : rate < 0,
      amount: positionValue.abs() * rate.abs(),
    );

// ───────────────────────────── open interest ─────────────────────────────

/// Open interest must have been watched this long before a change is
/// stated.
const Duration kHlOiMinWatch = Duration(minutes: 10);

/// The change is measured over at most this long.
const Duration kHlOiWindow = Duration(minutes: 30);

/// A change this large over the window is sharp.
const double kHlOiSharpChange = 0.01;

/// At most one sample this often.
const Duration kHlOiSampleEvery = Duration(seconds: 30);

/// Open interest moved sharply: the change as a fraction (signed) over
/// [minutes].
class HlOiSignal {
  final double change;
  final int minutes;
  const HlOiSignal(this.change, this.minutes);
  bool get rising => change > 0;
}

/// Samples the current open interest while the chart is open.
class HlOiTracker {
  final List<({int t, double oi})> _samples = [];

  void sample(int nowMs, double openInterest) {
    if (openInterest <= 0 || !openInterest.isFinite) return;
    if (_samples.isNotEmpty &&
        nowMs - _samples.last.t < kHlOiSampleEvery.inMilliseconds) {
      return;
    }
    _samples.add((t: nowMs, oi: openInterest));
    final cutoff = nowMs - kHlOiWindow.inMilliseconds;
    while (_samples.length > 2 && _samples[1].t <= cutoff) {
      _samples.removeAt(0);
    }
  }

  /// The signal now, or null: not watched for long enough yet, or the
  /// change is not sharp.
  HlOiSignal? get signal {
    if (_samples.length < 2) return null;
    final first = _samples.first, last = _samples.last;
    final span = last.t - first.t;
    if (span < kHlOiMinWatch.inMilliseconds) return null;
    final change = (last.oi - first.oi) / first.oi;
    if (change.abs() < kHlOiSharpChange) return null;
    return HlOiSignal(change, (span / 60000).round());
  }
}
