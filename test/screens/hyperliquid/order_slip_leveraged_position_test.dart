// LEVERAGE IS BLOCKED IN THIS APP (hl_exposure_rule.dart): on a market whose
// position is held above 1x or in cross (opened elsewhere), the Investing
// ticket, as a phone sheet or as the web's in-place column, with Advanced
// off or on, takes only a reduction or a close. An add or a flip keeps the
// button off with the reason above it, before any approval. Nothing is
// ever placed here.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/platform/kute_layout.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_orderbook_provider.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart'
    show hlHeldPositionProvider;
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/screens/hyperliquid/components/order_slip_sheet.dart';
import 'package:kute/screens/shared/amount_keypad_panel.dart';
import 'package:kute/services/hyperliquid/hl_exposure_rule.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:money2/money2.dart';

import '../../helpers/fake_swap_orders.dart';
import '../../helpers/shell_bar_harness.dart';

const _note = 'This position uses leverage, so here you can only reduce or '
    'close it.';

class _LivePrices extends HlLivePricesNotifier {
  @override
  HlLivePriceState build() => const HlLivePriceState(mids: {'BTC': 60000});
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

/// Every gate open; Advanced withheld when [advanced] is false.
class _Policy extends Fake implements RuntimeCapabilitiesService {
  _Policy({required this.advanced});
  final bool advanced;
  @override
  CapabilityDecision decision(String id) =>
      id == 'trading.advanced' && !advanced
          ? const CapabilityDecision(allowed: false, reason: 'disabled')
          : const CapabilityDecision(allowed: true);
  @override
  String? blockReason(String id) =>
      id == 'trading.advanced' && !advanced ? 'Advanced is off' : null;
  @override
  Future<void> ensureAllAllowed(Iterable<String> ids,
      {Duration maxAge = Duration.zero}) async {}
  @override
  int? get maxLeverage => null;
  @override
  int offeredLeverage(int venueMax) => venueMax;
}

/// The account: a BTC position of [usd] notional at 60,000 (negative: a
/// short), at 10x.
class _Account extends HlAccountNotifier {
  _Account(this.usd, {required this.cross});
  final double usd;
  final bool cross;
  @override
  Future<HlAccountSnapshot> build() async => HlAccountSnapshot(
        accountValue: 1000,
        withdrawable: 1000,
        totalMarginUsed: 50,
        positions: [
          HlPerpPosition(
            coin: 'BTC',
            szi: usd / 60000,
            entryPx: 60000,
            positionValue: usd.abs(),
            unrealizedPnl: 0,
            returnOnEquity: 0,
            liquidationPx: null,
            marginUsed: usd.abs() / 10,
            leverageType: cross ? 'cross' : 'isolated',
            leverageValue: 10,
            maxLeverage: 40,
          ),
        ],
        spotBalances: const [],
      );
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

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pump(WidgetTester tester,
    {required bool isLong,
    required double heldUsd,
    bool cross = false,
    bool advanced = false,
    bool typed = false,
    List<Override> extra = const []}) async {
  final width = typed ? 1440.0 : 390.0;
  final height = typed ? 1000.0 : 844.0;
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  installShellBar();
  final ticket = typed
      ? HlOrderSlipSheet.inPlace(
          market: _btc,
          entrySource: 'test',
          onDone: () {},
          isLong: isLong,
          typedAmount: true)
      : HlOrderSlipSheet(market: _btc, initialIsLong: isLong);
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
      hyperliquidAccountProvider
          .overrideWith(() => _Account(heldUsd, cross: cross)),
      hyperliquidWithdrawableProvider.overrideWith((_) => 1000),
      hyperliquidSpotBalancesProvider.overrideWith((_) => []),
      swapOrdersProvider.overrideWith((_) => FakeSwapOrders()),
      hyperliquidAddressProvider.overrideWith((_) async => null),
      hyperliquidOrderbookProvider
          .overrideWith((_, __) => Stream.value(const HlOrderBookState())),
      aiEnabledProvider.overrideWith((_) async => false),
      currencyProvider.overrideWith((_) => _Currency()),
      runtimeCapabilitiesProvider.overrideWithValue(_Policy(advanced: advanced)),
      ...extra,
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

Future<void> _type(WidgetTester tester, String amount,
    {bool typed = false}) async {
  if (typed) {
    final field = find.byKey(const ValueKey('order-slip-typed-amount'));
    await tester.tap(field);
    await tester.enterText(field, amount);
    await _settle(tester);
    return;
  }
  final pad = find.byType(AmountKeypad);
  final backspace =
      find.descendant(of: pad, matching: find.byIcon(Icons.backspace_rounded));
  for (var i = 0; i < 8; i++) {
    await tester.tap(backspace);
    await tester.pump();
  }
  for (final key in amount.split('')) {
    await tester.tap(find.descendant(of: pad, matching: find.text(key)));
    await tester.pump();
  }
  await _settle(tester);
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  for (final advanced in [false, true]) {
    for (final cross in [false, true]) {
      final kind = '10x ${cross ? 'cross' : 'isolated'}';
      final mode = 'Advanced ${advanced ? 'on' : 'off'}';
      group('a $kind BTC short worth \$500, $mode', () {
        testWidgets('a \$1,000 Buy (a flip): the button off, the reason above',
            (tester) async {
          await _pump(tester,
              isLong: true, heldUsd: -500, cross: cross, advanced: advanced);
          await _type(tester, '1000');
          expect(find.text(_note), findsOneWidget);
          expect(scopeEnabled(tester), isFalse);
          expect(tester.takeException(), isNull);
        });

        testWidgets('a \$100 Sell (an add): the button off, the reason above',
            (tester) async {
          await _pump(tester,
              isLong: false, heldUsd: -500, cross: cross, advanced: advanced);
          await _type(tester, '100');
          expect(find.text(_note), findsOneWidget);
          expect(scopeEnabled(tester), isFalse);
          expect(tester.takeException(), isNull);
        });

        testWidgets('a \$200 Buy (a reduction): no refusal, the button on',
            (tester) async {
          await _pump(tester,
              isLong: true, heldUsd: -500, cross: cross, advanced: advanced);
          await _type(tester, '200');
          expect(find.text(_note), findsNothing);
          expect(scopeEnabled(tester), isTrue);
          expect(tester.takeException(), isNull);
        });
      });
    }
  }

  testWidgets(
      'the web\'s in-place column (typed amount) takes the same rule: a flip '
      'refused, a reduction not', (tester) async {
    await _pump(tester, isLong: true, heldUsd: -500, typed: true);
    await _type(tester, '1000', typed: true);
    // The column draws its own button, from the same gates as the sheet's
    // (the note is shown exactly when they are shut).
    expect(find.text(_note), findsOneWidget);
    await _type(tester, '200', typed: true);
    expect(find.text(_note), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a flat market (no position) is untouched: no note, the button on',
      (tester) async {
    await _pump(tester, isLong: true, heldUsd: 0);
    await _type(tester, '100');
    expect(find.text(_note), findsNothing);
    expect(scopeEnabled(tester), isTrue);
  });

  testWidgets(
      'a position that cannot be read yet: the ticket is not shut while it '
      'loads; the tap reads it first and, unreadable, says so inline with '
      'nothing approved', (tester) async {
    var asked = 0;
    RuntimeCapabilitiesService.debugInstance = _Policy(advanced: false);
    addTearDown(() => RuntimeCapabilitiesService.debugInstance = null);
    await _pump(tester, isLong: true, heldUsd: 0, extra: [
      hlHeldPositionProvider.overrideWithValue((_) async {
        asked++;
        return const HlHeldPosition.unknown();
      }),
    ]);
    await _type(tester, '100');
    expect(scopeEnabled(tester), isTrue);
    await tapBarPrimary(tester, settle: false);
    await _settle(tester);
    expect(asked, 1);
    expect(
        find.text("Couldn't check your position on this market. Try again in "
            'a moment.'),
        findsOneWidget);
  });

  testWidgets(
      'the Advanced page, Limit: a buy against a 10x short goes only with '
      'Reduce-only on', (tester) async {
    await _pump(tester, isLong: true, heldUsd: -500, advanced: true);
    final button = find.byKey(const ValueKey('slip-advanced-button'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Limit'));
    await tester.tap(find.text('Limit'));
    await tester.pumpAndSettle();
    Future<void> enter(int i, String text) async {
      final f = find.byType(TextField).at(i);
      await tester.ensureVisible(f);
      await tester.enterText(f, text);
      await tester.pumpAndSettle();
    }

    await enter(0, '200');
    await enter(1, '59000');
    expect(find.text(_note), findsOneWidget);
    expect(scopeEnabled(tester), isFalse);
    await tester.ensureVisible(find.text('Expert settings'));
    await tester.tap(find.text('Expert settings'));
    await tester.pumpAndSettle();
    final reduce = find.text('Reduce-only (never opens a new position)');
    await tester.ensureVisible(reduce);
    await tester.tap(reduce);
    await tester.pumpAndSettle();
    expect(find.text(_note), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final cross in [false, true]) {
    testWidgets(
        'the Details row says the held 10x ${cross ? 'cross' : 'isolated'} '
        'position\'s own leverage and margin, never "1×"', (tester) async {
      await _pump(tester,
          isLong: true, heldUsd: -500, cross: cross, advanced: true);
      final button = find.byKey(const ValueKey('slip-advanced-button'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      final real = cross ? '10× · Shared balance' : '10× · Separate balance';
      expect(find.text(real, skipOffstage: false), findsWidgets);
      expect(find.text('1× · Separate balance', skipOffstage: false),
          findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a flat market: the Details row says 1× · Separate balance',
      (tester) async {
    await _pump(tester, isLong: true, heldUsd: 0, advanced: true);
    final button = find.byKey(const ValueKey('slip-advanced-button'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('1× · Separate balance', skipOffstage: false),
        findsWidgets);
  });
}
