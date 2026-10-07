import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/theme/app_theme.dart';

const _checkKey = ValueKey('kute-confirmation-check');

Widget _app({
  required Widget home,
  ThemeMode mode = ThemeMode.light,
  bool reduceMotion = false,
  double textScale = 1.0,
}) {
  return ScreenUtilInit(
    designSize: const Size(430, 932),
    builder: (_, __) => MaterialApp(
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: mode,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
            disableAnimations: reduceMotion,
            textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: home,
    ),
  );
}

Finder _markPaint() => find.descendant(
    of: find.byType(KuteCheckMark), matching: find.byType(CustomPaint));

double _messageOpacity(WidgetTester tester, String message) => tester
    .widget<FadeTransition>(find
        .ancestor(of: find.text(message), matching: find.byType(FadeTransition))
        .first)
    .opacity
    .value;

void main() {
  late int haptics;

  setUp(() {
    haptics = 0;
    KuteConfirmation.debugFeedbackOverride = () async => haptics++;
  });
  tearDown(() => KuteConfirmation.debugFeedbackOverride = null);

  void useSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('check is centered and the message sits near the bottom',
      (tester) async {
    useSurface(tester);
    await tester.pumpWidget(_app(
      home: KuteConfirmation(
        message: 'Position sold',
        detail: 'Routing to your Bitcoin wallet…',
        onDone: () {},
      ),
    ));
    await tester.pumpAndSettle();

    final check = tester.getRect(find.byKey(_checkKey));
    final message = tester.getRect(find.text('Position sold'));
    final detail = tester.getRect(find.text('Routing to your Bitcoin wallet…'));
    final button = tester.getRect(find.byType(AppButton));

    expect(check.center.dx, closeTo(215, 0.5));
    expect(message.center.dx, closeTo(215, 0.5));
    expect(message.top, greaterThan(check.bottom));
    expect(message.center.dy, greaterThan(932 * 0.6));
    expect(detail.top, greaterThanOrEqualTo(message.bottom));
    expect(detail.bottom, lessThanOrEqualTo(button.top));
    expect(find.text('Done'), findsOneWidget);
    expect(find.byType(KuteCheckMark), findsOneWidget);
  });

  testWidgets(
      'plays once under 1.2 s and the haptic fires once when the stroke completes',
      (tester) async {
    await tester.pumpWidget(_app(
      home: KuteConfirmation(message: 'Order filled', onDone: () {}),
    ));
    await tester.pump();
    expect(_messageOpacity(tester, 'Order filled'), 0);

    await tester.pump(const Duration(milliseconds: 540));
    expect(haptics, 0);
    expect(_messageOpacity(tester, 'Order filled'), 0);

    await tester.pump(const Duration(milliseconds: 60));
    expect(haptics, 1);

    // The ring is expanding: ring plus disc.
    await tester.pump(const Duration(milliseconds: 150));
    expect(_markPaint(), paintsExactlyCountTimes(#drawCircle, 2));

    await tester.pump(const Duration(milliseconds: 450));
    // The check has finished; Sal keeps cheering beside it for a few
    // seconds by design, so the page as a whole settles below.
    expect(_messageOpacity(tester, 'Order filled'), 1);
    // The ring is gone; the disc and check remain.
    expect(_markPaint(), paintsExactlyCountTimes(#drawCircle, 1));
    expect(
      _markPaint(),
      paints
        ..circle(color: AppColors.marketUp)
        ..path(color: Colors.white),
    );

    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
    expect(haptics, 1);
  });

  testWidgets('reduced motion shows the final check at once with no ring',
      (tester) async {
    await tester.pumpWidget(_app(
      reduceMotion: true,
      home: KuteConfirmation(message: 'Bitcoin sent', onDone: () {}),
    ));
    await tester.pump();

    expect(tester.hasRunningAnimations, isFalse);
    expect(_messageOpacity(tester, 'Bitcoin sent'), 1);
    expect(tester.widget<KuteCheckMark>(find.byType(KuteCheckMark)).reduceMotion,
        isTrue);
    expect(_markPaint(), paintsExactlyCountTimes(#drawCircle, 1));
    expect(
      _markPaint(),
      paints
        ..circle(color: AppColors.marketUp)
        ..path(color: Colors.white),
    );
    expect(haptics, 1);

    await tester.pumpAndSettle();
    expect(haptics, 1);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('uses the app background and text colors in ${mode.name} theme',
        (tester) async {
      await tester.pumpWidget(_app(
        mode: mode,
        home: KuteConfirmation(message: 'Prediction placed', onDone: () {}),
      ));
      await tester.pumpAndSettle();

      final element = tester.element(find.byType(KuteConfirmation));
      final colors = element.colors;
      expect(Theme.of(element).brightness,
          mode == ThemeMode.dark ? Brightness.dark : Brightness.light);
      expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
          colors.background);
      // Dark mode is the flat charcoal background, not pure black.
      expect(colors.background,
          mode == ThemeMode.dark ? const Color(0xFF1D2024) : const Color(0xFFFFFFFF));
      expect(tester.widget<Text>(find.text('Prediction placed')).style?.color,
          colors.textPrimary);
    });
  }

  testWidgets('waits for the route fade before the check pops',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        navigatorKey: navKey,
        theme: buildLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(),
      ),
    ));
    pushKuteSuccessOverlay(
      navigator: navKey.currentState!,
      overlay: KuteConfirmation(message: 'Position sold', onDone: () {}),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    // Route still fading in: nothing drawn yet, no haptic.
    expect(_markPaint(), paintsExactlyCountTimes(#drawCircle, 0));
    expect(haptics, 0);

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 700));
    expect(haptics, 1);
    await tester.pumpAndSettle();
    expect(haptics, 1);
    expect(_messageOpacity(tester, 'Position sold'), 1);
  });

  testWidgets('Done runs the caller navigation', (tester) async {
    var done = 0;
    await tester.pumpWidget(_app(
      home: KuteConfirmation(message: 'Prediction placed', onDone: () => done++),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AppButton));
    await tester.pump();
    expect(done, 1);
  });

  testWidgets(
      'a failure with a long detail and receipt wraps and scrolls on a '
      'small screen with large text, nothing clipped', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    const detail = 'Nicht genug Guthaben, um den Betrag plus die '
        'Netzwerkgebühr zu decken. Verringere den Betrag oder tippe auf '
        '100 %, um alles zu senden.';
    final receipt = List.filled(
            12,
            'LNURL error: the recipient service answered with a long '
            'message about routing and limits.')
        .join(' ');
    await tester.pumpWidget(_app(
      reduceMotion: true,
      textScale: 1.3,
      home: KuteConfirmation(
        success: false,
        message: 'Zahlung nicht gesendet',
        detail: detail,
        receipt: Text(receipt, key: const ValueKey('receipt')),
        buttonText: 'Erneut versuchen',
        onDone: () {},
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // The detail wraps in full: no line limit, nothing ellipsized.
    final detailFinder = find.text(detail);
    expect(tester.widget<Text>(detailFinder).maxLines, isNull);
    expect(tester.renderObject<RenderParagraph>(detailFinder).didExceedMaxLines,
        isFalse);
    expect(
        tester
            .renderObject<RenderParagraph>(find.byKey(const ValueKey('receipt')))
            .didExceedMaxLines,
        isFalse);

    // More than fits: the page scrolls, and the button stays on screen.
    final scrollable = find.byType(Scrollable);
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, greaterThan(0));
    final button = tester.getRect(find.byType(AppButton));
    expect(button.bottom, lessThanOrEqualTo(568));

    // Scrolled to the end, the message and its whole detail sit above the
    // button, inside the screen.
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    final message = tester.getRect(find.text('Zahlung nicht gesendet'));
    final detailRect = tester.getRect(detailFinder);
    expect(message.top, greaterThanOrEqualTo(0));
    expect(detailRect.top, greaterThanOrEqualTo(message.bottom));
    expect(detailRect.bottom, lessThanOrEqualTo(button.top));
    expect(tester.getRect(find.byType(AppButton)), button);

    // Scrolled back up, the receipt's start is reachable too.
    position.jumpTo(0);
    await tester.pumpAndSettle();
    expect(
        tester.getRect(find.byKey(const ValueKey('receipt'))).top,
        greaterThanOrEqualTo(0));
    expect(tester.takeException(), isNull);
  });
}
