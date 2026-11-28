// Phase 2 of Advanced trading on the Hyperliquid opening ticket: Market,
// Limit, Scale and TWAP (stop / take orders live on the close sheet), each
// validated inline before Confirm with the venue's own figures, the
// ticket's draft reset to valid defaults, the side panel on the web's
// column, a typed field keeping its own keys, a ticket that holds an
// accepted order still following it after Back from Advanced, and the
// receipt told what of an attached trailing stop did not happen. Nothing
// is ever placed here.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart' show l10nForLanguage;
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/platform/kute_layout.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_orderbook_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/screens/hyperliquid/components/order_slip_sheet.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/screens/shared/kute_dialog.dart' show KuteDialogRoute;
import 'package:kute/screens/shared/rubber_band_progress.dart'
    show RubberBandBusy;
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:money2/money2.dart';

import '../../helpers/fake_swap_orders.dart';
import '../../helpers/shell_bar_harness.dart';

class _LivePrices extends HlLivePricesNotifier {
  @override
  HlLivePriceState build() =>
      const HlLivePriceState(mids: {'BTC': 60000, 'HYPE': 40});
  @override
  void acquire() {}
  @override
  void release() {}
  @override
  void watchCoins(List<String> coins, {Map<String, String>? wire}) {}
}

class _Currency extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _Currency() : super(CurrencyState({'USD': Fixed.fromInt(1)}));
  @override
  Future<void> updateRates() async {}
}

class _Allowed extends Fake implements RuntimeCapabilitiesService {
  @override
  CapabilityDecision decision(String id) =>
      const CapabilityDecision(allowed: true);
  @override
  String? blockReason(String id) => null;
  @override
  Future<void> ensureAllAllowed(Iterable<String> ids,
      {Duration maxAge = Duration.zero}) async {}
  @override
  int? get maxLeverage => null;
  @override
  int offeredLeverage(int venueMax) => venueMax;
}

const _btc = HlMarket(
  coin: 'BTC',
  wireCoin: 'BTC',
  assetId: 0,
  kind: HlMarketKind.perp,
  szDecimals: 5,
  maxLeverage: 40,
  onlyIsolated: false,
  markPx: 60000,
  midPx: 60000,
  prevDayPx: 60000,
  dayNtlVlm: 0,
);

const _hypeSpot = HlMarket(
  coin: 'HYPE',
  wireCoin: '@107',
  assetId: 10107,
  kind: HlMarketKind.spot,
  szDecimals: 2,
  maxLeverage: 1,
  onlyIsolated: false,
  markPx: 40,
  midPx: 40,
  prevDayPx: 40,
  dayNtlVlm: 0,
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The ticket as a sheet (phone), or in place as the web's column
/// ([typed]: [HlOrderSlipSheet.inPlace] with a typed amount) at the right
/// of a wide window.
Future<void> _pump(WidgetTester tester,
    {HlMarket market = _btc,
    bool isLong = true,
    bool typed = false,
    Set<String>? standingEndedBefore,
    double available = 500,
    double width = 390,
    double height = 844}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  installShellBar();
  final ticket = typed
      ? HlOrderSlipSheet.inPlace(
          market: market,
          entrySource: 'test',
          onDone: () {},
          isLong: isLong,
          typedAmount: true)
      : HlOrderSlipSheet(
          market: market,
          initialIsLong: isLong,
          standingEndedBefore: standingEndedBefore);
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
            reviewDone: false,
          ))),
      hyperliquidLivePricesProvider.overrideWith(_LivePrices.new),
      hyperliquidWithdrawableProvider.overrideWith((_) => available),
      hyperliquidSpotBalancesProvider.overrideWith((_) => []),
      swapOrdersProvider.overrideWith((_) => FakeSwapOrders()),
      hyperliquidAddressProvider.overrideWith((_) async => null),
      hyperliquidOrderbookProvider
          .overrideWith((_, __) => Stream.value(const HlOrderBookState())),
      aiEnabledProvider.overrideWith((_) async => false),
      currencyProvider.overrideWith((_) => _Currency()),
      runtimeCapabilitiesProvider.overrideWithValue(_Allowed()),
    ],
    child: shellBarApp(
      designSize: KuteLayout.designSizeFor(Size(width, height)),
      home: Scaffold(
        body: typed
            ? Align(
                alignment: Alignment.topRight,
                child: SizedBox(width: 420, height: 900, child: ticket))
            : Align(alignment: Alignment.bottomCenter, child: ticket),
      ),
    ),
  ));
  await _settle(tester);
}

Future<void> _openAdvanced(WidgetTester tester) async {
  final button = find.byKey(const ValueKey('slip-advanced-button'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> _pickType(WidgetTester tester, String type) async {
  final tile = find.byKey(ValueKey('hl-adv-type-${type.toLowerCase()}'));
  await tester.ensureVisible(tile);
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

Future<void> _back(WidgetTester tester) async {
  await tester.tap(find.byType(KuteBackButton));
  await tester.pumpAndSettle();
}

/// The Advanced page's fields in order: the amount first, then the type's.
Finder _field(int i) => find.byType(TextField).at(i);

String _text(WidgetTester tester, int i) =>
    tester.widget<TextField>(_field(i)).controller!.text;

Future<void> _enter(WidgetTester tester, int i, String text) async {
  await tester.ensureVisible(_field(i));
  await tester.enterText(_field(i), text);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets(
      'the order types are four tiles, Market, Limit, Scale and TWAP: no '
      'stop or take', (tester) async {
    await _pump(tester);
    await _openAdvanced(tester);
    for (final type in ['market', 'limit', 'scale', 'twap']) {
      expect(find.byKey(ValueKey('hl-adv-type-$type')), findsOneWidget);
    }
    expect(find.text('More options'), findsNothing);
    for (final gone in [
      'Stop market',
      'Stop limit',
      'Take market',
      'Take limit'
    ]) {
      expect(find.text(gone), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'H13: Scale, back, reopen, Scale again: the defaults come back valid',
      (tester) async {
    await _pump(tester);
    await _openAdvanced(tester);
    await _pickType(tester, 'Scale');
    // Amount, start, end, count.
    expect(_text(tester, 3), '5');
    await _enter(tester, 3, '9');
    await _back(tester);
    await _openAdvanced(tester);
    await _pickType(tester, 'Scale');
    expect(_text(tester, 3), '5');
    expect(find.text('Scale takes 2 to 50 orders.'), findsNothing);
    expect(find.text('Enter start and end prices.'), findsNothing);
    expect(find.text('Start and end prices must differ.'), findsNothing);
    expect(find.text('Both prices must be below the current price.'),
        findsNothing);
    await _back(tester);
    await _openAdvanced(tester);
    await _pickType(tester, 'TWAP');
    expect(_text(tester, 1), '30');
    expect(find.text('Duration must be between 5 minutes and 7 days.'),
        findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('H18: a scale order is checked as it is sent', () {
    testWidgets('2..50 orders, inline, the button off', (tester) async {
      await _pump(tester, available: 5000);
      await _openAdvanced(tester);
      await _pickType(tester, 'Scale');
      // Enough that every leg clears the minimum, 51 of them included.
      await _enter(tester, 0, '2000');
      expect(scopeEnabled(tester), isTrue);
      await _enter(tester, 3, '51');
      expect(find.text('Scale takes 2 to 50 orders.'), findsOneWidget);
      expect(scopeEnabled(tester), isFalse);
      await _enter(tester, 3, '1');
      expect(find.text('Scale takes 2 to 50 orders.'), findsOneWidget);
      await _enter(tester, 3, '50');
      expect(find.text('Scale takes 2 to 50 orders.'), findsNothing);
    });

    testWidgets('start and end must differ, on the resting side of the price',
        (tester) async {
      await _pump(tester);
      await _openAdvanced(tester);
      await _pickType(tester, 'Scale');
      await _enter(tester, 0, '200');
      await _enter(tester, 1, '58000');
      await _enter(tester, 2, '58000');
      expect(find.text('Start and end prices must differ.'), findsOneWidget);
      expect(scopeEnabled(tester), isFalse);
      // A buy ladder over the price would buy at once.
      await _enter(tester, 1, '61000');
      expect(find.text('Both prices must be below the current price.'),
          findsOneWidget);
      expect(scopeEnabled(tester), isFalse);
      await _enter(tester, 1, '59000');
      expect(find.text('Both prices must be below the current price.'),
          findsNothing);
      expect(scopeEnabled(tester), isTrue);
    });

    testWidgets('a sell ladder rests above the price', (tester) async {
      await _pump(tester, isLong: false);
      await _openAdvanced(tester);
      await _pickType(tester, 'Scale');
      await _enter(tester, 0, '200');
      expect(scopeEnabled(tester), isTrue);
      await _enter(tester, 1, '59000');
      expect(find.text('Both prices must be above the current price.'),
          findsOneWidget);
      expect(scopeEnabled(tester), isFalse);
    });

    testWidgets(
        'the least-worth leg, at its own price, must clear the minimum '
        '(at the mid it would have passed)', (tester) async {
      await _pump(tester);
      await _openAdvanced(tester);
      await _pickType(tester, 'Scale');
      // \$52 over 5 legs is \$10.40 a leg at the mid, but the size is
      // worked at the range's middle and the 30,000 leg is worth \$6.90.
      await _enter(tester, 0, '52');
      await _enter(tester, 1, '59400');
      await _enter(tester, 2, '30000');
      expect(find.text(r'Each order must be at least $10.00.'),
          findsOneWidget);
      expect(scopeEnabled(tester), isFalse);
      await _enter(tester, 2, '58000');
      await _enter(tester, 0, '60');
      expect(find.text(r'Each order must be at least $10.00.'), findsNothing);
      expect(scopeEnabled(tester), isTrue);
    });
  });

  testWidgets(
      'H6: a TWAP names its own \$100 minimum inline, the button off, '
      'never a one-tap jump', (tester) async {
    await _pump(tester);
    await _openAdvanced(tester);
    await _pickType(tester, 'TWAP');
    await _enter(tester, 0, '50');
    // The venue's \$100 total, as the size is floored and with the price's
    // headroom: \$101.31 at 60,000 on a 0.00001 BTC step.
    expect(find.text(r'A TWAP order needs at least $101.31.'), findsOneWidget);
    expect(scopeLabel(tester), 'Start TWAP · 30m');
    expect(scopeEnabled(tester), isFalse);
    // \$100 floors to 0.00166 BTC, \$99.60: still under.
    await _enter(tester, 0, '100');
    expect(scopeEnabled(tester), isFalse);
    await _enter(tester, 0, '150');
    expect(find.textContaining('A TWAP order needs at least'), findsNothing);
    expect(scopeEnabled(tester), isTrue);
    await _enter(tester, 1, '10081');
    expect(find.text('Duration must be between 5 minutes and 7 days.'),
        findsOneWidget);
    expect(scopeEnabled(tester), isFalse);
  });

  testWidgets('H17: spot offers Market and Limit only, no reduce-only',
      (tester) async {
    await _pump(tester, market: _hypeSpot);
    await _openAdvanced(tester);
    expect(find.byKey(const ValueKey('hl-adv-type-scale')), findsNothing);
    expect(find.byKey(const ValueKey('hl-adv-type-twap')), findsNothing);
    await tester.ensureVisible(find.text('Limit'));
    await tester.tap(find.text('Limit'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Expert settings'));
    await tester.tap(find.text('Expert settings'));
    await tester.pumpAndSettle();
    expect(find.text('Reduce-only (never opens a new position)'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a stop-loss past the estimated liquidation is warned about, '
      'never blocked', (tester) async {
    await _pump(tester, isLong: false);
    await _openAdvanced(tester);
    await _enter(tester, 0, '100');
    final attach = find.byKey(const ValueKey('order-slip-tpsl-switch'));
    await tester.ensureVisible(attach);
    await tester.tap(attach);
    await tester.pumpAndSettle();
    // Amount, take-profit, stop-loss. A 1x short liquidates near twice
    // its entry.
    await _enter(tester, 2, '130000');
    final warning =
        find.byKey(const ValueKey('order-slip-sl-past-liquidation'));
    expect(warning, findsOneWidget);
    expect(scopeEnabled(tester), isTrue);
    await _enter(tester, 2, '61000');
    expect(warning, findsNothing);
  });

  testWidgets('H22: a price typed past the venue\'s precision reads back '
      'as the price sent', (tester) async {
    await _pump(tester);
    await _openAdvanced(tester);
    await tester.ensureVisible(find.text('Limit'));
    await tester.tap(find.text('Limit'));
    await tester.pumpAndSettle();
    await _enter(tester, 1, '59000.123456');
    // Left: the field shows what the order and its approval carry.
    await tester.ensureVisible(_field(0));
    await tester.tap(_field(0));
    await tester.pumpAndSettle();
    expect(_text(tester, 1), '59000');
  });

  testWidgets(
      'H19: on the web column a focused amount field keeps its own keys',
      (tester) async {
    await _pump(tester, typed: true, width: 1440, height: 1000);
    final field = find.byKey(const ValueKey('order-slip-typed-amount'));
    await tester.tap(field);
    await tester.enterText(field, '12');
    await tester.pump();
    final controller = tester.widget<TextField>(field).controller!;
    controller.selection = const TextSelection.collapsed(offset: 0);
    await tester.pump();
    // The page's hardware-key handler must not take a key the focused
    // field owns (it used to append it at the end, past the cursor).
    await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
    await tester.pump();
    expect(controller.text, isNot('125'));
    expect(controller.text, '12');
    // Nothing focused: the key types the amount, as the keypad would.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.digit7);
    await tester.pump();
    expect(controller.text, '127');
  });

  testWidgets(
      'EXPANDED web column: Advanced is the side panel, the same TWAP '
      'checks', (tester) async {
    await _pump(tester, typed: true, width: 1440, height: 1000);
    await _openAdvanced(tester);
    final title = find.text('Long BTC · Advanced');
    expect(title, findsOneWidget);
    // The form panel (kute_form_panel_route.dart), never a page or a
    // sheet across the window.
    expect(ModalRoute.of(tester.element(title)), isA<KuteDialogRoute>());
    await _pickType(tester, 'TWAP');
    await _enter(tester, 0, '50');
    expect(find.text(r'A TWAP order needs at least $101.31.'), findsOneWidget);
    expect(scopeEnabled(tester), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'H16: Back from Advanced while the ticket holds an accepted order '
      'keeps the ticket following it', (tester) async {
    await _pump(tester, standingEndedBefore: const {});
    RubberBandBusy band() => tester.widget<RubberBandBusy>(
        find.byKey(const ValueKey('order-slip-placement-band')));
    expect(band().haptic, isTrue);
    await _openAdvanced(tester);
    await _back(tester);
    // Still on screen, still the order's: not "left" (whose receipt and
    // haptics would go quiet).
    expect(find.byType(HlOrderSlipSheet), findsOneWidget);
    expect(band().haptic, isTrue);
    expect(tester.takeException(), isNull);
  });

  group('H5: what the receipt says about an attached trailing stop', () {
    final l10n = l10nForLanguage('en');

    test('placed: nothing', () async {
      expect(
          await hlAttachedTrailingNote(l10n,
              place: () async => true, describe: (e) => '$e'),
          isNull);
    });

    test('its approval declined: not placed, said', () async {
      final failures = <String>[];
      final note = await hlAttachedTrailingNote(l10n,
          place: () async => false,
          describe: (e) => '$e',
          onFailed: failures.add);
      expect(note,
          'The order filled, but the trailing stop was not placed because '
          'it was not approved.');
      expect(failures, ['declined']);
    });

    test('a failure: not placed, with the reason', () async {
      final note = await hlAttachedTrailingNote(l10n,
          place: () async => throw StateError('boom'),
          describe: (_) => 'The exchange refused it.');
      expect(note,
          'The order filled, but the trailing stop was not placed: The '
          'exchange refused it.');
    });
  });

  group('H20: fills are matched on the wire coin', () {
    HlFill fill(String coin) => HlFill(
        coin: coin,
        px: 1,
        sz: 1,
        side: 'B',
        time: 0,
        closedPnl: 0,
        fee: 0,
        feeToken: 'USDC',
        oid: 1,
        hash: '',
        dir: 'Open Long',
        cloid: null);

    test('a HIP-3 market (xyz:TSLA shown as TSLA)', () {
      const tsla = HlMarket(
        coin: 'TSLA',
        wireCoin: 'xyz:TSLA',
        assetId: 110003,
        kind: HlMarketKind.perp,
        szDecimals: 3,
        maxLeverage: 10,
        onlyIsolated: true,
        markPx: 400,
        midPx: 400,
        prevDayPx: 400,
        dayNtlVlm: 0,
        dex: 'xyz',
        isHip3: true,
      );
      expect(hlFillOnMarket(tsla, fill('xyz:TSLA')), isTrue);
      expect(hlFillOnMarket(tsla, fill('TSLA')), isFalse);
    });

    test('a spot pair (@107 shown as HYPE)', () {
      expect(hlFillOnMarket(_hypeSpot, fill('@107')), isTrue);
      expect(hlFillOnMarket(_hypeSpot, fill('HYPE')), isFalse);
    });
  });
}
