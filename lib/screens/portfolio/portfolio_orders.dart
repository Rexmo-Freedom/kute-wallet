// lib/screens/portfolio/portfolio_orders.dart
//
// The account's resting orders from both venues — a running Investing
// TWAP, a resting Investing order, a resting Predictions limit order —
// each as the row its venue's own sheet draws (HlTwapRow, HlOrderRow,
// PolyOrderRow), with its own Cancel. Since 28 October 2026 (founder
// decision) they are listed UNDER THEIR VENUE on Investments → Portfolio
// → P&L charts (portfolio_statistics.dart, PortfolioStatisticsOverview):
// Predictions' orders under the Predictions row, Investing's under the
// Investing row, newest first within a venue ([predictionsItems],
// [investingItems]); orders Hyperliquid ended on its own this session
// keep their place at the end of Investing's under their own small
// heading, as the Investing sheet lists them: the reason the venue gave
// is the point of the row. No Orders heading and no count any more; one
// quiet "Cancel all" text link ([PortfolioCancelAllLink]) after the last
// venue's orders, only when orders rest at BOTH venues: it runs each
// venue's own cancel-all routine in turn (hlCancelAllOrders,
// polyCancelAllOrders), so the receipt, the events and the error wording
// are exactly the venue sheets'. A venue the shell draws no tab for
// (portfolio_filters.dart) is not read and has no rows.
//
// The one merged list ([rows], [items]) stays for [PortfolioPositions],
// the positions as a page of their own.

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
    required this.investingRows,
    required this.predictionsRows,
    required this.ended,
    required this.loading,
    required this.investingLoading,
    required this.predictionsLoading,
    required this.predictionsFailed,
    required this.investing,
    required this.predictions,
  });

  /// Every resting order and running TWAP, each its venue sheet's row,
  /// newest first.
  final List<Widget> rows;

  /// The same rows, one venue's at a time, newest first.
  final List<Widget> investingRows;
  final List<Widget> predictionsRows;

  /// Orders Hyperliquid ended on its own this session, newest first.
  final List<HlOrderUpdate> ended;

  /// Nothing listed yet and a venue still reading.
  final bool loading;

  /// A venue still reading with nothing of its own listed.
  final bool investingLoading;
  final bool predictionsLoading;

  /// The Predictions read failed: the venue sheet's retry leads.
  final bool predictionsFailed;

  /// Which venues have something to cancel.
  final bool investing;
  final bool predictions;

  /// Nothing to list at all: no order, nothing ended, no failure.
  bool get isEmpty => rows.isEmpty && ended.isEmpty && !predictionsFailed;

  /// Orders rest at both venues: the one Cancel all is offered.
  bool get both => investing && predictions;

  /// A venue has something to list under its row (or a failure to retry).
  bool get investingAny => investingRows.isNotEmpty || ended.isNotEmpty;
  bool get predictionsAny => predictionsRows.isNotEmpty || predictionsFailed;

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

    final investingRows = <(int placedMs, Widget row)>[
      for (final t in twaps)
        (
          t.startedAt.millisecondsSinceEpoch,
          HlTwapRow(key: ValueKey('hl-twap-${t.twapId}'), twap: t)
        ),
      for (final o in hlOrders)
        (o.timestamp, HlOrderRow(key: ValueKey('hl-order-${o.oid}'), order: o)),
    ];
    final predictionsRows = <(int placedMs, Widget row)>[
      for (final o in pmOrders)
        (
          polyOrderPlacedMs(o),
          PolyOrderRow(key: ValueKey('pm-order-${o.id}'), order: o)
        ),
    ];
    int newestFirst((int, Widget) a, (int, Widget) b) => b.$1.compareTo(a.$1);
    final rows = [...investingRows, ...predictionsRows]..sort(newestFirst);
    investingRows.sort(newestFirst);
    predictionsRows.sort(newestFirst);
    final hlLoading = hl?.isLoading ?? false;
    final pmLoading = pm?.isLoading ?? false;

    return PortfolioOrdersBook._(
      rows: [for (final row in rows) row.$2],
      investingRows: [for (final row in investingRows) row.$2],
      predictionsRows: [for (final row in predictionsRows) row.$2],
      ended: ended,
      loading: rows.isEmpty && (hlLoading || pmLoading),
      investingLoading: investingRows.isEmpty && hlLoading,
      predictionsLoading: predictionsRows.isEmpty && pmLoading,
      predictionsFailed: pm?.hasError ?? false,
      investing: hlOrders.isNotEmpty || twaps.isNotEmpty,
      predictions: pmOrders.isNotEmpty,
    );
  }

  /// Predictions' orders as the rows under its venue row on P&L charts:
  /// the retry when the read failed, then the rows newest first, each
  /// spaced as the venue sheet spaces its own. Nothing when there is
  /// nothing.
  List<Widget> predictionsItems(BuildContext context, WidgetRef ref) => [
        if (predictionsFailed)
          _spaced(Center(
            child: TextButton.icon(
              key: const ValueKey('portfolio-orders-predictions-retry'),
              onPressed: () => ref.invalidate(polymarketOpenOrdersProvider),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(context.l10n.retry),
            ),
          )),
        for (final row in predictionsRows) _spaced(row),
      ];

  /// Investing's orders as the rows under its venue row on P&L charts:
  /// the running TWAPs and resting orders newest first, then the orders
  /// Hyperliquid ended this session under their own small heading.
  List<Widget> investingItems(BuildContext context, WidgetRef ref) => [
        for (final row in investingRows) _spaced(row),
        ..._endedItems(context),
      ];

  /// The list's items: the Orders heading with the count and one Cancel
  /// all ([header], the app's section heading), the Predictions retry when
  /// that read failed, the rows, then the ended orders under their own
  /// heading. Nothing when [isEmpty]. [PortfolioPositions]' merged list.
  List<Widget> items(BuildContext context, WidgetRef ref,
      {required Widget Function(Widget? trailing) header}) {
    if (isEmpty) return const [];
    final c = context.colors;
    final l10n = context.l10n;
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
                PortfolioCancelAllLink(
                    investing: investing, predictions: predictions),
              ],
            )),
      if (predictionsFailed)
        _spaced(Center(
          child: TextButton.icon(
            onPressed: () => ref.invalidate(polymarketOpenOrdersProvider),
            icon: const Icon(Icons.refresh_rounded),
            label: Text(l10n.retry),
          ),
        )),
      for (final row in rows) _spaced(row),
      ..._endedItems(context),
    ];
  }

  /// The orders Hyperliquid ended this session, under their small heading.
  List<Widget> _endedItems(BuildContext context) {
    if (ended.isEmpty) return const [];
    return [
      _spaced(Padding(
        padding: EdgeInsets.only(top: 8.h),
        child: Text(
          context.l10n.hlOrdersEndedTitle,
          style: TextStyle(
            color: context.colors.textTertiary,
            fontSize: 13.sp,
            fontWeight: FontWeight.w700,
          ),
        ),
      )),
      for (final u in ended)
        _spaced(HlEndedOrderRow(
            key: ValueKey('hl-ended-${u.oid}-${u.statusTimestamp}'),
            update: u)),
    ];
  }

  static Widget _spaced(Widget child) =>
      Padding(padding: EdgeInsets.only(bottom: 10.h), child: child);
}

/// Cancels every resting order at both venues, each venue's own routine
/// in turn: a quiet text link (founder style, no button) at the end of
/// the last venue's orders; dimmed while it runs.
class PortfolioCancelAllLink extends ConsumerStatefulWidget {
  const PortfolioCancelAllLink(
      {super.key, required this.investing, required this.predictions});

  /// Which venues have something to cancel.
  final bool investing;
  final bool predictions;

  @override
  ConsumerState<PortfolioCancelAllLink> createState() =>
      _PortfolioCancelAllLinkState();
}

class _PortfolioCancelAllLinkState
    extends ConsumerState<PortfolioCancelAllLink> {
  bool _busy = false;

  Future<void> _cancelAll() async {
    if (_busy) return;
    setState(() => _busy = true);
    HapticFeedback.lightImpact();
    try {
      if (widget.investing) await hlCancelAllOrders(context, ref);
      if (widget.predictions && mounted)
        await polyCancelAllOrders(context, ref);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = context.l10n.ordersCancelAll;
    return Semantics(
      button: true,
      enabled: !_busy,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        key: const ValueKey('portfolio-orders-cancel-all'),
        behavior: HitTestBehavior.opaque,
        onTap: _busy ? null : _cancelAll,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8.h),
          child: Text(
            label,
            style: TextStyle(
              color: _busy ? c.textTertiary : c.textSecondary,
              fontSize: 13.sp,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1,
              height: 1.3,
            ),
          ),
        ),
      ),
    );
  }
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
