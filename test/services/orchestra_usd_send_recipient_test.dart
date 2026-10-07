// The dollar send's recipient recognition: what a pasted or scanned
// value means against the routes the dollar balance can reach.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/scanned_address.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/services/orchestra_usd_send_routes.dart';

const _spark =
    'sp1pgssy7d7vel0nh9m4326qc54e6rskpczn07dktww9rv4nu5ptvt0s9ucez8h3s';
const _evm = '0xAac5482758cD28C38090Dcc2f0A08f09C0F814B2';
const _usdcContract = '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913';
const _tron = 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t';
const _btc = 'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4';
const _sol = '7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU';

UsdSendDestination _d(String chain, String asset) => UsdSendDestination(
      assetCode: asset,
      displayName: asset,
      displaySymbol: asset,
      chain: chain,
      chainDisplayName: chain,
      decimals: 6,
    );

final _table = [
  _d('arbitrum', 'USDC'),
  _d('arbitrum', 'USDT'),
  _d('base', 'ETH'),
  _d('base', 'USDC'),
  _d('bitcoin', 'BTC'),
  _d('ethereum', 'USDC'),
  _d('solana', 'SOL'),
  _d('solana', 'USDC'),
  _d('tron', 'USDT'),
];

List<String> _ids(UsdRecipientMatch m) => [for (final d in m.candidates) d.id];

Map<String, dynamic> _row(String chain, String asset, {int decimals = 6}) => {
      'id': '$chain:$asset',
      'chain': chain,
      'asset': asset,
      'decimals': decimals,
      'route': {'to': 'all', 'fixedTo': [], 'exactOutTo': []},
    };

void main() {
  group('matchUsdRecipient', () {
    test('a Spark address is recognised but no dollar route takes it', () {
      for (final raw in [_spark, 'spark:$_spark?amount=5']) {
        final m = matchUsdRecipient(raw, _table);
        expect(m.family, 'spark');
        expect(m.recognised, isTrue);
        expect(m.candidates, isEmpty);
        expect(m.autoPick, isNull);
      }
    });

    test('the dollar send table offers nothing on Spark', () {
      final catalog = OrchestraRoutesCatalog.fromJson(
        {
          'assets': [
            _row('spark', 'BTC', decimals: 8),
            _row('spark', 'USDB'),
            _row('arbitrum', 'USDC'),
          ],
        },
        source: OrchestraCatalogSource.live,
        fetchedAt: DateTime(2026, 10, 1),
      );
      final ids = usdSendDestinations(catalog).map((d) => d.id).toList();
      expect(ids, ['arbitrum:USDC']);
      expect(usdSendDefaultDestination(usdSendDestinations(catalog))?.id,
          'arbitrum:USDC');
    });

    test('a bare EVM address reaches every EVM row', () {
      final m = matchUsdRecipient(_evm, _table);
      expect(m.family, 'evm');
      expect(_ids(m), [
        'arbitrum:USDC',
        'arbitrum:USDT',
        'base:ETH',
        'base:USDC',
        'ethereum:USDC',
      ]);
      // Several chains: the screen lands it on the default instead.
      expect(m.autoPick, isNull);
      expect(m.accepts(usdSendDefaultDestination(_table)!), isTrue);
    });

    test('ethereum:…@chainId narrows to its chain and picks its dollar coin',
        () {
      final base = matchUsdRecipient('ethereum:$_evm@8453', _table);
      expect(base.address, _evm);
      expect(base.chainId, 8453);
      expect(_ids(base), ['base:ETH', 'base:USDC']);
      expect(base.autoPick?.id, 'base:USDC');
      // The default does not fit a request naming another chain.
      expect(base.accepts(usdSendDefaultDestination(_table)!), isFalse);

      final arb = matchUsdRecipient('ethereum:$_evm@0xa4b1', _table);
      expect(arb.autoPick?.id, 'arbitrum:USDC');

      // An ERC-20 transfer request pays its address param on its chain.
      final transfer = matchUsdRecipient(
          'ethereum:$_usdcContract@1/transfer?address=$_evm&uint256=1e6', _table);
      expect(transfer.address, _evm);
      expect(_ids(transfer), ['ethereum:USDC']);
    });

    test('a chain id the app cannot route to matches nothing', () {
      final m = matchUsdRecipient('ethereum:$_evm@424242', _table);
      expect(m.recognised, isTrue);
      expect(m.candidates, isEmpty);
    });

    test('Tron, Solana and bitcoin pick their own routes', () {
      final tron = matchUsdRecipient(_tron, _table);
      expect(tron.family, 'tron');
      expect(tron.autoPick?.id, 'tron:USDT');

      final sol = matchUsdRecipient('solana:$_sol?amount=1', _table);
      expect(sol.family, 'solana');
      expect(_ids(sol), ['solana:SOL', 'solana:USDC']);
      expect(sol.autoPick?.id, 'solana:USDC');

      final btc = matchUsdRecipient('bitcoin:$_btc?amount=0.1', _table);
      expect(btc.address, _btc);
      expect(btc.autoPick?.id, 'bitcoin:BTC');
    });

    test('Lightning recipients and noise are not recognised', () {
      for (final raw in [
        'alice@getalby.com',
        'lnbc1pvjluezpp5qqqsyqcyq5rqwzqfqqqsyqcyq5rqwz',
        'hello',
      ]) {
        final m = matchUsdRecipient(raw, _table);
        expect(m.recognised, isFalse, reason: raw);
        expect(m.candidates, isEmpty, reason: raw);
      }
    });

    test('only routes the dollar table offers can match', () {
      final m = matchUsdRecipient(_tron, [_d('base', 'USDC')]);
      expect(m.recognised, isTrue);
      expect(m.candidates, isEmpty);
    });

    test('no default without the Arbitrum USDC route', () {
      expect(usdSendDefaultDestination([_d('base', 'USDC')]), isNull);
      expect(usdSendDefaultDestination([_d('arbitrum', 'USDT')]), isNull);
    });

    test('a destination accepts only its own family and named chain', () {
      expect(usdSendDestinationAccepts(_d('base', 'USDC'), _evm), isTrue);
      expect(usdSendDestinationAccepts(_d('base', 'USDC'), _evm, chainId: 1),
          isFalse);
      expect(usdSendDestinationAccepts(_d('tron', 'USDT'), _spark), isFalse);
    });
  });

  group('evmPaymentChainId', () {
    test('reads decimal and hex chain ids', () {
      expect(evmPaymentChainId('ethereum:$_evm@8453'), 8453);
      expect(evmPaymentChainId('ethereum:pay-$_evm@0x2105?value=1'), 8453);
      expect(evmPaymentChainId('ETHEREUM:$_evm@1/transfer?address=$_evm'), 1);
    });

    test('no chain id, or not an ethereum request', () {
      expect(evmPaymentChainId(_evm), isNull);
      expect(evmPaymentChainId('ethereum:$_evm'), isNull);
      expect(evmPaymentChainId('spark:$_spark'), isNull);
      expect(evmPaymentChainId('alice@getalby.com'), isNull);
    });

    test('every known chain id maps to a sendable EVM slug', () {
      for (final slug in kEvmChainIdSlugs.values) {
        expect(usdSendChainAcceptsAddress(slug, _evm), isTrue, reason: slug);
      }
    });
  });
}
