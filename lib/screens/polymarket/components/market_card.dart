import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_browse_provider.dart'
    show polymarketEventTeamsProvider;
import 'package:kute/screens/polymarket/components/bet_slip_sheet.dart'
    show BetSlipSheet;
import 'package:kute/screens/polymarket/components/poly_category_icons.dart';
import 'package:kute/screens/polymarket/components/poly_crest_image.dart';
import 'package:kute/screens/polymarket/components/outcome_leading.dart'
    show kPolyOutcomeColors, polyChartedOutcomes;
import 'package:kute/screens/polymarket/components/live_game.dart';
import 'package:kute/screens/polymarket/components/game_time.dart';
import 'package:kute/screens/polymarket/components/game_chart_section.dart'
    show gameSideColors, kGameSideColors;
import 'package:kute/providers/polymarket_card_spark_provider.dart'
    show polyCardSparkProvider;
import 'package:kute/services/polymarket/poly_card_spark_store.dart'
    show PolyCardSparkStore, polyCardSparkValues;
import 'package:kute/screens/hyperliquid/components/hl_charts.dart'
    show HlLineSparkline;
import 'package:kute/services/polymarket/live_game/game_sides.dart'
    show gameShortSideNames;
import 'package:kute/screens/shared/kute_motion.dart';
import 'package:kute/services/polymarket/market_buy_quote.dart'
    show polymarketCentsLabel;
import 'package:kute/services/polymarket/market_card_shape.dart';
import 'package:kute/theme/app_theme.dart';
import 'dart:math' as math;
import 'dart:math' show pi;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart' hide TextDirection;

/// The list thumbnail and the gap after it.
const double kPolyCardImage = 40;
const double kPolyCardImageGap = 10;

/// Where a grouped row's title starts, for the group's hairline: the
/// row's 16 inset, the thumbnail and the gap after it.
double polyGroupRowIndent() => 16.w + kPolyCardImage.w + kPolyCardImageGap.w;

/// Whether [title]'s market is a plain Yes/No one: the shape the lists
/// group into one card (an event with many outcomes, or a game, keeps a
/// card of its own).
bool polyCardGroups(String title, List<PolymarketOutcome> outcomes) =>
    polyCardShape(polyCardGame(title, outcomes), outcomes) ==
    PolyCardShape.yesNo;

/// The outcome that leads [outcomes], for a Top markets card
/// (top_markets_strip.dart): for a Yes/No market the likelier side ("Yes"
/// / "No", in the app's words), else the most likely outcome
/// ([polyCardTopOutcomes]). Its price is [live]'s where the feed has one.
/// Null with no outcome at all.
({String name, double price, bool binary})? polyRowLeader(
    AppLocalizations l10n, List<PolymarketOutcome> outcomes,
    {Map<String, double> live = const {}}) {
  double price(PolymarketOutcome o) =>
      ((o.tokenId == null ? null : live[o.tokenId]) ?? o.price)
          .clamp(0.0, 1.0);
  if (polyCardIsYesNo(outcomes)) {
    final yes =
        outcomes.firstWhere((o) => o.name.trim().toLowerCase() == 'yes');
    final no =
        outcomes.where((o) => o.name.trim().toLowerCase() == 'no').firstOrNull;
    final yesPrice = price(yes);
    // The No side's own price when the feed has it, else what Yes leaves.
    final noPrice = no == null ? 1 - yesPrice : price(no);
    return yesPrice >= noPrice
        ? (name: l10n.yes, price: yesPrice, binary: true)
        : (name: l10n.betNo, price: noPrice, binary: true);
  }
  final top = polyCardTopOutcomes(outcomes, live: live, count: 1).firstOrNull;
  if (top == null) return null;
  return (name: top.name, price: price(top), binary: false);
}

/// Between two Predictions rows of a group: a hairline at half the border
/// colour, from where the title starts (Kalshi / Polymarket rows).
Widget polyGroupRowDivider(BuildContext context, double indent) => Divider(
      color: context.colors.border.withValues(alpha: 0.5),
      height: 1,
      thickness: 0.5,
      indent: indent,
    );

/// What a card's pill opens the slip on (founder, 12 November 2026: one
/// tap to the slip, money only after Confirm there): a side of a single
/// market ('yes' / 'no') or one side of a game (0 the title's first
/// team, 1 the draw, 2 the second).
@immutable
class PolyCardPick {
  final String? side;
  final int? way;
  const PolyCardPick.side(String this.side) : way = null;
  const PolyCardPick.game(int this.way) : side = null;

  @override
  bool operator ==(Object other) =>
      other is PolyCardPick && other.side == side && other.way == way;

  @override
  int get hashCode => Object.hash(side, way);

  @override
  String toString() => 'PolyCardPick(${side ?? way})';
}

/// Opens the bet slip on [side] ('yes' / 'no') of [event], or on [pick],
/// the way the market page's own buttons do ([MarketCard.onPickSide] from
/// a card's pill): the side's outcome preselected, nothing new in between
/// and nothing placed, funded or approved (that waits for Confirm on the
/// slip). [source] is the list the card sits in, for the slip's existing
/// open event.
void polyCardOpenSlip(
  BuildContext context, {
  required PolymarketEvent event,
  String? side,
  PolyCardPick? pick,
  required String source,
  VoidCallback? onDeposit,
  String? ledgerWalletId,
}) {
  HapticFeedback.mediumImpact();
  void open({
    required List<PolymarketOutcome> outcomes,
    required int index,
    String? pos,
    String? neg,
    List<Color?>? colors,
    List<String>? labels,
  }) =>
      BetSlipSheet.show(
        context,
        event: event,
        negRisk: event.negRisk,
        marketQuestion: event.displayTitle,
        marketSlug: event.slug,
        marketImage: event.imageUrl,
        outcomes: outcomes,
        initialOutcomeIndex: index,
        onDeposit: onDeposit,
        ledgerWalletId: ledgerWalletId,
        marketCategory: event.category,
        marketEndAt: event.endDate,
        sideLabelPos: pos,
        sideLabelNeg: neg,
        outcomeColors: colors,
        outcomeLabels: labels,
        source: source,
      );
  // One market's two sides, Yes first, opened on [no] or not.
  List<PolymarketOutcome> pair(PolymarketOutcome m) {
    final yes = m.price.clamp(0.0, 1.0).toDouble();
    return [
      PolymarketOutcome(
        name: 'Yes',
        price: yes,
        tokenId: m.tokenId,
        conditionId: m.conditionId,
        gammaMarketId: m.gammaMarketId,
      ),
      PolymarketOutcome(
        name: 'No',
        price: 1.0 - yes,
        tokenId: m.noTokenId,
        conditionId: m.conditionId,
        gammaMarketId: m.gammaMarketId,
      ),
    ];
  }

  final way = pick?.way;
  if (way != null) {
    final game = polyCardGame(event.displayTitle, event.outcomes);
    if (game == null) return;
    final names =
        gameShortSideNames(game.nameA, game.nameB, teams: event.teams);
    final colors = gameSideColors(event.displayTitle, game.nameA, game.nameB);
    final draw = game.drawOutcome;
    if (draw != null) {
      // A three-way: the match's three winner markets as three sides,
      // each bought on its own market's Yes (the market page's slip).
      final sides = [game.outcomeA, draw, game.outcomeB];
      open(
        outcomes: [
          for (final o in sides)
            PolymarketOutcome(
              name: o.name,
              price: o.price,
              tokenId: o.tokenId,
              conditionId: o.conditionId,
              gammaMarketId: o.gammaMarketId,
              imageUrl: o.imageUrl,
            ),
        ],
        index: way.clamp(0, 2),
        labels: [names.$1, context.l10n.betDraw, names.$2],
        colors: [colors.$1, kGameSideColors[2], colors.$2],
      );
    } else if (identical(game.outcomeA, game.outcomeB)) {
      // The market named for the match: Yes is the team it names first.
      final market = game.outcomeA;
      final aFirst = !game.aOnNo;
      open(
        outcomes: pair(market),
        index: (way == 0 ? game.aOnNo : game.bOnNo) ? 1 : 0,
        pos: aFirst ? names.$1 : names.$2,
        neg: aFirst ? names.$2 : names.$1,
        colors: aFirst ? [colors.$1, colors.$2] : [colors.$2, colors.$1],
      );
    } else {
      // The teams are the market's own two outcomes.
      final target = way == 0 ? game.outcomeA : game.outcomeB;
      final idx = event.outcomes.indexWhere((o) => identical(o, target));
      open(
        outcomes: event.outcomes,
        index: idx < 0 ? 0 : idx,
        colors: [
          for (final o in event.outcomes)
            identical(o, game.outcomeA)
                ? colors.$1
                : identical(o, game.outcomeB)
                    ? colors.$2
                    : null,
        ],
      );
    }
    return;
  }
  final picked = (pick?.side ?? side ?? '').toLowerCase();
  var idx =
      event.outcomes.indexWhere((o) => o.name.trim().toLowerCase() == picked);
  if (idx < 0) idx = 0;
  open(outcomes: event.outcomes, index: idx);
}

/// A chance's move in whole points as the cards write it, an arrow and
/// its size ("▲ 6", "▼ 4"); null when it is unknown or under one point,
/// so the card stays quiet.
String? polyCardMoveArrow(double? move) {
  if (move == null || !move.isFinite || move.abs() < 0.01) return null;
  final points = (move * 100).round();
  if (points == 0) return null;
  return '${points > 0 ? '▲' : '▼'} ${points.abs()}';
}

/// A move's ink: the market's green up, its red down (a move is the one
/// thing on a card that is good or bad for someone holding it).
Color polyCardMoveColor(double move) =>
    move >= 0 ? AppColors.marketUp : AppColors.marketDown;

/// A move as a row writes it beside its leader's chance, compact ("▲6",
/// "▼4"); null when it is unknown or under one point.
String? polyCardMoveDelta(double? move) =>
    polyCardMoveArrow(move)?.replaceAll(' ', '');

/// A move's small figure, beside a row's chance or under the gauge's.
TextStyle _moveStyle(double move) => TextStyle(
      color: polyCardMoveColor(move),
      fontSize: 11.sp,
      fontWeight: FontWeight.w600,
      height: 1.2,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

/// [text]'s width in [style] as [context] draws it (its face and scale).
double _measureText(BuildContext context, String text, TextStyle style) =>
    (TextPainter(
      text: TextSpan(
          text: text, style: DefaultTextStyle.of(context).style.merge(style)),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout())
        .width;

/// The move column beside a chance: as wide as the widest move a card
/// writes ("▲99"), or [delta] when it is wider, so it is one width on
/// every card and the chances before it end on one edge.
double _moveSlotWidth(BuildContext context, String? delta, double? move) {
  final style = _moveStyle(move ?? 1);
  var w = _measureText(context, '▲99', style);
  if (delta != null) {
    final d = _measureText(context, delta, style);
    if (d > w) w = d;
  }
  return w.ceilToDouble() + 1;
}

/// One Predictions list card, in three shapes that share their frame:
/// names on the left, the number that matters on the right.
///
///   * a game: a row per team in the title's order (crest, name, win
///     chance, and the score once the game is on), with the card's
///     caption footer (when it is played) under it;
///   * a single Yes/No market (October 2026, after Kalshi / Polymarket):
///     the market's image (40, rounded 10; the category glyph on the
///     neutral ground when it has none), the question (two lines at
///     most), the Yes chance as a small half-ring gauge with the number
///     under it on the right, and under them two small Yes / No price
///     pills, right-aligned, that open the slip on that side
///     ([onPickSide]). The day's move ("▲ 4") sits under the gauge's
///     number (founder, 12 November 2026: what's moving, on all three
///     cards);
///   * an event with many outcomes: the question, then its three most
///     likely outcomes as rows on one grid (founder, 12 November 2026:
///     "sizes are strange"): the name (14, the leader semibold, wrapping
///     rather than cut) with the percent and the day's move in fixed
///     columns at its right ("84% ▲6", the leader's move only, an empty
///     slot on the other rows so every percent ends on one edge), and
///     under them the chance bar (6 tall) at the row's whole width, the
///     same length on every row; then "+N more ›". Each bar is filled in
///     its outcome's line colour on the market's chart (founder, 11
///     November 2026: "more colourful, not corporate").
///
/// A game in play leads with a live dot and its clock, and every game draws one split bar of its chances in the teams'
/// colours ([kGameSideColors], the draw grey), the leader's day move
/// beside its chance ("62% ▲9"). A move shows only when it is a point or
/// more: green up, red down; quiet otherwise.
///
/// No closing date, volume or stream tag on a list card (founder, 12
/// November 2026: "unnecessary"); the market page keeps them. A question
/// keeps no meta line under it, only a crypto round's window or a
/// match's other markets when it has them, and a game's footer only what
/// it adds (when it is played, the draw when no pill shows it).
///
/// The pills are quiet (founder, 1 November 2026): the neutral surface
/// as their fill, the side's market colour as their ink; no solid green
/// or red blocks on a list, and no tinted chips anywhere in the app.
///
/// Each card has a tiny chart (founder, 12 November 2026), read card by
/// card from the market chart's own history (polymarket_card_spark_provider):
/// the leader's 7-day line top right in its chart colour, a Yes/No
/// market's 7-day Yes line in the neutral ink over its answers, a game's
/// leader's win chance in its team's colour (since kickoff while it is
/// played). It never holds the card up: nothing is drawn until it lands.
///
/// A Yes/No market and a game have one tap to the slip ([onPickSide],
/// founder, 12 November 2026): a Yes/No market's two answers full width
/// and 36 tall, a game's sides as neutral pills (team · draw · team). A
/// pill only opens the slip prefilled on its side; nothing is placed,
/// funded or approved before Confirm there, and there are no amount
/// chips. An event with many outcomes has no pills (founder, 12 November
/// 2026: a pill per row was too small): its rows are the card's tap,
/// which opens the market.
///
/// Which shape, and every number on it, comes from the event the feed
/// already gave (market_card_shape.dart). The whole card is one tap
/// target that opens the detail sheet; only the pills tap elsewhere.
/// The Top markets strip over the feed (top_markets_strip.dart) is
/// built from the same pieces ([PolyCardThumbnail], [polyRowLeader]).
class MarketCard extends ConsumerWidget {
  final String title;
  final String? imageUrl;
  final List<PolymarketOutcome> outcomes;
  /// The lifetime and last-24 h volume. Not written on the card (founder,
  /// 12 November 2026); the market page has them.
  final double volume;
  final double volume24hr;
  final String category;
  /// Scheduled start/kickoff. When in the future the card shows a neutral
  /// "Starts in X" affordance instead of an "Ending soon" pulse, and the
  /// LIVE banner / ending-soon footer are suppressed until the game starts.
  final DateTime? startDate;

  /// A game's kickoff (`PolymarketEvent.kickoff`): the event's start
  /// date is when its market opened, often weeks before the game.
  final DateTime? gameStart;
  final DateTime? endDate;
  /// Resolution STATUS flags (mirrors `PolymarketEvent`). The card labels a
  /// market "Resolved" from these flags + dates ONLY, never from price — a
  /// LIVE longshot (e.g. a 2% Jesus market, a near-0% World Cup team) is an
  /// active, tradable market and must keep showing its real % chance.
  final bool active;
  final bool closed;
  final bool ended;
  final VoidCallback? onTap;

  /// A finger came down on the card (before it is known to be a tap):
  /// the sheet's chart history can start reading.
  final VoidCallback? onTapDown;
  final Map<String, double> livePrices;
  final Map<String, int> priceDirections;
  /// The game in play or just finished (score, clock) from the live
  /// sports feed or Gamma's seed; null before kickoff.
  final PolyLiveGame? liveGame;
  /// Team crests for sports/esports match events — used to give the card a
  /// real badge instead of the generic league soccer-ball image.
  final List<PolymarketTeam> teams;
  /// Event slug — used to lazily backfill team crests via
  /// `polymarketEventTeamsProvider` when [teams] arrived empty (the search
  /// API path drops them).
  final String? slug;
  /// Game id — gates the lazy crest backfill so ONLY actual match cards
  /// fetch teams. Non-match cards (gameId==null) never trigger a request,
  /// avoiding a per-card fetch storm across the whole feed.
  final int? gameId;
  /// Count of EXTRA sibling sub-markets for this match (Both Teams to Score,
  /// O/U, corners, More Markets …) that `collapseByGameId` folds away. When
  /// > 0 the footer names them ("4 markets") as a link wired to
  /// [onMoreMarkets], funnelling the user to the full set without losing the
  /// one-card-per-match feed density.
  final int siblingMarketCount;
  /// Opens the full set of this match's sub-markets. Only wired when
  /// [siblingMarketCount] > 0.
  final VoidCallback? onMoreMarkets;

  /// The lead outcome's 24 h move (a fraction), shown under a Yes/No
  /// market's chance as "+18 today".
  final double? dayMove;

  /// A crypto Up-or-Down round's own window: the footer then reads the
  /// round's time ("10:15 PM – 10:30 PM") instead of its end date.
  final ({DateTime start, DateTime end})? round;

  /// A row of a grouped list card (Home Activity's group, see
  /// market_groups.dart): no card of its own, the row padding of the
  /// group's rows. The list draws the card and the hairlines; only plain
  /// Yes/No markets are grouped.
  final bool inGroup;

  /// A pill was tapped: a Yes / No side of a single market, an outcome's
  /// Yes, or a game's side ([PolyCardPick]). The list opens the slip
  /// prefilled on it ([polyCardOpenSlip]); nothing is placed until Confirm
  /// there. Null leaves the pills as part of the card's own tap.
  final ValueChanged<PolyCardPick>? onPickSide;

  const MarketCard({
    super.key,
    required this.title,
    this.imageUrl,
    required this.outcomes,
    required this.volume,
    this.volume24hr = 0,
    required this.category,
    this.startDate,
    this.gameStart,
    this.endDate,
    this.active = true,
    this.closed = false,
    this.ended = false,
    this.onTap,
    this.onTapDown,
    this.livePrices = const {},
    this.priceDirections = const {},
    this.liveGame,
    this.teams = const [],
    this.slug,
    this.gameId,
    this.siblingMarketCount = 0,
    this.onMoreMarkets,
    this.dayMove,
    this.round,
    this.inGroup = false,
    this.onPickSide,
  });

  /// What the card's live figures belong to: a list that hands this card
  /// to another market starts them afresh instead of rolling across.
  Object get _identity => slug ?? title;

  /// True once the scheduled start has passed. A null [startDate] is treated
  /// as already started so non-dated markets behave exactly as before.
  bool get _hasStarted =>
      startDate == null || !startDate!.isAfter(DateTime.now());

  /// Relative "in X" label for an upcoming start time, e.g. "2h", "35m".
  String _formatStartsIn(AppLocalizations l10n, DateTime start) {
    final diff = start.difference(DateTime.now());
    if (diff.isNegative) return l10n.marketCardSoon;
    if (diff.inDays >= 1) return l10n.coinMapAgeShortDays(diff.inDays);
    if (diff.inHours >= 1) return l10n.coinMapAgeShortHours(diff.inHours);
    if (diff.inMinutes >= 1) return l10n.durationShortMinutes(diff.inMinutes);
    return l10n.marketCardSoon;
  }

  /// Returns the highest-priced outcome (live price preferred). For
  /// multi-outcome events this is the candidate Polymarket itself
  /// surfaces as the "leader" — we mirror that on the card so the
  /// thumbnail shows e.g. the leading team / candidate, not a generic
  /// tournament logo.
  PolymarketOutcome? get _leadingOutcome =>
      polyCardTopOutcomes(outcomes, live: livePrices).firstOrNull;

  /// Image used in the card's leading thumbnail. For multi-outcome
  /// events we prefer the leading outcome's image (per-candidate
  /// `groupItemImage`); for sports/esports matches we prefer a real team
  /// crest over the generic league ball; for binary markets or when no
  /// per-candidate image exists we fall back to the event image.
  ///
  /// [resolvedTeams] is the effective team list — the passed-in [teams],
  /// or the list lazily backfilled by slug in [build] when [teams] is empty.
  String? _displayImageUrl(List<PolymarketTeam> resolvedTeams) {
    // Precedence: real team crest > per-candidate outcome image > event image.
    //
    // Sports/esports matches ship a generic league ball as BOTH the event
    // image AND every sub-market's `image`/`icon`, so the leading outcome's
    // imageUrl is itself the ball. Resolve the team crest FIRST whenever team
    // data exists (incl. the lazy `polymarketEventTeamsProvider` backfill) so
    // the card shows an actual badge/flag instead of the ball. The
    // leading-outcome image stays the fallback for non-team multi-outcome
    // events (e.g. "World Cup Winner" candidate portraits).
    if (resolvedTeams.isNotEmpty) {
      final lead = _leadingOutcome;
      if (lead != null) {
        final crest = PolymarketEvent.logoFromTeams(resolvedTeams, lead.name);
        if (crest != null && crest.isNotEmpty) return crest;
      }
      final firstLogo = resolvedTeams.first.logo;
      if (firstLogo != null && firstLogo.isNotEmpty) return firstLogo;
    }
    if (!polyCardIsYesNo(outcomes)) {
      final lead = _leadingOutcome;
      if (lead?.imageUrl != null && lead!.imageUrl!.isNotEmpty) {
        return lead.imageUrl;
      }
    }
    // Tail of the chain (missing-event-icon fix): event image → ANY
    // outcome image → ANY team crest → nothing. An empty-string event
    // image must not win here — it just errors the loader and lands the
    // card on the generic glyph even when real art exists further down.
    if (imageUrl != null && imageUrl!.trim().isNotEmpty) return imageUrl;
    for (final o in outcomes) {
      final img = o.imageUrl;
      if (img != null && img.isNotEmpty) return img;
    }
    for (final t in resolvedTeams) {
      final logo = t.logo;
      if (logo != null && logo.isNotEmpty) return logo;
    }
    return null;
  }

  String _formatEndDate(DateTime date, {bool year = true}) {
    // Date only — the "00:00" / "12:00" tail was almost always
    // meaningless (Polymarket end-of-day markers) and added noise.
    return DateFormat(year ? 'MMM d, yyyy' : 'MMM d').format(date);
  }

  double _effectivePrice(PolymarketOutcome outcome) {
    if (outcome.tokenId != null && livePrices.containsKey(outcome.tokenId)) {
      return livePrices[outcome.tokenId]!;
    }
    return outcome.price;
  }

  /// A title is written whole: the card grows with it. The venue's
  /// longest real questions (about 130 characters) take five lines on a
  /// 375 pt phone beside the number; this cap only guards against
  /// pathological data.
  static const int _kTitleLines = 8;

  /// A single market's or an event's question on a list row: two lines,
  /// then cut (the market page writes it whole).
  static const int _kListTitleLines = 2;

  /// The title, in the size and weight the app's list rows use for
  /// theirs (the team names of a game card are the same size), so a long
  /// question takes fewer lines.
  static TextStyle _title(AppColorsExtension c) => TextStyle(
        color: c.textPrimary,
        fontSize: 16.sp,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        height: 1.25,
      );

  /// The card's big right-hand number: a chance, or a score.
  static TextStyle _figure(Color color) => TextStyle(
        color: color,
        fontSize: 20.sp,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        height: 1.1,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// The footer's caption text, also the day's move under a chance.
  static TextStyle _caption(AppColorsExtension c) => TextStyle(
        color: c.textTertiary,
        fontSize: 13.sp,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.1,
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;

    // Resolve the team crests for the thumbnail. Prefer the teams passed in;
    // if they arrived empty (search API drops them) lazily backfill by slug —
    // gated to actual match cards so the feed doesn't fire a per-card fetch
    // storm for outright / non-sports cards. gameId is the strong signal,
    // but the SEARCH payload drops gameId along with teams (user report:
    // searching "Portugal" showed the generic ball) — a "vs" in the title
    // is the cheap fallback signal that this is a match.
    List<PolymarketTeam> resolvedTeams = teams;
    final looksLikeMatch = gameId != null ||
        RegExp(r'\svs\.?\s', caseSensitive: false).hasMatch(title);
    if (resolvedTeams.isEmpty &&
        looksLikeMatch &&
        slug != null &&
        slug!.isNotEmpty) {
      resolvedTeams =
          ref.watch(polymarketEventTeamsProvider(slug!)).valueOrNull ??
              const [];
    }

    final game = polyCardGame(title, outcomes, live: livePrices);
    final shape = polyCardShape(game, outcomes);
    // In a group the list draws the card; the row keeps its ink.
    final radius = inGroup ? null : BorderRadius.circular(AppRadius.lg);

    return Container(
      decoration: inGroup ? null : AppDecorations.card(context),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          onTapDown: onTapDown == null ? null : (_) => onTapDown!(),
          borderRadius: radius,
          child: Padding(
            padding: inGroup
                ? EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h)
                : EdgeInsets.all(16.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (shape == PolyCardShape.game && _gameLive) ...[
                  _buildLiveHeader(context, c),
                  SizedBox(height: 12.h),
                ],
                switch (shape) {
                  PolyCardShape.game =>
                    _buildGame(context, c, game!, resolvedTeams),
                  PolyCardShape.yesNo => _buildYesNo(
                      context, ref, c, _displayImageUrl(resolvedTeams)),
                  PolyCardShape.outcomes => _buildOutcomes(
                      context, ref, c, _displayImageUrl(resolvedTeams)),
                },
                // A game keeps the caption footer; the other shapes carry
                // their meta line under the title.
                if (shape == PolyCardShape.game) ...[
                  SizedBox(height: 12.h),
                  _GameSplitBar(
                    a: game!.chanceA,
                    draw: game.draw,
                    b: game.chanceB,
                    colors: gameSideColors(title, game.nameA, game.nameB),
                  ),
                  if (_open && !(liveGame?.finished ?? false)) ...[
                    SizedBox(height: 12.h),
                    _buildGamePills(context, c, game, resolvedTeams),
                  ],
                  if (_buildFooter(context, ref, c, game)
                      case final footer?) ...[
                    SizedBox(height: 10.h),
                    footer,
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// A pill's tap: [pick] to the list ([onPickSide]), or null when the
  /// list gave none (the pill is then part of the card's own tap).
  VoidCallback? _pick(PolyCardPick pick) =>
      onPickSide == null ? null : () => onPickSide!(pick);

  /// Whether the market still takes bets: its pills show.
  bool get _open => !closed && !ended;

  /// A game being played now: it leads with its live dot and clock.
  bool get _gameLive => liveGame != null && !liveGame!.finished;

  /// A game in play's first line: the live dot and "Live · 67'" (no
  /// volume on a list card; the market page has it).
  Widget _buildLiveHeader(BuildContext context, AppColorsExtension c) {
    final l10n = context.l10n;
    final clock = liveGame!.clockOrStatus(context) ?? '';
    final label = clock.isEmpty || clock == l10n.liveBadge
        ? l10n.liveBadge
        : '${l10n.liveBadge} · $clock';
    final style = _caption(c).copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Row(
      children: [
        Container(
          width: 7.r,
          height: 7.r,
          decoration: const BoxDecoration(
            color: AppColors.marketDown,
            shape: BoxShape.circle,
          ),
        ),
        SizedBox(width: 6.w),
        Expanded(
          child: Text(
            label,
            style: style.copyWith(
                color: c.textPrimary, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  /// A game's sides as neutral price pills, team · draw · team (two on a
  /// game with no draw): each opens the slip on that side. Neutral ink: a
  /// team is not up or down.
  Widget _buildGamePills(BuildContext context, AppColorsExtension c,
      PolyCardGame game, List<PolymarketTeam> teams) {
    final names = gameShortSideNames(game.nameA, game.nameB, teams: teams);
    Widget pill(String label, double price, int way) => Expanded(
          child: PolySidePill(
            text: '$label ${polymarketCentsLabel(price.clamp(0.0, 1.0))}',
            color: c.textPrimary,
            onTap: _pick(PolyCardPick.game(way)),
          ),
        );
    // One height for the row: a side whose label wraps sets it.
    return IntrinsicHeight(
        child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        pill(names.$1, game.chanceA, 0),
        if (game.draw != null) ...[
          SizedBox(width: 6.w),
          pill(context.l10n.betDraw, game.draw!, 1),
        ],
        SizedBox(width: 6.w),
        pill(names.$2, game.chanceB, 2),
      ],
    ));
  }

  /// The score for [game]'s two rows, once the game is on or over.
  PolyCardScore? _scoreOf() {
    final live = liveGame;
    if (live == null) return null;
    return polyCardScore(live.score,
        period: live.period, firstIsHome: live.firstIsHome);
  }

  /// A game: one row per team in the title's order. The side ahead (on
  /// the score, else on the odds) reads in the primary colour.
  Widget _buildGame(BuildContext context, AppColorsExtension c,
      PolyCardGame game, List<PolymarketTeam> resolvedTeams) {
    final score = _scoreOf();
    final leader = polyCardLeader(
        score: score, chanceA: game.chanceA, chanceB: game.chanceB);
    // The leader's day move beside its chance ("62% ▲9"), in the move
    // column every card keeps (empty without one), so the chances end on
    // one edge on both rows and from one game card to the next.
    final move = leader == 0
        ? null
        : leader > 0
            ? game.dayMoveA
            : game.dayMoveB;
    final delta = polyCardMoveDelta(move);
    final deltaWidth = _moveSlotWidth(context, delta, move);
    // Both scores sit in one column as wide as the longer of the two.
    final digits = score == null
        ? 0
        : ('${score.a}'.length > '${score.b}'.length
            ? '${score.a}'.length
            : '${score.b}'.length);
    final scoreWidth = (digits * 12 + 8).w;

    Widget row(String name, double chance, int? points,
        PolymarketOutcome outcome, bool leads) {
      final crest = PolymarketEvent.logoFromTeams(resolvedTeams, name) ??
          // A single moneyline's image is the league's, not the team's.
          (identical(game.outcomeA, game.outcomeB) ? null : outcome.imageUrl);
      final tone = leads ? c.textPrimary : c.textSecondary;
      return Row(
        children: [
          _MarketThumbnail(
            title: name,
            imageUrl: crest,
            category: category,
            size: 28.w,
            radius: 8.r,
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: _TeamName(
              name: name,
              short: _teamAbbreviation(resolvedTeams, name),
              style: TextStyle(
                color: tone,
                fontSize: 16.sp,
                fontWeight: leads ? FontWeight.w600 : FontWeight.w500,
                letterSpacing: -0.2,
              ),
            ),
          ),
          SizedBox(width: 12.w),
          // Before kickoff the chance is the row's number; once there is
          // a score it steps back beside it. A new chance rolls the
          // digits that changed.
          RollingFigure(
            identity: _identity,
            text: polyCardChance(chance),
            style: points == null
                ? _figure(tone)
                : TextStyle(
                    color: tone,
                    fontSize: 14.sp,
                    fontWeight: leads ? FontWeight.w600 : FontWeight.w500,
                    letterSpacing: -0.1,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
          ),
          SizedBox(width: 4.w),
          SizedBox(
            width: deltaWidth,
            child: delta != null && leads && leader != 0
                ? Text(delta,
                    maxLines: 1, softWrap: false, style: _moveStyle(move!))
                : null,
          ),
          if (points != null)
            SizedBox(
              width: scoreWidth + 14.w,
              // A goal pulses the number that changed.
              child: Align(
                alignment: Alignment.centerRight,
                child: ScorePulseText(
                  identity: _identity,
                  text: '$points',
                  textAlign: TextAlign.right,
                  style: _figure(c.textPrimary),
                ),
              ),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        row(game.nameA, game.chanceA, score?.a, game.outcomeA, leader >= 0),
        SizedBox(height: 12.h),
        row(game.nameB, game.chanceB, score?.b, game.outcomeB, leader <= 0),
        if (_gameSpark(game, leader) case final spark?) ...[
          SizedBox(height: 10.h),
          spark,
        ],
      ],
    );
  }

  /// The leader's win chance as a line in its team's colour: since
  /// kickoff while the game is played, its last 7 days otherwise. Null
  /// when the side has no token to read.
  Widget? _gameSpark(PolyCardGame game, int leader) {
    final a = leader >= 0;
    final token = a ? game.tokenA : game.tokenB;
    if (token == null || token.isEmpty) return null;
    final colors = gameSideColors(title, game.nameA, game.nameB);
    final live = _gameLive;
    return _CardSpark(
      tokenId: token,
      interval: live ? PolyCardSparkStore.liveInterval : '1w',
      since: live ? gameStart : null,
      live: a ? game.chanceA : game.chanceB,
      color: a ? colors.$1 : colors.$2,
      width: double.infinity,
      height: 24,
    );
  }

  /// The abbreviation the event's teams give [name] ("San Diego Padres"
  /// -> "SD"); null when no team matches or it has none.
  static String? _teamAbbreviation(List<PolymarketTeam> teams, String name) {
    final n = name.trim().toLowerCase();
    for (final t in teams) {
      final full = t.name.trim().toLowerCase();
      final names = [full, t.alias?.trim().toLowerCase() ?? ''];
      if (names.contains(n) || full.endsWith(' $n') || n.endsWith(' $full')) {
        final abbr = t.abbreviation?.trim() ?? '';
        return abbr.isEmpty ? null : abbr.toUpperCase();
      }
    }
    return null;
  }

  /// The image and the title (with what goes under it), shared
  /// by the two shapes that keep a title.
  Widget _buildHeading(
    AppColorsExtension c,
    String? image, {
    Widget? trailing,
    String? title,
    int maxLines = _kTitleLines,
    List<Widget> under = const [],
  }) {
    // Everything hangs from the title's first line: the thumbnail (the
    // list size, so the title has the width) and the number beside it.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MarketThumbnail(
          title: this.title,
          imageUrl: image,
          category: category,
          size: kPolyCardImage.w,
          radius: 10.r,
        ),
        SizedBox(width: kPolyCardImageGap.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title ?? this.title,
                style: _title(c),
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
              ),
              ...under,
            ],
          ),
        ),
        if (trailing != null) ...[
          SizedBox(width: 10.w),
          trailing,
        ],
      ],
    );
  }

  /// A single Yes/No market: the question over its meta line, the Yes
  /// chance as a gauge on the right, and the Yes / No price pills under
  /// them while the market is open.
  Widget _buildYesNo(BuildContext context, WidgetRef ref,
      AppColorsExtension c, String? image) {
    final l10n = context.l10n;
    final yes =
        outcomes.firstWhere((o) => o.name.trim().toLowerCase() == 'yes');
    final no =
        outcomes.where((o) => o.name.trim().toLowerCase() == 'no').firstOrNull;
    final yesPrice = _effectivePrice(yes).clamp(0.0, 1.0);
    // The No side's own price when the feed has it, else what Yes leaves.
    final noPrice =
        (no == null ? 1 - yesPrice : _effectivePrice(no)).clamp(0.0, 1.0);
    final meta = _buildMeta(l10n, c);
    final open = !closed && !ended;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHeading(
          c,
          image,
          title: title,
          maxLines: _kListTitleLines,
          under: [
            if (meta != null) ...[SizedBox(height: 4.h), meta],
          ],
          trailing: _ChanceGauge(
              identity: _identity, chance: yesPrice, move: dayMove ?? yes.dayMove),
        ),
        // The 7-day Yes line in the neutral ink (a chance is not good or
        // bad), over the answers.
        if (yes.tokenId case final token? when token.isNotEmpty) ...[
          SizedBox(height: 12.h),
          _CardSpark(
            tokenId: token,
            interval: '1w',
            live: yesPrice,
            color: c.textPrimary,
            width: double.infinity,
            height: 24,
          ),
        ],
        if (open) ...[
          SizedBox(height: 12.h),
          // The two answers as the card's base: full width, 36 tall.
          IntrinsicHeight(
              child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: PolySidePill(
                        text: '${l10n.yes} ${polymarketCentsLabel(yesPrice)}',
                  color: AppColors.marketUp,
                  onTap: _pick(const PolyCardPick.side('yes')),
                ),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: PolySidePill(
                        text: '${l10n.betNo} ${polymarketCentsLabel(noPrice)}',
                  color: AppColors.marketDown,
                  onTap: _pick(const PolyCardPick.side('no')),
                ),
              ),
            ],
          )),
        ],
      ],
    );
  }

  /// The quiet line under a question, kept only for what the card cannot
  /// do without (founder, 12 November 2026: no closing date, no volume
  /// on a list card; the market page has them): a crypto round's own
  /// window ("10:15 PM – 10:30 PM", what tells one round from the next)
  /// and the match's other markets as a link. Null otherwise. The line
  /// wraps rather than cut.
  Widget? _buildMeta(AppLocalizations l10n, AppColorsExtension c) {
    final round = this.round;
    final when =
        round == null ? null : polyRoundTimes(round.start, round.end, l10n);
    if (when == null && siblingMarketCount == 0) return null;
    final style = _caption(c).copyWith(
      color: c.textSecondary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (when != null) Text(when, style: style),
        if (siblingMarketCount > 0) ...[
          if (when != null) Text(' · ', style: style),
          _marketsLink(c, style),
        ],
      ],
    );
  }

  /// The match's other markets (kept in sibling events), as a link.
  Widget _marketsLink(AppColorsExtension c, TextStyle style) =>
      Builder(builder: (context) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onMoreMarkets,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.l10n.polyCardMarkets(siblingMarketCount + 1),
                  style: style.copyWith(color: c.textSecondary)),
              Icon(Icons.chevron_right_rounded,
                  size: 16.sp, color: c.textTertiary),
            ],
          ),
        );
      });

  /// The outcomes an event's card lists before "+N more".
  static const int _kOutcomeRows = 3;

  /// An event with many outcomes: the question over its meta line, then
  /// its three most likely outcomes as rows on one grid ([_OutcomeLine]):
  /// the name (the first in the primary colour) with the percent and the
  /// day's move in fixed columns at its right, the chance bar under them
  /// at the row's whole width, and "+N more ›" when there are more. A bar
  /// is filled in the colour of its outcome's line on the market's chart
  /// ([polyChartedOutcomes], the rule the chart and the sheet's row dots
  /// read), so an outcome keeps one colour from the card to the sheet; an
  /// outcome the chart draws no line for keeps the neutral fill. No pill
  /// on a row: a row is the card's tap (the market page).
  Widget _buildOutcomes(BuildContext context, WidgetRef ref,
      AppColorsExtension c, String? image) {
    final top =
        polyCardTopOutcomes(outcomes, live: livePrices, count: _kOutcomeRows);
    // One market with two named sides (Up / Down), not two Yes/No markets.
    final twoSided =
        outcomes.length == 2 && !outcomes.any((o) => o.hasYesNo);
    // Fillers with no market behind them are not "more" outcomes.
    final more = polyRealOutcomes(outcomes).length - _kOutcomeRows;
    final meta = _buildMeta(context.l10n, c);
    final charted = polyChartedOutcomes(outcomes, kPolyOutcomeColors);
    Color? lineColor(PolymarketOutcome o) {
      for (final line in charted) {
        if (identical(line.outcome, o) ||
            (o.tokenId != null && line.outcome.tokenId == o.tokenId)) {
          return line.color;
        }
      }
      return null;
    }

    // The rows start where the title does.
    final indent = EdgeInsets.only(left: kPolyCardImage.w + kPolyCardImageGap.w);
    final figureStyle = TextStyle(
      fontSize: 14.sp,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    // One percent column for every card (the widest figure a chance
    // writes, "88.8%", or a wider one this card has), so the percents of
    // all rows end on one edge.
    var chanceWidth = _measureText(context, '88.8%', figureStyle);
    for (final o in top) {
      final w =
          _measureText(context, polyCardChance(_effectivePrice(o)), figureStyle);
      if (w > chanceWidth) chanceWidth = w;
    }
    chanceWidth = chanceWidth.ceilToDouble() + 1;
    // The leader's day move beside its percent ("84% ▲6") in the move
    // column every row keeps (empty on the others).
    final leadMove = top.firstOrNull?.dayMove;
    final delta = polyCardMoveDelta(leadMove);
    final moveWidth = _moveSlotWidth(context, delta, leadMove);

    double rowPrice(PolymarketOutcome o, bool first) => twoSided && !first
        ? 1 - _effectivePrice(top.first)
        : _effectivePrice(o);
    Widget row(PolymarketOutcome o, bool first) {
      final name = TextStyle(
        color: first ? c.textPrimary : c.textSecondary,
        fontSize: 14.sp,
        fontWeight: first ? FontWeight.w600 : FontWeight.w500,
        letterSpacing: -0.1,
        height: 1.25,
      );
      // The two sides of one market add up to 100.
      final price = rowPrice(o, first);
      return _OutcomeLine(
        name: o.name,
        fraction: price.clamp(0.0, 1.0),
        color: lineColor(o),
        chance: twoSided && !first
            ? polyCardOtherSideChance(_effectivePrice(top.first))
            : polyCardChance(_effectivePrice(o)),
        nameStyle: name,
        chanceStyle: figureStyle.copyWith(color: c.textPrimary, height: 1.25),
        chanceWidth: chanceWidth,
        delta: first ? delta : null,
        deltaStyle: delta == null ? null : _moveStyle(leadMove!),
        moveWidth: moveWidth,
      );
    }

    final moreStyle = TextStyle(
      color: c.textSecondary,
      fontSize: 13.sp,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.1,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(builder: (context, constraints) {
          // The leader's 7-day line top right, in its chart colour (where
          // the Yes/No card keeps its gauge). It never squeezes the title:
          // when the title would take more lines beside it than across
          // the card, the line goes under the title instead.
          final leader = top.firstOrNull;
          final token = leader?.tokenId;
          final spark = token == null || token.isEmpty
              ? null
              : _CardSpark(
                  tokenId: token,
                  interval: '1w',
                  live: _effectivePrice(leader!).clamp(0.0, 1.0),
                  color: lineColor(leader) ?? c.textPrimary,
                  width: 64,
                  height: 24,
                );
          final full =
              constraints.maxWidth - kPolyCardImage.w - kPolyCardImageGap.w;
          final narrow = full - 64.w - 10.w;
          final beside = spark != null &&
              narrow > 0 &&
              _lineCount(context, title, _title(c), narrow) <=
                  _lineCount(context, title, _title(c), full);
          return _buildHeading(
            c,
            image,
            title: title,
            maxLines: _kListTitleLines,
            trailing: beside ? spark : null,
            under: [
              if (meta != null) ...[SizedBox(height: 4.h), meta],
              if (spark != null && !beside) ...[SizedBox(height: 6.h), spark],
            ],
          );
        }),
        for (var i = 0; i < top.length; i++) ...[
          SizedBox(height: i == 0 ? 12.h : 10.h),
          Padding(padding: indent, child: row(top[i], i == 0)),
        ],
        if (more > 0) ...[
          SizedBox(height: 10.h),
          Padding(
            padding: indent,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(context.l10n.polyCardMoreOutcomes(more), style: moreStyle),
                Icon(Icons.chevron_right_rounded,
                    size: 14.sp, color: c.textSecondary),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// The lines [text] takes in [style] at [width], as [context] draws it.
  static int _lineCount(
      BuildContext context, String text, TextStyle style, double width) {
    final painter = TextPainter(
      text: TextSpan(
          text: text, style: DefaultTextStyle.of(context).style.merge(style)),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: width);
    return painter.computeLineMetrics().length;
  }

  /// When a market that is not a game starts or ends.
  String? _dateCaption(AppLocalizations l10n, {bool year = true}) {
    final round = this.round;
    if (round != null) return polyRoundTimes(round.start, round.end, l10n);
    // Not open yet: a neutral "Starts in X", never a closing date.
    if (!_hasStarted) {
      final soon = startDate!.difference(DateTime.now()).inHours < 24;
      return soon
          ? l10n.marketCardStartsIn(_formatStartsIn(l10n, startDate!))
          : l10n.marketCardStartsOn(_formatEndDate(startDate!, year: year));
    }
    return endDate == null ? null : _formatEndDate(endDate!, year: year);
  }

  /// Where a game is: its clock while it is played, "Final" once it is
  /// over, its kickoff before.
  String? _gameCaption(BuildContext context, {bool year = true}) {
    final l10n = context.l10n;
    final live = liveGame;
    if (live != null) {
      return live.finished ? l10n.polyMarkerFinal : live.clockOrStatus(context);
    }
    if (ended) return l10n.polyMarkerFinal;
    final kickoff = gameStart ?? (_hasStarted ? null : startDate);
    if (kickoff != null) {
      // The header's own wording ("Today 20:30", "Starts in 23 min").
      return polyKickoffText(l10n, kickoff, now: DateTime.now());
    }
    return _dateCaption(l10n, year: year);
  }

  /// A game's one caption line, only what its rows, bar and pills do not
  /// already say (founder, 12 November 2026: no volume on a list card,
  /// the market page has it): when it is played ("Today 20:30", "Final";
  /// a game in play has its clock in the live line), the games of the
  /// set in play (tennis), the draw's chance when no pills show it, and
  /// the match's other markets as a link. Null when there is nothing to
  /// say. Never cut: the date gives up its year when the line cannot fit,
  /// and a line that still cannot wraps.
  Widget? _buildFooter(BuildContext context, WidgetRef ref,
      AppColorsExtension c, PolyCardGame game) {
    final l10n = context.l10n;
    // A game starting within the day: refresh by the minute, so its
    // caption moves into (and through) the "Starts in" countdown.
    final soon = gameStart?.difference(DateTime.now());
    if (liveGame == null &&
        soon != null &&
        !soon.isNegative &&
        soon.inHours < 24) {
      ref.watch(polyMinuteTickProvider);
    }
    final live = _gameLive;
    final pills = _open && !(liveGame?.finished ?? false);
    String leftText({required bool year}) => <String?>[
          // In play the live line has the clock.
          if (!live) _gameCaption(context, year: year),
          // Tennis: the games of the set in play.
          if (live) _scoreOf()?.setGames,
          if (game.draw != null && !pills)
            '${l10n.betDraw} ${polyCardChance(game.draw!)}',
        ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    final style = _caption(c).copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final marketsText = siblingMarketCount > 0
        ? l10n.polyCardMarkets(siblingMarketCount + 1)
        : '';
    if (leftText(year: true).isEmpty && marketsText.isEmpty) return null;
    return LayoutBuilder(builder: (context, constraints) {
      final scaler = MediaQuery.textScalerOf(context);
      // Measured in the face the footer is drawn in.
      final drawn = DefaultTextStyle.of(context).style.merge(style);
      double measure(String text) => text.isEmpty
          ? 0
          : (TextPainter(
              text: TextSpan(text: text, style: drawn),
              textDirection: TextDirection.ltr,
              textScaler: scaler,
              maxLines: 1,
            )..layout())
              .width;
      final full = leftText(year: true);
      final fixed = marketsText.isEmpty
          ? 0
          : measure(marketsText) + 16.sp + measure(' · ');
      final left = measure(full) + fixed <= constraints.maxWidth
          ? full
          : leftText(year: false);
      return Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (left.isNotEmpty) Text(left, style: style),
          // The match's other markets (kept in sibling events), as a link.
          if (siblingMarketCount > 0) ...[
            if (left.isNotEmpty) Text(' · ', style: style),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onMoreMarkets,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(marketsText,
                      style: style.copyWith(color: c.textSecondary)),
                  Icon(Icons.chevron_right_rounded,
                      size: 16.sp, color: c.textTertiary),
                ],
              ),
            ),
          ],
        ],
      );
    });
  }
}

/// A round's window in the device's time zone and the locale's clock:
/// "10:15 PM – 10:30 PM", led by the day ("Oct 5, …") when the round is
/// not today's.
String polyRoundTimes(DateTime start, DateTime end, AppLocalizations l10n,
    {DateTime? now}) {
  final a = start.toLocal(), b = end.toLocal();
  final today = (now ?? DateTime.now()).toLocal();
  final time = DateFormat.jm(l10n.localeName);
  final times = '${time.format(a)} – ${time.format(b)}';
  final sameDay =
      a.year == today.year && a.month == today.month && a.day == today.day;
  return sameDay
      ? times
      : '${DateFormat.MMMd(l10n.localeName).format(a)}, $times';
}

/// The list card's own pieces, for the cards that follow its language
/// (the portfolio's position card): the thumbnail with its category-glyph
/// fallback, a team's name that gives way to its abbreviation, the big
/// right-hand figure and the caption line.
typedef PolyCardThumbnail = _MarketThumbnail;
typedef PolyCardTeamName = _TeamName;

TextStyle polyCardTitleStyle(AppColorsExtension c) => MarketCard._title(c);

TextStyle polyCardFigureStyle(Color color) => MarketCard._figure(color);

TextStyle polyCardCaptionStyle(AppColorsExtension c) => MarketCard._caption(c);

String? polyCardTeamAbbreviation(List<PolymarketTeam> teams, String name) =>
    MarketCard._teamAbbreviation(teams, name);

/// The lines a card's title may take before it is cut.
const int kPolyCardTitleLines = MarketCard._kTitleLines;

/// The Yes chance of a single market on its list row: a half ring, 40 by
/// 24 with a 4 stroke, its track in the border colour and the chance's
/// share of it in the primary text colour (neutral: a chance is not good
/// or bad), and the figure centred under it.
///
/// The day's move ([move], "▲ 4") sits under the figure in green or red
/// when it is a point or more.
class _ChanceGauge extends StatelessWidget {
  final Object? identity;
  final double chance;
  final double? move;
  const _ChanceGauge(
      {required this.identity, required this.chance, this.move});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 40.w,
          height: 24.h,
          child: CustomPaint(
            painter: _HalfRingPainter(
              fraction: chance,
              track: c.border,
              fill: c.textPrimary,
              stroke: 4,
            ),
          ),
        ),
        SizedBox(height: 2.h),
        RollingFigure(
          identity: identity,
          text: polyCardChance(chance),
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 13.sp,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
            height: 1.1,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (polyCardMoveArrow(move) case final arrow?) ...[
          SizedBox(height: 1.h),
          Text(arrow,
              maxLines: 1, softWrap: false, style: _moveStyle(move!)),
        ],
      ],
    );
  }
}

/// The gauge's ring: the upper half of a circle, open at the bottom, the
/// track whole and the fill from the left end for [fraction] of it.
class _HalfRingPainter extends CustomPainter {
  final double fraction;
  final Color track;
  final Color fill;
  final double stroke;
  const _HalfRingPainter({
    required this.fraction,
    required this.track,
    required this.fill,
    required this.stroke,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final r = (size.width - stroke) / 2;
    final rect = Rect.fromCircle(
        center: Offset(size.width / 2, size.height - stroke / 2), radius: r);
    Paint paint(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, pi, pi, false, paint(track));
    final sweep = pi * fraction.clamp(0.0, 1.0);
    if (sweep > 0) canvas.drawArc(rect, pi, sweep, false, paint(fill));
  }

  @override
  bool shouldRepaint(covariant _HalfRingPainter old) =>
      old.fraction != fraction ||
      old.track != track ||
      old.fill != fill ||
      old.stroke != stroke;
}

/// A price pill on a list card: the side's label and price ("Yes 29¢")
/// in [color] on the neutral surface (founder, 1 November 2026: quiet
/// pills, no solid green / red blocks on a list; no tinted chips anywhere
/// in the app, so the ground is the surface colour, never a tint of the
/// side's). It fills its slot, 36 tall, for a Yes/No market's two
/// answers and a game's sides, its text wrapping to a second line rather
/// than cut. Taps [onTap]; with none it is part of the card.
class PolySidePill extends StatelessWidget {
  final String text;

  /// The pill's ink: the side's market colour ([AppColors.marketUp] /
  /// [marketDown]), or the primary text colour for a side that is not up
  /// or down (a team, the draw).
  final Color color;
  final VoidCallback? onTap;
  const PolySidePill(
      {super.key, required this.text, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    final Widget pill = Container(
      // 36 on the design's phone, never a target under 32.
      constraints: BoxConstraints(minHeight: math.max(36.h, 32)),
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.colors.surfaceLight,
        borderRadius: BorderRadius.circular(11.r),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        maxLines: 3,
        style: TextStyle(
          color: color,
          fontSize: 13.sp,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
          height: 1.15,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
    if (onTap == null) return pill;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: pill,
    );
  }
}

/// One outcome of an event's row, on the grid every row of every card
/// keeps (founder, 12 November 2026: "sizes are strange"):
///
///   Name ……………………………… 84% ▲6
///   ▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬
///
/// The name takes the room the columns leave and wraps rather than being
/// cut; the percent sits in a column [chanceWidth] wide and the day's move
/// ([delta], the leader's only) in one [moveWidth] wide, empty on the
/// other rows, so every percent ends on one edge; both sit on the name's
/// first line. The bar under them is the row's whole width, so every
/// row's bar is the same length whatever its name.
class _OutcomeLine extends StatelessWidget {
  final String name;

  /// The outcome's chance, 0 to 1: the bar's fill.
  final double fraction;

  /// The bar's fill colour ([PolyOutcomeChanceBar.color]).
  final Color? color;
  final String chance;
  final TextStyle nameStyle;
  final TextStyle chanceStyle;
  final double chanceWidth;

  /// The day's move after the percent ("▲6"), in the [moveWidth] column.
  final String? delta;
  final TextStyle? deltaStyle;
  final double moveWidth;
  const _OutcomeLine({
    required this.name,
    required this.fraction,
    this.color,
    required this.chance,
    required this.nameStyle,
    required this.chanceStyle,
    required this.chanceWidth,
    this.delta,
    this.deltaStyle,
    required this.moveWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(child: Text(name, style: nameStyle)),
            SizedBox(width: 12.w),
            SizedBox(
              width: chanceWidth,
              child: Text(chance,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  softWrap: false,
                  style: chanceStyle),
            ),
            SizedBox(width: 4.w),
            SizedBox(
              width: moveWidth,
              // Empty on a row with no move: nothing in it sets the
              // row's height.
              child: delta == null
                  ? null
                  : Text(delta!,
                      maxLines: 1, softWrap: false, style: deltaStyle),
            ),
          ],
        ),
        SizedBox(height: 6.h),
        PolyOutcomeChanceBar(fraction: fraction, color: color),
      ],
    );
  }
}

/// An outcome's chance as a bar: [height] tall (6 on the list card),
/// rounded, the track in the border colour and [fraction] of it filled in
/// [color], the outcome's line colour on the chart, or the primary text
/// colour when it has none (neutral, as the Yes/No gauge: a chance is not
/// good or bad).
class PolyOutcomeChanceBar extends StatelessWidget {
  final double fraction;

  /// The fill; null for the primary text colour.
  final Color? color;
  final double height;
  const PolyOutcomeChanceBar(
      {super.key, required this.fraction, this.color, this.height = 6});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: ColoredBox(
          color: c.border,
          child: FractionallySizedBox(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: fraction.isFinite ? fraction.clamp(0.0, 1.0) : 0.0,
            heightFactor: 1,
            child: ColoredBox(color: color ?? c.textPrimary),
          ),
        ),
      ),
    );
  }
}

/// A card's tiny chart: one token's line ([HlLineSparkline], the
/// Investing cards' own) in [color], no fill and no baseline, ending on
/// [live] (the figure the card shows), from [since] when given. Until the
/// series lands it takes its place and draws nothing.
class _CardSpark extends ConsumerWidget {
  final String tokenId;
  final String interval;
  final DateTime? since;
  final double? live;
  final Color color;

  /// In design units (the sparkline scales them); [double.infinity] for
  /// the card's whole width.
  final double width;
  final double height;
  const _CardSpark({
    required this.tokenId,
    required this.interval,
    this.since,
    this.live,
    required this.color,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final points = ref.watch(
        polyCardSparkProvider((tokenId: tokenId, interval: interval)));
    final values = polyCardSparkValues(points, since: since, live: live);
    if (values.length < 2) {
      return SizedBox(width: width.w, height: height.h);
    }
    return HlLineSparkline(
      closes: values,
      width: width,
      height: height,
      upColor: color,
      downColor: color,
      strokeWidth: 1.6,
      baseline: false,
    );
  }
}

/// A game's chances as one bar split in three (two for a game with no
/// draw): the first team's share in its colour, the draw's in grey, the
/// second team's in its colour, a hairline gap between them. 6 tall.
class _GameSplitBar extends StatelessWidget {
  final double a;
  final double? draw;
  final double b;
  final (Color, Color) colors;
  const _GameSplitBar(
      {required this.a, this.draw, required this.b, required this.colors});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    double share(double? v) =>
        v == null || !v.isFinite ? 0 : v.clamp(0.0, 1.0).toDouble();
    final parts = [
      (share(a), colors.$1),
      if (draw != null) (share(draw), c.textTertiary.withValues(alpha: 0.45)),
      (share(b), colors.$2),
    ].where((p) => p.$1 > 0).toList();
    if (parts.isEmpty) return SizedBox(height: 6.h);
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        height: 6,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < parts.length; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              Expanded(
                flex: (parts[i].$1 * 1000).round().clamp(1, 1000),
                child: ColoredBox(color: parts[i].$2),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A team's name, never cut while it can be written: whole on one line,
/// on two when one cannot hold it, its abbreviation ("SD") only when two
/// cannot either, and only then cut.
class _TeamName extends StatelessWidget {
  final String name;
  final String? short;
  final TextStyle style;

  const _TeamName({required this.name, this.short, required this.style});

  @override
  Widget build(BuildContext context) {
    final short = this.short;
    if (short == null || short.isEmpty) {
      return Text(name,
          maxLines: 2, overflow: TextOverflow.ellipsis, style: style);
    }
    return LayoutBuilder(builder: (context, constraints) {
      // Measured in the font the Text below is drawn in.
      final drawn = DefaultTextStyle.of(context).style.merge(style);
      final fits = !(TextPainter(
        text: TextSpan(text: name, style: drawn),
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 2,
      )..layout(maxWidth: constraints.maxWidth))
          .didExceedMaxLines;
      return fits
          ? Text(name,
              maxLines: 2, overflow: TextOverflow.ellipsis, style: style)
          : Text(short,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    });
  }
}

class _MarketThumbnail extends StatelessWidget {
  final String title;
  final String? imageUrl;
  /// Market category slug — used to pick a real category glyph as the
  /// fallback when there is no event image and no team crest, so a card
  /// never renders with a blank/grey square.
  final String category;

  /// The card's thumbnail by default; a game's team rows pass their
  /// smaller crest size.
  final double? size;
  final double? radius;

  const _MarketThumbnail({
    required this.title,
    this.imageUrl,
    required this.category,
    this.size,
    this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final size = this.size ?? 56.w;
    final radius = this.radius ?? 14.r;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.surfaceLight,
        borderRadius: BorderRadius.circular(radius),
      ),
      // SVG-aware: national-team flags / some crests are `.svg`, which the
      // old CachedNetworkImage couldn't decode (→ generic glyph fallback).
      // Empty-string guard: a "" URL just errors the loader — treat it as
      // missing so the fallback glyph renders immediately.
      child: (imageUrl != null && imageUrl!.isNotEmpty)
          ? PolyCrestImage(
              url: imageUrl!,
              size: size,
              radius: radius,
              fallback: _InitialCircle(category: category, size: size),
            )
          : _InitialCircle(category: category, size: size),
    );
  }
}

/// The thumbnail with no image: the category's glyph (crypto, sports,
/// politics, the compass for an unknown one) in the quiet text colour on
/// the thumbnail's own neutral ground, so a card never shows a blank
/// square.
class _InitialCircle extends StatelessWidget {
  final String category;
  final double size;

  const _InitialCircle({required this.category, required this.size});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        polyCategoryGlyph(category),
        color: context.colors.textSecondary,
        size: size * 0.46,
      ),
    );
  }
}
