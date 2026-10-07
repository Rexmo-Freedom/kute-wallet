// The work a venue's search button does on open: the dock's square button
// on Predictions and Investing opens the search sheet straight onto the
// venue's own tab, and the composer takes focus (and the keyboard rises)
// once the sheet has slid in.
//
// Counted per open, from the tap until everything settles, with the
// keyboard inset stepped frame by frame the way iOS reports it:
//   * how many times the search surface builds;
//   * every widget rebuild in the app;
//   * the first frame's selected tab (a stale tab that then slides over is
//     a visible jump);
//   * whether the live sports feed is connected before anything is typed.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/services/trade_notification_store.dart'
    show TradeNotification;
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/trade_notifications_provider.dart';
import 'package:kute/providers/unified_search_provider.dart';
import 'package:kute/screens/home/components/kute_bottom_action_bar.dart';
import 'package:kute/screens/search/unified_search_screen.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/screens/portfolio/open_investments_screen.dart'
    show InvestmentsProduct;
import 'package:kute/screens/shared/investment_action_bar.dart';
import 'package:kute/services/advisor/advisor_input_guard.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/screens/shared/kute_dog_scenes.dart';

class _Sports extends SportsLiveNotifier {
  _Sports(this.probe);
  final _Probe probe;
  @override
  Map<String, SportsMatchUpdate> build() => {};
  @override
  void connect() => probe.sportsConnects++;
}

class _Probe {
  int sportsConnects = 0;
  int surfaceBuilds = 0;
  int rebuilds = 0;
  final navigator = GlobalKey<NavigatorState>();
}

Settings _settings() => Settings(
      currency: 'USD',
      language: 'en',
      btcFormat: 'sats',
      backup: false,
      biometricsEnabled: false,
      bitcoinElectrumNode: '',
      nodeType: 'Blockstream',
      reviewDone: true,
      wallets: [
        WalletConfig(id: 'spending', name: 'Spending'),
        WalletConfig(
            id: 'savings', name: 'Savings', sparkEnabled: false),
      ],
      activeWalletId: 'spending',
    );

/// [predictions] null opens Home's search sheet ([showKuteSearch]); a venue
/// mounts its real dock ([InvestmentActionBar]) and taps its magnifier.
Future<_Probe> _pumpHost(WidgetTester tester, {required bool? predictions}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final probe = _Probe();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      settingsProvider.overrideWith((_) => SettingsModel(_settings())),
      aiEnabledProvider.overrideWith((_) async => true),
      sportsLiveProvider.overrideWith(() => _Sports(probe)),
      tradeNotificationsProvider
          .overrideWith((_) => Stream.value(const <TradeNotification>[])),
      unifiedSearchResultsProvider
          .overrideWith((_) async => UnifiedSearchResults.empty),
      globalMarketResultsProvider
          .overrideWith((_) => const AsyncValue.data([])),
      globalHyperliquidResultsProvider
          .overrideWith((_) => const AsyncValue.data([])),
      hyperliquidAllMarketsProvider.overrideWith((_) => []),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        navigatorKey: probe.navigator,
        theme: ThemeData(
          splashFactory: NoSplash.splashFactory,
          fontFamily: 'Inter',
          extensions: [AppColorsExtension.light()],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showKuteSearch(context, source: 'home'),
              child: const Text('Open search'),
            ),
          ),
          bottomNavigationBar: predictions == null
              ? null
              : InvestmentActionBar(
                  product: predictions
                      ? InvestmentsProduct.predictions
                      : InvestmentsProduct.trading),
        ),
      ),
    ),
  ));
  // A previous open left the filter on another tab.
  ProviderScope.containerOf(tester.element(find.text('Open search')))
      .read(selectedSearchCategoryProvider.notifier)
      .state = SearchCategory.all;
  await tester.pump();
  return probe;
}

/// Taps the search button (the dock's Sal-with-a-magnifier when a venue
/// dock is mounted) and lets the sheet and the keyboard come up together: twelve
/// frames of 16 ms with the inset growing to 300.
Future<int?> _open(WidgetTester tester, _Probe probe) async {
  debugOnRebuildDirtyWidget = (element, builtOnce) {
    probe.rebuilds++;
    final name = element.widget.runtimeType.toString();
    if (name == 'UnifiedSearchSurface') probe.surfaceBuilds++;
  };
  addTearDown(() => debugOnRebuildDirtyWidget = null);
  final dock = find.byType(KuteDogMagnifier);
  await tester.tap(dock.evaluate().isEmpty ? find.text('Open search') : dock);
  await tester.pump();
  final pills = find.byType(KutePillTabs);
  final firstTab = pills.evaluate().isEmpty
      ? null
      : tester.widget<KutePillTabs>(pills.first).selectedIndex;
  for (var i = 1; i <= 12; i++) {
    tester.view.viewInsets = FakeViewPadding(bottom: 25.0 * i);
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pumpAndSettle();
  debugOnRebuildDirtyWidget = null;
  return firstTab;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(
      () async => expect(await AdvisorInputGuard.isSafe('bitcoin'), isTrue));
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    OpenOnce.reset();
  });

  for (final predictions in [true, false]) {
    final venue = predictions ? 'Predictions' : 'Investing';
    testWidgets('$venue search opens with little work', (tester) async {
      final probe = await _pumpHost(tester, predictions: predictions);
      final firstTab = await _open(tester, probe);
      debugPrint('[$venue open] surface builds ${probe.surfaceBuilds}, '
          'rebuilds ${probe.rebuilds}, first tab $firstTab, '
          'sports connects ${probe.sportsConnects}');

      expect(find.byType(UnifiedSearchSurface), findsOneWidget);
      // The first frame already shows the venue's own tab.
      expect(firstTab, predictions ? 2 : 3);
      // Built once to open, once as Sal's availability resolves and once
      // when the composer takes focus after the slide; the keyboard's
      // frames do not rebuild it.
      expect(probe.surfaceBuilds, lessThanOrEqualTo(3));
      // Nothing typed, so no live sports feed yet.
      expect(probe.sportsConnects, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Home search sheet does not rebuild with the keyboard',
      (tester) async {
    final probe = await _pumpHost(tester, predictions: null);
    await _open(tester, probe);
    debugPrint('[Home open] surface builds ${probe.surfaceBuilds}, '
        'rebuilds ${probe.rebuilds}');
    expect(find.byType(UnifiedSearchSurface), findsOneWidget);
    expect(probe.surfaceBuilds, lessThanOrEqualTo(3));
    probe.navigator.currentState!.pop();
    await tester.pumpAndSettle();
    // The idle mascot's delayed tagline exits after unmount.
    await tester.pump(const Duration(seconds: 6));
    expect(tester.takeException(), isNull);
  });

  for (final predictions in [true, null]) {
    testWidgets(
        'a double tap opens one ${predictions == null ? 'Home' : 'venue'} '
        'sheet', (tester) async {
      final probe = await _pumpHost(tester, predictions: predictions);
      // Two taps before the sheet has drawn a frame.
      if (predictions == null) {
        final button = tester.widget<TextButton>(find.byType(TextButton));
        button.onPressed!();
        button.onPressed!();
      } else {
        final dock = tester
            .widget<KuteBottomActionBar>(find.byType(KuteBottomActionBar));
        dock.onSearch!();
        dock.onSearch!();
      }
      await tester.pumpAndSettle();
      expect(find.byType(UnifiedSearchSurface), findsOneWidget);
      probe.navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.byType(UnifiedSearchSurface), findsNothing);
      await tester.pump(const Duration(seconds: 6));
      expect(tester.takeException(), isNull);
    });
  }
}
