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
        HyperliquidRejectedException;

/// Whether [e], thrown by an order send, leaves it UNKNOWN if the venue
/// took the order: the request timed out or the connection broke (the
/// venue may have received it), or the gateway answered without a verdict
/// (a 5xx, a non-JSON 200). Anything the venue itself said (every
/// [HyperliquidRejectedException], a 4xx) is a verdict: never unknown.
bool hlOrderOutcomeUnknown(Object e) {
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
