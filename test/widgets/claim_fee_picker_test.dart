import 'package:breez_sdk_spark_flutter/breez_sdk_spark.dart' as breez;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/spark_transaction_details.dart';
import 'package:kute/theme/app_theme.dart';

void main() {
  Future<void> pumpPicker(WidgetTester tester,
      {required int depositAmountSats, int? lastQuoteSats}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        conversionToFiatProvider.overrideWith((ref, amount) => '\$0.25')
      ],
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          theme: buildLightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
              body: ClaimFeePickerSheet(
            depositAmountSats: depositAmountSats,
            claimError: lastQuoteSats == null
                ? null
                : breez.DepositClaimError.maxDepositClaimFeeExceeded(
                    tx: 'tx',
                    vout: 0,
                    requiredFeeSats: BigInt.from(lastQuoteSats),
                    requiredFeeRateSatPerVbyte: BigInt.from(3)),
          )),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  VoidCallback? confirm(WidgetTester tester) =>
      tester.widget<AppButton>(find.byType(AppButton)).onPressed;

  test('suggested cap adds headroom to the last quote below the deposit', () {
    expect(suggestedClaimFeeSats(lastQuoteSats: 250, depositAmountSats: 1000),
        350);
    expect(
        suggestedClaimFeeSats(lastQuoteSats: 2600, depositAmountSats: 100000),
        2860);
    expect(suggestedClaimFeeSats(lastQuoteSats: 950, depositAmountSats: 1000),
        999);
    expect(suggestedClaimFeeSats(lastQuoteSats: 999, depositAmountSats: 1000),
        isNull);
    expect(suggestedClaimFeeSats(lastQuoteSats: 1200, depositAmountSats: 1000),
        isNull);
    expect(suggestedClaimFeeSats(lastQuoteSats: 10, depositAmountSats: 1),
        isNull);
  });

  testWidgets(
      'claim cap uses the last quote with headroom and blocks the entire deposit as fee',
      (tester) async {
    await pumpPicker(tester, depositAmountSats: 1000, lastQuoteSats: 250);
    expect(find.text('350'), findsOneWidget);
    expect(find.textContaining('last quote of 250 sats'), findsOneWidget);
    expect(find.textContaining('confirmation speed'), findsOneWidget);
    expect(confirm(tester), isNotNull);
    await tester.enterText(find.byType(TextField), '1000');
    await tester.pump();
    expect(confirm(tester), isNull);
    expect(find.text('Fee exceeds deposit value'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '500');
    await tester.pump();
    expect(confirm(tester), isNotNull);
    await tester.enterText(find.byType(TextField), '0');
    await tester.pump();
    expect(confirm(tester), isNull);
  });

  testWidgets('a quote that uses up the deposit is not prefilled below it',
      (tester) async {
    await pumpPicker(tester, depositAmountSats: 1000, lastQuoteSats: 1200);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    expect(find.textContaining('1200 sats, which would use up this deposit'),
        findsOneWidget);
    expect(find.textContaining('headroom'), findsNothing);
    expect(confirm(tester), isNull);
  });

  testWidgets('without a quote the cap starts empty and unlabelled',
      (tester) async {
    await pumpPicker(tester, depositAmountSats: 1000);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    expect(find.textContaining('last quote'), findsNothing);
    expect(confirm(tester), isNull);
  });
}
