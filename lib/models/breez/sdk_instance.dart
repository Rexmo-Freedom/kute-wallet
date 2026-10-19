import 'dart:async';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as spark;
import 'package:flutter/foundation.dart';
import 'package:kute/models/breez/deposit_update.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/services/security/address_guard.dart'
    show sparkIdentityPubkeyHex;
import 'package:kute/models/breez/shared_sync.dart';
import 'package:kute/models/breez/sdk_operation_guard.dart';
import 'package:kute/models/breez/sdk_balance_telemetry.dart';
import 'package:kute/services/tracking/latency_tracker.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/wallet_identity_service.dart';

/// Three UI wait windows: a normal slow sync must finish before recovery is
/// considered. A Dart timeout cannot cancel the native operation.
const kSparkSyncStallAfter = Duration(minutes: 1);

class BreezSdkSpark {
  static final BreezSdkSpark _singleton = BreezSdkSpark._internal();

  factory BreezSdkSpark() => _singleton;

  BreezSdkSpark._internal()
      : _connectSdk = _nativeConnect,
        _syncStallAfter = kSparkSyncStallAfter,
        _syncWaitTimeout = const Duration(seconds: 20),
        _settlementObservation = kArrivalPollWindow,
        _balanceTelemetry = const SdkBalanceTelemetry();

  @visibleForTesting
  BreezSdkSpark.forTesting({
    required Future<spark.BreezSdk> Function(spark.ConnectRequest) connectSdk,
    Duration syncStallAfter = kSparkSyncStallAfter,
    Duration syncWaitTimeout = const Duration(seconds: 20),
    SdkBalanceTelemetry balanceTelemetry = const SdkBalanceTelemetry(),
    Duration settlementObservation = kArrivalPollWindow,
  })  : _connectSdk = connectSdk,
        _syncStallAfter = syncStallAfter,
        _syncWaitTimeout = syncWaitTimeout,
        _settlementObservation = settlementObservation,
        _balanceTelemetry = balanceTelemetry;

  static Future<spark.BreezSdk> _nativeConnect(spark.ConnectRequest req) {
    // ignore: invalid_use_of_internal_member
    return spark.BreezSdkSparkLib.instance.api.crateSdkConnect(request: req);
  }

  final Future<spark.BreezSdk> Function(spark.ConnectRequest) _connectSdk;
  final SdkBalanceTelemetry _balanceTelemetry;
  final Duration _syncStallAfter;
  final Duration _syncWaitTimeout;
  final Duration _settlementObservation;
  String? _connectedWalletId;
  final Set<String> _settlementSeen = {};
  final Map<String, _SettledSparkArrival> _settlementPending = {};
  Future<void> _lifecycle = Future<void>.value();
  int _generation = 0;

  /// Handles shut down whose native shutdown is not confirmed yet. Two
  /// live handles on one wallet would run two background processors and
  /// two in-memory leaf trees over one storage directory, so a new handle
  /// never connects before every one of these is confirmed down
  /// ([_confirmRetired]). Never a permanent block: each connect waits
  /// [teardownTimeout] for them, a failed shutdown is asked again, and the
  /// reconnect retries ([_scheduleReconnectRetry]) until they are down.
  final List<_RetiringHandle> _retiring = [];

  spark.BreezSdk? _instance;
  spark.ConnectRequest? _lastConnectRequest;
  Future<bool>? _balanceRecovery;
  bool _optimizationInProgress = false;
  Timer? _syncStallWatch;
  Future<void>? _watchedSync;
  spark.BreezSdk? _watchedSyncSdk;
  String _watchedSyncSource = 'unknown';
  int _watchedRecoveryAttempts = 0;
  void Function()? _stopWatchingSync;
  void Function()? _stopWatchingIdle;

  /// A [connect] is between its start and its outcome: no handle yet, and
  /// none is missing either.
  bool _connecting = false;

  /// The handle a pull-to-refresh retired whose replacement did not
  /// connect, so the one that finally does takes over its identity.
  spark.BreezSdk? _retiredByPull;
  Timer? _pullRetry;
  int _pullRetryAttempt = 0;

  /// When a reconnect could not connect (offline, or the old handle's
  /// shutdown not confirmed yet), the connect is tried again from the same
  /// request after each of these, without the unlock (no PIN, no passkey
  /// prompt); then every [reconnectSlowRetry] while the wallet has no
  /// handle. The next pull and an app resume or network change
  /// ([reconnectIfDown]) try at once.
  @visibleForTesting
  static List<Duration> pullRetryDelays = const [
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 30),
  ];

  /// The slow retry after [pullRetryDelays].
  @visibleForTesting
  static Duration reconnectSlowRetry = const Duration(seconds: 60);

  /// How long a connect waits for a retired handle's native shutdown
  /// before it gives up this try (the shutdown keeps going; the next try
  /// waits for the same one).
  @visibleForTesting
  static Duration teardownTimeout = const Duration(seconds: 15);

  /// A handle younger than this is as fresh as a restart: a pull inside it
  /// syncs rather than reconnecting again. Pulling twice in a row
  /// reconnects the first time and syncs the second.
  @visibleForTesting
  static Duration pullReconnectCooldown = const Duration(seconds: 25);

  /// Since the current handle connected.
  Stopwatch? _sinceConnected;

  /// A guarded recovery either installed a new handle or left no usable
  /// handle. Provider owners use this to refresh captured SDK consumers or
  /// re-enter the standard connection lifecycle after a failed replacement.
  final _recoveryController = StreamController<void>.broadcast();
  Stream<void> get recoveryStream => _recoveryController.stream;

  /// Every new handle, the moment it is installed (any connect: unlock,
  /// wallet switch, recovery, pull). Consumers bound to a handle (the
  /// push pipeline's Activity feed) re-bind at once instead of waiting
  /// for the first event of the new handle, so nothing it emits while
  /// they re-bind is missed.
  final _connectedController = StreamController<void>.broadcast(sync: true);
  Stream<void> get connectedStream => _connectedController.stream;

  static void _debugFeed(String detail) {
    if (kDebugMode) debugPrint('[sdk-feed] $detail');
  }

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

  Future<void> connect({required spark.ConnectRequest req, String? walletId}) {
    if (walletId != _connectedWalletId) {
      _settlementSeen.clear();
      _settlementPending.clear();
    }
    _connectedWalletId = walletId;
    final generation = ++_generation;
    final previous = _instance;
    _instance = null;
    _connecting = true;
    _forgetWalletReadings();
    final cancelled = _unsubscribeFromSdkStreams();
    final result = _lifecycle.then((_) async {
      // Throws [SparkTeardownPending] when an old handle is not confirmed
      // down within [teardownTimeout]: never two handles at once.
      await _finishSessionTeardown(previous, cancelled);
      if (_generation != generation) {
        throw StateError('Spark connection was superseded.');
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
        _debugFeed('lifecycle=native_connect_started');
        sdk = await _connectSdk(req);
        _debugFeed('lifecycle=native_connect_completed');
      } catch (_) {
        _debugFeed('lifecycle=native_connect_failed');
        _recordBootConnect(connectSw, result: 'error');
        rethrow;
      }
      _recordBootConnect(connectSw, result: 'ok');
      if (!_bootSyncMeasured) LatencyTracker.start(LatencyKeys.sparkSync);
      if (_generation != generation) {
        // The next connect waits until it is confirmed down.
        _beginRetire(sdk);
        throw StateError('Spark connection was superseded.');
      }
      _instance = sdk;
      _sinceConnected = Stopwatch()..start();
      _lastConnectRequest = req;
      TrackingService.setSessionKey('breez_connected', true);
      _initializeEventsStream(sdk);
      _subscribeToSdkStreams(sdk);
      _stopWatchingSync =
          observeSharedSync(sdk, (sync) => _watchSync(sdk, sync));
      _stopWatchingIdle = observeSparkIdle(sdk, () => _onSparkIdle(sdk));
      _connectedController.add(null);
      // Fetches may complete after a wallet switch; publication below checks
      // the exact SDK handle. Failures are retried by the sync pipelines.
      unawaited(_fetchWalletData(sdk).catchError((Object _) {}));
    });
    void settled() {
      if (_generation == generation) _connecting = false;
    }

    result.then((_) => settled(), onError: (Object _) => settled());
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
    _connectedWalletId = null;
    _settlementSeen.clear();
    _settlementPending.clear();
    ++_generation;
    final previous = _instance;
    _instance = null;
    _connecting = false;
    _pullRetry?.cancel();
    _pullRetry = null;
    _pullRetryAttempt = 0;
    _retiredByPull = null;
    _lastConnectRequest = null;
    _forgetWalletReadings();
    final cancelled = _unsubscribeFromSdkStreams();
    // Riverpod disposal is synchronous. Queue native teardown so a subsequent
    // connect cannot overlap the old Rust runtime's asynchronous disconnect.
    final result = _lifecycle.then((_) async {
      await _finishSessionTeardown(previous, cancelled);
    });
    _lifecycle =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
  }

  /// The wallet is going away: its balance readings and the arrivals
  /// waiting on it mean nothing for the next one.
  void _forgetWalletReadings() {
    _syncStallWatch?.cancel();
    _syncStallWatch = null;
    _watchedSync = null;
    _watchedSyncSdk = null;
    _stopWatchingSync?.call();
    _stopWatchingSync = null;
    _stopWatchingIdle?.call();
    _stopWatchingIdle = null;
    _balanceLog.clear();
    _publishedBalances = null;
    _publishedPayments = null;
    _arrivals.cancelAll();
    _optimizationInProgress = false;
  }

  Future<void> _finishSessionTeardown(
      spark.BreezSdk? previous, Future<void> cancelled) async {
    // FRB cancellation can wait for the native event listener to close.
    // Disconnect must start without waiting for cancellation, and every
    // retired handle must be confirmed down before a replacement owns this
    // wallet. The SDK's `disconnect` signals its background tasks to stop
    // and waits, with no timeout of its own, until all of them have; it
    // never fails by itself, so a failure is the bridge's and the native
    // state is unknown. Either way the wait is bounded here and the
    // handle stays on the list: the next connect waits for (or asks again)
    // the same shutdown instead of opening a second handle.
    // A cancellation failure is the listener's, never a confirmation that
    // the native side stopped: it is observed here and only the native
    // shutdown decides.
    final cancellation = cancelled.then<bool>((_) => true,
        onError: (Object _) => false);
    if (previous != null) _beginRetire(previous);
    await _confirmRetired();
    // Native shutdown is confirmed; the listener's cancellation follows it.
    try {
      if (!await cancellation.timeout(teardownTimeout)) {
        _debugFeed('lifecycle=stream_cancellation_failed');
      }
    } catch (_) {
      _debugFeed('lifecycle=stream_cancellation_unconfirmed');
    }
  }

  /// Starts [sdk]'s native shutdown and keeps it on [_retiring] until it
  /// is confirmed.
  void _beginRetire(spark.BreezSdk sdk) {
    for (final r in _retiring) {
      if (identical(r.sdk, sdk)) return;
    }
    final retiring = _RetiringHandle(sdk);
    _retiring.add(retiring);
    _shutDown(retiring);
  }

  void _shutDown(_RetiringHandle retiring) {
    retiring.failed = false;
    retiring.attempts++;
    final flight = Future<void>.sync(() {
      _debugFeed('lifecycle=native_disconnect_started');
      return retiring.sdk.disconnect();
    });
    retiring.flight = flight;
    flight.then((_) {
      if (!identical(retiring.flight, flight)) return;
      _debugFeed('lifecycle=native_disconnect_completed');
      _retiring.remove(retiring);
      if (retiring.reported) {
        _balanceTelemetry.teardown(
            result: SparkTeardownResult.confirmedLate,
            attempt: retiring.attempts,
            durationMs: retiring.clock.elapsedMilliseconds);
      }
    }, onError: (Object _) {
      if (!identical(retiring.flight, flight)) return;
      _debugFeed('lifecycle=native_disconnect_failed');
      retiring.failed = true;
    });
  }

  /// Waits, at most [teardownTimeout] per handle, until every retired
  /// handle is confirmed down. One whose shutdown failed is asked again
  /// (a handle whose tasks already stopped answers at once). Throws
  /// [SparkTeardownPending] when one is not confirmed yet.
  Future<void> _confirmRetired() async {
    for (final retiring in List.of(_retiring)) {
      if (!_retiring.contains(retiring)) continue;
      if (retiring.failed) _shutDown(retiring);
      try {
        await retiring.flight!.timeout(teardownTimeout);
      } catch (error) {
        retiring.reported = true;
        _balanceTelemetry.teardown(
            result: error is TimeoutException
                ? SparkTeardownResult.timeout
                : SparkTeardownResult.error,
            attempt: retiring.attempts,
            durationMs: retiring.clock.elapsedMilliseconds);
        throw const SparkTeardownPending();
      }
    }
  }

  /// Whether a retired handle's native shutdown is still unconfirmed.
  @visibleForTesting
  bool get teardownPending => _retiring.isNotEmpty;

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
        final info = await sdk.getInfo(
            request: const spark.GetInfoRequest(ensureSynced: false));
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
      final cancelled = sub?.cancel() ?? Future<void>.value();
      try {
        // AWAIT the teardown: disconnect() is async on v0.23, and
        // returning while the rust runtime is still flushing lets the
        // caller delete the throwaway probe dir under live writes
        // (leaving a stray synced wallet DB behind) and can overlap the
        // probe instance with the real wallet's subsequent connect. An
        // un-awaited failure would also escape this catch entirely.
        await _finishSessionTeardown(sdk, cancelled);
      } catch (_) {/* best-effort teardown */}
    }
  }

  Future<void> _fetchWalletData(spark.BreezSdk sdk) async {
    if (!identical(_instance, sdk)) return;
    // These are independent cached reads. A slow or failed balance read
    // must never hide newly synced payment rows (or the other way round).
    await Future.wait([_publishWalletInfo(sdk), _publishPayments(sdk)]);
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

  /// Last resort for the SDK's stale in-memory token store. Spark's normal
  /// sync returns early on a failed Bitcoin leaf refresh, before refreshing
  /// tokens; startup refreshes tokens independently, even when leaves fail
  /// (SparkWallet::sync vs start_event_processing in SDK 2c140a5).
  ///
  /// Keep the wrapper's broadcast streams alive and attach the replacement
  /// SDK to them, so every existing balance/payment subscriber follows it.
  /// A native mutation, a sync younger than the stall threshold, or a pending
  /// outgoing payment defers recovery. An aged sync is interrupted only by a
  /// successful native disconnect, never by clearing its Dart future. The
  /// synchronous mutation reservation also blocks a send from
  /// starting while the pending-payment check is in flight. Never throws.
  Future<bool> recoverStaleTokenBalance(spark.BreezSdk expected,
          {String source = 'unknown'}) =>
      _recoverTokenBalance(expected, source: source);

  Future<bool> _recoverTokenBalance(spark.BreezSdk expected,
      {required String source,
      bool settledArrival = false,
      bool pull = false,
      void Function(UsdRecoveryReason reason)? onDeferred}) {
    final running = _balanceRecovery;
    if (running != null) return running;
    final sw = Stopwatch()..start();
    Future<bool> defer(UsdRecoveryReason reason) {
      onDeferred?.call(reason);
      _balanceTelemetry.recovery(
          source: source,
          result: UsdRecoveryResult.deferred,
          reason: reason,
          attempted: false,
          durationMs: sw.elapsedMilliseconds);
      return Future.value(false);
    }

    final req = _lastConnectRequest;
    if (req == null) return defer(UsdRecoveryReason.notConnected);
    if (!identical(_instance, expected)) {
      return defer(UsdRecoveryReason.walletChanged);
    }
    // A settled arrival and a pull-to-refresh replace the handle even
    // while a young sync runs: a hot restart would too, and the sync it
    // interrupts is the one that is not landing.
    final waitsForSync = !settledArrival && !pull;
    if (waitsForSync && _syncBlocksRecovery(expected)) {
      return defer(UsdRecoveryReason.syncInFlight);
    }
    if (_optimizationInProgress) {
      return defer(UsdRecoveryReason.optimizationInFlight);
    }
    if (pull && sparkMoneyFlowInFlight) {
      return defer(UsdRecoveryReason.flowInFlight);
    }
    final reservation = reserveSparkRecovery(expected);
    if (reservation == null) return defer(UsdRecoveryReason.mutationInFlight);
    final generation = _generation;
    final result = () async {
      var outcome = UsdRecoveryResult.failed;
      var reason = UsdRecoveryReason.lookupFailed;
      var attempted = false;
      var report = true;
      var teardownPending = false;
      try {
        final payments = await expected
            .listPayments(request: const spark.ListPaymentsRequest())
            .timeout(const Duration(seconds: 5));
        if (payments.payments.any((p) =>
            p.paymentType == spark.PaymentType.send &&
            p.status == spark.PaymentStatus.pending)) {
          outcome = UsdRecoveryResult.deferred;
          reason = UsdRecoveryReason.pendingSend;
          return false;
        }
        if (_generation != generation || !identical(_instance, expected)) {
          outcome = UsdRecoveryResult.deferred;
          reason = UsdRecoveryReason.walletChanged;
          return false;
        }
        if ((waitsForSync && _syncBlocksRecovery(expected)) ||
            _optimizationInProgress ||
            (pull && sparkMoneyFlowInFlight)) {
          outcome = UsdRecoveryResult.deferred;
          reason = waitsForSync && _syncBlocksRecovery(expected)
              ? UsdRecoveryReason.syncInFlight
              : _optimizationInProgress
                  ? UsdRecoveryReason.optimizationInFlight
                  : UsdRecoveryReason.flowInFlight;
          return false;
        }
        reservation.retire();
        attempted = true;
        reason = UsdRecoveryReason.connectFailed;
        if (pull) _retiredByPull = expected;
        await connect(req: req, walletId: _connectedWalletId);
        final replacement = _instance;
        final connectedGeneration = _generation;
        if (replacement != null) {
          WalletIdentityService.rebindAfterReconnect(expected, replacement);
          if (identical(_retiredByPull, expected)) _retiredByPull = null;
          _pullRetry?.cancel();
          _pullRetry = null;
          _pullRetryAttempt = 0;
        }
        await rereadWalletData();
        // A later wallet session must never receive an old success event.
        report = _generation == connectedGeneration &&
            identical(_instance, replacement);
        outcome = UsdRecoveryResult.ok;
        reason = UsdRecoveryReason.reconnected;
        return true;
      } catch (error) {
        if (_generation != generation + (attempted ? 1 : 0)) {
          outcome = UsdRecoveryResult.deferred;
          reason = UsdRecoveryReason.walletChanged;
        } else if (!attempted && error is TimeoutException) {
          reason = UsdRecoveryReason.lookupTimeout;
        } else if (attempted && error is SparkTeardownPending) {
          reason = UsdRecoveryReason.teardownFailed;
          teardownPending = true;
        }
        return false;
      } finally {
        reservation.release();
        if (outcome == UsdRecoveryResult.deferred) onDeferred?.call(reason);
        // Only a completed, current recovery may rebuild dependent providers.
        // A healthy but busy/offline handle remains connected as before.
        // A pull's failed connect is tried again from the same request
        // instead: rebuilding the connection provider would unlock the
        // wallet again (a passkey prompt) for what the pull asked.
        if (report && attempted && _generation == generation + 1) {
          if (outcome == UsdRecoveryResult.ok) {
            _recoveryController.add(null);
          } else if (_instance == null) {
            // The old handle's shutdown not confirmed yet: rebuilding the
            // connection provider would only wait on the same shutdown.
            if (pull || teardownPending) {
              _scheduleReconnectRetry();
            } else {
              _recoveryController.add(null);
            }
          }
        }
        if (report) {
          _balanceTelemetry.recovery(
              source: source,
              result: outcome,
              reason: reason,
              attempted: attempted,
              durationMs: sw.elapsedMilliseconds);
        }
      }
    }();
    _balanceRecovery = result;
    result.then((_) {
      if (identical(_balanceRecovery, result)) {
        _balanceRecovery = null;
        final sdk = _instance;
        if (sdk != null) _retrySettledArrivals(sdk);
      }
    });
    return result;
  }

  /// Whether a [connect] is under way (no handle yet, none missing).
  bool get isConnecting => _connecting;

  /// Whether pull-to-refresh may reconnect the SDK now ([reconnectForPull]):
  /// the wallet was connected once (its request is kept, so no unlock is
  /// needed), the last native shutdown did not fail, no connect is under
  /// way, and nothing is mid-flight on the handle: a payment, prepare,
  /// claim or refund ([runSparkMutation]), a quote's creation
  /// ([runSparkQuote]) or a leaf optimization. A pending send the SDK
  /// lists is checked again by [reconnectForPull] itself.
  bool get canReconnectForPull {
    if (_lastConnectRequest == null || _connecting) return false;
    final sdk = _instance;
    // No handle (a connect that failed, a shutdown not confirmed yet):
    // always try again.
    if (sdk == null) return true;
    if (_optimizationInProgress ||
        sparkMoneyFlowInFlight ||
        sparkMutationInFlight(sdk)) {
      return false;
    }
    final age = _sinceConnected?.elapsed;
    return age == null || age >= pullReconnectCooldown;
  }

  /// An app resume or network change: when the wallet has no handle (a
  /// reconnect that could not connect yet), connect again from the kept
  /// request at once, retries starting over. Never throws.
  Future<bool> reconnectIfDown() {
    if (_instance != null || _connecting || _lastConnectRequest == null) {
      return Future.value(false);
    }
    _pullRetryAttempt = 0;
    return _reconnectFromSaved();
  }

  /// Pull-to-refresh as a hot restart does it, without the unlock: the
  /// live handle shut down and the wallet connected again from the same
  /// request, so the SDK refreshes its leaves and tokens from the
  /// operators at start and opens a new event stream. Every wrapper
  /// stream stays (nothing on screen is cleared: the balances keep their
  /// figure until the new handle's reading lands), the identity signer
  /// follows the new handle, and the connection provider is not rebuilt.
  ///
  /// The guarded recovery's every check applies (a payment, prepare,
  /// claim or refund running, a pending send in the SDK's list, a leaf
  /// optimization, plus a quote being created): any of them leaves the
  /// handle as it is and answers false, and the pull syncs instead. Only
  /// the young-sync wait does not: the sync a pull interrupts is the one
  /// whose figure is not landing. A reconnect already running is joined.
  /// With no handle (a connect that failed), connects again from the
  /// request. A connect that fails is tried again on its own
  /// ([pullRetryDelays]). Never throws.
  Future<bool> reconnectForPull() {
    final running = _balanceRecovery;
    if (running != null) return running;
    final sdk = _instance;
    if (sdk == null) return _reconnectFromSaved();
    return _recoverTokenBalance(sdk, source: 'pull', pull: true);
  }

  /// Connects again from the last request when there is no handle (a
  /// pull's connect failed, or the unlock's did after a first success).
  Future<bool> _reconnectFromSaved() {
    final running = _balanceRecovery;
    if (running != null) return running;
    final req = _lastConnectRequest;
    if (req == null || _instance != null || _connecting) {
      return Future.value(false);
    }
    final sw = Stopwatch()..start();
    final result = () async {
      var outcome = UsdRecoveryResult.failed;
      var reason = UsdRecoveryReason.connectFailed;
      try {
        await connect(req: req, walletId: _connectedWalletId);
        final replacement = _instance;
        if (replacement == null) return false;
        final retired = _retiredByPull;
        _retiredByPull = null;
        if (retired != null) {
          WalletIdentityService.rebindAfterReconnect(retired, replacement);
        }
        _pullRetry?.cancel();
        _pullRetry = null;
        _pullRetryAttempt = 0;
        await rereadWalletData();
        outcome = UsdRecoveryResult.ok;
        reason = UsdRecoveryReason.reconnected;
        if (identical(_instance, replacement)) _recoveryController.add(null);
        return true;
      } catch (error) {
        if (error is SparkTeardownPending) {
          reason = UsdRecoveryReason.teardownFailed;
        }
        if (_instance == null && !_connecting) _scheduleReconnectRetry();
        return false;
      } finally {
        _balanceTelemetry.recovery(
            source: 'pull',
            result: outcome,
            reason: reason,
            attempted: true,
            durationMs: sw.elapsedMilliseconds);
      }
    }();
    _balanceRecovery = result;
    result.then((_) {
      if (identical(_balanceRecovery, result)) _balanceRecovery = null;
    });
    return result;
  }

  void _scheduleReconnectRetry() {
    if (_lastConnectRequest == null) return;
    // Bounded backoff, then the slow retry for as long as there is no
    // handle; a disconnect (the session ending) stops it.
    final delay = _pullRetryAttempt < pullRetryDelays.length
        ? pullRetryDelays[_pullRetryAttempt]
        : reconnectSlowRetry;
    _pullRetryAttempt++;
    _pullRetry?.cancel();
    _pullRetry = Timer(delay, () {
      _pullRetry = null;
      if (_instance == null) unawaited(_reconnectFromSaved());
    });
  }

  /// Only completed, newly observed own-wallet Orchestra deliveries may use
  /// this entry point. The adapter excludes bootstrap history. One bounded
  /// observation precedes recovery; no young-sync exemption is public.
  Future<void> refreshCompletedSparkOrder(SwapOrder row) async {
    final walletId = _connectedWalletId;
    final sdk = _instance;
    final coin = row.coinTo.toUpperCase();
    if (sdk == null ||
        walletId == null ||
        row.walletId != walletId ||
        !row.isOrchestra ||
        row.status != 'success' ||
        row.networkTo.toUpperCase() != 'SPARK' ||
        (coin != 'BTC' && coin != 'USDB') ||
        row.id.isEmpty ||
        DateTime.now().difference(row.createdAt).abs() >
            const Duration(hours: 6)) {
      return;
    }
    final destination = sparkIdentityPubkeyHex(row.withdrawalAddress);
    final amount = double.tryParse(row.withdrawalAmount);
    if (destination == null ||
        amount == null ||
        !amount.isFinite ||
        amount <= 0) {
      return;
    }
    final key = '$walletId|${row.id}';
    if (_settlementSeen.contains(key) || _settlementPending.containsKey(key)) {
      return;
    }
    final pending = _SettledSparkArrival(
        row,
        destination,
        BigInt.from((amount * (coin == 'BTC' ? 1e8 : 1e6)).round()),
        _balanceLog.baselineSince(row.createdAt));
    _settlementPending[key] = pending;
    await _checkSettledArrival(key, pending, observe: true);
  }

  void _onSparkIdle(spark.BreezSdk sdk) {
    _retrySettledArrivals(sdk);
    _recoverWatchedStall(sdk);
  }

  void _retrySettledArrivals(spark.BreezSdk sdk) {
    if (!identical(_instance, sdk)) return;
    for (final entry in _settlementPending.entries.toList()) {
      if (!entry.value.running && entry.value.checks < 3) {
        unawaited(_checkSettledArrival(entry.key, entry.value));
      }
    }
  }

  Future<void> _checkSettledArrival(String key, _SettledSparkArrival pending,
      {bool observe = false}) async {
    if (pending.running) return;
    pending.running = true;
    final generation = _generation;
    bool sameWallet() =>
        _connectedWalletId == pending.row.walletId &&
        identical(_settlementPending[key], pending);
    bool live() => sameWallet() && _generation == generation;
    void done() {
      _settlementPending.remove(key);
      _settlementSeen.add(key);
    }

    try {
      var sdk = _instance;
      if (sdk == null || !live()) return;
      var identityConfirmed = false;
      Future<bool?> reflected() async {
        final current = _instance;
        if (current == null || !live()) return null;
        try {
          final info =
              await _getInfo(current).timeout(const Duration(seconds: 2));
          if (!live() || !identical(_instance, current)) return null;
          if (info.identityPubkey.toLowerCase() != pending.destination) {
            done(); // An external Spark recipient is never a recovery trigger.
            return true;
          }
          identityConfirmed = true;
          final payments = await current
              .listPayments(request: const spark.ListPaymentsRequest())
              .timeout(const Duration(seconds: 2));
          if (!live() || !identical(_instance, current)) return null;
          final balances = pending.row.coinTo.toUpperCase() == 'BTC'
              ? {'sats': info.balanceSats}
              : {
                  for (final entry in info.tokenBalances.entries)
                    if (entry.value.tokenMetadata.ticker.toUpperCase() ==
                        'USDB')
                      entry.key: entry.value.balance
                };
          final asset = pending.row.coinTo.toUpperCase() == 'BTC'
              ? ArrivalAsset.bitcoin
              : ArrivalAsset.dollars;
          final matching = payments.payments.any((p) =>
              p.paymentType == spark.PaymentType.receive &&
              p.status == spark.PaymentStatus.completed &&
              (p.amount - pending.units).abs() <= BigInt.one &&
              p.timestamp.toInt() * 1000 >= pending.row.timestamp - 10000 &&
              (asset == ArrivalAsset.bitcoin
                  ? p.details is! spark.PaymentDetails_Token
                  : p.details is spark.PaymentDetails_Token &&
                      (p.details as spark.PaymentDetails_Token)
                              .metadata
                              .ticker
                              .toUpperCase() ==
                          'USDB'));
          for (final entry in balances.entries) {
            if (!asset.counts(entry.key)) continue;
            final baseline = pending.baseline?[entry.key] ?? BigInt.zero;
            if (pending.baseline != null &&
                entry.value + BigInt.one >= baseline + pending.units) {
              return true;
            }
            if (pending.baseline == null &&
                matching &&
                entry.value >= pending.units) {
              return true;
            }
          }
          return false;
        } catch (_) {
          return null;
        }
      }

      if (await reflected() == true) {
        if (live()) done();
        return;
      }
      if (!live()) return;
      if (observe) {
        await Future<void>.delayed(_settlementObservation);
        if (!live()) return;
        if (await reflected() == true) {
          if (live()) done();
          return;
        }
      }
      sdk = _instance;
      if (!live() ||
          !identityConfirmed ||
          sdk == null ||
          _balanceRecovery != null ||
          _optimizationInProgress ||
          sparkMutationInFlight(sdk)) {
        return;
      }
      pending.checks++;
      _debugFeed('arrival=completed_order action=guarded_recovery');
      final recovered = await _recoverTokenBalance(sdk,
          source: 'order_leg', settledArrival: true, onDeferred: (reason) {
        if (reason == UsdRecoveryReason.pendingSend ||
            reason == UsdRecoveryReason.mutationInFlight ||
            reason == UsdRecoveryReason.optimizationInFlight) {
          pending.checks--;
        }
      });
      if (sameWallet() && (recovered || !identical(_instance, sdk))) done();
    } finally {
      pending.running = false;
    }
  }

  bool _syncBlocksRecovery(spark.BreezSdk sdk) {
    final age = sharedSyncAge(sdk);
    return sharedSyncInFlight(sdk) && (age == null || age < _syncStallAfter);
  }

  /// One timer per exact native flight, including automatic incoming arrival
  /// syncs, with at most three attempts after idle/completion events. Its
  /// future stays registered until native completion; the
  /// watchdog never pretends a timed-out operation was cancelled. Native
  /// disconnect must finish before any replacement can connect.
  Future<void> _syncWithStallWatch(spark.BreezSdk sdk,
      {required String source}) {
    final sync = sharedSyncWallet(sdk);
    _watchSync(sdk, sync, source: source);
    return sync;
  }

  void _recoverWatchedStall(spark.BreezSdk sdk) {
    if (!identical(_instance, sdk) ||
        !identical(_watchedSyncSdk, sdk) ||
        _watchedSync == null ||
        _balanceRecovery != null ||
        _optimizationInProgress ||
        sparkMutationInFlight(sdk) ||
        _watchedRecoveryAttempts >= 3 ||
        !sharedSyncInFlight(sdk) ||
        _syncBlocksRecovery(sdk)) {
      return;
    }
    _watchedRecoveryAttempts++;
    _debugFeed('sync=stalled action=guarded_recovery');
    unawaited(recoverStaleTokenBalance(sdk, source: _watchedSyncSource));
  }

  void _watchSync(spark.BreezSdk sdk, Future<void> sync,
      {String source = 'unknown'}) {
    if (!identical(_instance, sdk)) return;
    if (identical(_watchedSync, sync) && identical(_watchedSyncSdk, sdk)) {
      if (source != 'unknown') _watchedSyncSource = source;
      return;
    }
    _syncStallWatch?.cancel();
    _watchedSync = sync;
    _watchedSyncSdk = sdk;
    _watchedSyncSource = source;
    _watchedRecoveryAttempts = 0;
    void arm() {
      final age = sharedSyncAge(sdk) ?? Duration.zero;
      final remaining = _syncStallAfter - age;
      // Timer precision is milliseconds; truncating a fractional remainder
      // can fire before the monotonic age reaches the safety threshold.
      final delay = remaining <= Duration.zero
          ? Duration.zero
          : Duration(milliseconds: (remaining.inMicroseconds + 999) ~/ 1000);
      _syncStallWatch = Timer(delay, () {
        _syncStallWatch = null;
        if (!identical(_instance, sdk) ||
            !identical(_watchedSync, sync) ||
            !sharedSyncInFlight(sdk)) {
          return;
        }
        if (_syncBlocksRecovery(sdk)) {
          arm();
          return;
        }
        _recoverWatchedStall(sdk);
      });
    }

    arm();
    void release() {
      if (identical(_watchedSync, sync)) {
        _syncStallWatch?.cancel();
        _syncStallWatch = null;
        _watchedSync = null;
        _watchedSyncSdk = null;
      }
    }

    sync.then((_) => release(), onError: (Object _) => release());
  }

  /// One final cached read per shared native sync, even when its caller
  /// has stopped waiting. SDK sync completion alone does not prove that
  /// every native sync sub-step succeeded.
  final _syncReadbacks =
      Expando<({Future<void> sync, Future<void> readback})>('syncReadbacks');

  Future<void> _syncThenFetchWalletData(spark.BreezSdk sdk,
      {bool manual = false}) async {
    // Read immediately as well: a native sync can hold its event loop for
    // seconds, while the cached balance/history may already have changed.
    unawaited(_fetchWalletData(sdk));
    _debugFeed('sync=requested joined=${sharedSyncInFlight(sdk)}');
    final sync = _syncWithStallWatch(sdk, source: 'refresh');
    final existing = _syncReadbacks[sdk];
    final Future<void> readback;
    if (existing != null && identical(existing.sync, sync)) {
      readback = existing.readback;
    } else {
      Future<void> publish() async {
        if (identical(_instance, sdk)) await _fetchWalletData(sdk);
      }

      readback = sync.then((_) {
        _debugFeed(
            'sync=completed result=ok current=${identical(_instance, sdk)}');
        return publish();
      }, onError: (Object _) {
        _debugFeed(
            'sync=completed result=error current=${identical(_instance, sdk)}');
        return publish();
      });
      _syncReadbacks[sdk] = (sync: sync, readback: readback);
      void release() {
        if (identical(_syncReadbacks[sdk]?.readback, readback)) {
          _syncReadbacks[sdk] = null;
        }
      }

      readback.then((_) => release(), onError: (Object _) => release());
    }
    try {
      await readback.timeout(_syncWaitTimeout);
    } on TimeoutException {
      _debugFeed('sync=ui_wait result=timeout');
      if (identical(_instance, sdk) &&
          sharedSyncInFlight(sdk) &&
          !_syncBlocksRecovery(sdk)) {
        if (manual) {
          // One explicit refresh may try again after the automatic budget
          // was exhausted. Every signer/payment/shutdown guard still applies.
          unawaited(recoverStaleTokenBalance(sdk, source: 'refresh'));
        } else {
          _recoverWatchedStall(sdk);
        }
      }
      // Timing out does not cancel the native call or its final readback.
    } catch (_) {
      _debugFeed('sync=ui_wait result=error');
    }
  }

  /// A pull-to-refresh: publish cached balances and payments immediately,
  /// then join one shared wallet sync and publish again when it finishes.
  /// A 20-second UI timeout leaves the final native-completion read intact.
  /// Nothing to do without a connected wallet. Never throws.
  Future<void> syncAndReread() async {
    final sdk = _instance;
    if (sdk != null) await _syncThenFetchWalletData(sdk, manual: true);
  }

  /// What the app read of the connected wallet's balances, for the
  /// baseline of an arrival (see [syncAndRefresh]).
  final ArrivalBalanceLog _balanceLog = ArrivalBalanceLog();

  late final ArrivalRefresher _arrivals = ArrivalRefresher(
    readBalances: () async {
      final sdk = _instance;
      if (sdk == null) throw StateError('No SDK');
      final info = await sdk.getInfo(
          request: const spark.GetInfoRequest(ensureSynced: false));
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
        await _syncWithStallWatch(sdk, source: 'order_leg')
            .timeout(const Duration(seconds: 20));
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
  Map<String, BigInt>? _publishedBalances;
  List<spark.Payment>? _publishedPayments;

  Future<spark.GetInfoResponse> _getInfo(spark.BreezSdk sdk) async {
    // The event/sync has updated storage; read its cached snapshot without
    // waiting for the initial-Synced barrier again.
    const req = spark.GetInfoRequest(ensureSynced: false);
    final asked = ++_infoAsked;
    final walletInfo = await sdk.getInfo(request: req);
    if (identical(_instance, sdk) && asked > _infoPublished) {
      _infoPublished = asked;
      final balances = balancesOf(walletInfo);
      _balanceLog.record(balances, DateTime.now());
      _walletInfoController.add(walletInfo);
      if (kDebugMode) {
        final changed = !mapEquals(_publishedBalances, balances);
        _publishedBalances = balances;
        _debugFeed('read=balance result=published changed=$changed');
      }
    } else {
      _debugFeed('read=balance result=discarded reason=stale_read_or_session');
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
      _debugFeed('read=balance result=error');
      // The next event or read publishes again.
    }
  }

  Future<void> _publishPayments(spark.BreezSdk sdk) async {
    try {
      await _listPayments(sdk: sdk);
    } catch (_) {
      _debugFeed('read=payments result=error');
      // The next event or read retries this snapshot independently.
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
      if (kDebugMode) {
        final changed = !listEquals(_publishedPayments, response.payments);
        _publishedPayments = response.payments;
        _debugFeed('read=payments result=published changed=$changed');
      }
    } else {
      _debugFeed('read=payments result=discarded reason=stale_read_or_session');
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
        final stage = sdkSyncLogStage(entry.line);
        if (stage == null) return;
        // ignore: avoid_print
        print('[sdk-sync] $stage');
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

  /// Re-publishes balances and payments after the current SDK's `synced` events
  /// (see [SyncedReread]). One per SDK handle.
  SyncedReread? _syncedInfoReread;

  /// Subscribes to SdkEvent's stream
  void _subscribeToEventsStream(spark.BreezSdk sdk) {
    _syncedInfoReread?.dispose();
    final syncedInfoReread = SyncedReread(() {
      if (identical(_instance, sdk)) unawaited(_fetchWalletData(sdk));
    });
    _syncedInfoReread = syncedInfoReread;
    _breezEventsSubscription = _breezEventsStream?.listen(
      (event) async {
        if (!identical(_instance, sdk)) return;
        if (kDebugMode) {
          final kind = event.map(
            synced: (_) => 'synced',
            autoOptimization: (_) => 'auto_optimization',
            unclaimedDeposits: (_) => 'unclaimed_deposits',
            claimedDeposits: (_) => 'claimed_deposits',
            newDeposits: (_) => 'new_deposits',
            paymentSucceeded: (_) => 'payment_succeeded',
            paymentPending: (_) => 'payment_pending',
            paymentFailed: (_) => 'payment_failed',
            paymentMetadataUpdated: (_) => 'payment_metadata_updated',
            lightningAddressChanged: (_) => 'lightning_address_changed',
            unilateralExitStateChanged: (_) => 'unilateral_exit_state_changed',
          );
          _debugFeed('event=$kind');
        }
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
          autoOptimization: (e) {
            switch (e.optimizationEvent) {
              case spark.AutoOptimizationEvent_Started():
              case spark.AutoOptimizationEvent_RoundCompleted():
                _optimizationInProgress = true;
              case spark.AutoOptimizationEvent_Completed():
              case spark.AutoOptimizationEvent_Cancelled():
              case spark.AutoOptimizationEvent_Failed():
              case spark.AutoOptimizationEvent_Skipped():
                _optimizationInProgress = false;
            }
            if (!_optimizationInProgress) _onSparkIdle(sdk);
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
            _onSparkIdle(sdk);
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
          // Metadata can arrive after the payment's status. Publish its
          // refreshed row without treating it as a second payment result.
          paymentMetadataUpdated: (_) => unawaited(_publishPayments(sdk)),
          lightningAddressChanged: (_) {},
          // New in breez 0.23: fires when the SDK's tracked unilateral-exit
          // package state changes. The app has no unilateral-exit UI to
          // refresh, so this is a deliberate no-op (the comment above
          // restricts active refreshes to payment-class events).
          unilateralExitStateChanged: (_) {},
        );
      },
      onError: (Object _) {
        if (identical(_instance, sdk)) {
          _debugFeed('event_stream=error');
        }
      },
      onDone: () {
        if (identical(_instance, sdk)) {
          _debugFeed('event_stream=done');
        }
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
    _debugFeed('lifecycle=stream_cancellation_started');
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
    _debugFeed('lifecycle=stream_cancellation_completed');
  }
}

/// A connect gave up waiting for a retired handle's native shutdown. The
/// shutdown keeps going; the next connect waits for it (or asks again).
class SparkTeardownPending implements Exception {
  const SparkTeardownPending();

  @override
  String toString() =>
      'The previous Spark session is still closing. Try again shortly.';
}

/// A handle shut down whose native shutdown is not confirmed yet.
class _RetiringHandle {
  _RetiringHandle(this.sdk);

  final spark.BreezSdk sdk;
  final Stopwatch clock = Stopwatch()..start();
  Future<void>? flight;
  bool failed = false;
  int attempts = 0;

  /// A timeout or failure was reported for it.
  bool reported = false;
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

/// Re-reads wallet data after the SDK's `synced` events: at once on the
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
const String kSdkSyncDebugLogFilter = 'warn,breez_sdk_spark::sdk::sync=debug,'
    'breez_sdk_spark::utils::deposit_chain_syncer=info,'
    'breez_sdk_spark::chain::rest_client=debug,'
    'breez_sdk_spark::sdk::init=info,spark::tree::service=error';

/// Only constant stage names leave the native logger. Chain URLs, deposit
/// identifiers, amounts and raw errors must never be printed by diagnostics.
String? sdkSyncLogStage(String line) {
  const stages = {
    'Starting Wallet sync': 'wallet_started',
    'Wallet sync completed': 'wallet_completed',
    'Starting WalletState sync': 'wallet_state_started',
    'WalletState sync completed': 'wallet_state_completed',
    'Starting LnurlMetadata sync': 'lnurl_started',
    'LnurlMetadata sync completed': 'lnurl_completed',
    'Starting Deposits sync': 'deposits_started',
    'Deposits sync completed': 'deposits_completed',
    'Syncing deposit UTXOs via identity': 'deposit_scan_started',
    'Checking refund of deposit': 'deposit_refund_check',
    'Fetching static deposit claim quote': 'deposit_claim_quote_started',
    'Claiming static deposit for utxo': 'deposit_claim_started',
    'Claimed static deposit for utxo': 'deposit_claim_completed',
    'background claim completed, unclaimed deposits:': 'deposit_scan_completed',
    'Spark private mode initialized:': 'private_mode_initialized',
    'Failed to initialize spark private mode': 'private_mode_failed',
    'Error refreshing leaves on startup:': 'startup_leaves_failed',
    'Error refreshing token outputs on startup:': 'startup_tokens_failed',
    'Failed to check and claim static deposits': 'deposits_failed',
    'Spark wallet sync failed': 'wallet_failed',
    'Failed to query operator': 'operator_query_failed',
  };
  for (final entry in stages.entries) {
    if (line.contains(entry.key)) return entry.value;
  }
  if (line.contains('Fetching response json from')) {
    if (line.contains('/address/')) return 'chain_address_read_started';
    if (line.contains('/outspend/')) return 'chain_outspend_read_started';
    return 'chain_json_read_started';
  }
  if (line.contains('Fetching response text from')) {
    return 'chain_text_read_started';
  }
  return null;
}

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

class _SettledSparkArrival {
  _SettledSparkArrival(this.row, this.destination, this.units, this.baseline);
  final SwapOrder row;
  final String destination;
  final BigInt units;
  final Map<String, BigInt>? baseline;
  bool running = false;
  int checks = 0;
}
