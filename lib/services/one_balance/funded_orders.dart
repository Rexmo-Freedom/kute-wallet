// lib/services/one_balance/funded_orders.dart
//
// "This money on a rail is for THAT order." One record per order a slip
// funds (from Dollars, or from Bitcoin through Dollars), holding what the
// person is doing in words the screens can show ("Placing $5 on Yes ·
// Lakers", "Opening $5 NVDA order") and the Activity row ids of the legs
// that carry its money. The Investments header reads it to name the
// action instead of the plumbing; the slips read it to know a Bitcoin
// leg they started is still on its way (even after a restart), and to
// say "Your $X is in Investments. Tap to place." when a chain stopped
// with the money in Dollars.
//
// Persisted in the `settings` box (JSON, like `MultiSourceMoveStore`), so
// a restart keeps the rows' meaning. A record a previous process left
// running is never resumed: the order's approval lived in memory only
// (D-10), so it becomes [FundedOrderStage.ready] (the money is, or lands,
// in Dollars). Kept a day at most.
//
// Privacy: local only. The ids here are never tracked or logged.

import 'dart:convert';

import 'package:flutter/foundation.dart' show immutable, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';

/// Where a funded order is.
enum FundedOrderStage {
  /// Bitcoin → Dollars on its way ("Adding $X to Investments").
  adding,

  /// Dollars → the venue on its way ("Getting your prediction ready").
  preparing,

  /// The venue holds the money; the order is being placed.
  placing,

  /// Placed. Kept briefly, then dropped.
  done,

  /// Stopped with the money in Dollars (the order was not placed): the
  /// slip says "Tap to place".
  ready,

  /// Stopped before any money moved, or the Bitcoin came back.
  failed;

  /// Money is on a rail for the order right now.
  bool get active =>
      this == adding || this == preparing || this == placing;
}

/// Where a funded order's money is once it stopped without placing.
enum FundedMoneyAt {
  /// Still in, or back in, Dollars (the venue move never left, or the
  /// Bitcoin leg landed and stopped there): "Your $X is in Investments".
  investments,

  /// It reached the venue and stays there as its cash (available, swept
  /// home when idle): "Your $X is in Predictions" / "in Investing".
  venue,

  /// It never left, or is coming back to, Bitcoin.
  bitcoin,
}

/// What a funded record is for: an order (or bet) a slip places, or
/// margin the margin sheet adds to an isolated Investing position. Both
/// run the same funding chain; the screens name them differently.
enum FundedOrderKind { order, margin }

/// What the order is, in the words the screens show.
@immutable
class FundedOrderLabel {
  const FundedOrderLabel({
    required this.venue,
    required this.orderUsd,
    required this.side,
    required this.market,
    required this.marketKey,
    this.kind = FundedOrderKind.order,
  });

  final OneBalanceVenue venue;

  /// The bet's stake or the order's margin.
  final double orderUsd;

  /// "Yes", "Lakers", "Long", "Buy".
  final String side;

  /// A short name of the market ("Lakers vs Celtics", "NVIDIA").
  final String market;

  /// The market's own key (token id, coin), to match a slip.
  final String marketKey;

  /// An order, or margin added to a position ([orderUsd] is the margin).
  final FundedOrderKind kind;

  /// The market's name cut to [max] characters for one line.
  static String shortName(String name, {int max = 32}) {
    final t = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.length <= max) return t;
    return '${t.substring(0, max - 1).trimRight()}…';
  }

  Map<String, Object?> toJson() => {
        'venue': venue.name,
        'orderUsd': orderUsd,
        'side': side,
        'market': market,
        'marketKey': marketKey,
        if (kind != FundedOrderKind.order) 'kind': kind.name,
      };

  static FundedOrderLabel? fromJson(Object? v) {
    if (v is! Map) return null;
    final venue = OneBalanceVenue.values
        .where((e) => e.name == v['venue'])
        .firstOrNull;
    final usd = v['orderUsd'];
    if (venue == null || usd is! num) return null;
    return FundedOrderLabel(
      venue: venue,
      orderUsd: usd.toDouble(),
      side: v['side'] is String ? v['side'] as String : '',
      market: v['market'] is String ? v['market'] as String : '',
      marketKey: v['marketKey'] is String ? v['marketKey'] as String : '',
      kind: FundedOrderKind.values
              .where((e) => e.name == v['kind'])
              .firstOrNull ??
          FundedOrderKind.order,
    );
  }
}

/// One funded order.
@immutable
class FundedOrderRecord {
  const FundedOrderRecord({
    required this.id,
    required this.label,
    required this.stage,
    required this.createdAt,
    required this.updatedAt,
    this.addUsd = 0,
    this.btcRowIds = const {},
    this.venueRowIds = const {},
    this.slow = false,
    this.reason,
    this.stoppedAt,
    this.moneyAt,
    this.message,
    this.cleared = false,
  });

  final String id;
  final FundedOrderLabel label;
  final FundedOrderStage stage;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// What the Bitcoin leg adds to Investments (zero without one).
  final double addUsd;

  /// The Bitcoin → Dollars leg's Activity row ids (quote, then order).
  final Set<String> btcRowIds;

  /// The Dollars → venue move's Activity row ids (quote, then order).
  final Set<String> venueRowIds;

  /// The Bitcoin leg is taking longer than usual.
  final bool slow;

  /// Why it stopped (a fixed code, never shown): refunded, timeout,
  /// not_sent, maybe_sent, venue_refused, placement, interrupted, and for
  /// a placement the venue refused, the autofire's own code (price_moved,
  /// market_closed, funds_timeout, book_unavailable, ...).
  final String? reason;

  /// The step it stopped at ([FundedOrderStage.adding], `preparing` or
  /// `placing`): the slip marks that step failed. Null for a record that
  /// stopped with nothing to show (replaced by a newer one).
  final FundedOrderStage? stoppedAt;

  /// Where the money is now that it stopped.
  final FundedMoneyAt? moneyAt;

  /// What the venue or the rail said, in the person's language, when it
  /// stopped (shown on the slip, never tracked).
  final String? message;

  /// The person acted on the stop (a new try on the market): the slip no
  /// longer shows it.
  final bool cleared;

  bool get fromBitcoin => addUsd > 0 || btcRowIds.isNotEmpty;

  bool ownsRow(String rowId) =>
      btcRowIds.contains(rowId) || venueRowIds.contains(rowId);

  /// What the header names for money on a rail for this order.
  InFlightOrder toInFlightOrder() => InFlightOrder(
        id: id,
        venue: label.venue,
        orderUsd: label.orderUsd,
        side: label.side,
        market: label.market,
        margin: label.kind == FundedOrderKind.margin,
      );

  FundedOrderRecord copyWith({
    FundedOrderStage? stage,
    DateTime? updatedAt,
    double? addUsd,
    Set<String>? btcRowIds,
    Set<String>? venueRowIds,
    bool? slow,
    String? reason,
    FundedOrderStage? stoppedAt,
    FundedMoneyAt? moneyAt,
    String? message,
    bool? cleared,
  }) =>
      FundedOrderRecord(
        id: id,
        label: label,
        stage: stage ?? this.stage,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        addUsd: addUsd ?? this.addUsd,
        btcRowIds: btcRowIds ?? this.btcRowIds,
        venueRowIds: venueRowIds ?? this.venueRowIds,
        slow: slow ?? this.slow,
        reason: reason ?? this.reason,
        stoppedAt: stoppedAt ?? this.stoppedAt,
        moneyAt: moneyAt ?? this.moneyAt,
        message: message ?? this.message,
        cleared: cleared ?? this.cleared,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'label': label.toJson(),
        'stage': stage.name,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
        'addUsd': addUsd,
        'btcRowIds': btcRowIds.toList(),
        'venueRowIds': venueRowIds.toList(),
        'slow': slow,
        if (reason != null) 'reason': reason,
        if (stoppedAt != null) 'stoppedAt': stoppedAt!.name,
        if (moneyAt != null) 'moneyAt': moneyAt!.name,
        if (message != null) 'message': message,
        if (cleared) 'cleared': true,
      };

  static FundedOrderRecord? fromJson(Object? v) {
    if (v is! Map) return null;
    final id = v['id'];
    final label = FundedOrderLabel.fromJson(v['label']);
    final stage = FundedOrderStage.values
        .where((e) => e.name == v['stage'])
        .firstOrNull;
    final created = v['createdAt'];
    final updated = v['updatedAt'];
    if (id is! String || label == null || stage == null) return null;
    if (created is! int || updated is! int) return null;
    Set<String> ids(Object? raw) =>
        raw is List ? {for (final e in raw) if (e is String) e} : const {};
    final add = v['addUsd'];
    return FundedOrderRecord(
      id: id,
      label: label,
      stage: stage,
      createdAt: DateTime.fromMillisecondsSinceEpoch(created),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updated),
      addUsd: add is num ? add.toDouble() : 0,
      btcRowIds: ids(v['btcRowIds']),
      venueRowIds: ids(v['venueRowIds']),
      slow: v['slow'] == true,
      reason: v['reason'] is String ? v['reason'] as String : null,
      stoppedAt: FundedOrderStage.values
          .where((e) => e.name == v['stoppedAt'])
          .firstOrNull,
      moneyAt:
          FundedMoneyAt.values.where((e) => e.name == v['moneyAt']).firstOrNull,
      message: v['message'] is String ? v['message'] as String : null,
      cleared: v['cleared'] == true,
    );
  }
}

/// The funded orders, newest first, persisted.
class FundedOrdersNotifier extends Notifier<List<FundedOrderRecord>> {
  static const String key = 'funded_orders_v1';

  /// How many records are kept.
  static const int keep = 40;

  /// No record outlives this.
  static const Duration maxAge = Duration(hours: 24);

  /// How long a "ready" record still shows its note on the slip.
  static const Duration readyNoteFor = Duration(hours: 1);

  /// Test seam: the clock records are stamped with.
  static DateTime Function() clock = DateTime.now;

  /// Test seam: persistence off (tests without a Hive box).
  @visibleForTesting
  static bool persist = true;

  static int _seq = 0;

  @override
  List<FundedOrderRecord> build() {
    final loaded = <FundedOrderRecord>[];
    try {
      if (persist && Hive.isBoxOpen('settings')) {
        final raw = Hive.box('settings').get(key);
        if (raw is String) {
          final list = jsonDecode(raw);
          if (list is List) {
            for (final v in list) {
              final r = FundedOrderRecord.fromJson(v);
              if (r != null) loaded.add(r);
            }
          }
        }
      }
    } catch (_) {/* unreadable: this session starts empty */}
    final now = clock();
    // A record a previous process left running never resumes: its
    // approval was memory only. Its money is (or lands) in Dollars.
    return _pruned([
      for (final r in loaded)
        r.stage.active
            ? r.copyWith(
                stage: FundedOrderStage.ready,
                reason: 'interrupted',
                updatedAt: now,
                slow: false,
                // The slip shows the step it was on and that the money is
                // (or lands) in Investments.
                stoppedAt: r.stage,
                moneyAt: FundedMoneyAt.investments)
            : r,
    ], now);
  }

  static List<FundedOrderRecord> _pruned(
      List<FundedOrderRecord> records, DateTime now) {
    final kept = records
        .where((r) => now.difference(r.updatedAt) <= maxAge)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return kept.length > keep ? kept.sublist(0, keep) : kept;
  }

  void _set(List<FundedOrderRecord> records) {
    state = _pruned(records, clock());
    if (!persist) return;
    try {
      if (Hive.isBoxOpen('settings')) {
        Hive.box('settings')
            .put(key, jsonEncode([for (final r in state) r.toJson()]));
      }
    } catch (_) {/* best effort: memory still holds them */}
  }

  /// A new record for [label] at [stage]; returns its id.
  String start(FundedOrderLabel label,
      {required FundedOrderStage stage,
      double addUsd = 0,
      Set<String> venueRowIds = const {}}) {
    final now = clock();
    final id = 'fo_${now.microsecondsSinceEpoch}_${_seq++}';
    // One live record per venue: an older one still marked live is over.
    // A "Tap to place" note for the same market and kind has been acted on.
    final older = [
      for (final r in state)
        if (r.label.venue == label.venue && r.stage.active)
          r.copyWith(
              stage: FundedOrderStage.ready,
              reason: 'replaced',
              updatedAt: now)
        else if (r.label.venue == label.venue &&
            r.stage == FundedOrderStage.ready &&
            r.label.marketKey == label.marketKey &&
            r.label.kind == label.kind)
          r.copyWith(
              stage: FundedOrderStage.done, updatedAt: now, cleared: true)
        else if (r.label.venue == label.venue &&
            r.stage == FundedOrderStage.failed &&
            !r.cleared &&
            r.label.marketKey == label.marketKey &&
            r.label.kind == label.kind)
          // A new try on the market: the earlier stop is acted on.
          r.copyWith(cleared: true, updatedAt: now)
        else
          r,
    ];
    _set([
      FundedOrderRecord(
        id: id,
        label: label,
        stage: stage,
        createdAt: now,
        updatedAt: now,
        addUsd: addUsd,
        venueRowIds: venueRowIds,
      ),
      ...older,
    ]);
    return id;
  }

  FundedOrderRecord? byId(String id) {
    for (final r in state) {
      if (r.id == id) return r;
    }
    return null;
  }

  void update(String id,
      FundedOrderRecord Function(FundedOrderRecord current) change) {
    var hit = false;
    final next = [
      for (final r in state)
        if (r.id == id)
          () {
            hit = true;
            return change(r).copyWith(updatedAt: clock());
          }()
        else
          r,
    ];
    if (hit) _set(next);
  }

  void setStage(String id, FundedOrderStage stage, {String? reason}) =>
      update(id, (r) => r.copyWith(stage: stage, reason: reason));

  /// [id] stopped without placing: [stage] (failed, or ready when the
  /// money waits in Dollars for a tap), the step it stopped at (the one
  /// it was on), where the money is and what was said. A record already
  /// ended keeps its end.
  void stop(
    String id, {
    required FundedOrderStage stage,
    required String reason,
    FundedMoneyAt? moneyAt,
    String? message,
  }) =>
      update(id, (r) {
        if (!r.stage.active) return r;
        return r.copyWith(
          stage: stage,
          reason: reason,
          slow: false,
          stoppedAt: r.stage,
          moneyAt: moneyAt,
          message: message,
        );
      });

  /// The person acted on [id]'s stop (tried again, or it no longer
  /// applies): the slip stops showing it.
  void clearStop(String id) => update(id, (r) => r.copyWith(cleared: true));

  void addBtcRow(String id, String rowId) {
    if (rowId.isEmpty) return;
    update(id, (r) => r.copyWith(btcRowIds: {...r.btcRowIds, rowId}));
  }

  void addVenueRow(String id, String rowId) {
    if (rowId.isEmpty) return;
    update(id, (r) => r.copyWith(venueRowIds: {...r.venueRowIds, rowId}));
  }

  /// Drops [id] (the slip used the note, or the order was placed).
  void remove(String id) => _set([
        for (final r in state)
          if (r.id != id) r,
      ]);

  /// The live funded order on [venue], if any.
  FundedOrderRecord? activeOn(OneBalanceVenue venue) =>
      activeOf(state, venue);

  static FundedOrderRecord? activeOf(
      List<FundedOrderRecord> records, OneBalanceVenue venue) {
    for (final r in records) {
      if (r.label.venue == venue && r.stage.active) return r;
    }
    return null;
  }

  /// The "Tap to place" record for the market [marketKey] on [venue]
  /// ([kind]: an order's for the slips, margin's for the margin sheet).
  static FundedOrderRecord? readyOn(List<FundedOrderRecord> records,
      OneBalanceVenue venue, String marketKey, DateTime now,
      {FundedOrderKind kind = FundedOrderKind.order}) {
    for (final r in records) {
      if (r.label.venue == venue &&
          r.stage == FundedOrderStage.ready &&
          r.fromBitcoin &&
          !r.cleared &&
          r.label.kind == kind &&
          r.label.marketKey == marketKey &&
          now.difference(r.updatedAt) <= readyNoteFor) {
        return r;
      }
    }
    return null;
  }

  /// How long a placed record still shows its finished steps.
  static const Duration doneStepsFor = Duration(seconds: 4);

  /// How long a stopped record still shows its failed step on the slip.
  static const Duration stopStepsFor = Duration(minutes: 30);

  /// The staged progress a slip shows for the market [marketKey] on
  /// [venue] ([kind]: an order's, or margin's): the newest record for it,
  /// while its money is on a rail, just after it placed, or once it
  /// stopped (until the person tries again). Null when there is nothing
  /// to show.
  static FundedProgress? progressOn(List<FundedOrderRecord> records,
      OneBalanceVenue venue, String marketKey, DateTime now,
      {FundedOrderKind kind = FundedOrderKind.order}) {
    for (final r in records) {
      if (r.label.venue != venue ||
          r.label.kind != kind ||
          r.label.marketKey != marketKey) {
        continue;
      }
      final age = now.difference(r.updatedAt);
      if (r.stage.active) return FundedProgress(r);
      if (r.cleared) return null;
      if (r.stage == FundedOrderStage.done) {
        return age <= doneStepsFor ? FundedProgress(r) : null;
      }
      if (r.stoppedAt != null && age <= stopStepsFor) {
        return FundedProgress(r);
      }
      return null;
    }
    return null;
  }

  /// The record that owns the Activity row [rowId], when its order is
  /// still live (so a line may name the order).
  static FundedOrderRecord? liveOwnerOf(
      List<FundedOrderRecord> records, String rowId) {
    for (final r in records) {
      if (r.stage.active && r.ownsRow(rowId)) return r;
    }
    return null;
  }

  /// The venue whose Bitcoin leg row [rowId] is, for any record still
  /// kept (a restart's ready record included): a slip counts that row as
  /// its own deposit on its way.
  static OneBalanceVenue? btcRowVenue(
      List<FundedOrderRecord> records, String rowId) {
    for (final r in records) {
      if (r.btcRowIds.contains(rowId)) return r.label.venue;
    }
    return null;
  }
}

/// A funded record as a slip's steps: the Bitcoin leg ("Adding $X to
/// Investments", only with one), the move ("Getting your prediction
/// ready"), the placement ("Placing $Y on Yes"), and where it is.
@immutable
class FundedProgress {
  const FundedProgress(this.record);

  final FundedOrderRecord record;

  bool get withBitcoin => record.fromBitcoin;

  /// How many steps the slip lists: three with a Bitcoin leg, else two.
  int get stepCount => withBitcoin ? 3 : 2;

  int _indexOf(FundedOrderStage stage) {
    final offset = withBitcoin ? 0 : 1;
    final i = switch (stage) {
      FundedOrderStage.adding => 0,
      FundedOrderStage.preparing => 1,
      FundedOrderStage.placing => 2,
      _ => 3,
    };
    return (i - offset).clamp(0, stepCount);
  }

  /// Placed: every step done.
  bool get done => record.stage == FundedOrderStage.done;

  /// Stopped without placing: the [active] step failed.
  bool get failed =>
      !record.stage.active && !done && record.stoppedAt != null;

  /// The step running now (or the one that failed); [stepCount] once
  /// every step is done.
  int get active {
    if (failed) return _indexOf(record.stoppedAt!).clamp(0, stepCount - 1);
    if (done) return stepCount;
    return _indexOf(record.stage);
  }

  /// How far along it is, 0..1, for the slip's tension: each step a
  /// share, the last step reaching 0.9 (1 is the placement itself).
  double get progress {
    if (done) return 1;
    return 0.9 * (active + 1) / stepCount;
  }
}

final fundedOrdersProvider =
    NotifierProvider<FundedOrdersNotifier, List<FundedOrderRecord>>(
        FundedOrdersNotifier.new);
