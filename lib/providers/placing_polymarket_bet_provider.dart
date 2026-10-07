// lib/providers/placing_polymarket_bet_provider.dart
//
// Tracks bets while they're in-flight so the home-screen Active Predictions
// list can render a loading tile immediately — mirroring the sell flow,
// where the sheet shows "Selling..." until the CLOB confirms.
//
// This is intentionally NOT an optimistic position:
//   - We don't fake P&L, share count, or a synthetic position.
//   - We just remember the market metadata + amount + side so the UI can
//     draw a spinner tile that says "Placing $X on <market>...".
//   - The tile disappears when `polymarketTradingProvider` reports the real
//     position (matched by `tokenId`) or the placement errors out.
//
// Multiple placements in flight at once are supported: each call to
// `markPlacing` returns a unique `placementId`, and the notifier holds a
// list of all current placements. The caller uses the returned id to
// transition that specific placement to succeeded/failed/cleared without
// disturbing the others.
//
// Auto-dispose is intentional: this state shouldn't survive wallet switches.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/l10n/l10n.dart' show l10nForLanguage;
import 'package:kute/providers/settings_provider.dart';

import 'package:kute/providers/polymarket_browse_provider.dart'
    show polymarketActivePositionsProvider;

enum PlacingBetStatus { placing, succeeded, failed }

class PlacingBet {
  /// Unique id for this placement attempt. Used by the bet slip to address
  /// its own tile when markSucceeded / markFailed is called, so concurrent
  /// placements don't step on each other.
  final String placementId;
  final String tokenId;
  final String marketQuestion;
  final String? marketImage;
  final String outcomeName;
  final double amount;
  final double shares;
  final double avgPrice;
  /// Shares already held on this token before the new buy was fired. Used
  /// by the Active Predictions listener to decide when to clear the
  /// placing tile:
  ///   - Fresh bet: `preExistingShares == 0`, tile clears when any
  ///     position with matching tokenId appears.
  ///   - Buy-more on an existing position: `preExistingShares > 0`, tile
  ///     clears only when the matching position's size exceeds this
  ///     baseline (i.e. the top-up actually landed).
  final double preExistingShares;
  final PlacingBetStatus status;
  final String? errorMessage;
  final DateTime startedAt;
  /// 1-based step inside [totalSteps]. Drives the small progress bar
  /// rendered on the placing tile so the user sees granular state
  /// instead of a generic "Placing…" spinner. Bet flows that don't
  /// have multiple stages (USDC-funded bets that go straight to the
  /// CLOB) keep [totalSteps] = 1 and the bar reads "Placing order".
  final int step;
  final int totalSteps;
  final String? stepLabel;

  const PlacingBet({
    required this.placementId,
    required this.tokenId,
    required this.marketQuestion,
    this.marketImage,
    required this.outcomeName,
    required this.amount,
    required this.shares,
    required this.avgPrice,
    this.preExistingShares = 0,
    this.status = PlacingBetStatus.placing,
    this.errorMessage,
    required this.startedAt,
    this.step = 1,
    this.totalSteps = 1,
    this.stepLabel,
  });

  PlacingBet copyWith({
    PlacingBetStatus? status,
    String? errorMessage,
    int? step,
    int? totalSteps,
    String? stepLabel,
  }) =>
      PlacingBet(
        placementId: placementId,
        tokenId: tokenId,
        marketQuestion: marketQuestion,
        marketImage: marketImage,
        outcomeName: outcomeName,
        amount: amount,
        shares: shares,
        avgPrice: avgPrice,
        preExistingShares: preExistingShares,
        status: status ?? this.status,
        errorMessage: errorMessage ?? this.errorMessage,
        startedAt: startedAt,
        step: step ?? this.step,
        totalSteps: totalSteps ?? this.totalSteps,
        stepLabel: stepLabel ?? this.stepLabel,
      );
}

class PlacingPolymarketBetNotifier extends Notifier<List<PlacingBet>> {
  // One timer per placement so concurrent bets don't cancel each other's
  // watchdog/fail-clear timers.
  final Map<String, Timer> _watchdogTimers = {};
  final Map<String, Timer> _failClearTimers = {};
  int _idSeq = 0;

  @override
  List<PlacingBet> build() {
    ref.onDispose(() {
      for (final t in _watchdogTimers.values) { t.cancel(); }
      for (final t in _failClearTimers.values) { t.cancel(); }
      _watchdogTimers.clear();
      _failClearTimers.clear();
    });

    // Auto-reconcile: when real positions land, clear any placing
    // tile they satisfy. Lives in the provider (not on a screen
    // widget) so the dedup runs regardless of which screen is
    // currently mounted — previously the listener lived on Home,
    // so a user who placed a bet then sat on the Predictions screen
    // would see "1 placing · 1 open" until they navigated to Home.
    //
    // Match rule: total size across all positions for that tokenId
    // exceeds the placement's preExistingShares by > 0.005 share
    // (rounding tolerance ≈ half a cent at $1/share).
    ref.listen(polymarketActivePositionsProvider, (prev, next) {
      if (state.isEmpty) return;
      final idsToClear = <String>[];
      for (final p in state) {
        final totalForToken = next
            .where((pos) => pos.tokenId == p.tokenId)
            .fold<double>(0, (sum, pos) => sum + pos.size);
        if (totalForToken > p.preExistingShares + 0.005) {
          idsToClear.add(p.placementId);
        }
      }
      if (idsToClear.isEmpty) return;
      // Defer to next frame — Riverpod doesn't allow mutating state
      // synchronously from a listen callback that fires during
      // another provider's build.
      Future.microtask(() {
        for (final id in idsToClear) {
          clear(id);
        }
      });
    });

    return const [];
  }

  /// Register a new in-flight placement. Returns the id used to address
  /// this specific tile later (markSucceeded/markFailed/clear).
  ///
  /// Idempotent: if a placement for the same [tokenId] is still in
  /// "placing" status, returns its existing id instead of creating a
  /// second tile. Lets the pending-bet overlay register a tile early
  /// (during Orchestra routing) and the auto-fire flow re-use the same
  /// id when the order finally lands, so the user sees one continuous
  /// "Placing bet" tile instead of two stacked.
  ///
  /// [watchdogDuration] caps how long the tile can sit in "placing"
  /// status before auto-failing. Default 25s for direct CLOB submits;
  /// pass a longer value (e.g. 5 min) when registering during a
  /// BTC→USDC routing wait so Orchestra has time to deliver.
  String markPlacing({
    required String tokenId,
    required String marketQuestion,
    String? marketImage,
    required String outcomeName,
    required double amount,
    required double shares,
    required double avgPrice,
    double preExistingShares = 0,
    Duration watchdogDuration = const Duration(seconds: 25),
    int step = 1,
    int totalSteps = 1,
    String? stepLabel,
  }) {
    // Reuse existing placing tile for the same tokenId if any.
    for (final b in state) {
      if (b.tokenId == tokenId && b.status == PlacingBetStatus.placing) {
        return b.placementId;
      }
    }

    final id = '${DateTime.now().microsecondsSinceEpoch}-${_idSeq++}';
    final bet = PlacingBet(
      placementId: id,
      tokenId: tokenId,
      marketQuestion: marketQuestion,
      marketImage: marketImage,
      outcomeName: outcomeName,
      amount: amount,
      shares: shares,
      avgPrice: avgPrice,
      preExistingShares: preExistingShares,
      startedAt: DateTime.now(),
      step: step,
      totalSteps: totalSteps,
      stepLabel: stepLabel,
    );
    state = [...state, bet];

    // A timeout cannot establish whether the venue accepted the order.
    _watchdogTimers[id] = Timer(watchdogDuration, () {
      final b = _find(id);
      if (b == null || b.status != PlacingBetStatus.placing) return;
      markFailed(id, l10nForLanguage(ref.read(settingsProvider).language).betSalePendingDetail);
    });

    return id;
  }

  PlacingBet? _find(String placementId) {
    for (final b in state) {
      if (b.placementId == placementId) return b;
    }
    return null;
  }

  /// Move the placement to a different stage of its progress bar.
  /// No-op when the placement isn't found or already succeeded/failed.
  void advanceStep(String placementId, {required int step, String? label}) {
    final current = _find(placementId);
    if (current == null || current.status != PlacingBetStatus.placing) return;
    state = [
      for (final b in state)
        b.placementId == placementId
            ? b.copyWith(step: step, stepLabel: label)
            : b,
    ];
  }

  /// [holdUntilPositionArrives]: BUY flows pass true so the tile becomes a
  /// "Confirmed — appearing in your bets…" bridge that stays in the strip
  /// until the auto-reconcile listener (in [build]) sees the real position
  /// land — the Data API lags the CLOB ack by seconds to ~a minute, and
  /// clearing the tile before the card exists left a gap where the user's
  /// bet was visible nowhere. The 45 s fallback clear bounds a stuck tile
  /// (Data API outage / preExistingShares raced the first index) so it
  /// can't live forever. SELL flows keep the default short clear: a sold
  /// position *disappears* rather than arrives — there is nothing to wait
  /// for (the trading provider's optimistic removal reconciles the strip).
  void markSucceeded(
    String placementId, {
    bool holdUntilPositionArrives = false,
  }) {
    _watchdogTimers.remove(placementId)?.cancel();
    final current = _find(placementId);
    if (current == null) return;
    state = [
      for (final b in state)
        b.placementId == placementId
            // Full rebuild instead of copyWith: the bridge label must
            // REPLACE any in-flight step label ("Confirming fill…"), and
            // for the non-bridge case the stale label must be cleared so
            // the strip's succeeded branch falls back to its "Placed"
            // copy — copyWith's `?? this.stepLabel` can't null it out.
            ? PlacingBet(
                placementId: b.placementId,
                tokenId: b.tokenId,
                marketQuestion: b.marketQuestion,
                marketImage: b.marketImage,
                outcomeName: b.outcomeName,
                amount: b.amount,
                shares: b.shares,
                avgPrice: b.avgPrice,
                preExistingShares: b.preExistingShares,
                status: PlacingBetStatus.succeeded,
                errorMessage: b.errorMessage,
                startedAt: b.startedAt,
                step: b.totalSteps,
                totalSteps: b.totalSteps,
                stepLabel: holdUntilPositionArrives
                    ? l10nForLanguage(ref.read(settingsProvider).language)
                        .betConfirmedAppearing
                    : null,
              )
            : b,
    ];
    // The tile is normally removed by the auto-reconcile listener once the
    // real position lands — but the Polymarket Data API can lag by tens of
    // seconds, leaving the tile showing "Placing order" long after the order
    // actually placed (only fixed by an app reload). Auto-clear after a
    // bounded window so it never lingers; the listener still clears it
    // sooner if the position lands first (clear() cancels this timer).
    final clearAfter = holdUntilPositionArrives
        ? const Duration(seconds: 45)
        : const Duration(seconds: 4);
    _failClearTimers[placementId]?.cancel();
    _failClearTimers[placementId] = Timer(clearAfter, () {
      _failClearTimers.remove(placementId);
      final b = _find(placementId);
      if (b?.status == PlacingBetStatus.succeeded) clear(placementId);
    });
  }

  void markFailed(String placementId, String message) {
    _watchdogTimers.remove(placementId)?.cancel();
    final current = _find(placementId);
    if (current == null) return;
    state = [
      for (final b in state)
        b.placementId == placementId
            ? b.copyWith(
                status: PlacingBetStatus.failed,
                errorMessage: message,
              )
            : b,
    ];
    // Auto-clear the failed tile after a short window so the UI doesn't
    // keep a stale error forever.
    _failClearTimers[placementId]?.cancel();
    _failClearTimers[placementId] = Timer(const Duration(seconds: 6), () {
      _failClearTimers.remove(placementId);
      final b = _find(placementId);
      if (b?.status == PlacingBetStatus.failed) {
        state = state.where((x) => x.placementId != placementId).toList();
      }
    });
  }

  /// Remove a specific placement (used by the home listener when a real
  /// position has landed that corresponds to this tile).
  void clear(String placementId) {
    _watchdogTimers.remove(placementId)?.cancel();
    _failClearTimers.remove(placementId)?.cancel();
    state = state.where((b) => b.placementId != placementId).toList();
  }

  /// Remove all placements (used on dispose / wallet switch).
  void clearAll() {
    for (final t in _watchdogTimers.values) { t.cancel(); }
    for (final t in _failClearTimers.values) { t.cancel(); }
    _watchdogTimers.clear();
    _failClearTimers.clear();
    state = const [];
  }
}

final placingPolymarketBetProvider =
    NotifierProvider<PlacingPolymarketBetNotifier, List<PlacingBet>>(
  PlacingPolymarketBetNotifier.new,
);
