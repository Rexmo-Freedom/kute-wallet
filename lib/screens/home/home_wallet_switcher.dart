import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/wallet_backup_provider.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

class SecurityActionCard extends ConsumerWidget {
  /// Null is the Home reminder for the spending account. Detail screens pin
  /// their own wallet so no reminder can reveal another wallet's words.
  final String? walletId;

  const SecurityActionCard({super.key, this.walletId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final target = walletId == null
        ? ref.watch(pendingSpendingWalletBackupProvider)
        : ref.watch(settingsProvider).wallets
            .where((wallet) => wallet.id == walletId)
            .firstOrNull;
    if (target == null || !needsWalletBackup(target)) {
      return const SizedBox.shrink();
    }
    // Phase 2 funnel: the prompt is actually on screen. Deduped per
    // surface+wallet per session inside the helper, so rebuilds and
    // remounts do not recount it.
    final surface = walletId == null ? 'home' : 'wallet_detail';
    TrackingService.backupPromptShownOnce(
        surface: surface, walletKey: target.id);
    // One compact neutral row: the whole row is the tap target and the
    // filled "Back up" button is its single visible action. The loss
    // warning lives on the backup screen this opens.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        TrackingService.backupPromptTapped(surface: surface);
        context.push('/backup_wallet', extra: target.id);
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
        // Same chrome as every other card in the app (floating shadow
        // card in light, hairline surface in dark).
        decoration: AppDecorations.card(context),
        child: Row(
          children: [
            Container(
              width: 36.sp,
              height: 36.sp,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.surfaceLight,
                shape: BoxShape.circle,
                border: Border.all(color: c.borderSubtle, width: 0.5),
              ),
              child: Icon(Icons.shield_outlined,
                  color: c.textSecondary, size: 18.sp),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.l10n.backUpBannerTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2)),
                  SizedBox(height: 2.h),
                  Text(context.l10n.backUpBannerSubtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: c.textSecondary,
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w500,
                          height: 1.3)),
                ],
              ),
            ),
            SizedBox(width: 8.w),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 9.h),
              decoration: BoxDecoration(
                color: context.ctaFill,
                borderRadius: AppRadius.buttonBorder,
              ),
              child: Text(
                context.l10n.backUpBannerAction,
                maxLines: 1,
                style: TextStyle(
                  color: context.ctaOnColor,
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.1,
                  height: 1.0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RenameWalletSheet extends ConsumerStatefulWidget {
  final String walletId;
  final String currentName;

  const _RenameWalletSheet({required this.walletId, required this.currentName});

  @override
  ConsumerState<_RenameWalletSheet> createState() => _RenameWalletSheetState();
}

class _RenameWalletSheetState extends ConsumerState<_RenameWalletSheet> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    TrackingService.track('wallet_rename_started',
        params: {'surface': 'wallet_switcher'});
    _controller = TextEditingController(text: widget.currentName);
    _focusNode = FocusNode();
    // `autofocus: true` fires before the modal-bottom-sheet animation
    // finishes; iOS then steals focus back when the sheet settles, so
    // the keyboard never appears. Request focus on the next frame
    // *and* once more after a short delay so we cover both the case
    // where the sheet snaps in fast and the case where it animates.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      Future.delayed(const Duration(milliseconds: 250), () {
        if (!mounted) return;
        if (!_focusNode.hasFocus) _focusNode.requestFocus();
      });
    });
  }

  @override
  void dispose() {
    if (!_saved) {
      TrackingService.track('wallet_rename_cancelled',
          params: {'surface': 'wallet_switcher'});
    }
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return KeyboardDismissOnTap(
      child: Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
          border: Border(top: BorderSide(color: c.border)),
        ),
        child: PlatformSafeArea(
          child: Padding(
            padding: EdgeInsets.all(24.w),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.l10n.renameWallet,
                  style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold, color: c.textPrimary),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 20.h),
                TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  style: TextStyle(color: c.textPrimary, fontSize: 16.sp),
                  decoration: InputDecoration(
                    hintText: context.l10n.walletName,
                    hintStyle: TextStyle(color: c.textTertiary, fontSize: 16.sp),
                    filled: true,
                    fillColor: c.surfaceLight,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16.r), borderSide: BorderSide.none),
                  ),
                ),
                SizedBox(height: 20.h),
                // Dark primary tier; AppButton picks the label contrast
                // (the old hardcoded white label vanished on the white
                // dark-mode fill).
                AppButton(
                  text: context.l10n.save,
                  onPressed: () {
                    final newName = _controller.text.trim();
                    if (newName.isNotEmpty) {
                      ref.read(settingsProvider.notifier).renameWallet(widget.walletId, newName);
                      _saved = true;
                      // Extends walletRenamed(); never the name itself.
                      TrackingService.track('wallet_renamed', params: {
                        'surface': 'wallet_switcher',
                        'changed': newName != widget.currentName.trim(),
                      });
                      context.pop();
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FingerprintEditSheet extends ConsumerStatefulWidget {
  final String walletId;
  final String? currentFingerprint;
  final String? scriptType;

  const _FingerprintEditSheet({
    required this.walletId,
    required this.currentFingerprint,
    required this.scriptType,
  });

  @override
  ConsumerState<_FingerprintEditSheet> createState() =>
      _FingerprintEditSheetState();
}

({String path, String label}) _derivationFor(String? scriptType,
    {bool isMnemonic = false}) {
  // Mnemonic-based wallets are built with `Descriptor.newBip84` in
  // `bitcoin_config_model.dart`, so when scriptType is unset assume
  // BIP84 for them and BIP44 for everything else (matches the import
  // fallback in xpub_import_screen.dart).
  final t = scriptType ?? (isMnemonic ? 'bip84' : 'bip44');
  switch (t) {
    case 'bip49':
      return (path: "m/49'/0'/0'", label: 'Nested SegWit');
    case 'bip84':
      return (path: "m/84'/0'/0'", label: 'Native SegWit');
    case 'bip86':
      return (path: "m/86'/0'/0'", label: 'Taproot');
    case 'bip44':
    default:
      return (path: "m/44'/0'/0'", label: 'Legacy');
  }
}

class _FingerprintEditSheetState extends ConsumerState<_FingerprintEditSheet> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  String? _error;
  bool _saved = false;
  final Set<String> _errorsSeen = {};

  bool get _hadFingerprint =>
      widget.currentFingerprint != null &&
      widget.currentFingerprint != '00000000';

  void _trackInvalid(String reason) {
    if (!_errorsSeen.add(reason)) return;
    TrackingService.track('wallet_fingerprint_invalid',
        params: {'reason': reason});
  }

  @override
  void initState() {
    super.initState();
    // Never the fingerprint itself, only whether one was set.
    TrackingService.track('wallet_fingerprint_edit_started',
        params: {'had_fingerprint': _hadFingerprint});
    final initial = widget.currentFingerprint;
    _controller = TextEditingController(
      text: (initial == null || initial == '00000000') ? '' : initial,
    );
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      Future.delayed(const Duration(milliseconds: 250), () {
        if (!mounted) return;
        if (!_focusNode.hasFocus) _focusNode.requestFocus();
      });
    });
  }

  @override
  void dispose() {
    if (!_saved) {
      TrackingService.track('wallet_fingerprint_edit_cancelled',
          params: {'had_fingerprint': _hadFingerprint});
    }
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final raw = _controller.text.trim().toLowerCase().replaceAll(' ', '');
    if (raw.isEmpty) {
      _trackInvalid('empty');
      setState(() => _error = context.l10n.homeNavEnter8HexCharacters);
      return;
    }
    if (!RegExp(r'^[0-9a-f]{8}$').hasMatch(raw)) {
      _trackInvalid('format');
      setState(
          () => _error = context.l10n.homeNavMustBeExactly8HexCharacters);
      return;
    }

    final wallets = ref.read(settingsProvider).wallets;
    final wallet = wallets.firstWhere(
      (w) => w.id == widget.walletId,
      orElse: () => throw StateError('wallet vanished'),
    );
    final updated = wallet.copyWith(masterFingerprint: raw);
    await ref.read(settingsProvider.notifier).updateWalletConfig(updated);
    _saved = true;
    TrackingService.track('wallet_fingerprint_saved',
        params: {'had_fingerprint': _hadFingerprint});
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return KeyboardDismissOnTap(
      child: Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
          border: Border(top: BorderSide(color: c.border)),
        ),
        child: PlatformSafeArea(
          child: Padding(
            padding: EdgeInsets.all(24.w),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.l10n.homeNavMasterFingerprint,
                  style: TextStyle(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.bold,
                      color: c.textPrimary),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 12.h),
                Text(
                  context.l10n.homeNavPasteYourHardwareWalletFingerprint,
                  style: TextStyle(
                      fontSize: 13.sp,
                      color: c.textSecondary,
                      height: 1.35),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 16.h),
                Builder(builder: (_) {
                  final d = _derivationFor(widget.scriptType);
                  return Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: 14.w, vertical: 10.h),
                    decoration: BoxDecoration(
                      color: c.surfaceLight,
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.account_tree_rounded,
                            size: 14.sp, color: c.textTertiary),
                        SizedBox(width: 8.w),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(context.l10n.homeNavDerivationPath,
                                  style: TextStyle(
                                      fontSize: 13.sp,
                                      color: c.textTertiary)),
                              SizedBox(height: 2.h),
                              Text(
                                '${d.path}  ·  ${d.label}',
                                style: TextStyle(
                                  fontSize: 14.sp,
                                  color: c.textPrimary,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                SizedBox(height: 16.h),
                TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  textCapitalization: TextCapitalization.none,
                  autocorrect: false,
                  enableSuggestions: false,
                  maxLength: 8,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]')),
                  ],
                  style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 16.sp,
                      letterSpacing: 2,
                      fontFeatures: const [FontFeature.tabularFigures()]),
                  decoration: InputDecoration(
                    hintText: 'aabbccdd',
                    counterText: '',
                    errorText: _error,
                    hintStyle:
                        TextStyle(color: c.textTertiary, fontSize: 16.sp),
                    filled: true,
                    fillColor: c.surfaceLight,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16.r),
                        borderSide: BorderSide.none),
                  ),
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                  onSubmitted: (_) => _save(),
                ),
                SizedBox(height: 20.h),
                // Dark primary tier; AppButton picks the label contrast
                // (fixes the hardcoded white-on-white in dark mode).
                AppButton(
                  text: context.l10n.save,
                  onPressed: _save,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
