// The light/dark switch never paints the red error screen "Text shadow
// blur radius should be non-negative" (founder report, 1 November 2026).
// Cause: an AnimatedContainer on the chip SPRING (the Sal pill) whose
// shadow existed in light and was null in dark: the theme switch lerped
// the shadow towards none, BoxShadow.lerpList scaled its blur by (1 - t),
// and the spring's overshoot past 1 made it negative. Every spring-driven
// decoration keeps the same shadow list in both modes, and text-style and
// theme lerps run on the settle (KuteMotion.textCurve).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/screens/home/components/kute_bottom_action_bar.dart'
    show KuteSalPill;
import 'package:kute/screens/home/components/kute_shell_bar.dart'
    show KuteBarPrimaryButton;
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/theme/kute_motion.dart';

void main() {
  testWidgets(
      'toggling light/dark five round trips over the pill, the pill tabs and the '
      'bar button throws nothing', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final mode = ValueNotifier<ThemeMode>(ThemeMode.light);
    addTearDown(mode.dispose);
    ThemeData theme(AppColorsExtension ext, Brightness b) => ThemeData(
          brightness: b,
          splashFactory: NoSplash.splashFactory,
          extensions: [ext],
        );
    await tester.pumpWidget(ProviderScope(
      overrides: [aiEnabledProvider.overrideWith((_) async => true)],
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => ValueListenableBuilder<ThemeMode>(
          valueListenable: mode,
          builder: (_, m, __) => MaterialApp(
            themeMode: m,
            themeAnimationCurve: KuteMotion.textCurve,
            theme: theme(AppColorsExtension.light(), Brightness.light),
            darkTheme: theme(AppColorsExtension.dark(), Brightness.dark),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  KuteSalPill(label: 'Search or ask Sal', onTap: () {}),
                  KutePillTabs(
                    items: const [
                      KutePillItem(label: 'Investing'),
                      KutePillItem(label: 'Predictions'),
                    ],
                    selectedIndex: 0,
                    onTap: (_) {},
                  ),
                  KuteBarPrimaryButton(
                    barContext: KuteBarContext.primary(
                        label: 'Continue', onPrimary: () {}),
                    onAsk: () {},
                  ),
                  KuteBarPrimaryButton(
                    barContext: KuteBarContext.primary(
                        label: 'Continue', onPrimary: () {}, enabled: false),
                    onAsk: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    for (var i = 0; i < 10; i++) {
      mode.value =
          mode.value == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
      // Every frame of the switch, through the spring's overshoot.
      for (var f = 0; f < 40; f++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull,
            reason: 'toggle ${i + 1}, frame $f');
      }
    }
  });
}
