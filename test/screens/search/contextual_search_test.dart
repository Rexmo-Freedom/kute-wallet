import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/advisor_context.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/providers/unified_search_provider.dart';
import 'package:kute/screens/portfolio/open_investments_screen.dart';
import 'package:kute/screens/search/unified_search_screen.dart';
import 'package:kute/screens/shared/ask_sal_sheet.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/services/advisor/advisor_input_guard.dart';

class _Sports extends SportsLiveNotifier {
  @override
  Map<String, SportsMatchUpdate> build() => {};
  @override
  void connect() {}
}

class _Advisor extends AdvisorSessionNotifier {
  _Advisor(this.probe);
  final _Probe probe;
  @override
  AdvisorSessionState build() {
    probe.advisorBuilds++;
    return const AdvisorSessionState();
  }

  @override
  Future<void> ask(String query,
      {AdvisorContext? context,
      String input = 'typed',
      String? template,
      int? chipIndex,
      String? locale}) async {
    probe.advisorRequests.add(query);
    probe.asks.add((input: input, template: template, chipIndex: chipIndex));
    state = AdvisorSessionState(turns: [AdvisorTurn(query: query)]);
  }
}

class _Probe {
  int advisorBuilds = 0;
  int aiConfigReads = 0;
  final advisorRequests = <String>[];
  final asks = <({String input, String? template, int? chipIndex})>[];
  final publicQueries = <String>[];
  final navigator = GlobalKey<NavigatorState>();
  late ProviderContainer container;
}

Future<_Probe> _openSearch(
  WidgetTester tester, {
  InvestmentsProduct? product,
  bool aiEnabled = true,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final probe = _Probe();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      aiEnabledProvider.overrideWith((_) async {
        probe.aiConfigReads++;
        return aiEnabled;
      }),
      advisorSessionProvider.overrideWith(() => _Advisor(probe)),
      sportsLiveProvider.overrideWith(_Sports.new),
      unifiedSearchResultsProvider
          .overrideWith((_) async => UnifiedSearchResults.empty),
      globalMarketResultsProvider.overrideWith((ref) {
        probe.publicQueries.add(ref.watch(searchQueryProvider));
        return const AsyncValue.data([]);
      }),
      globalHyperliquidResultsProvider.overrideWith((ref) {
        probe.publicQueries.add(ref.watch(searchQueryProvider));
        return const AsyncValue.data([]);
      }),
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
                      onPressed: () => showKuteSearch(
                        context,
                        initialCategory: product == null
                            ? SearchCategory.all
                            : product == InvestmentsProduct.trading
                                ? SearchCategory.perpetuals
                                : SearchCategory.predictions,
                        searchHint: product == null
                            ? null
                            : product == InvestmentsProduct.trading
                                ? 'Search investments or ask for anything'
                                : 'Search predictions or ask for anything',
                        source: product == null ? 'home' : product.name,
                      ),
                      child: const Text('Open search'),
                    ))),
      ),
    ),
  ));
  probe.container =
      ProviderScope.containerOf(tester.element(find.text('Open search')));
  await tester.tap(find.text('Open search'));
  await tester.pumpAndSettle();
  return probe;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The guard caches this asset future; load it outside a per-test fake clock.
  setUpAll(
      () async => expect(await AdvisorInputGuard.isSafe('bitcoin'), isTrue));
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  for (final product in InvestmentsProduct.values) {
    for (final aiEnabled in [true, false]) {
      testWidgets(
          '${product.name} context search with AI ${aiEnabled ? 'on' : 'off'}',
          (tester) async {
        final probe =
            await _openSearch(tester, product: product, aiEnabled: aiEnabled);
        // With Sal on, the field names both jobs whatever venue opened it,
        // the dock square's own words; search-only keeps the market hint.
        final hint = aiEnabled ? 'Search or ask Sal' : 'Search markets';
        expect(
            tester
                .widget<TextField>(find.byType(TextField))
                .decoration!
                .hintText,
            hint);
        expect(find.text('Manage portfolio'), findsNothing);
        expect(find.text('Markets'), findsNothing);
        expect(find.byIcon(Icons.qr_code_scanner_rounded), findsNothing);
        expect(tester.widget<TextField>(find.byType(TextField)).textInputAction,
            aiEnabled ? TextInputAction.send : TextInputAction.search);
        expect(
            probe.container.read(selectedSearchCategoryProvider),
            product == InvestmentsProduct.trading
                ? SearchCategory.perpetuals
                : SearchCategory.predictions);

        // Typing searches the initial venue without asking Sal.
        await tester.enterText(find.byType(TextField), 'bitcoin');
        await tester.pump(const Duration(milliseconds: 200));
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pumpAndSettle();
        expect(probe.container.read(searchQueryProvider), 'bitcoin');
        expect(probe.publicQueries, contains('bitcoin'));
        expect(probe.advisorRequests, isEmpty);

        // Private text must not be sent to public market providers.
        final privateQuery = '0x${List.filled(40, '1').join()}';
        await tester.enterText(find.byType(TextField), privateQuery);
        await tester.pump(const Duration(milliseconds: 200));
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pumpAndSettle();
        expect(probe.container.read(searchQueryProvider), isEmpty);
        expect(probe.publicQueries, isNot(contains(privateQuery)));

        if (aiEnabled) {
          // Venue context must not restrict Sal to investment questions.
          await tester.enterText(
              find.byType(TextField), 'How do rainbows form?');
          await tester.testTextInput.receiveAction(TextInputAction.send);
          await tester.pumpAndSettle();
          expect(probe.advisorRequests, ['How do rainbows form?']);
          expect(find.byType(SalChatPanel), findsOneWidget);
          expect(probe.container.read(searchQueryProvider), isEmpty);
        } else {
          await tester.enterText(find.byType(TextField), 'bitcoin');
          await tester.runAsync(() async {
            await tester.testTextInput.receiveAction(TextInputAction.search);
            await Future<void>.delayed(Duration.zero);
          });
          await tester.pumpAndSettle();
          expect(probe.container.read(searchQueryProvider), 'bitcoin');
          expect(
              tester.widget<TextField>(find.byType(TextField)).controller!.text,
              'bitcoin');
          expect(find.byType(SalChatPanel), findsNothing);
          expect(probe.advisorRequests, isEmpty);
        }
        probe.navigator.currentState!.pop();
        await tester.pumpAndSettle();
        // The idle Home-style mascot's delayed tagline exits after unmount.
        await tester.pump(const Duration(seconds: 6));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('Home keeps Ask Sal but has no scanner in the search sheet',
      (tester) async {
    final probe = await _openSearch(tester);
    expect(find.text('Search or ask Sal anything'), findsWidgets);
    expect(find.byIcon(Icons.qr_code_scanner_rounded), findsNothing);
    expect(find.byTooltip('Scan QR code'), findsNothing);
    await tester.enterText(find.byType(TextField), 'Explain margin');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    expect(find.byType(SalChatPanel), findsOneWidget);
    expect(probe.advisorRequests, ['Explain margin']);
    expect(find.byIcon(Icons.qr_code_scanner_rounded), findsNothing);
    probe.navigator.currentState!.pop();
    await tester.pumpAndSettle();
    // Home's rotating tagline uses a delayed callback that exits after unmount.
    await tester.pump(const Duration(seconds: 6));
    expect(tester.takeException(), isNull);
  });

  testWidgets('idle Home search offers Sal\'s opening questions as chips',
      (tester) async {
    final probe = await _openSearch(tester);
    expect(find.byType(SalSuggestionButton), findsWidgets);
    await tester.tap(find.text('How do I receive Bitcoin in Kute?'));
    await tester.pumpAndSettle();
    expect(probe.advisorRequests, ['How do I receive Bitcoin in Kute?']);
    expect(probe.asks.single,
        (input: 'suggested', template: 'wallet.receive', chipIndex: 0));
    probe.navigator.currentState!.pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 6));
    expect(tester.takeException(), isNull);
  });
}
