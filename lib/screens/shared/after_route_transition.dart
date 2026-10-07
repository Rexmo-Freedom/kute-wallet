// lib/screens/shared/after_route_transition.dart
//
// Work that must wait for the enclosing route's open transition: a sheet
// that focuses its field (search, Ask Sal) and a header button that
// widens once its screen is on. Raising the keyboard while the sheet is
// still sliding in makes iOS animate the keyboard against a moving
// surface (its "Unable to simultaneously satisfy constraints" logs), so
// focus is only ever requested once the slide has finished and the
// frame that follows it has been laid out.

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Runs [action] once the route around [context] has finished its open
/// transition: at once when there is no route or it is already settled
/// (call from a post-frame callback, so the tree is laid out), else at
/// the end of the frame the transition completes on, since the completed
/// status lands at that frame's start, before the settled sheet is laid
/// out. Returns a cancel: call it from `dispose` so the action never runs
/// on a widget that has gone.
VoidCallback afterRouteTransition(BuildContext context, VoidCallback action) {
  final animation = ModalRoute.of(context)?.animation;
  if (animation == null || animation.status == AnimationStatus.completed) {
    action();
    return () {};
  }
  var cancelled = false;
  void listener(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    animation.removeStatusListener(listener);
    SchedulerBinding.instance.endOfFrame.then((_) {
      if (!cancelled) action();
    });
  }

  animation.addStatusListener(listener);
  return () {
    cancelled = true;
    animation.removeStatusListener(listener);
  };
}

/// Focuses [node] once the route around [context] has finished opening
/// (never mid-slide), if the node is still attached by then. Returns the
/// cancel, for `dispose`.
VoidCallback requestFocusAfterTransition(
        BuildContext context, FocusNode node) =>
    afterRouteTransition(context, () {
      if (node.context?.mounted ?? false) node.requestFocus();
    });
