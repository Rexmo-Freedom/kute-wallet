// The sweeper's state machine against a fake host and a fake clock: what
// moves, what waits, what backs off, and what each pass reports.

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
    OneBalanceVenue.predictions: const VenueSnapshot(idleUsd: 0, sweepableUsd: 0),
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
    await sweeper.trigger('position_closed', venue: OneBalanceVenue.predictions);
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
    await sweeper.trigger('position_closed', venue: OneBalanceVenue.predictions);
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
    host.venues[OneBalanceVenue.predictions] =
        const VenueSnapshot(idleUsd: 12, sweepableUsd: 12, hasPendingMove: true);
    await sweeper.trigger('resume');
    expect(host.sent, isEmpty);
    expect(host.lastEvent('venue_sweep_skipped')['reason'], 'pending_deposit');
    // Same reason again: no second event.
    await sweeper.trigger('resume');
    expect(host.eventsNamed('venue_sweep_skipped').length, 1);

    host.venues[OneBalanceVenue.predictions] =
        const VenueSnapshot(idleUsd: 12, sweepableUsd: 12, hasPendingIntent: true);
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
    await sweeper.trigger('market_resolved', venue: OneBalanceVenue.predictions);
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
    await sweeper.trigger('market_resolved', venue: OneBalanceVenue.predictions);
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
    expect(sweeper.state.dust[OneBalanceVenue.investing],
        closeTo(0.06, 1e-9));
  });

  test('dust is not shown while the venue backs off', () async {
    host.idle(OneBalanceVenue.predictions, 20);
    host.sendError[OneBalanceVenue.predictions] = () => StateError('boom');
    await sweeper.trigger('position_closed', venue: OneBalanceVenue.predictions);
    expect(sweeper.state.waiting, {OneBalanceVenue.predictions: 20});
    // Most of it left another way; the cents left are dust, not waiting.
    host.idle(OneBalanceVenue.predictions, 0.4);
    await sweeper.trigger('timer');
    expect(sweeper.state.waiting, isEmpty);
    expect(sweeper.state.dust, {OneBalanceVenue.predictions: 0.4});
  });

  test('the CCTP floor refusing the amount is dust, with no backoff',
      () async {
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
    await sweeper.trigger('order_cancelled', venue: OneBalanceVenue.predictions);
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
    await sweeper.trigger('position_closed', venue: OneBalanceVenue.predictions);
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

  test('the legacy rail reporting nothing withdrawable shows waiting', () async {
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
    await sweeper.trigger('position_closed', venue: OneBalanceVenue.predictions);
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
    await sweeper.trigger('position_closed', venue: OneBalanceVenue.predictions);
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
    await sweeper.trigger('position_closed', venue: OneBalanceVenue.predictions);
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
      expect(host.sent.map((s) => s.purpose), ['rollout_sweep', 'rollout_sweep']);
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

    test('below the minimum at rollout is dust and still marks done',
        () async {
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

  test('a venue in use keeps its cash as Available (held), never dust or '
      'waiting, and wakes when its idle window ends', () async {
    final usedAt = host.clock.subtract(const Duration(hours: 23));
    host.venues[OneBalanceVenue.investing] = VenueSnapshot(
        idleUsd: 12, sweepableUsd: 12, lastActivityAt: usedAt);
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
    expect(host.lastEvent('venue_sweep_started')['trigger'],
        'investing_idle_24h');
    expect(sweeper.state.held, isEmpty);
  });
}
