// Every way a placement ends without an accepted order reaches PostHog
// with a closed stage. These are plain TrackingService.track calls: sent in
// release builds, muted in debug builds and by the person's opt-out.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/polymarket/placement_diagnostics.dart';
import 'package:kute/services/polymarket_backend_service.dart';
import 'package:kute/services/tracking_service.dart';

void main() {
  final events = <(String, Map<String, Object>?)>[];
  setUp(() {
    events.clear();
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });
  tearDown(() => TrackingService.debugTrackObserver = null);

  test('a declined placement names its stage', () {
    PolymarketPlacementDiagnostics.declined('region_or_policy');
    PolymarketPlacementDiagnostics.declined('approval_not_granted');
    PolymarketPlacementDiagnostics.declined('setup_timeout',
        error: TimeoutException('setup'));
    expect(events.map((e) => e.$2!['stage']),
        ['geo_blocked', 'user_declined', 'setup']);
    expect(events.map((e) => e.$1).toSet(), {'polymarket_placement_declined'});
  });

  test('a refusal carried by a decline is classed and cleaned', () {
    PolymarketPlacementDiagnostics.declined('outcome_unknown',
        error: const PolymarketOrderNotAcceptedException(
            'maker address 0x1111111111111111111111111111111111111111 '
            'not allowed'));
    final params = events.single.$2!;
    expect(params['stage'], 'submit');
    expect(params['refusal_class'], 'maker_not_allowed');
    expect(params['venue_refusal'], 'maker address not allowed');
  });

  test('a failed step carries its stage and error category', () {
    PolymarketPlacementDiagnostics.stepFailed(
        'order_book', TimeoutException('book'), const Duration(seconds: 5));
    final params = events.single.$2!;
    expect(events.single.$1, 'polymarket_placement_step_failed');
    expect(params['stage'], 'book');
    expect(params['timed_out'], true);
    expect(params['error_category'], 'timeout');
  });

  test('every decline reason the slip uses has a stage', () {
    for (final reason in [
      'region_or_policy',
      'insufficient_balance',
      'approval_not_granted',
      'setup_timeout',
      'setup_failed',
      'wallet_not_ready',
      'prepare_failed',
      'no_intent',
      'liquidity_unavailable',
      'side_mismatch',
      'advanced_unavailable',
    ]) {
      expect(PolymarketPlacementDiagnostics.declineStage(reason),
          isNot('unknown'),
          reason: reason);
    }
  });

  test('a self-heal names the spender it approved, never the address', () {
    PolymarketPlacementDiagnostics.selfHeal(
      heal: 'approveSpender',
      refusal: 'not enough balance / allowance: the allowance is not enough '
          '-> spender: 0xd91E80cF2E7be2e162c6513ceD06f1dD0dA35296, '
          'allowance: 0',
      attempt: 0,
      negRisk: true,
      result: 'sent',
    );
    final (name, params) = events.single;
    expect(name, 'polymarket_order_outcome');
    expect(params!['stage'], 'self_heal');
    expect(params['heal'], 'approveSpender');
    expect(params['heal_result'], 'sent');
    expect(params['spender'], 'neg_risk_adapter');
    expect(params['refusal_class'], 'allowance_not_enough');
    expect(params.values.join(' '), isNot(contains('0x')));
  });
}
