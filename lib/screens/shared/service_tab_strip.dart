// lib/screens/shared/service_tab_strip.dart
//
// The Home pill tab visuals, extracted so other screens (the Ledger
// account screen, Wallet hardening Phase 4, P4.1) reuse the exact same
// look and motion. Inactive tabs are icon-only; the active tab grows into
// a labelled pill and the neighbours reflow. Reduced motion snaps to the
// final layout with no slide.
//
// Home behaviour and labels are unchanged: `FloatingActionPill` builds
// its tabs and hands them to this strip.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:kute/theme/app_theme.dart';

/// One tab in a [ServiceTabStrip].
class ServiceTabData {
  final IconData icon;
  final String? svgAsset;
  final String label;

  /// Screen reader name. Defaults to [label]; set it when the icon carries
  /// meaning the label does not (for example the venue behind a tab).
  final String? semanticsLabel;
  final VoidCallback onTap;
  final bool active;
  final int badgeCount;

  /// Tint [svgAsset] with the tab foreground instead of drawing it in its
  /// own colours. Set it for monochrome marks (the Ledger logo, a wallet
  /// mark) that would otherwise vanish against one of the two themes.
  final bool tintSvg;

  /// Drawn in the icon's square in place of [svgAsset] and [icon] (the
  /// Bitcoin tab's Sal with his coin while it is selected).
  final Widget? glyph;

  const ServiceTabData({
    required this.icon,
    this.svgAsset,
    this.glyph,
    required this.label,
    this.semanticsLabel,
    required this.onTap,
    this.active = false,
    this.badgeCount = 0,
    this.tintSvg = false,
  });
}

/// How much wider the active tab is than an inactive (icon-only) tab, as a
/// flex weight. The active tab needs room for its label; the others stay
/// icon-sized. The layout eases between these on a tab change so the pill
/// grows/slides and the neighbours reflow.
const double _kActiveWeight = 3;

/// Icon-sized tabs that spread to fill the bar; the active one grows into a
/// labelled pill. The active tab is the first entry with `active: true`.
class ServiceTabStrip extends StatefulWidget {
  final List<ServiceTabData> tabs;

  /// Strip height. Defaults to the Home pill height (44.h).
  final double? height;

  const ServiceTabStrip({super.key, required this.tabs, this.height});

  @override
  State<ServiceTabStrip> createState() => _ServiceTabStripState();
}

class _ServiceTabStripState extends State<ServiceTabStrip>
    with SingleTickerProviderStateMixin {
  /// Drives the pill's slide: the active tab's flex weight eases up to
  /// [_kActiveWeight] while the previous active eases back to 1, so the pill
  /// grows in place and the neighbours reflow smoothly. No measuring needed:
  /// the layout just reads this 0..1 each frame.
  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: 1,
  );

  /// Which tab the pill is sliding FROM / TO. Seeded (-1) so the first build
  /// rests fully expanded on the initial tab with no intro animation.
  int _activeIndex = -1;
  int _prevActiveIndex = 0;

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tabs = widget.tabs;
    if (tabs.isEmpty) return SizedBox(height: widget.height ?? 44.h);

    final int activeIndex =
        tabs.indexWhere((t) => t.active).clamp(0, tabs.length - 1);
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    // Start the slide when the active tab changes: the active tab's flex
    // weight eases up (so it's wide enough for its label) while the previous
    // one eases back to an icon, and the neighbours reflow between. Seeded on
    // the first build so the initial tab simply rests expanded.
    if (_activeIndex == -1 || _activeIndex >= tabs.length) {
      _activeIndex = activeIndex;
      _prevActiveIndex = activeIndex;
      _slide.value = 1;
    } else if (activeIndex != _activeIndex) {
      _prevActiveIndex = _activeIndex;
      _activeIndex = activeIndex;
      if (reduceMotion) {
        _slide.value = 1;
      } else {
        _slide.forward(from: 0);
      }
    }

    // Per-tab flex weight (active ≈ _kActiveWeight × an icon slot) and reveal
    // (0 = plain icon, 1 = full pill + label), interpolated over the slide.
    double weightFor(int i, double t) {
      final double from = i == _prevActiveIndex ? _kActiveWeight : 1;
      final double to = i == _activeIndex ? _kActiveWeight : 1;
      return from + (to - from) * t;
    }

    double revealFor(int i, double t) {
      if (i == _activeIndex) return t;
      if (i == _prevActiveIndex) return 1 - t;
      return 0;
    }

    // Weights are animated (not measured), and each label lives in a
    // Flexible so it can never overflow: the strip is overflow-proof on any
    // width.
    return SizedBox(
      height: widget.height ?? 44.h,
      child: AnimatedBuilder(
        animation: _slide,
        builder: (context, _) {
          // Ease the raw (linear) controller value so the pill DECELERATES
          // into place instead of stopping flat.
          final double t = Curves.easeOutCubic.transform(_slide.value);
          return Row(
            children: [
              for (var i = 0; i < tabs.length; i++)
                Expanded(
                  flex: (weightFor(i, t) * 1000).round(),
                  child: ServiceTab(
                    data: tabs[i],
                    colors: c,
                    reveal: revealFor(i, t),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// A single tab. Inactive tabs are icon-only; the active tab (reveal→1)
/// grows into a labelled pill. [reveal] (0..1), driven by the parent's
/// slide, cross-fades the pill background, the label, and the icon tint as
/// the active tab changes. The label sits in a Flexible so it can never
/// overflow the slot.
class ServiceTab extends StatelessWidget {
  final ServiceTabData data;
  final AppColorsExtension colors;

  /// 0 = plain icon (inactive), 1 = full pill + label (active).
  final double reveal;

  const ServiceTab({
    super.key,
    required this.data,
    required this.colors,
    required this.reveal,
  });

  @override
  Widget build(BuildContext context) {
    final double r = reveal.clamp(0.0, 1.0);
    final Color foreground =
        Color.lerp(colors.textSecondary, colors.textPrimary, r)!;
    final bool isLight = Theme.of(context).brightness == Brightness.light;
    // Active tab wears the neutral fill, revealed with the slide. No
    // border (user decision: the outlined pill read as clutter).
    final Color fillColor =
        (isLight ? Colors.white : colors.surface).withValues(alpha: r);

    final iconArea = SizedBox(
      width: 24.sp,
      height: 24.sp,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          if (data.glyph != null)
            ExcludeSemantics(child: data.glyph!)
          else if (data.svgAsset != null)
            ExcludeSemantics(
              child: SvgPicture.asset(
                data.svgAsset!,
                width: 24.sp,
                height: 24.sp,
                colorFilter: data.tintSvg
                    ? ColorFilter.mode(foreground, BlendMode.srcIn)
                    : null,
              ),
            )
          else
            Icon(data.icon, color: foreground, size: 24.sp),
          if (data.badgeCount > 0)
            Positioned(
              top: -9,
              right: -12,
              child: Container(
                constraints: BoxConstraints(minWidth: 18.sp, minHeight: 18.sp),
                padding: EdgeInsets.symmetric(horizontal: 5.w),
                decoration: BoxDecoration(
                  color: colors.accent,
                  borderRadius: BorderRadius.circular(10.r),
                  border: Border.all(color: colors.surface, width: 1.5),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${data.badgeCount}',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    return Semantics(
      label: data.semanticsLabel ?? data.label,
      button: true,
      selected: data.active,
      excludeSemantics: data.semanticsLabel != null,
      child: GestureDetector(
        // Haptic confirms the tap even for users who opt out of motion.
        onTap: () {
          HapticFeedback.selectionClick();
          data.onTap();
        },
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: 10.w + 4.w * r,
              vertical: 8.h,
            ),
            decoration: BoxDecoration(
              color: fillColor,
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                iconArea,
                // The label reveals as the tab becomes active. Its WIDTH is
                // collapsed by [widthFactor] (not just faded), so by the time
                // reveal hits ~0 the label already occupies zero width and
                // can drop out with no layout snap.
                if (r > 0.001)
                  Flexible(
                    child: ClipRect(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        widthFactor: r,
                        child: Opacity(
                          opacity: r,
                          child: Padding(
                            padding: EdgeInsets.only(left: 8.w),
                            child: Text(
                              data.label,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.clip,
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 14.sp,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
