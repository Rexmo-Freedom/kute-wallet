import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/shared/service_tab_strip.dart';
import 'package:kute/theme/app_theme.dart';

Widget _wrap(Widget child) => ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(extensions: [AppColorsExtension.light()]),
        home: Scaffold(body: Center(child: child)),
      ),
    );

ServiceTabData _tab(String label, {bool active = false}) => ServiceTabData(
    icon: Icons.circle, label: label, active: active, onTap: () {});

void main() {
  testWidgets('a plain strip keeps every label on screen, no animation',
      (tester) async {
    await tester.pumpWidget(_wrap(ServiceTabStrip(
      plain: true,
      tabs: [_tab('Bitcoin', active: true), _tab('Investments')],
    )));
    expect(find.text('Bitcoin'), findsOneWidget);
    expect(find.text('Investments'), findsOneWidget);
    // Both tabs share the width equally.
    final widths = tester
        .widgetList<Expanded>(find.byType(Expanded))
        .map((e) => e.flex)
        .toList();
    expect(widths, [1, 1]);
  });

  testWidgets('the sliding strip still hides inactive labels',
      (tester) async {
    await tester.pumpWidget(_wrap(ServiceTabStrip(
      tabs: [_tab('Wallet', active: true), _tab('Investing'), _tab('Predictions')],
    )));
    await tester.pumpAndSettle();
    expect(find.text('Wallet'), findsOneWidget);
    expect(find.text('Investing'), findsNothing);
    expect(find.text('Predictions'), findsNothing);
  });
}
