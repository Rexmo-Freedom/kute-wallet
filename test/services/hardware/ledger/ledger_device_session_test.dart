import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/hardware/ledger/eth/eth_app_config_operation.dart';
import 'package:kute/services/hardware/ledger/eth/eth_eip712_operations.dart';
import 'package:kute/services/hardware/ledger/ledger_device_session.dart';
import 'package:kute/services/hardware/ledger/ledger_failure.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show EthPrivateKey;

import '../../../mocks/fake_ledger_eth_device.dart';

final _key = EthPrivateKey.fromHex('01'.padLeft(64, '0'));

TypeMatcher<LedgerFailure> _failure(LedgerFailureCode code) =>
    isA<LedgerFailure>().having((f) => f.code, 'code', code);

LedgerDeviceSession _session(
  FakeLedgerEthDevice device, {
  LedgerReconnect? reconnect,
  int attempts = 5,
}) =>
    LedgerDeviceSession(
      connection: device.connection,
      reconnect: reconnect,
      appPollInterval: Duration.zero,
      appPollAttempts: attempts,
      delay: (_) async {},
    );

/// CLA and INS of every frame, e.g. `b001`.
List<String> _ops(FakeLedgerEthDevice device) => device.frames
    .map((f) =>
        '${f[0].toRadixString(16).padLeft(2, '0')}${f[1].toRadixString(16).padLeft(2, '0')}')
    .toList();

void main() {
  group('single flight', () {
    test('a second flow while one is in flight fails with busy', () async {
      final device = FakeLedgerEthDevice(key: _key);
      final session = _session(device);
      final gate = Completer<void>();
      final first = session.run((scope) async {
        await gate.future;
        return 1;
      });
      expect(session.isBusy, isTrue);
      await expectLater(
          session.run((scope) async => 2), throwsA(_failure(LedgerFailureCode.busy)));
      gate.complete();
      expect(await first, 1);
      expect(session.isBusy, isFalse);
      expect(await session.run((scope) async => 3), 3);
    });

    test('reads with no prompt queue behind the current flow', () async {
      final device = FakeLedgerEthDevice(key: _key);
      final session = _session(device);
      final order = <String>[];
      final gate = Completer<void>();
      final flow = session.run((scope) async {
        await gate.future;
        order.add('flow');
      });
      final read = session.read((scope) async => order.add('read'));
      await Future<void>.delayed(Duration.zero);
      expect(order, isEmpty);
      gate.complete();
      await Future.wait([flow, read]);
      expect(order, ['flow', 'read']);
    });
  });

  group('app switching', () {
    test('quit, then open, then poll until the app answers', () async {
      final device = FakeLedgerEthDevice(key: _key, runningApp: 'Bitcoin');
      final session = _session(device);
      await session.run((scope) => scope.ensureApp(LedgerAppId.ethereum));
      expect(_ops(device), ['b001', 'b0a7', 'b001', 'e0d8', 'b001']);
      expect(session.confirmedApp, LedgerAppId.ethereum);
    });

    test('from the dashboard there is nothing to quit', () async {
      final device = FakeLedgerEthDevice(key: _key);
      final session = _session(device);
      await session.run((scope) => scope.ensureApp(LedgerAppId.ethereum));
      expect(_ops(device), ['b001', 'e0d8', 'b001']);
    });

    test('an app that is already open is only confirmed', () async {
      final device = FakeLedgerEthDevice(key: _key, runningApp: 'Ethereum');
      final session = _session(device);
      await session.run((scope) => scope.ensureApp(LedgerAppId.ethereum));
      expect(_ops(device), ['b001']);
    });

    test('a missing app is appNotInstalled for that app', () async {
      final device =
          FakeLedgerEthDevice(key: _key, installedApps: {'Bitcoin'});
      final session = _session(device);
      await expectLater(
        session.run((scope) => scope.ensureApp(LedgerAppId.ethereum)),
        throwsA(_failure(LedgerFailureCode.appNotInstalled)
            .having((f) => f.app, 'app', LedgerAppId.ethereum)),
      );
    });

    test('refusing to open the app on the device is a rejection', () async {
      final device = FakeLedgerEthDevice(key: _key)..openAppStatus = 0x5501;
      final session = _session(device);
      await expectLater(
        session.run((scope) => scope.ensureApp(LedgerAppId.ethereum)),
        throwsA(_failure(LedgerFailureCode.rejected)),
      );
    });

    test('a different app coming up is wrongApp', () async {
      final device = FakeLedgerEthDevice(key: _key)
        ..openAppActuallyOpens = 'Bitcoin';
      final session = _session(device, attempts: 3);
      await expectLater(
        session.run((scope) => scope.ensureApp(LedgerAppId.ethereum)),
        throwsA(_failure(LedgerFailureCode.wrongApp)
            .having((f) => f.app, 'app', LedgerAppId.ethereum)),
      );
    });

    test('an app that never comes up times out', () async {
      final device = FakeLedgerEthDevice(key: _key)
        ..openAppActuallyOpens = 'BOLOS';
      final session = _session(device, attempts: 3);
      await expectLater(
        session.run((scope) => scope.ensureApp(LedgerAppId.ethereum)),
        throwsA(_failure(LedgerFailureCode.timeout)),
      );
    });

    test('Ethereum commands in another app are wrongApp', () async {
      final device = FakeLedgerEthDevice(key: _key, runningApp: 'Bitcoin');
      final session = _session(device);
      await expectLater(
        session.run((scope) => scope.send(ethAppConfigApdu())),
        throwsA(_failure(LedgerFailureCode.wrongApp)),
      );
    });

    test('0x6d00 inside the confirmed app is an unsupported version',
        () async {
      final device = FakeLedgerEthDevice(key: _key)..definitionStatus = 0x6d00;
      final session = _session(device);
      await expectLater(
        session.run((scope) async {
          await scope.ensureApp(LedgerAppId.ethereum);
          await scope.send(eip712StructNameApdu('EIP712Domain'));
        }),
        throwsA(_failure(LedgerFailureCode.unsupportedAppVersion)),
      );
    });

    test('a locked device is locked', () async {
      final device = FakeLedgerEthDevice(key: _key)
        ..statusForEverything = 0x5515;
      final session = _session(device);
      await expectLater(
        session.run((scope) => scope.ensureApp(LedgerAppId.ethereum)),
        throwsA(_failure(LedgerFailureCode.locked)),
      );
    });
  });

  group('reconnect', () {
    test('a link drop during a switch reconnects to the same device and '
        're-checks identity', () async {
      final device = FakeLedgerEthDevice(key: _key, runningApp: 'Bitcoin')
        ..dropLinkOnQuit = true;
      var identityChecks = 0;
      final session = _session(device, reconnect: (d) async {
        expect(d.id, 'ledger-1');
        return FakeLedgerConnection(id: 'ledger-1', handler: device.handle);
      });
      await session.run(
        (scope) => scope.ensureApp(LedgerAppId.ethereum),
        identityCheck: (scope) async => identityChecks++,
      );
      expect(session.reconnectCount, 1);
      expect(identityChecks, 1);
      expect(session.confirmedApp, LedgerAppId.ethereum);
    });

    test('reconnecting to a different device ID is wrongDevice', () async {
      final device = FakeLedgerEthDevice(key: _key, runningApp: 'Bitcoin')
        ..dropLinkOnQuit = true;
      final other = FakeLedgerConnection(id: 'ledger-2', handler: device.handle);
      final session = _session(device, reconnect: (_) async => other);
      await expectLater(
        session.run((scope) => scope.ensureApp(LedgerAppId.ethereum)),
        throwsA(_failure(LedgerFailureCode.wrongDevice)),
      );
      expect(other.disconnects, 1);
      expect(session.connection.device.id, 'ledger-1');
    });

    test('without a reconnect path a dropped link is disconnected', () async {
      final device = FakeLedgerEthDevice(key: _key, runningApp: 'Bitcoin')
        ..dropLinkOnQuit = true;
      final session = _session(device);
      await expectLater(
        session.run((scope) => scope.ensureApp(LedgerAppId.ethereum)),
        throwsA(_failure(LedgerFailureCode.disconnected)),
      );
    });

    test('a disconnect mid-flow fails with disconnected', () async {
      final device = FakeLedgerEthDevice(key: _key, runningApp: 'Ethereum');
      final session = _session(device);
      await expectLater(
        session.run((scope) async {
          await scope.ensureApp(LedgerAppId.ethereum);
          device.connection.drop();
          await scope.send(ethAppConfigApdu());
        }),
        throwsA(_failure(LedgerFailureCode.disconnected)),
      );
      expect(session.confirmedApp, isNull);
    });
  });

  group('timeouts', () {
    test('a command with no prompt times out at the command timeout',
        () async {
      final connection = FakeLedgerConnection(
          handler: (_) => Completer<List<int>>().future);
      final session = LedgerDeviceSession(
        connection: connection,
        commandTimeout: const Duration(milliseconds: 20),
        promptTimeout: const Duration(seconds: 5),
      );
      await expectLater(
        session.run((scope) => scope.send(ethAppConfigApdu())),
        throwsA(_failure(LedgerFailureCode.timeout)),
      );
    });

    test('a prompting command waits for the prompt timeout', () async {
      final slowButAnswers = FakeLedgerConnection(handler: (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
        return ledgerOk([1]);
      });
      final session = LedgerDeviceSession(
        connection: slowButAnswers,
        commandTimeout: const Duration(milliseconds: 20),
        promptTimeout: const Duration(seconds: 2),
      );
      expect(
          await session
              .run((scope) => scope.send(eip712SignFullApdu(), prompts: true)),
          [1]);

      final never = FakeLedgerConnection(
          handler: (_) => Completer<List<int>>().future);
      final waiting = LedgerDeviceSession(
        connection: never,
        commandTimeout: const Duration(milliseconds: 10),
        promptTimeout: const Duration(milliseconds: 60),
      );
      await expectLater(
        waiting.run((scope) => scope.send(eip712SignFullApdu(), prompts: true)),
        throwsA(_failure(LedgerFailureCode.timeout)),
      );
    });
  });
}
