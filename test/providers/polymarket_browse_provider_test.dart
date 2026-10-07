import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';

/// Helper to create a [PolymarketEvent] with sensible defaults.
PolymarketEvent _event({
  String id = '1',
  String slug = 'test',
  String title = 'Test Event',
  double volume = 100000,
  double volume24hr = 10000,
  double liquidity = 1000,
  String category = 'politics',
  DateTime? endDate,
  bool active = true,
  String conditionId = 'cond1',
  List<PolymarketOutcome>? outcomes,
}) {
  return PolymarketEvent(
    id: id,
    slug: slug,
    title: title,
    volume: volume,
    volume24hr: volume24hr,
    liquidity: liquidity,
    category: category,
    endDate: endDate,
    active: active,
    conditionId: conditionId,
    outcomes: outcomes ??
        const [
          PolymarketOutcome(name: 'Yes', price: 0.5, tokenId: 'yes-token'),
          PolymarketOutcome(name: 'No', price: 0.5, tokenId: 'no-token'),
        ],
  );
}

void main() {
  // ──────────────────────────────────────────────────────────────────────────
  // PolymarketEvent model
  // ──────────────────────────────────────────────────────────────────────────
  group('PolymarketEvent', () {
    test('isBinary true for Yes/No outcomes', () {
      final event = _event();
      expect(event.isBinary, true);
    });

    test('isBinary false for single outcome', () {
      final event = _event(outcomes: [
        const PolymarketOutcome(name: 'Yes', price: 0.7),
      ]);
      expect(event.isBinary, false);
    });

    test('isBinary false for multi-outcome non Yes/No', () {
      final event = _event(outcomes: [
        const PolymarketOutcome(name: 'A', price: 0.3),
        const PolymarketOutcome(name: 'B', price: 0.7),
      ]);
      expect(event.isBinary, false);
    });

    test('isBinary case insensitive', () {
      final event = _event(outcomes: [
        const PolymarketOutcome(name: 'YES', price: 0.6),
        const PolymarketOutcome(name: 'no', price: 0.4),
      ]);
      expect(event.isBinary, true);
    });

    test('yesPrice returns Yes outcome price', () {
      final event = _event(outcomes: [
        const PolymarketOutcome(name: 'Yes', price: 0.73),
        const PolymarketOutcome(name: 'No', price: 0.27),
      ]);
      expect(event.yesPrice, 0.73);
    });

    test('yesPrice falls back to first outcome when no Yes', () {
      final event = _event(outcomes: [
        const PolymarketOutcome(name: 'A', price: 0.4),
        const PolymarketOutcome(name: 'B', price: 0.6),
      ]);
      expect(event.yesPrice, 0.4);
    });

    test('yesPrice returns 0.5 for empty outcomes', () {
      final event = _event(outcomes: []);
      expect(event.yesPrice, 0.5);
    });

    test('noPrice returns No outcome price', () {
      final event = _event(outcomes: [
        const PolymarketOutcome(name: 'Yes', price: 0.3),
        const PolymarketOutcome(name: 'No', price: 0.7),
      ]);
      expect(event.noPrice, 0.7);
    });

    test('noPrice falls back to second outcome', () {
      final event = _event(outcomes: [
        const PolymarketOutcome(name: 'A', price: 0.4),
        const PolymarketOutcome(name: 'B', price: 0.6),
      ]);
      expect(event.noPrice, 0.6);
    });

    test('noPrice computes complement for single outcome', () {
      final event = _event(outcomes: [
        const PolymarketOutcome(name: 'Yes', price: 0.65),
      ]);
      // noPrice should be 1 - yesPrice = 0.35
      expect(event.noPrice, closeTo(0.35, 0.001));
    });

    test('yesTokenId returns Yes token', () {
      final event = _event(outcomes: [
        const PolymarketOutcome(
            name: 'Yes', price: 0.5, tokenId: 'token-yes'),
        const PolymarketOutcome(name: 'No', price: 0.5, tokenId: 'token-no'),
      ]);
      expect(event.yesTokenId, 'token-yes');
    });

    test('noTokenId returns No token', () {
      final event = _event(outcomes: [
        const PolymarketOutcome(
            name: 'Yes', price: 0.5, tokenId: 'token-yes'),
        const PolymarketOutcome(name: 'No', price: 0.5, tokenId: 'token-no'),
      ]);
      expect(event.noTokenId, 'token-no');
    });

    test('yesTokenId falls back to first outcome tokenId', () {
      final event = _event(outcomes: [
        const PolymarketOutcome(name: 'A', price: 0.5, tokenId: 'tok-a'),
        const PolymarketOutcome(name: 'B', price: 0.5, tokenId: 'tok-b'),
      ]);
      expect(event.yesTokenId, 'tok-a');
    });

    test('noTokenId falls back to second outcome tokenId', () {
      final event = _event(outcomes: [
        const PolymarketOutcome(name: 'A', price: 0.5, tokenId: 'tok-a'),
        const PolymarketOutcome(name: 'B', price: 0.5, tokenId: 'tok-b'),
      ]);
      expect(event.noTokenId, 'tok-b');
    });

    test('yesTokenId null when no outcomes', () {
      final event = _event(outcomes: []);
      expect(event.yesTokenId, isNull);
    });

    test('noTokenId null when single outcome', () {
      final event = _event(outcomes: [
        const PolymarketOutcome(name: 'Yes', price: 0.5, tokenId: 'tok'),
      ]);
      expect(event.noTokenId, isNull);
    });

    test('outcomeCount returns correct count', () {
      final event = _event(outcomes: [
        const PolymarketOutcome(name: 'A', price: 0.25),
        const PolymarketOutcome(name: 'B', price: 0.25),
        const PolymarketOutcome(name: 'C', price: 0.25),
        const PolymarketOutcome(name: 'D', price: 0.25),
      ]);
      expect(event.outcomeCount, 4);
    });

    test('outcomeCount zero for empty outcomes', () {
      final event = _event(outcomes: []);
      expect(event.outcomeCount, 0);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // PolymarketPosition
  // ──────────────────────────────────────────────────────────────────────────
  group('PolymarketPosition', () {
    test('holds required fields', () {
      const p = PolymarketPosition(
        marketId: 'market-1',
        marketQuestion: 'Will X happen?',
        outcome: 'Yes',
        size: 100,
        avgPrice: 0.55,
        currentPrice: 0.70,
        pnl: 15.0,
        pnlPercent: 27.27,
        isResolved: false,
      );
      expect(p.marketId, 'market-1');
      expect(p.marketQuestion, 'Will X happen?');
      expect(p.outcome, 'Yes');
      expect(p.size, 100);
      expect(p.avgPrice, 0.55);
      expect(p.currentPrice, 0.70);
      expect(p.pnl, 15.0);
      expect(p.pnlPercent, 27.27);
      expect(p.isResolved, false);
    });

    test('optional fields default to null', () {
      const p = PolymarketPosition(
        marketId: 'id',
        marketQuestion: 'Q?',
        outcome: 'No',
        size: 10,
        avgPrice: 0.4,
        currentPrice: 0.3,
        pnl: -1.0,
        pnlPercent: -10.0,
        isResolved: false,
      );
      expect(p.won, isNull);
      expect(p.createdAt, isNull);
      expect(p.resolvedAt, isNull);
      expect(p.tokenId, isNull);
      expect(p.eventSlug, isNull);
      expect(p.marketImage, isNull);
      expect(p.endDateStr, isNull);
    });

    test('resolved position with won=true', () {
      const p = PolymarketPosition(
        marketId: 'id',
        marketQuestion: 'Q?',
        outcome: 'Yes',
        size: 50,
        avgPrice: 0.6,
        currentPrice: 1.0,
        pnl: 20.0,
        pnlPercent: 66.67,
        isResolved: true,
        won: true,
      );
      expect(p.isResolved, true);
      expect(p.won, true);
    });

    test('resolved position with won=false', () {
      const p = PolymarketPosition(
        marketId: 'id',
        marketQuestion: 'Q?',
        outcome: 'Yes',
        size: 50,
        avgPrice: 0.6,
        currentPrice: 0.0,
        pnl: -30.0,
        pnlPercent: -100.0,
        isResolved: true,
        won: false,
      );
      expect(p.isResolved, true);
      expect(p.won, false);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // PolymarketPricePoint
  // ──────────────────────────────────────────────────────────────────────────
  group('PolymarketPricePoint', () {
    test('holds timestamp and price', () {
      final ts = DateTime(2025, 6, 1, 12, 0);
      final pp = PolymarketPricePoint(timestamp: ts, price: 0.42);
      expect(pp.timestamp, ts);
      expect(pp.price, 0.42);
    });

    test('zero price', () {
      final pp = PolymarketPricePoint(
        timestamp: DateTime.now(),
        price: 0.0,
      );
      expect(pp.price, 0.0);
    });

    test('price at boundary 1.0', () {
      final pp = PolymarketPricePoint(
        timestamp: DateTime.now(),
        price: 1.0,
      );
      expect(pp.price, 1.0);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Liquidity filtering (the providers filter events with liquidity < 500)
  // ──────────────────────────────────────────────────────────────────────────
  group('Liquidity filtering logic', () {
    test('events with liquidity >= 500 pass the filter', () {
      final events = [
        _event(id: '1', liquidity: 500),
        _event(id: '2', liquidity: 1000),
        _event(id: '3', liquidity: 10000),
      ];
      final filtered = events.where((e) => e.liquidity >= 500).toList();
      expect(filtered.length, 3);
    });

    test('events with liquidity < 500 are removed', () {
      final events = [
        _event(id: '1', liquidity: 499),
        _event(id: '2', liquidity: 0),
        _event(id: '3', liquidity: 100),
      ];
      final filtered = events.where((e) => e.liquidity >= 500).toList();
      expect(filtered, isEmpty);
    });

    test('mixed liquidity filtering', () {
      final events = [
        _event(id: '1', liquidity: 499),
        _event(id: '2', liquidity: 500),
        _event(id: '3', liquidity: 1),
        _event(id: '4', liquidity: 5000),
      ];
      final filtered = events.where((e) => e.liquidity >= 500).toList();
      expect(filtered.length, 2);
      expect(filtered.map((e) => e.id).toList(), ['2', '4']);
    });

    test('empty events list returns empty', () {
      final events = <PolymarketEvent>[];
      final filtered = events.where((e) => e.liquidity >= 500).toList();
      expect(filtered, isEmpty);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Search filtering (search provider uses liquidity >= 100)
  // ──────────────────────────────────────────────────────────────────────────
  group('Search liquidity filtering', () {
    test('search events with liquidity >= 100 pass', () {
      final events = [
        _event(id: '1', liquidity: 100),
        _event(id: '2', liquidity: 50),
        _event(id: '3', liquidity: 200),
      ];
      final filtered = events.where((e) => e.liquidity >= 100).toList();
      expect(filtered.length, 2);
      expect(filtered.map((e) => e.id).toList(), ['1', '3']);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Deduplication logic (used in the 'live' category)
  // ──────────────────────────────────────────────────────────────────────────
  group('Event deduplication', () {
    test('removes duplicate event IDs', () {
      final events = [
        _event(id: '1', liquidity: 1000),
        _event(id: '2', liquidity: 1000),
        _event(id: '1', liquidity: 1000), // duplicate
        _event(id: '3', liquidity: 1000),
        _event(id: '2', liquidity: 1000), // duplicate
      ];

      final seenIds = <String>{};
      final deduped = <PolymarketEvent>[];
      for (final e in events) {
        if (e.liquidity < 500) continue;
        if (seenIds.add(e.id)) deduped.add(e);
      }

      expect(deduped.length, 3);
      expect(deduped.map((e) => e.id).toList(), ['1', '2', '3']);
    });

    test('deduplication with low liquidity filtering', () {
      final events = [
        _event(id: '1', liquidity: 100), // too low
        _event(id: '2', liquidity: 600),
        _event(id: '1', liquidity: 800), // same id, but first was filtered
      ];

      final seenIds = <String>{};
      final deduped = <PolymarketEvent>[];
      for (final e in events) {
        if (e.liquidity < 500) continue;
        if (seenIds.add(e.id)) deduped.add(e);
      }

      expect(deduped.length, 2);
      expect(deduped.map((e) => e.id).toList(), ['2', '1']);
    });

    test('all duplicates filtered leaves unique set', () {
      final events = [
        _event(id: '1', liquidity: 1000),
        _event(id: '1', liquidity: 2000),
        _event(id: '1', liquidity: 3000),
      ];

      final seenIds = <String>{};
      final deduped = <PolymarketEvent>[];
      for (final e in events) {
        if (e.liquidity < 500) continue;
        if (seenIds.add(e.id)) deduped.add(e);
      }

      expect(deduped.length, 1);
      // First occurrence wins
      expect(deduped.first.liquidity, 1000);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Excitement score sorting (reimplemented inline to test the logic)
  // ──────────────────────────────────────────────────────────────────────────
  group('Excitement score sorting', () {
    // Mirror the private _excitementScore function for testing the logic.
    double excitementScore(PolymarketEvent e, DateTime now) {
      double score = 0;

      if (e.category == 'sports') score += 500;

      if (e.endDate != null) {
        final hoursLeft = e.endDate!.difference(now).inHours;
        if (hoursLeft >= 0 && hoursLeft < 1) {
          score += 1000;
        } else if (hoursLeft >= 0 && hoursLeft < 6) {
          score += 600;
        } else if (hoursLeft >= 0 && hoursLeft < 24) {
          score += 300;
        } else if (hoursLeft >= 0 && hoursLeft < 72) {
          score += 100;
        }
      }

      if (e.volume24hr > 100000) {
        score += 200;
      } else if (e.volume24hr > 50000) {
        score += 100;
      } else if (e.volume24hr > 10000) {
        score += 50;
      }

      if (e.volume > 0) {
        final ratio = e.volume24hr / e.volume;
        if (ratio > 0.2) {
          score += 300;
        } else if (ratio > 0.1) {
          score += 150;
        } else if (ratio > 0.05) {
          score += 50;
        }
      }

      final yesPrice = e.yesPrice;
      final closeness = 1.0 - (yesPrice - 0.5).abs() * 2;
      score += closeness * 100;

      score += (e.liquidity / 10000).clamp(0, 50);

      return score;
    }

    test('sports category gets +500 bonus', () {
      final now = DateTime(2025, 6, 1);
      final sports = _event(category: 'sports', volume: 0, volume24hr: 0);
      final politics = _event(category: 'politics', volume: 0, volume24hr: 0);
      expect(
        excitementScore(sports, now) - excitementScore(politics, now),
        closeTo(500, 0.01),
      );
    });

    test('ending within 1 hour gets +1000', () {
      final now = DateTime(2025, 6, 1, 12, 0);
      final ending = _event(
        endDate: now.add(const Duration(minutes: 30)),
        volume: 0,
        volume24hr: 0,
      );
      final score = excitementScore(ending, now);
      // Contains 1000 from time urgency
      expect(score, greaterThanOrEqualTo(1000));
    });

    test('ending in 3 hours gets +600', () {
      final now = DateTime(2025, 6, 1, 12, 0);
      final ending = _event(
        endDate: now.add(const Duration(hours: 3)),
        volume: 0,
        volume24hr: 0,
      );
      final noEnd = _event(volume: 0, volume24hr: 0);
      final diff = excitementScore(ending, now) - excitementScore(noEnd, now);
      expect(diff, closeTo(600, 0.01));
    });

    test('ending in 12 hours gets +300', () {
      final now = DateTime(2025, 6, 1, 12, 0);
      final ending = _event(
        endDate: now.add(const Duration(hours: 12)),
        volume: 0,
        volume24hr: 0,
      );
      final noEnd = _event(volume: 0, volume24hr: 0);
      final diff = excitementScore(ending, now) - excitementScore(noEnd, now);
      expect(diff, closeTo(300, 0.01));
    });

    test('ending in 48 hours gets +100', () {
      final now = DateTime(2025, 6, 1, 12, 0);
      final ending = _event(
        endDate: now.add(const Duration(hours: 48)),
        volume: 0,
        volume24hr: 0,
      );
      final noEnd = _event(volume: 0, volume24hr: 0);
      final diff = excitementScore(ending, now) - excitementScore(noEnd, now);
      expect(diff, closeTo(100, 0.01));
    });

    test('ended event (negative hours) gets no time bonus', () {
      final now = DateTime(2025, 6, 1, 12, 0);
      final ended = _event(
        endDate: now.subtract(const Duration(hours: 5)),
        volume: 0,
        volume24hr: 0,
      );
      final noEnd = _event(volume: 0, volume24hr: 0);
      final diff = excitementScore(ended, now) - excitementScore(noEnd, now);
      expect(diff, closeTo(0, 0.01));
    });

    test('high 24h volume gets +200', () {
      final now = DateTime(2025, 6, 1);
      final high = _event(volume24hr: 150000, volume: 1000000);
      final low = _event(volume24hr: 5000, volume: 1000000);
      final diff = excitementScore(high, now) - excitementScore(low, now);
      // 200 from volume24hr tier, plus ratio difference
      expect(diff, greaterThan(100));
    });

    test('50/50 price gets maximum closeness bonus', () {
      final now = DateTime(2025, 6, 1);
      final balanced = _event(
        outcomes: const [
          PolymarketOutcome(name: 'Yes', price: 0.5),
          PolymarketOutcome(name: 'No', price: 0.5),
        ],
        volume: 0,
        volume24hr: 0,
      );
      final extreme = _event(
        outcomes: const [
          PolymarketOutcome(name: 'Yes', price: 0.95),
          PolymarketOutcome(name: 'No', price: 0.05),
        ],
        volume: 0,
        volume24hr: 0,
      );
      expect(
        excitementScore(balanced, now),
        greaterThan(excitementScore(extreme, now)),
      );
    });

    test('high volume ratio (>0.2) gets +300', () {
      final now = DateTime(2025, 6, 1);
      final hotEvent = _event(volume: 100000, volume24hr: 30000); // ratio 0.3
      final coldEvent = _event(volume: 100000, volume24hr: 1000); // ratio 0.01
      final diff = excitementScore(hotEvent, now) - excitementScore(coldEvent, now);
      // 300 ratio bonus + volume24hr tier difference
      expect(diff, greaterThan(250));
    });

    test('sorting puts highest excitement first', () {
      final now = DateTime(2025, 6, 1, 12, 0);
      final events = [
        _event(
          id: 'low',
          category: 'politics',
          volume: 10000,
          volume24hr: 100,
          liquidity: 1000,
        ),
        _event(
          id: 'high',
          category: 'sports',
          endDate: now.add(const Duration(minutes: 30)),
          volume: 500000,
          volume24hr: 200000,
          liquidity: 50000,
        ),
        _event(
          id: 'mid',
          category: 'crypto',
          volume: 100000,
          volume24hr: 50001,
          liquidity: 5000,
        ),
      ];

      events.sort((a, b) {
        final scoreA = excitementScore(a, now);
        final scoreB = excitementScore(b, now);
        return scoreB.compareTo(scoreA);
      });

      expect(events.first.id, 'high');
      expect(events.last.id, 'low');
    });

    test('zero volume avoids division by zero in ratio', () {
      final now = DateTime(2025, 6, 1);
      final event = _event(volume: 0, volume24hr: 10000);
      // Should not throw
      final score = excitementScore(event, now);
      expect(score.isFinite, true);
    });

    test('liquidity bonus clamped at 50', () {
      final now = DateTime(2025, 6, 1);
      final hugeL = _event(liquidity: 10000000, volume: 0, volume24hr: 0);
      final smallL = _event(liquidity: 10000, volume: 0, volume24hr: 0);
      final diff = excitementScore(hugeL, now) - excitementScore(smallL, now);
      // Huge liquidity clamped at 50, small = 10000/10000 = 1, diff <= 49
      expect(diff, lessThanOrEqualTo(49));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // PolymarketTopMarket
  // ──────────────────────────────────────────────────────────────────────────
  group('PolymarketTopMarket', () {
    test('holds all fields', () {
      const m = PolymarketTopMarket(
        question: 'Will BTC hit 100k?',
        yesPrice: 0.65,
        noPrice: 0.35,
        volume: 1000000,
        conditionId: 'cond-abc',
        yesTokenId: 'yes-tok',
        noTokenId: 'no-tok',
        imageUrl: 'https://img.png',
      );
      expect(m.question, 'Will BTC hit 100k?');
      expect(m.yesPrice, 0.65);
      expect(m.noPrice, 0.35);
      expect(m.volume, 1000000);
      expect(m.conditionId, 'cond-abc');
      expect(m.yesTokenId, 'yes-tok');
      expect(m.noTokenId, 'no-tok');
      expect(m.imageUrl, 'https://img.png');
    });

    test('optional fields can be null', () {
      const m = PolymarketTopMarket(
        question: 'Q?',
        yesPrice: 0.5,
        noPrice: 0.5,
        volume: 100,
        conditionId: 'cond',
      );
      expect(m.imageUrl, isNull);
      expect(m.yesTokenId, isNull);
      expect(m.noTokenId, isNull);
    });
  });
}
