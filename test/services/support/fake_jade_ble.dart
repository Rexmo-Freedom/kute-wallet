import 'dart:async';
import 'dart:typed_data';

import 'package:kute/services/jade_ble_transport.dart';
import 'package:universal_ble/universal_ble.dart';

class FakeJadeBle extends UniversalBlePlatform {
  AvailabilityState availability = AvailabilityState.poweredOn;
  Completer<void>? permissionGate;
  Completer<void>? connectGate;
  bool disconnectConfirmsPendingConnection = true;
  Completer<void>? discoveryGate;
  Completer<void>? disconnectGate;
  Completer<void>? stopGate;
  Object? discoveryError;
  Object? subscriptionError;
  Object? mtuError;
  int mtu = 517;
  int startCount = 0;
  int stopCount = 0;
  int disconnectCount = 0;
  int connectCount = 0;
  PlatformConfig? scanConfig;
  final connected = <String>{};
  final writes = <Uint8List>[];
  final writeModes = <BleOutputProperty>[];
  final notifications = <BleInputProperty>[];
  FutureOr<void> Function(Uint8List bytes)? onWrite;
  List<BleService> services = [
    BleService(JadeBleConstants.serviceUuid, [
      BleCharacteristic(
          JadeBleConstants.txCharUuid, [CharacteristicProperty.notify], []),
      BleCharacteristic(JadeBleConstants.rxCharUuid, [
        CharacteristicProperty.write,
        CharacteristicProperty.writeWithoutResponse
      ], []),
    ]),
  ];

  void notify(Uint8List bytes, {String deviceId = 'JADE-A'}) =>
      updateCharacteristicValue(
          deviceId, JadeBleConstants.txCharUuid, bytes, null);

  void loseConnection([String deviceId = 'JADE-A']) {
    connected.remove(deviceId.toLowerCase());
    updateConnection(deviceId, false);
  }

  @override
  Future<void> requestPermissions(
      {bool withAndroidFineLocation = false}) async {
    await permissionGate?.future;
  }

  @override
  Future<AvailabilityState> getBluetoothAvailabilityState() async =>
      availability;

  @override
  Future<void> startScan(
      {ScanFilter? scanFilter, PlatformConfig? platformConfig}) async {
    startCount++;
    scanConfig = platformConfig;
  }

  @override
  Future<void> stopScan() async {
    stopCount++;
    await stopGate?.future;
  }

  @override
  Future<void> connect(String deviceId,
      {Duration? connectionTimeout,
      bool autoConnect = false,
      ConnectionPlatformConfig? platformConfig}) async {
    connectCount++;
    await connectGate?.future;
    connected.add(deviceId.toLowerCase());
    updateConnection(deviceId, true);
  }

  @override
  Future<void> disconnect(String deviceId) async {
    disconnectCount++;
    await disconnectGate?.future;
    connected.remove(deviceId.toLowerCase());
    if (connectGate == null ||
        connectGate!.isCompleted ||
        disconnectConfirmsPendingConnection) {
      updateConnection(deviceId, false);
    }
  }

  @override
  Future<BleConnectionState> getConnectionState(String deviceId) async =>
      connectCount > 0 && connectGate != null && !connectGate!.isCompleted
          ? BleConnectionState.connecting
          : connected.contains(deviceId.toLowerCase())
              ? BleConnectionState.connected
              : BleConnectionState.disconnected;

  @override
  Future<List<BleService>> discoverServices(
      String deviceId, bool withDescriptors) async {
    await discoveryGate?.future;
    if (discoveryError != null) throw discoveryError!;
    return services;
  }

  @override
  Future<int> requestMtu(String deviceId, int expectedMtu) async {
    if (mtuError != null) throw mtuError!;
    return mtu;
  }

  @override
  Future<void> setNotifiable(String deviceId, String service,
      String characteristic, BleInputProperty property) async {
    notifications.add(property);
    if (subscriptionError != null && property != BleInputProperty.disabled) {
      throw subscriptionError!;
    }
  }

  @override
  Future<void> writeValue(
      String deviceId,
      String service,
      String characteristic,
      Uint8List value,
      BleOutputProperty property) async {
    writes.add(Uint8List.fromList(value));
    writeModes.add(property);
    await onWrite?.call(value);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected BLE test operation');
}
