// A look by eye at the Bitcoin home on a desktop, separated like the
// Dollars home (bitcoin_home_panes.dart): a new wallet (one empty state
// under the pills) and a wallet with a balance history and a dozen
// transactions (the pills, then the activity or the goals, on the left;
// the hero on the right), at 1440x900, 1180x820, 1920x1080, 1000x700 and
// 430x932 (the phone, as before), light and dark; another wallet's tab
// (WalletBitcoinBody.wide); and the Dollars home beside them, whose panes
// the Bitcoin home's must match exactly (checked, not only rendered).
// Written only when asked:
//   DESK_HOME_RENDER=<dir> flutter test test/render/desk_home_render_test.dart

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:coingecko_api/data/market_chart_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:money2/money2.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/balance_history.dart';
import 'package:kute/models/balance_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/platform/kute_layout.dart';
import 'package:kute/providers/advisor_provider.dart' show aiEnabledProvider;
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/providers/analytics_provider.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/coingecko_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart'
    show CurrencyNotifier, currencyProvider, currentBtcUsdProvider;
import 'package:kute/providers/hyperliquid_account_provider.dart'
    show hyperliquidAddressProvider;
import 'package:kute/providers/hyperliquid_sats_pnl_provider.dart'
    show hyperliquidActivityFillsProvider;
import 'package:kute/providers/hyperliquid_watchlist_provider.dart';
import 'package:kute/providers/one_balance_provider.dart';
import 'package:kute/providers/polymarket_watchlist_provider.dart';
import 'package:kute/providers/refresh_everything_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/transactions_provider.dart'
    show walletTransactionCacheProvider;
import 'package:kute/providers/usd_account_provider.dart';
import 'package:kute/providers/usd_rewards_provider.dart';
import 'package:kute/screens/home/bitcoin_home_panes.dart';
import 'package:kute/screens/home/shell_wallet_screen.dart';
import 'package:kute/providers/active_shell_tab_provider.dart'
    show ActiveNavTab;
import 'package:kute/providers/shell_wallet_provider.dart'
    show shellWalletIdProvider;
import 'package:kute/screens/home/components/kute_top_nav_bar.dart';
import 'package:kute/platform/kute_wide_frames.dart' show KuteBarPane;
import 'package:kute/screens/shared/kute_pill_tabs.dart' show KutePillTabs;
import 'package:kute/screens/usd/usd_account_screen.dart' show UsdAccountScreen;
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../helpers/offline_venue_overrides.dart';
import '../helpers/portfolio_overrides.dart';
import '../helpers/shell_bar_harness.dart';
import '../screens/usd/investments_harness.dart'
    show
        InvestmentsTestPolicy,
        RecordingRefresh,
        RecordingRewardsApi,
        kEarnOff,
        kInvestmentsTestBalance;

final _dir = Platform.environment['DESK_HOME_RENDER'];

class _NoStars extends HlWatchlistNotifier {
  @override
  List<String> build() => const [];
}

class _NoPolyStars extends PolyWatchlistNotifier {
  @override
  List<String> build() => const [];
}

class _Currency extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _Currency() : super(CurrencyState({'USD': Fixed.fromInt(1)}));
  @override
  Future<void> updateRates() async {}
}

class _Balances extends WalletBalanceCacheNotifier {
  _Balances(Map<String, WalletBalance> values) {
    state = values;
  }
}

class _Market extends BitcoinMarketDataNotifier {
  _Market(this.data);
  final List<MarketChartData> data;
  @override
  Future<List<MarketChartData>> build() async => data;
}

SparkTransaction _spark(String id, int sats, DateTime at,
        {TransactionType direction = TransactionType.received,
        SparkTransactionType type = SparkTransactionType.spark}) =>
    SparkTransaction.fromCache(
      id: id,
      timestamp: at,
      isConfirmed: true,
      amountSats: sats,
      sparkType: type,
      direction: direction,
      pending: false,
    );

/// A dozen payments over two months, newest first, and the balance they
/// leave.
(Transaction, BalanceHistory, int) _history() {
  final now = DateTime.now();
  const rx = TransactionType.received;
  const tx = TransactionType.sent;
  const ln = SparkTransactionType.lightning;
  final rows = <(String, int, int, TransactionType, SparkTransactionType)>[
    ('a', 120000, 60 * 24 * 58, rx, ln),
    ('b', 21000, 60 * 24 * 51, tx, ln),
    ('c', 250000, 60 * 24 * 44, rx, SparkTransactionType.spark),
    ('d', 38000, 60 * 24 * 37, tx, ln),
    ('e', 90000, 60 * 24 * 30, rx, ln),
    ('f', 15500, 60 * 24 * 24, tx, SparkTransactionType.spark),
    ('g', 64000, 60 * 24 * 18, rx, ln),
    ('h', 9000, 60 * 24 * 12, tx, ln),
    ('i', 180000, 60 * 24 * 7, rx, SparkTransactionType.spark),
    ('j', 27000, 60 * 24 * 3, tx, ln),
    ('k', 48000, 60 * 26, rx, ln),
    ('l', 12000, 52, tx, ln),
  ];
  var balance = 0.0;
  final changes = <(DateTime, double)>[];
  for (final r in rows) {
    balance += r.$4 == rx ? r.$2 : -r.$2;
    changes.add((now.subtract(Duration(minutes: r.$3)), balance));
  }
  final txs = Transaction(
    bitcoinTransactions: const [],
    sparkTransactions: [
      for (final r in rows.reversed)
        _spark('tx_${r.$1}', r.$2, now.subtract(Duration(minutes: r.$3)),
            direction: r.$4, type: r.$5),
    ],
    sparkUnclaimedDeposits: const [],
  );
  return (
    txs,
    BalanceHistory(opening: 0, changes: changes, current: balance),
    balance.round(),
  );
}

Future<void> _assets(WidgetTester tester) => tester.runAsync(() async {
      for (final family in [GoogleFonts.inter().fontFamily!, 'Inter']) {
        final inter = FontLoader(family);
        for (final f in ['Regular', 'SemiBold', 'Bold']) {
          inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
        }
        await inter.load();
      }
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
      try {
        final manifest = jsonDecode(
                await rootBundle.loadString('$kSalSpriteDir/manifest.json'))
            as Map<String, dynamic>;
        SalSpriteCache.debugSetManifest(manifest);
        for (final clip in [kSalHeroLoop, 'body_sit_down', 'body_sit']) {
          await SalSpriteCache.clip(clip, 2);
        }
      } catch (e) {
        // Sal is decoration in a render; say why he is missing.
        debugPrint('desk home render: Sal not loaded: $e');
      }
    });

Future<void> _shoot(WidgetTester tester, String name) async {
  debugDisableShadows = false;
  for (final o in tester.allRenderObjects) {
    o.markNeedsPaint();
  }
  await tester.pump();
  await tester.runAsync(() async {
    final view = tester.binding.renderViews.first;
    final layer = view.debugLayer! as OffsetLayer;
    final image = await layer.toImage(Offset.zero & view.size, pixelRatio: 1);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_dir!).createSync(recursive: true);
    File('$_dir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    image.dispose();
  });
  debugDisableShadows = true;
  await tester.pump();
}

ThemeData _theme(bool dark) {
  final base = dark ? buildDarkTheme() : buildLightTheme();
  return base.copyWith(
    splashFactory: NoSplash.splashFactory,
    textTheme: base.textTheme.apply(fontFamily: 'Inter'),
  );
}

final _cold = WalletConfig(id: 'cold', name: 'Savings', isWatchOnly: true);

Future<void> _pump(WidgetTester tester, Size size, bool dark,
    {required bool withHistory,
    bool otherWallet = false,
    bool dollars = false}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final policy = InvestmentsTestPolicy(kEarnOff);
  RuntimeCapabilitiesService.debugInstance = policy;
  addTearDown(() => RuntimeCapabilitiesService.debugInstance = null);
  final (txs, steps, sats) = _history();
  final prices = [
    for (var ago = 90; ago >= 0; ago--)
      MarketChartData(DateTime.now().subtract(Duration(days: ago)),
          price: 100000, marketCap: 0, totalVolume: 0),
  ];
  final history = withHistory ? txs : null;
  final wallets = [
    // A wide wallet with history is backed up (the hero without its
    // banner, to line the balance up with the Dollars one); the phone
    // keeps the inputs of its before / after renders.
    WalletConfig(
        id: 'spending',
        name: 'Spending',
        backedUp: withHistory && size.width >= 900),
    if (otherWallet) _cold,
  ];
  await tester.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: [
      ...offlineVenueOverrides,
      ...portfolioOverrides(
          dollars: kInvestmentsTestBalance.dollarsUsd, history: history),
      hyperliquidActivityFillsProvider.overrideWith((_) => const []),
      walletBalanceCacheProvider.overrideWith((_) => _Balances({
            'spending': WalletBalance(
                onChainBtcBalance: 0,
                sparkBitcoinbalance: withHistory ? sats : 0),
            if (otherWallet)
              'cold': WalletBalance(
                  onChainBtcBalance: withHistory ? sats : 0,
                  sparkBitcoinbalance: 0),
          })),
      bitcoinMarketDataProvider.overrideWith(() => _Market(prices)),
      if (withHistory) bitcoinBalanceStepsProvider.overrideWith((_) => steps),
      currentBtcUsdProvider.overrideWithValue(100000),
      currencyProvider.overrideWith((_) => _Currency()),
      runtimeCapabilitiesProvider.overrideWithValue(policy),
      settingsProvider.overrideWith((_) => SettingsModel(Settings(
            currency: 'USD',
            language: 'en',
            btcFormat: 'sats',
            backup: false,
            biometricsEnabled: false,
            bitcoinElectrumNode: '',
            nodeType: 'Blockstream',
            reviewDone: true,
            activeWalletId: 'spending',
            wallets: wallets,
          ))),
      oneBalanceProvider.overrideWithValue(kInvestmentsTestBalance),
      usdBalanceProvider.overrideWithValue(kInvestmentsTestBalance.dollarsUsd),
      aiEnabledProvider.overrideWith((_) async => true),
      hyperliquidAddressProvider.overrideWith((_) async => null),
      usdRewardsApiProvider.overrideWithValue(RecordingRewardsApi()),
      hlWatchlistProvider.overrideWith(_NoStars.new),
      polyWatchlistProvider.overrideWith(_NoPolyStars.new),
      refreshEverythingProvider.overrideWith(RecordingRefresh.new),
      if (otherWallet) shellWalletIdProvider.overrideWith((_) => 'cold'),
    ],
    // The app's own ScreenUtil setup (app_widget.dart).
    child: ScreenUtilInit(
      designSize: KuteLayout.designSizeFor(size),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _theme(dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: shellBarBuilder,
        home: Builder(
          builder: (context) => Scaffold(
            backgroundColor: context.colors.background,
            // The shell's layering: the page, the top bar over it.
            body: Stack(children: [
              Positioned.fill(
                child: dollars
                    ? const UsdAccountScreen()
                    : otherWallet
                        ? ShellWalletScreen(wallet: _cold)
                        : const BitcoinHomePanes(),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: KuteTopNavBar(
                    activeTab: dollars ? ActiveNavTab.usd : ActiveNavTab.home),
              ),
            ]),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
  if (otherWallet && withHistory) {
    // The other wallet's own history, as its scan leaves it.
    ProviderScope.containerOf(tester.element(find.byType(MaterialApp)))
        .read(walletTransactionCacheProvider.notifier)
        .setForWallet('cold', txs);
    await tester.pump();
  }
}

Future<void> _settle(WidgetTester tester, [int frames = 20]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The left pane, its pill row and the right column (if any) on screen,
/// for the frame comparison between the two homes.
({Rect left, Rect pills, Rect? right})? _frame(WidgetTester tester) {
  final pane = find.byType(KuteBarPane);
  if (pane.evaluate().isEmpty) return null;
  final left = tester.getRect(pane.first);
  final pills = tester.getRect(find
      .descendant(of: pane.first, matching: find.byType(KutePillTabs))
      .first);
  final right = find.byWidgetPredicate((w) =>
      w.key == const ValueKey('investments-action-pane') ||
      w.key == const ValueKey('bitcoin-home-action-pane'));
  Rect? rightRect;
  for (final e in right.evaluate()) {
    final box = e.renderObject as RenderBox?;
    if (box != null && box.hasSize && box.size.width > 0) {
      rightRect = tester.getRect(find.byWidget(e.widget));
    }
  }
  return (left: left, pills: pills, right: rightRect);
}

final _frames = <String, ({Rect left, Rect pills, Rect? right})>{};

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  for (final (label, size) in [
    ('1440x900', const Size(1440, 900)),
    ('1180x820', const Size(1180, 820)),
    ('1920x1080', const Size(1920, 1080)),
    ('1000x700', const Size(1000, 700)),
    ('1280x800', const Size(1280, 800)),
    ('820x1180', const Size(820, 1180)),
    ('430x932', const Size(430, 932)),
  ]) {
    for (final dark in [false, true]) {
      final mode = dark ? 'dark' : 'light';
      for (final withHistory in [false, true]) {
        final state = withHistory ? 'history' : 'new';
        testWidgets('desk home $state $label $mode', skip: _dir == null,
            (tester) async {
          debugDisableShadows = true;
          addTearDown(() => debugDisableShadows = true);
          installShellBar();
          await _assets(tester);
          await _pump(tester, size, dark, withHistory: withHistory);
          await _settle(tester, 30);
          expect(tester.takeException(), isNull);
          await _shoot(tester, 'home_${state}_${label}_$mode');
          if (size.width >= 900) {
            final frame = _frame(tester)!;
            _frames['btc $label'] = frame;
          }
          if (withHistory && size.width >= 900) {
            // The left pane is the scroll.
            await tester.drag(
                find
                    .descendant(
                        of: find.byType(KuteBarPane),
                        matching: find.byType(Scrollable))
                    .first,
                const Offset(0, -500));
            await _settle(tester, 10);
            expect(tester.takeException(), isNull);
            await _shoot(tester, 'home_${state}_${label}_${mode}_scrolled');
          }
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 7));
        });
      }
      {
        testWidgets('desk dollars $label $mode', skip: _dir == null,
            (tester) async {
          debugDisableShadows = true;
          addTearDown(() => debugDisableShadows = true);
          installShellBar();
          await _assets(tester);
          await _pump(tester, size, dark, withHistory: false, dollars: true);
          await _settle(tester, 30);
          expect(tester.takeException(), isNull);
          await _shoot(tester, 'dollars_${label}_$mode');
          final usd = _frame(tester);
          final btc = _frames['btc $label'];
          // ignore: avoid_print
          print('frame $label dollars $usd bitcoin $btc');
          if (btc != null && usd != null) {
            // The two tabs' panes stand exactly in the same place.
            expect(btc.left.left, usd.left.left);
            expect(btc.left.top, usd.left.top);
            expect(btc.pills.topLeft, usd.pills.topLeft);
            expect(btc.pills.height, usd.pills.height);
          }
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 7));
        });
      }
      for (final withHistory in [false, true]) {
        final state = withHistory ? 'history' : 'new';
        testWidgets('desk wallet tab $state $label $mode', skip: _dir == null,
            (tester) async {
          debugDisableShadows = true;
          addTearDown(() => debugDisableShadows = true);
          installShellBar();
          await _assets(tester);
          await _pump(tester, size, dark,
              withHistory: withHistory, otherWallet: true);
          await _settle(tester, 30);
          expect(tester.takeException(), isNull);
          await _shoot(tester, 'wallet_${state}_${label}_$mode');
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 7));
        });
      }
    }
  }
}
