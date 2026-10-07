import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/creation/passkey_choice.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  for (final systemBack in [false, true]) {
    for (final pushed in [false, true]) {
      testWidgets('creation back works with ${pushed ? "push" : "replacement"} via ${systemBack ? "system" : "toolbar"}', (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final router = GoRouter(initialLocation: '/start', routes: [
          GoRoute(path: '/start', builder: (context, _) => Scaffold(
            body: TextButton(onPressed: () {
              if (pushed) {
                context.push('/passkey_choice');
              } else {
                // ConfirmPin uses go(), leaving no previous page to pop.
                context.go('/passkey_choice');
              }
            }, child: const Text('Create account')),
          )),
          GoRoute(path: '/passkey_choice', builder: (_, __) =>
              const PasskeyChoice(nextRoute: '/home')),
        ]);
        addTearDown(router.dispose);
        await tester.pumpWidget(ProviderScope(child: ScreenUtilInit(
          designSize: const Size(430, 932),
          builder: (_, __) => MaterialApp.router(
            routerConfig: router,
            theme: ThemeData(splashFactory: NoSplash.splashFactory,
                fontFamily: 'Inter', extensions: [AppColorsExtension.light()]),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        )));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Create account'));
        await tester.pumpAndSettle();
        expect(find.byType(PasskeyChoice), findsOneWidget);
        expect(tester.takeException(), isNull);
        final button = tester.getRect(find.byType(AppButton));
        expect(button.bottom, greaterThan(790));
        expect(button.bottom, lessThanOrEqualTo(844));
        if (systemBack) {
          await tester.binding.handlePopRoute();
        } else {
          await tester.tap(find.byType(KuteBackButton));
        }
        await tester.pumpAndSettle();
        expect(find.text('Create account'), findsOneWidget);
        expect(find.byType(PasskeyChoice), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
