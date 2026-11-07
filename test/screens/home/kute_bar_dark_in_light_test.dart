// The bar is dark in light mode, in every state (founder, 7 November 2026,
// of the white "Search or Manage with AI", "Pick a market group" and "Send
// to a friend" pills: "shoudn tthe button be black idk. why you didnt
// change?"; kute_bar_surface.dart). Every non-trade state the shell bar
// shows paints the primary button's dark fill with its light hairline and
// soft shadow, the words white, a hint's second line quieter, a disabled
// step quieter still; a cross-fade between states never shows white; a
// tinted slip's own white button keeps the light pill while off; and dark
// mode keeps its own look.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/screens/home/components/kute_shell_bar.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:kute/theme/kute_bar_surface.dart';

final _navKey = GlobalKey<NavigatorState>();
const _boundary = Key('dark-bar-boundary');
final _pillBox = find.byKey(const ValueKey('dock-search-pill'));
final _buttonBox = find.byKey(const ValueKey('kute-bar-primary-button'));

/// The app's layering in miniature (as kute_shell_bar_test.dart), in
/// [dark] or light mode, inside one repaint boundary the flash check reads.
Future<void> _pump(WidgetTester tester, {bool dark = false}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [aiEnabledProvider.overrideWith((_) async => true)],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
          brightness: dark ? Brightness.dark : Brightness.light,
          splashFactory: NoSplash.splashFactory,
          fontFamily: 'Inter',
          extensions: [
            dark ? AppColorsExtension.dark() : AppColorsExtension.light()
          ],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        navigatorKey: _navKey,
        navigatorObservers: [KuteBarRouteObserver()],
        builder: (context, child) => RepaintBoundary(
          key: _boundary,
          child: Stack(children: [child!, const KuteShellBar()]),
        ),
        // A white page under the bar: a white surface would vanish on it.
        home: const Scaffold(
            backgroundColor: Colors.white, body: SizedBox.expand()),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// A page over the tabs holding [ctx] (the default bar with none), its
/// context changed through [notifier] when given.
Future<void> _push(WidgetTester tester,
    {KuteBarContext? ctx, ValueNotifier<KuteBarContext>? notifier}) async {
  _navKey.currentState!.push(MaterialPageRoute<void>(
    builder: (_) {
      const body =
          Scaffold(backgroundColor: Colors.white, body: SizedBox.expand());
      if (notifier != null) {
        return ValueListenableBuilder<KuteBarContext>(
          valueListenable: notifier,
          builder: (_, c, __) => KuteBarContextScope(barContext: c, child: body),
        );
      }
      return ctx == null
          ? body
          : KuteBarContextScope(barContext: ctx, child: body);
    },
  ));
  await _settle(tester);
}

Future<void> _pop(WidgetTester tester) async {
  _navKey.currentState!.pop();
  await _settle(tester);
}

/// Frames until the bar is at rest (a busy button's shimmer never settles).
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

BoxDecoration _decoration(WidgetTester tester, Finder box) =>
    tester.widget<AnimatedContainer>(box).decoration! as BoxDecoration;

Color? _ink(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text).last).style?.color;

/// The bar's surface is the dark one: the fill, the hairline, the shadow.
void _expectDark(WidgetTester tester, Finder box) {
  final d = _decoration(tester, box);
  expect(d.color, AppColorsExtension.light().textPrimary);
  expect((d.border! as Border).top.color, KuteBarSurface.edge);
  expect(d.boxShadow, [KuteBarSurface.shadow(visible: true)]);
}

/// The colour at [at] (logical px) of what the boundary painted last.
Future<Color> _pixel(WidgetTester tester, Offset at) async {
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_boundary));
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes =
        (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final i = (at.dy.round() * image.width + at.dx.round()) * 4;
    final color = Color.fromARGB(bytes.getUint8(i + 3), bytes.getUint8(i),
        bytes.getUint8(i + 1), bytes.getUint8(i + 2));
    image.dispose();
    return color;
  }))!;
}

/// The bar's middle, just under its top edge, above the words: inside the
/// pill and the button alike while they cross-fade (both centred).
Offset _probe(WidgetTester tester) {
  final rect = tester.getRect(find
      .descendant(
          of: find.byKey(const ValueKey('kute-shell-bar-slide')),
          matching: find.byType(AnimatedSize))
      .first);
  return Offset(rect.center.dx, rect.top + 7);
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    KuteBarRouteObserver.reset();
  });

  testWidgets(
      'light mode: every non-trade bar state paints the dark fill, its '
      'hairline and its shadow, the words white, a hint quieter, a step '
      'to take quieter still', (tester) async {
    await _pump(tester);

    // The search pill (the default over any page).
    await _push(tester);
    _expectDark(tester, _pillBox);
    expect(_ink(tester, 'Search or Manage with AI'), KuteBarSurface.ink);
    await _pop(tester);

    // The two-line hints: a category sheet's, a market's Send to a friend.
    for (final (label, sub, clip) in const [
      ('Pick a market group', 'or ask Sal to find one', 'search'),
      ('Send to a friend', 'They get a link to look at it', 'share'),
    ]) {
      await _push(tester,
          ctx: KuteBarContext(label: label, sublabel: sub, clip: clip));
      _expectDark(tester, _pillBox);
      expect(_ink(tester, label), KuteBarSurface.ink, reason: label);
      expect(_ink(tester, sub), KuteBarSurface.quietInk, reason: sub);
      await _pop(tester);
    }

    // The primary button: the action, busy, off, the PIN gate's Cancel,
    // a coloured action while off, and one with the round share button.
    final states = <(String, KuteBarContext, Color)>[
      (
        'See full portfolio and activity',
        KuteBarContext.primary(
            label: 'See full portfolio and activity', onPrimary: () {}),
        KuteBarSurface.ink
      ),
      (
        'Sending…',
        KuteBarContext.primary(
            label: 'Send',
            busy: true,
            busyLabel: 'Sending…',
            onPrimary: () {}),
        KuteBarSurface.ink
      ),
      (
        'Enter an amount',
        KuteBarContext.primary(
            label: 'Create request',
            disabledLabel: 'Enter an amount',
            enabled: false,
            onPrimary: () {}),
        KuteBarSurface.disabledInk
      ),
      (
        'Cancel',
        KuteBarContext.primary(label: 'Cancel', onPrimary: () {}),
        KuteBarSurface.ink
      ),
      (
        'Position closed',
        KuteBarContext.primary(
            label: 'Close position',
            disabledLabel: 'Position closed',
            enabled: false,
            style: KuteBarPrimaryStyle.destructive,
            onPrimary: () {}),
        KuteBarSurface.disabledInk
      ),
      (
        'Sell',
        KuteBarContext.primary(
            label: 'Sell',
            onPrimary: () {},
            share: const KuteBarShare(
                barContext: KuteBarContext(label: 'Send to a friend'))),
        KuteBarSurface.ink
      ),
    ];
    for (final (words, ctx, ink) in states) {
      await _push(tester, ctx: ctx);
      _expectDark(tester, _buttonBox);
      expect(_ink(tester, words), ink, reason: words);
      if (ctx.share != null) {
        // The round share button beside it: the folded pill, dark too.
        _expectDark(tester, _pillBox);
      }
      await _pop(tester);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'light mode: a coloured action keeps its colours, and a tinted '
      'slip\'s own white button keeps the light pill while off',
      (tester) async {
    await _pump(tester);
    await _push(
        tester,
        ctx: KuteBarContext.primary(
            label: 'Close position',
            style: KuteBarPrimaryStyle.destructive,
            onPrimary: () {}));
    expect(_decoration(tester, _buttonBox).color, AppColors.marketDown);
    expect(_ink(tester, 'Close position'), Colors.white);
    await _pop(tester);

    const slip = KuteBarPrimaryStyle(
        fill: Colors.white, foreground: AppColors.marketUp);
    await _push(
        tester,
        ctx: KuteBarContext.primary(
            label: r'Place $10.00 on Yes',
            disabledLabel: 'Enter an amount',
            enabled: false,
            style: slip,
            onPrimary: () {}));
    final d = _decoration(tester, _buttonBox);
    expect(d.color, Colors.white, reason: 'never black on a tinted slip');
    expect((d.border! as Border).top.color, AppColorsExtension.light().border);
    await _pop(tester);
  });

  testWidgets('dark mode keeps its own look: the white pill, the white '
      'action, the surface-grey step to take', (tester) async {
    await _pump(tester, dark: true);
    final c = AppColorsExtension.dark();
    await _push(tester);
    expect(_decoration(tester, _pillBox).color, Colors.white);
    await _pop(tester);
    await _push(tester,
        ctx: KuteBarContext.primary(label: 'Continue', onPrimary: () {}));
    expect(_decoration(tester, _buttonBox).color, c.textPrimary);
    expect(_ink(tester, 'Continue'), c.background);
    await _pop(tester);
    await _push(
        tester,
        ctx: KuteBarContext.primary(
            label: 'Continue',
            disabledLabel: 'Enter an amount',
            enabled: false,
            onPrimary: () {}));
    expect(_decoration(tester, _buttonBox).color, c.surface);
    expect(_ink(tester, 'Enter an amount'), c.textSecondary);
    await _pop(tester);
  });

  testWidgets(
      'light mode: no white flash as the bar morphs, pill to button, off '
      'to on to busy, and back to the pill: its middle stays dark on every '
      'frame', (tester) async {
    await _pump(tester);
    const pill = KuteBarContext(label: 'Search or Manage with AI');
    final notifier = ValueNotifier<KuteBarContext>(pill);
    addTearDown(notifier.dispose);
    await _push(tester, notifier: notifier);
    KuteBarContext primary({bool enabled = true, bool busy = false}) =>
        KuteBarContext.primary(
          label: 'Create request',
          disabledLabel: 'Enter an amount',
          enabled: enabled,
          busy: busy,
          busyLabel: busy ? 'Creating…' : null,
          onPrimary: () {},
        );
    for (final next in [
      primary(enabled: false),
      primary(),
      primary(busy: true),
      pill,
      primary(),
    ]) {
      notifier.value = next;
      // Through the settle's cross-fade and the chip spring's width.
      for (var frame = 0; frame < 30; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        final at = _probe(tester);
        final color = await _pixel(tester, at);
        final brightest = [
          (color.r * 255).round(),
          (color.g * 255).round(),
          (color.b * 255).round(),
        ].reduce((a, b) => a > b ? a : b);
        expect(brightest, lessThan(0x60),
            reason: 'frame $frame towards '
                '${next.isPrimary ? next.primaryLabel : next.label}: '
                '$color at $at');
      }
      await _settle(tester);
    }
    expect(tester.takeException(), isNull);
  });
}
