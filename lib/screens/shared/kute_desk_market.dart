// lib/screens/shared/kute_desk_market.dart
//
// A MARKET PAGE ON A LAPTOP AT REST (founder, 25 November 2026, of the
// Investing market page's always-open ticket: "maybe on this one, on
// desktop, have a button like Long and Short, and move those data and the
// Advanced chart button to the right, to be more similar with the open
// bet. Then clicking Long or Short this side bar appears"; and "same
// thing for Polymarket"). EXPANDED only.
//
// The page is the position page's shape: the market (header, figure,
// chart, the rest under the fold) on the left, from the window's left
// gutter; on the right a COLUMN ([kuteDeskColumnWidth], the position
// page's right pane, kute_detail_panes.dart) at the window's right gutter
// ([kuteDeskGutter]): the page's primary buttons, what the person holds,
// the market's figures as stat squares and its cards. A click on a
// primary button opens the ticket as the SIDE PANEL (kute_side_panel.dart,
// [kuteSidePanelWidth], the window's right edge top to bottom), which
// slides in from the right and takes the column's place; the left side
// keeps the rest of the window and reflows. Closing it brings the column
// back. On the settle curve (kute_motion.dart), at once under Reduce
// Motion.
//
// At 1000 wide (the narrowest EXPANDED) the column is its least, 400,
// which with its gap and the right gutter is the panel's own 448: the
// chart keeps its width whether the panel is open or not.
//
// Shared with the Investing market page (lib/screens/hyperliquid); kept
// tiny so the two can be unified.

import 'dart:ui' show lerpDouble;

import 'package:flutter/gestures.dart'
    show GestureBinding, PointerScrollEvent;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:kute/platform/kute_wide_frames.dart';
import 'package:kute/screens/shared/kute_detail_panes.dart'
    show kuteDetailPaneWidth;
import 'package:kute/theme/kute_motion.dart';

/// The right column's width in a window [width] wide: the position page's
/// right pane for the content between the two gutters.
double kuteDeskColumnWidth(double width) =>
    kuteDetailPaneWidth(width - 2 * kuteDeskGutter);

/// The right column's primary buttons' height (the trade row's pills,
/// taller: the page's primary actions).
const double kuteDeskButtonHeight = 68;

// The hero chart's height is [kuteDeskChartHeight]
// (platform/kute_wide_frames.dart), shared with the Investing pages.

/// The market page's two sides on EXPANDED (see the file header): [left]
/// across the rest of the window, and at the right either [column] (at
/// rest) or [panel] (while [open]), the one sliding in over the other.
class KuteDeskMarket extends StatefulWidget {
  const KuteDeskMarket({
    super.key,
    required this.left,
    required this.column,
    required this.panel,
    required this.open,
    this.gap = kuteDeskGutter,
  });

  /// The room between [left]'s edge and the column (less where [left]
  /// keeps a gutter of its own).
  final double gap;

  final Widget left;
  final Widget column;
  final Widget panel;
  final bool open;

  @override
  State<KuteDeskMarket> createState() => _KuteDeskMarketState();
}

class _KuteDeskMarketState extends State<KuteDeskMarket> {
  /// The left side, whose scroll the wheel over the column turns.
  final GlobalKey _left = GlobalKey();

  Widget get left => KeyedSubtree(key: _left, child: widget.left);
  Widget get column => KuteWheelRelay(target: _left, child: widget.column);
  Widget get panel => widget.panel;
  bool get open => widget.open;
  double get gap => widget.gap;

  @override
  Widget build(BuildContext context) {
    final reduce = KuteMotion.reduce(context);
    return LayoutBuilder(builder: (context, constraints) {
      final colW = kuteDeskColumnWidth(constraints.maxWidth);
      final restW = colW + gap + kuteDeskGutter;
      return TweenAnimationBuilder<double>(
        tween: Tween<double>(end: open ? 1 : 0),
        duration: reduce ? Duration.zero : KuteMotion.settleDuration,
        curve: KuteMotion.settle,
        builder: (context, t, _) {
          final rightW = lerpDouble(restW, kuteSidePanelWidth, t)!;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: left),
              SizedBox(
                width: rightW,
                child: ClipRect(
                  child: Stack(
                    children: [
                      Positioned(
                        left: gap,
                        top: 0,
                        bottom: 0,
                        width: colW,
                        child: Offstage(
                          offstage: t >= 1,
                          child: IgnorePointer(
                            ignoring: open,
                            child: Opacity(
                              opacity: (1 - t).clamp(0.0, 1.0),
                              child: KeyedSubtree(
                                key: const ValueKey('kute-desk-column'),
                                child: kuteNarrowMedia(context,
                                    width: colW, child: column),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        bottom: 0,
                        width: kuteSidePanelWidth,
                        child: Offstage(
                          offstage: t <= 0 && !open,
                          child: FractionalTranslation(
                            translation: Offset(1 - t, 0),
                            child: panel,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      );
    });
  }
}

/// Reports [child]'s laid-out height to [onHeight] after the frame (the
/// column's top line follows the left side's header).
class KuteDeskMeasure extends SingleChildRenderObjectWidget {
  const KuteDeskMeasure(
      {super.key, required this.onHeight, required super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderKuteDeskMeasure(onHeight);

  @override
  void updateRenderObject(
          BuildContext context, RenderKuteDeskMeasure renderObject) =>
      renderObject.onHeight = onHeight;
}

class RenderKuteDeskMeasure extends RenderProxyBox {
  RenderKuteDeskMeasure(this.onHeight);

  ValueChanged<double> onHeight;
  double? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (_reported == height) return;
    _reported = height;
    SchedulerBinding.instance.addPostFrameCallback((_) => onHeight(height));
  }
}

/// A page's right pane under a side panel (kute_wide_frames.dart,
/// KuteSideFlow; founder, 25 November 2026, of a position's Sell and
/// Details: "these ones also be side bars"): while a side panel stands
/// over this page the pane fades away under it, so no card of it peeks
/// out at the panel's edge; the hero keeps its place. Back as the panel
/// closes. Anything else ([child] as it is) when no panel is up.
class KuteDeskUnderPanel extends StatelessWidget {
  const KuteDeskUnderPanel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduce = KuteMotion.reduce(context);
    return ValueListenableBuilder<int>(
      valueListenable: kuteDialogsOpen,
      builder: (context, open, child) {
        final covered = open > 0 &&
            KuteSideFlow.anyOpen &&
            !(ModalRoute.of(context)?.isCurrent ?? true);
        return IgnorePointer(
          ignoring: covered,
          child: AnimatedOpacity(
            opacity: covered ? 0 : 1,
            duration: reduce ? Duration.zero : KuteMotion.settleDuration,
            curve: KuteMotion.settle,
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// The wheel over a market page's right column scrolls the PAGE (founder,
/// 25 November 2026: "we should be able to scroll down on the right side
/// if the mouse is there", the wheel over the chart being the chart's
/// zoom). A vertical wheel or trackpad turn over [child] that nothing
/// inside it takes (a list in the column that can still move takes its
/// own) turns the first downward scroll under [target], the page's left
/// side; at that scroll's end it does nothing.
class KuteWheelRelay extends StatelessWidget {
  const KuteWheelRelay({super.key, required this.target, required this.child});

  /// A key over the subtree that holds the page's scroll.
  final GlobalKey target;
  final Widget child;

  static ScrollPosition? _positionUnder(BuildContext? context) {
    if (context == null) return null;
    ScrollPosition? found;
    void visit(Element e) {
      if (found != null) return;
      if (e is StatefulElement && e.state is ScrollableState) {
        final scrollable = e.state as ScrollableState;
        if (scrollable.axisDirection == AxisDirection.down) {
          found = scrollable.position;
          return;
        }
      }
      e.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
    return found;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: (event) {
        if (event is! PointerScrollEvent) return;
        final d = event.scrollDelta;
        if (d.dy == 0 || d.dx.abs() > d.dy.abs()) return;
        final position = _positionUnder(target.currentContext);
        if (position == null || !position.hasPixels) return;
        final to = (position.pixels + d.dy)
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble();
        if (to == position.pixels) return;
        // After the column's own lists: the first to ask wins.
        GestureBinding.instance.pointerSignalResolver
            .register(event, (_) => position.jumpTo(to));
      },
      child: child,
    );
  }
}
