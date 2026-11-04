// lib/screens/shared/kute_action_cards.dart
//
// BIG SQUARES, NOT LISTS (founder, 1 November 2026: "on these sheets when
// possible, instead of a list, big squares like modern fintech apps"). A
// sheet whose content is two to four actions or choices shows them as
// cards, in the style the Sal sheet's send cards set (commit 6dcf960f):
// surface-1 (the dark surface in dark mode), radius 20, a 1 px hairline,
// 16 padding, at least 170 tall; a large visual at the top left (a logo,
// Sal, an icon), the title (16, w600, two lines), up to two lines under
// it (13, textSecondary) and, optionally, the foot (13, w600, two lines);
// the press spring.
//
// [KuteActionCardGrid] lays them out:
//   1 card:  one full-width card;
//   2 cards: two equal cards side by side;
//   3 cards: three in a row where every title and line fits its card at
//            the sheet's width, else two side by side over one full width;
//   4 cards: a 2 × 2 grid.
// More than four (no sheet has that) continue in pairs, an odd last card
// full width. The cards of one row are equally tall, so their foot lines
// sit level.
//
// OPTION CARDS, THE SAME SQUARES, SMALLER (founder, 4 November 2026: the
// rows under a market's or a position's chart, "Add margin", "Rules and
// resolution", "should be like big squares"; "little cards, square-ish"):
// [KuteActionCard.option] is the card for a screen rather than a sheet,
// the options under the chart of the Investing and Predictions market
// and position screens, alike on both venues. The same surface, hairline
// and press spring; radius 18, 14 padding, at least 112 tall; an icon (22,
// primary text) at the top left, the title under it (15, w600, two lines)
// and, when the option has one, its value on one line (13, textSecondary:
// "Stop loss", "Ends Nov 5"). The text sits at the top, so the titles of
// a row sit level whether or not a card has a value. A tap gives the
// selection click the rows gave. The same grid lays them out, in two
// columns: a lone option card, or an odd last one, keeps its column (half
// the width, a square like the others) rather than a full-width band.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/screens/shared/kute_motion.dart' show KutePressable;
import 'package:kute/theme/app_theme.dart';

/// The space between the cards of a grid (design units, scaled by width).
const double kKuteActionCardGap = 12;

/// The least height of a card.
const double kKuteActionCardMinHeight = 170;

/// The card's inner padding.
const double kKuteActionCardPadding = 16;

/// The default height of the visual's box at the card's top; a 36 to 40
/// logo, Sal or icon sits in it, centred on its left edge.
const double kKuteActionCardVisualSlot = 40;

/// The size the converted sheets draw their visuals at.
const double kKuteActionCardVisualSize = 40;

/// The least height of an option card ([KuteActionCard.option]).
const double kKuteOptionCardMinHeight = 112;

/// An option card's inner padding.
const double kKuteOptionCardPadding = 14;

/// The height of an option card's icon box; its icon is drawn at
/// [kKuteOptionCardIconSize].
const double kKuteOptionCardVisualSlot = 24;

/// The size of an option card's icon.
const double kKuteOptionCardIconSize = 22;

/// One big action card (see the file header). A null [onTap] draws the
/// card disabled (0.6 opacity, no press); [badge] then reads at its top
/// right ("SELECTED", "SOON"), in the Move pickers' pill.
class KuteActionCard extends StatelessWidget {
  const KuteActionCard({
    super.key,
    required this.visual,
    required this.title,
    this.subtitle,
    this.footer,
    this.footerKey,
    this.badge,
    this.semanticsLabel,
    this.visualSlot = kKuteActionCardVisualSlot,
    required this.onTap,
  }) : compact = false;

  /// An option card (see the file header): [icon] at the top left, the
  /// [title] and, when the option has one, its value ([subtitle]) on one
  /// line.
  KuteActionCard.option({
    super.key,
    required IconData icon,
    required this.title,
    this.subtitle,
    this.semanticsLabel,
    required this.onTap,
  })  : visual = _KuteOptionIcon(icon),
        footer = null,
        footerKey = null,
        badge = null,
        visualSlot = kKuteOptionCardVisualSlot,
        compact = true;

  /// The large visual at the top left.
  final Widget visual;
  final String title;

  /// Up to two lines under the title.
  final String? subtitle;

  /// The line at the card's foot, up to two lines: what the action sends,
  /// for instance a market's whole name (founder, 2 November 2026: a
  /// market title cut to one line read "Michigan Senate Electio…").
  final String? footer;
  final Key? footerKey;

  /// A pill at the top right; meant for a disabled card.
  final String? badge;

  /// The label read out; defaults to the title and the line under it.
  final String? semanticsLabel;

  /// The height of the visual's box.
  final double visualSlot;

  /// Null: disabled.
  final VoidCallback? onTap;

  /// An option card ([KuteActionCard.option]): smaller, the text at the
  /// top, the value on one line.
  final bool compact;

  bool get enabled => onTap != null;

  /// The title's style (shared with the grid's fit measurement).
  static TextStyle titleStyle(AppColorsExtension c) => TextStyle(
        color: c.textPrimary,
        fontSize: 16.sp,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        height: 1.2,
      );

  /// The style of the lines under the title.
  static TextStyle subtitleStyle(AppColorsExtension c) => TextStyle(
        color: c.textSecondary,
        fontSize: 13.sp,
        fontWeight: FontWeight.w500,
        height: 1.3,
      );

  /// An option card's title style.
  static TextStyle optionTitleStyle(AppColorsExtension c) => TextStyle(
        color: c.textPrimary,
        fontSize: 15.sp,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        height: 1.2,
      );

  /// This card's title style.
  TextStyle titleStyleOf(AppColorsExtension c) =>
      compact ? optionTitleStyle(c) : titleStyle(c);

  /// How many lines this card's [subtitle] takes at most.
  int get subtitleMaxLines => compact ? 1 : 2;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final badgeText = badge;
    final foot = footer;
    final card = Container(
      constraints: BoxConstraints(
          minHeight:
              compact ? kKuteOptionCardMinHeight : kKuteActionCardMinHeight),
      padding: EdgeInsets.all(
          compact ? kKuteOptionCardPadding : kKuteActionCardPadding),
      decoration: BoxDecoration(
        color: isLight ? c.surfaceLight : c.surface,
        borderRadius: BorderRadius.circular(compact ? 18 : 20),
        border:
            Border.all(color: isLight ? c.border : c.borderSubtle, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: visualSlot,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Align(alignment: Alignment.centerLeft, child: visual),
                ),
                if (badgeText != null)
                  Align(
                    alignment: Alignment.topRight,
                    child: Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                      decoration: BoxDecoration(
                        color: c.textPrimary.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                      child: Text(
                        badgeText,
                        maxLines: 1,
                        style: TextStyle(
                          color: c.textTertiary,
                          fontSize: 11.sp,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(height: compact ? 10 : 12),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: titleStyleOf(c),
          ),
          if (subtitle != null) ...[
            SizedBox(height: compact ? 2 : 4),
            Text(
              subtitle!,
              maxLines: subtitleMaxLines,
              overflow: TextOverflow.ellipsis,
              style: subtitleStyle(c),
            ),
          ],
          // An option card's text stays at the top; a big card's foot sits
          // at its bottom.
          if (!compact) const Spacer(),
          if (foot != null && foot.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              foot,
              key: footerKey,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ],
      ),
    );
    return Semantics(
      button: true,
      enabled: enabled ? null : false,
      label: semanticsLabel ??
          [title, if (subtitle != null) subtitle!, if (badgeText != null) badgeText]
              .join(', '),
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled ? 1 : 0.6,
        child: KutePressable(
          enabled: enabled,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: compact && onTap != null
                ? () {
                    HapticFeedback.selectionClick();
                    onTap!();
                  }
                : onTap,
            child: card,
          ),
        ),
      ),
    );
  }
}

/// An option card's icon, at the left of its box.
class _KuteOptionIcon extends StatelessWidget {
  const _KuteOptionIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) => Icon(icon,
      size: kKuteOptionCardIconSize, color: context.colors.textPrimary);
}

/// Lays out 1 to 4 [cards] (see the file header).
class KuteActionCardGrid extends StatelessWidget {
  const KuteActionCardGrid({
    super.key,
    required this.cards,
    this.gap = kKuteActionCardGap,
  });

  final List<KuteActionCard> cards;

  /// The space between cards, in design units (scaled by width).
  final double gap;

  /// Whether every card's title and line fit a card [cardWidth] wide
  /// without an ellipsis or a word broken across lines.
  static bool labelsFit(
    BuildContext context,
    List<KuteActionCard> cards,
    double cardWidth,
  ) {
    final c = context.colors;
    final padding = cards.any((card) => !card.compact)
        ? kKuteActionCardPadding
        : kKuteOptionCardPadding;
    final inner = cardWidth - 2 * padding;
    if (inner <= 0) return false;
    final base = DefaultTextStyle.of(context).style;
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    bool fits(String text, TextStyle style, {int maxLines = 2}) {
      final s = base.merge(style);
      // A single word wider than the card would break mid-word.
      for (final word in text.split(RegExp(r'\s+'))) {
        if (word.isEmpty) continue;
        final w = TextPainter(
          text: TextSpan(text: word, style: s),
          textDirection: direction,
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        final wide = w.width > inner;
        w.dispose();
        if (wide) return false;
      }
      final p = TextPainter(
        text: TextSpan(text: text, style: s),
        textDirection: direction,
        textScaler: scaler,
        maxLines: maxLines,
      )..layout(maxWidth: inner);
      final over = p.didExceedMaxLines;
      p.dispose();
      return !over;
    }

    for (final card in cards) {
      if (!fits(card.title, card.titleStyleOf(c))) return false;
      final sub = card.subtitle;
      if (sub != null &&
          !fits(sub, KuteActionCard.subtitleStyle(c),
              maxLines: card.subtitleMaxLines)) {
        return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final g = gap.w;
    final space = SizedBox(width: g, height: g);
    // A card's foot sits at its bottom: each card is as tall as the
    // tallest of its row (IntrinsicHeight; a visual has a fixed box).
    Widget row(List<KuteActionCard> items) => IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) space,
                Expanded(child: items[i]),
              ],
            ],
          ),
        );
    // Option cards keep their column: a lone or odd last one is half the
    // width, the other half left empty.
    final columns = cards.every((card) => card.compact);
    Widget single(KuteActionCard card) => IntrinsicHeight(
          child: columns
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: card),
                    space,
                    const Expanded(child: SizedBox.shrink()),
                  ],
                )
              : card,
        );

    if (cards.isEmpty) return const SizedBox.shrink();
    if (cards.length == 1) return single(cards.first);
    if (cards.length == 3) {
      return LayoutBuilder(builder: (context, constraints) {
        final third = (constraints.maxWidth - 2 * g) / 3;
        final across = constraints.hasBoundedWidth &&
            labelsFit(context, cards, third);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: across
              ? [row(cards)]
              : [row(cards.sublist(0, 2)), space, single(cards[2])],
        );
      });
    }
    final children = <Widget>[];
    for (var i = 0; i < cards.length; i += 2) {
      if (i > 0) children.add(space);
      children.add(i + 1 < cards.length
          ? row(cards.sublist(i, i + 2))
          : single(cards[i]));
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}
