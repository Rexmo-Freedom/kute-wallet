// lib/screens/shared/kute_action_cards.dart
//
// BIG SQUARES, NOT LISTS (founder, 1 November 2026: "on these sheets when
// possible, instead of a list, big squares like modern fintech apps"). A
// sheet whose content is two to four actions or choices shows them as
// cards, in the style the Sal sheet's send cards set (commit 6dcf960f):
// surface-1 (the dark surface in dark mode), radius 20, a 1 px hairline,
// 16 padding; a large visual at the top left (a logo, Sal, an icon), the
// title (16, w600), the lines under it (13, textSecondary) and,
// optionally, the foot (13, w600, two lines); the press spring. The title
// and its lines are never cut (founder, 5 November 2026: "this is cut"):
// they wrap to the lines they need, and the cards of a row grow together.
// A card is as tall as what it holds, never padded to a floor (5 November
// 2026: the Dollars Send's squares stood half empty under the old 170
// floor): the tallest card of a row sets the row, and a visual, a title
// and two lines under it make a square-ish card at a phone's width.
//
// [KuteActionCardGrid] lays them out:
//   1 card:  the lone card, full width and compact (founder, 5 November
//            2026, the Bitcoin Send's lone "Also sends to": "here no need
//            to be as big"): the visual at its left, the title and its
//            lines beside it, a chevron at its right (a disabled card's
//            badge in its place); as tall as that, no taller;
//   2 cards: two equal squares side by side;
//   3 cards: three in a row where every title and line fits its card at
//            the sheet's width, else two squares over one full-width
//            card laid out as the lone one;
//   4 cards: a 2 × 2 grid.
// More than four (no sheet has that) continue in pairs, an odd last card
// full width as the lone one. Never a square alone in half the width and
// never a square stretched across the whole width: a full-width card is
// the compact one. The squares of one row are equally tall, so their foot
// lines sit level.
//
// THE MAIN ACTION ON TOP (founder, 7 November 2026, the Bitcoin Receive:
// "Bitcoin should be on top, more prevalent here"): a grid given a
// [KuteActionCardGrid.lead] draws it first, full width and with more
// presence than the compact full-width card (a larger visual box, title
// and chevron, more padding), and lays the other cards out under it by
// the rules above: two squares side by side, one compact full width, or
// none at all.
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
// selection click the rows gave.
//
// The same grid lays them out in two columns and never leaves a card
// alone in half the width (founder, 5 November 2026: "Here there is more
// space, it can be Rules and resolution bigger ... adapt the cards to
// when there are fewer elements, like 1 or 3"):
//   1 card:  the lone card, full width and with more presence: a larger
//            icon (28) and title (17), the value, and the option's
//            [KuteActionCard.detail] when it has one (two lines, 13,
//            textSecondary: the first line of a market's rules), a chevron
//            at its right; as tall as that content, no taller (a
//            position's actions row, [KuteActionCardGrid.compactLone],
//            keeps the squares' sizes instead: one action never
//            outweighs the tiles under it);
//   2 cards: two squares side by side;
//   3 cards: two squares over one full-width card;
//   4 cards: a 2 x 2 grid; 5: 2 x 2 over one full width; and so on, an odd
//            last card full width.
// A full-width card under squares keeps their sizes (icon 22, title 15)
// and is laid out as the lone card is: its text at the left, the detail
// line when it has one, the chevron at its right. A square never shows
// the detail or a chevron.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/screens/shared/kute_motion.dart' show KutePressable;
import 'package:kute/theme/app_theme.dart';

/// The space between the cards of a grid (design units, scaled by width).
const double kKuteActionCardGap = 12;

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

/// The size of the lone option card's icon (see the file header).
const double kKuteOptionCardLoneIconSize = 28;

/// The lone option card's inner padding.
const double kKuteOptionCardLonePadding = 16;

/// The space between a full-width big card's visual and its text.
const double kKuteActionCardWideGap = 14;

/// The visual box of a grid's lead card ([KuteActionCardGrid.lead]).
const double kKuteActionCardLeadVisualSlot = 48;

/// The size the sheets draw a lead card's visual at.
const double kKuteActionCardLeadVisualSize = 48;

/// A lead card's inner padding.
const double kKuteActionCardLeadPadding = 18;

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
  })  : compact = false,
        detail = null;

  /// An option card (see the file header): [icon] at the top left, the
  /// [title] and, when the option has one, its value ([subtitle]) on one
  /// line; [detail], a helpful line more, only when the grid gives the
  /// card the full width.
  KuteActionCard.option({
    super.key,
    required IconData icon,
    required this.title,
    this.subtitle,
    this.detail,
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

  /// An option card's helpful line under its value, shown (two lines) only
  /// when it is laid out full width (see the file header): the first line
  /// of a market's rules. Null on the sheets' big cards.
  final String? detail;

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

  /// The lone option card's title style (see the file header).
  static TextStyle optionLoneTitleStyle(AppColorsExtension c) =>
      optionTitleStyle(c).copyWith(fontSize: 17.sp, letterSpacing: -0.3);

  /// The style of a full-width option card's [detail] line.
  static TextStyle optionDetailStyle(AppColorsExtension c) => TextStyle(
        color: c.textSecondary,
        fontSize: 13.sp,
        fontWeight: FontWeight.w400,
        height: 1.35,
      );

  /// This card's title style.
  TextStyle titleStyleOf(AppColorsExtension c) =>
      compact ? optionTitleStyle(c) : titleStyle(c);

  /// How many lines this card's [subtitle] takes at most.
  int get subtitleMaxLines => compact ? 1 : 2;

  /// The [detail] a full-width option card shows, null when blank.
  String? get _detailLine {
    final line = detail?.trim();
    return line == null || line.isEmpty ? null : line;
  }

  /// The card's surface: surface-1, the hairline, [radius] round.
  BoxDecoration _surface(AppColorsExtension c, bool isLight, double radius) =>
      BoxDecoration(
        color: isLight ? c.surfaceLight : c.surface,
        borderRadius: BorderRadius.circular(radius),
        border:
            Border.all(color: isLight ? c.border : c.borderSubtle, width: 1),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final span = _KuteCardSpan.of(context);
    final badgeText = badge;
    if (span != _CardSpan.square) {
      if (!compact) {
        return _interactive(
          _wideCard(c, isLight, lead: span == _CardSpan.lead),
          semanticsLabel ??
              [
                title,
                if (subtitle != null) subtitle!,
                if (footer != null && footer!.isNotEmpty) footer!,
                if (badgeText != null) badgeText,
              ].join(', '),
        );
      }
      final more = _detailLine;
      return _interactive(
        _wideOption(c, isLight, lone: span == _CardSpan.lone),
        semanticsLabel ??
            [title, if (subtitle != null) subtitle!, if (more != null) more]
                .join(', '),
      );
    }
    final foot = footer;
    final card = Container(
      // An option card keeps its floor; a big card is as tall as what it
      // holds (the row's tallest sets the row; see the file header).
      constraints: compact
          ? const BoxConstraints(minHeight: kKuteOptionCardMinHeight)
          : null,
      padding: EdgeInsets.all(
          compact ? kKuteOptionCardPadding : kKuteActionCardPadding),
      decoration: _surface(c, isLight, compact ? 18 : 20),
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
                    child: _badgePill(c, badgeText),
                  ),
              ],
            ),
          ),
          SizedBox(height: compact ? 10 : 12),
          // A big card's title wraps whole too (French "Un autre
          // portefeuille ou une plateforme" took three lines at 375 pt); an
          // option card's keeps its two.
          Text(
            title,
            maxLines: compact ? 2 : null,
            overflow: compact ? TextOverflow.ellipsis : null,
            style: titleStyleOf(c),
          ),
          if (subtitle != null) ...[
            SizedBox(height: compact ? 2 : 4),
            Text(
              subtitle!,
              // A big card's lines are never cut (founder, 5 November 2026:
              // "this is cut", the Add money card's "Get an address to send
              // dollars to"): they wrap to the lines they need and the
              // cards of the row grow together (the grid's IntrinsicHeight).
              // An option card's value stays on its one line.
              maxLines: compact ? subtitleMaxLines : null,
              overflow: compact ? TextOverflow.ellipsis : null,
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
    return _interactive(
      card,
      semanticsLabel ??
          [title, if (subtitle != null) subtitle!, if (badgeText != null) badgeText]
              .join(', '),
    );
  }

  /// The pill a disabled card reads at its top right ("SELECTED", "SOON").
  Widget _badgePill(AppColorsExtension c, String text) => Container(
        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
        decoration: BoxDecoration(
          color: c.textPrimary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8.r),
        ),
        child: Text(
          text,
          maxLines: 1,
          style: TextStyle(
            color: c.textTertiary,
            fontSize: 11.sp,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
          ),
        ),
      );

  /// A lead card's title style ([KuteActionCardGrid.lead]).
  static TextStyle leadTitleStyle(AppColorsExtension c) =>
      titleStyle(c).copyWith(fontSize: 18.sp, letterSpacing: -0.3);

  /// The style of a lead card's line under its title.
  static TextStyle leadSubtitleStyle(AppColorsExtension c) =>
      subtitleStyle(c).copyWith(fontSize: 14.sp);

  /// A full-width big card, the grid's only card or an odd last one (see
  /// the file header): the visual at the left in its box, the title, its
  /// lines and the foot beside it, wrapping as they need, then the chevron
  /// (the badge on a disabled card) at the right; as tall as that. [lead]
  /// (the grid's main action on top) draws it with more presence.
  Widget _wideCard(AppColorsExtension c, bool isLight, {bool lead = false}) {
    final badgeText = badge;
    final foot = footer;
    return Container(
      padding: EdgeInsets.all(
          lead ? kKuteActionCardLeadPadding : kKuteActionCardPadding),
      decoration: _surface(c, isLight, 20),
      child: Row(
        children: [
          SizedBox(
            height: lead
                ? (visualSlot > kKuteActionCardLeadVisualSlot
                    ? visualSlot
                    : kKuteActionCardLeadVisualSlot)
                : visualSlot,
            child: Center(widthFactor: 1, child: visual),
          ),
          const SizedBox(width: kKuteActionCardWideGap),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: lead ? leadTitleStyle(c) : titleStyle(c)),
                if (subtitle != null) ...[
                  SizedBox(height: lead ? 3 : 2),
                  Text(subtitle!,
                      style:
                          lead ? leadSubtitleStyle(c) : subtitleStyle(c)),
                ],
                if (foot != null && foot.isNotEmpty) ...[
                  const SizedBox(height: 6),
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
          ),
          const SizedBox(width: 12),
          if (badgeText != null)
            _badgePill(c, badgeText)
          else
            Icon(Icons.chevron_right_rounded,
                size: lead ? 24 : 22, color: c.textTertiary),
        ],
      ),
    );
  }

  /// A full-width option card (see the file header): the icon, the title,
  /// the value and the [detail] at the left, the chevron at the right;
  /// [lone] (the grid's only card) draws them larger.
  Widget _wideOption(AppColorsExtension c, bool isLight,
      {required bool lone}) {
    final more = _detailLine;
    return Container(
      padding: EdgeInsets.all(
          lone ? kKuteOptionCardLonePadding : kKuteOptionCardPadding),
      decoration: _surface(c, isLight, 18),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: lone ? kKuteOptionCardLoneIconSize : visualSlot,
                  child: Align(alignment: Alignment.centerLeft, child: visual),
                ),
                SizedBox(height: lone ? 12 : 10),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: lone ? optionLoneTitleStyle(c) : optionTitleStyle(c),
                ),
                if (subtitle != null) ...[
                  SizedBox(height: lone ? 3 : 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: subtitleStyle(c),
                  ),
                ],
                if (more != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    more,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: optionDetailStyle(c),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Icon(Icons.chevron_right_rounded,
              size: lone ? 24 : 22, color: c.textTertiary),
        ],
      ),
    );
  }

  /// [card] as a button: its [label] read out, the press spring, a
  /// disabled card at 0.6 opacity; an option card's tap gives the
  /// selection click.
  Widget _interactive(Widget card, String label) {
    return Semantics(
      button: true,
      enabled: enabled ? null : false,
      label: label,
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

/// An option card's icon, at the left of its box; larger on the lone card.
class _KuteOptionIcon extends StatelessWidget {
  const _KuteOptionIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) => Icon(icon,
      size: _KuteCardSpan.of(context) == _CardSpan.lone
          ? kKuteOptionCardLoneIconSize
          : kKuteOptionCardIconSize,
      color: context.colors.textPrimary);
}

/// How the grid lays a card out: a square of a row, full width under
/// squares, the grid's only card, or its main action on top (see the file
/// header). A big card draws wide and lone alike (compact, the visual at
/// its left) and the lead larger; an option card draws the lone one
/// larger.
enum _CardSpan { square, wide, lone, lead }

/// The [_CardSpan] [KuteActionCardGrid] gives the card under it; a card
/// outside a grid is a square.
class _KuteCardSpan extends InheritedWidget {
  const _KuteCardSpan({required this.span, required super.child});

  final _CardSpan span;

  static _CardSpan of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_KuteCardSpan>()?.span ??
      _CardSpan.square;

  @override
  bool updateShouldNotify(_KuteCardSpan oldWidget) => span != oldWidget.span;
}

/// Lays out 1 to 4 [cards] (see the file header): squares in pairs, an
/// odd last card (or the only one) full width and compact; three big
/// cards three across where they fit.
class KuteActionCardGrid extends StatelessWidget {
  const KuteActionCardGrid({
    super.key,
    required this.cards,
    this.lead,
    this.gap = kKuteActionCardGap,
    this.compactLone = false,
  });

  final List<KuteActionCard> cards;

  /// The main action, drawn first, full width and with more presence; the
  /// [cards] follow under it by the usual rules, a lone one compact (see
  /// the file header). A big card, never an option card.
  final KuteActionCard? lead;

  /// The space between cards, in design units (scaled by width).
  final double gap;

  /// A lone card laid out as an odd last one is (full width, the squares'
  /// sizes) rather than with the lone card's presence: a position's
  /// actions row over its tiles, which one card must not outweigh
  /// (founder, 6 November 2026: full width and compact).
  final bool compactLone;

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
    // A card across the whole width: the grid's only card ([lone]) or an
    // odd last one under squares, laid out for the width (see the file
    // header).
    Widget full(KuteActionCard card, {required bool lone}) => _KuteCardSpan(
          span: lone ? _CardSpan.lone : _CardSpan.wide,
          child: card,
        );

    final first = lead;
    if (first != null) {
      assert(!first.compact, 'a lead card is a big card');
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _KuteCardSpan(span: _CardSpan.lead, child: first),
          if (cards.isNotEmpty) ...[
            space,
            // Under the lead a lone card is the compact full-width one,
            // never a second card with the lead's presence.
            KuteActionCardGrid(cards: cards, gap: gap, compactLone: true),
          ],
        ],
      );
    }
    if (cards.isEmpty) return const SizedBox.shrink();
    if (cards.length == 3 && !cards.every((card) => card.compact)) {
      // Three big cards: three across where every label fits a third,
      // else two squares over one full-width card.
      return LayoutBuilder(builder: (context, constraints) {
        final third = (constraints.maxWidth - 2 * g) / 3;
        final across = constraints.hasBoundedWidth &&
            labelsFit(context, cards, third);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: across
              ? [row(cards)]
              : [
                  row(cards.sublist(0, 2)),
                  space,
                  full(cards[2], lone: false),
                ],
        );
      });
    }
    // Squares in pairs, never one alone in half the width: the lone card,
    // or an odd last one, takes the full width, laid out for it.
    final children = <Widget>[];
    for (var i = 0; i < cards.length; i += 2) {
      if (i > 0) children.add(space);
      children.add(i + 1 < cards.length
          ? row(cards.sublist(i, i + 2))
          : full(cards[i], lone: cards.length == 1 && !compactLone));
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}
