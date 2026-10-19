import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart';

// A reconnect must never retire a native handle while an app-initiated
// payment/claim/refund is running. The reservation is synchronous, so a send
// cannot start in the gap between a recovery's safety check and disconnect.
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
