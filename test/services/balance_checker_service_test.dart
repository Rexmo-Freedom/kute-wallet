import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/balance_checker_service.dart';
import 'package:kute/services/onchain/native_onchain_service.dart';

void main() {
  test(
      'all recovery paths use the selected native backend and preserve results',
      () async {
    final native = _NativeFixture(balances: [100, 0, 900]);
    final service = _service(native);
    addTearDown(service.dispose);

    final result = await service.checkAllPaths('test mnemonic');

    expect(result.isComplete, isTrue);
    expect(result.error, isNull);
    expect(result.totalBalance, 1000);
    expect(result.paths.map((path) => path.derivationPath),
        ["m/44'/0'/0'", "m/49'/0'/0'", "m/84'/0'/0'"]);
    expect(result.paths.map((path) => path.scriptType),
        ['bip44', 'bip49', 'bip84']);
    expect(result.paths.map((path) => path.xpub),
        ['xpub-legacy', 'xpub-nested_segwit', 'xpub-native_segwit']);
    expect(result.paths[0].sampleAddress, 'sample-address');
    expect(result.paths[1].sampleAddress, isNull);
    expect(service.state.checkedPaths, 3);
    final opens = native.argumentsFor('open');
    expect(opens, hasLength(3));
    expect(opens.map((args) => args['walletId']).toSet(), hasLength(3));
    for (final args in opens) {
      expect(args['backendKind'], 'electrum');
      expect(args['backendUrl'], 'ssl://selected.example:50002');
      expect(args['network'], 'bitcoin');
      expect(args['temporary'], isTrue);
      expect(args['dbPath'], startsWith('/test/bdk_temp_check_'));
      expect(args['descriptor'], startsWith('private-external-'));
      expect(args['changeDescriptor'], startsWith('private-internal-'));
    }
    expect(
        native.argumentsFor('sync').every((args) => args['fullScan'] == true),
        isTrue);
    expect(native.argumentsFor('close'), hasLength(3));
    expect(
        native
            .argumentsFor('close')
            .every((args) => args['deleteTemporary'] == true),
        isTrue);
  });

  test('a failed path remains unknown and retains earlier funded paths',
      () async {
    final native = _NativeFixture(balances: [1500], failScan: 2);
    final service = _service(native);
    addTearDown(service.dispose);

    final result = await service.checkAllPaths('test mnemonic');

    expect(result.isComplete, isFalse);
    expect(result.paths, hasLength(1));
    expect(result.totalBalance, 1500);
    expect(result.error,
        'Could not check all Bitcoin addresses. Please try again.');
    expect(result.error, isNot(contains('sensitive-native-error')));
    expect(service.state.checkedPaths, 1);
    expect(service.state.isChecking, isFalse);
    expect(native.argumentsFor('sync'), hasLength(2));
    await _settleCleanup();
    expect(native.argumentsFor('close'), hasLength(2));
  });

  test('failure before any discovery is incomplete, never three empty paths',
      () async {
    final native = _NativeFixture(failScan: 1);
    final service = _service(native);
    addTearDown(service.dispose);

    final result = await service.checkAllPaths('test mnemonic');

    expect(result.isComplete, isFalse);
    expect(result.paths, isEmpty);
    expect(result.error, isNotNull);
    expect(service.state.checkedPaths, 0);
  });

  test(
      'temporary cleanup waits for the real scan reply after a visible timeout',
      () async {
    final scan = Completer<Object?>();
    final native = _NativeFixture(pendingScan: scan);
    final service = _service(native, timeout: const Duration(milliseconds: 5));
    addTearDown(service.dispose);

    final result = await service.checkAllPaths('test mnemonic');

    expect(result.isComplete, isFalse);
    expect(result.paths, isEmpty);
    expect(native.argumentsFor('close'), isEmpty);
    scan.complete({'fullScan': true, 'snapshot': _snapshot(600)});
    await _settleCleanup();
    expect(native.argumentsFor('close'), hasLength(1));
    expect(native.argumentsFor('close').single['deleteTemporary'], isTrue);
    expect(service.state.result, same(result));
  });

  test('watch-only discovery failures propagate instead of returning zero',
      () async {
    final native = _NativeFixture(failScan: 1);
    final service = _service(native);
    addTearDown(service.dispose);

    await expectLater(
        service.checkXpubBalance(xpub: 'xpub-test', scriptType: 'bip86'),
        throwsA(isA<OnchainException>()
            .having((error) => error.code, 'code', 'network')));
    await _settleCleanup();
    expect(native.argumentsFor('open').single['descriptor'],
        'public-external-bip86');
    expect(native.argumentsFor('open').single['dbPath'],
        startsWith('/test/bdk_xpub_check_'));
    expect(native.argumentsFor('close'), hasLength(1));
  });

  test('watch-only descriptor errors are static and never expose the key',
      () async {
    final native = _NativeFixture();
    final service = BalanceCheckerService(
        electrumUrl: 'https://selected.example/api',
        nativeService: NativeOnchainService(transport: native.call),
        directoryPath: () async => '/test',
        xpubDescriptorBuilder: (_, __) =>
            throw const FormatException('sensitive xpub'));
    addTearDown(service.dispose);

    await expectLater(
        service.checkXpubBalance(xpub: 'xpub-test', scriptType: 'bip84'),
        throwsA(isA<OnchainException>()
            .having((error) => error.code, 'code', 'invalid_request')
            .having((error) => error.toString(), 'message',
                isNot(contains('sensitive')))));
    expect(native.calls, isEmpty);
  });

  test(
      'an approved sweep scans, drains, signs and broadcasts on the same session',
      () async {
    final native = _NativeFixture(balances: [10000]);
    final service = _service(native);
    addTearDown(service.dispose);

    final txid = await service.sweepPath(
        mnemonic: 'test mnemonic',
        addressType: 'legacy',
        targetAddress: 'approved-target',
        feeRate: 2.1);

    expect(txid, _txid);
    expect(native.calls.map((call) => call.method),
        ['open', 'sync', 'build', 'sign', 'broadcast', 'close']);
    final build = native.argumentsFor('build').single;
    expect(build['drain'], isTrue);
    expect(build['amountSats'], 0);
    expect(build['address'], 'approved-target');
    expect(build['feeRateSatVb'], 3);
    final broadcast = native.argumentsFor('broadcast').single;
    expect(broadcast['format'], 'psbt');
    expect(broadcast['payload'], _signedPsbt);
    expect(native.calls.skip(1).map((call) => call.args['sessionId']).toSet(),
        hasLength(1));
    expect(native.argumentsFor('close').single['deleteTemporary'], isTrue);
  });

  test('a PSBT that was not fully signed is never broadcast', () async {
    final native = _NativeFixture(signed: false);
    final service = _service(native);
    addTearDown(service.dispose);

    final result = await service.sweepPath(
        mnemonic: 'test mnemonic',
        addressType: 'native_segwit',
        targetAddress: 'approved-target',
        feeRate: 1);

    expect(result, isNull);
    expect(native.argumentsFor('broadcast'), isEmpty);
    await _settleCleanup();
    expect(native.argumentsFor('close'), hasLength(1));
  });

  test('an uncertain broadcast is not automatically retried', () async {
    final native = _NativeFixture(failBroadcast: true);
    final service = _service(native);
    addTearDown(service.dispose);

    final result = await service.sweepPath(
        mnemonic: 'test mnemonic',
        addressType: 'native_segwit',
        targetAddress: 'approved-target',
        feeRate: 1);

    expect(result, isNull);
    expect(native.argumentsFor('broadcast'), hasLength(1));
    await _settleCleanup();
    expect(native.argumentsFor('close'), hasLength(1));
  });
}

BalanceCheckerService _service(_NativeFixture fixture,
        {Duration timeout = const Duration(seconds: 1)}) =>
    BalanceCheckerService(
        electrumUrl: 'ssl://selected.example:50002',
        nativeService: NativeOnchainService(
            transport: fixture.call, fullScanTimeout: timeout),
        directoryPath: () async => '/test',
        descriptorBuilder: (_, type) => (
              external: 'private-external-$type',
              internal: 'private-internal-$type',
              xpub: 'xpub-$type'
            ),
        xpubDescriptorBuilder: (xpub, type) => (
              external: 'public-external-$type',
              internal: 'public-internal-$type',
              xpub: xpub
            ));

Future<void> _settleCleanup() =>
    Future<void>.delayed(const Duration(milliseconds: 10));

const _txid =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _unsignedPsbt = 'cHNidP8A';
const _signedPsbt = 'cHNidP8AAA==';

Map<String, Object?> _snapshot(int total) => {
      'balance': {
        'confirmed': total,
        'trustedPending': 0,
        'untrustedPending': 0,
        'immature': 0,
        'total': total,
        'spendable': total
      },
      'transactions': <Object?>[],
      'utxos': <Object?>[],
    };

class _NativeFixture {
  final List<int> balances;
  final int? failScan;
  final Completer<Object?>? pendingScan;
  final bool signed;
  final bool failBroadcast;
  final calls = <({String method, Map<String, Object?> args})>[];
  int scans = 0;

  _NativeFixture(
      {this.balances = const [0, 0, 0],
      this.failScan,
      this.pendingScan,
      this.signed = true,
      this.failBroadcast = false});

  List<Map<String, Object?>> argumentsFor(String method) => calls
      .where((call) => call.method == method)
      .map((call) => call.args)
      .toList();

  Future<Object?> call(String method, Map<String, Object?> arguments) async {
    calls.add((method: method, args: Map.of(arguments)));
    switch (method) {
      case 'open':
        return {
          'sessionId': 'session-${arguments['walletId']}',
          'isNewWallet': true,
          'snapshot': _snapshot(0)
        };
      case 'sync':
        scans++;
        if (scans == failScan) {
          throw PlatformException(
              code: 'network', message: 'sensitive-native-error');
        }
        if (pendingScan != null) return pendingScan!.future;
        return {'fullScan': true, 'snapshot': _snapshot(balances[scans - 1])};
      case 'address':
        return {'address': 'sample-address', 'index': 0};
      case 'build':
      case 'sign':
        return {
          'psbt': method == 'sign' ? _signedPsbt : _unsignedPsbt,
          'feeSats': 140,
          if (method == 'sign') 'signed': signed,
          'tx': {
            'txid': _txid,
            'vsize': 140,
            'inputCount': 1,
            'outputCount': 1,
            'rawHex': ''
          }
        };
      case 'broadcast':
        if (failBroadcast) throw PlatformException(code: 'network');
        return {'txid': _txid};
      case 'close':
        return null;
      default:
        throw StateError('Unexpected test method');
    }
  }
}
