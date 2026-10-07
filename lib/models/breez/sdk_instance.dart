import 'dart:async';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as spark;
import 'package:flutter/foundation.dart';
import 'package:kute/models/breez/deposit_update.dart';
import 'package:kute/services/tracking/latency_tracker.dart';
import 'package:kute/services/tracking_service.dart';

class BreezSdkSpark {
  static final BreezSdkSpark _singleton = BreezSdkSpark._internal();

  factory BreezSdkSpark() => _singleton;

  BreezSdkSpark._internal() : _connectSdk = _nativeConnect;

  @visibleForTesting
  BreezSdkSpark.forTesting({
    required Future<spark.BreezSdk> Function(spark.ConnectRequest) connectSdk,
  }) : _connectSdk = connectSdk;

  static Future<spark.BreezSdk> _nativeConnect(spark.ConnectRequest req) {
    // ignore: invalid_use_of_internal_member
    return spark.BreezSdkSparkLib.instance.api.crateSdkConnect(request: req);
  }

  final Future<spark.BreezSdk> Function(spark.ConnectRequest) _connectSdk;
  Future<void> _lifecycle = Future<void>.value();
  int _generation = 0;
  Object? _teardownFailure;

  spark.BreezSdk? _instance;

  spark.BreezSdk? get instance => _instance;

  /// The SDK handle whose `synced` event last arrived. The SDK holds its
  /// first `synced` until the wallet AND the real-time sync pull of
  /// remote records (contacts among them) have both landed, so this
  /// tells a reader that records from the wallet's other devices are in
  /// local storage.
  spark.BreezSdk? _syncedSdk;

  /// True once the current SDK has delivered a `synced` event.
  bool get hasSynced => _instance != null && identical(_syncedSdk, _instance);

  /// Set once the boot session's first `synced` event has been timed, so
  /// reconnects (wallet switches) never emit a second measurement.
  bool _bootSyncMeasured = false;

  Future<void> connect({required spark.ConnectRequest req}) {
    final generation = ++_generation;
    // connect() → first `synced`: one `spark_sync_latency` per process.
    // A connect that is superseded before syncing simply restarts it.
    if (!_bootSyncMeasured) LatencyTracker.start(LatencyKeys.sparkSync);
    final previous = _instance;
    _instance = null;
    final cancelled = _unsubscribeFromSdkStreams();
    final result = _lifecycle.then((_) async {
      await cancelled;
      if (previous != null) await _retireSdk(previous);
      if (_generation != generation) {
        throw StateError('Spark connection was superseded.');
      }
      if (_teardownFailure != null) {
        throw StateError(
            'The previous Spark session could not close. Restart the app before reconnecting.');
      }
      final sdk = await _connectSdk(req);
      if (_generation != generation) {
        await _retireSdk(sdk);
        throw StateError('Spark connection was superseded.');
      }
      _instance = sdk;
      TrackingService.setSessionKey('breez_connected', true);
      _initializeEventsStream(sdk);
      _subscribeToSdkStreams(sdk);
      // Fetches may complete after a wallet switch; publication below checks
      // the exact SDK handle. Failures are retried by the sync pipelines.
      unawaited(_fetchWalletData(sdk).catchError((Object _) {}));
    });
    _lifecycle =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  void disconnect() {
    ++_generation;
    final previous = _instance;
    _instance = null;
    final cancelled = _unsubscribeFromSdkStreams();
    // Riverpod disposal is synchronous. Queue native teardown so a subsequent
    // connect cannot overlap the old Rust runtime's asynchronous disconnect.
    final result = _lifecycle.then((_) async {
      await cancelled;
      if (previous != null) await _retireSdk(previous);
    });
    _lifecycle =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
  }

  Future<void> _retireSdk(spark.BreezSdk sdk) async {
    try {
      await sdk.disconnect();
    } catch (error) {
      // Native ownership is now uncertain. Do not open a second signer/runtime.
      _teardownFailure = error;
      rethrow;
    }
  }

  /// Recovery-only: connect a candidate seed (via [req], pointed at an
  /// ISOLATED throwaway storage dir) purely to read its on-chain balance
  /// and payment count, then disconnect. Never touches the live
  /// [_instance], never subscribes streams, never fires the push
  /// pipeline — so it's safe to run BEFORE any wallet is adopted.
  ///
  /// The legacy passkey recovery flow uses this to confirm a derived seed
  /// actually controls a real wallet (non-zero balance OR payment
  /// history) before persisting it, so recovery never adopts an empty
  /// phantom. Always disconnects the probe handle in a `finally` so it
  /// can't leak a background sync loop.
  ///
  /// A FRESH restore reports 0 balance / empty history from `getInfo`
  /// until the SDK's first `Synced` event lands (the app's own event
  /// wiring notes `getInfo` is "wildly inconsistent" mid-settlement). So
  /// this polls: it bails the instant the wallet shows funds or history,
  /// otherwise keeps reading until sync completes (plus one settle cycle)
  /// or the ~20s ceiling — never reporting a funded wallet as empty just
  /// because sync hadn't finished.
  Future<({BigInt balanceSats, int paymentCount})> probeSeed(
    spark.ConnectRequest req,
  ) async {
    final sdk = await _nativeConnect(req);
    StreamSubscription<spark.SdkEvent>? sub;
    var synced = false;
    try {
      sub = sdk.addEventListener().listen((e) {
        if (e is spark.SdkEvent_Synced) synced = true;
      });

      var balance = BigInt.zero;
      var payments = 0;
      for (var attempt = 0; attempt < 14; attempt++) {
        final info = await sdk.getInfo(request: const spark.GetInfoRequest());
        final pays =
            await sdk.listPayments(request: const spark.ListPaymentsRequest());
        balance = info.balanceSats;
        payments = pays.payments.length;
        // Funded or has history → definitive, stop now.
        if (balance > BigInt.zero || payments > 0) break;
        // Only trust a 0/empty reading once sync has completed AND we've
        // re-read at least once after it (balance surfaces a beat after
        // `Synced`), so a funded wallet is never dropped on the race.
        if (synced && attempt > 0) break;
        await Future.delayed(const Duration(milliseconds: 1500));
      }
      return (balanceSats: balance, paymentCount: payments);
    } finally {
      await sub?.cancel();
      try {
        // AWAIT the teardown: disconnect() is async on v0.23, and
        // returning while the rust runtime is still flushing lets the
        // caller delete the throwaway probe dir under live writes
        // (leaving a stray synced wallet DB behind) and can overlap the
        // probe instance with the real wallet's subsequent connect. An
        // un-awaited failure would also escape this catch entirely.
        await sdk.disconnect();
      } catch (_) {/* best-effort teardown */}
    }
  }

  Future<void> _fetchWalletData(spark.BreezSdk sdk) async {
    try {
      await _getInfo(sdk);
      if (identical(_instance, sdk)) await _listPayments(sdk: sdk);
    } catch (_) {
      // SDK events are fire-and-forget. The next sync read retries failures.
    }
  }

  /// Forces an SDK wallet sync, which rewrites the SDK's cached balance
  /// from its leaves, then re-reads the wallet data.
  Future<void> _syncThenFetchWalletData(spark.BreezSdk sdk) async {
    try {
      await sdk
          .syncWallet(request: const spark.SyncWalletRequest())
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      // The periodic sync catches up.
    }
    if (identical(_instance, sdk)) await _fetchWalletData(sdk);
  }

  Future<spark.GetInfoResponse> _getInfo(spark.BreezSdk sdk) async {
    // Spark requires a request object for getInfo
    const req = spark.GetInfoRequest();
    final walletInfo = await sdk.getInfo(request: req);
    if (identical(_instance, sdk)) _walletInfoController.add(walletInfo);
    return walletInfo;
  }

  Future<List<spark.Payment>> _listPayments({
    required spark.BreezSdk sdk,
  }) async {
    // Spark requires a request object for listPayments
    const req = spark.ListPaymentsRequest();
    final response = await sdk.listPayments(request: req);
    if (identical(_instance, sdk)) _paymentsController.add(response.payments);
    return response.payments;
  }

  StreamSubscription<spark.LogEntry>? _breezLogSubscription;
  Stream<spark.LogEntry>? _breezLogStream;

  /// Initializes SDK log stream.
  /// Call once on your Dart entrypoint file, e.g.; `lib/main.dart`.
  void initializeLogStream() {
    // In Spark, logging is initialized via the static API
    // ignore: invalid_use_of_internal_member
    _breezLogStream ??= spark.BreezSdkSparkLib.instance.api
        .crateSdkInitLogging()
        .asBroadcastStream();
  }

  StreamSubscription<spark.SdkEvent>? _breezEventsSubscription;
  Stream<spark.SdkEvent>? _breezEventsStream;

  void _initializeEventsStream(spark.BreezSdk sdk) {
    _breezEventsStream = sdk.addEventListener();
  }

  /// Subscribes to SDK's event & log streams.
  void _subscribeToSdkStreams(spark.BreezSdk sdk) {
    _subscribeToEventsStream(sdk);
    _subscribeToLogStream();
  }

  final StreamController<spark.GetInfoResponse> _walletInfoController =
      StreamController<spark.GetInfoResponse>.broadcast();

  Stream<spark.GetInfoResponse> get walletInfoStream =>
      _walletInfoController.stream;

  // Stream for single payment updates (success/failure)
  final StreamController<spark.Payment> _paymentResultStream =
      StreamController.broadcast();
  Stream<spark.Payment> get paymentResultStream => _paymentResultStream.stream;

  // Stream for the list of all payments
  final StreamController<List<spark.Payment>> _paymentsController =
      StreamController<List<spark.Payment>>.broadcast();
  Stream<List<spark.Payment>> get paymentsStream => _paymentsController.stream;

  // Deposit events are deltas. Never replay one into a later wallet session;
  // PushPipeline hydrates an authoritative snapshot when attaching/resuming.
  final StreamController<SparkDepositUpdate> _depositsController =
      StreamController<SparkDepositUpdate>.broadcast();
  Stream<SparkDepositUpdate> get depositsStream => _depositsController.stream;

  // Fires after each sync of the current SDK. Sync can claim or drop deposits
  // without a matching deposit event, so listeners re-read local storage.
  final StreamController<void> _syncedController =
      StreamController<void>.broadcast();
  Stream<void> get syncedStream => _syncedController.stream;

  final _logStreamController = StreamController<spark.LogEntry>.broadcast();
  Stream<spark.LogEntry> get logStream => _logStreamController.stream;

  /// Subscribes to SdkEvent's stream
  void _subscribeToEventsStream(spark.BreezSdk sdk) {
    _breezEventsSubscription = _breezEventsStream?.listen(
      (event) async {
        if (!identical(_instance, sdk)) return;
        // Map Spark Events to Logic
        event.map(
          // Reverted to the original wiring. Trying to fan out every
          // SDK event to a `_fetchWalletData` call produced multiple
          // overlapping `getInfo` reads at different stages of
          // internal SDK settlement, surfacing wildly inconsistent
          // balance values. Only payment-class events get an active
          // refresh here; `synced` only logs and signals listeners
          // (PushPipeline re-reads deposits and, debounced, the
          // bitcoin balance), and the periodic 2 s poll covers
          // anything else.
          synced: (_) {
            _syncedSdk = sdk;
            _logStreamController.add(const spark.LogEntry(
                line: "Received Synced event.", level: "INFO"));
            if (!_bootSyncMeasured) {
              _bootSyncMeasured = true;
              LatencyTracker.stop(LatencyKeys.sparkSync);
            }
            _syncedController.add(null);
          },
          autoOptimization: (_) {
            _fetchWalletData(sdk);
          },
          unclaimedDeposits: (e) {
            if (kDebugMode) {
              // ignore: avoid_print
              print(
                  '[sdk-event] unclaimedDeposits count=${e.unclaimedDeposits.length} '
                  '${e.unclaimedDeposits.map((d) => "${d.txid.substring(0, 8)}…/${d.vout}/mature=${d.isMature}").toList()}');
            }
            _depositsController.add(SparkDepositUpdate(
                SparkDepositUpdateKind.upsert, e.unclaimedDeposits));
          },
          claimedDeposits: (e) {
            if (kDebugMode) {
              // ignore: avoid_print
              print(
                  '[sdk-event] claimedDeposits count=${e.claimedDeposits.length}');
            }
            _depositsController.add(SparkDepositUpdate(
                SparkDepositUpdateKind.claimed, e.claimedDeposits));
          },
          newDeposits: (e) {
            if (kDebugMode) {
              // ignore: avoid_print
              print('[sdk-event] newDeposits count=${e.newDeposits.length} '
                  '${e.newDeposits.map((d) => "${d.txid.substring(0, 8)}…/${d.vout}/mature=${d.isMature}/sats=${d.amountSats}").toList()}');
            }
            _logStreamController.add(const spark.LogEntry(
                line: 'New on-chain deposit detected.', level: 'INFO'));
            _depositsController.add(SparkDepositUpdate(
                SparkDepositUpdateKind.upsert, e.newDeposits));
            _fetchWalletData(sdk);
          },
          paymentSucceeded: (e) {
            _logStreamController.add(
              spark.LogEntry(
                  line: "Payment Succeeded. ${e.payment.id}", level: "INFO"),
            );
            _paymentResultStream.add(e.payment);
            _fetchWalletData(sdk);
          },
          paymentPending: (e) {
            _logStreamController.add(
              spark.LogEntry(
                  line: "Payment Pending. ${e.payment.id}", level: "INFO"),
            );
            _paymentResultStream.add(e.payment);
            _fetchWalletData(sdk);
          },
          paymentFailed: (e) {
            _logStreamController.add(
              spark.LogEntry(
                  line: "Payment Failed. ${e.payment.id}", level: "WARN"),
            );
            _paymentResultStream.addError(PaymentException(e.payment));
            _fetchWalletData(sdk);
            // `PaymentFailed` does not refresh the SDK's cached balance
            // (only `PaymentSucceeded` and its 60 s sync do), so a
            // refunded send would read as spent until the next sync.
            _syncThenFetchWalletData(sdk);
          },
          // New in breez 0.26: metadata attached to an existing payment
          // (SDK cross-chain receives, which the app does not create). The
          // status did not change, so it is not a payment result; the
          // periodic poll picks up the new details.
          paymentMetadataUpdated: (_) {},
          lightningAddressChanged: (_) {},
          // New in breez 0.23: fires when the SDK's tracked unilateral-exit
          // package state changes. The app has no unilateral-exit UI to
          // refresh, so this is a deliberate no-op (the comment above
          // restricts active refreshes to payment-class events).
          unilateralExitStateChanged: (_) {},
        );
      },
    );
  }

  /// Subscribes to SDK's logs stream
  void _subscribeToLogStream() {
    _breezLogSubscription = _breezLogStream?.listen((logEntry) {
      _logStreamController.add(logEntry);
    }, onError: (e) {
      _logStreamController.addError(e);
    });
  }

  /// Unsubscribes from SDK's event & log streams.
  Future<void> _unsubscribeFromSdkStreams() async {
    final events = _breezEventsSubscription;
    final logs = _breezLogSubscription;
    _breezEventsSubscription = null;
    _breezLogSubscription = null;
    _breezEventsStream = null;
    await Future.wait([
      if (events != null) events.cancel(),
      if (logs != null) logs.cancel(),
    ]);
  }
}

class PaymentException implements Exception {
  final spark.Payment payment;

  const PaymentException(this.payment);

  @override
  String toString() => "PaymentException: Payment ${payment.id} failed.";
}
