// lib/screens/analytics/components/money_in_out.dart
//
// The Bitcoin home's "In & out" tab (the analytics strip's third pill,
// AnalyticsTab.breakdown): the spending wallet's bitcoin that came in and
// went out, a month or a year at a time, in plain words (founder, October
// 2026: the all-time donut by rail "means nothing").
//
//   * Header: the period's name ("October", "2026") and the app's small
//     Month | Year pills.
//   * In and Out side by side, each label behind a dot of its chart
//     colour (the app's chart palette: In teal, Out indigo, founder
//     2026-10-28: "the same colour palette as the rest"): +amount and
//     −amount in the primary text colour, as Balances writes figures,
//     each with its other unit under it (fiat under bitcoin, or bitcoin under fiat when the person picked
//     fiat as the main denomination); sats or BTC as everywhere else.
//     Tapping a side lists it below; the picked side sits on the inset
//     tone, the legend rows' selected treatment.
//   * Bars: a pair per period (the last six months, or each year since
//     the first move), In teal and Out indigo, the
//     picked period's pair at full strength and the others faded. Tapping
//     a pair picks its period.
//   * "Where it went" (Out) or "Where it came from" (In): one row per
//     category with money in it, largest first: a round icon, a dot and
//     the name over a thin share bar in the chart palette by rank of size
//     (chartColorsByShare, as the old donut legend), and the amount. Never a rail, an address or a
//     counterparty (services/portfolio/money_in_out.dart).
//   * A period with nothing in it: Sal's compact empty state; a wallet
//     with nothing at all: only Sal.
//   * Hidden balances mask every figure.
//   * Analytics: `bitcoin_in_out_period_changed` {period, offset} and
//     `bitcoin_in_out_side_changed` {side}, fixed ids only; the strip's own
//     `analytics_tab_selected` (tab: breakdown) is unchanged.
//
// Only the hot spending wallet has these flows; hardware, Ledger,
// watch-only, external-address and other on-chain wallets never mount it.

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart' show WalletConfig;
import 'package:kute/models/transactions_model.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/transactions_provider.dart';
import 'package:kute/screens/polymarket/components/market_card.dart'
    show polyCardCaptionStyle, polyCardFigureStyle, polyCardTitleStyle;
import 'package:kute/screens/shared/kute_motion.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/screens/shared/no_activity_state.dart';
import 'package:kute/screens/shared/transactions_builder.dart'
    show activityOwnSettleAddresses, assembleActivityRows;
import 'package:kute/services/portfolio/money_in_out.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// A category's name on [side], in plain words.
String moneyCategoryLabel(
        AppLocalizations l10n, MoneySide side, MoneyCategory category) =>
    switch ((side, category)) {
      (MoneySide.moneyOut, MoneyCategory.people) => l10n.inOutSentToPeople,
      (MoneySide.moneyOut, MoneyCategory.investments) =>
        l10n.inOutIntoInvestments,
      (MoneySide.moneyOut, MoneyCategory.dollars) => l10n.inOutIntoDollars,
      (MoneySide.moneyIn, MoneyCategory.people) => l10n.inOutFromPeople,
      (MoneySide.moneyIn, MoneyCategory.investments) =>
        l10n.inOutFromInvestments,
      (MoneySide.moneyIn, MoneyCategory.dollars) => l10n.inOutFromDollars,
      (_, MoneyCategory.fees) => l10n.fees,
      (_, MoneyCategory.bought) => l10n.inOutBought,
    };

/// A category's glyph, in the icon family of the app's tabs.
IconData moneyCategoryIcon(MoneyCategory category) => switch (category) {
      MoneyCategory.people => Icons.person_rounded,
      MoneyCategory.investments => Icons.trending_up_rounded,
      MoneyCategory.dollars => Icons.attach_money_rounded,
      MoneyCategory.fees => Icons.percent_rounded,
      MoneyCategory.bought => Icons.shopping_bag_rounded,
    };

/// Home's In & out tab for [wallet]: the hot spending wallet's money in
/// and out, or null (no tab) for any other kind of wallet.
Widget? homeBreakdownChild(WalletConfig? wallet) =>
    (wallet?.isSparkWallet ?? false) ? const MoneyInOut() : null;

class MoneyInOut extends ConsumerStatefulWidget {
  /// The moment "this month" is read from; null is now (tests and renders
  /// pin it).
  final DateTime? now;

  const MoneyInOut({super.key, this.now});

  @override
  ConsumerState<MoneyInOut> createState() => _MoneyInOutState();
}

class _MoneyInOutState extends ConsumerState<MoneyInOut> {
  MoneyPeriodKind _kind = MoneyPeriodKind.month;

  /// Periods back from the current one (0 = this month or this year).
  int _offset = 0;
  MoneySide _side = MoneySide.moneyOut;

  // The last fold, kept while the wallet's rows are the same list (the
  // assembly is Activity's, not free to redo every frame).
  List<BaseTransaction>? _memoRows;
  Set<String>? _memoOwn;
  List<MoneyMove> _moves = const [];

  List<MoneyMove> _movesOf(List<BaseTransaction> sorted, Set<String> own) {
    if (identical(sorted, _memoRows) && setEquals(own, _memoOwn)) {
      return _moves;
    }
    _memoRows = sorted;
    _memoOwn = own;
    final rows = assembleActivityRows(
      sorted,
      ownAddresses: own,
      isHardwareOrWatchOnly: false,
      onlyUsdb: false,
      keepVenueMoves: true,
    );
    return _moves = moneyMoves(rows, everyRow: sorted);
  }

  void _pickKind(MoneyPeriodKind kind) {
    if (kind == _kind) return;
    HapticFeedback.selectionClick();
    setState(() {
      _kind = kind;
      _offset = 0;
    });
    _reportPeriod();
  }

  void _pickOffset(int offset) {
    if (offset == _offset) return;
    HapticFeedback.selectionClick();
    setState(() => _offset = offset);
    _reportPeriod();
  }

  void _pickSide(MoneySide side) {
    if (side == _side) return;
    HapticFeedback.selectionClick();
    setState(() => _side = side);
    TrackingService.track('bitcoin_in_out_side_changed',
        params: {'side': side.analyticsName});
  }

  void _reportPeriod() {
    TrackingService.track('bitcoin_in_out_period_changed',
        params: {'period': _kind.name, 'offset': _offset});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    // The spending account's rows, read the way the Activity tab beside
    // this one reads them.
    final activeId =
        ref.watch(settingsProvider.select((s) => s.activeWalletId));
    final cache = ref.watch(walletTransactionCacheProvider);
    final sorted =
        (activeId != null ? cache[activeId] : null)?.allTransactionsSorted ??
            const <BaseTransaction>[];
    final moves = _movesOf(sorted, activityOwnSettleAddresses(ref));
    if (moves.isEmpty) {
      return NoActivityState(
        key: const ValueKey('in-out-empty'),
        compact: true,
        cycles: 1,
        title: l10n.inOutEmpty,
      );
    }

    final now = widget.now ?? DateTime.now();
    final count = moneyPeriodCount(_kind, now, moves);
    final offset = _offset.clamp(0, count - 1);
    // Oldest on the left, the current period on the right.
    final periods = [
      for (var back = count - 1; back >= 0; back--)
        MoneyPeriod.back(_kind, now, back),
    ];
    final totals = [for (final p in periods) moneyTotals(moves, p)];
    final selectedIndex = count - 1 - offset;
    final selected = totals[selectedIndex];
    final locale = l10n.localeName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _periodName(periods[selectedIndex], now, locale),
                key: const ValueKey('in-out-period'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: polyCardTitleStyle(c),
              ),
            ),
            KutePill(
              key: const ValueKey('in-out-month'),
              label: l10n.inOutMonth,
              size: KutePillSize.compact,
              selected: _kind == MoneyPeriodKind.month,
              onTap: () => _pickKind(MoneyPeriodKind.month),
            ),
            SizedBox(width: 4.w),
            KutePill(
              key: const ValueKey('in-out-year'),
              label: l10n.inOutYear,
              size: KutePillSize.compact,
              selected: _kind == MoneyPeriodKind.year,
              onTap: () => _pickKind(MoneyPeriodKind.year),
            ),
          ],
        ),
        Container(
          margin: EdgeInsets.only(top: 8.h),
          padding: EdgeInsets.all(16.w),
          decoration: AppDecorations.card(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (selected.isEmpty)
                NoActivityState(
                  key: const ValueKey('in-out-period-empty'),
                  compact: true,
                  cycles: 1,
                  title: l10n.inOutEmpty,
                  padding: EdgeInsets.only(bottom: 8.h),
                )
              else
                Row(
                  children: [
                    for (final side in const [
                      MoneySide.moneyIn,
                      MoneySide.moneyOut
                    ]) ...[
                      if (side == MoneySide.moneyOut) SizedBox(width: 8.w),
                      Expanded(
                        child: _SideFigure(
                          key: ValueKey('in-out-side-${side.analyticsName}'),
                          side: side,
                          sats: selected.totalOf(side),
                          selected: side == _side,
                          onTap: () => _pickSide(side),
                        ),
                      ),
                    ],
                  ],
                ),
              SizedBox(height: 16.h),
              _Bars(
                totals: totals,
                labels: [
                  for (final p in periods) _barLabel(p, locale),
                ],
                selectedIndex: selectedIndex,
                onTap: (i) => _pickOffset(count - 1 - i),
              ),
              if (selected.totalOf(_side) > 0) ...[
                SizedBox(height: 20.h),
                Text(
                  _side == MoneySide.moneyOut
                      ? l10n.inOutWhereItWent
                      : l10n.inOutWhereItCameFrom,
                  key: const ValueKey('in-out-where'),
                  style: polyCardCaptionStyle(c),
                ),
                SizedBox(height: 4.h),
                SelectionFade(
                  selection: (_side, _kind, offset),
                  child: Builder(builder: (context) {
                    final rows = selected.rowsOf(_side);
                    final total = selected.totalOf(_side);
                    final shares = [for (final r in rows) r.value / total];
                    // The chart palette by rank of size, as the old donut
                    // legend; slivers wear the palette's grey.
                    final colors = c.chartColorsByShare(shares);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < rows.length; i++)
                          _CategoryRow(
                            key: ValueKey(
                                'in-out-row-${_side.analyticsName}-${rows[i].key.name}'),
                            side: _side,
                            category: rows[i].key,
                            sats: rows[i].value,
                            share: shares[i],
                            color: colors[i],
                          ),
                      ],
                    );
                  }),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The header's name of [period]: "October" (with its year once it is
/// another year's), or "2026".
String _periodName(MoneyPeriod period, DateTime now, String locale) {
  String format(DateFormat Function(String? l) f) {
    try {
      return f(locale).format(period.start);
    } catch (_) {
      // Date symbols not loaded for this locale (tests, early start).
      return f(null).format(period.start);
    }
  }

  return switch (period.kind) {
    MoneyPeriodKind.year => format(DateFormat.y),
    MoneyPeriodKind.month => period.start.year == now.toLocal().year
        ? format(DateFormat.LLLL)
        : format(DateFormat.yMMMM),
  };
}

/// A bar's caption: "Oct", or "2026".
String _barLabel(MoneyPeriod period, String locale) {
  final f = period.kind == MoneyPeriodKind.year ? DateFormat.y : DateFormat.LLL;
  try {
    return f(locale).format(period.start);
  } catch (_) {
    return f(null).format(period.start);
  }
}

/// [sats] in the person's main denomination, and in the other one.
({String main, String other}) _money(WidgetRef ref, int sats) {
  final fiatFirst = ref.watch(
      settingsProvider.select((s) => s.mainDenomination == 'fiat'));
  final bitcoin = ref.watch(conversionProvider(sats));
  final fiat = ref.watch(conversionToFiatProvider(sats));
  return fiatFirst
      ? (main: fiat, other: bitcoin)
      : (main: bitcoin, other: fiat);
}

const _masked = '••••••';

/// A side's chart colour: In the palette's teal, Out its indigo (the two
/// first hues of `chartCategorical`, light and dark alike).
Color moneySideColor(AppColorsExtension c, MoneySide side) =>
    side == MoneySide.moneyIn ? c.chartCategorical[1] : c.chartCategorical[0];

/// The legend's dot: the old donut legend's 8 pt circle.
class _Dot extends StatelessWidget {
  final Color color;
  const _Dot(this.color);

  @override
  Widget build(BuildContext context) => Container(
        width: 8.w,
        height: 8.w,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

/// One side's total: a dot of the side's chart colour and "In" over
/// +amount, or "Out" over −amount, in the primary text colour, the other
/// unit under it. The picked side sits on
/// the inset tone.
class _SideFigure extends ConsumerWidget {
  final MoneySide side;
  final int sats;
  final bool selected;
  final VoidCallback onTap;

  const _SideFigure({
    super.key,
    required this.side,
    required this.sats,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final l10n = context.l10n;
    final visible =
        ref.watch(settingsProvider.select((s) => s.balanceVisible));
    final money = _money(ref, sats);
    final isIn = side == MoneySide.moneyIn;
    final caption = polyCardCaptionStyle(c).copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final radius = BorderRadius.circular(AppRadius.sm);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: AnimatedContainer(
            duration: kuteMotion(context, kSelectionFadeDuration),
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 10.h),
            decoration: BoxDecoration(
              color: selected ? c.surfaceLight : Colors.transparent,
              borderRadius: radius,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _Dot(moneySideColor(c, side)),
                    SizedBox(width: 6.w),
                    Text(
                      isIn ? l10n.inOutIn : l10n.inOutOut,
                      style: caption.copyWith(
                        color: selected ? c.textPrimary : c.textTertiary,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 4.h),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    visible
                        ? '${isIn ? '+' : '−'}${money.main}'
                        : _masked,
                    maxLines: 1,
                    style: polyCardFigureStyle(c.textPrimary),
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  visible ? money.other : _masked,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: caption.copyWith(color: c.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The pairs of bars, one per period: In (teal) beside Out (indigo), on
/// one scale. The picked pair is at full strength, the
/// others faded; a period with nothing in it keeps a hairline stub so
/// the row never has a hole.
class _Bars extends StatelessWidget {
  final List<MoneyTotals> totals;
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onTap;

  const _Bars({
    required this.totals,
    required this.labels,
    required this.selectedIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final height = 72.h;
    var top = 0;
    for (final t in totals) {
      if (t.totalIn > top) top = t.totalIn;
      if (t.totalOut > top) top = t.totalOut;
    }
    final duration = kuteMotion(context, const Duration(milliseconds: 220));
    Widget bar(int value, Color color, bool picked) {
      final h = top <= 0 || value <= 0
          ? 2.0
          : (value / top * height).clamp(3.0, height).toDouble();
      return AnimatedContainer(
        duration: duration,
        curve: Curves.easeOutCubic,
        width: 8.w,
        height: h,
        decoration: BoxDecoration(
          color: value <= 0
              ? c.border
              : color.withValues(alpha: picked ? 1 : 0.28),
          borderRadius: BorderRadius.vertical(top: Radius.circular(3.r)),
        ),
      );
    }

    final caption = polyCardCaptionStyle(c).copyWith(fontSize: 12.sp);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < totals.length; i++)
          Expanded(
            child: Semantics(
              button: true,
              selected: i == selectedIndex,
              label: labels[i],
              child: GestureDetector(
                key: ValueKey('in-out-bar-$i'),
                behavior: HitTestBehavior.opaque,
                onTap: () => onTap(i),
                child: Column(
                  children: [
                    SizedBox(
                      height: height,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          bar(totals[i].totalIn,
                              moneySideColor(c, MoneySide.moneyIn),
                              i == selectedIndex),
                          SizedBox(width: 3.w),
                          bar(totals[i].totalOut,
                              moneySideColor(c, MoneySide.moneyOut),
                              i == selectedIndex),
                        ],
                      ),
                    ),
                    SizedBox(height: 6.h),
                    ExcludeSemantics(
                      child: Text(
                        labels[i],
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: i == selectedIndex
                            ? caption.copyWith(
                                color: c.textPrimary,
                                fontWeight: FontWeight.w600)
                            : caption,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// One "Where it went" line: the category's round icon, a dot and its
/// name over a thin share bar in its chart colour, and the amount.
class _CategoryRow extends ConsumerWidget {
  final MoneySide side;
  final MoneyCategory category;
  final int sats;

  /// The row's share of its side's total, 0 to 1.
  final double share;

  /// The row's chart colour (by rank of size).
  final Color color;

  const _CategoryRow({
    super.key,
    required this.side,
    required this.category,
    required this.sats,
    required this.share,
    required this.color,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final visible =
        ref.watch(settingsProvider.select((s) => s.balanceVisible));
    final caption = polyCardCaptionStyle(c).copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return MergeSemantics(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 8.h),
        child: Row(
          children: [
            Container(
              width: 32.sp,
              height: 32.sp,
              decoration: BoxDecoration(
                color: c.surfaceLight,
                shape: BoxShape.circle,
              ),
              child: Icon(moneyCategoryIcon(category),
                  size: 16.sp, color: c.textPrimary),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _Dot(color),
                      SizedBox(width: 8.w),
                      Flexible(
                        child: Text(
                          moneyCategoryLabel(context.l10n, side, category),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: caption.copyWith(
                              color: c.textPrimary,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 6.h),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2.r),
                    child: SizedBox(
                      height: 3.h,
                      child: Stack(
                        children: [
                          Positioned.fill(
                              child: ColoredBox(color: c.surfaceLight)),
                          FractionallySizedBox(
                            widthFactor: share.clamp(0.0, 1.0),
                            heightFactor: 1,
                            child: ColoredBox(color: color),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 16.w),
            Text(
              visible ? _money(ref, sats).main : _masked,
              maxLines: 1,
              style: caption.copyWith(
                  color: c.textPrimary, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
