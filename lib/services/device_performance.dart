// lib/services/device_performance.dart
//
// One answer to "is this a low-end phone?", decided once from what the
// platform exposes without a plugin: on Android, a screen no wider than
// 800 physical pixels is a 720p-class device, which in practice means a
// Mali or PowerVR GPU that cannot afford full-screen blurs, shader glass
// or a repaint on every price tick. iOS devices that run this app are
// all capable. The answer feeds the "lite" choices across the app:
// blurs become translucent fills, glass becomes flat, live feeds coalesce
// over a longer frame, sparklines paint fewer points.

import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;

class DevicePerformance {
  DevicePerformance._();

  static bool? _lowEnd;

  /// Test and debug override; null restores the measured answer.
  static bool? debugOverride;

  static bool get isLowEnd {
    final override = debugOverride;
    if (override != null) return override;
    return _lowEnd ??= _measure();
  }

  static bool _measure() {
    try {
      if (!Platform.isAndroid) return false;
      final views = PlatformDispatcher.instance.views;
      if (views.isEmpty) return false;
      final size = views.first.physicalSize;
      final shortest = size.width < size.height ? size.width : size.height;
      return shortest > 0 && shortest <= 800;
    } catch (_) {
      return false;
    }
  }

  /// The live-feed frame for this device: how long price ticks coalesce
  /// before the UI is told. Longer on a low-end phone, where every commit
  /// is a repaint it cannot spare.
  static Duration liveFrame(Duration normal) =>
      isLowEnd ? normal * 3 : normal;
}
