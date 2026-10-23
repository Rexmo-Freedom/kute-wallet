import 'dart:async';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as spark;

/// The SDK's `syncWallet` call outstanding for each SDK handle.
final Expando<Future<void>> _inFlight = Expando<Future<void>>('syncWallet');
final Expando<Stopwatch> _inFlightClocks =
    Expando<Stopwatch>('syncWalletClocks');
final _observers =
    Expando<Set<void Function(Future<void>)>>('syncWalletObservers');

/// Asks [sdk] for a wallet sync, sharing the one already running.
///
/// The SDK's `syncWallet` always queues a whole new forced sync behind any
/// sync in flight. Its client runtime awaits the wallet/state portion before
/// handling more operator events, so that portion can hold balance updates.
/// The native call also waits on exit-chain collection afterwards: an
/// outstanding call alone does not identify which native stage is blocked.
/// Every app-side caller goes through here: while a call is
/// outstanding, callers get that same future, and a new one starts only
/// once the SDK has answered it. A Dart `.timeout()` does not cancel the
/// native call, so the slot stays taken until the SDK itself answers;
/// callers put their own timeouts on the returned future.
///
/// The returned future completes with the SDK's error when the sync fails.
/// Nobody has to listen to it: a failure nobody awaits is not reported as
/// unhandled.
Future<void> sharedSyncWallet(spark.BreezSdk sdk) {
  final running = _inFlight[sdk];
  if (running != null) return running;
  final Future<void> run;
  try {
    run = sdk.syncWallet(request: const spark.SyncWalletRequest()).then((_) {});
  } catch (error, stack) {
    return Future<void>.error(error, stack);
  }
  _inFlight[sdk] = run;
  _inFlightClocks[sdk] = Stopwatch()..start();
  for (final observe in List.of(_observers[sdk] ?? const {})) {
    try {
      observe(run);
    } catch (_) {/* diagnostics cannot prevent a wallet sync */}
  }
  // Registered before any caller's listener, so the slot is free by the
  // time a caller that awaited [run] asks again.
  void release() {
    if (identical(_inFlight[sdk], run)) {
      _inFlight[sdk] = null;
      _inFlightClocks[sdk] = null;
    }
  }

  run.then((_) => release(), onError: (Object _) => release());
  return run;
}

/// Starts a shared wallet sync without waiting for it, so the SDK's cached
/// balance is fresh by the time a reader needs it.
void kickSharedSyncWallet(spark.BreezSdk sdk) {
  sharedSyncWallet(sdk).ignore();
}

/// Whether a shared sync is outstanding for [sdk].
bool sharedSyncInFlight(spark.BreezSdk sdk) => _inFlight[sdk] != null;

/// Native elapsed time, including time after a Dart caller stopped waiting.
/// Never clears or cancels the outstanding SDK operation.
Duration? sharedSyncAge(spark.BreezSdk sdk) => _inFlightClocks[sdk]?.elapsed;

/// Observes every app-requested native flight, irrespective of its caller.
/// Attaching also reports a flight already in progress. This never starts a
/// sync itself; disposing the listener never cancels the native call.
void Function() observeSharedSync(
    spark.BreezSdk sdk, void Function(Future<void>) onStarted) {
  final observers = _observers[sdk] ??= {};
  observers.add(onStarted);
  final running = _inFlight[sdk];
  if (running != null) onStarted(running);
  return () => observers.remove(onStarted);
}
