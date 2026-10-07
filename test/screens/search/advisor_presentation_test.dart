import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart' show l10nForLanguage;
import 'package:kute/models/advisor_model.dart';
import 'package:kute/screens/search/components/advisor_presentation.dart';

AdvisorBlock marketBlock(
        AdvisorCard card, String id, Map<String, dynamic> params) =>
    AdvisorBlock(
      id: 'market',
      kind: AdvisorBlockKind.market,
      markdown: 'Public market',
      card: card,
      actions: [
        AdvisorActionButton(label: 'Open', actionId: id, params: params)
      ],
    );

void main() {
  const stock = AdvisorCard(
      venue: 'hyperliquid', id: 'xyz:NVDA', instrument: 'stock_perp');
  const prediction = AdvisorCard(
      venue: 'polymarket', id: 'exact-event-slug', slug: 'exact-event-slug');

  test('artwork accepts known provider hosts and rejects model-picked sites',
      () {
    expect(
        advisorMarketImageUrl(const AdvisorCard(
            venue: 'hyperliquid',
            id: 'xyz:NVDA',
            imageUrl: 'https://app.hyperliquid.xyz/coins/xyz:NVDA.svg')),
        isNotNull);
    expect(
        advisorMarketImageUrl(const AdvisorCard(
            venue: 'polymarket',
            id: 'event',
            imageUrl:
                'https://polymarket-upload.s3.us-east-2.amazonaws.com/event.png')),
        isNotNull);
    for (final url in [
      'https://example.org/tracker.svg',
      'https://polymarket.com.evil.org/icon.svg',
      'data:image/svg+xml,fake'
    ]) {
      expect(
          advisorMarketImageUrl(
              AdvisorCard(venue: 'polymarket', id: 'event', imageUrl: url)),
          isNull);
    }
  });

  test('a perpetual card reads as the app writes its market stats', () {
    final l = l10nForLanguage('en');
    final card = AdvisorCard.tryParse({
      'venue': 'hyperliquid',
      'id': 'BTC',
      'instrument': 'crypto_perp',
      'asOf': '2026-10-07T10:00:00Z',
      'perp': {
        'markPx': 65000,
        'prevDayPx': 64000,
        'change24hPct': 1.56,
        'fundingHourly': 0.0000125,
        'fundingAnnualizedPct': 10.95,
        'openInterest': {'base': 1234.5, 'usd': 80000000},
        'volume24hUsd': 9e9,
        'maxLeverage': 40,
      },
    })!;
    final price = advisorCardPrice(card)!;
    expect(price.price, r'$65,000');
    expect(price.change, '+1.56%');
    expect(price.up, isTrue);
    expect([
      for (final r in advisorCardRows(card, l)) (r.label, r.value)
    ], [
      (l.hlFunding, '+0.0013%'),
      (l.hlOpenInterest, r'$80.0M'),
      (l.hl24hVolume, r'$9.0B'),
      (l.chartMaxLeverage, '40×'),
    ]);
  });

  test('a prediction card reads its game, outcomes with the day and close', () {
    final l = l10nForLanguage('en');
    final card = AdvisorCard.tryParse({
      'venue': 'polymarket',
      'id': 'ars-che',
      'slug': 'ars-che',
      'instrument': 'prediction',
      'asOf': '2026-10-07T10:00:00Z',
      'closesAt': '2026-10-07T21:00:00Z',
      'outcomes': [
        {'id': 'Yes', 'label': 'Yes', 'price': 0.61, 'delta24h': 0.04},
        {'id': 'No', 'label': 'No', 'price': 0.39, 'delta24h': -0.04},
        {'id': 'bad', 'label': 'Bad', 'price': 1.4},
      ],
      'live': {
        'state': 'live',
        'home': 'Arsenal',
        'away': 'Chelsea',
        'score': '1-0',
        'period': '2H',
        'elapsed': "46'",
      },
    })!;
    expect(advisorCardPrice(card), isNull);
    final rows = advisorCardRows(card, l);
    expect([
      for (final r in rows) (r.label, r.value, r.move, r.up)
    ], [
      (l.liveBadge, "Arsenal 1-0 Chelsea · 2H · 46'", null, null),
      ('Yes', '61%', '+4%', true),
      ('No', '39%', '−4%', false),
      (l.polyStatEnds, '7 Oct 2026, 21:00 UTC', null, null),
    ]);
    final ended = AdvisorCard.tryParse({
      'venue': 'polymarket',
      'id': 'x',
      'live': {'state': 'ended', 'score': '2-1'},
    })!;
    expect(advisorCardRows(ended, l).single.value, '2-1');
  });

  test('keeps disclosure calendar dates separate from freshness timestamps',
      () {
    expect(advisorDisplayDate('2026-09-14'), '14 Sep 2026');
    expect(advisorDisplayDate('2026-09-14T00:00:00+10:00'), '14 Sep 2026');
    expect(advisorDisplayDate('2026-09-14T10:32:00Z', includeTime: true),
        '14 Sep 2026, 10:32 UTC');
    expect(advisorDisplayDate('Not disclosed'), 'Not disclosed');
  });

  test('opens only the exact verified Hyperliquid wire coin', () {
    expect(
        advisorMarketAction(marketBlock(
                stock, 'open_hl_market', {'coin': 'xyz:NVDA', 'kind': 'perp'}))
            ?.label,
        'View market');
    expect(
        advisorMarketAction(marketBlock(
            stock, 'open_hl_market', {'coin': 'NVDA', 'kind': 'perp'})),
        isNull);
    expect(
        advisorMarketAction(marketBlock(
            stock, 'open_hl_market', {'coin': 'xyz:TSLA', 'kind': 'perp'})),
        isNull);
    expect(
        advisorMarketAction(marketBlock(stock, 'open_hl_market',
            {'coin': 'xyz:NVDA', 'kind': 'perp', 'side': 'buy'})),
        isNull);
    expect(
        advisorMarketAction(marketBlock(stock, 'open_hl_market',
            {'coin': 'xyz:NVDA', 'kind': 'perp', 'amountUsd': 10})),
        isNull);
  });

  test('rejects ambiguous or mismatched Hyperliquid product kinds', () {
    for (final kind in ['stock', 'spot', '']) {
      expect(
          advisorMarketAction(marketBlock(
              stock, 'open_hl_market', {'coin': 'xyz:NVDA', 'kind': kind})),
          isNull);
    }
  });

  test('prediction navigation never guesses a side or opens a bet slip', () {
    expect(
        advisorMarketAction(marketBlock(prediction, 'open_market_by_slug',
            {'slug': 'exact-event-slug'}))?.params,
        {'slug': 'exact-event-slug'});
    expect(
        advisorMarketAction(marketBlock(
            prediction, 'open_market_by_slug', {'slug': 'different-slug'})),
        isNull);
    expect(
        advisorMarketAction(marketBlock(prediction, 'open_bet_slip',
            {'slug': 'exact-event-slug', 'outcomeName': 'Yes'})),
        isNull);
    expect(
        advisorMarketAction(marketBlock(prediction, 'open_market_by_slug',
            {'slug': 'exact-event-slug', 'outcomeName': 'Yes'})),
        isNull);
  });

  test('labels stock perpetual contracts distinctly from spot products', () {
    // Product words only: Investing and Predictions, never the venue or the
    // contract type, and a stock-linked listing never reads as shares.
    expect(advisorInstrumentLabel(stock, 'stocks'),
        'Stock-linked Investing market');
    expect(
        advisorInstrumentLabel(
            const AdvisorCard(
                venue: 'hyperliquid', id: 'xyz:NVDA', instrument: 'stock_spot'),
            'stocks'),
        'Stock-linked spot market');
    expect(
        advisorInstrumentLabel(
            const AdvisorCard(
                venue: 'hyperliquid', id: 'BTC', instrument: 'crypto_perp'),
            'crypto_perps'),
        'Crypto Investing market');
    expect(advisorInstrumentLabel(prediction, 'predictions'),
        'Predictions market');
  });

  test('a Sal card names the jurisdiction gate it answers to', () {
    expect(advisorMarketGateCapability(stock, null), 'hyperliquid.stocks');
    expect(
        advisorMarketGateCapability(
            const AdvisorCard(
                venue: 'hyperliquid',
                id: 'xyz:TSLA',
                instrument: 'crypto_perp'),
            'stocks'),
        'hyperliquid.stocks');
    expect(
        advisorMarketGateCapability(
            const AdvisorCard(
                venue: 'hyperliquid',
                id: 'xyz:TSLA',
                instrument: 'crypto_perp',
                category: 'stocks'),
            null),
        'hyperliquid.stocks');
    expect(
        advisorMarketGateCapability(
            const AdvisorCard(
                venue: 'hyperliquid', id: 'BTC', instrument: 'crypto_perp'),
            'crypto_perps'),
        isNull);
    expect(
        advisorMarketGateCapability(
            const AdvisorCard(
                venue: 'hyperliquid', id: 'TSLA', instrument: 'stock_spot'),
            'stocks'),
        isNull,
        reason: 'a spot token is not a perpetual');
    expect(advisorMarketGateCapability(prediction, 'predictions'), isNull);
    expect(
        advisorMarketGateCapability(
            const AdvisorCard(
                venue: 'polymarket', id: 'nba-finals', category: 'sports'),
            'predictions'),
        'polymarket.sports');
    expect(
        advisorMarketGateCapability(
            const AdvisorCard(
                venue: 'polymarket', id: 'midterms', category: 'politics'),
            'predictions'),
        'polymarket.politics');
  });

  test('source links are HTTPS public hostnames without embedded credentials',
      () {
    expect(advisorSourceUri('https://disclosures-clerk.house.gov/'), isNotNull);
    expect(advisorSourceUri('https://example.org/research?q=NVDA'), isNotNull);
    const rejected = [
      'javascript:alert(1)',
      'data:text/html,hello',
      'file:///private/secret',
      'http://example.com',
      'https://user:password@example.com',
      'https://localhost',
      'https://private.local',
      'https://private.internal',
      'https://127.0.0.1',
      'https://192.168.0.1',
      'https://[::1]',
      'https://example.com:8443',
    ];
    for (final value in rejected) {
      expect(advisorSourceUri(value), isNull, reason: value);
    }
  });
}
