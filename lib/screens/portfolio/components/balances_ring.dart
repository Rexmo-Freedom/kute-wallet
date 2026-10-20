// lib/screens/portfolio/components/balances_ring.dart
//
// Investments → Portfolio → Balances (founder approval, October 2026: the
// three-column card "looks cheap for the space we have"). The same
// figures as the breakdown's tiles, laid out as:
//
//   * an allocation RING, one arc per balance in its own colour (Dollars
//     the USDB green, Investing the Hyperliquid mint, Predictions the
//     Polymarket blue), each arc split into its cash (solid) and what it
//     holds in positions (the same colour, faded), a small gap between
//     arcs, tiny ones held to a minimum visible arc, empty or unknown
//     balances drawing none. The hole says what is ready to use (the cash
//     of all three) and, under it, what is in positions; the header above
//     already shows the total, so the hole never repeats it;
//   * one ROW per balance on the app's card: its mark, name and share,
//     its total, a two-part bar (cash / positions) and the two figures
//     under it ("Available" under Dollars, as the tile said);
//   * a small legend (Cash / Positions) under the ring.
//
// A tap on an arc or a row picks that balance: its arc thickens, the
// others dim, its row lifts with a hairline in its colour and the hole
// shows its name, total and split. The same tap again clears it (the hole
// or outside the ring too). A selection click on every change; no
// analytics event (the tiles had none).
//
// Motion: the arcs and bars draw once on first show, then hold still; a
// pick eases in. Under Reduce Motion everything is drawn at once.
//
// Unknown figures keep the breakdown's rules: a balance never read reads
// a dash (and draws no arc), a cached one is dimmed with the skeleton's
// sweep ([StaleShimmer]) while it refreshes, never a confident $0.00.

import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/portfolio/portfolio_figure_tiles.dart'
    show portfolioTileCaptionStyle;
import 'package:kute/screens/shared/kute_motion.dart'
    show RollingFigure, kuteReduceMotion;
import 'package:kute/screens/shared/stale_shimmer.dart';
import 'package:kute/theme/app_theme.dart';

/// The three balances, in ring and row order.
enum BalancesRingPart { dollars, investing, predictions }

/// The balance's own colour: the colour of its mark (the USDB coin, the
/// Hyperliquid and Polymarket logos), as the money map draws them. On the
/// light theme the Hyperliquid mint is deepened: the logo's own mint
/// vanishes on white, all the more at the positions' fade.
Color balancesRingColor(BalancesRingPart part, {bool dark = true}) =>
    switch (part) {
      BalancesRingPart.dollars => const Color(0xFF00875A),
      BalancesRingPart.investing =>
        dark ? const Color(0xFF97FCE4) : kBalancesRingMintOnLight,
      BalancesRingPart.predictions => const Color(0xFF2E5CFF),
    };

/// The Hyperliquid mint on the light theme.
const Color kBalancesRingMintOnLight = Color(0xFF14B89C);

/// The faded half of an arc or bar: what the balance holds in positions.
const double kBalancesRingPositionsAlpha = 0.35;

/// The arcs not picked while one is.
const double kBalancesRingDimAlpha = 0.3;

/// The first draw of the arcs and bars.
const Duration kBalancesRingDrawDuration = Duration(milliseconds: 900);

/// A pick easing in or out.
const Duration kBalancesRingSelectDuration = Duration(milliseconds: 200);

/// A figure as the breakdown resolved it: its text (masked when balances
/// are hidden, a dash when never read), whether it is still refreshing,
/// and its value (null when unknown).
@immutable
class BalancesRingFigure {
  const BalancesRingFigure(this.text, {this.stale = false, this.usd});

  final String text;
  final bool stale;
  final double? usd;
}

/// One balance as the ring and its row show it.
@immutable
class BalancesRingEntry {
  const BalancesRingEntry({
    required this.part,
    required this.asset,
    required this.name,
    required this.cash,
    this.positions,
    this.reserved,
    this.footer = const [],
  });

  final BalancesRingPart part;
  final String asset;
  final String name;
  final BalancesRingFigure cash;

  /// What it holds in positions; null for Dollars, which hold none.
  final BalancesRingFigure? positions;

  /// What open BUY orders reserve ("$4.00 in open orders").
  final String? reserved;

  /// Notes about a Rebalance, words only.
  final List<String> footer;

  /// The key part of its widgets ("dollars", "investing").
  String get id => part.name;

  /// Both figures known.
  bool get known =>
      cash.usd != null && (positions == null || positions!.usd != null);

  double get cashUsd => _clean(cash.usd);
  double get positionsUsd => _clean(positions?.usd);
  double get totalUsd => cashUsd + positionsUsd;

  bool get stale => cash.stale || (positions?.stale ?? false);
}

double _clean(double? usd) => usd != null && usd.isFinite && usd > 0 ? usd : 0;

/// One balance's arc: where it starts and how far it sweeps (radians
/// clockwise from twelve o'clock), the cash part first.
@immutable
class BalancesRingArc {
  const BalancesRingArc({
    required this.part,
    required this.start,
    required this.sweep,
    required this.cashSweep,
  });

  final BalancesRingPart part;
  final double start;
  final double sweep;

  /// The solid (cash) part of [sweep], from [start]; the rest is
  /// positions.
  final double cashSweep;

  double get end => start + sweep;
}

/// The gap between two arcs.
const double kBalancesRingGap = 3 * math.pi / 180;

/// The least an arc sweeps, however small its balance.
const double kBalancesRingMinSweep = 5 * math.pi / 180;

/// The arcs for [entries]: one per non-empty balance, its sweep its share
/// of the circle (less the gaps), a tiny one raised to [minSweep] and the
/// others shrunk to make room. None while any balance is unknown: its
/// share of the circle cannot be drawn without a guess. Pure for the
/// tests.
List<BalancesRingArc> balancesRingArcs(
  List<BalancesRingEntry> entries, {
  double gap = kBalancesRingGap,
  double minSweep = kBalancesRingMinSweep,
}) {
  if (entries.any((e) => !e.known)) return const [];
  final shown = [
    for (final e in entries)
      if (e.totalUsd > 0) e,
  ];
  if (shown.isEmpty) return const [];
  final total = shown.fold<double>(0, (sum, e) => sum + e.totalUsd);
  final room = 2 * math.pi - (shown.length > 1 ? gap * shown.length : 0);
  final sweeps = [for (final e in shown) room * e.totalUsd / total];
  // Raise the tiny ones to the minimum, taking it from the rest in
  // proportion, until nothing is under it.
  final floor = math.min(minSweep, room / shown.length);
  final raised = <int>{};
  for (var pass = 0; pass < shown.length; pass++) {
    final under = [
      for (var i = 0; i < sweeps.length; i++)
        if (!raised.contains(i) && sweeps[i] < floor) i,
    ];
    if (under.isEmpty) break;
    raised.addAll(under);
    final fixed = floor * raised.length;
    final rest = [
      for (var i = 0; i < shown.length; i++)
        if (!raised.contains(i)) i,
    ];
    final restTotal = rest.fold<double>(0, (sum, i) => sum + shown[i].totalUsd);
    for (final i in raised) {
      sweeps[i] = floor;
    }
    for (final i in rest) {
      sweeps[i] = (room - fixed) * shown[i].totalUsd / restTotal;
    }
  }
  final arcs = <BalancesRingArc>[];
  var at = shown.length > 1 ? gap / 2 : 0.0;
  for (var i = 0; i < shown.length; i++) {
    final e = shown[i];
    arcs.add(BalancesRingArc(
      part: e.part,
      start: at,
      sweep: sweeps[i],
      cashSweep: sweeps[i] * e.cashUsd / e.totalUsd,
    ));
    at += sweeps[i] + (shown.length > 1 ? gap : 0);
  }
  return arcs;
}

/// The balance whose arc is at [angle] (radians clockwise from twelve
/// o'clock), half a gap of slack on each side; null in a gap. Pure for
/// the tests.
BalancesRingPart? balancesRingPartAt(List<BalancesRingArc> arcs, double angle,
    {double gap = kBalancesRingGap}) {
  final a = angle % (2 * math.pi);
  for (final arc in arcs) {
    for (final turn in [0.0, 2 * math.pi]) {
      final x = a + turn;
      if (x >= arc.start - gap / 2 && x <= arc.end + gap / 2) return arc.part;
    }
  }
  return null;
}

/// A balance's share of [total], as the donut writes it: "12%", "<1%"
/// under one percent, nothing for an empty balance or while any is
/// unknown ([total] null), "••%" when balances are hidden.
String? balancesRingShare(BalancesRingEntry e, double? total,
    {required bool visible}) {
  if (total == null || !e.known || e.totalUsd <= 0 || total <= 0) {
    return null;
  }
  if (!visible) return '••%';
  final percent = (e.totalUsd / total * 100).round();
  return percent < 1 ? '<1%' : '$percent%';
}

/// The ring, the legend and the rows (see the file header). [money]
/// writes an amount (masked when balances are hidden); [wrap] lets the
/// breakdown wrap each row (its Rebalance band, the Dollars arrival).
class BalancesRingView extends StatefulWidget {
  const BalancesRingView({
    super.key,
    required this.entries,
    required this.money,
    required this.visible,
    this.wrap,
  });

  final List<BalancesRingEntry> entries;
  final String Function(double usd) money;
  final bool visible;
  final Widget Function(BalancesRingPart part, Widget row)? wrap;

  @override
  State<BalancesRingView> createState() => _BalancesRingViewState();
}

class _BalancesRingViewState extends State<BalancesRingView>
    with TickerProviderStateMixin {
  late final AnimationController _draw =
      AnimationController(vsync: this, duration: kBalancesRingDrawDuration);
  late final AnimationController _pick =
      AnimationController(vsync: this, duration: kBalancesRingSelectDuration);
  late final Animation<double> _drawn =
      CurvedAnimation(parent: _draw, curve: Curves.easeOutCubic);
  late final Animation<double> _picked =
      CurvedAnimation(parent: _pick, curve: Curves.easeOut);

  BalancesRingPart? _selected;

  /// Each arc's thickening and opacity, from and to, for the pick's ease.
  Map<BalancesRingPart, (double, double)> _from = _emphasis(null);
  Map<BalancesRingPart, (double, double)> _to = _emphasis(null);

  bool _started = false;

  static Map<BalancesRingPart, (double, double)> _emphasis(
          BalancesRingPart? selected) =>
      {
        for (final p in BalancesRingPart.values)
          p: selected == null
              ? (0.0, 1.0)
              : p == selected
                  ? (1.0, 1.0)
                  : (0.0, kBalancesRingDimAlpha),
      };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      if (kuteReduceMotion(context)) {
        _draw.value = 1;
      } else {
        _draw.forward();
      }
      _pick.value = 1;
    }
  }

  @override
  void dispose() {
    _draw.dispose();
    _pick.dispose();
    super.dispose();
  }

  Map<BalancesRingPart, (double, double)> get _current => {
        for (final p in BalancesRingPart.values)
          p: (
            lerpDouble(_from[p]!.$1, _to[p]!.$1, _picked.value)!,
            lerpDouble(_from[p]!.$2, _to[p]!.$2, _picked.value)!,
          ),
      };

  void _select(BalancesRingPart? part) {
    final next = part == _selected ? null : part;
    if (next == _selected) return;
    HapticFeedback.selectionClick();
    setState(() {
      _from = _current;
      _selected = next;
      _to = _emphasis(next);
    });
    if (kuteReduceMotion(context)) {
      _pick.value = 1;
    } else {
      _pick.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final entries = widget.entries;
    // A pick whose balance is gone is no pick.
    final selected = entries.where((e) => e.part == _selected).firstOrNull;
    final arcs = balancesRingArcs(entries);
    // Shares only of a whole that is known.
    final total = entries.every((e) => e.known)
        ? entries.fold<double>(0, (sum, e) => sum + e.totalUsd)
        : null;
    final anyPositions = entries.any((e) => e.positions != null);
    final size = 230.w;
    final stroke = 18.w;
    final grow = 6.w;
    final caption = portfolioTileCaptionStyle(c);

    final ring = SizedBox.square(
      dimension: size,
      child: GestureDetector(
        key: const ValueKey('portfolio-balance-ring'),
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) {
          final centre = Offset(size / 2, size / 2);
          final d = details.localPosition - centre;
          final radius = (size - stroke - grow) / 2;
          final slop = stroke / 2 + 12;
          if ((d.distance - radius).abs() > slop) {
            if (_selected != null) _select(_selected);
            return;
          }
          final angle = math.atan2(d.dy, d.dx) + math.pi / 2;
          final part = balancesRingPartAt(arcs, angle);
          if (part != null) _select(part);
        },
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: Listenable.merge([_drawn, _picked]),
                  builder: (context, _) => CustomPaint(
                    painter: _RingPainter(
                      arcs: arcs,
                      progress: _drawn.value,
                      emphasis: _current,
                      track: _trackColor(context),
                      dark: context.isDark,
                      stroke: stroke,
                      grow: grow,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: size - 2 * (stroke + grow) - 24.w,
              child: _Centre(
                entries: entries,
                selected: selected,
                money: widget.money,
                anyPositions: anyPositions,
              ),
            ),
          ],
        ),
      ),
    );

    return Column(
      key: const ValueKey('portfolio-balance-ring-view'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: 8.h),
        Center(
          child: Semantics(
            container: true,
            label: _ringLabel(l10n, entries),
            child: ExcludeSemantics(child: ring),
          ),
        ),
        if (anyPositions) ...[
          SizedBox(height: 14.h),
          ExcludeSemantics(
            child: Row(
              key: const ValueKey('portfolio-balance-ring-legend'),
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Swatch(color: c.textSecondary),
                SizedBox(width: 6.w),
                Text(l10n.ledgerHlCash, style: caption),
                SizedBox(width: 16.w),
                _Swatch(
                    color: c.textSecondary
                        .withValues(alpha: kBalancesRingPositionsAlpha)),
                SizedBox(width: 6.w),
                Text(l10n.ledgerPositionsTitle, style: caption),
              ],
            ),
          ),
        ],
        SizedBox(height: 20.h),
        for (final (i, e) in entries.indexed) ...[
          if (i > 0) SizedBox(height: 10.h),
          _wrap(
              e.part,
              _BalanceRow(
                key: ValueKey('portfolio-balance-${e.id}'),
                entry: e,
                share: balancesRingShare(e, total, visible: widget.visible),
                total: e.known ? widget.money(e.totalUsd) : '—',
                selected: selected?.part == e.part,
                progress: _drawn,
                onTap: () => _select(e.part),
              )),
        ],
      ],
    );
  }

  Widget _wrap(BalancesRingPart part, Widget row) =>
      widget.wrap?.call(part, row) ?? row;

  /// The ring as one node: each balance's total, cash and positions.
  String _ringLabel(AppLocalizations l10n, List<BalancesRingEntry> entries) {
    String total(BalancesRingEntry e) =>
        e.known ? widget.money(e.totalUsd) : '—';
    return [
      for (final e in entries)
        [
          '${e.name} ${total(e)}',
          '${l10n.ledgerHlCash} ${e.cash.text}',
          if (e.positions case final p?)
            '${l10n.ledgerPositionsTitle} ${p.text}',
        ].join(', '),
    ].join('. ');
  }
}

/// The ring's quiet track.
Color _trackColor(BuildContext context) => context.isDark
    ? context.colors.surfaceLight
    : context.colors.surfaceElevated;

/// The hole: what is ready to use and what is in positions, or the
/// picked balance's name, total and split.
class _Centre extends StatelessWidget {
  const _Centre({
    required this.entries,
    required this.selected,
    required this.money,
    required this.anyPositions,
  });

  final List<BalancesRingEntry> entries;
  final BalancesRingEntry? selected;
  final String Function(double usd) money;
  final bool anyPositions;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final caption = portfolioTileCaptionStyle(c).copyWith(fontSize: 13.sp);
    final big = TextStyle(
      color: c.textPrimary,
      fontSize: 28.sp,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.6,
      height: 1.15,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final String label;
    final BalancesRingFigure figure;
    final String? line;
    final pick = selected;
    if (pick == null) {
      label = l10n.available;
      final cashKnown = entries.every((e) => e.cash.usd != null);
      figure = BalancesRingFigure(
        cashKnown
            ? money(entries.fold<double>(0, (s, e) => s + e.cashUsd))
            : '—',
        stale: cashKnown && entries.any((e) => e.cash.stale),
      );
      final held = [
        for (final e in entries)
          if (e.positions case final p?) p,
      ];
      line = !anyPositions
          ? null
          : '${l10n.ledgerPositionsTitle} ${held.every((p) => p.usd != null) ? money(held.fold<double>(0, (s, p) => s + _clean(p.usd))) : '—'}';
    } else {
      label = pick.name;
      figure = BalancesRingFigure(
        pick.known ? money(pick.totalUsd) : '—',
        stale: pick.known && pick.stale,
      );
      line = [
        '${l10n.ledgerHlCash} ${pick.cash.text}',
        if (pick.positions case final p?)
          '${l10n.ledgerPositionsTitle} ${p.text}',
      ].join(' · ');
    }

    Widget fit(Widget child) => FittedBox(fit: BoxFit.scaleDown, child: child);
    return Column(
      key: const ValueKey('portfolio-balance-ring-centre'),
      mainAxisSize: MainAxisSize.min,
      children: [
        fit(Text(label,
            key: const ValueKey('portfolio-balance-ring-label'),
            maxLines: 1,
            style: pick == null
                ? caption
                : caption.copyWith(
                    color: c.textPrimary, fontWeight: FontWeight.w600))),
        SizedBox(height: 4.h),
        fit(KeyedSubtree(
          key: const ValueKey('portfolio-balance-ring-figure'),
          child: StaleShimmer(
            stale: figure.stale,
            child: RollingFigure(
                identity: pick?.part,
                text: figure.text,
                style:
                    figure.stale ? big.copyWith(color: c.textSecondary) : big),
          ),
        )),
        if (line != null) ...[
          SizedBox(height: 4.h),
          fit(Text(line,
              key: const ValueKey('portfolio-balance-ring-line'),
              maxLines: 1,
              style: caption)),
        ],
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 10.w,
        height: 10.w,
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(3.r)),
      );
}

/// One balance's row: mark, name and share, total; the two-part bar; its
/// cash and positions.
class _BalanceRow extends StatelessWidget {
  const _BalanceRow({
    super.key,
    required this.entry,
    required this.share,
    required this.total,
    required this.selected,
    required this.progress,
    required this.onTap,
  });

  final BalancesRingEntry entry;
  final String? share;

  /// The balance's total, written as its figures are (masked when
  /// hidden), a dash when unknown.
  final String total;
  final bool selected;
  final Animation<double> progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final e = entry;
    final color = balancesRingColor(e.part, dark: context.isDark);
    final caption = portfolioTileCaptionStyle(c);
    final figureCaption =
        caption.copyWith(color: c.textSecondary, fontWeight: FontWeight.w600);
    final totalStyle = TextStyle(
      color: c.textPrimary,
      fontSize: 16.sp,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.2,
      height: 1.2,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    // Live: a new figure rolls the digits that changed; while it refreshes
    // it is dimmed with the skeleton's sweep.
    Widget live(BalancesRingFigure figure, TextStyle style) => StaleShimmer(
          stale: figure.stale,
          child: RollingFigure(
              text: figure.text,
              style: figure.stale
                  ? style.copyWith(color: c.textSecondary)
                  : style),
        );

    final sum = BalancesRingFigure(total, stale: e.known && e.stale);

    final base =
        AppDecorations.card(context, color: selected ? c.surfaceLight : null);
    final decoration = base.copyWith(
      border: selected
          ? Border.all(color: color.withValues(alpha: 0.4), width: 1)
          : base.border ?? Border.all(color: Colors.transparent, width: 1),
    );

    return Semantics(
      container: true,
      button: true,
      selected: selected,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: kuteReduceMotion(context)
              ? Duration.zero
              : kBalancesRingSelectDuration,
          curve: Curves.easeOut,
          padding: EdgeInsets.fromLTRB(14.w, 14.h, 14.w, 12.h),
          decoration: decoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  SvgPicture.asset(e.asset, width: 24.w, height: 24.w),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(e.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: c.textPrimary,
                                  fontSize: 15.sp,
                                  fontWeight: FontWeight.w600,
                                  height: 1.2)),
                        ),
                        if (share case final s?) ...[
                          SizedBox(width: 6.w),
                          Text(s,
                              key: ValueKey('portfolio-balance-${e.id}-share'),
                              maxLines: 1,
                              style: caption.copyWith(fontSize: 13.sp)),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FittedBox(
                        key: ValueKey('portfolio-balance-${e.id}-total'),
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: live(sum, totalStyle),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12.h),
              ExcludeSemantics(
                child: AnimatedBuilder(
                  animation: progress,
                  builder: (context, _) => CustomPaint(
                    size: Size(double.infinity, 6.h),
                    painter: _BarPainter(
                      progress: progress.value,
                      color: color,
                      cash: e.known ? e.cashUsd : 0,
                      positions: e.known ? e.positionsUsd : 0,
                      track: _trackColor(context),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 8.h),
              Row(
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        key: ValueKey('portfolio-balance-${e.id}-available'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(l10n.ledgerHlCash, style: caption),
                          SizedBox(width: 4.w),
                          live(e.cash, figureCaption),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: e.positions == null
                          ? Text(l10n.available, style: caption)
                          : Row(
                              key: ValueKey(
                                  'portfolio-balance-${e.id}-positions'),
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(l10n.ledgerPositionsTitle, style: caption),
                                SizedBox(width: 4.w),
                                live(e.positions!, figureCaption),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
              if (e.reserved case final line?) ...[
                SizedBox(height: 4.h),
                Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(line, maxLines: 1, style: caption),
                  ),
                ),
              ],
              for (final line in e.footer) ...[
                SizedBox(height: 6.h),
                Text(line, style: caption),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The arcs on their track: cash solid, positions faded, a picked arc
/// thicker and the others dimmed, drawn clockwise from twelve o'clock up
/// to [progress] of the circle.
class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.arcs,
    required this.progress,
    required this.emphasis,
    required this.track,
    required this.dark,
    required this.stroke,
    required this.grow,
  });

  final List<BalancesRingArc> arcs;
  final double progress;
  final Map<BalancesRingPart, (double, double)> emphasis;
  final Color track;
  final bool dark;
  final double stroke;
  final double grow;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final radius = (math.min(size.width, size.height) - stroke - grow) / 2;
    final rect = Rect.fromCircle(center: centre, radius: radius);
    canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..color = track);
    final limit = progress * 2 * math.pi;
    void arc(double from, double sweep, Color color, double width) {
      final end = math.min(from + sweep, limit);
      if (end <= from) return;
      canvas.drawArc(
          rect,
          from - math.pi / 2,
          end - from,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = width
            ..strokeCap = StrokeCap.butt
            ..isAntiAlias = true
            ..color = color);
    }

    for (final a in arcs) {
      final (thick, alpha) = emphasis[a.part] ?? (0.0, 1.0);
      final color = balancesRingColor(a.part, dark: dark);
      final width = stroke + grow * thick;
      if (a.cashSweep > 0) {
        arc(a.start, a.cashSweep, color.withValues(alpha: alpha), width);
      }
      if (a.sweep - a.cashSweep > 0) {
        arc(
            a.start + a.cashSweep,
            a.sweep - a.cashSweep,
            color.withValues(alpha: alpha * kBalancesRingPositionsAlpha),
            width);
      }
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.track != track ||
      old.dark != dark ||
      old.stroke != stroke ||
      old.grow != grow ||
      !_sameArcs(old.arcs, arcs) ||
      !_sameEmphasis(old.emphasis, emphasis);

  static bool _sameArcs(List<BalancesRingArc> a, List<BalancesRingArc> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].part != b[i].part ||
          a[i].start != b[i].start ||
          a[i].sweep != b[i].sweep ||
          a[i].cashSweep != b[i].cashSweep) {
        return false;
      }
    }
    return true;
  }

  static bool _sameEmphasis(Map<BalancesRingPart, (double, double)> a,
          Map<BalancesRingPart, (double, double)> b) =>
      BalancesRingPart.values.every((p) => a[p] == b[p]);
}

/// A row's two-part bar: its cash solid, its positions faded, over the
/// track, grown to [progress] of the width.
class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.progress,
    required this.color,
    required this.cash,
    required this.positions,
    required this.track,
  });

  final double progress;
  final Color color;
  final double cash;
  final double positions;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.height / 2);
    final full = Offset.zero & size;
    canvas.drawRRect(RRect.fromRectAndRadius(full, r), Paint()..color = track);
    final total = cash + positions;
    if (total <= 0 || progress <= 0) return;
    final shown = size.width * progress;
    final cashW = size.width * cash / total;
    canvas.save();
    canvas.clipRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, shown, size.height), r));
    if (cashW > 0) {
      canvas.drawRect(
          Rect.fromLTWH(0, 0, cashW, size.height), Paint()..color = color);
    }
    if (cashW < size.width) {
      canvas.drawRect(
          Rect.fromLTWH(cashW, 0, size.width - cashW, size.height),
          Paint()
            ..color = color.withValues(alpha: kBalancesRingPositionsAlpha));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.cash != cash ||
      old.positions != positions ||
      old.track != track;
}
