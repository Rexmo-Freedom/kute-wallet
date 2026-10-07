import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/advisor_model.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
import 'package:kute/screens/hyperliquid/components/hl_market_card.dart';
import 'package:kute/screens/polymarket/components/poly_crest_image.dart';
import 'package:kute/screens/search/components/advisor_answer_surface.dart';
import 'package:kute/screens/shared/investment_market_browser.dart';
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/services/advisor/advisor_service.dart'
    show AdvisorProgress;
import 'package:kute/screens/usd/flow/usd_flow_widgets.dart'
    show UsdReviewPlate;
import 'package:kute/theme/app_theme.dart';
// Production image caching uses this transitive plugin; widget tests register
// its channel factory against the local mock below, without native code.
// ignore: depend_on_referenced_packages
import 'package:sqflite/sqflite.dart';
import 'package:webview_flutter/webview_flutter.dart';

const _bitcoin = AdvisorBlock(
  id: 'hl-BTC',
  kind: AdvisorBlockKind.market,
  title: 'Bitcoin (BTC)',
  section: 'crypto_perps',
  markdown:
      'Crypto perpetual contract on Hyperliquid. Prices and funding can change.',
  card: AdvisorCard(
    venue: 'hyperliquid',
    id: 'BTC',
    instrument: 'crypto_perp',
    category: 'crypto',
    imageUrl: 'https://app.hyperliquid.xyz/coins/BTC.svg',
    asOf: '2026-09-15T09:16:00Z',
    perp: AdvisorCardPerp(
      markPx: 76950,
      prevDayPx: 75000,
      change24hPct: 2.6,
      fundingHourly: 0.0000125,
      fundingAnnualizedPct: 10.95,
      openInterestBase: 1000,
      openInterestUsd: 76950000,
      volume24hUsd: 9e9,
      maxLeverage: 40,
    ),
  ),
  actions: [
    AdvisorActionButton(
        label: 'View market',
        actionId: 'open_hl_market',
        params: {'coin': 'BTC', 'kind': 'perp'})
  ],
);

const _rules =
    'The GRAMMY Awards are presented annually by the Recording Academy. '
    'This market resolves to the listed song that wins Song of the Year. '
    'If a song is not officially nominated, its market resolves to No. '
    'The resolution source is the official awards broadcast and Grammy website.';
const _prediction = AdvisorBlock(
  id: 'pm-grammys-2027',
  kind: AdvisorBlockKind.market,
  title: 'Grammys 2027: Song of the Year Winner',
  section: 'predictions',
  markdown: 'Public Polymarket snapshot. Market prices reflect trading odds.',
  card: AdvisorCard(
    venue: 'polymarket',
    id: 'grammys-2027',
    slug: 'grammys-2027',
    instrument: 'prediction',
    imageUrl:
        'https://polymarket-upload.s3.us-east-2.amazonaws.com/grammys.svg',
    asOf: '2026-09-15T09:16:00Z',
    closesAt: '2027-02-07T23:59:00Z',
    outcomes: [
      AdvisorCardOutcome(
          id: '501', label: 'The Fate of Ophelia', price: .022, delta24h: -.01),
    ],
    resolutionRules: _rules,
  ),
  sources: [
    AdvisorSource(
        title: 'Polymarket resolution rules',
        url: 'https://polymarket.com/event/grammys-2027')
  ],
  actions: [
    AdvisorActionButton(
        label: 'View market',
        actionId: 'open_market_by_slug',
        params: {'slug': 'grammys-2027'})
  ],
);

// The Predictions list's event for [_prediction] (no token ids: no live
// price socket in a widget test).
const _grammysEvent = PolymarketEvent(
  id: 'grammys',
  slug: 'grammys-2027',
  title: 'Grammys 2027: Song of the Year Winner',
  volume: 1200000,
  liquidity: 100,
  category: 'culture',
  conditionId: 'grammys-condition',
  outcomes: [
    PolymarketOutcome(name: 'The Fate of Ophelia', price: .022),
    PolymarketOutcome(name: 'Abracadabra', price: .41),
  ],
);

final _btcMarket = HlMarket(
  coin: 'BTC',
  wireCoin: 'BTC',
  assetId: 0,
  kind: HlMarketKind.perp,
  szDecimals: 5,
  maxLeverage: 40,
  onlyIsolated: false,
  markPx: 76950,
  midPx: 76950,
  prevDayPx: 75000,
  dayNtlVlm: 9e9,
  category: 'crypto',
);

/// A conversation the test drives turn state by turn state.
class _Session extends AdvisorSessionNotifier {
  @override
  AdvisorSessionState build() => const AdvisorSessionState();
  void show(AdvisorTurn turn) => state = AdvisorSessionState(turns: [turn]);
}

class _Sports extends SportsLiveNotifier {
  @override
  Map<String, SportsMatchUpdate> build() => {};
  @override
  void connect() {}
}

/// What the venues answer: by default neither lists the market, so the card
/// falls back to the facts plate.
List<Override> _venues({
  Future<PolymarketEvent?> Function()? event,
  AsyncValue<List<HlMarket>> universe = const AsyncValue.data([]),
}) =>
    [
      sportsLiveProvider.overrideWith(_Sports.new),
      polymarketEventDetailsProvider
          .overrideWith((ref, slug) => event?.call() ?? Future.value(null)),
      hyperliquidBrowseUniverseProvider.overrideWith((_) => universe),
      hyperliquidPerpMarketsProvider.overrideWith((_) async => <HlMarket>[]),
      hyperliquidSpotMarketsProvider.overrideWith((_) async => <HlMarket>[]),
    ];

Future<void> _pump(WidgetTester tester, Widget child,
    {double width = 430,
    double scale = 1,
    bool dark = false,
    List<Override>? overrides}) async {
  tester.view.physicalSize = Size(width, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
      overrides: overrides ?? _venues(),
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (context, _) => MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(
              fontFamily: 'Inter',
              brightness: dark ? Brightness.dark : Brightness.light,
              extensions: [
                dark ? AppColorsExtension.dark() : AppColorsExtension.light()
              ]),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
              backgroundColor:
                  dark ? const Color(0xFF111113) : const Color(0xFFF8FAFC),
              body: SingleChildScrollView(
                  child: Padding(
                      padding: const EdgeInsets.all(16), child: child))),
        ),
      )));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory imageCache;
  setUpAll(() async {
    databaseFactory = databaseFactorySqflitePlugin;
    imageCache = Directory.systemTemp.createTempSync('kute-advisor-test-');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    // These cards intentionally use the production artwork widgets. Keep
    // their disk-cache plumbing local and deterministic in widget tests.
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => imageCache.path);
    messenger.setMockMethodCallHandler(
        const MethodChannel('com.tekartik.sqflite'), (call) async {
      switch (call.method) {
        case 'openDatabase':
          return {'id': 1};
        case 'query':
          final sql = (call.arguments as Map)['sql']?.toString() ?? '';
          return sql.contains('user_version')
              ? [
                  {'user_version': 3}
                ]
              : <Map<String, Object?>>[];
        case 'insert':
        case 'update':
          return 0;
        case 'databaseExists':
          return false;
        case 'getDatabasesPath':
          return imageCache.path;
        default:
          return null;
      }
    });
    // Finish cache initialization outside the widget fake clock so teardown
    // never races an in-flight platform-directory/database setup.
    await DefaultCacheManager().getFileFromCache('advisor-test-initialization');
    final loader = FontLoader('Inter')
      ..addFont(rootBundle.load('lib/assets/fonts/Inter-Regular.ttf'));
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  tearDownAll(() async {
    await DefaultCacheManager().dispose();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'), null);
    messenger.setMockMethodCallHandler(
        const MethodChannel('com.tekartik.sqflite'), null);
    if (imageCache.existsSync()) imageCache.deleteSync(recursive: true);
  });

  testWidgets('unlisted market falls back to a plate from the typed card',
      (tester) async {
    await _pump(
        tester, AdvisorBlockCard(block: _bitcoin, onAction: (_, __) {}));
    expect(find.text('Bitcoin (BTC)'), findsOneWidget);
    expect(find.text('\$76,950'), findsOneWidget);
    expect(find.text('+2.60%'), findsOneWidget);
    expect(find.text('Funding'), findsOneWidget);
    expect(find.text('+0.0013%'), findsOneWidget);
    expect(find.text('Open interest'), findsOneWidget);
    expect(find.text('\$77.0M'), findsOneWidget);
    expect(find.text('40×'), findsOneWidget);
    expect(find.text('As of 15 Sep 2026, 09:16 UTC'), findsOneWidget);
    expect(find.textContaining('Public Hyperliquid'), findsNothing);
    expect(find.byType(WebViewWidget), findsNothing);
    final icon = tester.widget<HlCoinIcon>(find.byType(HlCoinIcon));
    expect(icon.wireCoin, 'BTC');
    expect(icon.iconUrl, 'https://app.hyperliquid.xyz/coins/BTC.svg');
    expect(
        tester
            .getSize(
                find.byKey(const ValueKey('advisor-market-hyperliquid-BTC')))
            .height,
        lessThan(430));
    expect(tester.takeException(), isNull);
  });

  testWidgets('unlisted prediction plate: outcomes, day move, rules collapsed',
      (tester) async {
    await _pump(
        tester, AdvisorBlockCard(block: _prediction, onAction: (_, __) {}));
    expect(find.text('2027-02-07T23:59:00Z'), findsNothing);
    expect(find.text('7 Feb 2027, 23:59 UTC'), findsOneWidget);
    // The outcome by its own name, its chance and the day's move.
    expect(find.text('The Fate of Ophelia'), findsOneWidget);
    expect(find.text('2.2%  −1%', findRichText: true), findsOneWidget);
    expect(find.text('View market'), findsNothing);
    expect(find.text('Polymarket resolution rules'), findsNothing);
    expect(find.text(_rules), findsNothing);
    expect(tester.widget<PolyCrestImage>(find.byType(PolyCrestImage)).url,
        _prediction.card!.imageUrl);
    await tester.tap(find.text('Resolution rules'));
    await tester.pump();
    expect(find.text(_rules), findsOneWidget);
    expect(tester.getSize(find.text(_rules)).width, greaterThan(300));
    expect(tester.widget<Text>(find.text(_rules)).style?.fontWeight,
        FontWeight.w400);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a prediction block is the Predictions tab card, and the door',
      (tester) async {
    final opened = <(String, Map<String, dynamic>)>[];
    await _pump(
        tester,
        AdvisorBlockCard(
            block: _prediction,
            onAction: (id, params) => opened.add((id, params))),
        overrides: _venues(event: () async => _grammysEvent));
    expect(find.byType(PredictionBrowseCard), findsOneWidget);
    expect(
        tester
            .widget<PredictionBrowseCard>(find.byType(PredictionBrowseCard))
            .event
            .slug,
        'grammys-2027');
    expect(find.byType(UsdReviewPlate), findsNothing);
    expect(find.text('View market'), findsNothing);
    expect(find.text('Source'), findsNothing);
    expect(find.text('Polymarket resolution rules'), findsNothing);
    expect(find.text('Resolution rules'), findsNothing);
    await tester.tap(find.byType(PredictionBrowseCard));
    await tester.pump();
    expect(opened.single.$1, 'open_market_by_slug');
    expect(opened.single.$2, {'slug': 'grammys-2027'});
    expect(tester.takeException(), isNull);
  });

  testWidgets('a Hyperliquid block is the Investing tab card, and the door',
      (tester) async {
    final opened = <(String, Map<String, dynamic>)>[];
    await _pump(
        tester,
        AdvisorBlockCard(
            block: _bitcoin,
            onAction: (id, params) => opened.add((id, params))),
        overrides: _venues(universe: AsyncValue.data([_btcMarket])));
    expect(find.byType(HlMarketCard), findsOneWidget);
    expect(tester.widget<HlMarketCard>(find.byType(HlMarketCard)).market,
        same(_btcMarket));
    expect(find.byType(UsdReviewPlate), findsNothing);
    expect(find.text('View market'), findsNothing);
    await tester.tap(find.byType(HlMarketCard));
    await tester.pump();
    expect(opened.single.$1, 'open_hl_market');
    expect(opened.single.$2, {'coin': 'BTC', 'kind': 'perp'});
    expect(tester.takeException(), isNull);
  });

  testWidgets('a loading venue market holds its place with the card skeleton',
      (tester) async {
    final pending = Completer<PolymarketEvent?>();
    await _pump(
        tester,
        AdvisorBlocks(
            blocks: const [_bitcoin, _prediction], onAction: (_, __) {}),
        overrides: _venues(
            event: () => pending.future, universe: const AsyncValue.loading()));
    expect(find.byType(SkeletonCard), findsNWidgets(2));
    expect(find.byType(UsdReviewPlate), findsNothing);
    expect(find.byType(PredictionBrowseCard), findsNothing);
    pending.complete(_grammysEvent);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(PredictionBrowseCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a block without a verified open action keeps the plate',
      (tester) async {
    const block = AdvisorBlock(
      id: 'pm-grammys-2027',
      kind: AdvisorBlockKind.market,
      section: 'predictions',
      markdown: '',
      card: AdvisorCard(
          venue: 'polymarket',
          id: 'grammys-2027',
          slug: 'grammys-2027',
          outcomes: [
            AdvisorCardOutcome(id: 'Yes', label: 'Yes', price: .61),
            AdvisorCardOutcome(id: 'No', label: 'No', price: .39),
          ]),
    );
    await _pump(tester, AdvisorBlockCard(block: block, onAction: (_, __) {}),
        overrides: _venues(event: () async => _grammysEvent));
    expect(find.byType(PredictionBrowseCard), findsNothing);
    expect(find.text('Yes'), findsOneWidget);
    expect(find.text('61%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow large-text cards preserve readable labels and amounts',
      (tester) async {
    await _pump(
        tester, AdvisorBlockCard(block: _prediction, onAction: (_, __) {}),
        width: 320, scale: 1.6);
    await tester.tap(find.text('Resolution rules'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('2.2%  −1%', findRichText: true), findsOneWidget);
  });

  testWidgets('a live game plate reads the score and the clock',
      (tester) async {
    const block = AdvisorBlock(
      id: 'pm-ars-che',
      kind: AdvisorBlockKind.market,
      title: 'Arsenal vs Chelsea',
      section: 'predictions',
      markdown: '',
      card: AdvisorCard(
        venue: 'polymarket',
        id: 'ars-che',
        slug: 'ars-che',
        instrument: 'prediction',
        outcomes: [
          AdvisorCardOutcome(
              id: '1', label: 'Arsenal', price: .61, delta24h: .04),
        ],
        live: AdvisorCardLive(
            state: 'live',
            home: 'Arsenal',
            away: 'Chelsea',
            score: '1-0',
            period: '2H',
            elapsed: "46'"),
      ),
    );
    await _pump(tester, AdvisorBlockCard(block: block, onAction: (_, __) {}));
    expect(find.text('Live'), findsOneWidget);
    expect(find.text("Arsenal 1-0 Chelsea · 2H · 46'"), findsOneWidget);
    expect(find.text('61%  +4%', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('public activity is prose with its dates and sources, no plate',
      (tester) async {
    const block = AdvisorBlock(
      id: 'block-0',
      kind: AdvisorBlockKind.answer,
      title: 'Public filing',
      section: 'activity',
      markdown: 'A disclosed purchase.',
      transactionDate: '2026-08-01',
      disclosureDate: '2026-09-01',
      sources: [
        AdvisorSource(
            title: 'House disclosure',
            url: 'https://disclosures-clerk.house.gov/x')
      ],
    );
    await _pump(tester, AdvisorBlockCard(block: block, onAction: (_, __) {}));
    expect(find.byType(WebViewWidget), findsNothing);
    expect(find.byType(UsdReviewPlate), findsNothing);
    expect(find.text('Public filing'), findsOneWidget);
    expect(find.text('Transaction: 1 Aug 2026'), findsOneWidget);
    expect(find.text('House disclosure'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'the early card leads the answer, text streams under it, and the '
      'finished answer keeps that one card', (tester) async {
    final session = _Session();
    await _pump(
        tester, const SizedBox(height: 800, child: AdvisorAnswerSurface()),
        overrides: [
          ..._venues(universe: AsyncValue.data([_btcMarket])),
          advisorSessionProvider.overrideWith(() => session),
        ]);
    const q = 'Why is BTC moving?';
    session.show(const AdvisorTurn(
        query: q, loading: true, progress: AdvisorProgress.reading));
    await tester.pump();
    expect(find.byType(HlMarketCard), findsNothing);
    // The card event: the market shows before any text.
    session.show(const AdvisorTurn(
        query: q,
        loading: true,
        card: _bitcoin,
        progress: AdvisorProgress.connecting));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(HlMarketCard), findsOneWidget);
    final cardElement = tester.element(find.byType(HlMarketCard));
    final cardTop = tester.getTopLeft(find.byType(HlMarketCard)).dy;
    // Deltas stream under it.
    session.show(
        const AdvisorTurn(query: q, card: _bitcoin).append('Bitcoin is up '));
    await tester.pump();
    session.show(const AdvisorTurn(query: q, card: _bitcoin)
        .append('Bitcoin is up 2.6% today.'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Bitcoin is up', findRichText: true),
        findsOneWidget);
    expect(
        tester
            .getTopLeft(
                find.textContaining('Bitcoin is up', findRichText: true))
            .dy,
        greaterThan(cardTop));
    // Done repeats the card block (same id): it is drawn once, unchanged.
    session.show(const AdvisorTurn(query: q, card: _bitcoin).answered(const [
      AdvisorBlock(
          id: 'block-0',
          kind: AdvisorBlockKind.answer,
          markdown: 'Bitcoin is up 2.6% today on ETF inflows.'),
      _bitcoin,
    ]));
    await tester.pump();
    expect(find.byType(HlMarketCard), findsOneWidget);
    expect(tester.element(find.byType(HlMarketCard)), same(cardElement),
        reason: 'the card is not rebuilt from scratch when the answer lands');
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(HlMarketCard), findsOneWidget);
    expect(
        find.text('Bitcoin is up 2.6% today on ETF inflows.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets('card visual preview ${dark ? 'dark' : 'light'}',
        (tester) async {
      const key = ValueKey('preview');
      await _pump(
          tester,
          RepaintBoundary(
            key: key,
            child: ColoredBox(
              color: dark ? const Color(0xFF111113) : const Color(0xFFF8FAFC),
              child: Column(children: [
                AdvisorBlocks(
                    blocks: const [_bitcoin, _prediction],
                    onAction: (_, __) {}),
              ]),
            ),
          ),
          dark: dark);
      expect(tester.takeException(), isNull);
      final directory = Platform.environment['KUTE_UI_PREVIEW_DIR'];
      if (directory != null) {
        final boundary =
            tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File('$directory/advisor-${dark ? 'dark' : 'light'}.png')
              .writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }
}
