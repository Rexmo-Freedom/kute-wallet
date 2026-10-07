import 'dart:convert';

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
}
