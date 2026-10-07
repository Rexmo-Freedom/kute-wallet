import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/orchestra_legacy_status_rules.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/services/funding/settlement_reconciler.dart';
import 'package:kute/services/funding/settlement_stage.dart';

final _t0 = DateTime.utc(2026, 9, 1, 12);

SettlementReconcileState _funded(SettlementStage stage) =>
    SettlementReconcileState(
      stage: stage,
      createdAt: _t0,
      everBroadcast: true,
      fundingKind: SettlementFundingKind.spark,
      hasFundingProof: true,
      submitAccepted: true,
      quoteExpiresAt: _t0.add(const Duration(minutes: 2)),
      broadcastingAt: _t0.add(const Duration(minutes: 1)),
      fundedAt: _t0.add(const Duration(minutes: 1)),
    );

SettlementReconcileResult _read(SettlementStage stage, String status) =>
    applySettlementReconcile(
      _funded(stage),
      SettlementReconcileEvidence(
        status: OrchestraStatusReadKind.order,
        providerStatus: status,
      ),
      now: _t0.add(const Duration(hours: 1)),
      foregroundedAt: _t0,
    );

void main() {
  test('P5-X11 duplicate status responses are idempotent', () {
    var stage = SettlementStage.submitted;
    final seen = <SettlementStage>[];
    for (final status in [
      'processing',
      'processing',
      'completed',
      'completed',
      'completed',
    ]) {
      stage = _read(stage, status).stage;
      seen.add(stage);
    }
    expect(seen, [
      SettlementStage.processing,
      SettlementStage.processing,
      SettlementStage.settled,
      SettlementStage.settled,
      SettlementStage.settled,
    ]);
  });

  test('P5-X11 out-of-order responses never regress a stage', () {
    var stage = SettlementStage.submitted;
    for (final status in [
      'refunding',
      'processing',
      'awaiting_deposit',
      'refunded',
      'refunding',
      'completed',
    ]) {
      stage = _read(stage, status).stage;
    }
    expect(stage, SettlementStage.refunded);
  });

  test('P5-X11 a duplicated order read swaps a legacy row id once', () async {
    final rows = <String, SwapOrder>{
      'q_1': SwapOrder(
        id: 'q_1',
        coinFrom: 'BTC',
        networkFrom: 'SPARK',
        coinTo: 'USDC.e',
        networkTo: 'POLYGON',
        depositAddress: 'deposit',
        depositAmount: '0.001',
        withdrawalAmount: '50',
        status: 'wait',
        timestamp: _t0.millisecondsSinceEpoch,
        withdrawalAddress: '',
        depositMin: '0',
        depositMax: '0',
        rate: '0',
        refundAddress: '',
        provider: 'Orchestra',
      ),
    };
    for (var i = 0; i < 2; i++) {
      final source = rows['q_1'] ?? rows['ord_1']!;
      await replaceOrchestraRowId(
        oldId: 'q_1',
        replacement: legacyRowWithOrderId(source, 'ord_1'),
        add: (row) async => rows[row.id] = row,
        delete: (id) async => rows.remove(id),
      );
    }
    expect(rows.keys, ['ord_1']);
  });
}
