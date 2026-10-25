// The open-position screen's speedometer, read through the screen
// (position_detail_sheet.dart): the result line under the dial, the
// held side's colour, the dial's zones on a binary and a many-outcome
// market, drag to explore (what it would be worth, the sell offer, the
// what-if event) and the journey line.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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
import 'package:kute/screens/polymarket/components/sell_sheet.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/services/kute_haptics.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

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

class _NoTrading extends PolymarketTradingNotifier {
  @override
  Future<PolymarketTradingState> build() async =>
      const PolymarketTradingState();
}

class _Prices extends LivePriceNotifier {
  @override
  LivePriceState build() => const LivePriceState();
}

/// 20 No shares bought at 19¢, No now at 66%: worth $13.20, +$9.40.
const _no = PolymarketPosition(
  marketId: 'c-cf',
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
);

/// 50 Lula Yes shares bought at 34¢, now 33.9%: worth $16.95, -$0.05.
const _lula = PolymarketPosition(
  marketId: 'm-lula',
  marketQuestion: 'Will Lula win the 2026 Brazilian presidential election?',
  outcome: 'Yes',
  size: 50,
  avgPrice: 0.34,
  currentPrice: 0.339,
  pnl: -0.05,
  pnlPercent: -0.3,
  isResolved: false,
  tokenId: 'lula-yes',
  eventSlug: 'brazil-election-2026',
);

final _election = PolymarketEvent(
  id: 'e-br',
  slug: 'brazil-election-2026',
  title: 'Brazil Presidential Election',
  volume: 1000,
  liquidity: 1000,
  category: 'politics',
  conditionId: 'c-br',
  outcomes: const [
    PolymarketOutcome(gammaMarketId: 'm-lula', name: 'Lula', price: 0.339,
        tokenId: 'lula-yes'),
    PolymarketOutcome(gammaMarketId: 'm-tar', name: 'Tarcísio', price: 0.31,
        tokenId: 'tar-yes'),
    PolymarketOutcome(gammaMarketId: 'm-fla', name: 'Flávio', price: 0.19,
        tokenId: 'fla-yes'),
  ],
);

List<Override> _overrides(
        {PolymarketEvent? event, PolyPositionJourney? journey}) =>
    [
      polymarketClaimablePositionsProvider.overrideWithValue(const []),
      polymarketActivePositionsProvider.overrideWithValue(const []),
      livePriceProvider.overrideWith(_Prices.new),
      sportsLiveProvider.overrideWith(_NoGames.new),
      polyGameTimelineProvider.overrideWith(_NoTimeline.new),
      aiEnabledProvider.overrideWith((ref) async => false),
      polymarketCostBasisProvider.overrideWith((ref) => _NoCostBasis()),
      predictionUsdCostProvider.overrideWith((ref, id) async => null),
      polymarketTradingProvider.overrideWith(_NoTrading.new),
      polymarketEventDetailsProvider('ceasefire-2026')
          .overrideWith((ref) async => null),
      polymarketEventDetailsProvider('brazil-election-2026')
          .overrideWith((ref) async => event),
      polyPositionJourneyProvider.overrideWith((ref, key) async => journey),
    ];

Future<void> _pump(WidgetTester tester, PolymarketPosition position,
    {PolymarketEvent? event, PolyPositionJourney? journey}) async {
  tester.view.physicalSize = const Size(390, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: _overrides(event: event, journey: journey),
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
          splashFactory: NoSplash.splashFactory,
          extensions: [AppColorsExtension.light()],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PositionDetailSheet(position: position),
      ),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

/// The held side's span in the "You hold" line.
TextSpan _heldSide(WidgetTester tester) =>
    (tester.widget<Text>(find.byKey(const ValueKey('poly-position-held')))
                .textSpan! as TextSpan)
        .children!
        .last as TextSpan;

Finder _rolling(String text) => find.byWidgetPredicate(
    (w) => w is RollingNumberText && w.text == text,
    description: 'rolling "$text"');

/// The dial's centre on screen and a point at [fraction] on it.
({Offset hub, Offset Function(double) at}) _dial(WidgetTester tester) {
  final box = tester.getRect(find.byKey(PolyPositionSpeedometer.dialKey));
  final g = (tester
          .widget<CustomPaint>(find.byKey(PolyPositionSpeedometer.dialPaintKey))
          .painter! as PolySpeedometerDialPainter)
      .geometry;
  final hub = box.topLeft + g.center;
  final r = g.radius * 0.7;
  return (
    hub: hub,
    at: (f) {
      final a = polyGaugeAngle(f);
      return hub + Offset(r * math.cos(a), r * math.sin(a));
    },
  );
}

void main() {
  late List<(String, Map<String, Object>?)> events;

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    events = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    PolyPositionSpeedometer.debugSelectionTick = () {};
    KuteHaptics.debugForeground = () => true;
  });

  tearDown(() {
    TrackingService.debugTrackObserver = null;
    PolyPositionSpeedometer.debugSelectionTick = null;
    KuteHaptics.debugReset();
  });

  testWidgets('a No bought at 19¢ now at 66%: the dial, the result line in '
      'the up colour, "Worth now" and "If No wins"', (tester) async {
    await _pump(tester, _no);
    final dial = tester.widget<PolyPositionSpeedometer>(
        find.byType(PolyPositionSpeedometer));
    expect(dial.chance, closeTo(0.66, 1e-9));
    expect(dial.entry, closeTo(0.19, 1e-9));
    expect(find.text('You · 19%'), findsOneWidget);
    // No is the down side: its word in the down colour, as everywhere.
    expect(_heldSide(tester).style!.color, AppColors.marketDown);
    // ▲ $9.40 · +247% since you bought.
    final figure = tester.widget<Text>(
        find.byKey(PolyPositionResultLine.figureKey));
    expect(figure.data, r'$9.40 · +247%');
    expect(figure.style!.color, AppColors.marketUp);
    expect(find.text('since you bought'), findsOneWidget);
    final caret = tester.widget<CustomPaint>(
        find.byKey(PolyPositionResultLine.caretKey));
    expect((caret.painter! as PolyCaretPainter).up, isTrue);
    expect((caret.painter! as PolyCaretPainter).color, AppColors.marketUp);
    // The tiles.
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('poly-position-value')),
            matching: find.text('Worth now')),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('poly-position-payout')),
            matching: find.text('If No wins')),
        findsOneWidget);
    expect(_rolling(r'$13.20'), findsOneWidget);
    // No history: no journey line.
    expect(find.byType(PolyPositionJourneyLine), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a Lula Yes on a many-outcome market: the same zones, the '
      'side in the up colour, the result a small loss', (tester) async {
    await _pump(tester, _lula, event: _election);
    await tester.pump(const Duration(milliseconds: 100));
    final painter = tester
        .widget<CustomPaint>(find.byKey(PolyPositionSpeedometer.dialPaintKey))
        .painter! as PolySpeedometerDialPainter;
    // Red under 34%, green over it: no candidate colours on the dial.
    expect(painter.zones, hasLength(2));
    expect(painter.zones[0].to, closeTo(0.34, 1e-9));
    expect(painter.zones[0].color.withValues(alpha: 1),
        AppColors.marketDown.withValues(alpha: 1));
    expect(painter.zones[1].color.withValues(alpha: 1),
        AppColors.marketUp.withValues(alpha: 1));
    expect(find.text('You · 34%'), findsOneWidget);
    expect(_heldSide(tester).style!.color, AppColors.marketUp);
    final figure = tester.widget<Text>(
        find.byKey(PolyPositionResultLine.figureKey));
    expect(figure.data, r'$0.05 · -0.3%');
    expect(figure.style!.color, AppColors.marketDown);
    expect(
        (tester
                .widget<CustomPaint>(
                    find.byKey(PolyPositionResultLine.caretKey))
                .painter! as PolyCaretPainter)
            .up,
        isFalse);
    expect(find.text('If Yes wins'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a named outcome is written in the primary text colour; flat '
      'reads "0.0%" quietly, no caret', (tester) async {
    await _pump(
        tester,
        const PolymarketPosition(
          marketId: 'm-x',
          marketQuestion: 'Who wins?',
          outcome: 'Lula',
          size: 10,
          avgPrice: 0.5,
          currentPrice: 0.5,
          pnl: 0,
          pnlPercent: 0,
          isResolved: false,
          tokenId: 'x',
        ));
    expect(_heldSide(tester).style!.color,
        AppColorsExtension.light().textPrimary);
    final figure = tester.widget<Text>(
        find.byKey(PolyPositionResultLine.figureKey));
    expect(figure.data, r'$0.00 · 0.0%');
    expect(figure.style!.color, AppColorsExtension.light().textSecondary);
    expect(find.byKey(PolyPositionResultLine.caretKey), findsNothing);
  });

  testWidgets(r'drag to 85%: "If No reaches", "Worth then" $17.00 ▲ $13.20 '
      r'beside "Now"; the sell offer; on release the tiles come back, the '
      'offer stays 3 s, then one what-if event', (tester) async {
    await _pump(tester, _no);
    final d = _dial(tester);
    final g = await tester.startGesture(d.hub + const Offset(0, -10));
    await tester.pump();
    for (final f in [0.6, 0.7, 0.8, 0.85]) {
      await g.moveTo(d.at(f));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('If No reaches'), findsOneWidget);
    final then = find.byKey(const ValueKey('poly-position-worth-then'));
    expect(find.descendant(of: then, matching: find.text('Worth then')),
        findsOneWidget);
    // 20 shares × 85¢ = $17.00; $13.20 over the $3.80 paid.
    expect(find.descendant(of: then, matching: _rolling(r'$17.00')),
        findsOneWidget);
    final change = tester.widget<Text>(
        find.byKey(const ValueKey('poly-position-worth-then-change')));
    expect(change.data, r'$13.20');
    expect(change.style!.color, AppColors.marketUp);
    final now = find.byKey(const ValueKey('poly-position-value'));
    expect(find.descendant(of: now, matching: find.text('Now')),
        findsOneWidget);
    expect(find.descendant(of: now, matching: _rolling(r'$13.20')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('poly-position-payout')), findsNothing);
    expect(find.text('Set a sell at 85%'), findsOneWidget);
    expect(events.where((e) => e.$1 == 'prediction_position_whatif_used'),
        isEmpty);

    await g.up();
    await tester.pump();
    expect(find.text('If No reaches'), findsNothing);
    expect(find.byKey(const ValueKey('poly-position-worth-then')),
        findsNothing);
    expect(find.text('If No wins'), findsOneWidget);
    // The offer stays a moment after the release.
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Set a sell at 85%'), findsOneWidget);
    // The needle is back on the live chance.
    expect(
        tester
            .state<PolyPositionSpeedometerState>(
                find.byType(PolyPositionSpeedometer))
            .debugNeedle,
        closeTo(0.66, 0.003));
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Set a sell at 85%'), findsNothing);
    expect(find.byKey(PolyPositionResultLine.lineKey), findsOneWidget);
    final whatIf =
        events.where((e) => e.$1 == 'prediction_position_whatif_used');
    expect(whatIf, hasLength(1));
    final p = whatIf.single.$2!;
    expect(p['whatif_pct'], 85.0);
    expect(p['live_pct'], 66.0);
    expect(p['entry_pct'], 19.0);
    expect(p['direction'], 'up');
    expect(p['sell_tapped'], false);
    expect(p['venue'], 'polymarket');
    // Never an id.
    expect(p.values.whereType<String>().any((v) => v.contains('cf-no')),
        isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('"Set a sell at 85%" opens the limit sell at 85¢ and logs the '
      'what-if with the sell tapped', (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const PositionDetailSheet(position: _no))),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: _overrides(),
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp.router(
          routerConfig: router,
          theme: ThemeData(extensions: [AppColorsExtension.light()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final d = _dial(tester);
    final g = await tester.startGesture(d.hub + const Offset(0, -10));
    await tester.pump();
    for (final f in [0.7, 0.8, 0.85]) {
      await g.moveTo(d.at(f));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Set a sell at 85%'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final sell = tester.widget<SellSheet>(find.byType(SellSheet));
    expect(sell.startWithLimit, isTrue);
    expect(sell.limitPrice, closeTo(0.85, 1e-9));
    expect(sell.source, 'position_whatif');
    final whatIf =
        events.where((e) => e.$1 == 'prediction_position_whatif_used');
    expect(whatIf, hasLength(1));
    expect(whatIf.single.$2!['sell_tapped'], true);
    expect(polyWhatIfSellPrice(1.0), 0.99);
    expect(polyWhatIfSellPrice(0.0), 0.01);
  });

  testWidgets('the journey: from the buy at 19¢ to now, hidden without '
      'history', (tester) async {
    final since = DateTime.now().subtract(const Duration(days: 9));
    await _pump(tester, _no, journey: (
      since: since,
      points: [
        for (var i = 1; i < 9; i++)
          PolymarketPricePoint(
              timestamp: since.add(Duration(days: i)),
              price: 0.19 + 0.05 * i),
      ],
    ));
    expect(find.byType(PolyPositionJourneyLine), findsOneWidget);
    expect(find.text('You bought · 19¢'), findsOneWidget);
    expect(find.text('Now'), findsOneWidget);
    final painter = tester
        .widget<CustomPaint>(find.byKey(PolyPositionJourneyLine.paintKey))
        .painter! as PolyJourneyPainter;
    // Starts at the price paid, ends on the live chance.
    expect(painter.points.first.p, closeTo(0.19, 1e-9));
    expect(painter.points.first.t, 0);
    expect(painter.points.last.p, closeTo(0.66, 1e-9));
    expect(painter.points.last.t, 1);
    expect(painter.entry, closeTo(0.19, 1e-9));
    // Under the tiles.
    expect(
        tester.getRect(find.byType(PolyPositionJourneyLine)).top,
        greaterThan(tester
            .getRect(find.byKey(const ValueKey('poly-position-value')))
            .bottom));
    expect(tester.takeException(), isNull);
  });

  group('the journey\'s data', () {
    test('the first buy of the shares held now', () {
      Activity t(int at, String side, double size, {String asset = 'cf-no'}) =>
          Activity(
              proxyWallet: 'w',
              timestamp: at,
              conditionId: 'c',
              type: 'TRADE',
              size: size,
              usdcSize: size * 0.2,
              transactionHash: 'h$at',
              asset: asset,
              side: side);
      // Bought, sold out, bought again twice: the holding began at 300.
      expect(
          polyFirstBuyOfHolding([
            t(400, 'BUY', 5),
            t(100, 'BUY', 10),
            t(200, 'SELL', 10),
            t(300, 'BUY', 5),
            t(50, 'BUY', 3, asset: 'other'),
          ], 'cf-no'),
          DateTime.fromMillisecondsSinceEpoch(300 * 1000));
      // A partial sell keeps the start.
      expect(
          polyFirstBuyOfHolding(
              [t(100, 'BUY', 10), t(200, 'SELL', 4)], 'cf-no'),
          DateTime.fromMillisecondsSinceEpoch(100 * 1000));
      expect(polyFirstBuyOfHolding([t(100, 'BUY', 10), t(200, 'SELL', 10)],
          'cf-no'), isNull);
    });

    test('the shortest history range that reaches the buy', () {
      expect(polyJourneyInterval(const Duration(minutes: 30)), '1h');
      expect(polyJourneyInterval(const Duration(hours: 3)), '6h');
      expect(polyJourneyInterval(const Duration(hours: 20)), '1d');
      expect(polyJourneyInterval(const Duration(days: 3)), '1w');
      expect(polyJourneyInterval(const Duration(days: 20)), '1m');
      expect(polyJourneyInterval(const Duration(days: 90)), 'max');
    });

    test('the range holds every point and the price paid, at least ten '
        'points tall', () {
      final r = polyJourneyRange([0.33, 0.35], 0.34);
      expect(r.hi - r.lo, greaterThanOrEqualTo(0.10));
      expect(r.lo, lessThan(0.33));
      expect(r.hi, greaterThan(0.35));
      final top = polyJourneyRange([0.97, 0.99], 0.95);
      expect(top.hi, lessThanOrEqualTo(1));
    });

    test('result percents: whole from 10%, one decimal under it', () {
      expect(polyResultPercent(81.3), '+81%');
      expect(polyResultPercent(4.54), '+4.5%');
      expect(polyResultPercent(-0.3), '-0.3%');
      expect(polyResultPercent(0.01), '0.0%');
      expect(polyResultPercent(-12.4), '-12%');
    });
  });
}
