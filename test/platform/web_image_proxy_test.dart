// Pictures through the backend's image routes on the web: the two
// upstream hosts map to their routes (nothing else does), a missing
// picture is remembered for the session and never asked again, at most
// four requests run at once, and the bytes are kept in a bounded cache.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/platform/web_image_proxy.dart';

void main() {
  setUp(() {
    WebImageProxy.debugReset();
    WebImageProxy.baseOverride = () => 'https://backend.example';
  });
  tearDown(WebImageProxy.debugReset);

  test('the two hosts map to their routes, nothing else does', () {
    expect(
        WebImageProxy.proxied(
            'https://polymarket-upload.s3.us-east-2.amazonaws.com/BTC+fullsize.png'),
        'https://backend.example/api/v1/img/pm/BTC+fullsize.png');
    expect(
        WebImageProxy.proxied(
            'https://polymarket-upload.s3.us-east-2.amazonaws.com/a%20b.jpeg'),
        'https://backend.example/api/v1/img/pm/a%20b.jpeg');
    expect(WebImageProxy.proxied('https://app.hyperliquid.xyz/coins/xyz:SOXL.svg'),
        'https://backend.example/api/v1/img/hl/xyz:SOXL.svg');
    expect(WebImageProxy.proxied('https://app.hyperliquid.xyz/coins/BTC.png'),
        isNull);
    expect(WebImageProxy.proxied('https://app.hyperliquid.xyz/trade/BTC.svg'),
        isNull);
    expect(WebImageProxy.proxied('https://assets.parqet.com/logos/symbol/AAPL'),
        isNull);
    expect(WebImageProxy.proxied('http://polymarket-upload.s3.us-east-2.amazonaws.com/x.png'),
        isNull);
    WebImageProxy.baseOverride = () => null;
    expect(
        WebImageProxy.proxied(
            'https://polymarket-upload.s3.us-east-2.amazonaws.com/x.png'),
        isNull);
  });

  test('a missing picture is asked once and remembered', () async {
    const url = 'https://polymarket-upload.s3.us-east-2.amazonaws.com/gone.png';
    var asked = 0;
    WebImageProxy.fetch = (_) async {
      asked++;
      return null; // 404
    };
    WebImageProxy.debugWeb = true;
    expect(WebImageProxy.drawable(url), isTrue);
    expect(await WebImageProxy.load(url), isNull);
    expect(await WebImageProxy.load(url), isNull);
    expect(asked, 1);
    expect(WebImageProxy.missing(url), isTrue);
    expect(WebImageProxy.drawable(url), isFalse);
  });

  test('at most four requests at once; bytes held afterwards', () async {
    final gates = <Completer<Uint8List?>>[];
    var running = 0, most = 0;
    WebImageProxy.fetch = (_) {
      running++;
      if (running > most) most = running;
      final c = Completer<Uint8List?>();
      gates.add(c);
      return c.future.whenComplete(() => running--);
    };
    final loads = [
      for (var i = 0; i < 10; i++)
        WebImageProxy.load(
            'https://polymarket-upload.s3.us-east-2.amazonaws.com/$i.png')
    ];
    await Future<void>.delayed(Duration.zero);
    expect(running, WebImageProxy.parallel);
    while (gates.any((g) => !g.isCompleted)) {
      for (final g in gates.where((g) => !g.isCompleted).toList()) {
        g.complete(Uint8List.fromList([1, 2, 3]));
      }
      await Future<void>.delayed(Duration.zero);
    }
    final got = await Future.wait(loads);
    expect(got.every((b) => b != null), isTrue);
    expect(most, lessThanOrEqualTo(WebImageProxy.parallel));
    expect(
        WebImageProxy.held(
            'https://polymarket-upload.s3.us-east-2.amazonaws.com/3.png'),
        isNotNull);
  });

  test('off the web nothing is drawable', () {
    expect(
        WebImageProxy.drawable(
            'https://polymarket-upload.s3.us-east-2.amazonaws.com/x.png'),
        isFalse);
  });

  test('an SVG body is told from a raster', () {
    expect(webImageIsSvg(Uint8List.fromList('<svg></svg>'.codeUnits)), isTrue);
    expect(
        webImageIsSvg(Uint8List.fromList('<?xml version="1.0"?><svg/>'.codeUnits)),
        isTrue);
    expect(webImageIsSvg(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47])), isFalse);
  });
}
