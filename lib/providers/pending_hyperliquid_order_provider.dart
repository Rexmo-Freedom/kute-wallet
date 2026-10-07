import 'package:kute/helpers/hyperliquid_error_message.dart';
// lib/providers/pending_hyperliquid_order_provider.dart
//
// Holds a Hyperliquid order intent while the user tops up USDC — the
// order slip pre-stores the intent when the user hits Long/Short/Buy
// with an insufficient perp balance, and the auto-fire watcher below
// fires the order the moment hyperliquidWithdrawableProvider's
// underlying balance covers the margin. Mirrors
// pending_polymarket_bet_provider.dart + pending_bet_autofire.dart,
// folded into one file (the HL flow has no swap leg — a deposit credits
// perp USDC directly, so the state machine is smaller).
//
// Auto-fire consent rule (same as Polymarket's): only `awaitingBalance`
// fires — the state the slip sets AFTER the user explicitly confirmed
// the order and kicked off a deposit. `awaitingDeposit` (picker open)
// must NEVER auto-fire.
//
// Balance watching is a BOUNDED POLL (4 s tick, 12 min ceiling), not a
// permanent ref.listen on hyperliquidWithdrawableProvider: the watcher
// is a non-autoDispose Provider bootstrapped by whatever UI surface
// reads it, and a build-time listen would pin the whole account stack
// (address derivation + API polling) alive for every user forever. The
// poll only runs while an intent is actually awaiting funds, and each
// tick reads a fresh account snapshot — exactly what PM's
// `_startAwaitPolling` does for swaps that settle off-screen.
//
// Step-up (Wallet Hardening Phase 1b.5, D-10): the order fires on the grant
// the user gave at confirm time ([confirmPendingHlOrderAutofire]), held 30
// minutes in memory only and consumed against the exact order only while the
// session is unlocked. No grant (for example after a restart) or an expired
// one cancels the order and asks the user to confirm it again.

import 'dart:async';
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
  }) : createdAt = createdAt ?? DateTime.now();

  PendingHlOrderIntent copyWith({
    PendingHlOrderStatus? status,
    String? errorMessage,
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
}

final pendingHyperliquidOrderProvider =
    NotifierProvider<PendingHyperliquidOrderNotifier, PendingHlOrderIntent?>(
  PendingHyperliquidOrderNotifier.new,
);

/// The autofire grant slot for the one pending Hyperliquid order (D-10).
const String kPendingHlOrderAutofireId = 'hyperliquid_pending_order';

/// What a queued order is approved for at confirm time (D-10): exactly the
/// order the autofire places (market, side, margin, leverage, slippage).
SensitiveIntent pendingHlOrderAutofireIntent(
  PendingHlOrderIntent intent,
  HlMarket market, {
  required String walletId,
}) =>
    intent.kind == HlMarketKind.spot
        ? HlIntents.spotOrder(
            walletId: walletId,
            market: market,
            isBuy: intent.isLong,
            usd: intent.marginUsd,
            slippagePct: intent.slippagePct,
          )
        : HlIntents.openPosition(
            walletId: walletId,
            market: market,
            isLong: intent.isLong,
            marginUsd: intent.marginUsd,
            leverage: intent.leverage,
            slippagePct: intent.slippagePct,
          );

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

  /// See [PendingHlOrderIntent.createdAt] — intents older than this
  /// never auto-place.
  static const kMaxIntentAge = Duration(minutes: 30);
  static const Duration _kAwaitPollInterval = Duration(seconds: 4);
  static const Duration _kAwaitMaxWait = Duration(minutes: 12);

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
  }

  void dispose() {
    _stopAwaitPolling();
    AuthGrantRegistry.instance
        .removeAutofireExpiredListener(_onAutofireExpired);
  }

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
    ref
        .read(pendingHyperliquidOrderProvider.notifier)
        .updateStatus(PendingHlOrderStatus.failed, errorMessage: msg);
    if (!drift) {
      TrackingService.track('pending_intent_expired', params: {'venue': venue});
    }
  }

  /// Consumes the confirm-time grant against [actual] and returns the
  /// single-use grant the trading notifier takes. Null when the order must
  /// not fire now: locked (it waits for the unlock), or no live grant or
  /// drift (cancelled, the user confirms again).
  AuthGrant? _autofireGrant(SensitiveIntent actual, {String? placementId}) {
    try {
      final parent = AuthGrantRegistry.instance.consumeAutofire(
        kPendingHlOrderAutofireId,
        actual,
        session: ref.read(stepUpSessionStateProvider),
      );
      return GrantGuard.chain(parent, actual);
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

    // Same 99% threshold as the PM overlay: the exchange rejects real
    // overcommits, and balances are floating-point, so a tiny buffer
    // prevents an infinite "almost there" race.
    if (withdrawable < intent.marginUsd * 0.99) {
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
      ref.read(pendingHyperliquidOrderProvider.notifier).updateStatus(
            PendingHlOrderStatus.failed,
            errorMessage: l10nForLanguage(ref.read(settingsProvider).language)
                .hlDepositArrivedPricesMoved,
          );
      return;
    }
    _firing = true;
    try {
      await _placeOrder(intent);
    } catch (_) {
      // _placeOrder owns its error reporting; swallow so a throw doesn't
      // block subsequent attempts.
    } finally {
      _firing = false;
    }
  }

  Future<void> _placeOrder(PendingHlOrderIntent intent) async {
    final pending = ref.read(pendingHyperliquidOrderProvider.notifier);
    final placing = ref.read(placingHyperliquidOrderProvider.notifier);
    // D-10: never fire without the confirm-time grant (a restart drops it).
    if (!AuthGrantRegistry.instance
        .hasAutofireGrant(kPendingHlOrderAutofireId)) {
      _cancelForReconfirm();
      return;
    }
    pending.updateStatus(PendingHlOrderStatus.placing);

    // Re-use the slip's early-registered tile when present (markPlacing
    // is idempotent per coin+side) so the user sees one continuous tile.
    final placementId = placing.markPlacing(
      coin: intent.coin,
      marketLabel: intent.marketLabel,
      isLong: intent.isLong,
      marginUsd: intent.marginUsd,
      leverage: intent.leverage,
      sizeRequested: intent.expectedPx > 0
          ? intent.marginUsd * intent.leverage / intent.expectedPx
          : 0,
    );

    try {
      final market = await _resolveMarket(intent);
      final grant = _autofireGrant(
        pendingHlOrderAutofireIntent(
          intent,
          market,
          walletId: pickSpendingWallet(ref.read(settingsProvider))?.id ?? '',
        ),
        placementId: placementId,
      );
      if (grant == null) return;
      VenueAnalytics.stage('hl', intent.coin, {
        'origin': intent.source ?? 'unknown',
        'entry_source': 'autofire',
        'funding_source': 'venue_balance',
        'slippage_bps': VenueAnalytics.bps(intent.slippagePct),
      });
      final trading = ref.read(hyperliquidTradingProvider.notifier);
      if (intent.kind == HlMarketKind.spot) {
        await trading.placeSpotOrder(
          market: market,
          isBuy: intent.isLong,
          usd: intent.marginUsd,
          slippagePct: intent.slippagePct,
          source: 'autofire',
          grant: grant,
        );
      } else {
        await trading.openPosition(
          market: market,
          isLong: intent.isLong,
          marginUsd: intent.marginUsd,
          leverage: intent.leverage,
          slippagePct: intent.slippagePct,
          source: 'autofire',
          grant: grant,
        );
      }
      placing.markSucceeded(placementId);
      pending.updateStatus(PendingHlOrderStatus.done);
    } catch (e, st) {
      _trackAutofireFailed('error', intent, error: e);
      TrackingService.hyperliquidOrderFailed(
        coin: intent.coin,
        reason: TrackingService.errorCategory(e),
        action: 'open',
        orderType: 'market',
        isBuy: intent.isLong,
        notionalUsd: intent.marginUsd * intent.leverage,
        leverage: intent.leverage,
        walletKind: 'hot',
        stackTrace: st,
        extra: {'origin': intent.source ?? 'unknown', 'entry_source': 'autofire'},
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
  /// flight. Idempotent — repeated _maybeFire calls won't stack timers.
  void _startAwaitPolling() {
    if (_awaitPoll != null) return;
    _awaitStart = DateTime.now();
    _awaitPoll = Timer.periodic(_kAwaitPollInterval, (_) {
      final intent = ref.read(pendingHyperliquidOrderProvider);
      if (intent == null ||
          intent.status != PendingHlOrderStatus.awaitingBalance) {
        _stopAwaitPolling();
        return;
      }
      // Give up after a sane ceiling so a never-arriving deposit doesn't
      // poll forever. The funds are safe on the exchange account
      // regardless; surface an actionable failure so the user can retry
      // (instant once the USDC is there).
      final start = _awaitStart;
      if (start != null &&
          DateTime.now().difference(start) > _kAwaitMaxWait) {
        _stopAwaitPolling();
        _trackAutofireFailed('funds_timeout', intent);
        ref.read(pendingHyperliquidOrderProvider.notifier).updateStatus(
              PendingHlOrderStatus.failed,
              errorMessage: l10nForLanguage(ref.read(settingsProvider).language)
                  .hlFundsTimeout,
            );
        return;
      }
      unawaited(_maybeFire());
    });
  }

  void _stopAwaitPolling() {
    _awaitPoll?.cancel();
    _awaitPoll = null;
    _awaitStart = null;
  }
}
