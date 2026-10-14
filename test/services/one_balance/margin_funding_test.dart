// Adding margin beyond the Investing cash is funded exactly as the order
// slips fund an order (founder, 14 October 2026): Dollars, then the
// Predictions cash straight into Investing, then the person's own bitcoin
// for exactly X, all planned before ONE approval that binds the margin
// change, the Dollars move, the direct legs and the Bitcoin leg. The
// change is signed once the money landed, on the very position it was
// approved for, or not at all.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/orchestra_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/settlement_operation.dart' show SettlementFlow;
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/spark_address_provider.dart'
    show sparkSelfAddressProvider;
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider;
import 'package:kute/services/funding/settlement_runner.dart'
    show
        SettlementAuthorizationIntent,
        SettlementStepUpHook,
        SettlementStopReason,
        SettlementStopped;
import 'package:kute/services/one_balance/bitcoin_funded_order.dart';
import 'package:kute/services/one_balance/bitcoin_to_dollars_leg.dart';
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/services/one_balance/hyperliquid_venue_funder.dart';
import 'package:kute/services/one_balance/margin_funding.dart';
import 'package:kute/services/one_balance/multi_source_move.dart'
    show MultiSourceMoveStore;
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/order_funding.dart';
import 'package:kute/services/one_balance/venue_cash_source.dart';
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/orchestra/orchestra_quote_guard.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:money2/money2.dart';

const _ownSpark =
    'spark1pgss93sy072yrmtad5cy2srwjhq8ekzuw78yhr808jn6htqfh9w8p8h9mfwlv9';
const _depositSpark =
    'spark1pgssy7d7vel0nh9m4326qc54e6rskpczn07dktww9rv4nu5ptvt0s9uc489gg2';
final _now = DateTime.utc(2026, 10, 14, 12);
const _usdPerBtc = 60000.0;

const _long = HlPerpPosition(
  coin: 'xyz:TSLA',
  szi: 2,
  entryPx: 350,
  positionValue: 740,
  unrealizedPnl: 40,
  returnOnEquity: 0.2,
  liquidationPx: 300,
  marginUsed: 200,
  leverageType: 'isolated',
  leverageValue: 5,
  maxLeverage: 10,
);

const _market = HlMarket(
  coin: 'TSLA',
  wireCoin: 'xyz:TSLA',
  assetId: 110001,
  kind: HlMarketKind.perp,
  szDecimals: 3,
  maxLeverage: 10,
  onlyIsolated: false,
  markPx: 370,
  midPx: 370,
  prevDayPx: 360,
  dayNtlVlm: 1,
  dex: 'xyz',
  isHip3: true,
);

class _Currency extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _Currency() : super(CurrencyState({'USD': Fixed.fromInt(100)}));
  @override
  Future<void> updateRates() async {}
}

/// Dollars → Investing at a near-flat $1.24, recording every move.
class _Funder implements VenueFunder {
  final sent = <double>[];

  @override
  Future<VenueMoveQuote> estimate(double usd) async => VenueMoveQuote(
      arrivingUsd: usd - 1.24,
      feeUsd: 1.24,
      fixedCostUsd: 0,
      minUsd: 1,
      maxUsd: 100000);

  @override
  Future<VenueMoveResult> fund(
      {required double usd,
      required MoveAuthorization auth,
      String purpose = 'order_funding'}) async {
    // The rail's own check: the one approval covers this move.
    final grant = (auth as UserGrantAuthorization).grant;
    expect(grant.boundIntent.limits[kFundVenueLimit], kFundVenueInvesting);
    sent.add(usd);
    return VenueMoveResult(
        quoteId: 'q_venue', sentUsd: usd, arrivingUsdEstimate: usd - 1.24);
  }

  @override
  Future<double> idleUsd() async => 0;

  @override
  Future<double> minimumUsd() async => 1;
}

/// Predictions cash that goes straight into Investing only within the
/// caps the one approval binds, as the real rail does.
class _Predictions implements VenueCashSource, DirectVenueCashSource {
  _Predictions(this.cash);
  double cash;
  final direct = <double>[];
  final home = <double>[];

  @override
  OneBalanceVenue get venue => OneBalanceVenue.predictions;

  @override
  Duration get estimatedArrival => const Duration(minutes: 1);

  @override
  Future<double> availableUsd() async => cash;

  @override
  Future<VenueMoveResult> pull(double usd, {required String purpose}) async {
    home.add(usd);
    cash -= usd;
    return VenueMoveResult(
        quoteId: 'q_home',
        sentUsd: usd,
        arrivingUsdEstimate: venuePullArrives(
            usd, kVenuePullCost[OneBalanceVenue.predictions]!));
  }

  @override
  bool canPullTo(VenueCashDestination destination) =>
      destination == VenueCashDestination.investing;

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
    direct.add(usd);
    cash -= usd;
    return VenueMoveResult(
        quoteId: 'q_direct',
        sentUsd: usd,
        arrivingUsdEstimate: venuePullArrives(
            usd, kVenuePullCost[OneBalanceVenue.predictions]!));
  }
}

/// The Bitcoin leg: the runner's own step-up hook against a verified
/// quote for exactly the planned sats, as the settlement runner calls it.
class _Bitcoin {
  final plans = <BitcoinLegPlan>[];
  var paid = 0;
  double dollarsAfter = 0;

  BitcoinLegEnv env(double Function() dollars) => BitcoinLegEnv(
        ownSpark: () async => _ownSpark,
        send: ({
          required String sparkAddress,
          required BitcoinLegPlan plan,
          required SettlementStepUpHook stepUp,
          required void Function() onSending,
        }) async {
          plans.add(plan);
          final q = _quote(plan.sats);
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
          onSending();
          paid++;
          return BitcoinLegTicket(
              quoteId: 'q_btc',
              sats: plan.sats,
              estimatedOutUsd: plan.targetUsd,
              minOutUsd: plan.targetUsd);
        },
        watcher: ({required DateTime since}) => _Landed(dollarsAfter),
        dollarsNow: dollars,
        freshDollars: () async => dollars(),
      );
}

class _Landed extends DollarsLandingWatcher {
  _Landed(this.fresh)
      : super(
          statusOf: (_) async => null,
          dollarsNow: () => 0,
          freshDollars: () async => null,
          kickSync: () {},
        );
  final double fresh;

  @override
  Future<DollarsLandingOutcome> watch({
    required String Function() id,
    required double baselineUsd,
    required double minRiseUsd,
    required double enoughUsd,
    void Function()? onSlow,
  }) async =>
      DollarsLanded(byStatus: true, freshDollarsUsd: fresh);
}

VerifiedOrchestraQuote _quote(int sats) => verifyOrchestraQuote(
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
        'quoteId': 'q_btc',
        'depositAddress': _depositSpark,
        'amountIn': '$sats',
        'estimatedOut': '${(sats * 600).round()}',
        'feeAmount': '0',
        'feeBps': 0,
        'totalFeeAmount': '0',
        'feeAsset': 'USDB',
        'route': ['spark:BTC', 'spark:USDB'],
        'expiresAt': '2026-10-14T12:02:00Z',
        'priceLockMode': 'floating',
      }),
      now: _now,
      bounds: OrchestraQuoteBounds.forSource('spark',
          inputValueInOutputUnits: sats * 600.0),
      mainnet: true,
    );

/// The Investing account as the chain reads it, and the signatures.
class _Account {
  _Account({this.cashUsd = 30, this.positions = const [_long]});
  double cashUsd;
  List<HlPerpPosition> positions;
  final signed = <({double usd, AuthGrant grant})>[];
  var t = _now;

  MarginChainEnv get env => MarginChainEnv(
        account: () async => (cashUsd: cashUsd, positions: positions),
        adjust: ({
          required HlMarket market,
          required HlPerpPosition position,
          required double usd,
          required AuthGrant grant,
        }) async {
          // The notifier's own check: the grant is bound to the change.
          GrantGuard.consume(
              grant,
              HlIntents.isolatedMargin(
                  walletId: 'w',
                  market: market,
                  positionIsLong: position.isLong,
                  usd: usd),
              allowed: const {SensitiveAction.hlOrder});
          signed.add((usd: usd, grant: grant));
        },
        hold: () => () {},
        sleep: (d) async => t = t.add(d),
        clock: () => t,
      );
}

void main() {
  late _Funder funder;
  late List<(String, Map<String, Object>?)> events;

  setUp(() {
    AuthGrants.clock = () => _now;
    FundedOrdersNotifier.persist = false;
    OrderFundingJourney.reset();
    MultiSourceMoveStore.reset();
    DirectRouteRefusals.reset();
    funder = _Funder();
    events = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    debugBitcoinLegEstimate = (sats) async => sats / 1e8 * _usdPerBtc * 0.995;
  });
  tearDown(() {
    AuthGrants.clock = DateTime.now;
    FundedOrdersNotifier.persist = true;
    TrackingService.debugTrackObserver = null;
    debugBitcoinLegEstimate = null;
    debugFreshSpendingBitcoin = null;
  });

  ProviderContainer container({
    required double Function() dollars,
    required List<VenueCashSource> sources,
    required _Account account,
    _Bitcoin? bitcoin,
  }) {
    final puller = VenueCashPuller(
      sources: sources,
      readDollars: dollars,
      minimumUsd: (_) async => 1,
      sleep: (_) async {},
      clock: () => _now,
    );
    final c = ProviderContainer(overrides: [
      settingsProvider.overrideWith((ref) => SettingsModel(Settings(
            currency: 'USD',
            language: 'en',
            btcFormat: 'sats',
            backup: false,
            biometricsEnabled: false,
            bitcoinElectrumNode: '',
            nodeType: '',
            reviewDone: true,
          ))),
      currencyProvider.overrideWith((ref) => _Currency()),
      usdBalanceProvider.overrideWith((_) => dollars()),
      sparkSelfAddressProvider.overrideWith((_) async => _ownSpark),
      hyperliquidVenueFunderProvider.overrideWithValue(funder),
      venueCashPullerProvider.overrideWithValue(puller),
      orderFundingControllerProvider.overrideWithValue(OrderFundingController(
          funderFor: (_) => funder, dollarsUsd: dollars)),
      marginChainEnvProvider.overrideWithValue(account.env),
      bitcoinLegEnvProvider
          .overrideWithValue((bitcoin ?? _Bitcoin()).env(dollars)),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  SensitiveIntent change() => HlIntents.isolatedMargin(
      walletId: 'w', market: _market, positionIsLong: true, usd: 30);

  MarginTarget target() => MarginTarget(
        market: _market,
        position: _long,
        change: change(),
        label: const FundedOrderLabel(
          venue: OneBalanceVenue.investing,
          orderUsd: 30,
          side: 'Long',
          market: 'TSLA',
          marketKey: 'TSLA',
          kind: FundedOrderKind.margin,
        ),
      );

  /// The sheet's one approval: the change bound with the plan's limits.
  ({Future<AuthGrant?> Function() approve, List<AuthGrant> grants}) faceId(
      MarginFundingPlan plan,
      {bool decline = false}) {
    final grants = <AuthGrant>[];
    return (
      grants: grants,
      approve: () async {
        if (decline) return null;
        final c = change();
        final g = AuthGrants.issue(
          c.copyWith(
              limits: {...c.limits, ...plan.grantLimits()},
              ttl: AuthGrants.autofireTtl),
          method: AuthGrantMethod.biometric,
          now: _now,
        );
        grants.add(g);
        return g;
      },
    );
  }

  group('decideMarginFunding', () {
    test('Dollars that cover the move: Dollars only, nothing else bound',
        () async {
      final c = container(
          dollars: () => 50, sources: [_Predictions(20)], account: _Account());
      final d = await decideMarginFunding(c.read,
          amountUsd: 30, readyUsd: 20, dollarsUsd: 50);
      final plan = (d as MarginFundingPlanned).plan;
      expect(plan.bitcoin, isNull);
      expect(plan.needsOtherVenue, isFalse);
      expect(plan.directLegs, isNull);
      // $10 short plus the engine's $0.25 buffer lands; ~$1.24 on top.
      expect(plan.fundUsd, inInclusiveRange(11.49, 11.6));
      expect(plan.sources, ['investing', 'dollars']);
      expect(plan.grantLimits()[kFundUsdLimit], dollarsBaseUnits(plan.fundUsd));
      expect(plan.grantLimits().containsKey(VenueLimit.fundBtc), isFalse);
    });

    test('bitcoin that cannot cover X: the Investments Receive sheet for X',
        () async {
      debugFreshSpendingBitcoin =
          () async => (sats: 1000, usdPerBtc: _usdPerBtc);
      final c = container(dollars: () => 2, sources: [], account: _Account());
      final d = await decideMarginFunding(c.read,
          amountUsd: 30, readyUsd: 20, dollarsUsd: 2);
      final fund = (await sizeMarginFunding(funder, shortfallUsd: 10)).fundUsd;
      expect(d, isA<MarginFundingNeedsReceive>());
      expect((d as MarginFundingNeedsReceive).addUsd,
          BitcoinLegRules.addUsd(fundUsd: fund, investmentsUsd: 2));
    });

    test(r'an "Add $X" tap whose X grew moves nothing', () async {
      final c = container(dollars: () => 2, sources: [], account: _Account());
      final d = await decideMarginFunding(c.read,
          amountUsd: 30, readyUsd: 20, dollarsUsd: 2, shownAddUsd: 5);
      expect(d, isA<MarginFundingAddChanged>());
    });
  });

  test(
      'a shortfall Predictions covers moves straight into Investing under '
      'the one approval, no bitcoin, then signs the change once', () async {
    var dollars = 2.0;
    final predictions = _Predictions(20);
    final account = _Account(cashUsd: 30);
    final bitcoin = _Bitcoin();
    debugFreshSpendingBitcoin = () async => fail('bitcoin was read');
    final c = container(
        dollars: () => dollars,
        sources: [predictions],
        account: account,
        bitcoin: bitcoin);
    final d = await decideMarginFunding(c.read,
        amountUsd: 30, readyUsd: 20, dollarsUsd: dollars);
    final plan = (d as MarginFundingPlanned).plan;
    expect(plan.bitcoin, isNull);
    expect(plan.needsOtherVenue, isTrue);
    // The leg straight into Investing is bound into the approval.
    expect(plan.directLegs!['to'], VenueCashDestination.investing.code);
    expect((plan.directLegs!['legs'] as Map).keys, ['predictions']);
    expect(plan.sources, ['investing', 'dollars', 'predictions']);

    final face = faceId(plan);
    final run = await c
        .read(marginFundingRunnerProvider)
        .startApproved(plan: plan, target: target(), approve: face.approve);
    expect(await run!.ended, MarginFundedEnd.signed);
    expect(face.grants, hasLength(1));
    expect(predictions.direct, isNotEmpty);
    expect(predictions.home, isEmpty);
    expect(bitcoin.paid, 0);
    // Dollars only for what the direct leg did not bring.
    expect(funder.sent.single, lessThanOrEqualTo(2.0));
    // Signed once, under a grant bound to the change alone.
    expect(account.signed, hasLength(1));
    expect(account.signed.single.usd, 30);
    final child = account.signed.single.grant.boundIntent.limits;
    expect(child.containsKey(kFundUsdLimit), isFalse);
    expect(child.containsKey(VenueLimit.directLegs), isFalse);
    expect(face.grants.single.revoked, isTrue);
    final record = c.read(fundedOrdersProvider).single;
    expect(record.label.kind, FundedOrderKind.margin);
    expect(record.stage, FundedOrderStage.done);
    // The slips' journey, tagged with the sources.
    final started =
        events.singleWhere((e) => e.$1 == 'order_funding_started').$2!;
    expect(started['funding_source'], 'investing,dollars,predictions');
    expect(started['entry_source'], kMarginEntrySource);
    expect(events.any((e) => e.$1 == 'order_funding_completed'), isTrue);
    dollars = 0;
  });

  test(
      'a shortfall needing bitcoin runs one Face ID and converts exactly X, '
      'then signs the change', () async {
    var dollars = 2.0;
    debugFreshSpendingBitcoin =
        () async => (sats: 100000000, usdPerBtc: _usdPerBtc);
    final bitcoin = _Bitcoin();
    final account = _Account(cashUsd: 30);
    final c = container(
        dollars: () => dollars,
        sources: [],
        account: account,
        bitcoin: bitcoin);
    final fund = (await sizeMarginFunding(funder, shortfallUsd: 10)).fundUsd;
    final x = BitcoinLegRules.addUsd(fundUsd: fund, investmentsUsd: 2);
    final d = await decideMarginFunding(c.read,
        amountUsd: 30, readyUsd: 20, dollarsUsd: dollars);
    final plan = (d as MarginFundingPlanned).plan;
    expect(plan.bitcoin!.targetUsd, x);
    expect(plan.ownSpark, _ownSpark);
    expect(plan.sources, ['investing', 'dollars', 'bitcoin']);
    final limits = plan.grantLimits();
    // The leg is pinned: route, the wallet's own Spark address, at most
    // the sized sats.
    expect(
        limits[VenueLimit.fundBtc],
        BitcoinLegGrants.limit(
            maxSats: plan.bitcoin!.maxSats, ownSpark: _ownSpark));
    expect(plan.analyticsParams()['bitcoin_usd'], x);

    // The dollars land: Dollars then hold the whole move.
    bitcoin.dollarsAfter = fund;
    dollars = fund;
    final face = faceId(plan);
    final run = await c
        .read(marginFundingRunnerProvider)
        .startApproved(plan: plan, target: target(), approve: face.approve);
    expect(await run!.ended, MarginFundedEnd.signed);
    expect(face.grants, hasLength(1));
    expect(bitcoin.paid, 1);
    expect(bitcoin.plans.single.targetUsd, x);
    expect(BitcoinLegGrants.takenBy(face.grants.single), isTrue);
    expect(funder.sent, [fund]);
    expect(account.signed.single.usd, 30);
    final record = c.read(fundedOrdersProvider).single;
    expect(record.fromBitcoin, isTrue);
    expect(record.stage, FundedOrderStage.done);
  });

  test('a declined Face ID moves nothing', () async {
    debugFreshSpendingBitcoin =
        () async => (sats: 100000000, usdPerBtc: _usdPerBtc);
    for (final sources in [
      <VenueCashSource>[],
      <VenueCashSource>[_Predictions(20)],
    ]) {
      final bitcoin = _Bitcoin();
      final account = _Account();
      final c = container(
          dollars: () => 2,
          sources: sources,
          account: account,
          bitcoin: bitcoin);
      final plan = ((await decideMarginFunding(c.read,
              amountUsd: 30,
              readyUsd: 20,
              dollarsUsd: 2)) as MarginFundingPlanned)
          .plan;
      final run = await c.read(marginFundingRunnerProvider).startApproved(
          plan: plan,
          target: target(),
          approve: faceId(plan, decline: true).approve);
      expect(run, isNull);
      expect(bitcoin.paid, 0);
      expect(funder.sent, isEmpty);
      for (final s in sources) {
        expect((s as _Predictions).direct, isEmpty);
        expect(s.home, isEmpty);
      }
      expect(account.signed, isEmpty);
      expect(c.read(fundedOrdersProvider), isEmpty);
    }
  });

  test(
      'a position that changed before signing: nothing signed, the money '
      'stays in Investments', () async {
    for (final changed in const [
      <HlPerpPosition>[], // closed
      [
        HlPerpPosition(
          coin: 'xyz:TSLA',
          szi: 1, // partly closed
          entryPx: 350,
          positionValue: 370,
          unrealizedPnl: 20,
          returnOnEquity: 0.1,
          liquidationPx: 300,
          marginUsed: 100,
          leverageType: 'isolated',
          leverageValue: 5,
          maxLeverage: 10,
        ),
      ],
    ]) {
      funder.sent.clear();
      final account = _Account(cashUsd: 30, positions: changed);
      final c = container(dollars: () => 50, sources: [], account: account);
      final plan = ((await decideMarginFunding(c.read,
              amountUsd: 30,
              readyUsd: 20,
              dollarsUsd: 50)) as MarginFundingPlanned)
          .plan;
      final face = faceId(plan);
      final run = await c
          .read(marginFundingRunnerProvider)
          .startApproved(plan: plan, target: target(), approve: face.approve);
      expect(await run!.ended, MarginFundedEnd.changed);
      // The money moved into Investing and stays there; nothing signed,
      // and the approval can no longer sign anything.
      expect(funder.sent, hasLength(1));
      expect(account.signed, isEmpty);
      expect(face.grants.single.revoked, isTrue);
      final record = c.read(fundedOrdersProvider).single;
      expect(record.stage, FundedOrderStage.failed);
      expect(record.reason, 'position_changed');
    }
  });

  test('the credit never came: nothing signed, the approval ends', () async {
    final account = _Account(cashUsd: 20);
    final c = container(dollars: () => 50, sources: [], account: account);
    final plan = ((await decideMarginFunding(c.read,
            amountUsd: 30,
            readyUsd: 20,
            dollarsUsd: 50)) as MarginFundingPlanned)
        .plan;
    final face = faceId(plan);
    final run = await c
        .read(marginFundingRunnerProvider)
        .startApproved(plan: plan, target: target(), approve: face.approve);
    expect(await run!.ended, MarginFundedEnd.stopped);
    expect(account.signed, isEmpty);
    expect(face.grants.single.revoked, isTrue);
    expect(
        events.any((e) =>
            e.$1 == 'order_funding_failed' && e.$2!['stage'] == 'credit'),
        isTrue);
  });

  test('the very position: same instrument, side, isolation, size', () {
    expect(
        marginPositionUnchanged(
            market: _market, approved: _long, live: const [_long]),
        isTrue);
    expect(
        marginPositionUnchanged(
            market: _market, approved: _long, live: const []),
        isFalse);
  });
}
