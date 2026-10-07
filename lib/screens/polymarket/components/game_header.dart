// A game's header as the market sheet and the open-position screen both
// show it: the two teams' crests and names, and between them the score in
// the order the header names the teams (with the clock under it while the
// game is played, "Final" once it is over) or the plain "vs" before
// kickoff, with when the game starts under it (game_time.dart).
//
// Everything here was the market sheet's own; it lives in one place so a
// running bet on a game reads exactly like the game's market.
//
//   * polySportsTeams: is this event a match, and who plays it;
//   * polyWdlOutcomes: a football three-way's team / draw / team outcomes;
//   * polyGameHeaderData: live or over, the score, the clock (watches the
//     live sports feed and the game's timeline);
//   * PolyGameTeamsHeader: the header itself.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_browse_provider.dart'
    show polymarketEventTeamsProvider;
import 'package:kute/providers/polymarket_game_timeline_provider.dart';
import 'package:kute/providers/polymarket_sports_provider.dart'
    show sportsLiveProvider, sportsUpdateFor, SportsMatchUpdate;
import 'package:kute/screens/polymarket/components/game_time.dart';
import 'package:kute/screens/polymarket/components/live_game.dart';
import 'package:kute/screens/polymarket/components/poly_crest_image.dart';
import 'package:kute/screens/shared/kute_motion.dart';
import 'package:kute/services/polymarket/live_game/game_sides.dart';
import 'package:kute/services/polymarket/live_game/local_game_events.dart'
    show gameTimelineId;
import 'package:kute/theme/app_theme.dart';

/// The two sides of a match as its header names them, with each side's
/// crest when one is known.
typedef PolySportsTeams = ({
  String teamA,
  String teamB,
  String? imageA,
  String? imageB,
});

/// A football three-way market's outcomes, with the header's team names.
typedef PolyWdlOutcomes = ({
  PolymarketOutcome teamA,
  PolymarketOutcome draw,
  PolymarketOutcome teamB,
  String teamAName,
  String teamBName,
});

/// Returns the two team names + their per-team images when the
/// event looks like a sports matchup, else null. Detection: the
/// event is in the sports category AND the title contains a "vs"
/// or "vs." separator. The team images are pulled from the first
/// two outcomes' `imageUrl` (which Gamma serves as the per-team
/// logo via `groupItemImage`). If outcome images are missing we
/// still render the layout — the team initial circle takes over.
///
/// Title parsing handles the common Polymarket shapes:
///   "NBA: Lakers vs Warriors" -> ("Lakers", "Warriors")
///   "Counter-Strike: Team Falcons vs Legacy (BO5) - CS Asia Championships Playoffs"
///       -> ("Team Falcons", "Legacy")
///   "MLB: Dodgers vs. Padres" -> ("Dodgers", "Padres")
///   "Real Madrid vs Barcelona" -> ("Real Madrid", "Barcelona")
///
/// [fetchedTeams] are the teams read by slug for an event that arrived
/// without its own.
PolySportsTeams? polySportsTeams(
    PolymarketEvent event, List<PolymarketTeam> fetchedTeams) {
  // Synthetic Yes/No events (drilled-in WDL / candidate outcomes) carry a
  // single-question title that the vs-parser mis-reads as two teams — keep
  // them plain Yes/No.
  if (event.isSyntheticBinary) return null;
  final cat = event.category.toLowerCase();
  if (!cat.contains('sport') &&
      cat != 'nfl' &&
      cat != 'nba' &&
      cat != 'soccer' &&
      cat != 'mlb' &&
      cat != 'nhl' &&
      cat != 'ufc' &&
      cat != 'mma' &&
      cat != 'tennis' &&
      cat != 'f1' &&
      cat != 'golf') {
    return null;
  }
  var title = event.title;
  // Strip a leading "<Sport>:" prefix (e.g. "NBA:", "Counter-Strike:",
  // "F1:", "Soccer:") before we look for the "vs" separator. Without
  // this, the prefix glues itself to teamA ("Counter-Strike: Team
  // Falcons" instead of "Team Falcons").
  title = title.replaceFirst(RegExp(r'^[A-Za-z0-9\- ]+:\s+'), '');
  // Match "Team A vs Team B" or "Team A vs. Team B" (case insensitive).
  final match =
      RegExp(r'^(.+?)\s+vs\.?\s+(.+)$', caseSensitive: false).firstMatch(title);
  if (match == null) return null;
  var teamA = match.group(1)!.trim();
  var teamB = match.group(2)!.trim();
  // Strip trailing parenthetical qualifiers ("(BO5)", "(Home)") and
  // " - <tournament>" suffixes that Polymarket bolts onto the second
  // team. Apply to teamA too in the rare case the prefix-strip left
  // junk behind.
  String cleanTeam(String s) {
    var out = s;
    // " - CS Asia Championships Playoffs" / " - NBA Playoffs Round 1"
    out = out.replaceFirst(RegExp(r'\s+-\s+.*$'), '');
    // " (BO5)" / " (Home)" — strip any trailing parenthetical chunks.
    out = out.replaceAll(RegExp(r'\s*\([^)]*\)\s*$'), '');
    return out.trim();
  }

  teamA = cleanTeam(teamA);
  teamB = cleanTeam(teamB);
  if (teamA.isEmpty || teamB.isEmpty) return null;
  // Reject question / novelty titles that merely MENTION a matchup rather
  // than BEING one — e.g. "What will the announcers say during Scotland vs
  // Brazil World Cup Match?", which the vs-parser otherwise splits into
  // "What will the announcers say during Scotland" / "Brazil World Cup
  // Match?" and renders as a fake VS header. A real matchup is
  // "<Team> vs <Team>": short proper-noun sides and no trailing "?".
  if (event.title.trimRight().endsWith('?')) return null;
  if (!polyLooksLikeTeamName(teamA) || !polyLooksLikeTeamName(teamB)) {
    return null;
  }
  // Prefer the real crest logos from Gamma's `teams` array (proper team
  // badges); fall back to per-outcome images, then to initials. Use the
  // event's own teams when present, else the lazily-fetched set.
  final effectiveTeams = event.teams.isNotEmpty ? event.teams : fetchedTeams;
  String? imageA = PolymarketEvent.logoFromTeams(effectiveTeams, teamA);
  String? imageB = PolymarketEvent.logoFromTeams(effectiveTeams, teamB);
  // Submarket artwork is usable only when its outcome identifies this
  // team. Array ordering and a shared suffix such as "FC" are not identity.
  final outcomeTeams = event.outcomes
      .where((outcome) => !outcome.name.toLowerCase().contains('draw'))
      .map((outcome) => PolymarketTeam(
            name: outcome.name,
            logo: outcome.imageUrl,
          ))
      .toList();
  imageA ??= PolymarketEvent.logoFromTeams(outcomeTeams, teamA);
  imageB ??= PolymarketEvent.logoFromTeams(outcomeTeams, teamB);
  // If both teams resolved to the SAME image URL, it's the league /
  // tournament logo (not a per-team crest) — showing the same logo
  // twice with two different team names underneath looks broken.
  // Drop both so the team-initial placeholder takes over.
  if (imageA != null && imageA == imageB) {
    imageA = null;
    imageB = null;
  }
  return (teamA: teamA, teamB: teamB, imageA: imageA, imageB: imageB);
}

/// The teams of an event that arrived without them (the search path and
/// a position's event drop `teams`), read by slug; empty when the event
/// has its own or cannot be a match. Gated on `gameId != null` (an actual
/// match) so a crypto / politics / binary market never fires a team read
/// that can produce nothing — mirrors the card path.
List<PolymarketTeam> polyFetchedTeams(WidgetRef ref, PolymarketEvent event) {
  if (event.teams.isEmpty &&
      event.slug.isNotEmpty &&
      (event.gameId != null ||
          (event.isSportsCategory && event.looksLikeMatchup)) &&
      !event.isSyntheticBinary) {
    return ref.watch(polymarketEventTeamsProvider(event.slug)).valueOrNull ??
        const [];
  }
  return const [];
}

/// Detects the soccer Win/Draw/Lose shape and returns the three mapped
/// outcomes with their display names, or null. [teams] is the match
/// ([polySportsTeams]); null when the event is not one. Read by structure
/// ([gameThreeWaySides]): one draw market (however Gamma names it,
/// "Draw (A vs. B)") and two team markets, each matched to its side.
PolyWdlOutcomes? polyWdlOutcomes(
    PolymarketEvent event, PolySportsTeams? teams) {
  if (teams == null) return null;
  final outcomes = event.outcomes;
  final sides = gameThreeWaySides(
      teams.teamA, teams.teamB, [for (final o in outcomes) o.name]);
  if (sides == null) return null;
  return (
    teamA: outcomes[sides.a],
    draw: outcomes[sides.draw],
    teamB: outcomes[sides.b],
    teamAName: teams.teamA,
    teamBName: teams.teamB,
  );
}

/// The live WS update for this match, looked up by event slug first, then
/// by the stable numeric gameId join (`game:<id>`), then cricket's
/// `eventMetadata.gameId` (`meta:<id>`). Null when nothing is live.
SportsMatchUpdate? polyLiveMatchUpdate(WidgetRef ref, PolymarketEvent event) {
  if (event.isSyntheticBinary) return null;
  // select(): the provider holds EVERY live game on the platform, so
  // watching the whole map repainted the sheet on every unrelated score.
  return ref.watch(sportsLiveProvider.select((map) => sportsUpdateFor(map,
      slug: event.slug,
      gameId: event.gameId,
      metadataGameId: event.metadataGameId)));
}

/// A game that is currently in play. True when the live WS update says
/// `live` (and not `ended`), OR — before any WS tick — when Gamma seeded a
/// score/period on the event and it hasn't ended. Never true once ended.
bool polyGameIsLive(PolymarketEvent event, SportsMatchUpdate? ws) {
  if (ws != null) return ws.live && !ws.ended;
  if (event.ended) return false;
  // `isInPlay` also rules out the periods of games that are not running
  // ("NS", "FT", "VFT", "CAN").
  return event.isInPlay;
}

/// Whether [event] is over, for its chart (no LIVE pip, no live price on
/// the newest point) and its Stats ("Ended"): closed, switched off, ended,
/// or past its end date. Gamma's end date of a match is its scheduled
/// start, so a game still being played ([inPlay]) is past it from the
/// first minute and is not over.
bool polyEventIsOver(PolymarketEvent event,
    {required bool inPlay, DateTime? now}) {
  if (event.closed || !event.active || event.ended) return true;
  final end = event.endDate;
  if (end == null || !end.isBefore(now ?? DateTime.now())) return false;
  return !inPlay;
}

/// [raw] as the header shows it: an esports score's series segment, and
/// the two numbers in the order of the header's teams. The app holds
/// the score home first; when the title's first team is the away side
/// each pair is turned round. Null when there is no score.
String? polyHeaderScore(
  PolymarketEvent event,
  String raw,
  SportsMatchUpdate? ws, {
  required PolySportsTeams? sportsTeams,
  required List<PolymarketTeam> teams,
}) {
  if (raw.isEmpty) return null;
  final score = PolyLiveGame.seriesScore(raw);
  if (score.isEmpty) return null;
  final firstIsHome = gameSideIsHome(
    sportsTeams?.teamA,
    teams: teams,
    feedHome: ws?.homeTeam,
    feedAway: ws?.awayTeam,
  );
  return scoreInTitleOrder(score, firstIsHome: firstIsHome);
}

/// The scoreline of a game in play. Prefers the live WS score, falls back
/// to Gamma's seeded `event.score`.
String? polyLiveScoreText(
  PolymarketEvent event,
  SportsMatchUpdate? ws, {
  required PolySportsTeams? sportsTeams,
  required List<PolymarketTeam> teams,
}) {
  final raw = (ws?.score?.trim().isNotEmpty ?? false)
      ? ws!.score!.trim()
      : (event.score?.trim() ?? '');
  return polyHeaderScore(event, raw, ws,
      sportsTeams: sportsTeams, teams: teams);
}

/// The final score of a finished game, or null when nothing reliable
/// has it: the live feed's last state if this phone saw the game, else
/// the game's timeline (the Kute backend keeps ended games a day), else
/// Gamma's own `score` on the event. A cancelled or postponed game has
/// no final score.
String? polyFinalScoreText(
  PolymarketEvent event,
  SportsMatchUpdate? ws,
  PolyGameTimeline? timeline, {
  required PolySportsTeams? sportsTeams,
  required List<PolymarketTeam> teams,
}) {
  bool noResult(String? period) {
    final p = period?.trim().toUpperCase() ?? '';
    return p == 'CAN' || p == 'PST' || p == 'NS';
  }

  final last =
      (timeline?.events.isNotEmpty ?? false) ? timeline!.events.last : null;
  if (noResult(ws?.period) ||
      (ws == null && noResult(last?.period)) ||
      (ws == null && last == null && noResult(event.period))) {
    return null;
  }
  String? shown(String raw) =>
      polyHeaderScore(event, raw, ws, sportsTeams: sportsTeams, teams: teams);
  final wsScore = ws?.score?.trim() ?? '';
  if (wsScore.isNotEmpty) return shown(wsScore);
  final timelineScore = last?.score.trim() ?? '';
  if (timelineScore.isNotEmpty) return shown(timelineScore);
  return shown(event.score?.trim() ?? '');
}

/// The clock/status text (period + elapsed). Prefers the live WS,
/// falls back to Gamma's seeded period/elapsed.
String? polyLiveStatusText(PolymarketEvent event, SportsMatchUpdate? ws) {
  if (ws != null && ws.statusLine.isNotEmpty) return ws.statusLine;
  final parts = <String>[];
  final p = event.period?.trim();
  final el = event.elapsed?.trim();
  if (p != null && p.isNotEmpty) parts.add(p);
  if (el != null && el.isNotEmpty) parts.add(el);
  final s = parts.join(' ');
  return s.isEmpty ? null : s;
}

/// The abbreviation Gamma's teams give [name] ("Colts" -> "IND"), for the
/// NFL possession join; null when no team matches.
String? polyTeamAbbreviation(List<PolymarketTeam> teams, String name) {
  final n = name.trim().toLowerCase();
  for (final t in teams) {
    final names = [t.name, t.alias ?? '', t.abbreviation ?? '']
        .map((x) => x.trim().toLowerCase());
    if (names.contains(n) ||
        t.name.toLowerCase().endsWith(' $n') ||
        n.endsWith(' ${t.name.toLowerCase()}')) {
      return t.abbreviation;
    }
  }
  return null;
}

/// Where a match stands, as its header shows it.
typedef PolyGameHeaderData = ({
  /// The live sports feed's update for the game, when it has one.
  SportsMatchUpdate? ws,

  /// In play right now.
  bool live,

  /// Over (and not in play).
  bool ended,

  /// The live score while in play, the final score once over; null when
  /// there is none to show.
  String? scoreText,

  /// The clock or the feed's status while in play.
  String? statusText,

  /// The game in play (NFL possession); null otherwise.
  PolyLiveGame? game,

  /// When the game kicks off ([PolymarketEvent.kickoff]); null when
  /// unknown or not a match.
  DateTime? kickoff,

  /// When the game was seen to finish, once it is over.
  DateTime? finishedAt,
});

/// The state of [event]'s match for its header: watches the live sports
/// feed and the game's timeline, so call it from the build of the widget
/// that should repaint on a score. [sportsTeams] null (not a match) gives
/// a header with nothing live.
PolyGameHeaderData polyGameHeaderData(
  WidgetRef ref,
  BuildContext context,
  PolymarketEvent event, {
  required PolySportsTeams? sportsTeams,
  required List<PolymarketTeam> teams,
}) {
  // Live score wiring for the vs-header (only surfaces when the game is
  // actually in play; non-live games render the unchanged "vs" header).
  final ws = sportsTeams != null ? polyLiveMatchUpdate(ref, event) : null;
  final gameLive = sportsTeams != null && polyGameIsLive(event, ws);
  final liveScore = gameLive
      ? polyLiveScoreText(event, ws, sportsTeams: sportsTeams, teams: teams)
      : null;
  // A finished game keeps its final score where the live one was.
  final timelineId = sportsTeams == null
      ? null
      : gameTimelineId(
          gameId: event.gameId, metadataGameId: event.metadataGameId);
  final timeline = timelineId == null
      ? null
      : ref.watch(polyGameTimelineProvider(timelineId));
  final gameEnded = sportsTeams != null &&
      !gameLive &&
      ((ws?.ended ?? false) || (timeline?.ended ?? false) || event.ended);
  final finalScore = gameEnded
      ? polyFinalScoreText(event, ws, timeline,
          sportsTeams: sportsTeams, teams: teams)
      : null;
  final game = gameLive ? PolyLiveGame.of(event, ws) : null;
  final liveStatus = gameLive
      ? (polyLiveStatusText(event, ws) ?? game?.clockOrStatus(context))
      : null;
  final endedAtMs = timeline?.endedAtMs;
  final finishedAt = !gameEnded
      ? null
      : ws?.finishedAt ??
          event.finishedAt ??
          (endedAtMs == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(endedAtMs));
  return (
    ws: ws,
    live: gameLive,
    ended: gameEnded,
    scoreText: gameLive ? liveScore : finalScore,
    statusText: liveStatus,
    game: game,
    kickoff: sportsTeams == null ? null : event.kickoff,
    finishedAt: finishedAt,
  );
}

/// A match's two-team header — team logo + name on each side, and in the
/// centre the score while the game is played or once it is over, else the
/// plain "vs" with the kickoff ("Today 20:30") under it when it is known.
class PolyGameTeamsHeader extends StatelessWidget {
  final PolySportsTeams teams;

  /// The event's teams (for the NFL possession join).
  final List<PolymarketTeam> eventTeams;
  final bool live;
  final bool ended;
  final String? scoreText;
  final String? statusText;
  final PolyLiveGame? game;

  /// When the game kicks off, shown under the "vs" before it starts.
  final DateTime? kickoff;

  /// When the game finished, dated after "Final" when not today.
  final DateTime? finishedAt;

  const PolyGameTeamsHeader({
    super.key,
    required this.teams,
    this.eventTeams = const [],
    this.live = false,
    this.ended = false,
    this.scoreText,
    this.statusText,
    this.game,
    this.kickoff,
    this.finishedAt,
  });

  /// The header for [data] ([polyGameHeaderData]).
  PolyGameTeamsHeader.of(
    PolyGameHeaderData data, {
    super.key,
    required this.teams,
    this.eventTeams = const [],
  })  : live = data.live,
        ended = data.ended,
        scoreText = data.scoreText,
        statusText = data.statusText,
        game = data.game,
        kickoff = data.kickoff,
        finishedAt = data.finishedAt;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final game = this.game;
    Widget teamCol(String name, String? image) {
      // NFL possession: a small ball under the team that has it.
      final hasBall = live &&
          game != null &&
          (game.hasBall(polyTeamAbbreviation(eventTeams, name)) ||
              game.hasBall(name));
      return Expanded(
        child: Column(
          children: [
            image != null
                ? PolyCrestImage(
                    url: image,
                    size: 64.w,
                    radius: 14.r,
                    fit: BoxFit.contain,
                    fallback: _teamInitial(name),
                  )
                : _teamInitial(name),
            SizedBox(height: 10.h),
            Text(
              name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 15.sp,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                height: 1.2,
              ),
            ),
            if (hasBall) ...[
              SizedBox(height: 4.h),
              Icon(Icons.sports_football_rounded,
                  size: 14.sp,
                  color: c.textSecondary,
                  semanticLabel: context.l10n.polyLivePossession(name)),
            ],
          ],
        ),
      );
    }

    // Center column: the score where the "vs" pill sits, in the order the
    // header names the teams, while the game is in play (with its clock
    // under it as a plain caption) and once it is over ("Final");
    // otherwise the plain "vs" pill.
    final Widget center;
    if ((live || ended) && (scoreText?.isNotEmpty ?? false)) {
      center = Padding(
        padding: EdgeInsets.only(top: 8.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Scoreline — FittedBox so long set scores (tennis "6-3, 3-6")
            // scale down instead of overlapping the team columns.
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 84.w),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                // A goal pulses the number that changed.
                child: ScorePulseText(
                  identity: (teams.teamA, teams.teamB),
                  text: scoreText!,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 24.sp,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    height: 1.0,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              ended
                  ? polyFinalText(context.l10n, finishedAt, now: DateTime.now())
                  : (statusText?.isNotEmpty ?? false)
                      ? statusText!
                      : context.l10n.betLiveUpper,
              maxLines: 1,
              style: TextStyle(
                color: c.textTertiary,
                fontSize: 12.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    } else {
      final pill = Container(
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
        decoration: BoxDecoration(
          color: c.surfaceLight,
          borderRadius: BorderRadius.circular(8.r),
        ),
        child: Text(
          context.l10n.betVersus,
          style: TextStyle(
            color: c.textSecondary,
            fontSize: 12.sp,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      );
      // Under the "vs", in the clock's caption style: the clock (or
      // "LIVE") of a game in play that has no score yet, else when the
      // game kicks off. A game over without a score keeps the plain "vs".
      Widget caption(String text) => ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 120.w),
            child: Text(
              text,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.textTertiary,
                fontSize: 12.sp,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          );
      final kickoff = this.kickoff;
      final Widget? under = live
          ? caption((statusText?.isNotEmpty ?? false)
              ? statusText!
              : context.l10n.betLiveUpper)
          : (ended || kickoff == null)
              ? null
              // Its own Consumer: the countdown refreshes each minute
              // while the header is on screen, and repaints only itself.
              : Consumer(builder: (context, ref, _) {
                  ref.watch(polyMinuteTickProvider);
                  return caption(polyKickoffText(context.l10n, kickoff,
                      now: DateTime.now()));
                });
      center = Padding(
        padding: EdgeInsets.only(top: 22.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            pill,
            if (under != null) ...[SizedBox(height: 6.h), under],
          ],
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        teamCol(teams.teamA, teams.imageA),
        center,
        teamCol(teams.teamB, teams.imageB),
      ],
    );
  }

  Widget _teamInitial(String name) {
    // Multi-word initials so two C-teams (e.g. "Cuiabá EC" and
    // "CR Brasil") don't both collapse to the same "C" placeholder.
    // Strip the common stop-words first ("the", "fc", "ec", etc.)
    // then take the first letter of up to 3 remaining words.
    final clean = name.trim();
    if (clean.isEmpty) {
      return _initialBubble('?', hueSeed: 0);
    }
    const stopWords = {'the', 'fc', 'ec', 'cf', 'sc', 'sk', 'vs', 'vs.'};
    final words = clean
        .split(RegExp(r'[\s\-:/]+'))
        .where((w) => w.isNotEmpty)
        .where((w) => !stopWords.contains(w.toLowerCase()))
        .toList();
    String initials;
    if (words.isEmpty) {
      initials = clean[0].toUpperCase();
    } else if (words.length == 1 && words.first.length >= 2) {
      // Single-word team — use first 2 letters ("Tunisia" → "TU").
      initials = words.first.substring(0, 2).toUpperCase();
    } else {
      initials = words.take(3).map((w) => w[0].toUpperCase()).join();
    }
    // Hue derived from the full name so two same-letter teams render
    // with distinct colors even when initials collide post-stripping.
    final hue = (clean.hashCode % 360).abs();
    return _initialBubble(initials, hueSeed: hue);
  }

  Widget _initialBubble(String text, {required int hueSeed}) {
    final bgColor =
        HSLColor.fromAHSL(1.0, hueSeed.toDouble(), 0.55, 0.45).toColor();
    return Container(
      width: 64.w,
      height: 64.w,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14.r),
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Colors.white,
          fontSize: text.length >= 3 ? 18.sp : 24.sp,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
      ),
    );
  }
}
