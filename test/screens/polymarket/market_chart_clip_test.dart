// A Predictions chart's lines never leave the plot: the curve through
// the points stays between them (Fritsch-Carlson limiter in
// kuteMonotonePath), the scale leaves room above the top line and under
// the bottom one for the end dots and the pulse (polyChartEdgeRoom), a
// one-off live tick from a thin book is not drawn
// (polyLiveTickIsOutlier, LiveChartNotifier), and an event's chart of
// three or more outcomes is a little taller (polyChartHeightFor).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/screens/polymarket/components/market_chart.dart';
import 'package:kute/screens/shared/charts/kute_chart_core.dart';

const _min = 60000;

/// Price → y in a plot [drawH] tall, as the chart maps it.
double _y(double v, ({double minY, double maxY}) d, double drawH) =>
    drawH * (1 - (v - d.minY) / (d.maxY - d.minY));

class _Feed extends LivePriceNotifier {
  @override
  LivePriceState build() => const LivePriceState();
  void push(LivePriceState s) => state = s;
  @override
  void acquire() {}
  @override
  void release() {}
  @override
  void pause() {}
  @override
  void resume() {}
  @override
  void subscribeTokens(List<String> tokenIds) {}
  @override
  void addTokens(List<String> tokenIds, {bool pin = true}) {}
  @override
  void registerCardTokens(List<String> tokenIds) {}
  @override
  void unregisterCardTokens(List<String> tokenIds) {}
  @override
  void removeTokens(List<String> tokenIds) {}
  @override
  void unsubscribeAll() {}
}

void main() {
  group('the curve through a line\'s points', () {
    test('a live tick seconds after an hour-old point does not throw the '
        'curve past either of them', () {
      // An hour of nearly flat history, then two ticks fifteen seconds
      // apart that drop forty points: the shape that shot out of the plot.
      final pts = [
        const Offset(0, 100),
        const Offset(300, 98),
        const Offset(600, 96),
        const Offset(601, 60),
        const Offset(602, 20),
      ];
      final b = kuteMonotonePath(pts).getBounds();
      expect(b.top, greaterThanOrEqualTo(20 - 1e-6));
      expect(b.bottom, lessThanOrEqualTo(100 + 1e-6));
    });

    test('points on one time (equal x) draw a straight step', () {
      final b = kuteMonotonePath(const [
        Offset(0, 50),
        Offset(100, 50),
        Offset(100, 10),
        Offset(200, 10),
      ]).getBounds();
      expect(b.top, greaterThanOrEqualTo(10 - 1e-6));
      expect(b.bottom, lessThanOrEqualTo(50 + 1e-6));
    });
  });

  group('room for the end dots and the pulse', () {
    const drawH = 214.0;
    const room = kPolyChartEndRoom / drawH;

    KuteYDomain fit(double lo, double hi) =>
        polyChartEdgeRoom(polyChartDomain(lo, hi), lo, hi,
            top: room, bottom: room);

    test('a line whose last live tick jumps to the top stays inside the '
        'plot, with the dot\'s room above it', () {
      // 40-64 jumps from 78% to 99.9%; a long shot sits at 0.1%.
      final d = fit(0.001, 0.999);
      expect(_y(0.999, d, drawH), greaterThanOrEqualTo(kPolyChartEndRoom - 1e-6));
      expect(_y(0.001, d, drawH),
          lessThanOrEqualTo(drawH - kPolyChartEndRoom + 1e-6));
    });

    test('a line whose last live tick drops to the bottom stays inside the '
        'plot, with the dot\'s room under it', () {
      final d = fit(0.0, 0.45);
      expect(_y(0.0, d, drawH),
          lessThanOrEqualTo(drawH - kPolyChartEndRoom + 1e-6));
      expect(_y(0.45, d, drawH), greaterThan(0));
    });

    test('the whole drawn line, live end included, is inside the plot', () {
      final prices = [0.60, 0.70, 0.78, 0.999, 0.999];
      final xs = [0.0, 120.0, 240.0, 240.5, 241.0];
      final lo = prices.reduce((a, b) => a < b ? a : b);
      final hi = prices.reduce((a, b) => a > b ? a : b);
      final d = fit(lo, hi);
      final b = kuteMonotonePath([
        for (var i = 0; i < prices.length; i++)
          Offset(xs[i], _y(prices[i], d, drawH)),
      ]).getBounds();
      expect(b.top, greaterThanOrEqualTo(kPolyChartEndRoom - 1e-6));
      expect(b.bottom, lessThanOrEqualTo(drawH));
    });

    test('a scale that already leaves the room is left alone', () {
      final d = polyChartDomain(0.30, 0.60);
      expect(polyChartEdgeRoom(d, 0.30, 0.60, top: room, bottom: room), d);
    });

    test('a game\'s marker lane still wins at the top', () {
      const lane = 30 / drawH;
      final d = polyChartEdgeRoom(polyChartDomain(0.2, 0.98), 0.2, 0.98,
          top: lane, bottom: room);
      expect(_y(0.98, d, drawH), greaterThanOrEqualTo(30 - 1e-6));
      expect(_y(0.2, d, drawH), lessThanOrEqualTo(drawH - kPolyChartEndRoom));
    });
  });

  group('a one-off live tick', () {
    test('a jump that comes straight back is an outlier', () {
      expect(polyLiveTickIsOutlier(before: 0.50, tick: 0.99, after: 0.51),
          isTrue);
      expect(polyLiveTickIsOutlier(before: 0.20, tick: 0.01, after: 0.20),
          isTrue);
    });

    test('a move that stays, a small wobble or the first tick is kept', () {
      expect(polyLiveTickIsOutlier(before: 0.50, tick: 0.90, after: 0.91),
          isFalse);
      expect(polyLiveTickIsOutlier(before: 0.50, tick: 0.55, after: 0.50),
          isFalse);
      expect(polyLiveTickIsOutlier(before: null, tick: 0.99, after: 0.50),
          isFalse);
    });

    test('a thin book\'s outlier tick is not drawn; the list\'s price is',
        () async {
      const key = (tokenId: 'tok', interval: '1d');
      final t0 = DateTime.now().millisecondsSinceEpoch - 10 * _min;
      final history = [
        for (var i = 0; i < 5; i++)
          PolymarketPricePoint(
              timestamp: DateTime.fromMillisecondsSinceEpoch(t0 + i * _min),
              price: 0.50),
      ];
      final c = ProviderContainer(overrides: [
        livePriceProvider.overrideWith(_Feed.new),
        polymarketMarketHistoryProvider
            .overrideWith((ref, arg) async => history),
      ]);
      addTearDown(c.dispose);
      final sub = c.listen(polymarketLiveChartProvider(key), (_, __) {});
      addTearDown(sub.close);
      await c.read(polymarketMarketHistoryProvider(key).future);
      final feed = c.read(livePriceProvider.notifier) as _Feed;
      final t1 = t0 + 6 * _min;
      for (final (i, p) in [0.50, 0.99, 0.51].indexed) {
        feed.push(LivePriceState(
            prices: {'tok': p},
            updatedAtMs: {'tok': t1 + i * 2000},
            live: true));
        c.read(polymarketLiveChartProvider(key));
      }
      final drawn = c.read(polymarketLiveChartProvider(key));
      expect(drawn.map((p) => p.price), isNot(contains(0.99)));
      expect(drawn.last.price, 0.51);
    });

    test('a wide book with no trade (unpriced) draws no tick', () async {
      const key = (tokenId: 'tok', interval: '1d');
      final t0 = DateTime.now().millisecondsSinceEpoch - 10 * _min;
      final history = [
        PolymarketPricePoint(
            timestamp: DateTime.fromMillisecondsSinceEpoch(t0), price: 0.30),
      ];
      final c = ProviderContainer(overrides: [
        livePriceProvider.overrideWith(_Feed.new),
        polymarketMarketHistoryProvider
            .overrideWith((ref, arg) async => history),
      ]);
      addTearDown(c.dispose);
      final sub = c.listen(polymarketLiveChartProvider(key), (_, __) {});
      addTearDown(sub.close);
      await c.read(polymarketMarketHistoryProvider(key).future);
      (c.read(livePriceProvider.notifier) as _Feed).push(LivePriceState(
          prices: const {'tok': 0.37},
          updatedAtMs: {'tok': t0 + _min},
          live: true,
          unpriced: const {'tok'}));
      expect(c.read(polymarketLiveChartProvider(key)).length, 1);
    });
  });

  group('the chart\'s height', () {
    test('three or more outcomes get a fifth more; one or two keep theirs',
        () {
      expect(polyChartHeightFor(1), 220);
      expect(polyChartHeightFor(2), 220);
      expect(polyChartHeightFor(3), 260);
      expect(polyChartHeightFor(6), 260);
    });
  });
}
