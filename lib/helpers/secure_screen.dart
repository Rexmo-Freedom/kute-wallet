import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/services/secure/keychain_local.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// A mounted surface that shows or collects recovery phrase words.
abstract class SecureScreenHolder {
  void onCaptureHidden();

  void onScreenshot();
}

/// Capture protection shared by every mounted [SecureScreen], over the
/// `com.kutewallet.app/security` channel.
///
/// `setSecureScreen(enabled)` is sent when the first screen mounts and when
/// the last one goes away:
///   * Android adds or clears `FLAG_SECURE`, so captures come out black.
///   * iOS starts or stops reporting `captureChanged(bool)` (recording or
///     mirroring) and `screenshotTaken()`. [captured] drives
///     [SecureContent]; screenshots and new captures are reported to the
///     most recently mounted screen only.
class SecureScreenController {
  SecureScreenController({
    MethodChannel channel = KeychainLocal.channel,
    this.platform,
  }) : _channel = channel;

  static SecureScreenController _instance = SecureScreenController();

  static SecureScreenController get instance => _instance;

  @visibleForTesting
  static void debugOverride(SecureScreenController controller) {
    _instance.debugDetach();
    _instance = controller;
  }

  @visibleForTesting
  static void debugReset() => debugOverride(SecureScreenController());

  final MethodChannel _channel;
  final TargetPlatform? platform;
  final ValueNotifier<bool> captured = ValueNotifier(false);
  final List<SecureScreenHolder> _holders = [];
  bool _handlerSet = false;

  TargetPlatform get _platform => platform ?? defaultTargetPlatform;

  bool get _isIOS => _platform == TargetPlatform.iOS;

  bool get _supported => _isIOS || _platform == TargetPlatform.android;

  int get activeCount => _holders.length;

  void acquire(SecureScreenHolder holder) {
    _holders.add(holder);
    if (_holders.length != 1 || !_supported) return;
    if (_isIOS && !_handlerSet) {
      _channel.setMethodCallHandler(_handleNativeCall);
      _handlerSet = true;
    }
    unawaited(_invoke<void>('setSecureScreen', {'enabled': true}));
    if (_isIOS) unawaited(_refreshCaptured());
  }

  void release(SecureScreenHolder holder) {
    if (!_holders.remove(holder) || _holders.isNotEmpty || !_supported) return;
    unawaited(_invoke<void>('setSecureScreen', {'enabled': false}));
  }

  @visibleForTesting
  void debugDetach() {
    if (_handlerSet) _channel.setMethodCallHandler(null);
    _handlerSet = false;
    _holders.clear();
  }

  Future<void> _refreshCaptured() async {
    final value = await _invoke<bool>('isCaptured') ?? false;
    if (_holders.isEmpty) return;
    if (value) _holders.last.onCaptureHidden();
    captured.value = value;
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'captureChanged':
        final value = call.arguments == true;
        if (value && !captured.value && _holders.isNotEmpty) {
          _holders.last.onCaptureHidden();
        }
        captured.value = value;
      case 'screenshotTaken':
        if (_holders.isNotEmpty) _holders.last.onScreenshot();
    }
  }

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } catch (_) {
      return null;
    }
  }
}

/// Protects a surface that shows recovery phrase words (D-18). Android
/// blocks screenshots and recording while it is mounted; iOS warns after a
/// screenshot, and [SecureContent] below it hides the words while the screen
/// is recorded or mirrored.
class SecureScreen extends StatefulWidget {
  const SecureScreen({super.key, required this.surface, required this.child});

  /// Analytics name of the surface ('seed_words', 'wallets', ...).
  final String surface;
  final Widget child;

  @override
  State<SecureScreen> createState() => _SecureScreenState();
}

class _SecureScreenState extends State<SecureScreen>
    implements SecureScreenHolder {
  late final SecureScreenController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SecureScreenController.instance;
    _controller.acquire(this);
  }

  @override
  void dispose() {
    _controller.release(this);
    super.dispose();
  }

  @override
  void onCaptureHidden() {
    TrackingService.seedCaptureHidden(surface: widget.surface);
  }

  @override
  void onScreenshot() {
    if (!mounted) return;
    TrackingService.seedScreenshotWarningShown(surface: widget.surface);
    showMessageSnackBar(
      context: context,
      message: context.l10n.seedScreenshotWarning,
      error: true,
      duration: const Duration(seconds: 8),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Shows [child] unless iOS reports that the screen is being recorded or
/// mirrored; then shows [hidden], by default [SeedHiddenNotice].
class SecureContent extends StatelessWidget {
  const SecureContent({super.key, required this.child, this.hidden});

  final Widget child;
  final Widget? hidden;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SecureScreenController.instance.captured,
      builder: (context, captured, _) =>
          captured ? hidden ?? const SeedHiddenNotice() : child,
    );
  }
}

class SeedHiddenNotice extends StatelessWidget {
  const SeedHiddenNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: c.surfaceLight,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: c.borderSubtle, width: 0.5),
        ),
        child: Row(
          children: [
            Icon(Icons.videocam_off_rounded,
                color: c.textSecondary, size: 22.sp),
            SizedBox(width: 12.w),
            Expanded(
              child: Text(
                context.l10n.seedHiddenWhileRecording,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
