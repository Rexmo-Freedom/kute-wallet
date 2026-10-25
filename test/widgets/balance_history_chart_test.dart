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
import 'package:kute/screens/analytics/components/balance_history_chart.dart';
import 'package:kute/screens/analytics/components/home_analytics_widget.dart';
import 'package:kute/screens/shared/charts/kute_chart_crosshair.dart';
import 'package:kute/screens/shared/charts/kute_chart_format.dart';
import 'package:kute/screens/shared/charts/kute_line_chart.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/screens/usd/components/usd_balance_chart.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart';

/// The Balance charts (Bitcoin wallets and Dollars) have no range row:
/// they open on the last 30 days at most, from the first money held, and
/// pinch out to the whole history, with a quiet scale on the left and no
/// "+100.0%" from a zero start.
void main() {
  final now = DateTime(2026, 10, 5, 18, 0);

  group('the series and the window', () {
    test('one deposit today: the line opens on it, flat to now', () {
      // João's Dollars case: $5.02 arriving three hours ago, nothing
      // before. The line starts on the money, never on a zero lead-in.
      final h = BalanceHistory(
        opening: 0,
        changes: [(now.subtract(const Duration(hours: 3)), 5.02)],
        current: 5.02,
      );
      final s = balanceSeries(h, now);
      expect(s.cellMinutes, 15);
      expect(s.times.first, now.subtract(const Duration(hours: 3)));
      expect(s.times.last, now);
      expect(s.values.toSet(), {5.02});
      // Three hours is the whole history: the chart opens on all of it.
      expect(s.defaultSpan, s.extent);
    });

    test('a deposit this very second: two points, flat', () {
      final h = BalanceHistory(
          opening: 0, changes: [(now, 17520)], current: 17520);
      final s = balanceSeries(h, now);
      expect(s.length, 2);
      expect(s.values, [17520, 17520]);
      expect(s.defaultSpan, s.extent);
    });

    test('a long history: the grid coarsens, the line still ends now', () {
      final first = now.subtract(const Duration(days: 270));
      final h = BalanceHistory(
        opening: 0,
        changes: [
          (first, 250000),
          (now.subtract(const Duration(days: 96)), 300000),
          (now.subtract(const Duration(days: 4)), 690400),
        ],
        current: 690400,
      );
      final s = balanceSeries(h, now);
      expect(s.cellMinutes, 60);
      expect(s.length, lessThanOrEqualTo(kBalanceMaxCells + 2));
      expect(s.times.first, first);
      expect(s.values.first, 250000);
      expect(s.values.last, 690400);
      expect(h.heldAt(now.subtract(const Duration(days: 100))), 250000);
      expect(h.heldAt(first.subtract(const Duration(seconds: 1))), 0);
      // Grid points sit on whole hours after the first one.
      expect(s.times[1].minute, 0);
      expect(s.times[1].second, 0);
    });

    test('money held before the first change: a short lead-in', () {
      final c0 = now.subtract(const Duration(days: 12));
      final h = BalanceHistory(
          opening: 100, changes: [(c0, 150)], current: 150);
      final s = balanceSeries(h, now);
      expect(s.times.first, c0.subtract(const Duration(days: 1)));
      expect(s.values.first, 100);
    });

    test('no change on record: the last week, flat at the balance', () {
      const h = BalanceHistory(opening: 0, changes: [], current: 1200);
      final s = balanceSeries(h, now);
      expect(s.times.last.difference(s.times.first),
          const Duration(days: 7));
      expect(s.values.every((v) => v == 1200), isTrue);
    });
  });

  group('the scale', () {
    test('two or three round levels, none under zero', () {
      // 17,520 sats on the engine's autoscale (an eighth of the span
      // free above and below).
      expect(kuteScaleLevels(-2190, 19710), [0, 10000]);
      expect(kuteScaleLevels(-0.63, 5.65), [0, 5]);
      for (final hi in [1.0, 7.3, 48.0, 999.0, 14500000.0, 0.0002]) {
        final levels = kuteScaleLevels(-hi / 8, hi * 9 / 8);
        expect(levels.length, inInclusiveRange(1, 3), reason: '$hi');
        expect(levels.every((l) => l >= 0), isTrue);
      }
    });

    test('labels in the balance unit', () {
      expect(bitcoinScaleLabel(10000, 10000, 'sats'), '10K sats');
      expect(bitcoinScaleLabel(0, 10000, 'sats'), '0 sats');
      expect(bitcoinScaleLabel(10000, 10000, 'btc'), '0.0001 BTC');
      expect(bitcoinScaleLabel(0, 10000, 'btc'), '0 BTC');
      expect(dollarScaleLabel(5, 5), r'$5');
      expect(dollarScaleLabel(0, 5), r'$0');
      expect(dollarScaleLabel(1500, 500), r'$1.5K');
      expect(dollarScaleLabel(0.5, 0.5), r'$0.50');
    });

    test('a balance is drawn flat, then straight up or down', () {
      final path = kuteStepPath(
          const [Offset(0, 10), Offset(10, 10), Offset(20, 2)]);
      final bounds = path.getBounds();
      expect(bounds, const Rect.fromLTRB(0, 2, 20, 10));
      final metric = path.computeMetrics().single;
      expect(metric.length, closeTo(10 + 10 + 8, 1e-6));
    });
  });

  group('on screen', () {
    Settings settings({int privacy = 0, WalletConfig? wallet}) => Settings(
          currency: 'USD',
          language: 'en',
          btcFormat: 'sats',
          backup: false,
          biometricsEnabled: false,
          bitcoinElectrumNode: '',
          nodeType: '',
          reviewDone: true,
          activeWalletId: 'spending',
          balancePrivacy: privacy,
          wallets: [
            WalletConfig(id: 'spending', name: 'Spending'),
            if (wallet != null) wallet,
          ],
        );

    Future<void> pump(WidgetTester tester, Widget child,
        List<Override> overrides) async {
      tester.view.physicalSize = const Size(393, 852) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ProviderScope(
        overrides: overrides,
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
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 8));
    }

    String today() => kuteChartDay(DateTime.now(), null);

    List<Override> dollars({int privacy = 0}) {
      final history = BalanceHistory(
        opening: 0,
        changes: [(DateTime.now().subtract(const Duration(hours: 3)), 5.02)],
        current: 5.02,
      );
      return [
        settingsProvider
            .overrideWith((_) => SettingsModel(settings(privacy: privacy))),
        usdBalanceProvider.overrideWithValue(5.02),
        usdBalanceStepsProvider.overrideWithValue(history),
      ];
    }

    testWidgets('Dollars: no range row, no date, no +100%, a scale',
        (tester) async {
      await pump(tester, const UsdBalanceChart(), dollars());
      for (final r in ['24H', '7D', '1M', '3M', '1Y', 'ALL']) {
        expect(find.text(r), findsNothing, reason: r);
      }
      expect(find.text(today()), findsNothing);
      expect(find.text('+100.0%'), findsNothing);
      expect(find.byType(KuteLineChart), findsOneWidget);
      final chart = tester.widget<KuteLineChart>(find.byType(KuteLineChart));
      // The other line charts' curve, on each bucket's close.
      expect(chart.stepped, isFalse);
      expect(chart.buckets, isNotNull);
      expect(chart.scaleLabel, isNotNull);
      expect(chart.values.toSet(), {5.02});
      // No headline above the plot (owner decision): the balance is the
      // hero card above the strip, and a touch reads it off the chart.
      expect(find.byType(RollingNumberText), findsNothing);
      expect(find.text(r'$5.02'), findsNothing);
      final rect = tester.getRect(find.byType(KuteLineChart));
      final touch =
          await tester.startGesture(rect.centerRight.translate(-8, 0));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 150));
      final card = find.byType(KuteScrubCard);
      expect(card, findsOneWidget);
      expect(find.descendant(of: card, matching: find.text(r'$5.02')),
          findsOneWidget);
      await touch.up();
      await settle(tester);
    });

    testWidgets('a window that starts above zero reports the amount',
        (tester) async {
      // A history whose first point on screen holds money: the change is
      // the amount since then, with its percent, as the scrub card says.
      final history = BalanceHistory(
        opening: 100,
        changes: [(DateTime.now().subtract(const Duration(days: 3)), 150)],
        current: 150,
      );
      await pump(
        tester,
        SizedBox(
          height: 300,
          child: BalanceHistoryChart(
            history: history,
            format: (v) => '\$${v.toStringAsFixed(2)}',
            scaleLabel: dollarScaleLabel,
            trackingChart: 'valuation',
          ),
        ),
        [settingsProvider.overrideWith((_) => SettingsModel(settings()))],
      );
      expect(find.text('+\$50.00 (+50.0%)'), findsOneWidget);
      await settle(tester);
    });

    testWidgets('balances hidden: the scale keeps no figures',
        (tester) async {
      await pump(tester, const UsdBalanceChart(), dollars(privacy: 1));
      final chart = tester.widget<KuteLineChart>(find.byType(KuteLineChart));
      expect(chart.showScale, isTrue);
      expect(chart.scaleLabel, isNull);
      await settle(tester);
    });

    List<Override> bitcoin() {
      final history = BalanceHistory(
        opening: 0,
        changes: [(DateTime.now().subtract(const Duration(hours: 2)), 17520)],
        current: 17520,
      );
      final prices = [
        for (var ago = 90; ago >= 0; ago--)
          MarketChartData(
            DateTime.now().subtract(Duration(days: ago)),
            price: 70000,
            marketCap: 0,
            totalVolume: 0,
          ),
      ];
      return [
        settingsProvider.overrideWith((_) => SettingsModel(settings())),
        bitcoinMarketDataProvider.overrideWith(() => _Market(prices)),
        bitcoinBalanceStepsProvider.overrideWith((_) => history),
        bitcoinBalanceInFormatByDayProvider.overrideWith((_) => {}),
        viewedWalletBalanceProvider.overrideWithValue(
            WalletBalance(onChainBtcBalance: 0, sparkBitcoinbalance: 17520)),
        polymarketBalanceProvider.overrideWith((_) => 0),
        selectedCurrencyProvider.overrideWith((ref, code) =>
            Money.fromNumWithCurrency(70000, AppCurrencies.usd)),
        selectedCurrencyProviderFromUSD.overrideWith(
            (ref, code) => Money.fromNumWithCurrency(1, AppCurrencies.usd)),
        viewedWalletProvider.overrideWithValue(null),
        viewedWalletTransactionsProvider.overrideWithValue(Transaction.empty()),
      ];
    }

    testWidgets('Bitcoin Balance: no range row or date; Price keeps them',
        (tester) async {
      await pump(tester, const HomeAnalyticsWidget(surface: 'home'), bitcoin());
      // Balance is the landing tab here (no activity list passed).
      for (final r in ['LIVE', '24H', '7D', '1M', '3M', '1Y', 'ALL']) {
        expect(find.text(r), findsNothing, reason: r);
      }
      expect(find.text(today()), findsNothing);
      expect(find.text('+100.0%'), findsNothing);
      final chart = tester.widget<KuteLineChart>(find.byType(KuteLineChart));
      expect(chart.stepped, isFalse);
      // The line is the balance in sats, as the headline leads with.
      expect(chart.values.last, 17520);
      // No headline above the plot on home either: a touch reads it.
      expect(
          find.byWidgetPredicate(
              (w) => w is RollingNumberText && w.text == '17,520 sats'),
          findsNothing);

      await tester.tap(find.text('Price'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('3M'), findsOneWidget);
      expect(find.text('LIVE'), findsOneWidget);
      await settle(tester);
    });

    testWidgets('Bitcoin wallet screen: no headline above the Balance plot, '
        'a touch reads the balance; Price keeps its headline',
        (tester) async {
      await pump(
          tester,
          const HomeAnalyticsWidget(
              surface: 'wallet_detail', showBalanceHeadline: false),
          bitcoin());
      expect(find.byType(KuteLineChart), findsOneWidget);
      expect(find.byType(RollingNumberText), findsNothing);
      expect(find.text('17,520 sats'), findsNothing);
      final rect = tester.getRect(find.byType(KuteLineChart));
      final touch =
          await tester.startGesture(rect.centerRight.translate(-8, 0));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 150));
      final card = find.byType(KuteScrubCard);
      expect(card, findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('17,520 sats')),
          findsOneWidget);
      await touch.up();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      await tester.tap(find.text('Price'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(RollingNumberText), findsWidgets);
      await settle(tester);
    });
  });
}

class _Market extends BitcoinMarketDataNotifier {
  _Market(this.data);
  final List<MarketChartData> data;
  @override
  Future<List<MarketChartData>> build() async => data;
}
