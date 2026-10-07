import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:kute/helpers/bbqr.dart';
import 'package:kute/screens/shared/components/sheet_detail_row.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:bc_ur_dart/bc_ur_dart.dart';

/// QR encoding format for PSBT display.
enum QrPsbtFormat {
  /// BC-UR (ur:crypto-psbt) - used by Jade, Passport, SeedSigner, Keystone, BlueWallet.
  ur,
  /// BBQr (B$HP...) - used by BBQr readers (Sparrow, BlueWallet) and
  /// kept for wallets stored with retired BBQr-only device types.
  bbqr,
}

class AnimatedQrView extends ConsumerStatefulWidget {
  final String psbtString;
  final bool defaultStatic;
  final QrPsbtFormat format;

  const AnimatedQrView({
    super.key,
    required this.psbtString,
    this.defaultStatic = false,
    this.format = QrPsbtFormat.ur,
  });

  @override
  ConsumerState<AnimatedQrView> createState() => _AnimatedQrViewState();
}

class _AnimatedQrViewState extends ConsumerState<AnimatedQrView> {
  Timer? _timer;
  String? _currentQrData;

  // BC-UR state
  UR? _ur;
  int _density = 50;
  double _sliderValue = 50;

  // BBQr state
  BbqrSplit? _bbqrSplit;
  int _bbqrFrameIndex = 0;

  // Toggle between animated and static QR
  late bool _isStaticMode = widget.defaultStatic;

  // The encoder controls (animated or single code, frame density) sit
  // behind "Having trouble scanning?" so the QR is the whole surface.
  bool _showScanHelp = false;

  Duration get _frameDuration => widget.format == QrPsbtFormat.bbqr
      ? const Duration(milliseconds: 250) // BBQr spec recommends 250ms
      : const Duration(milliseconds: 800);

  @override
  void initState() {
    super.initState();
    _createEncoder();
    if (!_isStaticMode) _startAnimation();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _createEncoder() {
    try {
      final psbtBytes = base64Decode(widget.psbtString);

      if (widget.format == QrPsbtFormat.bbqr) {
        _bbqrSplit = BbqrSplit.encode(
          data: Uint8List.fromList(psbtBytes),
          fileType: BbqrFileType.psbt,
          maxVersion: 27, // Good balance: 125x125 pixels
        );
        _bbqrFrameIndex = 0;
      } else {
        final cborPayload = Uint8List.fromList(cbor.encode(CborBytes(psbtBytes)));
        _ur = UR(type: 'crypto-psbt', payload: cborPayload, maxLength: _density, minLength: 10);
      }
    } catch (_) {
      _ur = null;
      _bbqrSplit = null;
    }
  }

  void _startAnimation() {
    _timer?.cancel();
    if (widget.format == QrPsbtFormat.bbqr) {
      if (_bbqrSplit == null) return;
      // Single-part PSBT: render the one frame and stop. No timer
      // needed. Without this branch the QR area was stuck on the
      // initial "Loading..." placeholder because the timer-driven
      // path only fired when `parts.length > 1` — a regression after
      // the BBQr split picked v27 (which is bigger and so fits more
      // payloads in a single frame) instead of v5.
      if (_bbqrSplit!.parts.length == 1) {
        setState(() => _currentQrData = _bbqrSplit!.parts.first);
        return;
      }
      _bbqrFrameIndex = 0;
      _nextFrame();
      _timer = Timer.periodic(_frameDuration, (_) => _nextFrame());
    } else {
      if (_ur != null) {
        _nextFrame();
        _timer = Timer.periodic(_frameDuration, (_) => _nextFrame());
      }
    }
  }

  void _stopAnimation() {
    _timer?.cancel();
    _timer = null;
  }

  void _nextFrame() {
    if (!mounted) return;
    setState(() {
      if (widget.format == QrPsbtFormat.bbqr) {
        if (_bbqrSplit == null) return;
        _currentQrData = _bbqrSplit!.parts[_bbqrFrameIndex % _bbqrSplit!.parts.length];
        _bbqrFrameIndex++;
      } else {
        if (_ur == null) return;
        _currentQrData = _ur!.next();
      }
    });
  }

  /// Static-mode payload — only call when [_canDisplayStatic] is true.
  /// Returns the SINGLE complete QR string (BBQr single-part header
  /// + payload, or one full UR encoding). Returning `parts.first` of
  /// a multi-part split here was the source of the "BBQr decode
  /// failed" / "PSBT too big" symptoms — the receiver got only the
  /// first chunk and the rest of the PSBT was inaccessible.
  String _getStaticQrData() {
    try {
      final psbtBytes = base64Decode(widget.psbtString);

      if (widget.format == QrPsbtFormat.bbqr) {
        final split = BbqrSplit.encode(
          data: Uint8List.fromList(psbtBytes),
          fileType: BbqrFileType.psbt,
        );
        return split.parts.first;
      } else {
        final cborPayload = Uint8List.fromList(cbor.encode(CborBytes(psbtBytes)));
        final ur = UR(type: 'crypto-psbt', payload: cborPayload);
        return ur.encode();
      }
    } catch (_) {
      return widget.psbtString;
    }
  }

  /// True when static mode can usefully render the whole PSBT in a
  /// SINGLE QR. For BBQr the answer is binary: only when `parts.length
  /// == 1`. For BC-UR (Jade / BlueWallet / Passport / Keystone /
  /// SeedSigner) the encoder produces a single string regardless of
  /// length and `qr_flutter` will surface its own "too large" error
  /// state when the QR can't fit, so we stay permissive there to
  /// preserve the existing toggle behaviour those wallets rely on.
  /// Only BBQr was producing a misleading "decode failed" because
  /// `parts.first` of a multi-part split looks like a complete QR
  /// to the camera but is structurally incomplete data — that's the
  /// regression this getter is fixing.
  bool get _canDisplayStatic {
    if (widget.format == QrPsbtFormat.bbqr) {
      return _bbqrSplit != null && _bbqrSplit!.parts.length == 1;
    }
    return _ur != null;
  }

  bool get _hasEncoder {
    if (widget.format == QrPsbtFormat.bbqr) return _bbqrSplit != null;
    return _ur != null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    if (_isStaticMode) {
      return _buildStaticQr(c, reduceMotion);
    }

    return _buildAnimatedQr(c, reduceMotion);
  }

  /// Closed disclosure holding the encoder controls. The QR renders
  /// fine without them; they are there for the few devices that need a
  /// single code or a different frame size.
  Widget _buildScanHelp(
      AppColorsExtension c, bool reduceMotion, List<Widget> controls) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: 8.h),
        InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _showScanHelp = !_showScanHelp);
            TrackingService.track('hw_sign_qr_help_toggled',
                params: {'open': _showScanHelp});
          },
          borderRadius: BorderRadius.circular(10.r),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 6.w),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _showScanHelp
                      ? Icons.keyboard_arrow_down_rounded
                      : Icons.keyboard_arrow_right_rounded,
                  size: 18.sp,
                  color: c.textTertiary,
                ),
                SizedBox(width: 4.w),
                // Flexible: at a large text size or in a longer locale the
                // label wraps under the chevron instead of overflowing.
                Flexible(
                  child: Text(
                    context.l10n.qrHavingTroubleScanning,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: c.textTertiary,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SheetAnimatedSize(
          child: _showScanHelp
              ? Column(
                  children: [
                    SizedBox(height: 4.h),
                    ...controls,
                  ],
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildModeToggle(AppColorsExtension c, bool reduceMotion) {
    return Container(
      padding: EdgeInsets.all(3.w),
      decoration: BoxDecoration(
        color: c.surfaceLight,
        borderRadius: BorderRadius.circular(10.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildToggleChip(
            c: c,
            reduceMotion: reduceMotion,
            label: context.l10n.qrModeAnimated,
            icon: Icons.animation,
            isSelected: !_isStaticMode,
            onTap: () {
              setState(() => _isStaticMode = false);
              _startAnimation();
            },
          ),
          _buildToggleChip(
            c: c,
            reduceMotion: reduceMotion,
            label: context.l10n.qrModeStatic,
            icon: Icons.qr_code_2,
            isSelected: _isStaticMode,
            onTap: () {
              _stopAnimation();
              setState(() => _isStaticMode = true);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildToggleChip({
    required AppColorsExtension c,
    required bool reduceMotion,
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
        decoration: BoxDecoration(
          color: isSelected ? c.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(8.r),
          boxShadow: isSelected
              ? [BoxShadow(color: c.cardShadow, blurRadius: 4, offset: const Offset(0, 1))]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14.sp, color: isSelected ? c.textPrimary : c.textTertiary),
            SizedBox(width: 4.w),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? c.textPrimary : c.textTertiary,
                fontSize: 14.sp,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStaticQr(AppColorsExtension c, bool reduceMotion) {
    // Multi-part BBQr can't be rendered as a single QR — `parts.first`
    // is structurally incomplete and the receiver fails decoding.
    // When the user is in static mode but the payload doesn't fit in
    // one QR, fall back to a clear "use animated" prompt instead of
    // showing a broken QR. UR keeps its permissive behaviour so the
    // existing Jade / BlueWallet / Passport flows aren't disturbed.
    if (widget.format == QrPsbtFormat.bbqr && !_canDisplayStatic) {
      return Container(
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(24.r),
          border: Border.all(color: c.borderSubtle),
        ),
        child: Column(
          children: [
            // Always show the toggle so the user can flip back to
            // animated even when static is offering only the
            // "switch modes" prompt — the previous gate on
            // `_hasMultipleParts` left them stranded in static
            // mode with no way out.
            _buildModeToggle(c, reduceMotion),
            SizedBox(height: 16.h),
            SizedBox(height: 24.h),
            Icon(Icons.info_outline_rounded,
                color: c.textTertiary, size: 28.sp),
            SizedBox(height: 12.h),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12.w),
              child: Text(
                context.l10n.qrTooLargeSwitchAnimated(
                    '${_bbqrSplit?.parts.length ?? '?'}'),
                textAlign: TextAlign.center,
                style: TextStyle(color: c.textSecondary, fontSize: 14.sp),
              ),
            ),
            SizedBox(height: 24.h),
          ],
        ),
      );
    }

    final qrData = _getStaticQrData();

    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(24.r),
        border: Border.all(color: c.borderSubtle),
      ),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12.r),
            ),
            padding: EdgeInsets.all(8.w),
            child: AspectRatio(
              aspectRatio: 1,
              child: QrImageView(
                data: qrData,
                version: QrVersions.auto,
                backgroundColor: Colors.white,
                padding: EdgeInsets.zero,
                gapless: true,
                errorStateBuilder: (cxt, err) => Center(
                  child: Padding(
                    padding: EdgeInsets.zero,
                    child: Text(
                      context.l10n.qrTooLargeUseAnimated,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.error, fontSize: 14.sp),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: 12.h),
          Text(
            context.l10n.qrSingleCode,
            style: TextStyle(color: c.textTertiary, fontSize: 14.sp),
          ),
          // The Animated/Static toggle always stays reachable here so a
          // single-part payload never traps the user in static mode.
          _buildScanHelp(c, reduceMotion, [_buildModeToggle(c, reduceMotion)]),
        ],
      ),
    );
  }

  Widget _buildAnimatedQr(AppColorsExtension c, bool reduceMotion) {
    if (!_hasEncoder) {
      return Container(
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(24.r),
          border: Border.all(color: c.borderSubtle),
        ),
        child: SizedBox(
          height: 400.h,
          child: Center(
            child: Text(context.l10n.qrCouldNotBuild, textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary)),
          ),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(24.r),
        border: Border.all(color: c.borderSubtle),
      ),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12.r),
            ),
            padding: EdgeInsets.all(8.w),
            child: AspectRatio(
              aspectRatio: 1,
              child: QrImageView(
                data: _currentQrData ?? "Loading...",
                version: QrVersions.auto,
                backgroundColor: Colors.white,
                padding: EdgeInsets.zero,
                gapless: true,
                errorStateBuilder: (cxt, err) =>
                    Center(child: Text(context.l10n.qrError, style: TextStyle(color: AppColors.error))),
              ),
            ),
          ),

          // Mode toggle plus, for UR only, the density slider (BBQr
          // auto-optimizes), all behind "Having trouble scanning?".
          _buildScanHelp(c, reduceMotion, [
          _buildModeToggle(c, reduceMotion),
          if (widget.format == QrPsbtFormat.ur) ...[
            SizedBox(height: 16.h),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.zoom_out, size: 16, color: c.textTertiary),
                Expanded(
                  child: Slider(
                    value: _sliderValue,
                    min: 30,
                    max: 200,
                    divisions: 17,
                    activeColor: c.textPrimary,
                    inactiveColor: c.surfaceLight,
                    onChanged: (value) {
                      setState(() => _sliderValue = value);
                    },
                    onChangeEnd: (value) {
                      setState(() {
                        _density = value.toInt();
                        _ur = null;
                      });
                      _createEncoder();
                      _startAnimation();
                    },
                  ),
                ),
                Icon(Icons.zoom_in, size: 16, color: c.textTertiary),
              ],
            ),
            Text(
              context.l10n.qrDensityBytes(_sliderValue.toInt()),
              style: TextStyle(color: c.textTertiary, fontSize: 14.sp),
            ),
          ] else ...[
            SizedBox(height: 12.h),
            if (_bbqrSplit != null)
              Text(
                context.l10n.qrFrameCount(_bbqrSplit!.parts.length),
                style: TextStyle(color: c.textTertiary, fontSize: 14.sp),
              ),
          ],
          ]),
        ],
      ),
    );
  }
}
