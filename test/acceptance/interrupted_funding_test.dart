import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/orchestra_legacy_status_rules.dart'
    show OrchestraStatusReadKind;
import 'package:kute/services/funding/settlement_reconciler.dart';
import 'package:kute/services/funding/settlement_stage.dart';

final _t0 = DateTime.utc(2026, 9, 1, 12);
final _expiresAt = _t0.add(const Duration(minutes: 2));
final _broadcastAt = _t0.add(const Duration(minutes: 1));

/// Records the I/O a relaunch performs. The ports have no call that moves
/// funds, so a relaunch can only read, look up and register.
class _RelaunchPorts implements SettlementReconcilePorts {
  OrchestraStatusReadKind status = OrchestraStatusReadKind.unavailable;
  String? providerStatus;
  int? candidates;
  BitcoinFundingProbe bitcoin = BitcoinFundingProbe.unavailable;
  SubmitAttemptOutcome submitOutcome = SubmitAttemptOutcome.accepted;
  final calls = <String>[];

  @override
  Future<({OrchestraStatusReadKind kind, String? providerStatus})>
      readStatus() async {
    calls.add('status');
    return (kind: status, providerStatus: providerStatus);
  }

  @override
  Future<SparkCandidateLookup?> findSparkCandidates() async {
    calls.add('sdk');
    final count = candidates;
    return count == null
        ? null
        : (count: count, matchedPaymentId: null, syncGeneration: calls.length);
  }

  @override
  Future<BitcoinFundingProbe> probeBitcoin() async {
    calls.add('bitcoin');
    return bitcoin;
  }

  @override
  Future<FundingSourceProbe> probeFundingSource() async {
    calls.add('source');
    return FundingSourceProbe.unavailable;
  }

  @override
  Future<SubmitAttemptOutcome> submitDeposit() async {
    calls.add('submit');
    return submitOutcome;
  }
}

SettlementReconcileState _killedAt(
  SettlementStage stage, {
  SettlementFundingKind kind = SettlementFundingKind.spark,
  int submitAttempts = 0,
  bool submitAccepted = false,
}) {
  final broadcast = !stage.isBeforeBroadcasting;
  return SettlementReconcileState(
    stage: stage,
    createdAt: _t0,
    everBroadcast: broadcast,
    fundingKind: kind,
    hasFundingProof: broadcast &&
        stage != SettlementStage.broadcasting &&
        stage != SettlementStage.fundingUnknown,
    quoteExpiresAt: _expiresAt,
    broadcastingAt: broadcast ? _broadcastAt : null,
    fundedAt: broadcast && stage != SettlementStage.broadcasting
        ? _broadcastAt
        : null,
    submitAttempts: submitAttempts,
    submitAccepted: submitAccepted,
  );
}

Future<SettlementReconcileResult?> _relaunch(
  SettlementReconcileState state,
  _RelaunchPorts ports, {
  required DateTime now,
  bool unlocked = true,
}) =>
    runSettlementReconcileCycle(state, ports,
        now: () => now, sessionUnlocked: unlocked, foregroundedAt: now);

void main() {
  for (final stage in [SettlementStage.quoted, SettlementStage.authorizing]) {
    test('P5-X12 kill at ${stage.name}: nothing moves, abandoned after expiry',
        () async {
      final ports = _RelaunchPorts();
      final early = await _relaunch(_killedAt(stage), ports,
          now: _t0.add(const Duration(seconds: 30)));
      expect(early, isNull);
      final late = await _relaunch(_killedAt(stage), ports,
          now: _expiresAt.add(const Duration(seconds: 1)));
      expect(late!.stage, SettlementStage.abandoned);
      expect(ports.calls, isEmpty);
    });
  }

  test(
      'P5-X12 kill at signed: no rebroadcast, watched until 30 min after '
      'expiry, then abandoned when unseen', () async {
    final ports = _RelaunchPorts()..bitcoin = BitcoinFundingProbe.noSignal;
    final state =
        _killedAt(SettlementStage.signed, kind: SettlementFundingKind.bitcoin);
    final watched = await _relaunch(state, ports,
        now: _expiresAt.add(const Duration(minutes: 1)));
    expect(watched!.stage, SettlementStage.signed);
    expect(ports.calls, ['bitcoin']);

    ports.bitcoin = BitcoinFundingProbe.txidSeen;
    final seenLate = await _relaunch(state, ports,
        now: _expiresAt.add(const Duration(minutes: 20)));
    expect(seenLate!.stage, SettlementStage.funded);

    ports.bitcoin = BitcoinFundingProbe.noSignal;
    final ended = await _relaunch(state, ports,
        now: _expiresAt.add(const Duration(minutes: 31)));
    expect(ended!.stage, SettlementStage.abandoned);
    expect(ports.calls, ['bitcoin', 'bitcoin', 'bitcoin']);
  });

  test('P5-X12 kill after broadcast before proof', () async {
    final ports = _RelaunchPorts();
    final state = _killedAt(SettlementStage.broadcasting);

    final offline = await _relaunch(state, ports,
        now: _expiresAt.add(const Duration(minutes: 5)), unlocked: false);
    expect(offline!.stage, SettlementStage.broadcasting);
    expect(offline.consecutiveFailures, 1);
    expect(ports.calls, ['status']);

    ports
      ..calls.clear()
      ..status = OrchestraStatusReadKind.order
      ..providerStatus = 'processing';
    final online = await _relaunch(state, ports,
        now: _expiresAt.add(const Duration(minutes: 6)));
    expect(online!.stage, SettlementStage.funded);
    expect(online.providerDetected, isTrue);
    expect(ports.calls, isNot(contains('submit')));
  });

  test('P5-X12 kill after funding before registration retries the submit',
      () async {
    final ports = _RelaunchPorts()
      ..status = OrchestraStatusReadKind.notFound
      ..submitOutcome = SubmitAttemptOutcome.transient;
    final state = _killedAt(SettlementStage.funded);
    final first = await _relaunch(state, ports,
        now: _broadcastAt.add(const Duration(minutes: 1)));
    expect(first!.stage, SettlementStage.funded);
    expect(first.rotateSubmitKey, isFalse);
    expect(ports.calls, ['status', 'submit']);
  });

  test('P5-X12 kill after registration never submits again', () async {
    final ports = _RelaunchPorts()..status = OrchestraStatusReadKind.notFound;
    final state = _killedAt(SettlementStage.submitted,
        submitAttempts: 1, submitAccepted: true);
    for (final age in const [
      Duration(minutes: 1),
      Duration(hours: 3),
      Duration(days: 2),
    ]) {
      await _relaunch(state, ports, now: _broadcastAt.add(age));
    }
    expect(ports.calls, isNot(contains('submit')));
  });

}
