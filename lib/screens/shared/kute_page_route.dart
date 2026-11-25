// lib/screens/shared/kute_page_route.dart
//
// THE PUSHED PAGE'S MOTION, IN ONE PLACE (founder, 31 October 2026:
// "attention to the animations on everything"). Every page the app pushes
// (a market, a position, a detail, a list) arrives the same way, after
// Orchestra: in on the settle easing ([KuteMotion.settle], cubic-bezier
// 0.22, 1, 0.36, 1) with a 0.97 → 1 scale and a fade, back out on the
// sheets' close easing ([KuteMotion.sheetOut]); a plain line under Reduce
// Motion. The numbers live in lib/theme/kute_motion.dart.
//
//   * [KutePageRoute]: a page pushed over another (Navigator.push), the
//     fade + scale, and the platform's back swipe kept: on iOS and macOS a
//     drag from the leading edge ([KuteBackSwipe]) drives the route's own
//     controller like Cupertino's, pops past halfway or on a fling, else
//     settles back. app_router.dart's pages ([kutePageTransition]) wear
//     the same transition and the same swipe.
//   * [KuteSheetPageRoute]: the full-height detail sheets (a market, a
//     position, the prediction history) that rise from the bottom over a
//     dimmed page: the rise on the settle easing with the 0.97 → 1 scale,
//     down on the close easing. A sheet is no horizontal page, so no back
//     swipe; the page's own close and the system back work as before.
//
// Reduce Motion: a 150 ms fade, no scale, no slide ([KuteMotion.reduce]).

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:kute/theme/kute_motion.dart';

/// The transition every pushed page wears: fade and 0.97 → 1 scale in on
/// the settle easing, out on the close easing; a fade alone under Reduce
/// Motion. [child] is wrapped in [KuteBackSwipe] when [backSwipe].
Widget kutePageTransition(
  BuildContext context,
  Animation<double> animation,
  Widget child, {
  bool backSwipe = true,
}) {
  final reduce = KuteMotion.reduce(context);
  final curved = CurvedAnimation(
    parent: animation,
    curve: reduce ? Curves.linear : KuteMotion.settle,
    reverseCurve: reduce ? Curves.linear : KuteMotion.sheetOut,
  );
  final scale = Tween<double>(begin: reduce ? 1.0 : 0.97, end: 1.0)
      .animate(curved);
  final page = backSwipe ? KuteBackSwipe(child: child) : child;
  return FadeTransition(
    opacity: curved,
    child: ScaleTransition(
      scale: scale,
      alignment: Alignment.center,
      child: page,
    ),
  );
}

/// The duration of a push or a pop (the line under Reduce Motion).
Duration kutePageDuration(BuildContext? context) =>
    context != null && KuteMotion.reduce(context)
        ? KuteMotion.reducedDuration
        : KuteMotion.settleDuration;

/// A page pushed over another (see the file header).
class KutePageRoute<T> extends PageRoute<T> {
  KutePageRoute({
    required this.builder,
    super.settings,
    this.maintainState = true,
    super.fullscreenDialog,
  });

  final WidgetBuilder builder;

  @override
  final bool maintainState;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get opaque => true;

  @override
  Duration get transitionDuration =>
      kutePageDuration(navigator?.context);

  @override
  Duration get reverseTransitionDuration =>
      kutePageDuration(navigator?.context);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation) =>
      Semantics(
          scopesRoute: true, explicitChildNodes: true, child: builder(context));

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation, Widget child) =>
      kutePageTransition(context, animation, child,
          backSwipe: !fullscreenDialog);
}

/// A full-height detail sheet rising over a dimmed page (see the file
/// header). [barrierColor] dims the page under it; the sheet keeps its
/// own close.
class KuteSheetPageRoute<T> extends PageRoute<T> {
  KuteSheetPageRoute({
    required this.builder,
    super.settings,
    this.barrierColor = const Color(0x66000000),
    this.maintainState = true,
  }) : super(fullscreenDialog: true);

  final WidgetBuilder builder;

  @override
  final Color? barrierColor;

  @override
  final bool maintainState;

  @override
  String? get barrierLabel => null;

  @override
  bool get opaque => false;

  @override
  Duration get transitionDuration =>
      kutePageDuration(navigator?.context);

  @override
  Duration get reverseTransitionDuration =>
      kutePageDuration(navigator?.context);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation) =>
      Semantics(
          scopesRoute: true, explicitChildNodes: true, child: builder(context));

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    final reduce = KuteMotion.reduce(context);
    final curved = CurvedAnimation(
      parent: animation,
      curve: reduce ? Curves.linear : KuteMotion.settle,
      reverseCurve: reduce ? Curves.linear : KuteMotion.sheetOut,
    );
    if (reduce) return FadeTransition(opacity: curved, child: child);
    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
          .animate(curved),
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.97, end: 1.0).animate(curved),
        alignment: Alignment.topCenter,
        child: child,
      ),
    );
  }
}

/// The platform back swipe for a page whose transition is not Cupertino's
/// (Cupertino's own detector is private to its route). A drag that starts
/// within 20 px of the leading edge (plus the notch's inset) drives the
/// route's controller: the page fades and shrinks back under the finger;
/// released past halfway, or flung back, it pops, else it settles in
/// again. Only on iOS and macOS, only while the route can pop
/// ([PageRoute.popGestureEnabled]: not the first page, no modal
/// dialog, nothing in flight). Mirrors Cupertino's numbers.
class KuteBackSwipe extends StatefulWidget {
  const KuteBackSwipe({super.key, required this.child});

  final Widget child;

  /// How far from the leading edge a drag may start.
  static const double edgeWidth = 20;

  /// A fling past this (screen widths per second) decides on its own.
  static const double minFlingVelocity = 1.0;

  /// The settle after the finger lifts.
  static const Duration dropDuration = Duration(milliseconds: 350);

  @override
  State<KuteBackSwipe> createState() => _KuteBackSwipeState();
}

class _KuteBackSwipeState extends State<KuteBackSwipe> {
  late final HorizontalDragGestureRecognizer _recognizer =
      HorizontalDragGestureRecognizer(debugOwner: this)
        ..onStart = _onStart
        ..onUpdate = _onUpdate
        ..onEnd = _onEnd
        ..onCancel = _onCancel;

  PageRoute<dynamic>? _route;
  NavigatorState? _navigator;
  bool _dragging = false;

  @override
  void dispose() {
    _recognizer.dispose();
    if (_dragging) {
      final navigator = _navigator;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (navigator?.mounted ?? false) navigator!.didStopUserGesture();
      });
    }
    super.dispose();
  }

  bool get _platformSwipes {
    final platform = Theme.of(context).platform;
    return platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
  }

  double _logical(double value) =>
      Directionality.of(context) == TextDirection.rtl ? -value : value;

  void _onPointerDown(PointerDownEvent event) {
    final route = ModalRoute.of(context);
    if (route is! PageRoute || !_platformSwipes || !route.popGestureEnabled) {
      return;
    }
    _route = route;
    _recognizer.addPointer(event);
  }

  void _onStart(DragStartDetails details) {
    final route = _route;
    final navigator = route?.navigator;
    if (route == null || navigator == null) return;
    _navigator = navigator;
    _dragging = true;
    navigator.didStartUserGesture();
  }

  void _onUpdate(DragUpdateDetails details) {
    if (!_dragging) return;
    final width = context.size?.width ?? 1;
    // ignore: invalid_use_of_protected_member
    final controller = _route?.controller;
    if (controller == null) return;
    controller.value -= _logical(details.primaryDelta! / width);
  }

  void _onEnd(DragEndDetails details) {
    if (!_dragging) return;
    final width = context.size?.width ?? 1;
    _finish(_logical(details.velocity.pixelsPerSecond.dx / width));
  }

  void _onCancel() {
    if (_dragging) _finish(0);
  }

  void _finish(double velocity) {
    _dragging = false;
    final route = _route;
    final navigator = _navigator;
    _route = null;
    _navigator = null;
    if (route == null || navigator == null) return;
    // ignore: invalid_use_of_protected_member
    final controller = route.controller;
    if (controller == null) return;
    final bool stay;
    if (!route.isCurrent) {
      stay = route.isActive;
    } else if (velocity.abs() >= KuteBackSwipe.minFlingVelocity) {
      stay = velocity <= 0;
    } else {
      stay = controller.value > 0.5;
    }
    if (stay) {
      controller.animateTo(1.0,
          duration: KuteBackSwipe.dropDuration, curve: KuteMotion.settle);
    } else {
      if (route.isCurrent) navigator.pop();
      if (controller.isAnimating) {
        controller.animateBack(0.0,
            duration: KuteBackSwipe.dropDuration, curve: KuteMotion.sheetOut);
      }
    }
    if (controller.isAnimating) {
      late AnimationStatusListener done;
      done = (AnimationStatus status) {
        if (navigator.mounted) navigator.didStopUserGesture();
        controller.removeStatusListener(done);
      };
      controller.addStatusListener(done);
    } else if (navigator.mounted) {
      navigator.didStopUserGesture();
    }
  }

  @override
  Widget build(BuildContext context) {
    final inset = Directionality.of(context) == TextDirection.rtl
        ? MediaQuery.paddingOf(context).right
        : MediaQuery.paddingOf(context).left;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        PositionedDirectional(
          start: 0,
          width: KuteBackSwipe.edgeWidth + inset,
          top: 0,
          bottom: 0,
          child: Listener(
            onPointerDown: _onPointerDown,
            behavior: HitTestBehavior.translucent,
          ),
        ),
      ],
    );
  }
}
