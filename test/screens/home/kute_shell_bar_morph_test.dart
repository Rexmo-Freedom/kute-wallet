// The pill becoming the Sal sheet's composer (kute_shell_bar.dart,
// search_morph.dart): tapping the pill starts the travelling copy and
// draws the pill transparent in place; the copy lands on the composer's
// rect; closing travels back and the pill is itself again. A context
// placed in the page's header keeps the pill away and the page's
// KuteSalHeaderButton (the Share pill) opens the same sheet, travelling too. Reduce
// Motion: a plain sheet, nothing travels.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/app_router.dart' show AppRouter;
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/providers/unified_search_provider.dart';
import 'package:kute/screens/home/components/kute_bottom_action_bar.dart'
    show KuteSalPill;
import 'package:kute/screens/home/components/kute_shell_bar.dart';
import 'package:kute/screens/search/components/search_composer.dart';
import 'package:kute/screens/search/components/search_morph.dart';
import 'package:kute/screens/search/unified_search_screen.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/theme/app_theme.dart';

class _Sports extends SportsLiveNotifier {
  @override
  Map<String, SportsMatchUpdate> build() => {};
  @override
  void connect() {}
}

/// The app's layering with the app's own root navigator key (the bar
/// opens the sheet over it), the scroll listener and the route observer.
Future<void> _pump(WidgetTester tester, {bool reduce = false}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      aiEnabledProvider.overrideWith((_) async => true),
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
        navigatorKey: AppRouter.rootNavigatorKey,
        navigatorObservers: [KuteBarRouteObserver()],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
          child: Stack(children: [
            NotificationListener<ScrollNotification>(
              onNotification: kuteBarScroll.report,
              child: child!,
            ),
            const KuteShellBar(),
          ]),
        ),
        home: const Scaffold(body: SizedBox.expand()),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

NavigatorState _nav() => AppRouter.rootNavigatorKey.currentState!;

/// A market page's context: an action row, so the sheet is the context
/// variant (no browse feeds read).
KuteBarContext _market(
        {KuteBarPlacement placement = KuteBarPlacement.bottom}) =>
    KuteBarContext(
      label: 'Share with your friends',
      clip: 'share',
      placement: placement,
      actions: [
        KuteBarAction(label: 'Share the market', onTap: (_) {}),
      ],
    );

Future<void> _push(WidgetTester tester, Widget page) async {
  _nav().push(MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'market'), builder: (_) => page));
  await tester.pumpAndSettle();
}

Widget _page(KuteBarContext ctx, {bool headerButton = false}) =>
    KuteBarContextScope(
      barContext: ctx,
      child: Scaffold(
        body: Column(children: [
          if (headerButton)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                const Spacer(),
                KuteSalHeaderButton(barContext: ctx),
              ]),
            ),
          const Expanded(child: SizedBox.expand()),
        ]),
      ),
    );

bool _barUp(WidgetTester tester) {
  final slide = tester.widget<AnimatedSlide>(
      find.byKey(const ValueKey('kute-shell-bar-slide')));
  return slide.offset == Offset.zero;
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    KuteBarRouteObserver.reset();
    OpenOnce.reset();
  });

  testWidgets(
      'tapping the pill: the travelling copy runs while the pill stays in '
      'place transparent, lands on the composer, and travels back on close',
      (tester) async {
    await _pump(tester);
    await _push(tester, _page(_market()));
    expect(find.byType(KuteSalPill), findsOneWidget);
    final pillRect = tester.getRect(find.byType(KuteSalPill));

    await tester.tap(find.byType(KuteSalPill));
    await tester.pump();
    // The copy is up, the pill is in place and transparent, the bar never
    // slid away.
    expect(KuteSearchMorph.running, isTrue);
    expect(kuteSearchMorphing.value, isTrue);
    expect(find.byKey(const ValueKey('kute-bar-morphed')), findsOneWidget);
    expect(_barUp(tester), isTrue);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(UnifiedSearchSurface), findsOneWidget);
    expect(_barUp(tester), isTrue);

    // Landed: the copy is gone, the composer is where it was heading.
    await tester.pumpAndSettle();
    expect(KuteSearchMorph.running, isFalse);
    expect(kuteSearchMorphing.value, isFalse);
    final composer = tester.getRect(find.byType(KuteSearchComposer));
    final overlay = AppRouter.rootNavigatorKey.currentState!.overlay!;
    final rest = KuteSearchMorph.composerRestRect(overlay.context);
    expect(composer.top, moreOrLessEquals(rest.top, epsilon: 0.5));
    expect(composer.bottom, moreOrLessEquals(rest.bottom, epsilon: 0.5));
    expect(composer.left, moreOrLessEquals(rest.left, epsilon: 0.5));
    expect(composer.right, moreOrLessEquals(rest.right, epsilon: 0.5));
    // Still the pill's place, transparent, while the sheet is up.
    expect(find.byKey(const ValueKey('kute-bar-morphed')), findsOneWidget);

    // Closing: the way back runs as the sheet drops, then the pill is
    // itself again where it was.
    _nav().pop();
    await tester.pump();
    expect(KuteSearchMorph.running, isTrue);
    expect(kuteSearchMorphing.value, isTrue);
    await tester.pumpAndSettle();
    expect(KuteSearchMorph.running, isFalse);
    expect(find.byKey(const ValueKey('kute-bar-morphed')), findsNothing);
    expect(find.byType(UnifiedSearchSurface), findsNothing);
    expect(tester.getRect(find.byType(KuteSalPill)), pillRect);
    expect(_barUp(tester), isTrue);
    await tester.pump(const Duration(seconds: 6));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Reduce Motion: a plain sheet, nothing travels', (tester) async {
    await _pump(tester, reduce: true);
    await _push(tester, _page(_market()));
    await tester.tap(find.byType(KuteSalPill));
    await tester.pump();
    expect(KuteSearchMorph.running, isFalse);
    expect(kuteSearchMorphing.value, isFalse);
    expect(find.byKey(const ValueKey('kute-bar-morphed')), findsNothing);
    await tester.pumpAndSettle();
    expect(find.byType(UnifiedSearchSurface), findsOneWidget);
    // The hidden context slid the bar away, as before.
    expect(_barUp(tester), isFalse);
    _nav().pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 6));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a header placement keeps the pill away; the page\'s KuteSalHeaderButton '
      'opens the same sheet and travels to the composer', (tester) async {
    await _pump(tester);
    await _push(tester,
        _page(_market(placement: KuteBarPlacement.header), headerButton: true));
    expect(_barUp(tester), isFalse);
    final button = find.byKey(const ValueKey('kute-sal-header-button'));
    expect(button, findsOneWidget);
    // A compact pill: 32 tall, Sal's face and the word "Share", no badge
    // (founder: the circle alone "should say share or send").
    final rect = tester.getRect(button);
    expect(rect.height, KuteSalHeaderButton.height);
    expect(rect.width, greaterThan(KuteSalHeaderButton.height));
    expect(
        find.descendant(
            of: button,
            matching: find.byKey(const ValueKey('kute-sal-header-label'))),
        findsOneWidget);
    expect(find.descendant(of: button, matching: find.text('Share')),
        findsOneWidget);
    expect(find.byIcon(Icons.ios_share_rounded), findsNothing);

    await tester.tap(button);
    await tester.pump();
    expect(KuteSearchMorph.running, isTrue);
    expect(
        tester
            .widget<Opacity>(
                find.ancestor(of: button, matching: find.byType(Opacity)).first)
            .opacity,
        0);
    await tester.pumpAndSettle();
    expect(find.byType(UnifiedSearchSurface), findsOneWidget);
    expect(find.text('Share the market'), findsOneWidget);
    // The bottom pill stayed away throughout.
    expect(_barUp(tester), isFalse);

    _nav().pop();
    await tester.pumpAndSettle();
    expect(KuteSearchMorph.running, isFalse);
    expect(
        tester
            .widget<Opacity>(
                find.ancestor(of: button, matching: find.byType(Opacity)).first)
            .opacity,
        1);
    await tester.pump(const Duration(seconds: 6));
    expect(tester.takeException(), isNull);
  });
}
