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
// app where every slip opens over the tab shell. The bar is a Riverpod
// consumer: a `ProviderScope` must sit above the MaterialApp.
//
// Timing: a scope pushes its context after its first frame and the bar
// rebuilds on the next, so after a tap that changes the label (a keypad
// key, Max) read the bar after [pumpBar] or a settle. While the keyboard
// is up the bar is away and, if it was never shown, not even built: assert
// [barIsUp] false, drop the inset, then read it.
//
// A surface under another route (a sheet over the slip, the Advanced
// page) is not what the bar reads; its DECLARED context is still on stage
// through its [KuteBarContextScope]: [scopeContext] and friends read that.

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
    show
        KuteBarContext,
        KuteBarContextScope,
        KuteBarRouteObserver,
        kuteShellMounted;

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
  TransitionBuilder? wrap,
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
        // [builder] wraps the navigator alone (under the bar); [wrap]
        // wraps the bar too (a MediaQuery for Reduce Motion or a text
        // scale that the bar must see).
        builder: (context, child) {
          final under = builder == null ? child : builder(context, child);
          final layered = shellBarBuilder(context, under);
          return wrap == null ? layered : wrap(context, layered);
        },
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

/// The progress ring inside the button, there while busy.
Finder barPrimaryRing() => find.descendant(
    of: findBarPrimary(), matching: find.byType(CircularProgressIndicator));

/// The colour the bar letters its label in (white on the primary fill in
/// light mode, the mode's background in dark, the quiet ink disabled).
Color? barPrimaryInk(WidgetTester tester) => tester
    .widget<Text>(
        find.descendant(of: findBarPrimary(), matching: find.byType(Text)))
    .style
    ?.color;

// ── Reading a surface's declared context ────────────────────────────────

/// The context the on-stage surface declares through its
/// [KuteBarContextScope] (the first on stage: the slip, or the page over
/// it), whether or not the bar is reading it right now. [within] narrows
/// to a scope under that finder.
KuteBarContext scopeContext(WidgetTester tester, {Finder? within}) {
  final scopes = within == null
      ? find.byType(KuteBarContextScope)
      : find.descendant(of: within, matching: find.byType(KuteBarContextScope));
  return tester.widget<KuteBarContextScope>(scopes.first).barContext;
}

/// What that surface's button would read (busy label while busy).
String scopeLabel(WidgetTester tester, {Finder? within}) {
  final ctx = scopeContext(tester, within: within);
  return ctx.busy ? (ctx.busyLabel ?? ctx.label) : ctx.label;
}

/// Whether that surface's action runs on a tap.
bool scopeEnabled(WidgetTester tester, {Finder? within}) {
  final ctx = scopeContext(tester, within: within);
  return ctx.enabled && !ctx.busy && ctx.onPrimary != null;
}

/// Whether that surface declares itself busy.
bool scopeBusy(WidgetTester tester, {Finder? within}) =>
    scopeContext(tester, within: within).busy;

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
