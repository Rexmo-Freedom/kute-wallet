import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/helpers/pin_attempt_guard.dart';
import 'package:kute/helpers/session_auth.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/auth_model.dart';
import 'package:kute/providers/auth_provider.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/custom_keypad.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// Shared PIN-entry bottom sheet used as the fallback when a
/// biometric (Face ID / Touch ID) prompt is unavailable or the
/// user dismisses it. Originally lived as `_WalletsPinSheet` inside
/// the wallets screen; promoted to a shared widget so the Home
/// hardware-wallets reveal can use the same gate without copy-pasting
/// the keypad + shake animation.
///
/// Caller is responsible for popping the sheet from [onVerified] /
/// [onCancelled] (so the sheet doesn't need to know how it was
/// opened). On success the session is marked unlocked by PIN; the typed
/// PIN is held only while a stored wallet still needs it.
///
/// Wrong PINs count through [PinAttemptGuard]. At the threshold the sheet
/// locks the app and calls [onLocked] (or [onCancelled]); it never wipes.
class PinGateSheet extends ConsumerStatefulWidget {
  final String title;

  /// Optional line under the title. Null renders nothing; callers
  /// should only pass one when it adds information the title lacks.
  final String? subtitle;
  final VoidCallback onVerified;
  final VoidCallback onCancelled;

  /// Called after wrong PINs locked the app. Defaults to [onCancelled].
  final VoidCallback? onLocked;

  /// Names this sheet in the `pin_gate_failed` event.
  final String analyticsSurface;

  const PinGateSheet({
    super.key,
    required this.title,
    this.subtitle,
    required this.onVerified,
    required this.onCancelled,
    this.onLocked,
    this.analyticsSurface = 'pin_gate',
  });

  /// Helper that opens the sheet with the standard modal config used
  /// across the app. Returns once the sheet is dismissed.
  static Future<void> show(
    BuildContext context, {
    required String title,
    String? subtitle,
    required VoidCallback onVerified,
    VoidCallback? onCancelled,
    String analyticsSurface = 'pin_gate',
  }) {
    return showAppBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (ctx) => PinGateSheet(
        title: title,
        subtitle: subtitle,
        analyticsSurface: analyticsSurface,
        onVerified: () {
          Navigator.of(ctx).pop();
          onVerified();
        },
        onCancelled: () {
          Navigator.of(ctx).pop();
          onCancelled?.call();
        },
      ),
    );
  }

  @override
  ConsumerState<PinGateSheet> createState() => _PinGateSheetState();
}

class _PinGateSheetState extends ConsumerState<PinGateSheet>
    with SingleTickerProviderStateMixin {
  String _pin = '';
  bool _isVerifying = false;
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

  PinAttemptGuard get _guard => PinAttemptGuard(ref.read(authModelProvider));

  /// Set on verified / locked so dispose reports only true cancels.
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    TrackingService.track('pin_gate_opened',
        params: {'surface': widget.analyticsSurface});
    _loadLockout();
  }

  void _resolve(String result) {
    if (_resolved) return;
    _resolved = true;
    TrackingService.track('pin_gate_result', params: {
      'surface': widget.analyticsSurface,
      'result': result,
    });
  }

  @override
  void dispose() {
    // Dismissed by Cancel (or the caller) without a verdict.
    _resolve('cancelled');
    _lockoutTimer?.cancel();
    _shake.dispose();
    super.dispose();
  }

  Future<void> _loadLockout() async {
    try {
      final remaining = await _guard.lockoutRemaining();
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
    if (minutes > 0) return '${minutes}m ${secs.toString().padLeft(2, '0')}s';
    return '${secs}s';
  }

  Future<void> _verify() async {
    if (_pin.length != 6 || _isVerifying || _lockoutSeconds > 0) return;
    // Read reduce-motion before the async gap so we don't touch
    // BuildContext after an await.
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    setState(() => _isVerifying = true);
    try {
      final guard = _guard;
      final check = await ref.read(authModelProvider).checkPin(_pin);
      if (check == PinCheck.match) {
        await guard.recordSuccess();
        final dependency = await evaluateV1Dependency(ref);
        if (!mounted) return;
        markSessionUnlocked(ref,
            method: UnlockMethod.pin, typedPin: _pin, dependency: dependency);
        _resolve('verified');
        widget.onVerified();
        return;
      }
      var lockout = Duration.zero;
      if (check == PinCheck.mismatch) {
        final outcome = await guard.recordFailure(
          surface: PinSurface.sheet,
          analyticsSurface: widget.analyticsSurface,
        );
        if (!mounted) return;
        if (outcome.action == PinFailureAction.lockApp) {
          _resolve('locked');
          lockAppAfterSheetLockout(ref);
          (widget.onLocked ?? widget.onCancelled)();
          return;
        }
        lockout = outcome.lockout;
      }
      if (!mounted) return;
      if (!reduceMotion) _shake.forward(from: 0);
      HapticFeedback.heavyImpact();
      setState(() {
        _pin = '';
        _isVerifying = false;
      });
      if (lockout > Duration.zero) _startLockout(lockout);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pin = '';
        _isVerifying = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final subtitle = _lockoutSeconds > 0
        ? context.l10n.lockedForTime(_formatLockout(_lockoutSeconds))
        : widget.subtitle;
    final lockedOut = _lockoutSeconds > 0;
    // No drag handle: the sheet is neither draggable nor dismissible,
    // so a handle would promise a gesture that does nothing.
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
          if (subtitle != null) ...[
            SizedBox(height: 6.h),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 24.w),
              child: Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: lockedOut ? c.error : c.textSecondary,
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
              ignoring: lockedOut,
              child: Opacity(
                opacity: lockedOut ? 0.4 : 1.0,
                child: CustomKeypad(
                  onDigitPressed: (d) {
                    if (_pin.length < 6) {
                      HapticFeedback.lightImpact();
                      setState(() => _pin += d);
                      if (_pin.length == 6) {
                        Future.delayed(
                            const Duration(milliseconds: 100), _verify);
                      }
                    }
                  },
                  onBackspacePressed: () {
                    if (_pin.isNotEmpty) {
                      HapticFeedback.lightImpact();
                      setState(
                          () => _pin = _pin.substring(0, _pin.length - 1));
                    }
                  },
                ),
              ),
            ),
          ),
          SizedBox(height: 16.h),
          AppTextButton(
            text: context.l10n.cancel,
            onPressed: widget.onCancelled,
          ),
          SizedBox(height: 8.h),
        ],
      ),
    );
  }
}
