// The wide web layout's search: a field pinned at the top of the home
// tabs' content column (KuteBarPane.top), in place of the floating pill;
// the phone layout builds no field. (The web is forced with
// KuteBarPane.debugWeb: the VM is never the web.)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/platform/kute_wide_frames.dart';
import 'package:kute/screens/home/components/kute_shell_bar.dart';
import 'package:kute/theme/app_theme.dart';

void main() {
  setUp(() => KuteBarPane.debugWeb = true);
  tearDown(() {
    KuteBarPane.debugWeb = false;
    kuteBarPane.value = null;
  });

  Future<void> pump(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          theme: ThemeData(extensions: [AppColorsExtension.light()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: KuteBarPane(
              top: const KuteTopSearchField(),
              child: ListView(children: const [Text('first card')]),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('wide: the field sits above the column, with the pill words',
      (tester) async {
    await pump(tester, const Size(1440, 900));
    final field = find.byKey(const ValueKey('kute-top-search-field'));
    expect(field, findsOneWidget);
    expect(find.text('Search or Manage with AI'), findsOneWidget);
    expect(tester.getTopLeft(field).dy,
        lessThan(tester.getTopLeft(find.text('first card')).dy));
    expect(tester.getSize(field).width,
        lessThanOrEqualTo(KuteTopSearchField.maxWidth));
    // The pane tells the bar the field is up, so the pill stays away.
    expect(kuteBarPane.value?.topSearch, isTrue);
  });

  testWidgets('phone: no field (the pill stays)', (tester) async {
    await pump(tester, const Size(430, 932));
    expect(find.byKey(const ValueKey('kute-top-search-field')), findsNothing);
    expect(kuteBarPane.value, isNull);
  });
}
