// A look by eye at the Bitcoin home's milestones (balance_goals.dart),
// written only when asked: FW27_GOALS_RENDER=<dir> flutter test
// test/render/balance_goals_render_test.dart. The real Inter face and the
// real Sal sheets, at 3x, light and dark, 375 wide (and 320, the narrowest
// phone, where the squares and the sheet are tightest): the Goals tab
// (the pill "Goals") with the card near a goal (the goal line just over
// the line, the gap a sliver) and the Next goal and Level squares with the
// nudge under it, far from one (the goal line always drawn, the gap
// squeezed to half the plot and tinted), a tiny balance under a far goal
// (the line still reads, centred in its half), a rung just passed (Sal and
// the line in the squares' place, the confetti mid-burst), the same under
// Reduce Motion, with balances hidden (no goal line), in German (the
// longest words); the whole ladder, the Goals squares at every level with
// Sal's still for each; and the ladder sheet at levels 1, 5 and 12 (the
// passed levels checked, the current one marked, "Share my level" as the bar,
// Done when hidden); with the real shell bar over them, the Goals tab reading
// "Share my level" and the Levels sheet at rest and scrolled to its end, the
// last row clear of the bar, on an iPhone's 393 x 852 with its home indicator
// and on the tightest phone.

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
import 'package:kute/screens/home/components/kute_shell_bar.dart'
    show KuteShellBar;
import 'package:kute/screens/share/cards/share_card_frame.dart'
    show ShareCardSal;
import 'package:kute/screens/shared/kute_bar_context.dart'
    show KuteBarRouteObserver, kuteShellMounted;
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
    // The bar's Sal, and the cards' stills for the preview.
    await SalSpriteCache.clip('idle', 3);
    await ShareCardSal.load();
    await ShareCardSal.loadStill(balanceLevelCardClip(1));
    for (final clip in balanceGoalClips) {
      await SalSpriteCache.clip(clip, 3);
    }
  });
}

ThemeData _theme(bool dark) {
  final base = dark ? buildDarkTheme() : buildLightTheme();
  return base.copyWith(textTheme: base.textTheme.apply(fontFamily: 'Inter'));
}

Widget _app(bool dark, Widget home, {Locale? locale, bool bar = false}) =>
    ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        navigatorObservers: bar ? [KuteBarRouteObserver()] : const [],
        builder: bar
            ? (context, child) =>
                Stack(children: [child!, const KuteShellBar()])
            : null,
        locale: locale,
        theme: _theme(dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    );

Future<ProviderContainer> _show(
  WidgetTester tester,
  GlobalKey key, {
  required bool dark,
  required int sats,
  double cash = 0,
  int privacy = 0,
  bool reduceMotion = false,
  _MapFlags? flags,
  Locale? locale,
  double width = 375,
  double height = 900,
  double inset = 0,
  bool bar = false,
}) async {
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3;
  tester.view.padding = FakeViewPadding(top: inset > 0 ? 59 * 3 : 20 * 3, bottom: inset * 3);
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
    child: _app(
      dark,
      locale: locale,
      bar: bar,
      Builder(
        builder: (context) => MediaQuery(
          data:
              MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
          child: Scaffold(
            body: RepaintBoundary(
              key: key,
              child: Builder(
                builder: (context) => ColoredBox(
                  color: context.colors.background,
                  child: const SingleChildScrollView(
                    child:
                        HomeAnalyticsWidget(surface: 'home', balanceGoals: true),
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

/// The ladder sheet as it opens over the Goals tab, at [width] wide.
Future<void> _showSheet(
  WidgetTester tester,
  GlobalKey key, {
  required bool dark,
  required double total,
  bool visible = true,
  double width = 375,
  Locale? locale,
}) async {
  tester.view.physicalSize = Size(width * 3, 860 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final ladder = BalanceMilestoneLadder.forCurrency('USD');
  await tester.pumpWidget(ProviderScope(
    child: _app(
      dark,
      locale: locale,
      Scaffold(
        body: RepaintBoundary(
          key: key,
          child: Builder(
            builder: (context) => ColoredBox(
              color: context.colors.background,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: BalanceLadderSheet(
                  progress: ladder.progress(total),
                  currency: 'USD',
                  visible: visible,
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

/// The whole view, the shell bar over the page too.
Future<void> _saveView(WidgetTester tester, String name) async {
  Directory(_dir!).createSync(recursive: true);
  await tester.runAsync(() async {
    final view = tester.binding.renderViews.first;
    final layer = view.debugLayer! as OffsetLayer;
    // The root layer already carries the device's 3x.
    final image =
        await layer.toImage(Offset.zero & tester.view.physicalSize);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_dir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Future<void> _away(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 3));
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

    // The bar over the tab and the sheet (goal_share.dart).
    for (final (name, width, height, inset, privacy, sats) in [
      ('393', 393.0, 852.0, 34.0, 0, 328686),
      ('375', 375.0, 812.0, 34.0, 0, 328686),
      ('320', 320.0, 568.0, 0.0, 0, 328686),
      ('hidden', 393.0, 852.0, 34.0, 1, 328686),
    ]) {
      testWidgets('the Goals tab and the Levels sheet under the bar $mode $name',
          (tester) async {
        KuteBarRouteObserver.reset();
        kuteShellMounted.value = true;
        addTearDown(() => kuteShellMounted.value = false);
        await _assets(tester);
        final key = GlobalKey();
        await _show(tester, key,
            dark: dark,
            sats: sats,
            privacy: privacy,
            width: width,
            height: height,
            inset: inset,
            bar: true);
        await _saveView(tester, 'bar_goals_${mode}_$name');
        if (privacy == 0) {
          // The bar opens the card's preview.
          await tester.tap(find.byKey(const ValueKey('kute-bar-primary-button')));
          for (var i = 0; i < 10; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          await _saveView(tester, 'bar_preview_${mode}_$name');
          Navigator.of(tester.element(find.byKey(const ValueKey('share-card-preview'))))
              .pop();
          for (var i = 0; i < 10; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
        }
        await tester.tap(find.byKey(const ValueKey('balance-goal-ladder')));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await _saveView(tester, 'bar_ladder_rest_${mode}_$name');
        final sheet = find.byKey(const ValueKey('balance-ladder-sheet'));
        final position = tester
            .state<ScrollableState>(find
                .descendant(of: sheet, matching: find.byType(Scrollable))
                .first)
            .position;
        position.jumpTo(position.maxScrollExtent);
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await _saveView(tester, 'bar_ladder_end_${mode}_$name');
        await _away(tester);
      });
    }

    for (final width in [375.0, 320.0]) {
      final w = width.round();
      testWidgets('near the goal $mode $w', (tester) async {
        await _assets(tester);
        final key = GlobalKey();
        // ₿328,686 at $75,700 is $248.82 (the founder's screenshot).
        await _show(tester, key, dark: dark, sats: 328686, width: width);
        await _save(tester, key, 'goals_near_${mode}_$w');
        await _away(tester);
      });

      testWidgets('far from the goal, with Dollars $mode $w', (tester) async {
        await _assets(tester);
        final key = GlobalKey();
        // $181.68 of bitcoin and $120: $301.68, the goal $500.
        await _show(tester, key,
            dark: dark, sats: 240000, cash: 120, width: width);
        await _save(tester, key, 'goals_far_${mode}_$w');
        await _away(tester);
      });
    }

    testWidgets('a tiny balance under a far goal $mode', (tester) async {
      await _assets(tester);
      final key = GlobalKey();
      // ₿7,000 is $5.30; the goal $100.
      await _show(tester, key, dark: dark, sats: 7000);
      await _save(tester, key, 'goals_tiny_$mode');
      await _away(tester);
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
        await _away(tester);
      });
    }

    testWidgets('in German $mode', (tester) async {
      await _assets(tester);
      final key = GlobalKey();
      await _show(tester, key,
          dark: dark, sats: 240000, cash: 120, locale: const Locale('de'));
      await _save(tester, key, 'goals_de_$mode');
      await _away(tester);
    });

    testWidgets('the ladder $mode', (tester) async {
      await _assets(tester);
      tester.view.physicalSize = const Size(375 * 3, 3300 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      final ladder = BalanceMilestoneLadder.forCurrency('USD');
      await tester.pumpWidget(_app(
        dark,
        Scaffold(
          body: RepaintBoundary(
            key: key,
            child: Builder(
              builder: (context) => ColoredBox(
                color: context.colors.background,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < 12; i++)
                        BalanceGoalsSection(
                          // Two thirds of the way from one rung to the
                          // next: level i + 1.
                          progress: ladder.progress(i == 0
                              ? 60
                              : ladder.rung(i - 1) +
                                  (ladder.rung(i) - ladder.rung(i - 1)) *
                                      0.66),
                          currency: 'USD',
                          visible: true,
                        ),
                    ],
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
      await _save(tester, key, 'goals_ladder_$mode');
      await _away(tester);
    });

    testWidgets('balances hidden $mode', (tester) async {
      await _assets(tester);
      final key = GlobalKey();
      await _show(tester, key, dark: dark, sats: 328686, privacy: 1);
      await _save(tester, key, 'goals_hidden_$mode');
      await _away(tester);
    });

    // The ladder sheet at levels 1, 5 and 12, at both widths.
    for (final (level, total) in [(1, 60.0), (5, 1660.0), (12, 250000.0)]) {
      for (final width in [375.0, 320.0]) {
        final w = width.round();
        testWidgets('the ladder sheet at level $level $mode $w',
            (tester) async {
          await _assets(tester);
          final key = GlobalKey();
          await _showSheet(tester, key,
              dark: dark, total: total, width: width);
          await _save(tester, key, 'ladder_sheet_l${level}_${mode}_$w');
          await _away(tester);
        });
      }
    }

    testWidgets('the ladder sheet in German, and hidden $mode',
        (tester) async {
      await _assets(tester);
      final key = GlobalKey();
      await _showSheet(tester, key,
          dark: dark, total: 1660, locale: const Locale('de'));
      await _save(tester, key, 'ladder_sheet_de_$mode');
      await _away(tester);
      await _assets(tester);
      final hidden = GlobalKey();
      await _showSheet(tester, hidden, dark: dark, total: 1660, visible: false);
      await _save(tester, hidden, 'ladder_sheet_hidden_$mode');
      await _away(tester);
    });
  }
}
