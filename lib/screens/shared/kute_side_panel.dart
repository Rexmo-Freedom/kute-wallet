// lib/screens/shared/kute_side_panel.dart
//
// THE MARKET DESK on EXPANDED (founder, 25 November 2026, the market page
// at laptop size: "not occupying full screen for some reason", "the card
// on the right should be a clear screen part on the right, not this
// small"; and on the editor: "there is much more space to make the
// advanced graph on desktop much better").
//
// A market page (Investing, Predictions market / event / game / timed
// round) and the Advanced chart editor are two parts of the window:
//
//   * the LEFT side, the market, from the window's left edge to the
//     panel, uncapped: the chart takes the width (and, on a tall window,
//     the height);
//   * the SIDE PANEL, [kuteSidePanelWidth] wide, attached to the window's
//     right edge from its top to its bottom: the order ticket or the bet
//     slip open in place, whose side colour (green Long / red Short, the
//     outcome's colour) IS the panel's surface ([kuteSidePanelDecoration]).
//
// The ticket keeps its phone layout inside the panel. What the person
// holds on the market (a position's row) sits in the panel too, on its
// surface, right over the primary button ([SlipPanelFooter]): the slip
// draws it there, under its own tinted palette, so the row reads on the
// side colour as everything else on the slip does.
//
// Phones and MEDIUM never build any of this.

import 'package:flutter/widgets.dart';
import 'package:kute/platform/kute_wide_frames.dart';

/// The corner where the panel meets the page (its left corners); the
/// window's edges keep it square.
const double kuteSidePanelRadius = 28;

/// The panel's surface: [color] (the ticket's side colour), rounded only
/// where it meets the page.
BoxDecoration kuteSidePanelDecoration(Color color) => BoxDecoration(
      color: color,
      borderRadius: const BorderRadius.horizontal(
          left: Radius.circular(kuteSidePanelRadius)),
    );

/// Room between the panel's edges and the ticket's own gutters, so its
/// phone-width content sits with comfortable margins.
const EdgeInsets kuteSidePanelInsets = EdgeInsets.fromLTRB(8, 20, 8, 16);

/// The two parts of a market page on EXPANDED (see the file header):
/// [left] from the window's left edge, [panel] at its right edge, full
/// height.
Widget kuteDeskPanes({required Widget left, required Widget panel}) => Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: left),
        SizedBox(width: kuteSidePanelWidth, child: panel),
      ],
    );

/// What a ticket open in the side panel draws over its primary button:
/// the person's position on this market (see the file header). Null
/// outside a panel, or with nothing held.
class SlipPanelFooter extends InheritedWidget {
  const SlipPanelFooter({super.key, this.footer, required super.child});

  final Widget? footer;

  static Widget? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SlipPanelFooter>()?.footer;

  @override
  bool updateShouldNotify(SlipPanelFooter old) => old.footer != footer;
}

/// [SlipPanelFooter.of] laid out over the slip's button: at the ticket's
/// gutter, a little air above the button, never more than [maxHeight]
/// (it scrolls past that).
class SlipPanelFooterSlot extends StatelessWidget {
  const SlipPanelFooterSlot(
      {super.key, required this.horizontal, this.maxHeight = 220});

  final double horizontal;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final footer = SlipPanelFooter.of(context);
    if (footer == null) return const SizedBox.shrink();
    return Padding(
      key: const ValueKey('slip-panel-footer'),
      padding: EdgeInsets.fromLTRB(horizontal, 10, horizontal, 4),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(primary: false, child: footer),
      ),
    );
  }
}

/// The keys a ticket in the side panel shares with the Advanced chart
/// editor beside it: while the editor has a drawing selected, Backspace
/// is the editor's (it removes the drawing), not the amount's.
abstract final class KuteDeskKeys {
  static bool editorHoldsSelection = false;
}
