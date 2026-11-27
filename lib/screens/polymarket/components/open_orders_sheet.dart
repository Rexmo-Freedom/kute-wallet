import 'package:kute/screens/polymarket/components/position_card.dart';
import 'package:kute/screens/shared/portfolio_position_card.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/venue_analytics.dart';
import 'package:kute/providers/ledger/ledger_pm_open_orders_provider.dart';
import 'package:kute/providers/ledger/ledger_polymarket_account_provider.dart';
// Open (resting, unfilled) GTC limit orders — the trading side of
// Predictions. Lists each order with its resting price, fill progress, and
// how far the market is from filling it, plus a per-order Cancel.
import 'package:flutter/material.dart';
import 'package:kute/screens/home/components/kute_dock_host.dart'
    show KuteDockClearance, kuteDockScrollClearance;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart' show Order;

import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_open_orders_provider.dart';
import 'package:kute/providers/polymarket_order_metadata_provider.dart';
import 'package:kute/providers/polymarket_resting_fills_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/screens/polymarket/components/price_format.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/screens/shared/sal_notices.dart';
import 'package:kute/screens/usd/usd_account_screen.dart'
    show openInvestmentsOrders;
import 'package:kute/theme/app_theme.dart';


/// Relative "placed 2h ago" from the CLOB order's unix-seconds timestamp.
/// Answers "when did I enter this order" — a limit order can rest for a
/// while before the market reaches it, so the entry time matters.
String _placedAgo(BuildContext context, String? ts) {
  final secs = int.tryParse(ts ?? '');
  if (secs == null || secs <= 0) return '';
  final placed = DateTime.fromMillisecondsSinceEpoch(secs * 1000);
  final diff = DateTime.now().difference(placed);
  if (diff.isNegative) return context.l10n.betPlacedJustNow;
  if (diff.inSeconds < 60) return context.l10n.betPlacedJustNow;
  if (diff.inMinutes < 60) {
    return context.l10n.betPlacedMinutesAgo(diff.inMinutes);
  }
  if (diff.inHours < 24) return context.l10n.betPlacedHoursAgo(diff.inHours);
  return context.l10n.betPlacedDaysAgo(diff.inDays);
}

class OpenOrdersSheet extends ConsumerWidget {
  final bool embedded;
  final String? ledgerWalletId;
  const OpenOrdersSheet(
      {super.key, this.embedded = false, this.ledgerWalletId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final walletId = ledgerWalletId;
    final AsyncValue<List<Order>?> ordersAsync = walletId == null
        ? ref.watch(polymarketOpenOrdersProvider)
        : ref.watch(ledgerPmOpenOrdersProvider(walletId));
    void refresh() {
      if (walletId == null) {
        ref.invalidate(polymarketOpenOrdersProvider);
      } else {
        ref.invalidate(ledgerPmOpenOrdersProvider(walletId));
      }
    }

    final orders = ordersAsync.valueOrNull ?? const <Order>[];

    return Container(
      constraints: embedded
          ? null
          : BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85),
      decoration: BoxDecoration(
        color: embedded ? null : c.surface,
        borderRadius:
            embedded ? null : BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      child: SafeArea(
        top: false,
        bottom: !embedded,
        child: Padding(
          // Embedded in the Portfolio, the list runs on under the dock
          // and keeps its own bottom room (below).
          padding: EdgeInsets.fromLTRB(20.w, 14.h, 20.w, embedded ? 0 : 20.h),
          child: Column(
            mainAxisSize: embedded ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!embedded) ...[
                Center(child: AppDecorations.dragHandle(context)),
                SizedBox(height: 14.h),
              ],
              if (!embedded || orders.isNotEmpty)
                Row(
                  children: [
                    if (embedded) const Spacer(),
                    if (!embedded)
                      Expanded(
                        child: Text(
                          context.l10n.betOpenOrders,
                          style: TextStyle(
                            fontSize: 20.sp,
                            fontWeight: FontWeight.w800,
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                    if (orders.isNotEmpty) ...[
                      _CancelAllButton(ledgerWalletId: walletId),
                      SizedBox(width: 10.w),
                    ],
                    if (orders.isNotEmpty)
                      Text(
                        '${orders.length}',
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w700,
                          color: c.textTertiary,
                        ),
                      ),
                  ],
                ),
              SizedBox(height: 12.h),
              if (ordersAsync.isLoading && orders.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 28.h),
                  child: Center(
                    child: Text(
                      context.l10n.betLoadingEllipsis,
                      style: TextStyle(color: c.textTertiary, fontSize: 14.sp),
                    ),
                  ),
                )
              else if (ordersAsync.hasError)
                TextButton.icon(
                  onPressed: refresh,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(context.l10n.retry),
                )
              else if (walletId != null && ordersAsync.valueOrNull == null)
                _emptyOrders(
                    c,
                    context.l10n.pmOrdersConnectLedger,
                    embedded)
              else if (orders.isEmpty)
                // Centred in the tab like every other empty portfolio
                // view (user decision), not pinned under the header.
                _emptyOrders(c, context.l10n.betNoRestingOrders, embedded)
              else
                Flexible(
                  fit: embedded ? FlexFit.tight : FlexFit.loose,
                  child: ListView.separated(
                    shrinkWrap: !embedded,
                    padding: embedded
                        ? EdgeInsets.only(
                            bottom: 20.h + kuteDockScrollClearance(context))
                        : null,
                    itemCount: orders.length,
                    separatorBuilder: (_, __) => SizedBox(height: 10.h),
                    itemBuilder: (_, i) => PolyOrderRow(
                        key: ValueKey('$walletId:${orders[i].id}'),
                        order: orders[i],
                        ledgerWalletId: walletId),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A resting Predictions limit order with its Cancel. Public: the
/// Portfolio's merged Orders list draws the same row.
class PolyOrderRow extends ConsumerStatefulWidget {
  final Order order;
  final String? ledgerWalletId;
  const PolyOrderRow({super.key, required this.order, this.ledgerWalletId});

  @override
  ConsumerState<PolyOrderRow> createState() => _OrderRowState();
}

class _OrderRowState extends ConsumerState<PolyOrderRow> {
  bool _cancelling = false;

  Future<void> _cancel() async {
    if (_cancelling) return;
    setState(() => _cancelling = true);
    HapticFeedback.lightImpact();
    final walletKind = widget.ledgerWalletId == null ? 'hot' : 'ledger';
    try {
      final walletId = widget.ledgerWalletId;
      if (walletId == null) {
        // Its leaving the list is this cancel, never a fill to announce.
        ref
            .read(polymarketRestingFillsProvider.notifier)
            .noteCancelled([widget.order.id]);
        await ref
            .read(polymarketTradingProvider.notifier)
            .cancelOrder(widget.order.id);
      } else {
        await cancelLedgerPmOrder(ref, walletId, widget.order.id);
      }
      TrackingService.track('polymarket_order_cancelled', params: {
        'venue': 'polymarket',
        'scope': 'single',
        'wallet_kind': walletKind,
        'market_id': widget.order.assetId,
        ...VenueAnalytics.pmKindParams([widget.order.assetId]),
      });
    } catch (e) {
      TrackingService.track('polymarket_order_cancel_failed', params: {
        'venue': 'polymarket',
        'scope': 'single',
        'wallet_kind': walletKind,
        'error_category': TrackingService.errorCategory(e),
      });
      if (mounted) {
        showMessageSnackBar(
          context: context,
          message: context.l10n.betCouldNotCancel,
          error: true,
        );
      }
    } finally {
      if (mounted) {
        if (widget.ledgerWalletId == null) {
          ref.invalidate(polymarketOpenOrdersProvider);
        } else {
          ref.invalidate(ledgerPmOpenOrdersProvider(widget.ledgerWalletId!));
        }
        setState(() => _cancelling = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final o = widget.order;
    final walletId = widget.ledgerWalletId;
    final metadata = walletId == null
        ? (ref.watch(polymarketOrderMetadataProvider).valueOrNull?[o.market])
        : ref.watch(polymarketMarketMetadataProvider(o.market)).valueOrNull;
    final positions = walletId == null
        ? ref.watch(polymarketTradingProvider
            .select((s) => s.valueOrNull?.openPositions ?? const []))
        : ref.watch(ledgerPmAccountProvider(walletId)).valueOrNull?.positions ??
            const [];
    final position =
        positions.where((p) => p.conditionId == o.market).firstOrNull;
    final title =
        metadata?.title.isNotEmpty == true ? metadata!.title : position?.title;
    final imageUrl = metadata?.imageUrl.isNotEmpty == true
        ? metadata!.imageUrl
        : position?.icon ?? '';
    final isBuy = o.side.toUpperCase() == 'BUY';
    final limitPrice = double.tryParse(o.price) ?? 0;
    final original = double.tryParse(o.originalSize) ?? 0;
    final matched = double.tryParse(o.sizeMatched) ?? 0;
    final cost = original * limitPrice;
    final fillPct = original > 0
        ? (matched / original * 100).clamp(0, 100).toDouble()
        : 0.0;
    // Live market price for this token — shows how far the market is from
    // filling the order ("Market at 42¢ · your limit 39¢").
    final live = ref.watch(livePriceProvider
        .select((s) => o.assetId.isNotEmpty ? s.prices[o.assetId] : null));

    final placedAgo = _placedAgo(context, o.timestamp);
    final priceText = formatPolyCents(limitPrice);
    // Direction the market has to move for this resting order to fill. A
    // buy fills when the price drops to the limit; a sell when it rises.
    final String triggerText;
    if (isBuy) {
      triggerText = (live != null && live > limitPrice)
          ? context.l10n.betBuysWhenPriceDrops(priceText)
          : context.l10n.betBuysWhenPriceReaches(priceText);
    } else {
      triggerText = (live != null && live < limitPrice)
          ? context.l10n.betSellsWhenPriceRises(priceText)
          : context.l10n.betSellsWhenPriceReaches(priceText);
    }

    // The portfolio's card (PolyTitledCard), as the Investing order rows:
    // the title whole, the order's price on the right with its kind under
    // it, the side as one line, what it will do and how much of it has
    // filled as captions, Cancel as the app's own button under them.
    return PolyTitledCard(
      margin: EdgeInsets.zero,
      title: title?.isNotEmpty == true ? title! : context.l10n.betOrder,
      imageUrl: imageUrl,
      // "Limit · pending" makes it unmistakably a resting limit order,
      // NOT a completed position.
      trailing: PortfolioCardValue(
        value: priceText,
        detail: context.l10n.betLimitPending,
      ),
      line:
          '${isBuy ? context.l10n.betBuyUpper : context.l10n.betSellUpper} · ${o.outcome}',
      footer: [
        [
          isBuy
              ? context.l10n.betBuySharesCost(
                  original.toStringAsFixed(2), '\$${cost.toStringAsFixed(2)}')
              : context.l10n.betSellSharesCost(original.toStringAsFixed(2),
                  '\$${cost.toStringAsFixed(2)}'),
          placedAgo,
        ].where((s) => s.isNotEmpty).join(' · '),
        // Which way the market has to move for the order to fill, and
        // where it is now.
        [
          triggerText,
          if (live != null) context.l10n.betMarketPrice(formatPolyCents(live)),
        ].join(' · '),
        fillPct > 0
            ? context.l10n.betPercentFilled(fillPct.toStringAsFixed(0))
            : (isBuy
                ? context.l10n.betRestingBuyNote
                : context.l10n.betRestingSellNote),
      ],
      below: fillPct > 0
          ? Padding(
              padding: EdgeInsets.only(top: 10.h),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3.r),
                child: LinearProgressIndicator(
                  value: fillPct / 100,
                  minHeight: 4,
                  backgroundColor: c.border,
                  valueColor: AlwaysStoppedAnimation<Color>(c.textSecondary),
                ),
              ),
            )
          : null,
      action: SizedBox(
        width: 96.w,
        child: AppButton(
          text: context.l10n.cancel,
          compact: true,
          variant: AppButtonVariant.secondary,
          isLoading: _cancelling,
          onPressed: _cancelling ? null : _cancel,
        ),
      ),
    );
  }
}

class _CancelAllButton extends ConsumerStatefulWidget {
  const _CancelAllButton({this.ledgerWalletId});
  final String? ledgerWalletId;

  @override
  ConsumerState<_CancelAllButton> createState() => _CancelAllButtonState();
}

/// Cancels EVERY resting Predictions order in one batch action, with this
/// sheet's own events and error wording, and reads the list again.
/// Shared with the Portfolio's merged Orders list (portfolio_orders.dart),
/// whose one Cancel all runs each venue's routine in turn.
Future<void> polyCancelAllOrders(BuildContext context, WidgetRef ref,
    {String? ledgerWalletId}) async {
  final walletKind = ledgerWalletId == null ? 'hot' : 'ledger';
  try {
    if (ledgerWalletId == null) {
      ref.read(polymarketRestingFillsProvider.notifier).noteCancelled([
        for (final o in ref.read(polymarketTradingProvider).valueOrNull
                ?.openOrders ??
            const <Order>[])
          o.id,
        for (final o
            in ref.read(polymarketOpenOrdersProvider).valueOrNull ??
                const <Order>[])
          o.id,
      ]);
      await ref.read(polymarketTradingProvider.notifier).cancelAllOrders();
    } else {
      final orders =
          await ref.read(ledgerPmOpenOrdersProvider(ledgerWalletId).future);
      if (orders == null) throw StateError('Account unavailable');
      for (final order in orders) {
        if (!context.mounted) return;
        await cancelLedgerPmOrder(ref, ledgerWalletId, order.id);
      }
    }
    TrackingService.track('polymarket_order_cancelled', params: {
      'venue': 'polymarket',
      'scope': 'all',
      'wallet_kind': walletKind,
    });
  } catch (e) {
    TrackingService.track('polymarket_order_cancel_failed', params: {
      'venue': 'polymarket',
      'scope': 'all',
      'wallet_kind': walletKind,
      'error_category': TrackingService.errorCategory(e),
    });
    if (context.mounted) {
      showMessageSnackBar(
        context: context,
        message: context.l10n.pmOrdersCancelAllFailed,
        error: true,
      );
    }
  } finally {
    if (context.mounted) {
      if (ledgerWalletId == null) {
        ref.invalidate(polymarketOpenOrdersProvider);
      } else {
        ref.invalidate(ledgerPmOpenOrdersProvider(ledgerWalletId));
      }
    }
  }
}

class _CancelAllButtonState extends ConsumerState<_CancelAllButton> {
  bool _busy = false;

  Future<void> _cancelAll() async {
    if (_busy) return;
    final walletId = widget.ledgerWalletId;
    final orders = walletId == null
        ? ref.read(polymarketOpenOrdersProvider).valueOrNull
        : ref.read(ledgerPmOpenOrdersProvider(walletId)).valueOrNull;
    // Asks first, listing what goes (one tap per order needs no ask).
    if (!await polyConfirmCancelAll(context,
        lines: polyCancelAllLines(context, orders ?? const []))) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    HapticFeedback.lightImpact();
    try {
      await polyCancelAllOrders(context, ref,
          ledgerWalletId: widget.ledgerWalletId);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 112.w,
      child: AppButton(
        text: context.l10n.ordersCancelAll,
        variant: AppButtonVariant.secondary,
        compact: true,
        isLoading: _busy,
        onPressed: _busy ? null : _cancelAll,
      ),
    );
  }
}

/// One centred sentence filling the tab, so an empty Orders view reads
/// like every other empty portfolio view instead of sitting at the top.
Widget _emptyOrders(AppColorsExtension c, String message, bool embedded) {
  final text = Center(
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: 32),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(color: c.textSecondary, fontSize: 15.sp, height: 1.4),
      ),
    ),
  );
  return embedded
      ? Expanded(child: KuteDockClearance(child: text))
      : Padding(padding: EdgeInsets.symmetric(vertical: 28.h), child: text);
}

/// One line per resting order a Cancel all removes: "BUY · Yes · 40% ·
/// 12.50 shares".
List<String> polyCancelAllLines(BuildContext context, List<Order> orders) => [
      for (final o in orders)
        [
          o.side.toUpperCase() == 'BUY'
              ? context.l10n.betBuyUpper
              : context.l10n.betSellUpper,
          if (o.outcome.isNotEmpty) o.outcome,
          formatPolyCents(double.tryParse(o.price) ?? 0),
          context.l10n.betSharesCount(
              ((double.tryParse(o.originalSize) ?? 0) -
                      (double.tryParse(o.sizeMatched) ?? 0))
                  .clamp(0.0, double.infinity)
                  .toStringAsFixed(2)),
        ].join(' · '),
    ];

/// The app's confirm sheet before a Cancel all: what it removes, one line
/// per order ([lines], at most eight and "…" after), Cancel all or keep
/// them. True only on Cancel all.
Future<bool> polyConfirmCancelAll(BuildContext context,
    {required List<String> lines}) async {
  final l10n = context.l10n;
  final shown = lines.length > 8 ? [...lines.take(8), '…'] : lines;
  final confirmed = await showAppBottomSheet<bool>(
    context: context,
    builder: (sheetContext) => AppBottomSheetContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppBottomSheetHeader(
            title: l10n.ordersCancelAllTitle,
            subtitle: [l10n.ordersCancelAllBody(lines.length), ...shown]
                .join('\n'),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 8.h),
            child: AppBottomSheetButton(
              key: const ValueKey('orders-cancel-all-confirm'),
              text: l10n.ordersCancelAll,
              onPressed: () => Navigator.of(sheetContext).pop(true),
            ),
          ),
          AppBottomSheetTextButton(
            key: const ValueKey('orders-cancel-all-keep'),
            text: l10n.ordersKeep,
            onPressed: () => Navigator.of(sheetContext).pop(false),
          ),
        ],
      ),
    ),
  );
  return confirmed == true;
}

/// A resting order that filled, all or part, as the Sal toast: what was
/// bought or sold, at which price, and what still rests. A tap opens the
/// Portfolio's orders while part still rests.
void showPolymarketRestingFillToast(
    BuildContext context, PolymarketRestingFill fill) {
  final l10n = context.l10n;
  final price = formatPolyCents(fill.price);
  final total = fill.originalShares.toStringAsFixed(2);
  final outcome = fill.outcome;
  final String detail;
  if (fill.isBuy) {
    detail = fill.complete
        ? l10n.betLimitBoughtShares(
            fill.matchedShares.toStringAsFixed(2), outcome, price)
        : l10n.betBuyPartialLimit(
            fill.matchedShares.toStringAsFixed(2), total, price);
  } else {
    detail = fill.complete
        ? l10n.soldShares(fill.matchedShares.toStringAsFixed(2), outcome)
        : l10n.betLimitSellPartial(fill.matchedShares.toStringAsFixed(2),
            total, price, fill.remainingShares.toStringAsFixed(2));
  }
  SalNotices.placed(
    context,
    message: l10n.betLimitOrderFilled,
    detail: detail,
    onTap: fill.complete
        ? null
        : () => openInvestmentsOrders(context,
            product: 'predictions', orderKind: 'limit_fill'),
  );
}

/// This market's resting orders ([here]) as the Orders tab draws them
/// ([PolyOrderRow], its one-tap Cancel), under the Open orders heading;
/// nothing while there are none. The hot wallet's orders, from the
/// account's last read.
class PolyMarketOrders extends ConsumerWidget {
  const PolyMarketOrders(
      {super.key, required this.here, this.heading = true, this.top = 0});

  final bool Function(Order order) here;

  /// The "Open orders" heading over the rows.
  final bool heading;

  /// Room over it, only when there is something to show.
  final double top;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Never builds the account itself: a page shown before Predictions
    // was opened (a Ledger's, a test's) has no orders to list.
    if (!ref.exists(polymarketTradingProvider)) return const SizedBox.shrink();
    final orders = [
      for (final o in ref.watch(polymarketTradingProvider
          .select((s) => s.valueOrNull?.openOrders ?? const <Order>[])))
        if (here(o)) o,
    ];
    if (orders.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    return Padding(
      key: const ValueKey('poly-market-orders'),
      padding: EdgeInsets.only(top: top),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (heading)
            Padding(
              padding: EdgeInsets.only(bottom: 8.h),
              child: Text(
                context.l10n.betOpenOrders,
                style: TextStyle(
                  color: c.textSecondary,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          for (final (i, o) in orders.indexed) ...[
            if (i > 0) SizedBox(height: 10.h),
            PolyOrderRow(key: ValueKey('market-order-${o.id}'), order: o),
          ],
        ],
      ),
    );
  }
}
