// lib/screens/shared/portfolio_builder/builder_placement.dart
//
// Per-pool placement adapters for the portfolio Builder. The sequential
// loop, funding checks and progress rendering live in
// portfolio_builder_screen.dart; these adapters place ONE leg each and
// report a per-leg outcome the review stage renders.
//
// The placement mechanics are lifted from the deleted AI confirm sheets
// (de241186):
//   * predictions — bucket_confirm_sheet.dart's loop body: resolve the
//     token id (live event details when the stored one is missing), stage
//     a PendingBetIntent, place via PolymarketBetController, and read the
//     resulting pending status. The controller is USDC-only now, so a leg
//     that can't be covered by the Predictions balance fails fast (the
//     Builder additionally gates the whole total upfront). An
//     awaitingBalance status keeps the intent alive for the autofire —
//     clearing it would orphan an in-flight swap's placement.
//   * trading — hl_basket_confirm_sheet.dart's loop body, minus the
//     AI-designed entry styles: the Builder only places simple market
//     orders (spot buy via placeSpotOrder, perp open via openPosition at
//     1x, no TP/SL bracket). The kill-switch + geoblock gates stay in the
//     screen, checked ONCE before the loop like the deleted sheet did.
//
// Step-up (Wallet Hardening Phase 1b.3 and 1b.4): a run asks for ONE
// approval before the loop ([TradeBuilderApproval.request] or
// [PredictionBuilderApproval.request]), bound to the exact leg list. Each
// leg is then placed with a single-use child grant bound to exactly that leg
// (GrantGuard.chain), and each approved leg can be placed once. The screen
// closes the approval after the loop.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/require_fresh_auth.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/pending_polymarket_bet_provider.dart';
import 'package:kute/providers/polymarket_bet_controller.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/screens/shared/hyperliquid_fee_summary.dart';
import 'package:kute/screens/shared/portfolio_builder/builder_legs_provider.dart';

/// Outcome of placing one Builder leg.
class BuilderLegResult {
  final bool success;
  final bool stopRun;

  /// User-facing failure reason. Null on success.
  final String? error;

  const BuilderLegResult.ok()
      : success = true,
        stopRun = false,
        error = null;

  const BuilderLegResult.fail(this.error)
      : success = false,
        stopRun = false;

  const BuilderLegResult.paused(this.error)
      : success = false,
        stopRun = true;
}

/// Trims exception wrapper noise ("Exception: ") off a thrown error so the
/// review row shows the actual message the engines produce.
String builderErrorText(Object e) {
  var s = e.toString().trim();
  const prefix = 'Exception: ';
  if (s.startsWith(prefix)) s = s.substring(prefix.length).trim();
  if (s.isEmpty) return appL10n().builderOrderNotPlaced;
  return s;
}

/// The pending bet a prediction leg places: the stored token id, or the live
/// event's token for a binary event when none was stored. Null when the leg
/// is unplaceable.
Future<PendingBetIntent?> resolvePredictionBuilderBet(
  WidgetRef ref,
  PredictionBuilderLeg leg,
) async {
  var tokenId = leg.tokenId;
  var price = leg.price;
  if (tokenId == null || tokenId.isEmpty) {
    // Binary events only: for a multi-outcome event the yes/no getters
    // fall back to candidate token ids, which would silently place the
    // wrong instrument. The pick stage stores candidate tokens directly,
    // so hitting this without them means the leg is unplaceable.
    final event =
        await ref.read(polymarketEventDetailsProvider(leg.slug).future);
    if (event != null && event.isBinary) {
      tokenId = leg.isNo ? event.noTokenId : event.yesTokenId;
      price = leg.isNo ? event.noPrice : event.yesPrice;
    }
  }
  if (tokenId == null || tokenId.isEmpty) return null;
  return PendingBetIntent(
    tokenId: tokenId,
    amount: leg.amountUsd,
    slippagePct: 1.0,
    marketQuestion: leg.title,
    outcomeName: leg.outcomeName,
    expectedPrice: price,
    marketImage: leg.imageUrl,
    entrySource: 'portfolio_builder',
    // 100% of the pool: preparation fits the stake plus the venue's fees
    // into this cash at the executable best ask.
    spendAllBudgetUsd: leg.spendAll ? leg.amountUsd : null,
  );
}

/// Places one prediction leg through the existing bet controller so the
/// wrap/cost-basis/fee bookkeeping is identical to a normal bet. [approval]
/// is the run's step-up approval; the leg's own grant is chained from it.
Future<BuilderLegResult> placePredictionBuilderLeg(
  WidgetRef ref,
  PredictionBuilderLeg leg, {
  required PredictionBuilderApproval approval,
}) async {
  final pending = ref.read(pendingPolymarketBetProvider.notifier);
  final active = ref.read(pendingPolymarketBetProvider)?.status;
  if (const {
    PendingBetStatus.placing,
    PendingBetStatus.converting,
    PendingBetStatus.awaitingBalance,
    PendingBetStatus.awaitingConfirmation
  }.contains(active)) {
    return BuilderLegResult.paused(
        l10nForLanguage(ref.read(settingsProvider).language)
            .builderOrderStatusPending);
  }
  // Set when the leg went in-flight (awaiting a swap) — its intent must
  // survive the clear so the poller/autofire can resolve it.
  var keepIntent = false;
  try {
    final bet = approval.betFor(leg);
    if (bet == null) {
      return BuilderLegResult.fail(appL10n().builderMarketGone);
    }
    final AuthGrant grant;
    try {
      grant = approval.grantFor(ref, bet);
    } on AuthGrantException catch (e) {
      // Nothing was signed for this leg.
      trackGrantFailure(e, action: SensitiveAction.pmBet);
      return BuilderLegResult.fail(approval.failureText(e));
    }

    pending.setIntent(bet);
    final failure = await ref
        .read(polymarketBetControllerProvider)
        .place('usdc', grant: grant, entrySource: 'portfolio_builder');
    if (failure != null) {
      trackGrantFailure(failure, action: SensitiveAction.pmBet);
      return BuilderLegResult.fail(approval.failureText(failure));
    }

    final after = ref.read(pendingPolymarketBetProvider);
    final status = after?.status;
    keepIntent = status == PendingBetStatus.awaitingBalance ||
        status == PendingBetStatus.awaitingConfirmation;
    if (keepIntent) {
      return BuilderLegResult.paused(
          l10nForLanguage(ref.read(settingsProvider).language)
              .builderOrderStatusPending);
    }
    if (status == PendingBetStatus.done) {
      return const BuilderLegResult.ok();
    }
    return BuilderLegResult.fail(
        after?.errorMessage ?? appL10n().builderBetNotPlaced);
  } catch (e) {
    return BuilderLegResult.fail(builderErrorText(e));
  } finally {
    // Don't clear an in-flight intent: the autofire still needs it (it
    // clears on resolution). Terminal states clear here.
    if (!keepIntent) pending.clear();
  }
}

/// Resolves the Builder leg's live market descriptor honoring the leg's
/// kind — `hyperliquidMarketProvider` alone prefers perps on a name
/// collision, which would place the wrong instrument for a spot leg whose
/// coin also trades as a perp.
HlMarket? resolveBuilderTradeMarket(WidgetRef ref, TradeBuilderLeg leg) {
  final list = leg.isSpot
      ? ref.read(hyperliquidSpotMarketsProvider).valueOrNull
      : ref.read(hyperliquidPerpMarketsProvider).valueOrNull;
  if (list != null) {
    for (final m in list) {
      if (m.coin == leg.coin) return m;
    }
  }
  // Kind-specific list missed (still loading, or the pair vanished). Fall
  // back to the generic lookup the deleted sheet used.
  return ref.read(hyperliquidMarketProvider(leg.coin));
}

/// One step-up approval for a whole Builder run (Wallet Hardening Phase 1b.3
/// and 1b.4). The grant is bound to the run intent, the exact leg list;
/// every leg gets a single-use child grant bound to exactly that leg, and
/// each approved leg can be placed once.
class BuilderRunApproval {
  BuilderRunApproval._({
    required AuthGrant grant,
    required SensitiveIntent runIntent,
    required List<SensitiveIntent> legs,
    required String expiredText,
    required String changedText,
  })  : _grant = grant,
        _runIntent = runIntent,
        _remaining = [for (final l in legs) GrantGuard.legKey(l)],
        _expiredText = expiredText,
        _changedText = changedText;

  final AuthGrant _grant;
  final SensitiveIntent _runIntent;

  /// Approved leg keys not placed yet (a multiset: equal legs repeat).
  final List<String> _remaining;
  final String _expiredText;
  final String _changedText;

  /// The single-use grant for [legIntent]. Throws [GrantExpired] when the
  /// run approval expired or was closed, and [ReauthRequired] (the `legs`
  /// field class) when the leg is not one the user approved or was already
  /// placed.
  AuthGrant _childFor(SensitiveIntent legIntent) {
    GrantGuard.check(_grant, _runIntent, allowed: {_runIntent.action});
    if (!_remaining.remove(GrantGuard.legKey(legIntent))) {
      throw ReauthRequired(const {DriftField.legs});
    }
    return GrantGuard.chain(_grant, legIntent);
  }

  /// The leg row text for a grant failure.
  String failureText(AuthGrantException e) =>
      e is ReauthRequired ? _changedText : _expiredText;

  /// Ends the run: no further leg can be approved from this grant. Child
  /// grants already handed out stay single use.
  void close() => _grant.revoke();
}

/// The run approval for Hyperliquid Builder legs.
class TradeBuilderApproval extends BuilderRunApproval {
  TradeBuilderApproval._({
    required super.grant,
    required String walletId,
    required super.runIntent,
    required super.legs,
    required super.expiredText,
    required super.changedText,
  })  : _walletId = walletId,
        super._();

  final String _walletId;

  /// Prompts once for [legs], with the `stepUpReasonBuilderOrders` copy.
  /// Legs whose market no longer resolves are left out of the approval
  /// (they fail fast when placed). Returns null when the user declined,
  /// there is no spending wallet, or no leg resolves to a market.
  static Future<TradeBuilderApproval?> request(
    BuildContext context,
    WidgetRef ref,
    List<TradeBuilderLeg> legs,
  ) async {
    final walletId = pickSpendingWallet(ref.read(settingsProvider))?.id;
    if (walletId == null) return null;
    final legIntents = <SensitiveIntent>[];
    var totalUsd = 0.0;
    for (final leg in legs) {
      final market = resolveBuilderTradeMarket(ref, leg);
      if (market == null) continue;
      legIntents.add(HlBuilderIntents.leg(
        walletId: walletId,
        market: market,
        isLong: leg.isLong,
        usd: leg.amountUsd,
      ));
      totalUsd += leg.amountUsd;
    }
    if (legIntents.isEmpty) return null;

    final l10n = context.l10n;
    final runIntent =
        HlBuilderIntents.legList(walletId: walletId, legs: legIntents);
    final grant = await requireFreshAuthGrant(
      context,
      ref,
      intent: runIntent,
      reason: l10n.stepUpReasonBuilderOrders(legIntents.length),
      amountUsd: totalUsd,
    );
    if (grant == null) return null;
    return TradeBuilderApproval._(
      grant: grant,
      walletId: walletId,
      runIntent: runIntent,
      legs: legIntents,
      expiredText: l10n.builderLegApprovalExpired,
      changedText: l10n.stepUpDetailsChanged,
    );
  }

  /// The single-use grant for [leg] on [market]. See [BuilderRunApproval].
  AuthGrant grantFor(TradeBuilderLeg leg, HlMarket market) =>
      _childFor(HlBuilderIntents.leg(
        walletId: _walletId,
        market: market,
        isLong: leg.isLong,
        usd: leg.amountUsd,
      ));
}

/// The run approval for Predictions Builder legs. Each leg's token is
/// resolved before the prompt, so the approval binds what will be placed.
class PredictionBuilderApproval extends BuilderRunApproval {
  PredictionBuilderApproval._({
    required super.grant,
    required Map<String, PendingBetIntent> bets,
    required super.runIntent,
    required super.legs,
    required super.expiredText,
    required super.changedText,
  })  : _bets = bets,
        super._();

  /// Resolved bets by leg key. Legs missing here are unplaceable.
  final Map<String, PendingBetIntent> _bets;

  /// Resolves every leg, then prompts once with the
  /// `stepUpReasonBuilderOrders` copy. Returns null when the user declined,
  /// the Predictions account is not ready, or no leg resolves.
  static Future<PredictionBuilderApproval?> request(
    BuildContext context,
    WidgetRef ref,
    List<PredictionBuilderLeg> legs,
  ) async {
    final walletId =
        ref.read(polymarketTradingProvider.notifier).signingWalletId;
    if (walletId == null || walletId.isEmpty) return null;
    final controller = ref.read(polymarketBetControllerProvider);
    final bets = <String, PendingBetIntent>{};
    final legIntents = <SensitiveIntent>[];
    var totalUsd = 0.0;
    for (final leg in legs) {
      PendingBetIntent? bet;
      try {
        bet = await resolvePredictionBuilderBet(ref, leg);
        if (bet != null) bet = await controller.prepareIntent(bet);
      } catch (_) {
        bet = null;
      }
      if (bet == null) continue;
      final review = controller.reviewIntent(bet);
      if (review == null) continue;
      bets[leg.key] = bet;
      legIntents.add(review);
      totalUsd += bet.amount;
    }
    if (legIntents.isEmpty || !context.mounted) return null;

    final l10n = context.l10n;
    final runIntent = PmGrants.builderRun(walletId: walletId, legs: legIntents);
    final grant = await requireFreshAuthGrant(
      context,
      ref,
      intent: runIntent,
      reason: l10n.stepUpReasonBuilderOrders(legIntents.length),
      amountUsd: totalUsd,
    );
    if (grant == null) return null;
    return PredictionBuilderApproval._(
      grant: grant,
      bets: bets,
      runIntent: runIntent,
      legs: legIntents,
      expiredText: l10n.builderLegApprovalExpired,
      changedText: l10n.stepUpDetailsChanged,
    );
  }

  /// The bet the approval resolved for [leg], or null when it is
  /// unplaceable.
  PendingBetIntent? betFor(PredictionBuilderLeg leg) => _bets[leg.key];

  /// The single-use grant for [bet]. See [BuilderRunApproval].
  AuthGrant grantFor(WidgetRef ref, PendingBetIntent bet) {
    final review = ref.read(polymarketBetControllerProvider).reviewIntent(bet);
    if (review == null) throw ReauthRequired(const {DriftField.wallet});
    return _childFor(review);
  }
}

/// The leverage every Builder perp leg opens at; its notional is the leg's
/// amount times this.
const builderTradeLeverage = 1;

/// What one Builder leg's order is priced at in the review's fee row: the
/// notional [placeTradeBuilderLeg] sends (spot: the amount; perp: the
/// margin at [builderTradeLeverage]), with the same side and market flags.
HyperliquidFeeLeg builderTradeFeeLeg(TradeBuilderLeg leg, HlMarket? market) =>
    HyperliquidFeeLeg(
      notional:
          leg.isSpot ? leg.amountUsd : leg.amountUsd * builderTradeLeverage,
      spot: leg.isSpot,
      buy: leg.isSpot || leg.isLong,
      // A leg whose market isn't resolved could be on a HIP-3 dex, so its
      // venue fee reads as unknown rather than the default-perp rate.
      dex: market?.dex ?? _unresolvedDex,
    );

/// Stands in for the dex of a leg whose market isn't loaded.
const _unresolvedDex = '?';

/// [builderTradeFeeLeg] for every leg, against the markets already loaded.
/// Never starts a markets load: the review only reads what the pick stage
/// fetched.
List<HyperliquidFeeLeg> builderTradeFeeLegs(
    WidgetRef ref, List<TradeBuilderLeg> legs) {
  HlMarket? loaded(TradeBuilderLeg leg) {
    final provider = leg.isSpot
        ? hyperliquidSpotMarketsProvider
        : hyperliquidPerpMarketsProvider;
    if (!ref.exists(provider)) return null;
    for (final m in ref.read(provider).valueOrNull ?? const <HlMarket>[]) {
      if (m.coin == leg.coin) return m;
    }
    return null;
  }

  return [for (final leg in legs) builderTradeFeeLeg(leg, loaded(leg))];
}

/// Places one Hyperliquid leg via the existing trading notifier so the
/// funding/rounding/analytics bookkeeping is identical to a normal order.
/// Simple market orders only: spot buy, or a 1x perp open with no TP/SL.
/// [approval] is the run's step-up approval; the leg's own grant is chained
/// from it and consumed by the notifier before anything is signed.
Future<BuilderLegResult> placeTradeBuilderLeg(
  WidgetRef ref,
  TradeBuilderLeg leg, {
  required TradeBuilderApproval approval,
}) async {
  final market = resolveBuilderTradeMarket(ref, leg);
  if (market == null) {
    // Coin no longer resolvable on Hyperliquid. Same null-fallback
    // philosophy as the order slip.
    return BuilderLegResult.fail(appL10n().builderMarketGone);
  }
  final trading = ref.read(hyperliquidTradingProvider.notifier);
  try {
    final grant = approval.grantFor(leg, market);
    if (market.isSpot) {
      await trading.placeSpotOrder(
        market: market,
        isBuy: true,
        usd: leg.amountUsd,
        source: 'builder',
        grant: grant,
      );
    } else {
      await trading.openPosition(
        market: market,
        isLong: leg.isLong,
        marginUsd: leg.amountUsd,
        leverage: builderTradeLeverage,
        source: 'builder',
        grant: grant,
      );
    }
    return const BuilderLegResult.ok();
  } on AuthGrantException catch (e) {
    // Nothing was signed for this leg.
    trackGrantFailure(e, action: SensitiveAction.hlOrder);
    return BuilderLegResult.fail(approval.failureText(e));
  } catch (e) {
    return BuilderLegResult.fail(builderErrorText(e));
  }
}
