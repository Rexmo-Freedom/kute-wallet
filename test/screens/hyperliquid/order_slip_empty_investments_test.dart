// An empty Investments balance takes the same path as a partly funded one
// (founder, 15 October 2026): nothing typed on a hot Investing ticket
// whose Investments hold $0, with enough spending bitcoin, "Add $X to
// Investments" is the order itself at the market's minimum, funded in
// place under ONE approval with the steps on the ticket. No deposit sheet
// is ever pushed, and the direct Bitcoin → Investing leg is planned
// before the chain picks its route. The bet slip does the same
// (bet_slip_empty_investments_test).

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
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_orderbook_provider.dart';
import 'package:kute/providers/pending_hyperliquid_order_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/spark_address_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/providers/usd_account_provider.dart';
import 'package:kute/screens/home/components/deposit_sheet.dart'
    show DepositSheet;
import 'package:kute/screens/hyperliquid/components/order_slip_sheet.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/slip_shortfall.dart';
import 'package:kute/services/funding/settlement_runner.dart'
    show SettlementStepUpHook;
import 'package:kute/services/one_balance/bitcoin_funded_order.dart';
import 'package:kute/services/one_balance/empty_slip_sources.dart';
import 'package:kute/services/one_balance/bitcoin_to_dollars_leg.dart';
import 'package:kute/services/one_balance/bitcoin_to_venue_leg.dart';
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/services/one_balance/hyperliquid_move_rail.dart';
import 'package:kute/services/one_balance/one_balance_state.dart'
    show OneBalanceVenue;
import 'package:kute/services/one_balance/order_funding.dart';
import 'package:kute/services/one_balance/venue_cash_source.dart';
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart';

import '../../helpers/fake_hyperliquid_move_rail.dart';
import '../../helpers/fake_swap_orders.dart';
import '../../helpers/runtime_policy_fixture.dart';

const _ownSpark =
    'spark1pgss93sy072yrmtad5cy2srwjhq8ekzuw78yhr808jn6htqfh9w8p8h9mfwlv9';
const _hlAccount = '0x2222222222222222222222222222222222222222';

class _LivePrices extends HlLivePricesNotifier {
  @override
  HlLivePriceState build() => const HlLivePriceState(mids: {'BTC': 60000});
  @override
  void acquire() {}
  @override
  void release() {}
  @override
  void watchCoins(List<String> coins, {Map<String, String>? wire}) {}
}

class _Currency extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _Currency() : super(CurrencyState({'USD': Fixed.fromInt(1)}));
  @override
  Future<void> updateRates() async {}
}

class _Allowed extends Fake implements RuntimeCapabilitiesService {
  @override
  CapabilityDecision decision(String id) =>
      const CapabilityDecision(allowed: true);
  @override
  String? blockReason(String id) => null;
  @override
  Future<void> ensureAllAllowed(Iterable<String> ids,
      {Duration maxAge = Duration.zero}) async {}
  @override
  int? get maxLeverage => null;
  @override
  int offeredLeverage(int venueMax) => venueMax;
}

/// The Investing account holds nothing.
class _Account extends HlAccountNotifier {
  @override
  Future<HlAccountSnapshot> build() async => const HlAccountSnapshot(
        accountValue: 0,
        withdrawable: 0,
        totalMarginUsed: 0,
        positions: [],
        spotBalances: [],
      );
}

const _market = HlMarket(
  coin: 'BTC',
  wireCoin: 'BTC',
  assetId: 0,
  kind: HlMarketKind.perp,
  szDecimals: 5,
  maxLeverage: 40,
  onlyIsolated: false,
  markPx: 60000,
  midPx: 60000,
  prevDayPx: 60000,
  dayNtlVlm: 0,
);

/// The rail's estimate at the very amount sent: a 0.1% route with the $1
/// gas float on an empty account.
class _Rail extends FakeHyperliquidMoveRail {
  @override
  Future<VenueMoveQuote> estimate(
          {required double usd, required bool deposit}) async =>
      VenueMoveQuote(
          arrivingUsd: usd * 0.999 - 1,
          feeUsd: usd * 0.001,
          fixedCostUsd: 1,
          minUsd: 0.8,
          maxUsd: 107600);
}

/// The Dollars → Investing move, recording what left.
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

/// The wallet behind the ticket's own runner: the direct leg is planned
/// on the own Investing account the approval bound (and found costlier
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
      const DollarsLanded(byStatus: true, freshDollarsUsd: 100);
}

late _Env _env;
late _Funder _funder;

Future<void> _pumpSlip(WidgetTester tester, FakeHyperliquidMoveRail rail,
    {bool knownEmpty = false}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      slipKnownEmptySourcesProvider.overrideWith((_) => () async => knownEmpty),
      settingsProvider.overrideWith((_) => SettingsModel(Settings(
            currency: 'USD',
            language: 'en',
            btcFormat: 'sats',
            backup: false,
            biometricsEnabled: false,
            bitcoinElectrumNode: '',
            nodeType: 'Blockstream',
            reviewDone: false,
            wallets: [WalletConfig(id: 'w1', name: 'Spending')],
            activeWalletId: 'w1',
          ))),
      hyperliquidLivePricesProvider.overrideWith(_LivePrices.new),
      hyperliquidAccountProvider.overrideWith(_Account.new),
      swapOrdersProvider.overrideWith((_) => FakeSwapOrders()),
      hyperliquidAddressProvider.overrideWith((_) async => null),
      hyperliquidOrderbookProvider
          .overrideWith((_, __) => Stream.value(const HlOrderBookState())),
      aiEnabledProvider.overrideWith((_) async => false),
      currencyProvider.overrideWith((_) => _Currency()),
      runtimeCapabilitiesProvider.overrideWithValue(_Allowed()),
      // $0 in Investments: no Dollars, no venue cash anywhere.
      usdBalanceProvider.overrideWith((_) => 0),
      hyperliquidMoveRailProvider.overrideWithValue(rail),
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
          extensions: [AppColorsExtension.light()],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: HlOrderSlipSheet(market: _market, initialIsLong: true),
          ),
        ),
      ),
    ),
  ));
  await _frames(tester);
}

Future<void> _frames(WidgetTester tester, [int n = 10]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

AppButton _button(WidgetTester tester) =>
    tester.widget<AppButton>(find.byType(AppButton));

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(HlOrderSlipSheet)));

void main() {
  late FakeHyperliquidMoveRail rail;
  late List<SensitiveIntent> approvals;
  late List<String> sheets;
  late List<String> events;
  late RuntimeCapabilitiesService policy;

  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    AffiliateService.debugSessionToken = 'test-session';
    // The geo and capability re-check at the confirm: allowed.
    policy = runtimePolicyFixture();
    RuntimeCapabilitiesService.debugInstance = policy;
    expect(await policy.refresh(), isTrue);
    FundedOrdersNotifier.persist = false;
    OrderFundingJourney.reset();
    rail = _Rail();
    _env = _Env();
    _funder = _Funder();
    approvals = [];
    sheets = [];
    events = [];
    TrackingService.debugTrackObserver = (e, _) => events.add(e);
    // The spending bitcoin covers X.
    debugFreshSpendingBitcoin = () async => (sats: 1000000, usdPerBtc: 60000.0);
    debugBitcoinLegEstimate = (sats) async => sats / 1e8 * 60000 * 0.995;
    // The own Investing account the approval binds the direct leg to.
    debugOwnVenueDeposit = (_) async => _hlAccount;
    // Any sheet the ticket might open, recorded: none must open.
    debugShowHlDollarsDeposit = (side, _) async => sheets.add('dollars');
    debugShowSlipTopUpSheet = (venue, _) async => sheets.add('top_up');
    debugShowSlipReceiveSheet = (venue, _) async => sheets.add('receive');
    debugShowEmptySlipDepositSheet = (venue, _) async => sheets.add('deposit:$venue');
    // The ONE prompt, approved.
    debugHlOrderFundingApproval = (intent) async {
      approvals.add(intent);
      return AuthGrantRegistry.instance.issueAutofire(
          kPendingHlOrderAutofireId, intent,
          method: AuthGrantMethod.biometric);
    };
  });

  tearDown(() {
    debugFreshSpendingBitcoin = null;
    debugBitcoinLegEstimate = null;
    debugOwnVenueDeposit = null;
    debugShowHlDollarsDeposit = null;
    debugShowSlipTopUpSheet = null;
    debugShowSlipReceiveSheet = null;
    debugShowEmptySlipDepositSheet = null;
    debugHlOrderFundingApproval = null;
    AuthGrantRegistry.instance.cancelAutofire(kPendingHlOrderAutofireId);
    RuntimeCapabilitiesService.debugInstance = null;
    policy.dispose();
    FundedOrdersNotifier.persist = true;
    AffiliateService.debugSessionToken = null;
    TrackingService.debugTrackObserver = null;
    rail.creditedController.close();
  });

  Future<void> release(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    // Past the autofire grant's own 30-minute life.
    await tester.pump(const Duration(minutes: 31));
  }

  testWidgets(
      'nothing typed, \$0 in Investments, enough bitcoin: "Add" funds the '
      'minimum order in place under ONE approval, no sheet', (tester) async {
    await _pumpSlip(tester, rail);
    expect(_button(tester).text, startsWith(r'Add $'));
    expect(_button(tester).text, endsWith('to Investments'));

    await tester.tap(find.byType(AppButton));
    await _frames(tester, 20);

    // No sheet of any kind: the ticket is still the only screen.
    expect(sheets, isEmpty);
    expect(find.byType(DepositSheet), findsNothing);
    expect(events, isNot(contains('slip_top_up_opened')));

    // ONE approval, binding the order, its move and the Bitcoin leg.
    expect(approvals, hasLength(1));
    expect(approvals.single.action, SensitiveAction.hlOrder);
    expect(approvals.single.limits[VenueLimit.fundBtc], isNotNull);
    // The direct Bitcoin → Investing leg was planned on the own account
    // that approval bound, before the route was picked.
    expect(_env.planned, [(OneBalanceVenue.investing, _hlAccount)]);
    // Costlier here: the via-Dollars leg went, once; the move followed.
    expect(_env.directSends, 0);
    expect(_env.sends, 1);
    expect(_funder.sent, hasLength(1));

    // The ticket took the order it was sized for: the market's minimum.
    final pending = _container(tester).read(pendingHyperliquidOrderProvider)!;
    expect(pending.marginUsd, greaterThan(0));
    expect(pending.fundingSource, 'bitcoin');

    // The steps, on the ticket, under one busy button.
    expect(find.byKey(const ValueKey('order-slip-funded-progress')),
        findsOneWidget);
    expect(_button(tester).isLoading, isTrue);

    // The venue credits it and the autofire places it: never a second
    // prompt.
    final notifier =
        _container(tester).read(pendingHyperliquidOrderProvider.notifier);
    notifier.updateStatus(PendingHlOrderStatus.placing);
    await _frames(tester, 3);
    notifier.updateStatus(PendingHlOrderStatus.done);
    await _frames(tester, 3);
    final record = _container(tester).read(fundedOrdersProvider).single;
    expect(record.stage, FundedOrderStage.done);
    expect(approvals, hasLength(1));
    await release(tester);
  });
  testWidgets('known zero across all sources opens Investing deposit and preserves slip',
      (tester) async {
    debugFreshSpendingBitcoin = () async => (sats: 0, usdPerBtc: 60000.0);
    await _pumpSlip(tester, rail, knownEmpty: true);
    await tester.tap(find.byType(AppButton));
    await _frames(tester, 20);
    expect(sheets, ['deposit:SlipVenue.investing']);
    expect(find.byType(HlOrderSlipSheet), findsOneWidget);
    expect(approvals, isEmpty);
    expect(_env.sends, 0);
    await release(tester);
  });
  testWidgets('unknown sources never open the contextual deposit', (tester) async {
    debugFreshSpendingBitcoin = () async => (sats: 0, usdPerBtc: 60000.0);
    await _pumpSlip(tester, rail);
    await tester.tap(find.byType(AppButton));
    await _frames(tester, 20);
    expect(sheets, ['receive']);
    expect(approvals, isEmpty);
    await release(tester);
  });
}
