import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart'
    show Tag, polymarketParentTagsProvider;
import 'package:kute/providers/polymarket_provider.dart'
    show CryptoPredictNotifier, CryptoPredictState, cryptoPredictProvider;

/// The 5 Minute Markets banner hides itself when its round cannot load,
/// which also keeps its live feeds, countdown timers and pulsing indicator
/// out of the test.
class _OfflineCryptoPredict extends CryptoPredictNotifier {
  @override
  Future<CryptoPredictState> build(String arg) async =>
      throw StateError('offline test venue');
}

/// Empty venue catalogues for widget tests that mount a Ledger venue tab,
/// its portfolio or its dock. Those screens browse Hyperliquid markets,
/// Polymarket tags and the live 5 Minute Markets round; without these the
/// test would reach the network (every request answers 400 under the test
/// binding) and never settle, instead of exercising the code under test.
final offlineVenueOverrides = <Override>[
  hyperliquidPerpMarketsProvider.overrideWith((_) async => const <HlMarket>[]),
  hyperliquidPerpCoreMarketsProvider
      .overrideWith((_) async => const <HlMarket>[]),
  hyperliquidSpotMarketsProvider.overrideWith((_) async => const <HlMarket>[]),
  hyperliquidSpotTickersProvider.overrideWith((_) async => (
        tickers: const <String, HyperliquidTicker>{},
        pairNameByToken: const <String, String>{},
      )),
  polymarketParentTagsProvider
      .overrideWith((_) => Stream.value(const <Tag>[])),
  cryptoPredictProvider.overrideWith(_OfflineCryptoPredict.new),
];
