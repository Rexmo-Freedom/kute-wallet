// A standing order's Sal toasts (standing_order_toasts.dart) with the
// app's shell mounted as the app mounts it (standing_orders_shell.dart,
// beside the navigator): the placing toast with Cancel and the X (founder,
// 9 November 2026: "Placing your prediction / cancel should be Sal. Also
// give it an X to close it"), what the X does and does not do, Cancel
// before the order is posted and gone after, and the toast turning into
// the result in place. Predictions and Investing alike.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/helpers/root_navigator.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/auth_provider.dart' show sessionUnlockedProvider;
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/shared/sal_reactions.dart';
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/screens/shared/sal_toast.dart';
import 'package:kute/screens/shared/standing_order_journey.dart';
import 'package:kute/screens/shared/standing_order_toasts.dart';
import 'package:kute/screens/shared/standing_orders_shell.dart';
import 'package:kute/services/standing_orders/standing_order_store.dart';
import 'package:kute/services/standing_orders/standing_orders_provider.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/portfolio_overrides.dart';
import '../../services/standing_orders/fake_secret_store.dart';

const _toast = ValueKey('sal-toast');
const _action = ValueKey('sal-toast-action');
const _close = ValueKey('sal-toast-close');
const _arrive = Duration(milliseconds: 450);
const _leave = Duration(milliseconds: 300);

final _at = DateTime(2026, 11, 9, 12);

StandingOrder _prediction(
        {StandingOrderState state = StandingOrderState.funding}) =>
    StandingOrder(
      id: 'so_p',
      walletId: 'w1',
      venue: StandingOrderVenue.predictions,
      marketKey: '111',
      marketTitle: 'Will it rain tomorrow?',
      sideLabel: 'Yes',
      isBuy: true,
      size: 19.23,
      approvedPrice: 0.52,
      amountUsd: 10,
      orderKind: 'market',
      state: state,
      createdAt: _at,
      updatedAt: _at,
      fundUsd: 10.3,
    );

StandingOrder _investing(
        {StandingOrderState state = StandingOrderState.funding}) =>
    StandingOrder(
      id: 'so_i',
      walletId: 'w1',
      venue: StandingOrderVenue.investing,
      marketKey: 'BTC',
      marketTitle: 'BTC · Perp',
      sideLabel: 'long',
      isBuy: true,
      size: 20,
      approvedPrice: 60000,
      amountUsd: 20,
      orderKind: 'market',
      state: state,
      createdAt: _at,
      updatedAt: _at,
      leverage: 2,
      marketKind: 'perp',
    );

/// The store without Hive: nothing persisted, so nothing waits on real
/// I/O in the test's fake time.
class _MemoryStore extends StandingOrderStore {
  _MemoryStore() : super(secrets: FakeSecretStore(), boxName: 'unused');

  @override
  Future<List<StandingOrder>> load(String walletId) async => const [];
  @override
  Future<void> save(StandingOrder order) async {}
  @override
  Future<void> remove(StandingOrder order) async {}
}

void main() {
  late StandingOrderStore store;
  late List<(String, Map<String, Object?>?)> events;

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    store = _MemoryStore();
    events = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    SalToast.debugSuccessFeedbackOverride = () async {};
    SalToast.debugFailureFeedbackOverride = () async {};
    SalReactions.debugReset();
  });

  tearDown(() {
    TrackingService.debugTrackObserver = null;
    SalToast.debugReset();
    SalToast.debugSuccessFeedbackOverride = null;
    SalToast.debugFailureFeedbackOverride = null;
    SalReactions.debugReset();
  });

  List<(String, Map<String, Object?>?)> named(String name) =>
      [for (final e in events) if (e.$1 == name) e];

  /// The app's shape: the root navigator under its key and the shell
  /// beside it in the builder's Stack (app_widget.dart).
  Future<ProviderContainer> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SalSpriteCache.debugSetManifest(null);
    addTearDown(SalSpriteCache.debugReset);
    final container = ProviderContainer(overrides: [
      ...portfolioOverrides(),
      standingOrderStoreProvider.overrideWithValue(store),
      standingOrderWatchersProvider.overrideWithValue(
          StandingOrderWatchers(wakePredictions: () {}, wakeInvesting: () {})),
      sessionUnlockedProvider.overrideWithValue(false),
      settingsProvider.overrideWith((_) => SettingsModel(Settings(
          currency: 'USD',
          language: 'en',
          btcFormat: 'sats',
          backup: false,
          biometricsEnabled: false,
          bitcoinElectrumNode: '',
          nodeType: '',
          reviewDone: true,
          activeWalletId: 'w1',
          wallets: [WalletConfig(id: 'w1', name: 'Hot')]))),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          navigatorKey: kuteRootNavigatorKey,
          theme: ThemeData(
              splashFactory: NoSplash.splashFactory,
              extensions: [AppColorsExtension.light()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => Stack(children: [
            child!,
            const StandingOrdersShell(),
          ]),
          home: const Scaffold(body: SizedBox.expand()),
        ),
      ),
    ));
    await tester.pump();
    return container;
  }

  Future<AppLocalizations> l10n() =>
      AppLocalizations.delegate.load(const Locale('en'));

  /// The slip closed at the accept: Sal's placing toast.
  Future<void> placing(
      WidgetTester tester, ProviderContainer c, StandingOrder order) async {
    c.read(standingOrdersProvider.notifier).debugReplace([order]);
    StandingOrderToasts.placing(kuteRootContext(), c, await l10n(),
        venue: order.venue,
        marketKey: order.marketKey,
        marketTitle: order.marketTitle,
        order: order);
    await tester.pump();
    await tester.pump(_arrive);
  }

  SalToast shown(WidgetTester tester) =>
      tester.widget<SalToast>(find.byType(SalToast));

  /// The transition's futures, then the frames.
  Future<void> settleIo(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(_leave);
  }

  Future<void> drain(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  testWidgets(
      'placing: Sal\'s pending toast with Cancel and the X, which stays '
      'while the order runs', (tester) async {
    final c = await pump(tester);
    await placing(tester, c, _prediction());
    expect(find.text('Placing your prediction'), findsOneWidget);
    expect(find.text('Will it rain tomorrow?'), findsOneWidget);
    expect(shown(tester).tone, SalToastTone.pending);
    expect(find.descendant(of: find.byKey(_action), matching: find.text('Cancel')),
        findsOneWidget);
    expect(find.byKey(_close), findsOneWidget);
    // The X: 44 pt to hit, read "Close".
    expect(tester.getSize(find.byKey(_close)), const Size(44, 44));
    final handle = tester.ensureSemantics();
    expect(find.bySemanticsLabel('Close'), findsOneWidget);
    handle.dispose();
    // Sticky: still there long after a pending toast would have gone.
    await tester.pump(const Duration(seconds: 30));
    expect(find.byKey(_toast), findsOneWidget);
    await tester.tap(find.byKey(_close));
    await tester.pump();
    await tester.pump(_leave);
    await drain(tester);
  });

  testWidgets(
      'the X closes the toast only: the order goes on, nothing is '
      'cancelled, the toast stays closed as it moves, and its result '
      'still shows', (tester) async {
    final c = await pump(tester);
    await placing(tester, c, _prediction());
    await tester.tap(find.byKey(_close));
    await tester.pump();
    await tester.pump(_leave);
    expect(find.byKey(_toast), findsNothing);
    expect(c.read(standingOrdersProvider).single.state,
        StandingOrderState.funding);
    expect(named('standing_order_cancelled'), isEmpty);

    // It moves on: the closed toast does not come back.
    c.read(standingOrdersProvider.notifier)
        .debugReplace([_prediction(state: StandingOrderState.posting)]);
    await tester.pump();
    await tester.pump(_arrive);
    expect(find.byKey(_toast), findsNothing);

    // It fills: Sal says so.
    await c
        .read(standingOrdersProvider.notifier)
        .advance('so_p', StandingOrderState.filled);
    await tester.pump();
    await tester.pump(_arrive);
    expect(find.text('Prediction placed'), findsOneWidget);
    expect(shown(tester).tone, SalToastTone.success);
    await drain(tester);
  });

  testWidgets(
      'Cancel before the order is posted cancels it (standing_order_'
      'cancelled once) and the toast turns into "Cancelled" in place',
      (tester) async {
    final c = await pump(tester);
    await placing(tester, c, _prediction(state: StandingOrderState.funded));
    await tester.tap(find.byKey(_action));
    await settleIo(tester);
    expect(c.read(standingOrdersProvider).single.state,
        StandingOrderState.cancelled);
    final cancelled = named('standing_order_cancelled');
    expect(cancelled, hasLength(1));
    expect(cancelled.single.$2!['venue'], 'polymarket');
    expect(cancelled.single.$2!['stage'], 'funded');
    expect(find.byType(SalToast), findsOneWidget, reason: 'in place');
    expect(find.text('Cancelled. The money stays in Predictions, available.'),
        findsOneWidget);
    expect(find.byKey(_action), findsNothing);
    await drain(tester);
    expect(find.byKey(_toast), findsNothing);
  });

  testWidgets('once the order is posted, Cancel is gone; the X stays',
      (tester) async {
    final c = await pump(tester);
    await placing(tester, c, _prediction());
    expect(find.byKey(_action), findsOneWidget);
    c.read(standingOrdersProvider.notifier)
        .debugReplace([_prediction(state: StandingOrderState.posting)]);
    await tester.pump();
    expect(find.byType(SalToast), findsOneWidget);
    expect(find.text('Placing your prediction'), findsOneWidget);
    expect(find.byKey(_action), findsNothing);
    expect(find.byKey(_close), findsOneWidget);
    await tester.tap(find.byKey(_close));
    await tester.pump();
    await tester.pump(_leave);
    await drain(tester);
  });

  testWidgets('it fills: the placing toast turns into "Prediction placed"',
      (tester) async {
    final c = await pump(tester);
    await placing(tester, c, _prediction(state: StandingOrderState.posted));
    await c
        .read(standingOrdersProvider.notifier)
        .advance('so_p', StandingOrderState.filled);
    await tester.pump();
    expect(find.byType(SalToast), findsOneWidget, reason: 'in place');
    expect(find.text('Prediction placed'), findsOneWidget);
    expect(shown(tester).tone, SalToastTone.success);
    expect(find.byKey(_close), findsNothing);
    await drain(tester);
    expect(find.byKey(_toast), findsNothing);
  });

  testWidgets('it fails: Sal says the money is in Predictions',
      (tester) async {
    final c = await pump(tester);
    await placing(tester, c, _prediction(state: StandingOrderState.posting));
    await c
        .read(standingOrdersProvider.notifier)
        .advance('so_p', StandingOrderState.failed, failureCode: 'x');
    await tester.pump();
    expect(shown(tester).tone, SalToastTone.failure);
    expect(find.textContaining("Your prediction wasn't placed"), findsOneWidget);
    await drain(tester);
  });

  testWidgets('a tap on the placing toast opens the money journey',
      (tester) async {
    final c = await pump(tester);
    await placing(tester, c, _prediction());
    await tester.tap(find.text('Placing your prediction'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(StandingOrderJourneySheet), findsOneWidget);
    expect(c.read(standingOrdersProvider).single.state,
        StandingOrderState.funding);
    // The journey's walking Sal never settles: closed before the drain.
    kuteRootNavigatorKey.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await drain(tester);
  });

  testWidgets(
      'Investing the same: "Placing your order", the X, Cancel; Cancel says '
      'the money stays in Investing', (tester) async {
    final c = await pump(tester);
    await placing(tester, c, _investing());
    expect(find.text('Placing your order'), findsOneWidget);
    expect(find.text('BTC · Perp'), findsOneWidget);
    expect(find.byKey(_close), findsOneWidget);
    await tester.tap(find.byKey(_action));
    await settleIo(tester);
    expect(c.read(standingOrdersProvider).single.state,
        StandingOrderState.cancelled);
    expect(named('standing_order_cancelled').single.$2!['venue'],
        'hyperliquid');
    expect(find.text('Cancelled. The money stays in Investing, available.'),
        findsOneWidget);
    await drain(tester);
  });

  testWidgets('Investing: the X keeps the order; it fills and Sal says so',
      (tester) async {
    final c = await pump(tester);
    await placing(tester, c, _investing(state: StandingOrderState.funded));
    await tester.tap(find.byKey(_close));
    await tester.pump();
    await tester.pump(_leave);
    expect(find.byKey(_toast), findsNothing);
    expect(c.read(standingOrdersProvider).single.isOpen, isTrue);
    await c
        .read(standingOrdersProvider.notifier)
        .advance('so_i', StandingOrderState.posting);
    await c
        .read(standingOrdersProvider.notifier)
        .advance('so_i', StandingOrderState.filled);
    await tester.pump();
    await tester.pump(_arrive);
    expect(find.text('Order placed'), findsOneWidget);
    await drain(tester);
  });
}
