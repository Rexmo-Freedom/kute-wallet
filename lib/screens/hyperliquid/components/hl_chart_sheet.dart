// lib/screens/hyperliquid/components/hl_chart_sheet.dart
//
// The Hyperliquid chart's one picker sheet (founder, 1 November 2026: "we
// have too many chart styles, this screen is too much; the indicators look
// like slop"). Opened from the in-page chart button, and in the Advanced
// editor from its style and Σ buttons (which show one half each):
//
//   * STYLE: Line, Candles, Area as three side-by-side cards, each with a
//     tiny thumbnail of the market's last ~30 bars drawn in that style.
//     The picked card has the app's selection look (the range row's
//     thumb); a pick applies at once and the sheet stays up.
//   * INDICATORS: one soft card of six rows, each a plain name, a one-line
//     explanation and a switch: Volume, Moving averages (EMA 9/21),
//     Bollinger bands, RSI, MACD, VWAP. Volume, RSI and MACD sit below the
//     price, and two of them fit: switching on a third turns the oldest
//     off, with a short toast.
//   * Reset (bottom left) puts back what a fresh install shows: Line, and
//     Volume alone.
//
// A picker: the floating Sal bar hides while it is up.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart' show HlMarket;
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/providers/chart_drawings_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_intervals.dart';
import 'package:kute/screens/hyperliquid/components/hl_charts.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/venue_analytics.dart';
import 'package:kute/theme/app_theme.dart';

/// The rows of the indicators list, in order.
const List<String> kHlSheetIndicators = [
  'vol',
  'ema',
  'bb',
  'rsi',
  'macd',
  'vwap',
];

/// The indicators drawn below the price (Volume's band counts as one).
const Set<String> kHlBelowIndicators = {'vol', 'rsi', 'macd'};

/// How many of [kHlBelowIndicators] can be on at once.
const int kHlMaxBelowPanes = 2;

/// What a fresh chart shows.
const Set<String> kHlDefaultIndicators = {'vol'};

/// Bars a style thumbnail draws.
const int kHlStyleThumbBars = 30;

/// Switching [key] in [current] (its order is the order the indicators
/// were switched on: the oldest first). Switching on a third pane below
/// the chart turns the oldest one off; [replaced] names it.
({List<String> next, String? replaced}) hlToggleSheetIndicator(
  Iterable<String> current,
  String key,
) {
  final next = [...current];
  if (next.remove(key)) return (next: next, replaced: null);
  String? replaced;
  if (kHlBelowIndicators.contains(key)) {
    final below = next.where(kHlBelowIndicators.contains).toList();
    if (below.length >= kHlMaxBelowPanes) {
      replaced = below.first;
      next.remove(replaced);
    }
  }
  next.add(key);
  return (next: next, replaced: replaced);
}

/// Opens the Chart sheet for [market]. [candles] feed the style
/// thumbnails (the bars the chart shows). [showStyle] / [showIndicators]
/// pick the halves (the Advanced editor opens one each).
Future<void> showHlChartSheet(
  BuildContext context, {
  required HlMarket market,
  required String marketKey,
  required List<HyperliquidCandle> candles,
  bool showStyle = true,
  bool showIndicators = true,
}) {
  HapticFeedback.selectionClick();
  return showAppBottomSheet<void>(
    context: context,
    builder: (_) => HlChartSheet(
      market: market,
      marketKey: marketKey,
      candles: candles,
      showStyle: showStyle,
      showIndicators: showIndicators,
    ),
  );
}

class HlChartSheet extends ConsumerWidget {
  const HlChartSheet({
    super.key,
    required this.market,
    required this.marketKey,
    required this.candles,
    this.showStyle = true,
    this.showIndicators = true,
  });

  final HlMarket market;
  final String marketKey;
  final List<HyperliquidCandle> candles;
  final bool showStyle;
  final bool showIndicators;

  Map<String, Object> get _assetParams => {
        'coin': market.coin,
        ...VenueAnalytics.hlAssetParams(market.coin),
      };

  void _pickStyle(WidgetRef ref, HlChartStyle style) {
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

  void _toggle(BuildContext context, WidgetRef ref, String key) {
    HapticFeedback.selectionClick();
    final l10n = context.l10n;
    final current = ref.read(hlChartPreferencesProvider(marketKey)).indicators;
    final r = hlToggleSheetIndicator(current, key);
    ref
        .read(hlChartPreferencesProvider(marketKey).notifier)
        .setIndicators(r.next);
    TrackingService.track('indicator_toggled', params: {
      'indicator': key,
      'enabled': r.next.contains(key),
      ..._assetParams,
    });
    final replaced = r.replaced;
    if (replaced != null) {
      TrackingService.track('indicator_toggled', params: {
        'indicator': replaced,
        'enabled': false,
        'via': 'pane_limit',
        ..._assetParams,
      });
      showMessageSnackBarInfo(
        context: context,
        message: l10n.chartPaneLimit(hlSheetIndicatorName(l10n, replaced)),
        duration: const Duration(seconds: 3),
      );
    }
  }

  void _reset(WidgetRef ref) {
    HapticFeedback.selectionClick();
    if (showStyle) {
      _pickStyle(ref, HlChartStyle.fromName(kHlDefaultChartStyle));
    }
    if (showIndicators) {
      final current =
          ref.read(hlChartPreferencesProvider(marketKey)).indicators;
      for (final key in {...current, ...kHlDefaultIndicators}) {
        final on = kHlDefaultIndicators.contains(key);
        if (current.contains(key) == on) continue;
        TrackingService.track('indicator_toggled', params: {
          'indicator': key,
          'enabled': on,
          'via': 'reset',
          ..._assetParams,
        });
      }
      ref
          .read(hlChartPreferencesProvider(marketKey).notifier)
          .setIndicators(kHlDefaultIndicators);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final c = context.colors;
    final style = HlChartStyle.fromName(ref.watch(hlChartLayoutProvider).style);
    final on = ref.watch(hlChartPreferencesProvider(marketKey)).indicators;
    final isDefault =
        (!showStyle || style == HlChartStyle.fromName(kHlDefaultChartStyle)) &&
            (!showIndicators ||
                (on.length == kHlDefaultIndicators.length &&
                    on.containsAll(kHlDefaultIndicators)));
    final title = showStyle && showIndicators
        ? l10n.chartSheetTitle
        : (showStyle ? l10n.chartStyleTitle : l10n.chartIndicators);
    // A picker: the floating bar is away while it is up.
    return KuteBarContextScope(
      barContext: const KuteBarContext.hidden(),
      child: AppBottomSheetContainer(
        child: Column(
          key: const ValueKey('hl-chart-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppBottomSheetHeader(
              title: title,
              compact: true,
              // The app's one close (kute_back_button.dart).
              trailing: const AppBottomSheetCloseButton(
                  key: ValueKey('hl-chart-sheet-close')),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showStyle) ...[
                    if (showIndicators) _SectionLabel(l10n.chartSheetStyle),
                    Row(
                      children: [
                        for (var i = 0;
                            i < HlChartStyle.picker.length;
                            i++) ...[
                          if (i > 0) SizedBox(width: 10.w),
                          Expanded(
                            child: _StyleCard(
                              style: HlChartStyle.picker[i],
                              picked: HlChartStyle.picker[i] == style,
                              candles: candles,
                              onTap: () =>
                                  _pickStyle(ref, HlChartStyle.picker[i]),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                  if (showStyle && showIndicators) SizedBox(height: 20.h),
                  if (showIndicators) ...[
                    if (showStyle) _SectionLabel(l10n.chartIndicators),
                    _IndicatorCard(
                      on: on,
                      onToggle: (key) => _toggle(context, ref, key),
                    ),
                  ],
                  SizedBox(height: 6.h),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      key: const ValueKey('hl-chart-sheet-reset'),
                      onPressed: isDefault ? null : () => _reset(ref),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.symmetric(horizontal: 4.w),
                        minimumSize: Size(0, 40.h),
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A row's plain name.
String hlSheetIndicatorName(AppLocalizations l10n, String key) => switch (key) {
      'vol' => l10n.chartVolume,
      'ema' => l10n.chartIndEma,
      'bb' => l10n.chartIndBb,
      'rsi' => l10n.chartIndRsi,
      'macd' => l10n.chartIndMacd,
      'vwap' => l10n.chartIndVwap,
      _ => key,
    };

String _note(AppLocalizations l10n, String key) => switch (key) {
      'vol' => l10n.chartIndVolumeNote,
      'ema' => l10n.chartIndEmaNote,
      'bb' => l10n.chartIndBbNote,
      'rsi' => l10n.chartIndRsiNote,
      'macd' => l10n.chartIndMacdNote,
      'vwap' => l10n.chartIndVwapNote,
      _ => '',
    };

String _styleName(AppLocalizations l10n, HlChartStyle style) => switch (style) {
      HlChartStyle.line => l10n.chartStyleLine,
      HlChartStyle.area => l10n.chartStyleArea,
      _ => l10n.chartStyleCandles,
    };

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
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

/// One style card: the thumbnail and the name under it.
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
    final isLight = !context.isDark;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
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
        child: AnimatedContainer(
          duration: reduce ? Duration.zero : const Duration(milliseconds: 150),
          height: 84,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 9),
          decoration: BoxDecoration(
            // The range row's thumb when picked; flat otherwise.
            color: picked
                ? (isLight ? Colors.white : c.surfaceElevated)
                : c.surfaceLight,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: picked
                  ? (isLight ? c.border : c.borderSubtle)
                  : Colors.transparent,
              width: isLight ? 1.0 : 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: picked && isLight
                    ? Colors.black.withValues(alpha: 0.04)
                    : Colors.transparent,
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
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
              const SizedBox(height: 7),
              Text(
                _styleName(context.l10n, style),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: picked ? c.textPrimary : c.textSecondary,
                  fontSize: 13.sp,
                  fontWeight: picked ? FontWeight.w600 : FontWeight.w500,
                  height: 1.1,
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
    3,
    4,
    3.6,
    5,
    4.4,
    5.6,
    5.1,
    6.2,
    5.8,
    6.8,
    6.1,
    7.2,
    6.9,
    7.8,
    7.4,
    8.4,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final bars = candles
        .where((k) =>
            k.open.isFinite &&
            k.close.isFinite &&
            k.high.isFinite &&
            k.low.isFinite)
        .toList();
    final real = bars.length >= 2;
    final closes = real ? [for (final k in bars) k.close] : _placeholder;
    var lo = double.infinity, hi = double.negativeInfinity;
    if (style == HlChartStyle.candles && real) {
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

    if (style == HlChartStyle.candles) {
      final n = real ? bars.length : closes.length;
      final slot = size.width / n;
      final body = math.max(1.2, slot * 0.6);
      for (var i = 0; i < n; i++) {
        final o = real ? bars[i].open : (i == 0 ? closes[0] : closes[i - 1]);
        final cl = real ? bars[i].close : closes[i];
        final h = real ? bars[i].high : math.max(o, cl) + 0.3;
        final l = real ? bars[i].low : math.min(o, cl) - 0.3;
        final barColor = real ? (cl >= o ? up : down) : muted;
        final x = (i + 0.5) * slot;
        final paint = Paint()..color = barColor;
        canvas.drawLine(
            Offset(x, y(h)), Offset(x, y(l)), paint..strokeWidth = 0.8);
        final top = y(math.max(o, cl));
        final bottom = math.max(top + 1, y(math.min(o, cl)));
        canvas.drawRect(
            Rect.fromLTRB(x - body / 2, top, x + body / 2, bottom), paint);
      }
      return;
    }

    final n = closes.length;
    final dx = size.width / (n - 1);
    final path = Path()..moveTo(0, y(closes.first));
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
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant HlStyleThumbPainter old) =>
      old.style != style ||
      !identical(old.candles, candles) ||
      old.up != up ||
      old.down != down ||
      old.muted != muted;
}

/// The soft card of indicator rows.
class _IndicatorCard extends StatelessWidget {
  const _IndicatorCard({required this.on, required this.onToggle});

  final Set<String> on;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final isLight = !context.isDark;
    return Container(
      decoration: BoxDecoration(
        color: isLight ? Colors.white : c.surfaceLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLight ? c.border : c.borderSubtle,
          width: isLight ? 1.0 : 0.5,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < kHlSheetIndicators.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Container(height: 0.5, color: c.border),
              ),
            _IndicatorRow(
              keyName: kHlSheetIndicators[i],
              name: hlSheetIndicatorName(l10n, kHlSheetIndicators[i]),
              note: _note(l10n, kHlSheetIndicators[i]),
              value: on.contains(kHlSheetIndicators[i]),
              onToggle: () => onToggle(kHlSheetIndicators[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _IndicatorRow extends StatelessWidget {
  const _IndicatorRow({
    required this.keyName,
    required this.name,
    required this.note,
    required this.value,
    required this.onToggle,
  });

  final String keyName;
  final String name;
  final String note;
  final bool value;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return MergeSemantics(
      child: InkWell(
        key: ValueKey('hl-chart-indicator-$keyName'),
        onTap: onToggle,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w500,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        note,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.textSecondary,
                          fontSize: 13.sp,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                // The Settings switch's look.
                Switch(
                  key: ValueKey('hl-chart-indicator-switch-$keyName'),
                  value: value,
                  onChanged: (_) => onToggle(),
                  activeThumbColor: context.ctaOnColor,
                  activeTrackColor: context.ctaFill,
                  inactiveThumbColor: c.textSecondary,
                  inactiveTrackColor:
                      context.isDark ? c.surfaceElevated : c.surfaceLight,
                  trackOutlineColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected)
                        ? Colors.transparent
                        : c.borderSubtle,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
