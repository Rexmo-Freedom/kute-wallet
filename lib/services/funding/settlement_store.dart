// lib/services/funding/settlement_store.dart
//
// The only writer of SettlementOperation records (Phase 5 plan B6).
//
// Invariants:
//  I1 every write is flushed before the call returns, so `broadcasting`
//     is on disk before the caller moves funds.
//  I2 `canQuote` is false once a record ever reached `broadcasting`.
//  I4 a record that ever reached `broadcasting` is never deleted; only
//     `abandoned` records that never did are pruned, after 7 days.
//  I6 stage changes follow [settlementTransitionAllowed].
// Writes are compare-and-set on the current stage and, when given, the
// record version, and are serialized per operation id.

import 'dart:async';

import 'package:hive_ce/hive.dart';
import 'package:kute/models/orchestra_routes_model.dart' show RouteKey;
import 'package:kute/models/settlement_operation.dart';
import 'package:kute/services/api/orchestra_api.dart';
import 'package:kute/services/funding/settlement_codec.dart';
import 'package:kute/services/funding/settlement_http.dart';
import 'package:kute/services/funding/settlement_reconciler.dart';
import 'package:kute/services/funding/settlement_stage.dart';
import 'package:kute/services/orchestra/orchestra_quote_guard.dart'
    show VerifiedOrchestraQuote;
import 'package:kute/services/tracking_service.dart';

/// `abandoned` records that never reached `broadcasting` are pruned this
/// long after they ended.
const Duration kSettlementAbandonedPruneAfter = Duration(days: 7);


const Set<SettlementStage> _preBroadcast = {
  SettlementStage.created,
  SettlementStage.quoted,
  SettlementStage.reviewed,
  SettlementStage.authorizing,
  SettlementStage.signed,
};

int _preBroadcastRank(SettlementStage s) => switch (s) {
      SettlementStage.created => 0,
      SettlementStage.quoted => 1,
      SettlementStage.reviewed => 2,
      SettlementStage.authorizing => 3,
      SettlementStage.signed => 4,
      _ => -1,
    };

const Set<SettlementStage> _providerOutcomes = {
  SettlementStage.lateDeposit,
  SettlementStage.failed,
  SettlementStage.refunding,
  SettlementStage.settled,
  SettlementStage.refunded,
};

/// The allowed stage graph (I6). Staying on a stage is always allowed (a
/// patch). Below `broadcasting` a stage may move forward, or back to
/// `quoted` when a quote is refreshed before funds move.
bool settlementTransitionAllowed(SettlementStage from, SettlementStage to) {
  if (from == to) return true;
  if (from.isTerminal) return false;
  if (_preBroadcast.contains(from)) {
    if (_preBroadcast.contains(to)) {
      return _preBroadcastRank(to) > _preBroadcastRank(from) ||
          to == SettlementStage.quoted;
    }
    return to == SettlementStage.broadcasting ||
        to == SettlementStage.abandoned ||
        // A provider order is positive evidence of a deposit.
        to == SettlementStage.funded;
  }
  switch (from) {
    case SettlementStage.broadcasting:
      return to == SettlementStage.funded ||
          to == SettlementStage.fundingUnknown ||
          to == SettlementStage.notFunded;
    case SettlementStage.fundingUnknown:
      return to == SettlementStage.funded || to == SettlementStage.notFunded;
    case SettlementStage.notFunded:
      return to == SettlementStage.funded || to == SettlementStage.lateDeposit;
    case SettlementStage.funded:
      return to == SettlementStage.submitted ||
          to == SettlementStage.processing ||
          to == SettlementStage.needsAttention ||
          _providerOutcomes.contains(to);
    case SettlementStage.needsAttention:
      return to == SettlementStage.submitted ||
          to == SettlementStage.processing ||
          _providerOutcomes.contains(to);
    case SettlementStage.submitted:
      return to == SettlementStage.processing ||
          to == SettlementStage.needsAttention ||
          _providerOutcomes.contains(to);
    case SettlementStage.processing:
      return to == SettlementStage.needsAttention ||
          _providerOutcomes.contains(to);
    case SettlementStage.lateDeposit:
    case SettlementStage.failed:
      return to == SettlementStage.refunding ||
          to == SettlementStage.settled ||
          to == SettlementStage.refunded;
    case SettlementStage.refunding:
      return to == SettlementStage.settled || to == SettlementStage.refunded;
    default:
      return false;
  }
}

/// The quote terms to persist for a verified quote. [skew] comes from the
/// quote response's `Date` header.
SettlementQuoteTerms settlementQuoteTermsFor(
  VerifiedOrchestraQuote verified, {
  Duration skew = Duration.zero,
  String? readToken,
}) {
  final q = verified.quote;
  return SettlementQuoteTerms(
    quoteId: verified.quoteId,
    depositAddress: verified.depositAddress,
    amountIn: verified.amountIn.toString(),
    estimatedOut: q.estimatedOut,
    lockedMinAmountOut: q.lockedMinAmountOut,
    feeBps: q.combinedFeeBps,
    totalFeeAmount: q.totalFeeAmount,
    feeAsset: q.feeAsset,
    priceLockMode: q.priceLockMode,
    expiresAt: verified.expiresAt,
    skew: skew,
    readToken: readToken,
  );
}

extension SettlementOperationKeys on SettlementOperation {
  /// The submit keys in the shape the submit wrapper takes. Null before a
  /// funding proof created them.
  SubmitIdempotencyKeys? get submitKeys {
    final current = keys.submit;
    if (current == null) return null;
    return SubmitIdempotencyKeys(
      current: current,
      history: keys.submitHistory,
      fingerprint: keys.submitFingerprint,
    );
  }

  SettlementKeys keysWithSubmit(SubmitIdempotencyKeys submit) => SettlementKeys(
        quote: keys.quote,
        submit: submit.current,
        submitHistory: submit.history,
        submitFingerprint: submit.fingerprint,
      );

  /// What the reconciler needs from this record.
  SettlementReconcileState toReconcileState({bool ownedByLiveFlow = false}) =>
      SettlementReconcileState(
        stage: stage,
        createdAt: createdAt,
        everBroadcast: everBroadcast,
        // A hot Spark record stopped at `broadcasting` before the kind was
        // stored there still gets the Spark payment lookup (B7).
        fundingKind: funding?.kind ??
            (accountKind == SettlementAccountKind.sparkHot &&
                    route.fromChain == 'spark'
                ? SettlementFundingKind.spark
                : null),
        hasFundingProof: funding?.hasProof ?? false,
        quoteExpiresAt: quote?.expiresAt,
        skew: quote?.skew ?? Duration.zero,
        broadcastingAt: firstEnteredAt(SettlementStage.broadcasting),
        fundedAt: firstEnteredAt(SettlementStage.funded),
        stageEnteredAt: stageEnteredAt,
        submitAccepted: submit.acceptedAt != null || submit.providerDetected,
        submitAttempts: submit.attempts,
        lastSubmitAttemptAt: submit.lastAttemptAt,
        lastCheckedAt: poll.lastCheckedAt,
        consecutiveFailures: poll.consecutiveFailures,
        sdkSyncsSinceBroadcasting: poll.sdkSyncsSinceBroadcasting,
        lastSdkSyncGeneration: poll.lastSdkSyncGeneration,
        ownedByLiveFlow: ownedByLiveFlow,
        recordVersion: version,
      );
}

enum SettlementStoreFailure {
  alreadyExists,
  invalidInitialStage,
  deleteRefused,
}

class SettlementStoreException implements Exception {
  const SettlementStoreException(this.failure);

  final SettlementStoreFailure failure;

  @override
  String toString() => 'SettlementStoreException(${failure.name})';
}

enum SettlementWriteStatus {
  applied,

  /// The record's stage or version changed since the caller read it.
  conflict,
  notFound,

  /// The stage change is not in the allowed graph.
  invalidTransition,
}

class SettlementWriteResult {
  const SettlementWriteResult(this.status, this.operation);

  final SettlementWriteStatus status;

  /// The written record when applied, otherwise the current one (null
  /// when not found).
  final SettlementOperation? operation;

  bool get applied => status == SettlementWriteStatus.applied;
}

class SettlementStore {
  SettlementStore({
    required Box<String> box,
    required Box<String> quarantine,
    DateTime Function() clock = DateTime.now,
    void Function()? onCorrupt,
  })  : _box = box,
        _quarantine = quarantine,
        _clock = clock,
        _onCorrupt = onCorrupt ?? TrackingService.settlementRecordCorrupt;

  static const String boxName = 'settlement_operations';
  static const String quarantineBoxName = 'settlement_quarantine';

  final Box<String> _box;
  final Box<String> _quarantine;
  final DateTime Function() _clock;
  final void Function() _onCorrupt;

  final Map<String, Future<void>> _tails = {};
  final Map<String, Object> _leases = {};
  final Set<String> _reportedUnreadable = {};

  /// Records written by a newer build that this build cannot read. They
  /// stay in the main box untouched.
  final Set<String> _unreadableFuture = {};

  static Future<SettlementStore>? _shared;

  /// The app-wide store, opening its boxes on first use. A failed open is
  /// retried on the next call; nothing is ever deleted to recover.
  static Future<SettlementStore> shared() {
    return _shared ??= open().catchError((Object e) {
      _shared = null;
      throw e;
    });
  }

  static Future<SettlementStore> open() async {
    Future<Box<String>> openBox(String name) async => Hive.isBoxOpen(name)
        ? Hive.box<String>(name)
        : await Hive.openBox<String>(name);
    final boxes = await Future.wait([
      openBox(boxName),
      openBox(quarantineBoxName),
    ]);
    return SettlementStore(box: boxes[0], quarantine: boxes[1]);
  }

  // ─────────────────────────────── leases ───────────────────────────────

  /// Marks [operationId] as held by a runner in this process. Returns the
  /// token to release it with, or null when another runner holds it.
  /// Leases are not persisted, so a killed process holds none.
  Object? acquireLease(String operationId) {
    if (_leases.containsKey(operationId)) return null;
    final token = Object();
    _leases[operationId] = token;
    return token;
  }

  void releaseLease(String operationId, Object token) {
    if (identical(_leases[operationId], token)) _leases.remove(operationId);
  }

  bool isLeased(String operationId) => _leases.containsKey(operationId);

  // ─────────────────────────────── reads ───────────────────────────────

  Future<SettlementOperation?> get(String operationId) => _read(operationId);

  Future<List<SettlementOperation>> all() async {
    final out = <SettlementOperation>[];
    for (final key in _box.keys.toList()) {
      if (key is! String) continue;
      final op = await _read(key);
      if (op != null) out.add(op);
    }
    return out;
  }

  /// Non-terminal operations on [walletId] and [route].
  Future<List<SettlementOperation>> activeFor(
      String walletId, RouteKey route) async {
    return (await all())
        .where((op) =>
            op.walletId == walletId &&
            op.route == route &&
            !op.stage.isTerminal)
        .toList();
  }

  /// Operations that block a new one on [walletId] and [route] (F11).
  /// Every operation the reconciler may still act on.
  Future<List<SettlementOperation>> pendingForReconcile() async =>
      (await all()).where((op) => !op.stage.isTerminal).toList();

  /// I2: a quote may be requested only below `broadcasting` for a record
  /// that never reached it.
  Future<bool> canQuote(String operationId) async {
    final op = await _read(operationId);
    return op != null && op.stage.isBeforeBroadcasting && !op.everBroadcast;
  }

  /// Quarantined records plus records from a newer build. The UI shows one
  /// row for them.
  Future<int> unreadableCount() async {
    for (final key in _box.keys.toList()) {
      if (key is String) await _read(key);
    }
    return _quarantine.length + _unreadableFuture.length;
  }

  // ─────────────────────────────── writes ───────────────────────────────

  /// Persists a new operation at version 1. A new operation starts at
  /// `created` or `quoted`; a recovered one ([SettlementOperation.recoveredFrom])
  /// starts at or after `broadcasting`.
  Future<SettlementOperation> create(SettlementOperation op) {
    return _locked(op.operationId, () async {
      if (_box.containsKey(op.operationId)) {
        throw const SettlementStoreException(
            SettlementStoreFailure.alreadyExists);
      }
      final recovered = op.recoveredFrom != null;
      final validStart = recovered
          ? op.stage.mayHaveMovedFunds
          : (op.stage == SettlementStage.created ||
              op.stage == SettlementStage.quoted);
      if (!validStart) {
        throw const SettlementStoreException(
            SettlementStoreFailure.invalidInitialStage);
      }
      final now = _clock();
      final record = op.copyWith(
        schema: kSettlementSchemaVersion,
        stageHistory: op.stageHistory.isEmpty
            ? [SettlementStageEntry(op.stage, now)]
            : op.stageHistory,
        updatedAt: now,
        version: 1,
      );
      await _write(record);
      return record;
    });
  }

  /// Moves [operationId] from [from] to [to] and applies [patch], only
  /// while the record is still at [from] (and [expectedVersion], when
  /// given). [patch] cannot change the id, wallet, stage or version. The
  /// write is flushed before this returns (I1).
  Future<SettlementWriteResult> transition(
    String operationId,
    SettlementStage to, {
    required SettlementStage from,
    int? expectedVersion,
    SettlementOperation Function(SettlementOperation current)? patch,
  }) {
    return _locked(operationId, () async {
      final current = await _read(operationId);
      if (current == null) {
        return const SettlementWriteResult(
            SettlementWriteStatus.notFound, null);
      }
      if (current.stage != from ||
          (expectedVersion != null && current.version != expectedVersion)) {
        return SettlementWriteResult(SettlementWriteStatus.conflict, current);
      }
      if (!settlementTransitionAllowed(from, to)) {
        return SettlementWriteResult(
            SettlementWriteStatus.invalidTransition, current);
      }
      final now = _clock();
      final patched = patch == null ? current : patch(current);
      final history = to == from
          ? current.stageHistory
          : List<SettlementStageEntry>.unmodifiable(
              [...current.stageHistory, SettlementStageEntry(to, now)]);
      final next = SettlementOperation(
        schema: current.schema,
        operationId: current.operationId,
        walletId: current.walletId,
        accountKind: current.accountKind,
        flow: current.flow,
        routeVersion: patched.routeVersion,
        route: current.route,
        amountInBaseUnits: patched.amountInBaseUnits,
        quote: patched.quote,
        quoteHistory: patched.quoteHistory,
        recipient: patched.recipient,
        refund: patched.refund,
        keys: patched.keys,
        stage: to,
        stageHistory: history,
        funding: patched.funding,
        orderId: patched.orderId,
        submit: patched.submit,
        poll: patched.poll,
        late: patched.late,
        refundObserved: patched.refundObserved,
        recoveredFrom: current.recoveredFrom,
        createdAt: current.createdAt,
        updatedAt: now,
        terminalAt: to.isTerminal && to != from ? now : current.terminalAt,
        version: current.version + 1,
        raw: current.raw,
      );
      await _write(next);
      return SettlementWriteResult(SettlementWriteStatus.applied, next);
    });
  }

  /// A write that keeps the stage.
  Future<SettlementWriteResult> update(
    String operationId, {
    required SettlementStage stage,
    int? expectedVersion,
    required SettlementOperation Function(SettlementOperation current) patch,
  }) =>
      transition(operationId, stage,
          from: stage, expectedVersion: expectedVersion, patch: patch);

  /// Writes one reconcile cycle's result. Applied only while the record
  /// still has the result's previous stage and record version, so a stale
  /// read never overwrites a runner's write. [providerStatus] is the raw
  /// status the cycle read, if any.
  Future<SettlementWriteResult> applyReconcileResult(
    String operationId,
    SettlementReconcileResult result, {
    String? providerStatus,
    String Function() generateKey = OrchestraService.generateIdempotencyKey,
  }) {
    final now = _clock();
    return transition(
      operationId,
      result.stage,
      from: result.previousStage,
      expectedVersion: result.expectedRecordVersion,
      patch: (op) {
        var keys = op.keys;
        final submitKeys = op.submitKeys;
        if (result.rotateSubmitKey && submitKeys != null) {
          keys = op.keysWithSubmit(submitKeys.afterOutcome(
              SettlementHttpOutcome.rejected,
              generateKey: generateKey));
        }
        var funding = op.funding;
        final paymentId = result.sparkPaymentId;
        if (paymentId != null && funding?.sparkPaymentId == null) {
          funding = (funding ??
                  const SettlementFunding(kind: SettlementFundingKind.spark))
              .copyWith(sparkPaymentId: paymentId);
        }
        final lateFlag = result.quoteExpiredBeforeFunding;
        final late = lateFlag != null
            ? SettlementLate(
                quoteExpiredBeforeFunding: lateFlag,
                detectedAt: lateFlag ? now : null,
              )
            : op.late;
        return op.copyWith(
          keys: keys,
          funding: funding,
          late: late,
          submit: SettlementSubmitState(
            attempts: result.submitAttempts,
            lastAttemptAt: result.lastSubmitAttemptAt,
            lastErrorCode: op.submit.lastErrorCode,
            acceptedAt:
                op.submit.acceptedAt ?? (result.submitAccepted ? now : null),
            providerDetected:
                op.submit.providerDetected || result.providerDetected,
          ),
          poll: SettlementPollState(
            providerStatus: providerStatus ?? op.poll.providerStatus,
            mappedStatus: result.stage.name,
            lastCheckedAt: result.lastCheckedAt,
            consecutiveFailures: result.consecutiveFailures,
            nextCheckAt: result.nextCheckAt,
            sdkSyncsSinceBroadcasting: result.sdkSyncsSinceBroadcasting,
            lastSdkSyncGeneration: result.lastSdkSyncGeneration,
          ),
        );
      },
    );
  }

  /// Deletes an `abandoned` record that never reached `broadcasting`.
  /// Anything else throws (I4).
  Future<void> delete(String operationId) {
    return _locked(operationId, () async {
      final op = await _read(operationId);
      if (op == null) return;
      _refuseUnlessPrunable(op);
      await _box.delete(operationId);
      await _box.flush();
    });
  }

  /// Removes `abandoned` records that never reached `broadcasting` and
  /// ended more than 7 days ago. Returns how many were removed.
  Future<int> prune({DateTime? now}) async {
    final at = now ?? _clock();
    var removed = 0;
    for (final op in await all()) {
      if (op.stage != SettlementStage.abandoned || op.everBroadcast) continue;
      final endedAt = op.terminalAt ?? op.updatedAt;
      if (at.difference(endedAt) <= kSettlementAbandonedPruneAfter) continue;
      await _locked(op.operationId, () async {
        final fresh = await _read(op.operationId);
        if (fresh == null ||
            fresh.stage != SettlementStage.abandoned ||
            fresh.everBroadcast) {
          return;
        }
        await _box.delete(op.operationId);
        await _box.flush();
        removed++;
      });
    }
    return removed;
  }

  void _refuseUnlessPrunable(SettlementOperation op) {
    if (op.stage != SettlementStage.abandoned || op.everBroadcast) {
      throw const SettlementStoreException(
          SettlementStoreFailure.deleteRefused);
    }
  }

  // ─────────────────────────────── internals ───────────────────────────────

  Future<void> _write(SettlementOperation op) async {
    await _box.put(op.operationId, SettlementCodec.encodeJson(op));
    await _box.flush();
  }

  Future<SettlementOperation?> _read(String operationId) async {
    final raw = _box.get(operationId);
    if (raw == null) return null;
    try {
      final op = SettlementCodec.decodeJson(raw);
      if (op.operationId != operationId) {
        throw const SettlementCodecException('operationId');
      }
      _unreadableFuture.remove(operationId);
      return op;
    } on SettlementCodecException {
      await _handleUnreadable(operationId, raw);
      return null;
    }
  }

  /// A record from a newer schema stays where it is. Any other undecodable
  /// record is copied with its raw text into the quarantine box, flushed,
  /// and only then removed from the main box. Quarantine is never pruned.
  Future<void> _handleUnreadable(String operationId, String raw) async {
    if (_reportedUnreadable.add(operationId)) _onCorrupt();
    final schema = SettlementCodec.peekSchema(raw);
    if (schema != null && schema > kSettlementSchemaVersion) {
      _unreadableFuture.add(operationId);
      return;
    }
    final key = '$operationId@${_clock().millisecondsSinceEpoch}';
    await _quarantine.put(key, raw);
    await _quarantine.flush();
    if (_box.get(operationId) == raw) {
      await _box.delete(operationId);
      await _box.flush();
    }
  }

  Future<T> _locked<T>(String operationId, Future<T> Function() body) {
    final previous = _tails[operationId] ?? Future<void>.value();
    final done = Completer<void>();
    final tail = done.future;
    _tails[operationId] = tail;
    return previous.then((_) => body()).whenComplete(() {
      done.complete();
      if (identical(_tails[operationId], tail)) _tails.remove(operationId);
    });
  }
}
