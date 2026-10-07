import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/orchestra_legacy_status_rules.dart'
    show OrchestraStatusReadKind;
import 'package:kute/services/funding/settlement_reconciler.dart';
import 'package:kute/services/funding/settlement_stage.dart';

final _t0 = DateTime.utc(2026, 9, 1, 12);
final _expiresAt = _t0.add(const Duration(minutes: 2));

SettlementReconcileState _state(
  SettlementStage stage, {
  DateTime? broadcastingAt,
  DateTime? lastCheckedAt,
}) =>
    SettlementReconcileState(
      stage: stage,
      createdAt: _t0,
      everBroadcast: true,
      fundingKind: SettlementFundingKind.bitcoin,
      hasFundingProof: stage != SettlementStage.broadcasting,
      submitAccepted: stage != SettlementStage.broadcasting &&
          stage != SettlementStage.funded,
      quoteExpiresAt: _expiresAt,
      broadcastingAt: broadcastingAt ?? _t0.add(const Duration(minutes: 1)),
      fundedAt: stage == SettlementStage.broadcasting
          ? null
          : (broadcastingAt ?? _t0.add(const Duration(minutes: 1))),
      lastCheckedAt: lastCheckedAt,
    );

SettlementReconcileResult _read(
  SettlementReconcileState state,
  String providerStatus, {
  required DateTime now,
}) =>
    applySettlementReconcile(
      state,
      SettlementReconcileEvidence(
        status: OrchestraStatusReadKind.order,
        providerStatus: providerStatus,
      ),
      now: now,
      foregroundedAt: _t0,
    );

void main() {
  test('P5-X16 funding after expiry is flagged late and never re-funded', () {
    final lateBroadcast = _expiresAt.add(const Duration(minutes: 3));
    final funded = applySettlementReconcile(
      _state(SettlementStage.broadcasting, broadcastingAt: lateBroadcast),
      const SettlementReconcileEvidence(bitcoin: BitcoinFundingProbe.txidSeen),
      now: lateBroadcast.add(const Duration(minutes: 1)),
      foregroundedAt: _t0,
    );
    expect(funded.stage, SettlementStage.funded);
    expect(funded.quoteExpiredBeforeFunding, isTrue);

    final plan = planSettlementReconcile(
      _state(SettlementStage.funded, broadcastingAt: lateBroadcast),
      now: lateBroadcast.add(const Duration(minutes: 2)),
      sessionUnlocked: true,
      foregroundedAt: _t0,
    );
    expect(plan.expireLocally, isFalse);
    expect(plan.readStatus || plan.submitDeposit, isTrue);
  });

  test('P5-X16 provider unfulfilled with a proof is a late deposit', () {
    final now = _t0.add(const Duration(hours: 1));
    final result =
        _read(_state(SettlementStage.submitted), 'unfulfilled', now: now);
    expect(result.stage, SettlementStage.lateDeposit);
    expect(result.signals, contains(SettlementReconcileSignal.lateDeposit));
    expect(result.nextCheckAt, isNotNull);
  });

  test('P5-X16 a late deposit keeps checking and is never closed locally', () {
    for (final age in const [
      Duration(hours: 2),
      Duration(days: 20),
      Duration(days: 59),
    ]) {
      final now = _t0.add(age);
      final plan = planSettlementReconcile(
        _state(SettlementStage.lateDeposit,
            lastCheckedAt: now.subtract(const Duration(days: 1))),
        now: now,
        sessionUnlocked: false,
        foregroundedAt: _t0,
      );
      expect(plan.readStatus, isTrue, reason: '$age');
      expect(plan.expireLocally, isFalse);
      final result = applySettlementReconcile(
        _state(SettlementStage.lateDeposit),
        const SettlementReconcileEvidence(
            status: OrchestraStatusReadKind.notFound),
        now: now,
        foregroundedAt: _t0,
      );
      expect(result.stage, SettlementStage.lateDeposit);
    }
  });

  test('P5-X18 refund branch: late deposit, refunding, refunded', () {
    final now = _t0.add(const Duration(hours: 3));
    final refunding =
        _read(_state(SettlementStage.lateDeposit), 'refunding', now: now);
    expect(refunding.stage, SettlementStage.refunding);
    expect(refunding.nextCheckAt, isNotNull);
    final refunded =
        _read(_state(SettlementStage.refunding), 'refunded', now: now);
    expect(refunded.stage, SettlementStage.refunded);
    expect(refunded.nextCheckAt, isNull);
    expect(refunded.signals, contains(SettlementReconcileSignal.terminal));
  });
}
