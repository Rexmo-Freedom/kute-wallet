import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/unified_search_provider.dart'
    show SearchCategory;
import 'package:kute/screens/home/components/kute_bottom_action_bar.dart';
import 'package:kute/screens/portfolio/open_investments_screen.dart';
import 'package:kute/screens/search/unified_search_screen.dart';

/// Shared dock for the spending account's venue browsers when they stand
/// on their own: Portfolio in the dock, and the square button is this
/// surface's way into search, scoped to the venue's own markets.
///
/// With one balance (October 2026) the hot wallet has no venue Withdraw:
/// money comes back to Dollars on its own, so the dock carries Portfolio
/// alone. Portfolio opens the one Portfolio screen, full screen, as the
/// Investments balance does.
class InvestmentActionBar extends ConsumerWidget {
  final InvestmentsProduct product;
  final ValueChanged<double>? onHeightChanged;

  const InvestmentActionBar({
    super.key,
    required this.product,
    this.onHeightChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final predictions = product == InvestmentsProduct.predictions;
    final source = predictions ? 'predictions' : 'trading';

    return KuteBottomActionBar(
      source: source,
      onHeightChanged: onHeightChanged,
      actions: [
        // The Portfolio, in the solid CTA fill so the dock leads with it.
        KuteDockAction(
          icon: Icons.pie_chart_rounded,
          label: context.l10n.walletPortfolioAction,
          trackingId: 'portfolio',
          solid: true,
          onTap: () => OpenInvestmentsScreen.show(context,
              source: predictions ? 'dock_predictions' : 'dock_investing'),
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
        source: source,
      ),
    );
  }
}
