// Sal's conversation inside the search / Sal sheet (sal_chat_panel.dart):
// the one Sal surface since the Ask Sal sheet went (founder, 1 November
// 2026). Answers with no next-question rows and one quiet disclaimer, a
// slip's controls never changed from here, and a follow-up typed while
// Sal is still answering.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/advisor_context.dart';
import 'package:kute/models/advisor_model.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/screens/search/components/sal_chat_panel.dart';
import 'package:kute/screens/shared/components/kute_list_row.dart';
import 'package:kute/screens/shared/kute_composer.dart';
import 'package:kute/services/advisor/advisor_input_guard.dart';
import 'package:kute/services/advisor/advisor_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

class _FollowupSession extends AdvisorSessionNotifier {
  _FollowupSession(this.asked);
  final List<(String, String, AdvisorContext?)> asked;
  @override
  AdvisorSessionState build() => const AdvisorSessionState(turns: [
        AdvisorTurn(query: 'How does funding work?', blocks: [
          AdvisorBlock(
              id: 'funding',
              kind: AdvisorBlockKind.answer,
              markdown: 'Funding is paid every hour.',
              actions: [
                AdvisorActionButton(
                    label: 'Switch to limit order',
                    actionId: 'switch_to_limit'),
              ]),
        ]),
      ]);
  @override
  Future<void> ask(String query,
      {AdvisorContext? context,
      String input = 'typed',
      String? template,
      int? chipIndex,
      String? locale}) async {
    asked.add((query, input, context));
  }
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _host(WidgetTester tester, Widget child,
    {required List<Override> overrides}) {
  _phone(tester);
  return ProviderScope(
      overrides: overrides,
      child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, __) => MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: buildLightTheme(),
              home: Scaffold(body: child))));
}

List<(String, Map<String, Object>?)> _observeEvents() {
  final events = <(String, Map<String, Object>?)>[];
  TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  addTearDown(() => TrackingService.debugTrackObserver = null);
  return events;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  const receipt = AdvisorContext(surface: 'btc_tx_detail');

  testWidgets('an answer has no next-question rows; a follow-up is typed '
      'with the conversation\'s context; one disclaimer', (tester) async {
    final asked = <(String, String, AdvisorContext?)>[];
    await tester.pumpWidget(_host(
        tester, const SalChatPanel(advisorContext: receipt),
        overrides: [
          advisorSessionProvider.overrideWith(() => _FollowupSession(asked)),
          aiEnabledProvider.overrideWith((ref) async => true),
        ]));
    await tester.pumpAndSettle();
    expect(find.text('Funding is paid every hour.'), findsOneWidget);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.text('Ask Sal next'), findsNothing);
    expect(find.byType(KuteListRow), findsNothing);
    expect(find.byType(KuteComposer), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'How is funding paid?');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    expect(asked, [('How is funding paid?', 'typed', receipt)]);
    expect(find.text('Factual AI information. Not investment advice.'),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a slip control in an answer is never applied from here',
      (tester) async {
    final events = _observeEvents();
    await tester.pumpWidget(_host(
        tester, const SalChatPanel(advisorContext: receipt),
        overrides: [
          advisorSessionProvider.overrideWith(() => _FollowupSession([])),
          aiEnabledProvider.overrideWith((ref) async => true),
        ]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Switch to limit order'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm'), findsNothing);
    expect(find.text('That control is not available on this screen.'),
        findsOneWidget);
    final result = events.firstWhere((e) => e.$1 == 'sal_action_result').$2!;
    expect(result['result'], 'unavailable');
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the next question can be typed and sent while Sal is still '
      'answering; the send stops that answer and starts the new one',
      (tester) async {
    const slip = AdvisorContext(
        surface: 'hl_market_detail',
        marketVenue: 'hyperliquid',
        marketId: 'BTC',
        marketDisplayName: 'BTC');
    final streams = <StreamController<AdvisorStreamEvent>>[];
    final cancellations = <AdvisorCancellation>[];
    final queries = <String>[];
    final events = _observeEvents();
    await tester.runAsync(() => AdvisorInputGuard.isSafe('Public question'));
    await tester.pumpWidget(_host(
        tester, const SalChatPanel(advisorContext: slip),
        overrides: [
          aiEnabledProvider.overrideWith((ref) async => true),
          advisorStreamRequestProvider.overrideWithValue((
              {required query,
              context,
              history = const [],
              required cancellation,
              locale,
              prompt}) {
            final controller = StreamController<AdvisorStreamEvent>();
            streams.add(controller);
            cancellations.add(cancellation);
            queries.add(query);
            return controller.stream;
          }),
        ]));
    await tester.pumpAndSettle();

    // The first question streams and stays mid-answer.
    await tester.enterText(find.byType(TextField), 'How does funding work?');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.runAsync(() async {});
    await tester.pump();
    expect(streams, hasLength(1));
    streams[0].add(const AdvisorStreamEvent.delta('Funding is paid'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Funding is paid'), findsOneWidget);

    // Still answering: the field is open and the circle is the stop square.
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enabled, isTrue);
    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'And what about fees?');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.runAsync(() async {});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // The first request is cancelled, the second has started.
    expect(cancellations[0].isCancelled, isTrue);
    expect(queries, ['How does funding work?', 'And what about fees?']);
    expect(find.textContaining('Response stopped before completion.'),
        findsOneWidget);
    final asked = [
      for (final (name, params) in events)
        if (name == 'sal_question_asked') params!
    ];
    expect(asked, hasLength(2));
    expect(asked[1]['interrupted'], isTrue);

    streams[1].add(const AdvisorStreamEvent.done(AdvisorResponse(blocks: [
      AdvisorBlock(
          id: 'fees',
          kind: AdvisorBlockKind.answer,
          markdown: 'Fees are shown before you confirm.')
    ])));
    unawaited(streams[1].close());
    await tester.pumpAndSettle();
    expect(find.textContaining('Fees are shown before you confirm.'),
        findsOneWidget);
    expect(find.byIcon(Icons.stop_rounded), findsNothing);
    expect(tester.takeException(), isNull);
    unawaited(streams[0].close());
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
