// lib/services/polymarket/live_game/game_esports.dart
//
// An esports series map by map, from the game's timeline. The feed writes
// the score as "mapScore|seriesScore|BoN" and the period as "4/5" (map 4
// of 5): a map is won when the series score goes up.
//
// Only what was seen is listed. Maps that finished before anyone was
// watching are known as a count ("earlier maps 1–2"), not in which order
// they went. A finished map's own score is not shown: the feed resets the
// map score in the same message that moves the series, so the last one
// seen is a round or a kill short.
//
// Pure Dart; unit tested in
// test/services/polymarket/live_game_momentum_test.dart.

import 'package:kute/services/polymarket/live_game/game_score.dart';
import 'package:kute/services/polymarket/live_game/game_timeline.dart';

class EsportsMap {
  final int number;

  /// 1 the home side won it, -1 the away side; null while it is played or
  /// when the winner is not known.
  final int? winner;
  final bool live;

  /// The score inside a map in play (rounds or kills).
  final int? mapHome;
  final int? mapAway;

  /// When the map was won (epoch ms).
  final int? wonAtMs;

  const EsportsMap({
    required this.number,
    this.winner,
    this.live = false,
    this.mapHome,
    this.mapAway,
    this.wonAtMs,
  });
}

class EsportsSeries {
  /// Maps each side had already won when the timeline starts.
  final int earlierHome;
  final int earlierAway;
  final List<EsportsMap> maps;
  final int? bestOf;

  const EsportsSeries({
    this.earlierHome = 0,
    this.earlierAway = 0,
    this.maps = const [],
    this.bestOf,
  });

  bool get isEmpty => maps.isEmpty && earlierHome + earlierAway == 0;
}

/// The series as far as it is known: [events] oldest first, and the feed's
/// current [score] and [period] for the map in play.
EsportsSeries esportsSeriesFrom(
  List<GameEvent> events, {
  String? score,
  String? period,
  bool ended = false,
}) {
  final current = GameScore.parse(
      score ?? (events.isEmpty ? null : events.last.score), GameSport.esports);
  final first = events.isEmpty
      ? current
      : GameScore.parse(events.first.scoreBefore, GameSport.esports);
  final earlierHome = first.home ?? 0, earlierAway = first.away ?? 0;
  final maps = <EsportsMap>[];
  for (final m in gameMarkersFrom(events, GameSport.esports)) {
    if (m.kind != GameMarkerKind.mapWon || m.number == null) continue;
    maps.add(EsportsMap(
      number: m.number!,
      winner: m.side == 0 ? null : m.side,
      wonAtMs: m.tMs,
    ));
  }
  if (!ended && current.hasPair) {
    final played = current.home! + current.away!;
    final live = esportsMapNumber(period) ?? played + 1;
    final decided = current.bestOf != null &&
        (current.home! > current.bestOf! ~/ 2 ||
            current.away! > current.bestOf! ~/ 2);
    if (live > played && !decided) {
      maps.add(EsportsMap(
        number: live,
        live: true,
        mapHome: current.mapHome,
        mapAway: current.mapAway,
      ));
    }
  }
  return EsportsSeries(
    earlierHome: earlierHome,
    earlierAway: earlierAway,
    maps: maps,
    bestOf: current.bestOf,
  );
}
