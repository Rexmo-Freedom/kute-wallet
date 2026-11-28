// "Protect it" and the close sheet's Advanced page, before any approval:
//
//   * the stop / take trigger is never prefilled at the price (it would
//     fire at once); a long's stop over the price, a short's under it, a
//     long's take under it, a short's over it, are refused inline with the
//     button off; a stop past liquidation is warned, not blocked;
//   * a Ledger's Protect it opens on a Limit close with no price, never a
//     ready market close;
//   * an existing stop loss is said, with Replace it / Add another;
//   * a whole-position close says it also cancels the left-over stops;
//   * a size the lot floors to nothing, and a trailing stop with no
//     amount, are said inline, the button / row off.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/advisor_provider.dart' show aiEnabledProvider;
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/hyperliquid/components/close_position_sheet.dart';
import 'package:kute/screens/polymarket/components/slip_chrome.dart';
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:money2/money2.dart';

import '../../helpers/shell_bar_harness.dart';

class _LivePrices extends HlLivePricesNotifier {
  @override
  HlLivePriceState build() => const HlLivePriceState(mids: {'BTC': 66000});
  @override
  void watchCoins(List<String> coins, {Map<String, String>? wire}) {}
  @override
  void focus(String coin, {String? wire}) {}
  @override
  void unfocus(String coin) {}
  @override
  void acquire() {}
  @override
  void release() {}
}

class _Currency extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _Currency() : super(CurrencyState({'USD': Fixed.fromInt(100)}));
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
  bool allows(String id) => true;
}

class _Trading extends HyperliquidTradingNotifier {
  _Trading(this.orders);
  final List<HlOpenOrder> orders;
  @override
  Future<HyperliquidTradingState> build() async =>
      HyperliquidTradingState(isInitialized: true, openOrders: orders);
}

const _btc = HlMarket(
  coin: 'BTC',
  wireCoin: 'BTC',
  assetId: 0,
  kind: HlMarketKind.perp,
  szDecimals: 5,
  maxLeverage: 40,
  onlyIsolated: false,
  markPx: 66000,
  midPx: 66000,
  prevDayPx: 65000,
  dayNtlVlm: 1e9,
);

const _long = HlPerpPosition(
  coin: 'BTC',
  szi: 0.5,
  entryPx: 64000,
  positionValue: 33000,
  unrealizedPnl: 0,
  returnOnEquity: 0,
  liquidationPx: 58000,
  marginUsed: 33000,
  leverageType: 'isolated',
  leverageValue: 1,
  maxLeverage: 40,
);

const _short = HlPerpPosition(
  coin: 'BTC',
  szi: -0.5,
  entryPx: 68000,
  positionValue: 33000,
  unrealizedPnl: 0,
  returnOnEquity: 0,
  liquidationPx: 74000,
  marginUsed: 33000,
  leverageType: 'isolated',
  leverageValue: 1,
  maxLeverage: 40,
);

const _stop = HlOpenOrder(
  coin: 'BTC',
  oid: 11,
  isBuy: false,
  limitPx: 57000,
  sz: 0.5,
  origSz: 0.5,
  timestamp: 1,
  cloid: null,
  reduceOnly: true,
  orderType: 'Stop Market',
  isTrigger: true,
  triggerPx: 60000,
);

Future<void> _pump(WidgetTester tester,
    {HlPerpPosition position = _long,
    String? ledger,
    List<HlOpenOrder> orders = const [],
    Widget? home}) async {
  tester.view.physicalSize = const Size(430, 932) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  OpenOnce.reset();
  addTearDown(OpenOnce.reset);
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
            nodeType: '',
            reviewDone: true,
          ))),
      hyperliquidLivePricesProvider.overrideWith(_LivePrices.new),
      hyperliquidPerpPositionsProvider.overrideWith((_) => [position]),
      hyperliquidAddressProvider.overrideWith((_) async => null),
      hyperliquidTradingProvider.overrideWith(() => _Trading(orders)),
      currencyProvider.overrideWith((_) => _Currency()),
      runtimeCapabilitiesProvider.overrideWithValue(_Allowed()),
      aiEnabledProvider.overrideWith((_) async => false),
    ],
    child: shellBarApp(
      // The trading state is alive wherever a position is (the Investing
      // screens keep it): watched above the page, as there.
      wrap: (context, child) => Consumer(builder: (context, ref, _) {
        ref.watch(hyperliquidTradingProvider);
        return child!;
      }),
      home: home ??
          Scaffold(
            body: Consumer(
              builder: (context, ref, _) => Center(
                child: TextButton(
                  onPressed: () => HlClosePositionSheet.showProtect(context, ref,
                      position: position,
                      market: _btc,
                      ledgerWalletId: ledger),
                  child: const Text('open protect'),
                ),
              ),
            ),
          ),
    ),
  ));
  await tester.pump();
}

Future<void> _openProtect(WidgetTester tester) async {
  await tester.tap(find.text('open protect'));
  await tester.pumpAndSettle();
}

bool _ctaEnabled(WidgetTester tester) =>
    tester.widget<PolySlipCta>(find.byType(PolySlipCta)).enabled;

/// The field behind [label]: the hero amount's, or a stepper's own
/// (HlStepField).
Finder _field(String label) => label == 'Amount'
    ? find.descendant(
        of: find.byKey(const ValueKey('hl-close-adv-amount')),
        matching: find.byType(TextField))
    : find.byKey(ValueKey(switch (label) {
        'Trigger price' => 'hl-close-field-trigger',
        'Limit price' => 'hl-close-field-limit',
        _ => 'hl-close-field-twap',
      }));

Future<void> _type(WidgetTester tester, String label, String value) async {
  await tester.enterText(_field(label).first, value);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('hot Protect it: a stop market of the whole position, its '
      'trigger empty (never the price now), the button off until set',
      (tester) async {
    await _pump(tester);
    await _openProtect(tester);
    expect(find.text('Stop market'), findsWidgets);
    expect(find.text('Enter a trigger price.'), findsOneWidget);
    expect(_ctaEnabled(tester), isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final (name, position, kind, bad, good, error) in [
    (
      'long stop',
      _long,
      'stop',
      '67000',
      '60000',
      'Set the stop loss below the current price, or it closes the position at once.'
    ),
    (
      'short stop',
      _short,
      'stop',
      '65000',
      '70000',
      'Set the stop loss above the current price, or it closes the position at once.'
    ),
    (
      'long take',
      _long,
      'take',
      '65000',
      '70000',
      'Set the take profit above the current price, or it closes the position at once.'
    ),
    (
      'short take',
      _short,
      'take',
      '67000',
      '60000',
      'Set the take profit below the current price, or it closes the position at once.'
    ),
  ]) {
    testWidgets('$name on the wrong side of the price (and the price '
        'itself) is refused inline, the button off; the right side enables',
        (tester) async {
      await _pump(tester, position: position);
      await _openProtect(tester);
      if (kind == 'take') {
        await tester.tap(find.text('Stop market').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Take market').last);
        await tester.pumpAndSettle();
        // Switching type never fills the trigger in.
        expect(find.text('Enter a trigger price.'), findsOneWidget);
      }
      await _type(tester, 'Trigger price', bad);
      expect(find.text(error), findsOneWidget);
      expect(_ctaEnabled(tester), isFalse);
      await _type(tester, 'Trigger price', '66000');
      expect(find.text(error), findsOneWidget);
      expect(_ctaEnabled(tester), isFalse);
      await _type(tester, 'Trigger price', good);
      expect(find.text(error), findsNothing);
      expect(_ctaEnabled(tester), isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a long stop past the liquidation price is warned, not blocked',
      (tester) async {
    await _pump(tester);
    await _openProtect(tester);
    await _type(tester, 'Trigger price', '57000');
    expect(find.byKey(const ValueKey('hl-protect-liq-warning')), findsOneWidget);
    expect(_ctaEnabled(tester), isTrue);
  });

  testWidgets('a stop limit resting above its trigger on a long is refused',
      (tester) async {
    await _pump(tester);
    await _openProtect(tester);
    await tester.tap(find.text('Stop market').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop limit').last);
    await tester.pumpAndSettle();
    await _type(tester, 'Trigger price', '60000');
    await _type(tester, 'Limit price', '61000');
    expect(find.text('Set the limit price at or below the trigger price.'),
        findsOneWidget);
    expect(_ctaEnabled(tester), isFalse);
    await _type(tester, 'Limit price', '59500');
    expect(_ctaEnabled(tester), isTrue);
  });

  testWidgets('Ledger Protect it opens on a Limit close with no price: never '
      'a ready "Close 100% now" market close', (tester) async {
    await _pump(tester, ledger: 'ledger-1');
    await _openProtect(tester);
    expect(find.text('Close 100% now'), findsNothing);
    expect(find.text('Enter a limit price.'), findsOneWidget);
    expect(_ctaEnabled(tester), isFalse);
    // The trailing stop is right there.
    expect(find.byKey(const ValueKey('hl-close-trailing-stop')), findsOneWidget);
  });

  testWidgets('an existing stop loss is said, with Replace it / Add another',
      (tester) async {
    await _pump(tester, orders: const [_stop]);
    await _openProtect(tester);
    final note = find.byKey(const ValueKey('hl-protect-existing-stop'));
    expect(note, findsOneWidget);
    expect(
        find.descendant(
            of: note, matching: find.textContaining('a stop loss at \$60,000')),
        findsOneWidget);
    expect(find.text('Replace it'), findsOneWidget);
    expect(find.text('Add another'), findsOneWidget);
  });

  testWidgets('a trailing stop with no amount says so and takes no tap; a '
      'size the lot floors to nothing is refused inline', (tester) async {
    await _pump(tester);
    await _openProtect(tester);
    await _type(tester, 'Amount', '');
    final row = tester.widget<ListTile>(
        find.byKey(const ValueKey('hl-close-trailing-stop')));
    expect(row.onTap, isNull);
    expect(find.text('Enter an amount'), findsWidgets);
    await _type(tester, 'Trigger price', '60000');
    await _type(tester, 'Amount', '0.000001');
    expect(find.text('Amount is too small'), findsOneWidget);
    expect(_ctaEnabled(tester), isFalse);
  });

  testWidgets('a whole-position close says it also cancels the left-over '
      'stops; a partial one does not', (tester) async {
    await _pump(tester,
        orders: const [_stop],
        home: const Scaffold(
            body: HlClosePositionSheet(position: _long, market: _btc)));
    await tester.pumpAndSettle();
    final note = find.byKey(const ValueKey('hl-close-leftovers-note'));
    expect(note, findsNothing);
    await tester.tap(find.bySemanticsLabel('Use maximum'));
    await tester.pumpAndSettle();
    expect(note, findsOneWidget);
    expect(
        find.text(
            'Closing all of it also cancels its stop and take-profit orders (1).'),
        findsOneWidget);
  });
}
