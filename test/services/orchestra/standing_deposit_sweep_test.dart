// Every deposit that reaches a receive address the app gave out appears
// in Activity as soon as the provider lists it. The incident this covers:
// 1.00 USDC sent on Polygon to a Dollars standing address was observed and
// bridged by Flashnet (Relay to Solana) and nothing ever showed in the app:
// a deposit with no order yet wrote no row at all, and an order whose
// source leg named another chain than the one paid was never matched.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/orchestra_model.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/services/orchestra/standing_deposit_activity.dart';
import 'package:kute/services/orchestra/standing_deposit_store.dart';
import 'package:kute/services/orchestra/standing_deposit_sweep.dart';
import 'package:kute/services/tracking_service.dart';

const _spark =
    'sp1pgssy7d7vel0nh9m4326qc54e6rskpczn07dktww9rv4nu5ptvt0s9ucez8h3s';
const _other =
    'sp1pgssxotherrecipientotherrecipientotherrecipientotherrecip0000';
const _polygon = '0x01fff40e5f134060e396195b4f80a281d68e6b91';

const _record = StandingDepositRecord(
  walletId: 'spending',
  label: 'sref',
  recipient: _spark,
  asset: 'USDB',
  revision: 4,
  response: {
    'standingAddressId': 'sda_1',
    'enabled': true,
    'addresses': {'polygon': _polygon},
  },
);

Map<String, dynamic> _deposit(
        {String status = 'processing',
        String? orderId,
        String? batchState,
        String? code}) =>
    {
      'id': 'dep_1',
      'chain': 'polygon',
      'asset': 'USDC',
      'amount': '1000000',
      'sourceTxId': '0xe2e7',
      'observedAt': '2026-10-18T20:22:20Z',
      'status': status,
      'code': code,
      'batchState': batchState,
      'orderId': orderId,
      'refundTxId': null,
    };

class _Rows implements StandingDepositRows {
  final byId = <String, SwapOrder>{};

  @override
  SwapOrder? find(String id) => byId[id];

  @override
  Future<void> put(SwapOrder row) async => byId[row.id] = row;

  @override
  Future<void> remove(String id) async => byId.remove(id);
}

void main() {
  late _Rows rows;
  late List<Map<String, dynamic>> listing;
  late Map<String, OrchestraOrder> orders;
  late List<String> discovered;
  late List<(String, Map<String, Object>?)> events;

  StandingDepositSweep sweep() => StandingDepositSweep(
        rows: rows,
        deposits: (record, current) async => listing,
        order: (id) async => orders[id],
        discovered: (row) => discovered.add(row.id),
      );

  Future<void> run({StandingDepositRecord record = _record}) =>
      sweep().syncRecord(
          record: record,
          walletId: 'spending',
          recipient: _spark,
          current: () => true);

  List<Map<String, Object>?> statusEvents() => [
        for (final e in events)
          if (e.$1 == 'standing_deposit_status') e.$2
      ];

  setUp(() {
    rows = _Rows();
    listing = [];
    orders = {};
    discovered = [];
    events = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });
  tearDown(() => TrackingService.debugTrackObserver = null);

  test('a deposit observed but not yet an order is a pending row', () async {
    for (final status in ['processing', 'detected', 'bridging', 'pending']) {
      rows = _Rows();
      listing = [_deposit(status: status)];
      await run();
      final row = rows.byId['sdep_dep_1']!;
      expect(row.status, isNot('wait'), reason: 'never "awaiting payment"');
      expect(row.isPending, isTrue, reason: status);
      expect(row.isExpired, isFalse);
      expect(row.isStuckStandingDeposit, isTrue);
      // No order id to ask the provider about.
      expect(row.shouldPollOrchestra, isFalse);
      expect(row.activityDirection, 'receive');
      expect(row.networkFrom, 'polygon');
      expect(row.coinFrom, 'USDC');
      expect(row.coinTo, 'USDB');
      expect(row.depositAddress, _polygon);
      expect(double.parse(row.depositAmount), 1.0);
      expect(row.timestamp,
          DateTime.parse('2026-10-18T20:22:20Z').millisecondsSinceEpoch);
    }
    expect(statusEvents().last, {
      'status': 'exchanging',
      'previous_status': 'none',
      'source_chain': 'polygon',
      'source_asset': 'USDC',
      'destination_asset': 'USDB',
      'amount': 1.0,
      'linked_order': false,
      'instruction': 'receive',
    });
    // The same status again writes and reports nothing.
    events.clear();
    await run();
    expect(statusEvents(), isEmpty);
  });

  test('held is a held row whose details offer the refund', () async {
    listing = [_deposit()];
    await run();
    listing = [
      _deposit(status: 'held', batchState: 'held', code: 'below_minimum')
    ];
    await run();
    final row = rows.byId['sdep_dep_1']!;
    expect(row.status, 'held');
    expect(row.isPending, isFalse);
    // The refund action finds its deposit by this id
    // (orchestra_swap_refund_action.dart).
    expect(row.stuckStandingDepositId, 'dep_1');
    expect(statusEvents().last!['previous_status'], 'exchanging');
    expect(statusEvents().last!['provider_code'], 'below_minimum');
    // Returned: by status, batch state or refund transaction.
    listing = [_deposit(status: 'refunded')];
    await run();
    expect(rows.byId['sdep_dep_1']!.status, 'refunded');
  });

  test('converted: the order row with the amount received replaces it',
      () async {
    listing = [_deposit()];
    await run();
    expect(rows.byId.keys, ['sdep_dep_1']);
    // Flashnet bridged the Polygon deposit to Solana before converting it,
    // so the order names another source leg than the one paid.
    listing = [_deposit(status: 'completed', orderId: 'ord_1')];
    orders['ord_1'] = OrchestraOrder(
      id: 'ord_1',
      status: 'completed',
      sourceChain: 'solana',
      sourceAsset: 'USDC',
      destinationChain: 'spark',
      destinationAsset: 'USDB',
      amountIn: '972414',
      amountOut: '967000',
      recipientAddress: _spark,
      depositAddress: 'JEJGkbBaoas7soCcTXK67q9VZ9rg3wJWSLEfj83ZgZi9',
      createdAt: '2026-10-18T20:22:44Z',
    );
    await run();
    expect(rows.byId.keys, ['ord_1'], reason: 'the deposit row retires');
    final row = rows.byId['ord_1']!;
    expect(row.status, 'success');
    expect(double.parse(row.withdrawalAmount), 0.967);
    expect(double.parse(row.depositAmount), 1.0,
        reason: 'what was sent, on the chain it was sent on');
    expect(row.networkFrom, 'polygon');
    expect(row.depositAddress, _polygon);
    expect(discovered, ['ord_1']);
  });

  test('an order that cannot be read yet keeps the deposit visible', () async {
    listing = [_deposit(status: 'processing', orderId: 'ord_2')];
    await run();
    final row = rows.byId['sdep_dep_1']!;
    expect(row.status, 'exchanging');
    expect(statusEvents().single!['linked_order'], isTrue);
    expect(discovered, isEmpty);
  });

  test('an order paying another recipient is never written', () async {
    listing = [_deposit(status: 'completed', orderId: 'ord_3')];
    orders['ord_3'] = OrchestraOrder(
      id: 'ord_3',
      status: 'completed',
      destinationChain: 'spark',
      destinationAsset: 'USDB',
      amountOut: '967000',
      recipientAddress: _other,
      createdAt: '2026-10-18T20:22:44Z',
    );
    await run();
    expect(rows.byId.containsKey('ord_3'), isFalse);
    // The money still shows, as the deposit it is.
    expect(rows.byId['sdep_dep_1']!.status, 'success');
  });

  test('failed with no order needs attention, never "expired"', () async {
    listing = [_deposit(status: 'failed')];
    await run();
    expect(rows.byId['sdep_dep_1']!.status, 'failed');
    listing = [_deposit(status: 'expired')];
    await run();
    expect(rows.byId['sdep_dep_1']!.status, 'failed');
  });

  test('the Investing-withdrawal instruction shows only what did not work',
      () async {
    final investing = StandingDepositRecord(
      walletId: 'spending',
      label: StandingDepositStore.investingWithdrawalLabelFor(_spark, 4),
      recipient: _spark,
      asset: 'USDB',
      revision: 4,
      response: const {
        'standingAddressId': 'sda_w',
        'enabled': true,
        'addresses': {'arbitrum': _polygon},
      },
    );
    listing = [
      {..._deposit(), 'chain': 'arbitrum'}
    ];
    await run(record: investing);
    expect(rows.byId, isEmpty, reason: 'the CCTP row shows it running');
    listing = [
      {..._deposit(status: 'held'), 'chain': 'arbitrum'}
    ];
    await run(record: investing);
    expect(rows.byId['sdep_dep_1']!.status, 'held');
  });

  test('standingDepositRowStatus maps the open status set', () {
    String of(Map<String, dynamic> d) => standingDepositRowStatus(d);
    expect(of(_deposit(status: 'confirming')), 'confirmation');
    expect(of(_deposit(status: 'materializing')), 'exchanging');
    expect(of(_deposit(status: 'awaiting_deposit')), 'exchanging');
    expect(of(_deposit(status: 'refund_requested')), 'refund_requested');
    expect(
        of(_deposit(status: 'processing', batchState: 'refunded')), 'refunded');
    expect(of(_deposit(status: 'failed', orderId: 'ord_1')), 'expired');
  });
}
