// lib/screens/portfolio/components/position_rows.dart
//
// The Portfolio's open positions as plain list rows (founder request,
// October 2026: "those cards are not fintech like"; layout "option B"),
// the way a brokerage app lists holdings, with no card, border or fill:
//
//   * leading, the real picture in a [kPortfolioRowImage] circle: a
//     Predictions market's image (the held team's crest when the event
//     names one) clipped round, an Investing market's coin logo through
//     [HlCoinIcon] (HIP-3 tickers such as xyz:NVDA included);
//   * the title, short by construction ([polyPositionRowNames]): the held
//     outcome's own name in a many-outcome event ("Lula da Silva", "Harry
//     Kane"), a named side ("Verstappen"), the event's title when short,
//     else the market's question without "Will … ?"; the asset's name
//     ("Bitcoin", "Nvidia"). Two lines at most, never one cut short;
//   * under it one line: the event and the side held ("Brazil
//     Presidential Election · Yes"; the state in place of the side where
//     there is one: "… · Settled", "… · Selling…", the awaiting-result
//     caption), or "Long · 0.0125 BTC" (never a leverage figure: leverage
//     is blocked in the app; the entry price is on the position screen);
//   * a Predictions row that is still open adds a thin bar, the held
//     side's live chance ([PortfolioChanceBar]);
//   * on the right what it is worth now (15 w600) with the P&L under it
//     in money and as a % (12, a caret, up or down: "▲ $0.61 · 5.4%";
//     founder, 6 November 2026: "on each open position say how much I am
//     actually winning in dollars"); a P&L under a cent reads "$0.00 ·
//     0.0%" quietly, never a red minus ([portfolioPnlPill]).
//
// The Portfolio's one row language ([kPortfolioRowPadV] and the styles
// under it, founder 1 November 2026): the picture 32, the title 15 w500,
// the line 13, the figure 15 w600 with its change 12; the P&L venue rows
// are drawn the same. The Portfolio screen lists them in SOFT CARDS
// (founder, 1 November 2026: one style with the home Activity list; flat
// rows on the page were dropped): [PortfolioCardList], the Activity day
// card's surface, radius and inset hairline, each row inset 16 at the
// sides and 13 above and below (the home Activity's compact rows). The
// figure column at the end takes what it needs, at most 45% of the row
// (the Activity rows' rule), and scales down past that: never cut at the
// card's edge, at 375 pt and at large text alike.
//
// THE PORTFOLIO SCREEN'S POSITIONS (the redesign of 7 November 2026,
// [PortfolioRowLayout.position]): the same row widgets as one plain row
// each under their venue's heading: the picture, the name with the side
// held as a small neutral chip after it ("Long", "Short", "Yes", "No";
// HlMetaChip), a quiet note under it only where there is one (the event,
// a state), and at the end the value over the P&L since it was opened,
// "+$1.20 (+8.0%)" in its colour ([portfolioSignedPnl]); no size, no
// leverage, no mark price, no return on equity (the position screen has
// the entry, the size, what was put in and the liquidation, or what a
// prediction pays if it wins). The same figures as every other shape and
// as the brag card (hlLivePnl on the margin, the shares at the live
// price). The P&L tab's closed positions are drawn the same
// ([PortfolioClosedRow]). The biggest positions as SQUARES
// ([PortfolioRowLayout.square], [PortfolioPositionSquares]) and the
// Investing list's own row ([PortfolioRowLayout.market]) are the Dollars
// Activity tab's and the Investing list's.
// Every row is its own widget watching only what it needs, so a price
// tick repaints one row. Taps open the same screens the cards opened,
// with the same `open_investments_position_tapped` event.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart' show DateFormat;

import 'package:kute/helpers/formatters/polymarket_amount_formatter.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/portfolio_performance.dart' show PredictionRecord;
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/models/polymarket_model.dart' show PolymarketEvent;
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart'
    show hyperliquidAccountMarketProvider, hyperliquidSpotMarketsProvider;
import 'package:kute/providers/placing_polymarket_bet_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart'
    show PolymarketPosition;
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart'
    show polymarketTradingProvider;
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart';
import 'package:kute/screens/home/components/action_pill.dart'
    show greenColor, redColor;
import 'package:kute/screens/hyperliquid/components/hl_isolated_margin.dart';
import 'package:kute/screens/hyperliquid/components/hl_market_card.dart'
    show HlListRow;
import 'package:kute/screens/hyperliquid/components/hl_position_detail_sheet.dart';
import 'package:kute/screens/hyperliquid/market_detail_sheet.dart';
import 'package:kute/screens/polymarket/components/combo_detail_sheet.dart';
import 'package:kute/screens/polymarket/components/game_time.dart'
    show polyMinuteTickProvider;
import 'package:kute/screens/polymarket/components/live_token_scope.dart';
import 'package:kute/screens/polymarket/components/market_card.dart'
    show PolyCardThumbnail;
import 'package:kute/screens/polymarket/components/poly_chart_tags.dart'
    show polyChartOutcomeName;
import 'package:kute/screens/polymarket/components/position_awaiting.dart';
import 'package:kute/screens/polymarket/components/position_detail_sheet.dart'
    show PositionDetailSheet, polyPositionEnd;
import 'package:kute/screens/portfolio/poly_position_events.dart'
    show polyPositionEventProvider;
import 'package:kute/screens/shared/all_activity.dart'
    show ActivitySquareGrid;
import 'package:kute/screens/shared/animations/premium_group_container.dart';
import 'package:kute/screens/shared/kute_motion.dart'
    show KutePressable, RollingFigure;
import 'package:kute/screens/shared/market_groups.dart' show marketGroupDivider;
import 'package:kute/screens/shared/transactions_builder.dart'
    show kActivitySquareHeight;
import 'package:kute/services/polymarket/combos/combo_models.dart';
import 'package:kute/services/polymarket/market_display_title.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// A row's picture (a circle) and the gap after it.
const double kPortfolioRowImage = 32;
const double kPortfolioRowGap = 12;

/// THE PORTFOLIO'S ONE ROW LANGUAGE (founder, 1 November 2026: "the vibes
/// are different" between Portfolio and P&L Charts): a position row here
/// and a P&L venue row (portfolio_pnl_chart.dart, PnlVenueRow) are drawn
/// the same: the picture at [kPortfolioRowImage], the title 15 w500, the
/// line under it 13 in textSecondary, the figure 15 w600 at the end with
/// its change 12 under it. Off a card, [kPortfolioRowPadV] above and below
/// each row; in a [PortfolioCardList], [kPortfolioCardRowPadV] and
/// [kPortfolioCardInset] with a hairline between rows.
const double kPortfolioRowPadV = 7;

/// A row's padding inside a [PortfolioCardList]: the home Activity list's
/// compact rows (transactions_builder.dart: 16 at the sides, 13 above and
/// below).
const double kPortfolioCardInset = 16;
const double kPortfolioCardRowPadV = 13;

/// The most of a row its figure column at the end may take before it
/// scales down (the Activity rows' rule, TransactionRowContent).
const double kPortfolioRowFiguresShare = 0.45;

/// A row's title: 15 w500.
TextStyle portfolioRowTitleStyle(BuildContext context) => TextStyle(
      color: context.colors.textPrimary,
      fontSize: 15.sp,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.2,
      height: 1.25,
    );

/// The line under a row's title: 13 in textSecondary.
TextStyle portfolioRowSubStyle(BuildContext context) => TextStyle(
      color: context.colors.textSecondary,
      fontSize: 13.sp,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.1,
      height: 1.3,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

/// A row's figure at the end: 15 w600, tabular.
TextStyle portfolioRowFigureStyle(BuildContext context, {Color? color}) =>
    TextStyle(
      color: color ?? context.colors.textPrimary,
      fontSize: 15.sp,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
      height: 1.25,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

/// The change under a row's figure: 12, in its colour.
TextStyle portfolioRowChangeStyle(Color color) => TextStyle(
      color: color,
      fontSize: 12.sp,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.1,
      height: 1.3,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

/// The insets of every [PortfolioPositionRow] (and P&L venue row) below
/// it: none at the sides and [kPortfolioRowPadV] above and below where the
/// rows sit on the page, the card's row padding where a
/// [PortfolioCardList] draws them. The inset is inside each row's ink, so
/// a press still reaches the card's edges.
class PortfolioRowInset extends InheritedWidget {
  const PortfolioRowInset(
      {super.key,
      required this.horizontal,
      this.vertical,
      required super.child});

  /// Logical pixels, already scaled.
  final double horizontal;

  /// Logical pixels, already scaled; null: [kPortfolioRowPadV].
  final double? vertical;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PortfolioRowInset>()
          ?.horizontal ??
      0;

  /// The padding above and below a row.
  static double verticalOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PortfolioRowInset>()
          ?.vertical ??
      kPortfolioRowPadV.h;

  @override
  bool updateShouldNotify(PortfolioRowInset oldWidget) =>
      horizontal != oldWidget.horizontal || vertical != oldWidget.vertical;
}

/// The Portfolio's soft card list (founder, 1 November 2026: one style
/// with the home Activity list): the Activity day card's surface, radius,
/// border and soft shadow ([PremiumGroupContainer.decorationOf]), its rows
/// inside it at [kPortfolioCardInset] / [kPortfolioCardRowPadV] with the
/// inset hairline between them, starting where a row's text does
/// ([marketGroupDivider]), the rows' press ink clipped to the corners.
/// [after] (a fold row, a skeleton) follows the rows, past the same
/// hairline when [afterHairline].
class PortfolioCardList extends StatelessWidget {
  const PortfolioCardList(
      {super.key,
      required this.rows,
      this.after,
      this.afterHairline = true,
      this.hairlines = true,
      this.indent});

  final List<Widget> rows;
  final Widget? after;
  final bool afterHairline;

  /// Where the hairline starts, logical pixels; null: [hairlineIndent],
  /// the rows' text (rows with no picture start theirs at the inset).
  final double? indent;

  /// The inset hairline between rows; false for the Investing list's
  /// rows ([PortfolioRowLayout.market]), which draw none.
  final bool hairlines;

  /// Where the hairline starts, from the card's edge: the rows' text.
  static double hairlineIndent() =>
      (kPortfolioCardInset + kPortfolioRowImage + kPortfolioRowGap).w;

  @override
  Widget build(BuildContext context) {
    final indent = this.indent ?? hairlineIndent();
    return DecoratedBox(
      decoration: PremiumGroupContainer.decorationOf(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(PremiumGroupContainer.radius),
        child: PortfolioRowInset(
          horizontal: kPortfolioCardInset.w,
          vertical: kPortfolioCardRowPadV.h,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0 && hairlines) marketGroupDivider(context, indent),
                rows[i],
              ],
              if (after case final a?) ...[
                if (rows.isNotEmpty && afterHairline && hairlines)
                  marketGroupDivider(context, indent),
                a,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// How a [PortfolioPositionRow] is drawn (see the file header): the
/// Portfolio's own row ([list]), the Investing list's row ([market]), a
/// big square ([square]), the full-width compact card an odd last
/// square becomes ([wide], [PortfolioPositionSquares]), or the Portfolio
/// screen's Positions row ([position]: the name and its side chip, a
/// quiet note under it where there is one, the value over the P&L since
/// it was opened, "+$1.20 (+8.0%)").
enum PortfolioRowLayout { list, market, square, wide, position }

/// The [PortfolioRowLayout] of the position rows under it; none above:
/// [PortfolioRowLayout.list].
class PortfolioRowLayoutScope extends InheritedWidget {
  const PortfolioRowLayoutScope(
      {super.key, required this.layout, required super.child});

  final PortfolioRowLayout layout;

  static PortfolioRowLayout of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<PortfolioRowLayoutScope>()
          ?.layout ??
      PortfolioRowLayout.list;

  @override
  bool updateShouldNotify(PortfolioRowLayoutScope old) => old.layout != layout;
}

/// How many of [positions] open positions the Portfolio screen draws as
/// squares: full rows of two only, two for two or three, four from four
/// (the rest are their venue's rows); a single position is the one
/// full-width compact card ([PortfolioPositionSquares]: never a lone
/// half square). Pure for the tests.
int portfolioSquareCount(int positions) => positions >= 4
    ? 4
    : positions >= 2
        ? 2
        : positions == 1
            ? 1
            : 0;

/// The square's logo (the Latest square's icon size) and inner padding.
const double kPortfolioSquareIcon = 40;
const double _kSquarePad = 14;

/// The gap between squares, each way (ActivitySquareGrid's), and over the
/// full-width card under them.
const double kPortfolioSquareGap = 10;

/// THE NO-ORPHAN RULE (founder, 6 November 2026, on three open positions
/// on the Dollars Activity tab, the third a half square alone on its row:
/// "should the 3rd one be rectangular and not with this disposition?"):
/// [rows] (the positions' own rows, biggest first) as squares two by two
/// (ActivitySquareGrid, [PortfolioRowLayout.square]), and an odd last one,
/// one alone included, as one full-width compact card under them
/// ([PortfolioRowLayout.wide]: the logo, the name over the side held, the
/// value, the P&L in money over its %), never a lone half square. The
/// Dollars Activity tab's squares (up to four) and the Portfolio's
/// (portfolioSquareCount: whole rows of two, the rest as rows) both draw
/// through it.
class PortfolioPositionSquares extends StatelessWidget {
  const PortfolioPositionSquares({super.key, required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final paired = rows.length - rows.length % 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (paired > 0)
          PortfolioRowLayoutScope(
            layout: PortfolioRowLayout.square,
            child: ActivitySquareGrid(children: rows.sublist(0, paired)),
          ),
        if (rows.length.isOdd) ...[
          if (paired > 0) SizedBox(height: kPortfolioSquareGap.w),
          PortfolioRowLayoutScope(
            layout: PortfolioRowLayout.wide,
            child: rows.last,
          ),
        ],
      ],
    );
  }
}

/// A P&L as the Investing rows write a change: "▲ 4.0%" / "▼ 4.0%" in the
/// up / down colour, "0.0%" quietly when flat ([portfolioPnlPill]'s
/// figure, its sign turned into the arrow). With its [amount] in money
/// (unsigned, "$0.61"), the money first: "▲ $0.61 · 4.0%", "$0.00 · 0.0%"
/// quietly when flat.
({String text, Color color}) portfolioArrowPnl(
    BuildContext context, ({String text, PortfolioPnlTone tone}) pnl,
    {String? amount}) {
  final percent = pnl.text.replaceFirst(RegExp(r'^[+\u2212-]'), '');
  final shown = amount == null ? percent : '$amount · $percent';
  return switch (pnl.tone) {
    PortfolioPnlTone.up => (text: '▲ $shown', color: greenColor),
    PortfolioPnlTone.down => (text: '▼ $shown', color: redColor),
    PortfolioPnlTone.flat => (
        text: shown,
        color: context.colors.textSecondary
      ),
  };
}

/// The P&L in a square's corner: the money with its arrow over the %
/// ("▲ $0.61" over "5.4%"), both in the result's colour; without [amount],
/// the % alone with its arrow, as before.
typedef PortfolioCornerPnl = ({String? amount, String percent, Color color});

/// [pnl] as a square's corner writes it ([PortfolioCornerPnl]).
PortfolioCornerPnl portfolioCornerPnl(
    BuildContext context, ({String text, PortfolioPnlTone tone}) pnl,
    {String? amount}) {
  final arrow = portfolioArrowPnl(context, pnl);
  if (amount == null) {
    return (amount: null, percent: arrow.text, color: arrow.color);
  }
  final lead = switch (pnl.tone) {
    PortfolioPnlTone.up => '▲ ',
    PortfolioPnlTone.down => '▼ ',
    PortfolioPnlTone.flat => '',
  };
  return (
    amount: '$lead$amount',
    percent: pnl.text.replaceFirst(RegExp(r'^[+\u2212-]'), ''),
    color: arrow.color,
  );
}

/// A position square's height: [kActivitySquareHeight], or its content at
/// the viewer's text size when that is taller (no overflow at an
/// accessibility size).
double portfolioSquareHeight(BuildContext context) {
  final scaler = MediaQuery.textScalerOf(context);
  // The top row: the logo, or the corner's two lines (the P&L in money
  // over its %) when they are taller at the viewer's text size.
  final corner = scaler.scale(13.sp) * 1.2 + 1.h + scaler.scale(12.sp) * 1.3;
  final top = corner > kPortfolioSquareIcon.w ? corner : kPortfolioSquareIcon.w;
  final content = _kSquarePad.w * 2 +
      top +
      10.w +
      scaler.scale(13.sp) * 1.25 +
      2.h +
      scaler.scale(12.sp) * 1.3 +
      4.h +
      scaler.scale(22.sp) * 1.2 +
      // A pixel of slack for rounding.
      2;
  final least = kActivitySquareHeight.w;
  return content > least ? content : least;
}

/// How a P&L reads: a gain, a loss, or nothing worth a colour.
enum PortfolioPnlTone { up, down, flat }

/// The P&L pill under a row's value: "+4.0%", "−4.0%", or "0.0%" (flat,
/// no sign) when the P&L is under a cent or its % rounds to nothing.
/// Null when there is no % to write. Pure for the tests.
({String text, PortfolioPnlTone tone})? portfolioPnlPill(double pnl,
    {double? percent}) {
  if (percent == null || !percent.isFinite) return null;
  if (!pnl.isFinite || pnl.abs() < 0.005 || percent.abs() < 0.05) {
    return (text: '0.0%', tone: PortfolioPnlTone.flat);
  }
  final up = pnl > 0;
  return (
    text: '${up ? '+' : '−'}${percent.abs().toStringAsFixed(1)}%',
    tone: up ? PortfolioPnlTone.up : PortfolioPnlTone.down,
  );
}

/// A Predictions row's words: its [title], the [context] the secondary
/// line starts with ('' for none) and whether the title already is the
/// side held ([titleIsSide], "Verstappen"), so the line does not repeat
/// it.
typedef PolyRowNames = ({String title, String context, bool titleIsSide});

/// The longest a title may be to count as short (the event's title, a
/// named side).
const int kPolyRowShortTitle = 28;

/// Sides that say nothing alone ("Up" of "Bitcoin Up or Down"): never a
/// title.
const Set<String> _kPlainSides = {
  'yes', 'no', 'up', 'down', 'over', 'under', 'odd', 'even', //
  'higher', 'lower', 'above', 'below',
};

String _capitalised(String t) =>
    t.isEmpty ? t : '${t[0].toUpperCase()}${t.substring(1)}';

/// Words after a question's "Will" that leave no sentence once it goes
/// ("Will it rain tomorrow?" never reads "It rain tomorrow").
const Set<String> _kPronouns = {
  'it', 'there', 'this', 'that', 'these', 'those', 'we', 'you', 'they', //
  'he', 'she', 'i', 'anyone', 'someone', 'anybody', 'somebody',
};

/// [text] (a market question, an event title) shortened for a row: no
/// leading "Will " or trailing "?" (a question whose "Will" a pronoun
/// follows stays whole: "Will it rain tomorrow?"), no trailing "(…)"
/// aside, cut at
/// " - " ("Bitcoin Up or Down - October 25, 9AM ET") or after a "Who
/// will finish higher: …" lead of three words or more, an ISO date
/// written by [date] ("2026-10-25" -> "Oct 25").
String polyRowShortText(String text, {String Function(DateTime)? date}) {
  var t = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  final words = t.toLowerCase().split(' ');
  if (words.length > 1 &&
      words.first == 'will' &&
      _kPronouns.contains(words[1])) {
    return t;
  }
  if (t.endsWith('?')) t = t.substring(0, t.length - 1).trimRight();
  if (t.length > 5 && t.toLowerCase().startsWith('will ')) {
    t = _capitalised(t.substring(5));
  }
  final aside = t.replaceFirst(RegExp(r'\s*\([^()]*\)$'), '');
  if (aside.isNotEmpty) t = aside;
  final dash = t.indexOf(' - ');
  if (dash >= 6) t = t.substring(0, dash);
  final colon = t.indexOf(': ');
  if (colon > 0 && t.substring(0, colon).split(' ').length >= 3) {
    t = t.substring(0, colon);
  }
  if (date != null) {
    t = t.replaceAllMapped(RegExp(r'\b\d{4}-\d{2}-\d{2}\b'), (m) {
      final d = DateTime.tryParse(m[0]!);
      return d == null ? m[0]! : date(d);
    });
  }
  return t;
}

/// The held market's own name in a many-outcome [event] (Polymarket's
/// `groupItemTitle`: "Lula da Silva", "Real Madrid"); null when the
/// market is not one of its sub-markets or carries no name of its own
/// (a question-shaped label falls back to the question).
String? _subMarketName(
    PolymarketEvent event, String question, String? marketId, String? tokenId) {
  for (final o in [...event.outcomes, ...event.hiddenOutcomes]) {
    if (o.noTokenId == null) continue;
    final match = (marketId != null &&
            marketId.isNotEmpty &&
            o.conditionId == marketId) ||
        (tokenId != null && (o.tokenId == tokenId || o.noTokenId == tokenId));
    if (!match) continue;
    var name = o.name.trim();
    if (name.isEmpty || name == question.trim()) return null;
    final aside = name.replaceFirst(RegExp(r'\s*\([^()]*\)$'), '');
    if (aside.isNotEmpty) name = aside;
    return name;
  }
  return null;
}

/// A sub-market's own name that says nothing without its question: a
/// date ("December 31, 2026", "June"), a number or a range ("100-119",
/// "↑ 110,000"). A row is never titled by one alone (founder, 7 November
/// 2026, a page titled only "December 31, 2026"); a person's or a team's
/// name is ("Lula da Silva", over the event's name).
bool _bareItemTitle(String name) {
  final n = name.trim().toLowerCase();
  if (RegExp(r'\d').hasMatch(n)) return true;
  return RegExp(r'^(?:january|february|march|april|may|june|july|august|'
          r'september|october|november|december|jan|feb|mar|apr|jun|jul|'
          r'aug|sept?|oct|nov|dec)\.?$')
      .hasMatch(n);
}

/// What a "Will X win the 2026 Ballon d'Or?" question asks after its
/// candidate [named], for a row with no event yet: "Win 2026 Ballon
/// d'Or", "Win Oct 25".
String _questionRest(
    String question, String named, String Function(DateTime)? date) {
  final short = polyRowShortText(question, date: date);
  final at = short.indexOf(named);
  if (at < 0) return '';
  final words = short
      .substring(at + named.length)
      .trim()
      .split(' ')
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.length > 1 && {'the', 'on', 'in'}.contains(words[1])) {
    words.removeAt(1);
  }
  return _capitalised(words.join(' '));
}

/// A Predictions row's title and context (see the file header), from the
/// market's [question], the [side] held and its [event] when loaded.
/// [date] writes an ISO date found in a title. Pure for the tests.
PolyRowNames polyPositionRowNames({
  required String question,
  required String side,
  String? marketId,
  String? tokenId,
  PolymarketEvent? event,
  String Function(DateTime)? date,
}) {
  final held = side.trim();
  // The event's name, its blank ("by...?") taken out.
  final eventName = event == null
      ? ''
      : polyRowShortText(polyMarketDisplayTitle(event.title), date: date);
  final candidate =
      event == null ? null : _subMarketName(event, question, marketId, tokenId);
  if (candidate != null && !_bareItemTitle(candidate)) {
    return (title: candidate, context: eventName, titleIsSide: false);
  }
  // One market of a grouped event (a deadline of "… by...?", the one it
  // has left open): the event's name alone never says which, so the row
  // is titled by the market's own question.
  final grouped = event != null &&
      (candidate != null ||
          event.marketQuestion != null ||
          polyTitleHasPlaceholder(event.title));
  final binary = held.toLowerCase() == 'yes' || held.toLowerCase() == 'no';
  if (!binary &&
      held.isNotEmpty &&
      held.length <= kPolyRowShortTitle &&
      !_kPlainSides.contains(held.toLowerCase())) {
    return (
      title: held,
      context: eventName.isNotEmpty
          ? eventName
          : polyRowShortText(question, date: date),
      titleIsSide: true,
    );
  }
  if (!grouped &&
      eventName.isNotEmpty &&
      eventName.length <= kPolyRowShortTitle) {
    return (title: eventName, context: '', titleIsSide: false);
  }
  if (event == null) {
    final named = polyChartOutcomeName(question);
    if (named.isNotEmpty &&
        named != question.trim() &&
        named.length <= kPolyRowShortTitle) {
      return (
        title: named,
        context: _questionRest(question, named, date),
        titleIsSide: false,
      );
    }
  }
  final title = polyRowShortText(question, date: date);
  return (
    title: title,
    // The event's name says nothing the grouped market's question does not.
    context: grouped &&
            title.toLowerCase().contains(eventName.toLowerCase())
        ? ''
        : eventName,
    titleIsSide: false,
  );
}

/// The secondary line of a Predictions row: "{context} · {side}", the
/// [status] in place of the side where there is one, the context left out
/// where it reads as the title.
String polyPositionRowLine(PolyRowNames names, String side, {String? status}) {
  final ctx = names.context.isNotEmpty &&
          names.context.toLowerCase() != names.title.toLowerCase()
      ? names.context
      : '';
  final parts = [
    if (ctx.isNotEmpty) ctx else if (!names.titleIsSide && status != null) side,
    if (status != null) status else if (!names.titleIsSide) side,
  ];
  return parts.isEmpty ? (status ?? side) : parts.join(' · ');
}

/// The quiet note under a Predictions row's name on the Portfolio
/// screen's Positions ([PortfolioRowLayout.position], whose side chip
/// says the side): the event where it is not the title, then the
/// [status] where there is one ("Brazil Presidential Election",
/// "Settled"); null with neither.
String? polyPositionRowNote(PolyRowNames names, {String? status}) {
  final ctx = names.context.isNotEmpty &&
          names.context.toLowerCase() != names.title.toLowerCase()
      ? names.context
      : '';
  final parts = [if (ctx.isNotEmpty) ctx, if (status != null) status];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// The side chip of a Predictions row ([PortfolioRowLayout.position]):
/// the side held ("Yes", "No", an outcome's name), none where the title
/// already is the side ("Verstappen").
String? polyPositionRowChip(PolyRowNames names, String side) {
  final held = side.trim();
  if (names.titleIsSide || held.isEmpty) return null;
  if (held.toLowerCase() == names.title.trim().toLowerCase()) return null;
  return held;
}

/// A Predictions position's name where nothing goes under it (the
/// Investing list's row): the title with the side held after
/// it ("Lakers · No", "Bitcoin Up or Down · Up"), the title alone when it
/// is the side ("Verstappen") or the side is a plain Yes. [question] is
/// the market's question for a position whose event is not read: a name
/// cut from it ("Bitcoin" of "Will Bitcoin reach \$150,000 in 2026?", its
/// rest on the line the Investing row does not have) reads as the whole
/// short question instead ("Bitcoin reach \$150,000 in 2026").
String polyPositionListName(PolyRowNames names, String side,
    {String? question, String Function(DateTime)? date}) {
  final held = side.trim();
  final title = question != null &&
          names.context.isNotEmpty &&
          !names.titleIsSide
      ? polyRowShortText(question, date: date)
      : names.title;
  if (names.titleIsSide ||
      held.isEmpty ||
      held.toLowerCase() == 'yes' ||
      held.toLowerCase() == title.trim().toLowerCase()) {
    return title;
  }
  return '$title · $held';
}

/// [rows] with a hairline between each, starting where the text does.
List<Widget> portfolioRowsWithHairlines(
    BuildContext context, List<Widget> rows) {
  final c = context.colors;
  return [
    for (var i = 0; i < rows.length; i++) ...[
      if (i > 0)
        Divider(
          color: context.isDark ? c.border : c.borderSubtle,
          height: 1,
          thickness: 0.5,
          indent: kPortfolioRowImage.w + kPortfolioRowGap.w,
        ),
      rows[i],
    ],
  ];
}

/// The quiet count above the rows ("3 positions").
class PortfolioPositionsCount extends StatelessWidget {
  const PortfolioPositionsCount({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: 4.h),
        child: Text(
          context.l10n.portfolioPositionsCount(count),
          key: const ValueKey('portfolio-positions-count'),
          style: TextStyle(
            color: context.colors.textSecondary,
            fontSize: 14.sp,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.1,
          ),
        ),
      );
}

/// The room a row keeps for its value and pill when it sizes its chance
/// bar, so every bar in the list is as long as the others whatever the
/// figures beside it.
const double kPortfolioRowValueRoom = 96;

/// The held side's chance as a thin bar: 3 pt, rounded, [width] long, the
/// accent over the border colour, with a small upright tick at [entry],
/// the price the position was bought at (where it sits): fill past the
/// tick is the way to a gain.
class PortfolioChanceBar extends StatelessWidget {
  const PortfolioChanceBar(
      {super.key, required this.chance, required this.width, this.entry});

  /// 0 to 1.
  final double chance;
  final double width;

  /// The average price paid, 0 to 1; null draws no tick.
  final double? entry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fill = chance.isFinite ? chance.clamp(0.0, 1.0) : 0.0;
    final at = entry;
    return SizedBox(
      width: width,
      height: 9,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: AlignmentDirectional.centerStart,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(1.5),
            child: SizedBox(
              height: 3,
              width: width,
              child: ColoredBox(
                color: c.border,
                child: FractionallySizedBox(
                  widthFactor: fill,
                  alignment: AlignmentDirectional.centerStart,
                  heightFactor: 1,
                  child: ColoredBox(color: c.accent),
                ),
              ),
            ),
          ),
          if (at != null && at.isFinite && at > 0 && at < 1)
            PositionedDirectional(
              key: const ValueKey('portfolio-row-entry-tick'),
              start: (width * at - 1).clamp(0.0, width - 2),
              top: 0,
              child: Container(
                width: 2,
                height: 9,
                decoration: BoxDecoration(
                  color: c.textPrimary,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The P&L % pill: the up or down colour on its own light tint, the quiet
/// text on the neutral surface when flat.
class PortfolioPnlPill extends StatelessWidget {
  const PortfolioPnlPill(
      {super.key, required this.text, required this.tone, this.amount});

  final String text;
  final PortfolioPnlTone tone;

  /// The P&L in money, unsigned ("$0.61"), written before the %: "▲ $0.61
  /// · 5.4%". Null: the % alone.
  final String? amount;

  /// The pill's ground and text colours for [tone].
  static ({Color background, Color foreground}) colorsFor(
      BuildContext context, PortfolioPnlTone tone) {
    final c = context.colors;
    final tint = context.isDark ? 0.18 : 0.12;
    return switch (tone) {
      PortfolioPnlTone.up => (
          background: AppColors.marketUp.withValues(alpha: tint),
          foreground: AppColors.marketUp,
        ),
      PortfolioPnlTone.down => (
          background: AppColors.marketDown.withValues(alpha: tint),
          foreground: AppColors.marketDown,
        ),
      PortfolioPnlTone.flat => (
          background: c.surfaceLight,
          foreground: c.textSecondary,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = colorsFor(context, tone);
    // Plain figure, brokerage style: a small caret for the direction and
    // the unsigned money and %, in the up/down colour; flat reads "$0.00 ·
    // 0.0%" quietly.
    final shown = text.replaceFirst(RegExp(r'^[+\u2212-]'), '');
    final style = portfolioRowChangeStyle(colors.foreground);
    final amount = this.amount;
    return Row(
      key: const ValueKey('portfolio-row-pnl-pill'),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (tone != PortfolioPnlTone.flat) ...[
          CustomPaint(
            size: Size(7.w, 5.h),
            painter: _CaretPainter(
                up: tone == PortfolioPnlTone.up, color: colors.foreground),
          ),
          SizedBox(width: 4.w),
        ],
        if (amount != null) ...[
          RollingFigure(
            key: const ValueKey('portfolio-row-pnl-usd'),
            text: amount,
            style: style,
          ),
          Text(' · ', style: style),
        ],
        RollingFigure(
          key: const ValueKey('portfolio-row-pnl'),
          text: shown,
          style: style,
        ),
      ],
    );
  }
}

/// The small solid triangle before a P&L figure: up or down.
class _CaretPainter extends CustomPainter {
  const _CaretPainter({required this.up, required this.color});

  final bool up;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = up
        ? (Path()
          ..moveTo(0, size.height)
          ..lineTo(size.width / 2, 0)
          ..lineTo(size.width, size.height))
        : (Path()
          ..moveTo(0, 0)
          ..lineTo(size.width / 2, size.height)
          ..lineTo(size.width, 0));
    canvas.drawPath(path..close(), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_CaretPainter old) => old.up != up || old.color != color;
}

/// One position as a list row (see the file header): its picture, title
/// and secondary line ([chance] adds the chance bar under it), its value
/// with the P&L pill under it ([pnl] null writes none; [detail] a quiet
/// word in its place, "Est. value").
class PortfolioPositionRow extends StatelessWidget {
  const PortfolioPositionRow({
    super.key,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.value,
    this.chance,
    this.entry,
    this.pnl,
    this.pnlAmount,
    this.detail,
    this.onTap,
    this.listName,
    this.chip,
    this.note,
    this.valueColor,
  });

  /// The value's colour on the Positions layout (a closed position's
  /// result in its colour); null: the text colour.
  final Color? valueColor;

  final Widget leading;
  final String title;

  /// The side held, as a small chip after the name on the Portfolio
  /// screen's Positions ([PortfolioRowLayout.position]): "Long", "Short",
  /// "Yes", "No"; null: none.
  final String? chip;

  /// The quiet line under the name there (the event, a state); null:
  /// none, the name alone.
  final String? note;

  /// The name the Investing list's row ([PortfolioRowLayout.market])
  /// writes, which has no line under it to say the side held (a
  /// Predictions row's "Lakers · No"); null: [title].
  final String? listName;
  final String subtitle;
  final String value;
  final double? chance;

  /// The price the held side was bought at (0 to 1): a tick on the chance
  /// bar.
  final double? entry;
  final ({String text, PortfolioPnlTone tone})? pnl;

  /// [pnl] in money, unsigned ("$0.61"): written before its % in every
  /// shape (founder, 6 November 2026: "on each open position say how much
  /// I am actually winning in dollars"). Null: the % alone.
  final String? pnlAmount;
  final String? detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final secondary = portfolioRowSubStyle(context);
    final under = pnl;
    final chance = this.chance;
    switch (PortfolioRowLayoutScope.of(context)) {
      case PortfolioRowLayout.market:
        final change = under == null
            ? null
            : portfolioArrowPnl(context, under, amount: pnlAmount);
        return HlListRow(
          inGroup: true,
          leading: SizedBox.square(
              dimension: kPortfolioRowImage.w, child: leading),
          name: listName ?? title,
          nameKey: const ValueKey('portfolio-row-title'),
          figure: value,
          figureKey: const ValueKey('portfolio-row-value'),
          change: change?.text ?? detail,
          changeColor: change?.color,
          changeKey: ValueKey(
              change != null ? 'portfolio-row-pnl' : 'portfolio-row-detail'),
          onTap: onTap,
        );
      case PortfolioRowLayout.square:
        // The line under the name says the side held: the title alone.
        return _PositionSquare(
          leading: leading,
          name: title,
          subtitle: subtitle,
          value: value,
          change: under == null
              ? null
              : portfolioCornerPnl(context, under, amount: pnlAmount),
          detail: detail,
          onTap: onTap,
        );
      case PortfolioRowLayout.wide:
        return _PositionWide(
          leading: leading,
          name: title,
          subtitle: subtitle,
          value: value,
          change: under == null
              ? null
              : portfolioCornerPnl(context, under, amount: pnlAmount),
          detail: detail,
          onTap: onTap,
        );
      case PortfolioRowLayout.position:
        return _PositionLine(
          leading: leading,
          name: title,
          chip: chip,
          note: note,
          value: value,
          valueColor: valueColor,
          pnl: under,
          pnlAmount: pnlAmount,
          detail: detail,
          onTap: onTap,
        );
      case PortfolioRowLayout.list:
        break;
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: PortfolioRowInset.of(context),
              vertical: PortfolioRowInset.verticalOf(context)),
          child: LayoutBuilder(builder: (context, box) {
            // 80% of the text column a typical value leaves.
            final barWidth = 0.8 *
                (box.maxWidth -
                        kPortfolioRowImage.w -
                        kPortfolioRowGap.w -
                        12.w -
                        kPortfolioRowValueRoom.w)
                    .clamp(0.0, double.infinity);
            return Row(
              children: [
                SizedBox.square(
                    dimension: kPortfolioRowImage.w, child: leading),
                SizedBox(width: kPortfolioRowGap.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Short by construction; a long name takes a second
                      // line rather than being cut on the first.
                      Text(title,
                          key: const ValueKey('portfolio-row-title'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: portfolioRowTitleStyle(context)),
                      SizedBox(height: 2.h),
                      Text(subtitle,
                          key: const ValueKey('portfolio-row-subtitle'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: secondary),
                      if (chance != null) ...[
                        SizedBox(height: 7.h),
                        // Under the title, from where it starts; never
                        // longer than the text column a wide figure
                        // leaves.
                        LayoutBuilder(
                          builder: (context, column) => PortfolioChanceBar(
                              key: const ValueKey('portfolio-row-chance'),
                              chance: chance,
                              entry: entry,
                              width: barWidth.clamp(0.0, column.maxWidth)),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(width: 12.w),
                // The figures take what they need, at most
                // kPortfolioRowFiguresShare of the row, each scaled down
                // past that, never cut at the card's edge.
                ConstrainedBox(
                  key: const ValueKey('portfolio-row-figures'),
                  constraints: BoxConstraints(
                      maxWidth: box.maxWidth * kPortfolioRowFiguresShare),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _figureFit(RollingFigure(
                        key: const ValueKey('portfolio-row-value'),
                        text: value,
                        style: portfolioRowFigureStyle(context),
                      )),
                      if (under != null) ...[
                        SizedBox(height: 2.h),
                        _figureFit(PortfolioPnlPill(
                            text: under.text,
                            tone: under.tone,
                            amount: pnlAmount)),
                      ] else if (detail case final word?) ...[
                        SizedBox(height: 4.h),
                        _figureFit(Text(word, maxLines: 1, style: secondary)),
                      ],
                    ],
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

/// "+$1.20 (+8.0%)": a P&L as the Positions rows write it, the money
/// signed and its percent after it; "$0.00 (0.0%)" when flat. [amount] is
/// the money unsigned; without it the percent alone.
String portfolioSignedPnl(
    ({String text, PortfolioPnlTone tone}) pnl, String? amount) {
  final sign = switch (pnl.tone) {
    PortfolioPnlTone.up => '+',
    PortfolioPnlTone.down => '−',
    PortfolioPnlTone.flat => '',
  };
  return amount == null ? pnl.text : '$sign$amount (${pnl.text})';
}

/// One position on the Portfolio screen's Positions
/// ([PortfolioRowLayout.position]): the picture, the name with its side
/// chip after it (HlMetaChip, the app's neutral chip; the name takes two
/// lines rather than being cut), the [note] quiet under it where there is
/// one; at the end the value (15 w600, rolling) over the P&L since it was
/// opened in its colour ([portfolioSignedPnl]), or the quiet [detail].
/// No leverage, no mark price, no return on equity: the position screen
/// has the rest. The row's padding is [PortfolioRowInset]'s, inside its
/// ink.
class _PositionLine extends StatelessWidget {
  const _PositionLine({
    required this.leading,
    required this.name,
    required this.chip,
    required this.note,
    required this.value,
    required this.pnl,
    required this.pnlAmount,
    required this.detail,
    required this.onTap,
    this.valueColor,
  });

  final Widget leading;
  final String name;
  final String? chip;
  final String? note;
  final String value;
  final Color? valueColor;
  final ({String text, PortfolioPnlTone tone})? pnl;
  final String? pnlAmount;
  final String? detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final secondary = portfolioRowSubStyle(context);
    final under = pnl;
    final chip = this.chip;
    final note = this.note;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: PortfolioRowInset.of(context),
              vertical: PortfolioRowInset.verticalOf(context)),
          child: LayoutBuilder(
            builder: (context, box) => Row(
              children: [
                SizedBox.square(
                    dimension: kPortfolioRowImage.w, child: leading),
                SizedBox(width: kPortfolioRowGap.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(text: name),
                          if (chip != null)
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: Padding(
                                padding:
                                    EdgeInsetsDirectional.only(start: 6.w),
                                child: HlMetaChip(
                                    key: const ValueKey('portfolio-row-chip'),
                                    text: chip),
                              ),
                            ),
                        ]),
                        key: const ValueKey('portfolio-row-title'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: portfolioRowTitleStyle(context),
                      ),
                      if (note != null) ...[
                        SizedBox(height: 2.h),
                        Text(note,
                            key: const ValueKey('portfolio-row-subtitle'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: secondary),
                      ],
                    ],
                  ),
                ),
                SizedBox(width: 12.w),
                // The figures take what they need, at most
                // kPortfolioRowFiguresShare of the row, each scaled down
                // past that, never cut at the card's edge.
                ConstrainedBox(
                  key: const ValueKey('portfolio-row-figures'),
                  constraints: BoxConstraints(
                      maxWidth: box.maxWidth * kPortfolioRowFiguresShare),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _figureFit(RollingFigure(
                        key: const ValueKey('portfolio-row-value'),
                        text: value,
                        style: portfolioRowFigureStyle(context,
                            color: valueColor),
                      )),
                      if (under != null) ...[
                        SizedBox(height: 2.h),
                        _figureFit(RollingFigure(
                          key: const ValueKey('portfolio-row-pnl'),
                          text: portfolioSignedPnl(under, pnlAmount),
                          style: portfolioRowChangeStyle(
                              PortfolioPnlPill.colorsFor(context, under.tone)
                                  .foreground),
                        )),
                      ] else if (detail case final word?) ...[
                        SizedBox(height: 2.h),
                        _figureFit(Text(word,
                            key: const ValueKey('portfolio-row-detail'),
                            maxLines: 1,
                            style: secondary)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A figure at a row's end: its own width, scaled down (never cut) when
/// the figure column is narrower.
Widget _figureFit(Widget figure) => FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerEnd,
      child: figure,
    );

/// One position as a big square (see the file header; drawn as the
/// Investing grid's HlMovingNowCard and the home's Latest squares): the
/// grouped card's ground, 14 padding, [portfolioSquareHeight] tall; the
/// logo ([kPortfolioSquareIcon]) top-left, the P&L ([change]: in money
/// over its %, or the quiet [detail]) top-right, then the name and the
/// line under it quiet over the value at 22 sp. The whole square taps through to the position
/// on the press spring.
class _PositionSquare extends StatelessWidget {
  const _PositionSquare({
    required this.leading,
    required this.name,
    required this.subtitle,
    required this.value,
    required this.change,
    required this.detail,
    required this.onTap,
  });

  final Widget leading;
  final String name;
  final String subtitle;
  final String value;
  final PortfolioCornerPnl? change;
  final String? detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final decoration = PremiumGroupContainer.decorationOf(context);
    final radius = decoration.borderRadius as BorderRadius?;
    final quiet = TextStyle(
      color: c.textSecondary,
      fontSize: 13.sp,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.1,
      height: 1.25,
    );
    final change = this.change;
    final corner = change?.percent ?? detail;
    final icon = kPortfolioSquareIcon.w;
    final cornerStyle = quiet.copyWith(
      color: change?.color ?? c.textSecondary,
      fontWeight: FontWeight.w600,
      height: 1.2,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final amount = change?.amount;
    return KutePressable(
      enabled: onTap != null,
      child: Container(
        key: const ValueKey('portfolio-square'),
        height: portfolioSquareHeight(context),
        decoration: decoration,
        child: Material(
          color: Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: Padding(
              padding: EdgeInsets.all(_kSquarePad.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // The row's picture, drawn at the square's size.
                      SizedBox.square(
                        dimension: icon,
                        child: FittedBox(child: leading),
                      ),
                      SizedBox(width: 8.w),
                      if (corner != null)
                        Expanded(
                          child: Align(
                            alignment: Alignment.topRight,
                            // The money over its %, right-aligned; a wide
                            // figure scales down rather than run into the
                            // logo.
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.topRight,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (amount != null) ...[
                                    RollingFigure(
                                      key: const ValueKey(
                                          'portfolio-row-pnl-usd'),
                                      text: amount,
                                      style: cornerStyle,
                                    ),
                                    SizedBox(height: 1.h),
                                  ],
                                  RollingFigure(
                                    key: ValueKey(change != null
                                        ? 'portfolio-row-pnl'
                                        : 'portfolio-row-detail'),
                                    text: corner,
                                    style: amount == null
                                        ? cornerStyle
                                        : cornerStyle.copyWith(
                                            fontSize: 12.sp,
                                            fontWeight: FontWeight.w500,
                                            height: 1.3),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const Spacer(),
                  Text(name,
                      key: const ValueKey('portfolio-row-title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: quiet),
                  SizedBox(height: 2.h),
                  Text(subtitle,
                      key: const ValueKey('portfolio-row-subtitle'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: quiet.copyWith(
                          color: c.textTertiary,
                          fontSize: 12.sp,
                          height: 1.3)),
                  SizedBox(height: 4.h),
                  // A value too wide for the square shrinks rather than
                  // overflow it.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: RollingFigure(
                      key: const ValueKey('portfolio-row-value'),
                      text: value,
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 22.sp,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.6,
                        height: 1.2,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One position as the full-width compact card an odd last square becomes
/// ([PortfolioPositionSquares], the no-orphan rule): the square's ground
/// and padding, one row: the logo ([kPortfolioSquareIcon]) on the left,
/// the name over the side held quiet, then the value, and at the end the
/// P&L as the square's corner writes it (the money over its %, or the
/// quiet [detail]) in its colour. Its own content's height, never taller
/// than it needs; the whole card taps through on the press spring.
class _PositionWide extends StatelessWidget {
  const _PositionWide({
    required this.leading,
    required this.name,
    required this.subtitle,
    required this.value,
    required this.change,
    required this.detail,
    required this.onTap,
  });

  final Widget leading;
  final String name;
  final String subtitle;
  final String value;
  final PortfolioCornerPnl? change;
  final String? detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final decoration = PremiumGroupContainer.decorationOf(context);
    final radius = decoration.borderRadius as BorderRadius?;
    final change = this.change;
    final corner = change?.percent ?? detail;
    final amount = change?.amount;
    final cornerStyle = TextStyle(
      color: change?.color ?? c.textSecondary,
      fontSize: 13.sp,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
      height: 1.2,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return KutePressable(
      enabled: onTap != null,
      child: Container(
        key: const ValueKey('portfolio-wide'),
        decoration: decoration,
        child: Material(
          color: Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: Padding(
              padding: EdgeInsets.all(_kSquarePad.w),
              child: LayoutBuilder(builder: (context, box) {
                return Row(
                  children: [
                    // The row's picture, drawn at the square's size.
                    SizedBox.square(
                      dimension: kPortfolioSquareIcon.w,
                      child: FittedBox(child: leading),
                    ),
                    SizedBox(width: kPortfolioRowGap.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(name,
                              key: const ValueKey('portfolio-row-title'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: portfolioRowTitleStyle(context)),
                          SizedBox(height: 2.h),
                          Text(subtitle,
                              key: const ValueKey('portfolio-row-subtitle'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: portfolioRowSubStyle(context)),
                        ],
                      ),
                    ),
                    SizedBox(width: 12.w),
                    // The figures take what they need, at most
                    // kPortfolioRowFiguresShare of the card, scaled down
                    // past that, never cut at its edge.
                    ConstrainedBox(
                      constraints: BoxConstraints(
                          maxWidth: box.maxWidth * kPortfolioRowFiguresShare),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerEnd,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            RollingFigure(
                              key: const ValueKey('portfolio-row-value'),
                              text: value,
                              style: TextStyle(
                                color: c.textPrimary,
                                fontSize: 17.sp,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.4,
                                height: 1.2,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                            if (corner != null) ...[
                              SizedBox(width: 12.w),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (amount != null) ...[
                                    RollingFigure(
                                      key: const ValueKey(
                                          'portfolio-row-pnl-usd'),
                                      text: amount,
                                      style: cornerStyle,
                                    ),
                                    SizedBox(height: 1.h),
                                  ],
                                  RollingFigure(
                                    key: ValueKey(change != null
                                        ? 'portfolio-row-pnl'
                                        : 'portfolio-row-detail'),
                                    text: corner,
                                    style: amount == null
                                        ? cornerStyle
                                        : cornerStyle.copyWith(
                                            fontSize: 12.sp,
                                            fontWeight: FontWeight.w500,
                                            height: 1.3),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

/// A Predictions picture: the market's image in the row's circle.
Widget _polyImage(String title, String? imageUrl, {String category = ''}) =>
    ClipOval(
      key: const ValueKey('portfolio-row-image-circle'),
      child: PolyCardThumbnail(
        title: title,
        imageUrl: imageUrl,
        category: category,
        size: kPortfolioRowImage.w,
        radius: kPortfolioRowImage.w / 2,
      ),
    );

/// Writes an ISO date found in a market's title in the app's language
/// ("Oct 25").
String Function(DateTime) _rowDate(BuildContext context) {
  final locale = Localizations.localeOf(context).toString();
  return (d) => DateFormat.MMMd(locale).format(d);
}

/// A held Polymarket position's row title ([polyPositionRowNames], an
/// ISO date written in the app's language), its [event] when loaded: the
/// name the Portfolio screen's ring gives its slice too.
String polyPositionRowTitle(
        BuildContext context, PolymarketPosition p, PolymarketEvent? event) =>
    polyPositionRowNames(
      question: p.marketQuestion,
      side: p.outcome,
      marketId: p.marketId,
      tokenId: p.tokenId,
      event: event,
      date: _rowDate(context),
    ).title;

/// One held Polymarket position. Its value and its chance bar follow the
/// held outcome's live price; a sale on its way, a resolved market or a
/// market waiting for its result says so in place of the side. Tap: the
/// open-position screen, as the card did.
class PolyPositionRow extends ConsumerWidget {
  const PolyPositionRow({super.key, required this.position});

  final PolymarketPosition position;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final p = position;
    final live = ref.watch(
        livePriceProvider.select((s) => s.live ? s.prices[p.tokenId] : null));
    final price = p.isResolved ? p.currentPrice : live ?? p.currentPrice;
    final value = p.size * price;
    final pnl = (price - p.avgPrice) * p.size;
    final pnlPercent = p.avgPrice > 0 ? (price / p.avgPrice - 1) * 100 : 0.0;
    final selling = p.tokenId != null &&
        ref.watch(polymarketTradingProvider.select((s) =>
            s.valueOrNull?.pendingSaleTokens.contains(p.tokenId) ?? false));

    final slug = p.eventSlug;
    final event = slug == null || slug.isEmpty
        ? null
        : ref.watch(polyPositionEventProvider(slug));
    final isGame = event != null &&
        !event.isSyntheticBinary &&
        (event.gameId != null || event.metadataGameId != null);

    // The state, where the position has one, in place of the side.
    String? status;
    if (selling) {
      status = l10n.betSellingEllipsis;
    } else if (p.isResolved) {
      // A win is claimed automatically: it reads "Settled" like any
      // closed position.
      status = l10n.activitySettled;
    } else {
      final end = polyPositionEnd(p);
      final shortRound = polyIsShortRound(slug);
      if (shortRound && end != null) {
        final left = end.difference(DateTime.now());
        if (left > Duration.zero && left < const Duration(hours: 1)) {
          ref.watch(polyMinuteTickProvider);
        }
        if (left > Duration.zero && left <= const Duration(minutes: 1)) {
          ref.watch(polyAwaitingTickProvider);
        }
      }
      if (polyMarketHasEnded(
          eventSlug: slug, end: end, event: event, isGame: isGame)) {
        final cid = p.marketId;
        final settleAt = cid.isEmpty
            ? null
            : ref.watch(polyExpectedSettlementProvider(cid)).valueOrNull;
        if (settleAt != null) ref.watch(polyMinuteTickProvider);
        final roundEnd = polyShortRoundEnd(slug);
        if (polyShortRoundEstimating(roundEnd, DateTime.now())) {
          ref.watch(polyAwaitingTickProvider);
        }
        status = polyAwaitingText(
            l10n, polyAwaitingResultFor(p.size > 0 ? value / p.size : null),
            shortRound: shortRound, settleAt: settleAt, roundEnd: roundEnd);
      }
    }
    final names = polyPositionRowNames(
      question: p.marketQuestion,
      side: p.outcome,
      marketId: p.marketId,
      tokenId: p.tokenId,
      event: event,
      date: _rowDate(context),
    );

    // Crest first: a sports market carries the league's generic ball as
    // its image; the held team's crest is in the event's teams. A bare
    // Yes / No is never matched against a name.
    final teams = event?.teams ?? const [];
    final side = p.outcome.trim().toLowerCase();
    final image = (side == 'yes' || side == 'no'
            ? null
            : PolymarketEvent.logoFromTeams(teams, p.outcome)) ??
        PolymarketEvent.logoForText(teams, p.marketQuestion) ??
        p.marketImage;

    String money(double usd) => formatPolyAmount(ref, usd);
    return LiveTokenScope(
      tokens: [if (!p.isResolved && p.tokenId != null) p.tokenId!],
      keepAlive: true,
      child: PortfolioPositionRow(
        leading: _polyImage(p.marketQuestion, image,
            category: event?.category ?? ''),
        title: names.title,
        listName: polyPositionListName(names, p.outcome,
            question: event == null ? p.marketQuestion : null,
            date: _rowDate(context)),
        subtitle: polyPositionRowLine(names, p.outcome, status: status),
        chip: polyPositionRowChip(names, p.outcome),
        note: polyPositionRowNote(names, status: status),
        value: money(value),
        chance: p.isResolved ? null : price,
        entry: p.isResolved ? null : p.avgPrice,
        pnl: portfolioPnlPill(pnl, percent: pnlPercent),
        pnlAmount: money(pnl.abs()),
        onTap: () {
          HapticFeedback.selectionClick();
          TrackingService.track('open_investments_position_tapped',
              params: {'product': 'predictions'});
          PositionDetailSheet.show(context, position: p);
        },
      ),
    );
  }
}

/// A held combo (parlay): "Combo · N legs", its stake or its outcome,
/// its value (an estimate while open, labelled so; what it made or lost
/// once settled). Tap: the combo's sheet, as the card did.
class ComboPositionRow extends StatelessWidget {
  const ComboPositionRow({super.key, required this.position});

  final ComboPosition position;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final p = position;
    final settled = p.settledPayoutUsd;
    final lost = p.isLost;
    final value = lost ? 0.0 : (settled ?? p.estimatedValueUsd);
    final pnl = value - p.stakeUsd;
    final firstImage =
        p.legs.map((l) => l.imageUrl).whereType<String>().firstOrNull;
    final title = l10n.comboLegsLabel(p.legsTotal);
    return PortfolioPositionRow(
      leading: _polyImage(title, firstImage),
      title: title,
      subtitle: lost
          ? l10n.comboLegLost
          : settled != null
              ? l10n.activitySettled
              : '${l10n.comboStake} ${formatHlUsd(p.stakeUsd)}',
      note: lost
          ? l10n.comboLegLost
          : settled != null
              ? l10n.activitySettled
              : '${l10n.comboStake} ${formatHlUsd(p.stakeUsd)}',
      value: formatHlUsd(value),
      pnl: lost || settled != null
          ? portfolioPnlPill(pnl,
              percent: p.stakeUsd > 0 ? pnl / p.stakeUsd * 100 : null)
          : null,
      pnlAmount: formatHlUsd(pnl.abs()),
      detail: l10n.comboEstimatedValue,
      onTap: () {
        HapticFeedback.selectionClick();
        TrackingService.track('open_investments_position_tapped',
            params: {'product': 'predictions', 'kind': 'combo'});
        ComboDetailSheet.show(context, conditionId: p.conditionId);
      },
    );
  }
}

/// A bet on its way to the book: its stake as the number, its step in
/// place of the facts. No tap, as before.
class PlacingBetRow extends ConsumerWidget {
  const PlacingBetRow({super.key, required this.bet});

  final PlacingBet bet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final p = bet;
    final step = p.status == PlacingBetStatus.failed
        ? l10n.openInvestPlacementFailed
        : p.stepLabel ?? l10n.openInvestUpdatingPosition;
    final names = polyPositionRowNames(
        question: p.marketQuestion,
        side: p.outcomeName,
        date: _rowDate(context));
    return PortfolioPositionRow(
      leading: _polyImage(p.marketQuestion, p.marketImage),
      title: names.title,
      listName: polyPositionListName(names, p.outcomeName,
          question: p.marketQuestion, date: _rowDate(context)),
      subtitle: polyPositionRowLine(names, p.outcomeName, status: step),
      chip: polyPositionRowChip(names, p.outcomeName),
      note: polyPositionRowNote(names, status: step),
      value: formatPolyAmount(ref, p.amount),
    );
  }
}

/// An Investing logo, round, at the row's size.
Widget _hlImage(
        {required String coin,
        String? wireCoin,
        String? iconUrl,
        String? category}) =>
    ClipOval(
      child: HlCoinIcon(
        coin: coin,
        wireCoin: wireCoin,
        iconUrl: iconUrl,
        category: category,
        size: kPortfolioRowImage.w,
      ),
    );

/// The ticker without its dex ("xyz:NVDA" → "NVDA").
String _ticker(String coin) => coin.contains(':') ? coin.split(':').last : coin;

/// One open Hyperliquid perp: its logo and name, "Long · 0.0125 BTC" (no
/// leverage figure; the entry price is on the position screen), what
/// closing it now gives back ([hlCloseValue]) with its return on the
/// margin in the pill, at the live mid. Tap: the position details, as the
/// card did.
class HlPositionRow extends ConsumerWidget {
  const HlPositionRow({super.key, required this.position});

  final HlPerpPosition position;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final p = position;
    final mid = ref.watch(hyperliquidLiveMidProvider(p.coin));
    final pnl = hlLivePnl(p, liveMid: mid);
    final margin = hlPositionMargin(p);
    final roe = margin > 0 ? pnl / margin : p.returnOnEquity;
    final descriptor = ref.watch(hyperliquidAccountMarketProvider(p.coin));
    final coin = descriptor?.coin ?? p.coin;
    String money(double usd) => formatPolyAmount(ref, usd);
    return PortfolioPositionRow(
      leading: _hlImage(
          coin: coin,
          wireCoin: descriptor?.wireCoin ?? p.coin,
          iconUrl: descriptor?.iconUrl,
          category: descriptor?.category),
      title: hlFriendlyName(p.coin) ??
          hlFriendlyName(coin) ??
          descriptor?.unitAssetName ??
          coin,
      subtitle: '${p.isLong ? l10n.longLabel : l10n.shortLabel} · '
          '${formatHlSize(p.szi.abs())} ${_ticker(coin)}',
      // Positions: the side alone; the size and the entry are on the
      // position screen.
      chip: p.isLong ? l10n.longLabel : l10n.shortLabel,
      value: money(hlCloseValue(p, liveMid: mid)),
      pnl: portfolioPnlPill(pnl, percent: roe * 100),
      pnlAmount: money(pnl.abs()),
      onTap: () {
        HapticFeedback.selectionClick();
        TrackingService.track('open_investments_position_tapped',
            params: {'product': 'trading'});
        HlPositionDetailSheet.show(context, position: p, market: descriptor);
      },
    );
  }
}

/// A spot holding: its logo and name, "0.5 HYPE · Spot", its value at the
/// mid with the P&L against what the venue records as paid (none for a
/// holding with no cost on record). Tap: the market, as the card did.
class HlSpotRow extends ConsumerWidget {
  const HlSpotRow({super.key, required this.balance});

  final HlSpotBalance balance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final markets = ref.watch(hyperliquidSpotMarketsProvider).valueOrNull ??
        const <HlMarket>[];
    final market = markets.where((m) => m.coin == balance.coin).firstOrNull;
    final value = market != null && market.midPx > 0
        ? balance.total * market.midPx
        : null;
    final cost = balance.costBasis;
    final pnl = cost != null && value != null ? value - cost : null;
    String money(double usd) => formatPolyAmount(ref, usd);
    return PortfolioPositionRow(
      leading: _hlImage(
          coin: balance.coin,
          wireCoin: market?.wireCoin,
          iconUrl: market?.iconUrl,
          category: market?.category),
      title:
          hlFriendlyName(balance.coin) ?? market?.unitAssetName ?? balance.coin,
      subtitle:
          '${formatHlSize(balance.total)} ${balance.coin} · ${l10n.investingSpot}',
      value: value == null ? '—' : money(value),
      pnl: pnl == null
          ? null
          : portfolioPnlPill(pnl,
              percent: cost != null && cost > 0 ? pnl / cost * 100 : null),
      pnlAmount: pnl == null ? null : money(pnl.abs()),
      onTap: market == null
          ? null
          : () {
              TrackingService.track('open_investments_position_tapped',
                  params: {'product': 'trading', 'kind': 'spot'});
              HlMarketDetailSheet.show(context, market: market);
            },
    );
  }
}

/// A closed position on the Portfolio screen's P&L ("Closed positions"):
/// a prediction decided ([prediction]: closed, or resolved and waiting to
/// be claimed) or an Investing position closed, reduced or sold ([fill],
/// its order's last fill; [long] the side it closed, null for a holding
/// sold), drawn as a Positions row ([PortfolioRowLayout.position]): the
/// picture, the name and its side chip, the day it closed under it, and
/// its result ([resultUsd], what closing it realised net of the fees in
/// dollars) signed in its colour at the end. Masked with balances hidden.
class PortfolioClosedRow extends ConsumerWidget {
  const PortfolioClosedRow({
    super.key,
    required this.at,
    required this.resultUsd,
    this.prediction,
    this.fill,
    this.long,
  }) : assert((prediction == null) != (fill == null));

  final DateTime at;
  final double resultUsd;
  final PredictionRecord? prediction;
  final HlFill? fill;
  final bool? long;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = context.colors;
    final visible = ref.watch(settingsProvider.select((s) => s.balanceVisible));
    final usd = resultUsd.abs() < 0.005 ? 0.0 : resultUsd;
    final value = !visible
        ? '••••••'
        : '${usd > 0 ? '+' : usd < 0 ? '−' : ''}'
            '${formatPolyAmount(ref, usd.abs())}';
    final color = !visible || usd == 0
        ? c.textPrimary
        : usd > 0
            ? AppColors.marketUp
            : AppColors.marketDown;
    final day = _rowDate(context)(at.toLocal());
    final Widget leading;
    final String title;
    final String? chip;
    final p = prediction;
    final f = fill;
    if (p != null) {
      final names = polyPositionRowNames(
        question: p.title,
        side: p.outcome,
        marketId: p.conditionId,
        tokenId: p.tokenId,
        date: _rowDate(context),
      );
      leading = _polyImage(p.title, p.icon.isEmpty ? null : p.icon);
      // A record without its question: the side held, else the venue.
      title = names.title.trim().isNotEmpty
          ? names.title
          : p.outcome.trim().isNotEmpty
              ? p.outcome
              : l10n.predictions;
      chip = polyPositionRowChip(names, p.outcome);
    } else {
      final market = ref.watch(hyperliquidAccountMarketProvider(f!.coin));
      final coin = market?.coin ?? f.coin;
      leading = _hlImage(
          coin: coin,
          wireCoin: market?.wireCoin ?? f.coin,
          iconUrl: market?.iconUrl,
          category: market?.category);
      final symbol = hlBaseCoin(coin);
      title = hlFriendlyName(symbol) ??
          hlFriendlyName(coin) ??
          market?.unitAssetName ??
          symbol;
      chip = switch (long) {
        true => l10n.longLabel,
        false => l10n.shortLabel,
        null => null,
      };
    }
    return PortfolioRowLayoutScope(
      layout: PortfolioRowLayout.position,
      child: PortfolioPositionRow(
        leading: leading,
        title: title,
        subtitle: day,
        chip: chip,
        note: day,
        value: value,
        valueColor: color,
      ),
    );
  }
}
