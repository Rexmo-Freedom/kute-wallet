// A slip opened FROM THE SEARCH SHEET keeps its primary button (founder,
// 6 November 2026: "Predictions on search have no buy button on the bet
// slip, and Hyperliquid the same"). The search sheet stays open under a
// market page and its slip (they stack on the root navigator), and the
// bar's pill had become the sheet's composer (kute_shell_bar.dart, THE
// PILL BECOMES THE COMPOSER): the bar held its place transparent and took
// no taps for as long as the SHEET was up, so the slip over it showed no
// button at all. The bar holds its place only while the sheet itself is
// on top; a page or a slip over it gets its own bar (its trade row, its
// primary with the round share button), and the sheet gets the held pill
// back when they close.

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

Future<void> _pump(WidgetTester tester, {bool reduce = false}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  kuteShellMounted.value = true;
  addTearDown(() => kuteShellMounted.value = false);
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

final _primary = find.byKey(const ValueKey('kute-bar-primary-button'));
final _share = find.byKey(const ValueKey('kute-bar-share'));
final _morphed = find.byKey(const ValueKey('kute-bar-morphed'));

bool _barUp(WidgetTester tester) {
  final slide = tester.widget<AnimatedSlide>(
      find.byKey(const ValueKey('kute-shell-bar-slide')));
  return slide.offset == Offset.zero;
}

/// Whether a tap at [finder]'s centre reaches its render box.
bool _tapLands(WidgetTester tester, Finder finder) {
  final box = tester.renderObject(finder);
  final result = tester.hitTestOnBinding(tester.getCenter(finder));
  return result.path.any((entry) => entry.target == box);
}

/// A slip over whatever is on top, on the root navigator as the real
/// slips are: its one action is the bar, with the round share button.
Future<void> _openSlip(WidgetTester tester, VoidCallback onPlace) async {
  showModalBottomSheet<void>(
    context: _nav().context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (_) => KuteBarContextScope(
      barContext: KuteBarContext.primary(
        label: r'Place prediction · $10',
        onPrimary: onPlace,
        disabledLabel: 'Enter an amount',
        share: KuteBarShare(send: () {}),
      ),
      child: const SizedBox(height: 520, width: double.infinity),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    KuteBarRouteObserver.reset();
    OpenOnce.reset();
  });

  testWidgets(
      'a slip over the search sheet shows its primary and the round share '
      'button, enabled and taking the tap; the sheet holds the pill again '
      'when the slip closes', (tester) async {
    await _pump(tester);
    expect(find.byType(KuteSalPill), findsOneWidget);
    final pillRect = tester.getRect(find.byType(KuteSalPill));

    // The pill becomes the sheet's composer.
    await tester.tap(find.byType(KuteSalPill));
    await tester.pumpAndSettle();
    expect(find.byType(UnifiedSearchSurface), findsOneWidget);
    expect(_morphed, findsOneWidget);

    var placed = 0;
    await _openSlip(tester, () => placed++);
    expect(_morphed, findsNothing);
    expect(_barUp(tester), isTrue);
    expect(_primary, findsOneWidget);
    expect(
        find.descendant(
            of: _primary, matching: find.text(r'Place prediction · $10')),
        findsOneWidget);
    expect(_share, findsOneWidget);
    expect(_tapLands(tester, _primary), isTrue);
    expect(_tapLands(tester, _share), isTrue);
    await tester.tap(_primary);
    await tester.pump();
    expect(placed, 1);

    // The slip closes: the search sheet is on top again, the bar holds
    // the pill in place for the way back.
    _nav().pop();
    await tester.pumpAndSettle();
    expect(find.byType(UnifiedSearchSurface), findsOneWidget);
    expect(_morphed, findsOneWidget);
    expect(find.descendant(of: _morphed, matching: find.byType(KuteSalPill)),
        findsOneWidget);

    // And the sheet closes onto the pill where it rests.
    _nav().pop();
    await tester.pumpAndSettle();
    expect(KuteSearchMorph.running, isFalse);
    expect(_morphed, findsNothing);
    expect(tester.getRect(find.byType(KuteSalPill)), pillRect);
    expect(_barUp(tester), isTrue);
    await tester.pump(const Duration(seconds: 6));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Reduce Motion: the sheet hides the bar, a slip over it brings its '
      'primary', (tester) async {
    await _pump(tester, reduce: true);
    await tester.tap(find.byType(KuteSalPill));
    await tester.pumpAndSettle();
    expect(find.byType(UnifiedSearchSurface), findsOneWidget);
    expect(_barUp(tester), isFalse);

    var placed = 0;
    await _openSlip(tester, () => placed++);
    expect(_barUp(tester), isTrue);
    expect(_primary, findsOneWidget);
    expect(_share, findsOneWidget);
    expect(_tapLands(tester, _primary), isTrue);
    await tester.tap(_primary);
    await tester.pump();
    expect(placed, 1);

    _nav().pop();
    await tester.pumpAndSettle();
    expect(_barUp(tester), isFalse);
    _nav().pop();
    await tester.pumpAndSettle();
    expect(_barUp(tester), isTrue);
    await tester.pump(const Duration(seconds: 6));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Reduce Motion: a page with no context of its own over the sheet '
      'gets the default pill, not the sheet\'s hidden bar', (tester) async {
    await _pump(tester, reduce: true);
    await tester.tap(find.byType(KuteSalPill));
    await tester.pumpAndSettle();
    expect(_barUp(tester), isFalse);
    _nav().push(MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'tx_detail'),
        builder: (_) => const Scaffold(body: SizedBox.expand())));
    await tester.pumpAndSettle();
    expect(_barUp(tester), isTrue);
    expect(find.byType(KuteSalPill), findsOneWidget);
    _nav().pop();
    await tester.pumpAndSettle();
    expect(_barUp(tester), isFalse);
    _nav().pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 6));
    expect(tester.takeException(), isNull);
  });
}
