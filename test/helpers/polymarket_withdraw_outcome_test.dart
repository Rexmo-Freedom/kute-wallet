import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/polymarket_withdraw_outcome.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/services/funding/settlement_funding_outcome.dart';
import 'package:kute/services/polymarket/hot_withdrawal_guard.dart';
import 'package:kute/services/polymarket_onboarding_service.dart';

void main() {
  group('polymarketWithdrawalFailure', () {
    test('a throw before the relayer hand-over is a refusal with its cause',
        () {
      final cause = StateError('balance read failed');
      final out = polymarketWithdrawalFailure(cause, submitted: false);
      expect(out, isA<SettlementFundingRefused>());
      expect((out as SettlementFundingRefused).cause, same(cause));
    });

    test('a throw after the hand-over is left alone: the outcome is unknown',
        () {
      final cause = Exception('relayer timed out');
      expect(polymarketWithdrawalFailure(cause, submitted: true), same(cause));
    });

    test('an error that already says it never submitted passes through', () {
      const earlier = EarlierPolymarketWithdrawalPending();
      expect(polymarketWithdrawalFailure(earlier, submitted: false),
          same(earlier));
      final refused = SettlementFundingRefused(StateError('x'));
      expect(polymarketWithdrawalFailure(refused, submitted: false),
          same(refused));
    });

    test(
        'a relayer 4xx and a missing wallet session say nothing was sent, '
        'even after the hand-over began', () {
      // Both are raised inside the submit itself: the relayer answered
      // with a refusal, or no session could be obtained to ask it.
      const rejected = RelayerSubmitRejected(400, '{"error":"wallet busy"}');
      expect(polymarketWithdrawalFailure(rejected, submitted: true),
          same(rejected));
      expect(rejected, isA<SettlementFundingNotStarted>());
      expect(rejected.toString(),
          'Relayer submit failed: 400 {"error":"wallet busy"}');
      const noSession = WalletSessionUnavailable('Sign in again');
      expect(noSession, isA<SettlementFundingNotStarted>());
      expect(polymarketWithdrawalFailure(noSession, submitted: true),
          same(noSession));
    });
  });
}
