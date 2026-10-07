// A game's markets by kind, from the questions Polymarket writes (sampled
// from an NFL game with 328 markets and a football match).

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/polymarket/live_game/game_market_groups.dart';

void main() {
  GameMarketGroup g(String name) => gameMarketGroupOf(name);

  test('the whole game: winner, spreads, totals', () {
    expect(g('Patriots vs. Bills'), GameMarketGroup.winner);
    expect(g('Spread: Bills (-1.5)'), GameMarketGroup.spreads);
    expect(g('Patriots vs. Bills: O/U 47.5'), GameMarketGroup.totals);
  });

  test('a half or a quarter goes with its period, whatever it prices', () {
    expect(g('1H Spread: Patriots (-1.5)'), GameMarketGroup.halves);
    expect(g('Patriots vs. Bills: 2H Moneyline'), GameMarketGroup.halves);
    expect(g('Patriots vs. Bills: 1H O/U 16.5'), GameMarketGroup.halves);
    expect(g('Patriots 1H Team Total: O/U 6.5'), GameMarketGroup.halves);
    expect(g('Will Portugal lead at half-time?'), GameMarketGroup.halves);
    expect(g('3Q Spread: Patriots (-2.5)'), GameMarketGroup.quarters);
    expect(g('Patriots vs. Bills: 4Q O/U 5.5'), GameMarketGroup.quarters);
    expect(g('Patriots vs. Bills: Both Teams to Score Points - 1Q'),
        GameMarketGroup.quarters);
  });

  test('one team\'s numbers and one-off questions are props', () {
    expect(g('Patriots Team Total: O/U 10.5'), GameMarketGroup.props);
    expect(g('Patriots Total Touchdowns: O/U 2.5'), GameMarketGroup.props);
    expect(g('Exact Margin: Patriots by 25+'), GameMarketGroup.props);
    expect(g('Patriots vs. Bills: Safety?'), GameMarketGroup.props);
    expect(g('Patriots vs. Bills: Team to Record Longest FG'),
        GameMarketGroup.props);
    expect(g('Both Teams to Score'), GameMarketGroup.props);
  });
}
