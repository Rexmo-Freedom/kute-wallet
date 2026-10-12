// lib/screens/usd/components/usd_balance_tabs.dart
//
// The Portfolio's Earn section (Portfolio › Statistics › Earn): the Earn
// content alone — the yield and the next payment the dollar balance
// earns ([UsdEarnChart]).
//
// This used to be the Dollars tab's Balance tab, with Balance | Earn
// pills over the card, then an Investments pill of its own. It is a
// section of the Portfolio's Statistics tab now (owner decision October
// 2026), so the inner Balance pill and the dollar balance chart are gone
// from here: the section IS the Earn view.
//
// EARN IS GATED BY THE BACKEND. The `usd.earn` capability
// (usdEarnEnabledProvider) decides whether the Earn pill exists at all;
// the Statistics tab mounts this widget only once that pill has been
// picked, so the rewards API is never read and `usd_earn_opened` never
// fires for someone who only looks at the venue figures. Off, or with no
// policy to read, this widget is never built.

import 'package:flutter/material.dart';

import 'package:kute/screens/usd/components/usd_earn_chart.dart';

/// The Earn chart, as the Portfolio's Earn section shows it.
class UsdBalanceTabs extends StatelessWidget {
  const UsdBalanceTabs({super.key});

  @override
  Widget build(BuildContext context) => const UsdEarnChart();
}
