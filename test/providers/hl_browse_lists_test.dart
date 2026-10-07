// The Investing browse lists: which markets each pill of the site's tree
// shows, the sub-pills inside one, and the order.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';

import '../helpers/runtime_policy_fixture.dart';

HlMarket _m(
  String coin, {
  String dex = '',
  HlMarketKind kind = HlMarketKind.perp,
  String category = 'crypto',
  double volume = 1000,
  String? wire,
  int assetId = 1,
}) =>
    HlMarket(
      coin: coin,
      wireCoin: wire ?? (dex.isEmpty ? coin : '$dex:$coin'),
      assetId: assetId,
      kind: kind,
      szDecimals: 2,
      maxLeverage: kind == HlMarketKind.spot ? 1 : 20,
      onlyIsolated: false,
      markPx: 10,
      midPx: 10,
      prevDayPx: 9,
      dayNtlVlm: volume,
      category: category,
      dex: dex,
      isHip3: dex.isNotEmpty,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => AffiliateService.debugSessionToken = 'test-session');
  tearDown(() => AffiliateService.debugSessionToken = null);

  final btc = _m('BTC', volume: 9000000);
  final hype = _m('HYPE', volume: 500000);
  final hypeSpot = _m('HYPE',
      kind: HlMarketKind.spot, wire: '@107', volume: 800000);
  final tslaXyz = _m('TSLA', dex: 'xyz', category: 'stocks', volume: 70000);
  final tslaFlx = _m('TSLA', dex: 'flx', category: 'stocks', volume: 300);
  final nvda = _m('NVDA', dex: 'km', category: 'stocks', volume: 40000);
  final spcxSpot = _m('SPCX',
      kind: HlMarketKind.spot, wire: '@590', category: 'stocks', volume: 20);
  final gold = _m('GOLD', dex: 'flx', category: 'commodities', volume: 5000);
  final eur = _m('EUR', dex: 'km', category: 'fx', volume: 10);
  final universe = [
    btc, hype, hypeSpot, tslaXyz, tslaFlx, nvda, spcxSpot, gold, eur //
  ];

  List<String> wires(List<HlMarket> l) => [for (final m in l) m.wireCoin];

  test('the pills are the site\'s, in its order, under its keys', () {
    expect([for (final t in HlBrowseTab.values) t.key], [
      'watchlist',
      'trending',
      'perps',
      'spot',
      'crypto',
      'tradfi',
      'pre_launch',
    ]);
  });

  test('Perps and Spot are the two kinds', () {
    // Most traded first. A thinly traded market still lists.
    expect(wires(hlBrowseListForTab(HlBrowseTab.perps, universe)), [
      'BTC', 'HYPE', 'xyz:TSLA', 'km:NVDA', 'flx:GOLD', 'flx:TSLA', 'km:EUR', //
    ]);
    expect(wires(hlBrowseListForTab(HlBrowseTab.spot, universe)),
        ['@107', '@590']);
    // Neither has a sub-row, nor do the rankings.
    expect(hlSubsForTab(HlBrowseTab.perps, universe), isEmpty);
    expect(hlSubsForTab(HlBrowseTab.spot, universe), isEmpty);
    expect(hlSubsForTab(HlBrowseTab.trending, universe), isEmpty);
    expect(hlSubsForTab(HlBrowseTab.prelaunch, universe), isEmpty);
  });

  test('Tradfi is the builder-dex perps of the venue\'s tradfi classes, then '
      'the spot tokens of those classes', () {
    final spcx = _m('SPCX', dex: 'xyz', category: 'preipo', volume: 60);
    final tenYear = _m('10Y', dex: 'para', category: 'rates');
    final sp500 = _m('SP500', dex: 'xyz', category: 'indices', volume: 50);
    final unclassified = _m('ODD', dex: 'abcd', category: 'other');
    final builderCrypto = _m('BTCD', dex: 'para', category: 'crypto');
    final all = [
      ...universe, spcx, tenYear, sp500, unclassified, builderCrypto //
    ];
    // The stock's spot token (@590) follows the perps.
    expect(wires(hlBrowseListForTab(HlBrowseTab.tradfi, all)), [
      'xyz:TSLA', 'km:NVDA', 'flx:GOLD', 'flx:TSLA', 'xyz:SPCX', 'xyz:SP500',
      'km:EUR', '@590', //
    ]);
    // The site's sub-pills, in its order, with no All; one with no market
    // is hidden.
    expect(hlSubsForTab(HlBrowseTab.tradfi, all), [
      HlBrowseSub.stocks,
      HlBrowseSub.indices,
      HlBrowseSub.commodities,
      HlBrowseSub.fx,
      HlBrowseSub.preipo,
    ]);
    expect(hlSubsForTab(HlBrowseTab.tradfi, universe), [
      HlBrowseSub.stocks,
      HlBrowseSub.commodities,
      HlBrowseSub.fx,
    ]);
    List<String> sub(HlBrowseSub s) =>
        wires(hlBrowseListForTab(HlBrowseTab.tradfi, all, sub: s));
    expect(sub(HlBrowseSub.stocks), ['xyz:TSLA', 'km:NVDA', 'flx:TSLA', '@590']);
    expect(sub(HlBrowseSub.indices), ['xyz:SP500']);
    expect(sub(HlBrowseSub.commodities), ['flx:GOLD']);
    expect(sub(HlBrowseSub.fx), ['km:EUR']);
    expect(sub(HlBrowseSub.preipo), ['xyz:SPCX']);
    // Rates, builder-dex crypto and unclassified builder coins are not
    // Tradfi or Crypto on the site: they list under Perps.
    for (final m in [tenYear, unclassified, builderCrypto]) {
      expect(hlMarketMatchesTab(m, HlBrowseTab.tradfi), isFalse);
      expect(hlMarketMatchesTab(m, HlBrowseTab.crypto), isFalse);
      expect(hlMarketMatchesTab(m, HlBrowseTab.perps), isTrue);
    }
    // The venue's own spellings are folded before any of this.
    expect(HlMarket.normalizeCategory('FX'), 'fx');
    expect(HlMarket.normalizeCategory('stock'), 'stocks');
  });

  test('Crypto is the main dex\'s perps, with the site\'s sectors', () {
    final eth = _m('ETH', volume: 4000000);
    final pump = _m('PUMP', volume: 700000);
    final wif = _m('WIF', volume: 100);
    // A token anyone deployed under a perp's name, with wash-like volume.
    final fakePump = _m('PUMP',
        kind: HlMarketKind.spot, wire: '@20', volume: 99000000);
    final ubtc = HlMarket(
      coin: 'UBTC',
      wireCoin: '@142',
      assetId: 10142,
      kind: HlMarketKind.spot,
      szDecimals: 5,
      maxLeverage: 1,
      onlyIsolated: false,
      markPx: 10,
      midPx: 10,
      prevDayPx: 9,
      dayNtlVlm: 300000,
      unitAssetName: 'Bitcoin',
    );
    final obscure = _m('WOW',
        kind: HlMarketKind.spot, wire: '@77', volume: 5000000);
    final all = [
      btc, eth, pump, wif, hype, hypeSpot, fakePump, ubtc, obscure, tslaXyz //
    ];

    // Perps only, most traded first: no spot token, no builder perp, and
    // no spot twin standing in for a perp.
    expect(wires(hlBrowseListForTab(HlBrowseTab.crypto, all)),
        ['BTC', 'ETH', 'PUMP', 'HYPE', 'WIF']);
    // Sectors with the majors' first and no All; one with no market is
    // hidden.
    expect(hlSubsForTab(HlBrowseTab.crypto, all), [
      HlBrowseSub.layer1,
      HlBrowseSub.defi,
      HlBrowseSub.meme,
    ]);
    // The row opens on its first pill when nothing in it is selected.
    expect(
        hlEffectiveSub(
            HlBrowseSub.all, hlSubsForTab(HlBrowseTab.crypto, all)),
        HlBrowseSub.layer1);
    expect(
        wires(hlBrowseListForTab(HlBrowseTab.crypto, all,
            sub: HlBrowseSub.layer1)),
        ['BTC', 'ETH', 'HYPE']);
    expect(
        wires(hlBrowseListForTab(HlBrowseTab.crypto, all,
            sub: HlBrowseSub.meme)),
        ['WIF']);

    // Spot: verified tokens lead whatever the others claim to trade.
    expect(wires(hlBrowseListForTab(HlBrowseTab.spot, all)),
        ['@107', '@142', '@20', '@77']);

    // A Unit token files under its asset.
    expect(hlSectorSymbol(ubtc), 'BTC');
    expect(HlMarket.hlUnitAssetName('UBTC', 'Unit Bitcoin'), 'Bitcoin');
    expect(HlMarket.hlUnitAssetName('USDH', 'USDH'), isNull);
    expect(HlMarket.hlUnitAssetName('HOP', 'Unit of hop'), isNull);
  });

  test('Pre-launch is the main dex\'s strictIsolated perps', () {
    HlMarket strict(String coin, {String dex = ''}) => HlMarket(
          coin: coin,
          wireCoin: dex.isEmpty ? coin : '$dex:$coin',
          assetId: 1,
          kind: HlMarketKind.perp,
          szDecimals: 2,
          maxLeverage: 3,
          onlyIsolated: true,
          marginMode: 'strictIsolated',
          markPx: 10,
          midPx: 10,
          prevDayPx: 9,
          dayNtlVlm: 10,
          dex: dex,
          isHip3: dex.isNotEmpty,
        );
    final pre = strict('NEWCOIN');
    final all = [
      ...universe, pre, strict('CASHCAT'), strict('GOLD', dex: 'xyz') //
    ];
    expect(wires(hlBrowseListForTab(HlBrowseTab.prelaunch, all)), ['NEWCOIN']);
    // It is still a main-dex perp: Crypto and Perps list it too.
    expect(hlMarketMatchesTab(pre, HlBrowseTab.crypto), isTrue);
    // None today: the pill has no market and is hidden.
    expect(hlBrowseListForTab(HlBrowseTab.prelaunch, universe), isEmpty);
  });

  test('Trending is the most traded, by volume, landing on what you own',
      () {
    final trending = wires(hlBrowseListForTab(HlBrowseTab.trending, universe));
    expect(trending.first, 'BTC');
    // HYPE's verified spot token stands in for its perp here, and only
    // here.
    expect(trending, contains('@107'));
    expect(trending, isNot(contains('HYPE')));
  });

  test(
      'the stock gate is what clears Tradfi of stock perps: closed, none '
      'is offered', () async {
    final open = runtimePolicyFixture();
    addTearDown(open.dispose);
    expect(await open.refresh(), isTrue);
    expect(
        wires(hlBrowseListForTab(HlBrowseTab.tradfi,
            hlMarketsOfferedUnderPolicy(universe, open),
            sub: HlBrowseSub.stocks)),
        ['xyz:TSLA', 'km:NVDA', 'flx:TSLA', '@590']);
    final blocked = runtimePolicyFixture(blocked: {'hyperliquid.stocks'});
    addTearDown(blocked.dispose);
    expect(await blocked.refresh(), isTrue);
    final offered = hlMarketsOfferedUnderPolicy(universe, blocked);
    // The stock's spot token is not a perp: it is what Stocks still lists,
    // and it stays under Spot too.
    expect(
        wires(hlBrowseListForTab(HlBrowseTab.tradfi, offered,
            sub: HlBrowseSub.stocks)),
        ['@590']);
    expect(wires(hlBrowseListForTab(HlBrowseTab.spot, offered)),
        ['@107', '@590']);
  });

  test('icon candidates: dex-qualified perp, spot token, default dex', () {
    expect(hlCoinIconCandidates('TSLA', 'xyz:TSLA', 'stocks'), [
      'https://app.hyperliquid.xyz/coins/xyz:TSLA.svg',
      'https://assets.parqet.com/logos/symbol/TSLA',
    ]);
    expect(hlCoinIconCandidates('KNTQ', '@334', 'crypto'), [
      'https://app.hyperliquid.xyz/coins/KNTQ_spot.svg',
      'https://app.hyperliquid.xyz/coins/KNTQ.svg',
      'https://app.hyperliquid.xyz/coins/KNTQ_USDC.svg',
    ]);
    expect(hlCoinIconCandidates('BTC', 'BTC', 'crypto'),
        ['https://app.hyperliquid.xyz/coins/BTC.svg']);
    expect(hlCoinIconCandidates('BTC', null, null),
        ['https://app.hyperliquid.xyz/coins/BTC.svg']);

    // A builder perp with no logo of its own borrows its twin's on another
    // dex, same category only.
    HlMarketDirectory.remember([
      _m('COPPER', dex: 'xyz', category: 'commodities'),
      _m('COPPER', dex: 'flx', category: 'commodities'),
      _m('STX', dex: 'para', category: 'stocks'),
      _m('STX'),
    ]);
    expect(HlMarketDirectory.builderSiblings('xyz:COPPER'), ['flx:COPPER']);
    expect(HlMarketDirectory.builderSiblings('para:STX'), isEmpty);
    expect(HlMarketDirectory.builderSiblings('STX'), isEmpty);
    expect(
        hlCoinIconCandidates('COPPER', 'xyz:COPPER', 'commodities',
            siblingWires: HlMarketDirectory.builderSiblings('xyz:COPPER')),
        [
          'https://app.hyperliquid.xyz/coins/xyz:COPPER.svg',
          'https://app.hyperliquid.xyz/coins/flx:COPPER.svg',
        ]);
  });

  test('a spot token with no logo shows the logo of its underlying', () {
    expect(hlIconUnderlying('XAUT0'), 'GOLD');
    expect(hlIconUnderlying('GLD'), 'GOLD');
    expect(hlIconUnderlying('PAXG'), 'GOLD');
    expect(hlIconUnderlying('SLV'), 'SILVER');
    expect(hlIconUnderlying('USPYX'), 'SP500');
    expect(hlIconUnderlying('QQQ'), 'XYZ100');
    // Not trackers: no underlying, and no accident of spelling.
    expect(hlIconUnderlying('HYPE'), isNull);
    expect(hlIconUnderlying('TSLA'), isNull);
    expect(hlIconUnderlying('GOLDEN'), isNull);

    HlMarketDirectory.remember([
      _m('GOLD', dex: 'xyz', category: 'commodities'),
      _m('GOLD', dex: 'flx', category: 'commodities'),
      _m('SILVER', dex: 'xyz', category: 'commodities'),
      _m('TSLA', dex: 'flx', category: 'stocks'),
      _m('TSLA', dex: 'xyz', category: 'stocks'),
      _m('STX', dex: 'para', category: 'stocks'),
    ]);
    // Gold trackers: their own names first, then the gold perp's logo.
    expect(hlIconSiblingWires('XAUT0', '@182', 'commodities'),
        ['xyz:GOLD', 'flx:GOLD']);
    expect(
        hlCoinIconCandidates('GLD', '@276', 'commodities',
            siblingWires: hlIconSiblingWires('GLD', '@276', 'commodities')),
        [
          'https://app.hyperliquid.xyz/coins/GLD_spot.svg',
          'https://app.hyperliquid.xyz/coins/GLD.svg',
          'https://app.hyperliquid.xyz/coins/GLD_USDC.svg',
          'https://app.hyperliquid.xyz/coins/xyz:GOLD.svg',
          'https://app.hyperliquid.xyz/coins/flx:GOLD.svg',
        ]);
    expect(hlIconSiblingWires('SLV', '@265', 'commodities'), ['xyz:SILVER']);
    // A tokenised stock: the stock perp of its own symbol, xyz first.
    expect(hlIconSiblingWires('TSLA', '@264', 'stocks'),
        ['xyz:TSLA', 'flx:TSLA']);
    // The crypto token STX never borrows the stock STX's logo.
    expect(hlIconSiblingWires('STX', '@999', 'crypto'), isEmpty);
    // A default-dex perp has nothing to borrow.
    expect(hlIconSiblingWires('BTC', 'BTC', 'crypto'), isEmpty);
    expect(hlIconSiblingWires('BTC', null, null), isEmpty);
  });
}
