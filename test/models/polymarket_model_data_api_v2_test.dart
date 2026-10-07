// Data API v2 + Gamma keyset reads (https://docs.polymarket.com/migrate/
// data-api-v1-to-v2): every parser re-keys the snake_case v2 rows into the
// Dart objects the v1 routes produced, so nothing downstream changes shape.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show TagSlug;

const _wallet = '0x4F615CCE8C655E74FEF14273EA85AE1E705D9E5A';

http.Response _page(List<Map<String, dynamic>> rows, {String? next}) =>
    http.Response(
        jsonEncode({
          'data': rows,
          'pagination': {
            'limit': rows.length,
            'offset': 0,
            'has_more': next != null,
            'next_cursor': next,
          },
        }),
        200);

// Live-shaped `GET /v2/positions` row (status=OPEN arm).
const _openRow = {
  'proxy_wallet': '0x4f615cce8c655e74fef14273ea85ae1e705d9e5a',
  'token_id': '115675',
  'condition_id': '0xf5d8',
  'current_size': 37.037,
  'avg_price': 0.0269,
  'entry_cost_usdc': 0.9999,
  'entry_fees_usdc': 0.05864,
  'total_cost_usdc': 1.05854,
  'current_price': 0.0,
  'current_value': 0.0,
  'total_size': 40.5,
  'realized_pnl': -0.0587,
  'unrealized_pnl': -0.9999,
  'total_pnl': -1.0586,
  'percent_pnl': -99.991,
  'percent_realized_pnl': -100.0,
  'status': 'REDEEMABLE',
  'redeemable': true,
  'mergeable': false,
  'negative_risk': true,
  'archived': false,
  'title': 'LoL: Vietnam vs United Arab Emirates (BO1)',
  'slug': 'lol-vie-uae-2026-09-29',
  'icon': 'https://img/lol.png',
  'event_id': '1094602',
  'event_slug': 'lol-vie-uae-2026-09-29',
  'outcome': 'United Arab Emirates',
  'outcome_index': 1,
  'opposite_outcome': 'Vietnam',
  'opposite_token_id': '927868',
  'end_date': '2026-09-29',
  'last_event_at': 1790676375,
  'name': '',
  'profile_image': '',
  'verified': false,
};

Map<String, dynamic> _closedRow({
  required String token,
  required double currentPrice,
  required double totalSize,
  required double avgPrice,
  required double realized,
  int lastEventAt = 1790669537,
}) =>
    {
      'proxy_wallet': '0x4f61',
      'token_id': token,
      'condition_id': '0xc-$token',
      'current_size': 0.0013,
      'avg_price': avgPrice,
      'entry_cost_usdc': 0.001,
      'entry_fees_usdc': 0.0,
      'total_cost_usdc': 0.001,
      'current_price': currentPrice,
      'current_value': 0.0013 * currentPrice,
      'total_size': totalSize,
      'realized_pnl': realized,
      'unrealized_pnl': 0.0,
      'total_pnl': realized,
      'percent_pnl': 30.0,
      'percent_realized_pnl': -41.066,
      'status': 'CLOSED',
      'redeemable': true,
      'mergeable': true,
      'negative_risk': false,
      'archived': false,
      'title': 'Bitcoin Up or Down - September 29, 3AM ET',
      'slug': 'bitcoin-up-or-down',
      'icon': 'https://img/btc.png',
      'event_id': '1090145',
      'event_slug': 'bitcoin-up-or-down',
      'outcome': 'Down',
      'outcome_index': 1,
      'opposite_outcome': 'Up',
      'opposite_token_id': '7720',
      'end_date': '2026-09-29',
      'last_event_at': lastEventAt,
      'name': '',
      'profile_image': '',
      'verified': false,
    };

const _activityRow = {
  'proxy_wallet': '0x4f61',
  'timestamp': 1790676509,
  'condition_id': '0x1d4e',
  'type': 'TRADE',
  'size': 13.513511,
  'usdc_size': 10.229978,
  'transaction_hash': '0xcf9b',
  'price': 0.7399999896,
  'token_id': '75935',
  'side': 'BUY',
  'outcome_index': 0,
  'title': 'Valorant: G2 Esports vs Paper Rex',
  'slug': 'val-g21-pr1',
  'icon': 'https://img/valorant.png',
  'event_slug': 'val-g21-pr1',
  'outcome': 'G2 Esports',
  'name': '',
  'pseudonym': '',
  'bio': '',
  'profile_image': '',
  'profile_image_optimized': '',
};

void main() {
  group('Data API v2 positions', () {
    test('getPositionsOrThrow asks /v2/positions with the v1 defaults restated',
        () async {
      Uri? seen;
      final positions = await PolymarketModel().getPositionsOrThrow(_wallet,
          client: MockClient((request) async {
        seen = request.url;
        return _page([_openRow]);
      }));
      expect(seen!.host, 'data-api.polymarket.com');
      expect(seen!.path, '/v2/positions');
      expect(seen!.queryParameters, {
        'user': _wallet.toLowerCase(),
        'status': 'OPEN',
        'limit': '100',
        'filter_type': 'TOKENS',
        'filter_amount': '1',
        'sort_by': 'TOKENS',
        'sort_direction': 'DESC',
      });
      expect(positions, hasLength(1));
      final p = positions.single;
      // v1 name -> v2 name mapping.
      expect(p.proxyWallet, '0x4f615cce8c655e74fef14273ea85ae1e705d9e5a');
      expect(p.asset, '115675'); // token_id
      expect(p.conditionId, '0xf5d8');
      expect(p.size, 37.037); // current_size
      expect(p.avgPrice, 0.0269);
      expect(p.initialValue, 0.9999); // entry_cost_usdc
      expect(p.currentValue, 0.0);
      expect(p.cashPnl, -0.9999); // unrealized_pnl
      expect(p.percentPnl, -99.991);
      expect(p.totalBought, 40.5); // total_size
      expect(p.realizedPnl, -0.0587);
      expect(p.percentRealizedPnl, -100.0);
      expect(p.curPrice, 0.0); // current_price
      expect(p.redeemable, isTrue);
      expect(p.mergeable, isFalse);
      expect(p.title, 'LoL: Vietnam vs United Arab Emirates (BO1)');
      expect(p.slug, 'lol-vie-uae-2026-09-29');
      expect(p.icon, 'https://img/lol.png');
      expect(p.eventSlug, 'lol-vie-uae-2026-09-29');
      expect(p.outcome, 'United Arab Emirates');
      expect(p.outcomeIndex, 1);
      expect(p.oppositeOutcome, 'Vietnam');
      expect(p.oppositeAsset, '927868'); // opposite_token_id
      expect(p.endDate, '2026-09-29');
      expect(p.negativeRisk, isTrue);
    });

    test('getPositions parses off-thread and reads a failure as no rows',
        () async {
      final model = PolymarketModel();
      final ok = await model.getPositions(_wallet,
          client: MockClient((_) async => _page([_openRow])));
      expect(ok.single.asset, '115675');
      final failed = await model.getPositions(_wallet,
          client: MockClient((_) async => http.Response('down', 503)));
      expect(failed, isEmpty);
    });
  });

  group('Data API v2 closed positions', () {
    test('asks the CLOSED arm newest-exit first and derives the v1 fields',
        () async {
      Uri? seen;
      final closed = await PolymarketModel().getClosedPositions(_wallet,
          client: MockClient((request) async {
        seen = request.url;
        return _page([
          // Settled winner: bought 10 @ 0.40, realized +6.
          _closedRow(
              token: 'won',
              currentPrice: 1.0,
              totalSize: 10,
              avgPrice: 0.4,
              realized: 6,
              lastEventAt: 1790669537),
          // Settled loser after clearing: bought 5 @ 0.80, realized -4.
          _closedRow(
              token: 'lost',
              currentPrice: 0.0,
              totalSize: 5,
              avgPrice: 0.8,
              realized: -4,
              lastEventAt: 0),
          // Sold while the market still trades: no WON/LOST verdict exists.
          _closedRow(
              token: 'sold',
              currentPrice: 0.61,
              totalSize: 5,
              avgPrice: 0.5,
              realized: 0.5),
        ]);
      }));
      expect(seen!.path, '/v2/positions');
      expect(seen!.queryParameters, {
        'user': _wallet.toLowerCase(),
        'status': 'CLOSED',
        'limit': '100',
        'sort_by': 'TIMESTAMP',
        'sort_direction': 'DESC',
      });
      expect(closed.map((c) => c.asset), ['won', 'lost']);

      final won = closed[0];
      expect(won.won, isTrue);
      expect(won.size, 10); // total_size: lifetime shares
      expect(won.avgPrice, 0.4);
      expect(won.initialValue, closeTo(4.0, 1e-9)); // total_size * avg_price
      expect(won.cashPnl, 6); // realized_pnl
      expect(won.percentPnl, closeTo(150, 1e-9));
      expect(won.payout, closeTo(10.0, 1e-9)); // basis + realized
      expect(won.resolutionDate,
          DateTime.fromMillisecondsSinceEpoch(1790669537 * 1000, isUtc: true));
      expect(won.title, 'Bitcoin Up or Down - September 29, 3AM ET');
      expect(won.conditionId, '0xc-won');
      expect(won.eventSlug, 'bitcoin-up-or-down');
      expect(won.outcome, 'Down');
      expect(won.outcomeIndex, 1);

      final lost = closed[1];
      expect(lost.won, isFalse);
      expect(lost.initialValue, closeTo(4.0, 1e-9));
      expect(lost.cashPnl, -4);
      expect(lost.percentPnl, closeTo(-100, 1e-9));
      expect(lost.payout, 0); // never negative
      expect(lost.resolutionDate, isNull); // last_event_at 0
    });

    test('remembers which closed conditions are neg-risk', () async {
      final model = PolymarketModel();
      await model.getClosedPositions(_wallet,
          client: MockClient((_) async => _page([
                {
                  ..._closedRow(
                      token: 'nr',
                      currentPrice: 1.0,
                      totalSize: 3,
                      avgPrice: 0.5,
                      realized: 1.5),
                  'negative_risk': true,
                },
                _closedRow(
                    token: 'std',
                    currentPrice: 1.0,
                    totalSize: 3,
                    avgPrice: 0.5,
                    realized: 1.5),
              ])));
      expect(model.closedNegRiskConditionIds, {'0xc-nr'});
    });

    test('a settled row sold before its result is neither won nor lost',
        () async {
      final model = PolymarketModel();
      final closed = await model.getClosedPositions(_wallet,
          client: MockClient((_) async => _page([
                // Held to the result: paid exactly $1 a share.
                _closedRow(
                    token: 'won',
                    currentPrice: 1.0,
                    totalSize: 10,
                    avgPrice: 0.4,
                    realized: 6),
                // The CS2 sale of 5 Oct 2026: 2.07 of 2.0729 G2 shares sold
                // for $1.95 while the game was being reported; the market
                // then settled at 1. Paid 94¢ a share: sold, not won.
                _closedRow(
                    token: 'g2',
                    currentPrice: 1.0,
                    totalSize: 2.072917,
                    avgPrice: 0.9,
                    realized: 1.95 - 2.072917 * 0.9),
                // Sold for a profit at 60¢, then its side lost: not lost.
                _closedRow(
                    token: 'exit',
                    currentPrice: 0.0,
                    totalSize: 10,
                    avgPrice: 0.5,
                    realized: 1),
                // Held to a loss: paid nothing.
                _closedRow(
                    token: 'lost',
                    currentPrice: 0.0,
                    totalSize: 5,
                    avgPrice: 0.8,
                    realized: -4),
              ])));
      expect(closed.map((c) => c.asset), ['won', 'lost']);
      expect(closed.first.won, isTrue);
      expect(closed.last.won, isFalse);
      // Kept aside for the on-chain claim scan only.
      expect(model.closedSoldPositions.map((c) => c.asset), ['g2', 'exit']);
    });

    test('a failed read is an empty list, as before', () async {
      final closed = await PolymarketModel().getClosedPositions(_wallet,
          client: MockClient((_) async => http.Response('down', 500)));
      expect(closed, isEmpty);
    });
  });

  group('Data API v2 value', () {
    test('reads data.value from the /v2/value envelope', () async {
      Uri? seen;
      final value = await PolymarketModel().getPortfolioTotalValue(_wallet,
          client: MockClient((request) async {
        seen = request.url;
        return http.Response(
            jsonEncode({
              'data': {'proxy_wallet': _wallet.toLowerCase(), 'value': 12.5}
            }),
            200);
      }));
      expect(seen!.path, '/v2/value');
      expect(seen!.queryParameters, {'user': _wallet.toLowerCase()});
      expect(value, 12.5);
    });

    test('a null payload, the retired v1 array and a failure all read as 0',
        () async {
      final model = PolymarketModel();
      Future<double> read(String body, [int status = 200]) =>
          model.getPortfolioTotalValue(_wallet,
              client: MockClient((_) async => http.Response(body, status)));
      expect(await read('{"data":null}'), 0);
      expect(await read('[{"user":"x","value":3}]'), 3);
      expect(await read('down', 503), 0);
    });
  });

  group('Data API v2 activity', () {
    test('getUserActivityOrThrow asks /v2/activity and maps token_id to asset',
        () async {
      Uri? seen;
      final rows = await PolymarketModel().getUserActivityOrThrow(_wallet,
          client: MockClient((request) async {
        seen = request.url;
        return _page([
          _activityRow,
          {
            ..._activityRow,
            'type': 'REDEEM',
            'side': '',
            'price': 0,
            'transaction_hash': '0xredeem',
          },
        ]);
      }));
      expect(seen!.path, '/v2/activity');
      expect(seen!.queryParameters, {
        'user': _wallet.toLowerCase(),
        'limit': '100',
      });
      expect(rows, hasLength(2));
      final trade = rows[0];
      expect(trade.proxyWallet, '0x4f61');
      expect(trade.timestamp, 1790676509);
      expect(trade.conditionId, '0x1d4e');
      expect(trade.type, 'TRADE');
      expect(trade.activityType, ActivityType.trade);
      expect(trade.size, 13.513511);
      expect(trade.usdcSize, 10.229978);
      expect(trade.transactionHash, '0xcf9b');
      expect(trade.price, 0.7399999896);
      expect(trade.asset, '75935'); // token_id
      expect(trade.side, 'BUY');
      expect(trade.outcomeIndex, 0);
      expect(trade.title, 'Valorant: G2 Esports vs Paper Rex');
      expect(trade.eventSlug, 'val-g21-pr1');
      expect(trade.outcome, 'G2 Esports');
      expect(trade.icon, 'https://img/valorant.png');
      final redeem = rows[1];
      expect(redeem.type, 'REDEEM');
      // v2 sends "" where no side applies; v1 consumers test for null.
      expect(redeem.side, isNull);
      expect(redeem.price, 0);
    });

    test('a failed read throws (unknown, not empty history)', () async {
      await expectLater(
          PolymarketModel().getUserActivityOrThrow(_wallet,
              client: MockClient((_) async => http.Response('down', 503))),
          throwsStateError);
    });
  });

  group('Data API v2 prices history', () {
    test('maps fidelity minutes to bucket_seconds and follows the cursor',
        () async {
      final seen = <Uri>[];
      final points = await PolymarketModel().getPriceHistory('75935',
          interval: '1w',
          fidelity: 60,
          client: MockClient((request) async {
        seen.add(request.url);
        if (request.url.queryParameters['cursor'] == null) {
          return _page([
            {'timestamp': 1790258400, 'price': 0.51, 'resolution_seconds': 3600},
            {'timestamp': 1790262000, 'price': 0.55, 'resolution_seconds': 3600},
          ], next: 'c1');
        }
        return _page([
          {'timestamp': 1790676526, 'price': 0.735, 'resolution_seconds': 0},
        ]);
      }));
      expect(seen, hasLength(2));
      expect(seen.first.host, 'data-api.polymarket.com');
      expect(seen.first.path, '/v2/prices-history');
      expect(seen.first.queryParameters, {
        'token_id': '75935',
        'interval': '1w',
        'bucket_seconds': '3600',
      });
      expect(seen.last.queryParameters['cursor'], 'c1');
      expect(points.map((p) => p.price), [0.51, 0.55, 0.735]);
      expect(points.first.timestamp,
          DateTime.fromMillisecondsSinceEpoch(1790258400 * 1000));
      expect(points.last.timestamp,
          DateTime.fromMillisecondsSinceEpoch(1790676526 * 1000));
    });

    test('bucket_seconds stays inside the documented 60..86400 range',
        () async {
      final buckets = <String?>[];
      final client = MockClient((request) async {
        buckets.add(request.url.queryParameters['bucket_seconds']);
        return _page(const []);
      });
      final model = PolymarketModel();
      await model.getPriceHistory('t', interval: '1h', fidelity: 0,
          client: client);
      await model.getPriceHistory('t', interval: 'max', fidelity: 5000,
          client: client);
      expect(buckets, ['60', '86400']);
    });

    test('a failed read is an empty series, as before', () async {
      final points = await PolymarketModel().getPriceHistory('t',
          client: MockClient((_) async => http.Response('down', 503)));
      expect(points, isEmpty);
    });
  });

  group('Gamma keyset lists', () {
    Map<String, dynamic> event(String id, {bool active = true}) => {
          'id': id,
          'slug': 'event-$id',
          'title': 'Event $id',
          'active': active,
          'closed': false,
          'volume24hr': 100.0 - int.parse(id),
          'liquidity': 1000,
          'tags': [
            {'id': 1, 'slug': 'politics', 'label': 'Politics'}
          ],
          'markets': [
            {
              'id': 'm$id',
              'conditionId': '0xc$id',
              'question': 'Will $id happen?',
              'outcomes': '["Yes","No"]',
              'outcomePrices': '["0.6","0.4"]',
              'clobTokenIds': '["y$id","n$id"]',
              'volumeNum': 10,
              'liquidityNum': 1000,
            }
          ],
        };

    test('walks after_cursor in 100-row pages, never sending active/offset',
        () async {
      final seen = <Uri>[];
      final rows = await http.runWithClient(
        () => PolymarketModel.fetchGammaKeyset(
          'events',
          {
            'tag_id': '2',
            'active': 'true',
            'closed': 'false',
            'order': 'volume24hr',
            'ascending': 'false',
            'offset': '0',
          },
          limit: 150,
        ),
        () => MockClient((request) async {
          seen.add(request.url);
          final page = request.url.queryParameters['after_cursor'];
          if (page == null) {
            return http.Response(
                jsonEncode({
                  'events': [
                    for (var i = 0; i < 100; i++) event('$i'),
                  ],
                  'next_cursor': 'cursor-1',
                }),
                200);
          }
          // Last page: Gamma omits `next_cursor` when the list ends.
          return http.Response(
              jsonEncode({
                'events': [
                  for (var i = 100; i < 150; i++)
                    event('$i', active: i == 120),
                ],
              }),
              200);
        }),
      );
      expect(seen, hasLength(2));
      expect(seen.first.host, 'gamma-api.polymarket.com');
      expect(seen.first.path, '/events/keyset');
      expect(seen.first.queryParameters, {
        'tag_id': '2',
        'closed': 'false',
        'order': 'volume24hr',
        'ascending': 'false',
        'limit': '100',
      });
      expect(seen.last.queryParameters['after_cursor'], 'cursor-1');
      expect(seen.last.queryParameters['limit'], '50');
      // 100 rows from page one, one active row from page two (the keyset
      // route has no `active` filter; inactive rows are dropped here, and
      // the walk would back-fill from further pages if Gamma offered any).
      expect(rows, hasLength(101));
      expect(rows.last['id'], '120');
    });

    test('stops on a short page and skips offset rows client-side', () async {
      var requests = 0;
      final rows = await http.runWithClient(
        () => PolymarketModel.fetchGammaKeyset(
            'markets', const {'closed': 'true'},
            limit: 2, offset: 1),
        () => MockClient((_) async {
          requests++;
          return http.Response(
              jsonEncode({
                'markets': [event('7'), event('8')],
              }),
              200);
        }),
      );
      expect(requests, 1);
      expect(rows.map((r) => r['id']), ['8']);
    });

    test('a failed first page throws; a failed later page keeps what was read',
        () async {
      await expectLater(
          http.runWithClient(
            () => PolymarketModel.fetchGammaKeyset('events', const {},
                limit: 10),
            () => MockClient((_) async => http.Response('down', 503)),
          ),
          throwsA(isA<http.ClientException>()));
      final partial = await http.runWithClient(
        () => PolymarketModel.fetchGammaKeyset('events', const {}, limit: 150),
        () => MockClient((request) async {
          if (request.url.queryParameters['after_cursor'] != null) {
            return http.Response('down', 503);
          }
          return http.Response(
              jsonEncode({
                'events': [for (var i = 0; i < 100; i++) event('$i')],
                'next_cursor': 'c',
              }),
              200);
        }),
      );
      expect(partial, hasLength(100));
    });

    test('listEvents reads /events/keyset with the same filters as before',
        () async {
      Uri? seen;
      final events = await http.runWithClient(
        () => PolymarketModel().listEvents(
            tag: TagSlug.sports, hot: true, limit: 3, order: 'volume24hr'),
        () => MockClient((request) async {
          seen = request.url;
          return http.Response(
              jsonEncode({
                'events': [event('1'), event('2', active: false), event('3')],
              }),
              200);
        }),
      );
      expect(seen!.path, '/events/keyset');
      expect(seen!.queryParameters, {
        'closed': 'false',
        'order': 'volume24hr',
        'ascending': 'false',
        'tag_slug': 'sports',
        'hot': 'true',
        'limit': '3',
      });
      expect(events.map((e) => e.id), ['1', '3']);
      expect(events.first.title, 'Event 1');
      expect(events.first.conditionId, '0xc1');
      expect(events.first.yesTokenId, 'y1');
      expect(events.first.category, 'politics');
    });

    test('getEventsForSeries reads /events/keyset by series_id', () async {
      Uri? seen;
      final events = await http.runWithClient(
        () => PolymarketModel().getEventsForSeries(77),
        () => MockClient((request) async {
          seen = request.url;
          return http.Response(
              jsonEncode({
                'events': [event('9')]
              }),
              200);
        }),
      );
      expect(seen!.path, '/events/keyset');
      expect(seen!.queryParameters, {
        'series_id': '77',
        'closed': 'false',
        'order': 'volume24hr',
        'ascending': 'false',
        'limit': '100',
      });
      expect(events.single.id, '9');
    });

    test('getTopMarket reads /markets/keyset and keeps the price band filter',
        () async {
      Uri? seen;
      Map<String, dynamic> market(String id, String yes) => {
            'id': id,
            'conditionId': '0xc$id',
            'question': 'Will $id happen?',
            'outcomes': '["Yes","No"]',
            'outcomePrices': '["$yes","${1 - double.parse(yes)}"]',
            'clobTokenIds': '["y$id","n$id"]',
            'volumeNum': 5000,
            'active': true,
            'closed': false,
            'events': [
              {'id': 'e$id', 'image': 'https://img/$id.png'}
            ],
          };
      final top = await http.runWithClient(
        () => PolymarketModel().getTopMarket(),
        () => MockClient((request) async {
          seen = request.url;
          return http.Response(
              jsonEncode({
                'markets': [market('1', '0.99'), market('2', '0.6')],
              }),
              200);
        }),
      );
      expect(seen!.path, '/markets/keyset');
      expect(seen!.queryParameters, {
        'closed': 'false',
        'order': 'volume24hr',
        'ascending': 'false',
        'limit': '20',
      });
      expect(top, isNotNull);
      expect(top!.conditionId, '0xc2');
      expect(top.question, 'Will 2 happen?');
      expect(top.yesPrice, 0.6);
      expect(top.yesTokenId, 'y2');
      expect(top.noTokenId, 'n2');
      expect(top.imageUrl, 'https://img/2.png');
    });
  });
}
