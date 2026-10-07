// lib/screens/shared/seed_word_tile.dart
//
// One numbered recovery-phrase word tile. Shared by the Settings seed
// words screen and the backup-wallet reveal step so both grids read as
// the same component instead of two drifting copies.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/theme/app_theme.dart';

class SeedWordTile extends StatelessWidget {
  /// 1-based position of the word in the phrase.
  final int index;
  final String word;

  const SeedWordTile({super.key, required this.index, required this.word});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: c.borderSubtle, width: 0.5),
      ),
      child: Row(
        children: [
          SizedBox(width: 14.w),
          Text(
            '$index.',
            style: TextStyle(
              color: c.textTertiary,
              fontSize: 14.sp,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(width: 8.w),
          Flexible(
            child: Text(
              word,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 15.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
