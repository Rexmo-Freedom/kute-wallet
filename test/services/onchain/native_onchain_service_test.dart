import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/onchain/native_onchain_service.dart';

Map<String, Object?> snapshot([int balance = 0]) => {
      'balance': {
        'confirmed': balance,
        'trustedPending': 0,
        'untrustedPending': 0,
        'immature': 0,
        'total': balance,
        'spendable': balance
      },
      'transactions': <Object?>[],
      'utxos': <Object?>[],
    };
Map<String, Object?> opened([String token = 'session']) => {
      'sessionId': token,
      'isNewWallet': false,
      'snapshot': snapshot(),
    };
Map<String, Object?> synced({bool full = false, int balance = 0}) => {
      'fullScan': full,
      'snapshot': snapshot(balance),
    };
Future<NativeWalletSession> open(NativeOnchainService service,
        {String id = 'wallet',
        bool temporary = false,
        Duration timeout = const Duration(seconds: 1),
        String descriptor = 'test descriptor'}) =>
    service.open(
        walletId: id,
        dbPath: '/tmp/bdk_temp_$id.sqlite',
        descriptor: descriptor,
        changeDescriptor: 'test change',
        network: 'bitcoin',
        temporary: temporary,
        timeout: timeout,
        endpoint: const OnchainEndpoint('esplora', 'https://example.test/api'));
Matcher errorCode(String code) =>
    isA<OnchainException>().having((e) => e.code, 'code', code);

void main() {
  test(
      'a successful full scan clears new-database discovery for provider rebuilds',
      () async {
    final service = NativeOnchainService(
        transport: (method, args) async => method == 'open'
            ? {...opened(), 'isNewWallet': true}
            : synced(full: true));
    final session = await open(service);
    expect(session.needsInitialScan, true);
    await session.sync(fullScan: true);
    expect(session.needsInitialScan, false);
  });

  test('uses the exact selected Electrum server, including existing defaults',
      () {
    for (final value in [
      'custom.example:50002',
      'electrum.blockstream.info:50002',
      'bitcoin-mainnet.blockstream.info:50002'
    ]) {
      final endpoint = OnchainEndpoint.fromStored(value);
      expect(endpoint.kind, 'electrum');
      expect(endpoint.url, 'ssl://$value');
    }
    expect(OnchainEndpoint.fromStored('tcp://localhost:50001').url,
        'tcp://localhost:50001');
    final endpoint =
        OnchainEndpoint.fromStored('https://my-node.test/esplora/');
    expect(endpoint.kind, 'esplora');
    expect(endpoint.url, 'https://my-node.test/esplora');
    expect(OnchainEndpoint.fromStored('', testnet: true).url,
        'ssl://electrum.blockstream.info:60002');
    expect(
        OnchainEndpoint.fromStored('https://blockstream.info/api',
                testnet: true)
            .url,
        'https://blockstream.info/testnet/api');
  });

  test('coalesces open and preserves the same opaque session', () async {
    final reply = Completer<Object?>();
    final requests = <String>[];
    final service = NativeOnchainService(transport: (method, args) {
      requests.add(method);
      expect(args['deadlineMs'], isA<int>());
      return reply.future;
    });
    final first = open(service);
    final second = open(service);
    expect(requests, ['open']);
    reply.complete(opened());
    final session = await first;
    expect(await second, same(session));
    expect(await open(service), same(session));
    await expectLater(open(service, descriptor: 'different'),
        throwsA(errorCode('wallet_mismatch')));
    expect(requests, ['open']);
  });

  test('joined scan propagates errors without retry or zero snapshot',
      () async {
    final reply = Completer<Object?>();
    var calls = 0;
    final service = NativeOnchainService(transport: (method, args) async {
      if (method == 'open') return opened();
      calls++;
      return reply.future;
    });
    final session = await open(service);
    final a = session.sync();
    final b = session.sync();
    final checks = [
      expectLater(a, throwsA(errorCode('network'))),
      expectLater(b, throwsA(errorCode('network')))
    ];
    reply.completeError(
        PlatformException(code: 'network', message: 'secret descriptor'));
    await Future.wait(checks);
    expect(calls, 1);
    expect(session.snapshot.balance.total.toSat(), 0);
  });

  test('timeout retains ownership until real completion and blocks mutations',
      () async {
    final reply = Completer<Object?>();
    final calls = <String>[];
    final service = NativeOnchainService(
        syncTimeout: const Duration(milliseconds: 5),
        transport: (method, args) async {
          calls.add(method);
          return method == 'open' ? opened() : reply.future;
        });
    final session = await open(service);
    await expectLater(session.sync(), throwsA(errorCode('timeout')));
    await expectLater(session.sync(), throwsA(errorCode('timeout')));
    await expectLater(session.call('build', {}), throwsA(errorCode('busy')));
    expect(calls, ['open', 'sync']);
    reply.complete(synced(balance: 123));
    await Future<void>.delayed(Duration.zero);
    expect(session.snapshot.balance.total.toSat(), 123);
  });

  test('full discovery waits for incremental and cannot be downgraded',
      () async {
    final incremental = Completer<Object?>();
    final discovery = Completer<Object?>();
    final modes = <bool>[];
    final service = NativeOnchainService(transport: (method, args) async {
      if (method == 'open') return opened();
      final full = args['fullScan']! as bool;
      modes.add(full);
      return full ? discovery.future : incremental.future;
    });
    final session = await open(service);
    final a = session.sync();
    final b = session.sync(fullScan: true);
    final c = session.sync(fullScan: true);
    expect(modes, [false]);
    incremental.complete(synced());
    await a;
    await Future<void>.delayed(Duration.zero);
    expect(modes, [false, true]);
    discovery.complete(synced(full: true, balance: 123));
    await Future.wait([b, c]);
    expect(session.snapshot.balance.total.toSat(), 123);
  });

  test('full scan join does not hide a failed incremental scan', () async {
    final reply = Completer<Object?>();
    var scanCalls = 0;
    final service = NativeOnchainService(transport: (method, args) async {
      if (method == 'open') return opened();
      scanCalls++;
      return reply.future;
    });
    final session = await open(service);
    final a = expectLater(session.sync(), throwsA(errorCode('network')));
    final b = expectLater(
        session.sync(fullScan: true), throwsA(errorCode('network')));
    reply.completeError(PlatformException(code: 'network'));
    await Future.wait([a, b]);
    expect(scanCalls, 1);
  });

  test('temporary cleanup waits for actual scan and coalesces close', () async {
    final scan = Completer<Object?>();
    final calls = <String>[];
    final service = NativeOnchainService(
        syncTimeout: const Duration(milliseconds: 5),
        transport: (method, args) async {
          calls.add(method);
          if (method == 'open') return opened();
          if (method == 'sync') return scan.future;
          expect(method, 'close');
          expect(args['deleteTemporary'], true);
          return null;
        });
    final session = await open(service, temporary: true);
    await expectLater(session.sync(), throwsA(errorCode('timeout')));
    final closing = session.close(deleteTemporary: true);
    final again = session.close(deleteTemporary: true);
    await expectLater(
        open(service, temporary: true), throwsA(errorCode('busy')));
    expect(calls, ['open', 'sync']);
    scan.complete(synced());
    await Future.wait([closing, again]);
    expect(calls, ['open', 'sync', 'close']);
    await expectLater(session.sync(), throwsA(errorCode('wallet_mismatch')));
  });

  test('late temporary open is released even when caller never got a token',
      () async {
    final reply = Completer<Object?>();
    final calls = <String>[];
    final service = NativeOnchainService(transport: (method, args) async {
      calls.add(method);
      if (method == 'open') return reply.future;
      expect(args['deleteTemporary'], true);
      return null;
    });
    await expectLater(
        open(service,
            temporary: true, timeout: const Duration(milliseconds: 5)),
        throwsA(errorCode('timeout')));
    reply.complete(opened());
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['open', 'close']);
  });

  test('never requests normal database deletion', () async {
    final calls = <String>[];
    final service = NativeOnchainService(transport: (method, args) async {
      calls.add(method);
      return opened();
    });
    final session = await open(service);
    await expectLater(session.close(deleteTemporary: true),
        throwsA(errorCode('invalid_request')));
    expect(calls, ['open']);
  });

  test('global admission remains bounded across wallets after a timeout',
      () async {
    final reply = Completer<Object?>();
    var count = 0;
    final service = NativeOnchainService(
        maxPending: 1,
        transport: (method, args) {
          count++;
          return reply.future;
        });
    await expectLater(open(service, timeout: const Duration(milliseconds: 5)),
        throwsA(errorCode('timeout')));
    await expectLater(open(service, id: 'other'), throwsA(errorCode('busy')));
    expect(count, 1);
    reply.complete(opened());
    await Future<void>.delayed(Duration.zero);
  });

  test('server change gates admission until settings are persisted', () async {
    final service = NativeOnchainService(
        transport: (method, args) async => method == 'open' ? opened() : null);
    await open(service);
    await service.closeAll(afterClose: () async {
      await expectLater(open(service), throwsA(errorCode('busy')));
    });
    expect(await open(service), isA<NativeWalletSession>());
  });

  test('retired wallet cannot reopen while its files are being removed',
      () async {
    final service = NativeOnchainService(
        transport: (method, args) async => method == 'open' ? opened() : null);
    await open(service);
    await service.retireWallet('wallet');
    await expectLater(open(service), throwsA(errorCode('busy')));
  });

  test('stale session cannot join a new session scan', () async {
    final reply = Completer<Object?>();
    final service = NativeOnchainService(
        transport: (method, args) async => method == 'open'
            ? opened()
            : method == 'sync'
                ? reply.future
                : null);
    final old = await open(service);
    await old.close();
    final current = await open(service);
    final scan = current.sync();
    await expectLater(old.sync(), throwsA(errorCode('wallet_mismatch')));
    reply.complete(synced());
    await scan;
  });

  test('unsupported platforms fail explicitly and SDK details are discarded',
      () async {
    final service = NativeOnchainService(
        transport: (method, args) async => throw MissingPluginException());
    await expectLater(open(service), throwsA(errorCode('unsupported')));
    final sensitive = NativeOnchainService(
        transport: (method, args) async =>
            throw PlatformException(code: 'private-key', message: 'secret'));
    await expectLater(open(sensitive), throwsA(errorCode('internal')));
    expect(const OnchainException('internal').toString(),
        isNot(contains('secret')));
  });
}
