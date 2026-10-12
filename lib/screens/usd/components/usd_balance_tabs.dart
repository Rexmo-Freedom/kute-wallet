// lib/screens/usd/components/usd_balance_tabs.dart
//
// The Dollars tab's Balance tab when the rewards programme may be shown:
// two small pills above the card, Balance | Earn, the way the Breakdown
// tab nests Sent | Received and Statistics nests Active | Historic.
//
// EARN IS A VIEW OF THE BALANCE (owner decision: "the Earn should be
// inside the Balance option like we do with the breakdown"). The
// programme pays on the dollars this card already charts, so it is a
// second reading of the same money, not a tab of its own in the strip.
// Balance is picked first; Earn mounts [UsdEarnChart] only when tapped,
// so the rewards API is never read and `usd_earn_opened` never fires for
// someone who only looks at the balance.
//
// When the `usd.earn` capability is off the screen passes the bare
// [UsdBalanceChart] instead and this widget is never built: no pills, no
// Earn, exactly the strip the gate test pins.
//
// The switch sends `analytics_tab_selected` with the tab names the strip
// used while Earn was a top-level pill (`earn` / `valuation`, surface
// `usd`), so the existing PostHog tiles keep counting Earn opens.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/screens/usd/components/usd_balance_chart.dart';
import 'package:kute/screens/usd/components/usd_earn_chart.dart';
import 'package:kute/services/tracking_service.dart';

/// Which reading of the dollar balance the card shows.
enum UsdBalanceView { balance, earn }

/// Balance | Earn pills over the dollar balance card.
class UsdBalanceTabs extends StatefulWidget {
  const UsdBalanceTabs({super.key});

  @override
  State<UsdBalanceTabs> createState() => _UsdBalanceTabsState();
}

class _UsdBalanceTabsState extends State<UsdBalanceTabs> {
  UsdBalanceView _view = UsdBalanceView.balance;

  /// The strip's own tab names, so the event reads as it did when Earn
  /// was a pill of the strip.
  static String _tabName(UsdBalanceView view) =>
      view == UsdBalanceView.earn ? 'earn' : 'valuation';

  void _pick(UsdBalanceView next) {
    if (next == _view) return;
    HapticFeedback.selectionClick();
    TrackingService.track('analytics_tab_selected', params: {
      'tab': _tabName(next),
      'from_tab': _tabName(_view),
      'surface': 'usd',
    });
    setState(() => _view = next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Natural width, as the Sent | Received pair.
        Row(
          children: [
            KutePill(
              key: const ValueKey('usd-balance-view-balance'),
              label: l10n.balance,
              selected: _view == UsdBalanceView.balance,
              onTap: () => _pick(UsdBalanceView.balance),
            ),
            SizedBox(width: 6.w),
            KutePill(
              key: const ValueKey('usd-balance-view-earn'),
              label: l10n.usdEarnTitle,
              selected: _view == UsdBalanceView.earn,
              onTap: () => _pick(UsdBalanceView.earn),
            ),
          ],
        ),
        SizedBox(height: 12.h),
        // Only the picked view is mounted: the Earn chart's reads and its
        // open event belong to the moment someone actually opens it.
        if (_view == UsdBalanceView.earn)
          const UsdEarnChart()
        else
          const UsdBalanceChart(),
      ],
    );
  }
}
