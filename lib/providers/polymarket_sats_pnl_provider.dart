import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show Activity;
import 'package:kute/providers/polymarket_trading_provider.dart';

/// Total USDC cost basis of the CURRENTLY-HELD shares of [tokenId], computed
/// from the trade history with the average-cost method: each BUY adds its
/// usdcSize + shares to the running pool; each SELL removes shares at the
/// running average price (so it draws down cost proportionally). The leftover
/// `cost` is therefore the basis of the shares still held — correct for both
/// multi-buy adds AND partial sells.
///
/// This replaces a naive "sum of every BUY" which overcounted any position
/// that had been partially sold (or sold then re-bought): e.g. 2.48 shares
/// showing a $4.00 basis = $1.61/share, which is impossible since a share
/// costs at most $1. That bogus basis produced a wrong P&L and pushed the
/// chart's "Bought" reference line off-screen.
///
/// Null when there's no buy activity yet — the caller falls back to the
/// cached/derived basis. [shares] is the held count the history implies, so
/// the caller can tell when the history and the position disagree.
final predictionUsdCostProvider = FutureProvider.autoDispose
    .family<({double cost, double shares})?, String>((ref, tokenId) async {
  if (tokenId.isEmpty) return null;
  final activities = await ref.watch(polymarketActivityProvider.future);
  return predictionHeldCostFromActivity(activities, tokenId);
});

/// The average-cost walk behind [predictionUsdCostProvider].
({double cost, double shares})? predictionHeldCostFromActivity(
    List<Activity> activities, String tokenId) {
  if (tokenId.isEmpty) return null;
  // Filter on `side` (BUY/SELL), never `activityType` — the latter throws on
  // SDK-unknown enum values (e.g. "YIELD").
  final trades =
      activities.where((a) => a.asset == tokenId && a.size > 0).toList()
        // Oldest-first so the running average reflects the real fill order.
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  if (trades.isEmpty) return null;

  var shares = 0.0;
  var cost = 0.0;
  var sawBuy = false;
  for (final t in trades) {
    final side = (t.side ?? '').toUpperCase();
    if (side == 'BUY' && t.usdcSize > 0) {
      shares += t.size;
      cost += t.usdcSize;
      sawBuy = true;
    } else if (side == 'SELL') {
      if (shares <= 0) continue;
      // Remove the sold shares at the current average cost so the remaining
      // basis stays proportional. Clamp to the shares actually held to guard
      // against out-of-order / partial-fill noise in the activity feed.
      final sold = t.size > shares ? shares : t.size;
      final avg = cost / shares;
      cost -= avg * sold;
      shares -= sold;
      if (cost < 0) cost = 0;
    }
  }
  if (!sawBuy) return null;
  // Fully closed (or noise drove shares to ~0): no basis to report.
  if (shares <= 0) return null;
  return (cost: cost, shares: shares);
}
