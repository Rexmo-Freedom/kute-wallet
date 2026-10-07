import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_watchlist_provider.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/venue_analytics.dart';
import 'package:kute/theme/app_theme.dart';

/// The ★ that puts an Investing market on the watchlist, on the market
/// sheet's header. The same star, size and event as the Predictions one
/// (PolyWatchStar); starred markets list under the Watchlist pill.
class HlWatchStar extends ConsumerWidget {
  final HlMarket market;
  final double size;

  /// Analytics surface.
  final String source;

  const HlWatchStar({
    super.key,
    required this.market,
    this.size = 20,
    this.source = 'detail',
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final key = hlWatchlistKey(market);
    final on = ref.watch(hlWatchlistProvider.select((l) => l.contains(key)));
    return Semantics(
      button: true,
      label: on
          ? context.l10n.polyWatchlistRemove
          : context.l10n.polyWatchlistAdd,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          final added = ref.read(hlWatchlistProvider.notifier).toggle(market);
          // The Predictions event, with this venue's public market facts:
          // the symbol and what kind of market it is. Never an id.
          TrackingService.track('watchlist_toggled', params: {
            'venue': 'hyperliquid',
            'action': added ? 'added' : 'removed',
            'category': market.category,
            'source': source,
            'list_size': ref.read(hlWatchlistProvider).length,
            'coin': market.coin,
            'kind': market.isSpot ? 'spot' : 'perp',
            ...VenueAnalytics.hlAssetParams(market.coin,
                kind: market.isSpot ? 'spot' : 'perp'),
          });
        },
        child: Padding(
          padding: EdgeInsets.all(4.w),
          child: Icon(
            on ? Icons.star_rounded : Icons.star_border_rounded,
            size: size.sp,
            color: on ? const Color(0xFFF5B301) : c.textTertiary,
          ),
        ),
      ),
    );
  }
}
