// BDK counts an unconfirmed send only once a sync sees it in the
// mempool, so after a Ledger broadcast the app re-scans that wallet
// (the hook below); otherwise its balance kept the spent coins until the
// person pulled to refresh.
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/bitcoin_model.dart';
import 'package:kute/services/bitcoin/ledger_btc_send_service.dart';
import 'package:mocktail/mocktail.dart';

class _Prepared extends Mock implements LedgerBtcPreparedSend {}

class _Signed extends Mock implements LedgerBtcSignedSend {}

class _Model extends Mock implements BitcoinModel {}

class _Config extends Mock implements Bitcoin {}

void main() {
  late _Model model;
  late _Signed signed;
  late List<String> rescanned;
  late LedgerBtcSendService service;

  setUp(() {
    final prepared = _Prepared();
    when(() => prepared.walletId).thenReturn('ledger-1');
    signed = _Signed();
    when(() => signed.prepared).thenReturn(prepared);
    when(() => signed.rawTxHex).thenReturn('00');
    final config = _Config();
    when(() => config.walletId).thenReturn('ledger-1');
    model = _Model();
    when(() => model.config).thenReturn(config);
    rescanned = [];
    service = LedgerBtcSendService(
      modelFor: (_) async => model,
      signPsbt: (_, {required scriptType, required expectedFingerprint}) =>
          throw UnimplementedError(),
      displayAddress: ({required scriptType, required addressIndex}) =>
          throw UnimplementedError(),
      onBroadcast: rescanned.add,
    );
  });

  test('a broadcast re-scans the wallet it spent from', () async {
    when(() => model.broadcastSignedTransaction(any()))
        .thenAnswer((_) async => 'ABCD');
    expect(await service.broadcast(signed), 'abcd');
    expect(rescanned, ['ledger-1']);
  });

  test('a failed broadcast re-scans nothing', () async {
    when(() => model.broadcastSignedTransaction(any()))
        .thenAnswer((_) async => throw Exception('rejected'));
    await expectLater(service.broadcast(signed), throwsException);
    expect(rescanned, isEmpty);
  });
}
