// lib/screens/home/components/deposit/deposit_summary_card.dart
//
// The Move sheet's cost block: what the move costs and what arrives,
// on one neutral card instead of loose rows floating under the route.
// Every breakdown (provider split, conversion equivalent, the estimate
// caveats) stays one tap away inside the rows themselves.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/theme/app_theme.dart';

class MoveSummaryCard extends StatelessWidget {
  const MoveSummaryCard({super.key, required this.children});

  /// Fee / receive rows. Empty renders nothing at all, so a flow with
  /// no quote yet shows an empty gap rather than an empty card.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }
    final c = context.colors;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: c.borderSubtle, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}
