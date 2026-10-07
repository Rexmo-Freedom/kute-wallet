// A Predictions position on the Portfolio (the spending wallet's and a
// Ledger's), in the list card's language: names on the left, the number
// that matters on the right, one quiet caption under them.
//
//   * a game: a row per team in the title's order (crest, name, and its
//     score once the game is on), as on the Predictions list card;
//   * any other market: its image and its title, on up to two lines;
//   * on the right: what the position is worth now, with the profit or
//     loss under it in the app's up / down colours;
//   * one line for the position itself ("Yes · 2.07 shares at 96¢", led
//     by the market's own question when the card shows a game's teams);
//   * a caption: the game's clock while it is played, else when the market
//     ends; once it has ended and until its result is claimable, that it
//     is waiting for the result ("Ended · Result in a few minutes", "You
//     won · Ready to claim soon", "Ended · Lost"; position_awaiting.dart);
//     "Ready to claim" / "Settled" on a resolved one, unless its Claim
//     button already says so; "Selling…" while a sale of it is on its way
//     (the caller's [status]).
//
// The card reads the position's event by its slug (title, teams, game)
// from the cards' shared batch (poly_position_events.dart: one read for
// every card on screen, kept a minute, the feed's own copy when it has
// one) and, for a game that may be on, the live sports feed. Without the
// event (no slug, not read yet, or the read failed) it is the plain
// market shape. Every money figure is the caller's: the card only lays
// them out.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart' hide TextDirection;

import 'package:kute/helpers/formatters/polymarket_amount_formatter.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_sports_provider.dart'
    show sportsLiveProvider, sportsUpdateFor;
import 'package:kute/screens/hyperliquid/components/hl_format.dart'
    show formatHlSize;
import 'package:kute/screens/polymarket/components/game_time.dart';
import 'package:kute/screens/polymarket/components/live_game.dart';
import 'package:kute/screens/polymarket/components/market_card.dart';
import 'package:kute/screens/polymarket/components/position_awaiting.dart';
import 'package:kute/screens/portfolio/poly_position_events.dart'
    show polyPositionEventProvider;
import 'package:kute/screens/shared/kute_motion.dart';
import 'package:kute/screens/shared/portfolio_position_card.dart';
import 'package:kute/services/polymarket/live_game/game_sides.dart';
import 'package:kute/services/polymarket/market_card_shape.dart';
import 'package:kute/theme/app_theme.dart';

class PolyPositionCard extends ConsumerWidget {
  /// The market's question.
  final String question;
  final String? imageUrl;

  /// The held outcome ("Yes", "49ers").
  final String outcome;
  final double shares;

  /// The average price paid per share (0..1).
  final double avgPrice;

  /// What the position is worth now, in dollars.
  final double value;

  /// The profit or loss in dollars, and in percent when known.
  final double pnl;
  final double? pnlPercent;

  /// The position's event, for a game's teams and score.
  final String? eventSlug;

  /// When the market ends.
  final DateTime? end;

  /// The market's condition id: once it has ended, when its result is
  /// expected (position_awaiting.dart).
  final String? conditionId;

  /// The market has resolved; [claimable] when it paid out.
  final bool resolved;
  final bool claimable;
  final VoidCallback? onTap;
  final Widget? action;

  /// An order in flight on this position ("Selling…"); replaces the
  /// caption until the venue has answered.
  final String? status;

  const PolyPositionCard({
    super.key,
    required this.question,
    this.imageUrl,
    required this.outcome,
    required this.shares,
    required this.avgPrice,
    required this.value,
    required this.pnl,
    this.pnlPercent,
    this.eventSlug,
    this.end,
    this.conditionId,
    this.resolved = false,
    this.claimable = false,
    this.onTap,
    this.action,
    this.status,
  });

  /// The price paid per share in cents, as the card always wrote it.
  static String _cents(double price) => '${(price * 100).round()}¢';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final l10n = context.l10n;
    final slug = eventSlug;
    final event = slug == null || slug.isEmpty
        ? null
        : ref.watch(polyPositionEventProvider(slug));
    // A game: the event is a match the venue keeps a game for, and its
    // title names two teams.
    final isGame = event != null &&
        !event.isSyntheticBinary &&
        (event.gameId != null || event.metadataGameId != null);
    final teams = isGame ? titleTeams(event.title) : null;

    PolyLiveGame? live;
    if (event != null && teams != null) {
      final ws = ref.watch(sportsLiveProvider.select((map) => sportsUpdateFor(
          map,
          slug: event.slug,
          gameId: event.gameId,
          metadataGameId: event.metadataGameId)));
      live = PolyLiveGame.of(event, ws);
      // A game that may be on keeps the live score feed open while its
      // card is on screen (nothing else joined it on the Portfolio).
      // connect() is idempotent.
      final start = event.gameStart;
      final mayBeOn = !resolved &&
          !event.ended &&
          !event.closed &&
          (start == null ||
              start.isBefore(DateTime.now().add(const Duration(hours: 1))));
      if (mayBeOn) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            ref.read(sportsLiveProvider.notifier).connect();
          }
        });
      }
    }

    final amount = PortfolioCardValue(
      value: formatPolyAmount(ref, value),
      pnl: PortfolioCardValue.pnlText(formatPolyAmount(ref, pnl.abs()), pnl,
          percent: pnlPercent),
      up: pnl >= 0,
    );

    // The position in one line. On a game's card the teams replace the
    // title, so a market inside the game (a spread, a total) leads the
    // line with its own question.
    final entry =
        '$outcome · ${l10n.portfolioPredictionEntry(formatHlSize(shares, maxDecimals: 2), _cents(avgPrice))}';
    final positionLine = teams != null && question.trim() != event!.title.trim()
        ? '$question · $entry'
        : entry;

    // The market has stopped and its result is not claimable yet (Polymarket
    // is still resolving it): say so instead of the end date or "Final", so
    // the card does not look stuck. A short round turns at its end, so the
    // card refreshes by the minute while its end is near.
    final shortRound = polyIsShortRound(slug);
    if (!resolved && shortRound && end != null) {
      final left = end!.difference(DateTime.now());
      if (left > Duration.zero && left < const Duration(hours: 1)) {
        ref.watch(polyMinuteTickProvider);
      }
      // In its last minute, every few seconds: the estimate starts at the end.
      if (left > Duration.zero && left <= const Duration(minutes: 1)) {
        ref.watch(polyAwaitingTickProvider);
      }
    }
    final awaiting = !resolved &&
        polyMarketHasEnded(
            eventSlug: slug,
            end: end,
            event: event,
            live: live,
            isGame: isGame);

    final String? footer;
    if (status != null) {
      footer = status;
    } else if (resolved && action != null) {
      // The Claim (or Clear) button under the card says it already.
      footer = null;
    } else if (resolved) {
      footer = claimable ? l10n.ledgerPmClaimable : l10n.activitySettled;
    } else if (awaiting) {
      final cid = conditionId;
      final settleAt = cid == null || cid.isEmpty
          ? null
          : ref.watch(polyExpectedSettlementProvider(cid)).valueOrNull;
      // A known settlement time counts down by the minute.
      if (settleAt != null) ref.watch(polyMinuteTickProvider);
      // A short round's estimate counts from its end, every few seconds.
      final roundEnd = polyShortRoundEnd(slug);
      if (polyShortRoundEstimating(roundEnd, DateTime.now())) {
        ref.watch(polyAwaitingTickProvider);
      }
      footer = polyAwaitingText(
          l10n, polyAwaitingResultFor(shares > 0 ? value / shares : null),
          shortRound: shortRound, settleAt: settleAt, roundEnd: roundEnd);
    } else if (live != null) {
      footer = [
        live.finished ? l10n.polyMarkerFinal : live.clockOrStatus(context),
        // Tennis: the games of the set in play.
        if (!live.finished)
          polyCardScore(live.score,
                  period: live.period, firstIsHome: live.firstIsHome)
              ?.setGames,
      ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    } else if (teams != null && event!.ended) {
      footer = l10n.polyMarkerFinal;
    } else if (teams != null && event!.kickoff != null) {
      // The game header's own wording, refreshed by the minute on the
      // day of the game ("Starts in 23 min").
      final kickoff = event.kickoff!;
      if (kickoff.difference(DateTime.now()).inHours < 24) {
        ref.watch(polyMinuteTickProvider);
      }
      footer = polyKickoffText(l10n, kickoff, now: DateTime.now());
    } else if (end != null) {
      // Date only, as on the list card; a market ending within a day
      // says the hour too. In the app's language.
      final local = end!.toLocal();
      final soon = local.difference(DateTime.now()).inHours.abs() < 24;
      footer = soon
          ? '${DateFormat.MMMd(l10n.localeName).format(local)}, '
              '${DateFormat.Hm(l10n.localeName).format(local)}'
          : DateFormat.yMMMd(l10n.localeName).format(local);
    } else {
      footer = null;
    }

    return PortfolioCardFrame(
      onTap: onTap,
      action: action,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // The figure takes what it needs, up to a little under half
          // of the card; the names keep the rest.
          LayoutBuilder(
            builder: (context, box) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  // The plain title gives way to the game's rows when the
                  // event lands: a short cross-fade, the card easing to
                  // its new height.
                  child: ArrivalSwitcher(
                    state: teams != null ? 'teams' : 'title',
                    child: teams != null
                        ? _teamRows(c, event!, teams, live)
                        : _heading(c, event),
                  ),
                ),
                SizedBox(width: 12.w),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: box.maxWidth * 0.45),
                  child: amount,
                ),
              ],
            ),
          ),
          SizedBox(height: 10.h),
          _positionLine(c, positionLine),
          if (footer != null && footer.isNotEmpty) ...[
            SizedBox(height: 8.h),
            Text(
              footer,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: portfolioCardCaptionStyle(c),
            ),
          ],
        ],
      ),
    );
  }

  /// The position in one line ("Yes · 2.07 shares at 96¢") under the
  /// card's names, in the caption under an Investing card's name.
  Widget _positionLine(AppColorsExtension c, String line) => Text(
        line,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: c.textSecondary,
          fontSize: 13.sp,
          fontWeight: FontWeight.w500,
          letterSpacing: -0.1,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );

  /// A game: one row per team in the title's order, with its score once
  /// the game is on. The side ahead on the score reads in the primary
  /// colour, as on the list card.
  Widget _teamRows(AppColorsExtension c, PolymarketEvent event,
      (String, String) teams, PolyLiveGame? live) {
    final score = live == null
        ? null
        : polyCardScore(live.score,
            period: live.period, firstIsHome: live.firstIsHome);
    final leader = score == null || score.a == score.b
        ? 0
        : (score.a > score.b ? 1 : -1);
    Widget row(String name, int? points, bool leads) {
      final tone = leads ? c.textPrimary : c.textSecondary;
      return Row(
        children: [
          PolyCardThumbnail(
            title: name,
            imageUrl: PolymarketEvent.logoFromTeams(event.teams, name),
            category: event.category,
            size: 28.w,
            radius: 8.r,
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: PolyCardTeamName(
              name: name,
              short: polyCardTeamAbbreviation(event.teams, name),
              style: TextStyle(
                color: tone,
                fontSize: 16.sp,
                fontWeight: leads ? FontWeight.w600 : FontWeight.w500,
                letterSpacing: -0.2,
              ),
            ),
          ),
          if (points != null) ...[
            SizedBox(width: 8.w),
            Text(
              '$points',
              maxLines: 1,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 16.sp,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        row(teams.$1, score?.a, leader >= 0),
        SizedBox(height: 10.h),
        row(teams.$2, score?.b, leader <= 0),
      ],
    );
  }

  /// Any other market: its image and its title, on up to two lines (the
  /// whole question is on the position screen).
  Widget _heading(AppColorsExtension c, PolymarketEvent? event) {
    // Crest first: a sports market carries the league's generic ball as
    // its image, the real crests are in the event's teams. The held
    // outcome names the team ("Portugal"), else the question does ("Will
    // Portugal win?"); a bare Yes / No is never matched against a name.
    final eventTeams = event?.teams ?? const <PolymarketTeam>[];
    final side = outcome.trim().toLowerCase();
    final image = (side == 'yes' || side == 'no'
            ? null
            : PolymarketEvent.logoFromTeams(eventTeams, outcome)) ??
        PolymarketEvent.logoForText(eventTeams, question) ??
        imageUrl;
    return Row(
      children: [
        PolyCardThumbnail(
          title: question,
          imageUrl: image,
          category: event?.category ?? '',
          size: 40.w,
          radius: 10.r,
        ),
        SizedBox(width: 10.w),
        Expanded(
          child: Text(
            question,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: polyCardTitleStyle(c),
          ),
        ),
      ],
    );
  }
}

/// A Predictions row that is not a held position yet (a resting order, a
/// bet being placed), on the position card's frame and in its language:
/// the market's image and its title written whole, the row's number on
/// the right with a quiet word under it, the side as one line, caption
/// lines, and the row's own button under them.
class PolyTitledCard extends StatelessWidget {
  final String title;
  final String? imageUrl;

  /// The right-hand figure (an order's price, a stake).
  final Widget? trailing;

  /// The line under the title ("BUY · Yes").
  final String? line;

  /// Quiet caption lines.
  final List<String> footer;

  /// Anything under the captions (a fill bar, a progress bar).
  final Widget? below;
  final Widget? action;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? margin;

  const PolyTitledCard({
    super.key,
    required this.title,
    this.imageUrl,
    this.trailing,
    this.line,
    this.footer = const [],
    this.below,
    this.action,
    this.onTap,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final lines = footer.where((s) => s.isNotEmpty).toList();
    return PortfolioCardFrame(
      onTap: onTap,
      action: action,
      margin: margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          LayoutBuilder(
            builder: (context, box) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PolyCardThumbnail(
                  title: title,
                  imageUrl: imageUrl,
                  category: '',
                  size: 40.w,
                  radius: 10.r,
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Text(
                    title,
                    maxLines: kPolyCardTitleLines,
                    overflow: TextOverflow.ellipsis,
                    style: polyCardTitleStyle(c),
                  ),
                ),
                if (trailing != null) ...[
                  SizedBox(width: 12.w),
                  ConstrainedBox(
                    constraints:
                        BoxConstraints(maxWidth: box.maxWidth * 0.45),
                    child: trailing,
                  ),
                ],
              ],
            ),
          ),
          if (line != null && line!.isNotEmpty) ...[
            SizedBox(height: 12.h),
            Text(
              line!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 14.sp,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.1,
                height: 1.25,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
          for (var i = 0; i < lines.length; i++) ...[
            SizedBox(height: i == 0 ? 6.h : 4.h),
            Text(lines[i],
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: portfolioCardCaptionStyle(c)),
          ],
          if (below != null) below!,
        ],
      ),
    );
  }
}
