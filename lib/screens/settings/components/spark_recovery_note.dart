import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/theme/app_theme.dart';

/// Under a Spark wallet's 12 words: those words restore its balance only
/// in a wallet that supports Spark. A plain Bitcoin wallet derives the
/// on-chain addresses from them and shows nothing. Same quiet card as the
/// "never share these words" warning beside it.
class SparkRecoveryNote extends StatelessWidget {
  const SparkRecoveryNote({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      key: const ValueKey('spark-recovery-note'),
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: c.borderSubtle, width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded,
              size: 20.sp, color: c.textSecondary),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              context.l10n.sparkRecoveryNote,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 14.sp,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
