// lib/screens/shared/kute_dialog.dart
//
// SHEETS BECOME PANELS ON A LAPTOP (founder, 25 November 2026, of round
// one's sheets in the middle of the screen: "these cards in the middle
// borrow from touch, but how can we make it better?"; then, the Financial
// hub beside the search panel: "this on desktop instead of a card, maybe
// show like this search, much better"; wide_design_2.md, B and C). On
// EXPANDED only; a phone and MEDIUM keep their bottom sheets as they were.
//
//   * A sheet is THE SEARCH PANEL'S SHAPE ([KuteDialogRoute],
//     [showKuteDialog]; the geometry, surface, dim and motion are the
//     search panel's own, kute_wide_frames.dart THE PANEL): top-anchored
//     at a tenth of the window's height, centred, `KuteLayout.sheetMaxWidth`
//     wide, rounded all round, no drag handle (AppDecorations.dragHandle
//     draws nothing inside one), its height hugging its content and
//     growing downward on the sheet spring, at most the window less its
//     top and 48 under it, the content scrolling inside past that. Escape,
//     a click outside and the close X close it (the content's own X when
//     it draws one, [KuteDialogCloseMark]; else the panel's, at its top
//     right). A sheet opened from a panel stacks as a second panel a
//     little lower; Escape closes the top one only (the key goes to the
//     focused route, and a route's focus scope keeps the focus inside).
//   * ITS PRIMARY BUTTON IS INSIDE IT. On a phone a sheet's Continue /
//     Send / Done is the floating bar (kute_bar_context.dart,
//     KuteBarContext.primary); round one had that bar hanging detached
//     under the card. Here the panel's foot ([_KuteDialogFoot]) reads the
//     bar contexts bound to ITS route and draws the same
//     [KuteBarPrimaryButton] (and the round Sal button beside it, or a
//     trade row) pinned at its bottom, the way the in-place slips do
//     (slip_chrome.dart, PolySlipInPlace). The floating bar stays away
//     while any panel is up ([kuteDialogsOpen]); the room a surface kept
//     for the bar over its last rows is dropped inside one
//     (KuteBarContextScope, kuteSheetBarClearance).
//   * The money flows (Swap, Send, Receive, Purchase, Add money) open as
//     the same panel at a page's height ([KuteDialogRoute.fill]) over the
//     dimmed page they came from (deposit_sheet.dart,
//     money_movement_sheet.dart, send_sheet.dart, receive_sheet.dart).
//
// The lock overlay, the privacy cover and the toasts sit over the root
// navigator (app_widget.dart), so they stay above every panel.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/platform/kute_layout.dart';
import 'package:kute/platform/kute_wide_frames.dart';
import 'package:kute/screens/home/components/kute_bar_trade_row.dart';
import 'package:kute/screens/home/components/kute_shell_bar.dart'
    show KuteBarPrimaryButton, openKuteBarSheet;
import 'package:kute/screens/shared/kute_back_button.dart' show KuteCloseButton;
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/theme/kute_motion.dart';
import 'package:kute/theme/kute_overlay_surface.dart';

/// The tallest a page-like flow's dialog gets ([KuteDialogRoute.fill]):
/// the phone design's height less its status bar and home indicator.
const double kuteDialogFillHeight = 860;

/// The air under a dialog's in-place primary button (founder, round two:
/// "the button in the end give it more space").
const double kuteDialogFootBottom = 24;

/// Opens [builder] as a panel on the root navigator (see the file header).
/// For EXPANDED; showKuteModalSheet calls it there.
Future<T?> showKuteDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? color,
  bool dismissible = true,
  bool fill = false,
  RouteSettings? settings,
}) {
  return Navigator.of(context, rootNavigator: true).push<T>(KuteDialogRoute<T>(
    builder: builder,
    color: color,
    dismissible: dismissible,
    fill: fill,
    settings: settings,
  ));
}

/// The route behind [showKuteDialog] (see the file header). Counted by the
/// bar as a sheet over the tabs ([KuteBarSheetRoute]).
class KuteDialogRoute<T> extends PopupRoute<T> implements KuteBarSheetRoute {
  KuteDialogRoute({
    required this.builder,
    this.color,
    this.dismissible = true,
    this.fill = false,
    super.settings,
  });

  final WidgetBuilder builder;

  /// The card's surface; the sheet surface when null.
  final Color? color;

  /// Escape, a click outside and the X close it.
  final bool dismissible;

  /// A page-like flow (a keypad, a pinned foot): the card takes a page's
  /// height ([kuteDialogFillHeight], at most the window's room) rather
  /// than hugging its content.
  final bool fill;

  static bool get _reduceMotion => WidgetsBinding
      .instance.platformDispatcher.accessibilityFeatures.disableAnimations;

  @override
  bool get barrierDismissible => dismissible;

  @override
  Color? get barrierColor => kutePanelBarrier;

  @override
  String? get barrierLabel => 'Dismiss';

  @override
  Duration get transitionDuration =>
      _reduceMotion ? KuteMotion.reducedDuration : KuteMotion.settleDuration;

  @override
  Duration get reverseTransitionDuration =>
      _reduceMotion ? KuteMotion.reducedDuration : KuteMotion.sheetOutDuration;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation) =>
      KuteDialogCard(
        route: this,
        color: color,
        fill: fill,
        onDismiss: dismissible ? () => navigator?.maybePop() : null,
        child: Builder(builder: builder),
      );

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    final reduce = KuteMotion.reduce(context);
    final curved = CurvedAnimation(
      parent: animation,
      curve: reduce ? Curves.linear : KuteMotion.settle,
      reverseCurve: reduce ? Curves.linear : KuteMotion.sheetOut,
    );
    // The search panel's own way in and out.
    if (reduce) return FadeTransition(opacity: curved, child: child);
    return kutePanelTransition(curved, child);
  }
}

/// The panel (see the file header): top-anchored and centred in the
/// window as the search panel is, a little lower for each panel already
/// under it, on the panel's surface, the content in a [KuteDialogScope]
/// with the panel's room as its MediaQuery, the bar's primary in its foot,
/// and the X when the content draws none. Its height eases on the sheet
/// spring as the content changes, so it only grows and shrinks downward.
/// [onDismiss] null: nothing closes it but the content itself. Used by
/// [KuteDialogRoute] and the send sheet's route (send_sheet.dart).
class KuteDialogCard extends StatefulWidget {
  const KuteDialogCard({
    super.key,
    required this.route,
    required this.child,
    this.color,
    this.fill = false,
    this.onDismiss,
  });

  final Route<dynamic> route;
  final Widget child;
  final Color? color;
  final bool fill;
  final VoidCallback? onDismiss;

  /// How much lower a panel over a panel stands.
  static const double stackStep = 20;

  @override
  State<KuteDialogCard> createState() => _KuteDialogCardState();
}

class _KuteDialogCardState extends State<KuteDialogCard> {
  final ValueNotifier<int> _closeMarks = ValueNotifier<int>(0);

  /// How many panels were up under this one when it opened.
  late final int _depth = kuteDialogsOpen.value;

  /// The content has had a frame to show its own X.
  bool _settled = false;

  @override
  void initState() {
    super.initState();
    // Read before this panel counts itself.
    _depth;
    // After the frame: the floating bar listens and rebuilds.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      kuteDialogsOpen.value = kuteDialogsOpen.value + 1;
      if (mounted) setState(() => _settled = true);
    });
  }

  @override
  void dispose() {
    // After the frame: the floating bar listens and rebuilds.
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => kuteDialogsOpen.value = math.max(0, kuteDialogsOpen.value - 1));
    // [_closeMarks] is not disposed: the content's close marks let go of
    // it after this frame (KuteDialogCloseMark), and it holds nothing.
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    // The top panel only: the key reaches the focused route's tree.
    if (!widget.route.isCurrent) return KeyEventResult.ignored;
    final dismiss = widget.onDismiss;
    if (dismiss == null) return KeyEventResult.ignored;
    dismiss();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final window = mq.size;
    final keyboard = mq.viewInsets.bottom;
    final width = math.min(window.width - 32, KuteLayout.sheetMaxWidth);
    // The search panel's place (kute_wide_frames.dart, THE PANEL), a step
    // lower for each panel under this one.
    final top =
        kutePanelTop(window) + math.min(_depth, 3) * KuteDialogCard.stackStep;
    final tallest = kutePanelTallest(window, keyboard: keyboard, top: top);
    final height = widget.fill ? math.min(tallest, kuteDialogFillHeight) : null;

    final content = MediaQuery(
      // The panel is the content's screen: its width, its room, no system
      // insets (the panel itself stands clear of them).
      data: mq.copyWith(
        size: Size(width, tallest),
        padding: EdgeInsets.zero,
        viewPadding: EdgeInsets.zero,
        viewInsets: EdgeInsets.zero,
      ),
      child: KuteDialogScope(
        route: widget.route,
        closeMarks: _closeMarks,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              fit: widget.fill ? FlexFit.tight : FlexFit.loose,
              child: widget.child,
            ),
            _KuteDialogFoot(route: widget.route),
          ],
        ),
      ),
    );

    final decoration = kutePanelDecoration(context);
    final surface = Container(
      key: const ValueKey('kute-dialog-card'),
      width: width,
      height: height,
      constraints: BoxConstraints(maxHeight: tallest),
      clipBehavior: Clip.antiAlias,
      decoration: widget.color == null
          ? decoration
          : decoration.copyWith(color: widget.color),
      child: Stack(
        children: [
          content,
          // The panel's own X, only when the content shows none: where
          // the search panel draws its close.
          if (widget.onDismiss != null)
            Positioned(
              top: 14,
              right: 14,
              child: ValueListenableBuilder<int>(
                valueListenable: _closeMarks,
                builder: (context, marks, _) => _settled && marks <= 0
                    ? KuteCloseButton(
                        key: const ValueKey('kute-dialog-close'),
                        onPressed: widget.onDismiss)
                    : const SizedBox.shrink(),
              ),
            ),
        ],
      ),
    );
    // Under Reduce Motion it changes height at once (an AnimatedSize of no
    // duration re-dirties itself in its own layout).
    final panel = KuteMotion.reduce(context)
        ? surface
        : AnimatedSize(
            duration: KuteMotion.sheetInDuration,
            curve: KuteMotion.sheetIn,
            alignment: Alignment.topCenter,
            child: surface,
          );

    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      // Above the navigator's Material: the theme's text, never the error
      // style.
      child: KuteOverlaySurface(
        child: Padding(
          padding: EdgeInsets.only(top: top),
          child: Align(alignment: Alignment.topCenter, child: panel),
        ),
      ),
    );
  }
}

/// The dialog's foot: the bar's primary button (and the round Sal button
/// beside it) or a trade row, from the bar contexts bound to [route], as
/// the floating bar would draw them (kute_shell_bar.dart). Nothing when
/// the content declares none.
class _KuteDialogFoot extends ConsumerWidget {
  const _KuteDialogFoot({required this.route});

  final Route<dynamic> route;

  List<KuteBarContext> _mine(List<KuteBarContext> stack) => [
        for (final c in stack)
          if (c.route == route) c
      ];

  void _share(KuteBarShare share, BuildContext shareContext) {
    final direct = share.brag ??
        share.send ??
        share.open ??
        share.barContext?.directAction;
    if (direct != null) {
      HapticFeedback.lightImpact();
      direct();
      return;
    }
    final ctx = share.barContext;
    if (ctx != null) unawaited(openKuteBarSheet(ctx, source: shareContext));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stack = ref.watch(kuteBarContextProvider);
    final top = kuteBarTop(_mine(stack));
    Widget foot = const SizedBox(width: double.infinity);
    if (top != null && !top.hidden && top.isPrimary) {
      foot = Padding(
        key: const ValueKey('kute-dialog-primary'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, kuteDialogFootBottom),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: KuteBarPrimaryButton(
                barContext: top,
                onAsk: () => unawaited(openKuteBarSheet(
                    kuteBarAskContext(ref.read(kuteBarContextProvider), top))),
                // The live context, as the floating bar taps it: a page
                // that just enabled its action may not have redrawn yet.
                onPrimaryTap: () {
                  final live =
                      kuteBarTop(_mine(ref.read(kuteBarContextProvider)));
                  if (live == null || !live.isPrimary || !live.actionable) {
                    return;
                  }
                  HapticFeedback.lightImpact();
                  live.onPrimary!();
                },
              ),
            ),
            KuteBarShareSlot(
              share: top.share,
              onTap: (shareContext) {
                final share = top.share;
                if (share != null) _share(share, shareContext);
              },
            ),
          ],
        ),
      );
    } else if (top != null && !top.hidden && top.isTrade) {
      foot = Padding(
        key: const ValueKey('kute-dialog-trade'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, kuteDialogFootBottom),
        child: KuteBarTradeRow(
          barContext: top,
          onShare: (shareContext) {
            final share = top.share;
            if (share != null) _share(share, shareContext);
          },
        ),
      );
    }
    if (KuteMotion.reduce(context)) return foot;
    return AnimatedSize(
      duration: KuteMotion.settleDuration,
      curve: KuteMotion.settle,
      alignment: Alignment.topCenter,
      child: foot,
    );
  }
}

/// A money flow's route (Swap, Purchase, Add money; wide_design_2.md, C):
/// on EXPANDED a dialog card at a page's height ([KuteDialogRoute.fill])
/// over the dimmed page it was opened from, its keypad at its phone size
/// and its primary inside the card; elsewhere the full-screen page it has
/// always been, in a centred column from MEDIUM up ([KuteFormColumn]).
/// The flow closes itself (its X, its result); a click outside or Escape
/// closes the dialog through the flow's own PopScope.
Route<T> kuteMoneyFlowRoute<T>(BuildContext context,
    {required WidgetBuilder builder}) {
  if (kuteWindowIsExpanded(context)) {
    return KuteDialogRoute<T>(
      builder: builder,
      fill: true,
      color: context.colors.background,
    );
  }
  return MaterialPageRoute<T>(
    fullscreenDialog: true,
    builder: (ctx) => KuteFormColumn(child: builder(ctx)),
  );
}
