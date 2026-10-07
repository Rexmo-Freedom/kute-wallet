import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_watchlist_provider.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// The ★ that puts a Predictions market on the watchlist, on the market
/// cards and the market sheet's header.
class PolyWatchStar extends ConsumerWidget {
  final PolymarketEvent event;
  final double size;

  /// Analytics surface: card or detail.
  final String source;

  const PolyWatchStar({
    super.key,
    required this.event,
    this.size = 20,
    this.source = 'card',
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = polyWatchlistKey(event);
    if (key == null) return const SizedBox.shrink();
    final c = context.colors;
    final on = ref.watch(polyWatchlistProvider.select((l) => l.contains(key)));
    return Semantics(
      button: true,
      label: on
          ? context.l10n.polyWatchlistRemove
          : context.l10n.polyWatchlistAdd,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          final added = ref.read(polyWatchlistProvider.notifier).toggle(event);
          TrackingService.track('watchlist_toggled', params: {
            'venue': 'polymarket',
            'action': added ? 'added' : 'removed',
            if (event.category.isNotEmpty)
              'category': event.category.toLowerCase(),
            'source': source,
            'list_size': ref.read(polyWatchlistProvider).length,
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
