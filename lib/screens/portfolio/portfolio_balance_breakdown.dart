// lib/screens/portfolio/portfolio_balance_breakdown.dart
//
// The top of the Portfolio (founder requests, October 2026): the
// Investments balance part by part, side by side, with one Rebalance
// under it.
//
//   * Dollars — the spending account's USDB (the USDB coin): Available;
//   * Investing — Hyperliquid (its mark): Available cash, and Positions
//     (margin and P&L, spot holdings: the venue's share of the header's
//     Invested);
//   * Predictions — Polymarket (its mark): Available cash, and Positions
//     (open positions at their value, combos, and the cash open BUY
//     orders reserve, named under it: "$4.00 in open orders").
//
// One row of three equal tiles (portfolio_figure_tiles.dart), the same
// tiles as the statistics row under the chart. The figures are the
// one-balance state's (`oneBalanceProvider`): Dollars plus every
// Available and every Positions figure is the header's total less what is
// on a rail, and the Positions figures add up to its Invested.
//
// Opening the Portfolio draws the tiles at once from what the app holds,
// refreshes both venues (the calls their pull-to-refresh makes) with the
// refreshed figures shimmering ([StaleShimmer]) meanwhile, and reads the
// venues for the sweeper right away ([VenueSweeperNotifier.preview]) and
// again whenever their figures move: what each venue's cash is and what a
// Rebalance could move never wait on the sweeper's next pass (it runs
// every three minutes, so the cash and the button used to take minutes to
// show).
//
// Rebalance, full width under the row, brings every venue's movable cash
// home to USDB now (portfolio_rebalance_provider.dart: one manual pass of
// the venue sweeper). It is enabled while a venue has cash a Rebalance can
// move (the sweeper's `movable`, at or above the route minimum) and busy
// while its pass runs. When the only cash at the venues is below the
// route minimum it stays on screen, disabled, and that venue's tile says
// "Below the minimum to move"; with nothing to move at all there is no
// button. After a tap each venue's tile says in one line what is
// happening to its cash: on its way to USDB (Investing's route takes
// minutes), or why it stayed.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:kute/helpers/formatters/polymarket_amount_formatter.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/asset_icon_provider.dart' show kUsdMarkAsset;
import 'package:kute/providers/auth_provider.dart' show sessionUnlockedProvider;
import 'package:kute/providers/hyperliquid_trading_provider.dart'
    show hyperliquidTradingProvider;
import 'package:kute/providers/investment_balances_provider.dart'
    show polymarketInvestmentBalances;
import 'package:kute/providers/one_balance_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart'
    show polymarketTradingProvider;
import 'package:kute/providers/portfolio_rebalance_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/providers/unified_balances_provider.dart';
import 'package:kute/providers/venue_sweeper_provider.dart';
import 'package:kute/screens/portfolio/open_investments_screen.dart'
    show InvestmentsProduct;
import 'package:kute/screens/portfolio/portfolio_figure_tiles.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_motion.dart' show RollingFigure;
import 'package:kute/screens/shared/portfolio_position_card.dart'
    show portfolioCardCaptionStyle;
import 'package:kute/screens/shared/stale_shimmer.dart';
import 'package:kute/screens/shared/venue_deposit_button.dart'
    show venueMarkAsset;
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/sweep_rules.dart'
    show SweepSkipReason, kSweepDustUsd;
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
    final below = rebalanceBelowMinimumVenues(sweeper);

    String? note(OneBalanceVenue venue) =>
        rebalanceNote(l10n,
            venue: venue,
            balance: balance,
            sweeper: sweeper,
            rebalance: rebalance,
            now: now) ??
        (below.contains(venue) ? l10n.portfolioRebalanceBelowMinimum : null);

    final canMove = sweeper.movable.values.any((usd) => usd >= kSweepDustUsd);
    final button = canMove || rebalance.running || below.isNotEmpty
        ? AppButton(
            key: const ValueKey('portfolio-rebalance'),
            text: l10n.portfolioRebalance,
            variant: AppButtonVariant.secondary,
            compact: true,
            isLoading: rebalance.running,
            onPressed: rebalance.running || !canMove
                ? null
                : () {
                    HapticFeedback.lightImpact();
                    ref.read(portfolioRebalanceProvider.notifier).rebalance(
                          dollarsUsd: dollars,
                          investingUsd: investing,
                          predictionsUsd: predictionsCash,
                        );
                  },
          )
        : null;

    _Figure venueFigure(double usd, {required bool known}) => known
        ? _Figure(amount(usd), stale: _refreshing)
        // Never read at all: a dash, never a guess.
        : const _Figure('—');

    return Column(
      key: const ValueKey('portfolio-balance-breakdown'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        PortfolioTileRow(
          key: const ValueKey('portfolio-balance-row'),
          children: [
            _BalanceTile(
              key: const ValueKey('portfolio-balance-dollars'),
              asset: kUsdMarkAsset,
              name: l10n.portfolioBalanceDollars,
              figures: [(l10n.available, _Figure(amount(dollars)))],
            ),
            if (widget.trading)
              _BalanceTile(
                key: const ValueKey('portfolio-balance-investing'),
                asset: venueMarkAsset(InvestmentsProduct.trading),
                name: l10n.trading,
                figures: [
                  (
                    l10n.available,
                    venueFigure(investing, known: balance.investingKnown)
                  ),
                  (
                    l10n.ledgerPositionsTitle,
                    venueFigure(
                        breakdownVenuePositions(
                            balance, OneBalanceVenue.investing),
                        known: balance.investingKnown)
                  ),
                ],
                footer: [
                  if (note(OneBalanceVenue.investing) case final line?) line,
                ],
              ),
            if (widget.predictions)
              _BalanceTile(
                key: const ValueKey('portfolio-balance-predictions'),
                asset: venueMarkAsset(InvestmentsProduct.predictions),
                name: l10n.predictions,
                figures: [
                  (
                    l10n.available,
                    venueFigure(predictionsCash,
                        known: balance.predictionsKnown)
                  ),
                  (
                    l10n.ledgerPositionsTitle,
                    venueFigure(
                        breakdownVenuePositions(
                            balance, OneBalanceVenue.predictions),
                        known: balance.predictionsKnown)
                  ),
                ],
                footer: [
                  if (reserved >= kSweepDustUsd)
                    l10n.investingInOpenOrders(amount(reserved)),
                  if (note(OneBalanceVenue.predictions) case final line?) line,
                ],
              ),
          ],
        ),
        if (button != null) ...[
          SizedBox(height: 12.h),
          button,
        ],
        SizedBox(height: 12.h),
      ],
    );
  }
}

/// A figure as a tile shows it: the text, and whether it is still being
/// refreshed.
class _Figure {
  const _Figure(this.text, {this.stale = false});

  final String text;
  final bool stale;
}

/// One part of the balance: its mark and name, then each figure under its
/// label, then one quiet line per thing there is to say.
class _BalanceTile extends StatelessWidget {
  const _BalanceTile({
    super.key,
    required this.asset,
    required this.name,
    required this.figures,
    this.footer = const [],
  });

  final String asset;
  final String name;
  final List<(String, _Figure)> figures;
  final List<String> footer;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final caption = portfolioCardCaptionStyle(c);
    return PortfolioTile(children: [
      Row(
        children: [
          SvgPicture.asset(asset, width: 18.w, height: 18.w),
          SizedBox(width: 6.w),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(name,
                  style: caption.copyWith(
                      color: c.textPrimary, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
      for (final (label, figure) in figures) ...[
        SizedBox(height: 10.h),
        PortfolioTileStat(
          label: label,
          figure: PortfolioTileFigure(
            figure.text,
            // Live: a new figure rolls the digits that changed; while the
            // venue refreshes it is dimmed with the skeleton's sweep.
            child: StaleShimmer(
              stale: figure.stale,
              child: RollingFigure(
                  text: figure.text,
                  style: PortfolioTileFigure.styleOf(
                      context, figure.stale ? c.textSecondary : null)),
            ),
          ),
        ),
      ],
      for (final line in footer) ...[
        SizedBox(height: 6.h),
        Text(line, style: caption.copyWith(fontSize: 12.sp)),
      ],
    ]);
  }
}
