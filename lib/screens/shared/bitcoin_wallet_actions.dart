import 'dart:async';

import 'package:kute/screens/scanner/scanner_sheet.dart';
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
import 'package:kute/screens/receive/receive_sheet.dart'
    show showBitcoinQrReceiveSheet, showBitcoinReceiveSheet;
import 'package:kute/screens/shared/capability_unavailable_sheet.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/pool_balance_header.dart';
import 'package:kute/screens/shared/receive_arrow_glyph.dart';
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
///
/// The spending wallet's Receive opens the Receive sheet (founder, 6 and
/// 7 November 2026; bitcoin_receive_options.dart): Bitcoin, the QR, on
/// top, then From your Dollars and Another crypto. A
/// watch-only or hardware wallet has no Dollars and nothing to receive
/// another coin into, so its Receive opens the QR itself. Every Receive
/// wears the plain receive arrow, moving as the hub's "+" does
/// ([ReceiveArrowGlyph]).
List<KuteDockAction> bitcoinWalletDockActions(
    BuildContext context, WidgetRef ref, WalletConfig wallet) {
  return [
    KuteDockAction(
      icon: Icons.south_west_rounded,
      glyph: receiveArrowGlyph,
      label: context.l10n.receive,
      trackingId: 'receive',
      onTap: () {
        if (!_pinBitcoinWallet(context, ref, wallet)) return;
        ref.read(selectedNetworkTypeProvider.notifier).state =
            'Bitcoin Network';
        // ignore: discarded_futures
        wallet.isSparkWallet
            ? showBitcoinReceiveSheet(context)
            : showBitcoinQrReceiveSheet(context);
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

/// The Unavailable sheet's `surface` when Purchase finds no Cash App.
const String kBitcoinPurchaseSurface = 'bitcoin_purchase';

/// Test seam: stands in for the Cash App purchase Purchase opens
/// ([showDepositSheet], the Buy bitcoin door on Cash App). Receives the
/// savings wallet the bitcoin lands in, null for the spending wallet.
@visibleForTesting
void Function(BuildContext context, {String? fiatDepositWalletId})?
    debugBitcoinPurchaseOpener;

/// PURCHASE IS CASH APP, OR UNAVAILABLE (founder, 7 November 2026:
/// "Bitcoin Purchase is not showing the Unavailable sheet, and it should;
/// only when Cash App is available should it show the purchase"). A buy
/// is money in from outside, and Cash App (`onramp.cashapp`, offered only
/// where the policy offers it, the United States) is the one live way in,
/// so:
///   * Cash App on offer: the Buy bitcoin door opened on Cash App, as
///     Activity's "Create new purchase" opens it, into the spending wallet
///     or the savings wallet whose button it is;
///   * otherwise: the shared Unavailable sheet, never another flow (not
///     the Dollars into Bitcoin move, which is Receive's "From your
///     Dollars"). Outside the United States, Cash App's allow list
///     (`country_not_allowed`) reads just "Not available right now" over
///     "Got it" (founder, 7 November 2026: "not avaliable in usa? my vpn
///     is in lisbon. please just say not avaliable right now"): no region,
///     no VPN sentence, nothing counted as a region block
///     ([CapabilityDecision.notOfferedHere]). A block-list region refusal
///     names the region over the VPN sentence and offers "Check
///     connection" (counted once as `capability_region_blocked` on
///     [kBitcoinPurchaseSurface]); found allowed there, the purchase opens
///     after all. Any other refusal reads "Buy unavailable".
/// The policy is asked again first ([confirmCapability]), so a refusal
/// from an older network or minute never shuts a rail open now. Both
/// Purchase doors (the compact row's square and the big button) open it;
/// the tap itself counts as `quick_action_tapped` `purchase`.
Future<void> openBitcoinPurchase(
    BuildContext context, WidgetRef ref, WalletConfig wallet) async {
  final policy = ref.read(runtimeCapabilitiesProvider);
  final decision = await confirmCapability(policy, kOnrampCashApp);
  if (!context.mounted) return;
  if (!decision.allowed || decision.comingSoon) {
    final l10n = context.l10n;
    // The sheet reads an allow list's refusal as "Not available right
    // now" by itself ([showCapabilityUnavailableSheet]).
    final region = decision.regionBlocked;
    final allowedNow = await showCapabilityUnavailableSheet(
      context,
      title: l10n.buyUnavailableTitle,
      message: region ? decision.bodyIn(l10n) : l10n.buyUnavailableBody,
      regionRestricted: region,
      capabilities: const [kOnrampCashApp],
      denial: (capability: kOnrampCashApp, decision: decision),
      surface: kBitcoinPurchaseSurface,
    );
    if (!allowedNow || !context.mounted) return;
  }
  if (!_pinBitcoinWallet(context, ref, wallet)) return;
  final walletId = wallet.isSparkWallet ? null : wallet.id;
  final open = debugBitcoinPurchaseOpener;
  if (open != null) return open(context, fiatDepositWalletId: walletId);
  showDepositSheet(
    context,
    lockedSide: MoveLockedSide.depositFromFiat,
    fiatDepositWalletId: walletId,
    cashAppSource: true,
  );
}

/// Purchase as one action of the compact row (the primary one, solid):
/// the same door the big Purchase Bitcoin button opens
/// ([openBitcoinPurchase]: Cash App, or the Unavailable sheet).
KuteDockAction bitcoinPurchaseDockAction(
    BuildContext context, WidgetRef ref, WalletConfig wallet,
    {required String source}) {
  return KuteDockAction(
    icon: Icons.currency_bitcoin_rounded,
    label: context.l10n.purchaseShort,
    trackingId: 'purchase',
    solid: true,
    onTap: () => unawaited(openBitcoinPurchase(context, ref, wallet)),
  );
}

/// The scanner as one action of the compact row: the camera, as a sheet
/// over the screen, the same as the square beside Purchase opens.
KuteDockAction bitcoinScanDockAction(
    BuildContext context, WidgetRef ref, WalletConfig wallet) {
  return KuteDockAction(
    icon: Icons.qr_code_scanner_rounded,
    label: context.l10n.scan,
    trackingId: 'scan',
    onTap: () {
      if (!_pinBitcoinWallet(context, ref, wallet)) return;
      ref.read(sendTxProvider.notifier).resetToDefault();
      showRoutingScannerSheet(context);
    },
  );
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
    // Purchase is always drawn (founder decision, October 2026) and opens
    // the Cash App purchase, or the Unavailable sheet where Cash App is
    // not on offer ([openBitcoinPurchase]).
    final scan = PoolHeaderShortcut(
      label: context.l10n.scan,
      icon: Icons.qr_code_scanner_rounded,
      showLabel: false,
      onTap: () {
        TrackingService.quickAction('scan', source: source);
        if (!_pinBitcoinWallet(context, ref, wallet)) return;
        ref.read(sendTxProvider.notifier).resetToDefault();
        showRoutingScannerSheet(context);
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
                  unawaited(openBitcoinPurchase(context, ref, wallet));
                },
              ))),
      if (showScan) ...[
        SizedBox(width: 10.w),
        scan,
      ],
    ]);
  }
}
