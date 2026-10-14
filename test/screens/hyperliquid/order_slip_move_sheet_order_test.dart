// Nothing typed on a hot Investing ticket whose Investments cannot cover
// even the minimum order (founder, 14 October 2026: "open the btc sheet
// and then go back and start automatically the investment if user
// adds"): "Add $X to Investments" opens the Bitcoin Move sheet prefilled
// with X, carrying the order at the minimum. Confirming an add that covers
// it is the go-ahead: the ticket takes the minimum, runs the staged chain
// with the sheet's leg and opens the order, under ONE approval. Closing
// the sheet leaves the ticket as it was; a declined approval moves
// nothing; a smaller add opens nothing and says the money is in
// Investments. The bet slip does the same (bet_slip_move_sheet_order_test).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/auth_grant_registry.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/orchestra_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/settlement_operation.dart' show SettlementFlow;
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_orderbook_provider.dart';
import 'package:kute/providers/pending_hyperliquid_order_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/spark_address_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/providers/usd_account_provider.dart';
import 'package:kute/screens/hyperliquid/components/order_slip_sheet.dart';
import 'package:kute/screens/shared/custom_button.dart';
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
import 'package:kute/services/one_balance/hyperliquid_move_rail.dart';
import 'package:kute/services/one_balance/one_balance_state.dart'
    show OneBalanceVenue;
import 'package:kute/services/one_balance/order_funding.dart';
import 'package:kute/services/one_balance/venue_cash_source.dart';
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/orchestra/orchestra_quote_guard.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart';

import '../../helpers/fake_hyperliquid_move_rail.dart';
import '../../helpers/fake_swap_orders.dart';
import '../../helpers/runtime_policy_fixture.dart';

const _ownSpark =
    'spark1pgss93sy072yrmtad5cy2srwjhq8ekzuw78yhr808jn6htqfh9w8p8h9mfwlv9';
const _depositSpark =
    'spark1pgssy7d7vel0nh9m4326qc54e6rskpczn07dktww9rv4nu5ptvt0s9uc489gg2';

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
  @override
  Future<HlAccountSnapshot> build() async => const HlAccountSnapshot(
        accountValue: 0,
        withdrawable: 0,
        totalMarginUsed: 0,
        positions: [],
        spotBalances: [],
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

/// The rail's estimate at the very amount sent: a 0.1% route with the $1
/// gas float on an empty account.
class _Rail extends FakeHyperliquidMoveRail {
  @override
  Future<VenueMoveQuote> estimate(
          {required double usd, required bool deposit}) async =>
      VenueMoveQuote(
          arrivingUsd: usd * 0.999 - 1,
          feeUsd: usd * 0.001,
          fixedCostUsd: 1,
          minUsd: 0.8,
          maxUsd: 107600);
}

/// The Dollars → Investing move, recording what left.
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
/// must never run: the leg is the Move sheet's.
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
      const DollarsLanded(byStatus: true, freshDollarsUsd: 100);
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
/// only when the hook it is handed (the order's grant) covers the quote.
class _SheetLeg {
  _SheetLeg(this.targetUsd);
  final double targetUsd;
  final paid = <int>[];
  var asked = 0;

  MoveSheetLeg get leg => MoveSheetLeg(
        plan: BitcoinLegPlan(
          dollarsShortUsd: targetUsd,
          targetUsd: targetUsd,
          sats: 30000,
          maxSats: 36000,
          usdPerBtc: 60000,
        ),
        send: ({
          required String sparkAddress,
          required BitcoinLegPlan plan,
          required SettlementStepUpHook stepUp,
          required void Function() onSending,
        }) async {
          asked++;
          final q = _quote(30000);
          final ok = await stepUp(SettlementAuthorizationIntent(
            flow: SettlementFlow.moveBtcToUsdc,
            walletId: 'w1',
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
          paid.add(30000);
          return const BitcoinLegTicket(
              quoteId: 'q_sheet',
              sats: 30000,
              estimatedOutUsd: 18,
              minOutUsd: 18);
        },
      );
}

late _Env _env;
late _Funder _funder;

Future<void> _pumpSlip(WidgetTester tester, FakeHyperliquidMoveRail rail) async {
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
            wallets: [WalletConfig(id: 'w1', name: 'Spending')],
            activeWalletId: 'w1',
          ))),
      hyperliquidLivePricesProvider.overrideWith(_LivePrices.new),
      hyperliquidAccountProvider.overrideWith(_Account.new),
      swapOrdersProvider.overrideWith((_) => FakeSwapOrders()),
      hyperliquidAddressProvider.overrideWith((_) async => null),
      hyperliquidOrderbookProvider
          .overrideWith((_, __) => Stream.value(const HlOrderBookState())),
      aiEnabledProvider.overrideWith((_) async => false),
      currencyProvider.overrideWith((_) => _Currency()),
      runtimeCapabilitiesProvider.overrideWithValue(_Allowed()),
      usdBalanceProvider.overrideWith((_) => 0),
      hyperliquidMoveRailProvider.overrideWithValue(rail),
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

Future<void> _frames(WidgetTester tester, [int n = 10]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

AppButton _button(WidgetTester tester) =>
    tester.widget<AppButton>(find.byType(AppButton));

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(HlOrderSlipSheet)));

void main() {
  late FakeHyperliquidMoveRail rail;
  late List<(SlipVenue, double?, MoveSheetOrder)> sheets;
  late List<SensitiveIntent> approvals;
  late bool approve;
  late RuntimeCapabilitiesService policy;

  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    AffiliateService.debugSessionToken = 'test-session';
    // The geo and capability re-check at the confirm: allowed.
    policy = runtimePolicyFixture();
    RuntimeCapabilitiesService.debugInstance = policy;
    expect(await policy.refresh(), isTrue);
    FundedOrdersNotifier.persist = false;
    OrderFundingJourney.reset();
    rail = _Rail();
    _env = _Env();
    _funder = _Funder();
    sheets = [];
    approvals = [];
    approve = true;
    debugFreshSpendingBitcoin = () async => (sats: 1000000, usdPerBtc: 60000.0);
    debugBitcoinLegEstimate = (sats) async => sats / 1e8 * 60000 * 0.995;
    debugShowSlipMoveSheetWithOrder = (venue, target, order) async {
      sheets.add((venue, target, order));
    };
    // The ONE prompt, as the person answers it.
    debugHlOrderFundingApproval = (intent) async {
      approvals.add(intent);
      if (!approve) return null;
      return AuthGrantRegistry.instance.issueAutofire(
          kPendingHlOrderAutofireId, intent,
          method: AuthGrantMethod.biometric);
    };
  });

  tearDown(() {
    debugFreshSpendingBitcoin = null;
    debugBitcoinLegEstimate = null;
    debugShowSlipMoveSheetWithOrder = null;
    debugHlOrderFundingApproval = null;
    AuthGrantRegistry.instance.cancelAutofire(kPendingHlOrderAutofireId);
    RuntimeCapabilitiesService.debugInstance = null;
    policy.dispose();
    FundedOrdersNotifier.persist = true;
    AffiliateService.debugSessionToken = null;
    TrackingService.debugTrackObserver = null;
    rail.creditedController.close();
  });

  Future<void> release(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 15));
  }

  /// Nothing typed: "Add $X to Investments", tapped. Returns X and the
  /// order the Move sheet was opened with.
  Future<(double, MoveSheetOrder)> openSheet(WidgetTester tester) async {
    await _pumpSlip(tester, rail);
    final label = _button(tester).text;
    expect(label, startsWith(r'Add $'));
    expect(label, endsWith('to Investments'));
    final x = double.parse(label.split(' ')[1].substring(1));
    await tester.tap(find.byType(AppButton));
    await _frames(tester, 3);
    expect(sheets, hasLength(1));
    final (venue, target, order) = sheets.single;
    expect(venue, SlipVenue.investing);
    expect(target, closeTo(x, 0.001));
    expect(order.addUsd, closeTo(x, 0.001));
    expect(order.venue, OneBalanceVenue.investing);
    expect(order.orderUsd, greaterThan(0));
    // The sheet's review names it in one line.
    expect(order.followOn,
        'Then opens \$${order.orderUsd.toStringAsFixed(2)} Long BTC');
    // Nothing on the ticket changed: still nothing typed, nothing queued.
    expect(_button(tester).text, label);
    expect(_container(tester).read(pendingHyperliquidOrderProvider), isNull);
    return (x, order);
  }

  Future<MoveSheetOrderStart> confirm(
      WidgetTester tester, MoveSheetOrder order, MoveSheetLeg leg) async {
    MoveSheetOrderStart? answer;
    unawaited(order.start(leg).then((a) => answer = a));
    for (var i = 0; i < 60 && answer == null; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(answer, isNotNull);
    return answer!;
  }

  testWidgets(
      'confirming an add that covers it: back on the ticket, the minimum, '
      'the steps, and the order opened under ONE approval', (tester) async {
    final events = <(String, Map<String, Object?>?)>[];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    final (x, order) = await openSheet(tester);
    final sheet = _SheetLeg(x + 1);
    final answer = await confirm(tester, order, sheet.leg);
    expect(answer.status, MoveSheetOrderStatus.started,
        reason: answer.message);
    await _frames(tester, 3);

    // ONE approval, binding the order, its move and the sheet's leg.
    expect(approvals, hasLength(1));
    expect(approvals.single.action, SensitiveAction.hlOrder);
    expect(approvals.single.limits[VenueLimit.fundBtc],
        BitcoinLegGrants.limit(maxSats: 36000, ownSpark: _ownSpark));
    expect(sheet.asked, 1);
    expect(sheet.paid, [30000]);
    expect(_env.sends, 0);
    // The ticket took the order it was sized for.
    final pending = _container(tester).read(pendingHyperliquidOrderProvider)!;
    expect(pending.marginUsd, closeTo(order.orderUsd, 0.005));
    expect(pending.fundingSource, 'bitcoin');
    expect(_funder.sent, hasLength(1));

    // The steps under one busy button.
    final money = '\$${order.orderUsd.toStringAsFixed(2)}';
    expect(find.text('Adding \$${(x + 1).toStringAsFixed(2)} to Investments'),
        findsOneWidget);
    expect(find.text('Opening $money Long BTC'), findsOneWidget);
    expect(_button(tester).isLoading, isTrue);

    // The venue credits it and the autofire places it.
    final notifier =
        _container(tester).read(pendingHyperliquidOrderProvider.notifier);
    notifier.updateStatus(PendingHlOrderStatus.placing);
    await _frames(tester, 3);
    expect(_button(tester).text, 'Opening $money Long BTC');
    notifier.updateStatus(PendingHlOrderStatus.done);
    await _frames(tester, 3);
    final record = _container(tester).read(fundedOrdersProvider).single;
    expect(record.stage, FundedOrderStage.done);
    expect(approvals, hasLength(1), reason: 'never a second prompt');
    // The order's funding reports the Move sheet as its door.
    expect(
        events.any((e) =>
            e.$1 == 'order_funding_started' &&
            e.$2!['door'] == 'move_sheet' &&
            e.$2!['funding_source'] == 'bitcoin'),
        isTrue);
    await release(tester);
  });

  testWidgets(
      'closing the sheet without adding: no order, the ticket as it was',
      (tester) async {
    await openSheet(tester);
    await _frames(tester, 5);
    expect(_container(tester).read(pendingHyperliquidOrderProvider), isNull);
    expect(_container(tester).read(fundedOrdersProvider), isEmpty);
    expect(approvals, isEmpty);
    expect(_funder.sent, isEmpty);
    expect(_button(tester).text, endsWith('to Investments'));
    expect(_button(tester).onPressed, isNotNull);
    await release(tester);
  });

  testWidgets('a smaller add: nothing opened, "Tap to place" on the ticket',
      (tester) async {
    final (x, order) = await openSheet(tester);
    expect(order.coveredBy(x - 1), isFalse);
    order.addedOnly!(2);
    await _frames(tester, 3);
    expect(find.text(r'Your $2.00 is in Investments. Tap to place.'),
        findsOneWidget);
    expect(_container(tester).read(pendingHyperliquidOrderProvider), isNull);
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
    expect(answer.status, MoveSheetOrderStatus.declined,
        reason: answer.message);
    expect(approvals, hasLength(1));
    expect(sheet.asked, 0);
    expect(_env.sends, 0);
    expect(_funder.sent, isEmpty);
    expect(
        PendingHyperliquidOrderNotifier.isActive(
            _container(tester).read(pendingHyperliquidOrderProvider)),
        isFalse);
    expect(_container(tester).read(fundedOrdersProvider), isEmpty);
    await release(tester);
  });
}
