// The brag cards as images, for a look by eye: a big win (with its
// all-time line, and without it: the top positions' rows), a small win, a
// loss, flat, and the positions (a winning prediction, a losing Investing
// position), at 1080 × 1350 with Sal's real stills.
// Every frame lays out without an overflow; the PNGs are written only
// when asked:
//
//   BRAG_FRAMES=<dir> flutter test test/screens/share/brag/brag_render_test.dart
//
// Asked, the renders go to the network for the real logos a phone would
// load: the coins' (HlCoinIcon) and two live Polymarket pictures for the
// prediction rows (an esports crest, an economy market's picture).

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/share/brag/brag_card.dart';
import 'package:kute/screens/share/brag/brag_data.dart';
import 'package:kute/screens/share/cards/share_card_frame.dart'
    show ShareCardSal;
import 'package:kute/theme/app_theme.dart';

import 'brag_fixtures.dart';
import '../cards/share_card_test_fonts.dart' show loadShareCardSal;
import 'brag_test_fonts.dart';
import '../share_artwork.dart';

/// A live Polymarket event's picture for [tag] (its first team's crest
/// when it has teams); null offline.
Future<String?> _livePicture(String tag) async {
  final client = HttpClient();
  try {
    final req = await client
        .getUrl(Uri.parse('https://gamma-api.polymarket.com/events/keyset'
            '?closed=false&order=volume24hr&ascending=false&limit=10'
            '&tag_slug=$tag'))
        .timeout(const Duration(seconds: 10));
    final res = await req.close().timeout(const Duration(seconds: 10));
    final body = jsonDecode(await res.transform(utf8.decoder).join());
    for (final e in (body is Map ? body['events'] as List? : null) ?? []) {
      if (e is! Map) continue;
      for (final t in (e['teams'] as List? ?? const [])) {
        final logo = t is Map ? t['logo'] as String? : null;
        if (logo != null && logo.isNotEmpty) return logo;
      }
      final image = e['image'] as String?;
      if (image != null && image.isNotEmpty) return image;
    }
  } catch (_) {
  } finally {
    client.close(force: true);
  }
  return null;
}

void main() {
  final dir = Platform.environment['BRAG_FRAMES'];

  testWidgets('brag cards render to PNG', (tester) async {
    await tester.runAsync(loadBragFonts);
    ShareCardSal.debugReset();
    addTearDown(ShareCardSal.debugReset);
    await tester.runAsync(loadShareCardSal);
    expect(ShareCardSal.peek(), isNotNull, reason: "Sal's face decodes");
    tester.view.physicalSize = const Size(1080, 1350);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    String? geng;
    String? fed;
    if (dir != null) {
      HttpOverrides.global = null;
      useShareTestArtwork(online: true);
      geng = await tester.runAsync<String?>(() => _livePicture('esports'));
      fed = await tester.runAsync<String?>(() => _livePicture('economy'));
    }
    final frames = <String, BragData>{
      'portfolio_series': fakeBragPortfolio(series: kFakeBragPortfolioSeries),
      'big_win': fakeBragPortfolio(gengImage: geng, fedImage: fed),
      'small_win': fakeBragSmallWinPortfolio(),
      'loss': fakeBragLosingPortfolio(),
      'flat': fakeBragFlatPortfolio(),
      'position_win': fakeBragPosition(),
      'position_loss': fakeBragLosingPosition(),
    };
    for (final MapEntry(key: name, value: data) in frames.entries) {
      final key = GlobalKey();
      final app = ScreenUtilInit(
          designSize: const Size(430, 932),
          builder: (_, __) => MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: ThemeData(
                    fontFamily: 'Inter',
                    extensions: [AppColorsExtension.light()]),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: Align(
                  alignment: Alignment.topLeft,
                  child: RepaintBoundary(
                    key: key,
                    child: BragCard(data: data, mark: ShareCardSal.peek()),
                  ),
                ),
              ));
      if (dir == null) {
        await tester.pumpWidget(app);
      } else {
        // Built on real time so the logos load over the network.
        await tester.runAsync(() async {
          await tester.pumpWidget(app);
          await Future<void>.delayed(const Duration(seconds: 4));
          // The artwork resolved: its image decodes on real time too.
          await tester.pump();
          await Future<void>.delayed(const Duration(seconds: 1));
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 500));
        });
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull, reason: '$name overflowed');
      if (dir == null) continue;
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: kBragCardPixelRatio);
        expect(image.width, 1080);
        expect(image.height, 1350);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory(dir).createSync(recursive: true);
        File('$dir/brag_$name.png').writeAsBytesSync(png!.buffer.asUint8List());
      });
    }
    // The logo fetches' timeouts, run out.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });
}
