import 'dart:async';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as spark;
import 'package:flutter/foundation.dart';
import 'package:kute/models/breez/deposit_update.dart';
import 'package:kute/models/breez/shared_sync.dart';
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

  /// Set once the boot session's first native connect has been timed
  /// (`spark_connect_latency`, whatever its outcome), for the same reason.
  bool _bootConnectMeasured = false;

  Future<void> connect({required spark.ConnectRequest req}) {
    final generation = ++_generation;
    final previous = _instance;
    _instance = null;
    _forgetWalletReadings();
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
      // Two boot timers, one each per process, without overlap:
      //   * `spark_connect_latency`: this native connect call → the
      //     connected handle (or its failure);
      //   * `spark_sync_latency`: the connected handle → the first `synced`
      //     event. A connect that is superseded before syncing restarts it.
      // Teardown of a previous handle (a wallet switch) is in neither.
      final connectSw = _bootConnectMeasured ? null : (Stopwatch()..start());
      final spark.BreezSdk sdk;
      try {
        sdk = await _connectSdk(req);
      } catch (_) {
        _recordBootConnect(connectSw, result: 'error');
        rethrow;
      }
      _recordBootConnect(connectSw, result: 'ok');
      if (!_bootSyncMeasured) LatencyTracker.start(LatencyKeys.sparkSync);
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

  /// Emits the boot session's one `spark_connect_latency`. [sw] is null
  /// once it has been emitted.
  void _recordBootConnect(Stopwatch? sw, {required String result}) {
    if (sw == null) return;
    sw.stop();
    _bootConnectMeasured = true;
    LatencyTracker.record(LatencyKeys.sparkConnect, sw.elapsedMilliseconds,
        params: {'result': result});
  }

  void disconnect() {
    ++_generation;
    final previous = _instance;
    _instance = null;
    _forgetWalletReadings();
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

  /// The wallet is going away: its balance readings and the arrivals
  /// waiting on it mean nothing for the next one.
  void _forgetWalletReadings() {
    _balanceLog.clear();
    _arrivals.cancelAll();
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

  /// Re-reads the connected wallet's balances and payments once and
  /// publishes them to the streams the balance providers follow: no poll,
  /// no sync. For a change the wallet made itself (one of its own sends
  /// finished, an order paid from it failed): the SDK's cache already has
  /// it, nothing has to arrive. Never throws.
  Future<void> rereadWalletData() async {
    final sdk = _instance;
    if (sdk != null) await _fetchWalletData(sdk);
  }

  /// Forces an SDK wallet sync (the shared one, see [sharedSyncWallet]),
  /// which rewrites the SDK's cached balance from its leaves, then re-reads
  /// the wallet data.
  Future<void> _syncThenFetchWalletData(spark.BreezSdk sdk) async {
    try {
      await sharedSyncWallet(sdk).timeout(const Duration(seconds: 20));
    } catch (_) {
      // The periodic sync catches up.
    }
    if (identical(_instance, sdk)) await _fetchWalletData(sdk);
  }

  /// What the app read of the connected wallet's balances, for the
  /// baseline of an arrival (see [syncAndRefresh]).
  final ArrivalBalanceLog _balanceLog = ArrivalBalanceLog();

  late final ArrivalRefresher _arrivals = ArrivalRefresher(
    readBalances: () async {
      final sdk = _instance;
      if (sdk == null) throw StateError('No SDK');
      final info = await sdk.getInfo(request: const spark.GetInfoRequest());
      // Another wallet connected meanwhile: not this wallet's reading.
      if (!identical(_instance, sdk)) throw StateError('SDK replaced');
      final balances = balancesOf(info);
      _balanceLog.record(balances, DateTime.now());
      return balances;
    },
    sync: () async {
      final sdk = _instance;
      if (sdk == null) return;
      try {
        await sharedSyncWallet(sdk).timeout(const Duration(seconds: 20));
      } catch (_) {
        // Read what the cache holds anyway.
      }
    },
    publish: () async {
      final sdk = _instance;
      if (sdk != null) await _fetchWalletData(sdk);
    },
  );

  /// Re-reads the connected wallet's balance and payments for money known
  /// to have just landed (an Orchestra order delivering to this wallet
  /// completed), and publishes the reading to the wallet-info and payments
  /// streams the balance providers follow once [asset]'s balance shows it.
  ///
  /// [since] is when the money could first have moved (the order's
  /// creation). The arrival is measured from the lowest balance read since
  /// then (at most [kArrivalLookback] back, see [ArrivalBalanceLog]), so
  /// money the SDK's own payment event already counted (it usually lands
  /// before Orchestra reports the order done) ends the refresh on its
  /// first reading: no polling, no sync. Otherwise the cached balance is
  /// polled (the operator stream normally lands the transfer within a
  /// second or so) and only when it has not risen does one shared wallet
  /// sync run; a sync blocks the SDK's runtime loop, so syncing first
  /// would hold back the very stream update being waited for.
  ///
  /// Concurrent arrivals share one poll ([ArrivalRefresher]), each with
  /// its own baseline and asset, so a bitcoin arrival never ends on a
  /// dollar one, and a second arrival never waits for the first one's
  /// run to finish. Never throws.
  Future<void> syncAndRefresh({
    ArrivalAsset asset = ArrivalAsset.any,
    DateTime? since,
  }) {
    if (_instance == null) return Future<void>.value();
    Map<String, BigInt>? baseline;
    if (since != null) {
      final now = DateTime.now();
      final floor = now.subtract(kArrivalLookback);
      final from = since.isBefore(floor)
          ? floor
          : since.isAfter(now)
              ? now
              : since;
      baseline = _balanceLog.baselineSince(from);
    }
    return _arrivals.request(asset: asset, baseline: baseline);
  }

  /// Sequence numbers of the wallet-info reads: the last one asked for and
  /// the newest one published. Reads overlap (a payment event, an arrival
  /// refresh and a `synced` re-read can all be in flight) and the native
  /// calls can answer out of order, so a read is published only when no
  /// read asked for after it has been published already: an older answer
  /// (the figure from before a transfer landed) never overwrites a newer
  /// one on screen.
  int _infoAsked = 0;
  int _infoPublished = 0;
  int _paymentsAsked = 0;
  int _paymentsPublished = 0;

  Future<spark.GetInfoResponse> _getInfo(spark.BreezSdk sdk) async {
    // Spark requires a request object for getInfo
    const req = spark.GetInfoRequest();
    final asked = ++_infoAsked;
    final walletInfo = await sdk.getInfo(request: req);
    if (identical(_instance, sdk) && asked > _infoPublished) {
      _infoPublished = asked;
      _balanceLog.record(balancesOf(walletInfo), DateTime.now());
      _walletInfoController.add(walletInfo);
    }
    return walletInfo;
  }

  /// Reads the connected wallet's balances once and publishes them to
  /// [walletInfoStream]: the balance half of [_fetchWalletData], for events
  /// that change a balance but no payment row (a sync, a claimed deposit).
  /// Never throws.
  Future<void> _publishWalletInfo(spark.BreezSdk sdk) async {
    try {
      await _getInfo(sdk);
    } catch (_) {
      // The next event or read publishes again.
    }
  }

  Future<List<spark.Payment>> _listPayments({
    required spark.BreezSdk sdk,
  }) async {
    // Spark requires a request object for listPayments
    const req = spark.ListPaymentsRequest();
    final asked = ++_paymentsAsked;
    final response = await sdk.listPayments(request: req);
    if (identical(_instance, sdk) && asked > _paymentsPublished) {
      _paymentsPublished = asked;
      _paymentsController.add(response.payments);
    }
    return response.payments;
  }

  StreamSubscription<spark.LogEntry>? _breezLogSubscription;
  Stream<spark.LogEntry>? _breezLogStream;

  /// Initializes SDK log stream.
  /// Call once on your Dart entrypoint file, e.g.; `lib/main.dart`.
  ///
  /// [logFilter] is the SDK's tracing filter (its own default when null).
  /// [printSyncSteps] prints the SDK's per-step wallet sync lines (see
  /// [isSdkSyncLogLine]) with an `[sdk-sync]` prefix, in debug builds only.
  void initializeLogStream({String? logFilter, bool printSyncSteps = false}) {
    if (_breezLogStream != null) return;
    // In Spark, logging is initialized via the static API
    // ignore: invalid_use_of_internal_member
    final stream = spark.BreezSdkSparkLib.instance.api
        .crateSdkInitLogging(logFilter: logFilter)
        .asBroadcastStream();
    _breezLogStream = stream;
    if (kDebugMode && printSyncSteps) {
      stream.listen((entry) {
        if (!isSdkSyncLogLine(entry.line)) return;
        // ignore: avoid_print
        print('[sdk-sync] ${entry.level} ${entry.line.trim()}');
      }, onError: (Object _) {});
    }
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

  /// Re-publishes the balances after the current SDK's `synced` events
  /// (see [SyncedReread]). One per SDK handle.
  SyncedReread? _syncedInfoReread;

  /// Subscribes to SdkEvent's stream
  void _subscribeToEventsStream(spark.BreezSdk sdk) {
    _syncedInfoReread?.dispose();
    final syncedInfoReread = SyncedReread(() {
      if (identical(_instance, sdk)) unawaited(_publishWalletInfo(sdk));
    });
    _syncedInfoReread = syncedInfoReread;
    _breezEventsSubscription = _breezEventsStream?.listen(
      (event) async {
        if (!identical(_instance, sdk)) return;
        // Map Spark Events to Logic
        //
        // The one rule for balances: every SDK event that can change a
        // balance of this wallet is followed by a `getInfo` published to
        // [walletInfoStream], and both balances (bitcoin through
        // `walletBalanceCacheProvider`, Dollars through
        // `usdSdkBalanceProvider`) follow that stream. What the SDK (0.26,
        // client runtime) guarantees:
        //
        //  * `paymentSucceeded`: the cached balance is refreshed BEFORE
        //    the event reaches the app (its BalanceWatcher is an internal
        //    listener the emitter awaits first, and an incoming Spark
        //    transfer or token transaction also refreshes it in
        //    `insert_payment_with_metadata`), so the read below already
        //    shows the money;
        //  * `paymentPending`: nothing is refreshed (an incoming transfer
        //    raises it when its claim starts); the same payment is raised
        //    again as succeeded once claimed, and read again then;
        //  * `claimedDeposits`: the balance is refreshed before it; its
        //    payment also follows as `paymentSucceeded`;
        //  * `synced`: the sync wrote the cached balance before raising
        //    it. A payment event is raised only when the stored status
        //    advances, so a transfer a sync recorded as completed first
        //    raises none when its claim lands (nor does any completed
        //    payment found before the first full sync): the balances are
        //    read here too, at once and once more after the burst
        //    ([SyncedReread]).
        //
        // Overlapping reads are safe: [_getInfo] publishes only the
        // newest answer, so a read that started before a transfer landed
        // never overwrites one that started after.
        event.map(
          synced: (_) {
            _syncedSdk = sdk;
            _logStreamController.add(const spark.LogEntry(
                line: "Received Synced event.", level: "INFO"));
            if (!_bootSyncMeasured) {
              _bootSyncMeasured = true;
              LatencyTracker.stop(LatencyKeys.sparkSync);
            }
            _syncedController.add(null);
            syncedInfoReread.onSynced();
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
            // The SDK refreshed its cached balance before raising this.
            unawaited(_publishWalletInfo(sdk));
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
    _syncedInfoReread?.dispose();
    _syncedInfoReread = null;
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

/// How often [syncUntilBalanceRises] re-reads the SDK's cached balance
/// while waiting for an expected arrival.
const Duration kArrivalPollInterval = Duration(milliseconds: 300);

/// How long [syncUntilBalanceRises] polls the cached balance before it
/// asks for a wallet sync.
const Duration kArrivalPollWindow = Duration(seconds: 3);

/// How often a request that ended without its rise (see [ArrivalRefresher])
/// reads the cached balance again, without a sync.
const Duration kArrivalLateCheckInterval = Duration(seconds: 5);

/// How many such late reads it gets: half a minute in all.
const int kArrivalLateChecks = 6;

/// How long after the last `synced` event of a burst [SyncedReread] reads
/// the balance a second time.
const Duration kSyncedRereadSettle = Duration(milliseconds: 300);

/// Re-reads a balance after the SDK's `synced` events: at once on the
/// first event of a burst (the SDK writes its cached balances before it
/// raises `synced`, so that reading already shows what the sync found),
/// and once more [settle] after the last one, in case a write landed just
/// after. Two reads per burst, however many events it has.
class SyncedReread {
  SyncedReread(this._read, {this.settle = kSyncedRereadSettle});

  final void Function() _read;
  final Duration settle;
  Timer? _trailing;

  void onSynced() {
    if (_trailing == null) _read();
    _trailing?.cancel();
    _trailing = Timer(settle, () {
      _trailing = null;
      _read();
    });
  }

  void dispose() {
    _trailing?.cancel();
    _trailing = null;
  }
}

/// The SDK tracing filter for debug builds: warnings, plus the wallet sync
/// steps and the per-operator query failures.
const String kSdkSyncDebugLogFilter =
    'warn,breez_sdk_spark::sdk::sync=debug,spark::tree::service=error';

/// Whether [line] from the SDK's log stream is one of its own wallet sync
/// step lines (timings and failures).
bool isSdkSyncLogLine(String line) =>
    line.contains('sync_wallet_internal') ||
    line.contains('Spark wallet sync failed') ||
    line.contains('Failed to query operator') ||
    line.contains('Deposits sync completed') ||
    line.contains('Failed to check and claim static deposits');

/// Every balance the wallet holds, by asset: `sats` and each token id.
Map<String, BigInt> balancesOf(spark.GetInfoResponse info) => {
      'sats': info.balanceSats,
      for (final entry in info.tokenBalances.entries)
        entry.key: entry.value.balance,
    };

/// Which balance an expected arrival lands in: [bitcoin] is the sats
/// balance, [dollars] any token balance, [any] either.
enum ArrivalAsset {
  bitcoin,
  dollars,
  any;

  /// Whether a rise of balance [key] (`sats` or a token id, see
  /// [balancesOf]) is this arrival.
  bool counts(String key) => switch (this) {
        ArrivalAsset.bitcoin => key == 'sats',
        ArrivalAsset.dollars => key != 'sats',
        ArrivalAsset.any => true,
      };

  ArrivalAsset merge(ArrivalAsset other) => this == other ? this : any;
}

/// How far back [BreezSdkSpark.syncAndRefresh] looks for the balance an
/// arrival is measured from (see [ArrivalBalanceLog.baselineSince]). An
/// Orchestra row reports success seconds after the wallet counted the
/// transfer; this leaves room for a status poll that ran late (the app
/// was in the background) while keeping unrelated receives of the same
/// asset out of the comparison.
const Duration kArrivalLookback = Duration(minutes: 10);

/// The balances the app read from the connected SDK, as they changed:
/// one entry per reading that differed from the one before it. The
/// balance at a moment is the last entry at or before it.
///
/// [baselineSince] gives an arrival the balance from before its money
/// moved, so a refresh asked for after the SDK's own event already
/// counted the transfer sees the rise at once instead of starting from a
/// reading that includes it.
class ArrivalBalanceLog {
  ArrivalBalanceLog(
      {this.keep = const Duration(hours: 6), this.maxEntries = 256});

  /// Entries older than this are dropped (the one in effect at the cutoff
  /// is kept).
  final Duration keep;
  final int maxEntries;

  final List<({DateTime at, Map<String, BigInt> balances})> _entries = [];

  /// Records a reading of every balance ([balancesOf]) taken at [at].
  void record(Map<String, BigInt> balances, DateTime at) {
    if (_entries.isNotEmpty && mapEquals(_entries.last.balances, balances)) {
      return;
    }
    _entries.add((at: at, balances: Map.unmodifiable(balances)));
    final cutoff = at.subtract(keep);
    // Keep the newest entry at or before the cutoff: it is the balance in
    // effect there.
    while (_entries.length > 1 &&
        (_entries.length > maxEntries || !_entries[1].at.isAfter(cutoff))) {
      _entries.removeAt(0);
    }
  }

  /// The lowest balance, key by key, in effect at any moment from [since]
  /// until now: the reading in effect at [since] and every later one. A
  /// spend after [since] lowers it; an arrival after [since] does not
  /// raise it. Null when nothing has been read yet.
  Map<String, BigInt>? baselineSince(DateTime since) {
    if (_entries.isEmpty) return null;
    var first = 0;
    for (var i = 0; i < _entries.length; i++) {
      if (_entries[i].at.isAfter(since)) break;
      first = i;
    }
    final low = <String, BigInt>{};
    final keys = <String>{
      for (var i = first; i < _entries.length; i++)
        ..._entries[i].balances.keys,
    };
    for (final key in keys) {
      BigInt? min;
      for (var i = first; i < _entries.length; i++) {
        // A balance missing from a reading is zero.
        final v = _entries[i].balances[key] ?? BigInt.zero;
        if (min == null || v < min) min = v;
      }
      low[key] = min!;
    }
    return low;
  }

  void clear() => _entries.clear();
}

class _ArrivalWaiter {
  _ArrivalWaiter(this.asset, this.baseline, this.pollsLeft);

  final ArrivalAsset asset;
  Map<String, BigInt>? baseline;
  int pollsLeft;
  final Completer<bool> done = Completer<bool>();

  /// A sync started after this request joined: its reading already
  /// carries whatever the operators held for it, so it never asks for
  /// another one.
  bool synced = false;

  /// Late reads left once it ended without its rise.
  int lateLeft = 0;

  bool roseIn(Map<String, BigInt> balances) {
    final base = baseline;
    if (base == null) return false;
    return balances.entries.any(
        (e) => asset.counts(e.key) && e.value > (base[e.key] ?? BigInt.zero));
  }
}

/// Waits for expected arrivals in the wallet's cached balance, every
/// request sharing one poll.
///
/// A request waits for some balance of its [ArrivalAsset] to rise above
/// its baseline: the one its caller passes (the balance from before the
/// money moved, see [ArrivalBalanceLog]), else the latest reading of the
/// running poll, else the poll's next reading. While any request waits,
/// the cache is read every [pollInterval]; one reading settles every
/// request it shows a rise for, at once, so a request whose money is
/// already counted ends on the first reading, with no wait and no sync.
/// A request that has seen no rise after [pollWindow] of polls (or had
/// nothing to compare against) asks for one [sync], shared by every
/// request due at that moment, and ends on the reading after it.
///
/// A request made while the poll runs joins it (no queue behind the
/// running one) with its own baseline and its own window. A sync serves
/// every request that joined before it started: one whose window ends
/// after such a sync ends on its reading without asking for another, so
/// a burst of arrivals (the legs of a Rebalance landing one after the
/// other) costs one sync, not one each. Whenever requests end, [publish]
/// runs once before their futures complete, so the reading reaches the UI
/// first.
///
/// A request that ends without its rise is not forgotten: the SDK can
/// write a transfer into its cached balance after the sync answered (a
/// sync holds the operator stream back, and once a sync has recorded the
/// payment the stream's late balance write raises no payment event, so
/// nothing else re-reads). Its baseline is read again every
/// [lateCheckInterval], without a sync, [lateChecks] times; a reading that
/// shows the rise is published at once. Never throws.
class ArrivalRefresher {
  ArrivalRefresher({
    required this.readBalances,
    required this.sync,
    Future<void> Function()? publish,
    this.pollInterval = kArrivalPollInterval,
    this.pollWindow = kArrivalPollWindow,
    this.lateCheckInterval = kArrivalLateCheckInterval,
    this.lateChecks = kArrivalLateChecks,
    Future<void> Function(Duration delay) sleep = _sleepFor,
  })  : _publish = publish,
        _sleep = sleep;

  final Future<Map<String, BigInt>> Function() readBalances;
  final Future<void> Function() sync;
  final Future<void> Function()? _publish;
  final Duration pollInterval;
  final Duration pollWindow;
  final Duration lateCheckInterval;
  final int lateChecks;
  final Future<void> Function(Duration delay) _sleep;

  final List<_ArrivalWaiter> _waiters = [];
  final List<_ArrivalWaiter> _late = [];
  int _generation = 0;
  int? _loopGeneration;
  int? _lateGeneration;
  Map<String, BigInt>? _lastReading;

  int get _pollsPerWindow => pollInterval > Duration.zero
      ? pollWindow.inMicroseconds ~/ pollInterval.inMicroseconds
      : 0;

  /// Requests waiting now.
  @visibleForTesting
  int get waiting => _waiters.length;

  /// Requests that ended without their rise and are still read late.
  @visibleForTesting
  int get lateWaiting => _late.length;

  /// Waits for an arrival of [asset] above [baseline]. Completes with
  /// whether one rose.
  Future<bool> request({
    ArrivalAsset asset = ArrivalAsset.any,
    Map<String, BigInt>? baseline,
  }) {
    final running = _loopGeneration == _generation;
    final waiter = _ArrivalWaiter(
        asset, baseline ?? (running ? _lastReading : null), _pollsPerWindow);
    _waiters.add(waiter);
    if (!running) {
      _loopGeneration = _generation;
      unawaited(_loop(_generation));
    } else if (waiter.baseline != null) {
      unawaited(_probe(waiter, _generation));
    }
    return waiter.done.future;
  }

  /// Ends every request with false (the wallet they wait on is gone).
  void cancelAll() {
    _generation++;
    _lastReading = null;
    _late.clear();
    final dropped = List.of(_waiters);
    _waiters.clear();
    for (final w in dropped) {
      w.done.complete(false);
    }
  }

  Future<Map<String, BigInt>?> _read(int gen) async {
    try {
      final balances = await readBalances();
      if (gen == _generation) _lastReading = balances;
      return balances;
    } catch (_) {
      return null;
    }
  }

  /// Ends the requests [balances] shows a rise for, and [giveUp] (their
  /// sync is done), after one [_publish]. Gives the others that still have
  /// no baseline this reading.
  Future<void> _settle(
    Map<String, BigInt>? balances,
    int gen, {
    List<_ArrivalWaiter> giveUp = const [],
  }) async {
    final ended = <(_ArrivalWaiter, bool)>[];
    for (final w in _waiters) {
      if (balances != null && w.roseIn(balances)) {
        ended.add((w, true));
      } else if (giveUp.contains(w)) {
        ended.add((w, false));
      } else if (w.baseline == null && balances != null) {
        w.baseline = balances;
      }
    }
    await _end(ended);
  }

  /// Ends [ended], after one [_publish] when there are any.
  Future<void> _end(List<(_ArrivalWaiter, bool)> ended) async {
    if (ended.isEmpty) return;
    for (final (w, _) in ended) {
      _waiters.remove(w);
    }
    final publish = _publish;
    if (publish != null) {
      try {
        await publish();
      } catch (_) {}
    }
    for (final (w, rose) in ended) {
      if (!w.done.isCompleted) w.done.complete(rose);
      if (!rose && w.baseline != null && lateChecks > 0) {
        w.lateLeft = lateChecks;
        _late.add(w);
      }
    }
    if (_late.isNotEmpty && _lateGeneration != _generation) {
      _lateGeneration = _generation;
      unawaited(_lateLoop(_generation));
    }
  }

  /// Reads the requests that ended without their rise again, every
  /// [lateCheckInterval], no sync; publishes once for a reading that
  /// shows any of them.
  Future<void> _lateLoop(int gen) async {
    bool live() => gen == _generation;
    try {
      while (live() && _late.isNotEmpty) {
        await _sleep(lateCheckInterval);
        if (!live()) break;
        Map<String, BigInt>? reading;
        try {
          reading = await readBalances();
        } catch (_) {
          reading = null;
        }
        if (!live()) break;
        var rose = false;
        for (final w in List.of(_late)) {
          if (reading != null && w.roseIn(reading)) {
            rose = true;
            _late.remove(w);
          } else if (--w.lateLeft <= 0) {
            _late.remove(w);
          }
        }
        final publish = _publish;
        if (rose && publish != null) {
          try {
            await publish();
          } catch (_) {}
        }
      }
    } finally {
      if (_lateGeneration == gen) _lateGeneration = null;
    }
  }

  /// One reading at once for [w], a request that joined the running poll
  /// with a baseline: its money may be counted already, and the poll may
  /// be sleeping or syncing.
  Future<void> _probe(_ArrivalWaiter w, int gen) async {
    final reading = await _read(gen);
    if (gen != _generation || reading == null) return;
    if (!_waiters.contains(w) || !w.roseIn(reading)) return;
    await _end([(w, true)]);
  }

  Future<void> _loop(int gen) async {
    bool live() => gen == _generation;
    try {
      while (live() && _waiters.isNotEmpty) {
        final reading = await _read(gen);
        if (!live()) break;
        await _settle(reading, gen);
        if (!live() || _waiters.isEmpty) break;
        final due = [
          for (final w in _waiters)
            if (w.baseline == null || w.pollsLeft <= 0) w,
        ];
        if (due.isNotEmpty && due.every((w) => w.synced)) {
          // Each already saw a sync that started after it joined, and the
          // reading above came after that sync: nothing more to sync for.
          await _end([
            for (final w in due)
              if (_waiters.contains(w)) (w, false),
          ]);
          if (!live() || _waiters.isEmpty) break;
        } else if (due.isNotEmpty) {
          // This sync serves every request waiting now.
          for (final w in _waiters) {
            w.synced = true;
          }
          try {
            await sync();
          } catch (_) {
            // Read what the cache holds anyway.
          }
          if (!live()) break;
          final after = await _read(gen);
          if (!live()) break;
          await _settle(after, gen, giveUp: due);
          if (!live() || _waiters.isEmpty) break;
        }
        final polled = List.of(_waiters);
        await _sleep(pollInterval);
        for (final w in polled) {
          w.pollsLeft--;
        }
      }
    } finally {
      if (_loopGeneration == gen) {
        _loopGeneration = null;
        _lastReading = null;
      }
    }
  }
}

/// Waits for some balance [readBalances] reports to rise above [baseline]
/// (else the first reading); [asset] says which balances count. One
/// request of an [ArrivalRefresher]: polls every [pollInterval] for up to
/// [pollWindow], then runs [sync] once and reads again. Returns whether
/// one rose. A failed read counts as not risen yet; when even the first
/// read fails and there is no [baseline], there is nothing to compare, so
/// it syncs once and returns false.
Future<bool> syncUntilBalanceRises({
  required Future<Map<String, BigInt>> Function() readBalances,
  ArrivalAsset asset = ArrivalAsset.any,
  Map<String, BigInt>? baseline,
  required Future<void> Function() sync,
  Duration pollInterval = kArrivalPollInterval,
  Duration pollWindow = kArrivalPollWindow,
  Future<void> Function(Duration delay) sleep = _sleepFor,
}) =>
    ArrivalRefresher(
      readBalances: readBalances,
      sync: sync,
      pollInterval: pollInterval,
      pollWindow: pollWindow,
      lateChecks: 0,
      sleep: sleep,
    ).request(asset: asset, baseline: baseline);

Future<void> _sleepFor(Duration d) => Future<void>.delayed(d);
