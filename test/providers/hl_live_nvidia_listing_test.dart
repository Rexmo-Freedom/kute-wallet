// "What happened to the NVIDIA perp? It does not show up?" (founder,
// 12 November 2026, build 115). Search for "nv" offered only the NVDAX and
// EQNVDA tokens; xyz:NVDA, the most traded stock perp on Hyperliquid, was
// gone, and so were io:NVDA and every other stock-linked perp: the live
// policy refuses `hyperliquid.stocks` in the UK (country_blocked) and the
// app used to hide what the policy refused.
//
// FOUNDER DECISION, same day: "we should not hide, we can show, just not
// allow to purchase. Showing the price is ok." So whatever the policy
// refuses, the markets stay in browse, Trending, the strip and search, and
// only the buy is shut: the ticket opens under the policy's reason, before
// Face ID and before any money moves. Closing and reducing stay open.
//
// The fixtures are the venue's own public answers on 12 November 2026
// (metaAndAssetCtxs for the main dex and the builder dexes that list a
// big-tech stock, perpConciseAnnotations, perpDexs, spotMetaAndAssetCtxs),
// trimmed to the most traded markets and every listing of NVDA, TSLA,
// AAPL, GOOGL, META, AMZN and MSFT. Run through the app's own parsing,
// browse universe, lists, Trending strip, search and order ticket, they
// show:
//
// * under ANY policy (stocks allowed, stocks and trading refused for the
//   region, the policy unreadable), xyz:NVDA is Nvidia's primary listing
//   everywhere (Stocks, Trending, the Trending strip, search for "nvidia",
//   "nvda" and "nv"), with io:NVDA, NVDAX and EQNVDA behind it under
//   "more ways", and the other big-tech names list under Stocks from xyz;
// * with `hyperliquid.stocks` refused, the xyz:NVDA ticket opens shut: the
//   region note with "check your VPN settings" and "Check connection" as
//   its one button (never the order), a held Nvidia position cannot be
//   added to, and reducing or closing it stays open;
// * with `hyperliquid.trade` refused, every buy is shut the same way (a
//   crypto perp, a stock perp, a stock token), the lists unchanged;
// * with the policy unreadable, the markets still show and the ticket is
//   shut (fail closed).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_orderbook_provider.dart';
import 'package:kute/providers/hyperliquid_search_provider.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider;
import 'package:kute/screens/hyperliquid/components/close_position_sheet.dart';
import 'package:kute/screens/hyperliquid/components/hl_moving_now_strip.dart'
    show hlTrendingStrip;
import 'package:kute/screens/hyperliquid/components/order_slip_sheet.dart';
import 'package:kute/screens/shared/capability_block_note.dart';
import 'package:kute/services/investment_provider_availability.dart';
import 'package:kute/services/region_freshness.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:money2/money2.dart';

import '../helpers/fake_swap_orders.dart';
import '../helpers/runtime_policy_fixture.dart';
import '../helpers/shell_bar_harness.dart';

const _dir = 'test/fixtures/hyperliquid_live_2026_11_12';

dynamic _read(String name) =>
    jsonDecode(File('$_dir/$name').readAsStringSync());

/// The perps as the app loads them: every builder dex in the venue's
/// order, a dex settling in another stablecoin left out
/// (HyperliquidModel._loadAllPerpMarkets).
List<HlMarket> _livePerps() {
  final annotations =
      HlPerpAnnotation.parseList(_read('perp_concise_annotations.json'));
  final perps =
      HlMarket.parsePerpList(_read('meta_main.json'), annotations: annotations);
  final dexes = _read('perp_dexs.json') as List;
  for (var i = 0; i < dexes.length; i++) {
    final dex = dexes[i];
    if (dex == null) continue;
    final file = File('$_dir/meta_${dex['name']}.json');
    if (!file.existsSync()) continue;
    final decoded = jsonDecode(file.readAsStringSync());
    if (hlMetaCollateralToken(decoded) != hlUsdcCollateralToken) continue;
    perps.addAll(HlMarket.parsePerpList(decoded,
        dex: dex['name'] as String, dexIndex: i, annotations: annotations));
  }
  return perps;
}

List<HlMarket> _liveSpots() => HlMarket.parseSpotList(_read('spot_meta.json'));

List<HlMarket> _liveUniverse() =>
    resolveHlBrowseUniverse(_livePerps(), _liveSpots());

/// The browse universe exactly as the Investing tab, its strip and search
/// read it ([hyperliquidBrowseUniverseProvider]), under [policy].
Future<List<HlMarket>> _browseUniverse(
    RuntimeCapabilitiesService policy) async {
  final perps = _livePerps();
  final spots = _liveSpots();
  final container = ProviderContainer(overrides: [
    hyperliquidPerpMarketsProvider.overrideWith((_) async => perps),
    hyperliquidPerpCoreMarketsProvider.overrideWith((_) async => perps),
    hyperliquidSpotMarketsProvider.overrideWith((_) async => spots),
    runtimeCapabilitiesProvider.overrideWithValue(policy),
  ]);
  addTearDown(container.dispose);
  final sub = container.listen(hyperliquidBrowseUniverseProvider, (_, __) {});
  addTearDown(sub.close);
  await container.read(hyperliquidPerpMarketsProvider.future);
  await container.read(hyperliquidSpotMarketsProvider.future);
  return container.read(hyperliquidBrowseUniverseProvider).requireValue;
}

/// A policy whose fetch never answers: nothing loaded, nothing in grace.
RuntimeCapabilitiesService _unreadablePolicy() =>
    RuntimeCapabilitiesService.forTesting(
      client: MockClient((_) async => http.Response('unavailable', 503)),
      baseUrl: () => 'https://policy.test',
      sessionToken: () => AffiliateService.sessionToken,
    );

const _ukRefused = {
  'hyperliquid.stocks': 'country_blocked',
  'hyperliquid.trade': 'country_blocked',
};

const _bigTech = ['NVDA', 'TSLA', 'AAPL', 'GOOGL', 'META', 'AMZN', 'MSFT'];

// ── The ticket ─────────────────────────────────────────────────────────

/// Kute's policy as the ticket reads it: [refused] maps each refused
/// capability to its reason; everything else is allowed.
class _Policy extends Fake implements RuntimeCapabilitiesService {
  _Policy(this.refused);
  final Map<String, String> refused;

  @override
  CapabilityDecision decision(String id) => refused.containsKey(id)
      ? CapabilityDecision(allowed: false, reason: refused[id]!)
      : const CapabilityDecision(allowed: true);
  @override
  bool allows(String id) => decision(id).allowed;
  @override
  String? blockReason(String id) =>
      decision(id).allowed ? null : decision(id).message;
  @override
  Future<void> ensureAllAllowed(Iterable<String> ids,
      {Duration maxAge = Duration.zero}) async {
    for (final id in ids) {
      if (!decision(id).allowed) {
        throw CapabilityUnavailableException(id, decision(id));
      }
    }
  }

  @override
  Future<void> ensureAllowed(String id, {Duration maxAge = Duration.zero}) =>
      ensureAllAllowed([id], maxAge: maxAge);
  @override
  Future<bool> networkChanged() async => true;
  @override
  int? get maxLeverage => null;
  @override
  int offeredLeverage(int venueMax) => venueMax;
}

class _LivePrices extends HlLivePricesNotifier {
  _LivePrices(this.mids);
  final Map<String, double> mids;
  @override
  HlLivePriceState build() => HlLivePriceState(mids: mids);
  @override
  void acquire() {}
  @override
  void release() {}
  @override
  void watchCoins(List<String> coins, {Map<String, String>? wire}) {}
  @override
  void focus(String coin, {String? wire}) {}
  @override
  void unfocus(String coin) {}
}

class _Currency extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _Currency() : super(CurrencyState({'USD': Fixed.fromInt(1)}));
  @override
  Future<void> updateRates() async {}
}

class _Account extends HlAccountNotifier {
  _Account(this.positions);
  final List<HlPerpPosition> positions;
  @override
  Future<HlAccountSnapshot> build() async => HlAccountSnapshot(
        accountValue: 500,
        withdrawable: 500,
        totalMarginUsed: 0,
        positions: positions,
        spotBalances: const [],
      );
}

class _Trading extends HyperliquidTradingNotifier {
  _Trading(this.positions);
  final List<HlPerpPosition> positions;
  @override
  Future<HyperliquidTradingState> build() async => HyperliquidTradingState(
      isInitialized: true, withdrawable: 500, positions: positions);
}

/// A held Nvidia long: 2 xyz:NVDA.
HlPerpPosition _heldNvidia(HlMarket m) => HlPerpPosition(
      coin: m.wireCoin,
      szi: 2,
      entryPx: m.markPx,
      positionValue: 2 * m.markPx,
      unrealizedPnl: 0,
      returnOnEquity: 0,
      liquidationPx: null,
      marginUsed: 2 * m.markPx,
      leverageType: 'isolated',
      leverageValue: 1,
      maxLeverage: m.maxLeverage,
    );

Settings get _settings => Settings(
      currency: 'USD',
      language: 'en',
      btcFormat: 'sats',
      backup: false,
      biometricsEnabled: false,
      bitcoinElectrumNode: '',
      nodeType: 'Blockstream',
      reviewDone: true,
    );

Future<void> _frames(WidgetTester tester, [int n = 10]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pump(
    WidgetTester tester, RuntimeCapabilitiesService policy, Widget child,
    {List<HlPerpPosition> held = const [],
    Map<String, double> mids = const {}}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));
  installShellBar();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      settingsProvider.overrideWith((_) => SettingsModel(_settings)),
      swapOrdersProvider.overrideWith((_) => FakeSwapOrders()),
      aiEnabledProvider.overrideWith((_) async => false),
      currencyProvider.overrideWith((_) => _Currency()),
      runtimeCapabilitiesProvider.overrideWithValue(policy),
      usdBalanceProvider.overrideWith((_) => 0),
      hyperliquidLivePricesProvider.overrideWith(() => _LivePrices(mids)),
      hyperliquidAccountProvider.overrideWith(() => _Account(held)),
      hyperliquidTradingProvider.overrideWith(() => _Trading(held)),
      hyperliquidPerpPositionsProvider.overrideWith((_) => held),
      hyperliquidAddressProvider.overrideWith((_) async => null),
      hyperliquidOrderbookProvider
          .overrideWith((_, __) => Stream.value(const HlOrderBookState())),
    ],
    child: shellBarApp(
      home: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Align(alignment: Alignment.bottomCenter, child: child),
      ),
    ),
  ));
  await _frames(tester);
}

Finder get _note => find.byType(CapabilityBlockNote);

String _noteText(WidgetTester tester) =>
    tester.widget<CapabilityBlockNote>(_note.first).message;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late InvestmentProviderAvailability venues;

  setUp(() {
    AffiliateService.debugSessionToken = 'test-session';
    GoogleFonts.config.allowRuntimeFetching = false;
    // The venues' own location answers: open, so only Kute's policy speaks.
    venues = InvestmentProviderAvailability(
      client: MockClient(
          (request) async => request.url.host == 'api.hyperliquid.xyz'
              ? http.Response(
                  jsonEncode({
                    'acceptedTerms': true,
                    'userAllowed': true,
                    'restrictions': 'n',
                  }),
                  200)
              : http.Response(jsonEncode({'blocked': false}), 200)),
      report: ({
        required String venue,
        required String trigger,
        required bool changed,
        required String result,
      }) {},
    );
    RegionFreshness.debugVenues = venues;
  });
  tearDown(() {
    AffiliateService.debugSessionToken = null;
    RuntimeCapabilitiesService.debugInstance = null;
    RegionFreshness.debugVenues = null;
    venues.dispose();
  });

  test('the venue lists Nvidia as xyz:NVDA, io:NVDA, NVDAX and EQNVDA', () {
    final universe = _liveUniverse();
    final nvidia = [
      for (final m in universe)
        if (m.underlyingTicker == 'NVDA') m.wireCoin
    ];
    // Volume order: xyz:NVDA traded about $1.6B in the day.
    expect(nvidia, ['xyz:NVDA', 'io:NVDA', '@702', '@1155']);
    final xyz = universe.firstWhere((m) => m.wireCoin == 'xyz:NVDA');
    expect(xyz.category, 'stocks');
    expect(xyz.dayNtlVlm, greaterThan(1e9));
    expect(xyz.iconUrl, HlMarket.hlIconUrl('xyz:NVDA'));
    // The delisted NVDA perps on km, mkts and cash never load.
    for (final dead in ['km:NVDA', 'mkts:NVDA', 'cash:NVDA']) {
      expect(universe.any((m) => m.wireCoin == dead), isFalse, reason: dead);
    }
  });

  // Every policy the app can be under: the lists are the same.
  final policies = <String, Future<RuntimeCapabilitiesService> Function()>{
    'stock perps allowed': () async {
      final p = runtimePolicyFixture();
      expect(await p.refresh(), isTrue);
      return p;
    },
    'stock perps and trading refused (the UK today)': () async {
      final p = runtimePolicyFixture(
          blocked: _ukRefused.keys.toSet(), reasons: _ukRefused);
      expect(await p.refresh(), isTrue);
      expect(p.allows('hyperliquid.stocks'), isFalse);
      expect(p.allows('hyperliquid.trade'), isFalse);
      return p;
    },
    'trading refused, stocks allowed': () async {
      final p = runtimePolicyFixture(
          blocked: {'hyperliquid.trade'},
          reasons: {'hyperliquid.trade': 'country_blocked'});
      expect(await p.refresh(), isTrue);
      return p;
    },
    'the policy unreadable (outage)': () async {
      final p = _unreadablePolicy();
      expect(await p.refresh(), isFalse);
      // Fail closed for buying, open for looking.
      expect(p.allows('hyperliquid.stocks'), isFalse);
      expect(p.allows('hyperliquid.trade'), isFalse);
      expect(p.allows('hyperliquid.browse'), isTrue);
      return p;
    },
  };

  for (final MapEntry(key: name, value: make) in policies.entries) {
    test(
        '$name: xyz:NVDA is the one Nvidia row in Stocks, Trending, the '
        'strip and search, the tokens under more ways', () async {
      final policy = await make();
      addTearDown(policy.dispose);
      final universe = await _browseUniverse(policy);
      expect(universe.map((m) => m.wireCoin),
          _liveUniverse().map((m) => m.wireCoin),
          reason: 'the policy never filters the browse universe');
      expect(universe.where(isHlStockPerp), isNotEmpty);

      final stocks = hlBrowseListForTab(HlBrowseTab.tradfi, universe,
          sub: HlBrowseSub.stocks);
      expect(stocks.first.wireCoin, 'xyz:NVDA');
      for (final t in _bigTech) {
        expect(
            [
              for (final m in stocks)
                if (m.underlyingTicker == t) m.wireCoin
            ],
            ['xyz:$t'],
            reason: '$t lists once under Stocks, from xyz');
      }

      final trending = hlBrowseListForTab(HlBrowseTab.trending, universe);
      expect(trending.take(2).map((m) => m.wireCoin), ['BTC', 'xyz:NVDA']);
      expect(
          trending.where((m) => m.underlyingTicker == 'NVDA'), hasLength(1));
      expect(hlTrendingStrip(universe, trending).first.wireCoin, 'xyz:NVDA');

      for (final q in ['nvidia', 'nvda', 'nv', 'NVIDIA']) {
        final hits = await hlSearchMarkets(universe, q);
        expect(hits.first.wireCoin, 'xyz:NVDA', reason: q);
        expect(hits.first.isPerp, isTrue, reason: q);
        expect(hits.first.alternatives.map((a) => a.wireCoin),
            ['io:NVDA', '@702', '@1155'],
            reason: '"$q": the spot tokens under more ways');
        expect(hits.where((h) => h.groupTicker == 'NVDA'), hasLength(1),
            reason: '"$q" shows Nvidia once');
      }

      // Buying is what the policy decides, never what is listed.
      final xyz = universe.firstWhere((m) => m.wireCoin == 'xyz:NVDA');
      expect(
          hlStockGateAllows(xyz, policy), policy.allows('hyperliquid.stocks'));
    });
  }

  group('the xyz:NVDA ticket with stock perps refused for the region', () {
    final xyz = _liveUniverse().firstWhere((m) => m.wireCoin == 'xyz:NVDA');

    testWidgets(
        'opens shut: the region note with the VPN sentence, "Check '
        'connection" as its one button, never the order', (tester) async {
      final policy = _Policy({'hyperliquid.stocks': 'country_blocked'});
      RuntimeCapabilitiesService.debugInstance = policy;
      await _pump(
          tester,
          policy,
          HlOrderSlipSheet(market: xyz, initialIsLong: true, initialUsd: 50),
          mids: {xyz.coin: xyz.markPx});
      expect(_note, findsOneWidget);
      expect(_noteText(tester), contains('check your VPN settings'));
      expect(find.textContaining('use a VPN'), findsNothing);
      expect(barPrimaryLabel(tester), 'Check connection');

      // Still refused after asking again: the note stays, and the button
      // is never the order (no approval, no funding).
      await tapBarPrimary(tester, settle: false);
      await _frames(tester, 20);
      expect(_note, findsOneWidget);
      expect(barPrimaryLabel(tester), 'Check connection');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('switched off rather than by region: the button is disabled',
        (tester) async {
      final policy = _Policy({'hyperliquid.stocks': 'disabled'});
      RuntimeCapabilitiesService.debugInstance = policy;
      await _pump(
          tester,
          policy,
          HlOrderSlipSheet(market: xyz, initialIsLong: true, initialUsd: 50),
          mids: {xyz.coin: xyz.markPx});
      expect(_note, findsOneWidget);
      expect(barPrimaryLabel(tester), isNot('Check connection'));
      expect(barPrimaryEnabled(tester), isFalse);
      await tapBarPrimary(tester, settle: false);
      await _frames(tester);
      expect(_note, findsOneWidget);
      expect(barPrimaryEnabled(tester), isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a held Nvidia long cannot be added to', (tester) async {
      final policy = _Policy({'hyperliquid.stocks': 'country_blocked'});
      RuntimeCapabilitiesService.debugInstance = policy;
      await _pump(
          tester,
          policy,
          HlOrderSlipSheet(market: xyz, initialIsLong: true, initialUsd: 50),
          held: [_heldNvidia(xyz)],
          mids: {xyz.coin: xyz.markPx});
      expect(_note, findsOneWidget);
      expect(barPrimaryLabel(tester), 'Check connection');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('reducing a held Nvidia long stays open', (tester) async {
      final policy = _Policy(_ukRefused);
      RuntimeCapabilitiesService.debugInstance = policy;
      await _pump(
          tester,
          policy,
          // Short $50 against a long of two shares: a reduce.
          HlOrderSlipSheet(market: xyz, initialIsLong: false, initialUsd: 50),
          held: [_heldNvidia(xyz)],
          mids: {xyz.coin: xyz.markPx});
      expect(_note, findsNothing);
      expect(barPrimaryLabel(tester), isNot('Check connection'));
      expect(barPrimaryEnabled(tester), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('closing a held Nvidia long stays open', (tester) async {
      final policy = _Policy(_ukRefused);
      RuntimeCapabilitiesService.debugInstance = policy;
      final held = _heldNvidia(xyz);
      await _pump(
          tester, policy, HlClosePositionSheet(position: held, market: xyz),
          held: [held], mids: {xyz.coin: xyz.markPx});
      await tester.tap(find.bySemanticsLabel('Use maximum'));
      await _frames(tester, 6);
      expect(_note, findsNothing);
      expect(barPrimaryLabel(tester), 'Close 100% now');
      expect(barPrimaryEnabled(tester), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('trading refused for the region: every buy shut, lists unchanged',
      () {
    final universe = _liveUniverse();
    final buys = {
      'a crypto perp (BTC)': universe.firstWhere((m) => m.wireCoin == 'BTC'),
      'a stock perp (xyz:NVDA)':
          universe.firstWhere((m) => m.wireCoin == 'xyz:NVDA'),
      'a stock token (NVDAX)':
          universe.firstWhere((m) => m.wireCoin == '@702'),
    };
    for (final MapEntry(key: name, value: market) in buys.entries) {
      testWidgets('$name: the ticket opens shut under the region note',
          (tester) async {
        final policy = _Policy({'hyperliquid.trade': 'country_blocked'});
        RuntimeCapabilitiesService.debugInstance = policy;
        await _pump(
            tester,
            policy,
            HlOrderSlipSheet(
                market: market, initialIsLong: true, initialUsd: 50),
            mids: {market.coin: market.markPx});
        expect(_note, findsOneWidget);
        expect(_noteText(tester), contains('check your VPN settings'));
        expect(barPrimaryLabel(tester), 'Check connection');
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  });

  testWidgets(
      'the policy unreadable: xyz:NVDA is listed and its ticket opens shut',
      (tester) async {
    final policy = _Policy({
      'hyperliquid.stocks': 'policy_unavailable',
      'hyperliquid.trade': 'policy_unavailable',
    });
    RuntimeCapabilitiesService.debugInstance = policy;
    final xyz = _liveUniverse().firstWhere((m) => m.wireCoin == 'xyz:NVDA');
    await _pump(
        tester,
        policy,
        HlOrderSlipSheet(market: xyz, initialIsLong: true, initialUsd: 50),
        mids: {xyz.coin: xyz.markPx});
    expect(_note, findsOneWidget);
    expect(barPrimaryLabel(tester), isNot('Check connection'));
    expect(barPrimaryEnabled(tester), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
