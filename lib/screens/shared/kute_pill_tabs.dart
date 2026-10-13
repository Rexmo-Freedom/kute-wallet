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
// ROWS STACKED UNDER EACH OTHER ARE ONE HIERARCHY, NOT THREE ROWS OF
// BUTTONS (owner decision 2026-10-13, from Investments › Investing: the
// Investing · Predictions · Portfolio pills, the categories and the
// subcategories wore the same boxed chip and read as three identical
// button rows). [KutePillStyle] gives each level its own weight with no
// new chrome: level 1 keeps the boxed chip ([KutePillStyle.boxed]),
// level 2 is text tabs with an ink underline under the one on screen
// ([KutePillStyle.tab]), level 3 is smaller text with no box and no
// underline ([KutePillStyle.subtle]). The text levels use the theme's
// ink tokens only (textPrimary on the one on screen, textTertiary on
// the others, as the chart range pills), keep a 44 pt hit target, line
// their first label up with the screen's 16 margin, announce the
// selected one to screen readers and ease over 180 ms (none under
// Reduce Motion).

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

/// Which level of a stack of rows a pill belongs to (see the file
/// header): how much chrome it wears, not what it does.
enum KutePillStyle {
  /// Level 1, and every single row: the boxed chip (white/surface card,
  /// hairline border, soft shadow on the one on screen). Sized by
  /// [KutePillSize].
  boxed,

  /// Level 2: a text tab. The one on screen is textPrimary, semibold,
  /// over a 2 pt ink underline as wide as its label; the others are
  /// textTertiary. No box. The label is [AppTextStyles.modalItem].
  tab,

  /// Level 3: smaller text (the regular chip's 13 sp label). The one on
  /// screen is textPrimary, semibold; the others are textTertiary. No
  /// box, no underline.
  subtle,
}

/// The inset a text pill ([KutePillStyle.tab] / [KutePillStyle.subtle])
/// carries on each side of its label, in design units. A row of them is
/// padded by `16 - kKuteTextPillInset` so its first label sits on the
/// screen's 16 margin, the edge of the cards under it.
const double kKuteTextPillInset = 10;

/// A text pill's row height: 44 pt, the minimum hit target, at every
/// screen size (scaled up on large screens, never down).
double kuteTextPillRowHeight() => math.max(44.0, 44.h);

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

  /// The boxed pill's size; the text styles have their own.
  final KutePillSize size;

  /// The pill's level in a stack of rows (see [KutePillStyle]).
  final KutePillStyle style;

  /// A link (a row with no selection, every pill drawn selected): screen
  /// readers hear a button, never "selected".
  final bool link;

  const KutePill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.leading,
    this.fillWidth = false,
    this.size = KutePillSize.regular,
    this.style = KutePillStyle.boxed,
    this.link = false,
  });

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: link ? null : selected,
        child: style == KutePillStyle.boxed
            ? _boxed(context)
            : _text(context),
      );

  /// Levels 2 and 3: the label alone in ink, no box.
  Widget _text(BuildContext context) {
    final c = context.colors;
    final tab = style == KutePillStyle.tab;
    final fg = selected ? c.textPrimary : c.textTertiary;
    final duration = kuteMotion(context, const Duration(milliseconds: 180));
    final weight = selected ? FontWeight.w600 : FontWeight.w500;
    // Merged onto the inherited style: AnimatedDefaultTextStyle replaces
    // it, and would drop the theme's Inter for the platform font.
    final textStyle = DefaultTextStyle.of(context).style.merge(tab
        ? AppTextStyles.modalItem(context)
            .copyWith(color: fg, fontWeight: weight, height: 1.0)
        : TextStyle(
            fontSize: KutePillSize.regular.font.sp,
            fontWeight: weight,
            color: fg,
            letterSpacing: 0.1,
            height: 1.0,
          ));

    Widget body = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: (tab ? 15 : 13).sp, color: fg),
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
              maxLines: 1,
              overflow: TextOverflow.clip,
              softWrap: false,
            ),
          ),
        ),
      ],
    );

    if (tab) {
      // The underline as wide as the label, under every tab (clear on
      // the others) so the labels share one baseline, balanced by the
      // same space above so the label stays centred in the row.
      body = IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 6),
            body,
            const SizedBox(height: 4),
            AnimatedContainer(
              key: const ValueKey('kute-pill-underline'),
              duration: duration,
              curve: Curves.easeOut,
              height: 2,
              decoration: BoxDecoration(
                color: selected
                    ? c.textPrimary
                    : c.textPrimary.withValues(alpha: 0),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: kKuteTextPillInset.w),
          child: Center(widthFactor: fillWidth ? null : 1, child: body),
        ),
      ),
    );
  }

  /// Level 1: the boxed chip.
  Widget _boxed(BuildContext context) {
    final c = context.colors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final fg = selected ? c.textPrimary : c.textTertiary;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: kuteMotion(context, const Duration(milliseconds: 180)),
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
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.clip,
                softWrap: false,
                style: TextStyle(
                  fontSize: size.font.sp,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: fg,
                  letterSpacing: 0.1,
                  height: 1.0,
                ),
              ),
            ),
          ],
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

  /// The pills' size (see [KutePillSize]); boxed rows only.
  final KutePillSize size;

  /// The row's level in a stack of rows (see [KutePillStyle]).
  final KutePillStyle style;

  const KutePillTabs({
    super.key,
    required this.items,
    required this.onTap,
    this.selectedIndex,
    this.horizontalPadding = 4,
    this.size = KutePillSize.regular,
    this.style = KutePillStyle.boxed,
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
    final boxed = widget.style == KutePillStyle.boxed;
    final link = widget.selectedIndex == null;
    // Text pills carry their own inset and sit side by side; the boxed
    // chips keep their 6 gap.
    final gap = boxed ? 6.w : 0.0;
    final height = boxed ? widget.size.height.h : kuteTextPillRowHeight();

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
                    style: widget.style,
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
              style: widget.style,
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
