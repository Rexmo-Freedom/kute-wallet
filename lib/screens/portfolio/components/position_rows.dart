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
//   * on the right what it is worth now (w600) with the P&L as a % in a
//     small pill under it, tinted up or down; a P&L under a cent reads
//     "0.0%" on the quiet surface, never a red minus ([portfolioPnlPill]).
//     The $ P&L is on the position screen.
//
// The list draws hairlines between rows ([portfolioRowsWithHairlines]).
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
import 'package:kute/screens/hyperliquid/components/hl_isolated_margin.dart';
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
import 'package:kute/screens/shared/kute_motion.dart' show RollingFigure;
import 'package:kute/services/polymarket/combos/combo_models.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// A row's picture (a circle) and the gap after it.
const double kPortfolioRowImage = 40;
const double kPortfolioRowGap = 12;

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
  final eventName =
      event == null ? '' : polyRowShortText(event.title, date: date);
  final candidate =
      event == null ? null : _subMarketName(event, question, marketId, tokenId);
  if (candidate != null) {
    return (title: candidate, context: eventName, titleIsSide: false);
  }
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
  if (eventName.isNotEmpty && eventName.length <= kPolyRowShortTitle) {
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
  return (
    title: polyRowShortText(question, date: date),
    context: eventName,
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
  const PortfolioPnlPill({super.key, required this.text, required this.tone});

  final String text;
  final PortfolioPnlTone tone;

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
    // the unsigned %, in the up/down colour; flat reads "0.0%" quietly.
    final shown = text.replaceFirst(RegExp(r'^[+\u2212-]'), '');
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
        RollingFigure(
          key: const ValueKey('portfolio-row-pnl'),
          text: shown,
          style: TextStyle(
            color: colors.foreground,
            fontSize: 13.sp,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.1,
            height: 1.3,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
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
    this.detail,
    this.onTap,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final String value;
  final double? chance;

  /// The price the held side was bought at (0 to 1): a tick on the chance
  /// bar.
  final double? entry;
  final ({String text, PortfolioPnlTone tone})? pnl;
  final String? detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final secondary = TextStyle(
      color: c.textSecondary,
      fontSize: 13.sp,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.1,
      height: 1.3,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final under = pnl;
    final chance = this.chance;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 14.h),
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
                          style: AppTextStyles.settingsTitle(context).copyWith(
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                              height: 1.25)),
                      SizedBox(height: 2.h),
                      Text(subtitle,
                          key: const ValueKey('portfolio-row-subtitle'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: secondary),
                      if (chance != null) ...[
                        SizedBox(height: 7.h),
                        PortfolioChanceBar(
                            key: const ValueKey('portfolio-row-chance'),
                            chance: chance,
                            entry: entry,
                            width: barWidth),
                      ],
                    ],
                  ),
                ),
                SizedBox(width: 12.w),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 140.w),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerEnd,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RollingFigure(
                          key: const ValueKey('portfolio-row-value'),
                          text: value,
                          style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                            height: 1.25,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        if (under != null) ...[
                          SizedBox(height: 4.h),
                          PortfolioPnlPill(text: under.text, tone: under.tone),
                        ] else if (detail case final word?) ...[
                          SizedBox(height: 4.h),
                          Text(word, maxLines: 1, style: secondary),
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
        subtitle: polyPositionRowLine(names, p.outcome, status: status),
        value: money(value),
        chance: p.isResolved ? null : price,
        entry: p.isResolved ? null : p.avgPrice,
        pnl: portfolioPnlPill(pnl, percent: pnlPercent),
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
      value: formatHlUsd(value),
      pnl: lost || settled != null
          ? portfolioPnlPill(pnl,
              percent: p.stakeUsd > 0 ? pnl / p.stakeUsd * 100 : null)
          : null,
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
      subtitle: polyPositionRowLine(names, p.outcomeName, status: step),
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
      value: money(hlCloseValue(p, liveMid: mid)),
      pnl: portfolioPnlPill(pnl, percent: roe * 100),
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
      onTap: market == null
          ? null
          : () => HlMarketDetailSheet.show(context, market: market),
    );
  }
}
