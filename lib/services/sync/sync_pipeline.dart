// lib/services/sync/sync_pipeline.dart
//
// Common contract for the per-domain sync pipelines that are
// progressively replacing the singleton `BackgroundSyncService` —
// the long-term shape of the data layer is one Store + many narrowly-
// scoped pipelines, each owning their own cadence, lifecycle, and
// route policy. See the architectural plan in the session notes for
// the full picture; this file is the seed.
//
// Each pipeline:
//   - Owns its own timers / subscriptions.
//   - Decides for itself when to run based on `currentRouteProvider`
//     visibility and any per-domain freshness / WS-up signals.
//   - Writes to the Store (currently the per-domain Riverpod
//     notifiers + Hive caches).
//   - Reports lifecycle errors back via [SyncStatus] so the UI can
//     show banners without each pipeline owning its own UI hook.
//
// Pipelines are constructed once at app start (typically inside
// `BackgroundSyncService.start`) and live for the lifetime of the
// session. They DO NOT depend on each other — a failure in one
// pipeline (Polymarket API down) doesn't block another (Spark
// stream still pushes).

import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class SyncPipeline {
  /// Begin running. Idempotent — re-calling on an already-running
  /// pipeline is a no-op.
  void start(ProviderContainer container);

  /// Stop all timers / subscriptions and release resources. Called on
  /// app pause and on logout.
  void stop();

  /// Manually request an immediate refresh, bypassing the pipeline's
  /// natural cadence. Used by pull-to-refresh and explicit user
  /// actions. Idempotent if a refresh is already in flight.
  Future<void> kickNow();

  /// Human-readable name for diagnostics (logs, debug menus).
  String get debugName;
}
