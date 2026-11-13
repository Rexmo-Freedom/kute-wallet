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
// A TABS ROW OF THREE OR FEWER (the Bitcoin | Investments halves, the
// Activity / Balance / Price pills) has ONE white pill that SLIDES between
// the tabs on the chip spring (founder, 31 October 2026: "attention to the
// animations on everything"; [_SlidingIndicator]) instead of each tab
// fading its own chrome in and out: the pills themselves are flat
// ([KutePill.flat]) and only their labels change weight and colour. At
// once under Reduce Motion.
//
// A PILL'S WORDS MORPH (founder, 6 November 2026: a category picked in
// the category sheet moves as a pill switch does): when they change
// ("Predictions" → "Predictions · Live"), their box eases to the new width
// on the chip spring with the pill's own, the new words fading in from
// the start of the line and the old fading out ([_PillWords]); never a
// jump, never squeezed into a pill still on its way. At once under Reduce
// Motion.
//
// A pill that holds more (the Investments pills, founder 31 October
// 2026: "it should be more clear that we have much more context here")
// carries its context after its name in the quieter weight ("Investing ·
// Trending", [KutePillItem.detail]) and a chevron in a small filled
// circle at its end ([KutePillItem.menu]), so it reads as a control and
// not as decoration.
//
// EVERY SWITCH ROW IS ONE SIZE (founder, 2 November 2026: "these buttons,
// now that we have space, should be as big as these"): a tabs row of three
// or fewer (the Dollars Investing | Predictions halves, the Bitcoin home's
// See all | Balance, the Portfolio's Portfolio | P&L Charts, Add | Remove
// margin) is drawn at [kutePillSwitchSize] unless it asks for another.
//
// NOTHING IN A SWITCH IS CUT (founder, 2 November 2026: "stuff gets cut
// here"): the halves stay equal while the picked pill's words fit its
// half; when they do not ("Investing · Stocks and shares ⌄"), the others
// hug their own words and the picked pill takes the rest of the row, the
// widths moving on the same chip spring as the white pill. Still too long,
// the picked pill reads its shorter context ([KutePillItem.shortDetail]),
// and as a last resort its words shrink to fit rather than being clipped.
//
// THREE PILLS (the Dollars switch, Activity · Investing · Predictions,
// founder 4 November 2026) leave the picked one less room: the others
// always hug their own words (a long name, Greek's "Δραστηριότητα", is
// never squeezed into an equal third), and a context that would still
// shrink the picked pill's words below [kutePillMinTextScale] is left off
// (the name and its chevron alone, "Investing ⌄"): never half-size words.
// The category sheet the chevron opens names it.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;
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

  /// A shorter [detail] for when the full one does not fit the row (the
  /// subcategory alone, "Commodities" for "Stocks and shares ·
  /// Commodities"); null keeps [detail].
  final String? shortDetail;

  /// A chevron in a small filled circle at the pill's end: the pill opens
  /// a pick when tapped again.
  final bool menu;

  /// The pill's own key (tests find a pill by it).
  final Key? key;

  const KutePillItem({
    required this.label,
    this.icon,
    this.leading,
    this.detail,
    this.shortDetail,
    this.menu = false,
    this.key,
  });
}

/// The one size of every switch row (a tabs row of three or fewer): the
/// Dollars Investing | Predictions halves' size.
const KutePillSize kutePillSwitchSize = KutePillSize.large;

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

  /// No chrome of its own (a row whose white pill slides under the tabs,
  /// [KutePillTabs]): the label still reads selected or not.
  final bool flat;

  /// The fill of the pill while it is not the picked one; null leaves it
  /// transparent (every strip on the page's own ground). On a card, where
  /// words alone would float, a row of rounds gives each its quiet fill so
  /// every one reads as a pill (the live round card's strip, founder, 12
  /// November 2026: "each a proper pill").
  final Color? restingFill;

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
    this.flat = false,
    this.restingFill,
  });

  /// The selected pill's card chrome, shared with the sliding indicator.
  static BoxDecoration chrome(BuildContext context, {required bool selected}) {
    final c = context.colors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    return BoxDecoration(
      color: selected ? (isLight ? Colors.white : c.surface) : Colors.transparent,
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
    );
  }

  /// The label's style. Merged onto the inherited style:
  /// AnimatedDefaultTextStyle replaces it, and would drop the theme's
  /// Inter for the platform font.
  static TextStyle _labelStyle(
          BuildContext context, KutePillSize size, bool selected) =>
      DefaultTextStyle.of(context).style.merge(TextStyle(
            fontSize: size.font.sp,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected
                ? context.colors.textPrimary
                : context.colors.textTertiary,
            letterSpacing: 0.1,
            height: 1.0,
          ));

  static TextStyle _detailStyle(BuildContext context, TextStyle label) =>
      label.copyWith(
          fontWeight: FontWeight.w500, color: context.colors.textSecondary);

  /// The width a pill needs to show all of its words on one line: its
  /// padding, the chrome's border, the glyph, the label (and " · detail")
  /// and the chevron. A pill with a [leading] image is not measured
  /// (null).
  static double? naturalWidth(
    BuildContext context, {
    required KutePillItem item,
    required bool selected,
    required KutePillSize size,
    String? detail,
  }) {
    if (item.leading != null) return null;
    final label = _labelStyle(context, size, selected);
    final painter = TextPainter(
      text: TextSpan(style: label, children: [
        TextSpan(text: item.label),
        if (detail != null)
          TextSpan(text: ' · $detail', style: _detailStyle(context, label)),
      ]),
      textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
      textScaler: MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling,
      maxLines: 1,
    )..layout();
    final text = painter.width;
    painter.dispose();
    final isLight = Theme.of(context).brightness == Brightness.light;
    final border = isLight ? 1.0 : 0.5;
    return 2 * size.hPad.w +
        2 * border +
        (item.icon != null ? size.icon.sp + 6.w : 0) +
        text +
        (item.menu ? 4.w + size.icon.sp : 0) +
        // A hair of room so rounding never clips the last glyph.
        1;
  }

  /// The words' own width on one line ("Predictions · Live"), in [style]
  /// with the context in [detailStyle], as a Text lays them out: the width
  /// the words' box springs to ([_PillWords]).
  double _wordsWidth(
      BuildContext context, TextStyle style, TextStyle detailStyle) {
    final painter = TextPainter(
      text: TextSpan(style: style, children: [
        TextSpan(text: label),
        if (detail != null) TextSpan(text: ' · $detail', style: detailStyle),
      ]),
      textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
      textScaler: MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  /// A pill sharing a row at a set width (fillWidth): its words shrink to
  /// that width rather than being clipped. A natural-width pill is as wide
  /// as its words already.
  Widget _shrinkToFit(Widget text) => fillWidth
      ? FittedBox(fit: BoxFit.scaleDown, child: text)
      : text;

  /// The words in the label row: as they are inside the fitted box (which
  /// lays them out unbounded), or flexible in a natural-width pill so a
  /// long label still gives way to the chevron.
  Widget _flexibleUnlessFitted(Widget words) =>
      fillWidth ? words : Flexible(child: words);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = selected ? c.textPrimary : c.textTertiary;
    final reduce = kuteReduceMotion(context);
    // The chrome springs between its two states (KuteMotion.chip).
    final duration = reduce ? Duration.zero : KuteMotion.chipDuration;
    final curve = reduce ? Curves.linear : KuteMotion.chip;
    final textStyle = _labelStyle(context, size, selected);
    final detailStyle = _detailStyle(context, textStyle);

    final chip = AnimatedContainer(
      duration: duration,
      curve: curve,
      padding:
          EdgeInsets.symmetric(horizontal: size.hPad.w, vertical: size.vPad.h),
      // Flat: the border still takes its room, so the label sits where it
      // does in a pill with chrome.
      decoration: selected || flat || restingFill == null
          ? KutePill.chrome(context, selected: selected && !flat)
          : KutePill.chrome(context, selected: false)
              .copyWith(color: restingFill),
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
          // The words, and the chevron after them. Sharing a row at a set
          // width (fillWidth) they shrink together, never past the pill:
          // a pill that just became the picked one starts its spring at its
          // old, narrower width with the chevron already on (three pills,
          // Japanese "予測": the chevron alone was wider than the room).
          Flexible(
            child: _shrinkToFit(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _flexibleUnlessFitted(
                    AnimatedDefaultTextStyle(
                      duration: duration,
                      // A text-style lerp never rides the spring: past 1 it
                      // extrapolates (a shadow's blur negative); the settle.
                      curve: reduce ? Curves.linear : KuteMotion.textCurve,
                      style: textStyle,
                      // The words morph when they change (a category
                      // picked, a pill picked or let go), with the pill's
                      // width on the chip spring ([_PillWords]).
                      child: _PillWords(
                        reduce: reduce,
                        width: _wordsWidth(context, textStyle, detailStyle),
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(text: label),
                            // The context after the name, quieter.
                            if (detail != null)
                              TextSpan(text: ' · $detail', style: detailStyle),
                          ]),
                          key: ValueKey<String>('$label\u0000${detail ?? ''}'),
                          semanticsLabel: semanticLabel,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          softWrap: false,
                        ),
                      ),
                    ),
                  ),
                  // A small plain chevron (founder, 31 October 2026: no
                  // circle). It takes the words' line, never more height:
                  // a glyph a hair taller than the line would otherwise
                  // shrink the words with it.
                  if (menu) ...[
                    SizedBox(width: 4.w),
                    SizedBox(
                      width: size.icon.sp,
                      height: 0,
                      child: OverflowBox(
                        minHeight: 0,
                        maxHeight: size.icon.sp,
                        child: Icon(Icons.expand_more_rounded,
                            size: size.icon.sp, color: c.textSecondary),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
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

/// The length of a pill's words morph: the chip spring's, so the words
/// and the pill's width (and the white pill under it) move as one.
const Duration kutePillWordsMorphDuration = KuteMotion.chipDuration;

/// A pill's words, morphing when they change ("Predictions" →
/// "Predictions · Live" as a category is picked, or as the pill is picked;
/// founder, 6 November 2026: a pick moves as a pill switch does). Their
/// box eases from the old words' width to the new words' [width] (measured
/// as [KutePill.naturalWidth] measures them) on the chip spring held to
/// its end, from the same frame as the pill's own width ([_SwitchLayout]),
/// so the words keep step with the pill and are never squeezed into a pill
/// still on its way; the new words fade in from the start of the line as
/// the box opens, the old fade out over them from the same start (the name
/// they share does not move). Only the width clips, never a glyph above or
/// below the line. At once under Reduce Motion. [child] is the words,
/// keyed by what they say.
class _PillWords extends StatelessWidget {
  const _PillWords(
      {required this.child, required this.width, required this.reduce});

  final Widget child;
  final double width;
  final bool reduce;

  @override
  Widget build(BuildContext context) {
    final duration = reduce ? Duration.zero : kutePillWordsMorphDuration;
    return ClipRect(
      clipper: const _ClipAcross(),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: width),
        duration: duration,
        // The chip spring held to its end: the box never runs past the
        // new words, so a pill growing into a tight fit never squeezes
        // them at its overshoot (the pill's chrome still bounces).
        curve: reduce ? Curves.linear : KuteMotion.clamped(KuteMotion.chip),
        builder: (context, w, words) =>
            SizedBox(width: math.max(0.0, w), child: words),
        // The words at their own width whatever the box's; the box clips.
        child: OverflowBox(
          alignment: AlignmentDirectional.centerStart,
          minWidth: 0,
          maxWidth: double.infinity,
          fit: OverflowBoxFit.deferToChild,
          child: AnimatedSwitcher(
            duration: duration,
            // A fade never rides the spring (an opacity past 1); the settle.
            switchInCurve: reduce ? Curves.linear : KuteMotion.textCurve,
            switchOutCurve: reduce ? Curves.linear : KuteMotion.textCurve,
            // Sized by the new words alone; the old ones sit at the same
            // start while they fade.
            layoutBuilder: (current, previous) => Stack(
              clipBehavior: Clip.none,
              alignment: AlignmentDirectional.centerStart,
              children: [
                for (final old in previous)
                  PositionedDirectional(
                      start: 0, top: 0, bottom: 0, child: old),
                if (current != null) current,
              ],
            ),
            transitionBuilder: (child, animation) =>
                FadeTransition(opacity: animation, child: child),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Clips across only: the words' box at its width, with room above and
/// below for the glyphs that rise or fall past a 1.0 line height.
class _ClipAcross extends CustomClipper<Rect> {
  const _ClipAcross();

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(-1, -size.height, size.width + 1, size.height * 2);

  @override
  bool shouldReclip(_ClipAcross oldClipper) => false;
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

  /// The pills' size (see [KutePillSize]); null: [kutePillSwitchSize] for
  /// a switch row (tabs, three or fewer, not scrolling), regular for the
  /// rest.
  final KutePillSize? size;

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
    this.size,
    this.height,
    this.scroll = false,
  });

  /// A switch row: tabs, three or fewer, sharing the width.
  bool get _isSwitch =>
      selectedIndex != null && items.length <= 3 && !scroll;

  /// The size the row draws at (see [size]).
  KutePillSize get resolvedSize =>
      size ?? (_isSwitch ? kutePillSwitchSize : KutePillSize.regular);

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
    final size = widget.resolvedSize;
    final height = widget.height ?? size.height.h;

    // Tabs with three or fewer entries fit comfortably in one row: give
    // each equal width so they're evenly spaced. Four or more truncated
    // the labels under equal widths ("Activit", "Balanc"), so longer
    // strips side-scroll at natural width instead.
    if (widget._isSwitch) {
      final selected = widget.selectedIndex!.clamp(0, items.length - 1);
      final reduce = kuteReduceMotion(context);
      final duration = reduce ? Duration.zero : KuteMotion.chipDuration;
      final curve = reduce ? Curves.linear : KuteMotion.chip;
      return SizedBox(
        height: height,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: pad),
          child: LayoutBuilder(
            builder: (context, box) {
              final layout = _SwitchLayout.of(context, items, selected, size,
                  box.maxWidth, gap);
              // Each tab and the white pill under the picked one move on
              // the chip spring together (at once under Reduce Motion):
              // positioned, so a spring's overshoot never overflows a row.
              return Stack(
                children: [
                  _SlidingIndicator(
                    left: layout.lefts[selected],
                    width: layout.widths[selected],
                    rowHeight: box.maxHeight,
                    duration: duration,
                    curve: curve,
                    size: size,
                  ),
                  for (int i = 0; i < items.length; i++)
                    AnimatedPositioned(
                      duration: duration,
                      curve: curve,
                      left: layout.lefts[i],
                      width: layout.widths[i],
                      top: 0,
                      bottom: 0,
                      child: KutePill(
                        key: items[i].key,
                        label: items[i].label,
                        icon: items[i].icon,
                        leading: items[i].leading,
                        detail: i == selected
                            ? layout.selectedDetail
                            : items[i].detail,
                        menu: items[i].menu,
                        selected: _isSelected(i),
                        fillWidth: true,
                        flat: true,
                        size: size,
                        onTap: () => widget.onTap(i),
                      ),
                    ),
                ],
              );
            },
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
              key: items[i].key,
              label: items[i].label,
              icon: items[i].icon,
              leading: items[i].leading,
              detail: items[i].detail,
              menu: items[i].menu,
              selected: _isSelected(i),
              size: size,
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

/// Where a switch row's tabs stand: equal halves (thirds) while the
/// picked tab's words fit its share; otherwise the other tabs hug their
/// own words and the picked tab takes the rest, reading its shorter
/// context when the full one still does not fit.
class _SwitchLayout {
  _SwitchLayout(this.widths, this.lefts, this.selectedDetail);

  final List<double> widths;
  final List<double> lefts;
  final String? selectedDetail;

  factory _SwitchLayout.of(BuildContext context, List<KutePillItem> items,
      int selected, KutePillSize size, double maxWidth, double gap) {
    final n = items.length;
    final room = math.max(0.0, maxWidth - gap * (n - 1));
    final equal = room / n;
    final picked = items[selected];
    var detail = picked.detail;
    var widths = List<double>.filled(n, equal);
    double? need(KutePillItem item, bool sel, String? d) =>
        KutePill.naturalWidth(context,
            item: item, selected: sel, size: size, detail: d);
    final full = need(picked, true, detail);
    // The others' own words. Two pills keep the old rule (the other never
    // wider than its half); three or more never squeeze a long name into
    // an equal share (see the file header).
    final hug = <double>[
      for (var i = 0; i < n; i++)
        if (i == selected)
          0
        else if (n > 2)
          need(items[i], false, items[i].detail) ?? equal
        else
          math.min(equal, need(items[i], false, items[i].detail) ?? equal),
    ];
    final othersFit = hug.every((w) => w <= equal);
    if ((full != null && full > equal) || !othersFit) {
      final rest = room - hug.fold<double>(0, (a, b) => a + b);
      widths = [
        for (var i = 0; i < n; i++) i == selected ? rest : hug[i],
      ];
      if (full != null && full > rest && picked.shortDetail != null) {
        detail = picked.shortDetail;
        // The shorter context back in its half: the halves equal again.
        final short = need(picked, true, detail);
        if (short != null && short <= equal && othersFit) {
          widths = List<double>.filled(n, equal);
        }
      }
      // Three pills: a context still too long for the room left is left
      // off rather than shrunk past [kutePillMinTextScale].
      if (n > 2 && detail != null) {
        final now = need(picked, true, detail);
        // The words' own scale: the pill's chrome (padding, border,
        // chevron) never shrinks.
        final chrome = need(
            KutePillItem(label: '', icon: picked.icon, menu: picked.menu),
            true,
            null);
        if (now != null && chrome != null && now > chrome) {
          final scale = (rest - chrome) / (now - chrome);
          if (scale < kutePillMinTextScale) detail = null;
        }
      }
    }
    final lefts = <double>[];
    var x = 0.0;
    for (final w in widths) {
      lefts.add(x);
      x += w + gap;
    }
    return _SwitchLayout(widths, lefts, detail);
  }
}

/// The sliding white pill's key, for tests.
const Key kutePillIndicatorKey = ValueKey('kute-pill-indicator');

/// The least a switch's picked pill may shrink its words to fit its room
/// before its context is left off ([_SwitchLayout]).
const double kutePillMinTextScale = 0.9;

/// The white pill under a tabs row of three or fewer: the selected chrome
/// ([KutePill.chrome]) as one card that slides between the tabs. Its
/// height is a pill's own ([KutePillSize.height]), centred in the row.
class _SlidingIndicator extends StatelessWidget {
  const _SlidingIndicator({
    required this.left,
    required this.width,
    required this.rowHeight,
    required this.duration,
    required this.curve,
    required this.size,
  });

  final double left;
  final double width;
  final double rowHeight;
  final Duration duration;
  final Curve curve;
  final KutePillSize size;

  @override
  Widget build(BuildContext context) {
    final pillHeight = math.min(rowHeight, size.height.h);
    return AnimatedPositioned(
      key: kutePillIndicatorKey,
      duration: duration,
      curve: curve,
      left: left,
      width: width,
      top: (rowHeight - pillHeight) / 2,
      height: pillHeight,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: KutePill.chrome(context, selected: true),
        ),
      ),
    );
  }
}
