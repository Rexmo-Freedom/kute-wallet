import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/services/orchestra_usd_send_routes.dart';

Map<String, dynamic> _row(String chain, String asset,
        {int decimals = 18, String? contract = '0xabc'}) =>
    {
      'id': '$chain:$asset',
      'chain': chain,
      'asset': asset,
      'decimals': decimals,
      if (contract != null) 'contractAddress': contract,
      'route': {'to': 'all', 'fixedTo': [], 'exactOutTo': []},
    };

OrchestraRoutesCatalog _catalog() => OrchestraRoutesCatalog.fromJson(
      {
        'assets': [
          _row('spark', 'BTC', decimals: 8, contract: null),
          _row('spark', 'USDB', decimals: 6),
          _row('robinhood', 'ETH', contract: null),
          _row('robinhood', 'USDG', decimals: 6),
          _row('robinhood', 'HOOD'),
          // The long tail the founder asked to drop.
          _row('robinhood', 'CASHCAT'),
          _row('robinhood', 'PIPEDOG'),
          _row('robinhood', 'NVDA'),
          _row('robinhood', 'TSLA'),
          _row('robinhood', 'SomeNewMeme'),
          // Other chains are untouched.
          _row('base', 'USDC', decimals: 6),
          _row('base', 'AAPL'),
        ],
      },
      source: OrchestraCatalogSource.live,
      fetchedAt: DateTime(2026, 9, 30),
    );

void main() {
  const kept = {'ETH', 'USDG', 'HOOD'};

  test('Robinhood Chain keeps only its core assets in the catalog', () {
    final robinhood = _catalog()
        .assets
        .where((a) => a.chain == 'robinhood')
        .map((a) => a.asset)
        .toSet();
    expect(robinhood, kept);
    expect(orchestraAssetOffered('robinhood', 'usdc'), isTrue);
    expect(orchestraAssetOffered('Robinhood', 'CASHCAT'), isFalse);
    expect(orchestraAssetOffered('base', 'AAPL'), isTrue);
  });

  test('no dropped Robinhood Chain token reaches a user-facing list', () {
    final catalog = _catalog();
    Iterable<String> robinhood(Iterable<({String chain, String asset})> rows) =>
        rows.where((r) => r.chain == 'robinhood').map((r) => r.asset);

    for (final destination in ['BTC', 'USDB']) {
      final rows = catalog.receiveOptions(
          destinationChain: 'spark', destinationAsset: destination);
      expect(
          robinhood(rows.map((o) => (chain: o.chain, asset: o.assetCode)))
              .every(kept.contains),
          isTrue,
          reason: 'receive into $destination');
    }
    final sends = usdSendDestinations(catalog);
    expect(
        robinhood(sends.map((d) => (chain: d.chain, asset: d.assetCode)))
            .every(kept.contains),
        isTrue);
    for (final dropped in ['CASHCAT', 'PIPEDOG', 'NVDA', 'TSLA']) {
      expect(catalog.sendChainsFor(dropped), isEmpty, reason: dropped);
      expect(catalog.receiveChainsFor(dropped), isEmpty, reason: dropped);
      expect(catalog.find('robinhood', dropped), isNull, reason: dropped);
    }
    // A tokenized stock elsewhere is not this chain's business.
    expect(catalog.find('base', 'AAPL'), isNotNull);
  });

  test('a hand-built catalog is filtered the same way', () {
    final catalog = OrchestraRoutesCatalog(
      assets: _catalog().assets.toList()
        ..add(OrchestraRouteAsset.fromJson(_row('robinhood', 'WEN'))),
      fetchedAt: null,
      source: OrchestraCatalogSource.cached,
    );
    expect(catalog.find('robinhood', 'WEN'), isNull);
  });

  test('artwork for the dropped Robinhood tokens is gone', () {
    for (final symbol in [
      'CASHCAT',
      'PIPEDOG',
      'PONS',
      'UP',
      'IF',
      'STONKBROKER',
      'TENDIES',
      'WEN',
      'AI',
      'BONER',
      'DELTA',
      'NVDA',
      'SPCX',
      'TSLA',
      'AAPL',
    ]) {
      expect(orchestraAssetIconUrl(symbol), isNull, reason: symbol);
    }
    expect(orchestraAssetIconUrl('USDG'), isNotNull);
    expect(orchestraAssetIconUrl('ETH'), isNotNull);
  });
}
