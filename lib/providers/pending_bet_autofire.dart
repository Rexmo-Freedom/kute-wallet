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
// `order_funding_*` outcome is reported from here. A bet is queued here
// only by the slip's Confirm (founder decision, 11 November 2026:
// pre-funding removed; nothing is armed, funded or queued before the
// person accepts).
//
// The next window (founder, 8 November 2026): a 5-minute card's buttons
// roll to the next window partway through this one, so a bet queued for it
// can land before that window starts or after. Neither changes anything
// here: it stays on the tokens it was approved for, a fresh book under the
// approved worst price places it, a price past that stops it with the
// price now, and a window that has ended stops it as any round that ended.
//
// Landed is not usable (founder, 15 October 2026: "$3.68 on Yes" funded
// from Dollars failed with "This action did not complete"): the deposit
// arrives as USDC.e, which the order book does not count, and once
// converted the book still counts the old pUSD until it re-reads. The
// summed cash the landed check reads counts both. So after it, the bet
// waits (read every second) until the pUSD on chain covers it and the
// book counts it ([autofireReadiness]); only then does it move to
// `placing`. A venue refusal that still says only "not usable yet"
// ([autofireNotReadyYet]) waits for that again and is sent again under
// the same approval, spaced out and bounded by the funds wait
// ([kAutofireNotReadyRetries] sends at most): an approval being mined or
// the book's count catching up late is waited out, never five sends
// spent in seconds and a generic failure while the money sits there.

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, visibleForTesting;
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
import 'package:kute/services/polymarket/relayer_wallet_queue.dart'
    show isTransientRelayerRefusal;
import 'package:kute/services/polymarket/polymarket_fee_terms.dart';
import 'package:kute/providers/placing_polymarket_bet_provider.dart';
import 'package:kute/providers/polymarket_open_orders_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_cost_basis_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/services/polymarket/usdce_wrap_gate.dart'
    show FundedConversionHold, WrapPhase, WrapTimeline, fundedConversionHeld;
import 'package:kute/services/polymarket/funded_chain_watch.dart';
import 'package:kute/services/polymarket_onboarding_service.dart'
    show PolygonPollReadFailed;
import 'package:kute/services/platform/background_grace.dart'
    show BackgroundGrace;
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding;
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/services/one_balance/one_balance_state.dart'
    show OneBalanceVenue;
import 'package:kute/services/one_balance/order_funding.dart'
    show OrderFundingJourney, OrderFundingLeg, OrderFundingStage;
import 'package:kute/services/one_balance/prediction_funding_ledger.dart';
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/services/one_balance/money_steps.dart';
import 'package:kute/screens/polymarket/components/price_format.dart'
    show formatPolyChance;
import 'package:kute/services/polymarket/crypto_round.dart'
    show kCryptoUpDown5mKind, polyIsCryptoUpDown5m, polyRoundWindowParams;
import 'package:kute/services/polymarket/fresh_fill.dart';
import 'package:kute/services/polymarket/hot_order_guard.dart';
import 'package:kute/services/polymarket/order_connection.dart';
import 'package:kute/services/polymarket/market_buy_quote.dart'
    show PolymarketOrderPlan, PolymarketThinBook, PolymarketMarketBuyQuote;
import 'package:kute/services/polymarket/order_refusal.dart'
    show
        PolymarketBalanceRefused,
        PolymarketRefusalOutlivedApproval,
        isPolymarketPriceRefusal,
        polymarketRefusalParams;
import 'package:kute/services/polymarket/placement_waits.dart'
    show
        PolymarketFundsConverting,
        PolymarketSetupIncomplete,
        PolymarketCollateralPending;
import 'package:kute/services/polymarket/venue_collateral.dart'
    show PolyVenueCount, polyBuySpenders;
import 'package:kute/services/polymarket/sell_settlement.dart';
import 'package:kute/services/polymarket/placement_timeline.dart';
import 'package:kute/services/polymarket/polymarket_slippage_defaults.dart'
    show isPolymarketFastRound;
import 'package:kute/services/standing_orders/polymarket_signed_order.dart'
    show StandingSignedOrder;
import 'package:kute/services/standing_orders/standing_orders_provider.dart'
    show StandingOrderFailure, standingOrdersProvider;
import 'package:kute/services/polymarket_backend_service.dart'
    show PolymarketOrderNotAcceptedException, isPolymarketBalanceRefusal;
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
  double reserve = 0,
}) {
  if (!amount.isFinite || amount <= 0) return null;
  final fits = isLimit
      ? min(amount, balance * 0.99)
      : min(amount, feeTerms.maxNotionalFor(balance, price, reserve: reserve));
  if (!fits.isFinite || fits < _kMinBetUsd) return null;
  final resized = fits + 0.01 <= amount;
  if (isLimit && resized) return null;
  return (usd: fits, resized: resized);
}

/// How many times a bet is sent again after the venue refused it only
/// because the money was not usable yet ([autofireNotReadyYet]). A safety
/// cap: the real bound is time (the funds wait, counted from the first
/// such refusal), and the sends are spaced out (1 s, 2 s, 4 s ... up to
/// 15 s), so a spend approval being mined or the order book's balance
/// view catching up a minute late is waited out instead of five sends
/// being spent in a few seconds (founder, 19 October 2026: "Moved $4.73
/// from Bitcoin", then "Confirming balance" failed with "This action did
/// not complete").
const int kAutofireNotReadyRetries = 12;

/// The longest gap between two sends after "not usable yet", in
/// [PendingBetAutoFire.readyPollInterval]s.
const int _kNotReadyMaxGapPolls = 15;

/// Below one cent of USDC.e there is nothing to convert.
final BigInt _kUsdceDustMicros = BigInt.from(10000);

/// How many readiness looks (one a second) a reading short of the bet's
/// money must hold, unchanged, before it is taken for a short landing.
/// The wallet's pUSD and USDC.e are two separate chain reads, each
/// answered by whichever endpoint is first: around the block a conversion
/// is mined in, or right after a leg's status says delivered, one can show
/// the wallet before and the other after (pUSD not there yet, USDC.e
/// already gone, or neither yet). A landing that really came in short
/// reads the same on every look.
const int kShortLandingLooks = 5;

/// Where a queued bet's landed money is, from the deposit wallet's [pusd]
/// and [usdce] read on chain, what the order book counts ([venue], null
/// when it could not be read) and whether the account's setup is done,
/// for a buy costing [costMicros] (fees included) drawn by [spenders]:
///  - converting: pUSD is short and USDC.e is there (the book counts only
///    pUSD);
///  - waitingFunds: nothing usable on chain yet;
///  - approving: the account's setup is still running, or the book
///    reports an exchange allowance short;
///  - confirming: the book does not count the pUSD yet;
///  - ready.
/// [costMicros] is the actual executable order's all-in cost. A smaller
/// market order is sized separately, only after its own funding completed.
@visibleForTesting
PredictionsReadiness autofireReadiness({
  required BigInt pusd,
  required BigInt usdce,
  required BigInt costMicros,
  required PolyVenueCount? venue,
  required List<String> spenders,
  required bool setupDone,
}) {
  if (pusd < costMicros && usdce >= _kUsdceDustMicros) {
    return PredictionsReadiness.converting;
  }
  if (pusd < costMicros || costMicros <= BigInt.zero) {
    return PredictionsReadiness.waitingFunds;
  }
  if (!setupDone) return PredictionsReadiness.approving;
  if (venue == null) return PredictionsReadiness.confirming;
  if (venue.shortSpenders(spenders, costMicros).isNotEmpty) {
    return PredictionsReadiness.approving;
  }
  if (venue.balance < costMicros) return PredictionsReadiness.confirming;
  return PredictionsReadiness.ready;
}

/// A refusal that says only that the money is not usable yet: the venue
/// does not count the balance or allowance, the conversion or the
/// account's setup is still running. Nothing was accepted. Never one that
/// outlived its approval.
@visibleForTesting
bool autofireNotReadyYet(Object e) {
  if (e is PolymarketRefusalOutlivedApproval) return false;
  // Refused by its approval, never sent: no send again under it.
  if (e is AuthGrantException) return false;
  if (e is PolymarketFundsConverting ||
      e is PolymarketSetupIncomplete ||
      e is PolymarketCollateralPending) {
    return true;
  }
  // The deposit wallet's relayer still busy with another action (a
  // conversion confirming) or its nonce moved: nothing was accepted.
  if (isTransientRelayerRefusal(e)) return true;
  return e is PolymarketBalanceRefused ||
      e is PolymarketOrderNotAcceptedException &&
          isPolymarketBalanceRefusal(e.reason);
}

/// The approval behind a bet that waited for its money ran out (or the
/// bet outlived its queued age): it asks to be confirmed again.
class _ApprovalLapsed implements Exception {
  const _ApprovalLapsed();
}

/// Whether [intent]'s market is a short round (5 or 15 minutes) whose end
/// has passed at [now]: its book is shut, so a bet still waiting on its
/// money, or about to be placed, stops with "This round closed before
/// your money arrived" instead of a generic refusal or a 12-minute wait.
/// The slip reads it too: a stop on a round that ended retries on the
/// series' round in play.
bool autofireRoundClosed(PendingBetIntent intent, {DateTime? now}) {
  final end = intent.marketEndAt;
  if (end == null) return false;
  final at = now ?? DateTime.now();
  if (at.isBefore(end)) return false;
  return isPolymarketFastRound(
      slug: intent.eventSlug,
      question: intent.marketQuestion,
      endAt: end,
      now: at);
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
  final drift = AuthGrants.driftError(approval.boundIntent, actual);
  if (drift != null) throw drift;
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
  bool _disposed = false;
  ({
    String token,
    DateTime? queuedAt,
    String? runId,
    double usd
  })? _confirmedCash;

  /// The funded attempt whose money the deposit wallet's own balances
  /// (pUSD + USDC.e, read on chain) showed all of: from then on its one
  /// conversion and its order may run ([FundedConversionHold]).
  ({String token, DateTime? queuedAt, String? runId})? _landedConfirmed;
  void Function()? _uninstallHold;
  void Function()? _uninstallWrapTimeline;

  /// Which poll is refreshing the trading state on the autofire's behalf
  /// now, so the change it publishes is credited to it (`detected_by`).
  String? _refreshingFor;

  /// Test seam: whether a chain read may go out now. Defaults to the app
  /// in the foreground (or a background grace held) with the session
  /// unlocked.
  @visibleForTesting
  static bool Function()? debugChainCanRead;

  /// Test seam: the clock of the chain watch's cadence.
  @visibleForTesting
  static DateTime Function()? debugChainClock;

  /// Test seam: how long a short reading must hold before it is a short
  /// landing ([kShortLandingLooks] readiness looks when null).
  @visibleForTesting
  static Duration? debugShortLandingGrace;

  /// The funded bet's own on-chain watch (funded_chain_watch.dart): one
  /// shared ticker, one read in flight, 1 s for 30 s after funding, 4 s
  /// until 2 min, then the 15 s await poll alone.
  late final FundedChainWatch _chainWatch = FundedChainWatch(
    read: _readChain,
    onRead: _onChainRead,
    canRead: () =>
        debugChainCanRead?.call() ??
        (!_disposed &&
            ref.read(sessionUnlockedProvider) &&
            (_appInForeground() || BackgroundGrace.activeCount > 0)),
    clock: debugChainClock,
  );

  /// The chain watch, for tests.
  @visibleForTesting
  FundedChainWatch get chainWatch => _chainWatch;

  static bool _appInForeground() {
    try {
      final state = WidgetsBinding.instance.lifecycleState;
      return state == null ||
          state == AppLifecycleState.resumed ||
          state == AppLifecycleState.inactive;
    } catch (_) {
      return true;
    }
  }

  /// The funded attempt's credit timings (the `ms_*` and `detected_by`
  /// on its `order_funding_*` outcome): when the wallet was seen holding
  /// every leg's money, and the conversion's moments after it.
  _CreditTimeline? _timeline;

  bool _landedConfirmedFor(PendingBetIntent intent) {
    final c = _landedConfirmed;
    return c != null &&
        c.token == intent.tokenId &&
        c.queuedAt == intent.queuedAt &&
        c.runId == intent.fundedRunId;
  }

  /// Whether the pending funded bet's money is still on its way: no
  /// conversion runs meanwhile ([fundedConversionHeld]).
  bool _conversionHeld() {
    if (_disposed) return false;
    final intent = ref.read(pendingPolymarketBetProvider);
    if (intent == null) return false;
    return fundedConversionHeld(
      funded: intent.funded,
      fundingRunning: intent.status == PendingBetStatus.converting,
      awaitingBalance: intent.status == PendingBetStatus.awaitingBalance,
      landedConfirmed: _landedConfirmedFor(intent),
    );
  }

  /// How often a landed bet's readiness is read while it waits.
  @visibleForTesting
  static Duration readyPollInterval = const Duration(seconds: 1);
  Timer? _readyPoll;
  late final ProviderSubscription<dynamic> _sub;
  StreamSubscription<void>? _depositSettled;

  PendingBetAutoFire(this.ref) {
    _uninstallHold = FundedConversionHold.install(_conversionHeld);
    _uninstallWrapTimeline = WrapTimeline.install(_onWrapPhase);
    // Watch the trading provider for balance changes. Each time it
    // ticks (refresh, optimistic, push-driven), check whether the
    // pending bet can now be placed.
    _sub = ref.listen(polymarketTradingProvider, (_, __) {
      _maybeFire(source: _refreshingFor ?? CreditDetectedBy.tradingPoll);
    });
    // The deposit's own path (PolymarketTradingNotifier.onDepositDelivered)
    // converts the money and re-reads the balance the moment Orchestra
    // delivers, then says so here: the bet fires on that, not on a poll.
    _depositSettled =
        ref.read(polymarketTradingProvider.notifier).depositSettled.listen((_) {
      // This signal has no order identity: a first leg or an unrelated
      // deposit must not certify every leg of the queued bet as landed.
      _maybeFire(source: CreditDetectedBy.status);
    });
    // Also re-check whenever the intent itself changes (a fresh setIntent
    // from the bet slip should trigger an immediate look at the
    // current balance — funds might already be there).
    ref.listen(pendingPolymarketBetProvider, (_, next) {
      // A cleared bet never fires: drop its confirm-time grant.
      if (next == null) {
        AuthGrantRegistry.instance.cancelAutofire(kPendingBetAutofireId);
      }
      _maybeFire(source: CreditDetectedBy.status);
    });
    ref.listen(fundedOrdersProvider,
        (_, __) => _maybeFire(source: CreditDetectedBy.status));
    AuthGrantRegistry.instance.addAutofireExpiredListener(_onAutofireExpired);
  }

  void dispose() {
    _disposed = true;
    _uninstallHold?.call();
    _uninstallWrapTimeline?.call();
    _chainWatch.dispose();
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
  /// to be placed, and returns it; the order's single-use grant is chained
  /// from it (`GrantGuard.chain`), and a bet keeps it for its one
  /// re-priced order or a send again after "not usable yet"
  /// ([autofireRetryGrant]). Null when the bet must not fire now: locked
  /// (it waits for the unlock), or no live grant or drift (cancelled, the
  /// user confirms again).
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
  @visibleForTesting
  static Duration awaitPollInterval = const Duration(seconds: 15);

  @visibleForTesting
  static Duration fundsTimeout = kFundsTimeout;

  Future<void> _maybeFire({String source = CreditDetectedBy.status}) async {
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
    final balance =
        ref.read(polymarketTradingProvider).valueOrNull?.usdcBalance ?? 0;
    // Same threshold the overlay used: 99% of the requested amount.
    // The CLOB will reject anything that overcommits, and balance is
    // floating-point, so a tiny safety buffer prevents infinite races.
    // A bet funded from Dollars waits for its own move: what the venue
    // held when the move left plus 99% of what it was quoted to bring.
    // Only this attempt's own completed funding legs can permit a short
    // landing to resize. An unscoped deposit notification only wakes us.
    final landed = _ownFundingDelivered(intent);
    // The chain watch (or an earlier readiness read) saw the wallet hold
    // every leg's money: arrived, whatever the cached balance says yet.
    final arrived = balance >= (landed ? 0.000001 : autofireFireAt(intent)) ||
        (intent.funded && _landedConfirmedFor(intent));
    // A short round that ended while its money was on the way: its book
    // is shut and nothing is signed, never on another round either. Said
    // once the money is Predictions cash (founder, 23 October 2026: fund
    // it anyway; if the bet cannot go in, the person retries), so the
    // slip's Retry on the series' round in play finds it there and moves
    // nothing twice. Money that never lands still meets the funds wait.
    if (arrived && autofireRoundClosed(intent)) {
      _stopAwaitPolling();
      _failRoundClosed(intent);
      return;
    }
    // Nothing signs behind the lock; the next trading tick after unlock
    // fires.
    if (!ref.read(sessionUnlockedProvider)) return;
    // Our own chain watch only while nothing says the money arrived; from
    // then on the readiness look (every second) reads the chain itself.
    if (arrived) {
      _chainWatch.clear();
    } else {
      _watchChain(intent);
    }
    if (!arrived) {
      // Funds aren't fully here yet. Keep forcing fresh balance reads until
      // they land (or we time out). Without this, a swap that settles after
      // the trading provider's periodic poll has gone quiet — or while the
      // user has navigated away — left the bet stuck on "Contacting
      // Polymarket" forever, even though the USDC was already at the Safe.
      // A restart only "fixed" it because re-init forced a fresh read.
      _setReadiness(PredictionsReadiness.waitingFunds);
      _startAwaitPolling();
      return;
    }

    // Landed is not usable yet: wait (every second) until the order book
    // can take the order, so `placing` (the slip's "ready" step) means it.
    // Held from the first read to the order, so no second check starts
    // in between.
    _firing = true;
    try {
      final ready = await _venueReady(intent, source: source);
      final now = ref.read(pendingPolymarketBetProvider);
      if (now == null ||
          now.status != PendingBetStatus.awaitingBalance ||
          now.tokenId != intent.tokenId ||
          now.queuedAt != intent.queuedAt ||
          now.fundedRunId != intent.fundedRunId) {
        return;
      }
      if (!ready) {
        _startAwaitPolling();
        _startReadyPolling();
        return;
      }

      _stopAwaitPolling();
      // The move behind this bet is here.
      PredictionFundingLedger.instance.landed(now.fundQuoteRef);
      if (now.funded) PolymarketPlacementTimeline.mark('funded');
      await _placeOrder(now);
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
    _awaitPoll = Timer.periodic(awaitPollInterval, (_) async {
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
          DateTime.now().difference(_awaitStart!) > fundsTimeout) {
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
      _refreshingFor = CreditDetectedBy.awaitPoll;
      try {
        await ref.read(polymarketTradingProvider.notifier).refresh();
      } catch (_) {
      } finally {
        _refreshingFor = null;
      }
      await _maybeFire(source: CreditDetectedBy.awaitPoll);
    });
  }

  /// The attempt [intent] is: its token, queue time and funded run.
  static ({String token, DateTime? queuedAt, String? runId}) _attemptOf(
          PendingBetIntent intent) =>
      (token: intent.tokenId, queuedAt: intent.queuedAt, runId: intent.fundedRunId);

  /// Keeps the chain watch on [intent] while it is funded and its money
  /// has not been seen in full; off otherwise. Idempotent: one waiter per
  /// attempt, one shared ticker.
  void _watchChain(PendingBetIntent intent) {
    if (!intent.funded || _landedConfirmedFor(intent)) {
      _chainWatch.clear();
      return;
    }
    final key = _attemptOf(intent);
    _chainWatch.retainOnly(key);
    _chainWatch.watch(key, since: intent.queuedAt ?? DateTime.now());
  }

  /// One chain-watch read, its RPC outcome counted on the funded
  /// attempt's journey (`chain_reads`, `chain_rpc_errors`,
  /// `chain_rpc_endpoint`): every failure is counted, none is silent.
  Future<ChainCollateral?> _readChain() async {
    final intent = ref.read(pendingPolymarketBetProvider);
    final timeline = intent == null ? null : _timelineFor(intent);
    void record() {
      if (timeline == null) return;
      final journey = OrderFundingJourney.instance;
      const venue = OneBalanceVenue.predictions;
      journey.count(venue, CreditCount.chainReads, timeline.chainReads);
      journey.count(venue, CreditCount.chainRpcErrors, timeline.chainRpcErrors);
      final endpoint = timeline.chainEndpoint;
      if (endpoint != null) {
        journey.count(venue, CreditCount.chainRpcEndpoint, endpoint);
      }
    }

    timeline?.chainReads++;
    try {
      final read =
          await ref.read(polymarketTradingProvider.notifier).readCollateralNow();
      if (read != null && timeline != null) {
        timeline.chainRpcErrors += read.rpcErrors;
        if (read.endpoint >= 0) timeline.chainEndpoint = read.endpoint;
      }
      record();
      return read;
    } on PolygonPollReadFailed catch (e) {
      timeline?.chainRpcErrors += e.attempts;
      record();
      rethrow;
    } catch (_) {
      timeline?.chainRpcErrors++;
      record();
      rethrow;
    }
  }

  /// A chain read while a funded bet waits: once the wallet's pUSD +
  /// USDC.e cover what the bet waits for (the same rule as
  /// [_venueReady]: every leg's money), the hold is released and the
  /// conversion starts at once; the bet then goes through its readiness
  /// read as before.
  void _onChainRead(ChainCollateral read) {
    if (_disposed) return;
    final intent = ref.read(pendingPolymarketBetProvider);
    if (intent == null ||
        intent.status != PendingBetStatus.awaitingBalance ||
        !intent.funded ||
        _landedConfirmedFor(intent) ||
        !_chainWatch.isWatching(_attemptOf(intent))) {
      _chainWatch.clear();
      return;
    }
    // Nothing signs behind the lock (the conversion is signed).
    if (!ref.read(sessionUnlockedProvider)) return;
    final total = (read.pusd + read.usdce).toDouble() / 1e6;
    if (total + 1e-6 < autofireFireAt(intent)) return;
    _confirmLanded(intent,
        usdce: read.usdce, source: CreditDetectedBy.chainPoll, convert: true);
    if (!_firing) unawaited(_maybeFire(source: CreditDetectedBy.chainPoll));
  }

  /// The wallet's own balances showed every leg's money of [intent]: its
  /// one conversion and its order may run from now
  /// ([FundedConversionHold] released). Records when and by what it was
  /// seen. With [convert], the conversion starts now (idempotent through
  /// the wallet's single-flight gate). Once per attempt.
  void _confirmLanded(PendingBetIntent intent,
      {required BigInt usdce, required String source, bool convert = false}) {
    if (_landedConfirmedFor(intent)) return;
    _landedConfirmed = _attemptOf(intent);
    _chainWatch.clear();
    final journey = OrderFundingJourney.instance;
    final now = OrderFundingJourney.clock();
    final timeline = _timelineFor(intent);
    timeline.seenAt ??= now;
    if (journey.isRunning(OneBalanceVenue.predictions)) {
      final fundedAt =
          journey.fundedAtOf(OneBalanceVenue.predictions) ?? intent.queuedAt;
      if (fundedAt != null) {
        journey.timing(OneBalanceVenue.predictions,
            CreditTiming.fundedToOnchainSeen,
            now.difference(fundedAt).inMilliseconds);
      }
      journey.detectedBy(OneBalanceVenue.predictions, source);
    }
    if (convert && usdce >= _kUsdceDustMicros) {
      try {
        ref.read(polymarketTradingProvider.notifier).nudgeConversion();
      } catch (_) {}
    }
  }

  _CreditTimeline _timelineFor(PendingBetIntent intent) {
    final key = _attemptOf(intent);
    final current = _timeline;
    if (current != null && current.key == key) return current;
    return _timeline = _CreditTimeline(key);
  }

  /// A conversion's moment, for the funded attempt waiting or placing now.
  void _onWrapPhase(WrapPhase phase) {
    if (_disposed) return;
    final intent = ref.read(pendingPolymarketBetProvider);
    if (intent == null ||
        !intent.funded ||
        (intent.status != PendingBetStatus.awaitingBalance &&
            intent.status != PendingBetStatus.placing)) {
      return;
    }
    final journey = OrderFundingJourney.instance;
    if (!journey.isRunning(OneBalanceVenue.predictions)) return;
    final timeline = _timelineFor(intent);
    final now = OrderFundingJourney.clock();
    switch (phase) {
      case WrapPhase.submitting:
        timeline.wrapStartedAt = now;
        if (timeline.wrapSubmittedAt == null) {
          timeline.wrapSubmittedAt = now;
          final seen = timeline.seenAt;
          if (seen != null) {
            journey.timing(OneBalanceVenue.predictions,
                CreditTiming.seenToWrapSubmitted,
                now.difference(seen).inMilliseconds);
          }
        }
      case WrapPhase.mined:
        final submitted = timeline.wrapSubmittedAt;
        if (timeline.minedAt == null && submitted != null) {
          timeline.minedAt = now;
          journey.timing(OneBalanceVenue.predictions,
              CreditTiming.wrapSubmittedToMined,
              now.difference(submitted).inMilliseconds);
        }
      case WrapPhase.done:
        // Every conversion of the attempt, whoever started it (the
        // arrival watch, the release, the order's own): `legs.wrap`.
        final from = timeline.wrapStartedAt;
        if (from != null) {
          timeline.wrapStartedAt = null;
          journey.leg(OneBalanceVenue.predictions, OrderFundingLeg.wrap,
              now.difference(from).inMilliseconds);
        }
    }
  }

  /// Adds one to the funded attempt's counter [name] on its journey.
  void _countCredit(PendingBetIntent intent, String name) {
    final timeline = _timelineFor(intent);
    final n = (timeline.counts[name] ?? 0) + 1;
    timeline.counts[name] = n;
    OrderFundingJourney.instance.count(OneBalanceVenue.predictions, name, n);
  }

  /// The order book counts [intent]'s converted money now.
  void _noteBookCounts(PendingBetIntent intent) {
    if (!intent.funded) return;
    final timeline = _timeline;
    if (timeline == null || timeline.key != _attemptOf(intent)) return;
    final mined = timeline.minedAt;
    if (mined == null || timeline.bookCounted) return;
    timeline.bookCounted = true;
    OrderFundingJourney.instance.timing(
        OneBalanceVenue.predictions,
        CreditTiming.minedToBookCounts,
        OrderFundingJourney.clock().difference(mined).inMilliseconds);
  }

  /// Reads [intent]'s readiness every [readyPollInterval] once its money
  /// landed. Idempotent.
  void _startReadyPolling() {
    if (_readyPoll != null) return;
    _readyPoll = Timer.periodic(readyPollInterval, (_) {
      if (!_firing) {
        unawaited(_maybeFire(source: CreditDetectedBy.awaitPoll));
      }
    });
  }

  void _setReadiness(PredictionsReadiness readiness,
          {bool convertSeen = false, bool approveSeen = false}) =>
      ref.read(pendingPolymarketBetProvider.notifier).setReadiness(readiness,
          convertSeen: convertSeen, approveSeen: approveSeen);

  /// What [intent]'s order may cost at most, fees included, in micro-pUSD.
  static BigInt _costMicros(PendingBetIntent intent, {double? amountUsd}) {
    final fees = intent.feeTerms ?? PolymarketFeeTerms.worstCase;
    final price = _costPrice(intent);
    return BigInt.from(((fees.allInCost(amountUsd ?? intent.amount, price) +
                (intent.isLimit
                    ? 0
                    : PolymarketMarketBuyQuote.roundingHeadroom)) *
            1e6)
        .ceil());
  }

  static double _costPrice(PendingBetIntent intent) {
    var price = intent.isLimit
        ? intent.limitPrice.clamp(0.01, 0.99).toDouble()
        : polymarketFundedWorstPrice(intent);
    if (!intent.isLimit) {
      final quote = intent.marketQuote;
      final lowest = quote?.tokenId == intent.tokenId
          ? quote!.bestAsk
          : intent.expectedPrice;
      if (lowest > 0 && lowest < price) price = lowest;
    }
    return price;
  }

  /// Only this order's completed source steps can certify a short landing.
  /// The move's own ledger record is used when there is no live step graph.
  bool _ownFundingDelivered(PendingBetIntent intent) {
    final id = intent.fundedRunId;
    if (id != null) {
      final record = ref.read(fundedOrdersProvider.notifier).byId(id);
      if (record == null ||
          !record.stage.active ||
          record.label.marketKey != intent.tokenId ||
          record.label.venue != OneBalanceVenue.predictions) {
        return false;
      }
      final legs = record.steps.steps.where((s) =>
          s.kind == MoneyStepKind.leg &&
          !s.id.startsWith('prev:') &&
          s.status != MoneyStepStatus.fellBack);
      return legs.any((s) => s.status == MoneyStepStatus.done) &&
          legs.every((s) => s.status.satisfies);
    }
    final key = intent.fundQuoteRef;
    return key != null &&
        PredictionFundingLedger.instance.record(key)?.stage ==
            PredictionFundingStage.landed;
  }

  double _orderCash(PendingBetIntent intent) {
    final confirmed = _confirmedCash;
    if (confirmed != null &&
        confirmed.token == intent.tokenId &&
        confirmed.queuedAt == intent.queuedAt &&
        confirmed.runId == intent.fundedRunId) {
      return confirmed.usd;
    }
    return ref.read(polymarketTradingProvider).valueOrNull?.usdcBalance ?? 0;
  }

  bool _sameAttempt(PendingBetIntent intent) {
    if (_disposed) return false;
    final current = ref.read(pendingPolymarketBetProvider);
    return current != null &&
        current.tokenId == intent.tokenId &&
        current.queuedAt == intent.queuedAt &&
        current.fundedRunId == intent.fundedRunId;
  }

  /// When the current placement handed its order to the trading notifier:
  /// the `ready` step it reports back closes the `venue_count` leg (the
  /// order's collateral check, until the book counts the money).
  DateTime? _placeStartedAt;

  void _placementStep(PendingBetIntent intent, String step) {
    if (!_sameAttempt(intent)) return;
    if (step == 'ready') {
      _setReadiness(PredictionsReadiness.ready);
      final intent = ref.read(pendingPolymarketBetProvider);
      if (intent?.funded == true) {
        _noteBookCounts(intent!);
        final journey = OrderFundingJourney.instance;
        final from = _placeStartedAt;
        if (from != null) {
          journey.leg(OneBalanceVenue.predictions, OrderFundingLeg.venueCount,
              OrderFundingJourney.clock().difference(from).inMilliseconds);
        }
        journey.credited(OneBalanceVenue.predictions);
      }
      _placeStartedAt = null;
    } else if (step == 'approving') {
      _setReadiness(PredictionsReadiness.approving, approveSeen: true);
    }
  }

  /// The reading short of [intent]'s money that every leg's "delivered"
  /// came with, and since when it has read exactly that.
  ({
    ({String token, DateTime? queuedAt, String? runId}) attempt,
    BigInt pusd,
    BigInt usdce,
    DateTime since
  })? _shortReading;

  /// Whether a reading short of [intent]'s money, with every leg reported
  /// delivered, has held long enough to be the landing itself
  /// ([kShortLandingLooks]) and not a read made while the money (or its
  /// conversion) was still reaching the endpoints. Any change starts the
  /// count again.
  bool _shortLandingHeld(PendingBetIntent intent,
      {required BigInt pusd, required BigInt usdce}) {
    final now = DateTime.now();
    final attempt = _attemptOf(intent);
    final seen = _shortReading;
    if (seen == null ||
        seen.attempt != attempt ||
        seen.pusd != pusd ||
        seen.usdce != usdce) {
      _shortReading =
          (attempt: attempt, pusd: pusd, usdce: usdce, since: now);
      return false;
    }
    final grace =
        debugShortLandingGrace ?? readyPollInterval * kShortLandingLooks;
    return now.difference(seen.since) >= grace;
  }

  /// Whether the order book can take [intent]'s order now
  /// ([autofireReadiness]), recorded on the bet. A deposit still USDC.e
  /// gets its conversion going; a book not counting the pUSD is asked to
  /// re-read on the next look. A missing exchange allowance on a set-up
  /// account does not wait: the order sets it under its own approval
  /// (venue_collateral.dart). Missing reads keep a funded bet confirming,
  /// bounded by the existing funds wait; they never authorize submission.
  /// The final actual quote is checked again before signing and is the
  /// only point that marks the balance confirmed.
  Future<bool> _venueReady(PendingBetIntent intent,
      {BigInt? requiredCostMicros,
      bool refreshVenue = false,
      String source = CreditDetectedBy.awaitPoll}) async {
    final trading = ref.read(polymarketTradingProvider.notifier);
    PolyBuyReads? reads;
    try {
      reads = await trading.readBuyReadiness(
          refreshVenue: refreshVenue ||
              intent.readiness == PredictionsReadiness.confirming ||
              intent.readiness == PredictionsReadiness.approving);
    } catch (_) {}
    final current = ref.read(pendingPolymarketBetProvider);
    if (current == null ||
        current.tokenId != intent.tokenId ||
        current.queuedAt != intent.queuedAt ||
        current.fundedRunId != intent.fundedRunId) {
      return false;
    }
    if (reads == null) {
      if (!intent.funded) return true;
      // The wallet could not be read (every endpoint failed or timed
      // out): counted, and read again on the next second's look.
      _countCredit(intent, CreditCount.readinessReadErrors);
      _setReadiness(PredictionsReadiness.confirming);
      return false;
    }
    // The order book's count could not be read: counted (the book, not
    // the chain, is what "Confirming balance" then waits on).
    if (reads.venue == null && intent.funded) {
      _countCredit(intent, CreditCount.bookCountErrors);
    }
    final cash = reads.pusd.toDouble() / 1e6;
    final delivered = _ownFundingDelivered(intent);
    final total = (reads.pusd + reads.usdce).toDouble() / 1e6;
    if (intent.funded && !delivered &&
        total + 1e-6 < autofireFireAt(intent)) {
      // Some legs' money is here, not all of it: nothing converts or is
      // signed yet (founder, 25 October 2026), the bet waits for every
      // leg. One conversion takes the whole delivered amount once the
      // wallet's balances show it.
      _setReadiness(PredictionsReadiness.waitingFunds);
      return false;
    }
    // The wallet's own balances show every leg's money (or every leg
    // landed, short): the one conversion and the order may run now.
    if (intent.funded) {
      _confirmLanded(intent, usdce: reads.usdce, source: source);
    }
    var cost = requiredCostMicros ?? _costMicros(intent);
    // Every leg says delivered and this read shows less than the bet
    // waits for, nothing left to convert: a short landing only once the
    // reading has held ([_shortLandingHeld]). Until then the bet waits
    // for the next look, a second away: never "Add funds" with the money
    // there, never a smaller bet on the cash that was there before
    // (founder, 11 November 2026: "we place the bet, then an error comes
    // saying that there is no money").
    if (requiredCostMicros == null &&
        intent.funded &&
        delivered &&
        reads.usdce < _kUsdceDustMicros &&
        reads.pusd < cost &&
        total + 1e-6 < autofireFireAt(intent)) {
      if (!_shortLandingHeld(intent, pusd: reads.pusd, usdce: reads.usdce)) {
        if (intent.readiness == null) {
          _setReadiness(PredictionsReadiness.waitingFunds);
        }
        return false;
      }
    } else {
      _shortReading = null;
    }
    // A proved short landing can resize a market order within its approval.
    // Never infer completion from the first arrival or a cached total.
    if (requiredCostMicros == null &&
        delivered &&
        !intent.isLimit &&
        reads.usdce < _kUsdceDustMicros) {
      final landed = landedStakeFor(
          amount: intent.amount,
          balance: cash,
          feeTerms: intent.feeTerms ?? PolymarketFeeTerms.worstCase,
          price: _costPrice(intent),
          isLimit: false,
          reserve: PolymarketMarketBuyQuote.roundingHeadroom);
      if (landed != null) {
        cost = _costMicros(intent, amountUsd: landed.usd);
      } else if (cash > 0) {
        _failShortLanding(intent);
        return false;
      }
    } else if (delivered && intent.isLimit && reads.pusd < cost &&
        reads.usdce < _kUsdceDustMicros && cash > 0) {
      _failShortLanding(intent);
      return false;
    }
    final phase = autofireReadiness(
      pusd: reads.pusd,
      usdce: reads.usdce,
      costMicros: cost,
      venue: reads.venue,
      spenders: polyBuySpenders(intent.tokenId,
          negRisk: intent.marketQuote?.tokenId == intent.tokenId
              ? intent.marketQuote!.negRisk
              : intent.negRisk),
      setupDone: reads.setupDone,
    );
    if (phase == PredictionsReadiness.converting) trading.nudgeConversion();
    _setReadiness(
        phase == PredictionsReadiness.ready
            ? PredictionsReadiness.confirming
            : phase,
        convertSeen: phase == PredictionsReadiness.converting,
        approveSeen: phase == PredictionsReadiness.approving);
    final ready = phase == PredictionsReadiness.ready ||
        phase == PredictionsReadiness.approving &&
            reads.setupDone &&
            reads.venue != null &&
            reads.venue!.balance >= cost;
    if (ready) {
      _noteBookCounts(intent);
      _confirmedCash = (
        token: intent.tokenId,
        queuedAt: intent.queuedAt,
        runId: intent.fundedRunId,
        usd: cash
      );
    }
    return ready;
  }

  void _failShortLanding(PendingBetIntent intent) {
    _trackFailed(intent, 'insufficient_usdc');
    OrderFundingJourney.instance.failed(OneBalanceVenue.predictions,
        OrderFundingStage.credit, 'insufficient_funds');
    PredictionFundingLedger.instance.release(intent.fundQuoteRef, reason: 'failed');
    ref.read(pendingPolymarketBetProvider.notifier).updateStatus(
        PendingBetStatus.failed, failureCode: 'insufficient_usdc',
        errorMessage: l10nForLanguage(ref.read(settingsProvider).language)
            .betAddFundsToPredict);
  }

  /// After [e], a refusal that says only that the money is not usable yet
  /// ([autofireNotReadyYet]): waits, the bet still `placing`, until the
  /// book can take the order, and says to send it again under the same
  /// [approval]. Bounded by time, the funds wait counted from [since]
  /// (the first such refusal of this order), with at most
  /// [kAutofireNotReadyRetries] sends again, spaced out by [attempt] (1,
  /// 2, 4 ... up to [_kNotReadyMaxGapPolls] polls): what makes the venue
  /// refuse (a spend approval still being mined, the order book's
  /// balance view not re-read yet) can take a minute to clear even when
  /// the readiness read already looks ready. Every look asks the book to
  /// re-read (`/balance-allowance/update`). False leaves [e] to the
  /// failure path (the bet was cleared, its round closed, the wait ran
  /// out). An approval that ran out meanwhile throws [_ApprovalLapsed]:
  /// the bet asks to be confirmed again. Nothing was accepted on a
  /// refusal like this, so a send again never places twice; each one is
  /// priced from a fresh book under the same approval.
  Future<bool> _waitAfterNotReady(
      Object e, PendingBetIntent intent, AuthGrant? approval, int attempt,
      {required DateTime since,
      BigInt? requiredCostMicros,
      bool standing = false}) async {
    if (!autofireNotReadyYet(e) || attempt >= kAutofireNotReadyRetries) {
      return false;
    }
    // A standing order's approval is the signed order itself: it lapses
    // with the queued bet's age, not with a grant.
    bool lapsed() => standing
        ? intent.isStale()
        : approval == null ||
            approval.revoked ||
            approval.isExpiredAt(AuthGrants.clock()) ||
            intent.isStale();
    final until = since.add(fundsTimeout);
    final gapPolls = min(1 << min(attempt, 16), _kNotReadyMaxGapPolls);
    if (gapPolls > 1) {
      await Future<void>.delayed(readyPollInterval * (gapPolls - 1));
    }
    while (true) {
      await Future<void>.delayed(readyPollInterval);
      if (lapsed()) throw const _ApprovalLapsed();
      final now = ref.read(pendingPolymarketBetProvider);
      if (now == null ||
          now.tokenId != intent.tokenId ||
          now.queuedAt != intent.queuedAt ||
          now.fundedRunId != intent.fundedRunId ||
          now.status != PendingBetStatus.placing ||
          autofireRoundClosed(intent) ||
          DateTime.now().isAfter(until)) {
        return false;
      }
      // Nothing signs behind the lock: the wait goes on.
      if (!ref.read(sessionUnlockedProvider)) continue;
      if (await _venueReady(now,
          requiredCostMicros: requiredCostMicros, refreshVenue: true)) {
        final current = ref.read(pendingPolymarketBetProvider);
        if (current == null ||
            current.tokenId != intent.tokenId ||
            current.queuedAt != intent.queuedAt ||
            current.fundedRunId != intent.fundedRunId) {
          return false;
        }
        return true;
      }
    }
  }

  void _stopAwaitPolling() {
    _chainWatch.clear();
    _readyPoll?.cancel();
    _readyPoll = null;
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
        ...polyRoundWindowParams(intent.eventSlug,
            window: intent.roundWindow, at: DateTime.now()),
        // A standing order: how long from the accept to this outcome, how
        // many orders were signed for it, and the price the slip quoted
        // (the outcome event turns it into `price_moved_bps` against the
        // fill). Exact figures, nothing identifying.
        ..._standingAnalytics(intent),
      };

  Map<String, Object> _standingAnalytics(PendingBetIntent intent) {
    final id = intent.standingOrderId;
    final queuedAt = intent.queuedAt;
    if (id == null || queuedAt == null) return const {};
    final record = ref.read(standingOrdersProvider.notifier).byId(id);
    return {
      'standing_order': true,
      'wait_ms': DateTime.now().difference(queuedAt).inMilliseconds,
      'attempts': record?.attempts ?? 1,
      if (intent.expectedPrice > 0) 'first_quote_price': intent.expectedPrice,
    };
  }

  /// A standing order's bet: the order signed at the accept is posted as
  /// is once the venue counts the money (standing_orders/). No fresh book
  /// prices it (the signed limit is the approval, never worse); a refusal
  /// for its price (proven not accepted) is met by a re-price INSIDE the
  /// approved worst price, signed anew under the approval still held this
  /// session, at most [kStandingReprices] times within
  /// [kStandingRepriceWindow]; a book past the worst price stops it with
  /// the money on the venue and asks the person again (needsApproval). A
  /// pick for the next 5-minute round waits here for it to open. Every
  /// post goes through `placeOrder`'s guard, so a restart or a resend can
  /// never place twice.
  Future<void> _placeStandingOrder(PendingBetIntent intent, String standingId,
      {required PolymarketCostBasisNotifier costBasis}) async {
    final pendingNotifier = ref.read(pendingPolymarketBetProvider.notifier);
    final placingNotifier = ref.read(placingPolymarketBetProvider.notifier);
    final tradingNotifier = ref.read(polymarketTradingProvider.notifier);
    final standing = ref.read(standingOrdersProvider.notifier);
    final journey = OrderFundingJourney.instance;
    final ledger = PredictionFundingLedger.instance;
    final funded = intent.funded;
    final fundingKey = intent.fundQuoteRef;
    final l10n = l10nForLanguage(ref.read(settingsProvider).language);

    void stop(String code, String message, {String? placementId}) {
      _trackFailed(intent, code);
      if (funded) {
        journey.failed(
            OneBalanceVenue.predictions, OrderFundingStage.order, code);
      }
      ledger.release(fundingKey, reason: 'failed');
      pendingNotifier.updateStatus(PendingBetStatus.failed,
          errorMessage: message, failureCode: code);
      if (placementId != null) placingNotifier.markFailed(placementId, message);
    }

    final stored = await standing.signedOrderFor(standingId);
    if (!_sameAttempt(intent)) return;
    if (stored == null) {
      stop(StandingOrderFailure.approvalMissing, l10n.standingPredictionFailed);
      return;
    }
    // The order posted now; a re-price replaces it (never a second live one).
    var signed = stored;
    // The next round's pick: funded ahead, posted once the round opens.
    while (!standing.mayPost(standingId)) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!_sameAttempt(intent)) return;
      if (intent.isStale()) {
        stop(StandingOrderFailure.expired, l10n.standingPredictionFailed);
        return;
      }
    }
    if (autofireRoundClosed(intent)) {
      _failRoundClosed(intent);
      return;
    }
    final isLimit = signed.orderType == OrderType.gtc;
    String? placementId;
    if (!isLimit) {
      final preShares = ref
          .read(polymarketActivePositionsProvider)
          .where((p) => p.tokenId == intent.tokenId)
          .fold<double>(0, (sum, p) => sum + p.size);
      placementId = placingNotifier.markPlacing(
        tokenId: intent.tokenId,
        marketQuestion: intent.marketQuestion,
        eventSlug: intent.eventSlug,
        marketImage: intent.marketImage,
        outcomeName: intent.outcomeName,
        amount: intent.amount,
        shares: 0,
        avgPrice: intent.expectedPrice,
        preExistingShares: preShares,
        step: 2,
        totalSteps: 3,
        stepLabel: l10n.betContactingPolymarket,
      );
    }
    var sentShares = 0.0;
    var venueTook = false;
    var attempt = 0;
    Map<String, dynamic>? takenAnswer;
    double? takenPaid;
    try {
      final fees = intent.feeTerms ?? PolymarketFeeTerms.worstCase;
      await tradingNotifier
          .readyCollateralForBuy(fees.allInCost(signed.spendUsd, signed.price));
      if (!_sameAttempt(intent)) return;
      final firstPost = DateTime.now();
      DateTime? notReadySince;
      var notReady = 0;
      Map<String, dynamic>? response;
      while (true) {
        sentShares = signed.shares;
        if (placementId != null) {
          placingNotifier.advanceStep(placementId,
              step: 3, label: l10n.betPlacingOrder);
        }
        ledger.reserve(fundingKey);
        try {
          response = await tradingNotifier.postStandingOrder(
            standing: signed,
            marketTitle: intent.marketQuestion,
            marketImage: intent.marketImage,
            marketOutcome: intent.outcomeName,
            marketCategory: intent.marketCategory,
            source: funded ? 'usdc_pool' : 'btc_pool',
            entrySource: 'autofire',
            analytics: {
              ..._analytics(intent),
              'retried': attempt > 0,
              'quoted_price': intent.expectedPrice,
            },
            onStep: (step) => _placementStep(intent, step),
          );
          break;
        } catch (e) {
          if (!_sameAttempt(intent)) return;
          // Refused for its price: the venue proved this order was not
          // accepted. A fresh book inside the approved worst price gives
          // a new order; past it, the person is asked again.
          if (!isLimit &&
              e is PolymarketOrderNotAcceptedException &&
              isPolymarketPriceRefusal(e.reason)) {
            final next =
                await _repriceStanding(intent, standingId, since: firstPost);
            if (!_sameAttempt(intent)) return;
            final resigned = next.signed;
            if (resigned != null) {
              signed = resigned;
              attempt++;
              continue;
            }
            _stopNeedsApproval(intent, standingId,
                priceNow: next.priceNow, error: e, placementId: placementId);
            return;
          }
          if (await _waitAfterNotReady(e, intent, null, notReady++,
              since: notReadySince ??= DateTime.now(),
              requiredCostMicros: BigInt.from(
                  (fees.allInCost(signed.spendUsd, signed.price) * 1e6).ceil()),
              standing: true)) {
            continue;
          }
          rethrow;
        }
      }
      final Map<String, dynamic> placed = response;
      venueTook = true;
      takenAnswer = placed;
      if (isLimit) {
        // Resting on the book: the order holds its own cash from now.
        unawaited(tradingNotifier.refresh().catchError((_) {}));
        ref.invalidate(polymarketOpenOrdersProvider);
        if (funded && _sameAttempt(intent)) {
          journey.completed(OneBalanceVenue.predictions,
              resized: false, amountUsd: signed.spendUsd);
        }
        ledger.release(fundingKey, reason: 'placed');
        if (!_sameAttempt(intent)) return;
        pendingNotifier.updateStatus(PendingBetStatus.done);
        Future.delayed(const Duration(milliseconds: 600), () {
          try {
            if (_sameAttempt(intent)) pendingNotifier.clear();
          } catch (_) {}
        });
        return;
      }
      final makingRaw = placed['makingAmount'] ?? placed['making_amount'];
      final paidUsdc = makingRaw is num
          ? makingRaw.toDouble()
          : double.tryParse('$makingRaw');
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
        takenPaid = paidUsdc;
        unawaited(
            costBasis.addCost(intent.tokenId, paidUsdc).catchError((_) {}));
      }
      unawaited(tradingNotifier.refresh().catchError((_) {}));
      if (!_sameAttempt(intent)) {
        ledger.release(fundingKey, reason: 'placed');
        if (!_disposed) ref.invalidate(polymarketOpenOrdersProvider);
        return;
      }
      pendingNotifier.recordFill(placed);
      if (!verifiedFill &&
          (placed['status']?.toString().toLowerCase() == 'delayed' ||
              placed['recovered'] == true) &&
          await _followHeldOrder(intent, placed,
              orderedShares: sentShares,
              placementId: placementId!,
              retried: attempt > 0,
              resized: false,
              costBasis: costBasis)) {
        return;
      }
      if (!_sameAttempt(intent)) return;
      if (funded) {
        journey.completed(OneBalanceVenue.predictions,
            resized: false, amountUsd: verifiedFill ? paidUsdc : null);
      }
      ledger.release(fundingKey, reason: 'placed');
      if (!verifiedFill) {
        ref.invalidate(polymarketOpenOrdersProvider);
        pendingNotifier.updateStatus(PendingBetStatus.awaitingConfirmation);
        placingNotifier.clear(placementId!);
        return;
      }
      pendingNotifier.updateStatus(PendingBetStatus.done);
      placingNotifier.markSucceeded(placementId!,
          holdUntilPositionArrives: true);
      Future.delayed(const Duration(milliseconds: 600), () {
        try {
          if (_sameAttempt(intent)) pendingNotifier.clear();
        } catch (_) {}
      });
    } catch (e, st) {
      if (!_sameAttempt(intent)) return;
      if (kDebugMode) debugPrint('[pm-standing] failed: $e\n$st');
      if (venueTook && e is! PendingPolymarketOrder) {
        _endTaken(intent,
            answer: takenAnswer,
            paidUsdc: takenPaid,
            resized: false,
            placementId: placementId);
        return;
      }
      if (e is PolymarketOrderOutcomeUnknown &&
          e.orderId != null &&
          !e.lookedUp &&
          sentShares > 0 &&
          placementId != null) {
        placingNotifier.markConfirming(placementId);
        pendingNotifier.setStage(PendingBetStage.reconciling);
        var ended = false;
        try {
          ended = await _followHeldOrder(
              intent, {'orderID': e.orderId, 'status': ''},
              orderedShares: sentShares,
              placementId: placementId,
              retried: attempt > 0,
              resized: false,
              costBasis: costBasis);
        } catch (_) {}
        if (ended) {
          unawaited(tradingNotifier
              .checkPendingOrder(tokenId: intent.tokenId)
              .catchError((_) {}));
          return;
        }
        if (!_sameAttempt(intent)) return;
      }
      if (e is PendingPolymarketOrder) {
        if (funded) {
          journey.completed(OneBalanceVenue.predictions, resized: false);
        }
        ledger.release(fundingKey, reason: 'placed');
        pendingNotifier.updateStatus(PendingBetStatus.awaitingConfirmation);
        if (placementId != null) placingNotifier.clear(placementId);
        return;
      }
      if (e is _ApprovalLapsed) {
        stop(StandingOrderFailure.expired, l10n.standingPredictionFailed,
            placementId: placementId);
        return;
      }
      if (autofireRoundClosed(intent)) {
        _failRoundClosed(intent, placementId: placementId);
        return;
      }
      _trackFailed(intent, _failureCode(e),
          stackTrace: st, retried: attempt > 0, error: e);
      if (funded) {
        journey.failed(OneBalanceVenue.predictions, _failureStage(e),
            _failureCode(e));
      }
      ledger.release(fundingKey, reason: 'failed');
      final msg = _friendlyError(e);
      pendingNotifier.updateStatus(PendingBetStatus.failed,
          errorMessage: msg, failureCode: _stopCode(e));
      if (placementId != null) placingNotifier.markFailed(placementId, msg);
    }
  }

  /// A fresh book for a standing order whose posted order the venue
  /// refused for its price: a new order at today's executable price, under
  /// the approved worst price, signed anew (`StandingOrdersNotifier.
  /// reprice`); or none, with the price now when the book moved past the
  /// approval.
  Future<({StandingSignedOrder? signed, double? priceNow})> _repriceStanding(
      PendingBetIntent intent, String standingId,
      {required DateTime since}) async {
    final book = await _freshBook(intent.tokenId);
    if (book == null) return (signed: null, priceNow: null);
    final fees = intent.feeTerms ?? PolymarketFeeTerms.worstCase;
    final slippage = autofireSlippagePct(intent.expectedPrice, intent.slippagePct);
    final PolymarketFillPrice fill;
    try {
      fill = polymarketFillPrice(book,
          tokenId: intent.tokenId,
          amount: intent.amount,
          slippagePct: slippage,
          approvedMaxPrice: polymarketFundedWorstPrice(intent),
          fees: fees);
    } on PolymarketThinBook catch (e) {
      return (signed: null, priceNow: e.price);
    } catch (_) {
      return (signed: null, priceNow: null);
    }
    final shares = PolymarketOrderPlan.sharesFor(intent.amount, fill.orderPrice);
    if (shares <= 0) return (signed: null, priceNow: fill.bestAsk);
    final signed = await ref.read(standingOrdersProvider.notifier).reprice(
          standingId,
          intent: intent,
          price: fill.orderPrice,
          shares: shares,
          spendUsd: intent.amount,
          since: since,
        );
    return (signed: signed, priceNow: signed == null ? fill.bestAsk : null);
  }

  /// The book moved past the approved worst price (or nothing may be
  /// signed any more): nothing is bought at a price never approved. The
  /// money stays on the venue, the standing order waits for the person
  /// (needsApproval: one tap and Face ID at the new price, or cancel).
  void _stopNeedsApproval(PendingBetIntent intent, String standingId,
      {double? priceNow, required Object error, String? placementId}) {
    final pendingNotifier = ref.read(pendingPolymarketBetProvider.notifier);
    final placingNotifier = ref.read(placingPolymarketBetProvider.notifier);
    _trackFailed(intent, 'price_moved', retried: true, error: error);
    if (intent.funded) {
      OrderFundingJourney.instance.failed(
          OneBalanceVenue.predictions, OrderFundingStage.order, 'price_moved');
    }
    PredictionFundingLedger.instance
        .release(intent.fundQuoteRef, reason: 'failed');
    unawaited(ref
        .read(standingOrdersProvider.notifier)
        .needsApproval(standingId, priceNow: priceNow));
    final l10n = l10nForLanguage(ref.read(settingsProvider).language);
    final msg = priceNow != null
        ? l10n.slipFundingRoundPriceMoved(formatPolyChance(priceNow))
        : l10n.betBuyLiquidityUnavailable;
    pendingNotifier.updateStatus(PendingBetStatus.failed,
        errorMessage: msg,
        retryMaxPrice: priceNow,
        movedToPrice: priceNow,
        failureCode: 'price_moved');
    if (placementId != null) placingNotifier.markFailed(placementId, msg);
  }

  /// [intent]'s round closed before its money arrived (or before it could
  /// be placed): nothing is signed, on this round or any other, and the
  /// money stays as Predictions cash. The slip's Retry opens the series'
  /// round in play with the same side and stake, for the person to
  /// confirm (`resolveCurrentPolyRound`).
  void _failRoundClosed(PendingBetIntent intent, {String? placementId}) {
    // A 5-minute crypto round says it ended while the money was moving,
    // and where the money is.
    final fiveMinute = polyIsCryptoUpDown5m(intent.eventSlug);
    final code = fiveMinute ? 'round_ended' : 'market_closed';
    _trackFailed(intent, code);
    if (intent.funded) {
      OrderFundingJourney.instance.failed(OneBalanceVenue.predictions,
          OrderFundingStage.order, code);
    }
    PredictionFundingLedger.instance
        .release(intent.fundQuoteRef, reason: 'failed');
    final l10n = l10nForLanguage(ref.read(settingsProvider).language);
    final msg = fiveMinute
        ? l10n.slipFundingRoundEnded('\$${intent.amount.toStringAsFixed(2)}')
        : l10n.slipFundingRoundClosed;
    if (placementId != null) {
      ref.read(placingPolymarketBetProvider.notifier).markFailed(placementId, msg);
    }
    ref.read(pendingPolymarketBetProvider.notifier).updateStatus(
        PendingBetStatus.failed,
        errorMessage: msg,
        failureCode: fiveMinute ? 'round_ended' : 'market_closed');
  }

  /// For a 5-minute crypto round stopped by [e]: the price now when it
  /// moved past what was approved while the money was moving (the book
  /// read before signing was over the cap, or the venue killed the
  /// re-priced order for its price, then read once more), with the cap a
  /// new approval would name. Null for any other stop or market.
  Future<({double price, double cap})?> _roundPriceMoved(
      PendingBetIntent intent, Object e,
      {required double slippagePct, required PolymarketFeeTerms fees}) async {
    if (!polyIsCryptoUpDown5m(intent.eventSlug)) return null;
    if (e is PolymarketThinBook) {
      final cap = polymarketRetryPrice(e);
      final price = e.price;
      return cap == null || price == null ? null : (price: price, cap: cap);
    }
    if (e is! PolymarketOrderNotAcceptedException ||
        !isPolymarketPriceRefusal(e.reason)) {
      return null;
    }
    final book = await _freshBook(intent.tokenId);
    if (book == null) return null;
    try {
      final quote = PolymarketMarketBuyQuote.fromBook(book,
          tokenId: intent.tokenId,
          amount: intent.amount,
          slippagePct: slippagePct.clamp(0, 30).toDouble(),
          fees: fees);
      // Only a price past what was approved; a kill under it stays the
      // venue's own refusal.
      if (quote.bestAsk <= polymarketFundedWorstPrice(intent) + 1e-9) {
        return null;
      }
      return (price: quote.price, cap: quote.maxPrice);
    } catch (_) {
      return null;
    }
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
        if (polyIsCryptoUpDown5m(intent.eventSlug))
          'market_kind': kCryptoUpDown5mKind,
        // Whether a second, re-priced order went out after the first was
        // refused for its price.
        'retried': retried,
        if (refusal != null) ...polymarketRefusalParams(refusal),
        ...settlement,
      },
    );
  }

  Future<void> _placeOrder(PendingBetIntent intent) async {
    if (!_sameAttempt(intent)) return;
    final pendingNotifier = ref.read(pendingPolymarketBetProvider.notifier);
    final placingNotifier = ref.read(placingPolymarketBetProvider.notifier);
    final tradingNotifier = ref.read(polymarketTradingProvider.notifier);

    // D-10: never fire without the confirm-time grant (a restart drops it).
    // A standing order (standing_orders/) carries its approval as the order
    // signed at the accept, kept in secure storage: no grant is needed.
    final standingId = intent.standingOrderId;
    if (standingId == null &&
        !AuthGrantRegistry.instance.hasAutofireGrant(kPendingBetAutofireId)) {
      _trackFailed(intent, 'approval_expired');
      _cancelForReconfirm();
      return;
    }

    // Keep the accepted fill on the observer/store this attempt began on,
    // even if the account or provider changes while the response is pending.
    final costBasis = ref.read(polymarketCostBasisProvider.notifier);

    pendingNotifier.updateStatus(PendingBetStatus.placing);
    if (standingId != null) {
      await _placeStandingOrder(intent, standingId, costBasis: costBasis);
      return;
    }
    final journey = OrderFundingJourney.instance;
    final funded = intent.funded;
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
      // The consumed approval, kept for a send again after a refusal that
      // said only "not usable yet" ([_waitAfterNotReady]).
      AuthGrant? limitApproval;
      var notReady = 0;
      DateTime? notReadySince;
      // The venue took the limit (it rests on the book): nothing after
      // that ends it as failed.
      var limitTook = false;
      try {
        final price = intent.limitPrice.clamp(0.01, 0.99).toDouble();
        var placedShares = 0.0;
        while (true) {
          // Cap by the USDC actually at the Safe — the swap can land slightly
          // under intent.amount (the fire gate only requires 99% of it), and
          // the CLOB rejects any order whose cost exceeds the balance. Without
          // the cap the rejection strands the swapped USDC with no order
          // placed. Same 99% cap as the market path below.
          final balance = _orderCash(intent);
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
          final actual = withFunding(PmIntents.order(
            walletId: tradingNotifier.signingWalletId ?? '',
            tokenId: intent.tokenId,
            isBuy: true,
            amountMax: PmGrants.buyCostMicros(shares, price),
            limitPrice: price,
            orderType: OrderType.gtc.name,
          ));
          final AuthGrant grant;
          final parent = limitApproval;
          if (parent == null) {
            final consumed = _autofireApproval(actual);
            if (consumed == null) {
              if (funded) journey.abandoned(OneBalanceVenue.predictions);
              PredictionFundingLedger.instance
                  .release(intent.fundQuoteRef, reason: 'abandoned');
              return;
            }
            limitApproval = consumed;
            grant = GrantGuard.chain(consumed, actual);
          } else {
            // Sent again after "not usable yet": inside the same approval.
            grant = autofireRetryGrant(parent, actual);
          }
          PredictionFundingLedger.instance.reserve(intent.fundQuoteRef);
          try {
            _placeStartedAt = OrderFundingJourney.clock();
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
              onStep: (step) => _placementStep(intent, step),
            );
            placedShares = shares;
            limitTook = true;
            break;
          } catch (e) {
            if (await _waitAfterNotReady(
                e, intent, limitApproval, notReady++,
                since: notReadySince ??= DateTime.now())) {
              continue;
            }
            rethrow;
          }
        }
        unawaited(tradingNotifier.refresh().catchError((_) {}));
        ref.invalidate(polymarketOpenOrdersProvider);
        if (funded && _sameAttempt(intent)) {
          journey.completed(OneBalanceVenue.predictions,
              resized: false, amountUsd: placedShares * price);
        }
        // The resting order holds its own cash on the book (the venue's
        // open orders); the rest of the move is idle from now.
        PredictionFundingLedger.instance
            .release(intent.fundQuoteRef, reason: 'placed');
        if (!_sameAttempt(intent)) return;
        pendingNotifier.updateStatus(PendingBetStatus.done);
        Future.delayed(const Duration(milliseconds: 600), () {
          try {
            if (_sameAttempt(intent)) pendingNotifier.clear();
          } catch (_) {}
        });
      } catch (e, st) {
        if (!_sameAttempt(intent)) return;
        // Taken by the venue, then something of ours threw (a read, the
        // bookkeeping): the order rests on the book, never "failed".
        if (limitTook) {
          if (kDebugMode) debugPrint('[pm-autofire] after the limit: $e\n$st');
          try {
            if (funded) {
              journey.completed(OneBalanceVenue.predictions, resized: false);
            }
          } catch (_) {}
          try {
            PredictionFundingLedger.instance
                .release(intent.fundQuoteRef, reason: 'placed');
          } catch (_) {}
          try {
            pendingNotifier.updateStatus(PendingBetStatus.done);
          } catch (_) {}
          Future.delayed(const Duration(milliseconds: 600), () {
            try {
              if (_sameAttempt(intent)) pendingNotifier.clear();
            } catch (_) {}
          });
          return;
        }
        if (e is PendingPolymarketOrder) {
          if (funded) {
            journey.completed(OneBalanceVenue.predictions, resized: false);
          }
          PredictionFundingLedger.instance
              .release(intent.fundQuoteRef, reason: 'placed');
          pendingNotifier.updateStatus(PendingBetStatus.awaitingConfirmation);
          return;
        }
        if (e is _ApprovalLapsed) {
          _trackFailed(intent, 'approval_expired');
          if (funded) journey.abandoned(OneBalanceVenue.predictions);
          _cancelForReconfirm();
          return;
        }
        PredictionFundingLedger.instance
            .release(intent.fundQuoteRef, reason: 'failed');
        _trackFailed(intent, _failureCode(e), stackTrace: st);
        if (funded) {
          journey.failed(OneBalanceVenue.predictions, _failureStage(e),
              _failureCode(e));
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
      eventSlug: intent.eventSlug,
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
    // The last order sent (its shares, and whether it was resized to what
    // landed), for the lookup of one whose answer proved nothing; and
    // whether the venue took it, after which nothing ends it as failed.
    var sentShares = 0.0;
    var sentResized = false;
    var venueTook = false;
    // The venue's answer once it took the order, and what it paid when
    // that answer is a verified match (the receipt's figures).
    Map<String, dynamic>? takenAnswer;
    double? takenPaid;
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
      // Its seconds reach the `legs` breakdown through the conversion's
      // own moments ([_onWrapPhase]), as every conversion of a funded
      // attempt does.
      await tradingNotifier
          .readyCollateralForBuy(fees.allInCost(intent.amount, approvedMax));
      if (!_sameAttempt(intent)) return;

      AuthGrant? approval;
      Map<String, dynamic>? response;
      var resized = false;
      var orderedShares = 0.0;
      var priceRetried = false;
      var notReady = 0;
      DateTime? notReadySince;
      while (true) {
        retried = priceRetried;
        final book = await _freshBook(intent.tokenId);
        if (!_sameAttempt(intent)) return;
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

        final balance = _orderCash(intent);
        // The swap lands roughly the stake; the venue also takes its fees
        // from the same balance. A funded bet is placed for what landed
        // when the deposit came in short, down to the venue's minimum;
        // under it, it fails and the cash is released for the sweeper.
        final landed = landedStakeFor(
            amount: intent.amount,
            balance: balance,
            feeTerms: fees,
            price: fill.quote.bestAsk,
            isLimit: false,
            reserve: PolymarketMarketBuyQuote.roundingHeadroom);
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
            min(
                intent.amount,
                fees.maxNotionalFor(balance, fill.quote.bestAsk,
                    reserve: PolymarketMarketBuyQuote.roundingHeadroom));
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
            fees.allInCost(minShares * fill.orderPrice, fill.quote.bestAsk) +
                    PolymarketMarketBuyQuote.roundingHeadroom <=
                balance + 1e-9 &&
            minShares * fill.orderPrice <= intent.amount + 0.02) {
          shares = (minShares * 100).ceilToDouble() / 100;
        }
        orderedShares = shares;
        sentShares = shares;
        sentResized = resized;
        // The stake itself is signed, to the cent, never the floored
        // shares × price (a typed \$5.00 signed as \$4.99); the venue's
        // minimum when the shares were lifted to it.
        final spend = max(stake, shares * fill.orderPrice);
        final actual = withFunding(PmIntents.order(
          walletId: tradingNotifier.signingWalletId ?? '',
          tokenId: intent.tokenId,
          isBuy: true,
          amountMax: PmGrants.orderAmount(
              isBuy: true,
              size: shares,
              price: fill.orderPrice,
              spendUsd: spend),
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
          // The one re-priced order, or one sent again after "not usable
          // yet": inside the same approval's bounds (amount, worst price,
          // slippage, funding cap), never wider.
          grant = autofireRetryGrant(parent, actual);
        }

        // Final stage of the progress bar — the CLOB call is in flight.
        placingNotifier.advanceStep(placementId,
            step: 3,
            label: l10nForLanguage(ref.read(settingsProvider).language)
                .betPlacingOrder);
        ledger.reserve(fundingKey);
        try {
          _placeStartedAt = OrderFundingJourney.clock();
          response = await tradingNotifier.placeOrder(
            tokenId: intent.tokenId,
            side: OrderSide.buy,
            size: shares,
            spendUsd: spend,
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
            onStep: (step) => _placementStep(intent, step),
          );
          break;
        } catch (e) {
          // Refused for its price (the book moved between the read and
          // the match): one more read and one re-priced order, from the
          // money already there. Nothing is funded again.
          if (!priceRetried &&
              e is PolymarketOrderNotAcceptedException &&
              isPolymarketPriceRefusal(e.reason)) {
            priceRetried = true;
            continue;
          }
          // Refused only because the money is not usable yet (still
          // converting, not counted by the book): wait until it is and
          // send again from the same money, never funded again.
          if (await _waitAfterNotReady(e, intent, approval, notReady++,
              since: notReadySince ??= DateTime.now(),
              requiredCostMicros:
                  BigInt.from((fill.quote.allInMax * 1e6).ceil()))) {
            continue;
          }
          rethrow;
        }
      }
      final placed = response;
      venueTook = true;
      takenAnswer = placed;

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
        takenPaid = paidUsdc;
        unawaited(costBasis.addCost(intent.tokenId, paidUsdc)
            .catchError((_) {}));
      }

      unawaited(tradingNotifier.refresh().catchError((_) {}));
      if (!_sameAttempt(intent)) {
        ledger.release(fundingKey, reason: 'placed');
        if (!_disposed) ref.invalidate(polymarketOpenOrdersProvider);
        return;
      }
      pendingNotifier.recordFill(placed);
      // Taken without a fill in the answer: a game in play holds the order
      // for its in-play delay, then matches or kills it. Followed to that
      // end here, so the slip shows the receipt once it matched and says
      // the price moved once it was killed, instead of ending on "check
      // your positions" while the order was still going through.
      // Same for an order found by a lookup after a lost answer: the record
      // has no fill amounts in it.
      if (!verifiedFill &&
          (placed['status']?.toString().toLowerCase() == 'delayed' ||
              placed['recovered'] == true) &&
          await _followHeldOrder(intent, placed,
              orderedShares: orderedShares,
              placementId: placementId,
              retried: retried,
              resized: resized,
              costBasis: costBasis)) {
        return;
      }
      if (!_sameAttempt(intent)) return;
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
          if (_sameAttempt(intent)) pendingNotifier.clear();
        } catch (_) {}
      });
    } catch (e, st) {
      if (!_sameAttempt(intent)) return;
      if (kDebugMode) debugPrint('[pm-autofire] failed: $e\n$st');
      // The venue took the order and something of ours threw after that:
      // never "failed". A verified match still ends on the receipt; any
      // other answer waits for its confirmation.
      if (venueTook && e is! PendingPolymarketOrder) {
        _endTaken(intent,
            answer: takenAnswer,
            paidUsdc: takenPaid,
            resized: sentResized,
            placementId: placementId);
        return;
      }
      // Sent, and the answer proved nothing: looked up with the venue by
      // its id first (the same follow a live game's held order gets).
      // Matched, the receipt; ended with nothing bought, said so; still
      // nowhere, it waits for its confirmation as before.
      if (e is PolymarketOrderOutcomeUnknown &&
          e.orderId != null &&
          !e.lookedUp &&
          sentShares > 0) {
        placingNotifier.markConfirming(placementId);
        pendingNotifier.setStage(PendingBetStage.reconciling);
        var ended = false;
        try {
          ended = await _followHeldOrder(
              intent, {'orderID': e.orderId, 'status': ''},
              orderedShares: sentShares,
              placementId: placementId,
              retried: retried,
              resized: sentResized,
              costBasis: costBasis);
        } catch (_) {}
        try {
          final status = ref.read(pendingPolymarketBetProvider)?.status;
          // Categorical only: never the order's id.
          TrackingService.track('polymarket_order_outcome_reconciled',
              params: {
                'outcome': !ended
                    ? 'unconfirmed'
                    : status == PendingBetStatus.failed
                        ? 'not_filled'
                        : 'filled',
                'side': 'buy',
                'order_type': 'market',
                'entry_source': 'autofire',
              });
        } catch (_) {}
        if (ended) {
          unawaited(tradingNotifier
              .checkPendingOrder(tokenId: intent.tokenId)
              .catchError((_) {}));
          return;
        }
        if (!_sameAttempt(intent)) return;
      }
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
      // Its approval ran out while the money became usable: nothing was
      // placed, the person confirms it again.
      if (e is _ApprovalLapsed) {
        _trackFailed(intent, 'approval_expired', retried: retried);
        if (funded) journey.abandoned(OneBalanceVenue.predictions);
        _cancelForReconfirm(placementId: placementId);
        return;
      }
      // Refused because the round closed in the meantime: said as such.
      if (autofireRoundClosed(intent)) {
        _failRoundClosed(intent, placementId: placementId);
        return;
      }
      // A 5-minute round whose price moved past the approval while the
      // money was moving: the price now, and the slip's one tap tries
      // again under a new approval (never placed by itself): at it while
      // the round is open, on the series' round in play once it ended.
      final moved = await _roundPriceMoved(intent, e,
          slippagePct:
              autofireSlippagePct(intent.expectedPrice, intent.slippagePct),
          fees: intent.feeTerms ?? PolymarketFeeTerms.worstCase);
      if (!_sameAttempt(intent)) return;
      if (moved != null) {
        _trackFailed(intent, 'price_moved',
            stackTrace: st, retried: retried, error: e);
        if (funded) {
          journey.failed(OneBalanceVenue.predictions, OrderFundingStage.order,
              _failureCode(e));
        }
        ledger.release(fundingKey, reason: 'failed');
        final msg = l10nForLanguage(ref.read(settingsProvider).language)
            .slipFundingRoundPriceMoved(formatPolyChance(moved.price));
        pendingNotifier.updateStatus(PendingBetStatus.failed,
            errorMessage: msg,
            retryMaxPrice: moved.cap,
            movedToPrice: moved.price,
            failureCode: 'round_price_moved');
        placingNotifier.markFailed(placementId, msg);
        return;
      }
      _trackFailed(intent, _failureCode(e),
          stackTrace: st, retried: retried, error: e);
      if (funded) {
        journey.failed(OneBalanceVenue.predictions, _failureStage(e),
            _failureCode(e));
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

  /// The venue took [intent]'s order ([answer]) and something of ours
  /// threw after that (the receipt's bookkeeping, a read, a listener):
  /// never "failed", and every step here runs on its own so one more throw
  /// cannot undo the rest. A verified match ([paidUsdc]) ends on the
  /// receipt with the venue's figures; any other answer waits for its
  /// confirmation (the slip's fill listener and the position landing
  /// settle it), the cash released as placed.
  void _endTaken(PendingBetIntent intent,
      {required Map<String, dynamic>? answer,
      required double? paidUsdc,
      required bool resized,
      String? placementId}) {
    void quietly(void Function() step) {
      try {
        step();
      } catch (_) {}
    }

    final pendingNotifier = ref.read(pendingPolymarketBetProvider.notifier);
    final placingNotifier = ref.read(placingPolymarketBetProvider.notifier);
    if (intent.funded) {
      quietly(() => OrderFundingJourney.instance.completed(
          OneBalanceVenue.predictions,
          resized: resized,
          amountUsd: paidUsdc));
    }
    quietly(() => PredictionFundingLedger.instance
        .release(intent.fundQuoteRef, reason: 'placed'));
    var receipt = false;
    if (answer != null && paidUsdc != null) {
      try {
        pendingNotifier.recordFill(answer);
        pendingNotifier.updateStatus(PendingBetStatus.done);
        receipt = true;
      } catch (_) {}
    }
    if (receipt) {
      if (placementId != null) {
        quietly(() => placingNotifier.markSucceeded(placementId,
            holdUntilPositionArrives: true));
      }
      Future.delayed(const Duration(milliseconds: 600), () {
        try {
          if (_sameAttempt(intent)) pendingNotifier.clear();
        } catch (_) {}
      });
      return;
    }
    quietly(() => ref.invalidate(polymarketOpenOrdersProvider));
    quietly(() =>
        pendingNotifier.updateStatus(PendingBetStatus.awaitingConfirmation));
    if (placementId != null) quietly(() => placingNotifier.clear(placementId));
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
    required PolymarketCostBasisNotifier costBasis,
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
            if (_sameAttempt(intent)) {
              pendingNotifier.setStage(PendingBetStage.delayed);
            }
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
    if (!_sameAttempt(intent)) {
      ledger.release(intent.fundQuoteRef, reason: 'placed');
      unawaited(tradingNotifier.refresh().catchError((_) {}));
      unawaited(settling.then((s) => _afterHeldFill(intent, placed, s,
          placementId: placementId, retried: retried, costBasis: costBasis)));
      return true;
    }
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
        if (_sameAttempt(intent)) pendingNotifier.clear();
      } catch (_) {}
    });
    // The rest of the settlement behind the receipt: the venue's own cost
    // for the funnel, revenue and the cost basis (the answer echoed none).
    unawaited(settling.then((s) => _afterHeldFill(intent, placed, s,
        placementId: placementId, retried: retried, costBasis: costBasis)));
    return true;
  }

  /// A held order that matched: its fill reported from the venue's own
  /// figures (never estimated), or its on-chain failure said. Never
  /// throws.
  void _afterHeldFill(PendingBetIntent intent, Map<String, dynamic> placed,
      PmSellSettlement s,
      {required String placementId, required bool retried,
      required PolymarketCostBasisNotifier costBasis}) {
    try {
      if (s.result == PmSellResult.failed) {
        _trackFailed(intent, 'failed_onchain',
            retried: retried, settlement: s.analyticsParams());
        if (_sameAttempt(intent)) {
          ref.read(placingPolymarketBetProvider.notifier).markFailed(
              placementId,
              l10nForLanguage(ref.read(settingsProvider).language)
                  .betBuyFailedOnChain);
        }
        return;
      }
      final cost = s.proceeds;
      if (s.soldShares <= 0 || cost == null || cost <= 0) return;
      unawaited(costBasis.addCost(intent.tokenId, cost)
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
    if (e is PolymarketCollateralPending) return 'balance_confirmation_timeout';
    // The readiness step that never cleared in the wait, by name (the
    // copy stays the safe generic one): the spend approval or account
    // setup, or the conversion to pUSD.
    if (e is PolymarketSetupIncomplete) return 'approval_timeout';
    if (e is PolymarketFundsConverting) return 'conversion_timeout';
    if (e is PolymarketThinBook) return 'liquidity_unavailable';
    if (e is PolymarketOrderNotAcceptedException &&
        isPolymarketPriceRefusal(e.reason)) {
      return 'price_moved';
    }
    // The order fell outside its approval at the executor's own check:
    // nothing was signed, the person approves again.
    if (e is ReauthRequired) return 'approval_drift';
    if (e is GrantExpired) return 'approval_expired';
    return TrackingService.errorCategory(e);
  }

  static OrderFundingStage _failureStage(Object e) =>
      e is PolymarketCollateralPending || e is PolymarketFundsConverting ||
              e is PolymarketSetupIncomplete
          ? OrderFundingStage.credit : OrderFundingStage.order;

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
    if (e is PolymarketCollateralPending) return l10n.betAutofireFundsTimeout;
    if (e is ResolvedPolymarketOrder) return l10n.betPreviousOrderChecked;
    // The price moved past what the approval covers (the slip's own copy:
    // where it went, or what fills now).
    if (e is PolymarketThinBook) return polymarketThinBookMessage(l10n, e);
    final slow = polymarketSlowConnectionLine(l10n, e);
    if (slow != null) return slow;
    if (e is PolymarketOrderNeverSent) return l10n.betConnectionUnavailable;
    if (e is PolymarketOrderNotAcceptedException &&
        isPolymarketPriceRefusal(e.reason)) {
      return l10n.betBuyLiquidityUnavailable;
    }
    // Refused by its approval before anything was signed: approving again
    // (the slip's Retry) places it. Debug logs name the drifted keys.
    if (e is ReauthRequired || e is GrantExpired) {
      if (kDebugMode) debugPrint('[pm-autofire] approval refused: $e');
      return e is ReauthRequired
          ? l10n.stepUpDetailsChanged
          : l10n.stepUpApprovalExpired;
    }
    // The generic words: the cause is always in the debug log.
    if (kDebugMode) {
      debugPrint('[pm-autofire] generic failure copy for: '
          '${e.runtimeType}: $e');
    }
    return l10n.betActionNotCompleted;
  }
}

/// What first saw a funded bet's money in full on chain: Orchestra's
/// status (a leg delivered, the deposit's own path), the bet's own chain
/// watch, the autofire's await / readiness poll, or the trading poll.
/// Sent as `detected_by` on the funding journey's outcome.
abstract final class CreditDetectedBy {
  static const String status = 'status';
  static const String chainPoll = 'chain_poll';
  static const String awaitPoll = 'await_poll';
  static const String tradingPoll = 'trading_poll';
}

/// The exact credit timings of a funded Predictions bet, on its
/// `order_funding_*` outcome (milliseconds).
abstract final class CreditTiming {
  static const String fundedToOnchainSeen = 'ms_funded_to_onchain_seen';
  static const String seenToWrapSubmitted = 'ms_seen_to_wrap_submitted';
  static const String wrapSubmittedToMined = 'ms_wrap_submitted_to_mined';
  static const String minedToBookCounts = 'ms_mined_to_book_counts';
}

class _CreditTimeline {
  _CreditTimeline(this.key);

  final ({String token, DateTime? queuedAt, String? runId}) key;
  DateTime? seenAt;
  DateTime? wrapSubmittedAt;
  DateTime? wrapStartedAt;
  DateTime? minedAt;
  bool bookCounted = false;
  int chainReads = 0;
  int chainRpcErrors = 0;
  int? chainEndpoint;
  final Map<String, int> counts = {};
}

/// The funded Predictions bet's read counters, on its `order_funding_*`
/// outcome: the chain watch's ticks, the endpoints that failed, the index
/// (in the configured Polygon read list, never a URL) of the endpoint
/// that answered last, and the readiness reads that got no wallet answer
/// or no order-book count.
abstract final class CreditCount {
  static const String chainReads = 'chain_reads';
  static const String chainRpcErrors = 'chain_rpc_errors';
  static const String chainRpcEndpoint = 'chain_rpc_endpoint';
  static const String readinessReadErrors = 'readiness_read_errors';
  static const String bookCountErrors = 'book_count_errors';
}
