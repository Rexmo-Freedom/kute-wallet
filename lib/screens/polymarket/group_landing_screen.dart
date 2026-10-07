import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/services/venue_analytics.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/screens/polymarket/components/live_game.dart';
import 'package:kute/screens/polymarket/components/live_token_scope.dart';
import 'package:kute/screens/polymarket/components/market_card.dart';
import 'package:kute/screens/polymarket/components/poly_category_icons.dart';
import 'package:kute/screens/polymarket/market_detail_sheet.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/screens/shared/kute_glass.dart';

/// Grouped view of a single match's sub-markets (moneyline + Both Teams to
/// Score + O/U + corners …) the feed collapse hides. Renders the same
/// [MarketCard] rows the main feed uses. Tapping a row opens the usual
/// `MarketDetailSheet`, never modified here, only called.
///
/// Pushed onto the root navigator from inside `PolymarketScreen` — it is
/// NOT a GoRoute, keeping the single Predictions render path intact.
class GroupLandingScreen extends ConsumerStatefulWidget {
  /// Display title shown in the app bar header.
  final String title;

  /// Slug used to pick the empty-state glyph.
  final String slug;

  /// The full sibling set (primary moneyline first).
  final List<PolymarketEvent> fixedEvents;

  const GroupLandingScreen.events({
    super.key,
    required this.title,
    required List<PolymarketEvent> events,
    String? slug,
  })  : slug = slug ?? 'sports',
        fixedEvents = events;

  @override
  ConsumerState<GroupLandingScreen> createState() =>
      _GroupLandingScreenState();
}

class _GroupLandingScreenState extends ConsumerState<GroupLandingScreen> {
  /// Local, category-scoped search (user decision: each category page
  /// searches just its own events, from a bar pinned at the bottom).
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    // Live CLOB prices are watched PER ROW inside [_GroupFeedCard] with
    // narrow selects (each row also registers its outcome tokens via
    // [LiveTokenScope] so the WS actually streams them) — a page-level
    // livePriceProvider watch rebuilt the entire list on every tick.

    return Scaffold(
      extendBodyBehindAppBar: true,
      // The floating search bar lifts itself by viewInsets; letting the
      // Scaffold ALSO shrink for the keyboard doubled the lift and
      // beached the bar mid-list.
      resizeToAvoidBottomInset: false,
      backgroundColor: context.isDark ? c.gradientBottom : c.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                widget.title,
                style: TextStyle(
                  color: c.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 17.sp,
                  letterSpacing: -0.3,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        leading: const KuteBackButton(),
      ),
      body: Stack(
        children: [
          Container(decoration: AppDecorations.screenGradient(context)),
          PlatformSafeArea(
            child: Builder(
              builder: (context) {
                // Drop finished games. The whole point is to SHOW the
                // siblings, so there is no same-game collapse here.
                final collapsed = widget.fixedEvents
                    .where((e) => !e.ended)
                    .toList(growable: false);
                // Category-scoped search: plain local title match over the
                // page's own events, driven by the bottom bar below.
                final q = _query.trim().toLowerCase();
                final events = q.isEmpty
                    ? collapsed
                    : collapsed
                        .where((e) => e.title.toLowerCase().contains(q))
                        .toList(growable: false);
                if (events.isEmpty && q.isNotEmpty) {
                  return _Empty(
                    glyph: Icons.search_off_rounded,
                    message: context.l10n.groupNoMatchesIn(widget.title),
                  );
                }
                if (events.isEmpty) {
                  return _Empty(
                    glyph: polyCategoryGlyph(widget.slug),
                    message: context.l10n.betNoOpenMarketsInTopic,
                  );
                }
                return ListView.separated(
                  padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 96.h),
                  physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics()),
                  itemCount: events.length,
                  separatorBuilder: (_, __) => SizedBox(height: 10.h),
                  itemBuilder: (_, i) => _GroupFeedCard(market: events[i]),
                );
              },
            ),
          ),
          // Category-scoped search, pinned at the bottom (same glass
          // language as the app-wide bar; searches ONLY this page).
          Positioned(
            left: 12.w,
            right: 12.w,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                padding: EdgeInsets.only(
                    bottom: 8.h + MediaQuery.of(context).viewInsets.bottom),
                child: KuteGlass(
                  borderRadius: BorderRadius.circular(26.r),
                  child: SizedBox(
                    height: 52.h,
                    child: Row(
                      children: [
                        SizedBox(width: 16.w),
                        Icon(Icons.search_rounded,
                            size: 20.sp, color: c.textSecondary),
                        SizedBox(width: 10.w),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            onChanged: (v) {
                              if (v.trim().isNotEmpty) {
                                VenueAnalytics.settingChanged(
                                    'polymarket_search_opened',
                                    setting: 'query',
                                    value: 'typed',
                                    scope: 'group_${widget.title}',
                                    extra: {'surface': 'group_landing'});
                              }
                              setState(() => _query = v);
                            },
                            style: TextStyle(
                              color: c.textPrimary,
                              fontSize: 16.sp,
                              fontWeight: FontWeight.w600,
                            ),
                            decoration: InputDecoration(
                              isCollapsed: true,
                              border: InputBorder.none,
                              hintText: context.l10n.groupSearchIn(widget.title),
                              hintStyle: TextStyle(
                                color: c.textSecondary,
                                fontSize: 16.sp,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        if (_query.isNotEmpty)
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                            child: Padding(
                              padding:
                                  EdgeInsets.symmetric(horizontal: 12.w),
                              child: Icon(Icons.close_rounded,
                                  size: 18.sp, color: c.textSecondary),
                            ),
                          )
                        else
                          SizedBox(width: 16.w),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One topic-page row. A standalone ConsumerWidget (repo rule: lazy-list
/// items reading Theme must be their own widget classes) that watches
/// ONLY its own tokens' slices of [livePriceProvider], so a WS tick
/// repaints just the rows it touches instead of the whole page.
class _GroupFeedCard extends ConsumerWidget {
  final PolymarketEvent market;
  const _GroupFeedCard({required this.market});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokenIds = <String>[
      for (final o in market.outcomes)
        if (o.tokenId != null && o.tokenId!.isNotEmpty) o.tokenId!,
    ];
    final cardLivePrices = <String, double>{};
    final cardDirections = <String, int>{};
    for (final t in tokenIds) {
      final lp = ref.watch(livePriceProvider.select((s) => s.prices[t]));
      if (lp != null) cardLivePrices[t] = lp;
      final dir =
          ref.watch(livePriceProvider.select((s) => s.priceDirection(t)));
      if (dir != 0) cardDirections[t] = dir;
    }
    return LiveTokenScope(
      tokens: tokenIds,
      child: MarketCard(
        title: market.title,
        imageUrl: market.imageUrl,
        outcomes: market.outcomes,
        volume: market.volume,
        volume24hr: market.volume24hr,
        category: market.category,
        startDate: market.startDate,
        gameStart: market.kickoff,
        endDate: market.endDate,
        active: market.active,
        closed: market.closed,
        ended: market.ended,
        livePrices: cardLivePrices,
        priceDirections: cardDirections,
        // The score Gamma seeded on the event (no live feed join here).
        liveGame: market.isSportsCategory ? PolyLiveGame.of(market, null) : null,
        dayMove: market.oneDayPriceChange,
        teams: market.teams,
        slug: market.slug,
        gameId: market.gameId,
        hasLivestream: market.hasLivestream,
        onTapDown: () => MarketDetailSheet.prefetch(market),
        onTap: () {
          HapticFeedback.mediumImpact();
          MarketDetailSheet.show(context,
              event: market, source: 'group_landing');
        },
      ),
    );
  }
}

/// Shared empty/error state for the topic page — real glyph, never a
/// blank placeholder.
class _Empty extends StatelessWidget {
  final IconData glyph;
  final String message;
  const _Empty({required this.glyph, required this.message});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 40.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(glyph, color: c.textTertiary, size: 44.sp),
            SizedBox(height: 16.h),
            Text(
              message,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 15.sp,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
