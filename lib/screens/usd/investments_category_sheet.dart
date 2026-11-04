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
//     grid (every Investing tile the same 96 px, 8 px apart, the odd last
//     one half width at the left). A tile is THE VENUE'S OWN ARTWORK, never a
//     generic icon (founder, 31 October 2026): a stack of up to three
//     overlapping logos of the category's top markets (Hyperliquid's coin
//     and asset logos, Polymarket's event images from the loaded feed), a
//     neutral circle in the group's tint when none is loaded; under it
//     the name (w500) and the numbers line ("64 markets · ▲ 0.5%", "Most
//     active · ▲ 1.8% today", "N markets · $12M vol today").
//
// The picked tile wears the app's own picked language, the strip's
// picked pill: white with the hairline border and the pill shadow; every
// other tile is flat surface-1 with no border (founder, 31 October 2026:
// choice "A" in the app's own style, no accent fill, no check, no
// tint). Its name is a step bolder (w600). Fill, border and shadow move
// on the chip spring; at once under Reduce Motion. The group's tint shows
// only on the placeholder. No chevrons anywhere. Every tile has the app's
// press spring (KutePressable).
//
// THE STACKS DIFFER (founder, 31 October 2026): Crypto, Perps and Spot
// would all show BTC, HYPE and ETH. Trending keeps its top three by
// volume and the Watchlist its newest stars; every other Investing tile
// shows the three markets moving most (largest |24h|) WITHIN its group,
// skipping a coin a tile above already shows while the group has others
// (hlTileMovers), so each stack says something about its group.
//
// PREDICTIONS TOPIC TILES ARE COMPACT (founder, 31 October 2026: the
// 96 px tiles sat empty, since a topic's feed loads only once it is
// opened): a 56 px row, a 28 px surface-1 square (the Settings rows'
// icon tile, KuteListRow, a size down) with POLYMARKET'S OWN GLYPH for
// the topic at the left, 20 px, monochrome in textPrimary (never a
// Material icon: the SVGs under lib/assets/polymarket_tags, pulled from
// polymarket.com's icon set, see the folder's README; a topic Polymarket
// draws no glyph for gets its closest one), and the name. ALWAYS icon +
// name, nothing else, in every state (founder, later that day, on a
// grid where the loaded topic had swapped to a logo stack and a trailing
// count that cut its name to "Br…"): never a logo stack, never a count,
// loaded or not. Only the wide Trending tile (and the Watchlist) keeps
// its stack and its numbers line.
//
// NAMES NEVER TRUNCATE (founder, 31 October 2026): a wide or grid tile
// whose name does not fit on one line sets it on two and drops its stat
// line instead ([_NameAndStat]); the stat goes, never the name.
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
// POSITIONS (founder, 31 October 2026: "the animation and position of
// the buttons is not good"): ONE 16 px gutter on both sides for
// everything (the wide tiles, the labels, the grid); 8 px between grid
// tiles, 12 px between the wide tiles, 16 px above the "Markets" /
// "Topics" label and the grid flush under it; every tile in a group the
// same height; the odd last tile stays left in its column. The header is
// the handle, 12 px, then the title at the left gutter with the circled
// close at the right gutter, centred on it ([_SheetHeader]); the
// Investing and Predictions sheets put the title, the wide tiles and the
// label at the same heights.
//
// MOTION: on open the tiles rise in (6 px, a fade) 16 ms apart on the
// settle easing, the wide tiles first; a press is the app's spring at
// 0.97; a pick animates the tile's fill, ring and check on the chip
// spring, holds 140 ms so the state is seen, then the sheet closes on
// the settle. A group with subcategories (Traditional → Stocks, Indices,
// Commodities, FX, Pre-IPO; Crypto → its sectors; a Predictions topic →
// its topics) slides to its own grid inside the same sheet on the sheet
// spring: the outgoing grid moves 24 px left and fades, the incoming
// comes from 24 px right, the "‹ Investing" back link fading in at the
// left of the header; back reverses. Reduce Motion: everything at once.
// The group's page is the group's name as the title, a wide "All
// Traditional" tile on top, then the subcategories as tiles with the
// same numbers. Tapping any tile picks (category and subcategory) and
// closes; a tile without subcategories picks and closes at once. The
// pick writes the same providers and sends the same events the pills did.
//
// THE BAR OVER THIS SHEET reads "Pick a market group"; tapped, the Sal
// sheet opens with every category of the venue under its composer, as
// these same tiles in the same two-column grid, the picked one in the
// white-pill style (founder, 1 November 2026: "user has clicked, so show
// the market categories"; [_SalCategoryGrid]). A tap there picks and
// closes both sheets. Never generic recommendation cards.
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
import 'package:flutter_svg/flutter_svg.dart';
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
    show KutePressable, KuteStaggerIn, kuteReduceMotion;
import 'package:kute/screens/usd/usd_account_screen.dart' show InvestmentsTab;
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/theme/kute_motion.dart';

/// The picked pill's sub-context, for its label: the category on screen
/// (and its subcategory when one is picked), or the Portfolio section.
/// Always a name, so the picked pill always shows what it holds (founder,
/// 31 October 2026: "it should be more clear that we have much more
/// context here"), except the default browse (Trending, no subcategory),
/// which reads "Filter" to prompt a pick (founder, 1 November 2026).
String investmentsCategoryLabel(
    WidgetRef ref, AppLocalizations l10n, InvestmentsTab tab) {
  switch (tab) {
    case InvestmentsTab.investing:
      final sel = ref.watch(hlBrowseSelectionProvider);
      final sub = sel.sub;
      if (sel.tab == HlBrowseTab.trending && sub == HlBrowseSub.all) {
        return l10n.categoryFilterPrompt;
      }
      return sub == HlBrowseSub.all
          ? sel.tab.localizedLabel(l10n)
          : '${sel.tab.localizedLabel(l10n)} · ${sub.localizedLabel(l10n)}';
    case InvestmentsTab.predictions:
      final sel = ref.watch(polyBrowseSelectionProvider);
      final pill = sel.pill;
      final subKey = sel.subOf(pill);
      if (pill == PolyPill.trending && subKey == pill.defaultSub) {
        return l10n.categoryFilterPrompt;
      }
      if (subKey == pill.defaultSub) return polyPillLabel(l10n, pill);
      final sub = polySubsFor(ref, pill).where((s) => s.key == subKey);
      return sub.isEmpty
          ? polyPillLabel(l10n, pill)
          : '${polyPillLabel(l10n, pill)} · ${polySubLabel(l10n, sub.first)}';
    case InvestmentsTab.positions:
      return portfolioSectionLabel(l10n, ref.watch(portfolioSectionProvider));
  }
}

/// The picked pill's shorter context, for a row too narrow for
/// [investmentsCategoryLabel]: the subcategory alone ("Commodities" for
/// "Stocks and shares · Commodities"); null when there is nothing shorter.
String? investmentsCategoryShortLabel(
    WidgetRef ref, AppLocalizations l10n, InvestmentsTab tab) {
  switch (tab) {
    case InvestmentsTab.investing:
      final sub = ref.watch(hlBrowseSelectionProvider).sub;
      return sub == HlBrowseSub.all ? null : sub.localizedLabel(l10n);
    case InvestmentsTab.predictions:
      final sel = ref.watch(polyBrowseSelectionProvider);
      final pill = sel.pill;
      final subKey = sel.subOf(pill);
      if (subKey == pill.defaultSub) return null;
      final sub = polySubsFor(ref, pill).where((s) => s.key == subKey);
      return sub.isEmpty ? null : polySubLabel(l10n, sub.first);
    case InvestmentsTab.positions:
      return null;
  }
}

String portfolioSectionLabel(AppLocalizations l10n, PortfolioSection s) =>
    switch (s) {
      PortfolioSection.activity => l10n.activity,
      PortfolioSection.charts => l10n.portfolioSectionPnlCharts,
      PortfolioSection.balances => l10n.portfolioSectionBalances,
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

/// The markets for a tile's logo stack: the [take] moving most today
/// (largest |24h| move) among [markets], one without a yesterday last and
/// ties by volume. A coin in [shown] (a tile above shows it) is skipped
/// while the group has others, so the stacks differ; the picks' coins are
/// added to [shown] for the tiles after.
List<HlMarket> hlTileMovers(List<HlMarket> markets, Set<String> shown,
    {int take = _kLogos}) {
  double move(HlMarket m) => m.prevDayPx > 0 && m.markPx > 0
      ? (m.markPx / m.prevDayPx - 1).abs()
      : -1;
  String keyOf(HlMarket m) => m.coin.toUpperCase();
  final ranked = [...markets]..sort((a, b) {
      final byMove = move(b).compareTo(move(a));
      return byMove != 0 ? byMove : b.dayNtlVlm.compareTo(a.dayNtlVlm);
    });
  final out = <HlMarket>[];
  final taken = <String>{};
  // The group's own movers first, then whatever a tile above shows too.
  for (final pass in [false, true]) {
    for (final m in ranked) {
      if (out.length == take) break;
      final k = keyOf(m);
      if (taken.contains(k) || (!pass && shown.contains(k))) continue;
      out.add(m);
      taken.add(k);
    }
  }
  shown.addAll(taken);
  return out;
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

/// A Predictions topic's glyph, Polymarket's own (lib/assets/polymarket_tags,
/// one SVG per pill key; see the folder's README for where each comes
/// from), for its compact tile while its feed is not loaded.
String _polyIconAsset(PolyPill p) => 'lib/assets/polymarket_tags/${p.key}.svg';

IconData _portfolioIcon(PortfolioSection s) => switch (s) {
      PortfolioSection.activity => Icons.receipt_long_rounded,
      PortfolioSection.balances => Icons.pie_chart_rounded,
      PortfolioSection.charts => Icons.show_chart_rounded,
    };

// ── What the tiles show ────────────────────────────────────────────────

/// The tiles' data from what is already loaded (see the file header),
/// shared by the sheet and its Sal-sheet grid ([_SalCategoryGrid]).
mixin _CategoryData<T extends ConsumerStatefulWidget> on ConsumerState<T> {
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

  /// The events a category's feed holds already: the picked category's
  /// (loaded for the list behind the sheet), or one browsed earlier whose
  /// feed is still alive. Nothing is read for a tile: a feed that does
  /// not exist is left alone and the tile shows its icon.
  List<PolymarketEvent> _polyLoaded(PolyPill p, [String? sub]) {
    final sel = ref.watch(polyBrowseSelectionProvider);
    final query = p == PolyPill.live
        ? const PolyFeedQuery(pill: PolyPill.live)
        : PolyFeedQuery(pill: p, sub: sub ?? sel.subOf(p));
    final onScreen =
        p == sel.pill && (sub == null || sub == sel.subOf(p));
    if (!onScreen && !ref.exists(polyBrowseFeedProvider(query))) {
      return const [];
    }
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

}

// ── The sheet ──────────────────────────────────────────────────────────

class _InvestmentsCategorySheet extends ConsumerStatefulWidget {
  const _InvestmentsCategorySheet({required this.tab});

  final InvestmentsTab tab;

  @override
  ConsumerState<_InvestmentsCategorySheet> createState() =>
      _InvestmentsCategorySheetState();
}

class _InvestmentsCategorySheetState
    extends ConsumerState<_InvestmentsCategorySheet>
    with _CategoryData<_InvestmentsCategorySheet> {
  /// The group whose subcategories are on screen (an [HlBrowseTab] or a
  /// [PolyPill]); null for the section's own grid.
  Object? _group;

  /// Which way the last page change went, for the slide.
  bool _forward = true;

  /// The tile just tapped, drawn picked while the sheet closes (see the
  /// file header); null reads the providers.
  (Object, Object)? _pending;

  /// Whether a tile is drawn picked: the tap's own while one is pending,
  /// else [current] (the providers' selection).
  bool _picked(Object a, Object b, bool current) =>
      _pending == null ? current : _pending == (a, b);

  /// A pick: the tile's state springs on, holds 140 ms, then the sheet
  /// closes and [write] runs (the providers, the event). Without [hold]
  /// (a pick made in the Sal sheet over this one, which held it already)
  /// the sheet closes and [write] runs at once.
  void _pick((Object, Object) key, VoidCallback write, {bool hold = true}) {
    if (_pending != null) return;
    if (hold) HapticFeedback.selectionClick();
    setState(() => _pending = key);
    void close() {
      if (!mounted) return;
      _closeSheet();
      write();
    }

    if (!hold) return close();
    final wait = kuteReduceMotion(context)
        ? Duration.zero
        : const Duration(milliseconds: 140);
    Future<void>.delayed(wait, close);
  }

  /// This sheet closes: popped while it is on top, else (the Sal sheet
  /// over it still on its way out) taken out from under it.
  void _closeSheet() {
    final navigator = Navigator.of(context);
    final route = ModalRoute.of(context);
    if (route == null || route.isCurrent) {
      navigator.pop();
    } else if (route.isActive) {
      navigator.removeRoute(route);
    }
  }

  /// A tile picked in the Sal sheet's grid ([_SalCategoryGrid]): the Sal
  /// sheet has closed; this one closes too and the pick is written, with
  /// the same providers and events as a tile here.
  void _pickFromSal(Object group, Object sub) {
    switch ((group, sub)) {
      case (final HlBrowseTab t, final HlBrowseSub s):
        _pickHl(t, s, hold: false);
      case (final PolyPill p, final String s):
        _pickPoly(p, PolySub(s), hold: false);
      case (final PortfolioSection s, _):
        _pickPortfolio(s, hold: false);
    }
  }

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
        // The grid's foot scrolls clear of the floating bar.
        padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, kuteBarScrollClearance.h),
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
          _SheetHeader(
            title: group == null
                ? _sectionTitle(l10n)
                : _groupTitle(l10n, group),
            back: group == null ? null : _sectionTitle(l10n),
            onBack: _back,
          ),
          Flexible(
            // A group's grid slides in 24 px from the right over the
            // section's (which moves 24 px left and fades), and back, on
            // the sheet spring (see the file header); the box they share
            // eases between their heights on the same spring, so the sheet
            // never jumps.
            child: AnimatedSize(
              duration: reduce ? Duration.zero : KuteMotion.sheetInDuration,
              curve: reduce ? Curves.linear : KuteMotion.sheetIn,
              alignment: Alignment.topCenter,
              child: AnimatedSwitcher(
              duration: reduce ? Duration.zero : KuteMotion.sheetInDuration,
              switchInCurve: reduce ? Curves.linear : KuteMotion.sheetIn,
              switchOutCurve: reduce ? Curves.linear : KuteMotion.settle,
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.topCenter,
                children: [...previous, if (current != null) current],
              ),
              transitionBuilder: (child, animation) {
                final incoming = child.key == page.key;
                final dir = _forward ? 1.0 : -1.0;
                final from = (incoming ? dir : -dir) * 24.0;
                return FadeTransition(
                  opacity: animation,
                  child: AnimatedBuilder(
                    animation: animation,
                    builder: (context, child) => Transform.translate(
                      offset: Offset(from * (1 - animation.value), 0),
                      child: child,
                    ),
                    child: child,
                  ),
                );
              },
              child: page,
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  /// The bar while this sheet is up (kute_bar_context.dart): "Pick a
  /// market group" over "or ask Sal to find one". Tapped, the Sal sheet
  /// opens with every category of the venue under its composer, as this
  /// sheet's own tiles ([_SalCategoryGrid]; founder, 1 November 2026:
  /// "user has clicked, so show the market categories"), never generic
  /// recommendation cards.
  KuteBarContext _barContext(BuildContext context) {
    final l10n = context.l10n;
    return KuteBarContext(
      label: l10n.barPickMarketGroup,
      sublabel: l10n.barPickMarketGroupSub,
      sheetHome: (_) =>
          _SalCategoryGrid(tab: widget.tab, onPick: _pickFromSal),
      category: widget.tab == InvestmentsTab.predictions
          ? SearchCategory.predictions
          : SearchCategory.perpetuals,
      searchHint: widget.tab == InvestmentsTab.predictions
          ? l10n.searchPredictionsHint
          : l10n.searchInvestmentsHint,
      source: 'category_sheet',
    );
  }

  /// A small label over a grid: 16 above it, the grid flush under.
  Widget _label(BuildContext context, String text) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(0, 16.h, 0, 6.h),
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

  /// A real two-column grid: every tile [extent] tall ([_Tile.gridHeight],
  /// or [_Tile.compactHeight] for the Predictions topics), 8 apart, the
  /// odd last one half width at the left. It sits in the sheet's
  /// ListView, so it is shrink-wrapped and never scrolls on its own.
  Widget _grid(List<Widget> tiles,
          {double extent = _Tile.gridHeight, int first = 3}) =>
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          mainAxisExtent: extent,
        ),
        itemCount: tiles.length,
        // The tiles rise in after the wide tiles and the label ([first]).
        itemBuilder: (_, i) => _rise(first + i, tiles[i]),
      );

  /// A tile's arrival: 6 px up and a fade, 16 ms after the one before
  /// (see the file header).
  Widget _rise(int index, Widget child) => KuteStaggerIn(
        index: index,
        step: const Duration(milliseconds: 16),
        rise: 6,
        limit: 64,
        child: child,
      );

  // ── Investing ────────────────────────────────────────────────────────

  void _pickHl(HlBrowseTab t, HlBrowseSub s, {bool hold = true}) =>
      _pick((t, s), hold: hold, () {
        final current = ref.read(hlBrowseSelectionProvider);
        if (t == current.tab && s == current.sub) return;
        TrackingService.track('hl_category_pill_tapped', params: {
          'section': t.key,
          if (s != HlBrowseSub.all) 'subcategory': s.key,
        });
        ref.read(hlBrowseSelectionProvider.notifier).state =
            current.copyWith(tab: t, sub: s);
      });

  List<Widget> _investing(BuildContext context) {
    final l10n = context.l10n;
    final c = context.colors;
    final sel = ref.watch(hlBrowseSelectionProvider);
    final onOffer = hlCategoriesOnOffer(ref);
    // The coins the tiles above already show, so the stacks differ.
    final shown = <String>{};

    Widget wide(HlBrowseTab t, {String? lead}) {
      final list = _hlList(t);
      final stat = _hlStat(list);
      // Trending keeps its top three by volume, the Watchlist its newest
      // stars; both count as shown for the tiles under them.
      final top = list.take(_kLogos).toList();
      shown.addAll(top.map((m) => m.coin.toUpperCase()));
      return _Tile.wide(
        key: ValueKey('category-tile-${t.key}'),
        tint: _hlTint(c, t),
        name: t == HlBrowseTab.watchlist
            ? l10n.polyPillWatchlist
            : t.localizedLabel(l10n),
        stat: _StatLine(
            lead: lead,
            count: lead == null ? stat.count : null,
            move: stat.move,
            tail: lead == null ? null : l10n.categoryStatToday),
        logos: _hlLogos(top),
        picked: _picked(t, HlBrowseSub.all, sel.tab == t),
        onTap: () => _pickHl(t, HlBrowseSub.all),
      );
    }

    Widget tile(HlBrowseTab t) {
      final list = _hlList(t);
      final stat = _hlStat(list);
      final subs = _hlSubs(t);
      return _Tile(
        key: ValueKey('category-tile-${t.key}'),
        logos: _hlLogos(hlTileMovers(list, shown)),
        tint: _hlTint(c, t),
        name: t.localizedLabel(l10n),
        stat: _StatLine(count: stat.count, move: stat.move),
        picked: _picked(t, HlBrowseSub.all, sel.tab == t),
        onTap: subs.isEmpty
            ? () => _pickHl(t, HlBrowseSub.all)
            : () => _open(t),
      );
    }

    return [
      if (onOffer.contains(HlBrowseTab.trending))
        _rise(0, wide(HlBrowseTab.trending, lead: l10n.categoryStatMostActive)),
      if (onOffer.contains(HlBrowseTab.watchlist))
        _rise(1, wide(HlBrowseTab.watchlist)),
      _rise(2, _label(context, l10n.categoryGroupMarkets)),
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
    final shown = <String>{};
    return [
      _rise(0, _Tile.wide(
        key: ValueKey('category-tile-${t.key}'),
        tint: tint,
        name: l10n.categoryAllOf(t.localizedLabel(l10n)),
        stat: _StatLine(count: allStat.count, move: allStat.move),
        logos: _hlLogos(hlTileMovers(all, shown)),
        picked: _picked(t, HlBrowseSub.all,
            sel.tab == t && sel.sub == HlBrowseSub.all),
        onTap: () => _pickHl(t, HlBrowseSub.all),
      )),
      _grid(first: 1, [
        for (final s in _hlSubs(t))
          () {
            final list = _hlList(t, s);
            final stat = _hlStat(list);
            return _Tile(
              key: ValueKey('category-tile-${s.key}'),
              logos: _hlLogos(hlTileMovers(list, shown)),
              tint: tint,
              name: s.localizedLabel(l10n),
              stat: _StatLine(count: stat.count, move: stat.move),
              picked: _picked(t, s, sel.tab == t && sel.sub == s),
              onTap: () => _pickHl(t, s),
            );
          }(),
      ]),
    ];
  }

  // ── Predictions ──────────────────────────────────────────────────────

  void _pickPoly(PolyPill p, PolySub s, {bool hold = true}) =>
      _pick((p, s.key), hold: hold, () {
        final current = ref.read(polyBrowseSelectionProvider);
        if (p == current.pill && s.key == current.subOf(p)) return;
        TrackingService.track('category_pill_tapped', params: {
          'section': p.key,
          if (s.key != p.defaultSub) 'subcategory': s.route,
        });
        ref.read(polyBrowseSelectionProvider.notifier).state =
            current.copyWith(pill: p).copyWith(sub: s.key);
      });

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
          key: ValueKey('category-tile-${p.key}'),
          tint: _polyTint(c, p),
          name: p == PolyPill.watchlist
              ? l10n.polyPillWatchlist
              : polyPillLabel(l10n, p),
          stat: statOf(p, lead: lead),
          logos: _polyLogos(_polyLoaded(p)),
          picked: _picked(p, p.defaultSub, sel.pill == p),
          onTap: () => _pickPoly(p, PolySub(p.defaultSub)),
        );

    // A topic: compact, always its icon and its name (see the file
    // header), whatever its feed has loaded.
    Widget tile(PolyPill p) {
      return _Tile.compact(
        key: ValueKey('category-tile-${p.key}'),
        asset: _polyIconAsset(p),
        tint: _polyTint(c, p),
        name: polyPillLabel(l10n, p),
        picked: _picked(p, p.defaultSub, sel.pill == p),
        onTap: _polySubs(p).isEmpty
            ? () => _pickPoly(p, PolySub(p.defaultSub))
            : () => _open(p),
      );
    }

    return [
      if (pills.contains(PolyPill.trending))
        _rise(0, wide(PolyPill.trending, lead: l10n.categoryStatMostActive)),
      if (pills.contains(PolyPill.watchlist))
        _rise(1, wide(PolyPill.watchlist)),
      _rise(2, _label(context, l10n.categoryGroupTopics)),
      _grid([
        for (final p in pills)
          if (p != PolyPill.trending && p != PolyPill.watchlist) tile(p),
      ], extent: _Tile.compactHeight),
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
      _rise(0, _Tile.wide(
        key: ValueKey('category-tile-${p.key}'),
        tint: tint,
        name: l10n.categoryAllOf(polyPillLabel(l10n, p)),
        stat: statOf(all.key),
        logos: _polyLogos(_polyLoaded(p, all.key)),
        picked: _picked(p, all.key, sel.pill == p && sel.subOf(p) == all.key),
        onTap: () => _pickPoly(p, all),
      )),
      _grid(first: 1, [
        for (final s in subs)
          if (s.key != p.defaultSub)
            _Tile.compact(
              key: ValueKey('category-tile-${s.key}'),
              asset: _polyIconAsset(p),
              tint: tint,
              name: polySubLabel(l10n, s),
              picked:
                  _picked(p, s.key, sel.pill == p && sel.subOf(p) == s.key),
              onTap: () => _pickPoly(p, s),
            ),
      ], extent: _Tile.compactHeight),
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
            picked: _picked(s, s, s == current),
            onTap: () => _pickPortfolio(s),
          ),
      ]),
    ];
  }

  void _pickPortfolio(PortfolioSection s, {bool hold = true}) =>
      _pick((s, s), hold: hold, () {
        final current = ref.read(portfolioSectionProvider);
        if (s == current) return;
        TrackingService.track('analytics_tab_selected', params: {
          'tab': InvestmentsTab.positions.key,
          'from_tab': InvestmentsTab.positions.key,
          'surface': 'investments',
          'sub': s.key,
          'from_sub': current.key,
        });
        ref.read(portfolioSectionProvider.notifier).state = s;
      });
}

/// THE CATEGORIES IN THE SAL SHEET (founder, 1 November 2026: "user has
/// clicked, so show the market categories"). Tapping the bar while the
/// category sheet is up opens the Sal sheet with EVERY category of the
/// venue under its composer, as the sheet's own tiles in its two-column
/// grid, 8 apart: Investing's logo stacks with their numbers (96 px),
/// Predictions' Polymarket glyphs with their names (56 px), the
/// Portfolio's sections; the picked one in the white-pill style. A group
/// picks whole (its All). A tap springs the tile on, holds 140 ms (at
/// once under Reduce Motion), then the Sal sheet and the category sheet
/// close together and the pick is written as from the sheet itself.
class _SalCategoryGrid extends ConsumerStatefulWidget {
  const _SalCategoryGrid({required this.tab, required this.onPick});

  final InvestmentsTab tab;

  /// The pick, once the Sal sheet has closed: (group, sub) as the sheet's
  /// own tiles key them.
  final void Function(Object group, Object sub) onPick;

  @override
  ConsumerState<_SalCategoryGrid> createState() => _SalCategoryGridState();
}

class _SalCategoryGridState extends ConsumerState<_SalCategoryGrid>
    with _CategoryData<_SalCategoryGrid> {
  (Object, Object)? _pending;

  bool _picked(Object a, Object b, bool current) =>
      _pending == null ? current : _pending == (a, b);

  void _tap(Object group, Object sub) {
    if (_pending != null) return;
    HapticFeedback.selectionClick();
    setState(() => _pending = (group, sub));
    final wait = kuteReduceMotion(context)
        ? Duration.zero
        : const Duration(milliseconds: 140);
    Future<void>.delayed(wait, () {
      if (!mounted) return;
      // The Sal sheet first, then the category sheet under it.
      Navigator.of(context).pop();
      widget.onPick(group, sub);
    });
  }

  List<Widget> _investing(AppLocalizations l10n, AppColorsExtension c) {
    // What hlCategoriesOnOffer reads, watched so the grid follows it.
    ref.watch(hyperliquidBrowseUniverseProvider);
    ref.watch(hlWatchlistProvider);
    ref.watch(hyperliquidBuilderMarketsMissingProvider);
    final sel = ref.watch(hlBrowseSelectionProvider);
    // The coins the tiles before already show, so the stacks differ;
    // Trending keeps its top three by volume, the Watchlist its newest.
    final shown = <String>{};
    return [
      for (final t in hlCategoriesOnOffer(ref))
        () {
          final list = _hlList(t);
          final stat = _hlStat(list);
          final lead = t == HlBrowseTab.trending;
          final List<HlMarket> top;
          if (lead || t == HlBrowseTab.watchlist) {
            top = list.take(_kLogos).toList();
            shown.addAll(top.map((m) => m.coin.toUpperCase()));
          } else {
            top = hlTileMovers(list, shown);
          }
          return _Tile(
            key: ValueKey('sal-category-tile-${t.key}'),
            logos: _hlLogos(top),
            tint: _hlTint(c, t),
            name: t == HlBrowseTab.watchlist
                ? l10n.polyPillWatchlist
                : t.localizedLabel(l10n),
            stat: _StatLine(
                lead: lead ? l10n.categoryStatMostActive : null,
                count: lead ? null : stat.count,
                move: stat.move,
                tail: lead ? l10n.categoryStatToday : null),
            picked: _picked(t, HlBrowseSub.all, sel.tab == t),
            onTap: () => _tap(t, HlBrowseSub.all),
          );
        }(),
    ];
  }

  List<Widget> _predictions(AppLocalizations l10n, AppColorsExtension c) {
    final sel = ref.watch(polyBrowseSelectionProvider);
    final policy = ref.watch(runtimeCapabilitiesProvider);
    final watchlist = ref.watch(polyWatchlistProvider);
    return [
      for (final p in PolyPill.values)
        if (polyPillOffered(p, policy) &&
            (p != PolyPill.watchlist || watchlist.isNotEmpty))
          _Tile.compact(
            key: ValueKey('sal-category-tile-${p.key}'),
            asset: _polyIconAsset(p),
            tint: _polyTint(c, p),
            name: p == PolyPill.watchlist
                ? l10n.polyPillWatchlist
                : polyPillLabel(l10n, p),
            picked: _picked(p, p.defaultSub, sel.pill == p),
            onTap: () => _tap(p, p.defaultSub),
          ),
    ];
  }

  List<Widget> _portfolio(AppLocalizations l10n, AppColorsExtension c) {
    final current = ref.watch(portfolioSectionProvider);
    return [
      for (final s in PortfolioSection.values)
        _Tile(
          key: ValueKey('sal-category-tile-${s.key}'),
          glyph: _portfolioIcon(s),
          tint: c.chartCategorical[4],
          name: portfolioSectionLabel(l10n, s),
          picked: _picked(s, s, s == current),
          onTap: () => _tap(s, s),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.colors;
    final tiles = switch (widget.tab) {
      InvestmentsTab.investing => _investing(l10n, c),
      InvestmentsTab.predictions => _predictions(l10n, c),
      InvestmentsTab.positions => _portfolio(l10n, c),
    };
    return GridView.builder(
      key: const ValueKey('sal-category-grid'),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        mainAxisExtent: widget.tab == InvestmentsTab.predictions
            ? _Tile.compactHeight
            : _Tile.gridHeight,
      ),
      itemCount: tiles.length,
      itemBuilder: (_, i) => KuteStaggerIn(
        index: i,
        step: const Duration(milliseconds: 16),
        rise: 6,
        limit: 64,
        child: tiles[i],
      ),
    );
  }
}

/// The sheet's header (see the file header): the handle, 12 under it the
/// title at the left gutter and the circled close at the right gutter,
/// centred on it. On a group's page the "‹ Investing" back link fades in
/// before the title (the sheet spring's length; at once under Reduce
/// Motion).
class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.title, this.back, required this.onBack});

  final String title;
  final String? back;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final reduce = kuteReduceMotion(context);
    final backLabel = back;
    final duration = reduce ? Duration.zero : KuteMotion.sheetInDuration;
    Widget fade(Widget child) => AnimatedSwitcher(
          duration: duration,
          switchInCurve: reduce ? Curves.linear : KuteMotion.settle,
          switchOutCurve: reduce ? Curves.linear : KuteMotion.settle,
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          child: child,
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.only(top: 12.h),
          child: AppDecorations.dragHandle(context),
        ),
        // A Stack: the title centred on the sheet's full width and
        // crossfading between the section and the group, the back link at
        // the left gutter and the close at the right, each on its own.
        Padding(
          padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 12.h),
          child: SizedBox(
            height: 40,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 48.w),
                    child: Center(
                      child: fade(Text(
                        title,
                        key: ValueKey(title),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 22.sp,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      )),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: fade(backLabel == null
                      ? const SizedBox.shrink(key: ValueKey('no-back'))
                      : Semantics(
                          key: const ValueKey('back'),
                          button: true,
                          label: backLabel,
                          excludeSemantics: true,
                          child: KutePressable(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: onBack,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.chevron_left_rounded,
                                      size: 22.sp, color: c.textSecondary),
                                  Text(
                                    backLabel,
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
                        )),
                ),
                const Positioned(right: 0, child: KuteCloseButton()),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A logo in a tile's stack, and how many a stack holds; the compact
/// tile's icon circle.
const double _kLogo = 22;
const int _kLogos = 3;
const double _kCompactArt = 28;

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

/// The three shapes a tile takes: the 96 px grid tile (art top-left,
/// name and numbers under it), the full-width 64 px row, and the 56 px
/// compact row of the Predictions topics.
enum _TileShape { grid, wide, compact }

/// A tile: the venue's logos (or the tint's placeholder circle, or a
/// [glyph] in it), the name, the numbers. The picked one is filled and
/// white with the hairline and the shadow, its name bolder.
/// Pressed, it gives the app's press spring.
class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.tint,
    required this.name,
    required this.onTap,
    this.logos = const [],
    this.glyph,
    this.stat,
    this.picked = false,
  })  : shape = _TileShape.grid,
        asset = null,
        count = null;

  const _Tile.wide({
    super.key,
    required this.tint,
    required this.name,
    required this.onTap,
    this.logos = const [],
    this.stat,
    this.picked = false,
  })  : shape = _TileShape.wide,
        glyph = null,
        asset = null,
        count = null;

  /// The compact row: the topic's own glyph ([asset], an SVG) on a 28 px
  /// surface-1 square and the name; nothing else, ever (see the file
  /// header: no logo stack, no count).
  const _Tile.compact({
    super.key,
    required this.tint,
    required this.name,
    required this.onTap,
    this.asset,
    this.picked = false,
  })  : shape = _TileShape.compact,
        logos = const [],
        glyph = null,
        count = null,
        stat = null;

  final Color tint;
  final String name;
  final Widget? stat;
  final int? count;
  final List<Widget> logos;
  final IconData? glyph;

  /// A monochrome SVG for the compact row's square (the Predictions
  /// topics' Polymarket glyphs).
  final String? asset;
  final bool picked;
  final _TileShape shape;
  final VoidCallback onTap;

  /// The grid tile's height, the wide row's and the compact row's.
  static const double gridHeight = 96;
  static const double wideHeight = 64;
  static const double compactHeight = 56;

  double get _height => switch (shape) {
        _TileShape.grid => gridHeight,
        _TileShape.wide => wideHeight,
        _TileShape.compact => compactHeight,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isLight = !context.isDark;
    final reduce = kuteReduceMotion(context);
    final compact = shape == _TileShape.compact;
    final Widget art;
    if (logos.isNotEmpty) {
      art = _LogoStack(logos: logos);
    } else if (asset case final svg?) {
      // The topic's own glyph, monochrome, on the app's surface-1 square
      // (KuteListRow's icon tile, a size down): no tint, no circle.
      final slug = svg.split('/').last.replaceAll('.svg', '');
      art = Container(
        width: _kCompactArt,
        height: _kCompactArt,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.surfaceLight,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.borderSubtle, width: 0.5),
        ),
        child: SvgPicture.asset(
          svg,
          key: ValueKey('category-tile-icon-$slug'),
          width: 20,
          height: 20,
          colorFilter: ColorFilter.mode(c.textPrimary, BlendMode.srcIn),
        ),
      );
    } else {
      final d = compact ? _kCompactArt : _kLogo;
      art = Container(
        width: d,
        height: d,
        decoration: BoxDecoration(
          color: tint.withValues(alpha: glyph == null ? 0.22 : 0.14),
          shape: BoxShape.circle,
        ),
        child: glyph == null
            ? null
            : Icon(glyph, size: compact ? 16 : 14, color: tint),
      );
    }
    final nameStyle = TextStyle(
      color: c.textPrimary,
      fontSize: 15.sp,
      fontWeight: picked ? FontWeight.w600 : FontWeight.w500,
      letterSpacing: -0.2,
    );
    // The picked tile wears the app's own picked language (the strip's
    // picked pill: white, the hairline, the shadow); no check, no accent.
    final body = switch (shape) {
      _TileShape.wide => Row(
          children: [
            art,
            SizedBox(width: 10.w),
            Expanded(
                child: _NameAndStat(name: name, style: nameStyle, stat: stat)),
          ],
        ),
      _TileShape.compact => Row(
          children: [
            art,
            SizedBox(width: 10.w),
            Expanded(
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: nameStyle),
            ),
          ],
        ),
      _TileShape.grid => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            art,
            const Spacer(),
            _NameAndStat(name: name, style: nameStyle, stat: stat),
          ],
        ),
    };
    final surface = isLight ? Colors.white : c.surface;
    return Semantics(
      button: true,
      selected: picked,
      label: name,
      child: KutePressable(
        scale: 0.97,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          // The fill and ring spring between the two states.
          child: AnimatedContainer(
            duration: reduce ? Duration.zero : KuteMotion.chipDuration,
            curve: reduce ? Curves.linear : KuteMotion.chip,
            width: double.infinity,
            height: _height,
            margin: EdgeInsets.only(bottom: shape == _TileShape.wide ? 12.h : 0),
            padding: compact
                ? const EdgeInsets.symmetric(horizontal: 12)
                : const EdgeInsets.all(12),
            // Picked: the strip's picked pill (white, hairline, shadow;
            // founder, 31 October 2026: "A, in the app's own style").
            // Unpicked: flat surface-1, no border. The shadow stays at
            // the same blur, only transparent, so the chip spring's
            // overshoot never lerps a blur negative.
            decoration: BoxDecoration(
              color: picked ? surface : c.surfaceLight,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: picked
                    ? (isLight ? c.border : c.borderSubtle)
                    : Colors.transparent,
                width: isLight ? 1.0 : 0.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: picked && isLight
                      ? Colors.black.withValues(alpha: 0.04)
                      : Colors.transparent,
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: body,
          ),
        ),
      ),
    );
  }
}

/// A tile's name with its stat line under it, the name never cut
/// (founder, 31 October 2026): the name on one line and the stat under
/// it while the name fits the width; a name that needs more runs onto a
/// second line and the stat is dropped, not the name.
class _NameAndStat extends StatelessWidget {
  const _NameAndStat({required this.name, required this.style, this.stat});

  final String name;
  final TextStyle style;
  final Widget? stat;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final painter = TextPainter(
            text: TextSpan(text: name, style: style),
            maxLines: 1,
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout(maxWidth: constraints.maxWidth);
          final fits = !painter.didExceedMaxLines;
          painter.dispose();
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  maxLines: fits ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: style),
              if (fits && stat != null) ...[SizedBox(height: 2.h), stat!],
            ],
          );
        },
      );
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
