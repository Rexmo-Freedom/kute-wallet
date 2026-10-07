import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_sports_provider.dart'
    show sportsLiveProvider, sportsUpdateFor;
import 'package:kute/screens/polymarket/components/live_game.dart';
import 'package:kute/screens/polymarket/components/live_token_scope.dart';
import 'package:kute/screens/polymarket/components/market_card.dart';
import 'package:kute/screens/shared/category_pill_strip.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// Public market data only. Account balances and execution remain with the
/// caller; a category sheet keeps the same explicit market callback.
class InvestmentBrowseSection<T> {
  const InvestmentBrowseSection({required this.label, required this.markets});

  final String label;
  final List<T> markets;
}

/// The Home feeds' section header: bold label plus chevron, the whole row
/// tappable when [onTap] is set.
class InvestmentSectionHeader extends StatelessWidget {
  const InvestmentSectionHeader({super.key, required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: EdgeInsets.fromLTRB(20.w, 18.h, 16.w, 10.h),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 22.sp,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ),
          if (onTap != null)
            Icon(Icons.chevron_right_rounded,
                color: context.colors.textSecondary, size: 22.sp),
        ],
      ),
    );
    if (onTap == null) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap!();
      },
      child: row,
    );
  }
}

class InvestmentMarketBrowser<T> extends StatelessWidget {
  const InvestmentMarketBrowser({
    super.key,
    required this.sections,
    required this.product,
    required this.cardBuilder,
    required this.onOpenMarket,
    this.leading,
  });

  final List<InvestmentBrowseSection<T>> sections;
  final String product;
  final Widget Function(T market, VoidCallback onTap) cardBuilder;
  final ValueChanged<T> onOpenMarket;

  /// Shown between the category pills and the first section, like Home's
  /// 5 Minute Markets block.
  final Widget? leading;

  /// Opens the category as a FULL SCREEN, the way Home does. A Ledger
  /// used to get a bottom sheet here, which made the same action look
  /// like a different product depending on the account you were in
  /// (user decision September 2026: Ledger always matches Home).
  void _openCategory(BuildContext context, InvestmentBrowseSection<T> section) {
    TrackingService.track('investment_category_opened',
        params: {'product': product, 'source': 'account'});
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => _CategoryPage<T>(
          title: section.label,
          markets: section.markets,
          cardBuilder: cardBuilder,
          onOpenMarket: onOpenMarket,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nonempty = sections.where((s) => s.markets.isNotEmpty).toList();
    if (nonempty.isEmpty) return leading ?? const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CategoryPillStrip(
          labels: [for (final section in nonempty) section.label],
          onTap: (index) => _openCategory(context, nonempty[index]),
        ),
        if (leading != null) leading!,
        for (final section in nonempty) ...[
          InvestmentSectionHeader(
            label: section.label,
            onTap: () => _openCategory(context, section),
          ),
          for (final market in section.markets.take(6))
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 12.h),
              child: cardBuilder(market, () => onOpenMarket(market)),
            ),
        ],
      ],
    );
  }
}

/// The Home market card with public live prices and caller-owned navigation.
/// No outcome button gets a trading callback from this read-only wrapper.
class PredictionBrowseCard extends ConsumerWidget {
  const PredictionBrowseCard({
    super.key,
    required this.event,
    this.onTap,
    this.followLiveGame = false,
  });

  final PolymarketEvent event;
  final VoidCallback? onTap;

  /// Read the game's score and clock from the live sports feed (as the
  /// Predictions list does) instead of only the event's seed. Only this
  /// game's update is watched.
  final bool followLiveGame;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = [
      for (final outcome in event.outcomes)
        if (outcome.tokenId != null && outcome.tokenId!.isNotEmpty)
          outcome.tokenId!,
    ];
    final livePrices = <String, double>{};
    final directions = <String, int>{};
    for (final token in tokens) {
      final price = ref.watch(livePriceProvider.select((s) => s.prices[token]));
      if (price != null) livePrices[token] = price;
      directions[token] =
          ref.watch(livePriceProvider.select((s) => s.priceDirection(token)));
    }
    final update = followLiveGame
        ? ref.watch(sportsLiveProvider.select((m) => sportsUpdateFor(m,
            slug: event.slug,
            gameId: event.gameId,
            metadataGameId: event.metadataGameId)))
        : null;
    return LiveTokenScope(
      tokens: tokens,
      child: MarketCard(
        title: event.title,
        imageUrl: event.imageUrl,
        outcomes: event.outcomes,
        volume: event.volume,
        volume24hr: event.volume24hr,
        category: event.category,
        startDate: event.startDate,
        gameStart: event.kickoff,
        endDate: event.endDate,
        active: event.active,
        closed: event.closed,
        ended: event.ended,
        // The score Gamma seeded on the event, or the live feed's when
        // [followLiveGame].
        liveGame: event.isSportsCategory || update != null
            ? PolyLiveGame.of(event, update)
            : null,
        dayMove: event.oneDayPriceChange,
        teams: event.teams,
        slug: event.slug,
        gameId: event.gameId,
        hasLivestream: event.hasLivestream,
        livePrices: livePrices,
        priceDirections: directions,
        onTap: onTap,
      ),
    );
  }
}

/// The category list as its own screen, in the chrome Home's category
/// page uses: transparent app bar over the screen gradient, a back
/// button and a centred title.
class _CategoryPage<T> extends StatelessWidget {
  const _CategoryPage({
    required this.title,
    required this.markets,
    required this.cardBuilder,
    required this.onOpenMarket,
  });

  final String title;
  final List<T> markets;
  final Widget Function(T market, VoidCallback onTap) cardBuilder;
  final void Function(T market) onOpenMarket;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: context.isDark ? c.gradientBottom : c.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: c.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 17.sp,
            letterSpacing: -0.3,
          ),
        ),
        leading: const KuteBackButton(),
      ),
      body: Stack(
        children: [
          Container(decoration: AppDecorations.screenGradient(context)),
          PlatformSafeArea(
            child: ListView.separated(
              padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 24.h),
              itemCount: markets.length,
              separatorBuilder: (_, __) => SizedBox(height: 12.h),
              itemBuilder: (_, index) {
                final market = markets[index];
                return cardBuilder(market, () => onOpenMarket(market));
              },
            ),
          ),
        ],
      ),
    );
  }
}
