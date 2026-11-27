// The wide web layout's search lives in the top bar at every width
// (founder, 27 November 2026): the home tabs' content column starts right
// under the bar, with no search row of its own, and still tells the
// floating bar the search is up there (topSearch), so the pill stays
// away; the phone layout builds no field. (The web is forced with
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

  testWidgets('wide: no search row over the column; the pill stays away',
      (tester) async {
    await pump(tester, const Size(1440, 900));
    expect(find.byKey(const ValueKey('kute-top-search-field')), findsNothing);
    expect(tester.getTopLeft(find.text('first card')).dy, lessThan(20));
    expect(kuteBarPane.value?.topSearch, isTrue);
  });

  testWidgets('phone: no field (the pill stays)', (tester) async {
    await pump(tester, const Size(430, 932));
    expect(find.byKey(const ValueKey('kute-top-search-field')), findsNothing);
    expect(kuteBarPane.value, isNull);
  });
}
