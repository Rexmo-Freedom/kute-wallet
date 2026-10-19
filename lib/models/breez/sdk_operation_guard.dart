import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

// A reconnect must never retire a native handle while an app-initiated
// payment/claim/refund is running. The reservation is synchronous and is
// taken in the same step as the retirement (after every asynchronous
// check, the SDK's pending-send list among them), so a send cannot start
// in the gap between a recovery's last check and the disconnect, and a
// send that started during the checks is seen by the reservation and
// defers the reconnect.
final _operations = Expando<_SdkOperations>('sparkOperations');

/// A cached asynchronous read from this handle must no longer publish.
bool isSparkSdkRetired(BreezSdk sdk) => _operations[sdk]?.retired ?? false;

/// A watchdog can wait for the complete operation's idle event without using
/// an eligible recovery attempt while the signer is known to be busy.
bool sparkMutationInFlight(BreezSdk sdk) =>
    (_operations[sdk]?.active ?? 0) != 0;

class _SdkOperations {
  int active = 0;
  bool recovering = false;
  bool retired = false;
  final idleObservers = <void Function()>{};
}

/// A liveness recovery deferred by a native mutation can try once when that
/// entire operation ends. No timer, payment retry or native sync is started.
void Function() observeSparkIdle(BreezSdk sdk, void Function() onIdle) {
  final state = _operations[sdk] ??= _SdkOperations();
  state.idleObservers.add(onIdle);
  return () => state.idleObservers.remove(onIdle);
}

Future<T> runSparkMutation<T>(
    BreezSdk sdk, Future<T> Function() operation) async {
  final state = _operations[sdk] ??= _SdkOperations();
  if (state.recovering || state.retired) {
    throw StateError('The wallet is reconnecting. Review the payment again.');
  }
  state.active++;
  try {
    return await operation();
  } finally {
    state.active--;
    if (state.active == 0 && !state.retired) {
      for (final observer in List.of(state.idleObservers)) {
        try {
          observer();
        } catch (_) {/* an observer never changes a completed payment */}
      }
    }
  }
}

/// Returns a recovery reservation only while no mutation is in flight.
/// Retiring it permanently rejects submissions using a prepared old handle.
/// Held only for the synchronous step from the last check to the
/// retirement: never across an await, so no send ever meets "The wallet
/// is reconnecting" because a check is still reading.
SparkRecoveryReservation? reserveSparkRecovery(BreezSdk sdk) {
  final state = _operations[sdk] ??= _SdkOperations();
  if (state.active != 0 || state.recovering || state.retired) return null;
  state.recovering = true;
  return SparkRecoveryReservation._(state);
}

class SparkRecoveryReservation {
  SparkRecoveryReservation._(this._state);
  final _SdkOperations _state;

  void retire() => _state.retired = true;
  void release() => _state.recovering = false;
}

/// Quotes being created right now (an Orchestra quote, a Lightning
/// invoice), whichever SDK handle they will use. Pull-to-refresh never
/// reconnects the SDK while one is, so a quote is never built against a
/// handle that is retired under it; it refreshes with one sync instead.
int _quotesInFlight = 0;

/// Whether a quote is being created ([runSparkQuote]).
bool get sparkQuoteInFlight => _quotesInFlight > 0;

/// Runs [operation], a quote's creation, counted by [sparkQuoteInFlight].
Future<T> runSparkQuote<T>(Future<T> Function() operation) async {
  _quotesInFlight++;
  try {
    return await operation();
  } finally {
    _quotesInFlight--;
  }
}

// ─── Money flows between steps ──────────────────────────────────────────
//
// A pull-to-refresh reconnects the SDK only when no money flow is
// anywhere between its steps, and reserves the handle only in the
// synchronous step that retires it, so "The wallet is reconnecting.
// Review the payment again." can never come from a pull: a send that
// starts while the pull is still checking runs, and the pull defers.
// Beside the running native calls ([runSparkMutation]) and quotes
// ([runSparkQuote]) a flow counts while:
//   * a flow scope runs ([runSparkFlow]): a settlement run, prepare or
//     confirm (quote, review, prepare, broadcast), a send tap on the
//     confirm screen through its biometric prompt and broadcast;
//   * a prepared send is held for review ([holdSparkFlow]): a prepare
//     provider's answer, for as long as a screen keeps it;
//   * a settlement record this process wrote sits before its funds are
//     confirmed ([noteSparkFlowRecord]): a quote waiting for its confirm
//     tap, a broadcast not confirmed yet. Records are persisted and can
//     outlive their flow, so one counts for [sparkFlowRecordMaxAge] after
//     its last write at most.
// Every check is synchronous and in memory.

int _flowScopes = 0;
final Set<SparkFlowHold> _flowHolds = {};
final Map<String, DateTime> _flowRecords = {};

/// How long a settlement record written before its funds were confirmed
/// keeps a pull from reconnecting (a verified quote expires sooner).
@visibleForTesting
Duration sparkFlowRecordMaxAge = const Duration(minutes: 10);

@visibleForTesting
DateTime Function() sparkFlowClock = DateTime.now;

/// Runs [operation], a money flow's steps, counted by
/// [sparkMoneyFlowInFlight] until it ends.
Future<T> runSparkFlow<T>(Future<T> Function() operation) async {
  _flowScopes++;
  try {
    return await operation();
  } finally {
    _flowScopes--;
  }
}

/// A prepared send held for review; [release] when nothing holds it.
class SparkFlowHold {
  SparkFlowHold._();
  void release() => _flowHolds.remove(this);
}

/// Counts a prepared send under review until the hold is released.
SparkFlowHold holdSparkFlow() {
  final hold = SparkFlowHold._();
  _flowHolds.add(hold);
  return hold;
}

/// A settlement record [key] was written: [open] while it sits before its
/// funds are confirmed (quoted, reviewed, authorizing, signed,
/// broadcasting, funding unknown).
void noteSparkFlowRecord(String key, {required bool open}) {
  if (open) {
    _flowRecords[key] = sparkFlowClock();
  } else {
    _flowRecords.remove(key);
  }
}

/// Whether any money flow is between its steps, a quote is being created
/// or a prepared send is under review.
bool get sparkMoneyFlowInFlight {
  if (_quotesInFlight > 0 || _flowScopes > 0 || _flowHolds.isNotEmpty) {
    return true;
  }
  if (_flowRecords.isEmpty) return false;
  final now = sparkFlowClock();
  _flowRecords.removeWhere(
      (_, at) => now.difference(at) >= sparkFlowRecordMaxAge);
  return _flowRecords.isNotEmpty;
}

@visibleForTesting
void debugResetSparkFlows() {
  _quotesInFlight = 0;
  _flowScopes = 0;
  _flowHolds.clear();
  _flowRecords.clear();
  sparkFlowRecordMaxAge = const Duration(minutes: 10);
  sparkFlowClock = DateTime.now;
}
