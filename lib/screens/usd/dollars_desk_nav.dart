// lib/screens/usd/dollars_desk_nav.dart
//
// THE DOLLARS PAGE'S LEFT NAVIGATION ON A LAPTOP (founder, 24 November
// 2026, of the three stacked rows of pills and chips over the browse:
// "also these layers deep, I don't like it. Even on desktop … make use of
// the left side of the screen, which is empty now, for this please").
//
// On EXPANDED from [kuteDeskNavMinWidth] the Dollars page's whole
// hierarchy is ONE tree down the left side, under the top bar, its left
// edge on the logo's line ([kuteDeskGutter]):
//
//   * the three sections (Overview, Investing, Predictions), the pills'
//     own names, at the pills' large size;
//   * under the open section its categories, the chips' own labels in
//     the chips' order ([InvestmentsCategoryChips] with `tree: true`:
//     the same handlers, the same events and sources);
//   * under the open category its subcategories, indented, shown for that
//     category only so the list stays readable.
//
// The picked item wears the picked pill's surface and words
// ([KutePill.chrome]); the picked items above it (the open section, the
// open category) wear the picked words alone, so the path reads at a
// glance with one surface on it, never three boxes nested; the others are
// the chips' quiet words. The column
// scrolls on its own when Predictions' list is taller than the window
// (the picked item brought into view), and stays put while the browse
// scrolls. Narrower windows (900 to [kuteDeskNavMinWidth]) keep the pills
// and the chips over the browse; MEDIUM and a phone are untouched.
//
// Every item leads with its icon (founder, 25 November 2026: "also why no
// icons here?"; dollars_desk_nav_icons.dart), in one column so the words
// of a list line up. The column scrolls with the wheel, the trackpad and
// a mouse drag, and its end has room under the last item so it clears the
// window's foot.

import 'package:flutter/gestures.dart' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:kute/screens/shared/kute_motion.dart'
    show KutePressable, kuteReduceMotion;
import 'package:kute/screens/shared/kute_pill_tabs.dart'
    show KutePill, KutePillSize;
import 'package:kute/screens/usd/dollars_desk_nav_icons.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/theme/kute_motion.dart';

/// One section of the left navigation (Overview, Investing, Predictions).
typedef DollarsDeskNavSection = ({
  Key key,
  String label,
  bool selected,
  VoidCallback onTap,
});

/// The left navigation: the [sections], and under the picked one its
/// [categories] (the tree of [InvestmentsCategoryChips], or null for a
/// section with none, the Overview).
class DollarsDeskNav extends StatelessWidget {
  const DollarsDeskNav({
    super.key,
    required this.sections,
    this.categories,
    this.top = 0,
  });

  final List<DollarsDeskNavSection> sections;
  final Widget? categories;

  /// The room over the first item, so it stands on the browse's first
  /// line.
  final double top;

  /// The room under the last item, so it clears the window's foot.
  static const double bottomRoom = 48;

  /// The section's [InvestmentsTab] key, read off its item's key
  /// (`dollars-desk-nav-<key>`), for its icon.
  static String? _sectionId(Key key) {
    const prefix = 'dollars-desk-nav-';
    return key is ValueKey<String> && key.value.startsWith(prefix)
        ? key.value.substring(prefix.length)
        : null;
  }

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        scrollbars: false,
        // The wheel and the trackpad scroll any list; a mouse drag too.
        dragDevices: const {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.stylus,
          PointerDeviceKind.invertedStylus,
        },
      ),
      child: SingleChildScrollView(
        key: const ValueKey('dollars-desk-nav'),
        // Never the page's primary scroll: the browse owns that.
        primary: false,
        padding: EdgeInsets.only(
            top: top,
            bottom: bottomRoom + MediaQuery.viewPaddingOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, s) in sections.indexed) ...[
              if (i > 0) const SizedBox(height: 2),
              DollarsDeskNavItem(
                key: s.key,
                label: s.label,
                selected: s.selected,
                onTap: s.onTap,
                level: 0,
                leading: switch (_sectionId(s.key)) {
                  final id? => deskNavSectionIcon(id),
                  null => null,
                },
                // The open section's categories carry the surface.
                ancestor: s.selected && categories != null,
              ),
              if (s.selected && categories != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: categories,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One row of the left navigation, at [level] 0 (a section), 1 (a
/// category) or 2 (a subcategory, indented under its category). Picked,
/// the picked pill's surface and words; otherwise the chips' quiet words,
/// a shade stronger under the pointer. [leading] is its icon, in its
/// words' colour (the ambient [IconTheme]). [trailing] is a quiet action
/// at the row's end (the Watchlist's Edit).
class DollarsDeskNavItem extends StatefulWidget {
  const DollarsDeskNavItem({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.level = 1,
    this.trailing,
    this.ancestor = false,
    this.leading,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int level;
  final ({Key key, String label, VoidCallback onTap})? trailing;

  /// The icon before the words ([kDeskNavIconSlot] square).
  final Widget? leading;

  /// Picked, with the pick going on under it (the open section, a
  /// category whose subcategory is picked): the picked words without the
  /// surface.
  final bool ancestor;

  /// How far a subcategory sits in from its category's words.
  static const double subIndent = 14;

  @override
  State<DollarsDeskNavItem> createState() => _DollarsDeskNavItemState();
}

class _DollarsDeskNavItemState extends State<DollarsDeskNavItem> {
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    if (widget.selected && !widget.ancestor) _reveal();
  }

  @override
  void didUpdateWidget(covariant DollarsDeskNavItem old) {
    super.didUpdateWidget(old);
    if (widget.selected &&
        !widget.ancestor &&
        (!old.selected || old.ancestor)) {
      _reveal();
    }
  }

  /// The picked item brought into the column's view, if it is out of it.
  void _reveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || Scrollable.maybeOf(context) == null) return;
      final duration = kuteReduceMotion(context)
          ? Duration.zero
          : KuteMotion.settleDuration;
      for (final policy in const [
        ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      ]) {
        Scrollable.ensureVisible(context,
            alignmentPolicy: policy,
            duration: duration,
            curve: KuteMotion.settle);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final size = widget.level == 0 ? KutePillSize.large : KutePillSize.regular;
    final selected = widget.selected;
    final reduce = kuteReduceMotion(context);
    final duration = reduce ? Duration.zero : KuteMotion.chipDuration;
    // The pill's own words (kute_pill_tabs.dart): bold primary picked,
    // the quiet tertiary otherwise, the secondary under the pointer.
    final style = DefaultTextStyle.of(context).style.merge(TextStyle(
          fontSize: size.font,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected
              ? c.textPrimary
              : _hover
                  ? c.textSecondary
                  : c.textTertiary,
          letterSpacing: 0.1,
          height: 1.2,
        ));
    final trailing = widget.trailing;
    final leading = widget.leading;
    final row = AnimatedContainer(
      duration: duration,
      curve: reduce ? Curves.linear : KuteMotion.chip,
      constraints: BoxConstraints(minHeight: widget.level == 0 ? 40 : 36),
      padding: EdgeInsets.only(
        left: size.hPad +
            (widget.level == 2 ? DollarsDeskNavItem.subIndent : 0),
        right: 8,
      ),
      decoration:
          KutePill.chrome(context, selected: selected && !widget.ancestor),
      child: Row(
        children: [
          if (leading != null) ...[
            IconTheme.merge(
              data: IconThemeData(color: style.color, size: kDeskNavGlyph),
              child: SizedBox.square(
                  dimension: kDeskNavIconSlot, child: leading),
            ),
            const SizedBox(width: kDeskNavIconGap),
          ],
          Expanded(
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: style,
            ),
          ),
          if (trailing != null)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                key: trailing.key,
                behavior: HitTestBehavior.opaque,
                onTap: trailing.onTap,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: Text(
                    trailing.label,
                    style: style.copyWith(
                        fontWeight: FontWeight.w600,
                        color: c.textSecondary),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: KutePressable(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: row,
          ),
        ),
      ),
    );
  }
}
