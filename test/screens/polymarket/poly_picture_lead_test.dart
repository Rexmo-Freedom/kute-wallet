// A single market's picture in a slip, sheet or header (PolyPictureLead,
// founder, 27 November 2026: "an empty rounded square where the picture
// belongs"). On the web a picture a backend image route serves is drawn,
// and with none (an uncovered host, a 404, no URL) neither the box nor the
// gap is drawn: the slip's question starts where the picture would have.
// The phones keep the picture and its gap.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/platform/web_image_proxy.dart';
import 'package:kute/screens/polymarket/components/poly_crest_image.dart';
import 'package:kute/screens/polymarket/components/slip_chrome.dart';
import 'package:kute/theme/app_theme.dart';

const _covered =
    'https://polymarket-upload.s3.us-east-2.amazonaws.com/fed-rates.png';
const _uncovered = 'https://example.org/picture.png';

// A 1 x 1 PNG.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

Widget _host(Widget child) => ProviderScope(
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          theme: ThemeData(extensions: [AppColorsExtension.light()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: Align(alignment: Alignment.topLeft, child: child)),
        ),
      ),
    );

Widget _slip(String? image) => SizedBox(
      width: 400,
      child: PolySlipHeader(
          marketQuestion: 'Will the Fed cut rates in December?',
          marketImage: image,
          closable: false),
    );

double _titleLeft(WidgetTester tester) =>
    tester.getTopLeft(find.text('Will the Fed cut rates in December?')).dx;

void main() {
  setUp(() {
    WebImageProxy.debugReset();
    WebImageProxy.baseOverride = () => 'https://backend.test';
  });
  tearDown(() {
    WebImageProxy.debugReset();
    PolyPictureLead.debugWeb = false;
  });

  void web() {
    PolyPictureLead.debugWeb = true;
    WebImageProxy.debugWeb = true;
  }

  testWidgets('web, a host no route covers: no box, no gap', (tester) async {
    web();
    await tester.pumpWidget(_host(_slip(null)));
    final bare = _titleLeft(tester);
    await tester.pumpWidget(_host(_slip(_uncovered)));
    await tester.pump();
    expect(_titleLeft(tester), bare);
    expect(find.byType(WebProxiedPicture), findsNothing);
    expect(find.byType(PolyCrestImage), findsNothing);
  });

  testWidgets('web, a covered picture that is missing: the box goes',
      (tester) async {
    web();
    WebImageProxy.fetch = (_) async => null;
    await tester.pumpWidget(_host(_slip(null)));
    final bare = _titleLeft(tester);
    await tester.pumpWidget(_host(_slip(_covered)));
    await tester.pump();
    await tester.pump();
    expect(_titleLeft(tester), bare);
    expect(WebImageProxy.missing(_covered), isTrue);
  });

  testWidgets('web, a covered picture: drawn small in the canvas, then gap',
      (tester) async {
    web();
    final asked = <String>[];
    WebImageProxy.fetch = (u) async {
      asked.add(u);
      return _png;
    };
    await tester.pumpWidget(_host(_slip(null)));
    final bare = _titleLeft(tester);
    await tester.pumpWidget(_host(_slip(_covered)));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(asked, ['https://backend.test/api/v1/img/pm/fed-rates.png']);
    expect(find.byType(WebProxiedPicture), findsOneWidget);
    expect(_titleLeft(tester), greaterThan(bare + 36));
  });

  testWidgets('phones: the picture and its gap, as before', (tester) async {
    await tester.pumpWidget(_host(_slip(null)));
    final bare = _titleLeft(tester);
    await tester.pumpWidget(_host(_slip(_uncovered)));
    await tester.pump();
    expect(find.byType(PolyCrestImage), findsOneWidget);
    expect(_titleLeft(tester), greaterThan(bare + 36));
  });
}
