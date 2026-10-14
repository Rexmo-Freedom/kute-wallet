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
        hyperliquidAddressProvider,
        hyperliquidFreeUsdcProvider,
        hyperliquidHeldPositionsProvider,
        hyperliquidOpenPositionsCountProvider,
        hyperliquidProvisionedProvider;
import 'package:kute/providers/hyperliquid_markets_provider.dart'
    show hyperliquidTradingModelProvider;
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
import 'package:kute/services/one_balance/investing_sweep_rules.dart';
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
    show
        VenueSweeperState,
        RebalanceOutcome,
        RebalanceOutcomeKind,
        kManualRebalanceTrigger;

/// The Predictions funder the sweeper sends through: the venue's
/// `PredictionsVenueFunder`, whose `sweepToDollars` is the Predictions
/// cash-out pointed at the wallet's own Spark address.
final predictionsSweepFunderProvider = Provider<SweepableVenueFunder?>(
    (ref) => ref.watch(predictionsVenueFunderProvider));

/// The foreground heartbeat between event-driven passes.
const Duration kVenueSweepHeartbeat = Duration(minutes: 3);

/// How long after a venue's cash moves its pass runs: a fill's balance
/// read and the reads behind it land as one pass.
const Duration kVenueCashPassDelay = Duration(seconds: 2);

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
  return moving.contains(stage) && now.difference(updatedAt) < kVenueMoveMaxAge;
}

/// When Predictions was last used, for the idle rule: now while it has
/// open orders, else the last order, sale, claim, cancel or funded bet
/// ([VenueActivity]); the epoch when nothing is known (cash from before
/// the rule is long idle).
DateTime predictionsLastActivity(
    {required bool openOrders, required DateTime now}) {
  if (openOrders) return now;
  return VenueActivity.last(OneBalanceVenue.predictions) ??
      DateTime.fromMillisecondsSinceEpoch(0);
}

/// Whether any order rests at the Investing account, read from the venue
/// itself (for when the trading state is not running). Unreadable holds:
/// an order resting there must never lose the cash it fills against.
/// Overridden in tests.
final investingRestingOrdersReaderProvider =
    Provider<Future<bool> Function()>((ref) => () async {
          try {
            final address = await ref
                .read(hyperliquidAddressProvider.future)
                .timeout(const Duration(seconds: 5));
            if (address == null || address.isEmpty) return true;
            final orders = await ref
                .read(hyperliquidTradingModelProvider)
                .getOpenOrders(address)
                .timeout(const Duration(seconds: 8));
            return orders.isNotEmpty;
          } catch (_) {
            return true;
          }
        });

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
    // Money landing at Investing is Investing activity: its cash stays.
    if (venue == OneBalanceVenue.investing) {
      VenueActivity.note(OneBalanceVenue.investing);
    }
  }

  Future<bool> _restingOrdersAtVenue() =>
      _ref.read(investingRestingOrdersReaderProvider)();

  /// Notes the deposit rows into a venue that just landed; returns their
  /// venues.
  Set<OneBalanceVenue> noteOrdersChanged(
      List<SwapOrder>? previous, List<SwapOrder> next) {
    final wallet = spendingWalletId;
    final before = {
      for (final row in previous ?? const <SwapOrder>[]) row.id: row,
    };
    final landed = <OneBalanceVenue>{};
    if (previous == null) return landed; // the first read is history
    for (final row in next) {
      if (!row.isComplete) continue;
      final was = before[row.id];
      if (was != null && was.isComplete) continue;
      final venue = venueDepositRowOf(row, walletId: wallet);
      if (venue != null) {
        noteDepositSettled(venue);
        landed.add(venue);
      }
    }
    return landed;
  }

  @override
  Future<VenueSnapshot?> readVenue(OneBalanceVenue venue) => _read(venue);

  /// A Rebalance sets the idle wait aside, so an Investing order resting
  /// at the venue that the held state does not know about is read from
  /// the venue whatever the idle window says (unreadable holds).
  @override
  Future<VenueSnapshot?> readVenueForRebalance(OneBalanceVenue venue) =>
      _read(venue, resolveResting: true);

  Future<VenueSnapshot?> _read(OneBalanceVenue venue,
      {bool resolveResting = false}) async {
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
        var positions = false;
        var cross = false;
        bool? resting;
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
          positions = hl.positions.isNotEmpty;
          cross = hl.positions.any((p) => p.isCross);
          resting = hl.openOrders.isNotEmpty;
        } else if (!_ref.read(hyperliquidProvisionedProvider)) {
          // Never provisioned: nothing there, and known to be nothing.
          idle = 0;
          resting = false;
        } else {
          idle = _ref.read(hyperliquidFreeUsdcProvider);
          final held = _ref.read(hyperliquidHeldPositionsProvider);
          reservations = held.isNotEmpty;
          positions = reservations;
          cross = held.any((p) => p.isCross);
        }
        // Investing cash stays, Available, until the account has sat idle
        // a day with nothing open (investing_sweep_rules.dart).
        var activeAt = investingLastActivity(
            hasOpenPositions: positions,
            hasRestingOrders: resting ?? false,
            now: now());
        if (resting == null &&
            idle >= kSweepDustUsd &&
            (resolveResting || !venueKeepsCash(activeAt, now()))) {
          resting = await _restingOrdersAtVenue();
          if (resting) {
            activeAt = investingLastActivity(
                hasOpenPositions: positions,
                hasRestingOrders: true,
                now: now());
          }
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
          // Only an order queued behind its money or being placed holds
          // the cash; a finished one never does.
          hasPendingIntent: PendingHyperliquidOrderNotifier.isActive(
              _ref.read(pendingHyperliquidOrderProvider)),
          isPlacing:
              placing || _ref.read(placingHyperliquidOrderProvider).isNotEmpty,
          hasOpenTwap: twap,
          isClaiming: closing,
          lastActivityAt: activeAt,
          // What the idle rule stood guard over, for a Rebalance: never
          // cross collateral, never money a resting order fills against.
          hasCrossPosition: cross,
          hasUnreservedRestingOrders: resting ?? false,
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
  Timer? _cashPass;
  OneBalanceVenue? _cashPassVenue;
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
      // A close, cancel, fill or failed order is Investing activity: its
      // cash stays there (Available) and the idle window restarts.
      if (venue == OneBalanceVenue.investing) {
        VenueActivity.note(OneBalanceVenue.investing);
      }
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
    // finishes. Its cash moving (a fill, a deposit, a sale, a fresh read)
    // re-classifies it soon: the header's venue cash is this state's
    // `held` / `dust` / `waiting`, and a bet paid from Predictions cash
    // left them stale until the 3-minute heartbeat.
    ref.listen(
        polymarketTradingProvider.select((s) => (
              cash: s.valueOrNull?.usdcBalance,
              orders: s.valueOrNull?.openOrders.length,
            )), (previous, next) {
      if (previous != null && previous != next) {
        _cashMoved(OneBalanceVenue.predictions);
      }
    });
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
      final landed = _host.noteOrdersChanged(previous, next);
      _sweeper.noteOrders(next);
      // Money landing at a venue is venue cash to classify.
      for (final venue in landed) {
        _cashMoved(venue);
      }
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
      _cashPass?.cancel();
      _sweeper.dispose();
    });
    return const VenueSweeperState();
  }

  /// A venue's cash moved: one pass shortly after, coalesced, so the
  /// header's venue cash follows the venue instead of waiting for the
  /// heartbeat. A timer pass: the rules (rate limit, batching, the idle
  /// rule) decide exactly as on the heartbeat.
  void _cashMoved(OneBalanceVenue venue) {
    _cashPassVenue =
        _cashPass == null || _cashPassVenue == venue ? venue : null;
    _cashPass?.cancel();
    _cashPass = Timer(kVenueCashPassDelay, () {
      _cashPass = null;
      final v = _cashPassVenue;
      _cashPassVenue = null;
      if (_visible) unawaited(trigger('timer', venue: v));
    });
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

  /// The Portfolio's Rebalance: every venue's movable cash home now
  /// ([VenueSweeper.sweepNow], trigger `manual_rebalance`), the idle wait
  /// set aside and every other rule kept. Same rails, same automatic
  /// authorization, same events and Activity rows as any sweep; never a
  /// second move while one is running.
  Future<Map<OneBalanceVenue, RebalanceOutcome>> rebalance() async {
    final out = await _sweeper.sweepNow(trigger: kManualRebalanceTrigger);
    _armDueTimer();
    return out;
  }
}

final venueSweeperProvider =
    NotifierProvider<VenueSweeperNotifier, VenueSweeperState>(
        VenueSweeperNotifier.new);
