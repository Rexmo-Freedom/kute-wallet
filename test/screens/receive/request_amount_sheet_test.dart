// The "Request amount" sheet: the Lightning receive opens it with nothing
// (its unit picker, no minimum line, "Create request" on any amount), and
// the one-time receive opens it fixed to dollars with the route's minimum,
// which turns red and keeps "Create request" off under it.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/receive/components/request_amount_sheet.dart';
import 'package:kute/screens/shared/amount_keypad_panel.dart'
    show AmountKeypad, BigAmountDisplay;
import 'package:kute/screens/shared/custom_button.dart' show AppButton;
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart';

class _Currency extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _Currency()
      : super(CurrencyState({
          'USD': Fixed.fromInt(60000),
          'BTC': Fixed.fromNum(1 / 60000, decimalDigits: 16),
        }));

  @override
  Future<void> updateRates() async {}
}

final _l10n = AppLocalizationsEn();

/// Opens the sheet with [open] and returns what it resolved to.
Future<List<RequestedAmount?>> _pump(WidgetTester tester,
    Future<RequestedAmount?> Function(BuildContext context) open) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final results = <RequestedAmount?>[];
  await tester.pumpWidget(ProviderScope(
    overrides: [
      settingsProvider.overrideWith((_) => SettingsModel(Settings(
            currency: 'USD',
            language: 'en',
            btcFormat: 'sats',
            backup: false,
            biometricsEnabled: false,
            bitcoinElectrumNode: '',
            nodeType: 'Blockstream',
            reviewDone: true,
            activeWalletId: 'spending',
            wallets: [WalletConfig(id: 'spending', name: 'Spending')],
          ))),
      currencyProvider.overrideWith((_) => _Currency()),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
            splashFactory: NoSplash.splashFactory,
            fontFamily: 'Inter',
            extensions: [AppColorsExtension.light()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async => results.add(await open(context)),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return results;
}

Future<void> _type(WidgetTester tester, String amount) async {
  tester.widget<AmountKeypad>(find.byType(AmountKeypad)).onChanged(amount);
  await tester.pump();
}

AppButton _create(WidgetTester tester) => tester.widget<AppButton>(
    find.widgetWithText(AppButton, _l10n.receiveCreateRequest));

void main() {
  testWidgets(
      'Lightning opens it as before: the unit picker, no minimum line, and '
      'any amount can be requested', (tester) async {
    final results = await _pump(tester, (c) => showRequestAmountSheet(c));
    final sheet =
        tester.widget<RequestAmountSheet>(find.byType(RequestAmountSheet));
    expect(sheet.fixedCurrency, isNull);
    expect(sheet.minimumLabel, isNull);
    expect(sheet.validate, isNull);
    expect(find.text(_l10n.receiveRequestAmount), findsOneWidget);
    expect(find.byIcon(Icons.unfold_more_rounded), findsOneWidget);
    expect(_create(tester).onPressed, isNull);

    await _type(tester, '1000');
    final display =
        tester.widget<BigAmountDisplay>(find.byType(BigAmountDisplay));
    expect(display.minimumLabel, isNull);
    expect(display.minimumIsError, isFalse);
    expect(_create(tester).onPressed, isNotNull);
    await tester
        .tap(find.widgetWithText(AppButton, _l10n.receiveCreateRequest));
    await tester.pumpAndSettle();
    expect(results, hasLength(1));
    expect(results.single!.amount, '1000');
  });

  testWidgets(
      'fixed to dollars with a minimum: no picker, the minimum on its line, '
      'red and disabled under it', (tester) async {
    final results = await _pump(
        tester,
        (c) => showRequestAmountSheet(c,
            fixedCurrency: 'USD',
            minimumLabel: _l10n.amountMinimumInline('\$2.00'),
            validate: (r) => (double.tryParse(r.amount) ?? 0) < 2
                ? _l10n.routeAmountTooSmall('\$2.00')
                : null));
    expect(find.byIcon(Icons.unfold_more_rounded), findsNothing);
    expect(find.text('USD'), findsOneWidget);
    var display =
        tester.widget<BigAmountDisplay>(find.byType(BigAmountDisplay));
    expect(display.prefix, '\$');
    expect(display.minimumLabel, _l10n.amountMinimumInline('\$2.00'));

    await _type(tester, '1.5');
    display = tester.widget<BigAmountDisplay>(find.byType(BigAmountDisplay));
    expect(display.minimumLabel, _l10n.routeAmountTooSmall('\$2.00'));
    expect(display.minimumIsError, isTrue);
    expect(display.conversionLabel, isEmpty);
    expect(_create(tester).onPressed, isNull);

    await _type(tester, '25');
    expect(_create(tester).onPressed, isNotNull);
    await tester
        .tap(find.widgetWithText(AppButton, _l10n.receiveCreateRequest));
    await tester.pumpAndSettle();
    expect(results.single, (amount: '25', currency: 'USD'));
  });
}
