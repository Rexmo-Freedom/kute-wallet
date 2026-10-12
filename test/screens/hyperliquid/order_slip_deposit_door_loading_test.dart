// The order slip's one button while it cannot know yet what it should be:
// the Investing account not read yet ("Loading your account..."); and, once
// read empty with no Dollars to fund the order, the Dollar deposit door
// ("Add $X to Investments"), one sheet at a time.
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
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart';

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

/// The Investing account, answered when the test says so.
class _Account extends HlAccountNotifier {
  _Account(this.answer);
  final Future<HlAccountSnapshot> answer;
  @override
  Future<HlAccountSnapshot> build() => answer;
}

HlAccountSnapshot _snapshot(double withdrawable) => HlAccountSnapshot(
      accountValue: withdrawable,
      withdrawable: withdrawable,
      totalMarginUsed: 0,
      positions: const [],
      spotBalances: const [],
    );

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

Future<void> _pumpSlip(
    WidgetTester tester, Future<HlAccountSnapshot> account) async {
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
      hyperliquidAccountProvider.overrideWith(() => _Account(account)),
      swapOrdersProvider.overrideWith((_) => FakeSwapOrders()),
      hyperliquidAddressProvider.overrideWith((_) async => null),
      hyperliquidOrderbookProvider
          .overrideWith((_, __) => Stream.value(const HlOrderBookState())),
      aiEnabledProvider.overrideWith((_) async => false),
      currencyProvider.overrideWith((_) => _Currency()),
      runtimeCapabilitiesProvider.overrideWithValue(_Allowed()),
      usdBalanceProvider.overrideWith((_) => 0),
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

/// Types [amount] on the ticket's keypad, one frame per key, after
/// clearing whatever the figure holds.
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

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('before the Investing account is read', () {
    testWidgets('waits, disabled, and never shows the Deposit door',
        (tester) async {
      final account = Completer<HlAccountSnapshot>();
      await _pumpSlip(tester, account.future);
      expect(_button(tester).isLoading, isTrue);
      expect(_button(tester).onPressed, isNull);
      expect(_button(tester).loadingLabel, 'Loading your account...');
      expect(find.text('Loading your account...'), findsOneWidget);
      expect(find.text('Deposit to invest'), findsNothing);

      // The account arrives with money: the trade, never the door.
      account.complete(_snapshot(500));
      await _frames(tester);
      expect(_button(tester).isLoading, isFalse);
      expect(_button(tester).text, startsWith('Go Long BTC'));
      expect(_button(tester).onPressed, isNotNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('an empty account, once read, is the Dollar deposit door',
        (tester) async {
      final account = Completer<HlAccountSnapshot>();
      await _pumpSlip(tester, account.future);
      expect(find.textContaining('to Investments'), findsNothing);
      account.complete(_snapshot(0));
      await _frames(tester);
      expect(_button(tester).text, startsWith('Add \$'));
      expect(_button(tester).text, endsWith('to Investments'));
      expect(_button(tester).isLoading, isFalse);
      expect(_button(tester).onPressed, isNotNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('the Dollar deposit door', () {
    late List<String> events;
    late List<(MoveLockedSide, double?)> sheets;
    late Completer<void> sheet;

    setUp(() {
      events = [];
      TrackingService.debugTrackObserver = (e, _) => events.add(e);
      sheets = [];
      debugShowHlDollarsDeposit = (side, target) {
        sheets.add((side, target));
        return sheet.future;
      };
    });

    tearDown(() {
      debugShowHlDollarsDeposit = null;
      TrackingService.debugTrackObserver = null;
    });

    testWidgets(
        'opens once, locked to Dollars with what the order lacks, and ignores repeat taps',
        (tester) async {
      sheet = Completer<void>();
      await _pumpSlip(tester, Future.value(_snapshot(0)));
      await _typeOnKeypad(tester, '20');
      expect(_button(tester).text, startsWith('Add \$'));

      await tester.tap(find.byType(AppButton));
      await _frames(tester, 3);
      expect(sheets, hasLength(1));
      expect(sheets.single.$1, MoveLockedSide.depositToUsd);
      // The $20 order needs $20.24 at the venue, grossed up for the route.
      expect(sheets.single.$2, greaterThanOrEqualTo(20.24));
      expect(events.where((e) => e == 'hl_order_step').length, 1);
      expect(events.where((e) => e == 'slip_top_up_opened').length, 1);
      // The sheet is open: shut, not calculating.
      expect(_button(tester).isLoading, isFalse);
      expect(_button(tester).onPressed, isNull);

      // Repeat taps while it is open: nothing more opens.
      await tester.tap(find.byType(AppButton), warnIfMissed: false);
      await _frames(tester, 3);
      expect(sheets, hasLength(1));

      // The sheet closes without a deposit: the door again, same prefill.
      sheet.complete();
      await _frames(tester, 3);
      expect(_button(tester).text, startsWith('Add \$'));
      expect(_button(tester).onPressed, isNotNull);
      sheet = Completer<void>()..complete();
      await tester.tap(find.byType(AppButton));
      await _frames(tester, 3);
      expect(sheets.map((s) => s.$2), [sheets.first.$2, sheets.first.$2]);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
