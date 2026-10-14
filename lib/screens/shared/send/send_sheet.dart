// lib/screens/shared/send/send_sheet.dart
//
// SEND OPENS AS A SHEET (founder decision, October 2026). Both send flows
// (bitcoin: `confirm_send.dart`, dollars: `usd/usd_send_screen.dart`)
// open over the screen they were started from as one bottom sheet:
//
//  * MEDIUM on the first step, the recipient (paste, scan, recents), so
//    the screen behind stays in view while the person picks who to pay.
//  * FULL once a recipient is in, once the flow moves on to the amount,
//    when the keyboard opens, or when the person drags it up. A send
//    that arrives with its recipient (a deep link, a scan from Home)
//    opens full. Growing is one way: the sheet never shrinks back under
//    the person mid-send.
//  * DISMISSIBLE only while the flow says so: a drag down or a tap on
//    the scrim closes it on the first step, and does nothing once the
//    send is past it or is signing, approving or broadcasting (a drag
//    rubber-bands and snaps back). The flow's own PopScope still owns
//    system back, so Android back steps back inside the sheet.
//
// The flow tells the sheet what it needs through [SendSheetScope.sync];
// the sheet owns only presentation (height, drag, scrim). Nothing here
// touches a money path, an approval or a check: those stay in the flows.
//
// Chrome is the app's own sheet chrome (AppDecorations.bottomSheet's
// radius and the shared drag handle), filled with the page colour the
// send steps are drawn on so their cards keep their contrast.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:kute/theme/app_theme.dart';

/// Share of the screen the sheet takes on its first step.
const double kSendSheetMediumFraction = 0.64;

/// What the sheet shows and allows, as the flow inside reports it.
class SendSheetController extends ChangeNotifier {
  SendSheetController();

  bool _expanded = false;
  bool _dismissible = true;

  /// Full height. One way for the life of the sheet: once full (the flow
  /// asked, the keyboard opened, or the person dragged it up) it never
  /// collapses under the person, even when the flow steps back.
  bool get expanded => _expanded;

  /// Whether a drag down or a scrim tap may close the sheet.
  bool get dismissible => _dismissible;

  /// Whether [update] with these values would change anything.
  bool differs({required bool expanded, required bool dismissible}) =>
      (expanded && !_expanded) || dismissible != _dismissible;

  /// The flow's report. Called after a frame (see [SendSheetScope.sync]).
  void update({required bool expanded, required bool dismissible}) {
    if (!differs(expanded: expanded, dismissible: dismissible)) return;
    _expanded = _expanded || expanded;
    _dismissible = dismissible;
    notifyListeners();
  }

  /// The keyboard opened, or the person dragged the sheet up.
  void expand() {
    if (_expanded) return;
    _expanded = true;
    notifyListeners();
  }
}

/// Puts a [SendSheetController] above a send flow.
class SendSheetScope extends InheritedNotifier<SendSheetController> {
  const SendSheetScope({
    super.key,
    required SendSheetController controller,
    required super.child,
  }) : super(notifier: controller);

  /// The sheet the flow sits in, or null when it is a plain screen. Does
  /// not make the caller depend on the sheet's state, so it is safe from
  /// initState and never rebuilds the flow when the sheet changes.
  static SendSheetController? maybeOf(BuildContext context) {
    final scope = context
        .getElementForInheritedWidgetOfExactType<SendSheetScope>()
        ?.widget;
    return scope is SendSheetScope ? scope.notifier : null;
  }

  /// Whether [context] is inside a send sheet.
  static bool presented(BuildContext context) => maybeOf(context) != null;

  /// A flow's report of what it needs, from its build. Applied after the
  /// frame so the sheet is never marked dirty while the flow builds.
  static void sync(BuildContext context,
      {required bool expanded, required bool dismissible}) {
    final controller = maybeOf(context);
    if (controller == null) return;
    if (!controller.differs(expanded: expanded, dismissible: dismissible)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => controller.update(expanded: expanded, dismissible: dismissible),
    );
  }
}

/// A send flow as a sheet on the root navigator. [SendSheetPage] is the
/// same thing for a go_router route.
Future<T?> showSendSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) =>
    Navigator.of(context, rootNavigator: true)
        .push<T>(SendSheetRoute<T>(builder: builder));

/// The send sheet as a declarative page, so a named route (the bitcoin
/// send's `pay_send`, reached from the dock, the scanner and deep links)
/// presents as the sheet wherever it is pushed from.
class SendSheetPage<T> extends Page<T> {
  const SendSheetPage(
      {super.key, super.name, super.arguments, required this.child});

  final Widget child;

  @override
  Route<T> createRoute(BuildContext context) =>
      SendSheetRoute<T>(builder: (_) => child, settings: this);
}

/// The route behind [showSendSheet] and [SendSheetPage]: a scrim and the
/// sheet, sliding up from the bottom.
///
/// A see-through PAGE route rather than a popup, so the route observers
/// keep seeing the send as the screen it was (PostHog's `$screen` and
/// the breadcrumb ring only record page routes, and `pay_send` is
/// named), while the screen it opened from stays visible behind it.
class SendSheetRoute<T> extends PageRoute<T> {
  SendSheetRoute({required this.builder, super.settings});

  final WidgetBuilder builder;
  final SendSheetController sheetController = SendSheetController();

  static bool get _reduceMotion => WidgetsBinding
      .instance.platformDispatcher.accessibilityFeatures.disableAnimations;

  @override
  bool get opaque => false;

  @override
  bool get maintainState => true;

  @override
  Color? get barrierColor => Colors.black54;

  /// Scrim taps are the sheet's own decision ([SendSheetController
  /// .dismissible]), never the barrier's.
  @override
  bool get barrierDismissible => false;

  @override
  String? get barrierLabel => null;

  @override
  Duration get transitionDuration =>
      _reduceMotion ? Duration.zero : const Duration(milliseconds: 320);

  @override
  Duration get reverseTransitionDuration =>
      _reduceMotion ? Duration.zero : const Duration(milliseconds: 260);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation) =>
      SendSheetScope(
        controller: sheetController,
        child: _SendSheetFrame(
          route: this,
          child: Builder(builder: builder),
        ),
      );

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
          .animate(CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      )),
      child: child,
    );
  }

  @override
  void dispose() {
    sheetController.dispose();
    super.dispose();
  }
}

class _SendSheetFrame extends StatefulWidget {
  const _SendSheetFrame({required this.route, required this.child});

  final SendSheetRoute<dynamic> route;
  final Widget child;

  @override
  State<_SendSheetFrame> createState() => _SendSheetFrameState();
}

class _SendSheetFrameState extends State<_SendSheetFrame>
    with SingleTickerProviderStateMixin {
  /// How far the sheet is dragged down, in logical pixels.
  double _drag = 0;
  double _dragUp = 0;
  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..addListener(
      () => setState(() => _drag = _settleFrom * (1 - _settle.value)));
  double _settleFrom = 0;

  SendSheetController get _controller => widget.route.sheetController;

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  /// Rubber band for a sheet that may not close: it gives a little and
  /// comes back.
  static const double _lockedTravel = 28;

  void _onDragUpdate(DragUpdateDetails d) {
    _settle.stop();
    final dy = d.delta.dy;
    if (dy < 0 && _drag <= 0) {
      _dragUp -= dy;
      return;
    }
    setState(() {
      if (_controller.dismissible) {
        _drag = (_drag + dy).clamp(0.0, double.infinity);
      } else {
        // Resistance grows with travel; capped so it reads as "held".
        final next = _drag + dy * (1 - _drag / _lockedTravel).clamp(0.05, 1);
        _drag = next.clamp(0.0, _lockedTravel);
      }
    });
  }

  void _onDragEnd(DragEndDetails d, double sheetHeight) {
    final v = d.primaryVelocity ?? 0;
    final up = _dragUp;
    _dragUp = 0;
    if (_drag <= 0 && (up > 40 || v < -500)) {
      _controller.expand();
      return;
    }
    if (_controller.dismissible &&
        (_drag > sheetHeight * 0.25 || v > 700)) {
      _dismiss();
      return;
    }
    _snapBack();
  }

  void _snapBack() {
    if (_drag == 0) return;
    _settleFrom = _drag;
    if (_reduceMotion(context)) {
      setState(() => _drag = 0);
      return;
    }
    _settle.forward(from: 0);
  }

  /// Closes through the flow's own PopScope, so a flow that has just
  /// become busy still refuses.
  Future<void> _dismiss() async {
    final popped = await Navigator.of(context).maybePop();
    if (!popped && mounted) _snapBack();
  }

  void _onScrimTap() {
    // With the keyboard up, a tap outside only puts it away.
    if (MediaQuery.viewInsetsOf(context).bottom > 0) {
      FocusManager.instance.primaryFocus?.unfocus();
      return;
    }
    if (_controller.dismissible) _dismiss();
  }

  static bool _reduceMotion(BuildContext context) =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final keyboard = mq.viewInsets.bottom;
    // Rebuild on the controller's reports.
    context.dependOnInheritedWidgetOfExactType<SendSheetScope>();
    final controller = _controller;
    if (keyboard > 0 && !controller.expanded) {
      // The keyboard would cover a half-height sheet: it stays full.
      WidgetsBinding.instance
          .addPostFrameCallback((_) => controller.expand());
    }
    final screen = mq.size.height;
    final full = (screen - mq.viewPadding.top - 8).clamp(0.0, screen);
    final medium = (screen * kSendSheetMediumFraction).clamp(0.0, full);
    final target = controller.expanded ? full : medium;
    // Height changes are instant while the sheet is still sliding in (a
    // send that opens expanded opens expanded) and under Reduce Motion.
    final entering =
        widget.route.animation?.status != AnimationStatus.completed;
    final duration = _reduceMotion(context) || entering
        ? Duration.zero
        : const Duration(milliseconds: 320);
    final c = context.colors;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            key: const ValueKey('send-sheet-scrim'),
            behavior: HitTestBehavior.opaque,
            onTap: _onScrimTap,
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Transform.translate(
            offset: Offset(0, _drag),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(end: target),
              duration: duration,
              curve: Curves.easeOutCubic,
              // The surface runs down behind the keyboard; the flow's
              // frame pads its content by the inset, so its action sits
              // above the keys. The sheet grows at least as fast as the
              // keyboard rises (the platform animates the inset on the
              // keyboard's own curve), so a half-height sheet is never
              // squeezed by it and nothing jumps.
              builder: (context, base, child) {
                final height = base < medium + keyboard
                    ? (medium + keyboard).clamp(0.0, full)
                    : base;
                return GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onVerticalDragUpdate: _onDragUpdate,
                  onVerticalDragEnd: (d) => _onDragEnd(d, height),
                  child: Container(
                    key: const ValueKey('send-sheet'),
                    height: height,
                    width: double.infinity,
                    clipBehavior: Clip.antiAlias,
                    decoration: AppDecorations.bottomSheet(context)
                        .copyWith(color: c.background),
                    child: child,
                  ),
                );
              },
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.only(top: 10.h, bottom: 2.h),
                    child: AppDecorations.dragHandle(context),
                  ),
                  Expanded(
                    // The sheet sits below the status bar: the flow's
                    // app bar needs no top inset. Bottom insets (home
                    // indicator, keyboard) pass through, so the flow's
                    // frame keeps its action above the keyboard.
                    child: MediaQuery.removePadding(
                      context: context,
                      removeTop: true,
                      child: widget.child,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
