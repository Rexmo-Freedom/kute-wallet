// A standing order's Sal toasts (standing_order_toasts.dart) with the
// app's shell mounted as the app mounts it (standing_orders_shell.dart,
// beside the navigator): nothing while the order is on its way (founder,
// 10 November 2026, on 2.2.0 (98): no "thinking" placing indicator once
// the slip is gone), and Sal's result toast once it ends: placed (the one
// success haptic), not placed, cancelled. Predictions and Investing alike.

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

  /// The order on record, as the accept leaves it once the slip is gone.
  Future<void> running(
      WidgetTester tester, ProviderContainer c, StandingOrder order) async {
    c.read(standingOrdersProvider.notifier).debugReplace([order]);
    await tester.pump();
    await tester.pump(_arrive);
  }

  SalToast shown(WidgetTester tester) =>
      tester.widget<SalToast>(find.byType(SalToast));

  Future<void> drain(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  /// Moves the order on, as the venue's answers do.
  Future<void> moveTo(WidgetTester tester, ProviderContainer c,
      StandingOrder order, StandingOrderState state) async {
    c.read(standingOrdersProvider.notifier)
        .debugReplace([order.copyWith(state: state)]);
    await tester.pump();
    await tester.pump(_arrive);
  }

  testWidgets(
      'while the order is on its way nothing shows: no placing toast, no '
      'spinner, at any step (founder, 10 November 2026)', (tester) async {
    final c = await pump(tester);
    final order = _prediction();
    await running(tester, c, order);
    for (final state in [
      StandingOrderState.funding,
      StandingOrderState.funded,
      StandingOrderState.posting,
      StandingOrderState.posted,
    ]) {
      await moveTo(tester, c, order, state);
      expect(find.byKey(_toast), findsNothing, reason: state.name);
      expect(find.text('Placing your prediction'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    }
    await drain(tester);
  });

  testWidgets(
      'it fills: Sal\'s result toast "Prediction placed", with the one '
      'success haptic, and it goes by itself', (tester) async {
    var beats = 0;
    SalToast.debugSuccessFeedbackOverride = () async => beats++;
    final c = await pump(tester);
    await running(tester, c, _prediction(state: StandingOrderState.posted));
    expect(find.byKey(_toast), findsNothing);
    await c
        .read(standingOrdersProvider.notifier)
        .advance('so_p', StandingOrderState.filled);
    await tester.pump();
    await tester.pump(_arrive);
    expect(find.text('Prediction placed'), findsOneWidget);
    expect(find.text('Will it rain tomorrow?'), findsOneWidget);
    expect(shown(tester).tone, SalToastTone.success);
    expect(find.byKey(_close), findsNothing);
    expect(find.byKey(_action), findsNothing);
    expect(beats, 1);
    await drain(tester);
    expect(find.byKey(_toast), findsNothing);
    expect(beats, 1);
  });

  testWidgets('it fails: Sal says the money is in Predictions',
      (tester) async {
    final c = await pump(tester);
    await running(tester, c, _prediction(state: StandingOrderState.posting));
    await c
        .read(standingOrdersProvider.notifier)
        .advance('so_p', StandingOrderState.failed, failureCode: 'x');
    await tester.pump();
    await tester.pump(_arrive);
    expect(shown(tester).tone, SalToastTone.failure);
    expect(find.textContaining("Your prediction wasn't placed"), findsOneWidget);
    await drain(tester);
  });

  testWidgets(
      'cancelled (from its journey): standing_order_cancelled once and '
      'Sal says the money stays in Predictions', (tester) async {
    final c = await pump(tester);
    await running(tester, c, _prediction(state: StandingOrderState.funded));
    await c.read(standingOrdersProvider.notifier).cancel('so_p');
    await tester.pump();
    await tester.pump(_arrive);
    expect(c.read(standingOrdersProvider).single.state,
        StandingOrderState.cancelled);
    final cancelled = named('standing_order_cancelled');
    expect(cancelled, hasLength(1));
    expect(cancelled.single.$2!['venue'], 'polymarket');
    expect(cancelled.single.$2!['stage'], 'funded');
    expect(find.byType(SalToast), findsOneWidget);
    expect(find.text('Cancelled. The money stays in Predictions, available.'),
        findsOneWidget);
    expect(find.byKey(_action), findsNothing);
    await drain(tester);
    expect(find.byKey(_toast), findsNothing);
  });

  testWidgets(
      'Investing the same: nothing on its way; "Order placed" once it fills; '
      'a cancel says the money stays in Investing', (tester) async {
    final c = await pump(tester);
    final order = _investing(state: StandingOrderState.funded);
    await running(tester, c, order);
    await moveTo(tester, c, order, StandingOrderState.posting);
    expect(find.byKey(_toast), findsNothing);
    expect(find.text('Placing your order'), findsNothing);
    await c
        .read(standingOrdersProvider.notifier)
        .advance('so_i', StandingOrderState.filled);
    await tester.pump();
    await tester.pump(_arrive);
    expect(find.text('Order placed'), findsOneWidget);
    await drain(tester);

    await running(tester, c, _investing());
    await c.read(standingOrdersProvider.notifier).cancel('so_i');
    await tester.pump();
    await tester.pump(_arrive);
    expect(named('standing_order_cancelled').single.$2!['venue'],
        'hyperliquid');
    expect(find.text('Cancelled. The money stays in Investing, available.'),
        findsOneWidget);
    await drain(tester);
  });
}
