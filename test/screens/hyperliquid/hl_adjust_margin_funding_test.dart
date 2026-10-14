// Adding margin is funded like the Investing order slip (founder, 14
// October 2026): "Available" and Max are the whole spendable Investments,
// an Add the whole balance cannot fund reads "Add $X to Investments" and,
// when the bitcoin cannot cover X, opens the Investments Receive sheet;
// a funded change shows the slips' staged steps under its one button, and
// a chain that stopped with the bitcoin's money in Investments says so.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:money2/money2.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider;
import 'package:kute/screens/hyperliquid/components/hl_adjust_margin_sheet.dart';
import 'package:kute/screens/polymarket/components/slip_chrome.dart';
import 'package:kute/screens/shared/amount_keypad_panel.dart';
import 'package:kute/screens/shared/slip_shortfall.dart';
import 'package:kute/services/one_balance/bitcoin_funded_order.dart'
    show debugFreshSpendingBitcoin;
import 'package:kute/services/one_balance/bitcoin_to_dollars_leg.dart';
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/services/one_balance/hyperliquid_venue_funder.dart';
import 'package:kute/services/one_balance/investments_spendable.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/venue_cash_source.dart'
    show venueCashReachExcludingProvider;
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

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

class _Trading extends HyperliquidTradingNotifier {
  @override
  Future<HyperliquidTradingState> build() async =>
      const HyperliquidTradingState(isInitialized: true, withdrawable: 100);
}

class _Currency extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _Currency() : super(CurrencyState({'USD': Fixed.fromInt(100)}));
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

class _Funded extends FundedOrdersNotifier {
  _Funded(this.records);
  final List<FundedOrderRecord> records;
  @override
  List<FundedOrderRecord> build() => records;
}

/// The route's estimate never answers here: the sheet prices the move on
/// its fallback.
class _NoEstimate implements VenueFunder {
  @override
  Future<VenueMoveQuote> estimate(double usd) => Future.error('offline');
  @override
  Future<VenueMoveResult> fund(
          {required double usd,
          required MoveAuthorization auth,
          String purpose = 'order_funding'}) =>
      throw UnimplementedError();
  @override
  Future<double> idleUsd() async => 0;
  @override
  Future<double> minimumUsd() async => 1;
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

FundedOrderRecord _record(FundedOrderStage stage,
        {double addUsd = 9.49, bool slow = false}) =>
    FundedOrderRecord(
      id: 'fo_margin',
      label: const FundedOrderLabel(
        venue: OneBalanceVenue.investing,
        orderUsd: 30,
        side: 'Long',
        market: 'TSLA',
        marketKey: 'TSLA',
        kind: FundedOrderKind.margin,
      ),
      stage: stage,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      addUsd: addUsd,
      btcRowIds: addUsd > 0 ? const {'q_btc'} : const {},
      slow: slow,
    );

Future<void> _pump(
  WidgetTester tester, {
  double dollars = 20,
  double otherSpendable = 49,
  double reach = 49,
  List<FundedOrderRecord> funded = const [],
  Size size = const Size(390, 1600),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      hyperliquidLivePricesProvider.overrideWith(_LivePrices.new),
      hyperliquidTradingProvider.overrideWith(_Trading.new),
      hyperliquidPerpPositionsProvider.overrideWith((_) => const [_long]),
      usdBalanceProvider.overrideWith((_) => dollars),
      investmentsSpendableExcludingProvider.overrideWith((_, __) =>
          InvestmentsSpendable(
              dollarsUsd: dollars,
              venueCashUsd: otherSpendable - dollars,
              maxUsd: otherSpendable)),
      venueCashRefreshProvider.overrideWith((_) async {}),
      venueCashReachExcludingProvider.overrideWith((_, __) async => reach),
      hyperliquidVenueFunderProvider.overrideWithValue(_NoEstimate()),
      fundedOrdersProvider.overrideWith(() => _Funded(funded)),
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
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
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
}

/// Spinners animate for as long as they wait: pump, never settle.
Future<void> _frames(WidgetTester tester, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _type(WidgetTester tester, String amount) async {
  final pad = find.byType(AmountKeypad);
  for (final key in amount.split('')) {
    await tester.tap(find.descendant(of: pad, matching: find.text(key)));
    await tester.pump();
  }
  await _frames(tester, 5);
}

PolySlipCta _cta(WidgetTester tester) =>
    tester.widget<PolySlipCta>(find.byType(PolySlipCta));

double _typed(WidgetTester tester) =>
    double.parse(tester.widget<AmountKeypad>(find.byType(AmountKeypad)).value);

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);
  tearDown(() {
    debugFreshSpendingBitcoin = null;
    debugShowSlipReceiveSheet = null;
    TrackingService.debugTrackObserver = null;
  });

  testWidgets(
      'Available and Max on Add are the whole spendable Investments, and '
      'Max is an addition the sheet funds itself', (tester) async {
    await _pump(tester);
    // $100 of Investing cash plus the $49 Dollars and Predictions bring.
    expect(find.text(r'Available: $149.00'), findsOneWidget);
    await tester.tap(find.text('Max'));
    await _frames(tester, 2);
    final max = _typed(tester);
    // Beyond the Investing cash, short of the total by the move's cost.
    expect(max, greaterThan(100));
    expect(max, lessThan(149));
    expect(_cta(tester).label, 'Add margin');
    expect(_cta(tester).enabled, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'more than Investments can fund: "Add \$X to Investments"; bitcoin '
      'short of X opens the Investments Receive sheet for X', (tester) async {
    final receives = <(SlipVenue, double)>[];
    debugShowSlipReceiveSheet = (venue, addUsd) async {
      receives.add((venue, addUsd));
    };
    debugFreshSpendingBitcoin = () async => (sats: 0, usdPerBtc: 60000.0);
    final events = <(String, Map<String, Object>?)>[];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));

    await _pump(tester);
    await _type(tester, '200');
    // $100 short: the fallback move for it, less the $49 Investments hold.
    final fund = HlAdjustMarginSheetFunding.fallback(100).fundUsd;
    final x = BitcoinLegRules.addUsd(fundUsd: fund, investmentsUsd: 49);
    expect(x, greaterThan(0));
    final label = _cta(tester).label;
    expect(label, startsWith(r'Add $'));
    expect(label, endsWith('to Investments'));
    expect(label, contains(x.toStringAsFixed(2)));
    expect(_cta(tester).enabled, isTrue);

    await tester.tap(find.byType(PolySlipCta));
    await _frames(tester, 4);
    expect(receives, [(SlipVenue.investing, x)]);
    final topUp = events.singleWhere((e) => e.$1 == 'slip_top_up_opened').$2!;
    expect(topUp['venue'], 'hyperliquid');
    expect(topUp['entry_source'], 'add_margin');
    expect(topUp['prefill_rule'], 'investments_shortfall');
    expect(topUp['suggested_source'], 'receive');
    expect(topUp['top_up_usd'], x);
    expect(topUp['shortfall_usd'], 100);
    expect(tester.takeException(), isNull);
  });

  group('a funded change on its way shows the steps', () {
    testWidgets('bitcoin: adding, preparing, then the margin change',
        (tester) async {
      await _pump(tester,
          funded: [_record(FundedOrderStage.preparing, slow: true)]);
      expect(find.byType(SlipFundingSteps), findsOneWidget);
      expect(find.text(r'Adding $9.49 to Investments'), findsOneWidget);
      expect(find.text('Preparing your order'), findsWidgets);
      expect(find.text(r'Adding $30.00 margin to TSLA'), findsOneWidget);
      expect(find.byKey(const ValueKey('slip-funding-step-done-0')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('slip-funding-step-active-1')),
          findsOneWidget);
      expect(find.text('Taking longer than usual'), findsOneWidget);
      // One busy button saying the step; the keypad is shut.
      expect(_cta(tester).isBusy, isTrue);
      expect(_cta(tester).busyLabel, 'Preparing your order');
      expect(tester.widget<AmountKeypad>(find.byType(AmountKeypad)).enabled,
          isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no bitcoin: preparing, then signing the change',
        (tester) async {
      await _pump(tester,
          funded: [_record(FundedOrderStage.placing, addUsd: 0)]);
      final steps =
          tester.widget<SlipFundingSteps>(find.byType(SlipFundingSteps));
      expect(steps.steps,
          ['Preparing your order', r'Adding $30.00 margin to TSLA']);
      expect(steps.active, 1);
      expect(_cta(tester).busyLabel, r'Adding $30.00 margin to TSLA');
    });

    testWidgets('stopped with the money in Investments: tap to add margin',
        (tester) async {
      await _pump(tester, funded: [_record(FundedOrderStage.ready)]);
      expect(find.byType(SlipFundingSteps), findsNothing);
      expect(find.text(r'Your $9.49 is in Investments. Tap to add margin.'),
          findsOneWidget);
      expect(_cta(tester).isBusy, isFalse);
    });
  });

  testWidgets('no overflow at 375pt and text scale 1.3: the steps',
      (tester) async {
    await _pump(tester,
        size: const Size(375, 812),
        textScale: 1.3,
        funded: [_record(FundedOrderStage.adding, slow: true)]);
    expect(find.byType(SlipFundingSteps), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no overflow at 375pt and text scale 1.3: the door',
      (tester) async {
    // A long amount on the button.
    await _pump(tester, size: const Size(375, 812), textScale: 1.3);
    await _type(tester, '9999');
    expect(_cta(tester).label, endsWith('to Investments'));
    expect(tester.takeException(), isNull);
  });
}
