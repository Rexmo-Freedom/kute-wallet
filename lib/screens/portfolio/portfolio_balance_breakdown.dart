// lib/screens/portfolio/portfolio_balance_breakdown.dart
//
// The top of the Portfolio (founder request, October 2026): the
// Investments balance's cash, part by part, with one Rebalance.
//
//   * Dollars — the spending account's USDB (the USDB coin);
//   * Investing — Hyperliquid's cash (the Hyperliquid mark);
//   * Predictions — Polymarket's cash, with what open orders reserve
//     ("$4.00 in open orders") (the Polymarket mark).
//
// Cash only: the positions are the donut's and the Positions list's.
// Each part is the Portfolio's own card (HlPortfolioCard with a mark in
// the logo's place, the slot it keeps for the account's balances), live
// on `oneBalanceProvider`.
//
// Rebalance, the action under the Dollars card, brings every venue's
// movable cash home to USDB now (portfolio_rebalance_provider.dart: one
// manual pass of the venue sweeper). It is drawn only while a venue has
// cash a Rebalance can move (the sweeper's `movable`, at or above the
// route minimum), and while its pass runs. After a tap each venue card
// says in one line what is happening to its cash: on its way to USDB
// (Investing's route takes minutes), or why it stayed.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:kute/helpers/formatters/polymarket_amount_formatter.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/asset_icon_provider.dart' show kUsdMarkAsset;
import 'package:kute/providers/investment_balances_provider.dart'
    show polymarketInvestmentBalances;
import 'package:kute/providers/one_balance_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart'
    show polymarketTradingProvider;
import 'package:kute/providers/portfolio_rebalance_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/venue_sweeper_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_portfolio_card.dart';
import 'package:kute/screens/portfolio/open_investments_screen.dart'
    show InvestmentsProduct;
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/portfolio_position_card.dart';
import 'package:kute/screens/shared/venue_deposit_button.dart'
    show venueMarkAsset;
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/sweep_rules.dart'
    show SweepSkipReason, kSweepDustUsd;

/// A venue's cash as the breakdown counts it: its unreserved cash, the
/// part the sweeper keeps or cannot move ([OneBalanceState.venueCash]) and
/// the part it still owes back ([OneBalanceState.waiting]).
double breakdownVenueCash(OneBalanceState state, OneBalanceVenue venue) {
  final cash = (state.venueCash[venue] ?? 0) + (state.waiting[venue] ?? 0);
  return cash.isFinite && cash > 0 ? cash : 0;
}

/// The note a venue card carries about a Rebalance, or null: the cash on
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
class PortfolioBalanceBreakdown extends ConsumerWidget {
  const PortfolioBalanceBreakdown({
    super.key,
    required this.trading,
    required this.predictions,
  });

  final bool trading;
  final bool predictions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final balance = ref.watch(oneBalanceProvider);
    final sweeper = ref.watch(venueSweeperProvider);
    final rebalance = ref.watch(portfolioRebalanceProvider);
    final visible = ref.watch(settingsProvider.select((s) => s.balanceVisible));
    // What open BUY orders reserve at Predictions: its cash, counted in
    // the row and named under it.
    final reserved = predictions
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
        breakdownVenueCash(balance, OneBalanceVenue.predictions) + reserved;

    String? note(OneBalanceVenue venue) => rebalanceNote(l10n,
        venue: venue,
        balance: balance,
        sweeper: sweeper,
        rebalance: rebalance,
        now: now);

    final canMove = sweeper.movable.values.any((usd) => usd >= kSweepDustUsd);
    final button = canMove || rebalance.running
        ? AppButton(
            key: const ValueKey('portfolio-rebalance'),
            text: l10n.portfolioRebalance,
            variant: AppButtonVariant.secondary,
            compact: true,
            isLoading: rebalance.running,
            onPressed: rebalance.running
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

    return Column(
      key: const ValueKey('portfolio-balance-breakdown'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _BalanceCard(
          key: const ValueKey('portfolio-balance-dollars'),
          asset: kUsdMarkAsset,
          name: l10n.portfolioBalanceDollars,
          caption: 'USDB',
          value: amount(dollars),
          action: button,
        ),
        if (trading)
          _BalanceCard(
            key: const ValueKey('portfolio-balance-investing'),
            asset: venueMarkAsset(InvestmentsProduct.trading),
            name: l10n.trading,
            caption: 'Hyperliquid',
            value: balance.investingKnown ? amount(investing) : '—',
            footer: [
              if (note(OneBalanceVenue.investing) case final line?) line,
            ],
          ),
        if (predictions)
          _BalanceCard(
            key: const ValueKey('portfolio-balance-predictions'),
            asset: venueMarkAsset(InvestmentsProduct.predictions),
            name: l10n.predictions,
            caption: 'Polymarket',
            value: balance.predictionsKnown ? amount(predictionsCash) : '—',
            footer: [
              if (note(OneBalanceVenue.predictions) case final line?) line,
              if (reserved >= kSweepDustUsd)
                l10n.investingInOpenOrders(amount(reserved)),
            ],
          ),
      ],
    );
  }
}

/// One part of the balance: the Portfolio's card with the balance's mark
/// in the logo's place, its name over where it lives, its cash on the
/// right, and one quiet line when there is something to say.
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    super.key,
    required this.asset,
    required this.name,
    required this.caption,
    required this.value,
    this.footer = const [],
    this.action,
  });

  final String asset;
  final String name;
  final String caption;
  final String value;
  final List<String> footer;
  final Widget? action;

  @override
  Widget build(BuildContext context) => HlPortfolioCard(
        coin: '',
        name: name,
        caption: caption,
        leading:
            SvgPicture.asset(asset, width: 36, height: 36, fit: BoxFit.contain),
        trailing: PortfolioCardValue(value: value),
        footer: footer,
        action: action,
      );
}
