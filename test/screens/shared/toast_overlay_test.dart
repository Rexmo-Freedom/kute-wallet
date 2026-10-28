// A toast draws on the root overlay and quietly does nothing when there
// is none. `Overlay.of` threw on the root navigator's own context (its
// overlay is a descendant) and on a context whose sheet had closed:
// cancelling a Cash App purchase from Activity was a fatal on iOS.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/theme/app_theme.dart';

ToastMessage _toast(String text) => ToastMessage(
      message: text,
      icon: Icons.check_circle_rounded,
      accentColor: Colors.green,
      duration: const Duration(seconds: 2),
    );

Widget _app(Widget home) => ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(theme: buildLightTheme(), home: home),
    );

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> settle(WidgetTester tester) async {
    // Past the toast's own duration and exit animation.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  }

  testWidgets('shows from the root navigator context, as after a pop',
      (tester) async {
    late BuildContext page;
    await tester.pumpWidget(_app(Scaffold(body: Builder(builder: (ctx) {
      page = ctx;
      return const SizedBox();
    }))));
    final rootContext = Navigator.of(page, rootNavigator: true).context;
    expect(ToastService.overlayFor(rootContext), isNotNull);

    ToastService.show(rootContext, _toast('Purchase cancelled'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Purchase cancelled'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await settle(tester);
  });

  testWidgets('a context with no overlay and no navigator shows nothing',
      (tester) async {
    late BuildContext bare;
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Builder(builder: (ctx) {
        bare = ctx;
        return const SizedBox();
      }),
    ));
    expect(ToastService.overlayFor(bare), isNull);
    ToastService.show(bare, _toast('Nowhere to draw'));
    await tester.pump();
    expect(find.text('Nowhere to draw'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a context whose sheet already closed does nothing',
      (tester) async {
    late BuildContext home;
    await tester.pumpWidget(_app(Scaffold(body: Builder(builder: (ctx) {
      home = ctx;
      return const SizedBox();
    }))));
    BuildContext? sheet;
    showModalBottomSheet<void>(
      context: home,
      builder: (ctx) {
        sheet = ctx;
        return const SizedBox(height: 200);
      },
    );
    await tester.pumpAndSettle();
    expect(sheet, isNotNull);
    Navigator.of(sheet!).pop();
    await tester.pumpAndSettle();
    expect(sheet!.mounted, isFalse);

    expect(ToastService.overlayFor(sheet!), isNull);
    ToastService.show(sheet!, _toast('Too late'));
    await tester.pump();
    expect(find.text('Too late'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
