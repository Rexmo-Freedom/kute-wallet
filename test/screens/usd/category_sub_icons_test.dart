// EVERY ROW ITS OWN ICON (founder, 9 November 2026, of the Esports screen,
// every game on the same controller: "i dont get why all sub categories are
// not getting a svg, fix it"; then "check on all sub categories").
//
//   * Every fixed row key resolves to a bundled SVG that exists and parses,
//     in light and dark, or to Polymarket's hosted image.
//   * The order: Polymarket's own SVG, its hosted image, the topic's glyph.
//   * A failed or offline image draws the topic's glyph at the same size;
//     one in flight holds the square, so nothing moves.
//   * The sheet, walked row by row on every screen (each Predictions topic
//     and the Sports league level, Investing on Hyperliquid and its Tradfi
//     and Crypto rows): no row wears its parent's icon or a sibling's, but
//     for the named exemptions below.
//
// The screens are written as PNGs when asked, the hosted images drawn from
// files named after the URL's last segment:
//
//   SUB_ICONS_FRAMES=<dir> SUB_ICONS_ARTWORK=<dir> flutter test test/screens/usd/category_sub_icons_test.dart

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

// ignore: depend_on_referenced_packages
import 'package:file/file.dart' as fs;
// ignore: depend_on_referenced_packages
import 'package:file/local.dart' show LocalFileSystem;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_site_order.dart';
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
import 'package:kute/screens/polymarket/components/poly_crest_image.dart';
import 'package:kute/screens/polymarket/components/poly_sport_icon.dart';
import 'package:kute/screens/usd/investments_category_sheet.dart';
import 'package:kute/screens/usd/usd_account_screen.dart' show InvestmentsTab;
import 'package:kute/theme/app_theme.dart';

import '../../helpers/offline_venue_overrides.dart';
import 'investments_harness.dart';

final _frames = Platform.environment['SUB_ICONS_FRAMES'] ?? '';
final _artwork = Platform.environment['SUB_ICONS_ARTWORK'] ?? '';

/// Rows allowed to share an icon on their screen, and why. Each is
/// polymarket's own choice: Gamma gives these leagues its generic ball for
/// the sport, the same file, and the site draws them that way too.
const Map<String, String> kSharedIconExemptions = {
  'nirl1': 'Gamma soccer ball placeholder',
  'wsl': 'Gamma soccer ball placeholder',
  'idn1': 'Gamma soccer ball placeholder',
  'idn2': 'Gamma soccer ball placeholder',
  'aze1': 'Gamma soccer ball placeholder',
  'tha1': 'Gamma soccer ball placeholder',
  'canpl': 'Gamma soccer ball placeholder',
  'cricshield': 'Gamma cricket ball placeholder',
  'cricmcat20': 'Gamma cricket ball placeholder',
  'vb2bundesliga': 'Gamma volleyball placeholder',
  'vbdivisao1': 'Gamma volleyball placeholder',
  'vbligueaw': 'Gamma volleyball placeholder',
  'vbbelligaa': 'Gamma volleyball placeholder',
  'vbligueb': 'Gamma volleyball placeholder',
};

/// Gamma `/sports` images, 9 November 2026: a few leagues of each sport
/// that has placeholders, the placeholders among them.
const _kS3 = 'https://polymarket-upload.s3.us-east-2.amazonaws.com';
const _kSoccerBall = '$_kS3/soccer ball-bba4025f77.png';
const _kCricketBall = '$_kS3/cricket-ball-a0b0bf2dc9.png';
const _kVolleyball = '$_kS3/vball-6b6648595f.png';
const Map<String, List<(String, String)>> _kLeagues = {
  'soccer': [
    ('epl', '$_kS3/league-icons/epl-24885021.png'),
    ('lal', '$_kS3/league-icons/lal.png'),
    ('nirl1', _kSoccerBall),
    ('wsl', _kSoccerBall),
    ('tha1', _kSoccerBall),
  ],
  'cricket': [
    ('crint', '$_kS3/league-icons/crint.png'),
    ('cricshield', _kCricketBall),
    ('cricmcat20', _kCricketBall),
  ],
  'volleyball': [
    ('vbplusliga', '$_kS3/league-icons/vbplusliga.png'),
    ('vbligueb', _kVolleyball),
    ('vbdivisao1', _kVolleyball),
  ],
};

HlMarket _market(String coin,
        {String category = 'crypto',
        bool isHip3 = false,
        double vlm = 1e6,
        double prev = 99}) =>
    HlMarket(
      coin: coin,
      wireCoin: coin,
      assetId: 0,
      kind: HlMarketKind.perp,
      szDecimals: 2,
      maxLeverage: 20,
      onlyIsolated: false,
      markPx: 100,
      midPx: 100,
      prevDayPx: prev,
      dayNtlVlm: vlm,
      category: category,
      isHip3: isHip3,
      dex: isHip3 ? 'xyz' : '',
    );

/// A Hyperliquid universe with several markets in every sector and class.
final _universe = [
  for (final (i, c) in const [
    'BTC', 'ETH', 'SOL', 'XRP', 'AVAX', // layer 1
    'ARB', 'OP', 'MNT', // layer 2
    'AAVE', 'UNI', 'LINK', // defi
    'TAO', 'FET', 'WLD', // ai
    'DOGE', 'WIF', 'kPEPE', // meme
    'APE', 'GALA', 'SAND', // gaming
    'ZZA', 'ZZB', 'ZZC', // other
  ].indexed)
    _market(c, vlm: 1e9 - i * 1e7, prev: 100 - (i % 7) - 1),
  for (final (i, (c, cat)) in const [
    ('xyz:AAPL', 'stocks'), ('xyz:TSLA', 'stocks'), ('xyz:NVDA', 'stocks'),
    ('xyz:SPX', 'indices'), ('xyz:NDX', 'indices'), ('xyz:DJI', 'indices'),
    ('xyz:GOLD', 'commodities'), ('xyz:SILVER', 'commodities'),
    ('xyz:CL', 'commodities'),
    ('xyz:EUR', 'fx'), ('xyz:JPY', 'fx'), ('xyz:GBP', 'fx'),
    ('xyz:OPENAI', 'preipo'), ('xyz:SPACEX', 'preipo'),
    ('xyz:ANTHROPIC', 'preipo'),
  ].indexed)
    _market(c, category: cat, isHip3: true, vlm: 5e8 - i * 1e6, prev: 98),
];

/// The topics' rows as the site lists them (the dated snapshot).
List<PolySub> _topicRows(PolyPill pill) => [
      for (final r in kPolySiteTopicRowsSnapshot[pill.key] ??
          const <Map<String, String>>[])
        PolySub('tag:${r['id']}', route: r['slug']!, label: r['label']),
    ];

/// The artwork: files of [_artwork] by the URL's last segment, else a
/// failure (no network in a test).
class _LocalArtwork implements BaseCacheManager {
  @override
  Future<fs.File> getSingleFile(String url,
      {String key = '', Map<String, String> headers = const {}}) async {
    final name = Uri.parse(url).pathSegments.last;
    final file = const LocalFileSystem().file('$_artwork/$name');
    if (_artwork.isNotEmpty && await file.exists()) return file;
    throw const HttpException('no local artwork');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Artwork that fails, or stays in flight until [gate] completes.
class _Offline implements BaseCacheManager {
  final Completer<fs.File>? gate;
  _Offline({this.gate});

  @override
  Future<fs.File> getSingleFile(String url,
      {String key = '', Map<String, String> headers = const {}}) {
    if (gate != null) return gate!.future;
    return Future.error(const SocketException('offline'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sports extends SportsLiveNotifier {
  @override
  Map<String, SportsMatchUpdate> build() => {};
  @override
  void connect() {}
}

class _Feed extends PolyFeedNotifier {
  @override
  PolyFeedState build(PolyFeedQuery arg) => const PolyFeedState(done: true);
}

List<Override> _predictionsOverrides() => [
      ...offlineVenueOverrides,
      polyBrowseFeedProvider.overrideWith(_Feed.new),
      sportsLiveProvider.overrideWith(_Sports.new),
      polyTopicSubsProvider
          .overrideWith((ref, pill) => Stream.value(_topicRows(pill))),
      polyCryptoSubsProvider
          .overrideWith((ref) => Stream.value(polyCryptoSubsFromCounts(null))),
      polyEsportsSubsProvider
          .overrideWith((ref) => Stream.value(polyEsportsSubsFrom())),
      polySportsSubsProvider
          .overrideWith((ref) => polySportsSubsFromLeagues(const [])),
      polySportLeagueSubsProvider.overrideWith((ref, sport) => [
            PolySub(sport),
            for (final (code, image)
                in _kLeagues[sport] ?? const <(String, String)>[])
              PolySub('series:$code',
                  route: code, label: code.toUpperCase(), imageUrl: image),
          ]),
    ];

List<Override> _investingOverrides() => [
      hyperliquidBrowseUniverseProvider
          .overrideWithValue(AsyncValue.data(_universe)),
      hyperliquidBuilderMarketsMissingProvider.overrideWithValue(false),
    ];

Future<void> _frames8(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _openSheet(WidgetTester tester, InvestmentsTab tab,
    {required List<Override> overrides, bool dark = false}) async {
  await pumpInvestments(
    tester,
    dark: dark,
    size: const Size(402, 1500),
    browseInvesting: true,
    browsePredictions: true,
    overrides: overrides,
    child: Scaffold(
      body: Consumer(
        builder: (context, ref, _) => Center(
          child: TextButton(
            onPressed: () => showInvestmentsCategorySheet(context, ref, tab),
            child: const Text('Open categories'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open categories'));
  await _frames8(tester);
}

Finder _tile(String key) => find.byKey(ValueKey('category-tile-$key'));

Future<void> _drill(WidgetTester tester, String key) async {
  await tester.ensureVisible(_tile(key));
  await tester.pump();
  await tester.tap(_tile(key));
  await _frames8(tester);
}

/// What a tile draws as its icon: the resolved glyph or image of a row
/// ([PolySubIcon]'s key), its topic's glyph, or the coins of its stack.
String _iconOf(WidgetTester tester, Finder tile) {
  final keyed = find.descendant(
      of: tile,
      matching: find.byWidgetPredicate((w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('poly-sub-icon-')));
  if (keyed.evaluate().isNotEmpty) {
    return (tester.widget(keyed.first).key! as ValueKey<String>)
        .value
        .substring('poly-sub-icon-'.length);
  }
  final glyph = find.descendant(
      of: tile, matching: find.byWidgetPredicate((w) => w is PolyPillGlyph));
  if (glyph.evaluate().isNotEmpty) {
    return polyPillGlyphAsset(tester.widget<PolyPillGlyph>(glyph.first).pill);
  }
  final svg = find.descendant(
      of: tile,
      matching: find.byWidgetPredicate(
          (w) => w is SvgPicture && w.bytesLoader is SvgAssetLoader));
  if (svg.evaluate().isNotEmpty) {
    return (tester.widget<SvgPicture>(svg.first).bytesLoader as SvgAssetLoader)
        .assetName;
  }
  final coins = [
    for (final c in tester.widgetList<HlCoinIcon>(
        find.descendant(of: tile, matching: find.byType(HlCoinIcon))))
      c.coin,
  ];
  return coins.isEmpty ? '' : 'coins:${coins.join(',')}';
}

/// The tiles on screen whose keys are [keys], each with its icon.
Map<String, String> _icons(WidgetTester tester, Iterable<String> keys) => {
      for (final k in keys)
        if (_tile(k).evaluate().isNotEmpty) k: _iconOf(tester, _tile(k).last),
    };

/// Fails on a row that wears [parent] or a sibling's icon, but for
/// [kSharedIconExemptions].
void _expectDistinct(String screen, Map<String, String> rows, String parent) {
  final byIcon = <String, List<String>>{};
  for (final e in rows.entries) {
    expect(e.value, isNotEmpty, reason: '$screen ${e.key}: no icon');
    byIcon.putIfAbsent(e.value, () => []).add(e.key);
  }
  for (final e in rows.entries) {
    final route = e.key.startsWith('series:') ? e.key.substring(7) : e.key;
    if (kSharedIconExemptions.containsKey(route)) continue;
    expect(e.value, isNot(parent),
        reason: '$screen ${e.key} wears its parent\'s icon');
    expect(byIcon[e.value], [e.key],
        reason: '$screen ${e.key} shares ${e.value}');
  }
}

/// Per screen: rows, and how many wear an icon of their own.
final _counts = <String, (int, int)>{};

Future<void> _shot(WidgetTester tester, String name) async {
  if (_frames.isEmpty) return;
  // The artwork's file reads and decodes run on real time.
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
  }
  await tester.runAsync(() async {
    final view = tester.binding.renderViews.first;
    final layer = view.debugLayer! as OffsetLayer;
    final image = await layer.toImage(Offset.zero & view.size, pixelRatio: 2);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_frames).createSync(recursive: true);
    File('$_frames/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

Future<void> _loadInter() async {
  final inter = FontLoader('Inter');
  for (final f in ['Regular', 'SemiBold', 'Bold']) {
    inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
  }
  await inter.load();
}

Future<void> _pump(WidgetTester tester, Widget child, {bool dark = false}) =>
    tester.pumpWidget(MaterialApp(
      theme: ThemeData(
        brightness: dark ? Brightness.dark : Brightness.light,
        extensions: [
          dark ? AppColorsExtension.dark() : AppColorsExtension.light()
        ],
      ),
      home: Scaffold(body: Center(child: child)),
    ));

/// Every fixed row of every topic with rows, by pill.
Map<PolyPill, List<PolySub>> _fixedRows() => {
      PolyPill.crypto: [
        for (final s in polyCryptoSubsFromCounts(null))
          if (s.key != 'all') s,
      ],
      PolyPill.finance: [
        for (final k in kPolyFinanceSubs)
          if (k != 'all') PolySub(k),
      ],
      PolyPill.weather: [
        for (final k in kPolyWeatherSubs)
          if (k != 'all') PolySub(k),
      ],
      PolyPill.breaking: [
        for (final k in kPolyBreakingTopics)
          if (k != 'all') PolySub(k),
      ],
      PolyPill.esports: [
        for (final s in polyEsportsSubsFrom())
          if (s.key != 'all') s,
      ],
      for (final p in const [
        PolyPill.politics,
        PolyPill.geopolitics,
        PolyPill.tech,
        PolyPill.culture,
        PolyPill.economy,
      ])
        p: _topicRows(p),
    };

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadInter();
  });
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    PolyCrestImage.debugCacheManager = _LocalArtwork();
  });
  tearDown(() => PolyCrestImage.debugCacheManager = null);
  tearDownAll(() {
    for (final e in _counts.entries) {
      // ignore: avoid_print
      print('rows ${e.key}: ${e.value.$2} of ${e.value.$1} with their own');
    }
  });

  group('the resolver', () {
    for (final dark in [false, true]) {
      test(
          'every fixed row resolves to a bundled SVG that exists and parses, '
          'or to a hosted image (${dark ? 'dark' : 'light'})', () async {
        for (final MapEntry(key: pill, value: rows) in _fixedRows().entries) {
          for (final sub in rows) {
            final asset = polySubIconAsset(pill, sub, dark: dark);
            final url = polySubImageUrl(pill, sub);
            expect(asset != null || url != null, isTrue,
                reason: '${pill.key} ${sub.route} has no icon of its own');
            if (asset == null) {
              expect(Uri.parse(url!).scheme, 'https', reason: url);
              continue;
            }
            final text = await rootBundle.loadString(asset);
            expect(text, contains('<svg'), reason: asset);
            final info = await vg.loadPicture(SvgAssetLoader(asset), null);
            expect(info.size.isEmpty, isFalse, reason: asset);
            info.picture.dispose();
          }
        }
      });
    }

    test('every bundled row glyph is in the text\'s colour, every esports '
        'glyph in the site\'s colours but Call of Duty\'s', () async {
      for (final glyph in {
        for (final m in kPolyRowGlyphs.values) ...m.values,
        ...kPolyTopicRowGlyphs.values,
      }) {
        final text = await rootBundle
            .loadString('lib/assets/polymarket_tags/rows/$glyph.svg');
        expect(text, contains('currentColor'), reason: glyph);
        expect(text, isNot(matches(RegExp(r'#[0-9a-fA-F]{3,6}\b'))),
            reason: glyph);
      }
      for (final slug in kPolyEsportsIconKeys) {
        final text = await rootBundle
            .loadString('lib/assets/polymarket_tags/esports/$slug.svg');
        if (slug == 'call-of-duty') {
          expect(text, contains('currentColor'));
        } else {
          expect(text, matches(RegExp(r'#[0-9a-fA-F]{6}')), reason: slug);
        }
      }
    });

    test('no two rows of a screen share an icon, none wears its topic\'s',
        () {
      for (final MapEntry(key: pill, value: rows) in _fixedRows().entries) {
        _expectDistinct(
            pill.key,
            {
              for (final s in rows)
                s.key: polySubIconAsset(pill, s) ?? polySubImageUrl(pill, s)!,
            },
            polyPillGlyphAsset(pill));
      }
    });

    test('the order: the site\'s SVG, then the hosted image, then the glyph',
        () {
      // An esports game draws its bundled glyph, even with a Gamma image.
      const game = PolySub('cs2',
          label: 'CS2', imageUrl: '$_kS3/league-icons/cs2.png');
      expect(polySubIconAsset(PolyPill.esports, game),
          'lib/assets/polymarket_tags/esports/cs2.svg');
      // Brood War: its card image, not Gamma's `sc` (StarCraft II's logo).
      const broodWar = PolySub('starcraft-brood-war',
          label: 'StarCraft: Brood War',
          imageUrl: '$_kS3/league-icons/sc.png');
      expect(polySubIconAsset(PolyPill.esports, broodWar), isNull);
      expect(polySubImageUrl(PolyPill.esports, broodWar),
          '$_kS3/starcraftbroodwar-77405089c8.jpg');
      // A topic row with a glyph of the site's set beats its market image.
      const apple = PolySub('tag:1097', route: 'apple', label: 'Apple');
      expect(polySubIconAsset(PolyPill.tech, apple),
          'lib/assets/polymarket_tags/rows/apple.svg');
      // Finance's Stocks: the site draws an image, not a glyph.
      expect(polySubIconAsset(PolyPill.finance, const PolySub('stocks')),
          isNull);
      expect(polySubImageUrl(PolyPill.finance, const PolySub('stocks')),
          '$_kS3/equities-2-ea04b2d05c.png');
      // A coin carries its own logo.
      final btc = polyCryptoSubsFromCounts(null)
          .firstWhere((s) => s.key == 'bitcoin');
      expect(polySubImageUrl(PolyPill.crypto, btc), btc.imageUrl);
      // A topic row's own image wins over the dated one.
      expect(
          polySubImageUrl(
              PolyPill.politics,
              const PolySub('tag:126',
                  route: 'trump', imageUrl: 'https://x.example/own.png')),
          'https://x.example/own.png');
      // A row the site adds later: nothing of its own.
      const later = PolySub('tag:9', route: 'later', label: 'Later');
      expect(polySubHasOwnIcon(PolyPill.politics, later), isFalse);
      // Breaking's rows are topics: each its topic's glyph.
      expect(polySubIconAsset(PolyPill.breaking, const PolySub('world')),
          'lib/assets/polymarket_tags/geopolitics.svg');
    });

    testWidgets('a row with nothing of its own draws its topic\'s glyph',
        (tester) async {
      await _pump(
          tester,
          const PolySubIcon(
              pill: PolyPill.politics,
              sub: PolySub('tag:9', route: 'later', label: 'Later'),
              size: 20));
      final glyph = tester.widget<PolyPillGlyph>(find.byType(PolyPillGlyph));
      expect(glyph.pill, PolyPill.politics);
      expect(tester.getSize(find.byType(PolySubIcon)), const Size(20, 20));
    });

    for (final dark in [false, true]) {
      testWidgets(
          'a failed image draws the topic\'s glyph at the same size, no '
          'broken image (${dark ? 'dark' : 'light'})', (tester) async {
        PolyCrestImage.debugCacheManager = _Offline();
        const trump = PolySub('tag:126', route: 'trump', label: 'Trump');
        await _pump(
            tester,
            const PolySubIcon(pill: PolyPill.politics, sub: trump, size: 20),
            dark: dark);
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
        expect(find.byType(PolyPillGlyph), findsOneWidget);
        expect(find.byType(Image), findsNothing);
        expect(tester.getSize(find.byType(PolySubIcon)), const Size(20, 20));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('an image in flight holds its square: nothing moves',
        (tester) async {
      final gate = Completer<fs.File>();
      PolyCrestImage.debugCacheManager = _Offline(gate: gate);
      await _pump(
          tester,
          PolySubIcon(
              pill: PolyPill.finance,
              sub: const PolySub('stocks'),
              size: 20));
      expect(tester.getSize(find.byType(PolySubIcon)), const Size(20, 20));
      expect(find.byType(PolyPillGlyph), findsNothing);
    });
  });

  group('the sheet, every row', () {
    testWidgets('Predictions: every topic\'s rows, and the league level',
        (tester) async {
      PolyCrestImage.debugCacheManager = _Offline();
      final screens = _fixedRows();
      for (final MapEntry(key: pill, value: rows) in screens.entries) {
        await _openSheet(tester, InvestmentsTab.predictions,
            overrides: _predictionsOverrides());
        if (_tile(pill.key).evaluate().isEmpty) {
          await unmountInvestments(tester);
          continue;
        }
        await _drill(tester, pill.key);
        final icons = _icons(tester, [for (final s in rows) s.key]);
        expect(icons.length, rows.length, reason: '${pill.key}: rows shown');
        _expectDistinct(pill.key, icons, polyPillGlyphAsset(pill));
        _counts[pill.key] = (
          icons.length,
          icons.values.where((v) => v != polyPillGlyphAsset(pill)).length
        );
        await unmountInvestments(tester);
      }

      // Sports, and the league level of the sports with placeholders.
      await _openSheet(tester, InvestmentsTab.predictions,
          overrides: _predictionsOverrides());
      await _drill(tester, PolyPill.sports.key);
      final sports = [
        for (final s in polySportsSubsFromLeagues(const []))
          if (s.key != PolyPill.sports.defaultSub) s.key,
      ];
      final sportIcons = _icons(tester, sports);
      expect(sportIcons.length, sports.length);
      _expectDistinct('sports', sportIcons, polyPillGlyphAsset(PolyPill.sports));
      _counts['sports'] = (sportIcons.length, sportIcons.length);
      for (final sport in _kLeagues.keys) {
        await _drill(tester, sport);
        final keys = [for (final (c, _) in _kLeagues[sport]!) 'series:$c'];
        final leagueIcons = _icons(tester, keys);
        expect(leagueIcons.length, keys.length, reason: sport);
        _expectDistinct('sports/$sport', leagueIcons,
            polyPillGlyphAsset(PolyPill.sports));
        await unmountInvestments(tester);
        await _openSheet(tester, InvestmentsTab.predictions,
            overrides: _predictionsOverrides());
        await _drill(tester, PolyPill.sports.key);
      }
      await unmountInvestments(tester);
    });

    testWidgets('Investing on Hyperliquid: every category and its rows',
        (tester) async {
      await _openSheet(tester, InvestmentsTab.investing,
          overrides: _investingOverrides());
      final tabs = [
        for (final t in HlBrowseTab.values)
          if (_tile(t.key).evaluate().isNotEmpty) t,
      ];
      expect(tabs, isNotEmpty);
      final top = _icons(tester, [for (final t in tabs) t.key]);
      _expectDistinct('investing', top, '');
      _counts['investing'] = (top.length, top.length);
      for (final t in [HlBrowseTab.tradfi, HlBrowseTab.crypto]) {
        if (!tabs.contains(t)) continue;
        await _drill(tester, t.key);
        final subs = hlSubsForTab(t, _universe);
        expect(subs, isNotEmpty, reason: t.key);
        final icons = _icons(tester, [for (final s in subs) s.key]);
        expect(icons.length, subs.length, reason: t.key);
        _expectDistinct('investing/${t.key}', icons, _iconOf(tester, _tile(t.key).last));
        _counts['investing/${t.key}'] = (icons.length, icons.length);
        await unmountInvestments(tester);
        await _openSheet(tester, InvestmentsTab.investing,
            overrides: _investingOverrides());
      }
      await unmountInvestments(tester);
    });
  });

  testWidgets('renders: Esports, Crypto, Politics and Finance, Esports dark',
      (tester) async {
    if (_frames.isEmpty) return;
    for (final (pill, dark) in const [
      (PolyPill.esports, false),
      (PolyPill.crypto, false),
      (PolyPill.politics, false),
      (PolyPill.finance, false),
      (PolyPill.esports, true),
      (PolyPill.geopolitics, false),
      (PolyPill.tech, false),
      (PolyPill.culture, false),
      (PolyPill.economy, false),
      (PolyPill.weather, false),
      (PolyPill.breaking, false),
      (PolyPill.crypto, true),
      (PolyPill.politics, true),
    ]) {
      await _openSheet(tester, InvestmentsTab.predictions,
          overrides: _predictionsOverrides(), dark: dark);
      await _drill(tester, pill.key);
      await _shot(tester, '${pill.key}_${dark ? 'dark' : 'light'}');
      await unmountInvestments(tester);
    }
  });
}
