import 'package:kute/screens/hyperliquid/components/hl_portfolio_card.dart';
import 'package:kute/screens/hyperliquid/components/hl_browse_labels.dart';
// lib/screens/ledger/ledger_hyperliquid_tab.dart
//
// Investing tab (Hyperliquid) of the Ledger account screen (Wallet
// hardening Phase 4, P4.4, B10).
//
// Read only, bound to the device-verified EVM address through
// `ledgerHlAccountProvider`; nothing here signs or connects. A failed
// read shows "Some balances could not load" and never renders as zero.
//
// Public discovery stays visible while account reads load. Past fills remain
// available in this wallet's Portfolio Activity tab.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/helpers/formatters/polymarket_amount_formatter.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_market_card.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart';
import 'package:kute/providers/ledger/ledger_hyperliquid_account_provider.dart';
import 'package:kute/providers/ledger/ledger_hyperliquid_activity_provider.dart';
import 'package:kute/providers/ledger/ledger_identity_provider.dart';
import 'package:kute/screens/ledger/ledger_account_body.dart'
    show openLedgerInvestingSetup;
import 'package:kute/screens/ledger/ledger_tab_actions.dart';
import 'package:kute/screens/ledger/ledger_tab_states.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/ledger/ledger_investment_balance_header.dart';
import 'package:kute/screens/portfolio/open_investments_screen.dart';
import 'package:kute/screens/shared/investment_market_browser.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/screens/hyperliquid/market_detail_sheet.dart';

/// Totals derived from one Ledger Hyperliquid read. Each figure is null
/// when a read it depends on failed, so the UI never shows a false zero.
class LedgerHlTotals {
  const LedgerHlTotals({this.total, this.invested, this.available});

  factory LedgerHlTotals.of(LedgerHlAccount data) {
    final account = data.account;
    if (account == null) return const LedgerHlTotals();
    final failures = data.partialFailures;
    final spotUsdc = account.spotBalances
        .where((b) => b.coin == 'USDC')
        .fold<double>(0, (s, b) => s + b.total);
    final dexValue =
        data.dexAccounts.values.fold<double>(0, (s, a) => s + a.accountValue);
    final positionsValue = [
      ...account.positions,
      for (final dex in data.dexAccounts.values) ...dex.positions,
    ].fold<double>(0, (s, p) => s + p.positionValue.abs());
    final complete = !failures.contains(LedgerHlReadCategory.hip3Dexes);
    return LedgerHlTotals(
      total: complete ? account.accountValue + dexValue + spotUsdc : null,
      invested: complete ? positionsValue : null,
      available: account.withdrawable +
          account.spotBalances
              .where((b) => b.coin == 'USDC')
              .fold<double>(0, (s, b) => s + b.available),
    );
  }

  final double? total;
  final double? invested;
  final double? available;
}

class LedgerHyperliquidTab extends ConsumerWidget {
  final String walletId;

  const LedgerHyperliquidTab({
    super.key,
    required this.walletId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(ledgerIdentityProvider(walletId));
    if (identity == null ||
        identity.walletId != walletId ||
        !identity.hasVerifiedEvm) {
      return ListView(
        padding: EdgeInsets.only(
            bottom: 40.h + MediaQuery.paddingOf(context).bottom),
        children: [
          LedgerEnableInvestingCard(
            onEnable: () => openLedgerInvestingSetup(context, walletId),
          ),
          _LedgerInvestingDiscovery(walletId: walletId),
        ],
      );
    }

    final async = ref.watch(ledgerHlAccountProvider(walletId));
    void retry() {
      ref.invalidate(ledgerHlAccountProvider(walletId));
      ref.invalidate(ledgerHlFillsProvider(walletId));
      ref.invalidate(hyperliquidBrowseUniverseProvider);
    }

    return RefreshIndicator(
      color: context.colors.accent,
      onRefresh: () async {
        HapticFeedback.lightImpact();
        retry();
        try {
          await ref.read(ledgerHlAccountProvider(walletId).future);
        } catch (_) {}
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
            top: 4.h, bottom: 40.h + MediaQuery.paddingOf(context).bottom),
        children: [
          ...async.when(
            loading: () => const [LedgerTabLoading()],
            error: (_, __) => [LedgerTabLoadFailed(onRetry: retry)],
            data: (data) => data.walletId != walletId ||
                    data.address?.toLowerCase() !=
                        identity.evmAddress!.toLowerCase()
                ? [LedgerTabLoadFailed(onRetry: retry)]
                : [
                    _LedgerHlContent(
                        walletId: walletId, data: data, onRetry: retry),
                  ],
          ),
          _LedgerInvestingDiscovery(walletId: walletId),
        ],
      ),
    );
  }
}

class _LedgerHlContent extends ConsumerWidget {
  final String walletId;
  final LedgerHlAccount data;
  final VoidCallback onRetry;

  const _LedgerHlContent({
    required this.walletId,
    required this.data,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final actions = ref.watch(ledgerAccountActionsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (data.hasPartialFailure) LedgerPartialLoadNote(onRetry: onRetry),
        LedgerInvestmentBalanceHeader(
          walletId: walletId,
          product: InvestmentsProduct.trading,
          showDepositButton: true,
        ),
        if (actions.onOpenOrderTicket != null)
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 4.h),
            child: AppButton(
              text: l10n.ledgerInvestCta,
              compact: true,
              onPressed: () => actions.onOpenOrderTicket!(context, walletId),
            ),
          ),
      ],
    );
  }
}

/// Only public market reads are shared with Home. Every market tap carries
/// the Ledger wallet ID through the existing gated Ledger order flow.
class _LedgerInvestingDiscovery extends ConsumerStatefulWidget {
  const _LedgerInvestingDiscovery({required this.walletId});
  final String walletId;

  @override
  ConsumerState<_LedgerInvestingDiscovery> createState() =>
      _LedgerInvestingDiscoveryState();
}

class _LedgerInvestingDiscoveryState
    extends ConsumerState<_LedgerInvestingDiscovery> {
  HlLivePricesNotifier? _prices;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _prices = ref.read(hyperliquidLivePricesProvider.notifier);
      _prices!.acquire();
    });
  }

  @override
  void dispose() {
    _prices?.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final walletId = widget.walletId;
    final identity = ref.watch(ledgerIdentityProvider(walletId));
    final decision =
        ref.watch(runtimeCapabilitiesProvider).decision('hyperliquid.browse');
    if (!decision.allowed) return LedgerTabNote(text: decision.message);
    return ref.watch(hyperliquidBrowseUniverseProvider).when(
          loading: () => const LedgerTabLoading(),
          error: (_, __) => LedgerTabLoadFailed(
              onRetry: () => ref.invalidate(hyperliquidBrowseUniverseProvider)),
          data: (markets) => InvestmentMarketBrowser<HlMarket>(
            product: 'investing',
            sections: [
              for (final tab in const [
                // Investing's own categories. All is left out: as a
                // section it would repeat the top of Perps.
                HlBrowseTab.trending,
                HlBrowseTab.tradfi,
                HlBrowseTab.crypto,
                HlBrowseTab.perps,
                HlBrowseTab.spot,
                HlBrowseTab.prelaunch,
              ])
                InvestmentBrowseSection(
                    label: tab.localizedLabel(context.l10n),
                    markets: hlBrowseListForTab(tab, markets)),
            ],
            cardBuilder: (market, onTap) =>
                HlMarketCard(market: market, onTap: onTap),
            onOpenMarket: (market) {
              if (!mounted || widget.walletId != walletId) return;
              final current = ref.read(ledgerIdentityProvider(walletId));
              if (current == null || !current.hasVerifiedEvm) {
                openLedgerInvestingSetup(context, walletId);
                return;
              }
              if (current.evmAddress != identity?.evmAddress) return;
              // Same chart and detail as Home; Invest and Short inside it
              // open the Ledger order sheet, and there is no hot deposit.
              HlMarketDetailSheet.show(context,
                  market: market, ledgerWalletId: walletId);
            },
          ),
        );
  }
}

/// One perps position (default dex or HIP-3).
class LedgerHlPositionRow extends ConsumerWidget {
  final HlPerpPosition position;

  final String walletId;
  const LedgerHlPositionRow(
      {super.key, required this.position, required this.walletId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child:
          HlPortfolioPositionCard(position: position, ledgerWalletId: walletId),
    );
  }
}

/// One resting order. Cancel needs the Ledger by protocol (O8), so it is
/// only offered when the Ledger cancel hook is wired.
class LedgerHlOrderRow extends ConsumerWidget {
  final HlOpenOrder order;
  final VoidCallback? onCancel;

  const LedgerHlOrderRow({super.key, required this.order, this.onCancel});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final side = order.isBuy ? l10n.ledgerSideBuy : l10n.ledgerSideSell;
    // Orders carry wire coins ('xyz:TSLA', '@107'); show the market's name.
    final market = ref.watch(hyperliquidWireMarketProvider(order.coin));
    final coin = hlDisplayCoin(market, order.coin);
    // The Portfolio's own card, on the list cards' inset.
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: HlPortfolioCard(
        coin: coin,
        wireCoin: market?.wireCoin ?? order.coin,
        iconUrl: market?.iconUrl,
        category: market?.category,
        name: hlFriendlyName(coin) ?? market?.unitAssetName ?? coin,
        // Dollars first; the coin size waits on the cancel review's
        // Advanced rows.
        caption: '$coin · ${order.isTrailingStop ? l10n.ledgerTrailingStopSubtitle(side, '${_trimNumber(order.sz)} $coin') : l10n.ledgerOrderSummary(side, formatPolyAmount(ref, order.sz * order.limitPx), formatHlPrice(order.limitPx, decimalCap: market?.pxDecimalCap))}',
        action: onCancel == null
            ? null
            : AppButton(
                text: l10n.ledgerCancelOrderSummary,
                compact: true,
                variant: AppButtonVariant.secondary,
                onPressed: onCancel,
              ),
      ),
    );
  }
}

String _trimNumber(double value) {
  final fixed = value.toStringAsFixed(value.abs() >= 1000 ? 2 : 6);
  if (!fixed.contains('.')) return fixed;
  return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
}
