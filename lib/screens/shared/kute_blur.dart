// lib/screens/shared/kute_blur.dart
//
// The app's backdrop blur. On a capable device it is a BackdropFilter; on
// a low-end phone it is nothing at all, because a full-width blur behind
// a bar costs a large fraction of every frame on a 720p Mali GPU, and the
// bars already carry a translucent fill that keeps them legible.

import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';
import 'package:kute/services/device_performance.dart';

class KuteBlur extends StatelessWidget {
  const KuteBlur({
    super.key,
    required this.sigmaX,
    required this.sigmaY,
    required this.child,
  });

  final double sigmaX, sigmaY;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (DevicePerformance.isLowEnd) return child;
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: sigmaX, sigmaY: sigmaY),
      child: child,
    );
  }
}
