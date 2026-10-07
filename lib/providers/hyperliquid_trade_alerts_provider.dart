// lib/providers/hyperliquid_trade_alerts_provider.dart
//
// In-app trade alerts for the spending wallet's Hyperliquid account, shown
// as the app's toast banner anywhere in the app (HlTradeAlertsHost in the
// shell). There are NO push notifications: nothing here reaches the OS,
// and nothing fires while the app is closed.
//
// What raises an alert:
//   * a RESTING order filled (a maker fill; market orders and triggered
//     stops take liquidity and are covered by the ticket's own receipt or
//     the trigger alert);
//   * a take-profit / stop-loss (or other trigger order) fired
//     (`orderUpdates` status 'triggered');
//   * a position liquidated (a fill flagged `liquidation`);
//   * the venue cancelling an order for a reason the person should hear
//     (no margin, open-interest cap, delisted, self-trade);
//   * LIQUIDATION RISK: the mark within [kHlLiquidationRiskDistance] (10%)
//     of the position's liquidation price. 10% is about one ordinary
//     daily move for a volatile asset: early enough to add margin or
//     reduce, rare enough not to nag a position that is merely leveraged.
//     It re-arms only after the distance recovers past 15%, and a second,
//     louder alert fires inside 5%;
//   * YOUR OWN LEVELS: the mark within [kHlLevelNearDistance] (1%) of a
//     held position's take-profit or stop-loss trigger price. Once per
//     approach: it re-arms only after the distance recovers past
//     [kHlLevelRearmDistance] (2%), so a price hovering at the level
//     does not repeat it. 1% is close enough that the order is about to
//     matter and far enough to still change it;
//   * a FUNDING SPIKE on a held position: paying at least 0.01% an hour
//     (about 88% a year, 8x the venue's 0.00125% baseline). Once per
//     position per 8 hours unless the rate doubles.
//
// Anti-spam: every alert is deduped on what it is about (order id,
// position, coin) and the host shows at most one banner every few
// seconds, queueing at most three.
//
// Sources: the user-events socket (orderUpdates + userFills), kept open
// here only while the wallet has provisioned Hyperliquid; positions from
// [hyperliquidHeldPositionsProvider] (5 s while Investing is open, else
// the 60 s badge poll); funding from the last market lists seen
// ([HlMarketDirectory]).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/helpers/hyperliquid_order_status.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/hyperliquid_user_events_provider.dart';
import 'package:kute/services/hyperliquid/hyperliquid_websocket.dart';

/// Distance from the liquidation price (as a fraction of the mark) that
/// raises the liquidation-risk alert.
const double kHlLiquidationRiskDistance = 0.10;

/// The second, closer liquidation-risk step.
const double kHlLiquidationRiskUrgent = 0.05;

/// The alert re-arms once the distance recovers past this.
const double kHlLiquidationRiskRearm = 0.15;

/// Distance from a take-profit or stop-loss trigger price (as a fraction
/// of the mark) that raises the level-approach alert.
const double kHlLevelNearDistance = 0.01;

/// The level-approach alert re-arms once the distance recovers past this.
const double kHlLevelRearmDistance = 0.02;

/// Hourly funding a held position must PAY to count as a spike.
const double kHlFundingSpikeHourly = 0.0001;

enum HlTradeAlertType {
  filled,
  takeProfit,
  stopLoss,
  triggered,
  liquidated,
  liquidationRisk,
  takeProfitNear,
  stopLossNear,
  fundingSpike,
  venueCancel,
}

extension HlTradeAlertTypeX on HlTradeAlertType {
  /// Analytics value.
  String get key => switch (this) {
        HlTradeAlertType.filled => 'order_filled',
        HlTradeAlertType.takeProfit => 'take_profit_triggered',
        HlTradeAlertType.stopLoss => 'stop_loss_triggered',
        HlTradeAlertType.triggered => 'trigger_fired',
        HlTradeAlertType.liquidated => 'liquidated',
        HlTradeAlertType.liquidationRisk => 'liquidation_risk',
        HlTradeAlertType.takeProfitNear => 'take_profit_near',
        HlTradeAlertType.stopLossNear => 'stop_loss_near',
        HlTradeAlertType.fundingSpike => 'funding_spike',
        HlTradeAlertType.venueCancel => 'venue_cancel',
      };

  bool get isWarning =>
      this == HlTradeAlertType.liquidated ||
      this == HlTradeAlertType.liquidationRisk ||
      this == HlTradeAlertType.stopLossNear ||
      this == HlTradeAlertType.fundingSpike ||
      this == HlTradeAlertType.venueCancel;

  /// The mark is closing in on one of the person's own levels
  /// (liquidation, take-profit, stop-loss).
  bool get isLevelApproach =>
      this == HlTradeAlertType.liquidationRisk ||
      this == HlTradeAlertType.takeProfitNear ||
      this == HlTradeAlertType.stopLossNear;
}

/// One alert. Carries data, not text: the host words it in the app
/// language when it is shown.
class HlTradeAlert {
  final int seq;
  final HlTradeAlertType type;

  /// Display coin ('TSLA') and wire coin ('xyz:TSLA').
  final String coin;
  final String wire;

  /// Liquidation risk and level approach: distance as a fraction and the
  /// level's price (liquidation, take-profit or stop-loss).
  final double? distance;
  final double? price;

  /// Funding spike: what the position pays a day, USD.
  final double? dailyCost;

  /// Venue cancel: the orderUpdates status.
  final String? status;

  const HlTradeAlert({
    required this.seq,
    required this.type,
    required this.coin,
    required this.wire,
    this.distance,
    this.price,
    this.dailyCost,
    this.status,
  });
}

/// Pure decision logic, kept apart from Riverpod so it can be tested.
class HlTradeAlertRules {
  final Set<String> _seenOrderEvents = {};
  final Map<String, DateTime> _liquidatedAt = {};
  final Map<String, int> _riskLevel = {}; // position key → 0 none, 1, 2
  final Map<String, ({DateTime at, double rate})> _fundingAlerted = {};
  final Set<int> _levelNear = {}; // trigger order ids inside the near band

  /// Alerts for one batch of live fills.
  List<HlTradeAlert> onFills(List<HlFill> fills, int Function() seq) {
    final out = <HlTradeAlert>[];
    for (final f in fills) {
      if (f.liquidated) {
        final last = _liquidatedAt[f.coin];
        if (last != null &&
            DateTime.now().difference(last) < const Duration(minutes: 10)) {
          continue;
        }
        _liquidatedAt[f.coin] = DateTime.now();
        out.add(_alert(seq(), HlTradeAlertType.liquidated, f.coin));
        continue;
      }
      // A resting order filled (maker). Partial fills of one order raise
      // one alert.
      if (f.crossed == false && _seenOrderEvents.add('fill:${f.oid}')) {
        out.add(_alert(seq(), HlTradeAlertType.filled, f.coin));
      }
    }
    return out;
  }

  /// Alerts for new orderUpdates. [orderTypeOf] names the order's kind
  /// ('Take Profit Market', 'Stop Limit', …) when the open orders list
  /// knew it.
  List<HlTradeAlert> onOrderUpdates(List<HlOrderUpdate> updates,
      String? Function(int oid) orderTypeOf, int Function() seq) {
    final out = <HlTradeAlert>[];
    for (final u in updates) {
      if (!_seenOrderEvents.add('${u.status}:${u.oid}')) continue;
      if (u.status == 'triggered') {
        final kind = (orderTypeOf(u.oid) ?? '').toLowerCase();
        final type = kind.startsWith('take profit')
            ? HlTradeAlertType.takeProfit
            : kind.startsWith('stop')
                ? HlTradeAlertType.stopLoss
                : HlTradeAlertType.triggered;
        out.add(_alert(seq(), type, u.coin));
      } else if (kHlAlertingCancelStatuses.contains(u.status)) {
        out.add(_alert(seq(), HlTradeAlertType.venueCancel, u.coin,
            status: u.status));
      }
    }
    return out;
  }

  /// Alerts for a fresh positions read. [fundingOf] is the hourly rate of
  /// a wire coin's market when known.
  List<HlTradeAlert> onPositions(List<HlPerpPosition> positions,
      double? Function(String wire) fundingOf, int Function() seq,
      {DateTime? now}) {
    final at = now ?? DateTime.now();
    final out = <HlTradeAlert>[];
    final live = <String>{};
    for (final p in positions) {
      final size = p.szi.abs();
      if (size <= 0) continue;
      final key = '${p.coin}:${p.isLong ? 'long' : 'short'}';
      live.add(key);
      final mark = p.positionValue.abs() / size;
      final liq = p.liquidationPx;
      if (liq != null && liq.isFinite && liq > 0 && mark > 0) {
        final distance = (mark - liq).abs() / mark;
        final level = distance <= kHlLiquidationRiskUrgent
            ? 2
            : distance <= kHlLiquidationRiskDistance
                ? 1
                : 0;
        final previous = _riskLevel[key] ?? 0;
        if (distance > kHlLiquidationRiskRearm) {
          _riskLevel[key] = 0;
        } else if (level > previous) {
          _riskLevel[key] = level;
          out.add(_alert(seq(), HlTradeAlertType.liquidationRisk, p.coin,
              distance: distance, price: liq));
        }
      }
      final funding = fundingOf(p.coin);
      if (funding != null) {
        final pays = p.isLong ? funding > 0 : funding < 0;
        final rate = funding.abs();
        if (pays && rate >= kHlFundingSpikeHourly) {
          final last = _fundingAlerted[key];
          final due = last == null ||
              at.difference(last.at) >= const Duration(hours: 8) ||
              rate >= last.rate * 2;
          if (due) {
            _fundingAlerted[key] = (at: at, rate: rate);
            out.add(_alert(seq(), HlTradeAlertType.fundingSpike, p.coin,
                dailyCost: p.positionValue.abs() * rate * 24));
          }
        }
      }
    }
    // A closed position starts afresh next time.
    _riskLevel.removeWhere((k, _) => !live.contains(k));
    _fundingAlerted.removeWhere((k, _) => !live.contains(k));
    return out;
  }

  /// Alerts for the mark closing in on a held position's take-profit or
  /// stop-loss. [orders] are the open orders; a trigger order counts when
  /// it is on a held position's coin and the venue names it TP or SL.
  /// Each order alerts once per approach (see [kHlLevelRearmDistance]).
  List<HlTradeAlert> onLevels(List<HlPerpPosition> positions,
      List<HlOpenOrder> orders, int Function() seq) {
    final out = <HlTradeAlert>[];
    final marks = <String, double>{};
    for (final p in positions) {
      final size = p.szi.abs();
      if (size > 0) marks[p.coin] = p.positionValue.abs() / size;
    }
    final live = <int>{};
    for (final o in orders) {
      final mark = marks[o.coin];
      final trigger = o.triggerPx;
      final tpsl = o.tpsl;
      if (mark == null || mark <= 0 || !o.isTrigger || tpsl == null) continue;
      if (trigger == null || !trigger.isFinite || trigger <= 0) continue;
      live.add(o.oid);
      final distance = (mark - trigger).abs() / mark;
      if (distance > kHlLevelRearmDistance) {
        _levelNear.remove(o.oid);
      } else if (distance <= kHlLevelNearDistance && _levelNear.add(o.oid)) {
        out.add(_alert(
            seq(),
            tpsl == 'tp'
                ? HlTradeAlertType.takeProfitNear
                : HlTradeAlertType.stopLossNear,
            o.coin,
            distance: distance,
            price: trigger));
      }
    }
    // A cancelled or fired order starts afresh if it is placed again.
    _levelNear.removeWhere((oid) => !live.contains(oid));
    return out;
  }

  static HlTradeAlert _alert(int seq, HlTradeAlertType type, String wire,
          {double? distance, double? price, double? dailyCost, String? status}) =>
      HlTradeAlert(
        seq: seq,
        type: type,
        coin: HlMarketDirectory.displayName(wire),
        wire: wire,
        distance: distance,
        price: price,
        dailyCost: dailyCost,
        status: status,
      );
}

/// The alerts raised since the app started, newest last (capped). The host
/// shows each new one once.
class HlTradeAlertsNotifier extends Notifier<List<HlTradeAlert>> {
  final _rules = HlTradeAlertRules();
  int _seq = 0;
  int _fillsSeq = 0;
  ProviderSubscription<HlUserEventsState>? _events;

  int _next() => ++_seq;

  @override
  List<HlTradeAlert> build() {
    ref.onDispose(() => _events?.close());
    // The user-events socket stays open only for a wallet that has
    // provisioned Hyperliquid; a wallet that never traded opens nothing.
    ref.listen<bool>(hyperliquidProvisionedProvider, (_, on) => _watchEvents(on),
        fireImmediately: true);
    ref.listen<List<HlPerpPosition>>(hyperliquidHeldPositionsProvider,
        (_, positions) {
      _add(_rules.onPositions(
          positions, (wire) => HlMarketDirectory.byWire(wire)?.funding, _next));
      _add(_rules.onLevels(positions, _openOrders(), _next));
    });
    return const [];
  }

  void _watchEvents(bool on) {
    if (!on) {
      _events?.close();
      _events = null;
      return;
    }
    if (_events != null) return;
    _events = ref.listen<HlUserEventsState>(hyperliquidUserEventsProvider,
        (prev, next) {
      if (next.fillsSeq != _fillsSeq) {
        _fillsSeq = next.fillsSeq;
        _add(_rules.onFills(next.lastLiveFills, _next));
      }
      // The whole ring each time: the rules dedupe on status and order
      // id, so a capped or reset ring never repeats or drops an alert.
      final fresh = next.recentOrderUpdates;
      if (fresh.isEmpty || identical(fresh, prev?.recentOrderUpdates)) {
        return;
      }
      final orders = _openOrders();
      _add(_rules.onOrderUpdates(fresh, (oid) {
        for (final o in orders) {
          if (o.oid == oid) return o.orderType;
        }
        return null;
      }, _next));
    });
  }

  /// The open orders as last read, without starting that read here.
  List<HlOpenOrder> _openOrders() => ref.exists(hyperliquidTradingProvider)
      ? ref.read(hyperliquidTradingProvider).valueOrNull?.openOrders ??
          const <HlOpenOrder>[]
      : const <HlOpenOrder>[];

  void _add(List<HlTradeAlert> alerts) {
    if (alerts.isEmpty) return;
    final next = [...state, ...alerts];
    state = next.length > 20 ? next.sublist(next.length - 20) : next;
  }
}

final hyperliquidTradeAlertsProvider =
    NotifierProvider<HlTradeAlertsNotifier, List<HlTradeAlert>>(
        HlTradeAlertsNotifier.new);
