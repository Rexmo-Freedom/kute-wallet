// Swap order store.
//
// `swapOrdersProvider` is the provider-neutral store of every
// exchange-style order the app tracks: Orchestra swaps, Cash App
// purchases, and read-only history from retired providers (see
// `SwapOrder.isRetiredProvider`). It persists in the
// `kSwapOrdersBoxName` Hive box.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/swap_order_model.dart';

final swapOrdersProvider = StateNotifierProvider<SwapOrdersNotifier, List<SwapOrder>>((ref) {
  return SwapOrdersNotifier();
});

class TopCoin {
  final String code;
  final String name;
  final String svgAsset;
  const TopCoin(this.code, this.name, this.svgAsset);
}

const kTopCoins = <TopCoin>[
  TopCoin('L-BTC', 'Liquid Bitcoin', 'lib/assets/liquid-btc.svg'),
  TopCoin('ETH',  'Ethereum',       'lib/assets/eth.svg'),
  TopCoin('USDT', 'Tether',         'lib/assets/usdt.svg'),
  TopCoin('USDC', 'USD Coin',       'lib/assets/usdc.svg'),
  TopCoin('BNB',  'BNB',            'lib/assets/bnb.svg'),
  TopCoin('SOL',  'Solana',         'lib/assets/sol.svg'),
  TopCoin('XRP',  'XRP',            'lib/assets/xrp-xrp-logo.svg'),
  TopCoin('TRX',  'TRON',           'lib/assets/trx.svg'),
  TopCoin('LTC',  'Litecoin',       'lib/assets/litecoin-ltc-logo.svg'),
  TopCoin('ADA',  'Cardano',        'lib/assets/cardano-ada-logo.svg'),
  TopCoin('DOT',  'Polkadot',       'lib/assets/polkadot-new-dot-logo.svg'),
  TopCoin('NEAR', 'NEAR Protocol',  'lib/assets/near-protocol-near-logo.svg'),
  TopCoin('POL',  'Polygon',        'lib/assets/pol.svg'),
  TopCoin('SUI',  'Sui',            'lib/assets/sui-sui-logo.svg'),
];
