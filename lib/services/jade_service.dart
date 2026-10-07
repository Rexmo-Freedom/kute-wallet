import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:kute/models/add_wallet_model.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:universal_ble/universal_ble.dart';

import 'bluetooth/ble_scan_coordinator.dart';

import 'jade_ble_transport.dart';
import 'jade_pin_auth.dart';
import 'jade_rpc.dart';

/// Minimal representation of a discovered Jade BLE device.
class JadeBleDevice {
  final String id;
  final String name;

  const JadeBleDevice({required this.id, required this.name});
}

/// State representing a Jade device connection.
class JadeConnectionState {
  final bool isConnected;
  final bool isScanning;
  final bool isAuthenticated;
  final bool isAuthenticating;
  final List<JadeBleDevice> foundDevices;
  final String? deviceName;
  final String? errorMessage;
  final String? firmwareVersion;

  const JadeConnectionState({
    this.isConnected = false,
    this.isScanning = false,
    this.isAuthenticated = false,
    this.isAuthenticating = false,
    this.foundDevices = const [],
    this.deviceName,
    this.errorMessage,
    this.firmwareVersion,
  });

  JadeConnectionState copyWith({
    bool? isConnected,
    bool? isScanning,
    bool? isAuthenticated,
    bool? isAuthenticating,
    List<JadeBleDevice>? foundDevices,
    String? deviceName,
    String? errorMessage,
    String? firmwareVersion,
  }) {
    return JadeConnectionState(
      isConnected: isConnected ?? this.isConnected,
      isScanning: isScanning ?? this.isScanning,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isAuthenticating: isAuthenticating ?? this.isAuthenticating,
      foundDevices: foundDevices ?? this.foundDevices,
      deviceName: deviceName ?? this.deviceName,
      errorMessage: errorMessage ?? this.errorMessage,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
    );
  }
}

/// Service for Blockstream Jade hardware wallet communication via BLE.
///
/// Follows the same StateNotifier + Riverpod pattern as [LedgerService].
/// Manages the full lifecycle: BLE scanning, connection, PIN authentication,
/// xpub retrieval, and PSBT signing.
class JadeService extends StateNotifier<JadeConnectionState> {
  JadeService() : super(const JadeConnectionState());

  JadeBleTransport? _transport;
  JadeRpc? _rpc;
  JadePinAuth? _pinAuth;
  Timer? _scanTimer;
  StreamSubscription<BleDevice>? _scanSubscription;
  BleScanLease? _scanLease;
  int _scanGeneration = 0;
  int _connectionGeneration = 0;
  bool _connectingDevice = false;

  static bool get isBluetoothAvailable => Platform.isAndroid || Platform.isIOS;

  /// Jade's reference client identifies advertisements by their Jade name prefix.
  /// The UART service and characteristics are verified after selection.
  static JadeBleDevice? deviceFromAdvertisement(BleDevice advertisement) {
    final name = advertisement.name?.trim() ?? '';
    if (!name.toLowerCase().startsWith('jade')) return null;
    return JadeBleDevice(id: advertisement.deviceId, name: name);
  }

  Future<void> startScan() async {
    final generation = ++_scanGeneration;
    await _stopOwnedScan(generation);
    if (!mounted || generation != _scanGeneration) return;
    state = const JadeConnectionState(isScanning: true);
    BleScanLease? lease;
    try {
      // Upstream handles both modern Bluetooth permissions and location on
      // Android versions below 12, plus CoreBluetooth authorization on iOS.
      await UniversalBle.requestPermissions();
      if (!mounted || generation != _scanGeneration) return;
      final availability = await UniversalBle.getBluetoothAvailabilityState();
      if (!mounted || generation != _scanGeneration) return;
      if (availability == AvailabilityState.unauthorized) {
        throw Exception(
            'Bluetooth permission denied. Please enable it in Settings.');
      }
      if (availability != AvailabilityState.poweredOn) {
        throw Exception(
            'Bluetooth is unavailable. Please turn on Bluetooth and try again.');
      }
      lease = BleScanCoordinator.instance.acquire();
      _scanLease = lease;
      final currentLease = lease;
      _scanSubscription = UniversalBle.scanStream.listen((advertisement) {
        if (!mounted ||
            generation != _scanGeneration ||
            !currentLease.isCurrent) {
          return;
        }
        final device = deviceFromAdvertisement(advertisement);
        if (device == null) return;
        final duplicate = state.foundDevices
            .any((found) => found.id.toLowerCase() == device.id.toLowerCase());
        if (!duplicate) {
          state = state.copyWith(foundDevices: [...state.foundDevices, device]);
        }
      }, onError: (Object error) {
        if (!mounted ||
            generation != _scanGeneration ||
            !currentLease.isCurrent) {
          return;
        }
        unawaited(stopScan());
        state = state.copyWith(
            isScanning: false,
            errorMessage: 'Bluetooth scan failed. Please try again.');
      });
      final started = await BleScanCoordinator.instance.start(
          currentLease,
          () => UniversalBle.startScan(
              platformConfig: PlatformConfig(
                  android: AndroidOptions(
                      legacy: true, scanMode: AndroidScanMode.lowLatency))));
      if (!mounted ||
          generation != _scanGeneration ||
          !currentLease.isCurrent ||
          !started) {
        return;
      }
      _scanTimer = Timer(const Duration(seconds: 60), () {
        if (mounted &&
            generation == _scanGeneration &&
            currentLease.isCurrent) {
          unawaited(stopScan());
        }
      });
    } catch (error) {
      if (generation != _scanGeneration || !mounted) return;
      await _stopOwnedScan(generation);
      if (mounted && generation == _scanGeneration) {
        state = JadeConnectionState(
            errorMessage: _interpretError(error.toString()));
      }
    }
  }

  Future<void> stopScan() => _stopOwnedScan(++_scanGeneration);

  Future<void> _stopOwnedScan(int generation) async {
    _scanTimer?.cancel();
    _scanTimer = null;
    final subscription = _scanSubscription;
    _scanSubscription = null;
    final lease = _scanLease;
    _scanLease = null;
    await subscription?.cancel();
    if (lease != null) {
      try {
        await BleScanCoordinator.instance.stop(lease);
      } catch (_) {}
    }
    if (mounted && generation == _scanGeneration && state.isScanning) {
      state = state.copyWith(isScanning: false);
    }
  }

  Future<bool> connectToDevice(JadeBleDevice device) async {
    if (!mounted || _connectingDevice) return false;
    _connectingDevice = true;
    final generation = ++_connectionGeneration;
    try {
      return await _connectToDevice(device, generation);
    } finally {
      _connectingDevice = false;
    }
  }

  Future<bool> _connectToDevice(JadeBleDevice device, int generation) async {
    await _cleanup();
    if (!mounted || generation != _connectionGeneration) return false;
    state = state.copyWith(isScanning: false, foundDevices: const []);
    late final JadeBleTransport transport;
    transport = JadeBleTransport(onDisconnected: () {
      if (!mounted || !identical(_transport, transport)) return;
      _rpc = null;
      _pinAuth?.dispose();
      _pinAuth = null;
      state = const JadeConnectionState(
          errorMessage: 'Jade disconnected. Please reconnect and try again.');
    });
    _transport = transport;
    try {
      await transport.connect(device.id);
      if (!mounted ||
          generation != _connectionGeneration ||
          !identical(_transport, transport)) {
        await transport.disconnect();
        return false;
      }
      final rpc = JadeRpc(transport);
      _rpc = rpc;
      _pinAuth = JadePinAuth(rpc);
      final versionInfo = await rpc.getVersionInfo();
      if (!mounted ||
          generation != _connectionGeneration ||
          !identical(_transport, transport) ||
          !transport.isConnected) {
        return false;
      }
      state = JadeConnectionState(
        isConnected: true,
        deviceName: device.name,
        firmwareVersion: versionInfo['JADE_VERSION']?.toString() ?? 'unknown',
      );
      return true;
    } catch (error) {
      if (generation == _connectionGeneration &&
          identical(_transport, transport)) {
        await _cleanup();
        if (mounted && generation == _connectionGeneration) {
          state = JadeConnectionState(
              errorMessage: _interpretError(error.toString()));
        }
      }
      return false;
    }
  }

  Future<bool> authenticate({String network = 'mainnet'}) async {
    if (!mounted || !state.isConnected || _pinAuth == null) return false;

    state = state.copyWith(isAuthenticating: true);

    try {
      final auth = _pinAuth!;
      final success = await auth.authenticate(network: network);
      if (!mounted || !identical(_pinAuth, auth) || !state.isConnected) {
        return false;
      }

      if (success) {
        state = state.copyWith(
          isAuthenticated: true,
          isAuthenticating: false,
        );
      } else {
        state = state.copyWith(
          isAuthenticating: false,
          errorMessage: 'PIN authentication failed. Please try again.',
        );
      }
      return success;
    } catch (e) {
      if (!mounted) return false;
      state = state.copyWith(
        isAuthenticating: false,
        errorMessage: _interpretError(e.toString()),
      );
      return false;
    }
  }

  Future<String?> getXpub({String derivationPath = "m/84'/0'/0'"}) async {
    if (!mounted ||
        !state.isConnected ||
        !state.isAuthenticated ||
        _rpc == null) {
      return null;
    }

    try {
      final path = JadeRpc.parseBip32Path(derivationPath);
      final xpub = await _rpc!.getXpub(network: 'mainnet', path: path);
      return _convertKeyPrefix(xpub, derivationPath);
    } catch (e) {
      if (mounted) {
        state = state.copyWith(errorMessage: _interpretError(e.toString()));
      }
      return null;
    }
  }

  Future<Map<BitcoinAddressType, String>> scanAllAddressTypes({
    void Function(int completed, int total)? onProgress,
  }) async {
    if (!mounted ||
        !state.isConnected ||
        !state.isAuthenticated ||
        _rpc == null) {
      return {};
    }

    final results = <BitcoinAddressType, String>{};
    final types = BitcoinAddressType.values;

    for (var i = 0; i < types.length; i++) {
      if (!mounted || !state.isConnected) break;
      onProgress?.call(i, types.length);
      try {
        final xpub = await getXpub(derivationPath: types[i].derivationPath);
        if (xpub != null && xpub.isNotEmpty) {
          results[types[i]] = xpub;
        }
      } catch (_) {
        // intentionally empty
      }
    }
    if (mounted) onProgress?.call(types.length, types.length);
    return results;
  }

  Future<String?> getMasterFingerprint() async {
    if (!mounted ||
        !state.isConnected ||
        !state.isAuthenticated ||
        _rpc == null) {
      return null;
    }

    try {
      final childXpub = await _rpc!.getXpub(
        network: 'mainnet',
        path: [0x80000054],
      );

      final rawBytes = _base58Decode(childXpub);
      if (rawBytes.length < 78) return null;

      final fingerprint = rawBytes
          .sublist(5, 9)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();

      return fingerprint;
    } catch (e) {
      return null;
    }
  }

  Future<String?> verifyReceiveAddress({
    required String? scriptType,
    required int addressIndex,
    int change = 0,
  }) async {
    if (!mounted ||
        !state.isConnected ||
        !state.isAuthenticated ||
        _rpc == null) {
      return null;
    }

    try {
      final derivationPath = _derivationPathForScriptType(scriptType);
      final basePath = JadeRpc.parseBip32Path(derivationPath);
      final fullPath = [...basePath, change, addressIndex];
      final variant = _variantForScriptType(scriptType);

      final address = await _rpc!.getReceiveAddress(
        network: 'mainnet',
        path: fullPath,
        variant: variant,
      );
      return address;
    } catch (e) {
      if (mounted) {
        state = state.copyWith(errorMessage: _interpretError(e.toString()));
      }
      return null;
    }
  }

  static String _variantForScriptType(String? scriptType) {
    switch (scriptType) {
      case 'bip49':
        return 'sh(wpkh(k))';
      case 'bip86':
        return 'tr(k)';
      case 'bip44':
        return 'pkh(k)';
      default: // bip84 or null
        return 'wpkh(k)';
    }
  }

  static String _derivationPathForScriptType(String? scriptType) {
    switch (scriptType) {
      case 'bip49':
        return "m/49'/0'/0'";
      case 'bip86':
        return "m/86'/0'/0'";
      case 'bip44':
        return "m/44'/0'/0'";
      default: // bip84 or null
        return "m/84'/0'/0'";
    }
  }

  Future<String?> signPsbt(
    String psbtBase64, {
    String? scriptType,
  }) async {
    if (!mounted) return null;
    if (!state.isConnected || !state.isAuthenticated || _rpc == null) {
      state =
          state.copyWith(errorMessage: 'Jade not connected or authenticated');
      return null;
    }

    try {
      final psbtBytes = base64Decode(psbtBase64);

      final signedPsbtBytes = await _rpc!.signPsbt(
        psbtBytes: Uint8List.fromList(psbtBytes),
        network: 'mainnet',
      );

      return base64Encode(signedPsbtBytes);
    } catch (e) {
      if (mounted) {
        state = state.copyWith(errorMessage: _interpretError(e.toString()));
      }
      return null;
    }
  }

  Future<void> disconnect() async {
    final generation = ++_connectionGeneration;
    await _cleanup();
    if (mounted && generation == _connectionGeneration) {
      state = const JadeConnectionState();
    }
  }

  Future<void> _cleanup() async {
    final auth = _pinAuth;
    _pinAuth = null;
    _rpc = null;
    final transport = _transport;
    _transport = null;
    auth?.dispose();
    await stopScan();
    await transport?.disconnect();
  }

  String _convertKeyPrefix(String key, String derivationPath) {
    final List<int> targetVersion;
    if (derivationPath.startsWith("m/49'")) {
      targetVersion = [0x04, 0x9D, 0x7C, 0xB2];
    } else if (derivationPath.startsWith("m/44'") ||
        derivationPath.startsWith("m/86'")) {
      targetVersion = [0x04, 0x88, 0xB2, 0x1E];
    } else {
      targetVersion = [0x04, 0xB2, 0x47, 0x46];
    }

    final rawBytes = _base58Decode(key);
    if (rawBytes.length < 5) return key;

    final currentVersion = rawBytes.sublist(0, 4);
    if (_listEquals(currentVersion, targetVersion)) return key;

    for (int i = 0; i < 4; i++) {
      rawBytes[i] = targetVersion[i];
    }
    return _base58EncodeCheck(rawBytes.sublist(0, rawBytes.length - 4));
  }

  String _interpretError(String error) {
    if (error.contains('USER_CANCELLED') || error.contains('user_cancelled')) {
      return 'Operation was cancelled on the Jade device.';
    }
    if (error.contains('BAD_PARAMS')) {
      return 'Invalid parameters sent to Jade. Please try again.';
    }
    if (error.contains('CBOR') || error.contains('cbor')) {
      return 'Communication error with Jade. Please reconnect.';
    }
    if (error.contains('NOT_LOGGED_IN') || error.contains('not_logged_in')) {
      return 'Jade is not unlocked. Please enter your PIN.';
    }
    if (error.contains('PIN') && error.contains('fail')) {
      return 'Wrong PIN entered. Note: 3 failed attempts will reset the device.';
    }
    if (error.contains('disconnected unexpectedly')) {
      return 'Jade disconnected. Please reconnect and try again.';
    }
    if (error.contains('Nordic UART')) {
      return 'Device is not a Blockstream Jade. Please check your device.';
    }
    if (error.contains('TimeoutException') || error.contains('scan_timeout')) {
      return 'No Jade found. Please check:\n'
          '1. Jade is powered on\n'
          '2. Bluetooth is enabled on Jade and your phone\n\n'
          'Tip: You can also use QR Mode to scan your xpub.';
    }
    if (error.contains('Cannot reach Blockstream PIN server')) {
      return 'Cannot reach PIN server. Check your internet or use QR Mode.';
    }
    if (error.contains('Bluetooth permission')) {
      return error.replaceFirst('Exception: ', '');
    }
    if (error.startsWith('Exception: ')) {
      return error.substring(11);
    }
    return error;
  }

  static const String _base58Alphabet =
      "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Uint8List _base58Decode(String input) {
    if (input.isEmpty) return Uint8List(0);
    BigInt intData = BigInt.zero;
    for (int i = 0; i < input.length; i++) {
      final digit = _base58Alphabet.indexOf(input[i]);
      if (digit == -1) return Uint8List(0);
      intData = intData * BigInt.from(58) + BigInt.from(digit);
    }
    final bytes = _bigIntToBytes(intData);
    int leadingZeros = 0;
    for (int i = 0; i < input.length; i++) {
      if (input[i] == '1') {
        leadingZeros++;
      } else {
        break;
      }
    }
    final result = Uint8List(leadingZeros + bytes.length);
    for (int i = 0; i < bytes.length; i++) {
      result[leadingZeros + i] = bytes[i];
    }
    return result;
  }

  String _base58EncodeCheck(List<int> payload) {
    final hash1 = sha256.convert(payload).bytes;
    final hash2 = sha256.convert(hash1).bytes;
    final checksum = hash2.sublist(0, 4);
    final fullBytes = [...payload, ...checksum];

    BigInt intData = BigInt.zero;
    for (final byte in fullBytes) {
      intData = intData * BigInt.from(256) + BigInt.from(byte);
    }

    String result = "";
    while (intData > BigInt.zero) {
      final remainder = intData % BigInt.from(58);
      intData = intData ~/ BigInt.from(58);
      result = _base58Alphabet[remainder.toInt()] + result;
    }

    for (final byte in fullBytes) {
      if (byte == 0) {
        result = "1$result";
      } else {
        break;
      }
    }

    return result;
  }

  Uint8List _bigIntToBytes(BigInt number) {
    if (number == BigInt.zero) return Uint8List(0);
    String hex = number.toRadixString(16);
    if (hex.length % 2 != 0) hex = '0$hex';
    final len = hex.length ~/ 2;
    final bytes = Uint8List(len);
    for (int i = 0; i < len; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  @override
  void dispose() {
    ++_connectionGeneration;
    unawaited(_cleanup());
    super.dispose();
  }
}

/// Riverpod provider for the Jade service.
final jadeServiceProvider =
    StateNotifierProvider<JadeService, JadeConnectionState>((ref) {
  return JadeService();
});
