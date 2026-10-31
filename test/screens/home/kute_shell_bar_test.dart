// The bar over everything (kute_shell_bar.dart, kute_bar_context.dart):
// away over the tabs, up with the default over any page or sheet pushed
// over them, never over a dialog or a lock screen, hidden by the keyboard
// and by a hidden context, honouring a page's context while its route is
// current, lifted above a declared action row; and on a market page,
// folding into Sal's circle while the page scrolls down.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart' show NoTransitionPage;
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/screens/home/components/kute_bottom_action_bar.dart'
    show KuteSalPill;
import 'package:kute/screens/home/components/kute_shell_bar.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/theme/app_theme.dart';

const _kHome = Key('shell-bar-test-home');
final _navKey = GlobalKey<NavigatorState>();

/// The app's layering in miniature: a root navigator under the bar, the
/// scroll listener around it, the route observer on it.
Future<ProviderContainer> _pump(WidgetTester tester,
    {bool reduce = false}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(overrides: [
    aiEnabledProvider.overrideWith((_) async => true),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
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
        navigatorKey: _navKey,
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
        home: const Scaffold(body: SizedBox.expand(key: _kHome)),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return container;
}

NavigatorState _nav(WidgetTester tester) => _navKey.currentState!;

/// A page over the tabs, with a long list to scroll and, when given, a
/// bar context of its own.
Widget _page({KuteBarContext? barContext}) {
  final body = Scaffold(
    body: ListView.builder(
      itemCount: 60,
      itemBuilder: (_, i) => SizedBox(height: 56, child: Text('Row $i')),
    ),
  );
  return barContext == null
      ? body
      : KuteBarContextScope(barContext: barContext, child: body);
}

Future<void> _push(WidgetTester tester, Widget page, {String? name}) async {
  _nav(tester).push(MaterialPageRoute<void>(
      settings: RouteSettings(name: name), builder: (_) => page));
  await tester.pumpAndSettle();
}

/// Whether the bar is up: shown and taking taps.
bool _up(WidgetTester tester) {
  final slide = tester.widget<AnimatedSlide>(
      find.byKey(const ValueKey('kute-shell-bar-slide')));
  return slide.offset == Offset.zero;
}

const _market = KuteBarContext(
  label: 'Share with your friends',
  sublabel: 'Send the market',
  clip: 'share',
  actionRowHeight: 80,
);

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    KuteBarRouteObserver.reset();
  });

  testWidgets('away over the tabs; up with the default over a pushed page',
      (tester) async {
    await _pump(tester);
    expect(find.byType(KuteSalPill), findsNothing);

    await _push(tester, _page(), name: 'settings');
    expect(_up(tester), isTrue);
    expect(find.text('Search or ask Sal'), findsOneWidget);

    _nav(tester).pop();
    await tester.pumpAndSettle();
    expect(_up(tester), isFalse);
  });

  testWidgets('a bottom sheet counts; a dialog and a lock screen do not',
      (tester) async {
    await _pump(tester);
    final homeContext = _navKey.currentContext!;
    // ignore: unawaited_futures
    showKuteModalSheet<void>(
        context: homeContext,
        builder: (_) => const SizedBox(height: 300, child: Text('Sheet')));
    await tester.pumpAndSettle();
    expect(find.text('Sheet'), findsOneWidget);
    expect(_up(tester), isTrue);
    _nav(tester).pop();
    await tester.pumpAndSettle();
    expect(_up(tester), isFalse);

    // ignore: unawaited_futures
    showDialog<void>(
        context: homeContext, builder: (_) => const Text('Dialog'));
    await tester.pumpAndSettle();
    expect(find.text('Dialog'), findsOneWidget);
    expect(_up(tester), isFalse);
    _nav(tester).pop();
    await tester.pumpAndSettle();

    await _push(tester, _page(), name: 'open_pin');
    expect(_up(tester), isFalse);
  });

  testWidgets('the keyboard hides it; a hidden context hides it',
      (tester) async {
    final container = await _pump(tester);
    await _push(tester, _page(), name: 'settings');
    expect(_up(tester), isTrue);

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(_up(tester), isFalse);
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();
    expect(_up(tester), isTrue);

    const hidden = KuteBarContext.hidden();
    container.read(kuteBarContextProvider.notifier).push(hidden);
    await tester.pumpAndSettle();
    expect(_up(tester), isFalse);
    container.read(kuteBarContextProvider.notifier).remove(hidden);
    await tester.pumpAndSettle();
    expect(_up(tester), isTrue);
  });

  testWidgets(
      'a page\'s context reads while its route is current; a sheet over it '
      'gets the default', (tester) async {
    await _pump(tester);
    await _push(tester, _page(barContext: _market), name: 'market');
    expect(find.text('Share with your friends'), findsOneWidget);

    // ignore: unawaited_futures
    showKuteModalSheet<void>(
        context: _navKey.currentContext!,
        builder: (_) => const SizedBox(height: 300, child: Text('Slip')));
    await tester.pumpAndSettle();
    expect(find.text('Search or ask Sal'), findsOneWidget);
    expect(find.text('Share with your friends'), findsNothing);

    _nav(tester).pop();
    await tester.pumpAndSettle();
    expect(find.text('Share with your friends'), findsOneWidget);
  });

  testWidgets(
      'a popped market page drops its context: the stack is empty and the '
      'bar is the home default, once, with no lift', (tester) async {
    kuteShellMounted.value = true;
    addTearDown(() => kuteShellMounted.value = false);
    final container = await _pump(tester);
    // On the tab root the one pill is the default.
    expect(find.text('Search or ask Sal'), findsOneWidget);

    await _push(tester, _page(barContext: _market), name: 'market');
    expect(find.text('Share with your friends'), findsOneWidget);
    expect(container.read(kuteBarContextProvider), hasLength(1));
    final lifted = tester.getRect(find.byType(KuteSalPill)).bottom;

    _nav(tester).pop();
    await tester.pumpAndSettle();
    expect(container.read(kuteBarContextProvider), isEmpty);
    expect(find.text('Share with your friends'), findsNothing);
    expect(find.text('Search or ask Sal'), findsOneWidget);
    expect(find.byType(KuteSalPill), findsOneWidget);
    expect(_up(tester), isTrue);
    // Back at the foot: no lift kept from the popped page.
    final rest = tester.getRect(find.byType(KuteSalPill)).bottom;
    expect(rest - lifted, moreOrLessEquals(80, epsilon: 1));
  });

  testWidgets('a declared action row lifts the bar above it',
      (tester) async {
    await _pump(tester);
    await _push(tester, _page(), name: 'settings');
    final rest = tester.getRect(find.byType(KuteSalPill)).bottom;
    _nav(tester).pop();
    await tester.pumpAndSettle();

    await _push(tester, _page(barContext: _market), name: 'market');
    final lifted = tester.getRect(find.byType(KuteSalPill)).bottom;
    expect(rest - lifted, moreOrLessEquals(80, epsilon: 1));
  });

  testWidgets(
      'a market page: scrolling down folds the pill into the circle at the '
      'right; still for 600 ms, or scrolling up, opens it again',
      (tester) async {
    await _pump(tester);
    await _push(tester, _page(barContext: _market), name: 'market');
    final full = tester.getRect(find.byType(KuteSalPill));
    expect(full.width, greaterThan(KuteSalPill.collapsedSize + 40));
    expect(find.text('Share with your friends'), findsOneWidget);

    // Reading down: the content moves up. One frame starts the fold, the
    // springs are through 450 ms later.
    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    final folded = tester.getRect(find.byType(KuteSalPill));
    expect(folded.width, moreOrLessEquals(KuteSalPill.collapsedSize, epsilon: 1));
    expect(folded.height, moreOrLessEquals(KuteSalPill.collapsedSize, epsilon: 1));
    // Docked at the right edge, where the full pill ended.
    expect(folded.right, moreOrLessEquals(full.right, epsilon: 1));
    expect(folded.center.dx, greaterThan(full.center.dx + 100));
    expect(find.text('Share with your friends'), findsNothing);

    // Still for the idle time: back to the full centred pill.
    await tester.pump(kBarScrollIdle);
    await tester.pumpAndSettle();
    final back = tester.getRect(find.byType(KuteSalPill));
    expect(back.width, moreOrLessEquals(full.width, epsilon: 1));
    expect(back.center.dx, moreOrLessEquals(full.center.dx, epsilon: 1));
    expect(find.text('Share with your friends'), findsOneWidget);

    // Down again, then up before the idle time: open at once.
    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(tester.getRect(find.byType(KuteSalPill)).width,
        moreOrLessEquals(KuteSalPill.collapsedSize, epsilon: 1));
    await tester.drag(find.byType(ListView), const Offset(0, 120));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(tester.getRect(find.byType(KuteSalPill)).width,
        moreOrLessEquals(full.width, epsilon: 1));
  });

  testWidgets('a page without a market context never folds',
      (tester) async {
    await _pump(tester);
    await _push(tester, _page(), name: 'settings');
    final full = tester.getRect(find.byType(KuteSalPill));
    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(tester.getRect(find.byType(KuteSalPill)).width,
        moreOrLessEquals(full.width, epsilon: 1));
  });

  testWidgets('Reduce Motion: the full pill stays, above the row',
      (tester) async {
    await _pump(tester, reduce: true);
    await _push(tester, _page(), name: 'settings');
    final rest = tester.getRect(find.byType(KuteSalPill)).bottom;
    _nav(tester).pop();
    await tester.pumpAndSettle();
    await _push(tester, _page(barContext: _market), name: 'market');
    final full = tester.getRect(find.byType(KuteSalPill));
    expect(rest - full.bottom, moreOrLessEquals(80, epsilon: 1));
    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(tester.getRect(find.byType(KuteSalPill)).width,
        moreOrLessEquals(full.width, epsilon: 1));
    expect(find.text('Share with your friends'), findsOneWidget);
  });

  testWidgets('the folded circle is 52 and still takes the tap',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var taps = 0;
    await tester.pumpWidget(ProviderScope(
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          theme: ThemeData(extensions: [AppColorsExtension.light()]),
          home: Scaffold(
            body: Center(
              child: KuteSalPill(
                label: 'Share with your friends',
                clip: 'share',
                collapsed: true,
                onTap: () => taps++,
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.byType(KuteSalPill));
    expect(rect.width, moreOrLessEquals(KuteSalPill.collapsedSize, epsilon: 1));
    expect(rect.height, moreOrLessEquals(KuteSalPill.collapsedSize, epsilon: 1));
    expect(find.text('Share with your friends'), findsNothing);
    await tester.tap(find.byType(KuteSalPill));
    expect(taps, 1);
  });

  test('which routes the bar shows over', () {
    expect(
        KuteBarRouteObserver.counts(MaterialPageRoute<void>(
            settings: const RouteSettings(name: 'settings'),
            builder: (_) => const SizedBox())),
        isTrue);
    expect(
        KuteBarRouteObserver.counts(MaterialPageRoute<void>(
            settings: const RouteSettings(name: 'open_pin'),
            builder: (_) => const SizedBox())),
        isFalse);
    // The router's tab shell and the tab roots: NoTransitionPages.
    expect(
        KuteBarRouteObserver.counts(const NoTransitionPage<void>(child: SizedBox())
            .createRoute(_FakeContext())),
        isFalse);
    // A pushed page whose GoRoute carries no name still counts.
    expect(
        KuteBarRouteObserver.counts(
            const MaterialPage<void>(child: SizedBox()).createRoute(_FakeContext())),
        isTrue);
    expect(
        KuteBarRouteObserver.counts(
            const MaterialPage<void>(name: 'camera', child: SizedBox())
                .createRoute(_FakeContext())),
        isTrue);
    expect(
        KuteBarRouteObserver.counts(
            const MaterialPage<void>(name: 'home', child: SizedBox())
                .createRoute(_FakeContext())),
        isFalse);
  });
}

/// A page's route needs no real context to be created.
class _FakeContext extends Fake implements BuildContext {}
