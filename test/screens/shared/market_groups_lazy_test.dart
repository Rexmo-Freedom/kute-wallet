// The market lists build lazily (market_groups.dart): a category of
// several hundred markets builds only the rows and the cards near the
// viewport, the grouped rows and the cards of their own alike (founder,
// 25 November 2026, the Investing list on a laptop: "extreme lag").

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/shared/market_groups.dart';
import 'package:kute/theme/app_theme.dart';

void main() {
  Future<Set<String>> pumpList(WidgetTester tester,
      {required List<String> items,
      required bool Function(String) groups,
      ScrollController? controller}) async {
    final built = <String>{};
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(extensions: [AppColorsExtension.light()]),
        home: Scaffold(
          body: Builder(
            builder: (context) => CustomScrollView(
              controller: controller,
              slivers: marketGroupSlivers<String>(
                context,
                items: items,
                groups: groups,
                dividerIndent: 64,
                build: (s, inGroup) {
                  built.add(s);
                  return SizedBox(height: 56, child: Text(s));
                },
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return built;
  }

  testWidgets('a long grouped list builds only the rows near the viewport',
      (tester) async {
    final items = [for (var i = 0; i < 500; i++) 'r$i'];
    final controller = ScrollController();
    final built = await pumpList(tester,
        items: items, groups: (_) => true, controller: controller);
    // 600 px of view and the cache: a few dozen rows, never the 500.
    expect(built.length, lessThan(40));
    expect(built, contains('r0'));
    expect(built, isNot(contains('r499')));

    // A jump lays out the rows on the way (a list of rows of unknown
    // height has to); what stays built is again only what is near.
    controller.jumpTo(56.0 * 300);
    await tester.pump();
    expect(find.text('r305'), findsOneWidget);
    expect(find.byType(Text).evaluate().length, lessThan(40));
    expect(find.text('r0'), findsNothing);
  });

  testWidgets('a long run of cards of their own is built lazily too',
      (tester) async {
    // Upper case: a card of its own (a Predictions event with outcomes).
    final items = [for (var i = 0; i < 300; i++) 'C$i'];
    final built = await pumpList(tester,
        items: items, groups: (s) => s == s.toLowerCase());
    expect(built.length, lessThan(30));
    expect(built, contains('C0'));
    expect(built, isNot(contains('C299')));
    // The same gap between the cards as before.
    final first = tester.getRect(find.text('C0'));
    final second = tester.getRect(find.text('C1'));
    expect(second.top - first.bottom, closeTo(marketSegmentGap(), 0.01));
  });

  testWidgets('cards and groups keep their order and gaps when they mix',
      (tester) async {
    final items = ['a', 'b', 'X', 'Y', 'c', 'Z'];
    await pumpList(tester, items: items, groups: (s) => s == s.toLowerCase());
    final tops = [for (final s in items) tester.getRect(find.text(s)).top];
    for (var i = 1; i < tops.length; i++) {
      expect(tops[i], greaterThan(tops[i - 1]), reason: items[i]);
    }
    expect(
        tester.getRect(find.text('Y')).top -
            tester.getRect(find.text('X')).bottom,
        closeTo(marketSegmentGap(), 0.01));
  });
}
