// lib/screens/portfolio/portfolio_orders.dart
//
// The Portfolio's Orders tab (one balance, October 2026): ONE list of the
// account's open orders from both venues, newest first — a running
// Investing TWAP, a resting Investing order, a resting Predictions limit
// order — each as the row its venue's own sheet draws (HlTwapRow,
// HlOrderRow, PolyOrderRow), with no Investing | Predictions switch above
// it (owner decision: the Portfolio's third rows are gone). Orders
// Hyperliquid ended on its own this session keep their place at the end
// under their own heading, as the Investing sheet lists them: the reason
// the venue gave is the point of the row.
//
// One count and one Cancel all over the list: the button runs each
// venue's own cancel-all routine in turn (hlCancelAllOrders,
// polyCancelAllOrders), so the receipt, the events and the error wording
// are exactly the venue sheets'. A venue the shell draws no tab for
// (portfolio_filters.dart) is not read and has no rows.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart' show Order;

import 'package:kute/helpers/hyperliquid_order_status.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/hyperliquid_user_events_provider.dart';
import 'package:kute/providers/polymarket_open_orders_provider.dart';
import 'package:kute/screens/home/components/kute_dock_host.dart'
    show kuteDockScrollClearance;
import 'package:kute/screens/hyperliquid/components/open_orders_sheet.dart'
    show HlEndedOrderRow, HlOrderRow, HlTwapRow, hlCancelAllOrders;
import 'package:kute/screens/polymarket/components/open_orders_sheet.dart'
    show PolyOrderRow, polyCancelAllOrders;
import 'package:kute/screens/portfolio/portfolio_empty_state.dart';
import 'package:kute/screens/portfolio/portfolio_filters.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/services/hyperliquid/hyperliquid_websocket.dart'
    show HlOrderUpdate;
import 'package:kute/theme/app_theme.dart';

/// When a Predictions order was placed, epoch ms (the CLOB's unix-seconds
/// string); zero when the venue gave no time, which sorts it last.
int polyOrderPlacedMs(Order order) =>
    (int.tryParse(order.timestamp ?? '') ?? 0) * 1000;

/// The merged open-orders list (see the file header).
class PortfolioOpenOrders extends ConsumerWidget {
  const PortfolioOpenOrders({super.key, required this.venues});

  final PortfolioVenues venues;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final l10n = context.l10n;

    // Investing: resting orders and running TWAPs from the trading state,
    // orders the venue ended this session from the user-events socket.
    final hl = venues.trading ? ref.watch(hyperliquidTradingProvider) : null;
    final hlOrders = hl?.valueOrNull?.openOrders ?? const <HlOpenOrder>[];
    final twaps = (hl?.valueOrNull?.runningTwaps ?? const <HlRunningTwap>[])
        .where((t) => !t.expired)
        .toList();
    final ended = venues.trading
        ? ref
            .watch(hyperliquidUserEventsProvider
                .select((s) => s.recentOrderUpdates))
            .where((u) => hlStatusIsVenueDecision(u.status))
            .toList()
            .reversed
            .take(10)
            .toList()
        : const <HlOrderUpdate>[];
    // Predictions: the resting limit orders, polled while this is open.
    final pm = venues.predictions ? ref.watch(polymarketOpenOrdersProvider) : null;
    final pmOrders = pm?.valueOrNull ?? const <Order>[];

    final rows = <(int placedMs, Widget row)>[
      for (final t in twaps)
        (
          t.startedAt.millisecondsSinceEpoch,
          HlTwapRow(key: ValueKey('hl-twap-${t.twapId}'), twap: t)
        ),
      for (final o in hlOrders)
        (o.timestamp, HlOrderRow(key: ValueKey('hl-order-${o.oid}'), order: o)),
      for (final o in pmOrders)
        (
          polyOrderPlacedMs(o),
          PolyOrderRow(key: ValueKey('pm-order-${o.id}'), order: o)
        ),
    ]..sort((a, b) => b.$1.compareTo(a.$1));

    final loading = rows.isEmpty &&
        ((hl?.isLoading ?? false) || (pm?.isLoading ?? false));
    final pmFailed = pm?.hasError ?? false;

    if (loading) return const _OrdersSkeleton();
    if (rows.isEmpty && ended.isEmpty && !pmFailed) {
      // The empty state every Portfolio tab shows; the headline is the
      // string's first line (its second is an explanatory note).
      return PortfolioEmptyState(l10n.betNoRestingOrders.split('\n').first);
    }

    final items = <Widget>[
      // The Predictions read failed: the venue sheet's own retry, over
      // whatever the other venue could list.
      if (pmFailed)
        Center(
          child: TextButton.icon(
            onPressed: () => ref.invalidate(polymarketOpenOrdersProvider),
            icon: const Icon(Icons.refresh_rounded),
            label: Text(l10n.retry),
          ),
        ),
      for (final row in rows) row.$2,
      if (ended.isNotEmpty) ...[
        Padding(
          padding: EdgeInsets.only(top: 8.h),
          child: Text(
            l10n.hlOrdersEndedTitle,
            style: TextStyle(
              color: c.textTertiary,
              fontSize: 13.sp,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        for (final u in ended)
          HlEndedOrderRow(
              key: ValueKey('hl-ended-${u.oid}-${u.statusTimestamp}'),
              update: u),
      ],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The count and Cancel all, right-aligned as on the venue sheets
        // (the strip's Orders label above is the title).
        if (rows.isNotEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 10.h, 16.w, 12.h),
            child: Row(
              children: [
                const Spacer(),
                Text(
                  '${rows.length}',
                  key: const ValueKey('portfolio-orders-count'),
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w700,
                    color: c.textTertiary,
                  ),
                ),
                SizedBox(width: 10.w),
                _CancelAllButton(
                    investing: hlOrders.isNotEmpty || twaps.isNotEmpty,
                    predictions: pmOrders.isNotEmpty),
              ],
            ),
          ),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.fromLTRB(16.w, rows.isEmpty ? 4.h : 0, 16.w,
                20.h + kuteDockScrollClearance(context)),
            itemCount: items.length,
            separatorBuilder: (_, __) => SizedBox(height: 10.h),
            itemBuilder: (_, i) => items[i],
          ),
        ),
      ],
    );
  }
}

/// Cancels every resting order at both venues, each venue's own routine
/// in turn; the venue sheets' button chrome.
class _CancelAllButton extends ConsumerStatefulWidget {
  const _CancelAllButton({required this.investing, required this.predictions});

  /// Which venues have something to cancel.
  final bool investing;
  final bool predictions;

  @override
  ConsumerState<_CancelAllButton> createState() => _CancelAllButtonState();
}

class _CancelAllButtonState extends ConsumerState<_CancelAllButton> {
  bool _busy = false;

  Future<void> _cancelAll() async {
    if (_busy) return;
    setState(() => _busy = true);
    HapticFeedback.lightImpact();
    try {
      if (widget.investing) await hlCancelAllOrders(context, ref);
      if (widget.predictions && mounted) await polyCancelAllOrders(context, ref);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 112.w,
        child: AppButton(
          key: const ValueKey('portfolio-orders-cancel-all'),
          text: context.l10n.ordersCancelAll,
          variant: AppButtonVariant.secondary,
          compact: true,
          isLoading: _busy,
          onPressed: _busy ? null : _cancelAll,
        ),
      );
}

/// Skeleton order rows shaped like the venue rows while either venue
/// first loads (the Investing sheet's skeleton).
class _OrdersSkeleton extends StatelessWidget {
  const _OrdersSkeleton();

  @override
  Widget build(BuildContext context) => KuteSkeleton(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 0),
          child: Column(
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) SizedBox(height: 10.h),
                SkeletonCard(
                  radius: 14.r,
                  padding: EdgeInsets.all(12.w),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          SkeletonBar(42.w, 20.h),
                          SizedBox(width: 8.w),
                          SkeletonBar(60.w, 14.h),
                          const Spacer(),
                          SkeletonBar(64.w, 26.h, radius: 8.r),
                        ],
                      ),
                      SizedBox(height: 10.h),
                      Row(
                        children: [
                          SkeletonBar(100.w, 11.h),
                          const Spacer(),
                          SkeletonBar(70.w, 11.h),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      );
}
