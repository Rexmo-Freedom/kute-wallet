import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/providers/active_shell_tab_provider.dart';
import 'package:kute/screens/home/components/move_sent_overlay.dart';
import 'package:kute/screens/hyperliquid/components/order_placed_overlay.dart';
import 'package:kute/screens/polymarket/components/bet_placed_overlay.dart';
import 'package:kute/screens/polymarket/components/claim_placed_overlay.dart';
import 'package:kute/screens/polymarket/components/position_sold_overlay.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/screens/portfolio/investments_portfolio.dart'
    show PortfolioSection, portfolioSectionProvider;
import 'package:kute/screens/shared/transaction_modal.dart';
import 'package:kute/screens/usd/usd_account_screen.dart'
    show InvestmentsTab, investmentsTabProvider, openInvestmentsOrders;
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

void main() {
  late GlobalKey<NavigatorState> rootKey;

  setUp(() {
    rootKey = GlobalKey<NavigatorState>();
    KuteConfirmation.debugFeedbackOverride = () async {};
  });
  tearDown(() => KuteConfirmation.debugFeedbackOverride = null);

  Future<void> pumpHost(WidgetTester tester) async {
    final router = GoRouter(
      navigatorKey: rootKey,
      initialLocation: '/start',
      routes: [
        GoRoute(
          path: '/start',
          builder: (_, __) => const Scaffold(body: Text('host')),
        ),
        GoRoute(
          path: '/home',
          builder: (_, __) => const Scaffold(body: Text('home screen')),
        ),
      ],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        // Investments is the tab on screen, so opening the Portfolio
        // only writes its state.
        activeShellTabProvider.overrideWith((_) => ActiveNavTab.usd),
      ],
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp.router(
          routerConfig: router,
          theme: buildLightTheme()
              .copyWith(splashFactory: NoSplash.splashFactory),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  NavigatorState nav() => rootKey.currentState!;

  Future<void> tapDoneAndExpectHost(WidgetTester tester) async {
    // Done is always the primary button; a "View ..." is the quiet one.
    await tester.tap(find.widgetWithText(AppButton, 'Done'));
    await tester.pumpAndSettle();
    expect(find.byType(KuteConfirmation), findsNothing);
    expect(find.text('host'), findsOneWidget);
  }

  testWidgets('pushBetPlacedOverlay shows Prediction placed', (tester) async {
    await pumpHost(tester);
    pushBetPlacedOverlay(
      navigator: nav(),
      marketQuestion: 'Will it rain?',
      outcome: 'Yes',
      shares: 20,
      total: 10,
      avgPrice: 0.5,
      potentialPayout: 20,
    );
    await tester.pumpAndSettle();
    expect(find.byType(KuteConfirmation), findsOneWidget);
    expect(find.text('Prediction placed'), findsOneWidget);
    expect(find.text('Will it rain?'), findsOneWidget);
    expect(find.text(r'$10.00 on Yes'), findsOneWidget);
    expect(find.text(r'$20.00'), findsOneWidget);
    expect(find.widgetWithText(AppTextButton, 'View prediction'),
        findsOneWidget);
    await tapDoneAndExpectHost(tester);
  });

  testWidgets(
      'pushPositionSoldOverlay shows Position sold and a pending line until the conversion ends',
      (tester) async {
    await pumpHost(tester);
    final conversion = Completer<void>();
    pushPositionSoldOverlay(
      navigator: nav(),
      marketQuestion: 'Will it rain?',
      outcome: 'Yes',
      shares: 20,
      proceeds: 12,
      avgSellPrice: 0.6,
      pnl: 2,
      conversionFuture: conversion.future,
    );
    await tester.pumpAndSettle();
    expect(find.text('Position sold'), findsOneWidget);
    expect(find.text('Routing to your Bitcoin wallet…'), findsOneWidget);

    conversion.complete();
    await tester.pumpAndSettle();
    expect(find.text('Position sold'), findsOneWidget);
    expect(find.text('Routing to your Bitcoin wallet…'), findsNothing);
    await tapDoneAndExpectHost(tester);
  });

  testWidgets('pushClaimPlacedOverlay shows confirmed payout destination',
      (tester) async {
    await pumpHost(tester);
    pushClaimPlacedOverlay(
      navigator: nav(),
      marketQuestion: 'Will it rain?',
      outcome: 'Yes',
      amountUsd: 25,
    );
    await tester.pumpAndSettle();
    expect(find.text('Winnings claimed'), findsOneWidget);
    // Claims do not route to Bitcoin, so there is no pending line.
    expect(find.text('Routing to your Bitcoin wallet…'), findsNothing);
    await tapDoneAndExpectHost(tester);
  });

  testWidgets('pushHlOrderPlacedOverlay shows Order filled', (tester) async {
    await pumpHost(tester);
    pushHlOrderPlacedOverlay(
      navigator: nav(),
      coin: 'BTC',
      isLong: true,
      leverage: 3,
      isSpot: false,
      sizeFilled: 0.01,
      avgPx: 60000,
      notionalUsd: 600,
    );
    await tester.pumpAndSettle();
    expect(find.text('Order filled'), findsOneWidget);
    expect(find.widgetWithText(AppTextButton, 'View positions'),
        findsOneWidget);
    await tapDoneAndExpectHost(tester);
  });

  for (final isClose in [false, true]) {
    testWidgets(
        'an accepted ${isClose ? 'close ' : ''}order keeps Done and adds '
        '"View orders", which opens the Portfolio on P&L charts and is '
        'tracked', (tester) async {
      final events = <(String, Map<String, Object>?)>[];
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
      addTearDown(() => TrackingService.debugTrackObserver = null);
      await pumpHost(tester);
      pushKuteSuccessOverlay(
        navigator: nav(),
        overlay: HlOrderAcceptedOverlay(
            coin: 'BTC', amount: '0.01 BTC', isClose: isClose, viewOrders: true),
      );
      await tester.pumpAndSettle();
      expect(find.text(isClose ? 'Close order placed' : 'Order placed'),
          findsOneWidget);
      expect(find.widgetWithText(AppButton, 'Done'), findsOneWidget);
      final view = find.widgetWithText(AppTextButton, 'View orders');
      expect(view, findsOneWidget);

      await tester.tap(view);
      await tester.pumpAndSettle();
      expect(find.byType(KuteConfirmation), findsNothing);
      final container =
          ProviderScope.containerOf(tester.element(find.text('host')));
      expect(container.read(investmentsTabProvider), InvestmentsTab.positions);
      expect(container.read(portfolioSectionProvider), PortfolioSection.charts);
      expect(
          events
              .where((e) => e.$1 == 'order_confirmation_view_orders_tapped')
              .single
              .$2,
          {'product': 'investing', 'order_kind': isClose ? 'close' : 'open'});
    });
  }

  testWidgets(
      'an accepted order without viewOrders (a Ledger\'s) has Done only',
      (tester) async {
    await pumpHost(tester);
    pushKuteSuccessOverlay(
      navigator: nav(),
      overlay: const HlOrderAcceptedOverlay(coin: 'BTC', amount: '0.01 BTC'),
    );
    await tester.pumpAndSettle();
    expect(find.text('View orders'), findsNothing);
    await tester.tap(find.widgetWithText(AppButton, 'Done'));
    await tester.pumpAndSettle();
    expect(find.byType(KuteConfirmation), findsNothing);
    expect(find.text('host'), findsOneWidget);
  });

  testWidgets(
      'openInvestmentsOrders (the Predictions limit confirmations\' View '
      'orders) opens P&L charts and says which confirmation it was',
      (tester) async {
    final events = <(String, Map<String, Object>?)>[];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    addTearDown(() => TrackingService.debugTrackObserver = null);
    await pumpHost(tester);
    final context = tester.element(find.text('host'));
    openInvestmentsOrders(context,
        product: 'predictions', orderKind: 'limit_sell');
    final container = ProviderScope.containerOf(context);
    expect(container.read(investmentsTabProvider), InvestmentsTab.positions);
    expect(container.read(portfolioSectionProvider), PortfolioSection.charts);
    expect(events.single.$1, 'order_confirmation_view_orders_tapped');
    expect(events.single.$2,
        {'product': 'predictions', 'order_kind': 'limit_sell'});
  });

  testWidgets('pushMoveSentOverlay shows the destination and the pending note',
      (tester) async {
    await pumpHost(tester);
    pushMoveSentOverlay(
      navigator: nav(),
      amount: '0.001 BTC',
      fromWalletName: 'Spending',
      toWalletName: 'Savings',
      note: 'Arriving in ~2 min',
    );
    await tester.pumpAndSettle();
    expect(find.text('Sent to Savings'), findsOneWidget);
    expect(find.text('Arriving in ~2 min'), findsOneWidget);
    // The amount is the hero again (the old wrapper dropped it).
    expect(find.text('0.001 BTC'), findsOneWidget);
    await tapDoneAndExpectHost(tester);
  });

  testWidgets(
      'KuteSuccessOverlay keeps its caller onDone, amount and subtitle, in sentence case',
      (tester) async {
    await pumpHost(tester);
    var done = 0;
    pushKuteSuccessOverlay(
      navigator: nav(),
      overlay: KuteSuccessOverlay(
        headlineLabel: 'BITCOIN PURCHASED',
        amount: r'$20.00',
        subtitle: 'Sent to your Spending account',
        onDone: () {
          done++;
          nav().pop();
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Bitcoin purchased'), findsOneWidget);
    expect(find.text(r'$20.00'), findsOneWidget);
    expect(find.text('Sent to your Spending account'), findsOneWidget);
    await tapDoneAndExpectHost(tester);
    expect(done, 1);

    pushKuteSuccessOverlay(
      navigator: nav(),
      overlay: const KuteSuccessOverlay(headlineLabel: 'Received', amount: ''),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(AppButton, 'Done'));
    await tester.pumpAndSettle();
    expect(find.byType(KuteConfirmation), findsNothing);
  });

  testWidgets(
      'showFullscreenTransactionSendModal goes home first, then shows Bitcoin '
      'sent over home and Done just closes it',
      (tester) async {
    await pumpHost(tester);
    nav().push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('send sheet'))));
    await tester.pumpAndSettle();

    showFullscreenTransactionSendModal(
      context: tester.element(find.text('send sheet')),
      amount: '1,000 sats',
      receiveAddress: 'bc1qexample',
      txid: 'abc',
    );
    await tester.pumpAndSettle();
    expect(find.text('Bitcoin sent'), findsOneWidget);
    expect(find.text('1,000 sats'), findsOneWidget);
    // Already home under the sheet.
    expect(find.text('send sheet'), findsNothing);
    expect(find.text('home screen'), findsOneWidget);

    await tester.tap(find.widgetWithText(AppButton, 'Done'));
    await tester.pumpAndSettle();
    expect(find.byType(KuteConfirmation), findsNothing);
    expect(find.text('home screen'), findsOneWidget);
  });

  testWidgets(
      'showFullscreenTransactionSendModal says Conversion started for swaps',
      (tester) async {
    await pumpHost(tester);
    showFullscreenTransactionSendModal(
      context: tester.element(find.text('host')),
      amount: '10 USDT',
      receiveAddress: '0xabc',
      isSwap: true,
    );
    await tester.pumpAndSettle();
    expect(find.text('Conversion started'), findsOneWidget);
  });
}
