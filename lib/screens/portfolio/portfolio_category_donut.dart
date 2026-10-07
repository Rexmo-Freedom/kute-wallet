// lib/screens/portfolio/portfolio_category_donut.dart
//
// The category donut at the top of the Portfolio's Statistics card, for
// Predictions and Investing, on the spending wallet and on a Ledger: the
// kinds of markets the account has put its money on, all time, as slices
// of one ring (the shared chart engine's KuteDonutChart), the total in the
// hole, a compact legend under it.
//
//   * Slices are categories (services/portfolio/portfolio_categories.dart):
//     Predictions weighs each by the amount predicted on it, Investing by
//     the volume traded in it. The five largest keep their own slice; the
//     rest, and anything with no category, share one "Other" slice
//     ([categorySlices]).
//   * All time, as the tiles under it: the hole says so. On the
//     Statistics tab's Active sub-tab the slices are what is open now and
//     the hole says "Active" ([PortfolioCategoryCard.centreLabel]).
//   * A tap on a slice or a legend row picks it: the slice pops out, the
//     hole shows its name, its amount and its share of the total. The
//     centre, outside the ring or the same row again clears it.
//   * With a [PortfolioCategoryCard.drill], a pick also opens the slice
//     up: the legend gives way (the card growing or shrinking to fit) to
//     the category's name with an "All" pill that brings the legend
//     back, and the caller's list of what is in it
//     (portfolio_category_drill.dart).
//   * Hidden balances mask the amounts and the shares alike.
//   * One analytics event once a pick settles (a walk around the ring is
//     one event): the venue, the slice's rank and kind, the category's
//     public slug, the wallet kind and the sub-tab (`scope`). Never an
//     amount.
//
// The card is the app's card surface and the list cards' type; the ring
// wears the theme's categorical chart palette, a hue per category.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/helpers/formatters/polymarket_amount_formatter.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/polymarket_browse_provider.dart' show PolyPillX;
import 'package:kute/providers/hyperliquid_markets_provider.dart'
    show HlBrowseSub;
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_browse_labels.dart';
import 'package:kute/screens/polymarket/components/market_card.dart'
    show polyCardCaptionStyle, polyCardFigureStyle;
import 'package:kute/screens/polymarket/components/poly_browse_bar.dart'
    show polyPillLabel;
import 'package:kute/screens/shared/charts/kute_donut_chart.dart';
import 'package:kute/screens/shared/components/sheet_detail_row.dart'
    show SheetAnimatedSize;
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/screens/shared/kute_motion.dart';
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/services/portfolio/portfolio_categories.dart'
    show kPortfolioOtherCategory;
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// What a slice stands for, as the analytics event names it.
enum CategorySliceKind { category, other }

/// One slice of the donut, as drawn and as listed in the legend.
class CategorySlice {
  /// The category's key (a Predictions pill's, an Investing class), or
  /// [kPortfolioOtherCategory] for the grouped slice.
  final String key;
  final double value;

  /// Share of the total, 0..1.
  final double fraction;

  /// Whole percent for display; the slices' percents add up to 100.
  final int percent;

  /// 1 for the largest slice; "Other" is always last.
  final int rank;
  final CategorySliceKind kind;

  const CategorySlice({
    required this.key,
    required this.value,
    required this.fraction,
    required this.percent,
    required this.rank,
    required this.kind,
  });
}

/// Categories that keep their own slice before the rest are grouped.
const int kCategoryTopSlices = 5;

/// The donut's slices for [values] (category key → amount): nothing worth
/// zero, less or not a number; the rest by amount, largest first (ties by
/// key); the [top] largest each a slice and the rest one "Other" slice,
/// together with the [kPortfolioOtherCategory] amount. A single category
/// left over keeps its own slice rather than become "Other" alone.
/// Percents are whole numbers by the largest remainder, so they always add
/// up to 100.
///
/// With [labelOf], categories that read the same are one category before
/// anything is ranked, so no two slices (or legend rows) ever share a
/// name: their amounts add up under one key, [kPortfolioOtherCategory]
/// when any of them is it (a name that reads "Other" is the Other slice),
/// else the first key alphabetically (stable while the amounts move).
List<CategorySlice> categorySlices(
  Map<String, double> values, {
  int top = kCategoryTopSlices,
  String Function(String key)? labelOf,
}) {
  if (labelOf != null) values = mergeCategoriesByLabel(values, labelOf);
  var other = 0.0;
  final named = <MapEntry<String, double>>[];
  for (final e in values.entries) {
    if (!e.value.isFinite || e.value <= 0) continue;
    if (e.key == kPortfolioOtherCategory) {
      other += e.value;
    } else {
      named.add(e);
    }
  }
  named.sort((a, b) {
    final byValue = b.value.compareTo(a.value);
    return byValue != 0 ? byValue : a.key.compareTo(b.key);
  });
  final total = named.fold<double>(other, (sum, e) => sum + e.value);
  if (total <= 0) return const [];

  final keepAll =
      named.length <= top || (named.length == top + 1 && other == 0);
  final kept = keepAll ? named : named.take(top).toList();
  for (final e in named.skip(kept.length)) {
    other += e.value;
  }
  final amounts = [for (final e in kept) e.value, if (other > 0) other];
  final percents = _largestRemainder(amounts, total);
  return [
    for (var i = 0; i < kept.length; i++)
      CategorySlice(
        key: kept[i].key,
        value: kept[i].value,
        fraction: kept[i].value / total,
        percent: percents[i],
        rank: i + 1,
        kind: CategorySliceKind.category,
      ),
    if (other > 0)
      CategorySlice(
        key: kPortfolioOtherCategory,
        value: other,
        fraction: other / total,
        percent: percents.last,
        rank: kept.length + 1,
        kind: CategorySliceKind.other,
      ),
  ];
}

/// [values] with the categories that share a label ([labelOf]) folded
/// into one key: [kPortfolioOtherCategory] when it is among them, else
/// the first of their keys alphabetically. Amounts that are not a finite
/// positive number are dropped.
Map<String, double> mergeCategoriesByLabel(
    Map<String, double> values, String Function(String key) labelOf) {
  final byLabel = <String, List<String>>{};
  for (final e in values.entries) {
    if (!e.value.isFinite || e.value <= 0) continue;
    final label = e.key == kPortfolioOtherCategory
        ? labelOf(kPortfolioOtherCategory)
        : labelOf(e.key);
    (byLabel[label] ??= []).add(e.key);
  }
  final out = <String, double>{};
  for (final keys in byLabel.values) {
    keys.sort();
    final key = keys.contains(kPortfolioOtherCategory)
        ? kPortfolioOtherCategory
        : keys.first;
    out[key] = keys.fold<double>(0, (sum, k) => sum + values[k]!);
  }
  return out;
}

/// Whole percents of [values] in [total] that add up to exactly 100: each
/// floored, the points left over handed to the largest remainders.
List<int> _largestRemainder(List<double> values, double total) {
  final exact = [for (final v in values) v / total * 100];
  final floors = [for (final e in exact) e.floor()];
  var left = 100 - floors.fold<int>(0, (a, b) => a + b);
  final order = List.generate(values.length, (i) => i)
    ..sort((a, b) {
      final byRemainder =
          (exact[b] - floors[b]).compareTo(exact[a] - floors[a]);
      return byRemainder != 0 ? byRemainder : a.compareTo(b);
    });
  for (final i in order) {
    if (left <= 0) break;
    floors[i]++;
    left--;
  }
  return floors;
}

/// The slice [category] (a category key as the values name it) is drawn
/// in among [slices]: the one whose name it shares ([labelOf]), else the
/// "Other" slice; null when neither is there.
String? categorySliceKeyOf(String category, List<CategorySlice> slices,
    String Function(String key) labelOf) {
  final label = labelOf(category);
  for (final s in slices) {
    if (s.kind == CategorySliceKind.category && labelOf(s.key) == label) {
      return s.key;
    }
  }
  return slices.any((s) => s.kind == CategorySliceKind.other)
      ? kPortfolioOtherCategory
      : null;
}

/// What a picked slice opens up to: the caller's list of what is in
/// [slice]. [inSlice] says whether a category key (as the values name
/// it) is drawn in that slice.
typedef CategoryDrillBuilder = Widget Function(BuildContext context,
    CategorySlice slice, bool Function(String category) inSlice);

/// Which venue's categories a donut shows; picks the labels.
enum CategoryVenue { predictions, trading }

/// A category's name as its venue's tab writes it: a Predictions pill's
/// label, an Investing class's.
String categoryLabel(AppLocalizations l10n, CategoryVenue venue, String key) {
  if (key == kPortfolioOtherCategory) return l10n.betGroupOther;
  if (venue == CategoryVenue.predictions) {
    final pill = PolyPillX.fromKey(key);
    return pill == null ? l10n.betGroupOther : polyPillLabel(l10n, pill);
  }
  return switch (key) {
    'crypto' => l10n.investingCrypto,
    'spot' => l10n.investingSpot,
    'stocks' => HlBrowseSub.stocks.localizedLabel(l10n),
    'indices' => HlBrowseSub.indices.localizedLabel(l10n),
    'commodities' => HlBrowseSub.commodities.localizedLabel(l10n),
    'fx' => HlBrowseSub.fx.localizedLabel(l10n),
    'preipo' => HlBrowseSub.preipo.localizedLabel(l10n),
    _ => l10n.betGroupOther,
  };
}

/// The donut's diameter.
double get _diameter => 184.w;

/// Insets of the [embedded] donut and its skeleton inside a host card:
/// the card's 16, the host's next block brings its own top inset.
EdgeInsets get _embeddedPadding => EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 0);

/// The loading placeholder in the card's place: the card's frame with a
/// ring and three legend lines, about the loaded card's height. [embedded]
/// drops the frame and the outer gap, for a host card.
class PortfolioCategorySkeleton extends StatelessWidget {
  const PortfolioCategorySkeleton({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context) => Padding(
        padding: embedded ? _embeddedPadding : EdgeInsets.only(top: 12.h),
        child: KuteSkeleton(
          child: _SkeletonFrame(
            embedded: embedded,
            child: Column(
              children: [
                SkeletonCircle(_diameter),
                SizedBox(height: 16.h),
                for (var i = 0; i < 3; i++)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.h),
                    child: Row(children: [
                      SkeletonCircle(8.w),
                      SizedBox(width: 10.w),
                      SkeletonBar(120.w, 12.h),
                      const Spacer(),
                      SkeletonBar(64.w, 12.h),
                    ]),
                  ),
              ],
            ),
          ),
        ),
      );
}

/// The skeleton's card frame; the bare content when [embedded].
class _SkeletonFrame extends StatelessWidget {
  const _SkeletonFrame({required this.embedded, required this.child});
  final bool embedded;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      embedded ? child : SkeletonCard(radius: AppRadius.lg, child: child);
}

/// The category card. [values] is category key → all-time amount in
/// dollars; [walletKind] is 'hot' or 'ledger' (analytics only). Nothing is
/// drawn when no category is worth anything. [embedded] drops the card's
/// own surface and outer gap, so it sits flush inside a host card.
class PortfolioCategoryCard extends ConsumerStatefulWidget {
  final Map<String, double> values;
  final CategoryVenue venue;
  final String walletKind;
  final bool embedded;

  /// Which Statistics sub-tab the donut is on ('active' or 'historic'),
  /// sent with the slice event; null sends none.
  final String? scope;

  /// The hole's caption while nothing is picked; "All time" when null.
  final String? centreLabel;

  /// What a picked slice opens up to in the legend's place; null keeps
  /// the legend under a pick.
  final CategoryDrillBuilder? drill;

  const PortfolioCategoryCard({
    super.key,
    required this.values,
    required this.venue,
    this.walletKind = 'hot',
    this.embedded = false,
    this.scope,
    this.centreLabel,
    this.drill,
  });

  @override
  ConsumerState<PortfolioCategoryCard> createState() =>
      _PortfolioCategoryCardState();
}

class _PortfolioCategoryCardState extends ConsumerState<PortfolioCategoryCard> {
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
      'venue': widget.venue.name,
      'slice_rank': slice.rank,
      'category_kind': slice.kind.name,
      'category': slice.key,
      'wallet_kind': widget.walletKind,
      if (widget.scope != null) 'scope': widget.scope!,
      // The pick opened the slice's list (the first level of the
      // drill-down; an item opened is level 2, a line opened level 3).
      if (widget.drill != null) 'drill_level': 1,
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
    // Categories that read the same are one slice.
    final slices = categorySlices(widget.values,
        labelOf: (key) => categoryLabel(l10n, widget.venue, key));
    _slices = slices;
    if (slices.isEmpty) return const SizedBox.shrink();

    // Each category keeps its hue while values move; "Other" is grey.
    final slots = _colorSlots.assign([
      for (final s in slices)
        if (s.kind == CategorySliceKind.category) s.key,
    ]);
    Color colorOf(CategorySlice s) =>
        KuteCategoryColorSlots.colorOf(c.chartCategorical,
            slot: slots[s.key], other: s.kind == CategorySliceKind.other);
    String label(CategorySlice s) => categoryLabel(l10n, widget.venue, s.key);
    String money(double v) => visible ? formatPolyAmount(ref, v) : '••••••';
    String share(CategorySlice s) => !visible
        ? '••%'
        : s.percent == 0
            ? '<1%'
            : '${s.percent}%';

    // A pick whose category is gone is no pick.
    final selected = slices.where((s) => s.key == _selected).firstOrNull;
    final total = slices.fold<double>(0, (sum, s) => sum + s.value);

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
          selected == null
              ? widget.centreLabel ?? l10n.exportPeriodAllTime
              : label(selected),
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
      margin: widget.embedded ? null : EdgeInsets.only(top: 12.h),
      padding: widget.embedded ? _embeddedPadding : EdgeInsets.all(16.w),
      decoration: widget.embedded ? null : AppDecorations.card(context),
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
          // The legend, or the picked slice opened up in its place; the
          // card grows or shrinks to the new content.
          SheetAnimatedSize(
            child: widget.drill != null && selected != null
                ? Column(
                    key: ValueKey('category-drill-${selected.key}'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _DrillHeader(
                        color: colorOf(selected),
                        label: label(selected),
                        onBack: () {
                          HapticFeedback.selectionClick();
                          _select(null);
                        },
                      ),
                      widget.drill!(
                          context,
                          selected,
                          (category) =>
                              categorySliceKeyOf(
                                  category,
                                  slices,
                                  (key) =>
                                      categoryLabel(l10n, widget.venue, key)) ==
                              selected.key),
                    ],
                  )
                : Column(
                    key: const ValueKey('category-legend'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
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
          ),
        ],
      ),
    );
  }
}

/// The top of an opened slice: its dot and name, as its legend row wrote
/// them, and the app's pill back to every category.
class _DrillHeader extends StatelessWidget {
  const _DrillHeader(
      {required this.color, required this.label, required this.onBack});
  final Color color;
  final String label;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(left: 8.w, bottom: 4.h),
      child: Row(
        children: [
          Container(
            width: 8.w,
            height: 8.w,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              label,
              style: polyCardCaptionStyle(c)
                  .copyWith(color: c.textPrimary, fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(width: 8.w),
          KutePill(
            key: const ValueKey('category-drill-back'),
            label: context.l10n.searchFilterAll,
            icon: Icons.chevron_left_rounded,
            selected: false,
            onTap: onBack,
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
