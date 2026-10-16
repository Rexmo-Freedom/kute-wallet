// PostHog gets exact values. Every legacy `*_bucket` property stays for the
// dashboards built on it, and the exact figure rides beside it under a
// plain name (`*_usd`, `*_ms`, `*_seconds`, counts).

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/exit_reason_service.dart';
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

  Map<String, Object> paramsOf(String event) =>
      seen.lastWhere((e) => e.$1 == event).$2 ?? const {};

  test(
      'exactUsd rounds to the cent, keeps the sign, drops what is not a '
      'number', () {
    expect(
        TrackingService.exactUsd('amount_usd', 12.345), {'amount_usd': 12.35});
    expect(TrackingService.exactUsd('pnl_usd', -3.2), {'pnl_usd': -3.2});
    expect(TrackingService.exactUsd('amount_usd', null), isEmpty);
    expect(TrackingService.exactUsd('amount_usd', double.nan), isEmpty);
    expect(TrackingService.exactUsd('amount_usd', double.infinity), isEmpty);
  });

  test('money events carry the exact amount beside the bucket', () {
    TrackingService.cashAppPurchaseCreated(amountUsd: 42.5);
    expect(
        paramsOf('cashapp_purchase_created'), containsPair('amount_usd', 42.5));
    expect(paramsOf('cashapp_purchase_created'),
        containsPair('amount_bucket', '10-100'));

    TrackingService.cashAppLimitReached(remaining: 180.01);
    expect(paramsOf('cashapp_limit_reached'), {
      'remaining_bucket': '100-1k',
      'remaining_usd': 180.01,
    });

    TrackingService.polymarketWithdrawInitiated(amountUsdc: 7.5);
    expect(paramsOf('polymarket_withdraw_initiated'), {
      'amount_bucket': '1-10',
      'amount_usd': 7.5,
      'venue': 'polymarket',
    });

    TrackingService.polymarketDepositConverted(
        amountUsd: 3.21, trigger: 'open');
    expect(paramsOf('polymarket_deposit_converted'),
        containsPair('amount_usd', 3.21));

    TrackingService.polymarketBetConfirmationShown(
        marketId: 'm', amountUsdc: 15);
    expect(paramsOf('polymarket_bet_confirmation_shown'),
        containsPair('amount_usd', 15.0));

    TrackingService.polymarketPositionWinLoss(
        marketId: 'm', pnl: -4.56, outcome: 'loss');
    expect(paramsOf('polymarket_position_win_loss'), {
      'market_id': 'm',
      'pnl_usd': -4.56,
      'pnl_bucket': '1-10',
      'outcome': 'loss',
    });

    TrackingService.paymentLinkCreated(amountUsd: 9.99);
    expect(paramsOf('payment_link_created'),
        {'amount_bucket': '1-10', 'amount_usd': 9.99});

    TrackingService.crossChainQuoteRequested(
        sourceChain: 'spark',
        sourceAsset: 'btc',
        destinationChain: 'polygon',
        destinationAsset: 'usdc',
        amountUsd: 101);
    expect(paramsOf('cross_chain_quote_requested'),
        containsPair('amount_usd', 101.0));

    TrackingService.polymarketViewed(
        marketId: 'm', liquidityUsd: 12345.678, outcomeCount: 4);
    final viewed = paramsOf('polymarket_viewed');
    expect(viewed['liquidity_usd'], 12345.68);
    expect(viewed['liquidity_bucket'], '10k+');
    expect(viewed['outcome_count'], 4);
    expect(viewed['outcome_count_bucket'], 'multi_small');
  });

  test('Ledger funding events carry the exact amount', () {
    TrackingService.ledgerFundingResult(
        route: 'r',
        outcome: 'submitted',
        amountBucket: '10-100',
        amountUsd: 25.4);
    expect(paramsOf('ledger_funding_result'), {
      'route': 'r',
      'outcome': 'submitted',
      'amount_bucket': '10-100',
      'amount_usd': 25.4,
    });
    TrackingService.ledgerFundingBroadcast(
        route: 'r', amountBucket: '1-10', amountUsd: 2.5);
    expect(
        paramsOf('ledger_funding_broadcast'), containsPair('amount_usd', 2.5));
    TrackingService.ledgerPmFundsMadeAvailable(
        amountBucket: '1-10', amountUsd: 3);
    expect(paramsOf('ledger_pm_funds_made_available'),
        containsPair('amount_usd', 3.0));
    TrackingService.ledgerPmCollateralUnwrapped(
        amountBucket: '1-10', amountUsd: 4);
    expect(paramsOf('ledger_pm_collateral_unwrapped'),
        containsPair('amount_usd', 4.0));
    TrackingService.ledgerPmMakeAvailableResult(
        outcome: 'success', amountBucket: '1-10', amountUsd: 5);
    expect(paramsOf('ledger_pm_make_available_result'),
        containsPair('amount_usd', 5.0));
    TrackingService.ledgerActionSubmitted(
        action: 'btc_to_hypercore', amountUsd: 61.234);
    expect(paramsOf('ledger_action_submitted'), {
      'action': 'btc_to_hypercore',
      'amount_bucket': '10-100',
      'amount_usd': 61.23,
    });
  });

  test('durations, counts and lengths go exact beside their buckets', () {
    TrackingService.appSession(durationSeconds: 95);
    expect(paramsOf('app_session'),
        {'duration_seconds': 95, 'duration_bucket': '30s-2m'});

    TrackingService.appColdStart(latencyMs: 1234);
    expect(paramsOf('app_cold_start'),
        {'latency_ms': 1234, 'latency_bucket': '1-3s'});

    TrackingService.sparkSdkConnect(result: 'ok', latencyMs: 420);
    expect(paramsOf('spark_sdk_connect'), containsPair('latency_ms', 420));

    TrackingService.bdkScan(result: 'ok', latencyMs: 6000, source: 'move');
    expect(paramsOf('bdk_scan'), containsPair('latency_ms', 6000));

    TrackingService.salQuestionAsked(
        input: 'typed', queryLength: 37, turnIndex: 2);
    final asked = paramsOf('sal_question_asked');
    expect(asked['query_length'], 37);
    expect(asked['query_length_bucket'], '21-60');
    expect(asked['turn_index'], 2);
    expect(asked['turn'], '2-3');

    TrackingService.salAnswerReceived(
        blockCount: 2, marketCards: 1, latencyMs: 4200);
    expect(paramsOf('sal_answer_received'), containsPair('latency_ms', 4200));

    TrackingService.changePinBlocked(walletCount: 5);
    expect(paramsOf('change_pin_blocked'),
        {'wallet_count': 5, 'wallet_count_bucket': '4+'});

    TrackingService.compromiseAddressesRetired(7);
    expect(paramsOf('compromise_addresses_retired'),
        {'outcome': 'success', 'count': 7, 'count_bucket': '6+'});

    TrackingService.polymarketListScrolled(depthPct: 80);
    expect(paramsOf('polymarket_list_scrolled'),
        {'depth_pct': 80, 'depth_bucket': '75'});

    expect(
        TrackingService.settlementOperationStartedParams(
            flow: 'f', routeVersion: 'v1', amountUsd: 33.333),
        {
          'flow': 'f',
          'route_version': 'v1',
          'amount_bucket': '10-100',
          'amount_usd': 33.33,
        });
    expect(
        TrackingService.settlementSubmitAttemptParams(
            flow: 'f', attempts: 4, outcome: 'ok'),
        {'flow': 'f', 'attempts': 4, 'attempt_bucket': '3-5', 'outcome': 'ok'});
    expect(
        TrackingService.settlementTerminalParams(
            route: 'r',
            outcome: 'done',
            duration: const Duration(minutes: 7, seconds: 3)),
        {
          'route': 'r',
          'outcome': 'done',
          'duration_ms': 423000,
          'duration_bucket': '5m-1h',
        });
  });

  test('an abandoned money flow says how long, exactly', () {
    TrackingService.moneyFlowStarted('send', entrySource: 'home');
    TrackingService.moneyFlowAbandoned('send');
    final p = paramsOf('send_abandoned');
    expect(p['time_in_flow_ms'], isA<int>());
    expect(p['time_in_flow_ms'] as int, lessThan(10000));
    expect(p['time_in_flow_bucket'], '<10s');
  });

  test('a previous exit carries its exact resident memory', () {
    expect(ExitReasonService.rssKbExact(524288), 524288);
    expect(ExitReasonService.rssKbExact('2048'), 2048);
    expect(ExitReasonService.rssKbExact(null), isNull);
    expect(ExitReasonService.rssKbExact(0), isNull);
    expect(ExitReasonService.rssMbBucket(524288), '512-1024');
  });
}
