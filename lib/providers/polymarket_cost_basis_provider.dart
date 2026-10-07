// Tracks the actual USDC the user paid for each Polymarket position,
// keyed by tokenId. The Polymarket API returns `avgPrice * size` as
// the implied cost basis, but that's a rounded value — a position
// bought for $1.04 with 321.78 shares at 0.323¢ comes back as
// `0.003 * 321.78 = $0.97`, leaving a 7¢ gap the user can't reconcile
// against their wallet. We solve it by recording the exact USDC moved
// (the FAK's `takingAmount`) at placement time, then preferring this
// cached cost in the position detail sheet.
//
// Schema is intentionally minimal: a single Hive box mapping tokenId
// → cumulative paid USDC. Buys add; full sells (size → 0) clear the
// entry so a re-entry on the same token starts fresh. Partial sells
// leave the entry alone — the user's "I put in $X" mental model
// shouldn't decrease when they take some chips off the table.
//
// Older positions placed before this layer existed fall through to
// the derived `pos.avgPrice * pos.size` fallback in the UI.

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/providers/polymarket_browse_provider.dart'
    show PolymarketPosition;
import 'package:kute/providers/polymarket_sats_pnl_provider.dart';

const String _kCostBasisBox = 'polymarket_cost_basis';

class PolymarketCostBasisNotifier extends StateNotifier<Map<String, double>> {
  PolymarketCostBasisNotifier() : super(const {}) {
    _load();
  }

  Future<void> _load() async {
    final box = await Hive.openBox<double>(_kCostBasisBox);
    state = Map<String, double>.from(box.toMap().cast<String, double>());
  }

  /// Record an additional USDC payment for [tokenId]. Buying more on
  /// an existing position accumulates; the running total is what gets
  /// shown in the detail sheet's "Invested" field.
  Future<void> addCost(String tokenId, double paidUsdc) async {
    if (tokenId.isEmpty || paidUsdc <= 0) return;
    final box = await Hive.openBox<double>(_kCostBasisBox);
    final existing = box.get(tokenId) ?? 0;
    final updated = existing + paidUsdc;
    await box.put(tokenId, updated);
    state = {...state, tokenId: updated};
  }

  /// Drop the cached cost for [tokenId]. Called when the position
  /// fully closes (sold to zero) so the next entry starts fresh.
  Future<void> reset(String tokenId) async {
    if (tokenId.isEmpty) return;
    final box = await Hive.openBox<double>(_kCostBasisBox);
    if (!box.containsKey(tokenId)) return;
    await box.delete(tokenId);
    final next = Map<String, double>.from(state)..remove(tokenId);
    state = next;
  }

  /// Scale the cached cost down by `fractionRemaining` after a
  /// partial sell. Standard proportional cost-basis: if the user
  /// sells 75% of a position, the cost attached to the remaining 25%
  /// is 25% of the original. Without this, the position-detail
  /// sheet keeps showing the original "Invested" against a much
  /// smaller current value, producing a fake catastrophic P&L like
  /// "Invested $3.77 / current $1.00 / -73.6%".
  Future<void> scaleByRemaining(
      String tokenId, double fractionRemaining) async {
    if (tokenId.isEmpty) return;
    final clamped = fractionRemaining.clamp(0.0, 1.0).toDouble();
    if (clamped >= 0.999) return; // basically nothing sold
    if (clamped <= 0.001) {
      // Effectively a full close — defer to reset.
      await reset(tokenId);
      return;
    }
    final box = await Hive.openBox<double>(_kCostBasisBox);
    final existing = box.get(tokenId);
    if (existing == null || existing <= 0) return;
    final updated = existing * clamped;
    await box.put(tokenId, updated);
    state = {...state, tokenId: updated};
  }

  double? costFor(String tokenId) => state[tokenId];
}

final polymarketCostBasisProvider =
    StateNotifierProvider<PolymarketCostBasisNotifier, Map<String, double>>(
  (ref) => PolymarketCostBasisNotifier(),
);

/// What the user paid for [pos], in USDC: the cost basis behind the
/// position sheet's "Invested" and P&L, and the chart's "Bought" line
/// (cost ÷ shares) on both the position and the market sheet, so the two
/// screens can never draw it at different prices.
///
/// Prefers the trade-history basis (every buy, average-cost on sells),
/// then the locally recorded USDC, then the API's `avgPrice × size`. A
/// cached entry that equals the share count is the old `takingAmount`
/// bug (shares stored where USDC belonged): it is ignored and reset.
/// Never more than the share count, since a share costs at most $1.
double polymarketPositionCostBasis(WidgetRef ref, PolymarketPosition pos) {
  final tokenId = pos.tokenId;
  final cachedCost = tokenId != null
      ? ref.watch(polymarketCostBasisProvider.select((m) => m[tokenId]))
      : null;
  final cachedLooksBroken = cachedCost != null &&
      pos.size > 0 &&
      (cachedCost - pos.size).abs() < 0.001;
  if (cachedLooksBroken && tokenId != null) {
    Future.microtask(() {
      ref
          .read(polymarketCostBasisProvider.notifier)
          .reset(tokenId)
          .catchError((_) {});
    });
  }
  final activity = tokenId != null
      ? ref.watch(predictionUsdCostProvider(tokenId)).valueOrNull
      : null;
  return resolvePolymarketCostBasis(
    size: pos.size,
    avgPrice: pos.avgPrice,
    activity: activity,
    cachedCost: cachedLooksBroken ? null : cachedCost,
  );
}

/// The choice behind [polymarketPositionCostBasis], for a position of
/// [size] shares the positions API prices at [avgPrice].
///
/// The trade history only describes this position when it accounts for
/// the same shares. Right after a bet it may count the fill twice (the
/// app's own row next to the indexed one) or miss it, and its cost then
/// belongs to another share count: a 15¢ fill read "Bought 30¢" and -50%.
/// A history that disagrees with the position by more than 1% is set
/// aside for the positions API's own average, and so is a local record
/// that would price a share above $1.
@visibleForTesting
double resolvePolymarketCostBasis({
  required double size,
  required double avgPrice,
  ({double cost, double shares})? activity,
  double? cachedCost,
}) {
  final derivedCost = avgPrice * size;
  final activityMatches = activity != null &&
      size > 0 &&
      (activity.shares - size).abs() <= size * 0.01 + 0.01;
  var costBasis =
      (activityMatches ? activity.cost : null) ?? cachedCost ?? derivedCost;
  if (size > 0 && costBasis > size) {
    costBasis = derivedCost > 0 && derivedCost <= size ? derivedCost : size;
  }
  return costBasis;
}
