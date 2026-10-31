// lib/screens/usd/investments_category_sheet.dart
//
// The Investments pills carry their sub-context: the picked pill reads
// "Investing · Trending", "Predictions · Politics · Live", and tapping it
// again opens this sheet with every category (and subcategory) of that
// section. One pill row on the page, nothing under it (founder, 31
// October 2026: "put it all in one row"). The browsers' own category rows
// are not drawn inside Investments; their selection providers are the
// same, so the lists follow a pick here exactly as they followed a pill.
//
// A TILE GRID WITH LIVE NUMBERS (founder, 31 October 2026, after a
// settings-list draft: "not fintech"). Under the sheet's handle, title
// and circled close:
//
//   * two WIDE tiles, Trending and Watchlist, then a small "Markets"
//     (Investing) or "Topics" (Predictions) label and a real two-column
//     grid (every tile the same 96 px, 8 px apart, the odd last one half
//     width at the left). A tile is THE VENUE'S OWN ARTWORK, never a
//     generic icon (founder, 31 October 2026): a stack of up to three
//     overlapping logos of the category's top markets (Hyperliquid's coin
//     and asset logos, Polymarket's event images from the loaded feed), a
//     neutral circle in the group's tint when none is loaded; under it
//     the name (w500) and the numbers line ("64 markets · ▲ 0.5%", "Most
//     active · ▲ 1.8% today", "N markets · $12M vol today").
//
// The picked tile wears a thin outline in its group's tint (the only
// place the tint shows besides the placeholder) and a check at its
// top-right corner. No chevrons anywhere. Every tile has the app's press
// spring (KutePressable).
//
// THE NUMBERS COME FROM WHAT IS ALREADY LOADED, never a new read: the
// Investing universe (hyperliquidBrowseUniverseProvider) and the browse
// list helpers give each group its markets; the count is how many, the
// move is the MEDIAN of their 24h changes (a median, so one outlier does
// not swing it), omitted when the group has no 24h data (Pre-launch);
// 0.0% reads in the quiet colour with no arrow. Predictions has numbers
// only where a feed is loaded: the picked category's feed (its event
// count and the sum of its events' 24h volume, "N markets · $12M vol
// today") and the watchlist's count; the other tiles carry their name.
//
// A group with subcategories (Traditional → Stocks, Indices, Commodities,
// FX, Pre-IPO; Crypto → its sectors; a Predictions topic → its topics)
// slides to its own grid inside the same sheet (an AnimatedSwitcher on
// the chip spring; at once under Reduce Motion): "‹ Investing" at the
// left of the header, the group's name as the title, a wide "All
// Traditional" tile on top, then the subcategories as tiles with the
// same numbers. Tapping any tile picks (category and subcategory) and
// closes; a tile without subcategories picks and closes at once. The
// pick writes the same providers and sends the same events the pills did.
//
// The Portfolio section (three tiles, no numbers) is here for the
// Portfolio's own screen (portfolio_screen.dart); the page's pill row no
// longer offers Portfolio.

import 'package:kute/providers/unified_search_provider.dart' show SearchCategory;
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/polymarket_model.dart' show PolymarketEvent;
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_watchlist_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_watchlist_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_browse_labels.dart';
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
import 'package:kute/screens/polymarket/components/poly_browse_bar.dart'
    show polyPillLabel, polySubLabel, polySubsFor;
import 'package:kute/screens/polymarket/components/poly_crest_image.dart';
import 'package:kute/screens/portfolio/investments_portfolio.dart'
    show PortfolioSection, portfolioSectionProvider;
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/kute_back_button.dart' show KuteCloseButton;
import 'package:kute/screens/shared/kute_motion.dart'
    show KutePressable, kuteReduceMotion;
import 'package:kute/screens/usd/usd_account_screen.dart' show InvestmentsTab;
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/theme/kute_motion.dart';

/// The picked pill's sub-context, for its label: the category on screen
/// (and its subcategory when one is picked), or the Portfolio section.
/// Always a name, the default's included ("Trending", "Balances"), so the
/// picked pill always shows what it holds (founder, 31 October 2026: "it
/// should be more clear that we have much more context here").
String investmentsCategoryLabel(
    WidgetRef ref, AppLocalizations l10n, InvestmentsTab tab) {
  switch (tab) {
    case InvestmentsTab.investing:
      final sel = ref.watch(hlBrowseSelectionProvider);
      final sub = sel.sub;
      return sub == HlBrowseSub.all
          ? sel.tab.localizedLabel(l10n)
          : '${sel.tab.localizedLabel(l10n)} · ${sub.localizedLabel(l10n)}';
    case InvestmentsTab.predictions:
      final sel = ref.watch(polyBrowseSelectionProvider);
      final pill = sel.pill;
      final subKey = sel.subOf(pill);
      if (subKey == pill.defaultSub) return polyPillLabel(l10n, pill);
      final sub = polySubsFor(ref, pill).where((s) => s.key == subKey);
      return sub.isEmpty
          ? polyPillLabel(l10n, pill)
          : '${polyPillLabel(l10n, pill)} · ${polySubLabel(l10n, sub.first)}';
    case InvestmentsTab.positions:
      return portfolioSectionLabel(l10n, ref.watch(portfolioSectionProvider));
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

// ── Numbers ────────────────────────────────────────────────────────────

/// A group's numbers: how many markets, and the median of their 24h
/// changes (null without any 24h data).
typedef _Stat = ({int count, double? move});

/// The median of [values], null when there are none.
double? _median(List<double> values) {
  if (values.isEmpty) return null;
  final sorted = [...values]..sort();
  final n = sorted.length;
  return n.isOdd ? sorted[n ~/ 2] : (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
}

/// The Investing markets' numbers: a market's change is its mark against
/// yesterday's price; one without a yesterday (pre-launch) is left out of
/// the median.
_Stat _hlStat(List<HlMarket> markets) => (
      count: markets.length,
      move: _median([
        for (final m in markets)
          if (m.prevDayPx > 0 && m.markPx > 0) m.markPx / m.prevDayPx - 1,
      ]),
    );

/// "$12M", "$850K", "$1.2M": a volume in a few characters.
String _compactUsd(double usd) {
  if (usd >= 1e9) return '\$${(usd / 1e9).toStringAsFixed(1)}B';
  if (usd >= 1e7) return '\$${(usd / 1e6).round()}M';
  if (usd >= 1e6) return '\$${(usd / 1e6).toStringAsFixed(1)}M';
  if (usd >= 1e4) return '\$${(usd / 1e3).round()}K';
  if (usd >= 1e3) return '\$${(usd / 1e3).toStringAsFixed(1)}K';
  return '\$${usd.round()}';
}

// ── Icons and tints ────────────────────────────────────────────────────

/// Bitcoin's orange, the Crypto tiles' tint (the light theme's accent is
/// blue, so it is not a theme token).
const Color _kBitcoinOrange = Color(0xFFF7931A);

Color _hlTint(AppColorsExtension c, HlBrowseTab t) => switch (t) {
      HlBrowseTab.watchlist => c.chartCategorical[2],
      HlBrowseTab.trending => c.chartCategorical[0],
      HlBrowseTab.tradfi => c.chartCategorical[1],
      HlBrowseTab.crypto => _kBitcoinOrange,
      HlBrowseTab.perps => c.chartCategorical[0],
      HlBrowseTab.spot => c.chartCategorical[3],
      HlBrowseTab.prelaunch => c.chartCategorical[2],
    };

Color _polyTint(AppColorsExtension c, PolyPill p) => switch (p) {
      PolyPill.watchlist => c.chartCategorical[2],
      PolyPill.trending => c.chartCategorical[0],
      PolyPill.breaking => c.chartCategorical[3],
      PolyPill.newest => c.chartCategorical[4],
      PolyPill.live => c.chartCategorical[2],
      PolyPill.politics => c.chartCategorical[0],
      PolyPill.sports => c.chartCategorical[1],
      PolyPill.crypto => _kBitcoinOrange,
      PolyPill.esports => c.chartCategorical[4],
      PolyPill.finance => c.chartCategorical[1],
      PolyPill.geopolitics => c.chartCategorical[0],
      PolyPill.tech => c.chartCategorical[4],
      PolyPill.culture => c.chartCategorical[3],
      PolyPill.economy => c.chartCategorical[1],
      PolyPill.weather => c.chartCategorical[0],
      PolyPill.mentions => c.chartCategorical[3],
      PolyPill.elections => c.chartCategorical[0],
    };

IconData _portfolioIcon(PortfolioSection s) => switch (s) {
      PortfolioSection.balances => Icons.pie_chart_rounded,
      PortfolioSection.charts => Icons.show_chart_rounded,
      PortfolioSection.activity => Icons.receipt_long_rounded,
    };

// ── The sheet ──────────────────────────────────────────────────────────

class _InvestmentsCategorySheet extends ConsumerStatefulWidget {
  const _InvestmentsCategorySheet({required this.tab});

  final InvestmentsTab tab;

  @override
  ConsumerState<_InvestmentsCategorySheet> createState() =>
      _InvestmentsCategorySheetState();
}

class _InvestmentsCategorySheetState
    extends ConsumerState<_InvestmentsCategorySheet> {
  /// The group whose subcategories are on screen (an [HlBrowseTab] or a
  /// [PolyPill]); null for the section's own grid.
  Object? _group;

  /// Which way the last page change went, for the slide.
  bool _forward = true;

  void _open(Object group) {
    HapticFeedback.selectionClick();
    setState(() {
      _group = group;
      _forward = true;
    });
  }

  void _back() {
    HapticFeedback.selectionClick();
    setState(() {
      _group = null;
      _forward = false;
    });
  }

  String _sectionTitle(AppLocalizations l10n) => switch (widget.tab) {
        InvestmentsTab.investing => l10n.trading,
        InvestmentsTab.predictions => l10n.predictions,
        InvestmentsTab.positions => l10n.walletPortfolioAction,
      };

  String _groupTitle(AppLocalizations l10n, Object group) => switch (group) {
        HlBrowseTab t => t.localizedLabel(l10n),
        PolyPill p => polyPillLabel(l10n, p),
        _ => '',
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final reduce = kuteReduceMotion(context);
    final group = _group;
    final page = KeyedSubtree(
      key: ValueKey<Object?>(group),
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 12.h),
        children: switch (widget.tab) {
          InvestmentsTab.investing => group == null
              ? _investing(context)
              : _investingSubs(context, group as HlBrowseTab),
          InvestmentsTab.predictions => group == null
              ? _predictions(context)
              : _predictionsSubs(context, group as PolyPill),
          InvestmentsTab.positions => _portfolio(context),
        },
      ),
    );
    return KuteBarContextScope(
      barContext: _barContext(context),
      child: AppBottomSheetContainer(
      maxHeight: 0.9,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (group == null)
            AppBottomSheetHeader(
                title: _sectionTitle(l10n), trailing: const KuteCloseButton())
          else
            _SubHeader(
              back: _sectionTitle(l10n),
              title: _groupTitle(l10n, group),
              onBack: _back,
            ),
          Flexible(
            // A group's grid slides in from the right over the section's,
            // and back out to it, on the chip spring.
            child: AnimatedSwitcher(
              duration: reduce ? Duration.zero : KuteMotion.chipDuration,
              switchInCurve: reduce ? Curves.linear : KuteMotion.chip,
              switchOutCurve: reduce ? Curves.linear : KuteMotion.settle,
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.topCenter,
                children: [...previous, if (current != null) current],
              ),
              transitionBuilder: (child, animation) {
                final incoming = child.key == page.key;
                final dir = _forward ? 1.0 : -1.0;
                final slide = Tween<Offset>(
                  begin: Offset(incoming ? dir : -dir, 0),
                  end: Offset.zero,
                ).animate(animation);
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(position: slide, child: child),
                );
              },
              child: page,
            ),
          ),
        ],
      ),
      ),
    );
  }

  /// The bar while this sheet is up (kute_bar_context.dart): "Pick a
  /// market group" over "or ask Sal to find one", and its Sal sheet's
  /// recommended rows: the three categories moving most today (Investing)
  /// or the first three on offer (Predictions), a row picking and closing.
  KuteBarContext _barContext(BuildContext context) {
    final l10n = context.l10n;
    final actions = <KuteBarAction>[];
    switch (widget.tab) {
      case InvestmentsTab.investing:
        final ranked = [
          for (final t in hlCategoriesOnOffer(ref))
            if (t != HlBrowseTab.watchlist) (t, _hlStat(_hlList(t)))
        ]..sort((a, b) =>
            (b.$2.move?.abs() ?? -1).compareTo(a.$2.move?.abs() ?? -1));
        for (final (t, stat) in ranked.take(3)) {
          actions.add(KuteBarAction(
            label: t.localizedLabel(l10n),
            sublabel: l10n.categoryStatMarkets(stat.count),
            onTap: (_) => _pickHl(t, HlBrowseSub.all),
          ));
        }
      case InvestmentsTab.predictions:
        final policy = ref.read(runtimeCapabilitiesProvider);
        for (final p in PolyPill.values
            .where((p) => p != PolyPill.watchlist && polyPillOffered(p, policy))
            .take(3)) {
          actions.add(KuteBarAction(
            label: polyPillLabel(l10n, p),
            onTap: (_) => _pickPoly(p, PolySub(p.defaultSub)),
          ));
        }
      case InvestmentsTab.positions:
        break;
    }
    return KuteBarContext(
      label: l10n.barPickMarketGroup,
      sublabel: l10n.barPickMarketGroupSub,
      actions: actions,
      category: widget.tab == InvestmentsTab.predictions
          ? SearchCategory.predictions
          : SearchCategory.perpetuals,
      searchHint: widget.tab == InvestmentsTab.predictions
          ? l10n.searchPredictionsHint
          : l10n.searchInvestmentsHint,
      source: 'category_sheet',
    );
  }

  /// A small label over a grid.
  Widget _label(BuildContext context, String text) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(4.w, 14.h, 4.w, 8.h),
      child: Text(
        text,
        style: TextStyle(
          color: c.textTertiary,
          fontSize: 13.sp,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
        ),
      ),
    );
  }

  /// A real two-column grid: every tile [_Tile.gridHeight] tall, 8 apart,
  /// the odd last one half width at the left. It sits in the sheet's
  /// ListView, so it is shrink-wrapped and never scrolls on its own.
  Widget _grid(List<Widget> tiles) => GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          mainAxisExtent: _Tile.gridHeight,
        ),
        itemCount: tiles.length,
        itemBuilder: (_, i) => tiles[i],
      );

  // ── Investing ────────────────────────────────────────────────────────

  void _pickHl(HlBrowseTab t, HlBrowseSub s) {
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

  List<HlMarket> _hlList(HlBrowseTab t, [HlBrowseSub s = HlBrowseSub.all]) {
    final universe =
        ref.watch(hyperliquidBrowseUniverseProvider).valueOrNull ??
            const <HlMarket>[];
    final watchlist = ref.watch(hlWatchlistProvider);
    return hlBrowseListForTab(t, universe, sub: s, watchlist: watchlist);
  }

  /// The venue's own logos of a category's top markets, for its tile.
  List<Widget> _hlLogos(List<HlMarket> markets) => [
        for (final m in markets.take(_kLogos))
          HlCoinIcon(
              coin: m.coin,
              wireCoin: m.wireCoin,
              iconUrl: m.iconUrl,
              category: m.category,
              size: _kLogo),
      ];

  List<HlBrowseSub> _hlSubs(HlBrowseTab t) {
    final universe =
        ref.watch(hyperliquidBrowseUniverseProvider).valueOrNull ??
            const <HlMarket>[];
    final awaitingBuilder =
        ref.watch(hyperliquidBuilderMarketsMissingProvider);
    final subs = awaitingBuilder && hlTabNeedsBuilderMarkets(t)
        ? const <HlBrowseSub>[]
        : hlSubsForTab(t, universe);
    return subs.length > 1 ? subs : const [];
  }

  List<Widget> _investing(BuildContext context) {
    final l10n = context.l10n;
    final c = context.colors;
    final sel = ref.watch(hlBrowseSelectionProvider);
    final onOffer = hlCategoriesOnOffer(ref);

    Widget wide(HlBrowseTab t, {String? lead}) {
      final list = _hlList(t);
      final stat = _hlStat(list);
      return _Tile.wide(
        tint: _hlTint(c, t),
        name: t == HlBrowseTab.watchlist
            ? l10n.polyPillWatchlist
            : t.localizedLabel(l10n),
        stat: _StatLine(
            lead: lead,
            count: lead == null ? stat.count : null,
            move: stat.move,
            tail: lead == null ? null : l10n.categoryStatToday),
        logos: _hlLogos(list),
        picked: sel.tab == t,
        onTap: () => _pickHl(t, HlBrowseSub.all),
      );
    }

    Widget tile(HlBrowseTab t) {
      final list = _hlList(t);
      final stat = _hlStat(list);
      final subs = _hlSubs(t);
      return _Tile(
        logos: _hlLogos(list),
        tint: _hlTint(c, t),
        name: t.localizedLabel(l10n),
        stat: _StatLine(count: stat.count, move: stat.move),
        picked: sel.tab == t,
        onTap: subs.isEmpty
            ? () => _pickHl(t, HlBrowseSub.all)
            : () => _open(t),
      );
    }

    return [
      if (onOffer.contains(HlBrowseTab.trending))
        wide(HlBrowseTab.trending, lead: l10n.categoryStatMostActive),
      if (onOffer.contains(HlBrowseTab.watchlist)) wide(HlBrowseTab.watchlist),
      _label(context, l10n.categoryGroupMarkets),
      _grid([
        for (final t in onOffer)
          if (t != HlBrowseTab.trending && t != HlBrowseTab.watchlist) tile(t),
      ]),
    ];
  }

  List<Widget> _investingSubs(BuildContext context, HlBrowseTab t) {
    final l10n = context.l10n;
    final c = context.colors;
    final sel = ref.watch(hlBrowseSelectionProvider);
    final tint = _hlTint(c, t);
    final all = _hlList(t);
    final allStat = _hlStat(all);
    return [
      _Tile.wide(
        tint: tint,
        name: l10n.categoryAllOf(t.localizedLabel(l10n)),
        stat: _StatLine(count: allStat.count, move: allStat.move),
        logos: _hlLogos(all),
        picked: sel.tab == t && sel.sub == HlBrowseSub.all,
        onTap: () => _pickHl(t, HlBrowseSub.all),
      ),
      _grid([
        for (final s in _hlSubs(t))
          () {
            final list = _hlList(t, s);
            final stat = _hlStat(list);
            return _Tile(
              logos: _hlLogos(list),
              tint: tint,
              name: s.localizedLabel(l10n),
              stat: _StatLine(count: stat.count, move: stat.move),
              picked: sel.tab == t && sel.sub == s,
              onTap: () => _pickHl(t, s),
            );
          }(),
      ]),
    ];
  }

  // ── Predictions ──────────────────────────────────────────────────────

  void _pickPoly(PolyPill p, PolySub s) {
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

  /// The events the picked category's feed holds (already loaded for
  /// the list behind the sheet); nothing is read for any other.
  List<PolymarketEvent> _polyLoaded(PolyPill p, [String? sub]) {
    final sel = ref.watch(polyBrowseSelectionProvider);
    if (p != sel.pill) return const [];
    if (sub != null && sub != sel.subOf(p)) return const [];
    final query = p == PolyPill.live
        ? const PolyFeedQuery(pill: PolyPill.live)
        : sel.query;
    return ref.watch(polyBrowseFeedProvider(query)).events;
  }

  List<Widget> _polyLogos(List<PolymarketEvent> events) => [
        for (final e in events)
          if (e.imageUrl != null && e.imageUrl!.isNotEmpty)
            PolyCrestImage(url: e.imageUrl!, size: _kLogo, radius: _kLogo / 2),
      ].take(_kLogos).toList();

  List<PolySub> _polySubs(PolyPill p) {
    var subs = polySubsFor(ref, p);
    if (subs.isNotEmpty && !subs.any((s) => s.key == p.defaultSub)) {
      subs = [PolySub(p.defaultSub), ...subs];
    }
    return subs.length > 1 ? subs : const [];
  }

  List<Widget> _predictions(BuildContext context) {
    final l10n = context.l10n;
    final c = context.colors;
    final sel = ref.watch(polyBrowseSelectionProvider);
    final policy = ref.watch(runtimeCapabilitiesProvider);
    final watchlist = ref.watch(polyWatchlistProvider);
    final pills = [
      for (final p in PolyPill.values)
        if (polyPillOffered(p, policy) &&
            (p != PolyPill.watchlist || watchlist.isNotEmpty))
          p,
    ];

    _StatLine? statOf(PolyPill p, {String? lead}) {
      if (p == PolyPill.watchlist) {
        return _StatLine(count: watchlist.length);
      }
      final events = _polyLoaded(p);
      if (events.isEmpty) return null;
      final volume = events.fold<double>(0, (sum, e) => sum + e.volume24hr);
      return _StatLine(
        lead: lead,
        count: lead == null ? events.length : null,
        volume: volume > 0 ? volume : null,
      );
    }

    Widget wide(PolyPill p, {String? lead}) => _Tile.wide(
          tint: _polyTint(c, p),
          name: p == PolyPill.watchlist
              ? l10n.polyPillWatchlist
              : polyPillLabel(l10n, p),
          stat: statOf(p, lead: lead),
          logos: _polyLogos(_polyLoaded(p)),
          picked: sel.pill == p,
          onTap: () => _pickPoly(p, PolySub(p.defaultSub)),
        );

    Widget tile(PolyPill p) => _Tile(
          logos: _polyLogos(_polyLoaded(p)),
          tint: _polyTint(c, p),
          name: polyPillLabel(l10n, p),
          stat: statOf(p),
          picked: sel.pill == p,
          onTap: _polySubs(p).isEmpty
              ? () => _pickPoly(p, PolySub(p.defaultSub))
              : () => _open(p),
        );

    return [
      if (pills.contains(PolyPill.trending))
        wide(PolyPill.trending, lead: l10n.categoryStatMostActive),
      if (pills.contains(PolyPill.watchlist)) wide(PolyPill.watchlist),
      _label(context, l10n.categoryGroupTopics),
      _grid([
        for (final p in pills)
          if (p != PolyPill.trending && p != PolyPill.watchlist) tile(p),
      ]),
    ];
  }

  List<Widget> _predictionsSubs(BuildContext context, PolyPill p) {
    final l10n = context.l10n;
    final c = context.colors;
    final sel = ref.watch(polyBrowseSelectionProvider);
    final tint = _polyTint(c, p);
    final subs = _polySubs(p);
    final all = subs.firstWhere((s) => s.key == p.defaultSub,
        orElse: () => PolySub(p.defaultSub));

    _StatLine? statOf(String sub) {
      final events = _polyLoaded(p, sub);
      if (events.isEmpty) return null;
      final volume = events.fold<double>(0, (sum, e) => sum + e.volume24hr);
      return _StatLine(
          count: events.length, volume: volume > 0 ? volume : null);
    }

    return [
      _Tile.wide(
        tint: tint,
        name: l10n.categoryAllOf(polyPillLabel(l10n, p)),
        stat: statOf(all.key),
        logos: _polyLogos(_polyLoaded(p, all.key)),
        picked: sel.pill == p && sel.subOf(p) == all.key,
        onTap: () => _pickPoly(p, all),
      ),
      _grid([
        for (final s in subs)
          if (s.key != p.defaultSub)
            _Tile(
              logos: _polyLogos(_polyLoaded(p, s.key)),
              tint: tint,
              name: polySubLabel(l10n, s),
              stat: statOf(s.key),
              picked: sel.pill == p && sel.subOf(p) == s.key,
              onTap: () => _pickPoly(p, s),
            ),
      ]),
    ];
  }

  // ── Portfolio ────────────────────────────────────────────────────────

  List<Widget> _portfolio(BuildContext context) {
    final l10n = context.l10n;
    final c = context.colors;
    final current = ref.watch(portfolioSectionProvider);
    final tint = c.chartCategorical[4];
    return [
      SizedBox(height: 4.h),
      _grid([
        for (final s in PortfolioSection.values)
          _Tile(
            glyph: _portfolioIcon(s),
            tint: tint,
            name: portfolioSectionLabel(l10n, s),
            picked: s == current,
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
      ]),
    ];
  }
}

/// A group's header: the handle, "‹ Investing" at the left, the group's
/// name, the circled close at the right.
class _SubHeader extends StatelessWidget {
  const _SubHeader(
      {required this.back, required this.title, required this.onBack});

  final String back;
  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.only(top: 12.h),
          child: AppDecorations.dragHandle(context),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(12.w, 12.h, 20.w, 12.h),
          child: Row(
            children: [
              Semantics(
                button: true,
                label: back,
                excludeSemantics: true,
                child: KutePressable(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onBack,
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: 8.w, vertical: 8.h),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.chevron_left_rounded,
                              size: 22.sp, color: c.textSecondary),
                          Text(
                            back,
                            style: TextStyle(
                              color: c.textSecondary,
                              fontSize: 15.sp,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 20.sp,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
              const KuteCloseButton(),
            ],
          ),
        ),
      ],
    );
  }
}

/// A logo in a tile's stack, and how many a stack holds.
const double _kLogo = 22;
const int _kLogos = 3;

/// A tile's second line: "[lead ·] N markets · ▲ 1.8% [· $12M vol today]
/// [today]". The move's arrow and colour follow its sign; 0.0% is quiet
/// with no arrow; a null [move] is left out.
class _StatLine extends StatelessWidget {
  const _StatLine({this.lead, this.count, this.move, this.volume, this.tail});

  final String? lead;
  final int? count;
  final double? move;
  final double? volume;
  final String? tail;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final quiet = TextStyle(
      color: c.textSecondary,
      fontSize: 12.5.sp,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.1,
      height: 1.2,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final parts = <InlineSpan>[];
    void sep() {
      if (parts.isNotEmpty) parts.add(TextSpan(text: ' · ', style: quiet));
    }

    if (lead != null) parts.add(TextSpan(text: lead, style: quiet));
    if (count != null) {
      sep();
      parts.add(TextSpan(text: l10n.categoryStatMarkets(count!), style: quiet));
    }
    if (move != null) {
      sep();
      final pct = (move!.abs() * 100).toStringAsFixed(1);
      final flat = double.parse(pct) == 0;
      final up = move! > 0;
      parts.add(TextSpan(
        text: flat ? '$pct%' : '${up ? '▲' : '▼'} $pct%',
        style: quiet.copyWith(
          color: flat
              ? c.textSecondary
              : (up ? AppColors.marketUp : AppColors.marketDown),
          fontWeight: FontWeight.w600,
        ),
      ));
    }
    if (volume != null) {
      sep();
      parts.add(TextSpan(
          text: l10n.categoryStatVolToday(_compactUsd(volume!)), style: quiet));
    }
    if (tail != null) parts.add(TextSpan(text: ' $tail', style: quiet));
    if (parts.isEmpty) return const SizedBox.shrink();
    return Text.rich(TextSpan(children: parts),
        maxLines: 1, overflow: TextOverflow.ellipsis);
  }
}

/// A tile: the venue's logos (or the tint's placeholder circle, or a
/// [glyph] for the Portfolio) top-left, the name, the numbers under it.
/// The picked one wears the tint's outline and the check. Pressed, it
/// gives the app's press spring. [wide] is the full-width row tile.
class _Tile extends StatelessWidget {
  const _Tile({
    required this.tint,
    required this.name,
    required this.onTap,
    this.logos = const [],
    this.glyph,
    this.stat,
    this.picked = false,
  }) : wide = false;

  const _Tile.wide({
    required this.tint,
    required this.name,
    required this.onTap,
    this.logos = const [],
    this.stat,
    this.picked = false,
  })  : wide = true,
        glyph = null;

  final Color tint;
  final String name;
  final Widget? stat;
  final List<Widget> logos;
  final IconData? glyph;
  final bool picked;
  final bool wide;
  final VoidCallback onTap;

  /// Every grid tile's height; the wide tiles are shorter.
  static const double gridHeight = 96;
  static const double wideHeight = 64;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isLight = !context.isDark;
    final reduce = kuteReduceMotion(context);
    final Widget art = logos.isNotEmpty
        ? _LogoStack(logos: logos)
        : Container(
            width: _kLogo,
            height: _kLogo,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: glyph == null ? 0.22 : 0.14),
              shape: BoxShape.circle,
            ),
            child: glyph == null ? null : Icon(glyph, size: 14, color: tint),
          );
    final nameText = Text(
      name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: c.textPrimary,
        fontSize: 15.sp,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.2,
      ),
    );
    final body = wide
        ? Row(
            children: [
              art,
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    nameText,
                    if (stat != null) ...[SizedBox(height: 2.h), stat!],
                  ],
                ),
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              art,
              const Spacer(),
              nameText,
              if (stat != null) ...[SizedBox(height: 2.h), stat!],
            ],
          );
    return Semantics(
      button: true,
      selected: picked,
      label: name,
      child: KutePressable(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: reduce ? Duration.zero : KuteMotion.chipDuration,
                curve: reduce ? Curves.linear : KuteMotion.chip,
                width: double.infinity,
                height: wide ? wideHeight : gridHeight,
                margin: EdgeInsets.only(bottom: wide ? 8.h : 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isLight ? Colors.white : c.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: picked ? tint : (isLight ? c.border : c.borderSubtle),
                    width: picked ? 1.5 : (isLight ? 1.0 : 0.5),
                  ),
                  boxShadow: isLight
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: body,
              ),
              // The check at the picked tile's top-right corner.
              if (picked)
                Positioned(
                  top: -6,
                  right: -6,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: tint,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.background, width: 2),
                    ),
                    child: const Icon(Icons.check_rounded,
                        size: 12, color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Up to three logos overlapping by a third, each ringed in the tile's
/// surface so they read apart.
class _LogoStack extends StatelessWidget {
  const _LogoStack({required this.logos});

  final List<Widget> logos;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const step = _kLogo * 0.66;
    final n = logos.length.clamp(0, _kLogos);
    return SizedBox(
      width: _kLogo + step * (n - 1),
      height: _kLogo + 4,
      child: Stack(
        children: [
          for (var i = 0; i < n; i++)
            Positioned(
              left: i * step,
              top: 2,
              child: Container(
                width: _kLogo + 3,
                height: _kLogo + 3,
                padding: const EdgeInsets.all(1.5),
                decoration: BoxDecoration(
                  color: context.isDark ? c.surface : Colors.white,
                  shape: BoxShape.circle,
                ),
                child: ClipOval(child: logos[i]),
              ),
            ),
        ],
      ),
    );
  }
}
