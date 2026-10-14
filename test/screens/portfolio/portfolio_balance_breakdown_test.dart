// The top of the Portfolio (founder requests, October 2026): the
// Investments balance part by part (Dollars, Investing, Predictions) in
// one row of equal tiles, each venue's Available and Positions, live on
// the one-balance state and adding up to the header; one Rebalance under
// the row that runs one manual sweeper pass, shown from the venues as they
// are when the Portfolio opens (never the sweeper's last pass); and the
// Positions section (the Positions pill's rows) above the Activity.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart'
    show
        hyperliquidAccountMarketProvider,
        hyperliquidPerpMarketsProvider,
        hyperliquidSpotMarketsProvider;
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/one_balance_live_provider.dart'
    show OneBalanceLiveMarks;
import 'package:kute/providers/one_balance_provider.dart';
import 'package:kute/providers/polymarket_open_orders_provider.dart';
import 'package:kute/providers/polymarket_order_metadata_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/portfolio_rebalance_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/unified_balances_provider.dart';
import 'package:kute/providers/venue_sweeper_provider.dart';
import 'package:kute/screens/portfolio/open_investments_screen.dart';
import 'package:kute/screens/portfolio/portfolio_balance_breakdown.dart';
import 'package:kute/screens/portfolio/portfolio_figure_tiles.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_motion.dart' show RollingFigure;
import 'package:kute/screens/shared/stale_shimmer.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/sweep_rules.dart'
    show SweepSkipReason;
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart' show Order;

import '../../helpers/portfolio_overrides.dart';

final _balance = StateProvider<OneBalanceState>((_) => const OneBalanceState(
      dollarsUsd: 42.5,
      investedUsd: 605,
      investedByVenue: {
        OneBalanceVenue.investing: 600,
        OneBalanceVenue.predictions: 5,
      },
      investingKnown: true,
      predictionsKnown: true,
      venueCash: {OneBalanceVenue.investing: 6.54},
      waiting: {OneBalanceVenue.predictions: 3},
    ));

final _sweeperState =
    StateProvider<VenueSweeperState>((_) => const VenueSweeperState());

/// The sweeper as the Portfolio sees it: its state from [_sweeperState],
/// a Rebalance that waits on [gate] and answers [outcomes], and a preview
/// (the venues read as the Portfolio opens) that publishes [previewed].
class _FakeSweeper extends VenueSweeperNotifier {
  static int calls = 0;
  static int previews = 0;
  static int passes = 0;
  static Completer<void>? gate;
  static Map<OneBalanceVenue, RebalanceOutcome> outcomes = const {};
  static VenueSweeperState? previewed;

  @override
  VenueSweeperState build() => ref.watch(_sweeperState);

  @override
  Future<void> preview() async {
    previews++;
    final next = previewed;
    if (next != null) ref.read(_sweeperState.notifier).state = next;
  }

  @override
  Future<void> trigger(String reason, {OneBalanceVenue? venue}) async =>
      passes++;

  @override
  Future<Map<OneBalanceVenue, RebalanceOutcome>> rebalance() async {
    calls++;
    await gate?.future;
    return outcomes;
  }
}

class _RouteNames extends NavigatorObserver {
  _RouteNames(this.names);
  final List<String?> names;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      names.add(route.settings.name);
}

const _crossBtc = HlPerpPosition(
    coin: 'BTC',
    szi: 0.1,
    entryPx: 60000,
    positionValue: 6000,
    unrealizedPnl: 0,
    returnOnEquity: 0,
    liquidationPx: null,
    marginUsed: 600,
    leverageType: 'cross',
    leverageValue: 10,
    maxLeverage: 40);

/// An Investing fill a day old, so the Activity has a row.
HyperliquidTradingState _tradingWith(
        {List<HlPerpPosition> positions = const []}) =>
    HyperliquidTradingState(
        isInitialized: true,
        positions: positions,
        recentFills: [
          HlFill.fromJson({
            'coin': 'BTC',
            'tid': '1',
            'oid': 1,
            'hash': 'h1',
            'time': DateTime.now()
                .subtract(const Duration(days: 1))
                .millisecondsSinceEpoch,
            'startPosition': '0',
            'sz': '0.1',
            'px': '60000',
            'side': 'B',
            'closedPnl': '0',
            'fee': '1',
            'feeToken': 'USDC',
            'dir': 'Open Long',
          }),
        ]);

/// Predictions whose refresh waits on [gate] (the Portfolio's refresh on
/// open), with the cash it knows.
class _SlowPoly extends PolymarketTradingNotifier {
  static Completer<void>? gate;
  static int refreshes = 0;

  @override
  Future<PolymarketTradingState> build() async =>
      const PolymarketTradingState(isAuthenticated: true, usdcBalance: 2.77);

  @override
  Future<void> refresh() async {
    refreshes++;
    await gate?.future;
  }
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required Widget home,
  HyperliquidTradingState trading = const HyperliquidTradingState(),
  Size size = const Size(400, 1000),
  double textScale = 1,
  List<NavigatorObserver> observers = const [],
  List<Override> overrides = const [],
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(ProviderScope(
      overrides: [
        ...portfolioOverrides(trading: trading),
        hyperliquidLiveMidProvider('BTC').overrideWith((_) => null),
        hyperliquidAccountMarketProvider('BTC').overrideWith((_) => null),
        hyperliquidPerpMarketsProvider.overrideWith((_) async => <HlMarket>[]),
        hyperliquidSpotMarketsProvider.overrideWith((_) async => <HlMarket>[]),
        polymarketOpenOrdersProvider
            .overrideWith((_) => Stream.value(const <Order>[])),
        polymarketOrderMetadataProvider.overrideWith((_) async => const {}),
        settingsProvider.overrideWith((_) => SettingsModel(Settings(
            currency: 'USD',
            language: 'en',
            btcFormat: 'sats',
            backup: false,
            biometricsEnabled: false,
            bitcoinElectrumNode: '',
            nodeType: '',
            reviewDone: true))),
        oneBalanceProvider.overrideWith((ref) => ref.watch(_balance)),
        venueSweeperProvider.overrideWith(_FakeSweeper.new),
        ...overrides,
      ],
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          theme: ThemeData(
              splashFactory: NoSplash.splashFactory,
              fontFamily: 'Inter',
              extensions: [AppColorsExtension.light()]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          navigatorObservers: observers,
          home: home,
        ),
      )));
  if (settle) await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byWidget(home)));
}

const _breakdown = Scaffold(
    body: SingleChildScrollView(
        child: PortfolioBalanceBreakdown(trading: true, predictions: true)));

Finder _figure(String text) =>
    find.byWidgetPredicate((w) => w is RollingFigure && w.text == text);

Finder _inCard(String venue, Finder finder) => find.descendant(
    of: find.byKey(ValueKey('portfolio-balance-$venue')), matching: finder);

Finder get _rebalance => find.byKey(const ValueKey('portfolio-rebalance'));

Finder get _row => find.byKey(const ValueKey('portfolio-balance-row'));

Rect _tile(WidgetTester tester, String venue) =>
    tester.getRect(find.byKey(ValueKey('portfolio-balance-$venue')));

/// The figure under [label] in [venue]'s tile.
String _figureUnder(WidgetTester tester, String venue, String label) {
  final stat = find.ancestor(
      of: _inCard(venue, find.text(label)),
      matching: find.byType(PortfolioTileStat));
  return tester
      .widget<RollingFigure>(
          find.descendant(of: stat, matching: find.byType(RollingFigure)))
      .text;
}

double _usd(String text) =>
    double.parse(text.replaceAll(RegExp(r'[^0-9.]'), ''));

List<(String, Map<String, Object>?)> _events() {
  final events = <(String, Map<String, Object>?)>[];
  TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  addTearDown(() => TrackingService.debugTrackObserver = null);
  return events;
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    _FakeSweeper.calls = 0;
    _FakeSweeper.previews = 0;
    _FakeSweeper.passes = 0;
    _FakeSweeper.gate = null;
    _FakeSweeper.outcomes = const {};
    _FakeSweeper.previewed = null;
    _SlowPoly.gate = null;
    _SlowPoly.refreshes = 0;
  });

  group('the balance breakdown', () {
    testWidgets(
        'Dollars, Investing and Predictions side by side: one row of three '
        'equal tiles, each with its mark, name, Available and Positions, '
        'following the one-balance state', (tester) async {
      final c = await _pump(tester, home: _breakdown);
      expect(_inCard('dollars', find.text('Dollars')), findsOneWidget);
      expect(_inCard('dollars', find.byType(SvgPicture)), findsOneWidget);
      expect(_figureUnder(tester, 'dollars', 'Available'), r'$42.50');
      // Dollars hold no positions.
      expect(_inCard('dollars', find.text('Positions')), findsNothing);
      expect(_inCard('investing', find.text('Investing')), findsOneWidget);
      expect(_inCard('investing', find.byType(SvgPicture)), findsOneWidget);
      expect(_figureUnder(tester, 'investing', 'Available'), r'$6.54');
      expect(_figureUnder(tester, 'investing', 'Positions'), r'$600.00');
      expect(_inCard('predictions', find.text('Predictions')), findsOneWidget);
      expect(_inCard('predictions', find.byType(SvgPicture)), findsOneWidget);
      expect(_figureUnder(tester, 'predictions', 'Available'), r'$3.00');
      expect(_figureUnder(tester, 'predictions', 'Positions'), r'$5.00');

      // One row: the same top, equal widths and heights, left to right,
      // never stretched to the full width.
      final d = _tile(tester, 'dollars');
      final i = _tile(tester, 'investing');
      final p = _tile(tester, 'predictions');
      for (final r in [i, p]) {
        expect(r.top, d.top);
        expect(r.height, d.height);
        expect(r.width, moreOrLessEquals(d.width, epsilon: 0.01));
      }
      expect(d.right, lessThan(i.left));
      expect(i.right, lessThan(p.left));
      expect(d.width, lessThan(tester.getSize(_row).width / 2));

      // Live: the tiles follow the provider.
      c.read(_balance.notifier).state = const OneBalanceState(
          dollarsUsd: 49.04, investingKnown: true, predictionsKnown: true);
      await tester.pumpAndSettle();
      expect(_inCard('dollars', _figure(r'$49.04')), findsOneWidget);
      expect(_figureUnder(tester, 'investing', 'Available'), r'$0.00');
      expect(_figureUnder(tester, 'predictions', 'Positions'), r'$0.00');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'the tiles add up to the header: Dollars and every Available and '
        'Positions make the total, the Positions the Invested', (tester) async {
      // The header's own arithmetic, from the venues' reads, the
      // sweeper's classification and the live marks.
      final state = oneBalanceStateFrom(
        dollarsUsd: 42.5,
        venues: const UnifiedVenueBalances(
          readyInInvestingUsd: 6.54,
          readyInPredictionsUsd: 2.77,
          investedInInvestingUsd: 600,
          investedInPredictionsUsd: 9, // positions $5 + $4 in open orders
          investingKnown: true,
          predictionsKnown: true,
        ),
        inFlight: const [],
        sweeper: const VenueSweeperState(held: {
          OneBalanceVenue.investing: 6.54,
          OneBalanceVenue.predictions: 2.77,
        }),
        marks: const OneBalanceLiveMarks(
            investingDeltaUsd: 12.5, predictionsDeltaUsd: -1.25),
      );
      final c = await _pump(tester, home: _breakdown);
      c.read(_balance.notifier).state = state;
      await tester.pumpAndSettle();
      final positions = _usd(_figureUnder(tester, 'investing', 'Positions')) +
          _usd(_figureUnder(tester, 'predictions', 'Positions'));
      final total = _usd(_figureUnder(tester, 'dollars', 'Available')) +
          _usd(_figureUnder(tester, 'investing', 'Available')) +
          _usd(_figureUnder(tester, 'predictions', 'Available')) +
          positions;
      expect(positions, moreOrLessEquals(state.investedUsd, epsilon: 0.005));
      expect(total, moreOrLessEquals(state.totalUsd, epsilon: 0.005));
      expect(_figureUnder(tester, 'investing', 'Positions'), r'$612.50');
      expect(_figureUnder(tester, 'predictions', 'Positions'), r'$7.75');
      expect(_figureUnder(tester, 'predictions', 'Available'), r'$2.77');
    });

    testWidgets('a venue not read yet reads a dash, never a guess',
        (tester) async {
      final c = await _pump(tester, home: _breakdown);
      c.read(_balance.notifier).state =
          const OneBalanceState(dollarsUsd: 1, predictionsKnown: true);
      await tester.pumpAndSettle();
      // Available and Positions both: never a guess, never a shimmer.
      expect(_inCard('investing', _figure('—')), findsNWidgets(2));
      expect(_figureUnder(tester, 'predictions', 'Available'), r'$0.00');
    });

    testWidgets('nothing a Rebalance can move: no button', (tester) async {
      await _pump(tester, home: _breakdown);
      expect(_rebalance, findsNothing);
    });

    testWidgets(
        'one tap: one manual pass, the busy state while it runs, no second '
        'pass on a second tap, then a line per venue', (tester) async {
      final events = _events();
      final c = await _pump(tester, home: _breakdown);
      c.read(_sweeperState.notifier).state =
          const VenueSweeperState(movable: {OneBalanceVenue.investing: 6.54});
      await tester.pumpAndSettle();
      expect(_rebalance, findsOneWidget);
      expect(find.text('Rebalance'), findsOneWidget);
      // Under the row, the row's full width.
      final row = tester.getRect(_row);
      final button = tester.getRect(_rebalance);
      expect(button.top, greaterThan(row.bottom));
      expect(button.width, moreOrLessEquals(row.width, epsilon: 1));
      expect(_inCard('dollars', _rebalance), findsNothing);

      _FakeSweeper.gate = Completer<void>();
      _FakeSweeper.outcomes = const {
        OneBalanceVenue.investing:
            RebalanceOutcome(RebalanceOutcomeKind.moving, usd: 6.54),
        OneBalanceVenue.predictions: RebalanceOutcome(RebalanceOutcomeKind.held,
            usd: 3, reason: SweepSkipReason.openOrders),
      };
      await tester.tap(_rebalance);
      await tester.pump();
      expect(tester.widget<AppButton>(_rebalance).isLoading, isTrue);
      expect(tester.widget<AppButton>(_rebalance).onPressed, isNull);
      await tester.tap(_rebalance, warnIfMissed: false);
      await tester.pump();
      expect(_FakeSweeper.calls, 1);
      expect(
          events.where((e) => e.$1 == 'portfolio_rebalance_tapped').single.$2,
          {'dollars_usd': 42.5, 'investing_usd': 6.54, 'predictions_usd': 3.0});

      // The move is running at Investing.
      c.read(_sweeperState.notifier).state =
          const VenueSweeperState(sweeping: {OneBalanceVenue.investing});
      await tester.pump();
      expect(
          _inCard(
              'investing', find.text('Moving to USDB… takes a few minutes')),
          findsOneWidget);

      _FakeSweeper.gate!.complete();
      await tester.pumpAndSettle();
      expect(_FakeSweeper.calls, 1);
      // Submitted: on its way (Investing's route takes minutes); the
      // other venue says why its cash stayed.
      expect(
          _inCard(
              'investing', find.text('Moving to USDB… takes a few minutes')),
          findsOneWidget);
      expect(_inCard('predictions', find.text('Held by open orders')),
          findsOneWidget);
      // Nothing movable is left: the button goes.
      c.read(_sweeperState.notifier).state = const VenueSweeperState();
      await tester.pumpAndSettle();
      expect(_rebalance, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('what stayed and why: margin, the minimum, not now',
        (tester) async {
      final c = await _pump(tester, home: _breakdown);
      c.read(_sweeperState.notifier).state =
          const VenueSweeperState(movable: {OneBalanceVenue.predictions: 3});
      await tester.pumpAndSettle();
      _FakeSweeper.outcomes = const {
        OneBalanceVenue.investing: RebalanceOutcome(RebalanceOutcomeKind.held,
            usd: 6.54, reason: SweepSkipReason.crossPosition),
        OneBalanceVenue.predictions:
            RebalanceOutcome(RebalanceOutcomeKind.belowMinimum, usd: 3),
      };
      await tester.tap(_rebalance);
      await tester.pumpAndSettle();
      expect(
          _inCard('investing', find.text('Kept as margin for open positions')),
          findsOneWidget);
      expect(_inCard('predictions', find.text('Below the minimum to move')),
          findsOneWidget);

      _FakeSweeper.outcomes = const {
        OneBalanceVenue.investing:
            RebalanceOutcome(RebalanceOutcomeKind.notNow, usd: 6.54),
      };
      await tester.tap(_rebalance);
      await tester.pumpAndSettle();
      expect(
          _inCard('investing',
              find.text("Couldn't move now, will retry on its own")),
          findsOneWidget);
      expect(_inCard('predictions', find.text('Below the minimum to move')),
          findsNothing);
      expect(tester.takeException(), isNull);
    });

    test('the move line follows the rail, not the tap alone', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final at = DateTime(2026, 10, 14, 12);
      final tapped = PortfolioRebalanceState(outcomes: const {
        OneBalanceVenue.predictions:
            RebalanceOutcome(RebalanceOutcomeKind.moving, usd: 3),
      }, at: at);
      String? note(OneBalanceState balance, DateTime now) => rebalanceNote(l10n,
          venue: OneBalanceVenue.predictions,
          balance: balance,
          sweeper: const VenueSweeperState(),
          rebalance: tapped,
          now: now);
      const empty = OneBalanceState();
      const homeward = OneBalanceState(inFlight: [
        InFlightMove(
            kind: InFlightKind.fromVenue,
            venue: OneBalanceVenue.predictions,
            usd: 3),
      ]);
      // Just submitted: moving, before the row is listed.
      expect(
          note(empty, at.add(const Duration(seconds: 30))), 'Moving to USDB…');
      // The row pending: still moving.
      expect(note(homeward, at.add(const Duration(minutes: 5))),
          'Moving to USDB…');
      // Landed: the row gone, no line.
      expect(note(empty, at.add(const Duration(minutes: 5))), isNull);
    });

    testWidgets(
        r"the founder's $2.77 at Predictions: on open, with no sweeper pass "
        'ever run, the venues are read and Rebalance is there, enabled, '
        'within the first frames', (tester) async {
      _FakeSweeper.previewed = const VenueSweeperState(
          movable: {OneBalanceVenue.predictions: 2.77},
          held: {OneBalanceVenue.predictions: 2.77});
      final c = await _pump(tester,
          home: _breakdown,
          overrides: [polymarketTradingProvider.overrideWith(_SlowPoly.new)],
          settle: false);
      c.read(_balance.notifier).state = const OneBalanceState(
          dollarsUsd: 42.5,
          investingKnown: true,
          predictionsKnown: true,
          venueCash: {OneBalanceVenue.predictions: 2.77});
      // No time passes beyond the first frame and its microtasks: the
      // heartbeat (3 minutes) and the sweeper's passes play no part.
      await tester.pump();
      await tester.pump();
      expect(_FakeSweeper.previews, greaterThanOrEqualTo(1));
      expect(_FakeSweeper.passes, 0);
      expect(_figureUnder(tester, 'predictions', 'Available'), r'$2.77');
      expect(_rebalance, findsOneWidget);
      expect(tester.widget<AppButton>(_rebalance).onPressed, isNotNull);
      await tester.pumpAndSettle();
    });

    testWidgets(
        'on open both venues refresh; their figures shimmer meanwhile, '
        'never a dash, then read again for the sweeper', (tester) async {
      _SlowPoly.gate = Completer<void>();
      await _pump(tester,
          home: _breakdown,
          overrides: [polymarketTradingProvider.overrideWith(_SlowPoly.new)],
          settle: false);
      await tester.pump();
      await tester.pump();
      expect(_SlowPoly.refreshes, 1);
      bool shimmering(String venue) => tester
          .widgetList<StaleShimmer>(_inCard(venue, find.byType(StaleShimmer)))
          .every((w) => w.stale);
      expect(shimmering('predictions'), isTrue);
      expect(_figureUnder(tester, 'predictions', 'Available'), r'$3.00');
      expect(_inCard('predictions', _figure('—')), findsNothing);
      // Dollars are not refreshed here: steady.
      expect(
          tester
              .widget<StaleShimmer>(
                  _inCard('dollars', find.byType(StaleShimmer)))
              .stale,
          isFalse);
      final before = _FakeSweeper.previews;
      _SlowPoly.gate!.complete();
      await tester.pump();
      await tester.pump();
      expect(shimmering('predictions'), isFalse);
      expect(_FakeSweeper.previews, greaterThan(before));
      await tester.pumpAndSettle();
    });

    testWidgets(
        'cash below the route minimum: Rebalance stays, disabled, and the '
        'venue says why', (tester) async {
      final c = await _pump(tester, home: _breakdown);
      c.read(_sweeperState.notifier).state = const VenueSweeperState(
          belowMinimum: {OneBalanceVenue.predictions: 2.77});
      await tester.pumpAndSettle();
      expect(_rebalance, findsOneWidget);
      expect(tester.widget<AppButton>(_rebalance).onPressed, isNull);
      expect(tester.widget<AppButton>(_rebalance).isLoading, isFalse);
      expect(_inCard('predictions', find.text('Below the minimum to move')),
          findsOneWidget);
      // A tap does nothing.
      await tester.tap(_rebalance, warnIfMissed: false);
      await tester.pump();
      expect(_FakeSweeper.calls, 0);

      // Above it: enabled, no line.
      c.read(_sweeperState.notifier).state =
          const VenueSweeperState(movable: {OneBalanceVenue.predictions: 2.77});
      await tester.pumpAndSettle();
      expect(tester.widget<AppButton>(_rebalance).onPressed, isNotNull);
      expect(find.text('Below the minimum to move'), findsNothing);

      // The few cents a CCTP move leaves behind are not worth a button.
      c.read(_sweeperState.notifier).state = const VenueSweeperState(
          belowMinimum: {OneBalanceVenue.investing: 0.06});
      await tester.pumpAndSettle();
      expect(_rebalance, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '375 pt at 130 % text: the row fits, large figures scale down, '
        'nothing cut', (tester) async {
      final c = await _pump(tester,
          home: _breakdown, size: const Size(375, 812), textScale: 1.3);
      c.read(_balance.notifier).state = const OneBalanceState(
        dollarsUsd: 123456.78,
        investedUsd: 1111111.11,
        investedByVenue: {
          OneBalanceVenue.investing: 987654.32,
          OneBalanceVenue.predictions: 123456.79,
        },
        investingKnown: true,
        predictionsKnown: true,
        venueCash: {OneBalanceVenue.investing: 45678.9},
        waiting: {OneBalanceVenue.predictions: 34567.89},
      );
      c.read(_sweeperState.notifier).state = const VenueSweeperState(
          belowMinimum: {OneBalanceVenue.predictions: 0.5});
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final d = _tile(tester, 'dollars');
      final p = _tile(tester, 'predictions');
      expect(p.top, d.top);
      expect(p.width, moreOrLessEquals(d.width, epsilon: 0.01));
      expect(p.right, lessThanOrEqualTo(375));
      expect(_figureUnder(tester, 'investing', 'Positions'), r'$987,654.32');
      expect(find.text('Below the minimum to move'), findsOneWidget);
    });
  });

  group('the Portfolio screen', () {
    testWidgets(
        'the breakdown leads, above the chart; Positions sit above the '
        'Activity, with the Positions pill\'s rows and taps', (tester) async {
      final events = _events();
      final pushed = <String?>[];
      const home = OpenInvestmentsScreen(source: 'test');
      await _pump(tester,
          home: home,
          trading: _tradingWith(positions: [_crossBtc]),
          observers: [_RouteNames(pushed)]);
      final breakdown =
          find.byKey(const ValueKey('portfolio-balance-breakdown'));
      expect(breakdown, findsOneWidget);
      final scrollable = find
          .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable))
          .first;
      final positions =
          find.byKey(const ValueKey('portfolio-positions-heading'));
      await tester.scrollUntilVisible(positions, 200, scrollable: scrollable);
      await tester.pumpAndSettle();
      expect(find.descendant(of: positions, matching: find.text('Positions')),
          findsOneWidget);
      final card = find.byType(HlPortfolioPositionCard);
      expect(card, findsOneWidget);
      final activity = find.byKey(const ValueKey('portfolio-activity-heading'));
      await tester.scrollUntilVisible(activity, 200, scrollable: scrollable);
      await tester.pumpAndSettle();
      expect(
          tester.getTopLeft(card).dy, lessThan(tester.getTopLeft(activity).dy));

      // The same tap as on the Positions pill: the position screen.
      await tester.scrollUntilVisible(card, -200, scrollable: scrollable);
      await tester.pumpAndSettle();
      pushed.clear();
      await tester.tap(card);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(pushed, ['hyperliquid-position-detail-sheet']);
      expect(
          events
              .where((e) => e.$1 == 'open_investments_position_tapped')
              .single
              .$2,
          {'product': 'trading'});
    });

    testWidgets('nothing held: no Positions section, the Activity as before',
        (tester) async {
      await _pump(tester,
          home: const OpenInvestmentsScreen(source: 'test'),
          trading: _tradingWith());
      expect(find.byKey(const ValueKey('portfolio-balance-breakdown')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('portfolio-positions-heading')),
          findsNothing);
      expect(find.byType(HlPortfolioPositionCard), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('375 pt at 130 % text: no overflow anywhere on the page',
        (tester) async {
      const home = OpenInvestmentsScreen(source: 'test');
      final c = await _pump(tester,
          home: home,
          size: const Size(375, 812),
          textScale: 1.3,
          trading: _tradingWith(positions: [_crossBtc]));
      c.read(_sweeperState.notifier).state = const VenueSweeperState(
          movable: {OneBalanceVenue.investing: 6.54},
          sweeping: {OneBalanceVenue.investing});
      _FakeSweeper.outcomes = const {
        OneBalanceVenue.predictions: RebalanceOutcome(RebalanceOutcomeKind.held,
            usd: 3, reason: SweepSkipReason.openOrders),
      };
      await tester.pumpAndSettle();
      await tester.tap(_rebalance);
      await tester.pumpAndSettle();
      expect(find.text('Moving to USDB… takes a few minutes'), findsOneWidget);
      expect(find.text('Held by open orders'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Down the whole page.
      for (var i = 0; i < 8; i++) {
        await tester.drag(
            find.byType(CustomScrollView).first, const Offset(0, -300));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  });
}
