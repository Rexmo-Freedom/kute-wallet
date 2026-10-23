// A one-time receive has no Activity row until a deposit is detected: the
// address screen persists only its pending quote, and the deposit poller
// writes the real order's row (`ord_…`) when Orchestra's history reports
// it, then retires the pending quote.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/providers/transactions_provider.dart'
    show walletTransactionCacheProvider;
import 'package:kute/screens/receive/orchestra_deposit_poller.dart';
import 'package:kute/services/http/shared_http_client.dart';
import 'package:kute/services/orchestra/pending_receive_quote_cache.dart';

const _spark =
    'spark1pgss93sy072yrmtad5cy2srwjhq8ekzuw78yhr808jn6htqfh9w8p8h9mfwlv9';
const _deposit = '0x1111111111111111111111111111111111111111';
const _refund = '0x52908400098527886e0f7030069857d2e4169ee7';
const _wallet = 'spending';

SwapOrder _quote() => SwapOrder(
      activityDirection: 'receive',
      id: 'q_onetime_1',
      coinFrom: 'USDC',
      networkFrom: 'polygon',
      coinTo: 'BTC',
      networkTo: 'SPARK',
      depositAddress: _deposit,
      depositAmount: '4.14',
      withdrawalAmount: '0.000069',
      status: 'wait',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      withdrawalAddress: _spark,
      depositMin: '0',
      depositMax: '0',
      rate: '0',
      refundAddress: _refund,
      provider: 'Orchestra',
      walletId: _wallet,
      expiresAt:
          DateTime.now().add(const Duration(minutes: 2)).millisecondsSinceEpoch,
      purchaseSource: 'crypto_receive',
    );

void main() {
  late Directory directory;

  setUpAll(() {
    dotenv.loadFromString(envString: 'BACKEND=https://backend.test');
    if (!Hive.isAdapterRegistered(SwapOrderAdapter().typeId)) {
      Hive.registerAdapter(SwapOrderAdapter());
    }
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('deposit-poller-test-');
    Hive.init(directory.path);
    await Hive.openBox<SwapOrder>(kSwapOrdersBoxName);
    AffiliateService.debugSessionToken = 'test-session';
  });

  tearDown(() async {
    SharedHttpClient.debugOverride = null;
    AffiliateService.debugSessionToken = null;
    await PendingReceiveQuoteCache.clear();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  testWidgets(
      'no Activity row before a deposit; the order becomes the first row '
      'when history reports it, and the pending quote retires', (tester) async {
    final quote = _quote();
    var orders = <Map<String, dynamic>>[];
    SharedHttpClient.debugOverride = MockClient((request) async {
      expect(request.url.path, endsWith('/history'));
      return http.Response(jsonEncode({'orders': orders}), 200);
    });

    late WidgetRef ref;
    await tester.pumpWidget(ProviderScope(
      child: Consumer(builder: (context, r, _) {
        ref = r;
        return const SizedBox();
      }),
    ));

    await tester.runAsync(() async {
      await PendingReceiveQuoteCache.save(
          display: quote,
          expiresAt: DateTime.fromMillisecondsSinceEpoch(quote.expiresAt!),
          scope: PendingReceiveQuoteCache.capture(_wallet));
      final poller = OrchestraDepositPoller(ref,
          interval: const Duration(milliseconds: 20));
      poller.start(quote, stillWanted: () => true, onProgress: (_) {});

      // Polled with nothing sent: no row anywhere, the quote still watched.
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(ref.read(swapOrdersProvider), isEmpty);
      expect(ref.read(walletTransactionCacheProvider)[_wallet], isNull);
      expect((await PendingReceiveQuoteCache.pending()).map((q) => q.id),
          ['q_onetime_1']);

      // The deposit lands.
      orders = [
        {
          'id': 'ord_onetime_1',
          'quoteId': 'q_onetime_1',
          'status': 'processing',
          'sourceChain': 'polygon',
          'sourceAsset': 'USDC',
          'destinationChain': 'spark',
          'destinationAsset': 'BTC',
          'depositAddress': _deposit,
          'recipientAddress': _spark,
          'amountIn': '4140000',
          'amountOut': '6900',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        }
      ];
      for (var i = 0; i < 50 && ref.read(swapOrdersProvider).isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      poller.cancel();

      final rows = ref.read(swapOrdersProvider);
      expect(rows.map((r) => r.id), ['ord_onetime_1']);
      expect(rows.single.activityDirection, 'receive');
      expect(rows.single.purchaseSource, 'crypto_receive');
      expect(
          ref
              .read(walletTransactionCacheProvider)[_wallet]!
              .swapOrderTransactions
              .map((t) => t.id),
          ['ord_onetime_1']);
      expect(await PendingReceiveQuoteCache.pending(), isEmpty);
    });
  });
}
