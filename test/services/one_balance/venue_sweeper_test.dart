// The sweeper's state machine against a fake host and a fake clock: what
// moves, what waits, what backs off, and what each pass reports.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/orchestra_route_limits.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/sweep_rules.dart';
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/one_balance/venue_sweeper.dart';

class _Sent {
  _Sent(this.venue, this.usd, this.purpose);

  final OneBalanceVenue venue;
  final double usd;
  final String purpose;
}

class _FakeHost extends VenueSweeperHost {
  DateTime clock = DateTime(2026, 10, 12, 12);
  bool unlocked = true;
  String? wallet = 'spend';
  final Map<OneBalanceVenue, VenueSnapshot?> venues = {
    OneBalanceVenue.predictions:
        const VenueSnapshot(idleUsd: 0, sweepableUsd: 0),
    OneBalanceVenue.investing: const VenueSnapshot(idleUsd: 0, sweepableUsd: 0),
  };
  final Map<OneBalanceVenue, double> minimums = {
    OneBalanceVenue.predictions: 1,
    OneBalanceVenue.investing: 1,
  };
  final Map<OneBalanceVenue, Object Function()?> sendError = {};
  final List<_Sent> sent = [];
  final List<OneBalanceVenue> prepared = [];
  final List<(OneBalanceVenue, double)> tooSmall = [];
  final List<(String, Map<String, Object>)> events = [];
  final Set<String> rolloutFlags = {};
  final Set<String> claimed = {};
  int nextOrder = 1;
  bool registerLate = false;

  /// What the rail reports as sent for an ask of `usd` (default: all of
  /// it). The CCTP fallback keeps a HyperCore reserve back.
  double Function(double usd)? sendResult;
  Future<void> Function()? beforeSend;

  /// Runs as [send] starts for a venue, before [beforeSend].
  Future<void> Function(OneBalanceVenue venue)? beforeSendTo;
  Future<void> Function()? onPrepare;

  void idle(OneBalanceVenue venue, double usd, {double? sweepable}) {
    venues[venue] = VenueSnapshot(idleUsd: usd, sweepableUsd: sweepable ?? usd);
  }

  Iterable<String> eventsNamed(String name) =>
      events.where((e) => e.$1 == name).map((e) => e.$1);

  Map<String, Object> lastEvent(String name) =>
      events.lastWhere((e) => e.$1 == name).$2;

  @override
  DateTime now() => clock;

  @override
  bool get sessionUnlocked => unlocked;

  @override
  String? get spendingWalletId => wallet;

  @override
  Future<VenueSnapshot?> readVenue(OneBalanceVenue venue) async =>
      venues[venue];

  @override
  Future<double> minimumUsd(OneBalanceVenue venue) async => minimums[venue]!;

  /// The session's cached minimums for the preview, when a test sets one.
  final Map<OneBalanceVenue, double> previewMinimums = {};

  @override
  Future<double> previewMinimumUsd(OneBalanceVenue venue) async =>
      previewMinimums[venue] ?? minimums[venue]!;

  @override
  void noteAmountTooSmall(OneBalanceVenue venue, double usd) =>
      tooSmall.add((venue, usd));

  @override
  Future<void> prepare(OneBalanceVenue venue) async {
    prepared.add(venue);
    await onPrepare?.call();
  }

  @override
  Future<VenueMoveResult> send(OneBalanceVenue venue,
      {required double usd, required String purpose}) async {
    await beforeSendTo?.call(venue);
    await beforeSend?.call();
    final error = sendError[venue];
    if (error != null) throw error();
    final sentUsd = sendResult?.call(usd) ?? usd;
    sent.add(_Sent(venue, usd, purpose));
    final id = 'ord_${nextOrder++}';
    // The venue has not caught up yet: its idle figure still shows it.
    return VenueMoveResult(
      quoteId: 'quote_$id',
      orderId: registerLate ? null : id,
      registration: registerLate ? Future.value(id) : null,
      sentUsd: sentUsd,
      arrivingUsdEstimate: sentUsd * 0.999,
    );
  }

  @override
  bool rolloutDone(String walletId) => rolloutFlags.contains(walletId);

  @override
  void markRolloutDone(String walletId) => rolloutFlags.add(walletId);

  @override
  bool claimTerminal(String orderId, {required bool success}) =>
      claimed.add('$orderId:$success');

  @override
  void track(String event, Map<String, Object> params) =>
      events.add((event, params));
}

SwapOrder _orderRow(String id, String status) => SwapOrder(
      id: id,
      coinFrom: 'USDC.e',
      networkFrom: 'POLYGON',
      coinTo: 'USDB',
      networkTo: 'SPARK',
      depositAddress: 'd',
      depositAmount: '10',
      withdrawalAmount: '9.9',
      status: status,
      timestamp: DateTime(2026, 10, 12, 12).millisecondsSinceEpoch,
      withdrawalAddress: 'r',
      depositMin: '0',
      depositMax: '0',
      rate: '0',
      refundAddress: 'f',
      provider: 'Orchestra',
    );

void main() {
  late _FakeHost host;
  late VenueSweeper sweeper;
  final states = <VenueSweeperState>[];

  setUp(() {
    host = _FakeHost()..rolloutFlags.add('spend');
    states.clear();
    sweeper = VenueSweeper(host, onState: states.add);
  });

  test('a close sweeps the venue at once and reports each stage', () async {
    host.idle(OneBalanceVenue.predictions, 12);
    await sweeper.trigger('position_closed',
        venue: OneBalanceVenue.predictions);
    expect(host.sent.single.venue, OneBalanceVenue.predictions);
    expect(host.sent.single.usd, 12);
    expect(host.sent.single.purpose, 'sweep');
    expect(host.prepared, [OneBalanceVenue.predictions]);
    final started = host.lastEvent('venue_sweep_started');
    expect(started['trigger'], 'close');
    expect(started['amount_usd'], 12);
    expect(started['idle_usd'], 12);
    expect(started['wallet_kind'], 'hot');
    final submitted = host.lastEvent('venue_sweep_submitted');
    expect(submitted['amount_usd'], 12);
    expect(submitted['quote_id'], startsWith('ref_'));
    expect(host.events.map((e) => e.$1), isNot(contains('venue_sweep_failed')));
    // Sweeping showed while the send ran, then cleared.
    expect(states.any((s) => s.sweeping.contains(OneBalanceVenue.predictions)),
        isTrue);
    expect(sweeper.state.sweeping, isEmpty);
    // The venue still reports the cash until it catches up: not waiting.
    expect(sweeper.state.waiting, isEmpty);
  });

  test('the order reaching success completes the sweep once', () async {
    host.idle(OneBalanceVenue.predictions, 12);
    await sweeper.trigger('position_closed',
        venue: OneBalanceVenue.predictions);
    host.clock = host.clock.add(const Duration(seconds: 40));
    sweeper.noteOrders([_orderRow('ord_1', 'exchanging')]);
    expect(host.eventsNamed('venue_sweep_completed'), isEmpty);
    sweeper.noteOrders([_orderRow('ord_1', 'success')]);
    sweeper.noteOrders([_orderRow('ord_1', 'success')]);
    expect(host.eventsNamed('venue_sweep_completed').length, 1);
    final done = host.lastEvent('venue_sweep_completed');
    expect(done['duration_ms'], 40000);
    expect(done['trigger'], 'close');
    expect(done['amount_usd'], 12);
    expect(sweeper.openSweepCount, 0);
  });

  test('a late registration is still watched to completion', () async {
    host.registerLate = true;
    host.idle(OneBalanceVenue.investing, 30);
    await sweeper.trigger('position_closed', venue: OneBalanceVenue.investing);
    expect(sweeper.openSweepCount, 1);
    sweeper.noteOrders([_orderRow('ord_1', 'failed')]);
    final failed = host.lastEvent('venue_sweep_failed');
    expect(failed['stage'], 'settle');
    expect(failed['error_category'], 'failed');
  });

  test('a pending deposit, an intent or a claim leave the venue alone',
      () async {
    host.venues[OneBalanceVenue.predictions] = const VenueSnapshot(
        idleUsd: 12, sweepableUsd: 12, hasPendingMove: true);
    await sweeper.trigger('resume');
    expect(host.sent, isEmpty);
    expect(host.lastEvent('venue_sweep_skipped')['reason'], 'pending_deposit');
    // Same reason again: no second event.
    await sweeper.trigger('resume');
    expect(host.eventsNamed('venue_sweep_skipped').length, 1);

    host.venues[OneBalanceVenue.predictions] = const VenueSnapshot(
        idleUsd: 12, sweepableUsd: 12, hasPendingIntent: true);
    await sweeper.trigger('resume');
    expect(host.lastEvent('venue_sweep_skipped')['reason'], 'open_orders');

    host.venues[OneBalanceVenue.predictions] =
        const VenueSnapshot(idleUsd: 12, sweepableUsd: 12, isClaiming: true);
    await sweeper.trigger('resume');
    expect(host.lastEvent('venue_sweep_skipped')['reason'], 'claiming');
    expect(host.sent, isEmpty);
    expect(sweeper.state.waiting, isEmpty);
  });

  test('grace after a settled deposit, then the sweep', () async {
    host.venues[OneBalanceVenue.predictions] = VenueSnapshot(
        idleUsd: 12,
        sweepableUsd: 12,
        lastDepositSettledAt: host.clock.subtract(const Duration(seconds: 10)));
    await sweeper.trigger('resume');
    expect(host.sent, isEmpty);
    expect(host.lastEvent('venue_sweep_skipped')['reason'], 'grace');
    host.clock = host.clock.add(const Duration(seconds: 90));
    await sweeper.trigger('timer');
    expect(host.sent.length, 1);
  });

  test('Investing sweeps only what the rail says is withdrawable', () async {
    host.venues[OneBalanceVenue.investing] = const VenueSnapshot(
        idleUsd: 40, sweepableUsd: 25, hasReservations: true);
    await sweeper.trigger('position_closed', venue: OneBalanceVenue.investing);
    expect(host.prepared, [OneBalanceVenue.investing]);
    expect(host.sent.single.usd, 25);
  });

  test('below the minimum is dust: never waiting, never sent, reported once',
      () async {
    host.minimums[OneBalanceVenue.predictions] = 1;
    host.idle(OneBalanceVenue.predictions, 0.6);
    await sweeper.trigger('market_resolved',
        venue: OneBalanceVenue.predictions);
    expect(host.sent, isEmpty);
    expect(sweeper.state.waiting, isEmpty);
    expect(sweeper.state.dust, {OneBalanceVenue.predictions: 0.6});
    expect(host.lastEvent('venue_sweep_skipped')['reason'], 'below_minimum');
    // Nothing scheduled for it, nothing sent on later passes, one report.
    expect(sweeper.nextDueIn(), isNull);
    await sweeper.trigger('timer');
    await sweeper.trigger('resume');
    expect(host.sent, isEmpty);
    expect(host.eventsNamed('venue_sweep_skipped').length, 1);
    expect(host.eventsNamed('venue_sweep_failed'), isEmpty);
    expect(host.eventsNamed('venue_cash_waiting_shown'), isEmpty);
    // More cash: crosses the minimum and the \$5 batch size.
    host.idle(OneBalanceVenue.predictions, 6);
    await sweeper.trigger('market_resolved',
        venue: OneBalanceVenue.predictions);
    expect(host.sent.single.usd, 6);
    expect(sweeper.state.waiting, isEmpty);
    expect(sweeper.state.dust, isEmpty);
    // A new episode reports again.
    host.idle(OneBalanceVenue.predictions, 0.3);
    host.clock = host.clock.add(const Duration(minutes: 3));
    await sweeper.trigger('timer');
    expect(sweeper.state.dust, {OneBalanceVenue.predictions: 0.3});
    expect(host.eventsNamed('venue_sweep_skipped').length, 2);
  });

  test('Investing dust (the CCTP reserve left behind) is never waiting',
      () async {
    host.idle(OneBalanceVenue.investing, 6.28);
    await sweeper.trigger('position_closed', venue: OneBalanceVenue.investing);
    expect(host.sent.single.usd, 6.28);
    // The move kept the HyperCore reserve back: what the venue reads next
    // is six cents, below every minimum.
    host.idle(OneBalanceVenue.investing, 0.06);
    host.clock = host.clock.add(const Duration(minutes: 3));
    await sweeper.trigger('timer');
    expect(sweeper.state.waiting, isEmpty);
    expect(sweeper.state.dust, {OneBalanceVenue.investing: 0.06});
    expect(host.sent, hasLength(1));
    expect(sweeper.nextDueIn(), isNull);
  });

  test('what a sweep leaves below the minimum is dust at once', () async {
    host.idle(OneBalanceVenue.investing, 6.28);
    host.sendResult = (usd) => usd - 0.06;
    await sweeper.trigger('position_closed', venue: OneBalanceVenue.investing);
    expect(sweeper.state.waiting, isEmpty);
    expect(sweeper.state.dust[OneBalanceVenue.investing], closeTo(0.06, 1e-9));
  });

  test('dust is not shown while the venue backs off', () async {
    host.idle(OneBalanceVenue.predictions, 20);
    host.sendError[OneBalanceVenue.predictions] = () => StateError('boom');
    await sweeper.trigger('position_closed',
        venue: OneBalanceVenue.predictions);
    expect(sweeper.state.waiting, {OneBalanceVenue.predictions: 20});
    // Most of it left another way; the cents left are dust, not waiting.
    host.idle(OneBalanceVenue.predictions, 0.4);
    await sweeper.trigger('timer');
    expect(sweeper.state.waiting, isEmpty);
    expect(sweeper.state.dust, {OneBalanceVenue.predictions: 0.4});
  });

  test('the CCTP floor refusing the amount is dust, with no backoff', () async {
    host.idle(OneBalanceVenue.investing, 1.02);
    host.sendError[OneBalanceVenue.investing] =
        () => const RouteUnavailable('cctp_below_minimum');
    // Leaving the foreground flushes the held batch into a send.
    await sweeper.onAppPaused();
    expect(host.tooSmall, [(OneBalanceVenue.investing, 1.02)]);
    expect(sweeper.state.waiting, isEmpty);
    expect(sweeper.state.dust, {OneBalanceVenue.investing: 1.02});
    expect(sweeper.nextDueIn(), isNull);
    expect(host.lastEvent('venue_sweep_failed')['error_category'],
        'amount_too_small');
    // The raised minimum keeps the next passes from trying again.
    host.minimums[OneBalanceVenue.investing] = 1.03;
    await sweeper.trigger('timer');
    await sweeper.trigger('resume');
    expect(host.sent, isEmpty);
    expect(host.eventsNamed('venue_sweep_failed').length, 1);
  });

  test('between the minimum and \$5 the cash waits, then goes after 10 min',
      () async {
    host.idle(OneBalanceVenue.predictions, 3);
    await sweeper.trigger('order_cancelled',
        venue: OneBalanceVenue.predictions);
    expect(host.sent, isEmpty);
    expect(sweeper.state.waiting, {OneBalanceVenue.predictions: 3});
    expect(host.eventsNamed('venue_cash_waiting_shown'), isEmpty);
    expect(sweeper.nextDueIn(), const Duration(minutes: 10));
    expect(sweeper.nextDueIsRetry(), isFalse);
    host.clock = host.clock.add(const Duration(minutes: 10));
    await sweeper.trigger('timer');
    expect(host.sent.single.usd, 3);
    expect(host.lastEvent('venue_sweep_started')['trigger'], 'timer');
  });

  test('leaving the foreground flushes a held batch', () async {
    host.idle(OneBalanceVenue.investing, 2);
    await sweeper.trigger('timer');
    expect(host.sent, isEmpty);
    await sweeper.onAppPaused();
    expect(host.sent.single.usd, 2);
  });

  test('one sweep per venue per 10 minutes unless an event asks', () async {
    host.idle(OneBalanceVenue.predictions, 20);
    await sweeper.trigger('timer');
    expect(host.sent.length, 1);
    // The venue has not caught up: the discount hides the swept amount.
    await sweeper.trigger('timer');
    expect(host.sent.length, 1);
    host.idle(OneBalanceVenue.predictions, 40);
    host.clock = host.clock.add(const Duration(minutes: 3));
    await sweeper.trigger('timer');
    expect(host.sent.length, 1, reason: 'rate-limited heartbeat');
    expect(sweeper.state.waiting[OneBalanceVenue.predictions], 40);
    await sweeper.trigger('position_closed',
        venue: OneBalanceVenue.predictions);
    expect(host.sent.length, 2, reason: 'event-driven');
    expect(host.sent.last.usd, 40);
  });

  test('a failed send backs off 2 → 30 min and reports once per episode',
      () async {
    host.idle(OneBalanceVenue.investing, 50);
    host.sendError[OneBalanceVenue.investing] = () => StateError('boom');
    await sweeper.trigger('position_closed', venue: OneBalanceVenue.investing);
    expect(host.lastEvent('venue_sweep_failed')['stage'], 'fund');
    expect(sweeper.state.waiting, {OneBalanceVenue.investing: 50});
    expect(sweeper.nextDueIn(), const Duration(minutes: 2));
    expect(sweeper.nextDueIsRetry(), isTrue);
    // Inside the backoff: skipped, cash still visible.
    await sweeper.trigger('position_closed', venue: OneBalanceVenue.investing);
    expect(host.lastEvent('venue_sweep_skipped')['reason'], 'backoff');
    expect(sweeper.state.waiting, {OneBalanceVenue.investing: 50});
    var expected = const Duration(minutes: 2);
    for (var i = 0; i < 6; i++) {
      host.clock = host.clock.add(expected);
      await sweeper.trigger('retry');
      expected = expected * 2 > const Duration(minutes: 30)
          ? const Duration(minutes: 30)
          : expected * 2;
      expect(sweeper.nextDueIn(), expected);
    }
    expect(host.eventsNamed('venue_sweep_failed').length, 1);
    // The rail recovers: the retry sweeps and resets the ladder.
    host.sendError.remove(OneBalanceVenue.investing);
    host.clock = host.clock.add(const Duration(minutes: 30));
    await sweeper.trigger('retry');
    expect(host.sent.single.usd, 50);
    expect(host.lastEvent('venue_sweep_started')['trigger'], 'retry');
    expect(sweeper.nextDueIn(), isNull);
  });

  test('RouteUnavailable degrades to waiting, never an error state', () async {
    host.idle(OneBalanceVenue.investing, 15);
    host.sendError[OneBalanceVenue.investing] =
        () => const RouteUnavailable('legacy rail');
    await sweeper.trigger('position_closed', venue: OneBalanceVenue.investing);
    expect(sweeper.state.waiting, {OneBalanceVenue.investing: 15});
    expect(sweeper.state.sweeping, isEmpty);
    expect(host.lastEvent('venue_sweep_failed')['error_category'],
        'route_unavailable');
  });

  test('a rail that cannot carry the move retries every 10 min at most',
      () async {
    host.idle(OneBalanceVenue.investing, 6.54);
    host.sendError[OneBalanceVenue.investing] =
        () => const RouteUnavailable('cctp_fee_terms_unavailable');
    await sweeper.trigger('resume');
    expect(sweeper.nextDueIn(), const Duration(minutes: 2));
    var expected = const Duration(minutes: 2);
    for (var i = 0; i < 5; i++) {
      host.clock = host.clock.add(expected);
      await sweeper.trigger('retry');
      expected = expected * 2 > kSweepRouteBackoffMax
          ? kSweepRouteBackoffMax
          : expected * 2;
      expect(sweeper.nextDueIn(), expected);
      expect(sweeper.nextDueIsRetry(), isTrue);
    }
    expect(expected, kSweepRouteBackoffMax);
    expect(sweeper.state.waiting, {OneBalanceVenue.investing: 6.54});
    expect(host.eventsNamed('venue_sweep_failed').length, 1);
    // The backend turns ready: the next retry moves the cash.
    host.sendError.remove(OneBalanceVenue.investing);
    host.clock = host.clock.add(kSweepRouteBackoffMax);
    await sweeper.trigger('retry');
    expect(host.sent.single.usd, 6.54);
  });

  test('coming back to the foreground retries a backed-off venue', () async {
    host.idle(OneBalanceVenue.investing, 6.54);
    host.sendError[OneBalanceVenue.investing] =
        () => const RouteUnavailable('route_unavailable');
    await sweeper.trigger('resume');
    expect(host.lastEvent('venue_sweep_failed')['error_category'],
        'route_unavailable');
    // A quick app switch: still inside the backoff, nothing is asked.
    host.clock = host.clock.add(const Duration(seconds: 20));
    host.sendError.remove(OneBalanceVenue.investing);
    await sweeper.trigger('resume');
    expect(host.sent, isEmpty);
    expect(host.lastEvent('venue_sweep_skipped')['reason'], 'backoff');
    // A heartbeat inside the backoff waits too.
    host.clock = host.clock.add(const Duration(seconds: 50));
    await sweeper.trigger('timer');
    expect(host.sent, isEmpty);
    // Back after a minute: tried at once, without waiting the backoff out.
    await sweeper.trigger('resume');
    expect(host.sent.single.usd, 6.54);
    expect(host.lastEvent('venue_sweep_started')['trigger'], 'resume');
    expect(sweeper.nextDueIn(), isNull);
  });

  test('a resume retry that fails again keeps climbing the ladder', () async {
    host.idle(OneBalanceVenue.investing, 6.54);
    host.sendError[OneBalanceVenue.investing] =
        () => const RouteUnavailable('route_unavailable');
    await sweeper.trigger('resume');
    host.clock = host.clock.add(const Duration(minutes: 1));
    await sweeper.trigger('resume');
    expect(sweeper.nextDueIn(), const Duration(minutes: 4));
  });

  test('the legacy rail reporting nothing withdrawable shows waiting',
      () async {
    host.venues[OneBalanceVenue.investing] =
        const VenueSnapshot(idleUsd: 15, sweepableUsd: 0);
    await sweeper.trigger('resume');
    expect(host.sent, isEmpty);
    expect(sweeper.state.waiting, {OneBalanceVenue.investing: 15});
    expect(host.eventsNamed('venue_sweep_failed'), isEmpty);
  });

  test('a quote refusing the amount raises the minimum and holds it as dust',
      () async {
    host.idle(OneBalanceVenue.predictions, 6);
    host.sendError[OneBalanceVenue.predictions] =
        () => const RouteQuoteError(RouteQuoteErrorCode.amountTooSmall);
    await sweeper.trigger('position_closed',
        venue: OneBalanceVenue.predictions);
    expect(host.tooSmall, [(OneBalanceVenue.predictions, 6.0)]);
    expect(sweeper.state.waiting, isEmpty);
    expect(sweeper.state.dust, {OneBalanceVenue.predictions: 6});
    final failed = host.lastEvent('venue_sweep_failed');
    expect(failed['stage'], 'quote');
    expect(failed['error_category'], 'amount_too_small');
    // No backoff: the next pass compares against the raised minimum.
    expect(sweeper.nextDueIn(), isNull);
    host.minimums[OneBalanceVenue.predictions] = 6.01;
    await sweeper.trigger('timer');
    expect(host.sent, isEmpty);
    expect(host.lastEvent('venue_sweep_skipped')['reason'], 'below_minimum');
  });

  test('a locked session or a non-owner wallet never sends', () async {
    host.idle(OneBalanceVenue.predictions, 50);
    host.unlocked = false;
    await sweeper.trigger('position_closed',
        venue: OneBalanceVenue.predictions);
    expect(host.sent, isEmpty);
    expect(host.lastEvent('venue_sweep_skipped')['reason'], 'locked');
    host.unlocked = true;
    host.wallet = null;
    await sweeper.trigger('resume');
    expect(host.sent, isEmpty);
    host.wallet = 'spend';
    await sweeper.trigger('resume');
    expect(host.sent.length, 1);
  });

  test('a lock dropping during prepare aborts the send', () async {
    host.idle(OneBalanceVenue.investing, 50);
    host.onPrepare = () async => host.unlocked = false;
    await sweeper.trigger('position_closed', venue: OneBalanceVenue.investing);
    expect(host.sent, isEmpty);
    expect(host.lastEvent('venue_sweep_failed')['stage'], 'fund');
    expect(sweeper.state.waiting, {OneBalanceVenue.investing: 50});
  });

  test('one pass at a time; a trigger mid-pass runs once more after', () async {
    host.idle(OneBalanceVenue.predictions, 20);
    var sends = 0;
    host.beforeSend = () async {
      sends++;
      if (sends == 1) {
        await sweeper.trigger('position_closed',
            venue: OneBalanceVenue.predictions);
      }
    };
    await sweeper.trigger('position_closed',
        venue: OneBalanceVenue.predictions);
    // The first send is in flight when the second trigger arrives; the
    // rerun finds the amount discounted and sends nothing more.
    expect(host.sent.length, 1);
  });

  test('a venue that has not answered is left alone', () async {
    host.venues[OneBalanceVenue.predictions] = null;
    host.idle(OneBalanceVenue.investing, 20);
    await sweeper.trigger('resume');
    expect(host.sent.single.venue, OneBalanceVenue.investing);
    expect(host.events.where((e) => e.$2['venue'] == 'polymarket'), isEmpty);
  });

  group('rollout', () {
    setUp(() => host.rolloutFlags.clear());

    test('first unlocked run sweeps both venues, Investing first, once',
        () async {
      host.idle(OneBalanceVenue.predictions, 12);
      host.idle(OneBalanceVenue.investing, 30);
      await sweeper.trigger('resume');
      expect(host.sent.map((s) => s.venue),
          [OneBalanceVenue.investing, OneBalanceVenue.predictions]);
      expect(
          host.sent.map((s) => s.purpose), ['rollout_sweep', 'rollout_sweep']);
      expect(host.prepared.first, OneBalanceVenue.investing);
      expect(host.eventsNamed('venue_sweep_started').length, 2);
      expect(host.lastEvent('venue_sweep_started')['trigger'], 'rollout');
      expect(host.rolloutFlags, {'spend'});
      // The next pass is an ordinary one.
      host.idle(OneBalanceVenue.predictions, 12);
      host.clock = host.clock.add(const Duration(minutes: 11));
      await sweeper.trigger('timer');
      expect(host.sent.last.purpose, 'sweep');
    });

    test('below the minimum at rollout is dust and still marks done', () async {
      host.idle(OneBalanceVenue.predictions, 0.5);
      await sweeper.trigger('resume');
      expect(host.sent, isEmpty);
      expect(sweeper.state.waiting, isEmpty);
      expect(sweeper.state.dust, {OneBalanceVenue.predictions: 0.5});
      expect(host.rolloutFlags, {'spend'});
    });

    test('a venue that has not answered keeps the rollout for the next run',
        () async {
      host.venues[OneBalanceVenue.investing] = null;
      host.idle(OneBalanceVenue.predictions, 12);
      await sweeper.trigger('resume');
      expect(host.sent.single.venue, OneBalanceVenue.predictions);
      expect(host.rolloutFlags, isEmpty);
      host.idle(OneBalanceVenue.investing, 8);
      await sweeper.trigger('resume');
      expect(host.sent.last.venue, OneBalanceVenue.investing);
      expect(host.rolloutFlags, {'spend'});
    });

    test('a locked session does not consume the rollout', () async {
      host.unlocked = false;
      host.idle(OneBalanceVenue.predictions, 12);
      await sweeper.trigger('resume');
      expect(host.sent, isEmpty);
      expect(host.rolloutFlags, isEmpty);
    });
  });

  test('trigger names normalise to the analytics set', () {
    expect(VenueSweeper.normalizeTrigger('position_closed'), 'close');
    expect(VenueSweeper.normalizeTrigger('market_resolved'), 'claim');
    expect(VenueSweeper.normalizeTrigger('order_cancelled'), 'cancel');
    expect(VenueSweeper.normalizeTrigger('manual'), 'resume');
    expect(VenueSweeper.normalizeTrigger('retry'), 'retry');
    // A TP/SL fill closes (part of) a position.
    expect(VenueSweeper.normalizeTrigger('reduce_fill'), 'close');
  });

  test(
      'a venue in use keeps its cash as Available (held), never dust or '
      'waiting, and wakes when its idle window ends', () async {
    final usedAt = host.clock.subtract(const Duration(hours: 23));
    host.venues[OneBalanceVenue.investing] =
        VenueSnapshot(idleUsd: 12, sweepableUsd: 12, lastActivityAt: usedAt);
    await sweeper.trigger('close', venue: OneBalanceVenue.investing);
    expect(host.sent, isEmpty);
    expect(sweeper.state.held, {OneBalanceVenue.investing: 12});
    expect(sweeper.state.waiting, isEmpty);
    expect(sweeper.state.dust, isEmpty);
    expect(host.lastEvent('venue_sweep_skipped')['reason'], 'venue_active');
    // The idle window ends an hour from now: a pass is due then.
    expect(sweeper.nextDueIn(), const Duration(hours: 1));

    // A day idle: the cash goes home, named for the rule.
    host.clock = host.clock.add(const Duration(hours: 1, minutes: 1));
    await sweeper.trigger('timer');
    expect(host.sent.single.usd, 12);
    expect(
        host.lastEvent('venue_sweep_started')['trigger'], 'investing_idle_24h');
    expect(sweeper.state.held, isEmpty);
  });

  test('a pass that decides nothing keeps the venue cash counted', () async {
    // A venue in use keeps its cash (held).
    final usedAt = host.clock.subtract(const Duration(hours: 1));
    host.venues[OneBalanceVenue.predictions] = VenueSnapshot(
        idleUsd: 3.55, sweepableUsd: 3.55, lastActivityAt: usedAt);
    await sweeper.trigger('timer');
    expect(sweeper.state.held, {OneBalanceVenue.predictions: 3.55});
    // Locked: nothing decided, the cash stays where the last pass put it
    // (it used to drop out of the total).
    host.unlocked = false;
    await sweeper.trigger('timer');
    expect(host.lastEvent('venue_sweep_skipped')['reason'], 'locked');
    expect(sweeper.state.held, {OneBalanceVenue.predictions: 3.55});
  });

  test('cash held back for a moment is Available, never dropped', () async {
    // Idle a day (no idle rule keeping it) but a bet is queued on it.
    host.venues[OneBalanceVenue.predictions] = const VenueSnapshot(
        idleUsd: 12, sweepableUsd: 12, hasPendingIntent: true);
    await sweeper.trigger('timer');
    expect(host.sent, isEmpty);
    expect(sweeper.state.held, {OneBalanceVenue.predictions: 12});
    expect(sweeper.state.waiting, isEmpty);
    // What a resting order holds is not Available.
    host.venues[OneBalanceVenue.predictions] = const VenueSnapshot(
        idleUsd: 12, sweepableUsd: 7, hasReservations: true, isClaiming: true);
    await sweeper.trigger('timer');
    expect(sweeper.state.held, {OneBalanceVenue.predictions: 7});
    // A move pending keeps what the last pass counted (a sweep the read
    // still shows is counted in flight already).
    host.venues[OneBalanceVenue.predictions] = const VenueSnapshot(
        idleUsd: 30, sweepableUsd: 30, hasPendingMove: true);
    await sweeper.trigger('timer');
    expect(sweeper.state.held, {OneBalanceVenue.predictions: 7});
  });

  group('the Portfolio\'s Rebalance (sweepNow)', () {
    /// A venue used a minute ago: the idle rule keeps its cash.
    VenueSnapshot inUse(double usd,
            {double? sweepable,
            bool reservations = false,
            bool cross = false,
            bool resting = false}) =>
        VenueSnapshot(
          idleUsd: usd,
          sweepableUsd: sweepable ?? usd,
          hasReservations: reservations,
          hasCrossPosition: cross,
          hasUnreservedRestingOrders: resting,
          lastActivityAt: host.clock.subtract(const Duration(minutes: 1)),
        );

    test(
        'sends each venue\'s cash home once, the idle wait set aside, under '
        'the same rail and events, trigger manual_rebalance', () async {
      host.venues[OneBalanceVenue.investing] = inUse(6.54);
      host.venues[OneBalanceVenue.predictions] = inUse(3);
      // A pass of its own leaves the cash where it is (the idle rule) but
      // says what a Rebalance would move.
      await sweeper.trigger('timer');
      expect(host.sent, isEmpty);
      expect(sweeper.state.movable,
          {OneBalanceVenue.investing: 6.54, OneBalanceVenue.predictions: 3});

      final out = await sweeper.sweepNow();
      expect(host.sent.map((s) => (s.venue, s.usd, s.purpose)), [
        (OneBalanceVenue.investing, 6.54, 'sweep'),
        (OneBalanceVenue.predictions, 3.0, 'sweep'),
      ]);
      expect(out[OneBalanceVenue.investing],
          const RebalanceOutcome(RebalanceOutcomeKind.moving, usd: 6.54));
      expect(out[OneBalanceVenue.predictions],
          const RebalanceOutcome(RebalanceOutcomeKind.moving, usd: 3));
      final started =
          host.events.where((e) => e.$1 == 'venue_sweep_started').toList();
      expect(started.map((e) => e.$2['trigger']),
          ['manual_rebalance', 'manual_rebalance']);
      expect(host.eventsNamed('venue_sweep_submitted').length, 2);
      // Nothing movable is left once they went.
      expect(sweeper.state.movable, isEmpty);
    });

    test(
        'never a cross position\'s margin, an order\'s cash at Investing, '
        'cash open orders reserve, or dust; each reported with the trigger',
        () async {
      host.venues[OneBalanceVenue.investing] = inUse(20, cross: true);
      host.venues[OneBalanceVenue.predictions] =
          inUse(8, sweepable: 0, reservations: true);
      await sweeper.trigger('timer');
      expect(sweeper.state.movable, isEmpty);
      var out = await sweeper.sweepNow();
      expect(host.sent, isEmpty);
      expect(out[OneBalanceVenue.investing]!.reason,
          SweepSkipReason.crossPosition);
      expect(
          out[OneBalanceVenue.predictions]!.reason, SweepSkipReason.openOrders);
      final skipped =
          host.events.where((e) => e.$1 == 'venue_sweep_skipped').toList();
      expect(
          skipped.map((e) => (e.$2['venue'], e.$2['reason'], e.$2['trigger'])),
          containsAll([
            ('hyperliquid', 'cross_position', 'manual_rebalance'),
            ('polymarket', 'open_orders', 'manual_rebalance'),
          ]));

      // An order resting at Investing (no cash reserved for it there).
      host.venues[OneBalanceVenue.investing] = inUse(20, resting: true);
      // Predictions dust: below the route minimum.
      host.venues[OneBalanceVenue.predictions] = inUse(0.4);
      out = await sweeper.sweepNow();
      expect(host.sent, isEmpty);
      expect(
          out[OneBalanceVenue.investing],
          const RebalanceOutcome(RebalanceOutcomeKind.held,
              usd: 20, reason: SweepSkipReason.openOrders));
      expect(out[OneBalanceVenue.predictions],
          const RebalanceOutcome(RebalanceOutcomeKind.belowMinimum, usd: 0.4));
      // A tap reports each time, not once per episode.
      expect(
          host.events.where((e) =>
              e.$1 == 'venue_sweep_skipped' &&
              e.$2['trigger'] == 'manual_rebalance'),
          hasLength(4));
    });

    test('only the unreserved part of Predictions cash moves', () async {
      host.venues[OneBalanceVenue.predictions] =
          inUse(10, sweepable: 6, reservations: true);
      await sweeper.sweepNow();
      expect(host.sent.single.venue, OneBalanceVenue.predictions);
      expect(host.sent.single.usd, 6);
    });

    test('a bet queued since the read keeps the cash (re-read before send)',
        () async {
      // The second read (right before the move) sees a bet queued.
      final queued = _QueuedBetHost(host, inUse(10));
      final out = await VenueSweeper(queued).sweepNow();
      expect(host.sent, isEmpty);
      expect(
          out[OneBalanceVenue.predictions],
          const RebalanceOutcome(RebalanceOutcomeKind.held,
              usd: 10, reason: SweepSkipReason.openOrders));
    });

    test(
        'no double sweep: a Rebalance during an automatic pass waits for it, '
        'and the cash that pass sent is not sent again', () async {
      host.idle(OneBalanceVenue.predictions, 20);
      final gate = Completer<void>();
      host.beforeSend = () => gate.future;
      final auto = sweeper.trigger('position_closed',
          venue: OneBalanceVenue.predictions);
      await Future<void>.delayed(Duration.zero);
      expect(sweeper.state.sweeping, {OneBalanceVenue.predictions});
      final manual = sweeper.sweepNow();
      final second = sweeper.sweepNow();
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      await auto;
      final out = await manual;
      await second;
      expect(host.sent.length, 1);
      expect(out[OneBalanceVenue.predictions]!.kind,
          isNot(RebalanceOutcomeKind.moving));
    });

    test(
        'submits both venues at once: both sends start before either '
        'completes, and each venue keeps its own outcome', () async {
      host.venues[OneBalanceVenue.investing] = inUse(6);
      host.venues[OneBalanceVenue.predictions] = inUse(3);
      final started = <OneBalanceVenue>[];
      final gates = {
        for (final v in OneBalanceVenue.values) v: Completer<void>(),
      };
      host.beforeSendTo = (venue) {
        started.add(venue);
        return gates[venue]!.future;
      };
      // Investing's rail refuses once its gate opens; Predictions' sends.
      host.sendError[OneBalanceVenue.investing] =
          () => StateError('rail down');

      final tap = sweeper.sweepNow();
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(started.toSet(), OneBalanceVenue.values.toSet(),
          reason: 'both sends are out before either answers');
      expect(sweeper.state.sweeping, OneBalanceVenue.values.toSet());
      expect(host.sent, isEmpty);

      // Predictions answers first, Investing after: no waiting on order.
      gates[OneBalanceVenue.predictions]!.complete();
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(host.sent.single.venue, OneBalanceVenue.predictions);
      expect(sweeper.state.sweeping, {OneBalanceVenue.investing});
      gates[OneBalanceVenue.investing]!.complete();
      final out = await tap;

      expect(out.keys, [OneBalanceVenue.investing, OneBalanceVenue.predictions]);
      expect(out[OneBalanceVenue.predictions],
          const RebalanceOutcome(RebalanceOutcomeKind.moving, usd: 3));
      expect(out[OneBalanceVenue.investing],
          const RebalanceOutcome(RebalanceOutcomeKind.notNow, usd: 6));
      expect(sweeper.state.sweeping, isEmpty);
      // The events stay per venue: two starts, one submit, one failure.
      expect(
          host.events
              .where((e) => e.$1 == 'venue_sweep_started')
              .map((e) => e.$2['venue'])
              .toSet(),
          {'hyperliquid', 'polymarket'});
      expect(host.lastEvent('venue_sweep_submitted')['venue'], 'polymarket');
      expect(host.lastEvent('venue_sweep_failed')['venue'], 'hyperliquid');
      // Only the failed venue backs off: an automatic pass a minute later
      // leaves Investing alone.
      host.sendError.remove(OneBalanceVenue.investing);
      host.beforeSendTo = null;
      host.venues[OneBalanceVenue.investing] =
          const VenueSnapshot(idleUsd: 6, sweepableUsd: 6);
      host.clock = host.clock.add(const Duration(seconds: 30));
      await sweeper.trigger('position_closed',
          venue: OneBalanceVenue.investing);
      expect(host.sent.length, 1);
      expect(host.lastEvent('venue_sweep_skipped')['reason'], 'backoff');
    });

    test('no double sweep: a second tap while both venues move sends nothing',
        () async {
      host.venues[OneBalanceVenue.investing] = inUse(6);
      host.venues[OneBalanceVenue.predictions] = inUse(3);
      final gate = Completer<void>();
      host.beforeSend = () => gate.future;
      final first = sweeper.sweepNow();
      await Future<void>.delayed(Duration.zero);
      final second = sweeper.sweepNow();
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      gate.complete();
      final a = await first;
      final b = await second;
      expect(host.sent.map((s) => s.venue).toSet(),
          OneBalanceVenue.values.toSet());
      expect(host.sent.length, 2, reason: 'one move per venue');
      expect(a.values.map((o) => o.kind).toSet(),
          {RebalanceOutcomeKind.moving});
      expect(b.values.map((o) => o.kind),
          everyElement(isNot(RebalanceOutcomeKind.moving)));
    });

    test('a locked session never sends', () async {
      host.venues[OneBalanceVenue.investing] = inUse(20);
      host.unlocked = false;
      final out = await sweeper.sweepNow();
      expect(host.sent, isEmpty);
      expect(out[OneBalanceVenue.investing]!.reason, SweepSkipReason.locked);
      expect(sweeper.state.movable, isEmpty);
    });

    test(
        'a venue backing off after a failure a Rebalance would retry shows '
        'as movable, not hidden until the backoff ends', () async {
      host.idle(OneBalanceVenue.predictions, 12);
      host.sendError[OneBalanceVenue.predictions] =
          () => StateError('rail down');
      await sweeper.trigger('timer'); // fails: backs off 2 minutes
      expect(host.sent, isEmpty);
      host.sendError.remove(OneBalanceVenue.predictions);
      host.venues[OneBalanceVenue.predictions] = inUse(2.77);
      // 30 s later: too soon, a Rebalance would still wait.
      host.clock = host.clock.add(const Duration(seconds: 30));
      await sweeper.trigger('timer');
      expect(sweeper.state.movable, isEmpty);
      // 90 s after the failure a Rebalance lifts the backoff: the button
      // shows what it would move, though the backoff runs another 30 s.
      host.clock = host.clock.add(const Duration(minutes: 1));
      await sweeper.trigger('timer');
      expect(sweeper.state.movable, {OneBalanceVenue.predictions: 2.77});
      await sweeper.sweepNow();
      expect(host.sent.single.usd, 2.77);
    });
  });

  group('preview (the Portfolio opening)', () {
    /// Predictions used an hour ago: the idle rule keeps its cash, so no
    /// pass of its own would ever move it.
    VenueSnapshot inUse(double usd,
            {double? sweepable, bool reservations = false}) =>
        VenueSnapshot(
          idleUsd: usd,
          sweepableUsd: sweepable ?? usd,
          hasReservations: reservations,
          lastActivityAt: host.clock.subtract(const Duration(hours: 1)),
        );

    test(
        r"the founder's $2.77 of free Predictions cash: movable at once, "
        'with no pass ever run, nothing sent, nothing reported', () async {
      host.venues[OneBalanceVenue.predictions] = inUse(2.77);
      // No pass has run: the sweeper knows nothing yet.
      expect(sweeper.state, const VenueSweeperState());
      await sweeper.preview();
      expect(sweeper.state.movable, {OneBalanceVenue.predictions: 2.77});
      expect(sweeper.state.belowMinimum, isEmpty);
      // The cash is counted as the pass would count it: Available.
      expect(sweeper.state.held, {OneBalanceVenue.predictions: 2.77});
      expect(host.sent, isEmpty);
      expect(host.events, isEmpty);
      // And a tap moves exactly that.
      await sweeper.sweepNow();
      expect(host.sent.single.venue, OneBalanceVenue.predictions);
      expect(host.sent.single.usd, 2.77);
    });

    test(r'$2.77 under a $3 route minimum: below the minimum, not movable',
        () async {
      host.venues[OneBalanceVenue.predictions] = inUse(2.77);
      host.minimums[OneBalanceVenue.predictions] = 3;
      await sweeper.preview();
      expect(sweeper.state.movable, isEmpty);
      expect(sweeper.state.belowMinimum, {OneBalanceVenue.predictions: 2.77});
      expect(sweeper.state.dust, {OneBalanceVenue.predictions: 2.77});
      expect(host.sent, isEmpty);
    });

    test('reads with the session\'s minimum, not a fresh network read',
        () async {
      host.venues[OneBalanceVenue.predictions] = inUse(2.77);
      host.previewMinimums[OneBalanceVenue.predictions] = 1;
      host.minimums[OneBalanceVenue.predictions] = 99; // never asked
      await sweeper.preview();
      expect(sweeper.state.movable, {OneBalanceVenue.predictions: 2.77});
    });

    test('cash open orders reserve is never movable', () async {
      host.venues[OneBalanceVenue.predictions] =
          inUse(8, sweepable: 0, reservations: true);
      await sweeper.preview();
      expect(sweeper.state.movable, isEmpty);
      expect(sweeper.state.belowMinimum, isEmpty);
    });

    test('a locked session: nothing movable', () async {
      host.venues[OneBalanceVenue.predictions] = inUse(2.77);
      host.unlocked = false;
      await sweeper.preview();
      expect(sweeper.state.movable, isEmpty);
    });

    test('a venue that has not answered: nothing claimed for it', () async {
      host.venues[OneBalanceVenue.predictions] = null;
      await sweeper.preview();
      expect(sweeper.state.movable, isEmpty);
    });

    test('a move that started while it read: what it read is dropped',
        () async {
      host.venues[OneBalanceVenue.predictions] = inUse(2.77);
      final gate = Completer<void>();
      host.beforeSend = () => gate.future;
      final manual = sweeper.sweepNow();
      await Future<void>.delayed(Duration.zero);
      await sweeper.preview();
      // The move is running: the preview leaves the venue to it.
      expect(sweeper.state.movable, isEmpty);
      gate.complete();
      await manual;
      expect(host.sent.length, 1);
    });
  });
}

/// [inner] with a bet queued on Predictions from the second read on.
class _QueuedBetHost extends VenueSweeperHost {
  _QueuedBetHost(this.inner, this.snapshot);

  final _FakeHost inner;
  final VenueSnapshot snapshot;
  int _reads = 0;

  @override
  DateTime now() => inner.now();

  @override
  bool get sessionUnlocked => inner.sessionUnlocked;

  @override
  String? get spendingWalletId => inner.spendingWalletId;

  @override
  Future<VenueSnapshot?> readVenue(OneBalanceVenue venue) async {
    if (venue != OneBalanceVenue.predictions) return inner.readVenue(venue);
    _reads++;
    if (_reads < 2) return snapshot;
    return VenueSnapshot(
        idleUsd: snapshot.idleUsd,
        sweepableUsd: snapshot.sweepableUsd,
        hasPendingIntent: true,
        lastActivityAt: snapshot.lastActivityAt);
  }

  @override
  Future<double> minimumUsd(OneBalanceVenue venue) => inner.minimumUsd(venue);

  @override
  void noteAmountTooSmall(OneBalanceVenue venue, double usd) =>
      inner.noteAmountTooSmall(venue, usd);

  @override
  Future<void> prepare(OneBalanceVenue venue) => inner.prepare(venue);

  @override
  Future<VenueMoveResult> send(OneBalanceVenue venue,
          {required double usd, required String purpose}) =>
      inner.send(venue, usd: usd, purpose: purpose);

  @override
  bool rolloutDone(String walletId) => inner.rolloutDone(walletId);

  @override
  void markRolloutDone(String walletId) => inner.markRolloutDone(walletId);

  @override
  bool claimTerminal(String orderId, {required bool success}) =>
      inner.claimTerminal(orderId, success: success);

  @override
  void track(String event, Map<String, Object> params) =>
      inner.track(event, params);
}
