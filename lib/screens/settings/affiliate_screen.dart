// lib/screens/settings/affiliate_screen.dart
//
// THE REFERRAL PROGRAM (founder, 7 November 2026: "this screen must be
// remade in a much much better way also, this is not good": the QR
// dominated, the buttons were an old style, the numbers were weak and
// scattered, the tier progress was a tiny line and "How it works" was a
// wall of bullets). Reached from Settings' Referral program card and the
// Financial hub's Referrals square (both `/affiliate`, both where the
// policy allows `affiliate.program`). Remade as a fintech invite page on
// the app's own parts, top down, in the 16 gutters under the app's
// standard back header (kept: every screen pushed from Settings and the
// hub wears it, and the hero under it is the page's big headline, so a
// second large title would say the same thing twice):
//
//   * THE HERO: what the person gets and what a friend gets, from the
//     backend's own figures: "Earn 5% of your friends' fees" (the
//     person's commission rate, `commission_rate_pct`, else the program's
//     base rate) over "They get 20% off Kute fees" (the referee discount,
//     `referee_discount_pct`; no line where the backend states none), in
//     the sheet header's headline style, Sal wagging beside it (the
//     existing `body_wag` sheet, held while off screen);
//   * THE CODE CARD: one soft card, "Your code" over the code, the QR
//     square and the copy square at its right (the receive screens'
//     square buttons). A tap on the card or the copy square copies the
//     CODE itself, never the invite link (founder, 11 November 2026: "the
//     copy should copy the code, not the invite link"), with "Code
//     copied"; the link travels with Share invite and the QR. The QR
//     square opens the QR in a sheet ([_ReferralQrSheet]:
//     the receive screens' white plate, the code under it, the sheet's
//     own "Share" in the bar sending the QR as an image). No QR on the
//     page: almost nobody scans a referral QR in person;
//   * SHARE INVITE IS THE BAR (kute_bar_context.dart, the primary): the
//     invite card with Sal (InviteCardData: what a friend gets, the code
//     in its footer) in the share cards' preview sheet, whose Share sends
//     the image with the invite text and the link (or the code). The Sal
//     sheet stays a long press away;
//   * THE PROGRESS CARD, the lead under the code: "Friends joined" large
//     and "Your rate" large beside it, then the next step in words
//     ("Invite 38 more friends to earn 20%", or "You're on the top rate"
//     once nothing pays more) and the ladder as steps: one bar per rung
//     (the Goals level's bar, BalanceGoalBar), the rates under its edges
//     with the friends each one needs, all from `rules.base_rate_pct` and
//     `rules.tiers` (never a number of our own);
//   * PENDING PAYOUT and PAID TO DATE as two fact squares
//     (KuteActionCard.fact), exact to the cent;
//   * the earnings line (7d / 30d / 90d), the payments and the friends
//     list, as before, on the same soft card, each only when it has
//     something;
//   * HOW IT WORKS in three rows: Share your link, They join and trade
//     (the friend discount sentence, word for word), You earn 5% of
//     their fees (the ladder under it, "10% at 50 friends, 20% at 100
//     friends"): every terms sentence the old card carried, nothing about
//     payouts or eligibility was there to keep;
//   * "Got a friend's code?" last, and only while a code can still be
//     applied (founder, 11 November 2026: "don't show 'Got a friend's
//     code' when [the person] can no longer add [one]"). The backend's
//     rule (store.SetReferrerByCode, behind POST
//     /affiliate/set-referrer-by-code): no referrer yet (409), the
//     account at most 7 days old (410), not the person's own code (400),
//     a code that exists (404). `/me` states the first (`is_referred`)
//     but not the account's age, so the window is read from the spending
//     wallet's local creation moment (its id, `<unix-ms>-<rand>`): never
//     earlier than the backend's account row for a new wallet, later for
//     a restored one (so a restore can still show the card, and the
//     backend's own 409 / 410 then closes it for the run). Unknown age
//     keeps the card ([referrerEntryOpen]).
//
// GATING, unchanged: where the runtime policy withholds
// `affiliate.program` (or fails closed) there is no way in (Settings,
// the hub, search and onboarding hide it); reached anyway, nothing
// promotes the program: no hero, no code card, no QR, no Share invite in
// the bar (the default Sal pill), no "Share your link" step and no
// late-entry prompt, and no unavailable message. The progress, the
// money, the line, the payments, the friends and the two rules stay, on
// their own backend rules. With no code minted yet the code card reads
// dashes with no buttons and the bar is the default pill. Loading draws
// the page's shapes; the backend failing with the program live reads
// "Couldn't load your Earn data" with Try again as the bar; failing with
// the program not live reads "Coming soon".
//
// Numbers: all from the backend's `/me` (code, rate, friends, accrued,
// paid, payments, rules, discount), `/me/history` and `/me/referees`.
// Code renames done in the admin board propagate here automatically
// (getMe reconciles the cached code and re-identifies PostHog).
//
// Analytics (names unchanged; never the code, the link or an id):
// `affiliate_earn_viewed` {state}, `affiliate_dashboard_loaded`,
// `affiliate_share_link_generated` {link_type}, `affiliate_share_opened`
// {method: card | qr | image, trigger: bar (Share invite) | code_card (the
// QR square, method qr) | qr (the QR tapped in its sheet) | qr_sheet (the
// sheet's Share)},
// `affiliate_code_shared` {method: card | sheet | image, result, surface:
// earn},
// `affiliate_code_copied` {surface: earn, source: code_card |
// copy_button}, `affiliate_earn_retry_tapped` / `_result`,
// `affiliate_history_window_changed`, `affiliate_referees_viewed`, the
// late-entry events and `pull_to_refresh_executed` {screen: affiliate}.

import 'dart:async' show unawaited;
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/providers/breez_config_provider.dart';
import 'package:kute/providers/breez_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart'
    show pickSpendingWallet;
import 'package:kute/screens/analytics/components/balance_goals.dart'
    show BalanceGoalBar, BalanceGoalSalMotion;
import 'package:kute/screens/share/cards/share_card_data.dart'
    show InviteCardData;
import 'package:kute/screens/share/cards/share_card_preview.dart'
    show showShareCardPreviewSheet;
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/charts/kute_line_chart.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/fee_copy.dart';
import 'package:kute/screens/shared/kute_action_cards.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/kute_motion.dart' show KutePressable;
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/screens/shared/qr_code.dart';
import 'package:kute/screens/shared/receive_surface.dart'
    show ReceiveAddressIconButton, ReceiveQrPlate;
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/services/appsflyer_service.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/wallet_identity_service.dart';
import 'package:kute/theme/app_theme.dart';

/// One rung of the commission ladder: [rate] percent of the friends'
/// fees from [friends] friends on.
@immutable
class ReferralTier {
  const ReferralTier(this.friends, this.rate);

  final int friends;
  final double rate;

  @override
  bool operator ==(Object other) =>
      other is ReferralTier && other.friends == friends && other.rate == rate;

  @override
  int get hashCode => Object.hash(friends, rate);

  @override
  String toString() => 'ReferralTier($friends, $rate)';
}

/// Where the person stands on the ladder (see the file header), from the
/// dashboard payload alone: the base rate at no friends then each tier
/// by the friends it needs ([ladder], empty without a base rate), the
/// friends joined and the person's own rate (0 where the backend has not
/// said).
@immutable
class ReferralProgress {
  const ReferralProgress({
    required this.ladder,
    required this.friends,
    required this.rate,
  });

  /// Read from `/me`: `rules.base_rate_pct`, `rules.tiers`
  /// (`activated_referees`, `rate_pct`), `referees_bound` and
  /// `commission_rate_pct`.
  factory ReferralProgress.fromMe(Map<String, dynamic>? me) {
    final ladder = <ReferralTier>[];
    final rules = me?['rules'];
    if (rules is Map) {
      final base = rules['base_rate_pct'];
      if (base is num && base.isFinite && base > 0) {
        ladder.add(ReferralTier(0, base.toDouble()));
        final tiers = rules['tiers'];
        final rungs = <ReferralTier>[];
        if (tiers is List) {
          for (final tier in tiers) {
            if (tier is! Map) continue;
            final rate = tier['rate_pct'];
            final count = tier['activated_referees'];
            if (rate is num &&
                rate.isFinite &&
                rate > 0 &&
                count is num &&
                count > 0) {
              rungs.add(ReferralTier(count.toInt(), rate.toDouble()));
            }
          }
        }
        rungs.sort((a, b) => a.friends.compareTo(b.friends));
        ladder.addAll(rungs);
      }
    }
    final friends = me?['referees_bound'];
    final rate = me?['commission_rate_pct'];
    return ReferralProgress(
      ladder: List.unmodifiable(ladder),
      friends: friends is num ? math.max(0, friends.toInt()) : 0,
      rate: rate is num && rate.isFinite && rate > 0 ? rate.toDouble() : 0,
    );
  }

  final List<ReferralTier> ladder;
  final int friends;
  final double rate;

  /// The rate the person earns now: theirs, else the ladder's first.
  double? get currentRate =>
      rate > 0 ? rate : (ladder.isEmpty ? null : ladder.first.rate);

  /// The next rung that pays more than the person's rate and is still
  /// ahead of their friends; null at the top (or with no ladder).
  ReferralTier? get next {
    final now = currentRate ?? 0;
    for (final tier in ladder.skip(1)) {
      if (tier.rate > now && tier.friends > friends) return tier;
    }
    return null;
  }

  /// Friends still to invite for [next].
  int? get remaining {
    final n = next;
    return n == null ? null : n.friends - friends;
  }

  /// Nothing on the ladder pays more than the person's rate.
  bool get top {
    final now = currentRate;
    if (now == null || ladder.length < 2) return false;
    return ladder.every((t) => t.rate <= now);
  }

  /// Whether the rung at [i] is reached: its rate is paid now, or its
  /// friends have joined.
  bool reached(int i) {
    final t = ladder[i];
    return (currentRate ?? 0) >= t.rate || friends >= t.friends;
  }

  /// How full the bar between rung [i] and rung [i] + 1 is, 0 to 1.
  double fill(int i) {
    final a = ladder[i];
    final b = ladder[i + 1];
    if ((currentRate ?? 0) >= b.rate || friends >= b.friends) return 1;
    final span = b.friends - a.friends;
    if (span <= 0) return 0;
    return ((friends - a.friends) / span).clamp(0.0, 1.0);
  }
}

/// The backend's late-entry window (store.SetReferrerByCode: an account
/// older than 7 days gets 410, "past 7-day window").
const Duration kReferrerEntryWindow = Duration(days: 7);

/// The local creation moment a wallet id carries (`<unix-ms>-<rand>`, as
/// every create and restore path mints it); null when it doesn't parse.
DateTime? walletCreatedAtFromId(String? id) {
  if (id == null) return null;
  final dash = id.indexOf('-');
  if (dash <= 0) return null;
  final ms = int.tryParse(id.substring(0, dash));
  return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
}

/// Whether "Got a friend's code?" can still do anything for this person
/// (see the file header): no referrer bound, the backend has not already
/// answered that entry is closed ([closed]: a 409 or 410 this run), and
/// the wallet no older than [kReferrerEntryWindow] where its age is known.
bool referrerEntryOpen({
  required bool isReferred,
  bool closed = false,
  DateTime? walletCreatedAt,
  DateTime? now,
}) {
  if (isReferred || closed) return false;
  if (walletCreatedAt == null) return true;
  final age = (now ?? DateTime.now()).difference(walletCreatedAt);
  return age <= kReferrerEntryWindow;
}

/// A rate as the page writes it in a sentence's number slot (5 → "5",
/// 7.5 → "7.5"): the strings carry their own percent sign.
String _rateNumber(double rate) =>
    rate.toStringAsFixed(rate == rate.roundToDouble() ? 0 : 1);

/// Dollars exact to the cent ("$1,210.50").
final NumberFormat _usdFormat =
    NumberFormat.currency(locale: 'en_US', symbol: r'$', decimalDigits: 2);
String _usd(num v) => _usdFormat.format(v);

/// AffiliateScreen: the Referral program (see the file header).
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
  // Codes whose late entry the backend closed this run (a 409 or 410):
  // the card stays away on every open until the app restarts.
  static final Set<String> _entryClosedFor = <String>{};
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
        'time_in_flow_ms': _lateEntryWatch.elapsed.inMilliseconds,
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
      (_me?['affiliate_code'] as String?) ??
      AffiliateService.affiliateCode ??
      '';

  /// "Got a friend's code?" can still apply one (see the file header).
  bool get _lateEntryOpen => referrerEntryOpen(
        isReferred: _me?['is_referred'] == true,
        closed: _entryClosedFor.contains(_code),
        walletCreatedAt: walletCreatedAtFromId(
            pickSpendingWallet(ref.read(settingsProvider))?.id),
      );

  /// The invite link: the OneLink (branded once it resolved, else the
  /// local long form), null where no template is configured.
  String? get _link =>
      _shareLink ??
      (_code.isNotEmpty ? AppsFlyerService.shareLink(_code) : null);

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
    // upgrade to a branded short link. No website fallback: if neither
    // resolves, the QR square is absent and the share and copy carry the
    // code.
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
    final participation =
        ref.read(runtimeCapabilitiesProvider).allows('affiliate.program');
    final isReferred = _me?['is_referred'] == true;
    final lateEntryOpen = _lateEntryOpen;
    TrackingService.track('affiliate_dashboard_loaded', params: {
      'has_code': _code.isNotEmpty,
      'has_pending_payout': _d(_me?['accrued_usd']) > 0,
      'has_paid_out': _d(_me?['paid_usd']) > 0,
      'has_payments': payments.isNotEmpty,
      'has_history': _history.isNotEmpty,
      'referees': bound,
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
      'late_entry_shown': participation && lateEntryOpen,
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

  void _retry() {
    TrackingService.track('affiliate_earn_retry_tapped');
    _retrying = true;
    setState(() => _phase = _Phase.loading);
    _bootstrap();
  }

  // ── number helpers ──
  double _d(dynamic v) => v is num ? v.toDouble() : 0;
  int _i(dynamic v) => v is num ? v.toInt() : 0;

  /// The referee discount as copy ("20%", a share of the Kute fee), from
  /// the dashboard payload when it has answered, otherwise the figure the
  /// backend gave elsewhere this run. Null when there is none to quote.
  String? get _discount {
    final fromMe = _me?['referee_discount_pct'];
    final pct = fromMe is num && fromMe >= 0
        ? fromMe.toInt()
        : AffiliateService.refereeDiscountPct;
    return pct == null || pct <= 0 ? null : discountShareText(pct);
  }

  /// The ladder's rungs past the base as one line ("10% at 50 friends,
  /// 20% at 100 friends"); null with none.
  String? _ladderLine(ReferralProgress progress) {
    if (progress.ladder.length < 2) return null;
    return progress.ladder
        .skip(1)
        .map((t) => context.l10n
            .accountRuleEarningsStep(commissionRateText(t.rate), t.friends))
        .join(', ');
  }

  // ── build ──

  /// What the bar is over this screen (see the file header): Share
  /// invite on the dashboard with a code to share, Try again on the
  /// error, else the default pill (null).
  KuteBarContext? _barContext(bool participationAllowed) {
    final l10n = context.l10n;
    return switch (_phase) {
      _Phase.dashboard when participationAllowed && _code.isNotEmpty =>
        KuteBarContext.primary(
          label: l10n.referralShareInvite,
          onPrimary: _openInviteCard,
          // Never off: with a code there is always something to share.
          disabledLabel: null,
          source: 'affiliate',
        ),
      _Phase.error => KuteBarContext.primary(
          label: l10n.accountTryAgain,
          onPrimary: _retry,
          disabledLabel: null,
          source: 'affiliate',
        ),
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final participationAllowed =
        ref.watch(runtimeCapabilitiesProvider).allows('affiliate.program');
    final bar = _barContext(participationAllowed);
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: true,
        elevation: 0,
        leading: const KuteBackButton(),
        title: Text(context.l10n.settingsReferralProgram,
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 20.sp,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            )),
      ),
      body: Container(
        decoration: AppDecorations.screenGradient(context),
        // The scope stays in place and is toggled, so the page under it
        // is never re-parented as the phase moves.
        child: KuteBarContextScope(
          barContext:
              bar ?? KuteBarContext(label: context.l10n.searchOrManageAi),
          active: bar != null,
          child: switch (_phase) {
            _Phase.loading => _buildLoading(c),
            _Phase.comingSoon => _buildMessage(
                key: const ValueKey('referral-coming-soon'),
                title: context.l10n.comingSoon2,
                line: context.l10n.accountInviteFriendsEarnShare,
                clip: _kHeroClip,
              ),
            _Phase.error => _buildMessage(
                key: const ValueKey('referral-error'),
                title: context.l10n.accountCouldntLoadEarnData,
                clip: 'body_sad',
              ),
            _Phase.dashboard => RefreshIndicator(
                onRefresh: () {
                  TrackingService.pullToRefreshExecuted(screen: 'affiliate');
                  return _refresh();
                },
                color: c.textPrimary,
                child: _buildDashboard(c, participationAllowed),
              ),
          },
        ),
      ),
    );
  }

  /// The page's end padding: clear of the floating bar and the home
  /// indicator (the body is not SafeArea-wrapped).
  EdgeInsets get _pagePadding => EdgeInsets.fromLTRB(16.w, 8.h, 16.w,
      24.h + kuteBarScrollClearance.h + MediaQuery.paddingOf(context).bottom);

  /// The loading state: the page's own shapes (the hero's lines and Sal,
  /// the code card, the progress card, the two squares).
  Widget _buildLoading(AppColorsExtension c) {
    final surface = KuteActionCard.surfaceOf(context);
    // As tall as its bones, never a fixed height (a large text size or a
    // short phone would overflow one).
    Widget card(List<Widget> bones) => Container(
          padding: KuteActionCard.paddingIn(surface, kKuteActionCardPadding),
          decoration: surface,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: bones,
          ),
        );
    final gap = SizedBox(height: kKuteActionCardGap.w);
    return SingleChildScrollView(
      key: const ValueKey('referral-loading'),
      physics: const NeverScrollableScrollPhysics(),
      padding: _pagePadding,
      child: KuteSkeleton(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(4.w, 8.h, 4.w, 20.h),
              child: Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBar(200.w, 26.h, radius: 8.r),
                      SizedBox(height: 8.h),
                      SkeletonBar(140.w, 26.h, radius: 8.r),
                      SizedBox(height: 12.h),
                      SkeletonBar(170.w, 14.h),
                    ],
                  ),
                ),
                SkeletonCircle(_kHeroSal.w),
              ]),
            ),
            card([
              SkeletonBar(70.w, 12.h),
              SizedBox(height: 10.h),
              SkeletonBar(120.w, 20.h, radius: 8.r),
            ]),
            gap,
            card([
              SkeletonBar(90.w, 12.h),
              SizedBox(height: 10.h),
              SkeletonBar(50.w, 28.h, radius: 8.r),
              SizedBox(height: 14.h),
              SkeletonBar(180.w, 12.h),
              SizedBox(height: 18.h),
              SkeletonBar(double.infinity, 6.h),
              SizedBox(height: 10.h),
              SkeletonBar(double.infinity, 24.h),
            ]),
            gap,
            Row(children: [
              for (var i = 0; i < 2; i++) ...[
                if (i > 0) SizedBox(width: kKuteActionCardGap.w),
                Expanded(
                  child: card([
                    SkeletonCircle(kKuteActionCardVisualSize),
                    const SizedBox(height: 12),
                    SkeletonBar(80.w, 12.h),
                    SizedBox(height: 6.h),
                    SkeletonBar(60.w, 16.h),
                  ]),
                ),
              ],
            ]),
          ],
        ),
      ),
    );
  }

  /// Coming soon and the error: the hero's own layout, Sal beside the
  /// headline at the page's top (the error's way on is the bar).
  Widget _buildMessage({
    required Key key,
    required String title,
    String? line,
    required String clip,
  }) {
    return ListView(
      key: key,
      padding: _pagePadding,
      children: [_ReferralHero(title: title, line: line, clip: clip)],
    );
  }

  Widget _buildDashboard(AppColorsExtension c, bool participationAllowed) {
    final l10n = context.l10n;
    final progress = ReferralProgress.fromMe(_me);
    final rate = progress.currentRate;
    final accrued = _d(_me?['accrued_usd']);
    final paid = _d(_me?['paid_usd']);
    final lateEntryOpen = _lateEntryOpen;
    final payments = (_me?['payments'] as List<dynamic>?) ?? const [];
    final discount = _discount;
    final gap = SizedBox(height: kKuteActionCardGap.w);

    // How it works (see the file header): the base rate the program
    // pays from the first friend, else the person's own.
    final baseRate =
        progress.ladder.isNotEmpty ? progress.ladder.first.rate : rate;
    final steps = <_Step>[
      if (participationAllowed)
        _Step(
          key: const ValueKey('referral-step-share'),
          icon: Icons.ios_share_rounded,
          title: l10n.referralStepShare,
          line: l10n.referralStepShareLine,
        ),
      _Step(
        key: const ValueKey('referral-step-join'),
        icon: Icons.person_add_alt_1_rounded,
        title: l10n.referralStepJoin,
        line:
            discount == null ? null : l10n.accountRuleFriendDiscount(discount),
      ),
      if (baseRate != null)
        _Step(
          key: const ValueKey('referral-step-earn'),
          icon: Icons.savings_rounded,
          title: l10n.referralStepEarn(commissionRateText(baseRate)),
          line: _ladderLine(progress),
        ),
    ];

    return ListView(
      key: const ValueKey('referral-dashboard'),
      padding: _pagePadding,
      children: [
        if (participationAllowed) ...[
          _ReferralHero(
            title: rate == null
                ? l10n.shareCodeTitle
                : l10n.referralHeroTitle(commissionRateText(rate)),
            line: discount == null ? null : l10n.referralHeroLine(discount),
            clip: _kHeroClip,
          ),
          _CodeCard(
            code: _code,
            onCopy: _code.isEmpty ? null : _copyCode,
            onQr: _code.isEmpty || _link == null ? null : _openQrSheet,
          ),
          gap,
        ],
        _ProgressCard(progress: progress),
        gap,
        KuteActionCardGrid(
          key: const ValueKey('referral-money'),
          cards: [
            _moneyCard(
              key: const ValueKey('referral-pending'),
              icon: Icons.hourglass_bottom_rounded,
              label: l10n.accountPendingPayout,
              amount: accrued,
            ),
            _moneyCard(
              key: const ValueKey('referral-paid'),
              icon: Icons.payments_rounded,
              label: l10n.accountPaidToDate,
              amount: paid,
            ),
          ],
        ),
        if (_history.isNotEmpty) ...[gap, _graphCard(c)],
        if (payments.isNotEmpty) ...[gap, _paymentsCard(c, payments)],
        // No "Your friends" list, ever (founder, 11 November 2026).
        // Withheld, only the rules the old card carried (a figure the
        // backend stated); nothing to explain without one.
        if (participationAllowed || discount != null || baseRate != null) ...[
          gap,
          _HowItWorks(steps: steps)
        ],
        if (participationAllowed && lateEntryOpen) ...[
          gap,
          _lateEntryCard(c)
        ],
      ],
    );
  }

  /// A money square: the fact card, the amount exact to the cent on one
  /// line (a long one shrinks rather than wraps).
  KuteActionCard _moneyCard({
    required Key key,
    required IconData icon,
    required String label,
    required double amount,
  }) {
    final text = _usd(amount);
    return KuteActionCard.fact(
      key: key,
      visual: KuteActionCardIcon(icon),
      label: label,
      title: text,
      oneLineTitle: (style) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(text,
            maxLines: 1,
            style: style
                .copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
      ),
    );
  }

  // ── Copy, share, QR ──

  /// Copies the person's code, never the invite link (see the file
  /// header). [source]: `code_card` (the card) or `copy_button` (its
  /// square).
  void _copyCode({String source = 'code_card'}) {
    final code = _code;
    if (code.isEmpty) return;
    Clipboard.setData(ClipboardData(text: code));
    TrackingService.affiliateCodeCopied(surface: 'earn', source: source);
    if (!mounted) return;
    showMessageSnackBar(
      context: context,
      message: context.l10n.accountCodeCopied,
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

  Rect _shareOrigin() {
    final box = context.findRenderObject() as RenderBox?;
    return box != null && box.hasSize
        ? (box.localToGlobal(Offset.zero) & box.size)
        : (Offset.zero & const Size(1, 1));
  }

  /// Share invite: the invite card in the share cards' preview sheet, its
  /// Share sending the image with the invite text.
  void _openInviteCard() {
    if (_link == null && _code.isEmpty) return;
    _trackShareOpened('card', 'bar');
    final l10n = context.l10n;
    final card = InviteCardData(discount: _discount, referralCode: _code);
    unawaited(showShareCardPreviewSheet(
      context,
      title: l10n.shareCardReadyTitle,
      shareLabel: l10n.share,
      routeName: 'invite_card_preview',
      source: 'invite_card',
      build: (_) => card,
      text: (_) => _shareText(_link),
      onShared: (result) => TrackingService.affiliateCodeShared(
          method: 'card', result: result, surface: 'earn'),
    ));
  }

  /// The invite as text through the share sheet, where the QR image share
  /// fell back: the link, or the code where no link resolves.
  Future<void> _openShare({required String method, String? trigger}) async {
    final link = _link;
    if (link == null && _code.isEmpty) return;
    _trackShareOpened(method, trigger);
    try {
      final r = await SharePlus.instance.share(ShareParams(
        text: _shareText(link),
        sharePositionOrigin: _shareOrigin(),
      ));
      TrackingService.affiliateCodeShared(
          method: method, result: r.status.name, surface: 'earn');
    } catch (_) {
      // User dismissed / platform error: the share never opened.
      TrackingService.affiliateCodeShared(
          method: method, result: 'error', surface: 'earn');
    }
  }

  /// `affiliate_share_opened` with what the user tapped ([trigger], see
  /// the file header).
  void _trackShareOpened(String method, String? trigger) =>
      TrackingService.track('affiliate_share_opened', params: {
        'method': method,
        if (trigger != null) 'trigger': trigger,
      });

  /// The QR in its sheet (the code card's QR square).
  Future<void> _openQrSheet() async {
    final link = _link;
    if (link == null) return;
    _trackShareOpened('qr', 'code_card');
    await showAppBottomSheet<void>(
      context: context,
      builder: (sheetContext) => _ReferralQrSheet(
        link: link,
        code: _code,
        onShare: (qrKey, trigger) =>
            _shareImage(qrKey: qrKey, trigger: trigger),
      ),
    );
  }

  /// Shares the QR as a PNG image alongside the invite text, so a friend
  /// can scan it directly. Falls back to a plain link/text share if the
  /// QR hasn't rendered yet or the capture fails.
  Future<void> _shareImage({required GlobalKey qrKey, String? trigger}) async {
    final boundary =
        qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return _openShare(method: 'image', trigger: trigger);
    final link = _link;

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
    try {
      final r = await SharePlus.instance.share(ShareParams(
        files: [file],
        text: _shareText(link),
        sharePositionOrigin: _shareOrigin(),
      ));
      TrackingService.affiliateCodeShared(
          method: 'image', result: r.status.name, surface: 'earn');
    } catch (_) {
      TrackingService.affiliateCodeShared(
          method: 'image', result: 'error', surface: 'earn');
    }
  }

  // ── Earnings line ──
  Widget _graphCard(AppColorsExtension c) {
    final values = <double>[];
    for (var i = 0; i < _history.length; i++) {
      final p = _history[i] as Map<String, dynamic>;
      values.add(_d(p['cumulative_usd']));
    }
    return _SectionCard(
      key: const ValueKey('referral-earnings'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(context.l10n.accountEarnings,
                style: KuteActionCard.titleStyle(c)),
          ),
          for (final d in [7, 30, 90]) _windowChip(c, d),
        ]),
        SizedBox(height: 14.h),
        SizedBox(
          height: 120.h,
          child: values.length < 2
              ? Center(
                  child: Text(context.l10n.accountNotEnoughDataYet,
                      style: KuteActionCard.subtitleStyle(c)))
              // Shared chart engine: monotone cubic curve, the standard
              // 0.14 gradient fill and endpoint dot, plus the ~280ms
              // series morph when the 7/30/90d window flips. Non-
              // interactive: the squares above carry the values.
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

  // ── Payments ──
  Widget _paymentsCard(AppColorsExtension c, List<dynamic> payments) {
    return _SectionCard(
      key: const ValueKey('referral-payments'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(context.l10n.accountPayments, style: KuteActionCard.titleStyle(c)),
        SizedBox(height: 6.h),
        for (final p in payments)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 8.h),
            child: Row(children: [
              Expanded(
                child: Text(
                    _formatDate(
                        (p as Map<String, dynamic>)['paid_at']?.toString()),
                    style: TextStyle(color: c.textSecondary, fontSize: 14.sp)),
              ),
              Text(_usd(_d(p['amount_usd'])),
                  style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()])),
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

  // ── Late entry fallback ──
  Widget _lateEntryCard(AppColorsExtension c) {
    return _SectionCard(
      key: const ValueKey('referral-late-entry'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(context.l10n.accountGotAFriendsCode,
            style: KuteActionCard.titleStyle(c)),
        SizedBox(height: 4.h),
        Text(
            _discount == null
                ? context.l10n.accountEnterFriendCodeNoDiscount
                : context.l10n.accountEnterFriendCode(_discount!),
            style: KuteActionCard.subtitleStyle(c)),
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
              fontWeight: FontWeight.w600,
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
        // The secondary look: the page's one primary is the bar's Share
        // invite.
        AppButton(
          key: const ValueKey('referral-apply-code'),
          text: context.l10n.accountApplyCode,
          variant: AppButtonVariant.secondary,
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
        'time_in_flow_ms': _lateEntryWatch.elapsed.inMilliseconds,
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
    // The backend closed entry for good (a referrer is bound, or the
    // window has passed): the card goes and stays away this run.
    if (status == 409 || status == 410) {
      setState(() => _entryClosedFor.add(_code));
    }
    if (status == 200 || status == 409) _refresh();
  }
}

/// Sal in the hero: the existing wag loop.
const String _kHeroClip = 'body_wag';

/// Sal's side in the hero, design units.
const double _kHeroSal = 88;

/// The hero (see the file header): the headline in the sheet header's
/// style, the line under it, Sal at the right. Sal moves only while on
/// screen (BalanceGoalSalMotion).
class _ReferralHero extends StatelessWidget {
  const _ReferralHero({required this.title, this.line, required this.clip});

  final String title;
  final String? line;
  final String clip;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final size = _kHeroSal.w;
    return Padding(
      key: const ValueKey('referral-hero'),
      padding: EdgeInsets.fromLTRB(4.w, 4.h, 0, 20.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  key: const ValueKey('referral-hero-title'),
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 28.sp,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                    height: 1.1,
                  ),
                ),
                if (line != null) ...[
                  SizedBox(height: 8.h),
                  Text(
                    line!,
                    key: const ValueKey('referral-hero-line'),
                    style: TextStyle(
                      color: c.textSecondary,
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.1,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(width: 8.w),
          ExcludeSemantics(
            child: BalanceGoalSalMotion(
              child: SizedBox.square(
                dimension: size,
                child: SalSprite(
                  clip: clip,
                  size: size,
                  fallback: Center(
                    child: KuteActionCardIcon(Icons.group_rounded,
                        size: kKuteActionCardLeadVisualSize),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The code card (see the file header): "Your code" over the code, the
/// QR square and the copy square at its right. The card's tap copies.
/// With no code minted yet: dashes and no squares.
class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.code, this.onCopy, this.onQr});

  final String code;

  /// Copies the code; [source] names the card or its square.
  final void Function({String source})? onCopy;
  final VoidCallback? onQr;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final surface = KuteActionCard.surfaceOf(context);
    final copy = onCopy;
    final qr = onQr;
    final card = Container(
      padding: KuteActionCard.paddingIn(surface, kKuteActionCardPadding),
      decoration: surface,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.accountYourCode, style: KuteActionCard.labelStyle(c)),
                const SizedBox(height: 2),
                Text(
                  code.isEmpty ? '------' : code,
                  key: const ValueKey('referral-code'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 22.sp,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.5,
                    height: 1.2,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          if (qr != null) ...[
            SizedBox(width: 8.w),
            Semantics(
              button: true,
              label: l10n.walletsShowQr,
              excludeSemantics: true,
              child: ReceiveAddressIconButton(
                key: const ValueKey('referral-code-qr'),
                icon: Icons.qr_code_2_rounded,
                onTap: qr,
              ),
            ),
          ],
          if (copy != null) ...[
            SizedBox(width: 8.w),
            Semantics(
              button: true,
              label: l10n.copy,
              excludeSemantics: true,
              child: ReceiveAddressIconButton(
                key: const ValueKey('referral-code-copy'),
                icon: Icons.copy_rounded,
                onTap: () => copy(source: 'copy_button'),
              ),
            ),
          ],
        ],
      ),
    );
    if (copy == null) {
      return Semantics(
        key: const ValueKey('referral-code-card'),
        container: true,
        child: card,
      );
    }
    return Semantics(
      key: const ValueKey('referral-code-card'),
      button: true,
      label: '${l10n.accountYourCode}, $code, ${l10n.copy}',
      child: KutePressable(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.lightImpact();
            copy();
          },
          child: card,
        ),
      ),
    );
  }
}

/// The progress card (see the file header): friends and the rate large,
/// the next step in words, the ladder as steps.
class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.progress});

  final ReferralProgress progress;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final surface = KuteActionCard.surfaceOf(context);
    final rate = progress.currentRate;
    final next = progress.next;
    final remaining = progress.remaining;
    final String? line = progress.top
        ? l10n.referralTopRate
        : next != null && remaining != null
            ? l10n.accountInviteMoreForRate(remaining, _rateNumber(next.rate))
            : null;
    final figure = TextStyle(
      color: c.textPrimary,
      fontSize: 28.sp,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.6,
      height: 1.15,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Container(
      key: const ValueKey('referral-progress'),
      padding: KuteActionCard.paddingIn(surface, kKuteActionCardPadding),
      decoration: surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: MergeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.referralFriendsJoined,
                          style: KuteActionCard.labelStyle(c)),
                      const SizedBox(height: 2),
                      Text('${progress.friends}',
                          key: const ValueKey('referral-friends-joined'),
                          style: figure),
                    ],
                  ),
                ),
              ),
              if (rate != null) ...[
                SizedBox(width: 12.w),
                MergeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(l10n.referralYourRate,
                          style: KuteActionCard.labelStyle(c)),
                      const SizedBox(height: 2),
                      Text(commissionRateText(rate),
                          key: const ValueKey('referral-your-rate'),
                          style: figure),
                    ],
                  ),
                ),
              ],
            ],
          ),
          if (line != null) ...[
            SizedBox(height: 6.h),
            Text(line,
                key: const ValueKey('referral-next-step'),
                style: KuteActionCard.subtitleStyle(c)),
          ],
          if (progress.ladder.length >= 2) ...[
            SizedBox(height: 16.h),
            _LadderSteps(progress: progress),
          ],
        ],
      ),
    );
  }
}

/// The ladder as steps: one bar per rung (the Goals level's bar), the
/// rates under its edges, each over the friends it needs. The labels sit
/// at the rungs: the first at the left edge, the last at the right, the
/// ones between centred on their gap; they wrap rather than run into
/// each other.
class _LadderSteps extends StatelessWidget {
  const _LadderSteps({required this.progress});

  final ReferralProgress progress;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final ladder = progress.ladder;
    final n = ladder.length;
    final gap = 4.w;
    // Three rungs: three equal columns put the middle label on the gap;
    // more: half columns at the ends, so every label centres on its rung.
    int flexOf(int i) => n <= 3 || i == 0 || i == n - 1 ? 1 : 2;
    return Column(
      key: const ValueKey('referral-ladder'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (var i = 0; i < n - 1; i++) ...[
              if (i > 0) SizedBox(width: gap),
              Expanded(
                child: SizedBox(
                  height: 6.w,
                  child: BalanceGoalBar(
                    key: ValueKey('referral-ladder-bar-$i'),
                    fraction: progress.fill(i),
                  ),
                ),
              ),
            ],
          ],
        ),
        SizedBox(height: 8.h),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < n; i++)
              Expanded(
                flex: flexOf(i),
                child: MergeSemantics(
                  child: Column(
                    crossAxisAlignment: i == 0
                        ? CrossAxisAlignment.start
                        : i == n - 1
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.center,
                    children: [
                      Text(
                        commissionRateText(ladder[i].rate),
                        key: ValueKey('referral-ladder-rate-$i'),
                        textAlign: _align(i, n),
                        style: TextStyle(
                          color: progress.reached(i)
                              ? c.textPrimary
                              : c.textTertiary,
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        l10n.referralTierFriends(ladder[i].friends),
                        textAlign: _align(i, n),
                        style: TextStyle(
                          color: c.textTertiary,
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w500,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  static TextAlign _align(int i, int n) => i == 0
      ? TextAlign.start
      : i == n - 1
          ? TextAlign.end
          : TextAlign.center;
}

/// One row of How it works.
class _Step {
  const _Step({
    required this.key,
    required this.icon,
    required this.title,
    this.line,
  });

  final Key key;
  final IconData icon;
  final String title;
  final String? line;
}

/// How it works (see the file header): the steps as compact rows, each
/// the cards' icon tile beside its title and the line under it.
class _HowItWorks extends StatelessWidget {
  const _HowItWorks({required this.steps});

  final List<_Step> steps;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return _SectionCard(
      key: const ValueKey('referral-how-it-works'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.howItWorks2, style: KuteActionCard.titleStyle(c)),
          for (final step in steps) ...[
            SizedBox(height: 14.h),
            MergeSemantics(
              key: step.key,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KuteActionCardIcon(step.icon, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(step.title,
                              style: KuteActionCard.optionTitleStyle(c)),
                          if (step.line != null) ...[
                            const SizedBox(height: 2),
                            Text(step.line!,
                                style: KuteActionCard.subtitleStyle(c)),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A section on the app's one soft card (kute_action_cards.dart).
class _SectionCard extends StatelessWidget {
  const _SectionCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final surface = KuteActionCard.surfaceOf(context);
    return Container(
      width: double.infinity,
      padding: KuteActionCard.paddingIn(surface, kKuteActionCardPadding),
      decoration: surface,
      child: child,
    );
  }
}

/// The QR in a sheet (see the file header): the receive screens' white
/// plate, the code under it; the sheet's "Share" is the bar and sends the
/// QR as an image (the QR itself shares too, as it always did).
class _ReferralQrSheet extends StatefulWidget {
  const _ReferralQrSheet({
    required this.link,
    required this.code,
    required this.onShare,
  });

  final String link;
  final String code;
  final Future<void> Function(GlobalKey qrKey, String trigger) onShare;

  @override
  State<_ReferralQrSheet> createState() => _ReferralQrSheetState();
}

class _ReferralQrSheetState extends State<_ReferralQrSheet> {
  final GlobalKey _qrKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    return AppBottomSheetContainer(
      child: Column(
        key: const ValueKey('referral-qr-sheet'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppBottomSheetHeader(
            title: l10n.accountYourCode,
            trailing: const AppBottomSheetCloseButton(),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () => widget.onShare(_qrKey, 'qr'),
                    child: ReceiveQrPlate(
                      child: RepaintBoundary(
                        key: _qrKey,
                        child: buildQrCode(widget.link, context),
                      ),
                    ),
                  ),
                  SizedBox(height: 16.h),
                  Text(
                    widget.code,
                    key: const ValueKey('referral-qr-code'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 22.sp,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.5,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  // THE BAR IS THE BUTTON (kute_bar_context.dart): the
                  // sheet's Share, the QR as an image.
                  KuteBarContextScope(
                    barContext: KuteBarContext.primary(
                      label: l10n.share,
                      onPrimary: () => widget.onShare(_qrKey, 'qr_sheet'),
                      disabledLabel: null,
                      source: 'affiliate_qr',
                    ),
                    child: SizedBox(height: kuteBarScrollClearance.h),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
