// lib/screens/hyperliquid/components/open_orders_sheet.dart
//
// Resting Hyperliquid orders (limit / trigger) with per-row cancel —
// adapted from the Polymarket open_orders_sheet. Rows read from the
// trading notifier's openOrders (REST-seeded, WS-patched); cancel goes
// through HyperliquidTradingNotifier.cancelOrder, which needs the
// order-wire asset id — resolved here from the order's WIRE coin
// ('xyz:TSLA', '@107', 'PURR/USDC'), exactly, never by display name.

import 'package:flutter/material.dart';
import 'package:kute/screens/home/components/kute_dock_host.dart'
    show KuteDockClearance, kuteDockScrollClearance;
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/screens/shared/trade_receipt.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/hyperliquid_user_events_provider.dart';
import 'package:kute/helpers/hyperliquid_order_status.dart';
import 'package:kute/services/hyperliquid/hyperliquid_websocket.dart'
    show HlOrderUpdate;
import 'package:kute/screens/hyperliquid/components/hl_format.dart';
import 'package:kute/screens/hyperliquid/components/hl_portfolio_card.dart';
import 'package:kute/screens/shared/portfolio_position_card.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

void _showCancellationReceipt(
  BuildContext context, {
  String? coin,
  String? reference,
  int? count,
  bool stopped = false,
}) {
  final l10n = context.l10n;
  final navigator = Navigator.of(context, rootNavigator: true);
  pushKuteSuccessOverlay(
    navigator: navigator,
    overlay: KuteConfirmation(
      message: stopped
          ? l10n.investingRecurringStopped
          : count != null
              ? l10n.investingAllCancelled
              : l10n.investingCancelled,
      detail: l10n.investingCancellationDetails,
      showCloseButton: true,
      onDone: () => navigator.pop(),
      receipt: TradeReceipt(
        title: coin ?? l10n.trading,
        rows: {
          if (reference != null) l10n.investingReference: reference,
          if (count != null) l10n.investingOrderCount: '$count',
        },
      ),
    ),
  );
}

/// Show the Hyperliquid open-orders bottom sheet.
Future<void> showHlOpenOrdersSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const HlOpenOrdersSheet(),
  );
}

class HlOpenOrdersSheet extends ConsumerWidget {
  final bool embedded;
  const HlOpenOrdersSheet({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final tradingAsync = ref.watch(hyperliquidTradingProvider);
    final orders =
        tradingAsync.valueOrNull?.openOrders ?? const <HlOpenOrder>[];
    final twaps =
        (tradingAsync.valueOrNull?.runningTwaps ?? const <HlRunningTwap>[])
            .where((t) => !t.expired)
            .toList();
    // Orders the venue ended or fired on its own this session, with its
    // reason in plain words (newest first).
    final ended = ref
        .watch(hyperliquidUserEventsProvider
            .select((s) => s.recentOrderUpdates))
        .where((u) => hlStatusIsVenueDecision(u.status))
        .toList()
        .reversed
        .take(10)
        .toList();

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
              // The embedded tab already has the strip's Orders label
              // above it (user decision: no second title). Cancel all and
              // the count stay, right-aligned, as on Predictions.
              if (!embedded || orders.isNotEmpty || twaps.isNotEmpty) ...[
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
                    if (orders.isNotEmpty || twaps.isNotEmpty) ...[
                      Text(
                        '${orders.length + twaps.length}',
                        style: TextStyle(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w700,
                          color: c.textTertiary,
                        ),
                      ),
                      SizedBox(width: 10.w),
                      const _CancelAllButton(),
                    ],
                  ],
                ),
                SizedBox(height: 12.h),
              ],
              if (tradingAsync.isLoading && orders.isEmpty)
                // Skeleton order rows shaped like _HlOrderRow while the
                // trading state first loads.
                KuteSkeleton(
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
                )
              else if (orders.isEmpty && twaps.isEmpty && ended.isEmpty)
                // Centred in the tab like every other empty portfolio
                // view (user decision), not pinned under the header.
                _emptyOrders(
                    c,
                    context.l10n.hlOrdersEmpty,
                    embedded)
              else
                Flexible(
                  fit: embedded ? FlexFit.tight : FlexFit.loose,
                  child: ListView.separated(
                    shrinkWrap: !embedded,
                    padding: embedded
                        ? EdgeInsets.only(
                            bottom: 20.h + kuteDockScrollClearance(context))
                        : null,
                    itemCount: twaps.length +
                        orders.length +
                        (ended.isEmpty ? 0 : ended.length + 1),
                    separatorBuilder: (_, __) => SizedBox(height: 10.h),
                    // Running TWAPs lead — they're actively trading right
                    // now, resting orders are just waiting. Orders the
                    // venue ended come last, under their own heading.
                    itemBuilder: (_, i) {
                      if (i < twaps.length) return _HlTwapRow(twap: twaps[i]);
                      final o = i - twaps.length;
                      if (o < orders.length) {
                        return _HlOrderRow(order: orders[o]);
                      }
                      final e = o - orders.length;
                      if (e == 0) {
                        return Padding(
                          padding: EdgeInsets.only(top: 8.h),
                          child: Text(
                            context.l10n.hlOrdersEndedTitle,
                            style: TextStyle(
                              color: c.textTertiary,
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        );
                      }
                      return _HlEndedOrderRow(update: ended[e - 1]);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Header pill that cancels EVERY resting order in one batch action.
/// Same bordered-pill chrome as the per-row Cancel button.
class _CancelAllButton extends ConsumerStatefulWidget {
  const _CancelAllButton();

  @override
  ConsumerState<_CancelAllButton> createState() => _CancelAllButtonState();
}

class _CancelAllButtonState extends ConsumerState<_CancelAllButton> {
  bool _busy = false;

  Future<void> _cancelAll() async {
    if (_busy) return;
    setState(() => _busy = true);
    HapticFeedback.lightImpact();
    final walletId = pickSpendingWallet(ref.read(settingsProvider))?.id;
    try {
      final count =
          await ref.read(hyperliquidTradingProvider.notifier).cancelAllOrders();
      if (mounted &&
          count > 0 &&
          pickSpendingWallet(ref.read(settingsProvider))?.id == walletId) {
        _showCancellationReceipt(context, count: count);
      }
    } catch (error) {
      if (mounted) {
        showMessageSnackBar(
          context: context,
          message: error is HlCancellationIncompleteException
              ? context.l10n.investingCancellationIncomplete
              : context.l10n.investingCancelUnconfirmed,
          error: true,
        );
      }
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

/// A running TWAP — same card chrome as _HlOrderRow, with a Stop button
/// (twapCancel) and an elapsed-time bar instead of a fill bar. Client-
/// tracked: HL never lists running TWAPs, so this row exists only
/// because the twapId was captured at placement.
class _HlTwapRow extends ConsumerStatefulWidget {
  final HlRunningTwap twap;
  const _HlTwapRow({required this.twap});

  @override
  ConsumerState<_HlTwapRow> createState() => _HlTwapRowState();
}

class _HlTwapRowState extends ConsumerState<_HlTwapRow> {
  bool _stopping = false;

  Future<void> _stop() async {
    if (_stopping) return;
    setState(() => _stopping = true);
    HapticFeedback.lightImpact();
    final walletId = pickSpendingWallet(ref.read(settingsProvider))?.id;
    final twap = widget.twap;
    try {
      await ref.read(hyperliquidTradingProvider.notifier).cancelTwap(twap);
      if (mounted &&
          pickSpendingWallet(ref.read(settingsProvider))?.id == walletId) {
        _showCancellationReceipt(context,
            coin: twap.coin, reference: '${twap.twapId}', stopped: true);
      }
    } catch (_) {
      if (mounted) {
        showMessageSnackBar(
          context: context,
          message: context.l10n.investingCancelUnconfirmed,
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _stopping = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = widget.twap;
    final market = ref.watch(hyperliquidAccountMarketProvider(t.coin));
    final coin = hlDisplayCoin(market, t.coin);
    final elapsedMin = DateTime.now().difference(t.startedAt).inMinutes;
    final progress = t.durationMinutes > 0
        ? (elapsedMin / t.durationMinutes).clamp(0.0, 1.0)
        : 0.0;

    // The portfolio's card (HlPortfolioCard): what runs and how far it
    // is as captions, Stop as the app's own button under them.
    return HlPortfolioCard(
      margin: EdgeInsets.zero,
      coin: coin,
      wireCoin: market?.wireCoin ?? t.coin,
      iconUrl: market?.iconUrl,
      category: market?.category,
      name: hlFriendlyName(coin) ?? market?.unitAssetName ?? coin,
      caption:
          '$coin · ${t.isBuy ? context.l10n.buy : context.l10n.sell}',
      footer: [
        '${context.l10n.hlTwapOver(formatHlSize(t.size), t.durationMinutes)}'
            ' · ${(progress * 100).clamp(0, 100).toStringAsFixed(0)}% elapsed',
        if (t.reduceOnly) context.l10n.hlOrdersReduceOnly,
      ],
      below: Padding(
        padding: EdgeInsets.only(top: 10.h),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4.r),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 4.h,
            backgroundColor: c.border,
            valueColor: AlwaysStoppedAnimation<Color>(c.textSecondary),
          ),
        ),
      ),
      action: SizedBox(
        width: 96.w,
        child: AppButton(
          text: context.l10n.hlOrdersStop,
          compact: true,
          variant: AppButtonVariant.secondary,
          isLoading: _stopping,
          onPressed: _stopping ? null : _stop,
        ),
      ),
    );
  }
}

class _HlOrderRow extends ConsumerStatefulWidget {
  final HlOpenOrder order;
  const _HlOrderRow({required this.order});

  @override
  ConsumerState<_HlOrderRow> createState() => _HlOrderRowState();
}

class _HlOrderRowState extends ConsumerState<_HlOrderRow> {
  bool _cancelling = false;

  Future<void> _cancel() async {
    if (_cancelling) return;
    final o = widget.order;
    final walletId = pickSpendingWallet(ref.read(settingsProvider))?.id;
    // Resolve the order-wire asset id from the markets universe by the
    // order's wire coin (spot orders come back as '@107' / 'PURR/USDC',
    // builder-dex orders as 'xyz:TSLA').
    final market = ref.read(hyperliquidWireMarketProvider(o.coin));
    if (market == null) {
      // The notifier is never reached, so it cannot report this one.
      TrackingService.track('hyperliquid_cancel_failed', params: {
        'scope': 'single',
        'coin': o.coin,
        'reason': 'asset_unresolved',
        'wallet_kind': 'hot',
      });
      showMessageSnackBar(
        context: context,
        message: context.l10n.investingCancellationIncomplete,
        error: true,
      );
      return;
    }
    setState(() => _cancelling = true);
    HapticFeedback.lightImpact();
    try {
      await ref.read(hyperliquidTradingProvider.notifier).cancelOrder(
            assetId: market.assetId,
            oid: o.oid,
            coin: o.coin,
          );
      if (mounted &&
          pickSpendingWallet(ref.read(settingsProvider))?.id == walletId) {
        _showCancellationReceipt(context,
            coin: market.coin, reference: '${o.oid}');
      }
    } catch (_) {
      if (mounted) {
        showMessageSnackBar(
          context: context,
          message: context.l10n.investingCancelUnconfirmed,
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final o = widget.order;
    final market = ref.watch(hyperliquidWireMarketProvider(o.coin));
    final coin = hlDisplayCoin(market, o.coin);
    final filled = (o.origSz - o.sz).clamp(0, o.origSz).toDouble();
    final fillPct =
        o.origSz > 0 ? (filled / o.origSz * 100).clamp(0, 100).toDouble() : 0.0;

    // The portfolio's card (HlPortfolioCard): the order's price is the
    // number on the right, with the kind of order under it; what is left
    // of it is a caption, Cancel the app's own button under them.
    return HlPortfolioCard(
      margin: EdgeInsets.zero,
      coin: coin,
      wireCoin: market?.wireCoin ?? o.coin,
      iconUrl: market?.iconUrl,
      category: market?.category,
      name: hlFriendlyName(coin) ?? market?.unitAssetName ?? coin,
      caption:
          '$coin · ${o.isBuy ? context.l10n.buy : context.l10n.sell}',
      // Trigger orders show the TRIGGER price the user set — for a stop
      // market the exchange's limitPx is just the aggressive fill guard,
      // not what the user typed. A trailing stop has no fixed price.
      trailing: o.isTrailingStop
          ? null
          : PortfolioCardValue(
              value: formatHlPrice(
                  o.isTrigger && o.triggerPx != null
                      ? o.triggerPx!
                      : o.limitPx,
                  decimalCap: market?.pxDecimalCap),
              detail: o.orderType.isNotEmpty ? o.orderType : 'Limit',
            ),
      footer: [
        if (o.isTrailingStop) context.l10n.hlOrdersTrailingStopMarket,
        '${formatHlSize(o.sz)} of ${formatHlSize(o.origSz)} left',
        if (o.reduceOnly) context.l10n.hlOrdersReduceOnly,
        if (fillPct > 0)
          '${fillPct.toStringAsFixed(0)}% filled — partially matched',
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

/// An order Hyperliquid ended or fired on its own (orderUpdates), with
/// the reason in plain words: no margin left, open-interest cap, its TP/SL
/// partner filled, the trigger price reached, and so on.
class _HlEndedOrderRow extends ConsumerWidget {
  final HlOrderUpdate update;
  const _HlEndedOrderRow({required this.update});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = update;
    final market = ref.watch(hyperliquidWireMarketProvider(u.coin));
    final coin = hlDisplayCoin(market, u.coin);
    final when = DateTime.fromMillisecondsSinceEpoch(
        u.statusTimestamp > 0 ? u.statusTimestamp : u.timestamp);
    return HlPortfolioCard(
      margin: EdgeInsets.zero,
      coin: coin,
      wireCoin: market?.wireCoin ?? u.coin,
      iconUrl: market?.iconUrl,
      category: market?.category,
      name: hlFriendlyName(coin) ?? market?.unitAssetName ?? coin,
      caption: '$coin · '
          '${u.isBuy ? context.l10n.buy : context.l10n.sell} '
          '${formatHlSize(u.origSz)}',
      trailing: PortfolioCardValue(
        value: formatHlPrice(u.limitPx, decimalCap: market?.pxDecimalCap),
      ),
      footer: [
        hlOrderStatusReason(context.l10n, u.status),
        TimeOfDay.fromDateTime(when).format(context),
      ],
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
