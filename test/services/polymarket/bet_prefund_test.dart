// Getting a fast prediction ready before Confirm (founder option A): the
// one-second hold on a 5/15-minute round or a game in play, the ONE
// step-up that covers the move and the bet, Confirm queueing behind the
// money with no second prompt, top-ups inside the approved caps only,
// decline falling back to Confirm-time funding, a closed slip leaving the
// cash where it is, and the closing-market / ended-market rules.

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/pending_bet_autofire.dart' show autofireFireAt;
import 'package:kute/providers/pending_polymarket_bet_provider.dart';
import 'package:kute/services/one_balance/bet_funding_plan.dart';
import 'package:kute/services/one_balance/order_funding.dart';
import 'package:kute/services/one_balance/prediction_funding_ledger.dart';
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/polymarket/bet_prefund.dart';
import 'package:kute/services/tracking_service.dart';

const _token = 'up-token';
const _sel = PrefundSelection(tokenId: _token, isLimit: false, slippagePct: 10);

PrefundSnapshot _slip({
  PrefundMarketKind? kind = PrefundMarketKind.short,
  PrefundSelection selection = _sel,
  double amount = 20,
  double required = 20.5,
  double ready = 5,
  double balance = 5,
  double dollars = 100,
  bool allowed = true,
  bool busy = false,
}) =>
    PrefundSnapshot(
      kind: kind,
      selection: selection,
      amountUsd: amount,
      minBetUsd: 1,
      requiredUsd: required,
      readyUsd: ready,
      balanceUsd: balance,
      dollarsUsd: dollars,
      allowed: allowed,
      busy: busy,
    );

/// The fakes behind one slip's pre-funding.
class _Rig {
  _Rig({
    this.answer = PrefundApprovalResult.approved,
    this.block,
  }) {
    prefund = BetPrefund(
      approve: (r) async {
        requests.add(r);
        switch (answer) {
          case PrefundApprovalResult.declined:
            return const PrefundApproval.declined();
          case PrefundApprovalResult.unavailable:
            return const PrefundApproval.unavailable();
          case PrefundApprovalResult.approved:
            final grant = AuthGrants.issue(
                PmGrants.fundedBetReview(
                    PmGrants.betReview(
                        walletId: 'w',
                        tokenId: _token,
                        maxCostUsd: r.amountUsd * 1.05,
                        worstPrice: 0.6,
                        orderType: 'fak'),
                    fundUsd: r.fundingCapUsd,
                    venue: IntentVenue.polymarket),
                method: AuthGrantMethod.biometric);
            grants.add(grant);
            return PrefundApproval.approved(
                grant,
                PendingBetIntent(
                  tokenId: _token,
                  amount: r.amountUsd,
                  slippagePct: 10,
                  marketQuestion: 'Bitcoin Up or Down',
                  outcomeName: 'Up',
                  expectedPrice: 0.5,
                  fundUsd: r.fundingCapUsd,
                ));
        }
      },
      fund: (usd, grant, {required requiredUsd, required readyUsd}) async {
        funded.add((usd: usd, grant: grant));
        if (notNeeded) return const OrderFundingNotNeeded();
        if (refuse) return const OrderFundingRefused('route');
        return OrderFundingFunded(VenueMoveResult(
          quoteId: 'quote-${funded.length}',
          sentUsd: usd,
          arrivingUsdEstimate: usd * 0.99,
        ));
      },
      // The single sizing entry point.
      plan: ({required requiredUsd, required readyUsd}) async =>
          planBetFunding(requiredUsd: requiredUsd, readyUsd: readyUsd),
      window: ({required requireRead, fundUsd = 0}) async {
        windowReads.add(requireRead);
        return block;
      },
      onDisarm: () => disarmed++,
    );
  }

  late final BetPrefund prefund;
  PrefundApprovalResult answer;
  PredictionsFundingBlock? block;
  bool notNeeded = false;
  bool refuse = false;
  int disarmed = 0;
  final requests = <PrefundRequest>[];
  final grants = <AuthGrant>[];
  final funded = <({double usd, AuthGrant grant})>[];
  final windowReads = <bool>[];
}

void main() {
  late List<(String, Map<String, Object?>)> events;
  setUp(() {
    PredictionFundingLedger.reset();
    OrderFundingJourney.reset();
    events = [];
    TrackingService.debugTrackObserver =
        (e, params) => events.add((e, Map.of(params ?? const {})));
  });
  tearDown(() => TrackingService.debugTrackObserver = null);

  Iterable<String> names() => events.map((e) => e.$1);

  group('the one-second hold', () {
    test('asks only after the amount has stayed one second', () {
      fakeAsync((async) {
        final rig = _Rig();
        rig.prefund.scheduleHold(_slip);
        async.elapse(const Duration(milliseconds: 900));
        // Typed again before the second was up: the hold restarts.
        rig.prefund.scheduleHold(_slip);
        async.elapse(const Duration(milliseconds: 900));
        expect(rig.requests, isEmpty);
        async.elapse(const Duration(milliseconds: 200));
        async.flushMicrotasks();
        expect(rig.requests, hasLength(1));
        expect(rig.requests.single.atConfirm, isFalse);
        expect(rig.funded, hasLength(1));
      });
    });

    test('never on a market that is not fast', () async {
      final rig = _Rig();
      await rig.prefund.holdFired(() => _slip(kind: null));
      expect(rig.requests, isEmpty);
    });

    test('a game in play is fast too', () async {
      final rig = _Rig();
      await rig.prefund.holdFired(() => _slip(kind: PrefundMarketKind.live));
      expect(rig.requests, hasLength(1));
      expect(events.firstWhere((e) => e.$1 == 'prediction_prefund_started').$2,
          containsPair('market_kind', 'live'));
    });

    test('never when Predictions cash already covers the bet', () async {
      final rig = _Rig();
      await rig.prefund
          .holdFired(() => _slip(required: 20.5, ready: 21, balance: 21));
      expect(rig.requests, isEmpty);
    });

    test('never when Investments cannot cover the move (Add at Confirm)',
        () async {
      final rig = _Rig();
      await rig.prefund.holdFired(() => _slip(dollars: 3));
      expect(rig.requests, isEmpty);
      expect(rig.funded, isEmpty);
    });

    test('never when a gate is shut, a placement runs, or limit mode',
        () async {
      final rig = _Rig();
      await rig.prefund.holdFired(() => _slip(allowed: false));
      await rig.prefund.holdFired(() => _slip(busy: true));
      await rig.prefund.holdFired(() => _slip(
          selection: const PrefundSelection(
              tokenId: _token, isLimit: true, slippagePct: 10)));
      expect(rig.requests, isEmpty);
    });

    test('never on a market closing before the money could land', () async {
      final rig = _Rig(block: PredictionsFundingBlock.closing);
      await rig.prefund.holdFired(_slip);
      expect(rig.requests, isEmpty);
      expect(rig.funded, isEmpty);
      // Pre-funding needs the market read.
      expect(rig.windowReads, [true]);
    });
  });

  group('one approval covers the move and the bet', () {
    test('Confirm queues behind the money with no second prompt', () async {
      final rig = _Rig();
      await rig.prefund.holdFired(_slip);
      expect(rig.requests, hasLength(1));
      expect(rig.funded, hasLength(1));
      final move = rig.funded.single;
      expect(move.usd,
          planBetFunding(requiredUsd: 20.5, readyUsd: 5).fundUsd);
      expect(identical(move.grant, rig.grants.single), isTrue);
      expect(rig.prefund.engaged, isTrue);
      final ref = rig.prefund.moves.single.ref;
      expect(PredictionFundingLedger.instance.record(ref)?.stage,
          PredictionFundingStage.sent);

      final result = await rig.prefund.confirm(_slip());
      expect(result, isA<PrefundQueued>());
      final queued = (result as PrefundQueued).intent;
      // No second prompt, no second move.
      expect(rig.requests, hasLength(1));
      expect(rig.funded, hasLength(1));
      expect(queued.status, PendingBetStatus.awaitingBalance);
      expect(queued.tokenId, _token);
      expect(queued.amount, 20);
      // The funding cap the grant binds, exactly (the autofire signs it).
      expect(queued.fundUsd, move.usd);
      expect(queued.fundQuoteRef, ref);
      expect(result.fundUsd, move.usd);
      expect(rig.grants.single.revoked, isFalse);

      final started =
          events.firstWhere((e) => e.$1 == 'prediction_prefund_started').$2;
      expect(started['amount_usd'], 20);
      expect(started['market_kind'], 'short');
      final used =
          events.firstWhere((e) => e.$1 == 'prediction_prefund_used').$2;
      expect(used['amount_usd'], 20);
      expect(used['seconds_to_confirm'], isA<int>());
      // Never a key, address or id on these events.
      for (final e in events.where((e) => e.$1.startsWith('prediction_'))) {
        expect(e.$2.keys, everyElement(isNot(anyOf('quote_id', 'token_id'))));
      }
    });

    test('Confirm before the money lands: queued, fires on landing',
        () async {
      final rig = _Rig();
      await rig.prefund.holdFired(_slip);
      final result = await rig.prefund.confirm(_slip()) as PrefundQueued;
      // The venue still holds $5: the autofire waits for the move.
      expect(5, lessThan(autofireFireAt(result.intent)));
      final landedBalance = 5 + rig.prefund.moves.single.arrivingUsd;
      expect(landedBalance, greaterThanOrEqualTo(autofireFireAt(result.intent)));
    });

    test('money already landed: the queued bet can fire at once', () async {
      final rig = _Rig();
      await rig.prefund.holdFired(_slip);
      final arriving = rig.prefund.moves.single.arrivingUsd;
      rig.prefund.observeBalance(5 + arriving);
      expect(rig.prefund.inFlightArrivingUsd, 0);
      expect(
          PredictionFundingLedger.instance
              .record(rig.prefund.moves.single.ref)
              ?.stage,
          PredictionFundingStage.landed);
      final result = await rig.prefund
          .confirm(_slip(ready: 5 + arriving, balance: 5 + arriving));
      expect(result, isA<PrefundQueued>());
      expect(rig.requests, hasLength(1));
    });
  });

  group('switching to a limit order after a pre-fund', () {
    const limit =
        PrefundSelection(tokenId: _token, isLimit: true, slippagePct: 10);

    test('Confirm-time funding counts the money still on its way', () async {
      final rig = _Rig();
      await rig.prefund.holdFired(_slip);
      final arriving = rig.prefund.moves.single.arrivingUsd;
      // A limit order is Confirm-time funded…
      expect(await rig.prefund.confirm(_slip(selection: limit)),
          isA<PrefundNotUsed>());
      // …against the venue cash plus what is still on its way, so the
      // same shortfall is never moved twice.
      final ready =
          rig.prefund.readyAtConfirmUsd(spendableUsd: 5, balanceUsd: 5);
      expect(ready, closeTo(5 + arriving, 1e-9));
      expect(planBetFunding(requiredUsd: 20.5, readyUsd: ready).fundUsd, 0);
      expect(rig.funded, hasLength(1));
    });

    test('once it has landed, the venue cash alone counts', () async {
      final rig = _Rig();
      await rig.prefund.holdFired(_slip);
      final arriving = rig.prefund.moves.single.arrivingUsd;
      await rig.prefund.confirm(_slip(selection: limit));
      final ready = rig.prefund.readyAtConfirmUsd(
          spendableUsd: 5 + arriving, balanceUsd: 5 + arriving);
      expect(ready, closeTo(5 + arriving, 1e-9));
      expect(rig.prefund.inFlightArrivingUsd, 0);
    });
  });

  group('declining', () {
    test('falls back to Confirm-time funding and never asks again', () async {
      final rig = _Rig(answer: PrefundApprovalResult.declined);
      await rig.prefund.holdFired(_slip);
      expect(rig.funded, isEmpty);
      expect(names(), contains('prediction_prefund_declined'));
      expect(names(), isNot(contains('prediction_prefund_started')));
      await rig.prefund.holdFired(() => _slip(amount: 25, required: 25.6));
      expect(rig.requests, hasLength(1));
      // Confirm runs as before.
      expect(await rig.prefund.confirm(_slip()), isA<PrefundNotUsed>());
      expect(rig.prefund.engaged, isFalse);
    });
  });

  group('amount edits', () {
    test('a decrease leaves the excess on Predictions', () async {
      final rig = _Rig();
      await rig.prefund.holdFired(_slip);
      await rig.prefund.holdFired(() => _slip(amount: 10, required: 10.3));
      expect(rig.funded, hasLength(1));
      final result = await rig.prefund.confirm(_slip(amount: 10, required: 10.3));
      expect((result as PrefundQueued).intent.amount, 10);
      expect(rig.requests, hasLength(1));
    });

    test('an increase inside the caps tops up under the same approval',
        () async {
      final rig = _Rig()..notNeeded = true;
      // Approved at $20 with a funding cap; the venue covered it then.
      await rig.prefund.holdFired(_slip);
      expect(rig.requests, hasLength(1));
      final cap = rig.requests.single.fundingCapUsd;
      rig.notNeeded = false;
      // A resting buy took some cash since: $20 now needs a small move.
      await rig.prefund.holdFired(() => _slip(ready: 12, balance: 12));
      expect(rig.requests, hasLength(1), reason: 'no second prompt');
      expect(rig.funded, hasLength(2));
      expect(identical(rig.funded.last.grant, rig.grants.single), isTrue);
      expect(rig.funded.last.usd, lessThanOrEqualTo(cap));
    });

    test('an increase past the caps asks again', () async {
      final rig = _Rig();
      await rig.prefund.holdFired(_slip);
      await rig.prefund.holdFired(() => _slip(amount: 40, required: 41));
      expect(rig.requests, hasLength(2));
      expect(rig.funded, hasLength(2));
      // Only what is still missing moves, counting the money on its way.
      final first = rig.prefund.moves.first.arrivingUsd;
      expect(rig.funded.last.usd,
          planBetFunding(requiredUsd: 41, readyUsd: 5 + first).fundUsd);
    });

    test('another outcome drops the approval and asks again', () async {
      final rig = _Rig();
      await rig.prefund.holdFired(_slip);
      const down =
          PrefundSelection(tokenId: 'down-token', isLimit: false, slippagePct: 10);
      // The money on its way covers the other side too: nothing moves,
      // the old approval goes.
      await rig.prefund.holdFired(() => _slip(selection: down));
      expect(rig.disarmed, 1);
      expect(rig.grants.first.revoked, isTrue);
      expect(rig.funded, hasLength(1));
      // Confirm then asks once for the new bet (nothing more moves).
      final result = await rig.prefund.confirm(_slip(selection: down));
      expect(result, isA<PrefundQueued>());
      expect(rig.requests, hasLength(2));
      expect(rig.requests.last.atConfirm, isTrue);
      expect(rig.requests.last.fundingCapUsd, 0);
      expect(rig.funded, hasLength(1));
    });
  });

  group('cancel', () {
    test('closing the slip leaves the moved cash and drops the approval',
        () async {
      final rig = _Rig();
      await rig.prefund.holdFired(_slip);
      final ref = rig.prefund.moves.single.ref;
      rig.prefund.close();
      expect(rig.grants.single.revoked, isTrue);
      expect(rig.disarmed, 1);
      // Nothing comes back: no second move of any kind.
      expect(rig.funded, hasLength(1));
      final record = PredictionFundingLedger.instance.record(ref);
      expect(record?.stage, PredictionFundingStage.released);
      expect(record?.releaseReason, 'abandoned');
      expect(names(), isNot(contains('prediction_prefund_used')));
    });

    test('a handed-off bet is left to fire after the slip closes', () async {
      final rig = _Rig();
      await rig.prefund.holdFired(_slip);
      await rig.prefund.confirm(_slip());
      rig.prefund.close();
      expect(rig.grants.single.revoked, isFalse);
      expect(rig.disarmed, 0);
    });
  });

  group('closing markets (audit P1-5)', () {
    final now = DateTime.utc(2026, 10, 13, 12);

    test('ends within the funding p95 plus margin: closing', () {
      expect(
          predictionsFundingBlock(
              endAt: now.add(const Duration(seconds: 100)),
              fastRound: true,
              now: now),
          PredictionsFundingBlock.closing);
      expect(
          predictionsFundingBlock(
              endAt: now.add(const Duration(minutes: 3)),
              fastRound: true,
              now: now),
          isNull);
    });

    test('not taking orders, or a short round past its end: ended', () {
      expect(
          predictionsFundingBlock(
              market: const PolymarketMarketWindow(
                  acceptingOrders: false, closed: false),
              endAt: now.add(const Duration(hours: 2)),
              fastRound: false,
              now: now),
          PredictionsFundingBlock.ended);
      expect(
          predictionsFundingBlock(
              endAt: now.subtract(const Duration(seconds: 1)),
              fastRound: true,
              now: now),
          PredictionsFundingBlock.ended);
    });

    test('a longer market past its display end still trades', () {
      expect(
          predictionsFundingBlock(
              market: const PolymarketMarketWindow(
                  acceptingOrders: true, closed: false),
              endAt: now.subtract(const Duration(days: 3)),
              fastRound: false,
              now: now),
          isNull);
    });

    test('pre-funding needs the market read; Confirm does not', () {
      expect(
          predictionsFundingBlock(
              endAt: now.add(const Duration(hours: 1)),
              fastRound: true,
              requireRead: true,
              now: now),
          PredictionsFundingBlock.unread);
      expect(
          predictionsFundingBlock(
              endAt: now.add(const Duration(hours: 1)),
              fastRound: true,
              now: now),
          isNull);
    });

    test('Confirm needing a top-up on a closing market moves nothing',
        () async {
      final rig = _Rig()..notNeeded = true;
      await rig.prefund.holdFired(_slip);
      rig
        ..notNeeded = false
        ..block = PredictionsFundingBlock.closing;
      final result = await rig.prefund.confirm(_slip(ready: 12, balance: 12));
      expect(result, isA<PrefundBlocked>());
      expect((result as PrefundBlocked).block, PredictionsFundingBlock.closing);
      expect(rig.funded, hasLength(1));
    });
  });

  group('slips on ended markets', () {
    final now = DateTime.utc(2026, 10, 13, 12);

    test('a short round past its end never opens', () {
      expect(
          polymarketSlipEnded(
              slug: 'btc-updown-5m-1760356800',
              question: 'Bitcoin Up or Down',
              endAt: now.subtract(const Duration(seconds: 5)),
              now: now),
          isTrue);
      expect(
          polymarketSlipEnded(
              slug: 'btc-updown-5m-1760356800',
              question: 'Bitcoin Up or Down',
              endAt: now.add(const Duration(minutes: 3)),
              now: now),
          isFalse);
    });

    test('a closed or ended event never opens; a long market past its date does',
        () {
      expect(
          polymarketSlipEnded(
              event: const PolymarketEvent(
                  id: '1',
                  title: 'Final',
                  slug: 'final',
                  volume: 0,
                  liquidity: 0,
                  category: 'sports',
                  conditionId: '',
                  outcomes: [],
                  closed: true),
              now: now),
          isTrue);
      expect(
          polymarketSlipEnded(
              question: 'Who wins the election?',
              endAt: now.subtract(const Duration(days: 10)),
              now: now),
          isFalse);
    });

    test('market kinds', () {
      expect(
          prefundMarketKind(
              slug: 'eth-updown-15m-1760356800', live: false, now: now),
          PrefundMarketKind.short);
      expect(prefundMarketKind(slug: 'nba-lal-bos', live: true, now: now),
          PrefundMarketKind.live);
      expect(prefundMarketKind(slug: 'nba-lal-bos', live: false, now: now),
          isNull);
    });
  });
}
