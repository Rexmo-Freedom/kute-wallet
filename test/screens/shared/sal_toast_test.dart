// The Sal toast (sal_toast.dart): the one message from the top of the
// screen since 9 November 2026. What it shows per tone, how it comes and
// goes, the haptic, Reduce Motion, both themes, what VoiceOver reads, and
// the two doors to it (message_display.dart, sal_notices.dart).

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/screens/shared/kute_dog_scenes.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart'
    show KuteConfirmationTone, KuteStatusMark;
import 'package:kute/screens/shared/message_display.dart';
import 'package:kute/screens/shared/sal_notices.dart';
import 'package:kute/screens/shared/sal_reactions.dart';
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/screens/shared/sal_toast.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/theme/kute_bar_surface.dart';

const _toast = ValueKey('sal-toast');
const _message = ValueKey('sal-toast-message');
const _detail = ValueKey('sal-toast-detail');
const _mark = ValueKey('sal-toast-mark');
const _semantics = ValueKey('sal-toast-semantics');

/// The toast's own time plus its arrival (the clock starts as it lands).
const _arrive = Duration(milliseconds: 450);
const _leave = Duration(milliseconds: 300);

Widget _app({
  ThemeMode mode = ThemeMode.light,
  bool reduceMotion = false,
  required void Function(BuildContext context) onContext,
}) =>
    ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: buildLightTheme(),
        darkTheme: buildDarkTheme(),
        themeMode: mode,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        home: Scaffold(body: Builder(builder: (ctx) {
          onContext(ctx);
          return const SizedBox.expand();
        })),
      ),
    );

String _clip(WidgetTester tester) =>
    tester.widget<SalSprite>(find.byKey(const ValueKey('sal-toast-sal'))).clip;

KuteDogMood _mood(WidgetTester tester) => tester
    .widget<KuteDogConfirmation>(find.byKey(const ValueKey('sal-toast-rig')))
    .mood;

SalToast _shown(WidgetTester tester) =>
    tester.widget<SalToast>(find.byType(SalToast));

Color _fill(WidgetTester tester) =>
    (tester.widget<Container>(find.byKey(_toast)).decoration! as BoxDecoration)
        .color!;

Color _ink(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(_message)).style!.color!;

void main() {
  late int success;
  late int failure;
  late BuildContext page;

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    success = 0;
    failure = 0;
    SalToast.debugSuccessFeedbackOverride = () async => success++;
    SalToast.debugFailureFeedbackOverride = () async => failure++;
    SalReactions.debugReset();
  });
  tearDown(() {
    SalToast.debugReset();
    SalToast.debugSuccessFeedbackOverride = null;
    SalToast.debugFailureFeedbackOverride = null;
    SalReactions.debugReset();
  });

  Future<void> pumpApp(WidgetTester tester,
      {ThemeMode mode = ThemeMode.light, bool reduceMotion = false}) async {
    // No sprite sheets, set from inside the test's clock so the read
    // fails in fake time: Sal is the rig in the toast's mood.
    SalSpriteCache.debugSetManifest(null);
    addTearDown(SalSpriteCache.debugReset);
    await tester.pumpWidget(_app(
        mode: mode, reduceMotion: reduceMotion, onContext: (c) => page = c));
  }

  /// A leave started by a tap or a swipe through: the tick that starts
  /// it, then its length.
  Future<void> left(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(_leave);
  }

  /// Everything still running (a rig's loop) through, nothing thrown.
  Future<void> drain(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  testWidgets(
      'success: Sal happy, the check, the message and the second line; '
      'the success beat once; gone by itself after 2.5 s', (tester) async {
    await pumpApp(tester);
    SalToast.show(page,
        message: 'Prediction placed',
        detail: r'$5.00 on Yes',
        tone: SalToastTone.success);
    await tester.pump();
    await tester.pump(_arrive);

    expect(find.byKey(_toast), findsOneWidget);
    expect(find.text('Prediction placed'), findsOneWidget);
    expect(find.byKey(_detail), findsOneWidget);
    expect(find.text(r'$5.00 on Yes'), findsOneWidget);
    expect(_clip(tester), 'happy');
    expect(_mood(tester), KuteDogMood.happy);
    expect(tester.widget<KuteStatusMark>(find.byKey(_mark)).tone,
        KuteConfirmationTone.success);
    expect(success, 1);
    expect(failure, 0);

    // Still there at 2 s, gone a beat after 2.5 s.
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(_toast), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(_leave);
    expect(find.byKey(_toast), findsNothing);
    expect(success, 1);
    await drain(tester);
  });

  testWidgets(
      'failure: Sal sad, the "!", the failure tap once; stays 6 s',
      (tester) async {
    await pumpApp(tester);
    SalToast.show(page,
        message: "Couldn't place the prediction", tone: SalToastTone.failure);
    await tester.pump();
    await tester.pump(_arrive);

    expect(_clip(tester), 'sad');
    expect(_mood(tester), KuteDogMood.sad);
    expect(tester.widget<KuteStatusMark>(find.byKey(_mark)).tone,
        KuteConfirmationTone.failure);
    expect(failure, 1);
    expect(success, 0);

    await tester.pump(const Duration(seconds: 5));
    expect(find.byKey(_toast), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pump(_leave);
    expect(find.byKey(_toast), findsNothing);
    await drain(tester);
  });

  testWidgets('info: Sal blinks, no mark, no haptic; gone after 3 s',
      (tester) async {
    await pumpApp(tester);
    SalToast.show(page, message: 'Address copied', tone: SalToastTone.info);
    await tester.pump();
    await tester.pump(_arrive);

    expect(_clip(tester), 'blink');
    expect(_mood(tester), KuteDogMood.calm);
    expect(find.byKey(_mark), findsNothing);
    expect(find.byKey(_detail), findsNothing);
    expect(success, 0);
    expect(failure, 0);

    await tester.pump(const Duration(milliseconds: 2500));
    expect(find.byKey(_toast), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(_leave);
    expect(find.byKey(_toast), findsNothing);
    await drain(tester);
  });

  testWidgets('pending: Sal blinks, the clock, no haptic', (tester) async {
    await pumpApp(tester);
    SalToast.show(page, message: 'Order resting', tone: SalToastTone.pending);
    await tester.pump();
    await tester.pump(_arrive);

    expect(_clip(tester), 'blink');
    expect(tester.widget<KuteStatusMark>(find.byKey(_mark)).tone,
        KuteConfirmationTone.pending);
    expect(success, 0);
    expect(failure, 0);
    expect(_shown(tester).resolvedDuration, SalToast.infoDuration);
    await drain(tester);
  });

  testWidgets('one at a time: a new toast sends the one on screen off',
      (tester) async {
    await pumpApp(tester);
    SalToast.show(page, message: 'First', tone: SalToastTone.info);
    await tester.pump();
    await tester.pump(_arrive);
    expect(find.text('First'), findsOneWidget);

    SalToast.show(page, message: 'Second', tone: SalToastTone.info);
    await tester.pump();
    // Both on stage while the first leaves under the second's arrival.
    expect(find.text('First'), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);
    await tester.pump(_leave);
    expect(find.text('First'), findsNothing);
    expect(find.text('Second'), findsOneWidget);
    expect(find.byType(SalToast), findsOneWidget);
    expect(tester.takeException(), isNull);
    await drain(tester);
  });

  testWidgets('a tap runs the action and sends it off', (tester) async {
    await pumpApp(tester);
    var taps = 0;
    SalToast.show(page,
        message: 'Filled', tone: SalToastTone.success, onTap: () => taps++);
    await tester.pump();
    await tester.pump(_arrive);

    await tester.tap(find.byKey(_toast));
    expect(taps, 1);
    await left(tester);
    expect(find.byKey(_toast), findsNothing);
    await drain(tester);
  });

  testWidgets(
      'a sticky information toast with its X (the placing toast\'s shape): '
      'Sal and the words, no mark, no spinner, no action; it stays until '
      'closed, by the 44 pt X or a swipe up', (tester) async {
    await pumpApp(tester);
    var closed = 0;
    SalToast.show(page,
        message: 'Placing your prediction',
        detail: 'Will it rain?',
        tone: SalToastTone.info,
        sticky: true,
        closable: true,
        onClose: () => closed++);
    await tester.pump();
    await tester.pump(_arrive);
    expect(_clip(tester), 'blink');
    expect(find.byKey(_mark), findsNothing);
    expect(find.byType(KuteStatusMark), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byKey(const ValueKey('sal-toast-action')), findsNothing);
    final x = find.byKey(const ValueKey('sal-toast-close'));
    expect(x, findsOneWidget);
    expect(tester.getSize(x), const Size(44, 44));
    expect(success + failure, 0);
    // Past every tone's own time: still there.
    await tester.pump(const Duration(seconds: 10));
    expect(find.byKey(_toast), findsOneWidget);
    await tester.tap(x);
    await left(tester);
    expect(find.byKey(_toast), findsNothing);
    expect(closed, 1);

    SalToast.show(page,
        message: 'Placing your investment',
        tone: SalToastTone.info,
        sticky: true,
        closable: true);
    await tester.pump();
    await tester.pump(_arrive);
    await tester.drag(find.byKey(_toast), const Offset(0, -80));
    await left(tester);
    expect(find.byKey(_toast), findsNothing);
    await drain(tester);
  });

  testWidgets('a swipe up sends it off; a swipe down springs back',
      (tester) async {
    await pumpApp(tester);
    SalToast.show(page, message: 'Note', tone: SalToastTone.failure);
    await tester.pump();
    await tester.pump(_arrive);

    await tester.drag(find.byKey(_toast), const Offset(0, 40));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byKey(_toast), findsOneWidget);

    await tester.drag(find.byKey(_toast), const Offset(0, -80));
    await left(tester);
    expect(find.byKey(_toast), findsNothing);
    await drain(tester);
  });

  testWidgets(
      'Reduce Motion: at rest on the first frame, the mark final, the '
      'haptic still plays, gone at once', (tester) async {
    await pumpApp(tester, reduceMotion: true);
    SalToast.show(page,
        message: 'Prediction placed', tone: SalToastTone.success);
    await tester.pump();

    expect(find.byKey(_toast), findsOneWidget);
    final fade = tester.widget<FadeTransition>(find.ancestor(
        of: find.byKey(_semantics), matching: find.byType(FadeTransition)));
    expect(fade.opacity.value, 1.0);
    final shift = tester.widget<Transform>(find
        .ancestor(of: find.byKey(_semantics), matching: find.byType(Transform))
        .first);
    expect(shift.transform.getTranslation().y, 0);
    expect(tester.widget<KuteStatusMark>(find.byKey(_mark)).reduceMotion,
        isTrue);
    expect(success, 1);

    await tester.pump(SalToast.successDuration);
    await tester.pump();
    expect(find.byKey(_toast), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('light: the dark pill with white words (the Sal pill\'s)',
      (tester) async {
    await pumpApp(tester);
    SalToast.show(page,
        message: 'Prediction placed',
        detail: 'Will it rain?',
        tone: SalToastTone.success);
    await tester.pump();
    await tester.pump(_arrive);

    final light = buildLightTheme().extension<AppColorsExtension>()!;
    expect(_fill(tester), light.textPrimary);
    expect(_ink(tester), KuteBarSurface.ink);
    expect(tester.widget<Text>(find.byKey(_detail)).style!.color,
        KuteBarSurface.quietInk);
    await drain(tester);
  });

  testWidgets('dark: the white pill with near-black words', (tester) async {
    await pumpApp(tester, mode: ThemeMode.dark);
    SalToast.show(page,
        message: 'Prediction placed',
        detail: 'Will it rain?',
        tone: SalToastTone.success);
    await tester.pump();
    await tester.pump(_arrive);

    expect(_fill(tester), KuteBarSurface.whiteFill);
    expect(_ink(tester), KuteBarSurface.inkOnWhite);
    expect(tester.widget<Text>(find.byKey(_detail)).style!.color,
        KuteBarSurface.quietInkOnWhite);
    await drain(tester);
  });

  testWidgets(
      'VoiceOver: one live region reading the message and the second '
      'line, a tap and a dismiss; Sal and the mark say nothing',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pumpApp(tester);
    SalToast.show(page,
        message: 'Prediction placed',
        detail: r'$5.00 on Yes',
        tone: SalToastTone.success,
        onTap: () {});
    await tester.pump();
    await tester.pump(_arrive);

    expect(
      tester.getSemantics(find.byKey(_semantics)),
      matchesSemantics(
        label: r'Prediction placed. $5.00 on Yes',
        isLiveRegion: true,
        isButton: true,
        hasTapAction: true,
        hasDismissAction: true,
      ),
    );
    // Nothing else of the toast is read: the one node carries it all.
    expect(
        find.descendant(
            of: find.byKey(_semantics), matching: find.byType(Semantics)),
        findsNothing);
    await drain(tester);
    handle.dispose();
  });

  testWidgets(
      'showMessageSnackBar: error is a failure (the bar\'s Sal shakes), '
      'info is information, plain is a success; the default time is the '
      'tone\'s, an own time is honoured', (tester) async {
    await pumpApp(tester);

    showMessageSnackBar(context: page, message: 'Failed', error: true);
    await tester.pump();
    expect(_shown(tester).tone, SalToastTone.failure);
    expect(_shown(tester).resolvedDuration, SalToast.failureDuration);
    expect(SalReactions.current.value?.reaction, SalReaction.shakeNo);
    expect(failure, 1);

    showMessageSnackBar(
        context: page, message: 'Note', error: false, info: true);
    await tester.pump();
    await tester.pump(_leave);
    expect(_shown(tester).tone, SalToastTone.info);
    expect(_shown(tester).resolvedDuration, SalToast.infoDuration);

    showMessageSnackBar(context: page, message: 'Saved', error: false);
    await tester.pump();
    await tester.pump(_leave);
    expect(_shown(tester).tone, SalToastTone.success);
    expect(_shown(tester).resolvedDuration, SalToast.successDuration);
    expect(success, 1);

    showMessageSnackBar(
        context: page,
        message: 'Copied',
        error: false,
        duration: const Duration(seconds: 1));
    await tester.pump();
    await tester.pump(_leave);
    expect(_shown(tester).resolvedDuration, const Duration(seconds: 1));

    showMessageSnackBarInfo(context: page, message: 'Heads up');
    await tester.pump();
    await tester.pump(_leave);
    expect(_shown(tester).tone, SalToastTone.info);
    expect(_shown(tester).resolvedDuration, SalToast.infoDuration);
    expect(find.text('Heads up'), findsOneWidget);
    await drain(tester);
  });

  testWidgets(
      'showMessageBanner: the accent says the tone, the tap is kept, no '
      'haptic of its own', (tester) async {
    await pumpApp(tester);
    var opened = 0;
    showMessageBanner(
        context: page,
        message: 'BTC filled',
        icon: Icons.check_circle_rounded,
        accentColor: AppColors.success,
        onTap: () => opened++);
    await tester.pump();
    await tester.pump(_arrive);
    expect(_shown(tester).tone, SalToastTone.success);
    expect(_shown(tester).haptic, isFalse);
    expect(success, 0);
    await tester.tap(find.byKey(_toast));
    expect(opened, 1);
    await left(tester);
    expect(find.byKey(_toast), findsNothing);

    showMessageBanner(
        context: page,
        message: 'Liquidation risk',
        icon: Icons.warning_rounded,
        accentColor: AppColors.error);
    await tester.pump();
    expect(_shown(tester).tone, SalToastTone.failure);
    expect(failure, 0);
    await drain(tester);
  });

  testWidgets('SalNotices: placed, failed and pending in their tones',
      (tester) async {
    await pumpApp(tester);

    SalNotices.placed(page, message: 'Prediction placed', detail: 'Yes');
    await tester.pump();
    expect(_shown(tester).tone, SalToastTone.success);
    expect(_shown(tester).detail, 'Yes');
    expect(success, 1);

    SalNotices.failed(page, message: "Couldn't place it");
    await tester.pump();
    await tester.pump(_leave);
    expect(_shown(tester).tone, SalToastTone.failure);
    expect(SalReactions.current.value?.reaction, SalReaction.shakeNo);
    expect(failure, 1);

    var taps = 0;
    SalNotices.pending(page, message: 'Order resting', onTap: () => taps++);
    await tester.pump();
    await tester.pump(_leave);
    expect(_shown(tester).tone, SalToastTone.pending);
    await tester.pump(_arrive);
    await tester.tap(find.byKey(_toast));
    expect(taps, 1);
    await drain(tester);
  });

  testWidgets('SalToast.dismiss sends the one on screen off',
      (tester) async {
    await pumpApp(tester);
    SalToast.show(page, message: 'Leaving', tone: SalToastTone.failure);
    await tester.pump();
    await tester.pump(_arrive);
    SalToast.dismiss();
    await left(tester);
    expect(find.byKey(_toast), findsNothing);
    await drain(tester);
  });
}
