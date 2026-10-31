// The harness the share-link widget tests pump into: the app theme, the
// localizations, ScreenUtil and a fake share-links backend. Animations
// are disabled (Sal's rig never settles otherwise), so tests pump a few
// frames instead of pumpAndSettle.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/services/api/share_links_api.dart';
import 'package:kute/services/share_links_store.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';

import '../../mocks/fake_share_links_api.dart';

class ShareTestEnv {
  ShareTestEnv(this.fake, this.events);
  final FakeShareLinksApi fake;
  final List<(String, Map<String, Object>?)> events;

  Iterable<Map<String, Object>?> paramsOf(String event) =>
      events.where((e) => e.$1 == event).map((e) => e.$2);
}

bool _hiveReady = false;

/// Resets the store, tracking and fonts before each test. Hive gets a
/// temp directory: the bitcoin amount label reads the currency provider,
/// whose notifier opens its rates box on construction.
ShareTestEnv setUpShareTest() {
  if (!_hiveReady) {
    Hive.init(Directory.systemTemp.createTempSync('share_test_hive').path);
    _hiveReady = true;
  }
  GoogleFonts.config.allowRuntimeFetching = false;
  TrackingService.setDisabled(true);
  ShareLinksStore.debugMemory = <String, String>{};
  final events = <(String, Map<String, Object>?)>[];
  TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  return ShareTestEnv(FakeShareLinksApi(), events);
}

void tearDownShareTest() {
  TrackingService.debugTrackObserver = null;
  ShareLinksStore.debugMemory = null;
}

Future<void> pumpShareWidget(
  WidgetTester tester,
  ShareTestEnv env,
  Widget child, {
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      shareLinksApiProvider.overrideWithValue(env.fake),
      ...overrides,
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        home: Scaffold(body: child),
        theme: ThemeData(
            splashFactory: NoSplash.splashFactory,
            fontFamily: 'Inter',
            extensions: [AppColorsExtension.light()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  ));
  await settle(tester);
}

/// A few frames, enough for futures and short transitions.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
