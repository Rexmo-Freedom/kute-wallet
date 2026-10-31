// lib/screens/home/components/kute_shell_bar.dart
//
// The bar over everything (founder, 31 October 2026; see
// kute_bar_context.dart): drawn once, above the root navigator (the
// MaterialApp builder's Stack, app_widget.dart), so it sits over pushed
// pages, modal barriers and sheets. It shows the topmost
// [KuteBarContext] on the stack; with none (Home, Dollars draw their own
// pill in their dock) it is away. A hidden context or the keyboard slides
// it down ([KuteMotion.sheetOut]); it springs back when they go. Tapping
// it opens the Sal sheet with that context (showKuteSearch).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/app_router.dart' show AppRouter;
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/screens/home/components/kute_bottom_action_bar.dart'
    show KuteSalPill;
import 'package:kute/screens/search/unified_search_screen.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/kute_motion.dart' show kuteReduceMotion;
import 'package:kute/theme/kute_motion.dart';

class KuteShellBar extends ConsumerStatefulWidget {
  const KuteShellBar({super.key});

  @override
  ConsumerState<KuteShellBar> createState() => _KuteShellBarState();
}

class _KuteShellBarState extends ConsumerState<KuteShellBar> {
  /// The last context shown, kept while the bar slides away.
  KuteBarContext? _last;

  void _open(KuteBarContext ctx) {
    final navContext = AppRouter.rootNavigatorKey.currentContext;
    if (navContext == null) return;
    HapticFeedback.lightImpact();
    // ignore: discarded_futures
    showKuteSearch(
      navContext,
      initialCategory: ctx.category,
      searchFirst: true,
      searchHint: ctx.searchHint,
      source: ctx.source,
      barContext: ctx,
    );
  }

  @override
  Widget build(BuildContext context) {
    final top = kuteBarTop(ref.watch(kuteBarContextProvider));
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final show = top != null && !top.hidden && !keyboard;
    if (top != null && !top.hidden) _last = top;
    final ctx = _last;
    if (ctx == null) return const SizedBox.shrink();
    final reduce = kuteReduceMotion(context);
    final aiEnabled = ref.watch(aiEnabledProvider).valueOrNull ?? true;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: IgnorePointer(
        ignoring: !show,
        child: AnimatedSlide(
          offset: show ? Offset.zero : const Offset(0, 1.4),
          duration: reduce
              ? Duration.zero
              : (show ? KuteMotion.sheetInDuration : KuteMotion.sheetOutDuration),
          curve: show ? KuteMotion.sheetIn : KuteMotion.sheetOut,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(12.w, 0, 12.w, 2.h),
              child: Center(
                child: KuteSalPill(
                  label: ctx.label,
                  sublabel: ctx.sublabel,
                  clip: ctx.clip,
                  aiEnabled: aiEnabled,
                  onTap: () => _open(ctx),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
