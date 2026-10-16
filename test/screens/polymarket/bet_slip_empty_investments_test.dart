// An empty Investments balance takes the same path as a partly funded one
// (founder, 15 October 2026: "we should never make it show up"): nothing
// typed on a hot bet slip whose Investments hold $0, with enough spending
// bitcoin, "Add $X to Investments" is the bet itself at the market's
// minimum, funded in place under ONE approval with the steps on the slip.
// No deposit sheet is ever pushed, and the direct Bitcoin → Predictions
// leg is planned before the chain picks its route.

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
import 'package:kute/screens/home/components/deposit_sheet.dart'
    show DepositSheet;
import 'package:kute/screens/polymarket/components/bet_slip_sheet.dart';
import 'package:kute/screens/polymarket/components/slip_chrome.dart';
import 'package:kute/screens/shared/slip_shortfall.dart';
import 'package:kute/services/funding/settlement_runner.dart'
    show SettlementStepUpHook;
import 'package:kute/services/one_balance/bitcoin_funded_order.dart';
import 'package:kute/services/one_balance/empty_slip_sources.dart';
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
  Future<PendingBetIntent> prepareIntent(PendingBetIntent intent) async =>
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

/// The wallet behind the slip's own runner: the direct leg is planned on
/// the own Predictions deposit the approval bound (and found costlier
/// here), then the via-Dollars leg goes and its dollars land at once.
class _Env {
  var sends = 0;
  var directSends = 0;
  final planned = <(OneBalanceVenue, String)>[];

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
        dollarsNow: () => 0,
        freshDollars: () async => 0,
        planDirect: ({
          required OneBalanceVenue venue,
          required double fundUsd,
          required double addUsd,
          required double dollarsUsd,
          required BitcoinLegPlan via,
          required String ownVenue,
          required int directMaxSats,
        }) async {
          planned.add((venue, ownVenue));
          return const DirectBitcoinPlan.viaDollars(
              DirectBitcoinReason.costlier);
        },
        sendDirect: ({
          required OneBalanceVenue venue,
          required String ownVenue,
          required String ownSpark,
          required int sats,
          required double targetUsd,
          required SettlementStepUpHook stepUp,
          required void Function() onSending,
        }) async {
          directSends++;
          throw StateError('the direct leg was not chosen');
        },
      );
}

class _Landed extends DollarsLandingWatcher {
  _Landed()
      : super(
          statusOf: (_) async => null,
          dollarsNow: () => 0,
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
      const DollarsLanded(byStatus: true, freshDollarsUsd: 10);
}

const _outcomes = [
  PolymarketOutcome(name: 'Yes', price: 0.5, tokenId: 'yes-token'),
  PolymarketOutcome(name: 'No', price: 0.5, tokenId: 'no-token'),
];

late _Env _env;
late _Funder _funder;

Future<void> _pumpSlip(WidgetTester tester, {bool knownEmpty = false}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      slipKnownEmptySourcesProvider.overrideWith((_) => () async => knownEmpty),
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
      // $0 in Investments: no Dollars, no venue cash anywhere.
      usdBalanceProvider.overrideWithValue(0),
      polymarketFeeTermsProvider
          .overrideWith((ref, _) async => PolymarketFeeTerms.worstCase),
      polymarketBetControllerProvider.overrideWith(_Controller.new),
      polymarketMarketWindowReaderProvider
          .overrideWithValue((_) async => null),
      sparkSelfAddressProvider.overrideWith((_) async => _ownSpark),
      venueCashPullerProvider.overrideWith((_) => VenueCashPuller(
          sources: const [],
          readDollars: () => 0,
          minimumUsd: (_) async => 1)),
      bitcoinLegEnvProvider.overrideWith((_) => _env.env),
      orderFundingControllerProvider.overrideWithValue(OrderFundingController(
          funderFor: (_) => _funder, dollarsUsd: () => 0)),
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
        home: const Scaffold(
          resizeToAvoidBottomInset: false,
          body: Align(
            alignment: Alignment.bottomCenter,
            child: BetSlipSheet(
                marketQuestion: 'Will it rain?',
                outcomes: _outcomes,
                initialAmountUsd: null),
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

Finder get _door => find.byKey(const ValueKey('bet-slip-deposit-door'));

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(BetSlipSheet)));

void main() {
  late RuntimeCapabilitiesService policy;
  late List<SensitiveIntent> approvals;
  late List<String> sheets;
  late List<String> events;

  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    PredictionsVenueFunder.debugRouteShare = (_) async => 0;
    AffiliateService.debugSessionToken = 'test-session';
    FundedOrdersNotifier.persist = false;
    OrderFundingJourney.reset();
    policy = runtimePolicyFixture();
    RuntimeCapabilitiesService.debugInstance = policy;
    _env = _Env();
    _funder = _Funder();
    approvals = [];
    sheets = [];
    events = [];
    TrackingService.debugTrackObserver = (e, _) => events.add(e);
    // The spending bitcoin covers X.
    debugFreshSpendingBitcoin = () async => (sats: 1000000, usdPerBtc: 60000.0);
    debugBitcoinLegEstimate = (sats) async => sats / 1e8 * 60000 * 0.995;
    // The own Predictions deposit the approval binds the direct leg to.
    debugOwnVenueDeposit = (_) async => _pmDeposit;
    // Any sheet the slip might open, recorded: none must open.
    debugShowSlipTopUpSheet = (venue, _) async => sheets.add('top_up');
    debugShowSlipReceiveSheet = (venue, _) async => sheets.add('receive');
    debugShowEmptySlipDepositSheet = (venue, _) async => sheets.add('deposit:$venue');
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
    debugShowEmptySlipDepositSheet = null;
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

  testWidgets(
      'nothing typed, \$0 in Investments, enough bitcoin: "Add" funds the '
      'minimum bet in place under ONE approval, no sheet', (tester) async {
    expect(await policy.refresh(), isTrue);
    await _pumpSlip(tester);
    expect(_door, findsOneWidget);
    expect(_cta(tester).label, startsWith(r'Add $'));
    expect(_cta(tester).label, endsWith('to Investments'));

    await tester.tap(_door);
    await _frames(tester, 10);

    // No sheet of any kind: the slip is still the only screen.
    expect(sheets, isEmpty);
    expect(find.byType(DepositSheet), findsNothing);
    expect(events, isNot(contains('slip_top_up_opened')));

    // ONE approval, binding the bet, its move and the Bitcoin leg.
    expect(approvals, hasLength(1));
    expect(approvals.single.action, SensitiveAction.pmBet);
    expect(approvals.single.limits[VenueLimit.fundBtc], isNotNull);
    // The direct Bitcoin → Predictions leg was planned on the own deposit
    // that approval bound, before the route was picked.
    expect(_env.planned, [(OneBalanceVenue.predictions, _pmDeposit)]);
    // Costlier here: the via-Dollars leg went, once; the move followed.
    expect(_env.directSends, 0);
    expect(_env.sends, 1);
    expect(_funder.sent, hasLength(1));

    // The slip took the bet it was sized for: the market's minimum.
    final pending = _container(tester).read(pendingPolymarketBetProvider)!;
    expect(pending.amount, greaterThan(0));
    expect(pending.status, PendingBetStatus.awaitingBalance);

    // The steps, on the slip, under one busy button.
    expect(find.byKey(const ValueKey('bet-slip-funded-progress')),
        findsOneWidget);
    expect(_cta(tester).isBusy, isTrue);
    final money = '\$${pending.amount.toStringAsFixed(2)}';
    expect(find.text('Placing $money on Yes'), findsOneWidget);

    // The venue credits it and the autofire places it: never a second
    // prompt.
    final notifier =
        _container(tester).read(pendingPolymarketBetProvider.notifier);
    notifier.updateStatus(PendingBetStatus.placing);
    await _frames(tester, 3);
    notifier.updateStatus(PendingBetStatus.done);
    await _frames(tester, 3);
    final record = _container(tester).read(fundedOrdersProvider).single;
    expect(record.stage, FundedOrderStage.done);
    expect(record.label.orderUsd, pending.amount);
    expect(approvals, hasLength(1));
    await release(tester);
  });
  testWidgets('known zero across all sources opens Predictions deposit and preserves slip',
      (tester) async {
    expect(await policy.refresh(), isTrue);
    debugFreshSpendingBitcoin = () async => (sats: 0, usdPerBtc: 60000.0);
    await _pumpSlip(tester, knownEmpty: true);
    await tester.tap(_door);
    await _frames(tester, 20);
    expect(sheets, ['deposit:SlipVenue.predictions']);
    expect(find.byType(BetSlipSheet), findsOneWidget);
    expect(approvals, isEmpty);
    expect(_env.sends, 0);
    await release(tester);
  });
  testWidgets('unknown sources never open Predictions contextual deposit',
      (tester) async {
    expect(await policy.refresh(), isTrue);
    debugFreshSpendingBitcoin = () async => (sats: 0, usdPerBtc: 60000.0);
    await _pumpSlip(tester);
    await tester.tap(_door);
    await _frames(tester, 20);
    expect(sheets, ['receive']);
    expect(approvals, isEmpty);
    await release(tester);
  });
}
