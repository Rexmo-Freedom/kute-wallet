// lib/providers/hyperliquid_sparkline_provider.dart
//
// The Investing cards' sparkline series, served from the device cache
// (HlSparklineStore, hl_sparkline_cache.dart) and refreshed at most once
// per coin per UTC day. A card watches [hyperliquidSparklineProvider]
// with its WIRE coin (perp: the coin, HIP-3: 'dex:COIN', spot: '@N' or
// the canonical pair name), which is what candleSnapshot expects.
//
// Only the browse cards use this. The market detail chart and the
// position charts read live intraday candles of their own.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/services/hyperliquid/hl_sparkline_cache.dart';

/// The one store of the session (memory over the disk box, the request
/// queue and its concurrency cap). Kept alive: the queue and the
/// in-memory series outlive any one card.
final hyperliquidSparklineStoreProvider = Provider<HlSparklineStore>((ref) {
  final model = HyperliquidModel();
  return HlSparklineStore(fetch: (wire) async {
    // Ninety days is what a card-sized sparkline can show.
    final candles = await model.getCandles(
        coin: wire, interval: '1d', window: const Duration(days: 90));
    return [for (final k in candles) k.close];
  });
});

/// One card's series: the cached one at once (null when the coin was
/// never seen), replaced when today's lands. Asking is what queues the
/// request; a card disposed before its turn drops out of the queue.
class HlSparklineNotifier
    extends AutoDisposeFamilyNotifier<HlSparkline?, String> {
  @override
  HlSparkline? build(String wire) {
    final store = ref.watch(hyperliquidSparklineStoreProvider);
    final unlisten = store.listen(wire, (s) => state = s);
    ref.onDispose(() {
      unlisten();
      store.cancel(wire);
    });
    store.request(wire);
    return store.cached(wire);
  }
}

final hyperliquidSparklineProvider = NotifierProvider.autoDispose
    .family<HlSparklineNotifier, HlSparkline?, String>(
        HlSparklineNotifier.new);
