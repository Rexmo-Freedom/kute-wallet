import 'package:coingecko_api/data/market_chart_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/balance_history.dart';
import 'package:kute/models/balance_model.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/analytics_provider.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/coingecko_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/transactions_provider.dart';
import 'package:kute/providers/usd_account_provider.dart';
import 'package:kute/providers/viewed_wallet_provider.dart';
import 'package:kute/screens/analytics/components/home_analytics_widget.dart';
import 'package:kute/screens/shared/charts/kute_trend_chart.dart';
import 'package:kute/screens/shared/no_activity_state.dart';
import 'package:kute/screens/usd/components/usd_balance_chart.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart';

class _Market extends BitcoinMarketDataNotifier {
  _Market(this.data);
  final List<MarketChartData> data;
  @override
  Future<List<MarketChartData>> build() async => data;
}

/// The Balance cards are as tall as their content (founder, 6 November
/// 2026, on the Bitcoin Balance tab: "card bottom is not great, it expands
/// too much, right?"): the card ends the card's own 16 under the range
/// row, on the Bitcoin home, on another wallet's screen and on Dollars, at
/// a small phone and a large one; with nothing held, 16 under Sal's empty
/// state.
void main() {
  Settings settings() => Settings(
        currency: 'USD',
        language: 'en',
        btcFormat: 'sats',
        backup: false,
        biometricsEnabled: false,
        bitcoinElectrumNode: '',
        nodeType: '',
        reviewDone: true,
        activeWalletId: 'spending',
        balancePrivacy: 0,
        wallets: [WalletConfig(id: 'spending', name: 'Spending')],
      );

  List<Override> bitcoin({double current = 17520}) {
    final history = BalanceHistory(
      opening: 0,
      changes: current == 0
          ? const []
          : [(DateTime.now().subtract(const Duration(hours: 2)), current)],
      current: current,
    );
    final prices = [
      for (var ago = 90; ago >= 0; ago--)
        MarketChartData(DateTime.now().subtract(Duration(days: ago)),
            price: 70000, marketCap: 0, totalVolume: 0),
    ];
    return [
      settingsProvider.overrideWith((_) => SettingsModel(settings())),
      bitcoinMarketDataProvider.overrideWith(() => _Market(prices)),
      bitcoinBalanceStepsProvider.overrideWith((_) => history),
      bitcoinBalanceInFormatByDayProvider.overrideWith((_) => {}),
      viewedWalletBalanceProvider.overrideWithValue(WalletBalance(
          onChainBtcBalance: 0, sparkBitcoinbalance: current.round())),
      polymarketBalanceProvider.overrideWith((_) => 0),
      selectedCurrencyProvider.overrideWith(
          (ref, code) => Money.fromNumWithCurrency(70000, AppCurrencies.usd)),
      selectedCurrencyProviderFromUSD.overrideWith(
          (ref, code) => Money.fromNumWithCurrency(1, AppCurrencies.usd)),
      viewedWalletProvider.overrideWithValue(null),
      viewedWalletTransactionsProvider.overrideWithValue(Transaction.empty()),
    ];
  }

  Future<void> pump(WidgetTester tester, Widget child, List<Override> o,
      {Size screen = const Size(393, 852)}) async {
    tester.view.physicalSize = screen * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: o,
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          locale: const Locale('en'),
          theme: buildLightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 8));
  }

  Finder card() => find.byKey(const ValueKey('balance-card'));

  double gapUnder(WidgetTester tester, Finder outer, Finder last) =>
      tester.getBottomLeft(outer).dy - tester.getBottomLeft(last).dy;

  for (final screen in [const Size(375, 667), const Size(430, 932)]) {
    final pad = 16 * screen.height / 932;
    final label = '${screen.width.round()}x${screen.height.round()}';

    testWidgets('Bitcoin home: 16 under the range row ($label)',
        (tester) async {
      await pump(tester, const HomeAnalyticsWidget(surface: 'home'), bitcoin(),
          screen: screen);
      expect(gapUnder(tester, card(), find.byType(KuteChartRangeRow)),
          closeTo(pad, 0.5));
      // Nothing under the range row but the card's padding.
      expect(tester.getSize(card()).height, lessThan(400 * screen.height / 932),
          reason: 'no longer the fixed 400 card');
      await settle(tester);
    });
  }

  testWidgets('another wallet screen: the same', (tester) async {
    await pump(
        tester, const HomeAnalyticsWidget(surface: 'wallet_detail'), bitcoin());
    expect(gapUnder(tester, card(), find.byType(KuteChartRangeRow)),
        closeTo(16 * 852 / 932, 0.5));
    await settle(tester);
  });

  testWidgets('nothing held: 16 under Sal', (tester) async {
    await pump(tester, const HomeAnalyticsWidget(surface: 'home'),
        bitcoin(current: 0));
    expect(gapUnder(tester, card(), find.byType(NoActivityState)),
        closeTo(16 * 852 / 932, 0.5));
    await settle(tester);
  });

  testWidgets('Dollars: 16 under the range row', (tester) async {
    await pump(tester, const UsdBalanceChart(), [
      settingsProvider.overrideWith((_) => SettingsModel(settings())),
      usdBalanceProvider.overrideWithValue(5.02),
      usdBalanceStepsProvider.overrideWithValue(BalanceHistory(
        opening: 0,
        changes: [(DateTime.now().subtract(const Duration(hours: 3)), 5.02)],
        current: 5.02,
      )),
    ]);
    expect(
        gapUnder(tester, find.byType(UsdBalanceChart),
            find.byType(KuteChartRangeRow)),
        closeTo(16 * 852 / 932, 0.5));
    await settle(tester);
  });
}
