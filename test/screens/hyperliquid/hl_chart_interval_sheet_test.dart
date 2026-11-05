// The Advanced chart's Interval sheet (hl_chart_interval_sheet.dart),
// behind the interval button in its top bar (founder, 5 November 2026:
// "Intervals should also be the squares"): the five intervals as the
// Chart sheet's square cards, three to a row and the last two centred
// under them; each card the interval big, what one bar spans and what it
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
const _labels = ['1m', '5m', '1h', '1D', '1W'];

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
      '1 hour',
      'The last few days',
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
    for (final other in ['1m', '5m', '1d', '1w']) {
      expect(_picked(tester, other), isFalse, reason: other);
    }
    // A picker: the floating bar is away.
    final bar = kuteBarTop(hlEditContainer(tester).read(kuteBarContextProvider));
    expect(bar?.hidden ?? false, isTrue);
  });

  testWidgets(
      'three to a row, the last two centred under them (no orphan), every '
      'card the same square', (tester) async {
    await pumpHlEditSheet(tester);
    await enterHlEdit(tester);
    await _open(tester);

    final rects = {
      for (final iv in ['1m', '5m', '1h', '1d', '1w'])
        iv: tester.getRect(_card(iv)),
    };
    final first = rects['1m']!;
    for (final r in rects.values) {
      expect(r.width, moreOrLessEquals(first.width, epsilon: 0.5));
      expect(r.height, moreOrLessEquals(first.height, epsilon: 0.5));
      // Square, or taller only when text needs it.
      expect(r.height, greaterThanOrEqualTo(r.width - 0.5));
    }
    // Row one: 1m 5m 1h side by side.
    expect(rects['5m']!.top, rects['1m']!.top);
    expect(rects['1h']!.top, rects['1m']!.top);
    expect(rects['5m']!.left, greaterThan(rects['1m']!.right));
    expect(rects['1h']!.left, greaterThan(rects['5m']!.right));
    // Row two: 1D 1W under them, centred on the row above.
    expect(rects['1d']!.top, greaterThan(rects['1m']!.bottom));
    expect(rects['1w']!.top, rects['1d']!.top);
    final rowOneCentre = (rects['1m']!.left + rects['1h']!.right) / 2;
    final rowTwoCentre = (rects['1d']!.left + rects['1w']!.right) / 2;
    expect(rowTwoCentre, moreOrLessEquals(rowOneCentre, epsilon: 0.5));
    expect(rects['1d']!.left, greaterThan(rects['1m']!.left));
    expect(rects['1w']!.right, lessThan(rects['1h']!.right));
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
