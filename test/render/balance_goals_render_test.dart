// A look by eye at the Bitcoin home's milestones (balance_goals.dart),
// written only when asked: FW27_GOALS_RENDER=<dir> flutter test
// test/render/balance_goals_render_test.dart. The real Inter face and the
// real Sal sheets, 390 wide at 3x, light and dark: the Balance card near a
// goal (the goal line drawn), far from one (no line), a rung just passed
// (Sal, the line and the confetti mid-burst), the same under Reduce
// Motion, and with balances hidden.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:coingecko_api/data/market_chart_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/services/balance_milestones.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart';

final _dir = Platform.environment['FW27_GOALS_RENDER'];
const _price = 75700.0;

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

final _input = StateProvider<BalanceGoalInput?>((_) => null);

BalanceGoalInput _goal(int sats, {double cash = 0}) => BalanceGoalInput(
      ready: true,
      currency: 'USD',
      bitcoinSats: sats,
      fiatPerBtc: _price,
      usdToDisplay: 1,
      cashUsd: cash,
      canMoveToDollars: true,
      investing: true,
      predictions: true,
    );

/// A month of a balance that climbed to [sats].
BalanceHistory _history(int sats) {
  final now = DateTime.now();
  return BalanceHistory(
    opening: 0,
    changes: [
      (now.subtract(const Duration(days: 70)), sats * 0.42),
      (now.subtract(const Duration(days: 26)), sats * 0.58),
      (now.subtract(const Duration(days: 19)), sats * 0.55),
      (now.subtract(const Duration(days: 12)), sats * 0.81),
      (now.subtract(const Duration(days: 6)), sats * 0.76),
      (now.subtract(const Duration(days: 2)), sats.toDouble()),
    ],
    current: sats.toDouble(),
  );
}

Future<void> _assets(WidgetTester tester) async {
  await tester.runAsync(() async {
    final inter = FontLoader('Inter')
      ..addFont(rootBundle.load('lib/assets/fonts/Inter-Regular.ttf'))
      ..addFont(rootBundle.load('lib/assets/fonts/Inter-SemiBold.ttf'))
      ..addFont(rootBundle.load('lib/assets/fonts/Inter-Bold.ttf'));
    await inter.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final manifest =
        jsonDecode(await rootBundle.loadString('$kSalSpriteDir/manifest.json'))
            as Map<String, dynamic>;
    SalSpriteCache.debugSetManifest(manifest);
    await SalSpriteCache.clip('body_cheer', 3);
  });
}

ThemeData _theme(bool dark) {
  final base = dark ? buildDarkTheme() : buildLightTheme();
  return base.copyWith(textTheme: base.textTheme.apply(fontFamily: 'Inter'));
}

Future<ProviderContainer> _show(
  WidgetTester tester,
  GlobalKey key, {
  required bool dark,
  required int sats,
  double cash = 0,
  int privacy = 0,
  bool reduceMotion = false,
  _MapFlags? flags,
}) async {
  tester.view.physicalSize = const Size(390 * 3, 700 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final prices = [
    for (var ago = 90; ago >= 0; ago--)
      MarketChartData(DateTime.now().subtract(Duration(days: ago)),
          price: _price, marketCap: 0, totalVolume: 0),
  ];
  final container = ProviderContainer(overrides: [
    settingsProvider.overrideWith((_) => SettingsModel(Settings(
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
        ))),
    bitcoinMarketDataProvider.overrideWith(() => _Market(prices)),
    bitcoinBalanceStepsProvider.overrideWith((_) => _history(sats)),
    bitcoinBalanceInFormatByDayProvider.overrideWith((_) => {}),
    viewedWalletBalanceProvider.overrideWithValue(
        WalletBalance(onChainBtcBalance: 0, sparkBitcoinbalance: sats)),
    polymarketBalanceProvider.overrideWith((_) => 0),
    selectedCurrencyProvider.overrideWith(
        (ref, code) => Money.fromNumWithCurrency(_price, AppCurrencies.usd)),
    selectedCurrencyProviderFromUSD.overrideWith(
        (ref, code) => Money.fromNumWithCurrency(1, AppCurrencies.usd)),
    viewedWalletProvider.overrideWithValue(null),
    viewedWalletTransactionsProvider.overrideWithValue(Transaction.empty()),
    balanceGoalInputProvider.overrideWith((ref) => ref.watch(_input)),
    balanceMilestoneFlagsProvider.overrideWithValue(flags ?? _MapFlags()),
  ]);
  addTearDown(container.dispose);
  container.read(_input.notifier).state = _goal(sats, cash: cash);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _theme(dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(disableAnimations: reduceMotion),
            child: Scaffold(
              body: RepaintBoundary(
                key: key,
                child: Builder(
                  builder: (context) => ColoredBox(
                    color: context.colors.background,
                    child: const SingleChildScrollView(
                      child: HomeAnalyticsWidget(
                          surface: 'home', balanceGoals: true),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return container;
}

Future<void> _save(WidgetTester tester, GlobalKey key, String name) async {
  Directory(_dir!).createSync(recursive: true);
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_dir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  final dir = _dir;
  if (dir == null || dir.isEmpty) {
    test('balance goals render', () {},
        skip: 'on demand: FW27_GOALS_RENDER=<dir>');
    return;
  }

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';

    testWidgets('near the goal $mode', (tester) async {
      await _assets(tester);
      final key = GlobalKey();
      // ₿328,686 at $75,700 is $248.82 (the founder's screenshot).
      await _show(tester, key, dark: dark, sats: 328686);
      await _save(tester, key, 'goals_near_$mode');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('far from the goal, with Dollars $mode', (tester) async {
      await _assets(tester);
      final key = GlobalKey();
      await _show(tester, key, dark: dark, sats: 240000, cash: 120);
      await _save(tester, key, 'goals_far_$mode');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    });

    for (final reduce in [false, true]) {
      final tag = reduce ? '_reduce' : '';
      testWidgets('a rung passed $mode$tag', (tester) async {
        await _assets(tester);
        final key = GlobalKey();
        final flags = _MapFlags();
        final c = await _show(tester, key,
            dark: dark, sats: 328686, flags: flags, reduceMotion: reduce);
        await tester.pump(kBalanceMilestoneSettle);
        await tester.pump(const Duration(milliseconds: 100));
        c.read(_input.notifier).state = _goal(334000);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(kBalanceMilestoneSettle);
        // Mid-burst.
        await tester.pump(const Duration(milliseconds: 380));
        await _save(tester, key, 'goals_passed_$mode$tag');
        await tester.pump(const Duration(milliseconds: 700));
        await _save(tester, key, 'goals_passed_late_$mode$tag');
        await tester.pump(kBalanceMilestoneCelebration);
        await tester.pump(const Duration(milliseconds: 500));
        await _save(tester, key, 'goals_after_$mode$tag');
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 3));
      });
    }

    testWidgets('balances hidden $mode', (tester) async {
      await _assets(tester);
      final key = GlobalKey();
      await _show(tester, key, dark: dark, sats: 328686, privacy: 1);
      await _save(tester, key, 'goals_hidden_$mode');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    });
  }
}
