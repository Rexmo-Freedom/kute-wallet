// lib/screens/usd/flow/usd_flow_widgets.dart
//
// THE SHELL THE TWO DOLLAR FLOWS SHARE.
//
// Receive dollars and the quoted receive: pick the coin, say how much,
// then the address the sender pays into. (Send dollars now wears the
// bitcoin send's own screens, from shared/send/send_flow_widgets.dart.)
//
// Everything here is presentation. No money call, no route table and no
// provider lives in this file; the two screens own their own rails and
// pass finished strings in.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/amount_keypad_panel.dart';
import 'package:kute/screens/shared/coin_asset_grid.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/stepper/stepper_widgets.dart';
import 'package:kute/theme/app_theme.dart';

// The coin question is shared beyond the dollar flows (both bitcoin
// directions ask it), so it lives in shared/ and is re-exported here
// for the two screens that read this file.
export 'package:kute/screens/shared/coin_asset_grid.dart';

/// The chrome both dollar flows wear: a transparent bar over the screen
/// background with a centred title and the shared back button, the
/// shared step progress under it, the step body, and ONE primary action
/// pinned full width at the bottom.
///
/// The action is pinned on every step deliberately. The old send screen
/// floated its button wherever the step's `Spacer` happened to leave it,
/// which is why two steps in a row never looked like the same screen.
class UsdFlowScaffold extends StatelessWidget {
  const UsdFlowScaffold({
    super.key,
    required this.title,
    required this.totalSteps,
    required this.currentStep,
    required this.completedSteps,
    required this.child,
    this.action,
    this.onBack,
    this.resizeToAvoidBottomInset = true,
  });

  final String title;
  final int totalSteps;
  final int currentStep;
  final Set<int> completedSteps;

  /// The step body. Wrap it in a [StepPageWrapper] so every step's
  /// heading sits at the same height.
  final Widget child;

  /// The pinned bottom action. Null renders the space away rather than
  /// leaving a gap the eye reads as a missing button.
  final Widget? action;

  final VoidCallback? onBack;

  final bool resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      // The body sits BELOW the bar. Extending behind it put the step
      // progress and the first rows under a transparent app bar, so the
      // content ran off the top of the page.
      extendBodyBehindAppBar: false,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: c.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 17.sp,
            letterSpacing: -0.3,
          ),
        ),
        leading: KuteBackButton(onPressed: onBack),
      ),
      body: Stack(
        children: [
          Container(decoration: AppDecorations.screenGradient(context)),
          // A plain SafeArea, not PlatformSafeArea: that helper applies
          // the bottom inset on Android ONLY, so on iOS the pinned
          // action sat under the home indicator.
          SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(20.w, 6.h, 20.w, 12.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  StepperProgress(
                    totalSteps: totalSteps,
                    currentStep: currentStep,
                    completedSteps: completedSteps,
                    colors: c,
                  ),
                  Expanded(child: child),
                  if (action != null) ...[
                    SizedBox(height: 12.h),
                    action!,
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// THE AMOUNT STEP. The app's own hero figure over the app's own
/// keypad — the pairing the owner picked as the reference for every
/// amount in the app — with the available line, the optional percent
/// chips, and a live second line saying what the other side gets.
///
/// The OS keyboard never opens here: nothing in this body is focusable.
class UsdAmountStepBody extends StatelessWidget {
  const UsdAmountStepBody({
    super.key,
    required this.typed,
    required this.onChanged,
    this.prefix = '',
    this.suffix = '',
    this.secondaryLine,
    this.secondaryIsError = false,
    this.secondaryLoading = false,
    this.availableLabel,
    this.availableExceeded = false,
    this.onPercent,
    this.unitControl,
    this.maxDecimals = 2,
    this.enabled = true,
  });

  final String typed;
  final ValueChanged<String> onChanged;
  final String prefix;
  final String suffix;

  /// "They receive about $12.40", or the reason the amount is refused.
  final String? secondaryLine;
  final bool secondaryIsError;
  final bool secondaryLoading;

  final String? availableLabel;
  final bool availableExceeded;

  /// Null hides the 25/50/100 row (the receive side has no balance to
  /// take a percentage of).
  final ValueChanged<double>? onPercent;

  /// The unit the figure is typed in, rendered BESIDE it, on the right.
  /// Only the receive side has a unit to choose.
  ///
  /// It used to sit centred underneath, where it read as a caption on
  /// the number rather than the control that changes it (owner
  /// decision). [BigAmountDisplay] keeps both arrangements; this flow
  /// takes the trailing one.
  final Widget? unitControl;

  final int maxDecimals;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final percent = onPercent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BigAmountDisplay(
          prefix: prefix,
          suffix: suffix,
          amountText: typed,
          conversionLabel: secondaryLine,
          conversionIsError: secondaryIsError,
          conversionLoading: secondaryLoading,
          availableLabel: availableLabel,
          availableExceeded: availableExceeded,
          trailing: unitControl,
        ),
        const Spacer(),
        if (percent != null) ...[
          AmountPercentChips(
            enabled: enabled,
            onPercent: (ratio) {
              HapticFeedback.selectionClick();
              percent(ratio);
            },
          ),
          SizedBox(height: 10.h),
        ],
        AmountKeypad(
          value: typed,
          enabled: enabled,
          maxDecimals: maxDecimals,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// One label/value line of the review plate. Values that are addresses
/// get [monospace] so the characters line up while they are checked.
class UsdReviewLine extends StatelessWidget {
  const UsdReviewLine({
    super.key,
    required this.label,
    required this.value,
    this.emphasised = false,
    this.monospace = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool emphasised;
  final bool monospace;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 9.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: c.textTertiary,
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(width: 16.w),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: monospace ? 3 : 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: valueColor ?? c.textPrimary,
                fontSize: emphasised ? 16.sp : 14.sp,
                fontWeight: emphasised ? FontWeight.w800 : FontWeight.w600,
                fontFamily: monospace ? 'monospace' : null,
                letterSpacing: monospace ? -0.2 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The plate the review lines sit on.
class UsdReviewPlate extends StatelessWidget {
  const UsdReviewPlate({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: c.borderSubtle, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

/// m:ss. Not localized copy: it is digits and a colon.
String usdFormatCountdown(Duration d) {
  final seconds = d.inSeconds < 0 ? 0 : d.inSeconds;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// The quiet note a flow leaves under a plate: an expiry, a refund
/// rule, a reusable-address promise.
///
/// It holds text only. A note that also carried a button gave that
/// button a width no other button in either flow had; actions belong in
/// the page, below the note, at the page's own width.
class UsdFlowNote extends StatelessWidget {
  const UsdFlowNote({
    super.key,
    required this.lines,
    this.emphasis,
  });

  final List<String> lines;

  /// A line that should read louder than the rest (a countdown).
  final String? emphasis;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: c.surfaceLight,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < lines.length; i++) ...[
            if (i > 0) SizedBox(height: 6.h),
            Text(
              lines[i],
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.textTertiary,
                fontSize: 13.sp,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          if (emphasis != null) ...[
            SizedBox(height: 8.h),
            Text(
              emphasis!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 13.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The one pinned action. A thin wrapper so both screens cannot drift
/// on height, width or loading behaviour.
class UsdFlowAction extends StatelessWidget {
  const UsdFlowAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppButton(text: label, isLoading: loading, onPressed: onPressed),
        if (secondaryLabel != null) ...[
          SizedBox(height: 10.h),
          AppButton(
            text: secondaryLabel!,
            variant: AppButtonVariant.secondary,
            onPressed: onSecondary,
          ),
        ],
      ],
    );
  }
}

/// What the coin step shows behind the sheet.
///
/// The question itself is asked in [CoinAssetPickerSheet], which opens
/// over this step the moment the flow starts, because a grid of coins
/// is the same question here as it is on the bitcoin screens and a
/// dollar flow that asked it differently is exactly what made the two
/// feel unrelated. This is what the sheet was dismissed back to: a
/// statement of which coins the flow takes, and the way back in.
class UsdFlowCoinPickerPanel extends StatelessWidget {
  const UsdFlowCoinPickerPanel({
    super.key,
    required this.label,
    required this.groups,
    required this.onTap,
  });

  final String label;
  final List<CoinAssetGroup> groups;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: c.borderSubtle, width: 0.5),
      ),
      child: CoinMarksLine(
        label: label,
        groups: groups,
        moreLabel: context.l10n.receiveAlsoAcceptsMore,
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 16.h),
        onTap: onTap,
      ),
    );
  }
}
