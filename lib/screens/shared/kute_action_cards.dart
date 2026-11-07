// lib/screens/shared/kute_action_cards.dart
//
// BIG SQUARES, NOT LISTS (founder, 1 November 2026: "on these sheets when
// possible, instead of a list, big squares like modern fintech apps"). A
// sheet whose content is two to four actions or choices shows them as
// cards, in the style the Sal sheet's send cards set (commit 6dcf960f):
// THE APP'S ONE CARD (founder, 7 November 2026, the position page's grey
// bordered cards beside its soft tiles: "dofferent cards than this"): the
// soft card the Goals squares, the Dollars position squares and the
// activity squares wear ([PremiumGroupContainer.decorationOf]: the card
// surface, radius 20, the soft shadow under it, no visible border), on a
// screen and on a sheet alike, light and dark; 16 padding; a large
// visual at the top left (a logo, Sal, an icon), the
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
// TITLES ON ONE LINE (founder, 7 November 2026, the Receive sheets: "sizes
// are strange here"; one square's title on one line, the other's on two,
// left one card half empty): a grid asked for [KuteActionCardGrid.
// oneLineTitles] draws two big cards as squares only where both titles
// read on one line at half the width, and otherwise as two compact
// full-width cards, one over the other: the same layout as an odd last
// card, never a squeezed font.
//
// OPTION CARDS, THE SAME SQUARES, SMALLER (founder, 4 November 2026: the
// rows under a market's or a position's chart, "Add margin", "Rules and
// resolution", "should be like big squares"; "little cards, square-ish"):
// [KuteActionCard.option] is the card for a screen rather than a sheet,
// the options under the chart of the Investing and Predictions market
// and position screens, alike on both venues. The same soft card and
// press spring; 14 padding, at least 112 tall; an icon (22,
// primary text) at the top left, the title under it (15, w600, two lines)
// and, when the option has one, its value on one line (13, textSecondary:
// "Stop loss", "Ends Nov 5"). The text sits at the top, so the titles of
// a row sit level whether or not a card has a value. A tap gives the
// selection click the rows gave.
//
// The same grid lays them out in two columns and never leaves a card
// alone in half the width (founder, 5 November 2026: "adapt the cards to
// when there are fewer elements, like 1 or 3"):
//   1 card:  the lone card, full width, one compact row;
//   2 cards: two squares side by side;
//   3 cards: two squares over one full-width row;
//   4 cards: a 2 x 2 grid; 5: 2 x 2 over one full-width row; and so on, an
//            odd last card full width.
// A FULL-WIDTH OPTION IS ONE ROW (founder, 7 November 2026, the market
// page's lone "Rules and resolution" card with its gavel on top and the
// rules' first lines under its date: "way too much"): the lone card and an
// odd last one alike, at the squares' sizes (icon 22, title 15, value 13
// on one line), the icon at its left, the title over its value beside it,
// the chevron at its right; as tall as a list row ([KuteListRow]), never
// a preview of what the option opens. A square never shows a chevron.
//
// A CARD THAT STATES (founder, 7 November 2026, the Bitcoin Send's Review:
// "make this more with the square cards we have now"): the Review's From
// and To are two of these squares side by side ([KuteActionCard.fact]),
// the same card with a small label over the title ("From", "To"; 13,
// w600, textTertiary). A fact never shows a chevron, full width or not:
// it opens nothing. With no tap it is plain: no press and never dimmed,
// since it is not a choice that is switched off; with a tap (the To
// square shows the whole address under the pair) it presses as any card
// does. A title that is an address ([KuteActionCard.oneLineTitle])
// keeps to one line in its middle-ellipsis form, its head and its tail
// whole, so an address never stands a pair's titles on two lines.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/screens/shared/animations/premium_group_container.dart';
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

/// The space between a full-width option card's icon and its text.
const double kKuteOptionCardRowGap = 12;

/// The space between a full-width big card's visual and its text.
const double kKuteActionCardWideGap = 14;

/// The visual box of a grid's lead card ([KuteActionCardGrid.lead]).
const double kKuteActionCardLeadVisualSlot = 48;

/// The size the sheets draw a lead card's visual at.
const double kKuteActionCardLeadVisualSize = 48;

/// A lead card's inner padding.
const double kKuteActionCardLeadPadding = 18;

/// The width of the card surface's hairline, inside its bounds.
const double _kCardHairline = 1;

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
        fact = false,
        label = null,
        oneLineTitle = null;

  /// An option card (see the file header): [icon] at the top left, the
  /// [title] and, when the option has one, its value ([subtitle]) on one
  /// line; full width, one compact row.
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
        compact = true,
        fact = false,
        label = null,
        oneLineTitle = null;

  /// A card that states rather than offers (see the file header: the
  /// Send Review's From and To): [label] over the [title], the line under
  /// it; never a chevron. Without [onTap] it is plain, never dimmed; with
  /// one it presses as any card does.
  const KuteActionCard.fact({
    super.key,
    required this.visual,
    required String this.label,
    required this.title,
    this.subtitle,
    this.oneLineTitle,
    this.semanticsLabel,
    this.onTap,
  })  : footer = null,
        footerKey = null,
        badge = null,
        visualSlot = kKuteActionCardVisualSlot,
        compact = false,
        fact = true;

  /// The large visual at the top left.
  final Widget visual;

  /// The small line over the title of a fact card ("From", "To").
  final String? label;
  final String title;

  /// Draws the title on ONE line that shapes itself to the card's width
  /// (an address in its middle-ellipsis form, head and tail kept), given
  /// the title's style; [title] stays what is read out. Such a title
  /// always fits its line, so it never moves a grid from squares to full
  /// width cards ([KuteActionCardGrid.oneLineTitles]).
  final Widget Function(TextStyle style)? oneLineTitle;

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

  /// A card that states ([KuteActionCard.fact]): without a tap it is
  /// plain, never disabled.
  final bool fact;

  bool get enabled => onTap != null;

  /// A fact with nothing to do on a tap: drawn plain.
  bool get _plain => fact && onTap == null;

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

  /// The style of a fact card's label over its title ("From", "To").
  static TextStyle labelStyle(AppColorsExtension c) => TextStyle(
        color: c.textTertiary,
        fontSize: 13.sp,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
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

  /// The card's surface: the app's one soft card (see the file header),
  /// the Goals and position squares' own, never a surface of its own.
  static BoxDecoration surfaceOf(BuildContext context) =>
      PremiumGroupContainer.decorationOf(context);

  /// [padding] inside [surface], measured as the cards always measured it:
  /// from a 1 px edge. The soft card's hairline is thinner in light mode,
  /// so the padding takes up the difference and the content sits exactly
  /// where it did.
  static EdgeInsets paddingIn(BoxDecoration surface, double padding) =>
      EdgeInsets.all(
          padding + 1 - ((surface.border as Border?)?.top.width ?? 0));

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final surface = surfaceOf(context);
    final span = _KuteCardSpan.of(context);
    final badgeText = badge;
    final factLabel = label;
    if (span != _CardSpan.square) {
      if (!compact) {
        return _interactive(
          _wideCard(context, c, surface, lead: span == _CardSpan.lead),
          semanticsLabel ??
              [
                if (factLabel != null) factLabel,
                title,
                if (subtitle != null) subtitle!,
                if (footer != null && footer!.isNotEmpty) footer!,
                if (badgeText != null) badgeText,
              ].join(', '),
        );
      }
      return _interactive(
        _wideOption(c, surface),
        semanticsLabel ??
            [title, if (subtitle != null) subtitle!].join(', '),
      );
    }
    final foot = footer;
    final card = Container(
      // An option card keeps its floor; a big card is as tall as what it
      // holds (the row's tallest sets the row; see the file header).
      constraints: compact
          ? const BoxConstraints(minHeight: kKuteOptionCardMinHeight)
          : null,
      padding: paddingIn(surface,
          compact ? kKuteOptionCardPadding : kKuteActionCardPadding),
      decoration: surface,
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
          if (factLabel != null) ...[
            Text(factLabel, style: labelStyle(c)),
            const SizedBox(height: 2),
          ],
          // A big card's title wraps whole too (French "Un autre
          // portefeuille ou une plateforme" took three lines at 375 pt); an
          // option card's keeps its two.
          _title(
            context,
            titleStyleOf(c),
            maxLines: compact ? 2 : null,
            overflow: compact ? TextOverflow.ellipsis : null,
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
          [
            if (factLabel != null) factLabel,
            title,
            if (subtitle != null) subtitle!,
            if (badgeText != null) badgeText,
          ].join(', '),
    );
  }

  /// The title in [style]: the text, or, for [oneLineTitle], the line it
  /// shapes itself, its height fixed from the style so a grid row can
  /// ask the card its height (IntrinsicHeight) without laying it out.
  Widget _title(BuildContext context, TextStyle style,
      {int? maxLines, TextOverflow? overflow}) {
    final shaped = oneLineTitle;
    if (shaped == null) {
      return Text(title, maxLines: maxLines, overflow: overflow, style: style);
    }
    final line = TextPainter(
      text: TextSpan(
          text: title, style: DefaultTextStyle.of(context).style.merge(style)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final height = line.height;
    line.dispose();
    return SizedBox(
      width: double.infinity,
      height: height,
      child: shaped(style),
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
  /// (the badge on a disabled card; nothing on a fact) at the right;
  /// as tall as that. [lead] (the grid's main action on top) draws it with
  /// more presence.
  Widget _wideCard(
      BuildContext context, AppColorsExtension c, BoxDecoration surface,
      {bool lead = false}) {
    final badgeText = badge;
    final foot = footer;
    final factLabel = label;
    return Container(
      padding: paddingIn(surface,
          lead ? kKuteActionCardLeadPadding : kKuteActionCardPadding),
      decoration: surface,
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
                if (factLabel != null) ...[
                  Text(factLabel, style: labelStyle(c)),
                  const SizedBox(height: 2),
                ],
                _title(context, lead ? leadTitleStyle(c) : titleStyle(c)),
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
          if (badgeText != null) ...[
            const SizedBox(width: 12),
            _badgePill(c, badgeText),
          ] else if (!fact) ...[
            const SizedBox(width: 12),
            Icon(Icons.chevron_right_rounded,
                size: lead ? 24 : 22, color: c.textTertiary),
          ],
        ],
      ),
    );
  }

  /// A full-width option card, the grid's only card or an odd last one
  /// (see the file header): one row, the icon at its left, the title over
  /// its value beside it, the chevron at its right; as tall as a list row.
  Widget _wideOption(AppColorsExtension c, BoxDecoration surface) {
    return Container(
      padding: paddingIn(surface, kKuteOptionCardPadding),
      decoration: surface,
      child: Row(
        children: [
          SizedBox(
            width: visualSlot,
            child: Align(alignment: Alignment.centerLeft, child: visual),
          ),
          const SizedBox(width: kKuteOptionCardRowGap),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: optionTitleStyle(c),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: subtitleStyle(c),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Icon(Icons.chevron_right_rounded, size: 22, color: c.textTertiary),
        ],
      ),
    );
  }

  /// [card] as a button: [readOut] read out, the press spring, a
  /// disabled card at 0.6 opacity; an option card's tap gives the
  /// selection click. A plain fact is read out and nothing more.
  Widget _interactive(Widget card, String readOut) {
    if (_plain) {
      return Semantics(
        container: true,
        label: readOut,
        excludeSemantics: true,
        child: card,
      );
    }
    return Semantics(
      button: true,
      enabled: enabled ? null : false,
      label: readOut,
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

/// A big card's visual where the action has an icon rather than a logo:
/// the icon (primary text) on the ink-tinted rounded square (6% in light
/// mode, 10% in dark), [size] square, the icon at 55% of it (22 in the 40
/// box). Settings' four cards and the Financial hub's cards wear it.
class KuteActionCardIcon extends StatelessWidget {
  const KuteActionCardIcon(this.icon,
      {super.key, this.size = kKuteActionCardVisualSize});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.textPrimary.withValues(alpha: context.isDark ? 0.10 : 0.06),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(icon, color: c.textPrimary, size: size * 0.55),
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

/// How the grid lays a card out: a square of a row, full width (the
/// grid's only card or an odd last one, compact: the visual at its left),
/// or its main action on top, larger (see the file header).
enum _CardSpan { square, wide, lead }

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
    this.oneLineTitles = false,
  });

  final List<KuteActionCard> cards;

  /// The main action, drawn first, full width and with more presence; the
  /// [cards] follow under it by the usual rules, a lone one compact (see
  /// the file header). A big card, never an option card.
  final KuteActionCard? lead;

  /// The space between cards, in design units (scaled by width).
  final double gap;

  /// Two big cards are squares only where both titles fit on one line at
  /// half the width; otherwise each is a compact full-width card (see the
  /// file header).
  final bool oneLineTitles;

  /// Whether every card's title and line fit a card [cardWidth] wide
  /// without an ellipsis or a word broken across lines, the title in at
  /// most [titleLines] lines.
  static bool labelsFit(
    BuildContext context,
    List<KuteActionCard> cards,
    double cardWidth, {
    int titleLines = 2,
  }) {
    final c = context.colors;
    final padding = cards.any((card) => !card.compact)
        ? kKuteActionCardPadding
        : kKuteOptionCardPadding;
    // The surface's hairline sits inside the card too (a Container adds
    // its border to its padding), so the text has that much less.
    final inner = cardWidth - 2 * (padding + _kCardHairline);
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
      final cardLabel = card.label;
      if (cardLabel != null &&
          !fits(cardLabel, KuteActionCard.labelStyle(c), maxLines: 1)) {
        return false;
      }
      // A title that shapes itself to its one line always fits it.
      if (card.oneLineTitle == null &&
          !fits(card.title, card.titleStyleOf(c), maxLines: titleLines)) {
        return false;
      }
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
    // A card across the whole width: the grid's only card or an odd last
    // one under squares, laid out for the width (see the file header).
    Widget full(KuteActionCard card) =>
        _KuteCardSpan(span: _CardSpan.wide, child: card);

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
            KuteActionCardGrid(
                cards: cards, gap: gap, oneLineTitles: oneLineTitles),
          ],
        ],
      );
    }
    if (cards.isEmpty) return const SizedBox.shrink();
    if (oneLineTitles &&
        cards.length == 2 &&
        !cards.every((card) => card.compact)) {
      // Two squares where both titles read on one line at half the width,
      // else two compact full-width cards (see the file header).
      return LayoutBuilder(builder: (context, constraints) {
        final half = (constraints.maxWidth - g) / 2;
        final squares = constraints.hasBoundedWidth &&
            labelsFit(context, cards, half, titleLines: 1);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: squares
              ? [row(cards)]
              : [
                  full(cards[0]),
                  space,
                  full(cards[1]),
                ],
        );
      });
    }
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
                  full(cards[2]),
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
          : full(cards[i]));
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}
