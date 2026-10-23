import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/theme/app_theme.dart';

/// Keeps amount entry pinned while a ticket is quiet. A message gives the
/// upper form that space back: the same input scrolls after the message,
/// so it stays editable without squeezing the explanation behind it.
/// The scroll position stays mounted; there is no automatic scroll jump.
///
/// It also makes the ticket fit a short screen, in this order, each step
/// only when the one before is not enough:
///  1. the pinned input (the amount keypad) gives up height: its keys
///     shrink towards a 44 pt tap target and its rows close up, by
///     exactly what the form needs, measured on this very layout;
///  2. under a [SlipFit] ([SlipDensity]), the gaps close up;
///  3. then the ticket goes compact: its figures close up and the
///     amount figure steps down;
///  4. then a notice says only its message, in two lines, and then in
///     one (a tap reads it all, in a bottom sheet);
///  5. and only then does the form scroll, with a soft fade at the edge
///     it continues past, never a hard cut through text.
/// A screen with the room keeps the ticket exactly as designed.
class SlipFormBody extends StatefulWidget {
  const SlipFormBody({
    super.key,
    required this.form,
    required this.input,
    required this.expandForMessage,
  });

  final Widget form;
  final Widget input;
  final bool expandForMessage;

  @override
  State<SlipFormBody> createState() => _SlipFormBodyState();
}

class _SlipFormBodyState extends State<SlipFormBody> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fit = SlipFit._stateOf(context);
    final expand = widget.expandForMessage;
    return _SlipFormLayout(
      controller: _scroll,
      onNeed: fit == null ? null : (need) => fit._report(need, pinned: !expand),
      children: [
        SingleChildScrollView(
          controller: _scroll,
          physics: const ClampingScrollPhysics(),
          primary: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [widget.form, if (expand) widget.input],
          ),
        ),
        if (!expand) widget.input,
      ],
    );
  }
}

/// How much room a [SlipFit] ticket has: as designed, or compact.
abstract final class SlipDensity {
  /// The ticket is short of room: its gaps and paddings close up. False
  /// outside a [SlipFit], so a shared widget elsewhere looks exactly as
  /// it did.
  static bool tight(BuildContext context) =>
      (_SlipFitScope.of(context)?.level ?? 0) >= _kTight;

  /// Still short of room once tight: tiles drop their small line and
  /// the amount figure steps down.
  static bool compact(BuildContext context) =>
      (_SlipFitScope.of(context)?.level ?? 0) >= _kCompact;

  /// How many lines a notice keeps once the ticket is still short of
  /// room after going compact: its message alone in two lines, then in
  /// one (a tap reads it all). Null: the whole notice.
  static int? noticeLines(BuildContext context) {
    final level = _SlipFitScope.of(context)?.level ?? 0;
    if (level >= _kFoldNotices) return 1;
    if (level >= _kShortNotices) return 2;
    return null;
  }

  /// How much height the keypad gives up while it scrolls with the form
  /// after a message (where it cannot measure the room it has): the
  /// deficit the ticket measured, or all it can on a compact ticket.
  /// Zero for a pinned keypad, which measures its own room.
  static double keypadGive(BuildContext context) =>
      _SlipFitScope.of(context)?.give ?? 0;

  /// Tells the ticket how much the keypad can give at most (its designed
  /// height less its smallest). Called on the keypad's layout.
  static void reportKeypadRange(BuildContext context, double range) =>
      SlipFit._stateOf(context)?._keypadRange = range;

  /// Whether the keypad sits in a [SlipFit] ticket, where it fits the
  /// height it is given rather than its fixed one.
  static bool adaptive(BuildContext context) =>
      _SlipFitScope.of(context) != null;
}

/// [gap] as designed, or half of it on a tight ticket.
double slipGap(BuildContext context, double gap) =>
    SlipDensity.tight(context) ? gap * 0.5 : gap;

/// A vertical gap in a slip's form: [height] as designed, half of it on a
/// tight ticket ([slipGap]).
class SlipGap extends StatelessWidget {
  const SlipGap(this.height, {super.key});

  final double height;

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: slipGap(context, height));
}

/// Opens what a slip keeps folded (a notice in full, its raw details,
/// the order's details) in a bottom sheet: [title] over [children]. A
/// slip never grows in place to show it.
Future<void> showSlipDetailSheet(
  BuildContext context, {
  required String title,
  required List<Widget> children,
}) {
  HapticFeedback.selectionClick();
  return showAppBottomSheet<void>(
    // The app's own colours, never the side tint of the slip it opens
    // from (a sheet takes its theme from where it is opened).
    context: Navigator.of(context, rootNavigator: true).context,
    builder: (_) => AppBottomSheetContainer(
      maxHeight: 0.8,
      child: Column(
        key: const ValueKey('slip-detail-sheet'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppBottomSheetHeader(title: title, compact: true),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 8.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: children,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// A slip notice on a ticket short of room, in at most [maxLines] lines
/// cut with an ellipsis: its [title] over the message in two, the message
/// alone in one; a chevron says there is more. Tapping it calls [onOpen],
/// which shows the whole notice in a bottom sheet
/// ([showSlipDetailSheet]). [title] (when the notice has one) is what a
/// screen reader hears first; the line itself keeps the message, which
/// says what happened and where the money is.
class SlipNoticeLine extends StatelessWidget {
  const SlipNoticeLine({
    super.key,
    required this.icon,
    required this.message,
    required this.decoration,
    required this.onOpen,
    this.title,
    this.maxLines = 1,
  });

  final int maxLines;
  final IconData icon;
  final String message;
  final String? title;
  final BoxDecoration decoration;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final title = this.title;
    final messageStyle = TextStyle(
      fontSize: 14.sp,
      fontWeight: FontWeight.w600,
      color: c.textPrimary,
    );
    // Two lines keep the title over the message; one line is the
    // message alone, which says what happened and where the money is.
    final withTitle = title != null && maxLines > 1;
    final text = withTitle
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: messageStyle.copyWith(fontWeight: FontWeight.w700)),
              Text(message,
                  maxLines: maxLines - 1,
                  overflow: TextOverflow.ellipsis,
                  style: messageStyle.copyWith(
                      fontWeight: FontWeight.w500, color: c.textSecondary)),
            ],
          )
        : Text(
            message,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: messageStyle,
          );
    return Semantics(
      button: true,
      label: withTitle ? null : title,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onOpen,
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 9.h),
          decoration: decoration,
          child: Row(
            crossAxisAlignment: maxLines > 1
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              Icon(icon, size: 18.sp, color: c.textPrimary),
              SizedBox(width: 8.w),
              Expanded(child: text),
              SizedBox(width: 4.w),
              Icon(Icons.chevron_right_rounded,
                  size: 18.sp, color: c.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

const _kKeypadTight = 1;
const _kTight = 2;
const _kCompact = 3;
const _kShortNotices = 4;
const _kFoldNotices = 5;

/// A ticket that fits its screen: wraps the whole sheet (header, form,
/// action) so everything in it can read [SlipDensity]. The [SlipFormBody]
/// inside measures, on each layout, how far the form is from fitting;
/// this steps the ticket compact when it does not fit with the keypad at
/// its smallest, and back as designed once it would fit again.
class SlipFit extends StatefulWidget {
  const SlipFit({super.key, required this.child});

  final Widget child;

  static _SlipFitState? _stateOf(BuildContext context) =>
      _SlipFitScope.of(context)?.state;

  @override
  State<SlipFit> createState() => _SlipFitState();
}

class _SlipFitState extends State<SlipFit> {
  int _level = 0;
  bool _pinned = true;
  double? _need;
  bool _scheduled = false;

  /// How far the keypad scrolled with the form (after a message) gives
  /// up its height on [_kKeypadTight]: the deficit it was asked to cover.
  double _give = 0;

  /// How much the keypad can give at most (its designed height less its
  /// smallest), as it last laid out.
  double _keypadRange = 0;

  /// What stepping into a level gained, measured once the ticket settles
  /// after the step (its sizes animate): the estimate for stepping back
  /// out of it.
  final _saving = <int, double>{};
  int? _steppedTo;
  double? _needBeforeStep;
  double? _lastNeed;

  /// A step back down that had to be undone at once is not tried again
  /// for the same content: the need it was tried at, per level.
  final _blocked = <int, double>{};
  ({int level, double need})? _down;
  int _sinceDown = 0;

  void _report(double need, {required bool pinned}) {
    _need = need;
    _pinned = pinned;
    if (_scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) => _evaluate());
  }

  void _step(int next, double need) {
    final down = _down;
    if (down != null && down.level == next && _sinceDown < 8) {
      _blocked[next] = down.need;
    }
    _down = null;
    _needBeforeStep = need;
    _steppedTo = next;
    setState(() => _level = next);
  }

  void _stepDown(double need, VoidCallback apply) {
    _down = (level: _level, need: need);
    _sinceDown = 0;
    setState(apply);
  }

  void _evaluate() {
    _scheduled = false;
    final need = _need;
    if (!mounted || need == null) return;
    // Sizes animate (a figure arriving, a line folding away): the ticket
    // acts on a need that has settled, read again on the next frame.
    final stable = _lastNeed != null && (need - _lastNeed!).abs() < 0.5;
    _lastNeed = need;
    _sinceDown++;
    if (!stable) {
      _scheduled = true;
      SchedulerBinding.instance
        ..addPostFrameCallback((_) => _evaluate())
        ..scheduleFrame();
      return;
    }
    if (_steppedTo == _level && _needBeforeStep != null) {
      _saving[_level] = _needBeforeStep! - need;
      _needBeforeStep = null;
      _steppedTo = null;
    }
    // A pinned keypad gives its room on the layout itself: a pinned
    // ticket has no keypad step.
    if (_pinned && _level == _kKeypadTight) {
      setState(() {
        _level = 0;
        _give = 0;
      });
      return;
    }
    if (_level == _kKeypadTight) {
      // The scrolled keypad gives exactly the deficit, up to its range;
      // once it is at its smallest, the ticket goes compact.
      if (need > 0.5) {
        if (_give < _keypadRange - 0.5) {
          setState(() => _give = math.min(_keypadRange, _give + need + 0.5));
        } else {
          _step(_kTight, need);
        }
      } else if (need < -2) {
        final give = _give + need + 1;
        setState(() {
          if (give <= 0) {
            _give = 0;
            _level = 0;
          } else {
            _give = give;
          }
        });
      }
      return;
    }
    if (need > 0.5 && _level < _kFoldNotices) {
      if (!_pinned && _level == 0) {
        _give = need + 0.5;
        _step(_kKeypadTight, need);
      } else {
        _step(_level < _kTight ? _kTight : _level + 1, need);
      }
      return;
    }
    if (_level > 0) {
      final saving = _saving[_level];
      final blocked = _blocked[_level];
      if (blocked != null && (need - blocked).abs() >= 3) {
        _blocked.remove(_level);
      }
      // Back as designed only once the step below would fit with room to
      // spare, so a ticket at the edge does not flicker between the two.
      if (saving != null &&
          need + saving < -2 &&
          !_blocked.containsKey(_level)) {
        _stepDown(need, () {
          if (_level == _kTight) {
            _level = _pinned ? 0 : _kKeypadTight;
            _give = _keypadRange;
          } else {
            _level -= 1;
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => _SlipFitScope(
        state: this,
        level: _level,
        pinned: _pinned,
        give: _pinned
            ? 0
            : _level >= _kTight
                ? double.infinity
                : _level == _kKeypadTight
                    ? _give
                    : 0,
        child: widget.child,
      );
}

class _SlipFitScope extends InheritedWidget {
  const _SlipFitScope({
    required this.state,
    required this.level,
    required this.pinned,
    required this.give,
    required super.child,
  });

  final _SlipFitState state;
  final int level;
  final bool pinned;
  final double give;

  static _SlipFitScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SlipFitScope>();

  @override
  bool updateShouldNotify(_SlipFitScope old) =>
      level != old.level || pinned != old.pinned || give != old.give;
}

/// The form's scroll view over the pinned input. Lays the input out at
/// its natural height when the form fits above it, else at just the
/// height the form leaves (never under its minimum), and reports how far
/// the form is from fitting with the input at its smallest.
class _SlipFormLayout extends MultiChildRenderObjectWidget {
  const _SlipFormLayout({
    required this.controller,
    required this.onNeed,
    required super.children,
  });

  final ScrollController controller;
  final ValueChanged<double>? onNeed;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSlipFormLayout(controller: controller, onNeed: onNeed);

  @override
  void updateRenderObject(
      BuildContext context, _RenderSlipFormLayout renderObject) {
    renderObject
      ..controller = controller
      ..onNeed = onNeed;
  }
}

class _SlipFormParentData extends ContainerBoxParentData<RenderBox> {}

/// The soft edge where the form continues past its viewport.
const double _kFade = 28;

class _RenderSlipFormLayout extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _SlipFormParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _SlipFormParentData> {
  _RenderSlipFormLayout({
    required ScrollController controller,
    this.onNeed,
  }) : _controller = controller;

  ValueChanged<double>? onNeed;

  ScrollController _controller;
  set controller(ScrollController value) {
    if (value == _controller) return;
    if (attached) _controller.removeListener(markNeedsPaint);
    _controller = value;
    if (attached) _controller.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  ScrollPosition? get _position {
    if (!_controller.hasClients) return null;
    final p = _controller.position;
    return p.hasContentDimensions && p.hasPixels ? p : null;
  }

  /// How far the form reaches past its viewport, read once the scroll
  /// view has laid out (its position is current by then).
  double get _overflow {
    final p = _position;
    if (p == null) return 0;
    return math.max(0, p.maxScrollExtent - p.minScrollExtent);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _controller.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _controller.removeListener(markNeedsPaint);
    _shaderLayer.layer = null;
    super.detach();
  }

  @override
  void dispose() {
    _shaderLayer.layer = null;
    super.dispose();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _SlipFormParentData) {
      child.parentData = _SlipFormParentData();
    }
  }

  RenderBox get _scroll => firstChild!;
  RenderBox? get _input => childCount > 1 ? lastChild : null;

  @override
  double computeMinIntrinsicHeight(double width) =>
      _input?.getMinIntrinsicHeight(width) ?? 0;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _scroll.getMaxIntrinsicHeight(width) +
      (_input?.getMaxIntrinsicHeight(width) ?? 0);

  @override
  double computeMinIntrinsicWidth(double height) => math.max(
      _scroll.getMinIntrinsicWidth(height),
      _input?.getMinIntrinsicWidth(height) ?? 0);

  @override
  double computeMaxIntrinsicWidth(double height) => math.max(
      _scroll.getMaxIntrinsicWidth(height),
      _input?.getMaxIntrinsicWidth(height) ?? 0);

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final maxHeight = constraints.maxHeight;
    final wide = BoxConstraints(minWidth: width, maxWidth: width);
    final input = _input;
    var inputHeight = 0.0;
    var inputMin = 0.0;
    if (input != null) {
      input.layout(wide, parentUsesSize: true);
      inputHeight = input.size.height;
      inputMin = maxHeight.isFinite
          ? math.min(inputHeight, input.getMinIntrinsicHeight(width))
          : inputHeight;
    }
    final scrollRoom = maxHeight.isFinite
        ? math.max(0.0, maxHeight - inputMin)
        : double.infinity;
    _scroll.layout(wide.copyWith(maxHeight: scrollRoom), parentUsesSize: true);
    final form = _scroll.size.height + _overflow;
    if (input != null && maxHeight.isFinite) {
      final target = (maxHeight - form).clamp(inputMin, inputHeight);
      if (target < inputHeight - 0.01) {
        input.layout(wide.copyWith(maxHeight: target), parentUsesSize: true);
      }
    }
    (_scroll.parentData! as _SlipFormParentData).offset = Offset.zero;
    if (input != null) {
      (input.parentData! as _SlipFormParentData).offset =
          Offset(0, _scroll.size.height);
    }
    size = constraints.constrain(
        Size(width, _scroll.size.height + (input?.size.height ?? 0)));
    if (maxHeight.isFinite) onNeed?.call(form + inputMin - maxHeight);
  }

  final _shaderLayer = LayerHandle<ShaderMaskLayer>();

  @override
  void paint(PaintingContext context, Offset offset) {
    final scroll = _scroll;
    final scrollOffset =
        offset + (scroll.parentData! as _SlipFormParentData).offset;
    final p = _position;
    final top = p != null && p.extentBefore > 0.5;
    final bottom = p != null && p.extentAfter > 0.5;
    if (!top && !bottom) {
      _shaderLayer.layer = null;
      context.paintChild(scroll, scrollOffset);
    } else {
      final rect = scrollOffset & scroll.size;
      final h = math.max(1.0, rect.height);
      final edge = math.min(_kFade, h / 3) / h;
      final layer = _shaderLayer.layer ??= ShaderMaskLayer();
      layer
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            top ? Colors.transparent : Colors.black,
            Colors.black,
            Colors.black,
            bottom ? Colors.transparent : Colors.black,
          ],
          stops: [0, edge * 0.6, 1 - edge, 1],
        ).createShader(Offset.zero & rect.size)
        ..maskRect = rect
        ..blendMode = BlendMode.dstIn;
      context.pushLayer(
          layer, (ctx, o) => ctx.paintChild(scroll, o), scrollOffset);
    }
    final input = _input;
    if (input != null) {
      context.paintChild(
          input, offset + (input.parentData! as _SlipFormParentData).offset);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
