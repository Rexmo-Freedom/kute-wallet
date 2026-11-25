// The chart's log price axis: one mapping for the plot, the drawings, the
// markers and the crosshair, so everything stays in register; a value at
// or under zero has no place on it and never bends the scale.

import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/hyperliquid_market.dart' show HlFill;
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/screens/hyperliquid/components/hl_charts.dart';
import 'package:kute/screens/shared/charts/kute_chart_indicators.dart';

const _t0 = 1700000000000;
const _minute = 60000;

List<HyperliquidCandle> _tape() => [
      for (var i = 0; i < 10; i++)
        HyperliquidCandle(
          openTime: DateTime.fromMillisecondsSinceEpoch(_t0 + i * _minute),
          closeTime:
              DateTime.fromMillisecondsSinceEpoch(_t0 + (i + 1) * _minute),
          open: 100.0 * (i + 1),
          high: 110.0 * (i + 1),
          low: 90.0 * (i + 1),
          close: 100.0 * (i + 1),
          volume: 10,
        ),
    ];

HlFill _fill(int bar, double px, {bool buy = true}) => HlFill(
      coin: 'BTC',
      px: px,
      sz: 1,
      side: buy ? 'B' : 'A',
      time: _t0 + bar * _minute + 1000,
      closedPnl: 0,
      fee: 0,
      feeToken: 'USDC',
      oid: 1,
      hash: '$bar',
      dir: '',
      cloid: null,
      tradeId: '$bar',
    );

void main() {
  group('the log mapping', () {
    final geom = KuteLogDrawingGeometry(
      timesMs: const [0, 1],
      width: 100,
      priceH: 300,
      loP: math.log(100),
      rangeP: math.log(1000) - math.log(100),
      bucketMs: 1,
    );

    test('a price round-trips through y', () {
      for (final p in [100.0, 137.5, 316.227766, 999.0, 1000.0, 1e-3, 1e7]) {
        expect(geom.priceForY(geom.yForPrice(p)),
            moreOrLessEquals(p, epsilon: p * 1e-9));
      }
    });

    test('equal ratios take equal heights: a decade across 300 px', () {
      expect(geom.yForPrice(1000), moreOrLessEquals(0));
      expect(geom.yForPrice(100), moreOrLessEquals(300));
      // sqrt(100 × 1000) sits halfway.
      expect(geom.yForPrice(316.22776601683796), moreOrLessEquals(150));
      expect(geom.yForPrice(200) - geom.yForPrice(400),
          moreOrLessEquals(geom.yForPrice(400) - geom.yForPrice(800)));
    });

    test('a non-positive price stays finite, far below the plot', () {
      for (final p in [0.0, -5.0]) {
        final y = geom.yForPrice(p);
        expect(y.isFinite, isTrue);
        expect(y, greaterThan(geom.priceH));
      }
      expect(kuteLogPrice(0), kuteLogPrice(-1));
    });
  });

  group('in register', () {
    const size = Size(300, 200);

    test('a fill sits on the same log mapping as the bars', () {
      final tape = _tape();
      final domain = (lo: math.log(90.0), hi: math.log(1100.0), log: true);
      final markers = hlResolveFillMarkers(
        candles: tape,
        fills: [_fill(4, 500)],
        size: size,
        renderAsLine: false,
        showVolume: false,
        logScale: true,
        domain: domain,
      );
      expect(markers, hasLength(1));
      final expected = size.height *
          (1 - (math.log(500) - domain.lo) / (domain.hi - domain.lo));
      expect(markers.single.dot.dy, moreOrLessEquals(expected));
      expect(markers.single.dot.dx,
          moreOrLessEquals(4.5 * size.width / tape.length));
    });

    test('with a linear domain the same fill maps linearly', () {
      final tape = _tape();
      const domain = (lo: 90.0, hi: 1100.0, log: false);
      final markers = hlResolveFillMarkers(
        candles: tape,
        fills: [_fill(4, 500)],
        size: size,
        renderAsLine: false,
        showVolume: false,
        domain: domain,
      );
      final expected =
          size.height * (1 - (500 - domain.lo) / (domain.hi - domain.lo));
      expect(markers.single.dot.dy, moreOrLessEquals(expected));
    });

    test('with no domain, a tape holding a non-positive low stays linear', () {
      final bad = [
        HyperliquidCandle(
          openTime: DateTime.fromMillisecondsSinceEpoch(_t0),
          closeTime: DateTime.fromMillisecondsSinceEpoch(_t0 + _minute),
          open: 100,
          high: 110,
          low: 0,
          close: 100,
          volume: 1,
        ),
        ..._tape().skip(1),
      ];
      final markers = hlResolveFillMarkers(
        candles: bad,
        fills: [_fill(4, 500)],
        size: size,
        renderAsLine: false,
        showVolume: false,
        logScale: true,
      );
      expect(markers.single.dot.dy.isFinite, isTrue);
    });
  });
}
