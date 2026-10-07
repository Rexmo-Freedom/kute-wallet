import 'package:kute/services/runtime_capabilities_service.dart';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:kute/screens/shared/charts/kute_line_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:intl/intl.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/screens/shared/fee_copy.dart';
import 'package:kute/providers/breez_config_provider.dart';
import 'package:kute/providers/breez_provider.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/home/components/home_action_row.dart'
    show NeutralActionChip;
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/screens/shared/qr_code.dart';
import 'package:kute/services/appsflyer_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/wallet_identity_service.dart';
import 'package:kute/theme/app_theme.dart';

/// AffiliateScreen — the Earn screen (v2). Unified for everyone (no B2B/B2C
/// fork). Shows the user's code + share QR, a headline counter (users with
/// your code), earnings (pending + paid), a cumulative earnings graph, a
/// plain rules card, the payment history, an anonymized referee list, and a
/// late-entry "got a friend's code?" fallback. Where the runtime policy
/// withholds `affiliate.program` there is no way in (Settings row, search
/// entry and onboarding steps are all hidden); reached anyway, the code
/// card and the late-entry prompt are simply absent, with no unavailable
/// message, and the earnings record stays.
///
/// All numbers come from the backend `/me`, `/me/history`, `/me/referees`.
/// Code renames done in the admin board propagate here automatically (getMe
/// reconciles the cached code + re-identifies PostHog).
class AffiliateScreen extends ConsumerStatefulWidget {
  const AffiliateScreen({super.key});

  @override
  ConsumerState<AffiliateScreen> createState() => _AffiliateScreenState();
}

enum _Phase { loading, comingSoon, error, dashboard }

class _AffiliateScreenState extends ConsumerState<AffiliateScreen> {
  _Phase _phase = _Phase.loading;

  Map<String, dynamic>? _me;
  List<dynamic> _history = [];
  List<dynamic> _referees = [];
  int _windowDays = 30;
  String? _shareLink; // local OneLink first; upgraded to branded async
  bool _showReferees = false;
  final GlobalKey _qrKey = GlobalKey(); // captures the QR card as an image
  // Once per screen open: a retry re-runs _bootstrap without re-counting.
  bool _viewTracked = false;
  bool _shareLinkTracked = false;
  // Owned by the state so async rebuilds (branded link, pull-to-refresh,
  // referee toggle) never wipe a half-typed friend code.
  final TextEditingController _codeCtrl = TextEditingController();
  // A retry re-runs _bootstrap; its outcome is reported once.
  bool _retrying = false;
  bool _dashboardTracked = false;

  // Late-entry ("got a friend's code?") flow: started on the first typed
  // character, abandoned on leaving without a bound code. Never the code.
  bool _lateEntryStarted = false;
  bool _lateEntryDone = false;
  bool _lateEntrySubmitting = false;
  int _lateEntryAttempts = 0;
  String? _lateEntryLastResult;
  final Stopwatch _lateEntryWatch = Stopwatch();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    if (_lateEntryStarted && !_lateEntryDone) {
      TrackingService.track('affiliate_late_entry_abandoned', params: {
        'step': _lateEntryAttempts > 0 ? 'submitted' : 'code_entry',
        'attempts': _lateEntryAttempts,
        'time_in_flow_bucket': _flowTimeBucket(_lateEntryWatch.elapsed),
        if (_lateEntryLastResult != null)
          'last_error_category': _lateEntryLastResult!,
        'reason': 'user_closed',
      });
      TrackingService.clearFlowContext('affiliate_late_entry');
    }
    _codeCtrl.dispose();
    super.dispose();
  }

  static String _flowTimeBucket(Duration d) => d.inSeconds < 10
      ? '<10s'
      : d.inSeconds < 30
          ? '10-30s'
          : d.inSeconds < 120
              ? '30s-2m'
              : d.inMinutes < 10
                  ? '2-10m'
                  : '10m+';

  void _startLateEntry() {
    if (_lateEntryStarted) return;
    _lateEntryStarted = true;
    _lateEntryWatch.start();
    TrackingService.track('affiliate_late_entry_started',
        params: {'entry_source': 'earn'});
    TrackingService.setFlowContext(
        flow: 'affiliate_late_entry', step: 'code_entry');
  }

  String get _code =>
      (_me?['affiliate_code'] as String?) ?? AffiliateService.affiliateCode ?? '';

  Future<void> _bootstrap() async {
    // Ensure a session: prime wallet identity then auth with the @paykute addr.
    if (AffiliateService.sessionToken == null) {
      try {
        if (!WalletIdentityService.isReady) {
          final wrapper = await ref.read(breezSDKProvider.future);
          final sdk = wrapper.instance;
          if (sdk != null) await WalletIdentityService.initFromBreez(sdk);
        }
        final addr = ref.read(lnAddressProvider).valueOrNull;
        if (addr != null && addr.isNotEmpty) {
          await AffiliateService.authWallet(paykuteAddress: addr);
        }
      } catch (_) {/* fall through to whatever cached state we have */}
    }
    final live = await AffiliateService.isProgramLive();
    await _refresh();
    if (!mounted) return;
    final ok = _me != null;
    if (!ok && !live) {
      setState(() => _phase = _Phase.comingSoon);
      _trackView('coming_soon');
      _trackRetryResult('coming_soon');
      return;
    }
    setState(() => _phase = ok ? _Phase.dashboard : _Phase.error);
    _trackView(ok ? 'dashboard' : 'error');
    _trackRetryResult(ok ? 'dashboard' : 'error');
    if (ok) _trackDashboardState();
    // Instant local OneLink (when a template is configured), then try to
    // upgrade to a branded short link. No website fallback — if neither
    // resolves, the QR/share simply doesn't render.
    if (ok && _code.isNotEmpty) {
      final local = AppsFlyerService.shareLink(_code);
      if (local != null) setState(() => _shareLink = local);
      final branded = await AppsFlyerService.brandedInviteLink(_code);
      final hasBranded = branded != null && branded.isNotEmpty;
      if (mounted && hasBranded) setState(() => _shareLink = branded);
      // One event per screen open, naming the link the QR/share settled on.
      if (mounted && !_shareLinkTracked && (hasBranded || local != null)) {
        _shareLinkTracked = true;
        TrackingService.affiliateShareLinkGenerated(
            linkType: hasBranded ? 'branded' : 'local');
      }
    }
  }

  void _trackView(String state) {
    if (_viewTracked) return;
    _viewTracked = true;
    TrackingService.affiliateEarnViewed(state: state);
  }

  void _trackRetryResult(String state) {
    if (!_retrying) return;
    _retrying = false;
    TrackingService.track('affiliate_earn_retry_result',
        params: {'state': state});
  }

  /// What the dashboard showed, once per open: booleans and a coarse
  /// referee count only — never the owed / paid amounts or the code.
  void _trackDashboardState() {
    if (_dashboardTracked) return;
    _dashboardTracked = true;
    final bound = _i(_me?['referees_bound']);
    final payments = (_me?['payments'] as List<dynamic>?) ?? const [];
    final participation = ref
        .read(runtimeCapabilitiesProvider)
        .allows('affiliate.program');
    final isReferred = _me?['is_referred'] == true;
    TrackingService.track('affiliate_dashboard_loaded', params: {
      'has_code': _code.isNotEmpty,
      'has_pending_payout': _d(_me?['accrued_usd']) > 0,
      'has_paid_out': _d(_me?['paid_usd']) > 0,
      'has_payments': payments.isNotEmpty,
      'has_history': _history.isNotEmpty,
      'referees_bucket': bound == 0
          ? '0'
          : bound < 5
              ? '1-4'
              : bound < 20
                  ? '5-19'
                  : bound < 50
                      ? '20-49'
                      : bound < 100
                          ? '50-99'
                          : '100+',
      'is_referred': isReferred,
      'participation_allowed': participation,
      'late_entry_shown': participation && !isReferred,
    });
  }

  Future<void> _refresh() async {
    final results = await Future.wait([
      AffiliateService.getMe(),
      AffiliateService.getHistory(days: _windowDays),
      AffiliateService.getReferees(limit: 100),
    ]);
    if (!mounted) return;
    setState(() {
      _me = results[0] as Map<String, dynamic>? ?? _me;
      _history = (results[1] as List<dynamic>?) ?? _history;
      _referees = (results[2] as List<dynamic>?) ?? _referees;
    });
  }

  Future<void> _reloadHistory(int days) async {
    // Only a real change counts; re-tapping the selected chip still reloads.
    if (days != _windowDays) {
      TrackingService.affiliateHistoryWindowChanged(days: days);
    }
    setState(() => _windowDays = days);
    final h = await AffiliateService.getHistory(days: days);
    if (mounted && h != null) setState(() => _history = h);
  }

  // ── number helpers ──
  double _d(dynamic v) => v is num ? v.toDouble() : 0;
  int _i(dynamic v) => v is num ? v.toInt() : 0;

  /// The referee discount as copy ("40%", a share of the Kute fee), from
  /// the dashboard payload when it has answered, otherwise the figure the
  /// backend gave elsewhere this run. Null when there is none to quote.
  String? get _discount {
    final fromMe = _me?['referee_discount_pct'];
    final pct = fromMe is num && fromMe >= 0
        ? fromMe.toInt()
        : AffiliateService.refereeDiscountPct;
    return pct == null || pct <= 0 ? null : discountShareText(pct);
  }

  /// The commission ladder as one sentence, formatted from the backend's
  /// program rules in the dashboard payload (`rules.base_rate_pct` and
  /// `rules.tiers`). Null until the payload has answered.
  String? get _earningsRule {
    final rules = _me?['rules'];
    if (rules is! Map) return null;
    final base = rules['base_rate_pct'];
    if (base is! num || !base.isFinite || base <= 0) return null;
    final steps = <String>[];
    final tiers = rules['tiers'];
    if (tiers is List) {
      for (final tier in tiers) {
        if (tier is! Map) continue;
        final rate = tier['rate_pct'];
        final count = tier['activated_referees'];
        if (rate is num && rate.isFinite && rate > 0 && count is num) {
          steps.add(context.l10n
              .accountRuleEarningsStep(commissionRateText(rate), count.toInt()));
        }
      }
    }
    final rate = commissionRateText(base);
    return steps.isEmpty
        ? context.l10n.accountRuleEarnings(rate)
        : context.l10n.accountRuleEarningsLadder(rate, steps.join(', '));
  }
  String _usd(num v) => '\$${v.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        centerTitle: true,
        elevation: 0,
        // Merge: nav's shared KuteBackButton + main's l10n title.
        leading: const KuteBackButton(),
        title: Text(context.l10n.accountEarn,
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 20.sp,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            )),
      ),
      body: switch (_phase) {
        // Skeleton mimicking the dashboard: header stat card + rows.
        _Phase.loading => SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 0),
            child: Column(children: [
              KuteSkeleton(
                child: SkeletonCard(
                  height: 120.h,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBar(120.w, 12.h),
                      SizedBox(height: 10.h),
                      SkeletonBar(160.w, 28.h, radius: 8.r),
                      const Spacer(),
                      SkeletonBar(90.w, 12.h),
                    ],
                  ),
                ),
              ),
              const SkeletonRowList(count: 3),
            ]),
          ),
        _Phase.comingSoon => _buildComingSoon(c),
        _Phase.error => _buildError(c),
        _Phase.dashboard => RefreshIndicator(
            onRefresh: () {
              TrackingService.pullToRefreshExecuted(screen: 'affiliate');
              return _refresh();
            },
            color: c.textPrimary,
            child: _buildDashboard(c),
          ),
      },
    );
  }

  Widget _buildComingSoon(AppColorsExtension c) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32.w),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.bolt_rounded, color: c.textSecondary, size: 48.sp),
          SizedBox(height: 16.h),
          Text(context.l10n.comingSoon2,
              style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 22.sp,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5)),
          SizedBox(height: 8.h),
          Text(
            context.l10n.accountInviteFriendsEarnShare,
            textAlign: TextAlign.center,
            style: TextStyle(color: c.textSecondary, fontSize: 15.sp, height: 1.4),
          ),
        ]),
      ),
    );
  }

  Widget _buildError(AppColorsExtension c) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32.w),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.wifi_off_rounded, color: c.textSecondary, size: 44.sp),
          SizedBox(height: 16.h),
          Text(context.l10n.accountCouldntLoadEarnData,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 17.sp,
                  fontWeight: FontWeight.w600)),
          SizedBox(height: 16.h),
          AppButton(
            text: context.l10n.accountTryAgain,
            compact: true,
            onPressed: () {
              TrackingService.track('affiliate_earn_retry_tapped');
              _retrying = true;
              setState(() => _phase = _Phase.loading);
              _bootstrap();
            },
          ),
        ]),
      ),
    );
  }

  Widget _buildDashboard(AppColorsExtension c) {
    final policy = ref.watch(runtimeCapabilitiesProvider);
    // Where the affiliate programme is withheld, the code card and the
    // late-entry "got a friend's code?" prompt are hidden outright (no
    // disabled card, no unavailable message): neither the promotion nor a
    // way into it is offered where the policy (or its absence: it fails
    // closed) says no. Earned balances, history and payouts stay, on their
    // own backend rules.
    final participationAllowed = policy.allows('affiliate.program');
    final rate = _d(_me?['commission_rate_pct']);
    final bound = _i(_me?['referees_bound']);
    final accrued = _d(_me?['accrued_usd']);
    final paid = _d(_me?['paid_usd']);
    final isReferred = _me?['is_referred'] == true;
    final payments = (_me?['payments'] as List<dynamic>?) ?? const [];

    return ListView(
      // Clear the Android gesture nav / iOS home indicator — the Scaffold
      // body isn't SafeArea-wrapped, so without this the last card sits
      // under the system navigation bar.
      padding: EdgeInsets.fromLTRB(
          16.w, 8.h, 16.w, 32.h + MediaQuery.of(context).padding.bottom),
      children: [
        if (participationAllowed) ...[
          _codeCard(c),
          SizedBox(height: 16.h),
        ],
        _countersRow(c, bound),
        SizedBox(height: 16.h),
        _earningsCard(c, accrued, paid, rate, bound),
        SizedBox(height: 16.h),
        if (_history.isNotEmpty) ...[
          _graphCard(c),
          SizedBox(height: 16.h),
        ],
        if (_earningsRule != null || _discount != null) ...[
          _rulesCard(c),
          SizedBox(height: 16.h),
        ],
        if (payments.isNotEmpty) ...[
          _paymentsCard(c, payments),
          SizedBox(height: 16.h),
        ],
        if (bound > 0) ...[
          _refereesCard(c, bound),
          SizedBox(height: 16.h),
        ],
        if (participationAllowed && !isReferred) _lateEntryCard(c),
      ],
    );
  }

  // ── Code + share + QR ──
  Widget _codeCard(AppColorsExtension c) {
    return _card(
      c,
      child: Column(children: [
        Text(context.l10n.accountYourCode,
            style: TextStyle(
                color: c.textSecondary,
                fontSize: 13.sp,
                fontWeight: FontWeight.w500)),
        SizedBox(height: 10.h),
        Text(_code.isEmpty ? '------' : _code,
            style: TextStyle(
                color: c.textPrimary,
                fontSize: 30.sp,
                fontWeight: FontWeight.w800,
                fontFamily: 'monospace',
                letterSpacing: 3)),
        SizedBox(height: 16.h),
        if (_shareLink != null)
          GestureDetector(
            onTap: () => _shareImage(trigger: 'qr'),
            child: RepaintBoundary(
              key: _qrKey,
              // buildQrCode paints its own white ground and quiet zone;
              // only the corner clip lives here.
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                child: buildQrCode(_shareLink!, context),
              ),
            ),
          ),
        SizedBox(height: 16.h),
        // Neutral chips (user decision: the blue AppButtons clashed with
        // the app chrome — same language as the Deposit/Withdraw chips).
        Row(children: [
          Expanded(
            child: NeutralActionChip(
              icon: Icons.link_rounded,
              label: context.l10n.accountCopyLink,
              onTap: _copyLink,
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: NeutralActionChip(
              icon: Icons.ios_share_rounded,
              label: context.l10n.share,
              onTap: () => _shareImage(trigger: 'button'),
            ),
          ),
        ]),
      ]),
    );
  }

  void _copyLink() {
    // Prefer the OneLink (branded if it resolved, else the local long form);
    // fall back to the bare code so the button never silently no-ops if the
    // template is missing in .env or shareLink() returns null.
    final link =
        _shareLink ?? (_code.isNotEmpty ? AppsFlyerService.shareLink(_code) : null);
    final toCopy = link ?? _code;
    if (toCopy.isEmpty) return;
    Clipboard.setData(ClipboardData(text: toCopy));
    TrackingService.affiliateCodeCopied(surface: 'earn');
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

  String _shareText(String? link) {
    final discount = _discount;
    if (discount == null) {
      return link != null
          ? context.l10n.walletsShareTextWithLinkNoDiscount(link)
          : context.l10n.walletsShareTextWithCodeNoDiscount(_code);
    }
    return link != null
        ? context.l10n.accountShareTextWithLink(link, discount)
        : context.l10n.accountShareTextWithCode(_code, discount);
  }

  /// [method] is the share the user chose: 'sheet', or 'image' when the QR
  /// image share fell back to this text share.
  Future<void> _openShare({String method = 'sheet', String? trigger}) async {
    final link =
        _shareLink ?? (_code.isNotEmpty ? AppsFlyerService.shareLink(_code) : null);
    if (link == null) return;
    _trackShareOpened(method, trigger);
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
          method: method, result: r.status.name, surface: 'earn');
    } catch (_) {
      // User dismissed / platform error: the share never opened.
      TrackingService.affiliateCodeShared(
          method: method, result: 'error', surface: 'earn');
    }
  }

  /// `affiliate_share_opened` with what the user tapped ([trigger]: qr |
  /// button), so the QR tap and the Share chip read apart.
  void _trackShareOpened(String method, String? trigger) =>
      TrackingService.track('affiliate_share_opened', params: {
        'method': method,
        if (trigger != null) 'trigger': trigger,
      });

  /// Shares the QR card as a PNG image alongside the invite text, so a
  /// friend can scan it directly. Falls back to a plain link/text share if
  /// the QR hasn't rendered yet or the capture fails.
  Future<void> _shareImage({String? trigger}) async {
    final boundary =
        _qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return _openShare(method: 'image', trigger: trigger);
    final link =
        _shareLink ?? (_code.isNotEmpty ? AppsFlyerService.shareLink(_code) : null);

    XFile? file;
    try {
      final image = await boundary.toImage(pixelRatio: 3.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data != null) {
        final dir = await getTemporaryDirectory();
        final out = File('${dir.path}/kute_referral.png');
        await out.writeAsBytes(data.buffer.asUint8List());
        file = XFile(out.path, mimeType: 'image/png');
      }
    } catch (_) {/* capture failed → fall through to a link-only share */}
    if (file == null) return _openShare(method: 'image', trigger: trigger);
    if (!mounted) return;

    _trackShareOpened('image', trigger);
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null
        ? (box.localToGlobal(ui.Offset.zero) & box.size)
        : (ui.Offset.zero & const ui.Size(1, 1));
    try {
      final r = await SharePlus.instance.share(ShareParams(
        files: [file],
        text: _shareText(link),
        sharePositionOrigin: origin,
      ));
      TrackingService.affiliateCodeShared(
          method: 'image', result: r.status.name, surface: 'earn');
    } catch (_) {
      TrackingService.affiliateCodeShared(
          method: 'image', result: 'error', surface: 'earn');
    }
  }

  // ── Headline counter ──
  Widget _countersRow(AppColorsExtension c, int bound) {
    // Neutral number (user decision: the blue headline read off-brand —
    // stats are textPrimary everywhere else in the app).
    return _counter(
        c, bound.toString(), context.l10n.accountUsersWithYourCode);
  }

  Widget _counter(AppColorsExtension c, String value, String label) {
    return _card(
      c,
      padding: EdgeInsets.symmetric(vertical: 18.h, horizontal: 12.w),
      child: Column(children: [
        Text(value,
            style: TextStyle(
                color: c.textPrimary,
                fontSize: 30.sp,
                fontWeight: FontWeight.w800)),
        SizedBox(height: 4.h),
        Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: c.textSecondary, fontSize: 13.sp, fontWeight: FontWeight.w500)),
      ]),
    );
  }

  // ── Earnings ──
  Widget _earningsCard(
      AppColorsExtension c, double accrued, double paid, double rate, int friends) {
    final nextTier = friends < 50 ? 50 : (friends < 100 ? 100 : null);
    final nextRate = friends < 50 ? 10 : (friends < 100 ? 20 : null);
    return _card(
      c,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: _stat(c, context.l10n.accountPendingPayout, _usd(accrued),
                  big: true)),
          Expanded(
              child: _stat(c, context.l10n.accountPaidToDate, _usd(paid))),
        ]),
        SizedBox(height: 14.h),
        Row(children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
            decoration: BoxDecoration(
              color: c.surfaceLight,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: c.borderSubtle, width: 0.5),
            ),
            child: Text(
                context.l10n.accountYouEarnRate(rate.toStringAsFixed(
                    rate.truncateToDouble() == rate ? 0 : 1)),
                style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w700)),
          ),
          SizedBox(width: 10.w),
          if (nextTier != null)
            Expanded(
              child: Text(
                  context.l10n.accountInviteMoreForRate(
                      nextTier - friends, nextRate ?? 0),
                  style: TextStyle(color: c.textSecondary, fontSize: 13.sp)),
            ),
        ]),
      ]),
    );
  }

  Widget _stat(AppColorsExtension c, String label, String value, {bool big = false}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(color: c.textSecondary, fontSize: 13.sp)),
      SizedBox(height: 4.h),
      Text(value,
          style: TextStyle(
              color: c.textPrimary,
              fontSize: big ? 26.sp : 18.sp,
              fontWeight: FontWeight.w800)),
    ]);
  }

  // ── Graph ──
  Widget _graphCard(AppColorsExtension c) {
    final values = <double>[];
    for (var i = 0; i < _history.length; i++) {
      final p = _history[i] as Map<String, dynamic>;
      values.add(_d(p['cumulative_usd']));
    }
    return _card(
      c,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(context.l10n.accountEarnings,
              style: TextStyle(
                  color: c.textPrimary, fontSize: 16.sp, fontWeight: FontWeight.w700)),
          Row(children: [
            for (final d in [7, 30, 90]) _windowChip(c, d),
          ]),
        ]),
        SizedBox(height: 14.h),
        SizedBox(
          height: 120.h,
          child: values.length < 2
              ? Center(
                  child: Text(context.l10n.accountNotEnoughDataYet,
                      style: TextStyle(color: c.textSecondary, fontSize: 13.sp)))
              // Shared chart engine: monotone cubic curve, the standard
              // 0.14 gradient fill and endpoint dot, plus the ~280ms
              // series morph when the 7/30/90d window flips. Non-
              // interactive — the stat tiles above carry the values.
              : KuteLineChart(
                  values: values,
                  lineColor: AppColors.marketUp,
                ),
        ),
      ]),
    );
  }

  Widget _windowChip(AppColorsExtension c, int days) {
    final selected = _windowDays == days;
    // Selection is the monochrome CTA fill (never the orange accent);
    // unselected chips sit on the neutral surface with a hairline.
    return GestureDetector(
      onTap: () => _reloadHistory(days),
      child: Container(
        margin: EdgeInsets.only(left: 6.w),
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
        decoration: BoxDecoration(
          color: selected ? context.ctaFill : c.surfaceLight,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: selected ? context.ctaFill : c.borderSubtle,
            width: 0.5,
          ),
        ),
        child: Text(context.l10n.accountDaysAbbrev(days),
            style: TextStyle(
                color: selected ? context.ctaOnColor : c.textSecondary,
                fontSize: 13.sp,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
      ),
    );
  }

  // ── Rules (super clear) ──
  Widget _rulesCard(AppColorsExtension c) {
    // Two rules only (user decision): the earnings ladder and the
    // friend discount. "Only new wallets count" and the payout
    // mechanics were dropped from the card.
    // Both figures are the backend's; a rule it has not stated yet is
    // left out rather than filled in.
    final earnings = _earningsRule;
    final discount = _discount;
    final rules = [
      if (earnings != null) earnings,
      if (discount != null) context.l10n.accountRuleFriendDiscount(discount),
    ];
    return _card(
      c,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(context.l10n.howItWorks2,
            style: TextStyle(
                color: c.textPrimary, fontSize: 16.sp, fontWeight: FontWeight.w700)),
        SizedBox(height: 12.h),
        for (final r in rules)
          Padding(
            padding: EdgeInsets.only(bottom: 10.h),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: EdgeInsets.only(top: 6.h, right: 10.w),
                child: Container(
                  width: 6.w,
                  height: 6.w,
                  decoration: BoxDecoration(
                      color: c.textTertiary, shape: BoxShape.circle),
                ),
              ),
              Expanded(
                child: Text(r,
                    style: TextStyle(
                        color: c.textSecondary, fontSize: 14.sp, height: 1.4)),
              ),
            ]),
          ),
      ]),
    );
  }

  // ── Payments ──
  Widget _paymentsCard(AppColorsExtension c, List<dynamic> payments) {
    return _card(
      c,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(context.l10n.accountPayments,
            style: TextStyle(
                color: c.textPrimary, fontSize: 16.sp, fontWeight: FontWeight.w700)),
        SizedBox(height: 8.h),
        for (final p in payments)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 8.h),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(
                  _formatDate((p as Map<String, dynamic>)['paid_at']?.toString()),
                  style: TextStyle(color: c.textSecondary, fontSize: 14.sp)),
              Text(_usd(_d(p['amount_usd'])),
                  style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w700)),
            ]),
          ),
      ]),
    );
  }

  String _formatDate(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso.split('T').first;
    // Same locale-aware date as the Milestones screen, never an ISO date.
    return DateFormat.yMMMd(Localizations.localeOf(context).toString())
        .format(dt);
  }

  // ── Referees ──
  Widget _refereesCard(AppColorsExtension c, int bound) {
    return _card(
      c,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GestureDetector(
          onTap: () {
            setState(() => _showReferees = !_showReferees);
            if (_showReferees) {
              TrackingService.affiliateRefereesViewed(boundCount: bound);
            }
          },
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(context.l10n.accountYourFriends,
                style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w700)),
            Icon(_showReferees ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                color: c.textSecondary, size: 22.sp),
          ]),
        ),
        if (_showReferees) ...[
          SizedBox(height: 8.h),
          for (var i = 0; i < _referees.length; i++)
            _refereeRow(c, i, _referees[i] as Map<String, dynamic>),
        ],
      ]),
    );
  }

  Widget _refereeRow(AppColorsExtension c, int i, Map<String, dynamic> r) {
    // contribution_usd is Kute's GROSS earnings from this referee, NOT the
    // referrer's cut. Show the actual profit this user makes from the friend:
    // their commission rate applied to that gross (same math as the earnings
    // chart: ratePct/100 * gross).
    final rate = _d(_me?['commission_rate_pct']);
    final contrib = _d(r['contribution_usd']) * rate / 100.0;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 7.h),
      child: Row(children: [
        Text(context.l10n.accountUserNumber(i + 1),
            style: TextStyle(color: c.textPrimary, fontSize: 14.sp)),
        const Spacer(),
        if (contrib > 0)
          Text(_usd(contrib),
              style: TextStyle(
                  color: c.textSecondary,
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w600)),
      ]),
    );
  }

  // ── Late entry fallback ──
  Widget _lateEntryCard(AppColorsExtension c) {
    return _card(
      c,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(context.l10n.accountGotAFriendsCode,
            style: TextStyle(
                color: c.textPrimary, fontSize: 16.sp, fontWeight: FontWeight.w700)),
        SizedBox(height: 6.h),
        Text(
            _discount == null
                ? context.l10n.accountEnterFriendCodeNoDiscount
                : context.l10n.accountEnterFriendCode(_discount!),
            style: TextStyle(color: c.textSecondary, fontSize: 14.sp, height: 1.4)),
        SizedBox(height: 12.h),
        // Same chrome as AppTextField (surfaceLight fill, 16 radius,
        // hairline border, accent focus ring); kept as a raw TextField
        // only because AppTextField has no textCapitalization knob.
        TextField(
          controller: _codeCtrl,
          textCapitalization: TextCapitalization.characters,
          cursorColor: c.accent,
          onChanged: (v) {
            if (v.trim().isNotEmpty) _startLateEntry();
          },
          style: TextStyle(
              color: c.textPrimary,
              fontSize: 16.sp,
              fontFamily: 'monospace',
              letterSpacing: 2),
          decoration: InputDecoration(
            hintText: context.l10n.accountCodeHint,
            hintStyle: TextStyle(
                color: c.textTertiary, fontSize: 16.sp, letterSpacing: 2),
            filled: true,
            fillColor: c.surfaceLight,
            contentPadding:
                EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                borderSide: BorderSide(color: c.border)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                borderSide: BorderSide(color: c.accent, width: 1.5)),
          ),
        ),
        SizedBox(height: 12.h),
        AppButton(
          text: context.l10n.accountApplyCode,
          compact: true,
          onPressed: () => _submitReferrer(_codeCtrl.text.trim()),
        ),
      ]),
    );
  }

  Future<void> _submitReferrer(String code) async {
    if (code.isEmpty || _lateEntrySubmitting) return;
    _startLateEntry();
    _lateEntrySubmitting = true;
    _lateEntryAttempts++;
    TrackingService.setFlowStep('submitted');
    final int status;
    try {
      status = await AffiliateService.setReferrerByCode(code);
    } finally {
      _lateEntrySubmitting = false;
    }
    final result = switch (status) {
      200 => 'ok',
      404 => 'not_found',
      409 => 'already_set',
      410 => 'past_window',
      400 => 'self',
      _ => 'error',
    };
    // Same event as affiliateLateEntrySubmitted, plus the attempt number.
    TrackingService.track('affiliate_late_entry_submitted', params: {
      'result': result,
      'attempt': _lateEntryAttempts,
    });
    if (status == 200) {
      _lateEntryDone = true;
      TrackingService.track('affiliate_late_entry_completed', params: {
        'attempts': _lateEntryAttempts,
        'time_in_flow_bucket': _flowTimeBucket(_lateEntryWatch.elapsed),
      });
      TrackingService.clearFlowContext('affiliate_late_entry');
    } else {
      _lateEntryLastResult = result;
    }
    if (!mounted) return;
    final msg = switch (status) {
      200 => _discount == null
          ? context.l10n.accountCodeAppliedNoDiscount
          : context.l10n.accountCodeApplied(_discount!),
      404 => context.l10n.accountCodeDoesntExist,
      409 => context.l10n.accountFriendCodeAlreadySet,
      410 => context.l10n.accountCodeEntryClosed,
      400 => context.l10n.accountCantUseOwnCode,
      _ => context.l10n.accountSomethingWentWrong,
    };
    showMessageSnackBar(context: context, message: msg, error: status != 200);
    if (status == 200) _refresh();
  }

  // ── shared card shell ──
  Widget _card(AppColorsExtension c, {required Widget child, EdgeInsets? padding}) {
    // AppDecorations.card: floating shadow card in light mode, hairline
    // surface in dark, same chrome as the rest of Settings.
    return Container(
      width: double.infinity,
      padding: padding ?? EdgeInsets.all(16.w),
      decoration: AppDecorations.card(context),
      child: child,
    );
  }
}
