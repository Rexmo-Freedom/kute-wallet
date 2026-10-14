// lib/screens/portfolio/portfolio_orders.dart
//
// The resting orders under Positions (the Investments tab's third pill,
// October 2026; they were the Portfolio's Orders tab): ONE list of the
// account's open orders from both venues, newest first — a running
// Investing TWAP, a resting Investing order, a resting Predictions limit
// order — each as the row its venue's own sheet draws (HlTwapRow,
// HlOrderRow, PolyOrderRow), with no Investing | Predictions switch above
// it. Orders Hyperliquid ended on its own this session keep their place
// at the end under their own heading, as the Investing sheet lists them:
// the reason the venue gave is the point of the row.
//
// One Orders heading over them, with one count and one Cancel all: the
// button runs each venue's own cancel-all routine in turn
// (hlCancelAllOrders, polyCancelAllOrders), so the receipt, the events
// and the error wording are exactly the venue sheets'. A venue the shell
// draws no tab for (portfolio_filters.dart) is not read and has no rows.

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
import 'package:kute/screens/hyperliquid/components/open_orders_sheet.dart'
    show HlEndedOrderRow, HlOrderRow, HlTwapRow, hlCancelAllOrders;
import 'package:kute/screens/polymarket/components/open_orders_sheet.dart'
    show PolyOrderRow, polyCancelAllOrders;
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

/// Both venues' open orders as Positions lists them under its positions
/// (see the file header): the rows newest first, the orders the venue
/// ended this session, and what is still loading or failed.
class PortfolioOrdersBook {
  const PortfolioOrdersBook._({
    required this.rows,
    required this.ended,
    required this.loading,
    required this.predictionsFailed,
    required this.investing,
    required this.predictions,
  });

  /// Every resting order and running TWAP, each its venue sheet's row,
  /// newest first.
  final List<Widget> rows;

  /// Orders Hyperliquid ended on its own this session, newest first.
  final List<HlOrderUpdate> ended;

  /// Nothing listed yet and a venue still reading.
  final bool loading;

  /// The Predictions read failed: the venue sheet's retry leads.
  final bool predictionsFailed;

  /// Which venues have something to cancel.
  final bool investing;
  final bool predictions;

  /// Nothing to list at all: no order, nothing ended, no failure.
  bool get isEmpty => rows.isEmpty && ended.isEmpty && !predictionsFailed;

  /// Reads both venues' orders for [venues] (a venue the shell draws no
  /// tab for is not read).
  static PortfolioOrdersBook watch(WidgetRef ref, PortfolioVenues venues) {
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
    final pm =
        venues.predictions ? ref.watch(polymarketOpenOrdersProvider) : null;
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

    return PortfolioOrdersBook._(
      rows: [for (final row in rows) row.$2],
      ended: ended,
      loading: rows.isEmpty &&
          ((hl?.isLoading ?? false) || (pm?.isLoading ?? false)),
      predictionsFailed: pm?.hasError ?? false,
      investing: hlOrders.isNotEmpty || twaps.isNotEmpty,
      predictions: pmOrders.isNotEmpty,
    );
  }

  /// The list's items: the Orders heading with the count and one Cancel
  /// all ([header], the app's section heading), the Predictions retry when
  /// that read failed, the rows, then the ended orders under their own
  /// heading. Nothing when [isEmpty].
  List<Widget> items(BuildContext context, WidgetRef ref,
      {required Widget Function(Widget? trailing) header}) {
    if (isEmpty) return const [];
    final c = context.colors;
    final l10n = context.l10n;
    Widget spaced(Widget child) =>
        Padding(padding: EdgeInsets.only(bottom: 10.h), child: child);
    return [
      header(rows.isEmpty
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                _CancelAllButton(investing: investing, predictions: predictions),
              ],
            )),
      if (predictionsFailed)
        spaced(Center(
          child: TextButton.icon(
            onPressed: () => ref.invalidate(polymarketOpenOrdersProvider),
            icon: const Icon(Icons.refresh_rounded),
            label: Text(l10n.retry),
          ),
        )),
      for (final row in rows) spaced(row),
      if (ended.isNotEmpty) ...[
        spaced(Padding(
          padding: EdgeInsets.only(top: 8.h),
          child: Text(
            l10n.hlOrdersEndedTitle,
            style: TextStyle(
              color: c.textTertiary,
              fontSize: 13.sp,
              fontWeight: FontWeight.w700,
            ),
          ),
        )),
        for (final u in ended)
          spaced(HlEndedOrderRow(
              key: ValueKey('hl-ended-${u.oid}-${u.statusTimestamp}'),
              update: u)),
      ],
    ];
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
/// first loads (the Investing sheet's skeleton), with nothing else to
/// show.
class PortfolioOrdersSkeleton extends StatelessWidget {
  const PortfolioOrdersSkeleton({super.key});

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
