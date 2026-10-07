import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/l10n/l10n.dart';
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

/// The same input surface and focus treatment for opening and closing.
class HlNumericField extends StatefulWidget {
  const HlNumericField(
      {super.key,
      required this.controller,
      required this.label,
      required this.onChanged,
      this.focusNode,
      this.prefix,
      this.hint = '0',
      this.valueFontSize,
      this.footer = const [],
      this.inputFormatters,
      this.decimal = true,
      this.readOnly = false});
  final TextEditingController controller;
  final String label, hint;
  final String? prefix;
  final FocusNode? focusNode;
  final double? valueFontSize;
  final List<Widget> footer;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String> onChanged;
  final bool decimal;
  final bool readOnly;
  @override
  State<HlNumericField> createState() => _HlNumericFieldState();
}

class _HlNumericFieldState extends State<HlNumericField> {
  final _ownFocus = FocusNode();
  @override
  void dispose() {
    _ownFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.focusNode ?? _ownFocus;
    return ListenableBuilder(
        listenable: node,
        builder: (context, _) {
          final c = context.colors;
          final focused = node.hasFocus;
          final controller = widget.controller;
          final text = controller.text;
          final label = widget.label;
          final prefix = widget.prefix;
          final hint = widget.hint;
          final footer = widget.footer;
          final fontSize = widget.valueFontSize ?? 16.sp;
          return Semantics(
            label: label,
            value: text,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => node.requestFocus(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w600,
                      color: focused ? c.textPrimary : c.textTertiary,
                    ),
                  ),
                  SizedBox(height: 6.h),
                  Container(
                    constraints: BoxConstraints(minHeight: 56.h),
                    decoration: BoxDecoration(
                      // Inputs sit on a section card of the quiet veil, so they
                      // take the step above it to read as fields you can edit.
                      color: c.surface,
                      // 16, the radius every other card on an Advanced page
                      // wears. At 12 these fields read as a different family
                      // sitting inside the same frame.
                      borderRadius: BorderRadius.circular(16.r),
                      border: Border.all(
                        // Focus in the accent, the app's own focus ink. A rim
                        // in the primary text colour is a black bar in light
                        // mode and a white one in dark, which shouts.
                        color: focused ? c.accent : c.border,
                        width: focused ? 1.5 : 0.5,
                      ),
                    ),
                    padding: EdgeInsets.symmetric(horizontal: 14.w),
                    child: Row(
                      children: [
                        if (prefix != null) ...[
                          Text(
                            prefix,
                            style: TextStyle(
                              fontSize: fontSize,
                              fontWeight: FontWeight.w700,
                              color: c.textSecondary,
                            ),
                          ),
                          SizedBox(width: 4.w),
                        ],
                        Expanded(
                          child: TextField(
                            controller: controller,
                            readOnly: widget.readOnly,
                            focusNode: node,
                            keyboardType: TextInputType.numberWithOptions(
                              decimal: widget.decimal,
                            ),
                            inputFormatters: widget.inputFormatters,
                            cursorColor: c.textPrimary,
                            maxLines: 1,
                            onChanged: widget.onChanged,
                            style: TextStyle(
                              fontSize: fontSize,
                              fontWeight: FontWeight.w700,
                              color: c.textPrimary,
                            ),
                            decoration: InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding:
                                  EdgeInsets.symmetric(vertical: 14.h),
                              hintText: hint,
                              hintStyle: TextStyle(
                                fontSize: fontSize,
                                fontWeight: FontWeight.w700,
                                color: c.textTertiary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...footer,
                ],
              ),
            ),
          );
        });
  }
}
