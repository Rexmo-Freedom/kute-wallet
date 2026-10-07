import 'dart:async';
import 'dart:typed_data';

import 'package:cbor/cbor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/jade_ble_transport.dart';
import 'package:universal_ble/universal_ble.dart';

import 'support/fake_jade_ble.dart';

Uint8List _reply(String id, [String result = 'ok']) =>
    Uint8List.fromList(cbor.encode(CborMap({
      CborString('id'): CborString(id),
      CborString('result'): CborString(result)
    })));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeJadeBle ble;
  late JadeBleTransport transport;
  setUp(() {
    ble = FakeJadeBle();
    UniversalBle.setInstance(ble);
    transport = JadeBleTransport();
  });
  tearDown(() async {
    await transport.disconnect();
  });

  test('simultaneous connection requests cannot both acquire the transport',
      () async {
    final first = transport.connect('JADE-A');
    await expectLater(transport.connect('JADE-A'), throwsStateError);
    await first;
    expect(ble.connectCount, 1);
  });

  test('a cancelled discovery cannot complete a stale connection', () async {
    ble.discoveryGate = Completer<void>();
    final connection =
        expectLater(transport.connect('JADE-A'), throwsException);
    await Future<void>.delayed(Duration.zero);
    final closing = transport.disconnect();
    ble.discoveryGate!.complete();
    await closing;
    await connection;
    expect(transport.isConnected, isFalse);
    expect(ble.connected, isEmpty);
  });

  test('a native connection that succeeds after cancellation is disconnected',
      () async {
    ble.connectGate = Completer<void>();
    ble.disconnectConfirmsPendingConnection = false;
    final connecting =
        expectLater(transport.connect('JADE-A'), throwsException);
    await Future<void>.delayed(Duration.zero);
    final closing = transport.disconnect();
    await Future<void>.delayed(Duration.zero);
    ble.connectGate!.complete();
    await connecting;
    await closing;
    expect(ble.connected, isEmpty);
    expect(transport.isConnected, isFalse);
  });

  test('reconnect waits for the previous physical disconnect to finish',
      () async {
    await transport.connect('JADE-A');
    ble.disconnectGate = Completer<void>();
    final closing = transport.disconnect();
    await Future<void>.delayed(Duration.zero);
    final reopening = transport.connect('JADE-A');
    await Future<void>.delayed(Duration.zero);
    expect(ble.connectCount, 1);
    ble.disconnectGate!.complete();
    await closing;
    await reopening;
    expect(ble.connectCount, 2);
    expect(transport.isConnected, isTrue);
  });

  test('Jade subscriptions leave Ledger global callbacks intact', () async {
    void values(
        String id, String characteristic, Uint8List bytes, int? timestamp) {}
    void connections(String id, bool connected, String? error) {}
    UniversalBle.onValueChange = values;
    UniversalBle.onConnectionChange = connections;
    await transport.connect('JADE-A');
    expect(ble.onValueChange, same(values));
    expect(ble.onConnectionChange, same(connections));
    await transport.disconnect();
    expect(ble.onValueChange, same(values));
    expect(ble.onConnectionChange, same(connections));
    expect(ble.notifications.last, BleInputProperty.disabled);
  });

  test('uses acknowledged chunks capped at the official Jade payload limit',
      () async {
    await transport.connect('JADE-A');
    await transport.write(Uint8List(1020));
    expect(transport.writeSize, 509);
    expect(ble.writes.map((bytes) => bytes.length), [509, 509, 2]);
    expect(ble.writeModes, everyElement(BleOutputProperty.withResponse));
  });

  test('MTU negotiation failure preserves safe 20-byte writes', () async {
    ble.mtuError = Exception('MTU unavailable');
    await transport.connect('JADE-A');
    await transport.write(Uint8List(41));
    expect(ble.writes.map((bytes) => bytes.length), [20, 20, 1]);
  });

  test('uses indication and write-without-response when those are supported',
      () async {
    ble.services = [
      BleService(JadeBleConstants.serviceUuid, [
        BleCharacteristic(
            JadeBleConstants.txCharUuid, [CharacteristicProperty.indicate], []),
        BleCharacteristic(JadeBleConstants.rxCharUuid,
            [CharacteristicProperty.writeWithoutResponse], []),
      ])
    ];
    await transport.connect('JADE-A');
    await transport.write(Uint8List.fromList([1]));
    expect(ble.notifications.first, BleInputProperty.indication);
    expect(ble.writeModes.single, BleOutputProperty.withoutResponse);
  });

  test('retains a reply received before the write future completes', () async {
    await transport.connect('JADE-A');
    ble.onWrite = (_) async {
      ble.notify(_reply('1'));
      await Future<void>.delayed(Duration.zero);
    };
    expect(await transport.exchange({'id': '1', 'method': 'get_version_info'}),
        {'id': '1', 'result': 'ok'});
    expect(ble.writes, hasLength(1));
  });

  test(
      'reassembles fragments and queues multiple CBOR frames in one notification',
      () async {
    await transport.connect('JADE-A');
    final first = _reply('1');
    ble.notify(first.sublist(0, 3), deviceId: 'jade-a');
    ble.notify(Uint8List.fromList([...first.sublist(3), ..._reply('2')]));
    expect(cbor.decode(await transport.readMessage()), cbor.decode(first));
    expect(
        cbor.decode(await transport.readMessage()), cbor.decode(_reply('2')));
  });

  test('skips unsolicited firmware logs before the matching RPC response',
      () async {
    await transport.connect('JADE-A');
    final log = cbor.encode(
        CborMap({CborString('log'): CborString('firmware diagnostic')}));
    ble.onWrite = (_) async {
      ble.notify(Uint8List.fromList([...log, ..._reply('5')]));
      await Future<void>.delayed(Duration.zero);
    };
    expect(await transport.exchange({'id': '5', 'method': 'get_version_info'}),
        {'id': '5', 'result': 'ok'});
    expect(transport.isConnected, isTrue);
  });

  test('ignores notifications belonging to a different device', () async {
    await transport.connect('JADE-A');
    ble.notify(_reply('wrong'), deviceId: 'LEDGER-B');
    ble.notify(_reply('1'));
    expect(
        cbor.decode(await transport.readMessage()), cbor.decode(_reply('1')));
  });

  test('a disconnected device fails an active reader promptly', () async {
    await transport.connect('JADE-A');
    final read = expectLater(transport.readMessage(), throwsException);
    ble.loseConnection();
    await read;
    expect(transport.isConnected, isFalse);
  });

  test('failed service discovery releases the connection', () async {
    ble.discoveryError = Exception('Discovery failed');
    await expectLater(transport.connect('JADE-A'), throwsException);
    expect(transport.isConnected, isFalse);
    expect(ble.connected, isEmpty);
    expect(ble.disconnectCount, 1);
  });

  test('failed notification subscription releases the connection', () async {
    ble.subscriptionError = Exception('Subscription failed');
    await expectLater(transport.connect('JADE-A'), throwsException);
    expect(ble.connected, isEmpty);
  });

  test('a mismatched response fails and disconnects without resending',
      () async {
    await transport.connect('JADE-A');
    ble.onWrite = (_) {
      ble.notify(_reply('old'));
    };
    await expectLater(transport.exchange({'id': 'new', 'method': 'sign_psbt'}),
        throwsFormatException);
    expect(ble.writes, hasLength(1));
    expect(transport.isConnected, isFalse);
  });

  test('an unanswered request times out and disconnects without resending',
      () async {
    await transport.connect('JADE-A');
    await expectLater(
        transport.exchange({'id': '1', 'method': 'sign_psbt'},
            timeout: const Duration(milliseconds: 10)),
        throwsA(isA<TimeoutException>()));
    expect(ble.writes, hasLength(1));
    expect(transport.isConnected, isFalse);
  });

  test('an overlapping request cannot replace the first response waiter',
      () async {
    await transport.connect('JADE-A');
    final first = transport.exchange({'id': '1', 'method': 'get_version_info'});
    await Future<void>.delayed(Duration.zero);
    await expectLater(
        transport.exchange({'id': '2', 'method': 'get_version_info'}),
        throwsStateError);
    ble.notify(_reply('1'));
    expect((await first)['id'], '1');
    expect(ble.writes, hasLength(1));
  });

  test('excessive incomplete CBOR fails safely instead of accumulating forever',
      () async {
    await transport.connect('JADE-A');
    final read = expectLater(transport.readMessage(), throwsFormatException);
    ble.notify(Uint8List(JadeBleConstants.maximumResponseBytes + 1));
    await read;
    expect(transport.isConnected, isFalse);
  });
}
