// lib/services/standing_orders/standing_orders_provider.dart
//
// The standing orders of the spending wallet (standing_order.dart), kept
// durably and driven by the venues' own queued-order machinery:
//
//  * ACCEPT. The moment a funded prediction or Investing order is queued
//    behind its money (`awaitingBalance`, the state the slips set right
//    after the one Face ID), a standing order is created here. For a
//    prediction the CLOB order is SIGNED NOW under that approval (a child
//    grant chained from the autofire grant, consumed against exactly this
//    order; `PmGrants.consumeOrder` as `placeOrder` does) and the signed
//    bytes go to secure storage: no new approval is ever asked, and the
//    signed limit is the price bound. For an Investing order the exact
//    approved intent goes to secure storage and the action is signed when
//    it is posted (the nonce window would allow a pre-signed action, the
//    live mid does not: see the report). The queued intent is marked with
//    the standing order's id, so the autofires post the stored order and
//    never sign a second one.
//  * MIRROR. The pending providers' statuses map onto the standing states
//    ([standingStateForBet], [standingStateForHlOrder]); every change is
//    persisted and published to [StandingOrderProgress].
//  * CANCEL. Before posting only: the queued intent is cleared (which drops
//    its grant), the secret deleted, the money already moved left on the
//    venue, available.
//  * RESUME. On start and on unlock: the wallet's records are loaded; one
//    past its life is settled as expired; one that was posting is looked
//    up at the venue by its hash (and the order guard reconciles its own
//    journal before anything is posted again); one still waiting for its
//    money is queued again with its id, and the autofire posts the stored
//    order when the venue counts the money.
//
// Analytics (exact amounts, never ids or text): `standing_order_created`,
// `standing_order_resumed`, `standing_order_cancelled`; the venues' own
// `polymarket_bet_*` / `hyperliquid_order_*` keep their names and carry
// `wait_ms` for a standing order (the autofires add it).

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/auth_grant_registry.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/l10n/l10n.dart' show l10nForLanguage;
import 'package:kute/models/hyperliquid_market.dart' show HlMarketKind;
import 'package:kute/providers/pending_bet_autofire.dart'
    show kPendingBetAutofireId, pendingBetAutoFireProvider, polymarketFundedWorstPrice;
import 'package:kute/providers/pending_hyperliquid_order_provider.dart';
import 'package:kute/providers/pending_polymarket_bet_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/services/one_balance/one_balance_state.dart'
    show OneBalanceVenue;
import 'package:kute/services/one_balance/order_funding.dart'
    show OrderFundingJourney;
import 'package:kute/services/one_balance/prediction_funding_ledger.dart';
import 'package:kute/services/polymarket/market_buy_quote.dart'
    show PolymarketOrderPlan;
import 'package:kute/services/polymarket/market_terms_store.dart';
import 'package:kute/services/standing_orders/polymarket_signed_order.dart';
import 'package:kute/services/standing_orders/standing_order.dart';
import 'package:kute/services/standing_orders/standing_order_progress.dart';
import 'package:kute/services/standing_orders/standing_order_store.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show OrderType;

export 'package:kute/services/standing_orders/standing_order.dart';

/// The store the notifier persists through. Tests override it with one
/// over an in-memory secret store.
final standingOrderStoreProvider =
    Provider<StandingOrderStore>((_) => StandingOrderStore());

/// Signs a prediction's standing order under [grant] (the chained child):
/// the trading notifier's `signStandingOrder`. Null when the account
/// cannot sign now. Tests fake it.
typedef StandingPredictionSigner = Future<StandingSignedOrder?> Function({
  required String tokenId,
  required double size,
  required double price,
  required double spendUsd,
  required bool negRisk,
  required OrderType orderType,
  required AuthGrant grant,
});

final standingPredictionSignerProvider =
    Provider<StandingPredictionSigner>((ref) => ({
          required tokenId,
          required size,
          required price,
          required spendUsd,
          required negRisk,
          required orderType,
          required grant,
        }) =>
            ref.read(polymarketTradingProvider.notifier).signStandingOrder(
                  tokenId: tokenId,
                  size: size,
                  price: price,
                  spendUsd: spendUsd,
                  negRisk: negRisk,
                  orderType: orderType,
                  grant: grant,
                ));

/// Looks a prediction order up at the venue by its hash (`GET
/// /data/order/{id}`); null when the venue does not know it. Tests fake it.
typedef StandingOrderLookup = Future<Map<String, dynamic>?> Function(
    String orderHash);

final standingOrderLookupProvider = Provider<StandingOrderLookup>((ref) =>
    (hash) async {
      final backend =
          ref.read(polymarketTradingProvider.notifier).backendService;
      if (backend == null) throw StateError('Predictions account not ready');
      return backend.getOrderById(hash);
    });

/// What a resume wakes once it has queued a standing order again: the
/// venue's watcher that posts it when the money is counted. Tests, which
/// have no venue, override it with nothing.
class StandingOrderWatchers {
  const StandingOrderWatchers(
      {required this.wakePredictions, required this.wakeInvesting});
  final void Function() wakePredictions;
  final void Function() wakeInvesting;
}

final standingOrderWatchersProvider = Provider<StandingOrderWatchers>(
  (ref) => StandingOrderWatchers(
    wakePredictions: () => ref.read(pendingBetAutoFireProvider),
    wakeInvesting: () => ref.read(pendingHlOrderAutoFireProvider),
  ),
);

/// The Investing approval a standing order keeps: the exact intent the
/// person approved and how (the step-up method), rebuilt into a grant at
/// post time when the in-memory one is gone (a restart).
class StandingHlApproval {
  const StandingHlApproval({required this.intent, required this.method});
  final SensitiveIntent intent;
  final AuthGrantMethod method;

  Map<String, Object?> toJson() => {
        'venue': 'investing',
        'method': method.name,
        'intent': sensitiveIntentToJson(intent),
      };

  static StandingHlApproval? fromJson(Map<String, Object?> json) {
    try {
      if (json['venue'] != 'investing') return null;
      return StandingHlApproval(
        intent: sensitiveIntentFromJson(
            (json['intent'] as Map).cast<String, Object?>()),
        method:
            AuthGrantMethod.values.firstWhere((m) => m.name == json['method']),
      );
    } catch (_) {
      return null;
    }
  }
}

/// A [SensitiveIntent] as JSON: BigInt as decimal strings. Reading it back
/// keeps them as strings, which the grant drift check compares equal to
/// the live intent's BigInts (`AuthGrants.canonicalJsonOf` does the same).
Map<String, Object?> sensitiveIntentToJson(SensitiveIntent i) => {
      'action': i.action.name,
      'walletId': i.walletId,
      'venue': i.venue,
      'account': i.account,
      'destination': i.destination,
      'asset': i.asset,
      'amountMax': i.amountMax.toString(),
      'limits': _plain(i.limits),
    };

SensitiveIntent sensitiveIntentFromJson(Map<String, Object?> json) =>
    SensitiveIntent(
      action: SensitiveAction.values.firstWhere((a) => a.name == json['action']),
      walletId: json['walletId'] as String,
      venue: json['venue'] as String,
      account: json['account'] as String?,
      destination: json['destination'] as String?,
      asset: json['asset'] as String,
      amountMax: BigInt.parse(json['amountMax'] as String),
      limits: (json['limits'] as Map).cast<String, Object?>(),
    );

Object? _plain(Object? v) {
  if (v is BigInt) return v.toString();
  if (v is Enum) return v.name;
  if (v is Map) return {for (final e in v.entries) '${e.key}': _plain(e.value)};
  if (v is Iterable) return [for (final e in v) _plain(e)];
  return v;
}

/// The signed order of a prediction's standing order, or null when it has
/// none (posted, cancelled, expired, or never signed).
typedef StandingSignedReader = Future<StandingSignedOrder?> Function(String id);

class StandingOrdersNotifier extends Notifier<List<StandingOrder>> {
  final StreamController<StandingOrder> _outcomes =
      StreamController<StandingOrder>.broadcast();

  /// The orders that just ended (filled or failed), for the notices.
  Stream<StandingOrder> get outcomes => _outcomes.stream;

  /// Test seam: the clock.
  static DateTime Function() clock = DateTime.now;

  /// The ids whose standing order is being created right now (its secret
  /// not written yet): the autofire waits for it.
  final Set<String> _creating = {};

  @override
  List<StandingOrder> build() {
    ref.onDispose(_outcomes.close);
    ref.listen<PendingBetIntent?>(pendingPolymarketBetProvider, _onBet);
    ref.listen<PendingHlOrderIntent?>(
        pendingHyperliquidOrderProvider, _onHlOrder);
    return const [];
  }

  StandingOrderStore get _store => ref.read(standingOrderStoreProvider);

  StandingOrder? byId(String id) {
    for (final o in state) {
      if (o.id == id) return o;
    }
    return null;
  }

  /// The orders still in flight, oldest first.
  List<StandingOrder> get open => [for (final o in state) if (o.isOpen) o];

  String? _walletId() {
    try {
      return pickSpendingWallet(ref.read(settingsProvider))?.id;
    } catch (_) {
      return null;
    }
  }

  void _publish(List<StandingOrder> next) {
    state = next;
    try {
      ref.read(standingOrderProgressProvider).update(next);
    } catch (_) {}
  }

  void _put(StandingOrder order) {
    _publish([for (final o in state) if (o.id != order.id) o, order]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt)));
  }

  static String newId() =>
      'so_${clock().microsecondsSinceEpoch}_${math.Random().nextInt(1 << 20)}';

  // ── Accept ───────────────────────────────────────────────────────────

  void _onBet(PendingBetIntent? prev, PendingBetIntent? next) {
    if (next == null) {
      final id = prev?.standingOrderId;
      if (id != null) _dropped(id);
      return;
    }
    final id = next.standingOrderId;
    if (id != null) {
      final mapped = standingStateForBet(next.status,
          readiness: next.readiness, isLimit: next.isLimit);
      // A stop for a price past the approval is the person's to settle
      // (needsApproval), never a failure by itself.
      if (mapped != null &&
          !(mapped == StandingOrderState.failed &&
              byId(id)?.state == StandingOrderState.needsApproval)) {
        unawaited(advance(id, mapped, failureCode: next.failureCode));
      }
      return;
    }
    // The accept: queued behind its own funding, no standing order yet.
    if (next.status == PendingBetStatus.awaitingBalance &&
        next.funded &&
        (prev == null ||
            prev.status != PendingBetStatus.awaitingBalance ||
            prev.queuedAt != next.queuedAt)) {
      _standPrediction(next);
    }
  }

  void _onHlOrder(PendingHlOrderIntent? prev, PendingHlOrderIntent? next) {
    if (next == null) {
      final id = prev?.standingOrderId;
      if (id != null) _dropped(id);
      return;
    }
    final id = next.standingOrderId;
    if (id != null) {
      final mapped = standingStateForHlOrder(next.status,
          readiness: next.readiness, result: next.result?.kind);
      if (mapped != null) unawaited(advance(id, mapped));
      return;
    }
    if (next.status == PendingHlOrderStatus.awaitingBalance &&
        next.fundUsd > 0 &&
        prev?.status != PendingHlOrderStatus.awaitingBalance) {
      _standInvestingOrder(next);
    }
  }

  /// A queued intent cleared while its standing order was still open and
  /// nobody cancelled it (the funding runner dropped it before any money
  /// moved): nothing will be placed, said so.
  void _dropped(String id) {
    final order = byId(id);
    if (order == null || !order.isOpen || _cancelling.contains(id)) return;
    unawaited(advance(id, StandingOrderState.failed, failureCode: 'dropped'));
  }

  final Set<String> _cancelling = {};

  /// Signs the prediction now and keeps it (see the file header). Nothing
  /// here moves money: the funding legs run on their own, in parallel.
  void _standPrediction(PendingBetIntent intent) {
    final walletId = _walletId();
    if (walletId == null) return;
    final parent =
        AuthGrantRegistry.instance.peekAutofire(kPendingBetAutofireId);
    if (parent == null) return;
    final now = clock();
    final id = newId();
    final isLimit = intent.isLimit;
    final price = isLimit
        ? intent.limitPrice.clamp(0.01, 0.99).toDouble()
        : _onTick(polymarketFundedWorstPrice(intent), intent);
    final shares = PolymarketOrderPlan.sharesFor(intent.amount, price);
    if (shares <= 0 || price <= 0) return;
    final orderType = isLimit ? OrderType.gtc : OrderType.fak;
    final spend = isLimit ? shares * price : intent.amount;
    final actual = PmGrants.executedOrder(
      parent,
      walletId: walletId,
      tokenId: intent.tokenId,
      isBuy: true,
      size: shares,
      price: price,
      orderType: orderType.name,
      spendUsd: isLimit ? null : spend,
    );
    final AuthGrant child;
    try {
      AuthGrants.check(parent, actual);
      child = GrantGuard.chain(parent, actual);
    } on AuthGrantException {
      // Outside what was approved: the autofire's own path decides.
      return;
    }
    final record = StandingOrder(
      id: id,
      walletId: walletId,
      venue: StandingOrderVenue.predictions,
      marketKey: intent.tokenId,
      marketTitle: intent.marketQuestion,
      sideLabel: intent.outcomeName,
      isBuy: true,
      size: shares,
      approvedPrice: price,
      amountUsd: intent.amount,
      orderKind: isLimit ? 'limit' : 'market',
      state: standingStateForBet(intent.status, readiness: intent.readiness) ??
          StandingOrderState.funding,
      createdAt: intent.queuedAt ?? now,
      updatedAt: now,
      fundUsd: intent.fundUsd ?? 0,
      arrivingUsd: intent.fundArrivingUsd ?? 0,
      readyUsd: intent.fundReadyUsd ?? 0,
      slippagePct: intent.slippagePct,
      marketImage: intent.marketImage,
      marketCategory: intent.marketCategory,
      eventSlug: intent.eventSlug,
      roundWindow: intent.roundWindow,
      marketEndAt: intent.marketEndAt,
      postNotBefore: standingPostNotBefore(
          eventSlug: intent.eventSlug, window: intent.roundWindow, now: now),
      negRisk: intent.marketQuote?.tokenId == intent.tokenId
          ? intent.marketQuote!.negRisk
          : intent.negRisk,
      entrySource: intent.entrySource,
    );
    // Marked before the signature: the autofire sees the id at once and
    // posts the stored order, never one of its own.
    _creating.add(id);
    _put(record);
    final notifier = ref.read(pendingPolymarketBetProvider.notifier);
    final current = ref.read(pendingPolymarketBetProvider);
    if (current == null || !_sameBet(current, intent)) {
      _creating.remove(id);
      _publish([for (final o in state) if (o.id != id) o]);
      return;
    }
    notifier.setIntent(current.copyWith(standingOrderId: id));
    unawaited(_signPrediction(record, intent, child,
        shares: shares, price: price, spend: spend, orderType: orderType));
  }

  Future<void> _signPrediction(
    StandingOrder record,
    PendingBetIntent intent,
    AuthGrant child, {
    required double shares,
    required double price,
    required double spend,
    required OrderType orderType,
  }) async {
    StandingSignedOrder? signed;
    try {
      signed = await ref.read(standingPredictionSignerProvider)(
        tokenId: intent.tokenId,
        size: shares,
        price: price,
        spendUsd: spend,
        negRisk: record.negRisk,
        orderType: orderType,
        grant: child,
      );
      if (signed != null) {
        await _store.writeSecret(record.id, signed.toJson());
        final withHash = (byId(record.id) ?? record)
            .copyWith(orderHash: signed.orderHash, updatedAt: clock());
        _put(withHash);
        await _store.save(withHash);
      }
    } catch (_) {
      signed = null;
    } finally {
      _creating.remove(record.id);
    }
    if (signed == null) {
      // Nothing was signed: the money on its way stays as venue cash, the
      // person is told nothing was placed. Never a second attempt.
      await _store.save(byId(record.id) ?? record);
      _failBet(record.id, StandingOrderFailure.approvalMissing);
      return;
    }
    TrackingService.track('standing_order_created', params: {
      'venue': record.venue.analyticsName,
      'amount_usd': record.amountUsd,
      'fund_usd': record.fundUsd,
      'stage': (byId(record.id) ?? record).state.name,
      'order_kind': record.orderKind,
      'waits_for_round': record.postNotBefore != null,
    });
  }

  /// The approved worst price on the market's increment (rounded down),
  /// so the venue takes the signed order as is.
  double _onTick(double price, PendingBetIntent intent) {
    final quote = intent.marketQuote;
    final raw = quote != null && quote.tokenId == intent.tokenId
        ? quote.tickSize
        : PolymarketMarketTermsStore.currentTickSize(intent.tokenId,
            referencePrice: price);
    final tick = double.tryParse(raw ?? '') ?? 0.01;
    if (tick <= 0) return price.clamp(0.01, 0.99).toDouble();
    final steps = (price / tick + 1e-9).floor();
    return (steps * tick).clamp(tick, 1 - tick).toDouble();
  }

  static bool _sameBet(PendingBetIntent a, PendingBetIntent b) =>
      a.tokenId == b.tokenId &&
      a.queuedAt == b.queuedAt &&
      a.fundedRunId == b.fundedRunId;

  void _failBet(String id, String code) {
    final current = ref.read(pendingPolymarketBetProvider);
    if (current != null && current.standingOrderId == id) {
      PredictionFundingLedger.instance
          .release(current.fundQuoteRef, reason: 'failed');
      if (current.funded) {
        OrderFundingJourney.instance.abandoned(OneBalanceVenue.predictions);
      }
      ref.read(pendingPolymarketBetProvider.notifier).updateStatus(
          PendingBetStatus.failed,
          errorMessage: l10nForLanguage(ref.read(settingsProvider).language)
              .standingPredictionFailed,
          failureCode: code);
    } else {
      unawaited(advance(id, StandingOrderState.failed, failureCode: code));
    }
  }

  /// Keeps the Investing order's exact approval (see the file header).
  void _standInvestingOrder(PendingHlOrderIntent intent) {
    final walletId = _walletId();
    final market = intent.market;
    if (walletId == null || market == null) return;
    final parent =
        AuthGrantRegistry.instance.peekAutofire(kPendingHlOrderAutofireId);
    if (parent == null) return;
    final approved =
        pendingHlOrderAutofireIntent(intent, market, walletId: walletId);
    if (AuthGrants.driftError(parent.boundIntent, approved) != null) return;
    final now = clock();
    final id = newId();
    final record = StandingOrder(
      id: id,
      walletId: walletId,
      venue: StandingOrderVenue.investing,
      marketKey: intent.coin,
      marketTitle: intent.marketLabel,
      sideLabel: intent.isLong ? 'long' : 'short',
      isBuy: intent.isLong,
      size: intent.marginUsd,
      approvedPrice: intent.expectedPx,
      amountUsd: intent.marginUsd,
      orderKind: intent.orderKind,
      state: standingStateForHlOrder(intent.status, readiness: intent.readiness) ??
          StandingOrderState.funding,
      createdAt: intent.createdAt,
      updatedAt: now,
      fundUsd: intent.fundUsd,
      arrivingUsd: intent.arrivingUsd,
      requiredUsd: intent.requiredUsd,
      readyUsd: intent.readyAtQueueUsd,
      slippagePct: intent.slippagePct,
      leverage: intent.leverage,
      marketKind: intent.kind == HlMarketKind.spot ? 'spot' : 'perp',
      entrySource: intent.entrySource ?? intent.source,
    );
    final notifier = ref.read(pendingHyperliquidOrderProvider.notifier);
    final current = ref.read(pendingHyperliquidOrderProvider);
    if (current == null || !identical(current.placement, intent.placement)) {
      return;
    }
    _creating.add(id);
    _put(record);
    notifier.setIntent(current.copyWith(standingOrderId: id));
    unawaited(() async {
      try {
        await _store.writeSecret(
            id,
            StandingHlApproval(intent: approved, method: parent.method)
                .toJson());
        await _store.save(byId(id) ?? record);
        TrackingService.track('standing_order_created', params: {
          'venue': record.venue.analyticsName,
          'amount_usd': record.amountUsd,
          'fund_usd': record.fundUsd,
          'stage': (byId(id) ?? record).state.name,
          'order_kind': record.orderKind,
          'waits_for_round': false,
        });
      } catch (_) {
        // The in-memory approval still places it this session; only a
        // restart would lose it, and settles it honestly.
      } finally {
        _creating.remove(id);
      }
    }());
  }

  // ── What the autofires read ──────────────────────────────────────────

  /// The signed order of [id], waiting up to [patience] for one still
  /// being written at the accept. Null when there is none.
  Future<StandingSignedOrder?> signedOrderFor(String id,
      {Duration patience = const Duration(seconds: 10)}) async {
    final until = clock().add(patience);
    while (_creating.contains(id) && clock().isBefore(until)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final json = await _store.readSecret(id);
    return json == null ? null : StandingSignedOrder.fromJson(json);
  }

  /// The Investing approval of [id], or null when there is none or the
  /// order is past its life.
  Future<StandingHlApproval?> approvalFor(String id) async {
    final order = byId(id);
    if (order == null || order.isExpiredAt(clock())) return null;
    final json = await _store.readSecret(id);
    return json == null ? null : StandingHlApproval.fromJson(json);
  }

  /// The approval of [id] was used (the action signed): gone from storage.
  Future<void> approvalUsed(String id) => _store.deleteSecret(id);

  /// Whether [id]'s post may go out at [now] (a pick for the next round
  /// waits for it to open).
  bool mayPost(String id, {DateTime? now}) =>
      byId(id)?.mayPostAt(now ?? clock()) ?? true;

  // ── Transitions ──────────────────────────────────────────────────────

  /// Moves [id] to [to] when the state machine allows it; persists; a
  /// terminal state deletes the secret and is reported to [outcomes]
  /// (unless [quiet]: the person acted on it themselves).
  Future<void> advance(String id, StandingOrderState to,
      {String? failureCode,
      String? orderHash,
      double? movedToPrice,
      bool quiet = false}) async {
    final order = byId(id);
    if (order == null || !StandingOrder.canMove(order.state, to)) return;
    final next = order.copyWith(
      state: to,
      updatedAt: clock(),
      orderHash: orderHash,
      movedToPrice: movedToPrice,
      failureCode: to == StandingOrderState.failed ? failureCode : null,
    );
    _put(next);
    if (to.isTerminal || to == StandingOrderState.needsApproval) {
      await _store.deleteSecret(id);
      if (to.isTerminal && to != StandingOrderState.cancelled && !quiet) {
        _outcomes.add(next);
      }
    }
    try {
      await _store.save(next);
    } catch (_) {}
  }

  /// The price moved past the approved worst price ([priceNow]): stopped
  /// with the money on the venue, waiting for the person (see the shell).
  Future<void> needsApproval(String id, {double? priceNow}) =>
      advance(id, StandingOrderState.needsApproval, movedToPrice: priceNow);

  /// A re-price (founder, 9 November 2026: "we try again at a different
  /// price"): the earlier order proven not accepted, a NEW order for the
  /// same bet is signed at [price] under the same approval (a child of the
  /// autofire grant still held this session), its secret replacing the
  /// old one, and [attempts] counted. Null when nothing may be signed: no
  /// approval in memory (a restart), the new order outside what was
  /// approved, too many re-prices ([kStandingReprices]) or past the
  /// window ([kStandingRepriceWindow] from the first post, [since]).
  Future<StandingSignedOrder?> reprice(
    String id, {
    required PendingBetIntent intent,
    required double price,
    required double shares,
    required double spendUsd,
    required DateTime since,
  }) async {
    final order = byId(id);
    final walletId = _walletId();
    if (order == null || walletId == null || !order.isOpen) return null;
    if (order.attempts > kStandingReprices ||
        clock().difference(since) > kStandingRepriceWindow) {
      return null;
    }
    final parent =
        AuthGrantRegistry.instance.peekAutofire(kPendingBetAutofireId);
    if (parent == null) return null;
    final actual = PmGrants.executedOrder(
      parent,
      walletId: walletId,
      tokenId: intent.tokenId,
      isBuy: true,
      size: shares,
      price: price,
      orderType: OrderType.fak.name,
      spendUsd: spendUsd,
    );
    final AuthGrant child;
    try {
      AuthGrants.check(parent, actual);
      child = GrantGuard.chain(parent, actual);
    } on AuthGrantException {
      return null;
    }
    StandingSignedOrder? signed;
    try {
      signed = await ref.read(standingPredictionSignerProvider)(
        tokenId: intent.tokenId,
        size: shares,
        price: price,
        spendUsd: spendUsd,
        negRisk: order.negRisk,
        orderType: OrderType.fak,
        grant: child,
      );
    } catch (_) {
      signed = null;
    }
    if (signed == null) return null;
    // The old order is proven not accepted: its secret goes, the new one
    // takes its place (one signature unaccounted for at a time).
    await _store.deleteSecret(id);
    await _store.writeSecret(id, signed.toJson());
    final next = (byId(id) ?? order).copyWith(
      orderHash: signed.orderHash,
      approvedPrice: price,
      size: shares,
      attempts: order.attempts + 1,
      updatedAt: clock(),
    );
    _put(next);
    try {
      await _store.save(next);
    } catch (_) {}
    return signed;
  }

  /// Cancels [id] before it is posted: the queued intent is cleared (its
  /// grant with it), the secret deleted, the money already moved left on
  /// the venue, available. False when it is too late (posting or later).
  Future<bool> cancel(String id) async {
    final order = byId(id);
    if (order == null || !order.canCancel) return false;
    _cancelling.add(id);
    try {
      switch (order.venue) {
        case StandingOrderVenue.predictions:
          final current = ref.read(pendingPolymarketBetProvider);
          if (current != null && current.standingOrderId == id) {
            PredictionFundingLedger.instance
                .release(current.fundQuoteRef, reason: 'abandoned');
            if (current.funded) {
              OrderFundingJourney.instance
                  .abandoned(OneBalanceVenue.predictions);
            }
            ref.read(pendingPolymarketBetProvider.notifier).clear();
            // Nothing may sign for it any more, watcher alive or not.
            AuthGrantRegistry.instance.cancelAutofire(kPendingBetAutofireId);
          }
        case StandingOrderVenue.investing:
          final current = ref.read(pendingHyperliquidOrderProvider);
          if (current != null && current.standingOrderId == id) {
            OrderFundingJourney.instance.abandoned(OneBalanceVenue.investing);
            ref.read(pendingHyperliquidOrderProvider.notifier).clear();
            AuthGrantRegistry.instance
                .cancelAutofire(kPendingHlOrderAutofireId);
          }
      }
      await advance(id, StandingOrderState.cancelled);
      TrackingService.track('standing_order_cancelled', params: {
        'venue': order.venue.analyticsName,
        'amount_usd': order.amountUsd,
        'fund_usd': order.fundUsd,
        'stage': order.state.name,
        'wait_ms': clock().difference(order.createdAt).inMilliseconds,
      });
      return true;
    } finally {
      _cancelling.remove(id);
    }
  }

  // ── Resume ───────────────────────────────────────────────────────────

  /// Loads the spending wallet's standing orders and carries every open
  /// one on (see the file header). Safe to call at any time; one run at a
  /// time.
  Future<void> resume() async {
    if (_resuming) return;
    _resuming = true;
    try {
      final walletId = _walletId();
      if (walletId == null) return;
      final stored = await _store.load(walletId);
      final known = {for (final o in state) o.id};
      _publish([...state, for (final o in stored) if (!known.contains(o.id)) o]
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt)));
      for (final order in stored) {
        if (!order.isOpen || known.contains(order.id)) continue;
        await _resumeOne(order);
      }
    } finally {
      _resuming = false;
    }
  }

  bool _resuming = false;

  Future<void> _resumeOne(StandingOrder order) async {
    final now = clock();
    TrackingService.track('standing_order_resumed', params: {
      'venue': order.venue.analyticsName,
      'amount_usd': order.amountUsd,
      'fund_usd': order.fundUsd,
      'stage': order.state.name,
      'wait_ms': now.difference(order.createdAt).inMilliseconds,
    });
    if (order.isExpiredAt(now)) {
      await advance(order.id, StandingOrderState.failed,
          failureCode: StandingOrderFailure.expired);
      return;
    }
    switch (order.venue) {
      case StandingOrderVenue.predictions:
        await _resumePrediction(order);
      case StandingOrderVenue.investing:
        await _resumeInvestingOrder(order);
    }
  }

  Future<void> _resumePrediction(StandingOrder order) async {
    if (order.state == StandingOrderState.posting ||
        order.state == StandingOrderState.posted) {
      final hash = order.orderHash;
      if (hash == null) {
        await advance(order.id, StandingOrderState.failed,
            failureCode: StandingOrderFailure.approvalMissing);
        return;
      }
      Map<String, dynamic>? found;
      try {
        found = await ref.read(standingOrderLookupProvider)(hash);
      } catch (_) {
        // Unreadable now: left as it is, looked up again next time.
        return;
      }
      final settled = settleFromVenue(order, found);
      if (settled != null) {
        await advance(order.id, settled.state, failureCode: settled.code);
        return;
      }
      // Never reached the venue: posted again below when the money is
      // counted (the order guard reconciles its own journal first).
    }
    if (!await _store.hasSecret(order.id)) {
      await advance(order.id, StandingOrderState.failed,
          failureCode: StandingOrderFailure.approvalMissing);
      return;
    }
    final current = ref.read(pendingPolymarketBetProvider);
    if (current != null && current.standingOrderId == order.id) return;
    if (current != null &&
        (current.status == PendingBetStatus.awaitingBalance ||
            current.status == PendingBetStatus.placing)) {
      // Another queued bet holds the slot: this one waits for the next
      // resume (one funded bet at a time, as the slips enforce).
      return;
    }
    ref.read(pendingPolymarketBetProvider.notifier).setIntent(PendingBetIntent(
          tokenId: order.marketKey,
          amount: order.amountUsd,
          slippagePct: order.slippagePct,
          marketQuestion: order.marketTitle,
          outcomeName: order.sideLabel,
          expectedPrice: order.approvedPrice,
          marketImage: order.marketImage,
          marketEndAt: order.marketEndAt,
          marketCategory: order.marketCategory,
          status: PendingBetStatus.awaitingBalance,
          eventSlug: order.eventSlug,
          roundWindow: order.roundWindow,
          isLimit: order.orderKind == 'limit',
          limitPrice: order.orderKind == 'limit' ? order.approvedPrice : 0,
          negRisk: order.negRisk,
          entrySource: order.entrySource,
          fundUsd: order.fundUsd > 0 ? order.fundUsd : 0.0,
          fundReadyUsd: order.readyUsd,
          fundArrivingUsd: order.arrivingUsd > 0 ? order.arrivingUsd : null,
          queuedAt: order.createdAt,
          standingOrderId: order.id,
        ));
    // The watcher that posts it once the venue counts the money.
    ref.read(standingOrderWatchersProvider).wakePredictions();
  }

  Future<void> _resumeInvestingOrder(StandingOrder order) async {
    if (order.state == StandingOrderState.posting) {
      // Sent before the restart and its answer lost with the app: the
      // venue has it or not, and the account's positions say which. Never
      // sent again.
      await advance(order.id, StandingOrderState.posted);
      return;
    }
    if (order.state == StandingOrderState.posted) return;
    if (order.orderKind != 'market') {
      // Only the plain market order can be rebuilt without the slip.
      await advance(order.id, StandingOrderState.failed,
          failureCode: StandingOrderFailure.notResumable);
      return;
    }
    if (!await _store.hasSecret(order.id)) {
      await advance(order.id, StandingOrderState.failed,
          failureCode: StandingOrderFailure.approvalMissing);
      return;
    }
    final current = ref.read(pendingHyperliquidOrderProvider);
    if (current != null && current.standingOrderId == order.id) return;
    if (PendingHyperliquidOrderNotifier.isActive(current)) return;
    ref.read(pendingHyperliquidOrderProvider.notifier).setIntent(
          PendingHlOrderIntent(
            coin: order.marketKey,
            kind: order.marketKind == 'spot'
                ? HlMarketKind.spot
                : HlMarketKind.perp,
            isLong: order.isBuy,
            marginUsd: order.amountUsd,
            leverage: order.leverage,
            slippagePct: order.slippagePct,
            expectedPx: order.approvedPrice,
            marketLabel: order.marketTitle,
            source: order.entrySource,
            status: PendingHlOrderStatus.awaitingBalance,
            createdAt: order.createdAt,
            fundUsd: order.fundUsd,
            requiredUsd: order.requiredUsd,
            readyAtQueueUsd: order.readyUsd,
            arrivingUsd: order.arrivingUsd,
            orderKind: order.orderKind,
            entrySource: order.entrySource,
            fundedAt: order.createdAt,
            standingOrderId: order.id,
          ),
        );
    ref.read(standingOrderWatchersProvider).wakeInvesting();
  }

  /// What the venue's record of a posted prediction settles it as:
  /// matched (or ended after a part fill) is filled; live, delayed or
  /// unmatched is posted; ended with nothing matched is failed. Null when
  /// the venue does not know it (never posted) or the record proves
  /// nothing.
  @visibleForTesting
  static ({StandingOrderState state, String? code})? settleFromVenue(
      StandingOrder order, Map<String, dynamic>? found) {
    if (found == null) return null;
    final id = found['id']?.toString().toLowerCase();
    if (id != null && order.orderHash != null && id != order.orderHash) {
      return null;
    }
    final status = found['status']?.toString().toUpperCase();
    if (status == null) return null;
    if (status == 'MATCHED') return (state: StandingOrderState.filled, code: null);
    if (const {'LIVE', 'DELAYED', 'UNMATCHED'}.contains(status)) {
      return (state: StandingOrderState.posted, code: null);
    }
    if (const {'CANCELED', 'CANCELLED', 'EXPIRED'}.contains(status)) {
      final matched = double.tryParse('${found['size_matched']}') ?? 0;
      return matched > 0
          ? (state: StandingOrderState.filled, code: null)
          : (state: StandingOrderState.failed, code: StandingOrderFailure.notFilled);
    }
    return null;
  }

  @visibleForTesting
  void debugReplace(List<StandingOrder> orders) => _publish(orders);
}

final standingOrdersProvider =
    NotifierProvider<StandingOrdersNotifier, List<StandingOrder>>(
  StandingOrdersNotifier.new,
);
