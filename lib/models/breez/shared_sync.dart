import 'dart:async';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as spark;

/// The SDK's `syncWallet` call outstanding for each SDK handle.
final Expando<Future<void>> _inFlight = Expando<Future<void>>('syncWallet');

/// Asks [sdk] for a wallet sync, sharing the one already running.
///
/// The SDK's `syncWallet` always queues a whole new forced sync behind any
/// sync in flight, and the SDK's runtime loop handles nothing else while a
/// sync runs: the operator stream's balance updates (which refresh the
/// cached `getInfo` within about a second of a transfer landing) wait for
/// it. A sync takes seconds, 20 s or more when one of its steps keeps
/// failing, so every app-side caller goes through here: while a call is
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
  // Registered before any caller's listener, so the slot is free by the
  // time a caller that awaited [run] asks again.
  void release() {
    if (identical(_inFlight[sdk], run)) _inFlight[sdk] = null;
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
