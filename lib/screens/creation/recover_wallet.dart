import 'package:kute/helpers/recovery_phrase_input.dart';
import 'package:kute/helpers/seed_clipboard.dart';
import 'dart:async';
import 'dart:math';
import 'package:kute/services/secure/recovery_check.dart';
import 'package:kute/services/secure/recovery_evm_format.dart';
import 'package:kute/services/hyperliquid/hyperliquid_onboarding_service.dart';
import 'package:kute/providers/bitcoin_wallet_creation_provider.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/helpers/secure_screen.dart';
import 'package:kute/helpers/session_auth.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/providers/bitcoin_config_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/words_provider.dart';
import 'package:kute/screens/creation/recover_choice.dart'
    show RestoreFlowAnalytics;
import 'package:kute/screens/creation/set_pin.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/helpers/user_error_copy.dart';
import 'package:kute/services/balance_checker_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/l10n/l10n.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class RecoverWallet extends ConsumerStatefulWidget {
  final bool bitcoinOnly;

  /// Picks the recovered wallet's EVM format; tests replace the venue reads.
  final Future<RecoveryEvmChoice> Function(String mnemonic)? chooseEvmFormat;

  const RecoverWallet({
    super.key,
    this.bitcoinOnly = false,
    @visibleForTesting this.chooseEvmFormat,
  });

  @override
  ConsumerState<RecoverWallet> createState() => _RecoverWalletState();
}

class _RecoverWalletState extends ConsumerState<RecoverWallet>
    with SingleTickerProviderStateMixin {
  final TextEditingController _nameController = TextEditingController();
  final List<TextEditingController> _controllers = List.generate(24, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(24, (_) => FocusNode());

  List<String> _filteredWords = [];
  int _totalWords = 12;
  String _bitcoinScriptType = 'bip84';
  bool _isProcessing = false;

  /// Holds a phrase read by the Paste button until it is cleared from the
  /// clipboard (only while the clipboard still holds it).
  final SeedClipboard _pasteClipboard = SeedClipboard();

  @override
  void initState() {
    super.initState();
    // Default name on recovery — kept identical to the fresh-create
    // and passkey-restore paths so a wallet name never reads as
    // "Spending Account" vs "Spending Wallet" depending on which
    // door the user came through.
    _nameController.text = widget.bitcoinOnly ? "Bitcoin wallet" : "Spending Wallet";
    // Rebuild on name edits so the continue button's enabled state tracks
    // the name field too.
    _nameController.addListener(() {
      if (mounted) setState(() {});
    });
    for (var i = 0; i < _controllers.length; i++) {
      _controllers[i].addListener(() => _onTextChanged(i));
      _focusNodes[i].addListener(() {
        // Always rebuild on focus change so the focused chip's accent
        // border (and per-word error borders) update immediately.
        if (mounted) setState(() {});
        if (_focusNodes[i].hasFocus) {
          _onTextChanged(i);
        }
      });
    }
    // Passkey discovery moved to the `RecoverChoiceScreen` parent
    // route — by the time the user lands on the seed grid they've
    // explicitly chosen the recovery-phrase path, so we don't
    // interrupt them with a "we found a passkey" sheet.

    // Funnel: recovery-phrase entry screen mounted. Fired once here in
    // initState (not build) so it can't repeat on rebuild. No word count:
    // the length of a phrase never leaves the device.
    TrackingService.recoveryPhraseDisplayed();
    // A Bitcoin-only import belongs to the add-wallet flow, not restore.
    if (!widget.bitcoinOnly) {
      if (ref.read(settingsProvider).wallets.isEmpty) {
        // Onboarding funnel step; the restore flow owns the breadcrumb.
        trackOnboardingStep('restore_seed', path: 'restore', breadcrumb: false);
      }
      RestoreFlowAnalytics.step('seed_entry', method: 'seed');
    }
  }

  @override
  void dispose() {
    _pasteClipboard.dispose();
    _nameController.dispose();
    for (var controller in _controllers) {
      controller.dispose();
    }
    for (var focusNode in _focusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  /// Guards against the listener re-entering while a pasted phrase is
  /// being distributed across the grid programmatically.
  bool _distributingPaste = false;

  void _onTextChanged(int index) {
    if (_distributingPaste) return;
    final text = _controllers[index].text;
    // Pasting a whole phrase into any single field spreads the words
    // across the grid instead of cramming them into one chip.
    if (text.trim().contains(RegExp(r'\s'))) {
      _distributePastedPhrase(index, text);
      return;
    }
    if (!_focusNodes[index].hasFocus) {
      // Rebuild anyway: programmatic fills (QR scan, paste) change the
      // continue button's enabled state without focus.
      setState(() => _filteredWords = []);
      return;
    }
    final query = _controllers[index].text;
    final wordsState = ref.read(wordsProvider);
    if (query.isEmpty) {
      setState(() => _filteredWords = []);
      return;
    }
    if (wordsState.words != null) {
      final filtered = wordsState.words!
          .where((word) => word.toLowerCase().startsWith(query.toLowerCase()))
          .take(5)
          .toList();
      setState(() => _filteredWords = filtered);
    } else {
      setState(() {});
    }
  }

  /// Fills the grid from a multi-word paste. A full 12/24-word phrase
  /// resizes the grid and starts from slot 1; a partial fragment fills
  /// forward from the field it was pasted into.
  void _distributePastedPhrase(int index, String text) {
    if (text.trim().split(RegExp(r'\s+')).length <= 1) return;
    final RecoveryPhraseInput input;
    try {
      input = RecoveryPhraseInput.parse(RecoveryPhraseInput.normalize(text),
          startIndex: index, wordCount: _totalWords,
          bitcoinOnly: widget.bitcoinOnly, allowPartial: true);
    } on FormatException {
      _distributingPaste = true;
      _controllers[index].clear();
      _distributingPaste = false;
      showMessageSnackBar(context: context,
          message: context.l10n.recoveryPhraseInvalid, error: true);
      return;
    }
    // Never the words or how many there were.
    TrackingService.track('recovery_phrase_pasted',
        params: {'source': 'keyboard'});
    _distributingPaste = true;
    _totalWords = input.wordCount;
    if (input.words.length == input.wordCount) {
      for (final controller in _controllers) {
        controller.clear();
      }
    }
    for (var i = 0; i < input.words.length; i++) {
      _controllers[input.startIndex + i].text = input.words[i];
    }
    _distributingPaste = false;
    FocusScope.of(context).unfocus();
    setState(() => _filteredWords = []);
  }

  /// Non-empty word that is not in the BIP39 list, shown with an error
  /// border once the user has moved on from the field.
  bool _isWordInvalid(int index) {
    if (_focusNodes[index].hasFocus) return false;
    final text = _controllers[index].text.trim().toLowerCase();
    if (text.isEmpty) return false;
    final words = ref.read(wordsProvider).words;
    if (words == null) return false;
    return !words.contains(text);
  }

  /// Continue stays disabled until every visible word slot and the
  /// wallet name are filled in. Full BIP39 checksum validation still
  /// happens in [_recoverAccount].
  bool get _canSubmit {
    if (_nameController.text.trim().isEmpty) return false;
    for (var i = 0; i < _totalWords; i++) {
      if (_controllers[i].text.trim().isEmpty) return false;
    }
    return true;
  }

  /// Paste button: reads the clipboard once, fills every slot from a whole
  /// 12 or 24 word phrase (numbering, commas and line breaks dropped), then
  /// clears the clipboard if it still holds that phrase. Words outside the
  /// BIP39 list keep the field's error style. Anything that is not a whole
  /// phrase leaves both the grid and the clipboard alone.
  Future<void> _pastePhrase() async {
    if (_isProcessing) return;
    final text = await _pasteClipboard.takePaste();
    if (!mounted || text == null) return;
    final RecoveryPhraseInput input;
    try {
      input = RecoveryPhraseInput.parse(RecoveryPhraseInput.normalize(text),
          bitcoinOnly: widget.bitcoinOnly);
    } on FormatException {
      _pasteClipboard.forget();
      TrackingService.track('recovery_phrase_pasted',
          params: {'source': 'button', 'result': 'invalid'});
      showMessageSnackBar(context: context,
          message: context.l10n.recoveryPhraseInvalid, error: true);
      return;
    }
    unawaited(_pasteClipboard.clearIfUnchanged());
    // Outcome only: never the words or how many there were.
    TrackingService.track('recovery_phrase_pasted',
        params: {'source': 'button', 'result': 'ok'});
    _distributingPaste = true;
    _totalWords = input.wordCount;
    for (var i = 0; i < _controllers.length; i++) {
      _controllers[i].text = i < input.words.length ? input.words[i] : '';
    }
    _distributingPaste = false;
    FocusScope.of(context).unfocus();
    setState(() => _filteredWords = []);
  }

  Future<void> _scanRecoveryQR() async {
    final result = await context.pushNamed<String>('QrScanner');
    if (result == null || result.isEmpty || !mounted) return;

    final RecoveryPhraseInput input;
    try {
      input = RecoveryPhraseInput.parse(result, bitcoinOnly: widget.bitcoinOnly);
    } on FormatException {
      TrackingService.track('recovery_qr_scanned',
          params: {'result': 'invalid'});
      showMessageSnackBar(context: context,
          message: context.l10n.recoveryPhraseInvalid, error: true);
      return;
    }
    // Outcome only: never the words or how many there were.
    TrackingService.track('recovery_qr_scanned', params: {'result': 'ok'});
    _distributingPaste = true;
    _totalWords = input.wordCount;
    for (var i = 0; i < _controllers.length; i++) {
      _controllers[i].text = i < input.words.length ? input.words[i] : '';
    }
    _distributingPaste = false;

    setState(() => _filteredWords = []);
  }

  void _onWordSelected(String word) {
    final focusedIndex = _focusNodes.indexWhere((node) => node.hasFocus);
    if (focusedIndex != -1) {
      _controllers[focusedIndex].text = word;
      _controllers[focusedIndex].selection = TextSelection.fromPosition(
          TextPosition(offset: _controllers[focusedIndex].text.length));
      if (focusedIndex < _totalWords - 1) {
        FocusScope.of(context).requestFocus(_focusNodes[focusedIndex + 1]);
      } else {
        FocusScope.of(context).unfocus();
      }
      setState(() => _filteredWords = []);
    }
  }

  Future<void> _recoverAccount(BuildContext context) async {
    if (_isProcessing) return;
    final walletName = _nameController.text.trim();
    if (walletName.isEmpty) {
      showMessageSnackBar(context: context, message: context.l10n.pleaseEnterAWalletName, error: true);
      return;
    }

    setState(() => _isProcessing = true);
    final authModel = ref.read(authModelProvider);
    // Grab the ROOT ProviderContainer NOW, while `context` is valid and
    // before any await. context.go('/home') below disposes THIS widget
    // (and its WidgetRef), so the post-navigation background scan must
    // read through this long-lived container instead of the dead ref —
    // touching a disposed ConsumerState ref throws StateError even in
    // release.
    final container = ProviderScope.containerOf(context, listen: false);

    if (!ref.read(sessionUnlockedProvider)) {
      TrackingService.walletAddFailed(reason: 'session_locked');
      if (!widget.bitcoinOnly) RestoreFlowAnalytics.failed('session_locked');
      if (mounted) {
        setState(() => _isProcessing = false);
        showMessageSnackBar(context: context, message: context.l10n.pleaseSetUpYourPinFirst, error: true);
        if (!widget.bitcoinOnly) context.go('/start');
      }
      return;
    }

    final mnemonic = _controllers
        .take(_totalWords)
        .map((controller) => controller.text.trim().toLowerCase())
        .join(' ');

    final validMnemonic =
        mnemonic.isNotEmpty && await authModel.validateMnemonic(mnemonic);
    if (!mounted || !context.mounted) return;
    if (!validMnemonic) {
      TrackingService.track('recovery_phrase_invalid');
      if (!widget.bitcoinOnly) RestoreFlowAnalytics.failed('invalid_phrase');
      FocusScope.of(context).unfocus();
      setState(() => _isProcessing = false);
      showMessageSnackBar(context: context, message: context.l10n.recoveryPhraseInvalid, error: true);
      return;
    }

    if (widget.bitcoinOnly) {
      TrackingService.walletAddStarted();
      var created = false;
      try {
        final wallet = await ref.read(bitcoinWalletCreationProvider).create(
            name: walletName, recoveryPhrase: mnemonic,
            scriptType: _bitcoinScriptType);
        created = true;
        TrackingService.walletCreated(
            type: 'bitcoin_onchain', authMode: 'imported');
        TrackingService.walletAdded(
          walletKind: 'bitcoin_onchain',
          importMethod: 'seed',
          scriptType: switch (_bitcoinScriptType) {
            'bip84' => 'native_segwit',
            'bip86' => 'taproot',
            'bip49' => 'nested_segwit',
            'bip44' => 'legacy',
            _ => 'unknown',
          },
          network: 'bitcoin',
          source: 'add_wallet',
        );
        _distributingPaste = true;
        for (final controller in _controllers) { controller.clear(); }
        _distributingPaste = false;
        if (mounted && context.mounted) {
          _showRecovered(
            kind: 'bitcoin',
            navigate: (router) => router.goNamed('walletDetail',
                pathParameters: {'walletId': wallet.id}),
          );
        }
      } catch (e) {
        if (!created) {
          TrackingService.walletAddFailed(
              reason: 'bitcoin_create_failed',
              errorCode: e.runtimeType.toString());
        }
        if (mounted && context.mounted) {
          showMessageSnackBar(context: context,
              message: context.l10n.recoverBtcFailed, error: true);
        }
      } finally {
        if (mounted) setState(() => _isProcessing = false);
      }
      return;
    }

    // The same phrase leads to two EVM accounts: wallets created before the
    // standard format use the legacy SHA256 seed stretch. Ask the venues
    // which one holds this user's Predictions and Investing (about 5 s at
    // most, derivation off the UI isolate); legacy wins when its account
    // has funds or history, else standard. A check that cannot finish
    // falls back to standard and the next unlock retries it
    // (RecoveryEvmFormat.retryPending). Existing wallet records keep their
    // own version through RestoreSecrets.
    final evmChoice =
        await (widget.chooseEvmFormat ?? RecoveryEvmFormat.choose)(mnemonic);
    if (!mounted || !context.mounted) return;

    var persisted = false;
    try {
      // Create wallet immediately — no blocking balance check
      final walletId = '${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(1000)}';
      await authModel.setMnemonic(walletId, mnemonic);
      final newWallet = WalletConfig(
        id: walletId,
        name: walletName,
        sparkEnabled: true,
        backedUp: true,
        isHardware: false,
        isRestore: true,
        evmDerivationVersion: evmChoice.version,
        evmFormatCheckPending: !evmChoice.checked,
      );
      final settingsNotifier = ref.read(settingsProvider.notifier);
      await settingsNotifier.addWallet(newWallet);
      persisted = true;
      RecoveryCheck.record(settingsNotifier, walletId, mnemonic);
      ref.invalidate(bitcoinConfigProvider);
      // Investing balances poll only for wallets marked enabled; one whose
      // account already has Hyperliquid history must show it right away.
      if (evmChoice.hyperliquidActive) {
        unawaited(HyperliquidOnboardingService.markEnabled(walletId));
      }

      // Set up Polymarket account in background (Safe deploy + credentials)
      provisionPolymarketAccount(mnemonic: mnemonic, walletId: walletId,
          evmDerivationVersion: newWallet.evmDerivationVersion);

      TrackingService.recoverySeedEntered(evmFormat: evmChoice.analyticsValue);
      TrackingService.walletCreated(type: 'imported');
      final isFirstWallet = ref.read(settingsProvider).wallets.length == 1;
      TrackingService.walletAdded(
        walletKind: 'hot',
        importMethod: 'seed',
        network: 'spark',
        source: isFirstWallet ? 'onboarding' : 'add_wallet',
      );
      // A first-wallet restore skips the referrer screen, where the funnel
      // otherwise ends, so it never reached onboarding_completed.
      if (isFirstWallet) {
        TrackingService.onboardingCompletedOnce(authMode: 'recovered');
      }
      RestoreFlowAnalytics.completed();

      // Recovery is complete — the iCloud backup choice screen was
      // dropped during the passkey pivot, so the confirmation's Done
      // lands the user on home. The wallet's already added + active.
      if (mounted && context.mounted) {
        ref.read(recoveryModeProvider.notifier).state = false;
        _showRecovered(
          kind: 'spending',
          navigate: (router) => router.go('/home'),
        );
      }

      // Fire-and-forget: check old derivation paths for balances in the
      // background. We NEVER auto-migrate/sweep on recovery. When funds
      // are found on a legacy path we add a watch-only "other" wallet so
      // the user simply SEES those legacy funds as a separate wallet and
      // can move them manually later. No fund movement, ever.
      TrackingService.recoveryBalanceCheckInitiated();
      _runBackgroundBalanceCheck(container, mnemonic, walletName);
    } catch (e) {
      if (!persisted) {
        final category = TrackingService.errorCategory(e);
        RestoreFlowAnalytics.failed(category);
        TrackingService.track('wallet_add_failed', params: {
          'reason': 'restore_failed',
          'error_code': e.runtimeType.toString(),
          'error_category': category,
        });
      }
      if (mounted && context.mounted) {
        showMessageSnackBar(
            context: context,
            message: userErrorCopy(context, e,
                fallback: context.l10n.errorCopyRecoverWallet),
            error: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  /// The same confirmation every money moment ends on: one check, one
  /// line, Done. Done tears down the routes under the overlay and then
  /// runs [navigate], which lands where recovery used to go directly.
  void _showRecovered({
    required String kind,
    required void Function(GoRouter router) navigate,
  }) {
    final router = GoRouter.of(context);
    final rootNav = Navigator.of(context, rootNavigator: true);
    TrackingService.track('recovery_confirmation_shown',
        params: {'kind': kind});
    pushKuteSuccessOverlay(
      navigator: rootNav,
      overlay: KuteConfirmation(
        message: context.l10n.confirmationWalletRecovered,
        onDone: () {
          while (rootNav.canPop()) {
            rootNav.pop();
          }
          navigate(router);
        },
      ),
    );
  }

  /// Runs the multi-path Electrum scan AFTER the user has already left
  /// this screen for /home. Reads through the root [container] captured
  /// before navigation — NOT the widget's WidgetRef, which is disposed
  /// by the time this completes and would throw on read.
  void _runBackgroundBalanceCheck(
      ProviderContainer container, String mnemonic, String recoveredName) {
    // Use a non-autoDispose read so the checker survives navigation
    final electrumUrl = container.read(settingsProvider).bitcoinElectrumNode;
    final checker = BalanceCheckerService(electrumUrl: electrumUrl);
    checker.checkAllPaths(mnemonic).then((result) async {
      TrackingService.recoveryBalanceCheckCompleted(
          complete: result.isComplete, hasBalances: result.hasAnyBalance);
      if (result.isComplete) {
        TrackingService.recoveryBalanceFound(hasBalances: result.hasAnyBalance);
      }
      if (!result.hasAnyBalance) return;

      // NEVER auto-migrate. For each funded legacy path, add a
      // watch-only "other" wallet mirroring the xpub-import flow
      // (import_wallet_controller.importXpub): write the bare account
      // xpub to secure storage, then add a WalletConfig pointing at it.
      // The user simply SEES the legacy funds as a separate wallet and
      // can move them manually later. No sweeping, no fund movement.
      for (final path in result.pathsWithBalance) {
        await _addWatchOnlyForPath(container, path, recoveredName);
      }
    }).catchError((_) {
      TrackingService.recoveryBalanceCheckCompleted(complete: false, hasBalances: false);
    }).whenComplete(checker.dispose);
  }

  /// Add a single watch-only "other" wallet for a funded legacy
  /// derivation path. Mirrors import_wallet_controller's xpub-import:
  /// dedupe on the bare xpub, write it to secure storage, then add a
  /// `WalletConfig` (watch-only, walletType 'other'). Best-effort and
  /// fire-and-forget — a failure on one path never blocks the others
  /// or the user, who is already on Home.
  Future<void> _addWatchOnlyForPath(ProviderContainer container,
      DerivationBalance path, String recoveredName) async {
    try {
      final xpub = path.xpub;
      // Without a derived xpub we can't build a watch-only wallet —
      // skip rather than create a broken entry.
      if (xpub.isEmpty) return;

      final authModel = container.read(authModelProvider);

      // Dedupe: skip if any existing wallet already tracks this xpub.
      // Mirrors importXpub's duplicate check. Read the wallet list
      // through the long-lived container (not a disposed WidgetRef).
      for (final wallet in container.read(settingsProvider).wallets) {
        if (wallet.isExternalAddress) continue;
        final existingXpub = await authModel.getExtendedPublicKey(wallet.id);
        if (existingXpub != null && existingXpub == xpub) return;
      }

      // Human-readable suffix per address type, e.g.
      // "Spending Wallet (legacy)".
      final typeLabel = switch (path.addressType) {
        'legacy' => 'legacy',
        'nested_segwit' => 'nested SegWit',
        'native_segwit' => 'native SegWit',
        _ => path.addressType,
      };

      final newId =
          '${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(1000)}';
      await authModel.setExtendedPublicKey(newId, xpub);
      await container.read(settingsProvider.notifier).addWallet(
            WalletConfig(
              id: newId,
              name: '$recoveredName ($typeLabel)',
              sparkEnabled: false,
              isWatchOnly: true,
              isHardware: true,
              walletType: 'other',
              // App scriptType slug (bip44/bip49/bip84) the
              // xpub-import / BitcoinConfig flow expects, so the
              // watch-only wallet derives the SAME addresses the funds
              // live at.
              scriptType: path.scriptType,
              backedUp: true,
            ),
          );
    } catch (_) {
      // Best-effort: one bad path must not block the others.
    }
  }

  static const _bitcoinAddressTypes = {
    'bip84': ('Native SegWit', 'bc1q'),
    'bip86': ('Taproot', 'bc1p'),
    'bip49': ('Nested SegWit', '3'),
    'bip44': ('Legacy', '1'),
  };

  Future<void> _pickBitcoinAddressType() async {
    if (_isProcessing) return;
    FocusScope.of(context).unfocus();
    final selected = await showAppBottomSheet<String>(
      context: context,
      builder: (sheetContext) => AppBottomSheetContainer(
        maxHeight: 0.8,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AppBottomSheetHeader(title: context.l10n.recoverOriginalAddressType,
              subtitle: context.l10n.recoverOriginalAddressTypeSubtitle),
          Flexible(child: ListView(shrinkWrap: true, children: [
            for (final entry in _bitcoinAddressTypes.entries)
              AppBottomSheetListTile(
                title: entry.value.$1,
                subtitle: context.l10n.recoverAddressesStartWith(entry.value.$2),
                isSelected: entry.key == _bitcoinScriptType,
                onTap: () => Navigator.of(sheetContext).pop(entry.key),
              ),
          ])),
        ]),
      ),
    );
    if (mounted && !_isProcessing && selected != null) {
      if (selected != _bitcoinScriptType) {
        TrackingService.track('recovery_address_type_selected',
            params: {'script_type': selected, 'from': _bitcoinScriptType});
      }
      setState(() => _bitcoinScriptType = selected);
    }
  }

  Widget _bitcoinAddressTypeField() {
    final c = context.colors;
    final selected = _bitcoinAddressTypes[_bitcoinScriptType]!;
    return Container(
      decoration: AppDecorations.card(context),
      child: Material(color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: InkWell(
          key: const ValueKey('bitcoin-address-type'),
          onTap: _isProcessing ? null : _pickBitcoinAddressType,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Padding(padding: EdgeInsets.all(16.w),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(context.l10n.recoverOriginalAddressType, style: TextStyle(color: c.textSecondary, fontSize: 13.sp)),
                SizedBox(height: 4.h),
                Text('${selected.$1} (${selected.$2})',
                    style: TextStyle(color: c.textPrimary, fontSize: 15.sp, fontWeight: FontWeight.w600)),
              ])),
              SizedBox(width: 12.w),
              Icon(Icons.chevron_right_rounded, color: c.textTertiary, size: 20.sp),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final wordsState = ref.watch(wordsProvider);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardVisible = bottomInset > 0;

    if (wordsState.loading) {
      // Skeleton grid mimicking the 12 word-input chips about to render.
      return Scaffold(
        backgroundColor: c.background,
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20.w, 80.h, 20.w, 0),
            // Mirror the real grid's 2-column layout.
            child: const SkeletonWordGrid(crossAxisCount: 2, aspectRatio: 3.2),
          ),
        ),
      );
    }

    return SecureScreen(
      surface: 'recover_wallet',
      child: PopScope(
      canPop: !_isProcessing,
      child: KeyboardDismissOnTap(
      child: Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: c.background,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: Theme.of(context).brightness == Brightness.light
            ? SystemUiOverlayStyle.dark
            : SystemUiOverlayStyle.light,
        centerTitle: true,
        leading: KuteBackButton(
          onPressed: () {
            if (_isProcessing) return;
            if (widget.bitcoinOnly) {
              if (!_isProcessing) Navigator.of(context).maybePop();
              return;
            }
            RestoreFlowAnalytics.abandoned(reason: 'back');
            ref.read(recoveryModeProvider.notifier).state = false;
            clearSession(ref);
            ref.read(pinProvider.notifier).state = '';
            context.go('/start');
          },
        ),
        title: Text(
          context.l10n.recoverAccount,
          style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 18.sp),
        ),
        actions: const [],
      ),
      body: Container(
        color: c.background,
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(24.w, 8.h, 24.w, 24.h),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(height: 8.h),

                          Text(
                            context.l10n.recoverWithRecoveryPhrase,
                            style: TextStyle(
                              color: c.textSecondary,
                              fontSize: 15.sp,
                              height: 1.35,
                            ),
                          ),
                          SizedBox(height: 16.h),

                          Container(
                            decoration: BoxDecoration(
                              color: c.surfaceLight,
                              borderRadius: BorderRadius.circular(12.r),
                              border: Border.all(color: c.borderSubtle, width: 0.5),
                            ),
                            child: TextField(
                              controller: _nameController,
                              style: TextStyle(color: c.textPrimary, fontSize: 15.sp, fontWeight: FontWeight.w600),
                              cursorColor: context.colors.accent,
                              decoration: InputDecoration(
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.all(14.w),
                                hintText: context.l10n.accountName,
                                hintStyle: TextStyle(color: c.textTertiary, fontSize: 15.sp),
                                prefixIcon: Icon(Icons.label_outline_rounded, color: c.textTertiary, size: 18.sp),
                              ),
                            ),
                          ),

                          SizedBox(height: 12.h),

                          if (widget.bitcoinOnly) ...[
                            _bitcoinAddressTypeField(),
                            SizedBox(height: 12.h),
                          ],
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(child: Text(
                                context.l10n.recoveryPhraseSectionLabel,
                                style: TextStyle(color: c.textTertiary, fontSize: 14.sp, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                              )),
                              SizedBox(width: 8.w),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  InkWell(
                                    onTap: () {
                                      TrackingService.recoveryQrScannerOpened();
                                      _scanRecoveryQR();
                                    },
                                    borderRadius: BorderRadius.circular(AppRadius.md),
                                    child: Container(
                                      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
                                      decoration: BoxDecoration(
                                        color: c.surfaceLight,
                                        borderRadius: BorderRadius.circular(AppRadius.md),
                                        border: Border.all(color: c.borderSubtle, width: 0.5),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.qr_code_scanner_rounded, size: 14.sp, color: c.textPrimary),
                                          SizedBox(width: 4.w),
                                          Text(context.l10n.scan, style: TextStyle(color: c.textPrimary, fontSize: 14.sp, fontWeight: FontWeight.w600)),
                                        ],
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 8.w),
                                  if (widget.bitcoinOnly) Text('12 words', style: TextStyle(color: c.textSecondary, fontSize: 13.sp)) else _buildWordCountToggle(),
                                ],
                              ),
                            ],
                          ),
                          SizedBox(height: 12.h),
                          SecureContent(child: _buildMnemonicGrid()),
                          SizedBox(height: 12.h),
                          AppButton(
                            key: const ValueKey('recover-paste'),
                            text: context.l10n.paste,
                            icon: Icons.content_paste_rounded,
                            variant: AppButtonVariant.secondary,
                            onPressed: _isProcessing ? null : _pastePhrase,
                          ),

                          SizedBox(height: 16.h),
                        ],
                      ),
                    ),
                  ),
                  if (isKeyboardVisible && _filteredWords.isNotEmpty)
                    SecureContent(
                      hidden: const SizedBox.shrink(),
                      child: _buildSuggestionBar(0),
                    ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(24.w, 12.h, 24.w, 16.h),
                    child: _buildSubmitButton(),
                  ),
                ],
              ),
            ),

          ],
        ),
      ),
    ),
    )));
  }

  Widget _buildWordCountToggle() {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.surfaceLight,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: c.borderSubtle, width: 0.5),
      ),
      padding: EdgeInsets.all(3.sp),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildToggleButton("12", 12),
          _buildToggleButton("24", 24),
        ],
      ),
    );
  }

  Widget _buildToggleButton(String text, int wordCount) {
    final c = context.colors;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    bool isSelected = _totalWords == wordCount;
    return GestureDetector(
      onTap: () {
        TrackingService.recoveryWordCountToggled();
        setState(() => _totalWords = wordCount);
      },
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 14.w),
        decoration: BoxDecoration(
          color: isSelected ? context.colors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isSelected ? contrastingOnColor(c.accent) : c.textSecondary,
            fontSize: 15.sp,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildMnemonicGrid() {
    // Two well-spaced columns instead of the old cramped 3-up grid so
    // words are comfortably readable and tappable.
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10.w,
        mainAxisSpacing: 10.h,
        mainAxisExtent: 52.h,
      ),
      itemCount: _totalWords,
      itemBuilder: (context, index) {
        // Extracted widget (not an inline builder closure) so a live
        // theme change re-resolves Theme.of correctly per repo rule.
        return _WordInputField(
          index: index,
          controller: _controllers[index],
          focusNode: _focusNodes[index],
          isFocused: _focusNodes[index].hasFocus,
          isInvalid: _isWordInvalid(index),
          onSubmitted: () {
            if (index < _totalWords - 1) {
              FocusScope.of(context).requestFocus(_focusNodes[index + 1]);
            } else {
              FocusScope.of(context).unfocus();
            }
          },
        );
      },
    );
  }

  Widget _buildSuggestionBar(double bottomInset) {
    final c = context.colors;
    return Container(
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        color: c.surfaceLight,
        boxShadow: [
          BoxShadow(
            color: c.cardShadow,
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SizedBox(
        height: 52.h,
        child: Row(
          children: _filteredWords.map((word) {
            return Expanded(
              child: GestureDetector(
                onTap: () => _onWordSelected(word),
                child: Container(
                  alignment: Alignment.center,
                  margin: EdgeInsets.symmetric(horizontal: 4.w, vertical: 8.h),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Text(
                    word,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    // Standard primary CTA: default fill/height/typography from
    // AppButton, auto-contrast label, disabled until the grid is full.
    return AppButton(
      text: context.l10n.recoverAccount,
      onPressed:
          (_isProcessing || !_canSubmit) ? null : () => _recoverAccount(context),
      isLoading: _isProcessing,
    );
  }
}

/// One numbered seed-word chip. A standalone widget class (never an
/// inline itemBuilder closure) so Theme/colors re-resolve on live theme
/// changes, per the repo's lazy-list rule.
class _WordInputField extends StatelessWidget {
  final int index;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isFocused;
  final bool isInvalid;
  final VoidCallback onSubmitted;

  const _WordInputField({
    required this.index,
    required this.controller,
    required this.focusNode,
    required this.isFocused,
    required this.isInvalid,
    required this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final borderColor = isFocused
        ? c.accent
        : isInvalid
            ? c.error
            : c.borderSubtle;
    return Container(
      decoration: BoxDecoration(
        color: c.surfaceLight,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: borderColor,
          width: isFocused || isInvalid ? 1.5 : 0.5,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30.w,
            child: Text(
              '${index + 1}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isFocused
                    ? c.accent
                    : isInvalid
                        ? c.error
                        : c.textTertiary,
                fontSize: 13.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              style: TextStyle(
                color: isInvalid ? c.error : c.textPrimary,
                fontSize: 15.sp,
                fontWeight: FontWeight.w600,
              ),
              autocorrect: false,
              cursorColor: c.accent,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: false,
              keyboardType: TextInputType.visiblePassword,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => onSubmitted(),
              decoration: InputDecoration(
                border: InputBorder.none,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 2.w, vertical: 14.h),
                isDense: true,
              ),
            ),
          ),
          if (isInvalid)
            Padding(
              padding: EdgeInsets.only(right: 8.w),
              child: Icon(Icons.error_outline_rounded,
                  color: c.error, size: 16.sp),
            ),
        ],
      ),
    );
  }
}
