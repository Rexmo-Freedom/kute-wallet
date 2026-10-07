import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/asset_icon_provider.dart' show kBitcoinMarkAsset;
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/send_tx_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/providers/viewed_wallet_provider.dart';
import 'package:kute/providers/wallet_scope_provider.dart';
import 'package:kute/screens/home/components/action_pill.dart'
    show selectedNetworkTypeProvider;
import 'package:kute/screens/home/components/deposit_sheet.dart';
import 'package:kute/screens/shared/capability_unavailable_sheet.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/pool_balance_header.dart';
import 'package:kute/screens/home/components/kute_bottom_action_bar.dart';
import 'package:kute/services/onramp_visibility.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';

bool _pinBitcoinWallet(
    BuildContext context, WidgetRef ref, WalletConfig wallet) {
  final settings = ref.read(settingsProvider);
  if (!settings.wallets.any((entry) => entry.id == wallet.id) ||
      (wallet.isSparkWallet && settings.activeWalletId != wallet.id)) {
    showMessageSnackBar(
        context: context,
        message: context.l10n.walletActionsWalletChanged,
        error: true);
    return false;
  }
  final scope = wallet.isSparkWallet ? null : wallet.id;
  ref.read(bdkScopeWalletIdProvider.notifier).state = scope;
  ref.read(viewedWalletIdProvider.notifier).state = scope;
  return true;
}

/// The dock's two money verbs for a bitcoin surface. A tracked address or a
/// paired signer has nothing to sign with, so Send renders disabled there,
/// exactly as the sheet tile used to. The dock itself emits the
/// `quick_action_tapped` event for both buttons.
/// Receive on the left, Send on the right. Money coming in reads first,
/// and the order matches the way the two are arranged everywhere else.
List<KuteDockAction> bitcoinWalletDockActions(
    BuildContext context, WidgetRef ref, WalletConfig wallet) {
  return [
    KuteDockAction(
      icon: Icons.south_west_rounded,
      label: context.l10n.receive,
      trackingId: 'receive',
      onTap: () {
        if (!_pinBitcoinWallet(context, ref, wallet)) return;
        ref.read(selectedNetworkTypeProvider.notifier).state =
            'Bitcoin Network';
        context.pushNamed('receive');
      },
    ),
    KuteDockAction(
      icon: Icons.north_east_rounded,
      label: context.l10n.send,
      trackingId: 'send',
      onTap: wallet.isExternalAddress || wallet.isSigner
          ? null
          : () {
              if (!_pinBitcoinWallet(context, ref, wallet)) return;
              ref.read(sendTxProvider.notifier).resetToDefault();
              context.pushNamed('pay_send');
            },
    ),
  ];
}

/// Same purchase and camera controls for Home and the displayed cold wallet.
class BitcoinWalletPrimaryActions extends ConsumerWidget {
  const BitcoinWalletPrimaryActions(
      {super.key,
      required this.wallet,
      required this.source,
      this.showScan = true});
  final WalletConfig wallet;
  final String source;

  /// The scan chip beside Purchase. False on the Dollars account, which
  /// has nothing to scan: the scanner reads bitcoin and Lightning.
  final bool showScan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Purchase opens Buy bitcoin and is always drawn (founder decision,
    // October 2026). The spending account can always pay from the dollar
    // balance, so its Purchase always opens the buy. A savings wallet has
    // nothing to pay with but an onramp: with none on offer, or no policy,
    // its tap opens the "no purchase providers" sheet instead.
    final scan = PoolHeaderShortcut(
      label: context.l10n.scan,
      icon: Icons.qr_code_scanner_rounded,
      showLabel: false,
      onTap: () {
        TrackingService.quickAction('scan', source: source);
        if (!_pinBitcoinWallet(context, ref, wallet)) return;
        ref.read(sendTxProvider.notifier).resetToDefault();
        context.pushNamed('smartScanner');
      },
    );
    return Row(children: [
      Expanded(
          child: Padding(
              padding: EdgeInsets.only(top: 12.h),
              child: AppButton(
                // Named and marked the way the Dollars screen names and
                // marks its own deposit door, so the two read as the
                // same control pointed at two balances.
                text: context.l10n.purchaseBitcoin,
                svgAsset: kBitcoinMarkAsset,
                onPressed: () {
                  TrackingService.quickAction('purchase', source: source);
                  if (!wallet.isSparkWallet &&
                      !anyOnrampVisible(
                          ref.read(runtimeCapabilitiesProvider))) {
                    showBuyUnavailableSheet(context);
                    return;
                  }
                  if (!_pinBitcoinWallet(context, ref, wallet)) return;
                  showDepositSheet(
                    context,
                    lockedSide: MoveLockedSide.depositFromFiat,
                    fiatDepositWalletId:
                        wallet.isSparkWallet ? null : wallet.id,
                  );
                },
              ))),
      if (showScan) ...[
        SizedBox(width: 10.w),
        scan,
      ],
    ]);
  }
}
