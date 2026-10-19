import 'package:kute/services/evm_derivation_policy.dart';
import 'package:kute/models/evm_derivation_version.dart';
import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' show Wallet;
import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:kute/services/secure/recovery_check.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/breez/sdk_instance.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/services/passkey_prf_service.dart';
import 'package:kute/providers/bitcoin_config_provider.dart';
import 'package:kute/providers/breez_config_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/creation/set_pin.dart' show trackOnboardingStep;
import 'package:kute/screens/shared/custom_alert_dialog.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/screens/shared/receive_surface.dart' show ReceiveCaption;
import 'package:kute/helpers/user_error_copy.dart';
import 'package:kute/helpers/passkey_account_name.dart';
import 'package:kute/services/passkey_service.dart';
import 'package:local_auth/local_auth.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/wallet_identity_service.dart';
import 'package:kute/theme/app_theme.dart';

/// Post-PIN screen presented when the user is creating a NEW wallet
/// (not when restoring from seed). Toggle defaults ON when the
/// device supports WebAuthn PRF — in which case the user gets a
/// passkey wallet (biometric-gated, nothing to write down, syncs via
/// iCloud Keychain / Google Password Manager). Toggle OFF, or
/// passkey unsupported → standard BIP39 wallet with manual backup.
///
/// This screen OWNS wallet creation now. Earlier the work happened
/// in `confirm_pin.dart` and this screen just toggled a backup flag;
/// to let the user pick BEFORE we commit to either storage class we
/// moved the work here.
///
/// Route param `extra` is a `String` — the next path after the wallet
/// is committed (typically `/beta_survey` for fresh installs).
class PasskeyChoice extends ConsumerStatefulWidget {
  final String nextRoute;

  /// Test seams: the OS ceremonies and side effects behind passkey
  /// creation, and the biometrics probe. Production leaves both null.
  @visibleForTesting
  final PasskeyCeremonies? ceremonies;
  @visibleForTesting
  final LocalAuthentication? localAuth;

  const PasskeyChoice({
    super.key,
    required this.nextRoute,
    this.ceremonies,
    this.localAuth,
  });

  @override
  ConsumerState<PasskeyChoice> createState() => _PasskeyChoiceState();
}

class _PasskeyChoiceState extends ConsumerState<PasskeyChoice> {
  /// Live toggle state. Defaults ON when the device reports biometric
  /// capability. Locked OFF (and disabled) on devices that can't —
  /// simulators without Face ID enrolled, hardware without a passcode
  /// set, etc.
  bool _useBiometrics = true;
  bool _isProcessing = false;

  /// Default wallet label. Kept as the literal every other creation path
  /// uses ('Spending Wallet', English on purpose — persisted wallet names
  /// never vary by locale) so an untouched field behaves exactly like
  /// the pre-label flow.
  static const String _defaultLabel = 'Spending Wallet';

  /// User-editable wallet label. Doubles as the passkey display name in
  /// the OS sheet (create flow) and the in-app wallet name, so the two
  /// always match. Continue is disabled while it is blank.
  final TextEditingController _labelController =
      TextEditingController(text: _defaultLabel);

  /// `true` once we've confirmed the device supports biometrics.
  /// `false` once we've confirmed it doesn't. `null` while probing.
  bool? _biometricsAvailable;

  /// Which unlock method the device reports, for the one term the screen
  /// uses (Face ID, Touch ID, fingerprint or face unlock).
  bool _hasFace = false;
  bool _hasFingerprint = false;

  /// The wallet name field is folded into a quiet row until Rename.
  bool _renaming = false;

  @override
  void initState() {
    super.initState();
    // Re-render on every edit so the Continue CTA enables/disables live
    // with the trimmed-empty check.
    _labelController.addListener(() {
      if (mounted) setState(() {});
    });
    trackOnboardingStep('wallet_type', path: 'create');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      TrackingService.screenView('passkey_choice');
      _probeBiometrics();
    });
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  /// Trimmed label the user typed (may be empty; Continue guards that).
  String get _walletLabel => _labelController.text.trim();

  Future<void> _probeBiometrics() async {
    final auth = widget.localAuth ?? LocalAuthentication();
    bool available = false;
    var hasFace = false;
    var hasFingerprint = false;
    try {
      final supported = await auth.isDeviceSupported();
      final canCheck = await auth.canCheckBiometrics;
      available = supported && canCheck;
      final types = await auth.getAvailableBiometrics();
      hasFace = types.contains(BiometricType.face);
      hasFingerprint = types.contains(BiometricType.fingerprint);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _biometricsAvailable = available;
      _hasFace = hasFace;
      _hasFingerprint = hasFingerprint;
      if (!available) _useBiometrics = false;
    });
    if (!available) {
      TrackingService.track('passkey_unsupported_device');
    }
  }

  Future<void> _continue() async {
    if (_isProcessing || _walletLabel.isEmpty) return;
    setState(() => _isProcessing = true);

    // PRIVACY: emit only THAT the label was customized (plus its length
    // and which path it applies to) — never the label text itself.
    if (_walletLabel != _defaultLabel) {
      TrackingService.track('passkey_label_customized', params: {
        'length': _walletLabel.length,
        'biometrics': _useBiometrics,
      });
    }

    try {
      if (_useBiometrics) {
        final created = await _attemptPasskey(skipSignIn: false);
        // Cancelled: nothing was created and the screen already reset.
        if (!created) return;
      } else {
        await _createBip39Wallet();
        TrackingService.track('passkey_choice_bip_selected');
      }
    } catch (e, st) {
      if (!mounted) return;
      // The user reads one plain sentence. Which step failed
      // (setMnemonic / addWallet / PRF / session-PIN) goes to the console
      // in debug builds and to tracking as a coarse type, never to the
      // screen.
      if (kDebugMode) {
        // ignore: avoid_print
        print('passkey_choice _continue failed: $e\n$st');
      }
      TrackingService.walletAddFailed(reason: e.runtimeType.toString());
      TrackingService.recordHandled(TrackingService.errorCategory(e), e, st,
          flow: 'onboarding', stage: 'wallet_create');
      showMessageSnackBar(
        context: context,
        message: userErrorCopy(context, e,
            fallback: context.l10n.errorCopyCreateWallet),
        error: true,
      );
      setState(() => _isProcessing = false);
      return;
    }

    if (!mounted) return;
    // Don't re-resolve the BDK config for a passkey wallet: it uses Breez
    // Spark on-chain (no BDK), and resolving bitcoinConfig for it runs
    // PasskeyService.getWallet() → an OS biometric ceremony mid-navigation
    // that white-screened the post-create route. (BIP39 fallback wallets
    // still need the refresh.)
    final activeIsPasskey =
        ref.read(settingsProvider).activeWallet?.isPasskey ?? false;
    if (!activeIsPasskey) ref.invalidate(bitcoinConfigProvider);
    context.go(widget.nextRoute);
  }

  PasskeyCeremonies get _ceremonies =>
      widget.ceremonies ?? const PasskeyCeremonies();

  /// One passkey creation attempt, cancel handling included. Returns true
  /// when a wallet was created (passkey or, after a non-cancel failure,
  /// the recovery-phrase fallback) and false when the user cancelled and
  /// nothing was created (the screen is already reset for a retry).
  ///
  /// A cancel on the SIGN-IN sheet on a device that knows no passkey is
  /// not the end: the user is offered a fresh passkey (still minted with
  /// `excludeCredentials`), and accepting re-runs the attempt straight
  /// into the create sheet. A cancel on the CREATE sheet stops here.
  Future<bool> _attemptPasskey({required bool skipSignIn}) async {
    try {
      final result = await _createPasskeyWallet(skipSignIn: skipSignIn);
      TrackingService.track('passkey_choice_passkey_selected',
          params: result.analyticsParams);
      return true;
    } on PasskeySheetCancelled catch (e) {
      // User backed out of an OS passkey sheet → create NOTHING.
      // Previously every error (cancel included) silently fell back
      // to a BIP39 wallet, so cancelling still produced a wallet
      // (and the spinner hung). Stop here: reset and let the user
      // retry or flip the toggle off themselves.
      TrackingService.track('passkey_choice_cancelled', params: {
        'sheet': e.sheet.analyticsValue,
        'elapsed_ms': e.elapsedMs,
      });
      if (e.sheet == PasskeySheet.signIn &&
          !await _ceremonies.hasKnownCredentialOrDefault()) {
        if (!mounted) return false;
        final accepted = await _offerCreateNewPasskey();
        TrackingService.track('passkey_choice_create_new_offered',
            params: {'accepted': accepted});
        if (accepted) return _attemptPasskey(skipSignIn: true);
      }
      if (mounted) {
        setState(() => _isProcessing = false);
        showMessageSnackBar(
          context: context,
          message: context.l10n.passkeyChoiceCancelled,
          error: false,
          info: true,
        );
      }
      return false;
    } on PasskeyStepFailed catch (e) {
      // Genuine failure / platform unsupported (no PRF, no native
      // handler, broken RP association). Don't trap the user: fall
      // back to BIP39 and tell them via a snackbar. The typed mint
      // gate inside PasskeyWalletCreation already ran, so a failure
      // lands here as a recovery-phrase wallet, never as a second
      // minted credential on the shared RP.
      TrackingService.track('passkey_choice_fallback_bip', params: {
        'stage': e.stage,
        'error_category': TrackingService.errorCategory(e.cause),
      });
      await _createBip39Wallet();
      if (mounted) {
        showMessageSnackBar(
          context: context,
          message:
              context.l10n.passkeyChoiceFallbackWords(_methodName(context)),
          error: false,
          info: true,
        );
      }
      return true;
    }
  }

  /// "No passkey found" → Create a new passkey / Cancel. Resolves to
  /// whether the user chose to create one.
  Future<bool> _offerCreateNewPasskey() async {
    final l10n = context.l10n;
    var accepted = false;
    await showCustomAlertDialog(
      context: context,
      title: l10n.passkeyCreateNewTitle,
      content: l10n.passkeyCreateNewBody(_methodName(context)),
      buttons: [
        CustomAlertAction(
          text: l10n.passkeyCreateNewAction,
          onPressed: () {
            accepted = true;
            Navigator.of(context, rootNavigator: true).pop();
          },
        ),
        CustomAlertAction.secondary(
          text: l10n.cancel,
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
        ),
      ],
    );
    return accepted;
  }

  /// Runs the passkey ceremonies and saves the wallet (see
  /// [PasskeyWalletCreation] for the step order), then schedules the
  /// post-save work that is not part of creation: the recovery check
  /// record and the Polymarket provisioning.
  Future<PasskeyCreationResult> _createPasskeyWallet(
      {required bool skipSignIn}) async {
    // Every wallet gets a UNIQUE label (`<name> · <epochMs>`), so creating
    // a wallet ALWAYS produces a fresh seed — deleting and recreating
    // never reuses an old wallet. The timestamp also encodes the creation
    // date the recover picker renders (displayNameForLabel strips it).
    final createdAtMs = DateTime.now().millisecondsSinceEpoch;
    final walletId = '$createdAtMs-${Random().nextInt(1000)}';
    final label = standardEvmPasskeyLabel(PasskeyService.newWalletLabel(
      name: _walletLabel,
      createdAtMs: createdAtMs,
    ));
    final name = PasskeyService.displayNameForLabel(label);

    final settings = ref.read(settingsProvider.notifier);
    final creation = PasskeyWalletCreation(
      ceremonies: _ceremonies,
      addWallet: settings.addWallet,
      primeSpark: () => primeSparkConnect(ref),
    );
    final result = await creation.create(
      walletId: walletId,
      label: label,
      name: name,
      skipSignIn: skipSignIn,
    );
    // The wallet is saved: nothing below may fail creation (a "failed"
    // creation would be retried as a SECOND wallet under a new label).
    // Each step is reported by kind only.
    try {
      TrackingService.walletCreated(type: 'hot', authMode: 'passkey');
      TrackingService.walletAdded(
        walletKind: 'hot',
        importMethod: 'passkey',
        network: 'spark',
        source: 'onboarding',
      );
    } catch (e) {
      _trackPostSaveFailed('track', e);
    }

    // Provision Polymarket in the background. The passkey-derived
    // seed plugs into the same Safe derivation as BIP39. The REAL
    // mnemonic string is required: `seed.toString()` is a debug
    // representation and silently broke provisioning at creation
    // (it self-healed later from the Polymarket screen).
    try {
      final polymarketMnemonic =
          await PasskeyService.mnemonicOfSeed(result.wallet.seed);
      if (polymarketMnemonic != null) {
        RecoveryCheck.record(settings, walletId, polymarketMnemonic);
        _ceremonies.scheduleProvisioningOrDefault(
          mnemonic: polymarketMnemonic,
          walletId: walletId,
          evmDerivationVersion: result.config.evmDerivationVersion,
        );
      }
    } catch (e) {
      _trackPostSaveFailed('provision', e);
    }
    return result;
  }

  static void _trackPostSaveFailed(String stage, Object e) {
    TrackingService.track('passkey_create_post_save_failed', params: {
      'stage': stage,
      'error_category': TrackingService.errorCategory(e),
    });
  }

  Future<void> _createBip39Wallet() async {
    final authModel = ref.read(authModelProvider);
    if (!ref.read(sessionUnlockedProvider)) {
      throw const SeedLockedException();
    }

    final walletId =
        '${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(1000)}';
    final mnemonic = await authModel.generateMnemonic();
    TrackingService.mnemonicGenerated();
    await authModel.setMnemonic(walletId, mnemonic);

    final config = WalletConfig(
      id: walletId,
      // Same user-chosen label as the passkey path, so the name the user
      // typed sticks whichever storage class the wallet lands on.
      name: _walletLabel.isEmpty ? 'Spending Wallet' : _walletLabel,
      sparkEnabled: true,
      evmDerivationVersion: EvmDerivationVersion.standardBip39,
      backedUp: false,
      // Brand new: its balance is known to be 0 before any sync.
      createdEmpty: true,
    );
    await ref.read(settingsProvider.notifier).addWallet(config);
    // Start the Spark connect now so it runs while the user is on the
    // survey and referral screens instead of when home first watches it.
    primeSparkConnect(ref);
    RecoveryCheck.record(
        ref.read(settingsProvider.notifier), walletId, mnemonic);
    TrackingService.walletCreated(type: 'hot', authMode: 'mnemonic');
    TrackingService.walletAdded(
      walletKind: 'hot',
      importMethod: 'create',
      network: 'spark',
      source: 'onboarding',
    );

    // A brand-new seed is a new affiliate identity. Clear any affiliate
    // code/session and wallet identity cached from a previously-active
    // wallet so the onboarding share screen (and the Earn tab) re-derive
    // and re-register for THIS wallet — otherwise they surface the previous
    // wallet's code. Both self-heal by pubkey on the next authWallet.
    await AffiliateService.wipe();
    await WalletIdentityService.wipe();

    Future.delayed(const Duration(seconds: 5), () {
      provisionPolymarketAccount(
        mnemonic: mnemonic,
        walletId: walletId,
        evmDerivationVersion: config.evmDerivationVersion,
      );
    });
  }

  void _goBack() {
    if (_isProcessing) return;
    TrackingService.track('passkey_choice_back_tapped',
        params: {'biometrics': _useBiometrics});
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/start');
    }
  }

  /// The platform's own name for the unlock method: Face ID or Touch ID on
  /// iOS, fingerprint or face unlock on Android. The screen uses this one
  /// term and never says biometrics or passkey.
  String _methodName(BuildContext context) {
    final l10n = context.l10n;
    if (Platform.isIOS) {
      return _hasFace || !_hasFingerprint
          ? l10n.biometricFaceId
          : l10n.biometricTouchId;
    }
    return _hasFace && !_hasFingerprint
        ? l10n.biometricFaceUnlock
        : l10n.biometricFingerprint;
  }

  bool get _usesFace => _hasFace && (Platform.isIOS || !_hasFingerprint);

  /// The wallet name stays out of the way: one quiet row with the current
  /// name and Rename, which opens the field in place. Continue still needs
  /// a non-empty name, so the field stays open until one is submitted.
  Widget _buildNameRow(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    if (!_renaming) {
      return InkWell(
        onTap: _isProcessing
            ? null
            : () {
                HapticFeedback.selectionClick();
                TrackingService.track('passkey_choice_rename_tapped');
                setState(() => _renaming = true);
              },
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 10.h),
          child: Row(
            children: [
              Text(l10n.walletName, style: AppTextStyles.bodySmall(context)),
              SizedBox(width: 12.w),
              Expanded(
                child: Text(
                  _walletLabel.isEmpty ? _defaultLabel : _walletLabel,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body(context)
                      .copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              SizedBox(width: 10.w),
              Text(
                l10n.rename,
                style: AppTextStyles.bodySmall(context).copyWith(
                  color: c.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return TextField(
      controller: _labelController,
      enabled: !_isProcessing,
      autofocus: true,
      textInputAction: TextInputAction.done,
      textCapitalization: TextCapitalization.words,
      maxLength: 30,
      scrollPadding: EdgeInsets.only(bottom: 120.h),
      style: AppTextStyles.body(context),
      onSubmitted: (_) {
        if (_walletLabel.isNotEmpty) setState(() => _renaming = false);
      },
      decoration: InputDecoration(
        hintText: l10n.walletName,
        counterText: '',
        filled: true,
        fillColor: c.surface,
        contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: BorderSide(color: c.borderSubtle),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: BorderSide(color: c.borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          borderSide: BorderSide(color: c.accent),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final method = _methodName(context);
    final unavailable = _biometricsAvailable == false;
    final description = _biometricsAvailable == null
        ? l10n.walletsCheckingYourDevice
        : unavailable
            ? l10n.walletsNotAvailableOnDevice
            : _useBiometrics
                ? l10n.walletsNoRecoveryPhraseToManage
                : l10n.walletsWriteDown12WordsInstead;
    final account = passkeyAccountName(context);

    return PopScope(
      canPop: !_isProcessing && context.canPop(),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_isProcessing) _goBack();
      },
      child: Scaffold(
        backgroundColor: c.background,
        appBar: AppBar(
          backgroundColor: c.background,
          elevation: 0,
          leading: _isProcessing ? null : KuteBackButton(onPressed: _goBack),
          automaticallyImplyLeading: false,
        ),
        body: PlatformSafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: 24.w),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: 16.h),
                      Center(
                        child: Container(
                          width: 80.w,
                          height: 80.w,
                          decoration: AppDecorations.card(context),
                          child: Icon(
                            _usesFace
                                ? Icons.face_rounded
                                : Icons.fingerprint_rounded,
                            size: 42.sp,
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                      SizedBox(height: 24.h),
                      Text(
                        unavailable
                            ? l10n.passkeyChoiceTitleNoBiometrics
                            : l10n.passkeyChoiceTitle(method),
                        textAlign: TextAlign.center,
                        style: AppTextStyles.heading1(context),
                      ),
                      SizedBox(height: 10.h),
                      Text(
                        unavailable || !_useBiometrics
                            ? l10n.walletsWriteDown12WordsInstead
                            : l10n.passkeyChoiceSubtitle(method),
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodySmall(context)
                            .copyWith(height: 1.5),
                      ),
                      SizedBox(height: 32.h),
                      Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 16.w, vertical: 16.h),
                        decoration: AppDecorations.card(context),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(l10n.passkeyChoiceToggle(method),
                                      style: AppTextStyles.body(context)),
                                  SizedBox(height: 4.h),
                                  Text(description,
                                      style: AppTextStyles.bodySmall(context)
                                          .copyWith(height: 1.4)),
                                ],
                              ),
                            ),
                            SizedBox(width: 12.w),
                            Switch.adaptive(
                              value: _useBiometrics,
                              onChanged: !_isProcessing &&
                                      _biometricsAvailable == true
                                  ? (value) {
                                      HapticFeedback.selectionClick();
                                      if (value != _useBiometrics) {
                                        TrackingService.track(
                                            'passkey_choice_toggled',
                                            params: {'enabled': value});
                                      }
                                      setState(() => _useBiometrics = value);
                                    }
                                  : null,
                              activeTrackColor: c.accent,
                              activeThumbColor: contrastingOnColor(c.accent),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 12.h),
                      _buildNameRow(context),
                      SizedBox(height: 16.h),
                      Text(
                        _useBiometrics
                            ? l10n.passkeyChoiceFooter(account)
                            : l10n.walletsShown12WordsWarning,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodySmall(context)
                            .copyWith(height: 1.5),
                      ),
                      SizedBox(height: 24.h),
                      const Spacer(),
                      AppButton(
                        text: l10n.continueLabel,
                        isLoading: _isProcessing,
                        onPressed: _isProcessing ||
                                _walletLabel.isEmpty ||
                                _biometricsAvailable == null
                            ? null
                            : _continue,
                      ),
                      // The greater of a comfortable gap and the
                      // home-indicator inset, never both: PlatformSafeArea
                      // leaves the bottom to the screen on iOS.
                      SizedBox(
                          height: max(
                              16.h, MediaQuery.of(context).padding.bottom)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Start the Bitcoin (Spark) connection for the wallet that was just
/// saved, the same way `completeUnlock` (lib/helpers/session_unlock.dart)
/// primes it after a PIN unlock: heal a poisoned resolution (an error
/// cached while no wallet existed, or a null instance) and read the
/// provider's future so the 3–10 s connect + first sync runs while the
/// user is still on the survey and referral screens, instead of starting
/// when the home card first watches it. Never awaited, never throws.
void primeSparkConnect(WidgetRef ref) {
  final current = ref.read(breezSDKProvider);
  final asData = current is AsyncData<BreezSdkSpark> ? current : null;
  final shouldReconnect = current is AsyncError ||
      (asData != null && asData.value.instance == null);
  if (shouldReconnect) ref.invalidate(breezSDKProvider);
  ref.read(breezSDKProvider.future).then((_) {}, onError: (_) {});
}

/// The quiet "Syncing your backup…" line shown while a passkey label this
/// device created is still waiting to be published. Renders nothing when
/// nothing is pending, so it costs no layout on the ordinary path. Reuses
/// the Receive screen's caption style; no new chrome.
class PasskeyBackupSyncingNote extends StatelessWidget {
  const PasskeyBackupSyncingNote({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: PasskeyService.pendingLabels,
      builder: (context, pending, _) {
        if (pending.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: EdgeInsets.only(bottom: 8.h),
          child: ReceiveCaption(text: context.l10n.passkeyBackupSyncing),
        );
      },
    );
  }
}

/// Which OS passkey sheet a ceremony ran. Carried on the cancel analytics
/// so a dismissed "sign in" sheet (a brand-new user who had no passkey)
/// is told apart from a dismissed "create" sheet.
enum PasskeySheet {
  signIn('sign_in'),
  create('create');

  const PasskeySheet(this.analyticsValue);
  final String analyticsValue;
}

/// The user dismissed the OS sheet named by [sheet]; nothing was created.
class PasskeySheetCancelled implements Exception {
  const PasskeySheetCancelled(this.sheet, this.cause, {required this.elapsedMs});
  final PasskeySheet sheet;
  final Object cause;

  /// How long the sheet was up before the cancel.
  final int elapsedMs;

  @override
  String toString() => 'PasskeySheetCancelled(${sheet.analyticsValue})';
}

/// A passkey step failed for a reason other than a cancel; [stage] names
/// it (`sign_in`, `create`, `mint_blocked`, `save`) for the fallback
/// analytics and the console.
class PasskeyStepFailed implements Exception {
  const PasskeyStepFailed(this.stage, this.cause);
  final String stage;
  final Object cause;

  @override
  String toString() => 'PasskeyStepFailed($stage): $cause';
}

/// What one creation produced, plus the per-step timings that ride on
/// `passkey_choice_passkey_selected`.
class PasskeyCreationResult {
  const PasskeyCreationResult({
    required this.wallet,
    required this.config,
    required this.path,
    required this.signInMs,
    required this.createMs,
    required this.saveMs,
    required this.totalMs,
    this.pendingFlagged = true,
  });

  final Wallet wallet;
  final WalletConfig config;

  /// Whether the label's pending-publish flag was stored before the save.
  final bool pendingFlagged;

  /// `sign_in` (an existing passkey derived the seed), `create` (none
  /// resolved, one was minted) or `create_after_cancel` (the user
  /// dismissed the sign-in sheet and accepted a fresh passkey).
  final String path;
  final int? signInMs;
  final int? createMs;
  final int saveMs;
  final int totalMs;

  Map<String, Object> get analyticsParams => {
        'path': path,
        if (signInMs != null) 'sign_in_ms': signInMs!,
        if (createMs != null) 'create_ms': createMs!,
        'save_ms': saveMs,
        'total_ms': totalMs,
        'pending_flagged': pendingFlagged,
      };
}

/// The platform-facing pieces of passkey creation, each replaceable in
/// tests. Null fields fall through to the real services.
class PasskeyCeremonies {
  const PasskeyCeremonies({
    this.signIn,
    this.register,
    this.hasLegacyCredential,
    this.hasKnownCredential,
    this.cacheLabel,
    this.markPending,
    this.publishLabel,
    this.scheduleProvisioning,
  });

  /// Derive [label] from an existing passkey (OS sign-in sheet). Must
  /// throw the SDK's typed errors: a cancel, or `CredentialNotFound`.
  final Future<Wallet> Function(String label)? signIn;

  /// Mint a passkey named [displayName] and derive [label] from it (OS
  /// create sheet), with `excludeCredentials` from every known id.
  final Future<Wallet> Function(String label, String displayName)? register;

  /// Whether this device holds a legacy (pre-2.x) credential, which blocks
  /// minting.
  final Future<bool> Function()? hasLegacyCredential;

  /// Whether this device knows any passkey credential at all (0.17 pin or
  /// legacy signals).
  final Future<bool> Function()? hasKnownCredential;
  final Future<void> Function(String label)? cacheLabel;

  /// Store the label as pending publish, BEFORE the wallet record is
  /// written. Must throw when the flag could not be stored.
  final Future<void> Function(String label)? markPending;

  /// Start the background label publish. Never awaited by creation.
  final void Function(String label)? publishLabel;
  final void Function({
    required String mnemonic,
    required String walletId,
    required EvmDerivationVersion evmDerivationVersion,
  })? scheduleProvisioning;

  Future<Wallet> signInOrDefault(String label) => signIn != null
      ? signIn!(label)
      // Existing passkey → derive this label's seed (breez signIn()).
      // legacy: false — the CREATE flow on the new-SDK client; the config
      // is stamped 'breez-0.17' to match. getWallet pins to the stored
      // 0.17 credential when one exists and persists whatever resolved.
      // Prefer immediately available credentials: a device with no local
      // passkey fails fast with CredentialNotFound instead of showing a
      // sign-in sheet (see PasskeyService.getWallet).
      : PasskeyService.getWallet(
          label: label, legacy: false, preferImmediatelyAvailable: true);

  Future<Wallet> registerOrDefault(String label, String displayName) =>
      register != null
          ? register!(label, displayName)
          : PasskeyService.createWallet(
              label: label, userDisplayName: displayName);

  Future<bool> hasLegacyCredentialOrDefault() async {
    if (hasLegacyCredential != null) return hasLegacyCredential!();
    final legacyPin = await PasskeyPrfService.pinnedCredentialId();
    return legacyPin != null ||
        await PasskeyPrfService.hasRegisteredCredential();
  }

  Future<bool> hasKnownCredentialOrDefault() => hasKnownCredential != null
      ? hasKnownCredential!()
      : PasskeyService.hasKnownCredential();

  Future<void> cacheLabelOrDefault(String label) =>
      cacheLabel != null ? cacheLabel!(label) : PasskeyService.cacheLabel(label);

  Future<void> markPendingOrDefault(String label) => markPending != null
      ? markPending!(label)
      : PasskeyService.markLabelPendingForIdentity(label);

  void publishLabelOrDefault(String label) {
    if (publishLabel != null) {
      publishLabel!(label);
    } else {
      unawaited(
          PasskeyService.publishLabelInBackground(label, trigger: 'create'));
    }
  }

  void scheduleProvisioningOrDefault({
    required String mnemonic,
    required String walletId,
    required EvmDerivationVersion evmDerivationVersion,
  }) {
    if (scheduleProvisioning != null) {
      scheduleProvisioning!(
        mnemonic: mnemonic,
        walletId: walletId,
        evmDerivationVersion: evmDerivationVersion,
      );
      return;
    }
    Future.delayed(const Duration(seconds: 5), () {
      provisionPolymarketAccount(
        mnemonic: mnemonic,
        walletId: walletId,
        evmDerivationVersion: evmDerivationVersion,
      );
    });
  }
}

/// Passkey wallet creation, step by step, with no network on the path:
///
/// 1. Sign in first (unless [create] is told to skip it): derive the new
///    label from WHATEVER passkey the account already has, so one
///    Apple / Google account never gets a second credential, even across
///    reinstalls (the passkey lives in iCloud Keychain / Google, not in
///    local state). Asked with "prefer immediately available credentials",
///    so a device with no passkey fails fast instead of showing a sheet.
/// 2. Only the typed `CredentialNotFound` may mint; every other failure
///    surfaces (it lands on the recovery-phrase fallback). A device that
///    holds a legacy (0.15.1-era) credential never mints either
///    (`passkey_create_mint_blocked`).
/// 3. Mint + derive in one `register()` ceremony, with `excludeCredentials`
///    from every known id; the user's name becomes the credential's
///    OS-visible display name.
/// 4. Cache the label locally, flag it pending publish, then SAVE the
///    wallet with `backedUp: false`: it is backed up once its label is on
///    the relay (the settings model flips it when the publish lands), and
///    the existing reminder shows until then.
/// 5. Prime the Spark connect, then publish the label in the background:
///    creation returns while the publish is still in flight, so a slow
///    link no longer holds the spinner (`PasskeyService.publishLabel…`).
///    A label that did not land is retried after the next ceremony and
///    on app resume / unlock while the identity is primed.
///
/// ONE passkey, MANY wallets: Breez derives a DISTINCT seed per label off
/// the same passkey (seed = f(PRF, label)), so a single recover-side
/// discovery sign-in lists all of the user's wallets.
class PasskeyWalletCreation {
  PasskeyWalletCreation({
    required this.ceremonies,
    required this.addWallet,
    required this.primeSpark,
  });

  final PasskeyCeremonies ceremonies;
  final Future<void> Function(WalletConfig config) addWallet;
  final void Function() primeSpark;

  /// True when the error is the user dismissing the OS passkey ceremony
  /// (as opposed to a real failure or an unsupported platform). Typed
  /// check first (`PasskeyError.prf(userCancelled)` on the 0.23 SDK),
  /// then the legacy channel's `USER_CANCELLED` / message fallback.
  static bool isUserCancelled(Object e) {
    if (e is PlatformException && e.code == 'USER_CANCELLED') return true;
    return PasskeyService.isUserCancelledError(e);
  }

  Future<PasskeyCreationResult> create({
    required String walletId,
    required String label,
    required String name,
    bool skipSignIn = false,
  }) async {
    final total = Stopwatch()..start();
    Wallet wallet;
    String path;
    int? signInMs;
    int? createMs;

    if (skipSignIn) {
      wallet = await _register(label, name, total);
      createMs = total.elapsedMilliseconds;
      path = 'create_after_cancel';
    } else {
      final signIn = Stopwatch()..start();
      try {
        wallet = await ceremonies.signInOrDefault(label);
        signInMs = signIn.elapsedMilliseconds;
        path = 'sign_in';
      } catch (e) {
        signInMs = signIn.elapsedMilliseconds;
        if (isUserCancelled(e)) {
          throw PasskeySheetCancelled(PasskeySheet.signIn, e,
              elapsedMs: signInMs);
        }
        // ONLY the typed "no credential resolved" verdict may mint. A
        // string gate once let timeouts, auth failures and ceremony
        // collisions fall through to register(), silently minting a
        // SECOND credential on the shared RP — which forks the Nostr
        // label identity and hides every wallet created under the first
        // credential (the recovery regression).
        if (!PasskeyService.isCredentialNotFoundError(e)) {
          throw PasskeyStepFailed('sign_in', e);
        }
        if (await ceremonies.hasLegacyCredentialOrDefault()) {
          TrackingService.track('passkey_create_mint_blocked');
          throw PasskeyStepFailed('mint_blocked', e);
        }
        final create = Stopwatch()..start();
        wallet = await _register(label, name, create);
        createMs = create.elapsedMilliseconds;
        path = 'create';
      }
    }

    try {
      await ceremonies.cacheLabelOrDefault(label);
    } catch (e) {
      throw PasskeyStepFailed('save', e);
    }
    // The label is flagged pending BEFORE the record exists, so a kill
    // between the save and the publish still leaves it to be retried. A
    // flag that could not be stored is reported (by kind) and creation
    // goes on: the wallet works locally either way.
    var pendingFlagged = true;
    try {
      await ceremonies.markPendingOrDefault(label);
    } catch (e) {
      pendingFlagged = false;
      TrackingService.track('passkey_label_pending_flag_failed', params: {
        'error_category': TrackingService.errorReason(e),
      });
    }
    final config = WalletConfig(
      id: walletId,
      name: name,
      sparkEnabled: true,
      evmDerivationVersion: EvmDerivationVersion.standardBip39,
      // Not backed up until the label is on the relay: without it the
      // wallet never appears in passkey recovery on another device. The
      // settings model flips this when the publish lands
      // (PasskeyService.labelPublishedHandler); meanwhile the existing
      // backup reminder shows and a paper backup can also clear it.
      backedUp: false,
      isPasskey: true,
      passkeyLabel: label,
      // VINTAGE STAMP: created through the 0.17.1 PasskeyClient, so
      // every future seed resolution routes through the new SDK path.
      // (Legacy pre-2.x wallets carry null here and reconstruct via
      // PasskeyService.getLegacySeed instead.)
      passkeyProvider: 'breez-0.17',
      // Brand new: its balance is known to be 0 before any sync.
      createdEmpty: true,
    );
    final save = Stopwatch()..start();
    try {
      await addWallet(config);
    } catch (e) {
      throw PasskeyStepFailed('save', e);
    }
    final saveMs = save.elapsedMilliseconds;
    // Saved: from here nothing may fail creation (the caller would retry
    // it as a SECOND wallet under a new label). Reported by kind only.
    try {
      primeSpark();
    } catch (e) {
      TrackingService.track('passkey_create_post_save_failed', params: {
        'stage': 'prime_spark',
        'error_category': TrackingService.errorCategory(e),
      });
    }
    try {
      ceremonies.publishLabelOrDefault(label);
    } catch (e) {
      TrackingService.track('passkey_create_post_save_failed', params: {
        'stage': 'publish',
        'error_category': TrackingService.errorCategory(e),
      });
    }
    return PasskeyCreationResult(
      wallet: wallet,
      config: config,
      path: path,
      signInMs: signInMs,
      createMs: createMs,
      saveMs: saveMs,
      totalMs: total.elapsedMilliseconds,
      pendingFlagged: pendingFlagged,
    );
  }

  Future<Wallet> _register(String label, String name, Stopwatch sw) async {
    try {
      return await ceremonies.registerOrDefault(label, name);
    } catch (e) {
      if (isUserCancelled(e)) {
        throw PasskeySheetCancelled(PasskeySheet.create, e,
            elapsedMs: sw.elapsedMilliseconds);
      }
      throw PasskeyStepFailed('create', e);
    }
  }
}
