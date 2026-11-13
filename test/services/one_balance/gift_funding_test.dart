// A claimed gift funded like an order (one_balance/gift_funding.dart): the
// order of sources for a Dollars destination, the reach the slip judges an
// amount against, one approval binding the payment and the leg, nothing paid
// when a leg stops, and no second leg or second payment through a retry, a
// restart at each point, or two prompts at once. Fakes only: no SDK, no
// Orchestra, no live endpoint.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/models/orchestra_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/settlement_operation.dart' show SettlementFlow;
import 'package:kute/models/share_link_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceReadingProvider;
import 'package:kute/services/funding/settlement_runner.dart';
import 'package:kute/services/one_balance/bitcoin_funded_order.dart';
import 'package:kute/services/one_balance/bitcoin_to_dollars_leg.dart';
import 'package:kute/screens/shared/multi_source_move_activity.dart'
    show multiSourceMoveFinalStepMissing;
import 'package:kute/services/one_balance/gift_funding.dart';
import 'package:kute/services/one_balance/investments_spendable.dart'
    show venueCashLastReadProvider;
import 'package:kute/services/one_balance/move_steps.dart';
import 'package:kute/services/one_balance/multi_source_move.dart';
import 'package:kute/services/one_balance/money_steps.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/order_funding.dart'
    show planOrderSources;
import 'package:kute/services/one_balance/venue_cash_source.dart';
import 'package:kute/services/one_balance/venue_funder.dart'
    show VenueMoveResult;
import 'package:kute/services/orchestra/orchestra_capability_requirements.dart'
    show orchestraCapabilityRequirements;
import 'package:kute/services/orchestra/orchestra_quote_guard.dart';
import 'package:kute/services/runtime_capabilities_service.dart'
    show
        CapabilityDecision,
        RuntimeCapabilitiesService,
        runtimeCapabilitiesProvider;
import 'package:kute/services/share_link_claims.dart';
import 'package:kute/services/share_links_store.dart';
import 'package:kute/services/tracking_service.dart';

import '../../helpers/runtime_policy_fixture.dart';
import '../../mocks/fake_share_links_api.dart';

const _ownSpark =
    'spark1pgss93sy072yrmtad5cy2srwjhq8ekzuw78yhr808jn6htqfh9w8p8h9mfwlv9';
const _foreignSpark =
    'spark1pgssy7d7vel0nh9m4326qc54e6rskpczn07dktww9rv4nu5ptvt0s9uc489gg2';
const _friend = 'spark1qfriendfriendfriendfriendfriendfriendfr';
const _wallet = 'w1';

ClaimedShareLink _claim(String id, int cents) => ClaimedShareLink(
      id: id,
      kind: ShareLinkKind.dollars,
      amountMinor: cents,
      claimDestination: _friend,
    );

VerifiedOrchestraQuote _quote({String id = 'q_btc', int sats = 100000}) =>
    verifyOrchestraQuote(
      OrchestraQuoteRequest(
        sourceChain: 'spark',
        sourceAsset: 'BTC',
        destinationChain: 'spark',
        destinationAsset: 'USDB',
        amountBaseUnits: BigInt.from(sats),
        recipientAddress: _ownSpark,
        refundAddress: _ownSpark,
        recipientKind: RecipientKind.ownSpark,
        ownAddress: _ownSpark,
      ),
      OrchestraQuote.fromJson({
        'quoteId': id,
        'depositAddress': _foreignSpark,
        'amountIn': '$sats',
        'estimatedOut': '${sats * 600}',
        'feeAmount': '0',
        'feeBps': 0,
        'totalFeeAmount': '0',
        'feeAsset': 'USDB',
        'route': ['spark:BTC', 'spark:USDB'],
        'expiresAt': '2026-09-15T12:02:00Z',
        'priceLockMode': 'floating',
      }),
      now: DateTime.utc(2026, 9, 15, 12),
      bounds: OrchestraQuoteBounds.forSource('spark',
          inputValueInOutputUnits: sats * 600.0),
      mainnet: true,
    );

SettlementAuthorizationIntent _settlement(VerifiedOrchestraQuote quote) =>
    SettlementAuthorizationIntent(
      flow: SettlementFlow.moveBtcToUsdc,
      walletId: _wallet,
      destination: '$_ownSpark|v1',
      routeLabel: BitcoinLegGrants.route,
      amountIn: quote.amountIn,
      minReceive: BigInt.one,
      maxFeeBps: 100,
      reviewedQuote: quote,
    );

/// The wallet behind a runner: every balance, every call, and the clock
/// the landing wait runs on. Survives a "restart" (a new runner on it).
class _Wallet {
  _Wallet({this.dollars = 0, this.bitcoinLandUsd = 0, this.venues = const []});

  double dollars;
  double bitcoinLandUsd;
  List<VenueCashCandidate> venues;
  CapabilityDecision? denied;
  bool unlocked = true;
  DateTime now = DateTime(2026, 11, 8, 12);

  final log = <String>[];
  final payments = <(String, BigInt)>[];
  final intents = <SensitiveIntent>[];
  final grants = <AuthGrant>[];
  final legStates = <String, GiftLegState>{};
  final venueSent = <VenueCashPlan>[];

  /// Whether a leg's dollars land while the runner waits on them.
  bool landsLegs = true;
  double landing = 0;
  Object? bitcoinThrows;
  Object? paymentThrows;
  Object? legFails;
  bool decline = false;

  /// Parks the Bitcoin leg forever at this point: an app kill.
  Completer<void>? killBeforeSats;
  Completer<void>? killAfterSats;

  int legCount = 0;

  Future<AuthGrant?> approve(SensitiveIntent intent) async {
    log.add('approve');
    intents.add(intent);
    if (decline) return null;
    final grant = AuthGrants.issue(intent, method: AuthGrantMethod.biometric);
    grants.add(grant);
    return grant;
  }

  Future<BitcoinLegTicket> _send({
    required String sparkAddress,
    required BitcoinLegPlan plan,
    required SettlementStepUpHook stepUp,
    required void Function() onSending,
  }) async {
    legCount++;
    final quoteId = 'q_btc_$legCount';
    final quote = _quote(id: quoteId, sats: plan.sats);
    final thrown = bitcoinThrows;
    if (thrown is SettlementStopped) throw thrown;
    log.add('leg_quote');
    if (!await stepUp(_settlement(quote))) {
      throw const SettlementStopped(SettlementStopReason.declined);
    }
    if (killBeforeSats != null) await killBeforeSats!.future;
    if (thrown != null) throw thrown;
    onSending();
    log.add('leg_sats');
    bitcoinLandUsd = 0;
    legStates[quoteId] = GiftLegState.onItsWay;
    landing += plan.targetUsd;
    lastLegRef = quoteId;
    if (killAfterSats != null) await killAfterSats!.future;
    return BitcoinLegTicket(
      quoteId: quoteId,
      sats: plan.sats,
      estimatedOutUsd: plan.targetUsd,
      minOutUsd: plan.targetUsd,
    );
  }

  String? lastLegRef;

  /// The money that was on its way lands.
  void land() {
    dollars += landing;
    landing = 0;
    final ref = lastLegRef;
    if (ref != null) legStates[ref] = GiftLegState.delivered;
    log.add('landed');
  }

  GiftFundingEnv env() => GiftFundingEnv(
        walletId: () => _wallet,
        dollarsNow: () => dollars,
        freshDollars: () async => dollars,
        bitcoinDenied: () async => denied,
        venueSources: () async => venues,
        decide: ({
          required double fundUsd,
          required double dollarsUsd,
          required double otherVenueUsd,
          required bool investmentsCover,
        }) async {
          // The real split, as `decideOrderSources` makes it; a real sizing
          // needs a wallet, so the plan's own target is sized here.
          final split = planOrderSources(
            fundUsd: fundUsd,
            dollarsUsd: dollarsUsd,
            bitcoinMaxUsd: bitcoinLandUsd,
            otherVenueUsd: otherVenueUsd,
          );
          if (split.bitcoinUsd <= 0 && split.otherVenueUsd <= 0) {
            return split.covers
                ? const OrderSources(OrderSourceRoute.dollars)
                : const OrderSources(OrderSourceRoute.insufficient);
          }
          if (!split.covers) {
            return const OrderSources(OrderSourceRoute.insufficient);
          }
          if (split.bitcoinUsd <= 0) {
            return OrderSources(OrderSourceRoute.otherVenue,
                otherVenueUsd: split.otherVenueUsd);
          }
          return OrderSources(OrderSourceRoute.bitcoin,
              bitcoinUsd: split.bitcoinUsd,
              otherVenueUsd: split.otherVenueUsd,
              plan: BitcoinLegPlan(
                dollarsShortUsd: split.bitcoinUsd,
                targetUsd: split.bitcoinUsd,
                sats: 100000,
                maxSats: 105000,
                usdPerBtc: 60000,
              ));
        },
        ownSpark: () async => _ownSpark,
        sendBitcoin: _send,
        pullVenue: (plan, {required onStarted, required onLeg}) async {
          venueSent.add(plan);
          log.add('venue_legs');
          onStarted('msm_1');
          final legs = <VenueCashLegOutcome>[];
          for (final p in plan.pulls) {
            final failed = legFails;
            final leg = failed != null
                ? VenueCashLegOutcome(pull: p, error: failed)
                : VenueCashLegOutcome(
                    pull: p,
                    result: VenueMoveResult(
                        quoteId: 'q_${p.venue.name}',
                        orderId: 'ord_${p.venue.name}',
                        sentUsd: p.usd,
                        arrivingUsdEstimate: p.arrivingUsd));
            if (failed == null) {
              landing += p.arrivingUsd;
              legStates['ord_${p.venue.name}'] = GiftLegState.onItsWay;
            }
            onLeg(leg);
            legs.add(leg);
          }
          return VenueCashPullOutcome(
              plan: plan, legs: legs, dollarsCover: false, eta: plan.eta);
        },
        legState: (ref) async => legStates[ref] ?? GiftLegState.onItsWay,
        payDollars: (destination, amount) async {
          log.add('pay');
          final thrown = paymentThrows;
          if (thrown != null) throw thrown;
          payments.add((destination, amount));
          dollars -= amount.toDouble() / 1e6;
          return 'pay_${payments.length}';
        },
        sessionUnlocked: () => unlocked,
        sleep: (d) async {
          now = now.add(d);
          if (landsLegs && landing > 0) land();
          await Future<void>.delayed(Duration.zero);
        },
        clock: () => now,
        pollEvery: const Duration(seconds: 1),
      );

  GiftFundingRunner runner() => GiftFundingRunner(env());
}

VenueCashCandidate _venue(OneBalanceVenue venue, double usd) => (
      venue: venue,
      availableUsd: usd,
      eta: const Duration(minutes: 1),
      minimumUsd: 1.0,
    );

List<MoneyStep> _legs(String id) => [
      for (final s in ShareLinksStore.byId(id)!.funding!.steps.legs)
        if (s.id != kGiftFundingSendId) s,
    ];

void main() {
  late List<(String, Map<String, Object>?)> events;

  setUp(() {
    ShareLinksStore.debugMemory = <String, String>{};
    GiftFundingRunner.debugReset();
    TrackingService.setDisabled(true);
    events = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    AuthGrants.clock = DateTime.now;
  });

  tearDown(() {
    TrackingService.debugTrackObserver = null;
    ShareLinksStore.debugMemory = null;
  });

  group('the order of sources for a Dollars destination', () {
    test('Dollars, then Bitcoin, the venues only for the remainder', () {
      final plan = planGiftFunding(
        amountUsd: 50,
        dollarsUsd: 10,
        bitcoinMaxUsd: 25,
        sources: [_venue(OneBalanceVenue.investing, 40)],
      );
      expect(plan.dollarsUsd, 10);
      expect(plan.bitcoinUsd, 25);
      expect(plan.pulls.single.venue, OneBalanceVenue.investing);
      expect(plan.pulls.single.arrivingUsd, greaterThanOrEqualTo(15));
      expect(plan.covers, isTrue);
      expect(plan.fees.legs.length, 2);
    });

    test('Bitcoin covering it never touches venue cash, though it costs', () {
      final plan = planGiftFunding(
        amountUsd: 20,
        dollarsUsd: 0,
        bitcoinMaxUsd: 100,
        sources: [_venue(OneBalanceVenue.predictions, 100)],
      );
      expect(plan.bitcoinUsd, 20);
      expect(plan.pulls, isEmpty);
      expect(plan.fees.totalUsd, greaterThan(0));
    });

    test('a rest under the route minimum is raised to it', () {
      final plan = planGiftFunding(
          amountUsd: 10,
          dollarsUsd: 9.5,
          bitcoinMaxUsd: 100,
          sources: const []);
      expect(plan.bitcoinUsd, 1);
      expect(plan.covers, isTrue);
    });

    test('Dollars enough moves nothing', () {
      final plan = planGiftFunding(
          amountUsd: 10,
          dollarsUsd: 10,
          bitcoinMaxUsd: 100,
          sources: [_venue(OneBalanceVenue.investing, 40)]);
      expect(plan.needsFunding, isFalse);
      expect(plan.fees.isEmpty, isTrue);
    });
  });

  group('the reach the slip judges against', () {
    test('Dollars plus what Bitcoin lands plus venue cash net of its moves',
        () {
      final reach = giftReachUsd(
        dollarsUsd: 10,
        bitcoinMaxUsd: 20,
        sources: [_venue(OneBalanceVenue.predictions, 100)],
      );
      // 2% of the venue's cash is its route's cost.
      expect(reach, closeTo(128, 0.5));
      expect(reach, lessThan(130));
    });

    test('every Max is an amount the plan covers', () {
      for (final dollars in [0.0, 3.21, 50.0]) {
        for (final bitcoin in [0.0, 0.5, 1.0, 17.33]) {
          for (final cash in [0.0, 0.5, 2.0, 73.1]) {
            final sources = [_venue(OneBalanceVenue.investing, cash)];
            final reach = giftReachUsd(
                dollarsUsd: dollars, bitcoinMaxUsd: bitcoin, sources: sources);
            if (reach <= 0) continue;
            final plan = planGiftFunding(
                amountUsd: reach,
                dollarsUsd: dollars,
                bitcoinMaxUsd: bitcoin >= 1 ? bitcoin : 0,
                sources: sources);
            expect(plan.covers, isTrue,
                reason: 'D $dollars B $bitcoin V $cash → $reach');
          }
        }
      }
    });

    test('Bitcoin under the route minimum counts for nothing', () {
      expect(giftReachUsd(dollarsUsd: 5, bitcoinMaxUsd: 0.5, sources: const []),
          5);
    });
  });

  group('Send now', () {
    test('Dollars enough: no leg, today\'s approval, one payment', () async {
      final w = _Wallet(dollars: 50);
      final id = await w.runner().pay(_claim('a', 2000), approve: w.approve);
      expect(id, 'pay_1');
      expect(w.log, ['approve', 'pay']);
      final intent = w.intents.single;
      expect(intent.action, SensitiveAction.send);
      expect(intent.destination, _friend);
      expect(intent.asset, 'USDB');
      expect(intent.amountMax, BigInt.from(20000000));
      expect(intent.limits.containsKey(VenueLimit.fundBtc), isFalse);
      expect(intent.ttl, AuthGrants.defaultTtl);
      expect(w.grants.single.consumed, isTrue);
      expect(ShareLinksStore.byId('a')!.paymentId, 'pay_1');
      expect(ShareLinksStore.byId('a')!.funding, isNull);
      expect(events.where((e) => e.$1.startsWith('order_funding')), isEmpty);
      final paid = events.singleWhere((e) => e.$1 == 'share_link_paid').$2!;
      expect(paid['funded'], false);
      expect(paid['amount_usd'], 20.0);
    });

    test(
        'Bitcoin covers the shortfall: one approval binds the leg, the leg '
        'lands, then the payment', () async {
      final w = _Wallet(dollars: 5, bitcoinLandUsd: 40);
      final id = await w.runner().pay(_claim('a', 2000), approve: w.approve);
      expect(id, 'pay_1');
      expect(w.log.where((e) => e == 'approve'), hasLength(1));
      expect(w.log.indexOf('leg_sats'), lessThan(w.log.indexOf('landed')));
      expect(w.log.indexOf('landed'), lessThan(w.log.indexOf('pay')));
      expect(w.legCount, 1);

      final intent = w.intents.single;
      final bound = intent.limits[VenueLimit.fundBtc]! as Map;
      expect(bound['route'], BitcoinLegGrants.route);
      expect(bound['to'], _ownSpark);
      expect(bound['maxSats'], '105000');
      expect(intent.ttl, kGiftFundingGrantTtl);
      expect(w.grants.single.consumed, isTrue);
      expect(BitcoinLegGrants.takenBy(w.grants.single), isTrue);

      final row = ShareLinksStore.byId('a')!;
      expect(row.paymentId, 'pay_1');
      expect(row.status, ShareLinkStatus.paid);
      final funding = row.funding!;
      final leg = funding.steps.byId('leg:bitcoin')!;
      expect(leg.from, MoneyPlace.bitcoin);
      expect(leg.to, MoneyPlace.dollars);
      expect(leg.usd, 15);
      expect(leg.status, MoneyStepStatus.done);
      expect(leg.ref, 'q_btc_1');
      expect(
          funding.steps.byId(kGiftFundingSendId)!.status, MoneyStepStatus.done);

      final names = events.map((e) => e.$1).toList();
      expect(
          names,
          containsAllInOrder([
            'order_funding_started',
            'order_funding_step',
            'order_funding_submitted',
            'share_link_paid',
            'order_funding_completed',
          ]));
      final started =
          events.firstWhere((e) => e.$1 == 'order_funding_started').$2!;
      expect(started['venue'], 'wallet');
      expect(started['entry_source'], 'share_link');
      expect(started['funding_source'], 'bitcoin');
      expect(started['fund_usd'], 15.0);
      final paid = events.singleWhere((e) => e.$1 == 'share_link_paid').$2!;
      expect(paid['funded'], true);
      expect(paid['funding_sources'], 'bitcoin');
      // Never an id, an address or a payment id.
      for (final e in events) {
        final text = '${e.$2}';
        expect(text.contains(_friend), isFalse);
        expect(text.contains(_ownSpark), isFalse);
        expect(text.contains('pay_1'), isFalse);
        expect(text.contains('q_btc'), isFalse);
      }
    });

    test('a send grant covers its own leg and nothing else', () async {
      final w = _Wallet(dollars: 5, bitcoinLandUsd: 40);
      final intent = SensitiveIntent(
        action: SensitiveAction.send,
        walletId: _wallet,
        venue: 'spark',
        destination: _friend,
        asset: 'USDB',
        amountMax: BigInt.from(20000000),
        limits: {
          VenueLimit.fundBtc:
              BitcoinLegGrants.limit(maxSats: 105000, ownSpark: _ownSpark),
        },
      );
      final grant = (await w.approve(intent))!;
      expect(
          BitcoinLegGrants.covers(grant, _settlement(_quote()),
              ownSpark: _ownSpark),
          isTrue);
      // More sats than it binds.
      expect(
          BitcoinLegGrants.covers(grant, _settlement(_quote(sats: 105001)),
              ownSpark: _ownSpark),
          isFalse);
      // A plain send's grant binds no leg.
      final plain = (await w.approve(SensitiveIntent(
        action: SensitiveAction.send,
        walletId: _wallet,
        venue: 'spark',
        destination: _friend,
        asset: 'USDB',
        amountMax: BigInt.from(20000000),
      )))!;
      expect(
          BitcoinLegGrants.covers(plain, _settlement(_quote()),
              ownSpark: _ownSpark),
          isFalse);
    });

    test(
        'venue cash in the plan: Dollars and Bitcoin first, its legs for '
        'the rest only', () async {
      final w = _Wallet(dollars: 10, bitcoinLandUsd: 20, venues: [
        _venue(OneBalanceVenue.predictions, 60),
      ]);
      final id = await w.runner().pay(_claim('a', 5000), approve: w.approve);
      expect(id, 'pay_1');
      expect(w.legCount, 1);
      final plan = w.venueSent.single;
      // Only what comes home is that move: its Activity row says so.
      expect(plan.neededUsd, 20);
      expect(plan.dollarsUsd, 0);
      expect(plan.pulls.single.venue, OneBalanceVenue.predictions);
      expect(plan.pulls.single.arrivingUsd, greaterThanOrEqualTo(20));
      final row = ShareLinksStore.byId('a')!;
      expect(row.funding!.moveId, 'msm_1');
      expect(row.funding!.steps.byId('leg:predictions')!.status,
          MoneyStepStatus.done);
      final started =
          events.firstWhere((e) => e.$1 == 'order_funding_started').$2!;
      expect(started['funding_source'], 'bitcoin,venue_cash');
      expect(started['other_venue_used'], true);
    });

    test('nothing reaches it: refused before any approval, nothing moved',
        () async {
      final w = _Wallet(dollars: 5, bitcoinLandUsd: 2);
      await expectLater(w.runner().pay(_claim('a', 2000), approve: w.approve),
          throwsA(isA<GiftFundingRefused>()));
      expect(w.log, isEmpty);
      expect(ShareLinksStore.byId('a'), isNull);
      final failed =
          events.singleWhere((e) => e.$1 == 'order_funding_failed').$2!;
      expect(failed['stage'], 'plan');
    });

    test('declined: nothing quoted, nothing recorded, the prompt returns',
        () async {
      final w = _Wallet(dollars: 5, bitcoinLandUsd: 40)..decline = true;
      expect(
          await w.runner().pay(_claim('a', 2000), approve: w.approve), isNull);
      expect(w.log, ['approve']);
      expect(w.legCount, 0);
      expect(ShareLinksStore.byId('a'), isNull);
      expect(GiftFundingRunner.isRunning('a'), isFalse);
    });

    test(
        'a leg that never left: nothing paid, the money stays, a new tap '
        'tries again', () async {
      final w = _Wallet(dollars: 5, bitcoinLandUsd: 40)
        ..bitcoinThrows =
            const SettlementStopped(SettlementStopReason.routeUnavailable);
      await expectLater(w.runner().pay(_claim('a', 2000), approve: w.approve),
          throwsA(isA<GiftFundingStopped>()));
      expect(w.log.contains('pay'), isFalse);
      expect(w.dollars, 5);
      expect(ShareLinksStore.byId('a')!.paymentId, isNull);
      expect(_legs('a').single.status, MoneyStepStatus.failed);
      expect(w.grants.single.revoked, isTrue);
      expect(events.singleWhere((e) => e.$1 == 'order_funding_failed').$2!,
          containsPair('stage', 'funding'));

      w.bitcoinThrows = null;
      w.log.clear();
      expect(
          await w.runner().pay(_claim('a', 2000), approve: w.approve), 'pay_1');
      expect(w.legCount, 2);
      expect(w.payments, hasLength(1));
    });

    test(
        'Orchestra refunds the leg while it is waited on: nothing paid, the '
        'next tap plans again', () async {
      final w = _Wallet(dollars: 5, bitcoinLandUsd: 40)..landsLegs = false;
      final env = w.env();
      final run = GiftFundingRunner(GiftFundingEnv(
        walletId: env.walletId,
        dollarsNow: env.dollarsNow,
        freshDollars: env.freshDollars,
        bitcoinDenied: env.bitcoinDenied,
        venueSources: env.venueSources,
        decide: env.decide,
        ownSpark: env.ownSpark,
        sendBitcoin: env.sendBitcoin,
        pullVenue: env.pullVenue,
        legState: (ref) async => GiftLegState.failed,
        payDollars: env.payDollars,
        sessionUnlocked: env.sessionUnlocked,
        sleep: env.sleep,
        clock: env.clock,
      )).pay(_claim('a', 2000), approve: w.approve);
      await expectLater(run, throwsA(isA<GiftFundingStopped>()));
      expect(w.log.contains('pay'), isFalse);
      expect(_legs('a').single.status, MoneyStepStatus.failed);
      expect(_legs('a').single.reason, 'refunded');
    });

    test(
        'an outcome nobody can tell: it stays on its way and is never sent '
        'again', () async {
      final w = _Wallet(dollars: 5, bitcoinLandUsd: 40)
        ..landsLegs = false
        ..bitcoinThrows =
            SettlementFundingUnknown('op_1', StateError('network'));
      await expectLater(w.runner().pay(_claim('a', 2000), approve: w.approve),
          throwsA(isA<GiftFundingStopped>()));
      expect(_legs('a').single.status, MoneyStepStatus.running);
      expect(_legs('a').single.ref, 'q_btc_1');

      // A tap asks a new approval for the payment alone, and waits on it.
      w.bitcoinThrows = null;
      w.landsLegs = true;
      w.landing = 15;
      w.lastLegRef = 'q_btc_1';
      w.log.clear();
      expect(
          await w.runner().pay(_claim('a', 2000), approve: w.approve), 'pay_1');
      expect(w.legCount, 1);
      expect(w.intents.last.limits.containsKey(VenueLimit.fundBtc), isFalse);
    });

    test(
        'the payment fails after the leg: the money is in Dollars, a retry '
        'pays with no second leg', () async {
      final w = _Wallet(dollars: 5, bitcoinLandUsd: 40)
        ..paymentThrows = StateError('refused');
      await expectLater(w.runner().pay(_claim('a', 2000), approve: w.approve),
          throwsA(isA<StateError>()));
      expect(w.dollars, 20);
      expect(ShareLinksStore.byId('a')!.paymentId, isNull);
      final record = ShareLinksStore.byId('a')!.funding!;
      expect(record.steps.byId('leg:bitcoin')!.status, MoneyStepStatus.done);
      expect(record.steps.byId(kGiftFundingSendId)!.status,
          MoneyStepStatus.failed);
      expect(record.reason, 'payment');

      w.paymentThrows = null;
      w.log.clear();
      expect(
          await w.runner().pay(_claim('a', 2000), approve: w.approve), 'pay_1');
      expect(w.log, ['approve', 'pay']);
      expect(w.legCount, 1);
      expect(w.intents.last.limits.containsKey(VenueLimit.fundBtc), isFalse);
      expect(
          ShareLinksStore.byId('a')!
              .funding!
              .steps
              .byId(kGiftFundingSendId)!
              .status,
          MoneyStepStatus.done);
    });

    test('a lock while the legs ran: nothing paid, the money in Dollars',
        () async {
      final w = _Wallet(dollars: 5, bitcoinLandUsd: 40)..unlocked = false;
      await expectLater(w.runner().pay(_claim('a', 2000), approve: w.approve),
          throwsA(isA<GiftFundingStopped>()));
      expect(w.log.contains('pay'), isFalse);
      expect(w.dollars, 20);
      expect(w.grants.single.revoked, isTrue);
    });

    test('legs that do not land in time: it stops, they keep going', () async {
      final w = _Wallet(dollars: 5, bitcoinLandUsd: 40)..landsLegs = false;
      await expectLater(
          w.runner().pay(_claim('a', 2000), approve: w.approve),
          throwsA(isA<GiftFundingStopped>()
              .having((e) => e.category, 'category', 'timeout')));
      expect(w.log.contains('pay'), isFalse);
      expect(_legs('a').single.status, MoneyStepStatus.running);
    });

    test('a second tap while a run is on is that run: one payment', () async {
      final w = _Wallet(dollars: 5, bitcoinLandUsd: 40);
      final runner = w.runner();
      final first = runner.pay(_claim('a', 2000), approve: w.approve);
      expect(GiftFundingRunner.isRunning('a'), isTrue);
      final second = runner.pay(_claim('a', 2000), approve: w.approve);
      expect(await first, 'pay_1');
      expect(await second, 'pay_1');
      expect(w.payments, hasLength(1));
      expect(w.intents, hasLength(1));
      expect(GiftFundingRunner.isRunning('a'), isFalse);
    });

    test('a row already paid is never paid again', () async {
      final w = _Wallet(dollars: 50);
      ShareLinksStore.recordPaid(_claim('a', 2000), 'pay_old');
      expect(await w.runner().pay(_claim('a', 2000), approve: w.approve),
          'pay_old');
      expect(w.log, isEmpty);
    });
  });

  group('an app restart', () {
    void restart() => GiftFundingRunner.debugReset();

    test('before the leg was even quoted: nothing moved, it plans again',
        () async {
      final w = _Wallet(dollars: 5, bitcoinLandUsd: 40);
      // The record is written and the process dies in the leg's quote.
      ShareLinksStore.setFunding(
        _claim('a', 2000),
        GiftFundingRecord(
          startedAt: w.now,
          landsUsd: const {'leg:bitcoin': 15},
          steps: MoneyStepGraph([
            MoneyStep(
                id: 'leg:bitcoin',
                kind: MoneyStepKind.leg,
                from: MoneyPlace.bitcoin,
                to: MoneyPlace.dollars,
                usd: 15,
                status: MoneyStepStatus.running,
                startedAt: w.now),
          ]),
        ),
      );
      restart();
      expect(
          await w.runner().pay(_claim('a', 2000), approve: w.approve), 'pay_1');
      expect(w.legCount, 1);
      expect(w.payments, hasLength(1));
    });

    test('its quote named but no sats left (never broadcast): it plans again',
        () async {
      final w = _Wallet(dollars: 5, bitcoinLandUsd: 40)
        ..killBeforeSats = Completer<void>();
      unawaited(w
          .runner()
          .pay(_claim('a', 2000), approve: w.approve)
          .catchError((_) => null));
      await pumpEventQueue();
      expect(_legs('a').single.ref, 'q_btc_1');

      restart();
      w.killBeforeSats = null;
      w.legStates['q_btc_1'] = GiftLegState.notSent;
      w.landing = 0;
      w.log.clear();
      expect(
          await w.runner().pay(_claim('a', 2000), approve: w.approve), 'pay_1');
      expect(w.legCount, 2);
      expect(w.payments, hasLength(1));
    });

    test(
        'the leg on its way: it resumes, never repeats, under a new approval '
        'for the payment alone', () async {
      final w = _Wallet(dollars: 5, bitcoinLandUsd: 40)
        ..killAfterSats = Completer<void>()
        ..landsLegs = false;
      unawaited(w
          .runner()
          .pay(_claim('a', 2000), approve: w.approve)
          .catchError((_) => null));
      await pumpEventQueue();
      expect(w.log, contains('leg_sats'));
      expect(_legs('a').single.status, MoneyStepStatus.running);
      expect(w.payments, isEmpty);

      restart();
      w.killAfterSats = null;
      w.landsLegs = true;
      w.log.clear();
      final resumed = w.runner();
      expect(await resumed.pay(_claim('a', 2000), approve: w.approve), 'pay_1');
      expect(w.legCount, 1);
      expect(w.log.first, 'approve');
      expect(w.log, isNot(contains('leg_quote')));
      expect(w.intents.last.limits.containsKey(VenueLimit.fundBtc), isFalse);
      // The one approval still outlives the wait.
      expect(w.intents.last.ttl, kGiftFundingGrantTtl);
      expect(w.payments, hasLength(1));
      final started =
          events.lastWhere((e) => e.$1 == 'order_funding_started').$2!;
      expect(started['resumed'], true);
    });

    test('after a leg landed, before the payment: it pays, no second leg',
        () async {
      final w = _Wallet(dollars: 5, bitcoinLandUsd: 40)
        ..killAfterSats = Completer<void>()
        ..landsLegs = false;
      unawaited(w
          .runner()
          .pay(_claim('a', 2000), approve: w.approve)
          .catchError((_) => null));
      await pumpEventQueue();

      restart();
      w.killAfterSats = null;
      w.land();
      w.log.clear();
      expect(
          await w.runner().pay(_claim('a', 2000), approve: w.approve), 'pay_1');
      expect(w.legCount, 1);
      expect(w.log, ['approve', 'pay']);
      expect(w.intents.last.limits.containsKey(VenueLimit.fundBtc), isFalse);
      expect(w.payments, hasLength(1));
    });

    test('a venue leg on its way: followed, never pulled again', () async {
      final w = _Wallet(dollars: 0, venues: [
        _venue(OneBalanceVenue.predictions, 60),
      ]);
      ShareLinksStore.setFunding(
        _claim('a', 2000),
        GiftFundingRecord(
          startedAt: w.now,
          moveId: 'msm_old',
          landsUsd: const {'leg:predictions': 20},
          steps: MoneyStepGraph([
            MoneyStep(
                id: 'leg:predictions',
                kind: MoneyStepKind.leg,
                from: MoneyPlace.predictions,
                to: MoneyPlace.dollars,
                usd: 20.5,
                status: MoneyStepStatus.running,
                startedAt: w.now,
                ref: 'ord_predictions'),
          ]),
        ),
      );
      restart();
      w.landing = 20;
      w.lastLegRef = 'ord_predictions';
      expect(
          await w.runner().pay(_claim('a', 2000), approve: w.approve), 'pay_1');
      expect(w.venueSent, isEmpty);
      expect(w.payments, hasLength(1));
      expect(ShareLinksStore.byId('a')!.funding!.moveId, 'msm_old');
    });

    test('Dollars still loading are not taken for none: no swap, no approval',
        () async {
      final w = _Wallet(dollars: 0, bitcoinLandUsd: 40);
      final env = w.env();
      final run = GiftFundingRunner(GiftFundingEnv(
        walletId: env.walletId,
        dollarsNow: env.dollarsNow,
        freshDollars: () async => null,
        dollarsKnown: () => false,
        bitcoinDenied: env.bitcoinDenied,
        venueSources: env.venueSources,
        decide: env.decide,
        ownSpark: env.ownSpark,
        sendBitcoin: env.sendBitcoin,
        pullVenue: env.pullVenue,
        legState: env.legState,
        payDollars: env.payDollars,
        sessionUnlocked: env.sessionUnlocked,
        sleep: env.sleep,
        clock: env.clock,
      )).pay(_claim('a', 2000), approve: w.approve);
      await expectLater(
          run,
          throwsA(isA<GiftFundingRefused>()
              .having((e) => e.category, 'category', 'balance_unknown')));
      expect(w.log, isEmpty);
      expect(w.legCount, 0);
    });

    test('paid but not reported: POST /paid is retried, the send is not',
        () async {
      final w = _Wallet(dollars: 5, bitcoinLandUsd: 40);
      expect(
          await w.runner().pay(_claim('a', 2000), approve: w.approve), 'pay_1');
      restart();
      final api = FakeShareLinksApi();
      api.claimedForMe.add(_claim('a', 2000));
      var prompted = 0;
      ShareLinkClaims.debugReset();
      ShareLinkClaims.debugPrompt = (_, __) async => prompted++;
      addTearDown(() => ShareLinkClaims.debugPrompt = null);
      await ShareLinkClaims.check(
        read: <T>(p) => api as T,
        contextOf: () => null,
        trigger: 'test',
      );
      expect(prompted, 0);
      expect(api.calls.any((c) => c.$1 == 'markPaid'), isTrue);
      expect(ShareLinksStore.byId('a')!.paidReported, isTrue);
      expect(w.payments, hasLength(1));
    });

    test('the record survives its own JSON', () async {
      final w = _Wallet(dollars: 5, bitcoinLandUsd: 40)
        ..killAfterSats = Completer<void>()
        ..landsLegs = false;
      unawaited(w
          .runner()
          .pay(_claim('a', 2000), approve: w.approve)
          .catchError((_) => null));
      await pumpEventQueue();
      final row =
          PendingShareLink.fromJson(ShareLinksStore.byId('a')!.toJson())!;
      expect(row.funding!.onItsWay, isTrue);
      expect(row.funding!.landsUsd['leg:bitcoin'], 15);
      expect(row.funding!.steps.byId('leg:bitcoin')!.ref, 'q_btc_1');
      expect(
          row.funding!.steps.byId(kGiftFundingSendId)!.after, ['leg:bitcoin']);
    });
  });

  group('a swap blocked for this person', () {
    const denied = CapabilityDecision(allowed: false, reason: 'country_rule');

    test(
        'Bitcoin cannot fund it: the shared refusal, the link stays payable '
        'when Dollars arrive', () async {
      final w = _Wallet(dollars: 5, bitcoinLandUsd: 40)..denied = denied;
      await expectLater(
          w.runner().pay(_claim('a', 2000), approve: w.approve),
          throwsA(isA<GiftFundingRefused>()
              .having((e) => e.denied, 'denied', denied)));
      expect(w.legCount, 0);
      expect(w.log, isEmpty);

      w.dollars = 25;
      expect(
          await w.runner().pay(_claim('a', 2000), approve: w.approve), 'pay_1');
      expect(w.legCount, 0);
    });

    test('venue cash answers to its own capabilities and still funds it',
        () async {
      final w = _Wallet(dollars: 5, bitcoinLandUsd: 40, venues: [
        _venue(OneBalanceVenue.predictions, 60),
      ])
        ..denied = denied;
      expect(
          await w.runner().pay(_claim('a', 2000), approve: w.approve), 'pay_1');
      expect(w.legCount, 0);
      expect(w.venueSent, hasLength(1));
      expect(w.intents.single.limits.containsKey(VenueLimit.fundBtc), isFalse);
    });
  });

  group('prompts at once', () {
    test('two prompts never spend the same Dollars', () async {
      final w = _Wallet(dollars: 50);
      final runner = w.runner();
      final first = runner.pay(_claim('a', 3000), approve: w.approve);
      final second = runner.pay(_claim('b', 3000), approve: w.approve);
      expect(await first, 'pay_1');
      await expectLater(second, throwsA(isA<GiftFundingRefused>()));
      expect(w.payments, hasLength(1));
      expect(w.dollars, 20);
    });

    test('the later prompt funds its own shortfall on what is left', () async {
      final w = _Wallet(dollars: 50, bitcoinLandUsd: 40);
      final runner = w.runner();
      final results = await Future.wait([
        runner.pay(_claim('a', 3000), approve: w.approve),
        runner.pay(_claim('b', 3000), approve: w.approve),
      ]);
      expect(results, ['pay_1', 'pay_2']);
      expect(w.legCount, 1);
      expect(ShareLinksStore.byId('b')!.funding!.steps.byId('leg:bitcoin')!.usd,
          10);
      expect(ShareLinksStore.byId('a')!.funding, isNull);
      expect(w.dollars, closeTo(0, 1e-6));
    });

    test('a link whose leg landed keeps its Dollars from the next prompt',
        () async {
      final w = _Wallet(dollars: 0, bitcoinLandUsd: 40)
        ..paymentThrows = StateError('refused');
      ShareLinksStore.put(PendingShareLink(
        id: 'a',
        kind: ShareLinkKind.dollars,
        amountMinor: 2000,
        url: '',
        createdAt: w.now,
        status: ShareLinkStatus.claimed,
      ));
      await expectLater(w.runner().pay(_claim('a', 2000), approve: w.approve),
          throwsA(isA<StateError>()));
      expect(w.dollars, 20);

      // Those $20 are A's: B has nothing to pay from.
      w.paymentThrows = null;
      w.bitcoinLandUsd = 0;
      await expectLater(w.runner().pay(_claim('b', 1000), approve: w.approve),
          throwsA(isA<GiftFundingRefused>()));
      expect(
          await w.runner().pay(_claim('a', 2000), approve: w.approve), 'pay_1');
    });
  });

  group('giftSpendableProvider', () {
    ProviderContainer container(
        {double? dollars,
        double bitcoin = 20,
        List<VenueCashCandidate>? venues,
        required RuntimeCapabilitiesService policy}) {
      final c = ProviderContainer(overrides: [
        usdBalanceReadingProvider.overrideWithValue(dollars),
        spendingBitcoinLandingUsdProvider.overrideWith((_) => bitcoin),
        settingsProvider.overrideWith((_) => SettingsModel(Settings(
              currency: 'USD',
              language: 'en',
              btcFormat: 'sats',
              backup: false,
              biometricsEnabled: false,
              bitcoinElectrumNode: '',
              nodeType: 'Blockstream',
              reviewDone: true,
            ))),
        runtimeCapabilitiesProvider.overrideWithValue(policy),
        venueCashLastReadProvider.overrideWith(
            (_) => (walletId: null, candidates: venues ?? const [])),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    Future<RuntimeCapabilitiesService> policy(
        {Set<String> blocked = const {}}) async {
      final p = runtimePolicyFixture(blocked: blocked);
      await p.refresh();
      return p;
    }

    test('Dollars not known yet: not judged', () async {
      final c = container(policy: await policy());
      expect(c.read(giftSpendableProvider), isNull);
    });

    test('Dollars, Bitcoin and venue cash together', () async {
      final c = container(
          dollars: 10,
          venues: [_venue(OneBalanceVenue.predictions, 100)],
          policy: await policy());
      expect(c.read(giftSpendableProvider), closeTo(128, 0.5));
    });

    test('a swap blocked: Bitcoin is out, plain Dollars and venue cash stay',
        () async {
      final swap = orchestraCapabilityRequirements(
              sourceChain: 'spark',
              sourceAsset: 'BTC',
              destinationChain: 'spark',
              destinationAsset: 'USDB')
          .toSet();
      final c = container(
          dollars: 10,
          venues: [_venue(OneBalanceVenue.predictions, 100)],
          policy: await policy(blocked: swap));
      expect(c.read(giftSpendableProvider), closeTo(108, 0.5));
    });

    test('a venue whose withdraw is closed is out of reach', () async {
      final c = container(
          dollars: 10,
          venues: [_venue(OneBalanceVenue.predictions, 100)],
          policy: await policy(blocked: const {'polymarket.withdraw'}));
      expect(c.read(giftSpendableProvider), 30);
    });
  });

  test(
      'the venue legs read in Activity as money home to Dollars, the send '
      'being its own row', () {
    final move = MultiSourceMove(
      id: 'msm_1',
      forAction: VenueCashFor.shareLink,
      destination: VenueCashDestination.dollars,
      totalUsd: 20,
      dollarsUsd: 0,
      createdAt: DateTime(2026, 11, 8),
      legs: [
        MultiSourceMoveLeg(
            venue: OneBalanceVenue.predictions,
            usd: 20.5,
            arrivingUsd: 20,
            route: VenueCashRoute.viaDollars,
            ok: true,
            at: DateTime(2026, 11, 8),
            quoteId: 'q_1'),
      ],
    );
    expect(MoveSteps.finalIdFor(move.destination, move.forAction), isNull);
    expect(MoveSteps.of(move).byId(MoveSteps.sendId), isNull);
    expect(
        multiSourceMoveFinalStepMissing(move, const [],
            now: DateTime(2026, 11, 8, 12)),
        isFalse);
  });

  test('a claim whose funding is running is not asked about again', () async {
    final w = _Wallet(dollars: 5, bitcoinLandUsd: 40)
      ..killAfterSats = Completer<void>()
      ..landsLegs = false;
    unawaited(w
        .runner()
        .pay(_claim('a', 2000), approve: w.approve)
        .catchError((_) => null));
    await pumpEventQueue();
    expect(GiftFundingRunner.isRunning('a'), isTrue);
    final api = FakeShareLinksApi();
    api.claimedForMe.add(_claim('a', 2000));
    var prompted = 0;
    ShareLinkClaims.debugReset();
    ShareLinkClaims.debugPrompt = (_, __) async => prompted++;
    addTearDown(() => ShareLinkClaims.debugPrompt = null);
    await ShareLinkClaims.check(
      read: <T>(p) => api as T,
      contextOf: () => null,
      trigger: 'test',
    );
    expect(prompted, 0);
  });
}
