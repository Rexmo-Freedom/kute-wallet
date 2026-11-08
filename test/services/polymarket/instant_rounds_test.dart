// Predictions › Instant: which lengths and assets the filter offers, and
// the one round that stands for each asset (instant_rounds.dart).

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/services/polymarket/instant_rounds.dart';

final _now = DateTime.utc(2026, 11, 8, 12, 7);

int _epoch(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

PolymarketEvent _event(String slug, {DateTime? end, bool closed = false}) =>
    PolymarketEvent(
      id: slug,
      slug: slug,
      title: slug,
      volume: 0,
      liquidity: 0,
      category: 'crypto',
      conditionId: slug,
      endDate: end,
      closed: closed,
      outcomes: const [],
    );

PolymarketEvent _fifteen(String asset, DateTime start) => _event(
    '$asset-updown-15m-${_epoch(start)}',
    end: start.add(const Duration(minutes: 15)));

void main() {
  test('the lengths are the Crypto chips whose rows are rounds', () {
    expect(polyInstantLengthsOffered(['all', '5m', '15m', '1h', 'daily']),
        ['5m', '15m', '1h']);
    expect(polyInstantLengthsOffered(['all', '4h', '15m', '5m']),
        ['5m', '15m', '4h']);
    // Five minutes is the live cards and has no list to count.
    expect(polyInstantLengthsOffered(const []), ['5m']);
  });

  test('tickers follow the slug either way it writes the asset', () {
    expect(polyRoundTicker('btc'), 'BTC');
    expect(polyRoundTicker('bitcoin'), 'BTC');
    expect(polyRoundTicker('ethereum'), 'ETH');
    expect(polyRoundTicker('solana'), 'SOL');
    expect(polyRoundTicker('xrp'), 'XRP');
    expect(polyRoundTicker('dogecoin'), 'DOGE');
    expect(polyRoundTicker('hype'), 'HYPE');
    expect(polyRoundTicker('zec'), 'ZEC');
  });

  test('the chosen asset leads, the others keep the usual order', () {
    const all = ['XRP', 'BTC', 'ZEC', 'SOL', 'ETH'];
    expect(polyInstantAssetOrder(all, 'BTC'),
        ['BTC', 'ETH', 'SOL', 'XRP', 'ZEC']);
    expect(polyInstantAssetOrder(all, 'SOL'),
        ['SOL', 'BTC', 'ETH', 'XRP', 'ZEC']);
    expect(polyInstantAssetOrder(all, ''), ['BTC', 'ETH', 'SOL', 'XRP', 'ZEC']);
    // An asset it does not have does not lead.
    expect(polyInstantAssetOrder(const ['ETH', 'BTC'], 'SOL'), ['BTC', 'ETH']);
  });

  group('one round per asset', () {
    final inPlay = DateTime.utc(2026, 11, 8, 12, 0);
    final next = DateTime.utc(2026, 11, 8, 12, 15);

    test('the round in play, never the windows ahead', () {
      final rows = polyInstantRows([
        _fifteen('eth', next),
        _fifteen('btc', next),
        _fifteen('eth', inPlay),
        _fifteen('btc', inPlay),
      ], chosen: 'BTC', now: _now);
      expect(rows.map((e) => e.slug), [
        'btc-updown-15m-${_epoch(inPlay)}',
        'eth-updown-15m-${_epoch(inPlay)}',
      ]);
    });

    test('an asset between rounds shows its next one', () {
      final rows = polyInstantRows([_fifteen('sol', next)],
          chosen: 'BTC', now: _now);
      expect(rows.single.slug, 'sol-updown-15m-${_epoch(next)}');
    });

    test('a finished round, a closed one and a row that is no round go', () {
      final earlier = DateTime.utc(2026, 11, 8, 11, 45);
      final rows = polyInstantRows([
        _fifteen('btc', earlier),
        _event('xrp-updown-15m-${_epoch(inPlay)}',
            end: next, closed: true),
        _event('bitcoin-above-on-november-8-2026-1pm-et',
            end: DateTime.utc(2026, 11, 8, 13)),
      ], chosen: 'BTC', now: _now);
      expect(rows, isEmpty);
    });

    test('an hourly round reads its time off its end, its name to a ticker',
        () {
      final hour = _event('bitcoin-up-or-down-november-8-2026-7am-et',
          end: DateTime.utc(2026, 11, 8, 13));
      final ahead = _event('bitcoin-up-or-down-november-8-2026-8am-et',
          end: DateTime.utc(2026, 11, 8, 14));
      final rows = polyInstantRows([ahead, hour], chosen: 'BTC', now: _now);
      expect(rows.single, hour);
      expect(polyInstantAssetOf(hour), 'BTC');
      expect(polyInstantAssetOf(_event('fed-decision')), isNull);
    });

    test('the shown rows are read again when the first of them ends', () {
      final rows = [_fifteen('btc', inPlay), _fifteen('eth', next)];
      expect(polyInstantNextEnd(rows), next);
      expect(polyInstantNextEnd(const []), isNull);
    });
  });

  test('the next five-minute round starts on the clock', () {
    expect(polyNextFiveMinuteRoundIn(DateTime.utc(2026, 11, 8, 12, 7, 47)),
        const Duration(seconds: 133));
    expect(polyNextFiveMinuteRoundIn(DateTime.utc(2026, 11, 8, 12, 10)),
        const Duration(minutes: 5));
  });
}
