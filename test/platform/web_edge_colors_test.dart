// The colours the web hands Safari for its bands (web_edge_colors.dart):
// what is drawn at the app's top and bottom edges, a sheet's colour at the
// bottom, the app's background where a plain box keeps its colour
// private, and a sheet's dimming over the page at the top.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/platform/web_edge_colors.dart';

void main() {
  const red = Color(0xFFD9485A);
  const page = Color(0xFFFFFFFF);

  testWidgets('a sheet\'s colour at the bottom edge, the page at the top',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(children: [
        const Positioned.fill(
            child: DecoratedBox(decoration: BoxDecoration(color: page))),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 300,
          child: Container(
            decoration: const BoxDecoration(
                color: red,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          ),
        ),
      ]),
    ));
    final view = tester.view;
    expect(webEdgeColorAt(view, const Offset(2, 799), Colors.black), red);
    expect(webEdgeColorAt(view, const Offset(2, 1), Colors.black, top: true),
        page);
  });

  testWidgets('a plain coloured field that says its colour (the scanner)',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(children: [
        const Positioned.fill(
            child: DecoratedBox(decoration: BoxDecoration(color: page))),
        const Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 500,
          child: WebEdgeColor(
              color: Colors.black, child: ColoredBox(color: Colors.black)),
        ),
      ]),
    ));
    final view = tester.view;
    expect(webEdgeColorAt(view, const Offset(2, 799), page),
        const Color(0xFF000000));
    // Above the field the page is still the page.
    expect(webEdgeColorAt(view, const Offset(2, 1), Colors.red, top: true),
        page);
  });

  testWidgets('nothing opaque: the fallback, a sheet\'s dimming blended on',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const ColoredBox(color: Colors.blue));
    final view = tester.view;
    expect(webEdgeColorAt(view, const Offset(2, 1), page), page);
    expect(
        webEdgeColorAt(view, const Offset(2, 1), page, dim: Colors.black54),
        Color.alphaBlend(Colors.black54, page));
  });
}
