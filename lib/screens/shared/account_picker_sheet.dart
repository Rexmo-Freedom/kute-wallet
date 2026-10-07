// Shared account-picker bottom sheet.
//
// One widget, one UX, every action screen.
//
// Usage:
//
//   final picked = await AccountPickerSheet.show(
//     context,
//     title: 'Send from',
//     // Restrict to accounts that can sign tx (Send / Move flows).
//     filter: (a) => a.capabilities.canSend,
//     selectedAccountId: currentAccount.id,
//   );
//   if (picked != null) setState(() => _account = picked);
//
// Returns the picked `Account`, or `null` if the user dismissed
// without selecting. Sheets share the look/feel of
// `home_wallet_switcher.dart`'s `WalletSwitcherSheet` so the user
// never has to relearn the layout.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/account.dart';
import 'package:kute/providers/accounts_provider.dart';
import 'package:kute/screens/shared/wallet_icon.dart';
import 'package:kute/theme/app_theme.dart';

class AccountPickerSheet extends ConsumerWidget {
  final String title;
  final bool Function(Account) filter;
  final String? selectedAccountId;

  const AccountPickerSheet({
    super.key,
    required this.title,
    required this.filter,
    this.selectedAccountId,
  });

  /// Open the picker. Returns the picked Account, or null on dismiss.
  static Future<Account?> show(
    BuildContext context, {
    required String title,
    bool Function(Account)? filter,
    String? selectedAccountId,
  }) {
    return showModalBottomSheet<Account>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      builder: (_) => AccountPickerSheet(
        title: title,
        filter: filter ?? ((_) => true),
        selectedAccountId: selectedAccountId,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final accounts =
        ref.watch(accountsListProvider).where(filter).toList();

    // Group by type for clarity. Order mirrors the home pager
    // (Spending → Hardware → Watch-only → Tracked → Signer).
    final spending = accounts
        .where(
            (a) => a is BtcSpendingAccount || a is UsdcSpendingAccount)
        .toList();
    final hardware = accounts
        .where((a) =>
            a is BtcColdAccount && a.kind == ColdAccountKind.hardware)
        .toList();
    final watchOnly = accounts
        .where((a) =>
            a is BtcColdAccount && a.kind == ColdAccountKind.watchOnly)
        .toList();
    final tracked = accounts
        .where((a) =>
            a is BtcColdAccount && a.kind == ColdAccountKind.tracked)
        .toList();
    final signer = accounts
        .where((a) =>
            a is BtcColdAccount && a.kind == ColdAccountKind.signer)
        .toList();

    final software = accounts.where((a) => a is BtcColdAccount && a.kind == ColdAccountKind.software).toList();
    final sections = <_Section>[
      if (spending.isNotEmpty) _Section(context.l10n.spending, spending),
      if (hardware.isNotEmpty)
        _Section(context.l10n.accountHardwareWallets, hardware),
      if (watchOnly.isNotEmpty)
        _Section(context.l10n.accountWatchOnly, watchOnly),
      if (software.isNotEmpty) _Section('Bitcoin wallets', software),
      if (tracked.isNotEmpty) _Section(context.l10n.activityTracked, tracked),
      if (signer.isNotEmpty)
        _Section(context.l10n.activitySignerDevices, signer),
    ];

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28.r)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 10.h),
            Container(
              width: 36.w,
              height: 4.h,
              decoration: BoxDecoration(
                color: c.dragHandle,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            SizedBox(height: 16.h),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 22.sp,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ),
            SizedBox(height: 16.h),
            if (sections.isEmpty)
              Padding(
                padding: EdgeInsets.fromLTRB(20.w, 24.h, 20.w, 32.h),
                child: Text(
                  context.l10n.activityNoAccountsMatchAction,
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 15.sp,
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 24.h),
                  itemCount: sections.length,
                  itemBuilder: (_, i) => _SectionView(
                    section: sections[i],
                    selectedId: selectedAccountId,
                    onPick: (a) {
                      HapticFeedback.selectionClick();
                      Navigator.of(context).pop(a);
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Section {
  final String title;
  final List<Account> items;
  const _Section(this.title, this.items);
}

class _SectionView extends StatelessWidget {
  final _Section section;
  final String? selectedId;
  final ValueChanged<Account> onPick;

  const _SectionView({
    required this.section,
    required this.selectedId,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(4.w, 14.h, 4.w, 8.h),
          child: Text(
            section.title.toUpperCase(),
            style: TextStyle(
              color: c.textTertiary,
              fontSize: 13.sp,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: c.surfaceLight,
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(color: c.borderSubtle, width: 0.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (int i = 0; i < section.items.length; i++) ...[
                if (i > 0) Divider(height: 1, color: c.borderSubtle),
                _AccountRow(
                  account: section.items[i],
                  selected: section.items[i].id == selectedId,
                  onTap: () => onPick(section.items[i]),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _AccountRow extends StatelessWidget {
  final Account account;
  final bool selected;
  final VoidCallback onTap;

  const _AccountRow({
    required this.account,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Resolve the wallet's brand SVG (Ledger / Jade /
    // Passport / SeedSigner / Keystone / Kute-dog spending) so each
    // row shows the actual device, not a generic Bitcoin icon.
    // Bare SVG, no tinted disc — the icon IS the identity here.
    final w = account.wallet;
    final visual = w != null
        ? WalletVisual.fromWallet(
            walletType: w.walletType,
            isHardware: w.isHardware,
            isWatchOnly: w.isWatchOnly,
            isSigner: w.isSigner,
            isDark: Theme.of(context).brightness == Brightness.dark,
          )
        : null;
    Widget leadingIcon;
    if (visual?.svgAsset != null) {
      leadingIcon = SvgPicture.asset(
        visual!.svgAsset!,
        width: 28.sp,
        height: 28.sp,
        colorFilter: visual.color == Colors.white ||
                visual.color == const Color(0xFF333333)
            ? ColorFilter.mode(c.textPrimary, BlendMode.srcIn)
            : null,
      );
    } else if (visual != null) {
      // Walletype without a brand SVG (krux, generic) — fallback
      // to the visual's IconData at the same 28.sp size.
      leadingIcon = Icon(
        visual.icon,
        size: 28.sp,
        color: visual.color == Colors.white ? c.textPrimary : visual.color,
      );
    } else {
      // Non-wallet account (rare in practice) — keep the legacy
      // path so we don't lose a leading slot.
      leadingIcon = SvgPicture.asset(
        account.iconAsset,
        width: 28.sp,
        height: 28.sp,
      );
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(14.w, 12.h, 14.w, 12.h),
          child: Row(
            children: [
              SizedBox(
                width: 36.sp,
                height: 36.sp,
                child: Center(child: leadingIcon),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      account.name,
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      account.subtitle,
                      style: TextStyle(
                        color: c.textSecondary,
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(
                  Icons.check_circle_rounded,
                  color: account.accent,
                  size: 22.sp,
                )
              else
                Icon(
                  Icons.chevron_right_rounded,
                  color: c.textTertiary,
                  size: 20.sp,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
