import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/qr_scanner_provider.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QRScannerScreen extends ConsumerStatefulWidget {
  const QRScannerScreen({super.key});

  @override
  ConsumerState<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends ConsumerState<QRScannerScreen> {
  late final MobileScannerController _cameraController;

  /// Set when a code was handed back, so dispose can report a dismiss.
  /// Nothing about the code itself is ever sent: this scanner also reads
  /// recovery phrases and PSBTs.
  bool _completed = false;
  bool _animatedSeen = false;
  double _lastProgress = 0;

  @override
  void initState() {
    super.initState();
    _cameraController = MobileScannerController(
      // Animated PSBT QRs (Sparrow BBQr, Jade UR, Passport UR) cycle
      // frames at 4–8 fps. `DetectionSpeed.normal` throttles to one
      // detection per `detectionTimeoutMs` (250 ms default = 4 fps),
      // which on a 6-part BBQr PSBT was missing every other frame
      // and the user saw "0 of 6 parts scanned" stick. `unrestricted`
      // disables the throttle so every camera frame goes through the
      // ZXing pipeline; the QrScannerNotifier dedupes identical frames
      // via `_processedParts`, so there's no risk of double-counting.
      detectionSpeed: DetectionSpeed.noDuplicates,
      returnImage: false,
      torchEnabled: false,
      formats: [BarcodeFormat.qrCode],
    );
  }

  @override
  void dispose() {
    if (!_completed) {
      TrackingService.track('qr_scanner_dismissed', params: {
        'animated_in_progress': _animatedSeen,
        'progress_bucket': _progressBucket(_lastProgress),
      });
    }
    _cameraController.dispose();
    super.dispose();
  }

  static String _progressBucket(double p) {
    if (p <= 0) return 'none';
    if (p < 0.5) return '<50%';
    if (p < 1) return '50-99%';
    return 'complete';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    final scannerState = ref.watch(qrScannerProvider);
    final scannerNotifier = ref.read(qrScannerProvider.notifier);

    ref.listen<QrScannerState>(qrScannerProvider, (previous, next) {
      if (next.isScanningAnimated) {
        _animatedSeen = true;
        _lastProgress = next.progress;
      }
      if (next.hasResult && next.resultData != null) {
        _cameraController.stop();
        if (mounted) {
          if (!_completed) {
            _completed = true;
            TrackingService.track('qr_scanner_completed', params: {
              'animated': next.isScanningAnimated || _animatedSeen,
            });
          }
          context.pop(next.resultData);
        }
      }
    });

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        elevation: 0,
        leading: Center(
          child: KuteCloseButton(onPressed: () => context.pop()),
        ),
        actions: [
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _cameraController,
            builder: (context, state, child) {
              final isOn = state.torchState == TorchState.on;
              return IconButton(
                icon: Icon(
                  isOn ? Icons.flash_on : Icons.flash_off,
                  color: isOn ? context.colors.accent : c.textSecondary,
                ),
                onPressed: () {
                  TrackingService.track('qr_scanner_torch_toggled',
                      params: {'enabled': !isOn});
                  _cameraController.toggleTorch();
                },
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20.r),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  MobileScanner(
                    controller: _cameraController,
                    onDetect: scannerNotifier.onDetect,
                  ),
                  // Scan frame overlay
                  Container(
                    width: 260.sp,
                    height: 260.sp,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20.r),
                      border: Border.all(color: context.colors.accent.withValues(alpha:0.6), width: 2),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 16.h),
          if (scannerState.isScanningAnimated)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4.r),
                child: LinearProgressIndicator(
                  value: scannerState.progress > 0 ? scannerState.progress : null,
                  backgroundColor: c.surfaceLight,
                  valueColor: AlwaysStoppedAnimation<Color>(context.colors.accent),
                  minHeight: 4.h,
                ),
              ),
            ),
          SizedBox(height: 12.h),
          // One plain line: the progress bar above already shows how
          // much of an animated code has been read.
          Text(
            scannerState.isScanningAnimated
                ? context.l10n.scannerKeepInFrame
                : context.l10n.scannerPointAtCode,
            style: TextStyle(color: c.textSecondary, fontSize: 16.sp),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 24.h),
        ],
      ),
    );
  }
}
