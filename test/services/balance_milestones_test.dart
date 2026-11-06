import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/services/balance_milestones.dart';
import 'package:kute/services/once_flags_service.dart';

/// The flags as a map, for the record's tests.
class MapFlags implements BalanceMilestoneFlags {
  final Set<String> claimed = {};

  @override
  bool isClaimed(String key) => claimed.contains(key);

  @override
  bool claim(String key) => claimed.add(key);
}

/// The Bitcoin home's milestones: the ladder of round goals for the
/// person's Bitcoin + Dollars total, the progress to the next one, the
/// nudge's amount, the goal line's reach, and the once-only record
/// (founder, 6 November 2026: "gamify the graph ... to reach certain
/// thresholds").
void main() {
  group('the nice numbers', () {
    test('1, 2.5, 5 of each power of ten', () {
      expect([for (var j = 0; j < 9; j++) niceNumberAt(j)],
          [1, 2.5, 5, 10, 25, 50, 100, 250, 500]);
    });

    test('nearest on a log scale, and the floor', () {
      expect(niceNumberAt(nearestNiceIndex(100)), 100);
      expect(niceNumberAt(nearestNiceIndex(86)), 100);
      expect(niceNumberAt(nearestNiceIndex(15300)), 10000);
      expect(niceNumberAt(nearestNiceIndex(36000)), 50000);
      expect(nearestNiceIndex(0), 0);
      expect(floorNiceNumber(57.5), 50);
      expect(floorNiceNumber(25), 25);
      expect(floorNiceNumber(24.99), 10);
      expect(floorNiceNumber(0.4), 0);
    });
  });

  group('the ladder', () {
    test(r'dollars: $100, $250, $500, $1,000 and on, past a million', () {
      final l = BalanceMilestoneLadder.forCurrency('USD');
      expect([for (var i = 0; i < 8; i++) l.rung(i)],
          [100, 250, 500, 1000, 2500, 5000, 10000, 25000]);
      expect(l.rung(12), 1000000);
      expect(l.rung(13), 2500000);
    });

    test('each currency starts on its own round figure, whatever the rate', () {
      expect(BalanceMilestoneLadder.forCurrency('EUR').rung(0), 100);
      expect(BalanceMilestoneLadder.forCurrency('gbp').rung(1), 250);
      expect(BalanceMilestoneLadder.forCurrency('HUF').rung(0), 50000);
      expect(BalanceMilestoneLadder.forCurrency('HUF').rung(1), 100000);
      expect(BalanceMilestoneLadder.forCurrency('CZK').rung(0), 2500);
      expect(BalanceMilestoneLadder.forCurrency('SEK').rung(0), 1000);
      // The rate is read only for a currency outside the table.
      expect(BalanceMilestoneLadder.forCurrency('EUR', usdToDisplay: 9).rung(0),
          100);
      expect(
          BalanceMilestoneLadder.forCurrency('JPY', usdToDisplay: 153).rung(0),
          10000);
      expect(BalanceMilestoneLadder.forCurrency('XYZ').rung(0), 100);
    });

    test('rungs passed, the level and the goal', () {
      final l = BalanceMilestoneLadder.forCurrency('USD');
      expect(l.reached(0), 0);
      expect(l.reached(99.99), 0);
      expect(l.reached(100), 1);
      // Float dust under the figure is the figure.
      expect(l.reached(249.9999999), 2);
      expect(l.reached(248.82), 1);
      expect(l.reached(1200), 4);
      expect(l.reached(double.nan), 0);

      final p = l.progress(248.82);
      expect(p.reached, 1);
      expect(p.level, 2);
      expect(p.next, 250);
      expect(p.last, 100);
      expect(p.fraction, closeTo(0.99528, 1e-5));
      // Rounded down, never 100 before it is passed.
      expect(p.percent, 99);
      expect(p.gap, closeTo(1.18, 1e-9));

      final none = l.progress(0);
      expect(none.level, 1);
      expect(none.next, 100);
      expect(none.last, isNull);
      expect(none.percent, 0);

      final passed = l.progress(250);
      expect(passed.level, 3);
      expect(passed.next, 500);
      expect(passed.percent, 50);
    });

    test('names: one per level up to the twelfth, the last for the rest', () {
      final l = BalanceMilestoneLadder.forCurrency('USD');
      expect(l.progress(50).nameIndex, 0);
      expect(l.progress(260).nameIndex, 2);
      expect(l.progress(1e12).nameIndex, kBalanceLevelNames - 1);
    });
  });

  group('the nudge amount', () {
    test(r'a round tenth of the goal, in dollars', () {
      expect(
          balanceGoalSuggestedUsd(
              goal: 250, usdToDisplay: 1, bitcoinUsd: 248.82),
          25);
      expect(
          balanceGoalSuggestedUsd(goal: 100, usdToDisplay: 1, bitcoinUsd: 60),
          10);
      // €500 at 0.87 € a dollar: $57.47, the round figure under it.
      expect(
          balanceGoalSuggestedUsd(
              goal: 500, usdToDisplay: 0.87, bitcoinUsd: 400),
          50);
      // 50,000 Ft at 360 Ft a dollar: $13.89 → $10.
      expect(
          balanceGoalSuggestedUsd(
              goal: 50000, usdToDisplay: 360, bitcoinUsd: 100),
          10);
    });

    test('never more than the bitcoin is worth; none under a dollar', () {
      expect(
          balanceGoalSuggestedUsd(goal: 1000, usdToDisplay: 1, bitcoinUsd: 7.3),
          7);
      expect(
          balanceGoalSuggestedUsd(goal: 1000, usdToDisplay: 1, bitcoinUsd: 0.6),
          isNull);
      expect(
          balanceGoalSuggestedUsd(goal: 1000, usdToDisplay: 0, bitcoinUsd: 60),
          isNull);
    });
  });

  group('the goal line in reach', () {
    test('a flat line: within a quarter of its height', () {
      expect(balanceGoalInReach([355000, 355000], 357143), isTrue);
      expect(balanceGoalInReach([150000, 150000], 357143), isFalse);
    });

    test('a moving line: within the span it covers', () {
      expect(balanceGoalInReach([100, 300], 480), isTrue);
      expect(balanceGoalInReach([100, 300], 520), isFalse);
      // Touched on screen already (the balance fell back): drawn.
      expect(balanceGoalInReach([400, 300], 380), isTrue);
    });

    test('nothing on screen, or a goal that is not a number: none', () {
      expect(balanceGoalInReach(const [], 10), isFalse);
      expect(balanceGoalInReach([0, 0], 10), isFalse);
      expect(balanceGoalInReach([5, 5], double.nan), isFalse);
    });
  });

  group('the once-only record', () {
    final usd = BalanceMilestoneLadder.forCurrency('USD');

    test('the first reading is history: recorded, no celebration', () {
      final flags = MapFlags();
      final record = BalanceMilestoneRecord(flags);
      expect(record.hasNews(usd, usd.reached(1200)), isTrue);
      expect(record.claim(usd, usd.reached(1200)), isNull);
      expect(record.hasNews(usd, usd.reached(1200)), isFalse);
      expect(
          flags.claimed,
          containsAll([
            'balance_milestones_seen_USD',
            'balance_milestone_USD_100',
            'balance_milestone_USD_1000',
          ]));
    });

    test('a rung passed later is celebrated once, never again', () {
      final record = BalanceMilestoneRecord(MapFlags());
      expect(record.claim(usd, usd.reached(248.82)), isNull);
      expect(record.hasNews(usd, usd.reached(251)), isTrue);
      expect(record.claim(usd, usd.reached(251)), 250);
      expect(record.claim(usd, usd.reached(251)), isNull);
      // Down under it and back up: no second party.
      expect(record.claim(usd, usd.reached(240)), isNull);
      expect(record.hasNews(usd, usd.reached(255)), isFalse);
      expect(record.claim(usd, usd.reached(255)), isNull);
    });

    test('several at once: the highest is the one celebrated', () {
      final record = BalanceMilestoneRecord(MapFlags());
      record.claim(usd, usd.reached(50));
      expect(record.claim(usd, usd.reached(1100)), 1000);
      expect(record.claim(usd, usd.reached(1100)), isNull);
    });

    test('each display currency keeps its own record', () {
      final flags = MapFlags();
      final record = BalanceMilestoneRecord(flags);
      final eur = BalanceMilestoneLadder.forCurrency('EUR');
      record.claim(usd, usd.reached(300));
      // A switch to euros: its first reading is history too.
      expect(record.claim(eur, eur.reached(280)), isNull);
      expect(record.claim(eur, eur.reached(510)), 500);
    });

    group('kept in the once-only box', () {
      late Directory dir;

      setUp(() async {
        dir = await Directory.systemTemp.createTemp('balance_milestones');
        Hive.init(dir.path);
        await Hive.openBox<bool>(OnceFlagsService.boxName);
      });

      tearDown(() async {
        await Hive.close();
        await dir.delete(recursive: true);
      });

      test('across a restart; a wallet wipe starts it afresh', () async {
        const record = BalanceMilestoneRecord(OnceBalanceMilestoneFlags());
        expect(record.claim(usd, usd.reached(90)), isNull);
        expect(record.claim(usd, usd.reached(120)), 100);

        // The app again: the box from disk.
        await Hive.close();
        Hive.init(dir.path);
        await Hive.openBox<bool>(OnceFlagsService.boxName);
        expect(record.hasNews(usd, usd.reached(120)), isFalse);
        expect(record.claim(usd, usd.reached(120)), isNull);
        expect(record.claim(usd, usd.reached(260)), 250);

        // The wipe clears the box: the next reading is history again.
        await OnceFlagsService.resetAll();
        expect(record.claim(usd, usd.reached(260)), isNull);
        expect(record.claim(usd, usd.reached(510)), 500);
      });
    });
  });
}
