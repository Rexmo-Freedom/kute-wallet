// Account-switcher pill — the Revolut-style "current context"
// chip that lives at the top of every action screen (Receive /
// Send / Move / Pay Link / Deposit / bet slip).
//
// Renders the currently-selected Account (icon + name + subtitle)
// with a chevron-down. Tapping opens `AccountPickerSheet` filtered
// to whatever the action allows (e.g., Send shows only sign-capable
// accounts), and on pick updates the global selection providers so
// the new context flows back to Home + every other screen.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:kute/models/account.dart';
import 'package:kute/providers/accounts_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/home/components/wallet_cards.dart'
    show selectedWalletCardProvider, WalletCardType;
import 'package:kute/screens/shared/account_picker_sheet.dart';
import 'package:kute/screens/shared/wallet_icon.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

class AccountSwitcherPill extends ConsumerWidget {
  /// "Send from", "Receive into", "Deposit to", etc. Surfaced as
  /// the picker sheet's title when the pill is tapped.
  final String pickerTitle;

  /// Restricts the picker to accounts that match this predicate.
  /// Defaults to "any account" (no filter).
  final bool Function(Account)? filter;

  /// Optional override — when null, the pill reads
  /// `selectedAccountProvider`. Pass an explicit Account when the
  /// caller wants to control the displayed account independently
  /// (e.g., during a multi-step flow that has its own local state).
  final Account? account;

  /// Fired when the user picks a different account.
  ///
  /// **Action screens (Receive, Send, Move, Pay Link, Deposit)
  /// MUST pass an `onPicked` that updates only their local state.**
  /// Don't let an in-flow account swap mutate the home context —
  /// that's reserved for the home top-bar wallet switcher.
  ///
  /// When `onPicked` is null (the home top-bar pill is the only
  /// caller that should rely on this), the default behavior is to
  /// write `setActiveWallet` + `selectedWalletCardProvider` so the
  /// global context follows the pick.
  final void Function(Account picked)? onPicked;

  /// Action flows keep the account they were opened from. Display its identity
  /// without a dropdown, tap action, or account-picker semantics.
  final bool readOnly;

  const AccountSwitcherPill({
    super.key,
    required this.pickerTitle,
    this.filter,
    this.account,
    this.onPicked,
    this.readOnly = false,
  });

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final current = account ?? ref.read(selectedAccountProvider);
    final picked = await AccountPickerSheet.show(
      context,
      title: pickerTitle,
      filter: filter,
      selectedAccountId: current?.id,
    );
    if (picked == null) return;
    if (onPicked != null) {
      onPicked!(picked);
      return;
    }
    // Default behavior — write the pick back to the global state
    // so the home cards + every other action screen pick it up.
    if (picked.wallet != null) {
      await ref
          .read(settingsProvider.notifier)
          .setActiveWallet(picked.wallet!.id);
    }
    final asset = picked is UsdcSpendingAccount
        ? WalletCardType.usdc
        : WalletCardType.bitcoin;
    ref.read(selectedWalletCardProvider.notifier).state = asset;
    // Categorical pool label only — switching to 'usdc' is the toggle
    // that routes Receive/Deposit to USDC. No wallet id, no amount.
    TrackingService.accountPoolSwitched(
        asset == WalletCardType.usdc ? 'usdc' : 'bitcoin');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final acc = account ?? ref.watch(selectedAccountProvider);
    if (acc == null) return const SizedBox.shrink();

    // Chromeless inline pill — drops the surface bg + border so
    // the AppBar title doesn't feel like a free-floating sticker
    // dislocated from the rest of the page. Reads as one
    // consolidated label + chevron, like a stock title with a
    // disclosure indicator (App Store / Robinhood pattern).
    //
    // Label preference: wallet name (e.g. "Spending wallet",
    // "Cold storage"), then fall back to the account asset name
    // ("Bitcoin"/"USDC") when no wallet is attached. The asset is
    // already implied by the QR + address below, so the title's
    // job is to identify the destination WALLET, not the asset.
    final walletName = acc.wallet?.name;
    final label =
        (walletName != null && walletName.isNotEmpty) ? walletName : acc.name;

    // Resolve the wallet's brand SVG (Ledger / Jade / Passport /
    // Spending dog / Watch-only eye / etc.) and render it leading
    // the label so the pill shows the actual wallet — not a
    // generic Bitcoin glyph. USDC accounts ride the spending
    // wallet's visual since they share that wallet's identity
    // (the Polymarket Safe is a sub-balance, not a separate
    // device).
    final w = acc.wallet;
    final visual = w != null
        ? WalletVisual.fromWallet(
            walletType: w.walletType,
            isHardware: w.isHardware,
            isWatchOnly: w.isWatchOnly,
            isSigner: w.isSigner,
            isDark: Theme.of(context).brightness == Brightness.dark,
          )
        : null;
    Widget? leading;
    if (visual?.svgAsset != null) {
      // Bare SVG, no tinted disc around it — matches the destination
      // picker tile treatment so the Send-from / Receive-into row
      // reads as the wallet's brand identity, not a button.
      leading = Padding(
        padding: EdgeInsets.only(right: 8.w),
        child: SvgPicture.asset(
          visual!.svgAsset!,
          width: 22.sp,
          height: 22.sp,
          colorFilter: visual.color == Colors.white ||
                  visual.color == const Color(0xFF333333)
              ? ColorFilter.mode(c.textPrimary, BlendMode.srcIn)
              : null,
        ),
      );
    } else if (visual != null) {
      // Fallback to the IconData when the wallet type has no SVG
      // logo (krux, generic). Keeps the leading slot consistent.
      leading = Padding(
        padding: EdgeInsets.only(right: 8.w),
        child: Icon(visual.icon, size: 22.sp, color: c.textPrimary),
      );
    }

    final title = Padding(
      padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 4.h),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) leading,
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 17.sp,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
          ),
          if (!readOnly) ...[
            SizedBox(width: 4.w),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              color: c.textSecondary,
              size: 22.sp,
            ),
          ],
        ],
      ),
    );
    if (readOnly) return Semantics(header: true, child: title);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.lightImpact();
        _open(context, ref);
      },
      child: title,
    );
  }
}
