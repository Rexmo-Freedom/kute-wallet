// lib/services/one_balance/money_steps.dart
//
// Every money move as an explicit step graph (founder, 15 October 2026:
// "just make all steps clear in the sub steps ... make it in parallel
// most of the things that can be parallel"). One model for a funded
// order (a bet, an Investing order, added margin) and for a move (Buy
// bitcoin from Investments): named steps with dependencies, driven by ONE
// runner ([MoneyStepRunner]), rendered by ONE widget as the slip's or the
// sheet's sub-steps. The progress the person sees IS the state machine.
//
// A step starts the moment its dependencies allow it: every leg of an
// order starts together; Predictions' readiness starts on the FIRST money
// landing (`afterAny`) and does not wait for every leg; the order waits
// on readiness covering it. A step that fails names itself; a retry
// restarts only that step and what depends on it; a fallback replaces a
// step with the steps that do its job another way (a direct Bitcoin leg
// going via Dollars), and whatever depended on it depends on the last of
// those instead.
//
// The graph persists with its record (`fundedOrdersProvider`, the move
// stores) as plain JSON. The `ref` a leg keeps is the Activity row's id,
// local only: nothing here is ever tracked or logged.

import 'dart:async';

import 'package:flutter/foundation.dart' show immutable, visibleForTesting;

/// Where a step is.
enum MoneyStepStatus {
  /// Not started: a dependency is still open.
  waiting,
  running,
  done,
  failed,

  /// Replaced by the steps that do its job another way.
  fellBack,

  /// Not needed this time (the money was already pUSD, the allowance was
  /// already set): never shown.
  skipped;

  /// Ended, one way or another.
  bool get ended => this != waiting && this != running;

  /// Satisfies a dependency on it.
  bool get satisfies => this == done || this == skipped;
}

/// What a step does, which decides its words and the stage it shows under.
enum MoneyStepKind {
  /// Money moving from one place to another ("Moving $8.00 from Bitcoin").
  leg,

  /// Predictions: USDC.e converted to pUSD ("Converting to pUSD").
  convert,

  /// Predictions: the spend allowance set ("Approving spend").
  approve,

  /// Predictions: the venue's own balance view covers the order
  /// ("Confirming balance").
  confirm,

  /// Investing: the USDC is where the order draws from ("Crediting to
  /// trading balance").
  credit,

  /// The order itself ("Placing $15 on Yes").
  place,

  /// Dollars buying bitcoin ("Buying $5.00 of Bitcoin").
  buy,

  /// The bitcoin landing in the wallet ("Arriving in Bitcoin").
  arrive;

  /// A readiness sub-step, shown indented under the venue's "getting
  /// ready" stage line.
  bool get readiness =>
      this == convert || this == approve || this == confirm || this == credit;
}

/// A balance money moves from or to, named on screen by the balance's own
/// name (Bitcoin, Dollars, Predictions, Investing).
enum MoneyPlace { bitcoin, dollars, predictions, investing }

/// The route a leg takes: straight to its destination, or through Dollars.
abstract final class MoneyRoute {
  static const String direct = 'direct';
  static const String viaDollars = 'via_dollars';
}

/// Why a direct leg went the longer way, as the person reads it.
enum MoneyFallBack {
  /// A refusal that says nothing about the route: the network, a read,
  /// an earlier move still on its way ("route busy").
  busy,

  /// The route itself is off: not offered, paused, refused recently.
  unavailable,

  /// The amount is under what the direct route takes.
  tooSmall,

  /// Nothing the person can act on (the approval, an account read, the
  /// wallet's own guard): "going via Dollars", no reason given.
  neutral;

  /// [reason] (the fixed code a fallen-back step keeps) as one of these.
  /// Only a transient refusal ever reads as busy.
  static MoneyFallBack of(String? reason) {
    final r = (reason ?? '').toLowerCase();
    if (r.contains('minimum') ||
        r.contains('too_small') ||
        r.startsWith('below')) {
      return tooSmall;
    }
    if (r == 'no_direct_route' ||
        r == 'no_route' ||
        r == 'refused_recently' ||
        r == 'cctp_paused' ||
        r.contains('route_unavailable') ||
        r.contains('routeunavailable') ||
        r.contains('capability') ||
        r.contains('pair_missing') ||
        r == 'unsupported_source') {
      return unavailable;
    }
    if (r == 'network' ||
        r == 'timeout' ||
        r == 'rate_limited' ||
        r == 'cctp_in_flight') {
      return busy;
    }
    return neutral;
  }
}

/// One step.
@immutable
class MoneyStep {
  const MoneyStep({
    required this.id,
    required this.kind,
    this.from,
    this.to,
    this.usd = 0,
    this.route,
    this.after = const [],
    this.afterAny = false,
    this.status = MoneyStepStatus.waiting,
    this.startedAt,
    this.endedAt,
    this.reason,
    this.ref,
  });

  /// Unique in its graph ("leg:bitcoin", "ready:convert", "place").
  final String id;
  final MoneyStepKind kind;
  final MoneyPlace? from;
  final MoneyPlace? to;

  /// The dollars the step moves, places or buys.
  final double usd;

  /// [MoneyRoute] for a leg.
  final String? route;

  /// The steps this one waits on.
  final List<String> after;

  /// Starts once ANY of [after] is done (readiness on the first money
  /// landing) instead of all of them.
  final bool afterAny;

  final MoneyStepStatus status;
  final DateTime? startedAt;
  final DateTime? endedAt;

  /// Why it failed or fell back (a fixed code, never shown, never text
  /// from a provider).
  final String? reason;

  /// The leg's Activity row id (quote, then order), to follow it after a
  /// restart. Local only.
  final String? ref;

  /// Milliseconds from start to end, when both are known.
  int? get ms => startedAt == null || endedAt == null
      ? null
      : endedAt!.difference(startedAt!).inMilliseconds.clamp(0, 1 << 31);

  MoneyStep copyWith({
    MoneyStepStatus? status,
    double? usd,
    String? route,
    List<String>? after,
    bool? afterAny,
    DateTime? startedAt,
    DateTime? endedAt,
    String? reason,
    String? ref,
    bool clearEnd = false,
    bool clearReason = false,
  }) =>
      MoneyStep(
        id: id,
        kind: kind,
        from: from,
        to: to,
        usd: usd ?? this.usd,
        route: route ?? this.route,
        after: after ?? this.after,
        afterAny: afterAny ?? this.afterAny,
        status: status ?? this.status,
        startedAt: startedAt ?? this.startedAt,
        endedAt: clearEnd ? null : (endedAt ?? this.endedAt),
        reason: clearReason ? null : (reason ?? this.reason),
        ref: ref ?? this.ref,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind.name,
        if (from != null) 'from': from!.name,
        if (to != null) 'to': to!.name,
        'usd': usd,
        if (route != null) 'route': route,
        if (after.isNotEmpty) 'after': after,
        if (afterAny) 'afterAny': true,
        'status': status.name,
        if (startedAt != null) 'startedAt': startedAt!.millisecondsSinceEpoch,
        if (endedAt != null) 'endedAt': endedAt!.millisecondsSinceEpoch,
        if (reason != null) 'reason': reason,
        if (ref != null) 'ref': ref,
      };

  static T? _enum<T extends Enum>(List<T> values, Object? name) =>
      values.where((e) => e.name == name).firstOrNull;

  static DateTime? _time(Object? v) =>
      v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;

  static MoneyStep? fromJson(Object? v) {
    if (v is! Map) return null;
    final id = v['id'];
    final kind = _enum(MoneyStepKind.values, v['kind']);
    if (id is! String || id.isEmpty || kind == null) return null;
    final usd = v['usd'];
    final after = v['after'];
    return MoneyStep(
      id: id,
      kind: kind,
      from: _enum(MoneyPlace.values, v['from']),
      to: _enum(MoneyPlace.values, v['to']),
      usd: usd is num ? usd.toDouble() : 0,
      route: v['route'] is String ? v['route'] as String : null,
      after: after is List
          ? [
              for (final a in after)
                if (a is String) a
            ]
          : const [],
      afterAny: v['afterAny'] == true,
      status:
          _enum(MoneyStepStatus.values, v['status']) ?? MoneyStepStatus.waiting,
      startedAt: _time(v['startedAt']),
      endedAt: _time(v['endedAt']),
      reason: v['reason'] is String ? v['reason'] as String : null,
      ref: v['ref'] is String ? v['ref'] as String : null,
    );
  }
}

/// The steps of one order or move, in the order they are shown.
@immutable
class MoneyStepGraph {
  const MoneyStepGraph(this.steps);

  static const MoneyStepGraph empty = MoneyStepGraph([]);

  final List<MoneyStep> steps;

  bool get isEmpty => steps.isEmpty;

  MoneyStep? byId(String id) {
    for (final s in steps) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// The legs, in order.
  Iterable<MoneyStep> get legs =>
      steps.where((s) => s.kind == MoneyStepKind.leg);

  /// Whether [step] may start now: waiting, and its dependencies allow it
  /// (all of them satisfied, or any one for [MoneyStep.afterAny]). A step
  /// whose dependency failed stays waiting until a retry.
  bool canStart(MoneyStep step) {
    if (step.status != MoneyStepStatus.waiting) return false;
    if (step.after.isEmpty) return true;
    final deps = [for (final id in step.after) byId(id)];
    if (step.afterAny) {
      return deps.any((d) => d != null && d.status.satisfies);
    }
    return deps.every((d) => d == null || d.status.satisfies);
  }

  /// [id] and every step that depends on it, directly or not.
  Set<String> branchOf(String id) {
    final out = <String>{id};
    var grew = true;
    while (grew) {
      grew = false;
      for (final s in steps) {
        if (out.contains(s.id)) continue;
        if (s.after.any(out.contains)) {
          out.add(s.id);
          grew = true;
        }
      }
    }
    return out;
  }

  MoneyStepGraph withStep(MoneyStep step) => MoneyStepGraph([
        for (final s in steps) s.id == step.id ? step : s,
      ]);

  MoneyStepGraph update(String id, MoneyStep Function(MoneyStep s) change) =>
      MoneyStepGraph([
        for (final s in steps) s.id == id ? change(s) : s,
      ]);

  /// [id] fell back: it is kept (marked [MoneyStepStatus.fellBack], so the
  /// person sees the route change), [replacements] are inserted right
  /// after it, and every step that waited on [id] waits on the last
  /// replacement instead. The first replacement inherits [id]'s own
  /// dependencies when it names none.
  MoneyStepGraph fallBack(String id, List<MoneyStep> replacements,
      {String? reason, DateTime? at}) {
    final old = byId(id);
    if (old == null || replacements.isEmpty) return this;
    final last = replacements.last.id;
    final fixed = [
      for (var i = 0; i < replacements.length; i++)
        i == 0 && replacements[i].after.isEmpty
            ? replacements[i].copyWith(after: old.after, afterAny: old.afterAny)
            : replacements[i],
    ];
    final out = <MoneyStep>[];
    for (final s in steps) {
      if (s.id == id) {
        out.add(s.copyWith(
            status: MoneyStepStatus.fellBack, reason: reason, endedAt: at));
        out.addAll(fixed);
        continue;
      }
      out.add(s.after.contains(id)
          ? s.copyWith(after: [
              for (final a in s.after) a == id ? last : a,
            ])
          : s);
    }
    return MoneyStepGraph(out);
  }

  /// Every step running or able to run.
  bool get live =>
      steps.any((s) => s.status == MoneyStepStatus.running || canStart(s));

  /// The first failed step, if any.
  MoneyStep? get firstFailed =>
      steps.where((s) => s.status == MoneyStepStatus.failed).firstOrNull;

  /// Every step that is not skipped ended well.
  bool get allDone => steps
      .every((s) => s.status.satisfies || s.status == MoneyStepStatus.fellBack);

  List<Map<String, Object?>> toJson() => [for (final s in steps) s.toJson()];

  static MoneyStepGraph fromJson(Object? v) {
    if (v is! List) return empty;
    return MoneyStepGraph([
      for (final e in v)
        if (MoneyStep.fromJson(e) case final s?) s,
    ]);
  }
}

// ── The runner ────────────────────────────────────────────────────────

/// How one step's work ended.
sealed class MoneyStepOutcome {
  const MoneyStepOutcome();
}

final class MoneyStepDone extends MoneyStepOutcome {
  const MoneyStepDone({this.usd, this.ref});

  /// What the step really moved, when it differs from the plan.
  final double? usd;
  final String? ref;
}

final class MoneyStepFailed extends MoneyStepOutcome {
  const MoneyStepFailed(this.reason);
  final String reason;
}

/// Not needed this time: never shown.
final class MoneyStepSkipped extends MoneyStepOutcome {
  const MoneyStepSkipped();
}

/// Done another way: [replacements] run in its place (see
/// [MoneyStepGraph.fallBack]).
final class MoneyStepFellBack extends MoneyStepOutcome {
  const MoneyStepFellBack(this.reason, this.replacements);
  final String reason;
  final List<MoneyStep> replacements;
}

/// A step's work. [update] lets a running step record what it learned
/// (its Activity row id, a resized amount) before it ends.
typedef MoneyStepAction = Future<MoneyStepOutcome> Function(
    MoneyStep step, void Function(MoneyStep Function(MoneyStep s)) update);

/// Drives a [MoneyStepGraph]: starts every step whose dependencies allow
/// it at once, re-evaluates whenever one ends, and finishes when nothing
/// runs and nothing can start. [actionFor] gives each step its work (null:
/// the step completes on its own, `done`). [onChange] hears every change,
/// for the record and the screen.
class MoneyStepRunner {
  MoneyStepRunner({
    required MoneyStepGraph graph,
    required this.actionFor,
    this.onChange,
    DateTime Function()? clock,
  })  : _graph = graph,
        _clock = clock ?? DateTime.now;

  MoneyStepGraph _graph;
  final MoneyStepAction? Function(MoneyStep step) actionFor;
  final void Function(MoneyStepGraph graph)? onChange;
  final DateTime Function() _clock;

  final Set<String> _inFlight = {};
  Completer<MoneyStepGraph>? _settled;
  bool _cancelled = false;

  MoneyStepGraph get graph => _graph;

  void _set(MoneyStepGraph next) {
    _graph = next;
    try {
      onChange?.call(next);
    } catch (_) {}
  }

  /// Runs until nothing runs and nothing can start; returns the graph.
  Future<MoneyStepGraph> run() {
    final settled = _settled ??= Completer<MoneyStepGraph>();
    _pump();
    return settled.future;
  }

  /// Stops starting new steps (the order was dropped). Running steps end
  /// on their own; their outcome is still recorded.
  void cancel() {
    _cancelled = true;
    _pump();
  }

  /// Restarts [id] and only what depends on it: they go back to waiting
  /// (ended steps elsewhere keep their state), then the graph runs again.
  Future<MoneyStepGraph> retry(String id) {
    final branch = _graph.branchOf(id);
    _set(MoneyStepGraph([
      for (final s in _graph.steps)
        branch.contains(s.id) &&
                s.status != MoneyStepStatus.running &&
                s.status != MoneyStepStatus.fellBack
            ? s.copyWith(
                status: MoneyStepStatus.waiting,
                clearEnd: true,
                clearReason: true)
            : s,
    ]));
    _cancelled = false;
    _settled = null;
    return run();
  }

  void _pump() {
    // A step with no work completes at once and may open others: loop
    // until nothing more can start.
    var again = !_cancelled;
    while (again) {
      again = false;
      for (final step in _graph.steps) {
        if (_inFlight.contains(step.id)) continue;
        final current = _graph.byId(step.id);
        if (current == null || !_graph.canStart(current)) continue;
        if (_start(current)) again = true;
      }
    }
    if (_inFlight.isEmpty) {
      final settled = _settled;
      if (settled != null && !settled.isCompleted) settled.complete(_graph);
    }
  }

  /// Starts [step]; true when it completed at once (no work).
  bool _start(MoneyStep step) {
    final action = actionFor(step);
    final now = _clock();
    if (action == null) {
      _set(_graph.update(
          step.id,
          (s) => s.copyWith(
              status: MoneyStepStatus.done, startedAt: now, endedAt: now)));
      return true;
    }
    _inFlight.add(step.id);
    _set(_graph.update(step.id,
        (s) => s.copyWith(status: MoneyStepStatus.running, startedAt: now)));
    final running = _graph.byId(step.id)!;
    Future<MoneyStepOutcome> work;
    try {
      work = action(running, (change) {
        if (_graph.byId(step.id)?.status != MoneyStepStatus.running) return;
        _set(_graph.update(step.id, change));
      });
    } catch (e) {
      work = Future.value(MoneyStepFailed(_reasonOf(e)));
    }
    work
        .then<MoneyStepOutcome>((o) => o,
            onError: (Object e) => MoneyStepFailed(_reasonOf(e)))
        .then((outcome) {
      _inFlight.remove(step.id);
      _end(step.id, outcome);
      _pump();
    });
    return false;
  }

  void _end(String id, MoneyStepOutcome outcome) {
    final at = _clock();
    switch (outcome) {
      case MoneyStepDone(:final usd, :final ref):
        _set(_graph.update(
            id,
            (s) => s.copyWith(
                status: MoneyStepStatus.done,
                endedAt: at,
                usd: usd,
                ref: ref)));
      case MoneyStepFailed(:final reason):
        _set(_graph.update(
            id,
            (s) => s.copyWith(
                status: MoneyStepStatus.failed, endedAt: at, reason: reason)));
      case MoneyStepSkipped():
        _set(_graph.update(id,
            (s) => s.copyWith(status: MoneyStepStatus.skipped, endedAt: at)));
      case MoneyStepFellBack(:final reason, :final replacements):
        _set(_graph.fallBack(id, replacements, reason: reason, at: at));
    }
  }

  static String _reasonOf(Object e) {
    final t = e.runtimeType.toString();
    return RegExp(r'^[A-Za-z_]{1,48}$').hasMatch(t) ? t : 'error';
  }
}

// ── Reading a graph for the screen ─────────────────────────────────────

/// The status a stage line shows for its sub-steps: running while any
/// runs, failed when one failed, done once every shown one is, waiting
/// otherwise. Null when it has no shown sub-step.
MoneyStepStatus? stageStatusOf(Iterable<MoneyStep> subSteps) {
  final shown = subSteps.where((s) => s.status != MoneyStepStatus.skipped);
  if (shown.isEmpty) return null;
  if (shown.any((s) => s.status == MoneyStepStatus.failed)) {
    return MoneyStepStatus.failed;
  }
  if (shown.any((s) => s.status == MoneyStepStatus.running)) {
    return MoneyStepStatus.running;
  }
  if (shown.every((s) => s.status.satisfies)) return MoneyStepStatus.done;
  if (shown.any((s) => s.status.satisfies)) return MoneyStepStatus.running;
  return MoneyStepStatus.waiting;
}

/// Test seam for widgets: a graph from (id, kind, status) triples.
@visibleForTesting
MoneyStepGraph debugGraph(
        List<(String, MoneyStepKind, MoneyStepStatus)> steps) =>
    MoneyStepGraph([
      for (final (id, kind, status) in steps)
        MoneyStep(id: id, kind: kind, status: status),
    ]);
