// A stand-in for the scanner sheet's camera: there is no camera in a
// widget test. Override [scannerCameraFactoryProvider] with
// [FakeScannerCameras.override] and hand codes in with [FakeScannerCamera.scan].

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:kute/screens/scanner/scanner_camera.dart';

class FakeScannerCamera implements ScannerCamera {
  FakeScannerCamera({required this.multiPart, this.startError});

  final bool multiPart;

  /// Thrown by every [start] when set (a camera that never frees).
  final Object? startError;
  final ValueNotifier<bool> _torch = ValueNotifier(false);
  void Function(BarcodeCapture capture)? _onDetect;

  int starts = 0;
  int stops = 0;
  int torchToggles = 0;
  bool disposed = false;

  /// Running: started and not stopped since.
  bool running = false;

  @override
  ValueListenable<bool> get torchOn => _torch;

  @override
  Future<void> start() async {
    starts++;
    if (startError != null) throw startError!;
    running = true;
  }

  @override
  Future<void> stop() async {
    stops++;
    running = false;
  }

  @override
  Future<void> toggleTorch() async {
    torchToggles++;
    _torch.value = !_torch.value;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    running = false;
  }

  @override
  Widget buildPreview(void Function(BarcodeCapture capture) onDetect) {
    _onDetect = onDetect;
    return const SizedBox.expand(key: ValueKey('fake-camera-preview'));
  }

  /// The camera sees a QR holding [raw].
  void scan(String raw) =>
      _onDetect!(BarcodeCapture(barcodes: [Barcode(rawValue: raw)]));
}

/// Every camera the scanner sheets opened, in order.
class FakeScannerCameras {
  FakeScannerCameras({this.startErrors = const []});

  /// The start error of each camera opened, in order; none past the end.
  final List<Object?> startErrors;

  final List<FakeScannerCamera> opened = [];

  FakeScannerCamera get last => opened.last;

  Override get override => scannerCameraFactoryProvider.overrideWithValue(
        ({required bool multiPart}) {
          final i = opened.length;
          final camera = FakeScannerCamera(
              multiPart: multiPart,
              startError: i < startErrors.length ? startErrors[i] : null);
          opened.add(camera);
          return camera;
        },
      );
}
