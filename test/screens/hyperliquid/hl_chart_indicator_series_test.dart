// The Advanced chart's indicator maths against known values: Wilder's
// own RSI worked example (the StockCharts table), small hand-worked
// series, and an 80-bar tape whose values come from a separate
// implementation of TradingView's Pine reference (ta.sma, ta.ema, ta.rma,
// ta.stdev, ta.rsi, ta.macd, Stoch RSI, ta.atr, ta.supertrend, ta.obv, and
// TradingView's built-in Ichimoku Cloud and Directional Movement Index
// scripts). Ichimoku, ADX and the pivots are also pinned by hand-worked
// small series, the arithmetic written beside them.

import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_indicator_catalog.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_indicator_frame.dart';
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

  group('Ichimoku', () {
    // A climbing tape: close 100 + i, high close + 1, low close − 1. Over a
    // window ending at i the highest high is 101 + i and the lowest low
    // 99 + i − (len − 1), so each midline is a plain line in i:
    //   conversion (9)  = 96 + i
    //   base (26)       = 87.5 + i
    //   span A, drawn 25 ahead = ((96 + j) + (87.5 + j)) / 2, j = i − 25
    //                   = 66.75 + i
    //   span B (52), drawn 25 ahead = 74.5 + j = 49.5 + i
    //   lagging, drawn 25 behind = 100 + (i + 25) = 125 + i
    final climb = [
      for (var i = 0; i < 100; i++)
        _bar(i, 100.0 + i, 101.0 + i, 99.0 + i, 100.0 + i, 10),
    ];
    final ic = hlIchimoku(climb);

    test('9, 26, 52, 26 on a climbing tape, by hand', () {
      expect(ic.conversion[7].isNaN, isTrue);
      expect(ic.conversion[8], moreOrLessEquals(104));
      expect(ic.conversion[60], moreOrLessEquals(156));
      expect(ic.base[24].isNaN, isTrue);
      expect(ic.base[25], moreOrLessEquals(112.5));
      expect(ic.base[99], moreOrLessEquals(186.5));
      // Span A's first value is computed at bar 25, drawn at bar 50.
      expect(ic.spanA[49].isNaN, isTrue);
      expect(ic.spanA[50], moreOrLessEquals(116.75));
      expect(ic.spanA[99], moreOrLessEquals(165.75));
      // Span B's first is computed at bar 51, drawn at bar 76.
      expect(ic.spanB[75].isNaN, isTrue);
      expect(ic.spanB[76], moreOrLessEquals(125.5));
      expect(ic.spanB[99], moreOrLessEquals(148.5));
      expect(ic.lagging[0], moreOrLessEquals(125));
      expect(ic.lagging[74], moreOrLessEquals(199));
      expect(ic.lagging[75].isNaN, isTrue);
    });

    test('the cloud is cut at the last bar: as long as the tape, never past',
        () {
      expect(ic.spanA, hasLength(climb.length));
      expect(ic.spanB, hasLength(climb.length));
      expect(ic.spanA.last.isFinite, isTrue);
    });

    test('2, 3, 4, 2 on eight bars, by hand', () {
      final bars = [
        _bar(0, 10, 11, 9, 10, 1),
        _bar(1, 10, 12, 10, 11, 1),
        _bar(2, 11, 13, 10, 12, 1),
        _bar(3, 12, 12, 9, 10, 1),
        _bar(4, 10, 11, 8, 9, 1),
        _bar(5, 9, 10, 8, 10, 1),
        _bar(6, 10, 12, 9, 11, 1),
        _bar(7, 11, 14, 11, 13, 1),
      ];
      final s =
          hlIchimoku(bars, conversion: 2, base: 3, spanB: 4, displacement: 2);
      void same(List<double> got, List<double?> want) {
        for (var i = 0; i < want.length; i++) {
          final w = want[i];
          if (w == null) {
            expect(got[i].isNaN, isTrue, reason: 'bar $i');
          } else {
            expect(got[i], moreOrLessEquals(w), reason: 'bar $i');
          }
        }
      }

      // Bar 2: conversion (13 + 10) / 2, base (13 + 9) / 2; drawn at bar 3,
      // span A is their average, 11.25.
      same(s.conversion, [null, 10.5, 11.5, 11, 10, 9.5, 10, 11.5]);
      same(s.base, [null, null, 11, 11, 10.5, 10, 10, 11]);
      same(s.spanA, [null, null, null, 11.25, 11, 10.25, 9.75, 10]);
      same(s.spanB, [null, null, null, null, 11, 10.5, 10.5, 10]);
      same(s.lagging, [11, 12, 10, 9, 10, 11, 13, null]);
    });

    test('9, 26, 52, 26 on the tape', () {
      final s = hlIchimoku(tape);
      _expectAt(s.conversion, [
        106.295739, 96.780810, 102.886181, 112.608352, 113.697833, //
        106.956005, 108.249648, 117.561608, 119.314386,
      ]);
      _expectAt(s.base, [
        null, 104.200145, 103.986947, 105.507355, 106.897756, //
        110.588139, 110.417048, 111.764833, 113.268691,
      ]);
      _expectAt(s.spanA, [
        null, null, null, null, null, //
        101.519634, 105.991249, 111.151909, 108.652199,
      ]);
      _expectAt(s.spanB, [
        null, null, null, null, null, null, null, null, 106.897756,
      ]);
      _expectAt(s.lagging, [
        116.845032, 103.300006, 100.657296, 119.780666, 123.880999, //
        null, null, null, null,
      ]);
    });
  });

  group('ADX', () {
    // Lengths 3 and 2 on eight bars, by hand. Bars 1 to 3:
    //   TR  2, 3, 3         +DM 1, 1, 0        −DM 0, 0, 1
    // The first RMAs, at bar 3: TR 8/3, +DM 2/3, −DM 1/3, so +DI 25, −DI
    // 12.5 and DX 12.5 / 37.5 = 1/3. Bar 4 has TR 3, +DM 0, −DM 1:
    //   TR (3 + 2 × 8/3) / 3 = 25/9, +DM 4/9, −DM 5/9
    // so +DI 16, −DI 20, DX 4 / 36 = 1/9, and the first ADX at bar 4 is
    // (1/3 + 1/9) / 2 = 2/9 = 22.22. The rest from the separate
    // implementation of TradingView's script.
    final bars = [
      _bar(0, 10, 11, 9, 10, 1),
      _bar(1, 10, 12, 10, 11, 1),
      _bar(2, 11, 13, 10, 12, 1),
      _bar(3, 12, 12, 9, 10, 1),
      _bar(4, 10, 11, 8, 9, 1),
      _bar(5, 9, 10, 8, 10, 1),
      _bar(6, 10, 12, 9, 11, 1),
      _bar(7, 11, 14, 11, 13, 1),
    ];

    test('3, 2 on eight bars, by hand', () {
      final s = hlAdx(bars, length: 3, smoothing: 2);
      expect(s.plusDi[2].isNaN, isTrue);
      expect(s.plusDi[3], moreOrLessEquals(25));
      expect(s.minusDi[3], moreOrLessEquals(12.5));
      expect(s.plusDi[4], moreOrLessEquals(16));
      expect(s.minusDi[4], moreOrLessEquals(20));
      expect(s.adx[3].isNaN, isTrue);
      expect(s.adx[4], moreOrLessEquals(200 / 9));
      expect(s.adx[5], closeTo(16.666667, 1e-5));
      expect(s.adx[6], closeTo(36.111111, 1e-5));
      expect(s.adx[7], closeTo(56.359649, 1e-5));
      expect(s.plusDi[7], closeTo(44.608567, 1e-5));
      expect(s.minusDi[7], closeTo(5.908419, 1e-5));
    });

    test('a straight climb is all +DI, ADX 100', () {
      // TR 2 and +DM 1 on every bar: +DI 50, −DI 0, DX 1.
      final climb = [
        for (var i = 0; i < 40; i++)
          _bar(i, 100.0 + i, 101.0 + i, 99.0 + i, 100.0 + i, 1),
      ];
      final s = hlAdx(climb);
      expect(s.plusDi[13].isNaN, isTrue);
      expect(s.plusDi[14], moreOrLessEquals(50));
      expect(s.minusDi[14], moreOrLessEquals(0));
      expect(s.adx[26].isNaN, isTrue);
      expect(s.adx[27], moreOrLessEquals(100));
    });

    test('a bar with no range holds the DIs (fixnan), no division by zero',
        () {
      final flat = [for (var i = 0; i < 40; i++) _bar(i, 5, 5, 5, 5, 1)];
      final s = hlAdx(flat);
      for (final v in [...s.adx, ...s.plusDi, ...s.minusDi]) {
        expect(v.isInfinite, isFalse);
      }
    });

    test('14, 14 on the tape', () {
      final s = hlAdx(tape);
      _expectAt(s.adx, [
        null, null, 22.595840, 35.086988, 35.036755, //
        28.597597, 26.972067, 37.273278, 36.563688,
      ]);
      _expectAt(s.plusDi, [
        20.385144, 14.693857, 38.514805, 38.032393, 23.594199, //
        17.394778, 36.899329, 37.318693, 22.756357,
      ]);
      _expectAt(s.minusDi, [
        26.640611, 29.723427, 14.267142, 9.490090, 28.957455, //
        27.689345, 16.005433, 10.781973, 29.125687,
      ]);
    });
  });

  group('pivot points', () {
    test('standard, from high 110, low 90, close 105, by hand', () {
      // P = (110 + 90 + 105) / 3 = 305 / 3
      //   R1 = 2P − L        S1 = 2P − H
      //   R2 = P + (H − L)   S2 = P − (H − L)
      //   R3 = 2P + H − 2L   S3 = 2P − (2H − L)
      // TradingView's Pivot Points Standard, type Traditional.
      final l = HlPivotLevels.of(110, 90, 105);
      expect(l.p, moreOrLessEquals(101.666667, epsilon: 1e-5));
      expect(l.r1, moreOrLessEquals(113.333333, epsilon: 1e-5));
      expect(l.s1, moreOrLessEquals(93.333333, epsilon: 1e-5));
      expect(l.r2, moreOrLessEquals(121.666667, epsilon: 1e-5));
      expect(l.s2, moreOrLessEquals(81.666667, epsilon: 1e-5));
      expect(l.r3, moreOrLessEquals(133.333333, epsilon: 1e-5));
      expect(l.s3, moreOrLessEquals(73.333333, epsilon: 1e-5));
      // The textbook's other way to write R3 and S3.
      expect(l.r3, moreOrLessEquals(110 + 2 * (l.p - 90)));
      expect(l.s3, moreOrLessEquals(90 - 2 * (110 - l.p)));
    });

    final dayOne = DateTime.utc(2026, 10, 1);
    HyperliquidCandle day(int d, double h, double l, double c) => _bar(
        d, c, h, l, c, 1,
        step: const Duration(days: 1), start: dayOne);

    test('each UTC day draws the day before\'s levels, flat, not joined', () {
      final hourly = [
        for (var i = 0; i < 48; i++)
          _bar(i, 100, 101, 99, 100, 1, start: DateTime.utc(2026, 10, 2)),
      ];
      final d = hlDailyPivots(hourly, [
        day(0, 110, 90, 105),
        day(1, 120, 100, 110),
        day(2, 130, 110, 120),
      ]);
      // 2 October: from 1 October's bar, day 0. 3 October: from day 1.
      expect(d.p[0], moreOrLessEquals(305 / 3));
      expect(d.p[23], moreOrLessEquals(305 / 3));
      expect(d.p[24].isNaN, isTrue, reason: 'the days never join');
      expect(d.p[25], moreOrLessEquals(110));
      expect(d.r1[47], moreOrLessEquals(2 * 110 - 100));
    });

    test('a day with no daily candle yet has no levels', () {
      final hourly = [
        for (var i = 0; i < 4; i++)
          _bar(i, 100, 101, 99, 100, 1, start: dayOne),
      ];
      final d = hlDailyPivots(hourly, [day(0, 110, 90, 105)]);
      expect(d.p.where((v) => v.isFinite), isEmpty);
      expect(hlDailyPivots(hourly, const []).p.where((v) => v.isFinite),
          isEmpty);
    });

    test('a thin market: the last daily candle before the day', () {
      final hourly = [
        _bar(0, 100, 101, 99, 100, 1, start: DateTime.utc(2026, 10, 5)),
        _bar(1, 100, 101, 99, 100, 1, start: DateTime.utc(2026, 10, 5)),
      ];
      final d = hlDailyPivots(hourly, [day(0, 110, 90, 105), day(1, 120, 100, 110)]);
      expect(d.p[1], moreOrLessEquals(110));
    });

    test('daily and weekly bars: the newest day\'s levels on the newest bars',
        () {
      final daily = [
        for (var i = 0; i < 30; i++) day(i, 110.0 + i, 90.0 + i, 100.0 + i),
      ];
      final d = hlDailyPivots(daily, daily);
      final at = daily.length - 2; // the candle before today's
      final want =
          HlPivotLevels.of(daily[at].high, daily[at].low, daily[at].close);
      expect(d.p.where((v) => v.isFinite), hasLength(kHlPivotLongBarSpan));
      expect(d.p.last, moreOrLessEquals(want.p));
      expect(d.r3.last, moreOrLessEquals(want.r3));
      expect(d.p[daily.length - kHlPivotLongBarSpan - 1].isNaN, isTrue);
      expect(d.p[daily.length - kHlPivotLongBarSpan].isFinite, isTrue);

      final weekly = [
        // The last one still open past the newest daily candle.
        for (var i = 0; i < 5; i++)
          _bar(i, 100, 110, 90, 100, 1,
              step: const Duration(days: 7), start: dayOne),
      ];
      final w = hlDailyPivots(weekly, daily);
      expect(w.p.last, moreOrLessEquals(want.p));
      expect(w.p.where((v) => v.isFinite), hasLength(5));
    });

    test('a preview\'s days come from the tape\'s own bars', () {
      final hourly = [
        for (var i = 0; i < 30; i++)
          _bar(i, 100, 100.0 + i, 90.0 - i, 95.0 + i, 2),
      ];
      final days = hlDailyFromBars(hourly);
      expect(days, hasLength(2));
      expect(days.first.high, 123);
      expect(days.first.low, 67);
      expect(days.first.close, 118);
      expect(days.first.volume, 48);
    });
  });

  group('the computed frame', () {
    const up = Color(0xFF00AA00), down = Color(0xFFAA0000);
    final computer = HlIndicatorComputer();

    test('Ichimoku carries its cloud through a slice, Pivots their names', () {
      final daily = hlDailyFromBars(tape);
      final frame = computer
          .compute(tape, ['ichi', 'pp', 'adx'], const {},
              up: up, down: down, daily: daily)
          .slice(60, 80);
      final ichi = frame.price.first;
      expect(ichi.title, 'Ichimoku 9 26 52 26');
      expect(ichi.lines, hasLength(5));
      expect(frame.cloud, isNotNull);
      expect(frame.cloud!.spanA, hasLength(20));
      expect(frame.cloud!.spanA.first, moreOrLessEquals(hlIchimoku(tape).spanA[60]));
      expect(frame.levelLabels.map((l) => l.label),
          ['P', 'R1', 'R2', 'R3', 'S1', 'S2', 'S3']);
      expect(frame.price.last.valuesAt(null), hasLength(1));
      expect(frame.panes.single.title, 'ADX 14 14');
      expect(frame.panes.single.lines, hasLength(3));
    });

    test('new daily candles recompute Pivots alone', () {
      final c = HlIndicatorComputer();
      final daily = hlDailyFromBars(tape);
      final a = c.compute(tape, ['ichi', 'pp'], const {},
          up: up, down: down, daily: daily);
      final b = c.compute(tape, ['ichi', 'pp'], const {},
          up: up, down: down, daily: [...daily]);
      expect(identical(a.price.first, b.price.first), isTrue);
      expect(identical(a.price.last, b.price.last), isFalse);
    });

    test('a 1W tape with all fifteen on computes in one tick\'s time', () {
      // 500 weekly bars, as a year-long pan could hold: the whole catalog
      // at once, more than the limits ever allow.
      final weekly = [
        for (var i = 0; i < 500; i++)
          _bar(
              i,
              1000 + 200 * math.sin(i / 11),
              1040 + 200 * math.sin(i / 11),
              960 + 200 * math.sin(i / 11),
              1000 + 200 * math.sin((i + 1) / 11),
              100,
              step: const Duration(days: 7)),
      ];
      final sw = Stopwatch()..start();
      final frame = HlIndicatorComputer().compute(
          weekly, kHlIndicatorCatalog.map((s) => s.key), const {},
          up: up, down: down, daily: hlDailyFromBars(weekly));
      sw.stop();
      expect(frame.price, isNotEmpty);
      // A debug-mode test VM; the point is the order of magnitude.
      expect(sw.elapsedMilliseconds, lessThan(100),
          reason: 'took ${sw.elapsedMilliseconds} ms');
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
