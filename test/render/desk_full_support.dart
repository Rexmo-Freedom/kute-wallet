// test/render/desk_full_support.dart
//
// The shared harness for round three's page renders (founder, 25 November
// 2026: "it must be all occupying full screen when we can"). A page is
// pumped the way the app frames it (app_router.dart: KutePageFrame with
// its route's KuteWideMode, under the floating bar, the screenutil design
// size the app gives the window), shot to `$DESK_FULL_RENDER/<name>.png`,
// and checked for stretch: no button wider than a column, no rows card
// wider than a readable column.
//
//   DESK_FULL_RENDER=<dir> flutter test test/render/<page>_render_test.dart

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/platform/kute_layout.dart';
import 'package:kute/platform/kute_wide_frames.dart';
import 'package:kute/screens/home/components/kute_shell_bar.dart'
    show KuteBarPrimaryButton;
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_page_route.dart';
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/theme/app_theme.dart';

import '../helpers/kute_bar_test_support.dart';

/// Where the PNGs go; null: the render tests skip.
final String? deskFullDir = Platform.environment['DESK_FULL_RENDER'];

/// The windows every page is shot at on EXPANDED.
const List<(String, Size)> deskFullExpanded = [
  ('1440x900', Size(1440, 900)),
  ('1920x1080', Size(1920, 1080)),
  ('1180x820', Size(1180, 820)),
  ('1000x700', Size(1000, 700)),
];

/// The phone and MEDIUM, to prove them unchanged.
const List<(String, Size)> deskFullNarrow = [
  ('430x932', Size(430, 932)),
  ('820x1180', Size(820, 1180)),
];

/// Inter, the monospace stand-in, the icons and Sal's sheets.
Future<void> deskFullAssets(WidgetTester tester,
        {List<String> clips = const ['idle', 'body_idle', 'blink']}) =>
    tester.runAsync(() async {
      for (final family in [GoogleFonts.inter().fontFamily!, 'Inter']) {
        final inter = FontLoader(family);
        for (final f in ['Regular', 'SemiBold', 'Bold']) {
          inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
        }
        await inter.load();
      }
      final mono = FontLoader('monospace');
      for (final f in ['Regular', 'Bold']) {
        mono.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
      }
      await mono.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
      try {
        final manifest = jsonDecode(
                await rootBundle.loadString('$kSalSpriteDir/manifest.json'))
            as Map<String, dynamic>;
        SalSpriteCache.debugSetManifest(manifest);
        for (final clip in clips) {
          try {
            await SalSpriteCache.clip(clip, 3);
            await SalSpriteCache.clip(clip, 2);
          } catch (_) {}
        }
      } catch (_) {}
    });

ThemeData deskFullTheme(bool dark) {
  final base = dark ? buildDarkTheme() : buildLightTheme();
  return base.copyWith(
    splashFactory: NoSplash.splashFactory,
    textTheme: base.textTheme.apply(fontFamily: 'Inter'),
  );
}

/// Pumps [page] at [size] as the app frames a pushed page of [mode]
/// (KutePageFrame), under the floating bar, over a plain root page so it
/// has something to pop to. [overrides] for the page's providers.
/// [wrap] lets a test add an ancestor (an http client zone is not a
/// widget: run the pump inside `http.runWithClient` instead).
Future<void> pumpDeskPage(
  WidgetTester tester, {
  required Size size,
  required bool dark,
  required Widget page,
  KuteWideMode mode = KuteWideMode.full,
  List<Override> overrides = const [],
  bool frame = true,
  int frames = 12,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(initialLocation: '/page', routes: [
    GoRoute(
      path: '/',
      builder: (_, __) => const Scaffold(body: SizedBox.expand()),
      routes: [
        GoRoute(
          path: 'page',
          pageBuilder: (context, state) => CustomTransitionPage<void>(
            key: state.pageKey,
            child: frame ? KutePageFrame(mode: mode, child: page) : page,
            transitionsBuilder: (_, __, ___, child) => child,
          ),
        ),
      ],
    ),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: overrides,
    child: ScreenUtilInit(
      designSize: KuteLayout.designSizeFor(size),
      builder: (_, __) => MaterialApp.router(
        debugShowCheckedModeBanner: false,
        builder: withKuteShellBar,
        routerConfig: router,
        theme: deskFullTheme(dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  ));
  await deskFullFrames(tester, frames);
}

Future<void> deskFullFrames(WidgetTester tester, [int n = 12]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The window as a PNG at `$DESK_FULL_RENDER/<name>.png`, shadows drawn.
Future<void> deskFullShoot(WidgetTester tester, String name) async {
  final dir = deskFullDir;
  if (dir == null) return;
  debugDisableShadows = false;
  for (final o in tester.allRenderObjects) {
    o.markNeedsPaint();
  }
  await tester.pump();
  await tester.runAsync(() async {
    final view = tester.binding.renderViews.first;
    final layer = view.debugLayer! as OffsetLayer;
    final image = await layer.toImage(Offset.zero & view.size, pixelRatio: 1);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(dir).createSync(recursive: true);
    File('$dir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
  debugDisableShadows = true;
  await tester.pump();
}

/// Nothing stretched on a full page: every button at most a column wide,
/// and every rows card (a [KuteListGroup]-like surface: a painted box
/// taller than [minHeight]) at most [maxCard] wide, except [allow]ed
/// widgets' subtrees (a chart, a hero meant to span).
void expectDeskNothingStretched(
  WidgetTester tester, {
  double maxCard = 760,
  double minHeight = 40,
  List<Finder> allow = const [],
}) {
  const buttonLimit = KuteLayout.columnMaxWidth + 0.5;
  for (final finder in [
    find.byType(AppButton),
    find.byType(AppTextButton),
    find.byType(CustomButton),
    find.byType(KuteBarPrimaryButton),
  ]) {
    for (final e in finder.evaluate()) {
      final box = e.renderObject;
      if (box is! RenderBox || !box.hasSize || !box.attached) continue;
      expect(box.size.width, lessThanOrEqualTo(buttonLimit),
          reason: 'a ${e.widget.runtimeType} is ${box.size.width} wide');
    }
  }
  final allowed = <RenderObject>{};
  for (final f in allow) {
    for (final e in f.evaluate()) {
      final r = e.renderObject;
      if (r == null) continue;
      void visit(RenderObject o) {
        allowed.add(o);
        o.visitChildren(visit);
      }

      visit(r);
    }
  }
  final window = tester.view.physicalSize.width;
  void visit(RenderObject o) {
    if (o is RenderDecoratedBox &&
        o.hasSize &&
        o.attached &&
        !allowed.contains(o)) {
      final d = o.decoration;
      final painted = d is BoxDecoration &&
          (d.borderRadius != null) &&
          ((d.color != null && d.color!.a > 0) || d.border != null);
      // A rounded painted card (not the page's own background).
      if (painted && o.size.height >= minHeight && o.size.width < window - 1) {
        expect(o.size.width, lessThanOrEqualTo(maxCard),
            reason: 'a card ${o.size} stretches; created by ${o.debugCreator}');
      }
    }
    o.visitChildren(visit);
  }

  for (final view in tester.binding.renderViews) {
    visit(view);
  }
}

/// Unmounts the page and lets its timers run out (end every test with it).
Future<void> deskFullEnd(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 3));
}
