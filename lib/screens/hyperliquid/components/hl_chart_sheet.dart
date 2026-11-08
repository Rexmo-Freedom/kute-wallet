// lib/screens/hyperliquid/components/hl_chart_sheet.dart
//
// The Hyperliquid chart's one picker sheet, opened from the chart's one
// chart button: on the market chart beside the interval row, and in the
// Advanced chart's top bar beside its interval (founder, 4 November 2026:
// "the chart type and the indicators can be in only one button, exactly
// like we do on the main chart"; "picker should be with big squares").
//
//   * CHART TYPE: Line, Candles, Area, Heikin Ashi, Hollow candles and
//     Baseline as big square cards, a tiny chart of the market's last bars
//     drawn in each. A pick applies at once and the sheet stays up.
//   * DISPLAY: the on/off settings as the same square cards, each with a
//     tiny chart of what it does: Log scale, per market, saved with the
//     market's other chart settings. On (the CTA-coloured outline) the
//     price plot maps ln(price); panes stay linear.
//   * TREND · MOMENTUM · VOLATILITY · VOLUME: the curated indicators
//     (hl_chart_indicator_catalog.dart) as the same square cards, two to a
//     row: a mini chart of what it draws on this market (in its colours
//     while on, grey while off), its name and one line on what it shows.
//     A tap switches it (on: the CTA-coloured outline the app's chips
//     use); on, a card with settings shows a tune button that opens
//     [showHlIndicatorSettings]. Four fit on the price and two
//     below it: one more turns the oldest of that kind off, with a toast.
//   * Reset (pinned at the foot) puts back what a fresh install shows:
//     Line, Volume alone, a linear axis, every setting at its default.
//
// A picker: the floating Sal bar hides while it is up.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart' show HlMarket;
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/providers/chart_drawings_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_advanced_layers.dart'
    show hlPaintIchimokuCloud;
import 'package:kute/screens/hyperliquid/components/hl_chart_indicator_catalog.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_indicator_frame.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_indicator_series.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_intervals.dart';
import 'package:kute/screens/hyperliquid/components/hl_charts.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/kute_action_cards.dart'
    show KuteActionCard;
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/kute_motion.dart' show KutePressable;
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/venue_analytics.dart';
import 'package:kute/theme/app_theme.dart';

/// Bars a card's mini chart draws.
const int kHlStyleThumbBars = 30;
const int _kPreviewBars = 40;

/// The chart button's glyph for [style].
IconData hlChartStyleIcon(HlChartStyle style) => switch (style) {
      HlChartStyle.line => Icons.show_chart_rounded,
      HlChartStyle.area => Icons.area_chart_rounded,
      HlChartStyle.heikinAshi => Icons.candlestick_chart_outlined,
      HlChartStyle.hollow => Icons.candlestick_chart_outlined,
      HlChartStyle.baseline => Icons.ssid_chart_rounded,
      _ => Icons.candlestick_chart_rounded,
    };

/// The chart's one button: the chart type's glyph and a chevron in a soft
/// rounded box (the market chart's, beside its interval row; the Advanced
/// top bar uses the same).
class HlChartSheetButton extends StatelessWidget {
  const HlChartSheetButton({
    super.key,
    required this.style,
    required this.onTap,
  });

  final HlChartStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: context.l10n.chartSheetTitle,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 9.w, vertical: 7.h),
          decoration: BoxDecoration(
            color: c.textPrimary.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(9.r),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(hlChartStyleIcon(style), size: 16.sp, color: c.textPrimary),
              SizedBox(width: 4.w),
              Icon(Icons.expand_more_rounded,
                  size: 14.sp, color: c.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the Chart sheet for [market]. [candles] (the bars the chart
/// shows) draw the cards' mini charts.
Future<void> showHlChartSheet(
  BuildContext context, {
  required HlMarket market,
  required String marketKey,
  required List<HyperliquidCandle> candles,
}) {
  HapticFeedback.selectionClick();
  return showAppBottomSheet<void>(
    context: context,
    builder: (_) => HlChartSheet(
      market: market,
      marketKey: marketKey,
      candles: candles,
    ),
  );
}

/// An indicator's name on its card and in a toast.
String hlIndicatorName(AppLocalizations l10n, String key) => switch (key) {
      'vol' => l10n.chartVolume,
      'bb' => l10n.chartIndBb,
      'vp' => l10n.chartIndVp,
      _ => hlIndSpec(key)?.short ?? key,
    };

String _note(AppLocalizations l10n, String key) => switch (key) {
      'ema' => l10n.chartIndEmaNote,
      'ma' => l10n.chartIndSmaNote,
      'vwap' => l10n.chartIndVwapNote,
      'st' => l10n.chartIndStNote,
      'rsi' => l10n.chartIndRsiNote,
      'macd' => l10n.chartIndMacdNote,
      'srsi' => l10n.chartIndSrsiNote,
      'bb' => l10n.chartIndBbNote,
      'atr' => l10n.chartIndAtrNote,
      'ichi' => l10n.chartIndIchimokuNote,
      'pp' => l10n.chartIndPivotNote,
      'adx' => l10n.chartIndAdxNote,
      'vol' => l10n.chartIndVolumeNote,
      'obv' => l10n.chartIndObvNote,
      'vp' => l10n.chartIndVpNote,
      _ => '',
    };

String _groupName(AppLocalizations l10n, HlIndGroup g) => switch (g) {
      HlIndGroup.trend => l10n.chartGroupTrend,
      HlIndGroup.momentum => l10n.chartGroupMomentum,
      HlIndGroup.volatility => l10n.chartGroupVolatility,
      HlIndGroup.volume => l10n.chartVolume,
    };

String _styleName(AppLocalizations l10n, HlChartStyle style) => switch (style) {
      HlChartStyle.line => l10n.chartStyleLine,
      HlChartStyle.area => l10n.chartStyleArea,
      HlChartStyle.heikinAshi => l10n.chartStyleHeikinAshi,
      HlChartStyle.hollow => l10n.chartStyleHollow,
      HlChartStyle.baseline => l10n.chartStyleBaseline,
      _ => l10n.chartStyleCandles,
    };

class HlChartSheet extends ConsumerStatefulWidget {
  const HlChartSheet({
    super.key,
    required this.market,
    required this.marketKey,
    required this.candles,
  });

  final HlMarket market;
  final String marketKey;
  final List<HyperliquidCandle> candles;

  @override
  ConsumerState<HlChartSheet> createState() => _HlChartSheetState();
}

class _HlChartSheetState extends ConsumerState<HlChartSheet> {
  _HlPreviews? _previews;
  Object? _previewsKey;

  Map<String, Object> get _assetParams => {
        'coin': widget.market.coin,
        ...VenueAnalytics.hlAssetParams(widget.market.coin),
      };

  ChartPreferencesNotifier get _prefs =>
      ref.read(hlChartPreferencesProvider(widget.marketKey).notifier);

  _HlPreviews _previewsFor(Map<String, List<num>> params) {
    final key = (widget.candles, params);
    if (key != _previewsKey || _previews == null) {
      _previewsKey = key;
      _previews = _HlPreviews.build(widget.candles, params);
    }
    return _previews!;
  }

  void _pickStyle(HlChartStyle style) {
    final current =
        HlChartStyle.fromName(ref.read(hlChartLayoutProvider).style);
    if (style == current) return;
    HapticFeedback.selectionClick();
    // Only how the bars are drawn changes: the interval, the view and the
    // history stay, on this market and every other one.
    ref.read(hlChartLayoutProvider.notifier).setStyle(style.name);
    VenueAnalytics.settingChanged(
      'chart_type_changed',
      setting: 'chart_style',
      value: style.name,
      extra: {'type': style.name, ..._assetParams},
    );
  }

  void _toggle(String key) {
    HapticFeedback.selectionClick();
    final l10n = context.l10n;
    final current =
        ref.read(hlChartPreferencesProvider(widget.marketKey)).indicators;
    final r = hlToggleIndicator(current, key);
    _prefs.setIndicators(r.next);
    TrackingService.track('indicator_toggled', params: {
      'indicator': key,
      'enabled': r.next.contains(key),
      ..._assetParams,
    });
    final replaced = r.replaced;
    if (replaced == null) return;
    final pane = hlIndSpec(replaced)?.place == HlIndPlace.pane;
    TrackingService.track('indicator_toggled', params: {
      'indicator': replaced,
      'enabled': false,
      'via': pane ? 'pane_limit' : 'price_limit',
      ..._assetParams,
    });
    final name = hlIndicatorName(l10n, replaced);
    showMessageSnackBarInfo(
      context: context,
      message: pane ? l10n.chartPaneLimit(name) : l10n.chartPriceLimit(name),
      duration: const Duration(seconds: 3),
    );
  }

  void _setLogScale(bool on) {
    HapticFeedback.selectionClick();
    _prefs.setLogScale(on);
    VenueAnalytics.settingChanged(
      'chart_log_scale_toggled',
      setting: 'log_scale',
      value: on,
      scope: widget.marketKey,
      extra: _assetParams,
    );
  }

  void _reset() {
    HapticFeedback.selectionClick();
    _pickStyle(HlChartStyle.fromName(kHlDefaultChartStyle));
    final prefs = ref.read(hlChartPreferencesProvider(widget.marketKey));
    if (prefs.logScale) _setLogScale(false);
    for (final key in {...prefs.indicators, ...kHlDefaultIndicators}) {
      final on = kHlDefaultIndicators.contains(key);
      if (prefs.indicators.contains(key) == on) continue;
      TrackingService.track('indicator_toggled', params: {
        'indicator': key,
        'enabled': on,
        'via': 'reset',
        ..._assetParams,
      });
    }
    for (final key in prefs.params.keys) {
      final spec = hlIndSpec(key);
      if (spec == null) continue;
      TrackingService.track('indicator_settings_changed', params: {
        'indicator': key,
        'via': 'reset',
        for (final p in spec.params) p.id: p.defaultValue,
        ..._assetParams,
      });
    }
    _prefs
      ..setIndicators(kHlDefaultIndicators)
      ..clearParams();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.colors;
    final style = HlChartStyle.fromName(ref.watch(hlChartLayoutProvider).style);
    final prefs = ref.watch(hlChartPreferencesProvider(widget.marketKey));
    final on = prefs.indicators;
    final isDefault = style == HlChartStyle.fromName(kHlDefaultChartStyle) &&
        on.length == kHlDefaultIndicators.length &&
        on.containsAll(kHlDefaultIndicators) &&
        prefs.params.isEmpty &&
        !prefs.logScale;
    final previews = _previewsFor(prefs.params);

    Widget pairs(List<Widget> cards) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < cards.length; i += 2) ...[
              if (i > 0) const SizedBox(height: 10),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: cards[i]),
                    const SizedBox(width: 10),
                    Expanded(
                      child: i + 1 < cards.length
                          ? cards[i + 1]
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );

    final sections = <Widget>[
      _SectionLabel(l10n.chartSheetChartType,
          key: const ValueKey('hl-chart-group-type')),
      pairs([
        for (final s in HlChartStyle.picker)
          _StyleCard(
            style: s,
            picked: s == style,
            candles: widget.candles,
            onTap: () => _pickStyle(s),
          ),
      ]),
      const SizedBox(height: 20),
      _SectionLabel(l10n.chartGroupDisplay,
          key: const ValueKey('hl-chart-group-display')),
      pairs([
        _ToggleCard(
          cardKey: const ValueKey('hl-chart-log-card'),
          on: prefs.logScale,
          painter: HlLogPreviewPainter(
            tape: previews.tape,
            on: prefs.logScale,
            muted: c.textTertiary,
            up: AppColors.marketUp,
            down: AppColors.marketDown,
          ),
          name: l10n.chartLogScale,
          note: l10n.chartLogScaleNote,
          onTap: () => _setLogScale(!prefs.logScale),
        ),
      ]),
      for (final group in HlIndGroup.values) ...[
        const SizedBox(height: 20),
        _SectionLabel(_groupName(l10n, group),
            key: ValueKey('hl-chart-group-${group.name}')),
        pairs([
          for (final spec in kHlIndicatorCatalog)
            if (spec.group == group)
              _IndicatorCard(
                spec: spec,
                on: on.contains(spec.key),
                params: hlIndParams(spec.key, prefs.params),
                previews: previews,
                onTap: () => _toggle(spec.key),
                onSettings: () => unawaited(showHlIndicatorSettings(
                  context,
                  market: widget.market,
                  marketKey: widget.marketKey,
                  indicator: spec.key,
                )),
              ),
        ]),
      ],
      const SizedBox(height: 8),
    ];

    // A picker: the floating bar is away while it is up.
    return KuteBarContextScope(
      barContext: const KuteBarContext.hidden(),
      child: AppBottomSheetContainer(
        maxHeight: 0.9,
        child: Column(
          key: const ValueKey('hl-chart-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppBottomSheetHeader(
              title: l10n.chartSheetTitle,
              compact: true,
              // The app's one close (kute_back_button.dart).
              trailing: const AppBottomSheetCloseButton(
                  key: ValueKey('hl-chart-sheet-close')),
            ),
            Flexible(
              child: SingleChildScrollView(
                key: const ValueKey('hl-chart-sheet-scroll'),
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: sections,
                ),
              ),
            ),
            Container(height: 0.5, color: c.border),
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 2, 16.w, 2),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const ValueKey('hl-chart-sheet-reset'),
                  onPressed: isDefault ? null : _reset,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: 4.w),
                    minimumSize: Size(0, 44.h),
                    foregroundColor: c.textPrimary,
                    disabledForegroundColor: c.textTertiary,
                  ),
                  child: Text(
                    l10n.chartReset,
                    style: TextStyle(
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: 8.h, left: 2.w),
        child: Text(
          text,
          style: TextStyle(
            color: context.colors.textSecondary,
            fontSize: 13.sp,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}

/// A square card's box, in the app's big-square language (the option
/// cards of kute_action_cards.dart: the app's one soft card,
/// [KuteActionCard.surfaceOf], 14 padding, at least 112 tall, the press
/// spring). [picked] draws the selection the app's chips use: the CTA
/// colour, here as the card's 1.5 outline on the same soft card. The
/// Interval sheet (hl_chart_interval_sheet.dart) uses the same box, a
/// square at least [minHeight] tall.
class HlSquareBox extends StatelessWidget {
  const HlSquareBox({
    super.key,
    required this.picked,
    required this.child,
    this.minHeight = 112,
  });

  final bool picked;
  final Widget child;

  /// The least height (112, the option cards').
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final soft = KuteActionCard.surfaceOf(context);
    final ring = picked
        ? Border.all(color: context.ctaFill, width: 1.5)
        : soft.border as Border?;
    return KutePressable(
      child: AnimatedContainer(
        duration: reduce ? Duration.zero : const Duration(milliseconds: 150),
        constraints: BoxConstraints(minHeight: minHeight),
        // The content stays put as the ring thickens: the edge and the
        // padding always make 15.
        padding: EdgeInsets.all(15 - (ring?.top.width ?? 0)),
        decoration: soft.copyWith(border: ring),
        child: child,
      ),
    );
  }
}

/// One chart type: its mini chart and its name.
class _StyleCard extends StatelessWidget {
  const _StyleCard({
    required this.style,
    required this.picked,
    required this.candles,
    required this.onTap,
  });

  final HlChartStyle style;
  final bool picked;
  final List<HyperliquidCandle> candles;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final thumb = candles.length > kHlStyleThumbBars
        ? candles.sublist(candles.length - kHlStyleThumbBars)
        : candles;
    return Semantics(
      button: true,
      selected: picked,
      child: GestureDetector(
        key: ValueKey('hl-chart-style-${style.name}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: HlSquareBox(
          picked: picked,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 58,
                child: CustomPaint(
                  painter: HlStyleThumbPainter(
                    style: style,
                    candles: thumb,
                    up: AppColors.marketUp,
                    down: AppColors.marketDown,
                    muted: c.textTertiary,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _styleName(context.l10n, style),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A style's tiny chart of [candles]. With no bars, a gentle made-up
/// series so the card still reads.
class HlStyleThumbPainter extends CustomPainter {
  HlStyleThumbPainter({
    required this.style,
    required this.candles,
    required this.up,
    required this.down,
    required this.muted,
  });

  final HlChartStyle style;
  final List<HyperliquidCandle> candles;
  final Color up, down, muted;

  static const List<double> _placeholder = [
    3, 4, 3.6, 5, 4.4, 5.6, 5.1, 6.2, 5.8, 6.8, 6.1, 7.2, 6.9, 7.8, 7.4, //
    8.4,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final valid = candles
        .where((k) =>
            k.open.isFinite &&
            k.close.isFinite &&
            k.high.isFinite &&
            k.low.isFinite)
        .toList();
    final bars =
        style == HlChartStyle.heikinAshi ? hlHeikinAshi(valid) : valid;
    final real = bars.length >= 2;
    final closes = real ? [for (final k in bars) k.close] : _placeholder;
    final hollow = style == HlChartStyle.hollow;
    final candleLike = style == HlChartStyle.candles ||
        style == HlChartStyle.heikinAshi ||
        hollow;
    var lo = double.infinity, hi = double.negativeInfinity;
    if (candleLike && real) {
      for (final k in bars) {
        lo = math.min(lo, k.low);
        hi = math.max(hi, k.high);
      }
    } else {
      for (final v in closes) {
        lo = math.min(lo, v);
        hi = math.max(hi, v);
      }
    }
    if (hi <= lo) hi = lo + 1;
    double y(double v) => 1 + (size.height - 2) * (1 - (v - lo) / (hi - lo));
    final rising = closes.last >= closes.first;
    final color = real ? (rising ? up : down) : muted;

    if (candleLike) {
      final n = real ? bars.length : closes.length;
      final slot = size.width / n;
      final body = math.max(1.2, slot * 0.6);
      for (var i = 0; i < n; i++) {
        final o = real ? bars[i].open : (i == 0 ? closes[0] : closes[i - 1]);
        final cl = real ? bars[i].close : closes[i];
        final h = real ? bars[i].high : math.max(o, cl) + 0.3;
        final l = real ? bars[i].low : math.min(o, cl) - 0.3;
        // Hollow candles: the colour says the close against the previous
        // close, the outline a close above the open (as the chart draws).
        final risingBar =
            hollow && real && i > 0 ? cl >= bars[i - 1].close : cl >= o;
        final barColor = real ? (risingBar ? up : down) : muted;
        final x = (i + 0.5) * slot;
        final paint = Paint()
          ..color = barColor
          ..strokeWidth = 0.8;
        final top = y(math.max(o, cl));
        final bottom = math.max(top + 1, y(math.min(o, cl)));
        final rect = Rect.fromLTRB(x - body / 2, top, x + body / 2, bottom);
        if (hollow && cl >= o) {
          // The wick stops at the body; the inside stays empty.
          canvas.drawLine(Offset(x, y(h)), Offset(x, top), paint);
          canvas.drawLine(Offset(x, bottom), Offset(x, y(l)), paint);
          canvas.drawRect(
              rect.deflate(0.3),
              Paint()
                ..color = barColor
                ..style = PaintingStyle.stroke
                ..strokeWidth = 0.7);
        } else {
          canvas.drawLine(Offset(x, y(h)), Offset(x, y(l)), paint);
          canvas.drawRect(rect, paint);
        }
      }
      return;
    }

    final n = closes.length;
    final dx = size.width / (n - 1);
    final path = Path()..moveTo(0, y(closes.first));
    final isBaseline = style == HlChartStyle.baseline;
    for (var i = 1; i < n; i++) {
      // A light smoothing, as the chart's monotone line reads.
      final px = (i - 1) * dx, x = i * dx;
      final py = y(closes[i - 1]), cy = y(closes[i]);
      path.cubicTo(px + dx / 2, py, x - dx / 2, cy, x, cy);
    }
    if (style == HlChartStyle.area) {
      final fill = Path.from(path)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: 0.28),
              color.withValues(alpha: 0.0),
            ],
          ).createShader(Offset.zero & size),
      );
    }
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (isBaseline) {
      // Two tones either side of the first close, its hairline between.
      final baseY = y(closes.first);
      final fill = Path.from(path)
        ..lineTo(size.width, baseY)
        ..lineTo(0, baseY)
        ..close();
      final above = real ? up : muted;
      final below = real ? down : muted;
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, size.width, baseY));
      canvas.drawPath(fill, Paint()..color = above.withValues(alpha: 0.18));
      canvas.drawPath(path, stroke..color = above);
      canvas.restore();
      canvas.save();
      canvas.clipRect(
          Rect.fromLTWH(0, baseY, size.width, size.height - baseY));
      canvas.drawPath(fill, Paint()..color = below.withValues(alpha: 0.18));
      canvas.drawPath(path, stroke..color = below);
      canvas.restore();
      canvas.drawLine(
          Offset(0, baseY),
          Offset(size.width, baseY),
          Paint()
            ..color = muted.withValues(alpha: 0.5)
            ..strokeWidth = 0.6);
      return;
    }
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant HlStyleThumbPainter old) =>
      old.style != style ||
      !identical(old.candles, candles) ||
      old.up != up ||
      old.down != down ||
      old.muted != muted;
}

/// The cards' mini charts: every indicator over the market's own bars
/// (a made-up tape when the market has too few), with the market's
/// settings, cut to the newest [_kPreviewBars].
class _HlPreviews {
  _HlPreviews(this.tape, this.frame, this.profile);

  final List<HyperliquidCandle> tape;
  final HlIndicatorFrame frame;
  final HlVolumeProfile? profile;

  HlIndSeries? series(String key) {
    for (final s in [...frame.price, ...frame.panes]) {
      if (s.key == key) return s;
    }
    return null;
  }

  static _HlPreviews build(
      List<HyperliquidCandle> candles, Map<String, List<num>> params) {
    final source = candles.length >= 120 ? candles : _madeUpTape();
    final n = source.length;
    final start = math.max(0, n - _kPreviewBars);
    final frame = HlIndicatorComputer()
        .compute(
          source,
          kHlIndicatorKeys,
          params,
          up: AppColors.marketUp,
          down: AppColors.marketDown,
          // A preview's levels: the tape's own days (the chart reads real
          // daily candles).
          daily: hlDailyFromBars(source),
        )
        .slice(start, n);
    final tape = source.sublist(start);
    final rows = hlIndParams('vp', params).first.round();
    return _HlPreviews(
      tape,
      frame,
      hlVolumeProfile(tape, rows: math.min(rows, 16)),
    );
  }

  /// A gently swinging 260-bar tape for a market with little history.
  static List<HyperliquidCandle> _madeUpTape() {
    final start = DateTime.utc(2026, 1, 1);
    final out = <HyperliquidCandle>[];
    var prev = 100.0;
    for (var i = 0; i < 260; i++) {
      final c = 100 + 8 * math.sin(i / 9) + 3 * math.cos(i / 2.7) + i * 0.04;
      final o = prev;
      out.add(HyperliquidCandle(
        openTime: start.add(Duration(hours: i)),
        closeTime: start.add(Duration(hours: i + 1)),
        open: o,
        high: math.max(o, c) + 0.6 + (i % 4) * 0.25,
        low: math.min(o, c) - 0.5 - (i % 3) * 0.2,
        close: c,
        volume: 60 + (i * 37) % 50 + 30 * math.sin(i / 5).abs(),
      ));
      prev = c;
    }
    return out;
  }
}

/// One indicator: its mini chart (and, on, its settings button), its name
/// with its settings, and what it shows.
class _IndicatorCard extends StatelessWidget {
  const _IndicatorCard({
    required this.spec,
    required this.on,
    required this.params,
    required this.previews,
    required this.onTap,
    required this.onSettings,
  });

  final HlIndSpec spec;
  final bool on;
  final List<num> params;
  final _HlPreviews previews;
  final VoidCallback onTap;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final tunable = on && spec.params.isNotEmpty;
    return _ToggleCard(
      cardKey: ValueKey('hl-chart-indicator-${spec.key}'),
      on: on,
      painter: HlIndicatorPreviewPainter(
        keyName: spec.key,
        series: previews.series(spec.key),
        tape: previews.tape,
        profile: previews.profile,
        on: on,
        muted: c.textTertiary,
        up: AppColors.marketUp,
        down: AppColors.marketDown,
      ),
      trailing: tunable
          ? _TuneButton(
              key: ValueKey('hl-chart-indicator-settings-${spec.key}'),
              onTap: onSettings,
            )
          : null,
      name: hlIndicatorName(l10n, spec.key),
      defaults:
          spec.params.isEmpty ? null : params.map(hlParamText).join(' '),
      note: _note(l10n, spec.key),
      onTap: onTap,
    );
  }
}

/// A square card that switches something on or off: its mini chart (and,
/// on an indicator that is on, its settings button), its name with its
/// settings in small grey, and one line on what it shows.
class _ToggleCard extends StatelessWidget {
  const _ToggleCard({
    required this.cardKey,
    required this.on,
    required this.painter,
    required this.name,
    required this.note,
    required this.onTap,
    this.defaults,
    this.trailing,
  });

  final Key cardKey;
  final bool on;
  final CustomPainter painter;
  final String name;
  final String? defaults;
  final String note;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final trailing = this.trailing;
    final defaults = this.defaults;
    return Semantics(
      button: true,
      toggled: on,
      child: GestureDetector(
        key: cardKey,
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: HlSquareBox(
          picked: on,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 30,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: CustomPaint(painter: painter)),
                    if (trailing != null) ...[
                      const SizedBox(width: 6),
                      trailing,
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 9),
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: name),
                  if (defaults != null)
                    TextSpan(
                      text: '  $defaults',
                      style: TextStyle(
                        color: c.textTertiary,
                        fontWeight: FontWeight.w500,
                        fontSize: 12.sp,
                      ),
                    ),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                note,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.textSecondary,
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w500,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TuneButton extends StatelessWidget {
  const _TuneButton({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: context.l10n.settings,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: SizedBox(
          width: 30,
          height: 30,
          child: Center(
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: c.textPrimary.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.tune_rounded, size: 15, color: c.textPrimary),
            ),
          ),
        ),
      ),
    );
  }
}

/// An indicator card's mini chart: what it draws on the price (over a
/// faint close line) or in its pane, in its colours while [on] and in
/// [muted] grey while off.
class HlIndicatorPreviewPainter extends CustomPainter {
  HlIndicatorPreviewPainter({
    required this.keyName,
    required this.series,
    required this.tape,
    required this.profile,
    required this.on,
    required this.muted,
    required this.up,
    required this.down,
  });

  final String keyName;
  final HlIndSeries? series;
  final List<HyperliquidCandle> tape;
  final HlVolumeProfile? profile;
  final bool on;
  final Color muted, up, down;

  Color _tone(Color c) => on ? c : muted.withValues(alpha: 0.7);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || tape.length < 2) return;
    final n = tape.length;
    final slot = size.width / n;
    double x(int i) => (i + 0.5) * slot;
    final spec = hlIndSpec(keyName);
    if (spec == null) return;

    if (keyName == 'vol') {
      var maxV = 0.0;
      for (final k in tape) {
        maxV = math.max(maxV, k.volume);
      }
      if (maxV <= 0) return;
      final w = math.max(1.0, slot * 0.6);
      for (var i = 0; i < n; i++) {
        final k = tape[i];
        final h = size.height * k.volume / maxV;
        canvas.drawRect(
          Rect.fromLTWH(x(i) - w / 2, size.height - h, w, h),
          Paint()
            ..color = _tone(k.close >= k.open ? up : down)
                .withValues(alpha: on ? 0.7 : 0.45),
        );
      }
      return;
    }

    final s = series;
    if (spec.place == HlIndPlace.pane) {
      if (s == null) return;
      var lo = double.infinity, hi = double.negativeInfinity;
      void take(List<double> v) {
        for (final e in v) {
          if (!e.isFinite) continue;
          lo = math.min(lo, e);
          hi = math.max(hi, e);
        }
      }

      for (final l in s.lines) {
        take(l.values);
      }
      take(s.histogram ?? const []);
      final range = s.range;
      if (range != null) {
        lo = range.$1;
        hi = range.$2;
      }
      if (!lo.isFinite || !hi.isFinite) return;
      if (hi <= lo) hi = lo + 1;
      double y(double v) =>
          1 + (size.height - 2) * (1 - (v - lo) / (hi - lo));
      final guide = Paint()
        ..color = muted.withValues(alpha: 0.35)
        ..strokeWidth = 0.6;
      for (final level in s.levels) {
        if (level < lo || level > hi) continue;
        canvas.drawLine(
            Offset(0, y(level)), Offset(size.width, y(level)), guide);
      }
      final hist = s.histogram;
      if (hist != null) {
        final w = math.max(1.0, slot * 0.6);
        final zero = y(0).clamp(0.0, size.height);
        for (var i = 0; i < math.min(n, hist.length); i++) {
          final v = hist[i];
          if (!v.isFinite) continue;
          canvas.drawRect(
            Rect.fromLTRB(x(i) - w / 2, math.min(y(v), zero), x(i) + w / 2,
                math.max(y(v), zero)),
            Paint()..color = _tone(v >= 0 ? up : down).withValues(alpha: 0.45),
          );
        }
      }
      for (final l in s.lines) {
        _line(canvas, l.values, x, y, _tone(l.color), 1.4);
      }
      return;
    }

    // On the price: a faint close line, the indicator over it.
    final closes = [for (final k in tape) k.close];
    var lo = double.infinity, hi = double.negativeInfinity;
    for (final v in closes) {
      lo = math.min(lo, v);
      hi = math.max(hi, v);
    }
    final lines = keyName == 'pp'
        ? [
            for (final l in s?.lines ?? const <HlIndLine>[])
              HlIndLine(_newestStretch(l.values), l.color),
          ]
        : s?.lines ?? const <HlIndLine>[];
    for (final l in lines) {
      for (final v in l.values) {
        if (!v.isFinite) continue;
        lo = math.min(lo, v);
        hi = math.max(hi, v);
      }
    }
    if (hi <= lo) hi = lo + 1;
    double y(double v) => 1 + (size.height - 2) * (1 - (v - lo) / (hi - lo));
    final band = s?.band;
    if (band != null) {
      final path = Path();
      var started = false;
      for (var i = 0; i < n && i < band.upper.length; i++) {
        final u = band.upper[i];
        if (!u.isFinite) continue;
        started ? path.lineTo(x(i), y(u)) : path.moveTo(x(i), y(u));
        started = true;
      }
      for (var i = math.min(n, band.lower.length) - 1; i >= 0; i--) {
        final l = band.lower[i];
        if (!l.isFinite) continue;
        path.lineTo(x(i), y(l));
      }
      if (started) {
        path.close();
        canvas.drawPath(
            path, Paint()..color = _tone(band.color).withValues(alpha: 0.12));
      }
    }
    final cloud = s?.cloud;
    if (cloud != null) {
      hlPaintIchimokuCloud(canvas, cloud, slot, y,
          alpha: 0.22, tint: on ? null : muted);
    }
    final p = profile;
    if (keyName == 'vp' && p != null) {
      final maxRow = p.maxRow;
      if (maxRow > 0) {
        for (var r = 0; r < p.rows; r++) {
          final t = p.total(r);
          if (t <= 0) continue;
          final y0 = y(p.lo + (r + 1) * p.rowHeight) + 0.5;
          final y1 = y(p.lo + r * p.rowHeight) - 0.5;
          final len = size.width * 0.45 * t / maxRow;
          final inArea = r >= p.vaLow && r <= p.vaHigh;
          canvas.drawRect(
            Rect.fromLTRB(size.width - len, math.min(y0, y1), size.width,
                math.max(y0, y1)),
            Paint()
              ..color = _tone(r == p.poc ? const Color(0xFFF59E0B) : up)
                  .withValues(alpha: inArea ? 0.45 : 0.22),
          );
        }
      }
    }
    _line(canvas, closes, x, y, muted.withValues(alpha: on ? 0.55 : 0.4), 1.1);
    for (final l in lines) {
      _line(canvas, l.values, x, y, _tone(l.color), 1.5);
    }
  }

  /// Pivots' card draws one day's levels: their newest stretch.
  static List<double> _newestStretch(List<double> values) {
    var end = values.length - 1;
    while (end >= 0 && !values[end].isFinite) {
      end--;
    }
    var start = end;
    while (start > 0 && values[start - 1].isFinite) {
      start--;
    }
    return [
      for (var i = 0; i < values.length; i++)
        i >= start && i <= end ? values[i] : double.nan,
    ];
  }

  static void _line(Canvas canvas, List<double> values, double Function(int) x,
      double Function(double) y, Color color, double width) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    Path? path;
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (!v.isFinite) {
        if (path != null) canvas.drawPath(path, paint);
        path = null;
        continue;
      }
      if (path == null) {
        path = Path()..moveTo(x(i), y(v));
      } else {
        path.lineTo(x(i), y(v));
      }
    }
    if (path != null) canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant HlIndicatorPreviewPainter old) =>
      old.keyName != keyName ||
      !identical(old.series, series) ||
      !identical(old.tape, tape) ||
      !identical(old.profile, profile) ||
      old.on != on ||
      old.muted != muted ||
      old.up != up ||
      old.down != down;
}

/// The Log scale card's mini chart: the market's closes on a log axis
/// over guide lines bunching toward the top, as a log axis' round prices
/// do; in its colours while [on], grey while off.
class HlLogPreviewPainter extends CustomPainter {
  HlLogPreviewPainter({
    required this.tape,
    required this.on,
    required this.muted,
    required this.up,
    required this.down,
  });

  final List<HyperliquidCandle> tape;
  final bool on;
  final Color muted, up, down;

  /// Where the guides sit, as shares of the height from the top.
  static const List<double> _guides = [0.04, 0.16, 0.36, 0.68];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final guide = Paint()
      ..color = muted.withValues(alpha: on ? 0.45 : 0.3)
      ..strokeWidth = 0.6;
    for (final share in _guides) {
      final y = size.height * share;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), guide);
    }
    final logs = [
      for (final k in tape)
        if (k.close > 0) math.log(k.close),
    ];
    if (logs.length < 2) return;
    var lo = logs.first, hi = logs.first;
    for (final v in logs) {
      lo = math.min(lo, v);
      hi = math.max(hi, v);
    }
    if (hi <= lo) hi = lo + 1;
    final path = Path();
    for (var i = 0; i < logs.length; i++) {
      final x = (i + 0.5) * size.width / logs.length;
      final y = 2 + (size.height - 4) * (1 - (logs[i] - lo) / (hi - lo));
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    final rising = logs.last >= logs.first;
    canvas.drawPath(
      path,
      Paint()
        ..color = on
            ? (rising ? up : down)
            : muted.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant HlLogPreviewPainter old) =>
      !identical(old.tape, tape) ||
      old.on != on ||
      old.muted != muted ||
      old.up != up ||
      old.down != down;
}

// ─────────────────────────── settings ───────────────────────────

String _paramLabel(AppLocalizations l10n, String id) => switch (id) {
      'length' => l10n.chartParamLength,
      'fast' => l10n.chartParamFast,
      'slow' => l10n.chartParamSlow,
      'signal' => l10n.chartParamSignal,
      'multiplier' => l10n.chartParamMultiplier,
      'rsiLength' => l10n.chartParamRsiLength,
      'stochLength' => l10n.chartParamStochLength,
      'smoothK' => l10n.chartParamSmoothK,
      'smoothD' => l10n.chartParamSmoothD,
      'rows' => l10n.chartParamRows,
      'smoothing' => l10n.chartParamSmoothing,
      'conversion' => l10n.chartParamConversion,
      'base' => l10n.chartParamBase,
      'spanB' => l10n.chartParamSpanB,
      'displacement' => l10n.chartParamDisplacement,
      _ => id,
    };

/// One indicator's settings on [market]: a stepper per setting (a hold
/// repeats, faster after a moment) and Reset. Changes apply as they are
/// made; closing the sheet sends one `indicator_settings_changed` with
/// the values it was left at.
Future<void> showHlIndicatorSettings(
  BuildContext context, {
  required HlMarket market,
  required String marketKey,
  required String indicator,
}) {
  return showAppBottomSheet<void>(
    context: context,
    builder: (_) => HlIndicatorSettingsSheet(
      market: market,
      marketKey: marketKey,
      indicator: indicator,
    ),
  );
}

class HlIndicatorSettingsSheet extends ConsumerStatefulWidget {
  const HlIndicatorSettingsSheet({
    super.key,
    required this.market,
    required this.marketKey,
    required this.indicator,
  });

  final HlMarket market;
  final String marketKey;
  final String indicator;

  @override
  ConsumerState<HlIndicatorSettingsSheet> createState() =>
      _HlIndicatorSettingsSheetState();
}

class _HlIndicatorSettingsSheetState
    extends ConsumerState<HlIndicatorSettingsSheet> {
  late final List<num> _opened;
  late final ChartPreferencesNotifier _notifier;
  List<num> _last = const [];

  @override
  void initState() {
    super.initState();
    _notifier =
        ref.read(hlChartPreferencesProvider(widget.marketKey).notifier);
    _opened = hlIndParams(widget.indicator,
        ref.read(hlChartPreferencesProvider(widget.marketKey)).params);
    _last = _opened;
  }

  @override
  void dispose() {
    final spec = hlIndSpec(widget.indicator);
    var changed = false;
    for (var i = 0; i < _last.length; i++) {
      if (i >= _opened.length || _last[i] != _opened[i]) changed = true;
    }
    if (spec != null && changed) {
      TrackingService.track('indicator_settings_changed', params: {
        'indicator': widget.indicator,
        for (var i = 0; i < spec.params.length && i < _last.length; i++)
          spec.params[i].id: _last[i],
        'coin': widget.market.coin,
        ...VenueAnalytics.hlAssetParams(widget.market.coin),
      });
    }
    super.dispose();
  }

  void _set(int index, num value) {
    final next = [..._last];
    final spec = hlIndSpec(widget.indicator)!;
    next[index] = spec.params[index].clamp(value);
    if (next[index] == _last[index]) return;
    _last = next;
    _notifier.setParams(widget.indicator, next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.colors;
    final spec = hlIndSpec(widget.indicator);
    if (spec == null) return const SizedBox.shrink();
    final values = hlIndParams(widget.indicator,
        ref.watch(hlChartPreferencesProvider(widget.marketKey)).params);
    _last = values;
    final isDefault = [
      for (var i = 0; i < values.length; i++)
        values[i] == spec.params[i].defaultValue,
    ].every((v) => v);
    return KuteBarContextScope(
      barContext: const KuteBarContext.hidden(),
      child: AppBottomSheetContainer(
        child: Column(
          key: ValueKey('hl-indicator-settings-${widget.indicator}'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppBottomSheetHeader(
              title: l10n.chartIndSettingsTitle(
                  hlIndicatorName(l10n, widget.indicator)),
              compact: true,
              // The app's one close (kute_back_button.dart).
              trailing: const AppBottomSheetCloseButton(
                  key: ValueKey('hl-indicator-settings-close')),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              child: Container(
                decoration: BoxDecoration(
                  color: context.isDark ? c.surfaceLight : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: context.isDark ? c.borderSubtle : c.border,
                    width: context.isDark ? 0.5 : 1,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < spec.params.length; i++) ...[
                      if (i > 0)
                        Padding(
                          padding: const EdgeInsets.only(left: 16),
                          child: Container(height: 0.5, color: c.border),
                        ),
                      _StepperRow(
                        key: ValueKey(
                            'hl-indicator-param-${spec.params[i].id}'),
                        label: _paramLabel(l10n, spec.params[i].id),
                        param: spec.params[i],
                        value: values[i],
                        onChanged: (v) => _set(i, v),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 6, 16.w, 2),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const ValueKey('hl-indicator-settings-reset'),
                  onPressed: isDefault
                      ? null
                      : () {
                          HapticFeedback.selectionClick();
                          _last = spec.defaults;
                          _notifier.setParams(widget.indicator, null);
                        },
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: 4.w),
                    minimumSize: Size(0, 44.h),
                    foregroundColor: c.textPrimary,
                    disabledForegroundColor: c.textTertiary,
                  ),
                  child: Text(
                    l10n.chartReset,
                    style:
                        TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A setting's row: its name, then − value +. A hold on − or + repeats,
/// five steps at a time after the first ten.
class _StepperRow extends StatefulWidget {
  const _StepperRow({
    super.key,
    required this.label,
    required this.param,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final HlIndParam param;
  final num value;
  final ValueChanged<num> onChanged;

  @override
  State<_StepperRow> createState() => _StepperRowState();
}

class _StepperRowState extends State<_StepperRow> {
  Timer? _repeat;
  int _ticks = 0;
  late num _value = widget.value;

  @override
  void didUpdateWidget(covariant _StepperRow old) {
    super.didUpdateWidget(old);
    if (_repeat == null) _value = widget.value;
  }

  @override
  void dispose() {
    _repeat?.cancel();
    super.dispose();
  }

  void _step(int direction, {int times = 1}) {
    final next = widget.param.clamp(_value + direction * widget.param.step * times);
    if (next == _value) return;
    setState(() => _value = next);
    widget.onChanged(next);
  }

  void _startRepeat(int direction) {
    _ticks = 0;
    _repeat?.cancel();
    _repeat = Timer.periodic(const Duration(milliseconds: 80), (_) {
      _ticks++;
      _step(direction, times: _ticks > 10 ? 5 : 1);
    });
  }

  void _stopRepeat() {
    _repeat?.cancel();
    _repeat = null;
  }

  Widget _button(IconData icon, int direction, String id) {
    final c = context.colors;
    final atEnd = direction < 0
        ? _value <= widget.param.min
        : _value >= widget.param.max;
    return GestureDetector(
      key: ValueKey('hl-indicator-step-$id'),
      behavior: HitTestBehavior.opaque,
      onTap: atEnd
          ? null
          : () {
              HapticFeedback.selectionClick();
              _step(direction);
            },
      onLongPressStart: atEnd ? null : (_) => _startRepeat(direction),
      onLongPressEnd: (_) => _stopRepeat(),
      onLongPressCancel: _stopRepeat,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: c.textPrimary.withValues(alpha: atEnd ? 0.03 : 0.07),
              shape: BoxShape.circle,
            ),
            child: Icon(icon,
                size: 18,
                color: atEnd ? c.textTertiary : c.textPrimary),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                widget.label,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            _button(Icons.remove_rounded, -1, '${widget.param.id}-down'),
            SizedBox(
              width: 48,
              child: Text(
                hlParamText(_value),
                key: ValueKey('hl-indicator-value-${widget.param.id}'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            _button(Icons.add_rounded, 1, '${widget.param.id}-up'),
          ],
        ),
      ),
    );
  }
}
