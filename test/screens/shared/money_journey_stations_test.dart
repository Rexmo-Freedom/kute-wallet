// The money journey's stations and the coin's mark (money_steps_view.dart,
// founder on a live slip, 1 November 2026): each station is a 28 px logo
// disc like the Investments screens show (the Bitcoin mark, the Dollars
// green "$", the Hyperliquid logo for Investing, the Polymarket logo for
// Predictions), with its amount under it instead of a dot and a name
// label ("Bitcoin · Investing"); the mark drawn on the coin Sal carries
// (now the plate on his briefcase, accountant cut) is ~1.6x the first
// cut's, centred on the anchor.
//
// An on-demand render of a two-source move (Bitcoin + Investing →
// Predictions) with the real sheets: JOURNEY_R4_RENDER=<dir>.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/providers/asset_icon_provider.dart'
    show kBitcoinMarkAsset, kUsdMarkAsset;
import 'package:kute/screens/shared/money_steps_view.dart';
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/services/continuous_haptics.dart';
import 'package:kute/services/kute_haptics.dart';
import 'package:kute/services/one_balance/bitcoin_funded_order.dart'
    show fundedOrderGraph;
import 'package:kute/services/one_balance/money_steps.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/theme/app_theme.dart';

String _usd(double v) => '\$${v.toStringAsFixed(2)}';

const _run = MoneyStepStatus.running;

/// \$9.18 on No from [legs] (place, usd), all moving.
MoneyStepGraph _bet(List<(MoneyPlace, double)> legs,
        {OneBalanceVenue venue = OneBalanceVenue.predictions}) =>
    MoneyStepGraph([
      for (final s in fundedOrderGraph(
        venue: venue,
        orderUsd: legs.fold<double>(0, (t, l) => t + l.$2),
        legs: [
          for (final (place, usd) in legs)
            MoneyStep(
                id: 'leg:${place.name}',
                kind: MoneyStepKind.leg,
                from: place,
                usd: usd,
                route: place == MoneyPlace.bitcoin ? MoneyRoute.direct : null),
        ],
      ).steps)
        s.copyWith(status: s.kind == MoneyStepKind.leg ? _run : s.status),
    ]);

late AppLocalizations _en;

Widget _app(MoneyStepGraph g,
        {ThemeData? theme, Key? boundary, MoneyPlace? to}) =>
    ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme ?? buildLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: boundary,
              child: Builder(
                builder: (context) => ColoredBox(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: MoneyStepsView(
                        lines: moneyStepLines(_en, g, _usd,
                            readyLabel: 'Getting your prediction ready',
                            placeLine: 'Placing on No'),
                        graph: g,
                        to: to,
                        money: _usd),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

Finder _station(String id) => find.byKey(ValueKey('money-steps-station-$id'));

StationLogoPainter _logo(WidgetTester tester, String id) => tester
    .widget<CustomPaint>(find.byKey(ValueKey('money-steps-station-logo-$id')))
    .painter! as StationLogoPainter;

MoneyJourneyPainter _motion(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((p) => p.painter)
    .whereType<MoneyJourneyPainter>()
    .single;

/// The coin clips' anchors as the bundle has them.
Map<String, dynamic> _anchorsJson() => jsonDecode(
        File('lib/assets/sal/coin_anchors.json').readAsStringSync())
    as Map<String, dynamic>;

Map<String, List<SalCoinAnchor>> _anchors(Map<String, dynamic> json) {
  final minor = json['_minor'] as Map<String, dynamic>;
  return {
    for (final e in json.entries)
      if (!e.key.startsWith('_'))
        e.key: [
          for (var i = 0; i < (e.value as List).length; i++)
            () {
              final v = ((e.value as List)[i] as List).cast<num>();
              return SalCoinAnchor(Offset(v[0].toDouble(), v[1].toDouble()),
                  v[2].toDouble(), (minor[e.key] as List)[i].toDouble());
            }(),
        ],
  };
}

/// A synthetic sheet (a solid brown cell), [frames] at 24 fps.
SalClip _sheet({bool loop = true, int frames = 48}) {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 48, 64), Paint()..color = Colors.brown);
  return SalClip(
      image: recorder.endRecording().toImageSync(48, 64),
      fps: 24,
      frames: frames,
      columns: 6,
      cellWidth: 8,
      cellHeight: 8,
      loop: loop,
      body: true);
}

void _designSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(430 * 3, 932 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

const List<String> _bodyClips = [
  'body_pickup',
  'body_carry',
  'body_drop',
  'body_idle',
  'body_walk',
  'body_sit_down',
  'body_sit',
  'body_wag',
  'body_sad',
  'body_jump',
  'body_shake_no',
  'body_pace',
  'body_sniff_trail',
  'body_dig',
  'body_think',
  'body_point',
  'body_nod',
  'body_sniff',
  'body_cheer',
  'body_shake_off',
];

void main() {
  setUpAll(() async {
    _en = await AppLocalizations.delegate.load(const Locale('en'));
  });

  setUp(() {
    KuteHaptics.debugReset();
    KuteHaptics.debugForeground = () => true;
    ContinuousHaptics.debugReset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  });

  tearDown(() {
    KuteHaptics.debugReset();
    SalSpriteCache.debugReset();
    SalCoinAnchors.debugReset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test('each balance\'s logo disc wears its own mark', () {
    expect(const StationLogoPainter(MoneyPlace.bitcoin).asset,
        kBitcoinMarkAsset);
    expect(const StationLogoPainter(MoneyPlace.dollars).asset, kUsdMarkAsset);
    expect(const StationLogoPainter(MoneyPlace.investing).asset,
        'lib/assets/hyperliquid-logo.svg');
    expect(const StationLogoPainter(MoneyPlace.predictions).asset,
        'lib/assets/polymarket-logo.svg');
    expect(const StationLogoPainter(null).asset, isNull,
        reason: 'an outside destination: a grey disc with an arrow');
  });

  for (final (name, legs, venue, dest) in [
    (
      'Bitcoin + Investing → Predictions',
      [(MoneyPlace.bitcoin, 4.18), (MoneyPlace.investing, 5.0)],
      OneBalanceVenue.predictions,
      'predictions',
    ),
    (
      'Dollars + Bitcoin → Investing',
      [(MoneyPlace.dollars, 3.0), (MoneyPlace.bitcoin, 6.5)],
      OneBalanceVenue.investing,
      'investing',
    ),
  ]) {
    testWidgets(
        'stations as 28 px logo discs with their amounts under them: $name',
        (tester) async {
      _designSize(tester);
      await tester.runAsync(precacheMoneyJourneyMarks);
      await tester.pumpWidget(_app(_bet(legs, venue: venue),
          to: MoneyPlace.values.byName(dest)));
      await tester.pump(const Duration(milliseconds: 600));
      final total = legs.fold<double>(0, (t, l) => t + l.$2);
      for (final (id, place, usd) in [
        for (final (p, u) in legs) (p.name, p, u),
        (dest, MoneyPlace.values.byName(dest), total),
      ]) {
        final disc = _station(id);
        expect(disc, findsOneWidget, reason: id);
        expect(tester.getSize(disc), const Size(28, 28),
            reason: '$id: a 28 px disc at the design size');
        final logo = _logo(tester, id);
        expect(logo.place, place);
        expect(logo.asset, isNotNull);
        // Its amount, under it and centred on it.
        final label = find.byKey(ValueKey('money-steps-station-amount-$id'));
        expect(find.descendant(of: label, matching: find.text(_usd(usd))),
            findsOneWidget,
            reason: '$id: ${_usd(usd)}');
        expect(tester.getTopLeft(label).dy,
            greaterThanOrEqualTo(tester.getBottomLeft(disc).dy));
        // Under it: across its centre (a stacked source's ends at the
        // disc's right edge, clear of Sal taking the case up beside the
        // disc below).
        final cx = tester.getCenter(disc).dx;
        expect(tester.getTopLeft(label).dx, lessThanOrEqualTo(cx));
        expect(tester.getTopRight(label).dx, greaterThanOrEqualTo(cx));
        if (id != dest) {
          expect(tester.getTopRight(label).dx,
              lessThanOrEqualTo(tester.getTopRight(disc).dx + 1));
        }
      }
      // No name labels any more: the amounts say it, the semantics name
      // them, the status line words the move.
      expect(find.textContaining(' · '), findsNothing);
      expect(find.text('Bitcoin'), findsNothing);
      expect(
          tester.getSemantics(_station(legs.first.$1.name)).label,
          isNotEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    });
  }

  test('the coin anchors: the plate is 1.6x the first cut\'s coin', () {
    final a = _anchors(_anchorsJson());
    // The first cut held its coin at r 8.31 (cell units, of 128).
    final held = a['body_carry']!;
    expect(held, hasLength(48));
    for (final f in held) {
      expect(f.r, inInclusiveRange(1.5 * 8.31, 1.75 * 8.31));
      // Facing the camera on the briefcase's face: about round.
      expect(f.ry / f.r, greaterThan(0.85));
      // Inside the cell, clear of its edges.
      expect(f.centre.dx - f.r, greaterThan(0));
      expect(f.centre.dx + f.r, lessThan(128));
      expect(f.centre.dy + f.r, lessThan(128));
    }
    // Standing on the floor (the pick-up's start, the drop's end) it
    // still faces the camera: the mark is drawn there too.
    for (final clip in ['body_pickup', 'body_drop']) {
      for (final f in [a[clip]!.first, a[clip]!.last]) {
        expect(f.ry / f.r, greaterThan(0.5), reason: clip);
      }
    }
  });

  testWidgets(
      'the mark on the carried coin: kSalCoinMarkFill of the coin\'s rim, '
      'about 1.6x the first cut\'s, centred on the anchor', (tester) async {
    _designSize(tester);
    SalSpriteCache.debugSetManifest({
      for (final c in _bodyClips)
        c: {
          'framing': 'body',
          'fps': 24,
          'frames': 48,
          'columns': 6,
          'loop': !const {'body_pickup', 'body_drop', 'body_jump'}.contains(c),
          'group': 'waiting',
        },
    });
    for (final c in _bodyClips) {
      SalSpriteCache.debugPutClip(c, 3,
          _sheet(loop: !const {'body_pickup', 'body_drop'}.contains(c)));
    }
    final anchors = _anchors(_anchorsJson());
    SalCoinAnchors.debugSet(anchors);
    await tester.runAsync(precacheMoneyJourneyMarks);
    await tester.pumpWidget(_app(_bet([
      (MoneyPlace.bitcoin, 4.18),
      (MoneyPlace.investing, 5.0),
    ])));
    // Past the pick-up (2 s): carrying along the line.
    for (var t = 0; t < 26; t++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final m = _motion(tester);
    expect(m.salClip, 'body_carry');
    expect(m.coinInRender, isTrue);
    final markR = m.renderedCoinMarkR!;
    final scale = m.salSize / SalCoinAnchors.cell;
    final rs = anchors['body_carry']!.map((a) => a.r);
    final lo = rs.reduce((a, b) => a < b ? a : b);
    final hi = rs.reduce((a, b) => a > b ? a : b);
    expect(markR, greaterThanOrEqualTo(kSalCoinMarkFill * lo * scale - 0.01));
    expect(markR, lessThanOrEqualTo(kSalCoinMarkFill * hi * scale + 0.01));
    // The first cut drew 0.6 of an 8.31 rim: ~1.6x that now (or more).
    expect(markR / (0.6 * 8.31 * scale), greaterThanOrEqualTo(1.6));
    expect(markR / (0.6 * 8.31 * scale), lessThan(2.0));
    // About 6.8 px tall at least on the 64 px Sal (it was about 4).
    expect(2 * markR, greaterThan(6.4));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });

  // The scene with the real sheets, for a look by eye (written only when
  // asked: JOURNEY_R4_RENDER=<dir>).
  final renderDir = Platform.environment['JOURNEY_R4_RENDER'];
  testWidgets('render: Bitcoin + Investing → Predictions',
      skip: renderDir == null, (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      final inter = FontLoader('Inter')
        ..addFont(rootBundle.load('lib/assets/fonts/Inter-Regular.ttf'))
        ..addFont(rootBundle.load('lib/assets/fonts/Inter-SemiBold.ttf'));
      await inter.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
      await precacheMoneyJourneyMarks();
      // The real sheets, decoded from the bundle's files.
      final manifest = jsonDecode(
              File('lib/assets/sal/manifest.json').readAsStringSync())
          as Map<String, dynamic>;
      SalSpriteCache.debugSetManifest(manifest);
      for (final name in _bodyClips) {
        final entry = manifest[name] as Map<String, dynamic>?;
        if (entry == null) continue;
        final file = (entry['files'] as Map)['3x']['file'] as String;
        final codec = await ui.instantiateImageCodec(
            File('lib/assets/sal/$file').readAsBytesSync());
        final image = (await codec.getNextFrame()).image;
        final frames = (entry['frames'] as num).toInt();
        final columns = (entry['columns'] as num).toInt();
        final rows = (frames / columns).ceil();
        SalSpriteCache.debugPutClip(
            name,
            3,
            SalClip(
                image: image,
                fps: (entry['fps'] as num).toDouble(),
                frames: frames,
                columns: columns,
                cellWidth: image.width / columns,
                cellHeight: image.height / rows,
                loop: entry['loop'] != false,
                body: true));
      }
      SalCoinAnchors.debugSet(_anchors(_anchorsJson()));
    });
    Directory(renderDir!).createSync(recursive: true);
    final g = _bet([(MoneyPlace.bitcoin, 4.18), (MoneyPlace.investing, 5.0)]);
    for (final dark in [false, true]) {
      final base = dark ? buildDarkTheme() : buildLightTheme();
      final theme =
          base.copyWith(textTheme: base.textTheme.apply(fontFamily: 'Inter'));
      final key = GlobalKey();
      await tester.pumpWidget(DefaultTextStyle(
          style: const TextStyle(fontFamily: 'Inter'),
          child: _app(g, theme: theme, boundary: key)));
      Future<void> shot(String name) => tester.runAsync(() async {
            final boundary =
                key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 3);
            final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
            File('$renderDir/${dark ? 'dark' : 'light'}-$name.png')
                .writeAsBytesSync(bytes!.buffer.asUint8List());
          });
      for (var t = 0; t < 9; t++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await shot('1-pickup');
      for (var t = 0; t < 19; t++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await shot('2-carry');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    }
  });
}
