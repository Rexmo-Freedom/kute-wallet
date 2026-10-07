// Parser + query tests for the live Flashnet route catalog
// (lib/models/orchestra_routes_model.dart) against a fixture of the
// GET /v2/orchestration/routes response shape: an `assets` array whose
// entries carry a `route` object with `to` / `exactOutTo` / `fixedTo`
// destination sets encoded as "all", an id list, or {"except": [...]}.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/orchestra_routes_model.dart';

const String kRoutesFixture = '''
{
  "assets": [
    {
      "id": "spark:BTC",
      "chain": "spark",
      "asset": "BTC",
      "assetDisplayName": "Bitcoin",
      "assetDisplaySymbol": "BTC",
      "contractAddress": null,
      "decimals": 8,
      "chainId": null,
      "chainDisplayName": "Spark",
      "chainIcon": "/chain-spark.svg",
      "route": {
        "to": {"except": ["bitcoin:BTC"]},
        "exactOutTo": ["tron:USDT"],
        "fixedTo": []
      }
    },
    {
      "id": "bitcoin:BTC",
      "chain": "bitcoin",
      "asset": "BTC",
      "assetDisplayName": "Bitcoin",
      "assetDisplaySymbol": "BTC",
      "decimals": 8,
      "chainDisplayName": "Bitcoin",
      "route": {"to": [], "exactOutTo": [], "fixedTo": []}
    },
    {
      "id": "tron:USDT",
      "chain": "tron",
      "asset": "USDT",
      "assetDisplayName": "Tether USD",
      "assetDisplaySymbol": "USDT",
      "contractAddress": "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t",
      "decimals": 6,
      "chainDisplayName": "Tron",
      "chainIcon": "/chain-tron.svg",
      "route": {"to": ["spark:BTC"], "exactOutTo": [], "fixedTo": []}
    },
    {
      "id": "ethereum:USDC",
      "chain": "ethereum",
      "asset": "USDC",
      "assetDisplayName": "USD Coin",
      "assetDisplaySymbol": "USDC",
      "decimals": 6,
      "chainDisplayName": "Ethereum",
      "route": {"to": "all", "exactOutTo": [], "fixedTo": []}
    },
    {
      "id": "polygon:USDC.e",
      "chain": "polygon",
      "asset": "USDC.e",
      "assetDisplayName": "Bridged USDC",
      "assetDisplaySymbol": "USDC.e",
      "decimals": 6,
      "chainDisplayName": "Polygon",
      "route": {"to": ["spark:BTC"], "exactOutTo": [], "fixedTo": []}
    },
    {
      "id": "ton:USDT",
      "chain": "ton",
      "asset": "USDT",
      "assetDisplayName": "Tether USD",
      "assetDisplaySymbol": "USDT",
      "decimals": 6,
      "chainDisplayName": "TON",
      "chainIcon": "https://cdn.example.com/ton.png",
      "route": {"to": ["spark:BTC"], "exactOutTo": [], "fixedTo": []}
    },
    {
      "id": "base:WETH",
      "chain": "base",
      "asset": "WETH",
      "assetDisplayName": "Wrapped Ether",
      "assetDisplaySymbol": "WETH",
      "decimals": 18,
      "chainDisplayName": "Base",
      "chainIcon": "/chain-base.svg",
      "route": {"to": ["ethereum:USDC"], "exactOutTo": [], "fixedTo": []}
    }
  ]
}
''';

OrchestraRoutesCatalog parseFixture() => OrchestraRoutesCatalog.fromJson(
      jsonDecode(kRoutesFixture) as Map<String, dynamic>,
      source: OrchestraCatalogSource.live,
      fetchedAt: DateTime(2026, 9, 14),
    );

void main() {
  group('OrchestraRouteSet', () {
    test('parses "all" and excludes self', () {
      final set = OrchestraRouteSet.fromJson('all');
      expect(set.contains('tron:USDT'), isTrue);
      expect(set.contains('spark:BTC', selfId: 'spark:BTC'), isFalse);
      expect(set.isEmpty, isFalse);
    });

    test('parses id lists', () {
      final set = OrchestraRouteSet.fromJson(['spark:BTC']);
      expect(set.contains('spark:BTC'), isTrue);
      expect(set.contains('tron:USDT'), isFalse);
    });

    test('parses except objects', () {
      final set = OrchestraRouteSet.fromJson({
        'except': ['bitcoin:BTC']
      });
      expect(set.contains('bitcoin:BTC'), isFalse);
      expect(set.contains('tron:USDT'), isTrue);
    });

    test('malformed input parses as empty', () {
      expect(OrchestraRouteSet.fromJson(42).isEmpty, isTrue);
      expect(OrchestraRouteSet.fromJson(null).isEmpty, isTrue);
      expect(OrchestraRouteSet.fromJson({'weird': true}).isEmpty, isTrue);
    });
  });

  group('OrchestraRoutesCatalog.fromJson', () {
    test('parses assets with typed fields', () {
      final catalog = parseFixture();
      expect(catalog.assets, hasLength(7));
      expect(catalog.hasLiveData, isTrue);
      expect(catalog.source, OrchestraCatalogSource.live);

      final usdt =
          catalog.assets.firstWhere((a) => a.id == 'tron:USDT');
      expect(usdt.chain, 'tron');
      expect(usdt.asset, 'USDT');
      expect(usdt.decimals, 6);
      expect(usdt.displaySymbol, 'USDT');
      expect(usdt.contractAddress, isNotNull);
      expect(usdt.to.contains('spark:BTC'), isTrue);

      expect(catalog.sparkBtc?.id, 'spark:BTC');
      expect(catalog.sparkBtc?.exactOutTo.contains('tron:USDT'), isTrue);
      expect(catalog.sparkBtc?.fixedTo.isEmpty, isTrue);
    });

    test('chainIcon resolves to a fetchable URL', () {
      final catalog = parseFixture();
      final usdt = catalog.assets.firstWhere((a) => a.id == 'tron:USDT');
      // Relative catalog paths resolve against the Orchestra web host.
      expect(usdt.chainIcon, '/chain-tron.svg');
      expect(usdt.chainIconUrl,
          'https://orchestra.flashnet.xyz/chain-tron.svg');
      // Absolute URLs pass through untouched.
      final ton = catalog.assets.firstWhere((a) => a.id == 'ton:USDT');
      expect(ton.chainIconUrl, 'https://cdn.example.com/ton.png');
      // Rows without artwork stay null (no lettered-disc URL invented).
      final eth =
          catalog.assets.firstWhere((a) => a.id == 'ethereum:USDC');
      expect(eth.chainIcon, isNull);
      expect(eth.chainIconUrl, isNull);
    });

    test('tolerates a payload with no assets', () {
      final catalog = OrchestraRoutesCatalog.fromJson(
        const {'assets': null},
        source: OrchestraCatalogSource.live,
      );
      expect(catalog.assets, isEmpty);
      expect(catalog.hasLiveData, isFalse);
    });
  });

  group('live route queries', () {
    test('send direction reads the Spark-BTC destination set', () {
      final catalog = parseFixture();
      // spark:BTC routes to everything except bitcoin:BTC.
      expect(catalog.sendChainsFor('USDT'), {'tron', 'ton'});
      expect(catalog.sendChainsFor('USDC'), {'ethereum', 'polygon'});
      expect(catalog.sendChainFor('USDT', 'TRON'), 'tron');
      expect(catalog.sendChainFor('USDT', 'liquid'), isNull);
    });

    test('receive direction reads each asset\'s reach to Spark BTC', () {
      final catalog = parseFixture();
      expect(catalog.receiveChainsFor('USDT'), {'tron', 'ton'});
      // ethereum:USDC says "all" (includes spark:BTC); polygon USDC.e
      // lists spark:BTC explicitly and folds into USDC.
      expect(catalog.receiveChainsFor('USDC'), {'ethereum', 'polygon'});
      expect(catalog.receiveChainsFor('usdc.e'), {'ethereum', 'polygon'});
    });

    test('supportsSwapAsset covers both directions, never BTC itself', () {
      final catalog = parseFixture();
      expect(catalog.supportsSwapAsset('USDT'), isTrue);
      expect(catalog.supportsSwapAsset('usdc'), isTrue);
      expect(catalog.supportsSwapAsset('USDC.e'), isTrue);
      // bitcoin:BTC is excluded from spark:BTC's send set and reaches
      // nothing itself.
      expect(catalog.supportsSwapAsset('BTC'), isFalse);
      expect(catalog.supportsSwapAsset('DOGE'), isFalse);
    });

    test('both tables clip, for different reasons', () {
      final catalog = parseFixture();
      // 'ton' is reachable per the live catalog. SEND clips because the
      // send flow can only validate EVM/Tron/XRP/Solana address
      // families; RECEIVE clips because TON has no reusable deposit
      // address for the accumulation rail to mint.
      expect(catalog.sendRouteTable['USDT'], {'tron'});
      expect(catalog.receiveRouteTable['USDT'], {'tron'});
      expect(catalog.sendRouteTable['USDC'], {'ethereum', 'polygon'});
      expect(catalog.sendRouteTable.containsKey('BTC'), isFalse);
    });

    test('receiveOptions lists every mintable receive pair, no native rails',
        () {
      final catalog = parseFixture();
      final options = catalog.receiveOptions();
      final ids = options.map((o) => '${o.chain}:${o.assetCode}').toSet();
      expect(ids, {
        'tron:USDT',
        'ethereum:USDC',
        'polygon:USDC.e',
        'ton:USDT',
      });
      // bitcoin:BTC is a native rail, never an Orchestra receive row.
      expect(ids.contains('bitcoin:BTC'), isFalse);
      // ton:USDT has no reusable deposit address, so the mint would
      // refuse it; it is offered only as a guarded one-time quote (TON
      // addresses are checksum-validated and the memo is displayed).
      final ton = options.firstWhere((o) => o.chain == 'ton');
      expect(ton.reusableAddress, isFalse);
      expect(
          options
              .where((o) => o.chain != 'ton')
              .every((o) => o.reusableAddress),
          isTrue);
      final bridged = options.firstWhere((o) => o.chain == 'polygon');
      expect(bridged.assetCode, 'USDC.e');
      expect(bridged.decimals, 6);
    });

    test(
        'DESTINATION LOCK: receiveOptions only offers pairs whose route '
        'reaches spark:BTC', () {
      final catalog = parseFixture();
      final options = catalog.receiveOptions();
      // base:WETH is on the catalog but routes only to ethereum:USDC —
      // it must never be offered as a receive row, because the flow's
      // sole destination is BTC on Spark.
      expect(options.any((o) => o.assetCode == 'WETH'), isFalse);
      final btcId = catalog.sparkBtc!.id;
      for (final o in options) {
        final row = catalog.assets
            .firstWhere((a) => a.id == '${o.chain}:${o.assetCode}');
        expect(row.to.contains(btcId, selfId: row.id), isTrue,
            reason: '${row.id} was offered but cannot reach spark:BTC');
      }
    });

    test('receiveOptions carries the chain artwork URL', () {
      final catalog = parseFixture();
      final options = catalog.receiveOptions();
      final tron = options.firstWhere((o) => o.chain == 'tron');
      expect(tron.chainIconUrl,
          'https://orchestra.flashnet.xyz/chain-tron.svg');
      // A row without `chainIcon` still resolves to the host's
      // conventional path so the picker never shows a lettered disc
      // for a chain the host has artwork for.
      final eth = options.firstWhere((o) => o.chain == 'ethereum');
      expect(eth.chainIconUrl,
          'https://orchestra.flashnet.xyz/chain-ethereum.svg');
    });

    test('receiveOptions falls back to the static tables', () {
      final catalog = OrchestraRoutesCatalog.fromStatic();
      final options = catalog.receiveOptions();
      expect(options, isNotEmpty);
      final usdtChains = options
          .where((o) => o.assetCode == 'USDT')
          .map((o) => o.chain)
          .toSet();
      expect(usdtChains,
          {'ethereum', 'arbitrum', 'optimism', 'tron', 'plasma'});
      expect(options.every((o) => o.decimals == 6), isTrue);
      // The static tables carry no artwork field, but every chain they
      // list resolves to the host's conventional path.
      for (final o in options) {
        expect(o.chainIconUrl,
            'https://orchestra.flashnet.xyz/chain-${o.chain}.svg');
      }
    });
  });

  group('static fallback', () {
    test('empty catalog answers from the static tables', () {
      final catalog = OrchestraRoutesCatalog.fromStatic();
      expect(catalog.hasLiveData, isFalse);
      expect(catalog.supportsSwapAsset('USDT'), isTrue);
      expect(catalog.supportsSwapAsset('USDC.E'), isTrue);
      expect(catalog.supportsSwapAsset('DOGE'), isFalse);
      // 'bsc' deliberately absent from the static tables: BSC-pegged
      // stables are 18-decimal, which the ticker fallback would
      // mis-scale; only the live catalog (with real decimals) offers it.
      expect(catalog.sendChainsFor('USDT'),
          {'arbitrum', 'optimism', 'tron', 'plasma'});
      expect(catalog.receiveChainsFor('USDC'),
          {'solana', 'base', 'ethereum', 'arbitrum', 'optimism', 'polygon'});
      expect(catalog.sendRouteTable, isEmpty);
    });

    test('catalog without a Spark BTC anchor falls back too', () {
      final catalog = OrchestraRoutesCatalog.fromJson(
        jsonDecode('''
        {"assets": [{
          "id": "tron:USDT", "chain": "tron", "asset": "USDT",
          "decimals": 6,
          "route": {"to": ["spark:BTC"], "exactOutTo": [], "fixedTo": []}
        }]}
        ''') as Map<String, dynamic>,
        source: OrchestraCatalogSource.live,
      );
      expect(catalog.hasLiveData, isFalse);
      expect(catalog.supportsSwapAsset('USDT'), isTrue);
      expect(catalog.sendChainsFor('USDT'),
          {'arbitrum', 'optimism', 'tron', 'plasma'});
    });
  });

  group('decimalsFor', () {
    test('reads per-asset decimals from live catalog rows', () {
      final catalog = parseFixture();
      expect(catalog.decimalsFor('tron', 'USDT'), 6);
      expect(catalog.decimalsFor('spark', 'BTC'), 8);
      // Normalized bridged variant matches its literal row.
      expect(catalog.decimalsFor('polygon', 'USDC.e'), 6);
      expect(catalog.decimalsFor('polygon', 'usdc'), 6);
    });

    test('chain matters: BSC-pegged USDC reads 18 from the catalog', () {
      final catalog = OrchestraRoutesCatalog.fromJson(
        jsonDecode('''
        {"assets": [
          {"id": "spark:BTC", "chain": "spark", "asset": "BTC",
           "decimals": 8,
           "route": {"to": "all", "exactOutTo": [], "fixedTo": []}},
          {"id": "bsc:USDC", "chain": "bsc", "asset": "USDC",
           "decimals": 18,
           "route": {"to": ["spark:BTC"], "exactOutTo": [], "fixedTo": []}}
        ]}
        ''') as Map<String, dynamic>,
        source: OrchestraCatalogSource.live,
      );
      expect(catalog.decimalsFor('bsc', 'USDC'), 18);
      // Unlisted (chain, asset) pairs fall back to the ticker table.
      expect(catalog.decimalsFor('polygon', 'USDC'), 6);
      expect(catalog.decimalsFor('polygon', 'DOGE'), 8);
    });

    test('static catalog answers from the ticker fallback', () {
      final catalog = OrchestraRoutesCatalog.fromStatic();
      expect(catalog.decimalsFor('tron', 'USDT'), 6);
      expect(catalog.decimalsFor('spark', 'BTC'), 8);
      expect(fallbackOrchestraAssetDecimals('usdc.e'), 6);
      expect(fallbackOrchestraAssetDecimals('ETH'), 18);
      expect(fallbackOrchestraAssetDecimals('UNKNOWN'), 8);
    });
  });
}
