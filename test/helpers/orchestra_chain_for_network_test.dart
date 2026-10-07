import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/orchestra_chain_for_network.dart';
import 'package:kute/helpers/orchestra_router.dart';
import 'package:kute/models/orchestra_routes_model.dart';

OrchestraRouteAsset _asset(String chain, String asset, int decimals) =>
    OrchestraRouteAsset(
      id: '$chain:$asset',
      chain: chain,
      asset: asset,
      displayName: asset,
      displaySymbol: asset,
      decimals: decimals,
      chainDisplayName: chain,
      to: const OrchestraRouteSet.none(),
      exactOutTo: const OrchestraRouteSet.none(),
      fixedTo: const OrchestraRouteSet.none(),
    );

void main() {
  group('orchestraChainForNetwork', () {
    const table = {
      'SPARK': 'spark',
      'spark': 'spark',
      'POLYGON': 'polygon',
      'MATIC': 'polygon',
      'HYPERCORE': 'hypercore',
      'HYPERLIQUID': 'hypercore',
      'ARBITRUM': 'arbitrum',
      'arbitrum': 'arbitrum',
      'ARB': 'arbitrum',
      'LIGHTNING': 'lightning',
      'BITCOIN': 'bitcoin',
      'BASE': 'base',
      'ETH': 'ethereum',
      'SOL': 'solana',
      'BSC': 'bsc',
    };
    table.forEach((network, chain) {
      test('$network is $chain', () {
        expect(orchestraChainForNetwork(network), chain);
      });
    });

    test('ambiguous or unknown networks name no chain', () {
      expect(orchestraChainForNetwork('BTC'), isNull);
      expect(orchestraChainForNetwork(''), isNull);
      expect(orchestraChainForNetwork('TON'), isNull);
    });
  });

  group('row amounts without a catalog', () {
    test('Polygon USDC.e 1000000 parses to 1.0', () {
      expect(
          orchestraRowAmountToDouble('1000000', 'USDC.e', network: 'POLYGON'),
          1.0);
    });

    test('Spark BTC 100000000 parses to 1.0', () {
      expect(orchestraRowAmountToDouble('100000000', 'BTC', network: 'SPARK'),
          1.0);
    });

    test('receipt text keeps sub-eight-decimal amounts and order chain', () {
      expect(
          orchestraRowAmountToDecimalString('1', 'USDC',
              network: 'SPARK', orderChain: 'bsc'),
          '0.000000000000000001');
      expect(
          orchestraRowAmountToDecimalString('290000000', 'USDC',
              network: 'HYPERLIQUID'),
          '2.9');
    });
  });

  group('row amounts with the live catalog', () {
    setUpAll(() {
      setOrchestraDecimalsCatalog(OrchestraRoutesCatalog(
        assets: [
          _asset('spark', 'BTC', 8),
          _asset('hypercore', 'USDC', 8),
          _asset('polygon', 'USDC.e', 6),
          _asset('bsc', 'USDC', 18),
          _asset('arbitrum', 'USDC', 6),
        ],
        fetchedAt: DateTime.now(),
        source: OrchestraCatalogSource.live,
      ));
    });

    test('HyperCore USDC amountOut 100000000 parses to 1.0', () {
      expect(
          orchestraRowAmountToDouble('100000000', 'USDC', network: 'HYPERCORE'),
          1.0);
    });

    test('without the chain the ticker would read HyperCore USDC as 100', () {
      expect(orchestraAmountToDouble('100000000', 'USDC'), 100.0);
    });

    test('Polygon USDC.e 1000000 parses to 1.0', () {
      expect(
          orchestraRowAmountToDouble('1000000', 'USDC.e', network: 'POLYGON'),
          1.0);
    });

    test('the order chain is used when the row network names none', () {
      expect(
          orchestraRowAmountToDouble('100000000', 'USDC',
              network: 'BTC', orderChain: 'hypercore'),
          1.0);
    });

    test('a known order chain wins over the row network', () {
      expect(
          orchestraRowAmountToDouble('1000000', 'USDC',
              network: 'HYPERLIQUID', orderChain: 'arbitrum'),
          1.0);
      expect(
          orchestraRowAmountToDouble('100000000', 'USDC',
              network: 'ARBITRUM', orderChain: 'hypercore'),
          1.0);
    });

    test('an unknown or empty order chain falls back to the row network', () {
      expect(
          orchestraRowAmountToDouble('100000000', 'USDC',
              network: 'HYPERCORE', orderChain: 'somechain'),
          1.0);
      expect(
          orchestraRowAmountToDouble('100000000', 'USDC',
              network: 'HYPERCORE', orderChain: ''),
          1.0);
    });
  });
}
