// lib/screens/shared/kute_detail_panes.dart
//
// A DETAIL PAGE ON A WIDE WINDOW (round three; founder, 25 November 2026:
// "lots of screens are vertical only. It must be all occupying full
// screen when we can"). A position (Predictions, Investing) or a combo is
// a phone column of what to look at (the dial, the chart, the summary)
// over what to read and do (the tiles, the option cards, the legs). On
// EXPANDED those become two panes inside the page's one scroll
// ([kuteWidePadding] around it): the look-at part on the left across the
// rest of the page, the rows and cards on the right at a readable width
// ([kuteDetailPaneWidth], about a phone's), the floating bar's primary
// (Sell, Close position, Close combo) centred under that right pane
// ([KuteBarPane]). The same widgets, moved; nothing new. Off EXPANDED the
// page stacks them as before ([KuteDetailPanes] is only built there).

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:kute/platform/kute_wide_frames.dart';

/// The right pane's width for a page's content of [width]: about 42% of
/// it, between 400 and 480 (a rows card stays readable, the left pane
/// keeps the larger share).
double kuteDetailPaneWidth(double width) =>
    ((width - kuteWideGap) * 0.42).clamp(400.0, 480.0).toDouble();

/// [hero] on the left, [details] on the right (see the file header), top
/// aligned. [heroMaxWidth]: the hero centred at that width in its pane (a
/// dial that would grow with the pane); null, the pane's whole width (a
/// chart).
class KuteDetailPanes extends StatelessWidget {
  const KuteDetailPanes({
    super.key,
    required this.hero,
    required this.details,
    this.heroMaxWidth,
  });

  final Widget hero;
  final Widget details;
  final double? heroMaxWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final right = kuteDetailPaneWidth(width);
      final left = math.max(0.0, width - right - kuteWideGap);
      final max = heroMaxWidth;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: left,
            child: max == null || max >= left
                ? hero
                : Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(width: max, child: hero),
                  ),
          ),
          const SizedBox(width: kuteWideGap),
          SizedBox(
            width: right,
            // The right pane reads as the phone column it was.
            child: KuteBarPane(
              child: kuteNarrowMedia(context, width: right, child: details),
            ),
          ),
        ],
      );
    });
  }
}
