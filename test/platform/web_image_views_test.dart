// WebImageViews (platform/web_image.dart): on the web a page keeps at most
// [WebImageViews.cap] live `<img>` views, and what is on screen has its
// pictures; an image past the cap draws its stand-in and gets a view as
// it scrolls on screen (founder, 25 November 2026, the Investing list on a
// laptop in six columns: "extreme lag"). The `<img>` path is forced on the
// VM, where the view is an empty box.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/platform/web_image.dart';

void main() {
  const rowHeight = 40.0;
  const count = 200;
  String url(int i) => 'https://logos.test/$i.png';

  setUp(() {
    WebImageViews.debugForceWeb = true;
    for (var i = 0; i < count; i++) {
      WebImageLoader.debugSeedLoaded(url(i));
    }
  });

  tearDown(() {
    WebImageViews.debugReset();
    WebImageLoader.debugReset();
    WebCovers.debugReset();
  });

  Future<ScrollController> pumpList(WidgetTester tester) async {
    final controller = ScrollController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        // The cap's own mechanics, inside the one scope that draws
        // `<img>` views (a market's own screen); lists outside it draw
        // none (web_image_single_logo_test.dart).
        body: WebImagesOn(child: ListView.builder(
          controller: controller,
          itemCount: count,
          itemExtent: rowHeight,
          itemBuilder: (_, i) => Row(children: [
            WebNetworkImage(
              key: ValueKey('img-$i'),
              url: url(i),
              width: 32,
              height: 32,
              error: Text('tile $i'),
            ),
          ]),
        )),
      ),
    ));
    await tester.pump();
    await tester.pump();
    return controller;
  }

  /// The images laid out inside the 800 x 600 test window.
  List<int> onScreen(WidgetTester tester) => [
        for (var i = 0; i < count; i++)
          if (find.byKey(ValueKey('img-$i')).evaluate().isNotEmpty &&
              tester
                  .getRect(find.byKey(ValueKey('img-$i')))
                  .overlaps(Offset.zero & const Size(800, 600)))
            i
      ];

  bool hasView(WidgetTester tester, int i) => find
      .descendant(
          of: find.byKey(ValueKey('img-$i')),
          matching: find.byKey(const ValueKey('web-network-img')))
      .evaluate()
      .isNotEmpty;

  int liveViews() =>
      find.byKey(const ValueKey('web-network-img')).evaluate().length;

  testWidgets('never more live views than the cap', (tester) async {
    WebImageViews.cap = 12;
    await pumpList(tester);
    expect(liveViews(), lessThanOrEqualTo(12));
    expect(WebImageViews.live, lessThanOrEqualTo(12));
    // Fifteen rows on screen, twelve views: three stand-ins.
    expect(onScreen(tester).length, 15);
    expect(find.textContaining('tile '), findsWidgets);
  });

  testWidgets(
      'with room for what is on screen, everything on screen has its view, '
      'also after a scroll', (tester) async {
    // Fifteen rows on screen and the list's cache beyond: more images
    // built than the cap allows.
    WebImageViews.cap = 18;
    final controller = await pumpList(tester);
    for (final i in onScreen(tester)) {
      expect(hasView(tester, i), isTrue, reason: 'row $i');
    }
    expect(WebImageViews.live, lessThanOrEqualTo(18));
    expect(WebImageViews.waiting, greaterThan(0),
        reason: 'the cache holds more images than the cap');

    for (final offset in [300.0, 2000.0, 6000.0, 1000.0]) {
      controller.jumpTo(offset);
      await tester.pump();
      // At worst one frame of stand-in at the edge.
      await tester.pump();
      for (final i in onScreen(tester)) {
        expect(hasView(tester, i), isTrue, reason: 'row $i at $offset');
      }
      expect(liveViews(), lessThanOrEqualTo(18));
    }
  });

  testWidgets('a row scrolled away gives its view back', (tester) async {
    final controller = await pumpList(tester);
    final before = WebImageViews.live;
    expect(before, greaterThan(0));
    controller.jumpTo(rowHeight * (count - 15));
    await tester.pump();
    await tester.pump();
    expect(WebImageViews.live, lessThanOrEqualTo(before + 1));
    await tester.pumpWidget(const SizedBox());
    expect(WebImageViews.live, 0);
  });
}
