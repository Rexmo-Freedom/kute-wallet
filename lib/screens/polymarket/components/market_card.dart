import 'package:kute/helpers/formatters/polymarket_amount_formatter.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_browse_provider.dart'
    show polymarketEventTeamsProvider;
import 'package:kute/screens/polymarket/components/bet_slip_sheet.dart'
    show BetSlipSheet;
import 'package:kute/screens/polymarket/components/poly_category_icons.dart';
import 'package:kute/screens/polymarket/components/poly_crest_image.dart';
import 'package:kute/screens/polymarket/components/live_game.dart';
import 'package:kute/screens/polymarket/components/game_time.dart';
import 'package:kute/screens/shared/kute_motion.dart';
import 'package:kute/services/polymarket/market_buy_quote.dart'
    show polymarketCentsLabel;
import 'package:kute/services/polymarket/market_card_shape.dart';
import 'package:kute/theme/app_theme.dart';
import 'dart:math' show pi;
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:bootstrap_icons/bootstrap_icons.dart';
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

/// Between two Predictions rows of a group: a hairline at half the border
/// colour, from where the title starts (Kalshi / Polymarket rows).
Widget polyGroupRowDivider(BuildContext context, double indent) => Divider(
      color: context.colors.border.withValues(alpha: 0.5),
      height: 1,
      thickness: 0.5,
      indent: indent,
    );

/// Opens the bet slip on [side] ('yes' / 'no') of [event], the way the
/// market page's own Yes / No pair does ([MarketCard.onPickSide] from a
/// row's pill): the side's outcome preselected, nothing new in between.
/// [source] is the list the row sits in, for the slip's existing open
/// event.
void polyCardOpenSlip(
  BuildContext context, {
  required PolymarketEvent event,
  required String side,
  required String source,
  VoidCallback? onDeposit,
  String? ledgerWalletId,
}) {
  HapticFeedback.mediumImpact();
  var idx = event.outcomes
      .indexWhere((o) => o.name.trim().toLowerCase() == side.toLowerCase());
  if (idx < 0) idx = 0;
  BetSlipSheet.show(
    context,
    event: event,
    negRisk: event.negRisk,
    marketQuestion: event.title,
    marketSlug: event.slug,
    marketImage: event.imageUrl,
    outcomes: event.outcomes,
    initialOutcomeIndex: idx,
    onDeposit: onDeposit,
    ledgerWalletId: ledgerWalletId,
    marketCategory: event.category,
    marketEndAt: event.endDate,
    source: source,
  );
}

/// One Predictions list card, in three shapes that share their frame:
/// names on the left, the number that matters on the right.
///
///   * a game: a row per team in the title's order (crest, name, win
///     chance, and the score once the game is on), with the card's
///     caption footer (clock, draw chance, volume) under it;
///   * a single Yes/No market (October 2026, after Kalshi / Polymarket):
///     the question (two lines at most, its year dropped when the meta
///     line already says it), one meta line under it in the secondary
///     colour ("$27.8K · closes Jan 2027"), the Yes chance as a small
///     half-ring gauge with the number under it on the right, and under
///     them two small Yes / No price pills, right-aligned, that open the
///     slip on that side ([onPickSide]). The day's move is left to the
///     market page;
///   * an event with many outcomes: the question and the same meta line,
///     then its two most likely outcomes as "Name …… 41%" rows and
///     "+N more ›"; no pills (the card opens the event).
///
/// Which shape, and every number on it, comes from the event the feed
/// already gave (market_card_shape.dart). The whole card is one tap
/// target that opens the detail sheet; only the pills tap elsewhere.
class MarketCard extends ConsumerWidget {
  final String title;
  final String? imageUrl;
  final List<PolymarketOutcome> outcomes;
  final double volume;
  /// Last 24h volume — surfaced as a "live activity" signal next to the
  /// lifetime volume in the footer. Polymarket's own browse cards show
  /// `$X Vol · $Y 24h Vol`; mirroring that here lets static-feeling
  /// cards read as active markets.
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
  /// True when the event is broadcasting a watchable stream (from
  /// `PolymarketEvent.hasLivestream`). Surfaces a small "Live stream"
  /// badge on the card so users can tell a market is being streamed.
  final bool hasLivestream;
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

  /// A Yes / No pill of a single market was tapped: 'yes' or 'no'. The
  /// list opens the slip on that side ([polyCardOpenSlip]). Null leaves
  /// the pills as part of the card's own tap.
  final ValueChanged<String>? onPickSide;

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
    this.hasLivestream = false,
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

  String _formatVolume(WidgetRef ref, double v) {
    if (v >= 1000000) {
      return '${formatPolyAmount(ref, v / 1000000, decimalDigits: 1)}M';
    } else if (v >= 1000) {
      return '${formatPolyAmount(ref, v / 1000, decimalDigits: 1)}K';
    }
    return formatPolyAmount(ref, v, decimalDigits: 0);
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

  /// The question as a list row titles it. One that ends with its full
  /// date ("… by December 31, 2026?") loses the year when the meta line
  /// already says the market closes in that year: the year reads once.
  /// A plain check on the title's tail; any doubt keeps the title whole.
  String _listTitle() {
    final end = endDate;
    if (end == null || round != null || !_hasStarted) return title;
    final m = RegExp(r',\s*(\d{4})\s*(\?)?\s*$').firstMatch(title);
    if (m == null || int.tryParse(m.group(1)!) != end.year) return title;
    return '${title.substring(0, m.start)}${m.group(2) ?? ''}';
  }

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
                switch (shape) {
                  PolyCardShape.game => _buildGame(c, game!, resolvedTeams),
                  PolyCardShape.yesNo => _buildYesNo(
                      context, ref, c, _displayImageUrl(resolvedTeams)),
                  PolyCardShape.outcomes => _buildOutcomes(
                      context, ref, c, _displayImageUrl(resolvedTeams)),
                },
                // A game keeps the caption footer; the other shapes carry
                // their meta line under the title.
                if (shape == PolyCardShape.game) ...[
                  SizedBox(height: 14.h),
                  _buildFooter(context, ref, c, shape, game),
                ],
              ],
            ),
          ),
        ),
      ),
    );
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
  Widget _buildGame(AppColorsExtension c, PolyCardGame game,
      List<PolymarketTeam> resolvedTeams) {
    final score = _scoreOf();
    final leader = polyCardLeader(
        score: score, chanceA: game.chanceA, chanceB: game.chanceB);
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
        if (hasLivestream) ...[
          SizedBox(height: 10.h),
          _LiveStreamBadge(category: category),
        ],
      ],
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

  /// The image and the title (with the stream marker under it), shared
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
              if (hasLivestream) ...[
                SizedBox(height: 6.h),
                _LiveStreamBadge(category: category),
              ],
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
    final meta = _buildMeta(context, ref, c);
    final open = !closed && !ended;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHeading(
          c,
          image,
          title: _listTitle(),
          maxLines: _kListTitleLines,
          under: [
            if (meta != null) ...[SizedBox(height: 4.h), meta],
          ],
          trailing: _ChanceGauge(identity: _identity, chance: yesPrice),
        ),
        if (open) ...[
          SizedBox(height: 10.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _SidePill(
                text: '${l10n.yes} ${polymarketCentsLabel(yesPrice)}',
                color: AppColors.marketUp,
                onTap: onPickSide == null ? null : () => onPickSide!('yes'),
              ),
              SizedBox(width: 6.w),
              _SidePill(
                text: '${l10n.betNo} ${polymarketCentsLabel(noPrice)}',
                color: AppColors.marketDown,
                onTap: onPickSide == null ? null : () => onPickSide!('no'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// The one quiet line under a question: the volume, compact, and when
  /// the market closes ("$27.8K · closes Jan 2027"; a round's window or
  /// "Starts in 2h" in its place), with the match's other markets as a
  /// link when it has them. Null when there is nothing to say.
  Widget? _buildMeta(
      BuildContext context, WidgetRef ref, AppColorsExtension c) {
    final l10n = context.l10n;
    final volumeText = volume > 0 ? _formatVolume(ref, volume) : null;
    final String? when;
    final round = this.round;
    if (round != null) {
      when = polyRoundTimes(round.start, round.end, l10n);
    } else if (!_hasStarted) {
      when = _dateCaption(l10n);
    } else {
      final end = endDate;
      when = end == null
          ? null
          : l10n.marketCloses(DateFormat('MMM yyyy').format(end));
    }
    final String? text;
    if (volumeText != null && when != null) {
      text = round == null && _hasStarted
          ? l10n.marketMetaLine(
              volumeText, DateFormat('MMM yyyy').format(endDate!))
          : '$volumeText · $when';
    } else {
      text = volumeText ?? when;
    }
    if (text == null && siblingMarketCount == 0) return null;
    final style = _caption(c).copyWith(
      color: c.textSecondary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Row(
      children: [
        if (text != null)
          Flexible(
            child: Text(text,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
          ),
        if (siblingMarketCount > 0) ...[
          if (text != null) Text(' · ', style: style),
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

  /// An event with many outcomes: the question over its meta line, then
  /// its two most likely outcomes as "Name …… 41%" rows (the first in the
  /// primary colour) and "+N more ›" when there are more.
  Widget _buildOutcomes(BuildContext context, WidgetRef ref,
      AppColorsExtension c, String? image) {
    final top = polyCardTopOutcomes(outcomes, live: livePrices);
    // One market with two named sides (Up / Down), not two Yes/No markets.
    final twoSided =
        outcomes.length == 2 && !outcomes.any((o) => o.hasYesNo);
    // Fillers with no market behind them are not "more" outcomes.
    final more = polyRealOutcomes(outcomes).length - 2;
    final meta = _buildMeta(context, ref, c);
    // The rows start where the title does.
    final indent = EdgeInsets.only(left: kPolyCardImage.w + kPolyCardImageGap.w);
    Widget row(PolymarketOutcome o, bool first) {
      final name = TextStyle(
        color: first ? c.textPrimary : c.textSecondary,
        fontSize: 12.sp,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.1,
      );
      final chance = name.copyWith(
        color: c.textPrimary,
        fontWeight: FontWeight.w600,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
      return _OutcomeLine(
        name: o.name,
        // The two sides of one market add up to 100.
        chance: twoSided && !first
            ? polyCardOtherSideChance(_effectivePrice(top.first))
            : polyCardChance(_effectivePrice(o)),
        nameStyle: name,
        chanceStyle: chance,
      );
    }

    final moreStyle = TextStyle(
      color: c.textSecondary,
      fontSize: 12.sp,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.1,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHeading(
          c,
          image,
          title: _listTitle(),
          maxLines: _kListTitleLines,
          under: [
            if (meta != null) ...[SizedBox(height: 4.h), meta],
          ],
        ),
        for (var i = 0; i < top.length; i++) ...[
          SizedBox(height: i == 0 ? 10.h : 6.h),
          Padding(padding: indent, child: row(top[i], i == 0)),
        ],
        if (more > 0) ...[
          SizedBox(height: 6.h),
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

  /// One caption line: on the left what the shape has to add (a game's
  /// clock and draw chance, a market's end date, "+3 more"), on the right
  /// the volume.
  Widget _buildFooter(BuildContext context, WidgetRef ref,
      AppColorsExtension c, PolyCardShape shape, PolyCardGame? game) {
    final l10n = context.l10n;
    // A game starting within the day: refresh by the minute, so its
    // caption moves into (and through) the "Starts in" countdown.
    final soon = gameStart?.difference(DateTime.now());
    if (shape == PolyCardShape.game &&
        liveGame == null &&
        soon != null &&
        !soon.isNegative &&
        soon.inHours < 24) {
      ref.watch(polyMinuteTickProvider);
    }
    // Fillers with no market behind them are not "more" outcomes.
    final more = polyRealOutcomes(outcomes).length - 2;
    String leftText({required bool year}) => <String>[
          ...switch (shape) {
            PolyCardShape.game => [
                _gameCaption(context, year: year),
                // Tennis: the games of the set in play.
                if (liveGame != null && !liveGame!.finished)
                  _scoreOf()?.setGames,
                if (game!.draw != null)
                  '${l10n.betDraw} ${polyCardChance(game.draw!)}',
              ],
            PolyCardShape.yesNo => [_dateCaption(l10n, year: year)],
            PolyCardShape.outcomes => [
                more > 0
                    ? l10n.polyCardMoreOutcomes(more)
                    : _dateCaption(l10n, year: year),
              ],
          }
              .whereType<String>()
              .where((s) => s.isNotEmpty),
        ].join(' · ');
    final style = _caption(c).copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final volumeText =
        volume > 0 ? l10n.polyCardVolume(_formatVolume(ref, volume)) : '';
    final marketsText =
        siblingMarketCount > 0 ? l10n.polyCardMarkets(siblingMarketCount + 1) : '';
    // The line is never cut: when its two sides cannot both fit, the date
    // gives up its year.
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
      final fixed = measure(volumeText) +
          (volumeText.isEmpty ? 0 : 12.w) +
          (marketsText.isEmpty
              ? 0
              : measure(marketsText) + 16.sp + measure(' · '));
      final left = measure(full) + fixed <= constraints.maxWidth
          ? full
          : leftText(year: false);
      return Row(
        children: [
          Expanded(
            child: Row(
              children: [
                if (left.isNotEmpty)
                  Flexible(
                    child: Text(left,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: style),
                  ),
                // The match's other markets (kept in sibling events), as
                // a link.
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
            ),
          ),
          if (volumeText.isNotEmpty) ...[
            SizedBox(width: 12.w),
            Text(volumeText, maxLines: 1, style: style),
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
class _ChanceGauge extends StatelessWidget {
  final Object? identity;
  final double chance;
  const _ChanceGauge({required this.identity, required this.chance});

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

/// A Yes / No price pill under a single market's row: small (72 by 28),
/// the side's label and price ("Yes 29¢") in white on the side's solid
/// market colour, the market page's big Yes / No buttons in miniature (no
/// tint: solid fills or neutral grey only). Taps [onTap]; with none it is
/// part of the row.
class _SidePill extends StatelessWidget {
  final String text;
  final Color color;
  final VoidCallback? onTap;
  const _SidePill({required this.text, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      width: 72.w,
      height: 28.h,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(9.r),
      ),
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.fade,
        style: TextStyle(
          color: Colors.white,
          fontSize: 11.sp,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
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

/// One outcome of an event's row: its name, a dotted leader to the right
/// edge, its chance ("Name …… 41%"). The name takes what it needs up to
/// most of the line, cut only then; the leader takes the rest.
class _OutcomeLine extends StatelessWidget {
  final String name;
  final String chance;
  final TextStyle nameStyle;
  final TextStyle chanceStyle;
  const _OutcomeLine({
    required this.name,
    required this.chance,
    required this.nameStyle,
    required this.chanceStyle,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(builder: (context, constraints) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.7),
            child: Text(name,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: nameStyle),
          ),
          SizedBox(width: 6.w),
          Expanded(
            child: SizedBox(
              height: 12.h,
              child: CustomPaint(painter: _DotLeaderPainter(color: c.border)),
            ),
          ),
          SizedBox(width: 6.w),
          Text(chance, style: chanceStyle),
        ],
      );
    });
  }
}

/// The dotted leader of an [_OutcomeLine]: round dots, 1.5 wide and 4
/// apart, on the line's middle.
class _DotLeaderPainter extends CustomPainter {
  final Color color;
  const _DotLeaderPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const spacing = 4.0;
    final count = (size.width / spacing).floor();
    if (count <= 0) return;
    final start = (size.width - (count - 1) * spacing) / 2;
    final y = size.height * 0.62;
    final points = [
      for (var i = 0; i < count; i++) Offset(start + i * spacing, y),
    ];
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawPoints(PointMode.points, points, paint);
  }

  @override
  bool shouldRepaint(covariant _DotLeaderPainter old) => old.color != color;
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

/// Small streaming marker shown under the title when an event is
/// broadcasting: the broadcast glyph and a label on the card's neutral
/// chip ground, like the live line under it.
///
/// Esports streams get their own variant: a controller glyph and an
/// "Esports live" label, so a gaming match reads apart from a generic
/// livestream.
class _LiveStreamBadge extends StatelessWidget {
  final String category;
  const _LiveStreamBadge({required this.category});

  static const _kEsportsSlugs = {
    'esports',
    'gaming',
    'games',
    'cs2',
    'lol',
    'dota',
    'valorant',
  };

  bool get _isEsports => _kEsportsSlugs.contains(category.toLowerCase().trim());

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent = c.textSecondary;
    final glyph = _isEsports ? BootstrapIcons.controller : BootstrapIcons.broadcast;
    final label = _isEsports
        ? context.l10n.marketCardEsportsLive
        : context.l10n.marketCardLiveStream;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
      decoration: BoxDecoration(
        color: c.surfaceLight,
        borderRadius: BorderRadius.circular(6.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(glyph, size: 13.sp, color: accent),
          SizedBox(width: 5.w),
          Text(
            label,
            style: TextStyle(
              color: accent,
              fontSize: 13.sp,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }
}
