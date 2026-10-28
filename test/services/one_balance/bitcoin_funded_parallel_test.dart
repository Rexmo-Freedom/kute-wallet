// A bet funded from Bitcoin AND the Investing cash (founder, build 84, 25
// October 2026: "it sent from bitcoin and hyperliquid to polymarket.. but
// it could have done both at the same time no?"). Every leg starts at
// once: the Investing cash goes straight into Predictions from the Bitcoin
// leg's accepted quote, never after its landing; only the move from
// Dollars (which carries the Bitcoin's dollars) waits for them, and for
// Dollars to hold the whole move.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/models/orchestra_model.dart';
import 'package:kute/models/settlement_operation.dart' show SettlementFlow;
import 'package:kute/services/funding/settlement_runner.dart'
    show
        SettlementAuthorizationIntent,
        SettlementStepUpHook,
        SettlementStopReason,
        SettlementStopped;
import 'package:kute/services/one_balance/bitcoin_funded_order.dart';
import 'package:kute/services/one_balance/bitcoin_to_dollars_leg.dart';
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/services/one_balance/money_steps.dart';
import 'package:kute/services/one_balance/multi_source_move.dart'
    show MultiSourceMoveStore;
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/order_funding.dart';
import 'package:kute/services/one_balance/venue_cash_source.dart';
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/orchestra/orchestra_quote_guard.dart';
import 'package:kute/services/tracking_service.dart';

const _ownSpark =
    'spark1pgss93sy072yrmtad5cy2srwjhq8ekzuw78yhr808jn6htqfh9w8p8h9mfwlv9';
const _foreignSpark =
    'spark1pgssy7d7vel0nh9m4326qc54e6rskpczn07dktww9rv4nu5ptvt0s9uc489gg2';
final _now = DateTime.utc(2026, 9, 15, 12);

/// The bet: $8.40 to move into Predictions, no Dollars, $5.10 from
/// Bitcoin (via Dollars) and the rest from the Investing cash.
const double _fundUsd = 8.4;
const _plan = BitcoinLegPlan(
  dollarsShortUsd: 5.1,
  targetUsd: 5.1,
  sats: 100000,
  maxSats: 105000,
  usdPerBtc: 60000,
);

const _label = FundedOrderLabel(
  venue: OneBalanceVenue.predictions,
  orderUsd: 8,
  side: 'No',
  market: 'Lakers vs Celtics',
  marketKey: 'tok',
);

VerifiedOrchestraQuote _quote() => verifyOrchestraQuote(
      OrchestraQuoteRequest(
        sourceChain: 'spark',
        sourceAsset: 'BTC',
        destinationChain: 'spark',
        destinationAsset: 'USDB',
        amountBaseUnits: BigInt.from(100000),
        recipientAddress: _ownSpark,
        refundAddress: _ownSpark,
        recipientKind: RecipientKind.ownSpark,
        ownAddress: _ownSpark,
      ),
      OrchestraQuote.fromJson({
        'quoteId': 'q_btc',
        'depositAddress': _foreignSpark,
        'amountIn': '100000',
        'estimatedOut': '${100000 * 600}',
        'feeAmount': '0',
        'feeBps': 0,
        'totalFeeAmount': '0',
        'feeAsset': 'USDB',
        'route': ['spark:BTC', 'spark:USDB'],
        'expiresAt': '2026-09-15T12:02:00Z',
        'priceLockMode': 'floating',
      }),
      now: _now,
      bounds: OrchestraQuoteBounds.forSource('spark',
          inputValueInOutputUnits: 100000 * 600.0),
      mainnet: true,
    );

/// The Investing cash: straight into Predictions within the approval's
/// leg caps ([direct]), or home to Dollars when it cannot go straight.
class _Investing implements VenueCashSource, DirectVenueCashSource {
  _Investing(this.log, {this.straight = true});
  final List<String> log;
  final bool straight;
  double cash = 10;
  final direct = <double>[];
  final home = <double>[];

  @override
  OneBalanceVenue get venue => OneBalanceVenue.investing;

  @override
  Duration get estimatedArrival => const Duration(minutes: 1);

  @override
  Future<double> availableUsd() async => cash;

  @override
  Future<VenueMoveResult> pull(double usd, {required String purpose}) async {
    log.add('investing_home');
    home.add(usd);
    cash -= usd;
    return VenueMoveResult(
        quoteId: 'q_home', orderId: 'ord_home', sentUsd: usd,
        arrivingUsdEstimate: usd);
  }

  @override
  bool canPullTo(VenueCashDestination destination) =>
      straight && destination == VenueCashDestination.predictions;

  @override
  Future<VenueMoveResult> pullTo(VenueCashDestination destination, double usd,
      {required String purpose, required MoveAuthorization auth}) async {
    final grant = (auth as ApprovedLegAuthorization).grant;
    if (!DirectLegGrants.take(grant,
        venue: venue.name,
        destination: destination.code,
        amount: IntentUnits.usd(usd))) {
      throw const DirectRouteRefused('approval_does_not_cover');
    }
    log.add('investing_direct');
    direct.add(usd);
    cash -= usd;
    return VenueMoveResult(
        quoteId: 'q_direct', orderId: 'ord_direct', sentUsd: usd,
        arrivingUsdEstimate: usd);
  }
}

class _Funder implements VenueFunder {
  _Funder(this.log, this.dollars);
  final List<String> log;
  final double Function() dollars;
  final sent = <double>[];
  final dollarsAtSend = <double>[];

  @override
  Future<VenueMoveResult> fund(
      {required double usd,
      required MoveAuthorization auth,
      String purpose = 'order_funding'}) async {
    log.add('dollars_move');
    sent.add(usd);
    dollarsAtSend.add(dollars());
    return VenueMoveResult(
        quoteId: 'q_venue',
        orderId: 'o_venue',
        sentUsd: usd,
        arrivingUsdEstimate: usd);
  }

  @override
  Future<VenueMoveQuote> estimate(double usd) async => VenueMoveQuote(
      arrivingUsd: usd, feeUsd: 0, fixedCostUsd: 0, minUsd: 1, maxUsd: 1000);

  @override
  Future<double> idleUsd() async => 0;

  @override
  Future<double> minimumUsd() async => 1;
}

/// Holds the Bitcoin leg's landing until the test releases it.
class _HeldLanding extends DollarsLandingWatcher {
  _HeldLanding(this.gate)
      : super(
          statusOf: (_) async => null,
          dollarsNow: () => 0,
          freshDollars: () async => null,
          kickSync: () {},
        );
  final Future<DollarsLandingOutcome> gate;

  @override
  Future<DollarsLandingOutcome> watch({
    required String Function() id,
    required double baselineUsd,
    required double minRiseUsd,
    required double enoughUsd,
    void Function()? onSlow,
  }) =>
      gate;
}

Future<void> _until(bool Function() ok) async {
  for (var i = 0; i < 1000 && !ok(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  expect(ok(), isTrue);
}

void main() {
  setUp(() {
    AuthGrants.clock = () => _now;
    FundedOrdersNotifier.persist = false;
    OrderFundingJourney.reset();
    MultiSourceMoveStore.reset();
    TrackingService.debugTrackObserver = (_, __) {};
  });
  tearDown(() {
    AuthGrants.clock = DateTime.now;
    FundedOrdersNotifier.persist = true;
    TrackingService.debugTrackObserver = null;
  });

  group('Bitcoin and Investing cash into one bet', () {
    late List<String> log;
    late double dollars;
    late _Investing investing;
    late VenueCashPuller puller;
    late _Funder funder;
    late Completer<DollarsLandingOutcome> landing;
    late AuthGrant grant;
    late ProviderContainer c;

    Future<BitcoinFundedRun> start() async {
      log = [];
      dollars = 0;
      investing = _Investing(log);
      puller = VenueCashPuller(
        sources: [investing],
        readDollars: () => dollars,
        minimumUsd: (_) async => 1,
        sleep: (_) async {},
      );
      funder = _Funder(log, () => dollars);
      landing = Completer();
      // The rest of the bet from the Investing cash, planned and bound
      // into the one approval before anything moves.
      final other = await planOtherVenueCash(puller,
          venue: OneBalanceVenue.predictions,
          fundUsd: _fundUsd,
          addUsd: _plan.targetUsd,
          dollarsUsd: 0);
      expect(other.covers, isTrue);
      grant = AuthGrants.issue(
        PmGrants.fundedBetReview(
          PmGrants.betReview(
              walletId: 'w',
              tokenId: 'tok',
              maxCostUsd: 8.3,
              worstPrice: 0.6,
              orderType: 'fak'),
          fundUsd: _fundUsd,
          venue: 'polymarket',
          directLegs: other.directLegs,
          btcLeg: BitcoinLegGrants.limit(maxSats: 105000, ownSpark: _ownSpark),
        ).copyWith(ttl: AuthGrants.autofireTtl),
        method: AuthGrantMethod.biometric,
        now: _now,
      );
      final env = BitcoinLegEnv(
        ownSpark: () async => _ownSpark,
        send: ({
          required String sparkAddress,
          required BitcoinLegPlan plan,
          required SettlementStepUpHook stepUp,
          required void Function() onSending,
        }) async {
          final q = _quote();
          // The settlement runner's own order: the verified quote is
          // approved, then the sats leave.
          final ok = await stepUp(SettlementAuthorizationIntent(
            flow: SettlementFlow.moveBtcToUsdc,
            walletId: 'w',
            destination: '${q.request.recipientAddress}|',
            routeLabel: BitcoinLegGrants.route,
            amountIn: q.amountIn,
            minReceive: BigInt.zero,
            maxFeeBps: 0,
            reviewedQuote: q,
          ));
          if (!ok) throw const SettlementStopped(SettlementStopReason.declined);
          log.add('bitcoin_sent');
          onSending();
          return const BitcoinLegTicket(
              quoteId: 'q_btc',
              sats: 100000,
              estimatedOutUsd: 5.1,
              minOutUsd: 5.1);
        },
        watcher: ({required DateTime since}) => _HeldLanding(landing.future
            .then((o) {
          log.add('bitcoin_landed');
          return o;
        })),
        dollarsNow: () => dollars,
        freshDollars: () async => dollars,
      );
      c = ProviderContainer(overrides: [
        bitcoinLegEnvProvider.overrideWithValue(env),
        orderFundingControllerProvider.overrideWithValue(OrderFundingController(
            funderFor: (_) => funder, dollarsUsd: () => dollars)),
      ]);
      addTearDown(c.dispose);
      final funded = Completer<void>();
      return c.read(bitcoinFundedOrderRunnerProvider).start(
            BitcoinFundedOrderRequest(
              venue: OneBalanceVenue.predictions,
              grant: grant,
              plan: _plan,
              label: _label,
              fundUsd: _fundUsd,
              readyUsd: 0,
              otherVenueUsed: true,
              fundVenue: (controller, legs) => fundRestThenMove(
                legs: legs,
                puller: puller,
                venue: OneBalanceVenue.predictions,
                fundUsd: _fundUsd,
                readyUsd: 0,
                needsOtherVenue: true,
                grant: grant,
                queue: ({
                  required double fundUsd,
                  required double readyUsd,
                  required double directArrivingUsd,
                  String? moveId,
                }) async {
                  final outcome = await controller.fundAndQueue(
                    venue: OneBalanceVenue.predictions,
                    orderUsd: 8,
                    requiredUsd: _fundUsd,
                    readyUsd: readyUsd,
                    auth: UserGrantAuthorization(grant),
                    fundUsd: fundUsd,
                    continueJourney: true,
                  );
                  if (outcome is OrderFundingFunded && !funded.isCompleted) {
                    funded.complete();
                  }
                  return outcome;
                },
              ),
              dropOrder: () {
                log.add('dropped');
                grant.revoke();
              },
              awaitPlacement: ({required onCredited}) async {
                await funded.future;
                onCredited();
                return true;
              },
            ),
          );
    }

    FundedOrderRecord record() => c.read(fundedOrdersProvider).single;

    test(
        'both legs start before either lands: the Investing cash goes '
        'straight in from the Bitcoin quote, Dollars only after the landing',
        () async {
      final run = await start();
      // The Investing leg went while the Bitcoin's dollars are still on
      // their way.
      await _until(() => investing.direct.isNotEmpty);
      expect(log, unorderedEquals(['investing_direct', 'bitcoin_sent']));
      expect(landing.isCompleted, isFalse);
      expect(funder.sent, isEmpty, reason: 'Dollars wait for the bitcoin');
      expect(investing.home, isEmpty);
      // The approved plan's leg: what lands the rest, its route's cost on
      // top.
      expect(investing.direct.single,
          greaterThanOrEqualTo(_fundUsd - _plan.targetUsd - 1e-9));
      // On the step graph both legs run at once; the move from Dollars
      // waits for the Bitcoin leg; nothing at Predictions has started.
      final g = record().steps;
      expect(g.byId('leg:investing')!.status, MoneyStepStatus.running);
      expect(g.byId('leg:bitcoin>dollars')!.status, MoneyStepStatus.running);
      expect(g.byId('leg:investing')!.after, isEmpty);
      expect(
          g
              .byId('leg:investing')!
              .startedAt!
              .difference(g.byId('leg:bitcoin>dollars')!.startedAt!)
              .inMilliseconds
              .abs(),
          lessThan(50));
      expect(g.byId('leg:dollars:onward')!.status, MoneyStepStatus.waiting);
      expect(g.byId('ready:gather')!.after,
          containsAll(['leg:investing', 'leg:dollars:onward']));
      expect(g.byId('ready:convert')!.status, MoneyStepStatus.waiting);

      // The Bitcoin's dollars land: Dollars go on with them.
      dollars = 5.2;
      landing.complete(const DollarsLanded(byStatus: true, freshDollarsUsd: 5.2));
      expect(await run.ended, BitcoinFundedEnd.placed);
      expect(log.sublist(0, 2),
          unorderedEquals(['investing_direct', 'bitcoin_sent']));
      expect(log.sublist(2), ['bitcoin_landed', 'dollars_move']);
      // The whole move from Dollars: the Bitcoin's dollars (and the cent
      // the Investing leg's arrival lacks), never the Investing share.
      expect(funder.sent.single, greaterThanOrEqualTo(_plan.targetUsd));
      expect(funder.sent.single, lessThan(5.2));
      expect(investing.direct, hasLength(1));
    });

    test(
        'the Bitcoin leg refunded after the Investing cash went: nothing '
        'more moves from Dollars, the bet is dropped', () async {
      final run = await start();
      await _until(() => investing.direct.isNotEmpty);
      landing.complete(const DollarsLegFailed('refunded'));
      expect(await run.ended, BitcoinFundedEnd.refunded);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(funder.sent, isEmpty);
      expect(log.contains('dropped'), isTrue);
      expect(grant.revoked, isTrue);
      expect(investing.direct, hasLength(1));
      // Nothing at Predictions ever ran for it.
      final g = record().steps;
      expect(g.byId('ready:convert')!.status, MoneyStepStatus.waiting);
      expect(g.byId('place')!.status, MoneyStepStatus.waiting);
    });
  });

  group('fundRestThenMove next to the chain\'s Bitcoin leg', () {
    test(
        'a leg home to Dollars: the move from Dollars waits until Dollars '
        'hold all of it, never only the Bitcoin\'s dollars', () async {
      final log = <String>[];
      var dollars = 0.0;
      final home = _Investing(log, straight: false);
      var polls = 0;
      final puller = VenueCashPuller(
        sources: [home],
        readDollars: () => dollars,
        minimumUsd: (_) async => 1,
        sleep: (_) async {
          polls++;
          // The leg home lands a few reads after the Bitcoin's dollars.
          if (polls == 3) dollars += home.home.single;
          await Future<void>.delayed(Duration.zero);
        },
      );
      final landed = Completer<bool>();
      final queued = <(double, double)>[];
      final grant = AuthGrants.issue(
        PmGrants.fundedBetReview(
          PmGrants.betReview(
              walletId: 'w',
              tokenId: 'tok',
              maxCostUsd: 8.3,
              worstPrice: 0.6,
              orderType: 'fak'),
          fundUsd: _fundUsd,
          venue: 'polymarket',
        ),
        method: AuthGrantMethod.biometric,
        now: _now,
      );
      final outcome = fundRestThenMove(
        puller: puller,
        venue: OneBalanceVenue.predictions,
        fundUsd: _fundUsd,
        readyUsd: 0,
        needsOtherVenue: true,
        grant: grant,
        legs: FundingLegContext(
            viaBitcoinUsd: _plan.targetUsd, viaBitcoinLanded: landed.future),
        queue: ({
          required double fundUsd,
          required double readyUsd,
          required double directArrivingUsd,
          String? moveId,
        }) async {
          queued.add((fundUsd, dollars));
          return const OrderFundingNotNeeded();
        },
      );
      // The leg home went at once, sized without the Bitcoin's dollars.
      await _until(() => home.home.isNotEmpty);
      // (grossed up for its own route home, as a leg home always is)
      expect(home.home.single,
          greaterThanOrEqualTo(_fundUsd - _plan.targetUsd - 1e-9));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(queued, isEmpty);
      // The Bitcoin's dollars land first: still not all of it.
      dollars = 5.1;
      landed.complete(true);
      expect(await outcome, isA<OrderFundingNotNeeded>());
      expect(polls, greaterThanOrEqualTo(3));
      expect(queued.single.$1, _fundUsd);
      expect(queued.single.$2, greaterThanOrEqualTo(_fundUsd - 1e-9));
    });

    test('the Bitcoin leg stopped: nothing is queued from Dollars', () async {
      final log = <String>[];
      final investing = _Investing(log);
      final puller = VenueCashPuller(
        sources: [investing],
        readDollars: () => 0,
        minimumUsd: (_) async => 1,
        sleep: (_) async {},
      );
      final plan = await puller.plan(
          neededUsd: _fundUsd - _plan.targetUsd,
          exclude: OneBalanceVenue.predictions,
          destination: VenueCashDestination.predictions);
      final grant = AuthGrants.issue(
        PmGrants.fundedBetReview(
          PmGrants.betReview(
              walletId: 'w',
              tokenId: 'tok',
              maxCostUsd: 8.3,
              worstPrice: 0.6,
              orderType: 'fak'),
          fundUsd: _fundUsd,
          venue: 'polymarket',
          directLegs: puller.directLegLimit(
              plan, VenueCashDestination.predictions),
        ),
        method: AuthGrantMethod.biometric,
        now: _now,
      );
      var queued = 0;
      final outcome = await fundRestThenMove(
        puller: puller,
        venue: OneBalanceVenue.predictions,
        fundUsd: _fundUsd,
        readyUsd: 0,
        needsOtherVenue: true,
        grant: grant,
        legs: FundingLegContext(
            viaBitcoinUsd: _plan.targetUsd,
            viaBitcoinLanded: Future.value(false)),
        queue: ({
          required double fundUsd,
          required double readyUsd,
          required double directArrivingUsd,
          String? moveId,
        }) async {
          queued++;
          return const OrderFundingNotNeeded();
        },
      );
      expect(outcome, isA<OrderFundingRefused>());
      expect((outcome as OrderFundingRefused).reason, 'bitcoin_not_landed');
      expect(queued, 0);
      expect(investing.direct, hasLength(1));
    });
  });
}
