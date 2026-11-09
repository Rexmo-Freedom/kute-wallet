// NO CUT TEXT IN THE PREDICTIONS FILTER (founder, 9 November 2026, on an
// iPhone 16 Pro Max, build 2.2.0 (95): "On the predictions filter, no cut
// text"). Every level of the Predictions category sheet (the topics, the
// "Trending now" themes, every topic's rows, Sports and each sport's
// leagues) and every drill pill row (PolySubRow: a topic's rows, a
// sport's leagues), at 375 pt and 430 pt, in English, Portuguese and
// German, with every card carrying its numbers ("20 markets · $801K vol
// today"): no text on screen ends in an ellipsis or is clipped. A line too
// long is shortened (the volume goes first) or wraps, the card growing
// with its pair (kute_action_cards.dart).
//
// The sheet's levels and the drill rows are written as PNGs, light and
// dark, when asked (the icon audit), the hosted images drawn from files
// named after the URL's last segment and Gamma's whole `/sports`
// directory read from a file:
//
//   NO_CUT_FRAMES=<dir> NO_CUT_ARTWORK=<dir> NO_CUT_SPORTS=<sports.json> \
//     flutter test test/screens/usd/category_sheet_no_cut_test.dart

import 'dart:convert';
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
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_site_order.dart';
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/screens/polymarket/components/poly_browse_bar.dart';
import 'package:kute/screens/polymarket/components/poly_crest_image.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart' show KutePill;
import 'package:kute/screens/usd/investments_category_sheet.dart';
import 'package:kute/screens/usd/usd_account_screen.dart' show InvestmentsTab;
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/offline_venue_overrides.dart';
import 'investments_harness.dart';

final _frames = Platform.environment['NO_CUT_FRAMES'] ?? '';
final _artwork = Platform.environment['NO_CUT_ARTWORK'] ?? '';
final _sportsFile = Platform.environment['NO_CUT_SPORTS'] ?? '';

const _kS3 = 'https://polymarket-upload.s3.us-east-2.amazonaws.com';

/// Gamma `/sports` rows (9 November 2026): the pinned leagues and the
/// longest league names of the sports with a league level.
const List<Map<String, dynamic>> _kDirectory = [
  {'sport': 'nfl', 'name': 'NFL', 'image': '$_kS3/league-icons/nfl-helmet-blue-a1188621.png', 'series': '12185', 'tags': '1,450,100639'},
  {'sport': 'nba', 'name': 'NBA', 'image': '$_kS3/league-icons/nba-7a8bf611.png', 'series': '10345', 'tags': '1,745,100639'},
  {'sport': 'mlb', 'name': 'MLB', 'image': '$_kS3/league-icons/mlb-f4060398.png', 'series': '3', 'tags': '1,100639,100381'},
  {'sport': 'cfb', 'name': 'College Football', 'image': '$_kS3/league-icons/cfb-3ddd4bb7.png', 'series': '12756', 'tags': '1,100351,100639'},
  {'sport': 'ufc', 'name': 'UFC', 'image': '$_kS3/league-icons/ufc-40ea1d2a.png', 'series': '38', 'tags': '1,100639,279'},
  {'sport': 'ucl', 'name': 'UEFA Champions League', 'image': '$_kS3/league-icons/ucl-a369c3d8.png', 'series': '10204', 'tags': '1,100977,100639,1234,100350'},
  {'sport': 'unl', 'name': 'UEFA Nations League', 'image': '$_kS3/league-icons/unl.png', 'series': '11446', 'tags': '1,100639,100350,100816'},
  {'sport': 'epl', 'name': 'Premier League', 'image': '$_kS3/league-icons/epl-24885021.png', 'series': '10188', 'tags': '1,82,306,100639,100350'},
  {'sport': 'irl1', 'name': 'League of Ireland Premier Division', 'image': null, 'series': '11866', 'tags': '1,100639,100350,105245'},
  {'sport': 'wwcquefa', 'name': "UEFA Women's World Cup Qualifiers", 'image': null, 'series': '11846', 'tags': '1,100639,100350,105215'},
  {'sport': 'cricdhakadpl', 'name': 'Dhaka Premier Division Cricket League', 'image': null, 'series': '12572', 'tags': '1,100639,517,105943'},
  {'sport': 'cricdplw', 'name': "Women's Delhi Premier League T20", 'image': null, 'series': '12785', 'tags': '1,100639,517,106169'},
  {'sport': 'bkfibaqam', 'name': 'Americas FIBA World Cup Qualifiers', 'image': null, 'series': '11472', 'tags': '1,100639,28,104351'},
  {'sport': 'bkisrsl', 'name': 'Israeli Basketball Premier League', 'image': null, 'series': '11886', 'tags': '1,100639,28,105268'},
];

List<Map<String, dynamic>> _directory() => _sportsFile.isEmpty
    ? _kDirectory
    : [
        for (final r in jsonDecode(File(_sportsFile).readAsStringSync())
            as List<dynamic>)
          Map<String, dynamic>.from(r as Map),
      ];

/// Twenty markets worth $801K in a day, with no image (so a card keeps the
/// row's own icon): the line the founder saw cut.
final _events = [
  for (var i = 0; i < 20; i++)
    PolymarketEvent(
      id: 'e$i',
      slug: 'e$i',
      title: 'Market $i',
      volume: 1e6,
      volume24hr: 40061.7,
      liquidity: 1e5,
      category: 'sports',
      conditionId: 'c$i',
      outcomes: const [
        PolymarketOutcome(name: 'Yes', price: 0.4),
        PolymarketOutcome(name: 'No', price: 0.6),
      ],
    ),
];

class _Feed extends PolyFeedNotifier {
  @override
  PolyFeedState build(PolyFeedQuery arg) =>
      PolyFeedState(done: true, events: _events);
}

class _Sports extends SportsLiveNotifier {
  @override
  Map<String, SportsMatchUpdate> build() => {};
  @override
  void connect() {}
}

/// The artwork: files of [_artwork] by the URL's last segment, else a
/// failure (no network in a test).
class _LocalArtwork implements BaseCacheManager {
  @override
  Future<fs.File> getSingleFile(String url,
      {String key = '', Map<String, String> headers = const {}}) async {
    final name = Uri.decodeComponent(Uri.parse(url).pathSegments.last);
    final file = const LocalFileSystem().file('$_artwork/$name');
    if (_artwork.isNotEmpty && await file.exists()) return file;
    throw const HttpException('no local artwork');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<PolySub> _topicRows(PolyPill pill) => [
      for (final r in kPolySiteTopicRowsSnapshot[pill.key] ??
          const <Map<String, String>>[])
        PolySub('tag:${r['id']}', route: r['slug']!, label: r['label']),
    ];

List<PolySub> _themes(RuntimeCapabilitiesService policy) =>
    polyTopicSubsFromRows(kPolySiteTrendingThemesSnapshot, policy);

List<Override> _overrides() {
  final directory = _directory();
  return [
    ...offlineVenueOverrides,
    polyBrowseFeedProvider.overrideWith(_Feed.new),
    sportsLiveProvider.overrideWith(_Sports.new),
    polyTopicSubsProvider
        .overrideWith((ref, pill) => Stream.value(_topicRows(pill))),
    polyTrendingThemesProvider.overrideWith(
        (ref) => Stream.value(_themes(ref.read(runtimeCapabilitiesProvider)))),
    polyCryptoSubsProvider
        .overrideWith((ref) => Stream.value(polyCryptoSubsFromCounts(null))),
    polyEsportsSubsProvider
        .overrideWith((ref) => Stream.value(polyEsportsSubsFrom())),
    polySportsSubsProvider
        .overrideWith((ref) => polySportsSubsFromLeagues(directory)),
    polySportLeagueSubsProvider.overrideWith(
        (ref, sport) => polySportLeagueSubs(sport, directory, const [])),
  ];
}

Future<void> _loadInter() async {
  final inter = FontLoader('Inter');
  for (final f in ['Regular', 'SemiBold', 'Bold']) {
    inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
  }
  await inter.load();
}

Future<void> _frames8(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Every text painted under [root] that is cut: past its lines (an
/// ellipsis), or clipped on one line.
List<String> _cut(WidgetTester tester, Finder root) {
  final out = <String>[];
  for (final e in find
      .descendant(of: root, matching: find.byType(RichText))
      .evaluate()) {
    final p = e.renderObject! as RenderParagraph;
    if (!p.attached || !p.hasSize) continue;
    final text = p.text.toPlainText();
    if (text.trim().isEmpty) continue;
    if (p.didExceedMaxLines) {
      out.add('"$text" exceeds its ${p.maxLines} line(s)');
      continue;
    }
    if ((p.maxLines == 1 || !p.softWrap) &&
        p.getMaxIntrinsicWidth(double.infinity) > p.size.width + 0.5) {
      out.add('"$text" clipped');
    }
  }
  // A Text whose ellipsis would show: maxLines and an ellipsis, past them.
  for (final t in tester.widgetList<Text>(
      find.descendant(of: root, matching: find.byType(Text)))) {
    if (t.overflow == TextOverflow.ellipsis && t.maxLines != null) {
      out.add('"${t.data ?? t.textSpan?.toPlainText()}" is set to ellipsise');
    }
  }
  return out;
}

Finder get _sheet => find.byType(AppBottomSheetContainer);
Finder _tile(String key) => find.byKey(ValueKey('category-tile-$key'));

Future<void> _openSheet(WidgetTester tester,
    {required Size size, required Locale locale, bool dark = false}) async {
  await pumpInvestments(
    tester,
    dark: dark,
    locale: locale,
    size: size,
    browsePredictions: true,
    overrides: _overrides(),
    child: Scaffold(
      body: Consumer(
        builder: (context, ref, _) => Center(
          child: TextButton(
            onPressed: () => showInvestmentsCategorySheet(
                context, ref, InvestmentsTab.predictions),
            child: const Text('Open categories'),
          ),
        ),
      ),
    ),
  );
  // Every list the cards read is alive, so every card has its numbers.
  final container = ProviderScope.containerOf(
      tester.element(find.text('Open categories')));
  final queries = <PolyFeedQuery>{const PolyFeedQuery(pill: PolyPill.live)};
  for (final p in PolyPill.values) {
    queries.add(PolyFeedQuery(pill: p, sub: p.defaultSub));
  }
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump();
  final subs = <PolyPill, List<PolySub>>{
    PolyPill.trending: [
      ..._themes(container.read(runtimeCapabilitiesProvider))
    ],
    for (final p in [
      PolyPill.politics,
      PolyPill.geopolitics,
      PolyPill.tech,
      PolyPill.culture,
      PolyPill.economy,
    ])
      p: _topicRows(p),
    PolyPill.crypto: polyCryptoSubsFromCounts(null),
    PolyPill.esports: polyEsportsSubsFrom(),
    PolyPill.finance: [for (final k in kPolyFinanceSubs) PolySub(k)],
    PolyPill.weather: [for (final k in kPolyWeatherSubs) PolySub(k)],
    PolyPill.breaking: [for (final k in kPolyBreakingTopics) PolySub(k)],
    PolyPill.sports: [
      ...polySportsSubsFromLeagues(_directory()),
      for (final sport in kPolySportGroups)
        ...polySportLeagueSubs(sport, _directory(), const []),
    ],
  };
  for (final MapEntry(key: p, value: rows) in subs.entries) {
    for (final s in rows) {
      queries.add(PolyFeedQuery(pill: p, sub: s.key));
    }
  }
  for (final q in queries) {
    container.listen(polyBrowseFeedProvider(q), (_, __) {});
  }
  await tester.tap(find.text('Open categories'));
  await _frames8(tester);
}

Future<void> _shot(WidgetTester tester, String name) async {
  if (_frames.isEmpty) return;
  for (var i = 0; i < 15; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pump(const Duration(milliseconds: 100));
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

/// Scans the sheet's level on screen top to bottom (its list scrolled a
/// screen at a time), adding what is cut to [cut] under [where]; with
/// [shoot] each screen is written as a PNG.
Future<void> _scanLevel(WidgetTester tester, String where, List<String> cut,
    {String? shoot}) async {
  final list = find.descendant(of: _sheet, matching: find.byType(Scrollable));
  final position = tester.state<ScrollableState>(list.first).position;
  position.jumpTo(0);
  await tester.pump();
  for (var page = 0;; page++) {
    for (final c in _cut(tester, _sheet)) {
      cut.add('$where: $c');
    }
    if (shoot != null) await _shot(tester, '${shoot}_$page');
    if (position.pixels >= position.maxScrollExtent - 1) break;
    position.jumpTo((position.pixels + position.viewportDimension * 0.8)
        .clamp(0, position.maxScrollExtent));
    await tester.pump();
  }
}

Future<void> _drill(WidgetTester tester, String key) async {
  await tester.ensureVisible(_tile(key).last);
  await tester.pump();
  await tester.tap(_tile(key).last);
  await _frames8(tester);
}

Future<void> _back(WidgetTester tester) async {
  await tester.tap(find.descendant(
      of: _sheet,
      matching: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.button == true &&
              w.key == const ValueKey('back'))));
  await _frames8(tester);
}

/// The topics with rows of their own, as the sheet opens them.
const _kTopicsWithRows = [
  PolyPill.breaking,
  PolyPill.politics,
  PolyPill.sports,
  PolyPill.crypto,
  PolyPill.esports,
  PolyPill.finance,
  PolyPill.geopolitics,
  PolyPill.tech,
  PolyPill.culture,
  PolyPill.economy,
  PolyPill.weather,
];

/// Walks every level of the sheet: the top, each topic's rows, Sports and
/// each sport's leagues; returns what is cut.
Future<List<String>> _walkSheet(WidgetTester tester,
    {required Size size,
    required Locale locale,
    bool dark = false,
    String? shoot}) async {
  final cut = <String>[];
  final tag = '${locale.languageCode} ${size.width.round()}';
  await _openSheet(tester, size: size, locale: locale, dark: dark);
  await _scanLevel(tester, '$tag top', cut,
      shoot: shoot == null ? null : '${shoot}_top');
  for (final p in _kTopicsWithRows) {
    if (_tile(p.key).evaluate().isEmpty) continue;
    await _drill(tester, p.key);
    await _scanLevel(tester, '$tag ${p.key}', cut,
        shoot: shoot == null ? null : '${shoot}_${p.key}');
    if (p == PolyPill.sports) {
      for (final sport in kPolySportGroups) {
        if (!polySportHasLeagues(sport) || _tile(sport).evaluate().isEmpty) {
          continue;
        }
        await _drill(tester, sport);
        await _scanLevel(tester, '$tag sports/$sport', cut,
            shoot: shoot == null ? null : '${shoot}_sports_$sport');
        await _back(tester);
      }
    }
    await _back(tester);
  }
  await unmountInvestments(tester);
  return cut;
}

/// The drill rows: each topic's PolySubRow, and each sport's league row,
/// as the browser draws them.
Map<String, (PolyPill, List<PolySub>, String?)> _rows() {
  final directory = _directory();
  return {
    for (final p in [
      PolyPill.politics,
      PolyPill.geopolitics,
      PolyPill.tech,
      PolyPill.culture,
      PolyPill.economy,
    ])
      p.key: (p, [const PolySub('all'), ..._topicRows(p)], null),
    'crypto': (PolyPill.crypto, polyCryptoSubsFromCounts(null), null),
    'esports': (PolyPill.esports, polyEsportsSubsFrom(), null),
    'finance': (
      PolyPill.finance,
      [for (final k in kPolyFinanceSubs) PolySub(k)],
      null
    ),
    'weather': (
      PolyPill.weather,
      [for (final k in kPolyWeatherSubs) PolySub(k)],
      null
    ),
    'breaking': (
      PolyPill.breaking,
      [for (final k in kPolyBreakingTopics) PolySub(k)],
      null
    ),
    'sports': (PolyPill.sports, polySportsSubsFromLeagues(directory), null),
    for (final sport in kPolySportGroups)
      if (polySportHasLeagues(sport))
        'sports_$sport': (
          PolyPill.sports,
          polySportLeagueSubs(sport, directory, const []),
          sport
        ),
  };
}

Widget _rowApp(Locale locale, bool dark, Widget child) => ProviderScope(
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(
            fontFamily: 'Inter',
            brightness: dark ? Brightness.dark : Brightness.light,
            extensions: [
              dark ? AppColorsExtension.dark() : AppColorsExtension.light()
            ],
          ),
          home: Scaffold(body: child),
        ),
      ),
    );

/// A drill row laid out whole (wrapped, not scrolled): every pill of it
/// drawn, the first picked, as the row draws them.
Widget _wholeRow(PolyPill pill, List<PolySub> subs, String? sport) =>
    Builder(builder: (context) {
      final l10n = context.l10n;
      return SingleChildScrollView(
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final (i, s) in subs.indexed)
              KutePill(
                label: s.key == sport ? l10n.polySubAll : polySubLabel(l10n, s),
                leading: s.key == sport ? null : polySubLogo(pill, s),
                selected: i == 0,
                onTap: () {},
              ),
          ],
        ),
      );
    });

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

  for (final width in [375.0, 430.0]) {
    for (final lang in ['en', 'pt', 'de']) {
      testWidgets(
          'the category sheet, every level, at ${width.round()} pt in $lang: '
          'no text cut', (tester) async {
        final cut = await _walkSheet(tester,
            size: Size(width, 2400), locale: Locale(lang));
        expect(cut, isEmpty, reason: cut.join('\n'));
      });

      testWidgets(
          'the drill pill rows at ${width.round()} pt in $lang: no pill cut',
          (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final cut = <String>[];
        for (final MapEntry(key: name, value: (pill, subs, sport))
            in _rows().entries) {
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(_rowApp(Locale(lang), false,
              PolyDrillRow(
                drilledInto: pill,
                builder: (context, reveal) => PolySubRow(
                  pill: pill,
                  subs: subs,
                  groups: polySubGroups(pill, subs),
                  selectedKey: subs.first.key,
                  onSelect: (_) {},
                  allKey: sport,
                  onBack: () {},
                  backLabel: sport == null
                      ? null
                      : polySubLabel(
                          l10nForLanguage(lang), PolySub(sport)),
                ),
              )));
          await tester.pump(const Duration(seconds: 1));
          // The row scrolls sideways: every pill is laid out at its width.
          for (final c in _cut(tester, find.byType(PolySubRow))) {
            cut.add('$name: $c');
          }
        }
        expect(cut, isEmpty, reason: cut.join('\n'));
      });
    }
  }

  testWidgets('renders: every level of the sheet and every drill row, light '
      'and dark (the icon audit)', (tester) async {
    if (_frames.isEmpty) return;
    for (final dark in [false, true]) {
      final theme = dark ? 'dark' : 'light';
      await tester.pumpWidget(const SizedBox());
      await _walkSheet(tester,
          size: const Size(430, 932),
          locale: const Locale('en'),
          dark: dark,
          shoot: 'sheet_$theme');
      tester.view.physicalSize = const Size(430, 1400);
      tester.view.devicePixelRatio = 1;
      for (final MapEntry(key: name, value: (pill, subs, sport))
          in _rows().entries) {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(_rowApp(const Locale('en'), dark,
            Padding(
              padding: const EdgeInsets.all(12),
              child: _wholeRow(pill, subs, sport),
            )));
        await _shot(tester, 'row_${theme}_$name');
      }
      tester.view.reset();
    }
  });
}
