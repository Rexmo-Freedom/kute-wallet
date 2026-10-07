import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/ledger/ledger_pm_buying_power_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_open_orders_provider.dart';
import 'package:kute/providers/pending_polymarket_bet_provider.dart';
import 'package:kute/providers/polymarket_bet_controller.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/services/polymarket/placement_waits.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/services/polymarket/polymarket_fee_terms.dart';
import 'package:kute/screens/polymarket/components/bet_slip_sheet.dart';
import 'package:kute/screens/polymarket/components/slip_chrome.dart';
import 'package:kute/screens/shared/amount_keypad_panel.dart';
import 'package:kute/screens/shared/capability_block_note.dart';
import 'package:kute/screens/shared/polymarket_fee_summary.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart';

import '../../helpers/fake_swap_orders.dart';
import '../../helpers/runtime_policy_fixture.dart';

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

/// A first prediction whose one-time account setup does not finish:
/// [prepareIntent] (setup, then the price read) fails like the real one.
class _SetupController extends PolymarketBetController {
  _SetupController(super.ref, this.error);
  final Object error;
  var prepares = 0;
  @override
  Future<PendingBetIntent> prepareIntent(PendingBetIntent intent) async {
    prepares++;
    throw error;
  }
}

/// Records the stake each placement reaches the price read with, then
/// stops it there, before anything is approved or signed.
class _RecordingController extends PolymarketBetController {
  _RecordingController(super.ref);
  final amounts = <double>[];
  @override
  Future<PendingBetIntent> prepareIntent(PendingBetIntent intent) async {
    amounts.add(intent.amount);
    throw StateError('stopped by the test');
  }
}

class _Currency extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _Currency() : super(CurrencyState({'USD': Fixed.fromInt(100)}));
  @override
  Future<void> updateRates() async {}
}

Future<void> _pumpSlip(WidgetTester tester,
    {double balance = 100,
    double width = 390,
    double height = 844,
    double keyboard = 0,
    String question = 'Will it rain?',
    List<Order> orders = const [],
    List<PolymarketOutcome> outcomes = const [
      PolymarketOutcome(name: 'Yes', price: 0.5),
      PolymarketOutcome(name: 'No', price: 0.5),
    ],
    PolymarketFeeTerms? feeTerms,
    FakeSwapOrders? swaps,
    List<Override> extraOverrides = const [],
    String? sideLabelPos,
    String? sideLabelNeg,
    String fontFamily = 'Inter',
    // Most tests here are about a $10 bet, so they open with one carried
    // in; null opens empty like a plain tap does.
    double? initialAmountUsd = 10,
    String? ledgerWalletId,
    bool settle = true}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
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
      polymarketOpenOrdersProvider.overrideWith((ref) => Stream.value(orders)),
      aiEnabledProvider.overrideWith((ref) async => false),
      if (feeTerms != null) ...[
        polymarketFeeTermsProvider.overrideWith((ref, _) async => feeTerms),
        // A fee figure formats through the app's rates.
        currencyProvider.overrideWith((ref) => _Currency()),
      ],
      ...extraOverrides,
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
            splashFactory: NoSplash.splashFactory,
            fontFamily: fontFamily,
            extensions: [AppColorsExtension.light()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          resizeToAvoidBottomInset: false,
          body: Align(
            alignment: Alignment.bottomCenter,
            child: BetSlipSheet(
                marketQuestion: question,
                outcomes: outcomes,
                sideLabelPos: sideLabelPos,
                sideLabelNeg: sideLabelNeg,
                initialAmountUsd: initialAmountUsd,
                ledgerWalletId: ledgerWalletId),
          ),
        ),
      ),
    ),
  ));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // "Deposit incoming" spins until the money lands: pump, never settle.
    await tester.pump(const Duration(milliseconds: 500));
  }
}

/// The compact slip has no TextField: the amount is typed on its own
/// pinned keypad so the OS keyboard never covers the ticket. Clears the
/// figure with backspace, then types [amount] key by key.
Future<void> _typeOnKeypad(WidgetTester tester, String amount) async {
  final pad = find.byType(AmountKeypad);
  final backspace =
      find.descendant(of: pad, matching: find.byIcon(Icons.backspace_rounded));
  // One frame per key, as a finger would: the keypad edits the value it
  // was last built with.
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

/// Advanced opens only while `trading.advanced` is allowed, and with no
/// readable policy it is withheld. The tests that open it read a policy
/// that allows everything, released in the body (before the pending-timer
/// check) by [_release].
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

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('simple slip keeps selection, amount, payout and fees visible',
      (tester) async {
    await _pumpSlip(tester);
    expect(find.text('Payout if you win'), findsOneWidget);
    expect(find.text(r'Available $100.00 · Minimum $1.00'), findsOneWidget);
    expect(find.text('Limit'), findsNothing);
    expect(find.text('Estimated shares'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('NO'));
    await _typeOnKeypad(tester, '20');
    expect(find.text(r'$20'), findsOneWidget);
    expect(find.text(r'Place $20.00 on No'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Advanced opens a full page and Back keeps the side and amount',
      (tester) async {
    final policy = await _allowEverything();
    await _pumpSlip(tester);
    await tester.tap(find.text('NO'));
    await _typeOnKeypad(tester, '20');
    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    expect(find.text('Advanced prediction'), findsOneWidget);
    expect(tester.getSize(find.byType(Scaffold).last).height, 844);
    // The advanced field edits the same draft the keypad typed into.
    final advancedController =
        tester.widget<TextField>(find.byType(TextField)).controller;
    expect(advancedController!.text, '20');
    expect(find.text(r'Place $20.00 on No'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '35');
    await tester.ensureVisible(find.text('Limit'));
    await tester.tap(find.text('Limit'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byIcon(Icons.add_rounded));
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Until canceled'), findsOneWidget);
    expect(find.textContaining(r'Place $35.00 limit at'), findsOneWidget);
    await tester.tap(find.byType(KuteBackButton));
    await tester.pumpAndSettle();
    // Side and amount survive Back; the limit set on Advanced does not.
    // The plain slip is always a plain market prediction (5c4c007c).
    expect(find.text('Advanced prediction'), findsNothing);
    expect(find.text('Estimated shares'), findsNothing);
    expect(find.text(r'$35'), findsOneWidget);
    expect(advancedController.text, '35');
    expect(find.text(r'Place $35.00 on No'), findsOneWidget);
    expect(find.textContaining('limit at'), findsNothing);
    expect(find.textContaining('Limit · '), findsNothing);
    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    expect(find.text('Until canceled'), findsNothing);
    expect(find.text(r'Place $35.00 on No'), findsOneWidget);
    await tester.tap(find.byType(KuteBackButton));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await _release(tester, policy);
  });

  testWidgets('system Back from Advanced preserves side and edited amount',
      (tester) async {
    final policy = await _allowEverything();
    await _pumpSlip(tester);
    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('NO'));
    await tester.enterText(find.byType(TextField), '25');
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Advanced prediction'), findsNothing);
    expect(find.text(r'$25'), findsOneWidget);
    expect(find.text(r'Place $25.00 on No'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _release(tester, policy);
  });

  testWidgets('empty Predictions balance offers deposit directly',
      (tester) async {
    await _pumpSlip(tester, balance: 0);
    expect(find.text('Deposit to predict'), findsOneWidget);
    expect(find.text('Max'), findsNothing);
    expect(find.text('Enter an amount'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('a deposit into Predictions on its way', () {
    Finder incoming() => find.byKey(const ValueKey('bet-slip-deposit-incoming'));
    Finder door() => find.byKey(const ValueKey('bet-slip-deposit-door'));

    testWidgets('says Deposit incoming instead of offering a second deposit',
        (tester) async {
      final policy = await _allowEverything();
      final swaps = FakeSwapOrders([
        poolDepositRow(id: 'ord_1', network: 'POLYGON', usd: 20),
      ]);
      await _pumpSlip(tester, balance: 0, swaps: swaps, settle: false);
      expect(incoming(), findsOneWidget);
      expect(door(), findsNothing);
      final cta = tester.widget<PolySlipCta>(incoming());
      expect(cta.enabled, isFalse);
      expect(cta.label, r'Deposit incoming · $20.00');
      expect(find.text('Your money is on its way. This button unlocks when it lands.'),
          findsOneWidget);
      expect(find.text('Add more'), findsNothing);
      expect(tester.takeException(), isNull);
      await _release(tester, policy);
    });

    testWidgets('a deposit into Investing is not this slip\'s', (tester) async {
      final policy = await _allowEverything();
      final swaps = FakeSwapOrders([
        poolDepositRow(id: 'ord_1', network: 'HYPERCORE', usd: 20),
      ]);
      await _pumpSlip(tester, balance: 0, swaps: swaps);
      expect(incoming(), findsNothing);
      expect(door(), findsOneWidget);
      await _release(tester, policy);
    });

    testWidgets('a smaller deposit on its way offers Add more', (tester) async {
      final policy = await _allowEverything();
      final swaps = FakeSwapOrders([
        poolDepositRow(id: 'ord_1', network: 'POLYGON', usd: 2),
      ]);
      await _pumpSlip(tester, balance: 0, swaps: swaps, settle: false);
      expect(incoming(), findsOneWidget);
      expect(find.byKey(const ValueKey('slip-deposit-add-more')),
          findsOneWidget);
      await _release(tester, policy);
    });

    testWidgets('landed: stays incoming while the balance catches up',
        (tester) async {
      final policy = await _allowEverything();
      final swaps = FakeSwapOrders([
        poolDepositRow(id: 'ord_1', network: 'POLYGON', usd: 20),
      ]);
      await _pumpSlip(tester, balance: 0, swaps: swaps, settle: false);
      swaps.set([
        poolDepositRow(
            id: 'ord_1', network: 'POLYGON', usd: 20, status: 'success'),
      ]);
      await tester.pump(const Duration(milliseconds: 500));
      expect(incoming(), findsOneWidget);
      expect(door(), findsNothing);
      await _release(tester, policy);
    });

    testWidgets('failed: the deposit button comes back with a note',
        (tester) async {
      final policy = await _allowEverything();
      final swaps = FakeSwapOrders([
        poolDepositRow(id: 'ord_1', network: 'POLYGON', usd: 20),
      ]);
      await _pumpSlip(tester, balance: 0, swaps: swaps, settle: false);
      swaps.set([
        poolDepositRow(
            id: 'ord_1', network: 'POLYGON', usd: 20, status: 'refunded'),
      ]);
      await tester.pumpAndSettle();
      expect(incoming(), findsNothing);
      expect(door(), findsOneWidget);
      expect(find.text("Your deposit didn't go through. You can deposit again."),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      await _release(tester, policy);
    });
  });

  group('with polymarket.deposit withheld', () {
    // Mutable, so a refresh can flip the admin switch mid-test.
    final blocked = <String>{};
    late RuntimeCapabilitiesService policy;
    setUp(() {
      AffiliateService.debugSessionToken = 'test-session';
      blocked
        ..clear()
        ..add('polymarket.deposit');
      policy = runtimePolicyFixture(blocked: blocked);
      RuntimeCapabilitiesService.debugInstance = policy;
    });
    tearDown(() {
      RuntimeCapabilitiesService.debugInstance = null;
      AffiliateService.debugSessionToken = null;
    });

    PolySlipCta door(WidgetTester tester) => tester.widget<PolySlipCta>(
        find.byKey(const ValueKey('bet-slip-deposit-door')));

    testWidgets('insufficient balance: the door is disabled and says why',
        (tester) async {
      expect(await policy.refresh(), isTrue);
      // $5 cannot cover the $10 default stake.
      await _pumpSlip(tester, balance: 5);
      expect(door(tester).label, 'Deposit to predict');
      expect(door(tester).enabled, isFalse);
      expect(find.text('This feature is currently unavailable in Kute.'),
          findsOneWidget);
      // A tap on the shut door opens nothing and places nothing.
      await tester.tap(find.byKey(const ValueKey('bet-slip-deposit-door')));
      await tester.pumpAndSettle();
      expect(find.byType(BetSlipSheet), findsOneWidget);
      expect(door(tester).enabled, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      policy.dispose();
    });

    testWidgets('the door follows the admin switch live', (tester) async {
      expect(await policy.refresh(), isTrue);
      await _pumpSlip(tester, balance: 0);
      expect(door(tester).enabled, isFalse);
      blocked.clear();
      expect(await policy.refresh(), isTrue);
      await tester.pumpAndSettle();
      expect(door(tester).enabled, isTrue);
      expect(find.text('This feature is currently unavailable in Kute.'),
          findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      policy.dispose();
    });

    testWidgets('a funded bet is untouched by the deposit switch',
        (tester) async {
      expect(await policy.refresh(), isTrue);
      await _pumpSlip(tester);
      expect(find.byKey(const ValueKey('bet-slip-deposit-door')), findsNothing);
      expect(find.text(r'Place $10.00 on Yes'), findsOneWidget);
      expect(find.text('This feature is currently unavailable in Kute.'),
          findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      policy.dispose();
    });
  });

  group('with polymarket.trade withheld', () {
    late RuntimeCapabilitiesService policy;
    setUp(() {
      AffiliateService.debugSessionToken = 'test-session';
      policy = runtimePolicyFixture(blocked: {'polymarket.trade'});
      RuntimeCapabilitiesService.debugInstance = policy;
    });
    tearDown(() {
      RuntimeCapabilitiesService.debugInstance = null;
      AffiliateService.debugSessionToken = null;
    });

    testWidgets(
        'the market stays on screen; Place is disabled with the reason '
        'above it', (tester) async {
      expect(await policy.refresh(), isTrue);
      await _pumpSlip(tester);
      // No wall: the question, the payout and the amount are all still
      // there to read.
      expect(find.text('Will it rain?'), findsOneWidget);
      expect(find.text('Payout if you win'), findsOneWidget);
      expect(find.text('Predictions unavailable here'), findsNothing);
      final place = tester.widget<PolySlipCta>(find.ancestor(
          of: find.text(r'Place $10.00 on Yes'),
          matching: find.byType(PolySlipCta)));
      expect(place.enabled, isFalse);
      final note = find.byType(CapabilityBlockNote);
      expect(note, findsOneWidget);
      expect(
          find.descendant(
              of: note,
              matching:
                  find.text('This feature is currently unavailable in Kute.')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      policy.dispose();
    });

    testWidgets('a short balance does not offer a deposit for a dead bet',
        (tester) async {
      expect(await policy.refresh(), isTrue);
      await _pumpSlip(tester, balance: 0);
      final door = tester.widget<PolySlipCta>(
          find.byKey(const ValueKey('bet-slip-deposit-door')));
      expect(door.enabled, isFalse);
      expect(find.byType(CapabilityBlockNote), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      policy.dispose();
    });
  });

  testWidgets('Max excludes the unfilled portion of resting buy orders',
      (tester) async {
    final policy = await _allowEverything();
    await _pumpSlip(tester, orders: const [
      Order(
          id: 'buy',
          market: 'm',
          assetId: 'a',
          owner: 'o',
          side: 'BUY',
          price: '0.5',
          originalSize: '100',
          sizeMatched: '20',
          outcome: 'Yes'),
      Order(
          id: 'sell',
          market: 'm',
          assetId: 'a',
          owner: 'o',
          side: 'SELL',
          price: '0.5',
          originalSize: '100',
          sizeMatched: '0',
          outcome: 'Yes'),
    ]);
    // 100 cash less the unfilled 80 shares of the resting buy at 50c.
    expect(find.text(r'Available $60.00 · Minimum $1.00'), findsOneWidget);
    // Max beside the figure stakes all of it: the largest stake
    // whose stake plus worst-case venue fees, plus the market buy's
    // rounding cent, still fits the $60. The fee is sized at the side's
    // live price (50c), not the slippage-raised order price (52.5c): a
    // buy's fee per dollar is larger at the lower price, which is where
    // the placement check sizes it, so a Max sized at 52.5c was refused.
    await tester.tap(find.byType(AmountMaxChip));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    final staked = double.parse(
        tester.widget<TextField>(find.byType(TextField)).controller!.text);
    const terms = PolymarketFeeTerms.worstCase;
    expect(staked, terms.maxNotionalFor(60, 0.5, reserve: 0.01));
    expect(terms.allInCost(staked, 0.5) + 0.01, lessThanOrEqualTo(60));
    expect(staked, lessThan(terms.maxNotionalFor(60, 0.525)));
    expect(staked, greaterThan(50));
    expect(tester.takeException(), isNull);
    await _release(tester, policy);
  });

  testWidgets(
      'one small Max beside the figure; available and minimum under it, '
      'the minimum red while the stake is under it', (tester) async {
    final policy = await _allowEverything();
    await _pumpSlip(tester, balance: 60);
    String typed() =>
        tester.widget<BigAmountDisplay>(find.byType(BigAmountDisplay)).amountText;
    final hero = find.byType(BigAmountDisplay);
    Finder infoLine() =>
        find.descendant(of: hero, matching: find.textContaining('Minimum '));
    TextSpan minimumSpan() =>
        (tester.widget<Text>(infoLine()).textSpan! as TextSpan)
            .children!
            .cast<TextSpan>()
            .singleWhere((s) => s.text!.startsWith('Minimum '));
    final errorInk = Theme.of(tester.element(hero))
        .extension<AppColorsExtension>()!
        .error;
    bool placeEnabled() =>
        tester.widget<PolySlipCta>(find.byType(PolySlipCta)).enabled;

    // No Min, no full-width chip row: one Max, on the figure's row.
    expect(find.byType(AmountQuickChips), findsNothing);
    expect(find.text('Min'), findsNothing);
    final max =
        find.descendant(of: hero, matching: find.byType(AmountMaxChip));
    expect(max, findsOneWidget);
    final figure = tester.getRect(
        find.descendant(of: hero, matching: find.byType(FittedBox)));
    expect(tester.getRect(max).center.dy, closeTo(figure.center.dy, 1));
    // One quiet line: the balance, then the market's minimum.
    expect(tester.widget<Text>(infoLine()).textSpan!.toPlainText(),
        r'Available $60.00 · Minimum $1.00');
    expect(find.textContaining(r'$60.00'), findsOneWidget);
    expect(minimumSpan().style?.color, isNot(errorInk));

    await _typeOnKeypad(tester, '0.5');
    expect(minimumSpan().style?.color, errorInk);
    // Said once, on that line: nothing small above the keypad.
    expect(find.textContaining('Minimum is'), findsNothing);
    // ...and on the button, which now fills it instead of sitting dead.
    expect(find.textContaining('Minimum '), findsNWidgets(2));
    expect(tester.widget<PolySlipCta>(find.byType(PolySlipCta)).label,
        r'Minimum $1.00');
    expect(placeEnabled(), isTrue);

    await tester.tap(find.bySemanticsLabel('Use maximum'));
    await tester.pumpAndSettle();
    const terms = PolymarketFeeTerms.worstCase;
    final fundable = terms.maxNotionalFor(60, 0.5, reserve: 0.01);
    expect(double.parse(typed()), (fundable * 100).floorToDouble() / 100);
    expect(minimumSpan().style?.color, isNot(errorInk));
    expect(placeEnabled(), isTrue);
    expect(tester.takeException(), isNull);
    await _release(tester, policy);
  });

  testWidgets(
      'estimated fee uses the live curve and Kute rate at the live price, '
      'not the slippage cap', (tester) async {
    // A live read: a 3% curve and Kute's 20 bps taker rate.
    const terms = PolymarketFeeTerms(
        rate: 0.03, exponent: 1, builderTakerBps: 20, builderMakerBps: 0);
    await _pumpSlip(tester,
        feeTerms: terms,
        outcomes: const [
          PolymarketOutcome(name: 'Yes', price: 0.5, tokenId: 'yes-token'),
          PolymarketOutcome(name: 'No', price: 0.5, tokenId: 'no-token'),
        ]);
    await _typeOnKeypad(tester, '20');

    // $20 at the 50c live price is 40 shares: 40 × 0.03 × 0.5 × 0.5 =
    // $0.30 to Polymarket plus 20 bps of $20 = $0.04 to Kute. Priced at
    // the 52.5c slippage cap it read $0.33, short of what the venue takes.
    final summary =
        tester.widget<PolymarketFeeSummary>(find.byType(PolymarketFeeSummary));
    expect(summary.price, 0.5);
    expect(summary.shares, 40);
    expect(terms.totalFee(summary.shares, summary.price), closeTo(0.34, 1e-9));
    expect(find.text('Estimated fee'), findsOneWidget);
    expect(find.text(r'$0.34'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('small screen with keyboard retains a reachable action',
      (tester) async {
    await _pumpSlip(tester, width: 320, keyboard: 300);
    expect(tester.takeException(), isNull);
    final action = tester.getRect(find.text(r'Place $10.00 on Yes'));
    expect(action.bottom, lessThanOrEqualTo(544));
    expect(action.top, greaterThan(0));
    final scroll = tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView));
    expect(scroll.physics, isA<ClampingScrollPhysics>());
  });
  for (final keyboard in [0.0, 300.0]) {
    testWidgets(
        'advanced funding action stays pinned under long content with keyboard \$keyboard',
        (tester) async {
      final policy = await _allowEverything();
      await _pumpSlip(tester,
          balance: 0,
          width: 320,
          height: 700,
          question:
              'Will the city report more than one hundred millimeters of rainfall '
              'during the first full week of October, according to the official '
              'weather station, with the final report published before the end of the month?');
      await tester.ensureVisible(find.text('Advanced'));
      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
      await tester.pumpAndSettle();
      final scroll =
          find.byKey(const ValueKey('prediction-advanced-form-scroll'));
      final action = find.text('Deposit to predict');
      final position = tester
          .state<ScrollableState>(find
              .descendant(of: scroll, matching: find.byType(Scrollable))
              .first)
          .position;
      // The long form scrolls; the action is pinned as a bottom bar
      // outside it (3d8c274c), so it is reachable without scrolling and
      // the form never runs underneath it.
      expect(position.maxScrollExtent, greaterThan(0));
      expect(find.ancestor(of: action, matching: scroll), findsNothing);
      expect(position.pixels, 0);
      expect(action.hitTestable(), findsOneWidget);
      expect(tester.getRect(action).bottom, lessThanOrEqualTo(700 - keyboard));
      expect(tester.getRect(scroll).bottom,
          lessThanOrEqualTo(tester.getRect(action).top));
      expect(tester.takeException(), isNull);
      await _release(tester, policy);
    });
  }

  testWidgets('advanced funding action rests at bottom when content fits',
      (tester) async {
    final policy = await _allowEverything();
    await _pumpSlip(tester, balance: 0, height: 1600);
    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    final scroll =
        find.byKey(const ValueKey('prediction-advanced-form-scroll'));
    final position = tester
        .state<ScrollableState>(find
            .descendant(of: scroll, matching: find.byType(Scrollable))
            .first)
        .position;
    expect(position.maxScrollExtent, 0);
    final action = find
        .ancestor(
            of: find.text('Deposit to predict'), matching: find.byType(InkWell))
        .first;
    expect(tester.getRect(action).bottom, closeTo(1600 - 16 * 1600 / 932, 1));
    expect(tester.takeException(), isNull);
    await _release(tester, policy);
  });

  testWidgets(
      'trading.advanced withheld: Advanced stays, a tap opens the sheet only',
      (tester) async {
    AffiliateService.debugSessionToken = 'test-session';
    final policy = runtimePolicyFixture(blocked: {'trading.advanced'});
    RuntimeCapabilitiesService.debugInstance = policy;
    expect(await policy.refresh(), isTrue);
    await _pumpSlip(tester);
    expect(find.text('Advanced'), findsOneWidget);
    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('capability-unavailable-got-it')),
        findsOneWidget);
    expect(find.text('Advanced prediction'), findsNothing);
    await tester
        .tap(find.byKey(const ValueKey('capability-unavailable-got-it')));
    await tester.pumpAndSettle();
    expect(find.text('Advanced prediction'), findsNothing);
    expect(find.text(r'Place $10.00 on Yes'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _release(tester, policy);
  });

  testWidgets('no readable policy: Advanced opens the sheet, not the page',
      (tester) async {
    await _pumpSlip(tester);
    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('capability-unavailable-got-it')),
        findsOneWidget);
    expect(find.text('Advanced prediction'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('first prediction: the account setup does not finish', () {
    const outcomes = [
      PolymarketOutcome(name: 'Yes', price: 0.5, tokenId: '1'),
      PolymarketOutcome(name: 'No', price: 0.5, tokenId: '2'),
    ];
    for (final (timedOut, line) in [
      (
        true,
        'Your Predictions account is still being set up. This can take a '
            'minute. Try again shortly.'
      ),
      (
        false,
        'Your Predictions account could not finish setting up. Your money is '
            'safe. Try again.'
      ),
    ]) {
      testWidgets(
          '${timedOut ? 'still running' : 'failed'}: the slip says so with a '
          'Retry instead of the spinner just stopping', (tester) async {
        final policy = await _allowEverything();
        late _SetupController controller;
        await _pumpSlip(tester, outcomes: outcomes, extraOverrides: [
          polymarketBetControllerProvider.overrideWith((ref) => controller =
              _SetupController(
                  ref,
                  PolymarketSetupIncomplete(
                      timedOut: timedOut,
                      cause: timedOut ? null : StateError('busy')))),
        ]);
        await tester.tap(find.text(r'Place $10.00 on Yes'));
        await tester.pumpAndSettle();
        expect(controller.prepares, 1);
        // Before, the status went to failed but the slip showed nothing:
        // the spinner stopped and the button read "Place" again.
        expect(find.text('Could not place prediction'), findsOneWidget);
        expect(find.text(line), findsOneWidget);
        final retry = find.byKey(const ValueKey('bet-slip-retry'));
        expect(retry, findsOneWidget);
        // Retry runs the whole tap again (nothing was sent the first time).
        await tester.tap(retry);
        await tester.pumpAndSettle();
        expect(controller.prepares, 2);
        expect(find.text(line), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _release(tester, policy);
      });
    }
  });

  group('under the minimum', () {
    PolySlipCta cta(WidgetTester tester) =>
        tester.widget<PolySlipCta>(find.byType(PolySlipCta));

    testWidgets('the button names the minimum and a tap fills it',
        (tester) async {
      final events = <(String, Map<String, Object?>?)>[];
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
      addTearDown(() => TrackingService.debugTrackObserver = null);
      final policy = await _allowEverything();
      await _pumpSlip(tester);
      await _typeOnKeypad(tester, '0.5');
      expect(cta(tester).label, r'Minimum $1.00');
      expect(cta(tester).enabled, isTrue);
      expect(find.textContaining('Place'), findsNothing);
      events.clear();
      await tester.tap(find.byType(PolySlipCta));
      await tester.pumpAndSettle();
      expect(find.text(r'$1'), findsOneWidget);
      expect(cta(tester).label, r'Place $1.00 on Yes');
      expect(cta(tester).enabled, isTrue);
      expect(
          events.any((e) =>
              e.$1 == 'bet_slip_available_tapped' && e.$2?['chip'] == 'min'),
          isTrue);
      expect(tester.takeException(), isNull);
      await _release(tester, policy);
    });

    testWidgets('a zero amount is the bet at the minimum again',
        (tester) async {
      final policy = await _allowEverything();
      await _pumpSlip(tester);
      await _typeOnKeypad(tester, '0');
      expect(cta(tester).label, r'Place $1.00 on Yes');
      expect(cta(tester).enabled, isTrue);
      await _release(tester, policy);
    });

    testWidgets('above the minimum the button is the bet', (tester) async {
      final policy = await _allowEverything();
      await _pumpSlip(tester);
      await _typeOnKeypad(tester, '3');
      expect(cta(tester).label, r'Place $3.00 on Yes');
      expect(cta(tester).enabled, isTrue);
      await _release(tester, policy);
    });
  });

  group('slip title', () {
    test('shows the question once when the event repeats it', () {
      const same = 'Villena: Francesco Maestrelli vs Oliver Tarvet';
      expect(polySlipTitle('$same: $same'), same);
      expect(polySlipTitle('$same: ${same.toUpperCase()}.'),
          '${same.toUpperCase()}.');
      expect(polySlipTitle('Villena:  villena:   A vs B'), 'villena:   A vs B');
      expect(polySlipTitle('Maestrelli vs Tarvet: Maestrelli vs Tarvet - Set 1'),
          'Maestrelli vs Tarvet - Set 1');
      // A different question, or an event that is only a word prefix,
      // keeps the joined title.
      expect(polySlipTitle('NBA Finals: Who wins game 7?'),
          'NBA Finals: Who wins game 7?');
      expect(polySlipTitle('Bit: Bitcoin above 100k?'),
          'Bit: Bitcoin above 100k?');
      expect(polySlipTitle('Will it rain?'), 'Will it rain?');
    });

    testWidgets('the header shows a single-market event once', (tester) async {
      const same = 'Villena: Francesco Maestrelli vs Oliver Tarvet';
      await _pumpSlip(tester, question: '$same: $same');
      expect(find.text(same), findsOneWidget);
      expect(find.text('$same: $same'), findsNothing);
    });
  });

  testWidgets('a long outcome name is not cut on a 375 wide phone',
      (tester) async {
    // Real glyph widths: the test font draws every letter a full em wide,
    // so no name would ever fit. Registered under its own family so the
    // other tests keep the default.
    await tester.runAsync(() async {
      final loader = FontLoader('SlipInter')
        ..addFont(rootBundle.load('lib/assets/fonts/Inter-Bold.ttf'));
      await loader.load();
    });
    await _pumpSlip(tester,
        fontFamily: 'SlipInter',
        width: 375,
        height: 812,
        question: 'Villena: Francesco Maestrelli vs Oliver Tarvet',
        sideLabelPos: 'Francesco Maestrelli',
        sideLabelNeg: 'Oliver Tarvet');
    for (final name in ['Francesco Maestrelli', 'Oliver Tarvet']) {
      final paragraph =
          tester.renderObject<RenderParagraph>(find.text(name).first);
      expect(paragraph.didExceedMaxLines, isFalse, reason: name);
    }
    expect(tester.takeException(), isNull);
  });

  group('an empty slip', () {
    PolySlipCta cta(WidgetTester tester) =>
        tester.widget<PolySlipCta>(find.byType(PolySlipCta));
    const outcomes = [
      PolymarketOutcome(
          name: 'Yes', price: 0.5, conditionId: 'cond-1', tokenId: '1'),
      PolymarketOutcome(
          name: 'No', price: 0.5, conditionId: 'cond-1', tokenId: '2'),
    ];
    // The CLOB's own floor for this market: 10 shares at 50c is $5.
    final tenShares = polymarketMinOrderSizeProvider
        .overrideWith((ref, _) async => 10.0);

    testWidgets('opens at zero and types from there, nothing to delete',
        (tester) async {
      final events = <(String, Map<String, Object?>?)>[];
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
      addTearDown(() => TrackingService.debugTrackObserver = null);
      final policy = await _allowEverything();
      await _pumpSlip(tester, initialAmountUsd: null);
      expect(find.text(r'$0'), findsOneWidget);
      expect(cta(tester).label, r'Place $1.00 on Yes');
      expect(cta(tester).enabled, isTrue);
      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();
      final step = events.lastWhere((e) => e.$1 == 'polymarket_bet_step');
      expect(step.$2?['amount_method'], 'none');
      await tester.tap(find.byType(KuteBackButton));
      await tester.pumpAndSettle();
      // The first key is the amount: no prefill to clear first.
      await tester.tap(find.descendant(
          of: find.byType(AmountKeypad), matching: find.text('7')));
      await tester.pumpAndSettle();
      expect(find.text(r'$7'), findsOneWidget);
      expect(cta(tester).label, r'Place $7.00 on Yes');
      await _release(tester, policy);
    });

    testWidgets('the button names the market\'s minimum and a tap places '
        'exactly it', (tester) async {
      final events = <(String, Map<String, Object?>?)>[];
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
      addTearDown(() => TrackingService.debugTrackObserver = null);
      final policy = await _allowEverything();
      late _RecordingController controller;
      await _pumpSlip(tester,
          initialAmountUsd: null,
          outcomes: outcomes,
          extraOverrides: [
            tenShares,
            polymarketBetControllerProvider.overrideWith(
                (ref) => controller = _RecordingController(ref)),
          ]);
      expect(find.text(r'$0'), findsOneWidget);
      expect(find.text(r'Available $100.00 · Minimum $5.00'), findsOneWidget);
      expect(cta(tester).label, r'Place $5.00 on Yes');
      expect(cta(tester).enabled, isTrue);
      await tester.tap(find.byType(PolySlipCta));
      await tester.pumpAndSettle();
      expect(controller.amounts, [5.0]);
      expect(find.text(r'$5'), findsOneWidget);
      final step = events.lastWhere((e) => e.$1 == 'polymarket_bet_step');
      expect(step.$2?['amount_method'], 'min_direct');
      expect(events.any((e) => e.$1 == 'bet_slip_available_tapped'), isFalse);
      await _release(tester, policy);
    });

    testWidgets('typing turns the button into the typed bet and its checks',
        (tester) async {
      final policy = await _allowEverything();
      await _pumpSlip(tester,
          initialAmountUsd: null,
          outcomes: outcomes,
          extraOverrides: [tenShares]);
      await _typeOnKeypad(tester, '3');
      expect(cta(tester).label, r'Minimum $5.00');
      await _typeOnKeypad(tester, '7');
      expect(cta(tester).label, r'Place $7.00 on Yes');
      expect(cta(tester).enabled, isTrue);
      await _typeOnKeypad(tester, '200');
      expect(find.byKey(const ValueKey('bet-slip-deposit-door')),
          findsOneWidget);
      await _release(tester, policy);
    });

    testWidgets('an amount carried in still opens on it', (tester) async {
      final policy = await _allowEverything();
      await _pumpSlip(tester,
          initialAmountUsd: 12, outcomes: outcomes, extraOverrides: [tenShares]);
      expect(find.text(r'$12'), findsOneWidget);
      expect(cta(tester).label, r'Place $12.00 on Yes');
      await _release(tester, policy);
    });

    testWidgets('a Ledger slip opens empty with the same minimum button',
        (tester) async {
      final policy = await _allowEverything();
      await _pumpSlip(tester,
          initialAmountUsd: null,
          ledgerWalletId: 'ledger-1',
          extraOverrides: [
            ledgerPmPendingBetProvider.overrideWith((ref, _) async => false),
            ledgerPmBuyingPowerProvider.overrideWith((ref, _) async =>
                LedgerPmBuyingPower(
                    balance: BigInt.from(50000000),
                    reserved: BigInt.zero,
                    allowances: const {})),
          ]);
      expect(find.text(r'$0'), findsOneWidget);
      expect(cta(tester).label, r'Place $1.00 on Yes');
      expect(cta(tester).enabled, isTrue);
      await _typeOnKeypad(tester, '0.5');
      expect(cta(tester).label, r'Minimum $1.00');
      await _typeOnKeypad(tester, '5');
      expect(cta(tester).label, 'Review prediction');
      await _release(tester, policy);
    });

    testWidgets('less available than the minimum still offers the minimum',
        (tester) async {
      final policy = await _allowEverything();
      await _pumpSlip(tester,
          balance: 3,
          initialAmountUsd: null,
          outcomes: outcomes,
          extraOverrides: [tenShares]);
      expect(find.text(r'$0'), findsOneWidget);
      // The tap runs the placement, which offers the deposit it needs.
      expect(cta(tester).label, r'Place $5.00 on Yes');
      expect(cta(tester).enabled, isTrue);
      await _release(tester, policy);
    });
  });
}
