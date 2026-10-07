// A fake Ledger for unit tests.
//
// [FakeLedgerConnection] runs real `LedgerRawOperation`s (write, then read
// the response) against an APDU handler, so frame building and response
// parsing are exercised exactly as on a device.
//
// [FakeLedgerEthDevice] models the Ledger OS dashboard plus the Ethereum
// app. It rebuilds the EIP-712 typed data from the streamed definition and
// implementation frames, hashes it itself, and signs with a test key, so a
// happy-path signature only recovers when every frame was correct.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/hardware/eip712_typed_data.dart';
import 'package:kute/services/hardware/evm_signing_request.dart';
import 'package:ledger_flutter_plus/ledger_flutter_plus.dart'
    show LedgerConnection, LedgerDevice;
import 'package:ledger_flutter_plus/ledger_flutter_plus_dart.dart'
    show
        ByteDataReader,
        ByteDataWriter,
        ConnectionLostException,
        ConnectionType,
        DeviceNotConnectedException,
        LedgerDeviceType,
        LedgerTransformer;
// ignore: implementation_imports
import 'package:ledger_flutter_plus/src/operations/ledger_operations.dart'
    show LedgerOperation, LedgerRawOperation;
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show EthPrivateKey;
import 'package:web3dart/web3dart.dart' show privateKeyBytesToPublic;

typedef FakeApduHandler = FutureOr<List<int>> Function(Uint8List apdu);

List<int> ledgerOk([List<int> payload = const []]) => [...payload, 0x90, 0x00];

List<int> ledgerSw(int sw) => [(sw >> 8) & 0xff, sw & 0xff];

class FakeLedgerConnection extends Fake implements LedgerConnection {
  FakeLedgerConnection({this.id = 'ledger-1', required this.handler});

  final String id;
  FakeApduHandler handler;
  final List<Uint8List> sent = [];
  bool closed = false;
  int disconnects = 0;

  @override
  LedgerDevice get device => LedgerDevice.ble(
      id: id, name: 'Ledger', deviceInfo: LedgerDeviceType.nanoX);

  @override
  bool get isDisconnected => closed;

  @override
  Future<void> disconnect() async {
    closed = true;
    disconnects++;
  }

  /// Simulates the link dropping without an explicit disconnect.
  void drop() => closed = true;

  @override
  Future<T> sendOperation<T>(LedgerOperation<T> operation,
      {LedgerTransformer? transformer}) async {
    if (closed) {
      throw DeviceNotConnectedException(
          connectionType: ConnectionType.ble, requestedOperation: 'fake');
    }
    final raw = operation as LedgerRawOperation<T>;
    final apdu = (await raw.write(ByteDataWriter())).single;
    sent.add(apdu);
    final response = await handler(apdu);
    return raw.read(ByteDataReader()..add(response));
  }
}

class FakeLedgerEthDevice {
  FakeLedgerEthDevice({
    required this.key,
    this.runningApp = 'BOLOS',
    Set<String>? installedApps,
    this.ethVersion = const [1, 13, 0],
    String deviceId = 'ledger-1',
  }) : installedApps = installedApps ?? {'Bitcoin', 'Ethereum'} {
    connection = FakeLedgerConnection(id: deviceId, handler: handle);
  }

  final EthPrivateKey key;
  late final FakeLedgerConnection connection;
  String runningApp;
  Set<String> installedApps;
  List<int> ethVersion;

  // ── behaviour knobs ──
  String? reportedAddress;
  int? statusForEverything;
  int? openAppStatus;
  String? openAppActuallyOpens;
  int? definitionStatus;
  int? implementationStatus;
  int? signStatus;
  bool disconnectOnSign = false;
  bool dropLinkOnQuit = false;
  bool tamperSignature = false;
  Completer<void>? holdSign;

  /// Bitcoin app master fingerprint (4 bytes). Each read consumes the next
  /// entry of [fingerprintSequence] when set, so a test can change device
  /// identity mid-flow.
  List<int> bitcoinFingerprint = const [0xaa, 0xbb, 0xcc, 0xdd];
  List<List<int>>? fingerprintSequence;
  int fingerprintReads = 0;

  /// Status for GET_ETH_PUBLIC_ADDRESS with display (P1 0x01), e.g. 0x6985
  /// when the user rejects the address on the device.
  int? addressDisplayStatus;
  int addressDisplayPrompts = 0;

  /// Replaces the public key in address responses (to test key and
  /// address binding).
  List<int>? reportedPublicKey;

  // ── observations ──
  final List<Uint8List> frames = [];
  int prompts = 0;
  bool hashModeRequested = false;
  Eip712TypedData? lastTypedData;
  Uint8List? lastPersonalMessage;

  final Map<String, List<Eip712Field>> _types = {};
  String? _definingStruct;
  final List<Object> _events = [];
  List<int>? _pendingField;
  List<int>? _personal;
  int _personalLength = 0;

  Future<List<int>> handle(Uint8List apdu) async {
    frames.add(apdu);
    if (statusForEverything != null) return ledgerSw(statusForEverything!);
    final cla = apdu[0], ins = apdu[1], p1 = apdu[2], p2 = apdu[3];
    final data = apdu.sublist(5, 5 + apdu[4]);

    if (cla == 0xB0 && ins == 0x01) {
      final version = runningApp == 'Ethereum' ? ethVersion.join('.') : '2.2.4';
      return ledgerOk([
        0x01,
        runningApp.length,
        ...ascii.encode(runningApp),
        version.length,
        ...ascii.encode(version),
        0x01,
        0x00,
      ]);
    }
    if (cla == 0xB0 && ins == 0xA7) {
      runningApp = 'BOLOS';
      if (dropLinkOnQuit) {
        connection.drop();
        throw ConnectionLostException(connectionType: ConnectionType.ble);
      }
      return ledgerOk();
    }
    if (cla == 0xE0 && ins == 0xD8) {
      if (runningApp != 'BOLOS') return ledgerSw(0x6e01);
      if (openAppStatus != null) return ledgerSw(openAppStatus!);
      final name = utf8.decode(data);
      if (!installedApps.contains(name)) return ledgerSw(0x6807);
      runningApp = openAppActuallyOpens ?? name;
      return ledgerOk();
    }
    if (runningApp == 'Bitcoin' && cla == 0xE1 && ins == 0x05) {
      final sequence = fingerprintSequence;
      final fp = sequence != null && fingerprintReads < sequence.length
          ? sequence[fingerprintReads]
          : bitcoinFingerprint;
      fingerprintReads++;
      return ledgerOk(fp);
    }
    if (runningApp != 'Ethereum') return ledgerSw(0x6e00);

    switch (ins) {
      case 0x06:
        return ledgerOk([0x00, ...ethVersion]);
      case 0x02:
        if (p1 == 0x01) {
          addressDisplayPrompts++;
          if (addressDisplayStatus != null) {
            return ledgerSw(addressDisplayStatus!);
          }
        }
        final address =
            (reportedAddress ?? key.address.hexEip55).replaceFirst('0x', '');
        final pub = reportedPublicKey ?? [0x04, ..._publicKey()];
        return ledgerOk([pub.length, ...pub, 40, ...ascii.encode(address)]);
      case 0x1A:
        if (definitionStatus != null) return ledgerSw(definitionStatus!);
        _define(p2, data);
        return ledgerOk();
      case 0x1C:
        if (implementationStatus != null) {
          return ledgerSw(implementationStatus!);
        }
        _implement(p1, p2, data);
        return ledgerOk();
      case 0x0C:
        if (p2 != 0x01) {
          hashModeRequested = true;
          return ledgerSw(0x6a80);
        }
        return _prompt(() {
          final td = _rebuild();
          lastTypedData = td;
          return td.digest;
        });
      case 0x08:
        if (p1 == 0x00) {
          final count = data[0];
          var i = 1 + 4 * count;
          _personalLength = ByteData.sublistView(data, i, i + 4).getUint32(0);
          i += 4;
          _personal = data.sublist(i).toList();
        } else {
          _personal = [...?_personal, ...data];
        }
        if (_personal!.length < _personalLength) return ledgerOk();
        final message = Uint8List.fromList(_personal!);
        lastPersonalMessage = message;
        return _prompt(() => personalMessageDigest(message));
      default:
        return ledgerSw(0x6d00);
    }
  }

  /// 64-byte uncompressed public key (without the 0x04 prefix).
  List<int> _publicKey() => privateKeyBytesToPublic(key.privateKey);

  Future<List<int>> _prompt(Uint8List Function() digest) async {
    prompts++;
    final hold = holdSign;
    if (hold != null) await hold.future;
    if (disconnectOnSign) {
      connection.drop();
      throw ConnectionLostException(connectionType: ConnectionType.ble);
    }
    if (signStatus != null) return ledgerSw(signStatus!);
    final sig = await key.signToSignature(digest());
    final out = [sig.v, ..._be32(sig.r), ..._be32(sig.s)];
    if (tamperSignature) out[64] ^= 0x01;
    return ledgerOk(out);
  }

  void _define(int p2, Uint8List data) {
    if (p2 == 0x00) {
      _definingStruct = utf8.decode(data);
      _types[_definingStruct!] = [];
      return;
    }
    var i = 0;
    final desc = data[i++];
    final isArray = desc & 0x80 != 0;
    final hasSize = desc & 0x40 != 0;
    final typeId = desc & 0x0f;
    var base = '';
    if (typeId == 0) {
      final n = data[i++];
      base = utf8.decode(data.sublist(i, i + n));
      i += n;
    }
    final size = hasSize ? data[i++] : null;
    switch (typeId) {
      case 1:
        base = 'int${size! * 8}';
      case 2:
        base = 'uint${size! * 8}';
      case 3:
        base = 'address';
      case 4:
        base = 'bool';
      case 5:
        base = 'string';
      case 6:
        base = 'bytes$size';
      case 7:
        base = 'bytes';
    }
    var suffix = '';
    if (isArray) {
      final levels = data[i++];
      for (var l = 0; l < levels; l++) {
        suffix += data[i++] == 0 ? '[]' : '[${data[i++]}]';
      }
    }
    final keyLen = data[i++];
    final name = utf8.decode(data.sublist(i, i + keyLen));
    _types[_definingStruct!]!.add(Eip712Field(name, '$base$suffix'));
  }

  void _implement(int p1, int p2, Uint8List data) {
    switch (p2) {
      case 0x00:
        _events.add(_Root(utf8.decode(data)));
      case 0x0F:
        _events.add(_Array(data[0]));
      case 0xFF:
        _pendingField = [...?_pendingField, ...data];
        if (p1 == 0x00) {
          final full = _pendingField!;
          _pendingField = null;
          final len = (full[0] << 8) | full[1];
          if (full.length != len + 2) {
            throw StateError('Field length mismatch');
          }
          _events.add(_Value(Uint8List.fromList(full.sublist(2))));
        }
    }
  }

  Eip712TypedData _rebuild() {
    var cursor = 0;
    late final Map<String, Object?> Function(String name) decodeStruct;

    Object decodeField(String type) {
      if (Eip712TypedData.isArrayType(type)) {
        final array = _events[cursor++] as _Array;
        final element = Eip712TypedData.arrayElementType(type);
        return [for (var k = 0; k < array.count; k++) decodeField(element)];
      }
      if (_types.containsKey(type)) return decodeStruct(type);
      final bytes = (_events[cursor++] as _Value).bytes;
      switch (type) {
        case 'string':
          return utf8.decode(bytes);
        case 'bool':
          return bytes.single != 0;
        case 'address':
          return '0x${_hex(bytes)}';
        case 'bytes':
          return bytes;
      }
      final m = RegExp(r'^(uint|int|bytes)(\d+)$').firstMatch(type)!;
      if (m.group(1) == 'bytes') return bytes;
      var v = BigInt.zero;
      for (final b in bytes) {
        v = (v << 8) | BigInt.from(b);
      }
      final n = int.parse(m.group(2)!);
      if (m.group(1) == 'int' && v >= (BigInt.one << (n - 1))) {
        v -= BigInt.one << n;
      }
      return v;
    }

    decodeStruct = (String name) => {
          for (final f in _types[name]!) f.name: decodeField(f.type),
        };

    final domainRoot = _events[cursor++] as _Root;
    if (domainRoot.name != kEip712DomainType) {
      throw StateError('Domain must be sent first');
    }
    final domain = decodeStruct(kEip712DomainType);
    final primary = (_events[cursor++] as _Root).name;
    final message = decodeStruct(primary);
    if (cursor != _events.length) throw StateError('Unconsumed frames');

    final td = Eip712TypedData(
      types: Map.of(_types),
      primaryType: primary,
      domain: domain,
      message: message,
    );
    _types.clear();
    _events.clear();
    return td;
  }
}

class _Root {
  _Root(this.name);
  final String name;
}

class _Array {
  _Array(this.count);
  final int count;
}

class _Value {
  _Value(this.bytes);
  final Uint8List bytes;
}

List<int> _be32(BigInt value) {
  final out = List<int>.filled(32, 0);
  var v = value;
  for (var i = 31; i >= 0; i--) {
    out[i] = (v & BigInt.from(0xff)).toInt();
    v >>= 8;
  }
  return out;
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
