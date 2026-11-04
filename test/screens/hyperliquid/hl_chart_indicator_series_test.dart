// The Advanced chart's indicator maths against known values: Wilder's
// own RSI worked example (the StockCharts table), small hand-worked
// series, and an 80-bar tape whose values come from a separate
// implementation of TradingView's Pine reference (ta.sma, ta.ema, ta.rma,
// ta.stdev, ta.rsi, ta.macd, Stoch RSI, ta.atr, ta.supertrend, ta.obv).

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_indicator_series.dart';

HyperliquidCandle _bar(int i, double o, double h, double l, double c,
        double v,
        {Duration step = const Duration(hours: 1),
        DateTime? start}) =>
    HyperliquidCandle(
      openTime: (start ?? DateTime.utc(2026, 10, 1)).add(step * i),
      closeTime: (start ?? DateTime.utc(2026, 10, 1)).add(step * (i + 1)),
      open: o,
      high: h,
      low: l,
      close: c,
      volume: v,
    );

/// The 80-bar tape the reference values were computed on.
List<HyperliquidCandle> _tape() {
  final out = <HyperliquidCandle>[];
  var prev = 100.0;
  for (var i = 0; i < 80; i++) {
    final c = 100 + 10 * math.sin(i / 5) + 3 * math.cos(i / 1.7) + i * 0.2;
    final o = prev;
    final h = math.max(o, c) + 0.5 + (i % 4) * 0.3;
    final l = math.min(o, c) - 0.4 - (i % 3) * 0.25;
    final v = 100.0 + (i * 37) % 50;
    out.add(_bar(i, o, h, l, c, v));
    prev = c;
  }
  return out;
}

const _idx = [19, 25, 33, 40, 47, 55, 63, 71, 79];

void _expectAt(List<double> got, List<double?> want, {double tol = 1e-6}) {
  for (var k = 0; k < _idx.length; k++) {
    final w = want[k];
    final g = got[_idx[k]];
    if (w == null) {
      expect(g.isNaN, isTrue, reason: 'bar ${_idx[k]} should be warming up');
    } else {
      expect(g, closeTo(w, tol), reason: 'bar ${_idx[k]}');
    }
  }
}

void main() {
  final tape = _tape();
  final closes = [for (final k in tape) k.close];

  group('moving averages', () {
    test('SMA: a full window, and a gap restarts it', () {
      final s = hlSma([1, 2, 3, 4, 5, double.nan, 7, 8, 9], 3);
      expect(s.sublist(0, 2).every((v) => v.isNaN), isTrue);
      expect(s.sublist(2, 5), [2, 3, 4]);
      expect(s.sublist(5, 8).every((v) => v.isNaN), isTrue);
      expect(s[8], 8);
    });

    test('EMA is seeded with the SMA of its first period (ta.ema)', () {
      final e = hlEma([1, 2, 3, 4, 5], 3);
      expect(e[0].isNaN && e[1].isNaN, isTrue);
      expect(e.sublist(2), [2, 3, 4]);
    });

    test("RMA is Wilder's smoothing (ta.rma)", () {
      final r = hlRma([1, 2, 3, 4, 5], 2);
      expect(r[0].isNaN, isTrue);
      expect(r.sublist(1), [1.5, 2.25, 3.125, 4.0625]);
    });

    test('SMA 9 and EMA 9 on the tape', () {
      _expectAt(hlSma(closes, 9), [
        103.7802738369, 97.134822853, 101.6304637847, 113.7448870742,
        115.5412356976, 104.1825647169, 105.2139974005, 119.7775548222,
        121.2100576441,
      ]);
      _expectAt(hlEma(closes, 9), [
        102.1419736975, 97.5753372375, 104.4816575715, 112.9044213627,
        113.1491072482, 105.2525258781, 107.588915031, 118.5936799472,
        118.8587877655,
      ]);
    });
  });

  group('RSI', () {
    test("Wilder's worked example (RSI 14)", () {
      const c = [
        44.3389, 44.0902, 44.1497, 43.6124, 44.3278, 44.8264, 45.0955, //
        45.4245, 45.8433, 46.0826, 45.8931, 46.0328, 45.6140, 46.2820,
        46.2820, 46.0028, 46.0328, 46.4116, 46.2222, 45.6439, 46.2122,
        46.2521, 45.7137, 46.4515, 45.7835, 45.3548, 44.0288, 44.1783,
        44.2181, 44.5672, 43.4205, 42.6628, 43.1314,
      ];
      const want = [
        70.53, 66.32, 66.55, 69.41, 66.36, 57.97, 62.93, 63.26, 56.06, //
        62.38, 54.71, 50.42, 39.99, 41.46, 41.87, 45.46, 37.30, 33.08,
        37.77,
      ];
      final r = hlRsi(c);
      expect(r.sublist(0, 14).every((v) => v.isNaN), isTrue);
      for (var i = 0; i < want.length; i++) {
        expect(r[14 + i], closeTo(want[i], 0.005), reason: 'bar ${14 + i}');
      }
    });

    test('a flat market reads 50, a one-way one 100', () {
      expect(hlRsi(List.filled(20, 5.0)).last, 50);
      expect(hlRsi([for (var i = 0; i < 20; i++) i.toDouble()]).last, 100);
    });

    test('RSI 14 on the tape', () {
      _expectAt(hlWilderRsi(tape), [
        39.8243991684, 30.5114967465, 73.2173374294, 79.9484608321,
        43.8313786019, 36.7687582388, 68.8450050302, 76.8752150869,
        41.5171883508,
      ]);
    });
  });

  test('Bollinger bands 20, 2 (population deviation)', () {
    final b = hlBollinger(tape);
    _expectAt(b.upper, [
      116.0481415413, 116.9639610488, 110.5277468508, 122.1700695119,
      123.8455184446, 122.9679286246, 115.740141912, 127.6836271576,
      129.640055645,
    ]);
    _expectAt(b.lower, [
      96.060757188, 89.9996515902, 89.6402291478, 88.1224300066,
      100.1007838845, 98.1631495981, 96.5435038714, 94.4993822287,
      107.4165663589,
    ]);
    expect(b.basis[30], closeTo((b.upper[30] + b.lower[30]) / 2, 1e-9));
  });

  test('MACD 12, 26, 9', () {
    final m = hlMacd(tape);
    expect(m.macd.indexWhere((v) => v.isFinite), 25);
    expect(m.signal.indexWhere((v) => v.isFinite), 33);
    _expectAt(m.macd, [
      null, -5.254471974, -0.431430202, 3.0248061711, 2.072240793,
      -1.4806180193, 0.0356733515, 3.8853482488, 2.3418509746,
    ]);
    _expectAt(m.signal, [
      null, null, -3.5633467472, 0.9556162035, 2.6338630169,
      -0.2449631687, -1.0516924998, 2.4788703746, 3.4052684682,
    ]);
    _expectAt(m.histogram, [
      null, null, 3.1319165452, 2.0691899676, -0.5616222239,
      -1.2356548506, 1.0873658513, 1.4064778742, -1.0634174936,
    ]);
  });

  test('Stoch RSI 14, 14, 3, 3', () {
    final s = hlStochRsi(tape);
    expect(s.k.indexWhere((v) => v.isFinite), 29);
    expect(s.d.indexWhere((v) => v.isFinite), 31);
    _expectAt(s.k, [
      null, null, 100.0, 100.0, 0.0, 3.6337457514, 100.0, 99.5223993286, 0.0,
    ]);
    _expectAt(s.d, [
      null, null, 100.0, 100.0, 12.5493511648, 4.6812972944,
      92.0548365664, 99.0736332383, 8.3818163217,
    ]);
  });

  test('ATR 14: the first true range is the bar\'s own range', () {
    final tr = hlTrueRange(tape);
    expect(tr[0], tape[0].high - tape[0].low);
    final a = hlAtr(tape);
    expect(a.indexWhere((v) => v.isFinite), 13);
    expect(a[13], closeTo(tr.sublist(0, 14).reduce((x, y) => x + y) / 14,
        1e-12));
    _expectAt(a, [
      3.0634159087, 2.8208625263, 3.3569119426, 2.9989684746, 3.3670665758,
      2.9100327854, 3.362893139, 2.991595165, 3.3270197398,
    ]);
  });

  test('Supertrend 10, 3', () {
    final s = hlSupertrend(tape);
    expect(s.line.indexWhere((v) => v.isFinite), 9);
    _expectAt(s.line, [
      107.7831182065, 102.7500587574, 101.1212765233, 107.9161644056,
      119.545544596, 112.1808007747, 103.5207006509, 113.1278231876,
      124.8132735053,
    ]);
    // TradingView's direction 1 is down (the line over the price).
    const dir = [1, 1, -1, -1, 1, 1, -1, -1, 1];
    for (var k = 0; k < _idx.length; k++) {
      expect(s.up[_idx[k]], dir[k] == -1, reason: 'bar ${_idx[k]}');
    }
    final flips = [
      for (var i = 1; i < s.up.length; i++)
        if (s.up[i] != null && s.up[i - 1] != null && s.up[i] != s.up[i - 1])
          i,
    ];
    expect(flips, [30, 46, 62, 78]);
    // Up: the line is under the close; down: over it.
    for (var i = 9; i < tape.length; i++) {
      if (s.up[i]!) {
        expect(s.line[i], lessThan(tape[i].close));
      } else {
        expect(s.line[i], greaterThan(tape[i].close));
      }
    }
  });

  test('OBV adds up-close volume and takes off down-close volume', () {
    final bars = [
      _bar(0, 10, 11, 9, 10, 100),
      _bar(1, 10, 12, 9, 11, 50),
      _bar(2, 11, 12, 9, 10, 30),
      _bar(3, 10, 12, 9, 10, 70),
    ];
    expect(hlObv(bars), [0, 50, 20, 20]);
    _expectAt(hlObv(tape), [
      396.0, -69.0, 739.0, 1622.0, 1218.0, 968.0, 1226.0, 1716.0, 1424.0,
    ]);
  });

  group('anchored VWAP', () {
    test('hourly bars restart at 00:00 UTC', () {
      final start = DateTime.utc(2026, 10, 1, 22);
      final bars = [
        _bar(0, 10, 12, 9, 11, 10, start: start), // tp 32/3
        _bar(1, 11, 13, 10, 12, 30, start: start), // tp 35/3
        _bar(2, 12, 15, 12, 15, 20, start: start), // a new day: tp 14
        _bar(3, 15, 16, 14, 15, 20, start: start), // tp 15
      ];
      expect(hlVwapAnchorFor(hlBarMs(bars)), HlVwapAnchor.day);
      final v = hlAnchoredVwap(bars);
      expect(v[0], closeTo(32 / 3, 1e-12));
      expect(v[1], closeTo((32 / 3 * 10 + 35 / 3 * 30) / 40, 1e-12));
      expect(v[2], closeTo(14, 1e-12));
      expect(v[3], closeTo(14.5, 1e-12));
    });

    test('daily bars anchor to the week, weekly ones to the month', () {
      expect(hlVwapAnchorFor(const Duration(days: 1).inMilliseconds),
          HlVwapAnchor.week);
      expect(hlVwapAnchorFor(const Duration(days: 7).inMilliseconds),
          HlVwapAnchor.month);
      // 2026-10-04 is a Sunday, 10-05 a Monday: the week restarts there.
      final start = DateTime.utc(2026, 10, 4);
      const day = Duration(days: 1);
      final bars = [
        _bar(0, 10, 10, 10, 10, 5, step: day, start: start),
        _bar(1, 20, 20, 20, 20, 5, step: day, start: start),
      ];
      final v = hlAnchoredVwap(bars);
      expect(v[0], 10);
      expect(v[1], 20);
    });

    test('nothing traded yet: no value', () {
      final v = hlAnchoredVwap([_bar(0, 10, 11, 9, 10, 0)]);
      expect(v.single.isNaN, isTrue);
    });
  });

  group('volume profile', () {
    test('a bar\'s volume spreads over its range, split up and down', () {
      final p = hlVolumeProfile([
        _bar(0, 2, 10, 0, 8, 10), // up, over both rows
        _bar(1, 9, 10, 5, 6, 20), // down, the upper row only
      ], rows: 2)!;
      expect(p.lo, 0);
      expect(p.hi, 10);
      expect(p.up, [5, 5]);
      expect(p.down, [0, 20]);
      expect(p.poc, 1);
      expect((p.vaLow, p.vaHigh), (1, 1));
      expect(p.priceAt(1), 7.5);
    });

    test('the value area grows toward the busier side to 70%', () {
      // Rows 0..4 at 1-wide bars: volumes 10, 35, 100, 30, 25.
      final vols = [10.0, 35.0, 100.0, 30.0, 25.0];
      final p = hlVolumeProfile([
        for (var r = 0; r < 5; r++)
          _bar(r, r + 0.2, r + 1.0, r.toDouble(), r + 0.8, vols[r]),
      ], rows: 5)!;
      for (var r = 0; r < 5; r++) {
        expect(p.total(r), closeTo(vols[r], 1e-9));
      }
      expect(p.poc, 2);
      // 100 → +35 (below) = 135 → +30 (above) = 165 ≥ 70% of 200.
      expect((p.vaLow, p.vaHigh), (1, 3));
    });

    test('no volume, no profile', () {
      expect(hlVolumeProfile([_bar(0, 1, 2, 0, 1, 0)]), isNull);
      expect(hlVolumeProfile(const []), isNull);
    });
  });

  test('Heikin Ashi keeps times and volume', () {
    final ha = hlHeikinAshi(tape.sublist(0, 3));
    final k = tape[1];
    expect(ha[1].close, (k.open + k.high + k.low + k.close) / 4);
    expect(ha[1].open, (ha[0].open + ha[0].close) / 2);
    expect(ha[1].openTime, k.openTime);
    expect(ha[1].volume, k.volume);
  });
}
