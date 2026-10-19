// lib/screens/shared/money_journey_plan.dart
//
// The money journey's map, laid out from a money step graph (founder, 19
// October 2026: the step list becomes a journey, Sal the hero): where the
// money starts (the source STATIONS, left), where it goes (the
// destination, right), the places it passes through (serial stations in
// between), the ROADS between them (one per leg, with a WAYPOINT per
// sub-leg: HyperCore → Circle → Arbitrum → Bitcoin), and the CHECKPOINTS
// at the destination (the venue's readiness sub-steps, the order, the
// arrival), listed under the map. Pure: a [MoneyJourneyPlan] is built
// from the lines every surface already makes ([MoneyStepLine]) and, when
// the surface has it, the graph itself; the view draws it.

import 'package:flutter/foundation.dart';
import 'package:kute/services/one_balance/money_steps.dart';

/// One rendered line: its words, its state, and whether it is a
/// sub-step (indented under its stage, or a sub-leg of its leg).
/// [hop] names the place a sub-leg arrives at, as a waypoint on the map
/// ("Circle", "Arbitrum"); [amount] is the sub-leg's formatted amount,
/// shown beside the waypoint; [brief] the short words the status line
/// says while it runs ("Circle → Arbitrum").
@immutable
class MoneyStepLine {
  const MoneyStepLine(this.text, this.status,
      {this.sub = false, this.id, this.hop, this.amount, this.brief});
  final String text;
  final MoneyStepStatus status;
  final bool sub;
  final String? id;
  final String? hop;
  final String? amount;
  final String? brief;
}

/// A station on the map: a balance (its mark and name), or, for a send,
/// the outside world ([place] null; [label] names it when known).
@immutable
class JourneyStation {
  const JourneyStation({
    required this.id,
    required this.place,
    required this.column,
    required this.row,
    required this.rows,
    this.label,
  });

  final String id;
  final MoneyPlace? place;
  final String? label;

  /// Left to right.
  final int column;

  /// Top to bottom within the column, of [rows] there.
  final int row;
  final int rows;
}

/// A waypoint on a road: the end of one sub-leg, with its words.
@immutable
class JourneyWaypoint {
  const JourneyWaypoint({required this.line, required this.label, this.amount});

  /// The sub-leg's line index.
  final int line;
  final String label;
  final String? amount;
}

/// A road from one station to another: a leg's line, its segments (the
/// sub-legs' lines, or the leg's own line when it has none; for the
/// stage road of a list without a graph, every stage line), the
/// waypoints between the segments, and the dollars it carries.
@immutable
class JourneyRoad {
  const JourneyRoad({
    required this.line,
    required this.from,
    required this.to,
    required this.segments,
    required this.waypoints,
    required this.usd,
  });

  /// The leg's line index; -1 for the stage road (no leg line).
  final int line;
  final int from;
  final int to;
  final List<int> segments;
  final List<JourneyWaypoint> waypoints;
  final double usd;
}

/// The journey, laid out.
@immutable
class MoneyJourneyPlan {
  const MoneyJourneyPlan({
    required this.lines,
    required this.stations,
    required this.roads,
    required this.checkpoints,
    required this.chain,
    required this.destination,
    required this.columns,
    required this.totalUsd,
    required this.headline,
    required this.hasGraph,
    required this.placeLine,
  });

  final List<MoneyStepLine> lines;
  final List<JourneyStation> stations;
  final List<JourneyRoad> roads;

  /// The lines listed under the map, in order.
  final List<int> checkpoints;

  /// The roads Sal rides, in order: the first (biggest) leg, then on
  /// from wherever it lands while a road leaves there.
  final List<int> chain;

  /// The destination station, when there is one.
  final int? destination;
  final int columns;

  /// The dollars the journey is about (the order, the purchase, the
  /// send; else every leg's), when the graph says.
  final double? totalUsd;

  /// The amount shown counting up on top (formatted), when known.
  final String? headline;
  final bool hasGraph;

  /// The line index of the order itself (the `place` step), if any.
  final int? placeLine;

  /// Roads from the sources (column 0), for the destination's "n of m
  /// arrived" chip.
  Iterable<JourneyRoad> get sourceRoads =>
      roads.where((r) => stations[r.from].column == 0);

  bool get anyFailed =>
      lines.any((l) => l.status == MoneyStepStatus.failed);
  bool get inProgress => lines.any((l) => !l.status.ended);
  bool get success =>
      !anyFailed &&
      !inProgress &&
      lines.any((l) => l.status == MoneyStepStatus.done);

  /// The line the status line names: a stop, else the deepest line
  /// running (a sub-leg or sub-step under its running stage), else the
  /// first one waiting.
  int? get focus {
    for (final want in const [
      MoneyStepStatus.failed,
      MoneyStepStatus.running,
      MoneyStepStatus.waiting,
    ]) {
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].status != want) continue;
        if (!lines[i].sub) {
          for (var j = i + 1; j < lines.length && lines[j].sub; j++) {
            if (lines[j].status == want) return j;
          }
        }
        return i;
      }
    }
    return null;
  }

  /// At most this many stations stacked in one column, and this many
  /// columns on the map; anything beyond is listed as a checkpoint.
  static const int maxRows = 3;
  static const int maxColumns = 4;

  /// Lays [lines] out. With [graph], every leg (and purchase) is a road
  /// between the balances it names, contiguous sub-lines right under a
  /// leg are its sub-legs (waypoints), and everything else (the
  /// readiness stage and its sub-steps, the order, the arrival, a route
  /// change) is a checkpoint. Without one, the map is one stage road
  /// from [from] to [to] and every line a checkpoint along it. [to]
  /// names the destination when the graph does not say; [toLabel] names
  /// an outside destination (where a send went). [money] formats the
  /// headline from the graph's dollars.
  static MoneyJourneyPlan of(
    List<MoneyStepLine> lines, {
    MoneyStepGraph? graph,
    MoneyPlace? from,
    MoneyPlace? to,
    String? toLabel,
    String Function(double usd)? money,
  }) {
    if (graph == null || graph.isEmpty) {
      return _stageRoad(lines, from: from, to: to, toLabel: toLabel);
    }
    return _fromGraph(lines, graph,
        from: from, to: to, toLabel: toLabel, money: money);
  }

  static MoneyJourneyPlan _stageRoad(List<MoneyStepLine> lines,
      {MoneyPlace? from, MoneyPlace? to, String? toLabel}) {
    final stations = <JourneyStation>[
      JourneyStation(
          id: from?.name ?? 'start', place: from, column: 0, row: 0, rows: 1),
      JourneyStation(
          id: to?.name ?? 'end',
          place: to,
          label: toLabel,
          column: 1,
          row: 0,
          rows: 1),
    ];
    final all = [for (var i = 0; i < lines.length; i++) i];
    return MoneyJourneyPlan(
      lines: lines,
      stations: stations,
      roads: [
        if (all.isNotEmpty)
          JourneyRoad(
              line: -1,
              from: 0,
              to: 1,
              segments: all,
              waypoints: const [],
              usd: 0),
      ],
      checkpoints: all,
      chain: all.isEmpty ? const [] : const [0],
      destination: 1,
      columns: 2,
      totalUsd: null,
      headline: _headlineOf(lines),
      hasGraph: false,
      placeLine: null,
    );
  }

  static MoneyJourneyPlan _fromGraph(
    List<MoneyStepLine> lines,
    MoneyStepGraph graph, {
    MoneyPlace? from,
    MoneyPlace? to,
    String? toLabel,
    String Function(double usd)? money,
  }) {
    // ── The roads, by line ──
    final legLines = <int>[]; // indexes of leg lines, in order
    final subLegs = <int, List<int>>{}; // leg line → its sub-lines
    final checkpoints = <int>[];
    int? placeLine;
    var destPlace = to;
    // The venue whose readiness the graph runs: Predictions converts and
    // approves, Investing credits.
    MoneyPlace? readinessPlace;
    for (final s in graph.steps) {
      if (s.kind == MoneyStepKind.credit) {
        readinessPlace ??= MoneyPlace.investing;
      } else if (s.kind.readiness) {
        readinessPlace ??= MoneyPlace.predictions;
      }
    }
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      final s = l.id == null ? null : graph.byId(l.id!);
      if (l.sub) {
        // A sub-line right under a leg (or its earlier sub-legs) is one
        // of its sub-legs; any other sub-line is a checkpoint.
        final last = legLines.isEmpty ? -1 : legLines.last;
        final under = last >= 0 &&
            (i - 1 == last || (subLegs[last]?.contains(i - 1) ?? false));
        if (under && s == null) {
          (subLegs[last] ??= []).add(i);
        } else {
          checkpoints.add(i);
        }
        continue;
      }
      if (s == null || s.status == MoneyStepStatus.fellBack) {
        checkpoints.add(i);
        continue;
      }
      switch (s.kind) {
        case MoneyStepKind.leg || MoneyStepKind.buy:
          legLines.add(i);
        case MoneyStepKind.convert ||
              MoneyStepKind.approve ||
              MoneyStepKind.confirm ||
              MoneyStepKind.credit:
          checkpoints.add(i);
        case MoneyStepKind.place:
          placeLine = i;
          checkpoints.add(i);
        case MoneyStepKind.arrive:
          destPlace ??= s.to;
          checkpoints.add(i);
      }
    }

    // ── Where the legs go ──
    MoneyStep stepOf(int i) => graph.byId(lines[i].id!)!;
    final froms = <MoneyPlace?>{};
    final tos = <MoneyPlace?>{};
    for (final i in legLines) {
      final s = stepOf(i);
      froms.add(s.from ?? MoneyPlace.dollars);
      tos.add(s.kind == MoneyStepKind.buy ? MoneyPlace.bitcoin : s.to);
    }
    // The destination: as told, else the one place money goes to and
    // never leaves, else the venue the readiness names.
    if (destPlace == null) {
      final sinks = tos.whereType<MoneyPlace>().where((p) => !froms.contains(p));
      if (sinks.length == 1) {
        destPlace = sinks.first;
      } else if (readinessPlace != null) {
        destPlace = readinessPlace;
      } else if (sinks.isNotEmpty) {
        destPlace = sinks.last;
      }
    }

    // ── The stations ──
    final stations = <String, (MoneyPlace?, String?)>{};
    String stationIdOf(MoneyPlace? p) => p?.name ?? 'outside';
    void addStation(MoneyPlace? p, {String? label}) {
      stations.putIfAbsent(stationIdOf(p), () => (p, label));
    }

    final rawRoads = <(int, String, String, double)>[];
    for (final i in legLines) {
      final s = stepOf(i);
      final a = s.from ?? MoneyPlace.dollars;
      MoneyPlace? b = s.kind == MoneyStepKind.buy ? MoneyPlace.bitcoin : s.to;
      b ??= s.id == 'send' ? null : destPlace;
      addStation(a);
      addStation(b, label: b == null ? toLabel : null);
      rawRoads.add((i, stationIdOf(a), stationIdOf(b), s.usd));
    }
    if (destPlace != null) addStation(destPlace);
    if (stations.isEmpty && from != null) addStation(from);

    // Columns by depth along the roads (a source is 0, a place reached
    // from it 1, and so on); the destination sits in the last column.
    final ids = stations.keys.toList();
    final depth = <String, int>{for (final id in ids) id: 0};
    for (var pass = 0; pass < ids.length; pass++) {
      var changed = false;
      for (final r in rawRoads) {
        if (r.$2 == r.$3) continue;
        final d = depth[r.$2]! + 1;
        if (d > depth[r.$3]! && d < ids.length) {
          depth[r.$3] = d;
          changed = true;
        }
      }
      if (!changed) break;
    }
    final destId = destPlace == null
        ? (ids.contains('outside') ? 'outside' : null)
        : stationIdOf(destPlace);
    var columns = ids.isEmpty ? 0 : depth.values.reduce((a, b) => a > b ? a : b) + 1;
    if (destId != null) {
      depth[destId] = columns - 1;
    }
    if (columns > maxColumns) {
      // Too long a chain to draw: the far stations fold into the
      // destination's column and their roads list as checkpoints.
      for (final id in ids) {
        if (depth[id]! > maxColumns - 1) depth[id] = maxColumns - 1;
      }
      columns = maxColumns;
    }

    // Rows within each column, in order of appearance; the destination
    // alone in its column stays centred. More than [maxRows] in a column:
    // the rest are not drawn (their roads are listed instead).
    final rowsIn = <int, int>{};
    final rowOf = <String, int>{};
    final dropped = <String>{};
    for (final id in ids) {
      final c = depth[id]!;
      final r = rowsIn[c] ?? 0;
      if (r >= maxRows && id != destId) {
        dropped.add(id);
        continue;
      }
      rowOf[id] = r;
      rowsIn[c] = r + 1;
    }
    final kept = [for (final id in ids) if (!dropped.contains(id)) id];
    final index = {for (var i = 0; i < kept.length; i++) kept[i]: i};
    final out = <JourneyStation>[
      for (final id in kept)
        JourneyStation(
          id: id,
          place: stations[id]!.$1,
          label: stations[id]!.$2,
          column: depth[id]!,
          row: rowOf[id]!,
          rows: rowsIn[depth[id]!]!,
        ),
    ];

    // ── The roads ──
    final roads = <JourneyRoad>[];
    final listed = <int>[...checkpoints];
    for (final r in rawRoads) {
      final a = index[r.$2];
      final b = index[r.$3];
      if (a == null || b == null || a == b) {
        listed.add(r.$1);
        listed.addAll(subLegs[r.$1] ?? const []);
        continue;
      }
      final subs = subLegs[r.$1] ?? const [];
      roads.add(JourneyRoad(
        line: r.$1,
        from: a,
        to: b,
        segments: subs.isEmpty ? [r.$1] : subs,
        waypoints: [
          for (var k = 0; k + 1 < subs.length; k++)
            JourneyWaypoint(
                line: subs[k],
                label: lines[subs[k]].hop ?? '',
                amount: lines[subs[k]].amount),
        ],
        usd: r.$4,
      ));
    }
    listed.sort();

    // ── Sal's chain: the biggest leg out of a source, then onward ──
    final chain = <int>[];
    var best = -1;
    for (var i = 0; i < roads.length; i++) {
      if (out[roads[i].from].column != 0) continue;
      if (best < 0 || roads[i].usd > roads[best].usd) best = i;
    }
    if (best >= 0) {
      chain.add(best);
      var at = roads[best].to;
      while (true) {
        final next = roads.indexWhere(
            (r) => r.from == at && !chain.contains(roads.indexOf(r)));
        if (next < 0) break;
        chain.add(next);
        at = roads[next].to;
      }
    }

    // ── The dollars ──
    double? total;
    for (final id in const ['place', 'buy', 'send', 'onward']) {
      final s = graph.byId(id);
      if (s != null && s.usd > 0) {
        total = s.usd;
        break;
      }
    }
    if (total == null) {
      var sum = 0.0;
      for (final r in roads) {
        sum += r.usd;
      }
      if (sum > 0) total = (sum * 100).round() / 100;
    }

    return MoneyJourneyPlan(
      lines: lines,
      stations: out,
      roads: roads,
      checkpoints: listed,
      chain: chain,
      destination: destId == null ? null : index[destId],
      columns: columns,
      totalUsd: total,
      headline: total != null && money != null
          ? money(total)
          : _headlineOf(lines),
      hasGraph: true,
      placeLine: placeLine,
    );
  }

  static final RegExp _amountToken =
      RegExp(r'[\$€£¥]\s?\d(?:[\d,.]*\d)?|\d(?:[\d,.]*\d)?\s?[€£]');

  /// The first amount in the last line that names one.
  static String? _headlineOf(List<MoneyStepLine> lines) {
    for (final l in lines.reversed) {
      final m = _amountToken.firstMatch(l.text);
      if (m != null) return m.group(0);
    }
    return null;
  }
}
