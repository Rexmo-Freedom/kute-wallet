import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/background_sync_provider.dart'
    show orchestraCompletionLandsOnSpark;
import 'package:kute/services/funding/settlement_registration.dart';

SwapOrder _row(String id,
        {String status = 'exchanging', String networkTo = 'SPARK'}) =>
    SwapOrder(
      id: id,
      coinFrom: 'BTC',
      networkFrom: 'SPARK',
      coinTo: 'USDB',
      networkTo: networkTo,
      depositAddress: 'deposit',
      depositAmount: '0.00010000',
      withdrawalAmount: '6.00',
      status: status,
      timestamp: 1,
      withdrawalAddress: 'spark-self',
      depositMin: '0',
      depositMax: '0',
      rate: '0',
      refundAddress: 'spark-self',
      provider: 'Orchestra',
      walletId: 'spending',
      operationId: 'op-1',
    );

class _Rows {
  _Rows(List<SwapOrder> initial) : rows = [...initial];

  final List<SwapOrder> rows;
  final cached = <String, SwapOrder>{};
  final uncached = <String>[];
  final logged = <String>[];
  final writes = <String>[];

  OrchestraActivityRows get sink => OrchestraActivityRows(
        rows: () => List.of(rows),
        add: (row) async {
          writes.add('add ${row.id}');
          rows.removeWhere((r) => r.id == row.id);
          rows.add(row);
        },
        delete: (id) async {
          writes.add('delete $id');
          rows.removeWhere((r) => r.id == id);
        },
        uncache: uncached.add,
        cache: (row) => cached[row.id] = row,
        logPending: (row) => logged.add(row.id),
      );
}

void main() {
  group('adoptRegisteredOrchestraRow', () {
    test('moves the quote row to the order id, writing before deleting',
        () async {
      final rows = _Rows([_row('q_1')]);
      final moved = await adoptRegisteredOrchestraRow(
          quoteId: 'q_1', orderId: 'ord_1', rows: rows.sink);

      expect(moved!.id, 'ord_1');
      expect(moved.operationId, 'op-1');
      expect(moved.withdrawalAmount, '6.00');
      expect(rows.writes, ['add ord_1', 'delete q_1']);
      expect(rows.rows.map((r) => r.id), ['ord_1']);
      expect(rows.uncached, ['q_1']);
      expect(rows.cached.keys, ['ord_1']);
      expect(rows.logged, ['ord_1']);
    });

    test('does nothing when the status poll already moved the row', () async {
      final rows = _Rows([_row('ord_1')]);
      expect(
          await adoptRegisteredOrchestraRow(
              quoteId: 'q_1', orderId: 'ord_1', rows: rows.sink),
          isNull);
      expect(rows.writes, isEmpty);
      expect(rows.logged, isEmpty);
    });

    test('never moves a row to a quote id', () async {
      final rows = _Rows([_row('q_1')]);
      expect(
          await adoptRegisteredOrchestraRow(
              quoteId: 'q_1', orderId: 'q_1', rows: rows.sink),
          isNull);
      expect(
          await adoptRegisteredOrchestraRow(
              quoteId: 'q_1', orderId: '', rows: rows.sink),
          isNull);
      expect(rows.writes, isEmpty);
    });

    test('a row that already completed moves without a pending report',
        () async {
      final rows = _Rows([_row('q_1', status: 'success')]);
      final moved = await adoptRegisteredOrchestraRow(
          quoteId: 'q_1', orderId: 'ord_1', rows: rows.sink);
      expect(moved!.id, 'ord_1');
      expect(rows.logged, isEmpty);
    });
  });

  group('orchestraCompletionLandsOnSpark', () {
    test('a newly completed delivery to Spark syncs the wallet', () {
      expect(
          orchestraCompletionLandsOnSpark(_row('ord_1'), 'success',
              wasTerminal: false),
          isTrue);
    });

    test('nothing else does', () {
      expect(
          orchestraCompletionLandsOnSpark(_row('ord_1'), 'success',
              wasTerminal: true),
          isFalse,
          reason: 'already reported');
      expect(
          orchestraCompletionLandsOnSpark(_row('ord_1'), 'exchanging',
              wasTerminal: false),
          isFalse);
      expect(
          orchestraCompletionLandsOnSpark(
              _row('ord_1', networkTo: 'POLYGON'), 'success',
              wasTerminal: false),
          isFalse,
          reason: 'a venue deposit lands elsewhere');
    });
  });
}
