import 'package:kute/screens/shared/sal_sprite.dart';
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
import 'package:kute/screens/shared/rolling_number_text.dart';
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
              child: SalSprite(
                clip: 'body_sad',
                size: 220,
                fallback: KuteDogNotHere(
                  width: 220,
                  ink: context.colors.textPrimary,
                  accent: context.colors.accent,
                ),
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
///     ([PortfolioArrowGlyph]); under it "Invested $X · Available $Y"
///     ([OneBalanceSplitLine]; founder, 4 November 2026), all in dollars
///     whatever the Settings currency (founder, 8 November 2026: "dollars
///     balance do not convert to currency"), the two adding
///     up to the total ([oneBalanceSplit]; Invested: positions, reserved
///     order cash, pending fills and money on its way into an order;
///     Available: the rest, Dollars and the venues' cash). Never a line
///     for an order on its way (founder, 10 November 2026: "under the
///     main balance what is happening. Do not have this"; the Overview's
///     card says Placing). The other in-flight lines follow under it, and
///     Available leaves their money out: incoming from outside,
///     unavailable until balancing completes (venue cash the sweeper
///     still owes back). Money on a rail between the person's
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
            : formatDollars(value);
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
                      ? formatDollars(pending)
                      : '••••••'
                  : null,
              leavingText: leaving > 0
                  ? visible
                      ? formatDollars(leaving)
                      : '••••••'
                  : null,
            )
          : null,
    );
  }

  /// The in-flight lines, in order, for [state]. Public so a test can pin
  /// the order and the wording without a widget tree.
  ///
  /// Never an order on its way (founder, 10 November 2026, on 2.2.0 (98):
  /// "we also have in the dollars under the main balance what is
  /// happening. Do not have this"): money on a rail for an order counts in
  /// Invested at once ([oneBalanceSplitFigures]) and the order's one card
  /// on the Overview says Placing. What is left:
  ///   * dollars arriving from outside: "Incoming $X";
  ///   * venue cash the sweeper still owes back: "unavailable until
  ///     balancing completes".
  /// Money moving between the person's own accounts for no order (the
  /// idle sweep home, a move with no order) leaves the total unchanged:
  /// no line.
  static List<String> inFlightLines(BuildContext context, OneBalanceState state,
      String Function(double) amount) {
    final l10n = context.l10n;
    return [
      for (final move in state.inFlight)
        if (move.hasLine) l10n.oneBalanceIncoming(amount(move.usd)),
      for (final usd in state.waiting.values)
        if (usd > 0) l10n.oneBalanceWaitingToWithdraw(amount(usd)),
    ];
  }

  /// Whether [state] puts in-flight lines under the split: whenever
  /// [inFlightLines] has one.
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

  /// The hero's "Invested · Available" under its total, as printed: the
  /// split of the total the hero prints ([oneBalanceSplit]: they add up to
  /// it, less the money the in-flight lines name, to the cent; money on
  /// its way into an order is Invested already), from the
  /// same snapshot as the figure (a saved one, dimmed, while a venue is
  /// still on its way). In dollars, whatever the Settings currency.
  static ({double investedUsd, double availableUsd, bool stale})
      oneBalanceSplitFigures(WidgetRef ref) {
    final display = _oneBalanceDisplay(ref);
    final state = ref.watch(oneBalanceProvider);
    final split = oneBalanceSplit(
      totalUsd: display.total,
      investedUsd: display.invested,
      forOrdersUsd: state.forOrdersUsd,
      onLinesUsd: state.onLinesUsd,
    );
    return (
      investedUsd: split.investedUsd,
      availableUsd: split.availableUsd,
      stale: display.stale,
    );
  }

  /// The hero's displayed total, also used by the collapsed Investments bar.
  static ({String text, bool stale}) oneBalanceFigure(WidgetRef ref) {
    final display = _oneBalanceDisplay(ref);
    final visible = ref.watch(settingsProvider.select((s) => s.balanceVisible));
    return (
      text: visible ? formatDollars(display.total) : '••••••',
      stale: display.stale,
    );
  }

  Widget _buildOneBalance(BuildContext context, WidgetRef ref) =>
      _OneBalanceHero(onTap: onTap);
}

/// The one-balance hero: the total with the portfolio glyph after
/// it, "Invested $X · Available $Y" under it ([OneBalanceSplitLine]) and
/// the in-flight lines under that. Stateful only to ping the arrow's quick
/// play on each press.
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
        visible ? formatDollars(value) : '••••••';
    final lines = InvestmentBalanceHeader.inFlightLines(context, state, amount);
    final split = InvestmentBalanceHeader.oneBalanceSplitFigures(ref);
    final figure = InvestmentBalanceHeader.oneBalanceFigure(ref);
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
      // "Invested $X · Available $Y" under the total, always (founder,
      // 4 November 2026: "it should show invested and available in a good
      // way at the bottom, don't make it sloppy"; it read Invested alone
      // since 28 October). The two add up to the total ([oneBalanceSplit]);
      // while money is on a rail its lines follow, under the split, and
      // the split leaves their money out, so the three still add up.
      availableText: null,
      investedText: null,
      showActionRow: false,
      investedChild: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.only(top: 2.h),
            child: OneBalanceSplitLine(
              invested: amount(split.investedUsd),
              available: amount(split.availableUsd),
              investedLabel: context.l10n.betInvested,
              availableLabel: context.l10n.available,
              stale: split.stale,
            ),
          ),
          if (lines.isNotEmpty) ...[
            SizedBox(height: 4.h),
            Row(
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
          ],
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

/// "Invested $X · Available $Y" under the Dollars total
/// ([InvestmentBalanceHeader.oneBalanceSplitFigures]), drawn so it never
/// jitters: the dot is fixed at the centre, right under the total, the
/// Invested half ends at it and the Available half starts at it, each
/// figure in tabular digits rolling like the total. A figure that ticks,
/// or grows a digit, moves only its own half outwards; the dot and the
/// other half stay where they are. Too wide for its half (a large text
/// size), a half scales down rather than wrapping or cutting. The words
/// stay quiet (textTertiary), the amounts carry the line (textSecondary,
/// w600); a saved figure still updating is dimmed, as the total is.
class OneBalanceSplitLine extends StatelessWidget {
  const OneBalanceSplitLine({
    super.key,
    required this.invested,
    required this.available,
    required this.investedLabel,
    required this.availableLabel,
    this.stale = false,
  });

  final String invested;
  final String available;
  final String investedLabel;
  final String availableLabel;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final labelStyle = TextStyle(
      color: c.textTertiary,
      fontSize: 15.sp,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.1,
      height: 1.2,
    );
    final valueStyle = TextStyle(
      color: stale ? c.textTertiary : c.textSecondary,
      fontSize: 15.sp,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
      height: 1.2,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    Widget half(Key key, String label, String value, Alignment align) =>
        Expanded(
          child: Align(
            alignment: align,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: align,
              child: Row(
                key: key,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$label ', maxLines: 1, style: labelStyle),
                  RollingNumberText(text: value, style: valueStyle),
                ],
              ),
            ),
          ),
        );
    return Semantics(
      container: true,
      label: '$investedLabel $invested, $availableLabel $available',
      excludeSemantics: true,
      child: Row(
        key: const ValueKey('investments-balance-split'),
        children: [
          half(const ValueKey('investments-balance-invested'), investedLabel,
              invested, Alignment.centerRight),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8.w),
            child: Text('·', style: labelStyle),
          ),
          half(const ValueKey('investments-balance-available'),
              availableLabel, available, Alignment.centerLeft),
        ],
      ),
    );
  }
}

class _Ping extends ChangeNotifier {
  void ping() => notifyListeners();
}
