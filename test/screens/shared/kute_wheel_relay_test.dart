// The wheel over a market page's right column scrolls the page (founder,
// 25 November 2026: "we should be able to scroll down on the right side
// if the mouse is there").

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/shared/kute_desk_market.dart';

void main() {
  testWidgets('a wheel turn over the column scrolls the page beside it',
      (tester) async {
    final left = GlobalKey();
    final page = ScrollController();
    final list = ScrollController();
    addTearDown(page.dispose);
    addTearDown(list.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Row(children: [
        Expanded(
          child: KeyedSubtree(
            key: left,
            child: SingleChildScrollView(
              controller: page,
              child: const SizedBox(height: 3000),
            ),
          ),
        ),
        SizedBox(
          width: 300,
          child: KuteWheelRelay(
            target: left,
            child: Column(children: [
              const SizedBox(height: 200, child: Text('buttons')),
              // A list in the column that can scroll takes its own turn.
              SizedBox(
                height: 200,
                child: ListView(controller: list, children: const [
                  SizedBox(height: 600),
                ]),
              ),
            ]),
          ),
        ),
      ]),
    ));

    Future<void> wheel(Offset at, double dy) async {
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      pointer.hover(at);
      await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
      await tester.pump();
    }

    final size = tester.getSize(find.byType(MaterialApp));
    final overButtons = Offset(size.width - 150, 100);
    final overList = Offset(size.width - 150, 300);

    await wheel(overButtons, 120);
    expect(page.offset, 120, reason: 'the page scrolls from over the column');

    await wheel(overList, 100);
    expect(list.offset, 100, reason: 'the column\'s own list scrolls first');
    expect(page.offset, 120);

    // At its end the list lets the page take the turn.
    await wheel(overList, 1000);
    expect(list.offset, list.position.maxScrollExtent);
    await wheel(overList, 80);
    expect(page.offset, 200);
  });
}
