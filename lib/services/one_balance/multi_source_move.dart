// lib/services/one_balance/multi_source_move.dart
//
// One record per action that pulled venue cash (venue_cash_source.dart):
// the person's intent ("Send $50", "Move $50 to Bitcoin") and every leg
// that moved money for it, so Activity shows ONE row for the intent with
// the legs inside its detail sheet, says what was delivered and what is
// left after a partial failure, and Retry can pull only the failed
// remainder.
//
//  * A leg is linked to its Activity rows by the settlement operation id
//    the rail recorded (every row a leg writes carries it), or its quote
//    id while there is no operation.
//  * The action's own step (the send, the purchase, the order's funding)
//    is linked the same way once it went ([MultiSourceMoveStore.attachFinal]).
//  * Every move keeps its step graph on the record ([MultiSourceMove.steps],
//    move_steps.dart): what each leg and the action's own step (the
//    purchase and the arrival, the send, Dollars going on into a venue)
//    are doing. A leg recorded and the own step attached update it here,
//    for every move. Records written before it had none and still read
//    (mapped from their legs).
//  * Records live in the settings box (best effort; this session keeps
//    them in memory either way), newest first, the last
//    [MultiSourceMoveStore.keep] only. No address, no key: venue names,
//    dollar amounts and the ids the wallet's own rows already carry.

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueNotifier, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/services/one_balance/money_steps.dart';
import 'package:kute/services/one_balance/move_steps.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/venue_funder.dart'
    show VenueCashDestination;
import 'package:kute/services/tracking_service.dart';

/// How a leg reached the move's destination.
abstract final class VenueCashRoute {
  /// Straight from the venue to the destination.
  static const String direct = 'direct';

  /// Home to Dollars first, then on from there (or Dollars was the
  /// destination).
  static const String viaDollars = 'via_dollars';
}

/// One venue leg of a move.
class MultiSourceMoveLeg {
  const MultiSourceMoveLeg({
    required this.venue,
    required this.usd,
    required this.arrivingUsd,
    required this.route,
    required this.ok,
    required this.at,
    this.operationId,
    this.quoteId,
    this.error,
    this.fellBack,
    this.uncertain = false,
    this.stoppedOperationId,
  });

  final OneBalanceVenue venue;

  /// What left the venue (what was asked of it, for a failed leg).
  final double usd;

  /// What the leg is expected to land.
  final double arrivingUsd;

  /// [VenueCashRoute.direct] or [VenueCashRoute.viaDollars].
  final String route;

  /// The leg went (its money is on its way); false: it stayed on its
  /// venue.
  final bool ok;
  final DateTime at;
  final String? operationId;
  final String? quoteId;

  /// A fixed code for a failed leg, never an error text.
  final String? error;

  /// Why a leg planned straight to the destination came home to Dollars
  /// instead (the rail's fixed refusal code); null otherwise.
  final String? fellBack;

  /// A failed RPC is not proof that no source payment happened.
  final bool uncertain;

  /// The settlement record of a leg that stopped before anything left (a
  /// CCTP move writes its record and Activity row before it signs): its
  /// row folds into the move instead of standing beside it. Never an
  /// operation that moved money ([operationId] is that).
  final String? stoppedOperationId;

  bool get direct => route == VenueCashRoute.direct;

  Map<String, dynamic> toJson() => {
        'venue': venue.name,
        'usd': usd,
        'arrivingUsd': arrivingUsd,
        'route': route,
        'ok': ok,
        'at': at.millisecondsSinceEpoch,
        if (operationId != null) 'operationId': operationId,
        if (quoteId != null) 'quoteId': quoteId,
        if (error != null) 'error': error,
        if (fellBack != null) 'fellBack': fellBack,
        if (uncertain) 'uncertain': true,
        if (stoppedOperationId != null)
          'stoppedOperationId': stoppedOperationId,
      };

  static MultiSourceMoveLeg? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final venue =
        OneBalanceVenue.values.where((v) => v.name == raw['venue']).firstOrNull;
    final usd = raw['usd'];
    final arriving = raw['arrivingUsd'];
    final at = raw['at'];
    if (venue == null || usd is! num || arriving is! num || at is! int) {
      return null;
    }
    return MultiSourceMoveLeg(
      venue: venue,
      usd: usd.toDouble(),
      arrivingUsd: arriving.toDouble(),
      route: raw['route'] == VenueCashRoute.direct
          ? VenueCashRoute.direct
          : VenueCashRoute.viaDollars,
      ok: raw['ok'] == true,
      at: DateTime.fromMillisecondsSinceEpoch(at),
      operationId: raw['operationId'] as String?,
      quoteId: raw['quoteId'] as String?,
      error: raw['error'] as String?,
      fellBack: raw['fellBack'] as String?,
      uncertain: raw['uncertain'] == true,
      stoppedOperationId: raw['stoppedOperationId'] as String?,
    );
  }
}

/// One action that pulled venue cash, and its legs.
class MultiSourceMove {
  const MultiSourceMove({
    required this.id,
    required this.forAction,
    required this.destination,
    required this.totalUsd,
    required this.dollarsUsd,
    required this.createdAt,
    this.walletId,
    this.legs = const [],
    this.finalOperationId,
    this.initialDollarsOperationId,
    this.initialDollarsSentUsd = 0,
    this.parallelPurchase = false,
    this.steps = MoneyStepGraph.empty,
  });

  final String id;
  final String? walletId;

  /// What the money is for (`VenueCashFor`: send, buy_bitcoin, …).
  final String forAction;
  final VenueCashDestination destination;

  /// The person's amount.
  final double totalUsd;

  /// What Dollars held toward it when the move started.
  final double dollarsUsd;
  final DateTime createdAt;
  final List<MultiSourceMoveLeg> legs;

  /// The action's own step (the send, the purchase), once it went.
  final String? finalOperationId;

  /// Dollars' independent, parallel purchase. The later purchase (if a venue
  /// had to come home first) remains [finalOperationId].
  final String? initialDollarsOperationId;
  final double initialDollarsSentUsd;
  final bool parallelPurchase;
  bool get isParallelPurchase => parallelPurchase || hasParallelDollars;

  bool get hasParallelDollars => steps.byId(MoveSteps.initialDollarsId) != null;
  double get _dollarsContribution =>
      hasParallelDollars ? initialDollarsSentUsd : dollarsUsd;

  /// The move as steps (its legs, its own step, the arrival), as the
  /// money code recorded them (move_steps.dart); empty on a record made
  /// before them.
  final MoneyStepGraph steps;

  List<MultiSourceMoveLeg> get okLegs => [
        for (final l in legs)
          if (l.ok) l
      ];
  List<MultiSourceMoveLeg> get failedLegs => [
        for (final l in legs)
          if (!l.ok) l
      ];

  /// What reached (or is on its way to) the move's destination: Dollars'
  /// part plus every leg that went, never more than [totalUsd].
  double get deliveredUsd {
    final sum = _dollarsContribution +
        okLegs.fold<double>(0, (s, l) => s + l.arrivingUsd);
    return math.min(totalUsd, _cents(sum));
  }

  /// What the legs that went straight to the destination delivered.
  double get directDeliveredUsd => _cents(initialDollarsSentUsd +
      okLegs
          .where((l) => l.direct)
          .fold<double>(0, (s, l) => s + l.arrivingUsd));

  List<MultiSourceMoveLeg> get provenUnsentLegs {
    final latest = <OneBalanceVenue, MultiSourceMoveLeg>{
      for (final leg in legs) leg.venue: leg,
    };
    return latest.values.where((leg) {
      if (leg.ok ||
          leg.uncertain ||
          leg.error != 'not_sent' ||
          leg.operationId != null ||
          leg.quoteId != null) {
        return false;
      }
      final proof = steps.steps
          .where((step) =>
              MoveSteps.isVenueLeg(step) &&
              step.from == MoveSteps.placeOf(leg.venue))
          .lastOrNull;
      return proof?.status == MoneyStepStatus.failed &&
          proof?.reason == 'not_sent' &&
          proof?.ref == null;
    }).toList();
  }

  /// What is still missing after a failed leg (0 when none failed).
  double get remainingUsd {
    if (isParallelPurchase) {
      final initial = steps.byId(MoveSteps.initialDollarsId);
      final initialMissing = initialDollarsOperationId == null &&
              initial?.status == MoneyStepStatus.failed &&
              initial?.reason == 'not_sent' &&
              initial?.ref == null
          ? initial!.usd
          : 0.0;
      return _cents(initialMissing +
          provenUnsentLegs.fold<double>(
              0, (sum, leg) => sum + leg.arrivingUsd));
    }
    final dollars = steps.byId(MoveSteps.initialDollarsId);
    final dollarsFailed =
        dollars?.status == MoneyStepStatus.failed && dollars?.ref == null;
    // The action's own step went: the whole amount was there for it.
    if ((failedLegs.isEmpty && !dollarsFailed) ||
        (!hasParallelDollars && finalOperationId != null)) {
      return 0;
    }
    // A leg whose outcome is unknown may have moved its money: it is never
    // part of what is still missing, so no Retry sends it again.
    final uncertainUsd = legs
        .where((l) => !l.ok && l.uncertain)
        .fold<double>(0, (sum, l) => sum + l.arrivingUsd);
    final left = _cents(totalUsd - deliveredUsd - uncertainUsd);
    return left > 0 ? left : 0;
  }

  /// A leg failed and part of the amount never left its venue.
  bool get partial => remainingUsd >= 0.01;

  /// What the move spent: the person's amount, or after a failed leg
  /// what Dollars gave and the legs that went took.
  double get spentUsd {
    if (isParallelPurchase) {
      return _cents(initialDollarsSentUsd +
          okLegs.fold<double>(0, (sum, leg) => sum + leg.usd));
    }
    final buy = steps.byId(MoveSteps.buyId);
    if (finalOperationId == null &&
        buy != null &&
        buy.ref == null &&
        buy.status == MoneyStepStatus.skipped &&
        buy.reason == 'below_minimum') {
      // None of the initial Dollars left. Count actual source sends, including
      // their fees, rather than the requested total or unsent remainder.
      return _cents(okLegs.fold<double>(0, (s, l) => s + l.usd));
    }
    return partial
        ? math.min(totalUsd,
            _cents(dollarsUsd + okLegs.fold<double>(0, (s, l) => s + l.usd)))
        : totalUsd;
  }

  /// The Activity row ids and operation ids that belong to this move.
  Set<String> get linkedIds => {
        for (final l in legs) ...[
          if (l.operationId != null) l.operationId!,
          if (l.operationId != null) 'cctp-${l.operationId}',
          if (l.quoteId != null) l.quoteId!,
          if (l.stoppedOperationId != null) l.stoppedOperationId!,
          if (l.stoppedOperationId != null) 'cctp-${l.stoppedOperationId}',
        ],
        if (finalOperationId != null) finalOperationId!,
        if (initialDollarsOperationId != null) initialDollarsOperationId!,
      };

  MultiSourceMove copyWith({
    List<MultiSourceMoveLeg>? legs,
    String? finalOperationId,
    String? initialDollarsOperationId,
    double? initialDollarsSentUsd,
    bool? parallelPurchase,
    MoneyStepGraph? steps,
  }) =>
      MultiSourceMove(
        id: id,
        walletId: walletId,
        forAction: forAction,
        destination: destination,
        totalUsd: totalUsd,
        dollarsUsd: dollarsUsd,
        createdAt: createdAt,
        legs: legs ?? this.legs,
        finalOperationId: finalOperationId ?? this.finalOperationId,
        initialDollarsOperationId:
            initialDollarsOperationId ?? this.initialDollarsOperationId,
        initialDollarsSentUsd:
            initialDollarsSentUsd ?? this.initialDollarsSentUsd,
        parallelPurchase: parallelPurchase ?? this.parallelPurchase,
        steps: steps ?? this.steps,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        if (walletId != null) 'walletId': walletId,
        'for': forAction,
        'destination': destination.name,
        'totalUsd': totalUsd,
        'dollarsUsd': dollarsUsd,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'legs': [for (final l in legs) l.toJson()],
        if (finalOperationId != null) 'finalOperationId': finalOperationId,
        if (initialDollarsOperationId != null)
          'initialDollarsOperationId': initialDollarsOperationId,
        if (parallelPurchase) 'parallelPurchase': true,
        if (initialDollarsSentUsd > 0)
          'initialDollarsSentUsd': initialDollarsSentUsd,
        if (!steps.isEmpty) 'steps': steps.toJson(),
      };

  static MultiSourceMove? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final destination = VenueCashDestination.values
        .where((d) => d.name == raw['destination'])
        .firstOrNull;
    final total = raw['totalUsd'];
    final dollars = raw['dollarsUsd'];
    final created = raw['createdAt'];
    if (id is! String ||
        destination == null ||
        total is! num ||
        dollars is! num ||
        created is! int) {
      return null;
    }
    final legs = raw['legs'];
    return MultiSourceMove(
      id: id,
      walletId: raw['walletId'] as String?,
      forAction: raw['for'] as String? ?? '',
      destination: destination,
      totalUsd: total.toDouble(),
      dollarsUsd: dollars.toDouble(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(created),
      legs: [
        if (legs is List)
          for (final l in legs)
            if (MultiSourceMoveLeg.fromJson(l) case final leg?) leg,
      ],
      finalOperationId: raw['finalOperationId'] as String?,
      initialDollarsOperationId: raw['initialDollarsOperationId'] as String?,
      parallelPurchase: raw['parallelPurchase'] == true,
      initialDollarsSentUsd:
          (raw['initialDollarsSentUsd'] as num?)?.toDouble() ?? 0,
      steps: MoneyStepGraph.fromJson(raw['steps']),
    );
  }

  static double _cents(double usd) => (usd * 100).round() / 100;
}

/// The records, in memory and (best effort) in the settings box.
abstract final class MultiSourceMoveStore {
  static const String key = 'multi_source_moves_v1';

  /// How many moves are kept.
  static const int keep = 60;

  /// Bumped on every change, so the Activity lists rebuild.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Map<String, MultiSourceMove>? _held;
  static final Set<String> _retrying = {};

  /// Test seam: the clock new ids and legs are stamped with.
  static DateTime Function() clock = DateTime.now;
  static int _seq = 0;

  @visibleForTesting
  static void reset() {
    _held = {};
    _retrying.clear();
    revision.value++;
  }

  static Map<String, MultiSourceMove> _all() {
    final held = _held;
    if (held != null) return held;
    final loaded = <String, MultiSourceMove>{};
    try {
      if (Hive.isBoxOpen('settings')) {
        final raw = Hive.box('settings').get(key);
        if (raw is String) {
          final list = jsonDecode(raw);
          if (list is List) {
            for (final v in list) {
              final m = MultiSourceMove.fromJson(v);
              if (m != null) loaded[m.id] = m;
            }
          }
        }
      }
    } catch (_) {/* unreadable: this session starts empty */}
    return _held = loaded;
  }

  static void _save() {
    final moves = all();
    try {
      if (Hive.isBoxOpen('settings')) {
        Hive.box('settings')
            .put(key, jsonEncode([for (final m in moves) m.toJson()]));
      }
    } catch (_) {/* best effort: memory still holds them */}
    revision.value++;
  }

  /// Every move, newest first.
  static List<MultiSourceMove> all() {
    final list = _all().values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  static MultiSourceMove? get(String id) => _all()[id];

  /// A fresh move id (`msm_…`): local only, never sent anywhere.
  static String newId() => 'msm_${clock().microsecondsSinceEpoch}_${_seq++}';

  /// Starts [move], or keeps the one already under its id.
  static MultiSourceMove start(MultiSourceMove move) {
    final all = _all();
    final existing = all[move.id];
    if (existing != null) return existing;
    all[move.id] = move;
    final sorted = MultiSourceMoveStore.all();
    if (sorted.length > keep) {
      for (final old in sorted.skip(keep)) {
        all.remove(old.id);
      }
    }
    _save();
    return move;
  }

  /// Adds [leg] to move [id], and its step: on its way, failed, or
  /// through Dollars instead ([MoveSteps.legRecorded]).
  static void addLeg(String id, MultiSourceMoveLeg leg) {
    final all = _all();
    final move = all[id];
    if (move == null) return;
    final next = move.copyWith(legs: [...move.legs, leg]);
    all[id] = next.copyWith(
        steps: _stepsOr(
            next,
            () => MoveSteps.legRecorded(
                // The graph before this leg (a record without steps maps
                // from its earlier legs), then this leg.
                MoveSteps.of(move),
                leg,
                destination: next.destination,
                forAction: next.forAction)));
    _save();
  }

  /// The action's own step went: its settlement operation is part of the
  /// move's one row, and its step is on its way ([MoveSteps.finalSent]).
  static void attachFinal(String? id, String? operationId) {
    if (id == null || operationId == null || operationId.isEmpty) return;
    final all = _all();
    final move = all[id];
    if (move == null) return;
    final next = move.copyWith(finalOperationId: operationId);
    all[id] = next.copyWith(
        steps: _stepsOr(
            next, () => MoveSteps.finalSent(MoveSteps.of(next), operationId)));
    _save();
  }

  static void markParallelPurchase(String id) {
    final move = _all()[id];
    if (move == null || move.parallelPurchase) return;
    _all()[id] = move.copyWith(parallelPurchase: true);
    _save();
  }

  static void attachInitialDollars(
      String id, String operationId, double sentUsd) {
    final move = _all()[id];
    if (move == null || move.initialDollarsOperationId != null) return;
    _all()[id] = move.copyWith(
        initialDollarsOperationId: operationId, initialDollarsSentUsd: sentUsd);
    _save();
  }

  /// [make]'s graph, reconciled with [move]; [move]'s own graph when it
  /// throws (the steps never stop the money).
  static MoneyStepGraph _stepsOr(
      MultiSourceMove move, MoneyStepGraph Function() make) {
    try {
      return MoveSteps.reconcile(move, make());
    } catch (_) {
      return move.steps;
    }
  }

  /// Replaces move [id]'s step graph with what [change] makes of the
  /// record (null: unchanged). Saved only when it changed.
  static void updateSteps(
      String id, MoneyStepGraph? Function(MultiSourceMove move) change) {
    final all = _all();
    final move = all[id];
    if (move == null) return;
    MoneyStepGraph? next;
    try {
      next = change(move);
    } catch (_) {
      return; // the steps never stop the money
    }
    if (next == null) return;
    if (jsonEncode(next.toJson()) == jsonEncode(move.steps.toJson())) return;
    all[id] = move.copyWith(steps: next);
    _save();
  }

  /// Whether a Retry of move [id] is running.
  static bool retrying(String id) => _retrying.contains(id);

  /// Marks a Retry of [id] as running; false when one already is (a
  /// second tap never pulls twice).
  static bool beginRetry(String id) {
    final added = _retrying.add(id);
    if (added) revision.value++;
    return added;
  }

  static void endRetry(String id) {
    if (_retrying.remove(id)) revision.value++;
  }
}

/// `multi_source_move_retry_tapped`: Retry on a partly pulled move, with
/// what was left to pull.
void trackMultiSourceMoveRetry(double remainingUsd) =>
    TrackingService.track('multi_source_move_retry_tapped', params: {
      'remaining_usd': (remainingUsd * 100).round() / 100,
    });

/// Every move, newest first, rebuilt whenever one changes.
final multiSourceMovesProvider =
    NotifierProvider<MultiSourceMovesNotifier, List<MultiSourceMove>>(
        MultiSourceMovesNotifier.new);

class MultiSourceMovesNotifier extends Notifier<List<MultiSourceMove>> {
  @override
  List<MultiSourceMove> build() {
    void changed() => state = MultiSourceMoveStore.all();
    MultiSourceMoveStore.revision.addListener(changed);
    ref.onDispose(() => MultiSourceMoveStore.revision.removeListener(changed));
    return MultiSourceMoveStore.all();
  }
}
