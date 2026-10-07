import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/funding/settlement_reconciler.dart';
import 'package:kute/services/funding/settlement_stage.dart';

final _t0 = DateTime.utc(2026, 9, 1, 12);

void main() {
  test('P5-X20 pending operations keep reconciling whatever the flags', () {
    for (final kind in SettlementFundingKind.values) {
      for (final stage in [
        SettlementStage.broadcasting,
        SettlementStage.fundingUnknown,
        SettlementStage.funded,
        SettlementStage.submitted,
        SettlementStage.processing,
        SettlementStage.lateDeposit,
        SettlementStage.refunding,
        SettlementStage.needsAttention,
      ]) {
        final plan = planSettlementReconcile(
          SettlementReconcileState(
            stage: stage,
            createdAt: _t0,
            everBroadcast: true,
            fundingKind: kind,
            hasFundingProof: stage != SettlementStage.broadcasting &&
                stage != SettlementStage.fundingUnknown,
            quoteExpiresAt: _t0.add(const Duration(minutes: 2)),
            broadcastingAt: _t0.add(const Duration(minutes: 1)),
          ),
          now: _t0.add(const Duration(hours: 6)),
          sessionUnlocked: false,
          foregroundedAt: _t0,
        );
        expect(plan.isIdle, isFalse, reason: '${kind.name} ${stage.name}');
        expect(plan.expireLocally, isFalse);
      }
    }
  });

}
