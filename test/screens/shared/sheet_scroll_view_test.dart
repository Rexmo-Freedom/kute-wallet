import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/shared/components/sheet_detail_row.dart';

Widget _sheet(ValueNotifier<double> height, {bool reducedMotion = false}) =>
    MaterialApp(
      builder: (context, child) => MediaQuery(
          data:
              MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
          child: child!),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300, maxWidth: 400),
            child: ValueListenableBuilder<double>(
              valueListenable: height,
              builder: (_, size, __) => SheetScrollView(
                child: SizedBox(
                  height: size,
                  child: const Align(
                    alignment: Alignment.bottomCenter,
                    child: SizedBox(
                        key: ValueKey('last-row'),
                        height: 32,
                        child: Text('Last row')),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('short sheet height updates immediately with reduced motion',
      (tester) async {
    final height = ValueNotifier(100.0);
    addTearDown(height.dispose);
    await tester.pumpWidget(_sheet(height, reducedMotion: true));
    height.value = 200;
    await tester.pump();
    expect(tester.getSize(find.byType(SheetScrollView)).height, 200);
  });
  testWidgets('a capped sheet uses its real scroll extent when content shrinks',
      (tester) async {
    final height = ValueNotifier(1200.0);
    addTearDown(height.dispose);
    await tester.pumpWidget(_sheet(height));
    await tester.drag(
        find.byType(SingleChildScrollView), const Offset(0, -1600));
    await tester.pumpAndSettle();
    final position =
        tester.state<ScrollableState>(find.byType(Scrollable)).position;
    expect(position.pixels, closeTo(900, 0.01));

    // A completed progress block/disclosure removes content. Its child is
    // already shorter on this frame; the scroll extent must agree now.
    height.value = 800;
    await tester.pump();
    expect(position.maxScrollExtent, closeTo(500, 0.01));
    expect(position.pixels, closeTo(500, 0.01));
    final bottom = tester.getRect(find.byType(SingleChildScrollView)).bottom;
    expect(tester.getRect(find.byKey(const ValueKey('last-row'))).bottom,
        closeTo(bottom, 0.01));
    for (var frame = 0; frame < 5; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
      expect(position.pixels, closeTo(500, 0.01),
          reason: 'content updates must not keep dragging the viewport');
    }
  });

  testWidgets('a short sheet still eases to its new height', (tester) async {
    final height = ValueNotifier(100.0);
    addTearDown(height.dispose);
    await tester.pumpWidget(_sheet(height));
    expect(tester.getSize(find.byType(SheetScrollView)).height, 100);
    height.value = 200;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(
        tester.getSize(find.byType(SheetScrollView)).height, greaterThan(100));
    expect(tester.getSize(find.byType(SheetScrollView)).height, lessThan(200));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(SheetScrollView)).height, 200);
  });

  testWidgets(
      'an active drag survives content shrinking and growing at the bottom',
      (tester) async {
    final height = ValueNotifier(1200.0);
    addTearDown(height.dispose);
    await tester.pumpWidget(_sheet(height));
    await tester.drag(
        find.byType(SingleChildScrollView), const Offset(0, -1600));
    await tester.pumpAndSettle();
    final position =
        tester.state<ScrollableState>(find.byType(Scrollable)).position;
    final gesture = await tester
        .startGesture(tester.getCenter(find.byType(SingleChildScrollView)));
    await gesture.moveBy(const Offset(0, -30));
    await tester.pump();

    height.value = 800;
    await tester.pump();
    expect(position.maxScrollExtent, closeTo(500, 0.01));
    expect(position.pixels, closeTo(500, 0.01));
    final bottom = tester.getRect(find.byType(SingleChildScrollView)).bottom;
    expect(tester.getRect(find.byKey(const ValueKey('last-row'))).bottom,
        closeTo(bottom, 0.01));
    await tester.pump(const Duration(milliseconds: 50));
    expect(position.pixels, closeTo(500, 0.01));

    height.value = 1200;
    await tester.pump();
    expect(position.maxScrollExtent, closeTo(900, 0.01));
    expect(position.pixels, closeTo(500, 0.01),
        reason: 'an update must not take over an ongoing drag');
    await gesture.moveBy(const Offset(0, -80));
    await tester.pump();
    expect(position.pixels, greaterThan(500));
    expect(position.pixels, lessThanOrEqualTo(position.maxScrollExtent));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
