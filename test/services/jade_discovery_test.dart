import 'dart:async';
import 'dart:typed_data';

import 'package:cbor/cbor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/bluetooth/ble_scan_coordinator.dart';
import 'package:kute/services/jade_service.dart';
import 'package:universal_ble/universal_ble.dart';

import 'support/fake_jade_ble.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeJadeBle ble;
  late JadeService service;
  setUp(() {
    ble = FakeJadeBle();
    UniversalBle.setInstance(ble);
    service = JadeService();
  });
  tearDown(() async {
    await service.stopScan();
    if (service.mounted) service.dispose();
  });

  test(
      'discovers Jade names, ignores unrelated UART devices and deduplicates IDs',
      () async {
    await service.startScan();
    ble.updateScanResult(BleDevice(deviceId: 'AA:BB', name: 'Jade 123456'));
    ble.updateScanResult(BleDevice(deviceId: 'aa:bb', name: 'Jade 123456'));
    ble.updateScanResult(BleDevice(deviceId: 'OTHER', name: 'NotJade UART'));
    ble.updateScanResult(BleDevice(deviceId: 'EMPTY', name: null));
    await Future<void>.delayed(Duration.zero);
    expect(service.state.foundDevices.map((device) => device.name),
        ['Jade 123456']);
    expect(ble.scanConfig!.android!.legacy, isTrue);
    expect(ble.scanConfig!.android!.scanMode, AndroidScanMode.lowLatency);
  });

  test('leaves other scan callbacks installed when Jade stops', () async {
    void ledgerListener(BleDevice device) {}
    UniversalBle.onScanResult = ledgerListener;
    await service.startScan();
    await service.stopScan();
    expect(ble.onScanResultUpdate, same(ledgerListener));
    expect(service.state.isScanning, isFalse);
  });

  test('stale Jade teardown cannot stop a newer Ledger scan', () async {
    await service.startScan();
    final ledgerLease = BleScanCoordinator.instance.acquire();
    await BleScanCoordinator.instance
        .start(ledgerLease, () => UniversalBle.startScan());
    final stopsBeforeJadeTeardown = ble.stopCount;
    await service.stopScan();
    expect(ble.stopCount, stopsBeforeJadeTeardown);
    expect(ledgerLease.isCurrent, isTrue);
    await BleScanCoordinator.instance.stop(ledgerLease);
  });

  test('a delayed stop cannot clear the scanning state of a newer scan',
      () async {
    await service.startScan();
    ble.stopGate = Completer<void>();
    final stopping = service.stopScan();
    await Future<void>.delayed(Duration.zero);
    final starting = service.startScan();
    await Future<void>.delayed(Duration.zero);
    ble.stopGate!.complete();
    await stopping;
    expect(service.state.isScanning, isTrue);
    await starting;
    expect(service.state.isScanning, isTrue);
  });

  test('repeated device taps do not start two connections', () async {
    ble.onWrite = (_) {
      ble.notify(Uint8List.fromList(cbor.encode(CborMap({
        CborString('id'): CborString('0'),
        CborString('result'):
            CborMap({CborString('JADE_VERSION'): CborString('test')}),
      }))));
    };
    const device = JadeBleDevice(id: 'JADE-A', name: 'Jade test');
    final first = service.connectToDevice(device);
    expect(await service.connectToDevice(device), isFalse);
    expect(await first, isTrue);
    expect(ble.connectCount, 1);
    await service.disconnect();
  });

  test('cancelling during permission request never starts a late scan',
      () async {
    ble.permissionGate = Completer<void>();
    final scanning = service.startScan();
    await Future<void>.delayed(Duration.zero);
    await service.stopScan();
    ble.permissionGate!.complete();
    await scanning;
    expect(ble.startCount, 0);
    expect(service.state.isScanning, isFalse);
  });

  test(
      'disposal during permission request does not publish state or start scanning',
      () async {
    ble.permissionGate = Completer<void>();
    final scanning = service.startScan();
    await Future<void>.delayed(Duration.zero);
    service.dispose();
    ble.permissionGate!.complete();
    await scanning;
    expect(ble.startCount, 0);
  });

  test(
      'powered-off Bluetooth reports an actionable error without starting a scan',
      () async {
    ble.availability = AvailabilityState.poweredOff;
    await service.startScan();
    expect(ble.startCount, 0);
    expect(service.state.isScanning, isFalse);
    expect(service.state.errorMessage, contains('turn on Bluetooth'));
  });
}
