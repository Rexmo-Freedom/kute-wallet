// A funded margin change wears ONE rubber band over its button and the
// slips' steps (founder, 14 October 2026): pulled harder as the steps
// advance, snapping back with a light tap when the change is signed,
// letting go softly when it stopped, and still under Reduce Motion. The
// button inside does not pull a second band of its own.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider;
import 'package:kute/screens/hyperliquid/components/hl_adjust_margin_sheet.dart';
import 'package:kute/screens/polymarket/components/slip_chrome.dart';
import 'package:kute/screens/shared/rubber_band_progress.dart';
import 'package:kute/services/continuous_haptics.dart';
import 'package:kute/screens/shared/slip_shortfall.dart';
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/services/one_balance/hyperliquid_venue_funder.dart';
import 'package:kute/services/one_balance/investments_spendable.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/venue_cash_source.dart'
    show venueCashReachExcludingProvider;
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart';

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

/// The funded change's record, moved along by the test.
class _Funded extends FundedOrdersNotifier {
  _Funded(this.initial);
  final List<FundedOrderRecord> initial;
  @override
  List<FundedOrderRecord> build() => initial;
  void move(List<FundedOrderRecord> records) => state = records;
}

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

FundedOrderRecord _record(FundedOrderStage stage) => FundedOrderRecord(
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
      addUsd: 9.49,
      btcRowIds: const {'q_btc'},
    );

/// The steps band: the one over the button and its steps.
final _stepsBand =
    find.byWidgetPredicate((w) => w is RubberBandProgress && w.child is Column);

RubberBandProgressState _band(WidgetTester tester) =>
    tester.state<RubberBandProgressState>(_stepsBand);

Future<void> _frames(WidgetTester tester, int n,
    [Duration step = const Duration(milliseconds: 50)]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(step);
  }
}

void main() {
  late List<MethodCall> platform;

  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<_Funded> pump(WidgetTester tester,
      {required List<FundedOrderRecord> funded,
      bool reduceMotion = false}) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    platform = [];
    ContinuousHaptics.debugReset();
    ContinuousHaptics.debugLog = [];
    addTearDown(() => ContinuousHaptics.debugLog = null);
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      platform.add(call);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    final notifier = _Funded(funded);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        hyperliquidLivePricesProvider.overrideWith(_LivePrices.new),
        hyperliquidTradingProvider.overrideWith(_Trading.new),
        hyperliquidPerpPositionsProvider.overrideWith((_) => const [_long]),
        usdBalanceProvider.overrideWith((_) => 20),
        investmentsSpendableExcludingProvider.overrideWith((_, __) =>
            const InvestmentsSpendable(
                dollarsUsd: 20, venueCashUsd: 29, maxUsd: 49)),
        venueCashRefreshProvider.overrideWith((_) async {}),
        venueCashReachExcludingProvider.overrideWith((_, __) async => 49),
        hyperliquidVenueFunderProvider.overrideWithValue(_NoEstimate()),
        fundedOrdersProvider.overrideWith(() => notifier),
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
                .copyWith(disableAnimations: reduceMotion),
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
    await _frames(tester, 6);
    return notifier;
  }

  // The whoosh and the snap, through the haptics bridge's test seam.
  int snapTaps() =>
      ContinuousHaptics.debugLog!.where((c) => c.method == 'snap').length;

  testWidgets(
      'the steps pull one band, harder as they advance; the button inside '
      'pulls none of its own', (tester) async {
    final funded =
        await pump(tester, funded: [_record(FundedOrderStage.adding)]);
    expect(find.byType(SlipFundingSteps), findsOneWidget);
    expect(find.byType(RubberBandProgress), findsOneWidget,
        reason: 'one band, not doubled');
    expect(tester.widget<PolySlipCta>(find.byType(PolySlipCta)).band, isFalse);
    // Adding (step 1 of 3).
    expect(tester.widget<RubberBandProgress>(_stepsBand).progress,
        closeTo(0.9 * 1 / 3, 1e-9));
    await _frames(tester, 20);
    final first = _band(tester).stretch;
    expect(first, greaterThan(0));
    expect(_band(tester).ticking, isTrue);

    // Signing the change (step 3 of 3): pulled harder.
    funded.move([_record(FundedOrderStage.placing)]);
    await _frames(tester, 20);
    expect(tester.widget<RubberBandProgress>(_stepsBand).progress,
        closeTo(0.9, 1e-9));
    expect(_band(tester).stretch, greaterThan(first));
    expect(tester.takeException(), isNull);
  });

  testWidgets('done: the band snaps past rest with a light tap and settles',
      (tester) async {
    final funded =
        await pump(tester, funded: [_record(FundedOrderStage.placing)]);
    await _frames(tester, 20);
    expect(_band(tester).stretch, greaterThan(0));
    final tapsBefore = snapTaps();

    funded.move([_record(FundedOrderStage.done)]);
    var min = double.infinity;
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final s = _band(tester).stretch;
      if (s < min) min = s;
    }
    expect(min, lessThan(0), reason: 'the snap overshoots past rest');
    expect(snapTaps() - tapsBefore, 1);
    await _frames(tester, 40);
    expect(_band(tester).stretch, 0);
    expect(_band(tester).ticking, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stopped: a soft release, never past rest, no tap',
      (tester) async {
    final funded =
        await pump(tester, funded: [_record(FundedOrderStage.placing)]);
    await _frames(tester, 20);
    expect(_band(tester).stretch, greaterThan(0));
    final tapsBefore = snapTaps();

    funded.move([_record(FundedOrderStage.ready)]);
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(_band(tester).stretch, greaterThanOrEqualTo(-1e-9),
          reason: 'never past rest');
    }
    await _frames(tester, 20);
    expect(_band(tester).stretch, 0);
    expect(_band(tester).ticking, isFalse);
    expect(snapTaps(), tapsBefore);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Reduce Motion: the steps band never moves', (tester) async {
    final funded = await pump(tester,
        funded: [_record(FundedOrderStage.placing)], reduceMotion: true);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      expect(_band(tester).stretch, 0);
    }
    expect(_band(tester).ticking, isFalse);
    funded.move([_record(FundedOrderStage.done)]);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      expect(_band(tester).stretch, 0);
    }
    expect(tester.takeException(), isNull);
  });
}
