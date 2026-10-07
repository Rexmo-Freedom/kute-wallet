import 'package:kute/services/tracking_service.dart';
import 'package:kute/controllers/import_wallet_controller.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/helpers/user_error_copy.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';
import 'package:kute/screens/shared/kute_paste_chip.dart';

class ExternalAddressImportScreen extends ConsumerStatefulWidget {
  const ExternalAddressImportScreen({super.key});

  @override
  ConsumerState<ExternalAddressImportScreen> createState() =>
      _ExternalAddressImportScreenState();
}

class _ExternalAddressImportScreenState
    extends ConsumerState<ExternalAddressImportScreen> {
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  String? _expandedMethod;

  // ── wallet_add funnel (categorical only: never the address or name) ──
  final Stopwatch _flowClock = Stopwatch()..start();
  String _flowStep = '';
  /// How the address got in: qr | paste | typed.
  String? _captureMethod;
  String? _lastErrorCategory;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    TrackingService.setFlowContext(
        flow: 'wallet_add',
        step: 'enter_address',
        walletKind: 'external_address');
    _step('enter_address');
  }

  @override
  void dispose() {
    if (!_completed) {
      TrackingService.track('wallet_add_abandoned', params: {
        'step': _flowStep,
        'wallet_kind': 'external_address',
        if (_captureMethod != null) 'method': _captureMethod!,
        'has_address': _addressController.text.trim().isNotEmpty,
        'time_in_flow_bucket': _timeInFlowBucket(_flowClock.elapsed),
        'reason': _lastErrorCategory != null ? 'error' : 'user_closed',
        if (_lastErrorCategory != null)
          'last_error_category': _lastErrorCategory!,
      });
    }
    TrackingService.clearFlowContext('wallet_add');
    _addressController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  /// `wallet_add_step` on a real step change only.
  void _step(String step, {String? method}) {
    if (step == _flowStep) return;
    _flowStep = step;
    TrackingService.setFlowStep(step);
    TrackingService.track('wallet_add_step', params: {
      'step': step,
      'wallet_kind': 'external_address',
      if (method != null) 'method': method,
    });
  }

  void _onScanPressed() async {
    _step('scan_qr', method: 'qr');
    final result = await context.pushNamed<String>('QrScanner');
    if (result != null && result.isNotEmpty) {
      setState(() => _addressController.text = _cleanAddress(result));
      _captureMethod = 'qr';
      _step('address_captured', method: 'qr');
    }
  }

  String _cleanAddress(String raw) {
    String address = raw.trim();
    if (address.toLowerCase().startsWith('bitcoin:')) {
      address = address.substring(8);
      final qIndex = address.indexOf('?');
      if (qIndex != -1) address = address.substring(0, qIndex);
    }
    return address;
  }

  /// Plausibility check for a mainnet Bitcoin address. Gates the
  /// bottom Track CTA and drives the inline validation row so typos
  /// get caught before they reach the import controller.
  static bool _isPlausibleAddress(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return false;
    // Bech32 (native segwit / taproot).
    if (RegExp(r'^bc1[a-zA-HJ-NP-Z0-9]{25,87}$', caseSensitive: false)
        .hasMatch(t)) {
      return true;
    }
    // Legacy P2PKH / P2SH base58.
    if (RegExp(r'^[13][1-9A-HJ-NP-Za-km-z]{25,34}$').hasMatch(t)) {
      return true;
    }
    return false;
  }

  Future<void> _onImportPressed() async {
    _step('importing');
    // The commit point of this screen (same event the other add paths
    // fire on their commit). Never the address or the name.
    TrackingService.track('wallet_add_started', params: {
      'import_method': 'address',
      'wallet_kind': 'external_address',
      'method': _captureMethod ?? 'typed',
      'has_name': _nameController.text.trim().isNotEmpty,
    });
    FocusScope.of(context).unfocus();
    await ref.read(importWalletControllerProvider.notifier).importExternalAddress(
      address: _addressController.text.trim(),
      walletName: _nameController.text.trim(),
    );
  }

  Widget _buildStepRow(int stepNumber, String text, AppColorsExtension c, {bool isActive = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: 10.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22.sp,
            height: 22.sp,
            decoration: BoxDecoration(
              color: c.surfaceLight,
              borderRadius: BorderRadius.circular(8.r),
              border: Border.all(color: isActive ? c.textPrimary : c.borderSubtle),
            ),
            child: Center(
              child: Text(
                "$stepNumber",
                style: TextStyle(
                  color: isActive ? c.textPrimary : c.textSecondary,
                  fontSize: 13.sp,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.bold,
                ),
              ),
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 2.h),
              child: Text(
                text,
                style: TextStyle(color: c.textSecondary, fontSize: 14.sp, height: 1.4),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandableMethodCard({
    required AppColorsExtension c,
    required bool reduceMotion,
    required String methodKey,
    required IconData icon,
    required String label,
    required String description,
    required Widget Function(AppColorsExtension c) contentBuilder,
  }) {
    final isExpanded = _expandedMethod == methodKey;

    // Same chrome as the xpub import screen's method cards so every
    // "pick a way to get a key in" surface reads identically.
    return AnimatedContainer(
      duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18.r),
        border: Border.all(
          color: isExpanded ? c.border : c.borderSubtle,
          width: 0.5,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () {
              final newMethod = isExpanded ? null : methodKey;
              if (newMethod != null) {
                TrackingService.track('external_address_method_selected',
                    params: {'method': newMethod});
              }
              setState(() {
                _expandedMethod = newMethod;
              });
            },
            borderRadius: BorderRadius.circular(18.r),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 18.h),
              child: Row(
                children: [
                  Container(
                    width: 44.sp,
                    height: 44.sp,
                    decoration: BoxDecoration(
                      color: c.textPrimary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Icon(icon, color: c.textPrimary, size: 22.sp),
                  ),
                  SizedBox(width: 14.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label,
                            style: TextStyle(
                                color: c.textPrimary,
                                fontSize: 18.sp,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.3)),
                        SizedBox(height: 3.h),
                        Text(description,
                            style: TextStyle(
                                color: c.textTertiary,
                                fontSize: 14.sp,
                                fontWeight: FontWeight.w500,
                                letterSpacing: -0.1)),
                      ],
                    ),
                  ),
                  SizedBox(width: 8.w),
                  AnimatedRotation(
                    turns: isExpanded ? 0.25 : 0,
                    duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 200),
                    child: Icon(Icons.chevron_right, color: c.textTertiary, size: 22.sp),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: isExpanded
                ? contentBuilder(c)
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressPreview(AppColorsExtension c) {
    final text = _addressController.text;
    final shortAddr = text.length > 40
        ? '${text.substring(0, 20)}...${text.substring(text.length - 20)}'
        : text;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha:0.08),
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: AppColors.success.withValues(alpha:0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: AppColors.success, size: 16.sp),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              shortAddr,
              style: TextStyle(color: c.textSecondary, fontFamily: 'Courier', fontSize: 13.sp),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final importState = ref.watch(importWalletControllerProvider);

    ref.listen(importWalletControllerProvider, (prev, next) {
      if (next is AsyncData) {
        _completed = true;
        TrackingService.clearFlowContext('wallet_add');
        TrackingService.walletCreated(type: 'watch_only');
        TrackingService.walletAdded(
          walletKind: 'external_address',
          importMethod: 'address',
          network: 'bitcoin',
          source: 'add_wallet',
        );
        // The same confirmation every money moment ends on: one check,
        // one line, Done. Done tears down the routes under the overlay
        // and lands on Home, whose wallets menu surfaces the address.
        final router = GoRouter.of(context);
        final rootNav = Navigator.of(context, rootNavigator: true);
        TrackingService.track('track_address_confirmation_shown');
        pushKuteSuccessOverlay(
          navigator: rootNav,
          overlay: KuteConfirmation(
            message: context.l10n.confirmationAddressTracked,
            onDone: () {
              while (rootNav.canPop()) {
                rootNav.pop();
              }
              router.go('/home');
            },
          ),
        );
      }
      if (next is AsyncError) {
        final category = TrackingService.errorCategory(next.error);
        _lastErrorCategory = category;
        TrackingService.track('wallet_add_failed', params: {
          'stage': 'import',
          'error_category': category,
          'import_method': 'address',
          'wallet_kind': 'external_address',
        });
        showMessageSnackBar(
            context: context,
            message: userErrorCopy(context, next.error,
                fallback: context.l10n.errorCopyTrackAddress),
            error: true);
      }
    });

    return KeyboardDismissOnTap(
      child: Scaffold(
        extendBodyBehindAppBar: true,
        backgroundColor: c.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          systemOverlayStyle: Theme.of(context).brightness == Brightness.light
              ? SystemUiOverlayStyle.dark
              : SystemUiOverlayStyle.light,
          centerTitle: true,
          leading: const KuteBackButton(),
          title: Text(context.l10n.trackAddress,
              style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 20.sp,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3)),
          actions: const [],
        ),
        body: Container(
          decoration: AppDecorations.screenGradient(context),
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              Positioned(
                top: -100.h,
                left: 0,
                right: 0,
                height: 400.h,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.topCenter,
                      radius: 1.0,
                      colors: [
                        c.textPrimary.withValues(alpha:0.04),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 1.0],
                    ),
                  ),
                ),
              ),
              SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.symmetric(horizontal: 20.w),
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(height: 8.h),

                            Container(
                              width: double.infinity,
                              padding: EdgeInsets.all(14.w),
                              decoration: BoxDecoration(
                                color: c.surfaceLight.withValues(alpha:0.5),
                                borderRadius: BorderRadius.circular(16.r),
                                border: Border.all(color: c.borderSubtle),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 44.sp,
                                    height: 44.sp,
                                    decoration: BoxDecoration(
                                      color: c.textPrimary.withValues(alpha:0.06),
                                      borderRadius: BorderRadius.circular(12.r),
                                    ),
                                    child: Icon(Icons.visibility_rounded, color: c.textPrimary, size: 22.sp),
                                  ),
                                  SizedBox(width: 14.w),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(context.l10n.trackAddressHeroTitle, style: TextStyle(color: c.textPrimary, fontSize: 16.sp, fontWeight: FontWeight.w700)),
                                        Text(context.l10n.trackAddressHeroSubtitle, style: TextStyle(color: c.textSecondary, fontSize: 14.sp)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: 12.h),

                            Container(
                              decoration: BoxDecoration(
                                color: c.surfaceLight,
                                borderRadius: BorderRadius.circular(12.r),
                                border: Border.all(color: c.borderSubtle, width: 0.5),
                              ),
                              child: TextField(
                                controller: _nameController,
                                style: TextStyle(color: c.textPrimary, fontSize: 15.sp),
                                cursorColor: context.colors.accent,
                                decoration: InputDecoration(
                                  hintText: context.l10n.labelOptional,
                                  hintStyle: TextStyle(color: c.textTertiary, fontSize: 15.sp),
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.all(14.w),
                                  prefixIcon: Icon(Icons.label_outline_rounded, color: c.textTertiary, size: 18.sp),
                                ),
                              ),
                            ),
                            SizedBox(height: 12.h),

                            _buildExpandableMethodCard(
                              c: c,
                              reduceMotion: reduceMotion,
                              methodKey: 'qr',
                              icon: Icons.qr_code_scanner_rounded,
                              label: context.l10n.scanQrCode,
                              description: context.l10n.scanBitcoinAddressQr,
                              contentBuilder: (c) => Padding(
                                padding: EdgeInsets.fromLTRB(14.w, 0, 14.w, 14.h),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Divider(color: c.border, height: 1),
                                    SizedBox(height: 12.h),
                                    _buildStepRow(1, context.l10n.findBitcoinAddressToTrack, c),
                                    _buildStepRow(2, context.l10n.tapToScanQrCode, c, isActive: true),
                                    SizedBox(height: 4.h),
                                    AppButton(
                                      text: context.l10n.scanQrCode,
                                      onPressed: _onScanPressed,
                                      icon: Icons.camera_alt,
                                      textColor: context.ctaOnColor,
                                      compact: true,
                                    ),
                                    if (_addressController.text.isNotEmpty) ...[
                                      SizedBox(height: 12.h),
                                      _buildAddressPreview(c),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            SizedBox(height: 8.h),

                            _buildExpandableMethodCard(
                              c: c,
                              reduceMotion: reduceMotion,
                              methodKey: 'paste',
                              icon: Icons.paste_rounded,
                              label: context.l10n.paste,
                              description: context.l10n.pasteBitcoinAddressFromClipboard,
                              contentBuilder: (c) => Padding(
                                padding: EdgeInsets.fromLTRB(14.w, 0, 14.w, 14.h),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Divider(color: c.border, height: 1),
                                    SizedBox(height: 14.h),
                                    Container(
                                      decoration: BoxDecoration(
                                        color: c.surfaceLight,
                                        borderRadius: BorderRadius.circular(12.r),
                                        border: Border.all(
                                          color: _addressController.text.trim().isEmpty
                                              ? c.borderSubtle
                                              : (_isPlausibleAddress(_addressController.text)
                                                  ? AppColors.success.withValues(alpha: 0.45)
                                                  : c.border),
                                          width: _addressController.text.trim().isEmpty ? 0.5 : 1,
                                        ),
                                      ),
                                      child: TextField(
                                        controller: _addressController,
                                        minLines: 2,
                                        maxLines: 3,
                                        autocorrect: false,
                                        enableSuggestions: false,
                                        style: TextStyle(color: c.textPrimary, fontSize: 15.sp, fontFamily: 'Courier', height: 1.4),
                                        cursorColor: context.colors.accent,
                                        onChanged: (value) {
                                          if (_captureMethod == null &&
                                              value.trim().isNotEmpty) {
                                            _captureMethod = 'typed';
                                          }
                                          setState(() {});
                                        },
                                        decoration: InputDecoration(
                                          hintText: context.l10n.trackAddressPasteHint,
                                          hintStyle: TextStyle(color: c.textTertiary, fontSize: 14.sp),
                                          contentPadding: EdgeInsets.all(12.w),
                                          border: InputBorder.none,
                                        ),
                                      ),
                                    ),
                                    SizedBox(height: 10.h),
                                    // Validation hint on the left, paste
                                    // chip on the right — same row as the
                                    // xpub paste card.
                                    Row(
                                      children: [
                                        Expanded(
                                          child: (_addressController.text.trim().isNotEmpty &&
                                                  !_isPlausibleAddress(_addressController.text))
                                              ? Row(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Icon(Icons.info_outline_rounded, color: c.textTertiary, size: 16.sp),
                                                    SizedBox(width: 6.w),
                                                    Expanded(
                                                      child: Text(
                                                        context.l10n.walletsInvalidAddressHint,
                                                        style: TextStyle(
                                                          color: c.textTertiary,
                                                          fontSize: 13.sp,
                                                          fontWeight: FontWeight.w600,
                                                          height: 1.3,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                )
                                              : const SizedBox.shrink(),
                                        ),
                                        SizedBox(width: 10.w),
                                        KutePasteChip(
                                          onPressed: () async {
                                            final data = await Clipboard.getData(Clipboard.kTextPlain);
                                            if (data?.text != null && mounted) {
                                              setState(() => _addressController.text = _cleanAddress(data!.text!));
                                              TrackingService.track(
                                                  'external_address_paste_clipboard_tapped',
                                                  params: {
                                                    'valid': _isPlausibleAddress(_addressController.text),
                                                  });
                                              _captureMethod = 'paste';
                                              _step('address_captured',
                                                  method: 'paste');
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            SizedBox(height: 16.h),

                            Container(
                              padding: EdgeInsets.all(14.w),
                              decoration: BoxDecoration(
                                color: c.surfaceLight,
                                borderRadius: BorderRadius.circular(12.r),
                                border: Border.all(color: c.borderSubtle, width: 0.5),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.info_outline_rounded, color: c.textTertiary, size: 18.sp),
                                  SizedBox(width: 10.w),
                                  Expanded(
                                    child: Text(
                                      context.l10n.trackAddressWatchOnlyNote,
                                      style: TextStyle(color: c.textSecondary, fontSize: 14.sp, height: 1.4),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            SizedBox(height: 100.h),
                          ],
                        ),
                      ),
                    ),

                    if (_addressController.text.isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, MediaQuery.of(context).padding.bottom + 16.h),
                        decoration: BoxDecoration(
                          color: c.surface,
                          borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
                          border: Border(top: BorderSide(color: c.border)),
                        ),
                        child: AppButton(
                          text: context.l10n.trackAddress,
                          // Disabled until the address looks like a
                          // real mainnet Bitcoin address so typos
                          // never reach the import controller.
                          onPressed: (importState.isLoading ||
                                  !_isPlausibleAddress(_addressController.text))
                              ? null
                              : _onImportPressed,
                          isLoading: importState.isLoading,
                          textColor: context.ctaOnColor,
                        ),
                      ),
                  ],
                ),
              ),
            ],
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
