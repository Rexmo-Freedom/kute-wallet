// lib/screens/portfolio/portfolio_filters.dart
//
// What the one Portfolio screen carries. The Portfolio is the spending
// account's: both venues on one screen, the same from every door (owner
// decision October 2026: the Portfolio button used to open a different
// screen per tab). A venue the shell would not draw a tab for
// (shellShowsTradingTab / shellShowsPredictionsTab) is absent here too:
// no section, no rows. The venue pill rows the tabs used to switch with
// are gone (owner decision October 2026: every tab shows both venues).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/screens/home/shell_venue_tabs.dart'
    show shellShowsPredictionsTab, shellShowsTradingTab;
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
