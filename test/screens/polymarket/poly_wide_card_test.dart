// The wide web Predictions grid's calm card: the title (two lines at
// most), the two leading outcomes, each one line with its chance, "+N
// more" when there are more, and no bars, sparkline or move arrows. The
// column rule gives four at 1440 with the sidebar, three at about 1100.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/screens/polymarket/components/poly_wide_card.dart';
import 'package:kute/theme/app_theme.dart';

Finder outcomeLines() => find.byWidgetPredicate((w) =>
    w.key is ValueKey<String> &&
    (w.key as ValueKey<String>).value.startsWith('poly-wide-outcome-'));

void main() {
  Future<void> pump(WidgetTester tester, List<PolymarketOutcome> outcomes,
      {VoidCallback? onTap}) async {
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
      theme: ThemeData(extensions: [AppColorsExtension.light()]),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            height: kPolyWideCardHeight,
            child: PolyWideCard(
              title: 'Who will win the election?',
              outcomes: outcomes,
              onTap: onTap ?? () {},
            ),
          ),
        ),
      ),
    )));
  }

  testWidgets('many outcomes: the two leaders and +N more, no bars',
      (tester) async {
    var taps = 0;
    await pump(tester, const [
      PolymarketOutcome(name: 'Ana', price: 0.12),
      PolymarketOutcome(name: 'Bruno', price: 0.55),
      PolymarketOutcome(name: 'Carla', price: 0.25),
      PolymarketOutcome(name: 'Duarte', price: 0.08),
    ], onTap: () => taps++);
    expect(outcomeLines(), findsNWidgets(2));
    expect(find.text('Bruno'), findsOneWidget);
    expect(find.text('Carla'), findsOneWidget);
    expect(find.text('Ana'), findsNothing);
    expect(find.text('55%'), findsOneWidget);
    expect(find.text('+2 more'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(CustomPaint).evaluate().where((e) {
      final w = e.widget as CustomPaint;
      return w.painter != null;
    }), isEmpty);
    await tester.tap(find.byKey(const ValueKey('poly-wide-card')));
    expect(taps, 1);
  });

  testWidgets('Yes / No: its two sides in order, adding up to 100, no "more"',
      (tester) async {
    await pump(tester, const [
      PolymarketOutcome(name: 'Yes', price: 0.38),
      PolymarketOutcome(name: 'No', price: 0.62),
    ]);
    expect(tester.getTopLeft(find.text('Yes')).dy,
        lessThan(tester.getTopLeft(find.text('No')).dy));
    expect(outcomeLines(), findsNWidgets(2));
    expect(find.text('62%'), findsOneWidget);
    expect(find.text('38%'), findsOneWidget);
    expect(find.textContaining('more'), findsNothing);
  });

  test('columns: 280 at the narrowest, 16 between', () {
    // 1440 window less the sidebar and gutters: about 1150 of content.
    expect(polyWideColumns(1150), 3);
    expect(polyWideColumns(1220), 4);
    expect(polyWideColumns(760), 2);
    expect(polyWideColumns(1600), 5);
    expect(polyWideColumns(200), 1);
  });
}
