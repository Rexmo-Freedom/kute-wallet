// Text drawn above the navigator never wears Flutter's error style (the
// yellow double underline; founder report, 1 November 2026): the shell
// bar in the MaterialApp builder's Stack and the pill's travel to the
// composer on the root overlay both sit outside every page's Material, and
// KuteOverlaySurface gives them the theme's text.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/screens/home/components/kute_shell_bar.dart';
import 'package:kute/screens/search/components/search_morph.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/theme/app_theme.dart';

final _navKey = GlobalKey<NavigatorState>();

/// Every painted text on screen, with the style it resolved to.
void _expectNoErrorStyle(WidgetTester tester, String where) {
  final texts = tester.widgetList<RichText>(find.byType(RichText)).toList();
  expect(texts, isNotEmpty, reason: where);
  for (final t in texts) {
    final style = t.text.style;
    expect(style?.decorationStyle, isNot(TextDecorationStyle.double),
        reason: '$where: "${t.text.toPlainText()}" wears the error style');
    expect(style?.decoration ?? TextDecoration.none,
        TextDecoration.none,
        reason: '$where: "${t.text.toPlainText()}" is underlined');
    expect(style?.fontFamily, isNot('monospace'),
        reason: '$where: "${t.text.toPlainText()}" fell back to monospace');
  }
}

void main() {
  setUp(KuteBarRouteObserver.reset);

  testWidgets(
      'the shell bar (pill and primary button) and the morph overlay paint '
      'the theme text, never the error underline', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [aiEnabledProvider.overrideWith((_) async => true)],
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          theme: ThemeData(extensions: [AppColorsExtension.light()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          navigatorKey: _navKey,
          navigatorObservers: [KuteBarRouteObserver()],
          // As app_widget.dart: the bar in the builder's Stack, over the
          // navigator, with no Material of its own around it.
          builder: (context, child) =>
              Stack(children: [child!, const KuteShellBar()]),
          // No Material on the root either, so nothing but the bar's own
          // surface can give its text a style.
          home: const SizedBox.expand(),
        ),
      ),
    ));
    // The default pill over a pushed page.
    _navKey.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const ColoredBox(color: Color(0xFFFFFFFF))));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('kute-bar-pill')), findsOneWidget);
    _expectNoErrorStyle(tester, 'the pill');

    // The primary button.
    _navKey.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => KuteBarContextScope(
              barContext:
                  KuteBarContext.primary(label: 'Continue', onPrimary: () {}),
              child: const ColoredBox(color: Color(0xFFFFFFFF)),
            )));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('kute-bar-primary-button')),
        findsOneWidget);
    _expectNoErrorStyle(tester, 'the primary button');

    // The pill travelling to the composer, on the root overlay.
    final travel = KuteSearchMorph.run(
      _navKey.currentState!.overlay!,
      from: const Rect.fromLTWH(16, 760, 358, 56),
      to: const Rect.fromLTWH(16, 400, 358, 48),
      opening: true,
      label: 'Search or ask Sal',
      hint: 'Ask Sal anything',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(find.text('Search or ask Sal'), findsWidgets);
    _expectNoErrorStyle(tester, 'the morph');
    await tester.pumpAndSettle();
    await travel;
  });
}
