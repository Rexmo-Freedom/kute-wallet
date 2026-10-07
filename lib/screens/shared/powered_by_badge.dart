// lib/screens/shared/powered_by_badge.dart
//
// Small attribution label rendered on flows that route through a
// third-party provider (Orchestra cross-chain and USDC ↔ BTC swaps).
// Surfaces transparency about who actually settles the swap so users
// can tell which leg is on which counterparty when something needs
// support.

import 'package:kute/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/theme/app_theme.dart';

class PoweredByBadge extends StatelessWidget {
  /// User-facing provider name as it should appear in the badge —
  /// e.g. "Orchestra". No need to add "Powered by" — this widget
  /// prepends it.
  final String provider;
  /// Optional override for the leading icon. Defaults to a small
  /// info dot. Set to a brand-specific glyph (e.g. lightning bolt
  /// for BitcoinVN) to make the attribution scan faster.
  final IconData icon;
  /// Horizontal alignment within the parent. Most callers center
  /// the badge under the action card; some surfaces left-align it.
  final MainAxisAlignment alignment;

  const PoweredByBadge({
    super.key,
    required this.provider,
    this.icon = Icons.bolt_rounded,
    this.alignment = MainAxisAlignment.center,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: alignment,
      children: [
        Icon(icon, size: 13.sp, color: c.textSecondary),
        SizedBox(width: 5.w),
        Text(
          context.l10n.poweredByProvider(provider),
          style: TextStyle(
            color: c.textSecondary,
            fontSize: 13.sp,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
      ],
    );
  }
}
