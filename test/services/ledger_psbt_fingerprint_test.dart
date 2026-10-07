// PSBT fingerprint gate (Wallet hardening Phase 3, P3.2 / plan B2).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/hardware/ledger/ledger_failure.dart';
import 'package:kute/services/ledger_service.dart';
import 'package:ledger_bitcoin/ledger_bitcoin.dart';

class _Connection extends Fake implements LedgerConnection {
  @override
  bool get isDisconnected => false;

  @override
  Future<void> disconnect() async {}
}

class _FakeBitcoinApp extends Fake implements BitcoinLedgerApp {
  _FakeBitcoinApp(this.fingerprint);

  final List<int> fingerprint;
  int fingerprintReads = 0;
  int signCalls = 0;

  @override
  Future<Uint8List> getMasterFingerprint() async {
    fingerprintReads++;
    return Uint8List.fromList(fingerprint);
  }

  @override
  Future<Uint8List> signPsbt({required PsbtV2 psbt}) async {
    signCalls++;
    return Uint8List.fromList([0xde, 0xad, 0xbe, 0xef]);
  }
}

void main() {
  final device = LedgerDevice.ble(
      id: 'ledger-1', name: 'Ledger', deviceInfo: LedgerDeviceType.nanoX);

  Future<({LedgerService service, _FakeBitcoinApp app, List<int> parses})>
      connected(List<int> deviceFingerprint) async {
    final app = _FakeBitcoinApp(deviceFingerprint);
    final parses = <int>[];
    final service = LedgerService(
      detectDeviceType: (_) async => LedgerDeviceType.nanoX,
      connectDevice: (_) async => _Connection(),
      disconnectBle: (_) async {},
      bitcoinAppFactory: (connection, scriptType, path) => app,
      psbtV0Reader: (bytes) async {
        parses.add(bytes.length);
        return PsbtV2()
          ..setGlobalInputCount(0)
          ..setGlobalOutputCount(0);
      },
    );
    expect(await service.connectToDevice(device), isTrue);
    return (service: service, app: app, parses: parses);
  }

  test('a different device fingerprint is wrongDevice and never signs',
      () async {
    final s = await connected([0x01, 0x02, 0x03, 0x04]);
    final signed = await s.service.signPsbt('cHNidP8=',
        scriptType: 'bip84', expectedFingerprint: 'aabbccdd');
    expect(signed, isNull);
    expect(s.service.state.failure?.code, LedgerFailureCode.wrongDevice);
    expect(s.app.signCalls, 0);
    expect(s.parses, isEmpty, reason: 'the PSBT is never prepared');
    s.service.dispose();
  });

  test('a matching fingerprint signs (case-insensitive)', () async {
    final s = await connected([0xaa, 0xbb, 0xcc, 0xdd]);
    final signed = await s.service.signPsbt('cHNidP8=',
        scriptType: 'bip84', expectedFingerprint: 'AABBCCDD');
    expect(signed, 'deadbeef');
    expect(s.service.state.failure, isNull);
    expect(s.app.signCalls, 1);
    s.service.dispose();
  });

  test('a null stored fingerprint signs as today', () async {
    for (final stored in [null, '', '   ']) {
      final s = await connected([0x01, 0x02, 0x03, 0x04]);
      final signed = await s.service
          .signPsbt('cHNidP8=', scriptType: 'bip84', expectedFingerprint: stored);
      expect(signed, 'deadbeef', reason: 'stored=$stored');
      expect(s.service.state.failure, isNull);
      expect(s.app.signCalls, 1);
      // Read once for the PSBT fingerprint fix-up, as before. The service
      // has no settings access, so nothing can be written back here.
      expect(s.app.fingerprintReads, 1);
      s.service.dispose();
    }
  });

  test('signing with no connection reports disconnected', () async {
    final service = LedgerService(disconnectBle: (_) async {});
    expect(await service.signPsbt('cHNidP8=', expectedFingerprint: 'aabbccdd'),
        isNull);
    expect(service.state.failure?.code, LedgerFailureCode.disconnected);
    service.dispose();
  });
}
