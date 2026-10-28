// Hide only what is actually closed: an event leaves the lists on Gamma's
// flags (closed, active:false, ended, every market closed or not accepting
// orders), never on a past end date or a lopsided price.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/services/polymarket/event_trading_over.dart';

final _pastDate = DateTime.utc(2026, 10, 5, 3, 59);

PolymarketEvent _event({
  bool closed = false,
  bool active = true,
  bool ended = false,
  bool marketsClosed = false,
  DateTime? endDate,
  String? score,
  String? period,
  List<PolymarketOutcome>? outcomes,
}) =>
    PolymarketEvent(
      id: 'brazil',
      slug: 'brazil-presidential-election',
      title: 'Brazil Presidential Election',
      volume: 180e6,
      liquidity: 2.6e6,
      category: 'politics',
      conditionId: 'c1',
      outcomes: outcomes ??
          const [
            PolymarketOutcome(name: 'Lula', price: 0.13, tokenId: 'a'),
            PolymarketOutcome(name: 'Flávio Bolsonaro', price: 0.87, tokenId: 'b'),
          ],
      endDate: endDate ?? _pastDate,
      closed: closed,
      active: active,
      ended: ended,
      marketsClosed: marketsClosed,
      score: score,
      period: period,
    );

Map<String, Object> _rawMarket(String id,
        {bool closed = false, bool? acceptingOrders, double? volumeNum}) =>
    {
      'id': id,
      'question': 'Will $id win?',
      'groupItemTitle': id,
      'conditionId': 'cond-$id',
      'active': true,
      'closed': closed,
      if (acceptingOrders != null) 'acceptingOrders': acceptingOrders,
      'outcomes': '["Yes","No"]',
      'outcomePrices': '["0.5","0.5"]',
      'clobTokenIds': '["y-$id","n-$id"]',
      if (volumeNum != null) 'volumeNum': volumeNum,
    };

void main() {
  group('polyTradingOver and the lists\' filter', () {
    test('a past end date with closed:false stays', () {
      final e = _event();
      expect(e.endDate!.isBefore(DateTime.now()), isTrue);
      expect(polyTradingOver(e, inPlay: false), isFalse);
      expect(debugPolyEventResolved(e), isFalse);
    });

    test('closed, switched off or ended goes', () {
      for (final e in [
        _event(closed: true),
        _event(active: false),
        _event(ended: true),
      ]) {
        expect(polyTradingOver(e, inPlay: false), isTrue);
        expect(debugPolyEventResolved(e), isTrue);
      }
    });

    test('every market closed goes; a game in play stays', () {
      final e = _event(marketsClosed: true);
      expect(polyTradingOver(e, inPlay: false), isTrue);
      expect(debugPolyEventResolved(e), isTrue);
      final live = _event(marketsClosed: true, score: '1-0', period: '2H');
      expect(live.isInPlay, isTrue);
      expect(debugPolyEventResolved(live), isFalse);
    });

    test('a 99/1 price never means closed', () {
      final e = _event(outcomes: const [
        PolymarketOutcome(name: 'Yes', price: 0.99, tokenId: 'a'),
        PolymarketOutcome(name: 'No', price: 0.01, tokenId: 'b'),
      ]);
      expect(debugPolyEventResolved(e), isFalse);
    });
  });

  group('raw Gamma markets', () {
    test('a missing acceptingOrders means open', () {
      expect(polyRawMarketTradable(_rawMarket('a')), isTrue);
      expect(polyRawMarketTradable(_rawMarket('a', acceptingOrders: true)),
          isTrue);
      expect(polyRawMarketTradable(_rawMarket('a', acceptingOrders: false)),
          isFalse);
      expect(polyRawMarketTradable(_rawMarket('a', closed: true)), isFalse);
      expect(polyRawMarketTradable('junk'), isFalse);
    });

    test('all closed only when every market is; never for no markets', () {
      expect(polyAllRawMarketsClosed(const []), isFalse);
      expect(polyAllRawMarketsClosed([_rawMarket('a'), _rawMarket('b', closed: true)]),
          isFalse);
      expect(
          polyAllRawMarketsClosed([
            _rawMarket('a', closed: true),
            _rawMarket('b', acceptingOrders: false),
          ]),
          isTrue);
    });

    test('an open event shows its tradable markets, a closed one all', () {
      final mixed = [_rawMarket('a', closed: true), _rawMarket('b')];
      expect(polyShownRawMarkets(mixed).map((m) => m['id']), ['b']);
      final allClosed = [
        _rawMarket('a', closed: true),
        _rawMarket('b', acceptingOrders: false)
      ];
      expect(polyShownRawMarkets(allClosed), same(allClosed));
    });

    test("a finished game's closed moneyline stays beside its open lines",
        () {
      final finished = [
        {..._rawMarket('ml', closed: true), 'sportsMarketType': 'moneyline'},
        {..._rawMarket('1h', closed: true), 'sportsMarketType': 'totals'},
        {..._rawMarket('2h'), 'sportsMarketType': 'second_half_spreads'},
      ];
      expect(polyShownRawMarkets(finished).map((m) => m['id']), ['ml', '2h']);
      expect(polyRawMarketIsGameWinner(finished.first), isTrue);
      expect(polyRawMarketTradable(finished.first), isFalse);
      // Every line closed: all kept, the game is over.
      final over = finished.sublist(0, 2);
      expect(polyShownRawMarkets(over), same(over));
    });
  });

  group('the feed parser', () {
    test('drops settled sub-markets, keeps the event total volume', () {
      final model = PolymarketModel();
      final rows = model.parseEventsRaw([
        {
          'id': '45915',
          'slug': 'brazil-presidential-election',
          'title': 'Brazil Presidential Election',
          'active': true,
          'closed': false,
          'endDate': '2026-10-05T03:59:00Z',
          'liquidity': 2672157.3,
          'volume': 180311064.7,
          'markets': [
            _rawMarket('Tarcisio', closed: true, acceptingOrders: false,
                volumeNum: 14e6),
            _rawMarket('Lula', acceptingOrders: true, volumeNum: 22e6),
            _rawMarket('Flavio', volumeNum: 19e6),
          ],
        },
      ]);
      model.dispose();
      final e = rows.single;
      expect(e.outcomes.map((o) => o.name), ['Lula', 'Flavio']);
      expect(e.conditionId, 'cond-Lula');
      expect(e.volume, 55e6);
      expect(e.marketsClosed, isFalse);
      expect(debugPolyEventResolved(e), isFalse);
    });

    test("uses the event's volume when the markets carry none; notes all closed",
        () {
      final model = PolymarketModel();
      final rows = model.parseEventsRaw([
        {
          'id': '1',
          'slug': 'done',
          'title': 'Done',
          'active': true,
          'closed': false,
          'volume': '1234.5',
          'markets': [
            _rawMarket('a', closed: true, acceptingOrders: false),
            _rawMarket('b', closed: true, acceptingOrders: false),
          ],
        },
      ]);
      model.dispose();
      final e = rows.single;
      expect(e.volume, 1234.5);
      expect(e.marketsClosed, isTrue);
      // A resolved event keeps its outcomes for a held position's detail.
      expect(e.outcomes, hasLength(2));
      expect(debugPolyEventResolved(e), isTrue);
    });
  });

  group('placeholder seats (Brazil: "Person O" … "Person Z", "Other")', () {
    // As Gamma sends them: switched off, never priced, a 0 bid and a 1 ask.
    Map<String, Object?> seat(String title) => {
          'id': title,
          'question': 'Will $title win?',
          'groupItemTitle': title,
          'conditionId': 'cond-$title',
          'active': false,
          'closed': false,
          'archived': false,
          'acceptingOrders': true,
          'enableOrderBook': true,
          'outcomes': '["Yes","No"]',
          'outcomePrices': null,
          'bestBid': 0,
          'bestAsk': 1,
          'lastTradePrice': 0,
          'clobTokenIds': '["y-$title","n-$title"]',
          'volumeNum': 0,
          'image': 'https://example.com/flag-br.png',
        };
    Map<String, Object?> priced(String title, double yes,
            {bool closed = false}) =>
        {
          'id': title,
          'question': 'Will $title win?',
          'groupItemTitle': title,
          'conditionId': 'cond-$title',
          'active': true,
          'closed': closed,
          'acceptingOrders': !closed,
          'outcomes': '["Yes","No"]',
          'outcomePrices': '["$yes","${1 - yes}"]',
          'bestBid': closed ? null : yes - 0.005,
          'bestAsk': closed ? 0.001 : yes + 0.005,
          'lastTradePrice': closed ? 0.001 : yes,
          'clobTokenIds': '["y-$title","n-$title"]',
          'volumeNum': 1e6,
          'image': 'https://example.com/$title.png',
        };

    test('a seat is a placeholder; a priced or settled market is not', () {
      expect(polyRawMarketPlaceholder(seat('Person O')), isTrue);
      expect(polyRawMarketPlaceholder(seat('Other')), isTrue);
      expect(polyRawMarketTradable(seat('Person O')), isFalse);
      expect(polyRawMarketPlaceholder(priced('Lula', 0.21)), isFalse);
      expect(
          polyRawMarketPlaceholder(priced('Tarcisio', 0, closed: true)), isFalse);
      // Archived goes too.
      expect(
          polyRawMarketPlaceholder({...priced('Old', 0.3), 'archived': true}),
          isTrue);
      // Switched on, but never priced and no prices at all.
      expect(polyRawMarketPlaceholder({...seat('Fresh'), 'active': true}),
          isTrue);
      // A generic name never priced, prices "0"/"1": still a seat.
      expect(
          polyRawMarketPlaceholder({
            ...seat('Person Q'),
            'active': true,
            'outcomePrices': '["0","1"]',
          }),
          isTrue);
      // An "Other" that trades is a real outcome.
      expect(
          polyRawMarketPlaceholder({...priced('Other', 0.04)}), isFalse);
      // A trimmed payload (no quote, no prices key) is not judged by
      // what it leaves out.
      expect(
          polyRawMarketPlaceholder({
            'id': 'x',
            'groupItemTitle': 'Lula',
            'active': true,
          }),
          isFalse);
    });

    test('an order book switched off cannot be traded', () {
      expect(
          polyRawMarketTradable({...priced('Lula', 0.2), 'enableOrderBook': false}),
          isFalse);
    });

    test('the lists drop the seats and the settled, keep the two open', () {
      final model = PolymarketModel();
      final rows = model.parseEventsRaw([
        {
          'id': '45915',
          'slug': 'brazil-presidential-election',
          'title': 'Brazil Presidential Election',
          'active': true,
          'closed': false,
          'markets': [
            priced('Tarcisio de Freitas', 0, closed: true),
            priced('Luiz Inácio Lula da Silva', 0.215),
            priced('Flávio Bolsonaro', 0.7885),
            for (final l in 'OPQRSTUVWXYZ'.split('')) seat('Person $l'),
            seat('Other'),
          ],
        },
      ]);
      model.dispose();
      final e = rows.single;
      expect(e.outcomes.map((o) => o.name),
          ['Luiz Inácio Lula da Silva', 'Flávio Bolsonaro']);
      expect(e.outcomes.every((o) => o.imageUrl != null), isTrue);
      expect(e.marketsClosed, isFalse);
      expect(e.hiddenOutcomes.map((o) => o.name),
          [for (final l in 'OPQRSTUVWXYZ'.split('')) 'Person $l', 'Other']);
      // Only seats are kept aside, never the settled candidate.
      expect(e.hiddenOutcomes.any((o) => o.name.startsWith('Tarcisio')),
          isFalse);
    });

    test('an outcome held is never hidden', () {
      final model = PolymarketModel();
      final e = model.parseEventsRaw([
        {
          'id': '1',
          'slug': 's',
          'title': 'Brazil Presidential Election',
          'active': true,
          'closed': false,
          'markets': [
            priced('Lula', 0.2),
            priced('Flávio', 0.79),
            seat('Person O'),
            seat('Person P'),
          ],
        },
      ]).single;
      model.dispose();
      expect(identical(e.withHeldOutcomes(const {}), e), isTrue);
      expect(identical(e.withHeldOutcomes({'y-Lula'}), e), isTrue);
      final held = e.withHeldOutcomes({'n-Person P'});
      expect(held.outcomes.map((o) => o.name),
          ['Lula', 'Flávio', 'Person P']);
      expect(held.hiddenOutcomes.map((o) => o.name), ['Person O']);
      expect(held.slug, e.slug);
      expect(held.title, e.title);
    });

    test('only seats left open: the event reads as over', () {
      final markets = [
        priced('Tarcisio', 0, closed: true),
        seat('Person O'),
      ];
      expect(polyAllRawMarketsClosed(markets), isTrue);
      // Resolved: the settled candidate shows, the seat does not.
      expect(polyShownRawMarkets(markets).map((m) => (m as Map)['id']),
          ['Tarcisio']);
    });
  });
}
