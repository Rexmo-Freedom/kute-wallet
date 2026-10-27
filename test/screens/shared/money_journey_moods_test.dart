// Sal's waiting moods (founder, 27 October 2026): while the money waits
// on a step that is still running, Sal's mood follows how long the wait
// has lasted. Fetch (0–8 s: sitting with the coin in his mouth, a wag
// every 2 s), sniff the trail (8–25 s: the coin at his paws, nose down,
// padding back and forth), settle in (25 s on: lying, chin on his paws,
// ears up with a small "!" whenever the step reports news). On confirm a
// hop and he drops the coin in; on a stop he stops where he is. Reduce
// Motion: one still pose per mood at the same thresholds. A record at
// rest has no moods. The moods are pixel-sprite frames at ~8 fps in
// short beats.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/screens/shared/money_steps_view.dart';
import 'package:kute/services/continuous_haptics.dart';
import 'package:kute/services/kute_haptics.dart';
import 'package:kute/services/one_balance/money_steps.dart';
import 'package:kute/theme/app_theme.dart';

const _run = MoneyStepStatus.running;
const _wait = MoneyStepStatus.waiting;
const _done = MoneyStepStatus.done;
const _fail = MoneyStepStatus.failed;

final AppLocalizations _en = lookupAppLocalizations(const Locale('en'));
String _usd(double v) => '\$${v.toStringAsFixed(2)}';

/// \$9.18 into Investing from Bitcoin, converted there by Orchestra
/// (seen once it runs), credited, then the order.
MoneyStepGraph _order({
  MoneyStepStatus bitcoin = _run,
  MoneyStepStatus convert = _wait,
  MoneyStepStatus confirm = _wait,
  MoneyStepStatus place = _wait,
}) =>
    MoneyStepGraph([
      MoneyStep(
          id: 'leg:bitcoin',
          kind: MoneyStepKind.leg,
          from: MoneyPlace.bitcoin,
          usd: 9.18,
          status: bitcoin),
      MoneyStep(
          id: 'ready:convert',
          kind: MoneyStepKind.convert,
          status: convert,
          ref: convert == _wait ? null : 'seen'),
      MoneyStep(id: 'ready:credit', kind: MoneyStepKind.credit, status: confirm),
      MoneyStep(
          id: 'place', kind: MoneyStepKind.place, usd: 9.18, status: place),
    ]);

/// The lines, the conversion in the words the founder saw ("Converting to
/// USDC · Orchestra"); [news] stands for a sub-step's update.
List<MoneyStepLine> _lines(MoneyStepGraph g, {String news = ''}) => [
      for (final l in moneyStepLines(_en, g, _usd,
          readyLabel: 'Getting your order ready',
          placeLine: 'Opening \$9.18 Long BTC'))
        l.id == 'ready:convert' && l.status == _run
            ? MoneyStepLine('Converting to USDC · Orchestra$news', l.status,
                sub: l.sub, id: l.id)
            : l,
    ];

final ThemeData _light = buildLightTheme();

Widget _app(MoneyStepGraph g,
        {String news = '',
        bool still = false,
        ThemeData? theme,
        Key? boundary}) =>
    ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme ?? _light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: still),
            child: Scaffold(
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
                            lines: _lines(g, news: news),
                            graph: g,
                            to: MoneyPlace.investing,
                            money: _usd),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

MoneyJourneyPainter _motion(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((w) => w.painter)
    .whereType<MoneyJourneyPainter>()
    .single;

/// The conversion running at Investing, Sal waiting beside it (the leg
/// landed live a moment ago).
Future<void> _converting(WidgetTester tester, {bool still = false}) async {
  await tester.pumpWidget(_app(_order(), still: still));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpWidget(
      _app(_order(bitcoin: _done, convert: _run), still: still));
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Pumps on (100 ms at a time) until Sal has waited [at].
Future<void> _until(WidgetTester tester, Duration at) async {
  for (var i = 0; (_motion(tester).waited ?? Duration.zero) < at; i++) {
    if (i > 600) fail('Sal never waited $at');
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  final bridge = <ContinuousHapticsCall>[];

  setUp(() {
    bridge.clear();
    KuteHaptics.debugReset();
    KuteHaptics.debugForeground = () => true;
    ContinuousHaptics.debugReset();
    ContinuousHaptics.debugLog = bridge;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  });

  tearDown(() {
    KuteHaptics.debugReset();
    ContinuousHaptics.debugLog = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets(
      'on the line: the coin parks, Sal walks up and fetches it, then '
      'sniffs, then settles, by how long it has waited', (tester) async {
    await tester.pumpWidget(_app(_order()));
    await tester.pump(const Duration(milliseconds: 600));
    expect(_motion(tester).mood, SalMood.none, reason: 'the coin glides');
    expect(_motion(tester).carrying, isFalse);
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final m = _motion(tester);
    expect(m.mood, SalMood.fetch);
    expect(m.carrying, isTrue);
    expect(m.walking, isFalse);
    // The coin in his mouth: over him, small, in Bitcoin still.
    final sal = m.travellerAt!;
    final coin = m.coin!;
    expect(coin.at.dx, closeTo(sal.dx, 0.5));
    expect(coin.at.dy, lessThan(sal.dy));
    expect(coin.place, MoneyPlace.bitcoin);

    await _until(tester, const Duration(seconds: 8));
    expect(_motion(tester).mood, SalMood.sniff);
    // The coin at his paws now, on the line in front of him.
    await tester.pump(const Duration(milliseconds: 300));
    final paws = _motion(tester).coin!.at;
    expect(paws.dx, greaterThan(_motion(tester).travellerAt!.dx));
    expect(paws.dy, greaterThan(coin.at.dy));

    await _until(tester, const Duration(seconds: 25));
    expect(_motion(tester).mood, SalMood.settle);
    expect(_motion(tester).travellerAt, sal, reason: 'he never left it');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'at the destination: Sal carries the coin in, waits beside it with '
      'the coin in its currency; news while he lies perks his ears',
      (tester) async {
    await tester.pumpWidget(_app(_order()));
    await tester.pump(const Duration(milliseconds: 600));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(_motion(tester).carrying, isTrue);
    final before = _motion(tester).travellerAt!;
    // The leg lands: the conversion runs. He carries the coin on.
    await tester.pumpWidget(_app(_order(bitcoin: _done, convert: _run)));
    await tester.pump(const Duration(milliseconds: 700));
    expect(_motion(tester).carrying, isTrue);
    expect(_motion(tester).hopping, isFalse, reason: 'not a confirm yet');
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final m = _motion(tester);
    expect(m.travellerAt!.dx, greaterThan(before.dx), reason: 'walked on');
    expect(m.travellerStation, 'investing');
    expect(m.mood, SalMood.fetch, reason: 'a new wait starts at fetch');
    expect(m.coin!.place, MoneyPlace.investing, reason: 'its venue mark');
    expect(m.destinationRing, 1);

    await _until(tester, const Duration(seconds: 25));
    await tester.pump(const Duration(milliseconds: 1200));
    expect(_motion(tester).mood, SalMood.settle);
    expect(_motion(tester).earsPerked, isFalse);
    // The step reports news: ears up, a "!", and he stays lying.
    await tester.pumpWidget(
        _app(_order(bitcoin: _done, convert: _run), news: ' · 2 of 3'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_motion(tester).earsPerked, isTrue);
    expect(_motion(tester).mood, SalMood.settle);
    await tester.pump(const Duration(milliseconds: 1100));
    expect(_motion(tester).earsPerked, isFalse);
    expect(_motion(tester).mood, SalMood.settle,
        reason: 'news within the wait keeps the mood');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'on confirm: a hop and he drops the coin into the destination, then '
      'the end beat as before', (tester) async {
    await _converting(tester);
    expect(_motion(tester).carrying, isTrue);
    await _until(tester, const Duration(seconds: 3));
    final held = _motion(tester).coin!.at;
    await tester.pumpWidget(_app(_order(
        bitcoin: _done, convert: _done, confirm: _done, place: _done)));
    await tester.pump(const Duration(milliseconds: 150));
    final m = _motion(tester);
    expect(m.hopping, isTrue);
    expect(m.carrying, isFalse);
    expect(m.mood, SalMood.none);
    final investing = tester.getCenter(
            find.byKey(const ValueKey('money-steps-station-investing'))) -
        tester.getTopLeft(find.byKey(const ValueKey('money-steps-map')));
    final mid = m.coin!.at;
    expect(mid.dx, greaterThan(held.dx), reason: 'on its way in');
    expect(mid.dx, lessThan(investing.dx));
    await tester.pump(const Duration(milliseconds: 600));
    expect(_motion(tester).coin, isNull, reason: 'dropped in');
    expect(_motion(tester).hopping, isFalse);
    expect(bridge.where((c) => c.pattern?.name == 'success'), hasLength(1));
    expect(
        find.byKey(const ValueKey('money-steps-station-done-investing')),
        findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('a stop: he stops where he is, in the pose he was in, no loop',
      (tester) async {
    await _converting(tester);
    await _until(tester, const Duration(seconds: 9));
    expect(_motion(tester).mood, SalMood.sniff);
    final at = _motion(tester).travellerAt;
    await tester.pumpWidget(_app(_order(bitcoin: _done, convert: _fail)));
    await tester.pump(const Duration(milliseconds: 50));
    final coin = _motion(tester).coin!.at;
    expect(_motion(tester).mood, SalMood.sniff, reason: 'held still');
    await tester.pump(const Duration(seconds: 30));
    expect(_motion(tester).mood, SalMood.sniff, reason: 'never settles');
    expect(_motion(tester).travellerAt, at);
    expect(_motion(tester).coin!.at, coin);
    expect(_motion(tester).waited, isNull);
    expect(tester.hasRunningAnimations, isFalse, reason: 'nothing loops');
  });

  testWidgets(
      'the beats: sprite frames (~8 fps) with rests, not a continuous '
      'pose', (tester) async {
    await _converting(tester);
    await _until(tester, const Duration(milliseconds: 650));
    // A wag beat is over by 625 ms of each 2 s: the pose holds until
    // the next one.
    final rest = _motion(tester).coin!.at;
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      expect(_motion(tester).coin!.at, rest);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'Reduce Motion: one still pose per mood, switched at the same '
      'thresholds, no loops', (tester) async {
    await _converting(tester, still: true);
    expect(tester.hasRunningAnimations, isFalse);
    expect(_motion(tester).mood, SalMood.fetch);
    expect(_motion(tester).carrying, isTrue);
    final sal = _motion(tester).travellerAt!;
    expect(_motion(tester).coin!.at.dx, closeTo(sal.dx, 0.5),
        reason: 'the coin in his mouth');
    await tester.pump(const Duration(seconds: 5));
    expect(_motion(tester).mood, SalMood.sniff);
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pump(const Duration(seconds: 17));
    expect(_motion(tester).mood, SalMood.settle);
    expect(tester.hasRunningAnimations, isFalse);
    // News does not animate under Reduce Motion.
    await tester.pumpWidget(_app(_order(bitcoin: _done, convert: _run),
        news: ' · 2 of 3', still: true));
    await tester.pump();
    expect(_motion(tester).earsPerked, isFalse);
    expect(_motion(tester).mood, SalMood.settle);
    // The confirm: the coin in at once, no hop.
    await tester.pumpWidget(_app(
        _order(bitcoin: _done, convert: _done, confirm: _done, place: _done),
        still: true));
    await tester.pump();
    expect(_motion(tester).coin, isNull);
    expect(_motion(tester).hopping, isFalse);
    expect(_motion(tester).mood, SalMood.none);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('a record replayed at rest has no moods', (tester) async {
    await tester.pumpWidget(_app(_order(
        bitcoin: _done, convert: _done, confirm: _done, place: _done)));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      expect(_motion(tester).mood, SalMood.none);
      expect(_motion(tester).carrying, isFalse);
    }
  });

  // Frames for a look by eye, 390 wide, light and dark (written only when
  // asked: JOURNEY_MOOD_FRAMES=<dir>).
  final framesDir = Platform.environment['JOURNEY_MOOD_FRAMES'];
  testWidgets('mood frames', skip: framesDir == null, (tester) async {
    await tester.runAsync(() async {
      final inter = FontLoader('Inter')
        ..addFont(rootBundle.load('lib/assets/fonts/Inter-Regular.ttf'))
        ..addFont(rootBundle.load('lib/assets/fonts/Inter-SemiBold.ttf'));
      await inter.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
      await precacheMoneyJourneyMarks();
    });
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    Directory(framesDir!).createSync(recursive: true);
    for (final dark in [false, true]) {
      final base = dark ? buildDarkTheme() : buildLightTheme();
      final theme =
          base.copyWith(textTheme: base.textTheme.apply(fontFamily: 'Inter'));
      final key = GlobalKey();
      Widget app(MoneyStepGraph g, {String news = ''}) => DefaultTextStyle(
          style: const TextStyle(fontFamily: 'Inter'),
          child: _app(g, news: news, theme: theme, boundary: key));
      Future<void> shot(String name) => tester.runAsync(() async {
            final boundary = key.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 3);
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            File('$framesDir/${dark ? 'dark' : 'light'}-$name.png')
                .writeAsBytesSync(bytes!.buffer.asUint8List());
          });
      Future<void> at(Duration d) async {
        for (var i = 0; (_motion(tester).waited ?? Duration.zero) < d; i++) {
          if (i > 2400) fail('Sal never waited $d');
          await tester.pump(const Duration(milliseconds: 25));
        }
      }

      final converting = _order(bitcoin: _done, convert: _run);
      await tester.pumpWidget(app(_order()));
      await tester.pump(const Duration(milliseconds: 600));
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await at(const Duration(milliseconds: 1300));
      await shot('0-line-fetch');
      await tester.pumpWidget(app(converting));
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      // Fetch: mid-wag, then at rest between beats.
      await at(const Duration(milliseconds: 2130));
      await shot('1-fetch-wag');
      await at(const Duration(milliseconds: 3000));
      await shot('1-fetch');
      // Sniff: padded back, puffs off his nose.
      await at(const Duration(milliseconds: 8000 + 3000 + 760));
      await shot('2-sniff');
      // Settle: lying, then ears up with a "!" on news.
      await at(const Duration(milliseconds: 25000 + 3000 + 1000));
      await shot('3-settle');
      await tester.pumpWidget(app(converting, news: ' · 2 of 3'));
      await tester.pump(const Duration(milliseconds: 60));
      await shot('4-settle-news');
      await tester.pump(const Duration(seconds: 2));
      // The confirm: the hop, the coin on its way in.
      await tester.pumpWidget(app(_order(
          bitcoin: _done, convert: _done, confirm: _done, place: _done)));
      await tester.pump(const Duration(milliseconds: 190));
      await shot('5-hop');
      await tester.pump(const Duration(seconds: 3));
      await shot('6-done');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    }
  });
}
