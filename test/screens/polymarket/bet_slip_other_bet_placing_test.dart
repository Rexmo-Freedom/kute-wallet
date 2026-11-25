// One prediction at a time (founder, 11 November 2026: "while one is
// placing can't place another. Just be clear about this you know"). A
// second bet slip while a funded prediction is still being placed says
// exactly that above its button, and the button (or the note) opens the
// prediction being placed, locked on it. The slip frees itself once that
// one is done; a deposit of its own on its way still reads as one.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/pending_polymarket_bet_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_open_orders_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider;
import 'package:kute/screens/polymarket/components/bet_slip_sheet.dart';
import 'package:kute/screens/polymarket/components/slip_chrome.dart';
import 'package:kute/screens/shared/standing_order_slips.dart';
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/services/one_balance/one_balance_state.dart'
    show OneBalanceVenue;
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/standing_orders/standing_orders_provider.dart';
import 'package:money2/money2.dart';

import '../../helpers/fake_swap_orders.dart';
import '../../helpers/runtime_policy_fixture.dart';
import '../../helpers/shell_bar_harness.dart';

const _otherNote =
    "Your other prediction is still being placed. You can place this one "
    "when it's done.";
const _depositNote =
    'Your money is on its way. This button unlocks when it lands.';

class _Prices extends LivePriceNotifier {
  @override
  LivePriceState build() => const LivePriceState();
  @override
  void acquire() {}
  @override
  void release() {}
  @override
  void addTokens(List<String> tokenIds, {bool pin = true}) {}
}

class _Trading extends PolymarketTradingNotifier {
  _Trading(this.balance);
  final double balance;
  @override
  Future<PolymarketTradingState> build() async =>
      PolymarketTradingState(usdcBalance: balance);
}

class _Currency extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _Currency() : super(CurrencyState({'USD': Fixed.fromInt(100)}));
  @override
  Future<void> updateRates() async {}
}

/// The other prediction, funded from Dollars, being placed right now.
class _Pending extends PendingPolymarketBetNotifier {
  _Pending(this.intent);
  final PendingBetIntent? intent;
  @override
  PendingBetIntent? build() => intent;
}

class _Funded extends FundedOrdersNotifier {
  _Funded(this.records);
  final List<FundedOrderRecord> records;
  @override
  List<FundedOrderRecord> build() => records;
}

const _snowPlacing = PendingBetIntent(
  tokenId: 'snow-yes',
  amount: 10,
  slippagePct: 1,
  marketQuestion: 'Will it snow?',
  outcomeName: 'Yes',
  expectedPrice: 0.5,
  status: PendingBetStatus.placing,
  fundUsd: 10,
);

StandingOrder _snowOrder(
    {StandingOrderState state = StandingOrderState.posting}) {
  final at = DateTime.now();
  return StandingOrder(
    id: 'so_snow',
    walletId: 'w',
    venue: StandingOrderVenue.predictions,
    marketKey: 'snow-yes',
    marketTitle: 'Will it snow?',
    sideLabel: 'Yes',
    isBuy: true,
    size: 20,
    approvedPrice: 0.5,
    amountUsd: 10,
    orderKind: 'fak',
    state: state,
    createdAt: at,
    updatedAt: at,
  );
}

/// A Bitcoin-funded prediction on another market, its money on its way.
FundedOrderRecord _snowRun() => FundedOrderRecord(
      id: 'fo_snow',
      label: const FundedOrderLabel(
        venue: OneBalanceVenue.predictions,
        orderUsd: 10,
        side: 'Yes',
        market: 'Will it snow?',
        marketKey: 'snow-yes',
      ),
      stage: FundedOrderStage.preparing,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      addUsd: 6,
      btcRowIds: const {'q_btc'},
    );

Future<RuntimeCapabilitiesService> _allowEverything() async {
  AffiliateService.debugSessionToken = 'test-session';
  final policy = runtimePolicyFixture();
  RuntimeCapabilitiesService.debugInstance = policy;
  expect(await policy.refresh(), isTrue);
  return policy;
}

Future<void> _release(
    WidgetTester tester, RuntimeCapabilitiesService policy) async {
  await tester.pumpWidget(const SizedBox.shrink());
  policy.dispose();
  RuntimeCapabilitiesService.debugInstance = null;
  AffiliateService.debugSessionToken = null;
}

/// The slip on its own route over a home page, as the app shows it, with
/// a $10 bet carried in and Predictions holding [balance].
Future<void> _pumpSlip(WidgetTester tester,
    {double balance = 100,
    PendingBetIntent? pending,
    List<FundedOrderRecord>? funded,
    FakeSwapOrders? swaps}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  installShellBar();
  final nav = GlobalKey<NavigatorState>();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      settingsProvider.overrideWith((ref) => SettingsModel(Settings(
            currency: 'USD',
            language: 'en',
            btcFormat: 'sats',
            backup: false,
            biometricsEnabled: false,
            bitcoinElectrumNode: '',
            nodeType: '',
            reviewDone: true,
          ))),
      polymarketTradingProvider.overrideWith(() => _Trading(balance)),
      swapOrdersProvider.overrideWith((ref) => swaps ?? FakeSwapOrders()),
      livePriceProvider.overrideWith(_Prices.new),
      polymarketOpenOrdersProvider
          .overrideWith((ref) => Stream.value(const <Order>[])),
      aiEnabledProvider.overrideWith((ref) async => false),
      usdBalanceProvider.overrideWithValue(0),
      currencyProvider.overrideWith((ref) => _Currency()),
      pendingPolymarketBetProvider.overrideWith(() => _Pending(pending)),
      if (funded != null)
        fundedOrdersProvider.overrideWith(() => _Funded(funded)),
    ],
    child: shellBarApp(
      navigatorKey: nav,
      home: const Scaffold(body: SizedBox.expand()),
    ),
  ));
  nav.currentState!.push(MaterialPageRoute<void>(
    settings: const RouteSettings(name: BetSlipSheet.routeName),
    builder: (_) => const Scaffold(
      resizeToAvoidBottomInset: false,
      body: Align(
        alignment: Alignment.bottomCenter,
        child: BetSlipSheet(
          marketQuestion: 'Will it rain?',
          outcomes: [
            PolymarketOutcome(name: 'Yes', price: 0.5, tokenId: 'rain-yes'),
            PolymarketOutcome(name: 'No', price: 0.5, tokenId: 'rain-no'),
          ],
          initialAmountUsd: 10,
        ),
      ),
    ),
  ));
  await _frames(tester);
}

/// "Deposit incoming" spins until the money lands: pump, never settle.
Future<void> _frames(WidgetTester tester, [int n = 10]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(Navigator).first));

/// The placing prediction on record, its slip captured: a reopen of it
/// counts here instead of opening a real one.
List<Set<String>> _rememberSnow(WidgetTester tester) {
  final opened = <Set<String>>[];
  _container(tester)
      .read(standingOrdersProvider.notifier)
      .debugReplace([_snowOrder()]);
  StandingOrderSlips.remember(
    venue: StandingOrderVenue.predictions,
    marketKey: 'snow-yes',
    orderId: 'so_snow',
    open: (root, follow) async => opened.add(follow),
  );
  return opened;
}

Finder _heldCta() => find.byKey(const ValueKey('bet-slip-other-placing-cta'));

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    StandingOrderSlips.debugReset();
  });
  tearDown(StandingOrderSlips.debugReset);

  testWidgets(
      'a second bet while one prediction is being placed says so, never that '
      'its money is on its way, and its button opens the one placing',
      (tester) async {
    final policy = await _allowEverything();
    await _pumpSlip(tester, pending: _snowPlacing);
    final opened = _rememberSnow(tester);
    await _frames(tester, 2);

    expect(find.text(_otherNote), findsOneWidget);
    expect(find.text(_depositNote), findsNothing);
    // The button is still this bet, and a tap opens the placing one.
    final cta = tester.widget<PolySlipCta>(_heldCta());
    expect(cta.label, contains(r'$10.00'));
    expect(cta.enabled, isTrue);
    expect(barPrimaryEnabled(tester), isTrue);

    await tapBarPrimary(tester, settle: false);
    await _frames(tester, 10);
    expect(opened, hasLength(1));
    expect(find.byType(BetSlipSheet), findsNothing);
    expect(tester.takeException(), isNull);
    await _release(tester, policy);
  });

  testWidgets('a tap on the note opens the prediction being placed too',
      (tester) async {
    final policy = await _allowEverything();
    await _pumpSlip(tester, pending: _snowPlacing);
    final opened = _rememberSnow(tester);
    await _frames(tester, 2);

    await tester.tap(find.byKey(const ValueKey('bet-slip-other-placing')));
    await _frames(tester, 10);
    expect(opened, hasLength(1));
    expect(find.byType(BetSlipSheet), findsNothing);
    await _release(tester, policy);
  });

  testWidgets(
      'a Bitcoin-funded prediction still on its way holds it the same way',
      (tester) async {
    final policy = await _allowEverything();
    await _pumpSlip(tester, funded: [_snowRun()]);
    _rememberSnow(tester);
    await _frames(tester, 2);

    expect(find.text(_otherNote), findsOneWidget);
    expect(tester.widget<PolySlipCta>(_heldCta()).enabled, isTrue);
    await _release(tester, policy);
  });

  testWidgets(
      'nothing on record to open yet: the note says it, the button waits',
      (tester) async {
    final policy = await _allowEverything();
    await _pumpSlip(tester, pending: _snowPlacing);

    expect(find.text(_otherNote), findsOneWidget);
    expect(tester.widget<PolySlipCta>(_heldCta()).enabled, isFalse);
    await _release(tester, policy);
  });

  testWidgets('once the other prediction is done the slip is free again',
      (tester) async {
    final policy = await _allowEverything();
    await _pumpSlip(tester, pending: _snowPlacing);
    _rememberSnow(tester);
    await _frames(tester, 2);
    expect(find.text(_otherNote), findsOneWidget);

    final c = _container(tester);
    c.read(pendingPolymarketBetProvider.notifier).clear();
    c
        .read(standingOrdersProvider.notifier)
        .debugReplace([_snowOrder(state: StandingOrderState.filled)]);
    await _frames(tester, 10);
    expect(find.text(_otherNote), findsNothing);
    expect(_heldCta(), findsNothing);
    expect(barPrimaryLabel(tester), contains(r'$10.00'));
    await _release(tester, policy);
  });

  testWidgets(
      'a deposit of its own on its way still reads as one, not as another '
      'prediction', (tester) async {
    final policy = await _allowEverything();
    await _pumpSlip(tester,
        balance: 0,
        swaps: FakeSwapOrders([
          poolDepositRow(id: 'ord_1', network: 'POLYGON', usd: 20),
        ]));
    final incoming = find.byKey(const ValueKey('bet-slip-deposit-incoming'));
    expect(incoming, findsOneWidget);
    expect(tester.widget<PolySlipCta>(incoming).label,
        r'Deposit incoming · $20.00');
    expect(find.text(_otherNote), findsNothing);
    await _release(tester, policy);
  });
}
