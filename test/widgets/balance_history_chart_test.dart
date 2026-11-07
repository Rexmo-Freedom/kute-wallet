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
import 'package:kute/screens/shared/charts/kute_line_chart.dart';
import 'package:kute/screens/shared/charts/kute_trend_chart.dart';
import 'package:kute/screens/shared/charts/kute_trend_window.dart';
import 'package:kute/screens/shared/no_activity_state.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/screens/usd/components/usd_balance_chart.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart';

/// The Balance charts (Bitcoin wallets and Dollars), restyled as a
/// brokerage app's balance chart: a range row under the plot (1M to
/// start, remembered for the session), no scale or gridlines, a dotted
/// baseline at the first value on screen, the neutral line colour, a
/// quiet change line above the plot (never "-100.0%"), the scrubbed
/// balance written there instead of on a card, and with no history Sal's
/// empty state, as Activity's (founder, 31 October 2026: "no balance
/// should also show Sal").
void main() {
  final now = DateTime(2026, 10, 5, 18, 0);

  group('the series and the ranges', () {
    test('one deposit today: an hour of what was held before, then it', () {
      // João's Dollars case: $5.02 arriving three hours ago, nothing
      // before. The line rises from nothing, never from the left edge.
      final deposit = now.subtract(const Duration(hours: 3));
      final h = BalanceHistory(
          opening: 0, changes: [(deposit, 5.02)], current: 5.02);
      final s = balanceSeries(h, now);
      expect(s.cellMinutes, 15);
      expect(s.times.first, deposit.subtract(kBalanceMinLeadIn));
      expect(s.times.last, now);
      expect(s.values.first, 0);
      expect(s.values.last, 5.02);
      expect(s.values.toSet(), {0, 5.02});
      // Three hours is younger than every range: each shows all of it.
      for (final r in BalanceRange.values) {
        expect(s.spanFor(r), s.extent, reason: '$r');
      }
    });

    test('a deposit this very second still rises from nothing', () {
      final h = BalanceHistory(
          opening: 0, changes: [(now, 17520)], current: 17520);
      final s = balanceSeries(h, now);
      expect(s.values.first, 0);
      expect(s.values.last, 17520);
      expect(s.times.last.difference(s.times.first), kBalanceMinLeadIn);
    });

    test('a long history: the grid coarsens, a twelfth of lead-in', () {
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
      expect(s.times.first,
          first.subtract(const Duration(days: 22, hours: 12)));
      expect(s.values.first, 0);
      expect(s.values.last, 690400);
      // Grid points sit on whole hours after the first one.
      expect(s.times[1].minute, 0);
    });

    test('money came and went the same day: the history starts later', () {
      final blip = DateTime(2026, 9, 10, 10);
      final stay = DateTime(2026, 10, 1, 9);
      final h = BalanceHistory(
        opening: 0,
        changes: [
          (blip, 5000),
          (blip.add(const Duration(minutes: 30)), 0),
          (stay, 12000),
        ],
        current: 12000,
      );
      final s = balanceSeries(h, now);
      expect(s.times.first.isAfter(blip), isTrue);
      expect(s.times.first.isBefore(stay), isTrue);
    });

    test('a balance held under an hour never shows; for hours, it does',
        () {
      // Steady at 7,000 for weeks. 110,000 in and on to Investments in 20
      // minutes, straddling an hour; later 50,000 in for three hours.
      final quick = DateTime(2026, 10, 3, 15, 55);
      final slow = DateTime(2026, 10, 4, 9, 0);
      final h = BalanceHistory(
        opening: 0,
        changes: [
          (DateTime(2026, 9, 1, 12), 7000),
          (quick, 117000),
          (quick.add(const Duration(minutes: 20)), 7000),
          (slow, 57000),
          (slow.add(const Duration(hours: 3)), 7000),
        ],
        current: 7000,
      );
      final s = balanceSeries(h, now);
      expect(s.values.contains(117000), isFalse);
      expect(s.values.contains(57000), isTrue);
    });

    test('money held for hours but gone the same day does not start the '
        'history', () {
      final morning = DateTime(2026, 9, 20, 9);
      final stay = DateTime(2026, 10, 1, 9);
      final h = BalanceHistory(
        opening: 0,
        changes: [
          (morning, 30000),
          (morning.add(const Duration(hours: 4)), 0),
          (stay, 12000),
        ],
        current: 12000,
      );
      final s = balanceSeries(h, now);
      expect(s.times.first.isAfter(morning), isTrue);
    });

    test('money held before the first change: a short lead-in on it', () {
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

    test('each range reaches back its length from now; ALL is everything',
        () {
      final h = BalanceHistory(
        opening: 0,
        changes: [(now.subtract(const Duration(days: 500)), 50000)],
        current: 50000,
      );
      final s = balanceSeries(h, now);
      for (final r in BalanceRange.values) {
        final start = s.times[(s.extent - s.spanFor(r)).round()];
        if (r == BalanceRange.all) {
          expect(start, s.times.first);
        } else {
          final cut = now.subtract(r.duration!);
          expect(start.isBefore(cut), isFalse, reason: '$r');
          // Within a grid step (and a clock change) of the cut.
          expect(start.difference(cut).inMinutes,
              lessThan(s.cellMinutes + 61), reason: '$r');
        }
      }
      expect([for (final r in BalanceRange.values) r.label],
          ['1W', '1M', '3M', '1Y', 'ALL']);
    });
  });

  group('the shared line chart', () {
    test('scale levels stay round (other charts still draw a scale)', () {
      expect(kuteScaleLevels(-2190, 19710), [0, 10000]);
      expect(kuteScaleLevels(-0.1, 1.1), [0, 0.5, 1]);
      expect(kuteScaleLevels(-0.1, 1.1, minStep: 1), [0, 1]);
    });

    test('a stepped line is drawn flat, then straight up or down', () {
      final path = kuteStepPath(
          const [Offset(0, 10), Offset(10, 10), Offset(20, 2)]);
      expect(path.getBounds(), const Rect.fromLTRB(0, 2, 20, 10));
    });
  });

  group('on screen', () {
    Settings settings({int privacy = 0}) => Settings(
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
          wallets: [WalletConfig(id: 'spending', name: 'Spending')],
        );

    Widget app(Widget child) => ScreenUtilInit(
          designSize: const Size(430, 932),
          builder: (_, __) => MaterialApp(
            locale: const Locale('en'),
            theme: buildLightTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: SingleChildScrollView(child: child)),
          ),
        );

    Future<void> pump(WidgetTester tester, Widget child,
        List<Override> overrides) async {
      tester.view.physicalSize = const Size(393, 852) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester
          .pumpWidget(ProviderScope(overrides: overrides, child: app(child)));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 8));
    }

    String header(WidgetTester tester) => tester
        .widget<Text>(find.byKey(const ValueKey('balance-chart-header')))
        .textSpan!
        .toPlainText();

    String headline(WidgetTester tester) => tester
        .widget<RollingNumberText>(
            find.byKey(const ValueKey('balance-chart-headline')))
        .text;

    KuteTrendChart chartOf(WidgetTester tester) =>
        tester.widget<KuteTrendChart>(find.byType(KuteTrendChart));

    Finder plot() => find.byKey(const ValueKey('trend-chart-plot'));

    /// Nothing ever on the balance: the Activity empty state, Sal centred
    /// with "No balance history yet" and its line.
    void expectNoHistory(WidgetTester tester) {
      final empty = find.byKey(const ValueKey('balance-chart-no-history'));
      expect(empty, findsOneWidget);
      final state = tester.widget<NoActivityState>(empty);
      expect(state.title, 'No balance history yet');
      expect(state.subtitle, 'It starts with your first transaction.');
    }

    /// A long press, then a slide: the scrub.
    Future<TestGesture> scrub(WidgetTester tester, Offset at) async {
      final touch = await tester.startGesture(at);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 150));
      return touch;
    }

    /// A bare Balance chart over [history], in dollars, ending [now].
    Widget bare(BalanceHistory history) => BalanceHistoryChart(
          history: history,
          format: (v) => '\$${v.toStringAsFixed(2)}',
          trackingChart: 'valuation',
          now: now,
        );

    /// 100 for months, 150 since three days ago.
    final rising = BalanceHistory(
      opening: 0,
      changes: [
        (now.subtract(const Duration(days: 200)), 100),
        (now.subtract(const Duration(days: 3)), 150),
      ],
      current: 150,
    );

    List<Override> plain({int privacy = 0}) => [
          settingsProvider
              .overrideWith((_) => SettingsModel(settings(privacy: privacy))),
        ];

    List<Override> dollars() {
      final history = BalanceHistory(
        opening: 0,
        changes: [(DateTime.now().subtract(const Duration(hours: 3)), 5.02)],
        current: 5.02,
      );
      return [
        ...plain(),
        usdBalanceProvider.overrideWithValue(5.02),
        usdBalanceStepsProvider.overrideWithValue(history),
      ];
    }

    testWidgets(
        'Dollars: the headline, the range row (1M) under the plot, the '
        'change from zero without a percent', (tester) async {
      await pump(tester, const UsdBalanceChart(), dollars());
      expect(find.byType(KuteChartRangeRow), findsOneWidget);
      for (final r in ['1W', '1M', '3M', '1Y', 'ALL']) {
        expect(find.text(r), findsOneWidget, reason: r);
      }
      final chart = chartOf(tester);
      expect(chart.selectedRange, BalanceRange.month.index);
      expect(chart.values.last, 5.02);
      // Up over the month: the result colour.
      expect(kuteTrendResultColor(AppColorsExtension.light(),
          chart.values.first, chart.values.last), AppColors.marketUp);
      expect(headline(tester), r'$5.02');
      expect(header(tester), '▲ \$5.02 · Past month');
      expect(find.textContaining('%'), findsNothing);
      // The range row 16 px under the plot.
      expect(tester.getTopLeft(find.byType(KuteChartRangeRow)).dy,
          closeTo(tester.getBottomLeft(plot()).dy + 16 * 393 / 430, 1));
      await settle(tester);
    });

    testWidgets('a range tapped sets the points drawn and the change line',
        (tester) async {
      final s = balanceSeries(rising, now);
      await pump(tester, bare(rising), plain());
      expect(chartOf(tester).values,
          kuteTrendWindow(s, s.spanFor(BalanceRange.month)).values);
      expect(header(tester), '▲ \$50.00 (+50.0%) · Past month');

      await tester.tap(find.text('1W'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(chartOf(tester).values,
          kuteTrendWindow(s, s.spanFor(BalanceRange.week)).values);
      expect(header(tester), '▲ \$50.00 (+50.0%) · Past week');

      await tester.tap(find.text('ALL'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(chartOf(tester).values.first, 0);
      // From the lead-in's nothing: no percent.
      expect(header(tester), '▲ \$150.00 · All time');
      await settle(tester);
    });

    testWidgets('the range is remembered when the chart is built afresh',
        (tester) async {
      final container = ProviderContainer(overrides: plain());
      addTearDown(container.dispose);
      tester.view.physicalSize = const Size(393, 852) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Future<void> show(Key key) async {
        await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: app(KeyedSubtree(key: key, child: bare(rising))),
        ));
        await tester.pump(const Duration(milliseconds: 700));
      }

      await show(const ValueKey('a'));
      await tester.tap(find.text('3M'));
      await tester.pump(const Duration(milliseconds: 400));
      await show(const ValueKey('b'));
      expect(chartOf(tester).selectedRange, BalanceRange.threeMonths.index);
      // The Dollars chart keeps its own choice.
      expect(container.read(balanceChartRangeProvider('dollars')),
          BalanceRange.month);
      await settle(tester);
    });

    testWidgets('the change line: down, emptied, no change', (tester) async {
      BalanceHistory to(double from, double end) => BalanceHistory(
            opening: 0,
            changes: [
              (now.subtract(const Duration(days: 200)), from),
              (now.subtract(const Duration(days: 3)), end),
            ],
            current: end,
          );
      await pump(tester, bare(to(200, 150)), plain());
      expect(header(tester), '▼ \$50.00 (−25.0%) · Past month');
      expect(chartOf(tester).lineColor, isNull);
      await pump(tester, bare(to(100, 0)), plain());
      // An account emptied: the amount, never "-100.0%".
      expect(header(tester), '▼ \$100.00 · Past month');
      expect(find.textContaining('100.0%'), findsNothing);
      await pump(tester, bare(to(100, 100)), plain());
      expect(header(tester), 'No change · Past month');
      await settle(tester);
    });

    testWidgets(
        'a scrub writes the balance under the finger in the headline and '
        'its change and moment in the change line; release puts now back',
        (tester) async {
      await pump(tester, bare(rising), plain());
      final rect = tester.getRect(plot());
      final touch = await scrub(tester, rect.centerRight.translate(-8, 0));
      expect(headline(tester), r'$150.00');
      expect(header(tester), startsWith('▲ \$50.00 (+50.0%) · '));
      // Back to the left: the older balance and its own day.
      await touch.moveTo(rect.centerLeft.translate(2, 0));
      await tester.pump(const Duration(milliseconds: 150));
      expect(headline(tester), r'$100.00');
      expect(header(tester), startsWith('No change · Sep '));
      await touch.up();
      await tester.pump(const Duration(milliseconds: 150));
      expect(headline(tester), r'$150.00');
      expect(header(tester), '▲ \$50.00 (+50.0%) · Past month');
      await settle(tester);
    });

    testWidgets(
        'no history: Sal\'s empty state with its title and line, no '
        'headline, no chart, no range row', (tester) async {
      const history = BalanceHistory(opening: 0, changes: [], current: 0);
      await pump(tester, bare(history), plain());
      expectNoHistory(tester);
      expect(find.byKey(const ValueKey('balance-chart-headline')),
          findsNothing);
      expect(find.byKey(const ValueKey('balance-chart-empty')), findsNothing);
      expect(plot(), findsNothing);
      expect(find.byType(KuteChartRangeRow), findsNothing);
      expect(find.byKey(const ValueKey('balance-chart-header')), findsNothing);
      await settle(tester);
    });

    testWidgets('balances hidden: dots for every figure, no percent',
        (tester) async {
      await pump(tester, bare(rising), plain(privacy: 1));
      expect(headline(tester), '••••••');
      expect(header(tester), '•••••• · Past month');
      expect(find.textContaining(r'$'), findsNothing);
      await settle(tester);
    });

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
          MarketChartData(
            DateTime.now().subtract(Duration(days: ago)),
            price: 70000,
            marketCap: 0,
            totalVolume: 0,
          ),
      ];
      return [
        ...plain(),
        bitcoinMarketDataProvider.overrideWith(() => _Market(prices)),
        bitcoinBalanceStepsProvider.overrideWith((_) => history),
        bitcoinBalanceInFormatByDayProvider.overrideWith((_) => {}),
        viewedWalletBalanceProvider.overrideWithValue(WalletBalance(
            onChainBtcBalance: 0, sparkBitcoinbalance: current.round())),
        polymarketBalanceProvider.overrideWith((_) => 0),
        selectedCurrencyProvider.overrideWith((ref, code) =>
            Money.fromNumWithCurrency(70000, AppCurrencies.usd)),
        selectedCurrencyProviderFromUSD.overrideWith(
            (ref, code) => Money.fromNumWithCurrency(1, AppCurrencies.usd)),
        viewedWalletProvider.overrideWithValue(null),
        viewedWalletTransactionsProvider.overrideWithValue(Transaction.empty()),
      ];
    }

    testWidgets(
        'Bitcoin home: the ₿ headline with its worth under it, its own '
        'range row, a scrub reads the line; Price keeps its row and LIVE',
        (tester) async {
      await pump(tester, const HomeAnalyticsWidget(surface: 'home'), bitcoin());
      // Balance is the landing tab here (no activity list passed).
      expect(find.text('LIVE'), findsNothing);
      expect(find.byType(KuteChartRangeRow), findsOneWidget);
      expect(headline(tester), '₿17,520');
      expect(
          tester
              .widget<RollingNumberText>(
                  find.byKey(const ValueKey('balance-chart-secondary')))
              .text,
          // 17,520 sats at $70,000.
          r'$12.26');
      expect(header(tester), '▲ ₿17,520 · Past month');
      expect(chartOf(tester).values.last, 17520);
      final rect = tester.getRect(plot());
      final touch = await scrub(tester, rect.centerRight.translate(-8, 0));
      expect(headline(tester), '₿17,520');
      expect(header(tester), startsWith('▲ ₿17,520 · '));
      expect(header(tester), isNot(contains('Past month')));
      await touch.up();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      await tester.tap(find.text('Price'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('3M'), findsOneWidget);
      expect(find.text('LIVE'), findsOneWidget);
      await settle(tester);
    });

    testWidgets('Bitcoin home with nothing held: the caption, no chart',
        (tester) async {
      await pump(tester, const HomeAnalyticsWidget(surface: 'home'),
          bitcoin(current: 0));
      expectNoHistory(tester);
      expect(plot(), findsNothing);
      expect(find.byType(KuteChartRangeRow), findsNothing);
      await settle(tester);
    });

    testWidgets('Dollars with nothing held: the caption, no chart',
        (tester) async {
      await pump(tester, const UsdBalanceChart(), [
        ...plain(),
        usdBalanceProvider.overrideWithValue(0),
        usdBalanceStepsProvider.overrideWithValue(
            const BalanceHistory(opening: 0, changes: [], current: 0)),
      ]);
      expectNoHistory(tester);
      expect(plot(), findsNothing);
      await settle(tester);
    });

    testWidgets('Bitcoin wallet screen: the same chart, a touch reads it',
        (tester) async {
      await pump(
          tester,
          const HomeAnalyticsWidget(
              surface: 'wallet_detail', showBalanceHeadline: false),
          bitcoin());
      expect(find.byType(KuteTrendChart), findsOneWidget);
      final rect = tester.getRect(plot());
      final touch = await scrub(tester, rect.centerRight.translate(-8, 0));
      expect(headline(tester), '₿17,520');
      expect(header(tester), startsWith('▲ ₿17,520 · '));
      await touch.up();
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
