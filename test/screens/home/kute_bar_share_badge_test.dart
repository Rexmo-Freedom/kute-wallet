// The round share button (kute_bar_trade_row.dart, THE SHARE BADGE;
// founder, 5 November 2026, of the 3D glyph in front of Sal: "still not
// clear, kinda hides behind Sal"): Sal's deadpan `idle` face whole inside
// the 52 circle (32, centred, no corner near the edge), and the vector
// share badge (kute_share_badge.dart) over the circle's bottom right, past
// its edge: an ink disc in a white ring on the white circle, inverted (a
// white disc, the ink glyph, a dark ring) on the dark circle of light
// mode (founder, 7 November 2026). The badge's arrow bobs up on
// Sal's blink, driven by his frames, and never under Reduce Motion. A tap
// on the badge is the button's. Labels: "Send to a friend", "Brag about
// it".

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/home/components/kute_bar_trade_row.dart';
import 'package:kute/screens/home/components/kute_bottom_action_bar.dart'
    show KuteSalPill;
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/screens/shared/kute_share_badge.dart';
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/theme/app_theme.dart';

const _market = KuteBarContext(
  label: 'Send to a friend',
  sublabel: 'Send the market',
  clip: 'share',
);

/// The bundle's manifest installed and Sal's `idle` decoded at 3x.
Future<void> _loadIdle(WidgetTester tester) async {
  final manifest = (await tester.runAsync(() async =>
      jsonDecode(await rootBundle.loadString('$kSalSpriteDir/manifest.json'))
          as Map<String, dynamic>))!;
  SalSpriteCache.debugSetManifest(manifest);
  final clip =
      await tester.runAsync(() => SalSpriteCache.clip(kSalShareButtonClip, 3));
  expect(clip, isNotNull, reason: 'idle@3x decodes');
}

Future<void> _pumpButton(WidgetTester tester,
    {VoidCallback? brag, bool reduce = false, VoidCallback? onTap}) async {
  tester.view.physicalSize = const Size(390 * 3, 200 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(430, 932),
    builder: (_, __) => MaterialApp(
      theme: ThemeData(extensions: [AppColorsExtension.light()]),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
        child: child!,
      ),
      home: Scaffold(
        body: Center(
          child: KuteBarShareButton(
            share: KuteBarShare(barContext: _market, brag: brag),
            onTap: (_) => onTap?.call(),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
}

final Finder _share = find.byKey(const ValueKey('kute-bar-share'));
final Finder _circle = find.byKey(const ValueKey('dock-search-pill'));
final Finder _badge = find.byKey(const ValueKey('kute-share-badge'));
Finder get _sal => find.descendant(
    of: _share,
    matching: find.byWidgetPredicate(
        (w) => w is SalSprite && w.clip == kSalShareButtonClip));

/// A one-pixel clip for frames built by hand (the lift reads the frame's
/// name and number only).
late SalClip _pixel;

SalSpriteFrame _frame(int frame, {String name = 'idle'}) =>
    SalSpriteFrame(clip: _pixel, name: name, frame: frame);

/// The arrow's lift the badge paints now.
double _lift(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(find.descendant(
      of: _badge,
      matching: find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is KuteShareGlyphPainter)));
  return (paint.painter! as KuteShareGlyphPainter).lift!.value;
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 1, 1), Paint()..color = Colors.white);
    _pixel = SalClip(
        image: recorder.endRecording().toImageSync(1, 1),
        fps: 24,
        frames: 48,
        columns: 8,
        cellWidth: 1,
        cellHeight: 1,
        loop: true,
        body: false);
  });
  tearDown(() {
    SalSprite.debugPaintLog = null;
    SalSpriteCache.debugSetManifest(null);
  });

  test('the arrow bobs on the idle blink only (frames 36-42, top at 39)', () {
    expect(kSalShareButtonClip, 'idle');
    for (final f in [0, 10, 33, 34, 42, 43, 47]) {
      expect(kuteShareBadgeLift(_frame(f)), 0, reason: 'frame $f');
    }
    expect(kuteShareBadgeLift(_frame(38)), 1);
    expect(kuteShareBadgeLift(_frame(36)), inExclusiveRange(0, 1));
    expect(kuteShareBadgeLift(_frame(40)), inExclusiveRange(0, 1));
    // Another clip (a reaction, search while loading), or a dissolve: none.
    expect(kuteShareBadgeLift(_frame(38, name: 'wink')), 0);
    expect(
        kuteShareBadgeLift(SalSpriteFrame(
            clip: _pixel,
            name: 'idle',
            frame: 38,
            outgoing: _pixel,
            outgoingName: 'wink',
            fade: 0.5)),
        0);
  });

  testWidgets(
      'Sal whole inside the circle, the badge over its bottom right past '
      'the edge, inverted on the dark circle of light mode (a white disc, '
      'the ink glyph, a ring of the circle\'s fill); read aloud as Send to '
      'a friend',
      (tester) async {
    await _pumpButton(tester);
    final circle = tester.getRect(_circle);
    expect(circle.size, const Size.square(KuteSalPill.collapsedSize));
    expect(tester.getRect(_share).size, circle.size);

    // Sal: 32, centred; every corner of his cell well inside the circle.
    expect(_sal, findsOneWidget);
    final sal = tester.getRect(_sal);
    expect(sal.size, const Size.square(kSalShareButtonSalSize));
    expect(sal.center.dx, moreOrLessEquals(circle.center.dx, epsilon: 0.01));
    expect(sal.center.dy, moreOrLessEquals(circle.center.dy, epsilon: 0.01));
    for (final corner in [
      sal.topLeft,
      sal.topRight,
      sal.bottomLeft,
      sal.bottomRight,
    ]) {
      expect((corner - circle.center).distance, lessThan(circle.width / 2 - 2),
          reason: 'breathing room at $corner');
    }

    // The badge: 26 with its ring, centred on the circle's 45 degree
    // radius just inside the edge, past the circle's box by a little.
    final badge = tester.getRect(_badge);
    expect(badge.size, const Size.square(kShareBadgeSize));
    final d = badge.center - circle.center;
    expect(d.dx, moreOrLessEquals(d.dy, epsilon: 0.01));
    expect(
        d.distance, inInclusiveRange(circle.width / 2 - 6, circle.width / 2));
    expect(badge.right - circle.right, inInclusiveRange(1, 4));
    expect(badge.bottom - circle.bottom, inInclusiveRange(1, 4));
    // The circle is the bar's dark fill in light mode (founder, 7 November
    // 2026; kute_bar_surface.dart), and the badge inverts on it.
    final fill = AppColorsExtension.light().textPrimary;
    expect(
        (tester.widget<AnimatedContainer>(_circle).decoration! as BoxDecoration)
            .color,
        fill);
    final ring = tester.widget<Container>(_badge).decoration! as BoxDecoration;
    expect(ring.color, fill);
    expect(ring.shape, BoxShape.circle);
    final disc = tester.widget<DecoratedBox>(
        find.descendant(of: _badge, matching: find.byType(DecoratedBox)).last);
    expect((disc.decoration as BoxDecoration).color, Colors.white);
    expect(tester.widget<KuteShareBadge>(find.byType(KuteShareBadge)).glyphColor,
        kShareBadgeInk);
    expect(_lift(tester), 0);

    expect(find.bySemanticsLabel('Send to a friend'), findsOneWidget);
    expect(
        find.descendant(of: _share, matching: find.byType(Text)), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tap on the badge is the button\'s', (tester) async {
    var taps = 0;
    await _pumpButton(tester, onTap: () => taps++);
    final badge = tester.getRect(_badge);
    final circle = tester.getRect(_circle);
    // On the badge, inside the circle's box.
    await tester.tapAt(Offset(
        (badge.left + circle.right) / 2, (badge.top + circle.bottom) / 2));
    await tester.pump(const Duration(milliseconds: 300));
    expect(taps, 1);
  });

  testWidgets(
      'with the real sheet: Sal loops idle and the arrow comes up as he '
      'blinks', (tester) async {
    await _loadIdle(tester);
    SalSprite.debugPaintLog = [];
    await _pumpButton(tester);
    var peak = 0.0;
    var restAt0 = false;
    // Two loops at 24 fps.
    for (var i = 0; i < 96; i++) {
      await tester.pump(const Duration(microseconds: 1000000 ~/ 24));
      final last = SalSprite.debugPaintLog!.last;
      final lift = _lift(tester);
      expect(lift, kuteShareBadgeLift(last), reason: '$last');
      if (lift > peak) peak = lift;
      if (last.frame == 0 && lift == 0) restAt0 = true;
    }
    final names = SalSprite.debugPaintLog!.map((f) => f.name).toSet();
    expect(names, {kSalShareButtonClip});
    expect(peak, greaterThan(0.9));
    expect(restAt0, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'in profit read aloud as Brag about it; Reduce Motion: frame 0 and '
      'the arrow still', (tester) async {
    await _loadIdle(tester);
    SalSprite.debugPaintLog = [];
    await _pumpButton(tester, brag: () {}, reduce: true);
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(microseconds: 1000000 ~/ 24));
      expect(_lift(tester), 0);
    }
    final log = SalSprite.debugPaintLog!;
    expect(log, isNotEmpty);
    expect(
        log.every((f) => f.name == kSalShareButtonClip && f.frame == 0), isTrue,
        reason: '$log');
    expect(find.bySemanticsLabel('Brag about it'), findsOneWidget);
    expect(_badge, findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('no sheet: happy stands in for Sal, the badge stays',
      (tester) async {
    // The test config's null manifest: nothing reads, nothing breaks.
    await _pumpButton(tester);
    // The failed reads settle on the real event loop (the manifest's
    // future is the test config's, outside the fake clock).
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(
        find.descendant(
            of: _share,
            matching: find
                .byWidgetPredicate((w) => w is SalSprite && w.clip == 'happy')),
        findsOneWidget);
    expect(_badge, findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
