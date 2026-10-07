// Platform-adaptive "surface" for floating chrome (nav bars, command bar).
//
// 2027 design direction: real Liquid Glass on both platforms via the
// `liquid_glass_widgets` renderer — full GPU refraction + specular on
// Impeller (iOS Metal / Android Vulkan), with the package's own lightweight
// Skia/Web fallback when shaders aren't available. We route ALL floating
// chrome through this single widget, so the whole app's glass is swappable
// (and revertible to the prior BackdropFilter implementation) in one place.
//
// Accessibility gate (principle #1): if the user has Increase Contrast on,
// we drop the translucency entirely and fall back to a solid tonal surface
// so text on the bar never loses contrast against busy content behind it.
// (Reduce Transparency is additionally honored inside the renderer.)

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'package:kute/services/device_performance.dart';
import 'package:kute/theme/app_theme.dart';

class KuteGlass extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;

  /// Frost strength. Mapped onto the renderer's backdrop blur (clamped to a
  /// sane band so callers passing the old high BackdropFilter sigmas don't
  /// over-frost the new shader).
  final double blur;

  const KuteGlass({
    super.key,
    required this.child,
    required this.borderRadius,
    this.padding,
    this.blur = 24,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Increase Contrast → never rely on translucency for legibility.
    final highContrast = MediaQuery.of(context).highContrast;

    if (highContrast) {
      // Solid tonal surface with a soft lift — the high-contrast fallback.
      return Container(
        padding: padding,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: borderRadius,
          border: Border.all(color: c.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.08),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: child,
      );
    }

    // Liquid Glass. AdaptiveGlass picks the best path for the active renderer
    // (full shader on Impeller, lightweight on Skia, FakeGlass as the final
    // fallback). Quality is also tiered by platform for low-end safety:
    //   * iOS    → premium (Impeller is always on and devices are capable):
    //              full refraction + specular.
    //   * Android→ standard (the cheap, calibrated lightweight shader): the
    //              device range is huge and low-end GPUs choke on the premium
    //              refraction pass — standard still reads as glass at a flat
    //              cost. Flagship Android can be opted up later if wanted.
    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;
    // A low-end phone gets the shader-free glass: the standard shader
    // still costs a pass per frame that a 720p Mali cannot spare.
    final lowEnd = DevicePerformance.isLowEnd;
    final radius = borderRadius.topLeft.x;
    final content =
        padding != null ? Padding(padding: padding!, child: child) : child;
    return AdaptiveGlass(
      quality: lowEnd
          ? GlassQuality.minimal
          : isIOS
              ? GlassQuality.premium
              : GlassQuality.standard,
      shape: LiquidRoundedSuperellipse(borderRadius: radius),
      settings: LiquidGlassSettings(
        blur: (blur * 0.5).clamp(6.0, 16.0),
        // Translucent tint of the app surface so the bar still reads as a
        // discrete pane and the hint text stays legible over busy content.
        glassColor: c.surface.withValues(alpha: isDark ? 0.45 : 0.55),
      ),
      child: content,
    );
  }
}
