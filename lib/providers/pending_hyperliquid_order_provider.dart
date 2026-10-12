import 'package:kute/helpers/hyperliquid_error_message.dart';
// lib/providers/pending_hyperliquid_order_provider.dart
//
// Holds a Hyperliquid order intent while its margin travels from Dollars
// to Investing — the order slip stores the intent when the user confirms
// an order the venue cannot cover yet, the one-balance controller moves
// the shortfall, and the auto-fire watcher below fires the order the
// moment the account's available cash covers the margin. Mirrors
// pending_polymarket_bet_provider.dart + pending_bet_autofire.dart,
// folded into one file (the HL flow has no swap leg — a deposit credits
// perp USDC directly, so the state machine is smaller).
//
// Auto-fire consent rule (same as Polymarket's): only `awaitingBalance`
// fires — the state the slip sets AFTER the user explicitly confirmed
// the order and the funding was handed to the controller.
// `awaitingDeposit` (picker open) must NEVER auto-fire.
//
// Balance watching is a BOUNDED POLL (1 s for the first 30 s, then 4 s,
// 12 min ceiling) plus the rail's own `credited` stream, not a permanent
// ref.listen on hyperliquidWithdrawableProvider: the watcher is a
// non-autoDispose Provider bootstrapped by whatever UI surface reads it,
// and a build-time listen would pin the whole account stack (address
// derivation + API polling) alive for every user forever. The poll only
// runs while an intent is actually awaiting funds, and each tick reads a
// fresh account snapshot — exactly what PM's `_startAwaitPolling` does
// for swaps that settle off-screen.
//
// Step-up (Wallet Hardening Phase 1b.5, D-10): the order fires on the grant
// the user gave at confirm time (`requireFreshAuthGrant(autofireIntentId:
// kPendingHlOrderAutofireId)` on the slip), held 30 minutes in memory only
// and consumed against the exact order only while the session is
// unlocked. The same grant, extended with the dollars allowed to leave for
// the order (`kFundUsdLimit`), is what the rail's step-up hook honours for
// the funding leg. No grant (for example after a restart) or an expired
// one cancels the order and asks the user to confirm it again.
//
// Sizing: a market order may shrink to what actually arrived
// (`hypercoreMaxOrderUsd`) as long as its notional still meets the venue
// minimum; a limit, pro, TP/SL or reduce-only order is placed exactly as
// approved or not at all, and what arrived stays for the sweeper.

import 'dart:async';
import 'package:kute/constants/hyperliquid_constants.dart';
import 'package:kute/services/hyperliquid/hl_failure_analytics.dart';
import 'package:kute/services/hyperliquid/hypercore_cash.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/auth_grant_registry.dart';
import 'package:kute/helpers/require_fresh_auth.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/auth_provider.dart' show sessionUnlockedProvider;
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/placing_hyperliquid_order_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart'
    show HlOrderResult;
import 'package:kute/services/one_balance/hyperliquid_move_rail.dart';
import 'package:kute/services/one_balance/hyperliquid_venue_funder.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/order_funding.dart';
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/venue_analytics.dart';
import 'package:kute/services/tracking_service.dart';

enum PendingHlOrderStatus {
  /// Initial state. User sees the funding CTA; nothing committed yet.
  /// NEVER auto-fires.
  awaitingDeposit,

  /// Deposit initiated (permit signed / onramp kicked); waiting for the
  /// USDC to credit the perp clearinghouse.
  awaitingBalance,

  /// Funds arrived; submitting the order to the exchange.
  placing,

  /// Order submitted successfully — the overlay transitions to the
  /// order-placed state shortly.
  done,

  /// Submission (or the wait) failed. The overlay shows a retry CTA;
  /// any deposited funds stay on the user's exchange account.
  failed,
}

/// The exact notifier call the slip built for a queued order, so a funded
/// limit, pro, TP/SL or reduce-only order is placed exactly as approved.
/// [intentAt] and [placeAt] take the margin so a [resizable] market order
/// can shrink to what arrived; the others ignore it.
class PendingHlOrderPlacement {
  const PendingHlOrderPlacement({
    required this.intentAt,
    required this.placeAt,
    required this.resizable,
    this.cloid,
  });

  final SensitiveIntent Function(double marginUsd) intentAt;
  final Future<HlOrderResult> Function(AuthGrant grant, double marginUsd)
      placeAt;

  /// Market orders only: may shrink to what arrived.
  final bool resizable;

  /// The client order id the slip's fill listener matches on.
  final String? cloid;
}

class PendingHlOrderIntent {
  final String coin;
  final HlMarketKind kind;

  /// Long/buy = true. Spot buys register as long.
  final bool isLong;
  final double marginUsd;

  /// 1 for spot.
  final int leverage;
  final double slippagePct;

  /// The mid the user saw in the slip when they confirmed — display
  /// continuity for the overlay (the fire path re-reads the live mid).
  final double expectedPx;

  /// Tile label, e.g. 'BTC-PERP'.
  final String marketLabel;

  /// Analytics source ('market' | 'advisor' | …).
  final String? source;
  final PendingHlOrderStatus status;
  final String? errorMessage;

  /// When the user CONFIRMED this order in the slip. The auto-fire
  /// refuses intents older than [PendingHlOrderAutoFire.kMaxIntentAge]:
  /// a leveraged order placing itself hours/days after confirmation at
  /// a price the user never saw is a consent violation (review
  /// finding on the fiat bank-transfer rail, whose deposits settle in
  /// days) — stale intents ask for a fresh confirm instead.
  final DateTime createdAt;

  /// The market, when the slip handed it over (saves a list read).
  final HlMarket? market;

  /// The slip's own call, or null for the plain market order the
  /// auto-fire builds itself.
  final PendingHlOrderPlacement? placement;

  /// Dollars approved to leave the spending account for this order (the
  /// grant's [kFundUsdLimit]). Zero when the venue already held enough.
  final double fundUsd;

  /// What the venue must hold for the order (margin with its headroom
  /// and fees). Zero means "the margin itself", as before funding.
  final double requiredUsd;

  /// The venue's available cash when the order was queued, and what the
  /// funding was sized to deliver: together they say when the money
  /// visibly arrived, which is when a market order may be resized.
  final double readyAtQueueUsd;
  final double arrivingUsd;

  /// market | limit | pro (analytics `order_kind`).
  final String orderKind;

  /// open | add | reduce | close | flip (perps), analytics only.
  final String? positionEffect;
  final String? entrySource;

  /// The funding move, once the controller sent it.
  final String? fundQuoteId;
  final String? fundOrderId;

  /// Milliseconds the slip spent quoting and funding, for the one
  /// `order_funding_completed` the auto-fire emits.
  final int quoteMs;
  final int fundMs;

  /// When the funding was handed over (the credit wait starts here).
  final DateTime? fundedAt;

  /// When the order started placing (the order timing starts here).
  final DateTime? placingAt;

  /// The margin the order was actually placed with (smaller than
  /// [marginUsd] when a market order was resized to what arrived).
  final double? placedMarginUsd;

  /// The venue's answer, once placed.
  final HlOrderResult? result;

  PendingHlOrderIntent({
    required this.coin,
    required this.kind,
    required this.isLong,
    required this.marginUsd,
    required this.leverage,
    required this.slippagePct,
    required this.expectedPx,
    required this.marketLabel,
    this.source,
    this.status = PendingHlOrderStatus.awaitingDeposit,
    this.errorMessage,
    DateTime? createdAt,
    this.market,
    this.placement,
    this.fundUsd = 0,
    this.requiredUsd = 0,
    this.readyAtQueueUsd = 0,
    this.arrivingUsd = 0,
    this.orderKind = 'market',
    this.positionEffect,
    this.entrySource,
    this.fundQuoteId,
    this.fundOrderId,
    this.quoteMs = 0,
    this.fundMs = 0,
    this.fundedAt,
    this.placingAt,
    this.placedMarginUsd,
    this.result,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Whether the auto-fire may shrink this order to what arrived.
  bool get resizable =>
      placement?.resizable ?? (orderKind == 'market');

  PendingHlOrderIntent copyWith({
    PendingHlOrderStatus? status,
    String? errorMessage,
    String? fundQuoteId,
    String? fundOrderId,
    int? quoteMs,
    int? fundMs,
    DateTime? fundedAt,
    DateTime? placingAt,
    double? placedMarginUsd,
    HlOrderResult? result,
  }) {
    return PendingHlOrderIntent(
      coin: coin,
      kind: kind,
      isLong: isLong,
      marginUsd: marginUsd,
      leverage: leverage,
      slippagePct: slippagePct,
      expectedPx: expectedPx,
      marketLabel: marketLabel,
      source: source,
      status: status ?? this.status,
      errorMessage: errorMessage,
      createdAt: createdAt,
      market: market,
      placement: placement,
      fundUsd: fundUsd,
      requiredUsd: requiredUsd,
      readyAtQueueUsd: readyAtQueueUsd,
      arrivingUsd: arrivingUsd,
      orderKind: orderKind,
      positionEffect: positionEffect,
      entrySource: entrySource,
      fundQuoteId: fundQuoteId ?? this.fundQuoteId,
      fundOrderId: fundOrderId ?? this.fundOrderId,
      quoteMs: quoteMs ?? this.quoteMs,
      fundMs: fundMs ?? this.fundMs,
      fundedAt: fundedAt ?? this.fundedAt,
      placingAt: placingAt ?? this.placingAt,
      placedMarginUsd: placedMarginUsd ?? this.placedMarginUsd,
      result: result ?? this.result,
    );
  }
}

class PendingHyperliquidOrderNotifier extends Notifier<PendingHlOrderIntent?> {
  @override
  PendingHlOrderIntent? build() => null;

  void setIntent(PendingHlOrderIntent intent) {
    state = intent;
  }

  void updateStatus(PendingHlOrderStatus status, {String? errorMessage}) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(status: status, errorMessage: errorMessage);
  }

  void clear() {
    state = null;
  }

  /// Queues [intent] behind its funding: the order is marked
  /// `awaitingBalance` (the one state the auto-fire places from), the
  /// controller moves the shortfall from Dollars under [grant] (the
  /// confirm-time autofire grant, which the rail's step-up hook honours),
  /// and the auto-fire places the order once the venue holds the money.
  ///
  /// A refusal, a Dollars shortfall or an error before any funds left
  /// clears the intent and the grant: nothing is queued, Dollars are
  /// untouched. The outcome is returned for the slip to show.
  Future<OrderFundingOutcome> fundAndQueue(
    PendingHlOrderIntent intent, {
    required AuthGrant grant,
    required OrderFundingController controller,
    required double orderUsd,
    required double requiredUsd,
    required double readyUsd,
    void Function(OrderFundingStage)? onStage,
  }) async {
    // The watcher ([pendingHlOrderAutoFireProvider]) must be alive: the
    // slip reads it before calling, and every state change below reaches
    // its listener, so the first check runs as soon as the move is sent.
    state = intent.copyWith(status: PendingHlOrderStatus.awaitingBalance);
    final startedAt = DateTime.now();
    OrderFundingOutcome outcome;
    try {
      outcome = await controller.fundAndQueue(
        venue: OneBalanceVenue.investing,
        orderUsd: orderUsd,
        requiredUsd: requiredUsd,
        readyUsd: readyUsd,
        auth: UserGrantAuthorization(grant),
        onStage: onStage,
      );
    } catch (e) {
      _dropQueued(intent);
      rethrow;
    }
    final fundMs = DateTime.now().difference(startedAt).inMilliseconds;
    switch (outcome) {
      case OrderFundingFunded(:final move):
        final current = state;
        if (current != null && identical(current.placement, intent.placement)) {
          state = current.copyWith(
            fundQuoteId: move.quoteId,
            fundOrderId: move.orderId,
            fundMs: fundMs,
            fundedAt: DateTime.now(),
          );
          final registration = move.registration;
          if (registration != null && move.orderId == null) {
            unawaited(registration.then((id) {
              final s = state;
              if (id != null && s != null && identical(s.placement, intent.placement)) {
                state = s.copyWith(fundOrderId: id);
              }
            }));
          }
        }
      case OrderFundingNotNeeded():
        final current = state;
        if (current != null && identical(current.placement, intent.placement)) {
          state = current.copyWith(fundMs: fundMs, fundedAt: DateTime.now());
        }
      case OrderFundingRefused():
      case OrderFundingNeedsDollars():
        _dropQueued(intent);
    }
    return outcome;
  }

  /// Clears [intent] if it is still the queued one, with its grant.
  void _dropQueued(PendingHlOrderIntent intent) {
    final current = state;
    if (current != null && identical(current.placement, intent.placement)) {
      state = null;
    }
  }
}

final pendingHyperliquidOrderProvider =
    NotifierProvider<PendingHyperliquidOrderNotifier, PendingHlOrderIntent?>(
  PendingHyperliquidOrderNotifier.new,
);

/// The autofire grant slot for the one pending Hyperliquid order (D-10).
const String kPendingHlOrderAutofireId = 'hyperliquid_pending_order';

/// The order the auto-fire places for [intent] at [marginUsd]: the slip's
/// own call when it handed one over, else the plain market order.
SensitiveIntent pendingHlOrderPlacementIntent(
  PendingHlOrderIntent intent,
  HlMarket market, {
  required String walletId,
  double? marginUsd,
}) {
  final margin = marginUsd ?? intent.marginUsd;
  final placement = intent.placement;
  if (placement != null) return placement.intentAt(margin);
  return intent.kind == HlMarketKind.spot
      ? HlIntents.spotOrder(
          walletId: walletId,
          market: market,
          isBuy: intent.isLong,
          usd: margin,
          slippagePct: intent.slippagePct,
        )
      : HlIntents.openPosition(
          walletId: walletId,
          market: market,
          isLong: intent.isLong,
          marginUsd: margin,
          leverage: intent.leverage,
          slippagePct: intent.slippagePct,
        );
}

/// What a queued order is approved for at confirm time (D-10): exactly the
/// order the autofire places (market, side, margin, leverage, slippage)
/// plus, when Dollars fund it, the most that may leave the spending
/// account for it ([kFundUsdLimit]) and where it goes ([kFundVenueLimit]).
/// The rail's step-up hook reads those two; the placement consumes the
/// grant against this same intent.
SensitiveIntent pendingHlOrderAutofireIntent(
  PendingHlOrderIntent intent,
  HlMarket market, {
  required String walletId,
  double? marginUsd,
}) {
  final order = pendingHlOrderPlacementIntent(intent, market,
      walletId: walletId, marginUsd: marginUsd);
  if (intent.fundUsd <= 0) return order;
  return order.copyWith(limits: {
    ...order.limits,
    kFundUsdLimit: dollarsBaseUnits(intent.fundUsd),
    kFundVenueLimit: kFundVenueInvesting,
  });
}

// ───────────────────────────── auto-fire ─────────────────────────────

/// Long-lived watcher that fires the pending order the moment perp USDC
/// covers the margin — even if the user dismissed the overlay. Bootstrap
/// it from the Hyperliquid screen (`ref.watch(pendingHlOrderAutoFireProvider)`);
/// once created it stays alive for the session.
final pendingHlOrderAutoFireProvider = Provider<PendingHlOrderAutoFire>((ref) {
  final svc = PendingHlOrderAutoFire(ref);
  ref.onDispose(svc.dispose);
  return svc;
});

class PendingHlOrderAutoFire {
  final Ref ref;
  bool _firing = false;

  Timer? _awaitPoll;
  DateTime? _awaitStart;
  StreamSubscription<void>? _credited;

  /// See [PendingHlOrderIntent.createdAt] — intents older than this
  /// never auto-place.
  static const kMaxIntentAge = Duration(minutes: 30);

  /// The poll runs every second while the money is expected any moment,
  /// then settles to every four.
  static const Duration kAwaitFastInterval = Duration(seconds: 1);
  static const Duration kAwaitSlowInterval = Duration(seconds: 4);
  static const Duration kAwaitFastFor = Duration(seconds: 30);
  static const Duration kAwaitMaxWait = Duration(minutes: 12);

  /// The share of the sized arrival that must show before a market order
  /// is resized to what arrived: the money visibly landed, not a stale
  /// snapshot read a moment after the rail said it had.
  static const double kArrivedShare = 0.9;

  PendingHlOrderAutoFire(this.ref) {
    // Re-evaluate whenever the intent itself changes — a fresh setIntent
    // or a status flip to awaitingBalance should immediately check the
    // balance (the deposit might already have landed).
    ref.listen(pendingHyperliquidOrderProvider, (_, next) {
      // A cleared order never fires: drop its confirm-time grant.
      if (next == null) {
        AuthGrantRegistry.instance.cancelAutofire(kPendingHlOrderAutofireId);
      }
      unawaited(_maybeFire());
    });
    AuthGrantRegistry.instance.addAutofireExpiredListener(_onAutofireExpired);
    // The rail says a move was credited: read the account at once instead
    // of waiting for the next tick.
    try {
      _credited = ref.read(hyperliquidMoveRailProvider).credited.listen((_) {
        if (ref.read(pendingHyperliquidOrderProvider)?.status !=
            PendingHlOrderStatus.awaitingBalance) {
          return;
        }
        ref.invalidate(hyperliquidAccountProvider);
        unawaited(_maybeFire());
      });
    } catch (_) {
      // No rail bound (a test container): the poll alone watches.
    }
  }

  void dispose() {
    _stopAwaitPolling();
    _credited?.cancel();
    _credited = null;
    AuthGrantRegistry.instance
        .removeAutofireExpiredListener(_onAutofireExpired);
  }

  /// Checks the balance now (the slip calls it once the funding was
  /// handed over). Safe to call at any time.
  Future<void> checkNow() => _maybeFire();

  /// D-10: the confirm-time grant lapsed before the order could fire.
  void _onAutofireExpired(String intentId, String venue) {
    if (intentId != kPendingHlOrderAutofireId) return;
    _cancelForReconfirm(venue: venue);
  }

  /// Cancels the queued order with nothing placed and asks the user to
  /// confirm it again. [drift] means the order no longer matched the
  /// approval.
  void _cancelForReconfirm({
    String venue = IntentVenue.hyperliquid,
    String? placementId,
    bool drift = false,
  }) {
    final intent = ref.read(pendingHyperliquidOrderProvider);
    if (intent == null ||
        intent.status == PendingHlOrderStatus.done ||
        intent.status == PendingHlOrderStatus.failed) {
      return;
    }
    _stopAwaitPolling();
    final l10n = l10nForLanguage(ref.read(settingsProvider).language);
    final msg = drift ? l10n.stepUpDetailsChanged : l10n.pendingIntentExpired;
    if (placementId != null) {
      ref.read(placingHyperliquidOrderProvider.notifier).markFailed(placementId, msg);
    }
    _trackFundingFailed(intent, stage: 'order', reason: drift ? 'drift' : 'expired');
    ref
        .read(pendingHyperliquidOrderProvider.notifier)
        .updateStatus(PendingHlOrderStatus.failed, errorMessage: msg);
    if (!drift) {
      TrackingService.track('pending_intent_expired', params: {'venue': venue});
    }
  }

  /// Consumes the confirm-time grant against [approved] (the order with
  /// its funding limits) and returns the single-use grant the trading
  /// notifier takes, bound to [placed] (the bare order). Null when the
  /// order must not fire now: locked (it waits for the unlock), or no
  /// live grant or drift (cancelled, the user confirms again).
  AuthGrant? _autofireGrant(SensitiveIntent approved, SensitiveIntent placed,
      {String? placementId}) {
    try {
      final parent = AuthGrantRegistry.instance.consumeAutofire(
        kPendingHlOrderAutofireId,
        approved,
        session: ref.read(stepUpSessionStateProvider),
      );
      return GrantGuard.chain(parent, placed);
    } on GrantSessionLocked {
      if (placementId != null) {
        ref.read(placingHyperliquidOrderProvider.notifier).clear(placementId);
      }
      ref
          .read(pendingHyperliquidOrderProvider.notifier)
          .updateStatus(PendingHlOrderStatus.awaitingBalance);
      _startAwaitPolling();
      return null;
    } on GrantMissing {
      _cancelForReconfirm(placementId: placementId);
      return null;
    } on AuthGrantException catch (e) {
      trackGrantFailure(e, action: SensitiveAction.hlOrder);
      _cancelForReconfirm(placementId: placementId, drift: e is ReauthRequired);
      return null;
    }
  }

  /// The venue cash the order needs before it is placed as approved.
  static double requiredFor(PendingHlOrderIntent intent) =>
      intent.requiredUsd > 0 ? intent.requiredUsd : intent.marginUsd * 0.99;

  /// The margin the order goes out with for [withdrawable], or null while
  /// the money has not arrived: the approved margin once the account
  /// covers what the order needs; for a resizable market order whose
  /// funding has visibly landed, what the account can fund instead, as
  /// long as its notional still meets the venue minimum.
  static double? placeableMargin(PendingHlOrderIntent intent, double withdrawable) {
    if (withdrawable + 1e-6 >= requiredFor(intent)) return intent.marginUsd;
    if (!intent.resizable) return null;
    final arrived = intent.arrivingUsd > 0 &&
        withdrawable + 1e-6 >=
            intent.readyAtQueueUsd + intent.arrivingUsd * kArrivedShare;
    if (!arrived) return null;
    final lev = intent.kind == HlMarketKind.spot ? 1 : intent.leverage;
    final margin = hypercoreMaxOrderUsd(
      availableUsd: withdrawable,
      leverage: lev,
      slippagePct: intent.slippagePct,
    );
    if (margin <= 0 || margin >= intent.marginUsd) return null;
    if (margin * lev + 1e-9 < HyperliquidConstants.minOrderNotionalUsd) {
      return null;
    }
    return margin;
  }

  Future<void> _maybeFire() async {
    if (_firing) return;
    final intent = ref.read(pendingHyperliquidOrderProvider);
    if (intent == null) {
      _stopAwaitPolling();
      return;
    }
    // Only the post-confirm state fires (see consent rule in header).
    if (intent.status != PendingHlOrderStatus.awaitingBalance) {
      _stopAwaitPolling();
      return;
    }
    // Nothing signs behind the lock: keep polling so the first check
    // after unlock fires.
    if (!ref.read(sessionUnlockedProvider)) {
      _startAwaitPolling();
      return;
    }

    // Fresh withdrawable read. `.future` forces a fetch when the account
    // provider isn't currently alive, so an off-screen deposit is still
    // detected — the reason PM grew _startAwaitPolling in the first
    // place.
    double withdrawable = 0;
    try {
      final snap = await ref.read(hyperliquidAccountProvider.future);
      withdrawable = hypercoreAvailableUsdc(snap.withdrawable, snap.spotBalances);
    } catch (_) {
      // Transient read failure — the poll below retries.
    }

    // The account must cover what the order needs (balances are
    // floating-point, so an epsilon keeps an "almost there" race out);
    // a market order whose funding landed short goes out smaller.
    final margin = placeableMargin(intent, withdrawable);
    if (margin == null) {
      _startAwaitPolling();
      return;
    }

    _stopAwaitPolling();
    // Consent staleness guard: only fire orders confirmed RECENTLY.
    // In-session flows (deposit sheet → funds land in minutes) pass;
    // a fiat bank-transfer continuation settling days later must NOT
    // place a leveraged position at then-current prices — clear the
    // intent and tell the user to reconfirm in the slip.
    if (DateTime.now().difference(intent.createdAt) > kMaxIntentAge) {
      _trackAutofireFailed('stale_intent', intent);
      _trackFundingFailed(intent, stage: 'order', reason: 'stale_intent');
      ref.read(pendingHyperliquidOrderProvider.notifier).updateStatus(
            PendingHlOrderStatus.failed,
            errorMessage: l10nForLanguage(ref.read(settingsProvider).language)
                .hlDepositArrivedPricesMoved,
          );
      return;
    }
    _firing = true;
    try {
      await _placeOrder(intent, margin);
    } catch (_) {
      // _placeOrder owns its error reporting; swallow so a throw doesn't
      // block subsequent attempts.
    } finally {
      _firing = false;
    }
  }

  Future<void> _placeOrder(PendingHlOrderIntent intent, double margin) async {
    final pending = ref.read(pendingHyperliquidOrderProvider.notifier);
    final placing = ref.read(placingHyperliquidOrderProvider.notifier);
    // D-10: never fire without the confirm-time grant (a restart drops it).
    if (!AuthGrantRegistry.instance
        .hasAutofireGrant(kPendingHlOrderAutofireId)) {
      _cancelForReconfirm();
      return;
    }
    final placingAt = DateTime.now();
    final resized = margin < intent.marginUsd - 1e-9;
    pending.setIntent(intent.copyWith(
      status: PendingHlOrderStatus.placing,
      placingAt: placingAt,
      placedMarginUsd: margin,
    ));

    // Re-use the slip's early-registered tile when present (markPlacing
    // is idempotent per coin+side) so the user sees one continuous tile.
    final placementId = placing.markPlacing(
      coin: intent.coin,
      marketLabel: intent.marketLabel,
      isLong: intent.isLong,
      marginUsd: margin,
      leverage: intent.leverage,
      sizeRequested: intent.expectedPx > 0
          ? margin * intent.leverage / intent.expectedPx
          : 0,
      cloid: intent.placement?.cloid,
    );

    try {
      final market = intent.market ?? await _resolveMarket(intent);
      final walletId = pickSpendingWallet(ref.read(settingsProvider))?.id ?? '';
      final grant = _autofireGrant(
        pendingHlOrderAutofireIntent(intent, market,
            walletId: walletId, marginUsd: margin),
        pendingHlOrderPlacementIntent(intent, market,
            walletId: walletId, marginUsd: margin),
        placementId: placementId,
      );
      if (grant == null) return;
      VenueAnalytics.stage('hl', intent.coin, {
        'origin': intent.source ?? 'unknown',
        'entry_source': 'autofire',
        'funding_source': intent.fundUsd > 0 ? 'dollars' : 'venue_balance',
        'slippage_bps': VenueAnalytics.bps(intent.slippagePct),
      });
      final placement = intent.placement;
      final HlOrderResult result;
      if (placement != null) {
        result = await placement.placeAt(grant, margin);
      } else {
        final trading = ref.read(hyperliquidTradingProvider.notifier);
        if (intent.kind == HlMarketKind.spot) {
          result = await trading.placeSpotOrder(
            market: market,
            isBuy: intent.isLong,
            usd: margin,
            slippagePct: intent.slippagePct,
            source: 'autofire',
            grant: grant,
          );
        } else {
          result = await trading.openPosition(
            market: market,
            isLong: intent.isLong,
            marginUsd: margin,
            leverage: intent.leverage,
            slippagePct: intent.slippagePct,
            source: 'autofire',
            grant: grant,
          );
        }
      }
      placing.markSucceeded(placementId);
      final current = ref.read(pendingHyperliquidOrderProvider) ?? intent;
      pending.setIntent(current.copyWith(
        status: PendingHlOrderStatus.done,
        result: result,
      ));
      _trackFundingCompleted(current, margin: margin, resized: resized,
          placingAt: placingAt);
    } catch (e, st) {
      _trackAutofireFailed('error', intent, error: e);
      _trackFundingFailed(intent, stage: 'order', error: e);
      TrackingService.hyperliquidOrderFailed(
        coin: intent.coin,
        reason: TrackingService.errorCategory(e),
        action: 'open',
        orderType: intent.orderKind,
        isBuy: intent.isLong,
        notionalUsd: margin * intent.leverage,
        leverage: intent.leverage,
        walletKind: 'hot',
        stackTrace: st,
        extra: {
          'origin': intent.source ?? 'unknown',
          'entry_source': 'autofire',
          ...hlFailureParams(e),
        },
      );
      final message = hlTradeErrorMessage(
          l10nForLanguage(ref.read(settingsProvider).language), e);
      placing.markFailed(placementId, message);
      pending.updateStatus(
        PendingHlOrderStatus.failed,
        errorMessage: message,
      );
    }
  }

  /// A confirmed pending order that did not fire. No amounts or ids.
  void _trackAutofireFailed(String reason, PendingHlOrderIntent intent,
      {Object? error}) {
    TrackingService.track('hyperliquid_autofire_failed', params: {
      'reason': reason,
      'kind': intent.kind.name,
      'coin': intent.coin,
      if (error != null)
        'error_category': TrackingService.errorCategory(error),
    });
  }

  /// The one `order_funding_completed` for an order Dollars funded: the
  /// whole journey's timings, and whether it went out smaller.
  void _trackFundingCompleted(PendingHlOrderIntent intent,
      {required double margin,
      required bool resized,
      required DateTime placingAt}) {
    if (intent.fundUsd <= 0) return;
    final now = DateTime.now();
    final fundedAt = intent.fundedAt;
    final msCredit = fundedAt == null
        ? 0
        : placingAt.difference(fundedAt).inMilliseconds.clamp(0, 1 << 31);
    TrackingService.track('order_funding_completed', params: {
      'venue': 'hyperliquid',
      'fund_usd': intent.fundUsd,
      'amount_usd': margin,
      'ms_quote': intent.quoteMs,
      'ms_fund': intent.fundMs,
      'ms_credit': msCredit,
      'ms_order': now.difference(placingAt).inMilliseconds,
      'duration_ms': now.difference(intent.createdAt).inMilliseconds,
      'resized': resized,
      'order_kind': intent.orderKind,
      if (intent.positionEffect != null)
        'position_effect': intent.positionEffect!,
    });
  }

  /// `order_funding_failed` for an order Dollars funded that stopped
  /// after the money left: at the credit wait or at the placement.
  void _trackFundingFailed(PendingHlOrderIntent intent,
      {required String stage, Object? error, String? reason}) {
    if (intent.fundUsd <= 0) return;
    TrackingService.track('order_funding_failed', params: {
      'venue': 'hyperliquid',
      'stage': stage,
      'error_category':
          reason ?? TrackingService.errorCategory(error),
      'duration_ms':
          DateTime.now().difference(intent.createdAt).inMilliseconds,
      'order_kind': intent.orderKind,
    });
  }

  Future<HlMarket> _resolveMarket(PendingHlOrderIntent intent) async {
    final markets = intent.kind == HlMarketKind.spot
        ? await ref.read(hyperliquidSpotMarketsProvider.future)
        : await ref.read(hyperliquidPerpMarketsProvider.future);
    for (final m in markets) {
      if (m.coin == intent.coin) return m;
    }
    throw StateError('Unknown Hyperliquid market: ${intent.coin}');
  }

  /// Begin (or keep) the bounded balance poll while a deposit is in
  /// flight: every second at first, every four seconds after
  /// [kAwaitFastFor]. Idempotent — repeated _maybeFire calls won't stack
  /// timers.
  void _startAwaitPolling() {
    if (_awaitPoll != null) return;
    _awaitStart = DateTime.now();
    _scheduleTick();
  }

  void _scheduleTick() {
    final start = _awaitStart;
    if (start == null) return;
    final elapsed = DateTime.now().difference(start);
    final interval =
        elapsed < kAwaitFastFor ? kAwaitFastInterval : kAwaitSlowInterval;
    _awaitPoll = Timer(interval, _onTick);
  }

  void _onTick() {
    _awaitPoll = null;
    final intent = ref.read(pendingHyperliquidOrderProvider);
    if (intent == null ||
        intent.status != PendingHlOrderStatus.awaitingBalance) {
      _stopAwaitPolling();
      return;
    }
    // Give up after a sane ceiling so a never-arriving deposit doesn't
    // poll forever. The funds are safe on the exchange account
    // regardless (the sweeper brings them home); surface an actionable
    // failure so the user can retry (instant once the USDC is there).
    final start = _awaitStart;
    if (start != null && DateTime.now().difference(start) > kAwaitMaxWait) {
      _stopAwaitPolling();
      _trackAutofireFailed('funds_timeout', intent);
      _trackFundingFailed(intent, stage: 'credit', reason: 'timeout');
      ref.read(pendingHyperliquidOrderProvider.notifier).updateStatus(
            PendingHlOrderStatus.failed,
            errorMessage: l10nForLanguage(ref.read(settingsProvider).language)
                .hlFundsTimeout,
          );
      return;
    }
    _scheduleTick();
    unawaited(_maybeFire());
  }

  void _stopAwaitPolling() {
    _awaitPoll?.cancel();
    _awaitPoll = null;
    _awaitStart = null;
  }
}
