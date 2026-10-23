import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/polymarket/components/market_chart.dart'
    show polyChartDomain, polyChartTagPct;
import 'package:kute/screens/polymarket/components/poly_chart_tags.dart';

// The value tags of a Predictions chart (poly_chart_tags.dart): name and
// chance, one column past the end of the lines, never over each other or
// level with another line's end dot, never cut (a name that does not fit
// leaves the chance alone), and never a pile. The column's width, font and
// names (polyTagStyle).

const _drawH = 214.0;
const _plotW = 349.0;
const _h = 18.0;
const _r = 4.0;

/// The widest a pill may be: a tag column sized for names like these.
const _maxW = 140.0;

/// A pill's text width: 6.2 px a character, close to the chart's 10.5 px
/// bold figures.
double _measure(String text) => text.runes.length * 6.2;

List<PolyTagLine> _lines(List<(String, double)> outcomes) {
  final prices = [for (final o in outcomes) o.$2];
  final lo = prices.reduce((a, b) => a < b ? a : b);
  final hi = prices.reduce((a, b) => a > b ? a : b);
  final d = polyChartDomain(lo - 0.1, hi + 0.05);
  double y(double p) => _drawH * (1 - (p - d.minY) / (d.maxY - d.minY));
  return [
    for (final o in outcomes)
      (
        y: y(o.$2),
        price: o.$2,
        pct: polyChartTagPct(o.$2),
        name: polyChartShortName(o.$1),
      ),
  ];
}

List<PolyTagPlacement> _layout(List<PolyTagLine> lines) => polyLayoutValueTags(
      lines: lines,
      maxWidth: _maxW,
      drawH: _drawH,
      tagHeight: _h,
      measure: _measure,
      dotRadius: _r,
    );

/// No two pills overlap, every pill is inside the plot and the column and
/// none sits level with another line's end dot; no text is cut.
void _expectClean(List<PolyTagLine> lines, List<PolyTagPlacement> tags) {
  final sorted = [...tags]..sort((a, b) => a.top.compareTo(b.top));
  for (var k = 0; k < sorted.length; k++) {
    final t = sorted[k];
    expect(t.top, greaterThanOrEqualTo(-0.01), reason: '${t.text} above plot');
    expect(t.top + _h, lessThanOrEqualTo(_drawH + 0.01),
        reason: '${t.text} under plot');
    if (k > 0) {
      expect(t.top, greaterThanOrEqualTo(sorted[k - 1].top + _h),
          reason: '${t.text} overlaps ${sorted[k - 1].text}');
    }
    for (var j = 0; j < lines.length; j++) {
      if (j == t.index) continue;
      final y = lines[j].y;
      final covers = y + _r > t.top + 0.5 && y - _r < t.top + _h - 0.5;
      expect(covers, isFalse,
          reason: '${t.text} covers the end dot of line $j');
    }
    expect(t.width, lessThanOrEqualTo(_maxW + 0.01));
    expect(t.text, isNot(contains('…')));
  }
}

String _textOf(List<PolyTagPlacement> tags, int index) =>
    tags.firstWhere((t) => t.index == index).text;

void main() {
  group('polyChartShortName', () {
    test('a short name as it is, a long one without its first word', () {
      expect(polyChartShortName('Yes'), 'Yes');
      expect(polyChartShortName('Draw'), 'Draw');
      expect(polyChartShortName('Real Madrid'), 'Real Madrid');
      expect(polyChartShortName('Himeno Sakatsume'), 'Sakatsume');
      expect(polyChartShortName('Viktoria Hruncakova'), 'Hruncakova');
      expect(polyChartShortName('  '), '');
    });
  });

  group('polyChartOutcomeName', () {
    test('a market question names its candidate', () {
      expect(
          polyChartOutcomeName('Will Flávio Bolsonaro win the 2026 Brazilian '
              'presidential election?'),
          'Flávio Bolsonaro');
      expect(polyChartOutcomeName('Will Gavin Newsom be the nominee?'),
          'Gavin Newsom');
      expect(polyChartShortName('Will Luiz Inácio Lula da Silva win the 2026 '
              'Brazilian presidential election?'),
          'Inácio Lula da Silva');
    });

    test('a name as it is; a question naming no one, nothing', () {
      expect(polyChartOutcomeName(' Real Madrid '), 'Real Madrid');
      expect(polyChartOutcomeName('Will the Fed cut rates in December?'), '');
      expect(polyChartOutcomeName('Bitcoin above 100k on Friday?'), '');
    });
  });

  group('polyTagStyle', () {
    /// 5.6 px a character at 10.5 px (the chart's bold Inter, names and
    /// figures together), in proportion at other sizes.
    double measure(String text, double fs) =>
        text.runes.length * 5.6 * fs / 10.5;

    /// A 393pt phone's chart.
    const phone = 361.0;

    PolyTagStyle style(List<String> labels, {double width = phone}) =>
        polyTagStyle(labels: labels, width: width, measure: measure);

    test('short names at full size, the column as wide as the widest', () {
      final s = style(['Viktoria Hruncakova', 'Himeno Sakatsume']);
      expect(s.names, ['Hruncakova', 'Sakatsume']);
      expect(s.fontSize, kPolyTagFontSizes.first);
      expect(
          s.gutter,
          closeTo(
              measure('Hruncakova $kPolyTagPctTemplate', s.fontSize) +
                  10 +
                  kPolyTagLead,
              0.01));
    });

    test('never wider than its share of the chart, never an ellipsis', () {
      for (final labels in [
        ['Yes'],
        ['Will Flávio Bolsonaro win the 2026 Brazilian presidential election?',
          'Will Luiz Inácio Lula da Silva win the 2026 Brazilian '
              'presidential election?'],
        ['Supercalifragilisticexpialidocious', 'Alexandria Ocasio-Cortez'],
      ]) {
        for (final width in [260.0, 343.0, phone]) {
          final s = style(labels, width: width);
          expect(s.gutter, lessThanOrEqualTo(width * kPolyTagMaxGutterShare));
          for (final n in s.names) {
            expect(n, isNot(contains('…')));
            if (n.isNotEmpty) {
              expect(
                  measure('$n $kPolyTagPctTemplate', s.fontSize) + 10,
                  lessThanOrEqualTo(s.gutter - kPolyTagLead + 0.01));
            }
          }
        }
      }
    });

    test('a long name drops its leading words, then the font steps down', () {
      final s = style(['Will Luiz Inácio Lula da Silva win the 2026 Brazilian '
          'presidential election?']);
      expect(s.names.single, 'Lula da Silva');
      expect(s.fontSize, lessThan(kPolyTagFontSizes.first));
    });

    test('a name that fits at no size: the chance alone', () {
      final s = style(['Supercalifragilisticexpialidocious']);
      expect(s.names.single, '');
      expect(s.gutter,
          closeTo(measure(kPolyTagPctTemplate, s.fontSize) + 10 + kPolyTagLead,
              0.01));
    });

    test('two lines with the same short name are told apart', () {
      final s = style(['Flávio Bolsonaro', 'Michelle Bolsonaro']);
      expect(s.names, ['F. Bolsonaro', 'M. Bolsonaro']);
    });

    test('a binary line keeps the column narrow', () {
      final s = style(['Yes']);
      expect(s.names.single, 'Yes');
      expect(s.gutter, lessThan(_plotW * 0.25));
    });
  });

  test('a tennis match: each line its surname and chance', () {
    final lines = _lines(
        [('Viktoria Hruncakova', 0.275), ('Himeno Sakatsume', 0.725)]);
    final tags = _layout(lines);
    _expectClean(lines, tags);
    expect(_textOf(tags, 0), 'Hruncakova 27.5%');
    expect(_textOf(tags, 1), 'Sakatsume 72.5%');
    // Each on its own line's end.
    for (final t in tags) {
      expect((t.top + _h / 2 - lines[t.index].y).abs(), lessThan(0.5));
    }
  });

  test('a binary market: "Yes 18%"', () {
    final lines = _lines([('Yes', 0.18)]);
    final tags = _layout(lines);
    expect(tags.single.text, 'Yes 18%');
  });

  test('a name too long for the column is never cut: the chance alone', () {
    final lines = _lines([('Supercalifragilisticexpialidocious', 0.4)]);
    final tags = _layout(lines);
    expect(tags.single.text, '40%');
    expect(tags.single.width, lessThanOrEqualTo(_maxW));
  });

  test('a line with no name writes its chance alone', () {
    final lines = _lines([('', 0.62)]);
    expect(_layout(lines).single.text, '62%');
  });

  test('the landfall case: 53 alone, 28 / 28 / 27.5 stacked, named', () {
    final lines = _lines([
      ('Louisiana', 0.53),
      ('Mississippi', 0.28),
      ('Alabama', 0.28),
      ('Florida', 0.275),
    ]);
    final tags = _layout(lines);
    expect(tags, hasLength(4));
    _expectClean(lines, tags);
    expect(_textOf(tags, 0), 'Louisiana 53%');
    // The stack sits in the column past the lines, hiding none of them:
    // each pill names its line.
    expect(_textOf(tags, 1), 'Mississippi 28%');
    expect(_textOf(tags, 2), 'Alabama 28%');
    expect(_textOf(tags, 3), 'Florida 27.5%');
    // The higher lines' tags above the dots, the lowest's under them,
    // each within two pills of its own line.
    final florida = tags.firstWhere((t) => t.index == 3);
    expect(florida.top, greaterThan(lines[3].y));
    for (final t in tags) {
      expect((t.top + _h / 2 - lines[t.index].y).abs(),
          lessThanOrEqualTo(kPolyTagMaxShift * _h));
    }
  });

  test('two lines half a point apart: named, one above and one under', () {
    final lines = _lines([('Over 2.5', 0.505), ('Under 2.5', 0.50)]);
    final tags = _layout(lines);
    expect(tags, hasLength(2));
    _expectClean(lines, tags);
    expect(_textOf(tags, 0), 'Over 2.5 50.5%');
    expect(_textOf(tags, 1), 'Under 2.5 50%');
    final over = tags.firstWhere((t) => t.index == 0);
    final under = tags.firstWhere((t) => t.index == 1);
    expect(over.top + _h, lessThanOrEqualTo(lines[0].y - _r));
    expect(under.top, greaterThanOrEqualTo(lines[1].y + _r));
  });

  test('two lines a point apart', () {
    final lines = _lines([('Arsenal', 0.27), ('Draw', 0.26)]);
    final tags = _layout(lines);
    expect(tags, hasLength(2));
    _expectClean(lines, tags);
  });

  test('two lines a point apart at the top edge: both under their dots', () {
    final lines = [
      (y: 3.0, price: 0.99, pct: '99%', name: 'Sinner'),
      (y: 6.0, price: 0.98, pct: '98%', name: 'Alcaraz'),
    ];
    final tags = _layout(lines);
    expect(tags, hasLength(2));
    _expectClean(lines, tags);
    for (final t in tags) {
      expect(t.top, greaterThan(6.0));
    }
  });

  test('two lines a point apart at the bottom edge: both above their dots',
      () {
    final lines = [
      (y: _drawH - 6, price: 0.02, pct: '2%', name: 'Netherlands'),
      (y: _drawH - 2, price: 0.01, pct: '1%', name: 'Belgium'),
    ];
    final tags = _layout(lines);
    expect(tags, hasLength(2));
    _expectClean(lines, tags);
    for (final t in tags) {
      expect(t.top + _h, lessThan(_drawH - 6));
    }
  });

  test('six lines: tags for the likeliest that fit, never a pile', () {
    final lines = _lines([
      ('Gavin Newsom', 0.41),
      ('Josh Shapiro', 0.22),
      ('Pete Buttigieg', 0.13),
      ('Alexandria Ocasio-Cortez', 0.09),
      ('Wes Moore', 0.085),
      ('Andy Beshear', 0.08),
    ]);
    final tags = _layout(lines);
    _expectClean(lines, tags);
    expect(tags.length, lessThanOrEqualTo(kPolyTagMaxTags));
    expect(tags.length, lessThan(6));
    // The likeliest lines keep theirs first.
    final shown = {for (final t in tags) t.index};
    for (final i in shown) {
      for (var j = 0; j < i; j++) {
        expect(shown, contains(j), reason: 'line $i tagged, likelier $j not');
      }
    }
    expect(_textOf(tags, 0), 'Gavin Newsom 41%');
    for (final t in tags) {
      expect((t.top + _h / 2 - lines[t.index].y).abs(),
          lessThanOrEqualTo(kPolyTagMaxShift * _h + 0.5));
    }
  });

  test('six lines all ending together: a few tags, not six', () {
    final lines = [
      for (var i = 0; i < 6; i++)
        (y: 100.0 + i, price: 0.2 - i * 0.002, pct: '20%', name: 'Name$i'),
    ];
    final tags = _layout(lines);
    _expectClean(lines, tags);
    expect(tags.length, lessThanOrEqualTo(4));
    expect(tags, isNotEmpty);
  });

  test('a lone line in a crowded plot always keeps its tag', () {
    final lines = [(y: 50.0, price: 0.5, pct: '50%', name: 'Up')];
    expect(_layout(lines).single.text, 'Up 50%');
  });
}
