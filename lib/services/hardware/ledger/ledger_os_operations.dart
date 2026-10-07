// lib/services/hardware/ledger/ledger_os_operations.dart
//
// One APDU frame per LedgerRawOperation, with our own status word check,
// plus the dashboard commands used to switch apps:
//   GET_APP_AND_VERSION  B0 01 00 00
//   QUIT_APP             B0 A7 00 00
//   OPEN_APP             E0 D8 00 00 <app name>  (generalized from the
//                        old LedgerService.openBitcoinApp)
//
// Multi-frame commands are sent as separate operations by the caller:
// the BLE gateway completes one pending request per response, so a raw
// operation that writes several frames is unsafe over BLE.

import 'dart:convert';
import 'dart:typed_data';

import 'package:kute/services/hardware/ledger/ledger_failure.dart';
import 'package:ledger_flutter_plus/ledger_flutter_plus_dart.dart'
    show ByteDataReader, ByteDataWriter, LedgerRawOperation;

/// One command APDU: CLA INS P1 P2 Lc data.
class LedgerApdu {
  LedgerApdu(this.cla, this.ins, this.p1, this.p2, [List<int>? data])
      : data = Uint8List.fromList(data ?? const []) {
    if (this.data.length > 255) {
      throw ArgumentError('APDU data must be 255 bytes or fewer');
    }
  }

  final int cla;
  final int ins;
  final int p1;
  final int p2;
  final Uint8List data;

  Uint8List toBytes() =>
      Uint8List.fromList([cla, ins, p1, p2, data.length, ...data]);

  String toHex() => toBytes()
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();

  @override
  String toString() => 'LedgerApdu(${toHex()})';
}

/// Splits a response into payload and status word; throws
/// [LedgerStatusException] for anything but 0x9000.
Uint8List ledgerResponsePayload(Uint8List response) {
  if (response.length < 2) {
    throw const LedgerStatusException(0x0000);
  }
  final sw = (response[response.length - 2] << 8) | response.last;
  if (sw != 0x9000) throw LedgerStatusException(sw);
  return Uint8List.fromList(response.sublist(0, response.length - 2));
}

class LedgerApduOperation extends LedgerRawOperation<Uint8List> {
  LedgerApduOperation(this.apdu);

  final LedgerApdu apdu;

  @override
  Future<List<Uint8List>> write(ByteDataWriter writer) async {
    writer.write(apdu.toBytes());
    return [writer.toBytes()];
  }

  @override
  Future<Uint8List> read(ByteDataReader reader) async =>
      ledgerResponsePayload(reader.read(reader.remainingLength));
}

/// Name the Ledger OS reports while the dashboard is showing.
const String kLedgerDashboardName = 'BOLOS';

class LedgerRunningApp {
  const LedgerRunningApp({required this.name, required this.version});
  final String name;
  final String version;

  bool get isDashboard => name == kLedgerDashboardName;

  bool isApp(LedgerAppId app) => name == app.deviceName;
}

LedgerApdu getAppAndVersionApdu() => LedgerApdu(0xB0, 0x01, 0x00, 0x00);

LedgerApdu quitAppApdu() => LedgerApdu(0xB0, 0xA7, 0x00, 0x00);

LedgerApdu openAppApdu(String appName) =>
    LedgerApdu(0xE0, 0xD8, 0x00, 0x00, utf8.encode(appName));

/// Response: format(1)=0x01 | nameLen | name | versionLen | version
/// [| flagsLen | flags].
LedgerRunningApp parseAppAndVersion(Uint8List payload) {
  if (payload.length < 3 || payload[0] != 0x01) {
    throw const FormatException('Unexpected GET_APP_AND_VERSION format');
  }
  var i = 1;
  final nameLen = payload[i++];
  if (i + nameLen >= payload.length) {
    throw const FormatException('Truncated app name');
  }
  final name = ascii.decode(payload.sublist(i, i + nameLen));
  i += nameLen;
  final versionLen = payload[i++];
  if (i + versionLen > payload.length) {
    throw const FormatException('Truncated app version');
  }
  final version = ascii.decode(payload.sublist(i, i + versionLen));
  return LedgerRunningApp(name: name, version: version);
}

/// A dotted app version, compared numerically.
class LedgerSemver implements Comparable<LedgerSemver> {
  const LedgerSemver(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  static LedgerSemver? tryParse(String text) {
    final m = RegExp(r'^(\d+)\.(\d+)\.(\d+)').firstMatch(text.trim());
    if (m == null) return null;
    return LedgerSemver(
        int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
  }

  @override
  int compareTo(LedgerSemver other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  bool operator <(LedgerSemver other) => compareTo(other) < 0;

  @override
  bool operator ==(Object other) =>
      other is LedgerSemver && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}
