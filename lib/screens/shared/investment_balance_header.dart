import 'package:kute/screens/shared/money_steps_view.dart' show moneyStepLine;
import 'package:kute/screens/shared/kute_dog_scenes.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/helpers/formatters/polymarket_amount_formatter.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/investment_balances_provider.dart';
import 'package:kute/providers/one_balance_provider.dart';
import 'package:kute/providers/pending_pool_deposits_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceUnknownProvider;
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/venue_total_cache_service.dart';
import 'package:kute/screens/portfolio/open_investments_screen.dart';
import 'package:kute/screens/shared/kute_motion.dart' show KutePressScale;
import 'package:kute/screens/shared/pending_deposit_line.dart';
import 'package:kute/screens/shared/pool_balance_header.dart';
import 'package:kute/screens/shared/portfolio_arrow_glyph.dart';
import 'package:kute/screens/shared/portfolio_builder/builder_legs_provider.dart';
import 'package:kute/screens/shared/portfolio_builder/portfolio_builder_screen.dart';
import 'package:kute/screens/shared/investment_funding.dart';
import 'package:kute/screens/shared/venue_deposit_button.dart';
import 'package:kute/theme/app_theme.dart';

/// Only discovery is replaced. The balance, withdrawal and portfolio doors
/// remain available above this notice under their independent capabilities.

/// The portfolio builder (and combos through it) is not exposed yet
/// (user decision 5 October 2026). Its code stays; only the entry is hidden.
const bool kShowPortfolioBuilder = false;

class InvestmentDiscoveryNotice extends ConsumerWidget {
  const InvestmentDiscoveryNotice({super.key, required this.capability});
  final String capability;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: KuteDogNotHere(
                width: 220,
                ink: context.colors.textPrimary,
                accent: context.colors.accent,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              ref
                  .watch(runtimeCapabilitiesProvider)
                  .decision(capability)
                  .message,
              textAlign: TextAlign.center,
              style:
                  TextStyle(fontSize: 16, color: context.colors.textSecondary),
            ),
          ],
        ),
      );
}

/// The pool hero. Two modes:
///
///   * PER VENUE (the default): one venue's total with its cash/position
///     split, the venue's Deposit button under it, and the in-flight
///     Orchestra lines of that venue. The Ledger venue screens and a
///     venue browser standing on its own use this.
///   * ONE BALANCE ([oneBalance]): the Investments tab's hero, reading
///     [oneBalanceProvider]. No title over it (owner decision October
///     2026): the total stands alone, Dollars plus the open positions of
///     every venue, the portfolio glyph (an arrow with a pie badge, built
///     like the hub's + gear) right after it
///     ([PortfolioArrowGlyph]); under it "Available $X · Invested $Y"
///     (Available: Dollars plus the venues' unreserved cash; Invested:
///     positions, reserved order cash and pending fills; back on
///     27 October 2026, founder). While anything is on a rail that line
///     gives way to the in-flight lines, in order:
///     the order money
///     on a rail is for ("Placing $5 on Yes · Lakers"), incoming from
///     outside, unavailable until balancing completes (venue cash the
///     sweeper still owes back). Money on a rail between the person's
///     own accounts for no order (a sweep home) stays in the total with
///     no line: it is plumbing. Venue dust
///     below every route minimum is no line at all: it is part of the
///     total like the rest of the venues' cash. No Deposit button:
///     money only reaches a venue through an order. The whole block, the
///     total and the line under it, is one tap ([onTap]: the Portfolio),
///     with the cards' press feedback ([KutePressScale]).
///
/// [showDepositButton]: the venue's Deposit button under the balance (the
/// market browsers). The Portfolio screen hides it; its dock carries
/// Deposit there. Ignored in one-balance mode.
class InvestmentBalanceHeader extends ConsumerWidget {
  final InvestmentsProduct product;
  final bool showDepositButton;
  final bool oneBalance;

  /// One balance only: what tapping the balance block opens (the
  /// Portfolio). Null: the block is not tappable and wears no chevron.
  final VoidCallback? onTap;

  const InvestmentBalanceHeader({
    super.key,
    required this.product,
    this.showDepositButton = true,
    this.oneBalance = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (oneBalance) return _buildOneBalance(context, ref);
    final predictions = product == InvestmentsProduct.predictions;
    final balances = ref.watch(investmentBalancesProvider(product));
    final visible = ref.watch(settingsProvider.select((s) => s.balanceVisible));
    String amount(double? value) => !visible
        ? '••••••'
        : value == null
            ? '—'
            : formatPolyAmount(ref, value);
    final pending = ref.watch(predictions
        ? pendingPredictionsDepositUsdProvider
        : pendingTradingDepositUsdProvider);
    final leaving = ref.watch(predictions
        ? pendingPredictionsWithdrawalUsdProvider
        : pendingTradingWithdrawalUsdProvider);

    // Both pools lead with the TOTAL and split it underneath (owner
    // decision). Investing led with spendable cash alone, which read as
    // the whole account and quietly left every open position out of the
    // figure at the top of the screen.
    final hasBalance = (balances.total ?? 0) > 0;
    // Never a bare dash (owner: "this looks bad"). Without a fresh total
    // (the account still on its way, or a read that failed) the header
    // shows this wallet's last known one, dimmed, and the next sync or
    // pull-to-refresh replaces it; with nothing known yet, a skeleton of
    // the figure's size.
    final total = resolveVenueTotal(
        walletId: ref
            .watch(settingsProvider.select((s) => pickSpendingWallet(s)?.id)),
        venue: predictions ? 'predictions' : 'trading',
        fresh: balances.total);
    return PoolBalanceHeader(
      loading: total.value == null,
      stale: total.stale,
      amountText: amount(total.value),
      totalLabel: predictions
          ? context.l10n.predictionsTotal
          : context.l10n.investingTotal,
      investedLabel: context.l10n.ledgerPositionsTitle,
      availableLabel: context.l10n.available,
      // What is at work: the prediction positions, or everything
      // Investing holds beyond spendable cash.
      investedText: hasBalance
          ? amount(predictions ? balances.positions : balances.portfolio)
          : null,
      availableText: hasBalance ? amount(balances.available) : null,
      balanceDetail: predictions && (balances.committed ?? 0) > 0
          ? context.l10n.investingInOpenOrders(amount(balances.committed))
          : null,
      showActionRow: false,
      // This header carries no shortcut any more.
      //
      // Earn used to sit here, on Investing only. It belongs to the
      // dollar balance now, so Investing does not offer it at all (user
      // decision September 2026).
      //
      // Predictions carries the Build shortcut to the portfolio builder
      // beside Deposit, where the scanner sits on Bitcoin: it is the way
      // into combos. Hidden until the builder ships ([kShowPortfolioBuilder]).
      trailingCta: kShowPortfolioBuilder && showDepositButton && predictions
          ? PoolHeaderShortcut(
              label: context.l10n.builderStepBuild,
              icon: Icons.add_chart_rounded,
              showLabel: false,
              onTap: () =>
                  PortfolioBuilderScreen.show(context, BuilderPool.predictions),
            )
          : null,
      // Deposit is the top button; Portfolio moved into the dock (owner
      // decision: each job has one home).
      primaryCta: showDepositButton
          ? VenueDepositButton(
              product: product,
              source: predictions ? 'predictions' : 'trading',
              onTap: () =>
                  openInvestmentFunding(context, ref, product, deposit: true),
            )
          : null,
      investedChild: pending > 0 || leaving > 0
          ? PendingDepositLine(
              investedText: '',
              pendingText: pending > 0
                  ? visible
                      ? formatPolyFiatForced(ref, pending)
                      : '••••••'
                  : null,
              leavingText: leaving > 0
                  ? visible
                      ? formatPolyFiatForced(ref, leaving)
                      : '••••••'
                  : null,
            )
          : null,
    );
  }

  /// The in-flight lines, in order, for [state]. Public so a test can pin
  /// the order and the wording without a widget tree.
  ///
  /// The lines name what the person is doing, never the plumbing
  /// (founder decision 14 October 2026):
  ///   * money on a rail for an order (its Bitcoin leg or its move into
  ///     the venue): the order itself, once ("Placing $5 on Yes · Lakers",
  ///     "Opening $5 NVDA order", "Adding $5 margin to BTC"), then each of
  ///     its sources in its own state, from the order's step graph
  ///     ("Moving $8.00 from Bitcoin", "Moved $5.00 from Dollars"), so the
  ///     person sees every source land with the slip closed;
  ///   * dollars arriving from outside: "Incoming $X";
  ///   * venue cash the sweeper still owes back: "unavailable until
  ///     balancing completes".
  /// Money moving between the person's own accounts for no order (the
  /// idle sweep home, a move with no order) leaves the total unchanged:
  /// no line.
  static List<String> inFlightLines(BuildContext context, OneBalanceState state,
      String Function(double) amount) {
    final l10n = context.l10n;
    final named = <String>{};
    return [
      for (final move in state.inFlight)
        if (move.order case final order? when named.add(order.id)) ...[
          switch (order.venue) {
            OneBalanceVenue.predictions => order.transfer
                ? l10n.slipStepPreparingPrediction
                : l10n.oneBalancePlacingBet(
                    amount(order.orderUsd), order.side, order.market),
            OneBalanceVenue.investing => order.margin
                ? l10n.hlMarginStepAdding(amount(order.orderUsd), order.market)
                : l10n.oneBalanceOpeningOrder(
                    amount(order.orderUsd), order.market),
          },
          for (final leg in order.legs) moneyStepLine(l10n, leg, amount),
        ],
      for (final move in state.inFlight)
        if (move.order == null && move.kind == InFlightKind.incomingDollars)
          l10n.oneBalanceIncoming(amount(move.usd)),
      for (final usd in state.waiting.values)
        if (usd > 0) l10n.oneBalanceWaitingToWithdraw(amount(usd)),
    ];
  }

  /// Whether [state] puts the in-flight lines where the split would be:
  /// whenever [inFlightLines] has one.
  static bool showsInFlight(OneBalanceState state) =>
      state.inFlight.any((move) => move.hasLine) ||
      state.waiting.values.any((usd) => usd > 0);

  /// Display-only snapshot shared by the expanded hero and compact bar. Keep
  /// the last complete wallet total while any input refreshes or reconnects.
  static ({double total, double invested, bool stale}) _oneBalanceDisplay(
      WidgetRef ref) {
    final state = ref.watch(oneBalanceProvider);
    return resolveInvestmentsDisplay(
      walletId:
          ref.watch(settingsProvider.select((s) => pickSpendingWallet(s)?.id)),
      total: state.totalUsd,
      invested: state.investedUsd,
      known: state.dollarsKnown &&
          state.investingKnown &&
          state.predictionsKnown &&
          !ref.watch(usdBalanceUnknownProvider),
    );
  }

  /// The hero's displayed total, also used by the collapsed Investments bar.
  static ({String text, bool stale}) oneBalanceFigure(WidgetRef ref) {
    final display = _oneBalanceDisplay(ref);
    final visible = ref.watch(settingsProvider.select((s) => s.balanceVisible));
    return (
      text: visible ? formatPolyFiatForced(ref, display.total) : '••••••',
      stale: display.stale,
    );
  }

  Widget _buildOneBalance(BuildContext context, WidgetRef ref) =>
      _OneBalanceHero(onTap: onTap);
}

/// The one-balance hero: the total with the portfolio glyph after
/// it and "Available $X · Invested $Y" under it, or the in-flight lines in
/// that line's place. Stateful only to ping the arrow's quick play on each
/// press.
class _OneBalanceHero extends ConsumerStatefulWidget {
  const _OneBalanceHero({this.onTap});

  final VoidCallback? onTap;

  @override
  ConsumerState<_OneBalanceHero> createState() => _OneBalanceHeroState();
}

class _OneBalanceHeroState extends ConsumerState<_OneBalanceHero> {
  final _pressed = _Ping();

  @override
  void dispose() {
    _pressed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(oneBalanceProvider);
    final visible = ref.watch(settingsProvider.select((s) => s.balanceVisible));
    String amount(double value) =>
        visible ? formatPolyFiatForced(ref, value) : '••••••';
    final lines = InvestmentBalanceHeader.inFlightLines(context, state, amount);
    final display = InvestmentBalanceHeader._oneBalanceDisplay(ref);
    final figure = InvestmentBalanceHeader.oneBalanceFigure(ref);
    // With nothing on a rail the total is Available plus Invested, so the
    // split is read off the same display snapshot as the total (cached
    // together while a venue reconnects) and always adds up to it.
    final available = display.total - display.invested;
    final tap = widget.onTap;
    // The tap affordance: an arrow to the right with the Portfolio's pie
    // as its badge, right after the big total (it opens the Portfolio;
    // founder decision), sized to sit with the 48 sp number and moving
    // like the hub's "+ gear" glyph in the top bar.
    final arrowGap = 6.w;
    final arrowSize = 30.sp;
    final arrow = tap == null
        ? null
        : Padding(
            padding: EdgeInsets.only(left: arrowGap),
            child: PortfolioArrowGlyph(
                key: const ValueKey('investments-balance-chevron'),
                color: context.colors.textTertiary,
                size: arrowSize,
                pressed: _pressed),
          );
    final header = PoolBalanceHeader(
      amountText: figure.text,
      stale: figure.stale,
      availableLabel: context.l10n.available,
      investedLabel: context.l10n.betInvested,
      amountTrailing: arrow,
      amountTrailingWidth: arrow == null ? 0 : arrowGap + arrowSize,
      // "Available $X · Invested $Y" under the total at rest (founder,
      // 27 October 2026: back after a day without it); the in-flight
      // lines in its place while anything is on a rail.
      availableFirst: true,
      availableText: lines.isEmpty
          ? amount(available.isFinite && available > 0 ? available : 0)
          : null,
      investedText: lines.isEmpty ? amount(display.invested) : null,
      showActionRow: false,
      investedChild: lines.isEmpty
          ? null
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final line in lines)
                        PendingDepositLine(investedText: '', noteText: line),
                    ],
                  ),
                ),
              ],
            ),
    );
    if (tap == null) return header;
    return Semantics(
      button: true,
      child: Listener(
        onPointerDown: (_) => _pressed.ping(),
        child: KutePressScale(
          key: const ValueKey('investments-balance'),
          onTap: tap,
          child: header,
        ),
      ),
    );
  }
}

class _Ping extends ChangeNotifier {
  void ping() => notifyListeners();
}
