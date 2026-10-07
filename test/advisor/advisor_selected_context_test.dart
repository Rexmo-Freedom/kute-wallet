import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart' show l10nForLanguage;
import 'package:kute/models/advisor_context.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/services/advisor/advisor_service.dart';
import 'package:kute/services/advisor/sal_chip_catalogue.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final en = l10nForLanguage('en');

  test('spot display names stay local while requests retain the exact market',
      () async {
    const context = AdvisorContext(
      surface: 'hl_order_slip',
      marketVenue: 'hyperliquid',
      marketId: '@288',
      marketDisplayName: 'EXAMPLE',
      orderType: 'limit',
    );
    final chips = SalChipCatalogue.select(context, en).map((c) => c.text);
    expect(chips.join(' '), contains('EXAMPLE'));
    expect(chips.join(' '), isNot(contains('@288')));
    expect(SalChipCatalogue.introduction(context, en), isNot(contains('@288')));
    final body = await const AdvisorRequest(
      query: 'How does this order work?',
      context: context,
    ).toJson();
    expect(body['market'], {'venue': 'hyperliquid', 'id': '@288'});
    expect(jsonEncode(body), isNot(contains('EXAMPLE')));
    expect(
      const AdvisorContext(
        surface: 'hl_market_detail',
        marketVenue: 'hyperliquid',
        marketId: '@288',
      ).publicMarketLabel,
      isNull,
    );
  });

  test('Stop Market context carries only public market and educational enum',
      () async {
    const context = AdvisorContext(
        surface: 'hl_order_slip',
        marketVenue: 'hyperliquid',
        marketId: 'xyz:XYZ100',
        orderType: 'stop_market');
    final body = await const AdvisorRequest(
            query: 'How does this order work?', context: context)
        .toJson();
    expect(body, {
      'schemaVersion': '3',
      'query': 'How does this order work?',
      'market': {'venue': 'hyperliquid', 'id': 'xyz:XYZ100'},
      'education': {'orderType': 'stop_market'},
    });
    final first = SalChipCatalogue.select(context, en).first;
    expect(first.template, 'edu.limit_order');
    expect(first.text, contains('stop market'));
    expect(first.text, contains('XYZ100'));
    expect(SalChipCatalogue.introduction(context, en), contains('stop market'));
    for (final field in [
      'surface',
      'side',
      'margin',
      'leverage',
      'balance',
      'wallet'
    ]) {
      expect(jsonEncode(body), isNot(contains('"$field"')));
    }
  });

  test('educational hints reject arbitrary values and incompatible order types',
      () {
    for (final type in ['20x', 'long', 'isolated', 'my private order']) {
      expect(
          AdvisorContext(
                  surface: 'hl_order_slip',
                  marketVenue: 'hyperliquid',
                  marketId: 'BTC',
                  orderType: type)
              .toRequestEducation,
          isNull);
    }
    for (final type in [
      'market',
      'limit',
      'stop_market',
      'stop_limit',
      'take_profit_market',
      'take_profit_limit',
      'scale',
      'twap'
    ]) {
      expect(
          AdvisorContext(
                  surface: 'hl_order_slip',
                  marketVenue: 'hyperliquid',
                  marketId: 'BTC',
                  orderType: type)
              .toRequestEducation,
          {'orderType': type});
    }
    expect(
        const AdvisorContext(surface: 'chat', orderType: 'limit')
            .toRequestEducation,
        isNull);
    expect(
        const AdvisorContext(
                surface: 'hl_order_slip',
                marketVenue: 'hyperliquid',
                marketId: '@142',
                orderType: 'stop_market')
            .toRequestEducation,
        isNull);
  });

  test('public Gamma child identity survives parsing without a selected side',
      () async {
    final model = PolymarketModel();
    final events = model.parseEventsRaw([
      {
        'id': 'event-fixture',
        'slug': 'chelsea-brentford',
        'title': 'Chelsea vs Brentford',
        'markets': [
          {
            'id': '4237404',
            'question': 'Will Brentford win?',
            'outcomes': ['Yes', 'No'],
            'outcomePrices': ['0.4', '0.6'],
            'clobTokenIds': ['101', '102']
          },
          {
            'id': '4237425',
            'question': 'Will Chelsea win?',
            'outcomes': ['Yes', 'No'],
            'outcomePrices': ['0.5', '0.5'],
            'clobTokenIds': ['201', '202']
          },
        ]
      }
    ]);
    expect(events.single.outcomes.map((o) => o.gammaMarketId),
        ['4237404', '4237425']);
    final selected = events.single.outcomes.last;
    final body = await AdvisorRequest(
            query: 'What are the resolution rules?',
            context: AdvisorContext(
                surface: 'bet_slip',
                marketVenue: 'polymarket',
                marketId: events.single.slug,
                submarketId: selected.gammaMarketId))
        .toJson();
    expect(body['market'], {
      'venue': 'polymarket',
      'id': 'chelsea-brentford',
      'submarketId': '4237425'
    });
    expect(body.keys, isNot(contains('side')));
    expect(jsonEncode(body), isNot(contains('tokenId')));
    expect(
        const AdvisorContext(
                surface: 'bet_slip',
                marketVenue: 'polymarket',
                marketId: 'chelsea-brentford',
                submarketId: '0x123456')
            .toRequestMarket,
        {'venue': 'polymarket', 'id': 'chelsea-brentford'});
  });
}
