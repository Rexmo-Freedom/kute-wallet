// lib/screens/shared/charts/kute_category_donut_card.dart
//
// The category donut card: amounts by category, all time, as slices of
// one ring (the chart engine's KuteDonutChart), the total in the hole, a
// compact legend under it. The Portfolio Statistics donut's card made
// generic (labels, formatting and analytics passed in) for the Breakdown
// tab on Home and Dollars; same chrome, same gestures, same event.
//
//   * The five largest categories keep their own slice; the rest, and
//     anything with no category, share one "Other" slice (the Statistics
//     donut's [categorySlices], shared).
//   * All time: the hole says so.
//   * A tap on a slice or a legend row picks it: the slice pops out, the
//     hole shows its name, its amount and its share of the total. The
//     centre, outside the ring or the same row again clears it. A new
//     [KuteCategoryDonutCard.scope] (another set of categories in the same
//     place) clears it too.
//   * Hidden balances mask the amounts and the shares alike.
//   * One analytics event once a pick settles (a walk around the ring is
//     one event): the caller's categorical properties, the slice's rank
//     and kind and the category's public slug. Never an amount.
//
// The card is the app's card surface and the list cards' type; the ring
// wears the theme's categorical chart palette, a hue per category.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/polymarket/components/market_card.dart'
    show polyCardCaptionStyle, polyCardFigureStyle;
import 'package:kute/screens/shared/charts/kute_donut_chart.dart';
import 'package:kute/screens/shared/kute_motion.dart';
import 'package:kute/screens/portfolio/portfolio_category_donut.dart'
    show CategorySlice, CategorySliceKind, categorySlices;
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// The donut's diameter.
double get _diameter => 184.w;

/// The category card. [values] is category key → all-time amount, in
/// whatever unit [formatValue] writes. Nothing is drawn when no category
/// is worth anything.
class KuteCategoryDonutCard extends ConsumerStatefulWidget {
  final Map<String, double> values;

  /// A category's name, the grouped "other" key included.
  final String Function(String key) labelOf;

  /// An amount as the legend and the hole write it (unmasked; the card
  /// masks it under hidden balances).
  final String Function(WidgetRef ref, double value) formatValue;

  /// A second, quieter figure under the hole's amount (the fiat value of
  /// a bitcoin amount), or null for none.
  final String Function(WidgetRef ref, double value)? formatSecondary;

  /// The categorical properties of the slice event besides the slice's
  /// own (venue, wallet kind…). Never an amount.
  final Map<String, Object> analyticsParams;

  /// What these categories are of. A new value clears the pick: the same
  /// key in another set of categories is another slice.
  final Object? scope;

  const KuteCategoryDonutCard({
    super.key,
    required this.values,
    required this.labelOf,
    required this.formatValue,
    required this.analyticsParams,
    this.formatSecondary,
    this.scope,
  });

  @override
  ConsumerState<KuteCategoryDonutCard> createState() =>
      _KuteCategoryDonutCardState();
}

class _KuteCategoryDonutCardState extends ConsumerState<KuteCategoryDonutCard> {
  /// How long a pick must hold before it is reported (a walk around the
  /// ring reports only where it stops).
  static const _settle = Duration(milliseconds: 600);

  String? _selected;

  /// Which hue each category wears (kept while values move).
  final _colorSlots = KuteCategoryColorSlots();
  Timer? _settleTimer;

  /// The pick last reported; cleared with the selection, so picking the
  /// same slice again later is a new event.
  String? _reported;
  List<CategorySlice> _slices = const [];

  @override
  void didUpdateWidget(covariant KuteCategoryDonutCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope != widget.scope) {
      // Another set of categories starts over in slice order.
      _colorSlots.reset();
      _settleTimer?.cancel();
      _selected = null;
      _reported = null;
    }
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    super.dispose();
  }

  void _select(Object? key) {
    final next = key as String?;
    if (next == _selected) return;
    setState(() => _selected = next);
    _settleTimer?.cancel();
    if (next == null) {
      _reported = null;
      return;
    }
    _settleTimer = Timer(_settle, _report);
  }

  void _report() {
    final key = _selected;
    if (key == null || key == _reported || !mounted) return;
    final slice = _slices.where((s) => s.key == key).firstOrNull;
    if (slice == null) return;
    _reported = key;
    TrackingService.track('portfolio_category_slice_selected', params: {
      ...widget.analyticsParams,
      'slice_rank': slice.rank,
      'category_kind': slice.kind.name,
      'category': slice.key,
    });
  }

  void _onLegendTap(String key) {
    if (key != _selected) HapticFeedback.selectionClick();
    // The picked row again clears, as the centre of the ring does.
    _select(key == _selected ? null : key);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final visible = ref.watch(settingsProvider.select((s) => s.balanceVisible));
    // Categories that read the same are one slice: never two "Spark"s.
    final slices = categorySlices(widget.values, labelOf: widget.labelOf);
    _slices = slices;
    if (slices.isEmpty) return const SizedBox.shrink();

    // Each category keeps its hue while values move; "Other" is grey.
    final slots = _colorSlots.assign([
      for (final s in slices)
        if (s.kind == CategorySliceKind.category) s.key,
    ]);
    Color colorOf(CategorySlice s) => KuteCategoryColorSlots.colorOf(
        c.chartCategorical,
        slot: slots[s.key],
        other: s.kind == CategorySliceKind.other);
    String label(CategorySlice s) => widget.labelOf(s.key);
    String money(double v) => visible ? widget.formatValue(ref, v) : '••••••';
    String share(CategorySlice s) => !visible
        ? '••%'
        : s.percent == 0
            ? '<1%'
            : '${s.percent}%';

    // A pick whose category is gone is no pick.
    final selected = slices.where((s) => s.key == _selected).firstOrNull;
    final total = slices.fold<double>(0, (sum, s) => sum + s.value);
    final secondary = widget.formatSecondary;

    final caption = polyCardCaptionStyle(c).copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final figure = polyCardFigureStyle(c.textPrimary);
    // The hole: the all-time total, or the picked category's name, amount
    // and share.
    final centre = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          selected == null ? l10n.exportPeriodAllTime : label(selected),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: selected == null
              ? caption
              : caption.copyWith(
                  color: c.textPrimary, fontWeight: FontWeight.w600),
        ),
        SizedBox(height: 4.h),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: RollingFigure(
              identity: selected?.key,
              text: money(selected?.value ?? total),
              style: figure),
        ),
        if (secondary != null && visible) ...[
          SizedBox(height: 2.h),
          Text(secondary(ref, selected?.value ?? total),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: caption),
        ],
        if (selected != null) ...[
          SizedBox(height: 2.h),
          Text(l10n.portfolioCategoryShare(share(selected)),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: caption),
        ],
      ],
    );

    return Container(
      margin: EdgeInsets.only(top: 12.h),
      padding: EdgeInsets.all(16.w),
      decoration: AppDecorations.card(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: KuteDonutChart(
              diameter: _diameter,
              thickness: 18.w,
              trackColor: c.surfaceLight,
              selectedId: selected?.key,
              onSelected: _select,
              semanticsLabel: l10n.allocation,
              segments: [
                for (final s in slices)
                  KuteDonutSegment(
                    id: s.key,
                    value: s.value,
                    color: colorOf(s),
                    semanticsLabel:
                        '${label(s)}, ${share(s)}, ${money(s.value)}',
                  ),
              ],
              center: centre,
            ),
          ),
          SizedBox(height: 12.h),
          for (final s in slices)
            _LegendRow(
              key: ValueKey('category-legend-${s.key}'),
              color: colorOf(s),
              label: label(s),
              share: share(s),
              value: money(s.value),
              selected: s.key == selected?.key,
              onTap: () => _onLegendTap(s.key),
            ),
        ],
      ),
    );
  }
}

/// One legend line: the slice's dot, its name, its share and its amount.
/// The picked line sits on the inset tone.
class _LegendRow extends StatelessWidget {
  final Color color;
  final String label;
  final String share;
  final String value;
  final bool selected;
  final VoidCallback onTap;

  const _LegendRow({
    super.key,
    required this.color,
    required this.label,
    required this.share,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final caption = polyCardCaptionStyle(c).copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final radius = BorderRadius.circular(AppRadius.sm);
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: AnimatedContainer(
              duration: kuteMotion(context, kSelectionFadeDuration),
              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: selected ? c.surfaceLight : Colors.transparent,
                borderRadius: radius,
              ),
              child: Row(
                children: [
                  Container(
                    width: 8.w,
                    height: 8.w,
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  SizedBox(width: 10.w),
                  Expanded(
                    flex: 3,
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: caption.copyWith(
                        color: c.textPrimary,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  // The figures scale down as one block under large text;
                  // they never push the name off the row.
                  Flexible(
                    flex: 2,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(share, style: caption),
                          SizedBox(width: 12.w),
                          Text(
                            value,
                            style: caption.copyWith(
                                color: c.textPrimary,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
