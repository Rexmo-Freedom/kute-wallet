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
//   * two WIDE tiles, Trending and Watchlist (Predictions: Trending as the
//     lone compact full-width card with its chevron, see below, the
//     Watchlist's wide tile under it), then a small "Markets"
//     (Investing) or "Topics" (Predictions) label and a real two-column
//     grid (every card the same compact 60 px, 8 px apart; an odd last
//     card full width as the wide row, never a card alone in half the
//     width: the app's no-orphan rule, kute_action_cards.dart;
//     [_tileGrid]; Predictions then the "Trending now" label and the
//     site's themes in the same grid). COMPACT (founder, 7 November
//     2026, the Predictions topics at 96 px, mostly empty: "cards here ae
//     too big now i thnk"):
//     a grid card is the wide row at half the width, its art at the left
//     and its name (and numbers) beside it, a little shorter than the
//     Trending row. A tile
//     is THE VENUE'S OWN ARTWORK, never a
//     generic icon (founder, 31 October 2026): a stack of up to three
//     overlapping logos of the category's top markets (Hyperliquid's coin
//     and asset logos, Polymarket's event images from the loaded feed), a
//     neutral circle in the group's tint when none is loaded; under it
//     the name (w500) and the numbers line ("64 markets · ▲ 0.5%", "Most
//     active · ▲ 1.8% today", "N markets · $12M vol today").
//
// EVERY TILE IS THE APP'S ONE CARD (founder, 7 November 2026: one card
// surface across the app): the soft card the Goals squares and the
// action cards wear (KuteActionCard.surfaceOf), radius 16. The picked
// tile keeps that card and wears the app's picked outline, the CTA colour
// as a 1.5 ring (the chart pickers' squares, HlSquareBox), its name a
// step bolder (w600); no accent fill, no check, no tint (founder, 31
// October 2026: choice "A" in the app's own style). The ring moves on
// the chip spring; at once under Reduce Motion. The group's tint shows
// only on the placeholder. No chevrons on the grid cards; the lone
// Trending row wears one (the one-card rule, kute_action_cards.dart).
// Every tile has the app's press spring (KutePressable).
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
// compact card as an Investing market group: its visual POLYMARKET'S OWN
// GLYPH for the topic, 20 px, monochrome in textPrimary on a 28 px
// surface-1 square (the Settings rows' icon tile, KuteListRow, a size
// down; never a Material icon: the SVGs under lib/assets/polymarket_tags,
// pulled from polymarket.com's icon set, see the folder's README; a topic
// Polymarket draws no glyph for gets its closest one), never a logo stack
// (founder, 31 October 2026); the name beside it with the numbers under
// the name, so a count never cuts it (the old 56 px rows cut "Breaking"
// to "Br…"); one quiet numbers line where a count is at hand ("12 markets · $3.4M
// vol today" from a loaded feed, "48 markets" from the topic row's own
// count), none where it is not. Predictions' Trending row is Investing's:
// the stack of its top markets' images and "Most active · $12M vol today"
// (no more bare tinted dot: a wide tile wears its glyph until its images
// land).
//
// TRENDING AND "5 MINUTE MARKETS" ON TOP, THE THEMES UNDER THEM. The
// Instant card and its page went on 9 November 2026 (founder: "get rid of
// the instant, those are within crypto"): the crypto rounds are Crypto's 5
// Min, 15 Min, 1 Hour and 4 Hours rows. On 12 November 2026 the founder
// asked for a way straight to them from the top of the sheet: a SECOND
// CARD in Trending's row, to its right, "5 minute markets", Trending's own
// card at half the width each ([_TilePair] of two [_Tile.wide], equal
// heights, no chevron: the chevron is the lone card's). It wears the 5 Min
// row's own glyph (poly_sport_icon.dart) and, under its name, the lengths
// the page runs ("5 min · 15 min · 1 hour · 4 hours", wrapping at the
// dots). A tap closes the sheet and opens Predictions › Crypto › 5 Min on
// its five-minute rounds, as Crypto's 5 Min row does
// (`category_pill_tapped`, section `crypto`, subcategory `5m`, plus
// `surface: five_minute_card`). It is a way in, not a category: the Sal
// grid lists the categories only, and the rounds' card never goes on the
// Trending list. Neither card's text is ever cut: Trending's stack shows
// as many of its three images as leave its name whole on one line
// ([_Tile.fitLogos]), its numbers wrap to a second line, and a name too
// long for its half wraps (the numbers then go, as on every card). Without
// Crypto on offer Trending is the lone card again, full width with its
// chevron ([_Tile.wide] with [_Tile.chevron]). Under them (and the
// Watchlist's row) the "Topics" label and the topics, and under the topics (founder, 9
// November 2026: "the trending now should be under topics") the site's
// SECOND KIND OF CATEGORY (founder, same day: "there are 2 categories on
// Polymarket, find a way to integrate both"): polymarket
// .com's home page has, beside its topic nav, an "All markets" chip row of
// current themes (2028 Election, Midterms, Anthropic IPO, Iran …; read
// live, polyTrendingThemesProvider). They are Trending's own rows: the
// "Trending now" label, then each theme as the compact grid card with the
// row's icon from the resolver (poly_sport_icon.dart: the theme's market
// image; Trending's glyph for one the resolver does not know) or its
// markets' images once its list is loaded, and its count. A tap picks
// Trending at that theme, exactly as a topic's row is picked
// (`category_pill_tapped`, section `trending`, the theme's slug); the pill
// reads "Predictions · Trending · Midterms". Both kinds on one sheet,
// nothing new drawn for it.
//
// GROUPS, AS THE SITE CUTS THEM (founder, 9 November 2026: "have some
// sort of separation in the categories exactly like Polymarket does,
// please, do not just throw them like this"). A topic's grid
// ([_predictionsSubs]) is one grid per group of the site's side list
// (polySubGroups: Crypto's time filters and sections, a divider, its
// assets; Finance's time filters, a divider, its sectors; every other
// topic one group), a hairline between two groups ([_groupDivider], the
// Predictions rows' own divider) or the group's label in the small label
// style where the site gives one. Each group's grid keeps the no-orphan
// rule on its own.
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
// pick springs the tile's ring on the chip spring (the switch's own
// spring), holds 140 ms so the state is seen, then the sheet closes
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
// width), the picked one with its ring (founder, 1 November 2026: "user has clicked, so show
// the market categories"; [_SalCategoryGrid]). A tap there picks and
// closes both sheets. Never generic recommendation cards.
//
// The Portfolio section (three tiles, no numbers) is here for the
// Portfolio's own screen (portfolio_screen.dart); the page's pill row no
// longer offers Portfolio.
//
// BROWSING WITHHELD (runtime policy, `hyperliquid.browse` /
// `polymarket.browse`; [investmentsBrowseCapability]): the venue's page
// lists no markets and shows its notice (InvestmentDiscoveryNotice), so
// this sheet lists no categories, logos or numbers either: the same
// notice stands in for the tiles, and the bar over it offers no grid.
// The policy alone decides; the Portfolio sections never answer to it.

import 'package:kute/screens/shared/kute_bar_context.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:kute/providers/polymarket_provider.dart'
    show cryptoPredictWindowProvider;
import 'package:kute/providers/polymarket_watchlist_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_browse_labels.dart';
import 'package:kute/screens/hyperliquid/components/hl_coin_icon.dart';
import 'package:kute/screens/polymarket/components/market_card.dart'
    show polyGroupRowDivider;
import 'package:kute/screens/polymarket/components/poly_browse_bar.dart'
    show polyPillLabel, polySubLabel, polySubsFor;
import 'package:kute/screens/polymarket/components/poly_category_icons.dart'
    show polyCategoryTint;
import 'package:kute/screens/polymarket/components/poly_crest_image.dart';
import 'package:kute/screens/polymarket/components/poly_sport_icon.dart';
import 'package:kute/screens/portfolio/investments_portfolio.dart'
    show PortfolioSection, portfolioSectionProvider;
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/investment_balance_header.dart'
    show InvestmentDiscoveryNotice;
import 'package:kute/screens/shared/kute_action_cards.dart'
    show KuteActionCard;
import 'package:kute/screens/shared/kute_back_button.dart' show KuteCloseButton;
import 'package:kute/screens/shared/kute_motion.dart'
    show KutePressable, KuteStaggerIn, kuteReduceMotion;
import 'package:kute/screens/usd/usd_account_screen.dart' show InvestmentsTab;
import 'package:kute/services/polymarket/polymarket_category_gate.dart'
    show polymarketCategoryGates;
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/theme/kute_motion.dart';

/// The Predictions selection as the browser shows it: a pick whose
/// category the policy no longer offers (`polymarket.sports`,
/// `polymarket.politics`; [polyPillOffered]) reads as Trending, the list
/// the browser falls back to, so the pill never names a hidden category.
/// Listens to the two category gates only.
PolyBrowseSelection polyShownSelection(WidgetRef ref) {
  final sel = ref.watch(polyBrowseSelectionProvider);
  ref.watch(runtimeCapabilitiesProvider.select(polymarketCategoryGates));
  return polyPillOffered(sel.pill, ref.read(runtimeCapabilitiesProvider))
      ? sel
      : sel.copyWith(pill: PolyPill.trending);
}

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
      final sel = polyShownSelection(ref);
      final pill = sel.pill;
      final subKey = sel.subOf(pill);
      if (pill == PolyPill.trending && subKey == pill.defaultSub) {
        return l10n.categoryFilterPrompt;
      }
      if (subKey == pill.defaultSub) return polyPillLabel(l10n, pill);
      final sub = _polySubNamed(ref, pill, subKey);
      return sub == null
          ? polyPillLabel(l10n, pill)
          : '${polyPillLabel(l10n, pill)} · ${polySubLabel(l10n, sub)}';
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
      final sel = polyShownSelection(ref);
      final pill = sel.pill;
      final subKey = sel.subOf(pill);
      if (subKey == pill.defaultSub) return null;
      final sub = _polySubNamed(ref, pill, subKey);
      return sub == null ? null : polySubLabel(l10n, sub);
    case InvestmentsTab.activity:
    case InvestmentsTab.positions:
      return null;
  }
}

/// The chip [key] names under [pill], for its label: one of the pill's
/// row, or, under Sports, a league of a sport's league row (every league
/// Gamma lists, [polySportsLeaguesProvider]); null for a key no chip has.
PolySub? _polySubNamed(WidgetRef ref, PolyPill pill, String key) {
  final own = polySubsFor(ref, pill).where((s) => s.key == key).firstOrNull;
  if (own != null || pill != PolyPill.sports) return own;
  return ref.watch(polySportsLeaguesProvider).where((s) => s.key == key).firstOrNull;
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

/// The stack of a category's All tile above its rows: the top mover of
/// each row in turn, so a row of three markets never wears the same stack
/// as its All (founder, 9 November 2026: "check on all sub categories").
/// With no rows, [hlTileMovers].
List<HlMarket> hlAllTileMovers(
    List<HlMarket> all, List<List<HlMarket>> rows, Set<String> shown,
    {int take = _kLogos}) {
  if (rows.isEmpty) return hlTileMovers(all, shown, take: take);
  final out = <HlMarket>[];
  final taken = <String>{};
  for (var round = 0; out.length < take && round < take; round++) {
    for (final row in rows) {
      if (out.length == take) break;
      final pick = hlTileMovers(row, {...shown, ...taken}, take: 1);
      if (pick.isEmpty || !taken.add(pick.first.coin.toUpperCase())) continue;
      out.add(pick.first);
    }
  }
  shown.addAll(taken);
  return out;
}

/// The browse capability [tab]'s categories answer to, or null for the
/// Portfolio sections (the person's own positions, never withheld).
String? investmentsBrowseCapability(InvestmentsTab tab) => switch (tab) {
      InvestmentsTab.investing => 'hyperliquid.browse',
      InvestmentsTab.predictions => 'polymarket.browse',
      InvestmentsTab.activity || InvestmentsTab.positions => null,
    };

/// The browse capability the policy withholds from [tab]'s categories
/// (see the file header), or null when they may be listed.
String? investmentsBrowseWithheld(
    RuntimeCapabilitiesService policy, InvestmentsTab tab) {
  final id = investmentsBrowseCapability(tab);
  return id == null || policy.allows(id) ? null : id;
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
      PolyPill.art => c.chartCategorical[4],
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
    final sel = polyShownSelection(ref);
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
  _StatLine? _polyStat(PolyPill p,
      {String? sub, String? lead, bool wrap = false}) {
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
        lines: wrap ? 2 : 1,
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

  void _open(Object group) {
    HapticFeedback.selectionClick();
    setState(() {
      _group = group;
      _forward = true;
    });
  }

  /// One level up: a sport's leagues back to Sports, a group back to the
  /// section's own grid.
  void _back() {
    HapticFeedback.selectionClick();
    setState(() {
      _group = _group is (PolyPill, String) ? PolyPill.sports : null;
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
        (PolyPill _, final String sport) => polySubLabel(l10n, PolySub(sport)),
        _ => '',
      };

  /// What the header's back link names: the section for a group, the
  /// group (Sports) for a sport's leagues.
  String _backTitle(AppLocalizations l10n, Object group) => switch (group) {
        (final PolyPill p, String _) => polyPillLabel(l10n, p),
        _ => _sectionTitle(l10n),
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final reduce = kuteReduceMotion(context);
    final group = _group;
    // Browsing withheld: the venue page's own notice, no tiles.
    final withheld = investmentsBrowseWithheld(
        ref.watch(runtimeCapabilitiesProvider), widget.tab);
    final page = KeyedSubtree(
      key: ValueKey<Object?>(group),
      child: ListView(
        shrinkWrap: true,
        // The grid's foot scrolls clear of the floating bar.
        padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, kuteBarScrollClearance.h),
        children: withheld != null
            ? [
                InvestmentDiscoveryNotice(
                    key: const ValueKey('category-sheet-browse-withheld'),
                    capability: withheld),
              ]
            : switch (widget.tab) {
                InvestmentsTab.investing => group == null
                    ? _investing(context)
                    : _investingSubs(context, group as HlBrowseTab),
                InvestmentsTab.predictions => switch (group) {
                    null => _predictions(context),
                    (PolyPill _, final String sport) =>
                      _predictionsLeagues(context, sport),
                    _ => _predictionsSubs(context, group as PolyPill),
                  },
                InvestmentsTab.activity ||
                InvestmentsTab.positions =>
                  _portfolio(context),
              },
      ),
    );
    final switcher = AnimatedSwitcher(
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
        final from = (incoming ? dir : -dir) * KuteMotion.switchSlide;
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
    );
    return KuteBarContextScope(
      // No bar on this sheet, for Predictions or Investing (founder,
      // 12 November 2026: no "Pick a market group" button).
      barContext: const KuteBarContext.hidden(),
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
            back: group == null ? null : _backTitle(l10n, group),
            onBack: _back,
          ),
          Flexible(
            // A group's grid slides in 24 px from the right over the
            // section's (which moves 24 px left and fades), and back, on
            // the switch's spring (KuteMotion.switchIn, the one every
            // switch rides; see the file header); the box they share
            // eases between their heights on the same spring, so the sheet
            // never jumps.
            // Under Reduce Motion no AnimatedSize at all: at a zero
            // duration it would restart, and finish, inside its own layout
            // whenever the page's height changed (a card's numbers
            // arriving), which Flutter refuses.
            child: reduce
                ? switcher
                : AnimatedSize(
                    duration: KuteMotion.switchDuration,
                    curve: KuteMotion.switchIn,
                    alignment: Alignment.topCenter,
                    child: switcher,
                  ),
          ),
        ],
      ),
      ),
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

  /// The sheet's two-column grid ([_tileGrid]): compact cards 8 apart, an
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
        logos: _hlLogos(hlAllTileMovers(
            all, [for (final s in _hlSubs(t)) _hlList(t, s)], shown)),
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

  /// A Predictions pick: the category at [s] (a topic's row, or one of
  /// Trending's themes), `category_pill_tapped` with the row's slug.
  ///
  /// [surface] names a card that is a way in rather than the category's
  /// own row (the "5 minute markets" card: `five_minute_card`); [also]
  /// runs with the pick, whether or not the category changes.
  void _pickPoly(PolyPill p, PolySub s,
          {bool hold = true,
          String? surface,
          void Function(ProviderContainer)? also}) =>
      _pick((p, s.key), hold: hold, (c) {
        also?.call(c);
        final current = c.read(polyBrowseSelectionProvider);
        if (p == current.pill && s.key == current.subOf(p)) return;
        TrackingService.track('category_pill_tapped', params: {
          'section': p.key,
          if (s.key != p.defaultSub) 'subcategory': s.route,
          if (surface != null) 'surface': surface,
        });
        c.read(polyBrowseSelectionProvider.notifier).state =
            current.copyWith(pill: p).copyWith(sub: s.key);
      });

  /// The "5 minute markets" card (see the file header): Predictions ›
  /// Crypto › 5 Min, on its five-minute rounds whatever length the page's
  /// chips were last left on.
  void _pickFiveMinute() => _pickPoly(PolyPill.crypto, _kFiveMinuteSub,
      surface: 'five_minute_card',
      also: (c) => c.read(cryptoPredictWindowProvider.notifier).state = 5);

  List<Widget> _predictions(BuildContext context) {
    final l10n = context.l10n;
    final c = context.colors;
    final sel = polyShownSelection(ref);
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
    // Trending, the lone card of its row, wears the one-card chevron (see
    // the file header); it reads picked at its own list, All, not at a
    // theme (whose card is ringed then).
    // [half]: one of the top row's two cards, its numbers on up to two
    // lines and its stack giving way to its name.
    Widget wide(PolyPill p,
            {String? lead, bool chevron = false, bool half = false}) =>
        _Tile.wide(
          key: ValueKey('category-tile-${p.key}'),
          tint: _polyTint(c, p),
          name: p == PolyPill.watchlist
              ? l10n.polyPillWatchlist
              : polyPillLabel(l10n, p),
          stat: _polyStat(p, lead: lead, wrap: half),
          logos: _polyLogos(_polyLoaded(p)),
          asset: _polyIconAsset(p),
          chevron: chevron,
          fitLogos: half,
          picked: _picked(p, p.defaultSub,
              sel.pill == p && sel.subOf(p) == p.defaultSub),
          onTap: () => _pickPoly(p, PolySub(p.defaultSub)),
        );

    // One of Trending's themes (see the file header): the compact card
    // with the row's icon from the resolver, or its markets' images once
    // its list is loaded, and the site's count for it.
    _Tile theme(PolySub s) => _Tile(
          key: ValueKey('category-tile-${s.key}'),
          logos: _polyLogos(_polyLoaded(PolyPill.trending, s.key)),
          plateIcon: polySubIcon(PolyPill.trending, s, _kPlateIcon),
          tint: _polyTint(c, PolyPill.trending),
          name: polySubLabel(l10n, s),
          stat: _polyStat(PolyPill.trending, sub: s.key),
          picked: _picked(PolyPill.trending, s.key,
              sel.pill == PolyPill.trending && sel.sub == s.key),
          onTap: () => _pickPoly(PolyPill.trending, s),
        );
    final themes = [
      for (final s in _polySubs(PolyPill.trending))
        if (s.key != PolyPill.trending.defaultSub) theme(s),
    ];

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

    final topics = [
      for (final p in pills)
        if (p != PolyPill.trending && p != PolyPill.watchlist) tile(p),
    ];
    // The way straight to the crypto rounds, beside Trending (see the file
    // header); ringed while Crypto › 5 Min is the page.
    final fiveMinute = _Tile.wide(
      key: const ValueKey('category-tile-five-minute'),
      tint: _polyTint(c, PolyPill.crypto),
      name: l10n.categoryFiveMinuteMarkets,
      stat: const _RoundLengths(),
      plateIcon: polySubIcon(PolyPill.crypto, _kFiveMinuteSub, _kPlateIcon),
      picked: _picked(
          PolyPill.crypto,
          _kFiveMinuteSub.key,
          sel.pill == PolyPill.crypto &&
              sel.subOf(PolyPill.crypto) == _kFiveMinuteSub.key),
      onTap: _pickFiveMinute,
    );
    return [
      if (pills.contains(PolyPill.crypto))
        _TilePair(
          key: const ValueKey('category-top-pair'),
          gap: 8,
          children: [
            _rise(
                0,
                wide(PolyPill.trending,
                    lead: l10n.categoryStatMostActive, half: true)),
            _rise(0, fiveMinute),
          ],
        )
      else
        _rise(
            0,
            wide(PolyPill.trending,
                lead: l10n.categoryStatMostActive, chevron: true)),
      if (pills.contains(PolyPill.watchlist))
        _rise(1, wide(PolyPill.watchlist)),
      // The topics first, then the site's themes, Trending's rows, under
      // their own label (founder, 9 November 2026: "the trending now
      // should be under topics").
      _rise(2, _label(context, l10n.categoryGroupTopics)),
      _grid(first: 3, topics),
      if (themes.isNotEmpty) ...[
        _rise(3 + topics.length,
            _label(context, l10n.categoryGroupTrendingNow)),
        _grid(first: 4 + topics.length, themes),
      ],
    ];
  }

  /// Between two groups of a topic's grid (see the file header): the
  /// Predictions rows' hairline, 12 above and below.
  Widget _groupDivider(BuildContext context) => Padding(
        key: const ValueKey('category-group-divider'),
        padding: EdgeInsets.symmetric(vertical: 12.h),
        child: polyGroupRowDivider(context, 0),
      );

  List<Widget> _predictionsSubs(BuildContext context, PolyPill p) {
    final l10n = context.l10n;
    final c = context.colors;
    final sel = ref.watch(polyBrowseSelectionProvider);
    final tint = _polyTint(c, p);
    final subs = _polySubs(p);
    final all = subs.firstWhere((s) => s.key == p.defaultSub,
        orElse: () => PolySub(p.defaultSub));

    _Tile tile(PolySub s) => _Tile(
          key: ValueKey('category-tile-${s.key}'),
          // The row's own icon (poly_sport_icon.dart), every topic.
          plateIcon: polySubIcon(p, s, _kPlateIcon),
          tint: tint,
          name: polySubLabel(l10n, s),
          stat: _polyStat(p, sub: s.key),
          picked: _picked(p, s.key, sel.pill == p && sel.subOf(p) == s.key),
          // A sport with leagues (Soccer, Tennis …) opens them, as the
          // site's "Soccer ▾" does; its All is the first tile there.
          onTap: p == PolyPill.sports && polySportHasLeagues(s.key)
              ? () => _open((p, s.key))
              : () => _pickPoly(p, s),
        );

    // The site's groups, one grid each (see the file header), a hairline
    // or the group's label between two; the tiles rise in reading order
    // across the groups.
    var next = 1;
    Widget gridOf(List<_Tile> tiles) {
      final grid = _grid(first: next, tiles);
      next += tiles.length;
      return grid;
    }

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
      for (final (i, g) in polySubGroups(p, subs).indexed) ...[
        if (i > 0)
          _rise(
              next++,
              g.label == null
                  ? _groupDivider(context)
                  : _label(context, g.label!)),
        gridOf([
          for (final s in g.subs)
            if (s.key != p.defaultSub) tile(s),
        ]),
      ],
    ];
  }

  /// Sports › a sport's leagues (the site's "Soccer ▾"): all of the sport
  /// as the wide tile, then its leagues, most traded first
  /// ([polySportLeagueSubsProvider]; the sport's list is read for them).
  List<Widget> _predictionsLeagues(BuildContext context, String sport) {
    final l10n = context.l10n;
    final c = context.colors;
    const p = PolyPill.sports;
    final sel = ref.watch(polyBrowseSelectionProvider);
    final tint = _polyTint(c, p);
    final all = PolySub(sport);
    final leagues = [
      for (final s in ref.watch(polySportLeagueSubsProvider(sport)))
        if (s.key != sport) s,
    ];
    return [
      _rise(0, _Tile.wide(
        key: ValueKey('category-tile-$sport'),
        tint: tint,
        name: l10n.categoryAllOf(polySubLabel(l10n, all)),
        stat: _polyStat(p, sub: sport),
        logos: _polyLogos(_polyLoaded(p, sport)),
        plateIcon: PolySportIcon(sub: all, size: _kPlateIcon),
        picked: _picked(p, sport, sel.pill == p && sel.subOf(p) == sport),
        onTap: () => _pickPoly(p, all),
      )),
      _grid(first: 1, [
        for (final s in leagues)
          _Tile(
            key: ValueKey('category-tile-${s.key}'),
            plateIcon: PolySportIcon(sub: s, size: _kPlateIcon),
            tint: tint,
            name: polySubLabel(l10n, s),
            stat: _polyStat(p, sub: s.key),
            picked: _picked(p, s.key, sel.pill == p && sel.subOf(p) == s.key),
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

  /// How wide the back link is: its chevron and its words.
  static double _backWidth(
      BuildContext context, String? label, TextStyle style) {
    if (label == null) return 0;
    final painter = TextPainter(
      text: TextSpan(
          text: label, style: DefaultTextStyle.of(context).style.merge(style)),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = painter.width;
    painter.dispose();
    return 22.sp + width;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final reduce = kuteReduceMotion(context);
    final backLabel = back;
    final backStyle = TextStyle(
      color: c.textSecondary,
      fontSize: 15.sp,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
    );
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
                    // Clear of the back link and the close on both sides,
                    // so it stays centred; a title still too long for the
                    // room left shrinks to it, whole, never cut (founder,
                    // 9 November 2026: "no cut text").
                    padding: EdgeInsets.symmetric(
                        horizontal: math.max(48.w,
                            _backWidth(context, backLabel, backStyle) + 8)),
                    child: Center(
                      child: fade(FittedBox(
                        key: ValueKey(title),
                        fit: BoxFit.scaleDown,
                        child: Text(
                          title,
                          maxLines: 1,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 22.sp,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
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
                                  Text(backLabel, style: backStyle),
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
/// Crypto's 5 Min row, where the "5 minute markets" card leads.
const PolySub _kFiveMinuteSub = PolySub('5m');

const double _kLogo = 22;
const int _kLogos = 3;
const double _kGlyphArt = 28;

/// The glyph on that square.
const double _kPlateIcon = 20;

/// A tile's second line: "[lead ·] N markets · ▲ 1.8% [· $12M vol today]
/// [today]". The move's arrow and colour follow its sign; 0.0% is quiet
/// with no arrow; a null [move] is left out. NEVER CUT (founder, 9
/// November 2026, of "20 markets · $801K vol…": "on the predictions
/// filter, no cut text"): on a card too narrow for the whole line the
/// line gets shorter, never an ellipsis: the volume goes first ("20
/// markets"), then the count (the move stays, "▲ 1.8%"), then "today",
/// then the lead. Should even the shortest not fit, it wraps and the card
/// grows (its pair with it, [_TilePair]).
class _StatLine extends StatelessWidget {
  const _StatLine(
      {this.lead,
      this.count,
      this.move,
      this.volume,
      this.tail,
      this.lines = 1});

  /// How many lines it may wrap to: two on a square card ([_TileShape]).
  final int lines;

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
    List<InlineSpan> spans(
        {required bool withCount,
        required bool withVolume,
        required bool withTail,
        required bool withLead}) {
      final parts = <InlineSpan>[];
      void sep() {
        if (parts.isNotEmpty) parts.add(TextSpan(text: ' · ', style: quiet));
      }

      if (lead != null && withLead) {
        parts.add(TextSpan(text: lead, style: quiet));
      }
      if (count != null && withCount) {
        sep();
        parts.add(
            TextSpan(text: l10n.categoryStatMarkets(count!), style: quiet));
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
      if (volume != null && withVolume) {
        sep();
        parts.add(TextSpan(
            text: l10n.categoryStatVolToday(_compactUsd(volume!)),
            style: quiet));
      }
      if (tail != null && withTail && parts.isNotEmpty) {
        parts.add(TextSpan(text: ' $tail', style: quiet));
      }
      return parts;
    }

    // The line's forms, longest first, each one part shorter.
    final forms = <List<InlineSpan>>[];
    for (final f in const [
      (count: true, volume: true, tail: true, lead: true),
      (count: true, volume: false, tail: true, lead: true),
      (count: false, volume: false, tail: true, lead: true),
      (count: false, volume: false, tail: false, lead: true),
      (count: false, volume: false, tail: false, lead: false),
    ]) {
      final parts = spans(
          withCount: f.count,
          withVolume: f.volume,
          withTail: f.tail,
          withLead: f.lead);
      if (parts.isNotEmpty) forms.add(parts);
    }
    if (forms.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, box) {
      for (final parts in forms) {
        final painter = TextPainter(
          text: TextSpan(
              style: DefaultTextStyle.of(context).style, children: parts),
          maxLines: lines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: box.maxWidth);
        final fits = !painter.didExceedMaxLines;
        painter.dispose();
        if (fits) {
          return Text.rich(TextSpan(children: parts), maxLines: lines);
        }
      }
      // Nothing fits on its lines: the shortest, whole, on as many as it
      // needs.
      return Text.rich(TextSpan(children: forms.last));
    });
  }
}

/// The line under "5 minute markets" (see the file header): the lengths
/// the page runs, "5 min · 15 min · 1 hour · 4 hours", in the numbers
/// line's own style. Never cut and never shrunk: on a half-width card it
/// wraps, and only at a dot (a length is never split, a dot never starts
/// a line).
class _RoundLengths extends StatelessWidget {
  const _RoundLengths();

  @override
  Widget build(BuildContext context) {
    final lengths = context.l10n.categoryInstantLengths
        .split(' · ')
        .map((l) => l.replaceAll(' ', '\u00A0'))
        .join('\u00A0· ');
    return Text(
      lengths,
      key: const ValueKey('category-round-lengths'),
      style: TextStyle(
        color: context.colors.textSecondary,
        fontSize: 12.5.sp,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.1,
        height: 1.2,
      ),
    );
  }
}

/// The shapes a tile takes: the compact grid card (at least 60 px) and the
/// full-width row (at least 64 px), both with the art at the left and the
/// name and numbers beside it (the row is also a grid's odd last card).
/// Both are AT LEAST their height, never fixed (founder, 7 November
/// 2026: "Stocks and shares", "Mobile Legends: Bang Bang" overflowed the
/// fixed card by 2 px): a name that wraps, at any text size and on as
/// many lines as it takes, makes the card taller, never cut short or
/// overflowing.
enum _TileShape { grid, wide }

/// The sheets' grid (see the file header): two columns of compact cards,
/// 8 apart, and an odd last card full width as the wide row, never a card
/// alone in half the width (the app's no-orphan rule, kute_action_cards
/// .dart). Each pair is as tall as its taller card ([_TilePair]): a card
/// whose name (live data from the venue, any length) wraps grows, and its
/// neighbour with it, so the two sit level. Shrink-wrapped: it sits in a
/// list and never scrolls on its own. [arrive] wraps each tile ([index] in
/// reading order) for its rise in.
Widget _tileGrid(List<_Tile> tiles,
    {required Widget Function(int index, Widget tile) arrive, Key? key}) {
  const gap = 8.0;
  final pairs = tiles.length.isOdd ? tiles.length - 1 : tiles.length;
  return Column(
    key: key,
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < pairs; i += 2) ...[
        if (i > 0) const SizedBox(height: gap),
        _TilePair(
          gap: gap,
          children: [arrive(i, tiles[i]), arrive(i + 1, tiles[i + 1])],
        ),
      ],
      if (pairs < tiles.length)
        Padding(
          padding: EdgeInsets.only(top: pairs > 0 ? gap : 0),
          child: arrive(pairs, tiles.last.asLone()),
        ),
    ],
  );
}

/// Two cards side by side, [gap] apart, each half the width; the pair as
/// tall as the taller card's own height and both cards stretched to it
/// (see [_tileGrid]). Each card is laid out at its natural height first,
/// then at the pair's: nothing is measured by hand, so no text size or
/// name can make a card overflow.
class _TilePair extends MultiChildRenderObjectWidget {
  const _TilePair({super.key, required this.gap, required super.children});

  final double gap;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderTilePair(gap);

  @override
  void updateRenderObject(BuildContext context, _RenderTilePair renderObject) =>
      renderObject.gap = gap;
}

class _TilePairData extends ContainerBoxParentData<RenderBox> {}

class _RenderTilePair extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _TilePairData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _TilePairData> {
  _RenderTilePair(this._gap);

  double _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _TilePairData) {
      child.parentData = _TilePairData();
    }
  }

  @override
  void performLayout() {
    final count = childCount;
    final width = constraints.maxWidth;
    final each = count == 0 ? 0.0 : (width - _gap * (count - 1)) / count;
    // Each card at its own height, then all at the tallest.
    var height = 0.0;
    var child = firstChild;
    while (child != null) {
      child.layout(BoxConstraints.tightFor(width: each), parentUsesSize: true);
      height = math.max(height, child.size.height);
      child = childAfter(child);
    }
    // Stretched to the tallest by a least height, not a tight one: a tight
    // box would be its own relayout boundary, and a card whose content
    // later changes (its numbers arriving, a name now on two lines) would
    // lay itself out inside the old height without the pair measuring
    // again. This way any change inside a card lays the pair out anew.
    var x = 0.0;
    child = firstChild;
    while (child != null) {
      child.layout(
          BoxConstraints(minWidth: each, maxWidth: each, minHeight: height),
          parentUsesSize: true);
      (child.parentData! as _TilePairData).offset = Offset(x, 0);
      x += each + _gap;
      child = childAfter(child);
    }
    size = constraints.constrain(Size(width, height));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// A tile: the venue's logos (or a Predictions topic's glyph on its
/// square, or the tint's circle with a [glyph] in it), the name, the
/// numbers, on the app's soft card. The picked one wears the CTA ring, its
/// name bolder. Pressed, it gives the app's press spring.
class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.tint,
    required this.name,
    required this.onTap,
    this.logos = const [],
    this.glyph,
    this.asset,
    this.plateIcon,
    this.stat,
    this.picked = false,
  })  : shape = _TileShape.grid,
        chevron = false,
        fitLogos = false,
        lone = false;

  const _Tile.wide({
    super.key,
    required this.tint,
    required this.name,
    required this.onTap,
    this.logos = const [],
    this.asset,
    this.plateIcon,
    this.stat,
    this.picked = false,
    this.chevron = false,
    this.fitLogos = false,
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
    required this.plateIcon,
    required this.stat,
    required this.picked,
  })  : shape = _TileShape.wide,
        chevron = false,
        fitLogos = false,
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
        plateIcon: plateIcon,
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

  /// Art on the same square, in [asset]'s place: a topic row's own icon
  /// ([PolySubIcon]).
  final Widget? plateIcon;
  final bool picked;

  /// A chevron at the row's right: the lone card of a row (the one-card
  /// rule, kute_action_cards.dart), Predictions' Trending.
  final bool chevron;

  /// The stack gives way to the name (a half-width row, Predictions'
  /// Trending beside "5 minute markets"): as many of the logos as leave
  /// the name whole on one line beside them, never fewer than one.
  final bool fitLogos;
  final _TileShape shape;

  /// A grid's odd last card ([asLone]): the wide row without the gap the
  /// wide rows above a grid keep under them.
  final bool lone;
  final VoidCallback onTap;

  /// The grid card's least height and the wide row's: the grid card a
  /// little shorter than the Trending row (see the file header). A card
  /// whose content needs more is taller ([_TileShape]).
  static const double gridHeight = 60;
  static const double wideHeight = 64;

  /// How far the content sits from the card's edge, its border included:
  /// the same whether the ring is on or off, so nothing moves on a pick.
  static const double _insetX = 13;
  double get _insetY => shape == _TileShape.grid ? 11 : 13;

  double get _height => switch (shape) {
        _TileShape.grid => gridHeight,
        _TileShape.wide => wideHeight,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final reduce = kuteReduceMotion(context);
    final Widget art;
    if (logos.isNotEmpty) {
      art = _LogoStack(logos: logos);
    } else if (plateIcon != null || asset != null) {
      // The topic's own glyph, monochrome, on the app's surface-1 square
      // (KuteListRow's icon tile, a size down): no tint, no circle. A topic
      // row's own icon sits on the same square.
      final svg = asset;
      art = Container(
        width: _kGlyphArt,
        height: _kGlyphArt,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.surfaceLight,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.borderSubtle, width: 0.5),
        ),
        child: plateIcon ??
            SvgPicture.asset(
              svg!,
              key: ValueKey(
                  'category-tile-icon-${svg.split('/').last.replaceAll('.svg', '')}'),
              width: _kPlateIcon,
              height: _kPlateIcon,
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
    // Both shapes: the art at the left, the name and numbers beside it
    // (the grid card is the wide row at half the width; see the file
    // header).
    Widget row(Widget art) => Row(
            children: [
              art,
              SizedBox(width: 10.w),
              Expanded(
                  child: _NameAndStat(name: name, style: nameStyle, stat: stat)),
              // The lone card's chevron (kute_action_cards.dart).
              if (chevron) ...[
                SizedBox(width: 6.w),
                Icon(Icons.chevron_right_rounded,
                    key: const ValueKey('category-tile-chevron'),
                    size: 20,
                    color: c.textTertiary),
              ],
            ],
          );
    final Widget body = !fitLogos || logos.length < 2
        ? row(art)
        : LayoutBuilder(builder: (context, box) {
            final painter = TextPainter(
              text: TextSpan(
                  text: name,
                  style: DefaultTextStyle.of(context).style.merge(nameStyle)),
              maxLines: 1,
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
            )..layout();
            final words = painter.width;
            painter.dispose();
            // What the stack may take: the row less the name and the gap.
            final room = box.maxWidth - 10.w - words - 1;
            final fit = ((room - _kLogo) / _LogoStack.step).floor() + 1;
            final count =
                fit.clamp(1, math.min(logos.length, _kLogos)).toInt();
            return row(_LogoStack(logos: logos.take(count).toList()));
          });
    // The app's one soft card, a smaller radius; picked, the CTA ring on
    // it (the chart pickers' squares), no check, no accent.
    final soft = KuteActionCard.surfaceOf(context)
        .copyWith(borderRadius: BorderRadius.circular(16));
    final ring = picked
        ? Border.all(color: context.ctaFill, width: 1.5)
        : soft.border as Border?;
    final edge = ring?.top.width ?? 0;
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
            // At least its height, taller when its name wraps (see
            // [_TileShape]); a grid's pair stretches it to its neighbour.
            constraints: BoxConstraints(minHeight: _height),
            margin: EdgeInsets.only(
                bottom: shape == _TileShape.wide && !lone ? 12.h : 0),
            padding: EdgeInsets.symmetric(
                horizontal: _insetX - edge, vertical: _insetY - edge),
            // The soft card in both states (its shadow the same, so the
            // chip spring's overshoot never lerps a blur negative); only
            // the ring changes.
            decoration: soft.copyWith(border: ring),
            child: body,
          ),
        ),
      ),
    );
  }
}

/// A tile's name with its stat line under it, the name never cut
/// (founder, 31 October 2026, and 9 November 2026: "no cut text"): the
/// name on one line and the stat under it while the name fits the width;
/// a name that needs more runs onto as many lines as it takes and the stat
/// is dropped, not the name. The card grows with it, its pair too
/// ([_TilePair]; kute_action_cards.dart: titles are never cut, the cards
/// of a row grow together).
class _NameAndStat extends StatelessWidget {
  const _NameAndStat({required this.name, required this.style, this.stat});

  final String name;
  final TextStyle style;
  final Widget? stat;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          // Measured in the style the name is drawn in: the inherited
          // one (the theme's Inter) under the name's own.
          final painter = TextPainter(
            text: TextSpan(
                text: name,
                style: DefaultTextStyle.of(context).style.merge(style)),
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
              Text(name, style: style),
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

  /// How far each logo stands from the one before.
  static const double step = _kLogo * 0.66;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
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
