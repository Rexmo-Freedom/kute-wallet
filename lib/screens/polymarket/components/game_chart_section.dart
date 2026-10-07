// The odds chart of a match, with the game on it: a marker at each event
// of the game's timeline (a goal, a touchdown, a set or a map won, a period
// change), so the move in the odds can be read against what happened.
//
// Under the chart sits the momentum strip (which side gained win chance,
// bucket by bucket, with the pressure label and an esports series' maps):
// see momentum_strip.dart. It needs the two sides' win-chance tokens: the
// three-way market's team tokens, else the event's moneyline, else a
// two-outcome event's own pair.
//
// The events are what the Kute backend and this phone saw on Polymarket's
// live sports feed (polyGameTimelineProvider). Nothing is inferred from
// prices: with no timeline there are simply no markers. Until the feed has
// sent its first word about the game, its teams, score and period come
// from the backend's timeline answer.
//
// Analytics: live_event_marker_tapped (sport, league, kind of marker; no
// ids).

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_game_lines_provider.dart';
import 'package:kute/providers/polymarket_game_momentum_provider.dart';
import 'package:kute/providers/polymarket_game_timeline_provider.dart';
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/screens/polymarket/components/game_header.dart';
import 'package:kute/screens/polymarket/components/game_markers.dart';
import 'package:kute/screens/polymarket/components/market_chart.dart';
import 'package:kute/screens/polymarket/components/momentum_strip.dart';
import 'package:kute/services/polymarket/live_game/game_esports.dart';
import 'package:kute/services/polymarket/live_game/game_momentum.dart';
import 'package:kute/services/polymarket/live_game/game_score.dart';
import 'package:kute/services/polymarket/live_game/game_sides.dart';
import 'package:kute/services/polymarket/live_game/game_timeline.dart';
import 'package:kute/services/polymarket/live_game/local_game_events.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/venue_analytics.dart';
import 'package:kute/theme/app_theme.dart';

/// The colours a game's sides take when the chart does not give them one:
/// the first side, the second side, and the draw of a three-way market.
const kGameSideColors = [
  Color(0xFF4FC3F7),
  Color(0xFFCE93D8),
  Color(0xFFFFB74D),
];

/// [chart] with the game's event markers on it and the momentum graph
/// under it when [event] is a match, [chart] alone otherwise. The market
/// sheet and the open-position screen both draw a game's chart through
/// this, so the two read the same. [sportsTeams] is the match as its
/// header names it ([polySportsTeams]); [teams] the event's teams (its own
/// or the ones read by slug).
Widget polyGameChart({
  required PolymarketEvent event,
  required MarketChart chart,
  required List<PolymarketTeam> teams,
  required PolySportsTeams? sportsTeams,
  String source = 'unknown',
}) {
  if (event.isSyntheticBinary ||
      (event.gameId == null && event.metadataGameId == null)) {
    return chart;
  }
  final wdl = polyWdlOutcomes(event, sportsTeams);
  return PolyGameChartSection(
    event: event,
    chart: chart,
    teams: teams,
    teamA: sportsTeams?.teamA,
    teamB: sportsTeams?.teamB,
    winTokenA: wdl?.teamA.tokenId,
    winTokenB: wdl?.teamB.tokenId,
    source: source,
  );
}

/// The colour of each of a game's two sides, one per team wherever the
/// game is drawn (the market sheet's chart, momentum graph and board, the
/// open-position screen): keyed by the order the event's [title] names
/// its teams, never by the odds or by which lines a chart happens to
/// draw. The title's first team takes the first of [kGameSideColors], its
/// second team the second (the draw of a three-way market the third).
/// [nameA] and [nameB] are the two sides as the caller has them, in the
/// caller's order; a side the title does not name takes the colour the
/// other one leaves. Never the green and red of up and down.
(Color, Color) gameSideColors(String title, String? nameA, String? nameB) {
  int? team(String? name) {
    final i = gameSideIndex(title, name);
    return i == 0 || i == 1 ? i : null;
  }

  var a = team(nameA), b = team(nameB);
  if (a == null && b == null || a == b) {
    a = 0;
    b = 1;
  } else {
    a ??= 1 - b!;
    b ??= 1 - a;
  }
  return (kGameSideColors[a], kGameSideColors[b]);
}

/// The colour of one outcome's line on its game's chart, by the same rule
/// ([gameSideColors]): its team's colour when [tokenId] is a side's win
/// token, the third colour for a three-way market's draw, and null for
/// anything else (a spread, a total, an event that is not a game), which
/// keeps the chart's own colour.
///
/// The sides are found as the chart section finds them: a three-way
/// market's team tokens, else the event's [moneyline], else a two-outcome
/// event's own pair.
Color? gameLineColor(
  PolymarketEvent event,
  PolySportsTeams? sportsTeams,
  PolyGameLine? moneyline,
  String tokenId,
) {
  if (event.isSyntheticBinary ||
      (event.gameId == null && event.metadataGameId == null)) {
    return null;
  }
  bool yesNo(String s) {
    final v = s.trim().toLowerCase();
    return v == 'yes' || v == 'no';
  }

  final wdl = polyWdlOutcomes(event, sportsTeams);
  if (wdl != null) {
    final sides =
        gameSideColors(event.title, wdl.teamAName, wdl.teamBName);
    if (wdl.teamA.tokenId == tokenId) return sides.$1;
    if (wdl.teamB.tokenId == tokenId) return sides.$2;
    if (wdl.draw.tokenId == tokenId) return kGameSideColors[2];
    return null;
  }
  if (moneyline != null &&
      (moneyline.tokenA?.isNotEmpty ?? false) &&
      !yesNo(moneyline.sideA) &&
      !yesNo(moneyline.sideB)) {
    final sides =
        gameSideColors(event.title, moneyline.sideA, moneyline.sideB);
    if (moneyline.tokenA == tokenId) return sides.$1;
    if (moneyline.tokenB == tokenId) return sides.$2;
  }
  final outcomes = event.outcomes;
  if (outcomes.length == 2 &&
      !yesNo(outcomes[0].name) &&
      !yesNo(outcomes[1].name)) {
    final sides =
        gameSideColors(event.title, outcomes[0].name, outcomes[1].name);
    if (outcomes[0].tokenId == tokenId) return sides.$1;
    if (outcomes[1].tokenId == tokenId) return sides.$2;
  }
  return null;
}

class PolyGameChartSection extends ConsumerStatefulWidget {
  final PolymarketEvent event;
  final MarketChart chart;

  /// The event's teams, with their home / away ordering.
  final List<PolymarketTeam> teams;

  /// The two sides as the title names them ("A vs B").
  final String? teamA;
  final String? teamB;

  /// Three-way markets (win / draw / win): each team's own win token.
  final String? winTokenA;
  final String? winTokenB;

  /// Where the sheet was opened from (analytics).
  final String source;

  const PolyGameChartSection({
    super.key,
    required this.event,
    required this.chart,
    this.teams = const [],
    this.teamA,
    this.teamB,
    this.winTokenA,
    this.winTokenB,
    this.source = 'unknown',
  });

  @override
  ConsumerState<PolyGameChartSection> createState() =>
      _PolyGameChartSectionState();
}

class _PolyGameChartSectionState extends ConsumerState<PolyGameChartSection> {
  /// Chart markers, rebuilt only when the timeline (or what colours and
  /// words it is drawn in) changes: the chart memoizes on this list.
  (Object, GameSport, String, Color, Color, bool?, List<MarketChartMarker>)?
      _markerMemo;

  /// Strip notches, memoized like the chart markers.
  (Object, List<MomentumNotch>)? _notchMemo;

  /// When the sheet opened: the stand-in end of a finished game with no
  /// end time on record, fixed so the strip's key does not move.
  late final int _openedMs = DateTime.now().millisecondsSinceEpoch;

  PolymarketEvent get event => widget.event;

  static bool _yesNo(String s) {
    final v = s.trim().toLowerCase();
    return v == 'yes' || v == 'no';
  }

  /// The two sides' win-chance tokens and names, or null when the event
  /// has no two-sided winner market to read momentum from.
  ({String tokenA, String? tokenB, String nameA, String nameB})? _sides() {
    final a = widget.winTokenA, b = widget.winTokenB;
    if (a != null && a.isNotEmpty && b != null && b.isNotEmpty) {
      return (
        tokenA: a,
        tokenB: b,
        nameA: widget.teamA ?? '',
        nameB: widget.teamB ?? '',
      );
    }
    final ml = polyGameLinesFor(ref, event).winner;
    if (ml != null &&
        (ml.tokenA?.isNotEmpty ?? false) &&
        !_yesNo(ml.sideA) &&
        !_yesNo(ml.sideB)) {
      return (
        tokenA: ml.tokenA!,
        tokenB: ml.tokenB,
        nameA: ml.sideA,
        nameB: ml.sideB,
      );
    }
    final outcomes = event.outcomes;
    if (outcomes.length == 2 &&
        !_yesNo(outcomes[0].name) &&
        !_yesNo(outcomes[1].name) &&
        (outcomes[0].tokenId?.isNotEmpty ?? false)) {
      return (
        tokenA: outcomes[0].tokenId!,
        tokenB: outcomes[1].tokenId,
        nameA: outcomes[0].name,
        nameB: outcomes[1].name,
      );
    }
    return null;
  }

  Map<String, Object> _analytics(GameSport sport, String? league) => {
        'sport': sport.key,
        if (league != null && league.isNotEmpty) 'league': league,
        if (event.category.isNotEmpty) 'category': event.category.toLowerCase(),
        ...VenueAnalytics.pmKindParams([event.id],
            fallbackCategory: event.category),
      };

  @override
  Widget build(BuildContext context) {
    final id = gameTimelineId(
        gameId: event.gameId, metadataGameId: event.metadataGameId);
    if (id == null) return widget.chart;
    final timeline = ref.watch(polyGameTimelineProvider(id));
    // The game as the live feed has it; until the feed has spoken about it
    // (its first message can take twenty seconds), as the backend's
    // timeline answer last saw it.
    final ws = timeline.liveOr(ref.watch(sportsLiveProvider.select((map) =>
        sportsUpdateFor(map,
            slug: event.slug,
            gameId: event.gameId,
            metadataGameId: event.metadataGameId))));
    final live = ws != null ? ws.isInPlay : event.isInPlay;
    final ended =
        timeline.ended || (ws?.ended ?? false) || event.ended || event.closed;
    if (!live && !ended && timeline.events.isEmpty) return widget.chart;

    // The game's own window: kickoff to now, or to its end once finished.
    // Gamma's event start date is when the market opened, so the kickoff
    // comes from the feed, Gamma's game start or the first sighting.
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final knownEndMs = live
        ? null
        : timeline.endedAtMs ??
            ws?.finishedAt?.millisecondsSinceEpoch ??
            event.finishedAt?.millisecondsSinceEpoch;
    final startMs = gameKickoffMs(
      // The feed's start time, else the backend's from its timeline
      // answer (the same start: the momentum read keeps its key when the
      // feed's arrives).
      feedStartMs: (ws?.gameStartTime ?? timeline.feed?.gameStartTime)
          ?.millisecondsSinceEpoch,
      gammaStartMs: event.gameStart?.millisecondsSinceEpoch,
      firstSeenMs: timeline.events.isNotEmpty
          ? timeline.events.first.tMs
          : timeline.knownSinceMs,
      marketStartMs: event.startDate?.millisecondsSinceEpoch,
      untilMs: knownEndMs ?? math.min(nowMs, _openedMs),
    );
    if (startMs == null) return widget.chart;
    final start = DateTime.fromMillisecondsSinceEpoch(startMs);
    // A finished game with no end time on record: one stand-in, fixed for
    // the life of the sheet.
    final endMs = live
        ? null
        : knownEndMs ??
            math.min(
                _openedMs, startMs + const Duration(hours: 4).inMilliseconds);

    final league = ws?.leagueAbbreviation ?? timeline.league;
    final sport = gameSportOf(
      league: league,
      score: ws?.score ??
          event.score ??
          (timeline.events.isEmpty ? null : timeline.events.last.score),
      period: ws?.period ?? event.period,
      cricket: event.gameId == null,
    );
    PolymarketTeam? team(String ordering) {
      for (final t in widget.teams) {
        if (t.ordering == ordering) return t;
      }
      return null;
    }

    final homeName = ws?.homeTeam ?? team('home')?.name;
    final awayName = ws?.awayTeam ?? team('away')?.name;
    final sides = _sides();
    final aIsHome = gameSideIsHome(
        sides != null && sides.nameA.isNotEmpty ? sides.nameA : widget.teamA,
        teams: widget.teams,
        feedHome: ws?.homeTeam,
        feedAway: ws?.awayTeam);
    final sideColors = gameSideColors(
        event.title,
        sides != null && sides.nameA.isNotEmpty ? sides.nameA : widget.teamA,
        sides != null && sides.nameB.isNotEmpty ? sides.nameB : widget.teamB);
    final markers = _markersFor(
      context,
      timeline.events,
      sport,
      colorA: sideColors.$1,
      colorB: sideColors.$2,
      aIsHome: aIsHome,
      home: homeName,
      away: awayName,
    );

    final chart = widget.chart.withGame(
      markers: markers,
      gameStart: start,
      gameEnd: endMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(endMs),
      onMarkerShown: (first, count, via) {
        TrackingService.track('live_event_marker_tapped', params: {
          ..._analytics(sport, league),
          'marker_kind': first.kind,
          'cluster_size': count,
          'via': via,
          'is_live': live,
          'timeline_source': timeline.source,
        });
      },
    );
    if (sides == null) return chart;

    // The price history API serves fine-grained windows 15 days back.
    if (endMs != null &&
        nowMs - endMs > const Duration(days: 14).inMilliseconds) {
      return chart;
    }
    // The totals line only feeds the pressure signal: the strip is drawn
    // from the sides' history at once, and the Over token is handed to it
    // when it lands.
    final overToken = live
        ? ref.watch(polyGameOverTokenProvider(event.slug)).valueOrNull
        : null;
    final PolyMomentumKey key = (
      gameId: id,
      tokenA: sides.tokenA,
      tokenB: sides.tokenB,
      startMs: startMs,
      endMs: endMs,
      axisMs: momentumAxisMs(sport),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        chart,
        PolyMomentumStrip(
          momentumKey: key,
          // Kept out of the key: either changing never re-reads the
          // sides' history or shows the strip loading again.
          aIsHome: aIsHome,
          overToken: overToken,
          nameA: sides.nameA.isNotEmpty ? sides.nameA : (widget.teamA ?? ''),
          nameB: sides.nameB.isNotEmpty ? sides.nameB : (widget.teamB ?? ''),
          colorA: sideColors.$1,
          colorB: sideColors.$2,
          notches: _notchesFor(timeline.events, sport, sideColors, aIsHome),
          // A football match is read by its minutes, a game in quarters
          // or periods from its first one.
          startLabel: momentumAxisStartLabel(sport),
          endLabel: sport == GameSport.soccer ? "90'" : null,
          series: sport == GameSport.esports
              ? esportsSeriesFrom(
                  timeline.events,
                  score: ws?.score ?? event.score,
                  period: ws?.period ?? event.period,
                  ended: ended && !live,
                )
              : null,
          homeName: homeName,
          awayName: awayName,
          analytics: {
            ..._analytics(sport, league),
            'timeline_source': timeline.source,
          },
        ),
      ],
    );
  }

  List<MomentumNotch> _notchesFor(List<GameEvent> events, GameSport sport,
      (Color, Color) colors, bool? aIsHome) {
    final memo = _notchMemo;
    final l10n = context.l10n;
    final memoKey = (
      events,
      sport,
      colors,
      aIsHome,
      Localizations.localeOf(context).toLanguageTag(),
    );
    if (memo != null && memo.$1 == memoKey) return memo.$2;
    final neutral = context.colors.textSecondary;
    // A score is a dot on the centre line; a period change (half-time, a
    // quarter) and a map starting are ticks across the plot where the
    // strip has room to name them: by the period that starts there ("Q2",
    // "HT", "Q3"; never "End Q1", see [momentumPeriodLabel]) or the map's
    // number.
    // Baseball changes period six times an inning ("Top 2nd", "Mid 2nd",
    // "Bot 2nd"…): only an inning's first one is named, by its number.
    int? inning;
    String? periodLabel(String period) {
      if (sport != GameSport.baseball) {
        return momentumPeriodLabel(sport, period);
      }
      final n = baseballInning(period);
      if (n == null || n == inning) return null;
      inning = n;
      return '$n';
    }

    final drawn = <MomentumNotch>[
      for (final m in gameMarkersFrom(events, sport))
        if (m.kind.isScoring ||
            m.kind == GameMarkerKind.period ||
            m.kind == GameMarkerKind.mapStart)
          (
            tMs: m.tMs,
            color: m.side == 0 || aIsHome == null
                ? neutral
                : ((m.side > 0) == aIsHome ? colors.$1 : colors.$2),
            divider: m.kind == GameMarkerKind.period ||
                m.kind == GameMarkerKind.mapStart ||
                m.kind == GameMarkerKind.setWon ||
                m.kind == GameMarkerKind.mapWon,
            label: m.kind == GameMarkerKind.period
                ? periodLabel(m.period)
                : m.kind == GameMarkerKind.mapStart && m.number != null
                    ? l10n.polyMarkerMap('${m.number}')
                    : null,
          ),
    ];
    // A name once, where its period starts.
    final names = momentumLabelsOnce([for (final n in drawn) n.label]);
    final out = <MomentumNotch>[
      for (var i = 0; i < drawn.length; i++)
        (
          tMs: drawn[i].tMs,
          color: drawn[i].color,
          divider: drawn[i].divider,
          label: names[i],
        ),
    ];
    _notchMemo = (memoKey, out);
    return out;
  }

  List<MarketChartMarker> _markersFor(
    BuildContext context,
    List<GameEvent> events,
    GameSport sport, {
    required Color colorA,
    required Color colorB,
    required bool? aIsHome,
    String? home,
    String? away,
  }) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final memo = _markerMemo;
    if (memo != null &&
        identical(memo.$1, events) &&
        memo.$2 == sport &&
        memo.$3 == '$locale|$home|$away' &&
        memo.$4 == colorA &&
        memo.$5 == colorB &&
        memo.$6 == aIsHome) {
      return memo.$7;
    }
    final l10n = context.l10n;
    final neutral = context.colors.textSecondary;
    final out = <MarketChartMarker>[
      for (final m in gameMarkersFrom(events, sport))
        MarketChartMarker(
          tMs: m.tMs,
          label: gameMarkerLabel(l10n, m, sport, home: home, away: away),
          color: m.side == 0 || aIsHome == null
              ? neutral
              : ((m.side > 0) == aIsHome ? colorA : colorB),
          minor: !m.kind.isScoring && m.kind != GameMarkerKind.finalScore,
          kind: m.kind.key,
        ),
    ];
    _markerMemo =
        (events, sport, '$locale|$home|$away', colorA, colorB, aIsHome, out);
    return out;
  }
}
