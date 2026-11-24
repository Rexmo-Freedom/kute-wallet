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
  const KuteFormColumn({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final window = MediaQuery.sizeOf(context).width;
    if (KuteLayout.forWidth(window) == KuteFormFactor.compact) return child;
    final width = math.min(window, KuteLayout.columnMaxWidth);
    return ColoredBox(
      color: context.colors.background,
      child: Center(
        child: SizedBox(
          width: width,
          height: double.infinity,
          child: kuteNarrowMedia(context, width: width, child: child),
        ),
      ),
    );
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
