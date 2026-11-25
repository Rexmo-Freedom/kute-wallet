// lib/screens/hyperliquid/components/hl_drawing_rail.dart
//
// The Advanced chart's tool rail as groups. Each group is one button
// that shows its face: the tool last picked from it (stored globally,
// hlDrawingRailFacesProvider), else its first. A tap takes that tool; a
// second tap on it, a long press, a tap on the corner mark or a right
// click opens the group's fly-out, which lists its tools by glyph and
// name. Picking one takes it in hand, makes it the face and closes the
// fly-out. A group of one tool is a plain button, as the rail always
// had.
//
// The fly-out is a compact sheet in the app's sheet style on an upright
// phone, and a small panel beside the button where the window has room
// for it (a phone on its side, a tablet, a desktop browser), in the style
// of the rail's "…" menu.
//
// To put a tool on the rail: add it to its group's list in
// [kHlToolGroups], its name in [hlToolName], its glyph in
// hl_drawing_tools.dart. See "How to add a drawing tool" at the top of
// models/chart_drawing.dart for the rest.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/chart_drawing.dart';
import 'package:kute/screens/hyperliquid/components/hl_drawing_tools.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/theme/app_theme.dart';

/// The rail's groups, top to bottom.
enum HlToolGroupId { cursor, lines, channels, fibonacci, positions, shapes, notes }

/// One group: its tools in fly-out order, and the face it shows until
/// another is picked ([face], else the first: the everyday tool). The
/// cursor group's one "tool" is null.
class HlToolGroup {
  const HlToolGroup(this.id, this.tools, {this.face});
  final HlToolGroupId id;
  final List<ChartDrawingTool?> tools;
  final ChartDrawingTool? face;

  /// One tool: a plain button, no fly-out.
  bool get single => tools.length == 1;
}

/// The groups and their tools. A group with no tools is not shown.
const List<HlToolGroup> kHlToolGroups = [
  HlToolGroup(HlToolGroupId.cursor, [null]),
  HlToolGroup(HlToolGroupId.lines, [
    ChartDrawingTool.trendline,
    ChartDrawingTool.ray,
    ChartDrawingTool.extendedLine,
    ChartDrawingTool.level,
    ChartDrawingTool.horizontalRay,
    ChartDrawingTool.verticalLine,
    ChartDrawingTool.priceLine,
  ]),
  HlToolGroup(HlToolGroupId.channels, [ChartDrawingTool.parallelChannel]),
  HlToolGroup(HlToolGroupId.fibonacci, [ChartDrawingTool.fibonacci]),
  // Drawings only: no order is placed from them, and never leverage.
  HlToolGroup(
    HlToolGroupId.positions,
    [
      ChartDrawingTool.longPosition,
      ChartDrawingTool.shortPosition,
      ChartDrawingTool.priceRange,
      ChartDrawingTool.dateRange,
      ChartDrawingTool.dateAndPriceRange,
    ],
    face: ChartDrawingTool.dateAndPriceRange,
  ),
  HlToolGroup(HlToolGroupId.shapes, [ChartDrawingTool.rect]),
  HlToolGroup(HlToolGroupId.notes, [ChartDrawingTool.text]),
];

/// The group [tool] sits in, or null for a tool off the rail.
HlToolGroup? hlGroupOf(ChartDrawingTool? tool) {
  for (final g in kHlToolGroups) {
    if (g.tools.contains(tool)) return g;
  }
  return null;
}

/// A group's name (the fly-out's title, a screen reader's label).
String hlToolGroupName(AppLocalizations l10n, HlToolGroupId id) =>
    switch (id) {
      HlToolGroupId.cursor => l10n.chartToolCursor,
      HlToolGroupId.lines => l10n.chartToolGroupLines,
      HlToolGroupId.channels => l10n.chartToolGroupChannels,
      HlToolGroupId.fibonacci => l10n.chartToolGroupFibonacci,
      HlToolGroupId.positions => l10n.chartToolGroupPositionsMeasure,
      HlToolGroupId.shapes => l10n.chartToolGroupShapes,
      HlToolGroupId.notes => l10n.chartToolGroupNotes,
    };

/// A tool's name, as the rail, the fly-out and the hint say it.
String hlToolName(AppLocalizations l10n, ChartDrawingTool? tool) =>
    switch (tool) {
      null => l10n.chartToolCursor,
      ChartDrawingTool.trendline => l10n.chartToolTrendLine,
      ChartDrawingTool.level => l10n.chartToolHorizontalLine,
      ChartDrawingTool.priceLine => l10n.chartToolPriceLine,
      ChartDrawingTool.ray => l10n.chartToolRay,
      ChartDrawingTool.extendedLine => l10n.chartToolExtendedLine,
      ChartDrawingTool.horizontalRay => l10n.chartToolHorizontalRay,
      ChartDrawingTool.verticalLine => l10n.chartToolVerticalLine,
      ChartDrawingTool.parallelChannel => l10n.chartToolParallelChannel,
      ChartDrawingTool.fibonacci => l10n.chartToolFibonacci,
      ChartDrawingTool.longPosition => l10n.chartToolLongPosition,
      ChartDrawingTool.shortPosition => l10n.chartToolShortPosition,
      ChartDrawingTool.priceRange => l10n.chartToolPriceRange,
      ChartDrawingTool.dateRange => l10n.chartToolDateRange,
      ChartDrawingTool.dateAndPriceRange => l10n.chartToolGroupMeasure,
      ChartDrawingTool.rect => l10n.chartToolRectangle,
      ChartDrawingTool.text => l10n.chartToolText,
    };

/// The tool a group's button shows and takes: the one last picked from
/// its fly-out ([faces], by group id and tool name), else its first.
ChartDrawingTool? hlGroupFace(HlToolGroup group, Map<String, String> faces) {
  final picked = faces[group.id.name];
  for (final t in group.tools) {
    if (t != null && t.name == picked) return t;
  }
  return group.face ?? (group.tools.isEmpty ? null : group.tools.first);
}

/// Whether the fly-out opens as a panel beside the rail (a window with
/// room beside it: a tablet, a browser, a phone on its side, where a sheet
/// would cover the short plot) rather than as a sheet (a phone upright).
bool hlFlyoutAsPanel(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= 600;

/// Opens [group]'s fly-out from its button ([anchor]) and returns the
/// tool picked, or null when it was closed without one. [armed] is the
/// tool in hand (marked).
Future<ChartDrawingTool?> showHlToolFlyout(
  BuildContext context, {
  required BuildContext anchor,
  required HlToolGroup group,
  required ChartDrawingTool? armed,
}) async {
  final tools = [for (final t in group.tools) if (t != null) t];
  if (hlFlyoutAsPanel(context)) {
    return _showPanel(context, anchor: anchor, group: group, tools: tools,
        armed: armed);
  }
  return showAppBottomSheet<ChartDrawingTool>(
    context: context,
    builder: (_) => HlToolFlyoutSheet(group: group, armed: armed),
  );
}

/// The panel beside the rail: the "…" menu's look, one row per tool.
Future<ChartDrawingTool?> _showPanel(
  BuildContext context, {
  required BuildContext anchor,
  required HlToolGroup group,
  required List<ChartDrawingTool> tools,
  required ChartDrawingTool? armed,
}) async {
  final box = anchor.findRenderObject() as RenderBox?;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (box == null || overlay == null) return null;
  final c = context.colors;
  final l10n = context.l10n;
  final origin =
      box.localToGlobal(Offset(box.size.width + 6, 0), ancestor: overlay);
  return showMenu<ChartDrawingTool>(
    context: context,
    position: RelativeRect.fromRect(origin & Size.zero, Offset.zero & overlay.size),
    color: context.isDark ? c.surfaceElevated : Colors.white,
    elevation: 6,
    // Room for a name on one line ("Horizontal ray"), never the screen.
    constraints: BoxConstraints(
        minWidth: 200, maxWidth: math.min(360, overlay.size.width - 24)),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14.r),
      side: BorderSide(color: c.borderSubtle, width: 0.5),
    ),
    items: [
      for (final tool in tools)
        PopupMenuItem<ChartDrawingTool>(
          key: ValueKey('hl-tool-flyout-${tool.name}'),
          value: tool,
          height: 46,
          // The pointer over a row, as over the rail's buttons.
          mouseCursor: SystemMouseCursors.click,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              HlGlyph(hlGlyphForTool(tool),
                  size: 20.sp,
                  color: tool == armed ? c.textPrimary : c.textSecondary),
              SizedBox(width: 12.w),
              Flexible(
                child: Text(
                  hlToolName(l10n, tool),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              SizedBox(width: 16.w),
              SizedBox(
                width: 18,
                child: tool == armed
                    ? Icon(Icons.check_rounded,
                        size: 18.sp, color: c.textPrimary)
                    : null,
              ),
            ],
          ),
        ),
    ],
  );
}

/// The fly-out on a phone: a compact sheet with the group's name and one
/// row per tool (its glyph and name), the tool in hand marked. A row
/// closes the sheet with its tool.
class HlToolFlyoutSheet extends StatelessWidget {
  const HlToolFlyoutSheet({super.key, required this.group, this.armed});

  final HlToolGroup group;
  final ChartDrawingTool? armed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = context.colors;
    final tools = [for (final t in group.tools) if (t != null) t];
    // A picker: the floating bar is away while it is up.
    return KuteBarContextScope(
      barContext: const KuteBarContext.hidden(),
      child: AppBottomSheetContainer(
        maxHeight: 0.9,
        child: Column(
          key: ValueKey('hl-tool-flyout-${group.id.name}'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppBottomSheetHeader(
              title: hlToolGroupName(l10n, group.id),
              compact: true,
              // The app's one close (kute_back_button.dart).
              trailing: const AppBottomSheetCloseButton(
                  key: ValueKey('hl-tool-flyout-close')),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(bottom: 8.h),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final tool in tools)
                      AppBottomSheetListTile(
                        key: ValueKey('hl-tool-flyout-${tool.name}'),
                        title: hlToolName(l10n, tool),
                        isSelected: tool == armed,
                        leading: SizedBox(
                          width: 24,
                          height: 24,
                          child: Center(
                            child: HlGlyph(
                              hlGlyphForTool(tool),
                              color: tool == armed
                                  ? context.ctaOnColor
                                  : c.textSecondary,
                            ),
                          ),
                        ),
                        onTap: () => Navigator.of(context).pop(tool),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
