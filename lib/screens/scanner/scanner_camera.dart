// lib/screens/scanner/scanner_camera.dart
//
// The camera behind the scanner sheet, behind a seam: the app drives
// mobile_scanner through [MobileScannerCamera]; tests override
// [scannerCameraFactoryProvider] with a fake that hands codes in by hand
// (there is no camera in a widget test).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// The camera permission is off: retrying can never start the camera.
class ScannerCameraDenied implements Exception {
  const ScannerCameraDenied();
}

/// This device has no camera to scan with (the simulator): retrying can
/// never start one.
class ScannerCameraUnavailable implements Exception {
  const ScannerCameraUnavailable();
}

/// One camera session of the scanner sheet. Created when the sheet opens,
/// disposed when it closes; never reused after [dispose].
abstract class ScannerCamera {
  /// Whether the torch is on, for the flash control.
  ValueListenable<bool> get torchOn;

  /// Start the preview. Throws [ScannerCameraDenied] when the camera
  /// permission is off and [ScannerCameraUnavailable] when the device has
  /// no camera; anything else it throws is worth a retry.
  Future<void> start();

  Future<void> stop();

  Future<void> toggleTorch();

  /// Release the camera. Safe to call more than once.
  Future<void> dispose();

  /// The live preview, calling [onDetect] with every capture.
  Widget buildPreview(void Function(BarcodeCapture capture) onDetect);
}

/// Builds the camera for one sheet. [multiPart] reads animated codes
/// (BBQr, UR) frame by frame, so it scans QR only and never throttles.
typedef ScannerCameraFactory = ScannerCamera Function(
    {required bool multiPart});

final scannerCameraFactoryProvider = Provider<ScannerCameraFactory>(
  (ref) =>
      ({required bool multiPart}) => MobileScannerCamera(multiPart: multiPart),
);

/// The real camera: a [MobileScannerController] and its [MobileScanner].
class MobileScannerCamera implements ScannerCamera {
  MobileScannerCamera({required bool multiPart})
      : _controller = multiPart
            // Animated PSBT QRs (Sparrow BBQr, Jade UR, Passport UR) cycle
            // frames at 4 to 8 fps; a throttled detector misses every
            // other frame. The multi-part assembler dedupes identical
            // frames itself.
            ? MobileScannerController(
                detectionSpeed: DetectionSpeed.noDuplicates,
                returnImage: false,
                torchEnabled: false,
                formats: const [BarcodeFormat.qrCode],
              )
            : MobileScannerController() {
    _controller.addListener(_syncTorch);
  }

  final MobileScannerController _controller;
  final ValueNotifier<bool> _torchOn = ValueNotifier(false);
  bool _disposed = false;

  void _syncTorch() {
    if (_disposed) return;
    _torchOn.value = _controller.value.torchState == TorchState.on;
  }

  @override
  ValueListenable<bool> get torchOn => _torchOn;

  @override
  Future<void> start() async {
    try {
      await _controller.start();
    } on MobileScannerException catch (e) {
      if (e.errorCode == MobileScannerErrorCode.permissionDenied) {
        throw const ScannerCameraDenied();
      }
      if (e.errorCode == MobileScannerErrorCode.unsupported) {
        throw const ScannerCameraUnavailable();
      }
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    if (_disposed) return;
    await _controller.stop();
  }

  @override
  Future<void> toggleTorch() async {
    if (_disposed) return;
    await _controller.toggleTorch();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _controller.removeListener(_syncTorch);
    _torchOn.dispose();
    // `dispose()` is async in v7: fire it so the OS frees the camera as
    // fast as it can (scan, pay, scan again must not find it "in use").
    await _controller.dispose();
  }

  @override
  Widget buildPreview(void Function(BarcodeCapture capture) onDetect) =>
      MobileScanner(
        controller: _controller,
        onDetect: onDetect,
        // The sheet says why the camera is off, in its own words: the
        // package's own placeholder and error text never show.
        placeholderBuilder: (_) => const ColoredBox(color: Colors.black),
        errorBuilder: (_, __) => const ColoredBox(color: Colors.black),
      );
}
