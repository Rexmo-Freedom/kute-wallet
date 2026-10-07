import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/screens/shared/components/transaction_row_content.dart';

const _title = 'Withdraw from a very long venue name that cannot fit';
const _metadata = 'Payment window ended · 15 Sep 2026, 09:16';
const _rowKey = ValueKey('transaction-row');
const _tile = TransactionRowContent(
  key: _rowKey,
  leading: SizedBox(width: 40, height: 40),
  title: Text(_title, style: TextStyle(fontSize: 16, height: 1.25)),
  subtitle: Text(_metadata, style: TextStyle(fontSize: 13.5, height: 1.3)),
  amount: Text('₿704,364,000', style: TextStyle(fontSize: 16)),
  secondaryAmount:
      Text('from \$555.00', style: TextStyle(fontSize: 13, height: 1.3)),
);

Future<void> _pump(WidgetTester tester,
    {double width = 430, double textScale = 1}) async {
  tester.view.physicalSize = Size(width, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(430, 932),
    minTextAdapt: true,
    builder: (_, __) => MaterialApp(
      theme: ThemeData(fontFamily: 'Inter'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const Scaffold(
        body: SingleChildScrollView(
          child: Padding(padding: EdgeInsets.all(16), child: _tile),
        ),
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('Inter')
      ..addFont(rootBundle.load('lib/assets/fonts/Inter-Regular.ttf'));
    await font.load();
  });

  double lineHeight(WidgetTester tester, String text) =>
      tester.getSize(find.text(text)).height;

  testWidgets('title and context stay on one line each, beside the figures',
      (tester) async {
    await _pump(tester);
    // One line each: the rendered height is a single line of its style.
    expect(lineHeight(tester, _title), lessThan(16 * 1.25 * 1.6));
    expect(lineHeight(tester, _metadata), lessThan(13.5 * 1.3 * 1.6));
    // The amount sits on the title's line, the secondary on the context's.
    expect(tester.getCenter(find.text('₿704,364,000')).dy,
        lessThan(tester.getCenter(find.text('from \$555.00')).dy));
    expect(tester.getTopLeft(find.text(_metadata)).dy,
        greaterThan(tester.getBottomLeft(find.text(_title)).dy - 1));
    // The figures stay right of the text.
    expect(tester.getTopRight(find.text(_title)).dx,
        lessThanOrEqualTo(tester.getTopLeft(find.text('₿704,364,000')).dx));
    expect(tester.getSize(find.byKey(_rowKey)).height, lessThan(64));
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow and 1.6x text keep one line and the same shape',
      (tester) async {
    for (final size in [(320.0, 1.0), (320.0, 1.6), (360.0, 1.6)]) {
      await _pump(tester, width: size.$1, textScale: size.$2);
      // Nothing wraps: the row is two lines tall whatever the text size.
      expect(tester.getSize(find.byKey(_rowKey)).height,
          lessThan(40 * size.$2 + 20));
      expect(tester.getRect(find.byKey(_rowKey)).right,
          lessThanOrEqualTo(size.$1 - 16));
      // The amount is whole, shrunk to its column rather than cut.
      expect(find.text('₿704,364,000'), findsOneWidget);
      expect(tester.getRect(find.byType(FittedBox).first).right,
          lessThanOrEqualTo(size.$1 - 16));
      expect(tester.takeException(), isNull);
    }
  });
}
