import 'dart:typed_data';

import 'jade_ble_transport.dart';

/// Represents a Jade RPC error response.
class JadeRpcError implements Exception {
  final int code;
  final String message;
  final dynamic data;

  JadeRpcError({required this.code, required this.message, this.data});

  @override
  String toString() => 'JadeRpcError($code): $message';
}

/// CBOR-RPC protocol layer for Blockstream Jade.
///
/// Builds and parses Jade RPC messages over [JadeBleTransport].
/// Each request is a CBOR map: `{id, method, params}`.
/// Each response is a CBOR map: `{id, result}` or `{id, error: {code, message}}`.
class JadeRpc {
  final JadeBleTransport _transport;
  int _idCounter = 0;

  JadeRpc(this._transport);

  String _nextId() => '${_idCounter++}';

  /// Send an RPC request and return the result.
  ///
  /// Throws [JadeRpcError] if the device returns an error response.
  /// Throws [TimeoutException] if no response within [timeout].
  Future<dynamic> call(
    String method, {
    Map<String, dynamic>? params,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final id = _nextId();
    final request = <String, dynamic>{
      'id': id,
      'method': method,
    };
    if (params != null) {
      request['params'] = params;
    }

    final response = await callRaw(request, timeout: timeout);
    return response['result'];
  }

  /// Send a pre-built request and return its validated response envelope.
  Future<Map<String, dynamic>> callRaw(
    Map<String, dynamic> request, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final response = await _transport.exchange(request, timeout: timeout);
    if (response['id']?.toString() != request['id']?.toString() ||
        request['id'] == null) {
      throw _invalidResponse();
    }
    if (response.containsKey('error')) {
      final error = response['error'];
      final code =
          error is Map && error['code'] is int ? error['code'] as int : -1;
      // Firmware error data can contain the request or encrypted PIN payload.
      // Preserve only known categories, never a device-supplied message/body.
      final text = error is Map && error['message'] is String
          ? (error['message'] as String).toLowerCase()
          : '';
      final message =
          text.contains('user_cancelled') || text.contains('user cancelled')
              ? 'USER_CANCELLED'
              : text.contains('not_logged_in') || text.contains('not logged in')
                  ? 'NOT_LOGGED_IN'
                  : text.contains('bad_params') || text.contains('bad params')
                      ? 'BAD_PARAMS'
                      : 'Jade request could not be completed.';
      throw JadeRpcError(code: code, message: message);
    }
    if (!response.containsKey('result')) throw _invalidResponse();
    return response;
  }

  static JadeRpcError _invalidResponse() =>
      JadeRpcError(code: -1, message: 'Invalid Jade CBOR response.');

  static Uint8List _responseBytes(Object? result) {
    if (result is! List ||
        result.any((byte) => byte is! int || byte < 0 || byte > 255)) {
      throw _invalidResponse();
    }
    return Uint8List.fromList(result.cast<int>());
  }

  /// Get device version info (firmware version, board type, features).
  Future<Map<String, dynamic>> getVersionInfo() async {
    final result = await call('get_version_info');
    return Map<String, dynamic>.from(result as Map);
  }

  /// Initiate user authentication (triggers PIN entry on device).
  ///
  /// Uses a long timeout since the user needs to enter their PIN.
  /// Returns the handshake data for the PIN server relay.
  Future<dynamic> authUser({required String network}) async {
    return await call(
      'auth_user',
      params: {'network': network},
      timeout: const Duration(seconds: 120),
    );
  }

  /// Get an extended public key for a BIP32 derivation path.
  ///
  /// [network] is 'mainnet' or 'testnet'.
  /// [path] is the BIP32 path as a list of uint32 values
  /// (hardened indices have bit 31 set).
  Future<String> getXpub({
    required String network,
    required List<int> path,
  }) async {
    final result = await call('get_xpub', params: {
      'network': network,
      'path': path,
    });
    return result as String;
  }

  /// Get a receive address for a BIP32 derivation path.
  ///
  /// Displays the address on the Jade screen for user verification.
  /// [variant] is the address type: 'pkh' (legacy), 'sh(wpkh)' (nested segwit),
  /// 'wpkh' (native segwit), or 'tr' (taproot).
  Future<String> getReceiveAddress({
    required String network,
    required List<int> path,
    required String variant,
  }) async {
    final result = await call(
      'get_receive_address',
      params: {
        'network': network,
        'path': path,
        'variant': variant,
      },
      timeout: const Duration(seconds: 30),
    );
    return result as String;
  }

  /// Get the master blinding key (for Liquid, future use).
  Future<Uint8List> getMasterBlindingKey({required String network}) async {
    final result = await call('get_master_blinding_key', params: {
      'network': network,
    });
    return result as Uint8List;
  }

  /// Sign a PSBT on the Jade device.
  ///
  /// Sends the raw PSBT bytes to Jade. For large PSBTs, handles the
  /// multi-part data exchange protocol where `seqnum`/`seqlen` fields
  /// appear at the response envelope level.
  Future<Uint8List> signPsbt({
    required Uint8List psbtBytes,
    required String network,
  }) async {
    final id = _nextId();
    final request = <String, dynamic>{
      'id': id,
      'method': 'sign_psbt',
      'params': {
        'network': network,
        'psbt': psbtBytes,
      },
    };

    final response =
        await callRaw(request, timeout: const Duration(seconds: 120));
    final sequence = response['seqnum'];
    final total = response['seqlen'];
    if (sequence == null && total == null) {
      return _responseBytes(response['result']);
    }
    if (sequence != 1 || total is! int || total < 1) {
      throw _invalidResponse();
    }
    return _collectExtendedData(response, total);
  }

  Future<Uint8List> _collectExtendedData(
      Map<String, dynamic> initial, int total) async {
    final parts = BytesBuilder(copy: false)
      ..add(_responseBytes(initial['result']));
    final origId = initial['id'];

    // Jade numbers reply chunks from one. The first reply is already present;
    // request its successor through the final chunk, inclusively (jadepy).
    for (var sequence = 2; sequence <= total; sequence++) {
      final response = await callRaw({
        'id': _nextId(),
        'method': 'get_extended_data',
        'params': {
          'origid': origId,
          'orig': 'sign_psbt',
          'seqnum': sequence,
          'seqlen': total,
        },
      }, timeout: const Duration(seconds: 30));
      if (response['seqnum'] != sequence || response['seqlen'] != total) {
        throw _invalidResponse();
      }
      parts.add(_responseBytes(response['result']));
    }
    return parts.takeBytes();
  }

  /// Ping the device to check connectivity.
  Future<bool> ping() async {
    try {
      final result = await call('ping', timeout: const Duration(seconds: 5));
      return result == 0 || result == true;
    } catch (_) {
      return false;
    }
  }

  /// Sign an arbitrary message with a key at the given path.
  Future<Uint8List> signMessage({
    required String message,
    required List<int> path,
    String aeScriptPath = '',
  }) async {
    final result = await call('sign_message', params: {
      'message': message,
      'path': path,
      'ae_host_commitment': Uint8List(32),
    });
    return result as Uint8List;
  }

  /// Parse a BIP32 derivation path string into Jade's uint32 array format.
  ///
  /// Example: `m/84'/0'/0'` → `[0x80000054, 0x80000000, 0x80000000]`
  /// Hardened indices (marked with `'` or `h`) have bit 31 set (0x80000000).
  static List<int> parseBip32Path(String path) {
    final components = path
        .replaceAll('m/', '')
        .replaceAll('m', '')
        .split('/')
        .where((s) => s.isNotEmpty);

    return components.map((component) {
      final hardened = component.endsWith("'") || component.endsWith('h');
      final indexStr = component.replaceAll("'", '').replaceAll('h', '');
      final index = int.parse(indexStr);
      return hardened ? (index | 0x80000000) : index;
    }).toList();
  }
}
