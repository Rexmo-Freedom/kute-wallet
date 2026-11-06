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
//     grid (every card the same 96 px, 8 px apart; an odd last card full
//     width as the wide row, never a card alone in half the width: the
//     app's no-orphan rule, kute_action_cards.dart; [_tileGrid]). A tile
//     is THE VENUE'S OWN ARTWORK, never a
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
// THE TWO SHEETS ARE ONE DESIGN (founder, 6 November 2026, the Investing
// and Predictions sheets side by side). A Predictions topic is the same
// 96 px card as an Investing market group: its visual POLYMARKET'S OWN
// GLYPH for the topic, 20 px, monochrome in textPrimary on a 28 px
// surface-1 square (the Settings rows' icon tile, KuteListRow, a size
// down; never a Material icon: the SVGs under lib/assets/polymarket_tags,
// pulled from polymarket.com's icon set, see the folder's README; a topic
// Polymarket draws no glyph for gets its closest one), never a logo stack
// (founder, 31 October 2026); the name under it on its own line, so a
// count never cuts it (the old 56 px rows cut "Breaking" to "Br…"); and
// one quiet numbers line where a count is at hand ("12 markets · $3.4M
// vol today" from a loaded feed, "48 markets" from the topic row's own
// count), none where it is not. Predictions' Trending row is Investing's:
// the stack of its top markets' images and "Most active · $12M vol today"
// (no more bare tinted dot: a wide tile wears its glyph until its images
// land).
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
// today"), the watchlist's count and the counts the topic rows read for
// their subcategories (Crypto's site counts, a related tag's open
// events). The one list the sheet reads for itself is Trending's, the
// default browse (disk first, only where the person browses), for its
// stack.
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
// MOTION, THE SAME AS A PILL SWITCH (founder, 6 November 2026: "why are
// the animations here when clicking the buttons not the same as the ones
// from these buttons, as in going to the next page?"). On open the tiles
// rise in (6 px, a fade) 16 ms apart on the settle easing, the wide tiles
// first. A press is the app's press spring at the app's scale
// (KutePressable, KuteMotion.pressScale: the pills' and cards' own). A
// pick springs the tile's fill and ring on the chip spring (the switch's
// white pill), holds 140 ms so the state is seen, then the sheet closes
// on the settle and, once it has cleared the page
// ([kCategoryPickWriteDelay], 30% into its close), the pick is written:
// the page then moves exactly as a pill switch moves it, the pill's words
// morphing to "Predictions · Live" on the chip spring with its width
// (kute_pill_tabs.dart) and the list switching in, a fade and 24 px from
// the right on the sheet spring (KuteMotion.switchIn, SliverSelectionFade;
// the Dollars body does the same between Activity, Investing and
// Predictions). A group with subcategories (Traditional → Stocks, Indices,
// Commodities, FX, Pre-IPO; Crypto → its sectors; a Predictions topic →
// its topics) goes to its own grid inside the same sheet with the same
// switch: the outgoing grid moves 24 px left and fades, the incoming
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
// these same cards in the same two-column grid (an odd last one full
// width), the picked one in the white-pill style (founder, 1 November 2026: "user has clicked, so show
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
import 'package:kute/screens/polymarket/components/poly_category_icons.dart'
    show polyCategoryTint;
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
    case InvestmentsTab.activity:
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
    case InvestmentsTab.activity:
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

/// How far into the sheet's close a pick is written (see the file
/// header): 30% of the close, when the settle easing has taken the sheet
/// most of the way down, so the page's switch (the pill's words, the list
/// sliding in) plays in full view rather than under the sheet.
final Duration kCategoryPickWriteDelay = KuteMotion.sheetOutDuration * 0.3;

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
/// from), for its card (and for Trending's row until its images land).
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

  /// Whether this person browses Predictions (the policy's gate): only
  /// then is Trending's list read for its tile.
  bool get _polyBrowses =>
      ref.watch(runtimeCapabilitiesProvider).allows('polymarket.browse');

  /// The events a category's feed holds already: the picked category's
  /// (loaded for the list behind the sheet), or one browsed earlier whose
  /// feed is still alive. Trending, the default browse, is the one list
  /// read for a tile (disk first, where the person browses), so its stack
  /// is Investing's (founder, 6 November 2026); any other feed that does
  /// not exist is left alone and the tile shows its glyph.
  List<PolymarketEvent> _polyLoaded(PolyPill p, [String? sub]) {
    final sel = ref.watch(polyBrowseSelectionProvider);
    final query = p == PolyPill.live
        ? const PolyFeedQuery(pill: PolyPill.live)
        : PolyFeedQuery(pill: p, sub: sub ?? sel.subOf(p));
    final onScreen =
        p == sel.pill && (sub == null || sub == sel.subOf(p));
    final trending = p == PolyPill.trending &&
        query.sub == PolyPill.trending.defaultSub &&
        _polyBrowses;
    if (!onScreen && !trending && !ref.exists(polyBrowseFeedProvider(query))) {
      return const [];
    }
    return ref.watch(polyBrowseFeedProvider(query)).events;
  }

  /// A Predictions tile's numbers (see the file header): a loaded feed's
  /// count and 24h volume ("12 markets · $3.4M vol today"; [lead] in the
  /// count's place, "Most active · $12M vol today"), else the count the
  /// topic's own row already read ("48 markets", Crypto's site counts and
  /// a subcategory's), else none: the card carries its glyph and name.
  _StatLine? _polyStat(PolyPill p, {String? sub, String? lead}) {
    if (p == PolyPill.watchlist) {
      return _StatLine(count: ref.watch(polyWatchlistProvider).length);
    }
    final events = _polyLoaded(p, sub);
    if (events.isNotEmpty) {
      final volume = events.fold<double>(0, (sum, e) => sum + e.volume24hr);
      return _StatLine(
        lead: lead,
        count: lead == null ? events.length : null,
        volume: volume > 0 ? volume : null,
      );
    }
    if (lead != null) return null;
    final key = sub ?? p.defaultSub;
    final count =
        polySubsFor(ref, p).where((s) => s.key == key).firstOrNull?.count;
    return count == null || count <= 0 ? null : _StatLine(count: count);
  }

  /// The top markets' images for a Predictions tile, each on its
  /// category's soft tint (Investing's letter discs) while it loads, and
  /// the market's initials there if it fails: never a blank ring.
  List<Widget> _polyLogos(List<PolymarketEvent> events) {
    final fallback = Theme.of(context).colorScheme.onSurfaceVariant;
    return [
      for (final e in events)
        if (e.imageUrl != null && e.imageUrl!.isNotEmpty)
          DecoratedBox(
            decoration: BoxDecoration(
              color: polyCategoryTint(e.category, fallback)
                  .withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: PolyCrestImage(
              url: e.imageUrl!,
              size: _kLogo,
              radius: _kLogo / 2,
              label: e.title,
              category: e.category,
            ),
          ),
    ].take(_kLogos).toList();
  }

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

  /// A pick: the tile's state springs on (the chip spring, as the pill
  /// switch's white pill), holds 140 ms, then the sheet closes and, once
  /// it has cleared the page ([kCategoryPickWriteDelay]), [write] runs
  /// (the providers, the event): the page then switches in full view
  /// exactly as a pill switch does, the pill's words morphing and the list
  /// sliding in (see the file header). Without [hold] (a pick made in the
  /// Sal sheet over this one, which held it already) the sheet closes at
  /// once. [write] is handed the app's container: this sheet may be gone
  /// by then. Under Reduce Motion everything at once.
  void _pick((Object, Object) key, void Function(ProviderContainer) write,
      {bool hold = true}) {
    if (_pending != null) return;
    if (hold) HapticFeedback.selectionClick();
    setState(() => _pending = key);
    final container = ProviderScope.containerOf(context, listen: false);
    final navigator = Navigator.of(context);
    void close() {
      if (!mounted) return;
      final reduce = kuteReduceMotion(context);
      _closeSheet();
      if (reduce) return write(container);
      Future<void>.delayed(kCategoryPickWriteDelay, () {
        // The app is still there (a test may have torn it down).
        if (navigator.mounted) write(container);
      });
    }

    // Under Reduce Motion no hold: the sheet goes and the pick is written
    // in the tap itself.
    if (!hold || kuteReduceMotion(context)) return close();
    Future<void>.delayed(const Duration(milliseconds: 140), close);
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
        InvestmentsTab.activity ||
        InvestmentsTab.positions =>
          l10n.walletPortfolioAction,
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
          InvestmentsTab.activity ||
          InvestmentsTab.positions =>
            _portfolio(context),
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
            // the switch's spring (KuteMotion.switchIn, the one every
            // switch rides; see the file header); the box they share
            // eases between their heights on the same spring, so the sheet
            // never jumps.
            child: AnimatedSize(
              duration: reduce ? Duration.zero : KuteMotion.switchDuration,
              curve: reduce ? Curves.linear : KuteMotion.switchIn,
              alignment: Alignment.topCenter,
              child: AnimatedSwitcher(
              duration: reduce ? Duration.zero : KuteMotion.switchDuration,
              switchInCurve: reduce ? Curves.linear : KuteMotion.switchIn,
              switchOutCurve: reduce ? Curves.linear : KuteMotion.switchOut,
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.topCenter,
                children: [...previous, if (current != null) current],
              ),
              transitionBuilder: (child, animation) {
                final incoming = child.key == page.key;
                final dir = _forward ? 1.0 : -1.0;
                final from =
                    (incoming ? dir : -dir) * KuteMotion.switchSlide;
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

  /// The sheet's two-column grid ([_tileGrid]): 96 px cards 8 apart, an
  /// odd last one full width. The tiles rise in after the wide tiles and
  /// the label ([first]).
  Widget _grid(List<_Tile> tiles, {int first = 3}) =>
      _tileGrid(tiles, arrive: (i, tile) => _rise(first + i, tile));

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
      _pick((t, s), hold: hold, (c) {
        final current = c.read(hlBrowseSelectionProvider);
        if (t == current.tab && s == current.sub) return;
        TrackingService.track('hl_category_pill_tapped', params: {
          'section': t.key,
          if (s != HlBrowseSub.all) 'subcategory': s.key,
        });
        c.read(hlBrowseSelectionProvider.notifier).state =
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

    _Tile tile(HlBrowseTab t) {
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
      _pick((p, s.key), hold: hold, (c) {
        final current = c.read(polyBrowseSelectionProvider);
        if (p == current.pill && s.key == current.subOf(p)) return;
        TrackingService.track('category_pill_tapped', params: {
          'section': p.key,
          if (s.key != p.defaultSub) 'subcategory': s.route,
        });
        c.read(polyBrowseSelectionProvider.notifier).state =
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

    // Trending and the Watchlist as Investing's: the stack of their top
    // markets' images and the numbers; the glyph until the images land.
    Widget wide(PolyPill p, {String? lead}) => _Tile.wide(
          key: ValueKey('category-tile-${p.key}'),
          tint: _polyTint(c, p),
          name: p == PolyPill.watchlist
              ? l10n.polyPillWatchlist
              : polyPillLabel(l10n, p),
          stat: _polyStat(p, lead: lead),
          logos: _polyLogos(_polyLoaded(p)),
          asset: _polyIconAsset(p),
          picked: _picked(p, p.defaultSub, sel.pill == p),
          onTap: () => _pickPoly(p, PolySub(p.defaultSub)),
        );

    // A topic: Investing's card, Polymarket's glyph for the topic, its
    // name and the numbers at hand (see the file header).
    _Tile tile(PolyPill p) => _Tile(
          key: ValueKey('category-tile-${p.key}'),
          asset: _polyIconAsset(p),
          tint: _polyTint(c, p),
          name: polyPillLabel(l10n, p),
          stat: _polyStat(p),
          picked: _picked(p, p.defaultSub, sel.pill == p),
          onTap: _polySubs(p).isEmpty
              ? () => _pickPoly(p, PolySub(p.defaultSub))
              : () => _open(p),
        );

    return [
      if (pills.contains(PolyPill.trending))
        _rise(0, wide(PolyPill.trending, lead: l10n.categoryStatMostActive)),
      if (pills.contains(PolyPill.watchlist))
        _rise(1, wide(PolyPill.watchlist)),
      _rise(2, _label(context, l10n.categoryGroupTopics)),
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

    return [
      _rise(0, _Tile.wide(
        key: ValueKey('category-tile-${p.key}'),
        tint: tint,
        name: l10n.categoryAllOf(polyPillLabel(l10n, p)),
        stat: _polyStat(p, sub: all.key),
        logos: _polyLogos(_polyLoaded(p, all.key)),
        asset: _polyIconAsset(p),
        picked: _picked(p, all.key, sel.pill == p && sel.subOf(p) == all.key),
        onTap: () => _pickPoly(p, all),
      )),
      _grid(first: 1, [
        for (final s in subs)
          if (s.key != p.defaultSub)
            _Tile(
              key: ValueKey('category-tile-${s.key}'),
              asset: _polyIconAsset(p),
              tint: tint,
              name: polySubLabel(l10n, s),
              stat: _polyStat(p, sub: s.key),
              picked:
                  _picked(p, s.key, sel.pill == p && sel.subOf(p) == s.key),
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
            picked: _picked(s, s, s == current),
            onTap: () => _pickPortfolio(s),
          ),
      ]),
    ];
  }

  void _pickPortfolio(PortfolioSection s, {bool hold = true}) =>
      _pick((s, s), hold: hold, (c) {
        final current = c.read(portfolioSectionProvider);
        if (s == current) return;
        TrackingService.track('analytics_tab_selected', params: {
          'tab': InvestmentsTab.positions.key,
          'from_tab': InvestmentsTab.positions.key,
          'surface': 'investments',
          'sub': s.key,
          'from_sub': current.key,
        });
        c.read(portfolioSectionProvider.notifier).state = s;
      });
}

/// THE CATEGORIES IN THE SAL SHEET (founder, 1 November 2026: "user has
/// clicked, so show the market categories"). Tapping the bar while the
/// category sheet is up opens the Sal sheet with EVERY category of the
/// venue under its composer, as the sheet's own cards in its two-column
/// grid ([_tileGrid], 96 px, 8 apart, an odd last one full width):
/// Investing's logo stacks with their numbers, Predictions' Polymarket
/// glyphs with their names and numbers (Trending's stack), the Portfolio's
/// sections; the picked one in the white-pill style. A group
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

  List<_Tile> _investing(AppLocalizations l10n, AppColorsExtension c) {
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

  /// The sheet's own Predictions cards: Trending and the Watchlist with
  /// their stacks, every topic its glyph, each with its numbers.
  List<_Tile> _predictions(AppLocalizations l10n, AppColorsExtension c) {
    final sel = ref.watch(polyBrowseSelectionProvider);
    final policy = ref.watch(runtimeCapabilitiesProvider);
    final watchlist = ref.watch(polyWatchlistProvider);
    return [
      for (final p in PolyPill.values)
        if (polyPillOffered(p, policy) &&
            (p != PolyPill.watchlist || watchlist.isNotEmpty))
          _Tile(
            key: ValueKey('sal-category-tile-${p.key}'),
            logos: p == PolyPill.trending || p == PolyPill.watchlist
                ? _polyLogos(_polyLoaded(p))
                : const [],
            asset: _polyIconAsset(p),
            tint: _polyTint(c, p),
            name: p == PolyPill.watchlist
                ? l10n.polyPillWatchlist
                : polyPillLabel(l10n, p),
            stat: _polyStat(p,
                lead: p == PolyPill.trending
                    ? l10n.categoryStatMostActive
                    : null),
            picked: _picked(p, p.defaultSub, sel.pill == p),
            onTap: () => _tap(p, p.defaultSub),
          ),
    ];
  }

  List<_Tile> _portfolio(AppLocalizations l10n, AppColorsExtension c) {
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
      InvestmentsTab.activity ||
      InvestmentsTab.positions =>
        _portfolio(l10n, c),
    };
    return _tileGrid(
      tiles,
      key: const ValueKey('sal-category-grid'),
      arrive: (i, tile) => KuteStaggerIn(
        index: i,
        step: const Duration(milliseconds: 16),
        rise: 6,
        limit: 64,
        child: tile,
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

/// A logo in a tile's stack, and how many a stack holds; the glyph's
/// square (a Predictions topic's visual).
const double _kLogo = 22;
const int _kLogos = 3;
const double _kGlyphArt = 28;

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

/// The two shapes a tile takes: the 96 px grid card (art top-left, name
/// and numbers under it) and the full-width 64 px row (art at the left,
/// name and numbers beside it), which is also a grid's odd last card.
enum _TileShape { grid, wide }

/// The sheets' grid (see the file header): two columns of 96 px cards, 8
/// apart, and an odd last card full width as the wide row, never a card
/// alone in half the width (the app's no-orphan rule, kute_action_cards
/// .dart). Shrink-wrapped: it sits in a list and never scrolls on its own.
/// [arrive] wraps each tile ([index] in reading order) for its rise in.
Widget _tileGrid(List<_Tile> tiles,
    {required Widget Function(int index, Widget tile) arrive, Key? key}) {
  final pairs = tiles.length.isOdd ? tiles.length - 1 : tiles.length;
  return Column(
    key: key,
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (pairs > 0)
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            mainAxisExtent: _Tile.gridHeight,
          ),
          itemCount: pairs,
          itemBuilder: (_, i) => arrive(i, tiles[i]),
        ),
      if (pairs < tiles.length)
        Padding(
          padding: EdgeInsets.only(top: pairs > 0 ? 8 : 0),
          child: arrive(pairs, tiles.last.asLone()),
        ),
    ],
  );
}

/// A tile: the venue's logos (or a Predictions topic's glyph on its
/// square, or the tint's circle with a [glyph] in it), the name, the
/// numbers. The picked one is filled and white with the hairline and the
/// shadow, its name bolder. Pressed, it gives the app's press spring.
class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.tint,
    required this.name,
    required this.onTap,
    this.logos = const [],
    this.glyph,
    this.asset,
    this.stat,
    this.picked = false,
  })  : shape = _TileShape.grid,
        lone = false;

  const _Tile.wide({
    super.key,
    required this.tint,
    required this.name,
    required this.onTap,
    this.logos = const [],
    this.asset,
    this.stat,
    this.picked = false,
  })  : shape = _TileShape.wide,
        glyph = null,
        lone = false;

  const _Tile._lone({
    super.key,
    required this.tint,
    required this.name,
    required this.onTap,
    required this.logos,
    required this.glyph,
    required this.asset,
    required this.stat,
    required this.picked,
  })  : shape = _TileShape.wide,
        lone = true;

  /// This card as a grid's odd last one: full width, laid out as the wide
  /// row, the same art, name, numbers and pick ([_tileGrid]).
  _Tile asLone() => _Tile._lone(
        key: key,
        tint: tint,
        name: name,
        onTap: onTap,
        logos: logos,
        glyph: glyph,
        asset: asset,
        stat: stat,
        picked: picked,
      );

  final Color tint;
  final String name;
  final Widget? stat;
  final List<Widget> logos;
  final IconData? glyph;

  /// A monochrome SVG on the art's square: a Predictions topic's
  /// Polymarket glyph, drawn while there are no [logos] (a topic's card
  /// always; Trending's row until its images land).
  final String? asset;
  final bool picked;
  final _TileShape shape;

  /// A grid's odd last card ([asLone]): the wide row without the gap the
  /// wide rows above a grid keep under them.
  final bool lone;
  final VoidCallback onTap;

  /// The grid card's height and the wide row's.
  static const double gridHeight = 96;
  static const double wideHeight = 64;

  double get _height => switch (shape) {
        _TileShape.grid => gridHeight,
        _TileShape.wide => wideHeight,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isLight = !context.isDark;
    final reduce = kuteReduceMotion(context);
    final Widget art;
    if (logos.isNotEmpty) {
      art = _LogoStack(logos: logos);
    } else if (asset case final svg?) {
      // The topic's own glyph, monochrome, on the app's surface-1 square
      // (KuteListRow's icon tile, a size down): no tint, no circle.
      final slug = svg.split('/').last.replaceAll('.svg', '');
      art = Container(
        width: _kGlyphArt,
        height: _kGlyphArt,
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
      art = Container(
        width: _kLogo,
        height: _kLogo,
        decoration: BoxDecoration(
          color: tint.withValues(alpha: glyph == null ? 0.22 : 0.14),
          shape: BoxShape.circle,
        ),
        child: glyph == null ? null : Icon(glyph, size: 14, color: tint),
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
      // The app's press, the pills' and the cards' own (KuteMotion.press
      // at KuteMotion.pressScale), never a deeper one of its own.
      child: KutePressable(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          // The fill and ring spring between the two states.
          child: AnimatedContainer(
            duration: reduce ? Duration.zero : KuteMotion.chipDuration,
            curve: reduce ? Curves.linear : KuteMotion.chip,
            width: double.infinity,
            height: _height,
            margin: EdgeInsets.only(
                bottom: shape == _TileShape.wide && !lone ? 12.h : 0),
            padding: const EdgeInsets.all(12),
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
