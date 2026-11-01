// On demand: renders the curated surfaces (founder, 1 November 2026) into
// PNGs for a look by eye: the Bitcoin home's Activity with its Today card
// (light and dark), the Investing browse (Trending: the strip, six rows,
// nothing after) and the Predictions browse (the compact BTC card, the
// strip, six markets).
//
//   flutter test test/screens/home/r4_curate_render_test.dart \
//     --dart-define=R4_CURATE_RENDER_OUT=<dir>
//
// Without the define the file does nothing.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as breez;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/helpers/swap_activity.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/models/portfolio_performance.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/currency_conversions_provider.dart'
    show currentBtcUsdProvider;
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_sats_pnl_provider.dart'
    show hyperliquidActivityFillsProvider;
import 'package:kute/providers/hyperliquid_sparkline_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_provider.dart';
import 'package:kute/providers/portfolio_performance_provider.dart'
    show portfolioPerformanceDisplayProvider;
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/hyperliquid/hyperliquid_screen.dart';
import 'package:kute/screens/polymarket/polymarket_screen.dart';
import 'package:kute/screens/shared/all_activity.dart';
import 'package:kute/screens/shared/transactions_builder.dart'
    show ActivityRowStyle;
import 'package:kute/services/hyperliquid/hl_sparkline_cache.dart';
import 'package:kute/services/orchestra/own_spark_arrivals.dart';
import 'package:kute/services/orchestra_routes.dart'
    show kOrchestraUsdAssetCode;
import 'package:kute/services/polymarket/crypto_window_results.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/offline_venue_overrides.dart';
import '../../helpers/portfolio_overrides.dart';
import '../hyperliquid/hl_trending_strip_fixture.dart';
import '../usd/investments_harness.dart';

const _out = String.fromEnvironment('R4_CURATE_RENDER_OUT');
final _shotKey = GlobalKey();

Future<void> _shot(WidgetTester tester, String name) async {
  for (Object? e = tester.takeException();
      e != null;
      e = tester.takeException()) {
    final text = '$e'.split('\n').first;
    if (!text.contains('MissingPlugin') && !text.contains('HTTP')) {
      // ignore: avoid_print
      print('RENDER problem: $text');
    }
  }
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_shotKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_out/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  });
  // ignore: avoid_print
  print('RENDER wrote $_out/$name.png');
}

// ── Home Activity ──────────────────────────────────────────────────────

const _kinds = {
  'btc_to_usd': SwapActivityKind.dollarDeposit,
  'usd_to_pm': SwapActivityKind.predictionsDeposit,
  'btc_to_hl': SwapActivityKind.investingDeposit,
  'manual_usd': SwapActivityKind.dollarDeposit,
};

SwapOrderTransaction _swap(String id,
        {required String coinFrom,
        required String networkFrom,
        required String coinTo,
        required String networkTo,
        required DateTime at,
        String depositAmount = '10',
        String withdrawalAmount = '10'}) =>
    SwapOrderTransaction(
      id: id,
      timestamp: at,
      isConfirmed: true,
      details: SwapOrder(
        id: id,
        coinFrom: coinFrom,
        networkFrom: networkFrom,
        coinTo: coinTo,
        networkTo: networkTo,
        depositAddress: 'deposit-$id',
        depositAmount: depositAmount,
        withdrawalAmount: withdrawalAmount,
        status: 'success',
        timestamp: at.millisecondsSinceEpoch,
        withdrawalAddress: networkTo == 'SPARK' ? 'sp1self' : '0xvenue',
        depositMin: '0',
        depositMax: '0',
        rate: '0',
        refundAddress: '',
        provider: 'Orchestra',
        walletId: 'spending',
      ),
    );

SparkTransaction _spark(String id, int sats, DateTime at,
        {TransactionType direction = TransactionType.received}) =>
    SparkTransaction.fromCache(
      id: id,
      timestamp: at,
      isConfirmed: true,
      amountSats: sats,
      sparkType: SparkTransactionType.spark,
      direction: direction,
      pending: false,
    );

UsdbTokenTransaction _dollars(String id, double usd, DateTime at) =>
    UsdbTokenTransaction(
      id: id,
      timestamp: at,
      isConfirmed: true,
      details: breez.Payment(
        id: id,
        paymentType: breez.PaymentType.send,
        status: breez.PaymentStatus.completed,
        amount: BigInt.from((usd * 1e6).round()),
        fees: BigInt.zero,
        timestamp: BigInt.from(at.millisecondsSinceEpoch ~/ 1000),
        method: breez.PaymentMethod.token,
        details: breez.PaymentDetails.token(
          metadata: breez.TokenMetadata(
            identifier: 'btkn1usdb',
            issuerPublicKey: 'issuer',
            name: 'USDB',
            ticker: 'USDB',
            decimals: 6,
            maxSupply: BigInt.zero,
            isFreezable: false,
          ),
          txHash: 'tx-$id',
          txType: breez.TokenTransactionType.transfer,
        ),
      ),
    );

PolymarketTransaction _bet(String id, DateTime at) => PolymarketTransaction(
      id: id,
      timestamp: at,
      activity: Activity(
        proxyWallet: '0xself',
        timestamp: at.millisecondsSinceEpoch ~/ 1000,
        conditionId: '0xfed',
        type: 'TRADE',
        size: 7.3,
        usdcSize: 4.24,
        transactionHash: '0x$id',
        side: 'BUY',
        asset: 'no',
        outcomeIndex: 1,
        title: 'Fed cuts rates in December?',
        outcome: 'No',
        eventSlug: '',
      ),
    );

HlFill _fill(DateTime at, {required int oid, required String dir,
        double closedPnl = 0}) =>
    HlFill(
      coin: 'NVDA',
      px: 182.4,
      sz: 0.12,
      side: dir.contains('Close') ? 'A' : 'B',
      time: at.millisecondsSinceEpoch,
      closedPnl: closedPnl,
      fee: 0.02,
      feeToken: 'USDC',
      oid: oid,
      hash: '0xfill$oid',
      dir: dir,
      cloid: null,
    );

Future<void> _renderHome(WidgetTester tester, {required bool dark}) async {
  final now = DateTime.now();
  DateTime ago(int minutes) => now.subtract(Duration(minutes: minutes));
  final yesterday = now.subtract(const Duration(days: 1));
  final history = Transaction(
    bitcoinTransactions: const [],
    sparkTransactions: [
      _spark('rx_friend', 48000, ago(52)),
      _spark('link_sent', 12000, ago(40),
          direction: TransactionType.sent),
      _spark('rx_old', 150000, yesterday),
    ],
    sparkUnclaimedDeposits: const [],
    usdbTokenTransactions: [_dollars('usd_send', 25, yesterday)],
    swapOrderTransactions: [
      _swap('btc_to_usd',
          coinFrom: 'BTC',
          networkFrom: 'SPARK',
          coinTo: kOrchestraUsdAssetCode,
          networkTo: 'SPARK',
          depositAmount: '0.00004',
          withdrawalAmount: '4.40',
          at: ago(20)),
      _swap('usd_to_pm',
          coinFrom: kOrchestraUsdAssetCode,
          networkFrom: 'SPARK',
          coinTo: 'USDC.E',
          networkTo: 'POLYGON',
          depositAmount: '4.40',
          withdrawalAmount: '4.30',
          at: ago(18)),
      _swap('btc_to_hl',
          coinFrom: 'BTC',
          networkFrom: 'SPARK',
          coinTo: 'USDC',
          networkTo: 'HYPERCORE',
          depositAmount: '0.0002',
          at: ago(12)),
      _swap('manual_usd',
          coinFrom: 'BTC',
          networkFrom: 'SPARK',
          coinTo: kOrchestraUsdAssetCode,
          networkTo: 'SPARK',
          withdrawalAmount: '60.00',
          at: yesterday.subtract(const Duration(hours: 2))),
    ],
    polymarketTransactions: [_bet('bet', ago(15))],
  );
  final fills = [
    _fill(ago(8), oid: 1, dir: 'Open Long'),
    _fill(ago(3), oid: 2, dir: 'Close Long', closedPnl: 1.18),
  ];
  final midnight = DateTime(now.year, now.month, now.day);
  final perf = PortfolioPerformance(points: [
    PortfolioPnlPoint(
        timestamp: midnight.subtract(const Duration(hours: 1)), pnlUsd: 10),
    PortfolioPnlPoint(timestamp: now, pnlUsd: 13.42),
  ], sourceLabel: '', basisLabel: 'P&L', coverageLabel: '');

  debugAllActivityClassify = (o) => _kinds[o.id] ?? classifySwapActivity(o);
  addTearDown(() => debugAllActivityClassify = null);
  const size = Size(430, 900);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: [
      ...portfolioOverrides(history: history),
      ...offlineVenueOverrides,
      hyperliquidActivityFillsProvider.overrideWith((_) => fills),
      currentBtcUsdProvider.overrideWithValue(100000),
      portfolioPerformanceDisplayProvider(const PortfolioPerformanceRequest(
              venue: PortfolioPerformanceVenue.trading))
          .overrideWithValue(AsyncData(perf)),
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
          wallets: [WalletConfig(id: 'spending', name: 'Spending')]))),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          fontFamily: 'Inter',
          brightness: dark ? Brightness.dark : Brightness.light,
          extensions: [
            dark ? AppColorsExtension.dark() : AppColorsExtension.light()
          ],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RepaintBoundary(
          key: _shotKey,
          child: Builder(
            builder: (context) => Scaffold(
              backgroundColor: context.colors.background,
              body: const SingleChildScrollView(
                padding: EdgeInsets.only(top: 12, bottom: 24),
                child: ActivityRowStyle(
                    compact: true, child: AllActivityPreview()),
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
  await _shot(tester, 'home_activity_${dark ? 'dark' : 'light'}');
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 7));
}

// ── Browse lists ───────────────────────────────────────────────────────

class _LivePrices extends HlLivePricesNotifier {
  @override
  HlLivePriceState build() => const HlLivePriceState();
  @override
  void watchCoins(List<String> coins, {Map<String, String>? wire}) {}
  @override
  void focus(String coin, {String? wire}) {}
  @override
  void unfocus(String coin) {}
  @override
  void acquire() {}
  @override
  void release() {}
}

final _sparks = HlSparklineStore(fetch: (wire) async {
  final seed = wire.codeUnits.fold<int>(0, (a, b) => a * 31 + b);
  return [
    for (var i = 0; i < 7; i++) 100 + ((seed >> (i * 3)) % 9) - 4.0 + i * 0.6,
  ];
});

final _start = DateTime.now().toUtc().subtract(const Duration(minutes: 2));

class _Round extends CryptoPredictNotifier {
  @override
  Future<CryptoPredictState> build(String arg) async => CryptoPredictState(
        asset: arg,
        currentPrice: 77812.4,
        priceToBeat: 77775,
        secondsRemaining: 154,
        priceHistory: [
          for (var i = 0; i < 40; i++)
            BtcPriceSnapshot(
                timestamp: _start.add(Duration(seconds: i * 3)),
                price: 77775 + ((i * 7) % 11) * 4.0 - 18 + i * 1.2),
        ],
        event: Btc5MinEvent(
          slug: 'btc-updown-5m-${_start.millisecondsSinceEpoch ~/ 1000}',
          title: 'Bitcoin Up or Down',
          windowStartTime: _start,
          endDate: _start.add(const Duration(minutes: 5)),
          upPrice: 0.62,
          downPrice: 0.38,
          upTokenId: 'up',
          downTokenId: 'down',
        ),
      );
}

class _Feed extends PolyFeedNotifier {
  @override
  PolyFeedState build(PolyFeedQuery arg) {
    PolymarketEvent yesNo(String id, String title, double yes,
            {double volume = 1e6}) =>
        PolymarketEvent(
          id: id,
          slug: id,
          title: title,
          volume: volume,
          liquidity: 1e5,
          category: 'politics',
          conditionId: id,
          outcomes: [
            PolymarketOutcome(name: 'Yes', price: yes),
            PolymarketOutcome(name: 'No', price: 1 - yes),
          ],
        );
    const titles = [
      ('Fed cuts rates in December?', 0.71),
      ('Bitcoin above \$120k on Friday?', 0.38),
      ('Will it snow in London on Christmas?', 0.12),
      ('Apple announces a foldable iPhone?', 0.27),
      ('Ethereum ETF inflows top \$1B this week?', 0.55),
      ('Will the Lakers win tonight?', 0.46),
      ('New Zelda game released in 2026?', 0.18),
      ('Recession declared in 2026?', 0.22),
      ('Tesla delivers 500k cars in Q4?', 0.61),
      ('SpaceX Starship reaches orbit again?', 0.83),
    ];
    return PolyFeedState(done: true, events: [
      for (var i = 0; i < 5; i++)
        yesNo('top$i', [
          'Who wins the 2026 World Cup final?',
          'Fed decision in December',
          'Bitcoin price on December 31',
          'Super Bowl LX winner',
          'Time Person of the Year 2026',
        ][i], 0.4 + i * 0.07, volume: 9e7 - i),
      for (var i = 0; i < titles.length; i++)
        yesNo('m$i', titles[i].$1, titles[i].$2, volume: 1e6 - i),
    ]);
  }
}

Future<void> _renderBrowse(WidgetTester tester,
    {required Widget screen,
    required String name,
    required List<Override> overrides}) async {
  await pumpInvestments(tester,
      browseInvesting: true,
      browsePredictions: true,
      size: const Size(430, 2300),
      child: RepaintBoundary(key: _shotKey, child: Scaffold(body: screen)),
      overrides: overrides);
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await _shot(tester, name);
  await unmountInvestments(tester);
  await tester.pump(const Duration(seconds: 31));
}

void main() {
  if (_out.isEmpty) {
    test('r4 curate render', () {},
        skip: 'on demand: --dart-define=R4_CURATE_RENDER_OUT=<dir>');
    return;
  }

  late Directory hiveDir;
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    Directory(_out).createSync(recursive: true);
    hiveDir = await Directory.systemTemp.createTemp('r4_curate_render');
    Hive.init(hiveDir.path);
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final family in [GoogleFonts.inter().fontFamily!, 'Inter']) {
      final inter = FontLoader(family);
      for (final f in ['Regular', 'SemiBold', 'Bold']) {
        inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
      }
      await inter.load();
    }
    final root = Platform.environment['FLUTTER_ROOT'];
    final icons = File(
        '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (root != null && icons.existsSync()) {
      final bytes = icons.readAsBytesSync();
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(ByteData.sublistView(bytes))))
          .load();
    }
  });
  tearDownAll(() async {
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });
  setUp(OwnSparkArrivals.reset);

  for (final dark in [false, true]) {
    testWidgets('home activity ${dark ? 'dark' : 'light'}', (tester) async {
      await _renderHome(tester, dark: dark);
    });
  }

  testWidgets('investing browse', (tester) async {
    await _renderBrowse(tester,
        name: 'investing_browse_light',
        screen: const HyperliquidScreen(embedded: true),
        overrides: [
          hyperliquidBrowseUniverseProvider
              .overrideWithValue(AsyncValue.data(hlTrendingFixture)),
          hyperliquidBuilderMarketsMissingProvider.overrideWithValue(false),
          hyperliquidLivePricesProvider.overrideWith(_LivePrices.new),
          hyperliquidSparklineStoreProvider.overrideWithValue(_sparks),
        ]);
  });

  testWidgets('predictions browse', (tester) async {
    await _renderBrowse(tester,
        name: 'predictions_browse_light',
        screen: const PolymarketScreen(embedded: true),
        overrides: [
          ...offlineVenueOverrides,
          polyBrowseFeedProvider.overrideWith(_Feed.new),
          cryptoPredictProvider.overrideWith(_Round.new),
          cryptoRecentResultsProvider.overrideWith((ref, key) async => const [
                CryptoWindowResult(1, true),
                CryptoWindowResult(2, false),
                CryptoWindowResult(3, true),
                CryptoWindowResult(4, true),
                CryptoWindowResult(5, null),
              ]),
        ]);
  });
}
