// test/screens/home/components/move_sent_bar_test.dart
//
// The bar on a result sheet closed over a tab that holds a bar context of
// its own (founder, 8 November 2026: "swapped should say ok, not with the
// search sal"; kute_bar_context.dart, A TAB UNDER THE ROOT NAVIGATOR). The
// app's layering in miniature: a tab's navigator nested in the root's, the
// tab's page holding its context only while its tickers run, as the
// Dollars home does (usd_account_screen.dart). An opaque page over the tab
// parks it; popped in the same tick the result sheet is pushed, the tab
// wakes and pushes its context AFTER the sheet's. The bar must stay the
// sheet's button.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/screens/home/components/move_sent_overlay.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/theme/app_theme.dart';

import '../../../helpers/kute_bar_test_support.dart';

const _tabLabel = 'Search investments or Manage with AI';
final _root = GlobalKey<NavigatorState>();
final _tab = GlobalKey<NavigatorState>();

/// The Dollars home's scope (usd_account_screen.dart) in miniature.
class _TabPage extends StatelessWidget {
  const _TabPage(this.barContext);

  final KuteBarContext barContext;

  @override
  Widget build(BuildContext context) => KuteBarContextScope(
        active: TickerMode.valuesOf(context).enabled,
        barContext: barContext,
        child: const Scaffold(body: Text('dollars home')),
      );
}

Future<ProviderContainer> _pump(WidgetTester tester,
    {KuteBarContext barContext = const KuteBarContext(label: _tabLabel)}) async {
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
        theme: buildLightTheme().copyWith(splashFactory: NoSplash.splashFactory),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        navigatorKey: _root,
        navigatorObservers: [KuteBarRouteObserver()],
        builder: withKuteShellBar,
        home: Navigator(
          key: _tab,
          observers: [KuteBarRouteObserver()],
          onGenerateRoute: (_) => PageRouteBuilder<void>(
            pageBuilder: (_, __, ___) => _TabPage(barContext),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return container;
}

/// Swap, an opaque page on the root navigator over the tab, its button the
/// bar; settled, so the tab under it is parked.
Future<void> _openSwap(WidgetTester tester) async {
  _root.currentState!.push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => KuteBarContextScope(
      barContext: KuteBarContext.primary(
          label: 'Swap', onPrimary: () {}, disabledLabel: null),
      child: const Scaffold(body: Text('swap screen')),
    ),
  ));
  await tester.pumpAndSettle();
  expect(kuteBarPrimaryWithText('Swap'), findsOneWidget);
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    KuteBarRouteObserver.reset();
    KuteConfirmation.debugFeedbackOverride = () async {};
    KuteConfirmation.debugFailureFeedbackOverride = () async {};
  });
  tearDown(() {
    KuteConfirmation.debugFeedbackOverride = null;
    KuteConfirmation.debugFailureFeedbackOverride = null;
  });

  for (final swapped in [true, false]) {
    testWidgets(
        '${swapped ? 'Swapped' : 'Moved'} over the Dollars home: the bar is '
        'Done and closes the sheet', (tester) async {
      await _pump(tester);
      expect(find.text(_tabLabel), findsOneWidget);
      await _openSwap(tester);

      final navigator = _root.currentState!;
      navigator.pop();
      pushMoveSentOverlay(
        navigator: navigator,
        amount: r'$4.99',
        fromWalletName: 'Bitcoin',
        toWalletName: 'Dollars',
        note: 'Sent. Registering your transfer.',
        swapped: swapped,
      );
      await tester.pumpAndSettle();

      expect(
          find.text(swapped ? 'Swapped to Dollars' : 'Moved to Dollars'),
          findsOneWidget);
      expect(kuteBarPrimaryWithText('Done'), findsOneWidget);
      expect(find.text(_tabLabel), findsNothing);

      await tester.tap(kuteBarPrimaryWithText('Done'));
      await tester.pumpAndSettle();
      expect(find.byType(KuteConfirmation), findsNothing);
      expect(find.text('dollars home'), findsOneWidget);
      // Back on the tab, the tab's own context.
      expect(find.text(_tabLabel), findsOneWidget);
    });
  }

  testWidgets('the real router: a branch of the shell, the sheet on the root',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final root = GlobalKey<NavigatorState>();
    final router = GoRouter(
      navigatorKey: root,
      initialLocation: '/usd',
      observers: [KuteBarRouteObserver()],
      routes: [
        StatefulShellRoute.indexedStack(
          pageBuilder: (_, state, shell) =>
              NoTransitionPage<void>(key: state.pageKey, child: shell),
          branches: [
            StatefulShellBranch(
              observers: [KuteBarRouteObserver()],
              routes: [
                GoRoute(
                  path: '/usd',
                  name: 'usd',
                  pageBuilder: (_, state) => NoTransitionPage<void>(
                    key: state.pageKey,
                    child: const _TabPage(KuteBarContext(label: _tabLabel)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [aiEnabledProvider.overrideWith((_) async => true)],
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp.router(
          routerConfig: router,
          theme:
              buildLightTheme().copyWith(splashFactory: NoSplash.splashFactory),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: withKuteShellBar,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text(_tabLabel), findsOneWidget);

    final navigator = root.currentState!;
    navigator.push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => KuteBarContextScope(
        barContext: KuteBarContext.primary(
            label: 'Swap', onPrimary: () {}, disabledLabel: null),
        child: const Scaffold(body: Text('swap screen')),
      ),
    ));
    await tester.pumpAndSettle();
    expect(kuteBarPrimaryWithText('Swap'), findsOneWidget);

    navigator.pop();
    pushMoveSentOverlay(
      navigator: navigator,
      amount: r'$4.99',
      fromWalletName: 'Bitcoin',
      toWalletName: 'Dollars',
      swapped: true,
    );
    await tester.pumpAndSettle();
    expect(kuteBarPrimaryWithText('Done'), findsOneWidget);
    expect(find.text(_tabLabel), findsNothing);

    await tester.tap(kuteBarPrimaryWithText('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(KuteConfirmation), findsNothing);
    expect(find.text(_tabLabel), findsOneWidget);
  });

  testWidgets(
      "a tab whose context is a primary button: the sheet's Done, and the "
      "tab's action does not run", (tester) async {
    var portfolio = 0;
    await _pump(tester,
        barContext: KuteBarContext.primary(
            label: 'See full portfolio and activity',
            onPrimary: () => portfolio++,
            disabledLabel: null));
    await _openSwap(tester);

    final navigator = _root.currentState!;
    navigator.pop();
    pushMoveSentOverlay(
      navigator: navigator,
      amount: r'$4.99',
      fromWalletName: 'Bitcoin',
      toWalletName: 'Dollars',
      swapped: true,
    );
    await tester.pumpAndSettle();

    expect(kuteBarPrimaryWithText('Done'), findsOneWidget);
    await tester.tap(kuteBarPrimaryWithText('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(KuteConfirmation), findsNothing);
    expect(portfolio, 0);
    expect(kuteBarPrimaryWithText('See full portfolio and activity'),
        findsOneWidget);
  });

  testWidgets('a failure result with its own button keeps that button',
      (tester) async {
    await _pump(tester);
    await _openSwap(tester);

    final navigator = _root.currentState!;
    navigator.pop();
    pushKuteSuccessOverlay(
      navigator: navigator,
      overlay: KuteConfirmation(
        message: "Couldn't send",
        success: false,
        buttonText: 'Try again',
        onDone: navigator.pop,
      ),
    );
    await tester.pumpAndSettle();

    expect(kuteBarPrimaryWithText('Try again'), findsOneWidget);
    expect(find.text(_tabLabel), findsNothing);
  });

  testWidgets(
      "a sheet with no context over the tab reads the default, not the tab's",
      (tester) async {
    await _pump(tester);
    _root.currentState!.push(ModalBottomSheetRoute<void>(
      isScrollControlled: false,
      builder: (_) => const SizedBox(height: 200, child: Text('a sheet')),
    ));
    await tester.pumpAndSettle();

    expect(find.text('a sheet'), findsOneWidget);
    expect(find.text(_tabLabel), findsNothing);
    expect(find.text('Search or Manage with AI'), findsOneWidget);

    _root.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text(_tabLabel), findsOneWidget);
  });

  testWidgets(
      "popping the page with nothing pushed over it: the tab's context is "
      'back', (tester) async {
    await _pump(tester);
    await _openSwap(tester);
    _root.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text(_tabLabel), findsOneWidget);
    expect(kuteBarPrimary, findsNothing);
  });
}
