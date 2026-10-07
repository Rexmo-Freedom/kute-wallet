import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
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

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildRow(context, ['1', '2', '3']),
          SizedBox(height: _rowGap),
          _buildRow(context, ['4', '5', '6']),
          SizedBox(height: _rowGap),
          _buildRow(context, ['7', '8', '9']),
          SizedBox(height: _rowGap),
          Row(
            children: [
              Expanded(
                child: showDecimal
                    ? _BouncingKey(
                        height: _keyHeight,
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
                            height: _keyHeight,
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
                  height: _keyHeight,
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
                  height: _keyHeight,
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
          ),
        ],
      ),
    );
  }

  Widget _buildRow(BuildContext context, List<String> digits) {
    final c = context.colors;

    return Row(
      children: digits.map((digit) {
        return Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 6.w),
            child: _BouncingKey(
              height: _keyHeight,
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
  final double height;
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
