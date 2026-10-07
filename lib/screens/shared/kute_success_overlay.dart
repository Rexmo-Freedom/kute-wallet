// lib/screens/shared/kute_success_overlay.dart
//
// The one success confirmation used after every money moment: bet
// placed, position sold, winnings claimed, order filled, move sent,
// payment sent, conversion started.
//
// Layout: the app background, a single centered check, a short message
// near the bottom (plus at most one small line when something is still
// pending) and the standard Done button. Nothing else.
//
// Motion: the green disc pops in on a soft spring, the white check
// draws from its short leg to its long leg, then one faint ring expands
// from the disc edge and fades. The success haptic fires exactly when
// the stroke completes. Reduced motion shows the final disc and check at
// once with no pop and no ring.

import 'package:kute/screens/shared/kute_dog_rig.dart';
import 'package:kute/screens/shared/kute_dog_scenes.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/services/success_feedback.dart';
import 'package:kute/theme/app_theme.dart';

/// Push a success confirmation using a pre-captured navigator. Every
/// `pushXxxOverlay` helper routes through this so the route plumbing
/// (fade transition, opaque: false) is identical everywhere.
void pushKuteSuccessOverlay({
  required NavigatorState navigator,
  required Widget overlay,
}) {
  // Respect Reduce Motion: the fade-in is a decorative route transition,
  // so collapse it to zero duration when the user has disabled animations.
  //
  // Read the accessibility flag straight off the platform dispatcher (the
  // same value MediaQueryData.fromView derives `disableAnimations` from),
  // NEVER `MediaQuery.of(navigator.context)`. Looking an inherited widget
  // up through a foreign context registers THAT element as a dependent:
  // this one registered the root Navigator against the app-level
  // MediaQuery, permanently, the first time any success overlay was
  // shown. From then on every metrics change — every keyboard show and
  // hide — marked the whole root Navigator dirty and rebuilt it, which is
  // exactly the wrong thing to be doing while a route is being torn down.
  final reduceMotion = WidgetsBinding
      .instance.platformDispatcher.accessibilityFeatures.disableAnimations;
  navigator.push(
    PageRouteBuilder(
      opaque: false,
      transitionDuration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 300),
      reverseTransitionDuration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 300),
      pageBuilder: (context, _, __) => overlay,
      transitionsBuilder: (context, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────
// KuteConfirmation: the shared screen
// ─────────────────────────────────────────────────────────────────────

/// Full-screen success confirmation: centered check, short message near
/// the bottom, optional pending line, Done button.
class KuteConfirmation extends StatefulWidget {
  /// Short plain sentence, e.g. "Prediction placed".
  final String message;

  final Widget? receipt;
  final bool celebrate;
  final bool success;

  /// Optional small line under the message. Only for flows that must stay
  /// honest about something still pending (e.g. funds still arriving).
  final String? detail;

  /// Done button label. Defaults to the localized "Done".
  final String? buttonText;

  /// What Done does. Each entry point passes its existing navigation.
  final VoidCallback onDone;

  /// Shows the circled close button top left (the shared overlays have
  /// always had one; the send confirmation never did).
  final bool showCloseButton;

  /// A receipt read later (a results-inbox notification): the message is
  /// the heading at the top, above [receipt], instead of a line near the
  /// bottom, and a neutral result shows only the receipt (no mascot).
  final bool messageAboveReceipt;

  /// Optional second, quieter button under the main one.
  final String? secondaryButtonText;
  final VoidCallback? onSecondary;

  const KuteConfirmation({
    super.key,
    required this.message,
    this.receipt,
    this.celebrate = false,
    this.success = true,
    required this.onDone,
    this.detail,
    this.buttonText,
    this.showCloseButton = false,
    this.messageAboveReceipt = false,
    this.secondaryButtonText,
    this.onSecondary,
  });

  /// Test seam for the success haptic. The real haptic schedules a timer,
  /// so widget tests install a fake here.
  @visibleForTesting
  static Future<void> Function()? debugFeedbackOverride;

  // Timeline (ms). Pop 0..350, stroke 300..580, ring and message from 580.
  static const int totalMs = 1080;
  static const int popEndMs = 350;
  static const int strokeStartMs = 300;
  static const int strokeEndMs = 580;
  static const int ringEndMs = 1080;
  static const int messageEndMs = 930;

  @override
  State<KuteConfirmation> createState() => _KuteConfirmationState();
}

class _KuteConfirmationState extends State<KuteConfirmation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _messageOpacity;
  bool _hapticFired = false;
  bool _started = false;

  /// The route's entrance animation while it is still running. The check
  /// waits for it so the pop is not hidden under the route fade.
  Animation<double>? _routeEntrance;

  static double _t(int ms) => ms / KuteConfirmation.totalMs;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: KuteConfirmation.totalMs),
    )..addListener(_maybeFireHaptic);
    _messageOpacity = CurvedAnimation(
      parent: _controller,
      curve: Interval(
        _t(KuteConfirmation.strokeEndMs),
        _t(KuteConfirmation.messageEndMs),
        curve: Curves.easeOut,
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      // Final state at once; the haptic is not motion, so it still fires.
      _controller.value = 1.0;
      return;
    }
    // Wait for the route fade so the pop plays on a fully visible page.
    // The route's animation is only wired up after the first frame (it
    // reports completed while building), so read it post frame.
    final route = ModalRoute.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final entrance = route?.animation;
      if (entrance == null || entrance.status == AnimationStatus.completed) {
        _controller.forward();
      } else {
        _routeEntrance = entrance..addStatusListener(_onRouteEntranceStatus);
      }
    });
  }

  void _onRouteEntranceStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _routeEntrance?.removeStatusListener(_onRouteEntranceStatus);
    _routeEntrance = null;
    if (mounted) _controller.forward();
  }

  void _maybeFireHaptic() {
    if (_hapticFired || !widget.success) return;
    if (_controller.value < _t(KuteConfirmation.strokeEndMs)) return;
    _hapticFired = true;
    // Single choke point for the success haptic: callers never fire it.
    (KuteConfirmation.debugFeedbackOverride ?? moneySuccessFeedback)();
  }

  @override
  void dispose() {
    _routeEntrance?.removeStatusListener(_onRouteEntranceStatus);
    _messageOpacity.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final markSize = 88.sp;
    final detail = widget.detail;
    final above = widget.messageAboveReceipt && widget.receipt != null;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(24.w, 0, 24.w, 12.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Everything above the buttons scrolls as one: the mark
                  // (or the receipt) centred in the room the message leaves,
                  // the message under it near the bottom. On a small screen
                  // or with large text the page scrolls instead of clipping
                  // the message, its detail or the receipt, and the buttons
                  // stay where they are.
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, viewport) => SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints:
                              BoxConstraints(minHeight: viewport.maxHeight),
                          child: Column(
                            mainAxisAlignment: above
                                ? MainAxisAlignment.start
                                : MainAxisAlignment.spaceBetween,
                            children: [
                              // With spaceBetween this empty first child
                              // keeps the mark in the middle of the room
                              // above the message, as it always sat.
                              if (!above) const SizedBox.shrink(),
                              _buildMarkAndReceipt(c, above, reduceMotion,
                                  markSize, detail),
                              if (!above)
                                _buildMessage(context, reduceMotion, detail),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 28.h),
                  AppButton(
                    text: widget.buttonText ?? context.l10n.done,
                    onPressed: widget.onDone,
                  ),
                  if (widget.secondaryButtonText != null &&
                      widget.onSecondary != null) ...[
                    SizedBox(height: 10.h),
                    AppButton(
                      text: widget.secondaryButtonText!,
                      variant: AppButtonVariant.secondary,
                      onPressed: widget.onSecondary,
                    ),
                  ],
                ],
              ),
            ),
            if (widget.showCloseButton)
              Positioned(
                left: 20.w,
                top: 8.h,
                child: const KuteCloseButton(),
              ),
          ],
        ),
      ),
    );
  }

  /// The mark (the check, or Sal with the receipt icon) and the receipt,
  /// with the message on top of the receipt for a read-later receipt.
  Widget _buildMarkAndReceipt(AppColorsExtension c, bool above,
      bool reduceMotion, double markSize, String? detail) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (above && widget.showCloseButton) SizedBox(height: 56.h),
        if (!above || widget.success)
          RepaintBoundary(
            child: ExcludeSemantics(
              child: !widget.success
                  // A receipt view (a pending bet, a notification already
                  // read): Sal sits with it instead of a bare icon.
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        KuteDogIdle(
                            size: 96.sp,
                            cycles: 2,
                            shadowColor:
                                c.textPrimary.withValues(alpha: 0.14)),
                        SizedBox(height: 10.h),
                        Icon(Icons.receipt_long_outlined,
                            size: 34.sp, color: c.textSecondary),
                      ],
                    )
                  : KuteCheckMark(
                      key: const ValueKey('kute-confirmation-check'),
                      animation: _controller,
                      size: markSize,
                      color: widget.celebrate
                          ? const Color(0xFFD4AF37)
                          : AppColors.marketUp,
                      reduceMotion: reduceMotion,
                    ),
            ),
          ),
        if (widget.success) ...[
          SizedBox(height: 8.h),
          // Sal arrives once the check has drawn: fades in with the
          // message, cheers, and throws one burst of confetti. The check
          // itself is untouched.
          FadeTransition(
            opacity: _messageOpacity,
            child: ExcludeSemantics(
              child: KuteDogCelebration(
                size: 84.sp,
                ink: c.textPrimary,
                accent: widget.celebrate
                    ? const Color(0xFFD4AF37)
                    : AppColors.marketUp,
                delay: const Duration(
                    milliseconds: KuteConfirmation.strokeEndMs),
              ),
            ),
          ),
        ],
        if (above) ...[
          if (widget.success) SizedBox(height: 16.h),
          _ReceiptHeading(
            message: widget.message,
            detail: detail,
            opacity:
                widget.success ? _messageOpacity : kAlwaysCompleteAnimation,
          ),
        ],
        if (widget.receipt != null) ...[
          SizedBox(height: above ? 20.h : 24.h),
          widget.receipt!,
        ],
      ],
    );
  }

  /// The message near the bottom and its detail, both wrapped in full: a
  /// line cut off after two lines once hid what to do next.
  Widget _buildMessage(
      BuildContext context, bool reduceMotion, String? detail) {
    return FadeTransition(
      opacity: _messageOpacity,
      child: Semantics(
        liveRegion: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 16.h),
            Text(
              widget.message,
              key: const ValueKey('kute-confirmation-message'),
              textAlign: TextAlign.center,
              style: AppTextStyles.heading2(context).copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
                height: 1.2,
              ),
            ),
            AnimatedSwitcher(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 200),
              child: detail == null || detail.isEmpty
                  ? const SizedBox.shrink()
                  : Padding(
                      key: ValueKey(detail),
                      padding: EdgeInsets.only(top: 6.h),
                      child: Text(
                        detail,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodySmall(context)
                            .copyWith(height: 1.35),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The message as a receipt's heading ([KuteConfirmation.messageAboveReceipt]).
class _ReceiptHeading extends StatelessWidget {
  final String message;
  final String? detail;
  final Animation<double> opacity;
  const _ReceiptHeading(
      {required this.message, required this.detail, required this.opacity});

  @override
  Widget build(BuildContext context) {
    final detail = this.detail;
    return FadeTransition(
      opacity: opacity,
      child: Semantics(
        header: true,
        liveRegion: true,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            message,
            key: const ValueKey('kute-confirmation-message'),
            textAlign: TextAlign.center,
            style: AppTextStyles.heading2(context).copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
              height: 1.2,
            ),
          ),
          if (detail != null && detail.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: 6.h),
              child: Text(
                detail,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall(context).copyWith(height: 1.35),
              ),
            ),
        ]),
      ),
    );
  }
}

/// The animated disc and check. Driven by the confirmation's controller
/// (0..1 over [KuteConfirmation.totalMs]).
class KuteCheckMark extends StatelessWidget {
  final Animation<double> animation;
  final double size;
  final bool reduceMotion;
  final Color color;

  const KuteCheckMark({
    super.key,
    required this.animation,
    required this.size,
    this.reduceMotion = false,
    this.color = AppColors.marketUp,
  });

  /// The ring reaches 1.55x the disc radius, so the paint box leaves room.
  static const double _ringReach = 1.55;

  @override
  Widget build(BuildContext context) {
    final box = size * _ringReach + 4;
    return SizedBox(
      width: box,
      height: box,
      child: CustomPaint(
        painter: _CheckMarkPainter(
          progress: animation,
          discDiameter: size,
          color: color,
          reduceMotion: reduceMotion,
        ),
      ),
    );
  }
}

/// Soft spring from 0 to 1 that overshoots slightly (about 10 percent of
/// the travel) and settles by the end of its interval.
class _SoftSpringCurve extends Curve {
  const _SoftSpringCurve();

  @override
  double transformInternal(double t) =>
      1 - math.exp(-6.5 * t) * math.cos(9.0 * t);
}

class _CheckMarkPainter extends CustomPainter {
  final Animation<double> progress;
  final double discDiameter;
  final Color color;
  final bool reduceMotion;

  _CheckMarkPainter({
    required this.progress,
    required this.discDiameter,
    required this.color,
    required this.reduceMotion,
  }) : super(repaint: progress);

  static double _t(int ms) => ms / KuteConfirmation.totalMs;
  static const _spring = _SoftSpringCurve();

  static double _interval(double value, int startMs, int endMs) =>
      ((value - _t(startMs)) / (_t(endMs) - _t(startMs))).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    final v = reduceMotion ? 1.0 : progress.value;
    final center = size.center(Offset.zero);
    final radius = discDiameter / 2;

    // Ring: one soft expansion from the disc edge, faded out by the end.
    if (!reduceMotion) {
      final ringT = _interval(
          v, KuteConfirmation.strokeEndMs, KuteConfirmation.ringEndMs);
      if (ringT > 0 && ringT < 1) {
        final eased = Curves.easeOut.transform(ringT);
        final ringRadius =
            radius + (radius * (KuteCheckMark._ringReach - 1)) * eased;
        canvas.drawCircle(
          center,
          ringRadius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = radius * 0.06
            ..color = color.withValues(alpha: 0.28 * (1 - eased)),
        );
      }
    }

    if (!reduceMotion && color == const Color(0xFFD4AF37)) {
      final burst = _interval(
          v, KuteConfirmation.strokeEndMs, KuteConfirmation.ringEndMs);
      if (burst > 0 && burst < 1) {
        for (var i = 0; i < 12; i++) {
          final angle = i * math.pi / 6;
          final distance = radius * (1 + .5 * burst);
          canvas.drawCircle(
              center + Offset(math.cos(angle), math.sin(angle)) * distance,
              2.5 * (1 - burst),
              Paint()..color = color.withValues(alpha: 1 - burst));
        }
      }
    }

    // Disc: pops in from 0.6 scale on the spring, fading in quickly.
    final popT = _interval(v, 0, KuteConfirmation.popEndMs);
    final scale = popT >= 1 ? 1.0 : 0.6 + 0.4 * _spring.transform(popT);
    final discOpacity = (popT / 0.3).clamp(0.0, 1.0);
    if (discOpacity <= 0) return;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);
    canvas.drawCircle(
      Offset.zero,
      radius,
      Paint()..color = color.withValues(alpha: discOpacity),
    );

    // Check: drawn from the short leg to the long leg.
    final strokeT = Curves.easeOut.transform(_interval(
        v, KuteConfirmation.strokeStartMs, KuteConfirmation.strokeEndMs));
    if (strokeT > 0) {
      final path = Path()
        ..moveTo(-0.40 * radius, 0.02 * radius)
        ..lineTo(-0.12 * radius, 0.30 * radius)
        ..lineTo(0.42 * radius, -0.28 * radius);
      final metric = path.computeMetrics().first;
      canvas.drawPath(
        metric.extractPath(0, metric.length * strokeT),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = radius * 0.16
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.white,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CheckMarkPainter old) =>
      old.progress != progress ||
      old.discDiameter != discDiameter ||
      old.color != color ||
      old.reduceMotion != reduceMotion;
}

// ─────────────────────────────────────────────────────────────────────
// KuteSuccessOverlay: the entry point used by existing call sites
// ─────────────────────────────────────────────────────────────────────

/// Kept so call sites outside the confirmation wrappers (Cash App
/// purchase, LNURL withdraw, Investing close) need no changes. The screen
/// now shows only the check and [headlineLabel]; [icon], [amount],
/// [statusPill], [subtitle] and [accentCard] are accepted but not shown.
class KuteSuccessOverlay extends StatelessWidget {
  final KuteIconSpec icon;
  final String headlineLabel;
  final String amount;
  final KuteStatusPill? statusPill;
  final String? subtitle;
  final Widget? accentCard;

  /// Small pending line under the message (see [KuteConfirmation.detail]).
  final String? detail;
  final String? ctaText;
  final VoidCallback? onDone;

  const KuteSuccessOverlay({
    super.key,
    this.icon = const KuteIconSpec(),
    required this.headlineLabel,
    this.amount = '',
    this.statusPill,
    this.subtitle,
    this.accentCard,
    this.detail,
    this.ctaText,
    this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    return KuteConfirmation(
      message: _sentenceCase(headlineLabel),
      detail: detail,
      buttonText: ctaText,
      showCloseButton: true,
      onDone: onDone ?? () => context.pop(),
    );
  }
}

/// "BITCOIN PURCHASED" becomes "Bitcoin purchased"; mixed-case input
/// passes through untouched.
String _sentenceCase(String label) {
  final t = label.trim();
  if (t.isEmpty || t != t.toUpperCase()) return t;
  return t[0] + t.substring(1).toLowerCase();
}

/// Icon description accepted by [KuteSuccessOverlay] for call-site
/// compatibility. Not rendered.
class KuteIconSpec {
  final String? imageUrl;
  final String? assetSvg;
  final String? assetImage;
  final IconData fallbackIcon;
  final Color? fallbackTint;
  final bool tintDisc;
  const KuteIconSpec({
    this.imageUrl,
    this.assetSvg,
    this.assetImage,
    this.fallbackIcon = Icons.check_rounded,
    this.fallbackTint,
    this.tintDisc = true,
  });
}

/// Status chip accepted by [KuteSuccessOverlay] for call-site
/// compatibility. Not rendered.
class KuteStatusPill {
  final String text;
  final Color color;
  const KuteStatusPill({required this.text, required this.color});
}
