import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/models/swap_order_model.dart';

void main() {
  // ---------------------------------------------------------------------------
  // SwapOrder
  // ---------------------------------------------------------------------------
  group('SwapOrder', () {
    Map<String, dynamic> fullJson() => {
          'id': 'shift-abc123',
          'depositCoin': 'usdt',
          'depositNetwork': 'tron',
          'settleCoin': 'btc',
          'settleNetwork': 'bitcoin',
          'depositAddress': 'TXyz123...',
          'depositMemo': 'memo123',
          'depositAmount': '100',
          'settleAmount': '0.0015',
          'status': 'wait',
          'createdAt': '2025-06-15T12:00:00Z',
          'settleAddress': 'bc1qxyz...',
          'depositMin': '10',
          'depositMax': '50000',
          'rate': '0.000015',
          'refundAddress': 'TRefund...',
          'refundMemo': 'refMemo',
          'expiresAt': '2025-06-15T14:00:00Z',
        };

    test('fromJson complete', () {
      final exchange = SwapOrder.fromJson(fullJson());
      expect(exchange.id, 'shift-abc123');
      expect(exchange.coinFrom, 'USDT');
      expect(exchange.networkFrom, 'tron');
      expect(exchange.coinTo, 'BTC');
      expect(exchange.networkTo, 'bitcoin');
      expect(exchange.depositAddress, 'TXyz123...');
      expect(exchange.depositExtraId, 'memo123');
      expect(exchange.depositAmount, '100');
      expect(exchange.withdrawalAmount, '0.0015');
      expect(exchange.status, 'wait');
      expect(exchange.withdrawalAddress, 'bc1qxyz...');
      expect(exchange.depositMin, '10');
      expect(exchange.depositMax, '50000');
      expect(exchange.rate, '0.000015');
      expect(exchange.refundAddress, 'TRefund...');
      expect(exchange.refundExtraId, 'refMemo');
      expect(exchange.expiresAt, isNotNull);
    });

    test('fromJson missing fields default gracefully', () {
      final exchange = SwapOrder.fromJson({});
      expect(exchange.id, '');
      expect(exchange.coinFrom, '');
      expect(exchange.coinTo, '');
      expect(exchange.depositAddress, '');
      expect(exchange.depositAmount, '0');
      expect(exchange.withdrawalAmount, '0');
      expect(exchange.depositMin, '0');
      expect(exchange.depositMax, '0');
      expect(exchange.rate, '0');
      expect(exchange.refundAddress, '');
      expect(exchange.depositExtraId, isNull);
      expect(exchange.refundExtraId, isNull);
      expect(exchange.expiresAt, isNull);
    });

    test('the saved status passes through unchanged', () {
      for (final status in ['wait', 'confirmation', 'custom_status']) {
        final e = SwapOrder.fromJson({...fullJson(), 'status': status});
        expect(e.status, status);
      }
    });

    group('backwards-compatible getters', () {
      test('depositCoin, depositNetwork, settleCoin, settleNetwork', () {
        final e = SwapOrder.fromJson(fullJson());
        expect(e.depositCoin, 'USDT');
        expect(e.depositNetwork, 'tron');
        expect(e.settleCoin, 'BTC');
        expect(e.settleNetwork, 'bitcoin');
      });

      test('settleAddress returns withdrawalAddress', () {
        final e = SwapOrder.fromJson(fullJson());
        expect(e.settleAddress, 'bc1qxyz...');
      });

      test('settleAmount returns withdrawalAmount', () {
        final e = SwapOrder.fromJson(fullJson());
        expect(e.settleAmount, '0.0015');
      });

      test('depositMemo returns depositExtraId', () {
        final e = SwapOrder.fromJson(fullJson());
        expect(e.depositMemo, 'memo123');
      });
    });

    group('amount parsing', () {
      test('amount parses depositAmount as double', () {
        final e = SwapOrder.fromJson({...fullJson(), 'depositAmount': '123.456'});
        expect(e.amount, closeTo(123.456, 1e-6));
      });

      test('amountTo parses withdrawalAmount as double', () {
        final e = SwapOrder.fromJson({...fullJson(), 'settleAmount': '0.0015'});
        expect(e.amountTo, closeTo(0.0015, 1e-10));
      });

      test('amount defaults to 0 for non-numeric string', () {
        final e = SwapOrder(
          id: 'x',
          coinFrom: 'BTC',
          networkFrom: 'bitcoin',
          coinTo: 'ETH',
          networkTo: 'ethereum',
          depositAddress: 'addr',
          depositAmount: 'invalid',
          withdrawalAmount: 'bad',
          status: 'wait',
          timestamp: 0,
          withdrawalAddress: 'addr2',
          depositMin: '0',
          depositMax: '0',
          rate: '0',
          refundAddress: '',
        );
        expect(e.amount, 0.0);
        expect(e.amountTo, 0.0);
      });
    });

    group('createdAt', () {
      test('returns DateTime from timestamp', () {
        final e = SwapOrder.fromJson(fullJson());
        expect(e.createdAt, isA<DateTime>());
        expect(e.createdAt.year, 2025);
        expect(e.createdAt.month, 6);
        expect(e.createdAt.day, 15);
      });
    });

    group('providerName', () {
      test('defaults to SideShift when provider is null', () {
        final e = SwapOrder.fromJson(fullJson());
        expect(e.providerName, 'SideShift');
      });

      test('returns provider when set', () {
        final e = SwapOrder(
          id: 'x',
          coinFrom: 'BTC',
          networkFrom: 'bitcoin',
          coinTo: 'ETH',
          networkTo: 'ethereum',
          depositAddress: 'addr',
          depositAmount: '1',
          withdrawalAmount: '15',
          status: 'wait',
          timestamp: 0,
          withdrawalAddress: 'addr2',
          depositMin: '0',
          depositMax: '0',
          rate: '0',
          refundAddress: '',
          provider: 'CustomProvider',
        );
        expect(e.providerName, 'CustomProvider');
      });
    });

    group('canRefund', () {
      test('true for overdue status', () {
        final e = SwapOrder.fromJson({...fullJson(), 'status': 'overdue'});
        expect(e.canRefund, isTrue);
      });

      test('true for emergency status', () {
        final e = _exchangeWithStatus('emergency');
        expect(e.canRefund, isTrue);
      });

      test('true for expired status', () {
        final e = SwapOrder.fromJson({...fullJson(), 'status': 'expired'});
        expect(e.canRefund, isTrue);
      });

      test('false for success', () {
        final e = SwapOrder.fromJson({...fullJson(), 'status': 'settled'});
        expect(e.canRefund, isFalse);
      });

      test('false for wait', () {
        final e = SwapOrder.fromJson({...fullJson(), 'status': 'waiting'});
        expect(e.canRefund, isFalse);
      });
    });

    group('statusLabel', () {
      final cases = {
        'wait': 'Awaiting Deposit',
        'confirmation': 'Confirming',
        'exchanging': 'Exchanging',
        'sending': 'Sending',
        'success': 'Completed',
        'overdue': 'Overdue',
        'refunded': 'Refunded',
        'emergency': 'Emergency',
        'expired': 'Expired',
        'pending': 'Confirming',
        'processing': 'Exchanging',
        'review': 'Under Review',
        'settling': 'Sending',
        'settled': 'Completed',
      };

      cases.forEach((status, label) {
        test('$status -> "$label"', () {
          final e = _exchangeWithStatus(status);
          expect(e.statusLabel, label);
        });
      });

      test('unknown status returns itself', () {
        final e = _exchangeWithStatus('something_new');
        expect(e.statusLabel, 'something_new');
      });
    });

    group('isComplete', () {
      test('true for success', () {
        final e = _exchangeWithStatus('success');
        expect(e.isComplete, isTrue);
      });

      test('true for settled', () {
        final e = _exchangeWithStatus('settled');
        expect(e.isComplete, isTrue);
      });

      test('false for wait', () {
        final e = _exchangeWithStatus('wait');
        expect(e.isComplete, isFalse);
      });

      test('false for expired', () {
        final e = _exchangeWithStatus('expired');
        expect(e.isComplete, isFalse);
      });
    });

    group('retired providers', () {
      test('an old SideShift order is never pending and is untracked', () {
        final e = _exchangeWithStatus('exchanging', provider: 'SideShift');
        expect(e.isRetiredProvider, isTrue);
        expect(e.isPending, isFalse);
        expect(e.isUntrackedLegacyOrder, isTrue);
      });

      test('a row with no provider and a plain id is retired history', () {
        final e = _exchangeWithStatus('wait', provider: null);
        expect(e.providerName, 'SideShift');
        expect(e.isRetiredProvider, isTrue);
        expect(e.isPending, isFalse);
      });

      test('a finished retired order is plain history', () {
        final e = _exchangeWithStatus('success', provider: 'SideShift');
        expect(e.isUntrackedLegacyOrder, isFalse);
        expect(e.isComplete, isTrue);
      });

      test('an Orchestra order is not retired', () {
        final e = _exchangeWithStatus('exchanging', provider: 'Orchestra');
        expect(e.isRetiredProvider, isFalse);
        expect(e.isPending, isTrue);
      });
    });

    group('isPending', () {
      test('true for wait (not expired)', () {
        // Future expiresAt so it is not expired
        final futureExpiry = DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch;
        final e = _exchangeWithStatus('wait', expiresAt: futureExpiry);
        expect(e.isPending, isTrue);
      });

      test('true for confirmation', () {
        final e = _exchangeWithStatus('confirmation');
        expect(e.isPending, isTrue);
      });

      test('true for exchanging', () {
        final e = _exchangeWithStatus('exchanging');
        expect(e.isPending, isTrue);
      });

      test('true for sending', () {
        final e = _exchangeWithStatus('sending');
        expect(e.isPending, isTrue);
      });

      test('true for pending', () {
        final e = _exchangeWithStatus('pending');
        expect(e.isPending, isTrue);
      });

      test('true for processing', () {
        final e = _exchangeWithStatus('processing');
        expect(e.isPending, isTrue);
      });

      test('true for review', () {
        final e = _exchangeWithStatus('review');
        expect(e.isPending, isTrue);
      });

      test('true for settling', () {
        final e = _exchangeWithStatus('settling');
        expect(e.isPending, isTrue);
      });

      test('true for waiting', () {
        final e = _exchangeWithStatus('waiting');
        expect(e.isPending, isTrue);
      });

      test('true for multiple', () {
        final e = _exchangeWithStatus('multiple');
        expect(e.isPending, isTrue);
      });

      test('false for success', () {
        final e = _exchangeWithStatus('success');
        expect(e.isPending, isFalse);
      });

      test('false for expired', () {
        final e = _exchangeWithStatus('expired');
        expect(e.isPending, isFalse);
      });

      test('false for canceled', () {
        final e = _exchangeWithStatus('canceled');
        expect(e.isPending, isFalse);
      });
    });

    group('isExpired', () {
      test('true when status is expired', () {
        final e = _exchangeWithStatus('expired');
        expect(e.isExpired, isTrue);
      });

      test('true when status is canceled', () {
        final e = _exchangeWithStatus('canceled');
        expect(e.isExpired, isTrue);
      });

      test('true when wait and expiresAt is in the past', () {
        final pastExpiry = DateTime.now().subtract(const Duration(hours: 1)).millisecondsSinceEpoch;
        final e = _exchangeWithStatus('wait', expiresAt: pastExpiry);
        expect(e.isExpired, isTrue);
      });

      test('false when wait and expiresAt is in the future', () {
        final futureExpiry = DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch;
        final e = _exchangeWithStatus('wait', expiresAt: futureExpiry);
        expect(e.isExpired, isFalse);
      });

      test('true when wait with no expiresAt and created > 2 hours ago', () {
        final oldTimestamp = DateTime.now().subtract(const Duration(hours: 3)).millisecondsSinceEpoch;
        final e = _exchangeWithStatus('wait', timestamp: oldTimestamp);
        expect(e.isExpired, isTrue);
      });

      test('false when wait with no expiresAt and created < 2 hours ago', () {
        final recentTimestamp = DateTime.now().subtract(const Duration(minutes: 30)).millisecondsSinceEpoch;
        final e = _exchangeWithStatus('wait', timestamp: recentTimestamp);
        expect(e.isExpired, isFalse);
      });

      test('false when status is confirmation (not wait/expired/canceled)', () {
        final e = _exchangeWithStatus('confirmation');
        expect(e.isExpired, isFalse);
      });

      test('false when status is success', () {
        final e = _exchangeWithStatus('success');
        expect(e.isExpired, isFalse);
      });
    });

    group('copyWith', () {
      test('overrides specified fields only', () {
        final original = SwapOrder.fromJson(fullJson());
        final copy = original.copyWith(
          status: 'success',
          withdrawalAmount: '0.002',
        );
        expect(copy.status, 'success');
        expect(copy.withdrawalAmount, '0.002');
        // Unchanged fields
        expect(copy.id, original.id);
        expect(copy.coinFrom, original.coinFrom);
        expect(copy.depositAddress, original.depositAddress);
        expect(copy.refundAddress, original.refundAddress);
      });

      test('copies all fields when no args', () {
        final original = SwapOrder.fromJson(fullJson());
        final copy = original.copyWith();
        expect(copy.id, original.id);
        expect(copy.coinFrom, original.coinFrom);
        expect(copy.networkFrom, original.networkFrom);
        expect(copy.coinTo, original.coinTo);
        expect(copy.networkTo, original.networkTo);
        expect(copy.depositAddress, original.depositAddress);
        expect(copy.depositExtraId, original.depositExtraId);
        expect(copy.depositAmount, original.depositAmount);
        expect(copy.withdrawalAmount, original.withdrawalAmount);
        expect(copy.status, original.status);
        expect(copy.timestamp, original.timestamp);
        expect(copy.withdrawalAddress, original.withdrawalAddress);
        expect(copy.depositMin, original.depositMin);
        expect(copy.depositMax, original.depositMax);
        expect(copy.rate, original.rate);
        expect(copy.refundAddress, original.refundAddress);
        expect(copy.refundExtraId, original.refundExtraId);
        expect(copy.expiresAt, original.expiresAt);
      });

      test('can set provider and walletId', () {
        final original = SwapOrder.fromJson(fullJson());
        final copy = original.copyWith(
          provider: 'NewProvider',
          providerToken: 'token123',
          walletId: 'wallet456',
        );
        expect(copy.provider, 'NewProvider');
        expect(copy.providerToken, 'token123');
        expect(copy.walletId, 'wallet456');
      });
    });
  });

  // ---------------------------------------------------------------------------
  // Cash App purchase marker
  // ---------------------------------------------------------------------------
  group('SwapOrder.isCashAppPurchase', () {
    test('explicit cashapp marker wins regardless of shape', () {
      final e = _purchaseRow(
        coinFrom: 'USDC',
        networkFrom: 'POLYGON',
        purchaseSource: 'cashapp',
      );
      expect(e.isCashAppPurchase, isTrue);
    });

    test('a non-cashapp marker is false even on the purchase shape', () {
      final e = _purchaseRow(purchaseSource: 'other');
      expect(e.isCashAppPurchase, isFalse);
    });

    test('shape fallback: Orchestra, Lightning in, BTC to Spark', () {
      final e = _purchaseRow();
      expect(e.purchaseSource, isNull);
      expect(e.isCashAppPurchase, isTrue);
    });

    test('shape fallback: on-chain delivery counts too', () {
      final e = _purchaseRow(networkTo: 'BITCOIN');
      expect(e.isCashAppPurchase, isTrue);
    });

    test('shape fallback is case-insensitive on the networks', () {
      final e = _purchaseRow(networkFrom: 'lightning', networkTo: 'spark');
      expect(e.isCashAppPurchase, isTrue);
    });

    test('shape fallback: ord_ id with no stored provider is Orchestra', () {
      final e = _purchaseRow(id: 'ord_abc', provider: null);
      expect(e.isOrchestra, isTrue);
      expect(e.isCashAppPurchase, isTrue);
    });

    test('ordinary Orchestra swap row is false', () {
      final e = _purchaseRow(coinFrom: 'USDC', networkFrom: 'POLYGON');
      expect(e.isCashAppPurchase, isFalse);
    });

    test('Orchestra BTC to USDC leg is false', () {
      final e = _purchaseRow(coinTo: 'USDC', networkTo: 'ARBITRUM');
      expect(e.isCashAppPurchase, isFalse);
    });

    test('SideShift row with the Lightning shape is false', () {
      final e = _purchaseRow(id: 'a1b2c3', provider: 'SideShift');
      expect(e.isCashAppPurchase, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // copyWith / mergeExchange keep the purchase fields
  // ---------------------------------------------------------------------------
  group('SwapOrder purchase fields survive copies and merges', () {
    test('copyWith keeps purchaseSource and purchaseFiatUsd by default', () {
      final e = _purchaseRow(
        purchaseSource: 'cashapp',
        purchaseFiatUsd: '55.00',
      );
      final copied = e.copyWith(status: 'success', withdrawalAmount: '0.001');
      expect(copied.purchaseSource, 'cashapp');
      expect(copied.purchaseFiatUsd, '55.00');
      expect(copied.status, 'success');
      expect(copied.isCashAppPurchase, isTrue);
    });

    test('copyWith with a new id (q_ to ord_ swap) keeps the marker', () {
      final e = _purchaseRow(
        id: 'q_quote',
        purchaseSource: 'cashapp',
        purchaseFiatUsd: '55.00',
      );
      final swapped = e.copyWith(id: 'ord_real', provider: 'Orchestra');
      expect(swapped.id, 'ord_real');
      expect(swapped.purchaseSource, 'cashapp');
      expect(swapped.purchaseFiatUsd, '55.00');
      expect(swapped.walletId, e.walletId);
    });

    test('copyWith can override the purchase fields', () {
      final e = _purchaseRow(purchaseSource: 'cashapp', purchaseFiatUsd: '5.00');
      final copied = e.copyWith(purchaseFiatUsd: '10.00');
      expect(copied.purchaseSource, 'cashapp');
      expect(copied.purchaseFiatUsd, '10.00');
    });

    group('SwapOrdersNotifier', () {
      late Directory tmp;
      late Box<SwapOrder> box;

      setUp(() async {
        tmp = await Directory.systemTemp.createTemp('swap_order_model_test');
        Hive.init(tmp.path);
        if (!Hive.isAdapterRegistered(31)) {
          Hive.registerAdapter(SwapOrderAdapter());
        }
        box = await Hive.openBox<SwapOrder>('sideshiftExchanges');
        await box.clear();
      });

      tearDown(() async {
        await Hive.deleteFromDisk();
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      });

      test('retired BitcoinVN history survives reopening its existing Hive box',
          () async {
        final history = _purchaseRow(
          id: 'historical-bitcoinvn-order',
          status: 'settle_data_error',
          walletId: 'original-wallet',
        ).copyWith(provider: 'BitcoinVN', providerToken: 'original-order-ref');
        await box.put(history.id, history);
        await box.close();
        box = await Hive.openBox<SwapOrder>('sideshiftExchanges');

        final restored = box.get(history.id)!;
        expect(restored.providerName, 'BitcoinVN');
        expect(restored.providerToken, 'original-order-ref');
        expect(restored.walletId, 'original-wallet');
        expect(restored.status, 'settle_data_error');
        expect(restored.depositAddress, history.depositAddress);
        expect(restored.withdrawalAddress, history.withdrawalAddress);
        expect(restored.depositAmount, history.depositAmount);
        expect(restored.withdrawalAmount, history.withdrawalAmount);
      });

      test('mergeExchange keeps the purchase fields the server omits',
          () async {
        final notifier = SwapOrdersNotifier();
        final local = _purchaseRow(
          id: 'ord_merge',
          purchaseSource: 'cashapp',
          purchaseFiatUsd: '55.00',
          walletId: 'spending',
        );
        await notifier.addExchange(local);
        // Server data has no marker, no fiat, no walletId: only the
        // status and amounts should land on the stored row.
        final server = _purchaseRow(
          id: 'ord_merge',
          status: 'success',
          withdrawalAmount: '0.00090000',
        );
        await notifier.mergeExchange(server);
        final stored = box.get('ord_merge')!;
        expect(stored.status, 'success');
        expect(stored.withdrawalAmount, '0.00090000');
        expect(stored.purchaseSource, 'cashapp');
        expect(stored.purchaseFiatUsd, '55.00');
        expect(stored.walletId, 'spending');
        expect(stored.isCashAppPurchase, isTrue);
      });

    });
  });

  // ---------------------------------------------------------------------------
  // Edge cases and error scenarios
  // ---------------------------------------------------------------------------
  test('unfulfilled HyperCore withdrawal needs attention but keeps reconciling', () {
    final order = SwapOrder.fromJson({
      'id': 'ord_hypercore', 'status': 'unfulfilled',
      'depositCoin': 'USDC', 'depositNetwork': 'hypercore',
      'settleCoin': 'BTC', 'settleNetwork': 'spark',
    });
    expect(order.isOrchestra, isTrue);
    expect(order.isPending, isFalse);
    expect(order.isComplete, isFalse);
    expect(order.shouldPollOrchestra, isTrue);
    expect(order.copyWith(status: 'refunded').shouldPollOrchestra, isFalse);
  });

  group('Edge cases', () {
    test('SwapOrder.fromJson with invalid createdAt falls back to now', () {
      final e = SwapOrder.fromJson({
        'id': 'test',
        'createdAt': 'not-a-date',
      });
      // Should not throw; timestamp should be close to now
      final now = DateTime.now().millisecondsSinceEpoch;
      expect((e.timestamp - now).abs(), lessThan(5000));
    });

    test('SwapOrder.fromJson with null status defaults to wait', () {
      final e = SwapOrder.fromJson({
        'id': 'test',
        'status': null,
      });
      expect(e.status, 'wait');
    });

    test('isPending returns false when wait status is expired by time', () {
      final oldTimestamp = DateTime.now().subtract(const Duration(hours: 3)).millisecondsSinceEpoch;
      final e = _exchangeWithStatus('wait', timestamp: oldTimestamp);
      expect(e.isExpired, isTrue);
      expect(e.isPending, isFalse);
    });
  });
}

/// Helper to build an Orchestra Cash App purchase row: Lightning
/// deposit leg settling BTC to Spark. Every field can be overridden so
/// the marker and shape tests can move one variable at a time.
SwapOrder _purchaseRow({
  String id = 'ord_purchase',
  String coinFrom = 'BTC',
  String networkFrom = 'LIGHTNING',
  String coinTo = 'BTC',
  String networkTo = 'SPARK',
  String status = 'exchanging',
  String withdrawalAmount = '0.00100000',
  String? provider = 'Orchestra',
  String? walletId,
  String? purchaseSource,
  String? purchaseFiatUsd,
}) {
  return SwapOrder(
    id: id,
    coinFrom: coinFrom,
    networkFrom: networkFrom,
    coinTo: coinTo,
    networkTo: networkTo,
    depositAddress: 'lnbc1...',
    depositAmount: '0.00100000',
    withdrawalAmount: withdrawalAmount,
    status: status,
    timestamp: DateTime.now().millisecondsSinceEpoch,
    withdrawalAddress: 'sp1test',
    depositMin: '0',
    depositMax: '0',
    rate: '0',
    refundAddress: '',
    provider: provider,
    walletId: walletId,
    purchaseSource: purchaseSource,
    purchaseFiatUsd: purchaseFiatUsd,
  );
}

/// Helper to build a [SwapOrder] with a given internal status.
SwapOrder _exchangeWithStatus(
  String status, {
  int? timestamp,
  int? expiresAt,
  // A live provider other than Orchestra, so the generic status rules
  // are what the tests see.
  String? provider = 'Native',
}) {
  return SwapOrder(
    id: 'test-id',
    coinFrom: 'USDT',
    networkFrom: 'tron',
    coinTo: 'BTC',
    networkTo: 'bitcoin',
    depositAddress: 'TXyz...',
    depositAmount: '100',
    withdrawalAmount: '0.0015',
    status: status,
    timestamp: timestamp ?? DateTime.now().millisecondsSinceEpoch,
    withdrawalAddress: 'bc1q...',
    depositMin: '10',
    depositMax: '50000',
    rate: '0.000015',
    refundAddress: '',
    expiresAt: expiresAt,
    provider: provider,
  );
}
