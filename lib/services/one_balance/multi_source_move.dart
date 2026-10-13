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
//  * Records live in the settings box (best effort; this session keeps
//    them in memory either way), newest first, the last
//    [MultiSourceMoveStore.keep] only. No address, no key: venue names,
//    dollar amounts and the ids the wallet's own rows already carry.

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueNotifier, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
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
      };

  static MultiSourceMoveLeg? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final venue = OneBalanceVenue.values
        .where((v) => v.name == raw['venue'])
        .firstOrNull;
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
    final sum = dollarsUsd + okLegs.fold<double>(0, (s, l) => s + l.arrivingUsd);
    return math.min(totalUsd, _cents(sum));
  }

  /// What the legs that went straight to the destination delivered.
  double get directDeliveredUsd => _cents(okLegs
      .where((l) => l.direct)
      .fold<double>(0, (s, l) => s + l.arrivingUsd));

  /// What is still missing after a failed leg (0 when none failed).
  double get remainingUsd {
    // The action's own step went: the whole amount was there for it.
    if (failedLegs.isEmpty || finalOperationId != null) return 0;
    final left = _cents(totalUsd - deliveredUsd);
    return left > 0 ? left : 0;
  }

  /// A leg failed and part of the amount never left its venue.
  bool get partial => remainingUsd >= 0.01;

  /// What the move spent: the person's amount, or after a failed leg
  /// what Dollars gave and the legs that went took.
  double get spentUsd => partial
      ? math.min(totalUsd,
          _cents(dollarsUsd + okLegs.fold<double>(0, (s, l) => s + l.usd)))
      : totalUsd;

  /// The Activity row ids and operation ids that belong to this move.
  Set<String> get linkedIds => {
        for (final l in legs) ...[
          if (l.operationId != null) l.operationId!,
          if (l.operationId != null) 'cctp-${l.operationId}',
          if (l.quoteId != null) l.quoteId!,
        ],
        if (finalOperationId != null) finalOperationId!,
      };

  MultiSourceMove copyWith({
    List<MultiSourceMoveLeg>? legs,
    String? finalOperationId,
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
        Hive.box('settings').put(
            key, jsonEncode([for (final m in moves) m.toJson()]));
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
  static String newId() =>
      'msm_${clock().microsecondsSinceEpoch}_${_seq++}';

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

  /// Adds [leg] to move [id].
  static void addLeg(String id, MultiSourceMoveLeg leg) {
    final all = _all();
    final move = all[id];
    if (move == null) return;
    all[id] = move.copyWith(legs: [...move.legs, leg]);
    _save();
  }

  /// The action's own step went: its settlement operation is part of the
  /// move's one row.
  static void attachFinal(String? id, String? operationId) {
    if (id == null || operationId == null || operationId.isEmpty) return;
    final all = _all();
    final move = all[id];
    if (move == null) return;
    all[id] = move.copyWith(finalOperationId: operationId);
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
