// Predictions › Instant: which lengths and assets the filter offers, how
// the coins are ordered, the route key (instant_rounds.dart).

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/services/polymarket/instant_rounds.dart';

PolymarketEvent _event(String slug, {DateTime? end}) => PolymarketEvent(
      id: slug,
      slug: slug,
      title: slug,
      volume: 0,
      liquidity: 0,
      category: 'crypto',
      conditionId: slug,
      endDate: end,
      outcomes: const [],
    );

void main() {
  test('the lengths are the Crypto chips whose rows are rounds', () {
    expect(polyInstantLengthsOffered(['all', '5m', '15m', '1h', 'daily']),
        ['5m', '15m', '1h']);
    expect(polyInstantLengthsOffered(['all', '4h', '15m', '5m']),
        ['5m', '15m', '4h']);
    // Five minutes is always on offer and has no list to count.
    expect(polyInstantLengthsOffered(const []), ['5m']);
  });

  test('a length in minutes', () {
    expect(polyInstantMinutes('5m'), 5);
    expect(polyInstantMinutes('15m'), 15);
    expect(polyInstantMinutes('1h'), 60);
    expect(polyInstantMinutes('4h'), 240);
    expect(const PolyInstantChoice(asset: 'ETH', length: '4h').minutes, 240);
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

  test('the assets on offer at a length come from the venue\'s list', () {
    final rows = [
      _event('eth-updown-15m-1794153600'),
      _event('btc-updown-15m-1794153600'),
      _event('btc-updown-15m-1794154500'),
      _event('bitcoin-up-or-down-november-8-2026-1pm-et',
          end: DateTime.utc(2026, 11, 8, 19)),
      // Not a round: shares the tag, no window.
      _event('bitcoin-above-80000-on-november-8'),
    ];
    const all = ['BTC', 'ETH', 'SOL', 'XRP', 'DOGE', 'BNB', 'HYPE'];
    expect(polyInstantAssetsOffered(rows, chosen: 'BTC', fallback: all),
        ['BTC', 'ETH']);
    // The chosen coin stays on offer whatever the list says.
    expect(polyInstantAssetsOffered(rows, chosen: 'HYPE', fallback: all),
        ['BTC', 'ETH', 'HYPE']);
    // No list yet: every known coin.
    expect(polyInstantAssetsOffered(const [], chosen: 'SOL', fallback: all),
        all);
    expect(polyInstantAssetOf(rows.last), isNull);
    expect(polyInstantAssetOf(rows[3]), 'BTC');
  });

  test('the route key names the screen, nothing else', () {
    expect(polyIsInstantRouteKey('predictions/instant'), isTrue);
    expect(polyIsInstantRouteKey('/predictions/instant/'), isTrue);
    expect(polyIsInstantRouteKey('predictions/crypto/5m'), isFalse);
    expect(polyIsInstantRouteKey('instant'), isFalse);
  });
}
