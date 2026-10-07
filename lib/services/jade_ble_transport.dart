import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cbor/cbor.dart';
import 'package:universal_ble/universal_ble.dart';

/// Nordic UART Service UUIDs for Jade BLE communication.
class JadeBleConstants {
  JadeBleConstants._();
  static const serviceUuid = '6E400001-B5A3-F393-E0A9-E50E24DCCA9E';
  static const rxCharUuid = '6E400002-B5A3-F393-E0A9-E50E24DCCA9E';
  static const txCharUuid = '6E400003-B5A3-F393-E0A9-E50E24DCCA9E';
  static const defaultRequestMtu = 517;
  static const defaultWriteSize = 20;
  // The official jadepy BLE transport caps payloads at 517 - 8 bytes.
  static const maximumWriteSize = 509;
  static const maximumResponseBytes = 1024 * 1024;
  static const maximumQueuedMessages = 16;
}

/// Owns Jade's stream subscriptions without replacing Ledger's BLE callbacks.
class JadeBleTransport {
  final void Function()? onDisconnected;
  JadeBleTransport({this.onDisconnected});

  String? _deviceId;
  int _mtu = JadeBleConstants.defaultWriteSize + 3;
  bool _connected = false;
  bool _connecting = false;
  bool _writing = false;
  bool _exchanging = false;
  Future<void>? _disconnecting;
  int _generation = 0;
  bool _writeWithoutResponse = false;
  StreamSubscription<Uint8List>? _values;
  StreamSubscription<bool>? _connections;
  ByteConversionSink? _decoder;
  final _messages = Queue<Uint8List>();
  int _incompleteBytes = 0;
  Completer<Uint8List>? _messageCompleter;

  int get writeSize => math.min(JadeBleConstants.maximumWriteSize,
      math.max(JadeBleConstants.defaultWriteSize, _mtu - 3));
  bool get isConnected => _connected;

  Future<void> connect(String deviceId) async {
    if (_connecting) throw StateError('Jade connection is already in progress');
    _connecting = true;
    final generation = ++_generation;
    var lostConnection = false;
    var connectionAttempted = false;
    try {
      await _disconnect(invalidate: false);
      if (generation != _generation) {
        throw Exception('Jade connection was cancelled');
      }
      _deviceId = deviceId;
      _resetDecoder();
      _connections =
          UniversalBle.connectionStream(deviceId).listen((connected) {
        if (generation != _generation || connected) return;
        lostConnection = true;
        _connectionLost(Exception('Jade disconnected unexpectedly'));
        unawaited(disconnect());
      });
      connectionAttempted = true;
      await UniversalBle.connect(deviceId);
      _ensureCurrent(generation, lostConnection);
      final services = await UniversalBle.discoverServices(deviceId);
      _ensureCurrent(generation, lostConnection);
      final uart = services
          .where((service) =>
              _sameUuid(service.uuid, JadeBleConstants.serviceUuid))
          .firstOrNull;
      if (uart == null) {
        throw Exception('Device does not expose the Nordic UART service. '
            'Is this a Blockstream Jade?');
      }
      final tx = uart.characteristics
          .where((characteristic) =>
              _sameUuid(characteristic.uuid, JadeBleConstants.txCharUuid))
          .firstOrNull;
      final rx = uart.characteristics
          .where((characteristic) =>
              _sameUuid(characteristic.uuid, JadeBleConstants.rxCharUuid))
          .firstOrNull;
      final notify =
          tx?.properties.contains(CharacteristicProperty.notify) == true;
      final indicate =
          tx?.properties.contains(CharacteristicProperty.indicate) == true;
      if (!notify && !indicate) {
        throw Exception(
            'Jade TX characteristic does not support notifications');
      }
      // Prefer acknowledged writes, as in Blockstream's reference transport.
      if (rx?.properties.contains(CharacteristicProperty.write) == true) {
        _writeWithoutResponse = false;
      } else if (rx?.properties
              .contains(CharacteristicProperty.writeWithoutResponse) ==
          true) {
        _writeWithoutResponse = true;
      } else {
        throw Exception('Jade RX characteristic does not support writes');
      }
      try {
        final negotiated = await UniversalBle.requestMtu(
            deviceId, JadeBleConstants.defaultRequestMtu);
        _mtu = negotiated >= 23 ? negotiated : 23;
      } catch (_) {
        _mtu = JadeBleConstants.defaultWriteSize + 3;
      }
      _ensureCurrent(generation, lostConnection);
      // Install the listener before enabling notifications to retain early replies.
      _values = UniversalBle.characteristicValueStream(
              deviceId, JadeBleConstants.txCharUuid)
          .listen((bytes) {
        if (generation == _generation) _onBytes(bytes);
      }, onError: (Object error) {
        if (generation == _generation) {
          _connectionLost(Exception('Jade notification stream failed'));
          unawaited(disconnect());
        }
      });
      if (notify) {
        await UniversalBle.subscribeNotifications(deviceId,
            JadeBleConstants.serviceUuid, JadeBleConstants.txCharUuid);
      } else {
        await UniversalBle.subscribeIndications(deviceId,
            JadeBleConstants.serviceUuid, JadeBleConstants.txCharUuid);
      }
      _ensureCurrent(generation, lostConnection);
      _connected = true;
    } catch (_) {
      if (generation == _generation) {
        await disconnect();
      } else if (connectionAttempted) {
        // A cancelled native connect can still report success late. No new
        // connect can acquire this transport until this attempt has finished.
        try {
          await UniversalBle.disconnect(deviceId);
        } catch (_) {}
      }
      rethrow;
    } finally {
      _connecting = false;
    }
  }

  static bool _sameUuid(String a, String b) =>
      a.toLowerCase() == b.toLowerCase();

  void _ensureCurrent(int generation, bool lostConnection) {
    if (generation != _generation || lostConnection || _deviceId == null) {
      throw Exception('Jade disconnected unexpectedly');
    }
  }

  void _resetDecoder() {
    _messages.clear();
    _incompleteBytes = 0;
    _decoder =
        const CborDecoder().startChunkedConversion(_JadeCborSink((value) {
      _incompleteBytes = 0;
      // Unsolicited firmware logs are not RPC replies. Discard their payload.
      if (value is CborMap &&
          value.keys.any((key) => key is CborString && key.toString() == 'log')) {
        return;
      }
      // Each decoded item is retained even when it arrives before readMessage.
      // Re-encoding the envelope preserves CBOR byte-string payloads exactly.
      final bytes = Uint8List.fromList(cbor.encode(value));
      final waiting = _messageCompleter;
      if (waiting != null && !waiting.isCompleted) {
        _messageCompleter = null;
        waiting.complete(bytes);
      } else if (_messages.length < JadeBleConstants.maximumQueuedMessages) {
        _messages.add(bytes);
      } else {
        throw const FormatException('Too many pending Jade CBOR messages');
      }
    }));
  }

  void _onBytes(Uint8List bytes) {
    if (_deviceId == null) return;
    try {
      _incompleteBytes += bytes.length;
      if (_incompleteBytes > JadeBleConstants.maximumResponseBytes) {
        throw const FormatException(
            'Jade CBOR response exceeds the size limit');
      }
      _decoder?.add(bytes);
    } catch (_) {
      _connectionLost(const FormatException('Invalid Jade CBOR response'));
      unawaited(disconnect());
    }
  }

  void _connectionLost(Object error) {
    final wasConnected = _connected;
    _connected = false;
    _messages.clear();
    _decoder = null;
    _incompleteBytes = 0;
    final waiting = _messageCompleter;
    _messageCompleter = null;
    if (waiting != null && !waiting.isCompleted) waiting.completeError(error);
    if (wasConnected) onDisconnected?.call();
  }

  Future<void> write(Uint8List data) async {
    final deviceId = _deviceId;
    final generation = _generation;
    if (!_connected || deviceId == null) {
      throw Exception('Not connected to Jade');
    }
    if (_writing) throw StateError('A Jade write is already in progress');
    _writing = true;
    try {
      final chunkSize = writeSize;
      for (var offset = 0; offset < data.length; offset += chunkSize) {
        if (!_connected || generation != _generation) {
          throw Exception('Jade disconnected unexpectedly');
        }
        await UniversalBle.write(
            deviceId,
            JadeBleConstants.serviceUuid,
            JadeBleConstants.rxCharUuid,
            data.sublist(offset, math.min(offset + chunkSize, data.length)),
            withoutResponse: _writeWithoutResponse);
      }
      if (!_connected || generation != _generation) {
        throw Exception('Jade disconnected unexpectedly');
      }
    } finally {
      _writing = false;
    }
  }

  Future<Uint8List> readMessage(
      {Duration timeout = const Duration(seconds: 30)}) async {
    if (!_connected) throw Exception('Not connected to Jade');
    if (_messageCompleter != null) {
      throw StateError('A Jade read is already in progress');
    }
    if (_messages.isNotEmpty) return _messages.removeFirst();
    final waiting = Completer<Uint8List>();
    _messageCompleter = waiting;
    try {
      return await waiting.future.timeout(timeout);
    } finally {
      if (identical(_messageCompleter, waiting)) _messageCompleter = null;
    }
  }

  Future<Map<String, dynamic>> exchange(Map<String, dynamic> request,
      {Duration timeout = const Duration(seconds: 30)}) async {
    if (_exchanging) throw StateError('A Jade request is already in progress');
    _exchanging = true;
    final generation = _generation;
    try {
      await write(_encodeCbor(request));
      final response = _decodeCbor(await readMessage(timeout: timeout));
      if (request['id'] != null &&
          response['id']?.toString() != request['id'].toString()) {
        throw const FormatException(
            'Jade CBOR response ID does not match request');
      }
      return response;
    } catch (_) {
      // A partial write or late response must not be reused by another request.
      // No RPC is automatically retried, especially a signing operation.
      if (generation == _generation) await disconnect();
      rethrow;
    } finally {
      _exchanging = false;
    }
  }

  /// Encode a Dart map as CBOR bytes.
  Uint8List _encodeCbor(Map<String, dynamic> data) {
    final cborValue = _toCborValue(data);
    final encoded = cbor.encode(cborValue);
    return Uint8List.fromList(encoded);
  }

  /// Decode CBOR bytes to a Dart map.
  Map<String, dynamic> _decodeCbor(Uint8List bytes) {
    final decoded = cbor.decode(bytes);
    return _fromCborValue(decoded) as Map<String, dynamic>;
  }

  /// Convert a Dart value to a CborValue for encoding.
  CborValue _toCborValue(dynamic value) {
    if (value == null) return const CborNull();
    if (value is bool) return CborBool(value);
    if (value is int) return CborInt(BigInt.from(value));
    if (value is double) return CborFloat(value);
    if (value is String) return CborString(value);
    if (value is Uint8List) return CborBytes(value);
    if (value is List) {
      return CborList(value.map((e) => _toCborValue(e)).toList());
    }
    if (value is Map) {
      final cborMap = CborMap({});
      value.forEach((k, v) {
        cborMap[_toCborValue(k)] = _toCborValue(v);
      });
      return cborMap;
    }
    return CborString(value.toString());
  }

  /// Convert a CborValue to a Dart value.
  dynamic _fromCborValue(CborValue value) {
    if (value is CborNull) return null;
    if (value is CborBool) return value.value;
    if (value is CborInt) return value.toInt();
    if (value is CborFloat) return value.value;
    if (value is CborString) return value.toString();
    if (value is CborBytes) return Uint8List.fromList(value.bytes);
    if (value is CborList) {
      return value.toList().map((e) => _fromCborValue(e)).toList();
    }
    if (value is CborMap) {
      final map = <String, dynamic>{};
      for (final entry in value.entries) {
        final key = _fromCborValue(entry.key);
        map[key.toString()] = _fromCborValue(entry.value);
      }
      return map;
    }
    return value.toString();
  }

  Future<void> disconnect() => _disconnect(invalidate: true);

  Future<void> _disconnect({required bool invalidate}) {
    if (invalidate) ++_generation;
    final pending = _disconnecting;
    if (pending != null) return pending;
    late Future<void> operation;
    operation = _releaseConnection().whenComplete(() {
      if (identical(_disconnecting, operation)) _disconnecting = null;
    });
    _disconnecting = operation;
    return operation;
  }

  Future<void> _releaseConnection() async {
    final deviceId = _deviceId;
    _deviceId = null;
    _connectionLost(Exception('Jade disconnected unexpectedly'));
    final values = _values;
    final connections = _connections;
    _values = null;
    _connections = null;
    _mtu = JadeBleConstants.defaultWriteSize + 3;
    await values?.cancel();
    await connections?.cancel();
    if (deviceId != null) {
      try {
        await UniversalBle.unsubscribe(deviceId, JadeBleConstants.serviceUuid,
            JadeBleConstants.txCharUuid);
      } catch (_) {}
      try {
        await UniversalBle.disconnect(deviceId);
      } catch (_) {}
    }
  }
}

class _JadeCborSink implements Sink<CborValue> {
  final void Function(CborValue) onValue;
  _JadeCborSink(this.onValue);
  @override
  void add(CborValue value) => onValue(value);
  @override
  void close() {}
}
