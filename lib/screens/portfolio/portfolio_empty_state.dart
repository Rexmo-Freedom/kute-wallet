// lib/screens/portfolio/portfolio_empty_state.dart
//
// The Portfolio's empty states.
//
//   * [PortfolioEmptyState]: an empty Portfolio tab on the older surfaces
//     (a Ledger's tabs, the Portfolio screen the Predictions card opens),
//     the app's empty state centred clear of the dock.
//   * [PortfolioSectionEmpty]: the Portfolio
//     screen's sections under the pinned strip (Portfolio | P&L Charts;
//     Activity moved to the Bitcoin home the same day). ONE treatment
//     for both (founder, 1 November 2026: "empty states must be the same
//     on all three sections"; the
//     P&L one was the one he liked): the hero Sal ([NoActivityState]:
//     `body_hero` with its idle director) at [kPortfolioSectionEmptySal],
//     the title 22 sp w600, the rotating tagline 15 sp in textSecondary,
//     [kPortfolioSectionEmptyTop] under the strip, so switching sections
//     moves neither Sal nor the text; only the copy changes ("No open
//     positions", "No P&L yet", each section starting the shared taglines
//     at its own line). No pixel Sal.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/screens/home/components/kute_dock_host.dart'
    show KuteDockClearance;
import 'package:kute/screens/shared/no_activity_state.dart';
import 'package:kute/theme/app_theme.dart';

/// An empty Portfolio tab (Open, Orders, Activity, Statistics): the app's
/// empty state ([NoActivityState], Sal over the headline and a rotating
/// tagline, as Home's "No activity yet") with the tab's own headline,
/// centred clear of the dock. Informational only: browsing stays on the
/// product pages. Sal settles after a few cycles, as on every surface a
/// person may leave open.
class PortfolioEmptyState extends StatelessWidget {
  const PortfolioEmptyState(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) => KuteDockClearance(
        child: Center(
          child: SingleChildScrollView(
            child: NoActivityState(title: title, cycles: 3),
          ),
        ),
      );
}

/// Sal's size in a Portfolio section's empty state, in design units.
const double kPortfolioSectionEmptySal = 160;

/// The room between the section's top (right under the pinned strip) and
/// Sal, in design units. The Portfolio section reaches it as its list's 4
/// top inset plus the overview's 18 gap (components/balances_overview.dart);
/// P&L Charts pads by it directly (investments_portfolio.dart, _ChartsBox).
const double kPortfolioSectionEmptyTop = 22;

/// Where each section starts the shared taglines, so the three never open
/// on the same line.
enum PortfolioSectionTagline {
  portfolio(0),
  pnl(4);

  const PortfolioSectionTagline(this.start);
  final int start;
}

/// A Portfolio section's empty state, the one treatment (see the file
/// header). It carries no top gap: its host puts it
/// [kPortfolioSectionEmptyTop] under the strip.
class PortfolioSectionEmpty extends StatelessWidget {
  const PortfolioSectionEmpty(
      {super.key, required this.title, required this.tagline});

  final String title;
  final PortfolioSectionTagline tagline;

  @override
  Widget build(BuildContext context) => NoActivityState(
        padding: EdgeInsets.symmetric(horizontal: 24.w),
        title: title,
        cycles: 3,
        salSize: kPortfolioSectionEmptySal,
        titleSize: 22,
        titleWeight: FontWeight.w600,
        subtitleSize: 15,
        subtitleColor: context.colors.textSecondary,
        taglineStart: tagline.start,
      );
}
