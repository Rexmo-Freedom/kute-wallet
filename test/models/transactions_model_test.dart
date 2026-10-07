import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/outlogic_model.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/services/mempool_address_service.dart' as mempool;
import 'package:kute/models/datetime_range_model.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

SwapOrder _makeSwapOrder({
  String id = 'ss1',
  String coinFrom = 'USDT',
  String coinTo = 'BTC',
  String networkFrom = 'tron',
  String networkTo = 'bitcoin',
  String status = 'success',
  int timestamp = 1700000000000,
}) {
  return SwapOrder(
    id: id,
    coinFrom: coinFrom,
    networkFrom: networkFrom,
    coinTo: coinTo,
    networkTo: networkTo,
    depositAddress: 'deposit_addr',
    depositAmount: '100',
    withdrawalAmount: '0.003',
    status: status,
    timestamp: timestamp,
    withdrawalAddress: 'withdraw_addr',
    depositMin: '10',
    depositMax: '10000',
    rate: '0.00003',
    refundAddress: 'refund_addr',
  );
}

SwapOrderTransaction _makeSwapOrderTx({
  String id = 'ss1',
  String status = 'success',
  String coinTo = 'BTC',
  DateTime? timestamp,
  bool isConfirmed = true,
}) {
  return SwapOrderTransaction(
    id: id,
    timestamp: timestamp ?? DateTime(2025, 3, 1),
    isConfirmed: isConfirmed,
    details: _makeSwapOrder(status: status, coinTo: coinTo),
  );
}

OutlogicOrder _makeOutlogicOrder({
  String id = 'ol1',
  String status = 'COMPLETED',
  String fromAsset = 'EUR',
  String toAsset = 'BTC',
  double fromAmount = 100.0,
  OutlogicTrade? trade,
}) {
  return OutlogicOrder(
    id: id,
    status: status,
    email: 'test@test.com',
    depositCryptoAddress: 'addr',
    fromAmount: fromAmount,
    fromAsset: fromAsset,
    toAsset: toAsset,
    destinationType: 'crypto',
    destinationCryptoAddress: 'dest_addr',
    createdAt: '2025-01-15T00:00:00Z',
    trade: trade,
  );
}

OutlogicTransaction _makeOutlogicTx({
  String id = 'ol1',
  String status = 'COMPLETED',
  String fromAsset = 'EUR',
  String toAsset = 'BTC',
  double fromAmount = 100.0,
  OutlogicTrade? trade,
  DateTime? timestamp,
  bool isConfirmed = true,
}) {
  return OutlogicTransaction(
    id: id,
    timestamp: timestamp ?? DateTime(2025, 2, 10),
    isConfirmed: isConfirmed,
    details: _makeOutlogicOrder(
      id: id,
      status: status,
      fromAsset: fromAsset,
      toAsset: toAsset,
      fromAmount: fromAmount,
      trade: trade,
    ),
  );
}

MempoolAddressTransaction _makeMempoolTx({
  String id = 'mempool1',
  int balanceChange = 50000,
  bool confirmed = true,
  DateTime? timestamp,
}) {
  return MempoolAddressTransaction(
    id: id,
    timestamp: timestamp ?? DateTime(2025, 4, 1),
    isConfirmed: confirmed,
    details: mempool.MempoolTransaction(
      txid: id,
      confirmed: confirmed,
      fee: 250,
      balanceChange: balanceChange,
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ===== Enums =====

  group('TransactionType enum', () {
    test('has received and sent', () {
      expect(TransactionType.values, contains(TransactionType.received));
      expect(TransactionType.values, contains(TransactionType.sent));
    });

    test('has exactly 2 values', () {
      expect(TransactionType.values.length, 2);
    });
  });

  group('SparkTransactionType enum', () {
    test('has all types', () {
      expect(SparkTransactionType.values.length, 3);
      expect(SparkTransactionType.values, contains(SparkTransactionType.bitcoin));
      expect(SparkTransactionType.values, contains(SparkTransactionType.lightning));
      expect(SparkTransactionType.values, contains(SparkTransactionType.spark));
    });
  });

  // ===== SwapOrderTransaction =====

  group('SwapOrderTransaction', () {
    test('type is always received', () {
      final tx = _makeSwapOrderTx(status: 'success');
      expect(tx.type, TransactionType.received);
    });

    test('amount is always 0', () {
      final tx = _makeSwapOrderTx();
      expect(tx.amount, 0);
    });

    test('asset delegates to details.coinTo', () {
      final tx = _makeSwapOrderTx(coinTo: 'ETH');
      expect(tx.asset, 'ETH');
    });

    test('isComplete returns true for success status', () {
      final tx = _makeSwapOrderTx(status: 'success');
      expect(tx.isComplete, isTrue);
    });

    test('isComplete returns false for non-success status', () {
      for (final status in ['wait', 'confirmation', 'exchanging', 'sending', 'expired']) {
        final tx = _makeSwapOrderTx(status: status);
        expect(tx.isComplete, isFalse, reason: 'status=$status should not be complete');
      }
    });

    test('stores id and timestamp correctly', () {
      final ts = DateTime(2025, 6, 15, 12, 30);
      final tx = _makeSwapOrderTx(id: 'shift-abc', timestamp: ts);
      expect(tx.id, 'shift-abc');
      expect(tx.timestamp, ts);
    });

    test('isConfirmed can be set independently', () {
      final confirmed = _makeSwapOrderTx(isConfirmed: true);
      final unconfirmed = _makeSwapOrderTx(isConfirmed: false);
      expect(confirmed.isConfirmed, isTrue);
      expect(unconfirmed.isConfirmed, isFalse);
    });
  });

  // ===== OutlogicTransaction =====

  group('OutlogicTransaction', () {
    group('isBuy', () {
      test('returns true when fromAsset is fiat (EUR)', () {
        final tx = _makeOutlogicTx(fromAsset: 'EUR', toAsset: 'BTC');
        expect(tx.isBuy, isTrue);
      });

      test('returns true when fromAsset is fiat (USD)', () {
        final tx = _makeOutlogicTx(fromAsset: 'USD', toAsset: 'BTC');
        expect(tx.isBuy, isTrue);
      });

      test('returns false when fromAsset is BTC', () {
        final tx = _makeOutlogicTx(fromAsset: 'BTC', toAsset: 'EUR');
        expect(tx.isBuy, isFalse);
      });

      test('returns false when fromAsset is L-BTC', () {
        final tx = _makeOutlogicTx(fromAsset: 'L-BTC', toAsset: 'CHF');
        expect(tx.isBuy, isFalse);
      });
    });

    group('type', () {
      test('is received for buy (fiat to BTC)', () {
        final tx = _makeOutlogicTx(fromAsset: 'EUR', toAsset: 'BTC');
        expect(tx.type, TransactionType.received);
      });

      test('is sent for sell (BTC to fiat)', () {
        final tx = _makeOutlogicTx(fromAsset: 'BTC', toAsset: 'EUR');
        expect(tx.type, TransactionType.sent);
      });
    });

    group('asset', () {
      test('returns toAsset for buy', () {
        final tx = _makeOutlogicTx(fromAsset: 'EUR', toAsset: 'BTC');
        expect(tx.asset, 'BTC');
      });

      test('returns fromAsset for sell', () {
        final tx = _makeOutlogicTx(fromAsset: 'BTC', toAsset: 'EUR');
        expect(tx.asset, 'BTC');
      });
    });

    group('fiatAsset', () {
      test('returns fromAsset for buy', () {
        final tx = _makeOutlogicTx(fromAsset: 'EUR', toAsset: 'BTC');
        expect(tx.fiatAsset, 'EUR');
      });

      test('returns toAsset for sell', () {
        final tx = _makeOutlogicTx(fromAsset: 'BTC', toAsset: 'CHF');
        expect(tx.fiatAsset, 'CHF');
      });
    });

    group('fiatAmount', () {
      test('returns fromAmount formatted for buy', () {
        final tx = _makeOutlogicTx(
          fromAsset: 'EUR',
          toAsset: 'BTC',
          fromAmount: 250.5,
        );
        expect(tx.fiatAmount, '250.50');
      });

      test('returns trade.toAmount formatted for sell with trade', () {
        final trade = OutlogicTrade(
          fromAmount: 0.005,
          fromAsset: 'BTC',
          toAmount: 125.75,
          toAsset: 'EUR',
          feeAmount: 1.0,
          price: 25000.0,
          timestamp: '2025-01-15T00:00:00Z',
        );
        final tx = _makeOutlogicTx(
          fromAsset: 'BTC',
          toAsset: 'EUR',
          trade: trade,
        );
        expect(tx.fiatAmount, '125.75');
      });

      test('returns "..." for sell without trade', () {
        final tx = _makeOutlogicTx(fromAsset: 'BTC', toAsset: 'EUR');
        expect(tx.fiatAmount, '...');
      });
    });

    group('status handling', () {
      test('isComplete returns true for COMPLETED', () {
        final tx = _makeOutlogicTx(status: 'COMPLETED');
        expect(tx.isComplete, isTrue);
      });

      test('isComplete returns false for non-COMPLETED', () {
        for (final status in ['WAITING_FOR_DEPOSIT', 'PROCESSING', 'CANCELED']) {
          final tx = _makeOutlogicTx(status: status);
          expect(tx.isComplete, isFalse, reason: 'status=$status');
        }
      });

      test('isPending returns false for terminal statuses', () {
        for (final status in ['COMPLETED', 'CANCELED', 'EXPIRED', 'REJECTED', 'REFUNDED']) {
          final tx = _makeOutlogicTx(status: status);
          expect(tx.isPending, isFalse, reason: 'status=$status should not be pending');
        }
      });

      test('isPending returns true for non-terminal statuses', () {
        for (final status in ['WAITING_FOR_DEPOSIT', 'PROCESSING']) {
          final tx = _makeOutlogicTx(status: status);
          expect(tx.isPending, isTrue, reason: 'status=$status should be pending');
        }
      });
    });

    test('amount is always 0', () {
      final tx = _makeOutlogicTx();
      expect(tx.amount, 0);
    });
  });

  // ===== MempoolAddressTransaction =====

  group('MempoolAddressTransaction', () {
    test('type is received for positive balanceChange', () {
      final tx = _makeMempoolTx(balanceChange: 50000);
      expect(tx.type, TransactionType.received);
    });

    test('type is received for zero balanceChange', () {
      final tx = _makeMempoolTx(balanceChange: 0);
      expect(tx.type, TransactionType.received);
    });

    test('type is sent for negative balanceChange', () {
      final tx = _makeMempoolTx(balanceChange: -30000);
      expect(tx.type, TransactionType.sent);
    });

    test('amount is absolute value of balanceChange', () {
      final txPositive = _makeMempoolTx(balanceChange: 50000);
      final txNegative = _makeMempoolTx(balanceChange: -30000);
      expect(txPositive.amount, 50000);
      expect(txNegative.amount, 30000);
    });

    test('asset is always btc', () {
      final tx = _makeMempoolTx();
      expect(tx.asset, 'btc');
    });

    test('isConfirmed reflects construction parameter', () {
      final confirmed = _makeMempoolTx(confirmed: true);
      final unconfirmed = _makeMempoolTx(confirmed: false);
      expect(confirmed.isConfirmed, isTrue);
      expect(unconfirmed.isConfirmed, isFalse);
    });

    test('stores id and timestamp correctly', () {
      final ts = DateTime(2025, 8, 20, 14, 0);
      final tx = _makeMempoolTx(id: 'abc123', timestamp: ts);
      expect(tx.id, 'abc123');
      expect(tx.timestamp, ts);
    });
  });

  // ===== Transaction.empty =====

  group('Transaction.empty', () {
    test('all lists are empty', () {
      final tx = Transaction.empty();
      expect(tx.bitcoinTransactions, isEmpty);
      expect(tx.sparkTransactions, isEmpty);
      expect(tx.sparkUnclaimedDeposits, isEmpty);
      expect(tx.sparkPendingDeposits, isEmpty);
      expect(tx.mempoolTransactions, isEmpty);
      expect(tx.usdbTokenTransactions, isEmpty);
      expect(tx.swapOrderTransactions, isEmpty);
      expect(tx.polymarketTransactions, isEmpty);
      expect(tx.outlogicTransactions, isEmpty);
    });

    test('allTransactions is empty', () {
      expect(Transaction.empty().allTransactions, isEmpty);
    });

    test('allTransactionsSorted is empty', () {
      expect(Transaction.empty().allTransactionsSorted, isEmpty);
    });

    test('allTransactionsWithSwaps is empty', () {
      expect(Transaction.empty().allTransactionsWithSwaps, isEmpty);
    });

    test('earliestTimestamp is null', () {
      expect(Transaction.empty().earliestTimestamp, isNull);
    });

    test('settledTransactions is empty', () {
      expect(Transaction.empty().settledTransactions, isEmpty);
    });

    test('unsettledSwapsAndPurchases is empty', () {
      expect(Transaction.empty().unsettledSwapsAndPurchases, isEmpty);
    });

    test('homeTransactionsSorted is empty', () {
      expect(Transaction.empty().homeTransactionsSorted, isEmpty);
    });
  });

  // ===== Transaction.copyWith =====

  group('Transaction.copyWith', () {
    test('preserves original when no args', () {
      final original = Transaction.empty();
      final copy = original.copyWith();
      expect(copy.bitcoinTransactions, isEmpty);
      expect(copy.sparkTransactions, isEmpty);
      expect(copy.sparkUnclaimedDeposits, isEmpty);
      expect(copy.sparkPendingDeposits, isEmpty);
      expect(copy.mempoolTransactions, isEmpty);
      expect(copy.usdbTokenTransactions, isEmpty);
      expect(copy.swapOrderTransactions, isEmpty);
      expect(copy.polymarketTransactions, isEmpty);
      expect(copy.outlogicTransactions, isEmpty);
    });

    test('overrides sideshift transactions', () {
      final original = Transaction.empty();
      final ssTx = _makeSwapOrderTx(id: 'ss-copy');
      final copy = original.copyWith(swapOrderTransactions: [ssTx]);
      expect(copy.swapOrderTransactions.length, 1);
      expect(copy.swapOrderTransactions.first.id, 'ss-copy');
    });

    test('overrides outlogic transactions', () {
      final original = Transaction.empty();
      final olTx = _makeOutlogicTx(id: 'ol-copy');
      final copy = original.copyWith(outlogicTransactions: [olTx]);
      expect(copy.outlogicTransactions.length, 1);
      expect(copy.outlogicTransactions.first.id, 'ol-copy');
    });

    test('overrides mempool transactions', () {
      final original = Transaction.empty();
      final mpTx = _makeMempoolTx(id: 'mp-copy');
      final copy = original.copyWith(mempoolTransactions: [mpTx]);
      expect(copy.mempoolTransactions.length, 1);
      expect(copy.mempoolTransactions.first.id, 'mp-copy');
    });

    test('does not mutate original', () {
      final original = Transaction.empty();
      original.copyWith(mempoolTransactions: [_makeMempoolTx()]);
      expect(original.mempoolTransactions, isEmpty);
    });
  });

  // ===== Transaction aggregate getters =====

  group('Transaction aggregate getters', () {
    late Transaction txCollection;

    setUp(() {
      txCollection = Transaction(
        bitcoinTransactions: [],
        sparkTransactions: [],
        sparkUnclaimedDeposits: [],
        mempoolTransactions: [
          _makeMempoolTx(id: 'mp1', timestamp: DateTime(2025, 1, 1)),
          _makeMempoolTx(id: 'mp2', timestamp: DateTime(2025, 6, 1)),
        ],
        swapOrderTransactions: [
          _makeSwapOrderTx(id: 'ss1', timestamp: DateTime(2025, 3, 1)),
        ],
        outlogicTransactions: [
          _makeOutlogicTx(id: 'ol1', status: 'PROCESSING', timestamp: DateTime(2025, 4, 1)),
          _makeOutlogicTx(id: 'ol2', status: 'COMPLETED', timestamp: DateTime(2025, 5, 1)),
        ],
      );
    });

    test('allTransactions includes outlogic transactions with a status', () {
      final all = txCollection.allTransactions;
      final ids = all.map((t) => t.id).toSet();
      // Pending AND completed orders both surface (UX call: users want
      // the full paper trail of a fiat order, not just in-flight ones).
      expect(ids, contains('ol1'));
      expect(ids, contains('ol2'));
    });

    test('allTransactions includes mempool and sideshift', () {
      final ids = txCollection.allTransactions.map((t) => t.id).toSet();
      expect(ids, containsAll(['mp1', 'mp2', 'ss1']));
    });

    test('allTransactionsWithSwaps includes all outlogic transactions', () {
      final ids = txCollection.allTransactionsWithSwaps.map((t) => t.id).toSet();
      expect(ids, containsAll(['ol1', 'ol2']));
    });

    test('allTransactionsSorted returns newest first', () {
      final sorted = txCollection.allTransactionsSorted;
      for (int i = 0; i < sorted.length - 1; i++) {
        expect(
          sorted[i].timestamp.isAfter(sorted[i + 1].timestamp) ||
              sorted[i].timestamp.isAtSameMomentAs(sorted[i + 1].timestamp),
          isTrue,
          reason: 'Index $i should be >= index ${i + 1}',
        );
      }
    });

    test('earliestTimestamp returns the oldest date', () {
      final earliest = txCollection.earliestTimestamp;
      expect(earliest, isNotNull);
      expect(earliest, DateTime(2025, 1, 1));
    });
  });

  // ===== homeTransactionsSorted filtering =====

  group('homeTransactionsSorted', () {
    test('filters out SideShift transactions with wait/expired/overdue status', () {
      final txCollection = Transaction(
        bitcoinTransactions: [],
        sparkTransactions: [],
        sparkUnclaimedDeposits: [],
        mempoolTransactions: [_makeMempoolTx(id: 'mp1')],
        swapOrderTransactions: [
          _makeSwapOrderTx(id: 'ss-wait', status: 'wait'),
          _makeSwapOrderTx(id: 'ss-expired', status: 'expired'),
          _makeSwapOrderTx(id: 'ss-overdue', status: 'overdue'),
          _makeSwapOrderTx(id: 'ss-success', status: 'success'),
          _makeSwapOrderTx(id: 'ss-exchanging', status: 'exchanging'),
        ],
      );

      final homeIds = txCollection.homeTransactionsSorted.map((t) => t.id).toSet();
      expect(homeIds, contains('mp1'));
      expect(homeIds, contains('ss-success'));
      expect(homeIds, contains('ss-exchanging'));
      expect(homeIds, isNot(contains('ss-wait')));
      expect(homeIds, isNot(contains('ss-expired')));
      expect(homeIds, isNot(contains('ss-overdue')));
    });
  });

  // ===== settledTransactions / unsettledSwapsAndPurchases =====

  group('settled vs unsettled transactions', () {
    test('unsettledSwapsAndPurchases is empty when no unclaimed deposits', () {
      final txCollection = Transaction(
        bitcoinTransactions: [],
        sparkTransactions: [],
        sparkUnclaimedDeposits: [],
        mempoolTransactions: [_makeMempoolTx(id: 'mp1')],
      );
      expect(txCollection.unsettledSwapsAndPurchases, isEmpty);
    });

    test('settledTransactions excludes unsettled ids', () {
      // Cannot construct SparkUnclaimedDeposit without breez package,
      // but we can verify the logic with an empty unsettled list
      final txCollection = Transaction(
        bitcoinTransactions: [],
        sparkTransactions: [],
        sparkUnclaimedDeposits: [],
        mempoolTransactions: [
          _makeMempoolTx(id: 'mp1'),
          _makeMempoolTx(id: 'mp2'),
        ],
      );
      // With no unsettled, all sorted transactions should appear in settled
      expect(txCollection.settledTransactions.length,
          txCollection.allTransactionsSorted.length);
    });
  });

  // ===== filterBitcoinTransactions =====

  group('filterBitcoinTransactions', () {
    test('returns empty when no bitcoin transactions', () {
      final txCollection = Transaction.empty();
      final range = DateTimeSelect(
        start: DateTime(2025, 1, 1),
        end: DateTime(2025, 12, 31),
      );
      expect(txCollection.filterBitcoinTransactions(range), isEmpty);
    });
  });

  // ===== Date handling =====

  group('date handling', () {
    test('transactions preserve exact timestamp', () {
      final precise = DateTime(2025, 7, 4, 13, 45, 30, 123);
      final tx = _makeMempoolTx(timestamp: precise);
      expect(tx.timestamp, precise);
      expect(tx.timestamp.millisecondsSinceEpoch,
          precise.millisecondsSinceEpoch);
    });

    test('earliest timestamp with single transaction', () {
      final txCollection = Transaction(
        bitcoinTransactions: [],
        sparkTransactions: [],
        sparkUnclaimedDeposits: [],
        mempoolTransactions: [
          _makeMempoolTx(id: 'only', timestamp: DateTime(2025, 9, 9)),
        ],
      );
      expect(txCollection.earliestTimestamp, DateTime(2025, 9, 9));
    });

    test('sorting handles same-timestamp transactions', () {
      final sameTime = DateTime(2025, 5, 5);
      final txCollection = Transaction(
        bitcoinTransactions: [],
        sparkTransactions: [],
        sparkUnclaimedDeposits: [],
        mempoolTransactions: [
          _makeMempoolTx(id: 'a', timestamp: sameTime),
          _makeMempoolTx(id: 'b', timestamp: sameTime),
        ],
      );
      final sorted = txCollection.allTransactionsSorted;
      expect(sorted.length, 2);
      // Both should be present regardless of order
      expect(sorted.map((t) => t.id).toSet(), {'a', 'b'});
    });
  });

  // ===== SwapOrder JSON deserialization =====

  group('SwapOrder JSON deserialization', () {
    test('parses the cached order JSON and keeps the saved status', () {
      final json = {
        'id': 'ord_123',
        'depositCoin': 'usdt',
        'settleCoin': 'btc',
        'depositNetwork': 'tron',
        'settleNetwork': 'bitcoin',
        'depositAddress': 'TAddr123',
        'depositMemo': null,
        'depositAmount': '100.5',
        'settleAmount': '0.004',
        'status': 'success',
        'createdAt': '2025-03-01T12:00:00Z',
        'settleAddress': 'bc1qaddr',
        'depositMin': '10',
        'depositMax': '50000',
        'rate': '0.00004',
        'refundAddress': 'TRefund',
      };
      final exchange = SwapOrder.fromJson(json);
      expect(exchange.id, 'ord_123');
      expect(exchange.coinFrom, 'USDT');
      expect(exchange.coinTo, 'BTC');
      expect(exchange.status, 'success');
      expect(exchange.depositAmount, '100.5');
      expect(exchange.withdrawalAmount, '0.004');
      expect(exchange.withdrawalAddress, 'bc1qaddr');
    });

    test('handles missing fields with defaults', () {
      final exchange = SwapOrder.fromJson({});
      expect(exchange.id, '');
      expect(exchange.coinFrom, '');
      expect(exchange.coinTo, '');
      expect(exchange.depositAmount, '0');
      expect(exchange.withdrawalAmount, '0');
    });
  });

  // ===== OutlogicOrder JSON deserialization =====

  group('OutlogicOrder JSON deserialization', () {
    test('parses from API JSON', () {
      final json = {
        'id': 'order-456',
        'status': 'COMPLETED',
        'email': 'user@example.com',
        'deposit_crypto_address': 'bc1q...',
        'from_amount': '100.50',
        'from_asset': 'EUR',
        'to_asset': 'BTC',
        'destination_type': 'crypto',
        'destination_crypto_address': 'bc1dest...',
        'created_at': '2025-02-15T10:30:00Z',
        'trade': {
          'from_amount': '100.50',
          'from_asset': 'EUR',
          'to_amount': '0.004',
          'to_asset': 'BTC',
          'fee_amount': '1.50',
          'price': '25000',
          'timestamp': '2025-02-15T10:31:00Z',
        },
      };
      final order = OutlogicOrder.fromJson(json);
      expect(order.id, 'order-456');
      expect(order.status, 'COMPLETED');
      expect(order.fromAmount, closeTo(100.50, 0.01));
      expect(order.fromAsset, 'EUR');
      expect(order.toAsset, 'BTC');
      expect(order.trade, isNotNull);
      expect(order.trade!.toAmount, closeTo(0.004, 0.0001));
      expect(order.trade!.feeAmount, closeTo(1.50, 0.01));
    });

    test('handles missing trade gracefully', () {
      final json = {
        'id': 'order-789',
        'status': 'WAITING_FOR_DEPOSIT',
        'from_amount': '50',
        'from_asset': 'CHF',
        'to_asset': 'BTC',
      };
      final order = OutlogicOrder.fromJson(json);
      expect(order.trade, isNull);
    });

    test('isTerminal identifies terminal statuses', () {
      for (final status in ['COMPLETED', 'CANCELED', 'EXPIRED', 'REJECTED', 'REFUNDED']) {
        final order = _makeOutlogicOrder(status: status);
        expect(order.isTerminal, isTrue, reason: '$status should be terminal');
      }
    });

    test('isTerminal returns false for non-terminal statuses', () {
      for (final status in ['WAITING_FOR_DEPOSIT', 'PROCESSING', 'PENDING']) {
        final order = _makeOutlogicOrder(status: status);
        expect(order.isTerminal, isFalse, reason: '$status should not be terminal');
      }
    });

    test('isCancellable only for WAITING_FOR_DEPOSIT', () {
      expect(_makeOutlogicOrder(status: 'WAITING_FOR_DEPOSIT').isCancellable, isTrue);
      expect(_makeOutlogicOrder(status: 'PROCESSING').isCancellable, isFalse);
      expect(_makeOutlogicOrder(status: 'COMPLETED').isCancellable, isFalse);
    });
  });

  // ===== MempoolTransaction construction =====

  group('MempoolTransaction', () {
    test('stores all fields correctly', () {
      final tx = mempool.MempoolTransaction(
        txid: 'abc123def',
        blockHeight: 800000,
        blockTime: 1700000000,
        confirmed: true,
        fee: 500,
        balanceChange: -25000,
      );
      expect(tx.txid, 'abc123def');
      expect(tx.blockHeight, 800000);
      expect(tx.blockTime, 1700000000);
      expect(tx.confirmed, isTrue);
      expect(tx.fee, 500);
      expect(tx.balanceChange, -25000);
    });

    test('handles unconfirmed tx with null block fields', () {
      final tx = mempool.MempoolTransaction(
        txid: 'unconf123',
        confirmed: false,
        fee: 300,
        balanceChange: 10000,
      );
      expect(tx.blockHeight, isNull);
      expect(tx.blockTime, isNull);
      expect(tx.confirmed, isFalse);
    });
  });

  // ===== Mixed transaction collection scenarios =====

  group('mixed transaction scenarios', () {
    test('allTransactions combines multiple types', () {
      final txCollection = Transaction(
        bitcoinTransactions: [],
        sparkTransactions: [],
        sparkUnclaimedDeposits: [],
        mempoolTransactions: [
          _makeMempoolTx(id: 'mp1'),
        ],
        swapOrderTransactions: [
          _makeSwapOrderTx(id: 'ss1'),
        ],
        outlogicTransactions: [
          _makeOutlogicTx(id: 'ol1', status: 'PROCESSING'), // pending
        ],
      );
      final ids = txCollection.allTransactions.map((t) => t.id).toSet();
      expect(ids, containsAll(['mp1', 'ss1', 'ol1']));
    });

    test('allTransactionsWithSwaps includes everything', () {
      final txCollection = Transaction(
        bitcoinTransactions: [],
        sparkTransactions: [],
        sparkUnclaimedDeposits: [],
        mempoolTransactions: [_makeMempoolTx(id: 'mp1')],
        swapOrderTransactions: [_makeSwapOrderTx(id: 'ss1')],
        outlogicTransactions: [
          _makeOutlogicTx(id: 'ol1', status: 'COMPLETED'),
          _makeOutlogicTx(id: 'ol2', status: 'PROCESSING'),
        ],
      );
      final ids = txCollection.allTransactionsWithSwaps.map((t) => t.id).toSet();
      expect(ids, containsAll(['mp1', 'ss1', 'ol1', 'ol2']));
    });

    test('empty default lists work correctly in constructor', () {
      // Only required params, everything else defaults
      final txCollection = Transaction(
        bitcoinTransactions: [],
        sparkTransactions: [],
        sparkUnclaimedDeposits: [],
      );
      expect(txCollection.sparkPendingDeposits, isEmpty);
      expect(txCollection.mempoolTransactions, isEmpty);
      expect(txCollection.usdbTokenTransactions, isEmpty);
      expect(txCollection.swapOrderTransactions, isEmpty);
      expect(txCollection.polymarketTransactions, isEmpty);
      expect(txCollection.outlogicTransactions, isEmpty);
    });
  });

  // ===== OutlogicTrade JSON deserialization =====

  group('OutlogicTrade JSON deserialization', () {
    test('parses all numeric fields', () {
      final json = {
        'from_amount': '0.005',
        'from_asset': 'BTC',
        'to_amount': '125.75',
        'to_asset': 'EUR',
        'fee_amount': '1.50',
        'price': '25150.0',
        'timestamp': '2025-03-01T00:00:00Z',
      };
      final trade = OutlogicTrade.fromJson(json);
      expect(trade.fromAmount, closeTo(0.005, 0.0001));
      expect(trade.toAmount, closeTo(125.75, 0.01));
      expect(trade.feeAmount, closeTo(1.50, 0.01));
      expect(trade.price, closeTo(25150.0, 0.1));
      expect(trade.fromAsset, 'BTC');
      expect(trade.toAsset, 'EUR');
    });

    test('handles missing/invalid numeric fields', () {
      final trade = OutlogicTrade.fromJson({});
      expect(trade.fromAmount, 0.0);
      expect(trade.toAmount, 0.0);
      expect(trade.feeAmount, 0.0);
      expect(trade.price, 0.0);
    });
  });

  // ===== SwapOrder computed properties =====

  group('SwapOrder computed properties', () {
    test('amount and amountTo parse string values', () {
      final exchange = _makeSwapOrder();
      expect(exchange.amount, closeTo(100.0, 0.01));
      expect(exchange.amountTo, closeTo(0.003, 0.0001));
    });

    test('createdAt converts timestamp to DateTime', () {
      final exchange = _makeSwapOrder(timestamp: 1700000000000);
      expect(exchange.createdAt,
          DateTime.fromMillisecondsSinceEpoch(1700000000000));
    });

    test('statusLabel returns human-readable labels', () {
      final labels = {
        'wait': 'Awaiting Deposit',
        'confirmation': 'Confirming',
        'exchanging': 'Exchanging',
        'sending': 'Sending',
        'success': 'Completed',
        'overdue': 'Overdue',
        'refunded': 'Refunded',
        'emergency': 'Emergency',
        'expired': 'Expired',
      };
      for (final entry in labels.entries) {
        final exchange = _makeSwapOrder(status: entry.key);
        expect(exchange.statusLabel, entry.value,
            reason: 'status ${entry.key} -> ${entry.value}');
      }
    });

    test('isComplete for success and settled', () {
      expect(_makeSwapOrder(status: 'success').isComplete, isTrue);
      expect(_makeSwapOrder(status: 'settled').isComplete, isTrue);
      expect(_makeSwapOrder(status: 'exchanging').isComplete, isFalse);
    });

    test('canRefund for eligible statuses', () {
      expect(_makeSwapOrder(status: 'overdue').canRefund, isTrue);
      expect(_makeSwapOrder(status: 'emergency').canRefund, isTrue);
      expect(_makeSwapOrder(status: 'expired').canRefund, isTrue);
      expect(_makeSwapOrder(status: 'success').canRefund, isFalse);
      expect(_makeSwapOrder(status: 'wait').canRefund, isFalse);
    });

    test('backwards-compatible getters', () {
      final exchange = _makeSwapOrder(
        coinFrom: 'USDT',
        coinTo: 'BTC',
        networkFrom: 'tron',
        networkTo: 'bitcoin',
      );
      expect(exchange.depositCoin, 'USDT');
      expect(exchange.settleCoin, 'BTC');
      expect(exchange.depositNetwork, 'tron');
      expect(exchange.settleNetwork, 'bitcoin');
      expect(exchange.settleAddress, exchange.withdrawalAddress);
      expect(exchange.settleAmount, exchange.withdrawalAmount);
    });

    test('providerName defaults to SideShift', () {
      final exchange = _makeSwapOrder();
      expect(exchange.providerName, 'SideShift');
    });
  });
}
