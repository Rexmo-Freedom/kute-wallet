// Claiming a resolved Predictions position in one tap.
//
// The Claim (or Clear) button where the user sees the result (the
// Portfolio card, the position screen) runs the redeem itself and ends on
// the shared confirmation (ClaimPlacedOverlay / the cleared overlay). There
// is no review page in between: the redeem is relayer-paid (its "Network
// fee: Free" is on the confirmation's receipt) and signs with the unlocked
// session exactly as before, inside PolymarketTradingNotifier
// .redeemPosition. Nothing here signs or builds a transaction.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/helpers/formatters/polymarket_amount_formatter.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/screens/polymarket/components/claim_placed_overlay.dart';
import 'package:kute/screens/polymarket/components/polymarket_error_copy.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/services/tracking_service.dart';

/// Conditions with a claim on its way from this app session: a second tap
/// (the same button twice, or the card and then the position screen) never
/// sends a second redeem while the first is in flight. After it lands the
/// trading state's `clearingConditionIds` keeps the button locked until the
/// Data API catches up.
final Set<String> _claimsInFlight = <String>{};

/// Claims (or, for a lost side, clears) the resolved [position]: the redeem,
/// then the shared confirmation. [surface] tags the analytics
/// (`portfolio_card`, `position_detail`). [popRoute] closes the screen the
/// tap came from before the confirmation opens. Returns whether the redeem
/// went through.
Future<bool> claimPolymarketPosition(
  BuildContext context,
  WidgetRef ref,
  PolymarketPosition position, {
  required String surface,
  bool popRoute = false,
}) async {
  final pos = position;
  if (!_claimsInFlight.add(pos.marketId)) return false;
  HapticFeedback.mediumImpact();
  final won = pos.won == true;
  TrackingService.track('prediction_claim_tapped', params: {
    'pnl_direction': won ? 'gain' : 'loss',
  });
  TrackingService.polymarketRedeemInitiated(
      marketId: pos.marketId, trigger: 'manual', surface: surface);
  final navigator = Navigator.of(context, rootNavigator: true);
  final local = Navigator.of(context);
  try {
    final credited =
        await ref.read(polymarketTradingProvider.notifier).redeemPosition(
              conditionId: pos.marketId,
              trigger: 'manual',
              surface: surface,
            );
    // The confirmation opens even when the tapped card has gone meanwhile
    // (the list re-sorted under it): the root navigator was read up front.
    if (popRoute && local.mounted) local.maybePop();
    if (!navigator.mounted) return true;
    if (won) {
      pushClaimPlacedOverlay(
        navigator: navigator,
        marketQuestion: pos.marketQuestion,
        outcome: pos.outcome,
        amountUsd: credited,
      );
    } else {
      pushPositionClearedOverlay(
          navigator: navigator,
          context: navigator.context,
          marketQuestion: pos.marketQuestion,
          outcome: pos.outcome);
    }
    return true;
  } catch (e) {
    // redeemPosition reports its own failures; this covers anything thrown
    // before or around it, once.
    if (!PolymarketTradingNotifier.redeemFailureTracked(e)) {
      TrackingService.polymarketRedeemFailed(
        marketId: pos.marketId,
        reason: TrackingService.errorCategory(e),
        trigger: 'manual',
        surface: surface,
      );
    }
    if (!context.mounted) return false;
    if (e is PolymarketResultNotOnChainException ||
        e is PolymarketNothingToClaimException) {
      // Nothing was sent: the result is not on chain yet, or the shares
      // are gone (sold, or claimed already). The refresh puts the card
      // back in its awaiting state, or drops it.
      showMessageSnackBar(
        context: context,
        message: e is PolymarketNothingToClaimException
            ? context.l10n.betClaimNothingHeld
            : context.l10n
                .betClaimResultRecording(formatPolyAmount(ref, pos.size)),
        error: false,
        info: true,
      );
      try {
        ref.read(polymarketTradingProvider.notifier).refresh();
      } catch (_) {}
      return false;
    }
    final raw = e.toString().toLowerCase();
    final alreadyClaimed =
        raw.contains('zero position') || raw.contains('precheck_skipped');
    showMessageSnackBar(
      context: context,
      message: alreadyClaimed
          ? context.l10n.betAlreadyClaimedRefreshing
          : polymarketErrorCopy(context, e),
      error: !alreadyClaimed,
    );
    if (alreadyClaimed) {
      try {
        ref.read(polymarketTradingProvider.notifier).refresh();
      } catch (_) {}
    }
    return false;
  } finally {
    _claimsInFlight.remove(pos.marketId);
  }
}

/// The Claim ("Claim $4.53") or Clear button of a resolved position, running
/// [claimPolymarketPosition] on one tap. [compact] is the card's small
/// button; otherwise the full-width action of the position screen.
class PolyClaimButton extends ConsumerStatefulWidget {
  final PolymarketPosition position;
  final String surface;
  final bool compact;
  final bool popRoute;

  /// The full-width button's label; the card's says the payout.
  final String? label;
  final IconData? icon;

  const PolyClaimButton({
    super.key,
    required this.position,
    required this.surface,
    this.compact = false,
    this.popRoute = false,
    this.label,
    this.icon,
  });

  @override
  ConsumerState<PolyClaimButton> createState() => _PolyClaimButtonState();
}

class _PolyClaimButtonState extends ConsumerState<PolyClaimButton> {
  bool _claiming = false;

  Future<void> _claim() async {
    if (_claiming) return;
    setState(() => _claiming = true);
    await claimPolymarketPosition(context, ref, widget.position,
        surface: widget.surface, popRoute: widget.popRoute);
    if (mounted) setState(() => _claiming = false);
  }

  @override
  Widget build(BuildContext context) {
    final pos = widget.position;
    // A redeem already sent and still propagating through the lagging Data
    // API keeps the button locked, so a claim that went through is not
    // fired again.
    final clearing = ref.watch(polymarketTradingProvider.select((s) =>
        s.valueOrNull?.clearingConditionIds.contains(pos.marketId) ?? false));
    final busy = _claiming || clearing;
    final won = pos.won == true;
    final l10n = context.l10n;
    final text = widget.label ??
        (won
            ? l10n.betClaimAmount(formatPolyAmount(ref, pos.size))
            : l10n.betClearPosition);
    if (widget.compact) {
      return AppButton(
        text: text,
        compact: true,
        isLoading: busy,
        onPressed: busy ? null : _claim,
      );
    }
    return AppButton(
      text: text,
      icon: widget.icon,
      isLoading: busy,
      onPressed: busy ? null : _claim,
      variant: won ? AppButtonVariant.moneyIn : AppButtonVariant.primary,
      fontWeight: FontWeight.w800,
    );
  }
}
