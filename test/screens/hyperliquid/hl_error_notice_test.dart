import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/screens/hyperliquid/components/hl_error_copy.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';
import 'package:kute/theme/app_theme.dart';

Future<void> _pump(WidgetTester tester, Object error) async {
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(430, 932),
    builder: (_, __) => MaterialApp(
      theme: ThemeData(extensions: [AppColorsExtension.light()]),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: HlTradeErrorNotice(message: 'Minimum is \$10.26.', error: error),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  const raw = r'order notional $9.98 is below the $10 minimum';

  testWidgets('the minimum refusal shows only its friendly line',
      (tester) async {
    await _pump(tester,
        const HyperliquidMinNotionalException(raw, minimumUsd: 10));
    expect(find.text('Minimum is \$10.26.'), findsOneWidget);
    expect(find.text('Details'), findsNothing);
    expect(find.text(raw), findsNothing);
  });

  testWidgets('the venue\'s own minimum wording hides details too',
      (tester) async {
    await _pump(
        tester,
        const HyperliquidRejectedException(
            r'Order must have minimum value of $10. asset=7'));
    expect(find.text('Details'), findsNothing);
  });

  testWidgets('an unknown rejection keeps Details, collapsed', (tester) async {
    const other = 'Something new the venue said';
    await _pump(tester, const HyperliquidRejectedException(other));
    expect(find.text('Details'), findsOneWidget);
    expect(find.text(other), findsNothing);
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.text(other), findsOneWidget);
  });
}
