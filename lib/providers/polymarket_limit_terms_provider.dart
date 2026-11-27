// lib/providers/polymarket_limit_terms_provider.dart
//
// The two market facts a resting limit is checked against on the
// Advanced pages, before anything is approved: the price increment (tick)
// and the venue's minimum order size in shares. Both come from the
// token's public REST book (which also saves the tick for the signer,
// market_terms_store.dart); a read that fails leaves the saved tick, if
// any, and an unknown minimum, which the pages treat as the venue's usual
// 5 shares. Public market data only.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/providers/polymarket_bet_controller.dart';
import 'package:kute/services/polymarket/limit_order_rules.dart';
import 'package:kute/services/polymarket/market_terms_store.dart';

class PolymarketLimitTerms {
  const PolymarketLimitTerms({this.tick, this.minShares});

  /// The market's increment; null while unknown.
  final double? tick;

  /// The venue's minimum order size in shares; null while unknown.
  final double? minShares;
}

/// [PolymarketLimitTerms] for one token. Read once per Advanced page.
final polymarketLimitTermsProvider = FutureProvider.autoDispose
    .family<PolymarketLimitTerms, String>((ref, tokenId) async {
  final saved =
      polymarketTickValue(PolymarketMarketTermsStore.currentTickSize(tokenId));
  if (tokenId.isEmpty) return PolymarketLimitTerms(tick: saved);
  try {
    final book = await PolymarketBetController.restBook(tokenId);
    return PolymarketLimitTerms(
      tick: polymarketTickValue(book.minTickSize) ?? saved,
      minShares: double.tryParse(book.minOrderSize ?? ''),
    );
  } catch (_) {
    return PolymarketLimitTerms(tick: saved);
  }
});
