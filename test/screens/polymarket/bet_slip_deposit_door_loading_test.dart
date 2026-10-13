// The bet slip's bottom button while it cannot know yet what it should be:
// the Predictions balance not read yet ("Loading your account..."), and the
// Dollars door working out its prefill ("Calculating…").
//
// One balance: a bet short of venue cash funds itself from Dollars at the
// tap. Only when Dollars cannot cover that move either is the button the
// Dollars door, "Add $X to Investments", which opens the Dollars deposit
// door prefilled with what is missing and queues nothing.
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
import 'package:kute/screens/shared/slip_shortfall.dart';
import 'package:kute/services/one_balance/predictions_venue_funder.dart';
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

Future<void> _pumpSlip(WidgetTester tester,
    Future<PolymarketTradingState> account,
    {double dollars = 0}) async {
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
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
            splashFactory: NoSplash.splashFactory,
            fontFamily: 'Inter',
            extensions: [AppColorsExtension.light()]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          resizeToAvoidBottomInset: false,
          body: Align(
            alignment: Alignment.bottomCenter,
            child: BetSlipSheet(
                marketQuestion: 'Will it rain?',
                outcomes: _outcomes,
                initialAmountUsd: 10),
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

  group('the Dollars door while it works out the prefill', () {
    late RuntimeCapabilitiesService policy;
    late List<String> events;
    late List<double?> sheets;
    Completer<void>? sheet;

    setUp(() async {
      AffiliateService.debugSessionToken = 'test-session';
      policy = runtimePolicyFixture();
      RuntimeCapabilitiesService.debugInstance = policy;
      events = [];
      TrackingService.debugTrackObserver = (e, _) => events.add(e);
      sheets = [];
      debugShowSlipTopUpSheet = (venue, target) {
        sheets.add(target);
        return sheet!.future;
      };
    });

    tearDown(() {
      debugShowSlipTopUpSheet = null;
      TrackingService.debugTrackObserver = null;
      RuntimeCapabilitiesService.debugInstance = null;
      AffiliateService.debugSessionToken = null;
    });

    Future<void> release(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      policy.dispose();
    }

    testWidgets(
        'opens the Dollars door once, prefilled with what is missing, and '
        'queues nothing', (tester) async {
      sheet = Completer<void>();
      expect(await policy.refresh(), isTrue);
      // $5 of venue cash cannot cover the $10 bet; only the rest moves
      // (about $5.51 with fees, tolerance and buffer), and $2 of Dollars
      // cannot cover that move.
      await _pumpSlip(tester,
          Future.value(const PolymarketTradingState(usdcBalance: 5)),
          dollars: 2);
      await _frames(tester);
      expect(_cta(tester).label, r'Add $3.51 to Investments');
      expect(_cta(tester).enabled, isTrue);

      await tester.tap(_door);
      await _frames(tester, 3);
      // One door, prefilled with the $3.51 missing from Dollars, nothing
      // queued behind it: the person places the bet themselves after.
      expect(sheets, [3.51]);
      expect(_queued(tester), isNull);
      expect(events, isNot(contains('prediction_place_cta_tapped')));
      expect(events, isNot(contains('bet_slip_deposit_to_trade_tapped')));
      expect(events, isNot(contains('slip_top_up_opened')));
      // The door is open: shut until it closes.
      expect(_cta(tester).isBusy, isFalse);
      expect(_cta(tester).enabled, isFalse);
      await tester.tap(_door);
      await _frames(tester, 2);
      expect(sheets.length, 1);

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
      expect(_cta(tester).label, r'Add $3.51 to Investments');
      expect(_cta(tester).enabled, isTrue);
      expect(find.text(r'$10'), findsOneWidget);
      await release(tester);
    });

    testWidgets('the prefill counts the route fee the move will pay',
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
      expect(sheets, hasLength(1));
      // $10 plus the venue's fee ceiling, grossed up by 1%: over $10.10.
      expect(sheets.single, greaterThan(10.1));
      expect(_queued(tester), isNull);
      sheet!.complete();
      await _frames(tester, 3);
      await release(tester);
    });
  });
}
