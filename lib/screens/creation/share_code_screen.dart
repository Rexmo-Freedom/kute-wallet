import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import 'package:kute/screens/shared/kute_dog_rig.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/fee_copy.dart';
import 'package:kute/providers/breez_config_provider.dart';
import 'package:kute/providers/breez_provider.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/screens/shared/qr_code.dart';
import 'package:kute/screens/creation/referrer_code_screen.dart'
    show referrerCodeStepAllowed;
import 'package:kute/services/appsflyer_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/wallet_identity_service.dart';
import 'package:kute/theme/app_theme.dart';

/// ShareCodeScreen — final onboarding step.
///
/// Shows the user THEIR freshly-minted affiliate code (+ QR + share) with a
/// "share and earn" pitch, the close of the invite loop opened by the prior
/// "got a friend's code?" screen.
///
/// The code is minted by [AffiliateService.authWallet] once the wallet's LN
/// address is provisioned. The seed was created one screen earlier
/// (passkey_choice), so Breez boots and the address provisions in the
/// background while the user moves through the survey + referrer screens —
/// usually the code is ready by the time we land here. We still drive
/// authWallet and poll, showing a spinner until it lands. If minting is slow
/// (offline / cold backend) we let the user continue after a short wait — the
/// code is always available later from Settings → Earn.
///
/// Part of the affiliate promotion, so only where the runtime policy allows
/// `affiliate.program` ([referrerCodeStepAllowed]): opened while withheld
/// (deep link), it ends onboarding and moves on without painting a code.
class ShareCodeScreen extends ConsumerStatefulWidget {
  const ShareCodeScreen({super.key});

  @override
  ConsumerState<ShareCodeScreen> createState() => _ShareCodeScreenState();
}

enum _Phase { waiting, ready, timedOut }

class _ShareCodeScreenState extends ConsumerState<ShareCodeScreen> {
  _Phase _phase = _Phase.waiting;
  String? _code;
  String? _shareLink; // local OneLink first; upgraded to branded async
  final GlobalKey _qrKey = GlobalKey();

  Timer? _poll;
  int _waitedMs = 0;
  // Set once we kick the lazy LN-address registration so we don't re-fire it
  // every tick (which could race and create a duplicate address).
  bool _lnRequested = false;
  // Honour "wait until it's generated" but never trap the user: after this we
  // surface a Continue button (polling keeps running in case it lands later).
  static const _softTimeoutMs = 22000;
  // Hard stop so a permanently-failing mint doesn't poll forever.
  static const _hardStopMs = 90000;
  static const _tickMs = 1500;

  // Analytics only, never the code or the link.
  bool _readyTracked = false;
  bool _shared = false;
  bool _copied = false;

  /// The referee discount quoted in the share text and the top commission
  /// rate in the description, from the backend's public program terms.
  /// Null until the backend has said; the copy then leaves them out.
  int? _discountPct = AffiliateService.refereeDiscountPct;
  double? _topRatePct = AffiliateService.commissionTopRatePct;

  /// Opened while the policy withholds the affiliate programme: nothing is
  /// shown, minted or tracked, and the first frame moves on to Home.
  bool _blocked = false;

  @override
  void initState() {
    super.initState();
    if (!referrerCodeStepAllowed()) {
      _blocked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        TrackingService.onboardingCompletedOnce();
        TrackingService.clearFlowContext('onboarding');
        context.go('/home');
      });
      return;
    }
    TrackingService.track('onboarding_share_code_viewed');
    AffiliateService.programRefereeDiscountPct().then((pct) {
      if (!mounted) return;
      setState(() {
        _discountPct = pct;
        _topRatePct = AffiliateService.commissionTopRatePct;
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _bootstrap() {
    final existing = AffiliateService.affiliateCode;
    if (existing != null && existing.isNotEmpty) {
      _onReady(existing);
      return;
    }
    _tick();
    _poll = Timer.periodic(const Duration(milliseconds: _tickMs), (_) => _tick());
  }

  Future<void> _tick() async {
    if (!mounted) return;
    final cached = AffiliateService.affiliateCode;
    if (cached != null && cached.isNotEmpty) {
      _onReady(cached);
      return;
    }
    await _attemptMint();
    if (!mounted || _phase == _Phase.ready) return;
    final minted = AffiliateService.affiliateCode;
    if (minted != null && minted.isNotEmpty) {
      _onReady(minted);
      return;
    }
    _waitedMs += _tickMs;
    if (_waitedMs >= _softTimeoutMs && _phase == _Phase.waiting) {
      setState(() => _phase = _Phase.timedOut);
      // Once: the phase only leaves `waiting` once.
      TrackingService.track('onboarding_share_code_timed_out');
    }
    if (_waitedMs >= _hardStopMs) _poll?.cancel();
  }

  /// One mint attempt, mirroring the Earn screen's bootstrap: prime wallet
  /// identity from Breez, then authWallet with the @paykute address (which
  /// also binds the referrer the user just entered / AppsFlyer captured).
  /// Best-effort — failures just mean the next tick retries.
  Future<void> _attemptMint() async {
    try {
      if (!WalletIdentityService.isReady) {
        final wrapper = await ref.read(breezSDKProvider.future);
        final sdk = wrapper.instance;
        if (sdk != null) await WalletIdentityService.initFromBreez(sdk);
      }
      var addr = ref.read(lnAddressProvider).valueOrNull;
      if ((addr == null || addr.isEmpty) && !_lnRequested) {
        // The @paykute (LN) address registers lazily — historically only when
        // the user opened the Receive screen — so a fresh wallet had no
        // address for authWallet and onboarding hung here. Provision it once
        // now. Idempotent server-side (the webhook-registered check short-
        // circuits), so a later boot / Receive open won't create a second one.
        _lnRequested = true;
        try {
          final lnurl = await ref.read(setupLnAddressProvider.future);
          addr =
              lnurl.lightningAddress ?? ref.read(lnAddressProvider).valueOrNull;
        } catch (_) {
          _lnRequested = false; // allow a retry on a later tick
        }
      }
      if (addr != null && addr.isNotEmpty) {
        await AffiliateService.authWallet(paykuteAddress: addr);
      }
    } catch (_) {/* transient — retried on the next tick */}
  }

  Future<void> _onReady(String code) async {
    _poll?.cancel();
    if (!mounted) return;
    if (!_readyTracked) {
      _readyTracked = true;
      TrackingService.track('onboarding_share_code_ready', params: {
        'wait_bucket': _waitedMs == 0
            ? 'instant'
            : _waitedMs < 10000
                ? '<10s'
                : _waitedMs < 30000
                    ? '10-30s'
                    : '30s+',
        'after_timeout': _phase == _Phase.timedOut,
      });
    }
    setState(() {
      _code = code;
      _phase = _Phase.ready;
    });
    // Instant local OneLink (when a template is configured), then upgrade to
    // a branded short link if it resolves. No website fallback.
    final local = AppsFlyerService.shareLink(code);
    if (local != null && mounted) setState(() => _shareLink = local);
    final branded = await AppsFlyerService.brandedInviteLink(code);
    if (branded != null && branded.isNotEmpty && mounted) {
      setState(() => _shareLink = branded);
    }
  }

  void _finish() {
    HapticFeedback.lightImpact();
    TrackingService.track('onboarding_share_code_continued', params: {
      'state': _phase == _Phase.ready ? 'ready' : 'timed_out',
      'shared': _shared,
      'copied': _copied,
    });
    TrackingService.onboardingCompletedOnce();
    TrackingService.clearFlowContext('onboarding');
    if (mounted) context.go('/home');
  }

  String _shareText(String? link) {
    final pct = _discountPct;
    if (pct == null || pct <= 0) {
      return link != null
          ? context.l10n.walletsShareTextWithLinkNoDiscount(link)
          : context.l10n.walletsShareTextWithCodeNoDiscount(_code ?? '');
    }
    final discount = discountShareText(pct);
    return link != null
        ? context.l10n.walletsShareTextWithLink(link, discount)
        : context.l10n.walletsShareTextWithCode(_code ?? '', discount);
  }

  void _copyLink() {
    final link = _shareLink ??
        (_code != null && _code!.isNotEmpty
            ? AppsFlyerService.shareLink(_code!)
            : null);
    final toCopy = link ?? _code;
    if (toCopy == null || toCopy.isEmpty) return;
    Clipboard.setData(ClipboardData(text: toCopy));
    TrackingService.affiliateCodeCopied(surface: 'share_code');
    _copied = true;
    if (!mounted) return;
    showMessageSnackBar(
      context: context,
      message: link != null
          ? context.l10n.accountLinkCopied
          : context.l10n.accountCodeCopied,
      error: false,
      duration: const Duration(seconds: 1),
    );
  }

  Future<void> _share() async {
    final link = _shareLink ??
        (_code != null && _code!.isNotEmpty
            ? AppsFlyerService.shareLink(_code!)
            : null);
    TrackingService.affiliateShareOpened(method: 'onboarding');
    _shared = true;
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null
        ? (box.localToGlobal(ui.Offset.zero) & box.size)
        : (ui.Offset.zero & const ui.Size(1, 1));
    try {
      final r = await SharePlus.instance.share(ShareParams(
        text: _shareText(link),
        sharePositionOrigin: origin,
      ));
      TrackingService.affiliateCodeShared(
          method: 'sheet', result: r.status.name, surface: 'share_code');
    } catch (_) {
      TrackingService.affiliateCodeShared(
          method: 'sheet', result: 'error', surface: 'share_code');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (_blocked) return Scaffold(backgroundColor: c.background);
    return Scaffold(
      backgroundColor: c.background,
      body: Container(
        decoration: AppDecorations.screenGradient(context),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: 24.h),
                Center(
                  // "Invite friends, earn together" is good news and asks
                  // nobody to check a number, so Sal gets to be pleased
                  // about it instead of standing there.
                  child: KuteDogCheer(size: 48.sp),
                ),
                SizedBox(height: 24.h),
                Text(
                  context.l10n.shareCodeTitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 22.sp,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                SizedBox(height: 6.h),
                Text(
                  _topRatePct == null
                      ? context.l10n.walletsShareCodeEarnDescriptionNoRate
                      : context.l10n.walletsShareCodeEarnDescription(
                          commissionRateText(_topRatePct!)),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 15.sp,
                    height: 1.4,
                  ),
                ),
                SizedBox(height: 28.h),
                Expanded(child: _body(c)),
                AppButton(
                  text: context.l10n.shareCodeStartUsing,
                  onPressed:
                      _phase == _Phase.waiting ? null : _finish,
                ),
                SizedBox(height: 20.h),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(AppColorsExtension c) {
    return switch (_phase) {
      _Phase.ready => SingleChildScrollView(child: _codeCard(c)),
      // Skeleton mimicking the code card about to appear, with the
      // status label kept underneath.
      _Phase.waiting => SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Column(children: [
            KuteSkeleton(
              child: SkeletonCard(
                height: 140.h,
                radius: 16.r,
                child: Column(children: [
                  SkeletonBar(90.w, 12.h),
                  SizedBox(height: 12.h),
                  SkeletonBar(170.w, 30.h, radius: 8.r),
                  const Spacer(),
                  SkeletonBar(double.infinity, 14.h),
                ]),
              ),
            ),
            SizedBox(height: 16.h),
            Text(context.l10n.shareCodeSettingUp,
                style: TextStyle(color: c.textSecondary, fontSize: 14.sp)),
          ]),
        ),
      _Phase.timedOut => Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 8.w),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.bolt_rounded, color: c.accent, size: 40.sp),
              SizedBox(height: 14.h),
              Text(
                context.l10n.shareCodeTimedOut,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: c.textSecondary, fontSize: 14.sp, height: 1.4),
              ),
            ]),
          ),
        ),
    };
  }

  Widget _codeCard(AppColorsExtension c) {
    final code = _code ?? '';
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: c.border),
      ),
      child: Column(children: [
        Text('YOUR CODE',
            style: TextStyle(
                color: c.textSecondary,
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2)),
        SizedBox(height: 10.h),
        Text(code.isEmpty ? '------' : code,
            style: TextStyle(
                color: c.textPrimary,
                fontSize: 30.sp,
                fontWeight: FontWeight.w800,
                fontFamily: 'monospace',
                letterSpacing: 3)),
        SizedBox(height: 16.h),
        if (_shareLink != null)
          RepaintBoundary(
            key: _qrKey,
            child: Container(
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14.r),
              ),
              child: buildQrCode(_shareLink!, context),
            ),
          ),
        SizedBox(height: 16.h),
        Row(children: [
          Expanded(
            child: AppButton(
              text: context.l10n.accountCopyLink,
              compact: true,
              icon: Icons.link_rounded,
              onPressed: _copyLink,
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: AppButton(
              text: context.l10n.share,
              compact: true,
              icon: Icons.ios_share_rounded,
              onPressed: _share,
            ),
          ),
        ]),
      ]),
    );
  }
}
