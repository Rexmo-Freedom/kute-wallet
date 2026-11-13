// lib/services/platform/order_activity_binder.dart
//
// Ties today's pending orders to the two platform facades: while a bet
// (pendingPolymarketBetProvider) or a trade (pendingHyperliquidOrderProvider)
// is in flight, the process holds a background grace
// (lib/services/platform/background_grace.dart) and the progress shows
// outside the app (lib/services/platform/order_activity.dart). The binder
// knows nothing of how an order is placed: it reads the intents' status,
// stage and readiness and maps them onto a stage and a 0..1 progress
// ([OrderStageMap]). A standing-order worker that later publishes a
// `StandingOrderProgress` plugs in through [apply] the same way.
//
// Rules:
//   * in flight means money is moving or the venue has the order and has
//     not answered: a bet from `converting` on, a trade from
//     `awaitingBalance` on. `awaitingDeposit` (the picker is open, nothing
//     committed) is not in flight;
//   * one grace for all in-flight orders, held when the first starts and
//     released when the last finishes, fails, is unconfirmed or disappears
//     (cancel, reset). [dispose] releases too; the facade's own watchdog
//     is the last line;
//   * a finished order gets `end`, a vanished one gets `cancel`;
//   * after the app comes back (`onResumed`) an order still in flight
//     whose grace expired while away is held again, so the next trip out
//     gets its window too.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/providers/pending_hyperliquid_order_provider.dart';
import 'package:kute/providers/pending_polymarket_bet_provider.dart';
import 'package:kute/services/platform/background_grace.dart';
import 'package:kute/services/platform/order_activity.dart';

/// One order's position, as the binder sees it: in flight with a
/// [stage] and [progress], or finished with an [outcome].
@immutable
class OrderProgress {
  const OrderProgress.inFlight({
    required this.id,
    required this.venue,
    required this.title,
    required this.amountUsd,
    required OrderStage this.stage,
    required this.progress,
  }) : outcome = null;

  const OrderProgress.finished({
    required this.id,
    required this.venue,
    required this.title,
    required this.amountUsd,
    required OrderOutcome this.outcome,
  })  : stage = null,
        progress = 1;

  /// The facade's order id; one per venue, never shown.
  final String id;
  final OrderVenue venue;

  /// The market as the person saw it on the slip.
  final String title;

  /// The stake or margin the person typed; passed through, never shown.
  final double amountUsd;
  final OrderStage? stage;
  final double progress;
  final OrderOutcome? outcome;

  bool get inFlight => outcome == null;

  @override
  String toString() => inFlight
      ? 'OrderProgress($id, ${stage!.name}, ${(progress * 100).round()}%)'
      : 'OrderProgress($id, ${outcome!.name})';
}

/// The pure mapping from today's intents to [OrderProgress]. Null when
/// nothing is in flight or finished (no intent, or the picker is open).
abstract final class OrderStageMap {
  static const String predictionsId = 'predictions';
  static const String investingId = 'investing';

  static OrderProgress? polymarket(PendingBetIntent? i) {
    if (i == null) return null;
    final title = '${i.marketQuestion} · ${i.outcomeName}';
    OrderProgress live(OrderStage stage, double progress) =>
        OrderProgress.inFlight(
            id: predictionsId,
            venue: OrderVenue.predictions,
            title: title,
            amountUsd: i.amount,
            stage: stage,
            progress: progress);
    OrderProgress done(OrderOutcome outcome) => OrderProgress.finished(
        id: predictionsId,
        venue: OrderVenue.predictions,
        title: title,
        amountUsd: i.amount,
        outcome: outcome);
    switch (i.status) {
      case PendingBetStatus.awaitingDeposit:
        return null;
      case PendingBetStatus.converting:
        return live(OrderStage.converting, 0.15);
      case PendingBetStatus.awaitingBalance:
        return switch (i.readiness) {
          null || PredictionsReadiness.waitingFunds =>
            live(OrderStage.waitingMoney, 0.35),
          PredictionsReadiness.converting => live(OrderStage.converting, 0.5),
          PredictionsReadiness.approving => live(OrderStage.settingUp, 0.6),
          PredictionsReadiness.confirming => live(OrderStage.confirming, 0.7),
          PredictionsReadiness.ready => live(OrderStage.sending, 0.75),
        };
      case PendingBetStatus.placing:
        return switch (i.stage) {
          PendingBetStage.submitting => live(OrderStage.sending, 0.8),
          PendingBetStage.settingUp => live(OrderStage.settingUp, 0.82),
          PendingBetStage.approving => live(OrderStage.settingUp, 0.84),
          PendingBetStage.delayed => live(OrderStage.confirming, 0.86),
          PendingBetStage.confirming => live(OrderStage.confirming, 0.9),
          PendingBetStage.reconciling => live(OrderStage.confirming, 0.92),
        };
      case PendingBetStatus.awaitingConfirmation:
        return live(OrderStage.confirming, 0.95);
      case PendingBetStatus.done:
        return done(OrderOutcome.placed);
      case PendingBetStatus.failed:
        return done(OrderOutcome.failed);
    }
  }

  static OrderProgress? hyperliquid(PendingHlOrderIntent? i) {
    if (i == null) return null;
    OrderProgress live(OrderStage stage, double progress) =>
        OrderProgress.inFlight(
            id: investingId,
            venue: OrderVenue.investing,
            title: i.marketLabel,
            amountUsd: i.marginUsd,
            stage: stage,
            progress: progress);
    OrderProgress done(OrderOutcome outcome) => OrderProgress.finished(
        id: investingId,
        venue: OrderVenue.investing,
        title: i.marketLabel,
        amountUsd: i.marginUsd,
        outcome: outcome);
    switch (i.status) {
      case PendingHlOrderStatus.awaitingDeposit:
        return null;
      case PendingHlOrderStatus.awaitingBalance:
        return switch (i.readiness) {
          null || HlReadiness.waitingFunds =>
            live(OrderStage.waitingMoney, 0.35),
          HlReadiness.crediting => live(OrderStage.confirming, 0.6),
          HlReadiness.ready => live(OrderStage.sending, 0.75),
        };
      case PendingHlOrderStatus.placing:
        return live(OrderStage.sending, 0.8);
      case PendingHlOrderStatus.done:
        return done(OrderOutcome.placed);
      case PendingHlOrderStatus.failed:
        return done(OrderOutcome.failed);
      case PendingHlOrderStatus.unconfirmed:
        return done(OrderOutcome.unconfirmed);
    }
  }
}

/// The facade calls the binder makes, so a test can hand it recorders.
abstract class OrderActivityPort {
  void start(String id,
      {required String title, required OrderVenue venue, double? amountUsd});
  void update(String id, {required OrderStage stage, required double progress});
  void end(String id, {required bool success, OrderOutcome? outcome});
  void cancel(String id);
}

abstract class BackgroundGracePort {
  GraceToken hold(String reason);
  void release(GraceToken token);
  bool isHeld(GraceToken token);
}

class _StaticActivity implements OrderActivityPort {
  const _StaticActivity();
  @override
  void start(String id,
          {required String title,
          required OrderVenue venue,
          double? amountUsd}) =>
      OrderActivity.start(id, title: title, venue: venue, amountUsd: amountUsd);
  @override
  void update(String id,
          {required OrderStage stage, required double progress}) =>
      OrderActivity.update(id, stage: stage, progress: progress);
  @override
  void end(String id, {required bool success, OrderOutcome? outcome}) =>
      OrderActivity.end(id, success: success, outcome: outcome);
  @override
  void cancel(String id) => OrderActivity.cancel(id);
}

class _StaticGrace implements BackgroundGracePort {
  const _StaticGrace();
  @override
  GraceToken hold(String reason) => BackgroundGrace.hold(reason);
  @override
  void release(GraceToken token) => BackgroundGrace.release(token);
  @override
  bool isHeld(GraceToken token) => BackgroundGrace.isHeld(token);
}

class OrderActivityBinder {
  OrderActivityBinder({OrderActivityPort? activity, BackgroundGracePort? grace})
      : _activity = activity ?? const _StaticActivity(),
        _grace = grace ?? const _StaticGrace();

  final OrderActivityPort _activity;
  final BackgroundGracePort _grace;

  /// The grace's reason word.
  static const String graceReason = 'order';

  final Map<String, OrderProgress> _tracked = {};
  GraceToken? _token;

  /// Orders in flight right now, by source.
  Iterable<OrderProgress> get inFlight => _tracked.values;

  /// The grace held now, if any (dead after an expiry until [onResumed]).
  GraceToken? get token => _token;

  void polymarket(PendingBetIntent? intent) =>
      apply(OrderStageMap.polymarket(intent),
          source: OrderStageMap.predictionsId);

  void hyperliquid(PendingHlOrderIntent? intent) =>
      apply(OrderStageMap.hyperliquid(intent),
          source: OrderStageMap.investingId);

  /// One source's latest position; null when it has nothing in flight or
  /// finished. Any publisher of [OrderProgress] can feed this.
  void apply(OrderProgress? next, {required String source}) {
    final current = _tracked[source];
    if (next == null) {
      if (current != null) {
        _tracked.remove(source);
        _activity.cancel(current.id);
        _syncGrace();
      }
      return;
    }
    if (!next.inFlight) {
      if (current != null) {
        _tracked.remove(source);
        _activity.end(next.id,
            success: next.outcome == OrderOutcome.placed,
            outcome: next.outcome);
        _syncGrace();
      }
      return;
    }
    if (current == null) {
      _activity.start(next.id,
          title: next.title, venue: next.venue, amountUsd: next.amountUsd);
    }
    if (current == null ||
        current.stage != next.stage ||
        current.progress != next.progress) {
      _activity.update(next.id, stage: next.stage!, progress: next.progress);
    }
    _tracked[source] = next;
    _syncGrace();
  }

  /// The app is back in front: an order still in flight whose grace died
  /// while away (iOS expiry, the watchdog) is held again.
  void onResumed() {
    if (_tracked.isEmpty) return;
    final t = _token;
    if (t == null || !_grace.isHeld(t)) _token = _grace.hold(graceReason);
  }

  void _syncGrace() {
    if (_tracked.isNotEmpty) {
      _token ??= _grace.hold(graceReason);
    } else if (_token != null) {
      _grace.release(_token!);
      _token = null;
    }
  }

  /// Releases the grace and takes down every running notice.
  void dispose() {
    final t = _token;
    _token = null;
    if (t != null) _grace.release(t);
    for (final order in _tracked.values) {
      _activity.cancel(order.id);
    }
    _tracked.clear();
  }
}

/// The app-wide binder, alive with the root ProviderScope. Read once from
/// the app root so it starts listening; nothing else needs it.
final orderActivityBinderProvider = Provider<OrderActivityBinder>((ref) {
  final binder = OrderActivityBinder();
  ref.onDispose(binder.dispose);
  ref.listen<PendingBetIntent?>(pendingPolymarketBetProvider,
      (_, next) => binder.polymarket(next),
      fireImmediately: true);
  ref.listen<PendingHlOrderIntent?>(pendingHyperliquidOrderProvider,
      (_, next) => binder.hyperliquid(next),
      fireImmediately: true);
  return binder;
});
