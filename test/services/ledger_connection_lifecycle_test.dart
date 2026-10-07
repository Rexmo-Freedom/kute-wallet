import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/ledger_service.dart';
import 'package:ledger_flutter_plus/ledger_flutter_plus.dart';

class _TestConnection extends Fake implements LedgerConnection {
  int disconnects = 0;

  @override
  Future<void> disconnect() async {
    disconnects++;
  }
}

final _candidate = LedgerDevice.ble(
  id: 'test-device',
  name: 'Ledger',
  deviceInfo: LedgerDeviceType.nanoX,
);

void main() {
  test('the SDK receives the discovered model rather than the provisional one',
      () async {
    final connection = _TestConnection();
    final service = LedgerService(
      detectDeviceType: (_) async => LedgerDeviceType.nanoGen5,
      connectDevice: (device) async {
        expect(device.deviceInfo, LedgerDeviceType.nanoGen5);
        return connection;
      },
      disconnectBle: (_) async {},
    );
    expect(await service.connectToDevice(_candidate), true);
    expect(service.state.isConnected, true);
    await service.disconnect();
    expect(connection.disconnects, 1);
    service.dispose();
  });

  test('an unsupported service never reaches the SDK and closes its probe',
      () async {
    var sdkCalls = 0;
    var probeDisconnects = 0;
    final service = LedgerService(
      detectDeviceType: (_) async => null,
      connectDevice: (_) async {
        sdkCalls++;
        return _TestConnection();
      },
      disconnectBle: (_) async {
        probeDisconnects++;
      },
    );
    expect(await service.connectToDevice(_candidate), false);
    expect(sdkCalls, 0);
    expect(probeDisconnects, 1);
    service.dispose();
  });

  test('a repeated tap closes the old attempt before opening the next one',
      () async {
    final oldConnection = _TestConnection();
    final currentConnection = _TestConnection();
    final oldResult = Completer<LedgerConnection>();
    final oldStarted = Completer<void>();
    var attempts = 0;
    final service = LedgerService(
      detectDeviceType: (_) async => LedgerDeviceType.nanoX,
      connectDevice: (_) async {
        attempts++;
        if (attempts == 1) {
          oldStarted.complete();
          return oldResult.future;
        }
        expect(oldConnection.disconnects, 1);
        return currentConnection;
      },
      disconnectBle: (_) async {},
    );
    final oldAttempt = service.connectToDevice(_candidate);
    await oldStarted.future;
    final currentAttempt = service.connectToDevice(_candidate);
    expect(attempts, 1);
    oldResult.complete(oldConnection);
    expect(await oldAttempt, false);
    expect(await currentAttempt, true);
    expect(service.state.isConnected, true);
    expect(currentConnection.disconnects, 0);
    await service.disconnect();
    expect(currentConnection.disconnects, 1);
    service.dispose();
  });

  test(
      'disposing during connection closes the late result without publishing it',
      () async {
    final connection = _TestConnection();
    final result = Completer<LedgerConnection>();
    final started = Completer<void>();
    final service = LedgerService(
      detectDeviceType: (_) async => LedgerDeviceType.nanoX,
      connectDevice: (_) {
        started.complete();
        return result.future;
      },
      disconnectBle: (_) async {},
    );
    final attempt = service.connectToDevice(_candidate);
    await started.future;
    service.dispose();
    result.complete(connection);
    expect(await attempt, false);
    expect(connection.disconnects, 1);
  });

  test('cancellation during discovery closes its probe before a new attempt',
      () async {
    final discovered = Completer<LedgerDeviceType?>();
    final probeStarted = Completer<void>();
    var probes = 0;
    var probeDisconnects = 0;
    var sdkCalls = 0;
    final service = LedgerService(
      detectDeviceType: (_) async {
        probes++;
        if (probes == 1) {
          probeStarted.complete();
          return discovered.future;
        }
        expect(probeDisconnects, 1);
        return LedgerDeviceType.nanoX;
      },
      connectDevice: (_) async {
        sdkCalls++;
        return _TestConnection();
      },
      disconnectBle: (_) async {
        probeDisconnects++;
      },
    );
    final stale = service.connectToDevice(_candidate);
    await probeStarted.future;
    final current = service.connectToDevice(_candidate);
    discovered.complete(LedgerDeviceType.nanoGen5);
    expect(await stale, false);
    expect(await current, true);
    expect(sdkCalls, 1);
    await service.disconnect();
    service.dispose();
  });
}
