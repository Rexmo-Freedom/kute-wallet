import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:kute/helpers/kute_dog_asset.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/creation/referrer_code_screen.dart'
    show referrerCodeStepAllowed, skipReferrerCodeStep;
import 'package:kute/screens/creation/set_pin.dart' show trackOnboardingStep;
import 'package:kute/services/tracking_service.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/theme/app_theme.dart';

class BetaSurveyScreen extends ConsumerStatefulWidget {
  const BetaSurveyScreen({super.key});

  @override
  ConsumerState<BetaSurveyScreen> createState() => _BetaSurveyScreenState();
}

class _BetaSurveyScreenState extends ConsumerState<BetaSurveyScreen> {
  String? _gender;
  String? _ageRange;

  @override
  void initState() {
    super.initState();
    trackOnboardingStep('beta_survey', path: 'create');
  }

  void _submit() {
    HapticFeedback.mediumImpact();

    TrackingService.track('beta_survey_completed', params: {
      'gender': _gender ?? 'not_specified',
      'age_range': _ageRange ?? 'not_specified',
    });

    if (_gender != null) {
      TrackingService.setUserProperty('gender', _gender!);
    }
    if (_ageRange != null) {
      TrackingService.setUserProperty('age_range', _ageRange!);
    }

    _goHome();
  }

  void _skip() {
    HapticFeedback.lightImpact();
    TrackingService.track('beta_survey_skipped');
    _goHome();
  }

  void _goHome() {
    // The referrer-code step is part of the affiliate promotion, so it only
    // shows where the runtime policy allows `affiliate.program`. Decided on
    // the current snapshot here at the navigation point; the step also
    // guards itself for a deep link. Fail closed: a policy that cannot be
    // fetched skips the step too (it is a promotion, not a feature the user
    // loses anything by missing). A referrer captured from an AppsFlyer
    // deferred deep link stays pending regardless; the backend decides
    // whether it binds.
    // A review-access code entry (App Review from a blocked region) would
    // need this step reachable in review mode.
    if (!referrerCodeStepAllowed()) {
      skipReferrerCodeStep(context);
      return;
    }
    // Show the referrer-code screen. It self-selects its mode: when the
    // install already carries a referrer from an AppsFlyer deferred deep link
    // (user installed via a friend's OneLink) it shows a "<CODE> recommended
    // you" confirmation (one tap to accept); otherwise it prompts for manual
    // entry. The screen fires onboardingCompleted itself on its way to /home.
    context.go('/referrer_code');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: c.background,
      body: Container(
        decoration: AppDecorations.screenGradient(context),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 24.h),

                // Header
                Center(
                  child: SvgPicture.asset(
                    kuteDogAsset(context),
                    width: 48.sp,
                    height: 48.sp,
                  ),
                ),
                SizedBox(height: 24.h),
                Center(
                  child: Text(
                    l10n.betaSurveyTitle,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 22.sp,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                SizedBox(height: 6.h),
                Center(
                  child: Text(
                    l10n.betaSurveySubtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: c.textSecondary,
                      fontSize: 15.sp,
                      height: 1.4,
                    ),
                  ),
                ),

                SizedBox(height: 32.h),

                // Gender
                Text(
                  l10n.betaSurveyGender,
                  style: TextStyle(
                    color: c.textTertiary,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                SizedBox(height: 10.h),
                Row(
                  children: [
                    _buildChip(c, 'male', l10n.betaSurveyMale, _gender, (v) => setState(() => _gender = v)),
                    SizedBox(width: 8.w),
                    _buildChip(c, 'female', l10n.betaSurveyFemale, _gender, (v) => setState(() => _gender = v)),
                  ],
                ),

                SizedBox(height: 24.h),

                // Age range
                Text(
                  l10n.betaSurveyAge,
                  style: TextStyle(
                    color: c.textTertiary,
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                SizedBox(height: 10.h),
                Row(
                  children: [
                    _buildChip(c, '18-24', '18–24', _ageRange, (v) => setState(() => _ageRange = v)),
                    SizedBox(width: 8.w),
                    _buildChip(c, '25-34', '25–34', _ageRange, (v) => setState(() => _ageRange = v)),
                    SizedBox(width: 8.w),
                    _buildChip(c, '35-44', '35–44', _ageRange, (v) => setState(() => _ageRange = v)),
                    SizedBox(width: 8.w),
                    _buildChip(c, '45+', '45+', _ageRange, (v) => setState(() => _ageRange = v)),
                  ],
                ),

                const Spacer(),

                // Continue button — routed through the shared AppButton
                // so the typography/text-color/animation match every other
                // full-bleed CTA in the app (previously hand-rolled with
                // hardcoded black text on accent, which diverged from the
                // global white-on-brand rule).
                AppButton(
                  text: l10n.betaSurveyContinue,
                  onPressed: _submit,
                ),

                SizedBox(height: 10.h),

                // Skip — bigger / clearer so users can find how to continue.
                Center(
                  child: GestureDetector(
                    onTap: _skip,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 14.h),
                      child: Text(
                        l10n.betaSurveySkip,
                        style: TextStyle(
                          color: c.textSecondary,
                          fontSize: 17.sp,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),

                SizedBox(height: 16.h),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChip(
    AppColorsExtension c,
    String value,
    String label,
    String? selected,
    ValueChanged<String> onTap,
  ) {
    final isSelected = selected == value;
    final isLight = Theme.of(context).brightness == Brightness.light;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap(value);
        },
        child: AnimatedContainer(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(vertical: 12.h),
          decoration: BoxDecoration(
            color: isSelected
                ? (isLight ? Colors.white : c.surface)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(
              color: isSelected ? c.border : c.borderSubtle,
              width: isLight ? 1.0 : 0.5,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? c.textPrimary : c.textSecondary,
                fontSize: 16.sp,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
