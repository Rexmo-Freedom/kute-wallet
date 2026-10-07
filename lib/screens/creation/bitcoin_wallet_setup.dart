import 'package:flutter/material.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/bitcoin_wallet_creation_provider.dart';
import 'package:kute/screens/creation/recover_wallet.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// An in-session wallet flow. Every cancel pops its local route and leaves the
/// existing wallet, unlock session and onboarding state untouched.
class BitcoinWalletSetup extends StatefulWidget {
  const BitcoinWalletSetup({super.key});

  @override
  State<BitcoinWalletSetup> createState() => _BitcoinWalletSetupState();
}

class _BitcoinWalletSetupState extends State<BitcoinWalletSetup> {
  /// This chooser owns `wallet_add_abandoned` only until an option is
  /// picked; the create / recover screens own their own drop-off.
  final Stopwatch _flowClock = Stopwatch()..start();
  bool _optionPicked = false;

  @override
  void initState() {
    super.initState();
    TrackingService.setFlowContext(
        flow: 'wallet_add',
        step: 'choose_bitcoin_action',
        walletKind: 'bitcoin_onchain');
    TrackingService.track('wallet_add_step', params: {
      'step': 'choose_bitcoin_action',
      'wallet_kind': 'bitcoin_onchain',
    });
  }

  @override
  void dispose() {
    if (!_optionPicked) {
      TrackingService.track('wallet_add_abandoned', params: {
        'step': 'choose_bitcoin_action',
        'wallet_kind': 'bitcoin_onchain',
        'time_in_flow_bucket': _timeInFlowBucket(_flowClock.elapsed),
        'reason': 'user_closed',
      });
      TrackingService.clearFlowContext('wallet_add');
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: Container(
        decoration: AppDecorations.screenGradient(context),
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 32.h),
            children: [
              Row(children: [
                KuteBackButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                )
              ]),
              SizedBox(height: 24.h),
              Text(context.l10n.walletTypeBitcoin,
                  style: AppTextStyles.heading1(context)),
              SizedBox(height: 6.h),
              Text(context.l10n.btcSetupSubtitle,
                  style: TextStyle(
                      color: c.textSecondary, fontSize: 15.sp, height: 1.3)),
              SizedBox(height: 28.h),
              _BitcoinSetupOption(
                icon: Icons.add_rounded,
                title: context.l10n.btcSetupCreateTitleShort,
                subtitle: context.l10n.btcSetupCreateSubtitle,
                onTap: () {
                  _optionPicked = true;
                  TrackingService.walletTypeSelected('bitcoin_create');
                  Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => const PostHogMaskWidget(
                          child: BitcoinWalletCreate())));
                },
              ),
              SizedBox(height: 12.h),
              _BitcoinSetupOption(
                icon: Icons.text_fields_rounded,
                title: context.l10n.btcSetupRecoverTitle,
                subtitle: context.l10n.btcSetupRecoverSubtitle,
                onTap: () {
                  _optionPicked = true;
                  TrackingService.walletTypeSelected('bitcoin_recover');
                  Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => const PostHogMaskWidget(
                          child: RecoverWallet(bitcoinOnly: true))));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BitcoinWalletCreate extends ConsumerStatefulWidget {
  const BitcoinWalletCreate({super.key});
  @override
  ConsumerState<BitcoinWalletCreate> createState() =>
      _BitcoinWalletCreateState();
}

class _BitcoinWalletCreateState extends ConsumerState<BitcoinWalletCreate> {
  /// The suggested name, in the app language. Set once the first time
  /// dependencies resolve, so an edited name is never overwritten.
  String? _defaultNameText;
  String get _defaultName => _defaultNameText ?? '';
  final _name = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_defaultNameText == null) {
      _defaultNameText = context.l10n.walletTypeBitcoin;
      _name.text = _defaultNameText!;
    }
  }
  bool _creating = false;

  // ── wallet_add funnel (categorical only; never the name) ──
  final Stopwatch _flowClock = Stopwatch()..start();
  bool _completed = false;
  String? _lastErrorCategory;

  @override
  void initState() {
    super.initState();
    TrackingService.setFlowContext(
        flow: 'wallet_add', step: 'name_wallet', walletKind: 'bitcoin_onchain');
    TrackingService.track('wallet_add_step', params: {
      'step': 'name_wallet',
      'import_method': 'create',
      'wallet_kind': 'bitcoin_onchain',
    });
    _name.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    if (!_completed) {
      TrackingService.track('wallet_add_abandoned', params: {
        'step': _creating ? 'creating' : 'name_wallet',
        'import_method': 'create',
        'wallet_kind': 'bitcoin_onchain',
        'has_custom_name': _name.text.trim() != _defaultName,
        'time_in_flow_bucket': _timeInFlowBucket(_flowClock.elapsed),
        'reason': _lastErrorCategory != null ? 'error' : 'user_closed',
        if (_lastErrorCategory != null)
          'last_error_category': _lastErrorCategory!,
      });
    }
    TrackingService.clearFlowContext('wallet_add');
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_creating || _name.text.trim().isEmpty) return;
    if (!ref.read(sessionUnlockedProvider)) {
      TrackingService.track('wallet_add_failed', params: {
        'reason': 'session_locked',
        'stage': 'precheck',
        'import_method': 'create',
        'wallet_kind': 'bitcoin_onchain',
      });
      showMessageSnackBar(
          context: context,
          message: context.l10n.btcSetupUnlockFirst,
          error: true);
      return;
    }
    final router = GoRouter.of(context);
    setState(() => _creating = true);
    // Extends walletAddStarted(): the commit point of this screen.
    TrackingService.setFlowStep('creating');
    TrackingService.track('wallet_add_started', params: {
      'import_method': 'create',
      'wallet_kind': 'bitcoin_onchain',
      'has_custom_name': _name.text.trim() != _defaultName,
    });
    var created = false;
    try {
      final wallet = await ref
          .read(bitcoinWalletCreationProvider)
          .create(name: _name.text);
      created = true;
      _completed = true;
      TrackingService.clearFlowContext('wallet_add');
      // The service's default script type is bip84 (native SegWit).
      TrackingService.walletCreated(
          type: 'bitcoin_onchain', authMode: 'mnemonic');
      TrackingService.walletAdded(
        walletKind: 'bitcoin_onchain',
        importMethod: 'create',
        scriptType: 'native_segwit',
        network: 'bitcoin',
        source: 'add_wallet',
      );
      if (!mounted) return;
      router.goNamed('walletDetail', pathParameters: {'walletId': wallet.id});
      await router.pushNamed('backup_wallet', extra: wallet.id);
    } catch (e) {
      // A navigation error after the wallet persisted is not a failed add.
      if (!created) {
        // Extends walletAddFailed(): same reason/error_code, plus a
        // fixed category and the flow dimensions.
        final category = TrackingService.errorCategory(e);
        _lastErrorCategory = category;
        TrackingService.track('wallet_add_failed', params: {
          'reason': 'bitcoin_create_failed',
          'error_code': e.runtimeType.toString(),
          'error_category': category,
          'stage': 'create',
          'import_method': 'create',
          'wallet_kind': 'bitcoin_onchain',
        });
      }
      if (mounted) {
        showMessageSnackBar(
            context: context,
            message: context.l10n.btcSetupCreateFailed,
            error: true);
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PopScope(
      canPop: !_creating,
      child: Scaffold(
        backgroundColor: c.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          leading: KuteBackButton(onPressed: () {
            if (!_creating) Navigator.of(context).maybePop();
          }),
        ),
        body: Container(
          decoration: AppDecorations.screenGradient(context),
          child: SafeArea(
            top: false,
            child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints:
                            BoxConstraints(minHeight: constraints.maxHeight),
                        child: IntrinsicHeight(
                          child: Padding(
                            padding:
                                EdgeInsets.fromLTRB(24.w, 24.h, 24.w, 24.h),
                            child: Column(children: [
                              Container(
                                width: 64.sp,
                                height: 64.sp,
                                padding: EdgeInsets.all(13.sp),
                                decoration: BoxDecoration(
                                    color: c.surfaceLight,
                                    borderRadius:
                                        BorderRadius.circular(AppRadius.xl)),
                                child: SvgPicture.asset(
                                    'lib/assets/bitcoin-icon.svg'),
                              ),
                              SizedBox(height: 20.h),
                              Text(context.l10n.btcSetupCreateTitle,
                                  textAlign: TextAlign.center,
                                  style: AppTextStyles.heading1(context)),
                              SizedBox(height: 10.h),
                              Text(context.l10n.btcSetupCreateBody,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: c.textSecondary,
                                      fontSize: 15.sp,
                                      fontWeight: FontWeight.w500,
                                      height: 1.4)),
                              const Spacer(),
                              SizedBox(height: 28.h),
                              TextField(
                                controller: _name,
                                enabled: !_creating,
                                maxLength: 60,
                                textInputAction: TextInputAction.done,
                                textCapitalization: TextCapitalization.words,
                                scrollPadding: EdgeInsets.only(bottom: 140.h),
                                style: TextStyle(
                                    color: c.textPrimary,
                                    fontSize: 16.sp,
                                    fontWeight: FontWeight.w600),
                                decoration: InputDecoration(
                                  hintText: context.l10n.btcSetupWalletNameHint,
                                  counterText: '',
                                  filled: true,
                                  fillColor: c.surfaceLight,
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 14.w, vertical: 14.h),
                                  enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12.r),
                                      borderSide: BorderSide(
                                          color: c.borderSubtle, width: 0.5)),
                                  focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12.r),
                                      borderSide: BorderSide(color: c.accent)),
                                  disabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12.r),
                                      borderSide: BorderSide(
                                          color: c.borderSubtle, width: 0.5)),
                                ),
                              ),
                              SizedBox(height: 12.h),
                              Container(
                                padding: EdgeInsets.all(16.w),
                                decoration: AppDecorations.card(context),
                                child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(Icons.lock_outline_rounded,
                                          size: 20.sp, color: c.textSecondary),
                                      SizedBox(width: 12.w),
                                      Expanded(
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                            Text(context.l10n.btcSetupBackupTitle,
                                                style: TextStyle(
                                                    color: c.textPrimary,
                                                    fontSize: 16.sp,
                                                    fontWeight:
                                                        FontWeight.w700)),
                                            SizedBox(height: 4.h),
                                            Text(
                                                context.l10n.btcSetupBackupBody,
                                                style: TextStyle(
                                                    color: c.textSecondary,
                                                    fontSize: 13.sp,
                                                    height: 1.35)),
                                          ])),
                                    ]),
                              ),
                              SizedBox(height: 28.h),
                              AppButton(
                                  text: context.l10n.continueLabel,
                                  isLoading: _creating,
                                  onPressed:
                                      _creating || _name.text.trim().isEmpty
                                          ? null
                                          : _create),
                            ]),
                          ),
                        ),
                      ),
                    )),
          ),
        ),
      ),
    );
  }
}

/// Matches the existing recovery-choice card spacing, typography and surfaces.
class _BitcoinSetupOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _BitcoinSetupOption(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: AppDecorations.card(context),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
            child: Row(children: [
              Container(
                  width: 44.w,
                  height: 44.w,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: c.surfaceLight,
                      borderRadius: BorderRadius.circular(AppRadius.md)),
                  child: Icon(icon, color: c.textPrimary, size: 24.sp)),
              SizedBox(width: 14.w),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(title,
                        style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w700)),
                    SizedBox(height: 3.h),
                    Text(subtitle,
                        style: TextStyle(
                            color: c.textSecondary,
                            fontSize: 13.sp,
                            height: 1.35)),
                  ])),
              SizedBox(width: 8.w),
              Icon(Icons.chevron_right_rounded,
                  color: c.textTertiary, size: 20.sp),
            ]),
          ),
        ),
      ),
    );
  }
}

/// `time_in_flow_bucket` for `wallet_add_abandoned`.
String _timeInFlowBucket(Duration d) {
  final s = d.inSeconds;
  if (s < 10) return '<10s';
  if (s < 30) return '10-30s';
  if (s < 120) return '30s-2m';
  if (s < 600) return '2-10m';
  return '10m+';
}
