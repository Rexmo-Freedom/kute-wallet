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
import 'package:kute/services/passkey_service.dart';
import 'package:kute/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  /// Labels the passkey reminder ran for, and what each run returns.
  late List<String> runs;
  late PasskeyLabelBackupResult runResult;
  setUp(() {
    runs = [];
    runResult = const PasskeyLabelBackupResult(
        succeeded: true, cancelled: false, republished: 1);
  });

  Future<void> pump(WidgetTester tester, WalletConfig? pending,
      {bool dark = false, Set<String> pendingLabels = const {}}) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(overrides: [
      pendingSpendingWalletBackupProvider.overrideWithValue(pending),
      passkeyPendingLabelsProvider.overrideWithValue(pendingLabels),
      passkeyLabelBackupRunnerProvider.overrideWithValue(
          (label, {required surface}) async {
        runs.add(label);
        return runResult;
      }),
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

  final passkey = WalletConfig(
      id: 'p1',
      name: 'Spending',
      sparkEnabled: true,
      isPasskey: true,
      passkeyLabel: 'Spending Wallet · 1',
      passkeyProvider: 'breez-0.17',
      backedUp: false);

  testWidgets('an unpublished passkey label asks for one passkey confirmation',
      (tester) async {
    await pump(tester, passkey);
    expect(find.text('Finish your passkey backup'), findsOneWidget);
    expect(find.text('So a new phone can restore it'), findsOneWidget);
    expect(find.text('Confirm'), findsOneWidget);
    expect(tester.getSize(find.byType(SecurityActionCard)).height,
        lessThanOrEqualTo(72));

    await tester.tap(find.text('Confirm'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    // The ceremony ran for this wallet's label; no words were revealed.
    expect(runs, ['Spending Wallet · 1']);
    expect(find.textContaining('route:backup_wallet'), findsNothing);
  });

  testWidgets('a failed confirmation keeps the reminder and says so',
      (tester) async {
    runResult = const PasskeyLabelBackupResult(
        succeeded: false, cancelled: false, republished: 0);
    await pump(tester, passkey);
    await tester.tap(find.text('Finish your passkey backup'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
        find.text("Couldn't finish your passkey backup. Check your "
            'connection and try again.'),
        findsOneWidget);
    expect(find.text('Finish your passkey backup'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(runs, hasLength(1));
  });

  testWidgets('a backed-up passkey wallet with a pending label still asks',
      (tester) async {
    await pump(tester, passkey.copyWith(backedUp: true),
        pendingLabels: const {'Spending Wallet · 1'});
    expect(find.text('Finish your passkey backup'), findsOneWidget);
  });

  testWidgets('an unbacked legacy passkey wallet opens the words backup',
      (tester) async {
    final legacy = WalletConfig(
        id: 'l1',
        name: 'Spending',
        sparkEnabled: true,
        isPasskey: true,
        backedUp: false);
    await pump(tester, legacy);
    expect(find.text('Back up your wallet'), findsOneWidget);
    await tester.tap(find.text('Back up'));
    await tester.pumpAndSettle();
    expect(find.text('route:backup_wallet l1'), findsOneWidget);
    expect(runs, isEmpty);
  });

  testWidgets('nothing shows once the wallet is backed up', (tester) async {
    await pump(tester, null);
    expect(find.text('Back up your wallet'), findsNothing);
    expect(tester.getSize(find.byType(SecurityActionCard)).height, 0);
  });
}
