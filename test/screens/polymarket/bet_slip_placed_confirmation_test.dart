import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/polymarket/components/bet_slip_sheet.dart';
import 'package:kute/screens/polymarket/components/fast_bet_scope.dart';
import 'package:kute/services/polymarket/fast_bet_window.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/theme/app_theme.dart';

void main() {
  tearDown(() => KuteConfirmation.debugFeedbackOverride = null);

  testWidgets(
      'bet slip success closes the slip and market sheet and shows Prediction placed',
      (tester) async {
    var haptics = 0;
    KuteConfirmation.debugFeedbackOverride = () async => haptics++;
    final rootKey = GlobalKey<NavigatorState>();
    final router = GoRouter(
      navigatorKey: rootKey,
      initialLocation: '/predictions',
      routes: [
        GoRoute(
          path: '/predictions',
          builder: (_, __) => const Scaffold(body: Text('predictions')),
        ),
      ],
    );
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp.router(
        routerConfig: router,
        theme: buildLightTheme().copyWith(splashFactory: NoSplash.splashFactory),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ));
    await tester.pumpAndSettle();

    final nav = rootKey.currentState!;
    nav.push(MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'polymarket-market-detail-sheet'),
      builder: (_) => const Scaffold(body: Text('market detail')),
    ));
    nav.push(MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'polymarket-bet-slip'),
      builder: (_) => const Scaffold(body: Text('bet slip')),
    ));
    await tester.pumpAndSettle();
    expect(find.text('bet slip'), findsOneWidget);

    showBetSlipPlacedConfirmation(
      navigator: nav,
      marketQuestion: 'Will it rain?',
      outcome: 'Yes',
      total: 10,
      price: 0.5,
      filledShares: 20,
      filledCost: 10,
    );
    await tester.pumpAndSettle();

    expect(find.text('bet slip'), findsNothing);
    expect(find.text('market detail'), findsNothing);
    expect(find.byType(KuteConfirmation), findsOneWidget);
    expect(find.text('Prediction placed'), findsOneWidget);
    expect(find.text(r'$10.00'), findsOneWidget);
    expect(find.text(r'$20.00'), findsOneWidget);
    expect(find.text('View prediction'), findsOneWidget);
    expect(haptics, 1);

    await tester.tap(find.byType(KuteCloseButton));
    await tester.pumpAndSettle();
    expect(find.byType(KuteConfirmation), findsNothing);
    expect(find.text('predictions'), findsOneWidget);
  });

  group('a 5 or 15 minute round keeps its market sheet', () {
    const round15 = 'btc-updown-15m-1791152100';
    final session =
        SessionAuth(method: UnlockMethod.pin, unlockedAt: DateTime(2026));
    SensitiveIntent buy(int cents) => PmIntents.order(
          walletId: 'w1',
          tokenId: '0xabc',
          isBuy: true,
          amountMax: BigInt.from(cents) * BigInt.from(10000),
          limitPrice: 0.55,
          orderType: 'fok',
          maxSlippageBps: 200,
        );

    setUp(FastBetWindow.instance.debugReset);
    tearDown(FastBetWindow.instance.debugReset);

    /// The 15 minute market sheet and the slip over it, both short-round
    /// screens, with the window opened by the first bet's approval.
    Future<NavigatorState> pumpRound(WidgetTester tester) async {
      KuteConfirmation.debugFeedbackOverride = () async {};
      final rootKey = GlobalKey<NavigatorState>();
      final router = GoRouter(
        navigatorKey: rootKey,
        initialLocation: '/predictions',
        routes: [
          GoRoute(
            path: '/predictions',
            builder: (_, __) => const Scaffold(body: Text('predictions')),
          ),
        ],
      );
      await tester.pumpWidget(ProviderScope(
        overrides: [
          settingsProvider.overrideWith((ref) => SettingsModel(Settings(
                wallets: [WalletConfig(id: 'w1', name: 'Spending')],
                activeWalletId: 'w1',
                currency: 'USD',
                language: 'en',
                btcFormat: 'sats',
                backup: true,
                biometricsEnabled: false,
                bitcoinElectrumNode: '',
                nodeType: 'electrum',
                reviewDone: true,
              ))),
          sessionAuthProvider.overrideWith((ref) => session),
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
      final nav = rootKey.currentState!;
      nav.push(MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'polymarket-market-detail-sheet'),
        builder: (_) => FastBetScope(
            active: polyIsFastBetRound(round15),
            child: const Scaffold(body: Text('market detail'))),
      ));
      nav.push(MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'polymarket-bet-slip'),
        builder: (_) => FastBetScope(
            active: polyIsFastBetRound(round15),
            child: const Scaffold(body: Text('bet slip'))),
      ));
      await tester.pumpAndSettle();
      expect(FastBetWindow.instance.scopes, 2);
      FastBetWindow.instance.open(buy(1000),
          request: const FastBetRequest(eventSlug: round15, hot: true),
          method: AuthGrantMethod.biometric,
          session: session,
          sessionUnlocked: true);
      expect(FastBetWindow.instance.isOpen, isTrue);
      return nav;
    }

    void confirm(NavigatorState nav, {required bool keep}) =>
        showBetSlipPlacedConfirmation(
          navigator: nav,
          marketQuestion: 'Bitcoin Up or Down',
          outcome: 'Up',
          total: 10,
          price: 0.5,
          filledShares: 20,
          filledCost: 10,
          keepMarketSheet: keep,
        );

    testWidgets('only the slip closes and the window rides the second bet',
        (tester) async {
      final nav = await pumpRound(tester);
      confirm(nav, keep: true);
      await tester.pumpAndSettle();
      expect(find.text('bet slip'), findsNothing);
      expect(find.text('Prediction placed'), findsOneWidget);
      expect(FastBetWindow.instance.scopes, 1);
      expect(FastBetWindow.instance.isOpen, isTrue);

      await tester.tap(find.byType(KuteCloseButton));
      await tester.pumpAndSettle();
      expect(find.text('market detail'), findsOneWidget,
          reason: 'back on the round, like the five-minute sheet');

      final second = FastBetWindow.instance.tryIssue(buy(1000),
          request: const FastBetRequest(eventSlug: round15, hot: true),
          amountUsdCents: 1000,
          session: session,
          sessionUnlocked: true);
      expect(second?.method, AuthGrantMethod.fastWindow);
    });

    testWidgets('without it the market sheet closes and the window ends',
        (tester) async {
      final nav = await pumpRound(tester);
      confirm(nav, keep: false);
      await tester.pumpAndSettle();
      expect(find.text('market detail'), findsNothing);
      expect(FastBetWindow.instance.isOpen, isFalse);
      expect(FastBetWindow.instance.lastEnd, FastBetWindowEnd.leftScreens);
    });

    test('the slip keeps the sheet for 5 and 15 minute rounds only', () {
      expect(polyIsFastBetRound(round15), isTrue);
      expect(polyIsFastBetRound('btc-updown-5m-1791152100'), isTrue);
      expect(polyIsFastBetRound('btc-updown-4h-1791144000'), isFalse);
      expect(polyIsFastBetRound('will-it-rain'), isFalse);
    });
  });

  test(
      'spot bets end on the confirmation and skip the controller haptic; '
      'limit orders keep the in-sheet beat', () {
    expect(betSlipEndsOnConfirmation(isLimit: false), isTrue);
    expect(betSlipEndsOnConfirmation(isLimit: true), isFalse);
  });
}
