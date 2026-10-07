import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:kute/models/add_wallet_model.dart';
import 'package:kute/services/bluetooth/ble_scan_coordinator.dart';
import 'package:kute/services/hardware/ledger/ledger_device_session.dart';
import 'package:kute/services/hardware/ledger/ledger_failure.dart';
import 'package:kute/services/hardware/ledger/ledger_os_operations.dart';
import 'package:kute/services/ledger/ledger_device_discovery.dart';
import 'package:kute/services/onchain/native_bitcoin_primitives.dart';
import 'package:convert/convert.dart' as convert;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ledger_bitcoin/ledger_bitcoin.dart';
// ignore: implementation_imports
import 'package:ledger_bitcoin/src/psbt/constants.dart';
// ignore: implementation_imports
import 'package:ledger_bitcoin/src/psbt/map_extension.dart';
// ignore: implementation_imports
import 'package:ledger_bitcoin/src/utils/buffer_reader.dart';

/// Supported Ledger connection types.
enum LedgerConnectionType { bluetooth, usb }

/// Builds a Bitcoin app client for a connection, script type and path.
/// Injectable so PSBT and fingerprint flows can be tested without a device.
typedef BitcoinLedgerAppFactory = BitcoinLedgerApp Function(
    LedgerConnection connection, String? scriptType, String derivationPath);

/// State representing a Ledger device connection.
class LedgerConnectionState {
  final bool isConnected;
  final bool isScanning;
  final List<LedgerDevice> foundDevices;
  final String? deviceName;

  /// Typed failure of the last operation. The UI maps it to l10n through
  /// `ledgerFailureMessage`; the service never returns English strings.
  final LedgerFailure? failure;
  final LedgerConnectionType? connectionType;

  const LedgerConnectionState({
    this.isConnected = false,
    this.isScanning = false,
    this.foundDevices = const [],
    this.deviceName,
    this.failure,
    this.connectionType,
  });

  LedgerConnectionState copyWith({
    bool? isConnected,
    bool? isScanning,
    List<LedgerDevice>? foundDevices,
    String? deviceName,
    LedgerFailure? failure,
    bool clearFailure = false,
    LedgerConnectionType? connectionType,
  }) {
    return LedgerConnectionState(
      isConnected: isConnected ?? this.isConnected,
      isScanning: isScanning ?? this.isScanning,
      foundDevices: foundDevices ?? this.foundDevices,
      deviceName: deviceName ?? this.deviceName,
      failure: clearFailure ? null : (failure ?? this.failure),
      connectionType: connectionType ?? this.connectionType,
    );
  }
}

/// Service for Ledger hardware wallet communication.
///
/// Based on SatoshiPortal/bullbitcoin-mobile implementation.
/// Uses ledger_bitcoin & ledger_flutter_plus for BLE/USB connection and PSBT signing.
class LedgerService extends StateNotifier<LedgerConnectionState> {
  LedgerService({
    Future<LedgerConnection> Function(LedgerDevice)? connectDevice,
    Future<LedgerDeviceType?> Function(String)? detectDeviceType,
    Future<void> Function(String)? disconnectBle,
    BitcoinLedgerAppFactory? bitcoinAppFactory,
    Future<PsbtV2> Function(Uint8List psbtV0)? psbtV0Reader,
  })  : _connectDeviceOverride = connectDevice,
        _detectDeviceTypeOverride = detectDeviceType,
        _disconnectBle = disconnectBle ?? UniversalBle.disconnect,
        _bitcoinApp = bitcoinAppFactory ?? defaultBitcoinLedgerApp,
        _psbtV0ReaderOverride = psbtV0Reader,
        super(const LedgerConnectionState());

  final Future<LedgerConnection> Function(LedgerDevice)? _connectDeviceOverride;
  final Future<LedgerDeviceType?> Function(String)? _detectDeviceTypeOverride;
  final Future<void> Function(String) _disconnectBle;
  final BitcoinLedgerAppFactory _bitcoinApp;
  final Future<PsbtV2> Function(Uint8List psbtV0)? _psbtV0ReaderOverride;

  LedgerInterface? _ledgerBle;
  LedgerInterface? _ledgerUsb;
  LedgerConnection? _connection;
  LedgerDeviceSession? _session;

  /// Builds the Bitcoin app client for a script type and derivation path.
  static BitcoinLedgerApp defaultBitcoinLedgerApp(
    LedgerConnection connection,
    String? scriptType,
    String derivationPath,
  ) {
    switch (scriptType) {
      case 'bip49':
        return BitcoinLedgerApp.nestedSegwit(connection,
            derivationPath: derivationPath);
      case 'bip86':
        return BitcoinLedgerApp.taproot(connection,
            derivationPath: derivationPath);
      case 'bip44':
        return BitcoinLedgerApp.legacy(connection,
            derivationPath: derivationPath);
      default: // bip84 or null
        return BitcoinLedgerApp.nativeSegwit(connection,
            derivationPath: derivationPath);
    }
  }

  static String? _scriptTypeForPath(String derivationPath) {
    if (derivationPath.startsWith("m/49'")) return 'bip49';
    if (derivationPath.startsWith("m/86'")) return 'bip86';
    if (derivationPath.startsWith("m/44'")) return 'bip44';
    return 'bip84';
  }

  /// The serialized device session over the current connection, or null
  /// when no Ledger is connected. A reconnect inside the session goes
  /// through [connectToDevice] and must return the same device ID.
  LedgerDeviceSession? get deviceSession {
    final connection = _connection;
    if (!state.isConnected || connection == null) return null;
    final existing = _session;
    if (existing != null && identical(existing.connection, connection)) {
      return existing;
    }
    return _session = LedgerDeviceSession(
      connection: connection,
      reconnect: _reconnectForSession,
    );
  }

  Future<LedgerConnection> _reconnectForSession(LedgerDevice device) async {
    final connected = await connectToDevice(device);
    final connection = _connection;
    if (!connected || connection == null) {
      throw const LedgerFailure(LedgerFailureCode.disconnected);
    }
    return connection;
  }
  StreamSubscription<BleDevice>? _bleScanSubscription;
  StreamSubscription<LedgerDevice>? _usbScanSubscription;
  Timer? _rawScanTimer;
  int _scanGeneration = 0;
  int _connectionGeneration = 0;
  Future<void> _connectionTail = Future.value();
  BleScanLease? _scanLease;

  static bool get isUsbAvailable => Platform.isAndroid;
  static bool get isBluetoothAvailable => Platform.isAndroid || Platform.isIOS;

  /// Start scanning for Ledger devices.
  ///
  /// Found devices accumulate in [state.foundDevices]. The scan runs until
  /// [stopScan] is called or [maxScanDuration] expires (60s).
  Future<void> startScan(LedgerConnectionType type) async {
    final connectionGeneration = ++_connectionGeneration;
    final generation = _scanGeneration + 1;
    await stopScan();
    if (!_ownsConnection(connectionGeneration) || generation != _scanGeneration) return;
    await _connectionTail;
    if (!_ownsConnection(connectionGeneration) || generation != _scanGeneration) return;
    await _disconnectOnly();
    if (!_ownsConnection(connectionGeneration) || generation != _scanGeneration) return;

    state = const LedgerConnectionState(isScanning: true);

    try {
      final needsBluetooth = type == LedgerConnectionType.bluetooth;

      if (needsBluetooth) {
        await _requestBluetoothPermissions();

        try {
          final bleState = await UniversalBle.getBluetoothAvailabilityState();
          if (bleState == AvailabilityState.unauthorized) {
            throw Exception(
                'Bluetooth permission denied. Please go to Settings > Kute. and enable Bluetooth.');
          }
          if (bleState != AvailabilityState.poweredOn) {
          }
        } catch (e) {
          if (e.toString().contains('Bluetooth permission denied')) rethrow;
        }

        if (!_isCurrentScan(generation)) return;
        _ledgerBle = LedgerInterface.ble(
          onPermissionRequest: (_) async {
            await _requestBluetoothPermissions();
            return true;
          },
          bleOptions: BluetoothOptions(
            maxScanDuration: const Duration(seconds: 60),
          ),
        );
      }

      if (isUsbAvailable && type == LedgerConnectionType.usb) {
        _ledgerUsb = LedgerInterface.usb();
      }

      if (!_isCurrentScan(generation)) return;
      if (_ledgerBle != null) {
        final lease = BleScanCoordinator.instance.acquire();
        _scanLease = lease;
        _bleScanSubscription = UniversalBle.scanStream.listen((bleDevice) {
          if (!_isCurrentScan(generation) || !lease.isCurrent) return;
          if (!LedgerDeviceDiscovery.isCandidate(
              name: bleDevice.name, services: bleDevice.services)) {
            return;
          }
          final name = bleDevice.name?.trim() ?? '';

          final deviceId = bleDevice.deviceId;

          final alreadyFound =
              state.foundDevices.any((d) => d.id == deviceId);
          if (!alreadyFound) {
            // Name-only advertisements need a provisional enum value for the
            // SDK's device DTO. Connection always verifies the actual service.
            final deviceType = LedgerDeviceDiscovery.modelForServices(
                bleDevice.services) ?? LedgerDeviceType.nanoX;

            final device = LedgerDevice.ble(
              id: deviceId,
              name: name.isEmpty ? 'Ledger' : name,
              deviceInfo: deviceType,
              rssi: bleDevice.rssi ?? 0,
            );
            state = state.copyWith(
              foundDevices: [...state.foundDevices, device],
            );
          }
        });

        final started = await BleScanCoordinator.instance.start(
            lease, () => UniversalBle.startScan());
        if (!started || !_isCurrentScan(generation) || !lease.isCurrent) {
          if (_isCurrentScan(generation)) await stopScan();
          return;
        }

        _rawScanTimer = Timer(const Duration(seconds: 60), () {
          if (_isCurrentScan(generation)) unawaited(stopScan());
        });
      }

      if (_ledgerUsb != null) {
        _usbScanSubscription = _ledgerUsb!.scan().listen(
          (device) {
            if (!_isCurrentScan(generation)) return;
            final alreadyFound = state.foundDevices.any((d) => d.id == device.id);
            if (!alreadyFound) {
              state = state.copyWith(
                foundDevices: [...state.foundDevices, device],
              );
            }
          },
          onError: (e) {},
          onDone: () {
            if (_isCurrentScan(generation) && _bleScanSubscription == null) {
              state = state.copyWith(isScanning: false);
            }
          },
        );
      }

      if (needsBluetooth) {
        unawaited(_checkSystemDevices(generation));
      }
    } catch (e) {
      if (!_isCurrentScan(generation)) return;
      await stopScan();
      if (!mounted || _scanGeneration != generation + 1) return;
      state = LedgerConnectionState(failure: LedgerFailure.from(e));
    }
  }

  bool _isCurrentScan(int generation) =>
      mounted && generation == _scanGeneration && state.isScanning;

  Future<void> _requestBluetoothPermissions() async {
    try {
      // UniversalBle selects location permissions on older Android versions.
      await UniversalBle.requestPermissions();
    } catch (_) {
      throw Exception(Platform.isIOS
          ? 'Bluetooth permission denied. Please go to Settings > Kute. and enable Bluetooth.'
          : 'Bluetooth permissions are required. Please enable them in Settings.');
    }
  }

  Future<void> _checkSystemDevices(int generation) async {
    try {
      final systemDevices = await UniversalBle.getSystemDevices(
        // Android's filtered implementation synchronously waits for service
        // discovery. Use its immediate inventory and filter candidates here.
        withServices: Platform.isAndroid
            ? const []
            : LedgerDeviceDiscovery.serviceUuids,
      );
      if (!_isCurrentScan(generation) || _scanLease?.isCurrent != true) return;
      for (final bleDevice in systemDevices) {
        if (Platform.isAndroid && !LedgerDeviceDiscovery.isCandidate(
            name: bleDevice.name, services: bleDevice.services)) {
          continue;
        }
        final reportedName = bleDevice.name?.trim() ?? '';
        final name = reportedName.isEmpty ? 'Ledger' : reportedName;

        final deviceType = LedgerDeviceDiscovery.modelForServices(
            bleDevice.services) ?? LedgerDeviceType.nanoX;

        final device = LedgerDevice.ble(
          id: bleDevice.deviceId,
          name: name,
          deviceInfo: deviceType,
        );

        final alreadyFound = state.foundDevices.any((d) => d.id == device.id);
        if (!alreadyFound) {
          state = state.copyWith(
            foundDevices: [...state.foundDevices, device],
          );
        }
      }
    } catch (_) {
      // intentionally empty
    }
  }

  /// Stop the current scan. Keeps interfaces alive for [connectToDevice].
  Future<void> stopScan() async {
    _scanGeneration++;
    _rawScanTimer?.cancel();
    _rawScanTimer = null;
    final bleSubscription = _bleScanSubscription;
    _bleScanSubscription = null;
    final lease = _scanLease;
    _scanLease = null;
    final usbSubscription = _usbScanSubscription;
    _usbScanSubscription = null;
    if (mounted && state.isScanning) {
      state = state.copyWith(isScanning: false);
    }
    await bleSubscription?.cancel();
    if (lease != null) {
      try { await BleScanCoordinator.instance.stop(lease); } catch (_) {}
    }
    await usbSubscription?.cancel();
  }

  Future<LedgerDeviceType?> _detectDeviceType(String deviceId) =>
      LedgerDeviceDiscovery.detectConnectedModel(
        connect: () => UniversalBle.connect(deviceId),
        discoverServices: () async =>
            (await UniversalBle.discoverServices(deviceId))
                .map((service) => service.uuid),
      );

  /// Connect to a specific Ledger device (from scan results).
  Future<bool> connectToDevice(LedgerDevice device) {
    final generation = ++_connectionGeneration;
    final scanStopped = stopScan();
    final attempt = _connectionTail.then(
        (_) => _connectOwned(device, generation, scanStopped));
    _connectionTail = attempt.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return attempt;
  }

  bool _ownsConnection(int generation) =>
      mounted && generation == _connectionGeneration;

  Future<bool> _connectOwned(
      LedgerDevice device, int generation, Future<void> scanStopped) async {
    await scanStopped;
    if (!_ownsConnection(generation)) return false;
    state = state.copyWith(isScanning: false, foundDevices: const []);

    LedgerConnection? candidate;
    var attemptedBleProbe = false;
    var accepted = false;
    try {
      final LedgerInterface? ledgerInterface;
      if (device.connectionType == ConnectionType.ble) {
        ledgerInterface = _ledgerBle;
      } else {
        ledgerInterface = _ledgerUsb;
      }

      if (ledgerInterface == null && _connectDeviceOverride == null) {
        throw Exception('No matching interface for device connection type.');
      }
      final connect = _connectDeviceOverride ?? ledgerInterface!.connect;
      final previousConnection = _connection;
      _connection = null;
      await previousConnection?.disconnect();
      if (!_ownsConnection(generation)) return false;

      var correctedDevice = device;
      if (device.connectionType == ConnectionType.ble) {
        attemptedBleProbe = true;
        final detectedType = await (_detectDeviceTypeOverride ?? _detectDeviceType)(device.id);
        if (!_ownsConnection(generation)) return false;
        if (detectedType == null) {
          throw ServiceNotSupportedException(
            connectionType: ConnectionType.ble,
            message: 'Required service not supported',
          );
        }
        if (detectedType != device.deviceInfo) {
          correctedDevice = LedgerDevice.ble(
            id: device.id,
            name: device.name,
            rssi: device.rssi,
            deviceInfo: detectedType,
          );
        }
      }


      if (correctedDevice.connectionType == ConnectionType.usb) {
        for (int attempt = 0; attempt < 5; attempt++) {
          if (!_ownsConnection(generation)) return false;
          try {
            // The platform permission dialog may outlive a Dart timeout. Keep
            // ownership of the actual result so cancellation can close it.
            candidate = await connect(correctedDevice);
            break;
          } catch (e) {
            if (attempt == 4) rethrow;
            await Future.delayed(const Duration(seconds: 2));
          }
        }
      } else {
        candidate = await connect(correctedDevice);
      }

      if (!_ownsConnection(generation)) return false;
      _connection = candidate;
      accepted = true;
      state = LedgerConnectionState(
        isConnected: true,
        connectionType: device.connectionType == ConnectionType.ble
            ? LedgerConnectionType.bluetooth
            : LedgerConnectionType.usb,
        deviceName: device.name.isNotEmpty ? device.name : 'Ledger',
      );
      return true;
    } catch (e) {
      if (_ownsConnection(generation)) {
        state = LedgerConnectionState(failure: LedgerFailure.from(e));
      }
      return false;
    } finally {
      if (!accepted) {
        if (candidate != null) {
          try { await candidate.disconnect(); } catch (_) {}
        } else if (attemptedBleProbe) {
          try { await _disconnectBle(device.id); } catch (_) {}
        }
      }
    }
  }

  /// Asks the Ledger OS to open [app] (OPEN_APP, E0 D8). The device shows
  /// a confirmation prompt. Returns true when the command was accepted.
  Future<bool> openApp(LedgerAppId app) async {
    if (!state.isConnected || _connection == null) return false;

    try {
      await _connection!.sendOperation<Uint8List>(
          LedgerApduOperation(openAppApdu(app.deviceName)));
      return true;
    } catch (e) {
      // 6e01 = app already open or command not supported on current screen
      // — that's fine, callers verify with the app's own command next.
      return false;
    }
  }

  /// Send an APDU command to the Ledger OS to open the Bitcoin app.
  /// The device will show a confirmation prompt on its screen.
  Future<bool> openBitcoinApp() => openApp(LedgerAppId.bitcoin);

  static String _hexFingerprint(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Get the master fingerprint from the connected Ledger.
  Future<String?> getMasterFingerprint() async {
    if (!state.isConnected || _connection == null) return null;
    state = state.copyWith(clearFailure: true);

    try {
      final bitcoinApp = _bitcoinApp(_connection!, null, "m/84'/0'/0'/0/0");
      final fingerprint = await bitcoinApp.getMasterFingerprint();
      return _hexFingerprint(fingerprint);
    } catch (e) {
      state = state.copyWith(failure: LedgerFailure.from(e));
      return null;
    }
  }

  /// Get an xpub for a given derivation path from the connected Ledger.
  /// Uses Native SegWit (BIP84) by default. The returned key prefix is
  /// converted to match the derivation path's address type (zpub for BIP84,
  /// ypub for BIP49, xpub for BIP44) so that downstream descriptor creation
  /// uses the correct script type.
  Future<String?> getXpub({String derivationPath = "m/84'/0'/0'"}) async {
    if (!state.isConnected || _connection == null) return null;
    state = state.copyWith(clearFailure: true);

    try {
      final bitcoinApp = _bitcoinApp(
          _connection!, _scriptTypeForPath(derivationPath), derivationPath);
      final xpub = await bitcoinApp.getXPubKey(
        derivationPath: derivationPath,
        displayPublicKey: false,
      );
      return _convertKeyPrefix(xpub, derivationPath);
    } catch (e) {
      state = state.copyWith(failure: LedgerFailure.from(e));
      return null;
    }
  }

  String _convertKeyPrefix(String key, String derivationPath) {
    final List<int> targetVersion;
    if (derivationPath.startsWith("m/49'")) {
      targetVersion = [0x04, 0x9D, 0x7C, 0xB2];
    } else if (derivationPath.startsWith("m/44'") || derivationPath.startsWith("m/86'")) {
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

  /// Scan all Bitcoin address types from the connected Ledger device.
  ///
  /// Returns a map of [BitcoinAddressType] to xpub string for each
  /// successfully scanned type. Optionally calls [onProgress] with
  /// (completedCount, totalCount) for UI updates.
  Future<Map<BitcoinAddressType, String>> scanAllAddressTypes({
    void Function(int completed, int total)? onProgress,
  }) async {
    if (!state.isConnected || _connection == null) return {};

    final results = <BitcoinAddressType, String>{};
    final types = BitcoinAddressType.values;

    for (var i = 0; i < types.length; i++) {
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
    onProgress?.call(types.length, types.length);
    return results;
  }

  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static const String _base58Alphabet =
      "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

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

  /// Sign a PSBT via the connected Ledger device.
  ///
  /// Takes a base64-encoded PSBTv0 (from BDK), converts to PSBTv2 format
  /// required by the Ledger Bitcoin app, signs it, and returns the signed
  /// raw transaction hex, or null on failure.
  ///
  /// [scriptType] should match the wallet's script type: 'bip84' (native segwit),
  /// 'bip49' (nested segwit), 'bip86' (taproot), or 'bip44' (legacy).
  ///
  /// [expectedFingerprint] is the wallet's stored master fingerprint. When
  /// it is set, the device fingerprint is read first and a mismatch fails
  /// with `wrongDevice` before any PSBT reaches the device. When it is null
  /// (import can store null) signing proceeds as before. The device value
  /// is never written back to the wallet from here.
  Future<String?> signPsbt(
    String psbtBase64, {
    String? scriptType,
    String? expectedFingerprint,
  }) async {
    if (!state.isConnected || _connection == null) {
      state = state.copyWith(
          failure: const LedgerFailure(LedgerFailureCode.disconnected));
      return null;
    }
    state = state.copyWith(clearFailure: true);

    try {
      final derivationPath = _derivationPathForScriptType(scriptType);
      final bitcoinApp = _bitcoinApp(_connection!, scriptType, derivationPath);

      final masterFP = await bitcoinApp.getMasterFingerprint();
      final expected = expectedFingerprint?.trim().toLowerCase();
      if (expected != null &&
          expected.isNotEmpty &&
          _hexFingerprint(masterFP) != expected) {
        state = state.copyWith(
            failure: const LedgerFailure(LedgerFailureCode.wrongDevice));
        return null;
      }

      final psbtBytes = Uint8List.fromList(base64Decode(psbtBase64));
      final reader = _psbtV0ReaderOverride;
      final psbt =
          reader != null ? await reader(psbtBytes) : await _readPsbtV0(psbtBytes);
      _fixPsbtFingerprints(psbt, masterFP);

      final rawTxBytes = await bitcoinApp.signPsbt(psbt: psbt);
      return convert.hex.encode(rawTxBytes);
    } catch (e) {
      state = state.copyWith(failure: LedgerFailure.from(e));
      return null;
    }
  }

  Future<PsbtV2> _readPsbtV0(Uint8List bytes) async {
    final psbt = PsbtV2();
    await _deserializePsbtV0(psbt, bytes);
    return psbt;
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

  /// Verify a receive address on the Ledger device screen.
  ///
  /// Connects to the already-connected Ledger, derives the address at the
  /// given index and script type, and displays it on the device screen for
  /// the user to visually verify. Returns the address string from the Ledger
  /// for comparison, or null on failure.
  Future<String?> verifyReceiveAddress({
    required String? scriptType,
    required int addressIndex,
    int change = 0,
  }) async {
    if (!state.isConnected || _connection == null) {
      state = state.copyWith(
          failure: const LedgerFailure(LedgerFailureCode.disconnected));
      return null;
    }
    state = state.copyWith(clearFailure: true);

    try {
      final derivationPath = _derivationPathForScriptType(scriptType);
      final fullPath = "$derivationPath/$change/$addressIndex";
      final bitcoinApp = _bitcoinApp(_connection!, scriptType, fullPath);

      final addresses = await bitcoinApp.getAccounts(
        accountsDerivationPath: fullPath,
        display: true,
      );

      return addresses.isNotEmpty ? addresses.first : null;
    } catch (e) {
      state = state.copyWith(failure: LedgerFailure.from(e));
      return null;
    }
  }

  void _fixPsbtFingerprints(PsbtV2 psbt, Uint8List realFingerprint) {
    final dummyFp = Uint8List.fromList([0, 0, 0, 0]);

    final inputCount = psbt.getGlobalInputCount();
    for (var i = 0; i < inputCount; i++) {
      final pubkeys = psbt.getInputKeyDatas(i, PSBTIn.bip32Derivation);
      for (final pubkey in pubkeys) {
        final deriv = psbt.getInputBip32Derivation(i, pubkey);
        if (deriv != null) {
          final (fp, path) = deriv;
          if (listEquals(fp, dummyFp)) {
            psbt.setInputBip32Derivation(i, pubkey, realFingerprint, path);
          }
        }
      }

      final tapPubkeys = psbt.getInputKeyDatas(i, PSBTIn.tapBip32Derivation);
      for (final pubkey in tapPubkeys) {
        try {
          final (hashes, fp, path) = psbt.getInputTapBip32Derivation(i, pubkey);
          if (listEquals(fp, dummyFp)) {
            psbt.setInputTapBip32Derivation(i, pubkey, hashes, realFingerprint, path);
          }
        } catch (_) {}
      }
    }

    final outputCount = psbt.getGlobalOutputCount();
    for (var i = 0; i < outputCount; i++) {
      final outputMap = psbt.outputMaps[i];

      final outPubkeys = <Uint8List>[];
      outputMap.forEach((k, v) {
        if (k.length >= 2) {
          final keyTypeByte = int.tryParse(k.substring(0, 2), radix: 16);
          if (keyTypeByte == PSBTOut.bip32Derivation.value) {
            outPubkeys.add(Uint8List.fromList(convert.hex.decode(k.substring(2))));
          }
        }
      });
      for (final pubkey in outPubkeys) {
        try {
          final (fp, path) = psbt.getOutputBip32Derivation(i, pubkey);
          if (listEquals(fp, dummyFp)) {
            psbt.setOutputBip32Derivation(i, pubkey, realFingerprint, path);
          }
        } catch (_) {}
      }

      final tapOutPubkeys = <Uint8List>[];
      outputMap.forEach((k, v) {
        if (k.length >= 2) {
          final keyTypeByte = int.tryParse(k.substring(0, 2), radix: 16);
          if (keyTypeByte == PSBTOut.tapBip32Derivation.value) {
            tapOutPubkeys.add(Uint8List.fromList(convert.hex.decode(k.substring(2))));
          }
        }
      });
      for (final pubkey in tapOutPubkeys) {
        try {
          final (hashes, fp, path) = psbt.getOutputTapBip32Derivation(i, pubkey);
          if (listEquals(fp, dummyFp)) {
            psbt.setOutputTapBip32Derivation(i, pubkey, hashes, realFingerprint, path);
          }
        } catch (_) {}
      }
    }
  }

  /// Disconnect from the current Ledger device and tear down interfaces.
  Future<void> disconnect() async {
    _connectionGeneration++;
    final scanStopped = stopScan();
    final connectionStopped = _disconnectOnly();
    if (mounted) state = const LedgerConnectionState();
    try {
      await Future.wait([scanStopped, connectionStopped, _connectionTail]);
    } catch (_) {
      // intentionally empty
    }
  }

  Future<void> _disconnectOnly() async {
    final connection = _connection;
    _connection = null;
    _session = null;
    _ledgerBle = null;
    _ledgerUsb = null;
    try {
      await connection?.disconnect();
    } catch (_) {
      // intentionally empty
    }
  }

  // The English `_interpretError` strings were replaced by typed
  // [LedgerFailure] codes; screens map them to l10n through
  // lib/screens/ledger/ledger_failure_copy.dart.

  Future<void> _deserializePsbtV0(PsbtV2 psbt, Uint8List data) async {
    final bufferReader = BufferReader(data);

    if (!listEquals(
      bufferReader.readSlice(5),
      Uint8List.fromList([0x70, 0x73, 0x62, 0x74, 0xff]),
    )) {
      throw Exception('Invalid PSBT: bad magic bytes');
    }

    while (_readKeyPair(psbt.globalMap, bufferReader)) {}

    final bdkPsbt = await NativeBitcoinPrimitives.instance.inspectPsbt(base64Encode(data));
    final tx = bdkPsbt.extractTx();

    final unsignedTxBytes = psbt.globalMap.remove('00');
    psbt.globalMap.remove('fb');
    psbt.setGlobalPsbtVersion(2);

    int locktime = 0;
    if (unsignedTxBytes != null && unsignedTxBytes.length >= 4) {
      locktime = unsignedTxBytes[unsignedTxBytes.length - 4] |
          (unsignedTxBytes[unsignedTxBytes.length - 3] << 8) |
          (unsignedTxBytes[unsignedTxBytes.length - 2] << 16) |
          (unsignedTxBytes[unsignedTxBytes.length - 1] << 24);
    }

    psbt.setGlobalInputCount(tx.input().length);
    psbt.setGlobalOutputCount(tx.output().length);
    psbt.setGlobalTxVersion(tx.version());
    psbt.setGlobalFallbackLocktime(locktime);

    for (var i = 0; i < psbt.getGlobalInputCount(); i++) {
      psbt.inputMaps.insert(i, <String, Uint8List>{});
      while (_readKeyPair(psbt.inputMaps[i], bufferReader)) {}

      final input = tx.input()[i];
      psbt.setInputOutputIndex(i, input.previousOutput.vout);
      psbt.setInputPreviousTxId(
        i,
        Uint8List.fromList(
          convert.hex.decode(input.previousOutput.txid.toString()).reversed.toList(),
        ),
      );
      final sequence = input.sequence;
      if (sequence == null) throw const FormatException('PSBT input sequence unavailable');
      psbt.setInputSequence(i, sequence);
    }

    for (var i = 0; i < psbt.getGlobalOutputCount(); i++) {
      psbt.outputMaps.insert(i, <String, Uint8List>{});
      while (_readKeyPair(psbt.outputMaps[i], bufferReader)) {}

      final output = tx.output()[i];
      psbt.setOutputAmount(i, output.value.toSat());
      psbt.setOutputScript(i, Uint8List.fromList(convert.hex.decode(output.scriptPubkey)));
    }
  }

  bool _readKeyPair(Map<String, Uint8List> map, BufferReader bufferReader) {
    final keyLen = bufferReader.readVarInt();
    if (keyLen == 0) return false;

    final keyType = bufferReader.readUInt8();
    final keyData = bufferReader.readSlice(keyLen - 1);
    final value = bufferReader.readVarSlice();

    map.set(keyType, keyData, value);
    return true;
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}

/// Provider for the Ledger service.
final ledgerServiceProvider =
    StateNotifierProvider<LedgerService, LedgerConnectionState>((ref) {
  return LedgerService();
});
