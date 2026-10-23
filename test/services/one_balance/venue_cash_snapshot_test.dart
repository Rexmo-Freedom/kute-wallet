import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider;
import 'package:kute/services/one_balance/investments_spendable.dart';
import 'package:kute/services/one_balance/multi_source_move.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/route_minimums.dart';
import 'package:kute/services/one_balance/venue_cash_source.dart';
import 'package:kute/services/one_balance/venue_funder.dart';

const _venue = OneBalanceVenue.investing;

VenueCashCandidate _candidate(double usd) => (
      venue: _venue,
      availableUsd: usd,
      eta: kVenuePullEta[_venue]!,
      minimumUsd: 1,
    );

VenueCashLegOutcome _sent(String id, double usd) => VenueCashLegOutcome(
    pull: VenueCashPull(
        venue: _venue, usd: usd, arrivingUsd: usd, eta: kVenuePullEta[_venue]!),
    result: VenueMoveResult(
        quoteId: id, operationId: id, sentUsd: usd, arrivingUsdEstimate: usd));

class _Settings extends SettingsModel {
  _Settings()
      : super(Settings(
            currency: 'USD',
            language: 'en',
            btcFormat: 'sats',
            backup: false,
            biometricsEnabled: false,
            bitcoinElectrumNode: '',
            nodeType: '',
            reviewDone: true,
            wallets: [WalletConfig(id: 'a', name: 'A')]));

  void wallet(String id) =>
      state = state.copyWith(wallets: [WalletConfig(id: id, name: id)]);
}

class _Source implements VenueCashSource {
  double usd = 100;
  Object? sendError;
  Future<double> Function()? read;
  int reads = 0;
  int sends = 0;

  @override
  OneBalanceVenue get venue => _venue;
  @override
  Duration get estimatedArrival => kVenuePullEta[_venue]!;
  @override
  Future<double> availableUsd() async {
    reads++;
    return read == null ? usd : await read!();
  }

  @override
  Future<VenueMoveResult> pull(double usd, {required String purpose}) async {
    if (sendError case final e?) throw e;
    // Deliberately retain the old API balance, as on the failing device.
    return VenueMoveResult(
        quoteId: 'own-send-${++sends}',
        sentUsd: usd,
        arrivingUsdEstimate: usd * 0.99);
  }
}

void main() {
  late ProviderContainer container;
  late _Source source;
  late _Settings settings;

  setUp(() {
    MultiSourceMoveStore.reset();
    source = _Source();
    settings = _Settings();
    container = ProviderContainer(overrides: [
      settingsProvider.overrideWith((_) => settings),
      usdBalanceProvider.overrideWithValue(0),
      venueCashSourcesProvider.overrideWithValue([source]),
      routeMinimumsProvider
          .overrideWithValue(RouteMinimums(fetch: (_) async => null)),
    ]);
    container.read(venueCashLastReadProvider.notifier).state =
        (walletId: 'a', candidates: [_candidate(100)]);
  });
  tearDown(() => container.dispose());

  double cash() => container
      .read(venueCashLastReadProvider)!
      .candidates
      .singleWhere((s) => s.venue == _venue)
      .availableUsd;
  VenueCashSnapshot scope() => container.read(venueCashSnapshotProvider);

  test('successful source pull debits app snapshot before destination arrival',
      () async {
    final result = await container.read(venueCashPullerProvider).pullShortfall(
        neededUsd: 20, forAction: VenueCashFor.send, waitFor: Duration.zero);
    expect(result.anyPulled, isTrue);
    expect(cash(), closeTo(100 - result.pulledUsd, 1e-6));
    final spendable = container.read(
        investmentsSpendableExcludingProvider(OneBalanceVenue.predictions));
    expect(spendable.venueCashUsd, cash());
    await scope().refresh(container.read);
    expect(cash(), closeTo(100 - result.pulledUsd, 1e-6),
        reason: 'a stale source read cannot restore moved cash');
  });

  test('duplicate callback and already-debited live read do not debit twice',
      () {
    final snapshot = scope();
    final first = _sent('first', 20);
    snapshot.cashMoved(first, 100);
    snapshot.cashMoved(first, 100);
    expect(cash(), 80);
    // Another read has already seen the next native send before its callback.
    container.read(venueCashLastReadProvider.notifier).state =
        (walletId: 'a', candidates: [_candidate(70)]);
    snapshot.cashMoved(_sent('second', 10), 80);
    expect(cash(), 70);
    snapshot.cashMoved(_sent('third', 5), 80); // raw API still stale
    expect(cash(), 65);
  });

  test(
      'new send uses lower published pre-send cash after earlier reconciliation',
      () async {
    final snapshot = scope();
    snapshot.cashMoved(_sent('first', 20), 100);
    source.usd = 80;
    await snapshot.refresh(container.read, settledRefs: {'first'});
    source.usd = 100; // endpoint rebound after that reconciliation
    final result = await container.read(venueCashPullerProvider).pullShortfall(
        neededUsd: 10, forAction: VenueCashFor.send, waitFor: Duration.zero);
    expect(cash(), closeTo(80 - result.pulledUsd, 1e-6));
  });

  test('old in-flight read is dropped; source ceiling survives stale rebound',
      () async {
    final snapshot = scope();
    final old = Completer<double>();
    source.read = () => old.future;
    final refreshing = snapshot.refresh(container.read);
    await pumpEventQueue();
    snapshot.cashMoved(_sent('first', 20), 100);
    old.complete(100);
    await refreshing;
    expect(cash(), 80);
    source.read = null;
    source.usd = 80;
    await snapshot.refresh(container.read);
    source.usd = 100;
    await snapshot.refresh(container.read);
    expect(cash(), 80,
        reason: 'one lower read never discards the pending debit');

    // The own leg is now proven settled. A read requested after that proof
    // may include a refund or a legitimate new deposit, so no permanent cap.
    source.usd = 110;
    await refreshVenueCashAfterMove(container.read,
        walletId: 'a', scope: snapshot, settledRefs: {'first'});
    expect(cash(), 110);
  });

  test('failed or unknown source send does not invent a debit', () async {
    for (final error in [StateError('not sent'), TimeoutException('unknown')]) {
      source.sendError = error;
      final result = await container
          .read(venueCashPullerProvider)
          .pullShortfall(
              neededUsd: 20,
              forAction: VenueCashFor.send,
              waitFor: Duration.zero);
      expect(result.anyPulled, isFalse);
      expect(cash(), 100);
    }
  });

  test('wallet switch and switch-back discard old callbacks and reads',
      () async {
    final oldScope = scope();
    final oldRead = Completer<double>();
    source.read = () => oldRead.future;
    final refreshing = oldScope.refresh(container.read);
    await pumpEventQueue();
    settings.wallet('b');
    settings.wallet('a');
    final current = scope();
    expect(identical(current, oldScope), isFalse);
    container.read(venueCashLastReadProvider.notifier).state =
        (walletId: 'a', candidates: [_candidate(200)]);
    oldScope.cashMoved(_sent('old-send', 20), 100);
    oldRead.complete(100);
    await refreshing;
    expect(cash(), 200);
    final reads = source.reads;
    await refreshVenueCashAfterMove(container.read,
        walletId: 'a', scope: oldScope, settledRefs: {'old-send'});
    expect(source.reads, reads);
    expect(cash(), 200);
  });

  test(
      'terminal refresh failure retains debit; later requested read reconciles',
      () async {
    final snapshot = scope();
    snapshot.cashMoved(_sent('first', 20), 100);
    source.read = () async => throw StateError('offline');
    await refreshVenueCashAfterMove(container.read,
        walletId: 'a', scope: snapshot, settledRefs: {'first'});
    expect(cash(), 80);
    source.read = null;
    source.usd = 120;
    await snapshot.refresh(container.read);
    expect(cash(), 120, reason: 'proved refund/deposit is not held forever');
  });

  test('one terminal operation cannot release another send at the same venue',
      () async {
    final snapshot = scope();
    snapshot.cashMoved(_sent('first', 20), 100);
    snapshot.cashMoved(_sent('second', 10), 100);
    expect(cash(), 70);
    source.usd = 100; // old endpoint state, neither debit visible yet
    await snapshot.refresh(container.read, settledRefs: {'first'});
    expect(cash(), 70);
    await snapshot.refresh(container.read, settledRefs: {'unrelated'});
    expect(cash(), 70);
    source.usd = 120; // own second move settled; includes new deposit/refund
    await snapshot.refresh(container.read, settledRefs: {'second'});
    expect(cash(), 120);
  });

  test('snapshot listener failure never changes an accepted source send',
      () async {
    final puller = VenueCashPuller(
        sources: [source],
        readDollars: () => 0,
        minimumUsd: (_) async => 1,
        onCashMoved: (_, __) => throw StateError('cache unavailable'));
    final result = await puller.pullShortfall(
        neededUsd: 20, forAction: VenueCashFor.send, waitFor: Duration.zero);
    expect(result.anyPulled, isTrue);
    expect(result.failedLegs, isEmpty);
  });
}
