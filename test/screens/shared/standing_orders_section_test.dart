// The standing orders at the top of Activity: the venue's own row with
// the placing copy; a tap opens the order's own slip again, locked as it
// was left (standing_order_slips.dart), never a white journey sheet and
// never a Cancel (founder, 11 November 2026, on 2.2.0 (104)).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/portfolio/components/position_rows.dart'
    show PlacingBetRow;
import 'package:kute/screens/shared/standing_order_slips.dart';
import 'package:kute/screens/shared/standing_orders_section.dart';
import 'package:kute/services/standing_orders/standing_order_store.dart';
import 'package:kute/services/standing_orders/standing_orders_provider.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/portfolio_overrides.dart';
import '../../services/standing_orders/fake_secret_store.dart';

final _at = DateTime(2026, 11, 9, 12);

StandingOrder _prediction({StandingOrderState state = StandingOrderState.funding}) =>
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
      movedToPrice: 0.81,
    );

StandingOrder _investing() => StandingOrder(
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
      state: StandingOrderState.funded,
      createdAt: _at.add(const Duration(minutes: 1)),
      updatedAt: _at,
      leverage: 2,
      marketKind: 'perp',
    );

void main() {
  late Directory dir;
  late StandingOrderStore store;

  setUpAll(() {
    dir = Directory.systemTemp.createTempSync('standing_section_test');
    Hive.init(dir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  setUp(() {
    store = StandingOrderStore(
        secrets: FakeSecretStore(), boxName: 'standing_section');
  });

  Future<ProviderContainer> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(overrides: [
      ...portfolioOverrides(),
      standingOrderStoreProvider.overrideWithValue(store),
      standingOrderWatchersProvider.overrideWithValue(
          StandingOrderWatchers(wakePredictions: () {}, wakeInvesting: () {})),
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
          theme: ThemeData(
              splashFactory: NoSplash.splashFactory,
              extensions: [AppColorsExtension.light()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ),
    ));
    await tester.pump();
    return container;
  }

  testWidgets('nothing without a standing order; each venue its own row',
      (tester) async {
    final c = await pump(tester, const StandingOrdersSection());
    expect(find.byType(PlacingBetRow), findsNothing);
    c.read(standingOrdersProvider.notifier).debugReplace([
      _prediction(),
      _investing(),
      _prediction().copyWith(state: StandingOrderState.filled),
    ]);
    await tester.pump();
    // Only the open ones, newest first; the finished one is history.
    expect(find.byType(PlacingBetRow), findsOneWidget);
    expect(find.byKey(const ValueKey('standing-row-so_p')), findsOneWidget);
    expect(find.byKey(const ValueKey('standing-row-so_i')), findsOneWidget);
    expect(find.textContaining('Placing your prediction'), findsOneWidget);
    expect(find.textContaining('Placing your order'), findsOneWidget);
    expect(find.textContaining('Long'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a tap opens the order\'s own slip again, through the one way back '
      '(the slip its order was left on), at every step: no journey sheet, '
      'no Cancel', (tester) async {
    final c = await pump(tester, const StandingOrdersSection());
    addTearDown(StandingOrderSlips.debugReset);
    final opened = <Set<String>>[];
    StandingOrderSlips.remember(
        venue: StandingOrderVenue.predictions,
        marketKey: '111',
        orderId: 'so_p',
        open: (_, follow) async => opened.add(follow));
    for (final state in [
      StandingOrderState.funding,
      StandingOrderState.funded,
      StandingOrderState.posting,
      StandingOrderState.posted,
    ]) {
      c.read(standingOrdersProvider.notifier)
          .debugReplace([_prediction(state: state), _investing()]);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('standing-row-so_p')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Cancel'), findsNothing, reason: state.name);
      expect(find.byType(BottomSheet), findsNothing, reason: state.name);
    }
    // Each tap followed exactly this order: nothing else on its market.
    expect(opened, [for (var i = 0; i < 4; i++) <String>{}]);
    expect(c.read(standingOrdersProvider).first.state,
        StandingOrderState.posted);
    expect(tester.takeException(), isNull);
  });

  test('the row\'s words by state', () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    String status(StandingOrderState s) =>
        standingOrderRowStatus(l10n, _prediction(state: s));
    expect(status(StandingOrderState.funding), 'Placing your prediction');
    expect(status(StandingOrderState.posting), 'Placing your prediction');
    expect(status(StandingOrderState.filled), 'Prediction placed');
    expect(status(StandingOrderState.needsApproval), contains('81%'));
    expect(standingOrderRowStatus(l10n, _investing()), 'Placing your order');
    expect(standingOrderRowStatus(l10n, _prediction(state: StandingOrderState.needsApproval)),
        contains('Tap to place'));
  });

  test(
      'the Overview card\'s word: Placing from the accept until the fill '
      '(the money moving included), placed the moment it fills', () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    for (final s in [
      StandingOrderState.funding,
      StandingOrderState.funded,
      StandingOrderState.posting,
      StandingOrderState.posted,
    ]) {
      expect(standingOrderStageLine(l10n, _prediction(state: s)), 'Placing',
          reason: s.name);
      expect(standingOrderStageLine(l10n, _investing().copyWith(state: s)),
          'Placing',
          reason: s.name);
    }
    expect(
        standingOrderStageLine(
            l10n, _prediction(state: StandingOrderState.filled)),
        isNull);
    expect(
        standingOrderStageLine(
            l10n, _investing().copyWith(state: StandingOrderState.filled)),
        isNull);
    expect(
        standingOrderStageLine(
            l10n, _prediction(state: StandingOrderState.needsApproval)),
        'Needs your approval');
  });

  test('placed, the card carries the fill\'s own figures', () {
    // Predictions: what the shares cost.
    expect(
        _prediction(state: StandingOrderState.filled)
            .copyWith(filledSize: 19.6, filledUsd: 9.8)
            .placedUsd,
        9.8);
    // Investing: the margin at the fill, the notional over the leverage.
    expect(
        _investing()
            .copyWith(
                state: StandingOrderState.filled,
                filledSize: 0.0005,
                filledUsd: 30)
            .placedUsd,
        closeTo(30 / _investing().leverage, 1e-9));
    // No figures in the answer: the stake stands in.
    expect(_prediction(state: StandingOrderState.filled).placedUsd,
        _prediction().amountUsd);
  });
}
