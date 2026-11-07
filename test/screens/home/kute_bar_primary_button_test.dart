// The bar as the primary button, an adaptive pill (kute_shell_bar.dart,
// KuteBarPrimaryButton; founder, 1 November 2026): disabled it says the
// step to take and takes no tap; enabled it is the action and its tap runs
// the handler, the words cross-sliding between the two; busy it says the
// busy label under a shimmer and takes no tap; and it is only as wide as
// what it says. In light mode every state is on the one dark fill
// (founder, 7 November 2026; kute_bar_surface.dart): the step to take in
// the quieter disabled ink, the action in white.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/home/components/kute_shell_bar.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/theme/kute_bar_surface.dart';

final _button = find.byKey(const ValueKey('kute-bar-primary-button'));
final _shimmer = find.byKey(const ValueKey('kute-bar-primary-shimmer'));

Future<ValueNotifier<KuteBarContext>> _pump(
  WidgetTester tester,
  KuteBarContext initial, {
  bool reduce = false,
  VoidCallback? onAsk,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final ctx = ValueNotifier<KuteBarContext>(initial);
  addTearDown(ctx.dispose);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(430, 932),
    builder: (_, __) => MaterialApp(
      theme: ThemeData(
        splashFactory: NoSplash.splashFactory,
        extensions: [AppColorsExtension.light()],
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
        child: child!,
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
            child: ValueListenableBuilder<KuteBarContext>(
              valueListenable: ctx,
              builder: (_, c, __) => KuteBarPrimaryButton(
                barContext: c,
                onAsk: onAsk ?? () {},
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 500));
  return ctx;
}

/// Frames until the button is at rest: the words' cross-slide, the
/// leaving words' hold and the width's spring.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

BoxDecoration _decoration(WidgetTester tester) {
  final box = tester.widget<AnimatedContainer>(_button);
  return box.decoration! as BoxDecoration;
}

Color? _labelColor(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.color;

void main() {
  final light = AppColorsExtension.light();

  testWidgets(
      'disabled: the step to take on the dark fill in the quieter ink; a '
      'tap does nothing', (tester) async {
    var ran = 0;
    await _pump(
      tester,
      KuteBarContext.primary(
        label: 'Create request',
        disabledLabel: 'Enter an amount',
        enabled: false,
        onPrimary: () => ran++,
      ),
    );
    expect(find.text('Enter an amount'), findsOneWidget);
    expect(find.text('Create request'), findsNothing);
    final d = _decoration(tester);
    expect(d.color, light.textPrimary,
        reason: 'the bar\'s one dark fill in light mode, never white');
    expect((d.border! as Border).top.color, KuteBarSurface.edge);
    expect(_labelColor(tester, 'Enter an amount'), KuteBarSurface.disabledInk);
    await tester.tap(_button);
    await tester.pump(const Duration(milliseconds: 500));
    expect(ran, 0);
  });

  testWidgets(
      'disabled to enabled: the words slide (both on screen mid-way), the '
      'fill stays dark throughout, a tap runs the handler', (tester) async {
    var ran = 0;
    KuteBarContext ctx(bool enabled) => KuteBarContext.primary(
          label: 'Create request',
          disabledLabel: 'Enter an amount',
          enabled: enabled,
          onPrimary: () => ran++,
        );
    final notifier = await _pump(tester, ctx(false));
    notifier.value = ctx(true);
    await tester.pump();
    expect(_decoration(tester).color, light.textPrimary);
    await tester.pump(const Duration(milliseconds: 120));
    expect(_decoration(tester).color, light.textPrimary,
        reason: 'no lerp through white on the way to the action');
    expect(find.text('Enter an amount'), findsOneWidget,
        reason: 'the old words still leaving');
    expect(find.text('Create request'), findsOneWidget,
        reason: 'the new words rising');
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Enter an amount'), findsNothing);
    expect(_decoration(tester).color, light.textPrimary);
    expect(_labelColor(tester, 'Create request'), Colors.white);
    await tester.tap(_button);
    await tester.pump(const Duration(milliseconds: 500));
    expect(ran, 1);
  });

  testWidgets(
      'busy: the busy label under the shimmer, the same size, taps ignored; '
      'Reduce Motion: no shimmer', (tester) async {
    var ran = 0;
    final notifier = await _pump(
      tester,
      KuteBarContext.primary(
          label: 'Send', disabledLabel: 'Enter an amount', onPrimary: () => ran++),
    );
    notifier.value = KuteBarContext.primary(
      label: 'Send',
      disabledLabel: 'Enter an amount',
      busy: true,
      busyLabel: 'Sending…',
      onPrimary: () => ran++,
    );
    // Longer words wait for their room (the spring's first frames).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Sending…'), findsOneWidget);
    expect(_shimmer, findsOneWidget);
    expect(_decoration(tester).color, light.textPrimary,
        reason: 'busy keeps the action look');
    // The shimmer sweeps: a band 30% of the width, moving right.
    final width = tester.getSize(_button).width;
    expect(tester.getSize(_shimmer).width,
        moreOrLessEquals(width * KuteBarPrimaryButton.shimmerBand, epsilon: 1));
    final x0 = tester.getTopLeft(_shimmer).dx;
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.getTopLeft(_shimmer).dx, greaterThan(x0));
    await tester.tap(_button);
    await tester.pump(const Duration(milliseconds: 100));
    expect(ran, 0);

    // Reduce Motion: the busy label, still; no shimmer.
    await _pump(
      tester,
      KuteBarContext.primary(
        label: 'Send',
        disabledLabel: 'Enter an amount',
        busy: true,
        busyLabel: 'Sending…',
        onPrimary: () {},
      ),
      reduce: true,
    );
    expect(find.text('Sending…'), findsOneWidget);
    expect(_shimmer, findsNothing);
  });

  testWidgets(
      'the width adapts: "Create request" is narrower than a long label, and '
      'never under the minimum', (tester) async {
    final notifier = await _pump(tester,
        KuteBarContext.primary(label: 'Create request', onPrimary: () {}));
    final narrow = tester.getSize(_button).width;
    notifier.value = KuteBarContext.primary(
        label: 'Place prediction · \$1,250.00 on Gen.G', onPrimary: () {});
    // The width springs (the button's own room, kute_shell_bar.dart).
    await _settle(tester);
    final wide = tester.getSize(_button).width;
    expect(narrow, lessThan(wide));
    expect(wide, lessThanOrEqualTo(390 - 32 + 0.5));
    notifier.value = KuteBarContext.primary(label: 'OK', onPrimary: () {});
    // The old words leave first, then the width springs down.
    await _settle(tester);
    expect(tester.getSize(_button).width,
        moreOrLessEquals(KuteBarPrimaryButton.minWidth));
    expect(tester.getSize(_button).height, KuteBarPrimaryButton.height);
  });

  testWidgets('a long press asks Sal, never the action', (tester) async {
    var asked = 0;
    var ran = 0;
    await _pump(
      tester,
      KuteBarContext.primary(label: 'Continue', onPrimary: () => ran++),
      onAsk: () => asked++,
    );
    await tester.longPress(_button);
    await tester.pump(const Duration(milliseconds: 500));
    expect(asked, 1);
    expect(ran, 0);
  });
}
