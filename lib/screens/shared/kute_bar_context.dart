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
// own pill in their dock (the default, "Search or Manage with AI"); every
// other surface is drawn by the shell-level [KuteShellBar]
// (kute_shell_bar.dart) over the root navigator, so it sits above modal
// barriers and sheets.
//
// EVERY SHEET AND PAGE SHOWS THE BAR (founder, 31 October 2026): a surface with
// no context of its own, a Receive sheet, the scanner, a slip, a receipt,
// Settings, gets the default ("Search or Manage with AI"). The bar knows
// something is over the tabs through [KuteBarRouteObserver], one on the root
// navigator and one on each tab's navigator (app_router.dart): every page route
// and bottom-sheet route pushed over a tab counts
// ([KuteBarRouteObserver.over]); dialogs and menus do not, and nor do the
// onboarding and lock screens ([kuteBarSilentRoutes]). Nothing reserves room
// for the bar: it floats over the content, which may scroll under it. The bar
// hides ONLY while the keyboard is up or the Sal sheet itself is open (a
// [hidden] context).
//
// EVERY PINNED PRIMARY BUTTON IS THE BAR (founder, 31 October 2026): a
// screen or sheet whose foot had a Continue / Send / Claim / Done draws
// none and declares it with [KuteBarContext.primary] instead (the label,
// the enabled and busy states as the button had them), keeping its
// content clear of the bar with [kuteBarScrollClearance]. A second pinned
// button (Cancel, Skip) stays on the page as a text button above the bar.
// A short sheet hides the bar (app_bottom_sheet.dart) UNLESS its own
// primary is the bar: a primary context mounted in the same route beats
// the sheet's hidden one ([kuteBarTop]), so the sheet is never left with
// no button at all. Onboarding and the Claim screen are silent for the
// default pill ([kuteBarSilentRoutes]) but show their own primary.
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
// the context's block on top: a market page's preview and its send cards
// ([actions]: "Share the market", "Send this prediction"; drawn only with
// a market's preview, never as generic arrow cards), or the surface's own
// widget in place of the home's blocks ([sheetHome]: over the category
// sheet, every category of the venue as the grid's own tiles), Sal's
// prompt chips tuned to the screen ([prompts]), and the composer scoped
// to that venue ([category], [searchHint]). A keyboard-driven surface, and the Sal
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
import 'package:kute/models/advisor_context.dart';
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

/// How a surface's primary button is painted when the bar is it (founder,
/// 31 October 2026: NEVER black on a tinted slip). The bet slip, the sell
/// and close sheets and the margin sheets hand the bar exactly the look
/// their own CTA had: the slip's ink as [fill] (white on the green Yes
/// slip, on the red No slip), the trade lettered in the side colour or a
/// neutral action in the contrast ([foreground]), the slip's [radius] and
/// weight. Without a style the bar is the app's primary button
/// (textPrimary fill). A disabled styled button fades whole, as the slip's
/// did.
class KuteBarPrimaryStyle {
  const KuteBarPrimaryStyle({
    required this.fill,
    required this.foreground,
    this.disabledFill,
    this.disabledForeground,
    this.radius,
    this.fontWeight,
  });

  final Color fill;
  final Color foreground;

  /// The fill and ink while the action is not available; the live ones at
  /// 0.35 when null.
  final Color? disabledFill;
  final Color? disabledForeground;
  final BorderRadius? radius;
  final FontWeight? fontWeight;
}

/// What the bar is on a surface: the search / Sal pill, or the surface's
/// PRIMARY BUTTON (founder, 31 October 2026: on amount and keypad
/// screens and slips the bar IS the Place / Send / Continue button; the
/// page draws none of its own). See [KuteBarContext.primary].
enum KuteBarKind { search, primaryAction }

/// Where a surface's Sal control sits (founder, 31 October 2026): the
/// floating pill at the foot of the screen ([bottom], the default), or a
/// compact circle the page draws in its own header's top-right
/// ([header]: market, position and multi-outcome event pages, where the
/// pill covered the Advanced chart and Rules rows). With [header] the
/// shell bar keeps its pill away and the page renders
/// `KuteSalHeaderButton` (kute_shell_bar.dart) with this same context.
enum KuteBarPlacement { bottom, header }

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
    this.question,
    this.advisorContext,
    this.placement = KuteBarPlacement.bottom,
    this.sheetHome,
  })  : kind = KuteBarKind.search,
        enabled = true,
        busy = false,
        onPrimary = null,
        busyLabel = null,
        disabledLabel = null,
        pairedWidth = null,
        style = null;

  /// Where this surface's Sal control sits (see [KuteBarPlacement]).
  final KuteBarPlacement placement;

  /// An informational screen's question ("Explain this receive screen…"):
  /// tapping the bar opens the Sal sheet with it already sent.
  final String? question;

  /// The public context Sal answers with when this bar opens it (a
  /// receipt's surface, a market's): the Sal sheet's questions carry it,
  /// as the small Ask Sal circle's once did. Only public, non-identifying
  /// fields ever leave the device (see [AdvisorContext]).
  final AdvisorContext? advisorContext;

  /// The bar as the surface's primary button: [label] ("Place prediction
  /// · $10", "Continue"), [onPrimary] the exact handler the page's button
  /// had, [enabled] false for the disabled state, [busy] while the action
  /// runs ([busyLabel], "Sending…", else [label]). A long press opens the
  /// Sal sheet with [category] / [searchHint] so asking Sal stays one
  /// gesture away.
  ///
  /// THE DISABLED BUTTON SAYS WHAT TO DO (founder, 1 November 2026): while
  /// [enabled] is false the button reads [disabledLabel], the step the
  /// person has to take ("Enter an amount", "Add who to send to", "Paste
  /// an address", "Tick the box to continue"), in the light pill look;
  /// never the greyed action. EVERY call site sets it (an architecture
  /// test holds them to it); null only where the button is never disabled
  /// for want of input (it is then [label]).
  const KuteBarContext.primary({
    required this.label,
    required this.onPrimary,
    this.enabled = true,
    this.busy = false,
    this.busyLabel,
    this.disabledLabel,
    this.style,
    this.clip = 'idle',
    this.pairedWidth,
    this.category = SearchCategory.all,
    this.searchHint,
    this.source = 'bar',
    this.route,
  })  : question = null,
        advisorContext = null,
        kind = KuteBarKind.primaryAction,
        sublabel = null,
        actions = const [],
        prompts = const [],
        hidden = false,
        actionRowHeight = 0,
        placement = KuteBarPlacement.bottom,
        sheetHome = null;

  final KuteBarKind kind;
  final bool enabled;
  final bool busy;
  final VoidCallback? onPrimary;
  final String? busyLabel;

  /// What the disabled button says (see [KuteBarContext.primary]).
  final String? disabledLabel;

  /// The primary button exactly this wide: a page that pairs it with a
  /// pill of its own (the Recover screen's account option) gives both the
  /// wider of their two widths, capped at the page's width.
  final double? pairedWidth;

  /// Whether the primary button takes a tap now.
  bool get actionable => enabled && !busy && onPrimary != null;

  /// The words on the primary button now: the busy label while busy, the
  /// action while it takes a tap, else what the person has to do.
  String get primaryLabel => busy
      ? (busyLabel ?? label)
      : actionable
          ? label
          : (disabledLabel ?? label);

  /// The surface's own button look for the bar (a tinted slip's); null
  /// for the app's primary button. See [KuteBarPrimaryStyle].
  final KuteBarPrimaryStyle? style;

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
        route = null,
        question = null,
        advisorContext = null,
        kind = KuteBarKind.search,
        enabled = true,
        busy = false,
        onPrimary = null,
        busyLabel = null,
        disabledLabel = null,
        pairedWidth = null,
        placement = KuteBarPlacement.bottom,
        sheetHome = null,
        style = null;

  /// The Sal control is the page's own header circle, not the pill.
  bool get inHeader => placement == KuteBarPlacement.header;

  /// The bar is this surface's primary button (see [KuteBarContext.primary]).
  bool get isPrimary => kind == KuteBarKind.primaryAction;

  final String label;
  final String? sublabel;

  /// Sal's clip in the bar: `search`, or `share` on a market or position;
  /// on a primary button the clip while it takes a tap (`idle`, `happy` on
  /// a result sheet's Done).
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

  /// The Sal sheet's home while this context opened it, in place of the
  /// home's blocks, under the composer: the surface's own widget, built
  /// in the Sal sheet with its context (the Investments category sheet:
  /// every category of the venue as the grid's own tiles, a tap picking
  /// it and closing both sheets). Null: the home, or the market preview
  /// and its cards.
  final WidgetBuilder? sheetHome;

  bool get hasRecommendations => actions.isNotEmpty || sheetHome != null;

  /// A market or position page's context: the bar moves with the page
  /// there (kute_shell_bar.dart). Its clip is the `share` one
  /// (kute_share_actions.dart).
  bool get market => clip == 'share';

  /// Whether the bar should read this context now: its route is current,
  /// or it has none.
  bool get current => route == null || route!.isCurrent;

  /// This context bound to [route] (see [KuteBarContextScope]).
  KuteBarContext boundTo(Route<dynamic>? route) => isPrimary
      ? KuteBarContext.primary(
          label: label,
          onPrimary: onPrimary,
          enabled: enabled,
          busy: busy,
          busyLabel: busyLabel,
          disabledLabel: disabledLabel,
          style: style,
          clip: clip,
          pairedWidth: pairedWidth,
          category: category,
          searchHint: searchHint,
          source: source,
          route: route,
        )
      : KuteBarContext(
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
          question: question,
          advisorContext: advisorContext,
          placement: placement,
          sheetHome: sheetHome,
        );
}

class KuteBarContextStack extends Notifier<List<KuteBarContext>> {
  /// The live stack, for the route observer (which has no ref): the
  /// contexts bound to a route go the moment the route goes, whatever
  /// path popped it (back, a swipe, a barrier tap, go() away), and a
  /// scope's late dispose then finds nothing to remove. A newer context
  /// is a different object, so nothing of it is ever taken by mistake.
  static KuteBarContextStack? instance;

  @override
  List<KuteBarContext> build() {
    instance = this;
    ref.onDispose(() {
      if (instance == this) instance = null;
    });
    return const [];
  }

  /// Puts [ctx] on the stack IN ROUTE ORDER, not simply on top: beside
  /// the contexts its own route already holds, and under every context of
  /// a route that is current (or of none) when its route is not. A scope
  /// that remounts under a covering page (a slip's, as the band under it
  /// changed shape) must never land its context over the page on top:
  /// the bar read the slip's button on the slip's Advanced page.
  void push(KuteBarContext ctx) {
    final list = [...state];
    final route = ctx.route;
    var at = list.length;
    final mate = route == null ? -1 : list.lastIndexWhere((c) => c.route == route);
    if (mate >= 0) {
      at = mate + 1;
    } else if (route != null && !route.isCurrent) {
      final above =
          list.indexWhere((c) => c.route == null || c.route!.isCurrent);
      if (above >= 0) at = above;
    }
    list.insert(at, ctx);
    state = list;
  }

  void replace(KuteBarContext old, KuteBarContext next) =>
      state = [for (final c in state) c == old ? next : c];

  void remove(KuteBarContext ctx) {
    if (!state.contains(ctx)) return;
    state = [for (final c in state) if (c != ctx) c];
  }

  /// Every context bound to [route] (see [instance]).
  void removeRoute(Route<dynamic> route) {
    if (!state.any((c) => c.route == route)) return;
    state = [for (final c in state) if (c.route != route) c];
  }
}

/// True while the tab shell (AppShell) is mounted: the bar is the ONE
/// pill of the app, on the tab roots too (founder, 31 October 2026: one
/// bar instance; Home and Dollars draw none of their own). Never on
/// onboarding or the cold-start PIN, whatever is pushed there.
final ValueNotifier<bool> kuteShellMounted = ValueNotifier<bool>(false);

/// The contexts on screen, bottom to top; the bar reads the last.
final kuteBarContextProvider =
    NotifierProvider<KuteBarContextStack, List<KuteBarContext>>(
        KuteBarContextStack.new);

/// The bar's current context, or null for the dock's default. A hidden
/// context bound to a route (a short sheet's) gives way to a primary one
/// bound to the same route: the sheet's own button is the bar (see the
/// file header). The Sal sheet's hidden context has no route and always
/// wins.
KuteBarContext? kuteBarTop(List<KuteBarContext> stack) {
  if (stack.isEmpty) return null;
  final top = stack.last;
  if (top.isPrimary || top.route == null) return top;
  // The page's own primary button is the bar, whatever else the page
  // declared for it (its short-sheet hidden context, or a search context
  // like the Send to step's "Send to anyone", which the long press keeps:
  // see [kuteBarAskContext]); a page view builds its page after the
  // frame's cta, so the order on the stack says nothing.
  for (var i = stack.length - 2; i >= 0; i--) {
    final c = stack[i];
    if (c.route != top.route) break;
    if (c.isPrimary) return c;
  }
  return top;
}

/// What a long press on the bar's primary button asks Sal with: the
/// search context the same route declared (its recommended rows and
/// prompts), else the primary context itself.
KuteBarContext kuteBarAskContext(
    List<KuteBarContext> stack, KuteBarContext primary) {
  for (final c in stack.reversed) {
    if (c.route != primary.route) continue;
    if (!c.isPrimary && !c.hidden) return c;
  }
  return primary;
}

/// Holds [barContext] on the stack while mounted (see the file header),
/// bound to the route it is mounted in. With [active] false it holds
/// nothing and is only its child: a surface that declares a context some
/// of the time (a sheet that is short until the keyboard lifts it) keeps
/// the scope in place and toggles it, so its subtree is never re-parented
/// (a swap between "scope around the child" and "the child alone" rebuilt
/// the sheet from scratch: the focused field lost its focus and the
/// keyboard, and its text).
class KuteBarContextScope extends ConsumerStatefulWidget {
  const KuteBarContextScope(
      {super.key,
      required this.barContext,
      this.active = true,
      required this.child});

  final KuteBarContext barContext;
  final bool active;
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
    _push();
  }

  /// Puts the context on the stack, after this frame's build.
  void _push() {
    // Provider writes are illegal while the tree is building: the stack
    // is written in a microtask, after this frame's build (and before the
    // next tap can land; the bar reads the live stack on a tap).
    scheduleMicrotask(() {
      if (!mounted || !widget.active || _held != null) return;
      // A scope inside a surface built without a ProviderScope (a widget
      // test of a keypad or a sheet on its own) holds nothing: the bar
      // is not there either.
      final KuteBarContextStack stack;
      try {
        stack = ref.read(kuteBarContextProvider.notifier);
      } on StateError {
        return;
      }
      _route = ModalRoute.of(context);
      _stack = stack;
      _held = widget.barContext.boundTo(_route);
      _stack!.push(_held!);
    });
  }

  /// Takes the held context off the stack, after the frame.
  void _drop() {
    final held = _held;
    final stack = _stack;
    _held = null;
    if (held != null && stack != null) {
      // After the frame: the stack's listeners must not rebuild mid-tear-down.
      scheduleMicrotask(() => stack.remove(held));
    }
  }

  @override
  void didUpdateWidget(covariant KuteBarContextScope old) {
    super.didUpdateWidget(old);
    if (!widget.active) {
      _drop();
      return;
    }
    final held = _held;
    if (held == null) {
      // Turned on, or the first push is still pending (it reads the
      // widget when it runs).
      _push();
      return;
    }
    if (identical(old.barContext, widget.barContext)) return;
    scheduleMicrotask(() {
      if (!mounted || _held != held) return;
      _held = widget.barContext.boundTo(_route);
      _stack?.replace(held, _held!);
    });
  }

  @override
  void dispose() {
    _drop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ── Scroll clearance ─────────────────────────────────────────────────────

/// The bar's height plus 16 px: what a scroll view under the bar pads its
/// end by, INSIDE the scrollable (founder: "we have to be able to scroll,
/// it is paramount, so we can see and click what is under the bar"), so
/// the last rows scroll clear of the bar and can be tapped. Nothing is
/// reserved outside the scroll (no band under a sheet's content). A view
/// that runs to the screen's bottom edge adds the home-indicator inset
/// itself.
const double kuteBarScrollClearance = 72;

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
    // Its contexts go with it, counted or not (see KuteBarContextStack).
    scheduleMicrotask(() => KuteBarContextStack.instance?.removeRoute(route));
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
