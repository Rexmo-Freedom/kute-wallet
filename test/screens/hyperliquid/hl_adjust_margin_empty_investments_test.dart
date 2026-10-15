// An empty Investments balance takes the same path as a partly funded one
// (founder, 15 October 2026), for adding margin too: with $0 in
// Investments and enough spending bitcoin, "Add $X to Investments" on the
// margin sheet is the change itself, funded in place under ONE approval
// with the steps on the sheet. No deposit or Receive sheet is pushed, and
// the direct Bitcoin → Investing leg is planned before the chain picks
// its route.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/spark_address_provider.dart'
    show sparkSelfAddressProvider;
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider;
import 'package:kute/screens/home/components/deposit_sheet.dart'
    show DepositSheet;
import 'package:kute/screens/hyperliquid/components/hl_adjust_margin_sheet.dart';
import 'package:kute/screens/polymarket/components/slip_chrome.dart';
import 'package:kute/screens/shared/amount_keypad_panel.dart';
import 'package:kute/screens/shared/slip_shortfall.dart';
import 'package:kute/services/funding/settlement_runner.dart'
    show SettlementStepUpHook;
import 'package:kute/services/one_balance/bitcoin_funded_order.dart';
import 'package:kute/services/one_balance/bitcoin_to_dollars_leg.dart';
import 'package:kute/services/one_balance/bitcoin_to_venue_leg.dart';
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/services/one_balance/hyperliquid_venue_funder.dart';
import 'package:kute/services/one_balance/investments_spendable.dart';
import 'package:kute/services/one_balance/margin_funding.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/order_funding.dart';
import 'package:kute/services/one_balance/venue_cash_source.dart';
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart';

const _ownSpark =
    'spark1pgss93sy072yrmtad5cy2srwjhq8ekzuw78yhr808jn6htqfh9w8p8h9mfwlv9';
const _hlAccount = '0x2222222222222222222222222222222222222222';

class _LivePrices extends HlLivePricesNotifier {
  @override
  HlLivePriceState build() => const HlLivePriceState(mids: {});
  @override
  void watchCoins(List<String> coins, {Map<String, String>? wire}) {}
  @override
  void focus(String coin, {String? wire}) {}
  @override
  void unfocus(String coin) {}
  @override
  void acquire() {}
  @override
  void release() {}
}

/// The Investing account holds no free cash.
class _Trading extends HyperliquidTradingNotifier {
  @override
  Future<HyperliquidTradingState> build() async =>
      const HyperliquidTradingState(isInitialized: true, withdrawable: 0);
}

class _Currency extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _Currency() : super(CurrencyState({'USD': Fixed.fromInt(60000)}));
  @override
  Future<void> updateRates() async {}
}

class _Allowed extends Fake implements RuntimeCapabilitiesService {
  @override
  CapabilityDecision decision(String id) =>
      const CapabilityDecision(allowed: true);
  @override
  String? blockReason(String id) => null;
}

/// Dollars → Investing at a flat $1, recording every move.
class _Funder implements VenueFunder {
  final sent = <double>[];

  @override
  Future<VenueMoveQuote> estimate(double usd) async => VenueMoveQuote(
      arrivingUsd: usd - 1,
      feeUsd: 1,
      fixedCostUsd: 0,
      minUsd: 1,
      maxUsd: 100000);

  @override
  Future<VenueMoveResult> fund(
      {required double usd,
      required MoveAuthorization auth,
      String purpose = 'order_funding'}) async {
    sent.add(usd);
    return VenueMoveResult(
        quoteId: 'q_venue', sentUsd: usd, arrivingUsdEstimate: usd - 1);
  }

  @override
  Future<double> idleUsd() async => 0;

  @override
  Future<double> minimumUsd() async => 1;
}

/// The wallet behind the runner: the direct leg is planned on the own
/// Investing account the approval bound (and found costlier here), then
/// the via-Dollars leg goes; its dollars land once [landing] completes.
class _Bitcoin {
  var sends = 0;
  var directSends = 0;
  final planned = <(OneBalanceVenue, String)>[];
  final landing = Completer<void>();

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
        watcher: ({required DateTime since}) => _Landed(landing.future),
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
  _Landed(this.gate)
      : super(
          statusOf: (_) async => null,
          dollarsNow: () => 0,
          freshDollars: () async => null,
          kickSync: () {},
        );
  final Future<void> gate;

  @override
  Future<DollarsLandingOutcome> watch({
    required String Function() id,
    required double baselineUsd,
    required double minRiseUsd,
    required double enoughUsd,
    void Function()? onSlow,
  }) async {
    await gate;
    return const DollarsLanded(byStatus: true, freshDollarsUsd: 100);
  }
}

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

/// The Investing account as the chain reads it (credited once [landed]),
/// and the signatures.
class _Account {
  _Account(this.landed);
  final bool Function() landed;
  final signed = <double>[];

  MarginChainEnv get env => MarginChainEnv(
        account: () async =>
            (cashUsd: landed() ? 100.0 : 0.0, positions: const [_long]),
        adjust: ({
          required HlMarket market,
          required HlPerpPosition position,
          required double usd,
          required AuthGrant grant,
        }) async =>
            signed.add(usd),
        hold: () => () {},
        sleep: (d) => Future<void>.delayed(d),
      );
}

/// Spinners animate for as long as they wait: pump, never settle.
Future<void> _frames(WidgetTester tester, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

PolySlipCta _cta(WidgetTester tester) =>
    tester.widget<PolySlipCta>(find.byType(PolySlipCta));

void main() {
  late _Funder funder;
  late _Bitcoin bitcoin;
  late _Account account;
  late List<SensitiveIntent> approvals;
  late List<String> sheets;
  late List<String> events;

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    FundedOrdersNotifier.persist = false;
    OrderFundingJourney.reset();
    funder = _Funder();
    bitcoin = _Bitcoin();
    account = _Account(() => bitcoin.landing.isCompleted);
    approvals = [];
    sheets = [];
    events = [];
    TrackingService.debugTrackObserver = (e, _) => events.add(e);
    // The spending bitcoin covers X.
    debugFreshSpendingBitcoin =
        () async => (sats: 100000000, usdPerBtc: 60000.0);
    debugBitcoinLegEstimate = (sats) async => sats / 1e8 * 60000 * 0.995;
    // The own Investing account the approval binds the direct leg to.
    debugOwnVenueDeposit = (_) async => _hlAccount;
    debugShowSlipReceiveSheet = (venue, _) async => sheets.add('receive');
    debugShowSlipTopUpSheet = (venue, _) async => sheets.add('top_up');
    // The ONE prompt, approved.
    debugHlMarginApproval = (intent) async {
      approvals.add(intent);
      return AuthGrants.issue(intent, method: AuthGrantMethod.biometric);
    };
  });

  tearDown(() {
    FundedOrdersNotifier.persist = true;
    TrackingService.debugTrackObserver = null;
    debugFreshSpendingBitcoin = null;
    debugBitcoinLegEstimate = null;
    debugOwnVenueDeposit = null;
    debugShowSlipReceiveSheet = null;
    debugShowSlipTopUpSheet = null;
    debugHlMarginApproval = null;
  });

  testWidgets(
      '\$0 in Investments, enough bitcoin: "Add" funds the margin in place '
      'under ONE approval, no sheet', (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        hyperliquidLivePricesProvider.overrideWith(_LivePrices.new),
        hyperliquidTradingProvider.overrideWith(_Trading.new),
        hyperliquidPerpPositionsProvider.overrideWith((_) => const [_long]),
        // $0 in Investments: no Dollars, no venue cash anywhere.
        usdBalanceProvider.overrideWith((_) => 0),
        investmentsSpendableExcludingProvider.overrideWith((_, __) =>
            const InvestmentsSpendable(
                dollarsUsd: 0, venueCashUsd: 0, maxUsd: 0)),
        venueCashRefreshProvider.overrideWith((_) async {}),
        venueCashReachExcludingProvider.overrideWith((_, __) async => 0),
        hyperliquidVenueFunderProvider.overrideWithValue(funder),
        venueCashPullerProvider.overrideWith((_) => VenueCashPuller(
            sources: const [],
            readDollars: () => 0,
            minimumUsd: (_) async => 1)),
        orderFundingControllerProvider.overrideWithValue(OrderFundingController(
            funderFor: (_) => funder, dollarsUsd: () => 0)),
        marginChainEnvProvider.overrideWithValue(account.env),
        bitcoinLegEnvProvider.overrideWithValue(bitcoin.env),
        sparkSelfAddressProvider.overrideWith((_) async => _ownSpark),
        runtimeCapabilitiesProvider.overrideWithValue(_Allowed()),
        settingsProvider.overrideWith((_) => SettingsModel(Settings(
              currency: 'USD',
              language: 'en',
              btcFormat: 'sats',
              backup: false,
              biometricsEnabled: false,
              bitcoinElectrumNode: '',
              nodeType: 'Blockstream',
              reviewDone: false,
              wallets: [WalletConfig(id: 'w', name: 'Spending')],
              activeWalletId: 'w',
            ))),
        currencyProvider.overrideWith((_) => _Currency()),
      ],
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          theme: ThemeData(
            splashFactory: NoSplash.splashFactory,
            extensions: [AppColorsExtension.light()],
          ),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: HlAdjustMarginSheet(
                  position: _long,
                  market: _market,
                  add: true,
                  source: HlMarginSource.liquidationRow),
            ),
          ),
        ),
      ),
    ));
    await _frames(tester);

    // $30 of margin with nothing in Investments.
    final pad = find.byType(AmountKeypad);
    for (final key in '30'.split('')) {
      await tester.tap(find.descendant(of: pad, matching: find.text(key)));
      await tester.pump();
    }
    await _frames(tester, 5);
    expect(_cta(tester).label, startsWith(r'Add $'));
    expect(_cta(tester).label, endsWith('to Investments'));
    expect(_cta(tester).enabled, isTrue);

    await tester.tap(find.byType(PolySlipCta));
    await _frames(tester, 10);

    // No sheet of any kind: the margin sheet is still the only screen.
    expect(sheets, isEmpty);
    expect(find.byType(DepositSheet), findsNothing);
    expect(events, isNot(contains('slip_top_up_opened')));

    // ONE approval, binding the change, its move and the Bitcoin leg.
    expect(approvals, hasLength(1));
    expect(approvals.single.limits[VenueLimit.fundBtc], isNotNull);
    // The direct Bitcoin → Investing leg was planned on the own account
    // that approval bound, before the route was picked.
    expect(bitcoin.planned, [(OneBalanceVenue.investing, _hlAccount)]);
    // Costlier here: the via-Dollars leg went, once.
    expect(bitcoin.directSends, 0);
    expect(bitcoin.sends, 1);

    // The steps, on the sheet, under one busy button, while the bitcoin's
    // dollars land.
    expect(find.byType(SlipFundingSteps), findsOneWidget);
    expect(find.text(r'Adding $30.00 margin to TSLA'), findsWidgets);
    expect(_cta(tester).isBusy, isTrue);
    expect(account.signed, isEmpty);

    // The dollars land: the change is signed once, never a second prompt.
    bitcoin.landing.complete();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(account.signed, [30]);
    expect(approvals, hasLength(1));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 31));
  });
}
