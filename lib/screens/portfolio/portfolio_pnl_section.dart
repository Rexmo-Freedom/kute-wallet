// lib/screens/portfolio/portfolio_pnl_section.dart
//
// THE PORTFOLIO SCREEN'S P&L TAB (the redesign of 7 November 2026 after
// the Robinhood / Public / Webull / Polymarket / Kalshi review; founder:
// "yes build this"), under the hero's chart and its range row, top down
// ([PortfolioPnlBreakdown], mounted by PortfolioStatisticsOverview without
// its chart, portfolio_statistics.dart, which keeps the loading, error
// and never-traded states and the resting orders under it):
//
//   1. THE HEADLINE over the hero's range: "You're up $7.55" / "You're
//      down $2.10" (22 sp w700 in the result colour; "No change" on a
//      P&L under a cent), the range under it ("Past month"). The same
//      figure as the hero's line, to the cent (portfolio_pnl_period.dart),
//      and with a "By product" row picked, that venue's.
//   2. THE ROWS THAT ADD UP TO IT, in ONE soft card (PortfolioCardList):
//      "From closed positions" and "On open positions"
//      ([portfolioPnlSplit]: what the positions open now made over the
//      range, the rest of the change from what was closed, rounded so the
//      two add up to the headline as written). No fees and funding row:
//      the engine keeps the fills' fees inside each position's result and
//      funding only inside the venue's own figure, never apart, so no such
//      figure is invented. While what the open positions stood at on the
//      range's start is still read, the rows wait (no row of a guess).
//   3. "BY PRODUCT": one plain row per venue (PnlVenueRow without its
//      sparkline: the venue's logo, "Predictions" over "Polymarket",
//      "Investing" over "Hyperliquid", its P&L over the hero's range at the
//      end in its colour, the same figure the hero draws with that venue
//      picked). A row tapped draws that venue alone in the hero above and
//      here (portfolioPnlVenueProvider: the other row dimmed, the headline
//      and its rows that venue's); tapped again, both.
//   4. "CLOSED POSITIONS" over the range (every one ALL), newest first,
//      with a Date / Amount pair to sort them (the biggest result either
//      way first): each a Positions row with its result
//      ([PortfolioClosedRow]): the predictions decided (Polymarket's own
//      result per position, the engine's realised figure) and the
//      Investing positions closed, reduced or sold (each order's fills
//      added: what closing realised, less the fees in dollars). The first
//      [kPortfolioClosedShown], then "See all N" for the rest (up to
//      [kPortfolioClosedMost]), unfolding in place. Nothing closed in the
//      range: no list. A row tapped opens its receipt, the sheet the
//      Activity rows open, with the row's figure as its result; a row with
//      no receipt the market's page; one with neither does not press
//      (portfolio_closed_receipt.dart says which is which).
//
// The "All time" cards (realised, unrealised, win rate) and the venue
// squares with their sparklines and "▲ Past month" tags are gone: every
// figure here follows the hero's range.
//
// With balances hidden every figure is dots and nothing says which way it
// went. Analytics: a row picked or put back sends
// `portfolio_statistics_venue_toggled` {venue: all | hyperliquid |
// polymarket} (portfolioPickPnlVenue); the sort sends nothing, as the
// ranges do; a closed row tapped sends `portfolio_closed_position_tapped`
// {venue: hyperliquid | polymarket, source: section | see_all (the list
// unfolded)}.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/helpers/formatters/polymarket_amount_formatter.dart';
import 'package:kute/helpers/hyperliquid_activity.dart'
    show HlFillKind, hlFillEffect;
import 'package:kute/helpers/prediction_results.dart' show predictionResults;
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart' show HlFill;
import 'package:kute/models/polymarket_model.dart'
    show ClosedPosition, Position;
import 'package:kute/models/open_pnl_history.dart' show hlFillIsSpot;
import 'package:kute/models/balance_history.dart' show BalanceRange;
import 'package:kute/providers/hyperliquid_sats_pnl_provider.dart'
    show hyperliquidActivityFillsProvider;
import 'package:kute/providers/polymarket_trading_provider.dart'
    show polymarketTradingProvider;
import 'package:kute/providers/portfolio_performance_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/transactions_provider.dart'
    show walletTransactionCacheProvider;
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/screens/portfolio/components/balances_overview.dart'
    show
        BalancesFoldRow,
        balancesFlatSectionTitle,
        kBalancesCentUsd,
        kBalancesGroupGap,
        kBalancesTitleGap;
import 'package:kute/screens/portfolio/components/portfolio_pnl_chart.dart'
    show PnlVenueRow, pnlResultColor;
import 'package:kute/screens/portfolio/components/portfolio_pnl_period.dart';
import 'package:kute/screens/portfolio/components/position_rows.dart'
    show
        PortfolioCardList,
        PortfolioClosedRow,
        PortfolioRowInset,
        kPortfolioCardInset,
        portfolioRowFigureStyle,
        portfolioRowTitleStyle;
import 'package:kute/screens/portfolio/open_investments_screen.dart'
    show InvestmentsProduct;
import 'package:kute/screens/portfolio/poly_position_events.dart'
    show polyPositionEventProvider;
import 'package:kute/screens/portfolio/portfolio_closed_receipt.dart';
import 'package:kute/screens/portfolio/portfolio_empty_state.dart'
    show kPortfolioSectionEmptyTop;
import 'package:kute/screens/portfolio/portfolio_filters.dart';
import 'package:kute/screens/shared/charts/kute_trend_window.dart'
    show kuteTrendPeriodLabel;
import 'package:kute/screens/shared/kute_pill_tabs.dart'
    show KutePill, KutePillSize;
import 'package:kute/screens/shared/venue_deposit_button.dart'
    show venueMarkAsset;
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// How many closed positions show before "See all".
const int kPortfolioClosedShown = 5;

/// The most closed positions "See all" lists.
const int kPortfolioClosedMost = 100;

/// The headline's size, design units.
const double kPortfolioPnlHeadline = 22;

/// The P&L tab (see the file header). [listed] are the venues read, in
/// order (Predictions, then Investing); [quiet] the ones with no history
/// (their "No … yet" in place of a figure, [quietText]); [selected] the
/// row picked (null: both); [onPick] a row tapped (null: the rows pick
/// nothing, one venue alone).
class PortfolioPnlBreakdown extends ConsumerWidget {
  const PortfolioPnlBreakdown({
    super.key,
    required this.listed,
    required this.quiet,
    required this.quietText,
    required this.selected,
    required this.onPick,
  });

  final List<PortfolioPerformanceVenue> listed;
  final Set<PortfolioPerformanceVenue> quiet;
  final String Function(PortfolioPerformanceVenue venue) quietText;
  final PortfolioPerformanceVenue? selected;
  final ValueChanged<PortfolioPerformanceVenue>? onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = portfolioPnlPeriod(ref, venue: selected);
    return Column(
      key: const ValueKey('statistics-pnl-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // The section's list starts 4 under the strip.
        SizedBox(height: (kPortfolioSectionEmptyTop - 4).h),
        _PnlHeadline(period: period),
        if (portfolioPnlSplit(ref, period) case final split?) ...[
          SizedBox(height: 14.h),
          _PnlSplitCard(split: split),
        ],
        SizedBox(height: kBalancesGroupGap.h),
        Text(context.l10n.portfolioPnlByProduct,
            key: const ValueKey('statistics-pnl-by-product'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: balancesFlatSectionTitle(context)),
        SizedBox(height: kBalancesTitleGap.h),
        _ByProduct(
          listed: listed,
          quiet: quiet,
          quietText: quietText,
          selected: selected,
          onPick: onPick,
          range: period.ready ? period.range : null,
        ),
        _ClosedPositions(
          venue: selected,
          since: period.ready && period.range != BalanceRange.all
              ? period.start
              : null,
        ),
      ],
    );
  }
}

/// A P&L as the tab writes it: signed dollars;
/// dots with balances hidden.
String _signed(WidgetRef ref, double usd, {required bool visible}) {
  if (!visible) return '••••••';
  final v = usd.abs() < kBalancesCentUsd ? 0.0 : usd;
  final sign = v > 0
      ? '+'
      : v < 0
          ? '−'
          : '';
  return '$sign${formatDollars(v.abs())}';
}

/// [usd]'s colour: green up, red down, the text colour flat or hidden.
Color _tone(BuildContext context, double usd, {required bool visible}) {
  final c = context.colors;
  if (!visible || usd.abs() < kBalancesCentUsd) return c.textPrimary;
  return pnlResultColor(c, usd);
}

/// "You're up $7.55" over "Past month" (see the file header): the hero's
/// own figure; its shape while the period is read.
class _PnlHeadline extends ConsumerWidget {
  const _PnlHeadline({required this.period});

  final PortfolioPnlPeriod period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final l10n = context.l10n;
    final visible = ref.watch(settingsProvider.select((s) => s.balanceVisible));
    final ready = period.ready;
    final change = ready ? period.change : 0.0;
    final flat = change.abs() < kBalancesCentUsd;
    final money = formatDollars(change.abs());
    final text = !ready
        ? '—'
        : !visible
            ? '••••••'
            : flat
                ? l10n.chartNoChange
                : change > 0
                    ? l10n.portfolioPnlYoureUp(money)
                    : l10n.portfolioPnlYoureDown(money);
    final quiet = TextStyle(
      color: c.textSecondary,
      fontSize: 13.sp,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.1,
      height: 1.3,
    );
    return Semantics(
      container: true,
      header: true,
      label: ready ? '$text, ${kuteTrendPeriodLabel(l10n, period.range)}' : text,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Scaled down rather than cut at a large text size.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              text,
              key: const ValueKey('portfolio-pnl-headline'),
              maxLines: 1,
              style: TextStyle(
                color: _tone(context, change, visible: visible && ready),
                fontSize: kPortfolioPnlHeadline.sp,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                height: 1.2,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (ready) ...[
            SizedBox(height: 2.h),
            Text(kuteTrendPeriodLabel(l10n, period.range),
                key: const ValueKey('portfolio-pnl-period'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: quiet),
          ],
        ],
      ),
    );
  }
}

/// The two rows that add up to the headline, in one soft card.
class _PnlSplitCard extends ConsumerWidget {
  const _PnlSplitCard({required this.split});

  final PortfolioPnlSplit split;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final visible = ref.watch(settingsProvider.select((s) => s.balanceVisible));
    Widget row(Key key, String label, double usd) => _SplitRow(
          key: key,
          label: label,
          figure: _signed(ref, usd, visible: visible),
          color: _tone(context, usd, visible: visible),
        );
    return PortfolioCardList(
      key: const ValueKey('portfolio-pnl-split'),
      indent: kPortfolioCardInset.w,
      rows: [
        row(const ValueKey('portfolio-pnl-closed'), l10n.portfolioPnlFromClosed,
            split.closed),
        row(const ValueKey('portfolio-pnl-open'), l10n.portfolioPnlOnOpen,
            split.open),
      ],
    );
  }
}

/// One row of the split: its label (the rows' title, 15 w500) and its
/// figure at the end (15 w600, signed, in its colour).
class _SplitRow extends StatelessWidget {
  const _SplitRow(
      {super.key,
      required this.label,
      required this.figure,
      required this.color});

  final String label;
  final String figure;
  final Color color;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        label: '$label, $figure',
        excludeSemantics: true,
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: PortfolioRowInset.of(context),
              vertical: PortfolioRowInset.verticalOf(context)),
          child: Row(
            children: [
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: portfolioRowTitleStyle(context)),
              ),
              SizedBox(width: 12.w),
              Text(figure,
                  key: const ValueKey('portfolio-pnl-split-figure'),
                  maxLines: 1,
                  style: portfolioRowFigureStyle(context, color: color)),
            ],
          ),
        ),
      );
}

/// "By product": one plain row per venue (see the file header), its P&L
/// over [range] (the hero's; null while it is read: a dash).
class _ByProduct extends ConsumerWidget {
  const _ByProduct({
    required this.listed,
    required this.quiet,
    required this.quietText,
    required this.selected,
    required this.onPick,
    required this.range,
  });

  final List<PortfolioPerformanceVenue> listed;
  final Set<PortfolioPerformanceVenue> quiet;
  final String Function(PortfolioPerformanceVenue venue) quietText;
  final PortfolioPerformanceVenue? selected;
  final ValueChanged<PortfolioPerformanceVenue>? onPick;
  final BalanceRange? range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    Widget row(PortfolioPerformanceVenue v) {
      final name = v == PortfolioPerformanceVenue.predictions
          ? 'predictions'
          : 'investing';
      final isQuiet = quiet.contains(v);
      double? figure;
      if (!isQuiet && range != null) {
        final p = portfolioPnlPeriod(ref, venue: v, range: range);
        figure = p.ready ? p.change : p.status == PortfolioPnlStatus.none ? 0 : null;
      }
      final pick = onPick;
      final tap = pick == null || isQuiet ? null : () => pick(v);
      final row = PnlVenueRow(
        key: ValueKey('pnl-venue-$name'),
        logoAsset: venueMarkAsset(v == PortfolioPerformanceVenue.predictions
            ? InvestmentsProduct.predictions
            : InvestmentsProduct.trading),
        name: v == PortfolioPerformanceVenue.predictions
            ? l10n.predictions
            : l10n.trading,
        subtitle: v == PortfolioPerformanceVenue.predictions
            ? 'Polymarket'
            : 'Hyperliquid',
        data: const PortfolioPerformance(
            points: [], sourceLabel: '', basisLabel: '', coverageLabel: ''),
        pnlUsd: figure,
        periodFigure: true,
        quiet: isQuiet ? quietText(v) : null,
        selected: selected == v,
        dimmed: selected != null && selected != v,
        onTap: tap,
      );
      return tap == null
          ? row
          : KeyedSubtree(key: ValueKey('pnl-venue-$name-pick'), child: row);
    }

    return PortfolioCardList(
      key: const ValueKey('statistics-figures'),
      rows: [for (final v in listed) row(v)],
    );
  }
}

/// One closed position (see the file header): a prediction decided or an
/// Investing order that closed, reduced or sold a position.
@immutable
class PortfolioClosedEntry {
  const PortfolioClosedEntry({
    required this.id,
    required this.venue,
    required this.at,
    required this.resultUsd,
    this.prediction,
    this.fill,
    this.fills = const [],
    this.long,
  });

  final String id;
  final PortfolioPerformanceVenue venue;
  final DateTime at;

  /// What closing it realised, net of the fees in dollars.
  final double resultUsd;
  final PredictionRecord? prediction;

  /// The order's last fill.
  final HlFill? fill;

  /// The order's closing fills, every one the result adds.
  final List<HlFill> fills;

  /// The side it closed; null for a holding sold.
  final bool? long;
}

/// Every closed position at the venues on the account, newest first (see
/// the file header): Polymarket's own result per decided prediction
/// (PredictionRecord.decidedPnlUsd, the engine's realised figure) and each
/// Investing order that closed, reduced or sold (its fills' realised P&L
/// added, less the fees paid in dollars). Laid once per read, never on a
/// tick.
final portfolioClosedPositionsProvider =
    Provider.autoDispose<List<PortfolioClosedEntry>>((ref) {
  final venues = ref.watch(portfolioVenuesProvider);
  final out = <PortfolioClosedEntry>[];
  if (venues.predictions) {
    final records = ref.watch(portfolioPerformanceDisplayProvider(
            const PortfolioPerformanceRequest(
                venue: PortfolioPerformanceVenue.predictions))
        .select((a) => a.valueOrNull?.predictions?.records));
    for (final r in distinctPredictionRecords(records ?? const [])) {
      final result = r.decidedPnlUsd;
      final at = r.lastEventAt ?? r.firstEntryAt;
      if (result == null || !result.isFinite || at == null) continue;
      out.add(PortfolioClosedEntry(
        id: 'pm:${r.tokenId}',
        venue: PortfolioPerformanceVenue.predictions,
        at: at,
        resultUsd: result,
        prediction: r,
      ));
    }
  }
  if (venues.trading) {
    final fills = ref.watch(hyperliquidActivityFillsProvider);
    final orders = <String,
        ({HlFill last, double result, bool? long, List<HlFill> fills})>{};
    for (final f in fills) {
      if (!(f.sz > 0)) continue;
      final e = hlFillEffect(f);
      final bool? long;
      switch (e.kind) {
        case HlFillKind.closed:
        case HlFillKind.reduced:
        case HlFillKind.liquidated:
          long = e.long;
        case HlFillKind.flipped:
          // The side it held before the flip is the one it closed.
          long = e.long == null ? null : !e.long!;
        case HlFillKind.sold:
          if (f.closedPnl == 0) continue;
          long = null;
        case HlFillKind.opened:
        case HlFillKind.added:
        case HlFillKind.bought:
          continue;
      }
      final usdFee =
          f.feeToken.isEmpty || f.feeToken.toUpperCase().startsWith('USD');
      final result = f.closedPnl - (usdFee ? f.fee : 0);
      if (!result.isFinite) continue;
      final key = '${f.coin}:${f.oid}';
      final before = orders[key];
      orders[key] = (
        last: before == null || f.time > before.last.time ? f : before.last,
        result: (before?.result ?? 0) + result,
        long: before?.long ?? (hlFillIsSpot(f) ? null : long),
        fills: [...?before?.fills, f],
      );
    }
    for (final MapEntry(key: key, value: o) in orders.entries) {
      out.add(PortfolioClosedEntry(
        id: 'hl:$key',
        venue: PortfolioPerformanceVenue.trading,
        at: DateTime.fromMillisecondsSinceEpoch(o.last.time),
        resultUsd: o.result,
        fill: o.last,
        fills: o.fills,
        long: o.long,
      ));
    }
  }
  out.sort((a, b) => b.at.compareTo(a.at));
  return List.unmodifiable(out);
});

/// Where each closed position goes when tapped, by its id; a row with none
/// is not in the map (see portfolio_closed_receipt.dart). Follows the
/// spending account's venue records and its resolved positions.
final portfolioClosedDestinationsProvider =
    Provider.autoDispose<Map<String, PortfolioClosedDestination>>((ref) {
  final entries = ref.watch(portfolioClosedPositionsProvider);
  final out = <String, PortfolioClosedDestination>{};
  if (entries.any((e) => e.prediction != null)) {
    final walletId =
        ref.watch(settingsProvider.select((s) => pickSpendingWallet(s)?.id));
    final history = ref.watch(walletTransactionCacheProvider.select((cache) =>
            walletId == null ? null : cache[walletId]?.polymarketTransactions)) ??
        const [];
    final held = ref.watch(polymarketTradingProvider.select((a) => (
          open: a.valueOrNull?.openPositions ?? const <Position>[],
          closed: a.valueOrNull?.closedPositions ?? const <ClosedPosition>[],
          clearing: a.valueOrNull?.clearingConditionIds ?? const <String>{},
        )));
    final results = predictionResults(
      open: held.open,
      closed: held.closed,
      history: [for (final t in history) t.activity],
      clearing: held.clearing,
    );
    for (final e in entries) {
      final record = e.prediction;
      if (record == null) continue;
      final to = resolveClosedPrediction(record,
          resultUsd: e.resultUsd, history: history, results: results);
      if (to != null) out[e.id] = to;
    }
  }
  for (final e in entries) {
    if (e.fills.isEmpty) continue;
    out[e.id] = PortfolioClosedFillReceipt(foldClosedFills(e.fills));
  }
  return out;
});

/// How the closed positions are listed.
enum PortfolioClosedSort { date, amount }

/// "Closed positions" (see the file header): [venue]'s (null: both),
/// closed since [since] (null: all of them).
class _ClosedPositions extends ConsumerStatefulWidget {
  const _ClosedPositions({required this.venue, required this.since});

  final PortfolioPerformanceVenue? venue;
  final DateTime? since;

  @override
  ConsumerState<_ClosedPositions> createState() => _ClosedPositionsState();
}

class _ClosedPositionsState extends ConsumerState<_ClosedPositions> {
  PortfolioClosedSort _sort = PortfolioClosedSort.date;
  bool _open = false;

  void _pick(PortfolioClosedSort next) {
    if (next == _sort) return;
    HapticFeedback.selectionClick();
    setState(() => _sort = next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final since = widget.since;
    final venue = widget.venue;
    final destinations = ref.watch(portfolioClosedDestinationsProvider);
    final all = [
      for (final e in ref.watch(portfolioClosedPositionsProvider))
        if ((venue == null || e.venue == venue) &&
            (since == null || !e.at.isBefore(since)))
          e,
    ];
    if (all.isEmpty) return const SizedBox.shrink();
    final sorted = _sort == PortfolioClosedSort.date
        ? all
        : ([...all]
          ..sort((a, b) => b.resultUsd.abs().compareTo(a.resultUsd.abs())));
    final shown = sorted
        .take(_open ? kPortfolioClosedMost : kPortfolioClosedShown)
        .toList(growable: false);
    final fold = all.length > kPortfolioClosedShown
        ? BalancesFoldRow(
            key: const ValueKey('portfolio-closed-see-all'),
            open: _open,
            count: all.length,
            onTap: () => setState(() => _open = !_open),
          )
        : null;
    Widget pill(PortfolioClosedSort sort, String label) => Padding(
          padding: EdgeInsetsDirectional.only(start: 6.w),
          child: KutePill(
            key: ValueKey('portfolio-closed-sort-${sort.name}'),
            label: label,
            selected: _sort == sort,
            size: KutePillSize.compact,
            onTap: () => _pick(sort),
          ),
        );
    return Padding(
      key: const ValueKey('portfolio-closed'),
      padding: EdgeInsets.only(top: kBalancesGroupGap.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(l10n.portfolioClosedPositions,
                    key: const ValueKey('portfolio-closed-title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: balancesFlatSectionTitle(context)),
              ),
              pill(PortfolioClosedSort.date, l10n.date),
              pill(PortfolioClosedSort.amount, l10n.amount),
            ],
          ),
          SizedBox(height: kBalancesTitleGap.h),
          PortfolioCardList(
            key: const ValueKey('portfolio-closed-list'),
            afterHairline: true,
            rows: [
              for (final e in shown)
                _ClosedListRow(
                  key: ValueKey('portfolio-closed-${e.id}'),
                  entry: e,
                  destination: destinations[e.id],
                  source: _open ? 'see_all' : 'section',
                ),
            ],
            after: fold,
          ),
        ],
      ),
    );
  }
}

/// One closed position on the list, tapped: its [destination] (see
/// portfolio_closed_receipt.dart). The market's page waits for its event;
/// no [destination], or an event not known: the row does not press.
class _ClosedListRow extends ConsumerWidget {
  const _ClosedListRow({
    super.key,
    required this.entry,
    required this.destination,
    required this.source,
  });

  final PortfolioClosedEntry entry;
  final PortfolioClosedDestination? destination;
  final String source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final to = destination;
    final ready = switch (to) {
      null => false,
      PortfolioClosedMarketPage(:final eventSlug) =>
        ref.watch(polyPositionEventProvider(eventSlug)) != null,
      _ => true,
    };
    return PortfolioClosedRow(
      at: entry.at,
      resultUsd: entry.resultUsd,
      prediction: entry.prediction,
      fill: entry.fill,
      long: entry.long,
      onTap: !ready
          ? null
          : () {
              HapticFeedback.selectionClick();
              TrackingService.track('portfolio_closed_position_tapped',
                  params: {
                    'venue': entry.venue == PortfolioPerformanceVenue.trading
                        ? 'hyperliquid'
                        : 'polymarket',
                    'source': source,
                  });
              openPortfolioClosedDestination(context, ref, to!,
                  resultUsd: entry.resultUsd);
            },
    );
  }
}
