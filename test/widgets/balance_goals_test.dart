import 'dart:convert';
import 'dart:io';

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
import 'package:kute/screens/analytics/components/balance_history_chart.dart';
import 'package:kute/screens/analytics/components/home_analytics_widget.dart';
import 'package:kute/screens/home/components/deposit_sheet.dart';
import 'package:kute/screens/shared/charts/kute_trend_chart.dart';
import 'package:kute/screens/shared/kute_motion.dart' show RollingFigure;
import 'package:kute/screens/shared/sal_sprite.dart';
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
/// 2026): the goal line on the plot while it is in reach; UNDER the card
/// (founder: "The design is too dense; must be better, like the things in
/// the Dollars screens"), "Goals" over the Level and Next goal squares and
/// the Move to Dollars nudge card; a once-only celebration with Sal and
/// confetti in the squares' place when a round figure is passed; the
/// nudge opening the Move sheet locked to Dollars with a suggested
/// amount; all of it dots (or nothing) with balances hidden; and the
/// Balance card hugging its chart, with nothing of the goals inside it.
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
    BalanceGoals.debugMoveOpener = null;
  });

  List<Override> overrides(
      {int sats = 355000, int privacy = 0, bool held = true}) {
    // Flat at [sats] for the month: the bitcoin held two months ago.
    // [held] false: nothing ever held (the card's empty state).
    final history = BalanceHistory(
      opening: 0,
      changes: [
        if (held)
          (DateTime.now().subtract(const Duration(days: 60)), sats.toDouble())
      ],
      current: held ? sats.toDouble() : 0,
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
    bool held = true,
    Widget child =
        const HomeAnalyticsWidget(surface: 'home', balanceGoals: true),
  }) async {
    tester.view.physicalSize = const Size(393, 852) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(
        overrides: overrides(
            sats: sats ?? first?.bitcoinSats ?? 355000,
            privacy: privacy,
            held: held));
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
    if (w is RollingFigure) return w.text;
    throw StateError('$key is ${w.runtimeType}');
  }

  KuteTrendChart chart(WidgetTester tester) =>
      tester.widget<KuteTrendChart>(find.byType(KuteTrendChart));

  double barFill(WidgetTester tester) =>
      tester.widget<BalanceGoalBar>(find.byType(BalanceGoalBar)).fraction;

  /// The still Sal wears in a square ('balance-goal-level-sal', ...).
  String sal(WidgetTester tester, String key) => tester
      .widget<SalSprite>(find.descendant(
          of: find.byKey(ValueKey(key)), matching: find.byType(SalSprite)))
      .clip;

  Rect rectOf(WidgetTester tester, String key) =>
      tester.getRect(find.byKey(ValueKey(key)));

  Finder confetti() => find.byKey(const ValueKey('kute-confetti'));

  testWidgets(
      r'under the card: "Goals", the Level and Next goal squares side by '
      'side, then the nudge; the goal line on the plot while it is in reach',
      (tester) async {
    // ₿355,000 at $70,000: $248.50, the next goal $250.
    await pump(tester, input());
    expect(text(tester, 'balance-goals-heading'), 'Goals');
    expect(text(tester, 'balance-goal-level'), 'Level 2');
    expect(text(tester, 'balance-goal-level-name'), 'Pocket money');
    expect(text(tester, 'balance-goal-progress'), r'99% to $250');
    expect(barFill(tester), closeTo(0.994, 0.01));
    expect(text(tester, 'balance-goal-next-label'), 'Next goal');
    expect(text(tester, 'balance-goal-next'), r'$250');
    expect(text(tester, 'balance-goal-to-go'), r'$1.50 to go');
    // Sal in both: the level's still (Pocket money: one coin) over the
    // bar, and the next goal's, squinting up at a flag.
    expect(sal(tester, 'balance-goal-level-sal'), 'level_2');
    expect(sal(tester, 'balance-goal-next-sal'), 'goal_next');
    final salRect = rectOf(tester, 'balance-goal-level-sal');
    final bar = tester.getRect(find.byType(BalanceGoalBar));
    expect(bar.top, greaterThan(salRect.bottom));
    expect(bar.width, closeTo(salRect.width, 0.5));

    // Nothing of the goals inside the card: they start under it.
    final card = rectOf(tester, 'balance-card');
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('balance-card')),
            matching: find.byKey(const ValueKey('balance-goals'))),
        findsNothing);
    expect(rectOf(tester, 'balance-goals').top,
        greaterThanOrEqualTo(card.bottom));
    // The two squares side by side, as tall as each other, the nudge
    // under them across both.
    final level = tester.getRect(find
        .ancestor(
            of: find.byKey(const ValueKey('balance-goal-level')),
            matching: find.byType(Container))
        .first);
    final next = tester.getRect(find
        .ancestor(
            of: find.byKey(const ValueKey('balance-goal-next')),
            matching: find.byType(Container))
        .first);
    expect(level.top, next.top);
    expect(level.height, next.height);
    expect(next.left, greaterThan(level.right));
    final nudge = rectOf(tester, 'balance-goal-nudge');
    expect(nudge.top, greaterThan(level.bottom));
    expect(nudge.left, closeTo(level.left, 0.5));
    expect(nudge.right, closeTo(next.right, 0.5));

    // The goal line: the bitcoin now plus the gap at today's price.
    final goal = chart(tester).goal;
    expect(goal, isNotNull);
    expect(goal!.label, r'Next $250');
    expect(goal.value, closeTo(355000 + 1.5 / price * 1e8, 1));
    await settle(tester);
  });

  testWidgets('a goal far above the line is not drawn; the squares still are',
      (tester) async {
    // $105 of bitcoin, $250 to go for: the line would be squashed.
    await pump(tester, input(sats: 150000));
    expect(chart(tester).goal, isNull);
    expect(text(tester, 'balance-goal-progress'), r'42% to $250');
    expect(text(tester, 'balance-goal-to-go'), r'$145 to go');
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
    expect(text(tester, 'balance-goal-level'), 'Level 2');
    expect(text(tester, 'balance-goal-to-go'), r'$1.50 to go');
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
      'a round figure passed: Sal, the line and confetti in the squares\' '
      'place, once, nothing under it moving; then the next goal',
      (tester) async {
    final container = await pump(tester, input());
    final nudgeTop = rectOf(tester, 'balance-goal-nudge').top;
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
    // In the squares' place at their height: the nudge has not moved.
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('balance-goal-squares')), findsNothing);
    expect(rectOf(tester, 'balance-goal-nudge').top, closeTo(nudgeTop, 0.5));
    // No goal line while it celebrates.
    expect(chart(tester).goal, isNull);
    final reached =
        events.where((e) => e.$1 == 'balance_milestone_reached').toList();
    expect(reached, hasLength(1));
    expect(reached.single.$2, {'milestone': 250, 'currency': 'USD'});

    // The burst is over in under two seconds.
    await tester.pump(const Duration(seconds: 2));
    expect(confetti(), findsNothing);
    // Back to the squares, towards $500.
    await tester.pump(kBalanceMilestoneCelebration);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('balance-goal-celebration-title')),
        findsNothing);
    expect(text(tester, 'balance-goal-level'), 'Level 3');
    expect(text(tester, 'balance-goal-level-name'), 'Stacker');
    // Sal moved up with the level, in place.
    expect(sal(tester, 'balance-goal-level-sal'), 'level_3');
    expect(text(tester, 'balance-goal-progress'), r'50% to $500');
    expect(text(tester, 'balance-goal-next'), r'$500');

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

  testWidgets('Reduce Motion: Sal and the line, no confetti, the bar at once',
      (tester) async {
    final container = await pump(tester, input(), reduceMotion: true);
    expect(barFill(tester), closeTo(0.994, 0.01));
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
    expect(text(tester, 'balance-goal-level-name'), '••••');
    expect(text(tester, 'balance-goal-progress'), '••••');
    expect(text(tester, 'balance-goal-next'), '••••••');
    expect(text(tester, 'balance-goal-to-go'), '••••');
    expect(text(tester, 'balance-goal-next-label'), 'Next goal');
    expect(barFill(tester), 0);
    // Sal names no level while the figures are hidden.
    expect(sal(tester, 'balance-goal-level-sal'), kBalanceGoalHiddenClip);
    expect(sal(tester, 'balance-goal-next-sal'), 'goal_next');
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
    BalanceGoals.debugMoveOpener =
        (context, side, usd) => opened.add((side, usd));
    await pump(tester, input());
    expect(text(tester, 'balance-goal-nudge-label'), r'Move $25 to Dollars');
    expect(text(tester, 'balance-goal-nudge-line'),
        'Your money, more places to go in Dollars.');
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
      'the nudge names no venue; it is there while either is live, and gone '
      'where the move or both venues are not', (tester) async {
    const line = 'Your money, more places to go in Dollars.';
    final container = await pump(tester, input(investing: false));
    expect(text(tester, 'balance-goal-nudge-line'), line);
    container.read(_input.notifier).state = input(predictions: false);
    await tester.pump(const Duration(milliseconds: 100));
    expect(text(tester, 'balance-goal-nudge-line'), line);
    expect(find.textContaining('Investing'), findsNothing);
    expect(find.textContaining('Predictions'), findsNothing);
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
    expect(find.byKey(const ValueKey('balance-goals')), findsNothing);
    expect(chart(tester).goal, isNull);
    container.read(_input.notifier).state = null;
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('balance-goals')), findsNothing);
    await tester.pump(kBalanceMilestoneSettle);
    expect(flags.claimed, isEmpty);
    await settle(tester);
  });

  testWidgets(
      'the goals arriving under the card never rebuild the card from scratch',
      (tester) async {
    final container = await pump(tester, input(ready: false));
    final before = tester.state(find.byType(BalanceHistoryChart));
    container.read(_input.notifier).state = input();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('balance-goals')), findsOneWidget);
    expect(tester.state(find.byType(BalanceHistoryChart)), same(before));
    await settle(tester);
  });

  testWidgets('nothing ever held: the empty state alone, nothing recorded',
      (tester) async {
    await pump(tester, input(cashUsd: 300), held: false);
    expect(find.byKey(const ValueKey('balance-chart-no-history')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('balance-goals')), findsNothing);
    await tester.pump(kBalanceMilestoneSettle);
    await tester.pump(const Duration(milliseconds: 100));
    expect(flags.claimed, isEmpty);
    await settle(tester);
  });

  testWidgets('another wallet screen never shows them', (tester) async {
    await pump(tester, input(),
        child: const HomeAnalyticsWidget(surface: 'wallet_detail'));
    expect(find.byKey(const ValueKey('balance-goals')), findsNothing);
    await settle(tester);
  });

  test('a Sal still per level name, then the last one for every level past it',
      () {
    expect([for (var i = 0; i < kBalanceLevelNames; i++) balanceLevelClip(i)],
        [for (var i = 1; i <= 12; i++) 'level_$i']);
    expect(balanceLevelClip(kBalanceLevelNames + 5), 'level_12');
    expect(balanceLevelClip(-1), 'level_1');
    final ladder = BalanceMilestoneLadder.forCurrency('USD');
    expect(balanceLevelClip(ladder.progress(50).nameIndex), 'level_1');
    expect(balanceLevelClip(ladder.progress(1e9).nameIndex), 'level_12');
  });

  test(
      'every Sal still the goals draw is in the manifest, one 64 cell, with '
      'both sheets bundled', () {
    final m = jsonDecode(File('lib/assets/sal/manifest.json')
        .readAsStringSync()) as Map<String, dynamic>;
    for (final clip in balanceGoalClips) {
      final entry = m[clip] as Map<String, dynamic>?;
      expect(entry, isNotNull, reason: clip);
      expect(entry!['frames'], 1, reason: clip);
      expect(entry['framing'], 'body', reason: clip);
      final files = entry['files'] as Map<String, dynamic>;
      expect(files.keys.toSet(), {'2x', '3x'}, reason: clip);
      for (final f in files.values) {
        final file = File('lib/assets/sal/${(f as Map)['file']}');
        expect(file.existsSync(), isTrue, reason: '$clip ${f['file']}');
        // Small: a still, never a sheet.
        expect(file.lengthSync(), lessThan(16 * 1024), reason: f['file']);
      }
    }
    for (var i = 1; i <= 12; i++) {
      expect((m['level_$i'] as Map)['group'], 'level');
      expect((m['level_$i'] as Map)['cell'], 64);
    }
    expect((m['goal_next'] as Map)['group'], 'goal');
  });

  group('the card hugs its chart, with the goals under it', () {
    double bottomGap(WidgetTester tester) =>
        tester.getBottomLeft(find.byKey(const ValueKey('balance-card'))).dy -
        tester.getBottomLeft(find.byType(KuteChartRangeRow)).dy;

    final pad = 16 * 393 / 430;

    testWidgets('16 under the range row, the goals and the nudge outside',
        (tester) async {
      await pump(tester, input());
      expect(bottomGap(tester), closeTo(pad, 0.5));
      expect(rectOf(tester, 'balance-goal-nudge').top,
          greaterThan(rectOf(tester, 'balance-card').bottom));
      await settle(tester);
    });

    testWidgets('the same when there is no nudge', (tester) async {
      await pump(tester, input(swap: false));
      expect(bottomGap(tester), closeTo(pad, 0.5));
      expect(find.byKey(const ValueKey('balance-goal-nudge')), findsNothing);
      await settle(tester);
    });
  });
}
