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

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/screens/shared/kute_motion.dart';
import 'package:kute/theme/app_theme.dart';

/// One entry of a [KutePillTabs] row.
class KutePillItem {
  final String label;
  final IconData? icon;

  const KutePillItem({required this.label, this.icon});
}

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

  const KutePill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.leading,
    this.fillWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final fg = selected ? c.textPrimary : c.textTertiary;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: kuteMotion(context, const Duration(milliseconds: 180)),
        curve: Curves.easeOut,
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 9.h),
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
              Icon(icon, size: 15.sp, color: fg),
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
                  fontSize: 13.sp,
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

/// A 34.h row of [KutePill]s.
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

  const KutePillTabs({
    super.key,
    required this.items,
    required this.onTap,
    this.selectedIndex,
    this.horizontalPadding = 4,
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

    // Tabs with three or fewer entries fit comfortably in one row: give
    // each equal width so they're evenly spaced. Four or more truncated
    // the labels under equal widths ("Activit", "Balanc"), so longer
    // strips side-scroll at natural width instead.
    if (widget.selectedIndex != null && items.length <= 3) {
      return SizedBox(
        height: 34.h,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: pad),
          child: Row(
            children: [
              for (int i = 0; i < items.length; i++) ...[
                Expanded(
                  child: KutePill(
                    label: items[i].label,
                    icon: items[i].icon,
                    selected: _isSelected(i),
                    fillWidth: true,
                    onTap: () => widget.onTap(i),
                  ),
                ),
                if (i < items.length - 1) SizedBox(width: 6.w),
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
      height: 34.h,
      child: Stack(
        children: [
          ListView.separated(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.symmetric(horizontal: pad),
            itemCount: items.length,
            separatorBuilder: (_, __) => SizedBox(width: 6.w),
            itemBuilder: (context, i) => KutePill(
              label: items[i].label,
              icon: items[i].icon,
              selected: _isSelected(i),
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
