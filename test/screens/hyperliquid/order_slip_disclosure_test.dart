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
import 'package:kute/screens/hyperliquid/components/order_slip_sheet.dart';
import 'package:kute/screens/shared/amount_keypad_panel.dart';
import 'package:kute/screens/shared/capability_block_note.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/services/hyperliquid/hypercore_cash.dart';
import 'package:kute/services/hyperliquid/hyperliquid_rounding.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart';

import '../../helpers/fake_swap_orders.dart';

class _LivePrices extends HlLivePricesNotifier {
  static int acquired = 0;
  static int released = 0;
  @override
  HlLivePriceState build() => const HlLivePriceState(mids: {'BTC': 60000});
  @override
  void acquire() => acquired++;
  @override
  void release() => released++;
  @override
  void watchCoins(List<String> coins, {Map<String, String>? wire}) {}

  void publishMid(double price) =>
      state = HlLivePriceState(mids: {'BTC': price});
}

/// The slip's fee summary shows fiat through [currencyProvider], whose real
/// notifier loads cached rates from Hive. Tests never open Hive.
class _Currency extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _Currency() : super(CurrencyState({'USD': Fixed.fromInt(1)}));
  @override
  Future<void> updateRates() async {}
}

/// Advanced order types are gated on the backend runtime policy and the
/// confirm stays disabled while it is unknown (c7096a09). These tests are
/// about the ticket, so the policy allows everything.
class _AllowedCapabilities extends Fake implements RuntimeCapabilitiesService {
  _AllowedCapabilities([this.blocked = const {}]);

  /// Capabilities an admin switched off for one test.
  final Set<String> blocked;
  static const blockedMessage = 'This feature is currently unavailable in Kute.';

  @override
  CapabilityDecision decision(String id) =>
      CapabilityDecision(allowed: !blocked.contains(id));
  @override
  String? blockReason(String id) =>
      blocked.contains(id) ? blockedMessage : null;
  @override
  Future<void> ensureAllAllowed(Iterable<String> ids,
      {Duration maxAge = Duration.zero}) async {
    for (final id in ids) {
      if (blocked.contains(id)) {
        throw CapabilityUnavailableException(id, decision(id));
      }
    }
  }

  @override
  int? get maxLeverage => null;
  @override
  int offeredLeverage(int venueMax) => venueMax;
}

/// The confirm's own gate check (RuntimeCapabilitiesService.instance):
/// records that the order reached it, then stops it there as a region
/// block would, before anything is signed or sent.
class _StopAtConfirm extends _AllowedCapabilities {
  int checks = 0;
  @override
  Future<void> ensureAllAllowed(Iterable<String> ids,
      {Duration maxAge = Duration.zero}) async {
    checks++;
    throw CapabilityUnavailableException(
        ids.first, const CapabilityDecision(allowed: false));
  }
}

final _availableFunds = StateProvider<double>((_) => 500);

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
    {double available = 500,
    bool isLong = true,
    double width = 390,
    double height = 844,
    Set<String> blocked = const {},
    HlMarket market = _market,
    List<HlPerpPosition>? positions,
    FakeSwapOrders? swaps}) async {
  tester.view.physicalSize = Size(width, height);
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
      _availableFunds.overrideWith((_) => available),
      hyperliquidWithdrawableProvider
          .overrideWith((ref) => ref.watch(_availableFunds)),
      hyperliquidSpotBalancesProvider.overrideWith((_) => []),
      swapOrdersProvider.overrideWith((_) => swaps ?? FakeSwapOrders()),
      hyperliquidAddressProvider.overrideWith((_) async => null),
      hyperliquidOrderbookProvider
          .overrideWith((_, __) => Stream.value(const HlOrderBookState())),
      aiEnabledProvider.overrideWith((_) async => false),
      currencyProvider.overrideWith((_) => _Currency()),
      runtimeCapabilitiesProvider
          .overrideWithValue(_AllowedCapabilities(blocked)),
      if (positions != null)
        hyperliquidPerpPositionsProvider.overrideWith((_) => positions),
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
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: HlOrderSlipSheet(market: market, initialIsLong: isLong),
          ),
        ),
      ),
    ),
  ));
  await _settle(tester);
}

/// Settles everything but the "Deposit incoming" working sign, which spins
/// for as long as a deposit is on its way (pumpAndSettle would never end).
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Types [amount] on the plain ticket's keypad, one frame per key, after
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
  await _settle(tester);
}

/// Rare order types (Scale, Stop, Take, TWAP) sit behind More options on
/// the Advanced page's order type control.
Future<void> _pickMoreOption(WidgetTester tester, String type) async {
  await tester.ensureVisible(find.text('More options'));
  await tester.tap(find.text('More options'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(type).last);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    _LivePrices.acquired = 0;
    _LivePrices.released = 0;
  });

  testWidgets(
      'Back from full-screen advanced discards the limit and reduce-only '
      'draft and keeps side and amount', (tester) async {
    await _pumpSlip(tester);
    expect(find.text('Est. liquidation'), findsNothing);
    expect(find.text('Leverage').hitTestable(), findsOneWidget);
    expect(find.text('Size'), findsNothing);
    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    final advancedRoute =
        ModalRoute.of(tester.element(find.text('Long BTC · Advanced')))!;
    expect(advancedRoute, isA<PageRoute>());
    expect((advancedRoute as PageRoute).fullscreenDialog, isTrue);
    expect(_LivePrices.acquired, 1);
    expect(find.text('Advanced'), findsNothing);
    expect(find.text('Size'), findsOneWidget);
    await tester.ensureVisible(find.text('Limit'));
    await tester.tap(find.text('Limit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), '59000');
    await tester.ensureVisible(find.text('Expert settings'));
    await tester.tap(find.text('Expert settings'));
    await tester.pumpAndSettle();
    final reduceOnly = find.text('Reduce-only (never opens a new position)');
    await tester.ensureVisible(reduceOnly);
    await tester.tap(reduceOnly);
    await tester.pumpAndSettle();
    expect(tester.widget<AppButton>(find.byType(AppButton)).text,
        'Place Long BTC limit');
    await tester.tap(find.byType(KuteBackButton));
    await tester.pumpAndSettle();

    // The plain ticket is always a plain market order (5c4c007c): the
    // limit price and reduce-only set on Advanced are gone, the side and
    // the amount stay.
    expect(find.textContaining('Limit order'), findsNothing);
    expect(tester.widget<AppButton>(find.byType(AppButton)).text,
        r'Go Long BTC 1x · $10.26');
    expect(find.text('Size'), findsNothing);
    expect(find.text('Est. liquidation'), findsNothing);
    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    expect(find.text('Limit price'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Reduce-only (never opens a new position)'), findsNothing);
    expect(_LivePrices.acquired, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(_LivePrices.released, 1);
  });

  group('a deposit into Investing on its way', () {
    testWidgets('says Deposit incoming instead of a second deposit',
        (tester) async {
      await _pumpSlip(tester,
          available: 0,
          swaps: FakeSwapOrders([
            poolDepositRow(id: 'ord_1', network: 'HYPERCORE', usd: 25),
          ]));
      final button = tester.widget<AppButton>(find.byType(AppButton));
      expect(button.text, r'Deposit incoming · $25.00');
      expect(button.onPressed, isNull);
      expect(
          find.text(
              'Your money is on its way. This button unlocks when it lands.'),
          findsOneWidget);
      // The small working sign beside that line.
      expect(find.byKey(const ValueKey('slip-deposit-incoming-working')),
          findsOneWidget);
      expect(find.text('Add more'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a smaller deposit on its way offers Add more',
        (tester) async {
      await _pumpSlip(tester,
          available: 0,
          swaps: FakeSwapOrders([
            poolDepositRow(id: 'ord_1', network: 'HYPERCORE', usd: 2),
          ]));
      expect(tester.widget<AppButton>(find.byType(AppButton)).text,
          r'Deposit incoming · $2.00');
      // Nothing typed asks for nothing more; an order the deposit falls
      // short of does.
      expect(find.byKey(const ValueKey('slip-deposit-add-more')),
          findsNothing);
      await _typeOnKeypad(tester, '20');
      expect(find.byKey(const ValueKey('slip-deposit-add-more')),
          findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a deposit into Predictions is not this slip\'s',
        (tester) async {
      await _pumpSlip(tester,
          available: 0,
          swaps: FakeSwapOrders([
            poolDepositRow(id: 'ord_1', network: 'POLYGON', usd: 25),
          ]));
      expect(tester.widget<AppButton>(find.byType(AppButton)).text,
          'Deposit to invest');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('failed: the deposit button comes back with a note',
        (tester) async {
      final swaps = FakeSwapOrders([
        poolDepositRow(id: 'ord_1', network: 'HYPERCORE', usd: 25),
      ]);
      await _pumpSlip(tester, available: 0, swaps: swaps);
      swaps.set([
        poolDepositRow(
            id: 'ord_1', network: 'HYPERCORE', usd: 25, status: 'refunded'),
      ]);
      await _settle(tester);
      final button = tester.widget<AppButton>(find.byType(AppButton));
      expect(button.text, 'Deposit to invest');
      expect(button.onPressed, isNotNull);
      expect(find.text("Your deposit didn't go through. You can deposit again."),
          findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('Max beside the amount, available and minimum under it', () {
    String typed(WidgetTester tester) =>
        tester.widget<BigAmountDisplay>(find.byType(BigAmountDisplay)).amountText;

    Future<void> typeOnKeypad(WidgetTester tester, String amount) async {
      final pad = find.byType(AmountKeypad);
      final backspace = find.descendant(
          of: pad, matching: find.byIcon(Icons.backspace_rounded));
      for (var i = 0; i < 8; i++) {
        await tester.tap(backspace);
        await tester.pump();
      }
      for (final key in amount.split('')) {
        await tester.tap(find.descendant(of: pad, matching: find.text(key)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    Finder infoLine() => find.descendant(
        of: find.byType(BigAmountDisplay),
        matching: find.textContaining('Minimum '));

    TextSpan minimumSpan(WidgetTester tester) =>
        (tester.widget<Text>(infoLine()).textSpan! as TextSpan)
            .children!
            .cast<TextSpan>()
            .singleWhere((s) => s.text!.startsWith('Minimum '));

    Color errorInk(WidgetTester tester) => Theme.of(
            tester.element(find.byType(BigAmountDisplay)))
        .extension<AppColorsExtension>()!
        .error;

    testWidgets('one small Max beside the figure fills the funded maximum',
        (tester) async {
      await _pumpSlip(tester);
      // No Min, no full-width chip row: one Max, on the figure's row.
      expect(find.byType(AmountQuickChips), findsNothing);
      expect(find.text('Min'), findsNothing);
      final max = find.descendant(
          of: find.byType(BigAmountDisplay),
          matching: find.byType(AmountMaxChip));
      expect(max, findsOneWidget);
      final chip = tester.getRect(max);
      final figure = tester.getRect(find.descendant(
          of: find.byType(BigAmountDisplay), matching: find.byType(FittedBox)));
      expect(chip.center.dy, closeTo(figure.center.dy, 1));
      expect(chip.left, greaterThanOrEqualTo(figure.right));
      expect(chip.height, lessThan(figure.height));
      expect(chip.width, lessThan(390 / 4));

      // One quiet line under it: the balance, then the minimum.
      final line = tester.widget<Text>(infoLine()).textSpan!.toPlainText();
      expect(line, matches(RegExp(r'^Available \$500\.00 · Minimum \$\d+\.\d{2}$')));
      expect(find.textContaining(r'$500.00'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Use maximum'));
      await tester.pumpAndSettle();
      // Fees and the 1% market slippage reserved out of the same cash.
      expect(typed(tester),
          hypercoreMaxOrderUsd(availableUsd: 500).toStringAsFixed(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        'below the minimum turns the minimum red, says nothing else and '
        'keeps the order shut', (tester) async {
      await _pumpSlip(tester);
      expect(minimumSpan(tester).style?.color, isNot(errorInk(tester)));

      await typeOnKeypad(tester, '1');
      expect(minimumSpan(tester).style?.color, errorInk(tester));
      // No second minimum message above the keypad; the button names
      // the same figure the line does, and does something.
      expect(find.textContaining('Minimum is'), findsNothing);
      final minimum = minimumSpan(tester).text!;
      final button = tester.widget<AppButton>(find.byType(AppButton));
      expect(button.text, minimum);
      expect(button.onPressed, isNotNull);

      await typeOnKeypad(tester, '50');
      expect(minimumSpan(tester).style?.color, isNot(errorInk(tester)));
      expect(tester.widget<AppButton>(find.byType(AppButton)).onPressed,
          isNotNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('under the minimum the button fills it, tracked as min',
        (tester) async {
      final events = <(String, Map<String, Object?>?)>[];
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
      addTearDown(() => TrackingService.debugTrackObserver = null);
      await _pumpSlip(tester);
      await typeOnKeypad(tester, '1');
      final minimum = minimumSpan(tester).text!;
      expect(tester.widget<AppButton>(find.byType(AppButton)).text, minimum);
      await tester.tap(find.byType(AppButton));
      await tester.pumpAndSettle();
      expect('Minimum \$${typed(tester)}', minimum);
      expect(minimumSpan(tester).style?.color, isNot(errorInk(tester)));
      final button = tester.widget<AppButton>(find.byType(AppButton));
      expect(button.text, startsWith('Go Long BTC'));
      expect(button.onPressed, isNotNull);
      await tester.pumpWidget(const SizedBox.shrink());
      final abandoned =
          events.lastWhere((e) => e.$1 == 'hyperliquid_order_slip_abandoned');
      expect(abandoned.$2?['amount_method'], 'min');
    });

    testWidgets('a zero amount is the order at the minimum again',
        (tester) async {
      await _pumpSlip(tester);
      final minimum = minimumSpan(tester).text!.replaceFirst('Minimum ', '');
      await typeOnKeypad(tester, '0');
      final button = tester.widget<AppButton>(find.byType(AppButton));
      expect(button.text, 'Go Long BTC 1x · $minimum');
      expect(button.onPressed, isNotNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    // A coin near two dollars traded in whole units. A 1x short used to
    // open on 10.08, whose order at the 1% slippage price was 9.98, and
    // the venue refused it.
    const coarse = HlMarket(
      coin: 'SPCX',
      wireCoin: 'SPCX',
      assetId: 7,
      kind: HlMarketKind.perp,
      szDecimals: 0,
      maxLeverage: 10,
      onlyIsolated: false,
      markPx: 2.016,
      midPx: 2.016,
      prevDayPx: 2.016,
      dayNtlVlm: 0,
    );
    for (final isLong in [false, true]) {
      testWidgets(
          '${isLong ? 'a long' : 'a short'} offers a minimum the venue '
          'accepts as sent', (tester) async {
        await _pumpSlip(tester, market: coarse, isLong: isLong);
        expect(typed(tester), '');
        final figure =
            minimumSpan(tester).text!.replaceFirst(r'Minimum $', '');
        final amount = double.parse(figure);
        final size = sizeFromUsd(usd: amount, px: 2.016, szDecimals: 0);
        final wire = double.parse(slippagePrice(
            referencePx: 2.016,
            isBuy: isLong,
            slippage: 0.01,
            szDecimals: 0,
            isSpot: false));
        expect(size * wire, greaterThanOrEqualTo(10));
        final button = tester.widget<AppButton>(find.byType(AppButton));
        expect(button.text,
            'Go ${isLong ? 'Long' : 'Short'} SPCX 1x · \$$figure');
        expect(button.onPressed, isNotNull);
        // The old figure is now under the minimum: the button offers it.
        await typeOnKeypad(tester, '10.08');
        expect(tester.widget<AppButton>(find.byType(AppButton)).text,
            minimumSpan(tester).text);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }

    testWidgets('an empty account has no Max, only the deposit door',
        (tester) async {
      await _pumpSlip(tester, available: 0);
      expect(find.byType(AmountMaxChip), findsNothing);
      expect(tester.widget<AppButton>(find.byType(AppButton)).text,
          'Deposit to invest');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  testWidgets('empty account can deposit with a blank amount', (tester) async {
    await _pumpSlip(tester, available: 0);
    // The plain ticket types on its own keypad (9a81c35d); clear it.
    final backspace = find.descendant(
        of: find.byType(AmountKeypad),
        matching: find.byIcon(Icons.backspace_rounded));
    for (var i = 0; i < 8; i++) {
      await tester.tap(backspace);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    final button = tester.widget<AppButton>(find.byType(AppButton));
    expect(button.text, 'Deposit to invest');
    expect(button.onPressed, isNotNull);
    expect(find.text('Add funds to continue'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final available in [0.0, 5.0]) {
    testWidgets(
        'insufficient balance \$available with hyperliquid.deposit withheld: '
        'the door is disabled and says why', (tester) async {
      await _pumpSlip(tester,
          available: available, blocked: {'hyperliquid.deposit'});
      if (available > 0) await _typeOnKeypad(tester, '20');
      final button = tester.widget<AppButton>(find.byType(AppButton));
      expect(button.text, 'Deposit to invest');
      expect(button.onPressed, isNull);
      expect(find.text(_AllowedCapabilities.blockedMessage), findsOneWidget);
      // A tap on the shut door opens nothing.
      await tester.tap(find.byType(AppButton));
      await tester.pumpAndSettle();
      expect(find.byType(HlOrderSlipSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('a funded order is untouched by the deposit switch',
      (tester) async {
    await _pumpSlip(tester, blocked: {'hyperliquid.deposit'});
    final button = tester.widget<AppButton>(find.byType(AppButton));
    expect(button.text, r'Go Long BTC 1x · $10.26');
    expect(button.onPressed, isNotNull);
    expect(find.text(_AllowedCapabilities.blockedMessage), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'hyperliquid.trade withheld: the ticket opens, the confirm is '
      'disabled and the reason sits above it', (tester) async {
    await _pumpSlip(tester, blocked: {'hyperliquid.trade'});
    // The market and the ticket stay readable.
    expect(find.text('Leverage').hitTestable(), findsOneWidget);
    final button = tester.widget<AppButton>(find.byType(AppButton));
    expect(button.text, r'Go Long BTC 1x · $10.26');
    expect(button.onPressed, isNull);
    final note = find.byType(CapabilityBlockNote);
    expect(note, findsOneWidget);
    expect(
        find.descendant(
            of: note, matching: find.text(_AllowedCapabilities.blockedMessage)),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'trade and deposit both withheld: the deposit door shuts too and the '
      'reason is said once', (tester) async {
    await _pumpSlip(tester,
        available: 0, blocked: {'hyperliquid.trade', 'hyperliquid.deposit'});
    final button = tester.widget<AppButton>(find.byType(AppButton));
    expect(button.text, 'Deposit to invest');
    expect(button.onPressed, isNull);
    expect(find.byType(CapabilityBlockNote), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('advanced keeps the short direction explicit for TWAP',
      (tester) async {
    await _pumpSlip(tester, isLong: false);
    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    expect(find.text('Short BTC · Advanced'), findsOneWidget);
    await _pickMoreOption(tester, 'TWAP');
    expect(find.text('Short BTC · Advanced').hitTestable(), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Short BTC'), findsOneWidget);
    expect(tester.widget<AppButton>(find.byType(AppButton)).text,
        r'Go Short BTC 1x · $10.26');
    // Even at 1x a short can be liquidated, and the plain ticket shows
    // that estimate up front (e3ea3faa).
    await _typeOnKeypad(tester, '20');
    expect(find.text('Est. liquidation'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('empty TWAP account offers funding before completing the order',
      (tester) async {
    await _pumpSlip(tester, available: 0);
    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    await _pickMoreOption(tester, 'TWAP');
    await tester.enterText(find.byType(TextField).first, '');
    await tester.enterText(find.byType(TextField).at(1), '2');
    await tester.pumpAndSettle();

    final button = tester.widget<AppButton>(find.byType(AppButton));
    expect(button.text, 'Deposit to invest');
    expect(button.onPressed, isNotNull);
    expect(find.text('Duration must be between 5 minutes and 7 days.'),
        findsOneWidget);

    // Back returns a plain market order (5c4c007c); still the deposit
    // door, since the account is empty.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.textContaining('TWAP'), findsNothing);
    expect(tester.widget<AppButton>(find.byType(AppButton)).text,
        'Deposit to invest');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'TWAP funding preserves duration and validation for funded orders',
      (tester) async {
    await _pumpSlip(tester);
    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    await _pickMoreOption(tester, 'TWAP');
    await tester.enterText(find.byType(TextField).first, '600');
    await tester.enterText(find.byType(TextField).at(1), '2');
    await tester.pumpAndSettle();

    var button = tester.widget<AppButton>(find.byType(AppButton));
    expect(button.text, 'Deposit to invest');
    expect(button.onPressed, isNotNull);

    await tester.enterText(find.byType(TextField).first, '100');
    await tester.pumpAndSettle();
    button = tester.widget<AppButton>(find.byType(AppButton));
    expect(button.text, 'Start TWAP · 2m');
    expect(button.onPressed, isNull);

    await tester.enterText(find.byType(TextField).at(1), '30');
    await tester.pumpAndSettle();
    button = tester.widget<AppButton>(find.byType(AppButton));
    expect(button.text, 'Start TWAP · 30m');
    expect(button.onPressed, isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('advanced stays live without creating a second price feed',
      (tester) async {
    await _pumpSlip(tester);
    final container = ProviderScope.containerOf(
        tester.element(find.byType(HlOrderSlipSheet)));
    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    final prices =
        container.read(hyperliquidLivePricesProvider.notifier) as _LivePrices;
    prices.publishMid(61000);
    await tester.pumpAndSettle();
    expect(find.text(r'$61,000'), findsOneWidget); // 5 sig figs since d62340f3

    container.read(_availableFunds.notifier).state = 0;
    await tester.pumpAndSettle();
    var button = tester.widget<AppButton>(find.byType(AppButton));
    expect(button.text, 'Deposit to invest');
    expect(button.onPressed, isNotNull);
    expect(_LivePrices.acquired, 1);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    button = tester.widget<AppButton>(find.byType(AppButton));
    expect(button.text, 'Deposit to invest');
    expect(find.text('Est. liquidation'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(_LivePrices.released, 1);
  });
  for (final keyboard in [0.0, 300.0]) {
    testWidgets(
        'advanced funding action stays pinned under long content with keyboard $keyboard',
        (tester) async {
      await _pumpSlip(tester, available: 0, width: 320, height: 700);
      await tester.ensureVisible(find.text('Advanced'));
      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      final scroll = find.byKey(const ValueKey('hl-advanced-form-scroll'));
      final action = find.text('Deposit to invest');
      final position = tester
          .state<ScrollableState>(find
              .descendant(of: scroll, matching: find.byType(Scrollable))
              .first)
          .position;
      // The long form scrolls; the action is pinned as a bottom bar
      // outside it (3d8c274c), reachable without scrolling and never
      // covered by the form.
      expect(position.maxScrollExtent, greaterThan(0));
      expect(find.ancestor(of: action, matching: scroll), findsNothing);
      expect(position.pixels, 0);
      expect(action.hitTestable(), findsOneWidget);
      expect(tester.getRect(action).bottom, lessThanOrEqualTo(700 - keyboard));
      expect(tester.getRect(scroll).bottom,
          lessThanOrEqualTo(tester.getRect(action).top));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('advanced funding action rests at bottom when content fits',
      (tester) async {
    // Advanced grew titled sections (c5a9ad1c, 8a4803b1); 1600 no longer
    // holds the whole form, so the page is made tall enough that it does.
    const height = 3600.0;
    await _pumpSlip(tester, available: 0, height: height);
    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    final scroll = find.byKey(const ValueKey('hl-advanced-form-scroll'));
    final position = tester
        .state<ScrollableState>(find
            .descendant(of: scroll, matching: find.byType(Scrollable))
            .first)
        .position;
    expect(position.maxScrollExtent, 0);
    final action = find.byType(AppButton);
    expect(
        tester.getRect(action).bottom, closeTo(height - 16 * height / 932, 1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'trading.advanced withheld: Advanced stays, a tap opens the sheet only',
      (tester) async {
    await _pumpSlip(tester, blocked: {'trading.advanced'});
    expect(find.text('Advanced'), findsOneWidget);
    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('capability-unavailable-got-it')),
        findsOneWidget);
    expect(find.text('Long BTC · Advanced'), findsNothing);
    await tester
        .tap(find.byKey(const ValueKey('capability-unavailable-got-it')));
    await tester.pumpAndSettle();
    expect(find.text('Long BTC · Advanced'), findsNothing);
    expect(find.text('Advanced'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('against a position already held (one net position per market)',
      () {
    HlPerpPosition held(double szi) => HlPerpPosition(
          coin: 'BTC',
          szi: szi,
          entryPx: 60000,
          positionValue: szi.abs() * 60000,
          unrealizedPnl: 0,
          returnOnEquity: 0,
          liquidationPx: null,
          marginUsed: szi.abs() * 60000,
          leverageType: 'isolated',
          leverageValue: 1,
          maxLeverage: 40,
        );

    Future<void> typeOnKeypad(WidgetTester tester, String amount) async {
      final pad = find.byType(AmountKeypad);
      final backspace = find.descendant(
          of: pad, matching: find.byIcon(Icons.backspace_rounded));
      for (var i = 0; i < 8; i++) {
        await tester.tap(backspace);
        await tester.pump();
      }
      for (final key in amount.split('')) {
        await tester.tap(find.descendant(of: pad, matching: find.text(key)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    AppButton button(WidgetTester tester) =>
        tester.widget<AppButton>(find.byType(AppButton));
    String? note(WidgetTester tester) =>
        tester.widget<BigAmountDisplay>(find.byType(BigAmountDisplay)).noteLabel;
    String? minimum(WidgetTester tester) => tester
        .widget<BigAmountDisplay>(find.byType(BigAmountDisplay))
        .minimumLabel;

    testWidgets('no position: the plain order, no line', (tester) async {
      await _pumpSlip(tester, positions: const []);
      expect(button(tester).text, startsWith('Go Long BTC 1x'));
      expect(note(tester), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    for (final long in [true, false]) {
      final side = long ? 'long' : 'short';
      final other = long ? 'short' : 'long';
      final szi = long ? 0.01 : -0.01;

      testWidgets('same side adds to the $side', (tester) async {
        await _pumpSlip(tester, isLong: long, positions: [held(szi)]);
        await typeOnKeypad(tester, '50');
        expect(button(tester).text, 'Add to $side · \$50.00');
        expect(note(tester),
            'You hold a $side of 0.01 BTC — this adds to it');
        expect(button(tester).onPressed, isNotNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });

      testWidgets('a smaller opposite order reduces the $side, under \$10 too',
          (tester) async {
        await _pumpSlip(tester, isLong: !long, positions: [held(szi)]);
        await typeOnKeypad(tester, '300');
        expect(button(tester).text, 'Reduce $side · \$300.00');
        expect(note(tester),
            'You hold a $side of 0.01 BTC — this reduces it to 0.005 BTC');
        // No venue minimum on an exit.
        expect(minimum(tester), isNull);
        await typeOnKeypad(tester, '3');
        expect(button(tester).text, 'Reduce $side · \$3.00');
        expect(button(tester).onPressed, isNotNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });

      testWidgets('an equal opposite order closes the $side', (tester) async {
        // A sliver of balance: closing needs no margin, so no deposit door.
        await _pumpSlip(tester,
            isLong: !long, available: 5, positions: [held(szi)]);
        await typeOnKeypad(tester, '600');
        expect(button(tester).text, 'Close $side');
        expect(note(tester), 'You hold a $side of 0.01 BTC — this closes it');
        expect(button(tester).onPressed, isNotNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });

      testWidgets('a larger opposite order flips to $other', (tester) async {
        await _pumpSlip(tester, isLong: !long, positions: [held(szi)]);
        await typeOnKeypad(tester, '660');
        expect(button(tester).text, 'Flip to $other · \$660.00');
        expect(
            note(tester),
            'You hold a $side of 0.01 BTC — this closes it and opens a '
            '$other of 0.001 BTC');
        expect(button(tester).onPressed, isNotNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });

      testWidgets('a flip whose new $other is under the minimum offers it',
          (tester) async {
        await _pumpSlip(tester, isLong: !long, positions: [held(szi)]);
        await typeOnKeypad(tester, '605');
        // 0.00008 BTC past the position is about \$5: under the minimum.
        final min = minimum(tester)!;
        expect(button(tester).text, min);
        final amount = double.parse(min.replaceFirst(r'Minimum $', ''));
        expect(amount, greaterThan(610));
        await tester.tap(find.byType(AppButton));
        await tester.pumpAndSettle();
        expect(button(tester).text, startsWith('Flip to $other'));
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  });

  group('an empty ticket', () {
    // The ticket's own button (a sheet over it may carry another).
    AppButton button(WidgetTester tester) => tester.widget<AppButton>(
        find.descendant(
            of: find.byType(HlOrderSlipSheet),
            matching: find.byType(AppButton)));
    String typed(WidgetTester tester) => tester
        .widget<BigAmountDisplay>(find.byType(BigAmountDisplay))
        .amountText;
    String minimum(WidgetTester tester) => tester
        .widget<BigAmountDisplay>(find.byType(BigAmountDisplay))
        .minimumLabel!
        .replaceFirst(r'Minimum $', '');

    testWidgets('opens at zero and types from there, nothing to delete',
        (tester) async {
      await _pumpSlip(tester);
      expect(typed(tester), '');
      expect(find.text(r'$0'), findsOneWidget);
      final pad = find.byType(AmountKeypad);
      for (final key in ['2', '5']) {
        await tester.tap(find.descendant(of: pad, matching: find.text(key)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(typed(tester), '25');
      expect(button(tester).text, r'Go Long BTC 1x · $25.00');
      expect(button(tester).onPressed, isNotNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the button names the minimum and a tap places exactly it',
        (tester) async {
      final events = <(String, Map<String, Object?>?)>[];
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
      addTearDown(() => TrackingService.debugTrackObserver = null);
      final gate = _StopAtConfirm();
      RuntimeCapabilitiesService.debugInstance = gate;
      addTearDown(() => RuntimeCapabilitiesService.debugInstance = null);
      await _pumpSlip(tester);
      final min = minimum(tester);
      expect(min, '10.26');
      expect(button(tester).text, 'Go Long BTC 1x · \$$min');
      expect(button(tester).onPressed, isNotNull);
      await tester.tap(find.byType(AppButton));
      await tester.pumpAndSettle();
      // The minimum went into the figure and on into the normal confirm,
      // whose gate stopped it with its sheet.
      expect(typed(tester), min);
      expect(gate.checks, 1);
      expect(find.text('Investing unavailable'), findsOneWidget);
      expect(button(tester).text, 'Go Long BTC 1x · \$$min');
      await tester.pumpWidget(const SizedBox.shrink());
      final abandoned =
          events.lastWhere((e) => e.$1 == 'hyperliquid_order_slip_abandoned');
      expect(abandoned.$2?['amount_method'], 'min_direct');
    });

    testWidgets('typing turns the button into the typed order and its checks',
        (tester) async {
      await _pumpSlip(tester);
      final min = minimum(tester);
      await _typeOnKeypad(tester, '1');
      expect(button(tester).text, 'Minimum \$$min');
      await _typeOnKeypad(tester, '20');
      expect(button(tester).text, r'Go Long BTC 1x · $20.00');
      expect(button(tester).onPressed, isNotNull);
      await _typeOnKeypad(tester, '600');
      expect(button(tester).text, 'Deposit to invest');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        'less available than the minimum: a tap writes it and the button '
        'is the deposit door', (tester) async {
      await _pumpSlip(tester, available: 5, blocked: {'hyperliquid.deposit'});
      final min = minimum(tester);
      expect(button(tester).text, 'Go Long BTC 1x · \$$min');
      await tester.tap(find.byType(AppButton));
      await tester.pumpAndSettle();
      expect(typed(tester), min);
      expect(button(tester).text, 'Deposit to invest');
      // The door is shut here, so nothing opened over the ticket.
      expect(find.byType(HlOrderSlipSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
