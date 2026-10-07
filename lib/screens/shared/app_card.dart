// Canonical card surface for the 2027 design system. One consistent radius,
// surface fill, and restrained depth (a hairline edge in light mode, no heavy
// shadow) so every card across the app reads as the same material instead of
// each screen rolling its own container.
//
// Pass [onTap] to make it interactive — it gets a subtle press-scale + haptic
// (honouring Reduce Motion). Reduce Motion is read in build(), never initState.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/theme/app_theme.dart';

class AppCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// Fill override; defaults to the theme surface.
  final Color? color;

  /// Corner radius; defaults to the card baseline (18).
  final double? radius;

  /// When false, the hairline border is dropped (e.g. cards already sitting
  /// on a distinct background).
  final bool bordered;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
    this.radius,
    this.bordered = true,
  });

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final r = widget.radius ?? 18.r;

    final Widget card = Container(
      padding: widget.padding,
      decoration: BoxDecoration(
        color: widget.color ?? c.surface,
        borderRadius: BorderRadius.circular(r),
        border: widget.bordered
            ? Border.all(
                color: isLight ? c.border.withValues(alpha: 0.6) : c.borderSubtle,
                width: 0.5,
              )
            : null,
        boxShadow: isLight
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: widget.child,
    );

    if (widget.onTap == null) return card;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: reduceMotion ? null : (_) => setState(() => _pressed = true),
      onTapUp: reduceMotion ? null : (_) => setState(() => _pressed = false),
      onTapCancel: reduceMotion ? null : () => setState(() => _pressed = false),
      onTap: () {
        HapticFeedback.lightImpact();
        widget.onTap!();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: card,
      ),
    );
  }
}
