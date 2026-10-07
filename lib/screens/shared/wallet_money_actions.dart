import 'package:kute/helpers/require_fresh_auth.dart';
import 'package:kute/screens/shared/trade_results_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart' show WalletConfig;
import 'package:kute/providers/add_wallet_return_provider.dart';
import 'package:kute/providers/shell_wallet_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/kute_back_button.dart'
    show KuteCirclePillButton;
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/providers/asset_icon_provider.dart' show kUsdMarkAsset;
import 'package:kute/screens/home/shell_venue_tabs.dart'
    show shellShowsPredictionsTab, shellShowsTradingTab;
import 'package:kute/screens/shared/wallet_icon.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// The Financial hub: the wallet list, switch wallet (with its step-up) and
/// Add wallet, and Settings (a labelled pill) and Notifications (the round
/// bell) side by side in its header. It opens from the + at the top right of the shell's top bar (the
/// only door on the shell; it replaced the Settings gear) and from the
/// wallet's name on a pushed wallet screen, which has no +. The dock's
/// square button is search everywhere (owner decision: give each job one
/// home). No Ask Sal here: Sal has its own doors.
///
/// [source] is the categorical door for `wallet_actions_opened`:
/// home_plus | usd_plus | trading_plus | predictions_plus | bank_plus (the
/// + on that tab) | wallet_detail (a wallet screen's name).
void showWalletMoneyActions(
  BuildContext context, {
  required String source,
}) {
  // One sheet at a time: a second tap while it slides in does nothing.
  const key = 'wallet_money_actions';
  if (OpenOnce.isOpen(key)) return;
  TrackingService.track('wallet_actions_opened', params: {'source': source});
  OpenOnce.run(
    key,
    () => showAppBottomSheet<void>(
      context: context,
      builder: (_) => _WalletMoneyActionsSheet(
        callerContext: context,
        source: source,
      ),
    ),
  );
}

class _WalletMoneyActionsSheet extends StatelessWidget {
  const _WalletMoneyActionsSheet({
    required this.callerContext,
    required this.source,
  });

  final BuildContext callerContext;
  final String source;

  @override
  Widget build(BuildContext context) {
    return AppBottomSheetContainer(
      maxHeight: 0.90,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBottomSheetHeader(
              title: context.l10n.walletActionsTitle,
              // Settings and Notifications side by side in the header:
              // Settings a labelled pill in the circled chassis of the
              // sheets' header buttons, Notifications the round bell with
              // its unread badge.
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _HubSettingsButton(callerContext: callerContext),
                  SizedBox(width: 8.w),
                  const TradeResultsButton(
                      compact: true, entrySource: 'financial_hub'),
                ],
              ),
            ),
            _WalletsSection(
              sheetContext: context,
              callerContext: callerContext,
              source: source,
            ),
          ],
        ),
      ),
    );
  }
}

/// Settings in the hub's header, next to Notifications: the gear and the
/// word "Settings" in a pill of the header buttons' chassis (owner
/// decision October 2026: a labelled button beside the bell, not a row
/// below Add account). Closes the hub and opens /settings from the screen
/// the hub was opened on, as Add wallet does.
class _HubSettingsButton extends StatelessWidget {
  const _HubSettingsButton({required this.callerContext});

  final BuildContext callerContext;

  @override
  Widget build(BuildContext context) {
    return KuteCirclePillButton(
      icon: Icons.settings_rounded,
      label: context.l10n.settings,
      onPressed: () {
        // `source` kept for the existing settings_opened breakdowns;
        // the playbook's entry_source carries the same door.
        TrackingService.track('settings_opened', params: {
          'source': 'financial_hub',
          'entry_source': 'financial_hub',
        });
        Navigator.of(context).pop();
        if (!callerContext.mounted) return;
        callerContext.push('/settings');
      },
    );
  }
}

/// The wallet roster that used to sit on Home as a chip strip: every added
/// wallet except signers (signer mode is its own surface). A row makes that
/// wallet the FIRST TAB of the shell instead of pushing a screen with its
/// own app bar and back button (user decision September 2026), and the
/// spending wallet's row is the way back to Home. `activeWalletId` is never
/// touched; the shell scopes BDK sync to the wallet itself. The wallet
/// currently on the first tab wears a check mark. Name only, no balance
/// (user decision: the wallet's own tab carries the number). A Ledger row
/// also shows the two venues it carries.
class _WalletsSection extends ConsumerWidget {
  const _WalletsSection({
    required this.sheetContext,
    required this.callerContext,
    required this.source,
  });

  final BuildContext sheetContext;
  final BuildContext callerContext;
  final String source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final settings = ref.watch(settingsProvider);
    final spending = pickSpendingWallet(settings);
    final wallets = settings.wallets.where((w) => !w.isSigner).toList();
    // The wallet the shell's first tab is showing; null means the spending
    // account, so its row is the one wearing the check mark then.
    final shellWalletId = ref.watch(shellWalletIdProvider);

    Future<void> openWallet(WalletConfig wallet) async {
      HapticFeedback.selectionClick();
      // Another account's balances and actions only come up once the
      // person has proved it is them, the same check removing a wallet
      // asks for. Re-tapping the wallet already shown asks nothing.
      final targetId = spending != null && wallet.id == spending.id
          ? null
          : wallet.id;
      if (targetId != shellWalletId) {
        final approved = await approveLocalAction(
          sheetContext,
          ref,
          intent: walletSwitchIntent(wallet.id),
          reason: sheetContext.l10n.stepUpReasonSwitchWallet(wallet.name),
        );
        if (!approved || !sheetContext.mounted) return;
      }
      // wallet_id deliberately NOT tracked (leaky correlator): the
      // categorical wallet_type only, same as the strip chip event.
      TrackingService.track('home_wallet_chip_tapped', params: {
        'wallet_type': wallet.walletType,
        'source': source,
      });
      final isSpending = spending != null && wallet.id == spending.id;
      TrackingService.track('shell_wallet_tab_selected', params: {
        'wallet_type': wallet.walletType,
        'spending': isSpending,
        'source': source,
      });
      // Mount the wallet on the first tab instead of pushing its screen.
      ref.read(shellWalletIdProvider.notifier).state =
          isSpending ? null : wallet.id;
      Navigator.of(sheetContext).pop();
      if (!callerContext.mounted) return;
      // Land on that first tab from wherever the sheet was opened.
      callerContext.go('/home');
    }

    void addWallet() {
      HapticFeedback.selectionClick();
      TrackingService.track('home_add_wallet_tapped', params: {
        'source': source,
      });
      // Land back on Home when the add flow completes (same target the
      // strip's Add wallet chip set).
      ref.read(addWalletReturnRouteProvider.notifier).state = '/home';
      Navigator.of(sheetContext).pop();
      if (!callerContext.mounted) return;
      callerContext.pushNamed('addWallet');
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 8.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The sheet's header already names it, so the list wears
          // no label of its own: one grouped card, rows split by hairlines.
          Container(
            decoration: BoxDecoration(
              color: c.surfaceLight,
              borderRadius: BorderRadius.circular(20.r),
              border: Border.all(color: c.borderSubtle, width: 0.5),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final wallet in wallets) ...[
                  _WalletRow(
                    label:
                        wallet.name.isNotEmpty ? wallet.name : 'Bitcoin Wallet',
                    leading: _WalletMark(wallet: wallet),
                    isActive: shellWalletId == null
                        ? (spending != null && wallet.id == spending.id)
                        : wallet.id == shellWalletId,
                    // Both the spending account and a Ledger carry
                    // Investing (Hyperliquid) and Predictions
                    // (Polymarket) as tabs of their own, so each row
                    // shows the two venue marks at a glance. A plain
                    // Bitcoin or watch-only account carries neither.
                    showDollars: wallet.isSparkWallet,
                    // A Ledger shows only the venues it has in this build
                    // (Ledger Investing / Predictions on), the same tabs
                    // the strip draws for it; none while both are off.
                    showInvesting: shellShowsTradingTab(wallet),
                    showPredictions: shellShowsPredictionsTab(wallet),
                    onTap: () => openWallet(wallet),
                  ),
                  Divider(height: 0.5, thickness: 0.5, color: c.borderSubtle),
                ],
                // Always offered: a way to add a wallet that Kute withholds
                // says so on Add wallet when tapped, it is never hidden.
                _WalletRow(
                  label: context.l10n.addWallet,
                  leading: Icon(Icons.add_rounded,
                      size: 20.sp, color: c.textPrimary),
                  isActive: false,
                  onTap: addWallet,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WalletRow extends StatelessWidget {
  const _WalletRow({
    required this.label,
    required this.leading,
    required this.isActive,
    required this.onTap,
    this.showInvesting = false,
    this.showPredictions = false,
    this.showDollars = false,
  });

  final String label;
  final Widget leading;
  final bool isActive;
  final VoidCallback onTap;

  /// Show the Hyperliquid and Polymarket marks on the right, for a wallet
  /// that carries both venues as tabs of its own.
  final bool showInvesting;
  final bool showPredictions;

  /// The spending account carries Dollars too; a Ledger does not.
  final bool showDollars;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
          child: Row(
            children: [
              SizedBox(
                width: 36.w,
                height: 36.w,
                child: Center(child: leading),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              SizedBox(width: 8.w),
              if (showInvesting || showPredictions) ...[
                _VenueMarks(
                  withDollars: showDollars,
                  investing: showInvesting,
                  predictions: showPredictions,
                ),
                SizedBox(width: 10.w),
              ],
              Icon(
                isActive ? Icons.check_rounded : Icons.chevron_right_rounded,
                size: 20.sp,
                color: isActive ? c.textPrimary : c.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The venue marks a Ledger row carries: the same Hyperliquid and
/// Polymarket logos the nav strip and the Ledger tabs already use.
class _VenueMarks extends StatelessWidget {
  const _VenueMarks({
    this.withDollars = false,
    this.investing = true,
    this.predictions = true,
  });

  /// The spending account also carries Dollars as a tab of its own, so
  /// its row shows that mark beside the two venues. A Ledger does not.
  final bool withDollars;

  /// Which venue marks to draw: a Ledger draws only the venues it has.
  final bool investing;
  final bool predictions;

  @override
  Widget build(BuildContext context) {
    final size = 18.sp;
    final l10n = context.l10n;
    return Semantics(
      label: [
        if (investing) l10n.ledgerTabInvestingSemantics,
        if (predictions) l10n.ledgerTabPredictionsSemantics,
        if (withDollars) l10n.usdAccountTab,
      ].join(', '),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (withDollars) ...[
            SvgPicture.asset(kUsdMarkAsset, width: size, height: size),
            if (investing || predictions) SizedBox(width: 6.w),
          ],
          if (investing)
            SvgPicture.asset('lib/assets/hyperliquid-logo.svg',
                width: size, height: size),
          if (investing && predictions) SizedBox(width: 6.w),
          if (predictions)
            SvgPicture.asset('lib/assets/polymarket-logo.svg',
                width: size, height: size),
        ],
      ),
    );
  }
}

/// Wallet-type glyph resolved through the same [WalletVisual] table the
/// Add Wallet and detail screens use so the row and the wallet's own
/// screens always agree. Monochrome brand marks tint to textPrimary;
/// colored marks and the tracked-address eye keep their color.
class _WalletMark extends StatelessWidget {
  const _WalletMark({required this.wallet});

  final WalletConfig wallet;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final visual = WalletVisual.fromWallet(
      walletType: wallet.walletType,
      isHardware: wallet.isHardware,
      isWatchOnly: wallet.isWatchOnly || wallet.isExternalAddress,
      isSigner: wallet.isSigner,
      isDark: context.isDark,
    );
    final size = 26.sp;
    if (visual.svgAsset != null) {
      final mono = visual.color == Colors.white ||
          visual.color == const Color(0xFF333333);
      return SvgPicture.asset(
        visual.svgAsset!,
        width: size,
        height: size,
        fit: BoxFit.contain,
        colorFilter:
            mono ? ColorFilter.mode(c.textPrimary, BlendMode.srcIn) : null,
      );
    }
    return Icon(visual.icon, size: size, color: visual.color);
  }
}
