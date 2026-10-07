// A game in play, as the cards and the game centre show it: the score in
// the order the market's title names its teams, the period and clock where
// the sport has them, the feed's status, and NFL possession. Built from the
// live sports WebSocket when it has the game and from Gamma's own
// score/period/elapsed until it does. A finished game keeps its final
// score.

import 'package:flutter/material.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/services/polymarket/live_game/game_sides.dart';
import 'package:kute/services/sports_websocket_service.dart';

class PolyLiveGame {
  /// Home and away names as the feed or Gamma's teams give them
  /// (abbreviations preferred); null when neither carries teams (cricket).
  final String? home;
  final String? away;

  /// The scoreline, home first as the app holds it: "7-3", "6-3, 2-1",
  /// or an esports series score.
  final String score;

  /// "Q2 08:14", "2H 67'", "S2" — period and clock where the sport has them.
  final String clock;

  /// The period alone, as the feed writes it ("Q2", "S2", "4/5"); it tells
  /// a tennis set in play from a plain score.
  final String? period;

  /// The feed's status when there is no period ("Halftime", "running").
  final String? status;

  /// NFL: the abbreviation of the team with the ball.
  final String? possession;

  /// Whether the first team the market's title names is the home side;
  /// null when the title is not a match or nothing says.
  final bool? firstIsHome;

  /// The game is over: [score] is the final score and there is no clock.
  final bool finished;

  const PolyLiveGame({
    this.home,
    this.away,
    required this.score,
    this.clock = '',
    this.period,
    this.status,
    this.possession,
    this.firstIsHome,
    this.finished = false,
  });

  /// The game for [event], from the live update [ws] when there is one and
  /// from Gamma's seed otherwise: in play, or finished with a final score.
  /// Null before kickoff, and for a game that was called off.
  static PolyLiveGame? of(PolymarketEvent event, SportsMatchUpdate? ws) {
    final firstIsHome = titleFirstIsHome(event.title,
        teams: event.teams, feedHome: ws?.homeTeam, feedAway: ws?.awayTeam);
    if (ws != null && ws.isInPlay) {
      return PolyLiveGame(
        home: ws.homeTeam ?? _team(event, 'home'),
        away: ws.awayTeam ?? _team(event, 'away'),
        score: seriesScore(ws.score ?? event.score ?? ''),
        clock: _clock(ws.period, ws.elapsed),
        period: ws.period,
        status: ws.status,
        possession: ws.turn,
        firstIsHome: firstIsHome,
      );
    }
    if (ws == null && event.isInPlay) {
      return PolyLiveGame(
        home: _team(event, 'home'),
        away: _team(event, 'away'),
        score: seriesScore(event.score ?? ''),
        clock: _clock(event.period, event.elapsed),
        period: event.period,
        firstIsHome: firstIsHome,
      );
    }
    // Over: the final score, when the feed or Gamma still has one.
    final ended = ws?.ended ?? event.ended;
    final period = (ws?.period ?? event.period)?.trim().toUpperCase() ?? '';
    if (!ended || period == 'CAN' || period == 'PST' || period == 'NS') {
      return null;
    }
    final score = seriesScore(
        (ws?.score?.trim().isNotEmpty ?? false) ? ws!.score! : event.score ?? '');
    if (!scoreHasPair(score)) return null;
    return PolyLiveGame(
      home: ws?.homeTeam ?? _team(event, 'home'),
      away: ws?.awayTeam ?? _team(event, 'away'),
      score: score,
      firstIsHome: firstIsHome,
      finished: true,
    );
  }

  /// Esports pack the score as "mapScore|seriesScore|bestOf"; the series
  /// segment is the one that matters for the match. Others pass through.
  static String seriesScore(String raw) {
    final s = raw.trim();
    if (!s.contains('|')) return s;
    final parts = s.split('|');
    if (parts.length >= 2 && parts[1].trim().isNotEmpty) return parts[1].trim();
    return parts.first.trim();
  }

  static String? _team(PolymarketEvent event, String ordering) {
    for (final t in event.teams) {
      if (t.ordering == ordering) {
        final abbr = t.abbreviation?.trim();
        if (abbr != null && abbr.isNotEmpty) return abbr.toUpperCase();
        return t.name;
      }
    }
    return null;
  }

  /// Period and clock on one line. An esports period is "map/maps"
  /// ("4/5"): kept apart so the line can say "Map 4".
  static String _clock(String? period, String? elapsed) => [
        if (period != null && period.trim().isNotEmpty) period.trim(),
        if (elapsed != null && elapsed.trim().isNotEmpty) elapsed.trim(),
      ].join(' ');

  /// The score in the order the title names the teams ("0 – 3"); empty
  /// when the feed's score is not a pair of numbers.
  String get titleScore =>
      scoreHasPair(score) ? scoreInTitleOrder(score, firstIsHome: firstIsHome) : '';

  /// Whether [team] (a name or abbreviation) has the ball.
  bool hasBall(String? team) {
    final p = possession?.trim().toLowerCase();
    final t = team?.trim().toLowerCase();
    if (p == null || p.isEmpty || t == null || t.isEmpty) return false;
    return p == t || t.startsWith('$p ') || t.endsWith(' $p');
  }

  /// The clock when there is one ("Map 4" for an esports "4/5"), else a
  /// readable status. Null for a finished game.
  String? clockOrStatus(BuildContext context) {
    if (finished) return null;
    if (clock.isNotEmpty) {
      final map = RegExp(r'^(\d+)/\d+$').firstMatch(clock);
      return map == null ? clock : context.l10n.polyMarkerMap(map[1]!);
    }
    final s = status?.trim();
    if (s == null || s.isEmpty || s.toLowerCase() == 'running') return null;
    return s;
  }
}
