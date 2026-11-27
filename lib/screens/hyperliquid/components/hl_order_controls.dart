import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderProxyBox;
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/advanced_ticket.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/theme/app_theme.dart';

/// Shared opening/closing ticket controls, so Advanced uses one design.
class HlAdvancedSection extends StatelessWidget {
  const HlAdvancedSection(
      {super.key,
      required this.title,
      required this.children,
      this.collapsible = false,
      this.expanded = true,
      this.onToggle});
  final String title;
  final List<Widget> children;
  final bool collapsible, expanded;
  final VoidCallback? onToggle;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final header = Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 17.sp,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
        ),
        if (collapsible)
          Icon(
            expanded
                ? Icons.keyboard_arrow_up_rounded
                : Icons.keyboard_arrow_down_rounded,
            size: 22.sp,
            color: c.textSecondary,
          ),
      ],
    );
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, expanded ? 18.h : 16.h),
      decoration: BoxDecoration(
        color: c.surfaceLight,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: c.borderSubtle, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (collapsible)
            Semantics(
              button: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onToggle?.call();
                },
                child: header,
              ),
            )
          else
            header,
          if (expanded) ...[
            SizedBox(height: 4.h),
            ...children,
          ],
        ],
      ),
    );
  }
}

class HlSegmentTrack extends StatelessWidget {
  const HlSegmentTrack({super.key, required this.segments});
  final List<Widget> segments;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: EdgeInsets.all(3.w),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: c.border, width: 0.5),
      ),
      child: Row(children: segments),
    );
  }
}

class HlTrackSegment extends StatelessWidget {
  const HlTrackSegment(
      {super.key,
      required this.label,
      required this.selected,
      required this.onTap,
      this.chevron = false});
  final String label;
  final bool selected, chevron;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 40.h,
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(horizontal: 6.w),
          decoration: BoxDecoration(
            color: selected ? c.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(9.r),
            border: selected ? Border.all(color: c.border) : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: selected ? c.textPrimary : c.textTertiary,
                    ),
                  ),
                ),
              ),
              if (chevron) ...[
                SizedBox(width: 2.w),
                Icon(
                  Icons.expand_more_rounded,
                  size: 16.sp,
                  color: selected ? c.textPrimary : c.textTertiary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Future<T?> showHlOrderTypePicker<T>(
  BuildContext context, {
  required List<(T, String)> items,
  required T? selected,
}) {
  HapticFeedback.selectionClick();
  return showAppBottomSheet<T>(
      context: context,
      builder: (sheetContext) {
        final c = sheetContext.colors;
        return AppBottomSheetContainer(
            child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
                padding: EdgeInsets.only(top: 12.h),
                child: Center(child: AppDecorations.dragHandle(sheetContext))),
            Padding(
                padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 8.h),
                child: Text(sheetContext.l10n.investingOrderType,
                    style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 20.sp,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4))),
            for (final item in items)
              Semantics(
                button: true,
                selected: selected == item.$1,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(sheetContext).pop(item.$1),
                  child: Container(
                    constraints: BoxConstraints(minHeight: 56.h),
                    margin: EdgeInsets.fromLTRB(20.w, 0, 20.w, 8.h),
                    padding:
                        EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                    decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(16.r),
                        border: Border.all(
                            color:
                                selected == item.$1 ? c.border : c.borderSubtle,
                            width: selected == item.$1 ? 1 : 0.5)),
                    child: Row(children: [
                      Expanded(
                          child: Text(item.$2,
                              style: TextStyle(
                                  color: c.textPrimary,
                                  fontSize: 17.sp,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.2))),
                      if (selected == item.$1)
                        Icon(Icons.check_rounded,
                            size: 20.sp, color: c.textPrimary),
                    ]),
                  ),
                ),
              ),
            SizedBox(height: 12.h),
          ],
        ));
      });
}

// ── The Advanced pages' steppers ─────────────────────────────────────────

/// The venue's price step at [px] (the rule [roundPrice] sends by): five
/// significant figures under the market's decimal cap (6, or 8 on spot,
/// less the size decimals), whole dollars from 100,000.
double hlPriceTick(double px, {required int szDecimals, required bool isSpot}) {
  if (!(px > 0)) return 1;
  if (px >= 1e5) return 1;
  final maxDecimals = math.max(0, (isSpot ? 8 : 6) - szDecimals);
  final magnitude = (math.log(px) / math.ln10 + 1e-9).floor();
  return math.max(math.pow(10, magnitude - 4).toDouble(),
      math.pow(10, -maxDecimals).toDouble());
}

/// One number on an Advanced page as a stepper ([AdvancedStepper]): the
/// value big with round − / + at its ends; a tap on the value types it in
/// its own field ([controller], [focusNode], [inputFormatters]), unseen
/// under the stepper, so the keyboard and every check on the field stay
/// the field's. [onStep] moves it; [trailing] is the snap to the market.
/// A price ([formatPrice]) reads formatted while it is not being typed.
class HlStepField extends StatefulWidget {
  const HlStepField({
    super.key,
    required this.controller,
    required this.label,
    required this.onStep,
    required this.onChanged,
    this.focusNode,
    this.fieldKey,
    this.prefix = '',
    this.suffix = '',
    this.formatPrice,
    this.inputFormatters,
    this.decimal = true,
    this.trailing,
    this.onTrailing,
    this.readOnly = false,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<int> onStep;
  final ValueChanged<String> onChanged;
  final FocusNode? focusNode;
  final Key? fieldKey;
  final String prefix;
  final String suffix;
  final String Function(double value)? formatPrice;
  final List<TextInputFormatter>? inputFormatters;
  final bool decimal;
  final String? trailing;
  final VoidCallback? onTrailing;
  final bool readOnly;

  @override
  State<HlStepField> createState() => _HlStepFieldState();
}

class _HlStepFieldState extends State<HlStepField> {
  FocusNode? _own;
  FocusNode get _node => widget.focusNode ?? (_own ??= FocusNode());

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final node = _node;
    return ListenableBuilder(
      listenable: Listenable.merge([node, widget.controller]),
      builder: (context, _) {
        final c = context.colors;
        final text = widget.controller.text.trim();
        final parsed = double.tryParse(text.replaceAll(',', '.'));
        final String value;
        if (text.isEmpty) {
          value = '—';
        } else if (widget.formatPrice != null &&
            !node.hasFocus &&
            parsed != null &&
            parsed > 0) {
          value = widget.formatPrice!(parsed);
        } else {
          value = '${widget.prefix}$text${widget.suffix}';
        }
        return Stack(
          children: [
            // The real input, unseen: it holds the focus and the keyboard.
            Positioned(
              left: 0,
              top: 0,
              child: Opacity(
                opacity: 0,
                child: SizedBox(
                  width: 1,
                  height: 1,
                  child: TextField(
                    key: widget.fieldKey,
                    controller: widget.controller,
                    focusNode: node,
                    readOnly: widget.readOnly,
                    keyboardType: TextInputType.numberWithOptions(
                        decimal: widget.decimal),
                    inputFormatters: widget.inputFormatters,
                    showCursor: false,
                    enableInteractiveSelection: false,
                    onChanged: widget.onChanged,
                    decoration: const InputDecoration.collapsed(hintText: ''),
                  ),
                ),
              ),
            ),
            Semantics(
              label: widget.label,
              value: text,
              child: AdvancedStepper(
                label: widget.label,
                value: value,
                enabled: !widget.readOnly,
                onStep: (dir) {
                  node.unfocus();
                  widget.onStep(dir);
                },
                onValueTap: node.requestFocus,
                trailing: widget.trailing,
                onTrailing: widget.onTrailing,
              ),
            ),
            // Typing: a neutral rim (never the side's or the accent's colour).
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(
                      color:
                          node.hasFocus ? c.textTertiary : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A plain switch row (the whole row toggles), drawn as Settings draws its
/// switches (the CTA fill when on, never the accent); [card] gives it the
/// page's card.
class HlSwitchRow extends StatelessWidget {
  const HlSwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.card = false,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool card;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final row = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onChanged(!value);
      },
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 2.h),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox(width: 8.w),
            Switch(
              value: value,
              onChanged: (v) {
                HapticFeedback.selectionClick();
                onChanged(v);
              },
              thumbColor: WidgetStateProperty.resolveWith((states) =>
                  states.contains(WidgetState.selected)
                      ? context.ctaOnColor
                      : c.textSecondary),
              trackColor: WidgetStateProperty.resolveWith((states) =>
                  states.contains(WidgetState.selected)
                      ? context.ctaFill
                      : c.surfaceLight),
              trackOutlineColor: WidgetStateProperty.resolveWith((states) =>
                  states.contains(WidgetState.selected)
                      ? Colors.transparent
                      : c.borderSubtle),
            ),
          ],
        ),
      ),
    );
    if (!card) return row;
    return Container(
      padding: EdgeInsets.fromLTRB(14.w, 6.h, 10.w, 6.h),
      decoration: AppDecorations.card(context),
      child: row,
    );
  }
}

/// The Advanced pages' switches as Settings draws them, for the shared
/// rows under [child] ([AdvancedToggleRow]'s own switch).
Widget hlAdvancedSwitchTheme(BuildContext context, {required Widget child}) {
  final c = context.colors;
  return Theme(
    data: Theme.of(context).copyWith(
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? context.ctaOnColor
                : c.textSecondary),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? context.ctaFill
                : c.surfaceLight),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? Colors.transparent
                : c.borderSubtle),
      ),
    ),
    child: child,
  );
}

/// Reports its child's laid-out size after the frame (an Advanced page's
/// floating primary, whose notes come and go, for the room the form
/// leaves under its last card).
class HlReportSize extends SingleChildRenderObjectWidget {
  const HlReportSize({super.key, required this.onSize, super.child});
  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderReportSize(onSize);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderReportSize).onSize = onSize;
  }
}

class _RenderReportSize extends RenderProxyBox {
  _RenderReportSize(this.onSize);
  ValueChanged<Size> onSize;
  Size? _last;

  @override
  void performLayout() {
    super.performLayout();
    final now = size;
    if (now == _last) return;
    _last = now;
    WidgetsBinding.instance.addPostFrameCallback((_) => onSize(now));
  }
}
