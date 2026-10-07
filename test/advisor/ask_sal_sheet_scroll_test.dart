// The Ask Sal sheet scrolls under the finger: reading upwards is never
// snapped back to the bottom, the sheet does not dismiss on an inner
// scroll, and streaming growth is followed only from the bottom.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/advisor_context.dart';
import 'package:kute/models/advisor_model.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/screens/search/components/advisor_answer_surface.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/ask_sal_sheet.dart';
import 'package:kute/theme/app_theme.dart';

const _paragraph =
    'Funding is paid between long and short traders every hour so the '
    'perpetual price keeps tracking the spot price of the asset.';

AdvisorSessionState _state({int paragraphs = 30}) =>
    AdvisorSessionState(turns: [
      AdvisorTurn(
        query: 'How does funding work?',
        blocks: [
          AdvisorBlock(
              id: 'funding',
              kind: AdvisorBlockKind.answer,
              markdown: List.filled(paragraphs, _paragraph).join('\n\n')),
        ],
      ),
    ]);

class _LongSession extends AdvisorSessionNotifier {
  @override
  AdvisorSessionState build() => _state();
  @override
  void clear() => state = _state();

  /// More text arrives (as a streaming chunk would).
  void grow() => state = _state(paragraphs: 45);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<ProviderContainer> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late ProviderContainer container;
    await tester.pumpWidget(ProviderScope(
        overrides: [
          advisorSessionProvider.overrideWith(_LongSession.new),
          aiEnabledProvider.overrideWith((ref) async => true),
        ],
        child: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (_, __) => MaterialApp(
                localizationsDelegates:
                    AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                theme: buildLightTheme(),
                home: Scaffold(
                    body: Builder(
                  builder: (context) {
                    container =
                        ProviderScope.containerOf(context, listen: false);
                    return TextButton(
                        onPressed: () => showAskSalSheet(
                              context,
                              advisorContext:
                                  const AdvisorContext(surface: 'hl_order_slip'),
                            ),
                        child: const Text('Open Sal'));
                  },
                ))))));
    await tester.tap(find.text('Open Sal'));
    await tester.pumpAndSettle();
    return container;
  }

  Finder answerList() => find.descendant(
      of: find.byType(AdvisorAnswerSurface), matching: find.byType(Scrollable));

  ScrollPosition position(WidgetTester tester) =>
      tester.state<ScrollableState>(answerList()).position;

  testWidgets('a long answer scrolls under the finger and the sheet stays',
      (tester) async {
    await open(tester);
    final before = position(tester);
    expect(before.maxScrollExtent, greaterThan(300));
    // Opens at the bottom: the newest line in view.
    expect(before.pixels, before.maxScrollExtent);

    // A finger reading upwards over several frames, as on a phone.
    await tester.timedDrag(
        answerList(), const Offset(0, 250), const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    final after = position(tester);
    expect(after.pixels, lessThan(after.maxScrollExtent - 150),
        reason: 'the list must not snap back to the bottom');
    // The inner scroll never dismissed the sheet.
    expect(find.byType(AppBottomSheetContainer), findsOneWidget);
    expect(find.byType(AdvisorAnswerSurface), findsOneWidget);
  });

  testWidgets('growth is followed from the bottom and never while reading',
      (tester) async {
    final container = await open(tester);
    final session = container.read(advisorSessionProvider.notifier) as _LongSession;

    // At the bottom: more text keeps the newest line in view.
    session.grow();
    await tester.pumpAndSettle();
    var p = position(tester);
    expect(p.pixels, p.maxScrollExtent);

    // Reading upwards: more text leaves the reader where they are.
    session.clear();
    await tester.pumpAndSettle();
    await tester.timedDrag(
        answerList(), const Offset(0, 300), const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    final reading = position(tester).pixels;
    expect(reading, lessThan(position(tester).maxScrollExtent - 200));
    session.grow();
    await tester.pumpAndSettle();
    p = position(tester);
    expect(p.pixels, reading, reason: 'never yanked back while reading');
    expect(p.pixels, lessThan(p.maxScrollExtent));
  });
}
