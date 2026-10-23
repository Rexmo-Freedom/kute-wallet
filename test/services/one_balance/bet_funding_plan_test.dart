// Predictions cash is used first and only the remainder moves from
// Dollars; that cash then stays on Predictions until the venue has been
// idle a day.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/funding/venue_shortfall.dart';
import 'package:kute/services/one_balance/bet_funding_plan.dart';
import 'package:kute/services/one_balance/prediction_funding_ledger.dart';
import 'package:kute/services/one_balance/sweep_rules.dart';
import 'package:kute/services/one_balance/venue_activity.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';

void main() {
  group('planBetFunding', () {
    test('venue cash first: only the remainder moves, with a small buffer',
        () {
      // Predictions holds $2; a $3.50 minimum bet needs $3.58 with fees.
      final plan = planBetFunding(
          requiredUsd: 3.58, readyUsd: 2, routeFee: 0.01, minUsd: 1);
      // $1.58 missing + the engine's $0.25 buffer, grossed up by the 1%
      // route fee.
      expect(plan.fundUsd, 1.85);
      expect(plan.arrivingUsd, greaterThanOrEqualTo(1.58 + 0.25 - 1e-9));
      expect(plan.rule, ShortfallRules.ruleRemaining);
    });

    test('never under the Move minimum or the route minimum', () {
      expect(
          planBetFunding(requiredUsd: 2.10, readyUsd: 2, routeFee: 0).fundUsd,
          1.0);
      expect(
          planBetFunding(
                  requiredUsd: 2.10, readyUsd: 2, routeFee: 0, minUsd: 2.5)
              .fundUsd,
          2.5);
    });

    test('nothing moves when the venue covers it', () {
      final plan = planBetFunding(requiredUsd: 5, readyUsd: 5.2);
      expect(plan.fundUsd, 0);
      expect(plan.arrivingUsd, 0);
    });

    test('a large shortfall carries a 2% buffer', () {
      final plan =
          planBetFunding(requiredUsd: 100, readyUsd: 0, routeFee: 0);
      expect(plan.fundUsd, 102.0);
    });
  });

  group('the idle rule', () {
    final now = DateTime.utc(2026, 10, 13, 12);
    SweepContext ctx() => SweepContext(now: now, minimumUsd: 1);

    test('cash stays while the venue was used within a day', () {
      final d = decideSweep(
          VenueSnapshot(
              idleUsd: 8,
              sweepableUsd: 8,
              lastActivityAt: now.subtract(const Duration(hours: 23))),
          ctx());
      expect(d, isA<SweepSkip>());
      expect((d as SweepSkip).reason, SweepSkipReason.active);
      expect(SweepSkipReason.active.label, 'venue_active');
    });

    test('a day idle: it all goes home', () {
      final d = decideSweep(
          VenueSnapshot(
              idleUsd: 8,
              sweepableUsd: 8,
              lastActivityAt: now.subtract(kVenueIdleSweepAfter)),
          ctx());
      expect(d, isA<SweepNow>());
    });

    test('a venue not under the rule is unchanged', () {
      expect(
          decideSweep(const VenueSnapshot(idleUsd: 8, sweepableUsd: 8), ctx()),
          isA<SweepNow>());
    });
  });

  group('the funding record', () {
    setUp(() {
      PredictionFundingLedger.reset();
      VenueActivity.reset();
    });

    test('sent → landed → reserved → released, each step activity', () {
      final ledger = PredictionFundingLedger.instance;
      ledger.sent('m1', usd: 10);
      expect(ledger.hasInFlight, isTrue);
      expect(VenueActivity.last(OneBalanceVenue.predictions), isNotNull);
      ledger.landed('m1');
      expect(ledger.hasInFlight, isFalse);
      ledger.reserve('m1');
      expect(ledger.hasReserved, isTrue);
      ledger.release('m1', reason: 'failed');
      expect(ledger.hasReserved, isFalse);
      expect(ledger.record('m1')!.stage, PredictionFundingStage.released);
      expect(ledger.record('m1')!.releaseReason, 'failed');
      // Idempotent.
      ledger.release('m1', reason: 'placed');
      expect(ledger.record('m1')!.releaseReason, 'failed');
    });

    test('a move not seen landing stops counting as in flight', () {
      final ledger = PredictionFundingLedger.instance;
      final at = DateTime.utc(2026, 10, 13, 12);
      PredictionFundingLedger.clock = () => at;
      addTearDown(() => PredictionFundingLedger.clock = DateTime.now);
      ledger.sent('m2', usd: 5);
      PredictionFundingLedger.clock =
          () => at.add(PredictionFundingLedger.inFlightMax);
      expect(ledger.hasInFlight, isFalse);
    });
  });
}
