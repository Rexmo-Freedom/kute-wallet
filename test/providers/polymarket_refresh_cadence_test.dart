// While Predictions is open, the periodic refresh reads cash and positions
// every tick and the heavier reads (open orders, portfolio value, settled
// positions) every third tick. While a queued bet waits for its deposit the
// tick backs off to 30 s: the deposit's own path reads the balance when the
// money lands, and the autofire's safety-net poll runs every 15 s, so three
// loops no longer overlap.
import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/services/polymarket/deposit_timings_reporter.dart';
import 'package:kute/services/polymarket_onboarding_service.dart';
import 'package:kute/services/wallet_identity_service.dart';

void main() {
  test('every tick reads cash and positions; every third reads everything',
      () {
    final scopes = [for (var t = 1; t <= 6; t++) polymarketRefreshScopeForTick(t)];
    expect(scopes, [
      PolymarketRefreshScope.cash,
      PolymarketRefreshScope.cash,
      PolymarketRefreshScope.full,
      PolymarketRefreshScope.cash,
      PolymarketRefreshScope.cash,
      PolymarketRefreshScope.full,
    ]);
  });

  test('a waiting bet backs the tick off to 30 s whatever else is going on',
      () {
    int? seconds({bool waiting = false, bool deposit = false,
            bool visible = true, bool open = false, bool result = false}) =>
        polymarketRefreshIntervalSeconds(
          pendingBetWaiting: waiting,
          awaitingDeposit: deposit,
          visible: visible,
          hasOpenBet: open,
          awaitingResult: result,
          minMinutesToExpiry: open ? 10 : null,
        );
    expect(seconds(open: true), 3);
    expect(seconds(deposit: true), 3);
    expect(seconds(visible: false, open: true), 30);
    expect(seconds(visible: false, result: true), 20);
    expect(seconds(waiting: true), 30);
    expect(seconds(waiting: true, deposit: true, open: true), 30);
  });

  test('holding nothing and waiting for nothing: no periodic read at all',
      () {
    for (final visible in [true, false]) {
      expect(
          polymarketRefreshIntervalSeconds(
            pendingBetWaiting: false,
            awaitingDeposit: false,
            visible: visible,
            hasOpenBet: false,
            awaitingResult: false,
          ),
          isNull);
    }
  });

  test('the wrap receipt is read every second for 20 s, then every 2 s', () {
    expect(PolymarketOnboardingService.receiptPollInterval(Duration.zero),
        const Duration(seconds: 1));
    expect(
        PolymarketOnboardingService.receiptPollInterval(
            const Duration(seconds: 25)),
        const Duration(seconds: 2));
  });

  group('deposit timings report', () {
    setUp(() {
      dotenv.loadFromString(envString: 'BACKEND=https://backend.test');
      WalletIdentityService.debugBind(pubkey: null);
      AffiliateService.debugSessionToken = 'test-session';
    });
    tearDown(() {
      AffiliateService.debugSessionToken = null;
      PolymarketDepositTimingsReporter.client = http.Client.new;
    });

    test('posts RFC 3339 UTC times with the wallet session, and a 404 is '
        'silent', () async {
      http.Request? seen;
      PolymarketDepositTimingsReporter.client = () => MockClient((request) async {
            seen = request;
            return http.Response('not found', 404);
          });
      final wrapped = DateTime.utc(2026, 10, 12, 10, 0, 1);
      final bettable = DateTime.utc(2026, 10, 12, 10, 0, 3);
      await PolymarketDepositTimingsReporter.report(
          orderId: 'ord_1', wrappedAt: wrapped, bettableAt: bettable);
      expect(seen, isNotNull);
      expect(seen!.url.path, '/api/v1/orchestra/timings');
      expect(seen!.headers['Authorization'], 'Bearer test-session');
      final body = jsonDecode(seen!.body) as Map<String, dynamic>;
      expect(body, {
        'orderId': 'ord_1',
        'wrappedAt': '2026-10-12T10:00:01.000Z',
        'bettableAt': '2026-10-12T10:00:03.000Z',
      });
    });

    test('a dead link never throws', () async {
      PolymarketDepositTimingsReporter.client =
          () => MockClient((_) async => throw http.ClientException('offline'));
      await PolymarketDepositTimingsReporter.report(
          orderId: 'ord_1', wrappedAt: DateTime.now());
    });
  });
}
