import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:kute/helpers/recovery_phrase_input.dart';
import 'package:kute/helpers/secure_screen.dart';
import 'package:kute/helpers/seed_clipboard.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/helpers/formatters/currency_formatter.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/bitcoin_config_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/restart_widget.dart';
import 'package:kute/screens/creation/set_pin.dart' show recoveryModeProvider;
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/app_card.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/services/background_sync_service.dart';
import 'package:kute/services/balance_checker_service.dart';
import 'package:kute/helpers/passkey_account_name.dart';
import 'package:kute/services/passkey_service.dart';
import 'package:kute/services/secure/flutter_secret_store.dart';
import 'package:kute/services/secure/recovery_check.dart';
import 'package:kute/services/secure/secret_error_class.dart';
import 'package:kute/services/secure/secret_store.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// How the Restore wallets screen was reached.
enum RestoreSecretsReason {
  secretsMissing,
  bindingMismatch,
  storageUnavailable,
  walletUnavailable,
}

/// Set while the PIN is created from the Restore wallets screen, so
/// `confirm_pin` returns here instead of continuing onboarding.
final restoreSecretsReturnProvider =
    StateProvider<RestoreSecretsReason?>((ref) => null);

typedef PasskeyMnemonicLoader = Future<String?> Function(
    {String? label, required bool legacy});

/// Restores wallet secrets on a phone whose Hive settings arrived without
/// them (device transfer, backup restore) or whose secure storage cannot be
/// read. A re-entered phrase is matched to the existing wallet id through
/// its public recovery check address and is never written over a different
/// wallet. Beta iCloud residue is offered as a read-only source.
class RestoreSecretsScreen extends ConsumerStatefulWidget {
  const RestoreSecretsScreen({
    super.key,
    required this.reason,
    @visibleForTesting this.deriveAddress,
    @visibleForTesting this.checkBalance,
    @visibleForTesting this.loadPasskeyMnemonic,
    @visibleForTesting this.offerLegacyCopies,
    @visibleForTesting this.wipe,
  });

  final RestoreSecretsReason reason;
  final Future<String> Function(String mnemonic)? deriveAddress;

  /// Total sats found for a phrase, or null when unknown.
  final Future<int?> Function(String mnemonic)? checkBalance;
  final PasskeyMnemonicLoader? loadPasskeyMnemonic;

  /// Whether the synced (iCloud) store is checked for residue. iOS only by
  /// default: on Android both stores share one prefs file.
  final bool? offerLegacyCopies;
  final Future<void> Function()? wipe;

  @override
  ConsumerState<RestoreSecretsScreen> createState() =>
      _RestoreSecretsScreenState();
}

enum _RowStatus { checking, needsRecovery, restored }

class _RowState {
  _RowStatus status = _RowStatus.checking;
  bool legacyCopy = false;
  bool passkeyFailed = false;
  bool busy = false;
}

class _RestoreSecretsScreenState extends ConsumerState<RestoreSecretsScreen> {
  final Map<String, _RowState> _rows = {};
  bool _hasPinMaterial = true;

  Future<String> _derive(String phrase, WalletConfig wallet) =>
      widget.deriveAddress?.call(phrase) ??
      RecoveryCheck.derive(phrase, version: wallet.evmDerivationVersion);

  bool get _offerLegacyCopies =>
      widget.offerLegacyCopies ?? defaultTargetPlatform == TargetPlatform.iOS;

  static String _v2Key(String walletId) => 'v2:wallet:$walletId.mnemonic';

  @override
  void initState() {
    super.initState();
    TrackingService.seedRestoreScreenShown(reason: widget.reason.name);
    TrackingService.setFlowContext(flow: 'seed_restore', step: 'choice');
    _probe();
  }

  WalletConfig? _wallet(String id) =>
      ref.read(settingsProvider).wallets.where((w) => w.id == id).firstOrNull;

  Future<bool> _present(SecretStore store, String key) async =>
      await store.read(key: key) is SecretPresent;

  Future<void> _probe() async {
    final local = SecretStores.local;
    final synced = SecretStores.synced;
    final pinHash = await local.read(key: 'pin_hash');
    final legacyPin = await local.read(key: 'pin');
    _hasPinMaterial = pinHash is! SecretAbsent || legacyPin is! SecretAbsent;

    for (final wallet in ref.read(settingsProvider).wallets) {
      final row = _rows.putIfAbsent(wallet.id, _RowState.new);
      if (!mounted) return;
      if (wallet.isPasskey) {
        row.status = _RowStatus.needsRecovery;
      } else if (!RecoveryCheck.holdsStoredSeed(wallet)) {
        final key = wallet.isExternalAddress
            ? 'external_address_${wallet.id}'
            : 'xpub_${wallet.id}';
        row.status = await _present(local, key)
            ? _RowStatus.restored
            : _RowStatus.needsRecovery;
      } else if (await _present(local, _v2Key(wallet.id)) ||
          (widget.reason != RestoreSecretsReason.secretsMissing &&
              await _present(local, 'mnemonic_${wallet.id}'))) {
        row.status = _RowStatus.restored;
      } else {
        row.status = _RowStatus.needsRecovery;
        if (_offerLegacyCopies) {
          final residue = await synced.read(key: _v2Key(wallet.id));
          if (residue is SecretPresent && residue.value.isNotEmpty) {
            final stored = wallet.recoveryCheckAddress;
            row.legacyCopy = stored == null ||
                RecoveryCheck.matches(
                    stored, await _safeDerive(residue.value, wallet));
          }
        }
      }
      if (mounted) setState(() {});
    }
  }

  Future<String> _safeDerive(String mnemonic, WalletConfig wallet) async {
    try {
      return await _derive(mnemonic, wallet);
    } catch (_) {
      return '';
    }
  }

  void _setBusy(String walletId, bool busy) {
    if (!mounted) return;
    setState(() => _rows[walletId]?.busy = busy);
  }

  void _markRestored(String walletId) {
    if (!mounted) return;
    setState(() {
      final row = _rows[walletId];
      if (row == null) return;
      row
        ..status = _RowStatus.restored
        ..busy = false
        ..legacyCopy = false;
    });
  }

  Future<void> _enterPhrase(WalletConfig wallet) async {
    final phrase = await showAppBottomSheet<String>(
      context: context,
      builder: (_) => _PhraseSheet(walletName: wallet.name),
    );
    if (phrase == null) {
      // The phrase sheet was closed without submitting.
      TrackingService.track('seed_restore_cancelled',
          params: {'method': 'phrase'});
      return;
    }
    if (!mounted) return;
    TrackingService.seedRestoreStarted(method: 'phrase');
    TrackingService.setFlowStep('phrase');
    _setBusy(wallet.id, true);
    try {
      await _restoreWithPhrase(wallet.id, RecoveryCheck.normalize(phrase));
    } finally {
      _setBusy(wallet.id, false);
    }
  }

  Future<void> _restoreWithPhrase(String walletId, String phrase) async {
    final auth = ref.read(authModelProvider);
    if (!await auth.validateMnemonic(phrase)) {
      _trackRestoreFailed('phrase', 'invalid_phrase');
      if (mounted) {
        showMessageSnackBar(
            context: context,
            message: context.l10n.recoveryPhraseInvalid,
            error: true);
      }
      return;
    }
    final wallet = _wallet(walletId);
    if (wallet == null || !mounted) return;
    final derived = await _derive(phrase, wallet);
    if (!mounted || _wallet(walletId) == null) return;
    final stored = wallet.recoveryCheckAddress;

    if (stored != null && !RecoveryCheck.matches(stored, derived)) {
      _trackRestoreFailed('phrase', 'mismatch');
      _setBusy(walletId, false);
      await _showMismatch();
      return;
    }
    if (stored == null) {
      final local = await SecretStores.local.read(key: _v2Key(walletId));
      if (local is SecretPresent &&
          RecoveryCheck.normalize(local.value) != phrase) {
        _trackRestoreFailed('phrase', 'mismatch');
        _setBusy(walletId, false);
        await _showMismatch();
        return;
      }
      final sats = await (widget.checkBalance ?? _checkBalance)(phrase);
      if (!mounted) return;
      final amount = sats == null
          ? context.l10n.restoreBalanceUnknown
          : '${sats.toFormattedString(ref.read(settingsProvider).btcFormat)} ${ref.read(settingsProvider).btcFormat == 'sats' ? 'sats' : 'BTC'}';
      _setBusy(walletId, false);
      final confirmed = await _choose(
        body: context.l10n.restorePhraseUnverified(wallet.name, amount),
        confirm: context.l10n.confirm,
      );
      if (!confirmed) _trackRestoreFailed('phrase', 'declined');
      if (!confirmed || !mounted) return;
      _setBusy(walletId, true);
    }

    if (!await _writeSeed(walletId, phrase)) return;
    if (stored == null) {
      await ref
          .read(settingsProvider.notifier)
          .setRecoveryCheckAddress(walletId, derived);
    }
    _markRestored(walletId);
    TrackingService.seedRestoreCompleted(
        method: 'phrase', matched: stored != null);
    if (mounted && stored != null) {
      // The same confirmation every money moment ends on: one check, one
      // line, Done. Done only pops the overlay; the row behind it already
      // reads restored and other wallets may still be waiting.
      final rootNav = Navigator.of(context, rootNavigator: true);
      pushKuteSuccessOverlay(
        navigator: rootNav,
        overlay: KuteConfirmation(
          message: context.l10n.confirmationWalletRecovered,
          detail: context.l10n.restorePhraseMatch(wallet.name),
          onDone: () => rootNav.pop(),
        ),
      );
    }
  }

  /// Writes the V2 copy for [walletId] unless a synced copy with the same
  /// phrase already serves it. Nothing is ever deleted.
  Future<bool> _writeSeed(String walletId, String phrase) async {
    final synced = await SecretStores.synced.read(key: _v2Key(walletId));
    if (synced is SecretPresent &&
        RecoveryCheck.normalize(synced.value) == phrase) {
      return true;
    }
    while (true) {
      try {
        await ref.read(authModelProvider).setMnemonicV2(walletId, phrase);
        return true;
      } catch (error) {
        if (!mounted) return false;
        // The storage error class is a coarse tracking dimension; the
        // sheet shows one plain sentence without it.
        final errorClass = classifySecretError(error);
        TrackingService.track('restore_write_failed',
            params: {'error_class': errorClass.name});
        _setBusy(walletId, false);
        final retry = await _choose(
          body: context.l10n.restoreWriteFailedPlain,
          confirm: context.l10n.storageUnavailableRetry,
        );
        if (!retry || !mounted) return false;
        _setBusy(walletId, true);
      }
    }
  }

  Future<int?> _checkBalance(String phrase) async {
    final checker = BalanceCheckerService(
        electrumUrl: ref.read(settingsProvider).bitcoinElectrumNode);
    try {
      final result = await checker.checkAllPaths(phrase);
      return result.isComplete || result.hasAnyBalance
          ? result.totalBalance
          : null;
    } catch (_) {
      return null;
    } finally {
      checker.dispose();
    }
  }

  /// A restore attempt that ended without restoring. [reason]:
  /// invalid_phrase | mismatch | declined | passkey_unavailable.
  void _trackRestoreFailed(String method, String reason) {
    TrackingService.track('seed_restore_failed',
        params: {'method': method, 'reason': reason});
  }

  Future<void> _showMismatch() async {
    final addNew = await _choose(
      body: context.l10n.restorePhraseMismatch,
      confirm: context.l10n.restoreAddAsNewWallet,
    );
    if (addNew && mounted) _addAsNewWallet();
  }

  /// The normal recover flow, which creates a new wallet id.
  void _addAsNewWallet() {
    TrackingService.track('seed_restore_add_as_new_wallet');
    TrackingService.clearFlowContext('seed_restore');
    ref.read(recoveryModeProvider.notifier).state = true;
    if (!_hasPinMaterial) {
      context.go('/set_pin');
    } else if (ref.read(sessionAuthProvider) != null) {
      context.go('/recover_wallet/seed');
    } else {
      context.go('/open_pin');
    }
  }

  void _useLegacyCopy(WalletConfig wallet) {
    TrackingService.seedRestoreStarted(method: 'legacy_copy');
    _markRestored(wallet.id);
    TrackingService.seedRestoreCompleted(
        method: 'legacy_copy', matched: wallet.recoveryCheckAddress != null);
  }

  Future<void> _usePasskey(WalletConfig wallet) async {
    TrackingService.seedRestoreStarted(method: 'passkey');
    TrackingService.setFlowStep('passkey');
    _setBusy(wallet.id, true);
    final loader = widget.loadPasskeyMnemonic ?? PasskeyService.getMnemonic;
    String? mnemonic;
    try {
      mnemonic = await loader(
        label: wallet.passkeyLabel,
        legacy: wallet.passkeyProvider == null,
      );
    } catch (_) {}
    final stored = wallet.recoveryCheckAddress;
    var restored = mnemonic != null;
    String? derived;
    if (mnemonic != null) {
      derived = await _safeDerive(mnemonic, wallet);
      if (stored != null && !RecoveryCheck.matches(stored, derived)) {
        restored = false;
      }
    }
    if (!restored) {
      _trackRestoreFailed(
          'passkey', mnemonic == null ? 'passkey_unavailable' : 'mismatch');
    }
    if (!mounted) return;
    if (!restored) {
      setState(() {
        _rows[wallet.id]
          ?..passkeyFailed = true
          ..busy = false;
      });
      showMessageSnackBar(
          context: context,
          message:
              context.l10n.restorePasskeyFailed(passkeyAccountName(context)),
          error: true);
      return;
    }
    if (stored == null && derived != null && derived.isNotEmpty) {
      await ref
          .read(settingsProvider.notifier)
          .setRecoveryCheckAddress(wallet.id, derived);
    }
    _markRestored(wallet.id);
    TrackingService.seedRestoreCompleted(
        method: 'passkey', matched: stored != null);
  }

  void _done() {
    TrackingService.track('seed_restore_done', params: {
      'restored_any':
          _rows.values.any((r) => r.status == _RowStatus.restored),
    });
    TrackingService.clearFlowContext('seed_restore');
    if (!_hasPinMaterial) {
      ref.read(recoveryModeProvider.notifier).state = false;
      ref.read(restoreSecretsReturnProvider.notifier).state = widget.reason;
      context.go('/set_pin');
      return;
    }
    context.go(ref.read(sessionAuthProvider) != null ? '/home' : '/open_pin');
  }

  Future<void> _startFresh() async {
    final word = context.l10n.restoreStartFreshWord;
    final confirmed = await showAppBottomSheet<bool>(
      context: context,
      builder: (_) => _StartFreshSheet(word: word),
    );
    if (confirmed != true || !mounted) return;
    TrackingService.seedRestoreStartFresh();
    TrackingService.clearFlowContext('seed_restore');
    final wipe = widget.wipe;
    if (wipe != null) {
      await wipe();
      return;
    }
    BackgroundSyncService().stop();
    await ref.read(authModelProvider).deleteAuthentication();
    ref.invalidate(bitcoinConfigProvider);
    if (mounted) RestartWidget.restartApp(context);
  }

  Future<bool> _choose({required String body, required String confirm}) async {
    final result = await showAppBottomSheet<bool>(
      context: context,
      builder: (_) => _ChoiceSheet(body: body, confirm: confirm),
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final wallets = ref.watch(settingsProvider.select((s) => s.wallets));
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(20.w, 32.h, 20.w, 24.h),
          children: [
            Text(
              context.l10n.restoreSecretsTitle,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 26.sp,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                height: 1.1,
              ),
            ),
            SizedBox(height: 10.h),
            Text(
              context.l10n.restoreSecretsBody,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 15.sp,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
            SizedBox(height: 24.h),
            for (final wallet in wallets) ...[
              _RestoreWalletRow(
                wallet: wallet,
                state: _rows[wallet.id] ?? _RowState(),
                onEnterPhrase: () => _enterPhrase(wallet),
                onUseLegacyCopy: () => _useLegacyCopy(wallet),
                onUsePasskey: () => _usePasskey(wallet),
                onUsePhraseInstead: _addAsNewWallet,
              ),
              SizedBox(height: 12.h),
            ],
            SizedBox(height: 12.h),
            AppButton(
              key: const ValueKey('restore-done'),
              text: context.l10n.done,
              onPressed: _done,
            ),
            if (widget.reason != RestoreSecretsReason.storageUnavailable) ...[
              SizedBox(height: 8.h),
              AppTextButton(
                key: const ValueKey('restore-start-fresh'),
                text: context.l10n.restoreStartFresh,
                textColor: c.error,
                onPressed: _startFresh,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RestoreWalletRow extends StatelessWidget {
  const _RestoreWalletRow({
    required this.wallet,
    required this.state,
    required this.onEnterPhrase,
    required this.onUseLegacyCopy,
    required this.onUsePasskey,
    required this.onUsePhraseInstead,
  });

  final WalletConfig wallet;
  final _RowState state;
  final VoidCallback onEnterPhrase;
  final VoidCallback onUseLegacyCopy;
  final VoidCallback onUsePasskey;
  final VoidCallback onUsePhraseInstead;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final restored = state.status == _RowStatus.restored;
    final needsRecovery = state.status == _RowStatus.needsRecovery;
    final storedSeed = RecoveryCheck.holdsStoredSeed(wallet);
    final String? hint = restored || storedSeed || wallet.isPasskey
        ? null
        : wallet.isExternalAddress
            ? l10n.restoreAddAddressAgainRow
            : wallet.isWatchOnly
                ? l10n.restoreImportWalletAgainRow
                : l10n.restoreReconnectDeviceRow;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  wallet.name,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (state.status != _RowStatus.checking)
                Text(
                  restored
                      ? l10n.restoreWalletRestored
                      : l10n.restoreNeedsRecovery,
                  style: TextStyle(
                    color: restored ? c.success : c.textTertiary,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          if (hint != null) ...[
            SizedBox(height: 6.h),
            Text(
              hint,
              style: TextStyle(color: c.textSecondary, fontSize: 14.sp),
            ),
          ],
          if (state.busy) ...[
            SizedBox(height: 12.h),
            const Center(child: CircularProgressIndicator.adaptive()),
          ] else if (needsRecovery && storedSeed) ...[
            SizedBox(height: 12.h),
            AppButton(
              key: ValueKey('restore-phrase-${wallet.id}'),
              text: l10n.restoreEnterPhrase,
              compact: true,
              onPressed: onEnterPhrase,
            ),
            if (state.legacyCopy) ...[
              SizedBox(height: 8.h),
              AppButton(
                key: ValueKey('restore-legacy-${wallet.id}'),
                text: l10n.restoreUseLegacyCopy,
                variant: AppButtonVariant.secondary,
                compact: true,
                onPressed: onUseLegacyCopy,
              ),
            ],
          ] else if (needsRecovery && wallet.isPasskey) ...[
            SizedBox(height: 12.h),
            AppButton(
              key: ValueKey('restore-passkey-${wallet.id}'),
              text: l10n.restoreUsePasskey(passkeyAccountName(context)),
              compact: true,
              onPressed: onUsePasskey,
            ),
            if (state.passkeyFailed && wallet.passkeyProvider == null) ...[
              SizedBox(height: 8.h),
              AppButton(
                key: ValueKey('restore-phrase-instead-${wallet.id}'),
                text: l10n.restoreUsePhraseInstead,
                variant: AppButtonVariant.secondary,
                compact: true,
                onPressed: onUsePhraseInstead,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _PhraseSheet extends StatefulWidget {
  const _PhraseSheet({required this.walletName});
  final String walletName;

  @override
  State<_PhraseSheet> createState() => _PhraseSheetState();
}

class _PhraseSheetState extends State<_PhraseSheet> {
  final _controller = TextEditingController();

  /// Holds a pasted phrase until it is cleared from the clipboard (only
  /// while the clipboard still holds it).
  final _pasteClipboard = SeedClipboard();

  /// Paste: reads the clipboard once, fills the field with a whole 12 or 24
  /// word phrase in plain form, then clears the clipboard if it still holds
  /// that phrase. Anything else leaves the field and the clipboard alone.
  Future<void> _paste() async {
    final text = await _pasteClipboard.takePaste();
    if (!mounted || text == null) return;
    final RecoveryPhraseInput input;
    try {
      input = RecoveryPhraseInput.parse(RecoveryPhraseInput.normalize(text));
    } on FormatException {
      _pasteClipboard.forget();
      TrackingService.track('recovery_phrase_pasted',
          params: {'source': 'restore_secrets', 'result': 'invalid'});
      showMessageSnackBar(
          context: context,
          message: context.l10n.recoveryPhraseInvalid,
          error: true);
      return;
    }
    unawaited(_pasteClipboard.clearIfUnchanged());
    TrackingService.track('recovery_phrase_pasted',
        params: {'source': 'restore_secrets', 'result': 'ok'});
    _controller.text = input.words.join(' ');
    FocusScope.of(context).unfocus();
  }

  @override
  void dispose() {
    _pasteClipboard.dispose();
    _controller.clear();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SecureScreen(
      surface: 'restore_secrets',
      child: AppBottomSheetContainer(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 16.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppBottomSheetHeader(
                title: context.l10n.restoreEnterPhrase,
                subtitle: widget.walletName,
              ),
              SecureContent(
                child: TextField(
                  key: const ValueKey('restore-phrase-field'),
                  controller: _controller,
                  minLines: 3,
                  maxLines: 5,
                  autofocus: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  enableIMEPersonalizedLearning: false,
                  keyboardType: TextInputType.multiline,
                  style: TextStyle(color: c.textPrimary, fontSize: 16.sp),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: c.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14.r),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              SizedBox(height: 12.h),
              AppButton(
                key: const ValueKey('restore-phrase-paste'),
                text: context.l10n.paste,
                icon: Icons.content_paste_rounded,
                variant: AppButtonVariant.secondary,
                onPressed: _paste,
              ),
              SizedBox(height: 10.h),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _controller,
                builder: (context, value, _) => AppButton(
                  key: const ValueKey('restore-phrase-confirm'),
                  text: context.l10n.confirm,
                  onPressed: value.text.trim().isEmpty
                      ? null
                      : () => Navigator.of(context).pop(_controller.text),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChoiceSheet extends StatelessWidget {
  const _ChoiceSheet({required this.body, required this.confirm});
  final String body;
  final String confirm;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppBottomSheetContainer(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20.w, 24.h, 20.w, 16.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 16.sp,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
            SizedBox(height: 20.h),
            AppButton(
              key: const ValueKey('restore-choice-confirm'),
              text: confirm,
              onPressed: () => Navigator.of(context).pop(true),
            ),
            SizedBox(height: 8.h),
            AppButton(
              key: const ValueKey('restore-choice-cancel'),
              text: context.l10n.cancel,
              variant: AppButtonVariant.secondary,
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ),
    );
  }
}

class _StartFreshSheet extends StatefulWidget {
  const _StartFreshSheet({required this.word});
  final String word;

  @override
  State<_StartFreshSheet> createState() => _StartFreshSheetState();
}

class _StartFreshSheetState extends State<_StartFreshSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppBottomSheetContainer(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20.w, 24.h, 20.w, 16.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.l10n.restoreStartFreshConfirm(widget.word),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 16.sp,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
            SizedBox(height: 16.h),
            TextField(
              key: const ValueKey('restore-start-fresh-field'),
              controller: _controller,
              autocorrect: false,
              enableSuggestions: false,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.textPrimary, fontSize: 16.sp),
              inputFormatters: [
                FilteringTextInputFormatter.deny(RegExp(r'\s')),
              ],
              decoration: InputDecoration(
                filled: true,
                fillColor: c.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14.r),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            SizedBox(height: 16.h),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (context, value, _) => AppButton(
                key: const ValueKey('restore-start-fresh-confirm'),
                text: context.l10n.restoreStartFresh,
                variant: AppButtonVariant.destructive,
                onPressed: value.text.trim().toUpperCase() == widget.word.toUpperCase()
                    ? () => Navigator.of(context).pop(true)
                    : null,
              ),
            ),
            SizedBox(height: 8.h),
            AppButton(
              text: context.l10n.cancel,
              variant: AppButtonVariant.secondary,
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ),
    );
  }
}
