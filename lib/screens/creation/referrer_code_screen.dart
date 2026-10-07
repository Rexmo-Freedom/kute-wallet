import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import 'package:kute/helpers/kute_dog_asset.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/screens/shared/fee_copy.dart';
import 'package:kute/services/appsflyer_service.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/theme/app_theme.dart';

/// The capability the referral-code and share-code onboarding steps hang
/// off. Both are part of the affiliate promotion, which the runtime policy
/// withholds per country.
const affiliateProgramCapability = 'affiliate.program';

/// Whether the referral-code and share-code onboarding steps may show,
/// from the current policy snapshot. Fails closed: no policy, or a policy
/// that does not name the capability, hides the steps (a promotion the
/// user is not offered is not something they lose).
bool referrerCodeStepAllowed() =>
    RuntimeCapabilitiesService.instance.allows(affiliateProgramCapability);

/// Skip the referral-code step (and the share-code step with it) and land
/// on Home as if the user had passed through. Ends the onboarding funnel
/// exactly as the screen's own continue does, and reports the skip through the existing skip event so the funnel keeps
/// one exit per user. Never touches a referrer captured from an AppsFlyer
/// deferred deep link: that stays pending and the backend decides.
void skipReferrerCodeStep(BuildContext context) {
  TrackingService.track('onboarding_referrer_skipped', params: {
    'had_input': false,
    'attempts': 0,
    'captured_dropped': false,
    'reason': 'blocked',
    'capability': affiliateProgramCapability,
  });
  TrackingService.onboardingCompletedOnce();
  TrackingService.clearFlowContext('onboarding');
  context.go('/home');
}

/// ReferrerCodeScreen — final input step of the onboarding flow.
///
/// Comes right after the beta survey screen. Has two modes:
///
///   • Confirmation — the install already carries a referrer code from an
///     AppsFlyer deferred deep link (the user installed via a friend's
///     OneLink). We pre-fill it and just ask the user to confirm
///     ("<CODE> recommended you" → Continue), with a subtle escape hatch
///     for a mis-captured code.
///   • Manual entry — no code was captured, so we ask whether a friend
///     invited them and let them type a code.
///
/// Either way, an accepted code is persisted as the pending referrer; the
/// wallet's first AffiliateService.authWallet call (fired from the Earn tab
/// on first open) forwards it to the backend as `referred_by_code`.
///
/// Optional. Skip lands the user straight at the share-code step with no
/// referrer binding. The Earn tab still shows the 7-day "Got a friend's
/// code?" late-entry prompt for users who want to add a code after install.
///
/// Only where the runtime policy allows `affiliate.program`
/// ([referrerCodeStepAllowed]): the survey skips this step when the
/// promotion is withheld, and the screen skips itself if it is still
/// reached (deep link). A captured deep-link referrer is left pending.
class ReferrerCodeScreen extends ConsumerStatefulWidget {
  const ReferrerCodeScreen({super.key});

  @override
  ConsumerState<ReferrerCodeScreen> createState() => _ReferrerCodeScreenState();
}

class _ReferrerCodeScreenState extends ConsumerState<ReferrerCodeScreen> {
  final _ctrl = TextEditingController();
  bool _submitting = false;
  String? _error; // typed error shown below the field
  String? _tierLevel; // populated after a successful check, used in the
                     // confirmation toast ("Silver partner invite ✓")

  /// Non-null => confirmation mode: a referrer code was captured from the
  /// AppsFlyer deferred deep link, so we confirm rather than ask. Cleared
  /// (→ manual entry) if the user says it isn't theirs or the backend can't
  /// find it.
  String? _capturedCode;

  // Analytics only (never the code): manual Apply attempts on this screen,
  // the last validation failure, and whether a captured code was dropped
  // back to manual entry.
  int _attempts = 0;
  String? _lastError;
  bool _capturedDropped = false;

  /// The referee discount shown in the copy, refreshed from the public
  /// program terms so the screen reads whatever the backend applies. Null
  /// until the backend has said; the copy then names no discount.
  int? _discountPct = AffiliateService.refereeDiscountPct;

  /// [_discountPct] as copy, or null when there is none to quote.
  String? get _discountText {
    final pct = _discountPct;
    return pct == null || pct <= 0 ? null : discountShareText(pct);
  }

  /// Set when the step was opened while the policy withholds the affiliate
  /// programme (a deep link, or a policy change between the survey and
  /// here): nothing is shown or tracked, and the first frame moves on.
  bool _blocked = false;

  @override
  void initState() {
    super.initState();
    if (!referrerCodeStepAllowed()) {
      _blocked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) skipReferrerCodeStep(context);
      });
      return;
    }
    AffiliateService.programRefereeDiscountPct().then((pct) {
      if (mounted && pct != _discountPct) setState(() => _discountPct = pct);
    });
    final captured = AppsFlyerService.capturedReferrer;
    final hasCaptured = captured != null && captured.isNotEmpty;
    // Once per mount: which of the two modes the user landed on.
    TrackingService.track('onboarding_referrer_shown',
        params: {'mode': hasCaptured ? 'confirm' : 'manual'});
    if (hasCaptured) {
      _capturedCode = captured;
      _ctrl.text = captured;
      TrackingService.track('onboarding_referrer_prefilled');
      // Best-effort: enrich the confirmation with the partner tier, and drop
      // a definitively-bad capture back to manual entry. Never blocks the OK
      // tap — a flaky check (exists == null) leaves confirmation intact since
      // the code still auto-binds server-side via authWallet.
      _verifyCaptured(captured);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Capitalize a tier string for display without ever throwing. The naked
  /// `s[0].toUpperCase() + s.substring(1)` idiom this replaces RangeError-ed
  /// on an empty backend tier_level once and red-screened onboarding (fix
  /// f82ef3b6). Centralized so the crash can't be reintroduced by a copy-paste
  /// at either call site; returns '' for null/empty/whitespace input.
  static String _capitalize(String? s) {
    final t = (s ?? '').trim();
    if (t.isEmpty) return '';
    return '${t[0].toUpperCase()}${t.substring(1)}';
  }

  Future<void> _verifyCaptured(String code) async {
    final check = await AffiliateService.checkCode(code);
    if (!mounted || _capturedCode != code) return;
    if (check.exists == false) {
      TrackingService.affiliateReferrerCodeValidationFailed(
          reason: 'captured_invalid');
      // Stale / malformed invite link — don't confirm a dead code. Drop it
      // (in-memory AND the durable copy the AppsFlyer callback persisted, so
      // authWallet won't re-bind it) and fall back to manual entry.
      AppsFlyerService.clearCapturedReferrer();
      await AffiliateService.clearPendingReferrer();
      if (!mounted) return;
      _capturedDropped = true;
      _lastError = 'captured_invalid';
      setState(() {
        _capturedCode = null;
        _ctrl.clear();
        _error = context.l10n.referrerCaptureInvalid;
      });
    } else if (check.exists == true) {
      setState(() => _tierLevel = check.tierLevel);
    }
    // exists == null → keep confirmation; network hiccup shouldn't block. The
    // code still auto-binds server-side via authWallet.
  }

  /// Confirmation-mode OK: bind the captured code and continue.
  Future<void> _confirmCaptured() async {
    final code = _capturedCode;
    if (code == null || _submitting) return;
    setState(() => _submitting = true);
    HapticFeedback.mediumImpact();
    // Persist durably — belt-and-braces alongside the auto-bind from
    // AppsFlyerService.capturedReferrer, so the referrer sticks even if the
    // SDK's own durable write didn't land.
    await AffiliateService.setPendingReferrer(code);
    TrackingService.track('onboarding_referrer_confirmed', params: {
      'tier_level': _tierLevel ?? 'unknown',
    });
    if (!mounted) return;
    _continueOnboarding();
  }

  Future<void> _apply() async {
    final raw = _ctrl.text.trim().toUpperCase();
    if (raw.length < 4 || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
      _tierLevel = null;
    });
    HapticFeedback.mediumImpact();
    _attempts++;
    TrackingService.track('onboarding_referrer_submitted',
        params: {'attempt': _attempts});

    // Validate against the backend BEFORE persisting. Catches typos at
    // entry time instead of failing silently on first authWallet.
    final check = await AffiliateService.checkCode(raw);
    if (!mounted) return;

    if (check.exists == false) {
      TrackingService.affiliateReferrerCodeValidationFailed(
          reason: 'not_found');
      _lastError = 'not_found';
      setState(() {
        _submitting = false;
        _error = context.l10n.referrerCodeNotFound;
      });
      return;
    }
    if (check.exists == null) {
      TrackingService.affiliateReferrerCodeValidationFailed(reason: 'network');
      _lastError = 'network';
      setState(() {
        _submitting = false;
        _error = context.l10n.referrerCodeNetwork;
      });
      return;
    }

    // Valid. Persist + continue.
    await AffiliateService.setPendingReferrer(raw);
    // referrer_code_validated is the single event for a manual entry that
    // passed (onboarding_referrer_entered duplicated it on the same tap).
    TrackingService.referrerCodeValidated(tierLevel: check.tierLevel);
    if (!mounted) return;
    setState(() => _tierLevel = check.tierLevel);
    // Brief confirmation flash, then continue. Gives the user a
    // moment to see "Bronze partner invite ✓" before navigating.
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    _continueOnboarding();
  }

  void _skip() {
    HapticFeedback.lightImpact();
    // What the user had done before skipping, so a skip after a failed
    // code reads apart from a skip by someone with no code.
    TrackingService.track('onboarding_referrer_skipped', params: {
      'had_input': _ctrl.text.trim().isNotEmpty,
      'attempts': _attempts,
      if (_lastError != null) 'last_error_category': _lastError!,
      'captured_dropped': _capturedDropped,
    });
    _continueOnboarding();
  }

  void _continueOnboarding() {
    // Straight to the main screen (user decision: don't show the
    // share-your-code step at entry). The affiliate code still mints in
    // the background — BackgroundSyncService kicks
    // AffiliateService.startBackgroundRegistration independent of any
    // UI — and surfaces later in the referral dashboard. The /share_code
    // route stays wired for reuse. onboardingCompleted moved here from
    // ShareCodeScreen._finish so the funnel end still fires exactly once.
    TrackingService.onboardingCompletedOnce();
    TrackingService.clearFlowContext('onboarding');
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Scaffold(
      backgroundColor: c.background,
      body: Container(
        decoration: AppDecorations.screenGradient(context),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.w),
            // Blocked: a blank frame while the post-frame skip lands, so no
            // code prompt is ever painted where the promotion is withheld.
            child: _blocked
                ? const SizedBox.shrink()
                : _capturedCode != null
                    ? _confirmBody(c)
                    : _manualBody(c),
          ),
        ),
      ),
    );
  }

  /// Confirmation mode — "<CODE> recommended you", one tap to accept.
  Widget _confirmBody(AppColorsExtension c) {
    final code = _capturedCode!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 24.h),

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
            context.l10n.referrerFriendInvitedYou,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 24.sp,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
        ),
        SizedBox(height: 10.h),
        Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12.w),
            child: Text(
              _discountText == null
                  ? context.l10n.walletsConfirmFriendInviteNoDiscount
                  : context.l10n.walletsConfirmFriendInvite(_discountText!),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 14.sp,
                height: 1.5,
              ),
            ),
          ),
        ),

        SizedBox(height: 28.h),

        // The captured code, shown as a read-only pill so the user can see
        // exactly what they're confirming. Constrained + FittedBox so a long
        // code (up to 32 chars) scales down instead of overflowing on narrow
        // screens rather than clipping.
        Center(
          child: Container(
            constraints: BoxConstraints(maxWidth: 320.w),
            padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 14.h),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: c.border, width: 1.0),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                code,
                maxLines: 1,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 22.sp,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 3,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ),

        if (_capitalize(_tierLevel).isNotEmpty) ...[
          SizedBox(height: 14.h),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_rounded, color: c.accent, size: 16.sp),
                SizedBox(width: 6.w),
                Text(
                  context.l10n.referrerPartnerInvite(_capitalize(_tierLevel)),
                  style: TextStyle(
                    color: c.accent,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],

        const Spacer(),

        AppButton(
          text: context.l10n.continueLabel,
          onPressed: _submitting ? null : _confirmCaptured,
          isLoading: _submitting,
        ),
        SizedBox(height: 20.h),
      ],
    );
  }

  /// Manual entry mode — ask whether a friend invited them.
  Widget _manualBody(AppColorsExtension c) {
    final canApply = _ctrl.text.trim().length >= 4 && !_submitting;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 24.h),

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
            context.l10n.referrerGotCode,
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 24.sp,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
        ),
        SizedBox(height: 8.h),
        Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12.w),
            child: Text(
              _discountText == null
                  ? context.l10n.walletsEnterFriendCodeDescriptionNoDiscount
                  : context.l10n
                      .walletsEnterFriendCodeDescription(_discountText!),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 14.sp,
                height: 1.5,
              ),
            ),
          ),
        ),

        SizedBox(height: 36.h),

        Text(
          'INVITE CODE',
          style: TextStyle(
            color: c.textTertiary,
            fontSize: 13.sp,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        SizedBox(height: 10.h),
        TextField(
          controller: _ctrl,
          textCapitalization: TextCapitalization.characters,
          textAlign: TextAlign.center,
          enabled: !_submitting,
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 22.sp,
            fontWeight: FontWeight.w800,
            letterSpacing: 3,
            fontFamily: 'monospace',
          ),
          decoration: InputDecoration(
            hintText: 'CODE',
            hintStyle: TextStyle(color: c.textTertiary, letterSpacing: 3),
            filled: true,
            fillColor: c.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.r),
              borderSide: BorderSide.none,
            ),
            contentPadding: EdgeInsets.symmetric(vertical: 16.h),
          ),
          onChanged: (_) => setState(() {
            _error = null;
            _tierLevel = null;
          }),
          onSubmitted: (_) => canApply ? _apply() : null,
        ),
        SizedBox(height: 10.h),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Colors.redAccent, fontSize: 13.sp, height: 1.4),
          )
        else if (_tierLevel != null)
          Row(children: [
            Icon(Icons.check_circle_rounded, color: c.accent, size: 16.sp),
            SizedBox(width: 6.w),
            Text(
              _capitalize(_tierLevel).isEmpty
                  ? context.l10n.referrerCodeAdded
                  : context.l10n.referrerPartnerInvite(_capitalize(_tierLevel)),
              style: TextStyle(color: c.accent, fontSize: 13.sp, fontWeight: FontWeight.w700),
            ),
          ])
        else
          Text(
            context.l10n.referrerAddLater,
            style: TextStyle(color: c.textTertiary, fontSize: 13.sp, height: 1.4),
          ),

        const Spacer(),

        // Apply — routed through AppButton for the same shape /
        // typography / haptic story as every other primary CTA.
        AppButton(
          text: context.l10n.accountApplyCode,
          onPressed: canApply ? _apply : null,
          isLoading: _submitting,
        ),
        SizedBox(height: 10.h),
        // Skip — kept prominent so users without a code can clearly
        // see how to continue (was a faint 14sp tertiary line that
        // people missed).
        Center(
          child: GestureDetector(
            onTap: _submitting ? null : _skip,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding:
                  EdgeInsets.symmetric(vertical: 14.h, horizontal: 24.w),
              child: Text(
                context.l10n.referrerSkip,
                style: TextStyle(
                  color: c.textSecondary,
                  fontSize: 17.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
        SizedBox(height: 20.h),
      ],
    );
  }
}
