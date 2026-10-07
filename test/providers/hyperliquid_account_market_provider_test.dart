import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';

HlMarket _market(String wire, HlMarketKind kind) => HlMarket(
    coin: 'TSLA',
    wireCoin: wire,
    assetId: kind == HlMarketKind.spot ? 10142 : 1001,
    kind: kind,
    szDecimals: 2,
    maxLeverage: 1,
    onlyIsolated: false,
    markPx: 100,
    midPx: 100,
    prevDayPx: 100,
    dayNtlVlm: 1000,
    category: 'stocks',
    iconUrl: 'https://example.com/$wire.svg');

void main() {
  test('wire identifiers keep spot and multiple builder perps distinct',
      () async {
    final xyz = _market('xyz:TSLA', HlMarketKind.perp);
    final unit = _market('unit:TSLA', HlMarketKind.perp);
    final spot = _market('@142', HlMarketKind.spot);
    final container = ProviderContainer(overrides: [
      hyperliquidPerpMarketsProvider.overrideWith((_) async => [xyz, unit]),
      hyperliquidSpotMarketsProvider.overrideWith((_) async => [spot]),
    ]);
    addTearDown(container.dispose);
    final subscriptions = [
      for (final coin in ['xyz:TSLA', 'unit:TSLA', '@142', 'TSLA'])
        container.listen(hyperliquidAccountMarketProvider(coin), (_, __) {}),
    ];
    addTearDown(() {
      for (final sub in subscriptions) {
        sub.close();
      }
    });
    await container.read(hyperliquidPerpMarketsProvider.future);
    await container.read(hyperliquidSpotMarketsProvider.future);
    expect(container.read(hyperliquidAccountMarketProvider('xyz:TSLA')),
        same(xyz));
    expect(container.read(hyperliquidAccountMarketProvider('unit:TSLA')),
        same(unit));
    expect(
        container.read(hyperliquidAccountMarketProvider('@142')), same(spot));
    expect(container.read(hyperliquidAccountMarketProvider('TSLA')), same(xyz));
    expect(container.read(hyperliquidAccountMarketProvider('missing')), isNull);
  });

  test('cancels resolve a market by its exact wire coin only', () async {
    final xyz = _market('xyz:TSLA', HlMarketKind.perp);
    final spot = _market('@142', HlMarketKind.spot);
    final purr = _market('PURR/USDC', HlMarketKind.spot);
    final container = ProviderContainer(overrides: [
      hyperliquidPerpMarketsProvider.overrideWith((_) async => [xyz]),
      hyperliquidSpotMarketsProvider.overrideWith((_) async => [spot, purr]),
    ]);
    addTearDown(container.dispose);
    final subscriptions = [
      for (final coin in ['xyz:TSLA', '@142', 'PURR/USDC', 'TSLA'])
        container.listen(hyperliquidWireMarketProvider(coin), (_, __) {}),
    ];
    addTearDown(() {
      for (final sub in subscriptions) {
        sub.close();
      }
    });
    await container.read(hyperliquidPerpMarketsProvider.future);
    await container.read(hyperliquidSpotMarketsProvider.future);
    // Spot orders come back as '@142' / 'PURR/USDC', not 'TSLA'.
    expect(container.read(hyperliquidWireMarketProvider('@142')), same(spot));
    expect(
        container.read(hyperliquidWireMarketProvider('PURR/USDC')), same(purr));
    expect(
        container.read(hyperliquidWireMarketProvider('xyz:TSLA')), same(xyz));
    // A display name is not a wire coin here: no guessing for a cancel.
    expect(container.read(hyperliquidWireMarketProvider('TSLA')), isNull);
    expect(hlDisplayCoin(spot, '@142'), 'TSLA');
    expect(hlDisplayCoin(null, 'xyz:TSLA'), 'TSLA');
  });
}
