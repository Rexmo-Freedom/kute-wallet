// lib/screens/shared/kute_wordmark.dart
//
// The brand, as a static widget.
//
// The splash plays this same wordmark with the dot escaping and the dog
// chasing it (lib/screens/spash/splash.dart), and then hands off to a PIN
// screen that showed no brand at all. The app introduced itself and then
// forgot its own name on the next frame. This is the same type spec with
// no controllers, so any screen before the wallet opens can carry it.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/theme/app_theme.dart';

class KuteWordmark extends StatelessWidget {
  const KuteWordmark({super.key, this.size = 32, this.color});

  /// Type size in design pixels. The splash uses 56; a screen that has
  /// work to do below it wants less.
  final double size;

  /// Overrides the word's colour. The dot always takes the accent, which
  /// is the one place the brand's colour belongs.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = TextStyle(
      color: color ?? c.textPrimary,
      fontSize: size.sp,
      fontWeight: FontWeight.w800,
      letterSpacing: -size * 0.025,
      height: 1.0,
    );
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: 'kute', style: style),
          TextSpan(
            text: '.',
            style: style.copyWith(color: c.accent),
          ),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
