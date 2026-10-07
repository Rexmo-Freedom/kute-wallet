import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/models/advisor_context.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/sal_chip_signals.dart';
import 'package:kute/screens/search/components/advisor_answer_surface.dart';
import 'package:kute/screens/shared/after_route_transition.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/components/kute_list_row.dart';
import 'package:kute/screens/shared/kute_composer.dart';
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/screens/usd/flow/usd_flow_widgets.dart' show UsdFlowNote;
import 'package:kute/services/advisor/action_dispatcher.dart';
import 'package:kute/services/advisor/advisor_capability_manifest.dart';
import 'package:kute/services/advisor/sal_chip_catalogue.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

/// `sal_closed`: once per Sal open (the Ask Sal sheet, or a search that
/// became a Sal conversation), read before the conversation is cancelled.
/// Counts and booleans only, never question or answer text.
/// [entry] matches `sal_opened`'s entry: chip | header_button |
/// market_capsule | position_capsule | full_chat | search (insight_row before
/// the market rows became the header button, market_row before the
/// Investing row became the market capsule).
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

/// A public-context conversation above the originating screen. All slip state
/// remains owned by that screen; Sal only returns a supported control name.
/// [chipSignals] are the public market facts the screen already shows; they
/// only choose the opening questions and never leave the device.
/// [initialQuestion] (a market or position screen's question capsule)
/// opens the sheet already asking that question, the screen's first: no
/// idle state, the answer streams at once and the composer takes
/// follow-ups. [entry] overrides the `sal_opened` entry ('market_capsule'
/// or 'position_capsule' from those screens); by default it is full_chat
/// or chip.
Future<void> showAskSalSheet(
  BuildContext context, {
  required AdvisorContext advisorContext,
  SalChipSignals chipSignals = const SalChipSignals(),
  Set<String> localActions = const {},
  bool Function(String actionId)? onLocalAction,
  bool fullChat = false,
  SalChip? initialQuestion,
  String? entry,
  bool? expanded,
}) async {
  entry ??= fullChat ? 'full_chat' : 'chip';
  TrackingService.salOpened(
      entry: entry, surface: advisorContext.surface, expanded: expanded);
  final container = ProviderScope.containerOf(context, listen: false);
  final session = container.read(advisorSessionProvider.notifier);
  session.clear();
  try {
    if (context.mounted) {
      // The app's sheet at its full height: the shared container and
      // header, the default modal slide, and the keyboard followed frame
      // by frame.
      // Opened from the root navigator's context so the sheet takes the
      // app's own theme: a modal copies the opener's themes, and an
      // order or bet slip tints its subtree green or red.
      final result = await showAppBottomSheet<String>(
        context: Navigator.of(context, rootNavigator: true).context,
        builder: (_) => SalChatPanel(
          advisorContext: advisorContext,
          chipSignals: chipSignals,
          fullChat: fullChat,
          localActions: onLocalAction == null ? const {} : localActions,
          initialQuestion: initialQuestion,
        ),
      );
      if (result != null && localActions.contains(result)) {
        final applied = onLocalAction?.call(result) ?? false;
        TrackingService.salActionResult(
          action: result,
          result: !applied
              ? 'unavailable'
              : result == 'switch_to_limit'
                  ? 'applied'
                  : 'opened',
        );
        if (!applied && context.mounted) {
          showMessageSnackBarInfo(
              context: context,
              message: context.l10n.salOrderNoLongerAvailable);
        }
      }
    }
  } finally {
    trackSalClosed(
      container.read(advisorSessionProvider),
      entry: entry,
      surface: advisorContext.surface,
    );
    session.cancel();
  }
}

/// Sal's conversation as a chat: the composer pinned at the bottom from
/// the first frame, and above it the opening questions (at most four)
/// while Sal is idle, then the answers, scrolling. No next-question rows
/// under an answer: a follow-up is typed.
///
/// On its own it is the Ask Sal sheet: the shared container at the
/// screen's full height under the status bar, with the drag handle and
/// the shared header. Idle, the composer takes focus once the sheet has
/// slid in (never mid-slide). With [embedded] it is only the content, for
/// a host that already draws the sheet (the search sheet, once a search
/// becomes a conversation). [initialQuestion] is asked as soon as the
/// panel opens (a market's top question): the opening rows are skipped
/// and the answer streams at once.
class SalChatPanel extends ConsumerStatefulWidget {
  final AdvisorContext advisorContext;
  final SalChipSignals chipSignals;
  final bool fullChat;
  final Set<String> localActions;
  final bool embedded;
  final SalChip? initialQuestion;
  const SalChatPanel({
    super.key,
    required this.advisorContext,
    this.chipSignals = const SalChipSignals(),
    this.fullChat = true,
    this.localActions = const {},
    this.embedded = false,
    this.initialQuestion,
  });

  @override
  ConsumerState<SalChatPanel> createState() => _AskSalSheetState();
}

class _AskSalSheetState extends ConsumerState<SalChatPanel> {
  final _composer = TextEditingController();
  final _composerFocus = FocusNode();
  VoidCallback? _cancelFocus;
  (AdvisorContext, SalChipSignals, Locale)? _chipsKey;
  List<SalChip> _chipsMemo = const [];
  bool _confirming = false;
  bool _openingAsked = false;
  var _contextGeneration = 0;

  @override
  void initState() {
    super.initState();
    // Idle in its own sheet: the composer takes focus, but only once the
    // sheet's slide has finished (afterRouteTransition). Opened with a
    // question, the answer streams and nothing asks for the keyboard.
    if (widget.embedded || widget.initialQuestion != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _cancelFocus = requestFocusAfterTransition(context, _composerFocus);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The market's top question, asked once as the sheet opens (here, not
    // in initState: the question is sent in the screen's language).
    final question = widget.initialQuestion;
    if (question == null || _openingAsked) return;
    _openingAsked = true;
    _ask(question.text,
        input: 'suggested',
        template: question.template,
        chipIndex: 0,
        haptic: false);
  }

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
    _cancelFocus?.call();
    _composer.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  /// The opening questions, chosen once per context and language so a
  /// rebuild never reorders them under the person's finger.
  List<SalChip> _chips(BuildContext context) {
    final key = (
      widget.advisorContext,
      widget.chipSignals,
      Localizations.localeOf(context)
    );
    if (_chipsKey case final last?
        when last.$1 == key.$1 &&
            identical(last.$2, key.$2) &&
            last.$3 == key.$3) {
      return _chipsMemo;
    }
    _chipsKey = key;
    final signals = withLocalSalSignals(
      ProviderScope.containerOf(context, listen: false),
      widget.advisorContext,
      widget.chipSignals,
    );
    return _chipsMemo = SalChipCatalogue.select(
        widget.advisorContext, context.l10n,
        signals: signals);
  }

  void _ask(String question,
      {String input = 'typed',
      String? template,
      int? chipIndex,
      bool haptic = true}) {
    final session = ref.read(advisorSessionProvider);
    if (question.trim().isEmpty ||
        ((session.context == null ||
                session.context == widget.advisorContext) &&
            session.turns.any((t) => t.loading))) {
      return;
    }
    if (haptic) HapticFeedback.lightImpact();
    _composer.clear();
    FocusScope.of(context).unfocus();
    ref.read(advisorSessionProvider.notifier).ask(question,
        context: widget.advisorContext,
        input: input,
        template: template,
        chipIndex: chipIndex,
        locale: Localizations.localeOf(context).languageCode);
  }

  Future<void> _action(String id, Map<String, dynamic> params) async {
    if (id == 'switch_to_limit' || id == 'open_leverage_settings') {
      if (params.isNotEmpty ||
          !widget.localActions.contains(id) ||
          _confirming) {
        TrackingService.salActionResult(action: id, result: 'unavailable');
        showMessageSnackBarInfo(
            context: context, message: context.l10n.salControlUnavailable);
        return;
      }
      _confirming = true;
      final isLimit = id == 'switch_to_limit';
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            isLimit
                ? ctx.l10n.salSwitchToLimitTitle
                : ctx.l10n.salOpenLeverageTitle,
          ),
          content: Text(
            isLimit
                ? ctx.l10n.salSwitchToLimitBody
                : ctx.l10n.salOpenLeverageBody,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ctx.l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ctx.l10n.confirm),
            ),
          ],
        ),
      );
      _confirming = false;
      if (confirmed != true) {
        // Declined at the confirmation step: the control stays untouched.
        TrackingService.salActionResult(action: id, result: 'cancelled');
      }
      if (confirmed == true && mounted) Navigator.pop(context, id);
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
    final active = currentSession && session.isActive;
    final loading = currentSession && session.turns.any((t) => t.loading);
    final enabled = ref.watch(aiEnabledProvider).asData?.value != false;
    final Widget body;
    if (!enabled) {
      body = Center(
        child: Text(context.l10n.salUnavailable,
            style: TextStyle(color: colors.textSecondary, fontSize: 15.sp)),
      );
    } else if (!active && widget.initialQuestion == null) {
      body = ListView(
        padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 16.h),
        children: [
          KuteListGroup(children: [
            // At most four opening questions (kSalMaxChips).
            for (final (index, chip)
                in _chips(context).take(kSalMaxChips).indexed)
              SalSuggestionButton(
                text: chip.text,
                onPressed: () => _ask(chip.text,
                    input: 'suggested',
                    template: chip.template,
                    chipIndex: index),
              ),
          ]),
          SizedBox(height: 24.h),
          UsdFlowNote(lines: [context.l10n.salDisclaimer]),
        ],
      );
    } else {
      // Opened with a question: the answer surface from the first frame
      // (the question lands on it as soon as it is sent), never the rows.
      // No next-question rows under an answer: follow-ups are typed.
      body = AdvisorAnswerSurface(onAction: _action);
    }
    final content = Column(
      children: [
        if (!widget.embedded)
          AppBottomSheetHeader(
            title: widget.fullChat
                ? context.l10n.salChatWith
                : context.l10n.salAsk,
            subtitle: SalChipCatalogue.introduction(
                widget.advisorContext, context.l10n),
            trailing: const AppBottomSheetCloseButton(),
          ),
        Expanded(child: body),
        // The composer, pinned under the conversation from the start: a
        // chat, whether Sal is idle with its opening questions or
        // answering.
        SizedBox(height: 8.h),
        KuteComposer(
          controller: _composer,
          focusNode: _composerFocus,
          enabled: enabled && !loading,
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
    if (widget.embedded) return content;
    // The whole screen under the status bar (showAppBottomSheet's safe
    // area), as the app's full-height sheets: the conversation needs the
    // room, and the sheet stops growing under the keyboard instead of
    // jumping in height.
    return AppBottomSheetContainer(
      maxHeight: 1.0,
      followKeyboard: true,
      child: content,
    );
  }
}

/// One opening question: a Settings row in the questions' grouped card,
/// with the Kute dog and the chevron. The search sheet's idle questions use
/// this same row.
class SalSuggestionButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  const SalSuggestionButton(
      {super.key, required this.text, required this.onPressed});

  @override
  Widget build(BuildContext context) => KuteListRow(
        title: text,
        glyph: const SalDogGlyph(),
        selectionHaptic: true,
        onTap: onPressed,
      );
}
