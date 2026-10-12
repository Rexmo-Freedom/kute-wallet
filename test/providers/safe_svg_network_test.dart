// A downloaded chain or coin icon that flutter_svg cannot parse shows the
// fallback instead of taking the app down. The parser throws from inside
// the picture's isolate, past `errorBuilder` (an `hsl(285deg …)` fill, a
// `transform="none"` were both fatals on 2.1.0/2.1.1), so the body is
// proven to parse first and a failure is remembered for the session.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/providers/asset_icon_provider.dart';

const _hslGradient = '<svg xmlns="http://www.w3.org/2000/svg" width="48" '
    'height="48"><defs><linearGradient id="g"><stop offset="0" '
    'stop-color="hsl(285deg 60% 50%)"/><stop offset="1" '
    'stop-color="hsl(285deg 60% 20%)"/></linearGradient></defs>'
    '<rect width="48" height="48" fill="url(#g)"/></svg>';

const _transformNone = '<svg xmlns="http://www.w3.org/2000/svg" width="48" '
    'height="48"><g transform="none"><rect width="48" height="48" '
    'fill="#00a86b"/></g></svg>';

const _good = '<svg xmlns="http://www.w3.org/2000/svg" width="48" '
    'height="48"><rect width="48" height="48" fill="#00a86b"/></svg>';

const _bodies = {
  'https://icons.test/hsl.svg': _hslGradient,
  'https://icons.test/none.svg': _transformNone,
  'https://icons.test/good.svg': _good,
};

void main() {
  const fallback = SizedBox(key: ValueKey('fallback'), width: 48, height: 48);
  late List<String> requests;

  setUp(() {
    requests = [];
    SafeSvgNetwork.resetCacheForTest();
    SafeSvgNetwork.debugClient = MockClient((req) async {
      requests.add(req.url.toString());
      final body = _bodies[req.url.toString()];
      if (body == null) return http.Response('', 404);
      return http.Response.bytes(utf8.encode(body), 200,
          headers: {'content-type': 'image/svg+xml'});
    });
  });

  tearDown(() {
    SafeSvgNetwork.debugClient = null;
    SafeSvgNetwork.resetCacheForTest();
  });

  Future<void> pump(WidgetTester tester, String url) async {
    await tester.pumpWidget(MaterialApp(
        home: Center(
            child: SafeSvgNetwork(
                url: url, width: 48, height: 48, fallback: fallback))));
    await tester.pumpAndSettle();
  }

  testWidgets('an hsl() fill the parser rejects shows the fallback',
      (tester) async {
    await pump(tester, 'https://icons.test/hsl.svg');
    expect(find.byKey(const ValueKey('fallback')), findsOneWidget);
    expect(find.byType(SvgPicture), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a transform="none" the parser rejects shows the fallback',
      (tester) async {
    await pump(tester, 'https://icons.test/none.svg');
    expect(find.byKey(const ValueKey('fallback')), findsOneWidget);
    expect(find.byType(SvgPicture), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed body is remembered: no second fetch, no retry',
      (tester) async {
    await pump(tester, 'https://icons.test/none.svg');
    await tester.pumpWidget(const SizedBox());
    await pump(tester, 'https://icons.test/none.svg');
    expect(find.byKey(const ValueKey('fallback')), findsOneWidget);
    expect(requests.where((u) => u.endsWith('none.svg')).length, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a document that parses still draws', (tester) async {
    await pump(tester, 'https://icons.test/good.svg');
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.byKey(const ValueKey('fallback')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
