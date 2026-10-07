import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/ledger/ledger_device_discovery.dart';
import 'package:ledger_flutter_plus/ledger_flutter_plus.dart'
    show LedgerDeviceType;

void main() {
  test('recognizes each upstream Bluetooth model and excludes USB-only models',
      () {
    for (final model in LedgerDeviceType.values) {
      if (model.usbOnly) {
        expect(LedgerDeviceDiscovery.serviceUuids,
            isNot(contains(model.serviceId)));
      } else {
        expect(
            LedgerDeviceDiscovery.modelForServices([model.serviceId]), model);
        expect(LedgerDeviceDiscovery.serviceUuids,
            contains(model.serviceId.toLowerCase()));
      }
    }
  });

  test('Nano Gen5 selects its actual transport instead of the Nano X transport',
      () {
    const gen5Service = '13D63400-2C97-8004-0000-4C6564676572';
    expect(LedgerDeviceDiscovery.modelForServices([gen5Service]),
        LedgerDeviceType.nanoGen5);
    expect(LedgerDeviceDiscovery.modelForServices([gen5Service]),
        isNot(LedgerDeviceType.nanoX));
    expect(LedgerDeviceDiscovery.serviceUuids,
        contains(gen5Service.toLowerCase()));
  });

  test('GATT matching is case insensitive and ignores unrelated services', () {
    expect(
      LedgerDeviceDiscovery.modelForServices([
        '180f',
        ' 13d63400-2C97-3004-0000-4c6564676572 ',
      ]),
      LedgerDeviceType.flex,
    );
  });

  test('unknown Ledger-shaped UUIDs are not treated as supported models', () {
    const futureService = '13D63400-2C97-9999-0000-4C6564676572';
    expect(LedgerDeviceDiscovery.modelForServices([futureService]), isNull);
    expect(LedgerDeviceDiscovery.modelForServices(['']), isNull);
    expect(
        LedgerDeviceDiscovery.isCandidate(
            name: null, services: [futureService]),
        false);
  });

  test('a recognized service finds renamed and unnamed devices', () {
    final services = [LedgerDeviceType.stax.serviceId];
    expect(
        LedgerDeviceDiscovery.isCandidate(
            name: 'My signer', services: services),
        true);
    expect(LedgerDeviceDiscovery.isCandidate(name: null, services: services),
        true);
    expect(
        LedgerDeviceDiscovery.isCandidate(name: '', services: services), true);
  });

  test(
      'name-only candidates still need service discovery before model selection',
      () {
    for (final name in ['Ledger Nano Gen5', ' Nano X ', 'STAX', 'Flex']) {
      expect(LedgerDeviceDiscovery.isCandidate(name: name, services: const []),
          true);
    }
    expect(LedgerDeviceDiscovery.modelForServices(const []), isNull);
    expect(
        LedgerDeviceDiscovery.isCandidate(
            name: 'Headphones', services: const []),
        false);
  });

  test('a name-only or paired device connects before GATT discovery', () async {
    final connected = Completer<void>();
    var discoveryCalled = false;
    final detection = LedgerDeviceDiscovery.detectConnectedModel(
      connect: () => connected.future,
      discoverServices: () async {
        expect(connected.isCompleted, true);
        discoveryCalled = true;
        return [LedgerDeviceType.nanoGen5.serviceId];
      },
    );
    expect(discoveryCalled, false);
    connected.complete();
    expect(await detection, LedgerDeviceType.nanoGen5);
    expect(discoveryCalled, true);
  });

  test('a failed BLE connection does not attempt GATT discovery', () async {
    var discoveryCalled = false;
    await expectLater(
      LedgerDeviceDiscovery.detectConnectedModel(
        connect: () async => throw StateError('connection failed'),
        discoverServices: () async {
          discoveryCalled = true;
          return [LedgerDeviceType.nanoX.serviceId];
        },
      ),
      throwsStateError,
    );
    expect(discoveryCalled, false);
  });
}
