// The chart's right-edge value tags never cover each other, and a game's
// two sides never take the green and red of up and down. (A "Bought" tag
// beside a value tag: test/screens/shared/chart_tag_layout_test.dart and
// market_chart_scrub_card_test.dart.)

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/polymarket/components/game_chart_section.dart';
import 'package:kute/screens/polymarket/components/market_chart.dart';
import 'package:kute/theme/app_theme.dart';

void main() {
  group('the value tags at the end of the lines', () {
    test('tags with room stay where their lines end', () {
      expect(spreadChartTags([10, 60, 120], height: 16, maxBottom: 200),
          [10, 60, 120]);
    });

    test('two lines ending close together are moved apart, in order', () {
      // 21.5% and 18.5% end 6 px apart; a tag is 16 high.
      final tops =
          spreadChartTags([100, 106, 150], height: 16, maxBottom: 200);
      expect(tops[0], 100);
      expect(tops[1], 118);
      expect(tops[2], 150);
    });

    test('the order of the values is kept whatever order they come in', () {
      final tops = spreadChartTags([106, 100], height: 16, maxBottom: 200);
      expect(tops[1], lessThan(tops[0]));
      expect(tops[0] - tops[1], greaterThanOrEqualTo(18));
    });

    test('a column pushed past the floor moves back up', () {
      final tops =
          spreadChartTags([180, 182, 184], height: 16, maxBottom: 200);
      expect(tops[2], 184);
      expect(tops[1], 166);
      expect(tops[0], 148);
    });
  });

  group('the colour of a game\'s sides', () {
    const title = 'NFL: 49ers vs. Broncos';

    test('the title\'s first team takes the first colour', () {
      expect(gameSideColors(title, '49ers', 'Broncos'),
          (kGameSideColors[0], kGameSideColors[1]));
    });

    test('whatever order the caller has the sides in', () {
      // A market that lists the Broncos first still draws the 49ers in
      // the first colour.
      expect(gameSideColors(title, 'Broncos', '49ers'),
          (kGameSideColors[1], kGameSideColors[0]));
      expect(gameSideColors(title, 'Denver Broncos', 'San Francisco 49ers'),
          (kGameSideColors[1], kGameSideColors[0]));
    });

    test('never the green and red of up and down', () {
      for (final c in kGameSideColors) {
        expect(c, isNot(AppColors.marketUp));
        expect(c, isNot(AppColors.marketDown));
      }
    });

    test('sides the title does not name still differ', () {
      final (a, b) = gameSideColors('Who wins?', null, null);
      expect(a, isNot(b));
      final (c, d) = gameSideColors(title, 'Broncos', null);
      expect(c, kGameSideColors[1]);
      expect(d, kGameSideColors[0]);
    });
  });
}
