import 'package:kute/helpers/orchestra_legacy_status_rules.dart'
    show OrchestraStatusReadKind;
import 'package:kute/helpers/reconcile_cadence.dart';
import 'package:kute/services/funding/settlement_stage.dart';

/// Status checks for funded operations: the Point 0 ladder, then daily until
/// 60 days, then on each foreground.
const kSettlementStatusCadence =
    ReconcileCadence(dailyUntil: Duration(days: 60));

/// After this long without a provider record a funded operation needs
/// attention.
const kSettlementAttentionAfter = Duration(hours: 24);

/// `failed` and `notFunded` operations keep a daily check this long.
const kSettlementDailyWatch = Duration(days: 14);

/// A Spark operation is proven not funded only this long after its quote
/// expired.
const kSparkNotFundedAfterExpiry = Duration(minutes: 30);

/// Full SDK syncs with no candidate payment before a Spark operation can be
/// proven not funded.
const kSparkNotFundedMinSyncs = 2;

/// A failed status read is retried once this soon instead of after a full
/// interval. Later failures wait for the stage's normal cadence.
const kSettlementFailedReadRetry = Duration(minutes: 1);

/// A `signed` operation whose chain shows nothing keeps being checked until
/// this long after its quote expired, since the `broadcasting` write can be
/// lost after the broadcast.
const kSettlementSignedWatchAfterExpiry = Duration(minutes: 30);

/// A created operation that never got a quote is abandoned this long after
/// creation.
const kSettlementUnquotedAbandonAfter = Duration(hours: 2);

/// What the reconciler needs to know about one operation. Built from the
/// settlement record; holds no addresses or ids.
class SettlementReconcileState {
  const SettlementReconcileState({
    required this.stage,
    required this.createdAt,
    this.everBroadcast = false,
    this.fundingKind,
    this.hasFundingProof = false,
    this.quoteExpiresAt,
    this.skew = Duration.zero,
    this.broadcastingAt,
    this.fundedAt,
    this.stageEnteredAt,
    this.submitAccepted = false,
    this.submitAttempts = 0,
    this.lastSubmitAttemptAt,
    this.lastCheckedAt,
    this.consecutiveFailures = 0,
    this.sdkSyncsSinceBroadcasting = 0,
    this.lastSdkSyncGeneration,
    this.ownedByLiveFlow = false,
    this.recordVersion,
  });

  final SettlementStage stage;
  final DateTime createdAt;

  /// Whether the stage history ever contains `broadcasting`.
  final bool everBroadcast;
  final SettlementFundingKind? fundingKind;
  final bool hasFundingProof;
  final DateTime? quoteExpiresAt;

  /// Server clock minus local clock, from the quote response.
  final Duration skew;
  final DateTime? broadcastingAt;
  final DateTime? fundedAt;
  final DateTime? stageEnteredAt;

  /// `submitDeposit` was accepted or the provider detected the deposit.
  final bool submitAccepted;
  final int submitAttempts;
  final DateTime? lastSubmitAttemptAt;
  final DateTime? lastCheckedAt;
  final int consecutiveFailures;
  final int sdkSyncsSinceBroadcasting;

  /// The SDK sync generation last counted in [sdkSyncsSinceBroadcasting].
  final int? lastSdkSyncGeneration;

  /// A runner holds the operation in this process. The reconciler leaves
  /// stages below `broadcasting` to it.
  final bool ownedByLiveFlow;

  /// The record version this state was read at, returned in the result for
  /// the store's compare-and-set.
  final int? recordVersion;

  bool quoteExpired(DateTime now) {
    final expiresAt = quoteExpiresAt;
    if (expiresAt == null) return false;
    return now.add(skew).isAfter(expiresAt);
  }

  DateTime get fundsMovedAt => fundedAt ?? broadcastingAt ?? createdAt;

  /// Whether a `signed` operation with no chain evidence may be abandoned.
  bool signedWatchEnded(DateTime now) {
    final expiresAt = quoteExpiresAt;
    if (expiresAt == null) {
      return now.difference(createdAt) > kSettlementUnquotedAbandonAfter;
    }
    return now
        .add(skew)
        .isAfter(expiresAt.add(kSettlementSignedWatchAfterExpiry));
  }
}

/// The I/O one reconcile cycle performs. The driver does the I/O and hands
/// the results to [applySettlementReconcile]. Nothing here moves funds.
class SettlementReconcilePlan {
  const SettlementReconcilePlan({
    this.expireLocally = false,
    this.readStatus = false,
    this.lookupSparkPayments = false,
    this.probeFundingSource = false,
    this.submitDeposit = false,
    this.deferredForLockedSession = false,
  });

  static const idle = SettlementReconcilePlan();

  /// Apply without I/O: the quote of an operation below broadcasting
  /// expired.
  final bool expireLocally;
  final bool readStatus;

  /// Needs the Spark SDK, so only while the session is unlocked and the SDK
  /// is connected for the operation's wallet (Phase 1a).
  final bool lookupSparkPayments;

  /// Bitcoin inputs and txid, relayer transaction or Hyperliquid ledger.
  final bool probeFundingSource;

  /// Skipped by the driver when the status read returns an order.
  final bool submitDeposit;

  /// A backend read or an SDK lookup was due but waits for an unlocked
  /// session. Deferred, not failed.
  final bool deferredForLockedSession;

  bool get isIdle =>
      !expireLocally &&
      !readStatus &&
      !lookupSparkPayments &&
      !probeFundingSource &&
      !submitDeposit;
}

enum BitcoinFundingProbe {
  /// The funding txid is in the mempool or a block.
  txidSeen,

  /// An input was spent by another transaction with at least one
  /// confirmation.
  conflictConfirmed,

  /// An input was spent by another transaction still in the mempool. It can
  /// be replaced, so it proves nothing.
  conflictUnconfirmed,

  /// Inputs unspent and the txid unseen.
  noSignal,

  /// The chain could not be read.
  unavailable,
}

enum FundingSourceProbe { confirmed, provenNotSent, inconclusive, unavailable }

enum SubmitAttemptOutcome { accepted, transient, rejected }

/// Results of the I/O a plan asked for. A null field was not attempted.
class SettlementReconcileEvidence {
  const SettlementReconcileEvidence({
    this.status,
    this.providerStatus,
    this.sparkCandidates,
    this.sparkMatchedPaymentId,
    this.sdkSyncGeneration,
    this.bitcoin,
    this.fundingSource,
    this.submit,
  });

  final OrchestraStatusReadKind? status;

  /// Raw provider status when [status] is an order.
  final String? providerStatus;

  /// Outgoing Spark payments matching the amount, sent at or after
  /// broadcasting, and claimed by no other operation or Activity row.
  final int? sparkCandidates;

  /// The id of the one matching payment, only when [sparkCandidates] is 1.
  final String? sparkMatchedPaymentId;

  /// The generation of the full SDK sync the lookup ran after. Each
  /// generation counts once toward the not funded rule, however many
  /// cycles read it.
  final int? sdkSyncGeneration;
  final BitcoinFundingProbe? bitcoin;
  final FundingSourceProbe? fundingSource;
  final SubmitAttemptOutcome? submit;
}

enum SettlementReconcileSignal {
  fundingResolved,
  fundingUnknown,
  lateDeposit,
  needsAttention,
  terminal,
  regressionIgnored,
}

class SettlementReconcileResult {
  const SettlementReconcileResult({
    required this.stage,
    required this.previousStage,
    required this.consecutiveFailures,
    required this.nextCheckAt,
    required this.submitAttempts,
    required this.sdkSyncsSinceBroadcasting,
    this.lastSdkSyncGeneration,
    this.expectedRecordVersion,
    this.sparkPaymentId,
    this.lastCheckedAt,
    this.lastSubmitAttemptAt,
    this.rotateSubmitKey = false,
    this.providerDetected = false,
    this.submitAccepted = false,
    this.fundingProofRecorded = false,
    this.quoteExpiredBeforeFunding,
    this.ignoredProviderStatus,
    this.signals = const [],
  });

  final SettlementStage stage;
  final SettlementStage previousStage;
  final int consecutiveFailures;

  /// Null when only a start or foreground triggers the next check.
  final DateTime? nextCheckAt;
  final int submitAttempts;
  final int sdkSyncsSinceBroadcasting;
  final int? lastSdkSyncGeneration;

  /// The state's [SettlementReconcileState.recordVersion]. The store writes
  /// this result only while the record still has this version and
  /// [previousStage], so a stale read never overwrites a runner's write.
  final int? expectedRecordVersion;

  /// The matched outgoing Spark payment to persist as the funding proof.
  final String? sparkPaymentId;
  final DateTime? lastCheckedAt;
  final DateTime? lastSubmitAttemptAt;

  /// The submit was definitively rejected; the next one uses a new key.
  final bool rotateSubmitKey;
  final bool providerDetected;
  final bool submitAccepted;

  /// The operation became funded in this cycle.
  final bool fundingProofRecorded;

  /// Informational late flag, set when the operation becomes funded.
  final bool? quoteExpiredBeforeFunding;

  /// A provider status that would have moved the stage backwards.
  final String? ignoredProviderStatus;
  final List<SettlementReconcileSignal> signals;

  bool get stageChanged => stage != previousStage;
}

/// Provider statuses that mean the order exists and is waiting.
const _kWaitingStatuses = {
  'created',
  'awaiting_payment',
  'waiting_for_payment',
  'pending_payment',
  'awaiting_deposit',
  'waiting',
  'pending',
};

const _kProcessingStatuses = {
  'processing',
  'confirming',
  'bridging',
  'swapping',
  'awaiting_approval',
  'delivering',
};

const _kSettledStatuses = {
  'completed',
  'complete',
  'success',
  'settled',
  'done',
};

const _kLateStatuses = {'expired', 'cancelled', 'canceled', 'unfulfilled'};

/// The stage a provider status means for an operation holding a funding
/// proof. `expired`, `cancelled` and `unfulfilled` are a late deposit, and
/// `failed` stays failed. Unknown statuses mean nothing.
SettlementStage? settlementStageForProviderStatus(String rawStatus) {
  final status = rawStatus.trim().toLowerCase();
  if (_kLateStatuses.contains(status)) return SettlementStage.lateDeposit;
  if (status == 'failed') return SettlementStage.failed;
  if (status == 'refunding') return SettlementStage.refunding;
  if (status == 'refunded') return SettlementStage.refunded;
  if (_kSettledStatuses.contains(status)) return SettlementStage.settled;
  if (_kProcessingStatuses.contains(status)) return SettlementStage.processing;
  if (_kWaitingStatuses.contains(status)) return SettlementStage.submitted;
  return null;
}

/// Order of provider-driven stages; a status read only moves forward.
int _providerRank(SettlementStage stage) => switch (stage) {
      SettlementStage.funded => 0,
      SettlementStage.needsAttention => 1,
      SettlementStage.submitted => 2,
      SettlementStage.processing => 4,
      SettlementStage.lateDeposit => 6,
      SettlementStage.failed => 6,
      SettlementStage.refunding => 8,
      SettlementStage.settled => 10,
      SettlementStage.refunded => 10,
      _ => -1,
    };

const _kSubmitBackoff = [
  Duration(seconds: 30),
  Duration(minutes: 2),
  Duration(minutes: 10),
  Duration(hours: 1),
];

/// When the next submit attempt is due after [state]'s last one: 30 s,
/// 2 min, 10 min and 1 h, then hourly until a day after funding, then every
/// 6 hours.
DateTime? settlementNextSubmitAt(SettlementReconcileState state) {
  final last = state.lastSubmitAttemptAt;
  if (last == null) return null;
  final attempts = state.submitAttempts;
  Duration wait;
  if (attempts <= _kSubmitBackoff.length) {
    wait = _kSubmitBackoff[attempts < 1 ? 0 : attempts - 1];
  } else if (last.difference(state.fundsMovedAt) < kSettlementAttentionAfter) {
    wait = const Duration(hours: 1);
  } else {
    wait = const Duration(hours: 6);
  }
  return last.add(wait);
}

bool _submitDue(SettlementReconcileState state, DateTime now) {
  if (state.submitAccepted || !state.hasFundingProof) return false;
  final next = settlementNextSubmitAt(state);
  return next == null || !now.isBefore(next);
}

bool _dailyWatchActive(SettlementReconcileState state, DateTime now) {
  final since = state.stageEnteredAt ?? state.fundsMovedAt;
  return now.difference(since) < kSettlementDailyWatch;
}

bool _statusDue(
  SettlementReconcileState state,
  DateTime now, {
  required bool visible,
  required DateTime foregroundedAt,
}) {
  final last = state.lastCheckedAt;
  if (last == null || last.isAfter(now)) return true;
  if (state.consecutiveFailures == 1 &&
      now.difference(last) >= kSettlementFailedReadRetry) {
    return true;
  }
  if (state.stage == SettlementStage.failed ||
      state.stage == SettlementStage.notFunded) {
    if (!_dailyWatchActive(state, now)) return false;
    return now.difference(last) >= const Duration(days: 1);
  }
  return kSettlementStatusCadence.isDue(
    now: now,
    since: state.fundsMovedAt,
    lastCheckedAt: last,
    foregroundedAt: foregroundedAt,
    visible: visible,
  );
}

/// Which I/O a reconcile cycle should run for [state].
///
/// Phase 1a session lock: [sessionUnlocked] is true only while the session
/// is unlocked and the Spark SDK is connected for the operation's wallet,
/// because the payment lookup reads the SDK. [backendAvailable] is false
/// while the session is locked: status reads and submits use the backend
/// session, whose mint or re-auth signs with the wallet identity through
/// the SDK. Both wait for an unlock, deferred and never failed. Local
/// expiry and public chain or relayer probes run either way.
///
/// A Spark lookup runs when a status check is due, or when
/// [sparkSyncGeneration] is a completed full SDK sync this operation has not
/// counted yet, so every sync is read (B7 lookup contract).
SettlementReconcilePlan planSettlementReconcile(
  SettlementReconcileState state, {
  required DateTime now,
  required bool sessionUnlocked,
  required DateTime foregroundedAt,
  bool visible = false,
  bool backendAvailable = true,
  int? sparkSyncGeneration,
}) {
  final stage = state.stage;
  if (stage.isTerminal) return SettlementReconcilePlan.idle;
  if (stage.isBeforeBroadcasting && state.ownedByLiveFlow) {
    return SettlementReconcilePlan.idle;
  }

  if (stage == SettlementStage.signed) {
    return const SettlementReconcilePlan(probeFundingSource: true);
  }

  if (stage.isBeforeBroadcasting) {
    if (state.everBroadcast) return SettlementReconcilePlan.idle;
    final unquotedTooLong = state.quoteExpiresAt == null &&
        now.difference(state.createdAt) > kSettlementUnquotedAbandonAfter;
    return (state.quoteExpired(now) || unquotedTooLong)
        ? const SettlementReconcilePlan(expireLocally: true)
        : SettlementReconcilePlan.idle;
  }

  final due =
      _statusDue(state, now, visible: visible, foregroundedAt: foregroundedAt);
  final statusDue = due && backendAvailable;

  switch (stage) {
    case SettlementStage.broadcasting:
    case SettlementStage.fundingUnknown:
      if (state.fundingKind == SettlementFundingKind.spark) {
        final counted = state.lastSdkSyncGeneration;
        // A send a live runner holds is left to it until the cadence is due.
        final newSync = !state.ownedByLiveFlow &&
            sparkSyncGeneration != null &&
            (counted == null || sparkSyncGeneration > counted);
        final lookup = sessionUnlocked && (due || newSync);
        if (!statusDue && !lookup) {
          return SettlementReconcilePlan(
              deferredForLockedSession: due || newSync);
        }
        return SettlementReconcilePlan(
          readStatus: statusDue,
          lookupSparkPayments: lookup,
          deferredForLockedSession: !sessionUnlocked || !backendAvailable,
        );
      }
      if (!due) return SettlementReconcilePlan.idle;
      return SettlementReconcilePlan(
        readStatus: statusDue,
        probeFundingSource: true,
        deferredForLockedSession: !backendAvailable,
      );
    case SettlementStage.funded:
    case SettlementStage.needsAttention:
      final submitDue = _submitDue(state, now);
      // Source confirmation and its persisted hash are separate writes. A
      // native send must recover that hash before its first provider submit.
      final missingNativeProof =
          state.fundingKind == SettlementFundingKind.hyperliquid &&
          !state.hasFundingProof;
      final submit = submitDue && backendAvailable && !missingNativeProof;
      return SettlementReconcilePlan(
        readStatus: statusDue || submit,
        probeFundingSource: missingNativeProof && due,
        submitDeposit: submit,
        deferredForLockedSession: !backendAvailable && (due || submitDue),
      );
    default:
      if (statusDue) return const SettlementReconcilePlan(readStatus: true);
      return SettlementReconcilePlan(
          deferredForLockedSession: due && !backendAvailable);
  }
}

/// Whether the driver sends the planned submit after the status read it just
/// made. A provider order means the deposit is known, so no submit.
bool settlementShouldSubmitAfterStatus(
  SettlementReconcilePlan plan,
  OrchestraStatusReadKind? status,
) =>
    plan.submitDeposit && status != OrchestraStatusReadKind.order;

/// Applies one cycle's evidence to [state]. Pure: the same inputs always give
/// the same result. A failed status read changes only the failure count and
/// the next check. The only local expiry is `abandoned`, and only below
/// broadcasting with no provider order. A terminal stage never changes.
SettlementReconcileResult applySettlementReconcile(
  SettlementReconcileState state,
  SettlementReconcileEvidence evidence, {
  required DateTime now,
  required DateTime foregroundedAt,
  bool visible = false,
}) {
  final previous = state.stage;
  var stage = previous;
  var failures = state.consecutiveFailures;
  var submitAttempts = state.submitAttempts;
  var syncs = state.sdkSyncsSinceBroadcasting;
  var syncGeneration = state.lastSdkSyncGeneration;
  String? sparkPaymentId;
  var rotateSubmitKey = false;
  var providerDetected = false;
  var submitAccepted = state.submitAccepted;
  var fundingProofRecorded = false;
  DateTime? lastSubmitAttemptAt = state.lastSubmitAttemptAt;
  String? ignoredProviderStatus;
  final signals = <SettlementReconcileSignal>[];

  final statusRead = evidence.status;
  if (statusRead == OrchestraStatusReadKind.unavailable) {
    failures++;
  } else if (statusRead != null) {
    failures = 0;
  }
  final generation = evidence.sdkSyncGeneration;
  if (generation != null &&
      (syncGeneration == null || generation > syncGeneration)) {
    syncs++;
    syncGeneration = generation;
  }

  void becomeFunded() {
    stage = SettlementStage.funded;
    fundingProofRecorded = true;
    signals.add(SettlementReconcileSignal.fundingResolved);
  }

  final providerStage = (statusRead == OrchestraStatusReadKind.order &&
          evidence.providerStatus != null)
      ? settlementStageForProviderStatus(evidence.providerStatus!)
      : null;
  final providerSaysClosed = statusRead == OrchestraStatusReadKind.order &&
      _kLateStatuses.contains(evidence.providerStatus?.trim().toLowerCase());
  final providerOrderActive =
      statusRead == OrchestraStatusReadKind.order && !providerSaysClosed;

  void becomeProviderDetected() {
    providerDetected = true;
    submitAccepted = true;
    becomeFunded();
  }

  if (previous.isTerminal) {
    if (providerStage != null && providerStage != previous) {
      ignoredProviderStatus = evidence.providerStatus;
      signals.add(SettlementReconcileSignal.regressionIgnored);
    }
  } else if (previous.isBeforeBroadcasting && state.ownedByLiveFlow) {
    // The runner moves its own operation.
  } else if (previous == SettlementStage.signed) {
    final bitcoin = evidence.bitcoin;
    final source = evidence.fundingSource;
    final chainAnswered =
        (bitcoin != null && bitcoin != BitcoinFundingProbe.unavailable) ||
            (source != null && source != FundingSourceProbe.unavailable);
    if (providerOrderActive) {
      becomeProviderDetected();
    } else if (bitcoin == BitcoinFundingProbe.txidSeen ||
        source == FundingSourceProbe.confirmed) {
      becomeFunded();
    } else if (bitcoin == BitcoinFundingProbe.conflictConfirmed ||
        source == FundingSourceProbe.provenNotSent) {
      stage = SettlementStage.abandoned;
    } else if (chainAnswered && state.signedWatchEnded(now)) {
      stage = SettlementStage.abandoned;
    }
  } else if (previous.isBeforeBroadcasting) {
    final unquotedTooLong = state.quoteExpiresAt == null &&
        now.difference(state.createdAt) > kSettlementUnquotedAbandonAfter;
    if (providerOrderActive) {
      becomeProviderDetected();
    } else if (!state.everBroadcast &&
        (providerSaysClosed || state.quoteExpired(now) || unquotedTooLong)) {
      stage = SettlementStage.abandoned;
    }
  } else if (previous == SettlementStage.broadcasting ||
      previous == SettlementStage.fundingUnknown) {
    var learned = false;
    if (statusRead == OrchestraStatusReadKind.order) {
      becomeProviderDetected();
    } else if (state.fundingKind == SettlementFundingKind.spark) {
      final candidates = evidence.sparkCandidates;
      if (candidates != null) learned = true;
      if (statusRead == OrchestraStatusReadKind.notFound) learned = true;
      final expiresAt = state.quoteExpiresAt;
      if (candidates == 1) {
        becomeFunded();
        sparkPaymentId = evidence.sparkMatchedPaymentId;
      } else if (candidates == 0 &&
          syncs >= kSparkNotFundedMinSyncs &&
          statusRead == OrchestraStatusReadKind.notFound &&
          expiresAt != null &&
          now
              .add(state.skew)
              .isAfter(expiresAt.add(kSparkNotFundedAfterExpiry))) {
        stage = SettlementStage.notFunded;
        signals.add(SettlementReconcileSignal.fundingResolved);
      }
    } else if (state.fundingKind == SettlementFundingKind.bitcoin) {
      switch (evidence.bitcoin) {
        case BitcoinFundingProbe.txidSeen:
          becomeFunded();
        case BitcoinFundingProbe.conflictConfirmed:
          stage = SettlementStage.notFunded;
          signals.add(SettlementReconcileSignal.fundingResolved);
        case BitcoinFundingProbe.conflictUnconfirmed:
        case BitcoinFundingProbe.noSignal:
          learned = true;
        case BitcoinFundingProbe.unavailable:
        case null:
          break;
      }
    } else {
      switch (evidence.fundingSource) {
        case FundingSourceProbe.confirmed:
          becomeFunded();
        case FundingSourceProbe.provenNotSent:
          stage = SettlementStage.notFunded;
          signals.add(SettlementReconcileSignal.fundingResolved);
        case FundingSourceProbe.inconclusive:
          learned = true;
        case FundingSourceProbe.unavailable:
        case null:
          break;
      }
    }
    if (stage == previous &&
        previous == SettlementStage.broadcasting &&
        learned) {
      stage = SettlementStage.fundingUnknown;
      signals.add(SettlementReconcileSignal.fundingUnknown);
    }
  } else if (previous == SettlementStage.notFunded) {
    if (statusRead == OrchestraStatusReadKind.order) {
      providerDetected = true;
      submitAccepted = true;
      if (providerStage == SettlementStage.lateDeposit) {
        stage = SettlementStage.lateDeposit;
        fundingProofRecorded = true;
        signals.add(SettlementReconcileSignal.lateDeposit);
      } else {
        becomeFunded();
      }
    }
  } else {
    if (previous == SettlementStage.funded ||
        previous == SettlementStage.needsAttention) {
      if (statusRead == OrchestraStatusReadKind.order) {
        providerDetected = true;
        submitAccepted = true;
      }
      final submit = evidence.submit;
      if (submit != null) {
        submitAttempts++;
        lastSubmitAttemptAt = now;
        if (submit == SubmitAttemptOutcome.accepted) submitAccepted = true;
        if (submit == SubmitAttemptOutcome.rejected) rotateSubmitKey = true;
      }
      if (previous == SettlementStage.funded && submitAccepted) {
        stage = SettlementStage.submitted;
      }
    }

    if (providerStage != null) {
      final current = stage;
      if (_providerRank(providerStage) > _providerRank(current)) {
        stage = providerStage;
      } else if (providerStage != current &&
          _providerRank(providerStage) < _providerRank(current)) {
        ignoredProviderStatus = evidence.providerStatus;
        signals.add(SettlementReconcileSignal.regressionIgnored);
      }
    }

    final noProviderRecord =
        statusRead == OrchestraStatusReadKind.notFound && !submitAccepted;
    final notFoundTooLong = statusRead == OrchestraStatusReadKind.notFound &&
        (stage == SettlementStage.submitted ||
            stage == SettlementStage.processing);
    if ((stage == SettlementStage.funded && noProviderRecord ||
            notFoundTooLong) &&
        now.difference(state.fundsMovedAt) > kSettlementAttentionAfter) {
      stage = SettlementStage.needsAttention;
    }
  }

  if (stage != previous) {
    if (stage == SettlementStage.lateDeposit &&
        !signals.contains(SettlementReconcileSignal.lateDeposit)) {
      signals.add(SettlementReconcileSignal.lateDeposit);
    }
    if (stage == SettlementStage.needsAttention) {
      signals.add(SettlementReconcileSignal.needsAttention);
    }
    if (stage.isTerminal || stage == SettlementStage.failed) {
      signals.add(SettlementReconcileSignal.terminal);
    }
  }

  bool? lateFlag;
  if (fundingProofRecorded) {
    final expiresAt = state.quoteExpiresAt;
    final fundedAt = state.fundedAt ?? state.broadcastingAt ?? now;
    lateFlag = expiresAt != null && fundedAt.add(state.skew).isAfter(expiresAt);
  }

  final lastCheckedAt = statusRead != null ? now : state.lastCheckedAt;
  final next = _nextCheckAt(
    stage: stage,
    state: state,
    now: now,
    failures: failures,
    visible: visible,
  );

  return SettlementReconcileResult(
    stage: stage,
    previousStage: previous,
    consecutiveFailures: failures,
    nextCheckAt: next,
    submitAttempts: submitAttempts,
    sdkSyncsSinceBroadcasting: syncs,
    lastSdkSyncGeneration: syncGeneration,
    expectedRecordVersion: state.recordVersion,
    sparkPaymentId: sparkPaymentId,
    lastCheckedAt: lastCheckedAt,
    lastSubmitAttemptAt: lastSubmitAttemptAt,
    rotateSubmitKey: rotateSubmitKey,
    providerDetected: providerDetected,
    submitAccepted: submitAccepted,
    fundingProofRecorded: fundingProofRecorded,
    quoteExpiredBeforeFunding: lateFlag,
    ignoredProviderStatus: ignoredProviderStatus,
    signals: List.unmodifiable(signals),
  );
}

DateTime? _nextCheckAt({
  required SettlementStage stage,
  required SettlementReconcileState state,
  required DateTime now,
  required int failures,
  required bool visible,
}) {
  if (stage.isTerminal) return null;
  if (stage.isBeforeBroadcasting) {
    final expiresAt = state.quoteExpiresAt;
    return expiresAt?.subtract(state.skew);
  }
  if (failures == 1 && !visible) return now.add(kSettlementFailedReadRetry);
  if (stage == SettlementStage.failed || stage == SettlementStage.notFunded) {
    final since = stage == state.stage
        ? (state.stageEnteredAt ?? state.fundsMovedAt)
        : now;
    return now.difference(since) < kSettlementDailyWatch
        ? now.add(const Duration(days: 1))
        : null;
  }
  return kSettlementStatusCadence.nextCheckAt(
    now: now,
    since: state.fundsMovedAt,
    visible: visible,
  );
}

/// The I/O ports a reconcile cycle uses. None of them moves funds.
/// Outgoing Spark payments matching an operation, read after a full SDK sync.
typedef SparkCandidateLookup = ({
  int count,

  /// The payment id when [count] is 1, otherwise null.
  String? matchedPaymentId,

  /// Increases with every completed full SDK sync.
  int syncGeneration,
});

abstract class SettlementReconcilePorts {
  Future<({OrchestraStatusReadKind kind, String? providerStatus})> readStatus();

  /// Runs after a full SDK sync. Null when no sync completed.
  Future<SparkCandidateLookup?> findSparkCandidates();

  Future<BitcoinFundingProbe> probeBitcoin();

  Future<FundingSourceProbe> probeFundingSource();

  /// Sends `submitDeposit` with the operation's persisted key.
  Future<SubmitAttemptOutcome> submitDeposit();
}

/// Runs one reconcile cycle: plan, the planned I/O, then apply.
Future<SettlementReconcileResult?> runSettlementReconcileCycle(
  SettlementReconcileState state,
  SettlementReconcilePorts ports, {
  required DateTime Function() now,
  required bool sessionUnlocked,
  required DateTime foregroundedAt,
  bool visible = false,
  bool backendAvailable = true,
  int? sparkSyncGeneration,
}) async {
  final startedAt = now();
  final plan = planSettlementReconcile(
    state,
    now: startedAt,
    sessionUnlocked: sessionUnlocked,
    foregroundedAt: foregroundedAt,
    visible: visible,
    backendAvailable: backendAvailable,
    sparkSyncGeneration: sparkSyncGeneration,
  );
  if (plan.isIdle) return null;

  OrchestraStatusReadKind? status;
  String? providerStatus;
  if (plan.readStatus) {
    try {
      final read = await ports.readStatus();
      status = read.kind;
      providerStatus = read.providerStatus;
    } catch (_) {
      status = OrchestraStatusReadKind.unavailable;
    }
  }

  SparkCandidateLookup? lookup;
  if (plan.lookupSparkPayments) {
    try {
      lookup = await ports.findSparkCandidates();
    } catch (_) {}
  }

  BitcoinFundingProbe? bitcoin;
  FundingSourceProbe? source;
  if (plan.probeFundingSource) {
    if (state.fundingKind == SettlementFundingKind.bitcoin) {
      try {
        bitcoin = await ports.probeBitcoin();
      } catch (_) {
        bitcoin = BitcoinFundingProbe.unavailable;
      }
    } else {
      try {
        source = await ports.probeFundingSource();
      } catch (_) {
        source = FundingSourceProbe.unavailable;
      }
    }
  }

  SubmitAttemptOutcome? submit;
  if (settlementShouldSubmitAfterStatus(plan, status)) {
    try {
      submit = await ports.submitDeposit();
    } catch (_) {
      submit = SubmitAttemptOutcome.transient;
    }
  }

  return applySettlementReconcile(
    state,
    SettlementReconcileEvidence(
      status: status,
      providerStatus: providerStatus,
      sparkCandidates: lookup?.count,
      sparkMatchedPaymentId:
          lookup?.count == 1 ? lookup?.matchedPaymentId : null,
      sdkSyncGeneration: lookup?.syncGeneration,
      bitcoin: bitcoin,
      fundingSource: source,
      submit: submit,
    ),
    now: now(),
    foregroundedAt: foregroundedAt,
    visible: visible,
  );
}
