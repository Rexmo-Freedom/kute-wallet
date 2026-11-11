// The open-position screen's speedometer, read through the screen
// (position_detail_sheet.dart): the result line under the dial, the
// held side's colour, the dial on a binary and a many-outcome
// market, drag to explore (what it would be worth, the sell offer, the
// what-if event) and the journey line.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
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
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/screens/shared/capability_unavailable_sheet.dart'
    show CapabilityUnavailableSheet;
import 'package:kute/services/runtime_capabilities_service.dart';
import '../../helpers/runtime_policy_fixture.dart';
import 'package:kute/screens/polymarket/components/position_journey.dart';
import 'package:kute/screens/polymarket/components/position_speedometer.dart';
import 'package:kute/screens/polymarket/components/sell_sheet.dart';
import 'package:kute/screens/shared/position_rows_card.dart'
    show positionTileCaptionStyle, positionTileValueStyle;
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/services/kute_haptics.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/screens/shared/kute_bar_context.dart'
    show KuteBarContextScope, KuteBarPrimaryStyle;
import '../../helpers/balance_privacy.dart';

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
        {PolymarketEvent? event,
        PolyPositionJourney? journey,
        int balancePrivacy = 0}) =>
    [
      balancePrivacyOverride(balancePrivacy),
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
    {PolymarketEvent? event,
    PolyPositionJourney? journey,
    double width = 390,
    double textScale = 1,
    bool dark = false,
    int balancePrivacy = 0}) async {
  tester.view.physicalSize = Size(width, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: _overrides(
        event: event, journey: journey, balancePrivacy: balancePrivacy),
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
          splashFactory: NoSplash.splashFactory,
          extensions: [
            dark ? AppColorsExtension.dark() : AppColorsExtension.light()
          ],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
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

Future<void> _advancedPolicy({Set<String> blocked = const {}}) async {
  AffiliateService.debugSessionToken = 'test-session';
  final policy =
      runtimePolicyFixture(also: const {'trading.advanced'}, blocked: blocked);
  RuntimeCapabilitiesService.debugInstance = policy;
  await policy.refresh();
}

void main() {
  late List<(String, Map<String, Object>?)> events;

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    events = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    PolyPositionSpeedometer.debugSelectionTick = () {};
    KuteHaptics.debugForeground = () => true;
    PolyDialDragMemory.debugReset();
  });

  tearDown(() {
    TrackingService.debugTrackObserver = null;
    PolyPositionSpeedometer.debugSelectionTick = null;
    KuteHaptics.debugReset();
  });

  testWidgets('a No bought at 19¢ now at 66%: the dial, what it is worth '
      'at the top left with the change in the up colour under it, "You hold '
      'No" at the right edge, "Profits" large and "If No wins"',
      (tester) async {
    await _pump(tester, _no);
    final dial = tester.widget<PolyPositionSpeedometer>(
        find.byType(PolyPositionSpeedometer));
    expect(dial.chance, closeTo(0.66, 1e-9));
    expect(dial.entry, closeTo(0.19, 1e-9));
    expect(find.text('You · 19%'), findsNothing);
    // No is the down side: its word in the down colour, as everywhere.
    expect(_heldSide(tester).style!.color, AppColors.marketDown);
    // What it is worth, $13.20, at the top left over the dial, "+247%
    // since 19¢" under it in the up colour (founder, 11 November 2026:
    // the value up here, the profit the tile's figure); "You hold No" at
    // the top right.
    final figure = tester.widget<Text>(
        find.byKey(PolyPositionResultLine.figureKey));
    expect(figure.data, r'$13.20');
    expect(figure.style!.color, AppColorsExtension.light().textPrimary);
    final since =
        tester.widget<Text>(find.byKey(PolyPositionResultLine.sinceKey));
    expect(since.data, '+247% since 19¢');
    expect(since.style!.color, AppColors.marketUp);
    final result = tester.getRect(find.byKey(PolyPositionResultLine.lineKey));
    final heldRect =
        tester.getRect(find.byKey(const ValueKey('poly-position-held')));
    final dialRect =
        tester.getRect(find.byKey(PolyPositionSpeedometer.dialKey));
    expect(result.left, closeTo(dialRect.left, 1));
    // The held line at the right, its right edge on the content's (the
    // tiles' right edge; founder, 11 November 2026: it had floated from
    // the middle); nothing to share beside it (founder, 4 November 2026:
    // the round Sal button floats beside Sell).
    final contentRight = tester
        .getRect(find.byKey(const ValueKey('poly-position-payout')))
        .right;
    expect(heldRect.right, closeTo(contentRight, 0.5));
    expect(heldRect.left, greaterThan(390 / 2));
    expect(heldRect.right, lessThanOrEqualTo(dialRect.right + 1));
    expect(find.byKey(const ValueKey('kute-sal-header-button')), findsNothing);
    expect(result.bottom, lessThanOrEqualTo(dialRect.top));
    expect(heldRect.bottom, lessThanOrEqualTo(dialRect.top));
    // The sweep in the result's colour.
    expect(
        (tester
                .widget<CustomPaint>(
                    find.byKey(PolyPositionSpeedometer.sweepPaintKey))
                .painter! as PolySpeedometerSweepPainter)
            .color,
        AppColors.marketUp);
    // The tiles: the profit large, in its colour, what it is worth under
    // it; the header's figures never said twice.
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('poly-position-value')),
            matching: find.text('Profits')),
        findsOneWidget);
    final pnlFigure = tester
        .widget<RollingNumberText>(find.byKey(PositionDetailSheet.pnlFigureKey));
    expect(pnlFigure.text, r'+$9.40');
    expect(pnlFigure.style, positionTileValueStyle(
        AppColorsExtension.light(), color: AppColors.marketUp));
    final worth = tester.widget<RollingNumberText>(
        find.byKey(PositionDetailSheet.worthCaptionKey));
    expect(worth.text, r'Worth now $13.20');
    expect(worth.style, positionTileCaptionStyle(AppColorsExtension.light()));
    expect(find.textContaining(r'$9.40'), findsNothing);
    expect(find.textContaining('247%', findRichText: true), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('poly-position-payout')),
            matching: find.text('If No wins')),
        findsOneWidget);
    expect(_rolling(r'$13.20'), findsNothing);
    // No journey chart under the tiles any more (founder, 1 November
    // 2026), and no share card (4 November 2026: it floats beside Sell).
    expect(find.byType(PolyPositionJourneyLine), findsNothing);
    expect(find.byKey(const ValueKey('position-share-card')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a Lula Yes on a many-outcome market: the same dial, the '
      'side in the up colour, the result a small loss', (tester) async {
    await _pump(tester, _lula, event: _election);
    await tester.pump(const Duration(milliseconds: 100));
    final painter = tester
        .widget<CustomPaint>(find.byKey(PolyPositionSpeedometer.dialPaintKey))
        .painter! as PolySpeedometerDialPainter;
    // The same calm dial: a neutral track, the price paid a dot on it, no
    // candidate colours.
    expect(painter.entry, closeTo(0.34, 1e-9));
    expect(painter.trackColor, AppColorsExtension.light().border);
    expect(find.text('-0.3% since 34¢'), findsOneWidget);
    expect(
        tester
            .widget<Text>(find.byKey(PolyPositionResultLine.sinceKey))
            .style!
            .color,
        AppColors.marketDown);
    expect(_heldSide(tester).style!.color, AppColors.marketUp);
    final figure = tester.widget<Text>(
        find.byKey(PolyPositionResultLine.figureKey));
    expect(figure.data, r'$16.95');
    final pnlFigure = tester
        .widget<RollingNumberText>(find.byKey(PositionDetailSheet.pnlFigureKey));
    expect(pnlFigure.text, r'-$0.05');
    expect(pnlFigure.style.color, AppColors.marketDown);
    expect(find.text('If Yes wins'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a named outcome is written in the primary text colour; flat '
      'reads "0.0%" quietly, the profit "\$0.00" plain', (tester) async {
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
    expect(figure.data, r'$5.00');
    expect(find.text('0.0% since 50¢'), findsOneWidget);
    expect(
        tester
            .widget<Text>(find.byKey(PolyPositionResultLine.sinceKey))
            .style!
            .color,
        AppColorsExtension.light().textTertiary);
    final pnlFigure = tester
        .widget<RollingNumberText>(find.byKey(PositionDetailSheet.pnlFigureKey));
    expect(pnlFigure.text, r'$0.00');
    expect(pnlFigure.style.color, AppColorsExtension.light().textPrimary);
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
    // The top left reads the what-if: worth $17.00, +347% since 19¢.
    expect(
        tester
            .widget<Text>(find.byKey(PolyPositionResultLine.figureKey))
            .data,
        r'$17.00');
    expect(find.text('+347% since 19¢'), findsOneWidget);
    expect(events.where((e) => e.$1 == 'prediction_position_whatif_used'),
        isEmpty);

    await g.up();
    await tester.pump();
    expect(find.text('If No reaches'), findsNothing);
    expect(find.byKey(const ValueKey('poly-position-worth-then')),
        findsNothing);
    expect(find.text('If No wins'), findsOneWidget);
    expect(find.text('Profits'), findsOneWidget);
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
    // Never dragged on this device before this test: the hint's drag.
    expect(p['first_drag'], true);
    // Never an id.
    expect(p.values.whereType<String>().any((v) => v.contains('cf-no')),
        isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('never dragged: "Drag the needle to see what it\'d be worth" '
      'under the chance and the needle hinted; the first drag fades it for '
      'good, the event the same', (tester) async {
    await _pump(tester, _no);
    final hint = find.byKey(PositionDetailSheet.dialHintKey);
    expect(hint, findsOneWidget);
    expect(find.text("Drag the needle to see what it'd be worth"),
        findsOneWidget);
    expect(
        tester
            .widget<PolyPositionSpeedometer>(
                find.byType(PolyPositionSpeedometer))
            .hintDrag,
        isTrue);
    // Under the chance, over the tiles.
    expect(tester.getRect(hint).top,
        greaterThan(tester
            .getRect(find.byKey(PolyPositionSpeedometer.figureKey))
            .bottom));
    expect(tester.getRect(hint).bottom,
        lessThan(tester
            .getRect(find.byKey(const ValueKey('poly-position-value')))
            .top));
    final tilesTop = tester
        .getRect(find.byKey(const ValueKey('poly-position-value')))
        .top;
    double opacity() => tester
        .widget<AnimatedOpacity>(find.ancestor(
            of: hint, matching: find.byType(AnimatedOpacity)))
        .opacity;
    expect(opacity(), 1);

    final d = _dial(tester);
    final g = await tester.startGesture(d.hub + const Offset(0, -10));
    await tester.pump();
    await g.moveTo(d.at(0.8));
    await tester.pump(const Duration(milliseconds: 16));
    // The offer to sell takes its place while dragging.
    expect(find.text('Set a sell at 80%'), findsOneWidget);
    expect(PolyDialDragMemory.dragged, isTrue);
    expect(
        tester
            .widget<PolyPositionSpeedometer>(
                find.byType(PolyPositionSpeedometer))
            .hintDrag,
        isFalse);
    await g.up();
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 300));
    // The offer over: the hint's place is back, faded for good; nothing
    // under it moved.
    expect(opacity(), 0);
    expect(
        tester
            .getRect(find.byKey(const ValueKey('poly-position-value')))
            .top,
        tilesTop);
    // The drag's own event, as before, marked as the first on this device;
    // nothing for the hint.
    expect(events.map((e) => e.$1), ['prediction_position_whatif_used']);
    expect(events.single.$2!['first_drag'], true);

    // Opened again: no hint, no room for it.
    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(tester, _no);
    expect(find.byKey(PositionDetailSheet.dialHintKey), findsNothing);
    expect(
        tester
            .widget<PolyPositionSpeedometer>(
                find.byType(PolyPositionSpeedometer))
            .hintDrag,
        isFalse);
    expect(tester.takeException(), isNull);
  });

  group('when it ends, under the chance (founder, 6 November 2026)', () {
    final end = DateTime.now().add(const Duration(days: 10));
    PolymarketPosition endingAt(DateTime at) => PolymarketPosition(
          marketId: _no.marketId,
          marketQuestion: _no.marketQuestion,
          outcome: _no.outcome,
          size: _no.size,
          avgPrice: _no.avgPrice,
          currentPrice: _no.currentPrice,
          pnl: _no.pnl,
          pnlPercent: _no.pnlPercent,
          isResolved: false,
          tokenId: _no.tokenId,
          eventSlug: _no.eventSlug,
          endDateStr: at.toUtc().toIso8601String(),
        );
    final expiry = find.byKey(const ValueKey('poly-position-expiry'));
    final figure = find.byKey(PolyPositionSpeedometer.figureKey);
    final value = find.byKey(const ValueKey('poly-position-value'));

    testWidgets('a quiet centred line right under the big %, no pill, over '
        'the drag hint; the sell offer takes the slot while dragging and '
        'nothing under it moves', (tester) async {
      await _pump(tester, endingAt(end));
      expect(expiry, findsOneWidget);
      final text = tester.widget<Text>(expiry);
      // The date and the hour in the app's language, the year only when it
      // is not this one (founder, 10 November 2026: clearer).
      final local = end.toLocal();
      final day = local.year == DateTime.now().year
          ? DateFormat.MMMd('en').format(local)
          : DateFormat.yMMMd('en').format(local);
      expect(text.data, 'Ends $day, ${DateFormat.Hm('en').format(local)}');
      expect(text.style?.color, AppColorsExtension.light().textSecondary);
      // A step up from the quiet 13 w500 it was.
      expect(text.style?.fontSize, 15.sp);
      expect(text.style?.fontWeight, FontWeight.w600);
      expect(text.maxLines, 1);
      // A line, not a pill: nothing bordered around it.
      expect(
          find.ancestor(
              of: expiry,
              matching: find.byWidgetPredicate((w) =>
                  w is Container &&
                  w.decoration is BoxDecoration &&
                  (w.decoration! as BoxDecoration).border != null)),
          findsNothing);
      // Right under the chance, centred, over the hint and the tiles (the
      // slot's few points over it read larger here: this tall test view
      // scales .h by 1.29).
      final hint = find.byKey(PositionDetailSheet.dialHintKey);
      expect(tester.getRect(expiry).top,
          greaterThan(tester.getRect(figure).bottom));
      expect(tester.getRect(expiry).top - tester.getRect(figure).bottom,
          lessThan(24));
      expect(tester.getCenter(expiry).dx, closeTo(390 / 2, 1));
      expect(tester.getRect(expiry).bottom,
          lessThanOrEqualTo(tester.getRect(hint).top));
      expect(tester.getRect(hint).bottom, lessThan(tester.getRect(value).top));
      // Said once.
      expect(find.textContaining('Ends '), findsOneWidget);
      final tilesTop = tester.getRect(value).top;

      final d = _dial(tester);
      final g = await tester.startGesture(d.hub + const Offset(0, -10));
      await tester.pump();
      await g.moveTo(d.at(0.8));
      await tester.pump(const Duration(milliseconds: 300));
      // Dragging: the offer in its place, never on top of it.
      expect(find.text('Set a sell at 80%'), findsOneWidget);
      expect(expiry, findsNothing);
      expect(tester.getRect(value).top, tilesTop);
      await g.up();
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 300));
      // The offer over: the line is back where it was.
      expect(expiry, findsOneWidget);
      expect(tester.getRect(value).top, tilesTop);

      // Opened again, the hint gone for good: the line alone under the
      // chance, still right under it.
      await tester.pumpWidget(const SizedBox.shrink());
      await _pump(tester, endingAt(end));
      expect(find.byKey(PositionDetailSheet.dialHintKey), findsNothing);
      expect(expiry, findsOneWidget);
      expect(tester.getRect(expiry).top - tester.getRect(figure).bottom,
          lessThan(24));
      expect(tester.getRect(expiry).bottom,
          lessThan(tester.getRect(value).top));
      expect(tester.takeException(), isNull);
    });

    testWidgets('hours to go: today or tomorrow at the hour, on the same '
        'line, never an h:mm:ss countdown', (tester) async {
      final at = DateTime.now().add(const Duration(hours: 2, minutes: 5));
      await _pump(tester, endingAt(at));
      final day = at.day == DateTime.now().day ? 'today' : 'tomorrow';
      expect(tester.widget<Text>(expiry).data,
          'Ends $day at ${DateFormat.Hm('en').format(at)}');
      expect(tester.getRect(expiry).top,
          greaterThan(tester.getRect(figure).bottom));
      expect(tester.getRect(expiry).bottom,
          lessThan(tester.getRect(value).top));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('no end date: no line, the hint keeps the slot',
        (tester) async {
      await _pump(tester, _no);
      expect(expiry, findsNothing);
      expect(find.byKey(PositionDetailSheet.dialHintKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('"Set a sell at 85%" opens the limit sell at 85¢ and logs the '
      'what-if with the sell tapped', (tester) async {
    await tester.runAsync(() => _advancedPolicy());
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

  testWidgets('"Set a sell at 85%" with limit orders withheld: just Unavailable, no '
      'sell sheet', (tester) async {
    await tester.runAsync(() => _advancedPolicy(blocked: {'trading.advanced'}));
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
    // Only the Unavailable sheet: the sell sheet never opens.
    expect(find.byType(SellSheet), findsNothing);
    expect(find.byType(CapabilityUnavailableSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('under the tiles: no chart (founder, 1 November 2026) and no '
      'share card; Sell carries the round Sal button, the brag card in '
      'profit (4 November 2026)', (tester) async {
    final since = DateTime.now().subtract(const Duration(days: 9));
    await _pump(tester, _no, journey: (
      since: since,
      points: [
        for (var i = 1; i < 9; i++)
          PolymarketPricePoint(
              timestamp: since.add(Duration(days: i)),
              price: 0.19 + 0.05 * i),
      ],
      fromBuy: true,
    ));
    expect(find.byType(PolyPositionJourneyLine), findsNothing);
    expect(find.text('Your avg 19¢'), findsNothing);
    expect(find.byKey(const ValueKey('position-share-card')), findsNothing);
    final sell = tester
        .widget<KuteBarContextScope>(find.byWidgetPredicate(
            (w) => w is KuteBarContextScope && w.barContext.isPrimary))
        .barContext;
    expect(sell.style, KuteBarPrimaryStyle.destructive);
    expect(sell.share, isNotNull);
    expect(sell.share!.barContext!.market, isTrue);
    expect(sell.share!.brag, isNotNull, reason: 'in profit: the card');
    expect(tester.takeException(), isNull);
  });

  group(
      'the amount won and when it ends, clearer (founder, 10 November '
      '2026, on 2.2.0 (101))', () {
    final en = lookupAppLocalizations(const Locale('en'));
    final de = lookupAppLocalizations(const Locale('de'));
    final now = DateTime(2026, 11, 10, 14, 30);

    test('under an hour: the countdown', () {
      expect(
          polyPositionEndsText(
              en, now.add(const Duration(minutes: 12, seconds: 34)),
              now: now),
          'Ends in 12:34');
      expect(polyPositionEndsText(en, now, now: now), 'Ends in 00:00');
    });

    test(
        'later today or tomorrow: the day in words and the hour, never '
        'an h:mm:ss countdown', () {
      expect(polyPositionEndsText(en, DateTime(2026, 11, 10, 21), now: now),
          'Ends today at 21:00');
      expect(polyPositionEndsText(en, DateTime(2026, 11, 11, 9, 5), now: now),
          'Ends tomorrow at 09:05');
      expect(polyPositionEndsText(de, DateTime(2026, 11, 10, 21), now: now),
          'Endet heute um 21:00');
      expect(polyPositionEndsText(de, DateTime(2026, 11, 11, 9), now: now),
          'Endet morgen um 09:00');
    });

    test(
        'later: the date and the hour in the app\'s language, the year '
        'only when it is not this one', () {
      expect(polyPositionEndsText(en, DateTime(2026, 12, 31, 21), now: now),
          'Ends Dec 31, 21:00');
      expect(polyPositionEndsText(en, DateTime(2027, 1, 5, 21), now: now),
          'Ends Jan 5, 2027, 21:00');
      expect(polyPositionEndsText(de, DateTime(2026, 12, 31, 21), now: now),
          'Endet 31. Dez., 21:00');
    });

    final ending = PolymarketPosition(
      marketId: _no.marketId,
      marketQuestion: _no.marketQuestion,
      outcome: _no.outcome,
      size: _no.size,
      avgPrice: _no.avgPrice,
      currentPrice: _no.currentPrice,
      pnl: _no.pnl,
      pnlPercent: _no.pnlPercent,
      isResolved: false,
      tokenId: _no.tokenId,
      eventSlug: _no.eventSlug,
      endDateStr: DateTime.now()
          .add(const Duration(days: 40))
          .toUtc()
          .toIso8601String(),
    );

    testWidgets(
        'the result 20 (was 17), still under the tiles\' 24; the '
        '"Ends" line 15 w600 in textSecondary', (tester) async {
      await _pump(tester, ending);
      final figure = tester
          .widget<Text>(find.byKey(PolyPositionResultLine.figureKey))
          .style!;
      expect(figure.fontSize, 20.sp);
      expect(figure.fontWeight, FontWeight.w700);
      final expiry = tester
          .widget<Text>(find.byKey(const ValueKey('poly-position-expiry')));
      expect(expiry.style!.fontSize, 15.sp);
      expect(expiry.style!.fontWeight, FontWeight.w600);
      expect(expiry.overflow, isNull);
      expect(tester.takeException(), isNull);
    });

    for (final dark in [false, true]) {
      testWidgets(
          'nothing cut at 320 pt and a large text size '
          '(${dark ? 'dark' : 'light'})', (tester) async {
        await _pump(tester, ending, width: 320, textScale: 1.6, dark: dark);
        final colors =
            dark ? AppColorsExtension.dark() : AppColorsExtension.light();
        final expiryFinder = find.byKey(const ValueKey('poly-position-expiry'));
        final expiry = tester.widget<Text>(expiryFinder);
        expect(expiry.style!.color, colors.textSecondary);
        expect(expiry.data, startsWith('Ends '));
        final view = Offset.zero & const Size(320, 1200);
        for (final f in [
          expiryFinder,
          find.byKey(PolyPositionResultLine.figureKey),
          find.byKey(PositionDetailSheet.dialHintKey),
        ]) {
          final r = tester.getRect(f);
          expect(r.left, greaterThanOrEqualTo(view.left - 0.5));
          expect(r.right, lessThanOrEqualTo(view.right + 0.5));
        }
        // The line and the hint keep to their slot: over the tiles, the
        // figure's chance above them.
        expect(
            tester.getRect(expiryFinder).top,
            greaterThan(tester
                .getRect(find.byKey(PolyPositionSpeedometer.figureKey))
                .bottom));
        expect(
            tester.getRect(find.byKey(PositionDetailSheet.dialHintKey)).bottom,
            lessThanOrEqualTo(tester
                .getRect(find.byKey(const ValueKey('poly-position-value')))
                .top));
        expect(tester.takeException(), isNull);
      });
    }
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

    test('the chart\'s colour is the result\'s', () {
      expect(polyJourneyColor(9.4, Colors.grey), AppColors.marketUp);
      expect(polyJourneyColor(-0.05, Colors.grey), AppColors.marketDown);
      expect(polyJourneyColor(0.001, Colors.grey), Colors.grey);
    });

    test('result percents: whole from 10%, one decimal under it', () {
      expect(polyResultPercent(81.3), '+81%');
      expect(polyResultPercent(4.54), '+4.5%');
      expect(polyResultPercent(-0.3), '-0.3%');
      expect(polyResultPercent(0.01), '0.0%');
      expect(polyResultPercent(-12.4), '-12%');
    });
  });

  group(
      'the value at the top left, the profit large in its tile, "You hold" '
      'at the right edge (founder, 11 November 2026)', () {
    final held = find.byKey(const ValueKey('poly-position-held'));
    final valueTile = find.byKey(const ValueKey('poly-position-value'));
    final payoutTile = find.byKey(const ValueKey('poly-position-payout'));

    for (final dark in [false, true]) {
      testWidgets(
          'nothing cut at 320 pt and text x1.5 '
          '(${dark ? 'dark' : 'light'})', (tester) async {
        await _pump(tester, _no, width: 320, textScale: 1.5, dark: dark);
        final colors =
            dark ? AppColorsExtension.dark() : AppColorsExtension.light();
        // Every figure whole and inside the view.
        final view = Offset.zero & const Size(320, 1200);
        for (final f in [
          find.byKey(PolyPositionResultLine.figureKey),
          find.byKey(PolyPositionResultLine.sinceKey),
          held,
          find.byKey(PositionDetailSheet.pnlFigureKey),
          find.byKey(PositionDetailSheet.worthCaptionKey),
          valueTile,
          payoutTile,
        ]) {
          final r = tester.getRect(f);
          expect(r.left, greaterThanOrEqualTo(view.left - 0.5));
          expect(r.right, lessThanOrEqualTo(view.right + 0.5));
        }
        expect(
            tester
                .getRect(find.byKey(PositionDetailSheet.pnlFigureKey))
                .right,
            lessThanOrEqualTo(tester.getRect(valueTile).right));
        expect(
            tester
                .getRect(find.byKey(PositionDetailSheet.worthCaptionKey))
                .right,
            lessThanOrEqualTo(tester.getRect(valueTile).right));
        // "You hold No" whole, at the content's right edge, clear of the
        // value at the left.
        expect(tester.renderObject<RenderParagraph>(held).didExceedMaxLines,
            isFalse);
        expect(tester.getRect(held).right,
            closeTo(tester.getRect(payoutTile).right, 0.5));
        expect(
            tester.getRect(held).left,
            greaterThan(tester
                .getRect(find.byKey(PolyPositionResultLine.lineKey))
                .right));
        // The theme's colours: the value in the primary text, the profit
        // in the up colour.
        expect(
            tester
                .widget<Text>(find.byKey(PolyPositionResultLine.figureKey))
                .style!
                .color,
            colors.textPrimary);
        expect(
            tester
                .widget<RollingNumberText>(
                    find.byKey(PositionDetailSheet.pnlFigureKey))
                .style
                .color,
            AppColors.marketUp);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a long side name keeps to the right half, smaller rather '
        'than over the value', (tester) async {
      await _pump(
          tester,
          const PolymarketPosition(
            marketId: 'm-long',
            marketQuestion: 'Who wins the cup?',
            outcome: 'Borussia Mönchengladbach',
            size: 10,
            avgPrice: 0.4,
            currentPrice: 0.5,
            pnl: 1,
            pnlPercent: 25,
            isResolved: false,
            tokenId: 'long',
          ),
          width: 320,
          textScale: 1.5);
      expect(tester.getRect(held).right,
          closeTo(tester.getRect(payoutTile).right, 0.5));
      expect(
          tester.getRect(held).left,
          greaterThan(tester
              .getRect(find.byKey(PolyPositionResultLine.lineKey))
              .right));
      expect(tester.takeException(), isNull);
    });

    testWidgets('balances hidden: the value, the change and the profit '
        'masked, no colour', (tester) async {
      await _pump(tester, _no, balancePrivacy: 1);
      expect(
          tester
              .widget<Text>(find.byKey(PolyPositionResultLine.figureKey))
              .data,
          '••••••');
      final since =
          tester.widget<Text>(find.byKey(PolyPositionResultLine.sinceKey));
      expect(since.data, '••% since 19¢');
      expect(since.style!.color, AppColorsExtension.light().textTertiary);
      final pnlFigure = tester.widget<RollingNumberText>(
          find.byKey(PositionDetailSheet.pnlFigureKey));
      expect(pnlFigure.text, '••••••');
      expect(pnlFigure.style.color, AppColorsExtension.light().textPrimary);
      expect(
          tester
              .widget<RollingNumberText>(
                  find.byKey(PositionDetailSheet.worthCaptionKey))
              .text,
          'Worth now ••••••');
      expect(find.textContaining(r'$13.20'), findsNothing);

      // Dragging masks the what-if figures too.
      final d = _dial(tester);
      final g = await tester.startGesture(d.hub + const Offset(0, -10));
      await tester.pump();
      await g.moveTo(d.at(0.85));
      await tester.pump(const Duration(milliseconds: 16));
      expect(
          tester
              .widget<Text>(find.byKey(PolyPositionResultLine.figureKey))
              .data,
          '••••••');
      expect(
          tester
              .widget<Text>(find
                  .byKey(const ValueKey('poly-position-worth-then-change')))
              .data,
          '••••••');
      expect(_rolling(r'$17.00'), findsNothing);
      await g.up();
      await tester.pump(const Duration(seconds: 5));
      expect(tester.takeException(), isNull);
    });
  });
}
