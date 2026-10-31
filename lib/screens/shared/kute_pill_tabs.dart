// lib/screens/shared/kute_pill_tabs.dart
//
// The Home Activity / Balance / Price pill strip, extracted so every
// pill row in the app (Home analytics tabs, the Predictions and
// Investing category strips on hot and Ledger wallets) shares ONE
// chrome (user decision: same design everywhere). A pill is a squared
// 12.r chip on the NeutralActionChip ground: selected wears the white/
// surface card with a hairline border and a soft shadow, unselected
// sits transparent and tonal. Three or fewer selectable pills share
// the row at equal widths; longer strips (and link rows, which have no
// selection) side-scroll at natural width with fade edges.
//
// Rows are never stacked (owner decision 2026-10-13: "I loved the
// pills"): a category row whose category has subcategories drills in,
// the row giving way to a back pill ("‹ Tradfi") and the subcategory
// pills, all in this one boxed chip (see PolyDrillRow). Every pill is
// announced as a button with its selection (a link row's never), keeps
// a 44 pt hit target wherever its row is [kutePillRowHeight] tall, and
// springs its chrome on the chip spring (KuteMotion.chip; at once under
// Reduce Motion), with the app's press under a finger ([KutePressable]).
//
// A pill that holds more (the Investments pills, founder 31 October
// 2026: "it should be more clear that we have much more context here")
// carries its context after its name in the quieter weight ("Investing ·
// Trending", [KutePillItem.detail]) and a chevron in a small filled
// circle at its end ([KutePillItem.menu]), so it reads as a control and
// not as decoration.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/screens/shared/kute_motion.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/theme/kute_motion.dart';

/// One entry of a [KutePillTabs] row.
class KutePillItem {
  final String label;
  final IconData? icon;

  /// A small image before the label (a venue's logo), at the label's
  /// height; see [KutePill.leading].
  final Widget? leading;

  /// The pill's context after its name, in the quieter weight ("Trending",
  /// "Politics · Live"); null for the plain name.
  final String? detail;

  /// A chevron in a small filled circle at the pill's end: the pill opens
  /// a pick when tapped again.
  final bool menu;

  const KutePillItem({
    required this.label,
    this.icon,
    this.leading,
    this.detail,
    this.menu = false,
  });
}

/// A pill's size: the row's height, the pill's padding, its label and
/// its glyph, in design units (scaled with ScreenUtil where used).
/// [regular] is every strip's size; the Investments pills are [large] on
/// the page and [compact] in its collapsed bar, the same chrome a step
/// up and a step down. [compact] went up one notch (founder, 2026-10-13:
/// "just a little bit bigger"): 12 sp labels, 14 glyphs, 32 high, still
/// under [regular] and [large].
enum KutePillSize {
  compact(height: 32, hPad: 11, vPad: 7, font: 12, icon: 14),
  regular(height: 34, hPad: 14, vPad: 9, font: 13, icon: 15),
  large(height: 40, hPad: 12, vPad: 11, font: 14, icon: 16);

  const KutePillSize({
    required this.height,
    required this.hPad,
    required this.vPad,
    required this.font,
    required this.icon,
  });

  /// The row's height.
  final double height;

  /// The pill's horizontal padding: a minimum inset for the equal-width
  /// pills, the whole inset for a natural-width one.
  final double hPad;
  final double vPad;
  final double font;
  final double icon;
}

/// The height of a row that gives each of its pills a 44 pt hit target
/// (the chip keeps its [KutePillSize] height, centred in it), at every
/// screen size (scaled up on large screens, never down).
double kutePillRowHeight() => math.max(44.0, 44.h);

/// A single pill. [selected] picks the card chrome (white/surface fill,
/// hairline border, bold label) over the quiet tonal treatment; link
/// rows pass `selected: true` for every pill so each reads as a button.
class KutePill extends StatelessWidget {
  final String label;
  final IconData? icon;

  /// A small image before the label, at the label's height (a league's
  /// or a coin's logo); null for the plain text pill.
  final Widget? leading;
  final bool selected;
  final bool fillWidth;
  final VoidCallback onTap;

  final KutePillSize size;

  /// A link (a row with no selection, every pill drawn selected): screen
  /// readers hear a button, never "selected".
  final bool link;

  /// What screen readers hear instead of [label] (the back pill: "Back,
  /// Tradfi"); null reads the label.
  final String? semanticLabel;

  /// See [KutePillItem.detail] and [KutePillItem.menu].
  final String? detail;
  final bool menu;

  const KutePill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.leading,
    this.fillWidth = false,
    this.size = KutePillSize.regular,
    this.link = false,
    this.semanticLabel,
    this.detail,
    this.menu = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final fg = selected ? c.textPrimary : c.textTertiary;
    final reduce = kuteReduceMotion(context);
    // The chrome springs between its two states (KuteMotion.chip).
    final duration = reduce ? Duration.zero : KuteMotion.chipDuration;
    final curve = reduce ? Curves.linear : KuteMotion.chip;
    // Merged onto the inherited style: AnimatedDefaultTextStyle replaces
    // it, and would drop the theme's Inter for the platform font.
    final textStyle = DefaultTextStyle.of(context).style.merge(TextStyle(
          fontSize: size.font.sp,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: fg,
          letterSpacing: 0.1,
          height: 1.0,
        ));
    final detailStyle = textStyle.copyWith(
        fontWeight: FontWeight.w500, color: c.textSecondary);

    final chip = AnimatedContainer(
      duration: duration,
      curve: curve,
      padding:
          EdgeInsets.symmetric(horizontal: size.hPad.w, vertical: size.vPad.h),
      decoration: BoxDecoration(
        color: selected
            ? (isLight ? Colors.white : c.surface)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: selected
              ? (isLight ? c.border : c.borderSubtle)
              : Colors.transparent,
          width: isLight ? 1.0 : 0.5,
        ),
        // The unselected state keeps the shadow at the same blur, only
        // transparent: the spring overshoots past 1, and a shadow lerped
        // towards none scales its blur negative (an assertion in debug).
        boxShadow: [
          BoxShadow(
            color: selected && isLight
                ? Colors.black.withValues(alpha: 0.04)
                : Colors.transparent,
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: fillWidth ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment:
            fillWidth ? MainAxisAlignment.center : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: size.icon.sp, color: fg),
            SizedBox(width: 6.w),
          ],
          if (leading != null) ...[
            leading!,
            SizedBox(width: 6.w),
          ],
          Flexible(
            child: AnimatedDefaultTextStyle(
              duration: duration,
              curve: curve,
              style: textStyle,
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: label),
                  // The context after the name, quieter.
                  if (detail != null)
                    TextSpan(text: ' · $detail', style: detailStyle),
                ]),
                semanticsLabel: semanticLabel,
                maxLines: 1,
                overflow: TextOverflow.clip,
                softWrap: false,
              ),
            ),
          ),
          // The chevron in a filled circle: a control, not decoration.
          if (menu) ...[
            SizedBox(width: 6.w),
            Container(
              width: (size.icon + 6).sp,
              height: (size.icon + 6).sp,
              decoration: BoxDecoration(
                color: isLight ? c.surfaceElevated : c.surfaceLight,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.expand_more_rounded,
                  size: size.icon.sp, color: c.textSecondary),
            ),
          ],
        ],
      ),
    );

    return Semantics(
      button: true,
      selected: link ? null : selected,
      child: KutePressable(
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          // The tap reaches 44 pt wherever the row gives it the room
          // ([kutePillRowHeight]); the chip keeps its own size, centred.
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            child: Align(
              widthFactor: fillWidth ? null : 1,
              heightFactor: 1,
              child: chip,
            ),
          ),
        ),
      ),
    );
  }
}

/// A row of [KutePill]s, 34.h tall at the regular [size].
///
/// With a [selectedIndex] the row behaves as tabs: up to three pills
/// share the width equally, more side-scroll. With `selectedIndex: null`
/// the row is a strip of links (category pills): every pill wears the
/// card chrome and the row always side-scrolls at natural width.
class KutePillTabs extends StatefulWidget {
  final List<KutePillItem> items;
  final int? selectedIndex;
  final void Function(int index) onTap;

  /// Horizontal inset of the row's content (also the scroll padding).
  final double horizontalPadding;

  /// The pills' size (see [KutePillSize]).
  final KutePillSize size;

  /// The row's height when it is not the [size]'s own: a row given
  /// [kutePillRowHeight] gives each pill a 44 pt hit target.
  final double? height;

  /// Natural-width pills in a side-scrolling row even with three or
  /// fewer tabs: for a row whose selected pill carries a longer label
  /// (the Investments pills, which name their category when picked).
  final bool scroll;

  const KutePillTabs({
    super.key,
    required this.items,
    required this.onTap,
    this.selectedIndex,
    this.horizontalPadding = 4,
    this.size = KutePillSize.regular,
    this.height,
    this.scroll = false,
  });

  @override
  State<KutePillTabs> createState() => _KutePillTabsState();
}

class _KutePillTabsState extends State<KutePillTabs> {
  final ScrollController _controller = ScrollController();
  bool _canScrollRight = true;
  bool _canScrollLeft = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateScrollIndicators);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _updateScrollIndicators());
  }

  void _updateScrollIndicators() {
    if (!mounted || !_controller.hasClients) return;
    final pos = _controller.position;
    final newCanScrollRight = pos.pixels < pos.maxScrollExtent - 2;
    final newCanScrollLeft = pos.pixels > 2;
    if (newCanScrollRight != _canScrollRight ||
        newCanScrollLeft != _canScrollLeft) {
      setState(() {
        _canScrollRight = newCanScrollRight;
        _canScrollLeft = newCanScrollLeft;
      });
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_updateScrollIndicators);
    _controller.dispose();
    super.dispose();
  }

  bool _isSelected(int i) =>
      widget.selectedIndex == null || widget.selectedIndex == i;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final items = widget.items;
    final pad = widget.horizontalPadding.w;
    final link = widget.selectedIndex == null;
    final gap = 6.w;
    final height = widget.height ?? widget.size.height.h;

    // Tabs with three or fewer entries fit comfortably in one row: give
    // each equal width so they're evenly spaced. Four or more truncated
    // the labels under equal widths ("Activit", "Balanc"), so longer
    // strips side-scroll at natural width instead.
    if (widget.selectedIndex != null && items.length <= 3 && !widget.scroll) {
      return SizedBox(
        height: height,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: pad),
          child: Row(
            children: [
              for (int i = 0; i < items.length; i++) ...[
                Expanded(
                  child: KutePill(
                    label: items[i].label,
                    icon: items[i].icon,
                    leading: items[i].leading,
                    detail: items[i].detail,
                    menu: items[i].menu,
                    selected: _isSelected(i),
                    fillWidth: true,
                    size: widget.size,
                    onTap: () => widget.onTap(i),
                  ),
                ),
                if (i < items.length - 1) SizedBox(width: gap),
              ],
            ],
          ),
        ),
      );
    }

    Widget fade({required bool left}) => Positioned(
          left: left ? 0 : null,
          right: left ? null : 0,
          top: 0,
          bottom: 0,
          width: 20.w,
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: left ? Alignment.centerRight : Alignment.centerLeft,
                  end: left ? Alignment.centerLeft : Alignment.centerRight,
                  colors: [
                    c.background.withValues(alpha: 0.0),
                    c.background.withValues(alpha: 0.8),
                  ],
                ),
              ),
            ),
          ),
        );

    return SizedBox(
      height: height,
      child: Stack(
        children: [
          ListView.separated(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.symmetric(horizontal: pad),
            itemCount: items.length,
            separatorBuilder: (_, __) => SizedBox(width: gap),
            itemBuilder: (context, i) => KutePill(
              label: items[i].label,
              icon: items[i].icon,
              leading: items[i].leading,
              detail: items[i].detail,
              menu: items[i].menu,
              selected: _isSelected(i),
              size: widget.size,
              link: link,
              onTap: () => widget.onTap(i),
            ),
          ),
          if (_canScrollLeft) fade(left: true),
          if (_canScrollRight) fade(left: false),
        ],
      ),
    );
  }
}
