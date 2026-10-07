// lib/screens/analytics/components/analytics_card.dart
//
// The raised card every analytics chart sits in — the rounded surface,
// its elevation, and the clip that keeps a chart inside the corners.
//
// Extracted from the Home analytics strip so the Dollars tab's balance
// chart renders in the SAME card, rather than a copy of it that drifts
// the first time the elevation or the radius is retuned.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/theme/app_theme.dart';

class AnalyticsCard extends StatelessWidget {
  const AnalyticsCard({
    super.key,
    required this.height,
    required this.child,
  });

  /// Animated so a tab swap that needs more room (Fees) grows into it
  /// instead of snapping.
  final double height;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isLight = Theme.of(context).brightness == Brightness.light;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      height: height,
      curve: Curves.easeOutQuart,
      // Calm: the card already reads as a raised surface via its fill +
      // shadow, so an extra hairline border would be double-chrome.
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(20.r),
        boxShadow: isLight
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ]
            : [
                BoxShadow(
                  color: c.cardShadow,
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20.r),
        child: child,
      ),
    );
  }
}
