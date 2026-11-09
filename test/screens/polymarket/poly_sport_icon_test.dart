// A Sports row's icon, in order: Polymarket's own glyph, bundled; else the
// league's Gamma image; else, or when that image fails, the Sports trophy.
// Always its full size, so a row never moves while an image lands.

import 'dart:async';
import 'dart:io';

// ignore: depend_on_referenced_packages
import 'package:file/file.dart' as fs;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/screens/polymarket/components/poly_browse_bar.dart';
import 'package:kute/screens/polymarket/components/poly_crest_image.dart';
import 'package:kute/screens/polymarket/components/poly_sport_icon.dart';
import 'package:kute/theme/app_theme.dart';

/// Artwork that fails, or stays in flight until [gate] completes.
class _Artwork implements BaseCacheManager {
  final Completer<fs.File>? gate;
  _Artwork({this.gate});

  @override
  Future<fs.File> getSingleFile(String url,
      {String key = '', Map<String, String> headers = const {}}) {
    if (gate != null) return gate!.future;
    return Future.error(const SocketException('offline'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A league's chip as `/sports` makes it: its key is the series, its route
/// the Gamma code.
PolySub _league(String code, {String? image}) =>
    PolySub('series:$code', route: code, label: code, imageUrl: image);

const _gamma = 'https://polymarket-upload.example/league-icons/x.png';

Future<void> _pump(WidgetTester tester, Widget child,
        {bool dark = false}) =>
    tester.pumpWidget(MaterialApp(
      theme: ThemeData(
        brightness: dark ? Brightness.dark : Brightness.light,
        extensions: [
          dark ? AppColorsExtension.dark() : AppColorsExtension.light()
        ],
      ),
      home: Scaffold(body: Center(child: child)),
    ));

Finder _svg(String asset) => find.byWidgetPredicate((w) =>
    w is SvgPicture &&
    w.bytesLoader is SvgAssetLoader &&
    (w.bytesLoader as SvgAssetLoader).assetName == asset);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => PolyCrestImage.debugCacheManager = null);

  /// Every key the Sports row and its pinned leagues draw from the bundle.
  /// NBA, MLB, College Football and the Nations League are the four the
  /// site has no vector of its mark for: see the folder's README.
  const fromGamma = {'nba', 'mlb', 'cfb', 'unl'};
  final subs = [
    const PolySub('live'),
    const PolySub('futures'),
    for (final s in kPolySportGroups) PolySub(s),
    for (final c in kPolySportsPinnedLeagues)
      if (!fromGamma.contains(c)) _league(c),
  ];

  for (final dark in [false, true]) {
    test(
        'every Sports row and pinned league resolves to a bundled glyph that '
        'exists and parses (${dark ? 'dark' : 'light'})', () async {
      for (final sub in subs) {
        final asset = polySportIconAsset(sub, dark: dark);
        expect(asset, isNotNull, reason: sub.route);
        final text = await rootBundle.loadString(asset!);
        expect(text, contains('<svg'), reason: asset);
        final info = await vg.loadPicture(SvgAssetLoader(asset), null);
        expect(info.size.isEmpty, isFalse, reason: asset);
        info.picture.dispose();
      }
    });
  }

  test('the glyphs keep their own colours, Futures alone the text\'s',
      () async {
    for (final sub in subs) {
      final text = await rootBundle.loadString(polySportIconAsset(sub)!);
      if (sub.key == 'futures') {
        expect(text, contains('currentColor'));
      } else {
        expect(text, isNot(contains('currentColor')), reason: sub.key);
        expect(text, matches(RegExp(r'#[0-9a-fA-F]{6}')), reason: sub.key);
      }
    }
    // Navy on the site's light theme, a lighter blue on its dark one.
    expect(await rootBundle.loadString(polySportIconAsset(const PolySub('football'))!),
        contains('#00457B'));
    expect(
        await rootBundle.loadString(
            polySportIconAsset(const PolySub('football'), dark: true)!),
        contains('#60a5fa'));
    // Soccer's green is the same on both.
    expect(polySportIconAsset(const PolySub('soccer'), dark: true),
        polySportIconAsset(const PolySub('soccer')));
  });

  test('the leagues with no vector of their mark are not bundled', () {
    for (final code in fromGamma) {
      expect(polySportIconAsset(_league(code)), isNull, reason: code);
    }
  });

  group('the order', () {
    testWidgets('the bundled glyph first, even with a Gamma image',
        (tester) async {
      await _pump(tester,
          PolySportIcon(sub: _league('nfl', image: _gamma), size: 20));
      expect(_svg('lib/assets/polymarket_tags/sports/nfl.svg'), findsOneWidget);
      expect(find.byType(PolyCrestImage), findsNothing);
    });

    testWidgets('else the league\'s Gamma image', (tester) async {
      PolyCrestImage.debugCacheManager = _Artwork(gate: Completer());
      await _pump(
          tester, PolySportIcon(sub: _league('lal', image: _gamma), size: 20));
      final crest = tester.widget<PolyCrestImage>(find.byType(PolyCrestImage));
      expect(crest.url, _gamma);
      expect(crest.size, 20);
      expect(crest.fit, BoxFit.contain);
    });

    testWidgets('else the trophy', (tester) async {
      await _pump(tester, PolySportIcon(sub: _league('lal'), size: 20));
      expect(find.byType(PolySportTrophy), findsOneWidget);
      expect(find.byType(PolyCrestImage), findsNothing);
    });

    testWidgets('dark mode takes the dark glyph', (tester) async {
      await _pump(tester, const PolySportIcon(sub: PolySub('football'), size: 20),
          dark: true);
      expect(_svg('lib/assets/polymarket_tags/sports/football.dark.svg'),
          findsOneWidget);
    });
  });

  testWidgets('a failed network image falls back to the trophy, nothing broken',
      (tester) async {
    PolyCrestImage.debugCacheManager = _Artwork();
    await _pump(
        tester, PolySportIcon(sub: _league('lal', image: _gamma), size: 20));
    expect(find.byType(PolySportTrophy), findsNothing);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(find.byType(PolySportTrophy), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(PolySportIcon)), const Size(20, 20));
  });

  testWidgets('a network icon holds its size while it loads', (tester) async {
    PolyCrestImage.debugCacheManager = _Artwork(gate: Completer());
    await _pump(
        tester, PolySportIcon(sub: _league('lal', image: _gamma), size: 20));
    expect(tester.getSize(find.byType(PolySportIcon)), const Size(20, 20));
  });

  testWidgets('every drill pill of Sports leads with its icon at the text\'s '
      'height', (tester) async {
    late double size;
    await tester.pumpWidget(ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) {
          size = 14.sp;
          return const SizedBox();
        }));
    for (final sub in [
      const PolySub('live'),
      const PolySub('soccer'),
      _league('nfl', image: _gamma),
      _league('lal', image: _gamma),
      _league('lal'),
    ]) {
      final logo = polySubLogo(PolyPill.sports, sub);
      expect(logo, isA<PolySportIcon>(), reason: sub.key);
      expect((logo! as PolySportIcon).size, size);
    }
  });
}
