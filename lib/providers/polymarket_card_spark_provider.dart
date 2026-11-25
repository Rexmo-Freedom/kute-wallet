// lib/providers/polymarket_card_spark_provider.dart
//
// The Predictions list cards' tiny charts: one store for the session
// (PolyCardSparkStore, poly_card_spark_store.dart: the batched, cached,
// cancellable reads) over the market sheet's own history cache, and one
// series per card, keyed by (token, range).

import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_browse_provider.dart'
    show PolyPriceHistoryCache;
import 'package:kute/services/polymarket/poly_card_spark_store.dart';

/// Under `flutter test` the cards read no network unless a test gives
/// the store a fake read (an override of [polyCardSparkStoreProvider]).
final bool _inTest = Platform.environment.containsKey('FLUTTER_TEST');

/// The one store of the session. Kept alive: its memory and queue outlive
/// any one card.
final polyCardSparkStoreProvider = Provider<PolyCardSparkStore>((ref) {
  final store = _inTest
      ? PolyCardSparkStore()
      : PolyCardSparkStore(
          fetch: PolyPriceHistoryCache.load,
          saved: PolyPriceHistoryCache.fromDisk,
          session: PolyPriceHistoryCache.any,
        );
  ref.onDispose(store.dispose);
  return store;
});

/// One card's series: what the store holds at once (null when nothing
/// yet), replaced when a read lands. Watching is what asks; a card that
/// goes away before its turn drops its read.
class PolyCardSparkNotifier extends AutoDisposeFamilyNotifier<
    List<PolymarketPricePoint>?, ({String tokenId, String interval})> {
  @override
  List<PolymarketPricePoint>? build(
      ({String tokenId, String interval}) arg) {
    final store = ref.watch(polyCardSparkStoreProvider);
    final unwatch =
        store.watch(arg.tokenId, arg.interval, (points) => state = points);
    ref.onDispose(unwatch);
    return store.cached(arg.tokenId, arg.interval);
  }
}

final polyCardSparkProvider = NotifierProvider.autoDispose.family<
    PolyCardSparkNotifier,
    List<PolymarketPricePoint>?,
    ({String tokenId, String interval})>(PolyCardSparkNotifier.new);
