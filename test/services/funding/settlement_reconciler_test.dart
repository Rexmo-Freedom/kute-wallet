import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/cash_app_status.dart';
import 'package:kute/helpers/orchestra_legacy_status_rules.dart'
    show OrchestraStatusReadKind;
import 'package:kute/services/funding/settlement_reconciler.dart';
import 'package:kute/services/funding/settlement_stage.dart';

final _t0 = DateTime.utc(2026, 9, 1, 12);
final _expiresAt = _t0.add(const Duration(minutes: 2));
final _broadcastAt = _t0.add(const Duration(minutes: 1));

SettlementReconcileState _state(
  SettlementStage stage, {
  SettlementFundingKind kind = SettlementFundingKind.spark,
  bool? everBroadcast,
  bool? hasFundingProof,
  DateTime? quoteExpiresAt,
  Duration skew = Duration.zero,
  DateTime? broadcastingAt,
  DateTime? fundedAt,
  DateTime? stageEnteredAt,
  bool submitAccepted = false,
  int submitAttempts = 0,
  DateTime? lastSubmitAttemptAt,
  DateTime? lastCheckedAt,
  int consecutiveFailures = 0,
  int sdkSyncs = 0,
  int? lastSdkSyncGeneration,
  bool ownedByLiveFlow = false,
  int? recordVersion,
}) {
  final pastBroadcast =
      !stage.isBeforeBroadcasting && stage != SettlementStage.abandoned;
  return SettlementReconcileState(
    stage: stage,
    createdAt: _t0,
    everBroadcast: everBroadcast ?? pastBroadcast,
    fundingKind: kind,
    hasFundingProof: hasFundingProof ??
        (pastBroadcast &&
            stage != SettlementStage.broadcasting &&
            stage != SettlementStage.fundingUnknown &&
            stage != SettlementStage.notFunded),
    quoteExpiresAt: quoteExpiresAt ?? _expiresAt,
    skew: skew,
    broadcastingAt: broadcastingAt ?? (pastBroadcast ? _broadcastAt : null),
    fundedAt: fundedAt,
    stageEnteredAt: stageEnteredAt,
    submitAccepted: submitAccepted,
    submitAttempts: submitAttempts,
    lastSubmitAttemptAt: lastSubmitAttemptAt,
    lastCheckedAt: lastCheckedAt,
    consecutiveFailures: consecutiveFailures,
    sdkSyncsSinceBroadcasting: sdkSyncs,
    lastSdkSyncGeneration: lastSdkSyncGeneration,
    ownedByLiveFlow: ownedByLiveFlow,
    recordVersion: recordVersion,
  );
}

SettlementReconcileResult _apply(
  SettlementReconcileState state,
  SettlementReconcileEvidence evidence, {
  required DateTime now,
  bool visible = false,
}) =>
    applySettlementReconcile(state, evidence,
        now: now, foregroundedAt: _t0, visible: visible);

SettlementReconcilePlan _plan(
  SettlementReconcileState state, {
  required DateTime now,
  bool sessionUnlocked = true,
  DateTime? foregroundedAt,
  bool visible = false,
}) =>
    planSettlementReconcile(state,
        now: now,
        sessionUnlocked: sessionUnlocked,
        foregroundedAt: foregroundedAt ?? _t0,
        visible: visible);

const _order = OrchestraStatusReadKind.order;
const _notFound = OrchestraStatusReadKind.notFound;
const _unavailable = OrchestraStatusReadKind.unavailable;

SettlementReconcileEvidence _status(OrchestraStatusReadKind kind,
        [String? providerStatus]) =>
    SettlementReconcileEvidence(status: kind, providerStatus: providerStatus);

class _FakePorts implements SettlementReconcilePorts {
  _FakePorts({
    this.status = _unavailable,
    this.providerStatus,
    this.submitOutcome = SubmitAttemptOutcome.transient,
    this.sourceOutcome = FundingSourceProbe.unavailable,
    this.candidates,
  });

  OrchestraStatusReadKind status;
  String? providerStatus;
  SubmitAttemptOutcome submitOutcome;
  FundingSourceProbe sourceOutcome;
  int? candidates;
  int statusReads = 0;
  int submits = 0;
  int sparkLookups = 0;
  int sourceProbes = 0;

  @override
  Future<({OrchestraStatusReadKind kind, String? providerStatus})>
      readStatus() async {
    statusReads++;
    return (kind: status, providerStatus: providerStatus);
  }

  @override
  Future<SparkCandidateLookup?> findSparkCandidates() async {
    sparkLookups++;
    final count = candidates;
    return count == null
        ? null
        : (count: count, matchedPaymentId: null, syncGeneration: sparkLookups);
  }

  @override
  Future<BitcoinFundingProbe> probeBitcoin() async =>
      BitcoinFundingProbe.unavailable;

  @override
  Future<FundingSourceProbe> probeFundingSource() async {
    sourceProbes++;
    return sourceOutcome;
  }

  @override
  Future<SubmitAttemptOutcome> submitDeposit() async {
    submits++;
    return submitOutcome;
  }
}

void main() {
  group('stages below broadcasting', () {
    for (final stage in [
      SettlementStage.created,
      SettlementStage.quoted,
      SettlementStage.reviewed,
      SettlementStage.authorizing,
    ]) {
      test('${stage.name} waits while the quote is live', () {
        final now = _expiresAt.subtract(const Duration(seconds: 1));
        expect(_plan(_state(stage), now: now).isIdle, isTrue);
        expect(
            _apply(_state(stage), const SettlementReconcileEvidence(), now: now)
                .stage,
            stage);
      });

      test('${stage.name} is abandoned once the quote expired', () {
        final now = _expiresAt.add(const Duration(seconds: 1));
        expect(_plan(_state(stage), now: now).expireLocally, isTrue);
        expect(
            _apply(_state(stage), const SettlementReconcileEvidence(), now: now)
                .stage,
            SettlementStage.abandoned);
      });
    }

    test('skew decides expiry', () {
      final now = _expiresAt.subtract(const Duration(seconds: 30));
      final ahead =
          _state(SettlementStage.quoted, skew: const Duration(seconds: 60));
      expect(_plan(ahead, now: now).expireLocally, isTrue);
      final behind =
          _state(SettlementStage.quoted, skew: const Duration(seconds: -60));
      expect(
          _plan(behind, now: _expiresAt.add(const Duration(seconds: 30)))
              .expireLocally,
          isFalse);
    });

    test('a record that ever reached broadcasting is never abandoned', () {
      final now = _expiresAt.add(const Duration(days: 3));
      final state = _state(SettlementStage.authorizing, everBroadcast: true);
      expect(_plan(state, now: now).isIdle, isTrue);
      expect(_apply(state, const SettlementReconcileEvidence(), now: now).stage,
          SettlementStage.authorizing);
    });

    test('unfulfilled without a proof below broadcasting is abandoned', () {
      final now = _t0.add(const Duration(seconds: 30));
      final result = _apply(
          _state(SettlementStage.reviewed), _status(_order, 'unfulfilled'),
          now: now);
      expect(result.stage, SettlementStage.abandoned);
    });

    test('signed: txid seen is funded, a confirmed conflict is abandoned', () {
      final now = _expiresAt.add(const Duration(minutes: 5));
      final signed =
          _state(SettlementStage.signed, kind: SettlementFundingKind.bitcoin);
      expect(_plan(signed, now: now).probeFundingSource, isTrue);
      expect(
          _apply(
                  signed,
                  const SettlementReconcileEvidence(
                      bitcoin: BitcoinFundingProbe.txidSeen),
                  now: now)
              .stage,
          SettlementStage.funded);
      expect(
          _apply(
                  signed,
                  const SettlementReconcileEvidence(
                      bitcoin: BitcoinFundingProbe.conflictConfirmed),
                  now: now)
              .stage,
          SettlementStage.abandoned);
      expect(
          _apply(
                  signed,
                  const SettlementReconcileEvidence(
                      bitcoin: BitcoinFundingProbe.unavailable),
                  now: now)
              .stage,
          SettlementStage.signed);
    });

    for (final probe in [
      BitcoinFundingProbe.noSignal,
      BitcoinFundingProbe.conflictUnconfirmed,
    ]) {
      test('signed: ${probe.name} is watched until 30 min after expiry', () {
        final signed =
            _state(SettlementStage.signed, kind: SettlementFundingKind.bitcoin);
        final evidence = SettlementReconcileEvidence(bitcoin: probe);
        for (final now in [
          _t0.add(const Duration(seconds: 30)),
          _expiresAt.add(const Duration(minutes: 5)),
          _expiresAt.add(kSettlementSignedWatchAfterExpiry),
        ]) {
          expect(
              _apply(signed, evidence, now: now).stage, SettlementStage.signed,
              reason: '$now');
        }
        expect(
            _apply(signed, evidence,
                    now:
                        _expiresAt.add(const Duration(minutes: 30, seconds: 1)))
                .stage,
            SettlementStage.abandoned);
      });
    }

    test('signed: an inconclusive source is watched, then abandoned', () {
      final signed =
          _state(SettlementStage.signed, kind: SettlementFundingKind.relayer);
      const inconclusive = SettlementReconcileEvidence(
          fundingSource: FundingSourceProbe.inconclusive);
      expect(
          _apply(signed, inconclusive,
                  now: _expiresAt.add(const Duration(minutes: 10)))
              .stage,
          SettlementStage.signed);
      expect(
          _apply(signed, inconclusive,
                  now: _expiresAt.add(const Duration(minutes: 31)))
              .stage,
          SettlementStage.abandoned);
      expect(
          _apply(
                  signed,
                  const SettlementReconcileEvidence(
                      fundingSource: FundingSourceProbe.unavailable),
                  now: _expiresAt.add(const Duration(days: 2)))
              .stage,
          SettlementStage.signed);
    });

    for (final stage in [
      SettlementStage.created,
      SettlementStage.quoted,
      SettlementStage.reviewed,
      SettlementStage.authorizing,
      SettlementStage.signed,
    ]) {
      test('${stage.name} held by a live flow is left to the runner', () {
        final now = _expiresAt.add(const Duration(hours: 3));
        final state = _state(stage,
            kind: SettlementFundingKind.bitcoin, ownedByLiveFlow: true);
        expect(_plan(state, now: now).isIdle, isTrue);
        for (final evidence in const [
          SettlementReconcileEvidence(),
          SettlementReconcileEvidence(bitcoin: BitcoinFundingProbe.noSignal),
          SettlementReconcileEvidence(
              status: OrchestraStatusReadKind.order, providerStatus: 'expired'),
        ]) {
          expect(_apply(state, evidence, now: now).stage, stage);
        }
      });

      for (final providerStatus in [
        'processing',
        'awaiting_approval',
        'pending',
        'completed',
        'refunding',
      ]) {
        test('${stage.name} with a $providerStatus order is never abandoned',
            () {
          final now = _expiresAt.add(const Duration(hours: 3));
          final result = _apply(
              _state(stage, kind: SettlementFundingKind.spark),
              _status(_order, providerStatus),
              now: now);
          expect(result.stage, SettlementStage.funded);
          expect(result.providerDetected, isTrue);
          expect(result.fundingProofRecorded, isTrue);
        });
      }
    }
  });

  group('record version', () {
    test('the result carries the version the state was read at', () {
      final result = _apply(
          _state(SettlementStage.processing, recordVersion: 7),
          _status(_order, 'completed'),
          now: _expiresAt.add(const Duration(minutes: 5)));
      expect(result.expectedRecordVersion, 7);
      expect(result.previousStage, SettlementStage.processing);
    });
  });

  group('status failures never change stage', () {
    final now = _t0.add(const Duration(seconds: 30));
    for (final stage in SettlementStage.values) {
      test(stage.name, () {
        final state = _state(stage, lastCheckedAt: _t0, stageEnteredAt: _t0);
        final result = _apply(state, _status(_unavailable), now: now);
        expect(result.stage, stage);
        expect(result.consecutiveFailures, 1);
        expect(result.submitAttempts, state.submitAttempts);
        expect(result.rotateSubmitKey, isFalse);
        expect(result.fundingProofRecorded, isFalse);
        if (!stage.isTerminal && !stage.isBeforeBroadcasting) {
          expect(result.nextCheckAt, now.add(kSettlementFailedReadRetry));
        }
      });
    }

    test('only the first failure gets the quick retry', () {
      for (final stage in [
        SettlementStage.processing,
        SettlementStage.failed,
        SettlementStage.notFunded,
      ]) {
        final old = _t0.add(const Duration(days: 70));
        final state = _state(stage,
            lastCheckedAt: old, stageEnteredAt: _t0, consecutiveFailures: 1);
        final now = old.add(kSettlementFailedReadRetry);
        expect(_plan(state, now: now).readStatus, isTrue, reason: stage.name);

        final second = _apply(state, _status(_unavailable), now: now);
        expect(second.consecutiveFailures, 2);
        expect(second.nextCheckAt, isNot(now.add(kSettlementFailedReadRetry)),
            reason: stage.name);
        final afterSecond = _state(stage,
            lastCheckedAt: now, stageEnteredAt: _t0, consecutiveFailures: 2);
        expect(
            _plan(afterSecond,
                    now: now.add(const Duration(hours: 2)), foregroundedAt: _t0)
                .readStatus,
            isFalse,
            reason: stage.name);
      }
    });

    test('a failed read never produces notFunded, at any age', () {
      for (final age in const [
        Duration(minutes: 31),
        Duration(hours: 5),
        Duration(days: 30),
      ]) {
        final state = _state(SettlementStage.fundingUnknown, sdkSyncs: 10);
        final result = _apply(
          state,
          const SettlementReconcileEvidence(
              status: _unavailable, sparkCandidates: 0, sdkSyncGeneration: 1),
          now: _expiresAt.add(age),
        );
        expect(result.stage, SettlementStage.fundingUnknown, reason: '$age');
      }
    });
  });

  group('Spark funding resolution after broadcasting', () {
    final late = _expiresAt.add(const Duration(minutes: 31));

    test('a provider-detected deposit is funded', () {
      final result = _apply(
          _state(SettlementStage.broadcasting), _status(_order, 'processing'),
          now: late);
      expect(result.stage, SettlementStage.funded);
      expect(result.providerDetected, isTrue);
      expect(result.fundingProofRecorded, isTrue);
    });

    test('exactly one matching payment is funded', () {
      final result = _apply(
        _state(SettlementStage.broadcasting),
        const SettlementReconcileEvidence(
            status: _notFound, sparkCandidates: 1, sdkSyncGeneration: 1),
        now: late,
      );
      expect(result.stage, SettlementStage.funded);
    });

    test('two matching payments stay unknown', () {
      final result = _apply(
        _state(SettlementStage.broadcasting, sdkSyncs: 3),
        const SettlementReconcileEvidence(
            status: _notFound, sparkCandidates: 2, sdkSyncGeneration: 1),
        now: late,
      );
      expect(result.stage, SettlementStage.fundingUnknown);
    });

    test(
        'no payment after two syncs, 30 min past expiry and no order is '
        'not funded', () {
      final result = _apply(
        _state(SettlementStage.fundingUnknown, sdkSyncs: 1),
        const SettlementReconcileEvidence(
            status: _notFound, sparkCandidates: 0, sdkSyncGeneration: 1),
        now: late,
      );
      expect(result.stage, SettlementStage.notFunded);
    });

    test('the same SDK sync generation counts once', () {
      final state = _state(SettlementStage.fundingUnknown,
          sdkSyncs: 1, lastSdkSyncGeneration: 4);
      final repeated = _apply(
        state,
        const SettlementReconcileEvidence(
            status: _notFound, sparkCandidates: 0, sdkSyncGeneration: 4),
        now: late,
      );
      expect(repeated.sdkSyncsSinceBroadcasting, 1);
      expect(repeated.stage, SettlementStage.fundingUnknown);
      final next = _apply(
        state,
        const SettlementReconcileEvidence(
            status: _notFound, sparkCandidates: 0, sdkSyncGeneration: 5),
        now: late,
      );
      expect(next.sdkSyncsSinceBroadcasting, 2);
      expect(next.lastSdkSyncGeneration, 5);
      expect(next.stage, SettlementStage.notFunded);
    });

    test('the one matching payment id is returned for the record', () {
      final result = _apply(
        _state(SettlementStage.fundingUnknown),
        const SettlementReconcileEvidence(
            status: _notFound,
            sparkCandidates: 1,
            sparkMatchedPaymentId: 'payment-1',
            sdkSyncGeneration: 1),
        now: late,
      );
      expect(result.stage, SettlementStage.funded);
      expect(result.sparkPaymentId, 'payment-1');
    });

    test('one sync is not enough to prove not funded', () {
      final result = _apply(
        _state(SettlementStage.fundingUnknown),
        const SettlementReconcileEvidence(
            status: _notFound, sparkCandidates: 0, sdkSyncGeneration: 1),
        now: late,
      );
      expect(result.stage, SettlementStage.fundingUnknown);
    });

    test('before 30 min past expiry it stays unknown', () {
      final result = _apply(
        _state(SettlementStage.fundingUnknown, sdkSyncs: 5),
        const SettlementReconcileEvidence(
            status: _notFound, sparkCandidates: 0, sdkSyncGeneration: 1),
        now: _expiresAt.add(const Duration(minutes: 29)),
      );
      expect(result.stage, SettlementStage.fundingUnknown);
    });

    test('a locked session defers the SDK lookup, not the status read', () {
      final state = _state(SettlementStage.broadcasting);
      final locked = _plan(state, now: late, sessionUnlocked: false);
      expect(locked.readStatus, isTrue);
      expect(locked.lookupSparkPayments, isFalse);
      expect(locked.deferredForLockedSession, isTrue);
      final unlocked = _plan(state, now: late);
      expect(unlocked.lookupSparkPayments, isTrue);
      expect(unlocked.deferredForLockedSession, isFalse);
    });

    test('the driver never looks up SDK payments while locked', () async {
      final ports = _FakePorts(status: _notFound, candidates: 0);
      final result = await runSettlementReconcileCycle(
        _state(SettlementStage.broadcasting),
        ports,
        now: () => late,
        sessionUnlocked: false,
        foregroundedAt: _t0,
      );
      expect(ports.sparkLookups, 0);
      expect(ports.statusReads, 1);
      expect(result!.stage, SettlementStage.fundingUnknown);
    });
  });

  group('other funding kinds after broadcasting', () {
    final now = _expiresAt.add(const Duration(minutes: 10));

    test('bitcoin txid seen is funded', () {
      expect(
          _apply(
                  _state(SettlementStage.broadcasting,
                      kind: SettlementFundingKind.bitcoin),
                  const SettlementReconcileEvidence(
                      bitcoin: BitcoinFundingProbe.txidSeen),
                  now: now)
              .stage,
          SettlementStage.funded);
    });

    test('a confirmed conflicting spend is not funded', () {
      expect(
          _apply(
                  _state(SettlementStage.fundingUnknown,
                      kind: SettlementFundingKind.bitcoin),
                  const SettlementReconcileEvidence(
                      bitcoin: BitcoinFundingProbe.conflictConfirmed),
                  now: now)
              .stage,
          SettlementStage.notFunded);
    });

    test('a mempool-only conflict stays unknown', () {
      expect(
          _apply(
                  _state(SettlementStage.broadcasting,
                      kind: SettlementFundingKind.bitcoin),
                  const SettlementReconcileEvidence(
                      bitcoin: BitcoinFundingProbe.conflictUnconfirmed),
                  now: now)
              .stage,
          SettlementStage.fundingUnknown);
    });

    test('an unreadable chain changes nothing', () {
      expect(
          _apply(
                  _state(SettlementStage.broadcasting,
                      kind: SettlementFundingKind.bitcoin),
                  const SettlementReconcileEvidence(
                      status: _unavailable,
                      bitcoin: BitcoinFundingProbe.unavailable),
                  now: now)
              .stage,
          SettlementStage.broadcasting);
    });

    test('relayer confirmed is funded, proven not sent is not funded', () {
      final state = _state(SettlementStage.broadcasting,
          kind: SettlementFundingKind.relayer);
      expect(
          _apply(
                  state,
                  const SettlementReconcileEvidence(
                      fundingSource: FundingSourceProbe.confirmed),
                  now: now)
              .stage,
          SettlementStage.funded);
      expect(
          _apply(
                  state,
                  const SettlementReconcileEvidence(
                      fundingSource: FundingSourceProbe.provenNotSent),
                  now: now)
              .stage,
          SettlementStage.notFunded);
    });
  });

  group('funded: registration', () {
    final fundedAt = _broadcastAt;
    final now = fundedAt.add(const Duration(minutes: 1));

    test('native source confirmation waits for persisted proof before submit',
        () async {
      final ports = _FakePorts(
          status: _notFound,
          sourceOutcome: FundingSourceProbe.confirmed,
          submitOutcome: SubmitAttemptOutcome.accepted);
      // Simulate interruption between recording `funded` and saving the hash.
      final missingHash = _state(SettlementStage.funded,
          kind: SettlementFundingKind.hyperliquid,
          fundedAt: fundedAt,
          hasFundingProof: false);
      await runSettlementReconcileCycle(missingHash, ports,
          now: () => now,
          sessionUnlocked: true,
          foregroundedAt: _t0);
      expect(ports.sourceProbes, 1);
      expect(ports.submits, 0);

      final persisted = _state(SettlementStage.funded,
          kind: SettlementFundingKind.hyperliquid,
          fundedAt: fundedAt,
          hasFundingProof: true);
      final result = await runSettlementReconcileCycle(persisted, ports,
          now: () => now,
          sessionUnlocked: true,
          foregroundedAt: _t0);
      expect(ports.submits, 1);
      expect(result!.stage, SettlementStage.submitted);
    });

    test('a first submit is planned with a status read', () {
      final plan =
          _plan(_state(SettlementStage.funded, fundedAt: fundedAt), now: now);
      expect(plan.readStatus, isTrue);
      expect(plan.submitDeposit, isTrue);
    });

    test('a non-null order skips submit and becomes submitted', () async {
      final ports = _FakePorts(status: _order, providerStatus: 'processing');
      final result = await runSettlementReconcileCycle(
        _state(SettlementStage.funded, fundedAt: fundedAt),
        ports,
        now: () => now,
        sessionUnlocked: true,
        foregroundedAt: _t0,
      );
      expect(ports.submits, 0);
      expect(result!.stage, SettlementStage.processing);
      expect(result.providerDetected, isTrue);
    });

    test('an accepted submit becomes submitted', () async {
      final ports = _FakePorts(
          status: _notFound, submitOutcome: SubmitAttemptOutcome.accepted);
      final result = await runSettlementReconcileCycle(
        _state(SettlementStage.funded, fundedAt: fundedAt),
        ports,
        now: () => now,
        sessionUnlocked: true,
        foregroundedAt: _t0,
      );
      expect(ports.submits, 1);
      expect(result!.stage, SettlementStage.submitted);
      expect(result.submitAttempts, 1);
      expect(result.rotateSubmitKey, isFalse);
    });

    test('a transient failure keeps the key and backs off', () {
      final result = _apply(
        _state(SettlementStage.funded, fundedAt: fundedAt),
        const SettlementReconcileEvidence(
            status: _unavailable, submit: SubmitAttemptOutcome.transient),
        now: now,
      );
      expect(result.stage, SettlementStage.funded);
      expect(result.rotateSubmitKey, isFalse);
      expect(result.submitAttempts, 1);
      expect(result.lastSubmitAttemptAt, now);
    });

    test('a definitive rejection asks for a new key', () {
      final result = _apply(
        _state(SettlementStage.funded, fundedAt: fundedAt),
        const SettlementReconcileEvidence(
            status: _notFound, submit: SubmitAttemptOutcome.rejected),
        now: now,
      );
      expect(result.stage, SettlementStage.funded);
      expect(result.rotateSubmitKey, isTrue);
    });

    test('submit backoff: 30 s, 2 min, 10 min, 1 h, hourly, then 6 h', () {
      DateTime next(int attempts, DateTime last) => settlementNextSubmitAt(
            _state(SettlementStage.funded,
                fundedAt: fundedAt,
                submitAttempts: attempts,
                lastSubmitAttemptAt: last),
          )!;
      expect(next(1, now), now.add(const Duration(seconds: 30)));
      expect(next(2, now), now.add(const Duration(minutes: 2)));
      expect(next(3, now), now.add(const Duration(minutes: 10)));
      expect(next(4, now), now.add(const Duration(hours: 1)));
      expect(next(5, now), now.add(const Duration(hours: 1)));
      final dayLater = fundedAt.add(const Duration(hours: 25));
      expect(next(9, dayLater), dayLater.add(const Duration(hours: 6)));
    });

    test('a submit is not repeated before its backoff', () {
      final state = _state(SettlementStage.funded,
          fundedAt: fundedAt,
          submitAttempts: 1,
          lastSubmitAttemptAt: now,
          lastCheckedAt: now);
      expect(
          _plan(state, now: now.add(const Duration(seconds: 29))).submitDeposit,
          isFalse);
      expect(
          _plan(state, now: now.add(const Duration(seconds: 30))).submitDeposit,
          isTrue);
    });

    test('no provider record after 24 h needs attention and keeps submitting',
        () {
      final later = fundedAt.add(const Duration(hours: 25));
      final result = _apply(
        _state(SettlementStage.funded, fundedAt: fundedAt, submitAttempts: 20),
        const SettlementReconcileEvidence(
            status: _notFound, submit: SubmitAttemptOutcome.transient),
        now: later,
      );
      expect(result.stage, SettlementStage.needsAttention);
      final attention = _state(SettlementStage.needsAttention,
          fundedAt: fundedAt,
          submitAttempts: 21,
          lastSubmitAttemptAt: later,
          lastCheckedAt: later);
      expect(
          _plan(attention, now: later.add(const Duration(hours: 6)))
              .submitDeposit,
          isTrue);
    });

    test('a failed read after 24 h never moves funded to needs attention', () {
      final result = _apply(
        _state(SettlementStage.funded, fundedAt: fundedAt, submitAttempts: 20),
        const SettlementReconcileEvidence(
            status: _unavailable, submit: SubmitAttemptOutcome.transient),
        now: fundedAt.add(const Duration(days: 3)),
      );
      expect(result.stage, SettlementStage.funded);
    });

    test('submit is never planned after submitted', () {
      final later = fundedAt.add(const Duration(days: 2));
      for (final stage in [
        SettlementStage.submitted,
        SettlementStage.processing,
        SettlementStage.refunding,
        SettlementStage.lateDeposit,
        SettlementStage.settled,
        SettlementStage.refunded,
        SettlementStage.failed,
      ]) {
        expect(
            _plan(_state(stage, fundedAt: fundedAt, stageEnteredAt: later),
                    now: later)
                .submitDeposit,
            isFalse,
            reason: stage.name);
      }
      expect(
          _plan(
                  _state(SettlementStage.needsAttention,
                      fundedAt: fundedAt, submitAccepted: true),
                  now: later)
              .submitDeposit,
          isFalse);
    });
  });

  group('provider statuses for operations with a funding proof', () {
    final now = _broadcastAt.add(const Duration(hours: 1));

    const table = {
      'expired': SettlementStage.lateDeposit,
      'cancelled': SettlementStage.lateDeposit,
      'canceled': SettlementStage.lateDeposit,
      'unfulfilled': SettlementStage.lateDeposit,
      'UNFULFILLED': SettlementStage.lateDeposit,
      'failed': SettlementStage.failed,
      'refunding': SettlementStage.refunding,
      'refunded': SettlementStage.refunded,
      'completed': SettlementStage.settled,
      'processing': SettlementStage.processing,
    };

    table.forEach((status, expected) {
      test('$status from submitted gives ${expected.name}', () {
        expect(settlementStageForProviderStatus(status), expected);
        final result = _apply(
            _state(SettlementStage.submitted), _status(_order, status),
            now: now);
        expect(result.stage, expected);
      });
    });

    test('failed is never mapped to expired', () {
      expect(settlementStageForProviderStatus('failed'),
          isNot(SettlementStage.abandoned));
    });

    test('unknown statuses change nothing', () {
      expect(settlementStageForProviderStatus('mystery'), isNull);
      expect(
          _apply(_state(SettlementStage.processing), _status(_order, 'mystery'),
                  now: now)
              .stage,
          SettlementStage.processing);
    });

    test('a 404 at funded or later stays tracked, then needs attention', () {
      final state = _state(SettlementStage.submitted, fundedAt: _broadcastAt);
      expect(_apply(state, _status(_notFound), now: now).stage,
          SettlementStage.submitted);
      expect(
          _apply(state, _status(_notFound),
                  now: _broadcastAt.add(const Duration(hours: 25)))
              .stage,
          SettlementStage.needsAttention);
    });
  });

  group('failed and notFunded keep daily checks for 14 days', () {
    for (final stage in [SettlementStage.failed, SettlementStage.notFunded]) {
      test(stage.name, () {
        final entered = _t0.add(const Duration(days: 1));
        final day3 = entered.add(const Duration(days: 3));
        final state = _state(stage,
            stageEnteredAt: entered,
            lastCheckedAt: day3.subtract(const Duration(hours: 23)));
        expect(_plan(state, now: day3).readStatus, isFalse);
        expect(_plan(state, now: day3.add(const Duration(hours: 1))).readStatus,
            isTrue);
        final day15 = entered.add(const Duration(days: 15));
        final old = _state(stage,
            stageEnteredAt: entered,
            lastCheckedAt: day15.subtract(const Duration(days: 2)));
        expect(_plan(old, now: day15).readStatus, isFalse);
        final result = _apply(
            _state(stage, stageEnteredAt: entered), _status(_notFound),
            now: day3);
        expect(result.nextCheckAt, day3.add(const Duration(days: 1)));
      });
    }

    test('failed moves on to a refund', () {
      final result = _apply(
          _state(SettlementStage.failed), _status(_order, 'refunding'),
          now: _t0.add(const Duration(days: 2)));
      expect(result.stage, SettlementStage.refunding);
    });

    test('a late provider detection moves notFunded to funded or late', () {
      final now = _t0.add(const Duration(days: 2));
      expect(
          _apply(_state(SettlementStage.notFunded),
                  _status(_order, 'processing'),
                  now: now)
              .stage,
          SettlementStage.funded);
      expect(
          _apply(_state(SettlementStage.notFunded),
                  _status(_order, 'unfulfilled'),
                  now: now)
              .stage,
          SettlementStage.lateDeposit);
    });
  });

  group('duplicate and out-of-order responses', () {
    final now = _t0.add(const Duration(hours: 2));

    for (final terminal in [
      SettlementStage.settled,
      SettlementStage.refunded
    ]) {
      for (final status in [
        'processing',
        'refunding',
        'awaiting_deposit',
        'unfulfilled',
        'failed',
        'completed',
        'refunded'
      ]) {
        test('$status after ${terminal.name} is ignored', () {
          final result =
              _apply(_state(terminal), _status(_order, status), now: now);
          expect(result.stage, terminal);
          expect(result.nextCheckAt, isNull);
        });
      }
    }

    test('processing after refunding is ignored and reported', () {
      final result = _apply(
          _state(SettlementStage.refunding), _status(_order, 'processing'),
          now: now);
      expect(result.stage, SettlementStage.refunding);
      expect(result.ignoredProviderStatus, 'processing');
      expect(result.signals,
          contains(SettlementReconcileSignal.regressionIgnored));
    });

    test('the same response twice gives the same stage', () {
      final first = _apply(
          _state(SettlementStage.submitted), _status(_order, 'processing'),
          now: now);
      final second =
          _apply(_state(first.stage), _status(_order, 'processing'), now: now);
      expect(first.stage, SettlementStage.processing);
      expect(second.stage, SettlementStage.processing);
      expect(second.stageChanged, isFalse);
    });

    test('a waiting status after processing is ignored', () {
      expect(
          _apply(_state(SettlementStage.processing),
                  _status(_order, 'awaiting_deposit'),
                  now: now)
              .stage,
          SettlementStage.processing);
    });

    test('terminal stages plan no I/O', () {
      for (final stage in [
        SettlementStage.settled,
        SettlementStage.refunded,
        SettlementStage.abandoned,
      ]) {
        expect(_plan(_state(stage), now: now).isIdle, isTrue);
      }
    });
  });

  group('late flag', () {
    test('funded after the skew-corrected expiry is late', () {
      final result = _apply(
        _state(SettlementStage.broadcasting,
            broadcastingAt: _expiresAt.subtract(const Duration(seconds: 30)),
            skew: const Duration(seconds: 60)),
        _status(_order, 'processing'),
        now: _expiresAt.add(const Duration(minutes: 1)),
      );
      expect(result.quoteExpiredBeforeFunding, isTrue);
    });

    test('funded before the skew-corrected expiry is not late', () {
      final result = _apply(
        _state(SettlementStage.broadcasting,
            broadcastingAt: _expiresAt.add(const Duration(seconds: 30)),
            skew: const Duration(seconds: -60)),
        _status(_order, 'processing'),
        now: _expiresAt.add(const Duration(minutes: 1)),
      );
      expect(result.quoteExpiredBeforeFunding, isFalse);
    });
  });

  group('cadence', () {
    test('the settlement ladder', () {
      Duration? at(Duration d) => kSettlementStatusCadence.intervalFor(d);
      expect(at(const Duration(minutes: 59)), const Duration(minutes: 1));
      expect(at(const Duration(hours: 23, minutes: 59)),
          const Duration(minutes: 10));
      expect(at(const Duration(days: 13)), const Duration(hours: 1));
      expect(at(const Duration(days: 59)), const Duration(days: 1));
      expect(at(const Duration(days: 61)), isNull);
    });

    test('past 60 days a check runs only after a foreground', () {
      final now = _broadcastAt.add(const Duration(days: 61));
      final foregrounded = now.subtract(const Duration(minutes: 5));
      final checkedBefore = _state(SettlementStage.lateDeposit,
          lastCheckedAt: now.subtract(const Duration(days: 10)));
      expect(
          _plan(checkedBefore, now: now, foregroundedAt: foregrounded)
              .readStatus,
          isTrue);
      final checkedAfter = _state(SettlementStage.lateDeposit,
          lastCheckedAt: now.subtract(const Duration(minutes: 1)));
      expect(_plan(checkedAfter, now: now, foregroundedAt: foregrounded).isIdle,
          isTrue);
    });

    test('an open sheet checks every 5 s', () {
      final last = _broadcastAt.add(const Duration(hours: 3));
      final state = _state(SettlementStage.processing, lastCheckedAt: last);
      final now = last.add(const Duration(seconds: 5));
      expect(_plan(state, now: now, visible: true).readStatus, isTrue);
      expect(_plan(state, now: now).readStatus, isFalse);
    });

    test('the Cash App ladder is unchanged', () {
      expect(
          kCashAppClosedWindowCadence.intervalFor(const Duration(minutes: 1)),
          Duration.zero);
      expect(cashAppClosedWindowPollInterval(const Duration(minutes: 30)),
          const Duration(minutes: 1));
      expect(cashAppClosedWindowPollInterval(const Duration(days: 13)),
          const Duration(hours: 1));
      expect(cashAppClosedWindowPollInterval(const Duration(days: 15)), isNull);
    });
  });
}
