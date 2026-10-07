// The chart of a market almost nobody trades is drawn from a cleaned copy
// of its history: needles and combs out, real moves kept. The series are
// Polymarket's own, recorded on 2026-10-05 (test/fixtures/
// polymarket_history): two thin markets ($152 and $160 traded) and three
// liquid ones.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/services/polymarket/thin_history.dart';

List<double> _series(String name) => [
      for (final row in (jsonDecode(
              File('test/fixtures/polymarket_history/$name.json')
                  .readAsStringSync())['points'] as List))
        ((row as List)[1] as num).toDouble(),
    ];

/// Points that stand at least [by] from both neighbours, on one side.
int _needles(List<double> p, {double by = 0.08}) {
  var n = 0;
  for (var i = 1; i < p.length - 1; i++) {
    final a = p[i] - p[i - 1], b = p[i] - p[i + 1];
    if (a.abs() >= by && b.abs() >= by && (a > 0) == (b > 0)) n++;
  }
  return n;
}

void main() {
  group('which markets are thin', () {
    test('under \$5,000 traded in all; an unknown volume is not', () {
      expect(polyMarketIsThin(152), isTrue);
      expect(polyMarketIsThin(0), isTrue);
      expect(polyMarketIsThin(4999), isTrue);
      expect(polyMarketIsThin(5000), isFalse);
      expect(polyMarketIsThin(71647778), isFalse);
      expect(polyMarketIsThin(null), isFalse);
    });
  });

  group('which outcome of an event is thin', () {
    PolymarketEvent event(List<PolymarketOutcome> outcomes, double volume) =>
        PolymarketEvent(
          id: 'e',
          slug: 'e',
          title: 'E',
          volume: volume,
          liquidity: 0,
          category: 'crypto',
          conditionId: 'c',
          outcomes: outcomes,
        );

    test('by its own volume, else the event\'s', () {
      // ETH above 2,300: Gamma sends no volume key for a market that has
      // never traded; the event traded \$541 in all.
      final young = event(const [
        PolymarketOutcome(name: '2,200', price: 0.99, tokenId: 'a'),
        PolymarketOutcome(name: '2,300', price: 0.98, tokenId: 'b'),
      ], 541);
      expect(polyTokenIsThin(young, 'a'), isTrue);
      // A candidate with \$1,552 of its own under a \$170M election.
      final race = event(const [
        PolymarketOutcome(name: 'Zema', price: 0.0005, tokenId: 'z', volume: 1552),
        PolymarketOutcome(name: 'Lula', price: 0.155, tokenId: 'l', volume: 16463431),
        PolymarketOutcome(name: 'Other', price: 0.5, tokenId: 'o'),
      ], 170219785);
      expect(polyTokenIsThin(race, 'z'), isTrue);
      expect(polyTokenIsThin(race, 'l'), isFalse);
      expect(polyTokenIsThin(race, 'o'), isFalse);
      // A Yes/No market: the event's volume, also through the No token.
      final yesNo = event(const [
        PolymarketOutcome(name: 'Yes', price: 0.17, tokenId: 'y', noTokenId: 'n'),
        PolymarketOutcome(name: 'No', price: 0.83, tokenId: 'n'),
      ], 152);
      expect(polyTokenIsThin(yesNo, 'y'), isTrue);
      expect(polyTokenIsThin(yesNo, 'n'), isTrue);
      expect(polyTokenIsThin(yesNo, null), isFalse);
      expect(polyTokenIsThin(yesNo, 'other'), isFalse);
    });
  });

  group('spikes', () {
    test('a needle that comes straight back is taken out', () {
      // 17%, 30%, 17%: the quote jumped across the spread for one bucket.
      final out = despikePrices([0.17, 0.17, 0.175, 0.30, 0.17, 0.17, 0.175]);
      expect(out[3], closeTo(0.1725, 1e-9));
      expect(out.sublist(0, 3), [0.17, 0.17, 0.175]);
    });

    test('so is one two points long', () {
      final out =
          despikePrices([0.47, 0.47, 0.475, 0.26, 0.26, 0.47, 0.47, 0.47]);
      expect(out[3], closeTo(0.4733, 1e-3));
      expect(out[4], closeTo(0.4717, 1e-3));
    });

    test('a move that stays is a move: kept as it is', () {
      final shift = [0.50, 0.50, 0.495, 0.28, 0.27, 0.275, 0.26, 0.28];
      expect(despikePrices(shift), same(shift));
      // Three points away is not a spike either.
      final plateau = [0.2, 0.2, 0.2, 0.45, 0.45, 0.45, 0.2, 0.2, 0.2];
      expect(despikePrices(plateau), same(plateau));
    });

    test('a jump under eight points is left alone', () {
      final small = [0.40, 0.40, 0.40, 0.47, 0.40, 0.40, 0.40];
      expect(despikePrices(small), same(small));
    });

    test('on a line that swings that much anyway, a swing is not a spike',
        () {
      // 62% between two 50%s would be a twelve-point needle on a calm
      // line; here the points around it range over twenty-five.
      final wild = [
        0.30, 0.50, 0.35, 0.55, 0.30, 0.50, 0.62, 0.50, 0.30, 0.55, 0.35,
        0.50, 0.30,
      ];
      expect(despikePrices(wild)[6], 0.62);
    });

    test('the latest point is never touched; a stray first one is', () {
      final last = despikePrices([0.2, 0.2, 0.2, 0.2, 0.2, 0.6]);
      expect(last.last, 0.6);
      final first = despikePrices([0.30, 0.17, 0.17, 0.175, 0.17, 0.175]);
      expect(first.first, 0.17);
    });
  });

  group('the recorded thin markets', () {
    test('"5,000 passing yards", 1D: fifteen needles to 30% over a line at '
        '17%, none left', () {
      final raw = _series('thin_5000_passing_yards_1d');
      expect(_needles(raw), greaterThanOrEqualTo(10));
      final out = despikePrices(raw);
      expect(_needles(out), 0);
      // The line it sat on all day is where it was.
      expect(out.where((p) => p < 0.2).length,
          greaterThan(raw.where((p) => p < 0.2).length));
    });

    test('"Euro 2028", 1D: the three jumps to 55% and back are out, the '
        'rise that stayed is in', () {
      final raw = _series('thin_euro_2028_1d');
      final out = despikePrices(raw);
      expect(_needles(out), lessThan(_needles(raw)));
      // It ended the day well above where it started, before and after.
      expect(out.last, raw.last);
      expect(out.last - out.first, closeTo(raw.last - raw.first, 1e-9));
    });

    test('"Euro 2028", 1W: the comb is ironed out and no level is moved',
        () {
      final raw = _series('thin_euro_2028_1w');
      expect(priceTurnShare(raw), greaterThan(kPolyCombTurnShare));
      final out = decombPrices(despikePrices(raw));
      expect(priceTurnShare(out), lessThan(priceTurnShare(raw) * 0.6));
      // Nothing is invented: every value drawn is one the series had
      // near that point.
      for (var i = 2; i < raw.length - 2; i++) {
        final near = raw.sublist(i - 2, i + 3);
        expect(
            out[i],
            inInclusiveRange(near.reduce((a, b) => a < b ? a : b) - 1e-9,
                near.reduce((a, b) => a > b ? a : b) + 1e-9));
      }
    });
  });

  group('the recorded liquid markets', () {
    test('the spike rule finds nothing in the Brazil election, on any '
        'range', () {
      for (final who in ['flavio', 'lula']) {
        for (final range in ['max', '1w', '1d']) {
          final raw = _series('liquid_brazil_${who}_$range');
          expect(despikePrices(raw), same(raw), reason: '$who $range');
        }
      }
    });

    test('but it would take a real spike out of a \$71M market, which is '
        'why only thin markets are cleaned', () {
      final raw = _series('liquid_us_invade_iran_max');
      expect(despikePrices(raw), isNot(same(raw)));
      expect(polyMarketIsThin(71647778), isFalse);
    });
  });

  group('a chart\'s points', () {
    PolymarketPricePoint p(int minute, double price) => PolymarketPricePoint(
        timestamp: DateTime.utc(2026, 10, 5, 0, minute), price: price);

    test('times are kept, only a spike\'s price changes, and a clean '
        'series is the same list', () {
      final clean = [for (var i = 0; i < 8; i++) p(i, 0.4)];
      expect(smoothThinHistory(clean), same(clean));
      final spiked = [
        p(0, 0.17), p(1, 0.17), p(2, 0.30), p(3, 0.17), p(4, 0.17), p(5, 0.18),
      ];
      final out = smoothThinHistory(spiked);
      expect(out.length, spiked.length);
      for (var i = 0; i < out.length; i++) {
        expect(out[i].timestamp, spiked[i].timestamp);
      }
      expect(out[2].price, closeTo(0.17, 1e-9));
      expect(identical(out[0], spiked[0]), isTrue);
      expect(out.last.price, 0.18);
    });
  });

  group('a live price far from a thin market\'s history', () {
    test('is not drawn as a cliff: the line stops, the tag says it', () {
      // ETH above 2,300 by Oct 11, seven hours old, never traded: history
      // at 35%, the live book at 98.65%.
      expect(polyThinCliff(thin: true, live: 0.9865, last: 0.35), isTrue);
    });

    test('a thin market whose book agrees with its history is pinned as '
        'any other', () {
      expect(polyThinCliff(thin: true, live: 0.17, last: 0.165), isFalse);
      expect(polyThinCliff(thin: true, live: 0.30, last: 0.17), isFalse);
    });

    test('a liquid market is always pinned to its live price', () {
      expect(polyThinCliff(thin: false, live: 0.9865, last: 0.35), isFalse);
    });

    test('with no history or no live price there is nothing to decide', () {
      expect(polyThinCliff(thin: true, live: null, last: 0.35), isFalse);
      expect(polyThinCliff(thin: true, live: 0.9, last: null), isFalse);
    });
  });
}
