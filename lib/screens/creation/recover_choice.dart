import 'package:kute/screens/shared/kute_dog_rig.dart';
import 'dart:math' as math;
import 'package:kute/services/evm_derivation_policy.dart';
import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:kute/services/secure/legacy_keychain_rescue.dart';
import 'package:kute/services/secure/recovery_check.dart';
import 'package:kute/services/secure/recovery_evm_format.dart';
import 'package:kute/helpers/evm_format_settle.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/helpers/formatters/currency_formatter.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/helpers/pin_attempt_guard.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/bitcoin_config_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/creation/set_pin.dart'
    show recoveryModeProvider, trackOnboardingStep;
import 'package:kute/services/hyperliquid/hyperliquid_onboarding_service.dart';
import 'package:kute/services/passkey_recovery.dart';
import 'package:kute/services/passkey_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/custom_keypad.dart';
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
      'time_in_flow_ms': DateTime.now().difference(started).inMilliseconds,
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
  const RecoverChoiceScreen({
    super.key,
    @visibleForTesting this.rescue,
    @visibleForTesting this.chooseEvmFormat,
  });

  /// Finds wallet copies an older build left on this phone under the
  /// legacy Keychain accessibility. iOS only by default.
  final LegacyKeychainRescue? rescue;

  /// The EVM-format check a restored phrase runs through.
  final Future<RecoveryEvmChoice> Function(String mnemonic)? chooseEvmFormat;

  @override
  ConsumerState<RecoverChoiceScreen> createState() =>
      _RecoverChoiceScreenState();
}

class _RecoverChoiceScreenState extends ConsumerState<RecoverChoiceScreen> {
  bool _checkingPasskey = false;

  /// Old copies found on this phone (key names only, nothing decrypted).
  /// Listed in the picker beside the passkeys discovery finds.
  List<LegacyWalletCopy> _legacyCopies = const [];
  Future<void>? _legacyLookup;

  LegacyKeychainRescue? get _rescue => widget.rescue ??
      (defaultTargetPlatform == TargetPlatform.iOS
          ? LegacyKeychainRescue()
          : null);

  /// Predictions builds again for the restored spending wallet. Its
  /// identity watch does too; this also covers a build that ended on a
  /// placeholder (no phrase yet) for the same identity.
  void _rebuildPredictions() {
    if (!mounted) return;
    ref
      ..invalidate(polymarketTradingProvider)
      ..invalidate(polymarketBalanceProvider);
  }

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
    _legacyLookup = _lookUpLegacyCopies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _handlePasskeyChoice(trigger: 'auto');
    });
  }

  Future<void> _lookUpLegacyCopies() async {
    final rescue = _rescue;
    if (rescue == null) return;
    try {
      final scan = await rescue.scan(ref.read(settingsProvider).wallets,
          source: 'sheet', includeUnlisted: true);
      if (mounted) _legacyCopies = scan.copies;
    } catch (_) {
      // Nothing to list; the passkey and phrase paths are unaffected.
    }
  }

  bool _restoringPasskey = false;
  bool _restoringLegacy = false;

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
        // than fall through and prompt them a second time. Copies from an
        // older version still get their list: they need no ceremony.
        if (PasskeyService.isUserCancelledError(e)) {
          _trackPasskeyRestoreCancelled('lookup');
          await _legacyLookup;
          if (mounted && _legacyCopies.isNotEmpty) {
            _showLabelPicker(const [], null, legacy: _legacyCopies);
          }
          return;
        }
        // Any other new-SDK failure is non-fatal: fall through to legacy.
      }
      if (!mounted) return;
      await _legacyLookup;
      if (!mounted) return;
      final labels = discovery?.labels ?? const <String>[];
      final legacy = _legacyCopies;
      if (labels.length == 1 && legacy.isEmpty) {
        // One wallet: nothing to choose, restore it straight away. The
        // confirmation ceremony is pinned to the discovered credential.
        await _restoreFromPasskeys(labels,
            credentialId: discovery!.credentialId, trigger: 'auto');
        return;
      }
      if (labels.isNotEmpty || legacy.isNotEmpty) {
        _showLabelPicker(labels, discovery?.credentialId, legacy: legacy);
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
      if (PasskeyService.isUserCancelledError(e)) {
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
  /// architecture). [legacy] lists copies an older version of the app
  /// left on this phone, in the same rows, under their own heading.
  ///
  /// Everything the sheet shows is captured here, before it opens: the
  /// sheet outlives this screen when a restore navigates away, and the
  /// builder must never read the screen's own context then.
  void _showLabelPicker(List<String> labels, Uint8List? credentialId,
      {List<LegacyWalletCopy> legacy = const []}) {
    final c = context.colors;
    final l10n = context.l10n;
    if (labels.isNotEmpty) {
      RestoreFlowAnalytics.step('passkey_pick', method: 'passkey');
    } else {
      RestoreFlowAnalytics.step('legacy_copy_pick', method: 'seed');
    }
    final total = labels.length + legacy.length;
    final title = total == 1 ? l10n.recoverPickWalletOne : l10n.recoverPickWalletMany;
    final rows = <_PickerRow>[
      for (final label in labels)
        _PickerRow(
          title: PasskeyService.displayNameForLabel(label),
          subtitle: PasskeyService.creationDateForLabel(label).isEmpty
              ? null
              : l10n.recoverPasskeyCreated(
                  PasskeyService.creationDateForLabel(label)),
          onTap: () => _restoreFromPasskeys([label], credentialId: credentialId),
        ),
    ];
    final legacyRows = <_PickerRow>[
      for (final copy in legacy)
        _PickerRow(
          key: ValueKey('legacy-copy-${copy.walletId}'),
          title: copy.wallet?.name ?? l10n.recoverOlderVersionWallet,
          subtitle: copy.plain
              ? null
              : copy.icloud
                  ? l10n.recoverOlderVersionIcloud
                  : l10n.recoverOlderVersionNeedsPin,
          onTap: () => _restoreLegacyCopy(copy),
        ),
    ];
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
                  title,
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
                        for (final row in rows)
                          _pickerButton(ctx, c, row, () => picked = true),
                        if (legacyRows.isNotEmpty) ...[
                          if (rows.isNotEmpty) SizedBox(height: 6.h),
                          Padding(
                            padding: EdgeInsets.only(bottom: 8.h),
                            child: Text(
                              l10n.recoverOlderVersionSection,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: c.textSecondary,
                                fontSize: 13.sp,
                                height: 1.3,
                              ),
                            ),
                          ),
                          for (final row in legacyRows)
                            _pickerButton(ctx, c, row, () => picked = true),
                        ],
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

  /// One picker row, in the style every picker on this screen uses. Reads
  /// only the sheet's [ctx] and the values captured in [row].
  Widget _pickerButton(BuildContext ctx, AppColorsExtension c, _PickerRow row,
      VoidCallback markPicked) {
    return Padding(
      key: row.key,
      padding: EdgeInsets.only(bottom: 8.h),
      child: ElevatedButton(
        onPressed: () {
          markPicked();
          Navigator.of(ctx).pop();
          row.onTap();
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: c.surfaceLight,
          foregroundColor: c.textPrimary,
          minimumSize: Size.fromHeight(48.h),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          elevation: 0,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              row.title,
              style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600),
            ),
            if (row.subtitle != null)
              Padding(
                padding: EdgeInsets.only(top: 2.h),
                child: Text(
                  row.subtitle!,
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
    );
  }

  /// Restores one copy an older version left on this phone by adding a
  /// wallet next to the current ones. A plain or iCloud copy is read as
  /// is; a PIN-encrypted one tries the PIN typed this session and a stored
  /// `biometric_pin` first, then asks for the PIN that version used. The
  /// phrase is validated (BIP39, then the wallet's public data when the
  /// phone still has some) and runs through the same EVM-format check as
  /// a typed phrase. Nothing old is deleted.
  Future<void> _restoreLegacyCopy(LegacyWalletCopy copy) async {
    final rescue = _rescue;
    if (rescue == null || !mounted) return;
    const source = 'sheet';
    final era = copy.preferredEra;
    HapticFeedback.lightImpact();
    RestoreFlowAnalytics.step('legacy_copy_confirm', method: 'seed');
    setState(() => _restoringLegacy = true);
    try {
      final String? phrase;
      if (copy.needsPin) {
        phrase = await _decryptLegacyCopy(rescue, copy);
        if (phrase == null) {
          TrackingService.seedRescueFailed(
              source: source, era: era.name, reason: 'cancelled');
          return;
        }
      } else {
        phrase = await rescue.readPlain(copy);
      }
      final check = await rescue.validate(phrase, copy.wallet);
      if (!mounted) return;
      await _addWalletFromLegacyCopy(
        RecoveryCheck.normalize(phrase),
        name: copy.wallet?.name ?? context.l10n.recoverOlderVersionWallet,
        era: era,
        check: check,
      );
    } on LegacyRescueException catch (e) {
      TrackingService.seedRescueFailed(
          source: source, era: era.name, reason: e.reason.name);
      RestoreFlowAnalytics.failed(e.reason.name);
      if (mounted) {
        showMessageSnackBar(
          context: context,
          message: e.reason == LegacyRescueFailure.invalidPhrase ||
                  e.reason == LegacyRescueFailure.mismatch
              ? context.l10n.recoveryPhraseInvalid
              : context.l10n.recoverOlderVersionFailed,
          error: true,
        );
      }
    } catch (e) {
      final category = TrackingService.errorCategory(e);
      TrackingService.seedRescueFailed(
          source: source, era: era.name, reason: 'writeFailed');
      RestoreFlowAnalytics.failed(category);
      TrackingService.track('wallet_add_failed', params: {
        'reason': 'restore_failed',
        'error_code': e.runtimeType.toString(),
        'error_category': category,
      });
      if (mounted) {
        showMessageSnackBar(
          context: context,
          message: context.l10n.recoverOlderVersionFailed,
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _restoringLegacy = false);
    }
  }

  /// The phrase behind a PIN-encrypted copy, or null when the user closed
  /// the PIN sheet. Throws [LegacyRescueException] for anything but a wrong
  /// PIN.
  Future<String?> _decryptLegacyCopy(
      LegacyKeychainRescue rescue, LegacyWalletCopy copy) async {
    // Only the PIN typed this session is tried silently. The stored
    // biometric_pin is never used here: it would decrypt an old copy
    // with no PIN entry and no biometric prompt on this surface.
    final typedPin = ref.read(typedPinProvider);
    if (typedPin != null && typedPin.isNotEmpty) {
      try {
        return await rescue.readEncrypted(copy, typedPin);
      } on LegacyRescueException catch (e) {
        if (e.reason != LegacyRescueFailure.wrongPin) rethrow;
      }
    }
    if (!mounted) return null;
    final title = context.l10n.recoverOlderVersionEnterPin;
    // Wrong PINs count on the shared attempt counter like any other
    // sheet: a lockout between attempts, and the app locks at the sheet
    // threshold; this surface never wipes.
    final guard = PinAttemptGuard(ref.read(authModelProvider));
    final result = await showAppBottomSheet<Object>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (ctx) => _LegacyPinSheet(
        title: title,
        tryPin: (pin) => rescue.readEncrypted(copy, pin),
        guard: guard,
      ),
    );
    if (result is LegacyRescueException) throw result;
    if (result == _LegacyPinSheet.locked) {
      if (mounted) lockAppAfterSheetLockout(ref);
      return null;
    }
    return result is String ? result : null;
  }

  /// The same persistence a typed phrase gets in `recover_wallet.dart`:
  /// EVM-format check, V2 seed write, wallet record, recovery check
  /// address, venue provisioning, then home.
  Future<void> _addWalletFromLegacyCopy(
    String mnemonic, {
    required String name,
    required LegacyCopyEra era,
    required LegacyCopyCheck check,
  }) async {
    if (!ref.read(sessionUnlockedProvider)) {
      TrackingService.walletAddFailed(reason: 'session_locked');
      RestoreFlowAnalytics.failed('session_locked');
      showMessageSnackBar(
          context: context,
          message: context.l10n.pleaseSetUpYourPinFirst,
          error: true);
      return;
    }
    final evmChoice =
        await (widget.chooseEvmFormat ?? RecoveryEvmFormat.choose)(mnemonic);
    if (!mounted) return;
    final container = ProviderScope.containerOf(context, listen: false);
    final authModel = ref.read(authModelProvider);
    final walletId =
        '${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(1000)}';
    await authModel.setMnemonic(walletId, mnemonic);
    final config = WalletConfig(
      id: walletId,
      name: name,
      sparkEnabled: true,
      backedUp: true,
      isRestore: true,
      evmDerivationVersion: evmChoice.version,
      evmFormatCheckPending: !evmChoice.checked,
    );
    final settingsNotifier = ref.read(settingsProvider.notifier);
    await settingsNotifier.addWallet(config);
    RecoveryCheck.record(settingsNotifier, walletId, mnemonic);
    ref.invalidate(bitcoinConfigProvider);
    if (evmChoice.hyperliquidActive) {
      unawaited(HyperliquidOnboardingService.markEnabled(walletId));
    }
    _rebuildPredictions();
    // A format check that could not finish is retried in this session;
    // Predictions is set up once it settles, not before.
    if (config.evmFormatCheckPending) EvmFormatSettle.schedule(container);
    provisionPolymarketAccount(
        mnemonic: mnemonic,
        walletId: walletId,
        evmDerivationVersion: config.evmDerivationVersion,
        evmFormatPending: config.evmFormatCheckPending);

    TrackingService.recoverySeedEntered(
        evmFormat: evmChoice.analyticsValue,
        legacySignal: evmChoice.legacySignal);
    TrackingService.seedRescueRestored(
        source: 'sheet', era: era.name, check: check.name);
    TrackingService.walletCreated(type: 'imported');
    final isFirstWallet = ref.read(settingsProvider).wallets.length == 1;
    TrackingService.walletAdded(
      walletKind: 'hot',
      importMethod: 'legacy_copy',
      network: 'spark',
      source: isFirstWallet ? 'onboarding' : 'add_wallet',
    );
    if (isFirstWallet) {
      TrackingService.onboardingCompletedOnce(authMode: 'recovered');
    }
    RestoreFlowAnalytics.completed();
    if (mounted) {
      ref.read(recoveryModeProvider.notifier).state = false;
      context.go('/home');
    }
  }

  /// Restore the chosen wallet(s). [credentialId] is the credential the
  /// discovery sign-in resolved: the confirmation ceremony is pinned to it
  /// so a different passkey can never answer for this wallet. [trigger] is
  /// 'auto' when discovery found a single wallet and no one tapped.
  Future<void> _restoreFromPasskeys(List<String> labels,
      {Uint8List? credentialId, String trigger = 'tap'}) async {
    if (!mounted) return;
    setState(() => _restoringPasskey = true);
    // True once any wallet record was written: from then on a failure
    // ends the flow as a success (the wallet is listed and works).
    var savedAny = false;
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
        // addWallet returns the existing record when this label is
        // already listed (a retry after a failure past the save).
        final stored =
            await ref.read(settingsProvider.notifier).addWallet(config);
        savedAny = true;
        // Past the save, nothing may fail the restore: the wallet is
        // listed and works. Each step is reported by kind only.
        _postSave('rebuild', () => _rebuildPredictions());
        _postSave(
            'track',
            () => TrackingService.walletAdded(
                  walletKind: 'hot',
                  importMethod: 'passkey',
                  network: 'spark',
                  source: ref.read(settingsProvider).wallets.length == 1
                      ? 'onboarding'
                      : 'add_wallet',
                ));
        // Every passkey wallet is a spending wallet now, so provision
        // Polymarket for the restored wallet (matches creation). The REAL
        // mnemonic string is required here: `seed.toString()` is a debug
        // representation and silently broke provisioning.
        String? mnemonic;
        try {
          mnemonic = await PasskeyService.mnemonicOfSeed(pkWallet.seed);
        } catch (e) {
          _trackPostSaveFailed('mnemonic', e);
        }
        if (mnemonic != null) {
          final phrase = mnemonic;
          _postSave(
              'recovery_check',
              () => RecoveryCheck.record(
                  ref.read(settingsProvider.notifier), stored.id, phrase));
          Future.delayed(const Duration(seconds: 5), () {
            provisionPolymarketAccount(
              mnemonic: phrase,
              walletId: stored.id,
              evmDerivationVersion: stored.evmDerivationVersion,
            );
          });
        }
      }
      _finishPasskeyRestore();
    } catch (e) {
      if (savedAny) {
        // A later label (or a step after a save) failed: the wallets
        // saved so far are listed and work, so finish as a success.
        _trackPostSaveFailed('later_label', e);
        _finishPasskeyRestore();
        return;
      }
      if (PasskeyService.isUserCancelledError(e)) {
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

  /// The end of a passkey restore that saved at least one wallet.
  void _finishPasskeyRestore() {
    _postSave('completed', () {
      TrackingService.walletCreated(type: 'imported', authMode: 'passkey');
      RestoreFlowAnalytics.completed();
      if (ref.read(settingsProvider).wallets.length == 1) {
        TrackingService.onboardingCompletedOnce(authMode: 'recovered');
      }
    });
    _postSave('invalidate', () => ref.invalidate(bitcoinConfigProvider));
    if (mounted) {
      ref.read(recoveryModeProvider.notifier).state = false;
      context.go('/home');
    }
  }

  /// Runs one step after a wallet record was saved; a throw is reported by
  /// step and error kind only and never fails the restore.
  void _postSave(String stage, void Function() body) {
    try {
      body();
    } catch (e) {
      _trackPostSaveFailed(stage, e);
    }
  }

  void _trackPostSaveFailed(String stage, Object e) {
    TrackingService.track('passkey_restore_post_save_failed', params: {
      'stage': stage,
      'error_category': TrackingService.errorCategory(e),
    });
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
      if (PasskeyService.isUserCancelledError(e)) {
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
    // Captured before the sheet opens: its builder must not touch this
    // screen's context once a restore has navigated away.
    final format = ref.read(settingsProvider).btcFormat;
    final subtitles = {
      for (final cand in candidates)
        cand: _candidateSubtitle(cand, l10n: l10n, format: format),
    };
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
                  l10n.recoverFoundOnDevice,
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
                                    subtitles[cand]!,
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
  String _candidateSubtitle(LegacyPasskeyCandidate cand,
      {required AppLocalizations l10n, required String format}) {
    final amount =
        '${cand.balanceSats.toFormattedString(format)} ${format == 'sats' ? 'sats' : 'BTC'}';
    return l10n.recoveryCandidateBalance(amount, cand.paymentCount);
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
      _rebuildPredictions();
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
    final busy = _checkingPasskey || _restoringPasskey || _restoringLegacy;
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
                              isLoading: busy,
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

/// One row of the restore picker, captured before the sheet opens.
class _PickerRow {
  const _PickerRow({
    this.key,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  final Key? key;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
}

/// Asks for the PIN an older version used for one of its copies. Each six
/// digits run [tryPin]; a wrong PIN shakes the dots and says so, any other
/// failure closes the sheet with the exception, Cancel closes it with
/// nothing. The current PIN is not involved: this PIN only opens that copy.
class _LegacyPinSheet extends StatefulWidget {
  const _LegacyPinSheet(
      {required this.title, required this.tryPin, required this.guard});

  /// Popped as the result when the sheet reached the attempt threshold:
  /// the caller locks the app.
  static const Object locked = Object();

  final String title;
  final Future<String> Function(String pin) tryPin;

  /// Counts wrong PINs on the shared attempt counter (sheet rules: a
  /// lockout between attempts, the app locks at the threshold, no wipe).
  final PinAttemptGuard guard;

  @override
  State<_LegacyPinSheet> createState() => _LegacyPinSheetState();
}

class _LegacyPinSheetState extends State<_LegacyPinSheet>
    with SingleTickerProviderStateMixin {
  String _pin = '';
  bool _verifying = false;
  bool _wrong = false;
  int _lockoutSeconds = 0;
  Timer? _lockoutTimer;
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );
  late final Animation<double> _shakeAnim =
      Tween<double>(begin: 0, end: 24)
          .chain(CurveTween(curve: Curves.elasticIn))
          .animate(_shake)
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed) _shake.reverse();
        });

  @override
  void initState() {
    super.initState();
    _loadLockout();
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    _shake.dispose();
    super.dispose();
  }

  /// A lockout left by an earlier surface applies here too.
  Future<void> _loadLockout() async {
    try {
      final remaining = await widget.guard.lockoutRemaining();
      if (mounted && remaining > Duration.zero) _startLockout(remaining);
    } catch (_) {}
  }

  void _startLockout(Duration lockout) {
    _lockoutTimer?.cancel();
    setState(() => _lockoutSeconds = lockout.inSeconds);
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _lockoutSeconds--);
      if (_lockoutSeconds <= 0) timer.cancel();
    });
  }

  String _formatLockout(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }

  Future<void> _verify() async {
    if (_pin.length != 6 || _verifying || _lockoutSeconds > 0) return;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    setState(() => _verifying = true);
    try {
      final phrase = await widget.tryPin(_pin);
      try {
        await widget.guard.recordSuccess();
      } catch (_) {/* the counter resets on the next unlock */}
      if (mounted) Navigator.of(context).pop(phrase);
    } on LegacyRescueException catch (e) {
      if (!mounted) return;
      if (e.reason != LegacyRescueFailure.wrongPin) {
        Navigator.of(context).pop(e);
        return;
      }
      var lockout = Duration.zero;
      try {
        final outcome = await widget.guard.recordFailure(
          surface: PinSurface.sheet,
          analyticsSurface: 'legacy_copy',
        );
        if (!mounted) return;
        if (outcome.action == PinFailureAction.lockApp) {
          Navigator.of(context).pop(_LegacyPinSheet.locked);
          return;
        }
        lockout = outcome.lockout;
      } catch (_) {/* counter unavailable: the sheet still shows wrong */}
      if (!mounted) return;
      if (!reduceMotion) _shake.forward(from: 0);
      HapticFeedback.heavyImpact();
      setState(() {
        _pin = '';
        _wrong = true;
        _verifying = false;
      });
      if (lockout > Duration.zero) _startLockout(lockout);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppBottomSheetContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 28.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.w),
            child: Text(
              widget.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 22.sp,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                height: 1.1,
              ),
            ),
          ),
          if (_lockoutSeconds > 0 || _wrong) ...[
            SizedBox(height: 6.h),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 24.w),
              child: Text(
                _lockoutSeconds > 0
                    ? context.l10n.lockedForTime(_formatLockout(_lockoutSeconds))
                    : context.l10n.incorrectPin,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: c.error,
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
          SizedBox(height: 24.h),
          AnimatedBuilder(
            animation: _shakeAnim,
            builder: (context, child) => Transform.translate(
              offset: Offset(_shakeAnim.value, 0),
              child: child,
            ),
            child: PinProgressIndicator(currentLength: _pin.length),
          ),
          SizedBox(height: 24.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.w),
            child: IgnorePointer(
              ignoring: _verifying || _lockoutSeconds > 0,
              child: CustomKeypad(
                onDigitPressed: (d) {
                  if (_pin.length < 6) {
                    HapticFeedback.lightImpact();
                    setState(() {
                      _pin += d;
                      _wrong = false;
                    });
                    if (_pin.length == 6) {
                      Future.delayed(const Duration(milliseconds: 100), _verify);
                    }
                  }
                },
                onBackspacePressed: () {
                  if (_pin.isNotEmpty) {
                    HapticFeedback.lightImpact();
                    setState(() => _pin = _pin.substring(0, _pin.length - 1));
                  }
                },
              ),
            ),
          ),
          SizedBox(height: 16.h),
          AppTextButton(
            text: context.l10n.cancel,
            onPressed: () => Navigator.of(context).pop(),
          ),
          SizedBox(height: 8.h),
        ],
      ),
    );
  }
}
