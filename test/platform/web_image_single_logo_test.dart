// On the web a remote logo is an `<img>` platform view, and on Safari each
// one costs Flutter a full-screen WebGL canvas: seven logos on the Dollars
// home held five canvases, nine WebGL contexts and a footprint that kept
// growing until the phone's browser reloaded the page. Founder, 26 November
// 2026: "Only show logos when opening the screen, so we only show 1 at the
// time." So a list or grid row never builds the `<img>` view (it draws its
// own stand-in), a market's own screen (WebImagesOn) still does, and the
// view goes when that screen closes. The `<img>` path is forced on the VM,
// where the view is an empty box.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/platform/web_image.dart';

void main() {
  String url(int i) => 'https://logos.test/$i.svg';

  setUp(() {
    WebImageViews.debugForceWeb = true;
    for (var i = 0; i < 20; i++) {
      WebImageLoader.debugSeedLoaded(url(i));
    }
  });

  tearDown(() {
    WebImageViews.debugReset();
    WebImageLoader.debugReset();
    WebCovers.debugReset();
  });

  Widget logo(int i) => WebNetworkImage(
        key: ValueKey('img-$i'),
        url: url(i),
        width: 32,
        height: 32,
        error: Text('monogram $i'),
      );

  Finder views() => find.byKey(const ValueKey('web-network-img'));

  testWidgets('a list of markets never builds an <img> view', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(children: [for (var i = 0; i < 20; i++) logo(i)]),
      ),
    ));
    await tester.pump();
    expect(views(), findsNothing);
    expect(WebImageViews.live, 0);
    // The row's own stand-in, as when a logo is missing.
    expect(find.text('monogram 0'), findsOneWidget);
  });

  testWidgets(
      'a market\'s own screen draws its one logo, and gives the view back '
      'when it closes', (tester) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: nav,
      home: Scaffold(
        body: ListView(children: [for (var i = 0; i < 5; i++) logo(i)]),
      ),
    ));
    for (var round = 0; round < 3; round++) {
      nav.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => Scaffold(body: WebImagesOn(child: logo(10 + round))),
      ));
      await tester.pumpAndSettle();
      expect(views(), findsOneWidget);
      expect(WebImageViews.live, 1);

      nav.currentState!.pop();
      await tester.pumpAndSettle();
      expect(views(), findsNothing);
      expect(WebImageViews.live, 0);
    }
  });

  test('both market screens wrap their header logo, and only that', () {
    for (final path in [
      'lib/screens/hyperliquid/market_detail_sheet.dart',
      'lib/screens/polymarket/market_detail_sheet.dart',
    ]) {
      final text = File(path).readAsStringSync();
      expect(RegExp(r'WebImagesOn\(').allMatches(text).length, 1,
          reason: path);
    }
    // No other screen opens the scope.
    final others = [
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')))
        if (!f.path.endsWith('market_detail_sheet.dart') &&
            !f.path.endsWith('platform/web_image.dart') &&
            f.readAsStringSync().contains('WebImagesOn('))
          f.path
    ];
    expect(others, isEmpty);
  });
}
