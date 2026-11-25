// Every pushed page's motion (kute_page_route.dart): in on the settle
// easing with a 0.97 → 1 scale and a fade, back out on the close easing,
// the platform back swipe kept on iOS; a detail sheet rises from the
// bottom the same way; a fade alone under Reduce Motion.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/shared/kute_page_route.dart';
import 'package:kute/theme/kute_motion.dart';

const _pushed = Key('pushed-page');

Widget _app({bool reduce = false, TargetPlatform platform = TargetPlatform.iOS}) =>
    MaterialApp(
      theme: ThemeData(platform: platform),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(KutePageRoute<void>(
                builder: (_) => const Scaffold(
                    body: Center(child: Text('Detail', key: _pushed))),
              )),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

double _scaleOf(WidgetTester tester) => tester
    .widget<ScaleTransition>(find
        .ancestor(of: find.byKey(_pushed), matching: find.byType(ScaleTransition))
        .first)
    .scale
    .value;

double _opacityOf(WidgetTester tester) => tester
    .widget<FadeTransition>(find
        .ancestor(of: find.byKey(_pushed), matching: find.byType(FadeTransition))
        .first)
    .opacity
    .value;

void main() {
  testWidgets('settles in from 0.97 with a fade, out on the close easing',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final early = _scaleOf(tester);
    expect(early, greaterThan(0.97));
    expect(early, lessThan(1.0));
    expect(_opacityOf(tester), lessThan(1.0));
    await tester.pump(KuteMotion.settleDuration);
    await tester.pump();
    expect(_scaleOf(tester), 1.0);
    expect(_opacityOf(tester), 1.0);

    Navigator.of(tester.element(find.byKey(_pushed))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(_scaleOf(tester), lessThan(1.0));
    await tester.pumpAndSettle();
    expect(find.byKey(_pushed), findsNothing);
  });

  testWidgets('Reduce Motion: a fade alone, no scale', (tester) async {
    await tester.pumpWidget(_app(reduce: true));
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(_scaleOf(tester), 1.0);
    expect(_opacityOf(tester), lessThan(1.0));
    await tester.pumpAndSettle();
    expect(_opacityOf(tester), 1.0);
  });

  testWidgets('a drag from the leading edge past halfway pops the page (iOS)',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byKey(_pushed), findsOneWidget);
    final width = tester.getSize(find.byType(MaterialApp)).width;
    final gesture = await tester.startGesture(const Offset(5, 300));
    await gesture.moveBy(Offset(width * 0.3, 0));
    await tester.pump();
    expect(_scaleOf(tester), lessThan(1.0), reason: 'follows the finger');
    await gesture.moveBy(Offset(width * 0.35, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byKey(_pushed), findsNothing);
  });

  testWidgets('a short drag from the edge settles the page back (iOS)',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final width = tester.getSize(find.byType(MaterialApp)).width;
    final gesture = await tester.startGesture(const Offset(5, 300));
    await gesture.moveBy(Offset(width * 0.2, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byKey(_pushed), findsOneWidget);
    expect(_scaleOf(tester), 1.0);
  });

  testWidgets('on Android the edge is just the page', (tester) async {
    await tester.pumpWidget(_app(platform: TargetPlatform.android));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final width = tester.getSize(find.byType(MaterialApp)).width;
    await tester.dragFrom(const Offset(5, 300), Offset(width * 0.8, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(_pushed), findsOneWidget);
  });

  testWidgets('a detail sheet rises from the bottom, 0.97 → 1, a dim behind',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                KuteSheetPageRoute<void>(
                  barrierColor: Colors.black.withValues(alpha: 0.4),
                  builder: (_) => const Scaffold(
                      body: Center(child: Text('Sheet', key: _pushed))),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final slide = tester.widget<SlideTransition>(find
        .ancestor(of: find.byKey(_pushed), matching: find.byType(SlideTransition))
        .first);
    expect(slide.position.value.dy, greaterThan(0));
    expect(slide.position.value.dy, lessThan(1));
    expect(_scaleOf(tester), lessThan(1.0));
    final route = ModalRoute.of(tester.element(find.byKey(_pushed)))!;
    expect(route, isA<PageRoute<void>>());
    expect((route as PageRoute<void>).fullscreenDialog, isTrue,
        reason: 'the slips pop it as the market sheet');
    await tester.pumpAndSettle();
    expect(slide.position.value.dy, 0);
    expect(_scaleOf(tester), 1.0);
  });
}
