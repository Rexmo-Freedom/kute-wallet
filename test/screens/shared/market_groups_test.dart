// The Investments market lists' grouping (market_groups.dart): runs of
// groupable markets share Home Activity's grouped card, every other market
// keeps its own card and breaks the run.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/shared/animations/premium_group_container.dart';
import 'package:kute/screens/shared/market_groups.dart';
import 'package:kute/theme/app_theme.dart';

void main() {
  test('consecutive groupable markets share a segment; others stand alone',
      () {
    final segs = marketSegments(['a', 'b', 'X', 'c', 'Y', 'Z', 'd', 'e', 'f'],
        (s) => s == s.toLowerCase());
    expect([for (final s in segs) (s.items.join(), s.grouped)], [
      ('ab', true),
      ('X', false),
      ('c', true),
      ('Y', false),
      ('Z', false),
      ('def', true),
    ]);
    expect(marketSegments(const <String>[], (_) => true), isEmpty);
  });

  testWidgets(
      'the column form: one Home Activity group per run with inset '
      'hairlines, a card of its own in between', (tester) async {
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(extensions: [AppColorsExtension.light()]),
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: marketGroupColumn<String>(
                context,
                items: const ['a', 'b', 'c', 'X', 'd'],
                groups: (s) => s == s.toLowerCase(),
                dividerIndent: 64,
                build: (s, inGroup) => SizedBox(
                    height: 50, child: Text(inGroup ? 'row $s' : 'card $s')),
              ),
            ),
          ),
        ),
      ),
    ));
    final groups = find.byType(PremiumGroupContainer);
    expect(groups, findsNWidgets(2));
    expect(find.descendant(of: groups.at(0), matching: find.byType(Divider)),
        findsNWidgets(2));
    expect(find.descendant(of: groups.at(1), matching: find.byType(Divider)),
        findsNothing);
    expect(tester.widget<Divider>(find.byType(Divider).first).indent, 64);
    expect(find.text('card X'), findsOneWidget);
    expect(find.descendant(of: groups, matching: find.text('card X')),
        findsNothing);
    for (final r in ['row a', 'row b', 'row c', 'row d']) {
      expect(find.text(r), findsOneWidget);
    }
  });

  test('the page grid fills its columns evenly, row by row', () {
    List<int> sizes(int n, int count) => [
          for (final c in marketGridDealEven<int>(
              List.generate(n, (i) => i), count,
              groups: (_) => true))
            c.length
        ];
    // Five indices in four columns: 2 · 2 · 1, never 2 · 1 · 1 · 1.
    expect(sizes(5, 4), [2, 2, 1, 0]);
    expect(sizes(9, 4), [3, 3, 3, 0]);
    expect(sizes(10, 4), [3, 3, 2, 2]);
    expect(sizes(8, 4), [2, 2, 2, 2]);
    // Read along the top row first.
    expect(
        marketGridDealEven<int>([0, 1, 2, 3, 4], 4, groups: (_) => true)
            .map((c) => c.isEmpty ? null : c.first),
        [0, 1, 2, null]);
    // Cards of their own: dealt by height, as before.
    expect(
        marketGridDealEven<int>([0, 1, 2], 2, groups: (i) => i != 0),
        marketGridDeal<int>([0, 1, 2], 2, weight: (i) => i != 0 ? 1 : 3));
  });
}
