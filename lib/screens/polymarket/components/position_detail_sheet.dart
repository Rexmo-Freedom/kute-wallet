import 'dart:async';

import 'package:kute/screens/shared/fitted_title.dart';
import 'package:kute/screens/shared/kute_blur.dart';
import 'package:kute/screens/shared/kute_motion.dart' show KuteStillWhenCovered;
import 'package:kute/screens/polymarket/components/live_token_scope.dart';
import 'package:kute/screens/polymarket/components/market_chart.dart'
    show formatPolyBoughtCents;
import 'package:kute/screens/polymarket/components/outcome_leading.dart'
    show kPolyOutcomeColors, polyChartedOutcomes;
import 'package:kute/screens/polymarket/components/position_chance_bar.dart';
import 'package:kute/screens/polymarket/components/position_chance_gauge.dart';
import 'package:kute/screens/polymarket/components/game_chart_section.dart';
import 'package:kute/screens/polymarket/components/game_header.dart';
import 'package:kute/screens/polymarket/components/live_game.dart'
    show PolyLiveGame;
import 'package:kute/screens/polymarket/components/game_time.dart'
    show polyMinuteTickProvider;
import 'package:kute/providers/polymarket_game_lines_provider.dart';
import 'package:kute/providers/polymarket_sports_provider.dart'
    show sportsLiveProvider;
import 'package:kute/screens/shared/position_rows_card.dart';

import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/kute_skeleton.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/helpers/formatters/polymarket_amount_formatter.dart';
import 'package:kute/models/polymarket_model.dart';

import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_cost_basis_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';

import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/screens/polymarket/components/poly_crest_image.dart';
import 'package:kute/screens/polymarket/components/position_awaiting.dart';
import 'package:kute/screens/polymarket/components/position_claim.dart';
import 'package:kute/screens/polymarket/components/poly_livestream_host.dart';
import 'package:kute/screens/polymarket/components/price_format.dart';
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/screens/polymarket/components/sell_sheet.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/polymarket/components/poly_market_stats.dart'
    show PolyRulesRow;
import 'package:kute/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/venue_analytics.dart';
import 'package:kute/screens/polymarket/components/fast_bet_scope.dart';
import 'package:kute/services/polymarket/fast_bet_window.dart';

const Color _kPolyGreen = AppColors.marketUp;
const Color _kPolyRed = AppColors.marketDown;

// The open-position screen of a Predictions bet. It reads like the market
// sheet of the same market: a game shows its two teams with the score
// between them (PolyGameTeamsHeader); any other market shows the sheet's
// icon-and-title header. Under it, what is the user's: a pill naming the
// held side ("▲ You hold Up", in its colour); the chance dial as the
// screen's hero (where the held outcome's chance is now against the price
// paid, ticked "Bought · 32¢", the chance in its middle:
// position_chance_gauge.dart) while the bet is open, the chance bar
// (position_chance_bar.dart) once it is settled; no price chart here, the
// market sheet keeps it. Then two tiles: the current value with the profit
// or loss, and the payout if the held side wins with what was paid (once
// settled: what it paid out); the end as a pill; and plain rows: "Protect
// it" while open, "Details" (outcome / shares / price paid / invested, on
// the shared bottom sheet, as on the Investing position) and the closing
// conditions; and the Sell (or, on a resolved losing side, Clear) action.
// A won position has no action: it is claimed automatically
// (claim_auto_fire.dart) and reads "Settled".

class PositionDetailSheet extends ConsumerStatefulWidget {
  final PolymarketPosition position;
  final VoidCallback? onDeposit;

  const PositionDetailSheet({
    super.key,
    required this.position,
    this.onDeposit,
  });

  static const routeName = 'polymarket-position-detail-sheet';

  static void show(
    BuildContext context, {
    required PolymarketPosition position,
    VoidCallback? onDeposit,
  }) {
    // One screen per position: a second tap while it is open does nothing.
    final key = '$routeName:${position.tokenId}';
    if (OpenOnce.isOpen(key)) return;
    TrackingService.screenView('prediction_position_detail');
    TrackingService.predictionsPositionDetailViewed();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final navigator = Navigator.of(context, rootNavigator: true);
    OpenOnce.run(key, () => navigator.push(
      PageRouteBuilder(
        settings: const RouteSettings(name: routeName),
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.4),
        fullscreenDialog: true,
        transitionDuration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 300),
        reverseTransitionDuration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 300),
        // Still while the sell slip (or any sheet) covers it, so its tick
        // animations never share the frames of the slip being scrolled.
        pageBuilder: (_, __, ___) => FastBetScope(
          active: polyIsFastBetRound(position.eventSlug),
          child: KuteStillWhenCovered(
            child: PositionDetailSheet(
              position: position,
              onDeposit: onDeposit,
            ),
          ),
        ),
        transitionsBuilder: (_, animation, __, child) {
          return SlideTransition(
            position: animation.drive(
              Tween(begin: const Offset(0, 1), end: Offset.zero)
                  .chain(CurveTween(curve: Curves.easeOutCubic)),
            ),
            child: child,
          );
        },
      ),
    ));
  }

  @override
  ConsumerState<PositionDetailSheet> createState() =>
      _PositionDetailSheetState();
}

class _PositionDetailSheetState extends ConsumerState<PositionDetailSheet>
    with PolyLivestreamHost<PositionDetailSheet> {
  /// The position's event once read by slug: its broadcast, when it has
  /// one, is watched here as on the market sheet ([PolyLivestreamHost]).
  PolymarketEvent? _event;
  @override
  PolymarketEvent? get streamEvent => _event;
  @override
  String get streamEntrySource => 'unknown';
  @override
  String get streamSurface => 'position';

  /// The match of the position's event, worked out once per event (the
  /// detection compiles a handful of regexes).
  PolymarketEvent? _teamsMemoEvent;
  List<PolymarketTeam>? _teamsMemoFetched;
  PolySportsTeams? _teamsMemo;

  /// The live score feed was joined for this position's game.
  bool _joinedScores = false;

  PolySportsTeams? _sportsTeams(
      PolymarketEvent event, List<PolymarketTeam> fetched) {
    if (!identical(_teamsMemoEvent, event) ||
        !identical(_teamsMemoFetched, fetched)) {
      _teamsMemoEvent = event;
      _teamsMemoFetched = fetched;
      _teamsMemo = polySportsTeams(event, fetched);
    }
    return _teamsMemo;
  }

  /// The held outcome's own line colour, as the market sheet draws it: a
  /// game's team (or a three-way market's draw), else one outcome of a
  /// many-outcome market. Null for a Yes / No or Up / Down market's side
  /// (the bar's green and red split) and for a line the market sheet's
  /// chart does not draw.
  Color? _heldLineColor(WidgetRef ref, PolymarketEvent event,
      PolySportsTeams? sportsTeams, String tokenId) {
    final isGame = !event.isSyntheticBinary &&
        (event.gameId != null || event.metadataGameId != null);
    final moneyline = isGame && polyWdlOutcomes(event, sportsTeams) == null
        ? polyGameLinesFor(ref, event).winner
        : null;
    final team = gameLineColor(event, sportsTeams, moneyline, tokenId);
    if (team != null) return team;
    if (event.isBinary) return null;
    final charted = polyChartedOutcomes(event.outcomes, kPolyOutcomeColors)
        .where((o) => o.outcome.tokenId == tokenId)
        .map((o) => o.color)
        .firstOrNull;
    // An Up or Down side is already the split's green or red.
    return charted == AppColors.marketUp || charted == AppColors.marketDown
        ? null
        : charted;
  }

  @override
  Widget build(BuildContext context) {
    final position = widget.position;
    final c = context.colors;
    // Follow authoritative holdings while this page remains open. A quote
    // near $1 or an elapsed end time does not establish claimability.
    final holdings = [
      ...ref.watch(polymarketClaimablePositionsProvider),
      ...ref.watch(polymarketActivePositionsProvider),
    ];
    final pos = holdings
            .where((p) =>
                p.marketId == position.marketId &&
                p.tokenId == position.tokenId &&
                p.outcome == position.outcome)
            .firstOrNull ??
        position;
    // The page's own token is kept on the live feed while it is open, so
    // the value and the chart tick with the book rather than waiting on
    // the positions list to have subscribed it. addTokens is idempotent.
    final liveToken = pos.tokenId;
    if (liveToken != null && liveToken.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        ref.read(livePriceProvider.notifier).addTokens([liveToken]);
      });
    }
    // Only rebuild when this position's token price changes.
    final livePrice = ref.watch(livePriceProvider
        .select((s) => pos.tokenId != null ? s.prices[pos.tokenId] : null));
    final currentPrice =
        pos.isResolved ? pos.currentPrice : livePrice ?? pos.currentPrice;
    final currentValue = currentPrice * pos.size;
    // What the user actually paid: the trade-history basis first, then
    // the locally recorded USDC, then the API's avgPrice × size, never
    // above the share count. Shared with the market sheet's chart so the
    // "Bought" line sits at the same price on both screens.
    final costBasis = polymarketPositionCostBasis(ref, pos);
    // PnL is `currentValue - costBasis` so it lines up with what the
    // user actually paid, not the rounded basis from the API.
    final pnl = currentValue - costBasis;
    final pnlPercent = costBasis > 0 ? (pnl / costBasis) * 100 : 0.0;

    final pnlPositive = pnl >= 0;
    final pnlColor = pnlPositive ? _kPolyGreen : _kPolyRed;
    final pnlText =
        '${pnlPositive ? '+' : '-'}${formatPolyAmount(ref, pnl.abs())}'
        ' · ${pnlPercent >= 0 ? '+' : ''}${pnlPercent.toStringAsFixed(1)}%';
    // Settled: whether the held side won (the bar's own reading).
    final won = pos.won ?? currentPrice >= 0.5;
    final investedText = formatPolyAmount(ref, costBasis);

    final eventDetails = pos.eventSlug != null && pos.eventSlug!.isNotEmpty
        ? ref.watch(polymarketEventDetailsProvider(pos.eventSlug!))
        : null;

    // Header icon, crest-first. Sports positions carry the generic league
    // ball as `marketImage` (Gamma ships it as every sub-market's icon); the
    // real crests live in the event's `teams`, already fetched above for the
    // description. Match the held outcome first ("Portugal" — moneyline),
    // then the question text ("Will Portugal win…?" — Yes/No sub-market
    // bets where outcome is just "Yes"). Pops in when details load.
    final event = eventDetails?.valueOrNull;
    _event = event;
    // Market / Livestream, as on the market sheet: the player is built only
    // once Livestream is picked, and while another route covers this one
    // the stream plays on in the mini player.
    final watching = watchingStream;
    syncStreamHandoff(context);
    final hasToken = pos.tokenId != null && pos.tokenId!.isNotEmpty;
    // Open (a live price, not settled: not won, lost, claimable or
    // claimed): the gauge, with the chance in its middle. A market past
    // its end and waiting for the result still trades, so it counts. A
    // settled position keeps the bar.
    final showGauge = !watching && hasToken && !pos.isResolved;
    // The event's teams (read by slug when the event came without them)
    // and, when it is a match, its two sides as the market sheet names
    // them.
    final fetchedTeams =
        event == null ? const <PolymarketTeam>[] : polyFetchedTeams(ref, event);
    final headerTeams = event == null
        ? const <PolymarketTeam>[]
        : (event.teams.isNotEmpty ? event.teams : fetchedTeams);
    final sportsTeams = event == null ? null : _sportsTeams(event, fetchedTeams);
    // A game keeps the live score feed open while its position is on
    // screen (nothing else joined it when the screen opens from the
    // Portfolio). connect() is idempotent.
    if (event != null &&
        !_joinedScores &&
        !event.isSyntheticBinary &&
        (event.gameId != null || event.metadataGameId != null)) {
      _joinedScores = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(sportsLiveProvider.notifier).connect();
      });
    }
    // Skip the outcome pass for bare "Yes"/"No" — logoFromTeams' substring
    // fuzz matches "no" inside team names (Norway, Nottingham…), which
    // would hijack the crest from the question-text pass below.
    final outcomeLower = pos.outcome.toLowerCase();
    final outcomeIsSide = outcomeLower == 'yes' || outcomeLower == 'no';
    final headerImage = (outcomeIsSide
            ? null
            : PolymarketEvent.logoFromTeams(headerTeams, pos.outcome)) ??
        PolymarketEvent.logoForText(headerTeams, pos.marketQuestion) ??
        pos.marketImage;

    return Scaffold(
      backgroundColor: context.isDark
          ? context.colors.gradientBottom
          : context.colors.background,
      resizeToAvoidBottomInset: false,
      body: Container(
        decoration: AppDecorations.screenGradient(context),
        child: PlatformSafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.max,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 4.h),
                child: Row(
                  children: [
                    const KuteCloseButton(),
                    SizedBox(width: 8.w),
                    // The market's icon (crest-first, see above) and its
                    // title, as on the market sheet's header. No Sal on a
                    // position: its rows say what is at risk and how to
                    // protect it.
                    if (headerImage != null && headerImage.isNotEmpty) ...[
                      // PolyCrestImage (not raw CachedNetworkImage) so SVG
                      // flags / team crests render: Polymarket serves many
                      // national-team icons as `.svg`.
                      PolyCrestImage(
                        url: headerImage,
                        size: 32.w,
                        radius: 8.w,
                        label: pos.marketQuestion,
                      ),
                      SizedBox(width: 8.w),
                    ],
                    Expanded(
                      // The whole title: smaller rather than cut.
                      child: FittedTitle(
                        pos.marketQuestion,
                        key: const ValueKey('poly-position-title'),
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 18.sp,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 28.h),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(height: 10.h),
                      // Watching: the stream at the top, as on the market
                      // sheet.
                      if (watching) ...[
                        buildMediaToggle(c),
                        SizedBox(height: 14.h),
                        buildWatchPlayer(c),
                        SizedBox(height: 18.h),
                      ],

                      // A game: the market sheet's own header, the score
                      // between the teams. Its own Consumer, so a score
                      // repaints the header alone.
                      if (event != null && sportsTeams != null) ...[
                        Consumer(
                          builder: (context, headerRef, _) =>
                              PolyGameTeamsHeader.of(
                            polyGameHeaderData(headerRef, context, event,
                                sportsTeams: sportsTeams, teams: headerTeams),
                            teams: sportsTeams,
                            eventTeams: headerTeams,
                          ),
                        ),
                        SizedBox(height: 22.h),
                      ],

                      if (hasStream && !watching) ...[
                        SizedBox(height: 8.h),
                        buildMediaToggle(c),
                      ],
                      if (!watching && hasToken) ...[
                        SizedBox(height: hasStream ? 14.h : 8.h),
                        LiveTokenScope(
                          tokens: [if (!pos.isResolved) pos.tokenId!],
                          keepAlive: true,
                          // Where the held outcome's chance is now against
                          // what was paid for it, under a pill naming the
                          // held side: a Yes / No or Up / Down market's
                          // green and red split, or a fill in the outcome's
                          // own line colour, with a "Bought · 32¢" tick at
                          // the price paid.
                          // Open: the half-circle gauge with the chance in
                          // its middle (position_chance_gauge.dart);
                          // settled: the bar (position_chance_bar.dart).
                          // Its own Consumer: the game's lines are read for
                          // the colour alone.
                          child: RepaintBoundary(
                            child: Consumer(builder: (context, barRef, _) {
                              final tokenId = pos.tokenId!;
                              final lineColor = event == null
                                  ? null
                                  : _heldLineColor(barRef, event,
                                      sportsTeams, tokenId);
                              final bought = pos.size > 0 && costBasis > 0
                                  ? costBasis / pos.size
                                  : null;
                              final spec = polyPositionChanceBarSpec(
                                outcome: pos.outcome,
                                chance:
                                    polyPositionBarChance(pos, currentPrice),
                                bought: bought,
                                lineColor: lineColor,
                                // The chart's own colour for a line with
                                // none of its own.
                                fallbackColor: pnlColor,
                              );
                              final tickLabel = bought == null
                                  ? null
                                  : '${context.l10n.polyChartBought} · '
                                      '${formatPolyBoughtCents(bought)}';
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Which side is held, in its colour.
                                  _HeldPill(
                                      outcome: pos.outcome, color: spec.held),
                                  SizedBox(height: 14.h),
                                  if (showGauge)
                                    PolyPositionChanceGauge(
                                      spec: spec,
                                      chance: currentPrice,
                                      tickLabel: tickLabel,
                                    )
                                  else ...[
                                    PolyPositionChanceBar(
                                      spec: spec,
                                      tickLabel: tickLabel,
                                    ),
                                    SizedBox(height: 8.h),
                                    // Settled: the chance the gauge would
                                    // write in its middle.
                                    RollingNumberText(
                                      text: context.l10n.betPercentChance(
                                          formatPolyChanceFigure(
                                              currentPrice)),
                                      style: positionTileCaptionStyle(c),
                                    ),
                                  ],
                                ],
                              );
                            }),
                          ),
                        ),
                      ],


                      // What it is worth now (with the profit or loss) and
                      // what it pays if the held side wins (once settled:
                      // what it paid), each on its own tile.
                      SizedBox(height: 20.h),
                      PositionStatTiles(
                        left: PositionStatTile(
                          key: const ValueKey('poly-position-value'),
                          label: context.l10n.betCurrentValue,
                          // `formatPolyAmount` honors the Predictions
                          // denomination setting. Rolling digits, so the
                          // value visibly ticks with the live price.
                          value: RollingNumberText(
                            text: formatPolyAmount(ref, currentValue),
                            style: positionTileValueStyle(c),
                          ),
                          caption: RollingNumberText(
                            text: pnlText,
                            style: positionTileCaptionStyle(c, color: pnlColor),
                          ),
                        ),
                        right: PositionStatTile(
                          key: const ValueKey('poly-position-payout'),
                          label: pos.isResolved
                              ? context.l10n.payout
                              : context.l10n.betReceiptPayout,
                          // A dollar a share if the held side wins.
                          value: Text(
                            pos.isResolved && !won
                                ? context.l10n.betNoPayout
                                : formatPolyAmount(ref, pos.size),
                            maxLines: 1,
                            style: positionTileValueStyle(c),
                          ),
                          caption: costBasis > 0
                              ? Text(
                                  '${context.l10n.paid} $investedText',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: positionTileCaptionStyle(c),
                                )
                              : null,
                        ),
                      ),

                      if (pos.isResolved ||
                          pos.endDateStr?.isNotEmpty == true) ...[
                        SizedBox(height: 16.h),
                        // While a game is being played its header says
                        // where it is; the market's scheduled end (already
                        // past) would only mislead.
                        Consumer(builder: (context, expiryRef, _) {
                          final isGame = event != null && sportsTeams != null;
                          final ws = isGame
                              ? polyLiveMatchUpdate(expiryRef, event)
                              : null;
                          if (!pos.isResolved &&
                              isGame &&
                              polyGameIsLive(event, ws)) {
                            return const SizedBox.shrink();
                          }
                          // Over and not claimable yet: when Polymarket
                          // expects the result, counted down by the minute.
                          // A passed end date alone is not over (the Brazil
                          // "who wins" market kept its first-round date
                          // while still trading), but for a 5 or 15 minute
                          // round: polyMarketHasEnded, as on the card.
                          final end = polyPositionEnd(pos);
                          final over = !pos.isResolved &&
                              polyMarketHasEnded(
                                  eventSlug: pos.eventSlug,
                                  end: end,
                                  event: event,
                                  live: isGame
                                      ? PolyLiveGame.of(event, ws)
                                      : null,
                                  isGame: isGame);
                          final settleAt = over && pos.marketId.isNotEmpty
                              ? expiryRef
                                  .watch(polyExpectedSettlementProvider(
                                      pos.marketId))
                                  .valueOrNull
                              : null;
                          if (settleAt != null) {
                            expiryRef.watch(polyMinuteTickProvider);
                          }
                          final roundEnd = polyShortRoundEnd(pos.eventSlug);
                          if (over &&
                              polyShortRoundEstimating(
                                  roundEnd, DateTime.now())) {
                            expiryRef.watch(polyAwaitingTickProvider);
                          }
                          return _PositionExpiry(
                            end: end,
                            resolved: pos.isResolved,
                            // The game's header already says when it
                            // kicks off; a match's end is its kickoff.
                            quietBeforeEnd: event != null &&
                                sportsTeams != null &&
                                event.kickoff != null,
                            // Over but not claimable yet: say what is
                            // being waited for (position_awaiting.dart).
                            ended: over,
                            // Still trading past the market's own end: the
                            // event's, when it is later.
                            eventEnd: event?.endDate,
                            endedLabel: polyAwaitingText(context.l10n,
                                polyAwaitingResultFor(currentPrice),
                                shortRound: polyIsShortRound(pos.eventSlug),
                                settleAt: settleAt,
                                roundEnd: roundEnd),
                          );
                        }),
                      ],


                      SizedBox(height: 12.h),
                      // How to protect it: the closest protective order
                      // Predictions has, a limit sell, set on the sell
                      // ticket's Advanced page. Only while it is open.
                      if (!pos.isResolved && pos.size > 0)
                        PositionLinkRow(
                          key: const ValueKey('poly-position-protect'),
                          label: context.l10n.positionProtectIt,
                          value: context.l10n.betSellAt,
                          onTap: () {
                            TrackingService.track('position_protect_tapped',
                                params: {
                                  'venue': 'polymarket',
                                  ...VenueAnalytics.pmKindParams([
                                    pos.tokenId,
                                    pos.marketId,
                                    pos.eventSlug
                                  ]),
                                  'wallet_kind': 'hot',
                                  'target': 'limit_sell',
                                });
                            context.pop();
                            SellSheet.show(context,
                                position: pos,
                                source: 'position_protect',
                                startWithLimit: true);
                          },
                        ),

                      // What the position is made of, as plain rows on
                      // the shared bottom sheet, one row away.
                      _PositionDetailsRow(rows: [
                        PositionRow(
                            context.l10n.activityOutcome, pos.outcome),
                        PositionRow(context.l10n.betShares,
                            pos.size.toStringAsFixed(2)),
                        // What was paid per share: the chart's dashed
                        // "Bought" line, as a number.
                        if (pos.size > 0 && costBasis > 0)
                          PositionRow(context.l10n.chartBoughtAt,
                              formatPolyBoughtCents(costBasis / pos.size)),
                        // The entry basis (what the user actually paid).
                        PositionRow(context.l10n.betInvested, investedText),
                      ]),

                      if (eventDetails != null)
                        eventDetails.when(
                          // Skeleton mimicking the description text lines.
                          loading: () => Padding(
                            padding: EdgeInsets.only(top: 12.h),
                            child: KuteSkeleton(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SkeletonBar(double.infinity, 12.h),
                                  SizedBox(height: 8.h),
                                  SkeletonBar(double.infinity, 12.h),
                                  SizedBox(height: 8.h),
                                  SkeletonBar(180.w, 12.h),
                                ],
                              ),
                            ),
                          ),
                          error: (_, __) => const SizedBox.shrink(),
                          data: (event) {
                            if (event?.description == null ||
                                event!.description!.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            return _ClosingConditionsRow(
                                description: event.description!);
                          },
                        ),

                      // (Balance row removed — BTC-native model: users think in BTC,
                      // not USDC, on Polymarket screens. The balance lives on home.)
                      SizedBox(height: 8.h),
                    ],
                  ),
                ),
              ),
              // Sticky action footer — Buy More + Sell live outside the
              // scroll view so they're always visible regardless of how
              // far down the user scrolls. Rendered for every position
              // but a won one: a win is claimed automatically
              // (claim_auto_fire.dart), so there is nothing to tap.
              //
              // Wrapped in SafeArea(top:false) and given extra bottom
              // padding so the buttons clear the iPhone home-indicator
              // area — earlier they sat right against the gesture bar
              // and felt unconfirmable.
              if (!(pos.isResolved && pos.won == true))
                ClipRect(
                  child: KuteBlur(
                    sigmaX: 18,
                    sigmaY: 18,
                    child: Container(
                      color: (context.isDark ? c.surface : c.background)
                          .withValues(alpha: 0.55),
                      child: SafeArea(
                        top: false,
                        child: Padding(
                          padding:
                              EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 16.h),
                          child: Row(
                            children: [
                              // Buy More removed — users go to the market
                              // via the browse list / search to add to a
                              // position. Position detail sticks to its
                              // single job: review + sell.
                              Expanded(
                                // Resolved (a lost side): Clear runs right
                                // here, one tap, and ends on the
                                // confirmation (position_claim.dart).
                                child: pos.isResolved
                                    ? PolyClaimButton(
                                        position: pos,
                                        surface: 'position_detail',
                                        popRoute: true,
                                        icon: Icons.check_rounded,
                                      )
                                    : _PositionActionButton(
                                        label: context.l10n.sell,
                                        icon: Icons.remove_rounded,
                                        color: _kPolyRed,
                                        // AppButton fires its own haptic.
                                        onTap: () {
                                          context.pop();
                                          SellSheet.show(context,
                                              position: pos);
                                        },
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Per-share price formatter that mirrors Polymarket. Sub-dollar
  /// share prices read in cents with one decimal (e.g. `0.3¢`,
  /// `26.5¢`) so deep-out-of-the-money positions don't collapse to
  /// `$0.00` when rounded to two decimals — the bug you saw on a
  /// position bought around 0.3¢. Once a share crosses $1 the value
  /// switches to dollar formatting.
}

/// Filled pill button shared by Buy More + Sell. Same height, shape,
/// icon size, and font weight — only the accent color differs.
class _PositionActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _PositionActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Unified AppButton chrome (56.h / 16.r); the fill comes from the
    // canonical market tokens and the label contrast is auto-picked.
    return AppButton(
      text: label,
      icon: icon,
      onPressed: onTap,
      color: color,
      fontWeight: FontWeight.w800,
    );
  }
}

/// "Closing conditions": one row, as the market sheet's "Rules and
/// resolution", opening the market's description on the app's shared
/// bottom sheet. A second tap while that sheet is opening or open is
/// ignored, so the same sheet is never stacked on itself.
/// "Details": one row under the position (the Investing position's same
/// row), opening the shared bottom sheet with what the position is made
/// of, the screen keeping only what is at risk.
class _PositionDetailsRow extends StatefulWidget {
  final List<PositionRow> rows;
  const _PositionDetailsRow({required this.rows});

  static const rowKey = ValueKey('poly-position-details');

  @override
  State<_PositionDetailsRow> createState() => _PositionDetailsRowState();
}

class _PositionDetailsRowState extends State<_PositionDetailsRow> {
  bool _open = false;

  Future<void> _show() async {
    if (_open) return;
    _open = true;
    try {
      await showAppBottomSheet<void>(
        context: context,
        builder: (_) => _PositionDetailsSheet(rows: widget.rows),
      );
    } finally {
      _open = false;
    }
  }

  @override
  Widget build(BuildContext context) => PositionLinkRow(
        key: _PositionDetailsRow.rowKey,
        label: context.l10n.details,
        onTap: _show,
      );
}

/// "▲ You hold Up": the held side under the title, in its colour (the
/// app's up / down colours for Yes / Up and No / Down, a team's own).
class _HeldPill extends StatelessWidget {
  final String outcome;
  final Color color;
  const _HeldPill({required this.outcome, required this.color});

  static const pillKey = ValueKey('poly-position-held');

  @override
  Widget build(BuildContext context) {
    return PositionSidePill(
      key: pillKey,
      text: '${context.l10n.chartYouHold} $outcome',
      color: color,
      up: polyOutcomeDirection(outcome),
    );
  }
}

class _PositionDetailsSheet extends StatelessWidget {
  final List<PositionRow> rows;
  const _PositionDetailsSheet({required this.rows});

  @override
  Widget build(BuildContext context) {
    return AppBottomSheetContainer(
      maxHeight: 0.85,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppBottomSheetHeader(
            title: context.l10n.details,
            trailing: IconButton(
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20.w, 4.h, 20.w, 24.h),
              child: PositionRowsCard(rows: rows),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClosingConditionsRow extends StatefulWidget {
  final String description;
  const _ClosingConditionsRow({required this.description});

  @override
  State<_ClosingConditionsRow> createState() => _ClosingConditionsRowState();
}

class _ClosingConditionsRowState extends State<_ClosingConditionsRow> {
  bool _open = false;

  Future<void> _show() async {
    if (_open) return;
    _open = true;
    try {
      await showAppBottomSheet<void>(
        context: context,
        builder: (_) =>
            _ClosingConditionsSheet(description: widget.description),
      );
    } finally {
      _open = false;
    }
  }

  @override
  Widget build(BuildContext context) => PolyRulesRow(
        label: context.l10n.betClosingConditions,
        onTap: _show,
      );
}

/// The market's closing conditions (its description) on the shared
/// bottom sheet, laid out as the "Rules and resolution" sheet.
class _ClosingConditionsSheet extends StatelessWidget {
  final String description;
  const _ClosingConditionsSheet({required this.description});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppBottomSheetContainer(
      maxHeight: 0.85,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppBottomSheetHeader(
            title: context.l10n.betClosingConditions,
            trailing: IconButton(
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20.w, 4.h, 20.w, 24.h),
              child: Text(
                description,
                style: TextStyle(
                  color: c.textSecondary,
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w500,
                  height: 1.5,
                  letterSpacing: -0.1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// When [position]'s market ends: a 5 / 15 minute round's own end (its
/// slug carries the start), else the market's end date.
DateTime? polyPositionEnd(PolymarketPosition position) {
  final round =
      RegExp(r'-(5|15)m-(\d{10})$').firstMatch(position.eventSlug ?? '');
  if (round != null) {
    return DateTime.fromMillisecondsSinceEpoch(int.parse(round[2]!) * 1000,
            isUtc: true)
        .add(Duration(minutes: int.parse(round[1]!)));
  }
  return DateTime.tryParse(position.endDateStr ?? '');
}

class _PositionExpiry extends StatefulWidget {
  const _PositionExpiry(
      {required this.end,
      required this.resolved,
      this.quietBeforeEnd = false,
      this.ended = false,
      this.eventEnd,
      required this.endedLabel});
  final DateTime? end;
  final bool resolved;

  /// The market is over and waiting for its result (polyMarketHasEnded):
  /// the only way to the ended caption. A passed [end] alone never is.
  final bool ended;

  /// The event's own end. A market still trading past its own [end] (a
  /// first-round date, the runoff weeks away) says this one when it is
  /// later, and nothing otherwise.
  final DateTime? eventEnd;

  /// What an ended, not yet claimable position waits for.
  final String endedLabel;

  /// Say nothing until the end has passed (a game whose header shows its
  /// kickoff).
  final bool quietBeforeEnd;
  @override
  State<_PositionExpiry> createState() => _PositionExpiryState();
}

class _PositionExpiryState extends State<_PositionExpiry> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !widget.resolved && widget.end != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    var end = widget.end;
    // Past the market's own end but not over: the event's later end, or
    // nothing. Never "Ended" on a date alone.
    if (!widget.resolved &&
        !widget.ended &&
        end != null &&
        !end.isAfter(now)) {
      final eventEnd = widget.eventEnd;
      end = eventEnd != null && eventEnd.isAfter(now) ? eventEnd : null;
    }
    final left = end?.difference(now);
    final String label;
    if (widget.resolved) {
      label = context.l10n.activitySettled;
    } else if (widget.ended) {
      label = widget.endedLabel;
    } else if (left == null) {
      return const SizedBox.shrink();
    } else if (widget.quietBeforeEnd) {
      return const SizedBox.shrink();
    } else if (left.inDays >= 1) {
      label = context.l10n
          .betEndsDate(DateFormat('MMM d, HH:mm').format(end!.toLocal()));
    } else {
      final h = left.inHours;
      final m = (left.inMinutes % 60).toString().padLeft(2, '0');
      final s = (left.inSeconds % 60).toString().padLeft(2, '0');
      label = context.l10n.predictEndsIn(h > 0 ? '$h:$m:$s' : '$m:$s');
    }
    final c = context.colors;
    // A quiet pill, centred.
    return Center(
      child: Container(
        key: const ValueKey('poly-position-expiry'),
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: c.borderSubtle, width: 0.5),
        ),
        child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: c.textSecondary,
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()])),
      ),
    );
  }
}
