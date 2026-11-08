// lib/screens/home/components/home_tab_switch.dart
//
// The Bitcoin | Dollars switch at the top of the spending account's homes
// (founder, 8 November 2026, option A): one soft track, full pill radius,
// with one raised thumb (the selected pill's chrome, [KutePill.chrome])
// behind the selected item: white on the soft fill in light; in dark the two
// fills swap, so the thumb is still the lighter, raised one. Both items are
// the same width; each keeps its glyph and label, the selected one in the
// primary text colour, the other secondary.
//
// THE THUMB IS THE PAGER. The shell's page position ([position], the
// [AppShell]'s continuous page controller) places it on every frame, and it
// has no animation of its own: a swipe drags it under the finger, a tap
// slides it on the shell's own tab-switch spring, a link moves it the same
// way, and Reduce Motion (which makes the shell's switch instant) moves it at
// once. The labels' colours ride the same value. Mounted without a pager (a
// test, a standalone use) it springs to the active tab on the chip spring,
// at once under Reduce Motion.
//
// It sizes itself to its words: its natural width, at least
// [_kMinWidth], up to whatever the bar leaves it; past that (a long locale, a
// large text setting on a narrow phone) the words scale down rather than
// overflow. The target of each item is at least 44 pt tall even where the
// track, which scales with the layout, is shorter.
//
// Screen readers hear a tab bar of tabs, each with its selection, the
// selection following the tab the shell is on rather than the thumb.

import 'dart:math' as math;
import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/screens/shared/kute_back_button.dart'
    show kKuteNavHitSize;
import 'package:kute/screens/shared/kute_pill_tabs.dart' show KutePill;
import 'package:kute/screens/shared/service_tab_strip.dart'
    show ServiceTabData;
import 'package:kute/theme/app_theme.dart';
import 'package:kute/theme/kute_motion.dart';

/// The track's height in design units (pre-`.w`).
const double _kTrackHeight = 44;

/// The least the track shrinks to on a narrow phone, in logical px.
const double _kTrackMinHeight = 34;

/// The gap between the track's edge and the thumb, in design units.
const double _kThumbInset = 3;

/// An item's padding either side of its words, in design units.
const double _kItemPadding = 10;

/// The switch's least width, in design units: wide enough to read as one
/// control with short words either side.
const double _kMinWidth = 250;

/// The glyph's size and its gap to the label, in design units.
const double _kGlyphSize = 20;
const double _kGlyphGap = 5;

/// The track's height on this screen, in logical px: it scales with the
/// layout, as the round button beside it does.
double homeTabSwitchTrackHeight() =>
    math.max(_kTrackMinHeight, _kTrackHeight.w);

class HomeTabSwitch extends StatelessWidget {
  const HomeTabSwitch({super.key, required this.tabs, this.position});

  /// The items, in the pager's order: an item's index is its page.
  final List<ServiceTabData> tabs;

  /// The shell's continuous page position; null springs to the active tab.
  final Animation<double>? position;

  int get _activeIndex =>
      tabs.indexWhere((tab) => tab.active).clamp(0, tabs.length - 1);

  TextStyle _labelStyle(BuildContext context) =>
      DefaultTextStyle.of(context).style.merge(TextStyle(
            fontSize: 14.sp,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
            height: 1.0,
          ));

  /// The width that shows every item's words in full at equal widths.
  double _naturalWidth(BuildContext context, TextStyle style) {
    var words = 0.0;
    for (final tab in tabs) {
      final painter = TextPainter(
        text: TextSpan(text: tab.label, style: style),
        textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
        textScaler:
            MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling,
        maxLines: 1,
      )..layout();
      words = math.max(words, painter.width);
      painter.dispose();
    }
    final item =
        2 * _kItemPadding.w + _kGlyphSize.sp + _kGlyphGap.w + words + 1;
    return tabs.length * item + 2 * _kThumbInset.w;
  }

  @override
  Widget build(BuildContext context) {
    final style = _labelStyle(context);
    final natural = _naturalWidth(context, style);
    final track = homeTabSwitchTrackHeight();
    final target = math.max(kKuteNavHitSize, track);
    return LayoutBuilder(
      builder: (context, constraints) {
        final room = constraints.maxWidth;
        final least = _kMinWidth.w;
        final width = room.isFinite
            ? math.max(math.min(least, room), math.min(natural, room))
            : math.max(least, natural);
        return Center(
          heightFactor: 1,
          widthFactor: 1,
          child: SizedBox(
            width: width,
            height: target,
            child: _thumbPosition(
              context,
              (place) => _SwitchBody(
                tabs: tabs,
                place: place,
                trackHeight: track,
                labelStyle: style,
              ),
            ),
          ),
        );
      },
    );
  }

  /// Rebuilds [builder] with the thumb's place: the pager's position, or
  /// the spring to the active tab with no pager.
  Widget _thumbPosition(
      BuildContext context, Widget Function(double place) builder) {
    final last = (tabs.length - 1).toDouble();
    final pager = position;
    if (pager != null) {
      return AnimatedBuilder(
        animation: pager,
        builder: (_, __) => builder(pager.value.clamp(0.0, last)),
      );
    }
    final reduce = KuteMotion.reduce(context);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: _activeIndex.toDouble()),
      duration: reduce ? Duration.zero : KuteMotion.chipDuration,
      curve: reduce ? Curves.linear : KuteMotion.chip,
      builder: (_, value, __) => builder(value.clamp(0.0, last)),
    );
  }
}

class _SwitchBody extends StatelessWidget {
  const _SwitchBody({
    required this.tabs,
    required this.place,
    required this.trackHeight,
    required this.labelStyle,
  });

  final List<ServiceTabData> tabs;

  /// Where the thumb is, in items (0..tabs.length - 1).
  final double place;
  final double trackHeight;
  final TextStyle labelStyle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dark = context.isDark;
    final inset = _kThumbInset.w;
    final span = tabs.length - 1;
    return Stack(
      alignment: Alignment.center,
      children: [
        // The track and the thumb on it. Directional, as the items' row is:
        // in a right-to-left language the first item sits on the right.
        Container(
          key: const ValueKey('home-tab-switch-track'),
          height: trackHeight,
          padding: EdgeInsets.all(inset),
          // The thumb's shadow stays inside the track.
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: dark ? c.surface : c.surfaceLight,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Align(
            alignment: AlignmentDirectional(
                span == 0 ? 0 : -1 + 2 * place / span, 0),
            child: FractionallySizedBox(
              widthFactor: 1 / tabs.length,
              heightFactor: 1,
              child: DecoratedBox(
                key: const ValueKey('home-tab-switch-thumb'),
                decoration: KutePill.chrome(context, selected: true).copyWith(
                  color: dark ? c.surfaceLight : null,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
          ),
        ),
        // The items over it: the track's whole width less its inset, the
        // target's whole height.
        Semantics(
          role: SemanticsRole.tabBar,
          container: true,
          explicitChildNodes: true,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: inset),
            child: Row(
              children: [
                for (var i = 0; i < tabs.length; i++)
                  Expanded(
                    child: _SwitchItem(
                      data: tabs[i],
                      // 0 under the thumb, 1 a whole item away.
                      away: (i - place).abs().clamp(0.0, 1.0),
                      labelStyle: labelStyle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SwitchItem extends StatelessWidget {
  const _SwitchItem({
    required this.data,
    required this.away,
    required this.labelStyle,
  });

  final ServiceTabData data;
  final double away;
  final TextStyle labelStyle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final foreground = Color.lerp(c.textPrimary, c.textSecondary, away)!;
    return Semantics(
      role: SemanticsRole.tab,
      container: true,
      button: true,
      selected: data.active,
      label: data.semanticsLabel ?? data.label,
      excludeSemantics: true,
      onTap: _tap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _tap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: _kItemPadding.w),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(data.icon, color: foreground, size: _kGlyphSize.sp),
                  SizedBox(width: _kGlyphGap.w),
                  Text(
                    data.label,
                    maxLines: 1,
                    softWrap: false,
                    style: labelStyle.copyWith(color: foreground),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _tap() {
    // Haptic confirms the tap even for users who opt out of motion.
    HapticFeedback.selectionClick();
    data.onTap();
  }
}
