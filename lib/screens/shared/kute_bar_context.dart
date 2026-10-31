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

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
        hidden = true;

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

  bool get hasRecommendations => actions.isNotEmpty;
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

/// Holds [barContext] on the stack while mounted (see the file header).
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

  @override
  void initState() {
    super.initState();
    // Provider writes are illegal while the tree is building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _stack = ref.read(kuteBarContextProvider.notifier);
      _held = widget.barContext;
      _stack!.push(_held!);
    });
  }

  @override
  void didUpdateWidget(covariant KuteBarContextScope old) {
    super.didUpdateWidget(old);
    final held = _held;
    if (held == null || identical(held, widget.barContext)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _held != held) return;
      _held = widget.barContext;
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
