// A coin received into Dollars through an address opened from the Bitcoin
// receive's "other coins" line shows in the Bitcoin Activity as well as in
// the Dollars (and Investments) Activity: the same row. A deposit to an
// address only ever opened from the Dollars receive stays on the dollar
// side, and no other dollar movement leaks onto the bitcoin ledger.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/helpers/swap_activity.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/screens/shared/transactions_builder.dart';
import 'package:kute/services/orchestra/bitcoin_receive_marks.dart';

const _marked = '0x1111111111111111111111111111111111111111';
const _dollarsOnly = '0x2222222222222222222222222222222222222222';
final _markedAt = DateTime.utc(2026, 10, 19, 12);

SwapOrderTransaction _row(
  String id, {
  required String depositAddress,
  String coinFrom = 'USDC',
  String networkFrom = 'polygon',
  String coinTo = 'USDB',
  String networkTo = 'SPARK',
  String? activityDirection = 'receive',
  String? purchaseSource = 'crypto_receive',
  DateTime? at,
  String walletId = 'spending',
}) {
  final ts = at ?? _markedAt.add(const Duration(minutes: 5));
  return SwapOrderTransaction(
    id: id,
    timestamp: ts,
    isConfirmed: false,
    details: SwapOrder(
      id: id,
      activityDirection: activityDirection,
      coinFrom: coinFrom,
      networkFrom: networkFrom,
      coinTo: coinTo,
      networkTo: networkTo,
      depositAddress: depositAddress,
      depositAmount: '5',
      withdrawalAmount: '0',
      status: 'success',
      timestamp: ts.millisecondsSinceEpoch,
      withdrawalAddress: 'sp1self',
      depositMin: '0',
      depositMax: '0',
      rate: '0',
      refundAddress: '',
      provider: 'Orchestra',
      walletId: walletId,
      purchaseSource: purchaseSource,
    ),
  );
}

List<String> _ids(List<BaseTransaction> rows,
        {required bool onlyUsdb, List<BitcoinReceiveMark> marks = const []}) =>
    assembleActivityRows(
      rows,
      ownAddresses: const {},
      isHardwareOrWatchOnly: false,
      onlyUsdb: onlyUsdb,
      classify: (o) => o.activityDirection == 'receive'
          ? SwapActivityKind.receive
          : SwapActivityKind.swap,
      bitcoinReceiveMarks: marks,
    ).map((t) => t.id).toList();

void main() {
  final mark = BitcoinReceiveMark(
      walletId: 'spending',
      label: 'sref',
      sourceChain: 'polygon',
      address: _marked,
      markedAtMs: _markedAt.millisecondsSinceEpoch);

  test(
      'a deposit to an address opened from Bitcoin is in both ledgers; one '
      'opened only from Dollars stays on the dollar side', () {
    final rows = <BaseTransaction>[
      _row('sdep_marked', depositAddress: _marked),
      _row('sdep_dollars', depositAddress: _dollarsOnly),
    ];
    expect(_ids(rows, onlyUsdb: false, marks: [mark]), ['sdep_marked']);
    expect(_ids(rows, onlyUsdb: true, marks: [mark]),
        unorderedEquals(['sdep_marked', 'sdep_dollars']));
    // With no mark, nothing dollar-only reaches the bitcoin ledger.
    expect(_ids(rows, onlyUsdb: false), isEmpty);
  });

  test('only deposits seen since the mark, on that chain, for that wallet', () {
    final rows = <BaseTransaction>[
      _row('before',
          depositAddress: _marked,
          at: _markedAt.subtract(const Duration(hours: 1))),
      _row('other_chain', depositAddress: _marked, networkFrom: 'base'),
      _row('other_wallet', depositAddress: _marked, walletId: 'savings'),
      _row('case',
          depositAddress: _marked.toUpperCase().replaceFirst('0X', '0x')),
    ];
    expect(_ids(rows, onlyUsdb: false, marks: [mark]), ['case']);
  });

  test('unrelated dollar movements stay out of the bitcoin ledger', () {
    final rows = <BaseTransaction>[
      // A dollar send paid to the same address string, a venue move and a
      // dollar conversion: none is a receive into Dollars on Spark.
      _row('send',
          depositAddress: _marked,
          coinFrom: 'USDB',
          networkFrom: 'polygon',
          coinTo: 'USDC',
          networkTo: 'POLYGON',
          activityDirection: 'send',
          purchaseSource: null),
      _row('venue',
          depositAddress: _marked,
          coinFrom: 'USDC',
          networkFrom: 'hypercore',
          activityDirection: null,
          purchaseSource: null),
    ];
    expect(_ids(rows, onlyUsdb: false, marks: [mark]), isEmpty);
  });

  group('the store', () {
    late Directory tmp;
    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('btc_receive_marks_');
      Hive.init(tmp.path);
      BitcoinReceiveMarks.reset();
    });
    tearDown(() async {
      BitcoinReceiveMarks.reset();
      await Hive.deleteFromDisk();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('keeps the first time, survives a restart, and forgets a wallet',
        () async {
      await BitcoinReceiveMarks.mark(
          walletId: 'spending',
          label: 'sref',
          sourceChain: 'Polygon',
          address: _marked,
          now: _markedAt);
      await BitcoinReceiveMarks.mark(
          walletId: 'spending',
          label: 'sref',
          sourceChain: 'polygon',
          address: _marked,
          now: _markedAt.add(const Duration(days: 1)));
      expect(BitcoinReceiveMarks.current.single.markedAtMs,
          _markedAt.millisecondsSinceEpoch);
      expect(BitcoinReceiveMarks.current.single.sourceChain, 'polygon');

      await Hive.close();
      BitcoinReceiveMarks.reset();
      await BitcoinReceiveMarks.load();
      expect(BitcoinReceiveMarks.current.single.address, _marked);

      await BitcoinReceiveMarks.deleteWallet('spending');
      expect(BitcoinReceiveMarks.current, isEmpty);
      BitcoinReceiveMarks.reset();
      await BitcoinReceiveMarks.load();
      expect(BitcoinReceiveMarks.current, isEmpty);
    });
  });
}
