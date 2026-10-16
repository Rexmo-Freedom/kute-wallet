// A hot Investing ticket short of venue cash funds the order from Dollars:
// the button is the order when Dollars cover the move (with the Move fee
// in the fee rows), "Add $X to Investments" when they do not (its tap
// funds X from the spending bitcoin when it covers it, else opens the
// Investments Receive sheet), and a Ledger ticket is not touched by any of
// it. "Available" is the whole spendable Investments.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_orderbook_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/providers/usd_account_provider.dart';
import 'package:kute/screens/home/components/deposit_sheet.dart'
    show MoveLockedSide;
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/screens/hyperliquid/components/hl_error_copy.dart'
    show HlTradeErrorNotice;
import 'package:kute/screens/shared/rubber_band_progress.dart';
import 'package:kute/screens/hyperliquid/components/order_slip_sheet.dart';
import 'package:kute/screens/shared/amount_keypad_panel.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/hyperliquid_fee_summary.dart';
import 'package:kute/screens/shared/money_fee_summary.dart';
import 'package:kute/screens/shared/side_tint_palette.dart'
    show slipCtaLabelColor;
import 'package:kute/services/one_balance/bitcoin_funded_order.dart'
    show
        SlipFundingDecision,
        SlipFundingRoute,
        SpendingBitcoin,
        debugBitcoinLegEstimate,
        debugFreshSpendingBitcoin,
        debugStartSlipBitcoinChain;
import 'package:kute/services/one_balance/hyperliquid_move_rail.dart';
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/services/one_balance/one_balance_state.dart'
    show OneBalanceVenue;
import 'package:kute/screens/shared/slip_shortfall.dart'
    show SlipFundingSteps, SlipVenue, debugShowSlipReceiveSheet;
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart';

import '../../helpers/fake_hyperliquid_move_rail.dart';
import '../../helpers/fake_swap_orders.dart';
import '../../helpers/runtime_policy_fixture.dart';

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

class _Funded extends FundedOrdersNotifier {
  _Funded(this.records);
  final List<FundedOrderRecord> records;
  @override
  List<FundedOrderRecord> build() => records;
}

FundedOrderRecord _btcRecord(FundedOrderStage stage,
        {String marketKey = 'BTC', bool slow = false}) =>
    FundedOrderRecord(
      id: 'fo_1',
      label: FundedOrderLabel(
        venue: OneBalanceVenue.investing,
        orderUsd: 20,
        side: 'Long',
        market: marketKey,
        marketKey: marketKey,
      ),
      stage: stage,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      addUsd: 6,
      btcRowIds: const {'q_btc'},
      slow: slow,
    );

/// An order funded from Dollars or the Predictions cash (no Bitcoin leg).
FundedOrderRecord _fundedOrder(FundedOrderStage stage,
        {FundedOrderStage? stoppedAt,
        FundedMoneyAt? moneyAt,
        String? reason,
        String? message}) =>
    FundedOrderRecord(
      id: 'fo_dollars',
      label: const FundedOrderLabel(
        venue: OneBalanceVenue.investing,
        orderUsd: 20,
        side: 'Long',
        market: 'BTC',
        marketKey: 'BTC',
      ),
      stage: stage,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      venueRowIds: const {'q_move'},
      stoppedAt: stoppedAt,
      moneyAt: moneyAt,
      reason: reason,
      message: message,
    );

Future<void> _pumpSlip(WidgetTester tester,
    {required double venueUsd,
    required double dollarsUsd,
    required FakeHyperliquidMoveRail rail,
    bool dark = false,
    List<FundedOrderRecord>? funded,
    bool withWallet = false}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
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
            wallets: withWallet
                ? [WalletConfig(id: 'w1', name: 'Spending')]
                : const [],
            activeWalletId: withWallet ? 'w1' : null,
          ))),
      hyperliquidLivePricesProvider.overrideWith(_LivePrices.new),
      hyperliquidAccountProvider.overrideWith(() => _Account(venueUsd)),
      swapOrdersProvider.overrideWith((_) => FakeSwapOrders()),
      hyperliquidAddressProvider.overrideWith((_) async => null),
      hyperliquidOrderbookProvider
          .overrideWith((_, __) => Stream.value(const HlOrderBookState())),
      aiEnabledProvider.overrideWith((_) async => false),
      currencyProvider.overrideWith((_) => _Currency()),
      runtimeCapabilitiesProvider.overrideWithValue(_Allowed()),
      usdBalanceProvider.overrideWith((_) => dollarsUsd),
      hyperliquidMoveRailProvider.overrideWithValue(rail),
      if (funded != null)
        fundedOrdersProvider.overrideWith(() => _Funded(funded)),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
          brightness: dark ? Brightness.dark : Brightness.light,
          splashFactory: NoSplash.splashFactory,
          fontFamily: 'Inter',
          extensions: [
            dark ? AppColorsExtension.dark() : AppColorsExtension.light()
          ],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: HlOrderSlipSheet(market: _market, initialIsLong: true),
          ),
        ),
      ),
    ),
  ));
  await _frames(tester);
}

/// The loading dots animate for as long as they wait: pump, never settle.
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

AppButton _button(WidgetTester tester) =>
    tester.widget<AppButton>(find.byType(AppButton));

/// The colour the ticket's one button letters its label in.
Color? _buttonLabelColor(WidgetTester tester) => tester
    .widget<Text>(find.descendant(
        of: find.byType(AppButton), matching: find.byType(Text)))
    .style
    ?.color;

/// The move fee the ticket's one fee row folds in: the summary's
/// `moveFeeUsd`, with `state` standing for its "Calculating…" while the
/// plan is still being read, in the shape the old standalone row had.
({double? usd, String? state}) _moveFeeRow(WidgetTester tester) {
  final summary = tester
      .widget<HyperliquidFeeSummary>(find.byType(HyperliquidFeeSummary));
  expect(summary.moveFeeLabel, 'Move fee');
  return (
    usd: summary.moveFeeUsd,
    state: summary.moveFeePending ? 'Calculating…' : null,
  );
}

void main() {
  late FakeHyperliquidMoveRail rail;
  late List<(String, Map<String, Object?>?)> events;

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    rail = FakeHyperliquidMoveRail();
    // A 0.1% route with the $1 gas float on an empty account.
    rail.quote = const VenueMoveQuote(
        arrivingUsd: 0,
        feeUsd: 0.02,
        fixedCostUsd: 1,
        minUsd: 0.8,
        maxUsd: 107600);
    events = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });

  tearDown(() {
    TrackingService.debugTrackObserver = null;
    debugShowHlDollarsDeposit = null;
    rail.creditedController.close();
  });

  testWidgets(
      'Dollars that cover the move: the button is the order and the Move fee shows',
      (tester) async {
    await _pumpSlip(tester, venueUsd: 0, dollarsUsd: 100, rail: rail);
    await _typeOnKeypad(tester, '20');
    final button = _button(tester);
    expect(button.text, startsWith('Go Long BTC 1x'));
    expect(button.onPressed, isNotNull);
    expect(find.text('Deposit to invest'), findsNothing);
    expect(find.textContaining('to Investments'), findsNothing);
    // The $20 order needs $20.24 at the venue; the route keeps ~0.1% and
    // the float: $21.27 leaves Dollars, $1.03 of it is the move.
    final row = _moveFeeRow(tester);
    expect(row.state, isNull);
    expect(row.usd, closeTo(1.03, 0.011));
    // One fee row: the move is a detail of the venue fee, never a second
    // "Move fee" row on the ticket.
    expect(find.text('Move fee'), findsNothing);
    final feeRow = find.descendant(
        of: find.byType(HyperliquidFeeSummary),
        matching: find.byType(MoneyFeeSummary));
    expect(feeRow, findsOneWidget);
    await tester.ensureVisible(feeRow);
    await tester.tap(feeRow);
    await _frames(tester);
    expect(find.text('Move fee'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'Investments short of the move and no bitcoin: "Add X to Investments" '
      'opens the Investments Receive sheet, never the Move sheet',
      (tester) async {
    final doors = <(MoveLockedSide, double?)>[];
    final receives = <(SlipVenue, double)>[];
    final sheet = Completer<void>();
    debugShowHlDollarsDeposit = (side, target) {
      doors.add((side, target));
      return sheet.future;
    };
    debugShowSlipReceiveSheet = (venue, addUsd) {
      receives.add((venue, addUsd));
      return sheet.future;
    };
    addTearDown(() => debugShowSlipReceiveSheet = null);
    await _pumpSlip(tester, venueUsd: 0, dollarsUsd: 5, rail: rail);
    await _typeOnKeypad(tester, '20');
    final button = _button(tester);
    expect(button.text, startsWith('Add \$'));
    expect(button.text, endsWith('to Investments'));
    expect(button.onPressed, isNotNull);
    // The $20.24 need plus the engine's safety buffer (2%, ≥ $0.25) lands,
    // so $21.68 has to leave Dollars; $5 are there.
    expect(button.text, 'Add \$16.68 to Investments');
    expect(_moveFeeRow(tester).usd, closeTo(1.03, 0.011));

    await tester.tap(find.byType(AppButton));
    await _frames(tester, 3);
    expect(receives, [(SlipVenue.investing, 16.68)]);
    expect(doors, isEmpty);
    expect(events.where((e) => e.$1 == 'slip_top_up_opened').length, 1);
    final topUp = events.singleWhere((e) => e.$1 == 'slip_top_up_opened').$2!;
    expect(topUp['suggested_source'], 'receive');
    // Exact amounts beside the legacy buckets: the $20.24 the venue lacks
    // and the $16.68 Investments lack.
    expect(topUp['shortfall_usd'], 20.24);
    expect(topUp['top_up_usd'], 16.68);
    expect(topUp['shortfall_bucket'], '10-100');
    expect(topUp['top_up_bucket'], '10-100');
    // Repeat taps while the sheet is up open nothing more.
    expect(_button(tester).onPressed, isNull);
    await tester.tap(find.byType(AppButton), warnIfMissed: false);
    await _frames(tester, 3);
    expect(receives, hasLength(1));
    sheet.complete();
    await _frames(tester, 3);
    expect(_button(tester).onPressed, isNotNull);
    expect(_button(tester).text, 'Add \$16.68 to Investments');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('nothing typed on an empty account: the minimum order, or the door for it',
      (tester) async {
    await _pumpSlip(tester, venueUsd: 0, dollarsUsd: 100, rail: rail);
    final funded = _button(tester);
    expect(funded.text, startsWith('Go Long BTC 1x'));
    expect(funded.onPressed, isNotNull);
    expect(_moveFeeRow(tester).usd, greaterThan(1));
    await tester.pumpWidget(const SizedBox.shrink());

    await _pumpSlip(tester, venueUsd: 0, dollarsUsd: 0, rail: rail);
    final door = _button(tester);
    expect(door.text, startsWith('Add \$'));
    expect(door.text, endsWith('to Investments'));
    expect(door.onPressed, isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'nothing typed, venue cash under the minimum and no Dollars: '
      '"Add \$X to Investments" from the start, the one action',
      (tester) async {
    await _pumpSlip(tester, venueUsd: 3, dollarsUsd: 0, rail: rail);
    final door = _button(tester);
    expect(door.text, startsWith('Add \$'));
    expect(door.text, endsWith('to Investments'));
    expect(door.onPressed, isNotNull);
    expect(find.textContaining('Go Long'), findsNothing);
    expect(find.byType(AppButton), findsOneWidget);
    expect(find.textContaining('to Investments'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    // The bet slip letters its button the same way (see
    // bet_slip_deposit_door_loading_test): the trade in its side colour on
    // the sheet's white ink, the "Add $X to Investments" door in black.
    testWidgets('$mode: the door contrasts with its fill, the order wears '
        'its side', (tester) async {
      await _pumpSlip(tester,
          venueUsd: 0, dollarsUsd: 0, rail: rail, dark: dark);
      await _typeOnKeypad(tester, '20');
      expect(_button(tester).text, endsWith('to Investments'));
      expect(_buttonLabelColor(tester), Colors.black);
      expect(
          _buttonLabelColor(tester),
          slipCtaLabelColor(
              fill: Colors.white, side: AppColors.marketUp, neutral: true));
      await tester.pumpWidget(const SizedBox.shrink());

      await _pumpSlip(tester,
          venueUsd: 500, dollarsUsd: 0, rail: rail, dark: dark);
      await _typeOnKeypad(tester, '20');
      expect(_button(tester).text, startsWith('Go Long BTC 1x'));
      expect(_buttonLabelColor(tester), AppColors.marketUp);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('venue cash that covers the order: no move, no Move fee row',
      (tester) async {
    await _pumpSlip(tester, venueUsd: 500, dollarsUsd: 0, rail: rail);
    await _typeOnKeypad(tester, '20');
    expect(_button(tester).text, startsWith('Go Long BTC 1x'));
    expect(_button(tester).onPressed, isNotNull);
    expect(find.text('Move fee'), findsNothing);
    final row = _moveFeeRow(tester);
    expect(row.usd, isNull);
    expect(row.state, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a route that cannot be read falls back to the route fee, never blocks',
      (tester) async {
    rail.estimateError = StateError('no estimate');
    await _pumpSlip(tester, venueUsd: 0, dollarsUsd: 100, rail: rail);
    await _typeOnKeypad(tester, '20');
    expect(_button(tester).text, startsWith('Go Long BTC 1x'));
    expect(_button(tester).onPressed, isNotNull);
    // 2% of $20.24 as the fallback.
    expect(_moveFeeRow(tester).usd, closeTo(0.42, 0.011));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  group('an order funded from bitcoin shows its steps', () {
    Future<void> pumpAt(WidgetTester tester, FundedOrderStage stage,
        {bool slow = false}) async {
      await _pumpSlip(tester,
          venueUsd: 0,
          dollarsUsd: 0,
          rail: rail,
          funded: [_btcRecord(stage, slow: slow)]);
    }

    testWidgets('adding: the first step runs, one busy button',
        (tester) async {
      await pumpAt(tester, FundedOrderStage.adding);
      final button = _button(tester);
      expect(button.text, r'Adding $6.00 to Investments');
      expect(find.text(r'Adding $6.00 to Investments'), findsOneWidget);
      expect(button.isLoading, isTrue);
      expect(button.onPressed, isNull);
      expect(find.byType(SlipFundingSteps), findsOneWidget);
      expect(find.byKey(const ValueKey('slip-funding-step-active-0')),
          findsOneWidget);
      expect(find.text('Preparing your order'), findsOneWidget);
      expect(find.text(r'Opening $20.00 Long BTC'), findsOneWidget);
      expect(find.byKey(const ValueKey('slip-funding-slow')), findsNothing);
      // Never the old "moving to Investing" wording.
      expect(find.textContaining('Moving'), findsNothing);
    });

    testWidgets('taking longer than usual is said under the steps',
        (tester) async {
      await pumpAt(tester, FundedOrderStage.adding, slow: true);
      expect(find.text('Taking longer than usual'), findsOneWidget);
    });

    testWidgets('preparing: the first step done, the second runs',
        (tester) async {
      await pumpAt(tester, FundedOrderStage.preparing);
      expect(_button(tester).text, 'Preparing your order');
      expect(find.byKey(const ValueKey('slip-funding-step-done-0')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('slip-funding-step-active-1')),
          findsOneWidget);
    });

    testWidgets('placing: the order itself, at its fresh price',
        (tester) async {
      await pumpAt(tester, FundedOrderStage.placing);
      expect(_button(tester).text, r'Opening $20.00 Long BTC');
      expect(find.byKey(const ValueKey('slip-funding-step-done-1')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('slip-funding-step-active-2')),
          findsOneWidget);
    });

    testWidgets('an old ready record adds no message above the order button',
        (tester) async {
      await _pumpSlip(tester,
          venueUsd: 0,
          dollarsUsd: 100,
          rail: rail,
          funded: [_btcRecord(FundedOrderStage.ready)]);
      await _typeOnKeypad(tester, '20');
      expect(find.text(r'Your $6.00 is in Investments. Tap to place.'),
          findsNothing);
      expect(find.byKey(const ValueKey('slip-funding-ready')), findsNothing);
      expect(_button(tester).text, startsWith('Go Long BTC'));
      expect(_button(tester).onPressed, isNotNull);
      expect(find.byType(SlipFundingSteps), findsNothing);
    });

    testWidgets('another market\'s run shows no steps here',
        (tester) async {
      await _pumpSlip(tester,
          venueUsd: 0,
          dollarsUsd: 100,
          rail: rail,
          funded: [_btcRecord(FundedOrderStage.adding, marketKey: 'ETH')]);
      expect(find.byType(SlipFundingSteps), findsNothing);
    });
  });

  group('every funded order shows its steps, whatever funds it', () {
    RubberBandProgressState band(WidgetTester tester) =>
        tester.state<RubberBandProgressState>(
            find.byKey(const ValueKey('order-slip-funded-progress')));

    testWidgets('from Dollars: the move, then the order, one busy button',
        (tester) async {
      await _pumpSlip(tester,
          venueUsd: 0,
          dollarsUsd: 100,
          rail: rail,
          funded: [_fundedOrder(FundedOrderStage.preparing)]);
      final button = _button(tester);
      expect(button.text, 'Preparing your order');
      expect(button.isLoading, isTrue);
      expect(button.onPressed, isNull);
      // Said once, in the steps: the busy button only spins, and a screen
      // reader still hears the step on it.
      expect(button.loadingLabel, isNull);
      expect(find.text('Preparing your order'), findsOneWidget);
      final said = tester.widget<Semantics>(find
          .ancestor(of: find.byType(AppButton), matching: find.byType(Semantics))
          .first);
      expect(said.properties.label, 'Preparing your order');
      expect(said.properties.liveRegion, isTrue);
      expect(find.byKey(const ValueKey('slip-funding-step-active-0')),
          findsOneWidget);
      expect(find.text(r'Opening $20.00 Long BTC'), findsOneWidget);
      // No Bitcoin step without a Bitcoin leg.
      expect(find.textContaining('to Investments'), findsNothing);
      await _frames(tester, 20);
      expect(band(tester).stretch, greaterThan(0));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('from the Predictions cash: then the order itself',
        (tester) async {
      await _pumpSlip(tester,
          venueUsd: 0,
          dollarsUsd: 100,
          rail: rail,
          funded: [_fundedOrder(FundedOrderStage.placing)]);
      expect(_button(tester).text, r'Opening $20.00 Long BTC');
      expect(find.byKey(const ValueKey('slip-funding-step-done-0')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('slip-funding-step-active-1')),
          findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        'refused once the money landed: the failed step and that the money '
        'is in Investing, never a second notice', (tester) async {
      await _pumpSlip(tester,
          venueUsd: 0,
          dollarsUsd: 100,
          rail: rail,
          funded: [
            _fundedOrder(FundedOrderStage.failed,
                stoppedAt: FundedOrderStage.placing,
                moneyAt: FundedMoneyAt.venue,
                reason: 'placement',
                message: 'Order rejected.')
          ]);
      expect(find.byKey(const ValueKey('slip-funding-step-failed-1')),
          findsOneWidget);
      expect(
          find.text(r'Order rejected. Your $20.00 is in Investing. '
              'Tap to try again.'),
          findsOneWidget);
      expect(find.byType(HlTradeErrorNotice), findsNothing);
      expect(_button(tester).isLoading, isFalse);
      await _frames(tester, 20);
      expect(band(tester).stretch, 0);
      expect(band(tester).ticking, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('closed mid-way and reopened: the current step',
        (tester) async {
      await _pumpSlip(tester,
          venueUsd: 0,
          dollarsUsd: 100,
          rail: rail,
          funded: [_fundedOrder(FundedOrderStage.preparing)]);
      expect(find.byKey(const ValueKey('slip-funding-step-active-0')),
          findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpSlip(tester,
          venueUsd: 0,
          dollarsUsd: 100,
          rail: rail,
          funded: [_fundedOrder(FundedOrderStage.placing)]);
      expect(find.byKey(const ValueKey('slip-funding-step-active-1')),
          findsOneWidget);
      expect(_button(tester).text, r'Opening $20.00 Long BTC');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        'an unfunded order (the Investing cash is there): the button is '
        'drawn up while it places',
        (tester) async {
      AffiliateService.debugSessionToken = 'test-session';
      final policy = runtimePolicyFixture();
      RuntimeCapabilitiesService.debugInstance = policy;
      addTearDown(() {
        RuntimeCapabilitiesService.debugInstance = null;
        AffiliateService.debugSessionToken = null;
      });
      expect(await policy.refresh(), isTrue);
      await _pumpSlip(tester,
          venueUsd: 100, dollarsUsd: 0, rail: rail, withWallet: true);
      await _typeOnKeypad(tester, '20');
      expect(_button(tester).text, startsWith('Go Long BTC'));
      RubberBandProgressState placement() =>
          tester.state<RubberBandProgressState>(find.descendant(
              of: find.byKey(const ValueKey('order-slip-placement-band')),
              matching: find.byType(RubberBandProgress)));
      expect(placement().stretch, 0);
      expect(placement().ticking, isFalse);
      await tester.tap(find.byType(AppButton));
      var pulled = 0.0;
      var low = double.infinity;
      var sawBusy = false;
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        final busy = tester
            .widget<AppButton>(find.descendant(
                of: find.byType(HlOrderSlipSheet),
                matching: find.byType(AppButton)))
            .isLoading;
        sawBusy = sawBusy || busy;
        final s = placement().stretch;
        if (busy && s > pulled) pulled = s;
        if (!busy && sawBusy && s < low) low = s;
      }
      expect(sawBusy, isTrue);
      expect(pulled, greaterThan(0));
      expect(pulled, lessThanOrEqualTo(RubberBandProgress.defaultMaxStretch));
      // No funded steps for an order the cash already covers.
      expect(find.byType(SlipFundingSteps), findsNothing);
      // Never past rest on the way (the success and failure releases are
      // the button's own: slip_cta_rubber_band_test).
      expect(low, greaterThanOrEqualTo(-1e-9));
      await tester.pumpWidget(const SizedBox.shrink());
      policy.dispose();
      // The harness has no venue: let its reads time out.
      await tester.pump(const Duration(minutes: 1));
    });
  });

  group('the "Add" door decides on the spending bitcoin at the tap', () {
    // The same decision and states as the bet slip
    // (bet_slip_deposit_door_loading_test): parity.
    late List<SlipFundingDecision> chains;
    late List<double> receives;
    late List<double?> doors;

    setUp(() {
      chains = [];
      receives = [];
      doors = [];
      debugStartSlipBitcoinChain = (venue, decision) async {
        expect(venue, OneBalanceVenue.investing);
        chains.add(decision);
      };
      debugShowSlipReceiveSheet = (venue, addUsd) async {
        receives.add(addUsd);
      };
      debugShowHlDollarsDeposit = (side, target) async {
        doors.add(target);
      };
      // The route keeps 0.5%.
      debugBitcoinLegEstimate = (sats) async => sats / 1e8 * 60000 * 0.995;
    });

    tearDown(() {
      debugStartSlipBitcoinChain = null;
      debugShowSlipReceiveSheet = null;
      debugBitcoinLegEstimate = null;
      debugFreshSpendingBitcoin = null;
    });

    testWidgets(
        'a first tap while the bitcoin is still loading waits, busy, then '
        'runs the chain once it is read: no sheet', (tester) async {
      final fresh = Completer<SpendingBitcoin?>();
      debugFreshSpendingBitcoin = () => fresh.future;
      await _pumpSlip(tester, venueUsd: 0, dollarsUsd: 5, rail: rail);
      await _typeOnKeypad(tester, '20');
      expect(_button(tester).text, 'Add \$16.68 to Investments');

      await tester.tap(find.byType(AppButton));
      await _frames(tester, 3);
      // The balance is still being read: the door's own busy state, never
      // a sheet.
      expect(_button(tester).isLoading, isTrue);
      expect(_button(tester).loadingLabel, 'Calculating…');
      expect(_button(tester).onPressed, isNull);
      expect(chains, isEmpty);
      expect(receives, isEmpty);
      expect(doors, isEmpty);

      fresh.complete((sats: 100000, usdPerBtc: 60000.0));
      await _frames(tester, 3);
      expect(chains, hasLength(1));
      expect(chains.single.route, SlipFundingRoute.bitcoin);
      expect(chains.single.addUsd, 16.68);
      expect(chains.single.plan!.targetUsd, 16.68);
      expect(chains.single.plan!.maxSats, lessThanOrEqualTo(100000));
      expect(receives, isEmpty);
      expect(doors, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        "bitcoin short of X once the route's spread is counted: the "
        'Investments Receive sheet for X, never the chain or the Move sheet',
        (tester) async {
      // $16.68 of bitcoin for an X of $16.68: the route keeps 0.5%.
      debugFreshSpendingBitcoin = () async =>
          (sats: (16.68 / 60000 * 1e8).round(), usdPerBtc: 60000.0);
      await _pumpSlip(tester, venueUsd: 0, dollarsUsd: 5, rail: rail);
      await _typeOnKeypad(tester, '20');
      await tester.tap(find.byType(AppButton));
      await _frames(tester, 3);
      expect(receives, [16.68]);
      expect(chains, isEmpty);
      expect(doors, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  testWidgets(
      'Available is the whole spendable Investments, and Max fills an order '
      'the ticket funds itself', (tester) async {
    // $0.49 of Investing cash and $8.10 in Dollars (the founder's case:
    // the ticket read "Available $0.49").
    await _pumpSlip(tester, venueUsd: 0.49, dollarsUsd: 8.10, rail: rail);
    expect(find.textContaining(r'Available $8.59'), findsOneWidget);
    expect(find.textContaining(r'Available $0.49'), findsNothing);
    // The minimum stays on the line.
    expect(find.textContaining('Minimum'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());

    // Enough in Dollars to clear the venue minimum: Max is an order past
    // the $0.49 here that the move from Dollars covers, so the button is
    // the order, never "Add".
    await _pumpSlip(tester, venueUsd: 0.49, dollarsUsd: 30, rail: rail);
    expect(find.textContaining(r'Available $30.49'), findsOneWidget);
    await tester.tap(find.text('Max'));
    await _frames(tester, 15);
    final button = _button(tester);
    expect(button.text, startsWith('Go Long BTC'));
    expect(button.onPressed, isNotNull);
    expect(find.textContaining('to Investments'), findsNothing);
    // Most of the $30.49, less the move's and the order's costs.
    final margin = double.parse(button.text.split(r'$').last);
    expect(margin, greaterThan(25));
    expect(margin, lessThan(30.49));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
