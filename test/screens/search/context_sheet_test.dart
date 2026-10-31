// The Sal sheet opened from the bar on a market page (a context screen,
// kute_share_actions.dart): the market preview card, the two action rows
// in one card, "Ask Sal" as a row of chips; no filter pills, no
// "Recommended" label, and the keyboard down until the field is tapped.

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
import 'package:kute/screens/search/unified_search_screen.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/screens/shared/kute_share_actions.dart';
import 'package:kute/theme/app_theme.dart';

class _Sports extends SportsLiveNotifier {
  @override
  Map<String, SportsMatchUpdate> build() => {};
  @override
  void connect() {}
}

class _Advisor extends AdvisorSessionNotifier {
  _Advisor(this.asked);
  final List<String> asked;
  @override
  AdvisorSessionState build() => const AdvisorSessionState();

  @override
  Future<void> ask(String query,
      {AdvisorContext? context,
      String input = 'typed',
      String? template,
      int? chipIndex,
      String? locale}) async {
    asked.add(query);
    state = AdvisorSessionState(turns: [AdvisorTurn(query: query)]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets(
      'a market context: preview card, one actions card, no chips, '
      'no pills, no Recommended, keyboard down', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final asked = <String>[];
    final tapped = <String>[];
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        aiEnabledProvider.overrideWith((_) async => true),
        advisorSessionProvider.overrideWith(() => _Advisor(asked)),
        sportsLiveProvider.overrideWith(_Sports.new),
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
          navigatorKey: navigator,
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
                  initialCategory: SearchCategory.predictions,
                  source: 'predictions',
                  barContext: KuteMarketBarContext(
                    label: 'Share with your friends',
                    preview: const KuteBarPreview(
                        title: 'Gemini Carbon', line: 'Yes 62%'),
                    prompts: const ['Explain the odds', "What's the risk?"],
                    category: SearchCategory.predictions,
                    actions: [
                      KuteMarketBarAction(
                        label: 'Share the market',
                        sublabel: 'A link they can open, with your code',
                        icon: Icons.ios_share_rounded,
                        onTap: (_) => tapped.add('share'),
                      ),
                      KuteMarketBarAction(
                        label: 'Send this prediction',
                        sublabel: 'They get your pick, ready to place',
                        salClip: 'share',
                        onTap: (_) => tapped.add('send'),
                      ),
                    ],
                  ),
                ),
                child: const Text('Open search'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open search'));
    await tester.pumpAndSettle();

    // The designed top: the preview, the one card with both rows, the chips.
    expect(find.byKey(const ValueKey('context-preview-card')), findsOneWidget);
    expect(find.text('Gemini Carbon'), findsOneWidget);
    expect(find.text('Yes 62%'), findsOneWidget);
    expect(find.byKey(const ValueKey('context-actions-card')), findsOneWidget);
    expect(find.text('Share the market'), findsOneWidget);
    expect(find.text('Send this prediction'), findsOneWidget);
    // No Ask Sal chips (founder, 31 October 2026).
    expect(find.text('Ask Sal'), findsNothing);
    expect(find.text('Explain the odds'), findsNothing);
    // Not search scoping, not the old label, no dollars wording.
    expect(find.byType(KutePillTabs), findsNothing);
    expect(find.text('Recommended'), findsNothing);
    expect(find.textContaining('dollars'), findsNothing);
    // The keyboard stays down until the field is tapped.
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode!.hasFocus, isFalse);

    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 6));
    expect(tester.takeException(), isNull);
  });

  testWidgets('an action row runs its action and closes the sheet',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final tapped = <String>[];
    await tester.pumpWidget(ProviderScope(
      overrides: [
        aiEnabledProvider.overrideWith((_) async => false),
        sportsLiveProvider.overrideWith(_Sports.new),
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
                  source: 'trading',
                  barContext: KuteMarketBarContext(
                    label: 'Share with your friends',
                    preview: const KuteBarPreview(title: 'BTC', line: 'Long'),
                    actions: [
                      KuteMarketBarAction(
                        label: 'Send this investment',
                        salClip: 'share',
                        onTap: (_) => tapped.add('send'),
                      ),
                    ],
                  ),
                ),
                child: const Text('Open search'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open search'));
    await tester.pumpAndSettle();
    // Sal off: no chips, still the card.
    expect(find.text('Ask Sal'), findsNothing);
    await tester.tap(find.text('Send this investment'));
    await tester.pumpAndSettle();
    expect(tapped, ['send']);
    expect(find.text('Send this investment'), findsNothing);
    // The dog glyph's delayed glance exits after unmount.
    await tester.pump(const Duration(seconds: 6));
    expect(tester.takeException(), isNull);
  });
}
