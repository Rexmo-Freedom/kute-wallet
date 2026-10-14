// The bet slip's bottom button while it cannot know yet what it should be:
// the Predictions balance not read yet ("Loading your account..."), and the
// Dollars door working out its prefill ("Calculating…").
//
// One balance: a bet short of venue cash funds itself from Dollars at the
// tap. Only when the whole Investments balance cannot cover that move is
// the button "Add $X to Investments", whose tap decides on the spending
// bitcoin read at the tap: the Bitcoin-funded chain when it covers X, the
// Investments Receive sheet (never the Bitcoin Move sheet) when it does
// not. "Available" is the whole spendable Investments.
import 'dart:async';

import 'package:flutter/material.dart';
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
import 'package:kute/providers/pending_polymarket_bet_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_open_orders_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider;
import 'package:kute/screens/polymarket/components/bet_slip_sheet.dart';
import 'package:kute/screens/shared/money_fee_summary.dart';
import 'package:kute/screens/shared/polymarket_fee_summary.dart';
import 'package:kute/services/polymarket/polymarket_fee_terms.dart';
import 'package:kute/screens/polymarket/components/slip_chrome.dart';
import 'package:kute/screens/shared/amount_keypad_panel.dart';
import 'package:kute/screens/shared/side_tint_palette.dart'
    show slipCtaLabelColor;
import 'package:kute/screens/shared/rubber_band_progress.dart';
import 'package:kute/screens/shared/slip_shortfall.dart';
import 'package:kute/services/one_balance/bitcoin_funded_order.dart'
    show
        SlipFundingDecision,
        SlipFundingRoute,
        SpendingBitcoin,
        debugBitcoinLegEstimate,
        debugFreshSpendingBitcoin,
        debugStartSlipBitcoinChain;
import 'package:kute/services/one_balance/predictions_venue_funder.dart';
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/services/one_balance/one_balance_state.dart'
    show OneBalanceVenue;
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

/// The Predictions account, answered when the test says so.
class _Trading extends PolymarketTradingNotifier {
  _Trading(this.answer);
  final Future<PolymarketTradingState> answer;
  @override
  Future<PolymarketTradingState> build() => answer;
}

/// The top-up reads the bitcoin price through [currencyProvider], whose
/// real notifier opens Hive. Tests never open Hive.
class _Currency extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _Currency() : super(CurrencyState({'USD': Fixed.fromInt(100)}));
  @override
  Future<void> updateRates() async {}
}

const _outcomes = [
  PolymarketOutcome(name: 'Yes', price: 0.5, tokenId: 'yes-token'),
  PolymarketOutcome(name: 'No', price: 0.5, tokenId: 'no-token'),
];

class _Funded extends FundedOrdersNotifier {
  _Funded(this.records);
  final List<FundedOrderRecord> records;
  @override
  List<FundedOrderRecord> build() => records;
}

FundedOrderRecord _btcBet(FundedOrderStage stage,
        {String marketKey = 'yes-token', bool slow = false}) =>
    FundedOrderRecord(
      id: 'fo_bet',
      label: FundedOrderLabel(
        venue: OneBalanceVenue.predictions,
        orderUsd: 10,
        side: 'Yes',
        market: 'Will it rain?',
        marketKey: marketKey,
      ),
      stage: stage,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      addUsd: 6,
      btcRowIds: const {'q_btc'},
      slow: slow,
    );

/// A bet funded from Dollars or the Investing cash (no Bitcoin leg).
FundedOrderRecord _fundedBet(FundedOrderStage stage,
        {FundedOrderStage? stoppedAt,
        FundedMoneyAt? moneyAt,
        String? reason,
        String? message}) =>
    FundedOrderRecord(
      id: 'fo_dollars',
      label: const FundedOrderLabel(
        venue: OneBalanceVenue.predictions,
        orderUsd: 10,
        side: 'Yes',
        market: 'Will it rain?',
        marketKey: 'yes-token',
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
    Future<PolymarketTradingState> account,
    {double dollars = 0,
    double? initialAmountUsd = 10,
    bool dark = false,
    List<FundedOrderRecord>? funded,
    String? slug,
    DateTime? endAt,
    bool reduceMotion = false}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
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
      polymarketTradingProvider.overrideWith(() => _Trading(account)),
      swapOrdersProvider.overrideWith((ref) => FakeSwapOrders()),
      livePriceProvider.overrideWith(_Prices.new),
      polymarketOpenOrdersProvider
          .overrideWith((ref) => Stream.value(const <Order>[])),
      aiEnabledProvider.overrideWith((ref) async => false),
      currencyProvider.overrideWith((ref) => _Currency()),
      usdBalanceProvider.overrideWithValue(dollars),
      // The venue's fee curve, answered at once: the fee row prices the
      // bet (and the move folded into it) instead of waiting on the
      // network.
      polymarketFeeTermsProvider
          .overrideWith((ref, _) async => PolymarketFeeTerms.worstCase),
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
            ]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(disableAnimations: reduceMotion),
            child: child!),
        home: Scaffold(
          resizeToAvoidBottomInset: false,
          body: Align(
            alignment: Alignment.bottomCenter,
            child: BetSlipSheet(
                marketQuestion: slug == null
                    ? 'Will it rain?'
                    : 'Bitcoin Up or Down - 5 minutes',
                marketSlug: slug,
                marketEndAt: endAt,
                outcomes: _outcomes,
                initialAmountUsd: initialAmountUsd),
          ),
        ),
      ),
    ),
  ));
  await _frames(tester);
}

/// The busy button animates for as long as it waits: pump, never settle.
Future<void> _frames(WidgetTester tester, [int n = 10]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

PolySlipCta _cta(WidgetTester tester) =>
    tester.widget<PolySlipCta>(find.byType(PolySlipCta));

Finder get _door => find.byKey(const ValueKey('bet-slip-deposit-door'));

/// The colour the slip's one button letters its label in.
Color? _ctaLabelColor(WidgetTester tester) => tester
    .widget<Text>(find.descendant(
        of: find.byType(PolySlipCta), matching: find.byType(Text)))
    .style
    ?.color;

PendingBetIntent? _queued(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(BetSlipSheet)))
        .read(pendingPolymarketBetProvider);

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    // The venue's estimate for the move: a route keeping nothing,
    // answered at once (never the network).
    PredictionsVenueFunder.debugRouteShare = (_) async => 0;
  });
  tearDown(() => PredictionsVenueFunder.debugRouteShare = null);

  group('before the Predictions balance is read', () {
    // Bets and deposits allowed, so the button is only about the balance.
    late RuntimeCapabilitiesService policy;
    setUp(() async {
      AffiliateService.debugSessionToken = 'test-session';
      policy = runtimePolicyFixture();
      RuntimeCapabilitiesService.debugInstance = policy;
    });
    tearDown(() {
      RuntimeCapabilitiesService.debugInstance = null;
      AffiliateService.debugSessionToken = null;
    });
    Future<void> release(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      policy.dispose();
    }

    testWidgets('waits, disabled, and never shows the Dollars door',
        (tester) async {
      final events = <String>[];
      TrackingService.debugTrackObserver = (e, _) => events.add(e);
      addTearDown(() => TrackingService.debugTrackObserver = null);
      expect(await policy.refresh(), isTrue);
      final account = Completer<PolymarketTradingState>();
      await _pumpSlip(tester, account.future);

      expect(find.byKey(const ValueKey('bet-slip-loading-account')),
          findsOneWidget);
      expect(_cta(tester).enabled, isFalse);
      expect(_cta(tester).isBusy, isTrue);
      expect(find.text('Loading your account...'), findsOneWidget);
      expect(_door, findsNothing);
      // A tap while it waits does nothing.
      await tester.tap(find.byType(PolySlipCta));
      await _frames(tester, 2);
      expect(events, isNot(contains('prediction_place_cta_tapped')));

      // The balance arrives and covers the bet: the bet, never the door.
      account.complete(const PolymarketTradingState(usdcBalance: 100));
      await _frames(tester);
      expect(find.byKey(const ValueKey('bet-slip-loading-account')),
          findsNothing);
      expect(_door, findsNothing);
      expect(_cta(tester).label, r'Place $10.00 on Yes');
      expect(_cta(tester).enabled, isTrue);
      await release(tester);
    });

    testWidgets('an empty balance and no Dollars, once read, is the door',
        (tester) async {
      expect(await policy.refresh(), isTrue);
      final account = Completer<PolymarketTradingState>();
      await _pumpSlip(tester, account.future);
      expect(_door, findsNothing);
      account.complete(const PolymarketTradingState(usdcBalance: 0));
      await _frames(tester);
      expect(_door, findsOneWidget);
      expect(_cta(tester).label, startsWith(r'Add $'));
      expect(_cta(tester).label, endsWith('to Investments'));
      expect(_cta(tester).enabled, isTrue);
      await release(tester);
    });

    testWidgets('an empty balance with Dollars that cover the move is the bet',
        (tester) async {
      expect(await policy.refresh(), isTrue);
      await _pumpSlip(tester,
          Future.value(const PolymarketTradingState(usdcBalance: 0)),
          dollars: 100);
      await _frames(tester);
      expect(_door, findsNothing);
      expect(_cta(tester).label, r'Place $10.00 on Yes');
      expect(_cta(tester).enabled, isTrue);
      // The move's own cost is folded into the venue fee row: part of the
      // total, one "Move fee" detail when the row is opened, never a row
      // of its own.
      final summary = tester
          .widget<PolymarketFeeSummary>(find.byType(PolymarketFeeSummary));
      expect(summary.moveFeeLabel, 'Move fee');
      expect(summary.moveFeeUsd, isNotNull);
      expect(summary.moveFeePending, isFalse);
      expect(find.text('Move fee'), findsNothing);
      final feeRow = find.descendant(
          of: find.byType(PolymarketFeeSummary),
          matching: find.byType(MoneyFeeSummary));
      expect(feeRow, findsOneWidget);
      await tester.ensureVisible(feeRow);
      await tester.tap(feeRow);
      await _frames(tester);
      expect(find.text('Move fee'), findsOneWidget);
      await release(tester);
    });

    testWidgets('a balance that could not be read is not taken for 0',
        (tester) async {
      expect(await policy.refresh(), isTrue);
      await _pumpSlip(tester,
          Future.value(const PolymarketTradingState(balanceKnown: false)));
      expect(find.byKey(const ValueKey('bet-slip-loading-account')),
          findsOneWidget);
      expect(_door, findsNothing);
      expect(_cta(tester).enabled, isFalse);
      await release(tester);
    });
  });

  group('the "Add" door with no bitcoin to cover X', () {
    late RuntimeCapabilitiesService policy;
    late List<String> events;
    late Map<String, Map<String, Object>?> lastParams;
    late List<double?> sheets;
    late List<double> receives;
    Completer<void>? sheet;

    setUp(() async {
      AffiliateService.debugSessionToken = 'test-session';
      policy = runtimePolicyFixture();
      RuntimeCapabilitiesService.debugInstance = policy;
      events = [];
      lastParams = {};
      TrackingService.debugTrackObserver = (e, p) {
        events.add(e);
        lastParams[e] = p;
      };
      sheets = [];
      debugShowSlipTopUpSheet = (venue, target) {
        sheets.add(target);
        return sheet!.future;
      };
      // No spending bitcoin in these tests: X is never covered, so the
      // tap opens the Investments Receive sheet, never the Move sheet.
      receives = [];
      debugShowSlipReceiveSheet = (venue, addUsd) {
        expect(venue, SlipVenue.predictions);
        receives.add(addUsd);
        return sheet!.future;
      };
    });

    tearDown(() {
      expect(sheets, isEmpty);
      debugShowSlipTopUpSheet = null;
      debugShowSlipReceiveSheet = null;
      TrackingService.debugTrackObserver = null;
      RuntimeCapabilitiesService.debugInstance = null;
      AffiliateService.debugSessionToken = null;
    });

    Future<void> release(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      policy.dispose();
    }

    testWidgets(
        'opens the Investments Receive sheet once for what is missing, and '
        'queues nothing', (tester) async {
      sheet = Completer<void>();
      expect(await policy.refresh(), isTrue);
      // $5 of venue cash cannot cover the $10 bet; only the rest moves
      // (about $5.70 with fees, tolerance and the engine buffer), and $2 of Dollars
      // cannot cover that move.
      await _pumpSlip(tester,
          Future.value(const PolymarketTradingState(usdcBalance: 5)),
          dollars: 2);
      await _frames(tester);
      expect(_cta(tester).label, r'Add $3.70 to Investments');
      expect(_cta(tester).enabled, isTrue);

      await tester.tap(_door);
      await _frames(tester, 3);
      // One Receive sheet for the $3.70 missing, never the Bitcoin Move
      // sheet, nothing queued behind it: the person places the bet
      // themselves after.
      expect(receives, [3.70]);
      expect(_queued(tester), isNull);
      expect(events, isNot(contains('prediction_place_cta_tapped')));
      expect(events, isNot(contains('bet_slip_deposit_to_trade_tapped')));
      // The Receive sheet reports itself once, as the Investing ticket's
      // does: this venue, the exact figures, the rule and the source.
      expect(events.where((e) => e == 'slip_top_up_opened').length, 1);
      final topUp = lastParams['slip_top_up_opened']!;
      expect(topUp['venue'], 'polymarket');
      expect(topUp['prefill_rule'], 'investments_shortfall');
      expect(topUp['suggested_source'], 'receive');
      expect(topUp['top_up_usd'], 3.70);
      expect(topUp['shortfall_usd'], greaterThan(0));
      expect(topUp.keys, containsAll(['shortfall_bucket', 'top_up_bucket']));
      // The door is open: shut until it closes.
      expect(_cta(tester).isBusy, isFalse);
      expect(_cta(tester).enabled, isFalse);
      await tester.tap(_door);
      await _frames(tester, 2);
      expect(receives.length, 1);

      // The slip is frozen while the door is open: the side and the
      // amount stay what was tapped.
      await tester.tap(find.text('NO'), warnIfMissed: false);
      final pad = find.byType(AmountKeypad);
      await tester.tap(find.descendant(of: pad, matching: find.text('9')),
          warnIfMissed: false);
      await _frames(tester, 3);
      expect(find.text(r'$10'), findsOneWidget);

      // The door closes without a deposit: the door again, amount kept.
      sheet!.complete();
      await _frames(tester, 3);
      expect(_cta(tester).label, r'Add $3.70 to Investments');
      expect(_cta(tester).enabled, isTrue);
      expect(find.text(r'$10'), findsOneWidget);
      await release(tester);
    });

    testWidgets('X counts the route fee the move will pay',
        (tester) async {
      sheet = Completer<void>();
      // A route keeping 1%: the $10 move must send more so $10 lands.
      PredictionsVenueFunder.debugRouteShare = (_) async => 0.01;
      expect(await policy.refresh(), isTrue);
      await _pumpSlip(tester,
          Future.value(const PolymarketTradingState(usdcBalance: 0)),
          dollars: 0);
      await _frames(tester);
      expect(_cta(tester).label, startsWith(r'Add $'));
      await tester.tap(_door);
      await _frames(tester, 3);
      expect(receives, hasLength(1));
      // $10 plus the venue's fee ceiling, grossed up by 1%: over $10.10.
      expect(receives.single, greaterThan(10.1));
      expect(_queued(tester), isNull);
      sheet!.complete();
      await _frames(tester, 3);
      await release(tester);
    });

    testWidgets(
        'nothing typed and Investments short of the minimum: the one button '
        'says "Add \$X to Investments", never "Place"', (tester) async {
      sheet = Completer<void>();
      expect(await policy.refresh(), isTrue);
      await _pumpSlip(tester,
          Future.value(const PolymarketTradingState(usdcBalance: 0)),
          dollars: 0,
          initialAmountUsd: null);
      await _frames(tester);
      expect(_door, findsOneWidget);
      expect(_cta(tester).label, startsWith(r'Add $'));
      expect(_cta(tester).label, endsWith('to Investments'));
      expect(_cta(tester).enabled, isTrue);
      expect(find.textContaining('Place'), findsNothing);
      // One action: no second Add or Deposit beside it.
      expect(find.byType(PolySlipCta), findsOneWidget);
      expect(find.textContaining('to Investments'), findsOneWidget);
      final label = _cta(tester).label;

      // The tap opens the Receive sheet for that amount, queues nothing,
      // and the button keeps saying the same thing.
      await tester.tap(_door);
      await _frames(tester, 3);
      expect(receives, hasLength(1));
      expect(receives.single,
          closeTo(double.parse(label.split(' ')[1].substring(1)), 0.011));
      expect(_queued(tester), isNull);
      expect(events, isNot(contains('prediction_place_cta_tapped')));
      sheet!.complete();
      await _frames(tester, 3);
      expect(_cta(tester).label, endsWith('to Investments'));
      await release(tester);
    });

    testWidgets(
        'nothing typed and Dollars that cover the minimum: the bet at the '
        'minimum', (tester) async {
      expect(await policy.refresh(), isTrue);
      await _pumpSlip(tester,
          Future.value(const PolymarketTradingState(usdcBalance: 0)),
          dollars: 100,
          initialAmountUsd: null);
      await _frames(tester);
      expect(_door, findsNothing);
      expect(_cta(tester).label, startsWith('Place '));
      expect(_cta(tester).enabled, isTrue);
      await release(tester);
    });
  });

  group('button label colour', () {
    // The order slip letters its button the same way (see
    // order_slip_funding_test): the trade in its side colour on the
    // sheet's white ink, the "Add $X to Investments" door in black on it.
    late RuntimeCapabilitiesService policy;
    setUp(() async {
      AffiliateService.debugSessionToken = 'test-session';
      policy = runtimePolicyFixture();
      RuntimeCapabilitiesService.debugInstance = policy;
    });
    tearDown(() {
      RuntimeCapabilitiesService.debugInstance = null;
      AffiliateService.debugSessionToken = null;
    });

    for (final dark in [false, true]) {
      final mode = dark ? 'dark' : 'light';
      testWidgets('$mode: the door contrasts with its fill, the bet wears '
          'its side', (tester) async {
        expect(await policy.refresh(), isTrue);
        await _pumpSlip(tester,
            Future.value(const PolymarketTradingState(usdcBalance: 0)),
            dollars: 0,
            dark: dark);
        await _frames(tester);
        expect(_door, findsOneWidget);
        expect(_ctaLabelColor(tester), Colors.black);
        expect(_ctaLabelColor(tester),
            slipCtaLabelColor(
                fill: Colors.white, side: AppColors.marketUp, neutral: true));
        await tester.pumpWidget(const SizedBox.shrink());

        await _pumpSlip(tester,
            Future.value(const PolymarketTradingState(usdcBalance: 100)),
            dark: dark);
        await _frames(tester);
        expect(_cta(tester).label, r'Place $10.00 on Yes');
        expect(_ctaLabelColor(tester), AppColors.marketUp);
        await tester.pumpWidget(const SizedBox.shrink());
        policy.dispose();
      });
    }
  });

  group('a bet funded from bitcoin shows its steps', () {
    late RuntimeCapabilitiesService policy;
    setUp(() async {
      AffiliateService.debugSessionToken = 'test-session';
      policy = runtimePolicyFixture();
      RuntimeCapabilitiesService.debugInstance = policy;
    });
    tearDown(() {
      RuntimeCapabilitiesService.debugInstance = null;
      AffiliateService.debugSessionToken = null;
    });
    Future<void> release(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      policy.dispose();
    }

    Future<void> pumpAt(WidgetTester tester, FundedOrderStage stage,
        {bool slow = false}) async {
      expect(await policy.refresh(), isTrue);
      await _pumpSlip(
          tester, Future.value(const PolymarketTradingState(usdcBalance: 0)),
          funded: [_btcBet(stage, slow: slow)]);
      await _frames(tester);
    }

    testWidgets('adding: the first step runs, one busy button',
        (tester) async {
      await pumpAt(tester, FundedOrderStage.adding);
      expect(find.byKey(const ValueKey('bet-slip-funded-progress')),
          findsOneWidget);
      expect(_cta(tester).isBusy, isTrue);
      expect(_cta(tester).enabled, isFalse);
      expect(_cta(tester).busyLabel, r'Adding $6.00 to Investments');
      expect(find.byKey(const ValueKey('slip-funding-step-active-0')),
          findsOneWidget);
      expect(find.text('Getting your prediction ready'), findsOneWidget);
      expect(find.text(r'Placing $10.00 on Yes'), findsOneWidget);
      // Never a second "Add" while it runs.
      expect(_door, findsNothing);
      expect(find.textContaining('Moving'), findsNothing);
      await release(tester);
    });

    testWidgets('slow: taking longer than usual', (tester) async {
      await pumpAt(tester, FundedOrderStage.adding, slow: true);
      expect(find.text('Taking longer than usual'), findsOneWidget);
      await release(tester);
    });

    testWidgets('preparing, then placing', (tester) async {
      await pumpAt(tester, FundedOrderStage.preparing);
      expect(_cta(tester).busyLabel, 'Getting your prediction ready');
      expect(find.byKey(const ValueKey('slip-funding-step-done-0')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('slip-funding-step-active-1')),
          findsOneWidget);
      await release(tester);
    });

    testWidgets('placing: the bet itself', (tester) async {
      await pumpAt(tester, FundedOrderStage.placing);
      expect(_cta(tester).busyLabel, r'Placing $10.00 on Yes');
      expect(find.byKey(const ValueKey('slip-funding-step-active-2')),
          findsOneWidget);
      await release(tester);
    });

    testWidgets('stopped with the money in Investments: tap to place',
        (tester) async {
      expect(await policy.refresh(), isTrue);
      await _pumpSlip(
          tester, Future.value(const PolymarketTradingState(usdcBalance: 0)),
          dollars: 100, funded: [_btcBet(FundedOrderStage.ready)]);
      await _frames(tester);
      expect(find.text(r'Your $6.00 is in Investments. Tap to place.'),
          findsOneWidget);
      expect(_cta(tester).label, r'Place $10.00 on Yes');
      expect(_cta(tester).enabled, isTrue);
      await release(tester);
    });
  });

  group('every funded bet shows its steps, whatever funds it', () {
    // Founder, 14 October 2026: "regardless of what is happening on the
    // prediction we should always show that progress there".
    late RuntimeCapabilitiesService policy;
    setUp(() async {
      AffiliateService.debugSessionToken = 'test-session';
      policy = runtimePolicyFixture();
      RuntimeCapabilitiesService.debugInstance = policy;
    });
    tearDown(() {
      RuntimeCapabilitiesService.debugInstance = null;
      AffiliateService.debugSessionToken = null;
    });
    Future<void> release(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      policy.dispose();
    }

    Future<void> pumpWith(WidgetTester tester, List<FundedOrderRecord> funded,
        {String? slug, DateTime? endAt, bool reduceMotion = false}) async {
      expect(await policy.refresh(), isTrue);
      await _pumpSlip(
          tester, Future.value(const PolymarketTradingState(usdcBalance: 0)),
          dollars: 100,
          funded: funded,
          slug: slug,
          endAt: endAt,
          reduceMotion: reduceMotion);
      await _frames(tester);
    }

    RubberBandProgressState band(WidgetTester tester) =>
        tester.state<RubberBandProgressState>(find.descendant(
            of: find.byKey(const ValueKey('bet-slip-funded-progress')),
            matching: find.byType(RubberBandProgress),
            matchRoot: true));

    testWidgets('from Dollars: the move, then the bet, one busy button',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpWith(tester, [_fundedBet(FundedOrderStage.preparing)]);
      expect(find.byKey(const ValueKey('bet-slip-funded-progress')),
          findsOneWidget);
      expect(_cta(tester).isBusy, isTrue);
      expect(_cta(tester).enabled, isFalse);
      expect(_cta(tester).busyLabel, 'Getting your prediction ready');
      // Said once, in the steps: the busy button only spins (and pulls),
      // and a screen reader still hears the step on it.
      expect(find.text('Getting your prediction ready'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(PolySlipCta),
              matching: find.text('Getting your prediction ready')),
          findsNothing);
      expect(
          find.descendant(
              of: find.byType(PolySlipCta),
              matching: find.byKey(const ValueKey('poly-slip-cta-busy-quiet'))),
          findsOneWidget);
      final quiet = tester.widget<Semantics>(
          find.byKey(const ValueKey('poly-slip-cta-busy-quiet')));
      expect(quiet.properties.label, 'Getting your prediction ready');
      expect(quiet.properties.liveRegion, isTrue);
      expect(find.bySemanticsLabel(RegExp('Getting your prediction ready')),
          findsWidgets);
      semantics.dispose();
      expect(find.byKey(const ValueKey('slip-funding-step-active-0')),
          findsOneWidget);
      expect(find.text(r'Placing $10.00 on Yes'), findsOneWidget);
      // No Bitcoin step without a Bitcoin leg.
      expect(find.textContaining('to Investments'), findsNothing);
      // The band is pulled.
      expect(band(tester).stretch, greaterThan(0));
      await release(tester);
    });

    testWidgets('from the Investing cash: the same steps, then the bet itself',
        (tester) async {
      final records = [_fundedBet(FundedOrderStage.placing)];
      await pumpWith(tester, records);
      expect(_cta(tester).busyLabel, r'Placing $10.00 on Yes');
      expect(find.text(r'Placing $10.00 on Yes'), findsOneWidget);
      expect(find.byKey(const ValueKey('slip-funding-step-done-0')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('slip-funding-step-active-1')),
          findsOneWidget);
      await release(tester);
    });

    testWidgets('the tension builds as the steps advance', (tester) async {
      final stretches = <double>[];
      for (final stage in [
        FundedOrderStage.preparing,
        FundedOrderStage.placing,
      ]) {
        await pumpWith(tester, [_fundedBet(stage)]);
        await _frames(tester, 20);
        stretches.add(band(tester).stretch);
        await tester.pumpWidget(const SizedBox.shrink());
      }
      expect(stretches[1], greaterThan(stretches[0]));
      policy.dispose();
    });

    testWidgets(
        'the venue refused once the money landed: the failed step, what '
        'happened and that the money is in Predictions', (tester) async {
      await pumpWith(tester, [
        _fundedBet(FundedOrderStage.failed,
            stoppedAt: FundedOrderStage.placing,
            moneyAt: FundedMoneyAt.venue,
            reason: 'price_moved',
            message: 'The price moved to 84¢, past your limit of 81¢.')
      ]);
      expect(find.byKey(const ValueKey('slip-funding-step-done-0')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('slip-funding-step-failed-1')),
          findsOneWidget);
      expect(
          find.text(r'Price moved too fast. Your $10.00 is in Predictions. '
              'Tap to try again.'),
          findsOneWidget);
      // The button is the bet again, never a silent reset.
      expect(_cta(tester).isBusy, isFalse);
      expect(_cta(tester).enabled, isTrue);
      expect(_cta(tester).label, r'Place $10.00 on Yes');
      // Let go softly: at rest, never past it.
      await _frames(tester, 20);
      expect(band(tester).stretch, 0);
      expect(band(tester).ticking, isFalse);
      await release(tester);
    });

    testWidgets('a 5-minute round with no Predictions cash shows the steps',
        (tester) async {
      await pumpWith(tester, [_fundedBet(FundedOrderStage.preparing)],
          slug: 'btc-updown-5m-1760443200',
          endAt: DateTime.now().add(const Duration(minutes: 4)));
      expect(find.byType(SlipFundingSteps), findsOneWidget);
      expect(_cta(tester).busyLabel, 'Getting your prediction ready');
      await release(tester);
    });

    testWidgets('the round closed before the money arrived: said so',
        (tester) async {
      await pumpWith(tester, [
        _fundedBet(FundedOrderStage.failed,
            stoppedAt: FundedOrderStage.preparing,
            moneyAt: FundedMoneyAt.venue,
            reason: 'market_closed')
      ],
          slug: 'btc-updown-5m-1760443200',
          endAt: DateTime.now().add(const Duration(minutes: 4)));
      expect(find.byKey(const ValueKey('slip-funding-step-failed-0')),
          findsOneWidget);
      expect(
          find.text(r'This round closed before your money arrived. Your '
              r'$10.00 is in Predictions. Tap to try again.'),
          findsOneWidget);
      await release(tester);
    });

    testWidgets('closed mid-way and reopened: the current step',
        (tester) async {
      await pumpWith(tester, [_fundedBet(FundedOrderStage.preparing)]);
      expect(find.byKey(const ValueKey('slip-funding-step-active-0')),
          findsOneWidget);
      // Closed: the chain carries on behind it.
      await tester.pumpWidget(const SizedBox.shrink());
      // Reopened once the money landed and the bet is going in.
      await pumpWith(tester, [_fundedBet(FundedOrderStage.placing)]);
      expect(find.byKey(const ValueKey('slip-funding-step-done-0')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('slip-funding-step-active-1')),
          findsOneWidget);
      expect(_cta(tester).busyLabel, r'Placing $10.00 on Yes');
      await release(tester);
    });

    testWidgets('Reduce Motion: the steps, nothing moves', (tester) async {
      await pumpWith(tester, [_fundedBet(FundedOrderStage.placing)],
          reduceMotion: true);
      expect(find.byType(SlipFundingSteps), findsOneWidget);
      expect(band(tester).stretch, 0);
      expect(band(tester).ticking, isFalse);
      await release(tester);
    });
  });

  group('the "Add" door decides on the spending bitcoin at the tap', () {
    // The same decision and states as the order slip
    // (order_slip_funding_test): parity.
    late RuntimeCapabilitiesService policy;
    late List<SlipFundingDecision> chains;
    late List<double> receives;
    late List<double?> sheets;

    setUp(() async {
      AffiliateService.debugSessionToken = 'test-session';
      policy = runtimePolicyFixture();
      RuntimeCapabilitiesService.debugInstance = policy;
      chains = [];
      receives = [];
      sheets = [];
      debugStartSlipBitcoinChain = (venue, decision) async {
        expect(venue, OneBalanceVenue.predictions);
        chains.add(decision);
      };
      debugShowSlipReceiveSheet = (venue, addUsd) async {
        receives.add(addUsd);
      };
      debugShowSlipTopUpSheet = (venue, target) async {
        sheets.add(target);
      };
      // The route keeps 0.5%.
      debugBitcoinLegEstimate = (sats) async => sats / 1e8 * 60000 * 0.995;
    });

    tearDown(() {
      debugStartSlipBitcoinChain = null;
      debugShowSlipReceiveSheet = null;
      debugShowSlipTopUpSheet = null;
      debugBitcoinLegEstimate = null;
      debugFreshSpendingBitcoin = null;
      RuntimeCapabilitiesService.debugInstance = null;
      AffiliateService.debugSessionToken = null;
    });

    Future<void> release(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      policy.dispose();
    }

    testWidgets(
        'a first tap while the bitcoin is still loading waits, busy, then '
        'runs the chain once it is read: no sheet', (tester) async {
      final fresh = Completer<SpendingBitcoin?>();
      debugFreshSpendingBitcoin = () => fresh.future;
      expect(await policy.refresh(), isTrue);
      await _pumpSlip(tester,
          Future.value(const PolymarketTradingState(usdcBalance: 5)),
          dollars: 2);
      await _frames(tester);
      expect(_cta(tester).label, r'Add $3.70 to Investments');

      await tester.tap(_door);
      await _frames(tester, 3);
      // The balance is still being read: the door's own busy state, never
      // a sheet.
      expect(_cta(tester).isBusy, isTrue);
      expect(_cta(tester).busyLabel, 'Calculating…');
      expect(_cta(tester).enabled, isFalse);
      expect(chains, isEmpty);
      expect(receives, isEmpty);
      expect(sheets, isEmpty);

      fresh.complete((sats: 100000, usdPerBtc: 60000.0));
      await _frames(tester, 3);
      expect(chains, hasLength(1));
      expect(chains.single.route, SlipFundingRoute.bitcoin);
      expect(chains.single.addUsd, 3.70);
      expect(chains.single.plan!.targetUsd, 3.70);
      expect(chains.single.plan!.maxSats, lessThanOrEqualTo(100000));
      expect(receives, isEmpty);
      expect(sheets, isEmpty);
      await release(tester);
    });

    testWidgets(
        "bitcoin short of X once the route's spread is counted: the "
        'Investments Receive sheet for X, never the chain or the Move sheet',
        (tester) async {
      // $3.70 of bitcoin for an X of $3.70: the route keeps 0.5%.
      debugFreshSpendingBitcoin = () async =>
          (sats: (3.70 / 60000 * 1e8).round(), usdPerBtc: 60000.0);
      expect(await policy.refresh(), isTrue);
      await _pumpSlip(tester,
          Future.value(const PolymarketTradingState(usdcBalance: 5)),
          dollars: 2);
      await _frames(tester);
      await tester.tap(_door);
      await _frames(tester, 3);
      expect(receives, [3.70]);
      expect(chains, isEmpty);
      expect(sheets, isEmpty);
      expect(_queued(tester), isNull);
      await release(tester);
    });
  });

  group('Available is the whole spendable Investments', () {
    late RuntimeCapabilitiesService policy;
    setUp(() async {
      AffiliateService.debugSessionToken = 'test-session';
      policy = runtimePolicyFixture();
      RuntimeCapabilitiesService.debugInstance = policy;
    });
    tearDown(() {
      RuntimeCapabilitiesService.debugInstance = null;
      AffiliateService.debugSessionToken = null;
    });

    testWidgets(
        "the venue's cash plus Dollars, and Max fills a bet the slip funds "
        'itself', (tester) async {
      expect(await policy.refresh(), isTrue);
      // $0.49 of Predictions cash and $8.10 in Dollars.
      await _pumpSlip(tester,
          Future.value(const PolymarketTradingState(usdcBalance: 0.49)),
          dollars: 8.10,
          initialAmountUsd: null);
      await _frames(tester);
      expect(find.textContaining(r'Available $8.59'), findsOneWidget);
      expect(find.textContaining(r'Available $0.49'), findsNothing);

      await tester.tap(find.text('Max'));
      await _frames(tester);
      // A stake past the $0.49 here, that the move from Dollars covers:
      // the button is the bet, never "Add".
      final label = _cta(tester).label;
      expect(label, startsWith('Place '));
      final stake = double.parse(label.split(' ')[1].substring(1));
      expect(stake, greaterThan(5));
      expect(stake, lessThan(8.59));
      expect(_door, findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      policy.dispose();
    });
  });
}
