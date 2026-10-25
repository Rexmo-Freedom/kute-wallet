// lib/screens/shared/kute_success_overlay.dart
//
// The one result sheet used after every money moment and every other
// outcome worth confirming: bet placed, position sold, winnings claimed,
// order filled or resting, move sent, payment sent, wallet imported,
// backup done, and the failures among them.
//
// Presentation: a bottom sheet over a dimmed scrim, as tall as its
// content. Swiping it down, tapping the scrim or the system back gesture
// all do exactly what Done does. There is no close X.
//
// Layout, left aligned: a header row with the status mark, the title and
// Sal on the right; the amount as the hero; one context line; up to four
// hairline-divided detail rows (the transaction as a row action); the
// primary button and at most one quiet text button.
//
// Motion: the sheet slides up, then the small disc pops in on a soft
// spring and its glyph draws (a check, a "!" for a failure, a clock for
// something pending). As the check lands Sal wags his tail in a quick
// burst (a cheer for a win, ears down for a failure) and settles into his
// idle loop. The success haptic fires exactly when the stroke completes;
// a failure plays the soft failure tap at the same moment instead.
// Reduce Motion shows everything in its final state at once.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_dog_scenes.dart';
import 'package:kute/screens/shared/trade_receipt.dart';
import 'package:kute/services/success_feedback.dart';
import 'package:kute/theme/app_theme.dart';

/// Present a result sheet using a pre-captured navigator. Every
/// `pushXxxOverlay` helper routes through this so the route plumbing is
/// identical everywhere: a transparent route the sheet slides up in.
void pushKuteSuccessOverlay({
  required NavigatorState navigator,
  required Widget overlay,
}) {
  // Respect Reduce Motion: the slide is a decorative route transition, so
  // collapse it to zero duration when the user has disabled animations.
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
          reduceMotion ? Duration.zero : const Duration(milliseconds: 320),
      reverseTransitionDuration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 240),
      pageBuilder: (context, _, __) => overlay,
      // The sheet slides and the scrim fades inside [KuteConfirmation],
      // off this route's animation; the route itself draws nothing.
      transitionsBuilder: (context, animation, _, child) => child,
    ),
  );
}

/// For a flow whose Done would take the user somewhere else (a send goes
/// home): [navigate] there first, then present [overlay] over the screen
/// they land on, so Done only has to close the sheet. The sheet is pushed
/// once the navigation's frame has run: pushed earlier, it would sit on
/// the page being replaced and leave with it.
Future<void> pushKuteSuccessOverlayAfter({
  required NavigatorState navigator,
  required VoidCallback navigate,
  required Widget overlay,
}) async {
  navigate();
  await WidgetsBinding.instance.endOfFrame;
  if (!navigator.mounted) return;
  pushKuteSuccessOverlay(navigator: navigator, overlay: overlay);
}

/// What a result sheet is saying, which picks its mark, Sal's mood and
/// the haptic.
enum KuteConfirmationTone {
  /// Done. Green check, Sal wags, the success haptic.
  success,

  /// A win (winnings, a won prediction). Gold check, Sal cheers, the
  /// success haptic.
  celebrate,

  /// Accepted but not finished (an order resting, funds on their way).
  /// Neutral clock, Sal calm, no haptic.
  pending,

  /// It did not happen. Red "!", Sal's ears down, the failure tap.
  failure,

  /// A result read again later. Neutral receipt glyph, Sal calm, no
  /// haptic.
  neutral,
}

// ─────────────────────────────────────────────────────────────────────
// KuteConfirmation: the shared sheet
// ─────────────────────────────────────────────────────────────────────

/// The result sheet. See the file header for the layout.
class KuteConfirmation extends StatefulWidget {
  /// The title beside the mark: a short plain sentence, e.g. "Prediction
  /// placed", "Couldn't send".
  final String message;

  /// The hero line, whenever the flow has an amount: "$5.00 on Yes",
  /// "Long $12.00", "0.001 BTC". Shown large and tabular.
  final String? amount;

  /// One line of context under the amount: the recipient, the market, "to
  /// Bitcoin".
  final String? contextLine;

  /// Label/value rows under the context, in order. Keep it to four.
  final Map<String, String> rows;

  /// The on-chain transaction, as a "View on blockchain" row action.
  final TradeReceiptTransaction? transaction;

  /// A small honest line for something still pending (funds arriving, a
  /// balance updating), or, on a failure, where the money is. Under the
  /// context line, or under the rows when there are rows.
  final String? detail;

  /// Legacy receipt slot. A [TradeReceipt] is read into the sheet's own
  /// parts (its title becomes the context line, its first row the amount,
  /// the rest rows, its transaction the row action) wherever those are not
  /// given directly; any other widget is shown under the rows (the send
  /// failure's Details disclosure).
  final Widget? receipt;

  /// What the sheet says. Null derives it from [celebrate] and [success].
  final KuteConfirmationTone? tone;
  final bool celebrate;
  final bool success;

  /// Primary button label. Defaults to the localized "Done".
  final String? buttonText;

  /// What Done does. Each entry point passes its existing navigation.
  /// Swiping the sheet down, tapping the scrim and the system back gesture
  /// run it too.
  final VoidCallback onDone;

  /// One optional quiet text button under the primary one.
  final String? secondaryButtonText;
  final VoidCallback? onSecondary;

  /// Accepted for call-site compatibility; the sheet has no close button.
  final bool showCloseButton;

  /// Accepted for call-site compatibility; the title always heads the
  /// sheet.
  final bool messageAboveReceipt;

  const KuteConfirmation({
    super.key,
    required this.message,
    this.amount,
    this.contextLine,
    this.rows = const {},
    this.transaction,
    this.receipt,
    this.tone,
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

  /// Test seams for the haptics. The real ones schedule timers, so widget
  /// tests install fakes here.
  @visibleForTesting
  static Future<void> Function()? debugFeedbackOverride;
  @visibleForTesting
  static Future<void> Function()? debugFailureFeedbackOverride;

  // Timeline (ms) after the sheet is up. Pop 0..350, stroke 300..580, ring
  // from 580. Sal wakes a beat before the stroke ends so his wag and the
  // check land together.
  static const int totalMs = 1080;
  static const int popEndMs = 350;
  static const int strokeStartMs = 300;
  static const int strokeEndMs = 580;
  static const int ringEndMs = 1080;
  static const int salWakeMs = 480;

  /// The tone [tone], or the one the legacy flags describe.
  KuteConfirmationTone get resolvedTone =>
      tone ??
      (celebrate
          ? KuteConfirmationTone.celebrate
          : success
              ? KuteConfirmationTone.success
              : KuteConfirmationTone.failure);

  @override
  State<KuteConfirmation> createState() => _KuteConfirmationState();
}

class _KuteConfirmationState extends State<KuteConfirmation>
    with TickerProviderStateMixin {
  late final AnimationController _controller;

  /// The sheet's drag offset in logical pixels, down from rest.
  late final AnimationController _drag;
  final _sheetKey = GlobalKey();
  bool _feedbackFired = false;
  bool _salAwake = false;
  bool _started = false;
  bool _closing = false;

  /// The route's entrance animation while it is still running. The mark
  /// waits for it so the pop is not hidden under the slide.
  Animation<double>? _routeEntrance;
  Animation<double> _entrance = kAlwaysCompleteAnimation;
  CurvedAnimation? _slide;

  static double _t(int ms) => ms / KuteConfirmation.totalMs;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: KuteConfirmation.totalMs),
    )..addListener(_onTick);
    _drag = AnimationController.unbounded(vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final entrance = ModalRoute.of(context)?.animation;
    if (entrance != null && entrance != _entrance) {
      _entrance = entrance;
      _slide?.dispose();
      _slide = CurvedAnimation(
        parent: entrance,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
    }
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      // Final state at once; the haptic is not motion, so it still fires.
      _controller.value = 1.0;
      return;
    }
    // Wait for the slide so the pop plays on a sheet that is all there.
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

  void _onTick() {
    final v = _controller.value;
    if (!_salAwake && v >= _t(KuteConfirmation.salWakeMs)) {
      setState(() => _salAwake = true);
    }
    if (_feedbackFired || v < _t(KuteConfirmation.strokeEndMs)) return;
    _feedbackFired = true;
    // Single choke point for the result haptic: callers never fire the
    // success one, and the failure one claims its moment once, so a
    // caller that already played it stays the only tap.
    switch (widget.resolvedTone) {
      case KuteConfirmationTone.success || KuteConfirmationTone.celebrate:
        (KuteConfirmation.debugFeedbackOverride ?? moneySuccessFeedback)();
      case KuteConfirmationTone.failure:
        (KuteConfirmation.debugFailureFeedbackOverride ??
            moneyFailureFeedback)();
      case KuteConfirmationTone.pending || KuteConfirmationTone.neutral:
        break;
    }
  }

  /// Runs [action] once for any of the ways out (Done, the secondary
  /// button, a swipe, the scrim, back). If the sheet is still the top
  /// route a frame later (an action that navigates nowhere), it takes
  /// taps again and springs back from any drag.
  void _finish(VoidCallback? action) {
    if (_closing || action == null) return;
    _closing = true;
    action();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ModalRoute.of(context)?.isCurrent ?? true) {
        _closing = false;
        _settleDrag();
      }
    });
  }

  void _settleDrag() {
    if (_drag.value == 0) return;
    _drag.animateTo(0,
        duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_closing) return;
    _drag.value = math.max(0, _drag.value + details.delta.dy);
  }

  void _onDragEnd(DragEndDetails details) {
    if (_closing) return;
    final height = _sheetKey.currentContext?.size?.height ?? 400;
    if (_drag.value > height * 0.25 ||
        details.velocity.pixelsPerSecond.dy > 700) {
      _finish(widget.onDone);
    } else {
      _settleDrag();
    }
  }

  @override
  void dispose() {
    _routeEntrance?.removeStatusListener(_onRouteEntranceStatus);
    _slide?.dispose();
    _drag.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final slide = _slide ?? kAlwaysCompleteAnimation;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finish(widget.onDone);
      },
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                key: const ValueKey('kute-confirmation-scrim'),
                behavior: HitTestBehavior.opaque,
                onTap: () => _finish(widget.onDone),
                child: FadeTransition(
                  opacity: _entrance,
                  child: ColoredBox(color: c.modalBarrier),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: AnimatedBuilder(
                animation: Listenable.merge([slide, _drag]),
                builder: (context, child) => FractionalTranslation(
                  translation: Offset(0, 1 - slide.value),
                  child: Transform.translate(
                    offset: Offset(0, _drag.value),
                    child: child,
                  ),
                ),
                child: _buildSheet(context, c),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSheet(BuildContext context, AppColorsExtension c) {
    final media = MediaQuery.of(context);
    final parts = _SheetParts.of(widget);
    final secondary = widget.secondaryButtonText;
    return GestureDetector(
      onVerticalDragUpdate: _onDragUpdate,
      onVerticalDragEnd: _onDragEnd,
      child: Container(
        key: _sheetKey,
        width: double.infinity,
        constraints: BoxConstraints(maxHeight: media.size.height * 0.92),
        decoration: AppDecorations.bottomSheet(context),
        padding: EdgeInsets.fromLTRB(
            20.w, 0, 20.w, math.max(media.padding.bottom, 12.h) + 8.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: 10.h),
            AppDecorations.dragHandle(context),
            SizedBox(height: 18.h),
            // Everything above the buttons scrolls as one, so large text
            // or a long receipt scrolls instead of clipping; the buttons
            // stay put.
            Flexible(
              child: SingleChildScrollView(
                child: _buildContent(context, c, parts),
              ),
            ),
            SizedBox(height: 24.h),
            AppButton(
              text: widget.buttonText ?? context.l10n.done,
              onPressed: () => _finish(widget.onDone),
            ),
            if (secondary != null && widget.onSecondary != null) ...[
              SizedBox(height: 6.h),
              AppTextButton(
                key: const ValueKey('kute-confirmation-secondary'),
                text: secondary,
                textColor: c.textPrimary,
                onPressed: () => _finish(widget.onSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildContent(
      BuildContext context, AppColorsExtension c, _SheetParts parts) {
    final tone = widget.resolvedTone;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final amount = parts.amount;
    final contextLine = parts.contextLine;
    final detail = widget.detail;
    final hasRows = parts.rows.isNotEmpty || parts.transaction != null;
    final detailText = detail == null || detail.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            key: ValueKey(detail),
            padding: EdgeInsets.only(top: hasRows ? 14.h : 6.h),
            child: Text(
              detail,
              key: const ValueKey('kute-confirmation-detail'),
              style: TextStyle(
                color: c.textSecondary,
                fontSize: hasRows ? 13.sp : 15.sp,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          );
    final animatedDetail = AnimatedSwitcher(
      duration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 200),
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topLeft,
        children: [...previous, if (current != null) current],
      ),
      child: detailText,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ExcludeSemantics(
              child: KuteStatusMark(
                key: const ValueKey('kute-confirmation-check'),
                animation: _controller,
                tone: tone,
                size: 30.sp,
                reduceMotion: reduceMotion,
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Semantics(
                header: true,
                liveRegion: true,
                child: Text(
                  widget.message,
                  key: const ValueKey('kute-confirmation-message'),
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 19.sp,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    height: 1.25,
                  ),
                ),
              ),
            ),
            SizedBox(width: 12.w),
            ExcludeSemantics(
              child: KuteDogConfirmation(
                key: const ValueKey('kute-confirmation-sal'),
                size: 42.sp,
                awake: _salAwake,
                mood: switch (tone) {
                  KuteConfirmationTone.success => KuteDogMood.happy,
                  KuteConfirmationTone.celebrate => KuteDogMood.cheer,
                  KuteConfirmationTone.failure => KuteDogMood.sad,
                  KuteConfirmationTone.pending ||
                  KuteConfirmationTone.neutral =>
                    KuteDogMood.calm,
                },
              ),
            ),
          ],
        ),
        if (amount != null && amount.isNotEmpty) ...[
          SizedBox(height: 16.h),
          Text(
            amount,
            key: const ValueKey('kute-confirmation-amount'),
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 34.sp,
              fontWeight: FontWeight.w700,
              letterSpacing: -1.0,
              height: 1.12,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
        if (contextLine != null && contextLine.isNotEmpty) ...[
          SizedBox(height: amount == null || amount.isEmpty ? 12.h : 6.h),
          Text(
            contextLine,
            key: const ValueKey('kute-confirmation-context'),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c.textSecondary,
              fontSize: 15.sp,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
        ],
        if (!hasRows) animatedDetail,
        if (hasRows) ...[
          SizedBox(height: 18.h),
          _ConfirmationRows(rows: parts.rows, transaction: parts.transaction),
        ],
        if (parts.extra != null) ...[
          SizedBox(height: 12.h),
          parts.extra!,
        ],
        if (hasRows) animatedDetail,
      ],
    );
  }
}

/// The sheet's content with a legacy [TradeReceipt] read in.
class _SheetParts {
  final String? amount;
  final String? contextLine;
  final Map<String, String> rows;
  final TradeReceiptTransaction? transaction;
  final Widget? extra;

  const _SheetParts({
    required this.amount,
    required this.contextLine,
    required this.rows,
    required this.transaction,
    required this.extra,
  });

  factory _SheetParts.of(KuteConfirmation w) {
    final receipt = w.receipt;
    if (receipt is! TradeReceipt) {
      return _SheetParts(
        amount: w.amount,
        contextLine: w.contextLine,
        rows: w.rows,
        transaction: w.transaction,
        extra: receipt,
      );
    }
    final entries = receipt.rows.entries.toList();
    final takeHero = w.amount == null && entries.isNotEmpty;
    final subtitle = receipt.subtitle;
    return _SheetParts(
      amount: w.amount ?? (takeHero ? entries.first.value : null),
      contextLine: w.contextLine ??
          (subtitle == null || subtitle.isEmpty
              ? receipt.title
              : '$subtitle · ${receipt.title}'),
      rows: w.rows.isNotEmpty
          ? w.rows
          : {for (final e in entries.skip(takeHero ? 1 : 0)) e.key: e.value},
      transaction: w.transaction ?? receipt.transaction,
      extra: null,
    );
  }
}

/// Hairline-divided label/value rows, the transaction last as a row
/// action. The label gives way first: numbers stay on one line, right
/// aligned; only long sentences wrap.
class _ConfirmationRows extends StatelessWidget {
  final Map<String, String> rows;
  final TradeReceiptTransaction? transaction;

  const _ConfirmationRows({required this.rows, required this.transaction});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tx = transaction;
    final labelStyle = TextStyle(
        color: c.textSecondary, fontSize: 14.sp, fontWeight: FontWeight.w500);
    final valueStyle = TextStyle(
      color: c.textPrimary,
      fontSize: 15.sp,
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final divider = Divider(height: 1, thickness: 0.5, color: c.border);
    return LayoutBuilder(
      builder: (context, box) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in rows.entries) ...[
            divider,
            Padding(
              padding: EdgeInsets.symmetric(vertical: 12.h),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Text(entry.key, style: labelStyle)),
                  SizedBox(width: 16.w),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: box.maxWidth * .6),
                    child: Text(entry.value,
                        textAlign: TextAlign.end, style: valueStyle),
                  ),
                ],
              ),
            ),
          ],
          if (tx != null) ...[
            divider,
            InkWell(
              key: const ValueKey('trade-receipt-explorer'),
              onTap: tx.open,
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12.h),
                child: Row(
                  children: [
                    Expanded(
                        child: Text(context.l10n.tnTransaction,
                            style: labelStyle)),
                    Text(context.l10n.activityViewOnBlockchain,
                        style: valueStyle),
                    SizedBox(width: 6.w),
                    Icon(Icons.open_in_new_rounded,
                        size: 15.sp, color: c.textPrimary),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// KuteStatusMark: the small disc in the header row
// ─────────────────────────────────────────────────────────────────────

/// The animated disc and its glyph. Driven by the sheet's controller
/// (0..1 over [KuteConfirmation.totalMs]). Laid out at [size]; the ring
/// paints a little beyond it.
class KuteStatusMark extends StatelessWidget {
  final Animation<double> animation;
  final KuteConfirmationTone tone;
  final double size;
  final bool reduceMotion;

  const KuteStatusMark({
    super.key,
    required this.animation,
    required this.size,
    this.tone = KuteConfirmationTone.success,
    this.reduceMotion = false,
  });

  /// The disc colour for [tone]: one success green (the theme's success
  /// token), the theme's error red, the gold [AppColors.celebrate], and
  /// a neutral fill for pending and read-later results.
  static Color discColor(BuildContext context, KuteConfirmationTone tone) {
    final c = context.colors;
    return switch (tone) {
      KuteConfirmationTone.success => c.success,
      KuteConfirmationTone.celebrate => AppColors.celebrate,
      KuteConfirmationTone.failure => c.error,
      KuteConfirmationTone.pending ||
      KuteConfirmationTone.neutral =>
        c.surfaceElevated,
    };
  }

  static Color glyphColor(BuildContext context, KuteConfirmationTone tone) =>
      switch (tone) {
        KuteConfirmationTone.pending ||
        KuteConfirmationTone.neutral =>
          context.colors.textPrimary,
        _ => Colors.white,
      };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _StatusMarkPainter(
          progress: animation,
          tone: tone,
          color: discColor(context, tone),
          glyph: glyphColor(context, tone),
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

class _StatusMarkPainter extends CustomPainter {
  final Animation<double> progress;
  final KuteConfirmationTone tone;
  final Color color;
  final Color glyph;
  final bool reduceMotion;

  _StatusMarkPainter({
    required this.progress,
    required this.tone,
    required this.color,
    required this.glyph,
    required this.reduceMotion,
  }) : super(repaint: progress);

  static double _t(int ms) => ms / KuteConfirmation.totalMs;
  static const _spring = _SoftSpringCurve();
  static const double _ringReach = 1.55;

  static double _interval(double value, int startMs, int endMs) =>
      ((value - _t(startMs)) / (_t(endMs) - _t(startMs))).clamp(0.0, 1.0);

  /// The glyph for [tone] in a disc of radius [r] centred on the origin.
  Path _glyph(double r) => switch (tone) {
        KuteConfirmationTone.success || KuteConfirmationTone.celebrate => Path()
          ..moveTo(-0.40 * r, 0.02 * r)
          ..lineTo(-0.12 * r, 0.30 * r)
          ..lineTo(0.42 * r, -0.28 * r),
        // The "!" stroke; its dot is drawn once the stroke is done.
        KuteConfirmationTone.failure => Path()
          ..moveTo(0, -0.44 * r)
          ..lineTo(0, 0.10 * r),
        // Clock hands.
        KuteConfirmationTone.pending => Path()
          ..moveTo(0, -0.38 * r)
          ..lineTo(0, 0)
          ..lineTo(0.28 * r, 0.14 * r),
        // Receipt lines.
        KuteConfirmationTone.neutral => Path()
          ..moveTo(-0.36 * r, -0.26 * r)
          ..lineTo(0.36 * r, -0.26 * r)
          ..moveTo(-0.36 * r, 0)
          ..lineTo(0.36 * r, 0)
          ..moveTo(-0.36 * r, 0.26 * r)
          ..lineTo(0.12 * r, 0.26 * r),
      };

  @override
  void paint(Canvas canvas, Size size) {
    final v = reduceMotion ? 1.0 : progress.value;
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final celebratory = tone == KuteConfirmationTone.success ||
        tone == KuteConfirmationTone.celebrate;

    // Ring: one soft expansion from the disc edge, faded out by the end.
    if (!reduceMotion && celebratory) {
      final ringT = _interval(
          v, KuteConfirmation.strokeEndMs, KuteConfirmation.ringEndMs);
      if (ringT > 0 && ringT < 1) {
        final eased = Curves.easeOut.transform(ringT);
        canvas.drawCircle(
          center,
          radius + radius * (_ringReach - 1) * eased,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.0, radius * 0.08)
            ..color = color.withValues(alpha: 0.32 * (1 - eased)),
        );
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
      Paint()..color = color.withValues(alpha: color.a * discOpacity),
    );

    // Glyph: drawn along its path.
    final strokeT = Curves.easeOut.transform(_interval(
        v, KuteConfirmation.strokeStartMs, KuteConfirmation.strokeEndMs));
    if (strokeT > 0) {
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.17
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = glyph;
      final metrics = _glyph(radius).computeMetrics().toList();
      final total = metrics.fold<double>(0, (sum, m) => sum + m.length);
      var remaining = total * strokeT;
      for (final metric in metrics) {
        if (remaining <= 0) break;
        canvas.drawPath(
            metric.extractPath(0, math.min(metric.length, remaining)), stroke);
        remaining -= metric.length;
      }
      if (tone == KuteConfirmationTone.failure && strokeT >= 1) {
        canvas.drawCircle(
            Offset(0, 0.40 * radius), radius * 0.1, Paint()..color = glyph);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _StatusMarkPainter old) =>
      old.progress != progress ||
      old.tone != tone ||
      old.color != color ||
      old.glyph != glyph ||
      old.reduceMotion != reduceMotion;
}

// ─────────────────────────────────────────────────────────────────────
// KuteSuccessOverlay: the entry point used by older call sites
// ─────────────────────────────────────────────────────────────────────

/// The result sheet from the older parameter set: [headlineLabel] is the
/// title (in sentence case), [amount] the hero, [subtitle] the context
/// line, [detail] the pending line. [icon] is accepted but not shown.
class KuteSuccessOverlay extends StatelessWidget {
  final KuteIconSpec icon;
  final String headlineLabel;
  final String amount;
  final String? subtitle;

  /// Small pending line (see [KuteConfirmation.detail]).
  final String? detail;
  final Map<String, String> rows;
  final String? ctaText;
  final VoidCallback? onDone;

  const KuteSuccessOverlay({
    super.key,
    this.icon = const KuteIconSpec(),
    required this.headlineLabel,
    this.amount = '',
    this.subtitle,
    this.detail,
    this.rows = const {},
    this.ctaText,
    this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    return KuteConfirmation(
      message: _sentenceCase(headlineLabel),
      amount: amount.isEmpty ? null : amount,
      contextLine: subtitle,
      rows: rows,
      detail: detail,
      buttonText: ctaText,
      onDone: onDone ?? () => Navigator.of(context).pop(),
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
