// What a market is, at the top of its About sheet: a curated description
// keyed by the market's underlying (one text for gold on every builder
// dex), else a template built from what the app knows about the market.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/advisor_provider.dart' show aiEnabledProvider;
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_candles_provider.dart';
import 'package:kute/providers/hyperliquid_insights_provider.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_orderbook_provider.dart';
import 'package:kute/providers/hyperliquid_sats_pnl_provider.dart'
    show hyperliquidActivityFillsProvider;
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_market_description.dart';
import 'package:kute/screens/hyperliquid/market_detail_sheet.dart'
    show HlMarketDetailSheet;
import 'package:kute/screens/shared/kute_bar_context.dart'
    show kuteBarScrollClearance;
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/theme/app_theme.dart';

HlMarket _market(
  String coin, {
  HlMarketKind kind = HlMarketKind.perp,
  String category = 'crypto',
  String dex = '',
  String? unitAssetName,
}) =>
    HlMarket(
      coin: coin,
      wireCoin: dex.isEmpty ? coin : '$dex:$coin',
      assetId: 0,
      kind: kind,
      szDecimals: 2,
      maxLeverage: 10,
      onlyIsolated: false,
      markPx: 100,
      midPx: 100,
      prevDayPx: 99,
      dayNtlVlm: 1e6,
      category: category,
      dex: dex,
      isHip3: dex.isNotEmpty,
      unitAssetName: unitAssetName,
    );

Map<String, String> _bundledTable() => HlMarketDescriptions.parse(
    File(HlMarketDescriptions.assetPath).readAsStringSync());

final _l10n = lookupAppLocalizations(const Locale('en'));

void main() {
  setUp(HlDexNames.debugReset);

  group('the curated table', () {
    test('ships well-formed: one text per underlying key', () {
      final table = _bundledTable();
      expect(table.length, greaterThanOrEqualTo(200));
      for (final e in table.entries) {
        expect(e.key, matches(RegExp(r'^[ct]:[a-z0-9]+$')), reason: e.key);
        expect(e.value.length, lessThan(260), reason: e.key);
      }
    });

    test('gold on two builder dexes and the gold token share one text', () {
      final table = _bundledTable();
      final xyz = _market('GOLD', category: 'commodities', dex: 'xyz');
      final flx = _market('GOLD', category: 'commodities', dex: 'flx');
      final token = _market('XAUT0',
          kind: HlMarketKind.spot, category: 'commodities');
      final text = hlMarketDescription(_l10n, xyz, table);
      expect(text, startsWith('Gold:'));
      expect(hlMarketDescription(_l10n, flx, table), text);
      expect(hlMarketDescription(_l10n, token, table), text);
    });

    test('Anthropic under its builders\' tickers, one text', () {
      final table = _bundledTable();
      final texts = {
        for (final m in [
          _market('ANTH', category: 'preipo', dex: 'io'),
          _market('ANT', category: 'preipo', dex: 'xyz'),
          _market('ANTHROPIC', category: 'preipo', dex: 'vntl'),
        ])
          hlMarketDescription(_l10n, m, table),
      };
      expect(texts, hasLength(1));
      expect(texts.single, startsWith('Anthropic (pre-IPO)'));
    });

    test('the Unit token reads as its asset; a crypto GAS is not natural '
        'gas', () {
      final table = _bundledTable();
      final ubtc = _market('UBTC',
          kind: HlMarketKind.spot, unitAssetName: 'Bitcoin');
      expect(hlMarketDescription(_l10n, ubtc, table),
          hlMarketDescription(_l10n, _market('BTC'), table));
      expect(hlCuratedDescription(table, _market('GAS')), isNull);
      expect(
          hlCuratedDescription(
              table, _market('GAS', category: 'commodities', dex: 'flx')),
          startsWith('Natural gas'));
    });

    testWidgets('the loader reads the bundled asset', (tester) async {
      HlMarketDescriptions.debugReset();
      addTearDown(HlMarketDescriptions.debugReset);
      final table = (await tester.runAsync(HlMarketDescriptions.load))!;
      expect(table['t:gold'], startsWith('Gold:'));
    });
  });

  group('the template for a market the table does not cover', () {
    test('a builder dex stock perp names its venue', () {
      HlDexNames.remember('xyz', 'XYZ');
      expect(
          hlMarketDescription(
              _l10n, _market('QNT', category: 'stocks', dex: 'xyz'), const {}),
          'QNT · a stock-linked perpetual traded on XYZ via Hyperliquid.');
    });

    test('a named main-dex perp: name and ticker, traded on Hyperliquid', () {
      expect(hlMarketDescription(_l10n, _market('BTC'), const {}),
          'Bitcoin (BTC) · a perpetual on a crypto token traded on '
          'Hyperliquid.');
    });

    test('a spot token, and a builder dex without a known name', () {
      expect(
          hlMarketDescriptionFallback(
              _l10n, _market('FOO', kind: HlMarketKind.spot)),
          'FOO · a spot token traded on Hyperliquid.');
      expect(
          hlMarketDescriptionFallback(
              _l10n, _market('ZZ', category: 'preipo', dex: 'abc')),
          'ZZ · a perpetual on a private company before its IPO traded on '
          'ABC via Hyperliquid.');
    });
  });

  group('the About sheet', () {
    const btc = HlMarket(
      coin: 'BTC',
      wireCoin: 'BTC',
      assetId: 0,
      kind: HlMarketKind.perp,
      szDecimals: 5,
      maxLeverage: 40,
      onlyIsolated: false,
      markPx: 66000,
      midPx: 66000,
      prevDayPx: 65000,
      dayNtlVlm: 1e9,
      funding: 0.0000125,
    );

    Future<void> openAbout(WidgetTester tester) async {
      GoogleFonts.config.allowRuntimeFetching = false;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(OpenOnce.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          hyperliquidLivePricesProvider.overrideWith(_LivePrices.new),
          hyperliquidAccountMarketProvider('BTC').overrideWith((_) => btc),
          hyperliquidExactMarketProvider.overrideWith((ref, key) => btc),
          hyperliquidActiveAssetCtxProvider
              .overrideWith((ref, wire) => const Stream.empty()),
          hyperliquidOrderbookProvider
              .overrideWith((ref, wire) => const Stream.empty()),
          hyperliquidPerpPositionsProvider.overrideWith((_) => const []),
          hyperliquidSpotBalancesProvider.overrideWith((_) => const []),
          hyperliquidActivityFillsProvider.overrideWith((_) => const []),
          hyperliquidTradingProvider.overrideWith(_Trading.new),
          hyperliquidLiveCandlesProvider.overrideWith(
              (ref, key) => Stream.value(const HlLiveCandlesState())),
          hyperliquidTradeFlowProvider.overrideWith(
              (ref, coin) => Stream.value(const HlTradeFlowState())),
          aiEnabledProvider.overrideWith((ref) async => false),
          hlMarketDescriptionsProvider.overrideWith((ref) async =>
              const {'c:bitcoin': 'Bitcoin: a fixed-supply digital asset.'}),
        ],
        child: ScreenUtilInit(
          designSize: const Size(430, 932),
          builder: (_, __) => MaterialApp(
            theme: ThemeData(
              splashFactory: NoSplash.splashFactory,
              extensions: [AppColorsExtension.light()],
            ),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const HlMarketDetailSheet(market: btc),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      final row = find.text('About Bitcoin');
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('"What it is" opens the sheet, above Stats; the venue line '
        'replaces the Instrument row', (tester) async {
      await openAbout(tester);
      final block = find.byKey(const ValueKey('hl-about-what-it-is'));
      expect(block, findsOneWidget);
      final description = find.text('Bitcoin: a fixed-supply digital asset.');
      expect(find.descendant(of: block, matching: description),
          findsOneWidget);
      expect(
          find.descendant(
              of: block, matching: find.text('Traded on Hyperliquid · Perp')),
          findsOneWidget);
      expect(find.text('Instrument'), findsNothing);
      // First in the sheet's scroll: nothing above it, Stats under it.
      final scroll = find.ancestor(
          of: block, matching: find.byType(SingleChildScrollView));
      final column = tester.widget<Column>(find
          .descendant(of: scroll.first, matching: find.byType(Column))
          .first);
      expect((column.children.first.key), const ValueKey('hl-about-what-it-is'));
      expect(tester.getRect(block).bottom,
          lessThanOrEqualTo(tester.getTopLeft(find.text('Stats')).dy));
      final style = tester.widget<Text>(description).style!;
      expect(style.fontSize, 15.sp);
      expect(style.color, AppColorsExtension.light().textPrimary);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the sheet scrolls clear of the floating bar', (tester) async {
      await openAbout(tester);
      final scroll = tester.widget<SingleChildScrollView>(find
          .ancestor(
              of: find.byKey(const ValueKey('hl-about-what-it-is')),
              matching: find.byType(SingleChildScrollView))
          .first);
      expect((scroll.padding! as EdgeInsets).bottom,
          kuteBarScrollClearance.h);
    });
  });
}

// No socket in a test.
class _LivePrices extends HlLivePricesNotifier {
  @override
  HlLivePriceState build() => const HlLivePriceState(mids: {'BTC': 66000});
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

class _Trading extends HyperliquidTradingNotifier {
  @override
  Future<HyperliquidTradingState> build() async =>
      const HyperliquidTradingState(isInitialized: true);
}
