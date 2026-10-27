// Speedometer render harness: draws the Predictions open-position screen
// (position_detail_sheet.dart) with its speedometer, result line and
// journey line for made-up positions, in light and dark, plus one shot
// mid-drag and a few frames of the opening sweep, and writes each as a
// PNG. Nothing reads the network.
//
// Not part of the normal suite; it only runs when asked:
//
//   fvm flutter test test/audit/position_speedometer_render_test.dart \
//     --dart-define=SPEEDOMETER_RENDER=true \
//     --dart-define=SPEEDOMETER_RENDER_OUT=/tmp/kute_speedometer
//
// The cases: a No bought at 19¢ now at 66%, and a Lula Yes bought at 34¢
// now at 33.9%; and, 390 wide, the founder's Flávio Yes bought at 36¢ now
// at 47.7% ($10.01 paid, worth $13.14) right after the buy (no history
// since: the chart from the price paid to now), with the drag hint, and
// after a first drag (the hint gone).

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/advisor_provider.dart' show aiEnabledProvider;
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_cost_basis_provider.dart';
import 'package:kute/providers/polymarket_game_timeline_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_sats_pnl_provider.dart'
    show predictionUsdCostProvider;
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/screens/polymarket/components/position_detail_sheet.dart';
import 'package:kute/screens/polymarket/components/position_journey.dart';
import 'package:kute/screens/polymarket/components/position_speedometer.dart';
import 'package:kute/theme/app_theme.dart';

const _enabled = bool.fromEnvironment('SPEEDOMETER_RENDER');
const _outDefine = String.fromEnvironment('SPEEDOMETER_RENDER_OUT');

final String _out = _outDefine.isNotEmpty
    ? _outDefine
    : '${Directory.systemTemp.path}/kute_speedometer';

const _phone = Size(393, 852);
const _shotKey = ValueKey('speedometer-render-shot');

class _NoGames extends SportsLiveNotifier {
  @override
  Map<String, SportsMatchUpdate> build() => const {};
  @override
  void connect() {}
}

class _NoTimeline extends PolyGameTimelineNotifier {
  @override
  PolyGameTimeline build(String arg) => PolyGameTimeline.empty;
}

class _Prices extends LivePriceNotifier {
  @override
  LivePriceState build() => const LivePriceState();
}

/// No account: the Claim button reads an empty trading state.
class _NoTrading extends PolymarketTradingNotifier {
  @override
  Future<PolymarketTradingState> build() async =>
      const PolymarketTradingState();
}

class _NoCostBasis extends StateNotifier<Map<String, double>>
    implements PolymarketCostBasisNotifier {
  _NoCostBasis() : super(const {});
  @override
  Future<void> addCost(String tokenId, double paidUsdc) async {}
  @override
  Future<void> reset(String tokenId) async {}
  @override
  Future<void> scaleByRemaining(
      String tokenId, double fractionRemaining) async {}
  @override
  double? costFor(String tokenId) => null;
}

Future<void> _show(WidgetTester tester, PolymarketPosition position,
    {required bool dark,
    PolyPositionJourney? journey,
    int settle = 30,
    Size phone = _phone}) async {
  // Never dragged on this device: the drag hint shows.
  PolyDialDragMemory.debugReset();
  tester.view.physicalSize = phone * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const SizedBox.shrink());
  final slug = position.eventSlug;
  await tester.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: [
      polymarketClaimablePositionsProvider.overrideWithValue(const []),
      polymarketActivePositionsProvider.overrideWithValue(const []),
      livePriceProvider.overrideWith(_Prices.new),
      sportsLiveProvider.overrideWith(_NoGames.new),
      polyGameTimelineProvider.overrideWith(_NoTimeline.new),
      aiEnabledProvider.overrideWith((ref) async => true),
      polymarketCostBasisProvider.overrideWith((ref) => _NoCostBasis()),
      predictionUsdCostProvider.overrideWith((ref, id) async => null),
      polymarketTradingProvider.overrideWith(_NoTrading.new),
      if (slug != null)
        polymarketEventDetailsProvider(slug).overrideWith((ref) async => null),
      polyPositionJourneyProvider.overrideWith((ref, key) async => journey),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dark ? buildDarkTheme() : buildLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RepaintBoundary(
          key: _shotKey,
          child: PositionDetailSheet(position: position),
        ),
      ),
    ),
  ));
  for (var i = 0; i < settle; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _shot(WidgetTester tester, String name) async {
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_shotKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_out/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  });
  // ignore: avoid_print
  print('RENDER wrote $name.png');
}


/// A wavy path from [from] to [to] over [days], one point an hour.
PolyPositionJourney _journey(double from, double to, int days, int seed) {
  final now = DateTime.now();
  final since = now.subtract(Duration(days: days));
  final n = days * 24;
  final pts = <PolymarketPricePoint>[];
  var s = seed;
  double rnd() {
    s = (s * 1103515245 + 12345) & 0x7fffffff;
    return s / 0x7fffffff - 0.5;
  }
  var noise = 0.0;
  for (var i = 1; i < n; i++) {
    final f = i / n;
    noise = noise * 0.9 + rnd() * 0.02;
    final p = from + (to - from) * (f * f * (3 - 2 * f)) + noise;
    pts.add(PolymarketPricePoint(
        timestamp: since.add(Duration(hours: i)),
        price: p.clamp(0.01, 0.99).toDouble()));
  }
  return (since: since, points: pts, fromBuy: true);
}

void main() {
  if (!_enabled) {
    test('speedometer render', () {},
        skip: 'on demand: --dart-define=SPEEDOMETER_RENDER=true');
    return;
  }

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    Directory(_out).createSync(recursive: true);
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final family in [
      GoogleFonts.inter().fontFamily!,
      'Inter',
      'FlutterTest'
    ]) {
      final inter = FontLoader(family);
      for (final f in ['Regular', 'SemiBold', 'Bold']) {
        inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
      }
      await inter.load();
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => '$_out/cache');
    final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json'))
        as List<dynamic>;
    for (final entry in manifest.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final font
          in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
  });

  final end = DateTime.now().add(const Duration(days: 40)).toUtc();
  final cases = <(String, PolymarketPosition, PolyPositionJourney)>[
    (
      'no_66_bought_19',
      PolymarketPosition(
        marketId: 'c-ceasefire',
        marketQuestion: 'Ukraine x Russia ceasefire in 2026?',
        outcome: 'No',
        size: 20,
        avgPrice: 0.19,
        currentPrice: 0.66,
        pnl: 9.4,
        pnlPercent: 247,
        isResolved: false,
        tokenId: 'cf-no',
        eventSlug: 'ceasefire-2026',
        endDateStr: end.toIso8601String(),
      ),
      _journey(0.19, 0.66, 9, 7),
    ),
    (
      'lula_yes_33.9_bought_34',
      PolymarketPosition(
        marketId: 'c-lula',
        marketQuestion: 'Brazil presidential election: Lula',
        outcome: 'Yes',
        size: 50,
        avgPrice: 0.34,
        currentPrice: 0.339,
        pnl: -0.05,
        pnlPercent: -0.3,
        isResolved: false,
        tokenId: 'lula-yes',
        eventSlug: 'brazil-election-2026',
        endDateStr: end.toIso8601String(),
      ),
      _journey(0.34, 0.339, 12, 3),
    ),
  ];

  for (final (name, position, journey) in cases) {
    for (final dark in [false, true]) {
      final id = '${name}_${dark ? 'dark' : 'light'}';
      testWidgets(id, (tester) async {
        await _show(tester, position, dark: dark, journey: journey);
        await _shot(tester, id);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 8));
      });
    }
    testWidgets('${name}_drag_light', (tester) async {
      await _show(tester, position, dark: false, journey: journey);
      final dial = find.byKey(PolyPositionSpeedometer.dialKey);
      final box = tester.getRect(dial);
      final hub = Offset(box.center.dx, box.bottom - 14);
      final g = await tester.startGesture(hub);
      await tester.pump();
      // Up and to the right: about 85%.
      final r = box.width / 2 - 30;
      final to = hub + Offset(r * 0.891, -r * 0.454);
      for (var i = 1; i <= 10; i++) {
        await g.moveTo(Offset.lerp(hub, to, i / 10)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(milliseconds: 200));
      await _shot(tester, '${name}_drag_light');
      await g.up();
      await tester.pump(const Duration(milliseconds: 100));
      await _shot(tester, '${name}_released_light');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 8));
    });
  }

  // The founder's position, 390 wide: just bought, the hint, the chart
  // from the price paid; then after a first drag.
  const founderPhone = Size(390, 844);
  final flavio = PolymarketPosition(
    marketId: '0x7c894d1d57329c7b05695a016bf45dbf14f78f4795af9f05c65495eb2bb14ab6',
    marketQuestion: 'Flávio Bolsonaro charged or arrested by October 31?',
    outcome: 'Yes',
    size: 27.5523,
    avgPrice: 10.01 / 27.5523,
    currentPrice: 0.477,
    pnl: 3.13,
    pnlPercent: 31.3,
    isResolved: false,
    tokenId: 'flavio-yes',
    eventSlug: 'flavio-bolsonaro-charged-or-arrested-by-october-31',
    endDateStr: DateTime.utc(2026, 11, 1).toIso8601String(),
  );
  final justBought = (
    since: DateTime.now().subtract(const Duration(minutes: 3)),
    points: const <PolymarketPricePoint>[],
    fromBuy: true,
  );
  for (final dark in [false, true]) {
    final id = 'flavio_just_bought_hint_${dark ? 'dark' : 'light'}';
    testWidgets(id, (tester) async {
      await _show(tester, flavio,
          dark: dark, journey: justBought, phone: founderPhone);
      await _shot(tester, id);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 8));
    });
    final dragged = 'flavio_after_drag_${dark ? 'dark' : 'light'}';
    testWidgets(dragged, (tester) async {
      await _show(tester, flavio,
          dark: dark, journey: justBought, phone: founderPhone);
      final dial = find.byKey(PolyPositionSpeedometer.dialKey);
      final box = tester.getRect(dial);
      final hub = Offset(box.center.dx, box.bottom - 14);
      final g = await tester.startGesture(hub);
      await tester.pump();
      final r = box.width / 2 - 30;
      for (var i = 1; i <= 10; i++) {
        await g.moveTo(hub + Offset(r * 0.6 * i / 10, -r * 0.8 * i / 10));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      // The sell offer runs out; the needle is home.
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await _shot(tester, dragged);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 8));
    });
  }
  testWidgets('flavio_unknown_buy_light', (tester) async {
    final now = DateTime.now();
    final week = _journey(0.03, 0.477, 7, 11);
    await _show(tester, flavio,
        dark: false,
        journey: (since: week.since, points: week.points, fromBuy: false),
        phone: founderPhone);
    // Settled, the lean over.
    await _shot(tester, 'flavio_unknown_buy_light');
    expect(now, isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 8));
  });

  // The needle at 20%, 50% and 85%: never across the chance's digits.
  for (final live in [0.20, 0.50, 0.85]) {
    final (_, base, journey) = cases.first;
    final position = PolymarketPosition(
      marketId: base.marketId,
      marketQuestion: base.marketQuestion,
      outcome: base.outcome,
      size: base.size,
      avgPrice: base.avgPrice,
      currentPrice: live,
      pnl: (live - base.avgPrice) * base.size,
      pnlPercent: (live - base.avgPrice) / base.avgPrice * 100,
      isResolved: false,
      tokenId: base.tokenId,
      eventSlug: base.eventSlug,
      endDateStr: base.endDateStr,
    );
    final id = 'needle_${(live * 100).round()}_light';
    testWidgets(id, (tester) async {
      await _show(tester, position, dark: false, journey: journey);
      await _shot(tester, id);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 8));
    });
  }

  testWidgets('sweep_frames', (tester) async {
    final (_, position, journey) = cases.first;
    await _show(tester, position, dark: false, journey: journey, settle: 0);
    final state = tester.state<PolyPositionSpeedometerState>(
        find.byType(PolyPositionSpeedometer));
    final log = <String>[];
    var t = 0;
    var peak = 0.0;
    for (final at in [0, 100, 200, 300, 400, 460, 550, 700, 900]) {
      if (at > t) {
        // Step in frames so the ticker runs as on a phone.
        while (t < at) {
          final step = (at - t).clamp(0, 16);
          await tester.pump(Duration(milliseconds: step));
          t += step;
          if (state.debugNeedle > peak) peak = state.debugNeedle;
        }
      } else {
        await tester.pump();
      }
      log.add('t=${at}ms needle=${(state.debugNeedle * 100).toStringAsFixed(2)}%');
      await _shot(tester, 'sweep_${at.toString().padLeft(3, '0')}ms');
    }
    // ignore: avoid_print
    print('SWEEP ${log.join(' | ')} | peak=${(peak * 100).toStringAsFixed(2)}%');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 8));
  });
}
