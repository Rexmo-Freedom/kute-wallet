// The top of the Portfolio (founder request, October 2026): the
// Investments balance's cash part by part (Dollars, Investing,
// Predictions), live on the one-balance state, with one Rebalance that
// runs one manual sweeper pass; and the Positions section (the Positions
// pill's rows) above the Activity.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
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
import 'package:kute/providers/one_balance_provider.dart';
import 'package:kute/providers/polymarket_open_orders_provider.dart';
import 'package:kute/providers/polymarket_order_metadata_provider.dart';
import 'package:kute/providers/portfolio_rebalance_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/venue_sweeper_provider.dart';
import 'package:kute/screens/portfolio/open_investments_screen.dart';
import 'package:kute/screens/portfolio/portfolio_balance_breakdown.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_motion.dart' show RollingFigure;
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/sweep_rules.dart'
    show SweepSkipReason;
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart' show Order;

import '../../helpers/portfolio_overrides.dart';

final _balance = StateProvider<OneBalanceState>((_) => const OneBalanceState(
      dollarsUsd: 42.5,
      investingKnown: true,
      predictionsKnown: true,
      venueCash: {OneBalanceVenue.investing: 6.54},
      waiting: {OneBalanceVenue.predictions: 3},
    ));

final _sweeperState =
    StateProvider<VenueSweeperState>((_) => const VenueSweeperState());

/// The sweeper as the Portfolio sees it: its state from [_sweeperState],
/// and a Rebalance that waits on [gate] and answers [outcomes].
class _FakeSweeper extends VenueSweeperNotifier {
  static int calls = 0;
  static Completer<void>? gate;
  static Map<OneBalanceVenue, RebalanceOutcome> outcomes = const {};

  @override
  VenueSweeperState build() => ref.watch(_sweeperState);

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

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required Widget home,
  HyperliquidTradingState trading = const HyperliquidTradingState(),
  Size size = const Size(400, 1000),
  double textScale = 1,
  List<NavigatorObserver> observers = const [],
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
  await tester.pumpAndSettle();
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
    _FakeSweeper.gate = null;
    _FakeSweeper.outcomes = const {};
  });

  group('the balance breakdown', () {
    testWidgets(
        'Dollars, Investing and Predictions with their marks and cash, '
        'following the one-balance state', (tester) async {
      final c = await _pump(tester, home: _breakdown);
      expect(_inCard('dollars', find.text('Dollars')), findsOneWidget);
      expect(_inCard('dollars', find.text('USDB')), findsOneWidget);
      expect(_inCard('dollars', _figure(r'$42.50')), findsOneWidget);
      expect(_inCard('investing', find.text('Investing')), findsOneWidget);
      expect(_inCard('investing', find.text('Hyperliquid')), findsOneWidget);
      expect(_inCard('investing', _figure(r'$6.54')), findsOneWidget);
      expect(_inCard('predictions', find.text('Predictions')), findsOneWidget);
      expect(_inCard('predictions', find.text('Polymarket')), findsOneWidget);
      expect(_inCard('predictions', _figure(r'$3.00')), findsOneWidget);
      // Top down: Dollars, Investing, Predictions.
      double top(String v) =>
          tester.getTopLeft(find.byKey(ValueKey('portfolio-balance-$v'))).dy;
      expect(top('dollars'), lessThan(top('investing')));
      expect(top('investing'), lessThan(top('predictions')));

      // Live: the rows follow the provider.
      c.read(_balance.notifier).state = const OneBalanceState(
          dollarsUsd: 49.04, investingKnown: true, predictionsKnown: true);
      await tester.pumpAndSettle();
      expect(_inCard('dollars', _figure(r'$49.04')), findsOneWidget);
      expect(_inCard('investing', _figure(r'$0.00')), findsOneWidget);
      expect(_inCard('predictions', _figure(r'$0.00')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a venue not read yet reads a dash, never a guess',
        (tester) async {
      final c = await _pump(tester, home: _breakdown);
      c.read(_balance.notifier).state =
          const OneBalanceState(dollarsUsd: 1, predictionsKnown: true);
      await tester.pumpAndSettle();
      expect(_inCard('investing', _figure('—')), findsOneWidget);
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
      expect(_inCard('dollars', _rebalance), findsOneWidget);
      expect(_inCard('dollars', find.text('Rebalance')), findsOneWidget);

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
