// A standing order's Sal toasts (standing_order_toasts.dart) with the
// app's shell mounted as the app mounts it (standing_orders_shell.dart,
// beside the navigator). The shell never puts anything up while the order
// is on its way; the slip, once left, puts up Sal's placing toast
// (founder, 10 November 2026, on 2.2.0 (99): "on the top when we close it
// we should say investment or prediction is placing ... but we can swipe
// it away or close it"): Sal and the words, no spinner, no clock, no
// Cancel; closable and swipable, the order unaffected; replaced in place
// by Sal's result toast once it ends: placed (the one success haptic),
// not placed, cancelled. Predictions and Investing alike.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/helpers/root_navigator.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/polymarket_model.dart' show PolymarketOutcome;
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/auth_provider.dart' show sessionUnlockedProvider;
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/shared/sal_reactions.dart';
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/screens/shared/sal_toast.dart';
import 'package:kute/screens/shared/standing_order_slips.dart';
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
    StandingOrderToasts.debugReset();
    StandingOrderSlips.debugReset();
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
      'the shell alone shows nothing while the order is on its way: no '
      'toast, no spinner, at any step', (tester) async {
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
      'cancelled (the provider\'s own cancel; the person has none): '
      'standing_order_cancelled once and '
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
  /// The slip left while its order is on its way (bet_slip_sheet.dart,
  /// order_slip_sheet.dart `_onLeave`): it hands over its reopen
  /// ([StandingOrderSlips.remember]) and puts up the placing toast.
  void left(StandingOrder order, VoidCallback? reopen) {
    if (reopen != null) {
      StandingOrderSlips.remember(
          venue: order.venue,
          marketKey: order.marketKey,
          orderId: order.id,
          open: (_, __) async => reopen());
    }
    StandingOrderToasts.placing(
        kuteRootNavigatorKey.currentContext,
        lookupAppLocalizations(const Locale('en')),
        venue: order.venue,
        marketKey: order.marketKey,
        marketTitle: order.marketTitle,
        order: order);
  }

  Future<void> leave(WidgetTester tester, StandingOrder order,
      {VoidCallback? reopen}) async {
    left(order, reopen);
    await tester.pump();
    await tester.pump(_arrive);
  }

  void expectPlacing(WidgetTester tester, String message) {
    expect(find.byKey(_toast), findsOneWidget);
    expect(find.text(message), findsOneWidget);
    // Sal and the words: nothing thinking, no Cancel; the X closes it.
    expect(shown(tester).tone, SalToastTone.info);
    expect(find.byKey(const ValueKey('sal-toast-mark')), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byKey(_action), findsNothing);
    expect(find.text('Cancel'), findsNothing);
    expect(find.byKey(_close), findsOneWidget);
    expect(tester.getSize(find.byKey(_close)), const Size(44, 44));
  }

  testWidgets(
      'left on its way: "Placing your prediction" at the top, Sal and the '
      'words only; it stays through every step and becomes "Prediction '
      'placed" in place, with the one success haptic', (tester) async {
    var beats = 0;
    SalToast.debugSuccessFeedbackOverride = () async => beats++;
    final c = await pump(tester);
    final order = _prediction();
    await running(tester, c, order);
    await leave(tester, order);
    expectPlacing(tester, 'Placing your prediction');
    expect(find.text('Will it rain tomorrow?'), findsOneWidget);
    expect(beats, 0);
    for (final state in [
      StandingOrderState.funded,
      StandingOrderState.posting,
      StandingOrderState.posted,
    ]) {
      await moveTo(tester, c, order, state);
      await tester.pump(const Duration(seconds: 5));
      expectPlacing(tester, 'Placing your prediction');
    }
    await c
        .read(standingOrdersProvider.notifier)
        .advance('so_p', StandingOrderState.filled);
    await tester.pump();
    // In place: one toast, never a second arriving under a leaving one.
    expect(find.byType(SalToast), findsOneWidget);
    await tester.pump(_arrive);
    expect(find.text('Prediction placed'), findsOneWidget);
    expect(find.text('Placing your prediction'), findsNothing);
    expect(shown(tester).tone, SalToastTone.success);
    expect(beats, 1);
    await drain(tester);
    expect(find.byKey(_toast), findsNothing);
    expect(beats, 1);
  });

  testWidgets(
      'closed with the X or swiped away any time: the order goes on, the '
      'placing toast does not come back, and Sal still says how it ended',
      (tester) async {
    final c = await pump(tester);
    final order = _prediction();
    await running(tester, c, order);
    await leave(tester, order);
    await tester.tap(find.byKey(_close));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(_toast), findsNothing);
    expect(c.read(standingOrdersProvider).single.state,
        StandingOrderState.funding);
    expect(named('standing_order_cancelled'), isEmpty);
    await moveTo(tester, c, order, StandingOrderState.posting);
    expect(find.byKey(_toast), findsNothing);

    // Swiped up instead.
    await leave(tester, order.copyWith(state: StandingOrderState.posting));
    await tester.drag(find.byKey(_toast), const Offset(0, -80));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(_toast), findsNothing);
    await moveTo(tester, c, order, StandingOrderState.posted);
    expect(find.byKey(_toast), findsNothing);
    expect(c.read(standingOrdersProvider).single.state,
        StandingOrderState.posted);

    await c
        .read(standingOrdersProvider.notifier)
        .advance('so_p', StandingOrderState.failed, failureCode: 'x');
    await tester.pump();
    await tester.pump(_arrive);
    expect(shown(tester).tone, SalToastTone.failure);
    await drain(tester);
  });

  testWidgets(
      'Investing: "Placing your investment"; a cancel (the provider\'s own) '
      'turns it into the cancelled toast in place', (tester) async {
    final c = await pump(tester);
    final order = _investing(state: StandingOrderState.funded);
    await running(tester, c, order);
    await leave(tester, order);
    expectPlacing(tester, 'Placing your investment');
    expect(find.text('BTC · Perp'), findsOneWidget);
    await c.read(standingOrdersProvider.notifier).cancel('so_i');
    await tester.pump();
    expect(find.byType(SalToast), findsOneWidget);
    await tester.pump(_arrive);
    expect(find.text('Placing your investment'), findsNothing);
    expect(find.text('Cancelled. The money stays in Investing, available.'),
        findsOneWidget);
    await drain(tester);
    expect(find.byKey(_toast), findsNothing);
  });

  testWidgets(
      'an order that ends with no result toast of its own (the person '
      'acted on it) takes the placing toast with it', (tester) async {
    final c = await pump(tester);
    final order = _prediction(state: StandingOrderState.posted);
    await running(tester, c, order);
    await leave(tester, order);
    expect(find.byKey(_toast), findsOneWidget);
    await c.read(standingOrdersProvider.notifier).advance(
        'so_p', StandingOrderState.failed,
        failureCode: 'price_moved', quiet: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(_toast), findsNothing);
    await drain(tester);
  });

  testWidgets(
      'a tap on the placing toast opens the slip that was left (its reopen), '
      'never a journey sheet, no Cancel', (tester) async {
    final c = await pump(tester);
    final order = _prediction();
    await running(tester, c, order);
    var reopened = 0;
    await leave(tester, order, reopen: () => reopened++);
    await tester.tap(find.text('Placing your prediction'));
    await tester.pump();
    await tester.pump(_arrive);
    expect(reopened, 1);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Cancel'), findsNothing);
    expect(find.byKey(_toast), findsNothing);
    await drain(tester);
  });

  testWidgets(
      'two orders on their way at once: ONE toast, the newest left one in '
      'place of the first (never two, never one arriving under a leaving '
      'one), its tap that order\'s; a result for either replaces it in '
      'place; once it goes nothing comes back for the one still placing',
      (tester) async {
    var beats = 0;
    SalToast.debugSuccessFeedbackOverride = () async => beats++;
    final c = await pump(tester);
    final bet = _prediction(state: StandingOrderState.posted);
    final buy = _investing(state: StandingOrderState.posted);
    c.read(standingOrdersProvider.notifier).debugReplace([bet, buy]);
    await tester.pump();
    final taps = <String>[];
    await leave(tester, bet, reopen: () => taps.add('bet'));
    expectPlacing(tester, 'Placing your prediction');
    // The second order's slip left: in place, one toast at every frame.
    left(buy, () => taps.add('buy'));
    await tester.pump();
    expect(find.byType(SalToast), findsOneWidget);
    await tester.pump(_arrive);
    expect(find.byType(SalToast), findsOneWidget);
    expectPlacing(tester, 'Placing your investment');
    expect(find.text('Placing your prediction'), findsNothing);
    expect(StandingOrderToasts.isAbout(buy.venue, buy.marketKey), isTrue);
    expect(StandingOrderToasts.isPlacing(bet), isFalse);
    expect(StandingOrderToasts.isPlacing(buy), isTrue);
    // The bet ending quietly (the person acted on it) leaves the toast,
    // which is about the investment, alone.
    StandingOrderToasts.endQuietly(bet);
    await tester.pump(const Duration(milliseconds: 400));
    expectPlacing(tester, 'Placing your investment');
    await tester.tap(find.text('Placing your investment'));
    await tester.pump();
    await tester.pump(_arrive);
    expect(taps, ['buy']);
    expect(find.byKey(_toast), findsNothing);

    // Both left again; the bet fills: its result in place of the
    // investment's placing toast, one toast, the one success haptic.
    await leave(tester, bet, reopen: () => taps.add('bet'));
    left(buy, () => taps.add('buy'));
    await tester.pump();
    await tester.pump(_arrive);
    expectPlacing(tester, 'Placing your investment');
    await c
        .read(standingOrdersProvider.notifier)
        .advance('so_p', StandingOrderState.filled);
    await tester.pump();
    expect(find.byType(SalToast), findsOneWidget);
    await tester.pump(_arrive);
    expect(find.byType(SalToast), findsOneWidget);
    expect(find.text('Prediction placed'), findsOneWidget);
    expect(find.text('Placing your investment'), findsNothing);
    expect(beats, 1);
    // The investment fills before the bet's result has gone: in place
    // again, the same tone, so not felt twice.
    await c
        .read(standingOrdersProvider.notifier)
        .advance('so_i', StandingOrderState.filled);
    await tester.pump();
    expect(find.byType(SalToast), findsOneWidget);
    await tester.pump(_arrive);
    expect(find.text('Order placed'), findsOneWidget);
    expect(find.byType(SalToast), findsOneWidget);
    expect(beats, 1);
    await drain(tester);
    expect(find.byKey(_toast), findsNothing);
    expect(beats, 1);
  });

  testWidgets(
      'a result while another order is still placing: in place; once it has '
      'gone, nothing is put back up for the one still on its way',
      (tester) async {
    final c = await pump(tester);
    final bet = _prediction(state: StandingOrderState.posting);
    final buy = _investing();
    c.read(standingOrdersProvider.notifier).debugReplace([bet, buy]);
    await tester.pump();
    await leave(tester, buy);
    expectPlacing(tester, 'Placing your investment');
    await c
        .read(standingOrdersProvider.notifier)
        .advance('so_p', StandingOrderState.failed, failureCode: 'x');
    await tester.pump();
    expect(find.byType(SalToast), findsOneWidget);
    await tester.pump(_arrive);
    expect(shown(tester).tone, SalToastTone.failure);
    expect(find.text('Placing your investment'), findsNothing);
    await drain(tester);
    expect(find.byKey(_toast), findsNothing);
    // The investment still on its way: nothing extra.
    expect(c.read(standingOrdersProvider.notifier).byId('so_i')!.isOpen,
        isTrue);
    await tester.pump(const Duration(seconds: 10));
    expect(find.byKey(_toast), findsNothing);
    await drain(tester);
  });

  testWidgets(
      'the price moved past the approval: Sal says the new price, its tap '
      'the approval; no Cancel, the X puts it away and the order is left '
      'as it is', (tester) async {
    final c = await pump(tester);
    await running(tester, c, _prediction(state: StandingOrderState.posting));
    await c.read(standingOrdersProvider.notifier)
        .needsApproval('so_p', priceNow: 0.81);
    await tester.pump();
    await tester.pump(_arrive);
    expect(find.textContaining('81%'), findsOneWidget);
    expect(shown(tester).tone, SalToastTone.pending);
    expect(shown(tester).onTap, isNotNull);
    expect(find.byKey(_action), findsNothing);
    expect(find.text('Cancel'), findsNothing);
    await tester.tap(find.byKey(_close));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(_toast), findsNothing);
    expect(c.read(standingOrdersProvider).single.state,
        StandingOrderState.needsApproval);
    expect(named('standing_order_cancelled'), isEmpty);
    await drain(tester);
  });

  testWidgets(
      'an order that already ended: placed or not placed with no stop on its '
      'slip, a tap opens nothing (never a journey sheet), not even the '
      'slip it was left on', (tester) async {
    final c = await pump(tester);
    var opened = 0;
    final order = _prediction();
    await running(tester, c, order);
    StandingOrderSlips.remember(
        venue: order.venue,
        marketKey: order.marketKey,
        orderId: order.id,
        open: (_, __) async => opened++);
    await moveTo(tester, c, order, StandingOrderState.posted);
    await c
        .read(standingOrdersProvider.notifier)
        .advance('so_p', StandingOrderState.failed, failureCode: 'x');
    await tester.pump();
    await tester.pump(_arrive);
    // The failed toast's tap: no stop on the slip, nothing opens.
    await tester.tap(find.textContaining("Your prediction wasn't placed"));
    await tester.pump();
    await tester.pump(_arrive);
    expect(opened, 0);
    expect(find.byType(BottomSheet), findsNothing);
    await StandingOrderSlips.reopen(kuteRootNavigatorKey.currentContext,
        id: 'so_p');
    await tester.pump();
    expect(opened, 0);
    await drain(tester);
  });

  test('the outcome an order\'s token is: its own token, else a No', () {
    const outcomes = [
      PolymarketOutcome(name: 'Yes', price: 0.4, tokenId: 'y'),
      PolymarketOutcome(name: 'No', price: 0.6, tokenId: 'n'),
      PolymarketOutcome(
          name: 'Ana', price: 0.3, tokenId: 'ana-yes', noTokenId: 'ana-no'),
    ];
    expect(StandingOrderSlips.pickOf(outcomes, 'y'), (index: 0, buyNo: false));
    expect(StandingOrderSlips.pickOf(outcomes, 'n'), (index: 1, buyNo: false));
    expect(StandingOrderSlips.pickOf(outcomes, 'ana-yes'),
        (index: 2, buyNo: false));
    expect(StandingOrderSlips.pickOf(outcomes, 'ana-no'),
        (index: 2, buyNo: true));
    expect(StandingOrderSlips.pickOf(outcomes, 'gone'), isNull);
  });
}
