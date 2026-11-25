// The Advanced chart's grouped tool rail (hl_drawing_rail.dart): each
// group shows its last-picked tool, a tap takes it, and its fly-out opens
// from a second tap, a long press, the corner mark or a right click.
// Picking from the fly-out takes the tool, makes it the face (kept in the
// settings box) and closes the fly-out. A double tap still keeps a tool.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_ce/hive.dart';
import 'package:kute/models/chart_drawing.dart';
import 'package:kute/providers/chart_drawings_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_drawing_rail.dart';
import 'package:kute/screens/hyperliquid/components/hl_drawing_tools.dart';

import '../../helpers/hl_chart_edit_harness.dart';

Finder _group(HlToolGroupId id) => find.descendant(
    of: find.byKey(ValueKey('hl-chart-rail-group-${id.name}')),
    matching: find.byType(HlRailButton));

Finder _flyout(HlToolGroupId id) =>
    find.byKey(ValueKey('hl-tool-flyout-${id.name}'));

bool _selected(WidgetTester tester, Finder button) {
  final pill = find.descendant(
      of: button, matching: find.byType(AnimatedContainer));
  final box = tester.widget<AnimatedContainer>(pill).decoration as BoxDecoration;
  return box.color != Colors.transparent;
}

/// A short real-time pause, so two taps never read as a double tap.
Future<void> _apart(WidgetTester tester) => tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 400)));

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('groups and faces', () {
    test('a group shows its everyday tool until another is picked', () {
      final lines =
          kHlToolGroups.firstWhere((g) => g.id == HlToolGroupId.lines);
      final positions =
          kHlToolGroups.firstWhere((g) => g.id == HlToolGroupId.positions);
      expect(hlGroupFace(lines, const {}), ChartDrawingTool.trendline);
      expect(hlGroupFace(positions, const {}),
          ChartDrawingTool.dateAndPriceRange);
      expect(hlGroupFace(lines, const {'lines': 'level'}),
          ChartDrawingTool.level);
      // A tool from another group, or one this build lacks: the default.
      expect(hlGroupFace(lines, const {'lines': 'rect'}),
          ChartDrawingTool.trendline);
      expect(hlGroupFace(lines, const {'lines': 'gannFan'}),
          ChartDrawingTool.trendline);
      // Every tool sits in exactly one group.
      final placed = [
        for (final g in kHlToolGroups)
          for (final t in g.tools)
            if (t != null) t
      ];
      expect(placed.toSet().length, placed.length);
    });

    test('the last-picked faces are kept in the settings box', () async {
      final dir = await Directory.systemTemp.createTemp('kute-rail-faces-');
      Hive.init(dir.path);
      final box = await Hive.openBox('settings');
      addTearDown(() async {
        await Hive.close();
        await dir.delete(recursive: true);
      });
      var container = ProviderContainer();
      expect(container.read(hlDrawingRailFacesProvider), isEmpty);
      container
          .read(hlDrawingRailFacesProvider.notifier)
          .setFace('lines', ChartDrawingTool.priceLine);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
          jsonDecode(box.get(HlDrawingRailFacesNotifier.debugStorageKey)
              as String),
          {'lines': 'priceLine'});
      container.dispose();
      // A newer build's tool in the store is ignored.
      await box.put(HlDrawingRailFacesNotifier.debugStorageKey,
          jsonEncode({'lines': 'priceLine', 'shapes': 'gannBox'}));
      container = ProviderContainer();
      expect(container.read(hlDrawingRailFacesProvider),
          {'lines': 'priceLine'});
      container.dispose();
    });
  });

  group('on the rail', () {
    testWidgets(
        'a tap takes the face; a second tap opens the fly-out; a pick takes '
        'the tool, becomes the face and closes it', (tester) async {
      await pumpHlEditSheet(tester);
      await enterHlEdit(tester);
      final lines = _group(HlToolGroupId.lines);
      expect(find.byKey(const ValueKey('hl-chart-rail-trendline')),
          findsOneWidget);
      // The group of several tools wears the corner mark; one of one
      // tool (Shapes) does not.
      expect(
          find.descendant(
              of: lines,
              matching: find.byKey(const ValueKey('hl-rail-more-mark'))),
          findsOneWidget);
      expect(
          find.descendant(
              of: _group(HlToolGroupId.shapes),
              matching: find.byKey(const ValueKey('hl-rail-more-mark'))),
          findsNothing);

      await tester.tap(lines);
      await tester.pump();
      expect(_selected(tester, lines), isTrue);
      expect(_flyout(HlToolGroupId.lines), findsNothing);
      await _apart(tester);
      await tester.tap(lines);
      await _settle(tester);
      expect(_flyout(HlToolGroupId.lines), findsOneWidget);
      // The tool in hand is the marked row.
      final row = find.byKey(const ValueKey('hl-tool-flyout-trendline'));
      expect(
          find.descendant(
              of: row, matching: find.byIcon(Icons.check_circle_rounded)),
          findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('hl-tool-flyout-level')));
      await _settle(tester);
      expect(_flyout(HlToolGroupId.lines), findsNothing);
      // The horizontal line is in hand and is now the group's face.
      final level = find.byKey(const ValueKey('hl-chart-rail-level'));
      expect(level, findsOneWidget);
      expect(find.byKey(const ValueKey('hl-chart-rail-trendline')),
          findsNothing);
      expect(_selected(tester, level), isTrue);
      expect(hlEditContainer(tester).read(hlDrawingRailFacesProvider),
          {'lines': 'level'});
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'a long press, the corner mark and a right click each open the '
        'fly-out; closing it takes nothing', (tester) async {
      await pumpHlEditSheet(tester);
      await enterHlEdit(tester);
      final lines = _group(HlToolGroupId.lines);
      final cursor = find.byKey(const ValueKey('hl-chart-rail-cursor'));

      await tester.longPress(lines);
      await _settle(tester);
      expect(_flyout(HlToolGroupId.lines), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('hl-tool-flyout-close')));
      await _settle(tester);
      expect(_flyout(HlToolGroupId.lines), findsNothing);
      expect(_selected(tester, cursor), isTrue);

      // The corner mark: the button's bottom-right corner.
      await tester.tapAt(tester.getBottomRight(lines) - const Offset(5, 5));
      await _settle(tester);
      expect(_flyout(HlToolGroupId.lines), findsOneWidget);
      // An outside tap closes it.
      await tester.tapAt(const Offset(200, 40));
      await _settle(tester);
      expect(_flyout(HlToolGroupId.lines), findsNothing);
      expect(_selected(tester, cursor), isTrue);

      // A right click.
      await tester.tap(lines, buttons: kSecondaryButton);
      await _settle(tester);
      expect(_flyout(HlToolGroupId.lines), findsOneWidget);
      await tester.tap(find.byKey(
          const ValueKey('hl-tool-flyout-priceLine')));
      await _settle(tester);
      expect(_selected(tester, lines), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a double tap on a group keeps its tool; a tap then stops it',
        (tester) async {
      await pumpHlEditSheet(tester);
      await enterHlEdit(tester);
      final lines = _group(HlToolGroupId.lines);
      await tester.tap(lines);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(lines);
      await tester.pump();
      expect(find.byKey(const ValueKey('hl-rail-sticky')), findsOneWidget);
      expect(_flyout(HlToolGroupId.lines), findsNothing);
      await _apart(tester);
      await tester.tap(lines);
      await _settle(tester);
      expect(find.byKey(const ValueKey('hl-rail-sticky')), findsNothing);
      expect(_selected(tester, lines), isFalse);
      expect(_flyout(HlToolGroupId.lines), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a wide window opens the fly-out as a panel beside the rail',
        (tester) async {
      await pumpHlEditSheet(tester, width: 1024, height: 768);
      await enterHlEdit(tester);
      final lines = _group(HlToolGroupId.lines);
      await tester.longPress(lines);
      await _settle(tester);
      // No sheet: the panel's rows, to the right of the button.
      expect(_flyout(HlToolGroupId.lines), findsNothing);
      final row = find.byKey(const ValueKey('hl-tool-flyout-priceLine'));
      expect(row, findsOneWidget);
      expect(tester.getTopLeft(row).dx,
          greaterThan(tester.getTopRight(lines).dx));
      await tester.tap(row);
      await _settle(tester);
      expect(row, findsNothing);
      expect(find.byKey(const ValueKey('hl-chart-rail-priceLine')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
