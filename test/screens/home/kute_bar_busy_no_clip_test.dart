// The bar's primary button never cuts its words (founder, 6 November
// 2026: "text is clipping in Investing when thinking on the button, bet
// slip sometimes"; kute_shell_bar.dart, THE WORDS NEVER CLIP). On a 375 pt
// phone, in English, German and Japanese, with the slip's round share
// button beside it, the button goes from the order slip's idle words to
// its busy steps and back ("Long $12.00" → "Adding $12.00 to Dollars" →
// "Preparing your order" → "Opening $12.00 Long BTC" → "Long $12.00"),
// and the bet slip's ("Place $10.00 on Yes" → "Placing order..." → back):
// on every frame every word on the button, the words arriving and the
// words leaving, lies inside the pill and inside the bar's width spring
// (the shell bar's AnimatedSize, which clips); at rest the words are whole
// (an ellipsis only where they could never fit beside the share button).

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/app_router.dart' show AppRouter;
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/screens/home/components/kute_shell_bar.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/theme/app_theme.dart';

final _button = find.byKey(const ValueKey('kute-bar-primary-button'));
final _share = find.byKey(const ValueKey('kute-bar-share'));

Future<void> _loadInter(WidgetTester tester) => tester.runAsync(() async {
      final inter = FontLoader('Inter');
      for (final f in ['Regular', 'SemiBold', 'Bold']) {
        inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
      }
      await inter.load();
    });

/// A slip's primary: the slip's own look (the side colour, w800) and the
/// round share button beside it.
KuteBarContext _slip(String label,
        {bool busy = false, String? busyLabel, Color fill = AppColors.marketUp}) =>
    KuteBarContext.primary(
      label: label,
      onPrimary: busy ? null : () {},
      busy: busy,
      busyLabel: busyLabel,
      disabledLabel: 'Enter an amount',
      style: KuteBarPrimaryStyle(
        fill: fill,
        foreground: Colors.white,
        radius: KuteBarPrimaryButton.radius,
        fontWeight: FontWeight.w800,
      ),
      share: KuteBarShare(send: () {}),
    );

/// The bar over a slip page on a 375 x 812 phone in [locale], the slip's
/// context in a notifier the test drives.
Future<ValueNotifier<KuteBarContext>> _pump(
    WidgetTester tester, Locale locale, KuteBarContext initial) async {
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  KuteBarRouteObserver.reset();
  kuteShellMounted.value = true;
  addTearDown(() {
    kuteShellMounted.value = false;
    KuteBarRouteObserver.reset();
  });
  final ctx = ValueNotifier<KuteBarContext>(initial);
  addTearDown(ctx.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [aiEnabledProvider.overrideWith((_) async => true)],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        locale: locale,
        theme: ThemeData(
          splashFactory: NoSplash.splashFactory,
          fontFamily: 'Inter',
          extensions: [AppColorsExtension.light()],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        navigatorKey: AppRouter.rootNavigatorKey,
        navigatorObservers: [KuteBarRouteObserver()],
        builder: (context, child) =>
            Stack(children: [child!, const KuteShellBar()]),
        home: const Scaffold(body: SizedBox.expand()),
      ),
    ),
  ));
  AppRouter.rootNavigatorKey.currentState!.push(MaterialPageRoute<void>(
    settings: const RouteSettings(name: 'slip'),
    builder: (_) => ValueListenableBuilder<KuteBarContext>(
      valueListenable: ctx,
      builder: (_, c, __) => KuteBarContextScope(
          barContext: c, child: const Scaffold(body: SizedBox.expand())),
    ),
  ));
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return ctx;
}

/// The product of the fades over [e] (the words' cross-slide, the bar's
/// own cross-fade).
double _opacity(WidgetTester tester, Element e) {
  var o = 1.0;
  for (final f in tester.widgetList<FadeTransition>(find.ancestor(
      of: find.byElementPredicate((x) => x == e),
      matching: find.byType(FadeTransition)))) {
    o *= f.opacity.value;
  }
  return o;
}

/// Every visible word on the button lies inside the pill (inside its
/// hairline) and inside the bar's width spring, edge to edge.
void _expectWhole(WidgetTester tester, String reason) {
  if (_button.evaluate().isEmpty) return;
  final pill = tester.getRect(_button.last);
  var clip = Rect.fromLTRB(pill.left + 1, pill.top, pill.right - 1, pill.bottom);
  final spring =
      find.ancestor(of: _button.last, matching: find.byType(AnimatedSize));
  for (final s in spring.evaluate()) {
    final box = s.renderObject! as RenderBox;
    clip = clip.intersect(box.localToGlobal(Offset.zero) & box.size);
  }
  for (final e in find
      .descendant(of: _button.last, matching: find.byType(RichText))
      .evaluate()) {
    if (_opacity(tester, e) < 0.02) continue;
    final p = e.renderObject! as RenderParagraph;
    final r = p.localToGlobal(Offset.zero) & p.size;
    final words = p.text.toPlainText();
    expect(r.left, greaterThanOrEqualTo(clip.left - 0.5),
        reason: '$reason: "$words" cut at its start');
    expect(r.right, lessThanOrEqualTo(clip.right + 0.5),
        reason: '$reason: "$words" cut at its end');
  }
}

/// Changes the slip's context to [next] and checks every frame until the
/// button is at rest; then the words it says are whole and alone.
Future<void> _morph(WidgetTester tester, ValueNotifier<KuteBarContext> ctx,
    KuteBarContext next, String reason) async {
  ctx.value = next;
  for (var f = 0; f < 60; f++) {
    await tester.pump(const Duration(milliseconds: 16));
    _expectWhole(tester, '$reason, frame $f');
  }
  expect(tester.takeException(), isNull, reason: reason);
  // At rest: the words the context says, once, whole.
  final words = next.primaryLabel;
  final shown = find.descendant(of: _button.last, matching: find.text(words));
  expect(shown, findsOneWidget, reason: '$reason: "$words" on the button');
  expect(find.descendant(of: _button.last, matching: find.byType(RichText)),
      findsOneWidget,
      reason: '$reason: nothing else left over');
  expect(_share, findsOneWidget, reason: '$reason: the round share button');
  final p = tester.renderObject<RenderParagraph>(find.descendant(
      of: shown, matching: find.byType(RichText)));
  // An ellipsis only where the words could never fit beside the share
  // button.
  final natural = TextPainter(
    text: TextSpan(text: words, style: p.text.style),
    textDirection: TextDirection.ltr,
    textScaler: p.textScaler,
    maxLines: 1,
  )..layout();
  final pill = tester.getRect(_button.last);
  final row = tester.getRect(find.ancestor(
      of: _share, matching: find.byType(Row)).first);
  // The bar's widest pill: the row's room less the share button.
  final widest = tester.getRect(find.byType(KuteShellBar)).width -
      2 * 16 * 375 / 430 -
      (row.right - pill.right);
  final fixed = KuteBarPrimaryButton.paddingStart +
      KuteBarPrimaryButton.salSize +
      8 * 375 / 430 +
      KuteBarPrimaryButton.paddingEnd +
      2;
  if (natural.width + 1 <= widest - fixed) {
    expect(p.didExceedMaxLines, isFalse, reason: '$reason: "$words" whole');
  }
  natural.dispose();
  _expectWhole(tester, '$reason, at rest');
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    OpenOnce.reset();
  });

  for (final code in ['en', 'de', 'ja']) {
    testWidgets(
        '$code at 375 pt: the order slip idle → its busy steps → idle, '
        'never a word cut', (tester) async {
      await _loadInter(tester);
      final l = lookupAppLocalizations(Locale(code));
      final idle = l.slipCtaSideAmount(l.longLabel, r'$12.00');
      final ctx = await _pump(tester, Locale(code), _slip(idle));
      expect(_share, findsOneWidget);
      // The funded order's steps (order_slip_sheet.dart): the step is the
      // busy button's words.
      final steps = [
        l.slipStepAddingToInvestments(r'$12.00'),
        l.slipStepPreparingOrder,
        l.slipStepOpeningOrder(r'$12.00', l.longLabel, 'BTC'),
      ];
      for (final s in steps) {
        await _morph(tester, ctx, _slip(s, busy: true), 'to "$s"');
      }
      // A placement busy under its own busy words, then back to idle.
      await _morph(tester, ctx,
          _slip(idle, busy: true, busyLabel: l.slipStepPreparingOrder),
          'busy "${l.slipStepPreparingOrder}"');
      await _morph(tester, ctx, _slip(idle), 'back to "$idle"');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets(
        '$code at 375 pt: the bet slip idle → placing → idle, never a word '
        'cut', (tester) async {
      await _loadInter(tester);
      final l = lookupAppLocalizations(Locale(code));
      for (final side in [l.yes, 'Kansas City Chiefs']) {
        final idle = l.betPredictSide(side, r'$10.00');
        final ctx = await _pump(tester, Locale(code), _slip(idle));
        await _morph(
            tester,
            ctx,
            _slip(idle, busy: true, busyLabel: l.betPlacingOrderEllipsis),
            'placing on $side');
        await _morph(tester, ctx, _slip(idle), 'back to "$idle"');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 6));
      }
    });
  }

  testWidgets('Reduce Motion: the busy words at once, whole', (tester) async {
    await _loadInter(tester);
    final l = lookupAppLocalizations(const Locale('de'));
    final idle = l.slipCtaSideAmount(l.longLabel, r'$12.00');
    final ctx = await _pump(tester, const Locale('de'), _slip(idle));
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pump();
    final busy = _slip(idle, busy: true, busyLabel: l.slipStepPreparingOrder);
    ctx.value = busy;
    await tester.pump();
    await tester.pump();
    expect(
        find.descendant(
            of: _button.last, matching: find.text(l.slipStepPreparingOrder)),
        findsOneWidget);
    _expectWhole(tester, 'reduce motion');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 6));
  });
}
