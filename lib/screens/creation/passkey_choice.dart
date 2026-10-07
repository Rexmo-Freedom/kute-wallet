import 'package:kute/services/evm_derivation_policy.dart';
import 'package:kute/models/evm_derivation_version.dart';
import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:kute/services/secure/recovery_check.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/services/passkey_prf_service.dart';
import 'package:kute/providers/bitcoin_config_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/creation/set_pin.dart' show trackOnboardingStep;
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/message_display.dart';
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

  const PasskeyChoice({super.key, required this.nextRoute});

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
    final auth = LocalAuthentication();
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
        try {
          await _createPasskeyWallet();
          TrackingService.track('passkey_choice_passkey_selected');
        } catch (e) {
          // User backed out of the OS passkey sheet → create NOTHING.
          // Previously every error (cancel included) silently fell back
          // to a BIP39 wallet, so cancelling still produced a wallet
          // (and the spinner hung). Stop here: reset and let the user
          // retry or flip the toggle off themselves.
          if (_isUserCancelled(e)) {
            TrackingService.track('passkey_choice_cancelled');
            if (mounted) {
              setState(() => _isProcessing = false);
              showMessageSnackBar(
                context: context,
                message: context.l10n.passkeyChoiceCancelled,
                error: false,
                info: true,
              );
            }
            return;
          }
          // Genuine failure / platform unsupported (no PRF, no native
          // handler, broken RP association). Don't trap the user: fall
          // back to BIP39 and tell them via a snackbar. The typed mint
          // gate inside _createPasskeyWallet already ran, so a failure
          // lands here as a recovery-phrase wallet, never as a second
          // minted credential on the shared RP.
          TrackingService.track('passkey_choice_fallback_bip');
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
        }
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

  /// True when the error is the user dismissing the OS passkey ceremony
  /// (as opposed to a real failure or an unsupported platform). Typed
  /// check first (`PasskeyError.prf(userCancelled)` on the 0.23 SDK),
  /// then the legacy channel's `USER_CANCELLED` / message fallback.
  bool _isUserCancelled(Object e) {
    if (e is PlatformException && e.code == 'USER_CANCELLED') return true;
    return PasskeyService.isUserCancelledError(e);
  }

  Future<void> _createPasskeyWallet() async {
    // ONE passkey, MANY wallets. Breez derives a DISTINCT deterministic
    // seed per label off the same passkey (seed = f(PRF, label)), so we
    // register a credential only ONCE per device and derive every new
    // wallet under a fresh, unique label on it. That way a single
    // recover-side discovery sign-in returns ALL of the user's wallets in
    // one picker to choose from — instead of one indistinguishable passkey
    // per wallet.
    //
    // 1. Every wallet gets a UNIQUE label (`Spending Wallet · <epochMs>`), so
    //    creating a wallet ALWAYS produces a fresh seed — deleting and
    //    recreating never reuses an old wallet. (We dropped the deterministic
    //    'Default' label precisely because it made "create new" reproduce the
    //    old wallet.) The timestamp also encodes the creation date the recover
    //    picker renders.
    //    The user-chosen label rides in front of the timestamp
    //    (`<label> · <epochMs>`), so custom names stay unique per creation
    //    and flow into the recover picker via displayNameForLabel.
    final createdAtMs = DateTime.now().millisecondsSinceEpoch;
    final walletId = '$createdAtMs-${Random().nextInt(1000)}';
    final label = standardEvmPasskeyLabel(PasskeyService.newWalletLabel(
      name: _walletLabel,
      createdAtMs: createdAtMs,
    ));
    final name = PasskeyService.displayNameForLabel(label);

    // 2 & 3. Reuse an existing passkey if there is one — even across app
    //    reinstalls/wipes, because the passkey lives in iCloud Keychain /
    //    Google, not in our local state. We try getWallet(label) FIRST: it
    //    asserts WHATEVER passkey exists (so it only prompts "sign in") and
    //    derives this label's seed. ONLY if no passkey resolves do we register
    //    one. This stops "create new wallet" from adding a SECOND passkey
    //    every time local state is fresh — the cause of the "add a passkey"
    //    prompt on every create. Keeps it to ONE passkey per Apple/Google
    //    account without depending on a local flag we can't trust after a wipe.
    final pkWallet = await () async {
      try {
        // Existing passkey → derive this label's seed (breez signIn()).
        // legacy: false — this is the CREATE flow on the new-SDK client
        // (v0.23.0; the persisted vintage tag stays 'breez-0.17'); the
        // config below is stamped 'breez-0.17' to match. getWallet
        // pins to the stored 0.17 credential when one exists, retries
        // with the hybrid (cross-device) flow enabled before concluding
        // "no passkey", and persists whatever resolved so future signIns
        // pin to that exact credential.
        return await PasskeyService.getWallet(label: label, legacy: false);
      } catch (e) {
        // A cancelled ceremony bubbles up (handled by _continue's catch).
        if (_isUserCancelled(e)) rethrow;
        // ONLY the typed "no credential resolved" verdict may mint. The
        // old string gate ('does not contain cancel') let timeouts, auth
        // failures, and ceremony collisions fall through to register(),
        // silently minting a SECOND credential on the shared RP — which
        // forks the Nostr label identity and hides every wallet created
        // under the first credential (the recovery regression).
        if (!PasskeyService.isCredentialNotFoundError(e)) rethrow;
        // Even then: a device that provably holds the old (0.15.1-era)
        // credential must never mint. Reaching this point with legacy
        // signals present means the ceremony route failed abnormally;
        // rethrow, which lands on _continue's BIP39 fallback — the user
        // gets a recovery-phrase wallet instead of a second credential
        // that would fork the account's identity.
        final legacyPin = await PasskeyPrfService.pinnedCredentialId();
        final hasLegacy = legacyPin != null ||
            await PasskeyPrfService.hasRegisteredCredential();
        if (hasLegacy) {
          TrackingService.track('passkey_create_mint_blocked');
          rethrow;
        }
        // No passkey anywhere on this account — mint one AND derive the
        // seed in a single register() ceremony (breez register(), with
        // excludeCredentials populated from every known id). The user's
        // label becomes the credential's OS-visible display name so the
        // Keychain / Password Manager entry matches the in-app wallet.
        return await PasskeyService.createWallet(
          label: label,
          userDisplayName: name,
        );
      }
    }();

    // 4. Cache the label locally for fast SDK reconnects, then publish it to
    //    Nostr (awaited + retried) so the wallet is discoverable in the
    //    recover picker on the user's other devices. Every wallet is
    //    Nostr-discovered now (no deterministic 'Default' shortcut), so this
    //    landing reliably is what makes recovery work.
    await PasskeyService.cacheLabel(label);
    await PasskeyService.storeLabel(label);

    // 5. Persist the WalletConfig with its unique passkey label.
    //    `backedUp: true` because the passkey IS the backup; there
    //    is no seed to write down.
    final config = WalletConfig(
      id: walletId,
      name: name,
      sparkEnabled: true,
      evmDerivationVersion: EvmDerivationVersion.standardBip39,
      backedUp: true,
      isPasskey: true,
      passkeyLabel: label,
      // VINTAGE STAMP: created through the 0.17.1 PasskeyClient, so
      // every future seed resolution routes through the new SDK path.
      // (Legacy pre-2.x wallets carry null here and reconstruct via
      // PasskeyService.getLegacySeed instead.)
      passkeyProvider: 'breez-0.17',
    );
    await ref.read(settingsProvider.notifier).addWallet(config);
    TrackingService.walletCreated(type: 'hot', authMode: 'passkey');
    TrackingService.walletAdded(
      walletKind: 'hot',
      importMethod: 'passkey',
      network: 'spark',
      source: 'onboarding',
    );

    // 6. Provision Polymarket in the background. The passkey-derived
    //    seed plugs into the same Safe derivation as BIP39. The REAL
    //    mnemonic string is required: `seed.toString()` is a debug
    //    representation and silently broke provisioning at creation
    //    (it self-healed later from the Polymarket screen).
    final polymarketMnemonic =
        await PasskeyService.mnemonicOfSeed(pkWallet.seed);
    if (polymarketMnemonic != null) {
      RecoveryCheck.record(
          ref.read(settingsProvider.notifier), walletId, polymarketMnemonic);
      Future.delayed(const Duration(seconds: 5), () {
        provisionPolymarketAccount(
          mnemonic: polymarketMnemonic,
          walletId: walletId,
          evmDerivationVersion: config.evmDerivationVersion,
        );
      });
    }
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
    );
    await ref.read(settingsProvider.notifier).addWallet(config);
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
