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
// eases its chrome over 180 ms (at once under Reduce Motion).

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/screens/shared/kute_motion.dart';
import 'package:kute/theme/app_theme.dart';

/// One entry of a [KutePillTabs] row.
class KutePillItem {
  final String label;
  final IconData? icon;

  /// A small image before the label (a venue's logo), at the label's
  /// height; see [KutePill.leading].
  final Widget? leading;

  const KutePillItem({required this.label, this.icon, this.leading});
}

/// A pill's size: the row's height, the pill's padding, its label and
/// its glyph, in design units (scaled with ScreenUtil where used).
/// [regular] is every strip's size; the Investments pills are [large] on
/// the page and [compact] in its collapsed bar, the same chrome a step
/// up and a step down.
enum KutePillSize {
  compact(height: 28, hPad: 10, vPad: 6, font: 11, icon: 12),
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
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final fg = selected ? c.textPrimary : c.textTertiary;
    final duration = kuteMotion(context, const Duration(milliseconds: 180));
    // Merged onto the inherited style: AnimatedDefaultTextStyle replaces
    // it, and would drop the theme's Inter for the platform font.
    final textStyle = DefaultTextStyle.of(context).style.merge(TextStyle(
          fontSize: size.font.sp,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: fg,
          letterSpacing: 0.1,
          height: 1.0,
        ));

    final chip = AnimatedContainer(
      duration: duration,
      curve: Curves.easeOut,
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
        boxShadow: selected && isLight
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
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
              curve: Curves.easeOut,
              style: textStyle,
              child: Text(
                label,
                semanticsLabel: semanticLabel,
                maxLines: 1,
                overflow: TextOverflow.clip,
                softWrap: false,
              ),
            ),
          ),
        ],
      ),
    );

    return Semantics(
      button: true,
      selected: link ? null : selected,
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

  const KutePillTabs({
    super.key,
    required this.items,
    required this.onTap,
    this.selectedIndex,
    this.horizontalPadding = 4,
    this.size = KutePillSize.regular,
    this.height,
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
    if (widget.selectedIndex != null && items.length <= 3) {
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
