// The result sheet's Sal while his sheet is read (kute_success_overlay.dart;
// founder, 9 November 2026: "the last send screen should have our Sal 3D
// one, not the SVG Sal"). Both sends end on this sheet
// (pushKuteSuccessOverlay → KuteConfirmation; the Bitcoin send through
// transaction_modal.dart's PaymentTransactionOverlay). Its SalSprite
// leaves his place empty while the clip is read and draws the pixel rig
// (KuteDogConfirmation) only when the read comes back empty, said once
// in the logs; a send flow warms the three clips on open
// ([KuteConfirmation.warmSal]).

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/screens/shared/kute_dog_scenes.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/kute_bar_test_support.dart';

Widget _app(Widget home, {bool reduceMotion = false}) => ProviderScope(
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          theme: buildLightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(disableAnimations: reduceMotion),
            child: withKuteShellBar(context, child),
          ),
          home: home,
        ),
      ),
    );

Widget _sheet({KuteConfirmationTone tone = KuteConfirmationTone.success}) =>
    KuteConfirmation(
      tone: tone,
      message: 'Bitcoin sent',
      amount: '0.001 BTC',
      contextLine: 'to bc1q…ab12',
      onDone: () {},
    );

/// A face sheet: 48 frames, 8 to a row.
SalClip _face() {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 64, 48), Paint()..color = Colors.brown);
  return SalClip(
      image: recorder.endRecording().toImageSync(64, 48),
      fps: 24,
      frames: 48,
      columns: 8,
      cellWidth: 8,
      cellHeight: 8,
      loop: true,
      body: false);
}

Map<String, dynamic> _entry() => {
      'framing': 'face',
      'fps': 24,
      'frames': 48,
      'columns': 8,
      'loop': true,
      'group': 'reaction',
      'files': {
        '2x': {'file': 'none@2x.webp'},
        '3x': {'file': 'none@3x.webp'},
      },
    };

void _manifest() => SalSpriteCache.debugSetManifest(
    {for (final c in KuteConfirmation.salClips) c: _entry()});

int _density(WidgetTester tester) =>
    SalSpriteCache.densityFor(tester.view.devicePixelRatio);

Finder _sal() => find.descendant(
    of: find.byType(KuteConfirmation), matching: find.byType(SalSprite));

void main() {
  setUp(() {
    KuteConfirmation.debugFeedbackOverride = () async {};
    KuteConfirmation.debugFailureFeedbackOverride = () async {};
    SalSprite.debugPaintLog = [];
  });
  tearDown(() {
    KuteConfirmation.debugFeedbackOverride = null;
    KuteConfirmation.debugFailureFeedbackOverride = null;
    SalSprite.debugPaintLog = null;
    SalSpriteCache.debugReset();
  });

  testWidgets(
      'sheet not warmed (the read still out): his place is empty at his '
      'size, no pixel rig, nothing painted; the clip plays once it lands',
      (tester) async {
    _manifest();
    final loading = Completer<SalClip?>();
    SalSpriteCache.debugPutLoading('happy', _density(tester), loading.future);
    await tester.pumpWidget(_app(_sheet()));
    await tester.pump(const Duration(milliseconds: 1200));

    expect(_sal(), findsOneWidget);
    expect(tester.widget<SalSprite>(_sal()).clip, 'happy');
    expect(find.byType(KuteDogConfirmation), findsNothing,
        reason: 'never the rig for a wait on a read');
    expect(SalSprite.debugPaintLog, isEmpty, reason: 'nothing painted yet');
    // His place is kept: the same square the clip will fill.
    final place = tester.getSize(_sal());
    expect(place.width, closeTo(42.sp, 0.5));
    expect(place.height, closeTo(42.sp, 0.5));

    loading.complete(_face());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(SalSprite.debugPaintLog, isNotEmpty);
    expect(SalSprite.debugPaintLog!.every((f) => f.name == 'happy'), isTrue);
    expect(find.byType(KuteDogConfirmation), findsNothing);
    expect(tester.getSize(_sal()), place);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sheet warmed before the sheet opens: the clip from the first frame',
      (tester) async {
    _manifest();
    final density = _density(tester);
    for (final c in KuteConfirmation.salClips) {
      SalSpriteCache.debugPutClip(c, density, _face());
    }
    await KuteConfirmation.warmSal();
    await tester.pumpWidget(_app(_sheet()));
    await tester.pump();
    expect(SalSprite.debugPaintLog, isNotEmpty,
        reason: 'a cached clip is taken on mount');
    expect(find.byType(KuteDogConfirmation), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'the read comes back empty (no sheet for the clip): the rig, and only '
      'then', (tester) async {
    _manifest();
    SalSpriteCache.debugPutLoading(
        'sad', _density(tester), Future<SalClip?>.value(null));
    await tester.pumpWidget(_app(_sheet(tone: KuteConfirmationTone.failure)));
    await tester.pump();
    await tester.pump();
    expect(find.byType(KuteDogConfirmation), findsOneWidget);
    expect(tester.widget<KuteDogConfirmation>(find.byType(KuteDogConfirmation))
        .mood, KuteDogMood.sad);
    expect(SalSprite.debugPaintLog, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no manifest at all: the rig', (tester) async {
    SalSpriteCache.debugSetManifest(null);
    await tester.pumpWidget(_app(_sheet()));
    await tester.pump();
    await tester.pump();
    expect(find.byType(KuteDogConfirmation), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Reduce Motion: the clip\'s first frame once read, never the rig',
      (tester) async {
    _manifest();
    final loading = Completer<SalClip?>();
    SalSpriteCache.debugPutLoading('happy', _density(tester), loading.future);
    await tester.pumpWidget(_app(_sheet(), reduceMotion: true));
    await tester.pump();
    expect(find.byType(KuteDogConfirmation), findsNothing);
    expect(SalSprite.debugPaintLog, isEmpty);
    loading.complete(_face());
    await tester.pump();
    await tester.pump();
    expect(SalSprite.debugPaintLog!.map((f) => f.frame).toSet(), {0});
    expect(find.byType(KuteDogConfirmation), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('warmSal asks for happy, sad and blink', () async {
    SalSpriteCache.debugSetManifest(null);
    SalSpriteCache.debugRequestLog = [];
    addTearDown(() => SalSpriteCache.debugRequestLog = null);
    await KuteConfirmation.warmSal();
    expect(SalSpriteCache.debugRequestLog,
        containsAll(KuteConfirmation.salClips));
  });
}
