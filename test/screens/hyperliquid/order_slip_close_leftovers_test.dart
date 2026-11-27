// The order slip's whole-position close says what it does to the
// position's left-over stops and takes, as the close sheet does:
//
//   * before Confirm, the close sheet's line ("Closing all of it also
//     cancels its stop and take-profit orders (n).") when the order
//     closes the whole position and such orders rest on it, on the phone
//     sheet and on the web's in-place column; never for a partial close,
//     never when there are none;
//   * on the receipt, the close sheet's rows: how many were cancelled, how
//     many are still open (with its line to cancel them in Orders);
//   * on a Ledger, the close sheet's Ledger row and line (each cancel
//     needs the device, so they stay).
//
// Nothing is ever placed here.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/platform/kute_layout.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_orderbook_provider.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/screens/hyperliquid/components/order_placed_overlay.dart';
import 'package:kute/screens/hyperliquid/components/order_slip_sheet.dart';
import 'package:kute/screens/shared/amount_keypad_panel.dart';
import 'package:kute/screens/shared/kute_success_overlay.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart';

import '../../helpers/fake_swap_orders.dart';
import '../../helpers/kute_bar_test_support.dart';
import '../../helpers/shell_bar_harness.dart';

const _noteKey = ValueKey('order-slip-leftovers-note');

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

class _Policy extends Fake implements RuntimeCapabilitiesService {
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

/// A 1x isolated BTC long worth $600 (0.01 BTC at 60,000).
const _held = HlPerpPosition(
  coin: 'BTC',
  szi: 0.01,
  entryPx: 60000,
  positionValue: 600,
  unrealizedPnl: 0,
  returnOnEquity: 0,
  liquidationPx: null,
  marginUsed: 600,
  leverageType: 'isolated',
  leverageValue: 1,
  maxLeverage: 40,
);

class _Account extends HlAccountNotifier {
  @override
  Future<HlAccountSnapshot> build() async => const HlAccountSnapshot(
        accountValue: 1000,
        withdrawable: 400,
        totalMarginUsed: 600,
        positions: [_held],
        spotBalances: [],
      );
}

class _Trading extends HyperliquidTradingNotifier {
  _Trading(this.orders);
  final List<HlOpenOrder> orders;
  @override
  Future<HyperliquidTradingState> build() async => HyperliquidTradingState(
      isInitialized: true,
      withdrawable: 400,
      positions: const [_held],
      openOrders: orders);
}

HlOpenOrder _trigger(int oid, String tpsl) => HlOpenOrder(
      coin: 'BTC',
      oid: oid,
      isBuy: false,
      limitPx: 50000,
      sz: 0.01,
      origSz: 0.01,
      timestamp: oid,
      cloid: null,
      reduceOnly: true,
      orderType: tpsl == 'tp' ? 'Take Profit Market' : 'Stop Market',
      isTrigger: true,
      triggerPx: tpsl == 'tp' ? 70000 : 50000,
    );

final _protective = [_trigger(11, 'sl'), _trigger(12, 'tp')];

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
    {required List<HlOpenOrder> orders, bool typed = false}) async {
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
          isLong: false,
          typedAmount: true)
      : const HlOrderSlipSheet(market: _btc, initialIsLong: false);
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
      hyperliquidAccountProvider.overrideWith(_Account.new),
      hyperliquidTradingProvider.overrideWith(() => _Trading(orders)),
      hyperliquidWithdrawableProvider.overrideWith((_) => 400),
      hyperliquidSpotBalancesProvider.overrideWith((_) => []),
      swapOrdersProvider.overrideWith((_) => FakeSwapOrders()),
      hyperliquidAddressProvider.overrideWith((_) async => null),
      hyperliquidOrderbookProvider
          .overrideWith((_, __) => Stream.value(const HlOrderBookState())),
      aiEnabledProvider.overrideWith((_) async => false),
      currencyProvider.overrideWith((_) => _Currency()),
      runtimeCapabilitiesProvider.overrideWithValue(_Policy()),
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

const _line =
    'Closing all of it also cancels its stop and take-profit orders (2).';

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('before Confirm', () {
    testWidgets(
        'a Sell of the whole long (it nets to zero): the close sheet\'s '
        'line, with the count', (tester) async {
      await _pump(tester, orders: _protective);
      await _type(tester, '600');
      expect(find.byKey(_noteKey), findsOneWidget);
      expect(find.text(_line), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a partial close: no line', (tester) async {
      await _pump(tester, orders: _protective);
      await _type(tester, '300');
      expect(find.byKey(_noteKey), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no stops or takes on it: no line', (tester) async {
      await _pump(tester, orders: const []);
      await _type(tester, '600');
      expect(find.byKey(_noteKey), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the web\'s in-place column says it the same way',
        (tester) async {
      await _pump(tester, orders: _protective, typed: true);
      await _type(tester, '600', typed: true);
      expect(find.text(_line), findsOneWidget);
      await _type(tester, '300', typed: true);
      expect(find.byKey(_noteKey), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('the receipt', () {
    final rootKey = GlobalKey<NavigatorState>();
    setUp(() => KuteConfirmation.debugFeedbackOverride = () async {});
    tearDown(() => KuteConfirmation.debugFeedbackOverride = null);

    Future<void> pumpReceipt(WidgetTester tester,
        ({int cancelled, int failed})? leftovers) async {
      await tester.pumpWidget(ProviderScope(
          child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          navigatorKey: rootKey,
          theme: buildLightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: withKuteShellBar,
          home: const Scaffold(body: Text('host')),
        ),
      )));
      pushHlOrderPlacedOverlay(
        navigator: rootKey.currentState!,
        coin: 'BTC',
        isLong: false,
        leverage: 1,
        isSpot: false,
        sizeFilled: 0.01,
        avgPx: 60000,
        notionalUsd: 600,
        leftovers: leftovers,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('what the cancel did, as the close sheet says it',
        (tester) async {
      await pumpReceipt(tester, (cancelled: 2, failed: 0));
      expect(find.text('Protective orders cancelled'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('Protective orders still open'), findsNothing);
    });

    testWidgets('one the venue would not cancel: still open, and the line',
        (tester) async {
      await pumpReceipt(tester, (cancelled: 1, failed: 1));
      expect(find.text('Protective orders cancelled'), findsOneWidget);
      expect(find.text('Protective orders still open'), findsOneWidget);
      expect(
          find.textContaining('could not be cancelled. Cancel them in Orders'),
          findsOneWidget);
    });

    testWidgets('no cancel ran: no rows', (tester) async {
      await pumpReceipt(tester, null);
      expect(find.text('Protective orders cancelled'), findsNothing);
      expect(find.text('Protective orders still open'), findsNothing);
    });
  });

  group('a Ledger close of the whole position', () {
    final l = lookupAppLocalizations(const Locale('en'));

    test('its stops and takes stay: counted, with the close sheet\'s line',
        () {
      final r = hlLedgerLeftoverReceipt(l, 2);
      expect(r.rows, {'Protective orders still open': '2'});
      expect(r.note, l.hlLeftLedgerStopsOpen);
    });

    test('its orders could not be read: the line, no count', () {
      final r = hlLedgerLeftoverReceipt(l, -1);
      expect(r.rows, isEmpty);
      expect(r.note, l.hlLeftLedgerStopsOpen);
    });

    test('none, or not a whole close: nothing said', () {
      final r = hlLedgerLeftoverReceipt(l, null);
      expect(r.rows, isEmpty);
      expect(r.note, isNull);
    });
  });
}
