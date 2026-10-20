import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/screens/shared/slip_form_body.dart' show SlipDensity;
import 'package:kute/theme/app_theme.dart';

class CustomKeypad extends StatelessWidget {
  final ValueSetter<String> onDigitPressed;
  final VoidCallback onBackspacePressed;
  final VoidCallback? onBiometricPressed;

  /// Renders a decimal key ('.') in the bottom-left slot, for amount
  /// entry keypads. Off by default so PIN callers are untouched; when
  /// on it takes the slot the biometric key would otherwise occupy
  /// (amount entry has no biometric affordance).
  final bool showDecimal;

  /// Fired when the decimal key is tapped. Only used when
  /// [showDecimal] is true.
  final VoidCallback? onDecimalPressed;

  /// Shorter keys and tighter rows for amount sheets, where the pad
  /// shares the screen with a hero figure and an action. PIN screens
  /// own the whole screen and keep the full size.
  final bool compact;

  /// Draws the digit keys in the app's own chip chrome: the 12r action
  /// radius, a hairline border and, in light mode, the soft lift every
  /// other neutral control has. Off by default so the surfaces inside
  /// the wallet keep exactly what they have today.
  ///
  /// Without it the pad is the only surface-filled control in the app
  /// with no border and a 24r corner, when nothing else is 24.
  final bool chromed;

  const CustomKeypad({
    super.key,
    required this.onDigitPressed,
    required this.onBackspacePressed,
    this.onBiometricPressed,
    this.showDecimal = false,
    this.onDecimalPressed,
    this.compact = false,
    this.chromed = false,
  });

  double get _keyHeight => compact ? 56.h : 72.h;
  double get _rowGap => compact ? 8.h : 12.h;
  double get _digitSize => compact ? 26.sp : 30.sp;

  /// The smallest a key gets on a ticket short of room: a 44 pt tap
  /// target (or the designed height, when that is already smaller).
  static const double _minKeyHeight = 44;

  /// The smallest gap between rows on a ticket short of room.
  static const double _minRowGap = 4;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // On a slip ([SlipFit]) the amount pad fits the height it is given:
    // as designed when there is room, its keys and gaps easing down to
    // a 44 pt tap target when the form above needs the room.
    final adaptive = compact && SlipDensity.adaptive(context);
    final double? keyHeight = adaptive ? null : _keyHeight;
    final rows = <Widget>[
      _buildRow(context, ['1', '2', '3'], keyHeight),
      _buildRow(context, ['4', '5', '6'], keyHeight),
      _buildRow(context, ['7', '8', '9'], keyHeight),
      _buildBottomRow(context, c, keyHeight),
    ];
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w),
      child: adaptive
          ? _KeypadRows(
              keyHeight: _keyHeight,
              minKeyHeight: math.min(_minKeyHeight, _keyHeight),
              rowGap: _rowGap,
              minRowGap: math.min(_minRowGap, _rowGap),
              give: SlipDensity.keypadGive(context),
              onRange: (range) =>
                  SlipDensity.reportKeypadRange(context, range),
              children: rows,
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) SizedBox(height: _rowGap),
                  rows[i],
                ],
              ],
            ),
    );
  }

  Widget _buildBottomRow(
      BuildContext context, AppColorsExtension c, double? keyHeight) {
    return Row(
            crossAxisAlignment: keyHeight == null
                ? CrossAxisAlignment.stretch
                : CrossAxisAlignment.center,
            children: [
              Expanded(
                child: showDecimal
                    ? _BouncingKey(
                        height: keyHeight,
                        onPressed: onDecimalPressed ?? () {},
                        surfaceColor: c.surface,
                        activeColor: c.surfaceLight,
                        isSecondary: true,
                        chromed: chromed,
                        child: Text(
                          '.',
                          style: TextStyle(
                            color: c.textPrimary,
                            fontSize: _digitSize,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                            height: 1.0,
                          ),
                        ),
                      )
                    : onBiometricPressed != null
                        ? _BouncingKey(
                            height: keyHeight,
                            onPressed: onBiometricPressed!,
                            surfaceColor: c.surface,
                            activeColor: c.surfaceLight,
                            isSecondary: true,
                            chromed: chromed,
                            // Was the accent, the only warm colour on an
                            // otherwise neutral grid, which read as a
                            // warning rather than a way in.
                            child: Icon(
                                Theme.of(context).platform == TargetPlatform.iOS
                                    ? Icons.face_rounded
                                    : Icons.fingerprint_rounded,
                                color: c.textSecondary,
                                size: 28.sp),
                          )
                        : const SizedBox(),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: _BouncingKey(
                  height: keyHeight,
                  onPressed: () => onDigitPressed('0'),
                  surfaceColor: c.surface,
                  activeColor: c.surfaceLight,
                  chromed: chromed,
                  child: Text(
                    '0',
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: _digitSize,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: _BouncingKey(
                  height: keyHeight,
                  onPressed: onBackspacePressed,
                  surfaceColor: c.surface,
                  activeColor: c.surfaceLight,
                  isSecondary: true,
                  chromed: chromed,
                  child: Icon(Icons.backspace_rounded,
                      color: c.textSecondary, size: 24.sp),
                ),
              ),
            ],
          );
  }

  Widget _buildRow(
      BuildContext context, List<String> digits, double? keyHeight) {
    final c = context.colors;

    return Row(
      crossAxisAlignment: keyHeight == null
          ? CrossAxisAlignment.stretch
          : CrossAxisAlignment.center,
      children: digits.map((digit) {
        return Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 6.w),
            child: _BouncingKey(
              height: keyHeight,
              onPressed: () => onDigitPressed(digit),
              surfaceColor: c.surface,
              activeColor: c.surfaceLight,
              chromed: chromed,
              child: Text(
                digit,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: _digitSize,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  height: 1.0,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _BouncingKey extends StatefulWidget {
  final VoidCallback onPressed;
  final Widget child;
  final bool isSecondary;
  final Color surfaceColor;
  final Color activeColor;

  /// Null fills the height the row gives it (an adaptive pad).
  final double? height;
  final bool chromed;

  const _BouncingKey({
    required this.onPressed,
    required this.child,
    required this.surfaceColor,
    required this.activeColor,
    required this.height,
    this.isSecondary = false,
    this.chromed = false,
  });

  @override
  State<_BouncingKey> createState() => _BouncingKeyState();
}

class _BouncingKeyState extends State<_BouncingKey>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;
  late Animation<Color?> _color;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      lowerBound: 0.0,
      upperBound: 1.0,
    );

    _scale = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutQuad),
    );

    _color = ColorTween(
      begin: widget.isSecondary ? Colors.transparent : widget.surfaceColor,
      end: widget.isSecondary ? widget.surfaceColor : widget.activeColor,
    ).animate(_controller);
  }

  @override
  void didUpdateWidget(covariant _BouncingKey oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.surfaceColor != widget.surfaceColor ||
        oldWidget.activeColor != widget.activeColor ||
        oldWidget.isSecondary != widget.isSecondary) {
      _color = ColorTween(
        begin: widget.isSecondary ? Colors.transparent : widget.surfaceColor,
        end: widget.isSecondary ? widget.surfaceColor : widget.activeColor,
      ).animate(_controller);
    }
  }

  void _onTapDown(TapDownDetails details) {
    HapticFeedback.lightImpact();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (!reduceMotion) _controller.forward();
  }

  void _onTapUp(TapUpDetails details) {
    _controller.reverse();
    widget.onPressed();
  }

  void _onTapCancel() {
    _controller.reverse();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isLight = !context.isDark;
    // The digits read as ten solid keys; the biometric and backspace
    // keys stay quiet until pressed, which is what a phone keypad does.
    final chrome = widget.chromed && !widget.isSecondary;
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => Transform.scale(
          scale: _scale.value,
          child: Container(
            height: widget.height,
            decoration: BoxDecoration(
              color: _color.value,
              borderRadius: widget.chromed
                  ? AppRadius.buttonBorder
                  : BorderRadius.circular(24.r),
              border: chrome
                  ? Border.all(
                      color: isLight ? c.border : c.borderSubtle,
                      width: isLight ? 1.0 : 0.5,
                    )
                  : null,
              boxShadow: chrome && isLight
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            alignment: Alignment.center,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class PinProgressIndicator extends StatelessWidget {
  final int currentLength;
  final int totalDigits;

  const PinProgressIndicator({
    super.key,
    required this.currentLength,
    this.totalDigits = 6,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(totalDigits, (index) {
        final isFilled = index < currentLength;

        // The dots were 12 and 14 across, which on a screen whose only
        // other content is a title and a keypad read as an afterthought
        // rather than as the thing being filled in. They are the
        // progress: they get the size to say so, and a filled one steps
        // up a further two points so the last key press is visible from
        // the corner of the eye rather than only by counting.
        return AnimatedContainer(
          duration:
              reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          margin: EdgeInsets.symmetric(horizontal: 9.w),
          width: isFilled ? 20.w : 18.w,
          height: isFilled ? 20.w : 18.w,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isFilled ? c.textPrimary : Colors.transparent,
            border: isFilled
                ? null
                : Border.all(
                    color: c.textTertiary.withValues(alpha: 0.45), width: 1.8),
          ),
        );
      }),
    );
  }
}

/// The amount pad's four rows, as tall as the height they are given:
/// as designed ([keyHeight], [rowGap]) when there is room, easing down to
/// [minKeyHeight] and [minRowGap] together as the room shrinks. Reports
/// that smallest height as its minimum intrinsic height, so the slip
/// knows how far the pad can give. With unbounded height (scrolled with
/// the form) it takes its designed height less [give].
class _KeypadRows extends MultiChildRenderObjectWidget {
  const _KeypadRows({
    required this.keyHeight,
    required this.minKeyHeight,
    required this.rowGap,
    required this.minRowGap,
    required this.give,
    required this.onRange,
    required super.children,
  });

  final double keyHeight, minKeyHeight, rowGap, minRowGap, give;
  final ValueChanged<double> onRange;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderKeypadRows(
        keyHeight: keyHeight,
        minKeyHeight: minKeyHeight,
        rowGap: rowGap,
        minRowGap: minRowGap,
        give: give,
        onRange: onRange,
      );

  @override
  void updateRenderObject(BuildContext context, _RenderKeypadRows r) {
    r
      ..keyHeight = keyHeight
      ..minKeyHeight = minKeyHeight
      ..rowGap = rowGap
      ..minRowGap = minRowGap
      ..give = give
      ..onRange = onRange;
  }
}

class _KeypadRowParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderKeypadRows extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _KeypadRowParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _KeypadRowParentData> {
  _RenderKeypadRows({
    required double keyHeight,
    required double minKeyHeight,
    required double rowGap,
    required double minRowGap,
    required double give,
    required this.onRange,
  })  : _keyHeight = keyHeight,
        _minKeyHeight = minKeyHeight,
        _rowGap = rowGap,
        _minRowGap = minRowGap,
        _give = give;

  double _keyHeight, _minKeyHeight, _rowGap, _minRowGap, _give;
  ValueChanged<double> onRange;

  set keyHeight(double v) => _set(_keyHeight, v, () => _keyHeight = v);
  set minKeyHeight(double v) =>
      _set(_minKeyHeight, v, () => _minKeyHeight = v);
  set rowGap(double v) => _set(_rowGap, v, () => _rowGap = v);
  set minRowGap(double v) => _set(_minRowGap, v, () => _minRowGap = v);
  set give(double v) => _set(_give, v, () => _give = v);

  void _set(double old, double v, VoidCallback apply) {
    if (old == v) return;
    apply();
    markNeedsLayout();
  }

  int get _gaps => math.max(0, childCount - 1);
  double get _natural => childCount * _keyHeight + _gaps * _rowGap;
  double get _smallest => childCount * _minKeyHeight + _gaps * _minRowGap;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _KeypadRowParentData) {
      child.parentData = _KeypadRowParentData();
    }
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      _smallest;

  @override
  double computeMaxIntrinsicHeight(double width) => _unbounded;

  /// Its height with no bound: as designed, less what it gives.
  double get _unbounded =>
      (_natural - _give).clamp(_smallest, _natural).toDouble();

  @override
  double computeMinIntrinsicWidth(double height) {
    var w = 0.0;
    for (var c = firstChild; c != null; c = childAfter(c)) {
      w = math.max(w, c.getMinIntrinsicWidth(_keyHeight));
    }
    return w;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    var w = 0.0;
    for (var c = firstChild; c != null; c = childAfter(c)) {
      w = math.max(w, c.getMaxIntrinsicWidth(_keyHeight));
    }
    return w;
  }

  double _heightFor(BoxConstraints constraints) {
    if (!constraints.hasBoundedHeight) return _unbounded;
    return constraints.maxHeight.clamp(_smallest, _natural).toDouble();
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.constrain(
      Size(constraints.maxWidth, _heightFor(constraints)));

  @override
  void performLayout() {
    onRange(_natural - _smallest);
    final height = _heightFor(constraints);
    final span = _natural - _smallest;
    final t = span <= 0 ? 1.0 : ((height - _smallest) / span).clamp(0.0, 1.0);
    final key = _minKeyHeight + (_keyHeight - _minKeyHeight) * t;
    final gap = _minRowGap + (_rowGap - _minRowGap) * t;
    final width = constraints.maxWidth;
    var y = 0.0;
    for (var c = firstChild; c != null; c = childAfter(c)) {
      c.layout(BoxConstraints.tightFor(width: width, height: key));
      (c.parentData! as _KeypadRowParentData).offset = Offset(0, y);
      y += key + gap;
    }
    size = constraints.constrain(Size(width, height));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
