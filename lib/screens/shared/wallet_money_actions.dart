import 'package:kute/helpers/require_fresh_auth.dart';
import 'dart:async';

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
import 'package:kute/screens/shared/kute_action_cards.dart';
import 'package:kute/screens/shared/kute_motion.dart' show KutePressable;
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/screens/home/shell_venue_tabs.dart'
    show shellShowsPredictionsTab, shellShowsTradingTab;
import 'package:kute/screens/shared/wallet_icon.dart';
import 'package:kute/screens/settings/settings.dart'
    show kReferralCapability, requestAppReview;
import 'package:kute/services/runtime_capabilities_service.dart'
    show runtimeCapabilitiesProvider;
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/support_service.dart';
import 'package:kute/theme/app_theme.dart';

/// The Financial hub: under its compact title, the app's big cards
/// (founder, 7 November 2026: "with the bigger cards just like the other
/// parts of the app now"), Settings on top, then Referrals and Support;
/// then wallet switching and Add account, each a full-width card on the
/// same soft surface. Referrals shows only where `affiliate.program` is
/// allowed; Rate the app takes its card otherwise, as on Settings.
/// Portfolio lives inside Investments. The hub opens from the shell's
/// top-right + or a pushed wallet screen's name.
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
              compact: true,
            ),
            _HubCards(sheetContext: context, callerContext: callerContext),
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

/// The hub's three big cards ([KuteActionCardGrid]), where its header
/// pills were. SETTINGS ON TOP, the grid's lead (full width, with more
/// presence): the gear is half of the hub's own door ("Financial hub and
/// settings"), and a lead sets it apart from the account cards under the
/// grid, where a compact full-width card would read as one more account.
/// REFERRALS AND SUPPORT, two squares under it, titles on one line
/// (oneLineTitles; two compact full-width cards where a translation or a
/// large text size does not fit). Where the policy withholds the referral
/// program, Rate the app takes its card, as on Settings' top cards: the
/// grid stays whole and never reads why. Each card closes the hub and
/// opens its door from the screen the hub was opened on, firing the
/// events the pills fired.
class _HubCards extends ConsumerWidget {
  const _HubCards({required this.sheetContext, required this.callerContext});

  final BuildContext sheetContext;
  final BuildContext callerContext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final showReferral =
        ref.watch(runtimeCapabilitiesProvider).allows(kReferralCapability);

    void openSettings() {
      HapticFeedback.lightImpact();
      // `source` kept for the existing settings_opened breakdowns;
      // the playbook's entry_source carries the same door.
      TrackingService.track('settings_opened', params: {
        'source': 'financial_hub',
        'entry_source': 'financial_hub',
      });
      Navigator.of(sheetContext).pop();
      if (!callerContext.mounted) return;
      callerContext.push('/settings');
    }

    void openReferrals() {
      HapticFeedback.lightImpact();
      Navigator.of(sheetContext).pop();
      if (!callerContext.mounted) return;
      callerContext.push('/affiliate');
    }

    void rateApp() {
      HapticFeedback.lightImpact();
      // Settings' rate_app tap, named for the door it came from.
      TrackingService.track('settings_action_tapped', params: {
        'feature': 'rate_app',
        'source': 'financial_hub',
      });
      // Asked before the hub closes: the review reads the settings
      // through this sheet's ref, which closing it disposes.
      final review = requestAppReview(ref);
      Navigator.of(sheetContext).pop();
      unawaited(review);
    }

    void openSupport() {
      HapticFeedback.lightImpact();
      TrackingService.supportOpened(source: 'financial_hub');
      Navigator.of(sheetContext).pop();
      openSupportChat();
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 4.h, 20.w, 0),
      child: KuteActionCardGrid(
        key: const ValueKey('hub-cards'),
        oneLineTitles: true,
        lead: KuteActionCard(
          key: const ValueKey('hub-card-settings'),
          visual: const KuteActionCardIcon(Icons.settings_rounded,
              size: kKuteActionCardLeadVisualSize),
          visualSlot: kKuteActionCardLeadVisualSlot,
          title: l10n.settings,
          subtitle: l10n.hubSettingsSubtitle,
          onTap: openSettings,
        ),
        cards: [
          if (showReferral)
            KuteActionCard(
              key: const ValueKey('hub-card-referral'),
              visual: const KuteActionCardIcon(Icons.group_rounded),
              title: l10n.hubReferrals,
              subtitle: l10n.hubReferralsSubtitle,
              onTap: openReferrals,
            )
          else
            KuteActionCard(
              key: const ValueKey('hub-card-rate'),
              visual: const KuteActionCardIcon(Icons.star_rounded),
              title: l10n.settingsRateTheApp,
              subtitle: l10n.settingsLeaveAReview,
              onTap: rateApp,
            ),
          // Opens live Crisp chat.
          KuteActionCard(
            key: const ValueKey('hub-card-support'),
            visual: const KuteActionCardIcon(Icons.support_agent_rounded),
            title: l10n.support,
            subtitle: l10n.hubSupportSubtitle,
            onTap: openSupport,
          ),
        ],
      ),
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
///
/// A list, since it grows with every account added, in the weight of the
/// cards above it (founder, 7 November 2026): each account and Add account
/// is its own full-width card on the app's one soft surface, laid out as
/// the grid's compact full-width card ([_AccountCard]), 12 apart.
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
      final targetId =
          spending != null && wallet.id == spending.id ? null : wallet.id;
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

    final gap = SizedBox(height: kKuteActionCardGap.w);
    return Padding(
      // Clear of the cards above, as Settings' sections sit under its
      // cards: the sheet's header already names the list, so it wears no
      // label of its own.
      padding: EdgeInsets.fromLTRB(20.w, 24.h, 20.w, 8.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final wallet in wallets) ...[
            _AccountCard(
              key: ValueKey('hub-account-${wallet.id}'),
              label: wallet.name.isNotEmpty ? wallet.name : 'Bitcoin Wallet',
              leading: _WalletMark(wallet: wallet),
              isActive: shellWalletId == null
                  ? (spending != null && wallet.id == spending.id)
                  : wallet.id == shellWalletId,
              // Both the spending account and a Ledger carry Investing
              // (Hyperliquid) and Predictions (Polymarket) as tabs of
              // their own, so each row shows the two venue marks at a
              // glance. A plain Bitcoin or watch-only account carries
              // neither.
              showDollars: wallet.isSparkWallet,
              // A Ledger shows only the venues it has in this build
              // (Ledger Investing / Predictions on), the same tabs the
              // strip draws for it; none while both are off.
              showInvesting: shellShowsTradingTab(wallet),
              showPredictions: shellShowsPredictionsTab(wallet),
              onTap: () => openWallet(wallet),
            ),
            gap,
          ],
          // Always offered: a way to add a wallet that Kute withholds says
          // so on Add wallet when tapped, it is never hidden. It wears the
          // cards' icon tile.
          _AccountCard(
            key: const ValueKey('hub-add-account'),
            label: context.l10n.addWallet,
            leading: const KuteActionCardIcon(Icons.add_rounded),
            isActive: false,
            onTap: addWallet,
          ),
        ],
      ),
    );
  }
}

/// One account of the hub's list, or Add account: the big cards' compact
/// full-width card (kute_action_cards.dart), the soft surface, its 16
/// padding and press spring, the [leading] mark in the 40 box at the
/// left, the name in the cards' title style, then the venue marks a wallet
/// carries and the check mark on the account the first tab shows (a
/// chevron on the others).
class _AccountCard extends StatelessWidget {
  const _AccountCard({
    super.key,
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
    final surface = KuteActionCard.surfaceOf(context);
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: isActive,
        child: KutePressable(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              padding:
                  KuteActionCard.paddingIn(surface, kKuteActionCardPadding),
              decoration: surface,
              child: Row(
                children: [
                  SizedBox(
                    width: kKuteActionCardVisualSlot,
                    height: kKuteActionCardVisualSlot,
                    child: Center(child: leading),
                  ),
                  const SizedBox(width: kKuteActionCardWideGap),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: KuteActionCard.titleStyle(c),
                    ),
                  ),
                  if (showInvesting || showPredictions) ...[
                    SizedBox(width: 8.w),
                    _VenueMarks(
                      withDollars: showDollars,
                      investing: showInvesting,
                      predictions: showPredictions,
                    ),
                  ],
                  const SizedBox(width: 12),
                  Icon(
                    isActive
                        ? Icons.check_rounded
                        : Icons.chevron_right_rounded,
                    size: 22,
                    color: isActive ? c.textPrimary : c.textTertiary,
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

/// The venue marks a Ledger row carries: the same Hyperliquid and
/// Polymarket logos the nav strip and the Ledger tabs already use.
class _VenueMarks extends StatelessWidget {
  const _VenueMarks({
    this.withDollars = false,
    this.investing = true,
    this.predictions = true,
  });

  /// The spending account also carries Investments (the dollar balance)
  /// as a tab of its own, so its row shows the Investments arrow beside
  /// the two venues, never the USDB coin. A Ledger does not.
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
        if (withDollars) l10n.bitcoin,
      ].join(', '),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The spending account's own mark is the bitcoin glyph the top
          // strip uses; the venues follow (user decision 2026-10-12).
          if (withDollars) ...[
            Icon(Icons.currency_bitcoin_rounded,
                size: size, color: context.colors.textPrimary),
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
    // Inside the cards' 40 box, with a little air round it.
    const size = 32.0;
    if (visual.svgAsset != null) {
      final mono = visual.color == Colors.white ||
          visual.color == const Color(0xFF333333);
      return BrandMark(
        asset: visual.svgAsset!,
        size: size,
        tint: mono ? c.textPrimary : null,
      );
    }
    return Icon(visual.icon, size: size, color: visual.color);
  }
}
