// lib/screens/portfolio/portfolio_screen.dart
//
// THE PORTFOLIO AS ITS OWN SCREEN (founder, 31 October 2026: "since we
// only have 2 buttons on the top now, we should and must have the
// portfolio part of the add and send on the top, maybe as a new screen?
// and we have more space for everything there"). The Dollars tab's action
// row is Add · Send · Portfolio; Portfolio pushes this, full screen, over
// the shell (route `/portfolio`, app_router.dart), with the app's standard
// back. NO BALANCE HERO and no Available to invest (founder, 31 October
// 2026: "Portfolio is just open positions. On top, instead of the
// balance, show the shares with the pie chart on the left"). Laid out on
// the fintech pattern (Robinhood, Revolut, Wealthfront; the founder's
// redo of the same day, after a card-with-rows draft "looked so bad"),
// top down, no card around the top block: the HERO, the allocation ring
// big and centred (150, a 14 stroke, the three share colours) with the
// all-time P&L in its hole; under it one quiet legend line (Investing,
// Predictions, Dollars: dot and name, no amounts; founder, 31 October
// 2026: "only auto managed", no allocation tiles and no Move money
// button, money moves from the Add and Send flows); the section switch
// (Portfolio | P&L Charts | Activity, the home strip); then the open
// positions by venue under small-caps labels, each venue one soft card
// (BalancesOverview.sharesHeader, components/balances_overview.dart). No
// total: the Dollars tab has it. The WHOLE page scrolls (founder, 1
// November 2026): the ring block scrolls away with the section and the
// strip pins under the app bar (investments_portfolio.dart,
// _PortfolioPage). No dock: Add and Send are not repeated here.
//
// A deep link naming a Portfolio section (`/usd?tab=portfolio|positions|
// orders|activity…`, PortfolioSection.forLink) opens this screen on that
// section (usd_account_screen.dart, openInvestmentsPortfolio), as do a
// filled order's "View positions", a resting order's "View orders" and a
// trade notification.
//
// THE BAR SHARES WHAT THE SECTION SHOWS (founder, 2 November 2026: "On
// share and brag portfolio we should say share portfolio on the bottom.
// PnL should say [something else]"): on Portfolio, with a position open
// or a P&L off zero, "Share portfolio" opens the portfolio card; on P&L
// Charts, with a P&L drawn, "Share P&L" opens the P&L card for the range
// (and the venue) picked on the chart (brag_preview_sheet.dart). The
// label morphs on a switch like every bar label (kute_morph_label.dart).
// Nothing to share: the default bar.
//
// Analytics: the existing `analytics_tab_selected` on a section pill
// (surface investments, tab positions, sub / from_sub), as the Investments
// page sent it; the screen itself adds no event (experimental branch).

import 'dart:async';

import 'package:kute/screens/portfolio/components/portfolio_pnl_chart.dart'
    show pnlChartRangeProvider, pnlChartVenueProvider;
import 'package:kute/screens/share/brag/brag_data.dart'
    show bragPnlAvailableProvider, bragPortfolioAvailableProvider;
import 'package:kute/screens/share/brag/brag_preview_sheet.dart'
    show showBragPnlPreviewSheet, showBragPortfolioPreviewSheet;
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/portfolio/investments_portfolio.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// The Portfolio, full screen (see the file header).
class PortfolioScreen extends ConsumerWidget {
  const PortfolioScreen({super.key});

  /// The route the shell pushes it on.
  static const String route = '/portfolio';

  /// A section pill: the strip's event again, the pill staying
  /// `positions` (so `from_tab` equals `tab`) with the section as `sub`
  /// and the one it left as `from_sub`; then the section is written.
  static void pickSection(WidgetRef ref, PortfolioSection next) {
    final current = ref.read(portfolioSectionProvider);
    if (next == current) return;
    HapticFeedback.selectionClick();
    TrackingService.track('analytics_tab_selected', params: {
      'tab': 'positions',
      'from_tab': 'positions',
      'surface': 'investments',
      'sub': next.key,
      'from_sub': current.key,
    });
    ref.read(portfolioSectionProvider.notifier).state = next;
  }

  /// The bar over [section] (see the file header).
  static KuteBarContext barContext(
      BuildContext context, WidgetRef ref, PortfolioSection section) {
    final l10n = context.l10n;
    final share = switch (section) {
      PortfolioSection.balances =>
        ref.watch(bragPortfolioAvailableProvider)
            ? (
                l10n.bragPortfolioBarLabel,
                () => unawaited(showBragPortfolioPreviewSheet(context)),
              )
            : null,
      PortfolioSection.charts => ref.watch(bragPnlAvailableProvider)
          ? (
              l10n.bragPnlBarLabel,
              () => unawaited(showBragPnlPreviewSheet(context,
                  range: ref.read(pnlChartRangeProvider),
                  venue: ref.read(pnlChartVenueProvider))),
            )
          : null,
    };
    if (share == null) {
      return KuteBarContext(label: l10n.searchOrManageAi, source: 'portfolio');
    }
    return KuteBarContext.primary(
      label: share.$1,
      onPrimary: share.$2,
      // Never off: the card always opens.
      disabledLabel: null,
      source: 'portfolio',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final section = ref.watch(portfolioSectionProvider);
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: const KuteBackButton(fallbackRoute: '/usd'),
        title: Text(
          context.l10n.walletPortfolioAction,
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 20.sp,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
      ),
      body: Container(
        decoration: AppDecorations.screenGradient(context),
        child: SafeArea(
          top: false,
          bottom: false,
          child: Material(
            color: Colors.transparent,
            // The bar over this page: the default search and Sal, no row
            // of its own (founder, 31 October 2026: "only auto managed";
            // money moves from the Add and Send flows).
            // Share (founder, 1 and 2 November 2026): with something to
            // share, the bar is the section's own share, "Share portfolio"
            // or "Share P&L" ([barContext]); the Sal sheet stays a long
            // press away.
            child: KuteBarContextScope(
              barContext: barContext(context, ref, section),
              // The bar floats over the list (nothing reserves room); each
              // section ends its own scroll with the bar's clearance
              // (kuteBarScrollClearance, investments_portfolio.dart), so
              // the last row scrolls clear of the bar.
              child: InvestmentsPortfolio(
                sharesHeader: true,
                onSection: (section) => pickSection(ref, section),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
