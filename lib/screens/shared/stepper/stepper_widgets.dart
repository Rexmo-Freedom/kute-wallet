import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/theme/app_theme.dart';

/// Top-of-screen progress indicator for a multi-step flow. Renders
/// `totalSteps` segments separated by 4-px gaps; each segment fills
/// fully when its step is completed, half when it's the active step,
/// empty when it's still locked. Smooth color transitions on every
/// rebuild so progressing through the flow feels animated.
///
/// Shared between `confirm_send.dart` and `confirm_receive.dart` so
/// the two stepper flows feel byte-identical.
class StepperProgress extends StatelessWidget {
  final int totalSteps;
  final int currentStep;
  final Set<int> completedSteps;
  final AppColorsExtension colors;

  const StepperProgress({
    super.key,
    required this.totalSteps,
    required this.currentStep,
    required this.completedSteps,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors;
    // The fill is decorative progress feedback, so it collapses to its
    // end state when the person has asked the OS to stop animating.
    final fillDuration = MediaQuery.of(context).disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 320);
    return Row(
      children: List.generate(totalSteps, (i) {
        final isCompleted = completedSteps.contains(i);
        final isActive = currentStep == i && !isCompleted;
        final progress = isCompleted ? 1.0 : (isActive ? 0.5 : 0.0);
        final fillColor = isCompleted ? const Color(0xFF47C97A) : c.accent;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i < totalSteps - 1 ? 4.w : 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2.r),
              child: SizedBox(
                height: 4.h,
                child: LayoutBuilder(
                  builder: (context, cons) {
                    return Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        Container(
                          width: cons.maxWidth,
                          color: c.surfaceLight,
                        ),
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.0, end: progress),
                          duration: fillDuration,
                          curve: Curves.easeOutCubic,
                          builder: (_, t, __) => Container(
                            width: cons.maxWidth * t,
                            color: fillColor,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// Page wrapper for each step — title at top, optional subtitle,
/// then the step's body. Keeps consistent typography + spacing across
/// pages so the swipe transitions feel like one continuous flow rather
/// than several unrelated screens.
class StepPageWrapper extends StatelessWidget {
  final String title;
  final String subtitle;
  final AppColorsExtension colors;
  final Widget child;

  /// When true, the wrapper renders a tighter rhythm (smaller title +
  /// subtitle + reduced gap between the header and the child). Used by
  /// dense content surfaces — e.g. the hardware Sign step — where the
  /// default 32sp display title eats half the viewport before the
  /// signing controls appear.
  final bool tight;

  /// Optional control on the title's own row, right-aligned (the send
  /// Review step puts its Ask Sal chip here rather than above the body).
  final Widget? trailing;

  const StepPageWrapper({
    super.key,
    required this.title,
    required this.subtitle,
    required this.colors,
    required this.child,
    this.tight = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: tight ? 6.h : 12.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(title,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: tight ? 24.sp : 32.sp,
                      fontWeight: FontWeight.w800,
                      letterSpacing: tight ? -0.5 : -0.7,
                      height: 1.05,
                    )),
              ),
              if (trailing != null) ...[
                SizedBox(width: 12.w),
                trailing!,
              ],
            ],
          ),
          if (subtitle.isNotEmpty) ...[
            SizedBox(height: tight ? 4.h : 6.h),
            Text(subtitle,
                style: TextStyle(
                  color: c.textTertiary,
                  fontSize: tight ? 14.sp : 15.sp,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.1,
                )),
          ],
          SizedBox(height: tight ? 14.h : 28.h),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Shared bottom CTA for a generic 4–5 step stepper. Renders one
/// consistent Continue button that the parent enables/disables per
/// step, so steps share the same color, height, and position.
///
/// `visibleSteps` is the set of step indices for which this CTA
/// should render. The Send screen passes `{1, 2}` (Amount + Send-to)
/// while Receive passes `{1, 2}` (Amount + Method) — both have steps
/// where the page itself owns its primary action (Pay-with auto-tap,
/// Review slide-to-confirm, Sign external) so the shared button is
/// hidden there.
class SharedStepCta extends StatelessWidget {
  final int step;
  final AppColorsExtension colors;
  final bool enabled;
  final Set<int> visibleSteps;

  /// Optional label override; defaults to the localized "Continue".
  final String? label;
  final VoidCallback onContinue;

  const SharedStepCta({
    super.key,
    required this.step,
    required this.colors,
    required this.enabled,
    required this.onContinue,
    this.visibleSteps = const {1, 2},
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    if (!visibleSteps.contains(step)) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: 12.h),
      child: AppButton(
        text: label ?? context.l10n.continueLabel,
        onPressed: enabled ? onContinue : null,
      ),
    );
  }
}
