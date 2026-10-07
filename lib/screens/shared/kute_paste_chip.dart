// lib/screens/shared/kute_paste_chip.dart
//
// Small "Paste" and "Scan" actions that sit next to an input field
// instead of a full-width button. Shared by the import screens and every
// typed-recipient field (dollar send, refund addresses) so paste and
// scan read the same everywhere.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/theme/app_theme.dart';

class KutePasteChip extends StatelessWidget {
  final VoidCallback onPressed;

  const KutePasteChip({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) => _KuteFieldChip(
        icon: Icons.content_paste_rounded,
        label: context.l10n.paste,
        onPressed: onPressed,
      );
}

/// The Scan twin of [KutePasteChip]: opens the shared smart scanner. The
/// caller owns what the scanned value means (see `scanRecipientRaw`).
class KuteScanChip extends StatelessWidget {
  final VoidCallback onPressed;

  const KuteScanChip({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) => _KuteFieldChip(
        icon: Icons.qr_code_scanner_rounded,
        label: context.l10n.scan,
        onPressed: onPressed,
      );
}

class _KuteFieldChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _KuteFieldChip({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.buttonBorder,
        side: BorderSide(color: c.borderSubtle, width: 0.5),
      ),
      child: InkWell(
        borderRadius: AppRadius.buttonBorder,
        onTap: () {
          HapticFeedback.selectionClick();
          onPressed();
        },
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 9.h),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: c.textSecondary, size: 15.sp),
              SizedBox(width: 6.w),
              Text(
                label,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
