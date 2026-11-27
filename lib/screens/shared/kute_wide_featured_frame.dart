// lib/screens/shared/kute_wide_featured_frame.dart
//
// THE WIDE WEB'S FEATURED CARD (founder, 27 November 2026: "on Investing
// and Predictions maybe have one big one"): one large card at the head of
// a market page's content column, stepping through a featured set. One
// frame for both pages so they read as the same component, each filling
// the slots with its own content:
//   * [KuteWideFeaturedFrame.header]: top-left (the picture or logo and the
//     title or name);
//   * [KuteWideFeaturedFrame.figures]: the big figures, at the foot of the
//     left side over the foot row;
//   * [KuteWideFeaturedFrame.foot]: the foot row's left, beside previous /
//     next;
//   * [KuteWideFeaturedFrame.chart]: the market's chart on the right, given
//     its height; dropped on a card under [kKuteWideFeaturedChartMinWidth].
// The whole card opens the market; previous / next step through the set.

import 'package:flutter/material.dart';

import 'package:kute/theme/app_theme.dart';

/// The featured card's height (logical px), on every page that has one.
const double kKuteWideFeaturedHeight = 300;

/// The least content width of a featured card that keeps its chart; a
/// narrower card keeps the left side only.
const double kKuteWideFeaturedChartMinWidth = 600;

/// The chart's height inside the card.
const double kKuteWideFeaturedChartHeight = kKuteWideFeaturedHeight - 48;

class KuteWideFeaturedFrame extends StatelessWidget {
  const KuteWideFeaturedFrame({
    super.key,
    required this.keyPrefix,
    required this.header,
    required this.figures,
    required this.foot,
    required this.count,
    required this.onStep,
    required this.onTap,
    this.onTapDown,
    this.chart,
  });

  /// The card's key and its controls' ('$keyPrefix-prev', '-next').
  final String keyPrefix;

  final Widget header;
  final List<Widget> figures;
  final Widget foot;

  /// How many markets the set holds: under two, no previous / next.
  final int count;

  /// Previous (-1) or next (+1).
  final ValueChanged<int> onStep;

  final VoidCallback onTap;
  final VoidCallback? onTapDown;

  /// The chart at the height given; null for none.
  final Widget Function(double height)? chart;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget arrow(IconData icon, int step, String key) => IconButton(
          key: ValueKey(key),
          onPressed: count < 2 ? null : () => onStep(step),
          icon: Icon(icon, color: c.textSecondary),
        );
    final chart = this.chart;
    return Container(
      key: ValueKey(keyPrefix),
      height: kKuteWideFeaturedHeight,
      decoration: AppDecorations.card(context),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onTapDown: onTapDown == null ? null : (_) => onTapDown!(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            // A narrow card (one grid column) keeps the left side only.
            child: LayoutBuilder(builder: (context, box) {
              final chartShown =
                  chart != null && box.maxWidth >= kKuteWideFeaturedChartMinWidth;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        header,
                        const Spacer(),
                        ...figures,
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(child: foot),
                            if (count > 1) ...[
                              arrow(Icons.chevron_left_rounded, -1,
                                  '$keyPrefix-prev'),
                              arrow(Icons.chevron_right_rounded, 1,
                                  '$keyPrefix-next'),
                            ] else
                              // The arrows' row height, kept.
                              const SizedBox(height: 48),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (chartShown) ...[
                    const SizedBox(width: 24),
                    Expanded(
                      flex: 6,
                      child: IgnorePointer(
                        child: chart(kKuteWideFeaturedChartHeight),
                      ),
                    ),
                  ],
                ],
              );
            }),
          ),
        ),
      ),
    );
  }
}
