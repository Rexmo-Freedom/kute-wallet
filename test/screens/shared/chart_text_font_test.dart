// The text a chart paints itself (scales, value tags, marker counts,
// trade-line, signal and drawing labels) is set in the app's own face. A
// painter has no theme to inherit from: a TextPainter that names no family
// draws in the system face, beside Inter everywhere else. The scrub card
// is a widget and takes the theme's face like any other text.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/shared/charts/kute_chart_core.dart';

import '../../helpers/source_scan.dart';

const _painters = [
  'lib/screens/polymarket/components/market_chart.dart',
  'lib/screens/hyperliquid/components/hl_charts.dart',
  'lib/screens/shared/charts/kute_chart_trade_lines.dart',
  'lib/screens/shared/charts/kute_chart_signals.dart',
  'lib/screens/shared/charts/kute_chart_drawings.dart',
];

void main() {
  test('the charts\' face is the family the app bundles', () {
    expect(kuteChartFontFamily, 'Inter');
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('- family: Inter'));
    for (final file in ['Regular', 'SemiBold', 'Bold']) {
      expect(pubspec, contains('lib/assets/fonts/Inter-$file.ttf'));
      expect(File('lib/assets/fonts/Inter-$file.ttf').existsSync(), isTrue);
    }
  });

  test('every text a chart painter lays out names that face', () {
    for (final path in _painters) {
      final source = stripComments(File(path).readAsStringSync());
      var from = 0, found = 0;
      while (true) {
        final at = source.indexOf('TextPainter(', from);
        if (at < 0) break;
        found++;
        // The painter's own TextStyle follows within a few lines.
        final end = (at + 400).clamp(0, source.length);
        expect(source.substring(at, end), contains('kuteChartFontFamily'),
            reason: '$path: TextPainter #$found names no font family');
        from = at + 1;
      }
      expect(found, greaterThan(0), reason: path);
    }
  });
}
