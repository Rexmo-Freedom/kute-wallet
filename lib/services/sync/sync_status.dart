// lib/services/sync/sync_status.dart
//
// Unified status surface for the sync pipelines. Each pipeline can
// report its current state — running / idle / failing — keyed by
// its [debugName]; UI can read the aggregated [syncStatusProvider]
// to drive a single banner / spinner / "tap to retry" affordance
// instead of every screen wiring its own per-pipeline state.
//
// Today only the new pipelines (`PolymarketPollPipeline`,
// `PushPipeline`, `OnchainPipeline`) report here. Legacy code paths
// inside `BackgroundSyncService` use the existing
// `backgroundSyncInProgressProvider` directly. As more sync work is
// extracted into pipelines, those legacy reads can migrate to this
// provider.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum SyncPipelineState {
  /// Pipeline isn't running — either deliberately stopped (off
  /// route, app paused) or hasn't been started yet.
  idle,

  /// Pipeline is currently fetching / processing.
  running,

  /// Last attempt failed — the pipeline keeps retrying on its
  /// internal cadence, but UI may want to show a stale-data hint.
  failing,
}

@immutable
class SyncPipelineStatus {
  const SyncPipelineStatus({
    required this.state,
    this.lastSuccessAt,
    this.lastFailureAt,
    this.errorMessage,
  });

  final SyncPipelineState state;
  final DateTime? lastSuccessAt;
  final DateTime? lastFailureAt;
  final String? errorMessage;

  SyncPipelineStatus copyWith({
    SyncPipelineState? state,
    DateTime? lastSuccessAt,
    DateTime? lastFailureAt,
    String? errorMessage,
    bool clearError = false,
  }) =>
      SyncPipelineStatus(
        state: state ?? this.state,
        lastSuccessAt: lastSuccessAt ?? this.lastSuccessAt,
        lastFailureAt: lastFailureAt ?? this.lastFailureAt,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      );

  static const idle = SyncPipelineStatus(state: SyncPipelineState.idle);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncPipelineStatus &&
          state == other.state &&
          lastSuccessAt == other.lastSuccessAt &&
          lastFailureAt == other.lastFailureAt &&
          errorMessage == other.errorMessage);

  @override
  int get hashCode =>
      Object.hash(state, lastSuccessAt, lastFailureAt, errorMessage);
}

/// Per-pipeline status, keyed by `SyncPipeline.debugName`.
final syncPipelineStatusProvider =
    StateNotifierProvider<_SyncPipelineStatusNotifier,
        Map<String, SyncPipelineStatus>>((ref) {
  return _SyncPipelineStatusNotifier();
});

class _SyncPipelineStatusNotifier
    extends StateNotifier<Map<String, SyncPipelineStatus>> {
  _SyncPipelineStatusNotifier() : super(const {});

  void markRunning(String pipeline) {
    final prev = state[pipeline] ?? SyncPipelineStatus.idle;
    if (prev.state == SyncPipelineState.running) return;
    state = {
      ...state,
      pipeline: prev.copyWith(state: SyncPipelineState.running),
    };
  }

  void markSuccess(String pipeline) {
    final prev = state[pipeline] ?? SyncPipelineStatus.idle;
    state = {
      ...state,
      pipeline: prev.copyWith(
        state: SyncPipelineState.idle,
        lastSuccessAt: DateTime.now(),
        clearError: true,
      ),
    };
  }

  void markFailure(String pipeline, [String? error]) {
    final prev = state[pipeline] ?? SyncPipelineStatus.idle;
    state = {
      ...state,
      pipeline: prev.copyWith(
        state: SyncPipelineState.failing,
        lastFailureAt: DateTime.now(),
        errorMessage: error,
      ),
    };
  }

  void markIdle(String pipeline) {
    final prev = state[pipeline] ?? SyncPipelineStatus.idle;
    if (prev.state == SyncPipelineState.idle) return;
    state = {
      ...state,
      pipeline: prev.copyWith(state: SyncPipelineState.idle),
    };
  }
}
