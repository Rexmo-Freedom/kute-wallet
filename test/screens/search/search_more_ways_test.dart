// Search shows a market that trades more than one way ONCE (founder,
// 7 November 2026: "nv" listed Nvidia twice, NVDAX and EQNVDA: "why on
// search there are many things the same? fix or make it clear"). Nvidia
// is one row, xyz:NVDA (the most traded), with "3 more ways to trade
// NVDA" under it; tapped, io's perp and the two tokens open in place,
// each saying what sets it apart. An exact ticker of one of the others
// shows that one; a closed stock gate leaves the tokens alone.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_search_provider.dart';
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/trade_notifications_provider.dart';
import 'package:kute/providers/unified_search_provider.dart';
import 'package:kute/screens/search/unified_search_screen.dart';
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/services/advisor/advisor_input_guard.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/trade_notification_store.dart'
    show TradeNotification;
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart' show Fixed;

import '../../helpers/runtime_policy_fixture.dart';

HlMarket _perp(String dex, String coin,
        {required double volume,
        double oi = 0,
        double px = 187.42,
        String category = 'stocks'}) =>
    HlMarket(
      coin: coin,
      wireCoin: '$dex:$coin',
      assetId: 110000,
      kind: HlMarketKind.perp,
      szDecimals: 3,
      maxLeverage: 20,
      onlyIsolated: false,
      markPx: px,
      midPx: px,
      prevDayPx: 188.6,
      dayNtlVlm: volume,
      openInterest: oi,
      category: category,
      dex: dex,
      isHip3: true,
      iconUrl: HlMarket.hlIconUrl('$dex:$coin'),
    );

HlMarket _spot(String coin, String wire,
        {required double volume, double px = 188.13}) =>
    HlMarket(
      coin: coin,
      wireCoin: wire,
      assetId: 10000 + int.parse(wire.substring(1)),
      kind: HlMarketKind.spot,
      szDecimals: 2,
      maxLeverage: 1,
      onlyIsolated: false,
      markPx: px,
      midPx: px,
      prevDayPx: 188.28,
      dayNtlVlm: volume,
      iconUrl: HlMarket.hlSpotIconUrl(coin),
    );

/// The venue's Nvidia listings on 7 November 2026, plus Tesla, resolved
/// as the browse universe resolves them.
List<HlMarket> _universe() => resolveHlBrowseUniverse([
      _perp('xyz', 'NVDA', volume: 14296610, oi: 486914),
      _perp('io', 'NVDA',
          volume: 1234312, oi: 10651.8, px: 187.48, category: 'other'),
      _perp('xyz', 'TSLA', volume: 4826836, px: 410),
    ], [
      _spot('NVDAX', '@702', volume: 23818),
      _spot('EQNVDA', '@1155', volume: 2171, px: 187.39),
    ]);

List<String> _wires(Iterable<HlMarketSearchResult> l) =>
    [for (final r in l) r.wireCoin];

class _Sports extends SportsLiveNotifier {
  @override
  Map<String, SportsMatchUpdate> build() => {};
  @override
  void connect() {}
}

class _Currency extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _Currency() : super(CurrencyState({'USD': Fixed.fromInt(100000)}));
  @override
  Future<void> updateRates() async {}
}

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

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _open(WidgetTester tester, String query,
    List<HlMarketSearchResult> results) async {
  tester.view.physicalSize = const Size(430, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      settingsProvider.overrideWith((_) => SettingsModel(_settings())),
      currencyProvider.overrideWith((_) => _Currency()),
      aiEnabledProvider.overrideWith((_) async => true),
      sportsLiveProvider.overrideWith(_Sports.new),
      tradeNotificationsProvider
          .overrideWith((_) => Stream.value(const <TradeNotification>[])),
      unifiedSearchResultsProvider
          .overrideWith((ref) async => UnifiedSearchResults.empty),
      globalMarketResultsProvider
          .overrideWith((ref) => const AsyncValue.data([])),
      globalHyperliquidResultsProvider.overrideWith((ref) =>
          ref.watch(searchQueryProvider).isEmpty
              ? const AsyncValue.data([])
              : AsyncValue.data(results)),
      hyperliquidAllMarketsProvider.overrideWith((_) => []),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
          fontFamily: 'Inter',
          extensions: [AppColorsExtension.light()],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showKuteSearch(context, source: 'home'),
              child: const Text('Open search'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Open search'));
  await tester.pump(const Duration(milliseconds: 500));
  await tester.enterText(find.byType(TextField), query);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await _settle(tester);
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 6));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The query guard reads its word list once, for real.
  setUpAll(() async => expect(await AdvisorInputGuard.isSafe('nvdax'), isTrue));
  setUp(() {
    HlDexNames.remember('xyz', 'XYZ');
    HlDexNames.remember('io', 'EntropyIO');
  });

  group('the search', () {
    test(
        '"nv" is one Nvidia result, the most traded perp, with the other '
        'three listings under it', () async {
      final results = await hlSearchMarkets(_universe(), 'nv');
      final nvidia = results.where((r) => r.groupTicker == 'NVDA').toList();
      expect(nvidia, hasLength(1));
      expect(nvidia.single.wireCoin, 'xyz:NVDA');
      expect(nvidia.single.name, 'Nvidia');
      expect(_wires(nvidia.single.alternatives), ['io:NVDA', '@702', '@1155']);
      // The tokens read as Nvidia, under their own tickers.
      expect([for (final a in nvidia.single.alternatives) a.name],
          ['Nvidia', 'Nvidia', 'Nvidia']);
      expect(nvidia.single.alternatives.last.coin, 'EQNVDA');
      // Nothing for Nvidia anywhere else in the list.
      expect(
          results
              .where((r) => r != nvidia.single)
              .where((r) => r.market?.underlyingTicker == 'NVDA'),
          isEmpty);
    });

    test(
        'an exact ticker of another listing shows that listing, the rest '
        'under it', () async {
      final nvdax = await hlSearchMarkets(_universe(), 'NVDAX');
      expect(_wires(nvdax), ['@702']);
      expect(
          _wires(nvdax.single.alternatives), ['xyz:NVDA', 'io:NVDA', '@1155']);
      expect(nvdax.single.groupTicker, 'NVDA');

      final eq = await hlSearchMarkets(_universe(), 'eqnvda');
      expect(_wires(eq), ['@1155']);
      // The ticker itself still leads with the primary.
      final nvda = await hlSearchMarkets(_universe(), 'nvda');
      expect(nvda.first.wireCoin, 'xyz:NVDA');
      expect(nvda, hasLength(1));
    });

    test('a market that trades once has nothing under it', () async {
      final tsla = await hlSearchMarkets(_universe(), 'tsla');
      expect(_wires(tsla), ['xyz:TSLA']);
      expect(tsla.single.alternatives, isEmpty);
    });

    test(
        'the stock gate closed (founder, 12 November 2026): Nvidia still '
        'leads with xyz:NVDA, the tokens under it; only its ticket shuts',
        () async {
      AffiliateService.debugSessionToken = 'test-session';
      addTearDown(() => AffiliateService.debugSessionToken = null);
      final blocked = runtimePolicyFixture(blocked: {'hyperliquid.stocks'});
      addTearDown(blocked.dispose);
      expect(await blocked.refresh(), isTrue);
      final results = await hlSearchMarkets(_universe(), 'nv');
      expect(results.first.wireCoin, 'xyz:NVDA');
      expect(_wires(results.first.alternatives), ['io:NVDA', '@702', '@1155']);
      expect(results.first.groupTicker, 'NVDA');
      final perp = _universe().firstWhere((m) => m.wireCoin == 'xyz:NVDA');
      expect(hlStockGateAllows(perp, blocked), isFalse);
    });
  });

  group('the sheet', () {
    late List<(String, Map<String, Object>?)> events;
    setUp(() {
      GoogleFonts.config.allowRuntimeFetching = false;
      OpenOnce.reset();
      events = [];
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    });
    tearDown(() => TrackingService.debugTrackObserver = null);

    testWidgets(
        'one Nvidia row and "3 more ways to trade NVDA"; tapped, the '
        'others open, each labelled', (tester) async {
      final results = await hlSearchMarkets(_universe(), 'nv');
      await _open(tester, 'nv', results);

      expect(find.text('Nvidia'), findsOneWidget);
      expect(find.text('NVDA'), findsOneWidget);
      final more = find.text('3 more ways to trade NVDA');
      expect(more, findsOneWidget);
      expect(find.text('NVDA · EntropyIO'), findsNothing);
      expect(find.text('NVDAX · Spot'), findsNothing);

      await tester.tap(more);
      await _settle(tester);
      expect(find.text('Nvidia'), findsNWidgets(4));
      expect(find.text('NVDA · EntropyIO'), findsOneWidget);
      expect(find.text('NVDAX · Spot'), findsOneWidget);
      expect(find.text('EQNVDA · Spot'), findsOneWidget);
      // Opening the others is not a result tap: nothing is tracked.
      expect(events.where((e) => e.$1 == 'search_result_tapped'), isEmpty);

      // Tapped again, they close.
      await tester.tap(more);
      await _settle(tester);
      expect(find.text('NVDA · EntropyIO'), findsNothing);
      expect(find.text('Nvidia'), findsOneWidget);
      await _close(tester);
    });

    testWidgets('an exact ticker of a token shows the token\'s row first',
        (tester) async {
      final results = await hlSearchMarkets(_universe(), 'NVDAX');
      await _open(tester, 'NVDAX', results);
      expect(find.text('NVDAX · Spot'), findsOneWidget);
      expect(find.text('3 more ways to trade NVDA'), findsOneWidget);
      await _close(tester);
    });
  });
}
