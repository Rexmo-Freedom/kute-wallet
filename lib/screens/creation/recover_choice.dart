import 'package:kute/screens/shared/kute_dog_rig.dart';
import 'dart:math' as math;
import 'package:kute/services/evm_derivation_policy.dart';
import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:kute/services/secure/recovery_check.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/helpers/formatters/currency_formatter.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/bitcoin_config_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/creation/set_pin.dart'
    show recoveryModeProvider, trackOnboardingStep;
import 'package:kute/services/passkey_recovery.dart';
import 'package:kute/services/passkey_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/theme/app_theme.dart';

/// Analytics for the wallet restore funnel: `restore_started` (this
/// screen) → `restore_step {step, method}` → `wallet_added
/// {import_method}` (completion) | `passkey_restore_failed` /
/// `wallet_add_failed` / `recovery_phrase_invalid` (failures) |
/// `restore_abandoned`. Shared with the seed entry screen. Categorical
/// values only: never words, labels or counts.
class RestoreFlowAnalytics {
  static DateTime? _startedAt;
  static String _step = 'choice';
  static String? _method;
  static String? _lastErrorCategory;

  static void start({required String entrySource}) {
    _startedAt = DateTime.now();
    _step = 'choice';
    _method = null;
    _lastErrorCategory = null;
    TrackingService.track('restore_started',
        params: {'entry_source': entrySource});
    TrackingService.setFlowContext(flow: 'restore', step: 'choice');
  }

  /// A real step transition. [method] is 'passkey' or 'seed'.
  static void step(String step, {required String method, String? trigger}) {
    _step = step;
    _method = method;
    TrackingService.track('restore_step', params: {
      'step': step,
      'method': method,
      if (trigger != null) 'trigger': trigger,
    });
    TrackingService.setFlowStep(step);
  }

  /// Remember the last failure so an abandon can say why.
  static void failed(String errorCategory) =>
      _lastErrorCategory = errorCategory;

  static void completed() {
    _startedAt = null;
    TrackingService.clearFlowContext('restore');
  }

  /// The user left the restore flow without a wallet. Once per flow.
  static void abandoned({required String reason}) {
    final started = _startedAt;
    if (started == null) return;
    _startedAt = null;
    TrackingService.track('restore_abandoned', params: {
      'step': _step,
      if (_method != null) 'method': _method!,
      'time_in_flow_bucket': _timeBucket(DateTime.now().difference(started)),
      if (_lastErrorCategory != null)
        'last_error_category': _lastErrorCategory!,
      'reason': reason,
    });
    TrackingService.clearFlowContext('restore');
  }

  static String _timeBucket(Duration d) {
    final s = d.inSeconds;
    if (s < 10) return '<10s';
    if (s < 30) return '10-30s';
    if (s < 120) return '30s-2m';
    if (s < 600) return '2-10m';
    return '10m+';
  }
}

/// Attempts passkey recovery once on entry. Dismissing the native prompt
/// reveals recovery-phrase entry and an explicit passkey retry.
class RecoverChoiceScreen extends ConsumerStatefulWidget {
  const RecoverChoiceScreen({super.key});

  @override
  ConsumerState<RecoverChoiceScreen> createState() =>
      _RecoverChoiceScreenState();
}

class _RecoverChoiceScreenState extends ConsumerState<RecoverChoiceScreen> {
  bool _checkingPasskey = false;

  @override
  void initState() {
    super.initState();
    final firstWallet = ref.read(settingsProvider).wallets.isEmpty;
    // Onboarding funnel step for the restore path; the crash breadcrumb
    // is the more specific restore flow started right after.
    if (firstWallet) {
      trackOnboardingStep('recover_choice', path: 'restore', breadcrumb: false);
    }
    RestoreFlowAnalytics.start(
        entrySource: firstWallet ? 'onboarding' : 'add_wallet');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _handlePasskeyChoice(trigger: 'auto');
    });
  }

  bool _restoringPasskey = false;

  /// The passkey wallet waiting on its confirmation ceremony, so the
  /// screen can say which wallet the OS prompt is for.
  String? _confirmingLabel;

  Future<void> _handlePasskeyChoice({String trigger = 'tap'}) async {
    if (_checkingPasskey || _restoringPasskey) return;
    HapticFeedback.lightImpact();
    // [trigger] 'auto' is the lookup this screen runs once on entry.
    TrackingService.track('recover_choice_passkey_tapped',
        params: {'trigger': trigger});
    RestoreFlowAnalytics.step('passkey_lookup',
        method: 'passkey', trigger: trigger);
    setState(() => _checkingPasskey = true);
    try {
      // 1) NEW-SDK discovery FIRST, the Breez way: ONE signIn with no label
      //    lists the user's wallet labels (published to Nostr at creation)
      //    and names the credential that owns them. Called DIRECTLY — do
      //    NOT gate on checkAvailability(): it returns false (or throws) on
      //    some devices even right after a passkey was created, and the
      //    CREATE flow never consults it, so gating recovery on it was the
      //    bug that made "no passkey available" appear for wallets that
      //    plainly exist.
      PasskeyDiscovery? discovery;
      try {
        // The discovery sign-in raises the native passkey sheet.
        TrackingService.passkeyRestorePromptShown();
        discovery = await PasskeyService.discoverWallets();
      } catch (e) {
        // A cancelled ceremony is the user backing out — stop here rather
        // than fall through and prompt them a second time.
        if (e.toString().toLowerCase().contains('cancel')) {
          _trackPasskeyRestoreCancelled('lookup');
          return;
        }
        // Any other new-SDK failure is non-fatal: fall through to legacy.
      }
      if (!mounted) return;
      final labels = discovery?.labels ?? const <String>[];
      if (labels.length == 1) {
        // One wallet: nothing to choose, restore it straight away. The
        // confirmation ceremony is pinned to the discovered credential.
        await _restoreFromPasskeys(labels,
            credentialId: discovery!.credentialId, trigger: 'auto');
        return;
      }
      if (labels.isNotEmpty) {
        _showLabelPicker(labels, discovery!.credentialId);
        return;
      }
      if (!mounted) return;
      // 2) LEGACY (pre-2.x) recovery. 0.15.1 never published a Nostr label,
      //    so discovery can't see it even though the wallet is fully
      //    recoverable — rebuild the seed the 0.15.1 way and probe its
      //    balance/history BEFORE offering it (never adopt an empty
      //    phantom). Gated on the LEGACY availability signal, not the new
      //    SDK's.
      await _attemptLegacyRecovery();
    } catch (e) {
      // A cancelled biometric is the user backing out — don't nag.
      if (e.toString().toLowerCase().contains('cancel')) {
        _trackPasskeyRestoreCancelled('lookup');
        return;
      }
      _trackPasskeyRestoreFailed('lookup', e);
      if (!mounted) return;
      showMessageSnackBar(
        context: context,
        message: context.l10n.recoverChoicePasskeyLookupFailed,
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() => _checkingPasskey = false);
      }
    }
  }

  void _trackPasskeyRestoreFailed(String stage, Object? error) {
    final category = TrackingService.errorCategory(error);
    RestoreFlowAnalytics.failed(category);
    TrackingService.track('passkey_restore_failed', params: {
      'stage': stage,
      'error_category': category,
    });
  }

  void _trackPasskeyRestoreCancelled(String stage) {
    TrackingService.track('passkey_restore_cancelled',
        params: {'stage': stage});
  }

  /// Picker for the user to choose which passkey-backed wallet to
  /// restore. One tap → one wallet — there is no "Restore all"
  /// option (incompatible with the always-one-spending-wallet
  /// architecture).
  void _showLabelPicker(List<String> labels, Uint8List? credentialId) {
    final c = context.colors;
    final l10n = context.l10n;
    RestoreFlowAnalytics.step('passkey_pick', method: 'passkey');
    var picked = false;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.surface,
      // Scrollable: users with many wallets previously had entries pushed
      // off screen with no way to reach them.
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.7,
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 24.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  labels.length == 1
                      ? l10n.recoverPickWalletOne
                      : l10n.recoverPickWalletMany,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 12.h),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final label in labels)
                          Padding(
                            padding: EdgeInsets.only(bottom: 8.h),
                            child: ElevatedButton(
                              onPressed: () {
                                picked = true;
                                Navigator.of(ctx).pop();
                                _restoreFromPasskeys([label],
                                    credentialId: credentialId);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: c.surfaceLight,
                                foregroundColor: c.textPrimary,
                                minimumSize: Size.fromHeight(48.h),
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.lg),
                                ),
                                elevation: 0,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    PasskeyService.displayNameForLabel(label),
                                    style: TextStyle(
                                        fontSize: 15.sp,
                                        fontWeight: FontWeight.w600),
                                  ),
                                  if (PasskeyService.creationDateForLabel(label)
                                      .isNotEmpty)
                                    Padding(
                                      padding: EdgeInsets.only(top: 2.h),
                                      child: Text(
                                        context.l10n.recoverPasskeyCreated(
                                            PasskeyService.creationDateForLabel(
                                                label)),
                                        style: TextStyle(
                                          fontSize: 12.sp,
                                          fontWeight: FontWeight.w400,
                                          color: c.textSecondary,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).then((_) {
      // Dismissed without choosing a wallet.
      if (!picked) _trackPasskeyRestoreCancelled('pick');
    });
  }

  /// Restore the chosen wallet(s). [credentialId] is the credential the
  /// discovery sign-in resolved: the confirmation ceremony is pinned to it
  /// so a different passkey can never answer for this wallet. [trigger] is
  /// 'auto' when discovery found a single wallet and no one tapped.
  Future<void> _restoreFromPasskeys(List<String> labels,
      {Uint8List? credentialId, String trigger = 'tap'}) async {
    if (!mounted) return;
    setState(() => _restoringPasskey = true);
    try {
      for (final label in labels) {
        RestoreFlowAnalytics.step('passkey_confirm',
            method: 'passkey', trigger: trigger);
        if (mounted) setState(() => _confirmingLabel = label);
        // legacy: false — labels here came from the new SDK's discovery
        // sign-in (Nostr), so this restore is by definition the new-SDK
        // path (legacy pre-2.x wallets never published labels and can't
        // appear in this picker).
        final pkWallet = await PasskeyService.getWallet(
            label: label, legacy: false, credentialId: credentialId);
        await PasskeyService.cacheLabel(label);
        final walletId =
            '${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(1000)}';
        final name = PasskeyService.displayNameForLabel(label);
        final config = WalletConfig(
          id: walletId,
          name: name,
          sparkEnabled: true,
          backedUp: true,
          isPasskey: true,
          isRestore: true,
          // Store the label so this wallet re-derives ITS OWN seed
          // (resolveBip39MnemonicFor passes wallet.passkeyLabel). Without
          // it, multi-wallet restores would all fall back to the cached
          // label and resolve the wrong seed.
          passkeyLabel: label,
          // VINTAGE STAMP: restored through the 0.17.1 PasskeyClient
          // (getWallet above), so seed resolution stays on the new SDK
          // path. Stamped ONLY on this new-SDK restore — a legacy
          // (pre-2.x) wallet restored any other way must keep null and
          // route through PasskeyService.getLegacySeed.
          passkeyProvider: 'breez-0.17',
          evmDerivationVersion: passkeyEvmDerivationVersion(label),
        );
        await ref.read(settingsProvider.notifier).addWallet(config);
        TrackingService.walletAdded(
          walletKind: 'hot',
          importMethod: 'passkey',
          network: 'spark',
          source: ref.read(settingsProvider).wallets.length == 1
              ? 'onboarding'
              : 'add_wallet',
        );
        // Every passkey wallet is a spending wallet now, so provision
        // Polymarket for the restored wallet (matches creation). The REAL
        // mnemonic string is required here: `seed.toString()` is a debug
        // representation and silently broke provisioning.
        final mnemonic = await PasskeyService.mnemonicOfSeed(pkWallet.seed);
        if (mnemonic != null) {
          RecoveryCheck.record(
              ref.read(settingsProvider.notifier), walletId, mnemonic);
          Future.delayed(const Duration(seconds: 5), () {
            provisionPolymarketAccount(
              mnemonic: mnemonic,
              walletId: walletId,
              evmDerivationVersion: config.evmDerivationVersion,
            );
          });
        }
      }
      TrackingService.walletCreated(type: 'imported', authMode: 'passkey');
      RestoreFlowAnalytics.completed();
      if (ref.read(settingsProvider).wallets.length == 1) {
        TrackingService.onboardingCompletedOnce(authMode: 'recovered');
      }
      ref.invalidate(bitcoinConfigProvider);
      if (mounted) {
        ref.read(recoveryModeProvider.notifier).state = false;
        context.go('/home');
      }
    } catch (e) {
      if (e.toString().toLowerCase().contains('cancel')) {
        _trackPasskeyRestoreCancelled('restore');
      } else {
        _trackPasskeyRestoreFailed('restore', e);
      }
      if (mounted) {
        showMessageSnackBar(
          context: context,
          message: context.l10n.recoverChoicePasskeyRestoreFailed,
          error: true,
        );
        setState(() {
          _restoringPasskey = false;
          _confirmingLabel = null;
        });
      }
    }
  }

  /// Legacy (pre-2.x) recovery. Runs when the new-SDK Nostr list is empty.
  /// Rebuilds the seed the 0.15.1 way for each plausible label, probes
  /// each candidate's on-chain balance + history, and only surfaces
  /// wallets that are demonstrably REAL (funded or with payment history)
  /// — an empty, historyless derivation is a phantom and is never shown.
  Future<void> _attemptLegacyRecovery() async {
    List<LegacyPasskeyCandidate> candidates;
    try {
      candidates = await PasskeyRecovery.probeLegacyCandidates();
    } catch (e) {
      // Cancelled biometric = user backing out, don't nag.
      if (e.toString().toLowerCase().contains('cancel')) {
        _trackPasskeyRestoreCancelled('legacy_probe');
        return;
      }
      _trackPasskeyRestoreFailed('legacy_probe', e);
      if (!mounted) return;
      showMessageSnackBar(
        context: context,
        message: context.l10n.recoverChoicePasskeyLookupFailed,
        error: true,
      );
      return;
    }
    if (!mounted) return;
    if (candidates.isEmpty) {
      TrackingService.track('passkey_restore_failed',
          params: {'stage': 'no_wallet_found'});
      showMessageSnackBar(
        context: context,
        message: context.l10n.recoverChoiceNoPasskeyWallet,
        error: false,
      );
      return;
    }
    _showLegacyCandidateSheet(candidates);
  }

  /// Confirm sheet for legacy candidates. Shows the balance and payment
  /// count so the user verifies it's really their wallet before we adopt
  /// it — the safeguard the always-one-spending-wallet architecture needs
  /// against silently restoring the wrong (empty) seed.
  void _showLegacyCandidateSheet(List<LegacyPasskeyCandidate> candidates) {
    final c = context.colors;
    final l10n = context.l10n;
    RestoreFlowAnalytics.step('legacy_pick', method: 'passkey');
    var picked = false;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.surface,
      // Scrollable, matching _showLabelPicker: long candidate lists must
      // never push entries off screen.
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.7,
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 24.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  candidates.length == 1
                      ? l10n.recoverPickWalletOne
                      : l10n.recoverPickWalletMany,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 6.h),
                Text(
                  context.l10n.recoverFoundOnDevice,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 13.sp,
                    height: 1.3,
                  ),
                ),
                SizedBox(height: 14.h),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final cand in candidates)
                          Padding(
                            padding: EdgeInsets.only(bottom: 8.h),
                            child: ElevatedButton(
                              onPressed: () {
                                picked = true;
                                Navigator.of(ctx).pop();
                                _adoptLegacyCandidate(cand);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: c.surfaceLight,
                                foregroundColor: c.textPrimary,
                                minimumSize: Size.fromHeight(56.h),
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.lg),
                                ),
                                elevation: 0,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    PasskeyService.displayNameForLabel(
                                        cand.effectiveLabel),
                                    style: TextStyle(
                                        fontSize: 15.sp,
                                        fontWeight: FontWeight.w700),
                                  ),
                                  SizedBox(height: 2.h),
                                  Text(
                                    _candidateSubtitle(cand),
                                    style: TextStyle(
                                      fontSize: 12.sp,
                                      fontWeight: FontWeight.w500,
                                      color: c.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).then((_) {
      if (!picked) _trackPasskeyRestoreCancelled('legacy_pick');
    });
  }

  /// "12,345 sats · 8 transactions" — the two signals that tell this
  /// wallet apart from an empty phantom.
  String _candidateSubtitle(LegacyPasskeyCandidate cand) {
    final format = ref.read(settingsProvider).btcFormat;
    final amount =
        '${cand.balanceSats.toFormattedString(format)} ${format == 'sats' ? 'sats' : 'BTC'}';
    return context.l10n.recoveryCandidateBalance(amount, cand.paymentCount);
  }

  /// Persist a confirmed legacy candidate as the restored spending
  /// wallet, stamped `passkeyProvider: null` so all seed resolution
  /// (connect, getMnemonic) routes through the 0.15.1 PRF pipeline —
  /// NEVER the new-SDK signIn, which could resolve a different,
  /// fund-losing credential on the shared RP.
  Future<void> _adoptLegacyCandidate(LegacyPasskeyCandidate cand) async {
    if (!mounted) return;
    setState(() => _restoringPasskey = true);
    try {
      await PasskeyService.cacheLabel(cand.effectiveLabel);
      final walletId =
          '${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(1000)}';
      final config = WalletConfig(
        id: walletId,
        name: PasskeyService.displayNameForLabel(cand.effectiveLabel),
        sparkEnabled: true,
        backedUp: true,
        isPasskey: true,
        isRestore: true,
        // Pin the EXACT salt this seed derived from so connect and
        // getMnemonic re-derive it byte-identically every time.
        passkeyLabel: cand.effectiveLabel,
        // VINTAGE: null = legacy (pre-2.x). Keeps seed resolution on
        // PasskeyService.getLegacySeed, never the new-SDK path.
        passkeyProvider: null,
      );
      await ref.read(settingsProvider.notifier).addWallet(config);
      TrackingService.walletAdded(
        walletKind: 'hot',
        importMethod: 'passkey',
        network: 'spark',
        source: ref.read(settingsProvider).wallets.length == 1
            ? 'onboarding'
            : 'add_wallet',
      );
      RecoveryCheck.record(
          ref.read(settingsProvider.notifier), walletId, cand.mnemonic);
      // Provision Polymarket for the restored spending wallet, matching
      // creation. Uses the mnemonic the probe already extracted, so no
      // extra biometric ceremony here.
      Future.delayed(const Duration(seconds: 5), () {
        provisionPolymarketAccount(
          mnemonic: cand.mnemonic,
          walletId: walletId,
          evmDerivationVersion: config.evmDerivationVersion,
        );
      });
      TrackingService.walletCreated(type: 'imported', authMode: 'passkey');
      RestoreFlowAnalytics.completed();
      if (ref.read(settingsProvider).wallets.length == 1) {
        TrackingService.onboardingCompletedOnce(authMode: 'recovered');
      }
      ref.invalidate(bitcoinConfigProvider);
      if (mounted) {
        ref.read(recoveryModeProvider.notifier).state = false;
        context.go('/home');
      }
    } catch (e) {
      _trackPasskeyRestoreFailed('legacy_adopt', e);
      if (mounted) {
        showMessageSnackBar(
          context: context,
          message: context.l10n.recoverChoicePasskeyRestoreFailed,
          error: true,
        );
        setState(() => _restoringPasskey = false);
      }
    }
  }

  void _handleSeedChoice() {
    HapticFeedback.lightImpact();
    TrackingService.track('recover_choice_seed_tapped');
    // The seed screen reports the `seed_entry` restore step on mount.
    context.go('/recover_wallet/seed');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final busy = _checkingPasskey || _restoringPasskey;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        // The title moves into the body below. It was an 18sp app bar
        // line, so the one question this screen asks was the smallest
        // text on it, while its sibling screen in the same flow states
        // its question at 28 in the middle of the page.
        leading: busy
            ? null
            : KuteBackButton(
                fallbackRoute: '/start',
                onBack: () async =>
                    RestoreFlowAnalytics.abandoned(reason: 'back'),
              ),
        automaticallyImplyLeading: false,
      ),
      body: PlatformSafeArea(
        child: Stack(
          children: [
            LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight),
                    child: IntrinsicHeight(
                      child: Padding(
                        // The greater of a comfortable gap and the
                        // home-indicator inset, never both: PlatformSafeArea
                        // leaves the bottom to the screen on iOS.
                        padding: EdgeInsets.fromLTRB(
                            24.w,
                            16.h,
                            24.w,
                            math.max(
                                16.h, MediaQuery.of(context).padding.bottom)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Same header shape as the passkey screen it
                            // sits beside in this flow: a mark, the
                            // question, then the explanation.
                            Center(
                              child: Container(
                                width: 80.w,
                                height: 80.w,
                                decoration: AppDecorations.card(context),
                                child: Icon(Icons.restore_rounded,
                                    size: 40.sp, color: c.textPrimary),
                              ),
                            ),
                            SizedBox(height: 24.h),
                            Text(
                              l10n.recoverAccount,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: c.textPrimary,
                                fontSize: 28.sp,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.6,
                                height: 1.05,
                              ),
                            ),
                            SizedBox(height: 10.h),
                            Text(
                                _confirmingLabel == null
                                    ? l10n.recoveryMethodDescription
                                    : l10n.recoverConfirmWallet(
                                        PasskeyService.displayNameForLabel(
                                            _confirmingLabel!)),
                                textAlign: TextAlign.center,
                                style: AppTextStyles.bodySmall(context)
                                    .copyWith(height: 1.5)),
                            // Sal on the trail: the empty middle of this
                            // screen is where the account is about to be
                            // found (user decision: Sal everywhere).
                            Expanded(
                              child: Center(
                                child: ExcludeSemantics(
                                  child: KuteDogAtWork(
                                    width: 250.w,
                                    ink: c.textPrimary,
                                    accent: c.accent,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(height: 32.h),
                            AppButton(
                              text: l10n.recoverWithPhrase,
                              icon: Icons.password_rounded,
                              height: 60.h,
                              fontSize: 17.sp,
                              onPressed: busy ? null : _handleSeedChoice,
                            ),
                            SizedBox(height: 12.h),
                            AppButton(
                              text: l10n.recoverWithAccount(Platform.isIOS
                                  ? l10n.passkeyChoiceAppleAccount
                                  : l10n.passkeyChoiceGoogleAccount),
                              icon: Icons.fingerprint_rounded,
                              height: 60.h,
                              variant: AppButtonVariant.secondary,
                              isOutlined: true,
                              onPressed: busy ? null : _handlePasskeyChoice,
                              // The passkey lookup and restore wait here,
                              // on the button, not behind a full-screen
                              // overlay over this page.
                              isLoading: _checkingPasskey || _restoringPasskey,
                            ),
                          ],
                        ),
                      ),
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
