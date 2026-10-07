// Money-flow funnel helpers: started → step → submitted → outcome or one
// abandon per started instance, carrying what was entered and why.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/tracking_service.dart';

void main() {
  late List<(String, Map<String, Object>?)> seen;

  setUp(() {
    TrackingService.setDisabled(true);
    TrackingService.debugResetMoneyFlows();
    seen = [];
    TrackingService.debugTrackObserver = (e, p) => seen.add((e, p));
  });
  tearDown(() {
    TrackingService.debugTrackObserver = null;
    TrackingService.debugResetMoneyFlows();
  });

  List<String> names() => [for (final e in seen) e.$1];
  Map<String, Object>? paramsOf(String event) =>
      seen.lastWhere((e) => e.$1 == event).$2;

  test('a full funnel fires in order and never abandons after an outcome', () {
    TrackingService.moneyFlowStarted('move',
        event: 'move_sheet_opened',
        abandonEvent: 'move_sheet_abandoned',
        entrySource: 'home',
        walletKind: 'hot',
        props: {'locked_side': 'none'});
    TrackingService.moneyFlowStep('move', 'amount_entered',
        props: {'amount_usd': 12.5});
    TrackingService.moneyFlowStep('move', 'amount_entered'); // repeat: no-op
    TrackingService.moneyFlowSubmitted('move', props: {'amount_usd': 12.5});
    TrackingService.moneyFlowFinished('move');
    TrackingService.moneyFlowAbandoned('move');

    expect(names(), ['move_sheet_opened', 'move_step', 'move_submitted']);
    expect(paramsOf('move_sheet_opened'), {
      'entry_source': 'home',
      'wallet_kind': 'hot',
      'locked_side': 'none',
    });
    expect(
        paramsOf('move_step'), {'step': 'amount_entered', 'amount_usd': 12.5});
  });

  test('abandon carries the last step, the inputs, a reason and a time bucket',
      () {
    TrackingService.moneyFlowStarted('send',
        event: 'send_flow_started',
        abandonEvent: 'send_flow_abandoned',
        entrySource: 'scanner',
        network: 'lightning');
    TrackingService.moneyFlowStep('send', 'review');
    TrackingService.moneyFlowError('send', 'Insufficient funds for payment');
    TrackingService.moneyFlowAbandoned('send',
        props: {'amount_usd': 3.0, 'network': 'lightning'});
    TrackingService.moneyFlowAbandoned('send'); // second close: nothing

    expect(names(), ['send_flow_started', 'send_step', 'send_flow_abandoned']);
    expect(paramsOf('send_flow_abandoned'), {
      'step': 'review',
      'reason': 'insufficient_balance',
      'time_in_flow_bucket': '<10s',
      'last_error_category': 'insufficient_funds',
      'amount_usd': 3.0,
      'network': 'lightning',
    });
  });

  test('an explicit abandon reason wins and a fresh flow has none', () {
    TrackingService.moneyFlowStarted('buy', entrySource: 'add_funds');
    TrackingService.moneyFlowAbandoned('buy', reason: 'geoblocked');
    expect(paramsOf('buy_abandoned')!['reason'], 'geoblocked');
    expect(
        paramsOf('buy_abandoned')!.containsKey('last_error_category'), isFalse);
    // Errors recorded for a flow that is not running are dropped.
    TrackingService.moneyFlowError('buy', 'timeout');
    TrackingService.moneyFlowStarted('buy', entrySource: 'activity');
    TrackingService.moneyFlowAbandoned('buy');
    expect(paramsOf('buy_abandoned')!['reason'], 'user_closed');
  });

  test('<flow>_failed classifies the error and ends the flow', () {
    TrackingService.moneyFlowStarted('receive', entrySource: 'home');
    TrackingService.moneyFlowFailed('receive',
        error: 'Connection timed out', stage: 'quote', props: {'asset': 'btc'});
    TrackingService.moneyFlowAbandoned('receive');
    expect(names(), ['receive_started', 'receive_failed']);
    expect(paramsOf('receive_failed'), {
      'error_category': 'timeout',
      'stage': 'quote',
      'asset': 'btc',
    });
  });

  test('abandon reasons map from error categories', () {
    expect(TrackingService.abandonReasonFor(null), 'user_closed');
    expect(TrackingService.abandonReasonFor('quote_rejected'), 'quote_failed');
    expect(TrackingService.abandonReasonFor('no_route'), 'route_unavailable');
    expect(TrackingService.abandonReasonFor('network'), 'backend_unreachable');
    expect(
        TrackingService.abandonReasonFor('user_cancelled'), 'signing_declined');
    expect(TrackingService.abandonReasonFor('below_minimum'), 'below_minimum');
    expect(TrackingService.abandonReasonFor('unknown'), 'error_shown');
  });

  test('time buckets', () {
    expect(
        TrackingService.timeInFlowBucket(const Duration(seconds: 3)), '<10s');
    expect(TrackingService.timeInFlowBucket(const Duration(seconds: 20)),
        '10-30s');
    expect(TrackingService.timeInFlowBucket(const Duration(seconds: 90)),
        '30s-2m');
    expect(
        TrackingService.timeInFlowBucket(const Duration(minutes: 5)), '2-10m');
    expect(TrackingService.timeInFlowBucket(const Duration(hours: 1)), '10m+');
  });

  test('entry sources are consumed once and outcomes dedupe on a hashed key',
      () {
    TrackingService.markEntrySource('send', 'scanner');
    expect(TrackingService.takeEntrySource('send'), 'scanner');
    expect(TrackingService.takeEntrySource('send'), 'unknown');
    expect(TrackingService.takeEntrySource('send', fallback: 'prefilled'),
        'prefilled');
    expect(TrackingService.claimOutcome('move_completed', 'order-1'), isTrue);
    expect(TrackingService.claimOutcome('move_completed', 'order-1'), isFalse);
    expect(TrackingService.claimOutcome('move_failed', 'order-1'), isTrue);
  });

  test('route params are lower-cased and only carry what is given', () {
    expect(
        TrackingService.routeParams(
            fromAsset: 'BTC',
            fromNetwork: 'Spark',
            toAsset: 'USDC.e',
            toNetwork: 'Polygon',
            provider: 'Orchestra',
            venue: 'polymarket'),
        {
          'from_asset': 'btc',
          'from_network': 'spark',
          'to_asset': 'usdc.e',
          'to_network': 'polygon',
          'provider': 'orchestra',
          'venue': 'polymarket',
        });
    expect(TrackingService.routeParams(toAsset: 'BTC'), {'to_asset': 'btc'});
  });

  test('a started flow sets the crash flow context and finishing clears it',
      () {
    TrackingService.debugResetCrashContext();
    TrackingService.moneyFlowStarted('send',
        entrySource: 'home', network: 'spark', walletKind: 'hot');
    TrackingService.moneyFlowStep('send', 'review');
    expect(TrackingService.crashContext['last_flow'], 'send');
    expect(TrackingService.crashContext['last_step'], 'review');
    expect(TrackingService.crashContextLines(), contains('network: spark'));
    TrackingService.moneyFlowFinished('send');
    expect(TrackingService.crashContext['last_flow'], 'none');
  });
}
