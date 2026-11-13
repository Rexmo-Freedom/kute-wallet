import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/services/polymarket/relayer_transaction.dart';
import 'package:kute/services/polymarket_onboarding_service.dart';

void main() {
  final hash = '0x${'ab' * 32}';
  final exact = {
    'transactionID': 'wanted',
    'state': 'STATE_CONFIRMED',
    'transactionHash': hash
  };

  test('finds the requested transaction regardless of list ordering', () {
    expect(
        relayerTransactionForId([
          {'transactionID': 'other', 'state': 'STATE_FAILED'},
          exact,
        ], 'wanted'),
        exact);
  });

  for (final payload in [
    null,
    [],
    {},
    {'state': 'STATE_CONFIRMED', 'transactionHash': hash},
    [exact, exact],
    [
      {'transactionID': 'other', 'state': 'STATE_FAILED'}
    ],
  ]) {
    test(
        'unrelated, missing or ambiguous identity remains unresolved: $payload',
        () {
      expect(relayerTransactionForId(payload, 'wanted'), isNull);
    });
  }

  test('production reconciliation rejects an unrelated confirmed transfer',
      () async {
    final result = await http.runWithClient(
      () => PolymarketOnboardingService().relayerTransactionState('wanted'),
      () => MockClient((request) async {
        expect(request.url.queryParameters['id'], 'wanted');
        return http.Response(
            jsonEncode([
              {
                ...exact,
                'transactionID': 'different',
              }
            ]),
            200);
      }),
    );
    expect(result, isNull);
  });

  test('production reconciliation returns only the requested operation',
      () async {
    final result = await http.runWithClient(
      () => PolymarketOnboardingService().relayerTransactionState('wanted'),
      () => MockClient((_) async => http.Response(
          jsonEncode([
            {'transactionID': 'other', 'state': 'STATE_FAILED'},
            exact,
          ]),
          200)),
    );
    expect(result, (state: 'STATE_CONFIRMED', hash: hash));
  });

  group('the receipt poll', () {
    // The relayer's own vocabulary (`RelayerTransactionState` in
    // @polymarket/builder-relayer-client): STATE_NEW, STATE_EXECUTED,
    // STATE_MINED, STATE_CONFIRMED; STATE_FAILED and STATE_INVALID end it.
    test('reads MINED and CONFIRMED by the relayer\'s own words', () {
      expect(PolymarketOnboardingService.relayerStateMined('STATE_MINED'),
          isTrue);
      expect(PolymarketOnboardingService.relayerStateMined('STATE_EXECUTED'),
          isFalse);
      expect(
          PolymarketOnboardingService.relayerStateMined('STATE_NEW'), isFalse);
      expect(PolymarketOnboardingService.relayerStateMined('STATE_CONFIRMED'),
          isFalse);
      expect(
          PolymarketOnboardingService.relayerStateConfirmed('STATE_CONFIRMED'),
          isTrue);
      expect(PolymarketOnboardingService.relayerStateConfirmed('STATE_MINED'),
          isFalse);
      expect(PolymarketOnboardingService.relayerStateConfirmed('STATE_FAILED'),
          isFalse);
    });

    test(
        'asks the relayer twice a second for 15 s, then every second to '
        '30 s, then every 2 s (was every second for 20 s, then every 2 s)',
        () {
      Duration at(int ms) =>
          PolymarketOnboardingService.relayerReceiptPollInterval(
              Duration(milliseconds: ms));
      expect(at(0), const Duration(milliseconds: 500));
      expect(at(14999), const Duration(milliseconds: 500));
      expect(at(15000), const Duration(seconds: 1));
      expect(at(29999), const Duration(seconds: 1));
      expect(at(30000), const Duration(seconds: 2));
      // The deposit path's wallet re-read keeps its own cadence.
      expect(PolymarketOnboardingService.receiptPollInterval(Duration.zero),
          const Duration(seconds: 1));
    });

    test(
        'tells the caller at MINED and goes on to CONFIRMED: the book is '
        'asked two polls (1 s) before the conversion is confirmed', () {
      fakeAsync((async) {
        // What the relayer answers on each poll, in order.
        final states = [
          'STATE_NEW',
          'STATE_MINED',
          'STATE_MINED',
          'STATE_CONFIRMED'
        ];
        var polls = 0;
        Duration? minedAt;
        String? confirmedHash;
        Duration? confirmedAt;
        http.runWithClient(
          () => PolymarketOnboardingService()
              .pollTransactionForTest('wanted',
                  requireConfirmed: true,
                  onMined: () => minedAt = async.elapsed)
              .then((h) {
            confirmedHash = h;
            confirmedAt = async.elapsed;
          }),
          () => MockClient((request) async {
            expect(request.url.queryParameters['id'], 'wanted');
            final state = states[polls.clamp(0, states.length - 1)];
            polls++;
            return http.Response(
                jsonEncode([
                  {
                    'transactionID': 'wanted',
                    'state': state,
                    if (state == 'STATE_CONFIRMED') 'transactionHash': hash,
                  }
                ]),
                200);
          }),
        );
        async.flushMicrotasks();
        expect(polls, 1);
        expect(minedAt, isNull);
        async.elapse(const Duration(milliseconds: 500));
        expect(polls, 2);
        expect(minedAt, const Duration(milliseconds: 500),
            reason: 'told once, on the first MINED');
        expect(confirmedHash, isNull, reason: 'still waiting for CONFIRMED');
        async.elapse(const Duration(milliseconds: 500));
        expect(polls, 3);
        async.elapse(const Duration(milliseconds: 500));
        expect(polls, 4);
        expect(confirmedHash, hash);
        expect(confirmedAt, const Duration(milliseconds: 1500));
        // Before this change the book was asked only here, at CONFIRMED.
        expect(confirmedAt! - minedAt!, const Duration(seconds: 1));
      });
    });

    test('a batch already confirmed on the first read tells the caller once',
        () {
      fakeAsync((async) {
        var told = 0;
        String? got;
        http.runWithClient(
          () => PolymarketOnboardingService()
              .pollTransactionForTest('wanted',
                  requireConfirmed: true, onMined: () => told++)
              .then((h) => got = h),
          () =>
              MockClient((_) async => http.Response(jsonEncode([exact]), 200)),
        );
        async.flushMicrotasks();
        expect(got, hash);
        expect(told, 1);
      });
    });

    test('without requireConfirmed MINED is the answer and nothing is told',
        () {
      fakeAsync((async) {
        var told = 0;
        String? got;
        http.runWithClient(
          () => PolymarketOnboardingService()
              .pollTransactionForTest('wanted', onMined: () => told++)
              .then((h) => got = h),
          () => MockClient((_) async => http.Response(
              jsonEncode([
                {
                  'transactionID': 'wanted',
                  'state': 'STATE_MINED',
                  'transactionHash': hash
                }
              ]),
              200)),
        );
        async.flushMicrotasks();
        expect(got, hash);
        expect(told, 0);
      });
    });
  });
}
