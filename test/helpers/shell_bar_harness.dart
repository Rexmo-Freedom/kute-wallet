// The bar as the primary button, in widget tests.
//
// Since 31 October 2026 (kute_shell_bar.dart, kute_bar_context.dart) a
// slip, an amount sheet or a keypad screen draws NO button of its own: it
// declares its one action through `KuteBarContext.primary` and the
// shell-level [KuteShellBar], mounted once over the root navigator, IS the
// button (`KuteBarPrimaryButton`, keyed `kute-bar-primary-button`). A test
// that mounts a slip on its own therefore sees no CTA unless it mounts the
// bar too. This file is the one place that does that: the same layering
// the app's MaterialApp builder has (the scroll listener around the
// navigator, the bar in a Stack over it, the route observer on the
// navigator), and the finders that read and tap the button.
//
// Two ways in:
//
//   * [shellBarApp] builds the whole ScreenUtilInit > MaterialApp for a
//     test whose pump has nothing unusual (the common case: theme,
//     localisations, `home`);
//   * a test that builds its own MaterialApp (a router, a navigator key,
//     a locale) passes [shellBarBuilder] as its `builder` and
//     [shellBarObservers] as its `navigatorObservers`.
//
// Either way, call [installShellBar] first (in `setUp` or at the top of
// the test): it resets the route observer's count and flips
// [kuteShellMounted] so the bar is up from the first frame, like in the
// app where every slip opens over the tab shell.

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/home/components/kute_shell_bar.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/theme/app_theme.dart';

export 'package:kute/screens/home/components/kute_shell_bar.dart'
    show KuteShellBar, KuteBarPrimaryButton;
export 'package:kute/screens/shared/kute_bar_context.dart'
    show KuteBarContext, KuteBarRouteObserver, kuteShellMounted;

/// The key the bar's primary button carries (kute_shell_bar.dart).
const Key kuteBarPrimaryButtonKey = ValueKey('kute-bar-primary-button');

/// Resets the bar's route count and marks the tab shell as mounted for
/// the rest of the test, undone on tear-down. Call before pumping.
void installShellBar() {
  KuteBarRouteObserver.reset();
  kuteShellMounted.value = true;
  addTearDown(() {
    kuteShellMounted.value = false;
    KuteBarRouteObserver.reset();
  });
}

/// The app's layering in miniature, for a `MaterialApp.builder`: the
/// scroll listener around the navigator, the bar over it.
Widget shellBarBuilder(BuildContext context, Widget? child) => Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: kuteBarScroll.report,
          child: child ?? const SizedBox.shrink(),
        ),
        const KuteShellBar(),
      ],
    );

/// A fresh route observer for a `MaterialApp.navigatorObservers` (one per
/// navigator; they all write the one count).
List<NavigatorObserver> shellBarObservers() => [KuteBarRouteObserver()];

/// The standard test app around [home], with the bar mounted: the app's
/// design size, Inter, the light (or [dark]) colours, the localisations.
/// A test with its own MaterialApp uses [shellBarBuilder] and
/// [shellBarObservers] instead.
Widget shellBarApp({
  required Widget home,
  ThemeData? theme,
  String fontFamily = 'Inter',
  bool dark = false,
  Locale? locale,
  GlobalKey<NavigatorState>? navigatorKey,
  Size designSize = const Size(430, 932),
  TransitionBuilder? builder,
}) =>
    ScreenUtilInit(
      designSize: designSize,
      builder: (_, __) => MaterialApp(
        theme: theme ??
            ThemeData(
              brightness: dark ? Brightness.dark : Brightness.light,
              splashFactory: NoSplash.splashFactory,
              fontFamily: fontFamily,
              extensions: [
                dark ? AppColorsExtension.dark() : AppColorsExtension.light()
              ],
            ),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        navigatorKey: navigatorKey,
        navigatorObservers: shellBarObservers(),
        builder: builder == null
            ? shellBarBuilder
            : (context, child) =>
                shellBarBuilder(context, builder(context, child)),
        home: home,
      ),
    );

// ── Reading the button ──────────────────────────────────────────────────

/// The bar's primary button (the painted box; absent while the bar is the
/// search pill).
Finder findBarPrimary() => find.byKey(kuteBarPrimaryButtonKey);

/// The one [KuteBarPrimaryButton] on screen (the bar cross-fades the
/// pill and the button, so this is the last one built).
Finder findBarPrimaryWidget() => find.byType(KuteBarPrimaryButton);

/// Text inside the primary button.
Finder barPrimaryText(String text) =>
    find.descendant(of: findBarPrimary(), matching: find.text(text));

/// Text inside the primary button containing [pattern].
Finder barPrimaryTextContaining(Pattern pattern) => find.descendant(
    of: findBarPrimary(), matching: find.textContaining(pattern));

/// The context the bar is drawing as the button.
KuteBarContext barPrimaryContext(WidgetTester tester) =>
    tester.widget<KuteBarPrimaryButton>(findBarPrimaryWidget().last).barContext;

/// Whether the bar is the primary button right now.
bool barIsPrimary(WidgetTester tester) =>
    findBarPrimaryWidget().evaluate().isNotEmpty;

/// Whether the bar is up: shown at its resting offset and taking taps
/// (it slides away under the keyboard and a hidden context).
bool barIsUp(WidgetTester tester) {
  final slide = find.byKey(const ValueKey('kute-shell-bar-slide'));
  if (slide.evaluate().isEmpty) return false;
  return tester.widget<AnimatedSlide>(slide).offset == Offset.zero;
}

/// What the button reads: the busy label while busy, else the label (the
/// text the bar paints, kute_shell_bar.dart).
String barPrimaryLabel(WidgetTester tester) {
  final ctx = barPrimaryContext(tester);
  return ctx.busy ? (ctx.busyLabel ?? ctx.label) : ctx.label;
}

/// The context's own label, busy or not (what the slip declared).
String barPrimaryDeclaredLabel(WidgetTester tester) =>
    barPrimaryContext(tester).label;

/// Whether a tap runs the action: enabled, not busy, with a handler.
bool barPrimaryEnabled(WidgetTester tester) {
  final ctx = barPrimaryContext(tester);
  return ctx.enabled && !ctx.busy && ctx.onPrimary != null;
}

/// Whether the button shows its progress ring.
bool barPrimaryBusy(WidgetTester tester) => barPrimaryContext(tester).busy;

/// Taps the bar's primary button. [settle] pumps until quiet; false pumps
/// one frame (a tap that starts a spinner never settles).
Future<void> tapBarPrimary(WidgetTester tester, {bool settle = true}) async {
  await tester.tap(findBarPrimary(), warnIfMissed: false);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

/// Lets the bar take a scope's context: the scope pushes it after its
/// first frame and the bar rebuilds on the next.
Future<void> pumpBar(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}
