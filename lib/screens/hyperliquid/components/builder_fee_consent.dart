import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/services/hyperliquid/hyperliquid_funding_service.dart';
import 'package:kute/services/hyperliquid/hyperliquid_onboarding_service.dart';

/// Registers the builder with the venue so an order can carry Kute's fee.
///
/// This used to stop and ask, on a sheet headed "Approve trading fee" with
/// the builder address behind a Details toggle. It was the wrong thing to
/// put in front of someone about to invest: the fee is already stated on
/// the slip they are looking at, the approval is bounded by the cap the
/// venue enforces, and the address it disclosed means nothing to a person
/// deciding whether to open a position. So it authorizes directly and the
/// slip stays on screen.
///
/// Existing approvals for the published builder still short-circuit; a
/// raised cap or a rotated builder address re-authorizes, exactly like the
/// first approval.
Future<bool> ensureHotHlBuilderFeeConsent(
    BuildContext context, WidgetRef ref) async {
  final walletId = pickSpendingWallet(ref.read(settingsProvider))?.id;
  if (walletId == null) return false;
  final trading = ref.read(hyperliquidTradingProvider.notifier);
  try {
    // The builder comes only from the backend. None published (or the
    // backend unreachable) means the order carries no builder, so there
    // is nothing to approve and trading goes ahead.
    final config = await HyperliquidFundingService.getBuilder();
    if (config == null) return true;
    // The spending wallet can change while the venue call is in flight;
    // authorize for the wallet this started on or not at all.
    if (pickSpendingWallet(ref.read(settingsProvider))?.id != walletId) {
      return false;
    }
    final accepted = await trading.ensureBuilderFeeApproved(reviewed: config);
    // A debug build trades without the builder, so a failed approval is
    // not an obstacle there and must not stop the slip or shout about
    // it. The order path logs the reason. Release still reports it.
    if (kDebugMode && !accepted) return true;
    if (!accepted && context.mounted) {
      // In debug the venue's own words go on screen. "Fee approval was
      // not completed" is the right thing to tell a person and the
      // wrong thing to tell whoever has to fix it, and this failure has
      // already survived several rounds of guessing at it.
      final reason = HyperliquidOnboardingService.lastFailure;
      showMessageSnackBar(
          context: context,
          message: kDebugMode && reason != null
              ? '${context.l10n.investingFeeApprovalFailed} [$reason]'
              : context.l10n.investingFeeApprovalFailed,
          error: true);
    }
    return accepted;
  } catch (_) {
    if (context.mounted) {
      showMessageSnackBar(
          context: context,
          message: context.l10n.investingFeeSettingsUnavailable,
          error: true);
    }
    return false;
  }
}
