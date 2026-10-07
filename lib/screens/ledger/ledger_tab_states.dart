// lib/screens/ledger/ledger_tab_states.dart
//
// Shared states for the Ledger account tabs (Wallet hardening Phase 4,
// P4.4): "Turn on investing" while the Ledger is not confirmed for it, the
// partial-load note (never zero), loading, a full read failure and a
// quiet section header. All read-only; nothing here connects a device.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/theme/app_theme.dart';

/// Shown on the Investing and Predictions tabs while the Ledger has no
/// verified Ethereum account. The button opens the setup step.
class LedgerEnableInvestingCard extends StatelessWidget {
  final VoidCallback onEnable;

  const LedgerEnableInvestingCard({super.key, required this.onEnable});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 24.h, 16.w, 16.h),
      child: Container(
        padding: EdgeInsets.all(20.w),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(color: c.borderSubtle, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.ledgerEnableInvestingTitle,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 18.sp,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              l10n.ledgerEnableInvestingBodyPlain,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 15.sp,
                height: 1.4,
              ),
            ),
            SizedBox(height: 16.h),
            AppButton(
              text: l10n.ledgerSetupTurnOnCta,
              onPressed: onEnable,
            ),
          ],
        ),
      ),
    );
  }
}

/// "Some balances could not load". A failed read is never shown as zero.
class LedgerPartialLoadNote extends StatelessWidget {
  final VoidCallback? onRetry;

  const LedgerPartialLoadNote({super.key, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 0),
      child: Semantics(
        liveRegion: true,
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded,
                size: 16.sp, color: c.textTertiary),
            SizedBox(width: 6.w),
            Expanded(
              child: Text(
                l10n.ledgerPartialLoad,
                style: TextStyle(
                  color: c.textSecondary,
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (onRetry != null)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onRetry!();
                },
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
                  child: Text(
                    l10n.ledgerRetry,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class LedgerTabLoading extends StatelessWidget {
  const LedgerTabLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 48.h),
      child: Center(
        child: LoadingAnimationWidget.staggeredDotsWave(
          color: context.colors.textSecondary,
          size: 28.sp,
        ),
      ),
    );
  }
}

/// The whole read failed. Shows the partial-load copy with a retry; no
/// balances, no zero.
class LedgerTabLoadFailed extends StatelessWidget {
  final VoidCallback onRetry;

  const LedgerTabLoadFailed({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 32.h),
      child: LedgerPartialLoadNote(onRetry: onRetry),
    );
  }
}

/// Quiet explanatory line (read-only account, no account yet).
class LedgerTabNote extends StatelessWidget {
  final String text;

  const LedgerTabNote({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 0),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: c.textSecondary, fontSize: 14.sp, height: 1.4),
      ),
    );
  }
}

