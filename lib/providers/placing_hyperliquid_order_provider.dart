// lib/providers/placing_hyperliquid_order_provider.dart
//
// Tracks Hyperliquid orders while they're in flight so the Trading tab's
// active-positions strip (and the home pill badge) can render a loading
// tile immediately — a line-for-line adaptation of
// placing_polymarket_bet_provider.dart.
//
// This is intentionally NOT an optimistic position:
//   - We don't fake PnL, entry price, or a synthetic HlPerpPosition.
//   - We just remember coin + side + margin + leverage so the UI can
//     draw a spinner tile that says "Opening 5x BTC long…".
//   - The tile disappears when the real position lands (reconciled
//     against the account snapshot), when the WS userFills event
//     confirms the fill, or when the placement errors out.
//
// Multiple placements in flight at once are supported: each `markPlacing`
// returns a unique `placementId` the caller uses to transition that
// specific tile without disturbing the others.
//
// Reconciliation is PUSH-based, not a ref.listen on the positions
// provider: `HlAccountNotifier` calls [reconcileWithPositions] after
// every snapshot fetch. Polymarket wires this the other way (the placing
// provider listens to the positions provider), but this provider is
// non-autoDispose and watched by the home pill — a build-time listen
// would pin `hyperliquidAccountProvider` (address derivation + API
// polling) alive for EVERY user from app start, which the design
// explicitly forbids for non-HL users. Push keeps the dependency arrow
// pointing at the cheap side.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/models/hyperliquid_market.dart';

enum PlacingHlOrderStatus { placing, succeeded, failed }

class PlacingHlOrder {
  /// Unique id for this placement attempt. Used by the order slip to
  /// address its own tile when markSucceeded / markFailed is called, so
  /// concurrent placements don't step on each other.
  final String placementId;
  final String coin;

  /// Human label for the tile ("BTC-PERP", "TSLA"…). Display-only.
  final String marketLabel;

  /// Long/buy = true, short/sell = false. Spot buys register as long.
  final bool isLong;
  final double marginUsd;

  /// 1 for spot orders.
  final int leverage;

  /// Size (base units) the order asked for.
  final double sizeRequested;

  /// SIGNED position size (szi) held on this coin before the new order
  /// was fired. Used by the reconcile pass to decide when the tile can
  /// clear:
  ///   - fresh position: preExistingSize == 0, clears when szi moves in
  ///     the placed direction;
  ///   - add-to-position: clears only when szi exceeds this baseline in
  ///     the placed direction (the top-up actually landed).
  final double preExistingSize;
  final PlacingHlOrderStatus status;
  final String? errorMessage;
  final DateTime startedAt;

  /// 1-based step inside [totalSteps]. Drives the small progress bar on
  /// the placing tile (e.g. "Adjusting leverage" → "Placing order").
  /// Direct submits keep [totalSteps] = 1.
  final int step;
  final int totalSteps;
  final String? stepLabel;

  /// Client order id sent with the exchange submit, when known. Lets the
  /// user-events provider match a WS fill to this exact tile instead of
  /// falling back to coin+side.
  final String? cloid;

  const PlacingHlOrder({
    required this.placementId,
    required this.coin,
    required this.marketLabel,
    required this.isLong,
    required this.marginUsd,
    required this.leverage,
    required this.sizeRequested,
    this.preExistingSize = 0,
    this.status = PlacingHlOrderStatus.placing,
    this.errorMessage,
    required this.startedAt,
    this.step = 1,
    this.totalSteps = 1,
    this.stepLabel,
    this.cloid,
  });

  PlacingHlOrder copyWith({
    PlacingHlOrderStatus? status,
    String? errorMessage,
    int? step,
    int? totalSteps,
    String? stepLabel,
    String? cloid,
  }) =>
      PlacingHlOrder(
        placementId: placementId,
        coin: coin,
        marketLabel: marketLabel,
        isLong: isLong,
        marginUsd: marginUsd,
        leverage: leverage,
        sizeRequested: sizeRequested,
        preExistingSize: preExistingSize,
        status: status ?? this.status,
        errorMessage: errorMessage ?? this.errorMessage,
        startedAt: startedAt,
        step: step ?? this.step,
        totalSteps: totalSteps ?? this.totalSteps,
        stepLabel: stepLabel ?? this.stepLabel,
        cloid: cloid ?? this.cloid,
      );
}

class PlacingHyperliquidOrderNotifier extends Notifier<List<PlacingHlOrder>> {
  // One timer per placement so concurrent orders don't cancel each
  // other's watchdog/fail-clear timers.
  final Map<String, Timer> _watchdogTimers = {};
  final Map<String, Timer> _failClearTimers = {};
  int _idSeq = 0;

  @override
  List<PlacingHlOrder> build() {
    ref.onDispose(() {
      for (final t in _watchdogTimers.values) {
        t.cancel();
      }
      for (final t in _failClearTimers.values) {
        t.cancel();
      }
      _watchdogTimers.clear();
      _failClearTimers.clear();
    });
    return const [];
  }

  /// Register a new in-flight placement. Returns the id used to address
  /// this specific tile later (markSucceeded/markFailed/clear).
  ///
  /// Idempotent: if a placement for the same [coin]+[isLong] is still in
  /// "placing" status, returns its existing id instead of creating a
  /// second tile. Lets the pending-order overlay register a tile early
  /// (while waiting for a deposit) and the auto-fire flow re-use the same
  /// id when the order finally lands, so the user sees one continuous
  /// "Opening position" tile instead of two stacked.
  ///
  /// [watchdogDuration] caps how long the tile can sit in "placing"
  /// status before auto-failing. Default 25 s for direct exchange
  /// submits; pass a longer value (e.g. 5 min) when registering during a
  /// deposit/funding wait so the credit has time to land.
  String markPlacing({
    required String coin,
    required String marketLabel,
    required bool isLong,
    required double marginUsd,
    required int leverage,
    required double sizeRequested,
    double preExistingSize = 0,
    Duration watchdogDuration = const Duration(seconds: 25),
    int step = 1,
    int totalSteps = 1,
    String? stepLabel,
    String? cloid,
  }) {
    // Reuse the existing placing tile for the same coin+side if any.
    for (final o in state) {
      if (o.coin == coin &&
          o.isLong == isLong &&
          o.status == PlacingHlOrderStatus.placing) {
        return o.placementId;
      }
    }

    final id = '${DateTime.now().microsecondsSinceEpoch}-${_idSeq++}';
    final order = PlacingHlOrder(
      placementId: id,
      coin: coin,
      marketLabel: marketLabel,
      isLong: isLong,
      marginUsd: marginUsd,
      leverage: leverage,
      sizeRequested: sizeRequested,
      preExistingSize: preExistingSize,
      startedAt: DateTime.now(),
      step: step,
      totalSteps: totalSteps,
      stepLabel: stepLabel,
      cloid: cloid,
    );
    state = [...state, order];

    // Stop the spinner after the watchdog interval. A timeout does not
    // prove no fill occurred; null selects the UI's unconfirmed-result copy.
    _watchdogTimers[id] = Timer(watchdogDuration, () {
      final o = _find(id);
      if (o == null || o.status != PlacingHlOrderStatus.placing) return;
      markFailed(id, null);
    });

    return id;
  }

  PlacingHlOrder? _find(String placementId) {
    for (final o in state) {
      if (o.placementId == placementId) return o;
    }
    return null;
  }

  /// Attach the exchange cloid to a tile once the submit has one (the
  /// slip registers the tile before the order is signed).
  void attachCloid(String placementId, String cloid) {
    final current = _find(placementId);
    if (current == null) return;
    state = [
      for (final o in state)
        o.placementId == placementId ? o.copyWith(cloid: cloid) : o,
    ];
  }

  /// Move the placement to a different stage of its progress bar.
  /// No-op when the placement isn't found or already succeeded/failed.
  void advanceStep(String placementId, {required int step, String? label}) {
    final current = _find(placementId);
    if (current == null || current.status != PlacingHlOrderStatus.placing) {
      return;
    }
    state = [
      for (final o in state)
        o.placementId == placementId
            ? o.copyWith(step: step, stepLabel: label)
            : o,
    ];
  }

  void markSucceeded(String placementId) {
    _watchdogTimers.remove(placementId)?.cancel();
    final current = _find(placementId);
    if (current == null) return;
    state = [
      for (final o in state)
        o.placementId == placementId
            ? o.copyWith(status: PlacingHlOrderStatus.succeeded)
            : o,
    ];
    // The tile is normally removed by the reconcile pass once the real
    // position lands in the account snapshot — but that snapshot can lag
    // the fill by a poll tick or two. Auto-clear shortly after success so
    // it never lingers; reconcile still clears it sooner if the position
    // lands first (clear() cancels this timer).
    _failClearTimers[placementId]?.cancel();
    _failClearTimers[placementId] = Timer(const Duration(seconds: 4), () {
      _failClearTimers.remove(placementId);
      final o = _find(placementId);
      if (o?.status == PlacingHlOrderStatus.succeeded) clear(placementId);
    });
  }

  /// Success path used by the WS user-events provider: a live fill for
  /// [coin] arrived. Matches on cloid when both sides have one, else on
  /// coin (+ side when derivable from the fill). No-op when nothing
  /// matches — fills for positions opened outside a tracked placement
  /// are normal.
  void markSucceededByFill({required String coin, String? cloid}) {
    for (final o in state) {
      if (o.status != PlacingHlOrderStatus.placing) continue;
      if (o.coin != coin) continue;
      if (cloid != null && o.cloid != null && o.cloid != cloid) continue;
      markSucceeded(o.placementId);
    }
  }

  void markFailed(String placementId, String? message) {
    _watchdogTimers.remove(placementId)?.cancel();
    final current = _find(placementId);
    if (current == null) return;
    state = [
      for (final o in state)
        o.placementId == placementId
            ? o.copyWith(
                status: PlacingHlOrderStatus.failed,
                errorMessage: message,
              )
            : o,
    ];
    // Auto-clear the failed tile after a short window so the UI doesn't
    // keep a stale error forever.
    _failClearTimers[placementId]?.cancel();
    _failClearTimers[placementId] = Timer(const Duration(seconds: 6), () {
      _failClearTimers.remove(placementId);
      final o = _find(placementId);
      if (o?.status == PlacingHlOrderStatus.failed) {
        state = state.where((x) => x.placementId != placementId).toList();
      }
    });
  }

  /// Reconcile against a fresh account snapshot: clear every placing
  /// tile whose position delta has landed. Called by `HlAccountNotifier`
  /// after each successful fetch (see file header for why this is push,
  /// not ref.listen). Mirrors the Polymarket listener body: match when
  /// the SIGNED size for the coin moved past `preExistingSize` in the
  /// placed direction by more than a rounding tolerance.
  void reconcileWithPositions(List<HlPerpPosition> positions) {
    if (state.isEmpty) return;
    final idsToClear = <String>[];
    for (final o in state) {
      double szi = 0;
      for (final p in positions) {
        if (p.coin == o.coin) {
          szi = p.szi;
          break;
        }
      }
      final delta = szi - o.preExistingSize;
      final tolerance = math.max(1e-9, o.sizeRequested * 0.001);
      final landed = o.isLong ? delta > tolerance : delta < -tolerance;
      if (landed) idsToClear.add(o.placementId);
    }
    if (idsToClear.isEmpty) return;
    // Defer to the next microtask — the caller may be inside another
    // provider's build/refresh, and Riverpod doesn't allow mutating a
    // provider synchronously from there (same deferral as the Polymarket
    // reconcile listener).
    Future.microtask(() {
      for (final id in idsToClear) {
        clear(id);
      }
    });
  }

  /// Remove a specific placement (used by the reconcile pass when the
  /// real position has landed for this tile).
  void clear(String placementId) {
    _watchdogTimers.remove(placementId)?.cancel();
    _failClearTimers.remove(placementId)?.cancel();
    state = state.where((o) => o.placementId != placementId).toList();
  }

  /// Remove all placements (used on wallet switch).
  void clearAll() {
    for (final t in _watchdogTimers.values) {
      t.cancel();
    }
    for (final t in _failClearTimers.values) {
      t.cancel();
    }
    _watchdogTimers.clear();
    _failClearTimers.clear();
    state = const [];
  }
}

final placingHyperliquidOrderProvider =
    NotifierProvider<PlacingHyperliquidOrderNotifier, List<PlacingHlOrder>>(
  PlacingHyperliquidOrderNotifier.new,
);
