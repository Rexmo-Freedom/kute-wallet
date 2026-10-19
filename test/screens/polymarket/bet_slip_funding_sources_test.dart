// The bet slip takes its money in the founder's order (15 October 2026:
// "We should always prioritize bitcoin balances and usdb balance to fund
// whatever. Only move from polymarket and hyperliquid and between them
// when there really isn't any balance left ... because those swaps are
// slower"): a $10 bet with $0 in Predictions and $5 in Dollars takes the
// rest from Bitcoin when there is Bitcoin, never from the $7 of Investing
// cash; only with no Bitcoin does the Investing cash come in, through the
// venue-cash runner, its steps on the slip from the approval.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/auth_grant_registry.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/pending_bet_autofire.dart'
    show kPendingBetAutofireId;
import 'package:kute/providers/pending_polymarket_bet_provider.dart';
import 'package:kute/providers/polymarket_bet_controller.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_open_orders_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/spark_address_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider;
import 'package:kute/screens/polymarket/components/bet_slip_sheet.dart';
import 'package:kute/screens/polymarket/components/slip_chrome.dart';
import 'package:kute/screens/shared/slip_shortfall.dart';
import 'package:kute/services/funding/settlement_runner.dart'
    show SettlementStepUpHook;
import 'package:kute/services/one_balance/bitcoin_funded_order.dart';
import 'package:kute/services/one_balance/bitcoin_to_dollars_leg.dart';
import 'package:kute/services/one_balance/bitcoin_to_venue_leg.dart';
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/services/one_balance/one_balance_state.dart'
    show OneBalanceVenue;
import 'package:kute/services/one_balance/order_funding.dart';
import 'package:kute/services/one_balance/predictions_venue_funder.dart';
import 'package:kute/services/one_balance/venue_cash_source.dart';
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/polymarket/polymarket_fee_terms.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart';

import '../../helpers/fake_swap_orders.dart';
import '../../helpers/runtime_policy_fixture.dart';
import '../../helpers/money_steps_finders.dart';

const _ownSpark =
    'spark1pgss93sy072yrmtad5cy2srwjhq8ekzuw78yhr808jn6htqfh9w8p8h9mfwlv9';
const _pmDeposit = '0x1111111111111111111111111111111111111111';

class _Prices extends LivePriceNotifier {
  @override
  LivePriceState build() => const LivePriceState();
  @override
  void acquire() {}
  @override
  void release() {}
  @override
  void addTokens(List<String> tokenIds, {bool pin = true}) {}
}

/// Predictions hold nothing.
class _Trading extends PolymarketTradingNotifier {
  @override
  Future<PolymarketTradingState> build() async =>
      const PolymarketTradingState(usdcBalance: 0);
}

class _Currency extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _Currency() : super(CurrencyState({'USD': Fixed.fromInt(60000)}));
  @override
  Future<void> updateRates() async {}
}

/// The venue's side of a bet: the book and the account are not asked.
class _Controller extends PolymarketBetController {
  _Controller(super.ref);

  @override
  Future<PendingBetIntent> prepareIntent(PendingBetIntent intent,
          {bool requireFreshCollateral = false}) async =>
      intent;

  @override
  SensitiveIntent? reviewIntent(PendingBetIntent intent) => PmGrants.betReview(
        walletId: 'w',
        tokenId: intent.tokenId,
        maxCostUsd: intent.amount * 1.1,
        worstPrice: 0.6,
        orderType: 'fak',
      );

  @override
  void prefetchForSend(PendingBetIntent intent) {}
}

/// The Dollars → Predictions move, recording what left.
class _Funder implements VenueFunder {
  final sent = <double>[];
  @override
  Future<VenueMoveResult> fund(
      {required double usd,
      required MoveAuthorization auth,
      String purpose = 'order_funding'}) async {
    sent.add(usd);
    return VenueMoveResult(
        quoteId: 'q_venue', sentUsd: usd, arrivingUsdEstimate: usd);
  }

  @override
  Future<VenueMoveQuote> estimate(double usd) async => VenueMoveQuote(
      arrivingUsd: usd, feeUsd: 0, fixedCostUsd: 0, minUsd: 1, maxUsd: 1000);

  @override
  Future<double> idleUsd() async => 0;

  @override
  Future<double> minimumUsd() async => 1;
}

/// $7 of Investing cash (with the $5 of Dollars, enough for the $10
/// bet and its fees): straight into Predictions within the approval's
/// caps, home to Dollars otherwise. Every pull recorded.
class _Investing implements VenueCashSource, DirectVenueCashSource {
  double cash = 7;
  final direct = <double>[];
  final home = <double>[];

  @override
  OneBalanceVenue get venue => OneBalanceVenue.investing;

  @override
  Duration get estimatedArrival => const Duration(minutes: 5);

  @override
  Future<double> availableUsd() async => cash;

  @override
  Future<VenueMoveResult> pull(double usd, {required String purpose}) async {
    home.add(usd);
    return VenueMoveResult(
        quoteId: 'q_home', sentUsd: usd, arrivingUsdEstimate: usd);
  }

  @override
  bool canPullTo(VenueCashDestination destination) =>
      destination == VenueCashDestination.predictions;

  @override
  Future<VenueMoveResult> pullTo(VenueCashDestination destination, double usd,
      {required String purpose, required MoveAuthorization auth}) async {
    final grant = (auth as ApprovedLegAuthorization).grant;
    if (!DirectLegGrants.take(grant,
        venue: venue.name,
        destination: destination.code,
        amount: IntentUnits.usd(usd))) {
      throw const DirectRouteRefused('settlement_declined');
    }
    direct.add(usd);
    return VenueMoveResult(
        quoteId: 'q_direct', sentUsd: usd, arrivingUsdEstimate: usd);
  }
}

/// The wallet behind the Bitcoin leg: the via-Dollars leg goes (the direct
/// one is costlier here) and its dollars land at once.
class _Env {
  var sends = 0;

  BitcoinLegEnv get env => BitcoinLegEnv(
        ownSpark: () async => _ownSpark,
        send: ({
          required String sparkAddress,
          required BitcoinLegPlan plan,
          required SettlementStepUpHook stepUp,
          required void Function() onSending,
        }) async {
          sends++;
          onSending();
          return BitcoinLegTicket(
              quoteId: 'q_btc',
              sats: plan.sats,
              estimatedOutUsd: plan.targetUsd,
              minOutUsd: plan.targetUsd);
        },
        watcher: ({required DateTime since}) => _Landed(),
        dollarsNow: () => 5,
        freshDollars: () async => 20,
        planDirect: ({
          required OneBalanceVenue venue,
          required double fundUsd,
          required double addUsd,
          required double dollarsUsd,
          required BitcoinLegPlan via,
          required String ownVenue,
          required int directMaxSats,
        }) async =>
            const DirectBitcoinPlan.viaDollars(DirectBitcoinReason.costlier),
        sendDirect: ({
          required OneBalanceVenue venue,
          required String ownVenue,
          required String ownSpark,
          required int sats,
          required double targetUsd,
          required SettlementStepUpHook stepUp,
          required void Function() onSending,
        }) async =>
            throw StateError('the direct leg was not chosen'),
      );
}

class _Landed extends DollarsLandingWatcher {
  _Landed()
      : super(
          statusOf: (_) async => null,
          dollarsNow: () => 5,
          freshDollars: () async => null,
          kickSync: () {},
        );

  @override
  Future<DollarsLandingOutcome> watch({
    required String Function() id,
    required double baselineUsd,
    required double minRiseUsd,
    required double enoughUsd,
    void Function()? onSlow,
  }) async =>
      const DollarsLanded(byStatus: true, freshDollarsUsd: 20);
}

const _outcomes = [
  PolymarketOutcome(name: 'Yes', price: 0.5, tokenId: 'yes-token'),
  PolymarketOutcome(name: 'No', price: 0.5, tokenId: 'no-token'),
];

late _Env _env;
late _Funder _funder;
late _Investing _investing;

Future<void> _pumpSlip(WidgetTester tester, {String? slug}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      settingsProvider.overrideWith((ref) => SettingsModel(Settings(
            currency: 'USD',
            language: 'en',
            btcFormat: 'sats',
            backup: false,
            biometricsEnabled: false,
            bitcoinElectrumNode: '',
            nodeType: '',
            reviewDone: true,
            wallets: [WalletConfig(id: 'w', name: 'Spending')],
            activeWalletId: 'w',
          ))),
      polymarketTradingProvider.overrideWith(_Trading.new),
      swapOrdersProvider.overrideWith((ref) => FakeSwapOrders()),
      livePriceProvider.overrideWith(_Prices.new),
      polymarketOpenOrdersProvider
          .overrideWith((ref) => Stream.value(const <Order>[])),
      aiEnabledProvider.overrideWith((ref) async => false),
      currencyProvider.overrideWith((ref) => _Currency()),
      // $5 in Dollars.
      usdBalanceProvider.overrideWithValue(5),
      polymarketFeeTermsProvider
          .overrideWith((ref, _) async => PolymarketFeeTerms.worstCase),
      polymarketBetControllerProvider.overrideWith(_Controller.new),
      polymarketMarketWindowReaderProvider.overrideWithValue((_) async => null),
      sparkSelfAddressProvider.overrideWith((_) async => _ownSpark),
      // $7 of Investing cash.
      venueCashPullerProvider.overrideWith((_) => VenueCashPuller(
          sources: [_investing],
          readDollars: () => 5,
          minimumUsd: (_) async => 1)),
      bitcoinLegEnvProvider.overrideWith((_) => _env.env),
      orderFundingControllerProvider.overrideWithValue(OrderFundingController(
          funderFor: (_) => _funder, dollarsUsd: () => 5)),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
            splashFactory: NoSplash.splashFactory,
            fontFamily: 'Inter',
            extensions: [AppColorsExtension.light()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          resizeToAvoidBottomInset: false,
          body: Align(
            alignment: Alignment.bottomCenter,
            child: BetSlipSheet(
                marketQuestion: 'Will it rain?',
                marketSlug: slug,
                outcomes: _outcomes,
                initialAmountUsd: 10),
          ),
        ),
      ),
    ),
  ));
  await _frames(tester);
}

/// The busy button animates for as long as it waits: pump, never settle.
Future<void> _frames(WidgetTester tester, [int n = 10]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

PolySlipCta _cta(WidgetTester tester) =>
    tester.widget<PolySlipCta>(find.byType(PolySlipCta));

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(BetSlipSheet)));

void main() {
  late RuntimeCapabilitiesService policy;
  late List<SensitiveIntent> approvals;
  late List<String> sheets;
  late List<(String, Map<String, Object?>?)> events;

  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    PredictionsVenueFunder.debugRouteShare = (_) async => 0;
    AffiliateService.debugSessionToken = 'test-session';
    FundedOrdersNotifier.persist = false;
    OrderFundingJourney.reset();
    DirectRouteRefusals.reset();
    policy = runtimePolicyFixture();
    RuntimeCapabilitiesService.debugInstance = policy;
    _env = _Env();
    _funder = _Funder();
    _investing = _Investing();
    approvals = [];
    sheets = [];
    events = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    debugBitcoinLegEstimate = (sats) async => sats / 1e8 * 60000 * 0.995;
    debugOwnVenueDeposit = (_) async => _pmDeposit;
    debugShowSlipTopUpSheet = (venue, _) async => sheets.add('top_up');
    debugShowSlipReceiveSheet = (venue, _) async => sheets.add('receive');
    // The ONE prompt, approved.
    debugPmBetFundingApproval = (intent) async {
      approvals.add(intent);
      return AuthGrantRegistry.instance.issueAutofire(
          kPendingBetAutofireId, intent,
          method: AuthGrantMethod.biometric);
    };
  });

  tearDown(() {
    PredictionsVenueFunder.debugRouteShare = null;
    debugFreshSpendingBitcoin = null;
    debugBitcoinLegEstimate = null;
    debugOwnVenueDeposit = null;
    debugShowSlipTopUpSheet = null;
    debugShowSlipReceiveSheet = null;
    debugPmBetFundingApproval = null;
    TrackingService.debugTrackObserver = null;
    AuthGrantRegistry.instance.cancelAutofire(kPendingBetAutofireId);
    FundedOrdersNotifier.persist = true;
    RuntimeCapabilitiesService.debugInstance = null;
    AffiliateService.debugSessionToken = null;
  });

  Future<void> release(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    policy.dispose();
    // Past the autofire grant's own 30-minute life.
    await tester.pump(const Duration(minutes: 31));
  }

  Future<void> placeAndFinish(WidgetTester tester) async {
    final notifier =
        _container(tester).read(pendingPolymarketBetProvider.notifier);
    notifier.updateStatus(PendingBetStatus.placing);
    await _frames(tester, 3);
    notifier.updateStatus(PendingBetStatus.done);
    await _frames(tester, 3);
  }

  for (final minutes in [5, 15]) {
    testWidgets(
        'Bitcoin $minutes-minute bet uses ordinary approval, funding and placement',
        (tester) async {
      debugFreshSpendingBitcoin =
          () async => (sats: 1000000, usdPerBtc: 60000.0);
      expect(await policy.refresh(), isTrue);
      final epoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await _pumpSlip(tester, slug: 'btc-updown-${minutes}m-$epoch');
      expect(_cta(tester).label, isNot('Transfer to Polymarket'));
      expect(find.textContaining('Transfer first, then place your bet.'),
          findsNothing);
      expect(approvals, isEmpty);
      expect(_funder.sent, isEmpty);
      expect(_container(tester).read(pendingPolymarketBetProvider), isNull);
      await tester.tap(find.byType(PolySlipCta));
      await _frames(tester, 10);
      expect(approvals, hasLength(1));
      expect(approvals.single.action, SensitiveAction.pmBet);
      expect(_env.sends, 1);
      expect(_funder.sent, hasLength(1));
      expect(_investing.direct, isEmpty);
      final intent = _container(tester).read(pendingPolymarketBetProvider);
      expect(intent, isNotNull);
      final record = _container(tester).read(fundedOrdersProvider).single;
      expect(record.label.kind, FundedOrderKind.order);
      expect(record.steps.byId('place'), isNotNull);
      await placeAndFinish(tester);
      expect(_container(tester).read(fundedOrdersProvider).single.stage,
          FundedOrderStage.done);
      expect(approvals, hasLength(1),
          reason: 'one approved bet, no separate transfer action');
      await release(tester);
    });
  }

  testWidgets(
      'a \$10 bet, \$5 Dollars, Bitcoin, \$7 Investing: Bitcoin brings the '
      'rest, the Investing cash is never touched', (tester) async {
    // Plenty of spending bitcoin.
    debugFreshSpendingBitcoin = () async => (sats: 1000000, usdPerBtc: 60000.0);
    expect(await policy.refresh(), isTrue);
    await _pumpSlip(tester);
    // Dollars and Investing cover it: the button is the bet itself.
    expect(find.byKey(const ValueKey('bet-slip-deposit-door')), findsNothing);
    expect(_cta(tester).label, isNot(startsWith(r'Add $')));

    await tester.tap(find.byType(PolySlipCta));
    await _frames(tester, 10);

    expect(sheets, isEmpty);
    // ONE approval: the bet, its move and the Bitcoin leg; no Investing
    // leg bound into it.
    expect(approvals, hasLength(1));
    expect(approvals.single.limits[VenueLimit.fundBtc], isNotNull);
    expect(approvals.single.limits[VenueLimit.directLegs], isNull);
    expect(_env.sends, 1);
    expect(_investing.direct, isEmpty);
    expect(_investing.home, isEmpty);
    expect(_funder.sent, hasLength(1));
    // The steps show only the sources used.
    final record = _container(tester).read(fundedOrdersProvider).single;
    expect(record.steps.byId('leg:investing'), isNull);
    expect(findMoneyStepContaining('from Investing'), findsNothing);
    expect(find.text('Placing \$10.00 on Yes'), findsOneWidget);
    final started =
        events.where((e) => e.$1 == 'order_funding_started').first.$2!;
    expect(started['funding_source'], 'bitcoin');
    expect(started['other_venue_used'], isFalse);

    await placeAndFinish(tester);
    expect(_container(tester).read(fundedOrdersProvider).single.stage,
        FundedOrderStage.done);
    expect(approvals, hasLength(1));
    await release(tester);
  });

  testWidgets(
      'no Bitcoin: Dollars and the Investing cash at once, the steps on the '
      'slip from the approval, the Investing cash straight into Predictions',
      (tester) async {
    debugFreshSpendingBitcoin = () async => (sats: 0, usdPerBtc: 60000.0);
    expect(await policy.refresh(), isTrue);
    await _pumpSlip(tester);
    expect(find.byKey(const ValueKey('bet-slip-deposit-door')), findsNothing);

    await tester.tap(find.byType(PolySlipCta));
    await _frames(tester, 10);

    expect(sheets, isEmpty);
    expect(approvals, hasLength(1));
    // The Investing leg straight in is bound into the one approval.
    expect(approvals.single.limits[VenueLimit.directLegs], isNotNull);
    expect(approvals.single.limits[VenueLimit.fundBtc], isNull);
    expect(_env.sends, 0);
    // Both sources went, neither waiting on the other's landing.
    expect(_funder.sent, [5.0]);
    expect(_investing.direct, hasLength(1));
    expect(_investing.home, isEmpty);
    // The step graph, on the slip, from the approval.
    final record = _container(tester).read(fundedOrdersProvider).single;
    expect([for (final l in record.steps.legs) l.id],
        ['leg:investing', 'leg:dollars']);
    expect(findMoneyStepContaining('from Investing'), findsOneWidget);
    expect(findMoneyStepContaining('from Dollars'), findsOneWidget);
    expect(find.text('Getting your prediction ready'), findsOneWidget);
    expect(find.text('Placing \$10.00 on Yes'), findsOneWidget);
    final pending = _container(tester).read(pendingPolymarketBetProvider)!;
    expect(pending.status, PendingBetStatus.awaitingBalance);
    final started =
        events.where((e) => e.$1 == 'order_funding_started').first.$2!;
    expect(started['funding_source'], 'venue_cash');
    expect(started['other_venue_used'], isTrue);

    await placeAndFinish(tester);
    expect(_container(tester).read(fundedOrdersProvider).single.stage,
        FundedOrderStage.done);
    expect(approvals, hasLength(1));
    await release(tester);
  });
}
