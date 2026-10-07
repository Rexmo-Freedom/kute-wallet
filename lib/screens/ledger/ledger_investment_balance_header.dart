import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/helpers/formatters/polymarket_amount_formatter.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/hyperliquid_provider.dart';
import 'package:kute/providers/ledger/ledger_hyperliquid_account_provider.dart';
import 'package:kute/providers/ledger/ledger_identity_provider.dart';
import 'package:kute/providers/ledger/ledger_pm_buying_power_provider.dart';
import 'package:kute/providers/ledger/ledger_polymarket_account_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/ledger/ledger_hyperliquid_tab.dart';
import 'package:kute/screens/ledger/ledger_polymarket_tab.dart';
import 'package:kute/screens/portfolio/open_investments_screen.dart';
import 'package:kute/screens/shared/pool_balance_header.dart';
import 'package:kute/screens/ledger/ledger_account_body.dart'
    show LedgerAccountTab;
import 'package:kute/screens/ledger/ledger_venue_funding.dart';
import 'package:kute/screens/shared/venue_deposit_button.dart';
import 'package:kute/services/venue_total_cache_service.dart';

/// Balance and the venue's Deposit button for the exact verified Ledger.
/// Shared by the venue overview and full-screen portfolio; no
/// spending-account fallback. [showDepositButton] is the overview's; the
/// portfolio screen's dock carries Deposit instead.
class LedgerInvestmentBalanceHeader extends ConsumerWidget {
  const LedgerInvestmentBalanceHeader({
    super.key,
    required this.walletId,
    required this.product,
    this.showDepositButton = false,
  });

  final String walletId;
  final InvestmentsProduct product;
  final bool showDepositButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(ledgerIdentityProvider(walletId));
    if (identity == null ||
        identity.walletId != walletId ||
        !identity.hasVerifiedEvm) {
      return const SizedBox.shrink();
    }
    final visible = ref.watch(settingsProvider.select((s) => s.balanceVisible));
    String amount(double? value) => !visible
        ? '••••••'
        : value == null
            ? context.l10n.ledgerBalanceUnavailable
            : formatPolyAmount(ref, value);
    final trading = product == InvestmentsProduct.trading;
    final venue = trading ? 'trading' : 'predictions';
    final totalLabel =
        trading ? context.l10n.investingTotal : context.l10n.predictionsTotal;
    // Never "unavailable" in the headline: without a fresh total (still
    // reading, or a read that failed) this Ledger's last known one,
    // dimmed, until the next sync brings a fresh one; with nothing known
    // yet, a skeleton of the figure's size.
    VenueTotal total(double? fresh) =>
        resolveVenueTotal(walletId: walletId, venue: venue, fresh: fresh);
    Widget lastKnown({required bool loading}) {
      final cached = total(null);
      if (cached.value == null && !loading) return const SizedBox.shrink();
      return PoolBalanceHeader(
          loading: cached.value == null,
          stale: cached.stale,
          amountText: amount(cached.value),
          totalLabel: totalLabel,
          showActionRow: false);
    }

    // Deposit is the top button; Portfolio moved into the dock (owner
    // decision: each job has one home). Resolved only when drawn: the
    // funding read watches the venue account this header already reads.
    Widget? depositButton() => showDepositButton
        ? VenueDepositButton(
            product: product,
            source: trading ? 'ledger_investing' : 'ledger_predictions',
            onTap: ledgerVenueFunding(context, ref,
                    walletId: walletId,
                    tab: trading
                        ? LedgerAccountTab.investing
                        : LedgerAccountTab.predictions)
                .deposit,
          )
        : null;

    if (product == InvestmentsProduct.trading) {
      final accountAsync = ref.watch(ledgerHlAccountProvider(walletId));
      final data = accountAsync.valueOrNull;
      if (data == null) return lastKnown(loading: accountAsync.isLoading);
      if (data.walletId != walletId ||
          data.address?.toLowerCase() != identity.evmAddress!.toLowerCase()) {
        return const SizedBox.shrink();
      }
      final totals = LedgerHlTotals.of(data);
      final hasSpot = data.account?.spotBalances
              .any((b) => b.coin != 'USDC' && b.total > 0) ??
          false;
      // Public prices only, queried solely when this Ledger holds noncash spot.
      final prices = hasSpot
          ? ref.watch(hyperliquidSpotTickersProvider).valueOrNull?.tickers
          : null;
      final invested = ledgerHlPortfolioValue(data,
          spotPrices:
              prices?.map((coin, ticker) => MapEntry(coin, ticker.markPrice)) ??
                  const <String, double>{});
      // Ledger mirrors Home: the total leads, with the split under it.
      final available = totals.available;
      final fresh = available == null || invested == null
          ? (available ?? invested)
          : available + invested;
      final shown = total(fresh);
      return PoolBalanceHeader(
        loading: shown.value == null,
        stale: shown.stale,
        amountText: amount(shown.value),
        totalLabel: totalLabel,
        investedLabel: context.l10n.ledgerPositionsTitle,
        investedText: (fresh ?? 0) > 0 ? amount(invested) : null,
        availableText: (fresh ?? 0) > 0 ? amount(available) : null,
        availableLabel: context.l10n.available,
        primaryCta: depositButton(),
        // The Earn shortcut is gone: Earn is the dollar balance's product
        // now, not the investing account's.
        showActionRow: false,
      );
    }

    final pmAsync = ref.watch(ledgerPmAccountProvider(walletId));
    final data = pmAsync.valueOrNull;
    if (data == null) return lastKnown(loading: pmAsync.isLoading);
    if (data.walletId != walletId ||
        data.eoa?.toLowerCase() != identity.evmAddress!.toLowerCase()) {
      return const SizedBox.shrink();
    }
    final buyingPower = ref.watch(ledgerPmBuyingPowerProvider(walletId));
    final verifiedSpendable = buyingPower.isLoading || buyingPower.hasError
        ? null
        : buyingPower.valueOrNull?.spendable;
    final totals = LedgerPmTotals.of(data);
    final hasBalance = (totals.total ?? 0) > 0;
    // Only the authenticated, address-scoped buying-power read establishes
    // spendable cash; the difference to public cash is what open orders hold.
    final spendable =
        verifiedSpendable == null ? null : verifiedSpendable.toDouble() / 1e6;
    final committed = spendable == null || totals.cash == null
        ? null
        : totals.cash! - spendable;
    final shown = total(totals.total);
    return PoolBalanceHeader(
      loading: shown.value == null,
      stale: shown.stale,
      amountText: amount(shown.value),
      totalLabel: totalLabel,
      balanceDetail: committed != null && committed > 0.005
          ? context.l10n.investingInOpenOrders(amount(committed))
          : null,
      investedText: hasBalance && totals.positionsValue != null
          ? amount(totals.positionsValue)
          : null,
      investedLabel: context.l10n.ledgerPositionsTitle,
      availableText: !hasBalance
          ? null
          : spendable != null
              ? amount(spendable)
              : totals.cash == null
                  ? null
                  : amount(totals.cash),
      availableLabel: context.l10n.available,
      primaryCta: depositButton(),
      // Build is hidden here exactly as it is on the spending account's
      // Predictions header (owner decision: it is not wanted beside this
      // balance). The builder screen and its route stay, so bringing it
      // back is one line.
      trailingCta: null,
      showActionRow: false,
    );
  }
}

/// Committed account equity, held cash and spot holdings. The position
/// notional is deliberately excluded because it includes leverage.
double? ledgerHlPortfolioValue(LedgerHlAccount data,
    {Map<String, double> spotPrices = const {}}) {
  final account = data.account;
  if (account == null ||
      data.partialFailures.contains(LedgerHlReadCategory.hip3Dexes)) {
    return null;
  }
  var value = [account, ...data.dexAccounts.values].fold<double>(
      0,
      (sum, a) =>
          sum + (a.accountValue - a.withdrawable).clamp(0, double.infinity));
  for (final balance in account.spotBalances) {
    if (balance.coin == 'USDC') {
      value += (balance.total - balance.available).clamp(0, double.infinity);
    } else if (balance.total > 0) {
      final price = spotPrices[balance.coin];
      if (price == null || !price.isFinite || price <= 0) return null;
      value += balance.total * price;
    }
  }
  return value.isFinite ? value : null;
}
