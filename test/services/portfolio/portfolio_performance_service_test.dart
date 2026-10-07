import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/portfolio_performance.dart';
import 'package:kute/services/portfolio/portfolio_performance_service.dart';

const address = '0x1111111111111111111111111111111111111111';
Object hl(Object points) => [
      [
        'allTime',
        {
          'pnlHistory': points,
          'accountValueHistory': [
            [1700000000000, '9000'],
            [1700000010000, '100000']
          ]
        }
      ]
    ];
Object pm(List<Object> points,
        {String wallet = address, String interval = 'max'}) =>
    {
      'data': {
        'proxy_wallet': wallet,
        'interval': interval,
        'fidelity': '1d',
        'points': points
      }
    };

void main() {
  test('Hyperliquid uses published cumulative PnL, never deposited equity', () {
    final data = parseHyperliquidPerformance(hl([
      [1700000010000, '-5.5'],
      [1700000000000, '12.5']
    ]));
    expect(data.points.map((p) => p.pnlUsd), [12.5, -5.5]);
    expect(data.points.first.timestamp,
        DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true));
    expect(data.totalPnlUsd, -5.5);
    expect(data.realizedPnlUsd, isNull);
    expect(data.openPnlUsd, isNull);
  });

  test(
      'Polymarket preserves economic PnL and optional components independently',
      () {
    final data = parsePolymarketPerformance(
        pm([
          {
            'timestamp': 1700000010,
            'economic_pnl': 12.25,
            'realized_pnl': 4.5,
            'unrealized_pnl': 5.5,
            'deposits': 9000,
            'cashflow_net': 8800
          },
          {'timestamp': 1700000000, 'economic_pnl': -2},
        ]),
        expectedAddress: address);
    expect(data.points.map((p) => p.pnlUsd), [-2, 12.25]);
    expect(data.totalPnlUsd, 12.25); // Other income is included by the source.
    expect(data.realizedPnlUsd, 4.5);
    expect(data.openPnlUsd, 5.5);
    expect(data.asOf,
        DateTime.fromMillisecondsSinceEpoch(1700000010000, isUtc: true));
    expect(data.points.first.realizedPnlUsd, isNull);
  });

  test(
      'identical duplicate samples are deduplicated without inventing endpoints',
      () {
    final data = parseHyperliquidPerformance(hl([
      [1700000010000, '7'],
      [1700000010000, 7]
    ]));
    expect(data.points, hasLength(1));
    expect(data.totalPnlUsd, 7);
  });

  test('conflicting observations and nonfinite/missing values fail', () {
    expect(
        () => parseHyperliquidPerformance(hl([
              [1700000010000, 5],
              [1700000010000, 6]
            ])),
        throwsFormatException);
    for (final bad in [null, 'NaN', 'Infinity', {}, true]) {
      expect(
          () => parseHyperliquidPerformance(hl([
                [1700000010000, bad]
              ])),
          throwsFormatException);
      expect(
          () => parsePolymarketPerformance(
              pm([
                {'timestamp': 1700000010, 'economic_pnl': bad}
              ]),
              expectedAddress: address),
          throwsFormatException);
    }
    expect(
        () => parseHyperliquidPerformance(hl([
              [0, 5]
            ])),
        throwsFormatException);
  });

  test('missing all-time series cannot be relabeled all time', () {
    expect(
        () => parseHyperliquidPerformance([
              [
                'day',
                {'pnlHistory': []}
              ]
            ]),
        throwsFormatException);
    expect(
        () => parsePolymarketPerformance(pm([], interval: '1d'),
            expectedAddress: address),
        throwsFormatException);
  });

  test('unknown and empty histories have no fabricated zero metrics', () {
    for (final data in [
      parseHyperliquidPerformance([]),
      parseHyperliquidPerformance(hl([])),
      parsePolymarketPerformance({'data': null}, expectedAddress: address),
      parsePolymarketPerformance(pm([]), expectedAddress: address)
    ]) {
      expect(data.points, isEmpty);
      expect(data.totalPnlUsd, isNull);
      expect(data.asOf, isNull);
    }
  });

  test('Polymarket response must belong to the requested proxy', () {
    expect(
        () => parsePolymarketPerformance(
            pm([], wallet: '0x2222222222222222222222222222222222222222'),
            expectedAddress: address),
        throwsFormatException);
  });

  test('service requests official PnL endpoints and explicit full history',
      () async {
    final requests = <http.Request>[];
    final service =
        PortfolioPerformanceService(client: MockClient((request) async {
      requests.add(request);
      if (request.method == 'POST') {
        return http.Response(jsonEncode(hl([])), 200);
      }
      return http.Response(
          jsonEncode(request.url.path == '/v2/positions'
              ? {'data': [], 'pagination': {'has_more': false}}
              : pm([])),
          200);
    }));
    addTearDown(service.close);
    await service.hyperliquid(address);
    await service.polymarket(address);
    expect(
        jsonDecode(requests[0].body), {'type': 'portfolio', 'user': address});
    final pnl = requests.singleWhere((r) => r.url.path == '/v2/user-pnl');
    expect(pnl.url.queryParameters,
        {'user': address, 'interval': 'max', 'fidelity': '1d'});
    final positions = requests.where((r) => r.url.path == '/v2/positions');
    expect(positions.map((r) => r.url.queryParameters['status']).toSet(),
        {'OPEN', 'CLOSED'});
    for (final r in positions) {
      expect(r.url.queryParameters['user'], address);
      expect(r.url.queryParameters['sort_by'], 'TIMESTAMP');
    }
  });

  group('a recorded Predictions account', () {
    // Read from the public Data API on 2026-10-05 at 10:16 UTC and
    // anonymised. The P&L series' last point is the 00:00 UTC snapshot:
    // −2.45 realised. Two predictions closed that morning (+1.46 won and
    // claimed, −0.04 sold), so Polymarket's own positions add up to −1.03.
    final fixture = jsonDecode(File(
            'test/services/fixtures/polymarket_predictions_account.json')
        .readAsStringSync()) as Map<String, dynamic>;
    final now = DateTime.utc(2026, 10, 5, 10, 20);

    Future<PortfolioPerformance> load() async {
      final service =
          PortfolioPerformanceService(client: MockClient((request) async {
        final body = switch (request.url.path) {
          '/v2/user-pnl' => fixture['user_pnl'],
          '/v2/positions' => request.url.queryParameters['status'] == 'OPEN'
              ? fixture['open']
              : fixture['closed'],
          _ => throw StateError('unexpected ${request.url.path}'),
        };
        return http.Response(jsonEncode(body), 200);
      }));
      addTearDown(service.close);
      return service.polymarket(address);
    }

    test('the series alone is a day behind', () async {
      final data = await load();
      expect(data.totalPnlUsd, closeTo(-2.449352, 1e-9));
      expect(data.realizedPnlUsd, closeTo(-2.45007, 1e-9));
      expect(data.asOf, DateTime.utc(2026, 10, 5));
      expect(data.otherPnlUsd, closeTo(0, 1e-9));
      expect(data.predictions!.records, hasLength(6));
      expect(data.predictions!.complete, isTrue);
    });

    test('the current figures match the positions, today included',
        () async {
      final data = (await load()).withLivePredictions(const {}, at: now);
      expect(data.totalPnlUsd, closeTo(-1.0286, 1e-9));
      expect(data.realizedPnlUsd, closeTo(-1.0286, 1e-9));
      expect(data.openPnlUsd, 0);
      // The chart's last point is the headline.
      expect(data.points.last.pnlUsd, data.totalPnlUsd);
      expect(data.points.last.timestamp, now);
    });

    test('each range starts where the account stood when it began',
        () async {
      final data = (await load()).withLivePredictions(const {}, at: now);
      // 7D starts on 28 September at 10:20, after that day's 00:00
      // snapshot (+0.90) and before that afternoon's losses.
      final week = data.rangeView(const Duration(days: 7));
      expect(week.changeUsd, closeTo(-1.9327, 1e-4));
      expect(week.realizedChangeUsd, closeTo(-1.9327, 1e-4));
      expect(week.points.first.pnlUsd, closeTo(0.904134, 1e-9));
      expect(week.points.last.pnlUsd, data.totalPnlUsd);
      // The account is eleven days old: a month, three months and all time
      // are its whole history, from zero.
      for (final range in [
        const Duration(days: 30),
        const Duration(days: 90),
        null
      ]) {
        final view = data.rangeView(range);
        expect(view.points.first.pnlUsd, 0);
        expect(view.changeUsd, closeTo(-1.0286, 1e-9));
        expect(view.realizedChangeUsd, closeTo(-1.0286, 1e-9));
      }
    });

    test('range statistics count the predictions and what was put on them',
        () async {
      final book = (await load()).predictions!;
      // Each record keeps its market, for the category split.
      expect(book.records.map((r) => r.conditionId), contains('0xcondition1'));
      final all = book.statsSince(null)!;
      expect(all.count, 6);
      expect(all.stakedUsd, closeTo(16.4129, 1e-3));
      final week = book.statsSince(now.subtract(const Duration(days: 7)))!;
      expect(week.count, 4);
      expect(week.stakedUsd, closeTo(11.3436, 1e-3));
      final today = book.statsSince(DateTime.utc(2026, 10, 5, 10, 0))!;
      expect(today.count, 0);
    });
  });

  test('positions follow the cursor and say when the read was cut', () async {
    var pages = 0;
    Map<String, Object?> row(int i) => {
          'proxy_wallet': address,
          'token_id': 't$i',
          'current_size': 0,
          'total_size': 10,
          'avg_price': .5,
          'entry_cost_usdc': 0,
          'current_price': 1,
          'realized_pnl': 1,
          'unrealized_pnl': 0,
          'first_entry_at': 1790000000 - i * 1000,
          'last_event_at': 1790000100 - i * 1000,
        };
    final service =
        PortfolioPerformanceService(client: MockClient((request) async {
      if (request.url.path == '/v2/user-pnl') {
        return http.Response(jsonEncode(pm([])), 200);
      }
      if (request.url.queryParameters['status'] == 'OPEN') {
        return http.Response(
            jsonEncode({'data': [], 'pagination': {'has_more': false}}), 200);
      }
      final page = pages++;
      expect(request.url.queryParameters['cursor'],
          page == 0 ? isNull : 'c$page');
      return http.Response(
          jsonEncode({
            'data': [row(page)],
            'pagination': {'has_more': true, 'next_cursor': 'c${page + 1}'}
          }),
          200);
    }));
    addTearDown(service.close);
    final data = await service.polymarket(address);
    expect(pages, kPolymarketPositionPages);
    final book = data.predictions!;
    expect(book.complete, isFalse);
    expect(book.records, hasLength(kPolymarketPositionPages));
    expect(book.coversFrom, book.records.last.lastEventAt);
    // Statistics reaching back before the oldest row read are unknown.
    expect(book.statsSince(null), isNull);
    expect(book.statsSince(book.coversFrom), isNotNull);
  });

  test('a position row names its market, event and outcome', () {
    final page = parsePolymarketPositionsPage({
      'data': [
        {
          'proxy_wallet': address,
          'token_id': 't',
          'condition_id': '0xABC',
          'current_size': 1,
          'total_size': 1,
          'avg_price': 0.5,
          'entry_cost_usdc': 0.5,
          'current_price': 0.6,
          'realized_pnl': 0,
          'unrealized_pnl': 0.1,
          'title': ' Will it rain? ',
          'slug': 'will-it-rain',
          'event_slug': 'rain',
          'outcome': 'Yes',
          'icon': 'https://example.com/i.png',
        },
        {
          'proxy_wallet': address,
          'token_id': 'u',
          'current_size': 0,
          'total_size': 1,
          'avg_price': 0.5,
          'entry_cost_usdc': 0,
          'current_price': 0,
          'realized_pnl': -0.5,
          'unrealized_pnl': 0,
        },
      ]
    }, expectedAddress: address, open: true);
    final [named, bare] = page.records;
    expect(named.conditionId, '0xabc');
    expect(named.title, 'Will it rain?');
    expect(named.slug, 'will-it-rain');
    expect(named.eventSlug, 'rain');
    expect(named.outcome, 'Yes');
    expect(named.icon, 'https://example.com/i.png');
    expect([bare.title, bare.eventSlug, bare.outcome, bare.icon],
        ['', '', '', '']);
  });

  test('positions of another wallet are rejected', () {
    expect(
        () => parsePolymarketPositionsPage({
              'data': [
                {'proxy_wallet': '0x2222222222222222222222222222222222222222'}
              ]
            }, expectedAddress: address, open: true),
        throwsFormatException);
  });

  test('Hyperliquid week and month samples are lifted onto all time', () {
    final data = parseHyperliquidPerformance([
      [
        'week',
        {
          'pnlHistory': [
            [1700000500000, '0.0'],
            [1700000600000, '-4'],
            [1700000900000, '3']
          ]
        }
      ],
      [
        'allTime',
        {
          'pnlHistory': [
            [1700000000000, '0.0'],
            [1700000500000, '20'],
            [1700000900000, '23']
          ]
        }
      ],
    ]);
    expect(data.points.map((p) => p.pnlUsd), [0, 20, 16, 23]);
    expect(data.totalPnlUsd, 23);
    final week = data.rangeView(const Duration(milliseconds: 400000));
    expect(week.changeUsd, 3);
  });

  test('HTTP and malformed responses remain errors', () async {
    final service = PortfolioPerformanceService(
        client: MockClient((_) async => http.Response('{}', 503)));
    addTearDown(service.close);
    await expectLater(
        service.polymarket(address), throwsA(isA<http.ClientException>()));
    await expectLater(service.hyperliquid('not-an-address'),
        throwsA(isA<PortfolioPerformanceUnavailable>()));
  });
}
