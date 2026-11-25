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
import 'package:kute/theme/kute_motion.dart';

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

/// The routes whose bar contexts a page draws IN PLACE on EXPANDED
/// (KuteInPlaceBar, kute_dialog.dart: a split screen's form half): while
/// one of them is on top the floating bar stays away, as it does for a
/// panel.
final ValueNotifier<Set<Route<dynamic>>> kuteInPlaceRoutes =
    ValueNotifier<Set<Route<dynamic>>>(<Route<dynamic>>{});

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
    this.surface,
    required super.child,
  });

  /// The dialog's route.
  final Route<dynamic>? route;

  /// How many close buttons the content shows now.
  final ValueNotifier<int> closeMarks;

  /// The surface colour the content paints itself ([KuteDialogSurfaceMark]),
  /// for a side panel to wear from its top to its foot. Null: not asked.
  final ValueNotifier<Color?>? surface;

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
      old.route != route ||
      old.closeMarks != closeMarks ||
      old.surface != surface;
}

/// Tells the enclosing side panel's [KuteDialogScope.surface] that the
/// content paints itself [color] (a receive sheet's pure white), so the
/// panel's foot under it wears the same colour rather than a band of
/// another. Outside a side panel it is only its child.
class KuteDialogSurfaceMark extends StatefulWidget {
  const KuteDialogSurfaceMark(
      {super.key, required this.color, required this.child});

  final Color? color;
  final Widget child;

  @override
  State<KuteDialogSurfaceMark> createState() => _KuteDialogSurfaceMarkState();
}

class _KuteDialogSurfaceMarkState extends State<KuteDialogSurfaceMark> {
  void _report() {
    final surface = KuteDialogScope.peek(context)?.surface;
    final color = widget.color;
    if (surface == null || color == null || surface.value == color) return;
    // After the frame: the panel listens and repaints.
    WidgetsBinding.instance.addPostFrameCallback((_) => surface.value = color);
  }

  @override
  Widget build(BuildContext context) {
    _report();
    return widget.child;
  }
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

// ── Round three: the market desk (founder, 25 November 2026: "not
// occupying full screen", "the card on the right should be a clear screen
// part on the right, not this small") ───────────────────────────────────

/// The side panel of a market page and of the Advanced chart editor on
/// EXPANDED: the order ticket or the bet slip, attached to the window's
/// right edge from its top to its bottom, its side colour the panel's
/// surface. The left side takes the rest of the window, uncapped.
const double kuteSidePanelWidth = 448;

// THE MONEY FLOWS AT THE SIDE (founder, 24 November 2026, of Receive and
// the Bitcoin receive opened from the top bar as centred panels: "these
// ones should open to the side like on fullscreen mode"). On EXPANDED a
// flow opened from the top bar's money actions (Purchase, Scan, Receive,
// Send; Buy dollars, Move) and every step it leads to is a SIDE PANEL:
// the shared panel (kute_dialog.dart, KuteDialogCard) attached to the
// window's right edge from its top to its bottom, [kuteSidePanelWidth]
// wide, sliding in from the right over a light dim, its primary pinned
// in its foot. Everything else keeps the centred panel.
//
// [KuteSideFlow] is the one switch. A top bar action arms it as it fires
// ([KuteSideFlow.arm]); a panel route created while it is on is a side
// panel ([KuteSideFlow.decide], once per route); side panels count
// themselves while they are up. It stays on while any side panel is up,
// so a step opened from a step (a sheet, a pushed named route such as
// Send) is at the side too; for a moment after the last one closes, so a
// hand-off (the scanner closing, then Send opening) stays there; and,
// armed with nothing open yet, for a short wait (Purchase asks the policy
// first). Nothing else arms it, so a phone and MEDIUM never see it.

/// The light dim behind a side panel: the page stays readable.
const Color kuteSidePanelBarrier = Color(0x33000000);

abstract final class KuteSideFlow {
  static DateTime? _armedAt;
  static DateTime? _closedAt;
  static int _open = 0;
  static final Expando<bool> _side = Expando<bool>('kuteSide');

  /// How long an armed flow waits for its first panel.
  static const Duration armedFor = Duration(seconds: 10);

  /// How long after the last side panel closes a new one still opens at
  /// the side (a hand-off).
  static const Duration handOff = Duration(milliseconds: 1500);

  /// A top bar money action fired.
  static void arm() {
    _armedAt = DateTime.now();
    _closedAt = null;
  }

  /// Whether a panel opened now opens at the side.
  static bool get active {
    if (_open > 0) return true;
    final armed = _armedAt;
    if (armed == null) return false;
    final now = DateTime.now();
    final closed = _closedAt;
    if (closed == null) return now.difference(armed) < armedFor;
    return now.difference(closed) < handOff;
  }

  /// Whether [route] is a side panel: decided the first time it is asked
  /// (as the route is created), the same for the rest of its life.
  static bool decide(Route<dynamic> route) => _side[route] ??= active;

  /// Whether [route] was decided a side panel (false if never asked).
  static bool isSide(Route<dynamic>? route) =>
      route != null && (_side[route] ?? false);

  /// Whether a side panel is up now.
  static bool get anyOpen => _open > 0;

  /// A side panel came up.
  static void opened() {
    _open++;
    _closedAt = null;
  }

  /// A side panel went away.
  static void closed() {
    _open = math.max(0, _open - 1);
    if (_open == 0) _closedAt = DateTime.now();
  }

  /// Off, for tests.
  @visibleForTesting
  static void reset() {
    _armedAt = null;
    _closedAt = null;
    _open = 0;
  }
}

/// The gutter between the window's left edge and a market page's
/// content on EXPANDED.
const double kuteDeskGutter = 24;

/// The widest a block of prose runs on a market page's left side.
const double kuteDeskProseMaxWidth = 720;

/// The Advanced chart editor opens with the ticket's side panel beside
/// it from this window width; narrower, folded (its header opens it).
const double kuteEditorPanelOpensAt = 1280;

/// The widest a list of rows (a market's outcomes, its board, Rules) runs
/// under the chart on a market page's left side.
const double kuteDeskListMaxWidth = 960;

// ── Round three: pages that use the window (founder, 25 November 2026) ──
//
// Of Settings on a laptop, a 560 column in the middle of a wide empty
// window: "lots of screens are vertical only. It must be all occupying
// full screen when we can." Round one's rule (every pushed page a centred
// [KuteFormColumn]) holds on MEDIUM only. On EXPANDED a page spans the
// window: page gutters of [kuteWideGutter] (the top bar's), no width cap
// ([kuteWideMaxWidth]; a readable measure inside it), its content arranged in
// COLUMNS ([KuteColumns]) and GRIDS ([KuteGrid], [SliverKuteGrid]) of the
// existing cards and rows, so no row, card or button is stretched and no
// half of the window is empty. A rows card stays about 360-560 wide, prose
// at most about 720. One scroll per page unless it is a real master /
// detail. The back button and the title sit on the page's left gutter.
//
// Every pushed page names how it sits on EXPANDED ([KuteWideMode]); the
// router and the page routes frame it (kute_page_route.dart,
// kutePageFrame). MEDIUM keeps the centred column, a phone is untouched.

/// How a pushed page sits on an EXPANDED window (MEDIUM is always the
/// centred [KuteFormColumn], a phone the page as it is).
enum KuteWideMode {
  /// The centred [KuteLayout.columnMaxWidth] column on EXPANDED too: a
  /// page with nothing to put side by side.
  column,

  /// The page spans the window and lays itself out ([KuteWidePage],
  /// [kuteWidePadding], [KuteColumns], [KuteGrid]).
  full,

  /// A split screen (kute_split_screen.dart): the brand on the left half,
  /// the step's form at phone width on the right, its primary button
  /// under it.
  split,

  /// The shared panel (kute_dialog.dart) over the dimmed page: a page
  /// that is truly short.
  panel,

  /// The page lays itself out from MEDIUM up (its own panes: a market,
  /// the Portfolio, the search).
  own,
}

/// A full page's side gutter on EXPANDED: the desktop top bar's
/// ([kuteDeskGutter]), so a page's back button and its last column stand
/// on the bar's logo and its last button (founder, 25 November 2026:
/// "make it full screen also").
const double kuteWideGutter = kuteDeskGutter;

/// A full page's content width on EXPANDED: no cap, the window between
/// its gutters at any width (founder, 25 November 2026, of pages centred
/// at [KuteLayout.pageMaxWidth] on a 2000 window: "why is this one not
/// full screen also?"). A page with a readable measure (a form, prose, a
/// pair of rows cards) passes its own `maxWidth`.
const double kuteWideMaxWidth = double.infinity;

/// The least width of a column of rows or cards on EXPANDED: three
/// columns from a window of about 1200, two under it.
const double kuteWideColumnMin = 360;

/// A column's widest for a rows card: past it a row reads stretched.
const double kuteWideColumnMax = 560;

/// The gap between columns and between the cards of a grid on EXPANDED.
const double kuteWideGap = 24;

/// Whether [context]'s width (a pane's narrowed MediaQuery included) is
/// EXPANDED: a full page lays itself out by this.
bool kuteIsExpanded(BuildContext context) =>
    KuteLayout.forWidth(MediaQuery.sizeOf(context).width) ==
    KuteFormFactor.expanded;

/// The horizontal padding that centres a full page's content at
/// [maxWidth] with at least [kuteWideGutter] at its sides, for a scroll
/// view's own padding (the whole window scrolls, the content stays in the
/// page). [width] is the page's width. By default the content runs from
/// gutter to gutter ([kuteWideMaxWidth]).
EdgeInsets kuteWidePaddingFor(double width,
    {double maxWidth = kuteWideMaxWidth}) {
  final side = math.max(kuteWideGutter, (width - maxWidth) / 2);
  return EdgeInsets.symmetric(horizontal: side);
}

/// [kuteWidePaddingFor] for [context]'s width.
EdgeInsets kuteWidePadding(BuildContext context,
        {double maxWidth = kuteWideMaxWidth}) =>
    kuteWidePaddingFor(MediaQuery.sizeOf(context).width, maxWidth: maxWidth);

/// A full page's content on EXPANDED: inside the page gutters
/// ([kuteWidePadding]), centred at [maxWidth] when it has one. Elsewhere
/// [child] as it is.
class KuteWidePage extends StatelessWidget {
  const KuteWidePage({
    super.key,
    required this.child,
    this.maxWidth = kuteWideMaxWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    if (!kuteIsExpanded(context)) return child;
    return Padding(
      padding: kuteWidePadding(context, maxWidth: maxWidth),
      child: child,
    );
  }
}

/// How many columns of at least [min] wide (with [gap] between) fit in
/// [width], from 1 to [max].
int kuteColumnsFor(double width,
    {double min = kuteWideColumnMin, double gap = kuteWideGap, int max = 4}) {
  if (!width.isFinite || width <= 0) return 1;
  return ((width + gap) / (min + gap)).floor().clamp(1, math.max(1, max));
}

/// Sections side by side: [children] (each a section: its header and its
/// grouped card, or any block) laid out in as many columns of at least
/// [minColumnWidth] as the width takes, at most [maxColumns] and never
/// more than there are children, filled in reading order across the
/// columns (the first child top left, the second top of the next column,
/// …). Each column's children stack with [spacing] between. One column:
/// a plain stack, as on a phone.
///
/// [KuteColumns.fixed] puts the given [columns] side by side whatever the
/// width (two panes of a detail page), at [flex] proportions.
class KuteColumns extends StatelessWidget {
  const KuteColumns({
    super.key,
    required this.children,
    this.minColumnWidth = kuteWideColumnMin,
    this.maxColumns = 3,
    this.gap = kuteWideGap,
    this.spacing = kuteWideGap,
  })  : columns = null,
        flex = null;

  const KuteColumns.fixed({
    super.key,
    required List<Widget> this.columns,
    this.flex,
    this.gap = kuteWideGap,
  })  : children = const [],
        minColumnWidth = 0,
        maxColumns = 0,
        spacing = 0;

  final List<Widget> children;
  final double minColumnWidth;
  final int maxColumns;
  final double gap;
  final double spacing;

  /// The fixed columns ([KuteColumns.fixed]).
  final List<Widget>? columns;

  /// Their proportions; equal when null.
  final List<int>? flex;

  Widget _row(List<Widget> cols, List<int>? flex) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < cols.length; i++) ...[
            if (i > 0) SizedBox(width: gap),
            Expanded(flex: flex?[i] ?? 1, child: cols[i]),
          ],
        ],
      );

  @override
  Widget build(BuildContext context) {
    final fixed = columns;
    if (fixed != null) return _row(fixed, flex);
    final items = [
      for (final c in children)
        if (c is! SizedBox || c.child != null) c
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final n = kuteColumnsFor(constraints.maxWidth,
          min: minColumnWidth,
          gap: gap,
          max: math.min(maxColumns, math.max(1, items.length)));
      Widget stack(List<Widget> list) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < list.length; i++) ...[
                if (i > 0) SizedBox(height: spacing),
                list[i],
              ],
            ],
          );
      if (n <= 1) return stack(items);
      final cols = List.generate(n, (_) => <Widget>[]);
      for (var i = 0; i < items.length; i++) {
        cols[i % n].add(items[i]);
      }
      return _row([for (final c in cols) stack(c)], null);
    });
  }
}

/// A grid of the existing cards or rows: [children] in rows of as many
/// columns of at least [minItemWidth] as the width takes (at most
/// [maxColumns]), each cell the same width, [gap] between columns and
/// [rowGap] between rows. [equalHeight]: the cells of a row stretch to the
/// tallest (cards with a foot); else each sits at its own height, top
/// aligned. A last row short of cells keeps the others' width (never one
/// card stretched across). Not lazy: for a long list use
/// [SliverKuteGrid].
class KuteGrid extends StatelessWidget {
  const KuteGrid({
    super.key,
    required this.children,
    this.minItemWidth = kuteWideColumnMin,
    this.maxColumns = 4,
    this.gap = kuteWideGap,
    this.rowGap = kuteWideGap,
    this.equalHeight = false,
  });

  final List<Widget> children;
  final double minItemWidth;
  final int maxColumns;
  final double gap;
  final double rowGap;
  final bool equalHeight;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final n = kuteColumnsFor(constraints.maxWidth,
          min: minItemWidth, gap: gap, max: maxColumns);
      final rows = <Widget>[];
      for (var i = 0; i < children.length; i += n) {
        if (i > 0) rows.add(SizedBox(height: rowGap));
        rows.add(kuteGridRow([
          for (var j = i; j < math.min(i + n, children.length); j++) children[j]
        ], columns: n, gap: gap, equalHeight: equalHeight));
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      );
    });
  }
}

/// One row of a [KuteGrid] / [SliverKuteGrid]: [cells] in [columns]
/// equal slots (empty slots at the end of a short row).
Widget kuteGridRow(List<Widget> cells,
    {required int columns,
    double gap = kuteWideGap,
    bool equalHeight = false}) {
  final row = Row(
    crossAxisAlignment:
        equalHeight ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < columns; i++) ...[
        if (i > 0) SizedBox(width: gap),
        Expanded(child: i < cells.length ? cells[i] : const SizedBox.shrink()),
      ],
    ],
  );
  return equalHeight ? IntrinsicHeight(child: row) : row;
}

/// A long list as a grid, built lazily row by row: [itemCount] items from
/// [itemBuilder] in rows of as many columns of at least [minItemWidth] as
/// the sliver's width takes (at most [maxColumns]); see [KuteGrid].
class SliverKuteGrid extends StatelessWidget {
  const SliverKuteGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.minItemWidth = kuteWideColumnMin,
    this.maxColumns = 4,
    this.gap = kuteWideGap,
    this.rowGap = 12,
    this.equalHeight = false,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double minItemWidth;
  final int maxColumns;
  final double gap;
  final double rowGap;
  final bool equalHeight;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(builder: (context, constraints) {
      final n = kuteColumnsFor(constraints.crossAxisExtent,
          min: minItemWidth, gap: gap, max: maxColumns);
      final rows = (itemCount + n - 1) ~/ n;
      return SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, r) {
            final start = r * n;
            return Padding(
              padding: EdgeInsets.only(top: r == 0 ? 0 : rowGap),
              child: kuteGridRow(
                [
                  for (var j = start; j < math.min(start + n, itemCount); j++)
                    itemBuilder(context, j)
                ],
                columns: n,
                gap: gap,
                equalHeight: equalHeight,
              ),
            );
          },
          childCount: rows,
        ),
      );
    });
  }
}

/// The width of the master column's list in a [KuteMasterDetail] (its
/// rows and cards; the page's left gutter is outside it).
const double kuteMasterWidth = 380;

/// Where a [KuteMasterDetail] puts its two panes in a window [width]
/// wide: the master's list on the page's own left gutter ([gutter], the
/// full page's and the top bar's, so the back button and the title never
/// move sideways when the split opens), the hairline at [divider] (the
/// list plus a [kuteWideGutter] after it), the detail from there to the
/// page's right gutter less the [kuteWideGutter] the detail pads itself
/// with ([detailWidth]), so both panes sit inside the page as the full
/// page's content does.
({double gutter, double divider, double detailWidth}) kuteMasterDetailLayout(
    double width,
    {double listWidth = kuteMasterWidth}) {
  final gutter = kuteWidePaddingFor(width).left;
  final divider = gutter + listWidth + kuteWideGutter;
  final right = width - math.max(0.0, gutter - kuteWideGutter);
  return (
    gutter: gutter,
    divider: divider,
    detailWidth: math.max(0.0, right - divider),
  );
}

/// A real MASTER / DETAIL on EXPANDED (round three; Settings and the
/// pages it opens; founder, 24 November 2026: "this is incorrectly
/// formatted. and should animate from this screen to the shared view"):
/// [master] as a section list on the page's left gutter, a quiet hairline,
/// [detail] beside it ([kuteMasterDetailLayout]), each scrolling on its
/// own. The master's subtree is marked ([KuteMasterScope], with the
/// gutter and the [selected] detail) so it lays itself out as the list
/// and opens the next detail in place of this one. Off EXPANDED it is
/// [detail] alone, as before.
///
/// THE MOTION. The route that shows this ([kuteSettingsDetailPageKey],
/// app_router.dart) wears no page transition of its own on EXPANDED; this
/// widget plays the route's animation instead, over the full page it was
/// pushed from (still painted under it while the route moves): the master
/// pane (the window's background and the list) fades in over the full
/// page, whose back button and title sit exactly where the list's do, so
/// they hold still while the page's sections settle into the list; the
/// detail slides in from the window's right edge on the settle easing,
/// its hairline leading. Back plays it in reverse. Opening another detail
/// from the list keeps this route (the same page key): the master stays
/// put, scroll and all, and only the detail cross-fades ([selected] keys
/// it). Reduce Motion: plain fades, no slide.
class KuteMasterDetail extends StatelessWidget {
  const KuteMasterDetail({
    super.key,
    required this.master,
    required this.detail,
    this.selected,
    this.masterWidth = kuteMasterWidth,
  });

  final Widget master;
  final Widget detail;

  /// Which detail is open (the master marks its row); a new value
  /// cross-fades the detail.
  final Object? selected;

  /// The master's list width.
  final double masterWidth;

  @override
  Widget build(BuildContext context) {
    if (!kuteIsExpanded(context)) return detail;
    final c = context.colors;
    final width = MediaQuery.sizeOf(context).width;
    final layout = kuteMasterDetailLayout(width, listWidth: masterWidth);
    final rest = layout.detailWidth;
    final reduce = KuteMotion.reduce(context);
    final animation = ModalRoute.of(context)?.animation ?? kAlwaysCompleteAnimation;
    // A fade THROUGH, never two layouts over each other: the window's
    // background first covers the full page under the route (all but its
    // back button and title, which the list's own sit on exactly), then
    // the list's rows come in. Back: the rows go, then the background.
    // Each part leaves on the settle easing played backwards, so back
    // answers at once.
    final ease = reduce ? Curves.linear : KuteMotion.settle;
    final back = reduce ? Curves.linear : KuteMotion.settle.flipped;
    final cover = CurvedAnimation(
      parent: animation,
      curve: Interval(0, reduce ? 1 : 0.45, curve: ease),
      reverseCurve: Interval(0, reduce ? 1 : 0.45, curve: back),
    );
    final reveal = CurvedAnimation(
      parent: animation,
      curve: Interval(reduce ? 0 : 0.4, 1, curve: ease),
      reverseCurve: Interval(reduce ? 0 : 0.4, 1, curve: back),
    );
    final slide =
        CurvedAnimation(parent: animation, curve: ease, reverseCurve: back);
    // A detail narrower than EXPANDED (a window of about 1300 or less)
    // is the centred column a MEDIUM page is.
    final detailPane = DecoratedBox(
      // The hairline over the detail's own background.
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: c.border)),
      ),
      // The floating bar centres under the detail.
      child: KuteBarPane(
        child: ColoredBox(
          color: c.background,
          child: AnimatedSwitcher(
        duration:
            reduce ? KuteMotion.reducedDuration : KuteMotion.settleDuration,
        // A fade through: the old detail is gone before the new one
        // comes in, never two pages over each other.
        switchInCurve: Interval(reduce ? 0 : 0.35, 1, curve: ease),
        switchOutCurve: Interval(reduce ? 0 : 0.6, 1, curve: ease),
        layoutBuilder: (current, previous) => Stack(
          fit: StackFit.expand,
          children: [...previous, if (current != null) current],
        ),
        child: KeyedSubtree(
          key: ValueKey<Object?>(selected),
          child: kuteNarrowMedia(context,
              width: rest,
              child: KuteLayout.forWidth(rest) == KuteFormFactor.expanded
                  ? detail
                  : KuteFormColumn(child: detail)),
            ),
          ),
        ),
      ),
    );
    return Stack(
      children: [
        Positioned.fill(
          child: FadeTransition(
            opacity: cover,
            child: ColoredBox(color: c.background),
          ),
        ),
        Positioned(
          left: 0,
          width: layout.divider,
          top: 0,
          bottom: 0,
          child: KuteMasterScope(
            gutter: layout.gutter,
            selected: selected,
            reveal: reveal,
            child: kuteNarrowMedia(context,
                width: layout.divider, child: master),
          ),
        ),
        Positioned(
          left: layout.divider,
          width: rest,
          top: 0,
          bottom: 0,
          // The detail slides in from the window's right edge, its
          // hairline leading (a plain fade under Reduce Motion).
          child: reduce
              ? FadeTransition(opacity: slide, child: detailPane)
              : SlideTransition(
                  position: Tween<Offset>(
                    begin: Offset(
                        rest > 0 ? (width - layout.divider) / rest : 0, 0),
                    end: Offset.zero,
                  ).animate(slide),
                  child: detailPane,
                ),
        ),
      ],
    );
  }
}

/// Marks the master column of a [KuteMasterDetail]: a page drawn there is
/// the section list beside a detail, on the page's left [gutter], with
/// the [selected] detail's row marked, and opens its next detail in place
/// of the one shown.
class KuteMasterScope extends InheritedWidget {
  const KuteMasterScope({
    super.key,
    this.gutter = kuteWideGutter,
    this.selected,
    this.reveal = kAlwaysCompleteAnimation,
    required super.child,
  });

  /// The page's left gutter, where the list starts.
  final double gutter;

  /// Which detail is open beside the list.
  final Object? selected;

  /// The list's rows' opacity as the split opens and closes (the back
  /// button and the title hold still; the [KuteMasterDetail] paints the
  /// background under the list, so the list paints none of its own).
  final Animation<double> reveal;

  static bool inMaster(BuildContext context) =>
      context.getElementForInheritedWidgetOfExactType<KuteMasterScope>() !=
      null;

  /// The scope [context] is drawn in, or null outside a master column.
  static KuteMasterScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<KuteMasterScope>();

  @override
  bool updateShouldNotify(KuteMasterScope oldWidget) =>
      gutter != oldWidget.gutter ||
      selected != oldWidget.selected ||
      reveal != oldWidget.reveal;
}

/// [child] (a master column's rows, under its fixed back button and
/// title) at [scope]'s reveal as the split opens and closes; [child] as
/// it is outside a master column.
Widget kuteMasterReveal(KuteMasterScope? scope, Widget child) =>
    scope == null ? child : FadeTransition(opacity: scope.reveal, child: child);

/// The `extra` a Settings sub-page is pushed with when Settings opened it:
/// on EXPANDED the router shows it as the detail beside Settings
/// ([KuteMasterDetail], app_router.dart).
const String kuteSettingsDetailExtra = 'kute.settings.detail';

// ── The Dollars browse uses the window (founder, 24 November 2026) ──
//
// Of the Investing and Predictions browse on a wide laptop window: "maybe
// for desktop make this look a bit better? occupy full screen?" On
// EXPANDED the Dollars page spans the window, as the market pages do: no
// [KuteLayout.pageMaxWidth] cap, the lists' edges on the desktop top
// bar's gutter (its logo, the pills, the chips and the grid on one left
// edge), and the grid's columns growing with the width
// ([kuteBrowseColumnsFor]).

/// The lists' own inset inside a browse pane (market_groups.dart's 16 at
/// the list's sides).
const double kuteBrowseListInset = 16;

/// The Dollars page's side padding on EXPANDED: with the lists' own
/// [kuteBrowseListInset] inside it, the content's edges sit on
/// [kuteDeskGutter], the top bar's (KuteLayout.paneGap, the same 24).
const double kuteBrowsePagePadding = kuteDeskGutter - kuteBrowseListInset;

/// The narrowest list column of the browse grid on EXPANDED: an Investing
/// row and a Predictions card read whole at it.
const double kuteBrowseColumnMin = 300;

/// The most columns the browse grid takes, however wide the window
/// (each about 380 on a 2400 window).
const int kuteBrowseColumnsMax = 6;

/// How many list columns of the browse grid stand in a content [width]
/// (the lists' insets already out) with [gap] between them: as many of
/// at least [kuteBrowseColumnMin] as fit, from 1 to
/// [kuteBrowseColumnsMax].
int kuteBrowseColumnsFor(double width, {double gap = 16}) {
  if (!width.isFinite || width <= 0) return 1;
  return ((width + gap) / (kuteBrowseColumnMin + gap))
      .floor()
      .clamp(1, kuteBrowseColumnsMax);
}

/// The page key every Settings detail is shown under (app_router.dart):
/// opening another detail from the master column replaces the page with
/// one of the same key, so the navigator keeps the route (and the master
/// in it) and only the detail changes ([KuteMasterDetail]).
const ValueKey<String> kuteSettingsDetailPageKey =
    ValueKey<String>(kuteSettingsDetailExtra);

// ── The Dollars page's left navigation (founder, 24 November 2026) ──
//
// Of the three stacked rows of pills and chips over the browse: "also
// these layers deep, I don't like it. Even on desktop … make use of the
// left side of the screen, which is empty now, for this please". From
// [kuteDeskNavMinWidth] the sections, their categories and the open
// category's subcategories are one tree down the page's left side
// (dollars_desk_nav.dart), [kuteDeskNavWidthFor] wide, its left edge on
// the top bar's logo ([kuteDeskGutter]). Narrower EXPANDED windows (900
// to 1099) keep the pills and the chips over the browse: there, with the
// open positions' column beside it, the browse would be left one column
// of about 270, its names cut ("Nasdaq …").

/// The narrowest window that shows the Dollars page's left navigation.
const double kuteDeskNavMinWidth = 1100;

/// The left navigation's width in a window [width] wide: 192 up to a
/// 1200 window, then growing with it to 248 (from 1550).
double kuteDeskNavWidthFor(double width) =>
    (width * 0.16).clamp(192.0, 248.0);

/// The room between the left navigation's items and the hairline that
/// closes it, and between the hairline and the browse's edge (the lists'
/// own [kuteBrowseListInset] then inside the browse).
const double kuteDeskNavGap = 12;
