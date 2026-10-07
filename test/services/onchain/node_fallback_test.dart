import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/onchain/esplora_fallback.dart';
import 'package:kute/services/onchain/native_onchain_service.dart';

void main() {
  test('an empty node setting opens Blockstream Electrum', () {
    final main = OnchainEndpoint.fromStored('');
    expect(main.kind, 'electrum');
    expect(main.url, 'ssl://electrum.blockstream.info:50002');
    final test = OnchainEndpoint.fromStored('', testnet: true);
    expect(test.url, 'ssl://electrum.blockstream.info:60002');
  });

  test('a preset host stands in for the next one; a custom node has none',
      () {
    expect(EsploraFallback.alternate(OnchainEndpoint.defaultMainnet),
        'electrum.bullbitcoin.com:50002');
    expect(EsploraFallback.alternate('ssl://electrum.hodlister.co:50002'),
        'https://mempool.space/api');
    expect(EsploraFallback.alternate('https://blockstream.info/api'),
        OnchainEndpoint.defaultMainnet);
    expect(EsploraFallback.alternate('my.node.local:50002'), isNull);
  });

  test('only a network failure moves the host; a timeout keeps it', () {
    expect(EsploraFallback.isNetworkFailure('network'), isTrue);
    expect(EsploraFallback.isNetworkFailure('timeout'), isFalse);
    final fallback = EsploraFallback.instance..resetForTest();
    fallback.markNetworkFailure(OnchainEndpoint.defaultMainnet);
    expect(fallback.effectiveUrl(OnchainEndpoint.defaultMainnet),
        'electrum.bullbitcoin.com:50002');
    fallback.resetForTest();
  });
}
