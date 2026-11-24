// WebCovers (platform/web_image.dart): on the web an image under a sheet
// that is fully up draws its placeholder instead of its `<img>`, so the
// page's logos never show through the sheet. Which images count as under
// a cover is plain route logic, tested here on the VM.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/platform/web_image.dart';

void main() {
  tearDown(WebCovers.debugReset);

  testWidgets('the page under an up cover is covered; the cover is not',
      (tester) async {
    late BuildContext page;
    late BuildContext sheet;
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navKey,
      home: Builder(builder: (c) {
        page = c;
        return const SizedBox();
      }),
    ));
    final route = PageRouteBuilder<void>(
      opaque: false,
      pageBuilder: (c, _, __) => Builder(builder: (c) {
        sheet = c;
        return const SizedBox();
      }),
    );
    navKey.currentState!.push(route);
    await tester.pumpAndSettle();
    expect(WebCovers.covers(page), isFalse, reason: 'no cover is up yet');

    WebCovers.set(route, true);
    expect(WebCovers.covers(page), isTrue);
    expect(WebCovers.covers(sheet), isFalse);

    WebCovers.set(route, false);
    expect(WebCovers.covers(page), isFalse);
  });

  testWidgets('a page in a nested navigator under a root cover is covered',
      (tester) async {
    late BuildContext inner;
    final rootKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: rootKey,
      home: Navigator(
        onGenerateRoute: (_) => MaterialPageRoute<void>(
          builder: (c) {
            inner = c;
            return const SizedBox();
          },
        ),
      ),
    ));
    final route = PageRouteBuilder<void>(
      opaque: false,
      pageBuilder: (_, __, ___) => const SizedBox(),
    );
    rootKey.currentState!.push(route);
    await tester.pumpAndSettle();
    WebCovers.set(route, true);
    expect(WebCovers.covers(inner), isTrue,
        reason: 'the inner page is current in its own navigator, but the '
            'route that holds that navigator is under the cover');
  });
}
