// Autonomous watcher that fires a Polymarket bet the moment USDC funds
// land — even if the user dismisses the PendingBetOverlay.
//
// Without this, the auto-fire was scoped to the overlay's StatefulWidget:
// once the user navigated away, the listener died, and a freshly-arrived
// USDC balance never triggered `placeOrder`. The overlay told the user
// "your bet will fire when funds land" — and silently broke that promise.
//
// This service is a long-lived (non-autoDispose) Provider. Once any UI
// surface bootstraps it (Home does, via `ref.watch`), it stays alive for
// the rest of the app session and keeps watching balance changes
// regardless of which screen is visible. Surface a placing tile via
// `placingPolymarketBetProvider` so the user gets feedback in the home
// Activity rail and the Predictions Active strip.
//
// Step-up (Wallet Hardening Phase 1b.5, D-10): the bet fires on the grant the
// user gave at confirm time ([confirmPendingBetAutofire]), held 30 minutes in
// memory only. The fire path consumes it against the exact order it is about
// to place, and only while the session is unlocked. No grant (for example
// after a restart) or an expired one cancels the bet and asks the user to
// confirm it again.
//
// One balance (2026-10): a bet short of venue cash is funded from Dollars
// by `OrderFundingController` and queued here at `awaitingBalance` with
// `PendingBetIntent.fundUsd`; the one approval the slip asked for binds
// both legs (`PmGrants.fundedBetReview`). The deposit's credit
// (`depositSettled`) fires it: a market bet is placed for what landed
// (down to the venue's minimum), a limit bet that landed short fails,
// and a bet queued more than 30 minutes ago never fires. The journey's
// `order_funding_*` outcome is reported from here.

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/formatters/polymarket_side_labels.dart'
    show polymarketMarketType;
import 'package:kute/helpers/auth_grant_registry.dart';
import 'package:kute/helpers/require_fresh_auth.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/l10n/l10n.dart';

import 'package:kute/providers/auth_provider.dart' show sessionUnlockedProvider;
import 'package:kute/providers/pending_polymarket_bet_provider.dart';
import 'package:kute/providers/polymarket_bet_controller.dart'
    show PolymarketBetController, polymarketRetryPrice, polymarketThinBookMessage;
import 'package:kute/services/polymarket/polymarket_fee_terms.dart';
import 'package:kute/providers/placing_polymarket_bet_provider.dart';
import 'package:kute/providers/polymarket_open_orders_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_cost_basis_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/services/one_balance/one_balance_state.dart'
    show OneBalanceVenue;
import 'package:kute/services/one_balance/order_funding.dart'
    show OrderFundingJourney, OrderFundingStage;
import 'package:kute/services/one_balance/prediction_funding_ledger.dart';
import 'package:kute/services/polymarket/fresh_fill.dart';
import 'package:kute/services/polymarket/hot_order_guard.dart';
import 'package:kute/services/polymarket/market_buy_quote.dart'
    show PolymarketOrderPlan, PolymarketThinBook;
import 'package:kute/services/polymarket/order_refusal.dart'
    show isPolymarketPriceRefusal, polymarketRefusalParams;
import 'package:kute/services/polymarket/sell_settlement.dart';
import 'package:kute/services/polymarket/polymarket_slippage_defaults.dart'
    show isPolymarketFastRound;
import 'package:kute/services/polymarket_backend_service.dart'
    show PolymarketOrderNotAcceptedException;
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/venue_analytics.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show OrderBook, OrderSide, OrderType;

const double _kMaxAutoSlippagePct = 30.0;

/// The CLOB's smallest order, the slip's floor too (`_kMinBetUsd`).
const double _kMinBetUsd = 1.0;

/// How long a queued bet waits for its funds to land before it is failed
/// with the funds-timeout copy. The money stays as venue cash (the
/// sweeper brings it home); the person can place again by hand.
const Duration kFundsTimeout = Duration(minutes: 12);

/// A funded market bet is placed for what actually landed, when the
/// deposit landed short: the largest stake whose stake plus fees fits
/// [balance] at [price] ([feeTerms]), never above [amount]. Null when
/// what landed cannot carry the venue's minimum: the bet fails instead.
/// `resized` says the stake shrank by a cent or more. A limit bet never
/// resizes (its price is the person's): short is short.
@visibleForTesting
({double usd, bool resized})? landedStakeFor({
  required double amount,
  required double balance,
  required PolymarketFeeTerms feeTerms,
  required double price,
  required bool isLimit,
}) {
  if (!amount.isFinite || amount <= 0) return null;
  final fits = isLimit
      ? min(amount, balance * 0.99)
      : min(amount, feeTerms.maxNotionalFor(balance, price));
  if (!fits.isFinite || fits < _kMinBetUsd) return null;
  final resized = fits + 0.01 <= amount;
  if (isLimit && resized) return null;
  return (usd: fits, resized: resized);
}

/// Whether [intent]'s market is a short round (5 or 15 minutes) whose end
/// has passed at [now]: its book is shut, so a bet still waiting on its
/// money, or about to be placed, stops with "This round closed before
/// your money arrived" instead of a generic refusal or a 12-minute wait.
@visibleForTesting
bool autofireRoundClosed(PendingBetIntent intent, {DateTime? now}) {
  final end = intent.marketEndAt;
  if (end == null) return false;
  final at = now ?? DateTime.now();
  if (at.isBefore(end)) return false;
  return isPolymarketFastRound(
      question: intent.marketQuestion, endAt: end, now: at);
}

/// The autofire grant slot for the one pending Polymarket bet (D-10). The
/// pending provider holds a single intent, so a new confirm replaces the
/// grant.
const String kPendingBetAutofireId = 'polymarket_pending_bet';

/// Slippage the autofire applies at [marketPrice].
double autofireSlippagePct(double marketPrice, double slippagePct) => min(
    marketPrice < 0.25 ? max(slippagePct, 10.0) : slippagePct,
    _kMaxAutoSlippagePct);

/// The order price the autofire submits at [marketPrice].
double autofireOrderPrice(double marketPrice, double slippagePct) =>
    (marketPrice * (1 + slippagePct / 100)).clamp(0.01, 0.99).toDouble();

/// The worst price the one approval of a funded market bet covers: the
/// prepared quote's cap, raised to the autofire's own rule on the price
/// the ticket showed ([autofireOrderPrice] at [autofireSlippagePct]). The
/// slip approves exactly this (`_fundedReviewIntent`); the order placed
/// once the money lands is priced from a fresh book under it.
double polymarketFundedWorstPrice(PendingBetIntent intent) {
  final quote = intent.marketQuote;
  final prepared = quote != null && quote.tokenId == intent.tokenId
      ? quote.maxPrice
      : 0.0;
  final slip = autofireSlippagePct(intent.expectedPrice, intent.slippagePct);
  return max(prepared, autofireOrderPrice(intent.expectedPrice, slip));
}

/// The Predictions balance at which a queued bet fires: 99% of its stake,
/// and for a bet funded from Dollars no less than what the venue held when
/// the move left plus 99% of what the move was quoted to bring (the
/// move has landed, not only venue cash that was already there).
double autofireFireAt(PendingBetIntent intent) {
  final stake = intent.amount * 0.99;
  final arriving = intent.fundArrivingUsd;
  if (!intent.funded || arriving == null) return stake;
  return max(stake, (intent.fundReadyUsd ?? 0) + arriving * 0.99);
}

/// The child grant for the one re-priced order a funded bet may send
/// after its first was refused for its price: bound to [actual], and only
/// while [actual] stays inside what [approval] (the confirm-time grant,
/// consumed by the first order) approved: the same wallet, market and
/// funding cap, no larger amount, no worse price, no wider slippage. A
/// lapsed or revoked approval, or any drift, throws; nothing is signed.
@visibleForTesting
AuthGrant autofireRetryGrant(AuthGrant approval, SensitiveIntent actual) {
  if (approval.revoked) throw const GrantRevoked();
  if (approval.isExpiredAt(AuthGrants.clock())) throw const GrantExpired();
  final drift = AuthGrants.driftBetween(approval.boundIntent, actual);
  if (drift.isNotEmpty) throw ReauthRequired(drift);
  return GrantGuard.chain(approval, actual);
}

/// Reads the book a funded bet is priced from once its money has landed:
/// the market feed's current snapshot, else the venue's REST book on the
/// warm connection.
final autofireBookReaderProvider =
    Provider<Future<OrderBook> Function(String tokenId)>(
  (ref) => (tokenId) async =>
      PolymarketBetController.liveBook(tokenId) ??
      await PolymarketBetController.restBook(tokenId,
          timeout: const Duration(seconds: 5)),
);

/// Follows an order the venue took without a fill in its answer to its
/// end ([PmSellSettlementWatcher], read-only): matched, killed, or not
/// said in time. [onStage] hears the in-play hold and the match.
typedef AutofireSettle = Future<PmSellSettlement> Function(
  Map<String, dynamic> response, {
  required String tokenId,
  required double orderedShares,
  void Function(PmSellStage stage, double shares)? onStage,
});

/// The venue's own reads of an accepted order and its trades.
final autofireSettlementProvider = Provider<AutofireSettle>((ref) => (response,
        {required tokenId, required orderedShares, onStage}) {
      final backend =
          ref.read(polymarketTradingProvider.notifier).backendService;
      return PmSellSettlementWatcher(
        readOrder: (id) async =>
            backend == null ? null : await backend.getOrderById(id),
        readTrade: backend?.getTradeById,
      ).watch(
        response: response,
        tokenId: tokenId,
        offeredShares: orderedShares,
        resting: false,
        buy: true,
        onStage: onStage,
      );
    });

final pendingBetAutoFireProvider = Provider<PendingBetAutoFire>((ref) {
  final svc = PendingBetAutoFire(ref);
  ref.onDispose(svc.dispose);
  return svc;
});

class PendingBetAutoFire {
  final Ref ref;
  bool _firing = false;
  late final ProviderSubscription<dynamic> _sub;
  StreamSubscription<void>? _depositSettled;

  PendingBetAutoFire(this.ref) {
    // Watch the trading provider for balance changes. Each time it
    // ticks (refresh, optimistic, push-driven), check whether the
    // pending bet can now be placed.
    _sub = ref.listen(polymarketTradingProvider, (_, __) {
      _maybeFire();
    });
    // The deposit's own path (PolymarketTradingNotifier.onDepositDelivered)
    // converts the money and re-reads the balance the moment Orchestra
    // delivers, then says so here: the bet fires on that, not on a poll.
    _depositSettled = ref
        .read(polymarketTradingProvider.notifier)
        .depositSettled
        .listen((_) {
      // The queued bet's move has landed (converted, spendable).
      final intent = ref.read(pendingPolymarketBetProvider);
      if (intent != null && intent.status == PendingBetStatus.awaitingBalance) {
        PredictionFundingLedger.instance.landed(intent.fundQuoteRef);
      }
      _maybeFire();
    });
    // Also re-check whenever the intent itself changes (a fresh setIntent
    // from the bet slip should trigger an immediate look at the
    // current balance — funds might already be there).
    ref.listen(pendingPolymarketBetProvider, (_, next) {
      // A cleared bet never fires: drop its confirm-time grant.
      if (next == null) {
        AuthGrantRegistry.instance.cancelAutofire(kPendingBetAutofireId);
      }
      _maybeFire();
    });
    AuthGrantRegistry.instance.addAutofireExpiredListener(_onAutofireExpired);
  }

  void dispose() {
    _sub.close();
    _depositSettled?.cancel();
    _stopAwaitPolling();
    AuthGrantRegistry.instance
        .removeAutofireExpiredListener(_onAutofireExpired);
  }

  /// D-10: the confirm-time grant lapsed before the bet could fire.
  void _onAutofireExpired(String intentId, String venue) {
    if (intentId != kPendingBetAutofireId) return;
    _cancelForReconfirm(venue: venue);
  }

  /// Cancels the queued bet with nothing placed and asks the user to confirm
  /// it again. [drift] means the order no longer matched the approval.
  void _cancelForReconfirm({
    String venue = IntentVenue.polymarket,
    String? placementId,
    bool drift = false,
  }) {
    final intent = ref.read(pendingPolymarketBetProvider);
    if (intent == null ||
        intent.status == PendingBetStatus.done ||
        intent.status == PendingBetStatus.awaitingConfirmation ||
        intent.status == PendingBetStatus.failed) {
      return;
    }
    _stopAwaitPolling();
    // Nothing will be placed for this move: its cash is released now.
    PredictionFundingLedger.instance
        .release(intent.fundQuoteRef, reason: 'abandoned');
    final l10n = l10nForLanguage(ref.read(settingsProvider).language);
    final msg = drift ? l10n.stepUpDetailsChanged : l10n.pendingIntentExpired;
    if (placementId != null) {
      ref.read(placingPolymarketBetProvider.notifier).markFailed(placementId, msg);
    }
    ref.read(pendingPolymarketBetProvider.notifier).updateStatus(
        PendingBetStatus.failed,
        errorMessage: msg,
        failureCode: drift ? 'approval_drift' : 'approval_expired');
    if (!drift) {
      TrackingService.track('pending_intent_expired', params: {'venue': venue});
    }
  }

  /// Consumes the confirm-time grant against [actual], the exact order about
  /// to be placed, and returns the single-use grant `placeOrder` takes. Null
  /// when the bet must not fire now: locked (it waits for the unlock), or no
  /// live grant or drift (cancelled, the user confirms again).
  AuthGrant? _autofireGrant(SensitiveIntent actual, {String? placementId}) {
    final approval = _autofireApproval(actual, placementId: placementId);
    return approval == null ? null : GrantGuard.chain(approval, actual);
  }

  /// [_autofireGrant]'s consumed confirm-time grant itself, which a market
  /// bet keeps for its one re-priced order ([autofireRetryGrant]).
  AuthGrant? _autofireApproval(SensitiveIntent actual, {String? placementId}) {
    final intent = ref.read(pendingPolymarketBetProvider);
    try {
      return AuthGrantRegistry.instance.consumeAutofire(
        kPendingBetAutofireId,
        actual,
        session: ref.read(stepUpSessionStateProvider),
      );
    } on GrantSessionLocked {
      if (placementId != null) {
        ref.read(placingPolymarketBetProvider.notifier).clear(placementId);
      }
      ref
          .read(pendingPolymarketBetProvider.notifier)
          .updateStatus(PendingBetStatus.awaitingBalance);
      return null;
    } on GrantMissing {
      if (intent != null) _trackFailed(intent, 'approval_expired');
      _cancelForReconfirm(placementId: placementId);
      return null;
    } on AuthGrantException catch (e) {
      trackGrantFailure(e, action: SensitiveAction.pmBet);
      if (intent != null) {
        _trackFailed(
            intent, e is ReauthRequired ? 'approval_drift' : 'user_cancelled');
      }
      _cancelForReconfirm(placementId: placementId, drift: e is ReauthRequired);
      return null;
    }
  }

  // Active while we're waiting for swapped USDC to land at the Safe. The
  // deposit's own path reads the balance and fires the bet the moment the
  // money lands (onDepositDelivered → depositSettled); this poll is the
  // safety net behind it (a deposit seen by no order-status poll, an app
  // that restarted mid-way), so it reads every 15 s, not every 4 s, and
  // the trading provider's own tick backs off to 30 s meanwhile. Before,
  // three loops overlapped while a bet waited: this one at 4 s, the
  // trading poll at 5 s and the order-status poll at 5 s.
  Timer? _awaitPoll;
  DateTime? _awaitStart;
  static const Duration _kAwaitPollInterval = Duration(seconds: 15);

  Future<void> _maybeFire() async {
    if (_firing) return;
    final intent = ref.read(pendingPolymarketBetProvider);
    if (intent == null) {
      _stopAwaitPolling();
      return;
    }
    // Auto-fire is only valid from `awaitingBalance` — the post-
    // BTC-swap state where the user already explicitly committed
    // to the bet (picked a pool, tapped Place, sent BTC, now we're
    // just waiting for the converted USDC.e to land at the Safe so
    // we can submit the order on their behalf).
    //
    // `awaitingDeposit` (the picker-open state) must NEVER auto-fire.
    // Per spec — "we choose all the time, never automatic bets" —
    // even when the user already has enough USDC at the Safe to
    // cover the bet, they have to pick a wallet and confirm. This
    // gate is what makes the picker actually visible to a user with
    // a sufficient balance; without it, the autofirer races the UI
    // and silently fires the order.
    if (intent.status != PendingBetStatus.awaitingBalance) {
      _stopAwaitPolling();
      return;
    }
    // A bet queued more than 30 minutes ago never fires, whatever the
    // balance says now: the person confirms it again.
    if (intent.isStale()) {
      _stopAwaitPolling();
      _trackFailed(intent, 'approval_expired');
      PredictionFundingLedger.instance
          .release(intent.fundQuoteRef, reason: 'timeout');
      if (intent.funded) {
        OrderFundingJourney.instance.failed(
            OneBalanceVenue.predictions, OrderFundingStage.credit, 'expired');
      }
      _cancelForReconfirm();
      return;
    }
    // A short round that closed while its money was on the way: its book
    // is shut. Stopped now (the money lands, or has landed, as
    // Predictions cash), never left waiting for the 12-minute timeout.
    if (autofireRoundClosed(intent)) {
      _stopAwaitPolling();
      _failRoundClosed(intent);
      return;
    }
    // Nothing signs behind the lock; the next trading tick after unlock
    // fires.
    if (!ref.read(sessionUnlockedProvider)) return;
    final balance =
        ref.read(polymarketTradingProvider).valueOrNull?.usdcBalance ?? 0;
    // Same threshold the overlay used: 99% of the requested amount.
    // The CLOB will reject anything that overcommits, and balance is
    // floating-point, so a tiny safety buffer prevents infinite races.
    // A bet funded from Dollars waits for its own move: what the venue
    // held when the move left plus 99% of what it was quoted to bring.
    // The deposit's own settle (depositSettled) marks the move landed:
    // then the stake alone decides.
    final key = intent.fundQuoteRef;
    final landed = key != null &&
        PredictionFundingLedger.instance.record(key)?.stage ==
            PredictionFundingStage.landed;
    if (balance < (landed ? intent.amount * 0.99 : autofireFireAt(intent))) {
      // Funds aren't fully here yet. Keep forcing fresh balance reads until
      // they land (or we time out). Without this, a swap that settles after
      // the trading provider's periodic poll has gone quiet — or while the
      // user has navigated away — left the bet stuck on "Contacting
      // Polymarket" forever, even though the USDC was already at the Safe.
      // A restart only "fixed" it because re-init forced a fresh read.
      _startAwaitPolling();
      return;
    }

    _stopAwaitPolling();
    // The move behind this bet is here.
    PredictionFundingLedger.instance.landed(intent.fundQuoteRef);
    _firing = true;
    try {
      await _placeOrder(intent);
    } catch (_) {
      // _placeOrder owns its own error reporting via providers; swallow
      // here so a thrown cancellation doesn't block subsequent attempts.
    } finally {
      _firing = false;
    }
  }

  /// Begin (or keep) the bounded balance-poll while we wait for swapped USDC.
  /// Idempotent — repeated `_maybeFire` calls won't stack timers.
  void _startAwaitPolling() {
    if (_awaitPoll != null) return;
    _awaitStart = DateTime.now();
    try {
      ref.read(polymarketTradingProvider.notifier).setPendingBetWaiting(true);
    } catch (_) {}
    _awaitPoll = Timer.periodic(_kAwaitPollInterval, (_) async {
      final intent = ref.read(pendingPolymarketBetProvider);
      if (intent == null ||
          intent.status != PendingBetStatus.awaitingBalance) {
        _stopAwaitPolling();
        return;
      }
      // Give up after a sane ceiling so a never-arriving swap doesn't poll
      // forever. The funds are safe at the Safe regardless; surface a clear,
      // actionable failure so the user can retry (which is instant once the
      // USDC is present) instead of staring at a frozen "Contacting
      // Polymarket".
      if (_awaitStart != null &&
          DateTime.now().difference(_awaitStart!) > kFundsTimeout) {
        _stopAwaitPolling();
        _trackFailed(intent, 'funds_timeout');
        PredictionFundingLedger.instance
            .release(intent.fundQuoteRef, reason: 'timeout');
        if (intent.funded) {
          // The Dollars left and sit as venue cash now; the sweeper
          // returns them.
          OrderFundingJourney.instance.failed(
              OneBalanceVenue.predictions, OrderFundingStage.credit, 'timeout');
        }
        final msg = l10nForLanguage(ref.read(settingsProvider).language)
            .betAutofireFundsTimeout;
        ref.read(pendingPolymarketBetProvider.notifier).updateStatus(
            PendingBetStatus.failed,
            errorMessage: msg,
            failureCode: 'funds_timeout');
        return;
      }
      // Force a fresh on-chain read (bypassing the 30s balance cache), THEN
      // re-check the fire gate DIRECTLY. We deliberately don't rely on the
      // provider-change listener (`_sub`) to re-enter `_maybeFire`: the
      // trading state has value-equality, so a refresh that returns an
      // "equal" snapshot (or a listener tick that's coalesced) wouldn't
      // notify — which stranded funded bets on "awaiting funds" even though
      // the USDC was already at the Safe. Awaiting the refresh and calling
      // `_maybeFire` here makes each tick a self-contained read-and-fire.
      try {
        ref.read(polymarketTradingProvider.notifier).invalidateBalanceCache();
      } catch (_) {}
      try {
        await ref.read(polymarketTradingProvider.notifier).refresh();
      } catch (_) {}
      await _maybeFire();
    });
  }

  void _stopAwaitPolling() {
    if (_awaitPoll != null) {
      try {
        ref
            .read(polymarketTradingProvider.notifier)
            .setPendingBetWaiting(false);
      } catch (_) {}
    }
    _awaitPoll?.cancel();
    _awaitPoll = null;
    _awaitStart = null;
  }

  /// Analytics for an autofired bet: entry_source 'autofire', origin = the
  /// surface that queued it.
  Map<String, Object> _analytics(PendingBetIntent intent) => {
        'origin': intent.entrySource ?? 'unknown',
        'funding_source': intent.btcLeg != null
            ? 'bitcoin'
            : intent.funded
                ? 'dollars'
                : 'venue_balance',
        if (intent.isLimit) 'limit_price': intent.limitPrice,
        if (!intent.isLimit)
          'slippage_bps': VenueAnalytics.bps(intent.slippagePct),
      };

  /// [intent]'s round closed before its money arrived (or before it could
  /// be placed): nothing is signed, the money stays as Predictions cash.
  void _failRoundClosed(PendingBetIntent intent, {String? placementId}) {
    _trackFailed(intent, 'market_closed');
    if (intent.funded) {
      OrderFundingJourney.instance.failed(OneBalanceVenue.predictions,
          OrderFundingStage.order, 'market_closed');
    }
    PredictionFundingLedger.instance
        .release(intent.fundQuoteRef, reason: 'failed');
    final msg = l10nForLanguage(ref.read(settingsProvider).language)
        .slipFundingRoundClosed;
    if (placementId != null) {
      ref.read(placingPolymarketBetProvider.notifier).markFailed(placementId, msg);
    }
    ref.read(pendingPolymarketBetProvider.notifier).updateStatus(
        PendingBetStatus.failed,
        errorMessage: msg,
        failureCode: 'market_closed');
  }

  void _trackFailed(PendingBetIntent intent, String reason,
      {StackTrace? stackTrace,
      bool retried = false,
      Object? error,
      Map<String, Object> settlement = const {}}) {
    final refusal =
        error is PolymarketOrderNotAcceptedException ? error.reason : null;
    TrackingService.polymarketBetFailed(
      marketId: intent.tokenId,
      reason: reason,
      side: 'buy',
      orderType: intent.isLimit ? 'limit' : 'market',
      amountUsd: intent.amount,
      walletKind: 'hot',
      entrySource: 'autofire',
      stackTrace: stackTrace,
      extra: {
        ..._analytics(intent),
        // Whether a second, re-priced order went out after the first was
        // refused for its price.
        'retried': retried,
        if (refusal != null) ...polymarketRefusalParams(refusal),
        ...settlement,
      },
    );
  }

  Future<void> _placeOrder(PendingBetIntent intent) async {
    final pendingNotifier = ref.read(pendingPolymarketBetProvider.notifier);
    final placingNotifier = ref.read(placingPolymarketBetProvider.notifier);
    final tradingNotifier = ref.read(polymarketTradingProvider.notifier);

    // D-10: never fire without the confirm-time grant (a restart drops it).
    if (!AuthGrantRegistry.instance.hasAutofireGrant(kPendingBetAutofireId)) {
      _trackFailed(intent, 'approval_expired');
      _cancelForReconfirm();
      return;
    }

    pendingNotifier.updateStatus(PendingBetStatus.placing);
    final journey = OrderFundingJourney.instance;
    final funded = intent.funded;
    if (funded) journey.credited(OneBalanceVenue.predictions);
    // The funding leg's cap and venue ride on the order intent too, so the
    // one approval the slip asked for covers exactly this order.
    final fundingLimits = funded
        ? PmGrants.fundingLimits(
            fundUsd: intent.fundUsd!,
            venue: IntentVenue.polymarket,
            directLegs: intent.directLegs,
            btcLeg: intent.btcLeg)
        : const <String, Object?>{};
    SensitiveIntent withFunding(SensitiveIntent order) => fundingLimits.isEmpty
        ? order
        : order.copyWith(limits: {...order.limits, ...fundingLimits});

    // LIMIT (GTC): the swapped USDC has landed — place the resting limit
    // order at the user's chosen price. No placing tile (it isn't a filled
    // position yet) and no slippage ladder; it sits on the book.
    if (intent.isLimit) {
      try {
        final price = intent.limitPrice.clamp(0.01, 0.99).toDouble();
        // Cap by the USDC actually at the Safe — the swap can land slightly
        // under intent.amount (the fire gate only requires 99% of it), and
        // the CLOB rejects any order whose cost exceeds the balance. Without
        // the cap the rejection strands the swapped USDC with no order
        // placed. Same 99% cap as the market path below.
        final balance =
            ref.read(polymarketTradingProvider).valueOrNull?.usdcBalance ?? 0;
        // A funded limit bet whose deposit landed short is not placed
        // for less at the person's price: it fails, the cash stays as
        // venue cash for the sweeper.
        if (funded &&
            landedStakeFor(
                    amount: intent.amount,
                    balance: balance,
                    feeTerms: intent.feeTerms ?? PolymarketFeeTerms.worstCase,
                    price: price,
                    isLimit: true) ==
                null) {
          _trackFailed(intent, 'insufficient_usdc');
          journey.failed(OneBalanceVenue.predictions, OrderFundingStage.order,
              'insufficient_funds');
          pendingNotifier.updateStatus(PendingBetStatus.failed,
              errorMessage:
                  l10nForLanguage(ref.read(settingsProvider).language)
                      .betAddFundsToPredict,
              failureCode: 'insufficient_usdc');
          PredictionFundingLedger.instance
              .release(intent.fundQuoteRef, reason: 'failed');
          return;
        }
        final effectiveAmount = min(intent.amount, balance * 0.99);
        double shares =
            ((effectiveAmount / price) * 100).floorToDouble() / 100;
        // The CLOB rejects orders under $1 — bump to the minimum when the
        // intent covers it, mirroring the market path. The overshoot is
        // bounded by one share-tick (≤ 1¢), which the 99% cap absorbs.
        if (shares * price < 1.0 && effectiveAmount >= 1.0) {
          shares = (1.0 / price * 100).ceilToDouble() / 100;
        }
        if (shares <= 0) {
          throw Exception('Amount too small for this limit price.');
        }
        final grant = _autofireGrant(withFunding(PmIntents.order(
          walletId: tradingNotifier.signingWalletId ?? '',
          tokenId: intent.tokenId,
          isBuy: true,
          amountMax: PmGrants.buyCostMicros(shares, price),
          limitPrice: price,
          orderType: OrderType.gtc.name,
        )));
        if (grant == null) {
          if (funded) journey.abandoned(OneBalanceVenue.predictions);
          PredictionFundingLedger.instance
              .release(intent.fundQuoteRef, reason: 'abandoned');
          return;
        }
        PredictionFundingLedger.instance.reserve(intent.fundQuoteRef);
        await tradingNotifier.placeOrder(
          tokenId: intent.tokenId,
          side: OrderSide.buy,
          size: shares,
          negRisk: intent.negRisk,
          price: price,
          orderType: OrderType.gtc,
          marketTitle: intent.marketQuestion,
          marketImage: intent.marketImage,
          marketOutcome: intent.outcomeName,
          marketCategory: intent.marketCategory,
          // Funded from Dollars (one balance) or after a BTC→USDC swap.
          source: funded ? 'usdc_pool' : 'btc_pool',
          entrySource: 'autofire',
          analytics: _analytics(intent),
          grant: grant,
        );
        unawaited(tradingNotifier.refresh().catchError((_) {}));
        ref.invalidate(polymarketOpenOrdersProvider);
        if (funded) {
          journey.completed(OneBalanceVenue.predictions,
              resized: false, amountUsd: shares * price);
        }
        // The resting order holds its own cash on the book (the venue's
        // open orders); the rest of the move is idle from now.
        PredictionFundingLedger.instance
            .release(intent.fundQuoteRef, reason: 'placed');
        pendingNotifier.updateStatus(PendingBetStatus.done);
        Future.delayed(const Duration(milliseconds: 600), () {
          try {
            pendingNotifier.clear();
          } catch (_) {}
        });
      } catch (e, st) {
        if (e is PendingPolymarketOrder) {
          if (funded) {
            journey.completed(OneBalanceVenue.predictions, resized: false);
          }
          PredictionFundingLedger.instance
              .release(intent.fundQuoteRef, reason: 'placed');
          pendingNotifier.updateStatus(PendingBetStatus.awaitingConfirmation);
          return;
        }
        PredictionFundingLedger.instance
            .release(intent.fundQuoteRef, reason: 'failed');
        _trackFailed(intent, TrackingService.errorCategory(e), stackTrace: st);
        if (funded) {
          journey.failed(OneBalanceVenue.predictions, OrderFundingStage.order,
              TrackingService.errorCategory(e));
        }
        pendingNotifier.updateStatus(PendingBetStatus.failed,
            errorMessage: _friendlyError(e), failureCode: _stopCode(e));
      }
      return;
    }

    // A short round already over: its book is shut, nothing is signed.
    if (autofireRoundClosed(intent)) {
      _failRoundClosed(intent);
      return;
    }

    // Register a placing tile so the user sees feedback wherever the
    // strip / home rail is visible — even if they're nowhere near the
    // PendingBetOverlay anymore. Pre-shares snapshot lets the home
    // listener tell when the buy actually lands on top of an existing
    // position vs creates a new one.
    final preShares = ref
        .read(polymarketActivePositionsProvider)
        .where((p) => p.tokenId == intent.tokenId)
        .fold<double>(0, (sum, p) => sum + p.size);
    final placementId = placingNotifier.markPlacing(
      tokenId: intent.tokenId,
      marketQuestion: intent.marketQuestion,
      marketImage: intent.marketImage,
      outcomeName: intent.outcomeName,
      amount: intent.amount,
      shares: 0,
      avgPrice: intent.expectedPrice,
      preExistingShares: preShares,
      step: 2,
      totalSteps: 3,
      stepLabel: l10nForLanguage(ref.read(settingsProvider).language)
          .betContactingPolymarket,
    );
    // If the overlay registered the tile earlier ("Sending bitcoin"
    // step 1), markPlacing reuses that id and the explicit
    // advanceStep here promotes it. For a USDC-direct retry through
    // autofire (no prior tile), the values above are used at create.
    placingNotifier.advanceStep(placementId,
        step: 2,
        label: l10nForLanguage(ref.read(settingsProvider).language)
            .betContactingPolymarket);

    final ledger = PredictionFundingLedger.instance;
    final fundingKey = intent.fundQuoteRef;
    var retried = false;
    try {
      // Limit intents never reach here — they return from the GTC branch
      // above. Everything below is the market (FAK) path.
      //
      // Priced from the book read AFTER the money landed, never from the
      // odds the slip showed at the tap: on a five-minute round or a game
      // in play the book moves in the seconds a move takes, and the old
      // price was killed. Same rule the slip's own placement uses: the
      // executable ask plus the order's tolerance (at least one tick),
      // on the market's increment, never past what the one approval
      // covers ([polymarketFundedWorstPrice]).
      final fees = intent.feeTerms ?? PolymarketFeeTerms.worstCase;
      final slippage =
          autofireSlippagePct(intent.expectedPrice, intent.slippagePct);
      final approvedMax = polymarketFundedWorstPrice(intent);
      // A deposit that landed as USDC.e is converted first, so the
      // conversion never sits between the book read and the signature.
      await tradingNotifier
          .readyCollateralForBuy(fees.allInCost(intent.amount, approvedMax));

      AuthGrant? approval;
      Map<String, dynamic>? response;
      var resized = false;
      var orderedShares = 0.0;
      for (var attempt = 0; attempt < 2; attempt++) {
        retried = attempt > 0;
        final book = await _freshBook(intent.tokenId);
        if (book == null) {
          _trackFailed(intent, 'book_unavailable', retried: retried);
          if (funded) {
            journey.failed(OneBalanceVenue.predictions, OrderFundingStage.order,
                'book_unavailable');
          }
          ledger.release(fundingKey, reason: 'failed');
          final msg = l10nForLanguage(ref.read(settingsProvider).language)
              .betAutofireBookUnavailable;
          pendingNotifier.updateStatus(PendingBetStatus.failed,
              errorMessage: msg, failureCode: 'book_unavailable');
          placingNotifier.markFailed(placementId, msg);
          return;
        }
        var fill = polymarketFillPrice(book,
            tokenId: intent.tokenId,
            amount: intent.amount,
            slippagePct: slippage,
            approvedMaxPrice: approvedMax,
            fees: fees);

        final balance =
            ref.read(polymarketTradingProvider).valueOrNull?.usdcBalance ?? 0;
        // The swap lands roughly the stake; the venue also takes its fees
        // from the same balance. A funded bet is placed for what landed
        // when the deposit came in short, down to the venue's minimum;
        // under it, it fails and the cash is released for the sweeper.
        final landed = landedStakeFor(
            amount: intent.amount,
            balance: balance,
            feeTerms: fees,
            price: fill.orderPrice,
            isLimit: false);
        if (funded && landed == null) {
          _trackFailed(intent, 'insufficient_usdc', retried: retried);
          journey.failed(OneBalanceVenue.predictions, OrderFundingStage.order,
              'insufficient_funds');
          ledger.release(fundingKey, reason: 'failed');
          final msg = l10nForLanguage(ref.read(settingsProvider).language)
              .betAddFundsToPredict;
          pendingNotifier.updateStatus(PendingBetStatus.failed,
              errorMessage: msg, failureCode: 'insufficient_usdc');
          placingNotifier.markFailed(placementId, msg);
          return;
        }
        resized = funded && (landed?.resized ?? false);
        final stake = landed?.usd ??
            min(intent.amount, fees.maxNotionalFor(balance, fill.orderPrice));
        if (stake + 1e-9 < intent.amount) {
          fill = polymarketFillPrice(book,
              tokenId: intent.tokenId,
              amount: stake,
              slippagePct: slippage,
              approvedMaxPrice: approvedMax,
              fees: fees);
        }
        var shares = PolymarketOrderPlan.sharesFor(stake, fill.orderPrice);
        // The market's own minimum order (in shares), not only the $1
        // floor: lifted to it when the money there covers it.
        final minShares = double.tryParse(book.minOrderSize ?? '') ?? 0;
        if (minShares > shares &&
            fees.allInCost(minShares * fill.orderPrice, fill.orderPrice) <=
                balance + 1e-9 &&
            minShares * fill.orderPrice <= intent.amount + 0.02) {
          shares = (minShares * 100).ceilToDouble() / 100;
        }
        orderedShares = shares;
        final actual = withFunding(PmIntents.order(
          walletId: tradingNotifier.signingWalletId ?? '',
          tokenId: intent.tokenId,
          isBuy: true,
          amountMax: PmGrants.buyCostMicros(shares, fill.orderPrice),
          limitPrice: fill.orderPrice,
          orderType: OrderType.fak.name,
          maxSlippageBps: IntentUnits.bps(slippage),
        ));
        final AuthGrant grant;
        final parent = approval;
        if (parent == null) {
          // The confirm-time approval, consumed against this exact order.
          final consumed = _autofireApproval(actual, placementId: placementId);
          if (consumed == null) {
            if (funded) journey.abandoned(OneBalanceVenue.predictions);
            ledger.release(fundingKey, reason: 'abandoned');
            return;
          }
          approval = consumed;
          grant = GrantGuard.chain(consumed, actual);
        } else {
          // The one re-priced order: inside the same approval's bounds
          // (amount, worst price, slippage, funding cap), never wider.
          grant = autofireRetryGrant(parent, actual);
        }

        // Final stage of the progress bar — the CLOB call is in flight.
        placingNotifier.advanceStep(placementId,
            step: 3,
            label: l10nForLanguage(ref.read(settingsProvider).language)
                .betPlacingOrder);
        ledger.reserve(fundingKey);
        try {
          response = await tradingNotifier.placeOrder(
            tokenId: intent.tokenId,
            side: OrderSide.buy,
            size: shares,
            negRisk: fill.quote.negRisk,
            marketQuote: fill.quote,
            price: fill.orderPrice,
            orderType: OrderType.fak,
            marketTitle: intent.marketQuestion,
            marketImage: intent.marketImage,
            marketOutcome: intent.outcomeName,
            marketCategory: intent.marketCategory,
            // Funded from Dollars (one balance) or after a BTC→USDC swap.
            source: funded ? 'usdc_pool' : 'btc_pool',
            entrySource: 'autofire',
            analytics: {
              ..._analytics(intent),
              'retried': retried,
              'quoted_price': fill.quotedPrice,
            },
            grant: grant,
          );
          break;
        } catch (e) {
          // Refused for its price (the book moved between the read and
          // the match): one more read and one re-priced order, from the
          // money already there. Nothing is funded again.
          if (attempt == 0 &&
              e is PolymarketOrderNotAcceptedException &&
              isPolymarketPriceRefusal(e.reason)) {
            continue;
          }
          rethrow;
        }
      }
      final placed = response!;

      // Record actual USDC moved on the BUY so the position detail
      // sheet's "Invested" reflects wallet truth, not the API's
      // rounded `avgPrice * size`. On a BUY the user is the maker
      // (offers USDC, takes shares), so the USDC side is
      // `makingAmount` — using `takingAmount` would record the
      // share count and produce nonsensical "Invested $13.04"
      // against 13.04 shares. Missing fill data stays unconfirmed.
      final makingRaw = placed['makingAmount'] ?? placed['making_amount'];
      double? paidUsdc;
      if (makingRaw is num) {
        paidUsdc = makingRaw.toDouble();
      } else if (makingRaw is String) {
        paidUsdc = double.tryParse(makingRaw);
      }
      final gotShares = double.tryParse(
          '${placed['takingAmount'] ?? placed['taking_amount']}');
      final verifiedFill =
          placed['status']?.toString().toLowerCase() == 'matched' &&
              paidUsdc != null &&
              paidUsdc.isFinite &&
              paidUsdc > 0 &&
              gotShares != null &&
              gotShares.isFinite &&
              gotShares > 0;
      if (verifiedFill) {
        unawaited(ref
            .read(polymarketCostBasisProvider.notifier)
            .addCost(intent.tokenId, paidUsdc)
            .catchError((_) {}));
      }

      pendingNotifier.recordFill(placed);
      unawaited(tradingNotifier.refresh().catchError((_) {}));
      // Taken without a fill in the answer: a game in play holds the order
      // for its in-play delay, then matches or kills it. Followed to that
      // end here, so the slip shows the receipt once it matched and says
      // the price moved once it was killed, instead of ending on "check
      // your positions" while the order was still going through.
      if (!verifiedFill &&
          placed['status']?.toString().toLowerCase() == 'delayed' &&
          await _followHeldOrder(intent, placed,
              orderedShares: orderedShares,
              placementId: placementId,
              retried: retried,
              resized: resized)) {
        return;
      }
      if (funded) {
        journey.completed(OneBalanceVenue.predictions,
            resized: resized, amountUsd: verifiedFill ? paidUsdc : null);
      }
      // What the order did not spend (a part fill, the rounding) is idle
      // from now: the warm window's, then the sweeper's.
      ledger.release(fundingKey, reason: 'placed');
      if (!verifiedFill) {
        ref.invalidate(polymarketOpenOrdersProvider);
        pendingNotifier.updateStatus(PendingBetStatus.awaitingConfirmation);
        placingNotifier.clear(placementId);
        return;
      }
      pendingNotifier.updateStatus(PendingBetStatus.done);
      // Hold the tile as a "Confirmed — appearing in your bets…" bridge
      // until the real position lands — the Data API lags the CLOB by
      // seconds to ~a minute, and the old 4 s auto-clear left the strip
      // showing nothing for the placed bet in between.
      placingNotifier.markSucceeded(
        placementId,
        holdUntilPositionArrives: verifiedFill,
      );
      // Clear the intent after a small delay so any UI listening to
      // PendingBetStatus.done has a chance to acknowledge it before
      // the state goes null.
      Future.delayed(const Duration(milliseconds: 600), () {
        try {
          pendingNotifier.clear();
        } catch (_) {}
      });
    } catch (e, st) {
      if (e is PendingPolymarketOrder) {
        if (funded) {
          journey.completed(OneBalanceVenue.predictions, resized: false);
        }
        // The order's answer is not in yet: the queued bet's own status
        // (awaiting confirmation) keeps the sweeper away until it is.
        ledger.release(fundingKey, reason: 'placed');
        pendingNotifier.updateStatus(PendingBetStatus.awaitingConfirmation);
        placingNotifier.clear(placementId);
        return;
      }
      // Refused because the round closed in the meantime: said as such.
      if (autofireRoundClosed(intent)) {
        _failRoundClosed(intent, placementId: placementId);
        return;
      }
      _trackFailed(intent, _failureCode(e),
          stackTrace: st, retried: retried, error: e);
      if (funded) {
        journey.failed(OneBalanceVenue.predictions, OrderFundingStage.order,
            TrackingService.errorCategory(e));
      }
      // Nothing was bought: the money stays as Predictions cash, released
      // at once (warm for a quick retry, then swept home to Dollars).
      ledger.release(fundingKey, reason: 'failed');
      final msg = _friendlyError(e);
      pendingNotifier.updateStatus(PendingBetStatus.failed,
          errorMessage: msg,
          retryMaxPrice: polymarketRetryPrice(e),
          failureCode: _stopCode(e));
      placingNotifier.markFailed(placementId, msg);
    }
  }

  /// Follows [placed], an order the venue took without a fill in its
  /// answer (a game in play holds it for its in-play delay, `delayed`).
  /// True when it ended here: matched (the bet is placed, the receipt
  /// shows) or ended with nothing bought (the price moved during the
  /// hold: the slip says so and the money stays as Predictions cash).
  /// False when the venue did not say in time: the bet then waits for its
  /// confirmation, never "failed" before anything is known.
  Future<bool> _followHeldOrder(
    PendingBetIntent intent,
    Map<String, dynamic> placed, {
    required double orderedShares,
    required String placementId,
    required bool retried,
    required bool resized,
  }) async {
    final pendingNotifier = ref.read(pendingPolymarketBetProvider.notifier);
    final placingNotifier = ref.read(placingPolymarketBetProvider.notifier);
    final tradingNotifier = ref.read(polymarketTradingProvider.notifier);
    final journey = OrderFundingJourney.instance;
    final ledger = PredictionFundingLedger.instance;
    final funded = intent.funded;
    final l10n = l10nForLanguage(ref.read(settingsProvider).language);
    if (orderedShares <= 0) return false;
    final matched = Completer<double>();
    final settling = ref
        .read(autofireSettlementProvider)(placed,
            tokenId: intent.tokenId,
            orderedShares: orderedShares, onStage: (stage, shares) {
          if (stage == PmSellStage.matched) {
            if (!matched.isCompleted) matched.complete(shares);
          } else {
            // Held for the game's in-play delay: the slip says why.
            pendingNotifier.setStage(PendingBetStage.delayed);
          }
        })
        .catchError((Object _) => PmSellSettlement(
            result: PmSellResult.unknown,
            offeredShares: orderedShares,
            soldShares: 0,
            firstStatus: '${placed['status'] ?? ''}'.toLowerCase(),
            confirmedBy: 'none',
            timeToMatch: Duration.zero));
    final first = await Future.any<Object>([matched.future, settling]);
    if (first is PmSellSettlement && first.soldShares <= 0) {
      switch (first.result) {
        case PmSellResult.notFilled:
        case PmSellResult.failed:
          // Nothing was bought: killed when the hold ended (the price had
          // moved past the order's), or the match failed on chain.
          final onChain = first.result == PmSellResult.failed;
          final code = onChain ? 'failed_onchain' : 'price_moved';
          _trackFailed(intent, onChain ? 'failed_onchain' : 'not_filled',
              retried: retried, settlement: first.analyticsParams());
          if (funded) {
            journey.failed(
                OneBalanceVenue.predictions, OrderFundingStage.order, code);
          }
          ledger.release(intent.fundQuoteRef, reason: 'failed');
          final msg =
              onChain ? l10n.betBuyFailedOnChain : l10n.betBuyNotMatched;
          pendingNotifier.updateStatus(PendingBetStatus.failed,
              errorMessage: msg, failureCode: code);
          placingNotifier.markFailed(placementId, msg);
          ref.invalidate(polymarketOpenOrdersProvider);
          return true;
        case PmSellResult.filled:
        case PmSellResult.partial:
        case PmSellResult.resting:
        case PmSellResult.unknown:
          return false;
      }
    }
    final settlementNow = first is PmSellSettlement ? first : null;
    final shares = settlementNow?.soldShares ?? first as double;
    final cost = settlementNow?.proceeds;
    pendingNotifier.recordSettlement(
        filledShares: shares, filledCost: cost, orderedShares: orderedShares);
    final orderId = PmSellSettlementWatcher.orderIdOf(placed);
    if (orderId != null && orderId.isNotEmpty) {
      tradingNotifier.notePendingFill(
        key: orderId,
        tokenId: intent.tokenId,
        shares: shares,
        costUsd: cost ?? shares * intent.expectedPrice,
      );
    }
    unawaited(tradingNotifier.refresh().catchError((_) {}));
    if (funded) {
      journey.completed(OneBalanceVenue.predictions,
          resized: resized, amountUsd: cost);
    }
    ledger.release(intent.fundQuoteRef, reason: 'placed');
    pendingNotifier.updateStatus(PendingBetStatus.done);
    placingNotifier.markSucceeded(placementId, holdUntilPositionArrives: true);
    Future.delayed(const Duration(milliseconds: 600), () {
      try {
        pendingNotifier.clear();
      } catch (_) {}
    });
    // The rest of the settlement behind the receipt: the venue's own cost
    // for the funnel, revenue and the cost basis (the answer echoed none).
    unawaited(settling.then((s) => _afterHeldFill(intent, placed, s,
        placementId: placementId, retried: retried)));
    return true;
  }

  /// A held order that matched: its fill reported from the venue's own
  /// figures (never estimated), or its on-chain failure said. Never
  /// throws.
  void _afterHeldFill(PendingBetIntent intent, Map<String, dynamic> placed,
      PmSellSettlement s,
      {required String placementId, required bool retried}) {
    try {
      if (s.result == PmSellResult.failed) {
        _trackFailed(intent, 'failed_onchain',
            retried: retried, settlement: s.analyticsParams());
        ref.read(placingPolymarketBetProvider.notifier).markFailed(
            placementId,
            l10nForLanguage(ref.read(settingsProvider).language)
                .betBuyFailedOnChain);
        return;
      }
      final cost = s.proceeds;
      if (s.soldShares <= 0 || cost == null || cost <= 0) return;
      unawaited(ref
          .read(polymarketCostBasisProvider.notifier)
          .addCost(intent.tokenId, cost)
          .catchError((_) {}));
      TrackingService.polymarketBetPlaced(
        side: 'buy',
        orderType: 'market',
        marketOutcome: intent.outcomeName,
        walletKind: 'hot',
        entrySource: 'autofire',
        marketId: intent.tokenId,
        outcome: 'buy',
        amount: cost,
        price: cost / s.soldShares,
        shares: s.soldShares.round(),
        providerOrderId: PmSellSettlementWatcher.orderIdOf(placed),
        category: intent.marketCategory,
        marketTitle: intent.marketQuestion,
        source: intent.funded ? 'usdc_pool' : 'btc_pool',
        betType: polymarketMarketType(intent.marketQuestion,
            outcome: intent.outcomeName),
        walletCategory: 'spending',
        extra: {
          ..._analytics(intent),
          ...s.analyticsParams(),
          'retried': retried,
          'approval': 'biometric',
        },
      );
    } catch (_) {
      // The app went on without it: nothing left to update.
    }
  }

  /// The book a funded bet is priced from, read now (a few tries for a
  /// slow venue); null when it cannot be read.
  Future<OrderBook?> _freshBook(String tokenId) async {
    final read = ref.read(autofireBookReaderProvider);
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) await Future.delayed(const Duration(milliseconds: 750));
      try {
        final book = await read(tokenId).timeout(const Duration(seconds: 6));
        if (book.asks.isNotEmpty || attempt == 2) return book;
      } catch (_) {
        // Transient (timeout / network) — try again.
      }
    }
    return null;
  }

  /// The failure class an autofired bet reports: the price-moved and
  /// thin-book stops by name, else the error's category.
  static String _failureCode(Object e) {
    if (e is PolymarketThinBook) return 'liquidity_unavailable';
    if (e is PolymarketOrderNotAcceptedException &&
        isPolymarketPriceRefusal(e.reason)) {
      return 'price_moved';
    }
    return TrackingService.errorCategory(e);
  }

  /// What the slip's steps say about a stop ([PendingBetIntent.
  /// failureCode]): a book past the approved maximum is the price moving
  /// ("Price moved too fast"), not the depth. Analytics keep
  /// [_failureCode].
  static String _stopCode(Object e) {
    if (e is PolymarketThinBook && polymarketRetryPrice(e) != null) {
      return 'price_moved';
    }
    return _failureCode(e);
  }

  /// Map raw CLOB / token-plumbing exception text to something the
  /// user can act on. Mirrors the overlay's `_friendlyPlacementError`
  /// — kept inline here so the autofire (which runs without a UI
  /// context) doesn't dump raw exception strings on the placing
  /// tile when an order is rejected post-swap.
  String _friendlyError(Object e) {
    final l10n = l10nForLanguage(ref.read(settingsProvider).language);
    if (e is ResolvedPolymarketOrder) return l10n.betPreviousOrderChecked;
    // The price moved past what the approval covers (the slip's own copy:
    // where it went, or what fills now).
    if (e is PolymarketThinBook) return polymarketThinBookMessage(l10n, e);
    if (e is PolymarketOrderNotAcceptedException &&
        isPolymarketPriceRefusal(e.reason)) {
      return l10n.betBuyLiquidityUnavailable;
    }
    return l10n.betActionNotCompleted;
  }
}
