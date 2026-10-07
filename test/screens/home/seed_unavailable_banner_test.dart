import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/breez/sdk_instance.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/breez_config_provider.dart';
import 'package:kute/screens/home/components/seed_unavailable_banner.dart';
import 'package:kute/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> pump(WidgetTester tester, Object error) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(overrides: [
      breezSDKProvider
          .overrideWith((ref) => Future<BreezSdkSpark>.error(error)),
    ]);
    addTearDown(container.dispose);
    final router = GoRouter(initialLocation: '/home', routes: [
      GoRoute(
          path: '/home',
          builder: (_, __) => const Scaffold(
              body: Column(children: [SeedUnavailableBanner()]))),
      GoRoute(
          path: '/restore_secrets',
          builder: (_, state) =>
              Scaffold(body: Text('route:restore_secrets ${state.extra}'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp.router(
          routerConfig: router,
          theme: ThemeData(
              fontFamily: 'Inter', extensions: [AppColorsExtension.light()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('an unreadable spending seed links to Restore wallets',
      (tester) async {
    await pump(
        tester, const SeedUnavailableException(SeedUnavailableReason.storage));
    expect(find.text('This wallet needs to be restored on this phone.'),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('seed-unavailable-banner')));
    await tester.pumpAndSettle();
    expect(find.textContaining('route:restore_secrets'), findsOneWidget);
    expect(find.textContaining('walletUnavailable'), findsOneWidget);
  });

  testWidgets('a locked session or another error shows no banner',
      (tester) async {
    for (final error in [const SeedLockedException(), StateError('offline')]) {
      await pump(tester, error);
      expect(
          find.byKey(const ValueKey('seed-unavailable-banner')), findsNothing);
    }
  });
}
