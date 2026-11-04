import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/models/advisor_context.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/screens/search/components/advisor_answer_surface.dart';
import 'package:kute/screens/shared/kute_composer.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/services/advisor/action_dispatcher.dart';
import 'package:kute/services/advisor/advisor_capability_manifest.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// `sal_closed`: once per Sal conversation (a search that became one),
/// read before the conversation is cancelled. Counts and booleans only,
/// never question or answer text. [entry] matches `sal_opened`'s entry
/// (search; legacy: chip, market_why_moving, full_chat, header_button,
/// market_capsule, position_capsule, insight_row, market_row).
void trackSalClosed(
  AdvisorSessionState session, {
  required String entry,
  String? surface,
}) {
  final turns = session.turns.length;
  TrackingService.track('sal_closed', params: {
    'entry': entry,
    if (surface != null) 'surface': surface,
    'turns': turns == 0
        ? '0'
        : turns == 1
            ? '1'
            : turns <= 3
                ? '2-3'
                : '4+',
    // includeInHistory is only set on a real answer (never on a failure,
    // a private-input notice or an interrupted turn).
    'had_answer': session.turns.any((t) => !t.loading && t.includeInHistory),
    'closed_while_loading': session.turns.any((t) => t.loading),
  });
}

/// Sal's conversation inside the search / Sal sheet (THE one way into Sal
/// is the bar, kute_bar_context.dart): the answers, scrolling, and the
/// composer pinned under them. No next-question rows under an answer: a
/// follow-up is typed. The host (the search sheet) draws the sheet and
/// its header; [advisorContext] is the conversation's public context (a
/// receipt's or a market's, from the bar), carried by every follow-up.
class SalChatPanel extends ConsumerStatefulWidget {
  final AdvisorContext advisorContext;
  const SalChatPanel({super.key, required this.advisorContext});

  @override
  ConsumerState<SalChatPanel> createState() => _SalChatPanelState();
}

class _SalChatPanelState extends ConsumerState<SalChatPanel> {
  final _composer = TextEditingController();
  final _composerFocus = FocusNode();
  var _contextGeneration = 0;

  @override
  void didUpdateWidget(covariant SalChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.advisorContext == widget.advisorContext) return;
    final generation = ++_contextGeneration;
    _composer.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _contextGeneration) return;
      ref.read(advisorSessionProvider.notifier).clear();
    });
  }

  @override
  void dispose() {
    _composer.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  void _ask(String question) {
    // A question sent while Sal is still answering interrupts that answer:
    // the notifier's ask() cancels the running turn (it keeps what was
    // streamed, marked stopped) and starts this one.
    if (question.trim().isEmpty) return;
    HapticFeedback.lightImpact();
    _composer.clear();
    FocusScope.of(context).unfocus();
    ref.read(advisorSessionProvider.notifier).ask(question,
        context: widget.advisorContext,
        locale: Localizations.localeOf(context).languageCode);
  }

  Future<void> _action(String id, Map<String, dynamic> params) async {
    // A slip's own controls (switch to limit, leverage) belong to the
    // slip: nothing here can change them.
    if (id == 'switch_to_limit' || id == 'open_leverage_settings') {
      TrackingService.salActionResult(action: id, result: 'unavailable');
      showMessageSnackBarInfo(
          context: context, message: context.l10n.salControlUnavailable);
      return;
    }
    if (!AdvisorCapabilityManifest.validParams(id, params)) {
      TrackingService.salActionResult(
          action: AdvisorActionDispatcher.analyticsAction(id),
          result: 'unavailable');
      return;
    }
    final container = ProviderScope.containerOf(context, listen: false);
    if (id == 'open_hl_market' || id == 'open_market_by_slug') {
      await AdvisorActionDispatcher.dispatch(context, container, id, params);
      return;
    }
    final navigator = Navigator.of(context, rootNavigator: true);
    final rootContext = navigator.context;
    navigator.pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (rootContext.mounted) {
        AdvisorActionDispatcher.dispatch(rootContext, container, id, params);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final session = ref.watch(advisorSessionProvider);
    final currentSession =
        session.context == null || session.context == widget.advisorContext;
    final loading = currentSession && session.turns.any((t) => t.loading);
    final enabled = ref.watch(aiEnabledProvider).asData?.value != false;
    return Column(
      children: [
        Expanded(
          child: enabled
              // The answers, with the one quiet disclaimer under them.
              ? AdvisorAnswerSurface(onAction: _action)
              : Center(
                  child: Text(context.l10n.salUnavailable,
                      style: TextStyle(
                          color: colors.textSecondary, fontSize: 15.sp)),
                ),
        ),
        // The composer, pinned under the conversation. It stays open while
        // an answer streams, so the next question can be typed and sent
        // without waiting (that send stops the running answer).
        SizedBox(height: 8.h),
        KuteComposer(
          controller: _composer,
          focusNode: _composerFocus,
          enabled: enabled,
          loading: loading,
          maxLength: 2000,
          hint: context.l10n.salAskQuestionHint,
          sendLabel: context.l10n.salSendQuestion,
          stopLabel: context.l10n.salStopResponse,
          onSubmit: () => _ask(_composer.text),
          onStop: !enabled
              ? null
              : () {
                  HapticFeedback.lightImpact();
                  ref.read(advisorSessionProvider.notifier).cancel();
                },
        ),
      ],
    );
  }
}
