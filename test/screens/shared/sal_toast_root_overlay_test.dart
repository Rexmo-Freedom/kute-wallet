// The Sal toast draws on the app's ROOT overlay, through the root
// navigator's key (root_navigator.dart), never through the caller's
// context (founder, 9 November 2026, on 2.2.0 (95): "Sal toast did not
// show"). Two callers whose context cannot reach an overlay:
//
//  * the standing orders' shell (standing_orders_shell.dart), mounted in
//    the MaterialApp builder's Stack BESIDE the navigator, as app_widget
//    mounts it: no Overlay and no Navigator above it, so every placed,
//    failed and price-moved notice was dropped;
//  * a slip's context, gone by the time its order fills.
//
// Both show the toast now. The second case also runs with profile-build
// hooks on (debugProfileBuildsEnabled), the closest a widget test gets to
// a release build: the toast's path has no debug-only branch.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart' as widgets show debugProfileBuildsEnabled;
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/helpers/root_navigator.dart';
import 'package:kute/screens/shared/sal_notices.dart';
import 'package:kute/screens/shared/sal_reactions.dart';
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/screens/shared/sal_toast.dart';
import 'package:kute/theme/app_theme.dart';

const _toast = ValueKey('sal-toast');
const _arrive = Duration(milliseconds: 450);

void main() {
  late BuildContext beside;

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SalToast.debugSuccessFeedbackOverride = () async {};
    SalToast.debugFailureFeedbackOverride = () async {};
    SalReactions.debugReset();
  });
  tearDown(() {
    SalToast.debugReset();
    SalToast.debugSuccessFeedbackOverride = null;
    SalToast.debugFailureFeedbackOverride = null;
    SalReactions.debugReset();
  });

  /// The app's shape (app_widget.dart): the router's navigator under the
  /// root key, and beside it in the builder's Stack a layer of the shell's
  /// kind.
  Future<void> pumpApp(WidgetTester tester) async {
    SalSpriteCache.debugSetManifest(null);
    addTearDown(SalSpriteCache.debugReset);
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        navigatorKey: kuteRootNavigatorKey,
        theme: buildLightTheme(),
        builder: (context, child) => Stack(children: [
          child!,
          Builder(builder: (ctx) {
            beside = ctx;
            return const SizedBox.shrink();
          }),
        ]),
        home: const Scaffold(body: SizedBox.expand()),
      ),
    ));
  }

  testWidgets(
      'a layer beside the navigator (the standing orders\' shell) has no '
      'overlay of its own, and its notice still shows', (tester) async {
    await pumpApp(tester);
    // The shell's context reaches neither an Overlay nor a Navigator: the
    // lookup the toast used to rely on finds nothing from here.
    expect(Overlay.maybeOf(beside, rootOverlay: true), isNull);
    expect(Navigator.maybeOf(beside, rootNavigator: true), isNull);

    SalNotices.placed(beside,
        message: 'Prediction placed', detail: 'Will it rain tomorrow?');
    await tester.pump();
    await tester.pump(_arrive);
    expect(find.byKey(_toast), findsOneWidget);
    expect(find.text('Prediction placed'), findsOneWidget);
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  Future<void> slipGoneThenFill(WidgetTester tester) async {
    await pumpApp(tester);
    // The slip: a sheet on the root navigator.
    late BuildContext slip;
    showModalBottomSheet<void>(
      context: kuteRootNavigatorKey.currentContext!,
      builder: (ctx) {
        slip = ctx;
        return const SizedBox(height: 300);
      },
    );
    await tester.pumpAndSettle();
    // The accept: the slip closes at once.
    kuteRootNavigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(slip.mounted, isFalse);

    // Minutes later the order fills; the notice is asked for with the
    // slip's dead context.
    await tester.pump(const Duration(minutes: 2));
    SalNotices.placed(slip, message: 'Prediction placed');
    await tester.pump();
    await tester.pump(_arrive);
    expect(find.byKey(_toast), findsOneWidget);
    expect(find.text('Prediction placed'), findsOneWidget);
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
    expect(find.byKey(_toast), findsNothing);
    expect(tester.takeException(), isNull);
  }

  testWidgets(
      'the slip closed before the order filled: the placed toast shows',
      slipGoneThenFill);

  testWidgets(
      'the same with profile-build hooks on (release-like): the toast '
      'shows', (tester) async {
    expect(kReleaseMode, isFalse, reason: 'widget tests run in debug');
    widgets.debugProfileBuildsEnabled = true;
    debugProfileLayoutsEnabled = true;
    debugProfilePaintsEnabled = true;
    try {
      await slipGoneThenFill(tester);
    } finally {
      // Unset before the test ends: the binding checks them.
      widgets.debugProfileBuildsEnabled = false;
      debugProfileLayoutsEnabled = false;
      debugProfilePaintsEnabled = false;
    }
  });
}
