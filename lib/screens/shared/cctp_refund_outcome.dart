// lib/screens/shared/cctp_refund_outcome.dart
//
// What became of an Investing move by CCTP (cctp_withdrawal.dart) whose
// one-time Orchestra quote from `arbitrum:USDC` was refunded: the USDC went
// back to the wallet's own EVM address on Arbitrum (account zero, the same
// address as its Hyperliquid account), where the app cannot move it (the
// address holds no ETH for gas and Kute has no relayer for it). Said only
// in that move's Activity detail (founder decision October 2026: no line
// on the Investing header or the Portfolio tile, no balance reads), from
// the row alone: its refunded status and the refund address on the record.
//
// Two plain captions: where it went (the address short, tap to copy), and
// how to move it. The second depends on the wallet's EVM key format
// (EvmWalletDerivation): the standard format is m/44'/60'/0'/0/0 from the
// recovery phrase, the account MetaMask opens from the same words; the
// legacy format stretches the phrase differently (PBKDF2-HMAC-SHA256), so
// MetaMask would open another, empty account. A legacy wallet, or one the
// row cannot be tied to, is told to contact Support instead.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/evm_derivation_version.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/shared/message_display.dart'
    show showMessageSnackBarInfo;
import 'package:kute/screens/shared/send/send_flow_widgets.dart'
    show sendShortAddress;
import 'package:kute/services/orchestra/standing_deposit_activity.dart'
    show
        kHypercoreCctpBtcRouteVersion,
        kHypercoreCctpPredictionsRouteVersion,
        kHypercoreCctpRouteVersion;
import 'package:kute/services/orchestra_routes.dart'
    show orchestraChainDisplayName;
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// Row-id prefix of a CCTP move's Arbitrum leg (cctp_withdrawal.dart's
/// `kCctpRowPrefix`, repeated here so this file needs none of its ports).
const String _cctpRowPrefix = 'cctp-';

/// Whether [row] is an Investing move by CCTP whose Orchestra order was
/// refunded: its USDC went back to the wallet's own EOA on Arbitrum.
bool isRefundedCctpMoveRow(SwapOrder row) =>
    row.status == 'refunded' &&
    (row.id.startsWith(_cctpRowPrefix) ||
        const {
          kHypercoreCctpRouteVersion,
          kHypercoreCctpBtcRouteVersion,
          kHypercoreCctpPredictionsRouteVersion,
        }.contains(row.routeVersion));

/// The refunded CCTP move's lines in its Activity detail (see the file
/// header); nothing for any other row, or one with no refund address.
class CctpRefundOutcome extends ConsumerWidget {
  const CctpRefundOutcome({super.key, required this.row});

  final SwapOrder row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final refund = row.refundAddress.trim();
    if (!isRefundedCctpMoveRow(row) || refund.isEmpty) {
      return const SizedBox.shrink();
    }
    final walletId = row.walletId;
    final standard = ref.watch(settingsProvider.select((s) =>
        walletId != null &&
        s.wallets
                .where((w) => w.id == walletId)
                .firstOrNull
                ?.evmDerivationVersion ==
            EvmDerivationVersion.standardBip39));
    final l10n = context.l10n;
    final c = context.colors;
    final note = TextStyle(color: c.textSecondary, fontSize: 14.sp);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: 8.h),
        // The whole line copies the full address, as the detail's other
        // copiable values do (the same small copy glyph).
        GestureDetector(
          key: const ValueKey('cctp-move-returned'),
          behavior: HitTestBehavior.opaque,
          onTap: () {
            TrackingService.addressCopied('cctp_refund');
            Clipboard.setData(ClipboardData(text: refund));
            showMessageSnackBarInfo(
                context: context, message: l10n.copiedToClipboard);
          },
          child: Text.rich(
            TextSpan(children: [
              TextSpan(
                  text: l10n.cctpRefundReturnedTo(
                      orchestraChainDisplayName('arbitrum'),
                      sendShortAddress(refund))),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: EdgeInsets.only(left: 6.w),
                  child:
                      Icon(Icons.copy_rounded, color: c.accent, size: 12.sp),
                ),
              ),
            ]),
            style: note,
          ),
        ),
        SizedBox(height: 4.h),
        Text(
          standard
              ? l10n.cctpRefundMoveWithWallet
              : l10n.cctpRefundContactSupport,
          key: const ValueKey('cctp-move-returned-how'),
          style: note,
        ),
      ],
    );
  }
}
