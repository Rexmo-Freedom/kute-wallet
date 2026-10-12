// lib/services/funding/settlement_runner.dart
//
// Runs one Orchestra settlement operation for a hot flow (Phase 5 plan
// B5, B6, B7). Each flow supplies callbacks; the runner owns ordering and
// persistence:
//
//   blocked check -> availability -> ownership -> created -> quote
//   -> quoted (persisted before any review) -> review -> reviewed
//   -> authorize (Phase 1b hook) -> margin check (refresh before send)
//   -> prepare (moves nothing) -> broadcasting (flushed) -> fund
//   -> funded (proof + submit key) -> submit -> submitted
//
// Pay-once rules:
//  - no quote is requested once the record ever reached `broadcasting`;
//  - a quote refreshed after review is never paid without another review;
//    a flow with no in-run review goes back to its review state
//    ([SettlementStopReason.quoteReplaced]) and needs another confirm tap;
//  - `fund` is only ever called with the quote id `review` accepted;
//  - `fund` throwing after `broadcasting` gives `fundingUnknown`, never
//    `abandoned`, and nothing retries it;
//  - a new operation on the same wallet and route is refused while an
//    earlier one may have moved funds and is unresolved (F11);
//  - a failed submit leaves the operation `funded` for the reconciler,
//    which retries with the persisted key.

import 'dart:async';

import 'package:kute/helpers/orchestra_legacy_status_rules.dart'
    show OrchestraStatusReadKind, classifyOrchestraStatusRead;
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/models/settlement_operation.dart';
import 'package:kute/models/orchestra_model.dart' show OrchestraSubmitResponse;
import 'package:kute/handlers/response_handlers.dart' show Result;
import 'package:kute/services/api/orchestra_api.dart';
import 'package:kute/services/funding/owned_address_resolver.dart';
import 'package:kute/services/funding/settlement_funding_outcome.dart';
import 'package:kute/services/funding/settlement_http.dart';
import 'package:kute/services/funding/settlement_quote_policy.dart';
import 'package:kute/services/funding/settlement_reconciler.dart'
    show SubmitAttemptOutcome;
import 'package:kute/services/funding/settlement_stage.dart';
import 'package:kute/services/funding/settlement_store.dart';
import 'package:kute/services/orchestra/orchestra_quote_guard.dart';
import 'package:kute/services/security/wallet_guard_exception.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/debug/settlement_fault_registry.dart';

/// How many silent refreshes a run makes before giving up. Each is a new
/// deliberate quote with a new idempotency key.
const int kSettlementMaxSilentRefreshes = 2;

/// A verified quote and the clock skew its response carried.
class SettlementQuoteResult {
  const SettlementQuoteResult(this.quote, {this.skew});

  final VerifiedOrchestraQuote quote;

  /// Server minus local clock; null when the response had no `Date`.
  final Duration? skew;
}

/// What left the source account, as the flow's `fund` callback saw it.
class SettlementFundingProof {
  const SettlementFundingProof.spark(String paymentId)
      : kind = SettlementFundingKind.spark,
        sparkPaymentId = paymentId,
        evmTxHash = null;

  const SettlementFundingProof.relayer(String txHash)
      : kind = SettlementFundingKind.relayer,
        sparkPaymentId = null,
        evmTxHash = txHash;

  /// A HyperCore source send (P4.12 reverse). The hash is submitted as
  /// `txHash` with the Hyperliquid account as `sourceAddress`.
  const SettlementFundingProof.hyperliquid(String txHash)
      : kind = SettlementFundingKind.hyperliquid,
        sparkPaymentId = null,
        evmTxHash = txHash;

  final SettlementFundingKind kind;
  final String? sparkPaymentId;
  final String? evmTxHash;
}

/// The step-up intent a Phase 1b grant binds to (F3). The destination is
/// the final recipient plus the route version, the provider is always
/// `orchestra`, and the provider deposit address is kept out: the quote
/// gate and `ensurePayable` verify it instead.
class SettlementAuthorizationIntent {
  const SettlementAuthorizationIntent({
    required this.flow,
    required this.walletId,
    required this.destination,
    required this.routeLabel,
    required this.amountIn,
    required this.minReceive,
    required this.maxFeeBps,
    this.reviewedQuote,
    this.sourceFeeBaseUnits,
    this.sourceFeeAsset,
  });

  static const String provider = 'orchestra';

  final SettlementFlow flow;
  final String walletId;

  /// `recipient|routeVersion`.
  final String destination;
  final String routeLabel;
  final BigInt amountIn;
  final BigInt minReceive;
  final int maxFeeBps;
  final VerifiedOrchestraQuote? reviewedQuote;

  /// A separately charged source-network fee, outside Orchestra's quote.
  /// HyperCore USDC uses eight decimals. Null for flows without this fee.
  final BigInt? sourceFeeBaseUnits;
  final String? sourceFeeAsset;
}

/// The single place where Phase 1b step-up grants bind to settlement
/// operations. Hot flows pass a function that requests a `SensitiveIntent`
/// grant through `requireFreshAuthGrant` for [SettlementAuthorizationIntent]
/// (`OrchestraGrants.settlement`: destination = recipient plus route
/// version, provider `orchestra`, deposit address out of the digest), and
/// returns false when the user declines. It runs after review, before the
/// margin check and the call that moves funds.
typedef SettlementStepUpHook = Future<bool> Function(
    SettlementAuthorizationIntent intent);

/// What review answered for a quote.
enum SettlementReviewDecision { accept, decline }

/// Why the runner stopped before any funds moved.
enum SettlementStopReason {
  /// An earlier operation on this wallet and route is unresolved.
  blockedPending,

  /// The route is not available for this operation.
  routeUnavailable,

  /// The user declined review or step-up.
  declined,

  /// The quote expired too many times in a row.
  quoteExpired,

  /// The quote was replaced before anything was sent. The flow goes back to
  /// review and needs another confirm tap (B5).
  quoteReplaced,
}

/// Thrown when the runner stopped before `broadcasting`. Nothing was sent.
class SettlementStopped implements Exception {
  const SettlementStopped(this.reason, {this.routeReason});

  final SettlementStopReason reason;
  final RouteUnavailableReason? routeReason;

  @override
  String toString() => 'SettlementStopped(${reason.name})';
}

/// Thrown when `fund` failed after `broadcasting` was persisted. Funds may
/// have left; the operation is `fundingUnknown` and nothing retries it.
class SettlementFundingUnknown implements Exception {
  const SettlementFundingUnknown(this.operationId, this.cause);

  final String operationId;
  final Object cause;

  @override
  String toString() => 'SettlementFundingUnknown';
}

/// The outcome of a run that moved funds.
class SettlementRunResult {
  const SettlementRunResult({
    required this.operation,
    required this.quote,
    required this.proof,
    required this.orderId,
    this.registration,
  });

  /// The record after the last write.
  final SettlementOperation operation;
  final VerifiedOrchestraQuote quote;
  final SettlementFundingProof proof;

  /// The provider order id, or null while registration is still pending
  /// (the reconciler retries it with the same key).
  final String? orderId;

  /// Set when the plan asked for [SettlementPlan.registerInBackground]: the
  /// submit still running after the run returned. Completes with the
  /// provider order id, or null when registration is left to the
  /// reconciler. Never throws.
  final Future<String?>? registration;

  bool get registered => orderId != null;
}

/// A quote persisted at `quoted` and waiting for a review tap.
class SettlementPrepared {
  const SettlementPrepared({required this.operationId, required this.quote});

  final String operationId;
  final VerifiedOrchestraQuote quote;
}

/// The outcome of confirming a prepared quote: either funds moved, or the
/// quote was refreshed and needs another review tap.
class SettlementConfirmResult {
  const SettlementConfirmResult.funded(SettlementRunResult this.result)
      : rereview = null;

  const SettlementConfirmResult.rereview(SettlementPrepared this.rereview)
      : result = null;

  final SettlementRunResult? result;
  final SettlementPrepared? rereview;
}

/// Everything a flow supplies for one operation.
class SettlementPlan {
  const SettlementPlan({
    required this.walletId,
    required this.flow,
    required this.route,
    required this.sourceAccount,
    required this.destinationAccount,
    required this.payer,
    required this.resolveOwnership,
    required this.requestQuote,
    required this.fund,
    this.routeVersion,
    this.amountUsd,
    this.checkAvailability,
    this.review,
    this.prepareFunding,
    this.stepUp,
    this.registerInBackground = false,
  });

  final String walletId;
  final SettlementFlow flow;
  final String? routeVersion;
  final RouteKey route;
  final SettlementAccountKind sourceAccount;

  /// Null for an external recipient.
  final SettlementAccountKind? destinationAccount;
  final SettlementPayer payer;

  /// Approximate USD value, only ever bucketed for analytics.
  final double? amountUsd;

  /// Route availability (B2). Null skips the check.
  final Future<RouteAvailability> Function()? checkAvailability;

  /// Resolves the refund and recipient from the wallet, never a backend.
  final Future<SettlementOwnership> Function() resolveOwnership;

  /// One deliberate quote attempt with [idempotencyKey], reused by the
  /// transport retries of that attempt only.
  final Future<SettlementQuoteResult> Function(String idempotencyKey)
      requestQuote;

  /// Shows [quote] to the user. [refreshed] is true when an earlier
  /// reviewed quote was replaced. Null means the flow shows no quote
  /// terms (the user confirmed the amount before the quote), so review is
  /// implicit and a refresh is silent.
  final Future<SettlementReviewDecision> Function(VerifiedOrchestraQuote quote,
      {required bool refreshed})? review;

  /// Work that moves no funds and may fail (prepare the payment, persist
  /// the Activity row, final amount checks). Runs before `broadcasting`.
  final Future<Object?> Function(
      VerifiedOrchestraQuote quote, String operationId)? prepareFunding;

  /// The call that moves funds. Runs only after `broadcasting` is flushed.
  final Future<SettlementFundingProof> Function(
      VerifiedOrchestraQuote quote, Object? prepared) fund;

  final SettlementStepUpHook? stepUp;

  /// Return as soon as the funding proof is persisted (`funded`) and run
  /// the deposit submit in the background, reported through
  /// [SettlementRunResult.registration]. The operation is held by this
  /// runner while the submit runs, so the reconciler does not send a second
  /// one. Off by default: the run returns after the submit.
  final bool registerInBackground;
}

/// The id `submitDeposit` takes as `sparkTxHash` for a Spark payment id.
///
/// Breez SDK Spark (0.26) gives a bitcoin transfer the Spark transfer id as
/// its payment id, which is what Orchestra matches. A token (dollar)
/// transfer's payment id is `<token transaction hash>:<output index>`, and
/// Orchestra matches the token transaction hash alone (the SDK's own
/// Orchestra client submits `details.txHash` for token payments). The
/// payment id itself stays the proof the reconciler matches against the
/// SDK's payment list.
String sparkSubmitTxHash(String paymentId) {
  final match = _kTokenPaymentId.firstMatch(paymentId.trim());
  return match == null ? paymentId : match.group(1)!;
}

final RegExp _kTokenPaymentId = RegExp(r'^([0-9a-fA-F]{32,}):\d+$');

/// Waits before each fast resubmit after a definitive rejection. A Spark
/// deposit submitted seconds after the send is often refused only because
/// Orchestra has not indexed the transfer yet (`invalid_tx_hash`), so the
/// next attempts follow quickly, each with a new idempotency key.
const List<Duration> kSettlementSubmitRejectRetryDelays = [
  Duration(milliseconds: 1500),
  Duration(seconds: 3),
  Duration(seconds: 6),
];

Future<void> _sleep(Duration d) => Future<void>.delayed(d);

/// The provider order for [op]'s quote, when Orchestra already has one (it
/// detects deposits on its own). Null when there is none or the read
/// failed.
typedef SettlementOrderLookup = Future<String?> Function(
    SettlementOperation op);

Future<String?> lookupSettlementOrder(SettlementOperation op) async {
  final quoteId = op.quote?.quoteId;
  if (quoteId == null || quoteId.isEmpty) return null;
  final result = await OrchestraService.getStatus(quoteId);
  if (classifyOrchestraStatusRead(result) != OrchestraStatusReadKind.order) {
    return null;
  }
  final id = result.data?.id ?? '';
  return id.isNotEmpty && id != quoteId && !id.startsWith('q_') ? id : null;
}

/// Submits the deposit for [op]. Shared by the runner and the reconciler
/// so both send the same body with the same key.
Map<String, Object?> settlementSubmitBody(SettlementOperation op) {
  final funding = op.funding;
  final quote = op.quote;
  return {
    'quoteId': quote?.quoteId,
    if (funding?.sparkPaymentId != null)
      'sparkTxHash': sparkSubmitTxHash(funding!.sparkPaymentId!),
    if (funding?.sparkPaymentId != null)
      'sourceSparkAddress': op.refund?.address,
    if (funding?.evmTxHash != null) 'txHash': funding!.evmTxHash,
    if (funding?.evmTxHash != null) 'sourceAddress': op.refund?.address,
    if (funding?.btcTxid != null) 'bitcoinTxid': funding!.btcTxid,
    if (funding?.btcVout != null) 'bitcoinVout': funding!.btcVout,
  };
}

typedef SettlementSubmitCall = Future<Result<OrchestraSubmitResponse>> Function(
    SettlementOperation op, String idempotencyKey);

/// How long a submit for an EVM-sourced proof (a Polygon relayer hash, a
/// HyperCore `usdSend`, a Ledger EVM send) may take. Flashnet's submit
/// blocks while it verifies the source transaction, and the backend's own
/// upstream timeout is 30 s, so the app's default 15 s gave up on submits
/// that were still being processed.
const Duration kSettlementEvmSubmitTimeout = Duration(seconds: 45);

/// Whether [op]'s proof is a source-chain transaction hash (not a Spark
/// transfer or a Bitcoin txid): its submit is slow and always runs after
/// the flow returned.
bool settlementProofIsEvm(SettlementOperation op) {
  final funding = op.funding;
  return funding?.evmTxHash != null &&
      funding?.sparkPaymentId == null &&
      funding?.btcTxid == null;
}

/// Sends `submitDeposit` for [op] with [key] and the body
/// [settlementSubmitBody] builds. The only submit call outside the gate
/// (Phase 5 plan B1).
Future<Result<OrchestraSubmitResponse>> sendSettlementSubmit(
    SettlementOperation op, String key) {
  final body = settlementSubmitBody(op);
  return OrchestraService.submitDeposit(
    quoteId: body['quoteId'] as String,
    sparkTxHash: body['sparkTxHash'] as String?,
    sourceSparkAddress: body['sourceSparkAddress'] as String?,
    txHash: body['txHash'] as String?,
    sourceAddress: body['sourceAddress'] as String?,
    bitcoinTxid: body['bitcoinTxid'] as String?,
    bitcoinVout: body['bitcoinVout'] as int?,
    idempotencyKey: key,
    timeout: settlementProofIsEvm(op)
        ? kSettlementEvmSubmitTimeout
        : const Duration(seconds: 15),
  );
}

/// Submits [op]'s deposit with its persisted keys and writes each
/// attempt's outcome. Returns the record after the last write and the
/// order id when the provider accepted it.
///
/// A timeout, 5xx or 429 is retried inside one attempt with the same key
/// ([policy]). A 409 `idempotency_in_progress` means the provider is still
/// processing an earlier request with the key: the attempt ends as
/// transient with the key kept, never retried with a new one. A definitive
/// rejection (any other 4xx) rotates the key, and
/// the deposit is submitted again after each of [rejectRetryDelays] with
/// the new key. Before each resubmit [findOrder] asks whether Orchestra
/// already detected the deposit; an order found there ends the retries.
/// The retries also end on acceptance, on a transient outcome, or when
/// another writer moved the record. The whole burst counts as one attempt
/// in the record, so the reconciler's own schedule after it is unchanged
/// (its first submit about 30 s after the burst).
Future<
    ({
      SettlementOperation op,
      String? orderId,
      SubmitAttemptOutcome outcome
    })> submitSettlementDeposit(
  SettlementStore store,
  SettlementOperation op, {
  SettlementSubmitCall submit = sendSettlementSubmit,
  DateTime Function() clock = DateTime.now,
  IdempotentRetryPolicy policy = const IdempotentRetryPolicy(),
  List<Duration> rejectRetryDelays = kSettlementSubmitRejectRetryDelays,
  Future<void> Function(Duration delay) sleep = _sleep,
  SettlementOrderLookup? findOrder = lookupSettlementOrder,
}) async {
  var current = op;
  for (var retry = 0;; retry++) {
    final (:attempt, :applied) = await _submitOnce(store, current,
        submit: submit, clock: clock, policy: policy, burstIndex: retry);
    if (!applied ||
        attempt.outcome != SubmitAttemptOutcome.rejected ||
        retry >= rejectRetryDelays.length) {
      return attempt;
    }
    await sleep(rejectRetryDelays[retry]);
    final latest = await store.get(current.operationId);
    if (latest == null ||
        latest.version != attempt.op.version ||
        latest.stage != attempt.op.stage ||
        (latest.orderId?.isNotEmpty ?? false)) {
      // Another writer (the reconciler) moved the record: it owns it now.
      final known = latest?.orderId;
      return (
        op: latest ?? attempt.op,
        orderId: known,
        outcome: known != null && known.isNotEmpty
            ? SubmitAttemptOutcome.accepted
            : attempt.outcome,
      );
    }
    String? detected;
    if (findOrder != null) {
      try {
        detected = await findOrder(latest);
      } catch (_) {
        detected = null;
      }
    }
    if (detected != null) {
      return _recordDetectedOrder(store, latest, detected);
    }
    current = latest;
  }
}

/// Orchestra already has the order for [op]: record it as registered.
Future<
    ({
      SettlementOperation op,
      String? orderId,
      SubmitAttemptOutcome outcome
    })> _recordDetectedOrder(
  SettlementStore store,
  SettlementOperation op,
  String orderId,
) async {
  final write = await store.transition(
    op.operationId,
    op.stage == SettlementStage.funded ? SettlementStage.submitted : op.stage,
    from: op.stage,
    expectedVersion: op.version,
    patch: (current) => current.copyWith(
      orderId: orderId,
      submit: SettlementSubmitState(
        attempts: current.submit.attempts,
        lastAttemptAt: current.submit.lastAttemptAt,
        lastErrorCode: current.submit.lastErrorCode,
        acceptedAt: current.submit.acceptedAt,
        providerDetected: true,
      ),
    ),
  );
  return (
    op: write.operation ?? op,
    orderId: orderId,
    outcome: SubmitAttemptOutcome.accepted,
  );
}

/// One submit attempt for [op] with its persisted keys, then the write of
/// the attempt's outcome. [applied] is false when another writer moved the
/// record first. [burstIndex] is the attempt's place in a quick resubmit
/// burst: only the first one adds to the persisted attempt count.
Future<
    ({
      ({
        SettlementOperation op,
        String? orderId,
        SubmitAttemptOutcome outcome
      }) attempt,
      bool applied
    })> _submitOnce(
  SettlementStore store,
  SettlementOperation op, {
  required SettlementSubmitCall submit,
  required DateTime Function() clock,
  required IdempotentRetryPolicy policy,
  int burstIndex = 0,
}) async {
  final keys = op.submitKeys ?? SubmitIdempotencyKeys.create();
  final fingerprint = submitBodyFingerprint(settlementSubmitBody(op));
  final attempt = await submitWithIdempotencyKeys<OrchestraSubmitResponse>(
    keys: keys,
    bodyFingerprint: fingerprint,
    submit: (key) => submit(op, key),
    policy: policy,
  );
  final call = attempt.call;
  final accepted = call.outcome == SettlementHttpOutcome.success;
  final rawOrderId = call.result.data?.orderId ?? '';
  final orderId = accepted && rawOrderId.isNotEmpty ? rawOrderId : null;
  final outcome = accepted
      ? SubmitAttemptOutcome.accepted
      : call.outcome == SettlementHttpOutcome.rejected
          ? SubmitAttemptOutcome.rejected
          : SubmitAttemptOutcome.transient;
  final counted = burstIndex == 0 ? 1 : 0;
  TrackingService.settlementSubmitAttempt(
    flow: op.flow.code,
    // Every request is numbered, the burst's resubmits included.
    attempts: op.submit.attempts + (burstIndex == 0 ? 1 : burstIndex),
    outcome: outcome.name,
  );
  final now = clock();
  final next = accepted ? SettlementStage.submitted : op.stage;
  final write = await store.transition(
    op.operationId,
    next,
    from: op.stage,
    expectedVersion: op.version,
    patch: (current) => current.copyWith(
      keys: current.keysWithSubmit(attempt.keys),
      orderId: orderId,
      submit: SettlementSubmitState(
        attempts: current.submit.attempts + counted,
        lastAttemptAt: now,
        lastErrorCode: accepted ? null : call.result.statusCode?.toString(),
        acceptedAt: current.submit.acceptedAt ?? (accepted ? now : null),
        providerDetected: current.submit.providerDetected,
      ),
    ),
  );
  return (
    attempt: (op: write.operation ?? op, orderId: orderId, outcome: outcome),
    applied: write.applied,
  );
}

class SettlementRunner {
  SettlementRunner({
    required this.store,
    DateTime Function() clock = DateTime.now,
    String Function() generateId = OrchestraService.generateIdempotencyKey,
    SettlementSubmitCall submit = sendSettlementSubmit,
    List<Duration> submitRejectRetryDelays = kSettlementSubmitRejectRetryDelays,
    Future<void> Function(Duration delay) sleep = _sleep,
    SettlementOrderLookup? findOrder = lookupSettlementOrder,
  })  : _clock = clock,
        _generateId = generateId,
        _submit = submit,
        _rejectRetryDelays = submitRejectRetryDelays,
        _sleepFor = sleep,
        _findOrder = findOrder;

  final SettlementStore store;
  final DateTime Function() _clock;
  final String Function() _generateId;
  final SettlementSubmitCall _submit;
  final List<Duration> _rejectRetryDelays;
  final Future<void> Function(Duration delay) _sleepFor;
  final SettlementOrderLookup? _findOrder;

  /// Skew per quote id, kept in memory; a quote whose skew is unknown
  /// gets the extra margin.
  final Map<String, Duration?> _skews = {};

  // ─────────────────────────────── public API ───────────────────────────────

  /// Runs [plan] start to end. For flows whose review happens across a
  /// later tap, use [prepare] and [confirm] instead.
  Future<SettlementRunResult> run(SettlementPlan plan) async {
    final prepared = await prepare(plan);
    var current = prepared;
    var refreshed = false;
    for (var i = 0; i <= kSettlementMaxSilentRefreshes; i++) {
      final review = plan.review;
      if (review != null) {
        final decision = await review(current.quote, refreshed: refreshed);
        if (decision == SettlementReviewDecision.decline) {
          await abandon(current.operationId);
          throw const SettlementStopped(SettlementStopReason.declined);
        }
        if (refreshed) {
          TrackingService.settlementRereviewConfirmed(plan.flow.code);
        }
      }
      final confirmed = await confirm(
        plan,
        operationId: current.operationId,
        reviewedQuoteId: current.quote.quoteId,
        amountBaseUnits: current.quote.amountIn,
      );
      final result = confirmed.result;
      if (result != null) return result;
      final replaced = confirmed.rereview!;
      if (review == null) {
        // The user's confirm tap covered only the quote it started with.
        // A replaced quote is never paid without another tap (B5).
        throw await returnToReview(plan, replaced);
      }
      current = replaced;
      refreshed = true;
    }
    await abandon(current.operationId);
    throw const SettlementStopped(SettlementStopReason.quoteExpired);
  }

  /// Creates the operation, resolves ownership and persists a verified
  /// quote at `quoted`. Nothing moves funds. Throws [SettlementStopped],
  /// [WalletGuardException] or the quote failure; the operation is then
  /// `abandoned`.
  ///
  /// [reReview] is set when [confirm] starts over with a fresh quote for
  /// the same user attempt: the new operation is not a new start, so
  /// `settlement_operation_started` is not sent again.
  Future<SettlementPrepared> prepare(SettlementPlan plan,
      {bool reReview = false}) async {
    if (_rereviewPending.remove(_rereviewKey(plan))) {
      // The confirm tap after a return to review (user action).
      TrackingService.settlementRereviewConfirmed(plan.flow.code);
    }
    final availability = await plan.checkAvailability?.call();
    if (availability != null && !availability.isAvailable) {
      TrackingService.settlementRouteUnavailable(
          route: plan.route.label, reason: availability.reason!.code);
      throw SettlementStopped(SettlementStopReason.routeUnavailable,
          routeReason: availability.reason);
    }

    // Ownership before any quote (B4): a failure never requests one.
    final ownership = await plan.resolveOwnership();

    final now = _clock();
    final created = await store.create(SettlementOperation(
      operationId: _generateId(),
      walletId: plan.walletId,
      accountKind: plan.sourceAccount,
      flow: plan.flow,
      routeVersion: plan.routeVersion,
      route: plan.route,
      amountInBaseUnits: '0',
      recipient: ownership.recipient,
      refund: ownership.refund,
      stage: SettlementStage.created,
      createdAt: now,
      updatedAt: now,
    ));
    if (!reReview) {
      TrackingService.settlementOperationStarted(
        flow: plan.flow.code,
        routeVersion: plan.routeVersion,
        amountUsd: plan.amountUsd,
      );
    }

    final lease = store.acquireLease(created.operationId);
    try {
      final quoted = await _quoteAndPersist(
        plan,
        created,
        ownership: ownership,
        moment: SettlementMoment.beforeReview,
        supersedeReason: null,
      );
      return SettlementPrepared(
          operationId: quoted.op.operationId, quote: quoted.quote);
    } catch (_) {
      await abandon(created.operationId);
      rethrow;
    } finally {
      if (lease != null) store.releaseLease(created.operationId, lease);
    }
  }

  /// Pays the quote [reviewedQuoteId] the user confirmed, after the margin
  /// check. When the margin fails, or the amount about to be paid no longer
  /// equals the quote, refreshes the quote and returns it for another
  /// review tap; nothing is paid against it.
  Future<SettlementConfirmResult> confirm(
    SettlementPlan plan, {
    required String operationId,
    required String reviewedQuoteId,
    required BigInt amountBaseUnits,
  }) async {
    final lease = store.acquireLease(operationId);
    if (lease == null) {
      // Another confirm is running for this operation (a double tap).
      throw const SettlementStopped(SettlementStopReason.blockedPending);
    }
    // Set when the lease passes to a background submit, which releases it.
    var leaseHandedOff = false;
    try {
      final loaded = await store.get(operationId);
      if (loaded == null ||
          !loaded.stage.isBeforeBroadcasting ||
          loaded.everBroadcast ||
          loaded.stage == SettlementStage.signed) {
        if (loaded != null && loaded.everBroadcast) {
          // Never quote or pay again for an operation that reached
          // broadcasting (I2).
          throw const SettlementStopped(SettlementStopReason.blockedPending);
        }
        // Expired and abandoned meanwhile: start over with a new review.
        final fresh = await prepare(plan, reReview: true);
        return SettlementConfirmResult.rereview(fresh);
      }
      var op = loaded;
      final quote = op.quote;
      final verified = _verifiedById[reviewedQuoteId];
      if (quote == null ||
          verified == null ||
          quote.quoteId != reviewedQuoteId) {
        // [fund] is only ever called with the quote review returned. A
        // quote this process never verified (a restart between taps) or
        // one the record no longer holds is shown again instead.
        await abandon(operationId);
        final fresh = await prepare(plan, reReview: true);
        return SettlementConfirmResult.rereview(fresh);
      }

      final ownership = await plan.resolveOwnership();
      _checkOwnership(plan, ownership, verified);

      if (op.stage != SettlementStage.reviewed) {
        final write = await store.transition(
            operationId, SettlementStage.reviewed,
            from: op.stage, expectedVersion: op.version);
        if (!write.applied) {
          throw const SettlementStopped(SettlementStopReason.blockedPending);
        }
        op = write.operation!;
      }

      final stepUp = plan.stepUp;
      if (stepUp != null) {
        final write = await store.transition(
            operationId, SettlementStage.authorizing,
            from: op.stage, expectedVersion: op.version);
        if (!write.applied) {
          throw const SettlementStopped(SettlementStopReason.blockedPending);
        }
        op = write.operation!;
        final ok = await stepUp(_intentFor(plan, op, verified));
        if (!ok) {
          await abandon(operationId);
          throw const SettlementStopped(SettlementStopReason.declined);
        }
      }

      final payable = amountBaseUnits == verified.amountIn &&
          SettlementQuotePolicy.hasMargin(
            expiresAt: verified.expiresAt,
            localNow: _clock(),
            skew: _skews[verified.quoteId],
            moment: SettlementMoment.beforeSend,
            payer: plan.payer,
          );
      if (!payable) {
        return SettlementConfirmResult.rereview(
            await _refreshAfterReview(plan, op, ownership, verified));
      }

      final prepared = await plan.prepareFunding?.call(verified, operationId);

      // Approval and preparation can wait on UI, providers or a device. Refuse
      // a wallet/address change during those waits before recording a send.
      _checkOwnership(plan, await plan.resolveOwnership(), verified);

      // Immediately before the call that moves funds: the Phase 2 gate's
      // amount and expiry check, then `broadcasting` on disk (I1).
      final latest = await store.get(operationId);
      if (latest == null ||
          latest.version != op.version ||
          latest.stage != op.stage) {
        throw const SettlementStopped(SettlementStopReason.blockedPending);
      }
      try {
        _ensurePayable(verified, amountBaseUnits, plan.payer);
      } on WalletGuardException catch (e) {
        if (e.reason != WalletGuardReason.quoteExpired) rethrow;
        return SettlementConfirmResult.rereview(
            await _refreshAfterReview(plan, op, ownership, verified));
      }
      // The funding kind is on disk before the call that moves funds, so
      // after a kill or a throw the reconciler runs the Spark payment
      // lookup for this operation (B7).
      final broadcasting = await store.transition(
        operationId,
        SettlementStage.broadcasting,
        from: op.stage,
        expectedVersion: op.version,
        patch: plan.payer == SettlementPayer.sparkHot
            ? (current) => current.copyWith(
                  funding: (current.funding ?? const SettlementFunding())
                      .copyWith(kind: SettlementFundingKind.spark),
                )
            : null,
      );
      if (!broadcasting.applied) {
        throw const SettlementStopped(SettlementStopReason.blockedPending);
      }
      op = broadcasting.operation!;

      final SettlementFundingProof proof;
      try {
        proof = await plan.fund(verified, prepared);
        SettlementFaults.afterFund(); // debug fault panel only
      } catch (e) {
        // A funding call that refused BEFORE submitting sent nothing, so
        // there is nothing to resolve and nothing to warn about. Wrapping
        // those as unresolved told people their money might be in flight
        // when the call had not even been made, and parked an operation
        // that should simply have ended.
        if (e is SettlementFundingNotStarted) {
          // broadcasting is persisted before invoking fund. abandon() only
          // handles pre-broadcast stages, so a proven refusal needs the
          // explicit notFunded transition, retaining the audit record.
          try {
            final refused = await store.transition(
                operationId, SettlementStage.notFunded,
                from: SettlementStage.broadcasting);
            if (!refused.applied) {
              throw StateError('Funding refusal could not be recorded.');
            }
          } catch (writeError) {
            throw SettlementFundingUnknown(operationId, writeError);
          }
          throw e is SettlementFundingRefused ? e.cause : e;
        }
        await store.transition(operationId, SettlementStage.fundingUnknown,
            from: SettlementStage.broadcasting);
        TrackingService.settlementFundingUnknown(plan.flow.code);
        throw SettlementFundingUnknown(operationId, e);
      }

      final fundedAt = _clock();
      final skew = _skews[verified.quoteId] ?? Duration.zero;
      final funded = await store.transition(
        operationId,
        SettlementStage.funded,
        from: SettlementStage.broadcasting,
        patch: (current) => current.copyWith(
          funding: SettlementFunding(
            kind: proof.kind,
            sparkPaymentId: proof.sparkPaymentId,
            evmTxHash: proof.evmTxHash,
          ),
          keys: current.keysWithSubmit(SubmitIdempotencyKeys.create()),
          late: SettlementLate(
            quoteExpiredBeforeFunding:
                fundedAt.add(skew).isAfter(verified.expiresAt),
          ),
        ),
      );
      op = funded.operation ?? op;
      TrackingService.settlementFundingRecorded(
          flow: plan.flow.code, fundingKind: proof.kind.name);
      if (!funded.applied) {
        // A reconciler write won the race (it saw a provider order). The
        // operation is tracked either way; never pay again.
        return SettlementConfirmResult.funded(SettlementRunResult(
            operation: op, quote: verified, proof: proof, orderId: op.orderId));
      }

      // A source-chain proof always registers in the background: its
      // submit can take most of a minute while Flashnet verifies it.
      if (plan.registerInBackground ||
          proof.kind == SettlementFundingKind.relayer ||
          proof.kind == SettlementFundingKind.hyperliquid) {
        // The funds moved and the proof is on disk: the flow can finish
        // now. The submit keeps this operation's lease until it ends, so
        // the reconciler does not submit it a second time meanwhile.
        leaseHandedOff = true;
        final registration = _registerHeld(op, lease);
        return SettlementConfirmResult.funded(SettlementRunResult(
            operation: op,
            quote: verified,
            proof: proof,
            orderId: null,
            registration: registration));
      }

      String? orderId;
      try {
        final submitted = await _submitDeposit(op);
        op = submitted.op;
        orderId = submitted.orderId;
      } catch (_) {
        // Stays `funded`; the reconciler retries with the persisted key.
      }
      return SettlementConfirmResult.funded(SettlementRunResult(
          operation: op, quote: verified, proof: proof, orderId: orderId));
    } on SettlementFundingUnknown {
      rethrow;
    } catch (_) {
      // Stopped before any funds moved: end the operation now. A record
      // that reached broadcasting is left untouched by [abandon].
      await abandon(operationId);
      rethrow;
    } finally {
      if (!leaseHandedOff) store.releaseLease(operationId, lease);
    }
  }

  Future<
      ({
        SettlementOperation op,
        String? orderId,
        SubmitAttemptOutcome outcome
      })> _submitDeposit(SettlementOperation op) => submitSettlementDeposit(
        store,
        op,
        submit: _submit,
        clock: _clock,
        rejectRetryDelays: _rejectRetryDelays,
        sleep: _sleepFor,
        findOrder: _findOrder,
      );

  /// The submit of a funded [op] run after its flow returned, holding
  /// [lease] until it ends. Completes with the order id, or null when the
  /// reconciler is left to register it. Never throws.
  Future<String?> _registerHeld(SettlementOperation op, Object lease) async {
    try {
      // Let the caller's frame finish before the first request.
      await Future<void>.delayed(Duration.zero);
      final submitted = await _submitDeposit(op);
      return submitted.orderId;
    } catch (_) {
      // Stays `funded`; the reconciler retries with the persisted key.
      return null;
    } finally {
      store.releaseLease(op.operationId, lease);
    }
  }

  /// Ends [replaced], a quote the user never confirmed, and returns the stop
  /// the flow shows. The flow goes back to its review state and the next
  /// confirm tap starts a new operation, so nothing is paid against a quote
  /// the user did not review (B5). Moves nothing.
  Future<SettlementStopped> returnToReview(
    SettlementPlan plan,
    SettlementPrepared replaced,
  ) async {
    await abandon(replaced.operationId);
    TrackingService.settlementRereviewRequired(plan.flow.code);
    _rereviewPending.add(_rereviewKey(plan));
    return const SettlementStopped(SettlementStopReason.quoteReplaced);
  }

  /// Flows sent back to review and waiting for the next confirm tap.
  final Set<String> _rereviewPending = {};

  static String _rereviewKey(SettlementPlan plan) =>
      '${plan.walletId}|${plan.flow.code}|${plan.route.label}';

  /// Ends an operation that never reached `broadcasting`. A record that
  /// did is left untouched.
  Future<void> abandon(String operationId) async {
    final op = await store.get(operationId);
    if (op == null || !op.stage.isBeforeBroadcasting || op.everBroadcast) {
      return;
    }
    if (op.stage == SettlementStage.signed) return;
    final write = await store.transition(
        operationId, SettlementStage.abandoned,
        from: op.stage, expectedVersion: op.version);
    if (write.applied) {
      // Abandoned is a terminal stage; without this the operation's
      // started event never gets a matching terminal one.
      TrackingService.settlementTerminal(
        route: op.route.label,
        outcome: SettlementStage.abandoned.name,
        duration: _clock().difference(op.createdAt),
        flow: op.flow.code,
        walletKind: op.accountKind.isLedger ? 'ledger' : 'hot',
      );
    }
  }

  // ─────────────────────────────── internals ───────────────────────────────

  /// Verified quotes this runner produced, by quote id. Only these can be
  /// paid, so a quote the review did not see can never reach [fund].
  final Map<String, VerifiedOrchestraQuote> _verifiedById = {};

  Future<({SettlementOperation op, VerifiedOrchestraQuote quote})>
      _quoteAndPersist(
    SettlementPlan plan,
    SettlementOperation op, {
    required SettlementOwnership ownership,
    required SettlementMoment moment,
    required String? supersedeReason,
  }) async {
    var current = op;
    for (var attempt = 0;; attempt++) {
      if (!await store.canQuote(current.operationId)) {
        throw const SettlementStopped(SettlementStopReason.blockedPending);
      }
      final key = _generateId();
      final fetched = await plan.requestQuote(key);
      final verified = fetched.quote;
      _checkOwnership(plan, ownership, verified);
      final hasMargin = SettlementQuotePolicy.hasMargin(
        expiresAt: verified.expiresAt,
        localNow: _clock(),
        skew: fetched.skew,
        moment: moment,
        payer: plan.payer,
      );
      if (!hasMargin) {
        // The user has not seen these terms: re-quote silently.
        if (attempt >= kSettlementMaxSilentRefreshes) {
          throw const SettlementStopped(SettlementStopReason.quoteExpired);
        }
        TrackingService.settlementQuoteRefreshed(
          flow: plan.flow.code,
          moment: moment.code,
          afterReview: false,
          withinGrant: true,
        );
        continue;
      }
      _skews[verified.quoteId] = fetched.skew;
      _verifiedById[verified.quoteId] = verified;
      final now = _clock();
      final previous = current.quote;
      final write = await store.transition(
        current.operationId,
        SettlementStage.quoted,
        from: current.stage,
        expectedVersion: current.version,
        patch: (record) => record.copyWith(
          amountInBaseUnits: verified.amountIn.toString(),
          quote: settlementQuoteTermsFor(verified,
              skew: fetched.skew ?? Duration.zero),
          quoteHistory: previous == null
              ? record.quoteHistory
              : [
                  ...record.quoteHistory,
                  SettlementQuoteHistoryEntry(
                    quoteId: previous.quoteId,
                    reason: supersedeReason ?? 'refreshed',
                    supersededAt: now,
                  ),
                ],
          keys: SettlementKeys(
            quote: key,
            submit: record.keys.submit,
            submitHistory: record.keys.submitHistory,
            submitFingerprint: record.keys.submitFingerprint,
          ),
        ),
      );
      if (!write.applied) {
        throw const SettlementStopped(SettlementStopReason.blockedPending);
      }
      return (op: write.operation!, quote: verified);
    }
  }

  Future<SettlementPrepared> _refreshAfterReview(
    SettlementPlan plan,
    SettlementOperation op,
    SettlementOwnership ownership,
    VerifiedOrchestraQuote reviewed,
  ) async {
    final refreshed = await _quoteAndPersist(
      plan,
      op,
      ownership: ownership,
      moment: SettlementMoment.beforeReview,
      supersedeReason: 'expired_before_send',
    );
    final change = classifySettlementTermsChange(
      _termsFor(plan, op, reviewed),
      _termsFor(plan, refreshed.op, refreshed.quote),
    );
    TrackingService.settlementQuoteRefreshed(
      flow: plan.flow.code,
      moment: SettlementMoment.beforeSend.code,
      afterReview: plan.review != null,
      withinGrant: change == SettlementTermsChange.withinGrant,
    );
    return SettlementPrepared(
        operationId: refreshed.op.operationId, quote: refreshed.quote);
  }

  void _checkOwnership(
    SettlementPlan plan,
    SettlementOwnership ownership,
    VerifiedOrchestraQuote verified,
  ) {
    final request = verified.request;
    if (plan.destinationAccount == null) {
      verifySettlementOwnership(
        route: plan.route,
        ownership: SettlementOwnership(
          refund: ownership.refund,
          recipient: SettlementAddressRef(
              address: request.recipientAddress,
              kind: OwnedAddressKind.external),
        ),
        refundAddress: request.refundAddress,
        recipientAddress: request.recipientAddress,
      );
      if (request.recipientAddress.trim() !=
          ownership.recipient.address.trim()) {
        throw const WalletGuardException(WalletGuardReason.echoMismatch,
            field: 'recipient');
      }
      return;
    }
    verifySettlementOwnership(
      route: plan.route,
      ownership: ownership,
      refundAddress: request.refundAddress,
      recipientAddress: request.recipientAddress,
    );
  }

  void _ensurePayable(
    VerifiedOrchestraQuote quote,
    BigInt amountBaseUnits,
    SettlementPayer payer,
  ) {
    if (amountBaseUnits != quote.amountIn) {
      throw const WalletGuardException(WalletGuardReason.amountMismatch);
    }
    final ok = SettlementQuotePolicy.hasMargin(
      expiresAt: quote.expiresAt,
      localNow: _clock(),
      skew: _skews[quote.quoteId],
      moment: SettlementMoment.beforeSend,
      payer: payer,
    );
    if (!ok || !quote.expiresAt.isAfter(_clock().add(quote.expiryMargin))) {
      throw const WalletGuardException(WalletGuardReason.quoteExpired);
    }
  }

  SettlementReviewedTerms _termsFor(
    SettlementPlan plan,
    SettlementOperation op,
    VerifiedOrchestraQuote quote,
  ) =>
      SettlementReviewedTerms(
        quoteId: quote.quoteId,
        recipient: quote.request.recipientAddress,
        routeVersion: plan.routeVersion,
        routeLabel: plan.route.label,
        amountIn: quote.amountIn,
        estimatedOut: BigInt.tryParse(quote.quote.estimatedOut) ?? BigInt.zero,
        feeBps: quote.quote.combinedFeeBps,
      );

  SettlementAuthorizationIntent _intentFor(
    SettlementPlan plan,
    SettlementOperation op,
    VerifiedOrchestraQuote quote,
  ) {
    final locked = BigInt.tryParse(quote.quote.lockedMinAmountOut ?? '');
    return SettlementAuthorizationIntent(
      flow: plan.flow,
      walletId: plan.walletId,
      destination:
          '${quote.request.recipientAddress}|${plan.routeVersion ?? ''}',
      routeLabel: plan.route.label,
      amountIn: quote.amountIn,
      minReceive:
          locked ?? BigInt.tryParse(quote.quote.estimatedOut) ?? BigInt.zero,
      maxFeeBps: quote.quote.combinedFeeBps,
      reviewedQuote: quote,
    );
  }
}
