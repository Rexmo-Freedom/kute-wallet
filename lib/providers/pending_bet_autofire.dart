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

import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/auth_grant_registry.dart';
import 'package:kute/helpers/require_fresh_auth.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/l10n/l10n.dart';

import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/auth_provider.dart' show sessionUnlockedProvider;
import 'package:kute/providers/pending_polymarket_bet_provider.dart';
import 'package:kute/services/polymarket/polymarket_fee_terms.dart';
import 'package:kute/providers/placing_polymarket_bet_provider.dart';
import 'package:kute/providers/polymarket_open_orders_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_cost_basis_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/services/polymarket/hot_order_guard.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/venue_analytics.dart';

const double _kMaxAutoSlippagePct = 30.0;

/// The autofire grant slot for the one pending Polymarket bet (D-10). The
/// pending provider holds a single intent, so a new confirm replaces the
/// grant.
const String kPendingBetAutofireId = 'polymarket_pending_bet';

/// Slippage the autofire applies at [marketPrice].
double _autofireSlippagePct(double marketPrice, double slippagePct) => min(
    marketPrice < 0.25 ? max(slippagePct, 10.0) : slippagePct,
    _kMaxAutoSlippagePct);

/// The order price the autofire submits at [marketPrice].
double _autofireOrderPrice(double marketPrice, double slippagePct) =>
    (marketPrice * (1 + slippagePct / 100)).clamp(0.01, 0.99).toDouble();

final pendingBetAutoFireProvider = Provider<PendingBetAutoFire>((ref) {
  final svc = PendingBetAutoFire(ref);
  ref.onDispose(svc.dispose);
  return svc;
});

class PendingBetAutoFire {
  final Ref ref;
  bool _firing = false;
  late final ProviderSubscription<dynamic> _sub;

  PendingBetAutoFire(this.ref) {
    // Watch the trading provider for balance changes. Each time it
    // ticks (refresh, optimistic, push-driven), check whether the
    // pending bet can now be placed.
    _sub = ref.listen(polymarketTradingProvider, (_, __) {
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
    final l10n = l10nForLanguage(ref.read(settingsProvider).language);
    final msg = drift ? l10n.stepUpDetailsChanged : l10n.pendingIntentExpired;
    if (placementId != null) {
      ref.read(placingPolymarketBetProvider.notifier).markFailed(placementId, msg);
    }
    ref
        .read(pendingPolymarketBetProvider.notifier)
        .updateStatus(PendingBetStatus.failed, errorMessage: msg);
    if (!drift) {
      TrackingService.track('pending_intent_expired', params: {'venue': venue});
    }
  }

  /// Consumes the confirm-time grant against [actual], the exact order about
  /// to be placed, and returns the single-use grant `placeOrder` takes. Null
  /// when the bet must not fire now: locked (it waits for the unlock), or no
  /// live grant or drift (cancelled, the user confirms again).
  AuthGrant? _autofireGrant(SensitiveIntent actual, {String? placementId}) {
    final intent = ref.read(pendingPolymarketBetProvider);
    try {
      final parent = AuthGrantRegistry.instance.consumeAutofire(
        kPendingBetAutofireId,
        actual,
        session: ref.read(stepUpSessionStateProvider),
      );
      return GrantGuard.chain(parent, actual);
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

  // Active while we're waiting for swapped USDC to land at the Safe. Forces a
  // fresh on-chain balance read on an interval so the bet fires the moment
  // funds arrive — even if the cross-chain swap settles minutes later while
  // the user is off-screen and the 5s position-poll has gone quiet.
  Timer? _awaitPoll;
  DateTime? _awaitStart;
  static const Duration _kAwaitPollInterval = Duration(seconds: 4);
  static const Duration _kAwaitMaxWait = Duration(minutes: 12);

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
    // Nothing signs behind the lock; the next trading tick after unlock
    // fires.
    if (!ref.read(sessionUnlockedProvider)) return;
    final balance =
        ref.read(polymarketTradingProvider).valueOrNull?.usdcBalance ?? 0;
    // Same threshold the overlay used: 99% of the requested amount.
    // The CLOB will reject anything that overcommits, and balance is
    // floating-point, so a tiny safety buffer prevents infinite races.
    if (balance < intent.amount * 0.99) {
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
          DateTime.now().difference(_awaitStart!) > _kAwaitMaxWait) {
        _stopAwaitPolling();
        _trackFailed(intent, 'funds_timeout');
        final msg = l10nForLanguage(ref.read(settingsProvider).language)
            .betAutofireFundsTimeout;
        ref
            .read(pendingPolymarketBetProvider.notifier)
            .updateStatus(PendingBetStatus.failed, errorMessage: msg);
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
    _awaitPoll?.cancel();
    _awaitPoll = null;
    _awaitStart = null;
  }

  /// Analytics for an autofired bet: entry_source 'autofire', origin = the
  /// surface that queued it.
  Map<String, Object> _analytics(PendingBetIntent intent) => {
        'origin': intent.entrySource ?? 'unknown',
        'funding_source': 'venue_balance',
        if (intent.isLimit) 'limit_price': intent.limitPrice,
        if (!intent.isLimit)
          'slippage_bps': VenueAnalytics.bps(intent.slippagePct),
      };

  void _trackFailed(PendingBetIntent intent, String reason,
      {StackTrace? stackTrace}) {
    TrackingService.polymarketBetFailed(
      marketId: intent.tokenId,
      reason: reason,
      side: 'buy',
      orderType: intent.isLimit ? 'limit' : 'market',
      amountUsd: intent.amount,
      walletKind: 'hot',
      entrySource: 'autofire',
      stackTrace: stackTrace,
      extra: _analytics(intent),
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
        final grant = _autofireGrant(PmIntents.order(
          walletId: tradingNotifier.signingWalletId ?? '',
          tokenId: intent.tokenId,
          isBuy: true,
          amountMax: PmGrants.buyCostMicros(shares, price),
          limitPrice: price,
          orderType: OrderType.gtc.name,
        ));
        if (grant == null) return;
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
          source: 'btc_pool', // autofire only runs after a BTC→USDC swap
          entrySource: 'autofire',
          analytics: _analytics(intent),
          grant: grant,
        );
        unawaited(tradingNotifier.refresh().catchError((_) {}));
        ref.invalidate(polymarketOpenOrdersProvider);
        pendingNotifier.updateStatus(PendingBetStatus.done);
        Future.delayed(const Duration(milliseconds: 600), () {
          try {
            pendingNotifier.clear();
          } catch (_) {}
        });
      } catch (e, st) {
        if (e is PendingPolymarketOrder) {
          pendingNotifier.updateStatus(PendingBetStatus.awaitingConfirmation);
          return;
        }
        _trackFailed(intent, TrackingService.errorCategory(e), stackTrace: st);
        pendingNotifier.updateStatus(PendingBetStatus.failed,
            errorMessage: _friendlyError(e));
      }
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

    try {
      // Limit intents never reach here — they return from the GTC branch
      // above. Everything below is the market (FAK) path.

      // Order book read — used to confirm a real ask exists. Same
      // gating rationale as the overlay: a flat zero book means the
      // CLOB has nothing to fill against, so we surface a clear
      // failure rather than letting the user wait on a phantom
      // order.
      double bestAsk = 0;
      final model = PolymarketModel();
      try {
        // The order-book read had NO timeout — if the CLOB API hung, the
        // autofire froze at "Contacting Polymarket" forever: the await never
        // returned, `_firing` never reset, and no later balance tick could
        // retry. Net effect was the BTC→USDC swap landing but the bet never
        // placing, with the funds left stranded in the Polymarket balance.
        // Bound each read with a timeout and retry a few times so transient
        // slowness still lets the bet land.
        for (var attempt = 0; attempt < 3 && bestAsk <= 0; attempt++) {
          if (attempt > 0) {
            await Future.delayed(const Duration(milliseconds: 1500));
          }
          try {
            final book = await model
                .getOrderBook(intent.tokenId)
                .timeout(const Duration(seconds: 12));
            if (book.bestAsk != null && book.bestAsk! > 0) {
              bestAsk = book.bestAsk!;
            }
          } catch (_) {
            // Transient (timeout / network) — fall through to the next try.
          }
        }
      } finally {
        model.dispose();
      }
      if (bestAsk <= 0) {
        _trackFailed(intent, 'book_unavailable');
        final msg = l10nForLanguage(ref.read(settingsProvider).language)
            .betAutofireBookUnavailable;
        pendingNotifier.updateStatus(PendingBetStatus.failed,
            errorMessage: msg);
        placingNotifier.markFailed(placementId, msg);
        return;
      }

      // Only price off the WS snapshot while the feed is actually
      // flowing — a paused feed (user parked on Home) keeps minutes-old
      // prices that must not shadow the just-fetched REST bestAsk.
      final livePrices = ref.read(livePriceProvider);
      final double marketPrice = (intent.expectedPrice > 0
              ? intent.expectedPrice
              : ((livePrices.live ? livePrices.prices[intent.tokenId] : null) ??
                  bestAsk))
          .clamp(0.01, 0.99)
          .toDouble();

      final balance =
          ref.read(polymarketTradingProvider).valueOrNull?.usdcBalance ?? 0;

      // Same rule [pendingBetAutofireIntent] approved.
      final slippage = _autofireSlippagePct(marketPrice, intent.slippagePct);
      final orderPrice = _autofireOrderPrice(marketPrice, slippage);
      // The swap lands roughly the stake; the venue also takes its fees
      // from the same balance. Size the stake so stake plus fees fits what
      // actually arrived (documented maxima when the curve was not read),
      // instead of shaving a flat 1% that neither matched the fees nor
      // left enough on low-priced outcomes.
      final effectiveAmount = min(
          intent.amount,
          (intent.feeTerms ?? PolymarketFeeTerms.worstCase)
              .maxNotionalFor(balance, orderPrice));

      // Snap to market tick (assumed 0.01) before sizing — the CLOB
      // computes makerAmount against the tick-rounded price, and if
      // we used the raw orderPrice the resulting USDC could drop
      // below the $1 minimum even though our intent matched. Same
      // fix as bet_slip_sheet's _handleBuy.
      final snappedOrderPrice =
          ((orderPrice * 100).roundToDouble() / 100).clamp(0.01, 0.99);
      final rawShares = effectiveAmount / snappedOrderPrice;
      final flooredShares = (rawShares * 100).floorToDouble() / 100;
      double shares = flooredShares;

      // Floor underspends by up to (snappedOrderPrice * 0.01) ≈ 1¢.
      // If shortfall is closer to a full share-tick than to zero, ceil
      // up so $2 → $2 instead of $1.99. Bounded by balance (already
      // capped at 99% above) so the <1¢ overshoot can't bust funds.
      final flooredCost = flooredShares * snappedOrderPrice;
      final shortfall = effectiveAmount - flooredCost;
      if (shortfall >= snappedOrderPrice * 0.005) {
        final ceiledShares = (rawShares * 100).ceilToDouble() / 100;
        if (ceiledShares * snappedOrderPrice <= balance) {
          shares = ceiledShares;
        }
      }

      if (shares * snappedOrderPrice < 1.0 && effectiveAmount >= 1.0) {
        shares = (1.0 / snappedOrderPrice * 100).ceilToDouble() / 100;
      }

      final grant = _autofireGrant(
        PmIntents.order(
          walletId: tradingNotifier.signingWalletId ?? '',
          tokenId: intent.tokenId,
          isBuy: true,
          amountMax: PmGrants.buyCostMicros(shares, orderPrice),
          limitPrice: orderPrice,
          orderType: OrderType.fak.name,
          maxSlippageBps: IntentUnits.bps(slippage),
        ),
        placementId: placementId,
      );
      if (grant == null) return;

      // Final stage of the progress bar — the CLOB call is in flight.
      placingNotifier.advanceStep(placementId,
          step: 3,
          label: l10nForLanguage(ref.read(settingsProvider).language)
              .betPlacingOrder);

      final response = await tradingNotifier.placeOrder(
        tokenId: intent.tokenId,
        side: OrderSide.buy,
        size: shares,
        negRisk: intent.negRisk,
        price: orderPrice,
        orderType: OrderType.fak,
        marketTitle: intent.marketQuestion,
        marketImage: intent.marketImage,
        marketOutcome: intent.outcomeName,
        marketCategory: intent.marketCategory,
        source: 'btc_pool', // autofire only runs after a BTC→USDC swap
        entrySource: 'autofire',
        analytics: _analytics(intent),
        grant: grant,
      );

      // Record actual USDC moved on the BUY so the position detail
      // sheet's "Invested" reflects wallet truth, not the API's
      // rounded `avgPrice * size`. On a BUY the user is the maker
      // (offers USDC, takes shares), so the USDC side is
      // `makingAmount` — using `takingAmount` would record the
      // share count and produce nonsensical "Invested $13.04"
      // against 13.04 shares. Missing fill data stays unconfirmed.
      final makingRaw = response['makingAmount'] ?? response['making_amount'];
      double? paidUsdc;
      if (makingRaw is num) {
        paidUsdc = makingRaw.toDouble();
      } else if (makingRaw is String) {
        paidUsdc = double.tryParse(makingRaw);
      }
      final gotShares = double.tryParse('${response['takingAmount'] ?? response['taking_amount']}');
      final verifiedFill = response['status']?.toString().toLowerCase() == 'matched' &&
          paidUsdc != null && paidUsdc.isFinite && paidUsdc > 0 &&
          gotShares != null && gotShares.isFinite && gotShares > 0;
      if (verifiedFill) {
        unawaited(ref
            .read(polymarketCostBasisProvider.notifier)
            .addCost(intent.tokenId, paidUsdc)
            .catchError((_) {}));
      }

      pendingNotifier.recordFill(response);
      unawaited(tradingNotifier.refresh().catchError((_) {}));
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
        pendingNotifier.updateStatus(PendingBetStatus.awaitingConfirmation);
        placingNotifier.clear(placementId);
        return;
      }
      _trackFailed(intent, TrackingService.errorCategory(e), stackTrace: st);
      final msg = _friendlyError(e);
      pendingNotifier.updateStatus(PendingBetStatus.failed, errorMessage: msg);
      placingNotifier.markFailed(placementId, msg);
    }
  }

  /// Map raw CLOB / token-plumbing exception text to something the
  /// user can act on. Mirrors the overlay's `_friendlyPlacementError`
  /// — kept inline here so the autofire (which runs without a UI
  /// context) doesn't dump raw exception strings on the placing
  /// tile when an order is rejected post-swap.
  String _friendlyError(Object e) {
    final l10n = l10nForLanguage(ref.read(settingsProvider).language);
    if (e is ResolvedPolymarketOrder) return l10n.betPreviousOrderChecked;
    return l10n.betActionNotCompleted;
  }
}
