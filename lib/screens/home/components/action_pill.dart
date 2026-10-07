import 'package:kute/providers/active_shell_tab_provider.dart'
    show ActiveNavTab;
import 'package:kute/models/settings_model.dart' show WalletConfig;
import 'package:kute/providers/shell_wallet_provider.dart';
import 'package:kute/screens/home/shell_venue_tabs.dart'
    show
        shellShowsLedgerVenues,
        shellShowsPredictionsTab,
        shellShowsTradingTab,
        shellShowsUsdTab;
import 'package:kute/screens/usd/usd_account_screen.dart'
    show trackUsdTabOpened;
import 'package:kute/providers/asset_icon_provider.dart'
    show kUsdMarkAsset;
import 'package:kute/screens/shared/wallet_icon.dart';
import 'package:kute/screens/shared/service_tab_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:kute/constants/feature_flags.dart';
import 'package:kute/services/runtime_capabilities_service.dart'
    show runtimeCapabilitiesProvider;
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/helpers/kute_dog_asset.dart';
import 'package:kute/screens/shared/kute_dog_scenes.dart' show KuteDogBitcoin;
import 'package:flutter_screenutil/flutter_screenutil.dart';

// [ActiveNavTab] used to be defined here; it moved to
// providers/active_shell_tab_provider.dart so the live-price notifiers
// can read the active tab without importing the widget layer.
// Re-exported so existing importers keep resolving it from this file.
export 'package:kute/providers/active_shell_tab_provider.dart'
    show ActiveNavTab;

/// Canonical market-direction pair. These names are kept as ALIASES of
/// `AppColors.marketUp` / `AppColors.marketDown` so the ~12 importing
/// files keep compiling unchanged — new code should import the
/// `AppColors` tokens directly. (Previously local `#16A34A` / `#FF5252`,
/// one more pair of drifted greens/reds.)
const Color greenColor = AppColors.marketUp;
const Color redColor = AppColors.marketDown;

final selectedNetworkTypeProvider = StateProvider<String>((ref) => "Bitcoin Network");

/// Navigation-only pill. Holds the four destination tabs that drive
/// repeated product exposure (every session, every screen a user returns
/// from): Home / Stocks / Predictions / Cash In. Money actions (Send /
/// Receive / Convert / Pay Link) live on the home card stack, so the nav
/// never competes with transactional intent.
class FloatingActionPill extends ConsumerStatefulWidget {
  final ActiveNavTab activeTab;

  /// Called when a DIFFERENT tab is tapped so the persistent nav shell can
  /// switch its go_router branch (no bar remount → the indicator pill morphs
  /// for real). When null (legacy / standalone use) taps fall back to
  /// `context.go('/…')`. Tapping the ACTIVE tab is never routed through here
  /// — the active-tab affordances (deposit menus) run inline below.
  final void Function(ActiveNavTab)? onSelectTab;
  const FloatingActionPill({
    super.key,
    this.activeTab = ActiveNavTab.home,
    this.onSelectTab,
  });

  @override
  ConsumerState<FloatingActionPill> createState() => _FloatingActionPillState();
}

class _FloatingActionPillState extends ConsumerState<FloatingActionPill> {
  /// Switch to [tab]. Routes through the shell's branch switcher when the
  /// bar is mounted in the persistent shell (no remount → the indicator
  /// morphs for real); falls back to `context.go(route)` for legacy /
  /// standalone mounts.
  void _switchTab(BuildContext context, ActiveNavTab tab, String route) {
    final onSelect = widget.onSelectTab;
    if (onSelect != null) {
      onSelect(tab);
    } else {
      context.go(route);
    }
  }

  /// The first slot names the account on screen (its mark and name). A
  /// plain destination switch: re-tapping it while active does nothing, as
  /// on the other tabs. The Financial hub (wallets, switch, Add wallet)
  /// opens from the + at the right of this bar (owner decision: one door).
  void _handleHome(BuildContext context) {
    HapticFeedback.selectionClick();
    TrackingService.homeActionTapped('home');
    if (widget.activeTab != ActiveNavTab.home) {
      _switchTab(context, ActiveNavTab.home, '/home');
    }
  }

  /// First-slot tap when that slot is a WALLET rather than Home. Same rule
  /// as the spending account's slot: a switch to the first tab, nothing on
  /// a re-tap. The wallet's own actions (rename, remove) stay on its
  /// pushed account screen's menu.
  void _handleWalletTab(BuildContext context, WalletConfig wallet) {
    HapticFeedback.selectionClick();
    TrackingService.track('wallet_tab_tapped', params: {
      'wallet_type': wallet.walletType,
      'active': widget.activeTab == ActiveNavTab.home,
    });
    if (widget.activeTab != ActiveNavTab.home) {
      _switchTab(context, ActiveNavTab.home, '/home');
    }
  }

  /// The wallet's own mark and name in the first tab slot. Monochrome
  /// vendor marks (the Ledger logo) tint with the tab foreground so they
  /// stay legible in both themes; the mascot follows the theme asset.
  ServiceTabData _walletTab(BuildContext context, WalletConfig wallet) {
    final visual = WalletVisual.fromWallet(
      walletType: wallet.walletType,
      isHardware: wallet.isHardware,
      isWatchOnly: wallet.isWatchOnly || wallet.isExternalAddress,
      isSigner: wallet.isSigner,
      isDark: context.isDark,
    );
    var asset = visual.svgAsset;
    if (asset == 'lib/assets/kute_dog.svg') asset = kuteDogAsset(context);
    final mono = visual.color == Colors.white ||
        visual.color == const Color(0xFF333333);
    return ServiceTabData(
      svgAsset: asset,
      icon: visual.icon,
      tintSvg: mono,
      label: wallet.name.isNotEmpty ? wallet.name : context.l10n.accountWallet,
      active: widget.activeTab == ActiveNavTab.home,
      onTap: () => _handleWalletTab(context, wallet),
    );
  }

  /// The spending account's dollars. A plain destination switch: the
  /// tab's own dock owns Purchase and Exchange, so re-tapping the active
  /// chip does nothing, exactly like Investing and Predictions.
  void _handleUsd(BuildContext context) {
    HapticFeedback.lightImpact();
    TrackingService.homeActionTapped('usd');
    if (widget.activeTab != ActiveNavTab.usd) {
      trackUsdTabOpened('nav_pill');
      _switchTab(context, ActiveNavTab.usd, '/usd');
    }
  }

  Future<void> _handlePredictions(BuildContext context) async {
    HapticFeedback.lightImpact();
    TrackingService.homeActionTapped('predictions');
    if (shellShowsLedgerVenues(ref.read(shellVenueOwnerProvider)) &&
        widget.activeTab != ActiveNavTab.predictions) {
      TrackingService.ledgerTabSwitched('predictions');
    }
    // Geoblock is centralised in BetSlipSheet.show — users browse freely;
    // the gate only fires when they open a prediction slip.
    if (widget.activeTab != ActiveNavTab.predictions) {
      TrackingService.polymarketTabOpened();
      _switchTab(context, ActiveNavTab.predictions, '/polymarket');
      return;
    }
    // Already on Predictions → no-op (user decision: the dedicated
    // Deposit/Withdraw buttons on the bottom bar own money now — the
    // active chip no longer opens a funding overlay).
  }

  Future<void> _handleTrading(BuildContext context) async {
    HapticFeedback.lightImpact();
    TrackingService.homeActionTapped('trading');
    // The venue tabs render this Ledger's own screens; report the switch
    // with the same event the Ledger account screen used.
    if (shellShowsLedgerVenues(ref.read(shellVenueOwnerProvider)) &&
        widget.activeTab != ActiveNavTab.trading) {
      TrackingService.ledgerTabSwitched('investing');
    }
    // Geoblock is centralised in HlOrderSlipSheet.show — browse freely;
    // the gate only fires when an order slip opens.
    if (widget.activeTab != ActiveNavTab.trading) {
      TrackingService.hyperliquidTabOpened();
      _switchTab(context, ActiveNavTab.trading, '/hyperliquid');
      return;
    }
    // Already on Trading → no-op (user decision: the dedicated Buy/
    // Deposit/Withdraw buttons on the bottom bar own money now — the
    // active chip no longer opens the deposit flow).
  }

  @override
  Widget build(BuildContext context) {
    // Tab badges removed (user decision): the in-motion count lives on
    // each screen's Activity header now, not on the top nav pills.
    // The first slot is Home for the spending account, and the WALLET the
    // user switched to otherwise (user decision September 2026: switching
    // wallets is a tab in this strip, not a pushed screen with a back
    // button). A Ledger keeps the same three slots: itself, Investing
    // (Hyperliquid) and Predictions (Polymarket).
    final shellWallet = ref.watch(shellWalletProvider);
    // Dollars and the venues belong to the strip's owner: the shell wallet,
    // or the Ledger Home is showing when no wallet was picked.
    final owner = ref.watch(shellVenueOwnerProvider);
    final policy = ref.watch(runtimeCapabilitiesProvider);
    final List<ServiceTabData> tabs = [
      if (shellWallet == null)
        ServiceTabData(
          svgAsset: kuteDogAsset(context),
          // Selected, Sal holds a bitcoin and tosses it now and then;
          // otherwise the plain dog.
          glyph: widget.activeTab == ActiveNavTab.home
              ? KuteDogBitcoin(
                  key: const ValueKey('bitcoin-tab-sal'), size: 24.sp)
              : null,
          icon: Icons.home_rounded,
          // The first tab is named for what it holds, the same way a
          // Ledger's first tab is. "Home" said where you were, not what
          // account you were looking at.
          label: context.l10n.bitcoin,
          active: widget.activeTab == ActiveNavTab.home,
          onTap: () => _handleHome(context),
        )
      else
        _walletTab(context, shellWallet),
      // Bank tab HIDDEN for this release (user decision September 2026:
      // hide, do not delete — it ships in a later version). Flip
      // showBankTab (lib/constants/feature_flags.dart) to bring it back;
      // the '/bank' route and screen
      // stay intact underneath.
      if (showBankTab)
        ServiceTabData(
          svgAsset: 'lib/assets/bank-transfer-logo.svg',
          icon: Icons.account_balance_rounded,
          label: context.l10n.walletsBank,
          active: widget.activeTab == ActiveNavTab.bank,
          onTap: () {
            HapticFeedback.lightImpact();
            TrackingService.homeActionTapped('bank');
            if (widget.activeTab != ActiveNavTab.bank) {
              _switchTab(context, ActiveNavTab.bank, '/bank');
            }
          },
        ),
      // USD — the spending account's dollar balance and its activity,
      // in the slot the Bank tab used to hold. Dropped for a wallet that
      // has no dollars of its own (Bitcoin-only, watch-only, tracked,
      // signer) and for a Ledger, which brings its own venues instead.
      if (shellShowsUsdTab(owner))
        ServiceTabData(
          // The dollar mark in the strip, the way every other tab there
          // carries its own. The hero inside the screen still uses a
          // typographic dollar sign, matching how amounts read
          // elsewhere (user decision September 2026).
          svgAsset: kUsdMarkAsset,
          icon: Icons.attach_money_rounded,
          label: context.l10n.usdAccountTab,
          active: widget.activeTab == ActiveNavTab.usd,
          onTap: () => _handleUsd(context),
        ),
      // Wealth tab removed — the cross-wallet view lives in the top bar's
      // wallets dropdown now (see _WalletsMenuButton in kute_top_nav_bar).
      // Earn tab removed too (user decision): Earn is a pushed detail
      // screen off the Home Earn card now, not a shell branch.
      // Trading (Hyperliquid) sits BEFORE Predictions in the strip.
      // Both are dropped when the first tab holds a wallet that has no
      // venues of its own: a Bitcoin wallet, a watch-only wallet, an
      // imported address or a signer. Leaving them in made those wallets
      // show the spending account's positions, which is not their money.
      // A Ledger's own Investing and Predictions are each drawn only
      // while that Ledger venue is on (its runtime capability): absent
      // otherwise, never a disabled chip.
      if (shellShowsTradingTab(owner, policy: policy))
        ServiceTabData(
          svgAsset: 'lib/assets/hyperliquid-logo.svg',
          icon: Icons.candlestick_chart_rounded,
          label: context.l10n.trading,
          active: widget.activeTab == ActiveNavTab.trading,
          onTap: () => _handleTrading(context),
        ),
      if (shellShowsPredictionsTab(owner, policy: policy))
        ServiceTabData(
          svgAsset: 'lib/assets/polymarket-logo.svg',
          icon: Icons.psychology_rounded,
          label: context.l10n.predictions,
          active: widget.activeTab == ActiveNavTab.predictions,
          onTap: () => _handlePredictions(context),
        ),
    ];

    // Shared strip (lib/screens/shared/service_tab_strip.dart): same
    // visuals, slide and reduced-motion handling as before the extraction.
    return ServiceTabStrip(tabs: tabs);
  }
}

