// lib/screens/hyperliquid/components/hl_trade_alerts_host.dart
//
// Shows the Hyperliquid trade alerts (hyperliquidTradeAlertsProvider) as
// the app's toast banner, wherever the person is in the app. Mounted once
// in the shell. In-app only: there are no push notifications.
//
// Pacing: one banner at a time, at least [_gap] apart, at most three
// waiting (the oldest waiting one is dropped first). A tap opens what the
// alert is about: the position (a liquidation-risk, take-profit or
// stop alert about a held position included), the market, or the orders
// list. The liquidation-risk banner on an isolated position opens the
// margin sheet in Add mode straight away, over the position screen; both
// open once (OpenOnce), however often the banner is tapped.
//
// Analytics: hyperliquid_banner_shown / hyperliquid_banner_tapped with the
// alert `type` and coin (no ids, addresses or balances).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/helpers/hyperliquid_order_status.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_trade_alerts_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_adjust_margin_sheet.dart';
import 'package:kute/screens/hyperliquid/components/hl_alert_haptics.dart';
import 'package:kute/screens/hyperliquid/components/hl_format.dart';
import 'package:kute/screens/hyperliquid/components/hl_isolated_margin.dart';
import 'package:kute/screens/hyperliquid/components/hl_position_detail_sheet.dart';
import 'package:kute/screens/hyperliquid/components/open_orders_sheet.dart';
import 'package:kute/screens/hyperliquid/market_detail_sheet.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

class HlTradeAlertsHost extends ConsumerStatefulWidget {
  const HlTradeAlertsHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<HlTradeAlertsHost> createState() => _HlTradeAlertsHostState();
}

class _HlTradeAlertsHostState extends ConsumerState<HlTradeAlertsHost> {
  static const _gap = Duration(seconds: 5);
  static const _maxWaiting = 3;

  final List<HlTradeAlert> _waiting = [];
  int _shownSeq = 0;
  DateTime? _lastShownAt;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    ref.listenManual<List<HlTradeAlert>>(hyperliquidTradeAlertsProvider,
        (_, alerts) {
      for (final a in alerts) {
        if (a.seq <= _shownSeq) continue;
        _shownSeq = a.seq;
        _waiting.add(a);
      }
      while (_waiting.length > _maxWaiting) {
        _waiting.removeAt(0);
      }
      _pump();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _pump() {
    if (!mounted || _waiting.isEmpty || _timer != null) return;
    final last = _lastShownAt;
    final wait = last == null ? Duration.zero : _gap - DateTime.now().difference(last);
    if (wait > Duration.zero) {
      _timer = Timer(wait, () {
        _timer = null;
        _pump();
      });
      return;
    }
    _show(_waiting.removeAt(0));
    if (_waiting.isNotEmpty) {
      _timer = Timer(_gap, () {
        _timer = null;
        _pump();
      });
    }
  }

  void _show(HlTradeAlert alert) {
    _lastShownAt = DateTime.now();
    KuteHaptics.play(hlAlertHaptic(alert.type));
    final params = <String, Object>{
      'type': alert.type.key,
      'coin': alert.coin,
      'venue': 'hyperliquid',
      'wallet_kind': 'hot',
      if (alert.status != null) 'status': alert.status!,
    };
    TrackingService.track('hyperliquid_banner_shown', params: params);
    showMessageBanner(
      context: context,
      message: _message(context.l10n, alert),
      icon: _icon(alert.type),
      accentColor: alert.type.isWarning ? AppColors.error : AppColors.success,
      onTap: () {
        TrackingService.track('hyperliquid_banner_tapped', params: params);
        _open(alert);
      },
    );
  }

  String _message(AppLocalizations l10n, HlTradeAlert a) {
    final market = HlMarketDirectory.byWire(a.wire);
    return switch (a.type) {
      HlTradeAlertType.filled => l10n.hlBannerFilled(a.coin),
      HlTradeAlertType.takeProfit => l10n.hlBannerTakeProfit(a.coin),
      HlTradeAlertType.stopLoss => l10n.hlBannerStopLoss(a.coin),
      HlTradeAlertType.triggered => l10n.hlBannerTriggered(a.coin),
      HlTradeAlertType.liquidated => l10n.hlBannerLiquidated(a.coin),
      HlTradeAlertType.liquidationRisk => l10n.hlBannerLiquidationRisk(
          a.coin,
          '${((a.distance ?? 0) * 100).toStringAsFixed(1)}%',
          formatHlPrice(a.price ?? 0, decimalCap: market?.pxDecimalCap)),
      HlTradeAlertType.takeProfitNear => l10n.hlBannerTakeProfitNear(
          a.coin,
          '${((a.distance ?? 0) * 100).toStringAsFixed(1)}%',
          formatHlPrice(a.price ?? 0, decimalCap: market?.pxDecimalCap)),
      HlTradeAlertType.stopLossNear => l10n.hlBannerStopLossNear(
          a.coin,
          '${((a.distance ?? 0) * 100).toStringAsFixed(1)}%',
          formatHlPrice(a.price ?? 0, decimalCap: market?.pxDecimalCap)),
      HlTradeAlertType.fundingSpike =>
        l10n.hlBannerFunding(a.coin, formatHlUsd(a.dailyCost ?? 0)),
      HlTradeAlertType.venueCancel => l10n.hlBannerOrderCancelled(
          a.coin, hlOrderStatusReason(l10n, a.status ?? '')),
    };
  }

  static IconData _icon(HlTradeAlertType type) => switch (type) {
        HlTradeAlertType.filled => Icons.check_circle_rounded,
        HlTradeAlertType.takeProfit ||
        HlTradeAlertType.takeProfitNear =>
          Icons.flag_rounded,
        HlTradeAlertType.stopLoss ||
        HlTradeAlertType.stopLossNear ||
        HlTradeAlertType.triggered =>
          Icons.bolt_rounded,
        HlTradeAlertType.liquidated ||
        HlTradeAlertType.liquidationRisk =>
          Icons.warning_amber_rounded,
        HlTradeAlertType.fundingSpike => Icons.percent_rounded,
        HlTradeAlertType.venueCancel => Icons.info_rounded,
      };

  void _open(HlTradeAlert alert) {
    if (!mounted) return;
    openHlTradeAlert(context, alert,
        held: ref.read(hyperliquidHeldPositionsProvider),
        market: HlMarketDirectory.byWire(alert.wire));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Opens what [alert] is about: the orders list for an order the venue
/// ended; else the position when one is held (in [held]); else the
/// market. A liquidation-risk alert on an isolated position the app can
/// move margin on also opens the margin sheet in Add mode, on top of the
/// position screen. Every one of them opens once (OpenOnce).
@visibleForTesting
void openHlTradeAlert(BuildContext context, HlTradeAlert alert,
    {required List<HlPerpPosition> held, required HlMarket? market}) {
  if (alert.type == HlTradeAlertType.venueCancel) {
    unawaited(showHlOpenOrdersSheet(context));
    return;
  }
  for (final p in held) {
    if (p.coin != alert.wire) continue;
    HlPositionDetailSheet.show(context, position: p, market: market);
    // The alerts follow the spending wallet only, so the margin sheet's
    // wallet rule holds here.
    if (alert.type == HlTradeAlertType.liquidationRisk &&
        hlCanAdjustMargin(p, market)) {
      unawaited(HlAdjustMarginSheet.show(context,
          position: p,
          market: market!,
          add: true,
          source: HlMarginSource.alertBanner));
    }
    return;
  }
  if (market != null) {
    HlMarketDetailSheet.show(context, market: market);
  }
}
