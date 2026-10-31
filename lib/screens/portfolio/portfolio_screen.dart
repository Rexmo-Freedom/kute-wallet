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
// balance, show the shares with the pie chart on the left"): the section
// pills (Portfolio · P&L Charts · Activity), and the Portfolio section
// opens on the shares block (the allocation ring at the left, the
// Investing / Predictions / Dollars shares as rows at the right, no total:
// the Dollars tab has it) over the venues' open positions
// (BalancesOverview.sharesHeader). No dock: Add and Send are not
// repeated here.
//
// A deep link naming a Portfolio section (`/usd?tab=portfolio|positions|
// orders|activity…`, PortfolioSection.forLink) opens this screen on that
// section (usd_account_screen.dart, openInvestmentsPortfolio), as do a
// filled order's "View positions", a resting order's "View orders" and a
// trade notification.
//
// Analytics: the existing `analytics_tab_selected` on a section pill
// (surface investments, tab positions, sub / from_sub), as the Investments
// page sent it; the screen itself adds no event (experimental branch).

import 'dart:async';

import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/kute_share_actions.dart'
    show KuteMarketBarAction;
import 'package:kute/screens/shared/money_movement_sheet.dart'
    show showMoneyMovementSheet;
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
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
            // The bar over this page: the default search and Sal.
            child: KuteBarContextScope(
              barContext: KuteBarContext(
                label: context.l10n.searchOrAskSalShort,
                source: 'portfolio',
                // The Sal sheet's top row: Move money (founder, 31
                // October 2026).
                actions: [
                  KuteMarketBarAction(
                    label: context.l10n.moveTransfer,
                    sublabel: context.l10n.portfolioMoveMoneySub,
                    icon: Icons.swap_horiz_rounded,
                    onTap: (_) {
                      TrackingService.track('portfolio_move_money_tapped',
                          params: const {'surface': 'sal_sheet'});
                      unawaited(showMoneyMovementSheet(context));
                    },
                  ),
                ],
              ),
              // The bar floats over the list (nothing reserves room); the
              // lists pad their own end by the bar's clearance, read from
              // the MediaQuery padding they already use.
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  padding: MediaQuery.paddingOf(context).copyWith(
                      bottom: MediaQuery.paddingOf(context).bottom +
                          kuteBarScrollClearance.h),
                ),
                child: InvestmentsPortfolio(
                  sharesHeader: true,
                  onSection: (section) => pickSection(ref, section),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
