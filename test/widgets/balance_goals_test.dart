import 'package:coingecko_api/data/market_chart_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/balance_history.dart';
import 'package:kute/models/balance_model.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/analytics_provider.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/coingecko_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/transactions_provider.dart';
import 'package:kute/providers/viewed_wallet_provider.dart';
import 'package:kute/screens/analytics/components/balance_goals.dart';
import 'package:kute/screens/analytics/components/home_analytics_widget.dart';
import 'package:kute/screens/home/components/deposit_sheet.dart';
import 'package:kute/screens/shared/charts/kute_trend_chart.dart';
import 'package:kute/services/balance_milestones.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart';

class _MapFlags implements BalanceMilestoneFlags {
  final Set<String> claimed = {};

  @override
  bool isClaimed(String key) => claimed.contains(key);

  @override
  bool claim(String key) => claimed.add(key);
}

class _Market extends BitcoinMarketDataNotifier {
  _Market(this.data);
  final List<MarketChartData> data;
  @override
  Future<List<MarketChartData>> build() async => data;
}

/// The input the tests drive, swapped mid-test.
final _input = StateProvider<BalanceGoalInput?>((_) => null);

/// The Bitcoin home's milestones on its Balance tab (founder, 6 November
/// 2026): the level and progress under the range row, the goal line on
/// the plot while it is in reach, a once-only celebration with Sal and
/// confetti when a round figure is passed, the Move to Dollars nudge
/// opening the Move sheet locked to Dollars with a suggested amount, all
/// of it dots (or nothing) with balances hidden; and the Balance cards
/// hugging their content (founder: "card bottom is not great, it expands
/// too much").
void main() {
  const price = 70000.0;

  Settings settings({int privacy = 0}) => Settings(
        currency: 'USD',
        language: 'en',
        btcFormat: 'sats',
        backup: false,
        biometricsEnabled: false,
        bitcoinElectrumNode: '',
        nodeType: '',
        reviewDone: true,
        activeWalletId: 'spending',
        balancePrivacy: privacy,
        wallets: [WalletConfig(id: 'spending', name: 'Spending')],
      );

  BalanceGoalInput input({
    int sats = 355000,
    double cashUsd = 0,
    bool ready = true,
    bool swap = true,
    bool investing = true,
    bool predictions = true,
  }) =>
      BalanceGoalInput(
        ready: ready,
        currency: 'USD',
        bitcoinSats: sats,
        fiatPerBtc: price,
        usdToDisplay: 1,
        cashUsd: cashUsd,
        canMoveToDollars: swap,
        investing: investing,
        predictions: predictions,
      );

  late _MapFlags flags;
  late List<(String, Map<String, Object>?)> events;

  setUp(() {
    flags = _MapFlags();
    events = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });

  tearDown(() {
    TrackingService.debugTrackObserver = null;
    BalanceGoalsChart.debugMoveOpener = null;
  });

  List<Override> overrides({int sats = 355000, int privacy = 0}) {
    // Flat at [sats] for the month: the bitcoin held two months ago.
    final history = BalanceHistory(
      opening: 0,
      changes: [
        (DateTime.now().subtract(const Duration(days: 60)), sats.toDouble())
      ],
      current: sats.toDouble(),
    );
    final prices = [
      for (var ago = 90; ago >= 0; ago--)
        MarketChartData(
          DateTime.now().subtract(Duration(days: ago)),
          price: price,
          marketCap: 0,
          totalVolume: 0,
        ),
    ];
    return [
      settingsProvider
          .overrideWith((_) => SettingsModel(settings(privacy: privacy))),
      bitcoinMarketDataProvider.overrideWith(() => _Market(prices)),
      bitcoinBalanceStepsProvider.overrideWith((_) => history),
      bitcoinBalanceInFormatByDayProvider.overrideWith((_) => {}),
      viewedWalletBalanceProvider.overrideWithValue(
          WalletBalance(onChainBtcBalance: 0, sparkBitcoinbalance: sats)),
      polymarketBalanceProvider.overrideWith((_) => 0),
      selectedCurrencyProvider.overrideWith(
          (ref, code) => Money.fromNumWithCurrency(price, AppCurrencies.usd)),
      selectedCurrencyProviderFromUSD.overrideWith(
          (ref, code) => Money.fromNumWithCurrency(1, AppCurrencies.usd)),
      viewedWalletProvider.overrideWithValue(null),
      viewedWalletTransactionsProvider.overrideWithValue(Transaction.empty()),
      balanceGoalInputProvider.overrideWith((ref) => ref.watch(_input)),
      balanceMilestoneFlagsProvider.overrideWithValue(flags),
    ];
  }

  Widget app(Widget child, {bool reduceMotion = false}) => ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          locale: const Locale('en'),
          theme: buildLightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(disableAnimations: reduceMotion),
              child: Scaffold(body: SingleChildScrollView(child: child)),
            ),
          ),
        ),
      );

  /// The Bitcoin home's analytics (its Balance tab, as no Activity list
  /// is passed) with the milestones on, over [first].
  Future<ProviderContainer> pump(
    WidgetTester tester,
    BalanceGoalInput? first, {
    int? sats,
    int privacy = 0,
    bool reduceMotion = false,
    Widget child =
        const HomeAnalyticsWidget(surface: 'home', balanceGoals: true),
  }) async {
    tester.view.physicalSize = const Size(393, 852) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(
        overrides: overrides(
            sats: sats ?? first?.bitcoinSats ?? 355000, privacy: privacy));
    addTearDown(container.dispose);
    container.read(_input.notifier).state = first;
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: app(child, reduceMotion: reduceMotion),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return container;
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 8));
  }

  String text(WidgetTester tester, String key) {
    final w = tester.widget(find.byKey(ValueKey(key)));
    if (w is Text) return w.textSpan?.toPlainText() ?? w.data!;
    throw StateError('$key is ${w.runtimeType}');
  }

  KuteTrendChart chart(WidgetTester tester) =>
      tester.widget<KuteTrendChart>(find.byType(KuteTrendChart));

  double barFill(WidgetTester tester) =>
      tester
          .getSize(find.byKey(const ValueKey('balance-goal-bar-fill')))
          .width /
      tester.getSize(find.byKey(const ValueKey('balance-goal-bar'))).width;

  Finder confetti() => find.byKey(const ValueKey('kute-confetti'));

  testWidgets(
      r'the level and the progress to the next goal under the range row; '
      'the goal line on the plot while it is in reach', (tester) async {
    // ₿355,000 at $70,000: $248.50, the next goal $250.
    await pump(tester, input());
    expect(text(tester, 'balance-goal-level'), 'Level 2 · Pocket money');
    expect(text(tester, 'balance-goal-progress'), r'99% to $250');
    expect(barFill(tester), closeTo(0.994, 0.01));
    // Under the range row.
    expect(
        tester.getTopLeft(find.byKey(const ValueKey('balance-goal-footer'))).dy,
        greaterThanOrEqualTo(
            tester.getBottomLeft(find.byType(KuteChartRangeRow)).dy));
    // The goal line: the bitcoin now plus the gap at today's price.
    final goal = chart(tester).goal;
    expect(goal, isNotNull);
    expect(goal!.label, r'Next $250');
    expect(goal.value, closeTo(355000 + 1.5 / price * 1e8, 1));
    await settle(tester);
  });

  testWidgets('a goal far above the line is not drawn; the footer still is',
      (tester) async {
    // $105 of bitcoin, $250 to go for: the line would be squashed.
    await pump(tester, input(sats: 150000));
    expect(chart(tester).goal, isNull);
    expect(text(tester, 'balance-goal-progress'), r'42% to $250');
    await settle(tester);
  });

  testWidgets(
      'Dollars count: moving bitcoin to Dollars never lowers the progress',
      (tester) async {
    final container = await pump(tester, input());
    expect(text(tester, 'balance-goal-progress'), r'99% to $250');
    // Half the bitcoin is now $124.25 of Dollars.
    container.read(_input.notifier).state =
        input(sats: 177500, cashUsd: 124.25);
    await tester.pump(const Duration(milliseconds: 600));
    expect(text(tester, 'balance-goal-progress'), r'99% to $250');
    expect(text(tester, 'balance-goal-level'), 'Level 2 · Pocket money');
    await settle(tester);
  });

  testWidgets(
      'a rate refresh that moves the goal line under 2% leaves it in place',
      (tester) async {
    final container = await pump(tester, input());
    final before = chart(tester).goal!.value;
    container.read(_input.notifier).state = BalanceGoalInput(
      ready: true,
      currency: 'USD',
      bitcoinSats: 355000,
      fiatPerBtc: price * 1.0005,
      usdToDisplay: 1,
      cashUsd: 0,
      canMoveToDollars: true,
      investing: true,
      predictions: true,
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(chart(tester).goal!.value, before);
    await settle(tester);
  });

  testWidgets(
      'a round figure passed: Sal, the line and confetti, once; then the '
      'next goal', (tester) async {
    final container = await pump(tester, input());
    // The first reading is history: recorded, nothing celebrated.
    await tester.pump(kBalanceMilestoneSettle);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('balance-goal-celebration-title')),
        findsNothing);
    expect(flags.claimed, contains('balance_milestone_USD_100'));
    expect(events.where((e) => e.$1 == 'balance_milestone_reached'), isEmpty);

    // A receive: ₿360,000 is $252.
    container.read(_input.notifier).state = input(sats: 360000);
    await tester.pump(const Duration(milliseconds: 100));
    // It must hold for the settle first.
    expect(find.byKey(const ValueKey('balance-goal-celebration-title')),
        findsNothing);
    await tester.pump(kBalanceMilestoneSettle);
    await tester.pump(const Duration(milliseconds: 100));
    expect(text(tester, 'balance-goal-celebration-title'), r'You passed $250');
    expect(
        find.text("Bitcoin and Dollars together. Sal is acting like it's "
            'nothing.'),
        findsOneWidget);
    expect(confetti(), findsOneWidget);
    // No goal line while it celebrates.
    expect(chart(tester).goal, isNull);
    final reached =
        events.where((e) => e.$1 == 'balance_milestone_reached').toList();
    expect(reached, hasLength(1));
    expect(reached.single.$2, {'milestone': 250, 'currency': 'USD'});

    // The burst is over in under two seconds.
    await tester.pump(const Duration(seconds: 2));
    expect(confetti(), findsNothing);
    // Back to the progress, towards $500.
    await tester.pump(kBalanceMilestoneCelebration);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('balance-goal-celebration-title')),
        findsNothing);
    expect(text(tester, 'balance-goal-level'), 'Level 3 · Stacker');
    expect(text(tester, 'balance-goal-progress'), r'50% to $500');

    // Down and back up again: never twice.
    container.read(_input.notifier).state = input(sats: 340000);
    await tester.pump(const Duration(milliseconds: 100));
    container.read(_input.notifier).state = input(sats: 362000);
    await tester.pump(kBalanceMilestoneSettle);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('balance-goal-celebration-title')),
        findsNothing);
    expect(
        events.where((e) => e.$1 == 'balance_milestone_reached'), hasLength(1));
    await settle(tester);
  });

  testWidgets('a figure that does not hold for the settle is not celebrated',
      (tester) async {
    final container = await pump(tester, input());
    await tester.pump(kBalanceMilestoneSettle);
    await tester.pump(const Duration(milliseconds: 100));
    container.read(_input.notifier).state = input(sats: 360000);
    await tester.pump(const Duration(milliseconds: 300));
    // A blip: back under before it held.
    container.read(_input.notifier).state = input(sats: 355000);
    await tester.pump(kBalanceMilestoneSettle);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('balance-goal-celebration-title')),
        findsNothing);
    expect(flags.claimed, isNot(contains('balance_milestone_USD_250')));
    await settle(tester);
  });

  testWidgets('Reduce Motion: Sal and the line, no confetti', (tester) async {
    final container = await pump(tester, input(), reduceMotion: true);
    await tester.pump(kBalanceMilestoneSettle);
    await tester.pump(const Duration(milliseconds: 100));
    container.read(_input.notifier).state = input(sats: 360000);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(kBalanceMilestoneSettle);
    await tester.pump(const Duration(milliseconds: 100));
    expect(text(tester, 'balance-goal-celebration-title'), r'You passed $250');
    expect(confetti(), findsNothing);
    await settle(tester);
  });

  testWidgets(
      'balances hidden: dots, the bar empty, no goal line, the nudge without '
      'its amount, and no celebration until the figures are back',
      (tester) async {
    final container = await pump(tester, input(), privacy: 1);
    expect(text(tester, 'balance-goal-level'), '••••••');
    expect(text(tester, 'balance-goal-progress'), '••••••');
    expect(barFill(tester), 0);
    expect(chart(tester).goal, isNull);
    expect(text(tester, 'balance-goal-nudge-label'), 'Move to Dollars');
    expect(find.textContaining(r'$'), findsNothing);
    // Nothing is recorded over hidden figures.
    container.read(_input.notifier).state = input(sats: 360000);
    await tester.pump(kBalanceMilestoneSettle);
    await tester.pump(const Duration(milliseconds: 100));
    expect(flags.claimed, isEmpty);
    expect(find.byKey(const ValueKey('balance-goal-celebration-title')),
        findsNothing);
    await settle(tester);
  });

  testWidgets(
      r'the nudge: "Move $25 to Dollars" opens the Move sheet locked to '
      'Dollars with \$25 filled in', (tester) async {
    final opened = <(MoveLockedSide, double)>[];
    BalanceGoalsChart.debugMoveOpener =
        (context, side, usd) => opened.add((side, usd));
    await pump(tester, input());
    expect(text(tester, 'balance-goal-nudge-label'), r'Move $25 to Dollars');
    expect(
        text(tester, 'balance-goal-nudge-line'),
        'Your money, more places to go: Investing and Predictions in '
        'Dollars.');
    await tester.tap(find.byKey(const ValueKey('balance-goal-nudge')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(opened, [(MoveLockedSide.depositToUsd, 25.0)]);
    final tapped =
        events.where((e) => e.$1 == 'balance_goal_cta_tapped').toList();
    expect(tapped, hasLength(1));
    expect(
        tapped.single.$2, {'milestone': 250, 'amount': 25, 'currency': 'USD'});
    await settle(tester);
  });

  testWidgets(
      'the nudge names only what is live, and is gone where the move or '
      'both venues are not', (tester) async {
    final container = await pump(tester, input(investing: false));
    expect(text(tester, 'balance-goal-nudge-line'),
        'Your money, more places to go: Predictions in Dollars.');
    container.read(_input.notifier).state = input(predictions: false);
    await tester.pump(const Duration(milliseconds: 100));
    expect(text(tester, 'balance-goal-nudge-line'),
        'Your money, more places to go: Investing in Dollars.');
    container.read(_input.notifier).state =
        input(investing: false, predictions: false);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('balance-goal-nudge')), findsNothing);
    container.read(_input.notifier).state = input(swap: false);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('balance-goal-nudge')), findsNothing);
    // Nothing worth moving: under a dollar of bitcoin.
    container.read(_input.notifier).state = input(sats: 1000, cashUsd: 300);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('balance-goal-nudge')), findsNothing);
    // The milestones still read the Dollars.
    expect(text(tester, 'balance-goal-progress'), r'60% to $500');
    await settle(tester);
  });

  testWidgets('not ready, or not the spending wallet: no milestones at all',
      (tester) async {
    final container = await pump(tester, input(ready: false));
    expect(find.byKey(const ValueKey('balance-goal-footer')), findsNothing);
    expect(chart(tester).goal, isNull);
    container.read(_input.notifier).state = null;
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('balance-goal-footer')), findsNothing);
    await tester.pump(kBalanceMilestoneSettle);
    expect(flags.claimed, isEmpty);
    await settle(tester);
  });

  testWidgets('another wallet screen never shows them', (tester) async {
    await pump(tester, input(),
        child: const HomeAnalyticsWidget(surface: 'wallet_detail'));
    expect(find.byKey(const ValueKey('balance-goal-footer')), findsNothing);
    await settle(tester);
  });

  group('the card hugs the milestones', () {
    double bottomGap(WidgetTester tester, Finder last) =>
        tester.getBottomLeft(find.byKey(const ValueKey('balance-card'))).dy -
        tester.getBottomLeft(last).dy;

    final pad = 16 * 393 / 430;

    testWidgets('with the milestones, 16 under the nudge', (tester) async {
      await pump(tester, input());
      expect(
          bottomGap(tester, find.byKey(const ValueKey('balance-goal-footer'))),
          closeTo(pad, 0.5));
      await settle(tester);
    });

    testWidgets('and 16 under the progress when there is no nudge',
        (tester) async {
      await pump(tester, input(swap: false));
      expect(
          bottomGap(tester, find.byKey(const ValueKey('balance-goal-footer'))),
          closeTo(pad, 0.5));
      await settle(tester);
    });
  });
}
