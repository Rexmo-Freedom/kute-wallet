// lib/platform/kute_wide_frames.dart
//
// THE SHELL'S WIDE FRAMES (kute_layout.dart). On a phone every one of
// these is its child, untouched. From MEDIUM up:
//
//   * [KuteFormColumn]: a pushed form or flow (onboarding, PIN, seed
//     words, settings, send, receive, add wallet, import, the lock
//     screen) is a [KuteLayout.columnMaxWidth] column centred on the
//     app's background. Its pinned buttons and keypads stay inside it.
//   * [KuteSheetWidth] / [kuteSheetConstraints]: a sheet is a form of at
//     most [KuteLayout.sheetMaxWidth], centred and anchored at the bottom
//     as on a phone (the same handle, radius and colours; the keyboard
//     and the drag-to-dismiss work as they do there).
//   * [KutePhoneColumn]: a phone-width box ([KuteLayout.paneWidth]) for
//     a widget that is a phone column on a wide window (the top nav, the
//     floating bar, a toast).
//
// Inside a column or a sheet the MediaQuery's width is the column's, so
// a widget that sizes itself from the screen (and [KuteLayout.of])
// sees the phone column it is drawn in, never the window around it.

import 'dart:math' as math;

import 'package:flutter/rendering.dart' show BoxParentData;
import 'package:flutter/widgets.dart';
import 'package:kute/platform/kute_layout.dart';
import 'package:kute/theme/app_theme.dart';

/// [child] with the MediaQuery's width set to [width] (the height and
/// everything else as they are).
Widget kuteNarrowMedia(BuildContext context,
    {required double width, required Widget child}) {
  final mq = MediaQuery.of(context);
  if (mq.size.width <= width) return child;
  return MediaQuery(
    data: mq.copyWith(size: Size(width, mq.size.height)),
    child: child,
  );
}

/// A pushed form or flow, centred in a [KuteLayout.columnMaxWidth]
/// column on the app's background from MEDIUM up (see the file header).
/// Nested, it is a no-op: inside one the width is a phone's.
class KuteFormColumn extends StatelessWidget {
  const KuteFormColumn(
      {super.key, required this.child, this.background = true});

  final Widget child;

  /// Paint the app's background at the column's sides. False for a page
  /// that rises over a dimmed page (a detail sheet, a confirmation over
  /// the screen it confirms): the dimmed page stays in view at its sides.
  final bool background;

  @override
  Widget build(BuildContext context) {
    final window = MediaQuery.sizeOf(context).width;
    if (KuteLayout.forWidth(window) == KuteFormFactor.compact) return child;
    final width = math.min(window, KuteLayout.columnMaxWidth);
    final column = Center(
      child: SizedBox(
        width: width,
        height: double.infinity,
        child: kuteNarrowMedia(context, width: width, child: child),
      ),
    );
    if (!background) return column;
    return ColoredBox(color: context.colors.background, child: column);
  }
}

/// A decorative background (a glow, a gradient) drawn across the WHOLE
/// window from inside a centred column or pane, so it is never cut at the
/// column's edges (founder, 25 November 2026, on the Start screen at
/// laptop size: "on desktop the gradient is bad": its two glows stopped
/// in hard vertical lines at the form column's sides). The child is laid
/// out at the window's width, centred on the column, unclipped; it takes
/// no taps outside the column. On a phone it is the child as it was.
class KuteFullBleed extends StatelessWidget {
  const KuteFullBleed({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final window = kuteWindowWidth(context);
    return LayoutBuilder(builder: (context, constraints) {
      if (!constraints.hasBoundedWidth ||
          window <= constraints.maxWidth + 0.5) {
        return child;
      }
      return OverflowBox(
        minWidth: window,
        maxWidth: window,
        alignment: Alignment.center,
        child: child,
      );
    });
  }
}

/// The window's width in logical pixels: the view's, never a pane's or a
/// column's narrowed MediaQuery (a sheet opened from inside a phone-width
/// pane is still a sheet over the whole window).
double kuteWindowWidth(BuildContext context) {
  final view = View.maybeOf(context);
  if (view == null || view.devicePixelRatio <= 0) {
    return MediaQuery.sizeOf(context).width;
  }
  return view.physicalSize.width / view.devicePixelRatio;
}

/// Whether the window is wider than a phone (MEDIUM or EXPANDED), read
/// from the view ([kuteWindowWidth]).
bool kuteWindowIsWide(BuildContext context) =>
    KuteLayout.forWidth(kuteWindowWidth(context)) != KuteFormFactor.compact;

/// The width cap a sheet gets from MEDIUM up, or null on a phone (its
/// full width, as before). Handed to the sheet route's `constraints`.
BoxConstraints? kuteSheetConstraints(BuildContext context) =>
    kuteWindowIsWide(context)
        ? const BoxConstraints(maxWidth: KuteLayout.sheetMaxWidth)
        : null;

/// A sheet's surface from MEDIUM up: at most [KuteLayout.sheetMaxWidth],
/// centred, with the MediaQuery's width narrowed to it. For a sheet route
/// that lays its surface out itself (the send sheet); a route built on
/// Flutter's bottom sheet takes [kuteSheetConstraints] and wraps its
/// content in [KuteSheetMedia].
class KuteSheetWidth extends StatelessWidget {
  const KuteSheetWidth({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final window = MediaQuery.sizeOf(context).width;
    if (KuteLayout.forWidth(window) == KuteFormFactor.compact) return child;
    final width = math.min(window, KuteLayout.sheetMaxWidth);
    return Center(
      heightFactor: 1,
      child: SizedBox(
        width: width,
        child: kuteNarrowMedia(context, width: width, child: child),
      ),
    );
  }
}

/// A sheet's content from MEDIUM up, with the MediaQuery's width the
/// sheet's ([KuteLayout.sheetMaxWidth]) rather than the window's.
class KuteSheetMedia extends StatelessWidget {
  const KuteSheetMedia({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final window = MediaQuery.sizeOf(context).width;
    if (KuteLayout.forWidth(window) == KuteFormFactor.compact) return child;
    return kuteNarrowMedia(context,
        width: math.min(window, KuteLayout.sheetMaxWidth), child: child);
  }
}

/// A phone-width box ([KuteLayout.paneWidth]) centred horizontally from
/// MEDIUM up; [child] as it is on a phone.
class KutePhoneColumn extends StatelessWidget {
  const KutePhoneColumn({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (KuteLayout.isCompact(context)) return child;
    return Center(
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: KuteLayout.paneWidth),
        child: child,
      ),
    );
  }
}

/// The pane the floating Sal bar centres under on an EXPANDED two-pane
/// page ([KuteBarPane]): its global horizontal span, the route it is on
/// and who reported it.
class KuteBarPaneSpan {
  const KuteBarPaneSpan(
      {required this.owner,
      required this.route,
      required this.left,
      required this.width});

  final Object owner;
  final Route<dynamic>? route;
  final double left;
  final double width;

  /// The bar's own span within this pane: centred, at most a phone's
  /// width ([KuteLayout.paneWidth]) and the pane's less 32.
  ({double left, double width}) barSpan() {
    final w = math.max(0.0, math.min(KuteLayout.paneWidth, width - 32));
    return (left: left + (width - w) / 2, width: w);
  }

  @override
  bool operator ==(Object other) =>
      other is KuteBarPaneSpan &&
      identical(other.owner, owner) &&
      other.route == route &&
      other.left == left &&
      other.width == width;

  @override
  int get hashCode => Object.hash(identityHashCode(owner), route, left, width);
}

/// The pane the bar sits under now, reported by a [KuteBarPane]; null on
/// pages with none (the bar is then window-centred). The bar uses it only
/// while the pane's route is on top ([KuteBarRouteObserver.onTop]).
final ValueNotifier<KuteBarPaneSpan?> kuteBarPane =
    ValueNotifier<KuteBarPaneSpan?>(null);

/// Marks [child] as the pane the floating Sal bar belongs under on an
/// EXPANDED window (kute_shell_bar.dart): while its page is the one on
/// screen (its tab shown, its route current) it reports its horizontal
/// span to [kuteBarPane], and clears it when it goes. MEDIUM and phones:
/// nothing reported, the bar is as it was. The pane's own scroll keeps its
/// last rows clear of the bar as on a phone (the bar's room is the same).
class KuteBarPane extends StatefulWidget {
  const KuteBarPane({super.key, required this.child});

  final Widget child;

  @override
  State<KuteBarPane> createState() => _KuteBarPaneState();
}

class _KuteBarPaneState extends State<KuteBarPane> {
  final _key = GlobalKey();

  void _clear() {
    if (identical(kuteBarPane.value?.owner, this)) kuteBarPane.value = null;
  }

  void _report(bool active, Route<dynamic>? route) {
    if (!mounted) return;
    if (!active) return _clear();
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || !box.attached) return;
    // Where the pane rests, by layout alone: a tab sliding in or a page
    // scaling in on its transition paints it elsewhere for a moment, and
    // the bar must not follow that.
    var left = 0.0;
    RenderObject? node = box;
    while (node != null && node.parent != null) {
      final data = node.parentData;
      if (data is BoxParentData) left += data.offset.dx;
      node = node.parent;
    }
    final span = KuteBarPaneSpan(
        owner: this, route: route, left: left, width: box.size.width);
    if (kuteBarPane.value != span) kuteBarPane.value = span;
  }

  @override
  void dispose() {
    final owner = this;
    // After the frame: the notifier's listeners may be building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (identical(kuteBarPane.value?.owner, owner)) kuteBarPane.value = null;
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A resize moves the pane: rebuilt, measured again.
    MediaQuery.sizeOf(context);
    final expanded = KuteLayout.forWidth(kuteWindowWidth(context)) ==
        KuteFormFactor.expanded;
    // A parked tab's page is built with its tickers off.
    final shown = TickerMode.valuesOf(context).enabled;
    final route = ModalRoute.of(context);
    final active = expanded && shown;
    return LayoutBuilder(builder: (context, constraints) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _report(active, route));
      return KeyedSubtree(key: _key, child: widget.child);
    });
  }
}

// ── Round two: the desktop chrome (wide_design_2.md, A to C) ──────────────

/// The desktop top bar's height on EXPANDED (kute_top_nav_bar.dart): the
/// Kute lockup and the Bitcoin | Dollars switch on the left, the search
/// field and the hub button on the right. The tab pages already clear a
/// 64 band at their top for the nav, so nothing under it moves.
const double kuteTopBarHeight = 64;

// THE PANEL (founder, 25 November 2026, the hub beside the search panel:
// "this on desktop instead of a card, maybe show like this search, much
// better"). On EXPANDED the search panel is the model for every sheet:
// top-anchored at [kutePanelTop], centred, rounded all round on the
// sheet's surface ([kutePanelDecoration]), the page dimmed behind it, its
// height hugging its content down to [kutePanelTallest], in and out on
// [kutePanelTransition]. The search panel (unified_search_screen.dart)
// and every sheet's dialog (kute_dialog.dart) read these, so the two
// never drift apart.

/// The room under a panel's foot, and the least above its top.
const double kutePanelMargin = 48;

/// A panel's top in a window of [window]: a tenth of its height, never
/// nearer the edge than [kutePanelMargin].
double kutePanelTop(Size window) =>
    math.max(window.height * 0.1, kutePanelMargin);

/// A panel's tallest under [top] with the keyboard [keyboard] up.
double kutePanelTallest(Size window, {double keyboard = 0, double? top}) =>
    math.max(
        0.0,
        window.height -
            keyboard -
            (top ?? kutePanelTop(window)) -
            kutePanelMargin);

/// A panel's surface: the sheet's own, rounded all round.
BoxDecoration kutePanelDecoration(BuildContext context) =>
    AppDecorations.bottomSheet(context)
        .copyWith(borderRadius: BorderRadius.circular(AppRadius.xxl));

/// A panel's dim.
const Color kutePanelBarrier = Color(0x8A000000);

/// A panel's way in and out: a fade and a small rise on the settle
/// easing ([curved] is the route's animation on that curve).
Widget kutePanelTransition(Animation<double> curved, Widget child) =>
    FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero)
            .animate(curved),
        child: child,
      ),
    );

/// Whether the WINDOW (the view, never a pane's narrowed MediaQuery) is
/// EXPANDED.
bool kuteWindowIsExpanded(BuildContext context) =>
    KuteLayout.forWidth(kuteWindowWidth(context)) == KuteFormFactor.expanded;


/// The floating bar's air under it from the window's bottom edge (founder,
/// round two: "the button in the end give it more space"): 32 on
/// EXPANDED, 24 on MEDIUM, the phone's 2 on a phone. [width] is the
/// window's.
double kuteBarBottomRoomFor(double width) =>
    switch (KuteLayout.forWidth(width)) {
      KuteFormFactor.compact => 2,
      // Raised again (founder, 25 November 2026: "button still too
      // low").
      KuteFormFactor.medium => 36,
      KuteFormFactor.expanded => 44,
    };

/// The window's width from the platform's first view, for a place with no
/// context (the bar's scroll clearance).
double kutePlatformWindowWidth() {
  final views = WidgetsBinding.instance.platformDispatcher.views;
  if (views.isEmpty) return KuteLayout.phoneDesign.width;
  final view = views.first;
  if (view.devicePixelRatio <= 0) return KuteLayout.phoneDesign.width;
  return view.physicalSize.width / view.devicePixelRatio;
}

/// How many sheet panels (kute_dialog.dart) are up: the floating
/// bar stays away while any is, their primary is drawn inside them.
final ValueNotifier<int> kuteDialogsOpen = ValueNotifier<int>(0);

/// Marks a subtree as the content of a sheet drawn as a panel on
/// EXPANDED (kute_dialog.dart). Inside it a sheet draws no drag handle,
/// its bar context's primary is drawn in the dialog's foot, and a close
/// button that the content draws itself ([KuteDialogCloseMark]) tells the
/// dialog it needs no X of its own.
class KuteDialogScope extends InheritedWidget {
  const KuteDialogScope({
    super.key,
    required this.route,
    required this.closeMarks,
    required super.child,
  });

  /// The dialog's route.
  final Route<dynamic>? route;

  /// How many close buttons the content shows now.
  final ValueNotifier<int> closeMarks;

  static KuteDialogScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<KuteDialogScope>();

  /// Without making [context] depend on the scope.
  static KuteDialogScope? peek(BuildContext context) =>
      context.getElementForInheritedWidgetOfExactType<KuteDialogScope>()?.widget
          as KuteDialogScope?;

  /// Whether [context] is inside a sheet panel.
  static bool inDialog(BuildContext context) => peek(context) != null;

  @override
  bool updateShouldNotify(KuteDialogScope old) =>
      old.route != route || old.closeMarks != closeMarks;
}

/// Counts [child] (a close button) in the enclosing [KuteDialogScope]
/// while it is mounted, so the dialog draws no second X. Outside a
/// dialog it is only its child.
class KuteDialogCloseMark extends StatefulWidget {
  const KuteDialogCloseMark({super.key, required this.child});

  final Widget child;

  @override
  State<KuteDialogCloseMark> createState() => _KuteDialogCloseMarkState();
}

class _KuteDialogCloseMarkState extends State<KuteDialogCloseMark> {
  ValueNotifier<int>? _marks;

  void _set(ValueNotifier<int>? next) {
    if (identical(next, _marks)) return;
    final old = _marks;
    _marks = next;
    // After the frame: the dialog's X listens and rebuilds.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (old != null) old.value = old.value - 1;
      if (next != null) next.value = next.value + 1;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _set(KuteDialogScope.maybeOf(context)?.closeMarks);
  }

  @override
  void dispose() {
    final old = _marks;
    _marks = null;
    if (old != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        old.value = old.value - 1;
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
