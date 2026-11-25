// lib/screens/hyperliquid/components/hl_drawing_settings_sheet.dart
//
// A selected drawing's settings, behind the tune button of its floating
// toolbar: line width, fill opacity (filled shapes), labels on or off,
// text size (notes) and, for a Fibonacci retracement, its levels on or
// off. Only the rows its tool offers are shown (ChartDrawingSpec.settings).
// The indicator settings sheet's look: one card of rows, the shared
// stepper (HlStepperRow), the settings toggle, Reset under it.
//
// Every change is saved at once, one undoable step, on the drawing's own
// optional fields (ChartDrawing.width, fill, labels, textSize, levels), so
// drawings saved before these existed load unchanged.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/chart_drawing.dart';
import 'package:kute/providers/chart_drawings_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_indicator_catalog.dart'
    show HlIndParam;
import 'package:kute/screens/hyperliquid/components/hl_chart_sheet.dart'
    show HlStepperRow;
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/theme/app_theme.dart';

/// Opens the settings of drawing [drawingId] on [marketKey]. [onClosed]
/// gets the settings changed while it was up ('width', 'fill', 'labels',
/// 'text_size', 'levels', 'reset'), for the editor's tracking.
Future<void> showHlDrawingSettings(
  BuildContext context, {
  required String marketKey,
  required String drawingId,
  required String title,
  ValueChanged<Set<String>>? onClosed,
}) =>
    showAppBottomSheet<void>(
      context: context,
      builder: (_) => HlDrawingSettingsSheet(
        marketKey: marketKey,
        drawingId: drawingId,
        title: title,
        onClosed: onClosed,
      ),
    );

/// A Fibonacci level as the chart writes it: "61.8%".
String hlFibLevelText(double ratio) =>
    '${NumberFormat('#,##0.#').format(ratio * 100)}%';

class HlDrawingSettingsSheet extends ConsumerStatefulWidget {
  const HlDrawingSettingsSheet({
    super.key,
    required this.marketKey,
    required this.drawingId,
    required this.title,
    this.onClosed,
  });

  final String marketKey;
  final String drawingId;
  final String title;
  final ValueChanged<Set<String>>? onClosed;

  @override
  ConsumerState<HlDrawingSettingsSheet> createState() =>
      _HlDrawingSettingsSheetState();
}

class _HlDrawingSettingsSheetState
    extends ConsumerState<HlDrawingSettingsSheet> {
  final Set<String> _changed = {};
  late final ChartDrawingsNotifier _notifier =
      ref.read(hlChartDrawingsProvider(widget.marketKey).notifier);

  /// The drawing as last written here: the store's copy lands after the
  /// initial load, so quick steps build on this one.
  ChartDrawing? _last;

  @override
  void dispose() {
    if (_changed.isNotEmpty) widget.onClosed?.call(Set.unmodifiable(_changed));
    super.dispose();
  }

  void _write(ChartDrawing next, String action) {
    _last = next;
    _changed.add(action);
    _notifier.update(next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.colors;
    final stored = ref
        .watch(hlChartDrawingsProvider(widget.marketKey))
        .where((d) => d.id == widget.drawingId)
        .firstOrNull;
    final drawing =
        _last != null && _last!.id == stored?.id ? _last! : stored;
    _last = drawing;
    if (drawing == null) return const SizedBox.shrink();
    final spec = chartDrawingSpec(drawing.tool);
    final offers = spec.settings;
    final percent = NumberFormat.percentPattern();

    final rows = <Widget>[
      if (offers.contains(ChartDrawingSetting.width))
        HlStepperRow(
          key: const ValueKey('hl-drawing-setting-width'),
          keyPrefix: 'hl-drawing-setting',
          label: l10n.chartLineWidth,
          param: const HlIndParam('width', kChartDrawingDefaultWidth,
              kChartDrawingMinWidth, kChartDrawingMaxWidth),
          value: drawing.width ?? kChartDrawingDefaultWidth,
          onChanged: (v) => _write(
              drawing.copyWith(
                  width: v == kChartDrawingDefaultWidth ? null : v.toInt()),
              'width'),
        ),
      if (offers.contains(ChartDrawingSetting.fill))
        HlStepperRow(
          key: const ValueKey('hl-drawing-setting-fill'),
          keyPrefix: 'hl-drawing-setting',
          label: l10n.chartFillOpacity,
          param: HlIndParam('fill', spec.fillPercent, 0, kChartDrawingMaxFill,
              step: 2),
          value: drawing.fill ?? spec.fillPercent,
          format: (v) => percent.format(v / 100),
          onChanged: (v) => _write(
              drawing.copyWith(fill: v == spec.fillPercent ? null : v.toInt()),
              'fill'),
        ),
      if (offers.contains(ChartDrawingSetting.textSize))
        HlStepperRow(
          key: const ValueKey('hl-drawing-setting-textSize'),
          keyPrefix: 'hl-drawing-setting',
          label: l10n.chartTextSize,
          param: const HlIndParam('textSize', kChartNoteDefaultTextSize,
              kChartNoteMinTextSize, kChartNoteMaxTextSize),
          value: drawing.textSize ?? kChartNoteDefaultTextSize,
          onChanged: (v) => _write(
              drawing.copyWith(
                  textSize:
                      v == kChartNoteDefaultTextSize ? null : v.toInt()),
              'text_size'),
        ),
      if (offers.contains(ChartDrawingSetting.labels))
        _SwitchRow(
          key: const ValueKey('hl-drawing-setting-labels'),
          label: l10n.chartDrawingLabels,
          value: drawing.labels,
          onChanged: (on) =>
              _write(drawing.copyWith(labels: on), 'labels'),
        ),
    ];
    final levels = offers.contains(ChartDrawingSetting.levels);

    return KuteBarContextScope(
      barContext: const KuteBarContext.hidden(),
      child: AppBottomSheetContainer(
        maxHeight: 0.9,
        child: Column(
          key: ValueKey('hl-drawing-settings-${drawing.tool.name}'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppBottomSheetHeader(
              title: l10n.chartIndSettingsTitle(widget.title),
              compact: true,
              // The app's one close (kute_back_button.dart).
              trailing: const AppBottomSheetCloseButton(
                  key: ValueKey('hl-drawing-settings-close')),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (rows.isNotEmpty) _Card(rows: rows),
                    if (levels) ...[
                      SizedBox(height: 16.h),
                      Padding(
                        padding: EdgeInsets.only(bottom: 8.h, left: 2.w),
                        child: Text(
                          l10n.chartFibLevels,
                          style: TextStyle(
                            color: c.textSecondary,
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      _Card(rows: [
                        for (final ratio in kChartFibLevelChoices)
                          _SwitchRow(
                            key: ValueKey('hl-drawing-setting-level-$ratio'),
                            label: hlFibLevelText(ratio),
                            value: drawing.fibLevels.contains(ratio),
                            onChanged: (on) {
                              final next = {
                                ...drawing.fibLevels,
                                if (on) ratio,
                              };
                              if (!on) next.remove(ratio);
                              final sorted = next.toList()..sort();
                              final isDefault =
                                  sorted.length == kChartFibDefaultLevels.length &&
                                      sorted.every(kChartFibDefaultLevels.contains);
                              _write(
                                  drawing.copyWith(
                                      levels: isDefault
                                          ? null
                                          : List<double>.unmodifiable(sorted)),
                                  'levels');
                            },
                          ),
                      ]),
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
                  key: const ValueKey('hl-drawing-settings-reset'),
                  onPressed: drawing.hasDefaultSettings
                      ? null
                      : () {
                          HapticFeedback.selectionClick();
                          _write(
                              drawing.copyWith(
                                width: null,
                                fill: null,
                                labels: true,
                                textSize: null,
                                levels: null,
                              ),
                              'reset');
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

/// The indicator sheet's card: rows under one another, hairlines between.
class _Card extends StatelessWidget {
  const _Card({required this.rows});
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
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
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Container(height: 0.5, color: c.border),
              ),
            rows[i],
          ],
        ],
      ),
    );
  }
}

/// A setting that is on or off: its name, then the settings toggle
/// (ctaFill track on, the hairline track off; never the accent).
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 10, 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w500,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Switch(
              value: value,
              onChanged: (on) {
                HapticFeedback.selectionClick();
                onChanged(on);
              },
              activeThumbColor: context.ctaOnColor,
              activeTrackColor: context.ctaFill,
              inactiveThumbColor: c.textSecondary,
              inactiveTrackColor: c.surfaceLight,
              trackOutlineColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? Colors.transparent
                    : c.borderSubtle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
