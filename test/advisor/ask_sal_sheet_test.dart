import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/advisor_model.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/hyperliquid_watchlist_provider.dart';
import 'package:kute/screens/shared/kute_dog_scenes.dart'
    show KuteDogGlance, SalAiRing;
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/ask_sal_chip.dart';
import 'package:kute/screens/shared/ask_sal_sheet.dart';
import 'package:kute/screens/shared/components/kute_list_row.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/kute_composer.dart';
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/services/advisor/advisor_service.dart';
import 'package:kute/services/advisor/advisor_input_guard.dart';
import 'package:kute/services/advisor/sal_chip_catalogue.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';


/// No stars: the watchlist box is never opened in a test.
class _NoStars extends HlWatchlistNotifier {
  @override
  List<String> build() => const [];
}

const _answer = AdvisorSessionState(turns: [
  AdvisorTurn(query: 'What is a limit order?', blocks: [
    AdvisorBlock(
        id: 'limit',
        kind: AdvisorBlockKind.answer,
        markdown: 'A limit order specifies a price.',
        actions: [
          AdvisorActionButton(
              label: 'Switch to limit order', actionId: 'switch_to_limit'),
        ]),
  ]),
]);

class _FollowupSession extends AdvisorSessionNotifier {
  _FollowupSession(this.asked);
  final List<(String, String)> asked;
  @override
  AdvisorSessionState build() => const AdvisorSessionState(turns: [
        AdvisorTurn(
            query: 'How does funding work?',
            blocks: [
              AdvisorBlock(
                  id: 'funding',
                  kind: AdvisorBlockKind.answer,
                  markdown: 'Funding is paid every hour.'),
            ]),
      ]);
  @override
  Future<void> ask(String query,
      {AdvisorContext? context,
      String input = 'typed',
      String? template,
      int? chipIndex,
      String? locale}) async {
    asked.add((query, input));
  }
}

class _ReadySession extends AdvisorSessionNotifier {
  @override
  AdvisorSessionState build() => _answer;
  @override
  void clear() => state = _answer;
}

/// A phone's frame: the sheet's rows and the composer at their real size,
/// so nothing an assertion looks for scrolls out of view.
void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    OpenOnce.reset();
  });

  Future<void> open(WidgetTester tester, void Function() applied,
      {bool supportsAction = true}) async {
    _phone(tester);
    await tester.pumpWidget(ProviderScope(
        overrides: [
          advisorSessionProvider.overrideWith(_ReadySession.new),
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
                  builder: (context) => TextButton(
                      onPressed: () => showAskSalSheet(
                            context,
                            advisorContext:
                                const AdvisorContext(surface: 'hl_order_slip'),
                            fullChat: true,
                            localActions: supportsAction
                                ? const {'switch_to_limit'}
                                : const {},
                            onLocalAction: (_) {
                              applied();
                              return true;
                            },
                          ),
                      child: const Text('Open Sal')),
                ))))));
    await tester.tap(find.text('Open Sal'));
    await tester.pumpAndSettle();
  }

  testWidgets('slip change requires confirmation and applies only once',
      (tester) async {
    var calls = 0;
    await open(tester, () => calls++);
    await tester.tap(find.text('Switch to limit order'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    await tester.tap(find.text('Switch to limit order'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('Chat with Sal'), findsNothing);
  });

  testWidgets('unsupported slip action cannot reach origin callback',
      (tester) async {
    var calls = 0;
    await open(tester, () => calls++, supportsAction: false);
    await tester.tap(find.text('Switch to limit order'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.text('Confirm'), findsNothing);
    expect(find.text('That control is not available on this screen.'),
        findsOneWidget);
    // The app's toast (not a Material snackbar) leaves after its 4 s.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
  });

  testWidgets('an answer has no next-question rows',
      (tester) async {
    final asked = <(String, String)>[];
    _phone(tester);
    await tester.pumpWidget(ProviderScope(
        overrides: [
          advisorSessionProvider.overrideWith(() => _FollowupSession(asked)),
          aiEnabledProvider.overrideWith((ref) async => true),
        ],
        child: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (_, __) => MaterialApp(
                localizationsDelegates:
                    AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                theme: buildLightTheme(),
                home: const Scaffold(
                    body: SalChatPanel(
                        advisorContext: AdvisorContext(surface: 'chat')))))));
    await tester.pumpAndSettle();
    // Plain answer text: no Material outlined or text buttons in the answer.
    expect(find.text('Funding is paid every hour.'), findsOneWidget);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.byIcon(Icons.north_east_rounded), findsNothing);
    // There is no "Ask Sal next" label or row of any kind under the answer.
    expect(find.text('How is funding paid?'), findsNothing);
    expect(find.text('Ask Sal next'), findsNothing);
    expect(find.byType(KuteListRow), findsNothing);
    // A follow-up is typed in the composer and reports typed.
    expect(find.byType(KuteComposer), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'How is funding paid?');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    expect(asked, [('How is funding paid?', 'typed')]);
    // One disclaimer, under the answers.
    expect(find.text('Factual AI information. Not investment advice.'),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('market prompts render immediately and only a tap asks AI',
      (tester) async {
    const first = AdvisorContext(
        surface: 'hl_order_slip',
        marketVenue: 'hyperliquid',
        marketId: 'xyz:XYZ100',
        orderType: 'stop_market');
    const second = AdvisorContext(
        surface: 'bet_slip',
        marketVenue: 'polymarket',
        marketId: 'chelsea-brentford',
        submarketId: '4237425');
    var selected = first;
    late StateSetter changeSelection;
    final requests = <AdvisorContext?>[];
    final prompts = <AdvisorPrompt?>[];
    final locales = <String?>[];
    final en = lookupAppLocalizations(const Locale('en'));
    String firstChip(AdvisorContext c) =>
        SalChipCatalogue.select(c, en).first.text;
    await tester.runAsync(() => AdvisorInputGuard.isSafe('Public question'));
    _phone(tester);
    await tester.pumpWidget(ProviderScope(
        overrides: [
          aiEnabledProvider.overrideWith((ref) async => true),
          advisorStreamRequestProvider.overrideWithValue((
              {required query,
              context,
              history = const [],
              required cancellation,
              locale,
              prompt}) {
            requests.add(context);
            prompts.add(prompt);
            locales.add(locale);
            return Stream.value(
                const AdvisorStreamEvent.done(AdvisorResponse(blocks: [
              AdvisorBlock(
                  id: 'answer',
                  kind: AdvisorBlockKind.answer,
                  markdown: 'The written rules determine resolution.')
            ])));
          }),
        ],
        child: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (_, __) => MaterialApp(
                localizationsDelegates:
                    AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                theme: buildLightTheme(),
                home: Scaffold(body: StatefulBuilder(builder: (_, setState) {
                  changeSelection = setState;
                  return SalChatPanel(
                      advisorContext: selected, fullChat: false);
                }))))));
    // Suggestions exist on the first frame, before any asynchronous work.
    expect(find.text(firstChip(first)), findsOneWidget);
    expect(requests, isEmpty);
    await tester.pumpAndSettle();
    expect(requests, isEmpty);
    changeSelection(() => selected = second);
    await tester.pump();
    expect(find.text(firstChip(second)), findsOneWidget);
    expect(find.text(firstChip(first)), findsNothing);
    expect(requests, isEmpty);
    await tester.pumpAndSettle();
    // The cached privacy dictionary was loaded in the real async zone. Let its
    // continuations finish before pumping the response into the widget tree.
    await tester.tap(find.text(firstChip(second)));
    await tester.runAsync(() async {});
    await tester.pumpAndSettle();
    expect(requests, [second]);
    expect(prompts.single?.source, 'chip');
    expect(prompts.single?.template,
        SalChipCatalogue.select(second, en).first.template);
    expect(locales, ['en']);
    expect(find.textContaining('The written rules determine resolution.'),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  Widget host(WidgetTester tester, Widget child,
      {required List<Override> overrides}) {
    _phone(tester);
    return ProviderScope(
          overrides: overrides,
          child: ScreenUtilInit(
              designSize: const Size(390, 844),
              builder: (_, __) => MaterialApp(
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  theme: buildLightTheme(),
                  home: Scaffold(body: child))));
  }

  /// Sal on, no stars, and every question answered at once with one next
  /// question of the answer's own.
  List<Override> answering(
          List<AdvisorContext?> requests, List<AdvisorPrompt?> prompts) =>
      [
        aiEnabledProvider.overrideWith((ref) async => true),
        hlWatchlistProvider.overrideWith(_NoStars.new),
        advisorStreamRequestProvider.overrideWithValue((
            {required query,
            context,
            history = const [],
            required cancellation,
            locale,
            prompt}) {
          requests.add(context);
          prompts.add(prompt);
          return Stream.value(const AdvisorStreamEvent.done(AdvisorResponse(
              blocks: [
                AdvisorBlock(
                    id: 'answer',
                    kind: AdvisorBlockKind.answer,
                    markdown: 'Bitcoin moved on the rate decision.')
              ])));
        }),
      ];

  List<(String, Map<String, Object>?)> observeEvents() {
    final events = <(String, Map<String, Object>?)>[];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    addTearDown(() => TrackingService.debugTrackObserver = null);
    return events;
  }

  testWidgets('the composer is there from the start, under the question rows',
      (tester) async {
    const slip = AdvisorContext(
        surface: 'hl_order_slip',
        marketVenue: 'hyperliquid',
        marketId: 'BTC',
        marketDisplayName: 'BTC');
    final en = lookupAppLocalizations(const Locale('en'));
    final chips = SalChipCatalogue.select(slip, en);
    final requests = <AdvisorContext?>[];
    final prompts = <AdvisorPrompt?>[];
    final events = observeEvents();
    await tester.runAsync(() => AdvisorInputGuard.isSafe('Public question'));
    await tester.pumpWidget(host(tester,
        const SalChatPanel(advisorContext: slip, fullChat: false),
        overrides: answering(requests, prompts)));
    await tester.pumpAndSettle();
    // Opened: a chat. The questions and the note scroll above the
    // composer, which is pinned at the bottom from the first frame.
    expect(find.byType(KuteComposer), findsOneWidget);
    expect(find.byType(SalSuggestionButton), findsNWidgets(chips.length));
    expect(find.text('Factual AI information. Not investment advice.'),
        findsOneWidget);
    final composer = tester.getRect(find.byType(KuteComposer));
    for (final row in find.byType(SalSuggestionButton).evaluate()) {
      expect(tester.getRect(find.byWidget(row.widget)).bottom,
          lessThanOrEqualTo(composer.top));
    }

    await tester.tap(find.text(chips[1].text));
    await tester.runAsync(() async {});
    await tester.pumpAndSettle();
    expect(requests, [slip]);
    expect(prompts.single?.template, chips[1].template);
    final asked = events.firstWhere((e) => e.$1 == 'sal_question_asked').$2!;
    expect(asked['input'], 'suggested');
    expect(asked['chip_index'], 1);
    // The answer and the composer for follow-ups; nothing under the answer:
    // neither the answer's own next question nor the other opening ones.
    expect(find.textContaining('Bitcoin moved on the rate decision.'),
        findsOneWidget);
    expect(find.byType(KuteComposer), findsOneWidget);
    expect(find.byType(SalSuggestionButton), findsNothing);
    expect(find.text('What happens next?'), findsNothing);
    expect(find.text('Ask Sal next'), findsNothing);
    for (final chip in [chips[0], ...chips.skip(2)]) {
      expect(find.text(chip.text), findsNothing);
    }
    expect(find.byType(KuteListRow), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the round dog button opens Sal idle with the question rows',
      (tester) async {
    const slip = AdvisorContext(surface: 'hl_order_slip');
    final en = lookupAppLocalizations(const Locale('en'));
    final chips = SalChipCatalogue.select(slip, en);
    final events = observeEvents();
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(host(tester, const AskSalChip(advisorContext: slip),
        overrides: [
          aiEnabledProvider.overrideWith((ref) async => true),
          hlWatchlistProvider.overrideWith(_NoStars.new),
        ]));
    await tester.pumpAndSettle();
    // The dog alone in the circled header button, named for the reader.
    expect(find.byType(KuteCircleButton), findsOneWidget);
    expect(find.byType(KuteDogGlance), findsOneWidget);
    expect(find.text('Ask Sal'), findsNothing);
    expect(find.bySemanticsLabel('Ask Sal'), findsOneWidget);
    // Inside Sal's AI mark, which paints only: the circle keeps its size.
    expect(find.byType(SalAiRing), findsOneWidget);
    expect(tester.getSize(find.byType(SalAiRing)),
        tester.getSize(find.byType(KuteCircleButton)));

    await tester.tap(find.byType(KuteCircleButton));
    await tester.pumpAndSettle();
    expect(find.text('Ask Sal'), findsOneWidget);
    expect(find.byType(SalSuggestionButton), findsNWidgets(chips.length));
    expect(find.byType(KuteComposer), findsOneWidget);
    final opened = events.firstWhere((e) => e.$1 == 'sal_opened').$2!;
    expect(opened['entry'], 'chip');
    expect(opened['surface'], 'hl_order_slip');
    semantics.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  /// The idle sheet from a button, on a phone with a status bar.
  Future<void> openIdle(WidgetTester tester) async {
    tester.view.padding = const FakeViewPadding(top: 47);
    addTearDown(() => tester.view.resetPadding());
    await tester.pumpWidget(host(
        tester,
        Builder(
            builder: (context) => TextButton(
                onPressed: () => showAskSalSheet(context,
                    advisorContext: const AdvisorContext(surface: 'hl_order_slip'),
                    fullChat: true),
                child: const Text('Open Sal'))),
        overrides: [
          aiEnabledProvider.overrideWith((ref) async => true),
          hlWatchlistProvider.overrideWith(_NoStars.new),
        ]));
    await tester.tap(find.text('Open Sal'));
  }

  bool composerFocused(WidgetTester tester) => tester
      .widget<EditableText>(find.descendant(
          of: find.byType(KuteComposer), matching: find.byType(EditableText)))
      .focusNode
      .hasFocus;

  testWidgets('the sheet opens at the screen\'s full height under the status '
      'bar, the composer pinned under the question rows while idle',
      (tester) async {
    const slip = AdvisorContext(surface: 'hl_order_slip');
    final en = lookupAppLocalizations(const Locale('en'));
    final chips = SalChipCatalogue.select(slip, en);
    await openIdle(tester);
    await tester.pumpAndSettle();
    // The whole screen below the status bar: the drag handle and the
    // shared header at the top, the composer at the bottom baseline.
    final sheet = tester.getRect(find.byType(AppBottomSheetContainer));
    expect(sheet.top, moreOrLessEquals(47));
    expect(sheet.bottom, moreOrLessEquals(844));
    expect(find.text('Chat with Sal'), findsOneWidget);
    expect(find.byType(AppBottomSheetCloseButton), findsOneWidget);
    expect(find.byType(SalSuggestionButton), findsNWidgets(chips.length));
    final composer = tester.getRect(find.byType(KuteComposer));
    expect(composer.bottom, moreOrLessEquals(844 - 16, epsilon: 1));
    expect(tester.getRect(find.byType(SalSuggestionButton).last).bottom,
        lessThan(composer.top));
    // Idle: the composer has the focus, for the keyboard.
    expect(composerFocused(tester), isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the composer takes focus only once the sheet has slid in',
      (tester) async {
    await openIdle(tester);
    await tester.pump();
    // Mid-slide (the sheet takes 250 ms): on screen, not focused.
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(KuteComposer), findsOneWidget);
    expect(composerFocused(tester), isFalse);
    await tester.pump(const Duration(milliseconds: 100));
    expect(composerFocused(tester), isFalse);
    // Settled: focused.
    await tester.pumpAndSettle();
    expect(composerFocused(tester), isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('opened with a question it asks it at once and leaves the '
      'keyboard down', (tester) async {
    const btc = AdvisorContext(
        surface: 'hl_market_detail',
        marketVenue: 'hyperliquid',
        marketId: 'BTC',
        marketDisplayName: 'BTC');
    final en = lookupAppLocalizations(const Locale('en'));
    final top = SalChipCatalogue.select(btc, en).first;
    final requests = <AdvisorContext?>[];
    final prompts = <AdvisorPrompt?>[];
    final events = observeEvents();
    await tester.runAsync(() => AdvisorInputGuard.isSafe('Public question'));
    await tester.pumpWidget(host(
        tester,
        Builder(
            builder: (context) => TextButton(
                onPressed: () => showAskSalSheet(context,
                    advisorContext: btc,
                    initialQuestion: top,
                    entry: 'header_button'),
                child: const Text('Open Sal'))),
        overrides: answering(requests, prompts)));
    await tester.tap(find.text('Open Sal'));
    await tester.pump();
    await tester.runAsync(() async {});
    await tester.pumpAndSettle();
    expect(requests, [btc]);
    expect(prompts.single?.template, top.template);
    final asked = events.firstWhere((e) => e.$1 == 'sal_question_asked').$2!;
    expect(asked['input'], 'suggested');
    expect(asked['chip_index'], 0);
    expect(find.text(top.text), findsOneWidget);
    expect(find.byType(SalSuggestionButton), findsNothing);
    expect(find.byType(KuteComposer), findsOneWidget);
    expect(composerFocused(tester), isFalse);
    expect(tester.getRect(find.byType(AppBottomSheetContainer)).top,
        moreOrLessEquals(0));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
