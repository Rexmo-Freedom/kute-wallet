// Nothing typed on a hot bet slip whose Investments cannot cover even the
// minimum (founder, 14 October 2026: "open the btc sheet and then go back
// and start automatically the investment if user adds"): "Add $X to
// Investments" opens the Bitcoin Move sheet prefilled with X, carrying the
// bet at the minimum. Confirming an add that covers it is the go-ahead:
// the slip takes the minimum, runs the staged chain with the sheet's leg
// and places the bet, under ONE approval. Closing the sheet leaves the
// slip as it was; a declined approval moves nothing; a smaller add places
// nothing and says the money is in Investments.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/screens/shared/rubber_band_progress.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/auth_grant_registry.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/orchestra_model.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/settlement_operation.dart' show SettlementFlow;
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/pending_bet_autofire.dart'
    show kPendingBetAutofireId;
import 'package:kute/providers/pending_polymarket_bet_provider.dart';
import 'package:kute/providers/polymarket_bet_controller.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_open_orders_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/spark_address_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider;
import 'package:kute/screens/polymarket/components/bet_slip_sheet.dart';
import 'package:kute/screens/polymarket/components/slip_chrome.dart';
import 'package:kute/screens/shared/slip_shortfall.dart';
import 'package:kute/services/funding/settlement_runner.dart'
    show
        SettlementAuthorizationIntent,
        SettlementStepUpHook,
        SettlementStopReason,
        SettlementStopped;
import 'package:kute/services/one_balance/bitcoin_funded_order.dart';
import 'package:kute/services/one_balance/bitcoin_to_dollars_leg.dart';
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/services/one_balance/one_balance_state.dart'
    show OneBalanceVenue;
import 'package:kute/services/one_balance/order_funding.dart';
import 'package:kute/services/one_balance/predictions_venue_funder.dart';
import 'package:kute/services/one_balance/venue_cash_source.dart';
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/orchestra/orchestra_quote_guard.dart';
import 'package:kute/services/polymarket/polymarket_fee_terms.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart';

import '../../helpers/fake_swap_orders.dart';
import '../../helpers/runtime_policy_fixture.dart';

const _ownSpark =
    'spark1pgss93sy072yrmtad5cy2srwjhq8ekzuw78yhr808jn6htqfh9w8p8h9mfwlv9';
const _depositSpark =
    'spark1pgssy7d7vel0nh9m4326qc54e6rskpczn07dktww9rv4nu5ptvt0s9uc489gg2';

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
  @override
  Future<PolymarketTradingState> build() async =>
      const PolymarketTradingState(usdcBalance: 0);
}

class _Currency extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _Currency() : super(CurrencyState({'USD': Fixed.fromInt(60000)}));
  @override
  Future<void> updateRates() async {}
}

/// The venue's side of a bet: the book and the account are not asked.
class _Controller extends PolymarketBetController {
  _Controller(super.ref);

  @override
  Future<PendingBetIntent> prepareIntent(PendingBetIntent intent) async =>
      intent;

  @override
  SensitiveIntent? reviewIntent(PendingBetIntent intent) => PmGrants.betReview(
        walletId: 'w',
        tokenId: intent.tokenId,
        maxCostUsd: intent.amount * 1.1,
        worstPrice: 0.6,
        orderType: 'fak',
      );

  @override
  void prefetchForSend(PendingBetIntent intent) {}
}

/// The Dollars → Predictions move, recording what left.
class _Funder implements VenueFunder {
  final sent = <double>[];
  @override
  Future<VenueMoveResult> fund(
      {required double usd,
      required MoveAuthorization auth,
      String purpose = 'order_funding'}) async {
    sent.add(usd);
    return VenueMoveResult(
        quoteId: 'q_venue', sentUsd: usd, arrivingUsdEstimate: usd);
  }

  @override
  Future<VenueMoveQuote> estimate(double usd) async => VenueMoveQuote(
      arrivingUsd: usd, feeUsd: 0, fixedCostUsd: 0, minUsd: 1, maxUsd: 1000);

  @override
  Future<double> idleUsd() async => 0;

  @override
  Future<double> minimumUsd() async => 1;
}

/// The wallet behind the runner: the dollars land at once. Its own send
/// is the slip's Bitcoin leg, never the Move sheet's: it must not run.
class _Env {
  var sends = 0;
  BitcoinLegEnv get env => BitcoinLegEnv(
        ownSpark: () async => _ownSpark,
        send: ({
          required String sparkAddress,
          required BitcoinLegPlan plan,
          required SettlementStepUpHook stepUp,
          required void Function() onSending,
        }) async {
          sends++;
          throw StateError('the runner sent its own leg');
        },
        watcher: ({required DateTime since}) => _Landed(),
        dollarsNow: () => 0,
        freshDollars: () async => 0,
      );
}

class _Landed extends DollarsLandingWatcher {
  _Landed()
      : super(
          statusOf: (_) async => null,
          dollarsNow: () => 0,
          freshDollars: () async => null,
          kickSync: () {},
        );

  @override
  Future<DollarsLandingOutcome> watch({
    required String Function() id,
    required double baselineUsd,
    required double minRiseUsd,
    required double enoughUsd,
    void Function()? onSlow,
  }) async =>
      const DollarsLanded(byStatus: true, freshDollarsUsd: 10);
}

VerifiedOrchestraQuote _quote(int sats) => verifyOrchestraQuote(
      OrchestraQuoteRequest(
        sourceChain: 'spark',
        sourceAsset: 'BTC',
        destinationChain: 'spark',
        destinationAsset: 'USDB',
        amountBaseUnits: BigInt.from(sats),
        recipientAddress: _ownSpark,
        refundAddress: _ownSpark,
        recipientKind: RecipientKind.ownSpark,
        ownAddress: _ownSpark,
      ),
      OrchestraQuote.fromJson({
        'quoteId': 'q_sheet',
        'depositAddress': _depositSpark,
        'amountIn': '$sats',
        'estimatedOut': '${sats * 600}',
        'feeAmount': '0',
        'feeBps': 0,
        'totalFeeAmount': '0',
        'feeAsset': 'USDB',
        'route': ['spark:BTC', 'spark:USDB'],
        'expiresAt': '2026-09-15T12:02:00Z',
        'priceLockMode': 'floating',
      }),
      now: DateTime.utc(2026, 9, 15, 12),
      bounds: OrchestraQuoteBounds.forSource('spark',
          inputValueInOutputUnits: sats * 600.0),
      mainnet: true,
    );

/// The Move sheet's leg as the test confirms it: [targetUsd] typed, paid
/// only when the hook it is handed (the order's grant) covers the quote,
/// exactly as the settlement runner asks it before paying.
class _SheetLeg {
  _SheetLeg(this.targetUsd);
  final double targetUsd;
  final paid = <int>[];
  var asked = 0;

  MoveSheetLeg get leg => MoveSheetLeg(
        plan: BitcoinLegPlan(
          dollarsShortUsd: targetUsd,
          targetUsd: targetUsd,
          sats: 10000,
          maxSats: 12000,
          usdPerBtc: 60000,
        ),
        send: ({
          required String sparkAddress,
          required BitcoinLegPlan plan,
          required SettlementStepUpHook stepUp,
          required void Function() onSending,
        }) async {
          asked++;
          final q = _quote(10000);
          final ok = await stepUp(SettlementAuthorizationIntent(
            flow: SettlementFlow.moveBtcToUsdc,
            walletId: 'w',
            destination: '$sparkAddress|',
            routeLabel: BitcoinLegGrants.route,
            amountIn: q.amountIn,
            minReceive: BigInt.zero,
            maxFeeBps: 0,
            reviewedQuote: q,
          ));
          if (!ok) {
            throw const SettlementStopped(SettlementStopReason.declined);
          }
          onSending();
          paid.add(10000);
          return const BitcoinLegTicket(
              quoteId: 'q_sheet',
              sats: 10000,
              estimatedOutUsd: 6,
              minOutUsd: 6);
        },
      );
}

const _outcomes = [
  PolymarketOutcome(name: 'Yes', price: 0.5, tokenId: 'yes-token'),
  PolymarketOutcome(name: 'No', price: 0.5, tokenId: 'no-token'),
];

late _Env _env;
late _Funder _funder;

Future<void> _pumpSlip(WidgetTester tester) async {
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
            wallets: [WalletConfig(id: 'w', name: 'Spending')],
            activeWalletId: 'w',
          ))),
      polymarketTradingProvider.overrideWith(_Trading.new),
      swapOrdersProvider.overrideWith((ref) => FakeSwapOrders()),
      livePriceProvider.overrideWith(_Prices.new),
      polymarketOpenOrdersProvider
          .overrideWith((ref) => Stream.value(const <Order>[])),
      aiEnabledProvider.overrideWith((ref) async => false),
      currencyProvider.overrideWith((ref) => _Currency()),
      usdBalanceProvider.overrideWithValue(0),
      polymarketFeeTermsProvider
          .overrideWith((ref, _) async => PolymarketFeeTerms.worstCase),
      polymarketBetControllerProvider.overrideWith(_Controller.new),
      polymarketMarketWindowReaderProvider
          .overrideWithValue((_) async => null),
      sparkSelfAddressProvider.overrideWith((_) async => _ownSpark),
      venueCashPullerProvider.overrideWith((_) => VenueCashPuller(
          sources: const [],
          readDollars: () => 0,
          minimumUsd: (_) async => 1)),
      bitcoinLegEnvProvider.overrideWith((_) => _env.env),
      orderFundingControllerProvider.overrideWithValue(OrderFundingController(
          funderFor: (_) => _funder, dollarsUsd: () => 0)),
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
                initialAmountUsd: null),
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

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(BetSlipSheet)));

void main() {
  late RuntimeCapabilitiesService policy;
  late List<(SlipVenue, double?, MoveSheetOrder)> sheets;
  late List<SensitiveIntent> approvals;
  late bool approve;

  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    PredictionsVenueFunder.debugRouteShare = (_) async => 0;
    AffiliateService.debugSessionToken = 'test-session';
    FundedOrdersNotifier.persist = false;
    OrderFundingJourney.reset();
    policy = runtimePolicyFixture();
    RuntimeCapabilitiesService.debugInstance = policy;
    _env = _Env();
    _funder = _Funder();
    sheets = [];
    approvals = [];
    approve = true;
    // The spending bitcoin covers X.
    debugFreshSpendingBitcoin = () async => (sats: 1000000, usdPerBtc: 60000.0);
    debugBitcoinLegEstimate = (sats) async => sats / 1e8 * 60000 * 0.995;
    debugShowSlipMoveSheetWithOrder = (venue, target, order) async {
      sheets.add((venue, target, order));
    };
    // The ONE prompt, as the person answers it.
    debugPmBetFundingApproval = (intent) async {
      approvals.add(intent);
      if (!approve) return null;
      return AuthGrantRegistry.instance.issueAutofire(
          kPendingBetAutofireId, intent,
          method: AuthGrantMethod.biometric);
    };
  });

  tearDown(() {
    PredictionsVenueFunder.debugRouteShare = null;
    debugFreshSpendingBitcoin = null;
    debugBitcoinLegEstimate = null;
    debugShowSlipMoveSheetWithOrder = null;
    debugPmBetFundingApproval = null;
    AuthGrantRegistry.instance.cancelAutofire(kPendingBetAutofireId);
    FundedOrdersNotifier.persist = true;
    RuntimeCapabilitiesService.debugInstance = null;
    AffiliateService.debugSessionToken = null;
  });

  Future<void> release(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    policy.dispose();
    await tester.pump(const Duration(minutes: 15));
  }

  /// Nothing typed: "Add $X to Investments", tapped. Returns X and the
  /// order the Move sheet was opened with.
  Future<(double, MoveSheetOrder)> openSheet(WidgetTester tester) async {
    expect(await policy.refresh(), isTrue);
    await _pumpSlip(tester);
    expect(_door, findsOneWidget);
    final label = _cta(tester).label;
    expect(label, startsWith(r'Add $'));
    final x = double.parse(label.split(' ')[1].substring(1));
    await tester.tap(_door);
    await _frames(tester, 3);
    expect(sheets, hasLength(1));
    final (venue, target, order) = sheets.single;
    expect(venue, SlipVenue.predictions);
    // Prefilled with X, carrying the bet at the market's minimum.
    expect(target, closeTo(x, 0.001));
    expect(order.addUsd, closeTo(x, 0.001));
    expect(order.venue, OneBalanceVenue.predictions);
    // The sheet's review names it in one line.
    expect(order.followOn,
        'Then places \$${order.orderUsd.toStringAsFixed(2)} on Yes');
    // Nothing on the slip changed: still nothing typed, nothing queued.
    expect(_cta(tester).label, label);
    expect(_container(tester).read(pendingPolymarketBetProvider), isNull);
    return (x, order);
  }

  /// The sheet's confirm: the slip's answer, once the frames run.
  Future<MoveSheetOrderStart> confirm(
      WidgetTester tester, MoveSheetOrder order, MoveSheetLeg leg) async {
    MoveSheetOrderStart? answer;
    unawaited(order.start(leg).then((a) => answer = a));
    for (var i = 0; i < 40 && answer == null; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(answer, isNotNull);
    return answer!;
  }

  testWidgets(
      'confirming an add that covers it: back on the slip, the minimum, '
      'the steps with the band, and the bet placed under ONE approval',
      (tester) async {
    final (x, order) = await openSheet(tester);
    final sheet = _SheetLeg(x + 2);
    final answer = await confirm(tester, order, sheet.leg);
    expect(answer.status, MoveSheetOrderStatus.started);
    await _frames(tester, 3);

    // ONE approval, binding the bet, its move and the sheet's leg.
    expect(approvals, hasLength(1));
    final bound = approvals.single;
    expect(bound.action, SensitiveAction.pmBet);
    expect(BitcoinLegGrants.limit(maxSats: 12000, ownSpark: _ownSpark),
        bound.limits[VenueLimit.fundBtc]);
    // The sheet's leg went once, under that approval; the runner's own
    // never ran.
    expect(sheet.asked, 1);
    expect(sheet.paid, [10000]);
    expect(_env.sends, 0);
    // The slip took the bet it was sized for: the market's minimum.
    final pending = _container(tester).read(pendingPolymarketBetProvider)!;
    expect(pending.amount, order.orderUsd);
    expect(pending.status, PendingBetStatus.awaitingBalance);
    expect(_funder.sent, hasLength(1));

    // The steps, under one busy button with its band.
    expect(find.byKey(const ValueKey('bet-slip-funded-progress')),
        findsOneWidget);
    expect(_cta(tester).isBusy, isTrue);
    expect(_cta(tester).busyLabel, 'Getting your prediction ready');
    final money = '\$${order.orderUsd.toStringAsFixed(2)}';
    expect(
        find.text('Adding \$${(x + 2).toStringAsFixed(2)} to Investments'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('slip-funding-step-done-0')),
        findsOneWidget);
    expect(find.text('Placing $money on Yes'), findsOneWidget);

    // The venue credits it and the autofire places it.
    final notifier = _container(tester).read(pendingPolymarketBetProvider.notifier);
    notifier.updateStatus(PendingBetStatus.placing);
    await _frames(tester, 3);
    expect(_cta(tester).busyLabel, 'Placing $money on Yes');
    notifier.updateStatus(PendingBetStatus.done);
    await _frames(tester, 3);
    final record = _container(tester).read(fundedOrdersProvider).single;
    expect(record.stage, FundedOrderStage.done);
    expect(record.label.orderUsd, order.orderUsd);
    expect(approvals, hasLength(1), reason: 'never a second prompt');
    // The confirmation follows the band's snap.
    await tester.pump(RubberBand.snapSettle + const Duration(milliseconds: 50));
    await release(tester);
  });

  testWidgets('closing the sheet without adding: no order, the slip as it was',
      (tester) async {
    final events = <String>[];
    TrackingService.debugTrackObserver = (e, _) => events.add(e);
    addTearDown(() => TrackingService.debugTrackObserver = null);
    final (_, order) = await openSheet(tester);
    await _frames(tester, 5);
    expect(order, isNotNull);
    expect(_container(tester).read(pendingPolymarketBetProvider), isNull);
    expect(_container(tester).read(fundedOrdersProvider), isEmpty);
    expect(approvals, isEmpty);
    expect(_env.sends, 0);
    expect(_funder.sent, isEmpty);
    expect(_cta(tester).label, endsWith('to Investments'));
    expect(_cta(tester).enabled, isTrue);
    expect(events, isNot(contains('order_funding_started')));
    await release(tester);
  });

  testWidgets('a smaller add: nothing placed, "Tap to place" on the slip',
      (tester) async {
    final (x, order) = await openSheet(tester);
    expect(order.coveredBy(x - 1), isFalse);
    // The sheet's own move went through for less than X.
    order.addedOnly!(2);
    await _frames(tester, 3);
    expect(find.text(r'Your $2.00 is in Investments. Tap to place.'),
        findsOneWidget);
    expect(_container(tester).read(pendingPolymarketBetProvider), isNull);
    expect(
        FundedOrdersNotifier.activeOf(_container(tester).read(fundedOrdersProvider),
            OneBalanceVenue.predictions),
        isNull);
    expect(approvals, isEmpty);
    expect(_funder.sent, isEmpty);
    await release(tester);
  });

  testWidgets('Face ID declined on the sheet: nothing moves, nothing queued',
      (tester) async {
    approve = false;
    final (x, order) = await openSheet(tester);
    final sheet = _SheetLeg(x);
    final answer = await confirm(tester, order, sheet.leg);
    expect(answer.status, MoveSheetOrderStatus.declined);
    expect(approvals, hasLength(1));
    expect(sheet.asked, 0);
    expect(_env.sends, 0);
    expect(_funder.sent, isEmpty);
    expect(_container(tester).read(pendingPolymarketBetProvider), isNull);
    expect(_container(tester).read(fundedOrdersProvider), isEmpty);
    await release(tester);
  });

  testWidgets('an add that no longer covers the bet: the sheet moves alone',
      (tester) async {
    final (x, order) = await openSheet(tester);
    // Less than the bet now lacks: no approval, no order.
    final sheet = _SheetLeg(x / 4);
    final answer = await confirm(tester, order, sheet.leg);
    expect(answer.status, MoveSheetOrderStatus.notCovered);
    expect(approvals, isEmpty);
    expect(sheet.asked, 0);
    expect(_container(tester).read(pendingPolymarketBetProvider), isNull);
    await release(tester);
  });
}
