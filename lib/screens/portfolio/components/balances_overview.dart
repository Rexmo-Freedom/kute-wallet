// lib/screens/portfolio/components/balances_overview.dart
//
// Investments → Portfolio → Balances, the Portfolio's first section. What
// the money is DOING first, where it sits only as detail (founder,
// October 2026, after a competitor review: Robinhood's "Buying power",
// Revolut's "Total wealth"), and since 27 October 2026 the positions
// themselves under their venue (the Positions pill is gone). Top down:
//
//   * the lead row, lighter (founder, 28 October 2026): a SMALL bare RING
//     on the left (40, the engine's KuteDonutChart, nothing in its hole:
//     the hero above the pills carries the total), its slices in each
//     category's FIXED colour of the muted chart palette (Available to
//     invest indigo, Investing teal, Predictions amber:
//     AppColorsExtension.chartCategorical), the same as the dots, so
//     there is no legend; next to it ONE line, "● Available to invest"
//     (the venues' title size; "Buying power" until the founder's 27
//     October 2026 review, the l10n key and widget keys keep the old
//     name) with the spare cash (Dollars + Hyperliquid cash + Polymarket
//     cash) and its chevron at the line's END, a tap opening where that
//     cash sits, largest first, under the row (a Rebalance note under a
//     place opens it by itself); Move money, a large pill like the
//     selected section pill, under that line, starting where the label
//     does; its [steps] under the row while a move runs;
//   * then one block per venue, no hairlines between them (founder,
//     27 October 2026): "● Predictions  N" (a step larger than the rows)
//     with its value and its P&L (in the result colour) on the right, the
//     venue's positions under it in ONE grouped card, the Investing and
//     Predictions lists' own (PremiumGroupContainer's surface, radius and
//     soft shadow, Home's inset hairline between rows), as the Option-B
//     position rows
//     (components/position_rows.dart: picture, short title, "event ·
//     side", chance bar with its entry tick, value and %), a tap opening
//     each one's sheet; then "● Investing  N" the same way. A venue with
//     nothing open reads "No open positions" in its header row and lists
//     nothing; what open orders hold there is named under its header.
//     Each venue's card lists its 3 largest open rows (founder, 28
//     October 2026: the same live rows, fewer of them), then a quiet
//     "See all  N ›" row (N: every row the venue has, settled ones
//     included) that opens the rest in place, the other open rows and
//     then the settled ones, and turns into "Show less"; a venue with 3
//     rows or fewer and nothing settled lists them all, no fold row.
//
// The first load (founder, 28 October 2026): until both venues' positions
// are known (a list still read with nothing in it, a venue's figures never
// read this session and the breakdown's refresh on open not done yet) the
// venue area is the venue card's skeleton rows, never headers that then
// give way to "No open positions" or Sal. Known once, the area follows the
// figures and a later refresh (the shimmer of a figure being read again,
// a list reloading) keeps what is on screen: no skeleton, no headers
// coming and going.
//
// Unknown figures keep the breakdown's rules: a figure never read reads a
// dash, dimmed and sweeping ([StaleShimmer]); a cached one is dimmed with
// the same sweep while it refreshes; never a confident $0.00. While any
// part of the total is unknown the ring shows its track only.
//
// The venue lines are shared: the P&L charts section
// (portfolio_statistics.dart, PortfolioStatisticsOverview) draws its one
// line per venue under the chart with [BalancesVenueHeader], so the two
// sections name and colour the venues the same way.
//
// Analytics: `portfolio_available_to_invest_toggled` {open} (the split),
// `portfolio_balances_empty_shown` {surface} (Sal, once per mount),
// `portfolio_venue_positions_expanded` {venue: predictions | investing,
// open} (a venue's See all / Show less).

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/charts/kute_donut_chart.dart';
import 'package:kute/screens/portfolio/components/position_rows.dart'
    show PortfolioRowInset, kPortfolioRowGap, kPortfolioRowImage;
import 'package:kute/screens/shared/animations/premium_group_container.dart';
import 'package:kute/screens/shared/market_groups.dart' show marketGroupDivider;
import 'package:kute/screens/shared/kute_motion.dart'
    show RollingFigure, kuteReduceMotion;
import 'package:kute/screens/shared/kute_skeleton.dart' show SkeletonRowList;
import 'package:kute/screens/shared/no_activity_state.dart';
import 'package:kute/screens/shared/stale_shimmer.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/screens/shared/money_movement_sheet.dart'
    show showMoneyMovementSheet;
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/theme/kute_motion.dart';

/// The three accounts the figures come from.
enum BalancesPart { dollars, investing, predictions }

/// What the money is doing, in legend and row order.
enum BalancesCategory { buyingPower, predictions, investing }

/// Under this a figure is nothing ("$0.00"): no slice.
const double kBalancesCentUsd = 0.005;

/// The ring's size: small and bare, at the start of the lead row (founder,
/// 28 October 2026: lighter; the Breakdown card's ring is 184 on a row of
/// its own).
const double kBalancesRingDiameter = 40;
const double kBalancesRingThickness = 5;

/// The Portfolio screen's shares ring.
const double kBalancesSharesRingDiameter = 72;

/// How many of a venue's open rows its card lists before "See all".
const int kBalancesVenueRowsShown = 3;

/// The gap between the ring and the dot that starts the lead line.
const double kBalancesRingGap = 10;

/// A figure as the breakdown resolved it: its text (masked when balances
/// are hidden, a dash when never read), whether it is still refreshing,
/// and its value (null when unknown).
@immutable
class BalancesFigure {
  const BalancesFigure(this.text, {this.stale = false, this.usd});

  final String text;
  final bool stale;
  final double? usd;
}

/// One account as the breakdown read it.
@immutable
class BalancesEntry {
  const BalancesEntry({
    required this.part,
    required this.asset,
    required this.name,
    required this.cash,
    this.positions,
    this.positionCount = 0,
    this.reservedUsd = 0,
    this.footer = const [],
    this.read = true,
  });

  final BalancesPart part;
  final String asset;

  /// Where the money sits, as the Buying power sub-row names it
  /// ("Hyperliquid", "Polymarket", "Dollars").
  final String name;
  final BalancesFigure cash;

  /// What it holds in positions; null for Dollars, which hold none.
  final BalancesFigure? positions;

  /// How many positions (Investing) or predictions (Predictions) it holds.
  final int positionCount;

  /// Cash its open orders reserve: neither spare cash nor a position
  /// (a prediction not yet bought). Part of the account's money at work,
  /// with [positions], and of its total; known whenever [positions] is.
  final double reservedUsd;

  /// Quiet captions under its sub-row (where Buying power sits): a
  /// Rebalance note. Any note opens the split.
  final List<String> footer;

  /// Its figures were read this session (a refresh of them may be
  /// running); false while they are only a saved figure or none, so what
  /// it holds is not known yet (the first load, see the file header).
  final bool read;

  /// The key part of its widgets ("dollars", "investing").
  String get id => part.name;

  /// Both figures known.
  bool get known =>
      cash.usd != null && (positions == null || positions!.usd != null);

  double get cashUsd => _clean(cash.usd);
  double get positionsUsd => _clean(positions?.usd);

  /// What open orders reserve, counted only while [positions] is known.
  double get reservedCashUsd =>
      positions?.usd == null ? 0 : _clean(reservedUsd);

  /// Positions and the reserve together: the account's money at work (its
  /// share of the header's Invested).
  double get atWorkUsd => positionsUsd + reservedCashUsd;
  double get totalUsd => cashUsd + atWorkUsd;

  bool get stale => cash.stale || (positions?.stale ?? false);
}

double _clean(double? usd) => usd != null && usd.isFinite && usd > 0 ? usd : 0;

/// One category's figure: its value (null while a part of it is unknown)
/// and whether any part is refreshing.
typedef BalancesCategoryFigure = ({double? usd, bool stale});

/// The categories the accounts make, in legend order: Buying power (every
/// account's cash), then Predictions and Investing (what each venue has at
/// work), each only when its venue is on the account. Pure for the tests.
Map<BalancesCategory, BalancesCategoryFigure> balancesCategories(
    List<BalancesEntry> entries) {
  BalancesEntry? of(BalancesPart part) {
    for (final e in entries) {
      if (e.part == part) return e;
    }
    return null;
  }

  BalancesCategoryFigure atWork(BalancesEntry e) => (
        usd: e.positions?.usd == null ? null : e.atWorkUsd,
        stale: e.positions?.stale ?? false,
      );
  final predictions = of(BalancesPart.predictions);
  final investing = of(BalancesPart.investing);
  return {
    BalancesCategory.buyingPower: (
      usd: entries.every((e) => e.cash.usd != null)
          ? entries.fold<double>(0, (s, e) => s + e.cashUsd)
          : null,
      stale: entries.any((e) => e.cash.stale),
    ),
    if (predictions != null) BalancesCategory.predictions: atWork(predictions),
    if (investing != null) BalancesCategory.investing: atWork(investing),
  };
}

/// The total of [categories], null while any is unknown.
double? balancesTotal(
        Map<BalancesCategory, BalancesCategoryFigure> categories) =>
    categories.values.every((c) => c.usd != null)
        ? categories.values.fold<double>(0, (s, c) => s + _clean(c.usd))
        : null;

/// Each category's share of the total (0..1, adding up to 1), in legend
/// order, zero for an empty one; empty while any figure is unknown or when
/// there is nothing at all. Pure for the tests.
Map<BalancesCategory, double> balancesShares(
    Map<BalancesCategory, BalancesCategoryFigure> categories) {
  final total = balancesTotal(categories);
  if (total == null || total < kBalancesCentUsd) return const {};
  return {
    for (final e in categories.entries)
      e.key: _clean(e.value.usd) < kBalancesCentUsd
          ? 0.0
          : _clean(e.value.usd) / total,
  };
}

/// A share as the legend writes it: whole percents, "<1%" for a sliver
/// that is not nothing, ">99%" for all but a sliver, "0%" for nothing.
/// Pure for the tests.
String balancesPercent(double share) {
  if (!share.isFinite || share <= 0) return '0%';
  final pct = share * 100;
  if (pct < 1) return '<1%';
  if (pct > 99 && pct < 100) return '>99%';
  return '${pct.round()}%';
}

/// Each category's fixed colour: the muted chart palette's indigo, amber
/// and teal, the same in the legend, the ring and the rows.
Color balancesCategoryColor(AppColorsExtension c, BalancesCategory category) =>
    switch (category) {
      BalancesCategory.buyingPower => c.chartCategorical[0],
      BalancesCategory.investing => c.chartCategorical[1],
      BalancesCategory.predictions => c.chartCategorical[2],
    };

/// The accounts under Buying power, largest cash first (an unknown one
/// last; ties in account order). Pure for the tests.
List<BalancesEntry> balancesBuyingPowerPlaces(List<BalancesEntry> entries) =>
    [...entries]..sort((a, b) {
        final au = a.cash.usd, bu = b.cash.usd;
        if (au == null || bu == null) {
          if (au == null && bu == null) return a.part.index - b.part.index;
          return au == null ? 1 : -1;
        }
        final bySize = _clean(bu).compareTo(_clean(au));
        return bySize != 0 ? bySize : a.part.index - b.part.index;
      });

/// What Balances lists under a venue's header: its open position [rows],
/// largest first (the breakdown's caller builds them,
/// open_investments_screen.dart), its [settled] rows (listed only once
/// "See all" opens the card, after the open ones), the venue's P&L beside
/// its value ([pnl]), and shimmer rows while the venue is still read with
/// nothing listed ([loading]).
@immutable
class BalancesVenueList {
  const BalancesVenueList(
      {this.rows = const [],
      this.settled = const [],
      this.pnl,
      this.loading = false});

  final List<Widget> rows;
  final List<Widget> settled;
  final Widget? pnl;
  final bool loading;

  /// Every row the venue has, open and settled.
  int get count => rows.length + settled.length;

  /// Anything listed at all.
  bool get any => rows.isNotEmpty || settled.isNotEmpty;

  static const BalancesVenueList empty = BalancesVenueList();
}

/// The ring, Available to invest beside it and Move money ([action], its
/// [steps]) at the row's end, then each
/// venue with its positions (see the file header). [money] writes an
/// amount (masked when balances are hidden); [wrap] lets the breakdown
/// wrap each account's place row (its Rebalance band, the Dollars
/// arrival); [venues] are the rows under Predictions and Investing.
class BalancesOverview extends StatefulWidget {
  const BalancesOverview({
    super.key,
    required this.entries,
    required this.money,
    this.wrap,
    this.action,
    this.steps,
    this.venues = const {},
    this.firstReadDone = true,
    this.sharesHeader = false,
  });

  /// The Portfolio screen's top (founder, 31 October 2026: "no Available
  /// to invest; Portfolio is just open positions. On top, instead of the
  /// balance, show the shares with the pie chart on the left"): the ring
  /// at 72 on the left and the shares as rows ("● Investing  $1,126.50 ·
  /// 64%") on the right, no total, no Available to invest, no Move money
  /// and no split; then the venues with their positions as ever.
  final bool sharesHeader;

  final List<BalancesEntry> entries;
  final String Function(double usd) money;
  final Widget Function(BalancesPart part, Widget row)? wrap;
  final Widget? action;
  final Widget? steps;
  final Map<BalancesCategory, BalancesVenueList> venues;

  /// The breakdown's read of the venues on open has finished (or there
  /// was none): a venue whose figures are still not read is then taken as
  /// it stands once its list is read (a cash read that failed never holds
  /// the first load forever).
  final bool firstReadDone;

  @override
  State<BalancesOverview> createState() => _BalancesOverviewState();
}

class _BalancesOverviewState extends State<BalancesOverview> {
  /// Sal's empty state (nothing open on either venue) was reported for
  /// this mount.
  bool _emptyReported = false;

  /// Reports `portfolio_balances_empty_shown` once per mount, after the
  /// frame that first draws Sal's empty state; an empty widget in the
  /// column so the build stays declarative.
  Widget _emptyShownOnce() {
    if (!_emptyReported) {
      _emptyReported = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        TrackingService.track('portfolio_balances_empty_shown',
            params: const {'surface': 'balances'});
      });
    }
    return const SizedBox.shrink();
  }

  /// Where Buying power sits, opened with its chevron.
  bool _split = false;

  /// The venues whose card is opened past its first rows ("See all").
  final Set<BalancesCategory> _expanded = {};

  /// A venue's rows folded: its first [kBalancesVenueRowsShown] open ones
  /// (only settled rows and nothing open: the first settled ones, never an
  /// empty card).
  static List<Widget> _folded(BalancesVenueList list) =>
      (list.rows.isEmpty ? list.settled : list.rows)
          .take(kBalancesVenueRowsShown)
          .toList();

  /// A venue's rows as its card lists them: folded, or, opened, every open
  /// row and then the settled ones.
  List<Widget> _shownRows(BalancesCategory category, BalancesVenueList list) =>
      _expanded.contains(category)
          ? [...list.rows, ...list.settled]
          : _folded(list);

  /// "See all  N ›" under a venue's first rows, "Show less" once opened;
  /// null when the folded card lists everything anyway.
  Widget? _foldRow(BalancesCategory category, BalancesVenueList list) {
    if (list.count <= _folded(list).length) return null;
    final open = _expanded.contains(category);
    return _FoldRow(
      key: ValueKey('portfolio-balance-${category.name}-see-all'),
      open: open,
      count: list.count,
      onTap: () {
        setState(
            () => open ? _expanded.remove(category) : _expanded.add(category));
        TrackingService.track('portfolio_venue_positions_expanded', params: {
          'venue': category.name,
          'open': !open,
        });
      },
    );
  }

  /// Both venues' positions were known once for this mount: from then on
  /// the venue area follows the figures, a refresh never brings the
  /// skeleton (or a venue's loading rows) back.
  bool _venuesKnown = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final entries = widget.entries;
    final money = widget.money;
    final categories = balancesCategories(entries);
    final shares = balancesShares(categories);
    final total = balancesTotal(categories);
    // Unknown: a dash, dimmed and sweeping, never a confident $0.00.
    BalancesFigure figure(BalancesCategoryFigure f) => f.usd == null
        ? const BalancesFigure('—', stale: true)
        : BalancesFigure(money(f.usd!), stale: f.stale, usd: f.usd);
    final totalFigure = total == null
        ? const BalancesFigure('—', stale: true)
        : BalancesFigure(money(total),
            stale: categories.values.any((f) => f.stale), usd: total);
    String label(BalancesCategory category) => switch (category) {
          BalancesCategory.buyingPower => l10n.portfolioBuyingPower,
          BalancesCategory.predictions => l10n.predictions,
          BalancesCategory.investing => l10n.trading,
        };
    BalancesEntry? entryOf(BalancesPart part) {
      for (final e in entries) {
        if (e.part == part) return e;
      }
      return null;
    }

    // What a venue holds is known: rows listed, or its list read and its
    // figures read this session (or the read on open done). Decided once
    // per mount ([_venuesKnown]), so only the first load waits on it.
    bool venueKnown(BalancesCategory category, BalancesEntry? e) {
      if (e == null) return true;
      final list = widget.venues[category] ?? BalancesVenueList.empty;
      if (list.any) return true;
      return !list.loading && (e.read || widget.firstReadDone);
    }

    // A venue with nothing to show: no positions and nothing held in open
    // orders. Asked only once the venues are known, so a refresh (a figure
    // shimmering, a list reloading) never turns it back into a header.
    bool venueEmpty(BalancesCategory category, BalancesEntry? e) {
      if (e == null) return true;
      final list = widget.venues[category] ?? BalancesVenueList.empty;
      final open = e.positionCount > 0 || list.any;
      final held = e.reservedCashUsd >= kBalancesCentUsd ||
          (!open &&
              e.positions?.usd != null &&
              e.atWorkUsd >= kBalancesCentUsd);
      return !open && !held;
    }

    Widget venue(BalancesCategory category, BalancesEntry e) {
      final list = widget.venues[category] ?? BalancesVenueList.empty;
      final open = e.positionCount > 0 || list.any;
      final f = figure(categories[category]!);
      // Nothing open: what open orders hold when that is all there is,
      // else "No open positions" in the header's place for a figure.
      final reserve = e.reservedCashUsd >= kBalancesCentUsd
          ? l10n.investingInOpenOrders(money(e.reservedCashUsd))
          : !open && e.positions?.usd != null && e.atWorkUsd >= kBalancesCentUsd
              ? l10n.investingInOpenOrders(money(e.atWorkUsd))
              : null;
      // Known (see [venueKnown]): nothing open is "No open positions",
      // whatever a refresh is doing to the figure.
      final empty = !open && reserve == null;
      return Column(
        key: ValueKey('portfolio-balance-venue-${category.name}'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          BalancesVenueHeader(
            key: ValueKey('portfolio-balance-category-${category.name}'),
            category: category,
            color: balancesCategoryColor(c, category),
            title: label(category),
            count: e.positionCount > 0 ? e.positionCount : null,
            figure: f,
            pnl: open ? list.pnl : null,
            empty: empty ? l10n.portfolioNoOpenPositions : null,
            caption: reserve,
          ),
          // A count the rows have not caught up with yet: their shimmer
          // rows; never an empty venue's while a refresh reloads its list.
          if (list.any || (open && list.loading))
            Padding(
              key: ValueKey('portfolio-balance-${category.name}-positions'),
              padding: EdgeInsets.only(top: 8.h),
              child: _VenueCard(
                  rows: _shownRows(category, list),
                  loading: list.loading,
                  fold: _foldRow(category, list)),
            ),
        ],
      );
    }

    final places = balancesBuyingPowerPlaces(entries);
    // A Rebalance note is never folded away.
    final split = _split || places.any((e) => e.footer.isNotEmpty);
    final predictions = entryOf(BalancesPart.predictions);
    final investing = entryOf(BalancesPart.investing);
    final buyingPower = figure(categories[BalancesCategory.buyingPower]!);
    final anyVenue = predictions != null || investing != null;
    if (!_venuesKnown &&
        venueKnown(BalancesCategory.predictions, predictions) &&
        venueKnown(BalancesCategory.investing, investing)) {
      _venuesKnown = true;
    }

    return Column(
      key: const ValueKey('portfolio-balance-overview'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: 8.h),
        if (widget.sharesHeader) ...[
          // The Portfolio screen's shares block (see [sharesHeader]).
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              BalancesRing(
                categories: categories.keys.toList(),
                shares: shares,
                diameter: kBalancesSharesRingDiameter,
                thickness: 9,
                semantics: [
                  '${l10n.total} ${totalFigure.text}',
                  if (shares.isNotEmpty)
                    for (final k in categories.keys)
                      '${label(k)} ${balancesPercent(shares[k] ?? 0)}',
                ].join(', '),
              ),
              SizedBox(width: 18.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final k in const [
                      BalancesCategory.investing,
                      BalancesCategory.predictions,
                      BalancesCategory.buyingPower,
                    ])
                      if (categories.containsKey(k))
                        _ShareRow(
                          key: ValueKey('portfolio-share-${k.name}'),
                          color: balancesCategoryColor(c, k),
                          label: k == BalancesCategory.buyingPower
                              ? l10n.assetDollars
                              : label(k),
                          figure: figure(categories[k]!),
                          share: shares.isEmpty ? null : shares[k] ?? 0,
                        ),
                  ],
                ),
              ),
            ],
          ),
          // Move money, right-aligned under the shares (founder, 31
          // October 2026: "where is the button to move money?"): the
          // Dollars tab's own pill, always on, whatever the balance.
          SizedBox(height: 12.h),
          Align(
            alignment: Alignment.centerRight,
            child: KutePill(
              key: const ValueKey('portfolio-move-money'),
              label: l10n.moveTransfer,
              size: KutePillSize.large,
              selected: true,
              link: true,
              onTap: () {
                TrackingService.track('portfolio_move_money_tapped',
                    params: const {'surface': 'portfolio'});
                unawaited(showMoneyMovementSheet(context));
              },
            ),
          ),
        ] else ...[
        // The lead row (founder, 31 October 2026: "the ring belongs to
        // Available to invest"): the small bare ring LEADS the line
        // itself (the hero above carries the total), then "● Available to
        // invest" with its amount and chevron on that same line, so the
        // ring, the label and the amount read as one row; Move money
        // under the label, starting where it does. Nothing hangs in the
        // margin on its own.
        BalancesLead(
          key: const ValueKey('portfolio-balance-category-buyingPower'),
          toggleKey: const ValueKey('portfolio-balance-split-toggle'),
          amountKey:
              const ValueKey('portfolio-balance-category-buyingPower-amount'),
          leading: BalancesRing(
            categories: categories.keys.toList(),
            shares: shares,
            semantics: [
              '${l10n.total} ${totalFigure.text}',
              if (shares.isNotEmpty)
                for (final k in categories.keys)
                  '${label(k)} ${balancesPercent(shares[k] ?? 0)}',
            ].join(', '),
          ),
          color: balancesCategoryColor(c, BalancesCategory.buyingPower),
          label: l10n.portfolioBuyingPower,
          figure: buyingPower,
          open: split,
          onToggle: places.any((e) => e.footer.isNotEmpty)
              ? null
              : () {
                  setState(() => _split = !_split);
                  TrackingService.track(
                      'portfolio_available_to_invest_toggled',
                      params: {'open': _split});
                },
        ),
        if (widget.action case final action?)
          Padding(
            padding: EdgeInsetsDirectional.only(
                start: balancesLeadInset(), top: 8.h),
            child: Align(
                alignment: AlignmentDirectional.centerStart, child: action),
          ),
        // Where the cash sits, opened in place.
        AnimatedSize(
          duration:
              kuteReduceMotion(context) ? Duration.zero : KuteMotion.chipDuration,
          curve: kuteReduceMotion(context) ? Curves.linear : KuteMotion.chip,
          alignment: Alignment.topCenter,
          child: split
              ? Padding(
                  key: const ValueKey('portfolio-balance-split'),
                  padding: EdgeInsets.only(top: 8.h),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final e in places)
                        _wrap(
                            e.part,
                            _PlaceRow(
                              key: ValueKey('portfolio-balance-${e.id}'),
                              entry: e,
                              cash: e.cash.usd == null
                                  ? const BalancesFigure('—', stale: true)
                                  : e.cash,
                            )),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        if (widget.steps case final steps?) steps,
        ],
        SizedBox(height: 16.h),
        // The first load: the venue card's skeleton rows until both
        // venues' positions are known, never headers that then go.
        if (anyVenue && !_venuesKnown)
          Padding(
            key: const ValueKey('portfolio-balance-venues-loading'),
            padding: EdgeInsets.only(top: 14.h),
            child: const _VenueCard(rows: [], loading: true, skeletonRows: 3),
          )
        // Nothing open anywhere: Sal's empty state, not two empty venue
        // rows (founder, 27 October 2026).
        else if (anyVenue &&
            venueEmpty(BalancesCategory.predictions, predictions) &&
            venueEmpty(BalancesCategory.investing, investing)) ...[
          _emptyShownOnce(),
          Padding(
            key: const ValueKey('portfolio-balance-no-positions'),
            padding: EdgeInsets.symmetric(vertical: 24.h),
            child: NoActivityState(
                title: l10n.portfolioNoOpenPositions, cycles: 3, compact: true),
          ),
        ] else if (anyVenue) ...[
          if (predictions != null)
            venue(BalancesCategory.predictions, predictions),
          // Room for the card's soft shadow, which falls below it.
          if (predictions != null && investing != null) SizedBox(height: 10.h),
          if (investing != null) venue(BalancesCategory.investing, investing),
        ],
      ],
    );
  }

  Widget _wrap(BalancesPart part, Widget row) =>
      widget.wrap?.call(part, row) ?? row;
}

/// The row padding inside a venue's card, the grouped lists' own.
const double _kCardInset = 16;

/// A venue's positions in one grouped card, as the Investing and
/// Predictions lists draw theirs (market_groups.dart): the group's
/// surface, radius and soft shadow, Home's inset hairline between rows
/// (starting where a row's text does), the rows' press ink clipped to the
/// corners; shimmer rows while the venue is read with nothing listed.
class _VenueCard extends StatelessWidget {
  const _VenueCard(
      {required this.rows,
      required this.loading,
      this.skeletonRows = 2,
      this.fold});

  final List<Widget> rows;
  final bool loading;

  /// "See all" / "Show less" after the rows, past the same hairline.
  final Widget? fold;

  /// How many shimmer rows [loading] draws.
  final int skeletonRows;

  @override
  Widget build(BuildContext context) {
    final inset = _kCardInset.w;
    return DecoratedBox(
      decoration: PremiumGroupContainer.decorationOf(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(PremiumGroupContainer.radius),
        child: PortfolioRowInset(
          horizontal: inset,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0)
                  marketGroupDivider(context,
                      inset + (kPortfolioRowImage + kPortfolioRowGap).w),
                rows[i],
              ],
              if (loading)
                SkeletonRowList(
                    count: skeletonRows,
                    padding:
                        EdgeInsets.symmetric(horizontal: inset, vertical: 8.h),
                    rowPadding: EdgeInsets.symmetric(vertical: 10.h)),
              if (fold case final f?) ...[
                if (rows.isNotEmpty)
                  marketGroupDivider(context,
                      inset + (kPortfolioRowImage + kPortfolioRowGap).w),
                f,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// "See all  N ›" at the foot of a venue's card ("Show less" once
/// opened): the outcome lists' quiet fold row (market_detail_sheet.dart,
/// "Show N more"), its text where the rows' titles start, the count in the
/// venue header's quieter tone.
class _FoldRow extends StatelessWidget {
  const _FoldRow(
      {super.key,
      required this.open,
      required this.count,
      required this.onTap});

  final bool open;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final style = TextStyle(
      color: c.textSecondary,
      fontSize: 13.sp,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final label = open ? l10n.salShowLess : l10n.seeAll;
    return Semantics(
      button: true,
      expanded: open,
      label: open ? label : '$label, $count',
      excludeSemantics: true,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: EdgeInsetsDirectional.only(
              start: PortfolioRowInset.of(context) +
                  (kPortfolioRowImage + kPortfolioRowGap).w,
              top: 12.h,
              bottom: 12.h),
          child: Row(
            children: [
              Text(label, style: style),
              if (!open) ...[
                SizedBox(width: 6.w),
                Text('$count',
                    key: const ValueKey('portfolio-balance-see-all-count'),
                    style: style.copyWith(
                        color: c.textTertiary, fontWeight: FontWeight.w500)),
              ],
              SizedBox(width: 2.w),
              Icon(
                  open
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.chevron_right_rounded,
                  size: 16.w,
                  color: c.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

/// The dot before a category's name.
const double kBalancesDot = 8;

/// A section's title: Available to invest, Predictions, Investing, all the
/// same size (founder, 27 October 2026), a step larger than the rows.
TextStyle balancesSectionTitle(BuildContext context) =>
    AppTextStyles.settingsTitle(context).copyWith(
        fontSize: 18.sp,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        height: 1.25);

/// A venue's text starts after its dot and this gap; its rows and the
/// places under Buying power line up with it.
const double kBalancesDotGap = 12;

/// Where a venue's sub-rows start: after the dot and its gap.
double balancesSubRowInset() => (kBalancesDot + kBalancesDotGap).w;

/// Where the lead line's label starts: past the ring and the dot (Move
/// money sits here, under the label).
double balancesLeadInset() =>
    (kBalancesRingDiameter + kBalancesRingGap + kBalancesDot + kBalancesDotGap)
        .w;

/// The amount at the end of a header row: Available to invest's, a
/// venue's value, the P&L charts' Open P&L.
TextStyle balancesHeaderAmount(BuildContext context, {Color? color}) =>
    TextStyle(
      color: color ?? context.colors.textPrimary,
      fontSize: 16.sp,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
      height: 1.25,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

/// A quiet line's style: a sub-row's label and figure, a header's "No
/// open positions".
TextStyle balancesQuiet(BuildContext context, {double? fontSize}) => TextStyle(
      color: context.colors.textSecondary,
      fontSize: fontSize ?? 13.sp,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.1,
      height: 1.3,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

/// A live figure: a new value rolls the digits that changed; while it
/// refreshes (or is not known yet) it is dimmed with the skeleton's sweep.
class BalancesLiveFigure extends StatelessWidget {
  const BalancesLiveFigure(
      {super.key, required this.figure, required this.style});

  final BalancesFigure figure;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => StaleShimmer(
        stale: figure.stale,
        child: RollingFigure(
            text: figure.text,
            style: figure.stale
                ? style.copyWith(color: context.colors.textSecondary)
                : style),
      );
}

/// An amount at the end of a row, scaled down rather than cut.
class BalancesEndFigure extends StatelessWidget {
  const BalancesEndFigure(
      {super.key, required this.figure, required this.style});

  final BalancesFigure figure;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerEnd,
        child: BalancesLiveFigure(figure: figure, style: style),
      );
}

/// The dot before a category's name, in its colour.
class BalancesDot extends StatelessWidget {
  const BalancesDot({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: kBalancesDot.w,
        height: kBalancesDot.w,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

/// A P&L beside a venue's value: "+$1.10 (12.4%)" or "−$0.40 (3.1%)" in
/// the result colour, the percentage against what was paid ([costUsd], as
/// the rows read theirs; left out when it is not known); nothing when the
/// P&L is under a cent. [money] writes the amount.
class BalancesPnlText extends StatelessWidget {
  const BalancesPnlText(
      {super.key,
      required this.usd,
      required this.money,
      this.costUsd,
      this.figureKey = const ValueKey('portfolio-balance-venue-pnl')});

  final double usd;
  final String Function(double usd) money;
  final double? costUsd;

  /// The key on the figure itself (the tests read it).
  final Key figureKey;

  /// "37.9%", one decimal like the rows; null without a cost to divide by.
  static String? percentOf(double usd, double? costUsd) {
    final cost = costUsd;
    if (cost == null || !cost.isFinite || cost < kBalancesCentUsd) return null;
    final pct = (usd / cost * 100).abs();
    return pct.isFinite ? '${pct.toStringAsFixed(1)}%' : null;
  }

  @override
  Widget build(BuildContext context) {
    if (!usd.isFinite || usd.abs() < kBalancesCentUsd) {
      return const SizedBox.shrink();
    }
    final up = usd > 0;
    final pct = percentOf(usd, costUsd);
    return Padding(
      padding: EdgeInsetsDirectional.only(start: 6.w),
      child: RollingFigure(
        key: figureKey,
        text: '${up ? '+' : '−'}${money(usd.abs())}'
            '${pct == null ? '' : ' ($pct)'}',
        style: TextStyle(
          color: up ? AppColors.marketUp : AppColors.marketDown,
          fontSize: 13.sp,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
          height: 1.25,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// The ring: one slice per non-empty category in its colour, nothing in
/// the hole (the hero above the pills shows the total; screen readers
/// still hear it). Only the track while a figure is unknown. Not a
/// control. [chartKey] is the chart's own key (the tests read it).
class BalancesRing extends StatelessWidget {
  const BalancesRing({
    super.key,
    required this.categories,
    required this.shares,
    required this.semantics,
    this.chartKey = const ValueKey('portfolio-balance-ring'),
    this.diameter = kBalancesRingDiameter,
    this.thickness = kBalancesRingThickness,
  });

  final List<BalancesCategory> categories;
  final Map<BalancesCategory, double> shares;
  final String semantics;
  final Key chartKey;

  /// Design units; the Portfolio screen's shares block draws it larger.
  final double diameter;
  final double thickness;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      container: true,
      label: semantics,
      excludeSemantics: true,
      child: IgnorePointer(
        child: KuteDonutChart(
          key: chartKey,
          diameter: diameter.w,
          thickness: thickness.w,
          trackColor: context.isDark ? c.surfaceLight : c.surfaceElevated,
          onSelected: (_) {},
          segments: [
            for (final k in categories)
              if ((shares[k] ?? 0) > 0)
                KuteDonutSegment(
                  id: k,
                  value: shares[k]!,
                  color: balancesCategoryColor(c, k),
                  semanticsLabel: '',
                ),
          ],
        ),
      ),
    );
  }
}

/// The lead line: [leading] (the ring) first, then "● Available to
/// invest" (the venues' title size; the dot only with a [color]) with its
/// amount at the line's end, in [amountColor], and a chevron after it
/// when a tap opens something ([onToggle]; null: nothing to open, or held
/// open by a note).
class BalancesLead extends StatelessWidget {
  const BalancesLead({
    super.key,
    this.leading,
    this.color,
    required this.label,
    required this.figure,
    this.open = false,
    this.onToggle,
    this.amountColor,
    this.toggleKey,
    this.amountKey,
  });

  /// What leads the line (the ring); null for the dot alone.
  final Widget? leading;
  final Color? color;
  final String label;
  final BalancesFigure figure;
  final bool open;
  final VoidCallback? onToggle;
  final Color? amountColor;
  final Key? toggleKey;
  final Key? amountKey;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dot = color;
    return Semantics(
      button: onToggle != null,
      expanded: open,
      label: '$label, ${figure.text}',
      excludeSemantics: true,
      child: GestureDetector(
        key: toggleKey,
        behavior: HitTestBehavior.opaque,
        onTap: onToggle,
        child: Row(
          children: [
            if (leading != null) ...[
              leading!,
              SizedBox(width: kBalancesRingGap.w),
            ],
            if (dot != null) ...[
              BalancesDot(color: dot),
              SizedBox(width: kBalancesDotGap.w),
            ],
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: balancesSectionTitle(context)),
            ),
            SizedBox(width: 12.w),
            // The amount at the line's end, scaled down rather than cut.
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 150.w),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerEnd,
                child: BalancesLiveFigure(
                  key: amountKey,
                  figure: figure,
                  style: balancesHeaderAmount(context, color: amountColor),
                ),
              ),
            ),
            if (onToggle != null) ...[
              SizedBox(width: 2.w),
              AnimatedRotation(
                turns: open ? 0.5 : 0,
                duration: kuteReduceMotion(context)
                    ? Duration.zero
                    : KuteMotion.chipDuration,
                curve:
                    kuteReduceMotion(context) ? Curves.linear : KuteMotion.chip,
                child: Icon(Icons.keyboard_arrow_down_rounded,
                    size: 18.w, color: c.textTertiary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One share in the Portfolio screen's top block: "● Investing
/// $1,126.50 · 64%", the amount tabular in the category's colour's row.
class _ShareRow extends StatelessWidget {
  const _ShareRow({
    super.key,
    required this.color,
    required this.label,
    required this.figure,
    required this.share,
  });

  final Color color;
  final String label;
  final BalancesFigure figure;
  final double? share;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final amount = TextStyle(
      color: c.textPrimary,
      fontSize: 15.sp,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.2,
      height: 1.25,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Semantics(
      label: '$label, ${figure.text}'
          '${share == null ? '' : ', ${balancesPercent(share!)}'}',
      excludeSemantics: true,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 4.h),
        child: Row(
          children: [
            BalancesDot(color: color),
            SizedBox(width: kBalancesDotGap.w),
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: balancesSectionTitle(context)),
            ),
            SizedBox(width: 8.w),
            BalancesLiveFigure(figure: figure, style: amount),
            if (share != null)
              Text(' · ${balancesPercent(share!)}',
                  style: amount.copyWith(
                      color: c.textSecondary, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

/// A venue's header: its dot, name and count, its value and P&L at the
/// end ("No open positions" in their place when nothing is held), what
/// open orders hold under it ([caption]). [keyPrefix] names its parts'
/// keys (`<prefix>-<category>-amount`, `-count`, `-line`, `-caption`);
/// [figureColor] colours the value (the P&L charts' realised P&L).
class BalancesVenueHeader extends StatelessWidget {
  const BalancesVenueHeader({
    super.key,
    required this.category,
    required this.color,
    required this.title,
    required this.count,
    required this.figure,
    required this.pnl,
    required this.empty,
    required this.caption,
    this.figureColor,
    this.keyPrefix = 'portfolio-balance-category',
  });

  final BalancesCategory category;
  final Color color;
  final String title;
  final int? count;
  final BalancesFigure figure;
  final Widget? pnl;
  final String? empty;
  final String? caption;
  final Color? figureColor;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final quiet = balancesQuiet(context);
    final titleStyle = balancesSectionTitle(context);
    final name = category.name;
    return Semantics(
      container: true,
      label: [
        title,
        if (count != null) '$count',
        empty ?? figure.text,
        if (caption != null) caption!,
      ].join(', '),
      excludeSemantics: true,
      child: Padding(
        padding: EdgeInsets.only(top: 14.h, bottom: 4.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                BalancesDot(color: color),
                SizedBox(width: kBalancesDotGap.w),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: titleStyle),
                      ),
                      if (count case final n?) ...[
                        SizedBox(width: 8.w),
                        Text('$n',
                            key: ValueKey('$keyPrefix-$name-count'),
                            style: titleStyle.copyWith(
                                color: c.textTertiary,
                                fontWeight: FontWeight.w500,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ])),
                      ],
                    ],
                  ),
                ),
                SizedBox(width: 12.w),
                if (empty case final text?)
                  Text(text,
                      key: ValueKey('$keyPrefix-$name-line'),
                      maxLines: 1,
                      style: quiet)
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: 210.w),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerEnd,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          BalancesLiveFigure(
                            key: ValueKey('$keyPrefix-$name-amount'),
                            figure: figure,
                            style: balancesHeaderAmount(context,
                                color: figureColor),
                          ),
                          if (pnl case final p?) p,
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            if (caption case final text?) ...[
              SizedBox(height: 2.h),
              Padding(
                padding:
                    EdgeInsetsDirectional.only(start: balancesSubRowInset()),
                child: Text(text,
                    key: ValueKey('$keyPrefix-$name-caption'),
                    style: quiet.copyWith(color: c.textTertiary)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A quiet indented line under a header: a [label] and its [figure] at
/// the end (where spare cash sits under Buying power, a venue's statistic
/// under its header on P&L charts), any [notes] under it in a smaller
/// tertiary line. [figureStyle] colours the figure (a P&L).
class BalancesSubRow extends StatelessWidget {
  const BalancesSubRow({
    super.key,
    required this.label,
    required this.figure,
    this.notes = const [],
    this.figureColor,
    this.amountKey,
  });

  final String label;
  final BalancesFigure figure;
  final List<String> notes;
  final Color? figureColor;
  final Key? amountKey;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = balancesQuiet(context, fontSize: 14.sp);
    return Semantics(
      container: true,
      label: [label, figure.text, ...notes].join(', '),
      excludeSemantics: true,
      child: Padding(
        padding: EdgeInsetsDirectional.only(
            start: balancesSubRowInset(), top: 4.h, bottom: 4.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style),
                ),
                SizedBox(width: 12.w),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 150.w),
                  child: BalancesEndFigure(
                    key: amountKey,
                    figure: figure,
                    style: figureColor == null
                        ? style
                        : style.copyWith(color: figureColor),
                  ),
                ),
              ],
            ),
            for (final note in notes) ...[
              SizedBox(height: 2.h),
              Text(note,
                  style:
                      style.copyWith(color: c.textTertiary, fontSize: 13.sp)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Where spare cash sits: a quiet indented line under Buying power, the
/// account's name and its cash, any Rebalance note under it.
class _PlaceRow extends StatelessWidget {
  const _PlaceRow({super.key, required this.entry, required this.cash});

  final BalancesEntry entry;
  final BalancesFigure cash;

  @override
  Widget build(BuildContext context) => BalancesSubRow(
        label: entry.name,
        figure: cash,
        notes: entry.footer,
        amountKey: ValueKey('portfolio-balance-${entry.id}-amount'),
      );
}
