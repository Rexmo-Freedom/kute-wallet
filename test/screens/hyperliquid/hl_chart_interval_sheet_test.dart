// The Advanced chart's Interval sheet (hl_chart_interval_sheet.dart),
// behind the interval button in its top bar (founder, 5 November 2026:
// "Intervals should also be the squares"): the seven intervals as the
// Chart sheet's square cards, 3 + 2 + 2 with the short rows centred (no
// orphan); each card the interval big, what one bar spans and what it
// is good for; the chosen one selected. A tap sets the interval and
// closes the sheet; the market chart's own interval row stays pills.
// Every language's lines fit their card in Inter on a 375 pt phone: the
// meaning on one line, the hint on two, no word broken.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_interval_sheet.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_intervals.dart';
import 'package:kute/screens/shared/app_bottom_sheet.dart';
import 'package:kute/screens/shared/kute_bar_context.dart';
import 'package:kute/theme/app_theme.dart';

import '../../helpers/hl_chart_edit_harness.dart';

const _sheet = ValueKey('hl-interval-sheet');
const _labels = ['1m', '5m', '15m', '1h', '4h', '1D', '1W'];

Finder _card(String interval) =>
    find.byKey(ValueKey('hl-interval-card-$interval'));

bool _picked(WidgetTester tester, String interval) => tester
    .widget<Semantics>(find
        .ancestor(of: _card(interval), matching: find.byType(Semantics))
        .first)
    .properties
    .selected!;

String _interval(WidgetTester tester) =>
    hlEditContainer(tester).read(hlChartLayoutProvider).interval;

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _open(WidgetTester tester) async {
  await tester
      .tap(find.byKey(const ValueKey('hl-chart-edit-interval-button')));
  await _settle(tester);
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets(
      'the interval button opens square cards, not a list: the interval big, '
      'what a bar spans and what it is good for, the chosen one selected',
      (tester) async {
    await pumpHlEditSheet(tester);
    await enterHlEdit(tester);
    await _open(tester);

    expect(find.byKey(_sheet), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(_sheet),
            matching: find.byType(AppBottomSheetListTile)),
        findsNothing);
    final sheet = find.byKey(_sheet);
    for (final iv in kHlCandleIntervals) {
      expect(_card(iv.interval), findsOneWidget);
      expect(
          find.descendant(of: _card(iv.interval), matching: find.text(iv.label)),
          findsOneWidget);
    }
    expect([for (final iv in kHlCandleIntervals) iv.label], _labels);
    for (final text in [
      '1 minute',
      'Live moves',
      '5 minutes',
      "Today's swings",
      '15 minutes',
      'The last day',
      '1 hour',
      'The last few days',
      '4 hours',
      'The last few weeks',
      '1 day',
      'The last months',
      '1 week',
      'The long run',
    ]) {
      expect(find.descendant(of: sheet, matching: find.text(text)),
          findsOneWidget,
          reason: text);
    }
    expect(_interval(tester), '1h');
    expect(_picked(tester, '1h'), isTrue);
    for (final other in ['1m', '5m', '15m', '4h', '1d', '1w']) {
      expect(_picked(tester, other), isFalse, reason: other);
    }
    // A picker: the floating bar is away.
    final bar = kuteBarTop(hlEditContainer(tester).read(kuteBarContextProvider));
    expect(bar?.hidden ?? false, isTrue);
  });

  test('rows never leave one card alone', () {
    expect(hlIntervalRows(7), [3, 2, 2]);
    expect(hlIntervalRows(6), [3, 3]);
    expect(hlIntervalRows(5), [3, 2]);
    expect(hlIntervalRows(4), [2, 2]);
    for (var n = 2; n <= 12; n++) {
      final rows = hlIntervalRows(n);
      expect(rows.reduce((a, b) => a + b), n);
      expect(rows.contains(1), isFalse, reason: '$n');
    }
  });

  testWidgets(
      '3 + 2 + 2, the short rows centred under the full one (no orphan), '
      'every card the same square', (tester) async {
    await pumpHlEditSheet(tester);
    await enterHlEdit(tester);
    await _open(tester);

    final rects = {
      for (final iv in ['1m', '5m', '15m', '1h', '4h', '1d', '1w'])
        iv: tester.getRect(_card(iv)),
    };
    final first = rects['1m']!;
    for (final r in rects.values) {
      expect(r.width, moreOrLessEquals(first.width, epsilon: 0.5));
      expect(r.height, moreOrLessEquals(first.height, epsilon: 0.5));
      // Square, or taller only when text needs it.
      expect(r.height, greaterThanOrEqualTo(r.width - 0.5));
    }
    // Row one: 1m 5m 15m side by side.
    expect(rects['5m']!.top, rects['1m']!.top);
    expect(rects['15m']!.top, rects['1m']!.top);
    expect(rects['5m']!.left, greaterThan(rects['1m']!.right));
    expect(rects['15m']!.left, greaterThan(rects['5m']!.right));
    final rowOneCentre = (rects['1m']!.left + rects['15m']!.right) / 2;
    // Rows two and three: pairs, centred on the row above.
    double centre(String a, String b) => (rects[a]!.left + rects[b]!.right) / 2;
    expect(rects['1h']!.top, greaterThan(rects['1m']!.bottom));
    expect(rects['4h']!.top, rects['1h']!.top);
    expect(centre('1h', '4h'), moreOrLessEquals(rowOneCentre, epsilon: 0.5));
    expect(rects['1d']!.top, greaterThan(rects['1h']!.bottom));
    expect(rects['1w']!.top, rects['1d']!.top);
    expect(centre('1d', '1w'), moreOrLessEquals(rowOneCentre, epsilon: 0.5));
  });

  testWidgets('a tap sets the interval for the chart and closes the sheet',
      (tester) async {
    await pumpHlEditSheet(tester);
    await enterHlEdit(tester);
    await _open(tester);

    await tester.tap(_card('5m'));
    await _settle(tester);
    expect(find.byKey(_sheet), findsNothing);
    expect(_interval(tester), '5m');
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('hl-chart-edit-interval-button')),
            matching: find.text('5m')),
        findsOneWidget);

    // Opened again: 5m is the chosen one.
    await _open(tester);
    expect(_picked(tester, '5m'), isTrue);
    expect(_picked(tester, '1h'), isFalse);

    // The close leaves the interval as it was.
    await tester
        .tap(find.byKey(const ValueKey('hl-interval-sheet-close')).last);
    await _settle(tester);
    expect(find.byKey(_sheet), findsNothing);
    expect(_interval(tester), '5m');
  });

  testWidgets('the market chart keeps its interval row of pills',
      (tester) async {
    await pumpHlEditSheet(tester);
    expect(find.byKey(const ValueKey('hl-interval-row')), findsOneWidget);
    expect(find.byKey(const ValueKey('hl-chart-edit-interval-button')),
        findsNothing);
  });

  for (final width in [320.0, 375.0]) {
    testWidgets('seven pills stay whole beside the chart button at $width',
        (tester) async {
      await pumpHlEditSheet(tester, width: width, height: 700);
      final row = find.byKey(const ValueKey('hl-interval-row'));
      for (final label in _labels) {
        final text = find.descendant(of: row, matching: find.text(label));
        expect(text, findsOneWidget, reason: label);
        final p = tester.renderObject<RenderParagraph>(text);
        final natural = TextPainter(
          text: p.text,
          textDirection: TextDirection.ltr,
          textScaler: p.textScaler,
          maxLines: 1,
        )..layout();
        expect(natural.width, lessThanOrEqualTo(p.constraints.maxWidth),
            reason: '$label is cut');
        natural.dispose();
      }
    });
  }

  group('every language', () {
    setUpAll(() async {
      for (final family in [GoogleFonts.inter().fontFamily!, 'Inter']) {
        final inter = FontLoader(family);
        for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
          final file = File('lib/assets/fonts/Inter-$f.ttf');
          if (file.existsSync()) {
            inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
          }
        }
        await inter.load();
      }
    });

    for (final locale in AppLocalizations.supportedLocales) {
      testWidgets('${locale.languageCode}: every line fits its card at 375',
          (tester) async {
        tester.view.devicePixelRatio = 3;
        tester.view.physicalSize = const Size(375, 812) * 3;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(ProviderScope(
          child: ScreenUtilInit(
            designSize: const Size(430, 932),
            builder: (_, __) => MaterialApp(
              locale: locale,
              theme: buildLightTheme(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const Scaffold(
                body: Align(
                  alignment: Alignment.bottomCenter,
                  child: HlIntervalSheet(current: '1h'),
                ),
              ),
            ),
          ),
        ));
        await tester.pump();

        final l10n = lookupAppLocalizations(locale);
        final lines = {
          for (final iv in kHlCandleIntervals) ...{
            hlIntervalMeaning(l10n, iv): 1,
            hlIntervalHint(l10n, iv): 2,
          },
        };
        var checked = 0;
        for (final iv in kHlCandleIntervals) {
          final paragraphs = tester.renderObjectList<RenderParagraph>(
              find.descendant(
                  of: _card(iv.interval), matching: find.byType(RichText)));
          for (final p in paragraphs) {
            final text = p.text.toPlainText();
            final maxLines = lines[text];
            if (maxLines == null) continue;
            checked++;
            expect(p.didExceedMaxLines, isFalse,
                reason: '"$text" takes more than $maxLines line(s)');
            final width = p.constraints.maxWidth;
            for (final word in text.split(RegExp(r'\s+'))) {
              if (word.isEmpty) continue;
              final w = TextPainter(
                text: TextSpan(text: word, style: p.text.style),
                textDirection: TextDirection.ltr,
                textScaler: p.textScaler,
                maxLines: 1,
              )..layout();
              expect(w.width, lessThanOrEqualTo(width),
                  reason: '"$word" of "$text" breaks mid-word');
              w.dispose();
            }
          }
        }
        expect(checked, 2 * kHlCandleIntervals.length);
        // Every card as tall as the others.
        final heights = {
          for (final iv in kHlCandleIntervals)
            tester.getSize(_card(iv.interval)).height.round(),
        };
        expect(heights, hasLength(1));
      });
    }
  });
}
