// lib/platform/kute_layout.dart
//
// THE WIDE LAYOUTS' ONE RULER (founder, 24 November 2026: "make web
// responsive, for iPad and horizontal screens also … on larger screens
// show the graphs on the left with the interfaces on the right, it must
// be a different experience … with what we already have, we just have to
// move stuff around").
//
// Three form factors, by the window's width in logical pixels:
//
//   * COMPACT, under 600: a phone. Everything is exactly as it was: the
//     430 x 932 design scaled to the screen, one column, bottom sheets.
//   * MEDIUM, 600 to 899: a small tablet or a narrow window. Still one
//     column, but at the design's own size (no scaling up), centred at
//     [columnMaxWidth], with sheets as centred [sheetMaxWidth] forms.
//   * EXPANDED, 900 and up: an iPad in landscape, a laptop, a desktop.
//     Two panes: what you look at (the chart, the market, the lists) on
//     the left, what you do (the ticket, the slip, the balance and its
//     actions) in a [paneWidth] column on the right; the whole page
//     centred at [pageMaxWidth].
//
// SCALING: on a phone flutter_screenutil scales the 430-wide design to
// the screen's width. Past 600 that would blow every size up with the
// window (3.3x on a 1440 laptop), so from MEDIUM up the design size IS
// the window ([designSizeFor]): one design pixel is one logical pixel and
// `.w`, `.h`, `.sp` and `.r` stop growing.
//
// Read the form factor with [KuteLayout.of] (the window) or, inside a
// pane, lay out by the pane's own constraints (LayoutBuilder): a 430 pane
// on a desktop is a phone column and its widgets must not ask the window.

import 'package:flutter/widgets.dart';

/// The window's form factor (see the file header).
enum KuteFormFactor { compact, medium, expanded }

abstract final class KuteLayout {
  /// The phone design the app is drawn for.
  static const Size phoneDesign = Size(430, 932);

  /// MEDIUM starts here.
  static const double mediumMinWidth = 600;

  /// EXPANDED (two panes) starts here.
  static const double expandedMinWidth = 900;

  /// The action pane on EXPANDED (the ticket, the slip, the balance and
  /// its actions): the phone design's own width, so everything built for
  /// a phone column fits it untouched.
  static const double paneWidth = 430;

  /// A single column of content on MEDIUM, and a form flow (onboarding,
  /// PIN, send, receive, settings) on MEDIUM and EXPANDED.
  static const double columnMaxWidth = 560;

  /// A sheet on MEDIUM and EXPANDED.
  static const double sheetMaxWidth = 480;

  /// The two panes together on EXPANDED; wider windows keep the page
  /// centred with the app background at its sides.
  static const double pageMaxWidth = 1360;

  /// The gap between the two panes and the page's side gutter on EXPANDED.
  static const double paneGap = 24;

  static KuteFormFactor forWidth(double width) => width < mediumMinWidth
      ? KuteFormFactor.compact
      : width < expandedMinWidth
          ? KuteFormFactor.medium
          : KuteFormFactor.expanded;

  /// The window's form factor.
  static KuteFormFactor of(BuildContext context) =>
      forWidth(MediaQuery.sizeOf(context).width);

  /// A phone: everything as it was.
  static bool isCompact(BuildContext context) =>
      of(context) == KuteFormFactor.compact;

  /// MEDIUM or EXPANDED: sizes no longer scale with the window.
  static bool isWide(BuildContext context) => !isCompact(context);

  /// Two panes.
  static bool isExpanded(BuildContext context) =>
      of(context) == KuteFormFactor.expanded;

  /// The design size flutter_screenutil is given for a window of [window]:
  /// the phone design on a phone (it scales to the screen), the window
  /// itself from MEDIUM up (scale 1, see SCALING in the file header).
  static Size designSizeFor(Size window) =>
      window.width < mediumMinWidth || window.isEmpty ? phoneDesign : window;
}
