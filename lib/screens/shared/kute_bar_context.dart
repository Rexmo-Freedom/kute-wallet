// lib/screens/shared/kute_bar_context.dart
//
// THE BOTTOM BAR IS ALWAYS PRESENT AND CONTEXT-AWARE (founder, 31 October
// 2026): the floating Sal pill is the one place that calls Sal or the
// screen's own action, on every screen, over sheets too. Each screen or
// sheet declares what the bar says and does while it is up through a
// [KuteBarContext], held on a stack ([kuteBarContextProvider]) by a
// [KuteBarContextScope] around its content: pushed on mount, taken off on
// dispose, so the bar always reads the topmost thing on screen and goes
// back to the one under it when that closes. Home and Dollars draw their
// own pill in their dock (the default, "Search or ask Sal"); every other
// surface is drawn by the shell-level [KuteShellBar] (kute_shell_bar.dart)
// over the root navigator, so it sits above modal barriers and sheets.
//
// EVERY SHEET AND PAGE SHOWS THE BAR (founder, 31 October 2026): a
// surface with no context of its own, a Receive sheet, the scanner, a
// slip, a receipt, Settings, gets the default ("Search or ask Sal"). The
// bar knows something is over the tabs through [KuteBarRouteObserver],
// one on the root navigator and one on each tab's navigator
// (app_router.dart): every page route and bottom-sheet route pushed over
// a tab counts ([KuteBarRouteObserver.over]); dialogs and menus do not,
// and nor do the onboarding and lock screens ([kuteBarSilentRoutes]).
// Nothing reserves room for the bar: it floats over the content, which
// may scroll under it. The bar hides ONLY while the keyboard is up or the
// Sal sheet itself is open (a [hidden] context).
//
// A context is honoured while its own route is current: a scope records
// the route it is mounted in, and a sheet pushed over that page (a slip
// over a market) gets the default bar at the bottom rather than the
// page's context lifted over a row that is now covered.
//
// NEVER OVER A SCREEN'S OWN ACTION ROW: a page with a pinned row at its
// foot (a market's Yes / No pair, Invest, Close position) declares the
// row's height in [actionRowHeight] (the row plus its own bottom padding,
// read from its code); the bar sits above that, and the lift animates on
// the sheet spring when the row appears or goes.
//
// Tapping the bar ALWAYS opens the same search / Sal sheet as Home, with
// the context's block on top: a "Recommended" block with the screen's
// action rows ([actions]: "Share the market", "Send dollars for this
// market"; the top categories of the category grid), Sal's prompt chips
// tuned to the screen ([prompts]), and the composer scoped to that venue
// ([category], [searchHint]). A keyboard-driven surface, and the Sal
// sheet itself, push a [hidden] context: the bar slides away.
//
// Share links: the two market rows go through the share flow in
// screens/share/ (the market share sheet, Send to anyone); see
// kute_share_actions.dart for the link they carry.
//
// The page's scroll reaches the bar through [kuteBarScroll]: the
// NotificationListener around the router (app_widget.dart) reports every
// vertical scroll, and the bar collapses on a market page while the page
// scrolls down (kute_shell_bar.dart).

import 'dart:async';

import 'package:flutter/material.dart' show ModalBottomSheetRoute;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart' show NoTransitionPage;
import 'package:kute/providers/unified_search_provider.dart'
    show SearchCategory;

/// One recommended action row in the Sal sheet. [onTap] runs after the
/// sheet has closed; [sheetContext] is the Sal sheet's own context (for a
/// row that opens something else, a toast, a share sheet).
class KuteBarAction {
  const KuteBarAction({
    required this.label,
    this.sublabel,
    required this.onTap,
  });

  final String label;
  final String? sublabel;
  final void Function(BuildContext sheetContext) onTap;
}

/// What the bar says and does while its surface is on screen.
class KuteBarContext {
  const KuteBarContext({
    required this.label,
    this.sublabel,
    this.clip = 'search',
    this.actions = const [],
    this.prompts = const [],
    this.category = SearchCategory.all,
    this.searchHint,
    this.source = 'bar',
    this.hidden = false,
    this.actionRowHeight = 0,
    this.route,
  });

  /// A context that only hides the bar (a keyboard surface, the Sal sheet).
  const KuteBarContext.hidden()
      : label = '',
        sublabel = null,
        clip = 'search',
        actions = const [],
        prompts = const [],
        category = SearchCategory.all,
        searchHint = null,
        source = 'bar',
        hidden = true,
        actionRowHeight = 0,
        route = null;

  final String label;
  final String? sublabel;

  /// Sal's clip in the bar: `search`, or `share` on a market or position.
  final String clip;
  final List<KuteBarAction> actions;

  /// Sal's prompt chips for this screen; empty for the Home set.
  final List<String> prompts;
  final SearchCategory category;
  final String? searchHint;

  /// The `search_opened` source.
  final String source;
  final bool hidden;

  /// The height of the screen's own pinned action row at its foot (the
  /// row plus its bottom padding), in logical pixels; 0 with none. The
  /// bar sits above it (see the file header).
  final double actionRowHeight;

  /// The route the context's scope is mounted in, set by
  /// [KuteBarContextScope]; the bar honours the context while this route
  /// is current. Null: always honoured (the Sal sheet's hidden context).
  final Route<dynamic>? route;

  bool get hasRecommendations => actions.isNotEmpty;

  /// A market or position page's context: the bar moves with the page
  /// there (kute_shell_bar.dart). Its clip is the `share` one
  /// (kute_share_actions.dart).
  bool get market => clip == 'share';

  /// Whether the bar should read this context now: its route is current,
  /// or it has none.
  bool get current => route == null || route!.isCurrent;

  /// This context bound to [route] (see [KuteBarContextScope]).
  KuteBarContext boundTo(Route<dynamic>? route) => KuteBarContext(
        label: label,
        sublabel: sublabel,
        clip: clip,
        actions: actions,
        prompts: prompts,
        category: category,
        searchHint: searchHint,
        source: source,
        hidden: hidden,
        actionRowHeight: actionRowHeight,
        route: route,
      );
}

class KuteBarContextStack extends Notifier<List<KuteBarContext>> {
  @override
  List<KuteBarContext> build() => const [];

  void push(KuteBarContext ctx) => state = [...state, ctx];

  void replace(KuteBarContext old, KuteBarContext next) =>
      state = [for (final c in state) c == old ? next : c];

  void remove(KuteBarContext ctx) =>
      state = [for (final c in state) if (c != ctx) c];
}

/// The contexts on screen, bottom to top; the bar reads the last.
final kuteBarContextProvider =
    NotifierProvider<KuteBarContextStack, List<KuteBarContext>>(
        KuteBarContextStack.new);

/// The bar's current context, or null for the dock's default.
KuteBarContext? kuteBarTop(List<KuteBarContext> stack) =>
    stack.isEmpty ? null : stack.last;

/// Holds [barContext] on the stack while mounted (see the file header),
/// bound to the route it is mounted in.
class KuteBarContextScope extends ConsumerStatefulWidget {
  const KuteBarContextScope(
      {super.key, required this.barContext, required this.child});

  final KuteBarContext barContext;
  final Widget child;

  @override
  ConsumerState<KuteBarContextScope> createState() =>
      _KuteBarContextScopeState();
}

class _KuteBarContextScopeState extends ConsumerState<KuteBarContextScope> {
  KuteBarContextStack? _stack;
  KuteBarContext? _held;
  Route<dynamic>? _route;

  @override
  void initState() {
    super.initState();
    // Provider writes are illegal while the tree is building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _route = ModalRoute.of(context);
      _stack = ref.read(kuteBarContextProvider.notifier);
      _held = widget.barContext.boundTo(_route);
      _stack!.push(_held!);
    });
  }

  @override
  void didUpdateWidget(covariant KuteBarContextScope old) {
    super.didUpdateWidget(old);
    final held = _held;
    if (held == null || identical(old.barContext, widget.barContext)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _held != held) return;
      _held = widget.barContext.boundTo(_route);
      _stack?.replace(held, _held!);
    });
  }

  @override
  void dispose() {
    final held = _held;
    final stack = _stack;
    if (held != null && stack != null) {
      // After the frame: the stack's listeners must not rebuild mid-tear-down.
      WidgetsBinding.instance.addPostFrameCallback((_) => stack.remove(held));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ── Routes over the tabs ─────────────────────────────────────────────────

/// Route names the bar stays away from: the splash, onboarding and the
/// PIN screens (nothing to search before a wallet exists, nothing while
/// it is locked), and the tab roots themselves (their dock draws the
/// pill).
const Set<String> kuteBarSilentRoutes = {
  'splash',
  'start',
  'claim',
  'seed_words',
  'open_pin',
  'confirm_pin',
  'passkey_choice',
  'beta_survey',
  'referrer_code',
  'share_code',
  'wallet_creation',
  'set_pin',
  'home',
  'bank',
  'usd',
  'hyperliquid',
  'polymarket',
};

/// Counts the routes over the tabs (see the file header). One instance
/// per navigator (a Flutter observer belongs to one navigator); they all
/// write the one [over] count.
class KuteBarRouteObserver extends NavigatorObserver {
  /// The routes on screen that the bar shows over.
  static final Set<Route<dynamic>> _over = {};

  /// How many pages and sheets are over the tabs; the bar shows the
  /// default context while this is above zero and no context is on the
  /// stack.
  static final ValueNotifier<int> over = ValueNotifier<int>(0);

  @visibleForTesting
  static void reset() {
    _over.clear();
    over.value = 0;
  }

  /// Whether the bar shows over [route]: a page route or a bottom-sheet
  /// route (never a dialog or a menu), not one of [kuteBarSilentRoutes].
  /// A router page with no name is one of the tab shell's own
  /// ([NoTransitionPage]: the shell, a tab root) or a pushed page whose
  /// GoRoute has no name (counted).
  static bool counts(Route<dynamic> route) {
    final settings = route.settings;
    if (settings is Page) {
      final name = settings.name;
      if (name == null || name.isEmpty) return settings is! NoTransitionPage;
      return !kuteBarSilentRoutes.contains(name);
    }
    final name = settings.name;
    if (name != null && kuteBarSilentRoutes.contains(name)) return false;
    return route is PageRoute || route is ModalBottomSheetRoute;
  }

  static void _add(Route<dynamic> route) {
    if (!counts(route) || !_over.add(route)) return;
    _publish();
  }

  static void _drop(Route<dynamic> route) {
    if (!_over.remove(route)) return;
    _publish();
  }

  /// The navigator calls in from inside its frame work, sometimes mid
  /// build; the bar is told after it.
  static void _publish() {
    scheduleMicrotask(() => over.value = _over.length);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // A navigator's first route is the surface itself, never over it.
    if (previousRoute == null) return;
    _add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _drop(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _drop(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) _drop(oldRoute);
    if (newRoute != null) _add(newRoute);
  }
}

// ── The page's scroll ────────────────────────────────────────────────────

/// What the page under the bar just did with its scroll.
enum KuteBarScroll {
  /// A scroll ended, or nothing has scrolled.
  idle,

  /// Content moved up: the person is reading down the page.
  down,

  /// Content moved down: the person is going back up.
  up,
}

/// The page's vertical scroll, reported by the NotificationListener around
/// the router (app_widget.dart) and read by the bar. Every report
/// notifies, a repeat of the same direction too, so the bar's idle timer
/// restarts on each.
class KuteBarScrollSignal extends ChangeNotifier {
  KuteBarScroll last = KuteBarScroll.idle;

  /// The NotificationListener's callback: horizontal scrolls (the tabs'
  /// swipe, a carousel) and the frames with no movement are ignored.
  bool report(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0;
      if (delta > 0.5) {
        _set(KuteBarScroll.down);
      } else if (delta < -0.5) {
        _set(KuteBarScroll.up);
      }
    } else if (notification is ScrollEndNotification) {
      _set(KuteBarScroll.idle);
    }
    return false;
  }

  void _set(KuteBarScroll value) {
    last = value;
    notifyListeners();
  }
}

final KuteBarScrollSignal kuteBarScroll = KuteBarScrollSignal();
