// A localized name is also searched in English; anything else runs once.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/polymarket/search_aliases.dart';

void main() {
  test('a country or competition name is rewritten to English', () {
    expect(polySearchAlias('brasil'), 'brazil');
    expect(polySearchAlias('Brasil'), 'brazil');
    expect(polySearchAlias('Alemanha'), 'germany');
    expect(polySearchAlias('França'), 'france');
    expect(polySearchAlias('Estados Unidos'), 'united states');
    expect(polySearchAlias('copa do mundo'), 'world cup');
  });

  test('the other words stay, and whole words only', () {
    expect(polySearchAlias('eleição brasil'), 'election brazil');
    expect(polySearchAlias('brasileirão'), isNull);
    expect(polySearchAlias('ira'), 'iran');
    expect(polySearchAlias('irã'), 'iran');
  });

  test('a name Gamma already matches is not rewritten', () {
    expect(polySearchAlias('brazil'), isNull);
    expect(polySearchAlias('méxico'), isNull);
    expect(polySearchAlias('bitcoin'), isNull);
    expect(polySearchAlias('  '), isNull);
  });
}
