// lib/screens/shared/pending_deposit_line.dart
//
// The pool hero's second slot while a deposit is in flight: the normal
// "$X invested" line with a light grey "≈ $Y arriving · deposit
// processing" line under it. Mounted through
// PoolBalanceHeader.investedChild by the Predictions and Trading
// screens, so the hero stops reading a flat $0.00 while the user's
// money is mid-swap. This exact treatment is user-approved ("like this
// it is perfect") — do not restyle it into a pill or chip.
//
// The "≈" is load bearing: the figure is the Orchestra quote's estimate,
// not a settled amount, and a quote must never read as a fact.

import 'package:kute/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/theme/app_theme.dart';

class PendingDepositLine extends StatelessWidget {
  /// The normal invested line ('$0.00 invested'); rendered exactly as
  /// PoolBalanceHeader would have rendered investedText.
  final String investedText;

  /// Pre-formatted pending figure ('$2.00'). Null hides the arriving
  /// line (used when only [leavingText] or [noteText] applies).
  final String? pendingText;

  /// Pre-formatted amount mid-withdrawal ('$1.50'). Renders the mirror
  /// line: the funds have left the pool balance and are being
  /// processed, so the drop is narrated rather than unexplained.
  final String? leavingText;

  /// Optional extra grey line in the same voice — e.g. the Trading
  /// hero's "waiting on Arbitrum" dust note.
  final String? noteText;

  const PendingDepositLine({
    super.key,
    required this.investedText,
    this.pendingText,
    this.leavingText,
    this.noteText,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final grey = TextStyle(
      color: c.textTertiary,
      fontSize: 13.sp,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.1,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (investedText.isNotEmpty)
          RollingNumberText(
            text: investedText,
            style: TextStyle(
              color: c.textSecondary,
              fontSize: 14.sp,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        if (pendingText != null) ...[
          SizedBox(height: 2.h),
          Text(context.l10n.pendingDepositArriving(pendingText!), style: grey),
        ],
        if (leavingText != null) ...[
          SizedBox(height: 2.h),
          Text(context.l10n.pendingWithdrawalLeaving(leavingText!), style: grey),
        ],
        if (noteText != null) ...[
          SizedBox(height: 2.h),
          Text(noteText!, style: grey),
        ],
      ],
    );
  }
}
