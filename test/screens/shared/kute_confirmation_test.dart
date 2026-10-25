import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_dog_rig.dart';
import 'package:kute/screens/shared/kute_dog_scenes.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/screens/shared/trade_receipt.dart';
import 'package:kute/theme/app_theme.dart';

const _scrimKey = ValueKey('kute-confirmation-scrim');

Widget _app({
  Widget? home,
  GlobalKey<NavigatorState>? navigatorKey,
  ThemeMode mode = ThemeMode.light,
  bool reduceMotion = false,
  double textScale = 1.0,
}) {
  return ScreenUtilInit(
    designSize: const Size(430, 932),
    builder: (_, __) => MaterialApp(
      navigatorKey: navigatorKey,
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
      home: home ?? const Scaffold(body: Text('host')),
    ),
  );
}

Finder _markPaint() => find.descendant(
    of: find.byType(KuteStatusMark), matching: find.byType(CustomPaint));

KuteStatusMark _mark(WidgetTester tester) =>
    tester.widget<KuteStatusMark>(find.byType(KuteStatusMark));

KuteDogConfirmation _sal(WidgetTester tester) =>
    tester.widget<KuteDogConfirmation>(find.byType(KuteDogConfirmation));

/// The sheet surface: the keyed, decorated container around the content.
Finder _sheet() => find
    .ancestor(
        of: find.byKey(const ValueKey('kute-confirmation-message')),
        matching: find.byWidgetPredicate((w) =>
            w is Container && w.decoration is BoxDecoration && w.key != null))
    .first;

void main() {
  late int haptics;
  late int failureHaptics;

  setUp(() {
    haptics = 0;
    failureHaptics = 0;
    KuteConfirmation.debugFeedbackOverride = () async => haptics++;
    KuteConfirmation.debugFailureFeedbackOverride =
        () async => failureHaptics++;
  });
  tearDown(() {
    KuteConfirmation.debugFeedbackOverride = null;
    KuteConfirmation.debugFailureFeedbackOverride = null;
  });

  void useSurface(WidgetTester tester, [Size size = const Size(430, 932)]) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets(
      'success: mark, title and Sal in one row, the amount as the hero, the '
      'context line, hairline rows and one quiet secondary button',
      (tester) async {
    useSurface(tester);
    var secondary = 0;
    await tester.pumpWidget(_app(
      home: KuteConfirmation(
        message: 'Prediction placed',
        amount: r'$5.00 on Yes',
        contextLine: 'Will it rain?',
        rows: const {'Shares': '8.33', 'Pays if right': r'$8.33'},
        secondaryButtonText: 'View prediction',
        onSecondary: () => secondary++,
        onDone: () {},
      ),
    ));
    await tester.pumpAndSettle();

    final mark = tester.getRect(find.byType(KuteStatusMark));
    final title = tester.getRect(find.text('Prediction placed'));
    final sal = tester.getRect(find.byType(KuteDogConfirmation));
    final amount = tester.getRect(find.text(r'$5.00 on Yes'));
    final context = tester.getRect(find.text('Will it rain?'));
    final shares = tester.getRect(find.text('Shares'));
    final done = tester.getRect(find.widgetWithText(AppButton, 'Done'));
    final view = tester.getRect(find.text('View prediction'));

    // Header row: mark, title, Sal on the right, vertically centred.
    expect(title.left, greaterThan(mark.right));
    expect(sal.left, greaterThan(title.right));
    expect(mark.center.dy, closeTo(sal.center.dy, 1));
    expect(sal.right, closeTo(410, 1));
    // Left aligned, top to bottom.
    expect(amount.left, closeTo(mark.left, 0.5));
    expect(context.left, closeTo(mark.left, 0.5));
    expect(amount.top, greaterThan(mark.bottom));
    expect(context.top, greaterThanOrEqualTo(amount.bottom));
    expect(shares.top, greaterThan(context.bottom));
    expect(done.top, greaterThan(shares.bottom));
    expect(view.top, greaterThan(done.bottom));
    // The amount is the largest text on the sheet.
    expect(tester.widget<Text>(find.text(r'$5.00 on Yes')).style!.fontSize,
        greaterThan(30));
    // Rows are hairline-divided, not boxed.
    expect(find.byType(Divider), findsNWidgets(2));
    // Fits its content: the sheet does not reach the top of the screen.
    expect(tester.getRect(_sheet()).top, greaterThan(932 * 0.3));
    // No close X; the secondary is a text button.
    expect(find.byIcon(Icons.close), findsNothing);
    expect(find.widgetWithText(AppTextButton, 'View prediction'),
        findsOneWidget);
    expect(find.widgetWithText(AppButton, 'View prediction'), findsNothing);

    await tester.tap(find.text('View prediction'));
    await tester.pump();
    expect(secondary, 1);
  });

  testWidgets(
      'the check lands under 1.2 s: the haptic fires once as the stroke '
      'completes and Sal wakes just before it', (tester) async {
    await tester.pumpWidget(_app(
      home: KuteConfirmation(message: 'Order filled', onDone: () {}),
    ));
    await tester.pump();
    expect(_sal(tester).awake, isFalse);
    expect(_sal(tester).mood, KuteDogMood.happy);

    await tester.pump(const Duration(milliseconds: 500));
    expect(_sal(tester).awake, isTrue);
    expect(haptics, 0);

    await tester.pump(const Duration(milliseconds: 100));
    expect(haptics, 1);

    // The ring is expanding: ring plus disc.
    await tester.pump(const Duration(milliseconds: 150));
    expect(_markPaint(), paintsExactlyCountTimes(#drawCircle, 2));

    await tester.pump(const Duration(milliseconds: 450));
    final colors = tester.element(find.byType(KuteStatusMark)).colors;
    expect(_markPaint(), paintsExactlyCountTimes(#drawCircle, 1));
    expect(
      _markPaint(),
      paints
        ..circle(color: colors.success)
        ..path(color: Colors.white),
    );
    expect(failureHaptics, 0);

    // Sal wags, idles and rests: the sheet settles.
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
    expect(haptics, 1);
  });

  testWidgets(
      'failure: red "!", Sal sad with no wag, the failure tap once and no '
      'success haptic', (tester) async {
    await tester.pumpWidget(_app(
      home: KuteConfirmation(
        tone: KuteConfirmationTone.failure,
        message: "Couldn't send",
        amount: '25,000 sats',
        detail: 'Nothing left your wallet.',
        buttonText: 'Try again',
        onDone: () {},
      ),
    ));
    await tester.pumpAndSettle();
    final colors = tester.element(find.byType(KuteStatusMark)).colors;
    expect(_mark(tester).tone, KuteConfirmationTone.failure);
    expect(_markPaint(), paints..circle(color: colors.error));
    expect(_sal(tester).mood, KuteDogMood.sad);
    expect(failureHaptics, 1);
    expect(haptics, 0);
    expect(find.text('25,000 sats'), findsOneWidget);
    expect(find.text('Nothing left your wallet.'), findsOneWidget);
    expect(find.widgetWithText(AppButton, 'Try again'), findsOneWidget);
    // The sad pose never swings the tail up the way the wag does.
    for (var ms = 0.0;
        ms < KuteDogConfirmation.totalMs(KuteDogMood.sad);
        ms += 50) {
      expect(KuteDogConfirmation.poseAt(KuteDogMood.sad, ms).tail,
          lessThanOrEqualTo(0));
    }
  });

  testWidgets('the legacy success: false is a failure', (tester) async {
    await tester.pumpWidget(_app(
      home: KuteConfirmation(
          message: 'Payment not sent', success: false, onDone: () {}),
    ));
    await tester.pumpAndSettle();
    expect(_mark(tester).tone, KuteConfirmationTone.failure);
  });

  testWidgets('pending: a neutral clock, Sal calm, no haptic', (tester) async {
    await tester.pumpWidget(_app(
      home: KuteConfirmation(
        tone: KuteConfirmationTone.pending,
        message: 'Order placed',
        amount: r'$10.00 on No',
        secondaryButtonText: 'View orders',
        onSecondary: () {},
        onDone: () {},
      ),
    ));
    await tester.pumpAndSettle();
    final colors = tester.element(find.byType(KuteStatusMark)).colors;
    expect(_markPaint(), paints..circle(color: colors.surfaceElevated));
    expect(_sal(tester).mood, KuteDogMood.calm);
    expect(haptics, 0);
    expect(failureHaptics, 0);
  });

  testWidgets('celebrate: the gold token, Sal cheers, the success haptic',
      (tester) async {
    await tester.pumpWidget(_app(
      home: KuteConfirmation(
          message: 'Winnings claimed',
          celebrate: true,
          amount: r'$42.50',
          onDone: () {}),
    ));
    await tester.pumpAndSettle();
    expect(_mark(tester).tone, KuteConfirmationTone.celebrate);
    expect(_markPaint(), paints..circle(color: AppColors.celebrate));
    expect(_sal(tester).mood, KuteDogMood.cheer);
    expect(haptics, 1);
  });

  testWidgets(
      'Reduce Motion: final mark at once with no ring, Sal static in his '
      'resting pose, nothing animating', (tester) async {
    await tester.pumpWidget(_app(
      reduceMotion: true,
      home: KuteConfirmation(message: 'Bitcoin sent', onDone: () {}),
    ));
    await tester.pump();

    expect(tester.hasRunningAnimations, isFalse);
    expect(_mark(tester).reduceMotion, isTrue);
    expect(_markPaint(), paintsExactlyCountTimes(#drawCircle, 1));
    // Sal is one still painter, no AnimatedBuilder driving him.
    expect(
        find.descendant(
            of: find.byType(KuteDogConfirmation),
            matching: find.byType(AnimatedBuilder)),
        findsNothing);
    final painter = tester
        .widget<CustomPaint>(find.descendant(
            of: find.byType(KuteDogConfirmation),
            matching: find.byType(CustomPaint)))
        .painter! as KuteDogPainter;
    expect(painter.pose.tail,
        KuteDogConfirmation.restPose(KuteDogMood.happy).tail);
    // The haptic is not motion, so it still fires.
    expect(haptics, 1);
  });

  test('the wag swings the tail widely both ways and ends at idle', () {
    final tails = [
      for (var ms = 120.0; ms < 1000; ms += 10)
        KuteDogConfirmation.poseAt(KuteDogMood.happy, ms).tail
    ];
    final swing = tails.reduce((a, b) => a > b ? a : b) -
        tails.reduce((a, b) => a < b ? a : b);
    expect(swing, greaterThan(0.9));
    final end = KuteDogConfirmation.poseAt(KuteDogMood.happy, 1499);
    final idle = kuteDogIdlePose(0);
    expect(end.tail, closeTo(idle.tail, 0.02));
    expect(end.earLeft, closeTo(idle.earLeft, 0.02));
  });

  group('every way out runs Done', () {
    Future<(NavigatorState, List<String>)> present(WidgetTester tester) async {
      useSurface(tester);
      final key = GlobalKey<NavigatorState>();
      final calls = <String>[];
      await tester.pumpWidget(_app(navigatorKey: key));
      pushKuteSuccessOverlay(
        navigator: key.currentState!,
        overlay: KuteConfirmation(
          message: 'Position sold',
          amount: r'$12.00',
          onDone: () {
            calls.add('done');
            key.currentState!.pop();
          },
        ),
      );
      await tester.pumpAndSettle();
      return (key.currentState!, calls);
    }

    testWidgets('swiping the sheet down', (tester) async {
      final (_, calls) = await present(tester);
      await tester.fling(
          find.text('Position sold'), const Offset(0, 300), 1500);
      await tester.pumpAndSettle();
      expect(calls, ['done']);
      expect(find.byType(KuteConfirmation), findsNothing);
      expect(find.text('host'), findsOneWidget);
    });

    testWidgets('a short drag springs back without Done', (tester) async {
      final (_, calls) = await present(tester);
      final before = tester.getRect(_sheet());
      await tester.drag(find.text('Position sold'), const Offset(0, 40));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      expect(tester.getRect(_sheet()), before);
    });

    testWidgets('tapping the scrim', (tester) async {
      final (_, calls) = await present(tester);
      await tester.tapAt(const Offset(215, 60));
      await tester.pumpAndSettle();
      expect(calls, ['done']);
      expect(find.text('host'), findsOneWidget);
    });

    testWidgets('the system back gesture', (tester) async {
      final (nav, calls) = await present(tester);
      await nav.maybePop();
      await tester.pumpAndSettle();
      expect(calls, ['done']);
      expect(find.byType(KuteConfirmation), findsNothing);
    });

    testWidgets('Done tapped twice runs once', (tester) async {
      final (_, calls) = await present(tester);
      await tester.tap(find.widgetWithText(AppButton, 'Done'));
      await tester.tap(find.widgetWithText(AppButton, 'Done'),
          warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(calls, ['done']);
    });
  });

  testWidgets('a Done that navigates nowhere leaves the sheet usable',
      (tester) async {
    var done = 0;
    await tester.pumpWidget(_app(
      home: KuteConfirmation(message: 'Prediction placed', onDone: () => done++),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AppButton));
    await tester.pump();
    await tester.tap(find.byType(AppButton));
    await tester.pump();
    expect(done, 2);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('sheet surface and text follow the ${mode.name} theme',
        (tester) async {
      await tester.pumpWidget(_app(
        mode: mode,
        home: KuteConfirmation(
            message: 'Prediction placed',
            amount: r'$5.00',
            contextLine: 'Will it rain?',
            onDone: () {}),
      ));
      await tester.pumpAndSettle();

      final element = tester.element(find.byType(KuteConfirmation));
      final colors = element.colors;
      expect(Theme.of(element).brightness,
          mode == ThemeMode.dark ? Brightness.dark : Brightness.light);
      final decoration =
          tester.widget<Container>(_sheet()).decoration! as BoxDecoration;
      expect(decoration.color, colors.surface);
      expect(decoration.borderRadius,
          BorderRadius.vertical(top: Radius.circular(AppRadius.xxl)));
      expect(tester.widget<Text>(find.text('Prediction placed')).style?.color,
          colors.textPrimary);
      expect(tester.widget<Text>(find.text(r'$5.00')).style?.color,
          colors.textPrimary);
      expect(tester.widget<Text>(find.text('Will it rain?')).style?.color,
          colors.textSecondary);
      final scrim = tester.widget<ColoredBox>(find.descendant(
          of: find.byKey(_scrimKey), matching: find.byType(ColoredBox)));
      expect(scrim.color, colors.modalBarrier);
    });
  }

  testWidgets('slides up and waits for the slide before the check pops',
      (tester) async {
    useSurface(tester);
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigatorKey: navKey));
    pushKuteSuccessOverlay(
      navigator: navKey.currentState!,
      overlay: KuteConfirmation(message: 'Position sold', onDone: () {}),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final midway = tester.getRect(_sheet()).top;
    await tester.pump(const Duration(milliseconds: 150));
    // Still sliding: nothing drawn yet, no haptic.
    expect(_markPaint(), paintsExactlyCountTimes(#drawCircle, 0));
    expect(haptics, 0);

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 700));
    expect(haptics, 1);
    await tester.pumpAndSettle();
    expect(tester.getRect(_sheet()).top, lessThan(midway));
    expect(tester.getRect(_sheet()).bottom, closeTo(932, 0.5));
    expect(haptics, 1);
  });

  testWidgets(
      'pushKuteSuccessOverlayAfter navigates first and presents the sheet '
      'over the landing screen', (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigatorKey: navKey));
    final nav = navKey.currentState!;
    nav.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('send screen'))));
    await tester.pumpAndSettle();

    final order = <String>[];
    final presented = pushKuteSuccessOverlayAfter(
      navigator: nav,
      navigate: () {
        order.add('navigate');
        nav.pop();
      },
      overlay: Builder(builder: (context) {
        order.add('sheet');
        return KuteConfirmation(message: 'Bitcoin sent', onDone: nav.pop);
      }),
    );
    await tester.pumpAndSettle();
    await presented;
    expect(order.first, 'navigate');
    expect(order, contains('sheet'));
    expect(find.text('Bitcoin sent'), findsOneWidget);
    expect(find.text('send screen'), findsNothing);
    expect(find.text('host'), findsOneWidget);

    await tester.tap(find.byType(AppButton));
    await tester.pumpAndSettle();
    expect(find.byType(KuteConfirmation), findsNothing);
    expect(find.text('host'), findsOneWidget);
  });

  testWidgets(
      'a TradeReceipt is read into the sheet: title as context, first row '
      'as the amount, the rest as rows, the transaction as a row action',
      (tester) async {
    final opened = <Uri>[];
    TradeReceiptTransaction.debugLaunchOverride = (uri) async => opened.add(uri);
    addTearDown(() => TradeReceiptTransaction.debugLaunchOverride = null);
    await tester.pumpWidget(_app(
      home: KuteConfirmation(
        message: 'Prediction won',
        celebrate: true,
        onDone: () {},
        receipt: TradeReceipt(
          title: 'Portugal to win',
          subtitle: 'Yes',
          rows: const {'Payout': r'$18.00', 'Cost': r'$10.00'},
          transaction: TradeReceiptTransaction.polygon('0x${'ab' * 32}'),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<Text>(
                find.byKey(const ValueKey('kute-confirmation-amount')))
            .data,
        r'$18.00');
    expect(find.text('Yes · Portugal to win'), findsOneWidget);
    expect(find.text('Cost'), findsOneWidget);
    expect(find.text('Payout'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('trade-receipt-explorer')));
    await tester.pump();
    expect(opened.single.host, 'polygonscan.com');
  });

  test('a bitcoin txid opens mempool.space; a Spark id gets no row', () {
    expect(TradeReceiptTransaction.bitcoin('spark-transfer-id'), isNull);
    final tx = TradeReceiptTransaction.bitcoin('ab' * 32)!;
    expect(tx.explorerUri.toString(), 'https://mempool.space/tx/${'ab' * 32}');
    expect(tx.explorer, 'mempool');
  });

  testWidgets(
      'KuteSuccessOverlay keeps its amount, subtitle and detail, title in '
      'sentence case', (tester) async {
    await tester.pumpWidget(_app(
      home: const KuteSuccessOverlay(
        headlineLabel: 'BITCOIN PURCHASED',
        amount: r'$20.00',
        subtitle: 'Sent to your Spending account',
        detail: 'Arriving in ~2 min',
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Bitcoin purchased'), findsOneWidget);
    expect(find.text(r'$20.00'), findsOneWidget);
    expect(find.text('Sent to your Spending account'), findsOneWidget);
    expect(find.text('Arriving in ~2 min'), findsOneWidget);
  });

  testWidgets(
      'a failure with a long detail and receipt wraps and scrolls on a '
      'small screen with large text, nothing clipped', (tester) async {
    useSurface(tester, const Size(320, 568));
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

    // More than fits: the content scrolls, the button stays on screen.
    final scrollable = find.byType(Scrollable);
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, greaterThan(0));
    final button = tester.getRect(find.byType(AppButton));
    expect(button.bottom, lessThanOrEqualTo(568));

    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    final detailRect = tester.getRect(detailFinder);
    expect(detailRect.bottom, lessThanOrEqualTo(button.top));
    expect(tester.getRect(find.byType(AppButton)), button);

    // Scrolled back up, the title is reachable inside the screen.
    position.jumpTo(0);
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('Zahlung nicht gesendet')).top,
        greaterThanOrEqualTo(0));
    expect(tester.takeException(), isNull);
  });
}
