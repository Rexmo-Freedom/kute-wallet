import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/services/hardware/ledger/ledger_device_session.dart';
import 'package:kute/services/hardware/ledger/ledger_failure.dart';
import 'package:kute/services/hardware/ledger/ledger_pairing_service.dart';
import 'package:ledger_flutter_plus/ledger_flutter_plus.dart'
    show LedgerDevice;
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show EthPrivateKey;

import '../../../mocks/fake_ledger_eth_device.dart';

final _key = EthPrivateKey.fromHex(
    '0x0123456789012345678901234567890101234567890123456789012345678901');

Matcher _failure(LedgerFailureCode code) =>
    isA<LedgerFailure>().having((f) => f.code, 'code', code);

WalletConfig _ledger({String? fingerprint = 'aabbccdd'}) => WalletConfig(
      id: 'ledger-1',
      name: 'Ledger',
      sparkEnabled: false,
      isWatchOnly: true,
      isHardware: true,
      walletType: 'ledger',
      masterFingerprint: fingerprint,
    );

class _Harness {
  _Harness({LedgerReconnect? reconnect, FakeLedgerEthDevice? device})
      : device = device ?? FakeLedgerEthDevice(key: _key) {
    session = LedgerDeviceSession(
      connection: this.device.connection,
      reconnect: reconnect,
      appPollInterval: Duration.zero,
      appPollAttempts: 5,
      delay: (_) async {},
    );
    service = LedgerPairingService(
      session: session,
      persist: (identity) async => writes.add(identity),
      clock: () => DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );
  }

  final FakeLedgerEthDevice device;
  late final LedgerDeviceSession session;
  late final LedgerPairingService service;
  final writes = <LedgerEvmIdentity>[];
}

void main() {
  test('success writes a checksummed address, path and timestamp', () async {
    final h = _Harness();
    final steps = <LedgerPairingStep>[];

    final identity =
        await h.service.verifyEthereumIdentity(_ledger(), onStep: steps.add);

    expect(identity.address, _key.address.hexEip55);
    expect(identity.derivationPath, "m/44'/60'/0'/0/0");
    expect(identity.verifiedAtMs, 1700000000000);
    expect(h.writes.single.address, _key.address.hexEip55);
    expect(h.device.addressDisplayPrompts, 1);
    // Fingerprint read before and after the Ethereum read, in order.
    expect(h.device.fingerprintReads, 2);
    expect(h.device.runningApp, 'Bitcoin');
    expect(steps.last, LedgerPairingStep.done);
    expect(steps.indexOf(LedgerPairingStep.saving),
        greaterThan(steps.indexOf(LedgerPairingStep.recheckingFingerprint)));
  });

  test('a lowercase device address is stored as EIP-55', () async {
    final h = _Harness();
    h.device.reportedAddress = _key.address.hex.toLowerCase();
    final identity = await h.service.verifyEthereumIdentity(_ledger());
    expect(identity.address, _key.address.hexEip55);
  });

  test('display rejection writes nothing', () async {
    final h = _Harness();
    h.device.addressDisplayStatus = 0x6985;
    await expectLater(h.service.verifyEthereumIdentity(_ledger()),
        throwsA(_failure(LedgerFailureCode.rejected)));
    expect(h.writes, isEmpty);
  });

  test('fingerprint mismatch with the stored one before writes nothing',
      () async {
    final h = _Harness();
    await expectLater(
        h.service.verifyEthereumIdentity(_ledger(fingerprint: '01020304')),
        throwsA(_failure(LedgerFailureCode.wrongDevice)));
    expect(h.writes, isEmpty);
    expect(h.device.addressDisplayPrompts, 0);
  });

  test('fingerprint change after the Ethereum read writes nothing', () async {
    final h = _Harness();
    h.device.fingerprintSequence = [
      [0xaa, 0xbb, 0xcc, 0xdd],
      [0x11, 0x22, 0x33, 0x44],
    ];
    await expectLater(h.service.verifyEthereumIdentity(_ledger()),
        throwsA(_failure(LedgerFailureCode.wrongDevice)));
    expect(h.device.addressDisplayPrompts, 1);
    expect(h.writes, isEmpty);
  });

  test('a null stored fingerprint still requires before and after to match',
      () async {
    final h = _Harness();
    h.device.fingerprintSequence = [
      [0x01, 0x01, 0x01, 0x01],
      [0x02, 0x02, 0x02, 0x02],
    ];
    await expectLater(
        h.service.verifyEthereumIdentity(_ledger(fingerprint: null)),
        throwsA(_failure(LedgerFailureCode.wrongDevice)));
    expect(h.writes, isEmpty);
  });

  test('a device ID change on reconnect writes nothing', () async {
    final other = FakeLedgerEthDevice(key: _key, deviceId: 'ledger-2');
    late _Harness h;
    h = _Harness(
      reconnect: (LedgerDevice device) async => other.connection,
      device: FakeLedgerEthDevice(key: _key, runningApp: 'Bitcoin'),
    );
    // Quitting the Bitcoin app to open Ethereum drops the link.
    h.device.dropLinkOnQuit = true;
    await expectLater(h.service.verifyEthereumIdentity(_ledger()),
        throwsA(_failure(LedgerFailureCode.wrongDevice)));
    expect(h.writes, isEmpty);
    expect(other.connection.disconnects, 1);
  });

  test('a reconnect to the same device still re-checks the fingerprint',
      () async {
    final device = FakeLedgerEthDevice(key: _key, runningApp: 'Bitcoin')
      ..dropLinkOnQuit = true
      ..fingerprintSequence = [
        [0xaa, 0xbb, 0xcc, 0xdd],
        [0x99, 0x99, 0x99, 0x99],
      ];
    final h = _Harness(
      device: device,
      reconnect: (LedgerDevice _) async {
        device.connection.closed = false; // same device ID comes back
        return device.connection;
      },
    );
    await expectLater(h.service.verifyEthereumIdentity(_ledger()),
        throwsA(_failure(LedgerFailureCode.wrongDevice)));
    expect(h.session.reconnectCount, greaterThan(0));
    expect(h.writes, isEmpty);
  });

  test('same-device reconnects with a stable fingerprint succeed', () async {
    final device = FakeLedgerEthDevice(key: _key, runningApp: 'Bitcoin')
      ..dropLinkOnQuit = true;
    final h = _Harness(
      device: device,
      reconnect: (LedgerDevice _) async {
        device.connection.closed = false;
        return device.connection;
      },
    );
    final identity = await h.service.verifyEthereumIdentity(_ledger());
    expect(identity.address, _key.address.hexEip55);
    expect(h.session.reconnectCount, 2);
    expect(h.writes, hasLength(1));
  });

  test('unsupported Ethereum app version fails before the address prompt',
      () async {
    final h = _Harness();
    h.device.ethVersion = [1, 9, 18];
    await expectLater(h.service.verifyEthereumIdentity(_ledger()),
        throwsA(_failure(LedgerFailureCode.unsupportedAppVersion)));
    expect(h.device.addressDisplayPrompts, 0);
    expect(h.writes, isEmpty);
  });

  test('a public key that does not hash to the address writes nothing',
      () async {
    final h = _Harness();
    h.device.reportedPublicKey = [0x04, ...List.filled(64, 7)];
    await expectLater(h.service.verifyEthereumIdentity(_ledger()),
        throwsA(_failure(LedgerFailureCode.wrongDevice)));
    expect(h.writes, isEmpty);
  });

  test('a failing persist surfaces and nothing else is written', () async {
    final device = FakeLedgerEthDevice(key: _key);
    final session = LedgerDeviceSession(
      connection: device.connection,
      appPollInterval: Duration.zero,
      appPollAttempts: 5,
      delay: (_) async {},
    );
    final service = LedgerPairingService(
        session: session, persist: (_) async => throw StateError('disk'));
    await expectLater(
        service.verifyEthereumIdentity(_ledger()), throwsStateError);
  });

  test('refuses a wallet that is not a Ledger before touching the device',
      () async {
    final h = _Harness();
    await expectLater(
        h.service.verifyEthereumIdentity(WalletConfig(id: 'x', name: 'x')),
        throwsArgumentError);
    expect(h.device.frames, isEmpty);
  });

  test('a second verification while one is in flight is busy', () async {
    final h = _Harness();
    h.device.addressDisplayStatus = null;
    final first = h.service.verifyEthereumIdentity(_ledger());
    await expectLater(h.service.verifyEthereumIdentity(_ledger()),
        throwsA(_failure(LedgerFailureCode.busy)));
    await first;
    expect(h.writes, hasLength(1));
  });
}
