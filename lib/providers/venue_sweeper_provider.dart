// lib/providers/venue_sweeper_provider.dart
//
// Brings idle venue cash back to Dollars so the one balance stays true:
// money the user is not investing lives on the spending account, not at
// a venue. This file binds `VenueSweeper` (the state machine, in
// `lib/services/one_balance/venue_sweeper.dart`) to the app: the reads
// it decides on, the rails it sends through, the triggers that wake it.
//
// Same long-lived shape as `ClaimAutoFire`: a non-autoDispose provider
// bootstrapped once by Home, alive for the session whatever screen is
// up. It reads only balances the app already holds (the Predictions
// trading state Home keeps warm, the Hyperliquid state while an
// Investing surface runs, else the always-on coarse free-USDC figure,
// the Orchestra rows background sync maintains) — no new endpoints.
//
// Spending (hot) wallet only: a Ledger cannot sign automatically and
// keeps today's flow. Every send goes out under
// `SweepAuthorization.automatic`, which the rails accept only for the
// wallet's own Spark address on a verified quote.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/auth_provider.dart'
    show appVisibleProvider, sessionUnlockedProvider;
import 'package:kute/providers/hyperliquid_account_provider.dart'
    show
        hyperliquidFreeUsdcProvider,
        hyperliquidHeldPositionsProvider,
        hyperliquidOpenPositionsCountProvider,
        hyperliquidProvisionedProvider;
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/investment_balances_provider.dart'
    show polymarketInvestmentBalances;
import 'package:kute/providers/pending_hyperliquid_order_provider.dart';
import 'package:kute/providers/pending_polymarket_bet_provider.dart';
import 'package:kute/providers/placing_hyperliquid_order_provider.dart';
import 'package:kute/providers/placing_polymarket_bet_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/services/funding/settlement_stage.dart';
import 'package:kute/services/funding/settlement_store.dart';
import 'package:kute/services/one_balance/hyperliquid_move_rail.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/prediction_funding_ledger.dart';
import 'package:kute/services/one_balance/predictions_venue_funder.dart'
    show predictionsVenueFunderProvider;
import 'package:kute/services/one_balance/route_minimums.dart';
import 'package:kute/services/one_balance/sweep_rules.dart';
import 'package:kute/services/one_balance/venue_activity.dart';
import 'package:kute/services/one_balance/venue_cash_released.dart';
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/one_balance/venue_sweeper.dart';
import 'package:kute/services/orchestra_routes.dart'
    show claimOrderTerminalAnalytics;
import 'package:kute/services/tracking_service.dart';

export 'package:kute/services/one_balance/venue_sweeper.dart'
    show VenueSweeperState;

/// The Predictions funder the sweeper sends through: the venue's
/// `PredictionsVenueFunder`, whose `sweepToDollars` is the Predictions
/// cash-out pointed at the wallet's own Spark address.
final predictionsSweepFunderProvider = Provider<SweepableVenueFunder?>(
    (ref) => ref.watch(predictionsVenueFunderProvider));

/// The foreground heartbeat between event-driven passes.
const Duration kVenueSweepHeartbeat = Duration(minutes: 3);

/// The one-time rollout flag's key for a wallet, in the settings box.
String oneBalanceRolloutKey(String walletId) =>
    'one_balance_rollout_v1:$walletId';

/// Whether the queued Predictions bet in [intent] still holds venue cash:
/// it waits for its funds, is being placed, or went out and its answer is
/// not in yet. A bet that failed, finished, or is only a slip being filled
/// in (nothing sent) holds nothing. Before, any bet left in the provider
/// held every sweep: a failed one stays there until a slip button resets
/// it, and closing the slip or failing with the slip gone never did.
bool pendingBetHoldsCash(PendingBetIntent? intent) => switch (intent?.status) {
      PendingBetStatus.converting ||
      PendingBetStatus.awaitingBalance ||
      PendingBetStatus.placing ||
      PendingBetStatus.awaitingConfirmation =>
        true,
      _ => false,
    };

/// Whether a settlement record in [stage], last updated at [updatedAt],
/// is money genuinely on its way (broadcast to processing, and recent)
/// and so holds the venue's sweep. A failed, needs-attention, unknown or
/// late record is watched by the reconciler for weeks; it is not a move in
/// flight, and it used to hold every sweep for that long.
bool settlementHoldsVenueCash(SettlementStage stage, DateTime updatedAt,
    {required DateTime now}) {
  const moving = {
    SettlementStage.broadcasting,
    SettlementStage.funded,
    SettlementStage.submitted,
    SettlementStage.processing,
  };
  return moving.contains(stage) &&
      now.difference(updatedAt) < kVenueMoveMaxAge;
}

/// When Predictions was last used, for the idle rule: now while it has
/// open orders, else the last order, sale, claim, cancel or funded bet
/// ([VenueActivity]); the epoch when nothing is known (cash from before
/// the rule is long idle).
DateTime predictionsLastActivity({required bool openOrders, required DateTime now}) {
  if (openOrders) return now;
  return VenueActivity.last(OneBalanceVenue.predictions) ??
      DateTime.fromMillisecondsSinceEpoch(0);
}

/// Orchestra chains a venue's settlement operations run on.
const Map<OneBalanceVenue, Set<String>> _venueChains = {
  OneBalanceVenue.predictions: {'polygon'},
  OneBalanceVenue.investing: {'hypercore'},
};

class _RiverpodSweeperHost extends VenueSweeperHost {
  _RiverpodSweeperHost(this._ref);

  final Ref _ref;
  final Map<OneBalanceVenue, DateTime> _lastDepositSettledAt = {};

  @override
  DateTime now() => DateTime.now();

  @override
  bool get sessionUnlocked => _ref.read(sessionUnlockedProvider);

  @override
  String? get spendingWalletId {
    final settings = _ref.read(settingsProvider);
    final spending = pickSpendingWallet(settings);
    if (spending == null) return null;
    final active = settings.activeWallet;
    if (active == null || active.id != spending.id) return null;
    return spending.id;
  }

  /// A deposit row into [venue] moved to success, or Predictions' own
  /// settle-and-wrap finished: the venue's grace window restarts.
  void noteDepositSettled(OneBalanceVenue venue) {
    _lastDepositSettledAt[venue] = now();
  }

  void noteOrdersChanged(List<SwapOrder>? previous, List<SwapOrder> next) {
    final wallet = spendingWalletId;
    final before = {
      for (final row in previous ?? const <SwapOrder>[]) row.id: row,
    };
    if (previous == null) return; // the first read is history
    for (final row in next) {
      if (!row.isComplete) continue;
      final was = before[row.id];
      if (was != null && was.isComplete) continue;
      final venue = venueDepositRowOf(row, walletId: wallet);
      if (venue != null) noteDepositSettled(venue);
    }
  }

  @override
  Future<VenueSnapshot?> readVenue(OneBalanceVenue venue) async {
    final wallet = spendingWalletId;
    final nowMs = now().millisecondsSinceEpoch;
    final pendingRows = _ref.read(swapOrdersProvider).any((row) =>
        pendingVenueMoveOf(row, walletId: wallet, nowMs: nowMs)?.$1 == venue);
    final pendingOps = await _hasPendingSettlement(venue, wallet);
    final settledAt = _lastDepositSettledAt[venue];

    switch (venue) {
      case OneBalanceVenue.predictions:
        final pm = _ref.read(polymarketTradingProvider).valueOrNull;
        if (pm == null || !pm.isAuthenticated || !pm.balanceKnown) {
          return null;
        }
        final balances =
            polymarketInvestmentBalances(state: pm, orders: pm.openOrders);
        final available = balances.available;
        return VenueSnapshot(
          idleUsd: pm.usdcBalance,
          // An order the arithmetic could not read keeps every dollar
          // reserved until it can.
          sweepableUsd: available ?? 0,
          hasReservations: available == null || (balances.committed ?? 0) > 0,
          hasPendingMove: pendingRows ||
              pendingOps ||
              PredictionFundingLedger.instance.hasInFlight,
          lastDepositSettledAt: settledAt,
          hasPendingIntent:
              pendingBetHoldsCash(_ref.read(pendingPolymarketBetProvider)) ||
                  PredictionFundingLedger.instance.hasReserved,
          isPlacing: pm.isPlacingOrder ||
              _ref
                  .read(placingPolymarketBetProvider)
                  .any((b) => b.status != PlacingBetStatus.failed),
          isClaiming: pm.openPositions.any((p) => p.redeemable) ||
              pm.clearingConditionIds.isNotEmpty ||
              pm.pendingSaleTokens.isNotEmpty,
          // Predictions cash stays, available, until the venue has been
          // idle a day (no orders, sells, claims, cancels, open orders).
          lastActivityAt: predictionsLastActivity(
              openOrders: pm.openOrders.isNotEmpty, now: now()),
        );
      case OneBalanceVenue.investing:
        double idle;
        var reservations = false;
        var placing = false;
        var twap = false;
        var closing = false;
        final hl = _ref.exists(hyperliquidTradingProvider)
            ? _ref.read(hyperliquidTradingProvider).valueOrNull
            : null;
        if (hl != null && hl.isInitialized) {
          idle = hl.availableUsdc;
          reservations = hl.positions.isNotEmpty ||
              hl.openOrders.isNotEmpty ||
              hl.totalMarginUsed > 0;
          placing = hl.isPlacingOrder;
          twap = hl.runningTwaps.any((t) => !t.expired);
          closing = hl.pendingCloseCoins.isNotEmpty;
        } else if (!_ref.read(hyperliquidProvisionedProvider)) {
          // Never provisioned: nothing there, and known to be nothing.
          idle = 0;
        } else {
          idle = _ref.read(hyperliquidFreeUsdcProvider);
          reservations = _ref.read(hyperliquidHeldPositionsProvider).isNotEmpty;
        }
        double withdrawable = 0;
        if (idle >= kSweepDustUsd) {
          try {
            withdrawable =
                await _ref.read(hyperliquidMoveRailProvider).withdrawableUsd();
          } catch (_) {
            withdrawable = 0;
          }
        }
        return VenueSnapshot(
          idleUsd: idle,
          sweepableUsd: withdrawable,
          hasReservations: reservations,
          hasPendingMove: pendingRows || pendingOps,
          lastDepositSettledAt: settledAt,
          hasPendingIntent: _ref.read(pendingHyperliquidOrderProvider) != null,
          isPlacing: placing ||
              _ref.read(placingHyperliquidOrderProvider).isNotEmpty,
          hasOpenTwap: twap,
          isClaiming: closing,
        );
    }
  }

  Future<bool> _hasPendingSettlement(
      OneBalanceVenue venue, String? wallet) async {
    try {
      final store = await SettlementStore.shared();
      final chains = _venueChains[venue]!;
      final at = now();
      for (final op in await store.pendingForReconcile()) {
        if (wallet != null && op.walletId != wallet) continue;
        if (!settlementHoldsVenueCash(op.stage, op.updatedAt, now: at)) {
          continue;
        }
        if (chains.any(op.route.involvesChain)) return true;
      }
      return false;
    } catch (_) {
      // An unreadable store is a reason to wait, never to send.
      return true;
    }
  }

  @override
  Future<double> minimumUsd(OneBalanceVenue venue) =>
      _ref.read(routeMinimumsProvider).minimumUsd(venue);

  @override
  void noteAmountTooSmall(OneBalanceVenue venue, double usd) =>
      _ref.read(routeMinimumsProvider).noteAmountTooSmall(venue, usd);

  @override
  Future<void> prepare(OneBalanceVenue venue) async {
    if (venue == OneBalanceVenue.investing) {
      await _ref.read(hyperliquidMoveRailProvider).ensureGasFloat();
    }
  }

  @override
  Future<VenueMoveResult> send(
    OneBalanceVenue venue, {
    required double usd,
    required String purpose,
  }) {
    switch (venue) {
      case OneBalanceVenue.predictions:
        final funder = _ref.read(predictionsSweepFunderProvider);
        if (funder == null) {
          throw const RouteUnavailable('no Predictions sweep funder bound');
        }
        return funder.sweepToDollars(
            usd: usd, auth: SweepAuthorization.automatic, purpose: purpose);
      case OneBalanceVenue.investing:
        return _ref.read(hyperliquidMoveRailProvider).withdrawToDollars(
            usd: usd, auth: SweepAuthorization.automatic, purpose: purpose);
    }
  }

  @override
  bool rolloutDone(String walletId) {
    try {
      if (!Hive.isBoxOpen('settings')) return true; // no store: never loop
      return Hive.box('settings').get(oneBalanceRolloutKey(walletId)) == true;
    } catch (_) {
      return true;
    }
  }

  @override
  void markRolloutDone(String walletId) {
    try {
      if (!Hive.isBoxOpen('settings')) return;
      Hive.box('settings').put(oneBalanceRolloutKey(walletId), true);
    } catch (_) {/* best-effort */}
  }

  @override
  bool claimTerminal(String orderId, {required bool success}) =>
      claimOrderTerminalAnalytics(orderId, success: success);

  @override
  void track(String event, Map<String, Object> params) =>
      TrackingService.track(event, params: params);
}

class VenueSweeperNotifier extends Notifier<VenueSweeperState> {
  late final VenueSweeper _sweeper;
  late final _RiverpodSweeperHost _host;
  Timer? _heartbeat;
  Timer? _due;
  bool _visible = true;

  @override
  VenueSweeperState build() {
    _host = _RiverpodSweeperHost(ref);
    _sweeper = VenueSweeper(_host, onState: (s) {
      state = s;
      _armDueTimer();
    });

    final released = VenueCashReleased.stream.listen((event) {
      final (venue, reason) = event;
      unawaited(trigger(reason, venue: venue));
    });

    // Keeps the Investing badge poll alive for the session: it is what
    // fills `hyperliquidProvisionedProvider` and `hyperliquidFreeUsdcProvider`
    // (60 s, a local no-op for a wallet that never traded). Nothing else
    // mounted it, so without this the venue's cash was read only while
    // the trading stack ran, which only a browse/trade surface starts: a
    // region where `hyperliquid.browse` is withheld never saw its cash in
    // the header and never swept it home. The money is read whatever
    // browse, trade or deposit allow; only `hyperliquid.withdraw`, which
    // the rail checks, decides whether it moves.
    ref.listen(hyperliquidOpenPositionsCountProvider, (_, __) {},
        onError: (_, __) {});

    // Keeps the Predictions state warm for the session, like auto-claim,
    // and restarts the grace window when its deposit settle-and-wrap
    // finishes.
    ref.listen(polymarketTradingProvider, (_, __) {});
    StreamSubscription<void>? depositSettled;
    try {
      depositSettled = ref
          .read(polymarketTradingProvider.notifier)
          .depositSettled
          .listen((_) => _host.noteDepositSettled(OneBalanceVenue.predictions));
    } catch (_) {
      depositSettled = null;
    }

    ref.listen<List<SwapOrder>>(swapOrdersProvider, (previous, next) {
      _host.noteOrdersChanged(previous, next);
      _sweeper.noteOrders(next);
    });

    ref.listen<bool>(sessionUnlockedProvider, (previous, next) {
      if (next && previous != true) unawaited(trigger('resume'));
    });

    ref.listen<bool>(appVisibleProvider, (_, next) {
      _visible = next;
      if (next) {
        _startHeartbeat();
      } else {
        _heartbeat?.cancel();
        _heartbeat = null;
        unawaited(_sweeper.onAppPaused());
      }
    }, fireImmediately: true);

    ref.onDispose(() {
      released.cancel();
      depositSettled?.cancel();
      _heartbeat?.cancel();
      _due?.cancel();
      _sweeper.dispose();
    });
    return const VenueSweeperState();
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(kVenueSweepHeartbeat, (_) {
      if (_visible) unawaited(trigger('timer'));
    });
  }

  /// One-shot wake for a backoff ending or a held batch coming due.
  void _armDueTimer() {
    _due?.cancel();
    _due = null;
    final wait = _sweeper.nextDueIn();
    if (wait == null) return;
    final retry = _sweeper.nextDueIsRetry();
    _due = Timer(wait + const Duration(seconds: 1), () {
      _due = null;
      if (_visible) unawaited(trigger(retry ? 'retry' : 'timer'));
    });
  }

  /// Asks for a sweep pass now. [reason] is a `VenueCashReleased` label
  /// (`position_closed`, `market_resolved`, `order_cancelled`) or a
  /// trigger name (`resume`, `timer`, `retry`); [venue] names the venue an
  /// event released cash at.
  Future<void> trigger(String reason, {OneBalanceVenue? venue}) async {
    await _sweeper.trigger(reason, venue: venue);
    _armDueTimer();
  }
}

final venueSweeperProvider =
    NotifierProvider<VenueSweeperNotifier, VenueSweeperState>(
        VenueSweeperNotifier.new);
