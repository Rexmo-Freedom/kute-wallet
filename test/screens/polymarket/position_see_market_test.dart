// "View market" on the open-position screen: the first of its rows, above
// Closing Conditions, opening the sheet of the event the position belongs
// to (a candidate's position opens the whole race), or back to that sheet
// when the position was opened over it.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
import 'package:kute/providers/polymarket_watchlist_provider.dart';
import 'package:kute/screens/polymarket/components/poly_market_stats.dart'
    show PolyRulesRow;
import 'package:kute/screens/polymarket/components/position_detail_sheet.dart';
import 'package:kute/screens/polymarket/market_detail_sheet.dart';
import 'package:kute/screens/shared/open_once.dart';
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

class _NoStars extends PolyWatchlistNotifier {
  @override
  List<String> build() => const [];
}

class _Prices extends LivePriceNotifier {
  @override
  LivePriceState build() => const LivePriceState();
  @override
  void addTokens(List<String> tokenIds, {bool pin = true}) {}
  @override
  void acquire() {}
  @override
  void release() {}
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

/// No account: a settled position's Clear button reads an empty state.
class _NoTrading extends PolymarketTradingNotifier {
  @override
  Future<PolymarketTradingState> build() async =>
      const PolymarketTradingState();
}

const _slug = 'brazil-presidential-election';

final _election = PolymarketEvent(
  id: 'br',
  slug: _slug,
  title: 'Brazil Presidential Election',
  description: 'Resolves to the winner of the 2026 election.',
  volume: 1000000,
  liquidity: 50000,
  category: 'politics',
  conditionId: '0xbr',
  endDate: DateTime.now().add(const Duration(days: 30)),
  outcomes: const [
    PolymarketOutcome(
        gammaMarketId: 'm1',
        name: 'Luiz Inácio Lula da Silva',
        price: 0.79,
        tokenId: 'lula'),
    PolymarketOutcome(
        gammaMarketId: 'm2',
        name: 'Flávio Bolsonaro',
        price: 0.19,
        tokenId: 'flavio'),
  ],
);

const _position = PolymarketPosition(
  marketId: 'm2',
  marketQuestion:
      'Will Flávio Bolsonaro win the 2026 Brazilian presidential election?',
  outcome: 'No',
  size: 10,
  avgPrice: 0.81,
  currentPrice: 0.81,
  pnl: 0,
  pnlPercent: 0,
  isResolved: false,
  eventSlug: _slug,
);

List<Override> _overrides(PolymarketEvent? event) => [
      polymarketClaimablePositionsProvider.overrideWithValue(const []),
      polymarketActivePositionsProvider.overrideWithValue(const []),
      livePriceProvider.overrideWith(_Prices.new),
      sportsLiveProvider.overrideWith(_NoGames.new),
      polyGameTimelineProvider.overrideWith(_NoTimeline.new),
      polyWatchlistProvider.overrideWith(_NoStars.new),
      aiEnabledProvider.overrideWith((ref) async => false),
      polymarketCostBasisProvider.overrideWith((ref) => _NoCostBasis()),
      predictionUsdCostProvider.overrideWith((ref, id) async => null),
      polymarketEventDetailsProvider(_slug).overrideWith((ref) async => event),
      polymarketTradingProvider.overrideWith(_NoTrading.new),
    ];

/// The app's frame with [home], after the position's event has been read.
Future<void> _pump(WidgetTester tester, Widget home,
    {PolymarketEvent? event}) async {
  tester.view.physicalSize = const Size(430, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: _overrides(event),
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
          splashFactory: NoSplash.splashFactory,
          extensions: [AppColorsExtension.light()],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    ),
  ));
  await tester.pump();
  await tester.pump();
}

/// A page with a button running [onTap] with its context.
Widget _launcher(void Function(BuildContext) onTap) => Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => onTap(context),
            child: const Text('launch'),
          ),
        ),
      ),
    );

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

final _row = find.byKey(PositionDetailSheet.seeMarketRowKey);

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    OpenOnce.reset();
  });
  tearDown(OpenOnce.reset);

  testWidgets('"View market" is the first row, above Protect it and '
      'Closing Conditions, with no leading glyph', (tester) async {
    await http.runWithClient(() async {
      await _pump(tester, const PositionDetailSheet(position: _position),
          event: _election);
      expect(_row, findsOneWidget);
      expect(
          find.descendant(of: _row, matching: find.text('View market')),
          findsOneWidget);
      // No leading glyph: the label alone, like the rows under it.
      expect(
          find.descendant(
              of: _row, matching: find.byIcon(Icons.show_chart_rounded)),
          findsNothing);
      final rules = find.byType(PolyRulesRow);
      expect(rules, findsOneWidget);
      expect(tester.getTopLeft(_row).dy,
          lessThan(tester.getTopLeft(rules).dy));
      final protect = find.byKey(const ValueKey('poly-position-protect'));
      if (protect.evaluate().isNotEmpty) {
        expect(tester.getTopLeft(_row).dy,
            lessThan(tester.getTopLeft(protect).dy));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => MockClient((_) async => http.Response('{}', 404)));
  });

  testWidgets('no row while the event cannot be read', (tester) async {
    await http.runWithClient(() async {
      await _pump(tester, const PositionDetailSheet(position: _position));
      expect(_row, findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => MockClient((_) async => http.Response('{}', 404)));
  });

  testWidgets('a settled position keeps the row', (tester) async {
    await http.runWithClient(() async {
      await _pump(
          tester,
          const PositionDetailSheet(
            position: PolymarketPosition(
              marketId: 'm2',
              marketQuestion: 'Will Flávio Bolsonaro win the 2026 Brazilian '
                  'presidential election?',
              outcome: 'No',
              size: 10,
              avgPrice: 0.81,
              currentPrice: 0,
              pnl: -8.1,
              pnlPercent: -100,
              isResolved: true,
              won: false,
              eventSlug: _slug,
            ),
          ),
          event: _election);
      expect(_row, findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => MockClient((_) async => http.Response('{}', 404)));
  });

  testWidgets('from the Portfolio: the position closes and the event\'s '
      'sheet opens, from position_see_market', (tester) async {
    final events = <(String, Map<String, Object>?)>[];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    addTearDown(() => TrackingService.debugTrackObserver = null);
    await http.runWithClient(() async {
      await _pump(
          tester,
          _launcher((context) =>
              PositionDetailSheet.show(context, position: _position)),
          event: _election);
      await tester.tap(find.text('launch'));
      await _settle(tester);
      expect(find.byType(PositionDetailSheet), findsOneWidget);

      await tester.ensureVisible(_row);
      await tester.tap(_row);
      await _settle(tester);

      expect(find.byType(PositionDetailSheet), findsNothing);
      final sheet =
          tester.widget<MarketDetailSheet>(find.byType(MarketDetailSheet));
      expect(sheet.event.slug, _slug);
      expect(sheet.event.isSyntheticBinary, isFalse);
      expect(sheet.event.outcomes, hasLength(2));
      expect(sheet.source, PositionDetailSheet.seeMarketSource);
      final viewed =
          events.where((e) => e.$1 == 'polymarket_viewed').single.$2!;
      expect(viewed['source'], 'position_see_market');
      expect(viewed['market_id'], 'br');
      // The analytics context's write, debounced.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => MockClient((_) async => http.Response('{}', 404)));
  });

  testWidgets('opened over the event\'s sheet: back to that sheet, never a '
      'second copy on top', (tester) async {
    final events = <(String, Map<String, Object>?)>[];
    await http.runWithClient(() async {
      await _pump(
          tester,
          _launcher((context) => MarketDetailSheet.show(context,
              event: _election, source: 'feed_card')),
          event: _election);
      await tester.tap(find.text('launch'));
      await _settle(tester);
      expect(find.byType(MarketDetailSheet), findsOneWidget);
      expect(MarketDetailSheet.openRouteFor(_slug), isNotNull);

      // The position opened over the market (as "View prediction" after a
      // bet does).
      final marketContext = tester.element(find.byType(MarketDetailSheet));
      PositionDetailSheet.show(marketContext, position: _position);
      await _settle(tester);
      expect(find.byType(PositionDetailSheet), findsOneWidget);

      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
      addTearDown(() => TrackingService.debugTrackObserver = null);
      await tester.ensureVisible(_row);
      await tester.tap(_row);
      await _settle(tester);

      expect(find.byType(PositionDetailSheet), findsNothing);
      final sheets = tester
          .widgetList<MarketDetailSheet>(find.byType(MarketDetailSheet))
          .toList();
      expect(sheets, hasLength(1));
      expect(sheets.single.source, 'feed_card');
      final viewed =
          events.where((e) => e.$1 == 'polymarket_viewed').single.$2!;
      expect(viewed['source'], 'position_see_market');

      // Closing it ends on the page it was opened from.
      Navigator.of(tester.element(find.byType(MarketDetailSheet)),
              rootNavigator: true)
          .pop();
      await _settle(tester);
      expect(find.byType(MarketDetailSheet), findsNothing);
      expect(find.text('launch'), findsOneWidget);
      expect(MarketDetailSheet.openRouteFor(_slug), isNull);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpWidget(const SizedBox.shrink());
    }, () => MockClient((_) async => http.Response('{}', 404)));
  });
}
