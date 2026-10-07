// lib/screens/shared/portfolio_builder/builder_legs_provider.dart
//
// State for the manual portfolio Builder (the "Build" chip on the
// Predictions and Trading pool screens). The user assembles legs one at a
// time in the Builder flow; these notifiers only hold that draft — they
// never move money. PortfolioBuilderScreen's review stage is the single
// real-money gate, and the placement adapters in builder_placement.dart
// do the actual placing.
//
// Modeled on the deleted AI bucket/basket providers
// (polymarket_bucket_provider.dart / hyperliquid_basket_provider.dart,
// see de241186) with the AI-specific fields dropped: the Builder only
// places plain market orders (no TP/SL, no limit/scale/twap styles), and
// the outcome/side is user-switchable in the Amounts stage, so a leg is
// keyed per MARKET (slug / coin), not per market+side.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which pool the Builder is assembling for.
enum BuilderPool { predictions, trading }

/// Balance gate shared by the Amounts and Review stages: the portfolio is
/// placeable only from the pool's own USDC (never auto-swapped from BTC),
/// so any total above the available balance blocks the CTA. The epsilon
/// mirrors the deleted hl_basket_confirm_sheet's float-safe comparison.
bool builderInsufficientBalance({
  required double totalUsd,
  required double availableUsd,
}) =>
    totalUsd > availableUsd + 1e-6;

/// One prediction-market leg. Carries BOTH sides' token ids/prices so the
/// Yes/No selector in the Amounts stage is a pure state flip (no refetch);
/// a missing token id is re-resolved from live event details at place time
/// (same fallback the deleted BucketConfirmSheet used).
@immutable
class PredictionBuilderLeg {
  final String slug;
  final String title;
  final String? imageUrl;
  final String? conditionId;
  final DateTime? marketEndAt;

  /// 'Yes' | 'No' — the picked side.
  final String outcomeName;
  final String? yesTokenId;
  final String? noTokenId;

  /// 0-1 probabilities as seen when the leg was added.
  final double yesPrice;
  final double noPrice;
  final double amountUsd;

  /// The amount came from the 100% chip: everything in the pool. The
  /// stake is then re-fitted at placement so it plus the venue's fees
  /// fits the cash (see `PendingBetIntent.spendAllBudgetUsd`); a typed
  /// amount is never changed.
  final bool spendAll;

  /// Polymarket Combos eligibility from Gamma, filled at review time:
  /// `comboStatus` (enabled / pending / disabled) and the Positions
  /// Framework ids of each side (`positionIds`, NOT the CLOB token ids).
  /// Null until looked up.
  final String? comboStatus;
  final String? yesPositionId;
  final String? noPositionId;

  const PredictionBuilderLeg({
    required this.slug,
    required this.title,
    this.imageUrl,
    this.conditionId,
    this.marketEndAt,
    this.outcomeName = 'Yes',
    this.yesTokenId,
    this.noTokenId,
    this.yesPrice = 0,
    this.noPrice = 0,
    this.amountUsd = 0,
    this.spendAll = false,
    this.comboStatus,
    this.yesPositionId,
    this.noPositionId,
  });

  /// One leg per market — the outcome is switchable in the Amounts stage.
  String get key => slug;

  bool get isNo => outcomeName.toLowerCase() == 'no';
  String? get tokenId => isNo ? noTokenId : yesTokenId;
  double get price => isNo ? noPrice : yesPrice;

  /// The combo leg id of the picked side, or null when unknown.
  String? get comboPositionId => isNo ? noPositionId : yesPositionId;

  /// Gamma says this market can be a combo leg and the side's id is known.
  bool get comboEnabled =>
      comboStatus == 'enabled' && (comboPositionId?.isNotEmpty ?? false);

  /// The same leg with Gamma's combo eligibility.
  PredictionBuilderLeg withCombo({
    required String? status,
    required String? yesPositionId,
    required String? noPositionId,
  }) =>
      PredictionBuilderLeg(
        slug: slug,
        title: title,
        imageUrl: imageUrl,
        conditionId: conditionId,
        marketEndAt: marketEndAt,
        outcomeName: outcomeName,
        yesTokenId: yesTokenId,
        noTokenId: noTokenId,
        yesPrice: yesPrice,
        noPrice: noPrice,
        amountUsd: amountUsd,
        spendAll: spendAll,
        comboStatus: status,
        yesPositionId: yesPositionId,
        noPositionId: noPositionId,
      );

  /// A new [amountUsd] without [spendAll] is a typed amount.
  PredictionBuilderLeg copyWith(
          {String? outcomeName, double? amountUsd, bool? spendAll}) =>
      PredictionBuilderLeg(
        slug: slug,
        title: title,
        imageUrl: imageUrl,
        conditionId: conditionId,
        marketEndAt: marketEndAt,
        outcomeName: outcomeName ?? this.outcomeName,
        yesTokenId: yesTokenId,
        noTokenId: noTokenId,
        yesPrice: yesPrice,
        noPrice: noPrice,
        amountUsd: amountUsd ?? this.amountUsd,
        spendAll: spendAll ?? (amountUsd == null && this.spendAll),
        comboStatus: comboStatus,
        yesPositionId: yesPositionId,
        noPositionId: noPositionId,
      );
}

/// One Hyperliquid leg. Spot is buy-only (isLong stays true); perps carry
/// a switchable long/short side. Always a simple 1x market order — the
/// full HlMarket (wire ids, rounding) is re-resolved by coin+kind at place
/// time so a stale draft can't carry outdated order-wire metadata.
@immutable
class TradeBuilderLeg {
  final String coin;

  /// Friendly name ('Apple', 'Bitcoin') when known.
  final String? name;
  final bool isSpot;
  final bool isLong;
  final double amountUsd;
  final String? iconUrl;
  final String category;

  const TradeBuilderLeg({
    required this.coin,
    this.name,
    required this.isSpot,
    this.isLong = true,
    this.amountUsd = 0,
    this.iconUrl,
    this.category = 'crypto',
  });

  /// One leg per market (coin+kind) — the side is switchable in Amounts.
  String get key => '$coin|${isSpot ? 'spot' : 'perp'}';

  TradeBuilderLeg copyWith({bool? isLong, double? amountUsd}) =>
      TradeBuilderLeg(
        coin: coin,
        name: name,
        isSpot: isSpot,
        isLong: isLong ?? this.isLong,
        amountUsd: amountUsd ?? this.amountUsd,
        iconUrl: iconUrl,
        category: category,
      );
}

/// Shared list mechanics for both pools' drafts. [K]eyed add/toggle/
/// remove/amount editing; subclasses only add their side/outcome flips.
abstract class _BuilderLegsNotifier<L> extends Notifier<List<L>> {
  String keyOf(L leg);
  L withAmount(L leg, double amountUsd);

  @override
  List<L> build() => const [];

  /// Adds the leg if absent, removes it if present. Returns true when the
  /// leg was ADDED (the callers' analytics distinguish add vs remove).
  bool toggle(L leg) {
    final k = keyOf(leg);
    final i = state.indexWhere((l) => keyOf(l) == k);
    if (i >= 0) {
      final next = [...state]..removeAt(i);
      state = next;
      return false;
    }
    state = [...state, leg];
    return true;
  }

  bool contains(String key) => state.any((l) => keyOf(l) == key);

  void setAmount(String key, double amountUsd) {
    state = [
      for (final l in state) keyOf(l) == key ? withAmount(l, amountUsd) : l,
    ];
  }

  void remove(String key) =>
      state = state.where((l) => keyOf(l) != key).toList();

  /// Drops every leg whose key is in [keys] — used after placement to
  /// clear the successfully placed legs while failed ones stay listed.
  void removeAll(Iterable<String> keys) {
    final drop = keys.toSet();
    state = state.where((l) => !drop.contains(keyOf(l))).toList();
  }

  void clear() => state = const [];

  void replaceAll(List<L> legs) => state = List.unmodifiable(legs);
}

class PredictionBuilderNotifier
    extends _BuilderLegsNotifier<PredictionBuilderLeg> {
  @override
  String keyOf(PredictionBuilderLeg leg) => leg.key;

  @override
  PredictionBuilderLeg withAmount(PredictionBuilderLeg leg, double amountUsd) =>
      leg.copyWith(amountUsd: amountUsd);

  void setOutcome(String key, String outcomeName) {
    state = [
      for (final l in state)
        l.key == key ? l.copyWith(outcomeName: outcomeName) : l,
    ];
  }
}

class TradeBuilderNotifier extends _BuilderLegsNotifier<TradeBuilderLeg> {
  @override
  String keyOf(TradeBuilderLeg leg) => leg.key;

  @override
  TradeBuilderLeg withAmount(TradeBuilderLeg leg, double amountUsd) =>
      leg.copyWith(amountUsd: amountUsd);

  /// Perp legs only — spot is buy-only, so the flip is refused there.
  void setSide(String key, bool isLong) {
    state = [
      for (final l in state)
        l.key == key && !l.isSpot ? l.copyWith(isLong: isLong) : l,
    ];
  }
}

final builderPredictionLegsProvider =
    NotifierProvider<PredictionBuilderNotifier, List<PredictionBuilderLeg>>(
        PredictionBuilderNotifier.new);

final builderTradeLegsProvider =
    NotifierProvider<TradeBuilderNotifier, List<TradeBuilderLeg>>(
        TradeBuilderNotifier.new);

/// Grand total of the Predictions draft in USD.
final builderPredictionTotalProvider = Provider<double>((ref) {
  final legs = ref.watch(builderPredictionLegsProvider);
  return legs.fold(0.0, (sum, l) => sum + l.amountUsd);
});

/// Grand total of the Trading draft in USD.
final builderTradeTotalProvider = Provider<double>((ref) {
  final legs = ref.watch(builderTradeLegsProvider);
  return legs.fold(0.0, (sum, l) => sum + l.amountUsd);
});

/// Ledger drafts are separate from the spending-wallet builder and each other.
final ledgerBuilderPredictionLegsProvider =
    StateProvider.family<List<PredictionBuilderLeg>, String>(
        (ref, walletId) => const []);
