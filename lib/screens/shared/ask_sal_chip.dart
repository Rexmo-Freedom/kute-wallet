import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/advisor_context.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/screens/shared/ask_sal_sheet.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/kute_dog_scenes.dart' show KuteDogGlance;
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/services/advisor/sal_chip_catalogue.dart';
import 'package:kute/theme/app_theme.dart';

export 'package:kute/models/advisor_context.dart';
export 'package:kute/providers/sal_chip_signals.dart'
    show salSignalsForHlMarket, salSignalsForPolyEvent;
export 'package:kute/services/advisor/sal_chip_catalogue.dart'
    show SalChip, SalChipSignals, salWhyMovingHl, salWhyMovingPm;

/// The `sal_opened` entry (and `sal_question_asked`'s `entry_source`) of a
/// market screen's "Why is it moving?" row.
const kSalEntryMarketWhyMoving = 'market_why_moving';

/// Opens Sal with public questions about this screen (send review,
/// transaction details, backup; never an order or bet slip, the moment of
/// decision): the Kute dog alone in the app's circled header button (the
/// close X's own chassis), in the button's one icon colour, glancing now
/// and then ([KuteDogGlance]). Sal's multicolour AI mark lives inside the
/// Sal sheet only. Size, tap target and label are the circle's own.
/// [chipSignals] are the public market facts the screen shows; they choose
/// and order the opening questions on the device and are never sent. A tap
/// opens Sal idle with the questions and reports `sal_opened {entry:
/// 'chip'}`.
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(aiEnabledProvider).asData?.value == false) {
      return const SizedBox.shrink();
    }
    return KuteCircleButton(
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
      // The circle's own icon colour, like the close X beside it.
      child: KuteDogGlance(size: 24.sp, color: context.colors.textSecondary),
    );
  }
}

/// A market screen's one quiet Sal door: "Why is it moving?" as a plain
/// details row under the chart (the hairline above it, the row's title
/// style, a chevron), led by the dog as a small one-colour glyph in the
/// title's colour. Drawn only while there is something worth explaining:
/// [question] is that market's why-moving question ([salWhyMovingHl] or
/// [salWhyMovingPm]), null when the market is calm, and then nothing is
/// drawn at all (not even [padding]).
///
/// Once shown for a market it stays while the screen is open, so a live
/// price crossing back over the threshold never pulls the row from under
/// a finger. A tap opens Sal already asking [question] and reports
/// `sal_opened {entry: 'market_why_moving', surface}`, then
/// `sal_question_asked {input: 'suggested', template, chip_index: 0,
/// entry_source: 'market_why_moving'}`. Nothing with Sal switched off.
class SalWhyMovingRow extends ConsumerStatefulWidget {
  final AdvisorContext advisorContext;
  final SalChip? question;

  /// The public market facts, for the questions Sal offers after the first.
  final SalChipSignals chipSignals;

  /// Space around the row, only while it is drawn.
  final EdgeInsetsGeometry padding;

  const SalWhyMovingRow({
    super.key,
    required this.advisorContext,
    required this.question,
    this.chipSignals = const SalChipSignals(),
    this.padding = EdgeInsets.zero,
  });

  @override
  ConsumerState<SalWhyMovingRow> createState() => _SalWhyMovingRowState();
}

class _SalWhyMovingRowState extends ConsumerState<SalWhyMovingRow> {
  SalChip? _shown;
  String? _shownKey;

  String get _marketKey {
    final c = widget.advisorContext;
    return '${c.surface}:${c.marketVenue}:${c.marketId}:${c.submarketId ?? ''}';
  }

  SalChip? _current() {
    final key = _marketKey;
    if (_shownKey != key) {
      _shownKey = key;
      _shown = null;
    }
    return _shown ??= widget.question;
  }

  void _onTap(SalChip question) {
    HapticFeedback.selectionClick();
    // Once: a second tap while the sheet slides in does not stack another.
    OpenOnce.run(
        'sal-why-moving:${widget.advisorContext.surface}',
        () => showAskSalSheet(
              context,
              advisorContext: widget.advisorContext,
              chipSignals: widget.chipSignals,
              initialQuestion: question,
              entry: kSalEntryMarketWhyMoving,
            ));
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(aiEnabledProvider).asData?.value == false) {
      return const SizedBox.shrink();
    }
    final question = _current();
    if (question == null) return const SizedBox.shrink();
    final c = context.colors;
    final title = AppTextStyles.settingsTitle(context);
    return Padding(
      padding: widget.padding,
      child: Semantics(
        button: true,
        label: context.l10n.salWhyMoving,
        excludeSemantics: true,
        child: InkWell(
          key: const ValueKey('sal-why-moving-row'),
          onTap: () => _onTap(question),
          child: Container(
            padding: EdgeInsets.symmetric(vertical: 14.h),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: c.borderSubtle, width: 0.5),
              ),
            ),
            child: Row(
              children: [
                KuteDogGlance(
                  key: const ValueKey('sal-why-moving-glyph'),
                  size: 20.sp,
                  color: title.color,
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Text(
                    context.l10n.salWhyMoving,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: title,
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: c.textTertiary, size: 22.sp),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
