// The live round card's strip of rounds (crypto_round_strip.dart, the
// Instant card's of 8 November 2026): which rounds it shows, which can be
// picked, which the buttons bet on by default and how long a pick stands.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/services/polymarket/crypto_round.dart';
import 'package:kute/services/polymarket/crypto_window_results.dart';
import 'package:kute/services/polymarket/crypto_round_strip.dart';
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
      return polyRoundStrip(
        asset: 'BTC',
        minutes: 5,
        now: now ?? _live.add(const Duration(minutes: 1)),
        past: past,
        live: _window(liveStart, 'cur'),
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
      expect(
          strip().where((r) => r.slot == PolyRoundSlot.next).single.selectable,
          isFalse);
      // Both books, 1¢ wide: real.
      final priced = strip(books: {
        'next-up': (0.50, 0.51),
        'next-down': (0.49, 0.50),
      });
      expect(
          priced.where((r) => r.slot == PolyRoundSlot.next).single.selectable,
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
      expect(polyRoundSelectedStart(rounds: rounds, now: now), liveStart);
      expect(
          polyRoundSelectedStart(rounds: rounds, now: now, rolledStart: next),
          next);
      // A roll onto a round without prices cannot happen; the strip holds.
      expect(
          polyRoundSelectedStart(rounds: strip(), now: now, rolledStart: next),
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
          polyRoundSelectedStart(
              rounds: rounds, now: late, picked: liveStart, rolledStart: next),
          liveStart);
      expect(
          polyRoundPickStands(liveStart,
              liveStart: liveStart, minutes: 5, now: late),
          isTrue);
      expect(
          polyRoundPickStands(liveStart,
              liveStart: liveStart,
              minutes: 5,
              now: _live.add(const Duration(minutes: 5))),
          isFalse);
      // Picked Next while early: Next, until it starts.
      final early = _live.add(const Duration(minutes: 1));
      expect(polyRoundSelectedStart(rounds: rounds, now: early, picked: next),
          next);
      expect(
          polyRoundPickStands(next,
              liveStart: liveStart, minutes: 5, now: early),
          isTrue);
      expect(
          polyRoundPickStands(next,
              liveStart: liveStart,
              minutes: 5,
              now: _live.add(const Duration(minutes: 5))),
          isFalse);
      // A pick of a round that lost its prices falls back to the roll.
      expect(polyRoundSelectedStart(rounds: strip(), now: early, picked: next),
          liveStart);
      // A past round is never a pick.
      expect(
          polyRoundPickStands(liveStart - 300,
              liveStart: liveStart, minutes: 5, now: early),
          isFalse);
    });

    test('which round, for the event', () {
      final rounds = strip();
      expect(polyRoundPickWhich(rounds[4]), 'current');
      expect(polyRoundPickWhich(rounds[5]), 'next');
      expect(polyRoundPickWhich(rounds[6]), 'later');
    });

    test(
        'the strip at other lengths is the same arithmetic, on New York\'s clock',
        () {
      // 18:30Z on 8 November is 1:30 PM EST: the 12 PM–4 PM ET round
      // (`eth-updown-4h-1794157200`, 17:00Z, listed by Gamma), then 4 PM
      // (21:00Z) and 8 PM (01:00Z the next day).
      final live = _epoch(DateTime.utc(2026, 11, 8, 17));
      final rounds = polyRoundStrip(
        asset: 'ETH',
        minutes: 240,
        now: DateTime.utc(2026, 11, 8, 18, 30),
        past: const [],
        live: _window(live, 'cur', minutes: 240),
        ahead: const {},
        books: (_) => null,
      );
      expect(rounds.map((r) => r.start), [
        live,
        _epoch(DateTime.utc(2026, 11, 8, 21)),
        _epoch(DateTime.utc(2026, 11, 9, 1)),
      ]);
      expect(rounds.first.selectable, isTrue);
      expect(rounds[1].selectable, isFalse);
    });

    test('the round in play without Gamma\'s event cannot be picked', () {
      final rounds = polyRoundStrip(
        asset: 'BTC',
        minutes: 240,
        now: DateTime.utc(2026, 11, 8, 18, 30),
        past: const [],
        live: null,
        ahead: const {},
        books: (_) => null,
      );
      final live = rounds.firstWhere((r) => r.slot == PolyRoundSlot.live);
      expect(live.selectable, isFalse, reason: 'no event, no prices, no bet');
      expect(live.event, isNull);
      // Nothing to pick: the buttons stay on the round in play, and the
      // card gives them nothing to open.
      expect(
          polyRoundSelectedStart(
              rounds: rounds, now: DateTime.utc(2026, 11, 8, 18, 30)),
          live.start);
    });

    test('the round the card still shows leads the strip until it rolls', () {
      // A second past the round's end, the card still on it: the strip
      // stays on that round (its ended event cannot be picked) and the
      // next is still "next", so the buttons hold the roll's round.
      final after = _live.add(const Duration(minutes: 5, seconds: 1));
      _books.reset();
      _books.clock = () => after;
      _quote('next-up', 0.50, 0.51);
      _quote('next-down', 0.49, 0.50);
      final rounds = polyRoundStrip(
        asset: 'BTC',
        minutes: 5,
        now: after,
        past: const [],
        live: null,
        ahead: {next: _window(next, 'next'), later: null},
        books: _books.snapshot,
        shownStart: liveStart,
      );
      expect(rounds.map((r) => r.start), [liveStart, next, later]);
      expect(rounds.first.selectable, isFalse);
      expect(rounds[1].slot, PolyRoundSlot.next);
      expect(rounds[1].selectable, isTrue);
      expect(
          polyRoundSelectedStart(rounds: rounds, now: after, rolledStart: next),
          next);
    });
  });
}
