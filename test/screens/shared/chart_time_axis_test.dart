// The shared time axis (kute_chart_time_axis.dart): the format follows the
// window's span, the end reads "Now" at the live edge, the row keeps time
// left to right in any text direction. And the zoom nudge's seen flag
// (kute_chart_zoom_hint.dart): one per device, kept across a restart.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:kute/screens/shared/charts/kute_chart_time_axis.dart';
import 'package:kute/screens/shared/charts/kute_chart_zoom_hint.dart';
import 'package:kute/theme/app_theme.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('pt');
  });

  group('kuteAxisTime', () {
    final t = DateTime(2025, 9, 12, 14, 5);
    test('under a day: the time of day', () {
      expect(kuteAxisTime(t, const Duration(hours: 6), 'en'), '14:05');
      expect(kuteAxisTime(t, const Duration(hours: 23, minutes: 59), 'en'),
          '14:05');
    });
    test('under a year: the day', () {
      expect(kuteAxisTime(t, const Duration(days: 1), 'en'), 'Sep 12');
      expect(kuteAxisTime(t, const Duration(days: 30), 'en'), 'Sep 12');
      expect(kuteAxisTime(t, const Duration(days: 364), 'en'), 'Sep 12');
    });
    test('a year or more: the month', () {
      expect(kuteAxisTime(t, const Duration(days: 365), 'en'), 'Sep 2025');
      expect(kuteAxisTime(t, const Duration(days: 900), 'en'), 'Sep 2025');
    });
    test('in the app\'s language', () {
      expect(kuteAxisTime(t, const Duration(days: 30), 'pt'),
          DateFormat.MMMd('pt').format(t));
      expect(kuteAxisTime(t, const Duration(days: 30), 'pt'), contains('set'));
    });
  });

  group('kuteTimeAxisTexts', () {
    final start = DateTime(2025, 9, 12, 9, 0);
    final end = DateTime(2025, 9, 12, 15, 30);
    test('at the live edge the end is "Now"', () {
      final t = kuteTimeAxisTexts(
          start: start, end: end, live: true, nowLabel: 'Now', locale: 'en');
      expect(t.start, '09:00');
      expect(t.end, 'Now');
    });
    test('panned away from it, the end is its time', () {
      final t = kuteTimeAxisTexts(
          start: start, end: end, live: false, nowLabel: 'Now', locale: 'en');
      expect(t.end, '15:30');
    });
    test('the span sets both labels\' format', () {
      final t = kuteTimeAxisTexts(
          start: DateTime(2025, 8, 1),
          end: DateTime(2025, 9, 12),
          live: false,
          nowLabel: 'Now',
          locale: 'en');
      expect(t.start, 'Aug 1');
      expect(t.end, 'Sep 12');
    });
  });

  testWidgets('right to left: time still runs left to right', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildLightTheme(),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: SizedBox(
            width: 300,
            child: KuteTimeAxis(start: 'Sep 12', end: 'Now'),
          ),
        ),
      ),
    ));
    final s = tester.getRect(find.text('Sep 12'));
    final e = tester.getRect(find.text('Now'));
    expect(s.left, lessThan(e.left));
    expect(s.left, closeTo(0, 0.5));
    expect(e.right, closeTo(300, 0.5));
    expect(tester.getSize(find.byType(KuteTimeAxis)).height,
        kKuteTimeAxisHeight);
  });

  group('the nudge\'s flag', () {
    tearDown(KuteZoomHint.debugReset);

    test('the amount: nothing at either end, the depth halfway', () {
      expect(kuteZoomNudgeAmount(0), 0);
      expect(kuteZoomNudgeAmount(1), closeTo(0, 1e-12));
      expect(kuteZoomNudgeAmount(0.5), closeTo(kKuteZoomNudgeDepth, 1e-12));
      expect(kuteZoomNudgeAmount(0.25), closeTo(kKuteZoomNudgeDepth / 2, 1e-12));
    });

    test('with no settings box it counts as seen: never a nudge', () {
      KuteZoomHint.debugReset();
      expect(KuteZoomHint.seen, isTrue);
      expect(KuteZoomHint.claim(), isFalse);
    });

    test('claimed once, then seen, and still seen after a restart', () async {
      final dir = await Directory.systemTemp.createTemp('kute_zoom_hint');
      addTearDown(() => dir.delete(recursive: true));
      Hive.init(dir.path);
      await Hive.openBox('settings');
      KuteZoomHint.debugReset();
      expect(KuteZoomHint.seen, isFalse);
      expect(KuteZoomHint.claim(), isTrue);
      expect(KuteZoomHint.claim(), isFalse);
      await Hive.box('settings').flush();
      await Hive.close();

      // A restart: a fresh session reads the box again.
      Hive.init(dir.path);
      await Hive.openBox('settings');
      KuteZoomHint.debugReset();
      expect(Hive.box('settings').get(KuteZoomHint.key), isTrue);
      expect(KuteZoomHint.seen, isTrue);
      expect(KuteZoomHint.claim(), isFalse);
      await Hive.close();
    });
  });
}
