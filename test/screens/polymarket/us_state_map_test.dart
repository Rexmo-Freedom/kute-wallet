// The US state map's outlines and taps: every state drawn from the
// Census outlines, a tap inside a state picks it, a tap near a small one
// (Rhode Island) still does, and the sea picks nothing.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/us_states.dart';
import 'package:kute/screens/polymarket/components/us_map_geometry.dart';
import 'package:kute/screens/polymarket/components/us_state_map.dart';

void main() {
  test('every state and DC has an outline and a label point', () {
    expect(kUsStatePaths.keys.toSet(), kUsStateNames.keys.toSet());
    expect(kUsStateLabelPoints.keys.toSet(), kUsStateNames.keys.toSet());
    for (final e in kUsStatePaths.entries) {
      final bounds = usMapPath(e.value).getBounds();
      expect(bounds.isEmpty, isFalse, reason: e.key);
      expect(bounds.left, greaterThanOrEqualTo(0), reason: e.key);
      expect(bounds.right, lessThanOrEqualTo(kUsMapWidth), reason: e.key);
      expect(bounds.bottom, lessThanOrEqualTo(kUsMapHeight), reason: e.key);
      // A state's label point is inside it.
      expect(usMapPath(e.value).contains(kUsStateLabelPoints[e.key]!.at),
          isTrue,
          reason: e.key);
    }
  });

  test('a tap picks the state under it, or a small state near it', () {
    const width = kUsMapWidth / 2;
    Offset at(String code, [Offset nudge = Offset.zero]) =>
        kUsStateLabelPoints[code]!.at / 2 + nudge;
    final all = kUsStateNames.keys.toSet();
    expect(usMapStateAt(at('TX'), width, all), 'TX');
    expect(usMapStateAt(at('AK'), width, all), 'AK');
    expect(usMapStateAt(at('HI'), width, all), 'HI');
    // Off Rhode Island's coast, within the slop.
    expect(
        usMapStateAt(at('RI', const Offset(6, 4)), width, {'RI', 'TX'}), 'RI');
    // Only the states that take a tap: Texas is not one here.
    expect(usMapStateAt(at('TX'), width, {'OH'}), isNull);
    // The Gulf of Mexico.
    expect(usMapStateAt(const Offset(330, 300), width, all), isNull);
  });
}
