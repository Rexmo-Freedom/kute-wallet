// Portfolio balances remain on screen while Move money opens a route/amount
// review. That tap never sweeps cash. Historical Rebalance records retain
// their existing progress and arrival presentation independently.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:money2/money2.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/swap_order_model.dart';
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
import 'package:kute/providers/polymarket_browse_provider.dart'
    show PolymarketPosition, polymarketActivePositionsProvider;
import 'package:kute/providers/polymarket_open_orders_provider.dart';
import 'package:kute/providers/polymarket_order_metadata_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/portfolio_rebalance_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/providers/unified_balances_provider.dart';
import 'package:kute/providers/venue_sweeper_provider.dart';
import 'package:kute/screens/portfolio/components/balances_overview.dart';
import 'package:kute/screens/portfolio/components/position_rows.dart';
import 'package:kute/screens/portfolio/open_investments_screen.dart';
import 'package:kute/screens/home/components/deposit_sheet.dart'
    show DepositSheet;
import 'package:kute/screens/portfolio/portfolio_balance_breakdown.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_motion.dart' show RollingFigure;
import 'package:kute/screens/shared/rubber_band_progress.dart';
import 'package:kute/services/continuous_haptics.dart';
import 'package:kute/screens/shared/stale_shimmer.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/sweep_rules.dart'
    show SweepSkipReason;
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/services/polymarket/pending_fills.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show Order, Position;

import '../../helpers/fake_swap_orders.dart';
import '../../helpers/portfolio_overrides.dart';
import '../../helpers/money_steps_finders.dart';

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

/// A display price for the real movement sheet, without opening Hive.
class _Currency extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _Currency() : super(CurrencyState({'USD': Fixed.fromInt(60000)}));
  @override
  Future<void> updateRates() async {}
}

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

/// Predictions with a resting BUY reserving 10 x 0.40 = \$4.00.
class _PolyWithOrders extends PolymarketTradingNotifier {
  @override
  Future<PolymarketTradingState> build() async => PolymarketTradingState(
          isAuthenticated: true,
          usdcBalance: 10,
          openOrders: [
            Order(
                id: 'o',
                market: 'm',
                assetId: 'a',
                owner: 'k',
                side: 'BUY',
                price: '0.40',
                originalSize: '10',
                sizeMatched: '0',
                outcome: 'Yes'),
          ]);

  @override
  Future<void> refresh() async {}
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

Finder get _rebalance => find.byKey(const ValueKey('portfolio-move-money'));

/// [finder] among the Rebalance's steps under its button: one line per
/// venue going home (move_steps: the same lines as every move).
Finder _inSteps(Finder finder) => find.descendant(
    of: find.byKey(const ValueKey('portfolio-rebalance-steps')),
    matching: finder);

Finder get _row => find.byKey(const ValueKey('portfolio-balance-row'));

Rect _tile(WidgetTester tester, String venue) =>
    tester.getRect(find.byKey(ValueKey('portfolio-balance-$venue')));

/// [venue]'s figure: its Available cash (the column's figure) or its
/// Positions (the small line under it).
String _figureUnder(WidgetTester tester, String venue, String label) {
  final part = switch (label) {
    'Available' => 'available',
    'Positions' => 'positions',
    _ => throw ArgumentError(label),
  };
  return tester
      .widget<RollingFigure>(find.descendant(
          of: find.byKey(ValueKey('portfolio-balance-$venue-$part')),
          matching: find.byType(RollingFigure)))
      .text;
}

/// Frames for [d]: a band keeps pulling while its move runs, so a pull
/// never "settles".
Future<void> _pumpFor(WidgetTester tester,
    [Duration d = const Duration(seconds: 1)]) async {
  const step = Duration(milliseconds: 50);
  for (var t = Duration.zero; t < d; t += step) {
    await tester.pump(step);
  }
}

double _usd(String text) =>
    double.parse(text.replaceAll(RegExp(r'[^0-9.]'), ''));

List<(String, Map<String, Object>?)> _events() {
  final events = <(String, Map<String, Object>?)>[];
  TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  addTearDown(() => TrackingService.debugTrackObserver = null);
  return events;
}

/// Seeds a pass that was already started by an older release. The new
/// Portfolio button is only a route/amount review and never calls this path.
Future<void> _startLegacyRebalance(WidgetTester tester) async {
  final c = ProviderScope.containerOf(
      tester.element(find.byType(PortfolioBalanceBreakdown)));
  final balance = c.read(oneBalanceProvider);
  c.read(rebalanceBandSessionProvider.notifier).state =
      RebalanceBandSession.tap(
          now: DateTime.now(),
          sweeper: c.read(venueSweeperProvider),
          balance: balance,
          rows: c.read(swapOrdersProvider),
          walletId: c.read(settingsProvider).activeWalletId);
  await c.read(portfolioRebalanceProvider.notifier).rebalance(
      dollarsUsd: balance.dollarsUsd,
      investingUsd: breakdownVenueCash(balance, OneBalanceVenue.investing),
      predictionsUsd: breakdownVenueCash(balance, OneBalanceVenue.predictions));
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
      // Dollars hold no positions: the line under the figure says what it
      // is.
      expect(_inCard('dollars', find.text('Positions')), findsNothing);
      expect(_inCard('dollars', find.text('Available')), findsOneWidget);
      expect(_inCard('investing', find.text('Positions')), findsOneWidget);
      expect(_inCard('predictions', find.text('Positions')), findsOneWidget);
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
        'compact: at 390 pt and 100 % text the row is one low card, its '
        'figures at the secondary size, Rebalance under it', (tester) async {
      final c =
          await _pump(tester, home: _breakdown, size: const Size(390, 844));
      c.read(_sweeperState.notifier).state =
          const VenueSweeperState(movable: {OneBalanceVenue.predictions: 3});
      await tester.pumpAndSettle();
      final row = tester.getRect(_row);
      expect(row.height, lessThanOrEqualTo(84));
      // Each column: mark and name, figure, one small line.
      for (final venue in ['dollars', 'investing', 'predictions']) {
        expect(_tile(tester, venue).height, lessThanOrEqualTo(84));
        final figure = tester.widget<RollingFigure>(find.descendant(
            of: find.byKey(ValueKey('portfolio-balance-$venue-available')),
            matching: find.byType(RollingFigure)));
        expect(figure.style.fontSize, lessThanOrEqualTo(17));
        expect(figure.style.fontFeatures,
            contains(const FontFeature.tabularFigures()));
      }
      final button = tester.getRect(_rebalance);
      expect(button.top, greaterThan(row.bottom));
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
      final c = await _pump(tester, home: _breakdown, overrides: [
        // Neither a live book nor a saved account snapshot exists yet.
        hyperliquidDisplayTradingProvider
            .overrideWith((_) => const AsyncLoading<HyperliquidTradingState>()),
      ]);
      c.read(_balance.notifier).state =
          const OneBalanceState(dollarsUsd: 1, predictionsKnown: true);
      await tester.pumpAndSettle();
      // Available and Positions both: never a guess, never a shimmer.
      expect(_inCard('investing', _figure('—')), findsNWidgets(2));
      expect(_figureUnder(tester, 'predictions', 'Available'), r'$0.00');
    });

    testWidgets(
        'Move money opens review without sweeping or clearing displayed balances',
        (tester) async {
      final events = _events();
      final c = await _pump(tester, home: _breakdown, overrides: [
        currencyProvider.overrideWith((_) => _Currency()),
      ]);
      c.read(_sweeperState.notifier).state = const VenueSweeperState(movable: {
        OneBalanceVenue.investing: 6.54,
        OneBalanceVenue.predictions: 3,
      });
      await tester.pumpAndSettle();
      final before = c.read(oneBalanceProvider);
      expect(c.read(rebalanceBandSessionProvider), isNull);
      await tester.tap(_rebalance);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(DepositSheet), findsOneWidget);
      expect(
          find.byKey(const ValueKey('money-movement-sheet')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('money-movement-route')), findsOneWidget);
      expect(find.text('From'), findsOneWidget);
      expect(find.text('To'), findsOneWidget);
      expect(_FakeSweeper.calls, 0);
      expect(_FakeSweeper.passes, 0);
      expect(c.read(oneBalanceProvider), same(before));
      expect(c.read(portfolioRebalanceProvider).running, isFalse);
      expect(c.read(portfolioRebalanceProvider).outcomes, isEmpty);
      expect(c.read(rebalanceBandSessionProvider), isNull);
      expect(events.where((event) => event.$1 == 'portfolio_rebalance_tapped'),
          isEmpty);
      Navigator.of(tester.element(find.byType(DepositSheet))).pop();
      await _pumpFor(tester);
      expect(_figureUnder(tester, 'dollars', 'Available'), r'$42.50');
      expect(_figureUnder(tester, 'investing', 'Available'), r'$6.54');
      expect(_figureUnder(tester, 'predictions', 'Available'), r'$3.00');
      expect(tester.takeException(), isNull);
    });

    testWidgets('Dollars-only Portfolio still offers the movement review',
        (tester) async {
      await _pump(tester, home: _breakdown);
      expect(_rebalance, findsOneWidget);
    });

    testWidgets(
        'an already-started manual pass keeps its busy state, no second '
        'pass on a second tap, then a line per venue', (tester) async {
      final events = _events();
      final c = await _pump(tester, home: _breakdown);
      c.read(_sweeperState.notifier).state =
          const VenueSweeperState(movable: {OneBalanceVenue.investing: 6.54});
      await tester.pumpAndSettle();
      expect(_rebalance, findsOneWidget);
      expect(find.text('Move money'), findsOneWidget);
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
      unawaited(_startLegacyRebalance(tester));
      await tester.pump();
      expect(tester.widget<AppButton>(_rebalance).isLoading, isTrue);
      expect(tester.widget<AppButton>(_rebalance).onPressed, isNull);
      await tester.tap(_rebalance, warnIfMissed: false);
      await tester.pump();
      expect(_FakeSweeper.calls, 1);
      expect(
          events.where((e) => e.$1 == 'portfolio_rebalance_tapped').single.$2,
          {'dollars_usd': 42.5, 'investing_usd': 6.54, 'predictions_usd': 3.0});

      // The move is running at Investing: its step under the button, one
      // line, never the tile's note too.
      c.read(_sweeperState.notifier).state =
          const VenueSweeperState(sweeping: {OneBalanceVenue.investing});
      await tester.pump();
      expect(_inSteps(findMoneyStep(r'Moving $6.54 from Investing → Dollars')),
          findsOneWidget);
      expect(
          _inCard(
              'investing', find.text('Moving to USDB… takes a few minutes')),
          findsNothing);

      _FakeSweeper.gate!.complete();
      // Investing's band pulls while its move runs: frames, never settled.
      await _pumpFor(tester);
      expect(_FakeSweeper.calls, 1);
      // Submitted: on its way; the other venue says why its cash stayed
      // (held: no step of its own).
      expect(_inSteps(findMoneyStep(r'Moving $6.54 from Investing → Dollars')),
          findsOneWidget);
      expect(_inSteps(find.textContaining('Predictions')), findsNothing);
      expect(_inCard('predictions', find.text('Held by open orders')),
          findsOneWidget);
      // Nothing movable is left: the button goes.
      c.read(_sweeperState.notifier).state = const VenueSweeperState();
      await _pumpFor(tester);
      expect(_rebalance, findsOneWidget);
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
      unawaited(_startLegacyRebalance(tester));
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
      unawaited(_startLegacyRebalance(tester));
      await tester.pumpAndSettle();
      expect(
          _inCard('investing',
              find.text("Couldn't move now. Tap Rebalance to try again.")),
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

    testWidgets('sweep minimums never disable choosing a movement route',
        (tester) async {
      final c = await _pump(tester, home: _breakdown);
      for (final below in [
        {OneBalanceVenue.predictions: 2.77},
        {OneBalanceVenue.investing: .06},
      ]) {
        c.read(_sweeperState.notifier).state =
            VenueSweeperState(belowMinimum: below);
        await tester.pumpAndSettle();
        expect(_rebalance, findsOneWidget);
        expect(tester.widget<AppButton>(_rebalance).onPressed, isNotNull);
        expect(tester.widget<AppButton>(_rebalance).isLoading, isFalse);
        expect(find.byKey(const ValueKey('portfolio-rebalance-reason')),
            findsNothing);
        expect(_FakeSweeper.calls, 0);
        expect(_FakeSweeper.passes, 0);
        expect(_figureUnder(tester, 'dollars', 'Available'), r'$42.50');
      }
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
      expect(find.text('Below the minimum to move'), findsNothing);
    });
    testWidgets(
        'what open orders reserve: one line under Predictions, its amount '
        'never wrapped, at 375 pt and 130 % text', (tester) async {
      await _pump(tester,
          home: _breakdown,
          size: const Size(375, 812),
          textScale: 1.3,
          overrides: [
            polymarketTradingProvider.overrideWith(_PolyWithOrders.new)
          ]);
      final line = _inCard('predictions', find.text(r'$4.00 in open orders'));
      expect(line, findsOneWidget);
      // One line: as tall as the one-line caption under Dollars.
      final available = _inCard('dollars', find.text('Available'));
      expect(tester.getSize(line).height,
          moreOrLessEquals(tester.getSize(available).height, epsilon: 0.5));
      expect(tester.takeException(), isNull);
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
      final card = find.byType(HlPositionRow);
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
      expect(find.byType(HlPositionRow), findsNothing);
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
      unawaited(_startLegacyRebalance(tester));
      // Investing's band pulls while its move runs: frames, never settled.
      await _pumpFor(tester);
      expect(find.text('Moving to USDB… takes a few minutes'), findsOneWidget);
      expect(find.text('Held by open orders'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Down the whole page.
      for (var i = 0; i < 8; i++) {
        await tester.drag(
            find.byType(CustomScrollView).first, const Offset(0, -300));
        await _pumpFor(tester);
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('the Rebalance bands', () {
    const both = VenueSweeperState(movable: {
      OneBalanceVenue.investing: 6.54,
      OneBalanceVenue.predictions: 3,
    });
    const bothMoving = {
      OneBalanceVenue.investing:
          RebalanceOutcome(RebalanceOutcomeKind.moving, usd: 6.54),
      OneBalanceVenue.predictions:
          RebalanceOutcome(RebalanceOutcomeKind.moving, usd: 3),
    };

    testWidgets(
        'one tap pulls BOTH moving columns at once, Dollars stays still, the '
        'button wears the busy band while the pass is sent', (tester) async {
      final c = await _pump(tester, home: _breakdown);
      c.read(_sweeperState.notifier).state = both;
      await tester.pumpAndSettle();
      _FakeSweeper.gate = Completer<void>();
      _FakeSweeper.outcomes = bothMoving;

      unawaited(_startLegacyRebalance(tester));
      await tester.pump();
      // The same frame: both bands asked for the first pull.
      expect(_bandWidget(tester, 'investing').progress,
          moreOrLessEquals(RubberBandProgress.firstPull, epsilon: 0.005));
      expect(_bandWidget(tester, 'predictions').progress,
          moreOrLessEquals(RubberBandProgress.firstPull, epsilon: 0.005));
      await tester.pump(const Duration(milliseconds: 250));
      final i = _band(tester, 'investing').stretch;
      final p = _band(tester, 'predictions').stretch;
      expect(i, greaterThan(0.04));
      expect(p, moreOrLessEquals(i, epsilon: 1e-4), reason: 'pulled together');
      expect(_dollarsDip(tester), 0);
      expect(_buttonBand(tester).stretch, greaterThan(0));

      // Sent: the button lets go, the venues keep pulling, a step up.
      _FakeSweeper.gate!.complete();
      await _pumpFor(tester);
      expect(_buttonBand(tester).stretch, 0);
      expect(_bandWidget(tester, 'investing').progress,
          greaterThanOrEqualTo(RebalanceBandPhase.submitted.floor));
      expect(_band(tester, 'investing').stretch, greaterThan(i));
      expect(_band(tester, 'predictions').stretch, greaterThan(p));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a held venue never pulls and keeps its one-line reason',
        (tester) async {
      final c = await _pump(tester, home: _breakdown);
      c.read(_sweeperState.notifier).state =
          const VenueSweeperState(movable: {OneBalanceVenue.investing: 6.54});
      await tester.pumpAndSettle();
      _FakeSweeper.outcomes = const {
        OneBalanceVenue.investing:
            RebalanceOutcome(RebalanceOutcomeKind.moving, usd: 6.54),
        OneBalanceVenue.predictions: RebalanceOutcome(RebalanceOutcomeKind.held,
            usd: 3, reason: SweepSkipReason.openOrders),
      };
      unawaited(_startLegacyRebalance(tester));
      for (var f = 0; f < 30; f++) {
        await tester.pump(const Duration(milliseconds: 50));
        expect(_band(tester, 'predictions').stretch, 0);
        expect(_bandWidget(tester, 'predictions').progress, 0);
      }
      expect(_band(tester, 'investing').stretch, greaterThan(0.04));
      expect(_inCard('predictions', find.text('Held by open orders')),
          findsOneWidget);
    });

    testWidgets(
        'each column snaps on its own as its row lands, one snap per '
        'venue; the pull is felt as one rumble until the long wait drops '
        'to a heartbeat; Dollars catch each arrival; nothing ticks once '
        'both are home', (tester) async {
      final log = _feel();
      final c = await _pump(tester, home: _breakdown);
      c.read(_sweeperState.notifier).state = both;
      await tester.pumpAndSettle();
      _FakeSweeper.outcomes = bothMoving;
      final rows = c.read(swapOrdersProvider.notifier) as FakeSwapOrders;

      unawaited(_startLegacyRebalance(tester));
      await tester.pump();
      // The start is felt: both bands pull with the haptic on, as one
      // rumble.
      expect(_bandWidget(tester, 'investing').haptic, isTrue);
      expect(_bandWidget(tester, 'predictions').haptic, isTrue);
      expect(log.where((c) => c.method == 'start'), isNotEmpty);
      await _pumpFor(tester, const Duration(milliseconds: 1400));
      expect(log.where((c) => c.method == 'update').length, greaterThan(10),
          reason: 'the pull is felt');
      expect(log.where((c) => c.method == 'stop'), isEmpty);

      // Both rows listed: on their way.
      rows.set([
        _homeRow('p', 'POLYGON'),
        _homeRow('i', 'HYPERCORE'),
      ]);
      c.read(_balance.notifier).state = _homeward(
          {OneBalanceVenue.investing: 6.54, OneBalanceVenue.predictions: 3});
      await _pumpFor(tester, const Duration(milliseconds: 300));
      expect(_bandWidget(tester, 'investing').progress,
          greaterThanOrEqualTo(RebalanceBandPhase.onItsWay.floor));
      // Still felt while they hold, the tension building; a long move
      // drops to the heartbeat (the 20 s rule).
      final held = _band(tester, 'predictions').stretch;
      await _pumpFor(tester, const Duration(seconds: 25));
      expect(_band(tester, 'predictions').stretch, greaterThan(held + 0.005));
      expect(_band(tester, 'predictions').heartbeat, isTrue);
      expect(_band(tester, 'investing').heartbeat, isTrue);
      final beatFrom = log.length;
      await _pumpFor(tester, const Duration(seconds: 3));
      expect(log.skip(beatFrom).map((c) => c.method).toSet(), {'pulse'},
          reason: 'only the heartbeat while they wait');
      expect(log.skip(beatFrom).length, inInclusiveRange(2, 4),
          reason: 'one beat a second, the two bands as one');

      // Predictions lands: it snaps, Investing keeps pulling.
      rows.set([
        _homeRow('p', 'POLYGON', status: 'success'),
        _homeRow('i', 'HYPERCORE'),
      ]);
      c.read(_balance.notifier).state =
          _homeward({OneBalanceVenue.investing: 6.54});
      await tester.pump();
      expect(_bandWidget(tester, 'predictions').outcome,
          RubberBandOutcome.success);
      expect(_bandWidget(tester, 'investing').outcome, RubberBandOutcome.none);
      expect(_snaps(log), 1);
      await tester.pump(const Duration(milliseconds: 50));
      expect(_dollarsDip(tester), greaterThan(0.01), reason: 'Dollars catch');
      await _pumpFor(tester, const Duration(milliseconds: 1000));
      expect(_band(tester, 'predictions').stretch,
          moreOrLessEquals(0, epsilon: 1e-4));
      expect(_band(tester, 'predictions').ticking, isFalse);
      expect(_dollarsDip(tester), 0);
      expect(_band(tester, 'investing').stretch, greaterThan(0.06));
      expect(
          _inCard('predictions', find.text('Moving to USDB…')), findsNothing);
      // Each step completes on its own: Predictions is home, Investing
      // still on its way.
      expect(_inSteps(findMoneyStep(r'Moved $3.00 from Predictions → Dollars')),
          findsOneWidget);
      expect(_inSteps(findMoneyStep(r'Moving $6.54 from Investing → Dollars')),
          findsOneWidget);

      // Investing lands: its own snap, the second thud.
      rows.set([
        _homeRow('p', 'POLYGON', status: 'success'),
        _homeRow('i', 'HYPERCORE', status: 'success'),
      ]);
      c.read(_balance.notifier).state = _homeward(const {});
      await tester.pump();
      expect(
          _bandWidget(tester, 'investing').outcome, RubberBandOutcome.success);
      expect(_snaps(log), 2);
      // Home: everything comes to rest and nothing ticks.
      await tester.pumpAndSettle();
      expect(_snaps(log), 2);
      expect(_band(tester, 'investing').ticking, isFalse);
      expect(_band(tester, 'investing').stretch, 0);
      expect(
          _inCard(
              'investing', find.text('Moving to USDB… takes a few minutes')),
          findsNothing);
      expect(_inSteps(findMoneyStep(r'Moved $6.54 from Investing → Dollars')),
          findsOneWidget);
      expect(_inSteps(findMoneyStep(r'Moved $3.00 from Predictions → Dollars')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'left and opened again mid-move: the band shows the tension reached, '
        'felt again while the move runs, no snap replayed', (tester) async {
      final log = _feel();
      _Toggle.shown.value = true;
      addTearDown(() => _Toggle.shown.value = true);
      final c = await _pump(tester, home: const _Toggle());
      c.read(_sweeperState.notifier).state =
          const VenueSweeperState(movable: {OneBalanceVenue.predictions: 3});
      await tester.pumpAndSettle();
      _FakeSweeper.outcomes = const {
        OneBalanceVenue.predictions:
            RebalanceOutcome(RebalanceOutcomeKind.moving, usd: 3),
      };
      unawaited(_startLegacyRebalance(tester));
      await tester.pump();
      (c.read(swapOrdersProvider.notifier) as FakeSwapOrders)
          .set([_homeRow('p', 'POLYGON')]);
      c.read(_balance.notifier).state =
          _homeward({OneBalanceVenue.predictions: 3});
      await _pumpFor(tester, const Duration(milliseconds: 500));

      // Leave the Portfolio; come back 40 s after the tap.
      _Toggle.shown.value = false;
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('portfolio-band-predictions')),
          findsNothing);
      final s = c.read(rebalanceBandSessionProvider)!;
      c.read(rebalanceBandSessionProvider.notifier).state =
          RebalanceBandSession(
              startedAt: s.startedAt.subtract(const Duration(seconds: 40)),
              pulling: s.pulling,
              pendingAtTap: s.pendingAtTap,
              knownAtTap: s.knownAtTap);
      final before = log.length;
      _Toggle.shown.value = true;
      await tester.pump();
      final progress = _bandWidget(tester, 'predictions').progress;
      expect(
          progress,
          moreOrLessEquals(
              rebalanceBandProgress(
                  RebalanceBandPhase.onItsWay, const Duration(seconds: 40),
                  expected: const Duration(minutes: 1)),
              epsilon: 0.02));
      expect(progress, greaterThan(RebalanceBandPhase.onItsWay.floor));
      // Still on its way: the pull is felt again, from the tension reached.
      expect(_bandWidget(tester, 'predictions').haptic, isTrue);
      await _pumpFor(tester, const Duration(milliseconds: 500));
      expect(_band(tester, 'predictions').stretch,
          moreOrLessEquals(rubberBandStretchFor(progress), epsilon: 0.01));
      final again = log.skip(before).toList();
      expect(again.first.method, 'start');
      expect(
          again.lastWhere((c) => c.method == 'update').intensity,
          moreOrLessEquals(RubberBandHaptics.intensityFor(progress),
              epsilon: 0.05),
          reason: 'at the tension reached, as the band is');
      expect(again.where((c) => c.method == 'snap'), isEmpty,
          reason: 'no snap replayed');
    });

    testWidgets('covered by a route: still, and nothing ticks', (tester) async {
      final c = await _pump(tester, home: _breakdown);
      c.read(_sweeperState.notifier).state = both;
      await tester.pumpAndSettle();
      _FakeSweeper.outcomes = bothMoving;
      unawaited(_startLegacyRebalance(tester));
      await _pumpFor(tester);
      expect(_band(tester, 'investing').stretch, greaterThan(0));
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(nav.push(MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: SizedBox()))));
      await _pumpFor(tester);
      final state = tester.state<RubberBandProgressState>(find.descendant(
          of: find.byKey(const ValueKey('portfolio-band-investing'),
              skipOffstage: false),
          matching: find.byType(RubberBandProgress, skipOffstage: false),
          skipOffstage: false));
      expect(state.stretch, 0);
      expect(state.ticking, isFalse);
      expect(tester.binding.transientCallbackCount, 0);
      nav.pop();
      await _pumpFor(tester);
      expect(_band(tester, 'investing').stretch, greaterThan(0));
    });

    testWidgets('Reduce Motion: no column moves, nothing ticks',
        (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final c = await _pump(tester, home: _breakdown);
      c.read(_sweeperState.notifier).state = both;
      await tester.pumpAndSettle();
      _FakeSweeper.outcomes = bothMoving;
      unawaited(_startLegacyRebalance(tester));
      for (var f = 0; f < 20; f++) {
        await tester.pump(const Duration(milliseconds: 50));
        expect(_band(tester, 'investing').stretch, 0);
        expect(_band(tester, 'predictions').stretch, 0);
      }
      expect(_band(tester, 'investing').ticking, isFalse);
      expect(_band(tester, 'predictions').ticking, isFalse);
      expect(tester.binding.transientCallbackCount, 0);
      expect(_inSteps(findMoneyStep(r'Moving $6.54 from Investing → Dollars')),
          findsOneWidget);
    });

    testWidgets('at rest nothing ticks', (tester) async {
      final c = await _pump(tester, home: _breakdown);
      c.read(_sweeperState.notifier).state = both;
      await tester.pumpAndSettle();
      expect(_band(tester, 'investing').ticking, isFalse);
      expect(_band(tester, 'predictions').ticking, isFalse);
      expect(_bandWidget(tester, 'investing').progress, 0);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('375 pt at 130 % text, both pulling: no overflow',
        (tester) async {
      final c = await _pump(tester,
          home: _breakdown, size: const Size(375, 812), textScale: 1.3);
      c.read(_sweeperState.notifier).state = both;
      await tester.pumpAndSettle();
      _FakeSweeper.outcomes = bothMoving;
      unawaited(_startLegacyRebalance(tester));
      await _pumpFor(tester);
      expect(_band(tester, 'investing').stretch, greaterThan(0));
      expect(_band(tester, 'predictions').stretch, greaterThan(0));
      expect(tester.takeException(), isNull);
      expect(_tile(tester, 'predictions').right, lessThanOrEqualTo(375));
      expect(_inSteps(findMoneyStep(r'Moving $6.54 from Investing → Dollars')),
          findsOneWidget);
      expect(
          _inSteps(findMoneyStep(r'Moving $3.00 from Predictions → Dollars')),
          findsOneWidget);
    });

    test('the phase follows the move: the tap, its row, its landing', () {
      final tap = DateTime(2026, 10, 14, 12);
      final session = RebalanceBandSession(
          startedAt: tap,
          pulling: const {OneBalanceVenue.predictions},
          knownAtTap: const {'old'});
      RebalanceBandPhase phase(
              {PortfolioRebalanceState rebalance =
                  const PortfolioRebalanceState(running: true),
              List<SwapOrder> rows = const [],
              OneBalanceState balance = const OneBalanceState(),
              OneBalanceVenue venue = OneBalanceVenue.predictions,
              Duration after = const Duration(seconds: 5)}) =>
          rebalanceBandPhase(
              venue: venue,
              session: session,
              rebalance: rebalance,
              balance: balance,
              sweeper: const VenueSweeperState(),
              rows: rows,
              walletId: null,
              now: tap.add(after));
      final done = PortfolioRebalanceState(
          outcomes: bothMoving, at: tap.add(const Duration(seconds: 2)));
      expect(phase(), RebalanceBandPhase.sending);
      expect(phase(venue: OneBalanceVenue.investing), RebalanceBandPhase.rest);
      // An earlier move home, done before the tap, is not this one.
      expect(
          phase(
              rebalance: done,
              rows: [_homeRow('old', 'POLYGON', status: 'success', at: tap)]),
          RebalanceBandPhase.submitted);
      final pending = _homeRow('new', 'POLYGON', at: tap);
      expect(
          phase(
              rebalance: done,
              rows: [pending],
              balance: _homeward({OneBalanceVenue.predictions: 3})),
          RebalanceBandPhase.onItsWay);
      // Pending, but its dollars already counted in Dollars: home.
      expect(
          phase(rebalance: done, rows: [pending]), RebalanceBandPhase.landed);
      expect(
          phase(
              rebalance: done,
              rows: [_homeRow('new', 'POLYGON', status: 'success', at: tap)]),
          RebalanceBandPhase.landed);
      // Never listed, past the grace: let go softly.
      expect(phase(rebalance: done, after: const Duration(minutes: 3)),
          RebalanceBandPhase.released);
      // Held after all: let go softly.
      expect(
          phase(
              rebalance: PortfolioRebalanceState(outcomes: const {
            OneBalanceVenue.predictions: RebalanceOutcome(
                RebalanceOutcomeKind.held,
                usd: 3,
                reason: SweepSkipReason.openOrders),
          }, at: tap)),
          RebalanceBandPhase.released);
    });

    test('the tension builds with time toward the ceiling, never past it', () {
      const minute = Duration(minutes: 1);
      expect(
          rebalanceBandProgress(RebalanceBandPhase.sending, Duration.zero,
              expected: minute),
          RubberBandProgress.firstPull);
      expect(
          rebalanceBandProgress(RebalanceBandPhase.submitted, minute,
              expected: minute),
          greaterThan(0.6));
      expect(
          rebalanceBandProgress(
              RebalanceBandPhase.onItsWay, const Duration(hours: 1),
              expected: minute),
          lessThan(RubberBandBusy.defaultCeiling + 1e-9));
      expect(
          rebalanceBandProgress(RebalanceBandPhase.landed, minute,
              expected: minute),
          0);
      // Investing builds slower than Predictions.
      expect(
          rebalanceBandProgress(RebalanceBandPhase.sending, minute,
              expected: rebalanceBandExpected(OneBalanceVenue.investing)),
          lessThan(rebalanceBandProgress(RebalanceBandPhase.sending, minute,
              expected: rebalanceBandExpected(OneBalanceVenue.predictions))));
    });
  });

  group('the Balances overview', () {
    const overviewBreakdown = Scaffold(
        body: SingleChildScrollView(
            child: PortfolioBalanceBreakdown(
                trading: true, predictions: true, overview: true)));

    // The founder's balances (October 2026).
    const founder = OneBalanceState(
      dollarsUsd: 0.06,
      investedUsd: 10.82,
      investedByVenue: {OneBalanceVenue.investing: 10.82},
      investingKnown: true,
      predictionsKnown: true,
      venueCash: {
        OneBalanceVenue.investing: 0.45,
        OneBalanceVenue.predictions: 9.56,
      },
    );

    BalancesEntry entry(BalancesPart part, double? cash,
            [double? positions, int count = 0]) =>
        BalancesEntry(
          part: part,
          asset: '',
          name: part.name,
          cash: BalancesFigure(cash == null ? '—' : '\$$cash', usd: cash),
          positions: part == BalancesPart.dollars
              ? null
              : BalancesFigure(positions == null ? '—' : '\$$positions',
                  usd: positions),
          positionCount: count,
        );

    RollingFigure rolling(WidgetTester tester, String key) =>
        tester.widget<RollingFigure>(find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(RollingFigure)));
    String figureOf(WidgetTester tester, String key) =>
        rolling(tester, key).text;
    // An account row's cash, the In positions value ('positions').
    String amount(WidgetTester tester, String row) =>
        figureOf(tester, 'portfolio-balance-$row-amount');
    bool sweeping(WidgetTester tester, String key) => tester
        .widget<StaleShimmer>(find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(StaleShimmer)))
        .stale;
    String? positionsLine(WidgetTester tester) {
      final f = find.byKey(const ValueKey('portfolio-balance-positions-line'));
      return f.evaluate().isEmpty ? null : tester.widget<Text>(f).data;
    }

    Finder segment(String name) =>
        find.byKey(ValueKey('portfolio-balance-bar-$name'));

    test(
        'the bar: each account its cash, every position one segment, an '
        'empty one drawing none', () {
      final segments = balancesBarSegments([
        entry(BalancesPart.dollars, 30),
        entry(BalancesPart.investing, 10, 40),
        entry(BalancesPart.predictions, 0, 20),
      ]);
      // Largest first; positions together (60), never per venue.
      expect(segments.map((s) => s.$1), [
        BalancesSegment.positions,
        BalancesSegment.dollars,
        BalancesSegment.investing,
      ]);
      expect(segments[0].$2, moreOrLessEquals(0.6));
      expect(segments[1].$2, moreOrLessEquals(0.3));
      expect(segments[2].$2, moreOrLessEquals(0.1));
      // The chart ramp by rank, in light and dark; a sliver is grey.
      for (final c in [AppColorsExtension.light(), AppColorsExtension.dark()]) {
        expect(balancesBarColors(c, segments), {
          BalancesSegment.positions: c.chartCategorical[0],
          BalancesSegment.dollars: c.chartCategorical[1],
          BalancesSegment.investing: c.chartCategorical[2],
        });
        final sliver = balancesBarSegments([
          entry(BalancesPart.dollars, 99),
          entry(BalancesPart.investing, 1, 0),
        ]);
        expect(sliver.map((s) => s.$1),
            [BalancesSegment.dollars, BalancesSegment.investing]);
        expect(balancesBarColors(c, sliver)[BalancesSegment.investing],
            c.chartOther);
      }
      // All three cash and the positions: four segments.
      expect(
          balancesBarSegments([
            entry(BalancesPart.dollars, 1),
            entry(BalancesPart.investing, 2, 3),
            entry(BalancesPart.predictions, 4, 5),
          ]).length,
          4);
      // Nothing anywhere: the track only.
      expect(balancesBarSegments([entry(BalancesPart.dollars, 0)]), isEmpty);
    });

    test('an unknown balance: no segments, no summary, never a guess', () {
      final unknown = [
        entry(BalancesPart.dollars, 0.06),
        entry(BalancesPart.investing, null, null),
        entry(BalancesPart.predictions, 9.56, 0),
      ];
      expect(balancesBarSegments(unknown), isEmpty);
      final sum = balancesSummary(unknown);
      expect(sum.total, isNull);
      expect(sum.ready, isNull);
      expect(sum.inPositions, isNull);
    });

    test(
        'ready to use is every cash, in positions every position, counted '
        'across both venues', () {
      final entries = [
        entry(BalancesPart.dollars, 0.06),
        entry(BalancesPart.investing, 0.45, 10.82, 2),
        entry(BalancesPart.predictions, 9.56, 3, 3),
      ];
      final sum = balancesSummary(entries);
      expect(sum.ready, moreOrLessEquals(10.07));
      expect(sum.inPositions, moreOrLessEquals(13.82));
      expect(sum.total, moreOrLessEquals(23.89));
      expect(balancesPositionCount(entries), 5);
    });

    test(
        'Predictions\' Invested: its predictions apart from what open orders '
        'reserve, the two adding up to it', () {
      const state = OneBalanceState(
        investedUsd: 17.39,
        investedByVenue: {OneBalanceVenue.predictions: 17.39},
        predictionsKnown: true,
      );
      final split = breakdownPredictionsSplit(state, reserved: 0.22);
      expect(split.held, moreOrLessEquals(17.17));
      expect(split.reserved, moreOrLessEquals(0.22));
      expect(split.held + split.reserved, moreOrLessEquals(17.39));
      // No order: everything is predictions.
      expect(breakdownPredictionsSplit(state, reserved: 0).held,
          moreOrLessEquals(17.39));
      // A reserve the read has not counted yet never goes negative.
      final over = breakdownPredictionsSplit(state, reserved: 40);
      expect(over.held, 0);
      expect(over.reserved, moreOrLessEquals(17.39));
      expect(breakdownPredictionsSplit(state, reserved: double.nan).reserved,
          0);
    });

    test(
        'a bet matched a moment ago counts as a prediction beside its value, '
        'once, until the positions read lists it', () {
      Position listed(String asset) => Position(
            proxyWallet: '0xw',
            asset: asset,
            conditionId: 'c-$asset',
            size: 10,
            avgPrice: 0.5,
            initialValue: 5,
            currentValue: 5,
            cashPnl: 0,
            percentPnl: 0,
            totalBought: 5,
            realizedPnl: 0,
            percentRealizedPnl: 0,
            curPrice: 0.5,
            redeemable: false,
            title: 'Q $asset',
            slug: 's-$asset',
            eventSlug: 'e-$asset',
            outcome: 'Yes',
            outcomeIndex: 0,
            oppositeOutcome: 'No',
            oppositeAsset: 'o-$asset',
          );
      PolymarketPendingFill fill(String token, {bool indexed = false}) =>
          PolymarketPendingFill(
            key: 'k-$token-$indexed',
            tokenId: token,
            shares: 10,
            price: 0.5,
            costUsd: 5,
            expectedShares: 10,
            cashBeforeUsd: 20,
            at: DateTime(2026, 10, 25),
            indexed: indexed,
          );
      // One listed, one just matched (not listed), one matched and already
      // listed, one indexed: two predictions.
      final pm = PolymarketTradingState(
        isAuthenticated: true,
        openPositions: [listed('a')],
        pendingFills: [fill('b'), fill('a'), fill('c', indexed: true)],
      );
      expect(breakdownPredictionsCount(pm, listed: 1), 2);
      // Two fills of the same outcome: one prediction.
      final twice = PolymarketTradingState(
          isAuthenticated: true,
          pendingFills: [fill('b'), fill('b', indexed: false)]);
      expect(breakdownPredictionsCount(twice, listed: 0), 1);
      expect(breakdownPredictionsCount(null, listed: 3), 3);
    });

    test(
        'an open order\'s reserve: in the account\'s total and in positions '
        '(the header\'s Invested), never ready to use', () {
      final entries = [
        entry(BalancesPart.dollars, 0),
        entry(BalancesPart.investing, 17.21, 0),
        BalancesEntry(
          part: BalancesPart.predictions,
          asset: '',
          name: 'predictions',
          cash: const BalancesFigure(r'$0.43', usd: 0.43),
          positions: const BalancesFigure(r'$17.17', usd: 17.17),
          reservedUsd: 0.22,
          positionCount: 2,
        ),
      ];
      final sum = balancesSummary(entries);
      expect(sum.ready, moreOrLessEquals(17.64));
      expect(sum.inPositions, moreOrLessEquals(17.39));
      expect(sum.total, moreOrLessEquals(35.03));
      expect(entries[2].totalUsd, moreOrLessEquals(17.82));
      // Unknown positions: the reserve is not counted on its own.
      const unknown = BalancesEntry(
          part: BalancesPart.predictions,
          asset: '',
          name: 'predictions',
          cash: BalancesFigure(r'$0.43', usd: 0.43),
          positions: BalancesFigure('—'),
          reservedUsd: 0.22);
      expect(unknown.totalUsd, moreOrLessEquals(0.43));
      expect(balancesSummary([unknown]).inPositions, isNull);
    });

    testWidgets(
        "the founder's balances: the total, its bar, Ready to use over a row "
        'per account, then one In positions row', (tester) async {
      final c = await _pump(tester,
          home: overviewBreakdown,
          trading:
              const HyperliquidTradingState(isInitialized: true, positions: [
            _crossBtc,
          ]));
      c.read(_balance.notifier).state = founder;
      await tester.pumpAndSettle();
      expect(find.text('Total'), findsOneWidget);
      expect(figureOf(tester, 'portfolio-balance-total'), r'$20.89');
      expect(find.text('Ready to use'), findsOneWidget);
      expect(figureOf(tester, 'portfolio-balance-ready'), r'$10.07');
      // No ring, no tiles, no cards, no per-venue positions line.
      expect(find.byKey(const ValueKey('portfolio-balance-row')), findsNothing);
      expect(find.text('Cash'), findsNothing);
      expect(find.textContaining('available'), findsNothing);
      expect(find.textContaining('prediction'), findsNothing);

      // Each account's cash on its row, its mark beside it.
      expect(amount(tester, 'dollars'), r'$0.06');
      expect(amount(tester, 'investing'), r'$0.45');
      expect(amount(tester, 'predictions'), r'$9.56');
      for (final venue in ['dollars', 'investing', 'predictions']) {
        expect(_inCard(venue, find.byType(SvgPicture)), findsOneWidget);
        // No legend dot before the name any more.
        expect(find.byKey(ValueKey('portfolio-balance-$venue-dot')),
            findsNothing);
      }
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('portfolio-balance-overview')),
              matching: find.byWidgetPredicate((w) =>
                  w is Container &&
                  w.decoration is BoxDecoration &&
                  (w.decoration! as BoxDecoration).shape == BoxShape.circle)),
          findsNothing);

      // In positions: one row, every position together, counted.
      expect(find.text('In positions'), findsOneWidget);
      expect(amount(tester, 'positions'), r'$10.82');
      expect(positionsLine(tester), '1 position');

      // Four segments: the three cash and the positions, by rank of size
      // (positions, Predictions, Investing, then Dollars under 2%, grey).
      final c0 = AppColorsExtension.light();
      for (final (name, color) in [
        ('positions', c0.chartCategorical[0]),
        ('predictions', c0.chartCategorical[1]),
        ('investing', c0.chartCategorical[2]),
        ('dollars', c0.chartOther),
      ]) {
        expect(segment(name), findsOneWidget);
        expect(tester.getSize(segment(name)).height, greaterThan(0));
        expect(tester.widget<ColoredBox>(segment(name)).color, color);
      }

      // In order: Ready to use, the rows, In positions, Move money.
      final ready =
          tester.getRect(find.byKey(const ValueKey('portfolio-balance-ready')));
      final d = _tile(tester, 'dollars');
      final i = _tile(tester, 'investing');
      final p = _tile(tester, 'predictions');
      final held = _tile(tester, 'positions');
      expect(d.top, greaterThan(ready.bottom));
      expect(i.top, greaterThan(d.bottom));
      expect(p.top, greaterThan(i.bottom));
      expect(held.top, greaterThan(p.bottom));
      expect(tester.getRect(_rebalance).top, greaterThan(held.bottom));
      // Plain rows: no card under them.
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('portfolio-balance-overview')),
              matching: find.byWidgetPredicate((w) =>
                  w is Container &&
                  w.decoration is BoxDecoration &&
                  (w.decoration! as BoxDecoration).shape ==
                      BoxShape.rectangle &&
                  ((w.decoration! as BoxDecoration).color != null ||
                      (w.decoration! as BoxDecoration).boxShadow != null))),
          findsNothing);
      // Without a Positions section to open, In positions is not a button.
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('portfolio-balance-positions')),
              matching: find.byType(InkWell)),
          findsNothing);
      // Drawn once, then still: nothing ticks.
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('In positions opens the Positions section', (tester) async {
      var opened = 0;
      final home = Scaffold(
          body: SingleChildScrollView(
              child: PortfolioBalanceBreakdown(
                  trading: true,
                  predictions: true,
                  overview: true,
                  onPositions: () => opened++)));
      final c = await _pump(tester, home: home);
      c.read(_balance.notifier).state = founder;
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const ValueKey('portfolio-balance-positions')));
      await tester.pumpAndSettle();
      expect(opened, 1);
      // The account rows stay still.
      await tester.tap(find.byKey(const ValueKey('portfolio-balance-dollars')));
      await tester.pumpAndSettle();
      expect(opened, 1);
    });

    testWidgets(
        r'an empty account: its row at $0.00, no segment; nothing held: '
        'no positions segment, no count', (tester) async {
      final c = await _pump(tester, home: overviewBreakdown);
      c.read(_balance.notifier).state = const OneBalanceState(
        dollarsUsd: 12,
        investingKnown: true,
        predictionsKnown: true,
        venueCash: {OneBalanceVenue.predictions: 4},
      );
      await tester.pumpAndSettle();
      expect(segment('dollars'), findsOneWidget);
      expect(segment('investing'), findsNothing);
      expect(segment('predictions'), findsOneWidget);
      expect(segment('positions'), findsNothing);
      expect(amount(tester, 'investing'), r'$0.00');
      expect(figureOf(tester, 'portfolio-balance-ready'), r'$16.00');
      expect(amount(tester, 'positions'), r'$0.00');
      expect(positionsLine(tester), isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'predictions held: counted as positions, and an open order\'s '
        'reserve under Predictions', (tester) async {
      PolymarketPosition held(String token) => PolymarketPosition(
          marketId: 'm-$token',
          marketQuestion: 'Q $token',
          outcome: 'Yes',
          size: 2,
          avgPrice: 0.5,
          currentPrice: 0.5,
          pnl: 0,
          pnlPercent: 0,
          isResolved: false,
          tokenId: token);
      final c = await _pump(tester, home: overviewBreakdown, overrides: [
        polymarketTradingProvider.overrideWith(_PolyWithOrders.new),
        polymarketActivePositionsProvider
            .overrideWith((_) => [held('a'), held('b')]),
      ]);
      c.read(_balance.notifier).state = const OneBalanceState(
        dollarsUsd: 1,
        investedUsd: 6,
        investedByVenue: {OneBalanceVenue.predictions: 6},
        investingKnown: true,
        predictionsKnown: true,
        venueCash: {OneBalanceVenue.predictions: 6},
      );
      await tester.pumpAndSettle();
      expect(amount(tester, 'predictions'), r'$6.00');
      expect(amount(tester, 'positions'), r'$6.00');
      expect(positionsLine(tester), '2 positions');
      expect(_inCard('predictions', find.text(r'$4.00 in open orders')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(r'a balance not read yet: a sweeping dash, never $0.00',
        (tester) async {
      final c = await _pump(tester, home: overviewBreakdown, overrides: [
        hyperliquidDisplayTradingProvider
            .overrideWith((_) => const AsyncLoading<HyperliquidTradingState>()),
      ]);
      c.read(_balance.notifier).state =
          const OneBalanceState(dollarsUsd: 0.06, predictionsKnown: true);
      // The dash sweeps for good: frames, not a settle.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(amount(tester, 'investing'), '—');
      expect(sweeping(tester, 'portfolio-balance-investing-amount'), isTrue);
      expect(_inCard('investing', _figure(r'$0.00')), findsNothing);
      expect(_inCard('investing', find.textContaining(r'$0.00')), findsNothing);
      // The whole is not known: no total, no sums, no bar.
      expect(figureOf(tester, 'portfolio-balance-total'), '—');
      expect(figureOf(tester, 'portfolio-balance-ready'), '—');
      expect(amount(tester, 'positions'), '—');
      expect(sweeping(tester, 'portfolio-balance-positions-amount'), isTrue);
      for (final name in ['dollars', 'investing', 'predictions', 'positions']) {
        expect(segment(name), findsNothing);
      }
      expect(amount(tester, 'dollars'), r'$0.06');
      expect(sweeping(tester, 'portfolio-balance-dollars-amount'), isFalse);
      expect(amount(tester, 'predictions'), r'$0.00');
      expect(tester.takeException(), isNull);
    });

    testWidgets('Reduce Motion: drawn at once, nothing animates',
        (tester) async {
      await tester.pumpWidget(const SizedBox());
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final c = await _pump(tester, home: overviewBreakdown, settle: false);
      c.read(_balance.notifier).state = founder;
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(segment('positions'), findsOneWidget);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('375 pt at 130 % text, long amounts: nothing overflows',
        (tester) async {
      final c = await _pump(tester,
          home: overviewBreakdown, size: const Size(375, 812), textScale: 1.3);
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
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(amount(tester, 'investing'), r'$45,678.90');
      expect(amount(tester, 'positions'), r'$1,111,111.11');
      expect(_tile(tester, 'positions').right, lessThanOrEqualTo(375));
      expect(_tile(tester, 'predictions').right, lessThanOrEqualTo(375));
    });
  });
}

/// The breakdown that can be left and opened again ([shown]).
class _Toggle extends StatelessWidget {
  const _Toggle();

  static final shown = ValueNotifier<bool>(true);

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
      valueListenable: shown,
      builder: (_, on, __) => on ? _breakdown : const Scaffold());
}

RubberBandProgressState _band(WidgetTester tester, String venue) =>
    tester.state<RubberBandProgressState>(find.descendant(
        of: find.byKey(ValueKey('portfolio-band-$venue')),
        matching: find.byType(RubberBandProgress)));

RubberBandProgress _bandWidget(WidgetTester tester, String venue) =>
    tester.widget<RubberBandProgress>(find.descendant(
        of: find.byKey(ValueKey('portfolio-band-$venue')),
        matching: find.byType(RubberBandProgress)));

RubberBandProgressState _buttonBand(WidgetTester tester) =>
    tester.state<RubberBandProgressState>(find.ancestor(
        of: _rebalance, matching: find.byType(RubberBandProgress)));

/// The Dollars column's catch, as a share of its height (down is
/// positive).
double _dollarsDip(WidgetTester tester) => tester
    .widget<FractionalTranslation>(find
        .descendant(
            of: find.byKey(const ValueKey('portfolio-band-dollars')),
            matching: find.byType(FractionalTranslation))
        .first)
    .translation
    .dy;

/// The bands' haptics, through the bridge's test seam.
List<ContinuousHapticsCall> _feel() {
  ContinuousHaptics.debugReset();
  final log = ContinuousHaptics.debugLog = <ContinuousHapticsCall>[];
  addTearDown(() => ContinuousHaptics.debugLog = null);
  return log;
}

/// The whoosh and the snap, one per landing.
int _snaps(List<ContinuousHapticsCall> log) =>
    log.where((c) => c.method == 'snap').length;

/// A move home from a venue ([network] 'POLYGON' or 'HYPERCORE').
SwapOrder _homeRow(String id, String network,
        {String status = 'exchanging', DateTime? at}) =>
    SwapOrder(
      id: id,
      coinFrom: 'USDC',
      networkFrom: network,
      coinTo: 'USDB',
      networkTo: 'SPARK',
      depositAddress: 'deposit',
      depositAmount: '3.00',
      withdrawalAmount: '3.00',
      status: status,
      timestamp: (at ?? DateTime.now()).millisecondsSinceEpoch,
      withdrawalAddress: 'spark',
      depositMin: '0',
      depositMax: '0',
      rate: '0',
      refundAddress: 'refund',
      provider: 'Orchestra',
    );

/// The test balance with [usd] on its way home from each venue.
OneBalanceState _homeward(Map<OneBalanceVenue, double> usd) => OneBalanceState(
      dollarsUsd: 42.5,
      investedUsd: 605,
      investedByVenue: const {
        OneBalanceVenue.investing: 600,
        OneBalanceVenue.predictions: 5,
      },
      investingKnown: true,
      predictionsKnown: true,
      inFlight: [
        for (final e in usd.entries)
          InFlightMove(
              kind: InFlightKind.fromVenue, venue: e.key, usd: e.value),
      ],
    );
