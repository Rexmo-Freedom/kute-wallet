// One Investing order at a time (founder, 11 November 2026, on a second
// ticket while one was placing: "while one is placing can't place another.
// Just be clear about this you know"). The second ticket says exactly that
// above its button, never "Your money is on its way", and the button (or
// the note) opens the order being placed, locked on it. The ticket frees
// itself once that order is done; a deposit of its own on its way still
// reads as one.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_orderbook_provider.dart';
import 'package:kute/providers/pending_hyperliquid_order_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/providers/usd_account_provider.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/screens/hyperliquid/components/order_slip_sheet.dart';
import 'package:kute/screens/shared/amount_keypad_panel.dart';
import 'package:kute/screens/shared/standing_order_slips.dart';
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/services/one_balance/hyperliquid_move_rail.dart';
import 'package:kute/services/one_balance/one_balance_state.dart'
    show OneBalanceVenue;
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/standing_orders/standing_orders_provider.dart';
import 'package:money2/money2.dart';

import '../../helpers/fake_hyperliquid_move_rail.dart';
import '../../helpers/fake_swap_orders.dart';
import '../../helpers/shell_bar_harness.dart';

const _otherNote =
    "Your other order is still being placed. You can place this one when "
    "it's done.";
const _depositNote =
    'Your money is on its way. This button unlocks when it lands.';

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

class _Account extends HlAccountNotifier {
  _Account(this.withdrawable);
  final double withdrawable;
  @override
  Future<HlAccountSnapshot> build() async => HlAccountSnapshot(
        accountValue: withdrawable,
        withdrawable: withdrawable,
        totalMarginUsed: 0,
        positions: const [],
        spotBalances: const [],
      );
}

/// The other order: a short on ETH being placed right now.
class _Placing extends PendingHyperliquidOrderNotifier {
  _Placing(this.intent);
  final PendingHlOrderIntent? intent;
  @override
  PendingHlOrderIntent? build() => intent;
}

class _Funded extends FundedOrdersNotifier {
  _Funded(this.records);
  final List<FundedOrderRecord> records;
  @override
  List<FundedOrderRecord> build() => records;
}

const _market = HlMarket(
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

PendingHlOrderIntent _ethPlacing() => PendingHlOrderIntent(
      coin: 'ETH',
      kind: HlMarketKind.perp,
      isLong: false,
      marginUsd: 10,
      leverage: 1,
      slippagePct: 1,
      expectedPx: 3000,
      marketLabel: 'ETH · Perp',
      status: PendingHlOrderStatus.placing,
    );

StandingOrder _ethOrder(
    {StandingOrderState state = StandingOrderState.posting}) {
  final at = DateTime.now();
  return StandingOrder(
    id: 'so_eth',
    walletId: 'w1',
    venue: StandingOrderVenue.investing,
    marketKey: 'ETH',
    marketTitle: 'ETH · Perp',
    sideLabel: 'short',
    isBuy: false,
    size: 1,
    approvedPrice: 3000,
    amountUsd: 10,
    orderKind: 'market',
    state: state,
    createdAt: at,
    updatedAt: at,
  );
}

/// A Bitcoin-funded order on ETH whose money is still on its way.
FundedOrderRecord _ethRun() => FundedOrderRecord(
      id: 'fo_eth',
      label: const FundedOrderLabel(
        venue: OneBalanceVenue.investing,
        orderUsd: 10,
        side: 'Short',
        market: 'ETH',
        marketKey: 'ETH',
      ),
      stage: FundedOrderStage.preparing,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      addUsd: 6,
      btcRowIds: const {'q_btc'},
    );

/// The ticket on its own route over a home page, as the app shows it: the
/// venue holds [venueUsd], Dollars [dollarsUsd].
Future<void> _pumpSlip(WidgetTester tester,
    {double venueUsd = 5,
    double dollarsUsd = 100,
    PendingHlOrderIntent? placing,
    List<FundedOrderRecord>? funded,
    List<SwapOrder> swaps = const []}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  installShellBar();
  final rail = FakeHyperliquidMoveRail()
    ..quote = const VenueMoveQuote(
        arrivingUsd: 0,
        feeUsd: 0.02,
        fixedCostUsd: 1,
        minUsd: 0.8,
        maxUsd: 107600);
  addTearDown(rail.creditedController.close);
  final nav = GlobalKey<NavigatorState>();
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
            wallets: const [],
          ))),
      hyperliquidLivePricesProvider.overrideWith(_LivePrices.new),
      hyperliquidAccountProvider.overrideWith(() => _Account(venueUsd)),
      swapOrdersProvider.overrideWith((_) => FakeSwapOrders(swaps)),
      hyperliquidAddressProvider.overrideWith((_) async => null),
      hyperliquidOrderbookProvider
          .overrideWith((_, __) => Stream.value(const HlOrderBookState())),
      aiEnabledProvider.overrideWith((_) async => false),
      currencyProvider.overrideWith((_) => _Currency()),
      runtimeCapabilitiesProvider.overrideWithValue(_Allowed()),
      usdBalanceProvider.overrideWith((_) => dollarsUsd),
      hyperliquidMoveRailProvider.overrideWithValue(rail),
      pendingHyperliquidOrderProvider.overrideWith(() => _Placing(placing)),
      if (funded != null)
        fundedOrdersProvider.overrideWith(() => _Funded(funded)),
    ],
    child: shellBarApp(
      navigatorKey: nav,
      home: const Scaffold(body: SizedBox.expand()),
    ),
  ));
  nav.currentState!.push(MaterialPageRoute<void>(
    settings: const RouteSettings(name: HlOrderSlipSheet.routeName),
    builder: (_) => const Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: HlOrderSlipSheet(market: _market, initialIsLong: true),
      ),
    ),
  ));
  await _frames(tester);
}

Future<void> _frames(WidgetTester tester, [int n = 10]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _typeOnKeypad(WidgetTester tester, String amount) async {
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
  await _frames(tester);
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(Navigator).first));

/// The placing order on record, its slip captured: a reopen of it counts
/// here instead of opening a real one.
List<Set<String>> _rememberEth(WidgetTester tester) {
  final opened = <Set<String>>[];
  _container(tester)
      .read(standingOrdersProvider.notifier)
      .debugReplace([_ethOrder()]);
  StandingOrderSlips.remember(
    venue: StandingOrderVenue.investing,
    marketKey: 'ETH',
    orderId: 'so_eth',
    open: (root, follow) async => opened.add(follow),
  );
  return opened;
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    StandingOrderSlips.debugReset();
  });
  tearDown(StandingOrderSlips.debugReset);

  testWidgets(
      'a second ticket while one order is being placed says so, never that '
      'its money is on its way, and its button opens the one placing',
      (tester) async {
    await _pumpSlip(tester, placing: _ethPlacing());
    final opened = _rememberEth(tester);
    await _typeOnKeypad(tester, '20');

    expect(find.text(_otherNote), findsOneWidget);
    expect(find.text(_depositNote), findsNothing);
    // The button is still this order, and a tap opens the placing one.
    expect(barPrimaryLabel(tester), contains(r'$20.00'));
    expect(barPrimaryEnabled(tester), isTrue);

    await tapBarPrimary(tester, settle: false);
    await _frames(tester, 10);
    expect(opened, hasLength(1));
    expect(find.byType(HlOrderSlipSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tap on the note opens the order being placed too',
      (tester) async {
    await _pumpSlip(tester, placing: _ethPlacing());
    final opened = _rememberEth(tester);
    await _typeOnKeypad(tester, '20');

    await tester.tap(find.byKey(const ValueKey('order-slip-other-placing')));
    // The ticket's route closes under the one placing.
    await _frames(tester, 10);
    expect(opened, hasLength(1));
    expect(find.byType(HlOrderSlipSheet), findsNothing);
  });

  testWidgets(
      'a Bitcoin-funded order on another market still on its way holds it '
      'the same way', (tester) async {
    await _pumpSlip(tester, funded: [_ethRun()]);
    _rememberEth(tester);
    await _typeOnKeypad(tester, '20');

    expect(find.text(_otherNote), findsOneWidget);
    expect(find.text(_depositNote), findsNothing);
    expect(barPrimaryEnabled(tester), isTrue);
  });

  testWidgets(
      'nothing on record to open yet: the note says it, the button waits',
      (tester) async {
    await _pumpSlip(tester, placing: _ethPlacing());
    await _typeOnKeypad(tester, '20');

    expect(find.text(_otherNote), findsOneWidget);
    expect(barPrimaryEnabled(tester), isFalse);
  });

  testWidgets('once the other order is done the ticket is free again',
      (tester) async {
    await _pumpSlip(tester, placing: _ethPlacing());
    _rememberEth(tester);
    await _typeOnKeypad(tester, '20');
    expect(find.text(_otherNote), findsOneWidget);

    final c = _container(tester);
    c.read(pendingHyperliquidOrderProvider.notifier).clear();
    c
        .read(standingOrdersProvider.notifier)
        .debugReplace([_ethOrder(state: StandingOrderState.filled)]);
    await _frames(tester, 3);
    expect(find.text(_otherNote), findsNothing);
    expect(barPrimaryLabel(tester), contains(r'$20.00'));
  });

  testWidgets(
      'an order the venue covers is never held: nothing to move, nothing to '
      'wait for', (tester) async {
    await _pumpSlip(tester, venueUsd: 100, placing: _ethPlacing());
    _rememberEth(tester);
    await _typeOnKeypad(tester, '20');
    expect(find.text(_otherNote), findsNothing);
  });

  testWidgets(
      'a deposit of its own on its way still reads as one, not as another '
      'order', (tester) async {
    await _pumpSlip(tester,
        venueUsd: 0,
        dollarsUsd: 0,
        swaps: [poolDepositRow(id: 'ord_1', network: 'HYPERCORE', usd: 25)]);
    expect(barPrimaryLabel(tester), r'Deposit incoming · $25.00');
    expect(barPrimaryEnabled(tester), isFalse);
    expect(find.text(_otherNote), findsNothing);
  });
}
