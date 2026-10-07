import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/unified_search_provider.dart'
    show SearchCategory;
import 'package:kute/screens/home/components/kute_bottom_action_bar.dart';
import 'package:kute/screens/portfolio/open_investments_screen.dart';
import 'package:kute/screens/search/unified_search_screen.dart';
import 'package:kute/screens/shared/investment_funding.dart';

/// Shared dock for the active wallet's venues: Portfolio and Withdraw sit
/// in the dock itself (Deposit is the venue's top button), and the square
/// button is this surface's way into search, scoped to the venue's own
/// markets. On the Portfolio screen itself ([onPortfolio]) the pair is
/// Deposit and Withdraw: that screen has no top button, and a Portfolio
/// door to the screen you are on would be a loop.
class InvestmentActionBar extends ConsumerWidget {
  final InvestmentsProduct product;
  final ValueChanged<double>? onHeightChanged;

  /// Analytics source for the search this dock opens, when the host reports
  /// itself as something other than the venue screen (the portfolio views).
  final String? searchSource;

  /// True when this dock sits on the Portfolio screen.
  final bool onPortfolio;

  const InvestmentActionBar({
    super.key,
    required this.product,
    this.onHeightChanged,
    this.searchSource,
    this.onPortfolio = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final predictions = product == InvestmentsProduct.predictions;
    final source = predictions ? 'predictions' : 'trading';

    return KuteBottomActionBar(
      source: source,
      onHeightChanged: onHeightChanged,
      actions: [
        if (onPortfolio)
          KuteDockAction(
            icon: Icons.south_west_rounded,
            label: context.l10n.deposit,
            trackingId: 'deposit',
            onTap: () =>
                openInvestmentFunding(context, ref, product, deposit: true),
          )
        else
          // Opens the venue's portfolio exactly as the top button did, in
          // the solid CTA fill so the dock leads with it.
          KuteDockAction(
            icon: Icons.pie_chart_rounded,
            label: context.l10n.walletPortfolioAction,
            trackingId: 'portfolio',
            solid: true,
            onTap: () => Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(
                    builder: (_) => OpenInvestmentsScreen(product: product))),
          ),
        KuteDockAction(
          icon: Icons.north_east_rounded,
          label: context.l10n.withdraw,
          trackingId: 'withdraw',
          onTap: () =>
              openInvestmentFunding(context, ref, product, deposit: false),
        ),
      ],
      // A venue dock searches its own markets: the search sheet opens on
      // this venue's tab, results first.
      onSearch: () => showKuteSearch(
        context,
        initialCategory: predictions
            ? SearchCategory.predictions
            : SearchCategory.perpetuals,
        searchFirst: true,
        searchHint: predictions
            ? context.l10n.searchPredictionsHint
            : context.l10n.searchInvestmentsHint,
        source: searchSource ?? source,
      ),
    );
  }
}
