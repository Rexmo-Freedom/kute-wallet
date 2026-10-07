// lib/screens/ledger/ledger_account_body.dart
//
// The Ledger account screen body (Wallet hardening Phase 4, P4.4, B10):
// a Home-style service tab strip with Bitcoin, Investing (Hyperliquid) and
// Predictions (Polymarket), per O9.
//
// Investing and Predictions are tabs only while that Ledger venue is on
// (the `ledger.hyperliquid` / `ledger.polymarket` runtime capability, see
// ledgerInvestmentAllowed). Off, the tab is
// absent, not disabled; with both off the body is the Bitcoin tab alone,
// with no strip.
//
// Reads only. Balances, positions and orders come from the wallet-scoped
// public read providers, so everything renders while the Ledger is
// disconnected; no tab opens a device prompt on its own. Tabs load the
// first time they are shown and then stay mounted.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/screens/ledger/ledger_bitcoin_tab.dart';
import 'package:kute/screens/ledger/ledger_hyperliquid_tab.dart';
import 'package:kute/screens/ledger/ledger_investment_gate.dart';
import 'package:kute/screens/ledger/ledger_polymarket_tab.dart';
import 'package:kute/screens/shared/service_tab_strip.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';

enum LedgerAccountTab {
  bitcoin('bitcoin'),
  investing('investing'),
  predictions('predictions');

  const LedgerAccountTab(this.trackingName);

  /// Analytics value for `ledger_account_viewed` / `ledger_tab_switched`.
  final String trackingName;
}

/// Whether [tab] exists on a Ledger right now: Bitcoin always, a venue
/// only while that Ledger venue is on ([ledgerInvestmentAllowed]).
bool ledgerAccountTabOffered(LedgerAccountTab tab,
        {RuntimeCapabilitiesService? policy}) =>
    switch (tab) {
      LedgerAccountTab.bitcoin => true,
      LedgerAccountTab.investing =>
        ledgerInvestmentAllowed(ledgerInvestingCapability, policy: policy),
      LedgerAccountTab.predictions =>
        ledgerInvestmentAllowed(ledgerPredictionsCapability, policy: policy),
    };

/// Opens the investing setup step for [walletId] from an account tab. The
/// setup is asked here, the first time a Ledger venue that is on is
/// opened, never at connect time; with both Ledger venues off it does
/// nothing.
void openLedgerInvestingSetup(BuildContext context, String walletId) {
  if (!ledgerAnyVenueAllowed()) return;
  context.pushNamed(
    'ledgerInvestingSetup',
    pathParameters: {'walletId': walletId},
  );
}

class LedgerAccountBody extends ConsumerStatefulWidget {
  final WalletConfig wallet;
  final LedgerAccountTab initialTab;
  final ValueChanged<LedgerAccountTab>? onTabChanged;

  const LedgerAccountBody({
    super.key,
    required this.wallet,
    this.initialTab = LedgerAccountTab.bitcoin,
    this.onTabChanged,
  });

  @override
  ConsumerState<LedgerAccountBody> createState() => _LedgerAccountBodyState();
}

class _LedgerAccountBodyState extends ConsumerState<LedgerAccountBody> {
  late LedgerAccountTab _tab = ledgerAccountTabOffered(widget.initialTab)
      ? widget.initialTab
      : LedgerAccountTab.bitcoin;
  late final Set<LedgerAccountTab> _visited = {_tab};

  @override
  void initState() {
    super.initState();
    TrackingService.ledgerAccountViewed(_tab.trackingName);
    if (_tab != widget.initialTab) {
      // Asked for a venue that is off: the host's dock follows Bitcoin.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onTabChanged?.call(_tab);
      });
    }
  }

  void _select(LedgerAccountTab tab) {
    if (!ledgerAccountTabOffered(tab) || tab == _tab) return;
    TrackingService.ledgerTabSwitched(tab.trackingName);
    setState(() {
      _tab = tab;
      _visited.add(tab);
    });
    widget.onTabChanged?.call(tab);
  }

  Widget _tabChild(LedgerAccountTab tab) {
    if (!_visited.contains(tab)) return const SizedBox.shrink();
    switch (tab) {
      case LedgerAccountTab.bitcoin:
        return LedgerBitcoinTab(wallet: widget.wallet);
      case LedgerAccountTab.investing:
        return LedgerHyperliquidTab(walletId: widget.wallet.id);
      case LedgerAccountTab.predictions:
        return LedgerPolymarketTab(walletId: widget.wallet.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final policy = ref.watch(runtimeCapabilitiesProvider);
    bool offered(LedgerAccountTab tab) =>
        ledgerAccountTabOffered(tab, policy: policy);
    if (!offered(_tab)) {
      // The open venue was switched off: back to Bitcoin, no sheet.
      final fallback = LedgerAccountTab.bitcoin;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || offered(_tab)) return;
        setState(() {
          _tab = fallback;
          _visited.add(fallback);
        });
        widget.onTabChanged?.call(fallback);
      });
    }
    final investing = offered(LedgerAccountTab.investing);
    final predictions = offered(LedgerAccountTab.predictions);
    if (!investing && !predictions) {
      // A Ledger is a bitcoin hardware wallet only: no strip to pick from.
      return LedgerBitcoinTab(wallet: widget.wallet);
    }
    final tabs = [
      ServiceTabData(
        svgAsset: 'lib/assets/bitcoin-icon.svg',
        icon: Icons.currency_bitcoin_rounded,
        label: l10n.ledgerTabBitcoin,
        active: _tab == LedgerAccountTab.bitcoin,
        onTap: () => _select(LedgerAccountTab.bitcoin),
      ),
      if (investing)
        ServiceTabData(
          svgAsset: 'lib/assets/hyperliquid-logo.svg',
          icon: Icons.candlestick_chart_rounded,
          label: l10n.ledgerTabInvesting,
          semanticsLabel: l10n.ledgerTabInvestingSemantics,
          active: _tab == LedgerAccountTab.investing,
          onTap: () => _select(LedgerAccountTab.investing),
        ),
      if (predictions)
        ServiceTabData(
          svgAsset: 'lib/assets/polymarket-logo.svg',
          icon: Icons.psychology_rounded,
          label: l10n.ledgerTabPredictions,
          semanticsLabel: l10n.ledgerTabPredictionsSemantics,
          active: _tab == LedgerAccountTab.predictions,
          onTap: () => _select(LedgerAccountTab.predictions),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 4.h),
          child: ServiceTabStrip(tabs: tabs),
        ),
        Expanded(
          child: IndexedStack(
            index: _tab.index,
            children: [
              for (final tab in LedgerAccountTab.values)
                KeyedSubtree(
                  key: ValueKey(tab),
                  child: _tabChild(tab),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
