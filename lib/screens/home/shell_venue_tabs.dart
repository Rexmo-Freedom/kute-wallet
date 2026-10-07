// lib/screens/home/shell_venue_tabs.dart
//
// The shell's Investing (Hyperliquid) and Predictions (Polymarket) tabs.
//
// They render the ordinary venue screens for the spending account, and the
// EXISTING Ledger venue screens when the first tab is showing a Ledger
// wallet (user decision September 2026: a Ledger carries the same three-tab
// strip as Home, so its venues are tabs of the shell rather than an inner
// tab row on a pushed detail screen). Nothing is forked: the bodies are
// LedgerHyperliquidTab / LedgerPolymarketTab, with the same dock and search
// targets the Ledger account screen used.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/constants/feature_flags.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/shell_wallet_provider.dart';
import 'package:kute/screens/home/components/kute_dock_host.dart';
import 'package:kute/screens/home/shell_wallet_screen.dart'
    show kShellTopBarSpacing;
import 'package:kute/screens/hyperliquid/hyperliquid_screen.dart';
import 'package:kute/screens/ledger/ledger_account_action_bar.dart';
import 'package:kute/screens/ledger/ledger_account_body.dart'
    show LedgerAccountTab;
import 'package:kute/screens/ledger/ledger_hyperliquid_tab.dart';
import 'package:kute/screens/ledger/ledger_investment_gate.dart';
import 'package:kute/screens/ledger/ledger_polymarket_tab.dart';
import 'package:kute/screens/polymarket/polymarket_screen.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/theme/app_theme.dart';

/// True when [wallet] should take over the venue tabs with its own Ledger
/// screens rather than the spending account's.
bool shellShowsLedgerVenues(WalletConfig? wallet) =>
    wallet != null && wallet.isLedger && kLedgerInvestingEnabled;

/// True when the first tab holds the spending account (or nothing yet).
bool _shellIsSpending(WalletConfig? wallet) =>
    wallet == null || wallet.isSparkWallet;

/// True when the Investing tab belongs in the strip.
///
/// Only two kinds of wallet have venues: the Spark spending account, whose
/// venues are the ones Home shows, and a Ledger, which has its own. A
/// Bitcoin wallet, a watch-only wallet, an imported address and a signer
/// have none, and must not borrow the spending account's, which is what
/// they did when the strip carried the tabs unconditionally. Their strip is
/// the wallet tab alone.
///
/// A Ledger's Investing exists only while the policy allows
/// `ledger.hyperliquid` ([ledgerInvestmentAllowed]); otherwise the tab is
/// absent, not disabled. Callers pass the strip's owner
/// ([shellVenueOwnerProvider]), never the bare shell wallet.
bool shellShowsTradingTab(WalletConfig? wallet,
        {RuntimeCapabilitiesService? policy}) =>
    _shellIsSpending(wallet) ||
    (shellShowsLedgerVenues(wallet) &&
        ledgerInvestmentAllowed(ledgerInvestingCapability, policy: policy));

/// True when the Predictions tab belongs in the strip. Same rule as
/// [shellShowsTradingTab], with `ledger.polymarket` for a Ledger.
bool shellShowsPredictionsTab(WalletConfig? wallet,
        {RuntimeCapabilitiesService? policy}) =>
    _shellIsSpending(wallet) ||
    (shellShowsLedgerVenues(wallet) &&
        ledgerInvestmentAllowed(ledgerPredictionsCapability, policy: policy));

/// True when either venue tab belongs in the strip.
bool shellShowsVenueTabs(WalletConfig? wallet,
        {RuntimeCapabilitiesService? policy}) =>
    shellShowsTradingTab(wallet, policy: policy) ||
    shellShowsPredictionsTab(wallet, policy: policy);

/// True when the USD tab belongs in the strip.
///
/// The dollar balance is the SPENDING account's own — it rides the same
/// rails as its bitcoin — so the tab shows for the spending account only:
/// a Ledger brings its own venues (when they are on), not the spending
/// account's cash, and a Bitcoin-only, watch-only, tracked or signer
/// wallet has no dollars at all. It shares [_shellIsSpending] with the
/// venue helpers so they never drift on what "the spending account"
/// means.
bool shellShowsUsdTab(WalletConfig? wallet) => _shellIsSpending(wallet);

/// Shell branch 2. Investing for the spending account, or the Ledger's own
/// Hyperliquid tab when a Ledger wallet owns the first tab.
class ShellTradingTab extends ConsumerWidget {
  const ShellTradingTab({
    super.key,
    this.autoShowDeposit = false,
    this.autoShowWithdraw = false,
  });

  final bool autoShowDeposit;
  final bool autoShowWithdraw;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(shellVenueOwnerProvider);
    final policy = ref.watch(runtimeCapabilitiesProvider);
    if (!shellShowsLedgerVenues(wallet)) {
      return HyperliquidScreen(
        autoShowDeposit: autoShowDeposit,
        autoShowWithdraw: autoShowWithdraw,
      );
    }
    // Ledger Investing off: the strip does not draw this tab and the
    // shell sends the branch home, so it holds nothing meanwhile.
    if (!shellShowsTradingTab(wallet, policy: policy)) {
      return const SizedBox.shrink();
    }
    return _LedgerVenueTab(
      walletId: wallet!.id,
      tab: LedgerAccountTab.investing,
      child: LedgerHyperliquidTab(walletId: wallet.id),
    );
  }
}

/// Shell branch 3. Predictions for the spending account, or the Ledger's own
/// Polymarket tab when a Ledger wallet owns the first tab.
class ShellPredictionsTab extends ConsumerWidget {
  const ShellPredictionsTab({
    super.key,
    this.autoShowDeposit = false,
    this.autoShowWithdraw = false,
  });

  final bool autoShowDeposit;
  final bool autoShowWithdraw;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(shellVenueOwnerProvider);
    final policy = ref.watch(runtimeCapabilitiesProvider);
    if (!shellShowsLedgerVenues(wallet)) {
      return PolymarketScreen(
        autoShowDeposit: autoShowDeposit,
        autoShowWithdraw: autoShowWithdraw,
      );
    }
    // Ledger Predictions off: see ShellTradingTab.
    if (!shellShowsPredictionsTab(wallet, policy: policy)) {
      return const SizedBox.shrink();
    }
    return _LedgerVenueTab(
      walletId: wallet!.id,
      tab: LedgerAccountTab.predictions,
      child: LedgerPolymarketTab(walletId: wallet.id),
    );
  }
}

/// Shared chrome for a Ledger venue mounted as a shell tab: the screen
/// gradient, the wallet-bound dock and the room the floating nav bar takes.
/// No app bar, no back button; the strip is the navigation.
class _LedgerVenueTab extends StatelessWidget {
  const _LedgerVenueTab({
    required this.walletId,
    required this.tab,
    required this.child,
  });

  final String walletId;
  final LedgerAccountTab tab;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppDecorations.screenGradient(context),
      child: KuteDockHost(
        dockBuilder: (onHeightChanged) => LedgerAccountActionBar(
          walletId: walletId,
          tab: tab,
          onHeightChanged: onHeightChanged,
        ),
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: kShellTopBarSpacing.h),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}
