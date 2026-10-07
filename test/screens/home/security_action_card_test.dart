import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/wallet_backup_provider.dart';
import 'package:kute/screens/home/home_wallet_switcher.dart';
import 'package:kute/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> pump(WidgetTester tester, WalletConfig? pending,
      {bool dark = false}) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(overrides: [
      pendingSpendingWalletBackupProvider.overrideWithValue(pending),
    ]);
    addTearDown(container.dispose);
    final router = GoRouter(initialLocation: '/home', routes: [
      GoRoute(
          path: '/home',
          builder: (_, __) => Scaffold(
              body: Column(children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: const SecurityActionCard(),
                ),
              ]))),
      GoRoute(
          path: '/backup_wallet',
          builder: (_, state) =>
              Scaffold(body: Text('route:backup_wallet ${state.extra}'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp.router(
          routerConfig: router,
          theme: ThemeData(
              fontFamily: 'Inter',
              brightness: dark ? Brightness.dark : Brightness.light,
              extensions: [
                dark ? AppColorsExtension.dark() : AppColorsExtension.light()
              ]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  final wallet = WalletConfig(id: 'w1', name: 'Spending', sparkEnabled: true);

  for (final dark in [false, true]) {
    testWidgets(
        'the backup reminder is one compact row with a single action '
        '(${dark ? 'dark' : 'light'})', (tester) async {
      await pump(tester, wallet, dark: dark);
      expect(find.text('Back up your wallet'), findsOneWidget);
      expect(find.text('In case you lose your phone'), findsOneWidget);
      expect(find.text('Back up'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
      // No animated border sweep any more.
      expect(
          find.descendant(
              of: find.byType(SecurityActionCard),
              matching: find.byType(CustomPaint)),
          findsNothing);
      // No taller than the old two-line card (about 80 at this size).
      expect(tester.getSize(find.byType(SecurityActionCard)).height,
          lessThanOrEqualTo(72));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the row and its button both open the backup flow',
      (tester) async {
    await pump(tester, wallet);
    await tester.tap(find.text('Back up'));
    await tester.pumpAndSettle();
    expect(find.text('route:backup_wallet w1'), findsOneWidget);

    await pump(tester, wallet);
    await tester.tap(find.text('Back up your wallet'));
    await tester.pumpAndSettle();
    expect(find.text('route:backup_wallet w1'), findsOneWidget);
  });

  testWidgets('nothing shows once the wallet is backed up', (tester) async {
    await pump(tester, null);
    expect(find.text('Back up your wallet'), findsNothing);
    expect(tester.getSize(find.byType(SecurityActionCard)).height, 0);
  });
}
