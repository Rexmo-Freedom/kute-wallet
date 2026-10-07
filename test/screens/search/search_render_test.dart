// On demand: renders the venue search sheet with results, on the
// Predictions and Investing tabs, in English and Portuguese, light and
// dark, with the app's Inter face, into PNGs for a look by eye.
//
//   flutter test test/screens/search/search_render_test.dart \
//     --dart-define=SEARCH_RENDER_OUT=/tmp/kute_search
//
// Market images are not fetched here: every crest falls back to its mark.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_search_provider.dart';
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/trade_notifications_provider.dart';
import 'package:kute/providers/unified_search_provider.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/screens/search/unified_search_screen.dart';
import 'package:kute/services/advisor/advisor_input_guard.dart';
import 'package:kute/services/trade_notification_store.dart'
    show TradeNotification;
import 'package:kute/theme/app_theme.dart';

const _out = String.fromEnvironment('SEARCH_RENDER_OUT');
final _shotKey = GlobalKey();

class _Sports extends SportsLiveNotifier {
  @override
  Map<String, SportsMatchUpdate> build() => {};
  @override
  void connect() {}
}

final _now = DateTime.now();

PolymarketEvent _event(
  String title, {
  required List<PolymarketOutcome> outcomes,
  List<String> tags = const [],
  String category = 'other',
  DateTime? endDate,
  double volume = 1200000,
}) =>
    PolymarketEvent(
      id: title,
      slug: title.toLowerCase().replaceAll(RegExp(r'[^a-z]+'), '-'),
      title: title,
      volume: volume,
      liquidity: 50000,
      category: category,
      tags: tags,
      endDate: endDate,
      conditionId: 'c-$title',
      outcomes: outcomes,
    );

const _yes = 'Yes', _no = 'No';

final _predictions = [
  _event('Lula flips Bolsonaro for Brazil president in 2026?',
      outcomes: const [
        PolymarketOutcome(name: _yes, price: 0.62),
        PolymarketOutcome(name: _no, price: 0.38),
      ],
      tags: const ['politics', 'elections', 'brazil'],
      category: 'politics',
      endDate: DateTime(_now.year, 12, 31)),
  _event('Bank of Brazil decision in December?',
      outcomes: const [
        PolymarketOutcome(name: 'No change', price: 0.71),
        PolymarketOutcome(name: '25 bps decrease', price: 0.24),
        PolymarketOutcome(name: '50+ bps decrease', price: 0.05),
      ],
      tags: const ['economy', 'finance'],
      endDate: DateTime(_now.year, 12, 10)),
  _event('Bank of Brazil decision in November?',
      outcomes: const [
        PolymarketOutcome(name: 'No change', price: 0.88),
        PolymarketOutcome(name: '25 bps decrease', price: 0.11),
      ],
      tags: const ['economy'],
      endDate: DateTime(_now.year, 11, 5)),
  _event('Alexandre de Moraes out as Brazil Supreme Court justice in 2026?',
      outcomes: const [
        PolymarketOutcome(name: _yes, price: 0.07),
        PolymarketOutcome(name: _no, price: 0.93),
      ],
      tags: const ['politics', 'geopolitics'],
      category: 'politics',
      endDate: DateTime(_now.year + 1, 1, 31)),
  _event('Brazil vs. Argentina',
      outcomes: const [
        PolymarketOutcome(name: 'Brazil', price: 0.54),
        PolymarketOutcome(name: 'Argentina', price: 0.46),
      ],
      tags: const ['sports', 'soccer'],
      category: 'sports',
      endDate: DateTime(_now.year, _now.month, _now.day + 3)),
];

const _investing = [
  HlMarketSearchResult(
      coin: 'TSLA',
      wireCoin: 'xyz:TSLA',
      kind: HlMarketKind.perp,
      isStock: true,
      name: 'Tesla',
      category: 'stocks',
      iconUrl: null,
      markPx: 438.21,
      dayChangePct: 0.0213,
      maxLeverage: 10),
  HlMarketSearchResult(
      coin: 'TSLA',
      wireCoin: '@182',
      kind: HlMarketKind.spot,
      isStock: true,
      name: 'Tesla',
      category: 'stocks',
      iconUrl: null,
      markPx: 437.95,
      dayChangePct: 0.0198),
  HlMarketSearchResult(
      coin: 'BTC',
      wireCoin: 'BTC',
      kind: HlMarketKind.perp,
      isStock: false,
      name: 'Bitcoin',
      category: 'crypto',
      iconUrl: null,
      markPx: 121845,
      dayChangePct: -0.0124,
      maxLeverage: 40),
  HlMarketSearchResult(
      coin: 'GLD',
      wireCoin: 'xyz:GOLD',
      kind: HlMarketKind.perp,
      isStock: true,
      name: 'Gold',
      category: 'commodities',
      iconUrl: null,
      markPx: 3871.4,
      dayChangePct: 0.0041,
      maxLeverage: 20),
];

Settings _settings() => Settings(
      currency: 'USD',
      language: 'en',
      btcFormat: 'sats',
      backup: false,
      biometricsEnabled: false,
      bitcoinElectrumNode: '',
      nodeType: 'Blockstream',
      reviewDone: true,
      wallets: [WalletConfig(id: 'spending', name: 'Spending')],
      activeWalletId: 'spending',
    );

Future<void> _render(WidgetTester tester,
    {required String lang, required bool dark, required bool predictions}) async {
  tester.view.physicalSize = const Size(390, 844) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  OpenOnce.reset();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: [
      settingsProvider.overrideWith((_) => SettingsModel(_settings())),
      aiEnabledProvider.overrideWith((_) async => true),
      sportsLiveProvider.overrideWith(_Sports.new),
      tradeNotificationsProvider
          .overrideWith((_) => Stream.value(const <TradeNotification>[])),
      unifiedSearchResultsProvider
          .overrideWith((_) async => UnifiedSearchResults.empty),
      globalMarketResultsProvider.overrideWith((ref) =>
          ref.watch(searchQueryProvider).isEmpty
              ? const AsyncValue.data([])
              : AsyncValue.data(
                  [for (final e in _predictions) GlobalMarketSearchResult(e)])),
      globalHyperliquidResultsProvider.overrideWith((ref) =>
          ref.watch(searchQueryProvider).isEmpty
              ? const AsyncValue.data([])
              : const AsyncValue.data(_investing)),
      hyperliquidAllMarketsProvider.overrideWith((_) => []),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: Locale(lang),
        theme: dark ? buildDarkTheme() : buildLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) =>
            RepaintBoundary(key: _shotKey, child: child),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showKuteSearch(
                  context,
                  initialCategory: predictions
                      ? SearchCategory.predictions
                      : SearchCategory.perpetuals,
                  searchFirst: true,
                  searchHint: predictions
                      ? context.l10n.searchPredictionsHint
                      : context.l10n.searchInvestmentsHint,
                  source: predictions ? 'predictions' : 'trading',
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  // The tab the screenshot was taken on: a previous open could have left
  // the sheet on All.
  final tabs = find.byType(KutePillTabs);
  if (tabs.evaluate().isNotEmpty) {
    final index = predictions ? 2 : 3;
    final pills = find.descendant(of: tabs.first, matching: find.byType(KutePill));
    if (pills.evaluate().length > index) {
      await tester.tap(pills.at(index));
      await tester.pumpAndSettle();
    }
  }
  await tester.enterText(find.byType(TextField), predictions ? 'brazil' : 'tesla');
  await tester.pump(const Duration(milliseconds: 200));
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pumpAndSettle();
  for (Object? e = tester.takeException(); e != null; e = tester.takeException()) {
    final text = '$e'.split('\n').first;
    if (!text.contains('MissingPlugin') && !text.contains('HTTP')) {
      // ignore: avoid_print
      print('RENDER problem: $text');
    }
  }
  final name =
      '${predictions ? 'predictions' : 'investing'}_${lang}_${dark ? 'dark' : 'light'}';
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_shotKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_out/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  });
  // ignore: avoid_print
  print('RENDER wrote $name.png');
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 6));
}

void main() {
  if (_out.isEmpty) {
    test('search render', () {},
        skip: 'on demand: --dart-define=SEARCH_RENDER_OUT=<dir>');
    return;
  }

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    Directory(_out).createSync(recursive: true);
    GoogleFonts.config.allowRuntimeFetching = false;
    expect(await AdvisorInputGuard.isSafe('bitcoin'), isTrue);
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
  });

  for (final predictions in [true, false]) {
    for (final lang in ['en', 'pt']) {
      for (final dark in [false, true]) {
        testWidgets(
            'render ${predictions ? 'predictions' : 'investing'} $lang '
            '${dark ? 'dark' : 'light'}',
            (tester) => _render(tester,
                lang: lang, dark: dark, predictions: predictions));
      }
    }
  }
}
