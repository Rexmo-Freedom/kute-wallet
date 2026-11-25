// The app's one back / close chassis (founder, 4 November 2026: "X
// buttons across the app are not very fintech-like"): a 40 circle in a
// soft tint of the ink with a thin drawn glyph, a 44 touch target, the
// press on KuteMotion's spring, the same in light and dark; and a sheet
// header's close sits centred on the title's first line.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/theme/app_theme.dart';

Future<void> _pump(WidgetTester tester, Widget child,
    {bool dark = false, bool reduceMotion = false}) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(430, 932),
    builder: (_, __) => MaterialApp(
      theme: dark ? buildDarkTheme() : buildLightTheme(),
      home: MediaQuery(
        data: MediaQueryData(
            size: const Size(430, 932), disableAnimations: reduceMotion),
        child: Scaffold(body: Center(child: child)),
      ),
    ),
  ));
}

/// The tinted circle a button draws.
Finder _circle(Finder button) => find.descendant(
    of: button,
    matching: find.byWidgetPredicate((w) =>
        w is AnimatedContainer &&
        w.decoration is ShapeDecoration &&
        (w.decoration as ShapeDecoration).shape is CircleBorder));

Color _fill(WidgetTester tester, Finder button) =>
    ((tester.widget<AnimatedContainer>(_circle(button)).decoration
            as ShapeDecoration)
        .color)!;

KuteNavGlyphPainter _glyph(WidgetTester tester, Finder button) =>
    tester
        .widget<CustomPaint>(find.descendant(
            of: button,
            matching: find.byWidgetPredicate(
                (w) => w is CustomPaint && w.painter is KuteNavGlyphPainter)))
        .painter as KuteNavGlyphPainter;

double _scale(WidgetTester tester, Finder button) => tester
    .widget<AnimatedScale>(
        find.descendant(of: button, matching: find.byType(AnimatedScale)))
    .scale;

void main() {
  testWidgets(
      'close and back: a 40 circle, a 44 target, the thin drawn X and '
      'chevron in the ink, read out as Close and Back', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(
        tester,
        Row(mainAxisSize: MainAxisSize.min, children: [
          KuteCloseButton(onPressed: () {}),
          KuteCircleBackButton(onPressed: () {}),
        ]));
    final close = find.byType(KuteCloseButton);
    final back = find.byType(KuteCircleBackButton);
    expect(tester.getSize(close), const Size(44, 44));
    expect(tester.getSize(back), const Size(44, 44));
    expect(tester.getSize(_circle(close)), const Size(40, 40));
    expect(tester.getSize(_circle(back)), const Size(40, 40));
    final c = AppColorsExtension.light();
    expect(_glyph(tester, close).glyph, KuteNavGlyph.close);
    expect(_glyph(tester, back).glyph, KuteNavGlyph.back);
    expect(_glyph(tester, close).color, c.textPrimary);
    // No Material font icon, no ripple: the glyph is drawn.
    expect(find.byType(Icon), findsNothing);
    expect(find.byType(InkWell), findsNothing);
    expect(find.bySemanticsLabel('Close'), findsOneWidget);
    expect(find.bySemanticsLabel('Back'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('the tint: the ink at 6% in light and 10% in dark',
      (tester) async {
    await _pump(tester, KuteCloseButton(onPressed: () {}));
    final light = AppColorsExtension.light();
    expect(_fill(tester, find.byType(KuteCloseButton)),
        light.textPrimary.withValues(alpha: 0.06));

    await _pump(tester, KuteCloseButton(onPressed: () {}), dark: true);
    await tester.pumpAndSettle();
    final dark = AppColorsExtension.dark();
    expect(_fill(tester, find.byType(KuteCloseButton)),
        dark.textPrimary.withValues(alpha: 0.10));
    expect(_glyph(tester, find.byType(KuteCloseButton)).color,
        dark.textPrimary);
  });

  testWidgets(
      'held: the circle sinks to 92% and its tint deepens; released it '
      'comes back and the tap runs once', (tester) async {
    var taps = 0;
    await _pump(tester, KuteCloseButton(onPressed: () => taps++));
    final close = find.byType(KuteCloseButton);
    final gesture = await tester.startGesture(tester.getCenter(close));
    await tester.pump(const Duration(milliseconds: 150));
    expect(_scale(tester, close), kKuteNavPressScale);
    final c = AppColorsExtension.light();
    expect(_fill(tester, close), c.textPrimary.withValues(alpha: 0.12));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_scale(tester, close), 1.0);
    expect(_fill(tester, close), c.textPrimary.withValues(alpha: 0.06));
    expect(taps, 1);
  });

  testWidgets('under Reduce Motion nothing moves on a press', (tester) async {
    await _pump(tester, KuteCloseButton(onPressed: () {}), reduceMotion: true);
    final close = find.byType(KuteCloseButton);
    final gesture = await tester.startGesture(tester.getCenter(close));
    await tester.pump(const Duration(milliseconds: 150));
    expect(_scale(tester, close), 1.0);
    await gesture.up();
    await tester.pump();
  });

  testWidgets(
      'on a narrow phone the box keeps its scaled layout, and the touch '
      'target still reaches 44', (tester) async {
    var taps = 0;
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: buildLightTheme(),
        home: Scaffold(
            body: Center(child: KuteCloseButton(onPressed: () => taps++))),
      ),
    ));
    final close = find.byType(KuteCloseButton);
    final rect = tester.getRect(close);
    // 44 design units at 375 / 430.
    expect(rect.width, closeTo(44 * 375 / 430, 0.01));
    // Just outside the laid-out box, inside the 44 logical target.
    await tester.tapAt(rect.centerLeft - const Offset(2, 0));
    await tester.pump();
    expect(taps, 1);
    // Past the 44 target: nothing.
    await tester.tapAt(rect.center - const Offset(24, 0));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('the edge of the 44 target still takes the tap',
      (tester) async {
    var taps = 0;
    await _pump(tester, KuteCircleBackButton(onPressed: () => taps++));
    final rect = tester.getRect(find.byType(KuteCircleBackButton));
    // 1 px inside the target, outside the 40 circle.
    await tester.tapAt(rect.topLeft + const Offset(1, 1));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('held while busy: no tap, faded', (tester) async {
    var taps = 0;
    await _pump(
        tester, KuteCloseButton(enabled: false, onPressed: () => taps++));
    await tester.tap(find.byType(KuteCloseButton));
    await tester.pump();
    expect(taps, 0);
    expect(
        tester
            .widget<Opacity>(find.descendant(
                of: find.byType(KuteCloseButton),
                matching: find.byType(Opacity)))
            .opacity,
        lessThan(1));
  });

  testWidgets(
      'the pill hugs its icon and word in a wide row, 40 tall in a 44 '
      'target', (tester) async {
    await _pump(
        tester,
        SizedBox(
          width: 400,
          child: Wrap(alignment: WrapAlignment.end, children: [
            KuteCirclePillButton(
                icon: Icons.settings_rounded,
                label: 'Settings',
                onPressed: () {}),
          ]),
        ));
    final pill = find.byType(KuteCirclePillButton);
    expect(tester.getSize(pill).width, lessThan(200));
    expect(tester.getSize(pill).height, 44);
    final face = find.descendant(
        of: pill,
        matching: find.byWidgetPredicate((w) =>
            w is AnimatedContainer &&
            (w.decoration as ShapeDecoration?)?.shape is StadiumBorder));
    expect(tester.getSize(face).height, 40);
  });

  testWidgets('with no handler the close pops its route', (tester) async {
    await _pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const Scaffold(
                    body: Center(child: KuteCloseButton())))),
            child: const Text('open'),
          ),
        ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(KuteCloseButton), findsOneWidget);
    await tester.tap(find.byType(KuteCloseButton));
    await tester.pumpAndSettle();
    expect(find.byType(KuteCloseButton), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets(
      'a sheet header: the close is the shared one, centred on the '
      "title's first line", (tester) async {
    await _pump(
        tester,
        const SizedBox(
          width: 430,
          child: AppBottomSheetHeader(
            title: 'Rules and resolution',
            subtitle: 'How this market settles',
            trailing: AppBottomSheetCloseButton(),
          ),
        ));
    final close = find.byType(KuteCloseButton);
    expect(close, findsOneWidget);
    final title = tester.getRect(find.text('Rules and resolution'));
    final lineCentre = title.top + 28 * 1.05 / 2;
    expect(tester.getCenter(close).dy, closeTo(lineCentre, 1.5));
    expect(tester.takeException(), isNull);
  });
}
