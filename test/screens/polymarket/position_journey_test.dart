// The open-position chart's data (position_journey.dart): an open
// position always has a chart, whatever the history holds.
//
// Founder report, 27 Oct 2026: "Flávio Bolsonaro charged or arrested by
// October 31?", Yes bought at 36¢ ($10.01) at 15:25:54 UTC, the chart
// missing under the tiles. The trade history found the buy; the price
// history (Data API /v2/prices-history: one point per minute in which the
// price moved, the last one stamped at the last move, 15:42:28 still the
// newest at 15:48) had no point after the buy when the sheet read it, so
// the journey was null and the chart hidden, and the sheet never read the
// history again while open.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/screens/polymarket/components/position_journey.dart';

const _token =
    '18543375126809870900251079011750118581792388072844828839324758095022873872366';

Activity _buy(DateTime at, {String asset = _token}) => Activity(
      proxyWallet: '0x91094d02a65314b016aa1565c604cbb9145f6d93',
      timestamp: at.millisecondsSinceEpoch ~/ 1000,
      conditionId:
          '0x7c894d1d57329c7b05695a016bf45dbf14f78f4795af9f05c65495eb2bb14ab6',
      type: 'TRADE',
      size: 27.552302,
      usdcSize: 10.00997,
      transactionHash: '0xbuy',
      price: 0.3625831337,
      asset: asset,
      side: 'BUY',
    );

Future<PolyPositionJourney?> _journey({
  required List<Activity> activity,
  required Map<String, List<PolymarketPricePoint>> history,
  DateTime? fallbackSince,
  List<String>? reads,
}) async {
  final c = ProviderContainer(overrides: [
    polymarketActivityProvider.overrideWith((ref) async => activity),
    polymarketMarketHistoryProvider.overrideWith((ref, key) async {
      reads?.add(key.interval);
      return history[key.interval] ?? const <PolymarketPricePoint>[];
    }),
  ]);
  addTearDown(c.dispose);
  final key = (tokenId: _token, fallbackSince: fallbackSince);
  final sub = c.listen(polyPositionJourneyProvider(key), (_, __) {});
  addTearDown(sub.close);
  return c.read(polyPositionJourneyProvider(key).future);
}

void main() {
  test('the founder\'s case: the buy found, no history point after it yet: '
      'still a journey, from the buy, no points', () async {
    final buy = DateTime.now().subtract(const Duration(minutes: 2));
    final j = await _journey(activity: [
      _buy(buy)
    ], history: {
      '1h': [
        PolymarketPricePoint(
            timestamp: buy.subtract(const Duration(minutes: 20)),
            price: 0.2175),
        PolymarketPricePoint(
            timestamp: buy.subtract(const Duration(seconds: 54)),
            price: 0.2195),
      ],
    });
    expect(j, isNotNull);
    expect(j!.since.millisecondsSinceEpoch ~/ 1000,
        buy.millisecondsSinceEpoch ~/ 1000);
    expect(j.points, isEmpty);
    expect(j.fromBuy, isTrue);
    // Drawn from the price paid to the live chance.
    final pts = PolyPositionJourneyLine.series(j, 0.477, 0.3626, DateTime.now());
    expect(pts, hasLength(2));
    expect(pts.first, (t: 0.0, p: 0.3626));
    expect(pts.last, (t: 1.0, p: 0.477));
  });

  test('the history after the buy is kept, oldest first', () async {
    final buy = DateTime.now().subtract(const Duration(hours: 2));
    final j = await _journey(activity: [
      _buy(buy)
    ], history: {
      '6h': [
        PolymarketPricePoint(
            timestamp: buy.add(const Duration(minutes: 30)), price: 0.33),
        PolymarketPricePoint(
            timestamp: buy.subtract(const Duration(minutes: 30)), price: 0.21),
        PolymarketPricePoint(
            timestamp: buy.add(const Duration(minutes: 10)), price: 0.32),
      ],
    });
    expect(j!.fromBuy, isTrue);
    expect(j.points.map((p) => p.price), [0.32, 0.33]);
  });

  test('the buy out of the trade history: the position\'s first entry', () async {
    final entered = DateTime.now().subtract(const Duration(days: 3));
    final reads = <String>[];
    final j = await _journey(
      activity: [_buy(DateTime.now(), asset: 'another-token')],
      history: {
        '1w': [
          PolymarketPricePoint(
              timestamp: entered.add(const Duration(hours: 1)), price: 0.3),
          PolymarketPricePoint(
              timestamp: entered.add(const Duration(hours: 2)), price: 0.31),
        ],
      },
      fallbackSince: entered,
      reads: reads,
    );
    expect(reads, ['1w']);
    expect(j!.since, entered);
    expect(j.fromBuy, isTrue);
    expect(j.points, hasLength(2));
  });

  test('no known buy at all: the last week of history, starting on its '
      'first point, not at the price paid', () async {
    final now = DateTime.now();
    final reads = <String>[];
    final j = await _journey(activity: const [], history: {
      '1w': [
        PolymarketPricePoint(
            timestamp: now.subtract(const Duration(days: 6)), price: 0.10),
        PolymarketPricePoint(
            timestamp: now.subtract(const Duration(days: 2)), price: 0.25),
      ],
    }, reads: reads);
    expect(reads, ['1w']);
    expect(j, isNotNull);
    expect(j!.fromBuy, isFalse);
    expect(j.since, now.subtract(const Duration(days: 6)));
    final pts = PolyPositionJourneyLine.series(j, 0.3, 0.36, now);
    expect(pts.first.p, closeTo(0.10, 1e-9));
    expect(pts.last, (t: 1.0, p: 0.3));
  });

  test('no known buy and no history: still a chart, price paid to now',
      () async {
    final j = await _journey(activity: const [], history: const {});
    expect(j, isNotNull);
    expect(j!.fromBuy, isFalse);
    expect(j.points, isEmpty);
    final pts = PolyPositionJourneyLine.series(j, 0.477, 0.36, DateTime.now());
    expect(pts.map((p) => p.p), [0.36, 0.477]);
  });

  testWidgets('a thin history is read again while the sheet is open, and the '
      'new minutes come in', (tester) async {
    final buy = DateTime.now().subtract(const Duration(minutes: 2));
    var reads = 0;
    final c = ProviderContainer(overrides: [
      polymarketActivityProvider.overrideWith((ref) async => [_buy(buy)]),
      polymarketMarketHistoryProvider.overrideWith((ref, key) async {
        reads++;
        return [
          PolymarketPricePoint(
              timestamp: buy.subtract(const Duration(minutes: 1)),
              price: 0.2195),
          if (reads > 1) ...[
            PolymarketPricePoint(
                timestamp: buy.add(const Duration(seconds: 6)), price: 0.3265),
            PolymarketPricePoint(
                timestamp: buy.add(const Duration(seconds: 66)), price: 0.327),
          ],
        ];
      }),
    ]);
    addTearDown(c.dispose);
    final key = (tokenId: _token, fallbackSince: null);
    final sub = c.listen(polyPositionJourneyProvider(key), (_, __) {});
    addTearDown(sub.close);
    await tester.pump();
    await tester.pump();
    expect(c.read(polyPositionJourneyProvider(key)).valueOrNull!.points,
        isEmpty);
    expect(reads, 1);
    // The 1h range is fresh for 30 s; then read again.
    await tester.pump(const Duration(seconds: 32));
    await tester.pump();
    await tester.pump();
    expect(reads, greaterThanOrEqualTo(2));
    expect(c.read(polyPositionJourneyProvider(key)).valueOrNull!.points,
        hasLength(2));
  });

  testWidgets('a trade history that never answers (restarted by every '
      'positions refresh, or a slow Data API) does not hold the chart back: '
      'the position\'s first entry after a few seconds', (tester) async {
    final entered = DateTime.now().subtract(const Duration(minutes: 20));
    final never = Completer<List<Activity>>();
    final c = ProviderContainer(overrides: [
      polymarketActivityProvider.overrideWith((ref) => never.future),
      polymarketMarketHistoryProvider.overrideWith((ref, key) async => [
            PolymarketPricePoint(
                timestamp: entered.add(const Duration(minutes: 5)),
                price: 0.33),
          ]),
    ]);
    final key = (tokenId: _token, fallbackSince: entered);
    final sub = c.listen(polyPositionJourneyProvider(key), (_, __) {});
    await tester.pump();
    expect(c.read(polyPositionJourneyProvider(key)).valueOrNull, isNull);
    await tester.pump(kPolyJourneyActivityWait + const Duration(seconds: 1));
    await tester.pump();
    final j = c.read(polyPositionJourneyProvider(key)).valueOrNull;
    expect(j, isNotNull);
    expect(j!.since, entered);
    expect(j.points, hasLength(1));
    // Its thin-history re-read timer goes with the sheet.
    sub.close();
    c.dispose();
    await tester.pump(const Duration(seconds: 10));
  });

  test('"Your avg" sits on the side the line leaves it from, the range '
      'opened to hold it', () {
    const h = 110.0;
    // Bought at 36¢, straight up to 47.7¢: under the dashed line.
    final up = [(t: 0.0, p: 0.36), (t: 1.0, p: 0.477)];
    final a = polyJourneyAvgPlacement(
        up, 0.36, polyJourneyRange(up.map((q) => q.p), 0.36), h);
    expect(a.below, isTrue);
    expect(a.y + 20, lessThanOrEqualTo(h + 1e-9));
    // Bought at 60¢, falling: over it.
    final down = [(t: 0.0, p: 0.60), (t: 1.0, p: 0.45)];
    final b = polyJourneyAvgPlacement(
        down, 0.60, polyJourneyRange(down.map((q) => q.p), 0.60), h);
    expect(b.below, isFalse);
    expect(b.y, greaterThanOrEqualTo(20 - 1e-9));
    // No room under 1¢ to open: the old rule.
    final floor = [(t: 0.0, p: 0.001), (t: 1.0, p: 0.2)];
    final c = polyJourneyAvgPlacement(
        floor, 0.001, polyJourneyRange(floor.map((q) => q.p), 0.001), h);
    expect(c.range.lo, greaterThanOrEqualTo(0));
  });

  group('where the buy\'s time comes from', () {
    test('the live /v2/activity row of the founder\'s buy finds it', () async {
      final rows = await PolymarketModel().getUserActivityOrThrow(
          '0x91094d02a65314b016aa1565c604cbb9145f6d93',
          client: MockClient((_) async => http.Response(
              jsonEncode({
                'data': [
                  {
                    'proxy_wallet': '0x91094d02a65314b016aa1565c604cbb9145f6d93',
                    'timestamp': 1793114754,
                    'condition_id':
                        '0x7c894d1d57329c7b05695a016bf45dbf14f78f4795af9f05c65495eb2bb14ab6',
                    'type': 'TRADE',
                    'size': 27.552302,
                    'usdc_size': 10.00997,
                    'transaction_hash': '0xabc',
                    'price': 0.3625831337,
                    'token_id': _token,
                    'side': 'BUY',
                    'outcome_index': 0,
                    'outcome': 'Yes',
                  }
                ],
                'pagination': {'has_more': false},
              }),
              200)));
      expect(polyFirstBuyOfHolding(rows, _token),
          DateTime.fromMillisecondsSinceEpoch(1793114754 * 1000));
    });

    test('/v2/positions first_entry_at is kept per wallet and token', () {
      final body = jsonEncode({
        'data': [
          {
            'proxy_wallet': '0x91094d02a65314b016aa1565c604cbb9145f6d93',
            'token_id': _token,
            'condition_id': '0x7c89',
            'current_size': 27.5523,
            'avg_price': 0.3625,
            'current_price': 0.322,
            'status': 'OPEN',
            'first_entry_at': 1793114754,
            'last_event_at': 1793114754,
          },
          {
            'proxy_wallet': '0x91094d02a65314b016aa1565c604cbb9145f6d93',
            'token_id': 'no-entry',
            'current_size': 1,
          },
        ],
      });
      final entries = debugParsePositionEntries(body);
      expect(entries, {_token: 1793114754});
      PolyPositionFirstEntry.debugReset();
      PolyPositionFirstEntry.note(
          '0x91094D02A65314B016AA1565C604CBB9145F6D93', entries);
      expect(
          PolyPositionFirstEntry.of(
              '0x91094d02a65314b016aa1565c604cbb9145f6d93', _token),
          DateTime.fromMillisecondsSinceEpoch(1793114754 * 1000));
      expect(PolyPositionFirstEntry.of('0xother', _token), isNull);
      PolyPositionFirstEntry.debugReset();
    });
  });
}
