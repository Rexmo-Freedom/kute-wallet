import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/bitcoin_model.dart';
import 'package:kute/models/onchain_types.dart';
import 'package:kute/services/bitcoin/bitcoin_fee_estimate_service.dart';
import 'package:kute/services/onchain/native_onchain_service.dart';

final _txid = 'ab' * 32;
final _previousTxid = 'cd' * 32;
final _psbtBytes = <int>[0x70, 0x73, 0x62, 0x74, 0xff, 0x00];
final _psbtBase64 = base64Encode(_psbtBytes);

// Transport fixtures exercise the model's codec boundary. Native BDK, rather
// than the Dart model, validates the actual Bitcoin transaction and PSBT.
Map<String, Object?> _transaction() => {
      'txid': _txid,
      'vsize': 141,
      'inputCount': 1,
      'outputCount': 1,
      'rawHex': '',
      'inputs': [
        {
          'previousOutput': {'txid': _previousTxid, 'vout': 2},
        },
      ],
      'outputs': [
        {'value': 50000, 'scriptPubkey': '0014${'11' * 20}'},
      ],
    };

Map<String, Object?> _position() => {
      'height': 900000,
      'confirmationTime': 1700000000,
      'blockHash': 'ef' * 32,
      'lastSeen': null,
    };

Map<String, Object?> _snapshot({int confirmed = 50000}) => {
      'balance': {
        'confirmed': confirmed,
        'trustedPending': 0,
        'untrustedPending': 0,
        'immature': 0,
        'total': confirmed,
        'spendable': confirmed,
      },
      'transactions': [
        {
          'txid': _txid,
          'sent': 0,
          'received': 50000,
          'fee': null,
          'feeRate': null,
          'balanceDelta': 50000,
          'chainPosition': _position(),
          'tx': _transaction(),
        },
      ],
      'utxos': [
        {
          'outpoint': {'txid': _txid, 'vout': 0},
          'txout': {'value': 50000, 'scriptPubkey': '0014${'11' * 20}'},
          'keychain': 'external',
          'isSpent': false,
          'derivationIndex': 4,
          'chainPosition': _position(),
        },
      ],
    };

Map<String, Object?> _psbtResult({bool? signed, int? feeSats = 282}) => {
      'psbt': _psbtBase64,
      'feeSats': feeSats,
      'tx': _transaction(),
      if (signed != null) 'signed': signed,
    };

class _Call {
  final String method;
  final Map<String, Object?> arguments;
  _Call(this.method, this.arguments);
}

class _RecordingTransport {
  final calls = <_Call>[];
  FutureOr<Object?> Function(String method, Map<String, Object?> args)? respond;

  Future<Object?> invoke(String method, Map<String, Object?> args) async {
    calls.add(_Call(method, Map.of(args)));
    if (respond != null) return await respond!(method, args);
    return switch (method) {
      'open' => {
          'sessionId': 'native-session',
          'isNewWallet': false,
          'snapshot': _snapshot(),
        },
      'address' => {'address': 'bc1qfixture', 'index': args['index'] ?? 4},
      'build' || 'bump' => _psbtResult(),
      'sign' => _psbtResult(signed: true),
      'broadcast' => {'txid': _txid},
      'sync' => {
          'fullScan': args['fullScan'],
          'snapshot': _snapshot(confirmed: 75000)
        },
      'close' => null,
      _ => throw StateError('Unexpected test operation'),
    };
  }
}

void main() {
  late _RecordingTransport transport;
  late NativeWalletSession session;
  late BitcoinModel model;

  setUp(() async {
    transport = _RecordingTransport();
    final service = NativeOnchainService(transport: transport.invoke);
    session = await service.open(
      walletId: 'wallet-fixture',
      dbPath: '/test/wallet.sqlite',
      descriptor: 'public-external-fixture',
      changeDescriptor: 'public-change-fixture',
      network: 'bitcoin',
      endpoint: const OnchainEndpoint('esplora', 'https://example.invalid/api'),
    );
    model = BitcoinModel(Bitcoin(session, Network.bitcoin));
    transport.calls.clear();
  });

  group('snapshot reads', () {
    test('balance, history and unspent outputs need no native call', () {
      expect(model.config.walletId, 'wallet-fixture');
      expect(model.config.network, Network.bitcoin);
      expect(model.getBalance().total.toSat(), 50000);
      final history = model.getTransactions();
      expect(history.single.txid.toString(), _txid);
      expect(history.single.fee, isNull);
      expect(history.single.chainPosition, isA<ConfirmedChainPosition>());
      expect(history.single.tx.input().single.previousOutput.vout, 2);
      expect(history.single.tx.output().single.value.toSat(), 50000);
      expect(model.listUnspent().single.derivationIndex, 4);
      expect(transport.calls, isEmpty);
    });

    test('a completed sync replaces the readable snapshot', () async {
      await model.sync();
      expect(transport.calls.single.method, 'sync');
      expect(transport.calls.single.arguments['fullScan'], isFalse);
      expect(model.getBalance().total.toSat(), 75000);
    });

    test('full discovery requests a full scan explicitly', () async {
      await model.fullScan();
      expect(transport.calls.single.arguments['fullScan'], isTrue);
      expect(model.getBalance().total.toSat(), 75000);
    });

    test('a failed sync preserves the last successful snapshot', () async {
      transport.respond = (_, __) => throw PlatformException(code: 'network');
      await expectLater(model.sync(), throwsA(isA<OnchainException>()));
      expect(model.getBalance().total.toSat(), 50000);
      expect(model.getTransactions(), hasLength(1));
    });
  });

  group('address requests', () {
    test('next-unused, reveal and peek retain distinct address semantics',
        () async {
      expect((await model.getNextUnusedAddress()).index, 4);
      expect(await model.getAddress(), 4);
      expect(await model.getAddressString(), 'bc1qfixture');
      expect(await model.getCurrentAddress(12), 'bc1qfixture');
      expect((await model.getAddressInfo(19)).index, 19);
      expect(transport.calls.map((c) => c.arguments['mode']),
          ['nextUnused', 'revealNext', 'revealNext', 'peek', 'peek']);
      expect(transport.calls.map((c) => c.arguments['keychain']),
          everyElement('external'));
      expect(transport.calls[3].arguments['index'], 12);
      expect(transport.calls[4].arguments['index'], 19);
    });
  });

  group('transaction creation', () {
    test('rounds fractional fees up and returns actual native PSBT metadata',
        () async {
      final psbt = await model.buildBitcoinTransaction(
          TransactionBuilder(12000, 'bc1qrecipient', 2.1));
      final call = transport.calls.single;
      expect(call.method, 'build');
      expect(call.arguments, containsPair('walletId', 'wallet-fixture'));
      expect(call.arguments, containsPair('sessionId', 'native-session'));
      expect(call.arguments['deadlineMs'], isA<int>());
      expect(call.arguments['address'], 'bc1qrecipient');
      expect(call.arguments['amountSats'], 12000);
      expect(call.arguments['feeRateSatVb'], 3);
      expect(call.arguments['drain'], isFalse);
      expect(call.arguments.containsKey('selectedUtxos'), isFalse);
      expect(psbt.serialize(), _psbtBase64);
      expect(psbt.fee(), 282);
      expect(psbt.extractTx().vsize(), 141);
      expect(transport.calls.map((c) => c.method), ['build']);
    });

    test('drain is explicit and sends chosen outpoints without native handles',
        () async {
      final selected = [
        OutPoint(txid: Txid.fromString(hex: _previousTxid), vout: 2),
        OutPoint(txid: Txid.fromString(hex: _txid), vout: 0),
      ];
      await model.drainWalletBitcoinTransaction(
          TransactionBuilder(0, 'bc1qrecipient', 1, selectedUtxos: selected));
      expect(transport.calls.single.arguments['drain'], isTrue);
      expect(transport.calls.single.arguments['amountSats'], 0);
      expect(transport.calls.single.arguments['selectedUtxos'], [
        {'txid': _previousTxid, 'vout': 2},
        {'txid': _txid, 'vout': 0},
      ]);
    });

    test('an empty UTXO selection retains automatic coin selection', () async {
      await model.buildBitcoinTransaction(
          TransactionBuilder(1000, 'bc1qrecipient', 1, selectedUtxos: []));
      expect(transport.calls.single.arguments.containsKey('selectedUtxos'),
          isFalse);
    });

    for (final fee in [0.0, -1.0, double.nan, double.infinity]) {
      test('rejects invalid build fee $fee before dispatch', () async {
        await expectLater(
            model.buildBitcoinTransaction(
                TransactionBuilder(1000, 'recipient', fee)),
            throwsA(isA<OnchainException>()
                .having((e) => e.code, 'code', 'invalid_fee_rate')));
        expect(transport.calls, isEmpty);
      });
    }

    test('rejects a negative amount before dispatch', () async {
      await expectLater(
          model.buildBitcoinTransaction(TransactionBuilder(-1, 'recipient', 1)),
          throwsA(isA<OnchainException>()));
      expect(transport.calls, isEmpty);
    });

    test('preserves the native insufficient-funds category', () async {
      transport.respond = (_, __) => throw PlatformException(
          code: 'insufficient_funds', message: 'private native details');
      await expectLater(
          model.buildBitcoinTransaction(
              TransactionBuilder(1000, 'recipient', 1)),
          throwsA(isA<OnchainException>()
              .having((e) => e.code, 'code', 'insufficient_funds')
              .having((e) => e.toString(), 'safe message',
                  isNot(contains('private')))));
      expect(transport.calls, hasLength(1));
    });

    test('bump passes the original txid and rounded fee, without broadcast',
        () async {
      final psbt = await model
          .bumpFeeTransaction(BumpFeeTransactionBuilder(txid: _txid, fee: 3.2));
      expect(transport.calls.single.method, 'bump');
      expect(transport.calls.single.arguments['txid'], _txid);
      expect(transport.calls.single.arguments['feeRateSatVb'], 4);
      expect(psbt.fee(), 282);
    });

    for (final fee in [0.0, -1.0, double.nan, double.infinity]) {
      test('rejects invalid bump fee $fee before dispatch', () async {
        await expectLater(
            model.bumpFeeTransaction(
                BumpFeeTransactionBuilder(txid: _txid, fee: fee)),
            throwsA(isA<OnchainException>()
                .having((e) => e.code, 'code', 'invalid_fee_rate')));
        expect(transport.calls, isEmpty);
      });
    }

    test('signing returns the native PSBT and never broadcasts it', () async {
      final signed =
          await model.signBitcoinTransaction(Psbt.fromMap(_psbtResult()));
      expect(transport.calls.single.method, 'sign');
      expect(transport.calls.single.arguments['psbt'], _psbtBase64);
      expect(signed.signed, isTrue);
      expect(signed.serialize(), _psbtBase64);
    });

    test('unavailable native fee stays unavailable instead of becoming zero',
        () async {
      transport.respond = (_, __) => _psbtResult(feeSats: null);
      final psbt = await model
          .buildBitcoinTransaction(TransactionBuilder(1000, 'recipient', 1));
      expect(psbt.feeSats, isNull);
      expect(psbt.fee, throwsStateError);
    });
  });

  group('broadcasting', () {
    test('a reviewed PSBT uses exactly one native broadcast call', () async {
      expect(
          await model.broadcastBitcoinTransaction(
              Psbt.fromMap(_psbtResult(signed: true))),
          _txid);
      expect(transport.calls.single.method, 'broadcast');
      expect(transport.calls.single.arguments['format'], 'psbt');
      expect(transport.calls.single.arguments['payload'], _psbtBase64);
    });

    test('an uncertain network failure is returned without automatic retry',
        () async {
      transport.respond = (_, __) => throw PlatformException(code: 'network');
      await expectLater(
          model.broadcastBitcoinTransaction(
              Psbt.fromMap(_psbtResult(signed: true))),
          throwsA(isA<OnchainException>()
              .having((e) => e.code, 'code', 'network')));
      expect(transport.calls.map((c) => c.method), ['broadcast']);
    });

    test('hex hardware PSBT is recognized and normalized to base64', () async {
      await model.broadcastSignedTransaction(' 70 73 62 74 FF 00 ');
      expect(transport.calls.single.arguments['format'], 'psbt');
      expect(transport.calls.single.arguments['payload'], _psbtBase64);
    });

    test('base64 hardware PSBT retains all bytes', () async {
      final split =
          '${_psbtBase64.substring(0, 4)}\n${_psbtBase64.substring(4)}';
      await model.broadcastSignedTransaction(split);
      expect(transport.calls.single.arguments['format'], 'psbt');
      expect(transport.calls.single.arguments['payload'], _psbtBase64);
    });

    test('mixed-case raw transaction hex is normalized without signing in Dart',
        () async {
      await model.broadcastSignedTransaction(' 0A bB\nCc 01 ');
      expect(transport.calls.single.arguments['format'], 'hex');
      expect(transport.calls.single.arguments['payload'], '0abbcc01');
      expect(transport.calls.map((c) => c.method), ['broadcast']);
    });

    test('base64 raw transaction is converted to the native hex format',
        () async {
      await model
          .broadcastSignedTransaction(base64Encode([0x02, 0x00, 0xff, 0x01]));
      expect(transport.calls.single.arguments['format'], 'hex');
      expect(transport.calls.single.arguments['payload'], '0200ff01');
    });

    test(
        'a partial PSBT magic prefix remains a raw transaction for native validation',
        () async {
      await model.broadcastSignedTransaction('70736274');
      expect(transport.calls.single.arguments['format'], 'hex');
    });

    for (final value in ['', '   ', 'not a valid !!! encoding']) {
      test('invalid hardware input "$value" never reaches broadcast', () {
        expect(() => model.broadcastSignedTransaction(value),
            throwsFormatException);
        expect(transport.calls, isEmpty);
      });
    }
  });

  group('fee estimates', () {
    // The service keeps the last good rates in memory; every test starts
    // cold so one test's success cannot answer another's failure.
    setUp(BitcoinFeeEstimateService.instance.debugReset);
    tearDown(BitcoinFeeEstimateService.instance.debugReset);

    MockClient feeServer(Object fees) =>
        MockClient((request) async => http.Response(jsonEncode(fees), 200));
    const goodFees = {
      'fastestFee': 10,
      'halfHourFee': 7.5,
      'hourFee': 4,
      'economyFee': 2.25,
      'minimumFee': 1,
    };

    test('parses integer and fractional fee tiers from the fee endpoint',
        () async {
      final client = MockClient((request) async {
        expect(request.url.toString(),
            'https://mempool.space/api/v1/fees/recommended');
        return http.Response(
            jsonEncode({
              'fastestFee': 10,
              'halfHourFee': 7.5,
              'hourFee': 4,
              'economyFee': 2.25,
              'minimumFee': 1,
            }),
            200);
      });
      final fees =
          await http.runWithClient(model.estimateFeeRate, () => client);
      expect([
        fees.fastestFee,
        fees.halfHourFee,
        fees.hourFee,
        fees.economyFee,
        fees.minimumFee
      ], [
        10.0,
        7.5,
        4.0,
        2.25,
        1.0
      ]);
      expect(transport.calls, isEmpty);
    });

    test('does not return made-up fees when every host fails', () async {
      final hosts = <String>[];
      final client = MockClient((request) async {
        hosts.add(request.url.host);
        return http.Response('{}', 503);
      });
      await expectLater(http.runWithClient(model.estimateFeeRate, () => client),
          throwsA(isA<BitcoinFeeUnavailableException>()));
      // One primary request, then the fallback host.
      expect(hosts, ['mempool.space', 'blockstream.info', 'blockstream.info']);
    });

    test('malformed fee data fails instead of being treated as zero', () async {
      for (final body in [
        'not JSON',
        jsonEncode({...goodFees, 'hourFee': 0}),
        jsonEncode({...goodFees, 'economyFee': 'fast'}),
      ]) {
        BitcoinFeeEstimateService.instance.debugReset();
        final client = MockClient((_) async => http.Response(body, 200));
        await expectLater(
            http.runWithClient(model.estimateFeeRate, () => client),
            throwsA(isA<BitcoinFeeUnavailableException>()),
            reason: body);
      }
    });

    test('a failure after a good fetch serves the last rates, marked stale',
        () async {
      final live = await http.runWithClient(
          model.estimateFeeRate, () => feeServer(goodFees));
      expect(live.isStale, isFalse);
      final client = MockClient((_) async => http.Response('{}', 503));
      final cached =
          await http.runWithClient(model.estimateFeeRate, () => client);
      expect(cached.isStale, isTrue);
      expect(cached.fastestFee, 10.0);
      expect(cached.minimumFee, 1.0);
    });
  });
}
