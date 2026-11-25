// The Investing chart's Funding pane: Hyperliquid's hourly settlements
// fitted to the chart's bars (hl_chart_indicator_series.dart
// hlFundingPerBar / hlFundingCumulative), the pane in the indicator frame,
// the session history's paging (hyperliquid_funding_history_provider.dart)
// and the client's pages (HyperliquidModel.getFundingHistoryRange), all
// against hand-computed values.

import 'dart:convert';

import 'package:flutter/painting.dart' show Color;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/providers/hyperliquid_funding_history_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_funding_pane.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_indicator_catalog.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_indicator_frame.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_indicator_series.dart';

const _h = 3600 * 1000;
final _t0 = DateTime.utc(2026, 11, 1).millisecondsSinceEpoch;

/// Bars of [minutes] from [_t0], closing a millisecond short of the next
/// open, as the venue's candles do.
List<HyperliquidCandle> _bars(int count, int minutes, {int from = 0}) => [
      for (var i = 0; i < count; i++)
        HyperliquidCandle(
          openTime: DateTime.fromMillisecondsSinceEpoch(
              _t0 + from + i * minutes * 60000,
              isUtc: true),
          closeTime: DateTime.fromMillisecondsSinceEpoch(
              _t0 + from + (i + 1) * minutes * 60000 - 1,
              isUtc: true),
          open: 1,
          high: 1,
          low: 1,
          close: 1,
          volume: 1,
        ),
    ];

/// Settlement k (1-based) at the end of hour k after [_t0], a few ms late
/// as the venue's are.
({int timeMs, double rate}) _s(int k, double rate) =>
    (timeMs: _t0 + k * _h + 37, rate: rate);

void main() {
  group('funding per bar', () {
    test('1h bars: each bar is the hour that ends at its close', () {
      final f = hlFundingPerBar(_bars(3, 60), [
        _s(1, 0.0001),
        _s(2, -0.00005),
        _s(3, 0.00002),
      ]);
      expect(f.rate, [0.0001, -0.00005, 0.00002]);
      expect(f.settled, f.rate);
    });

    test('4h bars sum their four hours; a missing hour is left out', () {
      final hours = [
        for (var k = 1; k <= 8; k++)
          if (k != 6) _s(k, k.isEven ? 0.00002 : 0.00001),
      ];
      final f = hlFundingPerBar(_bars(2, 240), hours);
      // 0.00001 + 0.00002 + 0.00001 + 0.00002
      expect(f.rate[0], closeTo(0.00006, 1e-12));
      // hours 5, 7, 8 (6 is missing): 0.00001 + 0.00001 + 0.00002
      expect(f.rate[1], closeTo(0.00004, 1e-12));
    });

    test('1D bars sum the day\'s 24 settlements, sign kept', () {
      final hours = [
        for (var k = 1; k <= 48; k++) _s(k, k <= 24 ? 0.0000125 : -0.00001),
      ];
      final f = hlFundingPerBar(_bars(2, 1440), hours);
      expect(f.rate[0], closeTo(0.0003, 1e-12)); // longs paid 0.03 %
      expect(f.rate[1], closeTo(-0.00024, 1e-12)); // shorts paid 0.024 %
    });

    test('under an hour: the hour\'s rate held across its bars, settled once',
        () {
      // 15m bars over two hours.
      final f = hlFundingPerBar(_bars(8, 15), [
        _s(1, 0.0001),
        _s(2, -0.0002),
      ]);
      expect(f.rate, [
        0.0001, 0.0001, 0.0001, 0.0001, //
        -0.0002, -0.0002, -0.0002, -0.0002,
      ]);
      expect(f.settled, [0, 0, 0, 0.0001, 0, 0, 0, -0.0002]);
    });

    test('a bar with none of its hours is a gap, never zero', () {
      final f = hlFundingPerBar(_bars(3, 60), [_s(1, 0.0001), _s(3, 0.0003)]);
      expect(f.rate[0], 0.0001);
      expect(f.rate[1].isNaN, isTrue);
      expect(f.rate[2], 0.0003);
      final sub = hlFundingPerBar(_bars(4, 30), [_s(2, 0.0002)]);
      expect(sub.rate[0].isNaN, isTrue);
      expect(sub.settled[0].isNaN, isTrue);
      expect(sub.rate.sublist(2), [0.0002, 0.0002]);
    });

    test('no history: every bar a gap', () {
      final f = hlFundingPerBar(_bars(3, 60), const []);
      expect(f.rate.every((v) => v.isNaN), isTrue);
    });
  });

  group('running sum', () {
    test('sums the bars on screen from the first, carrying over a gap', () {
      final c = hlFundingCumulative([0.0001, -0.00005, double.nan, 0.0002]);
      expect(c[0], closeTo(0.0001, 1e-12));
      expect(c[1], closeTo(0.00005, 1e-12));
      expect(c[2].isNaN, isTrue);
      expect(c[3], closeTo(0.00025, 1e-12));
    });

    test('is the same whatever the interval', () {
      final hours = [for (var k = 1; k <= 24; k++) _s(k, 0.00001 * (k % 5 - 2))];
      double last(List<double> v) => v.lastWhere((e) => e.isFinite);
      final hourly = last(hlFundingCumulative(
          hlFundingPerBar(_bars(24, 60), hours).settled));
      final fourHourly = last(hlFundingCumulative(
          hlFundingPerBar(_bars(6, 240), hours).settled));
      final quarter = last(hlFundingCumulative(
          hlFundingPerBar(_bars(96, 15), hours).settled));
      final total = hours.fold<double>(0, (a, p) => a + p.rate);
      expect(hourly, closeTo(total, 1e-12));
      expect(fourHourly, closeTo(total, 1e-12));
      expect(quarter, closeTo(total, 1e-12));
    });
  });

  group('the pane in the frame', () {
    const up = Color(0xFF00FF00), down = Color(0xFFFF0000);
    test('funding goes into the panes with its sums; none without history',
        () {
      final bars = _bars(4, 60);
      final frame = HlIndicatorComputer().compute(
        bars,
        const ['rsi', kHlFundingKey],
        const {},
        up: up,
        down: down,
        funding: [_s(1, 0.0001), _s(2, 0.0002)],
      );
      expect(frame.panes.map((p) => p.key), ['rsi', kHlFundingKey]);
      final fund = frame.panes.last;
      expect(fund.histogram!.take(2), [0.0001, 0.0002]);
      final cut = fund.slice(1, 3);
      expect(cut.settled!.first, 0.0002);
      // A spot market's chart hands no history: no pane.
      final spot = HlIndicatorComputer().compute(
          bars, const [kHlFundingKey], const {},
          up: up, down: down);
      expect(spot.panes, isEmpty);
    });

    test('Funding counts against the two panes', () {
      final r = hlToggleIndicator(['rsi', 'macd'], kHlFundingKey);
      expect(r.next, ['macd', kHlFundingKey]);
      expect(r.replaced, 'rsi');
      expect(hlIndSpec(kHlFundingKey)!.perpsOnly, isTrue);
    });

    test('labels', () {
      expect(hlFundingPeriodLabel(15), '1h');
      expect(hlFundingPeriodLabel(240), '4h');
      expect(hlFundingPeriodLabel(1440), '1D');
      expect(hlFundingPct(0.000013), '+0.0013%');
      expect(hlFundingPct(-0.0031), '−0.310%');
      expect(hlFundingPct(0.0125), '+1.25%');
      expect(hlBarMinutes(_bars(2, 240)), 240);
    });
  });

  group('session history', () {
    late ProviderContainer container;
    late List<(int, int)> asked;
    var fail = false;
    final now = DateTime.utc(2026, 11, 25, 12, 20);
    final nowMs = now.millisecondsSinceEpoch;
    final page = kHlFundingPage.inMilliseconds;

    HlFundingHistoryNotifier notifier() =>
        container.read(hlFundingHistoryProvider('xyz:XYZ100').notifier);
    HlFundingHistory state() =>
        container.read(hlFundingHistoryProvider('xyz:XYZ100'));

    setUp(() {
      asked = [];
      fail = false;
      container = ProviderContainer(overrides: [
        hlFundingFetchProvider.overrideWithValue((coin, start, end) async {
          expect(coin, 'xyz:XYZ100'); // a builder market, prefixed
          asked.add((start, end));
          if (fail) throw Exception('down');
          // One settlement on every hour in the range.
          final first = (start ~/ _h + 1) * _h;
          return [
            for (var t = first; t <= end; t += _h)
              (timeMs: t, rate: 0.00001),
          ];
        }),
      ]);
      notifier().now = () => now;
    });
    tearDown(() => container.dispose());

    Future<void> flush() async {
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('opens on one page back from now, or to the first bar asked', () async {
      notifier().want(nowMs - 2 * _h);
      await flush();
      expect(asked, [(nowMs - page, nowMs)]);
      expect(state().load, HlFundingLoad.ready);
      expect(state().points, hasLength(480));
    });

    test('panning back reads whole older pages, never past the limit',
        () async {
      notifier().want(nowMs - 2 * _h);
      await flush();
      // A little further back than read: a whole page more.
      notifier().want(nowMs - page - 3 * _h);
      await flush();
      expect(asked.last, (nowMs - 2 * page, nowMs - page - 1));
      // Within what is read: nothing.
      notifier().want(nowMs - page);
      await flush();
      expect(asked, hasLength(2));
      // A year back: only to the lookback.
      notifier().want(nowMs - const Duration(days: 365).inMilliseconds);
      await flush();
      final floor = nowMs - kHlFundingLookback.inMilliseconds;
      expect(asked.last.$1, floor);
      expect(state().fromMs, floor);
      // Every point once, oldest first.
      final times = [for (final p in state().points) p.timeMs];
      expect(times.toSet(), hasLength(times.length));
      expect([...times]..sort(), times);
    });

    test('the newest hour is read again once a new one settles', () async {
      notifier().want(nowMs - _h);
      await flush();
      notifier().want(nowMs - _h);
      await flush();
      expect(asked, hasLength(1)); // same hour: nothing
      final later = now.add(const Duration(minutes: 45)); // 13:05
      notifier().now = () => later;
      notifier().want(nowMs - _h);
      await flush();
      expect(asked.last, (nowMs + 1, later.millisecondsSinceEpoch));
      expect(state().points.last.timeMs,
          DateTime.utc(2026, 11, 25, 13).millisecondsSinceEpoch);
    });

    test('a failed first read is an error, retried after a pause', () async {
      fail = true;
      notifier().want(nowMs - _h);
      await flush();
      expect(state().load, HlFundingLoad.error);
      fail = false;
      notifier().want(nowMs - _h);
      await flush();
      expect(asked, hasLength(1)); // still pausing
      notifier().now = () => now.add(kHlFundingRetry);
      notifier().want(nowMs - _h);
      await flush();
      expect(state().load, HlFundingLoad.ready);
    });
  });

  group('client pages', () {
    test('reads on from the last time while an answer is full', () async {
      final bodies = <Map<String, dynamic>>[];
      final model = HyperliquidModel(
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          bodies.add(body);
          final start = body['startTime'] as int;
          final n = bodies.length == 1 ? 500 : 20;
          return http.Response(
            jsonEncode([
              for (var i = 0; i < n; i++)
                {
                  'coin': body['coin'],
                  'fundingRate': '-0.00001250',
                  'premium': '0',
                  'time': start + i * _h,
                },
            ]),
            200,
          );
        }),
      );
      final points = await model.getFundingHistoryRange(
          coin: 'xyz:XYZ100', startMs: 1000, endMs: 1000 + 600 * _h);
      expect(points, hasLength(520));
      expect(bodies, hasLength(2));
      expect(bodies.first['type'], 'fundingHistory');
      expect(bodies.first['coin'], 'xyz:XYZ100');
      expect(bodies[1]['startTime'], 1000 + 499 * _h + 1);
      expect(points.first.rate, -0.0000125);
    });

    test('throws on a failed request', () async {
      final model = HyperliquidModel(
          client: MockClient((_) async => http.Response('busy', 429)));
      expect(
          model.getFundingHistoryRange(coin: 'BTC', startMs: 0, endMs: _h),
          throwsA(isA<HyperliquidInfoException>()));
    });
  });
}
