import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/hyperliquid/components/hl_tick_price.dart';
import 'package:kute/screens/shared/rolling_number_text.dart';
import 'package:kute/theme/app_theme.dart';

const _primary = Color(0xFF111111);

Widget _price(double price) => MaterialApp(
      home: Center(
        child: HlTickPrice(
          price: price,
          text: '\$${price.toStringAsFixed(0)}',
          style: const TextStyle(color: _primary, fontSize: 16),
        ),
      ),
    );

Color? _color(WidgetTester tester) => tester
    .widget<RollingNumberText>(find.byType(RollingNumberText))
    .style
    .color;

void main() {
  testWidgets('the price rests in its own colour', (tester) async {
    await tester.pumpWidget(_price(85806));
    expect(_color(tester), _primary);
  });

  testWidgets('a down tick flashes red and returns to the resting colour',
      (tester) async {
    await tester.pumpWidget(_price(85806));
    await tester.pumpWidget(_price(85700));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_color(tester), AppColors.marketDown);

    await tester.pump(HlTickPrice.flashDuration);
    await tester.pumpAndSettle();
    expect(_color(tester), _primary);
  });

  testWidgets('an up tick flashes green and returns to the resting colour',
      (tester) async {
    await tester.pumpWidget(_price(85806));
    await tester.pumpWidget(_price(85900));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_color(tester), AppColors.marketUp);

    await tester.pump(HlTickPrice.flashDuration);
    await tester.pumpAndSettle();
    expect(_color(tester), _primary);
  });

  testWidgets('the first price to arrive does not flash', (tester) async {
    await tester.pumpWidget(_price(0));
    await tester.pumpWidget(_price(85806));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_color(tester), _primary);
  });
}
