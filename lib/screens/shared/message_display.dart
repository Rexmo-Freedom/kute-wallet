import 'dart:async';
import 'package:kute/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

void showMessageSnackBarInfo({
  required BuildContext context,
  required String message,
  Duration duration = const Duration(seconds: 4),
}) {
  ToastService.show(
    context,
    ToastMessage(
      message: message,
      icon: Icons.info_rounded,
      accentColor: AppColors.info,
      neutral: true,
      duration: duration,
    ),
  );
}

void showMessageSnackBar({
  required BuildContext context,
  required String message,
  required bool error,
  bool info = false,
  Duration duration = const Duration(seconds: 4),
}) {
  IconData icon;
  Color color;

  if (error) {
    icon = Icons.error_rounded;
    color = AppColors.error;
  } else if (info) {
    icon = Icons.info_rounded;
    color = AppColors.info;
  } else {
    icon = Icons.check_circle_rounded;
    color = AppColors.success;
  }

  ToastService.show(
    context,
    ToastMessage(
      message: message,
      icon: icon,
      accentColor: color,
      // Info carries no status; render its icon chip neutral (error stays
      // red, success stays green).
      neutral: info,
      duration: duration,
    ),
  );
}

/// A banner in the same toast style with its own icon and accent, and an
/// optional tap action (the banner closes on tap). Used for in-app
/// alerts that point somewhere, such as a trade alert opening the
/// position it is about.
void showMessageBanner({
  required BuildContext context,
  required String message,
  required IconData icon,
  required Color accentColor,
  VoidCallback? onTap,
  Duration duration = const Duration(seconds: 6),
}) {
  ToastService.show(
    context,
    ToastMessage(
      message: message,
      icon: icon,
      accentColor: accentColor,
      duration: duration,
      onTap: onTap,
    ),
  );
}

class ToastService {
  static OverlayEntry? _overlayEntry;
  static Timer? _timer;
  static bool _isVisible = false;

  static void show(BuildContext context, ToastMessage toast) {
    if (_isVisible) {
      _removeCurrentToast();
    }

    _overlayEntry = OverlayEntry(
      builder: (context) => _AnimatedToastWidget(
        message: toast,
        onDismiss: _removeCurrentToast,
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
    _isVisible = true;
  }

  static void _removeCurrentToast() {
    _timer?.cancel();
    _timer = null;
    _overlayEntry?.remove();
    _overlayEntry = null;
    _isVisible = false;
  }
}

class ToastMessage {
  final String message;
  final IconData icon;
  final Color accentColor;

  /// True for info toasts: the icon chip renders as a neutral plate
  /// (surface tint, monochrome icon) instead of a status tint.
  final bool neutral;
  final Duration duration;

  /// Tapping the toast runs this and closes it. Null: not tappable.
  final VoidCallback? onTap;

  const ToastMessage({
    required this.message,
    required this.icon,
    required this.accentColor,
    this.neutral = false,
    required this.duration,
    this.onTap,
  });
}

class _AnimatedToastWidget extends StatefulWidget {
  final ToastMessage message;
  final VoidCallback onDismiss;

  const _AnimatedToastWidget({
    required this.message,
    required this.onDismiss,
  });

  @override
  State<_AnimatedToastWidget> createState() => _AnimatedToastWidgetState();
}

class _AnimatedToastWidgetState extends State<_AnimatedToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  double _dragOffset = 0.0;
  bool _isDragging = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
      reverseDuration: const Duration(milliseconds: 220),
    );

    // Calm, single-spring entrance — the old elasticOut + scale-back
    // bounce read as jittery once the rest of the app settled on
    // smoother motion. A short slide-down + fade is enough to draw the
    // eye without the "boing".
    final curvedAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -0.6),
      end: Offset.zero,
    ).animate(curvedAnimation);

    _scaleAnimation = Tween<double>(
      begin: 0.96,
      end: 1.0,
    ).animate(curvedAnimation);

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  bool _entranceStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The slide/scale/fade entrance is decorative transition motion, so
    // honour the OS "reduce motion" setting: snap the toast into place
    // instead of animating it in.
    _reduceMotion = MediaQuery.of(context).disableAnimations;

    if (!_entranceStarted) {
      _entranceStarted = true;
      if (_reduceMotion) {
        _controller.value = 1.0;
      } else {
        _controller.forward();
      }

      Future.delayed(widget.message.duration, () {
        if (mounted && !_isDragging) {
          _dismiss();
        }
      });
    }
  }

  Future<void> _dismiss() async {
    if (_reduceMotion) {
      _controller.value = 0.0;
    } else {
      await _controller.reverse();
    }
    widget.onDismiss();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _isDragging = true;
      _dragOffset += details.delta.dy;
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (_dragOffset < -20 || details.primaryVelocity! < -500) {
      _dismiss();
    } else {
      setState(() {
        _dragOffset = 0.0;
        _isDragging = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 16.h,
      left: 16.w,
      right: 16.w,
      child: SlideTransition(
        position: _slideAnimation,
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: GestureDetector(
              onTap: widget.message.onTap == null
                  ? null
                  : () {
                      final tap = widget.message.onTap!;
                      widget.onDismiss();
                      tap();
                    },
              onVerticalDragUpdate: _onVerticalDragUpdate,
              onVerticalDragEnd: _onVerticalDragEnd,
              child: Transform.translate(
                offset: Offset(0, _dragOffset),
                child: _buildToastContent(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToastContent() {
    final c = context.colors;
    final accent = widget.message.accentColor;
    // Match the app's standard floating card (AppDecorations.card):
    // surface fill, layered soft shadows in light mode, hairline outline
    // in dark. The status color lives only in the tinted icon chip —
    // same pattern the rest of the app uses for accenting a row.
    return Container(
      decoration: AppDecorations.card(context),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 13.h),
        child: Row(
          children: [
            Container(
              width: 34.sp,
              height: 34.sp,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: widget.message.neutral
                    ? c.surfaceLight
                    : accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(
                widget.message.icon,
                color: widget.message.neutral ? c.textSecondary : accent,
                size: 18.sp,
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Text(
                widget.message.message,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                  letterSpacing: -0.1,
                  decoration: TextDecoration.none,
                  fontFamily: 'Inter',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
