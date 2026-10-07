// The search sheet with the keyboard up: the composer ("Search or ask Sal",
// Sal's dog leading it) keeps the sheets' 16dp bottom baseline above the
// keyboard instead of resting on the keys, the idle Sal questions stay
// above it, and nothing overflows on a small phone.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/trade_notifications_provider.dart';
import 'package:kute/providers/unified_search_provider.dart';
import 'package:kute/screens/search/unified_search_screen.dart';
import 'package:kute/screens/shared/ask_sal_sheet.dart'
    show SalSuggestionButton;
import 'package:kute/screens/shared/kute_composer.dart';
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/services/trade_notification_store.dart'
    show TradeNotification;
import 'package:kute/theme/app_theme.dart';

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

final _navigator = GlobalKey<NavigatorState>();

Future<void> _open(WidgetTester tester, Size screen, double keyboard) async {
  tester.view.physicalSize = screen;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      settingsProvider.overrideWith((_) => SettingsModel(_settings())),
      aiEnabledProvider.overrideWith((_) async => true),
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
        navigatorKey: _navigator,
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
        ),
      ),
    ),
  ));
  ProviderScope.containerOf(tester.element(find.text('Open search')))
      .read(selectedSearchCategoryProvider.notifier)
      .state = SearchCategory.all;
  await tester.tap(find.text('Open search'));
  await tester.pump();
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  await tester.pumpAndSettle();
}

Future<void> _close(WidgetTester tester) async {
  _navigator.currentState!.pop();
  await tester.pumpAndSettle();
  // The idle mascot's delayed tagline exits after unmount.
  await tester.pump(const Duration(seconds: 6));
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    OpenOnce.reset();
  });

  // A large phone with its keyboard, and the smallest supported phone
  // (iPhone SE 1st generation) with the tall keyboard plus suggestions.
  for (final (name, screen, keyboard) in [
    ('large phone', const Size(430, 932), 336.0),
    ('small phone', const Size(320, 568), 253.0),
  ]) {
    testWidgets('$name: the composer sits 16dp above the keyboard',
        (tester) async {
      await _open(tester, screen, keyboard);
      expect(tester.takeException(), isNull);
      // The sheets' bottom baseline (16.h on the 932 design height).
      final gap = 16 * screen.height / 932;
      final keyboardTop = screen.height - keyboard;
      final composer = tester.getRect(find.byType(KuteComposer));
      expect(composer.bottom, moreOrLessEquals(keyboardTop - gap, epsilon: 0.5));
      // Before the fix it rested on the keys (a 0dp gap).
      expect(keyboardTop - composer.bottom, greaterThan(9));
      // Sal's opening questions sit above the composer, never under it,
      // and the first one is on screen.
      final chips = find.byType(SalSuggestionButton);
      expect(chips, findsWidgets);
      final first = tester.getRect(chips.first);
      expect(first.top, greaterThanOrEqualTo(0));
      expect(first.top, lessThan(composer.top));
      // The last one scrolls into view rather than being cut off.
      await tester.ensureVisible(chips.last);
      await tester.pumpAndSettle();
      expect(tester.getRect(chips.last).bottom,
          lessThanOrEqualTo(composer.top + 0.5));
      expect(tester.takeException(), isNull);
      await _close(tester);
    });
  }

  testWidgets('the composer takes focus once the sheet has slid in, not '
      'before', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _open(tester, const Size(430, 932), 0);
    await _close(tester);
    bool focused() => tester
        .widget<EditableText>(find.descendant(
            of: find.byType(KuteComposer),
            matching: find.byType(EditableText)))
        .focusNode
        .hasFocus;
    await tester.tap(find.text('Open search'));
    await tester.pump();
    // Mid-slide (250 ms): the composer is on screen, not focused, so the
    // keyboard never rises against a moving sheet.
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(KuteComposer), findsOneWidget);
    expect(focused(), isFalse);
    await tester.pump(const Duration(milliseconds: 100));
    expect(focused(), isFalse);
    // Settled: focused, the keyboard's turn.
    await tester.pumpAndSettle();
    expect(focused(), isTrue);
    expect(tester.takeException(), isNull);
    await _close(tester);
  });

  testWidgets('keyboard down: the composer keeps the home-indicator spacing',
      (tester) async {
    tester.view.padding = const FakeViewPadding(bottom: 34);
    await _open(tester, const Size(430, 932), 0);
    final composer = tester.getRect(find.byType(KuteComposer));
    // Home indicator plus the same 16dp baseline.
    expect(composer.bottom, moreOrLessEquals(932 - 34 - 16, epsilon: 0.5));
    await _close(tester);
  });
}
