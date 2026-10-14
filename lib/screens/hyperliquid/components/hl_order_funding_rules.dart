// lib/screens/hyperliquid/components/hl_order_funding_rules.dart
//
// The order slip's funding decisions that need no widget, as pure rules
// (the slip calls them; the tests table them):
//   - what of the venue's cash is this order's ([hlSlipReadyUsd]);
//   - whether the market still takes a funded order ([hlFundedMarketBlock]);
//   - whether the first order's builder approval waits for the money
//     ([hlDeferBuilderApproval]).

/// The venue cash a NEW order on the slip may count on: the account's
/// perp withdrawable plus spot USDC, less what a funded order still
/// queued or placing needs ([queuedRequiredUsd], that order's money), and
/// nothing at all while a sweep is carrying the venue's cash home
/// ([sweeping]). Never negative.
double hlSlipReadyUsd({
  required double withdrawableUsd,
  required double spotUsdc,
  double queuedRequiredUsd = 0,
  bool sweeping = false,
}) {
  if (sweeping) return 0;
  double clean(double v) => v.isFinite && v > 0 ? v : 0;
  final ready =
      clean(withdrawableUsd) + clean(spotUsdc) - clean(queuedRequiredUsd);
  return ready > 0 ? ready : 0;
}

/// Why a funded order must not move money (checked before any approval),
/// or null:
///   - a builder (HIP-3) perp whose dex settles in another stablecoin than
///     USDC can never be funded with Dollars (`collateral_not_usdc`), and
///     one whose collateral could not be confirmed waits
///     (`collateral_unverified`): placement would refuse it only after the
///     money had moved;
///   - a perp at its open-interest cap refuses new exposure (`oi_capped`);
///   - a market no longer in the venue's list — delisted or halted out of
///     the universe — takes nothing (`market_unavailable`).
/// [listed] is null when the list could not be read (the venue answers at
/// the order then). [usdcCollateral] is whether the market's dex settles
/// in USDC, null when it could not be read; spot and main-dex perps
/// ([hip3] false) always settle in USDC.
String? hlFundedMarketBlock({
  required bool isSpot,
  required bool reduceOnly,
  required bool oiCapped,
  required bool? listed,
  bool hip3 = false,
  bool? usdcCollateral = true,
}) {
  if (!isSpot && hip3) {
    if (usdcCollateral == false) return 'collateral_not_usdc';
    if (usdcCollateral == null) return 'collateral_unverified';
  }
  if (!isSpot && !reduceOnly && oiCapped) return 'oi_capped';
  if (listed == false) return 'market_unavailable';
  return null;
}

/// Whether a [hlFundedMarketBlock] reason means the market itself cannot
/// take the order (it says so), rather than a moment to try again.
bool hlFundedBlockIsMarketUnavailable(String reason) =>
    reason == 'collateral_not_usdc' || reason == 'market_unavailable';

/// Whether the one-time builder-fee approval waits until the order's
/// money has landed: an account Hyperliquid has never funded cannot post
/// a signed action, so a first order that funds it signs the approval
/// after the credit (the auto-fire, before placing) instead of failing
/// before anything moved.
bool hlDeferBuilderApproval({
  required bool accountUnfunded,
  required double shortfallUsd,
}) =>
    accountUnfunded && shortfallUsd > 0;
