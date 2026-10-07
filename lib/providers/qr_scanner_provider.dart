import 'dart:convert';

import 'package:kute/helpers/bbqr.dart';
import 'package:kute/helpers/cbor_helper.dart';
import 'package:bc_ur_dart/bc_ur_dart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QrScannerState {
  final bool isScanningAnimated;
  final bool hasResult;
  final String? resultData;
  final double progress;

  const QrScannerState({
    this.isScanningAnimated = false,
    this.hasResult = false,
    this.resultData,
    this.progress = 0.0,
  });

  QrScannerState copyWith({
    bool? isScanningAnimated,
    bool? hasResult,
    String? resultData,
    double? progress,
  }) {
    return QrScannerState(
      isScanningAnimated: isScanningAnimated ?? this.isScanningAnimated,
      hasResult: hasResult ?? this.hasResult,
      resultData: resultData ?? this.resultData,
      progress: progress ?? this.progress,
    );
  }
}

class QrScannerNotifier extends StateNotifier<QrScannerState> {
  final UR _ur = UR();
  final BbqrJoiner _bbqr = BbqrJoiner();
  final Set<String> _processedParts = {};

  QrScannerNotifier() : super(const QrScannerState());

  void onDetect(BarcodeCapture capture) {
    if (state.hasResult) return;

    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue == null) continue;
      final String code = barcode.rawValue!;

      if (code.startsWith('B\$')) {
        _handleBbqrFrame(code);
      } else if (code.toLowerCase().startsWith("ur:")) {
        _handleUrFrame(code);
      } else {
        _finish(code);
        break;
      }
    }
  }

  void _handleBbqrFrame(String frame) {
    if (_processedParts.contains(frame)) return;
    _processedParts.add(frame);

    try {
      if (!state.isScanningAnimated && frame.length >= 6) {
        // Check if multi-part (total > 01)
        final totalStr = frame.substring(4, 6);
        if (totalStr != '01') {
          state = state.copyWith(
            isScanningAnimated: true,
          );
        }
      }

      final accepted = _bbqr.addPart(frame);
      if (!accepted) return;

      if (_bbqr.isComplete) {
        state = state.copyWith(
          progress: 1.0,
        );
        final data = _bbqr.finish();
        // For PSBT/transaction file types, return as base64
        if (_bbqr.fileType == BbqrFileType.psbt || _bbqr.fileType == BbqrFileType.transaction) {
          _finish(base64Encode(data));
        } else {
          _finish(base64Encode(data));
        }
      } else {
        final progress = _bbqr.progress.clamp(0.0, 0.99);
        state = state.copyWith(
          progress: progress,
        );
      }
    } catch (e) {
      // Malformed frame: keep scanning.
    }
  }

  void _handleUrFrame(String frame) {
    if (_processedParts.contains(frame)) return;
    _processedParts.add(frame);

    try {
      final isAnimated = frame.toLowerCase().contains(RegExp(r'ur:\w+/\d+-\d+/'));

      if (isAnimated && !state.isScanningAnimated) {
        state = state.copyWith(
          isScanningAnimated: true,
        );
      }

      final complete = _ur.read(frame);

      if (complete) {
        state = state.copyWith(
          progress: 1.0,
        );
        _processResult(_ur.payload, _ur.type);
      } else if (isAnimated) {
        final expected = _ur.expectedPartIndexes.length;
        final received = _ur.receivedPartIndexes.length;
        final estimatedProgress = expected > 0
            ? (received / expected).clamp(0.0, 0.99)
            : 0.0;

        state = state.copyWith(
          progress: estimatedProgress,
        );
      }
    } catch (e) {
      // Malformed frame: keep scanning.
    }
  }

  void _processResult(Uint8List cborBytes, String urType) {
    try {
      final result = _decodeCborPayload(cborBytes, urType);
      _finish(result);
    } catch (e) {
      _finish(base64Encode(cborBytes));
    }
  }

  String _decodeCborPayload(Uint8List cborBytes, String urType) {
    // Try standard cbor decoding
    try {
      final decoded = cbor.decode(cborBytes);
      if (decoded is CborBytes) {
        final bytes = Uint8List.fromList(decoded.bytes);
        if (urType == 'crypto-psbt' || urType == 'psbt') {
          return base64Encode(bytes);
        }
        try {
          final utf8String = utf8.decode(bytes, allowMalformed: false);
          if (_looksLikeXpub(utf8String)) return utf8String;
        } catch (_) {}
        return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      }
      if (decoded is CborString) return decoded.toString();

      // For complex structures (crypto-hdkey, crypto-account), convert to plain types
      final plain = _cborToPlain(decoded);
      final xpub = CborToXpubConverter.tryExtractXpub(plain);
      if (xpub != null) return xpub;
      if (plain is String) return plain;
    } catch (_) {}

    return cborBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Convert CborValue tree to plain Dart types (Map<int,dynamic>, List, Uint8List, etc.)
  /// so existing CborToXpubConverter.tryExtractXpub works unchanged.
  dynamic _cborToPlain(CborValue value) {
    if (value is CborBytes) return Uint8List.fromList(value.bytes);
    if (value is CborString) return value.toString();
    if (value is CborSmallInt) return value.value;
    if (value is CborInt) return value.toInt();
    if (value is CborBool) return value.value;
    if (value is CborList) return value.map(_cborToPlain).toList();
    if (value is CborMap) {
      final map = <dynamic, dynamic>{};
      for (final entry in value.entries) {
        map[_cborToPlain(entry.key)] = _cborToPlain(entry.value);
      }
      return map;
    }
    return value;
  }

  bool _looksLikeXpub(String s) {
    return s.startsWith('xpub') || s.startsWith('ypub') ||
        s.startsWith('zpub') || s.startsWith('tpub') ||
        s.startsWith('upub') || s.startsWith('vpub');
  }

  void _finish(String result) {
    state = state.copyWith(
      hasResult: true,
      resultData: result,
      isScanningAnimated: false,
    );
  }
}

final qrScannerProvider = StateNotifierProvider.autoDispose<QrScannerNotifier, QrScannerState>((ref) {
  return QrScannerNotifier();
});
