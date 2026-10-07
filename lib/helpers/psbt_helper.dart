import 'dart:convert';
import 'package:kute/l10n/l10n.dart' show appL10n;
import 'dart:io';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class PsbtHelper {
  static void debugLogPsbtFingerprints(String psbtBase64, String label) {
    try {
      final data = base64Decode(psbtBase64);
      if (data.length < 5) return;

      int pos = 5;
      int section = 0;
      final fps = <String>[];

      while (pos < data.length) {
        final keyLen = _readCompactSize(data, pos);
        if (keyLen == null) break;
        pos += keyLen.sizeBytes;

        if (keyLen.value == 0) {
          section++;
          continue;
        }

        final keyType = data[pos];
        pos += keyLen.value;

        final valLen = _readCompactSize(data, pos);
        if (valLen == null) break;
        pos += valLen.sizeBytes;
        final valStart = pos;
        pos += valLen.value;

        if ((keyType == 0x06 || keyType == 0x02) && valLen.value >= 4 && section > 0) {
          final fp = data.sublist(valStart, valStart + 4)
              .map((b) => b.toRadixString(16).padLeft(2, '0')).join();
          final pathLen = (valLen.value - 4) ~/ 4;
          final path = <String>[];
          for (int i = 0; i < pathLen; i++) {
            final idx = data[valStart + 4 + i * 4] |
                (data[valStart + 5 + i * 4] << 8) |
                (data[valStart + 6 + i * 4] << 16) |
                (data[valStart + 7 + i * 4] << 24);
            final hardened = (idx & 0x80000000) != 0;
            path.add('${idx & 0x7FFFFFFF}${hardened ? "h" : ""}');
          }
          fps.add('section=$section type=0x${keyType.toRadixString(16)} fp=$fp path=m/${path.join("/")}');
        }
      }
    } catch (_) {
      // intentionally empty
    }
  }

  static String fixFingerprints(String psbtBase64, String? fingerprintHex) {
    // Validate HEX-ness, not just length — a non-hex 8-char value (e.g. a
    // mislabelled fingerprint like "external") would otherwise reach the
    // per-byte int.parse(radix:16) below and throw "Invalid radix-16
    // number". Mirrors BitcoinConfigModel._validFingerprint.
    if (fingerprintHex == null ||
        !RegExp(r'^[a-fA-F0-9]{8}$').hasMatch(fingerprintHex) ||
        fingerprintHex == '00000000') {
      return psbtBase64;
    }

    try {
      final data = base64Decode(psbtBase64);
      if (data.length < 5 || data[0] != 0x70 || data[1] != 0x73 ||
          data[2] != 0x62 || data[3] != 0x74 || data[4] != 0xff) {
        return psbtBase64;
      }

      final realFp = Uint8List(4);
      for (int i = 0; i < 4; i++) {
        realFp[i] = int.parse(fingerprintHex.substring(i * 2, i * 2 + 2), radix: 16);
      }

      final result = Uint8List.fromList(data);
      int pos = 5;
      int section = 0;

      while (pos < result.length) {
        final keyLen = _readCompactSize(result, pos);
        if (keyLen == null) break;
        pos += keyLen.sizeBytes;

        if (keyLen.value == 0) {
          section++;
          continue;
        }

        final keyType = result[pos];
        pos += keyLen.value;

        final valLen = _readCompactSize(result, pos);
        if (valLen == null) break;
        pos += valLen.sizeBytes;
        final valStart = pos;
        pos += valLen.value;

        if (section == 0) continue;

        if ((keyType == 0x06 || keyType == 0x02) && valLen.value >= 4) {
          if (result[valStart] != realFp[0] || result[valStart + 1] != realFp[1] ||
              result[valStart + 2] != realFp[2] || result[valStart + 3] != realFp[3]) {
            result.setRange(valStart, valStart + 4, realFp);
          }
        }
        else if ((keyType == 0x16 || keyType == 0x07) && valLen.value >= 5) {
          final numHashes = _readCompactSize(result, valStart);
          if (numHashes != null) {
            final fpOffset = valStart + numHashes.sizeBytes + (numHashes.value * 32);
            if (fpOffset + 4 <= valStart + valLen.value) {
              if (result[fpOffset] != realFp[0] || result[fpOffset + 1] != realFp[1] ||
                  result[fpOffset + 2] != realFp[2] || result[fpOffset + 3] != realFp[3]) {
                result.setRange(fpOffset, fpOffset + 4, realFp);
              }
            }
          }
        }
      }

      return base64Encode(result);
    } catch (e) {
      return psbtBase64;
    }
  }

  static _CompactSize? _readCompactSize(Uint8List data, int offset) {
    if (offset >= data.length) return null;
    final first = data[offset];
    if (first < 0xfd) return _CompactSize(first, 1);
    if (first == 0xfd && offset + 2 < data.length) {
      return _CompactSize(data[offset + 1] | (data[offset + 2] << 8), 3);
    }
    if (first == 0xfe && offset + 4 < data.length) {
      return _CompactSize(
        data[offset + 1] | (data[offset + 2] << 8) |
        (data[offset + 3] << 16) | (data[offset + 4] << 24), 5);
    }
    return null;
  }

  static Future<void> sharePsbtFile(String psbtBase64, String label) async {
    try {
      final bytes = base64Decode(psbtBase64);
      final directory = await getTemporaryDirectory();
      final safeLabel = label.replaceAll(RegExp(r'[^\w\s]+'), '');
      final file = File('${directory.path}/$safeLabel.psbt');
      await file.writeAsBytes(bytes);

      final xFile = XFile(file.path, mimeType: 'application/octet-stream');
      await SharePlus.instance.share(
        ShareParams(
          files: [xFile],
          text: appL10n().psbtShareText,
          sharePositionOrigin: const Rect.fromLTWH(0, 0, 100, 100),
        ),
      );
    } catch (e) {
      throw Exception("Failed to share file: $e");
    }
  }

  static Future<String?> importFromFile() async {
    try {
      final PlatformFile? picked = await FilePicker.pickFile(
        type: FileType.any,
      );

      if (picked != null && picked.path != null) {
        File file = File(picked.path!);
        Uint8List bytes = await file.readAsBytes();

        try {
          String content = utf8.decode(bytes).trim();
          content = content.replaceAll(RegExp(r'\s+'), '');

          if (RegExp(r'^[a-zA-Z0-9+/=]+$').hasMatch(content)) {
            return content;
          }
          if (RegExp(r'^[a-fA-F0-9]+$').hasMatch(content)) {
            return content;
          }
        } catch (_) {}

        return base64Encode(bytes);
      }
      return null;
    } catch (e) {
      throw Exception("Failed to import file: $e");
    }
  }
}

class _CompactSize {
  final int value;
  final int sizeBytes;
  const _CompactSize(this.value, this.sizeBytes);
}
