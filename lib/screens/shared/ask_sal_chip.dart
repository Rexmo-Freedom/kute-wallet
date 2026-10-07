
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/advisor_context.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/sal_chip_signals.dart' show withLocalSalSignals;
import 'package:kute/screens/shared/after_route_transition.dart';
import 'package:kute/screens/shared/ask_sal_sheet.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/kute_dog_scenes.dart'
    show KuteDogGlance, SalAiRing;
import 'package:kute/screens/shared/kute_motion.dart';
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/services/advisor/sal_chip_catalogue.dart';
import 'package:kute/theme/app_theme.dart';

export 'package:kute/models/advisor_context.dart';
export 'package:kute/providers/sal_chip_signals.dart'
    show salSignalsForHlMarket, salSignalsForPolyEvent;
export 'package:kute/services/advisor/sal_chip_catalogue.dart'
    show SalChipSignals;

/// The one soft sweep across the question capsule's words once the
/// screen has slid in.
const Duration kSalShimmer = Duration(milliseconds: 900);

/// Sal's AI mark hues: the chart palette's violet, cyan and pink.
List<Color> salAiHues(AppColorsExtension c) => [
      c.chartCategorical[0],
      c.chartCategorical[1],
      c.chartCategorical[4],
    ];

/// Opens Sal with public questions about this screen (the slips, send
/// review, transaction details, backup): the Kute dog alone in the app's
/// circled header button (the close X's own chassis), glancing now and
/// then ([KuteDogGlance]), inside Sal's AI mark, a thin gradient ring and
/// a sparkle that twinkles on the same idle beat ([SalAiRing]). Size, tap
/// target and label are the circle's own. [chipSignals] are the public
/// market facts the screen shows; they choose and order the opening
/// questions on the device and are never sent. A tap opens Sal idle with
/// the questions and reports `sal_opened {entry: 'chip'}`.
class AskSalChip extends ConsumerWidget {
  final AdvisorContext advisorContext;
  final SalChipSignals chipSignals;
  final bool Function(String actionId)? onLocalAction;
  final Set<String> localActions;

  const AskSalChip({
    super.key,
    required this.advisorContext,
    this.chipSignals = const SalChipSignals(),
    this.onLocalAction,
    this.localActions = const {},
  });

  /// This market's top-ranked opening question: the same choice the sheet
  /// makes from the same signals, so it is the sheet's first question.
  static SalChip? topQuestion(BuildContext context,
      AdvisorContext advisorContext, SalChipSignals chipSignals) {
    final signals = withLocalSalSignals(
      ProviderScope.containerOf(context, listen: false),
      advisorContext,
      chipSignals,
    );
    return SalChipCatalogue.select(advisorContext, context.l10n,
            signals: signals)
        .firstOrNull;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(aiEnabledProvider).asData?.value == false) {
      return const SizedBox.shrink();
    }
    return SalAiRing(
      key: const ValueKey('ask-sal-ai-ring'),
      hues: salAiHues(context.colors),
      child: KuteCircleButton(
        semanticsLabel: context.l10n.salAsk,
        // Once: a second tap while the sheet slides in does not stack
        // another.
        onPressed: () => OpenOnce.run(
            'sal-header:${advisorContext.surface}',
            () => showAskSalSheet(
                  context,
                  advisorContext: advisorContext,
                  chipSignals: chipSignals,
                  localActions: localActions,
                  onLocalAction: onLocalAction,
                )),
        child: KuteDogGlance(size: 24.sp),
      ),
    );
  }
}

/// A market or open-position screen's Sal question, under its headline
/// figure (the Predictions chance, the Investing price, the position's
/// value): the header pill's capsule
/// look (surface fill, hairline border, pill ends) at the content's full
/// width, the glancing dog at its leading edge, the market's top-ranked
/// opening question ([AskSalChip.topQuestion], the one the Sal sheet
/// lists first) in up to two lines, never cut on a phone, and a chevron.
/// Always open; one soft shimmer sweeps across the question once the
/// screen has finished sliding in (none under Reduce Motion).
///
/// A tap opens Sal already asking it and reports `sal_opened {entry:
/// [entry], surface}` ('market_capsule' or 'position_capsule'), then `sal_question_asked {input:
/// 'suggested', template, chip_index: 0}`. With Sal switched off, or no
/// question for the market, nothing is drawn (not even [padding]).
///
/// The question is chosen once per market and kept while the screen is
/// open, so a live price moving the signals never swaps the words under
/// the reader's eye.
class SalQuestionCapsule extends ConsumerStatefulWidget {
  final AdvisorContext advisorContext;
  final SalChipSignals chipSignals;

  /// Space around the capsule, only while it is drawn.
  final EdgeInsetsGeometry padding;

  /// The `sal_opened` entry: 'market_capsule' on a market screen,
  /// 'position_capsule' on an open-position screen.
  final String entry;

  const SalQuestionCapsule({
    super.key,
    required this.advisorContext,
    this.chipSignals = const SalChipSignals(),
    this.padding = EdgeInsets.zero,
    this.entry = 'market_capsule',
  });

  @override
  ConsumerState<SalQuestionCapsule> createState() =>
      _SalQuestionCapsuleState();
}

class _SalQuestionCapsuleState extends ConsumerState<SalQuestionCapsule>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer =
      AnimationController(vsync: this, duration: kSalShimmer);
  VoidCallback? _cancelOpen;
  SalChip? _question;
  String? _questionKey;

  String get _marketKey {
    final c = widget.advisorContext;
    return '${c.surface}:${c.marketVenue}:${c.marketId}:${c.submarketId ?? ''}';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _cancelOpen = afterRouteTransition(context, () {
        if (!mounted || _question == null || kuteReduceMotion(context)) {
          return;
        }
        _shimmer.forward(from: 0);
      });
    });
  }

  @override
  void dispose() {
    _cancelOpen?.call();
    _shimmer.dispose();
    super.dispose();
  }

  SalChip? _currentQuestion() {
    final key = _marketKey;
    if (_questionKey != key || _question == null) {
      _questionKey = key;
      _question = AskSalChip.topQuestion(
          context, widget.advisorContext, widget.chipSignals);
    }
    return _question;
  }

  void _onTap(SalChip question) {
    HapticFeedback.selectionClick();
    // Once: a second tap while the sheet slides in does not stack another.
    OpenOnce.run(
        'sal-capsule:${widget.advisorContext.surface}',
        () => showAskSalSheet(
              context,
              advisorContext: widget.advisorContext,
              chipSignals: widget.chipSignals,
              initialQuestion: question,
              entry: widget.entry,
            ));
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(aiEnabledProvider).asData?.value == false) {
      return const SizedBox.shrink();
    }
    final question = _currentQuestion();
    if (question == null) return const SizedBox.shrink();
    final c = context.colors;
    final style = TextStyle(
      color: c.textPrimary,
      fontSize: 14.sp,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
      height: 1.3,
    );
    return Padding(
      padding: widget.padding,
      child: Semantics(
        button: true,
        label: '${context.l10n.salAsk}, ${question.text}',
        excludeSemantics: true,
        child: Material(
          key: const ValueKey('sal-question-capsule'),
          color: c.surface,
          shape: StadiumBorder(
              side: BorderSide(color: c.borderSubtle, width: 0.5)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => _onTap(question),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: 48.w),
              child: Padding(
                padding: EdgeInsets.fromLTRB(8.w, 6.h, 10.w, 6.h),
                child: Row(children: [
                  // The round button's AI mark, quieter, around his face.
                  SalAiRing(
                    hues: salAiHues(c),
                    stroke: 1,
                    sparkle: 3.5,
                    opacity: 0.6,
                    child: SizedBox.square(
                      dimension: 32.sp,
                      child: Center(child: KuteDogGlance(size: 24.sp)),
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: AnimatedBuilder(
                      animation: _shimmer,
                      builder: (context, child) {
                        if (!_shimmer.isAnimating) return child!;
                        final x = -1.6 + 3.2 * _shimmer.value;
                        return ShaderMask(
                          blendMode: BlendMode.srcIn,
                          shaderCallback: (rect) => LinearGradient(
                            begin: Alignment(x - 0.5, 0),
                            end: Alignment(x + 0.5, 0),
                            colors: [
                              c.textPrimary,
                              c.textSecondary,
                              c.textPrimary
                            ],
                          ).createShader(rect),
                          child: child,
                        );
                      },
                      child: Text(
                        question.text,
                        key: const ValueKey('sal-question-capsule-text'),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: style,
                      ),
                    ),
                  ),
                  SizedBox(width: 6.w),
                  Icon(Icons.chevron_right_rounded,
                      color: c.textTertiary, size: 22.sp),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
