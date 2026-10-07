// Detail and funding flows stay pinned to this wallet without changing the
// spending account. The previous display scope is restored when leaving.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kute/screens/shared/kute_blur.dart';
import 'package:kute/screens/shared/wallet_icon.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:kute/constants/feature_flags.dart';
import 'package:kute/screens/ledger/ledger_account_body.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/wallet_removal_step_up.dart';
import 'package:kute/screens/shared/wallet_bitcoin_body.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/analytics_provider.dart';
import 'package:kute/screens/analytics/components/home_analytics_widget.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/providers/transactions_provider.dart';
import 'package:kute/providers/viewed_wallet_provider.dart';
import 'package:kute/providers/home_view_scope_provider.dart';
import 'package:kute/providers/pending_ledger_settlement_provider.dart';
import 'package:kute/providers/wallet_scope_provider.dart';
import 'package:kute/screens/home/components/kute_dock_host.dart';
import 'package:kute/screens/home/home_wallet_switcher.dart';
import 'package:kute/providers/wallet_backup_provider.dart';
import 'package:kute/screens/ledger/ledger_account_action_bar.dart';
import 'package:kute/screens/search/unified_search_screen.dart';
import 'package:kute/screens/shared/wallet_money_actions.dart';
import 'package:kute/screens/shared/custom_alert_dialog.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/services/background_sync_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

class WalletDetailScreen extends ConsumerStatefulWidget {
  final String walletId;

  /// Opened through "Open Ledger account" on a pending Ledger settlement.
  /// Shows the Ledger account body even with `kLedgerInvestingEnabled`
  /// off, but only while that Ledger has a pending operation.
  final bool ledgerAccountView;

  const WalletDetailScreen({
    super.key,
    required this.walletId,
    this.ledgerAccountView = false,
  });

  @override
  ConsumerState<WalletDetailScreen> createState() => _WalletDetailScreenState();
}

class _WalletDetailScreenState extends ConsumerState<WalletDetailScreen> {
  String? _previousViewedId;
  LedgerAccountTab _ledgerTab = LedgerAccountTab.bitcoin;

  /// Snapshot of the home-carousel scope at entry. The home leaves
  /// this set to `'all'` when the user was parked on the All-accounts
  /// page; if we don't reset it, the analytics widget on this detail
  /// screen sums BTC across every wallet instead of just the viewed
  /// one. Restored on dispose so navigating back doesn't strand the
  /// carousel on the wrong scope.
  String? _previousScope;

  @override
  void initState() {
    super.initState();
    // Cold-start the Binance BTC/USD WS the moment the detail screen
    // mounts. By the time the user taps the Price tab → LIVE chip,
    // ticks should already be flowing, so the chart renders on the
    // first frame instead of staring at a placeholder. The singleton
    // honours its own idle-close grace (30s) so we don't leak the
    // connection if the user never reaches the LIVE view.
    prewarmLiveBtcFeed();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _previousViewedId = ref.read(viewedWalletIdProvider);
      _previousScope = ref.read(homeViewScopeProvider);
      ref.read(bdkScopeWalletIdProvider.notifier).state = widget.walletId;
      ref.read(viewedWalletIdProvider.notifier).state = widget.walletId;
      // Clear the home carousel scope so analytics + breakdown
      // surfaces follow the viewed wallet (this screen's wallet)
      // instead of aggregating across all wallets.
      ref.read(homeViewScopeProvider.notifier).state = null;
      ref
          .read(walletBalanceCacheProvider.notifier)
          .invalidateStreamFreshness(widget.walletId);
      // The analytics history chain is built on autoDispose
      // StateProviders; their `ref.watch` deps DO trigger a
      // recompute, but the chart sometimes paints a frame with
      // the previous (active-wallet) data before the new
      // viewedWalletId propagates. Force-invalidate so the very
      // first paint after we enter the detail screen reflects
      // THIS wallet's history, not the spending wallet's.
      ref.invalidate(bitcoinBalanceOverPeriod);
      ref.invalidate(bitcoinBalanceOverPeriodByDayProvider);
      ref.invalidate(bitcoinBalanceInFormatByDayProvider);
      ref.invalidate(bitcoinBalanceStepsProvider);
      // First open of a freshly added wallet auto-runs the one-time full
      // scan so the balance populates without the user having to know to
      // pull. After that first scan completes (firstScanDone persisted),
      // opening is pull-only: ongoing updates come from the user's
      // pull-to-refresh (scroll down). A failed first scan leaves the
      // flag false, so the next open retries until it succeeds.
      final viewed = ref
          .read(settingsProvider)
          .wallets
          .where((w) => w.id == widget.walletId)
          .firstOrNull;
      // Once per mount: which kind of wallet was opened (the route's
      // automatic $screen carries no wallet kind). Never id or name.
      if (viewed != null) {
        TrackingService.track('wallet_detail_viewed', params: {
          'wallet_kind': TrackingService.walletKind(
            isLedger: viewed.isLedger,
            isHardware: viewed.isHardware,
            isWatchOnly: viewed.isWatchOnly,
            isSigner: viewed.isSigner,
            isExternalAddress: viewed.isExternalAddress,
          ),
          'needs_backup': needsWalletBackup(viewed),
          'first_scan_done': viewed.firstScanDone,
        });
      }
      final firstScanDone = ref
          .read(settingsProvider)
          .wallets
          .any((w) => w.id == widget.walletId && w.firstScanDone);
      if (!firstScanDone) {
        unawaited(BackgroundSyncService().scanBdkScope());
      }
    });
  }

  Future<void> _restoreActive() async {
    ref.read(bdkScopeWalletIdProvider.notifier).state = null;
    // Snap viewedWalletId back to the operational active wallet
    // (spending). The earlier behaviour restored `_previousViewedId`
    // captured at init, but when the user navigated to this screen
    // from a home carousel position already parked on this hardware
    // wallet, that "previous" value WAS the hardware id — restoring
    // it left home showing the hardware wallet's analytics (and a
    // valid UTXO tab) after pop, leaking detail-screen state back
    // onto home. Home should always re-anchor to the active wallet
    // on return; the carousel resyncs from there on the next swipe.
    final activeId = ref.read(settingsProvider).activeWalletId;
    if (activeId != null) {
      ref.read(viewedWalletIdProvider.notifier).state = activeId;
    } else if (_previousViewedId != null) {
      ref.read(viewedWalletIdProvider.notifier).state = _previousViewedId;
    }
    // Put the carousel scope back so home picks up where the user
    // left off (All-accounts, Bitcoin-only, etc.).
    ref.read(homeViewScopeProvider.notifier).state = _previousScope;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final settings = ref.watch(settingsProvider);
    final wallet = settings.wallets.cast<WalletConfig?>().firstWhere(
          (w) => w?.id == widget.walletId,
          orElse: () => null,
        );

    if (wallet == null) {
      return PopScope(
        onPopInvokedWithResult: (_, __) => _restoreActive(),
        child: Scaffold(
          backgroundColor: c.background,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: KuteBackButton(
              onBack: _restoreActive,
              // Wealth tab removed — Home hosts the wallets menu now.
              fallbackRoute: '/home',
            ),
          ),
          body: Center(
            child: Text(
              context.l10n.walletNotFound,
              style: TextStyle(color: c.textPrimary, fontSize: 16.sp),
            ),
          ),
        ),
      );
    }

    // Ledger accounts get the three-tab account screen (Wallet hardening
    // Phase 4, P4.4) behind the release flag; every other wallet, and a
    // Ledger with the flag off, keeps today's Bitcoin body unchanged. The
    // one exception (Phase 5 plan B13): opened from a pending Ledger
    // settlement, the account stays reachable while that operation is
    // pending, so turning the flag off never strands it.
    final pendingLedgerView = widget.ledgerAccountView &&
        wallet.isLedger &&
        (ref
                .watch(walletHasPendingLedgerSettlementProvider(wallet.id))
                .valueOrNull ??
            false);
    final isLedgerAccount =
        wallet.isLedger && (kLedgerInvestingEnabled || pendingLedgerView);
    final nameText = Text(
      wallet.name,
      style: TextStyle(
        color: c.textPrimary,
        fontWeight: FontWeight.w800,
        fontSize: 20.sp,
        letterSpacing: -0.4,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    return PopScope(
      onPopInvokedWithResult: (_, __) => _restoreActive(),
      child: Scaffold(
        backgroundColor: c.background,
        body: Container(
          decoration: AppDecorations.screenGradient(context),
          // Home's dock mount: frost band + floating dock, bound to the
          // displayed wallet (Ledger tabs route through
          // LedgerAccountActionBar, never hot-wallet actions).
          child: KuteDockHost(
            dockBuilder: (onHeightChanged) =>
                isLedgerAccount && _ledgerTab != LedgerAccountTab.bitcoin
                    ? LedgerAccountActionBar(
                        walletId: wallet.id,
                        tab: _ledgerTab,
                        onHeightChanged: onHeightChanged,
                      )
                    : WalletBitcoinActionBar(
                        wallet: wallet,
                        onHeightChanged: onHeightChanged,
                        onSearch: () => showKuteSearch(context,
                            walletId: wallet.id, source: 'wallet_detail'),
                      ),
            body: SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(8.w, 8.h, 12.w, 4.h),
                    child: Row(
                      children: [
                        KuteBackButton(
                          onBack: _restoreActive,
                          // Wealth tab removed — back falls through to Home.
                          fallbackRoute: '/home',
                        ),
                        SizedBox(width: 8.w),
                        // The wallet's mark and name are the door to the
                        // Financial hub (switch wallet, Add wallet,
                        // Notifications, Settings): this screen has no
                        // top bar +. Just
                        // the name up here (user decision): the logo beside
                        // it already says which device this is, so no
                        // protected/type subtitle.
                        Expanded(
                          child: Semantics(
                            button: true,
                            label: context.l10n.walletActionsTitle,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                showWalletMoneyActions(context,
                                    source: 'wallet_detail');
                              },
                              child: Row(children: [
                                _WalletLogo(wallet: wallet),
                                SizedBox(width: 10.w),
                                Expanded(child: nameText),
                              ]),
                            ),
                          ),
                        ),
                        WalletMenuButton(
                          wallet: wallet,
                          onRestoreActive: _restoreActive,
                        ),
                      ],
                    ),
                  ),
                  if (needsWalletBackup(wallet))
                    Padding(
                      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 8.h),
                      child: SecurityActionCard(walletId: wallet.id),
                    ),
                  Expanded(
                    child: isLedgerAccount
                        ? LedgerAccountBody(
                            wallet: wallet,
                            onTabChanged: (tab) =>
                                setState(() => _ledgerTab = tab),
                          )
                        : WalletBitcoinBody(wallet: wallet),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class WalletMenuButton extends ConsumerWidget {
  final WalletConfig wallet;
  final Future<void> Function() onRestoreActive;
  const WalletMenuButton({
    super.key,
    required this.wallet,
    required this.onRestoreActive,
  });

  String get _walletKind => TrackingService.walletKind(
        isLedger: wallet.isLedger,
        isHardware: wallet.isHardware,
        isWatchOnly: wallet.isWatchOnly,
        isSigner: wallet.isSigner,
        isExternalAddress: wallet.isExternalAddress,
      );

  void _trackDeleteCancelled(String stage) {
    TrackingService.track('wallet_delete_cancelled', params: {
      'surface': 'wallet_detail',
      'stage': stage,
      'wallet_kind': _walletKind,
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    // Bottom sheet, not the stock PopupMenu overlay — same vocabulary
    // as the top bar's "+" menu (neutral squared icon chips, hairline
    // rows); red stays reserved for the destructive action.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.lightImpact();
        _showActionsSheet(context, ref);
      },
      child: Container(
        width: 44.w,
        height: 44.w,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: c.borderSubtle, width: 0.5),
        ),
        child:
            Icon(Icons.more_horiz_rounded, color: c.textPrimary, size: 20.sp),
      ),
    );
  }

  void _showActionsSheet(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    // Both doors (the ⋯ button and showWalletActionsSheet) land here.
    TrackingService.track('wallet_detail_menu_opened',
        params: {'wallet_kind': _walletKind});
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.only(top: 12.h, bottom: 4.h),
                child: AppDecorations.dragHandle(sheetContext),
              ),
              _sheetRow(
                sheetContext,
                icon: Icons.edit_rounded,
                label: context.l10n.rename,
                onTap: () {
                  TrackingService.track('wallet_menu_option_tapped', params: {
                    'surface': 'wallet_detail',
                    'option': 'rename',
                    'wallet_kind': _walletKind,
                  });
                  _showRenameDialog(context, ref);
                },
              ),
              _sheetRow(
                sheetContext,
                icon: Icons.delete_outline_rounded,
                label: context.l10n.delete,
                destructive: true,
                onTap: () {
                  TrackingService.track('wallet_menu_option_tapped', params: {
                    'surface': 'wallet_detail',
                    'option': 'delete',
                    'wallet_kind': _walletKind,
                  });
                  _handleDeleteRequest(context, ref);
                },
              ),
              SizedBox(height: 8.h),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetRow(
    BuildContext sheetContext, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool destructive = false,
  }) {
    final c = sheetContext.colors;
    final fg = destructive ? c.error : c.textPrimary;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 20.w),
      leading: Container(
        width: 36.w,
        height: 36.w,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.surfaceLight,
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(color: c.borderSubtle, width: 0.5),
        ),
        child: Icon(icon, size: 18.sp, color: fg),
      ),
      title: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 16.sp,
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.of(sheetContext).pop();
        onTap();
      },
    );
  }

  Future<void> _showRenameDialog(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: wallet.name);
    // Never the name: only started / saved / cancelled.
    TrackingService.track('wallet_rename_started',
        params: {'surface': 'wallet_detail'});
    var saved = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (dialogCtx) {
        final c = dialogCtx.colors;
        return KuteBlur(
          sigmaX: 5,
          sigmaY: 5,
          child: Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            insetPadding: EdgeInsets.symmetric(horizontal: 24.w),
            child: Container(
              padding: EdgeInsets.all(20.w),
              decoration: BoxDecoration(
                color: c.surfaceLight.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(20.r),
                border: Border.all(color: c.border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.l10n.rename,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 20.sp,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 16.h),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    style: TextStyle(color: c.textPrimary, fontSize: 15.sp),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: c.surface,
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 14.w, vertical: 12.h),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.r),
                        borderSide:
                            BorderSide(color: c.borderSubtle, width: 0.5),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.r),
                        borderSide:
                            BorderSide(color: c.borderSubtle, width: 0.5),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.r),
                        borderSide: BorderSide(color: c.accent, width: 1),
                      ),
                    ),
                  ),
                  SizedBox(height: 20.h),
                  Row(
                    children: [
                      Expanded(
                        child: CustomButton(
                          onPressed: () => dialogCtx.pop(),
                          text: context.l10n.cancel,
                          primaryColor: c.surfaceLight,
                          textColor: c.textPrimary,
                        ),
                      ),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: CustomButton(
                          onPressed: () async {
                            final next = controller.text.trim();
                            if (next.isEmpty || next == wallet.name) {
                              dialogCtx.pop();
                              return;
                            }
                            await ref
                                .read(settingsProvider.notifier)
                                .renameWallet(wallet.id, next);
                            saved = true;
                            TrackingService.track('wallet_renamed', params: {
                              'surface': 'wallet_detail',
                              'changed': true,
                            });
                            if (dialogCtx.mounted) dialogCtx.pop();
                          },
                          text: context.l10n.save,
                          primaryColor: context.ctaFill,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (!saved) {
      TrackingService.track('wallet_rename_cancelled',
          params: {'surface': 'wallet_detail'});
    }
  }

  /// One removal dialog with copy per wallet type, then the D-15 warning
  /// for a hot wallet that is not backed up, then the D-9 step-up, then
  /// removal. The step-up is the final confirmation; the old "Final
  /// Confirmation" dialog is gone.
  void _handleDeleteRequest(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final body = wallet.isHardware
        ? l10n.removeWalletHardwareBody
        : wallet.isExternalAddress
            ? l10n.removeWalletTrackedBody
            : wallet.isWatchOnly
                ? l10n.removeWalletViewOnlyBody
                : wallet.isPasskey && wallet.passkeyProvider != null
                    ? l10n.removeWalletPasskeyBody
                    : l10n.removeWalletHotBody;
    // showDialog uses the root navigator, so the buttons pop that one.
    final navigator = Navigator.of(context, rootNavigator: true);
    showCustomAlertDialog(
      context: context,
      title: l10n.removeWalletTitle(wallet.name),
      content: body,
      buttons: [
        CustomAlertAction.destructive(
          text: l10n.removeWalletAction,
          onPressed: () async {
            // Extends walletDeleteInitiated() with where/what kind.
            TrackingService.track('wallet_delete_initiated', params: {
              'surface': 'wallet_detail',
              'wallet_kind': _walletKind,
            });
            navigator.pop();
            // D-15: a wallet that is not backed up gets one more
            // confirmation first. Read fresh: a backup may have finished
            // since this screen built.
            final matches = ref
                .read(settingsProvider)
                .wallets
                .where((w) => w.id == wallet.id);
            final current = matches.isNotEmpty ? matches.first : wallet;
            if (walletRemovalNeedsBackupWarning(current)) {
              final choice = await confirmUnbackedWalletRemoval(context);
              if (!context.mounted) return;
              if (choice == UnbackedRemovalChoice.backUpFirst) {
                context.push('/backup_wallet', extra: wallet.id);
                return;
              }
              if (choice != UnbackedRemovalChoice.removeAnyway) return;
            }
            await _removeWallet(context, ref);
          },
        ),
        CustomAlertAction.secondary(
          text: l10n.cancel,
          onPressed: () {
            _trackDeleteCancelled('first_confirm');
            navigator.pop();
          },
        ),
      ],
    );
  }

  Future<void> _removeWallet(BuildContext context, WidgetRef ref) async {
    // D-9: removal needs a fresh approval bound to this wallet, consumed
    // right before it is removed. A declined prompt changes nothing.
    if (!await approveWalletRemoval(context, ref, wallet.id)) {
      _trackDeleteCancelled('approval');
      return;
    }
    if (!context.mounted) return;
    final wasPasskey = wallet.isPasskey;
    TrackingService.track('wallet_delete_confirmed', params: {
      'surface': 'wallet_detail',
      'wallet_kind': _walletKind,
    });
    // Restore the spending wallet BEFORE removing so the providers that
    // key off activeWalletId don't briefly point at a wallet that no
    // longer exists.
    await onRestoreActive();
    await ref.read(settingsProvider.notifier).removeWallet(wallet.id);
    ref.read(walletBalanceCacheProvider.notifier).deleteWallet(wallet.id);
    ref.read(walletTransactionCacheProvider.notifier).deleteWallet(wallet.id);
    await ref.read(swapOrdersProvider.notifier).deleteAllForWallet(wallet.id);
    final remaining = ref.read(settingsProvider).wallets.length;
    TrackingService.walletWiped(
      walletCount: remaining,
      wasPasskey: wasPasskey,
    );
    if (!context.mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      // Wealth tab removed — Home is the post-delete landing.
      context.go('/home');
    }
  }
}

/// The wallet's own mark in the header (vendor logo, Bitcoin mark or the
/// mascot). Bare artwork, no tile behind it (user decision).
class _WalletLogo extends StatelessWidget {
  const _WalletLogo({required this.wallet});
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
    final svg = visual.svgAsset;
    final mono =
        visual.color == Colors.white || visual.color == const Color(0xFF333333);
    return SizedBox(
      width: 30.sp,
      height: 30.sp,
      child: svg != null
          ? SvgPicture.asset(
              svg,
              fit: BoxFit.contain,
              colorFilter: mono
                  ? ColorFilter.mode(c.textPrimary, BlendMode.srcIn)
                  : null,
            )
          : Icon(visual.icon, color: visual.color, size: 26.sp),
    );
  }
}
