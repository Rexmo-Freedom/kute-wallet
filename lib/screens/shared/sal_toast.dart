// lib/screens/shared/sal_toast.dart
//
// THE SAL TOAST (founder, 9 November 2026: "it is super important that we
// substitute the toolbar on top of an error or something with a modern Sal
// one, saying prediction placed and a success Sal", and "haptics when the
// bet is placed, with a little confirmation of Sal on top"). Every message
// the app drops in from the top of the screen is this one pill:
// showMessageSnackBar's call sites (message_display.dart) and the venues'
// notices (sal_notices.dart) all come here.
//
// The pill is the floating Sal pill's own surface (kute_bar_surface.dart:
// the primary button's dark fill with white words in light mode, the white
// pill with near-black words in dark mode; the hairline edge and the one
// shadow), centred under the status bar and no wider than its words. On
// the left the 3D Sal at the pill's size in the tone's clip (`happy` for a
// success, `sad` for a failure, the calm `blink` for pending and for
// information; the rig in the matching mood where his sheets cannot be
// read, as in every Sal), then one line of message in the pill's text
// style and an optional quieter second line, and on the right the result
// sheet's own small mark (KuteStatusMark, kute_success_overlay.dart: the
// check pops and draws, the "!", the clock; none for information).
//
// Motion: it comes down from above the status bar on the sheet spring
// (KuteMotion.sheetIn) and leaves on the settle (KuteMotion.sheetOut), the
// one motion every sheet has. One toast at a time: a new one sends the
// one on screen off that way as it arrives. Swiping it up sends it off, a
// tap runs its action (and sends it off), and left alone it goes by
// itself: a success after 2.5 s, information and pending after 3 s, a
// failure after 6 s. Reduce Motion draws every state at once. VoiceOver
// reads it as it lands (a live region: the message, then the second
// line), and its dismiss gesture sends it off.
//
// Haptics, once per toast as it lands, through the money moments' own
// (success_feedback.dart): the success beat for a success, the soft
// failure tap for a failure, nothing for pending or information.
//
// WHERE IT DRAWS (founder, 9 November 2026, on 2.2.0 (95): "Sal toast did
// not show"): always the app's ROOT overlay, reached through the root
// navigator's key (root_navigator.dart), never through the caller's
// context. The standing orders' shell sits beside the navigator in the
// app's Stack, with no overlay above it, and a slip's context is gone by
// the time its order fills: both found nothing and every order notice
// was dropped. The caller's context is only a fallback where there is no
// root key (a test's app).
//
// CLOSE AND ACT (founder, 9 November 2026: "Placing your prediction /
// cancel should be Sal. Also give it an X to close it"): a pending toast
// and one with an action carry an X at the trailing edge
// (44 pt to hit, read "Close") that only sends the toast off; an action
// ([SalToast.actionLabel], "Cancel") is a word in the pill before it. A
// [SalToast.sticky] toast never goes by itself (an order on its way, once
// its slip is left; an order waiting on the person: the price moved), and
// a toast shown with a [tag] already on screen changes in place rather
// than arriving again (the placing toast turning into how the order
// ended).

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/helpers/root_navigator.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/screens/shared/kute_dog_scenes.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart'
    show KuteConfirmation, KuteConfirmationTone, KuteStatusMark;
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/services/success_feedback.dart';
import 'package:kute/theme/kute_bar_surface.dart';
import 'package:kute/theme/kute_motion.dart';
import 'package:kute/theme/kute_overlay_surface.dart';

/// What a toast is saying: Sal's clip, the mark, the haptic and how long
/// it stays.
enum SalToastTone {
  /// Done (a prediction placed, a send out). Sal `happy`, the check, the
  /// success beat, 2.5 s.
  success,

  /// It did not happen. Sal `sad`, the "!", the failure tap, 6 s.
  failure,

  /// Accepted, not finished yet. Sal `blink`, the clock, no haptic, 3 s.
  pending,

  /// Information (a copy, a note). Sal `blink`, no mark, no haptic, 3 s.
  info,
}

/// The pill's height with one line (the bar pill's) and its corner (the
/// tall pill's half height, so one and two lines share the same curve).
const double kSalToastHeight = 50;
const double kSalToastRadius = 28;

/// The Sal toast: the pill itself (see the file header). [SalToast.show]
/// puts one on the root overlay; the pill can also be laid out directly
/// (a render test).
class SalToast extends StatefulWidget {
  const SalToast({
    super.key,
    required this.message,
    this.detail,
    this.tone = SalToastTone.info,
    this.onTap,
    this.duration,
    this.haptic = true,
    this.actionLabel,
    this.onAction,
    this.closable,
    this.sticky = false,
    this.onClose,
  });

  /// The one line: a short plain sentence ("Prediction placed").
  final String message;

  /// An optional quieter second line (the market, where the money is).
  final String? detail;

  final SalToastTone tone;

  /// Tapping the toast runs this and sends it off. Null: a tap only
  /// sends it off.
  final VoidCallback? onTap;

  /// How long it stays before going by itself; null: the tone's own
  /// ([durationFor]).
  final Duration? duration;

  /// False: no haptic, whatever the tone (a surface that already played
  /// its own for the same moment).
  final bool haptic;

  /// A word in the pill that does something without opening anything
  /// ("Cancel"): [onAction] runs and the toast goes. Null: none.
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Whether the X shows; null: the rule ([showsClose]), a pending toast
  /// or one with an action.
  final bool? closable;

  /// True: it never goes by itself (a running order's, gone when the
  /// order ends, when the person closes it or another toast arrives).
  final bool sticky;

  /// Runs when the person closes it with the X (only the toast goes).
  final VoidCallback? onClose;

  bool get hasAction => actionLabel != null && onAction != null;

  /// Whether the X shows (see [closable]).
  bool get showsClose =>
      closable ?? (tone == SalToastTone.pending || hasAction);

  static const Duration successDuration = Duration(milliseconds: 2500);
  static const Duration infoDuration = Duration(seconds: 3);
  static const Duration failureDuration = Duration(seconds: 6);

  /// How long a toast of [tone] stays when its caller does not say.
  static Duration durationFor(SalToastTone tone) => switch (tone) {
        SalToastTone.success => successDuration,
        SalToastTone.failure => failureDuration,
        SalToastTone.pending || SalToastTone.info => infoDuration,
      };

  /// Sal's clip for [tone] (the result sheet's rule).
  static String clipFor(SalToastTone tone) => switch (tone) {
        SalToastTone.success => 'happy',
        SalToastTone.failure => 'sad',
        SalToastTone.pending || SalToastTone.info => 'blink',
      };

  /// The rig's mood for [tone], where the sheets cannot be read.
  static KuteDogMood moodFor(SalToastTone tone) => switch (tone) {
        SalToastTone.success => KuteDogMood.happy,
        SalToastTone.failure => KuteDogMood.sad,
        SalToastTone.pending || SalToastTone.info => KuteDogMood.calm,
      };

  /// The mark for [tone]; null for information, which carries no result.
  static KuteConfirmationTone? markFor(SalToastTone tone) => switch (tone) {
        SalToastTone.success => KuteConfirmationTone.success,
        SalToastTone.failure => KuteConfirmationTone.failure,
        SalToastTone.pending => KuteConfirmationTone.pending,
        SalToastTone.info => null,
      };

  Duration get resolvedDuration => duration ?? durationFor(tone);

  /// Shows a toast over everything on the root overlay (see the file
  /// header), sending off the one on screen; [context] is only the
  /// fallback where the app has no root key, and may be gone. A toast
  /// with a [tag] already on screen changes in place instead.
  static void show(
    BuildContext? context, {
    required String message,
    String? detail,
    SalToastTone tone = SalToastTone.info,
    VoidCallback? onTap,
    Duration? duration,
    bool haptic = true,
    String? actionLabel,
    VoidCallback? onAction,
    bool? closable,
    bool sticky = false,
    VoidCallback? onClose,
    String? tag,
  }) =>
      _SalToastStage.show(
        context,
        SalToast(
          message: message,
          detail: detail,
          tone: tone,
          onTap: onTap,
          duration: duration,
          haptic: haptic,
          actionLabel: actionLabel,
          onAction: onAction,
          closable: closable,
          sticky: sticky,
          onClose: onClose,
        ),
        tag: tag,
      );

  /// Sends the toast on screen off (a screen leaving with its message).
  static void dismiss() => _SalToastStage.dismissAll();

  /// Whether a toast shown with [tag] is on screen and not leaving.
  static bool isShowing(String tag) => _SalToastStage.live(tag) != null;

  /// Sends the toast shown with [tag] off, if it is on screen.
  static void dismissTag(String tag) => _SalToastStage.live(tag)?.leave();

  /// The root overlay to draw on: the root navigator's (the app's key,
  /// root_navigator.dart), whatever [context] is; without the key (a
  /// test's app), the one above [context], or null when there is none (a
  /// context whose sheet has already closed, a layer beside the
  /// navigator, the root navigator's own context, whose overlay is a
  /// descendant `Overlay.of` does not find). `Overlay.of` threw on those,
  /// which was a fatal after cancelling a Cash App purchase from Activity.
  static OverlayState? overlayFor(BuildContext? context) {
    final root = kuteRootNavigatorKey.currentState;
    if (root != null && root.mounted) {
      final overlay = root.overlay;
      if (overlay != null && overlay.mounted) return overlay;
    }
    if (context == null || !context.mounted) return null;
    return Overlay.maybeOf(context, rootOverlay: true) ??
        Navigator.maybeOf(context, rootNavigator: true)?.overlay;
  }

  /// Test seams for the haptics. The real ones schedule timers, so widget
  /// tests install fakes here.
  @visibleForTesting
  static Future<void> Function()? debugSuccessFeedbackOverride;
  @visibleForTesting
  static Future<void> Function()? debugFailureFeedbackOverride;

  /// Tests: every toast gone at once, nothing in flight.
  @visibleForTesting
  static void debugReset() => _SalToastStage.reset();

  @override
  State<SalToast> createState() => _SalToastState();
}

class _SalToastState extends State<SalToast>
    with SingleTickerProviderStateMixin {
  /// The mark's pop and stroke (the result sheet's timeline).
  late final AnimationController _mark = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: KuteConfirmation.totalMs));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _mark.value = 1;
    } else {
      _mark.forward();
    }
  }

  @override
  void didUpdateWidget(SalToast old) {
    super.didUpdateWidget(old);
    // Changed in place to another result: its mark plays again.
    if (old.tone == widget.tone) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _mark.value = 1;
    } else {
      _mark.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _mark.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLight = Theme.of(context).brightness == Brightness.light;
    // The Sal pill's surface (kute_bar_surface.dart): dark with white
    // words in light mode, white with near-black words in dark mode.
    final fill =
        isLight ? KuteBarSurface.fill(context) : KuteBarSurface.whiteFill;
    final ink = isLight ? KuteBarSurface.ink : KuteBarSurface.inkOnWhite;
    final quiet =
        isLight ? KuteBarSurface.quietInk : KuteBarSurface.quietInkOnWhite;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final tone = widget.tone;
    final mark = SalToast.markFor(tone);
    final detail = widget.detail;
    final close = widget.showsClose;
    final controls = close || widget.hasAction;
    final scope = _SalToastControls.maybeOf(context);
    return Container(
      key: const ValueKey('sal-toast'),
      constraints: const BoxConstraints(minHeight: kSalToastHeight),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(kSalToastRadius),
        border: Border.all(
          color: isLight ? KuteBarSurface.edge : KuteBarSurface.whiteFill,
          width: isLight ? KuteBarSurface.edgeWidth : 0.5,
        ),
        boxShadow: [KuteBarSurface.shadow(visible: isLight)],
      ),
      padding: EdgeInsets.fromLTRB(
          8.w, 6.h, close ? 2.w : (mark == null ? 18.w : 14.w), 6.h),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: SalSprite(
              key: const ValueKey('sal-toast-sal'),
              clip: SalToast.clipFor(tone),
              size: KuteBarSurface.salSize,
              fallback: KuteDogConfirmation(
                key: const ValueKey('sal-toast-rig'),
                size: KuteBarSurface.salSize,
                mood: SalToast.moodFor(tone),
              ),
            ),
          ),
          SizedBox(width: 6.w),
          Flexible(
            // With buttons in the pill VoiceOver reads the words once, as
            // the toast's label, and reaches the buttons on their own.
            child: ExcludeSemantics(
              excluding: controls,
              child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.message,
                  key: const ValueKey('sal-toast-message'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ink,
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                    height: 1.25,
                  ),
                ),
                if (detail != null && detail.isNotEmpty)
                  Text(
                    detail,
                    key: const ValueKey('sal-toast-detail'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: quiet,
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.1,
                      height: 1.25,
                    ),
                  ),
              ],
            ),
            ),
          ),
          if (mark != null) ...[
            SizedBox(width: 10.w),
            ExcludeSemantics(
              child: KuteStatusMark(
                key: const ValueKey('sal-toast-mark'),
                animation: _mark,
                tone: mark,
                size: 22.sp,
                reduceMotion: reduce,
              ),
            ),
          ],
          if (widget.hasAction) ...[
            SizedBox(width: 4.w),
            Semantics(
              button: true,
              label: widget.actionLabel,
              excludeSemantics: true,
              child: GestureDetector(
                key: const ValueKey('sal-toast-action'),
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (scope != null) {
                    scope.act();
                  } else {
                    widget.onAction?.call();
                  }
                },
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                      minWidth: kSalToastHitSize, minHeight: kSalToastHitSize),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.w),
                    child: Center(
                      widthFactor: 1,
                      child: Text(
                        widget.actionLabel!,
                        maxLines: 1,
                        style: TextStyle(
                          color: ink,
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                          decoration: TextDecoration.underline,
                          decorationColor: quiet,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
          if (close)
            Semantics(
              button: true,
              label: _closeLabel(context),
              excludeSemantics: true,
              child: GestureDetector(
                key: const ValueKey('sal-toast-close'),
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (scope != null) {
                    scope.close();
                  } else {
                    widget.onClose?.call();
                  }
                },
                child: SizedBox.square(
                  dimension: kSalToastHitSize,
                  child: Icon(Icons.close_rounded, size: 18.sp, color: quiet),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// "Close", the app's word; Material's where the app's strings are not
  /// loaded (a render test).
  static String _closeLabel(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations)?.close ??
      MaterialLocalizations.of(context).closeButtonLabel;
}

/// The X's and the action's hit area: 44 pt, the platform's minimum.
const double kSalToastHitSize = 44;

/// What the pill's X and action do on the overlay: the flight's own
/// close and act, which also send the toast off.
class _SalToastControls extends InheritedWidget {
  const _SalToastControls(
      {required this.close, required this.act, required super.child});

  final VoidCallback close;
  final VoidCallback act;

  static _SalToastControls? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SalToastControls>();

  @override
  bool updateShouldNotify(_SalToastControls old) => false;
}

// ─────────────────────────────────────────────────────────────────────
// The stage: one toast at a time on the root overlay
// ─────────────────────────────────────────────────────────────────────

class _Flight {
  _Flight(this.key, this.tag);
  final GlobalKey<_SalToastFlightState> key;
  final String? tag;
  late final OverlayEntry entry;
  bool gone = false;
}

abstract final class _SalToastStage {
  static final List<_Flight> _flights = [];

  /// The flight on screen shown with [tag], not leaving; null: none.
  static _SalToastFlightState? live(String tag) {
    for (final flight in _flights.reversed) {
      if (flight.tag != tag || flight.gone) continue;
      final state = flight.key.currentState;
      if (state != null && !state.leaving) return state;
    }
    return null;
  }

  static void show(BuildContext? context, SalToast toast, {String? tag}) {
    // The same toast on screen: changed in place, no second arrival.
    if (tag != null) {
      final same = live(tag);
      if (same != null) {
        same.replace(toast);
        return;
      }
    }
    final overlay = SalToast.overlayFor(context);
    if (overlay == null) return;
    // The one on screen leaves as the new one arrives (the sheet's out
    // under the sheet's in: the switch).
    for (final flight in List.of(_flights)) {
      flight.key.currentState?.leave();
    }
    final flight = _Flight(GlobalKey<_SalToastFlightState>(), tag);
    flight.entry = OverlayEntry(
      builder: (_) => _SalToastFlight(
        key: flight.key,
        toast: toast,
        onGone: () => _remove(flight),
        onDisposed: () => _flights.remove(flight),
      ),
    );
    _flights.add(flight);
    overlay.insert(flight.entry);
  }

  static void _remove(_Flight flight) {
    _flights.remove(flight);
    if (flight.gone) return;
    flight.gone = true;
    flight.entry
      ..remove()
      ..dispose();
  }

  static void dismissAll() {
    for (final flight in List.of(_flights)) {
      flight.key.currentState?.leave();
    }
  }

  static void reset() {
    for (final flight in List.of(_flights)) {
      _remove(flight);
    }
  }
}

/// A toast's flight on the overlay: its place under the status bar, its
/// arrival and leave, the swipe, the tap, the timer, the haptic and what
/// VoiceOver reads.
class _SalToastFlight extends StatefulWidget {
  const _SalToastFlight({
    super.key,
    required this.toast,
    required this.onGone,
    required this.onDisposed,
  });

  final SalToast toast;

  /// The leave has played: take the entry off the overlay.
  final VoidCallback onGone;

  /// The flight left the tree some other way (its overlay went).
  final VoidCallback onDisposed;

  @override
  State<_SalToastFlight> createState() => _SalToastFlightState();
}

class _SalToastFlightState extends State<_SalToastFlight>
    with TickerProviderStateMixin {
  /// 0 above the screen, 1 at rest: the sheet spring in, the settle out.
  late final AnimationController _flight = AnimationController(
    vsync: this,
    duration: KuteMotion.sheetInDuration,
    reverseDuration: KuteMotion.sheetOutDuration,
  );
  late final Animation<double> _arrival = CurvedAnimation(
      parent: _flight,
      curve: KuteMotion.sheetIn,
      reverseCurve: KuteMotion.sheetOut);

  /// The fade never passes 1 (the spring does).
  late final Animation<double> _opacity = CurvedAnimation(
      parent: _flight,
      curve: KuteMotion.clamped(KuteMotion.sheetIn),
      reverseCurve: KuteMotion.sheetOut);

  /// The swipe's offset in logical pixels, up negative.
  late final AnimationController _drag = AnimationController.unbounded(vsync: this);

  /// The toast drawn now: the one shown, or the one it was changed into
  /// in place ([replace]).
  late SalToast _toast = widget.toast;

  Timer? _timer;
  bool _started = false;
  bool _leaving = false;

  bool get leaving => _leaving;
  bool _dragging = false;
  bool _reduce = false;

  /// How far the toast comes from when nothing is laid out yet: a pill
  /// and the room above it.
  static const double _travel = kSalToastHeight + 60;

  @override
  void initState() {
    super.initState();
    _flight.addStatusListener(_onFlight);
    if (_toast.haptic) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _feedback();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.disableAnimationsOf(context);
    if (_started) return;
    _started = true;
    if (_reduce) {
      // At rest at once; the timer runs from here.
      _flight.value = 1;
      _arm();
    } else {
      _flight.forward();
    }
  }

  void _onFlight(AnimationStatus status) {
    if (status == AnimationStatus.completed) _arm();
  }

  /// The haptic is the moment, not the motion: it plays as the toast is
  /// first drawn, Reduce Motion or not.
  void _feedback() {
    switch (_toast.tone) {
      case SalToastTone.success:
        unawaited((SalToast.debugSuccessFeedbackOverride ?? moneySuccessFeedback)());
      case SalToastTone.failure:
        unawaited((SalToast.debugFailureFeedbackOverride ?? moneyFailureFeedback)());
      case SalToastTone.pending || SalToastTone.info:
        break;
    }
  }

  /// Starts (or restarts) the clock to go by itself; a sticky toast has
  /// none.
  void _arm() {
    _timer?.cancel();
    _timer = null;
    if (_toast.sticky) return;
    _timer = Timer(_toast.resolvedDuration, () {
      if (mounted && !_dragging) leave();
    });
  }

  /// The toast changes in place into [next] (the same tag shown again):
  /// its words, tone and buttons, its haptic when the tone changed, its
  /// clock from now.
  void replace(SalToast next) {
    if (!mounted || _leaving) return;
    final toneChanged = next.tone != _toast.tone;
    setState(() => _toast = next);
    if (toneChanged && next.haptic) _feedback();
    if (_flight.isCompleted) _arm();
  }

  /// Sends the toast off: the settle out, then the entry goes. Once.
  Future<void> leave() async {
    if (_leaving) return;
    _leaving = true;
    _timer?.cancel();
    _timer = null;
    if (_reduce) {
      _flight.value = 0;
    } else {
      await _flight.reverse();
    }
    if (!mounted) return;
    widget.onGone();
  }

  void _tap() {
    final action = _toast.onTap;
    leave();
    action?.call();
  }

  /// The X: only the toast goes.
  void _close() {
    final closed = _toast.onClose;
    leave();
    closed?.call();
  }

  /// The action word: it runs and the toast goes; a sticky toast stays,
  /// for what the action led to to change it in place (a cancelled order).
  void _act() {
    final action = _toast.onAction;
    if (!_toast.sticky) leave();
    action?.call();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_leaving) return;
    _dragging = true;
    final dy = details.delta.dy;
    // Up follows the finger; down gives a little and no more.
    final give = dy > 0 && _drag.value >= 0 ? 0.25 : 1.0;
    _drag.value = math.min(_drag.value + dy * give, 16.0);
  }

  void _onDragEnd(DragEndDetails details) {
    if (_leaving) return;
    _dragging = false;
    if (_drag.value < -20 || details.velocity.pixelsPerSecond.dy < -500) {
      leave();
      return;
    }
    if (_reduce) {
      _drag.value = 0;
    } else {
      _drag.animateTo(0,
          duration: KuteMotion.settleDuration, curve: KuteMotion.settle);
    }
    if (_flight.isCompleted) _arm();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _flight.removeStatusListener(_onFlight);
    _flight.dispose();
    _drag.dispose();
    widget.onDisposed();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final toast = _toast;
    final detail = toast.detail;
    final label = detail == null || detail.isEmpty
        ? toast.message
        : '${toast.message}. $detail';
    final top = media.padding.top + 8.h;
    return Positioned(
      top: top,
      left: 12.w,
      right: 12.w,
      // On the root overlay: the theme's text (kute_overlay_surface.dart).
      child: KuteOverlaySurface(
        child: Align(
          alignment: Alignment.topCenter,
          child: AnimatedBuilder(
            animation: Listenable.merge([_arrival, _drag]),
            builder: (context, child) => Transform.translate(
              offset: Offset(
                  0, -(1 - _arrival.value) * (top + _travel) + _drag.value),
              child: child,
            ),
            child: FadeTransition(
              opacity: _opacity,
              child: Semantics(
                key: const ValueKey('sal-toast-semantics'),
                container: true,
                liveRegion: true,
                label: label,
                button: toast.onTap != null,
                onTap: _tap,
                onDismiss: leave,
                // The pill's X and action stay reachable on their own.
                excludeSemantics: !(toast.showsClose || toast.hasAction),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _tap,
                  onVerticalDragUpdate: _onDragUpdate,
                  onVerticalDragEnd: _onDragEnd,
                  child: _SalToastControls(
                    close: _close,
                    act: _act,
                    child: toast,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
