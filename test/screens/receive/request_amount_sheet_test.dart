// The "Request amount" sheet: the Lightning receive opens it with nothing
// (its unit picker, no minimum line, "Create request" on any amount), and
// the one-time receive opens it fixed to dollars with the route's minimum,
// which turns red and keeps "Create request" off under it. Its limits can
// arrive while it is open (a live read landing): the line follows, and a
// tap while the read is in flight waits for it. "Create request" is the
// shell bar in primary mode (shell_bar_harness.dart): the sheet declares
// it through its KuteBarContextScope and the bar, mounted over the test
// app, draws and takes the tap.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/receive/components/request_amount_sheet.dart';
import 'package:kute/screens/shared/amount_keypad_panel.dart'
    show AmountKeypad, BigAmountDisplay;
import 'package:kute/screens/shared/kute_back_button.dart' show KuteCloseButton;
import 'package:money2/money2.dart';

import '../../helpers/shell_bar_harness.dart';

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
  installShellBar();
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
    // The app's layering (shell_bar_harness.dart): the bar over the
    // navigator is the sheet's Create request button.
    child: shellBarApp(
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
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return results;
}

Future<void> _type(WidgetTester tester, String amount) async {
  tester.widget<AmountKeypad>(find.byType(AmountKeypad)).onChanged(amount);
  await tester.pump();
  // The bar redraws a frame after the sheet, its words sliding to the
  // new state (kute_shell_bar.dart).
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// The sheet's own primary scope (the sheet frame around it declares a
/// hidden one of its own, app_bottom_sheet.dart).
final Finder _createScope = find.descendant(
    of: find.byType(RequestAmountSheet),
    matching: find.byWidgetPredicate(
        (w) => w is KuteBarContextScope && w.barContext.isPrimary));

/// "Create request" as the sheet declares it to the bar (its scope is
/// current on the frame it is built; the bar redraws a frame later), and
/// the bar lettering it.
KuteBarContext _create(WidgetTester tester) {
  final ctx = tester.widget<KuteBarContextScope>(_createScope).barContext;
  expect(ctx.label, _l10n.receiveCreateRequest);
  // The bar letters what the button says now: "Create request", or the
  // step to take while it is off ("Enter an amount").
  expect(barPrimaryText(ctx.primaryLabel), findsOneWidget);
  return ctx;
}

/// The handler while the button takes a tap, else null (what the drawn
/// button's `onPressed` used to read).
VoidCallback? _onCreate(WidgetTester tester) {
  final ctx = _create(tester);
  return ctx.enabled && !ctx.busy ? ctx.onPrimary : null;
}

/// Taps Create request on the bar: [settle] pumps until quiet, else one
/// frame (a tap that starts the spinner never settles).
Future<void> _tapCreate(WidgetTester tester, {bool settle = true}) async {
  _create(tester);
  await tapBarPrimary(tester, settle: settle);
}

bool _creating(WidgetTester tester) => _create(tester).busy;

void main() {
  testWidgets('its close X, on the left, dismisses it with nothing requested',
      (tester) async {
    final results = await _pump(tester, (c) => showRequestAmountSheet(c));
    await _type(tester, '1000');
    await tester.tap(find.byType(KuteCloseButton));
    await tester.pumpAndSettle();
    expect(find.byType(RequestAmountSheet), findsNothing);
    expect(results, [null]);
  });

  testWidgets(
      'Lightning opens it as before: the unit picker, no minimum line, and '
      'any amount can be requested', (tester) async {
    final results = await _pump(tester, (c) => showRequestAmountSheet(c));
    final sheet =
        tester.widget<RequestAmountSheet>(find.byType(RequestAmountSheet));
    expect(sheet.fixedCurrency, isNull);
    expect(sheet.minimumLabel, isNull);
    expect(sheet.validate, isNull);
    // No title: the person already knows what the sheet is for.
    expect(find.text(_l10n.receiveRequestAmount), findsNothing);
    expect(find.byIcon(Icons.unfold_more_rounded), findsOneWidget);
    expect(_onCreate(tester), isNull);
    // Off, the bar says the step to take (founder, 1 November 2026).
    expect(barPrimaryText(_l10n.barNeedAmount), findsOneWidget);
    // The close X on the left, as on every receive sheet.
    final close = find.byType(KuteCloseButton);
    expect(close, findsOneWidget);
    expect(tester.getCenter(close).dx,
        lessThan(tester.getCenter(find.byType(RequestAmountSheet)).dx));

    await _type(tester, '1000');
    final display =
        tester.widget<BigAmountDisplay>(find.byType(BigAmountDisplay));
    expect(display.minimumLabel, isNull);
    expect(display.minimumIsError, isFalse);
    expect(_onCreate(tester), isNotNull);
    await _tapCreate(tester);
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
    expect(_onCreate(tester), isNull);

    await _type(tester, '25');
    expect(_onCreate(tester), isNotNull);
    await _tapCreate(tester);
    expect(results.single, (amount: '25', currency: 'USD'));
  });

  RequestAmountLimits minimumOf(int? dollars) => (
        minimumLabel:
            dollars == null ? null : _l10n.amountMinimumInline('\$$dollars.00'),
        validate: (r) =>
            dollars != null && (double.tryParse(r.amount) ?? 0) < dollars
                ? _l10n.routeAmountTooSmall('\$$dollars.00')
                : null,
      );

  testWidgets(
      'live limits: no minimum line until the read lands, then the line and '
      'the check follow it', (tester) async {
    final limits = ValueNotifier(minimumOf(null));
    await _pump(
        tester,
        (c) => showRequestAmountSheet(c,
            fixedCurrency: 'USD', limits: limits, pending: () => null));
    var display =
        tester.widget<BigAmountDisplay>(find.byType(BigAmountDisplay));
    expect(display.minimumLabel, isNull);
    await _type(tester, '3');
    expect(_onCreate(tester), isNotNull);

    limits.value = minimumOf(5);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    display = tester.widget<BigAmountDisplay>(find.byType(BigAmountDisplay));
    expect(display.minimumLabel, _l10n.routeAmountTooSmall('\$5.00'));
    expect(display.minimumIsError, isTrue);
    expect(_onCreate(tester), isNull);
  });

  testWidgets(
      'a tap while the read is in flight waits for it (loading), then '
      'checks again with what it brought', (tester) async {
    final limits = ValueNotifier(minimumOf(null));
    var read = Completer<void>();
    final results = await _pump(
        tester,
        (c) => showRequestAmountSheet(c,
            fixedCurrency: 'USD',
            limits: limits,
            pending: () => read.isCompleted ? null : read.future));
    await _type(tester, '3');
    await _tapCreate(tester, settle: false);
    expect(_creating(tester), isTrue);
    expect(results, isEmpty);

    // The live minimum is higher than what was typed: nothing is asked.
    limits.value = minimumOf(5);
    read.complete();
    await tester.pump();
    await tester.pump();
    // The bar's longer words ("Check the amount") once their room has
    // grown (kute_shell_bar.dart, THE WORDS NEVER CLIP).
    await tester.pump(const Duration(milliseconds: 400));
    expect(_creating(tester), isFalse);
    expect(results, isEmpty);
    expect(find.byType(RequestAmountSheet), findsOneWidget);
    expect(
        tester
            .widget<BigAmountDisplay>(find.byType(BigAmountDisplay))
            .minimumLabel,
        _l10n.routeAmountTooSmall('\$5.00'));

    // Enough, and a second read in flight: it waits, then asks.
    read = Completer<void>();
    await _type(tester, '6');
    await _tapCreate(tester, settle: false);
    expect(_creating(tester), isTrue);
    read.complete();
    await tester.pumpAndSettle();
    expect(results.single, (amount: '6', currency: 'USD'));
  });
}
