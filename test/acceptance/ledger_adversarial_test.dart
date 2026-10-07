import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/funding/settlement_reconciler.dart';
import 'package:kute/services/funding/settlement_stage.dart';
import 'package:kute/services/hardware/ledger/ledger_operation_scope.dart';

final _t0 = DateTime.utc(2026, 9, 1, 12);

SettlementReconcileState _ledgerBtc(SettlementStage stage) =>
    SettlementReconcileState(
      stage: stage,
      createdAt: _t0,
      everBroadcast: !stage.isBeforeBroadcasting,
      fundingKind: SettlementFundingKind.bitcoin,
      quoteExpiresAt: _t0.add(const Duration(minutes: 2)),
      broadcastingAt: stage.isBeforeBroadcasting
          ? null
          : _t0.add(const Duration(minutes: 1)),
    );

void main() {
  tearDown(() => LedgerOperationScope.onBlocked = null);

  test('P5-L9 no hot signing for a Ledger action with the hot session locked',
      () async {
    final blocked = <HotSigningAction>[];
    LedgerOperationScope.onBlocked = blocked.add;
    var hotCalls = 0;
    void hotSparkSend() {
      LedgerOperationScope.assertHotAllowed(HotSigningAction.sparkTransaction);
      hotCalls++;
    }

    var deviceSignatures = 0;
    await LedgerOperationScope.run('ledger-1', () async {
      await Future<void>.delayed(Duration.zero);
      deviceSignatures++;
    });
    expect(deviceSignatures, 1);
    expect(hotCalls, 0);
    expect(blocked, isEmpty);

    await expectLater(
      LedgerOperationScope.run('ledger-1', () async => hotSparkSend()),
      throwsA(isA<HotSigningInLedgerScope>()),
    );
    expect(hotCalls, 0);
    expect(blocked, [HotSigningAction.sparkTransaction]);
  });

  test(
      'P5-L5 disconnect after sign before broadcast is watched, then '
      'abandoned', () {
    SettlementStage stageAt(Duration sinceStart) => applySettlementReconcile(
          _ledgerBtc(SettlementStage.signed),
          const SettlementReconcileEvidence(
              bitcoin: BitcoinFundingProbe.noSignal),
          now: _t0.add(sinceStart),
          foregroundedAt: _t0,
        ).stage;
    expect(stageAt(const Duration(minutes: 10)), SettlementStage.signed);
    expect(stageAt(const Duration(minutes: 32)), SettlementStage.signed);
    expect(stageAt(const Duration(minutes: 33)), SettlementStage.abandoned);
  });

  test('P5-L5 disconnect after broadcast is tracked until chain evidence', () {
    final now = _t0.add(const Duration(minutes: 10));
    expect(
      applySettlementReconcile(
        _ledgerBtc(SettlementStage.broadcasting),
        const SettlementReconcileEvidence(
            bitcoin: BitcoinFundingProbe.unavailable),
        now: now,
        foregroundedAt: _t0,
      ).stage,
      SettlementStage.broadcasting,
    );
    expect(
      applySettlementReconcile(
        _ledgerBtc(SettlementStage.broadcasting),
        const SettlementReconcileEvidence(
            bitcoin: BitcoinFundingProbe.conflictUnconfirmed),
        now: now,
        foregroundedAt: _t0,
      ).stage,
      SettlementStage.fundingUnknown,
    );
    expect(
      applySettlementReconcile(
        _ledgerBtc(SettlementStage.fundingUnknown),
        const SettlementReconcileEvidence(
            bitcoin: BitcoinFundingProbe.txidSeen),
        now: now,
        foregroundedAt: _t0,
      ).stage,
      SettlementStage.funded,
    );
  });

}
