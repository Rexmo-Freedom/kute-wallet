import 'package:kute/screens/shared/fitted_title.dart';
import 'package:kute/screens/shared/kute_blur.dart';
import 'package:kute/screens/shared/ask_sal_chip.dart';
import 'package:kute/helpers/formatters/polymarket_amount_formatter.dart';
import 'package:kute/helpers/formatters/polymarket_side_labels.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart'
    show polymarketActivePositionsProvider, PolyPriceHistoryCache;
import 'package:kute/providers/polymarket_cost_basis_provider.dart'
    show polymarketPositionCostBasis;
import 'package:kute/providers/polymarket_sports_provider.dart'
    show sportsLiveProvider, SportsMatchUpdate;
import 'package:kute/providers/polymarket_provider.dart'
    show kCryptoPredictAssets, CryptoAssetConfig;
import 'package:kute/screens/polymarket/components/bet_slip_sheet.dart';
import 'package:kute/screens/polymarket/components/market_chart.dart';
import 'package:kute/screens/polymarket/components/poly_chart_history.dart';
import 'package:kute/screens/polymarket/components/poly_market_stats.dart';
import 'package:kute/screens/polymarket/components/price_format.dart';
import 'package:kute/screens/polymarket/components/outcome_leading.dart';
import 'package:kute/screens/polymarket/components/poly_crest_image.dart';
import 'package:kute/screens/polymarket/components/poly_livestream_host.dart';
import 'package:kute/providers/polymarket_game_lines_provider.dart';
import 'package:kute/services/polymarket/crypto_round.dart';
import 'package:kute/screens/polymarket/components/fast_bet_scope.dart';
import 'package:kute/services/polymarket/fast_bet_window.dart';
import 'package:kute/services/polymarket/live_game/game_market_groups.dart';
import 'package:kute/services/polymarket/live_game/game_sides.dart'
    show gameShortSideNames;
import 'package:kute/providers/polymarket_tweet_count_provider.dart';
import 'package:kute/screens/polymarket/components/game_chart_section.dart';
import 'package:kute/screens/polymarket/components/game_header.dart';
import 'package:kute/screens/polymarket/components/exact_score_list.dart';
import 'package:kute/services/polymarket/thin_history.dart';
import 'package:kute/services/polymarket/shown_price.dart';
import 'package:kute/screens/polymarket/components/game_winner_lines.dart';
import 'package:kute/screens/polymarket/components/live_token_scope.dart';
import 'package:kute/screens/polymarket/components/poly_browse_bar.dart'
    show PolyAutoScrollRow;
import 'package:kute/screens/polymarket/components/poly_watch_star.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/screens/shared/kute_motion.dart';
import 'package:kute/screens/polymarket/polymarket_screen.dart'
    show CryptoPredictBanner;

import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/market_pair_button.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/screens/polymarket/components/round_heartbeat.dart';
import 'package:kute/services/haptic_gates.dart';
import 'package:kute/services/kute_haptics.dart';
import 'package:kute/services/venue_analytics.dart';
import 'package:kute/services/tracking_service.dart';

/// `"<Team> vs <Team>"` / `"<Team> vs. <Team>"` inside a sub-market name.
/// Hoisted out of [_MarketDetailSheetState._sideLabelsFor], which runs once
/// per legend row: a 50-market sports event was recompiling this (and the
/// one below) 100 times per rebuild of the list.
final _kNameVersusRegex = RegExp(r'\svs\.?\s', caseSensitive: false);

/// Structured sub-market names (Over/Under, spread, parenthesised line)
/// that must NOT take the two team names as their side labels.
final _kNameStructuredRegex =
    RegExp(r'o\s*/\s*u|over|under|spread|\(', caseSensitive: false);

/// Sub-market grouping regexes for the outcome legend, hoisted for the same
/// reason as the two above.
final _kGroupTotalsRegex = RegExp(r'o\s*/\s*u|over\s*/\s*under|\bover\b');
final _kGroupDigitRegex = RegExp(r'\d');
final _kGroupSpreadRegex = RegExp(r'\([+-]\s*\d');

/// Regex matching 5-min Up/Down crypto market slugs, e.g.
/// `btc-updown-5m-1715250300`. Capture group 1 is the lowercase asset.
final _kFiveMinSlugRegex = RegExp(r'^(\w+)-updown-5m(?:-|$)');

/// Resolves the matching `CryptoAssetConfig` (BTC/ETH/SOL/XRP) for a
/// 5-min event. Inspects the slug first (`btc-updown-5m-...`), then
/// falls back to the title (`BTC Up or Down`) and finally to BTC if
/// nothing matches so the banner always renders something live.
CryptoAssetConfig _resolveCryptoConfig(PolymarketEvent event) {
  String? sym;
  final match = _kFiveMinSlugRegex.firstMatch(event.slug);
  if (match != null) sym = match.group(1)?.toUpperCase();
  sym ??= () {
    final upper = event.title.toUpperCase();
    for (final cfg in kCryptoPredictAssets) {
      if (upper.contains(cfg.asset)) return cfg.asset;
    }
    return null;
  }();
  if (sym != null) {
    for (final cfg in kCryptoPredictAssets) {
      if (cfg.asset == sym) return cfg;
    }
  }
  return kCryptoPredictAssets.first;
}

// Unified Polymarket palette: saturated green/red used across charts,
// legend dots, CTAs and badges so the Predictions surface reads as one
// design system. Was previously a pastel `#47C97A` / `#FF6565` pair
// that looked weak against polymarket.com's saturated reference.
const Color _kPolyGreen = AppColors.marketUp;
const Color _kPolyRed = AppColors.marketDown;
const Color _kPolyPurple = Color(0xFF3B82F6);

// A chance as the whole sheet writes it: the shared rule of
// price_format.dart (one decimal at most, "<1%" / ">99%" at the ends).
String _formatPctShort(double price) => formatPolyChance(price);

String _formatVolume(WidgetRef ref, double value) {
  if (value >= 1e9) {
    return '${formatPolyAmount(ref, value / 1e9, decimalDigits: 1)}B';
  }
  if (value >= 1e6) {
    return '${formatPolyAmount(ref, value / 1e6, decimalDigits: 1)}M';
  }
  if (value >= 1e3) {
    return '${formatPolyAmount(ref, value / 1e3, decimalDigits: 1)}K';
  }
  return formatPolyAmount(ref, value, decimalDigits: 0);
}

String _formatEndsIn(BuildContext context, DateTime? end) {
  if (end == null) return context.l10n.betTbd;
  final diff = end.difference(DateTime.now());
  if (diff.isNegative) return context.l10n.betClosed;
  if (diff.inDays >= 365) {
    final y = (diff.inDays / 365).floor();
    return '${y}y';
  }
  if (diff.inDays >= 30) {
    final m = (diff.inDays / 30).floor();
    return '${m}mo';
  }
  if (diff.inDays >= 1) return '${diff.inDays}d';
  if (diff.inHours >= 1) return '${diff.inHours}h';
  if (diff.inMinutes >= 1) return '${diff.inMinutes}m';
  return context.l10n.betNow;
}

class MarketDetailSheet extends ConsumerStatefulWidget {
  final PolymarketEvent event;
  final VoidCallback? onDeposit;
  final String? ledgerWalletId;

  /// Surface the market was opened from (feed_card | search | hot_events |
  /// group_landing | ledger | ...). Analytics only; carried into the bet
  /// slip so polymarket_bet_placed.entry_source keeps the original entry.
  final String source;

  const MarketDetailSheet({
    super.key,
    required this.event,
    this.onDeposit,
    this.ledgerWalletId,
    this.source = 'unknown',
  });

  static const routeName = 'polymarket-market-detail-sheet';

  static void show(
    BuildContext context, {
    required PolymarketEvent event,
    VoidCallback? onDeposit,
    String? ledgerWalletId,
    String source = 'unknown',
  }) {
    // Single market-view event (consolidated). Enriched with category +
    // liquidity bucket + outcome-count bucket so the predictions funnel
    // and cohort dashboards can split market traffic by vertical and
    // depth — previously this was a second raw `prediction_market_viewed`
    // event firing alongside the bare one, splitting the metric.
    VenueAnalytics.rememberPolymarketEvent(event);
    TrackingService.polymarketViewed(
      marketId: event.id,
      category: event.category,
      liquidityUsd: event.liquidity,
      outcomeCount: event.outcomes.length,
      source: source,
      eventSlug: event.slug,
      // One outcome opened as its own screen is titled by the outcome:
      // the parent event's title is the one on record for it.
      eventTitle: event.isSyntheticBinary ? null : event.title,
      extra: {
        'entry_source': source,
        'wallet_kind': ledgerWalletId == null ? 'hot' : 'ledger',
      },
    );
    // Drop the active focus before we push the detail route. The
    // predictions search field stays focused when the route pushes,
    // so when the user closes the detail sheet the keyboard
    // immediately re-opens for the still-focused TextField — reads
    // as "the search is strange after tapping an event". Explicitly
    // unfocusing here means the field is dormant when the user
    // returns; they re-tap if they want to keep searching.
    FocusManager.instance.primaryFocus?.unfocus();
    // 5-min Up/Down crypto markets get a dedicated detail sheet that
    // reuses the same `CryptoPredictBanner` rendered on the list, so
    // the user lands on the same live price + countdown + Up/Down
    // CTAs they tapped — not the generic binary detail UI. That sheet
    // draws the five-minute round in play of the app's own assets and
    // nothing else, so every other Up/Down market (15 minutes, an hour,
    // four hours, a day, another asset) opens below as the market it is.
    if (polyOpensRoundSheet(
        event.slug, [for (final c in kCryptoPredictAssets) c.asset])) {
      FiveMinMarketDetailSheet.show(
        context,
        event: event,
        onDeposit: onDeposit,
        ledgerWalletId: ledgerWalletId,
      );
      return;
    }
    _prefetchChart(event);
    // Skip the slide-up transition entirely when the OS asks to reduce
    // motion (the route still appears, just without the animated slide).
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        settings: const RouteSettings(name: routeName),
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.4),
        fullscreenDialog: true,
        transitionDuration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 300),
        reverseTransitionDuration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 300),
        pageBuilder: (_, __, ___) => FastBetScope(
          active: ledgerWalletId == null && polyIsFastBetRound(event.slug),
          child: MarketDetailSheet(
            event: event,
            onDeposit: onDeposit,
            ledgerWalletId: ledgerWalletId,
            source: source,
          ),
        ),
        transitionsBuilder: (_, animation, __, child) {
          return SlideTransition(
            position: animation.drive(
              Tween(begin: const Offset(0, 1), end: Offset.zero)
                  .chain(CurveTween(curve: Curves.easeOutCubic)),
            ),
            child: child,
          );
        },
      ),
    );
  }

  /// Starts the history read of the chart [event]'s sheet opens on, for a
  /// card a finger has just come down on (before the tap is known): the
  /// read the sheet makes anyway, started up to a press-timeout earlier.
  /// Nothing for a five-minute round, whose sheet has its own chart.
  static void prefetch(PolymarketEvent event) {
    if (polyOpensRoundSheet(
        event.slug, [for (final c in kCryptoPredictAssets) c.asset])) {
      return;
    }
    _prefetchChart(event);
  }

  /// Starts the chart's history read for the lines the sheet will draw
  /// (the Yes line of a binary market, else the leading outcomes), so it
  /// overlaps the slide-in. See [MarketChart.prefetch].
  static void _prefetchChart(PolymarketEvent event) {
    final List<String?> tokens;
    DateTime? gameStart;
    if (event.isBinary) {
      tokens = [event.yesTokenId];
    } else if (event.outcomes.length > 3 &&
        (event.gameId != null || event.metadataGameId != null)) {
      // A game with many markets charts its winner market (never its most
      // likely markets), laid out from the event the card already has.
      tokens = [
        for (final line in polyGameWinnerLines(
          event: event,
          sportsTeams: polySportsTeams(event, const []),
          lines: PolyGameLines.fromEvent(event),
          drawLabel: '',
        ))
          line.tokenId
      ];
      // A game in play opens on the range that holds it.
      if (event.isInPlay) gameStart = event.gameStart ?? event.kickoff;
    } else {
      final sorted = [...event.outcomes]
        ..sort((a, b) => b.price.compareTo(a.price));
      tokens = [
        for (final o in sorted)
          if (o.tokenId != null && o.tokenId!.isNotEmpty) o.tokenId
      ];
    }
    final end = event.endDate;
    if (tokens.isEmpty) return;
    // A young market is read straight at a grain that can draw it.
    final opened = polyChartOpenedAt(event);
    for (final t in tokens) {
      if (t != null) PolyPriceHistoryCache.noteOpened(t, opened);
    }
    MarketChart.prefetch(
      tokens,
      gameStart: gameStart,
      inPlay: event.isInPlay,
      openedAt: opened,
      shortMarket: RegExp(r'-(5|15)m-').hasMatch(event.slug),
      resolved: event.closed ||
          !event.active ||
          event.ended ||
          (end != null && end.isBefore(DateTime.now())),
    );
  }

  @override
  ConsumerState<MarketDetailSheet> createState() => _MarketDetailSheetState();
}

class _MarketDetailSheetState extends ConsumerState<MarketDetailSheet>
    with PolyLivestreamHost<MarketDetailSheet> {
  // Market (chart) vs Livestream: [PolyLivestreamHost], only relevant when
  // the event has a watchable Twitch/YouTube broadcast
  // (`event.hasLivestream`).
  @override
  PolymarketEvent get streamEvent => event;
  @override
  String get streamEntrySource => widget.source;
  @override
  String get streamSurface => 'market_detail';

  /// Team crests lazily fetched by slug when the event arrived without them
  /// (search-opened events lose `teams`). Populated in [build].
  List<PolymarketTeam> _fetchedTeams = const [];

  /// Fits one screen above the sticky outcome bar and Buy buttons on a
  /// standard iPhone.
  static const double _chartHeight = 380;

  PolymarketEvent get event => widget.event;

  List<String> _subscribedTokenIds = [];

  /// Live-feed hold — the sheet can open OUTSIDE the Predictions tab
  /// (global search, deep links) where the shell has the CLOB stream
  /// paused; acquire()/release() keeps it live while up.
  LivePriceNotifier? _livePrices;

  @override
  void initState() {
    super.initState();
    // acquire() BEFORE addTokens so the tokens subscribe on the revived
    // socket; paired release() in dispose.
    _livePrices = ref.read(livePriceProvider.notifier);
    _livePrices!.acquire();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _subscribedTokenIds = event.outcomes
          .where((o) => o.tokenId != null && o.tokenId!.isNotEmpty)
          .map((o) => o.tokenId!)
          .toList();
      if (_subscribedTokenIds.isNotEmpty) {
        _livePrices?.addTokens(_subscribedTokenIds);
      }
      _listenForOddsTicks();
      // A match's sheet keeps the live score feed open (it may be opened
      // from search or a deep link, where nothing else joined it).
      if (!event.isSyntheticBinary &&
          (event.gameId != null || event.metadataGameId != null)) {
        ref.read(sportsLiveProvider.notifier).connect();
      }
    });
  }

  /// Odds ticks: the lightest haptic when the live price of the market on
  /// this sheet moves a point, at most one a second ([OddsTickGate]).
  /// Only here, on the open sheet; lists never tick. The market it
  /// follows is Yes on a binary market, else the favourite as the sheet
  /// opened.
  final OddsTickGate _oddsTicks = OddsTickGate();

  void _listenForOddsTicks() {
    final PolymarketOutcome? watched;
    if (event.isBinary) {
      watched = event.outcomes
          .where((o) => o.name.toLowerCase() == 'yes')
          .firstOrNull;
    } else {
      PolymarketOutcome? top;
      for (final o in event.outcomes) {
        if (o.tokenId == null || o.tokenId!.isEmpty) continue;
        if (top == null || o.price > top.price) top = o;
      }
      watched = top;
    }
    final token = watched?.tokenId;
    if (token == null || token.isEmpty) return;
    ref.listenManual<double?>(
      livePriceProvider.select((s) => s.prices[token]),
      (_, price) {
        if (price == null || !mounted) return;
        if (_oddsTicks.onPrice(price, DateTime.now().millisecondsSinceEpoch)) {
          KuteHaptics.play(KuteHaptic.oddsTick);
        }
      },
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    // Release the live-feed hold exactly once (nulled to guard a double
    // dispose from decrementing another surface's hold).
    _livePrices?.release();
    _livePrices = null;
    _subscribedTokenIds = [];
    super.dispose();
  }

  /// Resolves the freshest known price for [tokenId]: live WebSocket
  /// price if we've received any tick, otherwise the static price
  /// from the event payload. Lets the hero number, the split bar, and
  /// the sticky CTA cents all tick up/down with the order book in
  /// real time without waiting for a swipe-refresh.
  /// [ref] is the ref of the SMALLEST widget that shows this number — a
  /// leaf Consumer, not the sheet — so a tick repaints that number alone.
  /// `select` narrows further: only a real change to THIS token's price
  /// counts, not every LivePriceState emission (the notifier also republishes
  /// `updatedAtMs` for every other subscribed token on the feed).
  /// Use this only where the number of tokens is BOUNDED (the Yes/No pair,
  /// the chart's handful of lines). Each call opens its own selector
  /// subscription, so the per-outcome paths read [_livePriceMap] once and
  /// index it with [_priceOf] instead.
  /// A list row's name without the event's fixture in front of it
  /// ([polyStripEventPrefix]): the header already names the teams.
  String _rowName(PolymarketOutcome o) =>
      polyStripEventPrefix(o.name, event.title);

  /// The chance a list row shows for [o] ([polyShownChanceOf]): null when
  /// its book is wider than 10¢ and has never traded ("—").
  double? _shownChanceFor(WidgetRef ref, PolymarketOutcome o) {
    final token = o.tokenId ?? '';
    final live = ref.watch(livePriceProvider.select(
        (s) => (s.prices[token], s.unpriced.contains(token))));
    return polyShownChanceOf({if (live.$1 != null) token: live.$1!},
        {if (live.$2) token}, o);
  }

  double _livePriceFor(WidgetRef ref, String? tokenId, double fallback) {
    if (tokenId == null || tokenId.isEmpty) return fallback;
    final live = ref.watch(livePriceProvider.select((s) => s.prices[tokenId]));
    return live ?? fallback;
  }

  /// The whole live-price map, watched ONCE per consumer build — for the
  /// paths that need every outcome's price (the bettable filter, the leader
  /// and winner sorts). Those call sites are O(n), and the sorts O(n log n),
  /// so reaching for [_livePriceFor] there would open a subscription per
  /// comparison.
  Map<String, double> _livePriceMap(WidgetRef ref) =>
      ref.watch(livePriceProvider.select((s) => s.prices));

  double _priceOf(
      Map<String, double> prices, String? tokenId, double fallback) {
    if (tokenId == null || tokenId.isEmpty) return fallback;
    return prices[tokenId] ?? fallback;
  }

  double _liveYesPrice(WidgetRef ref) {
    if (event.isBinary) {
      final yes = event.outcomes
          .where((o) => o.name.toLowerCase() == 'yes')
          .firstOrNull;
      return _livePriceFor(ref, yes?.tokenId, event.yesPrice);
    }
    return event.yesPrice;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Honour the OS "Reduce Motion" setting: gate decorative/transition
    // animations (chart resize, expander cross-fades, chevron rotations,
    // toggle slide) on it. Essential motion (chart price updates, loading
    // spinners, live LIVE chip) stays untouched.
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    // Backfill team crests for events that arrived without them (the search
    // path drops `teams`) so the vs-header logos work everywhere, not just on
    // browse-opened events. Gate on `gameId != null` (an actual match) so
    // opening a crypto/politics/binary market doesn't fire a `fetchEventTeams`
    // HTTP call that can never produce teams — mirrors the card path.
    _fetchedTeams = polyFetchedTeams(ref, event);
    final watching = watchingStream;
    // While another route (the bet slip, an outcome's own sheet) covers
    // this one, the stream plays on in the mini player; it comes back here
    // when this sheet is on top again.
    // A sheet being closed is no longer active: its stream stops with it.
    syncStreamHandoff(context);
    return Scaffold(
      backgroundColor: context.isDark
          ? context.colors.gradientBottom
          : context.colors.background,
      resizeToAvoidBottomInset: false,
      body: Container(
        decoration: AppDecorations.screenGradient(context),
        child: PlatformSafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.max,
            children: [
              _buildHeader(c),
              Expanded(
                // Slivers, so a long outcome list ("More markets" of a game
                // with 300 markets) builds only the rows in view.
                child: CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(20.w, 4.h, 20.w, 0),
                      sliver: SliverMainAxisGroup(slivers: [
                        SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Watch and bet: the stream at the top, then the
                              // market; the Buy buttons stay at the bottom.
                              if (watching) ...[
                                buildMediaToggle(c),
                                SizedBox(height: 14.h),
                                buildWatchPlayer(c),
                                SizedBox(height: 18.h),
                              ],
                              _buildHeroCard(c),
                              SizedBox(height: 20.h),
                              if (event.hasLivestream && !watching) ...[
                                buildMediaToggle(c),
                                SizedBox(height: 14.h),
                              ],
                              if (!watching)
                                // The chart gets its OWN Consumer. It reads
                                // the CLOB trade stream and the live-price
                                // pin, both of which tick several times a
                                // second; watching them from the sheet's
                                // build() rebuilt the whole 2.8k-line
                                // subtree on every tick, which is what made
                                // scrolling stutter. Now a tick rebuilds the
                                // chart and nothing else.
                                Consumer(builder: (context, chartRef, _) {
                                  final chartWidget = _buildChartBody(chartRef);
                                  if (chartWidget == null) {
                                    return const SizedBox.shrink();
                                  }
                                  return Padding(
                                    padding: EdgeInsets.only(bottom: 8.h),
                                    child: AnimatedSize(
                                      duration: reduceMotion
                                          ? Duration.zero
                                          : const Duration(milliseconds: 240),
                                      curve: Curves.easeOutCubic,
                                      alignment: Alignment.topCenter,
                                      // A match adds its event markers to the
                                      // chart and its momentum strip under it.
                                      child: _gameChartSection(chartWidget),
                                    ),
                                  );
                                }),
                              // Count markets: the running tally, refreshed
                              // while open.
                              if (event.tweetCount != null)
                                Consumer(
                                  builder: (context, countRef, _) =>
                                      _buildTweetCounter(countRef, c),
                                ),
                            ],
                          ),
                        ),
                        // Own Consumer, returning slivers: it rebuilds when
                        // the order of the outcomes changes; a price tick
                        // repaints the one row (or board button) it moved.
                        // A game shows its main lines as a board and the
                        // rest of its markets under "More markets"; any
                        // other event with many outcomes keeps the one
                        // outcome list. A Yes/No market has neither: its two
                        // buttons below carry both chances.
                        if (!event.isBinary)
                          Consumer(
                            builder: (context, priceRef, _) => _showsGameLines
                                ? _buildGameMarkets(priceRef, c)
                                : _buildMultiOutcomeList(priceRef, c),
                          ),
                        SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(height: event.isBinary ? 12.h : 24.h),
                              _buildRulesRow(),
                              SizedBox(height: 24.h),
                            ],
                          ),
                        ),
                      ]),
                    ),
                  ],
                ),
              ),
              _buildStickyActions(c),
            ],
          ),
        ),
      ),
    );
  }

  /// Sal's grounding: this public event and, when every outcome is one
  /// market, that market.
  AdvisorContext get _salContext => AdvisorContext(
      surface: 'polymarket_market_detail',
      marketVenue: 'polymarket',
      marketId: event.slug,
      submarketId:
          event.outcomes.map((o) => o.gammaMarketId).toSet().length == 1
              ? event.outcomes.firstOrNull?.gammaMarketId
              : null);

  /// Close, the event's image and title (up to two lines), and the
  /// watchlist star. Sal's door is the question capsule under the hero.
  Widget _buildHeader(AppColorsExtension c) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 4.h),
      child: Row(
        children: [
          const KuteCloseButton(),
          SizedBox(width: 8.w),
          // The SAME resolver the cards use (team crest for a gaming /
          // esports "vs" market the sports detector didn't catch, the
          // leading candidate's portrait for a multi-outcome event, else
          // the event image), SVG-aware so `.svg` crests load; the size of
          // the Investing header's logo.
          Builder(builder: (_) {
            final iconUrl = event.displayIconUrl;
            if (iconUrl == null || iconUrl.isEmpty) {
              return _buildFallbackIcon(c, 32.w);
            }
            return PolyCrestImage(
              url: iconUrl,
              size: 32.w,
              radius: 8.w,
              fallback: _buildFallbackIcon(c, 32.w),
            );
          }),
          SizedBox(width: 8.w),
          Expanded(
            // The whole title: smaller rather than cut.
            child: FittedTitle(
              event.title,
              key: const ValueKey('poly-detail-title'),
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 18.sp,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                height: 1.2,
              ),
            ),
          ),
          SizedBox(width: 8.w),
          PolyWatchStar(event: event, size: 22, source: 'detail'),
        ],
      ),
    );
  }

  /// Resolves the live (or fallback) price for every outcome in the
  /// event. Used by the hero-card heuristics below so "Leading X%" /
  /// "Resolved" / "Awaiting liquidity" decisions all see the freshest
  /// prices, not just the static payload.
  List<double> _liveOutcomePrices(WidgetRef ref) {
    final prices = _livePriceMap(ref);
    return event.outcomes
        .map((o) => _priceOf(prices, o.tokenId, o.price))
        .toList();
  }

  /// STATUS-based "resolved" determination — mirrors the card's `_isResolved`
  /// (closed / not-active / ended / past endDate). A live market (closed:false,
  /// future endDate) must NEVER read as resolved, even when one outcome sits at
  /// ~99% and the rest near ~0 — a lopsided price is a heavy favourite, not a
  /// settled market. This killed the img64 bug where "Fed Decision in June?"
  /// ("Ends in 1d", not closed) wrongly showed a green "Resolved · No change".
  /// No price threshold is consulted here — the old `p >= 0.97 || p <= 0.03`
  /// heuristic is gone.
  bool get _isResolvedByStatus {
    if (event.closed) return true;
    if (!event.active) return true;
    if (event.ended) return true;
    final end = event.endDate;
    if (end != null && end.isBefore(DateTime.now())) return true;
    return false;
  }

  /// [_isResolvedByStatus] for the chart and the Stats, which a game still
  /// being played must not read as over ([polyEventIsOver], [polyGameIsLive]).
  bool _isOverFor(WidgetRef ref) {
    return polyEventIsOver(event, inPlay: _isGameLive(_liveMatchUpdate(ref)));
  }

  /// Multi-outcome event that has settled — used to swap the "Leading X%" hero
  /// for a neutral "Resolved · {winner}" pill. Now STATUS-based (see
  /// [_isResolvedByStatus]) rather than inferred from an extreme price. The
  /// live-in-play guard stays: a sports match that's live / hasn't actually
  /// ended is never "resolved" even if its endDate slipped past (injury time,
  /// OT, delayed kickoff).
  bool _allOutcomesResolvedFor(WidgetRef ref) {
    if (event.isBinary || event.outcomes.isEmpty) return false;
    if (_isSportsMatchEvent && !_sportsGameEndedFor(ref)) return false;
    return _isResolvedByStatus;
  }

  /// True when this detail is a sports matchup (has a parsed "Team vs Team"
  /// header). Used to suppress the price-based "resolved" inference for games
  /// that are still in play.
  bool get _isSportsMatchEvent => _detectSportsTeams() != null;

  /// Whether a sports game has actually finished — the explicit Gamma `ended`
  /// flag, or the live WS update reporting `ended`. A past endDate or an
  /// extreme price is NOT treated as ended.
  bool _sportsGameEndedFor(WidgetRef ref) {
    if (event.ended) return true;
    final ws = _liveMatchUpdate(ref);
    return ws?.ended ?? false;
  }

  /// Every outcome sits at exactly 0.5 — Polymarket's stub value when
  /// a sub-market has no liquidity. Surfacing "Leading 50%" pretends
  /// there's a leader when there's none.
  bool _allOutcomesStubFor(WidgetRef ref) {
    if (event.isBinary || event.outcomes.isEmpty) return false;
    final prices = _liveOutcomePrices(ref);
    return prices.every((p) => (p - 0.5).abs() < 0.001);
  }

  /// Large multi-outcome events (LoL with Game-2-Winner +
  /// Game-3-Winner + O/U 3.5 Games + Total Kills Over/Under + …)
  /// regularly hit 50-100 sub-markets. Picking any single one as
  /// "leading" is meaningless — surface the market count instead.
  bool get _isLargeMultiOutcome {
    if (event.isBinary) return false;
    return event.outcomes.length > 20;
  }

  /// The live WS update for this match, looked up by event slug first, then
  /// by the stable numeric gameId join (`game:<id>`), then cricket's
  /// `eventMetadata.gameId` (`meta:<id>`). Null when nothing is live.
  SportsMatchUpdate? _liveMatchUpdate(WidgetRef ref) =>
      polyLiveMatchUpdate(ref, event);

  /// A game that is currently in play. True when the live WS update says
  /// `live` (and not `ended`), OR — before any WS tick — when Gamma seeded a
  /// score/period on the event and it hasn't ended. Never true once ended.
  bool _isGameLive(SportsMatchUpdate? ws) => polyGameIsLive(event, ws);

  /// Returns the two team names + their per-team images when the
  /// event looks like a sports matchup, else null. Detection: the
  /// event is in the sports category AND the title contains a "vs"
  /// or "vs." separator. The team images are pulled from the first
  /// two outcomes' `imageUrl` (which Gamma serves as the per-team
  /// logo via `groupItemImage`). If outcome images are missing we
  /// still render the layout — the team initial circle takes over.
  ///
  /// Title parsing handles the common Polymarket shapes:
  ///   "NBA: Lakers vs Warriors" -> ("Lakers", "Warriors")
  ///   "Counter-Strike: Team Falcons vs Legacy (BO5) - CS Asia Championships Playoffs"
  ///       -> ("Team Falcons", "Legacy")
  ///   "MLB: Dodgers vs. Padres" -> ("Dodgers", "Padres")
  ///   "Real Madrid vs Barcelona" -> ("Real Madrid", "Barcelona")
  ///
  /// Memoised. The detection compiles half a dozen regexes and scans the
  /// team lists, and it is reached once per legend ROW through
  /// [_sideLabelsFor] — on a 50-market sports event that ran 50+ times per
  /// rebuild of the list. Everything it reads is immutable for the life of
  /// the sheet except [_fetchedTeams], which is therefore the whole key.
  ({String teamA, String teamB, String? imageA, String? imageB})?
      _detectSportsTeams() {
    if (!identical(_teamsMemoKey, _fetchedTeams)) {
      _teamsMemoKey = _fetchedTeams;
      _teamsMemo = _computeSportsTeams();
      _sideLabelMemo.clear();
    }
    return _teamsMemo;
  }

  ({String teamA, String teamB, String? imageA, String? imageB})? _teamsMemo;
  List<PolymarketTeam>? _teamsMemoKey;

  /// Memo for [_sideLabelsFor], keyed by sub-market name. Cleared alongside
  /// [_teamsMemo] because the labels can come from the detected teams.
  final Map<String, ({String pos, String neg})> _sideLabelMemo = {};

  ({String teamA, String teamB, String? imageA, String? imageB})?
      _computeSportsTeams() => polySportsTeams(event, _fetchedTeams);

  /// The current tally of a count market, from the event and then Gamma's
  /// tally read every 30 s while the sheet is open.
  int? _currentTweetCount(WidgetRef ref) {
    if (event.tweetCount == null) return null;
    final live = ref.watch(polyTweetCountProvider(event.id)).valueOrNull;
    return live ?? event.tweetCount;
  }

  /// A count market's running tally ("168 so far"), refreshed in the app
  /// while the sheet is open. There is no push; a failed refresh keeps the
  /// last count.
  Widget _buildTweetCounter(WidgetRef ref, AppColorsExtension c) {
    final count = _currentTweetCount(ref);
    if (count == null) return const SizedBox.shrink();
    final end = event.endDate;
    return Container(
      margin: EdgeInsets.only(bottom: 16.h),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: c.borderSubtle, width: 0.5),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.polyCountSoFar,
                  style: TextStyle(
                    color: c.textTertiary,
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 2.h),
                RollingNumberText(
                  text: '$count',
                  duration: MediaQuery.of(context).disableAnimations
                      ? Duration.zero
                      : const Duration(milliseconds: 250),
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 26.sp,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    height: 1.0,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          if (end != null && end.isAfter(DateTime.now()))
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  context.l10n.betEndsIn,
                  style: TextStyle(
                    color: c.textTertiary,
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  _formatEndsIn(context, end),
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// Matches (a team-vs-team event with a game id) get the main-lines
  /// board.
  bool get _showsGameLines =>
      !event.isSyntheticBinary &&
      event.gameId != null &&
      _detectSportsTeams() != null;

  /// The kind of market "More markets" is narrowed to ('all' for none).
  String _marketGroup = 'all';

  /// A game's markets the way a sportsbook lays them out: the main lines
  /// on top as a board (Winner, Spread, Total; each side a button that
  /// opens the bet slip on it), then every OTHER market under "More
  /// markets", by kind. A market on the board is never listed again.
  /// Falls back to the plain outcome list when the game has no main line.
  Widget _buildGameMarkets(WidgetRef ref, AppColorsExtension c) {
    final l10n = context.l10n;
    final lines = polyGameLinesFor(ref, event);
    final teams = event.teams.isNotEmpty ? event.teams : _fetchedTeams;
    final onBoard = <String>{};
    void take(String? id) {
      if (id != null && id.isNotEmpty) onBoard.add(id);
    }

    bool yesNo(String a, String b) =>
        a.toLowerCase() == 'yes' && b.toLowerCase() == 'no';
    void tapped(String kind) =>
        TrackingService.track('live_game_line_tapped', params: {
          'line_kind': kind,
          if (event.category.isNotEmpty)
            'category': event.category.toLowerCase(),
        });

    // Each button follows its own token(s) on the live feed: a tick
    // repaints that button alone, never the board or the list under it.
    Widget button({
      required String label,
      required double Function(WidgetRef ref) price,
      required Color accent,
      Color? lineColor,
      String? crest,
      required VoidCallback onTap,
    }) =>
        Expanded(
          child: Consumer(
            builder: (context, priceRef, _) => _WdlOutcomeButton(
              label: label,
              crestUrl: crest,
              pctText: _formatPctShort(price(priceRef)),
              accent: accent,
              lineColor: lineColor,
              onTap: onTap,
            ),
          ),
        );

    // The colour of each line the chart above draws, by token: a button
    // on one of those outcomes is a slab of its line's colour, and the
    // slip opened from it wears that colour too.
    final lineColors = {
      for (final line in _gameWinnerLines(ref)) line.tokenId: line.color,
    };

    final rows = <({String label, List<Widget> buttons})>[];
    // Winner: the three-way row of a football match, else the moneyline,
    // else a two-sided event's own pair.
    final wdl = _detectWDLOutcomes();
    final moneyline = lines.moneyline != null &&
            !yesNo(lines.moneyline!.sideA, lines.moneyline!.sideB)
        ? lines.moneyline
        : null;
    final own = event.outcomes.length == 2 &&
            !yesNo(event.outcomes[0].name, event.outcomes[1].name) &&
            !event.outcomes.any((o) => o.hasYesNo)
        ? event.outcomes
        : null;
    // One colour per team on the whole sheet: the chart's line for the
    // side, as the momentum graph uses it. Never green and red for a
    // team's figure (those read as up and down).
    final winnerNames = wdl != null
        ? (wdl.teamAName, wdl.teamBName)
        : moneyline != null
            ? (moneyline.sideA, moneyline.sideB)
            : own != null
                ? (own[0].name, own[1].name)
                : null;
    final sideColors =
        gameSideColors(event.title, winnerNames?.$1, winnerNames?.$2);
    // A team's line colour, null for a side that is not a team.
    Color? teamLine(String name) {
      final n = name.trim().toLowerCase();
      if (winnerNames != null) {
        if (n == winnerNames.$1.trim().toLowerCase()) return sideColors.$1;
        if (n == winnerNames.$2.trim().toLowerCase()) return sideColors.$2;
      }
      return null;
    }

    Color teamColor(String name) => teamLine(name) ?? c.textPrimary;

    /// One two-sided line as a row of two buttons.
    List<Widget> pair(PolyGameLine r, {required bool teamSides}) {
      take(r.gammaMarketId);
      take(r.tokenA);
      take(r.tokenB);
      // [short] is the board's own label: a spread names its team by the
      // abbreviation ("SD -1.5"), so the name and its line stay on one
      // line beside the crest. The bet slip keeps the whole name.
      String sideLabel(bool a, {bool short = false}) {
        final name = a ? r.sideA : r.sideB;
        if (r.kind == 'moneyline' || r.line == null) return name;
        if (r.kind == 'totals') return '$name ${r.lineText}';
        // The market's line belongs to its first side.
        final l = a ? r.line! : -r.line!;
        final t = l == l.roundToDouble() ? l.toStringAsFixed(0) : '$l';
        final abbr = short ? _teamAbbreviation(name)?.trim() : null;
        final team =
            abbr == null || abbr.isEmpty ? name : abbr.toUpperCase();
        return '$team ${l > 0 ? '+$t' : t}';
      }

      double sidePrice(WidgetRef priceRef, bool a) {
        final live = priceRef.watch(livePriceProvider.select((s) => (
              r.tokenA != null ? s.prices[r.tokenA] : null,
              r.tokenB != null ? s.prices[r.tokenB] : null,
            )));
        final priceA = live.$1 ?? r.priceA;
        if (a) return priceA;
        return live.$2 ??
            (live.$1 != null ? (1 - priceA).clamp(0.0, 1.0) : r.priceB);
      }

      // The side's line on the chart (a charted spread or total), else
      // its team's line; an Over or Under the chart does not draw has
      // none and stays a neutral card.
      Color? sideLine(bool a) =>
          lineColors[a ? r.tokenA : r.tokenB] ??
          (teamSides ? teamLine(a ? r.sideA : r.sideB) : null);
      Widget side(bool a) => button(
            label: sideLabel(a, short: teamSides),
            price: (priceRef) => sidePrice(priceRef, a),
            accent: teamSides
                ? teamColor(a ? r.sideA : r.sideB)
                : c.textPrimary,
            lineColor: sideLine(a),
            crest: teamSides
                ? PolymarketEvent.logoFromTeams(teams, a ? r.sideA : r.sideB)
                : null,
            onTap: () {
              tapped(r.kind);
              _openLineBetSlip(r.toOutcome(),
                  second: !a,
                  pos: sideLabel(true),
                  neg: sideLabel(false),
                  colors: [sideLine(true), sideLine(false)]);
            },
          );
      return [side(true), SizedBox(width: 8.w), side(false)];
    }

    if (wdl != null) {
      // Each team by its short name, never the same as the other's
      // ("Leeds" / "Man Utd"): the chart's tags and the slip's sides
      // read the same.
      final names = gameShortSideNames(wdl.teamAName, wdl.teamBName,
          teams: teams);
      Widget way(PolymarketOutcome o, String label, Color accent, int index,
          {String? crestOf}) {
        take(o.gammaMarketId);
        take(o.tokenId);
        final line = lineColors[o.tokenId];
        return button(
          label: label,
          price: (priceRef) => _livePriceFor(priceRef, o.tokenId, o.price),
          accent: accent,
          lineColor: line,
          crest: crestOf != null
              ? PolymarketEvent.logoFromTeams(teams, crestOf)
              : null,
          onTap: () {
            tapped('moneyline');
            // The slip of the whole match: its three sides, opened on
            // this one, each in its line's colour.
            _openThreeWaySlip(wdl, index, lineColors: lineColors);
          },
        );
      }

      rows.add((
        label: l10n.polyGameMoneyline,
        buttons: [
          way(wdl.teamA, names.$1, sideColors.$1, 0, crestOf: wdl.teamAName),
          SizedBox(width: 8.w),
          way(wdl.draw, l10n.betDraw, c.textPrimary, 1),
          SizedBox(width: 8.w),
          way(wdl.teamB, names.$2, sideColors.$2, 2, crestOf: wdl.teamBName),
        ],
      ));
    } else if (moneyline != null) {
      rows.add((
        label: l10n.polyGameMoneyline,
        buttons: pair(moneyline, teamSides: true),
      ));
    } else if (own != null) {
      Widget way(PolymarketOutcome o, Color accent) {
        take(o.tokenId);
        return button(
          label: o.name,
          price: (priceRef) => _livePriceFor(priceRef, o.tokenId, o.price),
          accent: accent,
          lineColor: lineColors[o.tokenId] ?? accent,
          crest: PolymarketEvent.logoFromTeams(teams, o.name) ?? o.imageUrl,
          onTap: () {
            tapped('moneyline');
            _openBetSlip(o.name.toLowerCase(), lineColors: {
              for (final (i, side) in own.indexed)
                if (side.tokenId != null)
                  side.tokenId!: lineColors[side.tokenId] ??
                      (i == 0 ? sideColors.$1 : sideColors.$2),
            });
          },
        );
      }

      rows.add((
        label: l10n.polyGameMoneyline,
        buttons: [
          way(own[0], sideColors.$1),
          SizedBox(width: 8.w),
          way(own[1], sideColors.$2),
        ],
      ));
    }
    final spread = lines.spread;
    if (spread != null && !yesNo(spread.sideA, spread.sideB)) {
      rows.add((
        label: l10n.polyGameSpread,
        buttons: pair(spread, teamSides: true),
      ));
    }
    final total = lines.total;
    if (total != null && !yesNo(total.sideA, total.sideB)) {
      rows.add((
        label: l10n.polyGameTotal,
        buttons: pair(total, teamSides: false),
      ));
    }
    if (rows.isEmpty) return _buildMultiOutcomeList(ref, c);

    // Everything the board does not show, most likely first. Watched as
    // an order: a tick that moves no market past another rebuilds nothing
    // here (each row follows its own price).
    final rest = _listOrderWatched(ref,
        skip: (o) =>
            onBoard.contains(o.gammaMarketId) || onBoard.contains(o.tokenId));
    final groups = [
      for (final g in GameMarketGroup.values)
        if (rest.any((o) => gameMarketGroupOf(o.name) == g)) g.key
    ];
    // A handful of markets needs no filter.
    final filterable = groups.length > 1 && rest.length > 8;
    final picked = filterable && groups.contains(_marketGroup)
        ? _marketGroup
        : 'all';
    final keys = ['all', ...groups];

    final head = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The sheet's own gap between sections (as before "Details").
        SizedBox(height: 24.h),
        LiveTokenScope(
          tokens: [
            for (final r in lines.rows) ...[
              if (r.tokenA != null) r.tokenA!,
              if (r.tokenB != null) r.tokenB!,
            ],
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                Padding(
                  // The list's group headings, to the letter.
                  padding: EdgeInsets.only(
                      top: i == 0 ? 0 : 16.h, bottom: 6.h, left: 4.w),
                  child: Text(
                    rows[i].label.toUpperCase(),
                    style: TextStyle(
                      color: c.textTertiary,
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Row(children: rows[i].buttons),
              ],
            ],
          ),
        ),
        // While the game is on, orders wait before they reach the book:
        // said once, under the board.
        _buildInPlayDelayNote(c),
        if (rest.isNotEmpty) ...[
          SizedBox(height: 24.h),
          Text(
            l10n.polyMoreMarkets,
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 17.sp,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          if (filterable) ...[
            SizedBox(height: 10.h),
            PolyAutoScrollRow(
              height: 34.h,
              padding: 0,
              itemCount: keys.length,
              selectedIndex: keys.indexOf(picked),
              itemBuilder: (context, i) => KutePill(
                label: keys[i] == 'all'
                    ? l10n.polySubAll
                    : gameMarketGroupLabel(l10n, keys[i]),
                selected: keys[i] == picked,
                onTap: () {
                  if (keys[i] == picked) return;
                  HapticFeedback.selectionClick();
                  TrackingService.track('category_pill_tapped', params: {
                    'section': 'game_markets',
                    'subcategory': keys[i],
                  });
                  setState(() => _marketGroup = keys[i]);
                },
              ),
            ),
          ],
          SizedBox(height: 10.h),
        ],
      ],
    );
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(child: head),
        if (rest.isNotEmpty)
          // A filter pill fades the list in; a price tick never does. The
          // rows are built as they scroll into view.
          SliverSelectionFade(
            selection: picked,
            slivers: [
              _ExpandableOutcomeLegend(
                outcomes: rest,
                livePriceFor: _shownChanceFor,
                nameFor: _rowName,
                sideLabelsFor: _sideLabelsFor,
                onPickOutcome: _openCandidateDetail,
                // A game's sub-markets all carry the league's logo: no
                // icon.
                showThumbs: false,
                calmFigures: true,
                gameGroups: true,
                onlyGroup: picked == 'all' ? null : picked,
                collapseAfter: picked == 'all' && filterable ? 4 : null,
              ),
            ],
          ),
      ],
    );
  }

  /// The bet slip on one side of [market], a two-sided market of this
  /// event: its first side, or with [second] its other one. [pos] and
  /// [neg] name the sides on the slip ("49ers -3.5" / "Broncos +3.5").
  /// The same call the feed card makes for one candidate of an event.
  /// [colors] are the two sides' line colours (either may be null): the
  /// slip wears the picked side's.
  void _openLineBetSlip(PolymarketOutcome market,
      {required bool second,
      String? pos,
      String? neg,
      List<Color?> colors = const []}) {
    if (!market.hasYesNo) {
      _openCandidateDetail(market);
      return;
    }
    openingBetSlip = true;
    final yes = market.price.clamp(0.0, 1.0);
    BetSlipSheet.show(
      context,
      negRisk: event.negRisk,
      marketSlug: event.slug,
      event: event,
      marketQuestion: '${event.title}: ${market.name}',
      marketImage: PolymarketEvent.logoFromTeams(
              event.teams.isNotEmpty ? event.teams : _fetchedTeams,
              market.name) ??
          market.imageUrl ??
          event.imageUrl,
      outcomes: [
        PolymarketOutcome(
          name: 'Yes',
          price: yes,
          tokenId: market.tokenId,
          conditionId: market.conditionId,
          gammaMarketId: market.gammaMarketId,
        ),
        PolymarketOutcome(
          name: 'No',
          price: (1.0 - yes).clamp(0.0, 1.0),
          tokenId: market.noTokenId,
          conditionId: market.conditionId,
          gammaMarketId: market.gammaMarketId,
        ),
      ],
      initialOutcomeIndex: second ? 1 : 0,
      onDeposit: widget.onDeposit,
      ledgerWalletId: widget.ledgerWalletId,
      marketCategory: event.category,
      marketEndAt: event.endDate,
      sideLabelPos: pos,
      sideLabelNeg: neg,
      outcomeColors: colors.any((c) => c != null) ? colors : null,
      source: widget.source,
    );
  }

  /// The slip of a three-way match ([wdl]): its three winner markets as
  /// three sides (team, draw, team, by their short names), opened on
  /// [index] (0 the title's first team, 1 the draw, 2 the second). Each
  /// side buys its own market's Yes and wears its chart line's colour
  /// ([lineColors], by token). Titled by the match, as a two-way game's
  /// slip is: the sides say which outcome.
  void _openThreeWaySlip(PolyWdlOutcomes wdl, int index,
      {Map<String, Color> lineColors = const {}}) {
    HapticFeedback.mediumImpact();
    openingBetSlip = true;
    final teams = event.teams.isNotEmpty ? event.teams : _fetchedTeams;
    final names =
        gameShortSideNames(wdl.teamAName, wdl.teamBName, teams: teams);
    final sides = [wdl.teamA, wdl.draw, wdl.teamB];
    TrackingService.track('prediction_outcome_tapped', params: {
      'outcome_type': 'multi',
      if (event.category.isNotEmpty) 'category': event.category.toLowerCase(),
    });
    final colors = [for (final o in sides) lineColors[o.tokenId]];
    BetSlipSheet.show(
      context,
      event: event,
      negRisk: event.negRisk,
      marketQuestion: event.title,
      marketSlug: event.slug,
      marketImage: event.imageUrl,
      outcomes: [
        // Each market's Yes alone: the three sides price against each
        // other, and a side is bought on its own market.
        for (final o in sides)
          PolymarketOutcome(
            name: o.name,
            price: o.price,
            tokenId: o.tokenId,
            conditionId: o.conditionId,
            gammaMarketId: o.gammaMarketId,
            imageUrl: o.imageUrl,
          ),
      ],
      outcomeLabels: [names.$1, context.l10n.betDraw, names.$2],
      initialOutcomeIndex: index.clamp(0, 2),
      onDeposit: widget.onDeposit,
      ledgerWalletId: widget.ledgerWalletId,
      marketCategory: event.category,
      marketEndAt: event.endDate,
      outcomeColors: colors.any((c) => c != null) ? colors : null,
      source: widget.source,
    );
  }

  /// "While the game is live, orders wait Ns…": one caption line, only
  /// while the game is on (Gamma sets the delay before kickoff too).
  Widget _buildInPlayDelayNote(AppColorsExtension c) {
    return Consumer(builder: (context, linesRef, _) {
      final delay = polyGameLinesFor(linesRef, event).secondsDelay;
      if (delay <= 0 || !_isGameLive(_liveMatchUpdate(linesRef))) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: EdgeInsets.only(top: 10.h, left: 4.w),
        child: Text(
          context.l10n.polyGameInPlayDelay('$delay'),
          style: TextStyle(
            color: c.textTertiary,
            fontSize: 12.sp,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
        ),
      );
    });
  }

  /// The abbreviation Gamma's teams give [name] ("Colts" -> "IND"), for the
  /// NFL possession join; null when no team matches.
  String? _teamAbbreviation(String name) => polyTeamAbbreviation(
      event.teams.isNotEmpty ? event.teams : _fetchedTeams, name);

  bool _gameCentreTracked = false;

  /// Once per sheet: the person opened a game in play (its live game
  /// centre). League and kind of market only.
  void _trackGameCentreOpened(SportsMatchUpdate? ws) {
    if (_gameCentreTracked) return;
    _gameCentreTracked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      TrackingService.track('live_game_center_opened', params: {
        if (ws?.leagueAbbreviation != null) 'league': ws!.leagueAbbreviation!,
        if (event.category.isNotEmpty) 'category': event.category.toLowerCase(),
        'entry_source': widget.source,
        'live_feed': ws != null,
        'has_stream': event.hasLivestream,
      });
    });
  }

  Widget _buildHeroCard(AppColorsExtension c) {
    final sportsTeams = _detectSportsTeams();
    // Where the game stands (live or over, score, clock): the same read
    // the open-position screen makes for its header.
    final eventTeams = event.teams.isNotEmpty ? event.teams : _fetchedTeams;
    final header = polyGameHeaderData(ref, context, event,
        sportsTeams: sportsTeams, teams: eventTeams);
    final ws = header.ws;
    final gameLive = header.live;
    if (gameLive) _trackGameCentreOpened(ws);
    return Padding(
      padding: EdgeInsets.only(top: 10.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sport events with a "Team A vs Team B" title get a
          // dedicated two-team header — team logo + name on each
          // side with a centered "vs" pill. Falls back to the
          // standard image + title row when team detection fails or
          // the event isn't sports.
          // Sport events with a "Team A vs Team B" title get a
          // dedicated two-team header (team logo + name on each side, a
          // centred "vs" pill, the score and clock). Any other event's
          // title and image are in the screen's header.
          if (sportsTeams != null)
            PolyGameTeamsHeader.of(header,
                teams: sportsTeams, eventTeams: eventTeams),
          // A game has no headline: its header carries the score and the
          // clock and its board the chances. (The most likely of its many
          // markets, an over/under at 99%, said nothing about the game.)
          if (!_isGameSheet) ...[
            if (sportsTeams != null) SizedBox(height: 22.h),
            // Own Consumer: the hero percentage is the only thing in the
            // hero card that has to follow a price tick.
            Consumer(
              builder: (context, heroRef, _) => _buildHeroHeadline(heroRef, c),
            ),
          ],
          // Sal's question for this market, right under the figure.
          SalQuestionCapsule(
            advisorContext: _salContext,
            chipSignals: salSignalsForPolyEvent(event),
            padding: EdgeInsets.only(top: 16.h),
          ),
        ],
      ),
    );
  }

  /// Headline branch of the hero card. Five paths in priority order:
  ///   1. Binary market — unchanged "Yes chance" + huge YES % (the
  ///      market_chart / Buy Yes/No flow expects this shape).
  ///   2. All sub-markets resolved (>0.97 or <0.03) — "Resolved" pill
  ///      with the winning outcome's name in green. Kills the
  ///      "Leading 100%" framing that triggered issue #201.
  ///   3. All sub-markets at the 0.5 stub — "Awaiting liquidity" pill.
  ///   4. Large multi-outcome event (>20 sub-markets like LoL with
  ///      Game N Winner / O/U / Total Kills) — "{N} markets" badge
  ///      with "Tap a market to predict" subtitle, since no single % is
  ///      representative.
  ///   5. Otherwise — leading outcome's name + its % (drops the
  ///      misleading "Leading" framing in favour of the actual
  ///      candidate, e.g. "Senegal 50%" / "France 18%").
  Widget _buildHeroHeadline(WidgetRef ref, AppColorsExtension c) {
    if (event.isBinary) {
      return _buildBinaryHeroHeadline(ref, c);
    }
    if (_allOutcomesResolvedFor(ref)) {
      return _buildResolvedHeroPill(ref, c);
    }
    if (_allOutcomesStubFor(ref)) {
      return _buildAwaitingLiquidityHeroPill(c);
    }
    if (_isLargeMultiOutcome) {
      return _buildMarketCountHero(ref, c);
    }
    return _buildLeadingOutcomeHero(ref, c);
  }

  Widget _buildBinaryHeroHeadline(WidgetRef ref, AppColorsExtension c) {
    final heroProb = _liveYesPrice(ref);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          context.l10n.betYesChance,
          style: TextStyle(
            color: c.textTertiary,
            fontSize: 13.sp,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
        ),
        SizedBox(height: 4.h),
        Text(
          _formatPctShort(heroProb),
          style: TextStyle(
            color: _kPolyGreen,
            fontSize: 56.sp,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.6,
            height: 1.0,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  /// Leading-outcome hero — shows the actual top candidate's name and
  /// its probability instead of the generic "Leading" label. Mirrors
  /// polymarket.com's event hero treatment ("Senegal 50%").
  Widget _buildLeadingOutcomeHero(WidgetRef ref, AppColorsExtension c) {
    // Rank only the BETTABLE field — a decided sports sub-market pinned
    // at 100% (e.g. a finished "Set 1 Winner") must not hijack the
    // headline from the still-live markets. Falls back to the raw list
    // when everything is decided (the resolved pill usually renders
    // before this anyway).
    final bettable = _bettableOutcomesFor(ref);
    final pool = bettable.isNotEmpty ? bettable : event.outcomes;
    final prices = _livePriceMap(ref);
    final indexed = List.generate(pool.length, (i) => i);
    indexed.sort((a, b) {
      final pa = _priceOf(prices, pool[a].tokenId, pool[a].price);
      final pb = _priceOf(prices, pool[b].tokenId, pool[b].price);
      return pb.compareTo(pa);
    });
    final leader = pool[indexed.first];
    final leaderPrice = _priceOf(prices, leader.tokenId, leader.price);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          leader.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: c.textTertiary,
            fontSize: 13.sp,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
        ),
        SizedBox(height: 4.h),
        Text(
          _formatPctShort(leaderPrice),
          style: TextStyle(
            // An Up or Down market's leader in its own colour.
            color: polyUpDownColor(leader.name, event.outcomes) ??
                _kPolyPurple,
            fontSize: 56.sp,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.6,
            height: 1.0,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  /// "Resolved · {winner}" pill — replaces the misleading
  /// "Leading 100%" hero when every sub-market has settled. Picks the
  /// outcome with price >0.97 as the winner; falls back to the
  /// highest-priced outcome if none crosses the threshold (defensive).
  Widget _buildResolvedHeroPill(WidgetRef ref, AppColorsExtension c) {
    final prices = _livePriceMap(ref);
    final indexed = List.generate(event.outcomes.length, (i) => i);
    indexed.sort((a, b) {
      final pa =
          _priceOf(prices, event.outcomes[a].tokenId, event.outcomes[a].price);
      final pb =
          _priceOf(prices, event.outcomes[b].tokenId, event.outcomes[b].price);
      return pb.compareTo(pa);
    });
    final winnerIdx = indexed.firstWhere(
      (i) =>
          _priceOf(prices, event.outcomes[i].tokenId, event.outcomes[i].price) >
          0.97,
      orElse: () => indexed.first,
    );
    final winner = event.outcomes[winnerIdx];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
          decoration: BoxDecoration(
            color: c.surfaceLight,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            context.l10n.resolved,
            style: TextStyle(
              color: c.textSecondary,
              fontSize: 12.sp,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.1,
            ),
          ),
        ),
        SizedBox(height: 10.h),
        Text(
          winner.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: _kPolyGreen,
            fontSize: 28.sp,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            height: 1.1,
          ),
        ),
      ],
    );
  }

  /// "Awaiting liquidity" pill — every outcome sits at the 0.5 stub
  /// because no one has placed an order yet. Don't pretend there's a
  /// leader.
  Widget _buildAwaitingLiquidityHeroPill(AppColorsExtension c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
          decoration: BoxDecoration(
            color: c.surfaceLight,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            context.l10n.betAwaitingLiquidity,
            style: TextStyle(
              color: c.textSecondary,
              fontSize: 12.sp,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.1,
            ),
          ),
        ),
        SizedBox(height: 10.h),
        Text(
          context.l10n.betNoPricesYet,
          style: TextStyle(
            color: c.textSecondary,
            fontSize: 22.sp,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            height: 1.1,
          ),
        ),
      ],
    );
  }

  /// Large multi-outcome (LoL Game N Winner, O/U 3.5 Games, Total
  /// Kills O/U, …): a single "leading %" reads as noise once you've
  /// got 50+ sub-markets. Show the count + nudge to tap a market.
  /// Outcomes still bettable / in contention — drops eliminated sub-markets
  /// sitting at ~0 (≤ 0.5¢), matching the legend's filter. Keeps the "N
  /// markets" count and the chart honest so a decided race doesn't read as
  /// "49 markets" of mostly-dead candidates.
  List<PolymarketOutcome> _bettableOutcomesFor(WidgetRef ref) {
    final prices = _livePriceMap(ref);
    return [for (final i in _bettableIndices(prices)) event.outcomes[i]];
  }

  /// Indices (into the event's outcomes) of the outcomes still bettable
  /// at [prices], in the event's order.
  List<int> _bettableIndices(Map<String, double> prices,
      {Set<String> unpriced = const {}}) {
    // On a SPORTS MATCH grouping, a sibling sub-market pinned at ~100%
    // is DECIDED (e.g. "Set 1 Winner" after the set ends) — Gamma keeps
    // it in the event until official resolution, but there is nothing
    // left to bet and it clutters the list / hijacks the leading-% hero
    // (user report: live tennis showed "Set 1 Winner … 100%" as the
    // headline mid-match). Candidate events are NOT gated: a 99.9%
    // election favourite is still a real, tradeable market.
    final isSportsMatch = _detectSportsTeams() != null || event.gameId != null;
    final outcomes = event.outcomes;
    // A book with no price to show ([polyShownChanceOf]) is still a market
    // to bet on: listed, last, with "—".
    return [
      for (var i = 0; i < outcomes.length; i++)
        if (polyShownChanceOf(prices, unpriced, outcomes[i]) == null ||
            _isBettable(
                _priceOf(prices, outcomes[i].tokenId, outcomes[i].price),
                isSportsMatch))
          i,
    ];
  }

  static bool _isBettable(double p, bool isSportsMatch) {
    if (isSportsMatch && p >= 0.995) return false;
    // Keep the FULL field — even deep longshots (a 0.01% World Cup team is
    // a real, tradable contender, not eliminated). Only drop a candidate
    // priced at exactly 0 (a truly-removed sub-market) and the rare 50/50
    // placeholder stub Polymarket returns for a candidate with no real
    // market yet.
    return p > 0 && (p - 0.5).abs() >= 0.0005;
  }

  /// [_bettableOutcomesFor], watched as a set: rebuilds the caller only
  /// when an outcome joins or leaves the bettable field, not on every
  /// tick of every outcome.
  List<PolymarketOutcome> _bettableWatched(WidgetRef ref) {
    final key = ref.watch(livePriceProvider
        .select((s) =>
            _IndexKey(_bettableIndices(s.prices, unpriced: s.unpriced))));
    return [for (final i in key.indices) event.outcomes[i]];
  }

  /// The bettable outcomes (less those [skip] names) in the order the
  /// list shows them, most likely first at the live prices. Watched as an
  /// order: a tick rebuilds the caller only when it moves one outcome past
  /// another or out of the field; each row follows its own price.
  List<PolymarketOutcome> _listOrderWatched(WidgetRef ref,
      {bool Function(PolymarketOutcome o)? skip}) {
    final outcomes = event.outcomes;
    final key = ref.watch(livePriceProvider.select((s) {
      final prices = s.prices;
      // Most likely first; a market with no chance to show goes last.
      final order = [
        for (final i in _bettableIndices(prices, unpriced: s.unpriced))
          if (skip == null || !skip(outcomes[i])) i
      ]..sort((a, b) => polyCompareShown(
          polyShownChanceOf(prices, s.unpriced, outcomes[a]),
          polyShownChanceOf(prices, s.unpriced, outcomes[b])));
      return _IndexKey(order);
    }));
    return [for (final i in key.indices) outcomes[i]];
  }

  Widget _buildMarketCountHero(WidgetRef ref, AppColorsExtension c) {
    final bettable = _bettableOutcomesFor(ref);
    final n = bettable.length;
    // The headline is the leader: the open outcome with the highest
    // chance, live with the list's own prices, its name where "markets"
    // used to be. The count moves to the caption. With no price at all
    // the count stays the headline.
    final prices = _livePriceMap(ref);
    PolymarketOutcome? leader;
    var leaderPrice = 0.0;
    for (final o in bettable) {
      final p = _priceOf(prices, o.tokenId, o.price);
      if (p > leaderPrice) {
        leader = o;
        leaderPrice = p;
      }
    }
    if (leader != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _LeaderHeadline(
            figure: _formatPctShort(leaderPrice),
            name: leader.name,
            figureStyle: TextStyle(
              color: _kPolyPurple,
              fontSize: 56.sp,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.6,
              height: 1.0,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            nameStyle: TextStyle(
              color: c.textSecondary,
              fontSize: 16.sp,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '$n',
              style: TextStyle(
                color: _kPolyPurple,
                fontSize: 56.sp,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.6,
                height: 1.0,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            SizedBox(width: 8.w),
            Padding(
              padding: EdgeInsets.only(bottom: 10.h),
              child: Text(
                context.l10n.betMarketsSuffix,
                style: TextStyle(
                  color: c.textSecondary,
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFallbackIcon(AppColorsExtension c, double size) {
    final initial = event.title.trim().isNotEmpty
        ? event.title.trim()[0].toUpperCase()
        : '?';
    final hue = (initial.codeUnitAt(0) * 37) % 360;
    final bgColor =
        HSLColor.fromAHSL(1.0, hue.toDouble(), 0.55, 0.45).toColor();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(size / 4),
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.4,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  /// Under the chart and the outcomes: the one row that opens the
  /// market's rules, how it resolves, its stats and what people wrote
  /// under it. The stats (24h volume, volume, liquidity) go in with the
  /// sheet rather than sitting on this screen (owner decision); when the
  /// market closes is already one of the sheet's own rows, so the end
  /// date is not among them.
  Widget _buildRulesRow() => Consumer(
        builder: (context, statsRef, _) => PolyRulesRow(
          onTap: () => showPolyRulesSheet(
            context,
            event,
            stats: polyMarketStats(
              context.l10n,
              volume24hr: event.volume24hr,
              volume: event.volume,
              liquidity: event.liquidity,
              endDate: null,
              ended: _isOverFor(statsRef),
              money: (v) => _formatVolume(statsRef, v),
            ),
          ),
        ),
      );

  /// The outcome list of an event with many outcomes, as slivers (its
  /// rows are built as they scroll into view).
  Widget _buildMultiOutcomeList(WidgetRef ref, AppColorsExtension c) {
    // Soccer-style W/D/L match? If the event is a sports vs-event
    // (we already detect team names) and there are exactly 3
    // outcomes — Team A win / Draw / Team B win — render a compact
    // 3-pill row with the actual odds instead of the verbose
    // "Will Portugal win on 2026-06-10?" question-list. Sums up
    // to ~100% across the three buttons so the user can read the
    // implied probabilities at a glance. Each pill follows its own price.
    final soccerLayout = _buildSoccerWDLRow(c);
    if (soccerLayout != null) return SliverToBoxAdapter(child: soccerLayout);

    // Drop resolved (eliminated) outcomes from the market-detail
    // legend — they sit at ≤ 0.5¢ and just clutter the list with
    // teams that physically can't win anymore. Bet slip still
    // exposes them via its `Show resolved (N)` collapsible so a
    // user who wants to verify a specific elimination can scroll
    // through. Matches polymarket.com's "Hide resolved" default
    // behaviour on the market page. Most likely first, watched as an
    // order: a tick that moves no outcome past another rebuilds nothing
    // here.
    final sorted = _listOrderWatched(ref);
    // The colour of each outcome's line on the chart above, by token: a
    // row takes it for its dot and its figure; an outcome the chart does
    // not draw has neither.
    final lineColors = _isGameSheet
        ? {
            for (final line in _gameWinnerLines(ref)) line.tokenId: line.color,
          }
        : {
            for (final line in _chartedOutcomes(ref, _bettableWatched(ref)))
              line.outcome.tokenId!: line.color,
          };
    // A football match's Exact Score: a score list, by result.
    final exact = _buildExactScoreList(sorted, lineColors);
    if (exact != null) return exact;
    // A count market marks the range its tally is in now.
    final count = _currentTweetCount(ref);
    final nowLabel = context.l10n.polyCountNow;
    return _ExpandableOutcomeLegend(
      outcomes: sorted,
      livePriceFor: _shownChanceFor,
      nameFor: _rowName,
      lineColorFor: (o) => lineColors[o.tokenId],
      sideLabelsFor: _sideLabelsFor,
      noteFor: count == null
          ? null
          : (o) {
              final b = polyCountBracket(o.name);
              final inRange = b != null &&
                  count >= b.min &&
                  (b.max == null || count <= b.max!);
              return inRange ? nowLabel : null;
            },
      // Tap a candidate → open its own full-screen binary detail, or the
      // slip in its line's colour for an outcome with no Yes / No.
      onPickOutcome: (o) => _openCandidateDetail(o, lineColors: lineColors),
    );
  }

  /// An Exact Score event's rows as a score list ([PolyExactScoreList]);
  /// null for any other event.
  Widget? _buildExactScoreList(
      List<PolymarketOutcome> sorted, Map<String, Color> lineColors) {
    if (!polyIsExactScoreList(event.outcomes, title: event.title)) return null;
    final teams = _detectSportsTeams();
    final unpriced = ref.read(livePriceProvider).unpriced;
    final prices = ref.read(livePriceProvider).prices;
    return PolyExactScoreList(
      outcomes: sorted,
      chanceFor: _shownChanceFor,
      sortChance: (o) => polyShownChanceOf(prices, unpriced, o),
      // As the plain list: the outcome's own Yes / No sheet.
      onPick: (o) => _openCandidateDetail(o, lineColors: lineColors),
      homeName: teams?.teamA ?? '',
      awayName: teams?.teamB ?? '',
      homeCrest: teams?.imageA,
      awayCrest: teams?.imageB,
      homeAbbr: teams == null ? null : _teamAbbreviation(teams.teamA),
      awayAbbr: teams == null ? null : _teamAbbreviation(teams.teamB),
    );
  }

  /// Detects the soccer Win/Draw/Lose shape and returns the three mapped
  /// outcomes with their display names, or null. Shared by the WDL pill
  /// row and the chart so both colour Team A / Draw / Team B identically.
  ({
    PolymarketOutcome teamA,
    PolymarketOutcome draw,
    PolymarketOutcome teamB,
    String teamAName,
    String teamBName,
  })? _detectWDLOutcomes() => polyWdlOutcomes(event, _detectSportsTeams());

  /// Returns a 3-pill Win/Draw/Lose row when the event matches the
  /// soccer-match shape, otherwise null.
  Widget? _buildSoccerWDLRow(AppColorsExtension c) {
    final wdl = _detectWDLOutcomes();
    if (wdl == null) return null;
    final teamAOutcome = wdl.teamA;
    final drawOutcome = wdl.draw;
    final teamBOutcome = wdl.teamB;
    final short = gameShortSideNames(wdl.teamAName, wdl.teamBName,
        teams: event.teams.isNotEmpty ? event.teams : _fetchedTeams);
    final teams = (teamA: short.$1, teamB: short.$2);
    // Solid slabs, each in its outcome's chart-line colour (the draw's
    // too) with white text, so the buttons read as the chart's traces
    // (never green and red, which read as up and down). Each card shows
    // the team/outcome name on top and its live percentage big
    // underneath. Tapping opens the match's three-way slip on it.
    final colors = _wdlLineColors(wdl);
    final lineColors = {
      for (final (o, line) in [
        (teamAOutcome, colors.teamA),
        (drawOutcome, colors.draw),
        (teamBOutcome, colors.teamB),
      ])
        if (o.tokenId != null) o.tokenId!: line,
    };
    Widget pill(PolymarketOutcome o, String label, Color line, int index) {
      // Match every other probability surface (hero/leader/legend): up to 3
      // decimals with trailing zeros trimmed, so a 49.75% outcome reads
      // "49.75%" and a longshot 1.25% reads "1.25%" instead of rounding to a
      // flat integer.
      return Expanded(
        child: Consumer(
          builder: (context, priceRef, _) => _WdlOutcomeButton(
            label: label,
            pctText: _formatPctShort(
                _livePriceFor(priceRef, o.tokenId, o.price)),
            accent: line,
            lineColor: line,
            onTap: () =>
                _openThreeWaySlip(wdl, index, lineColors: lineColors),
          ),
        ),
      );
    }

    return Row(
      children: [
        pill(teamAOutcome, teams.teamA, colors.teamA, 0),
        SizedBox(width: 8.w),
        pill(drawOutcome, context.l10n.betDraw, colors.draw, 1),
        SizedBox(width: 8.w),
        pill(teamBOutcome, teams.teamB, colors.teamB, 2),
      ],
    );
  }

  /// The colours of a soccer Win/Draw/Lose chart's three lines: each team
  /// its own ([gameSideColors]), the draw a third. The chart and the
  /// buttons under it both read this.
  ({Color teamA, Color draw, Color teamB}) _wdlLineColors(
      ({
        PolymarketOutcome teamA,
        PolymarketOutcome draw,
        PolymarketOutcome teamB,
        String teamAName,
        String teamBName,
      }) wdl) {
    final sides = gameSideColors(event.title, wdl.teamAName, wdl.teamBName);
    return (teamA: sides.$1, draw: kPolyOutcomeColors[2], teamB: sides.$2);
  }

  /// Builds the chart against [ref] — the chart Consumer's ref, NOT the
  /// sheet's — so everything watched in here repaints the chart alone.
  MarketChart? _buildChartBody(WidgetRef ref) {
    if (event.isBinary) {
      final yesIdx =
          event.outcomes.indexWhere((o) => o.name.toLowerCase() == 'yes');
      final noIdx =
          event.outcomes.indexWhere((o) => o.name.toLowerCase() == 'no');
      final lines = <MarketChartLine>[];
      if (yesIdx >= 0) {
        final y = event.outcomes[yesIdx];
        if (y.tokenId != null && y.tokenId!.isNotEmpty) {
          lines.add(MarketChartLine(
            tokenId: y.tokenId!,
            color: _kPolyGreen,
            // Merge: main's l10n label + nav's LIVE WS price pin (the
            // chart's right edge tracks incoming ticks and stays in sync
            // with the Yes/No buttons; `_livePriceFor` ref.watches the
            // live feed, so a new tick rebuilds this and re-pins).
            label: context.l10n.yes,
            livePrice: _livePriceFor(ref, y.tokenId, y.price),
            thin: polyTokenIsThin(event, y.tokenId),
          ));
        }
      }
      // Binary markets chart only the Yes probability. The No line is
      // its exact mirror (No = 1 - Yes), so drawing both just doubles
      // the ink without adding information; the No side is still
      // tradeable via the outcome buttons. Fall back to the No token
      // only when the market has no Yes outcome at all.
      if (lines.isEmpty && noIdx >= 0) {
        final n = event.outcomes[noIdx];
        if (n.tokenId != null && n.tokenId!.isNotEmpty) {
          lines.add(MarketChartLine(
            tokenId: n.tokenId!,
            color: _kPolyRed,
            label: context.l10n.betNo,
            livePrice: _livePriceFor(ref, n.tokenId, n.price),
            thin: polyTokenIsThin(event, n.tokenId),
          ));
        }
      }
      if (lines.isEmpty) {
        final tokenId = event.yesTokenId ??
            (event.outcomes.isNotEmpty ? event.outcomes.first.tokenId : null);
        if (tokenId == null || tokenId.isEmpty) return null;
        return MarketChart(
          tokenId: tokenId,
          height: _chartHeight,
          accentColor: _kPolyGreen,
          bought: _chartBought(ref, [tokenId]),
          shortMarket: _isShortRound,
          resolved: _isOverFor(ref),
          openedAt: polyChartOpenedAt(event),
          inPlay: event.isInPlay,
          kindIds: [event.id],
          thin: polyTokenIsThin(event, tokenId),
        );
      }
      return MarketChart(
        lines: lines,
        height: _chartHeight,
        // Match the charted line: green for Yes, red for the No-only
        // fallback.
        accentColor: lines.first.color,
        bought: _chartBought(ref, [for (final l in lines) l.tokenId]),
        shortMarket: _isShortRound,
        resolved: _isOverFor(ref),
        openedAt: polyChartOpenedAt(event),
        inPlay: event.isInPlay,
        kindIds: [event.id],
      );
    }

    // A game: the chart tells one story, who is winning. One line per team
    // in its team colour (and the draw of a three-way match), from the
    // winner market alone; never the game's most likely markets, which
    // are totals, spreads and props. Left out until that market is known.
    if (_isGameSheet) {
      final winner = _gameWinnerLines(ref);
      if (winner.isEmpty) return null;
      return MarketChart(
        lines: [
          for (final line in winner)
            MarketChartLine(
              tokenId: line.tokenId,
              color: line.color,
              label: line.label,
              livePrice: _livePriceFor(ref, line.tokenId, line.price),
            ),
        ],
        height: _chartHeight,
        accentColor: winner.first.color,
        bought: _chartBought(ref, [for (final l in winner) l.tokenId]),
        shortMarket: _isShortRound,
        resolved: _isOverFor(ref),
        openedAt: polyChartOpenedAt(event),
        inPlay: event.isInPlay,
        kindIds: [event.id],
      );
    }

    // Soccer Win/Draw/Lose: chart the same three series the board shows,
    // each team in its own colour (the one its figure on the board and its
    // side of the momentum graph take) and the draw in a third. Never
    // green and red: on a team those read as up and down.
    final wdl = _detectWDLOutcomes();
    if (wdl != null) {
      final wdlLines = <MarketChartLine>[];
      void addWdl(PolymarketOutcome o, String label, Color color) {
        if (o.tokenId != null && o.tokenId!.isNotEmpty) {
          wdlLines.add(MarketChartLine(
            tokenId: o.tokenId!,
            color: color,
            label: label,
            livePrice: _livePriceFor(ref, o.tokenId, o.price),
          ));
        }
      }

      final colors = _wdlLineColors(wdl);
      final names = gameShortSideNames(wdl.teamAName, wdl.teamBName,
          teams: event.teams.isNotEmpty ? event.teams : _fetchedTeams);
      addWdl(wdl.teamA, names.$1, colors.teamA);
      addWdl(wdl.draw, context.l10n.betDraw, colors.draw);
      addWdl(wdl.teamB, names.$2, colors.teamB);
      if (wdlLines.length >= 2) {
        return MarketChart(
          lines: wdlLines,
          height: _chartHeight,
          accentColor: colors.teamA,
          bought: _chartBought(ref, [for (final l in wdlLines) l.tokenId]),
          shortMarket: _isShortRound,
          resolved: _isOverFor(ref),
          openedAt: polyChartOpenedAt(event),
          inPlay: event.isInPlay,
          kindIds: [event.id],
        );
      }
    }

    // The most likely outcomes, a line each. The list under the chart
    // reads the same assignment for its rows' dots.
    final lines = <MarketChartLine>[
      for (final line in _chartedOutcomes(ref, _bettableWatched(ref)))
        MarketChartLine(
          tokenId: line.outcome.tokenId!,
          color: line.color,
          label: line.outcome.name,
          livePrice:
              _livePriceFor(ref, line.outcome.tokenId, line.outcome.price),
          thin: polyTokenIsThin(event, line.outcome.tokenId),
        ),
    ];

    if (lines.isEmpty) return null;

    return MarketChart(
      lines: lines,
      height: polyChartHeightFor(lines.length),
      accentColor: lines.first.color,
      bought: _chartBought(ref, [for (final l in lines) l.tokenId]),
      shortMarket: _isShortRound,
      resolved: _isOverFor(ref),
      openedAt: polyChartOpenedAt(event),
      inPlay: event.isInPlay,
      kindIds: [event.id],
    );
  }

  /// A match with a game behind it (two sides in the title, a game id):
  /// its header carries the score and its board the chances, so it has no
  /// headline of its own, and its chart draws the winner market only.
  bool get _isGameSheet =>
      !event.isSyntheticBinary &&
      !event.isBinary &&
      (event.gameId != null || event.metadataGameId != null) &&
      _detectSportsTeams() != null;

  /// The lines of a game's chart ([polyGameWinnerLines]).
  List<PolyGameChartLine> _gameWinnerLines(WidgetRef ref) =>
      polyGameWinnerLines(
        event: event,
        sportsTeams: _detectSportsTeams(),
        lines: polyGameLinesFor(ref, event),
        drawLabel: context.l10n.betDraw,
        teams: event.teams.isNotEmpty ? event.teams : _fetchedTeams,
      );

  /// The outcomes the chart draws, each with its line's colour. On a game
  /// a team's own line takes its team colour by the one rule the whole
  /// sheet and the open-position screen share ([gameLineColor]: the
  /// title's first team the first colour), whatever its rank; every other
  /// line keeps the palette's.
  List<({PolymarketOutcome outcome, Color color})> _chartedOutcomes(
      WidgetRef ref, List<PolymarketOutcome> outcomes) {
    final charted = polyChartedOutcomes(outcomes, kPolyOutcomeColors);
    if (event.isSyntheticBinary ||
        (event.gameId == null && event.metadataGameId == null)) {
      return charted;
    }
    final moneyline = polyGameLinesFor(ref, event).winner;
    final teams = _detectSportsTeams();
    return [
      for (final line in charted)
        (
          outcome: line.outcome,
          color: gameLineColor(
                  event, teams, moneyline, line.outcome.tokenId!) ??
              line.color,
        ),
    ];
  }

  /// The chart with the game's event markers (and what sits under it) when
  /// this is a match; the chart alone otherwise.
  Widget _gameChartSection(MarketChart chart) => polyGameChart(
        event: event,
        chart: chart,
        teams: event.teams.isNotEmpty ? event.teams : _fetchedTeams,
        sportsTeams: _detectSportsTeams(),
        source: widget.source,
      );

  /// A 5 or 15 minute round (`btc-updown-15m-1715250300`): the chart gets
  /// the short range row and opens on LIVE.
  bool get _isShortRound => RegExp(r'-(5|15)m-').hasMatch(event.slug);

  /// The user's average price on each of [tokens] they hold, for the
  /// chart's dashed "Bought" line — the same basis the position sheet
  /// draws. Hot wallet only: a Ledger sheet shares the market, not the
  /// account, so it shows none.
  List<MarketChartBought> _chartBought(WidgetRef ref, List<String> tokens) {
    if (widget.ledgerWalletId != null || tokens.isEmpty) return const [];
    final held = ref.watch(polymarketActivePositionsProvider);
    return [
      for (final p in held)
        if (p.tokenId != null && p.size > 0 && tokens.contains(p.tokenId))
          MarketChartBought(
            tokenId: p.tokenId!,
            price: polymarketPositionCostBasis(ref, p) / p.size,
          ),
    ];
  }

  /// True when the event's two outcomes are a literal YES / NO pair — i.e. a
  /// prop / sub-question about the match ("Both Teams to Score", "Over/Under
  /// X", "Total Corners", a Halftime question) rather than a MONEYLINE ("Team A
  /// vs Team B" winner, whose outcomes carry the team names). Team-name side
  /// labels must apply ONLY to moneylines; a Yes/No prop whose TITLE merely
  /// contains "vs." ("Spain vs. Cabo Verde: Both Teams to Score") must read
  /// Yes/No, not "Spain"/"Verde" (img62).
  bool get _isYesNoProp {
    if (event.outcomes.length != 2) return false;
    final names =
        event.outcomes.map((o) => o.name.toLowerCase().trim()).toSet();
    return names.contains('yes') && names.contains('no');
  }

  /// Resolve the two side labels for a sub-market [name].
  ///   - A literal Yes/No PROP (Both Teams to Score, O/U, Total Corners,
  ///     Halftime …) → "Yes" / "No". The title may still contain "vs." (it
  ///     names the match) but the question is a yes/no ABOUT the match, not
  ///     "who wins", so team names are wrong here.
  ///   - A plain "A vs B" moneyline → the reliably-detected team names
  ///     (`_detectSportsTeams`, same source as the vs-header) instead of
  ///     fragile free-text parsing.
  ///   - Over/Under, spread, handicap, NRFI, etc. → the name-based helper
  ///     (OVER/UNDER, team + line, Yes/No …).
  ({String pos, String neg}) _sideLabelsFor(String name) {
    // Memoised: the legend calls this once per row on every rebuild, and the
    // answer only depends on the (immutable) name and the detected teams.
    final cached = _sideLabelMemo[name];
    if (cached != null) return cached;
    final resolved = _computeSideLabelsFor(name);
    _sideLabelMemo[name] = resolved;
    return resolved;
  }

  ({String pos, String neg}) _computeSideLabelsFor(String name) {
    // Yes/No props short-circuit BEFORE any vs-detection — the outcomes are
    // the source of truth, not the title text. This also stops
    // `polymarketSideLabels`' own vs-regex from grabbing team names off a
    // "Team A vs. Team B: <yes/no question>" prop title.
    if (_isYesNoProp) return (pos: 'Yes', neg: 'No');
    final isVersus = _kNameVersusRegex.hasMatch(name);
    final structured = _kNameStructuredRegex.hasMatch(name);
    if (isVersus && !structured) {
      final teams = _detectSportsTeams();
      if (teams != null) return (pos: teams.teamA, neg: teams.teamB);
    }
    return polymarketSideLabels(name);
  }

  Widget _buildStickyActions(AppColorsExtension c) {
    // Multi-outcome has no sticky bar — tapping a candidate opens its own
    // full-screen binary detail (chart + Yes/No). Keeps the list flush to
    // the bottom (no empty CTA space).
    if (!event.isBinary) {
      return const SizedBox.shrink();
    }
    return ClipRect(
      child: KuteBlur(
        sigmaX: 18,
        sigmaY: 18,
        child: Container(
          padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 8.h),
          decoration: BoxDecoration(
            color: (context.isDark ? c.surface : c.background)
                .withValues(alpha: 0.55),
            border: Border(
              top: BorderSide(color: c.borderSubtle, width: 0.5),
            ),
          ),
          child: SafeArea(
            top: false,
            // Own Consumer: the two cent values follow the live feed; the
            // blurred bar around them does not need to be rebuilt for that.
            child: Consumer(builder: (context, priceRef, _) {
              // The two written off the one price, so they add up to 100.
              final sides = formatPolyChancePair(_liveYesPrice(priceRef));
              // Semantic side labels: Over/Under → OVER/UNDER, moneyline →
              // the two teams (from the reliable vs-header detector),
              // spread → team + line, etc. — Yes/No is meaningless here.
              final title = _sideLabelsFor(event.title);
              // Each button names the outcome it opens the slip on: the
              // title's pair matched to the outcomes by name (the slip
              // reads it the same way), else the outcomes' own names.
              final names = [for (final o in event.outcomes) o.name];
              final labels = () {
                if (names.length != 2) return title;
                final positive = polymarketPositiveIndex(names);
                final matched = polymarketBinarySideLabels(names, title);
                if (matched != null) {
                  return (
                    pos: matched[positive],
                    neg: matched[1 - positive]
                  );
                }
                final lower = names.map((n) => n.trim().toLowerCase()).toSet();
                if (lower.containsAll(const {'yes', 'no'})) return title;
                return (pos: names[positive], neg: names[1 - positive]);
              }();
              // Shared badge CTA (disc icon + glow). YES/NO outcome
              // tokens keep their localized display labels; any other
              // semantic side label (teams, Over/Under) passes through
              // with the generic bolt glyph — exactly the old
              // `_ActionButton` logic, now at the call site.
              // Up/Down sides take the browse card's arrows.
              IconData iconFor(String l) => switch (polymarketSideGlyph(l)) {
                    PolymarketSideGlyph.yes => Icons.check_rounded,
                    PolymarketSideGlyph.no => Icons.close_rounded,
                    PolymarketSideGlyph.up => Icons.arrow_upward_rounded,
                    PolymarketSideGlyph.down => Icons.arrow_downward_rounded,
                    PolymarketSideGlyph.neutral => Icons.bolt_rounded,
                  };
              String displayFor(String l) => l.toUpperCase() == 'YES'
                  ? context.l10n.yes
                  : l.toUpperCase() == 'NO'
                      ? context.l10n.betNo
                      : l;
              return Row(
                children: [
                  Expanded(
                    child: MarketPairButton(
                      label: displayFor(labels.pos),
                      value: sides.first,
                      icon: iconFor(labels.pos),
                      iconDisc: true,
                      glow: true,
                      color: _kPolyGreen,
                      onTap: () => _openBetSlip('yes'),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: MarketPairButton(
                      label: displayFor(labels.neg),
                      value: sides.second,
                      icon: iconFor(labels.neg),
                      iconDisc: true,
                      glow: true,
                      color: _kPolyRed,
                      onTap: () => _openBetSlip('no'),
                    ),
                  ),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }

  /// Tap a multi-outcome row. Only TRUE candidate-pickers — where the
  /// outcome carries its own Yes/No tokens (`noTokenId`) — open a
  /// full-screen Yes/No binary detail. Pure pick-one multis, Over/Under
  /// legs, and any single-token outcome bet directly (no Yes/No step);
  /// sports Win/Draw/Lose already routes through `_buildSoccerWDLRow`.
  ///
  /// [lineColors] are the chart's line colours by token: a slip opened
  /// straight on an outcome wears its line's colour.
  void _openCandidateDetail(PolymarketOutcome cand,
      {Map<String, Color> lineColors = const {}}) {
    final hasYesNo = cand.noTokenId != null && cand.noTokenId!.isNotEmpty;
    if (!hasYesNo) {
      _openBetSlip(cand.name.toLowerCase(), lineColors: lineColors);
      return;
    }
    HapticFeedback.lightImpact();
    final yes = cand.price.clamp(0.0, 1.0);
    // Resolve the candidate's real crest ("Portugal" → flag) — Gamma ships
    // the generic league ball as every sub-market's icon, so cand.imageUrl
    // is useless for sports. Baking the crest into the synthetic event's
    // imageUrl fixes the drilled header, the bet slip AND the optimistic
    // position icon in one spot. Teams are deliberately NOT copied onto the
    // synthetic event: displayIconUrl would match nothing against "Yes"/"No"
    // and fall back to the HOME crest even on away/Draw drill-ins.
    final crest = PolymarketEvent.logoFromTeams(
      event.teams.isNotEmpty ? event.teams : _fetchedTeams,
      cand.name,
    );
    final binaryEvent = PolymarketEvent(
      id: '${event.id}-${cand.name}',
      slug: event.slug,
      title: cand.name,
      imageUrl: crest ?? cand.imageUrl ?? event.imageUrl,
      volume: cand.volume ?? 0,
      liquidity: event.liquidity,
      category: event.category,
      tags: event.tags,
      endDate: event.endDate,
      conditionId: cand.conditionId ?? event.conditionId,
      outcomes: [
        PolymarketOutcome(
          name: 'Yes',
          price: yes,
          tokenId: cand.tokenId,
          conditionId: cand.conditionId,
          gammaMarketId: cand.gammaMarketId,
        ),
        PolymarketOutcome(
          name: 'No',
          price: (1.0 - yes).clamp(0.0, 1.0),
          tokenId: cand.noTokenId,
          conditionId: cand.conditionId,
          gammaMarketId: cand.gammaMarketId,
        ),
      ],
      // Deliberately NOT carrying streamUrl/isLive here: the livestream
      // toggle stays on the parent event sheet only, not the drilled-in
      // Yes/No screen.
      // Force plain Yes/No — the title is a single question ("Will the match
      // end in a draw?"), which the vs-team parser would otherwise mangle
      // into a bogus two-team header.
      isSyntheticBinary: true,
    );
    MarketDetailSheet.show(
      context,
      event: binaryEvent,
      onDeposit: widget.onDeposit,
      ledgerWalletId: widget.ledgerWalletId,
      source: widget.source,
    );
  }

  /// [lineColors] (by token) tint the slip in the picked outcome's chart
  /// line colour; Yes / No and Up / Down keep the slip's green and red.
  void _openBetSlip(String? outcome,
      {Map<String, Color> lineColors = const {}}) {
    HapticFeedback.mediumImpact();
    openingBetSlip = true;
    int idx = 0;
    if (outcome != null) {
      idx = event.outcomes.indexWhere((o) => o.name.toLowerCase() == outcome);
      if (idx < 0 &&
          (outcome == 'yes' || outcome == 'no') &&
          event.outcomes.length == 2) {
        // The sticky pair's green / red sides on a market whose outcomes
        // are not called Yes/No (Up/Down, two teams): the side tapped,
        // by position. Defaulting to the first outcome opened a DOWN tap
        // on UP.
        final positive =
            polymarketPositiveIndex([for (final o in event.outcomes) o.name]);
        idx = outcome == 'yes' ? positive : 1 - positive;
      }
      if (idx < 0) idx = 0;
    }
    // Intent signal — user picked an outcome and is opening the slip.
    // Carries category + the outcome enum (yes/no/multi) so the
    // funnel can split predictions placement by market type.
    final String outcomeType;
    if (outcome == null) {
      outcomeType = 'multi';
    } else if (outcome == 'yes' || outcome == 'no') {
      outcomeType = outcome;
    } else {
      outcomeType = 'multi';
    }
    TrackingService.track('prediction_outcome_tapped', params: {
      'outcome_type': outcomeType,
      if (event.category.isNotEmpty) 'category': event.category.toLowerCase(),
    });
    // Carry the resolved side labels (moneyline team names, OVER/UNDER …)
    // so the slip's toggle + CTA match the detail buttons exactly.
    final labels = _sideLabelsFor(event.title);
    // Each outcome's line colour, for the slip to wear. An Up / Down
    // market's lines are already the slip's own green and red.
    final colors = [
      for (final o in event.outcomes)
        event.isBinary
            ? null
            : switch (lineColors[o.tokenId]) {
                AppColors.marketUp || AppColors.marketDown => null,
                final c => c,
              },
    ];
    final outcomeColors = colors.any((c) => c != null) ? colors : null;
    BetSlipSheet.show(
      context,
      event: event,
      negRisk: event.negRisk,
      marketQuestion: event.title,
      marketSlug: event.slug,
      marketImage: event.imageUrl,
      outcomes: event.outcomes,
      initialOutcomeIndex: idx,
      onDeposit: widget.onDeposit,
      ledgerWalletId: widget.ledgerWalletId,
      marketCategory: event.category,
      marketEndAt: event.endDate,
      sideLabelPos: labels.pos,
      sideLabelNeg: labels.neg,
      outcomeColors: outcomeColors,
      source: widget.source,
    );
  }
}

/// The name of a kind of game market, for the "More markets" pills and
/// headings.
String gameMarketGroupLabel(AppLocalizations l10n, String key) => switch (key) {
      'winner' => l10n.betGroupMoneyline,
      'spreads' => l10n.betGroupSpread,
      'totals' => l10n.betGroupTotals,
      'halves' => l10n.polyGroupHalves,
      'quarters' => l10n.polyGroupQuarters,
      _ => l10n.betGroupProps,
    };

/// One outcome button of a game's board or a Win/Draw/Lose row: the
/// team/outcome name on top and the live percentage big underneath. An
/// outcome with a line on the chart is a solid slab of that line's colour
/// with white text; one without (an Over/Under the chart does not draw)
/// is a neutral surface card. Press language (scale 0.97, medium haptic,
/// reduce-motion aware) matches `MarketPairButton`.
class _WdlOutcomeButton extends StatefulWidget {
  final String label;

  /// The side's crest (a team's badge or flag), before its name.
  final String? crestUrl;
  final String pctText;
  final Color accent;

  /// The colour of this outcome's line on the chart above. When set the
  /// card is a solid slab of it ([polyOutcomeFill]) with white text, the
  /// weight of the Up/Down buttons, so each side reads as its line.
  final Color? lineColor;
  final VoidCallback onTap;

  const _WdlOutcomeButton({
    required this.label,
    this.crestUrl,
    required this.pctText,
    required this.accent,
    this.lineColor,
    required this.onTap,
  });

  @override
  State<_WdlOutcomeButton> createState() => _WdlOutcomeButtonState();
}

class _WdlOutcomeButtonState extends State<_WdlOutcomeButton> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed == v) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final line = widget.lineColor;
    final fill = line == null ? null : polyOutcomeFill(line);
    return GestureDetector(
      onTapDown: (_) => _setPressed(true),
      onTapCancel: () => _setPressed(false),
      onTapUp: (_) => _setPressed(false),
      onTap: () {
        HapticFeedback.mediumImpact();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: (_pressed && !reduceMotion) ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeInOut,
        child: Container(
          height: 62.h,
          padding: EdgeInsets.symmetric(horizontal: 6.w),
          decoration: fill == null
              ? BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(16.r),
                  border: Border.all(color: c.borderSubtle, width: 0.5),
                )
              // MarketPairButton's slab: the solid fill with a faint top
              // highlight so it reads as pressable, not flat paint.
              : BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(16.r),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color.alphaBlend(
                          Colors.white.withValues(alpha: 0.08), fill),
                      fill,
                    ],
                    stops: const [0.0, 0.55],
                  ),
                ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.crestUrl != null &&
                      widget.crestUrl!.isNotEmpty) ...[
                    PolyCrestImage(
                      url: widget.crestUrl!,
                      size: 16.sp,
                      radius: 4.r,
                      fit: BoxFit.contain,
                      fallback: const SizedBox.shrink(),
                    ),
                    SizedBox(width: 5.w),
                  ],
                  Flexible(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        // Full white: the fill is set for 4.5:1 on it.
                        color: fill == null ? c.textSecondary : Colors.white,
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 3.h),
              RollingNumberText(
                text: widget.pctText,
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 250),
                style: TextStyle(
                  color: fill == null ? widget.accent : Colors.white,
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  height: 1.0,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Indices into an event's outcomes, compared by value: what a price
/// selector hands back so a widget rebuilds only when the list it shows
/// changes, not on every tick.
class _IndexKey {
  final List<int> indices;
  const _IndexKey(this.indices);

  @override
  bool operator ==(Object other) {
    if (other is! _IndexKey || other.indices.length != indices.length) {
      return false;
    }
    for (var i = 0; i < indices.length; i++) {
      if (other.indices[i] != indices[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(indices);
}

/// The outcome rows of a market sheet, as a sliver: only the rows on (or
/// near) the screen are built, so a game with 300 markets builds the
/// dozen in view. Each row's figures follow that row's own price
/// ([livePriceFor], read against the row's own ref).
class _ExpandableOutcomeLegend extends StatefulWidget {
  final List<PolymarketOutcome> outcomes;

  /// The chance a row shows; null for none ("—").
  final double? Function(WidgetRef ref, PolymarketOutcome o) livePriceFor;

  /// The colour of an outcome's line on the chart, null when the chart
  /// draws none for it. A row with a line shows its figure in that colour
  /// and, when it has no image, a small dot of it before the name.
  final Color? Function(PolymarketOutcome)? lineColorFor;

  /// Tapping a row routes here. Multi-outcome events surface each
  /// sub-market as a tappable row — the Polymarket web pattern —
  /// instead of collapsing everything into a single "Predict" CTA.
  final void Function(PolymarketOutcome)? onPickOutcome;

  /// Name of the currently-picked candidate (highlights its row).
  /// Resolves the per-row side labels (moneyline → team names, O/U →
  /// OVER/UNDER …). Falls back to the name-based helper when null.
  final ({String pos, String neg}) Function(String)? sideLabelsFor;

  /// A short caption under a row's name (a count market's "Now" on the
  /// range its tally is in); null for none.
  final String? Function(PolymarketOutcome)? noteFor;

  /// Whether rows lead with the outcome's image, or with the dot of its
  /// chart line when it has none ([PolyOutcomeLeading]). A list with no
  /// image and no charted outcome is text only either way.
  final bool showThumbs;

  /// Every row's figure in the primary text colour, instead of the colour
  /// of the row's chart line.
  final bool calmFigures;

  /// A game's "More markets": grouped by kind of market
  /// ([gameMarketGroupOf]) instead of the plain list's sections.
  final bool gameGroups;

  /// Show this group alone, under no heading; null for every group.
  final String? onlyGroup;

  /// With every group listed, the rows a group shows before its "Show N
  /// more" row; null to list each group whole.
  final int? collapseAfter;

  /// The name a row shows; the outcome's own when null.
  final String Function(PolymarketOutcome)? nameFor;
  const _ExpandableOutcomeLegend({
    required this.outcomes,
    required this.livePriceFor,
    this.lineColorFor,
    this.onPickOutcome,
    // TODO(dead-code): optional parameter never passed — candidate for removal.
    this.sideLabelsFor,
    this.noteFor,
    this.showThumbs = true,
    this.calmFigures = false,
    this.gameGroups = false,
    this.onlyGroup,
    this.collapseAfter,
    this.nameFor,
  });

  @override
  State<_ExpandableOutcomeLegend> createState() =>
      _ExpandableOutcomeLegendState();
}

class _ExpandableOutcomeLegendState extends State<_ExpandableOutcomeLegend> {
  /// Bucket a sub-market name into a section. Sports events mix Moneyline /
  /// Spread / Totals (O/U) / Props (NRFI etc.) in one list — grouping makes
  /// that scannable. Pure candidate-pickers (e.g. World Cup teams) all land
  /// in 'Other', so they render as a single headerless list.
  ///
  /// Memoised per name: `build` groups EVERY outcome on every rebuild, and a
  /// price tick rebuilds this legend.
  final Map<String, String> _groupMemo = {};

  String _groupFor(String name) => _groupMemo[name] ??= _computeGroupFor(name);

  /// Groups opened past their first rows ("Show N more").
  final Set<String> _opened = {};

  String _computeGroupFor(String name) {
    if (widget.gameGroups) return gameMarketGroupOf(name).key;
    final n = name.toLowerCase();
    if (_kGroupTotalsRegex.hasMatch(n) && _kGroupDigitRegex.hasMatch(n)) {
      return 'Totals';
    }
    if (n.contains('spread') || _kGroupSpreadRegex.hasMatch(name)) {
      return 'Spread';
    }
    if (n.contains('nrfi') ||
        n.contains('yrfi') ||
        n.contains('first inning')) {
      return 'Props';
    }
    if (n.contains(' vs')) return 'Moneyline';
    return 'Other';
  }

  /// Localized display label for a `_groupFor` bucket. The bucket ids stay
  /// English (they double as sort keys); only the rendered header changes.
  String _groupLabel(BuildContext context, String g) {
    if (widget.gameGroups) return gameMarketGroupLabel(context.l10n, g);
    switch (g) {
      case 'Moneyline':
        return context.l10n.betGroupMoneyline;
      case 'Spread':
        return context.l10n.betGroupSpread;
      case 'Totals':
        return context.l10n.betGroupTotals;
      case 'Props':
        return context.l10n.betGroupProps;
      default:
        return context.l10n.betGroupOther;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final display = widget.outcomes;

    // Group by section, preserving the (price-sorted) order within each.
    final order = widget.gameGroups
        ? [for (final g in GameMarketGroup.values) g.key]
        : const ['Moneyline', 'Spread', 'Totals', 'Props', 'Other'];
    final byGroup = <String, List<int>>{};
    for (int i = 0; i < display.length; i++) {
      (byGroup[_groupFor(display[i].name)] ??= []).add(i);
    }
    final only = widget.onlyGroup;
    final groups = [
      ...order.where(byGroup.containsKey),
      ...byGroup.keys.where((g) => !order.contains(g)),
    ].where((g) => only == null || g == only).toList();
    final showHeaders = only == null && groups.length > 1;

    // One leading width for the whole list: the image's when any outcome
    // has one, the dot's when none has but the chart draws lines, and
    // none at all otherwise. Worked out once, not once per row.
    final anyImage =
        display.any((o) => PolyOutcomeLeading.hasImage(o.imageUrl));
    final leads = widget.showThumbs &&
        PolyOutcomeLeading.listLeads(
          anyImage: anyImage,
          anyLine: widget.lineColorFor != null &&
              display.any((o) => widget.lineColorFor!(o) != null),
        );

    // What the list shows, top to bottom; each entry is built only when
    // it scrolls into view.
    final entries = <Widget Function(BuildContext)>[];
    for (final g in groups) {
      if (showHeaders) {
        final first = entries.isEmpty;
        entries.add((context) => Padding(
              padding: EdgeInsets.only(
                  top: first ? 0 : 16.h, bottom: 4.h, left: 4.w),
              child: Text(
                _groupLabel(context, g).toUpperCase(),
                style: TextStyle(
                  color: c.textTertiary,
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ));
      }
      final rows = byGroup[g]!;
      final limit = widget.collapseAfter;
      final folded = limit != null &&
          showHeaders &&
          rows.length > limit + 1 &&
          !_opened.contains(g);
      for (final i in folded ? rows.take(limit) : rows) {
        entries.add((context) =>
            _buildRow(context, c, i, anyImage: anyImage, leads: leads));
      }
      if (folded) {
        entries.add((context) => InkWell(
              borderRadius: BorderRadius.circular(12.r),
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _opened.add(g));
              },
              child: Padding(
                padding:
                    EdgeInsets.symmetric(vertical: 10.h, horizontal: 4.w),
                child: Text(
                  context.l10n.salShowMore(rows.length - limit),
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
            ));
      }
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, i) => Align(
          alignment: AlignmentDirectional.centerStart,
          child: entries[i](context),
        ),
        childCount: entries.length,
      ),
    );
  }

  /// A row's figure: its side's word (none for a side of one two-sided
  /// market) and the chance, which rolls the digits that changed. Keyed
  /// by the outcome, so a filter or a re-sort never rolls one row's
  /// chance from another's.
  Widget _rowFigure(
      PolymarketOutcome o, String? word, String figure, TextStyle style) {
    final rolling = RollingFigure(
      identity: o.tokenId ?? o.gammaMarketId ?? o.name,
      text: figure,
      style: style,
    );
    if (word == null) return rolling;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$word ',
          maxLines: 1,
          style: style,
          textHeightBehavior: const TextHeightBehavior(
            applyHeightToFirstAscent: false,
            applyHeightToLastDescent: false,
          ),
        ),
        rolling,
      ],
    );
  }

  Widget _buildRow(BuildContext context, AppColorsExtension c, int i,
      {required bool anyImage, required bool leads}) {
    final display = widget.outcomes;
    final lineColor = widget.lineColorFor?.call(display[i]);
    // No Yes/No market of its own: one side of a market whose other side
    // is another row ("No 7%" under Up would be Down's chance).
    final oneSide = !display[i].hasYesNo;
    // Semantic side labels for the chance pills (Over/Under, team names,
    // spread lines …) instead of a meaningless "Yes/No" on sports legs.
    // Plain markets keep the softer title-case Yes/No.
    final sl = widget.sideLabelsFor?.call(display[i].name) ??
        polymarketSideLabels(display[i].name);
    final posLabel = sl.pos == 'YES' ? context.l10n.yes : sl.pos;
    final negLabel = sl.neg == 'NO' ? context.l10n.betNo : sl.neg;
    return InkWell(
      borderRadius: BorderRadius.circular(12.r),
      onTap: widget.onPickOutcome != null
          ? () {
              HapticFeedback.lightImpact();
              widget.onPickOutcome!(display[i]);
            }
          : null,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 4.w),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top-pad the leading so it lines up with the first line of
            // the name instead of vertically centering across the
            // wrapped lines of a long sub-market name.
            if (leads) ...[
              Padding(
                padding: EdgeInsets.only(top: anyImage ? 2.h : 6.h),
                child: PolyOutcomeLeading(
                  imageUrl: display[i].imageUrl,
                  lineColor: lineColor,
                  listHasImages: anyImage,
                ),
              ),
              SizedBox(width: 10.w),
            ],
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: 12.w),
                child: () {
                  final name = Text(
                    widget.nameFor?.call(display[i]) ?? display[i].name,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.1,
                      height: 1.3,
                    ),
                  );
                  final note = widget.noteFor?.call(display[i]);
                  if (note == null) return name;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      name,
                      SizedBox(height: 2.h),
                      Text(
                        note,
                        style: TextStyle(
                          color: c.textTertiary,
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ],
                  );
                }(),
              ),
            ),
            // Yes / No chances stacked. Yes uses the per-outcome
            // accent color so the row's identity (May 31 = blue,
            // etc.) still reads at a glance; No sits beneath in
            // muted text. Asked for explicitly by the user — the
            // single-Yes render was hiding the implied opposite
            // side which matters on candidate-pickers.
            // Its own Consumer: a tick on this row's token repaints these
            // two figures, nothing else in the list.
            Consumer(builder: (context, priceRef, _) {
              final yes = widget.livePriceFor(priceRef, display[i]);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  () {
                    final style = TextStyle(
                      color: widget.calmFigures
                          ? c.textPrimary
                          : (lineColor ?? c.textPrimary),
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    );
                    // A side of one two-sided market (Up, Down, a player)
                    // is its own name: its chance alone. The figure rolls
                    // the digits that changed; the side's word stays put.
                    return _rowFigure(display[i], oneSide ? null : posLabel,
                        yes == null ? '—' : _formatPctShort(yes), style);
                  }(),
                  if (!oneSide && yes != null) SizedBox(height: 2.h),
                  if (!oneSide && yes != null) () {
                    // What the chance written above leaves of 100.
                    return _rowFigure(
                      display[i],
                      negLabel,
                      formatPolyChancePair(yes).second,
                      TextStyle(
                        color: c.textTertiary,
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.1,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    );
                  }(),
                ],
              );
            }),
            if (widget.onPickOutcome != null) ...[
              SizedBox(width: 8.w),
              Icon(Icons.chevron_right_rounded,
                  color: c.textTertiary, size: 18.sp),
            ],
          ],
        ),
      ),
    );
  }
}

// The paired badge CTA now lives in the shared `MarketPairButton`
// (disc icon + glow configuration); the YES/NO icon + label mapping
// moved to the call site above.

/// Detail sheet for the 5-min Up/Down crypto markets. Mirrors the
/// standard `MarketDetailSheet` chrome (close button, the Instant chip,
/// gradient background) but the body is just a full-bleed
/// `CryptoPredictBanner` so the rich UI (live price hero, countdown
/// pill, Up/Down split, dedicated Up/Down CTAs, live chart with
/// target dashed line, trade ticker) all stays in one place — the
/// same widget rendered on the Predictions list.
class FiveMinMarketDetailSheet extends StatelessWidget {
  final PolymarketEvent event;
  final VoidCallback? onDeposit;
  final String? ledgerWalletId;

  const FiveMinMarketDetailSheet({
    super.key,
    required this.event,
    this.onDeposit,
    this.ledgerWalletId,
  });

  static const routeName = 'polymarket-5min-market-detail-sheet';

  static void show(
    BuildContext context, {
    required PolymarketEvent event,
    VoidCallback? onDeposit,
    String? ledgerWalletId,
  }) {
    // Skip the slide-up transition entirely when the OS asks to reduce
    // motion (the route still appears, just without the animated slide).
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        settings: const RouteSettings(name: routeName),
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.4),
        fullscreenDialog: true,
        transitionDuration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 300),
        reverseTransitionDuration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 300),
        pageBuilder: (_, __, ___) => FastBetScope(
          active: ledgerWalletId == null && polyIsFastBetRound(event.slug),
          child: FiveMinMarketDetailSheet(
            event: event,
            onDeposit: onDeposit,
            ledgerWalletId: ledgerWalletId,
          ),
        ),
        transitionsBuilder: (_, animation, __, child) {
          return SlideTransition(
            position: animation.drive(
              Tween(begin: const Offset(0, 1), end: Offset.zero)
                  .chain(CurveTween(curve: Curves.easeOutCubic)),
            ),
            child: child,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final config = _resolveCryptoConfig(event);

    return Scaffold(
      backgroundColor: context.isDark
          ? context.colors.gradientBottom
          : context.colors.background,
      resizeToAvoidBottomInset: false,
      body: Container(
        decoration: AppDecorations.screenGradient(context),
        child: PlatformSafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.max,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 4.h),
                child: Row(
                  children: [
                    const KuteCloseButton(),
                    const Spacer(),
                    Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(10.r),
                        border: Border.all(color: c.borderSubtle, width: 0.5),
                      ),
                      child: Text(
                        context.l10n.instant,
                        style: TextStyle(
                          color: c.textSecondary,
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 24.h),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // The heartbeat reads the spending wallet's
                      // positions, so a Ledger's round has none.
                      if (ledgerWalletId == null)
                        RoundHeartbeat(
                          asset: config.asset,
                          child: CryptoPredictBanner(
                            config: config,
                            onDeposit: onDeposit,
                          ),
                        )
                      else
                        CryptoPredictBanner(
                          config: config,
                          onDeposit: onDeposit,
                          ledgerWalletId: ledgerWalletId,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The leader's chance with its name: beside the figure when the whole
/// name fits there on one line, else under it on up to two lines, and
/// only then cut ("Flávio Bolsonaro" is never "Flávio Bolson…" while
/// there is room below).
class _LeaderHeadline extends StatelessWidget {
  const _LeaderHeadline({
    required this.figure,
    required this.name,
    required this.figureStyle,
    required this.nameStyle,
  });

  final String figure;
  final String name;
  final TextStyle figureStyle;
  final TextStyle nameStyle;

  @override
  Widget build(BuildContext context) {
    final figureText = Text(figure, style: figureStyle);
    return LayoutBuilder(builder: (context, constraints) {
      final scaler = MediaQuery.textScalerOf(context);
      final direction = Directionality.of(context);
      // Measured in the face the Text widgets will draw in.
      final base = DefaultTextStyle.of(context).style;
      double widthOf(String text, TextStyle style) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: base.merge(style)),
          textDirection: direction,
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        final width = painter.width;
        painter.dispose();
        return width;
      }

      final room =
          constraints.maxWidth - widthOf(figure, figureStyle) - 8.w;
      if (constraints.hasBoundedWidth && widthOf(name, nameStyle) > room) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            figureText,
            SizedBox(height: 6.h),
            Text(name,
                maxLines: 2, overflow: TextOverflow.ellipsis, style: nameStyle),
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          figureText,
          SizedBox(width: 8.w),
          Flexible(
            child: Padding(
              padding: EdgeInsets.only(bottom: 10.h),
              child: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: nameStyle),
            ),
          ),
        ],
      );
    });
  }
}
