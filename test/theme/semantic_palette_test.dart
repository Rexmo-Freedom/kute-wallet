// One green, one red, one amber: a "Completed" status, a received
// amount, a row's in-arrow and the Dollars coin all wear the same green;
// a failure, a loss and an out-arrow the same red; pending the theme's
// warning amber in each mode.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/common_operation_methods.dart';
import 'package:kute/theme/app_theme.dart';

void main() {
  test('success and error are the market pair, in both modes', () {
    expect(AppColors.success, AppColors.marketUp);
    expect(AppColors.error, AppColors.marketDown);
    for (final c in [AppColorsExtension.dark(), AppColorsExtension.light()]) {
      expect(c.success, AppColors.marketUp);
      expect(c.error, AppColors.marketDown);
    }
  });

  test('the direction badge arrows are the same green and red', () {
    expect(fintechGreen, AppColors.marketUp);
    expect(fintechRed, AppColors.marketDown);
  });

  test('pending is one amber per mode, apart from the green and red', () {
    final dark = AppColorsExtension.dark();
    final light = AppColorsExtension.light();
    expect(dark.warning, AppColors.warning);
    for (final c in [dark, light]) {
      expect(c.warning, isNot(c.success));
      expect(c.warning, isNot(c.error));
    }
  });

  test('the Dollars coin disc is the one green', () {
    final svg = File('lib/assets/usdb-logo.svg').readAsStringSync();
    final hex = AppColors.marketUp
        .toARGB32()
        .toRadixString(16)
        .substring(2)
        .toUpperCase();
    expect(svg, contains('fill="#$hex"'));
  });
}
