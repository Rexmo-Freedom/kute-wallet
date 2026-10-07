import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/screens/home/components/move_sent_overlay.dart';
import 'package:kute/screens/hyperliquid/components/order_placed_overlay.dart';
import 'package:kute/screens/polymarket/components/bet_placed_overlay.dart';
import 'package:kute/screens/polymarket/components/claim_placed_overlay.dart';
import 'package:kute/screens/polymarket/components/position_sold_overlay.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/screens/shared/transaction_modal.dart';
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
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp.router(
        routerConfig: router,
        theme:
            buildLightTheme().copyWith(splashFactory: NoSplash.splashFactory),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ));
    await tester.pumpAndSettle();
  }

  NavigatorState nav() => rootKey.currentState!;

  Future<void> tapDoneAndExpectHost(WidgetTester tester) async {
    // Receipts whose primary button opens the position (not "Done") are
    // dismissed with the close button instead.
    final isReceipt = find.text('View bet').evaluate().isNotEmpty ||
        find.text('View prediction').evaluate().isNotEmpty ||
        find.text('View positions').evaluate().isNotEmpty;
    await tester
        .tap(isReceipt ? find.byType(KuteCloseButton) : find.byType(AppButton));
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
    expect(find.text(r'$10.00'), findsOneWidget);
    expect(find.text(r'$20.00'), findsOneWidget);
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
    await tapDoneAndExpectHost(tester);
  });

  testWidgets('pushMoveSentOverlay shows the destination and the pending note',
      (tester) async {
    await pumpHost(tester);
    pushMoveSentOverlay(
      navigator: nav(),
      amount: '0.001 BTC',
      fromWalletName: 'Spending',
      toWalletName: 'Savings',
      assetIconAsset: 'lib/assets/bitcoin-icon.svg',
      note: 'Arriving in ~2 min',
    );
    await tester.pumpAndSettle();
    expect(find.text('Sent to Savings'), findsOneWidget);
    expect(find.text('Arriving in ~2 min'), findsOneWidget);
    expect(find.text('0.001 BTC'), findsNothing);
    await tapDoneAndExpectHost(tester);
  });

  testWidgets(
      'KuteSuccessOverlay keeps its caller onDone and close button, in sentence case',
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
    expect(find.text(r'$20.00'), findsNothing);
    expect(find.byType(KuteCloseButton), findsOneWidget);
    await tapDoneAndExpectHost(tester);
    expect(done, 1);

    pushKuteSuccessOverlay(
      navigator: nav(),
      overlay: const KuteSuccessOverlay(headlineLabel: 'Received', amount: ''),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(KuteCloseButton));
    await tester.pumpAndSettle();
    expect(find.byType(KuteConfirmation), findsNothing);
  });

  testWidgets(
      'showFullscreenTransactionSendModal shows Bitcoin sent and Done pops everything then goes home',
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
    expect(find.text('bc1qexample'), findsNothing);
    expect(find.byType(KuteCloseButton), findsNothing);

    await tester.tap(find.byType(AppButton));
    await tester.pumpAndSettle();
    expect(find.byType(KuteConfirmation), findsNothing);
    expect(find.text('send sheet'), findsNothing);
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
