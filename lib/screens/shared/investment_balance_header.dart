import 'package:kute/screens/shared/kute_dog_scenes.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/helpers/formatters/polymarket_amount_formatter.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/investment_balances_provider.dart';
import 'package:kute/providers/pending_pool_deposits_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/services/venue_total_cache_service.dart';
import 'package:kute/screens/portfolio/open_investments_screen.dart';
import 'package:kute/screens/shared/pending_deposit_line.dart';
import 'package:kute/screens/shared/pool_balance_header.dart';
import 'package:kute/screens/shared/portfolio_builder/builder_legs_provider.dart';
import 'package:kute/screens/shared/portfolio_builder/portfolio_builder_screen.dart';
import 'package:kute/screens/shared/investment_funding.dart';
import 'package:kute/screens/shared/venue_deposit_button.dart';
import 'package:kute/theme/app_theme.dart';

/// Only discovery is replaced. The balance, withdrawal and portfolio doors
/// remain available above this notice under their independent capabilities.

/// The portfolio builder (and combos through it) is not exposed yet
/// (user decision 5 October 2026). Its code stays; only the entry is hidden.
const bool kShowPortfolioBuilder = false;

class InvestmentDiscoveryNotice extends ConsumerWidget {
  const InvestmentDiscoveryNotice({super.key, required this.capability});
  final String capability;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: KuteDogNotHere(
                width: 220,
                ink: context.colors.textPrimary,
                accent: context.colors.accent,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              ref
                  .watch(runtimeCapabilitiesProvider)
                  .decision(capability)
                  .message,
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontSize: 16, color: context.colors.textSecondary),
            ),
          ],
        ),
      );
}

/// Shared by each market browser and its full-screen portfolio. Investing
/// shows spendable cash; Predictions shows its total with a cash/position split.
///
/// [showDepositButton]: the venue's Deposit button under the balance (the
/// market browsers). The Portfolio screen hides it; its dock carries
/// Deposit there.
class InvestmentBalanceHeader extends ConsumerWidget {
  final InvestmentsProduct product;
  final bool showDepositButton;

  const InvestmentBalanceHeader({
    super.key,
    required this.product,
    this.showDepositButton = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final predictions = product == InvestmentsProduct.predictions;
    final balances = ref.watch(investmentBalancesProvider(product));
    final visible = ref.watch(settingsProvider.select((s) => s.balanceVisible));
    String amount(double? value) => !visible
        ? '••••••'
        : value == null
            ? '—'
            : formatPolyAmount(ref, value);
    final pending = ref.watch(predictions
        ? pendingPredictionsDepositUsdProvider
        : pendingTradingDepositUsdProvider);
    final leaving = ref.watch(predictions
        ? pendingPredictionsWithdrawalUsdProvider
        : pendingTradingWithdrawalUsdProvider);

    // Both pools lead with the TOTAL and split it underneath (owner
    // decision). Investing led with spendable cash alone, which read as
    // the whole account and quietly left every open position out of the
    // figure at the top of the screen.
    final hasBalance = (balances.total ?? 0) > 0;
    // Never a bare dash (owner: "this looks bad"). Without a fresh total
    // (the account still on its way, or a read that failed) the header
    // shows this wallet's last known one, dimmed, and the next sync or
    // pull-to-refresh replaces it; with nothing known yet, a skeleton of
    // the figure's size.
    final total = resolveVenueTotal(
        walletId: ref
            .watch(settingsProvider.select((s) => pickSpendingWallet(s)?.id)),
        venue: predictions ? 'predictions' : 'trading',
        fresh: balances.total);
    return PoolBalanceHeader(
      loading: total.value == null,
      stale: total.stale,
      amountText: amount(total.value),
      totalLabel: predictions
          ? context.l10n.predictionsTotal
          : context.l10n.investingTotal,
      investedLabel: context.l10n.ledgerPositionsTitle,
      availableLabel: context.l10n.available,
      // What is at work: the prediction positions, or everything
      // Investing holds beyond spendable cash.
      investedText: hasBalance
          ? amount(predictions ? balances.positions : balances.portfolio)
          : null,
      availableText: hasBalance ? amount(balances.available) : null,
      balanceDetail: predictions && (balances.committed ?? 0) > 0
          ? context.l10n.investingInOpenOrders(amount(balances.committed))
          : null,
      showActionRow: false,
      // This header carries no shortcut any more.
      //
      // Earn used to sit here, on Investing only. It belongs to the
      // dollar balance now, so Investing does not offer it at all (user
      // decision September 2026).
      //
      // Predictions carries the Build shortcut to the portfolio builder
      // beside Deposit, where the scanner sits on Bitcoin: it is the way
      // into combos. Hidden until the builder ships ([kShowPortfolioBuilder]).
      trailingCta: kShowPortfolioBuilder && showDepositButton && predictions
          ? PoolHeaderShortcut(
              label: context.l10n.builderStepBuild,
              icon: Icons.add_chart_rounded,
              showLabel: false,
              onTap: () =>
                  PortfolioBuilderScreen.show(context, BuilderPool.predictions),
            )
          : null,
      // Deposit is the top button; Portfolio moved into the dock (owner
      // decision: each job has one home).
      primaryCta: showDepositButton
          ? VenueDepositButton(
              product: product,
              source: predictions ? 'predictions' : 'trading',
              onTap: () =>
                  openInvestmentFunding(context, ref, product, deposit: true),
            )
          : null,
      investedChild: pending > 0 || leaving > 0
          ? PendingDepositLine(
              investedText: '',
              pendingText: pending > 0
                  ? visible
                      ? formatPolyFiatForced(ref, pending)
                      : '••••••'
                  : null,
              leavingText: leaving > 0
                  ? visible
                      ? formatPolyFiatForced(ref, leaving)
                      : '••••••'
                  : null,
            )
          : null,
    );
  }
}
