import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/helpers/orchestra_legacy_status_rules.dart';
import 'package:kute/models/orchestra_model.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/services/api/orchestra_api.dart';
import 'package:kute/services/funding/settlement_http.dart';
import 'package:kute/services/funding/settlement_reconciler.dart';
import 'package:kute/services/funding/settlement_stage.dart';

final _t0 = DateTime.utc(2026, 9, 1, 12);

SwapOrder _quoteRow() => SwapOrder(
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
      expiresAt: _t0.add(const Duration(minutes: 2)).millisecondsSinceEpoch,
    );

void main() {
  setUpAll(() {
    dotenv.loadFromString(envString: 'BACKEND=https://backend.test');
    AffiliateService.debugSessionToken = 'test-session';
  });
  tearDownAll(() => AffiliateService.debugSessionToken = null);

  test('P5-X13 status read failures at every age never expire a quote row', () {
    for (final age in const [
      Duration(minutes: 6),
      Duration(hours: 1),
      Duration(days: 1),
      Duration(days: 20),
    ]) {
      expect(
        legacyStatusReadAction(
          row: _quoteRow(),
          read: OrchestraStatusReadKind.unavailable,
          now: _t0.add(age),
        ),
        LegacyStatusReadAction.keep,
      );
    }
  });

  test('P5-X13 status read failures never change a funded operation', () {
    for (final stage
        in SettlementStage.values.where((s) => s.mayHaveMovedFunds)) {
      final result = applySettlementReconcile(
        SettlementReconcileState(
          stage: stage,
          createdAt: _t0,
          everBroadcast: true,
          fundingKind: SettlementFundingKind.spark,
          hasFundingProof: true,
          quoteExpiresAt: _t0.add(const Duration(minutes: 2)),
          broadcastingAt: _t0.add(const Duration(minutes: 1)),
          sdkSyncsSinceBroadcasting: 9,
        ),
        const SettlementReconcileEvidence(
          status: OrchestraStatusReadKind.unavailable,
        ),
        now: _t0.add(const Duration(days: 3)),
        foregroundedAt: _t0,
      );
      expect(result.stage, stage, reason: stage.name);
    }
  });

  test('P5-X14 registration failure after send then restart keeps the key',
      () async {
    final sent = <String?>[];
    var failRegistration = true;
    final client = MockClient((request) async {
      sent.add(request.headers['X-Idempotency-Key']);
      if (failRegistration) return http.Response('{}', 503);
      return http.Response(
          jsonEncode({
            'order': {'id': 'ord_1', 'status': 'processing'}
          }),
          200);
    });
    Future<void> noSleep(Duration _) async {}

    final fundedAt = _t0.add(const Duration(minutes: 1));
    var state = SettlementReconcileState(
      stage: SettlementStage.funded,
      createdAt: _t0,
      everBroadcast: true,
      fundingKind: SettlementFundingKind.spark,
      hasFundingProof: true,
      quoteExpiresAt: _t0.add(const Duration(minutes: 2)),
      broadcastingAt: fundedAt,
      fundedAt: fundedAt,
    );
    final keys = SubmitIdempotencyKeys.create();

    final firstNow = fundedAt.add(const Duration(seconds: 5));
    expect(
        planSettlementReconcile(state,
                now: firstNow, sessionUnlocked: false, foregroundedAt: _t0)
            .submitDeposit,
        isTrue);
    final first = await http.runWithClient(
      () => submitWithIdempotencyKeys<OrchestraSubmitResponse>(
        keys: keys,
        bodyFingerprint: submitBodyFingerprint({'quoteId': 'q_1'}),
        submit: (key) =>
            OrchestraService.submitDeposit(quoteId: 'q_1', idempotencyKey: key),
        sleep: noSleep,
      ),
      () => client,
    );
    final afterFailure = applySettlementReconcile(
      state,
      const SettlementReconcileEvidence(
        status: OrchestraStatusReadKind.notFound,
        submit: SubmitAttemptOutcome.transient,
      ),
      now: firstNow,
      foregroundedAt: _t0,
    );
    expect(afterFailure.stage, SettlementStage.funded);
    final persistedKeys = jsonEncode(first.keys.toJson());

    state = SettlementReconcileState(
      stage: afterFailure.stage,
      createdAt: _t0,
      everBroadcast: true,
      fundingKind: SettlementFundingKind.spark,
      hasFundingProof: true,
      quoteExpiresAt: state.quoteExpiresAt,
      broadcastingAt: fundedAt,
      fundedAt: fundedAt,
      submitAttempts: afterFailure.submitAttempts,
      lastSubmitAttemptAt: afterFailure.lastSubmitAttemptAt,
      lastCheckedAt: afterFailure.lastCheckedAt,
    );
    final restartNow = firstNow.add(const Duration(minutes: 1));
    expect(
        planSettlementReconcile(state,
                now: restartNow,
                sessionUnlocked: false,
                foregroundedAt: restartNow)
            .submitDeposit,
        isTrue);

    failRegistration = false;
    final restored = SubmitIdempotencyKeys.fromJson(
        jsonDecode(persistedKeys) as Map<String, dynamic>);
    final second = await http.runWithClient(
      () => submitWithIdempotencyKeys<OrchestraSubmitResponse>(
        keys: restored,
        bodyFingerprint: submitBodyFingerprint({'quoteId': 'q_1'}),
        submit: (key) =>
            OrchestraService.submitDeposit(quoteId: 'q_1', idempotencyKey: key),
        sleep: noSleep,
      ),
      () => client,
    );
    expect(second.call.outcome, SettlementHttpOutcome.success);
    expect(sent.toSet(), {keys.current});

    final registered = applySettlementReconcile(
      state,
      const SettlementReconcileEvidence(
        status: OrchestraStatusReadKind.notFound,
        submit: SubmitAttemptOutcome.accepted,
      ),
      now: restartNow,
      foregroundedAt: restartNow,
    );
    expect(registered.stage, SettlementStage.submitted);
  });

}
