// A pending one-time receive quote is watched past its expiry for a late
// deposit (kOneTimeReceiveLateDepositWatch, 24 h), then retired: before,
// a quote no deposit ever paid stayed in the cache for good and the sweep
// kept reading it every 6 h, with its check record growing beside it.
// The retirement takes one last look first, so a deposit that landed
// while the app was away still gets its order; a failed last look keeps
// the quote for the next pass.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/background_sync_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/spark_address_provider.dart';
import 'package:kute/services/http/shared_http_client.dart';
import 'package:kute/services/orchestra/onetime_receive.dart'
    show kOneTimeReceiveLateDepositWatch;
import 'package:kute/services/orchestra/pending_receive_quote_cache.dart';

const _spark =
    'sp1pgssy7d7vel0nh9m4326qc54e6rskpczn07dktww9rv4nu5ptvt0s9ucez8h3s';

SwapOrder _quote(String id) => SwapOrder(
      id: id,
      coinFrom: 'USDT',
      networkFrom: 'ethereum',
      coinTo: 'USDB',
      networkTo: 'spark',
      depositAddress: '0x1111111111111111111111111111111111111111',
      depositAmount: '25',
      withdrawalAmount: '24.8',
      status: 'wait',
      timestamp: DateTime.utc(2026, 10, 1).millisecondsSinceEpoch,
      withdrawalAddress: _spark,
      depositMin: '0',
      depositMax: '0',
      rate: '0',
      refundAddress: '',
      provider: 'Orchestra',
      walletId: 'spending',
      purchaseSource: 'crypto_receive',
    );

void main() {
  late Directory tmp;
  late List<String> statusReads;
  late bool statusFails;

  setUpAll(() {
    if (!Hive.isAdapterRegistered(SwapOrderAdapter().typeId)) {
      Hive.registerAdapter(SwapOrderAdapter());
    }
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('receive_quote_sweep_');
    Hive.init(tmp.path);
    dotenv.loadFromString(envString: 'BACKEND=https://backend.test');
    AffiliateService.debugSessionToken = 'test-session';
    statusReads = [];
    statusFails = false;
    SharedHttpClient.debugOverride = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/status')) {
        statusReads.add(request.url.queryParameters['quoteId'] ?? '');
        if (statusFails) return http.Response('', 503);
        // The quote's status with no order: nothing was paid.
        return http.Response(
            jsonEncode({'order': null, 'status': 'expired'}), 200);
      }
      if (path.endsWith('/history')) {
        if (statusFails) return http.Response('', 503);
        return http.Response(jsonEncode({'orders': <Object>[]}), 200);
      }
      return http.Response('', 404);
    });
  });

  tearDown(() async {
    SharedHttpClient.debugOverride = null;
    AffiliateService.debugSessionToken = null;
    await PendingReceiveQuoteCache.clear();
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  ProviderContainer container() {
    final c = ProviderContainer(overrides: [
      settingsProvider.overrideWith((_) => SettingsModel(Settings(
            currency: 'USD',
            language: 'en',
            btcFormat: 'sats',
            backup: false,
            biometricsEnabled: false,
            bitcoinElectrumNode: '',
            nodeType: 'Blockstream',
            reviewDone: true,
            activeWalletId: 'spending',
            wallets: [WalletConfig(id: 'spending', name: 'Spending')],
          ))),
      sparkSelfAddressProvider.overrideWith((_) async => _spark),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  Future<void> save(String id, DateTime expiresAt) =>
      PendingReceiveQuoteCache.save(
          display: _quote(id),
          expiresAt: expiresAt,
          scope: PendingReceiveQuoteCache.capture('spending'));

  Future<Set<String>> pendingIds() async =>
      (await PendingReceiveQuoteCache.pending()).map((q) => q.id).toSet();

  test(
      'the cadence: fast while fresh, slower after an hour, a last look '
      'past the late-deposit watch', () {
    expect(receiveQuoteSweepStep(const Duration(minutes: -1)),
        (interval: const Duration(seconds: 30), last: false));
    expect(receiveQuoteSweepStep(const Duration(minutes: 30)),
        (interval: const Duration(seconds: 30), last: false));
    expect(receiveQuoteSweepStep(const Duration(hours: 2)),
        (interval: const Duration(minutes: 5), last: false));
    expect(receiveQuoteSweepStep(kOneTimeReceiveLateDepositWatch).last, isFalse,
        reason: 'watched through the whole window');
    expect(
        receiveQuoteSweepStep(
            kOneTimeReceiveLateDepositWatch + const Duration(hours: 1)),
        (interval: Duration.zero, last: true));
  });

  test(
      'a quote 25 h past expiry is read once more and retired; one 1 h '
      'past stays watched', () async {
    final now = DateTime.now();
    await save('q_old', now.subtract(const Duration(hours: 25)));
    await save('q_recent', now.subtract(const Duration(hours: 1)));
    final c = container();
    await c
        .read(backgroundSyncNotifierProvider.notifier)
        .pollReceiveAddresses(force: true);

    expect(statusReads, containsAll(['q_old', 'q_recent']),
        reason: 'the last look before retiring, and the recent watch');
    expect(await pendingIds(), {'q_recent'});
  });

  test('a failed last look (status and history) keeps the quote', () async {
    statusFails = true;
    await save('q_old', DateTime.now().subtract(const Duration(hours: 25)));
    final c = container();
    await c
        .read(backgroundSyncNotifierProvider.notifier)
        .pollReceiveAddresses(force: true);
    expect(statusReads, ['q_old']);
    expect(await pendingIds(), {'q_old'});
  });
}
