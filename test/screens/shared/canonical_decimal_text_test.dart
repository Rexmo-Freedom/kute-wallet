// The keypad's amount text must be a plain decimal whatever the locale
// formatted, or a euro user's "1,00" becomes 100.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/shared/amount_keypad_panel.dart';

void main() {
  test('reads formatted money back as a plain decimal', () {
    expect(canonicalDecimalText('1,00'), '1.00');
    expect(canonicalDecimalText('0,07'), '0.07');
    expect(canonicalDecimalText('1.00'), '1.00');
    expect(canonicalDecimalText('0.07'), '0.07');
    expect(canonicalDecimalText('1.234,56'), '1234.56');
    expect(canonicalDecimalText('1,234.56'), '1234.56');
    expect(canonicalDecimalText('€ 12,30'), '12.30');
    expect(canonicalDecimalText(''), '');
    expect(canonicalDecimalText('7', decimals: 0), '7');
  });
}
