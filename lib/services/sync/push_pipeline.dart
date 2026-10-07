// lib/services/sync/push_pipeline.dart
//
// Push-based balance + transaction signal from Breez SDK's
// `walletInfoStream`. Extracted from the inline implementation that
// used to live in `BackgroundSyncService._listenToWalletInfoStream`.
//
// What this pipeline owns:
//   1. The stream subscription itself, with re-attach on error /
//      done.
//   2. Exponential-backoff retry when the Breez SDK isn't ready at
//      attach time (e.g. session not yet unlocked, connect() still
//      in flight). Without retry, an unlock-time race would leave
//      the wallet "offline" forever.
//   3. Push cache writes — the Spark BTC balance — that fire
//      unconditionally on every event. These are what make incoming
//      Lightning feel instant on the home tile, regardless of the
//      user's current screen.
//   4. A debounced "the tx list might have changed" trigger that
//      is delegated back to the orchestrator (currently
//      [BackgroundSyncService]) via a callback. Debounce coalesces
//      bursts of HTLCs / spark transfers into one sync, and the
//      callback is route-gated by the orchestrator (no point
//      rebuilding the tx list while the user is on Settings).
//
// What this pipeline does NOT own:
//   - The full sync orchestration. The transaction-refresh path
//     stays in BackgroundSyncService for now; this pipeline just
//     pokes it. A future OnchainPipeline will fold both push +
//     periodic on-chain work into a single ownership boundary.
//   - The current-active-wallet decision. Spark is pinned to the
//     spending wallet at boot; we always write the cache for that
//     wallet's id, independent of which carousel page the user is
//     on.

import 'dart:async';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as breez;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/models/breez/deposit_update.dart';
import 'package:kute/providers/address_provider.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/breez_config_provider.dart';
import 'package:kute/providers/breez_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/transactions_provider.dart';
import 'package:kute/providers/usdb_provider.dart' show isUsdbTokenPayment;
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/services/sync/sync_pipeline.dart';
import 'package:kute/services/sync/sync_status.dart';
import 'package:kute/services/tracking_service.dart';

/// The settled incoming bitcoin payments in [transactions]' Spark rows:
/// id, sats and when. Dollar-token transfers never land in these rows.
List<({String id, int sats, DateTime at})> settledSparkReceives(
    Transaction? transactions) {
  if (transactions == null) return const [];
  return [
    for (final tx in transactions.sparkTransactions)
      if (tx.isConfirmed && tx.type == TransactionType.received)
        (id: tx.id, sats: tx.amountSats, at: tx.timestamp),
  ];
}

/// The identity of [transactions]' settled bitcoin receives: their ids,
/// in a stable order. Changes exactly when a receive settles.
String sparkReceivesSignature(Transaction? transactions) =>
    (settledSparkReceives(transactions).map((r) => r.id).toList()..sort())
        .join(',');

/// Brings the bitcoin balance up to date when a receive settles.
///
/// The SDK answers `getInfo()` from a cached balance, and a receive can
/// settle without the app seeing that figure refreshed: a sync that
/// records the payment as completed raises no payment event, so the
/// periodic `listPayments` shows it in Activity while every `getInfo()`
/// keeps the old figure until the SDK's next refresh. So the settled
/// receives are the trigger, as `UsdLedgerCatchUp` does for Dollars:
/// when they change and the SDK figure has not gone up with them, read
/// again shortly after; when that still returns the figure from before,
/// force one wallet sync (it rewrites the cached figure) and read again.
/// One run at a time; a change that lands mid-run queues one more.
/// Nothing repeats beyond that.
class SparkBalanceCatchUp {
  SparkBalanceCatchUp({
    required this.readSats,
    required this.syncWallet,
    required this.currentSats,
    required this.raisedAt,
    required this.publish,
    DateTime Function()? clock,
    this.delay = const Duration(milliseconds: 1500),
    this.syncTimeout = const Duration(seconds: 20),
  }) : _clock = clock ?? DateTime.now;

  /// The SDK's `getInfo()` bitcoin balance, in sats.
  final Future<int> Function() readSats;
  final Future<void> Function() syncWallet;

  /// The SDK figure the app holds now.
  final int Function() currentSats;

  /// When that figure last went up, or null.
  final DateTime? Function() raisedAt;
  final void Function(int sats) publish;
  final Duration delay;
  final Duration syncTimeout;
  final DateTime Function() _clock;

  /// An SDK figure that went up this close to the receives changing
  /// already counts the new receive (the payment event's own `getInfo()`
  /// lands just before its payments list; the periodic sync reads both
  /// in one pass).
  static const _countedWindow = Duration(seconds: 5);

  String? _signature;
  DateTime? _changedAt;
  Timer? _timer;
  bool _running = false;
  bool _again = false;
  bool _disposed = false;

  /// The settled receives' identity. The first call is the baseline;
  /// every later change schedules a catch-up.
  void onReceives(String signature) {
    if (_disposed) return;
    final previous = _signature;
    _signature = signature;
    if (previous == null || previous == signature) return;
    _changedAt = _clock();
    _timer?.cancel();
    _timer = Timer(delay, _run);
  }

  bool _countedAlready() {
    final raised = raisedAt();
    final changedAt = _changedAt;
    if (raised == null || changedAt == null) return false;
    return !raised.isBefore(changedAt.subtract(_countedWindow));
  }

  Future<void> _run() async {
    if (_disposed) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    try {
      do {
        _again = false;
        if (_countedAlready()) continue;
        final before = currentSats();
        int sats;
        try {
          sats = await readSats();
        } catch (_) {
          continue;
        }
        if (_disposed) return;
        if (sats != before) {
          publish(sats);
          continue;
        }
        // Same figure as before the receive: the SDK's cache has not
        // counted it yet. Sync, then read again.
        try {
          await syncWallet().timeout(syncTimeout);
        } catch (_) {
          // Read what the cache holds anyway.
        }
        if (_disposed) return;
        try {
          publish(await readSats());
        } catch (_) {
          // The next receive, SDK sync or payment event reads again.
        }
      } while (_again && !_disposed);
    } finally {
      _running = false;
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }
}

class PushPipeline implements SyncPipeline {
  PushPipeline({required this.onSyncRequested});

  /// Called (debounced) when the stream fires an event that suggests
  /// the transaction list may need refreshing. Implementation lives
  /// in BackgroundSyncService so we don't duplicate route-gating /
  /// in-progress checks here.
  final void Function() onSyncRequested;

  ProviderContainer? _container;
  StreamSubscription<breez.GetInfoResponse>? _subscription;
  StreamSubscription<List<breez.Payment>>? _paymentsSubscription;
  StreamSubscription<SparkDepositUpdate>? _depositsSubscription;
  StreamSubscription<void>? _syncedSubscription;
  ProviderSubscription<String>? _receivesSubscription;
  SparkBalanceCatchUp? _receivesCatchUp;
  int _depositRevision = 0;
  Timer? _retryTimer;
  Timer? _syncDebounce;
  Timer? _syncedBalanceRead;
  int _retryAttempt = 0;
  int _generation = 0;

  static const Duration _syncDebounceWindow = Duration(milliseconds: 500);

  /// Coalesces a burst of SDK `synced` events into one balance read.
  static const Duration _syncedReadDebounce = Duration(seconds: 1);
  static const int _maxBackoffShift = 5; // 1, 2, 4, 8, 16, 32 s ceiling

  /// Hashed deposit references ([TrackingService.orderRef] of
  /// `txid:vout`) already reported as auto-claimed / auto-claim-failed
  /// this app session. Static so a stop/start or SDK re-attach cannot
  /// re-report the same deposit. Raw outpoints never leave the device.
  static final Set<String> _autoClaimedRefs = <String>{};
  static final Set<String> _autoClaimFailedRefs = <String>{};

  @override
  String get debugName => 'PushPipeline';

  @override
  void start(ProviderContainer container) {
    _generation++;
    final gen = _generation;
    _container = container;
    _retryAttempt = 0;
    _attach(gen);
  }

  @override
  void stop() {
    _generation++;
    _subscription?.cancel();
    _subscription = null;
    _paymentsSubscription?.cancel();
    _paymentsSubscription = null;
    _depositsSubscription?.cancel();
    _depositsSubscription = null;
    _syncedSubscription?.cancel();
    _syncedSubscription = null;
    _receivesSubscription?.close();
    _receivesSubscription = null;
    _receivesCatchUp?.dispose();
    _receivesCatchUp = null;
    _syncedBalanceRead?.cancel();
    _syncedBalanceRead = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _syncDebounce?.cancel();
    _syncDebounce = null;
    _retryAttempt = 0;
    _container = null;
  }

  @override
  Future<void> kickNow() async {
    // Push pipeline is event-driven — `kickNow` re-attaches the
    // stream in case it silently dropped (e.g. socket recycled
    // while the app was paused). Equivalent to start() against the
    // current container.
    final container = _container;
    if (container == null) return;
    _generation++;
    _retryAttempt = 0;
    _attach(_generation);
  }

  void _attach(int gen) {
    _subscription?.cancel();
    _subscription = null;
    _paymentsSubscription?.cancel();
    _paymentsSubscription = null;
    _depositsSubscription?.cancel();
    _depositsSubscription = null;
    _syncedSubscription?.cancel();
    _syncedSubscription = null;
    _receivesSubscription?.close();
    _receivesSubscription = null;
    _receivesCatchUp?.dispose();
    _receivesCatchUp = null;
    _syncedBalanceRead?.cancel();
    _syncedBalanceRead = null;
    _retryTimer?.cancel();
    _retryTimer = null;

    final container = _container;
    if (container == null || _generation != gen) return;
    unawaited(_attachAsync(container, gen));
  }

  Future<void> _attachAsync(ProviderContainer container, int gen) async {
    final status = container.read(syncPipelineStatusProvider.notifier);
    try {
      final walletId = pickSpendingWallet(container.read(settingsProvider))?.id;
      final sdkWrapper = await container.read(breezSDKProvider.future);
      if (_container == null || _generation != gen) return;
      if (sdkWrapper.instance == null) {
        status.markFailure(debugName, 'Breez SDK not ready');
        _scheduleRetry(gen);
        return;
      }
      if (walletId == null ||
          walletId != pickSpendingWallet(container.read(settingsProvider))?.id) {
        _scheduleRetry(gen);
        return;
      }
      final sdk = sdkWrapper.instance!;
      bool isCurrent() =>
          _container != null &&
          _generation == gen &&
          identical(sdkWrapper.instance, sdk) &&
          walletId ==
              pickSpendingWallet(container.read(settingsProvider))?.id;
      // The wrapper streams outlive a reconnect this pipeline did not start.
      // Events from a replaced handle trigger exactly one re-attach.
      var reattachScheduled = false;
      bool followsSdk() {
        if (isCurrent()) return true;
        if (!reattachScheduled &&
            _container != null &&
            _generation == gen &&
            !identical(sdkWrapper.instance, sdk)) {
          reattachScheduled = true;
          _scheduleRetry(gen);
        }
        return false;
      }

      _retryAttempt = 0;
      _subscription = sdkWrapper.walletInfoStream.listen(
        (info) {
          if (!followsSdk()) return;
          status.markSuccess(debugName);
          _onEvent(info, gen);
        },
        onError: (e) {
          status.markFailure(debugName, e.toString());
          _scheduleRetry(gen);
        },
        onDone: () {
          status.markFailure(debugName, 'Stream closed');
          _scheduleRetry(gen);
        },
      );
      // Also subscribe to the SDK's payments stream so a new
      // Lightning / Spark payment lands in the per-wallet tx
      // cache *immediately* — no waiting for the debounced sync
      // tick. Previous design relied on `onSyncRequested` to
      // refresh the tx list, which got gated off when the user
      // wasn't on /home or when a sync was already in progress;
      // result was the user seeing the new balance but having to
      // pull-to-refresh to see the matching tx row. Stream-fed
      // updates eliminate that mismatch.
      _paymentsSubscription = sdkWrapper.paymentsStream.listen(
        (payments) {
          if (followsSdk()) _onPaymentsEvent(payments, gen);
        },
        onError: (_) {/* tx list will catch up via the debounced sync */},
      );
      _depositsSubscription = sdkWrapper.depositsStream.listen(
        (update) {
          if (!followsSdk()) return;
          _depositRevision++;
          trackAutoClaimEvent(update);
          _onDepositsEvent(update, gen);
        },
        onError: (_) {},
      );

      // SDK events carry only changed outpoints. Hydrate pending deposits on
      // every attach so missed/background events do not strand cached rows.
      // If an event races the read, retry instead of overwriting newer state.
      var snapshotRunning = false;
      var snapshotRequested = false;
      Future<void> hydrateDeposits() async {
        if (snapshotRunning) {
          snapshotRequested = true;
          return;
        }
        snapshotRunning = true;
        try {
          do {
            snapshotRequested = false;
            for (var attempt = 0; attempt < 2; attempt++) {
              final revision = _depositRevision;
              try {
                final snapshot = await sdk
                    .listUnclaimedDeposits(
                      request: const breez.ListUnclaimedDepositsRequest(),
                    )
                    .timeout(const Duration(seconds: 10));
                if (!isCurrent()) return;
                if (revision != _depositRevision) continue;
                _onDepositsEvent(
                    SparkDepositUpdate(
                      SparkDepositUpdateKind.snapshot,
                      snapshot.deposits,
                    ),
                    gen);
              } catch (_) {
                // Keep known pending deposits on a failed read; periodic sync retries.
              }
              break;
            }
          } while (snapshotRequested && isCurrent());
        } finally {
          snapshotRunning = false;
        }
      }

      final cacheNotifier = container.read(walletBalanceCacheProvider.notifier);

      // After each SDK sync, re-read the bitcoin balance too. The sync
      // rewrites the SDK's cached figure from its leaves, but raises no
      // event the app re-reads on: before this, only payment events and
      // the 2 s poll (which runs on the sync routes only) re-read it, so
      // a receive that arrived through a sync stayed off the balance on
      // any other screen. Debounced so a burst of syncs is one read;
      // applied as a poll read, so the stream-freshness and zero guards
      // still apply.
      Future<void> readBalanceAfterSync() async {
        try {
          final info = await sdk.getInfo(
              request: const breez.GetInfoRequest(ensureSynced: false));
          if (!isCurrent()) return;
          cacheNotifier.updateSparkBitcoinbalance(
              walletId, info.balanceSats.toInt(),
              source: BalanceSource.poll);
        } catch (_) {
          // The next sync, payment event or poll reads again.
        }
      }

      _syncedSubscription = sdkWrapper.syncedStream.listen(
        (_) {
          if (!followsSdk()) return;
          unawaited(hydrateDeposits());
          _syncedBalanceRead?.cancel();
          _syncedBalanceRead = Timer(_syncedReadDebounce, () {
            if (isCurrent()) unawaited(readBalanceAfterSync());
          });
        },
        onError: (_) {},
      );
      unawaited(hydrateDeposits());

      final catchUp = SparkBalanceCatchUp(
        readSats: () async => (await sdk.getInfo(
                request: const breez.GetInfoRequest(ensureSynced: false)))
            .balanceSats
            .toInt(),
        syncWallet: () =>
            sdk.syncWallet(request: const breez.SyncWalletRequest()),
        currentSats: () => cacheNotifier.sparkSdkSats(walletId),
        raisedAt: () => cacheNotifier.sparkSdkRaisedAt(walletId),
        publish: (sats) {
          if (!isCurrent()) return;
          cacheNotifier.updateSparkBitcoinbalance(walletId, sats,
              source: BalanceSource.poll);
        },
      );
      _receivesCatchUp = catchUp;

      // Settled bitcoin receives, wherever they reach the transaction
      // list (this pipeline's payments stream or the periodic sync's
      // `listPayments`). A receive that settles while a send hold caps
      // the balance raises that hold's ceiling, so it shows at once; one
      // the SDK's cached figure has not counted yet is caught up.
      _receivesSubscription = container.listen<String>(
        walletTransactionCacheProvider
            .select((all) => sparkReceivesSignature(all[walletId])),
        (_, signature) {
          if (!isCurrent()) return;
          cacheNotifier.noteSparkReceives(
              walletId,
              settledSparkReceives(
                  container.read(walletTransactionCacheProvider)[walletId]));
          catchUp.onReceives(signature);
        },
        fireImmediately: true,
      );

      // One-shot authoritative balance read right after subscribing.
      // `walletInfoStream` only delivers FUTURE emissions, so a balance
      // that landed BEFORE this subscription is never seen:
      //   - a first receive that arrives during the 2s startup delay,
      //     before the pipeline attaches, and
      //   - a resume re-attach after the app was backgrounded,
      // both leave the cache on its stale/0 value until the next stream
      // tick or a freshness-gated sync — the "balance reads 0 (and Send
      // says insufficient) until pull-to-refresh" bug. Read getInfo() now
      // and apply it ONLY when it RAISES the cached balance, so a
      // transient reconnect 0 (or a mid-reconcile dip) can never lower a
      // good value here. Genuine decreases / drains-to-0 still arrive
      // authoritatively through the stream.
      try {
        final info = await sdk.getInfo(request: const breez.GetInfoRequest());
        if (isCurrent()) {
          final spending = pickSpendingWallet(container.read(settingsProvider));
          if (spending == null) return;
          final cache = container.read(walletBalanceCacheProvider);
          final cacheNotifier =
              container.read(walletBalanceCacheProvider.notifier);
          final freshSpark = info.balanceSats.toInt();
          if (freshSpark > (cache[spending.id]?.sparkBitcoinbalance ?? 0)) {
            cacheNotifier.updateSparkBitcoinbalance(
              spending.id,
              freshSpark,
              source: BalanceSource.poll,
            );
          }
          // The USDB balance push died with the Flashnet Earn product.
          // Token PAYMENTS still route into UsdbTokenTransaction below
          // via the PaymentMethod.token guard, never the BTC bucket.
        }
      } catch (_) {
        // Non-fatal: the stream or the next sync tick will catch up.
      }

      // One-shot payments read, for the SAME reason as the balance one:
      // `paymentsStream` also only delivers FUTURE emissions, so a first
      // receive on a NEW wallet that lands before this subscription attaches
      // never populates the tx cache — the balance ticks up (fixed above) but
      // the matching "Received" row doesn't appear until a manual refresh.
      // Pull the current list and feed the SAME handler the stream uses.
      try {
        final resp =
            await sdk.listPayments(request: const breez.ListPaymentsRequest());
        if (isCurrent()) {
          _onPaymentsEvent(resp.payments.toList(), gen);
        }
      } catch (_) {
        // Non-fatal: the stream or the next sync tick will catch up.
      }
    } catch (e) {
      status.markFailure(debugName, e.toString());
      _scheduleRetry(gen);
    }
  }

  /// Push the freshest list of Spark / Lightning payments into the
  /// per-wallet tx cache as soon as the SDK surfaces it. The cache
  /// is the source of truth that the home Activity feed reads, so
  /// once we write here the new row appears in the next frame.
  void _onPaymentsEvent(List<breez.Payment> payments, int gen) {
    final container = _container;
    if (container == null || _generation != gen) return;
    try {
      final spending = pickSpendingWallet(container.read(settingsProvider));
      if (spending == null) return;
      final spendingId = spending.id;

      // Bucket payments by spark "kind" and direction. Builds
      // `SparkTransaction` rows the same way `updateTransactionsFor`
      // does on the periodic path — the cache merge below replaces
      // ONLY the spark side, leaving Bitcoin / Polymarket / Outlogic
      // / swap-order entries that were captured by the periodic sync
      // untouched.
      final sparkTxs = <SparkTransaction>[];
      final usdbTokenTxs = <UsdbTokenTransaction>[];
      for (final p in payments) {
        // Another token's transfer is neither dollars nor sats: it stays
        // out of both buckets, as it does on the periodic path.
        if (p.method == breez.PaymentMethod.token && !isUsdbTokenPayment(p)) {
          continue;
        }
        final isUsdbToken = p.method == breez.PaymentMethod.token;
        final tx = SparkTransaction(
          id: p.id,
          timestamp:
              DateTime.fromMillisecondsSinceEpoch(p.timestamp.toInt() * 1000),
          details: p,
          isConfirmed: p.status == breez.PaymentStatus.completed,
        );
        if (isUsdbToken) {
          usdbTokenTxs.add(UsdbTokenTransaction(
            id: p.id,
            timestamp: tx.timestamp,
            details: p,
            isConfirmed: tx.isConfirmed,
          ));
        } else {
          sparkTxs.add(tx);
        }
      }

      container.read(walletTransactionCacheProvider.notifier).mergeForWallet(
            spendingId,
            (current) => current.copyWith(
              sparkTransactions: sparkTxs,
              usdbTokenTransactions: usdbTokenTxs,
            ),
          );

      // Pin the Spark BTC balance non-increasing while at least one
      // outgoing Spark send is pending. Without this pin, the SDK's
      // walletInfoStream periodically re-emits a stale pre-deduction
      // balance and the home card bounces between deducted and
      // pre-send right up until confirmation. The flag clears as
      // soon as paymentsStream reports zero pending outgoing.
      final hasPendingOutgoing = payments.any(
        (p) =>
            p.status == breez.PaymentStatus.pending &&
            p.paymentType == breez.PaymentType.send,
      );
      final cacheNotifier = container.read(walletBalanceCacheProvider.notifier);
      cacheNotifier.setPendingOutgoingSparkSend(spendingId, hasPendingOutgoing);
      // End the holds of sends that failed (the SDK figure, refund
      // included, shows again) and start the grace of completed ones.
      final failedSends = <String>{};
      final completedSends = <String>{};
      for (final p in payments) {
        if (p.paymentType != breez.PaymentType.send) continue;
        if (p.status == breez.PaymentStatus.failed) failedSends.add(p.id);
        if (p.status == breez.PaymentStatus.completed) {
          completedSends.add(p.id);
        }
      }
      cacheNotifier.reconcileSparkSendHolds(spendingId,
          failed: failedSends, completed: completedSends);
    } catch (_) {}
  }

  /// Analytics for the SDK's own background claim (auto-claim). Only SDK
  /// events reach here — never the `listUnclaimedDeposits` snapshot — and
  /// the SDK emits ClaimedDeposits / UnclaimedDeposits from its sync-time
  /// auto-claim only; a manual `claimDeposit` returns its payment instead
  /// (and emits `spark_deposit_claimed` at its call site). Each deposit is
  /// reported at most once per session per event name (the first outcome
  /// seen wins), keyed by a hashed outpoint.
  @visibleForTesting
  static void trackAutoClaimEvent(SparkDepositUpdate update) {
    try {
      for (final deposit in update.deposits) {
        final ref = TrackingService.orderRef(
            sparkOutpointKey(deposit.txid, deposit.vout));
        switch (update.kind) {
          case SparkDepositUpdateKind.claimed:
            if (!_autoClaimedRefs.add(ref)) continue;
            TrackingService.track('spark_deposit_auto_claimed', params: {
              'outcome': deposit.instantClaimStatus
                      is breez.InstantClaimStatus_Submitted
                  ? 'instant_submitted'
                  : 'claimed',
            });
          case SparkDepositUpdateKind.upsert:
            // NewDeposits also arrive as upserts; only a deposit carrying
            // a claim error is an auto-claim that failed.
            final error = deposit.claimError;
            if (error == null || !_autoClaimFailedRefs.add(ref)) continue;
            TrackingService.autoClaimFailed(
              amountSats: 0,
              reason: autoClaimFailureCategory(error),
            );
          case SparkDepositUpdateKind.snapshot:
            break;
        }
      }
    } catch (_) {/* never let analytics break deposit sync */}
  }

  /// Fixed, low-cardinality reason for `auto_claim_failed`. Never carries
  /// any part of the SDK's message.
  @visibleForTesting
  static String autoClaimFailureCategory(breez.DepositClaimError error) =>
      switch (error) {
        breez.DepositClaimError_MaxDepositClaimFeeExceeded() => 'fee_exceeded',
        breez.DepositClaimError_MissingUtxo() => 'missing_utxo',
        breez.DepositClaimError_Generic(:final message) =>
          TrackingService.errorCategory(message),
      };

  @visibleForTesting
  static void resetAutoClaimTrackingForTest() {
    _autoClaimedRefs.clear();
    _autoClaimFailedRefs.clear();
  }

  /// Apply only the outpoints changed by an SDK event. A fresh list read is
  /// the only snapshot; one successful claim must not hide another deposit.
  void _onDepositsEvent(SparkDepositUpdate update, int gen) {
    final container = _container;
    if (container == null || _generation != gen) return;
    try {
      final spending = pickSpendingWallet(container.read(settingsProvider));
      if (spending == null) return;
      final spendingId = spending.id;
      final current =
          container.read(walletTransactionCacheProvider)[spendingId];
      if (current != null) {
        final next = applySparkDepositUpdate(
          current.sparkUnclaimedDeposits,
          update,
          now: DateTime.now(),
          settledOutpoints:
              sparkDepositPaymentOutpoints(current.sparkTransactions),
          mempoolTxids: {
            for (final pending in current.sparkPendingDeposits)
              pending.mempoolTx.txid.toLowerCase(),
          },
        );
        // Every SDK sync re-reads the list. Unchanged rows skip the feed
        // rebuild and the synchronous full-history write.
        if (!sameSparkDepositRows(current.sparkUnclaimedDeposits, next)) {
          final notifier =
              container.read(walletTransactionCacheProvider.notifier);
          notifier.mergeForWallet(
            spendingId,
            (latest) => latest.copyWith(sparkUnclaimedDeposits: next),
          );
          notifier.persistNowForWallet(spendingId);
        }
      }
      // Refresh on every settled batch, including when other deposits remain.
      if (update.hasSettledClaims) {
        container.invalidate(getSparkBitcoinAddressProvider);
        container.invalidate(initialAddressesProvider);
      }
    } catch (_) {}
  }

  void _onEvent(breez.GetInfoResponse info, int gen) {
    final container = _container;
    if (container == null || _generation != gen) return;
    try {
      final spending = pickSpendingWallet(container.read(settingsProvider));
      if (spending == null) return;
      final spendingId = spending.id;
      final cacheNotifier = container.read(walletBalanceCacheProvider.notifier);
      cacheNotifier.updateSparkBitcoinbalance(
        spendingId,
        info.balanceSats.toInt(),
        source: BalanceSource.stream,
      );
    } catch (_) {}

    _syncDebounce?.cancel();
    _syncDebounce = Timer(_syncDebounceWindow, () {
      if (_container == null || _generation != gen) return;
      onSyncRequested();
    });
  }

  void _scheduleRetry(int gen) {
    if (_container == null || _generation != gen) return;
    _retryTimer?.cancel();
    _retryAttempt = (_retryAttempt + 1).clamp(1, _maxBackoffShift + 1);
    final delaySec = 1 << (_retryAttempt - 1);
    _retryTimer = Timer(Duration(seconds: delaySec), () {
      if (_container == null || _generation != gen) return;
      _attach(gen);
    });
  }
}
