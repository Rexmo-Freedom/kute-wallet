// The title a Polymarket market is shown under (market_display_title.dart):
// founder, 7 November 2026, "Look here does not make sense, is the yes or
// no correct?" under "Will Russia invade a NATO country by...?", and a
// page, slip and PIN sheet titled only "December 31, 2026".

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_browse_provider.dart'
    show polymarketEventDetailsProvider, polymarketMarketHistoryProvider;
import 'package:kute/screens/share/cards/share_card_sources.dart'
    show ShareCardWatch, predictionCardFor;
import 'package:kute/screens/portfolio/components/position_rows.dart';
import 'package:kute/services/polymarket/market_display_title.dart';
import 'package:kute/services/polymarket/polymarket_feed_cache.dart';

const _russia = 'Will Russia invade a NATO country by...?';
const _q2025 = 'Will Russia invade a NATO country in 2025?';
const _qJun = 'Will Russia invade a NATO country by June 30, 2026?';
const _qSep = 'Will Russia invade a NATO country by September 30, 2026?';
const _qDec = 'Will Russia invade a NATO country by December 31, 2026?';

Map<String, dynamic> _market(String id, String question, String item,
        {required bool closed, required List<String> prices}) =>
    {
      'id': id,
      'question': question,
      'groupItemTitle': item,
      'conditionId': '0x$id',
      'outcomes': '["Yes", "No"]',
      'outcomePrices': jsonEncode(prices),
      'clobTokenIds': '["$id-yes", "$id-no"]',
      'bestBid': closed ? 0 : 0.02,
      'bestAsk': closed ? 0 : 0.021,
      'lastTradePrice': closed ? 0 : 0.0205,
      'active': true,
      'closed': closed,
      'acceptingOrders': !closed,
    };

Map<String, dynamic> _event(List<Map<String, dynamic>> markets,
        {String title = _russia}) =>
    {
      'id': '23784',
      'slug': 'will-russia-invade-a-nato-country-in-2025',
      'title': title,
      'endDate': '2027-01-01T00:00:00Z',
      'active': true,
      'closed': false,
      'markets': markets,
    };

/// Gamma's answer today: three deadlines settled, December 31, 2026 open.
Map<String, dynamic> _oneOpenLeft() => _event([
      _market('m2025', _q2025, 'December 31, 2025',
          closed: true, prices: ['0', '1']),
      _market('mjun', _qJun, 'June 30, 2026', closed: true, prices: ['0', '1']),
      _market('msep', _qSep, 'September 30, 2026',
          closed: true, prices: ['0', '1']),
      _market('mdec', _qDec, 'December 31, 2026',
          closed: false, prices: ['0.0205', '0.9795']),
    ]);

/// Earlier in the year: two deadlines still open.
Map<String, dynamic> _twoOpen() => _event([
      _market('m2025', _q2025, 'December 31, 2025',
          closed: true, prices: ['0', '1']),
      _market('mjun', _qJun, 'June 30, 2026',
          closed: false, prices: ['0.012', '0.988']),
      _market('mdec', _qDec, 'December 31, 2026',
          closed: false, prices: ['0.0205', '0.9795']),
    ]);

PolymarketEvent _parse(Map<String, dynamic> raw) =>
    PolymarketModel().parseEventsRaw([raw]).single;

void main() {
  group('polyMarketDisplayTitle', () {
    test('Polymarket\'s blank is found in its shapes', () {
      for (final t in [
        _russia,
        'Fed decision in ...?',
        '...?',
        'Trump out as President by…?',
        'Bitcoin above ___ on November 7?',
      ]) {
        expect(polyTitleHasPlaceholder(t), isTrue, reason: t);
      }
      expect(polyTitleHasPlaceholder('Will it rain tomorrow?'), isFalse);
      expect(polyTitleHasPlaceholder('Fed decision in December?'), isFalse);
    });

    test('one market: its own question, whatever the event says', () {
      expect(
          polyMarketDisplayTitle(_russia,
              question: _qDec, itemTitle: 'December 31, 2026'),
          _qDec);
      expect(polyMarketDisplayTitle(_russia, question: _q2025), _q2025);
    });

    test('no question: the blank filled from the groupItemTitle', () {
      expect(polyMarketDisplayTitle(_russia, itemTitle: 'December 31, 2026'),
          _qDec);
      expect(
          polyMarketDisplayTitle('Fed decision in ...?', itemTitle: 'December'),
          'Fed decision in December?');
      expect(
          polyMarketDisplayTitle('Bitcoin above ___ on November 7?',
              itemTitle: '110,000'),
          'Bitcoin above 110,000 on November 7?');
    });

    test('the event alone: its blank taken out with the word before it', () {
      expect(polyMarketDisplayTitle(_russia),
          'Will Russia invade a NATO country?');
      expect(polyMarketDisplayTitle('Fed decision in ...?'), 'Fed decision?');
      expect(polyMarketDisplayTitle('Will it rain tomorrow?'),
          'Will it rain tomorrow?');
    });

    test('a bare groupItemTitle is never the title on its own', () {
      // With the question: the question.
      expect(
          polyMarketDisplayTitle('December 31, 2026',
              question: _qDec, itemTitle: 'December 31, 2026'),
          _qDec);
      // Without: the event's title says what the name is for.
      final named = polyMarketDisplayTitle('Brazil Presidential Election',
          itemTitle: 'Lula da Silva');
      expect(named, 'Brazil Presidential Election: Lula da Silva');
      expect(
          polyMarketDisplayTitle('Who will win the 2026 World Cup?',
              itemTitle: 'Argentina'),
          'Who will win the 2026 World Cup?: Argentina');
      // A game's title names both teams: the one picked still follows.
      expect(polyMarketDisplayTitle('Lions vs Tigers', itemTitle: 'Tigers'),
          'Lions vs Tigers: Tigers');
      for (final t in [named, _qDec]) {
        expect(t, isNot('December 31, 2026'));
        expect(polyTitleHasPlaceholder(t), isFalse);
      }
    });
  });

  group('a grouped event as Gamma sends it', () {
    test(
        'three deadlines settled, one open: the event IS that market, titled '
        'by its question, priced and traded on it alone', () {
      final e = _parse(_oneOpenLeft());
      // Gamma's own title is kept for the logic that reads it.
      expect(e.title, _russia);
      expect(e.marketQuestion, _qDec);
      expect(e.displayTitle, _qDec);
      expect(polyTitleHasPlaceholder(e.displayTitle), isFalse);
      // The closed siblings drive nothing: the chance, the chart's token
      // and the trade buttons are the open market's.
      expect(e.isBinary, isTrue);
      expect(e.yesPrice, closeTo(0.0205, 1e-9));
      expect(e.noPrice, closeTo(0.9795, 1e-9));
      expect(e.yesTokenId, 'mdec-yes');
      expect(e.noTokenId, 'mdec-no');
      expect(e.conditionId, '0xmdec');
      expect(e.outcomes.map((o) => o.conditionId).toSet(), {'0xmdec'});
      expect(e.endDate, DateTime.utc(2027, 1, 1));
    });

    test(
        'several deadlines open: the event\'s title without its blank, each '
        'outcome carrying its own question', () {
      final e = _parse(_twoOpen());
      expect(e.marketQuestion, isNull);
      expect(e.displayTitle, 'Will Russia invade a NATO country?');
      expect(e.outcomes.map((o) => o.name),
          ['June 30, 2026', 'December 31, 2026']);
      expect(e.outcomes.map((o) => o.question), [_qJun, _qDec]);
      // The settled 2025 market is not an outcome to trade.
      expect(e.outcomes.any((o) => o.conditionId == '0xm2025'), isFalse);
      // One outcome picked: its own question, never its bare name.
      final dec = e.outcomes.last;
      expect(
          polyMarketDisplayTitle(e.title,
              question: dec.question, itemTitle: dec.name),
          _qDec);
    });

    test('a plain single-market event keeps the event\'s title', () {
      final e = _parse({
        'id': '1',
        'slug': 'bitcoin-150k-2026',
        'title': r'Will Bitcoin reach $150,000 in 2026?',
        'active': true,
        'closed': false,
        'markets': [
          {
            'id': 'btc',
            'question': r'Will Bitcoin reach $150,000 by December 31, 2026?',
            'conditionId': '0xbtc',
            'outcomes': '["Yes", "No"]',
            'outcomePrices': '["0.18", "0.82"]',
            'clobTokenIds': '["btc-yes", "btc-no"]',
            'active': true,
            'closed': false,
          },
        ],
      });
      expect(e.marketQuestion, isNull);
      expect(e.displayTitle, r'Will Bitcoin reach $150,000 in 2026?');
      expect(e.yesPrice, closeTo(0.18, 1e-9));
    });

    test('the feed cache keeps the one market\'s question', () {
      for (final raw in [_oneOpenLeft(), _twoOpen()]) {
        final e = _parse(raw);
        final back = PolymarketFeedCache.eventFromJson(
            jsonDecode(jsonEncode(PolymarketFeedCache.eventToJson(e)))
                as Map<String, dynamic>);
        expect(back.displayTitle, e.displayTitle);
        expect(back.outcomes.map((o) => o.question),
            e.outcomes.map((o) => o.question));
      }
    });
  });

  group('the share card says what the page says', () {
    Future<ShareCardWatch> watcher(PolymarketEvent event) async {
      final container = ProviderContainer(overrides: [
        polymarketEventDetailsProvider.overrideWith((ref, slug) async => event),
        polymarketMarketHistoryProvider
            .overrideWith((ref, key) async => const []),
      ]);
      addTearDown(container.dispose);
      container.listen(polymarketEventDetailsProvider(event.slug), (_, __) {});
      await container.read(polymarketEventDetailsProvider(event.slug).future);
      return <T>(ProviderListenable<T> p) => container.read(p);
    }

    test('one open deadline left: the market card and a pick on it', () async {
      final e = _parse(_oneOpenLeft());
      final watch = await watcher(e);
      final market = predictionCardFor(watch, slug: e.slug, title: _russia);
      expect(market.question, _qDec);
      final pick = predictionCardFor(watch,
          slug: e.slug, title: _qDec, outcome: 'Yes', picked: true);
      expect(pick.question, _qDec);
      expect(pick.outcome, 'Yes');
    });

    test(
        'several open: the event\'s name for the market, a picked deadline\'s '
        'own question for the pick', () async {
      final e = _parse(_twoOpen());
      final watch = await watcher(e);
      final market = predictionCardFor(watch, slug: e.slug, title: _russia);
      expect(market.question, 'Will Russia invade a NATO country?');
      final pick = predictionCardFor(watch,
          slug: e.slug,
          title: _qDec,
          outcome: 'December 31, 2026',
          picked: true);
      expect(pick.question, _qDec);
      expect(pick.outcome, 'December 31, 2026');
    });
  });

  group('position rows of a grouped event', () {
    test('the one open market held: its deadline, never "by..."', () {
      final names = polyPositionRowNames(
        question: _qDec,
        side: 'Yes',
        marketId: '0xmdec',
        tokenId: 'mdec-yes',
        event: _parse(_oneOpenLeft()),
      );
      expect(names.title, 'Russia invade a NATO country by December 31, 2026');
      expect(polyPositionRowLine(names, 'Yes'), 'Yes');
    });

    test('a deadline of several held: the question, not the bare date', () {
      final names = polyPositionRowNames(
        question: _qJun,
        side: 'No',
        marketId: '0xmjun',
        tokenId: 'mjun-no',
        event: _parse(_twoOpen()),
      );
      expect(names.title, 'Russia invade a NATO country by June 30, 2026');
      expect(polyPositionRowLine(names, 'No'), 'No');
    });

    test('a settled sibling held: its own question, never the open one', () {
      final names = polyPositionRowNames(
        question: _q2025,
        side: 'No',
        marketId: '0xm2025',
        tokenId: 'm2025-no',
        event: _parse(_oneOpenLeft()),
      );
      expect(names.title, 'Russia invade a NATO country in 2025');
      final line = polyPositionRowLine(names, 'No', status: 'Settled');
      expect(line, 'No · Settled');
      expect(line, isNot(contains('...')));
    });
  });
}
