// lib/screens/shared/pool_balance_header.dart
//
// Hero-style balance header for the pool screens (Predictions, Trading),
// echoing the Home screen's balance treatment (user decision: the balance
// belongs at the top of each screen, above the ongoing bets/positions,
// like the main screen — not on the bottom bar).

import 'package:kute/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/screens/home/components/action_pill.dart'
    show greenColor, redColor;
import 'package:kute/screens/home/components/home_action_row.dart'
    show NeutralActionChip;
import 'package:kute/theme/app_theme.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/screens/shared/kute_skeleton.dart';

class PoolBalanceHeader extends StatelessWidget {
  /// The formatted hero figure. Since the invested-first flip (user
  /// decision: invested on top, available underneath) callers pass the
  /// INVESTED amount here.
  final String amountText;

  /// Signed percent since investing rendered beside the hero, e.g.
  /// "+3.4%". Null hides it; [heroPctUp] picks green or red.
  final String? heroPctText;
  final bool heroPctUp;

  /// Caller-built widget under the hero (the pending-deposit lines
  /// during in-flight Orchestra moves). The old quiet "available" line
  /// and the "Manage investments" hero tap are gone (user decision:
  /// one green Manage CTA below carries the door and the figure).
  final Widget? investedChild;

  /// Formatted breakdown of the hero total, rendered as one quiet line
  /// directly under the number: "Invested $X · Available $Y" (user
  /// decision: both figures visible on the pool screens; the hero is
  /// the total, this line is the split, the CTA is pure action).
  /// Either side hides when null; the whole line hides when both are.
  final String? investedText;
  final String? availableText;

  /// The split line's labels; null reads the localized "Invested" /
  /// "Available", so no screen shows them in English.
  final String? investedLabel;
  final String? availableLabel;
  final String? totalLabel;
  final String? balanceDetail;

  /// Overrides the hero number's size. Null keeps the 48.sp Home-style
  /// treatment every pool tab uses. No live caller passes it today; it
  /// stays for a screen that wants to quiet a zero balance.
  final double? amountFontSize;

  /// Home-style action chips under the number (user decision: same
  /// design as the home screen). Deposit and Withdraw; search lives
  /// only in the bottom bar (user decision: no middle search chip).
  final VoidCallback? onDeposit;
  final VoidCallback? onWithdraw;

  /// Opens the pool's portfolio Builder flow. When set, a third "Build"
  /// chip sits BETWEEN Deposit and Withdraw (the manual replacement for
  /// the removed AI buckets/baskets).
  final VoidCallback? onBuild;
  final String buildLabel;
  final IconData buildIcon;
  final bool withdrawDisabled;
  final bool depositDisabled;

  /// Main action below the balance, optionally beside [trailingCta].
  /// Both children provide their own top spacing.
  final Widget? primaryCta;

  /// Quiet action beside the primary control, with matching top spacing.
  final Widget? trailingCta;

  /// Kept for screens such as Earn that still provide their own funding row.
  final bool showActionRow;

  /// While the account is still loading, the headline is a shimmer bar of
  /// the same height instead of a dash, the way the Home hero and the
  /// hardware wallets read while waking up.
  final bool loading;

  /// The headline is the last known figure, not a fresh read (still on
  /// its way, or the read failed): it reads in the secondary text colour
  /// until the next sync brings a fresh one.
  final bool stale;

  const PoolBalanceHeader({
    super.key,
    required this.amountText,
    this.loading = false,
    this.stale = false,
    this.heroPctText,
    this.heroPctUp = true,
    this.investedChild,
    this.investedText,
    this.availableText,
    this.investedLabel,
    this.availableLabel,
    this.totalLabel,
    this.balanceDetail,
    this.amountFontSize,
    this.onDeposit,
    this.onWithdraw,
    this.onBuild,
    this.buildLabel = 'Build',
    this.buildIcon = Icons.add_chart_rounded,
    this.depositDisabled = false,
    this.withdrawDisabled = false,
    this.primaryCta,
    this.trailingCta,
    this.showActionRow = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Mirrors the Home hero balance (user decision): just the centered
    // 48.sp number, whose formatter already prefixes the currency symbol.
    // Same size, weight and spacing as wallet_cards.dart's headline.
    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 6.h, 20.w, 12.h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (totalLabel != null)
            Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(totalLabel!,
                    style: TextStyle(color: c.textSecondary))),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (loading)
                  KuteSkeleton(
                    child: SkeletonBar(150.w, (amountFontSize ?? 48.sp) * 0.9,
                        radius: 12.r),
                  )
                else
                  RollingNumberText(
                    // The formatted amount carries its own currency
                    // symbol ($ / € / ₿ per settings) — no icon, per
                    // Joao. Rolls per digit like every live number
                    // on these screens.
                    text: amountText,
                    style: TextStyle(
                      color: stale ? c.textSecondary : c.textPrimary,
                      fontSize: amountFontSize ?? 48.sp,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.2,
                      height: 1.0,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                if (heroPctText != null)
                  Padding(
                    padding: EdgeInsets.only(left: 8.w),
                    child: Text(
                      heroPctText!,
                      style: TextStyle(
                        color: heroPctUp ? greenColor : redColor,
                        fontSize: 17.sp,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (investedText != null || availableText != null) ...[
            SizedBox(height: 8.h),
            _BalanceSplitLine(
                investedText: investedText,
                availableText: availableText,
                investedLabel: investedLabel ?? context.l10n.betInvested,
                availableLabel: availableLabel ?? context.l10n.available),
          ],
          if (balanceDetail != null && balanceDetail!.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(balanceDetail!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.textSecondary, fontSize: 13))),
          if (investedChild != null) ...[
            SizedBox(height: 6.h),
            investedChild!,
          ],
          if (primaryCta != null)
            Row(
              children: [
                Expanded(child: primaryCta!),
                if (trailingCta != null) ...[
                  SizedBox(width: 10.w),
                  trailingCta!,
                ],
              ],
            ),
          if (showActionRow &&
              (onDeposit != null || onWithdraw != null || onBuild != null)) ...[
            SizedBox(height: 12.h),
            Row(
              children: [
                if (onDeposit != null)
                  Expanded(
                    child: NeutralActionChip(
                      icon: Icons.south_west_rounded,
                      label: context.l10n.deposit,
                      disabled: depositDisabled,
                      onTap: () {
                        if (depositDisabled) return;
                        HapticFeedback.selectionClick();
                        onDeposit!();
                      },
                    ),
                  ),
                if (onBuild != null) ...[
                  if (onDeposit != null) SizedBox(width: 10.w),
                  _BuildIconChip(
                      label: buildLabel,
                      icon: buildIcon,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        onBuild!();
                      }),
                ],
                if (onWithdraw != null) ...[
                  if (onDeposit != null || onBuild != null)
                    SizedBox(width: 10.w),
                  Expanded(
                    child: NeutralActionChip(
                      icon: Icons.north_east_rounded,
                      label: context.l10n.withdraw,
                      disabled: withdrawDisabled,
                      onTap: () {
                        if (withdrawDisabled) return;
                        HapticFeedback.selectionClick();
                        onWithdraw!();
                      },
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A quiet 54x54 square chip beside the main Portfolio or Purchase
/// button, so the primary CTA keeps its width. [showLabel] false renders
/// the icon alone at 24.sp (the Scan chip), otherwise icon over label.
class PoolHeaderShortcut extends StatelessWidget {
  const PoolHeaderShortcut({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.showLabel = true,
    this.value,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool showLabel;

  /// Replaces the glyph with a figure under the label (the Earn chip
  /// shows its rate rather than a piggy bank).
  final String? value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: 12.h),
        child: Semantics(
          button: true,
          label: label,
          onTap: onTap,
          excludeSemantics: true,
          child: Opacity(
            opacity: onTap == null ? 0.35 : 1,
            child: _BuildIconChip(
              label: label,
              icon: icon,
              showLabel: showLabel,
              value: value,
              onTap: () {
                HapticFeedback.lightImpact();
                onTap?.call();
              },
            ),
          ),
        ),
      );
}

/// The quiet one-line split under the hero total: "Invested $X ·
/// Available $Y". Amounts roll like every live figure on these screens;
/// the words stay quiet so the numbers carry the line.
class _BalanceSplitLine extends StatelessWidget {
  final String? investedText;
  final String? availableText;

  final String investedLabel, availableLabel;
  const _BalanceSplitLine(
      {this.investedText,
      this.availableText,
      required this.investedLabel,
      required this.availableLabel});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final labelStyle = TextStyle(
      color: c.textTertiary,
      fontSize: 15.sp,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.1,
      height: 1.0,
    );
    final valueStyle = TextStyle(
      color: c.textSecondary,
      fontSize: 15.sp,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
      height: 1.0,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 8,
      children: [
        if (investedText != null) ...[
          Text('$investedLabel ', style: labelStyle),
          RollingNumberText(text: investedText!, style: valueStyle),
        ],
        if (investedText != null && availableText != null)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8.w),
            child: Text('·', style: labelStyle),
          ),
        if (availableText != null) ...[
          Text('$availableLabel ', style: labelStyle),
          RollingNumberText(text: availableText!, style: valueStyle),
        ],
      ],
    );
  }
}

/// Compact square chip for the portfolio Builder and the header
/// shortcuts, matching NeutralActionChip's chrome at a fixed 54x54.
class _BuildIconChip extends StatelessWidget {
  final VoidCallback onTap;
  final String label;
  final IconData icon;
  final bool showLabel;
  final String? value;
  const _BuildIconChip(
      {required this.onTap,
      required this.label,
      required this.icon,
      this.showLabel = true,
      this.value});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isLight = Theme.of(context).brightness == Brightness.light;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 54,
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isLight ? Colors.white : c.surface,
          borderRadius: AppRadius.buttonBorder,
          border: Border.all(
            color: isLight ? c.border : c.borderSubtle,
            width: isLight ? 1.0 : 0.5,
          ),
          boxShadow: isLight
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: value != null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(label,
                      maxLines: 1,
                      style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w600)),
                  SizedBox(height: 2.h),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(value!,
                        maxLines: 1,
                        style: TextStyle(
                            color: c.textSecondary,
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              )
            : showLabel
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, color: c.textPrimary, size: 20.sp),
                      Text(label,
                          style: TextStyle(
                              color: c.textPrimary,
                              fontSize: 12.sp,
                              fontWeight: FontWeight.w600)),
                    ],
                  )
                : Icon(icon, color: c.textPrimary, size: 24.sp),
      ),
    );
  }
}
