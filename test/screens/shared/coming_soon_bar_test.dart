// The Coming soon page's Go back is the floating bar's primary button
// (kute_bar_context.dart: every pinned primary is the bar), not the old
// outlined full-width button sitting over the default pill.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/coming_soon_screen.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/kute_bar_test_support.dart';

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    TrackingService.setDisabled(true);
    KuteBarRouteObserver.reset();
  });

  testWidgets('Go back is the bar, and takes the page away', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(initialLocation: '/', routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const Scaffold(body: Text('home')),
        routes: [
          GoRoute(
            path: 'soon',
            builder: (_, __) => const ComingSoonScreen(
                title: 'Games', icon: Icons.games, analyticsKey: 'games'),
          ),
        ],
      ),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp.router(
          builder: withKuteShellBar,
          routerConfig: router,
          theme: buildLightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    ));
    router.push('/soon');
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(tester.element(find.text('Games')));
    expect(find.byType(AppButton), findsNothing);
    expect(kuteBarPrimaryWithText(l10n.goBack), findsOneWidget);
    await tester.tap(kuteBarPrimaryWithText(l10n.goBack));
    await tester.pumpAndSettle();
    expect(find.byType(ComingSoonScreen), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });
}
