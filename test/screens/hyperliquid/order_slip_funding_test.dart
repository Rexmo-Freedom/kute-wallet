// A hot Investing ticket short of venue cash funds the order from Dollars:
// the button is the order when Dollars cover the move (with the Move fee
// in the fee rows), "Add $X to Investments" (the Dollar deposit door,
// prefilled with what is missing) when they do not, and a Ledger ticket
// is not touched by any of it.

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
import 'package:kute/screens/hyperliquid/components/order_slip_sheet.dart';
import 'package:kute/screens/shared/amount_keypad_panel.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/hyperliquid_fee_summary.dart';
import 'package:kute/screens/shared/money_fee_summary.dart';
import 'package:kute/services/one_balance/hyperliquid_move_rail.dart';
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart';

import '../../helpers/fake_hyperliquid_move_rail.dart';
import '../../helpers/fake_swap_orders.dart';

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

Future<void> _pumpSlip(WidgetTester tester,
    {required double venueUsd,
    required double dollarsUsd,
    required FakeHyperliquidMoveRail rail}) async {
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
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
          splashFactory: NoSplash.splashFactory,
          fontFamily: 'Inter',
          extensions: [AppColorsExtension.light()],
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

  testWidgets('Dollars short of the move: "Add X to Investments" opens the Dollar door',
      (tester) async {
    final doors = <(MoveLockedSide, double?)>[];
    final sheet = Completer<void>();
    debugShowHlDollarsDeposit = (side, target) {
      doors.add((side, target));
      return sheet.future;
    };
    await _pumpSlip(tester, venueUsd: 0, dollarsUsd: 5, rail: rail);
    await _typeOnKeypad(tester, '20');
    final button = _button(tester);
    expect(button.text, startsWith('Add \$'));
    expect(button.text, endsWith('to Investments'));
    expect(button.onPressed, isNotNull);
    // $21.27 has to leave Dollars; $5 are there.
    expect(button.text, 'Add \$16.27 to Investments');
    expect(_moveFeeRow(tester).usd, closeTo(1.03, 0.011));

    await tester.tap(find.byType(AppButton));
    await _frames(tester, 3);
    expect(doors, [(MoveLockedSide.depositToUsd, 16.27)]);
    expect(events.where((e) => e.$1 == 'slip_top_up_opened').length, 1);
    expect(events.singleWhere((e) => e.$1 == 'slip_top_up_opened').$2!['suggested_source'],
        'dollars');
    // Repeat taps while the door is open open nothing more.
    expect(_button(tester).onPressed, isNull);
    await tester.tap(find.byType(AppButton), warnIfMissed: false);
    await _frames(tester, 3);
    expect(doors, hasLength(1));
    sheet.complete();
    await _frames(tester, 3);
    expect(_button(tester).onPressed, isNotNull);
    expect(_button(tester).text, 'Add \$16.27 to Investments');
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
}
