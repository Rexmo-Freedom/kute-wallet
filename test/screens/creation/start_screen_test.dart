// The Start screen ("Change starts with you.", start.dart) without the
// lightning burst around Sal (founder, 27 November 2026): no spark
// painter, Sal idling in the same box, the two actions; the layout where
// it was on the phone, MEDIUM and EXPANDED, light and dark; the split
// screens' brand half the same. Shot when asked: DESK_FULL_RENDER=<dir>
// (names `t_start_*`).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/platform/kute_wide_frames.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/creation/set_pin.dart';
import 'package:kute/screens/creation/start.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/sal_sprite.dart';
import 'package:kute/services/tracking_service.dart';

import '../../helpers/kute_bar_test_support.dart';
import '../../render/desk_full_support.dart';

List<Override> _fresh() {
  final never = Completer<Settings>();
  return [initialSettingsProvider.overrideWith((ref) => never.future)];
}

/// No CustomPaint under [root] paints a spark burst.
void _expectNoSparks(WidgetTester tester, Finder root) {
  final painters = tester
      .widgetList<CustomPaint>(
          find.descendant(of: root, matching: find.byType(CustomPaint)))
      .expand((p) => [p.painter, p.foregroundPainter])
      .whereType<CustomPainter>()
      .map((p) => p.runtimeType.toString());
  expect(painters.where((n) => n.toLowerCase().contains('spark')), isEmpty);
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    TrackingService.setDisabled(true);
  });

  for (final (label, size) in const [
    ('430x932', Size(430, 932)),
    ('820x1180', Size(820, 1180)),
    ('1440x900', Size(1440, 900)),
  ]) {
    for (final dark in [false, true]) {
      final mode = dark ? 'dark' : 'light';
      testWidgets('start $label $mode: Sal and the two actions, no sparks',
          (tester) async {
        await deskFullAssets(tester);
        await pumpDeskPage(tester,
            size: size,
            dark: dark,
            page: const Start(),
            mode: KuteWideMode.column,
            overrides: _fresh(),
            frames: 30);
        expect(tester.takeException(), isNull);
        _expectNoSparks(tester, find.byType(Start));
        final sal = find.descendant(
            of: find.byType(Start), matching: find.byType(SalSprite));
        expect(sal, findsOneWidget);
        expect(tester.widget<SalSprite>(sal).clip, 'body_idle');
        expect(
            find.descendant(
                of: find.byType(Start), matching: find.byType(AppTextButton)),
            findsOneWidget);
        expect(find.text('I already have an account'), findsOneWidget);
        expect(kuteBarPrimaryContext(tester).label, 'Create account');
        // Sal centred in the 220 box the burst filled; the headline under.
        final box = tester.getRect(find
            .ancestor(of: sal, matching: find.byType(SizedBox))
            .first);
        expect(tester.getCenter(sal).dx, closeTo(box.center.dx, 0.5));
        expect(tester.getCenter(sal).dy, closeTo(box.center.dy, 0.5));
        final headline = tester.getRect(find
            .descendant(
                of: find.byType(Start), matching: find.byType(RichText))
            .evaluate()
            .map((e) => find.byWidget(e.widget))
            .firstWhere((f) => tester
                .widget<RichText>(f)
                .text
                .toPlainText()
                .contains('Change starts')));
        expect(headline.top, greaterThan(box.bottom));
        await deskFullShoot(tester, 't_start_${label}_$mode');
        await deskFullEnd(tester);
      });
    }
  }

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets('the split screens\' brand half 1440x900 $mode: no sparks',
        (tester) async {
      await deskFullAssets(tester);
      await pumpDeskPage(tester,
          size: const Size(1440, 900),
          dark: dark,
          page: const SetPin(),
          mode: KuteWideMode.split,
          overrides: _fresh());
      expect(tester.takeException(), isNull);
      expect(find.byType(StartBrandSide), findsOneWidget);
      _expectNoSparks(tester, find.byType(StartBrandSide));
      expect(
          find.descendant(
              of: find.byType(StartBrandSide),
              matching: find.byType(SalSprite)),
          findsOneWidget);
      await deskFullShoot(tester, 't_start_brand_1440x900_$mode');
      await deskFullEnd(tester);
    });
  }
}
