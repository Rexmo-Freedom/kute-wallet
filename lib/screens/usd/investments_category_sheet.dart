// lib/screens/usd/investments_category_sheet.dart
//
// The Investments pills carry their sub-context: the picked pill reads
// "Investing · Trending", "Predictions · Politics", "Portfolio · Balances",
// and tapping it again opens this sheet with every category (and
// subcategory) of that section. One pill row on the page, nothing under
// it (founder, 31 October 2026: "put it all in one row"). The browsers'
// own category rows are not drawn inside Investments; their selection
// providers are the same, so the lists follow a pick here exactly as they
// followed a pill.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_watchlist_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_watchlist_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_browse_labels.dart';
import 'package:kute/screens/polymarket/components/poly_browse_bar.dart'
    show polyPillLabel, polySubLabel, polySubsFor;
import 'package:kute/screens/portfolio/investments_portfolio.dart'
    show PortfolioSection, portfolioSectionProvider;
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/usd/usd_account_screen.dart' show InvestmentsTab;
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// The picked pill's sub-context, for its label: the category on screen
/// (and its subcategory when one is picked), or the Portfolio section.
/// Null at the section's default (Trending, Balances): the pill then
/// reads its name alone, and the three names share the row.
String? investmentsCategoryLabel(
    WidgetRef ref, AppLocalizations l10n, InvestmentsTab tab) {
  switch (tab) {
    case InvestmentsTab.investing:
      final sel = ref.watch(hlBrowseSelectionProvider);
      final sub = sel.sub;
      if (sel.tab == HlBrowseTab.trending && sub == HlBrowseSub.all) {
        return null;
      }
      return sub == HlBrowseSub.all
          ? sel.tab.localizedLabel(l10n)
          : '${sel.tab.localizedLabel(l10n)} · ${sub.localizedLabel(l10n)}';
    case InvestmentsTab.predictions:
      final sel = ref.watch(polyBrowseSelectionProvider);
      final pill = sel.pill;
      final subKey = sel.subOf(pill);
      if (pill == PolyPill.trending && subKey == pill.defaultSub) return null;
      if (subKey == pill.defaultSub) return polyPillLabel(l10n, pill);
      final sub = polySubsFor(ref, pill).where((s) => s.key == subKey);
      return sub.isEmpty
          ? polyPillLabel(l10n, pill)
          : '${polyPillLabel(l10n, pill)} · ${polySubLabel(l10n, sub.first)}';
    case InvestmentsTab.positions:
      final section = ref.watch(portfolioSectionProvider);
      if (section == PortfolioSection.balances) return null;
      return portfolioSectionLabel(l10n, section);
  }
}

String portfolioSectionLabel(AppLocalizations l10n, PortfolioSection s) =>
    switch (s) {
      PortfolioSection.charts => l10n.portfolioSectionPnlCharts,
      PortfolioSection.balances => l10n.portfolioSectionBalances,
      PortfolioSection.activity => l10n.activity,
    };

/// The Investing categories on offer, as the browser lists them: in the
/// site's order, hiding any whose list is empty, keeping the builder-dex
/// ones while those markets are still to be read.
List<HlBrowseTab> hlCategoriesOnOffer(WidgetRef ref) {
  final universe =
      ref.read(hyperliquidBrowseUniverseProvider).valueOrNull ?? const [];
  if (universe.isEmpty) return const [];
  final watchlist = ref.read(hlWatchlistProvider);
  final awaitingBuilder = ref.read(hyperliquidBuilderMarketsMissingProvider);
  return [
    for (final t in const [
      HlBrowseTab.watchlist,
      HlBrowseTab.trending,
      HlBrowseTab.tradfi,
      HlBrowseTab.crypto,
      HlBrowseTab.perps,
      HlBrowseTab.spot,
      HlBrowseTab.prelaunch,
    ])
      if ((awaitingBuilder && hlTabNeedsBuilderMarkets(t)) ||
          hlBrowseListForTab(t, universe,
                  sub: HlBrowseSub.all, watchlist: watchlist)
              .isNotEmpty)
        t,
  ];
}

/// Opens the categories of [tab] for a pick.
Future<void> showInvestmentsCategorySheet(
    BuildContext context, WidgetRef ref, InvestmentsTab tab) {
  HapticFeedback.selectionClick();
  TrackingService.track('category_sheet_opened',
      params: {'surface': 'investments', 'section': tab.key});
  return showAppBottomSheet<void>(
    context: context,
    builder: (_) => _InvestmentsCategorySheet(tab: tab),
  );
}

class _InvestmentsCategorySheet extends ConsumerWidget {
  const _InvestmentsCategorySheet({required this.tab});

  final InvestmentsTab tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final title = switch (tab) {
      InvestmentsTab.investing => l10n.trading,
      InvestmentsTab.predictions => l10n.predictions,
      InvestmentsTab.positions => l10n.walletPortfolioAction,
    };
    return AppBottomSheetContainer(
      maxHeight: 0.85,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppBottomSheetHeader(title: title),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.only(bottom: 8.h),
              children: switch (tab) {
                InvestmentsTab.investing => _investing(context, ref),
                InvestmentsTab.predictions => _predictions(context, ref),
                InvestmentsTab.positions => _portfolio(context, ref),
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _group(BuildContext context, String label) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 6.h),
      child: Text(
        label,
        style: TextStyle(
          color: c.textTertiary,
          fontSize: 13.sp,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
        ),
      ),
    );
  }

  List<Widget> _investing(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final sel = ref.watch(hlBrowseSelectionProvider);
    final universe =
        ref.watch(hyperliquidBrowseUniverseProvider).valueOrNull ??
            const <HlMarket>[];
    final awaitingBuilder =
        ref.watch(hyperliquidBuilderMarketsMissingProvider);
    void pick(HlBrowseTab t, HlBrowseSub s) {
      HapticFeedback.selectionClick();
      Navigator.of(context).pop();
      final current = ref.read(hlBrowseSelectionProvider);
      if (t == current.tab && s == current.sub) return;
      TrackingService.track('hl_category_pill_tapped', params: {
        'section': t.key,
        if (s != HlBrowseSub.all) 'subcategory': s.key,
      });
      ref.read(hlBrowseSelectionProvider.notifier).state =
          current.copyWith(tab: t, sub: s);
    }

    return [
      for (final t in hlCategoriesOnOffer(ref)) ...[
        _group(context, t.localizedLabel(l10n)),
        // A category with subcategories lists them (All first); one
        // without is one row: all of it.
        ...() {
          final subs = awaitingBuilder && hlTabNeedsBuilderMarkets(t)
              ? const <HlBrowseSub>[]
              : hlSubsForTab(t, universe);
          final rows = subs.length > 1 ? subs : const [HlBrowseSub.all];
          return [
            for (final s in rows)
              AppBottomSheetListTile(
                title: s == HlBrowseSub.all && subs.length <= 1
                    ? t.localizedLabel(l10n)
                    : s.localizedLabel(l10n),
                isSelected: sel.tab == t && sel.sub == s,
                onTap: () => pick(t, s),
              ),
          ];
        }(),
      ],
    ];
  }

  List<Widget> _predictions(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final sel = ref.watch(polyBrowseSelectionProvider);
    final policy = ref.watch(runtimeCapabilitiesProvider);
    final hasWatchlist = ref.watch(polyWatchlistProvider).isNotEmpty;
    final pills = [
      for (final p in PolyPill.values)
        if (polyPillOffered(p, policy) &&
            (p != PolyPill.watchlist || hasWatchlist))
          p,
    ];
    void pick(PolyPill p, PolySub s) {
      HapticFeedback.selectionClick();
      Navigator.of(context).pop();
      final current = ref.read(polyBrowseSelectionProvider);
      if (p == current.pill && s.key == current.subOf(p)) return;
      TrackingService.track('category_pill_tapped', params: {
        'section': p.key,
        if (s.key != p.defaultSub) 'subcategory': s.route,
      });
      ref.read(polyBrowseSelectionProvider.notifier).state =
          current.copyWith(pill: p).copyWith(sub: s.key);
    }

    return [
      for (final p in pills) ...[
        _group(context, polyPillLabel(l10n, p)),
        ...() {
          final subs = polySubsFor(ref, p);
          final rows = subs.isEmpty ? [PolySub(p.defaultSub)] : subs;
          return [
            for (final s in rows)
              AppBottomSheetListTile(
                title: subs.isEmpty ? polyPillLabel(l10n, p) : polySubLabel(l10n, s),
                isSelected: sel.pill == p && sel.subOf(p) == s.key,
                onTap: () => pick(p, s),
              ),
          ];
        }(),
      ],
    ];
  }

  List<Widget> _portfolio(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final current = ref.watch(portfolioSectionProvider);
    return [
      for (final s in PortfolioSection.values)
        AppBottomSheetListTile(
          title: portfolioSectionLabel(l10n, s),
          isSelected: s == current,
          onTap: () {
            HapticFeedback.selectionClick();
            Navigator.of(context).pop();
            if (s == current) return;
            TrackingService.track('analytics_tab_selected', params: {
              'tab': InvestmentsTab.positions.key,
              'from_tab': InvestmentsTab.positions.key,
              'surface': 'investments',
              'sub': s.key,
              'from_sub': current.key,
            });
            ref.read(portfolioSectionProvider.notifier).state = s;
          },
        ),
    ];
  }
}
