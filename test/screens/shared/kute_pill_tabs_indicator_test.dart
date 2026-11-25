// A tabs row of three or fewer (kute_pill_tabs.dart) has ONE white pill
// that slides between the tabs on the chip spring; the tabs themselves are
// flat. At once under Reduce Motion.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/theme/app_theme.dart';

Widget _app(Widget child, {bool reduce = false}) => ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: buildLightTheme(),
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduce),
          child: Scaffold(
            body: Center(child: SizedBox(width: 320, child: child)),
          ),
        ),
      ),
    );

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  const items = [KutePillItem(label: 'Bitcoin'), KutePillItem(label: 'Dollars')];

  testWidgets('the white pill slides from the first half to the second',
      (tester) async {
    var selected = 0;
    late StateSetter set;
    await tester.pumpWidget(_app(StatefulBuilder(builder: (context, s) {
      set = s;
      return KutePillTabs(
        items: items,
        selectedIndex: selected,
        onTap: (i) => s(() => selected = i),
      );
    })));
    final indicator = find.byKey(kutePillIndicatorKey);
    expect(indicator, findsOneWidget);
    final row = tester.getRect(find.byType(KutePillTabs));
    final start = tester.getRect(indicator);
    expect(start.left, closeTo(row.left + 4.w, 0.5));
    expect(start.width, lessThan(row.width / 2));
    // The tabs are flat: no pill paints its own white card.
    for (final pill in tester.widgetList<KutePill>(find.byType(KutePill))) {
      expect(pill.flat, isTrue);
    }

    set(() => selected = 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final mid = tester.getRect(indicator);
    expect(mid.left, greaterThan(start.left));
    expect(mid.left, lessThan(start.left + start.width + 6.w - 0.5),
        reason: 'on its way (the chip spring overshoots later)');
    await tester.pumpAndSettle();
    final end = tester.getRect(indicator);
    expect(end.left, closeTo(start.left + start.width + 6.w, 0.5));
    expect(end.right, closeTo(row.right - 4.w, 0.5));
  });

  testWidgets('Reduce Motion: the pill is at the new tab at once',
      (tester) async {
    var selected = 0;
    late StateSetter set;
    await tester.pumpWidget(_app(
        StatefulBuilder(builder: (context, s) {
          set = s;
          return KutePillTabs(
            items: items,
            selectedIndex: selected,
            onTap: (i) => s(() => selected = i),
          );
        }),
        reduce: true));
    final indicator = find.byKey(kutePillIndicatorKey);
    final start = tester.getRect(indicator);
    set(() => selected = 1);
    await tester.pump();
    final end = tester.getRect(indicator);
    expect(end.left, closeTo(start.left + start.width + 6.w, 0.5));
  });

  testWidgets('a tap moves the selection and the pill follows',
      (tester) async {
    var selected = 0;
    await tester.pumpWidget(_app(StatefulBuilder(builder: (context, s) {
      return KutePillTabs(
        items: items,
        selectedIndex: selected,
        onTap: (i) => s(() => selected = i),
      );
    })));
    final before = tester.getRect(find.byKey(kutePillIndicatorKey));
    await tester.tap(find.text('Dollars'));
    await tester.pumpAndSettle();
    expect(selected, 1);
    expect(tester.getRect(find.byKey(kutePillIndicatorKey)).left,
        greaterThan(before.left));
  });
}
