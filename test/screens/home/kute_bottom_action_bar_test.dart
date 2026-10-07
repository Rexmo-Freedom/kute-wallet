// The dock's square button is search on every surface (owner decision:
// each job has one home; accounts open from the wallet's name at the top).
// While Sal is available the glyph is a magnifying glass whose lens is
// Sal's face, his ears over the rim ("Search or ask Sal"); with AI off it is the plain magnifier at the same
// visual size. Never a plus, and a tap opens the unified search sheet
// scoped to the host.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/trade_notifications_provider.dart';
import 'package:kute/providers/unified_search_provider.dart';
import 'package:kute/screens/home/components/kute_bottom_action_bar.dart';
import 'package:kute/screens/home/home.dart' show HomeDock;
import 'package:kute/screens/portfolio/open_investments_screen.dart'
    show InvestmentsProduct;
import 'package:kute/screens/search/unified_search_screen.dart';
import 'package:kute/screens/shared/ask_sal_sheet.dart'
    show SalSuggestionButton;
import 'package:kute/screens/shared/kute_dog_scenes.dart';
import 'package:kute/screens/shared/investment_action_bar.dart';
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/screens/usd/usd_account_screen.dart';
import 'package:kute/services/trade_notification_store.dart'
    show TradeNotification;
import 'package:kute/theme/app_theme.dart';

class _Sports extends SportsLiveNotifier {
  @override
  Map<String, SportsMatchUpdate> build() => {};
  @override
  void connect() {}
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
      wallets: [WalletConfig(id: 'spending', name: 'Spending')],
      activeWalletId: 'spending',
    );

Future<ProviderContainer> _pump(WidgetTester tester, Widget dock,
    {bool aiEnabled = true, bool dark = false}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(overrides: [
    settingsProvider.overrideWith((_) => SettingsModel(_settings())),
    aiEnabledProvider.overrideWith((_) async => aiEnabled),
    sportsLiveProvider.overrideWith(_Sports.new),
    tradeNotificationsProvider
        .overrideWith((_) => Stream.value(const <TradeNotification>[])),
    unifiedSearchResultsProvider
        .overrideWith((_) async => UnifiedSearchResults.empty),
    globalMarketResultsProvider.overrideWith((_) => const AsyncValue.data([])),
    globalHyperliquidResultsProvider
        .overrideWith((_) => const AsyncValue.data([])),
    hyperliquidAllMarketsProvider.overrideWith((_) => []),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
          brightness: dark ? Brightness.dark : Brightness.light,
          splashFactory: NoSplash.splashFactory,
          fontFamily: 'Inter',
          extensions: [
            dark ? AppColorsExtension.dark() : AppColorsExtension.light()
          ],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
            body: const SizedBox.shrink(), bottomNavigationBar: dock),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    OpenOnce.reset();
  });

  KuteBottomActionBar dockWith(VoidCallback onSearch) => KuteBottomActionBar(
        source: 'home',
        actions: [
          KuteDockAction(
              label: 'Receive',
              icon: Icons.south_west_rounded,
              trackingId: 'receive',
              onTap: () {}),
          KuteDockAction(
              label: 'Send',
              icon: Icons.north_east_rounded,
              trackingId: 'send',
              onTap: () {}),
        ],
        onSearch: onSearch,
      );

  testWidgets('with Sal on, the square is a magnifier with Sal\'s face in '
      'the lens: search or ask',
      (tester) async {
    final semantics = tester.ensureSemantics();
    var opened = 0;
    await _pump(tester, dockWith(() => opened++));
    expect(find.byType(KuteDogMagnifier), findsOneWidget);
    expect(find.byIcon(Icons.search_rounded), findsNothing);
    expect(find.byIcon(Icons.add_rounded), findsNothing);
    expect(find.byTooltip('Search or ask Sal'), findsOneWidget);
    expect(find.bySemanticsLabel('Search or ask Sal'), findsOneWidget);
    // The glyph's square fills most of the 54 button, inside it with a
    // small margin, the glass in the theme's foreground like the other
    // dock icons.
    final glyph = tester.widget<KuteDogMagnifier>(find.byType(KuteDogMagnifier));
    final element = tester.element(find.byType(KuteDogMagnifier));
    expect(glyph.size, greaterThanOrEqualTo(44));
    expect(glyph.size, lessThanOrEqualTo(48));
    expect(glyph.lensColor, element.colors.textPrimary);
    final drawn = tester.getSize(find.byType(KuteDogMagnifier));
    expect(drawn.width, moreOrLessEquals(glyph.size));
    expect(drawn.height, moreOrLessEquals(glyph.size));
    await tester.tap(find.byType(KuteDogMagnifier));
    expect(opened, 1);
    semantics.dispose();
  });

  testWidgets('the glass and Sal paint in light and dark', (tester) async {
    for (final dark in [false, true]) {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
          extensions: [
            dark ? AppColorsExtension.dark() : AppColorsExtension.light()
          ],
        ),
        home: Builder(
          builder: (context) => Center(
            child: KuteDogMagnifier(
                size: 30, lensColor: context.colors.textPrimary),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(KuteDogMagnifier)),
          const Size.square(30));
    }
  });

  testWidgets('with AI off, the square is the plain magnifier', (tester) async {
    final semantics = tester.ensureSemantics();
    var opened = 0;
    await _pump(tester, dockWith(() => opened++), aiEnabled: false);
    expect(find.byType(KuteDogMagnifier), findsNothing);
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    // The same visual size as Sal's glass (its lens about 18 across).
    expect(tester.widget<Icon>(find.byIcon(Icons.search_rounded)).size, 34);
    expect(find.byTooltip('Search'), findsOneWidget);
    expect(find.byTooltip('Search or ask Sal'), findsNothing);
    expect(find.bySemanticsLabel('Search'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.search_rounded));
    expect(opened, 1);
    semantics.dispose();
  });

  testWidgets('Sal plays once on appearing, rests, and plays again later',
      (tester) async {
    await _pump(tester, dockWith(() {}));
    // pumpAndSettle returned: the play ended and nothing ticks between
    // plays.
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pump(const Duration(seconds: 10));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('under Reduce Motion Sal holds still', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _pump(tester, dockWith(() {}));
    expect(find.byType(KuteDogMagnifier), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(KuteDogMagnifier),
            matching: find.byType(AnimatedBuilder)),
        findsNothing);
    await tester.pump(const Duration(seconds: 30));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('Sal holds still while his tickers are off, and plays when '
      'they come back', (tester) async {
    final ticking = ValueNotifier(false);
    addTearDown(ticking.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: [AppColorsExtension.light()]),
      home: ValueListenableBuilder<bool>(
        valueListenable: ticking,
        builder: (context, on, _) => TickerMode(
          enabled: on,
          child: Center(
            child: KuteDogMagnifier(
                size: 46, lensColor: context.colors.textPrimary),
          ),
        ),
      ),
    ));
    AnimationController controller() => tester
        .widget<AnimatedBuilder>(find.descendant(
            of: find.byType(KuteDogMagnifier),
            matching: find.byType(AnimatedBuilder)))
        .animation as AnimationController;
    // Out of view: no play, no timer, the rest frame.
    await tester.pump(const Duration(seconds: 30));
    expect(controller().isAnimating, isFalse);
    expect(controller().value, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
    // Back in view: one play, then rest.
    ticking.value = true;
    await tester.pump();
    expect(controller().isAnimating, isTrue);
    await tester.pumpAndSettle();
    expect(controller().isAnimating, isFalse);
    // Turned off mid-play: it stops at the rest frame.
    await tester.pump(const Duration(seconds: 7));
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller().isAnimating, isTrue);
    ticking.value = false;
    await tester.pump();
    expect(controller().isAnimating, isFalse);
    expect(controller().value, 0);
    await tester.pump(const Duration(seconds: 30));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('every frame of Sal\'s play paints at 1x, 2x and 3x',
      (tester) async {
    for (final dpr in [1.0, 2.0, 3.0]) {
      tester.view.devicePixelRatio = dpr;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(extensions: [AppColorsExtension.dark()]),
        home: Builder(
          builder: (context) => Center(
            child: KuteDogMagnifier(
                size: 46, lensColor: context.colors.textPrimary),
          ),
        ),
      ));
      for (var ms = 0; ms <= 2100; ms += 50) {
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('no search callback, no square', (tester) async {
    await _pump(tester, const KuteBottomActionBar(source: 'home'));
    expect(find.byIcon(Icons.search_rounded), findsNothing);
    expect(find.byType(KuteDogMagnifier), findsNothing);
    expect(find.byIcon(Icons.add_rounded), findsNothing);
  });

  testWidgets('the Dollars dock searches the spending account\'s activity',
      (tester) async {
    final container =
        await _pump(tester, const UsdAccountActionBar());
    expect(find.byType(KuteDogMagnifier), findsOneWidget);
    expect(find.byIcon(Icons.add_rounded), findsNothing);
    await tester.tap(find.byType(KuteDogMagnifier));
    await tester.pumpAndSettle();
    expect(find.byType(UnifiedSearchSurface), findsOneWidget);
    expect(container.read(searchWalletScopeProvider), 'spending');
    expect(container.read(selectedSearchCategoryProvider),
        SearchCategory.transactions);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets('a solid Portfolio wears the primary CTA fill, Withdraw '
        'keeps the neutral chrome (${dark ? 'dark' : 'light'})',
        (tester) async {
      await _pump(
          tester,
          KuteBottomActionBar(
            source: 'trading',
            actions: [
              KuteDockAction(
                  label: 'Portfolio',
                  icon: Icons.pie_chart_rounded,
                  trackingId: 'portfolio',
                  solid: true,
                  onTap: () {}),
              KuteDockAction(
                  label: 'Withdraw',
                  icon: Icons.north_east_rounded,
                  trackingId: 'withdraw',
                  onTap: () {}),
            ],
            onSearch: () {},
          ),
          dark: dark);
      final context = tester.element(find.text('Portfolio'));
      Container box(String label) => tester.widget<Container>(find
          .ancestor(of: find.text(label), matching: find.byType(Container))
          .last);
      BoxDecoration fill(String label) =>
          box(label).decoration! as BoxDecoration;
      // Portfolio: near-black with white in light, white with near-black
      // in dark, no border, no shadow.
      expect(fill('Portfolio').color, context.ctaFill);
      expect(fill('Portfolio').color,
          dark ? AppColors.ctaFillDark : context.colors.textPrimary);
      expect(fill('Portfolio').border, isNull);
      expect(fill('Portfolio').boxShadow, isNull);
      expect(fill('Portfolio').borderRadius, AppRadius.buttonBorder);
      expect(tester.widget<Text>(find.text('Portfolio')).style!.color,
          context.ctaOnColor);
      expect(tester.widget<Icon>(find.byIcon(Icons.pie_chart_rounded)).color,
          context.ctaOnColor);
      // Withdraw: unchanged neutral chrome.
      expect(fill('Withdraw').color,
          dark ? context.colors.surface : Colors.white);
      expect(fill('Withdraw').border, isNotNull);
      expect(tester.widget<Text>(find.text('Withdraw')).style!.color,
          context.colors.textPrimary);
      expect(tester.widget<Icon>(find.byIcon(Icons.north_east_rounded)).color,
          context.colors.textPrimary);
      // Same size either way.
      expect(tester.getSize(find.byWidget(box('Portfolio'))).height,
          tester.getSize(find.byWidget(box('Withdraw'))).height);
    });
  }

  testWidgets('a disabled solid verb fades like a disabled primary CTA',
      (tester) async {
    await _pump(
        tester,
        const KuteBottomActionBar(source: 'trading', actions: [
          KuteDockAction(
              label: 'Portfolio',
              icon: Icons.pie_chart_rounded,
              trackingId: 'portfolio',
              solid: true,
              onTap: null),
        ]));
    final opacity = tester.widget<Opacity>(find
        .ancestor(of: find.text('Portfolio'), matching: find.byType(Opacity))
        .first);
    expect(opacity.opacity, 0.35);
  });

  testWidgets('the venue dock leads with the pie-chart Portfolio, solid',
      (tester) async {
    for (final product in InvestmentsProduct.values) {
      await _pump(tester, InvestmentActionBar(product: product));
      final bar = tester
          .widget<KuteBottomActionBar>(find.byType(KuteBottomActionBar));
      expect(bar.actions.map((a) => a.trackingId), ['portfolio', 'withdraw']);
      expect(bar.actions.first.icon, Icons.pie_chart_rounded);
      expect(bar.actions.map((a) => a.solid), [true, false]);
      expect(find.byIcon(Icons.account_balance_wallet_rounded), findsNothing);
    }
  });

  testWidgets('home and Investing dock searches open the same sheet',
      (tester) async {
    // Owner report: Home's search square opened a different screen (the
    // Sal intro) from the venue's. Every dock opens the one results-first
    // search sheet; only the category differs.
    UnifiedSearchSurface opened(WidgetTester tester) {
      final surface = tester
          .widget<UnifiedSearchSurface>(find.byType(UnifiedSearchSurface));
      expect(find.byType(SalSuggestionButton), findsNothing);
      return surface;
    }

    await _pump(tester, const HomeDock());
    await tester.tap(find.byType(KuteDogMagnifier));
    await tester.pumpAndSettle();
    final home = opened(tester);
    expect(find.text('Search transactions, Predictions and Investing'),
        findsOneWidget);
    // The field names both jobs, the square's own words.
    expect(
        tester.widget<TextField>(find.byType(TextField)).decoration!.hintText,
        'Search or ask Sal');
    await tester.pumpWidget(const SizedBox.shrink());
    OpenOnce.reset();

    await _pump(tester,
        const InvestmentActionBar(product: InvestmentsProduct.trading));
    await tester.tap(find.byType(KuteDogMagnifier));
    await tester.pumpAndSettle();
    final investing = opened(tester);

    expect(home.runtimeType, investing.runtimeType);
    expect(home.searchFirst, isTrue);
    expect(investing.searchFirst, isTrue);
    expect(home.lockCategory, investing.lockCategory);
    expect(home.walletId, investing.walletId);
    expect(home.initialCategory, SearchCategory.all);
    expect(investing.initialCategory, SearchCategory.perpetuals);
    expect(tester.takeException(), isNull);
  });
}
