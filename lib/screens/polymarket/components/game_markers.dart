// The words on a game's event markers ("Goal 38' 1–0", "Set 2 6–3",
// "Map 3 to Astralis"), in the user's language. Shared by the chart's
// markers and the match moments.

import 'package:kute/l10n/l10n.dart';
import 'package:kute/services/polymarket/live_game/game_score.dart';
import 'package:kute/services/polymarket/live_game/game_timeline.dart';

/// The marker's name alone: "Goal", "TD", "Set 2", "Half-time".
/// [home] and [away] name the sides where the marker says who (a map won).
String gameMarkerTitle(
  AppLocalizations l10n,
  GameMarker m,
  GameSport sport, {
  String? home,
  String? away,
}) {
  final n = '${m.number ?? ''}';
  switch (m.kind) {
    case GameMarkerKind.goal:
      return l10n.polyMarkerGoal;
    case GameMarkerKind.touchdown:
      return l10n.polyMarkerTouchdown;
    case GameMarkerKind.fieldGoal:
      return l10n.polyMarkerFieldGoal;
    case GameMarkerKind.score:
      return l10n.polyMarkerScore;
    case GameMarkerKind.correction:
      return l10n.polyMarkerCorrection;
    case GameMarkerKind.finalScore:
      return sport == GameSport.soccer
          ? l10n.polyMarkerFullTime
          : l10n.polyMarkerFinal;
    case GameMarkerKind.setWon:
      return l10n.polyMarkerSet(n);
    case GameMarkerKind.mapStart:
      return l10n.polyMarkerMap(n);
    case GameMarkerKind.mapWon:
      final team = m.side > 0
          ? home
          : m.side < 0
              ? away
              : null;
      return team == null || team.isEmpty
          ? l10n.polyMarkerMapWon(n)
          : l10n.polyMarkerMapWonBy(n, team);
    case GameMarkerKind.period:
      return _periodName(l10n, m.period, sport);
  }
}

String _periodName(AppLocalizations l10n, String period, GameSport sport) {
  final p = period.trim();
  final set = tennisSetNumber(p);
  if (set != null) return l10n.polyMarkerSet('$set');
  if (sport == GameSport.soccer) {
    switch (p.toUpperCase()) {
      case 'HT':
        return l10n.polyMarkerHalfTime;
      case '2H':
        return l10n.polyMarkerSecondHalf;
      case 'FT':
        return l10n.polyMarkerFullTime;
    }
  }
  return p;
}

/// The whole marker: its name, the game clock and the score it left,
/// "Goal 38' 1–0". A change seen only after the feed had been away says
/// its time is approximate.
String gameMarkerLabel(
  AppLocalizations l10n,
  GameMarker m,
  GameSport sport, {
  String? home,
  String? away,
}) {
  final label = [
    gameMarkerTitle(l10n, m, sport, home: home, away: away),
    if (m.clock.isNotEmpty) m.clock,
    if (m.scoreText.isNotEmpty) m.scoreText,
  ].join(' ');
  return m.approx ? l10n.polyMarkerApprox(label) : label;
}
