// lib/services/one_balance/pending_bitcoin_purchase.dart
//
// The last step of a "Buy bitcoin" whose venue cash came home to Dollars
// first: once every leg is SUBMITTED the Move sheet closes, and the
// purchase from Dollars finishes here, in the background, whether or not
// the sheet is still open (founder decision 15 October 2026: "once the
// order is placed, we should just exit").
//
//  * [BitcoinPurchaseFinisher.start] takes the Buy's ONE approval (its
//    grant, 30 min, `DirectLegGrants.buyBitcoin`), waits for Dollars to
//    hold what the purchase takes from them, then buys
//    ([buyBitcoinFromDollars]) under that same approval: no second prompt.
//  * Every purchase is recorded ([PendingBitcoinPurchaseStore], the
//    settings box, like the move records) until it is sent, so an app
//    restart never loses it. A grant lives in memory only: after a
//    restart, an expired approval, a declined or failed purchase, the
//    record waits on the person ([BitcoinPurchaseFinisher.waitingOnApproval])
//    and the move's Activity row says plainly "Your $X is in Dollars. Tap
//    to buy Bitcoin"; one tap asks a fresh approval and finishes it. The
//    money never sits silently in Dollars.
//  * Nothing is bought twice: the record is marked the moment the dollars
//    are handed to the send ([PendingPurchaseStage.funding]); from then on
//    the settlement pipeline owns the order and the record goes.
//
// No address, no key, no id in the record beyond the move's own local id:
// a dollar amount, a stage, a time.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show ValueNotifier, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/helpers/auth_grant.dart' show AuthGrant;
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider;
import 'package:kute/services/background_sync_service.dart';
import 'package:kute/services/funding/settlement_runner.dart'
    show SettlementStepUpHook;
import 'package:kute/services/one_balance/buy_bitcoin_steps.dart';
import 'package:kute/services/one_balance/multi_source_move.dart';
import 'package:kute/services/one_balance/money_steps.dart';
import 'package:kute/services/one_balance/dollars_to_bitcoin_purchase.dart';
import 'package:kute/services/one_balance/dollars_to_bitcoin_minimum.dart';
import 'package:kute/services/tracking_service.dart';

/// Where a pending purchase stands.
enum PendingPurchaseStage {
  /// Waiting for the dollars that came home to land.
  waiting,

  /// Asking the quote; nothing has left Dollars.
  buying,

  /// The dollars were handed to the send: the settlement owns it now.
  funding,

  /// Waiting on the person: the approval ran out, was declined, or the
  /// purchase stopped before anything moved.
  needsApproval,
}

/// One purchase from Dollars a Buy bitcoin still owes.
class PendingBitcoinPurchase {
  const PendingBitcoinPurchase({
    required this.moveId,
    required this.usd,
    required this.createdAt,
    this.walletId,
    this.stage = PendingPurchaseStage.waiting,
    this.legacy = false,
  });

  /// The Buy's move (`MultiSourceMove.id`): the purchase is its last step.
  final String moveId;
  final String? walletId;

  /// What the purchase takes from Dollars.
  final double usd;
  final DateTime createdAt;
  final PendingPurchaseStage stage;

  /// Made from a move that had no record (an older build tied the
  /// purchase to the open sheet): it is offered only while Dollars hold
  /// all of it.
  final bool legacy;

  PendingBitcoinPurchase copyWith({PendingPurchaseStage? stage, double? usd}) =>
      PendingBitcoinPurchase(
        moveId: moveId,
        walletId: walletId,
        usd: usd ?? this.usd,
        createdAt: createdAt,
        stage: stage ?? this.stage,
        legacy: legacy,
      );

  Map<String, dynamic> toJson() => {
        'moveId': moveId,
        if (walletId != null) 'walletId': walletId,
        'usd': usd,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'stage': stage.name,
        if (legacy) 'legacy': true,
      };

  static PendingBitcoinPurchase? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['moveId'];
    final usd = raw['usd'];
    final at = raw['createdAt'];
    if (id is! String || usd is! num || at is! int) return null;
    return PendingBitcoinPurchase(
      moveId: id,
      walletId: raw['walletId'] as String?,
      usd: usd.toDouble(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(at),
      stage: PendingPurchaseStage.values
              .where((s) => s.name == raw['stage'])
              .firstOrNull ??
          PendingPurchaseStage.needsApproval,
      legacy: raw['legacy'] == true,
    );
  }
}

/// The records, in memory and (best effort) in the settings box.
abstract final class PendingBitcoinPurchaseStore {
  static const String key =
      'pending_btc_purchases_v1'; // gitleaks:allow (Hive key name)

  /// How many records are kept.
  static const int keep = 20;

  /// Bumped on every change, so the Activity rows rebuild.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Map<String, PendingBitcoinPurchase>? _held;

  static Map<String, PendingBitcoinPurchase> _all() {
    final held = _held;
    if (held != null) return held;
    final loaded = <String, PendingBitcoinPurchase>{};
    try {
      if (Hive.isBoxOpen('settings')) {
        final raw = Hive.box('settings').get(key);
        if (raw is String) {
          final list = jsonDecode(raw);
          if (list is List) {
            for (final v in list) {
              final p = PendingBitcoinPurchase.fromJson(v);
              if (p != null) loaded[p.moveId] = p;
            }
          }
        }
      }
    } catch (_) {/* unreadable: this session starts empty */}
    return _held = loaded;
  }

  static void _save() {
    final list = all();
    try {
      if (Hive.isBoxOpen('settings')) {
        Hive.box('settings')
            .put(key, jsonEncode([for (final p in list) p.toJson()]));
      }
    } catch (_) {/* best effort: memory still holds them */}
    revision.value++;
  }

  /// Every record, newest first.
  static List<PendingBitcoinPurchase> all() => _all().values.toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  static PendingBitcoinPurchase? get(String moveId) => _all()[moveId];

  static void put(PendingBitcoinPurchase p) {
    final all = _all();
    all[p.moveId] = p;
    final sorted = PendingBitcoinPurchaseStore.all();
    for (final old in sorted.skip(keep)) {
      all.remove(old.moveId);
    }
    _save();
  }

  static void stage(String moveId, PendingPurchaseStage stage) {
    final p = _all()[moveId];
    if (p == null) return;
    put(p.copyWith(stage: stage));
  }

  static void remove(String moveId) {
    if (_all().remove(moveId) != null) _save();
  }

  /// Drops the in-memory copy so the next read loads the box again: what
  /// an app restart sees.
  @visibleForTesting
  static void reload() => _held = null;

  @visibleForTesting
  static void reset() {
    _held = {};
    revision.value++;
  }
}

/// Buys [usd] of bitcoin from Dollars under [stepUp] as the last step of
/// move [moveId]; calls [onFunding] the moment the dollars are handed to
/// the send.
typedef PendingPurchaseBuy = Future<void> Function(
  double usd,
  SettlementStepUpHook stepUp, {
  required String moveId,
  required void Function() onFunding,
});

/// How a background purchase ended.
enum PendingPurchaseEnd {
  /// Sent: the bitcoin is on its way.
  bought,

  /// Waiting on the person's tap (the money is in Dollars).
  needsApproval,

  /// Stopped after the dollars were handed to the send: the settlement
  /// pipeline reports the order's outcome.
  handedToSettlement,

  /// Below minimum and never sent: retained in Dollars.
  skipped,
}

/// Finishes the purchases a Buy bitcoin left to the background. See the
/// file header.
class BitcoinPurchaseFinisher {
  BitcoinPurchaseFinisher({
    required double Function() readDollars,
    required PendingPurchaseBuy buy,
    void Function()? nudge,
    Future<void> Function(double)? preflight,
    DateTime Function()? clock,
    Future<void> Function(Duration)? sleep,
    this.pollEvery = const Duration(seconds: 3),
    this.nudgeEvery = const Duration(seconds: 20),
  })  : _readDollars = readDollars,
        _buy = buy,
        _nudge = nudge,
        _preflight = preflight,
        _clock = clock ?? DateTime.now,
        _sleep = sleep ?? ((d) => Future<void>.delayed(d));

  final double Function() _readDollars;
  final PendingPurchaseBuy _buy;
  final void Function()? _nudge;
  final Future<void> Function(double)? _preflight;
  final DateTime Function() _clock;
  final Future<void> Function(Duration) _sleep;

  /// How often the wait reads Dollars.
  final Duration pollEvery;

  /// How often the wait asks the wallet to sync.
  final Duration nudgeEvery;

  final Map<String, Future<PendingPurchaseEnd>> _running = {};

  /// Whether move [moveId]'s purchase is running now (waiting or buying).
  bool running(String moveId) => _running.containsKey(moveId);

  /// Move [moveId]'s purchase when it waits on the person's tap: recorded,
  /// not running (after a restart no approval survives), and nothing has
  /// left Dollars for it.
  PendingBitcoinPurchase? waitingOnApproval(String moveId) {
    final p = PendingBitcoinPurchaseStore.get(moveId);
    if (p == null || running(moveId)) return null;
    if (p.stage == PendingPurchaseStage.funding) return null;
    final move = MultiSourceMoveStore.get(moveId);
    if (move != null &&
        move.finalOperationId == null &&
        BuyBitcoinSteps.of(move).byId(BuyBitcoinSteps.buyId)?.ref == null &&
        DollarsToBitcoinMinimum.belowFloor(
            BigInt.from((p.usd * 1e6).round()))) {
      return null;
    }
    return p;
  }

  /// Buys [usd] of bitcoin from Dollars as the last step of move [moveId],
  /// under [grant] (the Buy's one approval, or the fresh one a tap on the
  /// Activity row asked: [resumed]; [legacy] when that move had no record
  /// of its own). Waits for Dollars to hold [usd] while
  /// the approval lives, then buys. The record is written first, so a
  /// restart finds it. A second call for a purchase already running joins
  /// it (its [grant] is revoked).
  Future<PendingPurchaseEnd> start({
    required String moveId,
    required double usd,
    required AuthGrant grant,
    String? walletId,
    bool resumed = false,
    bool legacy = false,
  }) {
    final already = _running[moveId];
    if (already != null) {
      grant.revoke();
      return already;
    }
    final existing = PendingBitcoinPurchaseStore.get(moveId);
    final isLegacy = legacy || (existing?.legacy ?? false);
    PendingBitcoinPurchaseStore.put(PendingBitcoinPurchase(
      moveId: moveId,
      walletId: walletId ?? existing?.walletId,
      usd: usd,
      createdAt: existing?.createdAt ?? _clock(),
      legacy: isLegacy,
    ));
    final run = _run(moveId, usd, grant, resumed: resumed, legacy: isLegacy);
    _running[moveId] = run;
    PendingBitcoinPurchaseStore.revision.value++;
    return run.whenComplete(() {
      _running.remove(moveId);
      PendingBitcoinPurchaseStore.revision.value++;
    });
  }

  bool _live(AuthGrant grant) =>
      !grant.revoked && !grant.consumed && !grant.isExpiredAt(_clock());

  Future<PendingPurchaseEnd> _run(String moveId, double usd, AuthGrant grant,
      {required bool resumed, required bool legacy}) async {
    final started = _clock();
    var funded = false;
    void track(String outcome, {String? reason}) =>
        TrackingService.track('move_purchase_finished', params: {
          'outcome': outcome,
          if (reason != null) 'reason': reason,
          'amount_usd': (usd * 100).round() / 100,
          'waited_ms': _clock().difference(started).inMilliseconds,
          'resumed': resumed,
          if (legacy) 'legacy': true,
        });
    PendingPurchaseEnd waitOnPerson(String reason) {
      PendingBitcoinPurchaseStore.stage(
          moveId, PendingPurchaseStage.needsApproval);
      // The move's purchase step waits on the person's tap.
      BuyBitcoinSteps.record(moveId,
          (g) => BuyBitcoinSteps.buyStopped(g, 'needs_approval', at: _clock()));
      track('needs_approval', reason: reason);
      return PendingPurchaseEnd.needsApproval;
    }

    try {
      if (DollarsToBitcoinMinimum.belowFloor(
          BigInt.from((usd * 1e6).round()))) {
        throw const DollarsToBitcoinBelowMinimum();
      }
      final preflight = _preflight;
      if (preflight != null) await preflight(usd);
      // 1. The dollars that came home land, while the approval lives.
      var lastNudge = started;
      while (_readDollars() + 0.005 < usd) {
        if (!_live(grant)) return waitOnPerson('dollars_not_landed');
        final now = _clock();
        if (now.difference(lastNudge) >= nudgeEvery) {
          lastNudge = now;
          try {
            _nudge?.call();
          } catch (_) {}
        }
        await _sleep(pollEvery);
      }
      // What came home landed: its legs are done.
      BuyBitcoinSteps.record(
          moveId, (g) => BuyBitcoinSteps.dollarsLanded(g, at: _clock()));
      if (!_live(grant)) return waitOnPerson('approval_expired');
      // 2. The purchase, under the same approval (no second prompt).
      PendingBitcoinPurchaseStore.stage(moveId, PendingPurchaseStage.buying);
      BuyBitcoinSteps.record(
          moveId, (g) => BuyBitcoinSteps.buyStarted(g, at: _clock()));
      await _buy(usd, approvedPurchaseStepUp(grant), moveId: moveId,
          onFunding: () {
        funded = true;
        PendingBitcoinPurchaseStore.stage(moveId, PendingPurchaseStage.funding);
      });
      PendingBitcoinPurchaseStore.remove(moveId);
      track('bought');
      return PendingPurchaseEnd.bought;
    } catch (e) {
      if (funded) {
        // The dollars were handed to the send: never asked again; the
        // settlement pipeline owns the order and reports its outcome.
        PendingBitcoinPurchaseStore.remove(moveId);
        track('handed_to_settlement', reason: TrackingService.errorCategory(e));
        return PendingPurchaseEnd.handedToSettlement;
      }
      if (e is DollarsToBitcoinBelowMinimum) {
        BuyBitcoinSteps.record(
            moveId, (g) => BuyBitcoinSteps.buySkipped(g, at: _clock()));
        PendingBitcoinPurchaseStore.remove(moveId);
        track('skipped', reason: 'below_minimum');
        return PendingPurchaseEnd.skipped;
      }
      // Nothing left Dollars: the person finishes it with one tap.
      return waitOnPerson(TrackingService.errorCategory(e));
    } finally {
      grant.revoke();
    }
  }
}

/// The app's finisher. Not autoDispose: a purchase outlives every screen.
final bitcoinPurchaseFinisherProvider = Provider<BitcoinPurchaseFinisher>(
  (ref) => BitcoinPurchaseFinisher(
    readDollars: () => ref.read(usdBalanceProvider),
    preflight: (usd) => ref
        .read(dollarsToBitcoinMinimumProvider)
        .check(BigInt.from((usd * 1e6).round())),
    buy: (usd, stepUp, {required moveId, required onFunding}) =>
        buyBitcoinFromDollars(
      ref.read,
      amountBaseUnits: BigInt.from((usd * 1e6).round()),
      usd: usd,
      stepUp: stepUp,
      moveId: moveId,
      onFunding: onFunding,
    ),
    nudge: () => BackgroundSyncService().syncNow(),
  ),
);

/// Every pending purchase, rebuilt whenever one changes (the Activity row
/// of its move reads it).
final pendingBitcoinPurchasesProvider =
    NotifierProvider<PendingBitcoinPurchasesNotifier, int>(
        PendingBitcoinPurchasesNotifier.new);

class PendingBitcoinPurchasesNotifier extends Notifier<int> {
  @override
  int build() {
    void changed() => state = PendingBitcoinPurchaseStore.revision.value;
    PendingBitcoinPurchaseStore.revision.addListener(changed);
    ref.onDispose(
        () => PendingBitcoinPurchaseStore.revision.removeListener(changed));
    return PendingBitcoinPurchaseStore.revision.value;
  }
}

/// Older builds wrote an unsent sub-floor remainder as a failed purchase.
/// Only that exact shape is harmless. Sent/active purchases remain untouched.
MultiSourceMove bitcoinPurchaseMoveForDisplay(MultiSourceMove move) {
  if (!BuyBitcoinSteps.describes(move) || move.finalOperationId != null) {
    return move;
  }
  final pending = PendingBitcoinPurchaseStore.get(move.id);
  if (pending != null && pending.stage != PendingPurchaseStage.needsApproval) {
    return move;
  }
  final graph = BuyBitcoinSteps.of(move);
  final buy = graph.byId(BuyBitcoinSteps.buyId);
  if (buy == null ||
      buy.ref != null ||
      buy.status != MoneyStepStatus.failed ||
      !buy.usd.isFinite ||
      buy.usd <= 0 ||
      !DollarsToBitcoinMinimum.belowFloor(
          BigInt.from((buy.usd * 1e6).round()))) {
    return move;
  }
  return move.copyWith(steps: BuyBitcoinSteps.buySkipped(graph));
}
