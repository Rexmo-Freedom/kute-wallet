import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/orchestra_legacy_status_rules.dart';
import 'package:kute/models/orchestra_model.dart';
import 'package:kute/models/swap_order_model.dart';

SwapOrder _quoteRow() => SwapOrder(
      id: 'q_abc',
      coinFrom: 'BTC',
      networkFrom: 'LIGHTNING',
      coinTo: 'BTC',
      networkTo: 'SPARK',
      depositAddress: 'lnbc1invoice',
      depositExtraId: 'memo',
      depositAmount: '0.001',
      withdrawalAmount: '0.00099',
      status: 'wait',
      timestamp: DateTime.utc(2026, 9, 1).millisecondsSinceEpoch,
      withdrawalAddress: 'sp1recipient',
      depositMin: '0',
      depositMax: '0',
      rate: '0',
      refundAddress: 'sp1refund',
      provider: 'Orchestra',
      providerToken: 'read-token',
      walletId: 'wallet-1',
      expiresAt: DateTime.utc(2026, 9, 1, 0, 2).millisecondsSinceEpoch,
      purchaseSource: 'cashapp',
      purchaseFiatUsd: '55.00',
    );

OrchestraOrder _order(String id) =>
    OrchestraOrder(id: id, status: 'processing', createdAt: '');

/// A swap orders box keyed by id, like `sideshiftExchanges`.
class _Store {
  final rows = <String, SwapOrder>{};
  final writes = <String>[];
  bool killBeforeNextDelete = false;

  Future<void> add(SwapOrder row) async {
    writes.add('add:${row.id}');
    rows[row.id] = row;
  }

  Future<void> delete(String id) async {
    if (killBeforeNextDelete) throw StateError('process killed');
    writes.add('delete:$id');
    rows.remove(id);
  }
}

void main() {
  group('q_ to ord_ id swap', () {
    test('adds the ord_ row before deleting the q_ row', () async {
      final store = _Store()..rows['q_abc'] = _quoteRow();
      final replacement = legacyRowWithOrderId(_quoteRow(), 'ord_1');

      await replaceOrchestraRowId(
        oldId: 'q_abc',
        replacement: replacement,
        add: store.add,
        delete: store.delete,
      );

      expect(store.writes, ['add:ord_1', 'delete:q_abc']);
      expect(store.rows.keys, ['ord_1']);
    });

    test('a kill between the two writes leaves at least one pollable row',
        () async {
      final store = _Store()
        ..rows['q_abc'] = _quoteRow()
        ..killBeforeNextDelete = true;
      final replacement = legacyRowWithOrderId(_quoteRow(), 'ord_1');

      await expectLater(
        replaceOrchestraRowId(
          oldId: 'q_abc',
          replacement: replacement,
          add: store.add,
          delete: store.delete,
        ),
        throwsStateError,
      );

      final now = DateTime.utc(2026, 9, 1, 1);
      final pollable = store.rows.values
          .where((row) => legacyOrchestraRowNeedsStatusCheck(row, now))
          .map((row) => row.id)
          .toList();
      expect(pollable, contains('ord_1'));
    });

    test('the same id is never deleted', () async {
      final store = _Store()..rows['q_abc'] = _quoteRow();
      await replaceOrchestraRowId(
        oldId: 'q_abc',
        replacement: _quoteRow(),
        add: store.add,
        delete: store.delete,
      );
      expect(store.writes, ['add:q_abc']);
      expect(store.rows.keys, ['q_abc']);
    });

    test('the ord_ row keeps every field of the quote row', () {
      final quote = _quoteRow();
      final moved = legacyRowWithOrderId(quote, 'ord_1');

      expect(moved.id, 'ord_1');
      expect(moved.provider, 'Orchestra');
      expect(moved.purchaseSource, quote.purchaseSource);
      expect(moved.isCashAppPurchase, isTrue);
      expect(moved.purchaseFiatUsd, quote.purchaseFiatUsd);
      expect(moved.expiresAt, quote.expiresAt);
      expect(moved.providerToken, quote.providerToken);
      expect(moved.walletId, quote.walletId);
      expect(moved.depositAddress, quote.depositAddress);
      expect(moved.depositExtraId, quote.depositExtraId);
      expect(moved.depositAmount, quote.depositAmount);
      expect(moved.withdrawalAmount, quote.withdrawalAmount);
      expect(moved.withdrawalAddress, quote.withdrawalAddress);
      expect(moved.refundAddress, quote.refundAddress);
      expect(moved.status, quote.status);
      expect(moved.timestamp, quote.timestamp);
      expect(moved.coinFrom, quote.coinFrom);
      expect(moved.networkFrom, quote.networkFrom);
      expect(moved.coinTo, quote.coinTo);
      expect(moved.networkTo, quote.networkTo);
    });
  });

  group('replacement order id', () {
    test('any real non-quote id replaces a quote row', () {
      expect(legacyReplacementOrderId('q_abc', _order('ord_1')), 'ord_1');
      expect(legacyReplacementOrderId('q_abc', _order('9f2c')), '9f2c');
    });

    test('no replacement without a real order id', () {
      expect(legacyReplacementOrderId('q_abc', _order('')), isNull);
      expect(legacyReplacementOrderId('q_abc', _order('q_abc')), isNull);
      expect(legacyReplacementOrderId('q_abc', _order('q_other')), isNull);
      expect(legacyReplacementOrderId('ord_1', _order('ord_2')), isNull);
    });
  });
}
