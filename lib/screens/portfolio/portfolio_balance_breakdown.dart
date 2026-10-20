// Portfolio cash and position figures, with a review-only Move money entry.
// Opening the movement sheet chooses source, destination and amount; it never
// starts the former whole-balance Rebalance. Existing in-flight Rebalance
// records keep their per-venue progress and landing presentation below.
// Unknown same-wallet readings retain their display cache; that cache never
// authorizes spending.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart' show SpringSimulation, Tolerance;
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:kute/helpers/formatters/polymarket_amount_formatter.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/providers/asset_icon_provider.dart' show kUsdMarkAsset;
import 'package:kute/providers/auth_provider.dart' show sessionUnlockedProvider;
import 'package:kute/providers/hyperliquid_trading_provider.dart'
    show hyperliquidTradingProvider, hyperliquidDisplayTradingProvider;
import 'package:kute/providers/investment_balances_provider.dart'
    show polymarketInvestmentBalances, hyperliquidInvestmentBalances;
import 'package:kute/providers/one_balance_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart'
    show polymarketTradingProvider;
import 'package:kute/providers/portfolio_rebalance_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/providers/unified_balances_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceUnknownProvider;
import 'package:kute/providers/venue_sweeper_provider.dart';
import 'package:kute/screens/portfolio/open_investments_screen.dart'
    show InvestmentsProduct;
import 'package:kute/screens/portfolio/portfolio_figure_tiles.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/money_movement_sheet.dart'
    show showMoneyMovementSheet;
import 'package:kute/screens/shared/kute_motion.dart'
    show RollingFigure, StepsReveal;
import 'package:kute/screens/shared/money_steps_view.dart'
    show MoneyStepsView, moneyStepLines;
import 'package:kute/screens/shared/rubber_band_progress.dart';
import 'package:kute/screens/shared/stale_shimmer.dart';
import 'package:kute/screens/shared/venue_deposit_button.dart'
    show venueMarkAsset;
import 'package:kute/services/one_balance/money_steps.dart';
import 'package:kute/services/one_balance/move_steps.dart' show MoveSteps;
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/rebalance_steps.dart';
import 'package:kute/services/one_balance/sweep_rules.dart'
    show SweepSkipReason, kSweepDustUsd, kVenueMoveMaxAge, venueWithdrawalRowOf;
import 'package:kute/services/venue_total_cache_service.dart';
import 'package:kute/theme/app_theme.dart';

/// A venue's cash as the breakdown counts it: its unreserved cash, the
/// part the sweeper keeps or cannot move ([OneBalanceState.venueCash]) and
/// the part it still owes back ([OneBalanceState.waiting]).
double breakdownVenueCash(OneBalanceState state, OneBalanceVenue venue) {
  final cash = (state.venueCash[venue] ?? 0) + (state.waiting[venue] ?? 0);
  return cash.isFinite && cash > 0 ? cash : 0;
}

/// What a venue holds in positions as the breakdown counts it: its share
/// of the header's Invested ([OneBalanceState.investedByVenue]).
double breakdownVenuePositions(OneBalanceState state, OneBalanceVenue venue) {
  final usd = state.investedByVenue[venue] ?? 0;
  return usd.isFinite && usd > 0 ? usd : 0;
}

/// Below-minimum cash under this is not worth a disabled Rebalance and a
/// line: the few cents the CCTP route keeps back on HyperCore ($0.06)
/// after every Investing move stay there for good.
const double kRebalanceBelowMinimumShownUsd = 0.10;

/// The venues whose cash a Rebalance would leave because it is below the
/// route minimum, when that is the only cash there is (nothing movable).
Set<OneBalanceVenue> rebalanceBelowMinimumVenues(VenueSweeperState sweeper) {
  if (sweeper.movable.values.any((usd) => usd >= kSweepDustUsd)) {
    return const {};
  }
  return {
    for (final e in sweeper.belowMinimum.entries)
      if (e.value >= kRebalanceBelowMinimumShownUsd) e.key,
  };
}

/// How long after a venue's figures move the breakdown reads the venues
/// again ([VenueSweeperNotifier.preview]): one read for a burst of ticks.
const Duration kBreakdownPreviewDebounce = Duration(milliseconds: 300);

/// How long the refreshed figures shimmer at most while the venues'
/// refresh runs.
const Duration kBreakdownRefreshCap = Duration(seconds: 6);

/// The note a venue tile carries about a Rebalance, or null: the cash on
/// its way home (a move running, its Orchestra row pending, or the tap's
/// submit a moment ago), else why it stayed. Pure for the tests.
String? rebalanceNote(
  AppLocalizations l10n, {
  required OneBalanceVenue venue,
  required OneBalanceState balance,
  required VenueSweeperState sweeper,
  required PortfolioRebalanceState rebalance,
  required DateTime now,
}) {
  final outcome = rebalance.outcomeAt(venue, now);
  final kind = outcome?.kind;
  final homeward = balance.inFlight.any((m) =>
      m.kind == InFlightKind.fromVenue && m.venue == venue && m.order == null);
  final submitted = rebalance.at != null &&
      now.difference(rebalance.at!) < kRebalanceMovingGrace;
  final moving = sweeper.sweeping.contains(venue) ||
      ((kind == RebalanceOutcomeKind.moving ||
              kind == RebalanceOutcomeKind.alreadyMoving) &&
          (homeward || (kind == RebalanceOutcomeKind.moving && submitted)));
  if (moving) {
    // Investing → USDB rides CCTP when Orchestra cannot: minutes, not
    // seconds.
    return venue == OneBalanceVenue.investing
        ? l10n.portfolioRebalanceMovingMinutes
        : l10n.portfolioRebalanceMoving;
  }
  if (outcome == null || breakdownVenueCash(balance, venue) < kSweepDustUsd) {
    return null;
  }
  return switch (outcome.kind) {
    RebalanceOutcomeKind.held => switch (outcome.reason) {
        SweepSkipReason.openOrders => l10n.portfolioRebalanceHeldOrders,
        SweepSkipReason.crossPosition => l10n.portfolioRebalanceHeldMargin,
        _ => l10n.portfolioRebalanceNotNow,
      },
    RebalanceOutcomeKind.belowMinimum => l10n.portfolioRebalanceBelowMinimum,
    RebalanceOutcomeKind.notNow => l10n.portfolioRebalanceNotNow,
    _ => null,
  };
}

/// How long a venue's move home usually takes, what its band builds over:
/// Predictions about a minute; Investing, whose route can be CCTP, a few
/// minutes ("Moving to USDB… takes a few minutes").
Duration rebalanceBandExpected(OneBalanceVenue venue) => switch (venue) {
      OneBalanceVenue.predictions => const Duration(minutes: 1),
      OneBalanceVenue.investing => const Duration(minutes: 4),
    };

/// Where a venue's rubber band is in a Rebalance.
enum RebalanceBandPhase {
  /// No Rebalance moved it: no pull.
  rest(0),

  /// The tap: the pass is being sent.
  sending(RubberBandProgress.firstPull),

  /// The pass submitted the move; its row is not listed yet.
  submitted(0.5),

  /// Its Orchestra/CCTP row is listed and pending: on its way.
  onItsWay(0.62),

  /// The row landed in USDB: the snap.
  landed(0),

  /// It did not move after all (held, not now, the row failed): a soft
  /// release.
  released(0);

  const RebalanceBandPhase(this.floor);

  /// The least tension the band holds in this phase (share of full).
  final double floor;

  /// The band is pulling (the move is running).
  bool get pulling => this == sending || this == submitted || this == onItsWay;

  RubberBandOutcome get outcome => switch (this) {
        landed => RubberBandOutcome.success,
        released => RubberBandOutcome.failure,
        _ => RubberBandOutcome.none,
      };
}

/// The last Rebalance tap as its bands need it, kept outside the
/// Portfolio's widgets so a band built again (the Portfolio left and
/// opened again) shows the tension its move has reached.
@immutable
class RebalanceBandSession {
  const RebalanceBandSession({
    required this.startedAt,
    this.pulling = const <OneBalanceVenue>{},
    this.pendingAtTap = const <OneBalanceVenue, Set<String>>{},
    this.knownAtTap = const <String>{},
  });

  /// The tap.
  final DateTime startedAt;

  /// The venues pulled on the tap: cash a Rebalance can move, or a move
  /// home already on its way.
  final Set<OneBalanceVenue> pulling;

  /// The venue moves home already pending at the tap (their row ids):
  /// part of this Rebalance ("already moving").
  final Map<OneBalanceVenue, Set<String>> pendingAtTap;

  /// Every other venue move home listed at the tap: earlier moves, never
  /// this Rebalance's.
  final Set<String> knownAtTap;

  /// The session for a tap at [now] on [rows] and what the sweeper
  /// says it can move.
  factory RebalanceBandSession.tap({
    required DateTime now,
    required VenueSweeperState sweeper,
    required OneBalanceState balance,
    required List<SwapOrder> rows,
    required String? walletId,
  }) {
    final pending = <OneBalanceVenue, Set<String>>{};
    final known = <String>{};
    for (final row in rows) {
      final venue = venueWithdrawalRowOf(row, walletId: walletId);
      if (venue == null) continue;
      if (row.isPending && _fresh(row, now)) {
        (pending[venue] ??= <String>{}).add(row.id);
      } else {
        known.add(row.id);
      }
    }
    return RebalanceBandSession(
      startedAt: now,
      pulling: {
        for (final e in sweeper.movable.entries)
          if (e.value >= kSweepDustUsd) e.key,
        for (final venue in pending.keys)
          if (_homeward(balance, venue)) venue,
      },
      pendingAtTap: pending,
      knownAtTap: known,
    );
  }
}

/// The last Rebalance tap's bands ([RebalanceBandSession]), null before
/// any.
final rebalanceBandSessionProvider =
    StateProvider<RebalanceBandSession?>((_) => null);

bool _fresh(SwapOrder row, DateTime now) =>
    now.millisecondsSinceEpoch - row.timestamp <=
    kVenueMoveMaxAge.inMilliseconds;

bool _homeward(OneBalanceState balance, OneBalanceVenue venue) =>
    balance.inFlight.any((m) =>
        m.kind == InFlightKind.fromVenue &&
        m.venue == venue &&
        m.order == null);

/// Where [venue]'s band is: on the tap while the pass is sent, then the
/// move's own row (listed and pending, then landed), else why it let go.
/// Pure for the tests.
RebalanceBandPhase rebalanceBandPhase({
  required OneBalanceVenue venue,
  required RebalanceBandSession? session,
  required PortfolioRebalanceState rebalance,
  required OneBalanceState balance,
  required VenueSweeperState sweeper,
  required List<SwapOrder> rows,
  required String? walletId,
  required DateTime now,
}) {
  if (session == null) return RebalanceBandPhase.rest;
  final kind = rebalance.outcomes[venue]?.kind;
  final moved = kind == RebalanceOutcomeKind.moving ||
      kind == RebalanceOutcomeKind.alreadyMoving;
  if (!session.pulling.contains(venue) && (rebalance.running || !moved)) {
    // Held, below the minimum, not now, nothing: never pulled.
    return RebalanceBandPhase.rest;
  }
  final latest =
      session.startedAt.add(kRebalanceNoteFor).millisecondsSinceEpoch;
  final mine = [
    for (final row in rows)
      if (venueWithdrawalRowOf(row, walletId: walletId) == venue &&
          ((session.pendingAtTap[venue]?.contains(row.id) ?? false) ||
              (!session.knownAtTap.contains(row.id) &&
                  row.timestamp <= latest)))
        row,
  ];
  final pending = mine.where((r) => r.isPending && _fresh(r, now));
  if (pending.isNotEmpty && _homeward(balance, venue)) {
    return RebalanceBandPhase.onItsWay;
  }
  // Settled, or still pending but its dollars already counted in Dollars
  // (no longer in flight): the money is home.
  if (mine.any((r) => r.isComplete) || pending.isNotEmpty) {
    return RebalanceBandPhase.landed;
  }
  if (rebalance.running) return RebalanceBandPhase.sending;
  if (sweeper.sweeping.contains(venue)) return RebalanceBandPhase.submitted;
  final at = rebalance.at;
  if (kind == RebalanceOutcomeKind.moving &&
      at != null &&
      now.difference(at) < kRebalanceMovingGrace) {
    return RebalanceBandPhase.submitted;
  }
  return RebalanceBandPhase.released;
}

/// The last Rebalance's steps as they stand ([RebalanceSteps.live]: each
/// venue's leg done once its row settled or its money landed, [phases]),
/// or empty once there is nothing to show: no tap, or the tap's notes are
/// down ([kRebalanceNoteFor]) and nothing is still on its way. Pure for
/// the tests.
MoneyStepGraph rebalanceStepsShown({
  required PortfolioRebalanceState rebalance,
  required List<SwapOrder> rows,
  required Map<OneBalanceVenue, RebalanceBandPhase> phases,
  required DateTime now,
}) {
  if (rebalance.steps.isEmpty) return MoneyStepGraph.empty;
  final live = RebalanceSteps.live(rebalance.steps, rows, landed: {
    for (final e in phases.entries)
      if (e.value == RebalanceBandPhase.landed) e.key,
  });
  final at = rebalance.stepsAt;
  final recent = at != null && now.difference(at) < kRebalanceNoteFor;
  // Still on its way, while its row can still be (a row pending longer is
  // a stuck order for Activity).
  final running = live.steps.any((s) => s.status == MoneyStepStatus.running) &&
      (at == null || now.difference(at) < RebalanceStepsStore.keepFor);
  return rebalance.running || running || recent ? live : MoneyStepGraph.empty;
}

/// The tension [phase] holds [elapsed] after the tap (share of full): from
/// the phase's floor, built with the time since the tap toward
/// [RubberBandBusy.defaultCeiling] (two thirds of the way by [expected],
/// never reaching it). Rising with time and with every phase, so it never
/// goes back while the move runs. Pure for the tests.
double rebalanceBandProgress(RebalanceBandPhase phase, Duration elapsed,
    {required Duration expected}) {
  if (!phase.pulling) return 0;
  return rubberBandEasedProgress(phase.floor, elapsed, expected: expected);
}

/// The breakdown: Dollars, then the venues on the account ([trading],
/// [predictions]: the venues the shell draws a tab for).
class PortfolioBalanceBreakdown extends ConsumerStatefulWidget {
  const PortfolioBalanceBreakdown({
    super.key,
    required this.trading,
    required this.predictions,
  });

  final bool trading;
  final bool predictions;

  @override
  ConsumerState<PortfolioBalanceBreakdown> createState() =>
      _PortfolioBalanceBreakdownState();
}

class _PortfolioBalanceBreakdownState
    extends ConsumerState<PortfolioBalanceBreakdown> {
  /// The venues' refresh on open is running: their figures shimmer.
  bool _refreshing = false;
  Timer? _previewSoon;

  /// How many venues of the current Rebalance had landed at the last
  /// build, and for which tap (null before the first build: a landing
  /// from before the Portfolio opened is never replayed).
  int? _landed;
  DateTime? _landedFor;

  /// The money arrivals the Dollars column has caught.
  int _arrivals = 0;

  @override
  void initState() {
    super.initState();
    // Right away, from what the app holds: no frame waits on a read.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _preview();
      unawaited(_refresh());
    });
  }

  @override
  void dispose() {
    _previewSoon?.cancel();
    super.dispose();
  }

  /// The venues read for the sweeper now: their cash and what a
  /// Rebalance could move ([VenueSweeperNotifier.preview]).
  void _preview() {
    unawaited(ref
        .read(venueSweeperProvider.notifier)
        .preview()
        .then((_) {}, onError: (_) {}));
  }

  void _previewAfterChange() {
    _previewSoon?.cancel();
    _previewSoon = Timer(kBreakdownPreviewDebounce, () {
      _previewSoon = null;
      if (mounted) _preview();
    });
  }

  /// Both venues' figures fetched again, as their pull-to-refresh does,
  /// the refreshed figures shimmering until they land.
  Future<void> _refresh() async {
    final runs = <Future<void>>[
      if (widget.predictions && ref.exists(polymarketTradingProvider))
        ref.read(polymarketTradingProvider.notifier).refresh(),
      if (widget.trading && ref.exists(hyperliquidTradingProvider))
        ref.read(hyperliquidTradingProvider.notifier).refresh(),
    ];
    if (runs.isEmpty) return;
    setState(() => _refreshing = true);
    try {
      await Future.wait(runs).timeout(kBreakdownRefreshCap);
    } catch (_) {
      // A slow or failed read keeps the last figures; the venues' own
      // polls carry on.
    }
    if (!mounted) return;
    setState(() => _refreshing = false);
    _preview();
  }

  @override
  Widget build(BuildContext context) {
    // A venue's figures moving (a fill, a deposit, a fresh read), a move
    // listed or landing, the lock: read the venues again, at once.
    ref.listen(unifiedVenueBalancesProvider, (_, __) => _previewAfterChange());
    ref.listen(
        swapOrdersProvider
            .select((rows) => rows.where((r) => r.isPending).length),
        (_, __) => _previewAfterChange());
    ref.listen(sessionUnlockedProvider, (_, __) => _previewAfterChange());

    final l10n = context.l10n;
    final balance = ref.watch(oneBalanceProvider);
    final sweeper = ref.watch(venueSweeperProvider);
    final rebalance = ref.watch(portfolioRebalanceProvider);
    final visible = ref.watch(settingsProvider.select((s) => s.balanceVisible));
    // What open BUY orders reserve at Predictions: part of its Positions,
    // named under them.
    final reserved = widget.predictions
        ? ref.watch(polymarketTradingProvider.select((s) {
            final pm = s.valueOrNull;
            if (pm == null) return 0.0;
            final committed =
                polymarketInvestmentBalances(state: pm, orders: pm.openOrders)
                    .committed;
            return committed != null && committed.isFinite && committed > 0
                ? committed
                : 0.0;
          }))
        : 0.0;
    String amount(double usd) =>
        visible ? formatPolyFiatForced(ref, usd) : '••••••';
    final now = DateTime.now();

    final dollars = balance.dollarsUsd;
    final investing = breakdownVenueCash(balance, OneBalanceVenue.investing);
    final predictionsCash =
        breakdownVenueCash(balance, OneBalanceVenue.predictions);

    // The rubber bands: each venue's move home is its own band.
    final session = ref.watch(rebalanceBandSessionProvider);
    final rows = ref.watch(swapOrdersProvider);
    final walletId =
        ref.watch(settingsProvider.select((s) => s.activeWalletId));
    RebalanceBandPhase phaseOf(OneBalanceVenue venue) => rebalanceBandPhase(
        venue: venue,
        session: session,
        rebalance: rebalance,
        balance: balance,
        sweeper: sweeper,
        rows: rows,
        walletId: walletId,
        now: now);
    final phases = {
      if (widget.trading)
        OneBalanceVenue.investing: phaseOf(OneBalanceVenue.investing),
      if (widget.predictions)
        OneBalanceVenue.predictions: phaseOf(OneBalanceVenue.predictions),
    };
    // Dollars catch each landing once, as it happens.
    final landed =
        phases.values.where((p) => p == RebalanceBandPhase.landed).length;
    if (_landed != null &&
        _landedFor == session?.startedAt &&
        landed > _landed!) {
      _arrivals++;
    }
    _landed = landed;
    _landedFor = session?.startedAt;

    // The tap's steps under the button: one line per venue going home.
    final steps = rebalanceStepsShown(
        rebalance: rebalance, rows: rows, phases: phases, now: now);
    final stepLines = moneyStepLines(l10n, steps, amount);
    bool hasLine(OneBalanceVenue venue) => steps.steps.any((s) =>
        s.id == MoveSteps.legId(venue) && s.status != MoneyStepStatus.skipped);

    String? note(OneBalanceVenue venue) {
      final line = rebalanceNote(l10n,
          venue: venue,
          balance: balance,
          sweeper: sweeper,
          rebalance: rebalance,
          now: now);
      // A sweep minimum does not disable choosing another source/route.
      // Retain that note only as the result of an already-started move.
      if (line == l10n.portfolioRebalanceBelowMinimum &&
          !rebalance.outcomes.containsKey(venue)) {
        return null;
      }
      final moving = line == l10n.portfolioRebalanceMoving ||
          line == l10n.portfolioRebalanceMovingMinutes;
      // Its row landed: home, nothing on its way any more. Or its step
      // under the button says it: never twice.
      if (moving &&
          (phases[venue] == RebalanceBandPhase.landed || hasLine(venue))) {
        return null;
      }
      return line;
    }

    // This is a review entry, never the old "move every venue home" action.
    // Keep existing in-flight presentation, but a new tap only opens choices.
    final button = RubberBandBusy(
      busy: rebalance.running,
      expected: kRebalanceSendExpected,
      child: AppButton(
        key: const ValueKey('portfolio-move-money'),
        text: l10n.moveTransfer,
        variant: AppButtonVariant.secondary,
        compact: true,
        isLoading: rebalance.running,
        onPressed: rebalance.running
            ? null
            : () {
                unawaited(showMoneyMovementSheet(context));
              },
      ),
    );

    Widget band(OneBalanceVenue venue, Widget tile) => _VenueBand(
          key: ValueKey('portfolio-band-${venue.name}'),
          phase: phases[venue] ?? RebalanceBandPhase.rest,
          startedAt: session?.startedAt,
          expected: rebalanceBandExpected(venue),
          child: tile,
        );

    final displayHl = widget.trading && !balance.investingKnown
        ? ref.watch(hyperliquidDisplayTradingProvider).valueOrNull
        : null;
    final cachedHl = displayHl == null
        ? null
        : hyperliquidInvestmentBalances(state: displayHl, spotPrices: const {});
    _Figure venueFigure(String part, double usd,
        {required bool known, double? fallback, bool refresh = true}) {
      final figure = resolveVenueTotal(
          walletId: walletId,
          venue: 'portfolio_$part',
          fresh: known ? usd : null);
      final value = figure.value ?? fallback;
      return value == null
          ? const _Figure('—')
          : _Figure(amount(value), stale: (refresh && _refreshing) || !known);
    }

    return Column(
      key: const ValueKey('portfolio-balance-breakdown'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        PortfolioTileRow(
          key: const ValueKey('portfolio-balance-row'),
          children: [
            _ArrivalCatch(
              key: const ValueKey('portfolio-band-dollars'),
              arrivals: _arrivals,
              child: _BalanceTile(
                key: const ValueKey('portfolio-balance-dollars'),
                id: 'dollars',
                asset: kUsdMarkAsset,
                name: l10n.portfolioBalanceDollars,
                // Not confirmed by the SDK yet (its answer has no dollar
                // entry while the ledger holds dollars): the ledger's
                // figure, dimmed and sweeping, never a confident number.
                available: venueFigure('dollars', dollars,
                    refresh: false,
                    known: balance.dollarsKnown &&
                        !ref.watch(usdBalanceUnknownProvider)),
              ),
            ),
            if (widget.trading)
              band(
                  OneBalanceVenue.investing,
                  _BalanceTile(
                    key: const ValueKey('portfolio-balance-investing'),
                    id: 'investing',
                    asset: venueMarkAsset(InvestmentsProduct.trading),
                    name: l10n.trading,
                    available: venueFigure('investing_cash', investing,
                        known: balance.investingKnown,
                        fallback: cachedHl?.available),
                    positions: venueFigure(
                        'investing_positions',
                        breakdownVenuePositions(
                            balance, OneBalanceVenue.investing),
                        known: balance.investingKnown,
                        fallback: cachedHl?.portfolio),
                    footer: [
                      if (note(OneBalanceVenue.investing) case final line?)
                        line,
                    ],
                  )),
            if (widget.predictions)
              band(
                  OneBalanceVenue.predictions,
                  _BalanceTile(
                    key: const ValueKey('portfolio-balance-predictions'),
                    id: 'predictions',
                    asset: venueMarkAsset(InvestmentsProduct.predictions),
                    name: l10n.predictions,
                    available: venueFigure('predictions_cash', predictionsCash,
                        known: balance.predictionsKnown),
                    positions: venueFigure(
                        'predictions_positions',
                        breakdownVenuePositions(
                            balance, OneBalanceVenue.predictions),
                        known: balance.predictionsKnown),
                    reserved: reserved >= kSweepDustUsd
                        ? l10n.investingInOpenOrders(amount(reserved))
                        : null,
                    footer: [
                      if (note(OneBalanceVenue.predictions) case final line?)
                        line,
                    ],
                  )),
          ],
        ),
        SizedBox(height: 12.h),
        button,
        // The steps grow in under the button, never popping in.
        StepsReveal(
          child: stepLines.isNotEmpty
              ? Align(
                  key: const ValueKey('portfolio-rebalance-steps'),
                  alignment: Alignment.centerLeft,
                  // Each venue's band already plays its landing.
                  child: MoneyStepsView(
                      lines: stepLines,
                      graph: steps,
                      money: amount,
                      haptics: false),
                )
              : null,
        ),
        SizedBox(height: 12.h),
      ],
    );
  }
}

/// How long a Rebalance's pass usually takes to send: the button's busy
/// band builds over it.
const Duration kRebalanceSendExpected = Duration(seconds: 2);

/// A venue's column in its Rebalance band: [RubberBandProgress] at the
/// tension [phase] holds, built with the time since the tap ([startedAt],
/// wall clock, so a band built again picks up where the move is) on this
/// widget's own ticker while it pulls. The pull is felt as every band's
/// is ([RubberBandHaptics]: the rumble and the ratchet, the heartbeat on
/// a long wait), and the landing with the whoosh and the snap.
class _VenueBand extends StatefulWidget {
  const _VenueBand({
    super.key,
    required this.phase,
    required this.startedAt,
    required this.expected,
    required this.child,
  });

  final RebalanceBandPhase phase;
  final DateTime? startedAt;
  final Duration expected;
  final Widget child;

  @override
  State<_VenueBand> createState() => _VenueBandState();
}

class _VenueBandState extends State<_VenueBand>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);

  /// The time since the tap when this pull was first built here.
  Duration _base = Duration.zero;

  /// The ticker's time since then.
  Duration _ticked = Duration.zero;

  /// The tension last drawn: the band is rebuilt a step at a time.
  double _drawn = 0;

  bool _reduce = false;

  double get _progress => rebalanceBandProgress(widget.phase, _base + _ticked,
      expected: widget.expected);

  @override
  void initState() {
    super.initState();
    if (widget.phase.pulling) _latch();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _syncTicker();
  }

  @override
  void didUpdateWidget(_VenueBand oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.phase.pulling &&
        (!oldWidget.phase.pulling || oldWidget.startedAt != widget.startedAt)) {
      _latch();
    }
    _syncTicker();
  }

  /// A pull starts here: how far along its move already is.
  void _latch() {
    final at = widget.startedAt;
    final since = at == null ? Duration.zero : DateTime.now().difference(at);
    _base = since.isNegative ? Duration.zero : since;
    _ticked = Duration.zero;
    if (_ticker.isActive) _ticker.stop();
  }

  /// The build's clock runs only while the band pulls, never under
  /// Reduce Motion; the ticker is muted while covered.
  void _syncTicker() {
    final run = widget.phase.pulling && !_reduce;
    if (run && !_ticker.isActive) {
      _ticker.start();
    } else if (!run && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    _ticked = elapsed;
    if (_progress - _drawn >= 0.01) setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _drawn = _progress;
    return RubberBandProgress(
      progress: _drawn,
      outcome: widget.phase.outcome,
      haptic: true,
      child: widget.child,
    );
  }
}

/// The Dollars column catching money as it lands: one small spring dip and
/// back ([RubberBandProgress.snapSpring]) each time [arrivals] grows.
/// Silent (the landing venue's thud is the one felt); still under Reduce
/// Motion, covered or in the background; nothing ticks at rest.
class _ArrivalCatch extends StatefulWidget {
  const _ArrivalCatch({super.key, required this.arrivals, required this.child});

  final int arrivals;
  final Widget child;

  /// The catch's kick, in column heights per second: a dip of about 2.5%
  /// of the column.
  static const double kick = 1.1;

  @override
  State<_ArrivalCatch> createState() => _ArrivalCatchState();
}

class _ArrivalCatchState extends State<_ArrivalCatch>
    with SingleTickerProviderStateMixin {
  late final AnimationController _dip =
      AnimationController.unbounded(vsync: this)
        ..addStatusListener((status) {
          // Settled: exactly at rest, no sub-pixel offset left behind.
          if (status == AnimationStatus.completed) _dip.value = 0;
        });

  @override
  void didUpdateWidget(_ArrivalCatch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.arrivals > oldWidget.arrivals && RubberBand.animates(context)) {
      _dip.animateWith(SpringSimulation(
          RubberBandProgress.snapSpring, _dip.value, 0, _ArrivalCatch.kick,
          tolerance: const Tolerance(distance: 1e-4, velocity: 1e-3)));
    }
  }

  @override
  void dispose() {
    _dip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _dip,
        child: widget.child,
        // Translated, never scaled: the figures stay crisp.
        builder: (context, child) => FractionalTranslation(
          translation: Offset(0, _dip.value),
          child: child,
        ),
      );
}

/// A figure as a tile shows it: the text, and whether it is still being
/// refreshed.
class _Figure {
  const _Figure(this.text, {this.stale = false});

  final String text;
  final bool stale;
}

/// One part of the balance: its mark and name, its Available cash, then
/// one small line ("Available" for Dollars, the venue's Positions), then
/// one quiet line per thing there is to say.
class _BalanceTile extends StatelessWidget {
  const _BalanceTile({
    super.key,
    required this.id,
    required this.asset,
    required this.name,
    required this.available,
    this.positions,
    this.reserved,
    this.footer = const [],
  });

  /// The part's name in the figures' keys ("dollars", "investing").
  final String id;
  final String asset;
  final String name;
  final _Figure available;

  /// The venue's positions; null for Dollars, which hold none.
  final _Figure? positions;

  /// What open BUY orders reserve ("$4.00 in open orders"): an amount,
  /// so one line scaled to the column, never wrapped.
  final String? reserved;

  /// Notes about a Rebalance: words only, so they wrap.
  final List<String> footer;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final caption = portfolioTileCaptionStyle(c);

    // Live: a new figure rolls the digits that changed; while the venue
    // refreshes it is dimmed with the skeleton's sweep.
    Widget live(_Figure figure, TextStyle style) => StaleShimmer(
          stale: figure.stale,
          child: RollingFigure(
              text: figure.text,
              style: figure.stale
                  ? style.copyWith(color: c.textSecondary)
                  : style),
        );

    return PortfolioTile(children: [
      Row(
        children: [
          SvgPicture.asset(asset, width: 16.w, height: 16.w),
          SizedBox(width: 6.w),
          Flexible(
            child: PortfolioTileFit(
              child: Text(name,
                  maxLines: 1,
                  softWrap: false,
                  style: caption.copyWith(
                      color: c.textSecondary,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
      SizedBox(height: 6.h),
      Semantics(
        label: l10n.available,
        child: PortfolioTileFigure(
          available.text,
          key: ValueKey('portfolio-balance-$id-available'),
          child: live(available, PortfolioTileFigure.styleOf(context)),
        ),
      ),
      SizedBox(height: 2.h),
      if (positions case final held?)
        PortfolioTileFit(
          key: ValueKey('portfolio-balance-$id-positions'),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.ledgerPositionsTitle, style: caption),
              SizedBox(width: 4.w),
              live(
                  held,
                  caption.copyWith(
                      color: c.textSecondary, fontWeight: FontWeight.w600)),
            ],
          ),
        )
      else
        PortfolioTileLabel(l10n.available),
      if (reserved case final line?) ...[
        SizedBox(height: 2.h),
        PortfolioTileLabel(line),
      ],
      for (final line in footer) ...[
        SizedBox(height: 4.h),
        Text(line, style: caption),
      ],
    ]);
  }
}
