// lib/screens/portfolio/portfolio_screen.dart
//
// THE PORTFOLIO AS ITS OWN SCREEN (founder, 31 October 2026: "since we
// only have 2 buttons on the top now, we should and must have the
// portfolio part of the add and send on the top, maybe as a new screen?
// and we have more space for everything there"). The Dollars tab's action
// row and its Activity tab's "See full portfolio and activity" push this,
// full screen, over the shell (route `/portfolio`, app_router.dart), with
// the app's standard back. No dock: Add and Send are not repeated here.
//
// Overhauled on 4 November 2026 (founder: "the top chart means nothing,
// it's super confusing … much, much, much better fintech design
// comparable to the rest of the app"), the page is investments_portfolio
// .dart's, top down: the hero ("Invested", the figure, the P&L over the
// range, ONE P&L chart with its ranges, "3 positions · Available $17.64";
// components/portfolio_hero.dart), the Activity | Positions | P&L switch
// pinned under the app bar once it reaches it, then the section. The
// allocation ring that read each section is gone.
//
// A deep link naming a Portfolio section (`/usd?tab=portfolio|positions|
// orders…`, PortfolioSection.forLink) opens this screen on that section
// (usd_account_screen.dart, openInvestmentsPortfolio), as do a filled
// order's "View positions", a resting order's "View orders" and a trade
// notification.
//
// THE BAR SHARES WHAT THE PAGE SHOWS (founder, 2 November 2026: "On
// share and brag portfolio we should say share portfolio on the bottom.
// PnL should say [something else]"): on Activity and Positions, with a
// position open or a P&L off zero, "Share portfolio" opens the portfolio
// card; on P&L, with a P&L drawn, "Share P&L" opens the P&L card for the
// range picked on the hero's chart, of the venue square picked alone when
// one is (portfolioPnlVenueProvider; both venues otherwise;
// brag_preview_sheet.dart). The label
// morphs on a switch like every bar label (kute_morph_label.dart).
// Nothing to share: the default bar.
//
// Analytics: the existing `analytics_tab_selected` on a section pill
// (surface investments, tab positions, sub / from_sub: activity |
// balances | charts), as the Investments page sent it; the screen itself
// adds no event.

import 'dart:async';

import 'package:kute/screens/portfolio/components/portfolio_pnl_chart.dart'
    show pnlChartRangeProvider, portfolioPnlVenueProvider;
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
      PortfolioSection.activity ||
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
                  // The venue square picked: its card alone.
                  venue: ref.read(portfolioPnlVenueProvider))),
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
            // (Activity, Positions) or "Share P&L" (P&L) ([barContext]);
            // the Sal sheet stays a long press away.
            child: KuteBarContextScope(
              barContext: barContext(context, ref, section),
              // The bar floats over the list (nothing reserves room); each
              // section ends its own scroll with the bar's clearance
              // (kuteBarScrollClearance, investments_portfolio.dart), so
              // the last row scrolls clear of the bar.
              child: InvestmentsPortfolio(
                onSection: (section) => pickSection(ref, section),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
