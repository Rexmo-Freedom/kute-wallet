// lib/screens/portfolio/portfolio_filters.dart
//
// What the one Portfolio screen carries, and the pill row it switches
// with. The Portfolio is the spending account's: both venues on one
// screen, the same from every door (owner decision October 2026: the
// Portfolio button used to open a different screen per tab). A venue the
// shell would not draw a tab for (shellShowsTradingTab /
// shellShowsPredictionsTab) is absent here too: no pill, no section.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/screens/home/shell_venue_tabs.dart'
    show shellShowsPredictionsTab, shellShowsTradingTab;
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/services/runtime_capabilities_service.dart';

/// Which venues the Portfolio shows.
@immutable
class PortfolioVenues {
  /// Investing (Hyperliquid).
  final bool trading;

  /// Predictions (Polymarket).
  final bool predictions;

  const PortfolioVenues({required this.trading, required this.predictions});

  bool get any => trading || predictions;

  @override
  bool operator ==(Object other) =>
      other is PortfolioVenues &&
      other.trading == trading &&
      other.predictions == predictions;

  @override
  int get hashCode => Object.hash(trading, predictions);
}

/// The shell's own tab rules, applied to the spending account the
/// Portfolio belongs to.
final portfolioVenuesProvider = Provider<PortfolioVenues>((ref) {
  final spending = pickSpendingWallet(ref.watch(settingsProvider));
  final policy = ref.watch(runtimeCapabilitiesProvider);
  return PortfolioVenues(
    trading: shellShowsTradingTab(spending, policy: policy),
    predictions: shellShowsPredictionsTab(spending, policy: policy),
  );
});

/// A row of the app's small pills ([KutePill]) at natural width, the
/// Statistics Active | Historic pair's layout: under very large text they
/// share the row rather than overflow it.
class PortfolioPillRow<T> extends StatelessWidget {
  const PortfolioPillRow({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelected,
  });

  /// Each pill's value, label and key, in order.
  final List<(T, String, Key)> items;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 4.h),
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) SizedBox(width: 6.w),
              Flexible(
                child: KutePill(
                  key: items[i].$3,
                  label: items[i].$2,
                  selected: items[i].$1 == selected,
                  onTap: () => onSelected(items[i].$1),
                ),
              ),
            ],
          ],
        ),
      );
}
