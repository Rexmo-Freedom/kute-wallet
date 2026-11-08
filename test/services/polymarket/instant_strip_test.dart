// The Instant card's strip of rounds (instant_strip.dart): which rounds it
// shows, which can be picked, which the buttons bet on by default and how
// long a pick stands; the round slugs of every length (crypto_round.dart)
// and the chart's backfill join (polymarket_price_source.dart).

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/services/polymarket/crypto_round.dart';
import 'package:kute/services/polymarket/crypto_window_results.dart';
import 'package:kute/services/polymarket/instant_strip.dart';
import 'package:kute/services/polymarket/polymarket_price_source.dart';
import 'package:kute/services/polymarket_clob_websocket.dart';

final _live = DateTime.utc(2026, 11, 8, 12, 0);
int _epoch(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

Btc5MinEvent _window(int start, String tokens, {int minutes = 5}) =>
    Btc5MinEvent(
      slug: polyCryptoRoundSlug('btc', minutes, start),
      title: 'Bitcoin Up or Down',
      windowStartTime:
          DateTime.fromMillisecondsSinceEpoch(start * 1000, isUtc: true),
      endDate: DateTime.fromMillisecondsSinceEpoch(
          (start + minutes * 60) * 1000,
          isUtc: true),
      upPrice: 0.5,
      downPrice: 0.5,
      upTokenId: '$tokens-up',
      downTokenId: '$tokens-down',
    );

/// The feed's books, seeded by the test ([_quote]) and read as the card
/// reads them: a current snapshot or nothing.
final _books = PolymarketLiveBooks.instance;

void _quote(String token, double bid, double ask) =>
    _books.debugSeed(PolymarketBookMessage(
      assetId: token,
      market: 'm',
      timestamp: 0,
      hash: '',
      bids: [PolymarketOrderSummary(price: bid, size: 500)],
      asks: [PolymarketOrderSummary(price: ask, size: 500)],
    ));

void main() {
  group('slugs', () {
    test('every length as Gamma names it', () {
      expect(polyCryptoRoundSlug('BTC', 5, 1794153900),
          'btc-updown-5m-1794153900');
      expect(polyCryptoRoundSlug('btc', 15, 1794153600),
          'btc-updown-15m-1794153600');
      expect(polyCryptoRoundSlug('ETH', 240, 1794157200),
          'eth-updown-4h-1794157200');
      // The hourly rounds: the coin's name and the New York clock (EST on
      // 8 November 2026: 18:00Z is 1 PM).
      expect(polyCryptoRoundSlug('BTC', 60, 1794160800),
          'bitcoin-up-or-down-november-8-2026-1pm-et');
      expect(polyCryptoRoundSlug('bitcoin', 60, 1794160800),
          'bitcoin-up-or-down-november-8-2026-1pm-et');
      expect(polyCryptoRoundSlug('XRP', 60, 1794160800),
          'xrp-up-or-down-november-8-2026-1pm-et');
      expect(polyCryptoRoundSlug('DOGE', 60, 1794160800),
          'dogecoin-up-or-down-november-8-2026-1pm-et');
      // Midnight and noon write 12.
      expect(polyCryptoRoundSlug('BTC', 60, _epoch(DateTime.utc(2026, 11, 9, 5))),
          'bitcoin-up-or-down-november-9-2026-12am-et');
      expect(polyCryptoRoundSlug('BTC', 60, _epoch(DateTime.utc(2026, 11, 9, 17))),
          'bitcoin-up-or-down-november-9-2026-12pm-et');
      // Daylight time: 4 July 2026 at 17:00Z is 1 PM EDT.
      expect(polyCryptoRoundSlug('BTC', 60, _epoch(DateTime.utc(2026, 7, 4, 17))),
          'bitcoin-up-or-down-july-4-2026-1pm-et');
    });

    test('New York\'s offset switches on the right Sundays', () {
      expect(polyEasternOffsetHours(DateTime.utc(2026, 3, 8, 6, 59)), -5);
      expect(polyEasternOffsetHours(DateTime.utc(2026, 3, 8, 7)), -4);
      expect(polyEasternOffsetHours(DateTime.utc(2026, 11, 1, 5, 59)), -4);
      expect(polyEasternOffsetHours(DateTime.utc(2026, 11, 1, 6)), -5);
      expect(polyEasternOffsetHours(DateTime.utc(2027, 3, 14, 7)), -4);
    });

    test('a slug written is a round read back, every length', () {
      for (final minutes in [5, 15, 240]) {
        final start = _epoch(_live) ~/ (minutes * 60) * (minutes * 60);
        final round = polyCryptoRoundOf(polyCryptoRoundSlug('btc', minutes, start));
        expect(round!.window, Duration(minutes: minutes));
        expect(_epoch(round.start), start);
      }
      final hourly = polyCryptoRoundOf(polyCryptoRoundSlug('BTC', 60, _epoch(_live)),
          endDate: _live.add(const Duration(hours: 1)));
      expect(hourly!.window, const Duration(hours: 1));
      expect(hourly.start, _live);
      expect(hourly.asset, 'bitcoin');
    });

    test('the results strip writes the same slugs', () {
      expect(cryptoWindowSlugAt('btc', 240, 1794157200),
          'btc-updown-4h-1794157200');
      expect(cryptoWindowSlugAt('btc', 60, 1794160800),
          'bitcoin-up-or-down-november-8-2026-1pm-et');
    });

    test('rounds start on every multiple of their length', () {
      final at = DateTime.utc(2026, 11, 8, 12, 7, 30);
      expect(polyRoundStartAt(at, 5), _epoch(DateTime.utc(2026, 11, 8, 12, 5)));
      expect(polyRoundStartAt(at, 15), _epoch(DateTime.utc(2026, 11, 8, 12)));
      expect(polyRoundStartAt(at, 60), _epoch(DateTime.utc(2026, 11, 8, 12)));
      expect(polyRoundStartAt(at, 240), _epoch(DateTime.utc(2026, 11, 8, 12)));
      expect(polyRoundStartAt(DateTime.utc(2026, 11, 8, 15, 59), 240),
          _epoch(DateTime.utc(2026, 11, 8, 12)));
    });
  });

  group('the strip', () {
    final liveStart = _epoch(_live);
    final next = liveStart + 300;
    final later = liveStart + 600;
    final past = [
      CryptoWindowResult(liveStart - 1200, true),
      CryptoWindowResult(liveStart - 900, false),
      CryptoWindowResult(liveStart - 600, true),
      CryptoWindowResult(liveStart - 300, null),
    ];

    setUp(() {
      _books
        ..reset()
        ..clock = () => _live.add(const Duration(minutes: 1));
    });
    tearDown(_books.reset);

    List<PolyStripRound> strip({
      DateTime? now,
      Map<int, Btc5MinEvent?>? ahead,
      Map<String, (double, double)> books = const {},
      Set<String> held = const {},
    }) {
      _books.reset();
      books.forEach((t, q) => _quote(t, q.$1, q.$2));
      return polyInstantStrip(
        asset: 'BTC',
        minutes: 5,
        now: now ?? _live.add(const Duration(minutes: 1)),
        past: past,
        ahead: ahead ?? {next: _window(next, 'next'), later: null},
        books: _books.snapshot,
        heldSlugs: held,
      );
    }

    test('four results, the round in play, the next and one after', () {
      final rounds = strip();
      expect(rounds.map((r) => r.slot), [
        PolyRoundSlot.past,
        PolyRoundSlot.past,
        PolyRoundSlot.past,
        PolyRoundSlot.past,
        PolyRoundSlot.live,
        PolyRoundSlot.next,
        PolyRoundSlot.later,
      ]);
      expect(rounds.map((r) => r.start),
          [...past.map((p) => p.startEpoch), liveStart, next, later]);
      expect(rounds[3].result, isNull, reason: 'still settling');
      expect(rounds[0].result, isTrue);
      expect(rounds[4].selectable, isTrue, reason: 'the round in play');
    });

    test('a round ahead is picked only with real prices on both sides', () {
      // Listed, no book: no prices yet.
      expect(strip().where((r) => r.slot == PolyRoundSlot.next).single.selectable,
          isFalse);
      // Both books, 1¢ wide: real.
      final priced = strip(books: {
        'next-up': (0.50, 0.51),
        'next-down': (0.49, 0.50),
      });
      expect(priced.where((r) => r.slot == PolyRoundSlot.next).single.selectable,
          isTrue);
      // One side only, or a 12¢ book: not real.
      expect(
          strip(books: {'next-up': (0.50, 0.51)})
              .where((r) => r.slot == PolyRoundSlot.next)
              .single
              .selectable,
          isFalse);
      expect(
          strip(books: {
            'next-up': (0.44, 0.56),
            'next-down': (0.44, 0.56),
          }).where((r) => r.slot == PolyRoundSlot.next).single.selectable,
          isFalse);
      // Gamma has nothing for the one after: never.
      expect(strip().last.selectable, isFalse);
      expect(strip().last.event, isNull);
    });

    test('a round the person holds carries the marker', () {
      final rounds = strip(held: {
        polyCryptoRoundSlug('btc', 5, liveStart),
        polyCryptoRoundSlug('btc', 5, liveStart - 600),
      });
      expect(rounds[4].held, isTrue);
      expect(rounds[2].held, isTrue);
      expect(rounds[5].held, isFalse);
    });

    test('the buttons follow the roll by default', () {
      final rounds = strip(books: {
        'next-up': (0.50, 0.51),
        'next-down': (0.49, 0.50),
      });
      final now = _live.add(const Duration(minutes: 1));
      expect(polyInstantSelectedStart(rounds: rounds, now: now), liveStart);
      expect(polyInstantSelectedStart(rounds: rounds, now: now, rolledStart: next),
          next);
      // A roll onto a round without prices cannot happen; the strip holds.
      expect(polyInstantSelectedStart(rounds: strip(), now: now, rolledStart: next),
          liveStart);
    });

    test('a pick stands until its round starts or ends, then the roll rules',
        () {
      final rounds = strip(books: {
        'next-up': (0.50, 0.51),
        'next-down': (0.49, 0.50),
      });
      // Picked Now while the roll says Next: Now, until it ends.
      final late = _live.add(const Duration(minutes: 2, seconds: 30));
      expect(
          polyInstantSelectedStart(
              rounds: rounds, now: late, picked: liveStart, rolledStart: next),
          liveStart);
      expect(
          polyInstantPickStands(liveStart,
              liveStart: liveStart, minutes: 5, now: late),
          isTrue);
      expect(
          polyInstantPickStands(liveStart,
              liveStart: liveStart,
              minutes: 5,
              now: _live.add(const Duration(minutes: 5))),
          isFalse);
      // Picked Next while early: Next, until it starts.
      final early = _live.add(const Duration(minutes: 1));
      expect(polyInstantSelectedStart(rounds: rounds, now: early, picked: next),
          next);
      expect(polyInstantPickStands(next, liveStart: liveStart, minutes: 5, now: early),
          isTrue);
      expect(
          polyInstantPickStands(next,
              liveStart: liveStart,
              minutes: 5,
              now: _live.add(const Duration(minutes: 5))),
          isFalse);
      // A pick of a round that lost its prices falls back to the roll.
      expect(polyInstantSelectedStart(rounds: strip(), now: early, picked: next),
          liveStart);
      // A past round is never a pick.
      expect(
          polyInstantPickStands(liveStart - 300,
              liveStart: liveStart, minutes: 5, now: early),
          isFalse);
    });

    test('which round, for the event', () {
      final rounds = strip();
      expect(polyInstantWhich(rounds[4]), 'current');
      expect(polyInstantWhich(rounds[5]), 'next');
      expect(polyInstantWhich(rounds[6]), 'later');
    });

    test('the strip at other lengths is the same arithmetic', () {
      final rounds = polyInstantStrip(
        asset: 'ETH',
        minutes: 240,
        now: DateTime.utc(2026, 11, 8, 18, 30),
        past: const [],
        ahead: const {},
        books: (_) => null,
      );
      expect(rounds.map((r) => r.start), [
        _epoch(DateTime.utc(2026, 11, 8, 16)),
        _epoch(DateTime.utc(2026, 11, 8, 20)),
        _epoch(DateTime.utc(2026, 11, 9, 0)),
      ]);
      expect(rounds.first.selectable, isTrue);
      expect(rounds[1].selectable, isFalse);
    });
  });

  group('the chart\'s backfill', () {
    DateTime at(int s) => _live.add(Duration(seconds: s));
    test('older points go in front of the live series, never over it', () {
      final back = [at(0), at(1), at(2), at(3), at(4)];
      final live = [at(3), at(4), at(5)];
      expect(cryptoSeriesWithBackfill(back, live, at: (t) => t),
          [at(0), at(1), at(2), at(3), at(4), at(5)]);
      expect(cryptoSeriesWithBackfill(<DateTime>[], live, at: (t) => t), live);
      expect(cryptoSeriesWithBackfill(back, <DateTime>[], at: (t) => t), back);
      // A backfill that reaches no further back than the series adds nothing.
      expect(cryptoSeriesWithBackfill([at(3), at(4)], live, at: (t) => t), live);
    });
  });
}
