import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/unified_search_provider.dart'
    show SearchCategory;
import 'package:kute/screens/home/components/kute_bottom_action_bar.dart';
import 'package:kute/screens/ledger/ledger_account_body.dart';
import 'package:kute/screens/ledger/ledger_portfolio_screen.dart';
import 'package:kute/screens/ledger/ledger_venue_funding.dart';
import 'package:kute/screens/portfolio/open_investments_screen.dart'
    show InvestmentsProduct;
import 'package:kute/screens/search/unified_search_screen.dart';

/// Search and money actions stay bound to the displayed hardware wallet.
/// A venue tab's dock is Portfolio and Withdraw (Deposit is the venue's top
/// button); on the Ledger portfolio screen itself ([onPortfolio]) it is
/// Deposit and Withdraw, as on the spending account's.
class LedgerAccountActionBar extends ConsumerWidget {
  const LedgerAccountActionBar({
    super.key,
    required this.walletId,
    required this.tab,
    this.onHeightChanged,
    this.onPortfolio = false,
  });

  final String walletId;
  final LedgerAccountTab tab;
  final ValueChanged<double>? onHeightChanged;

  /// True when this dock sits on the Ledger portfolio screen.
  final bool onPortfolio;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final predictionsTab = tab == LedgerAccountTab.predictions;
    final funding = tab == LedgerAccountTab.bitcoin
        ? null
        : ledgerVenueFunding(context, ref, walletId: walletId, tab: tab);
    // Withdrawal opens even before a balance is loaded.
    final actions = funding == null
        ? const <KuteDockAction>[]
        : [
            if (onPortfolio)
              KuteDockAction(
                icon: Icons.south_west_rounded,
                label: l10n.deposit,
                trackingId: 'deposit',
                onTap: funding.deposit,
              )
            else
              KuteDockAction(
                icon: Icons.pie_chart_rounded,
                label: l10n.walletPortfolioAction,
                trackingId: 'portfolio',
                solid: true,
                onTap: () => LedgerPortfolioScreen.show(context,
                    walletId: walletId,
                    product: predictionsTab
                        ? InvestmentsProduct.predictions
                        : InvestmentsProduct.trading),
              ),
            KuteDockAction(
              icon: Icons.north_east_rounded,
              label: l10n.withdraw,
              trackingId: 'withdraw',
              onTap: funding.withdraw,
            ),
          ];
    final source = 'ledger_${tab.trackingName}';
    return KuteBottomActionBar(
      source: source,
      onHeightChanged: onHeightChanged,
      actions: actions,
      // The square is search on every tab: this Ledger's own activity on
      // the Bitcoin tab, and market search opening results on this Ledger
      // wallet's Predictions / Investing targets on the venue tabs, locked
      // to the venue the way it was when it opened as its own screen.
      onSearch: tab == LedgerAccountTab.bitcoin
          ? () => showKuteSearch(context, source: source, walletId: walletId)
          : () => showKuteSearch(
                context,
                initialCategory: predictionsTab
                    ? SearchCategory.predictions
                    : SearchCategory.perpetuals,
                ledgerWalletId: walletId,
                searchHint: predictionsTab
                    ? l10n.searchPredictionsHint
                    : l10n.searchInvestmentsHint,
                source: source,
                searchFirst: true,
                lockCategory: true,
              ),
    );
  }
}
