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

/// What the order is, in the words the screens show.
@immutable
class FundedOrderLabel {
  const FundedOrderLabel({
    required this.venue,
    required this.orderUsd,
    required this.side,
    required this.market,
    required this.marketKey,
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
  /// not_sent, maybe_sent, venue_refused, placement, interrupted.
  final String? reason;

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
      );

  FundedOrderRecord copyWith({
    FundedOrderStage? stage,
    DateTime? updatedAt,
    double? addUsd,
    Set<String>? btcRowIds,
    Set<String>? venueRowIds,
    bool? slow,
    String? reason,
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
                slow: false)
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
    // A "Tap to place" note for the same market has been acted on.
    final older = [
      for (final r in state)
        if (r.label.venue == label.venue && r.stage.active)
          r.copyWith(
              stage: FundedOrderStage.ready,
              reason: 'replaced',
              updatedAt: now)
        else if (r.label.venue == label.venue &&
            r.stage == FundedOrderStage.ready &&
            r.label.marketKey == label.marketKey)
          r.copyWith(stage: FundedOrderStage.done, updatedAt: now)
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

  /// The "Tap to place" record for the market [marketKey] on [venue].
  static FundedOrderRecord? readyOn(List<FundedOrderRecord> records,
      OneBalanceVenue venue, String marketKey, DateTime now) {
    for (final r in records) {
      if (r.label.venue == venue &&
          r.stage == FundedOrderStage.ready &&
          r.fromBitcoin &&
          r.label.marketKey == marketKey &&
          now.difference(r.updatedAt) <= readyNoteFor) {
        return r;
      }
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

final fundedOrdersProvider =
    NotifierProvider<FundedOrdersNotifier, List<FundedOrderRecord>>(
        FundedOrdersNotifier.new);
