// lib/services/sync/polymarket_poll_pipeline.dart
//
// Extracted from the legacy `BackgroundSyncService._startUsdcPolling`.
// Drives an independent 30 s refresh of `polymarketTradingProvider`
// so a slow Spark / on-chain sync can't starve the USDC card on the
// home surface — historical context: missing the USDC update meant
// the user received funds and the card stayed stale until the next
// full sync (or a manual swipe).
//
// Compared to the inline `Timer.periodic` it replaces, this pipeline
// adds:
//   - Route awareness: runs only when the user is on a surface that
//     consumes Polymarket state (Home / Polymarket / its
//     sub-screens). Off those routes the timer sleeps, saving
//     RPC noise + provider rebuild churn.
//   - A clean stop/start contract that honours app-lifecycle
//     transitions through the existing `BackgroundSyncService.stop`
//     code path.
//   - A `kickNow()` hook for pull-to-refresh and post-action
//     freshness without copy-pasting the refresh call.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/providers/current_route_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/services/sync/sync_pipeline.dart';
import 'package:kute/services/sync/sync_status.dart';

class PolymarketPollPipeline implements SyncPipeline {
  PolymarketPollPipeline();

  ProviderContainer? _container;
  Timer? _timer;
  bool _refreshing = false;

  static const Duration _interval = Duration(seconds: 30);

  /// Routes on which Polymarket state is meaningful for the user. On
  /// any other route (Settings, Send/Receive flow, transaction
  /// detail, etc.) the timer is paused; we'd just be heating GC for
  /// data nobody's looking at.
  static const Set<String> _activeRoutes = <String>{
    'home',
    'polymarket',
    'active_bets',
    'bet_history',
  };

  @override
  String get debugName => 'PolymarketPollPipeline';

  @override
  void start(ProviderContainer container) {
    if (_container != null) return;
    _container = container;
    _scheduleNext();
    // Fire one immediately so a freshly-foregrounded screen sees
    // updated USDC + positions without waiting a full interval.
    Future.microtask(_tick);
  }

  @override
  void stop() {
    _timer?.cancel();
    _timer = null;
    _container = null;
    _refreshing = false;
  }

  @override
  Future<void> kickNow() async {
    if (_container == null) return;
    if (_refreshing) return;
    await _tick();
  }

  void _scheduleNext() {
    _timer?.cancel();
    _timer = Timer(_interval, _tick);
  }

  Future<void> _tick() async {
    final container = _container;
    if (container == null) return;
    if (_refreshing) {
      _scheduleNext();
      return;
    }
    if (!_routeWantsPolymarket(container)) {
      // Off-route — skip this tick, but keep the cadence going so
      // we don't hot-loop scheduling. The next refresh fires when
      // the user is back somewhere that actually needs the data.
      _scheduleNext();
      return;
    }
    _refreshing = true;
    final statusNotifier =
        container.read(syncPipelineStatusProvider.notifier);
    statusNotifier.markRunning(debugName);
    try {
      final notifier = container.read(polymarketTradingProvider.notifier);
      await notifier.refresh();
      statusNotifier.markSuccess(debugName);
    } catch (e) {
      // Silent best-effort — the UI keeps showing the last known
      // state and the next tick tries again. Status banner reads
      // this via `lastSyncFailureProvider`.
      statusNotifier.markFailure(debugName, e.toString());
    } finally {
      _refreshing = false;
      if (_container != null) _scheduleNext();
    }
  }

  bool _routeWantsPolymarket(ProviderContainer container) {
    try {
      final route = container.read(currentRouteProvider);
      if (route == null) return true; // pre-init: don't starve
      if (_activeRoutes.contains(route)) return true;
      // Named Polymarket sheets/screens ('polymarket-bet-slip',
      // 'polymarket-market-detail-sheet', ...) publish their own route
      // name while open — they consume the same state, so keep
      // polling rather than letting the balance freeze mid-bet.
      return route.startsWith('polymarket');
    } catch (_) {
      return true;
    }
  }
}
