// lib/services/hyperliquid/hl_sent_order_trace.dart
//
// What became of an order the app already sent, looked up by its client
// order id (cloid) on the account's open orders and fills. Two callers:
//
//   * a queued (funded) order sent again after a margin refusal looks its
//     earlier sends up first, so nothing is ever placed twice;
//   * an order whose answer never came (the POST timed out, the connection
//     dropped, the gateway answered 5xx) is looked up BEFORE anything is
//     reported: the venue may well have taken it. The founder saw an order
//     "fail" in the slip and then find it placed; a close the same way.
//     An answer the venue gave (a rejection) is authoritative and is never
//     looked up.
//
// [hlSendReconciled] is that second use for every order send: opens,
// spot orders, limits and closes, from the slip and from the queued
// order. While it reads, the order's cloid is in
// [hlConfirmingOrdersProvider] and the slip says "Confirming with the
// exchange…". The order is reported placed when the account shows it,
// not placed only when a whole window of readable reads shows it nowhere
// ([hlReconcileSentOrder]), and unconfirmed otherwise: never "failed"
// for an order nobody has heard back about.

import 'dart:async';

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/hyperliquid_model.dart' show HyperliquidModel;
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart'
    show
        HlOrderResult,
        HlOrderResultKind,
        HyperliquidApiException,
        HyperliquidExchangeService,
        HyperliquidOrderNotPlacedException,
        HyperliquidOrderUnconfirmedException,
        HyperliquidRejectedException;
import 'package:kute/services/tracking_service.dart';

/// Whether [e], thrown by an order send, leaves it UNKNOWN if the venue
/// took the order: the request timed out or the connection broke (the
/// venue may have received it), or the gateway answered without a verdict
/// (a 5xx, a non-JSON 200). Anything the venue itself said (every
/// [HyperliquidRejectedException], a 4xx) is a verdict: never unknown.
bool hlOrderOutcomeUnknown(Object e) {
  if (e is HyperliquidOrderUnconfirmedException) return true;
  if (e is HyperliquidOrderNotPlacedException) return false;
  if (e is HyperliquidRejectedException) return false;
  if (e is TimeoutException) return true;
  if (e is HyperliquidApiException) {
    return e.statusCode == 0 || e.statusCode >= 500 || e.statusCode == 200;
  }
  return HyperliquidExchangeService.isOfflineError(e);
}

/// How many reads [hlTraceSentOrder] makes, a [kHlSentOrderTraceEvery]
/// apart, before an order it cannot find counts as unknown: a fill is on
/// the account within a second or two of the venue taking it.
const int kHlSentOrderTraceReads = 3;
const Duration kHlSentOrderTraceEvery = Duration(seconds: 1);

/// Every send of an order ([cloids]) looked up with [lookup] on [market]:
/// known (found, or nowhere) as soon as one read says so; unknown after
/// [reads] reads that could not say. Never throws.
Future<HlSentOrderTrace> hlTraceSentOrder(
  Future<HlSentOrderTrace> Function(List<String> cloids, HlMarket market)
      lookup,
  List<String> cloids,
  HlMarket market, {
  int reads = kHlSentOrderTraceReads,
  Duration every = kHlSentOrderTraceEvery,
}) async {
  var trace = const HlSentOrderTrace.unknown();
  for (var i = 0; i < reads; i++) {
    try {
      trace = await lookup(cloids, market);
    } catch (_) {
      trace = const HlSentOrderTrace.unknown();
    }
    if (trace.known) return trace;
    if (i + 1 < reads) await Future<void>.delayed(every);
  }
  return trace;
}

/// How long the account is read after an order send that got no verdict,
/// before "it is nowhere" counts as "it was not placed". The send itself
/// had 15 s; a request the venue was still working through when the app
/// gave up has landed (or never will) well inside this.
const Duration kHlReconcileWindow = Duration(seconds: 20);
const Duration kHlReconcileEvery = Duration(seconds: 2);

/// [cloids]' order read on [market] for [window], every [every]: found as
/// soon as one read shows it; nowhere only when the window has passed and
/// the last read answered (and showed it nowhere); unknown otherwise.
/// [hlTraceSentOrder] believes the first "nowhere", which is right for a
/// send the venue refused but not for one that went unanswered: the venue
/// can still be taking that order when the first read comes back empty.
/// Never throws.
Future<HlSentOrderTrace> hlReconcileSentOrder(
  Future<HlSentOrderTrace> Function(List<String> cloids, HlMarket market)
      lookup,
  List<String> cloids,
  HlMarket market, {
  Duration window = kHlReconcileWindow,
  Duration every = kHlReconcileEvery,
}) async {
  // Reads `every` apart from the first one until `window` has gone by,
  // counted in reads; and never much past the window when the reads are
  // slow themselves (each may take seconds on a bad connection), so the
  // slip's "Confirming…" is bounded either way.
  final gaps = every <= Duration.zero
      ? 1
      : (window.inMicroseconds / every.inMicroseconds).ceil().clamp(1, 600);
  final elapsed = Stopwatch()..start();
  var last = const HlSentOrderTrace.unknown();
  for (var i = 0; i <= gaps; i++) {
    try {
      last = await lookup(cloids, market);
    } catch (_) {
      last = const HlSentOrderTrace.unknown();
    }
    if (last.found != null) return last;
    if (i == gaps || elapsed.elapsed >= window) break;
    await Future<void>.delayed(every);
  }
  return last.known ? const HlSentOrderTrace.none() : last;
}

/// Cloids whose order is being looked up right now because its send got
/// no verdict ([hlSendReconciled]); the order slip says "Confirming with
/// the exchange…" while its own cloid is here.
final hlConfirmingOrdersProvider =
    StateProvider<Set<String>>((ref) => const <String>{});

/// Sends an order with [send] and, when the send gets no verdict
/// ([hlOrderOutcomeUnknown]: a timeout, a broken connection, a gateway
/// error), looks it up by [cloid] before anything is said: found, the
/// venue's order as it stands is returned (filled or resting, so the
/// receipt and the order's analytics follow as for any answer); nowhere
/// after the window, [HyperliquidOrderNotPlacedException]; unreadable,
/// [HyperliquidOrderUnconfirmedException]. Nothing is ever sent again.
/// A verdict the venue gave is rethrown as it is, never looked up.
/// [onConfirming] is told when the lookup starts (true) and ends (false).
Future<HlOrderResult> hlSendReconciled({
  required Future<HlOrderResult> Function() send,
  required String cloid,
  required HlMarket market,
  required Future<HlSentOrderTrace> Function(List<String> cloids, HlMarket m)
      lookup,
  required String action,
  void Function(bool confirming)? onConfirming,
  Duration window = kHlReconcileWindow,
  Duration every = kHlReconcileEvery,
}) async {
  try {
    return await send();
  } catch (e) {
    if (!hlOrderOutcomeUnknown(e) ||
        e is HyperliquidOrderUnconfirmedException) {
      rethrow;
    }
    final clock = Stopwatch()..start();
    try {
      onConfirming?.call(true);
    } catch (_) {}
    final HlSentOrderTrace trace;
    try {
      trace = await hlReconcileSentOrder(lookup, [cloid], market,
          window: window, every: every);
    } finally {
      try {
        onConfirming?.call(false);
      } catch (_) {}
    }
    final found = trace.found;
    final outcome = found != null
        ? (found.isFilled ? 'filled' : 'resting')
        : trace.known
            ? 'not_placed'
            : 'unconfirmed';
    try {
      // Categorical and durations only: never the cloid or the order.
      TrackingService.track('hl_order_outcome_reconciled', params: {
        'outcome': outcome,
        'cause': hlUnknownCause(e),
        'action': action,
        'market_kind': market.isSpot ? 'spot' : 'perp',
        'builder_dex': market.dex.isNotEmpty,
        'ms': clock.elapsedMilliseconds,
      });
    } catch (_) {}
    if (found != null) return found;
    if (trace.known) throw HyperliquidOrderNotPlacedException(cause: e);
    throw HyperliquidOrderUnconfirmedException(cause: e);
  }
}

/// Why a send got no verdict, as one closed word.
String hlUnknownCause(Object e) {
  if (e is TimeoutException) return 'timeout';
  if (e is HyperliquidApiException) {
    if (e.statusCode == 0) return 'connection';
    if (e.statusCode >= 500) return 'gateway';
    if (e.statusCode == 200) return 'unrecognised_answer';
    return 'http';
  }
  if (HyperliquidExchangeService.isOfflineError(e)) return 'connection';
  return 'other';
}

/// What became of an order already sent: still resting on the book, or
/// filled ([found]); nowhere ([known] and no [found]); or it could not be
/// read ([known] false).
@immutable
class HlSentOrderTrace {
  const HlSentOrderTrace.none()
      : known = true,
        found = null;
  const HlSentOrderTrace.found(HlOrderResult this.found) : known = true;
  const HlSentOrderTrace.unknown()
      : known = false,
        found = null;

  final bool known;
  final HlOrderResult? found;
}

/// Looks [cloids] up on [market]: the account's open orders and its fills.
/// Overridden in tests.
final hlSentOrderTraceProvider = Provider<
    Future<HlSentOrderTrace> Function(List<String> cloids, HlMarket market)>(
  (ref) => (cloids, market) async {
    try {
      final address = await ref
          .read(hyperliquidAddressProvider.future)
          .timeout(const Duration(seconds: 8));
      if (address == null || address.isEmpty) {
        return const HlSentOrderTrace.unknown();
      }
      final model = HyperliquidModel();
      final reads = await Future.wait<Object>([
        model.getOpenOrders(address,
            dexes: [if (market.dex.isNotEmpty) market.dex]),
        model.getUserFills(address),
      ]).timeout(const Duration(seconds: 10));
      return hlTraceOf(cloids,
          open: reads[0] as List<HlOpenOrder>, fills: reads[1] as List<HlFill>);
    } catch (_) {
      return const HlSentOrderTrace.unknown();
    }
  },
);

/// [cloids]' order in the account's [open] orders and [fills]: filled
/// (what filled, at its average price) before resting, else nowhere.
HlSentOrderTrace hlTraceOf(List<String> cloids,
    {required List<HlOpenOrder> open, required List<HlFill> fills}) {
  final ids = {for (final c in cloids) c.toLowerCase()};
  bool mine(String? cloid) =>
      cloid != null && ids.contains(cloid.toLowerCase());
  final filled = fills.where((f) => mine(f.cloid)).toList();
  if (filled.isNotEmpty) {
    final size = filled.fold<double>(0, (a, f) => a + f.sz);
    final notional = filled.fold<double>(0, (a, f) => a + f.sz * f.px);
    return HlSentOrderTrace.found(HlOrderResult(
      kind: HlOrderResultKind.filled,
      oid: filled.first.oid,
      cloid: filled.first.cloid,
      filledSz: size,
      avgPx: size > 0 ? notional / size : 0,
    ));
  }
  final resting = open.where((o) => mine(o.cloid)).toList();
  if (resting.isNotEmpty) {
    return HlSentOrderTrace.found(HlOrderResult(
        kind: HlOrderResultKind.resting,
        oid: resting.first.oid,
        cloid: resting.first.cloid));
  }
  return const HlSentOrderTrace.none();
}
