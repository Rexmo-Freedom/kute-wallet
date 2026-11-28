// The left navigation's open section folds shut and opens again (founder,
// 25 November 2026: "allow to close things like Investing please").

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/usd/dollars_desk_nav.dart';
import 'package:kute/theme/app_theme.dart';

void main() {
  testWidgets('a click on the open section closes it, the next opens it',
      (tester) async {
    var picked = 'a';
    var bTaps = 0;
    Widget build() => ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => MaterialApp(
          theme: ThemeData(
              fontFamily: 'Inter', extensions: [AppColorsExtension.light()]),
          home: Scaffold(
            body: SizedBox(
              width: 240,
              child: StatefulBuilder(
                builder: (context, setState) => DollarsDeskNav(
                  sections: [
                    (
                      key: const ValueKey('dollars-desk-nav-investing'),
                      label: 'Investing',
                      selected: picked == 'a',
                      onTap: () => setState(() => picked = 'a'),
                    ),
                    (
                      key: const ValueKey('dollars-desk-nav-predictions'),
                      label: 'Predictions',
                      selected: picked == 'b',
                      onTap: () => setState(() {
                        picked = 'b';
                        bTaps++;
                      }),
                    ),
                  ],
                  categories: const Text('its categories'),
                ),
              ),
            ),
          ),
        ));
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    expect(find.text('its categories'), findsOneWidget);
    expect(find.byIcon(Icons.expand_more_rounded), findsOneWidget);

    await tester.tap(find.text('Investing'));
    await tester.pumpAndSettle();
    expect(find.text('its categories'), findsNothing,
        reason: 'the open section is closed by a click');
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    expect(picked, 'a', reason: 'closing does not change what is picked');

    await tester.tap(find.text('Investing'));
    await tester.pumpAndSettle();
    expect(find.text('its categories'), findsOneWidget);

    // Shut, then another section picked: that one opens.
    await tester.tap(find.text('Investing'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Predictions'));
    await tester.pumpAndSettle();
    expect(bTaps, 1);
    expect(find.text('its categories'), findsOneWidget);
  });
}
