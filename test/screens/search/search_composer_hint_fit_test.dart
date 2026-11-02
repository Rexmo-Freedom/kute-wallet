// The search sheet's composer hint is never cut (founder, 2 November 2026:
// "Search investments or manage wit…" was): "Search or Manage with AI",
// "Search investments or Manage with AI" and "Search predictions or manage
// with AI", and the search-only hints, sit whole on the composer line on a
// 375 pt phone in every shipped language, in Inter, at the composer's real
// width (the sheet's gutters around it). A hint longer than the line
// shrinks to fit it (never below 12 px at the default text size; a larger
// system text size shrinks it rather than cutting it).

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/search/components/search_composer.dart';
import 'package:kute/theme/app_theme.dart';

Future<void> _loadInter() async {
  final inter = FontLoader('Inter');
  for (final f in ['Regular', 'SemiBold', 'Bold']) {
    inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
  }
  await inter.load();
}

void main() {
  for (final scale in [1.0, 1.3]) {
    testWidgets(
        'the composer hints sit whole on one line at 375 pt in every '
        'language, text scale $scale', (tester) async {
      await tester.runAsync(_loadInter);
      tester.view.physicalSize = const Size(375, 812) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      for (final locale in AppLocalizations.supportedLocales) {
        final l10n = l10nForLanguage(locale.languageCode);
        final hints = [
          (l10n.searchOrManageAi, true),
          (l10n.searchInvestmentsOrManageAi, true),
          (l10n.searchPredictionsOrManageAi, true),
          (l10n.searchMarketsHint, false),
          (l10n.searchYourWallet, false),
        ];
        for (final (hint, ai) in hints) {
          await tester.pumpWidget(ProviderScope(
            child: ScreenUtilInit(
              designSize: const Size(430, 932),
              builder: (_, __) => MaterialApp(
                debugShowCheckedModeBanner: false,
                locale: locale,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                theme: ThemeData(
                  fontFamily: 'Inter',
                  extensions: [AppColorsExtension.light()],
                ),
                // A larger system text size shrinks the hint to the line
                // rather than cutting it.
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Scaffold(
                  body: Builder(
                    builder: (context) => Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: KuteSearchComposer.gutter(context)),
                      child: KuteSearchComposer(
                        controller: controller,
                        onSubmit: () {},
                        aiEnabled: ai,
                        hint: hint,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ));
          await tester.pump();
          final p = tester.renderObject<RenderParagraph>(find.text(hint));
          final needed = p.getMaxIntrinsicWidth(double.infinity);
          final composer = tester.getRect(find.byType(KuteSearchComposer));
          final shown = tester.getRect(find.text(hint));
          expect(needed, lessThanOrEqualTo(p.size.width + 0.5),
              reason: '${locale.languageCode}: "$hint" is cut '
                  '(${needed.toStringAsFixed(1)} > '
                  '${p.size.width.toStringAsFixed(1)})');
          expect(shown.right, lessThanOrEqualTo(composer.right + 0.5),
              reason: '${locale.languageCode}: "$hint" runs off the line');
          final size = tester
              .widget<TextField>(find.byType(TextField))
              .decoration!
              .hintStyle!
              .fontSize!;
          if (scale == 1.0) {
            expect(size, greaterThanOrEqualTo(12),
                reason: '${locale.languageCode}: "$hint" shrinks to '
                    '${size.toStringAsFixed(1)} px');
          }
        }
      }
    });
  }
}
