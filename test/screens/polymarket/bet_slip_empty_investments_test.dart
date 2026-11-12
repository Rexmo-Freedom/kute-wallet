// An empty Investments balance takes the same path as a partly funded one
// (founder, 15 October 2026: "we should never make it show up"): nothing
// typed on a hot bet slip whose Investments hold $0, with enough spending
// bitcoin, "Add $X · the order" is the bet itself at the market's
// minimum, funded in place under ONE approval with the steps on the slip.
// No deposit sheet is ever pushed, and the direct Bitcoin → Predictions
// leg is planned before the chain picks its route.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/helpers/root_navigator.dart';
import 'package:kute/screens/shared/money_steps_view.dart' show MoneyStepsView;
import 'package:kute/screens/shared/sal_sprite.dart' show SalSpriteCache;
import 'package:kute/screens/shared/sal_toast.dart' show SalToast;
import 'package:kute/screens/shared/standing_order_slips.dart'
    show StandingOrderSlips;
import 'package:kute/screens/shared/standing_order_toasts.dart'
    show StandingOrderToasts;
import 'package:kute/screens/shared/amount_keypad_panel.dart' show AmountKeypad;
import 'package:kute/screens/shared/rubber_band_progress.dart'
    show RubberBandProgress;
import 'package:kute/services/continuous_haptics.dart';
import 'package:kute/services/standing_orders/standing_order_store.dart';
import 'package:kute/services/standing_orders/standing_orders_provider.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/auth_grant_registry.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/pending_bet_autofire.dart'
    show kPendingBetAutofireId;
import 'package:kute/providers/pending_polymarket_bet_provider.dart';
import 'package:kute/providers/polymarket_bet_controller.dart';
import 'package:kute/providers/polymarket_browse_provider.dart'
    show polymarketEventDetailsProvider;
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_open_orders_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/spark_address_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider;
import 'package:kute/screens/home/components/deposit_sheet.dart'
    show DepositSheet;
import 'package:kute/screens/polymarket/components/bet_slip_sheet.dart';
import 'package:kute/screens/polymarket/components/slip_chrome.dart';
import 'package:kute/screens/shared/slip_shortfall.dart';
import 'package:kute/services/funding/settlement_runner.dart'
    show SettlementStepUpHook;
import 'package:kute/services/one_balance/bitcoin_funded_order.dart';
import 'package:kute/services/one_balance/empty_slip_sources.dart';
import 'package:kute/services/one_balance/bitcoin_to_dollars_leg.dart';
import 'package:kute/services/one_balance/bitcoin_to_venue_leg.dart';
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/services/one_balance/one_balance_state.dart'
    show OneBalanceVenue;
import 'package:kute/services/one_balance/order_funding.dart';
import 'package:kute/services/one_balance/predictions_venue_funder.dart';
import 'package:kute/services/one_balance/venue_cash_source.dart';
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/polymarket/polymarket_fee_terms.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart' show AppColors;
import 'package:money2/money2.dart';

import '../../helpers/fake_swap_orders.dart';
import '../../helpers/runtime_policy_fixture.dart';
import '../../helpers/shell_bar_harness.dart';
import '../../helpers/render_png.dart';
import '../../services/standing_orders/fake_secret_store.dart';

const _ownSpark =
    'spark1pgss93sy072yrmtad5cy2srwjhq8ekzuw78yhr808jn6htqfh9w8p8h9mfwlv9';
const _pmDeposit = '0x1111111111111111111111111111111111111111';

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

/// Predictions hold nothing.
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
  Future<PendingBetIntent> prepareIntent(PendingBetIntent intent,
          {bool requireFreshCollateral = false}) async =>
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

/// The wallet behind the slip's own runner: the direct leg is planned on
/// the own Predictions deposit the approval bound (and found costlier
/// here), then the via-Dollars leg goes and its dollars land at once.
class _Env {
  var sends = 0;
  var directSends = 0;
  final planned = <(OneBalanceVenue, String)>[];

  BitcoinLegEnv get env => BitcoinLegEnv(
        ownSpark: () async => _ownSpark,
        send: ({
          required String sparkAddress,
          required BitcoinLegPlan plan,
          required SettlementStepUpHook stepUp,
          required void Function() onSending,
        }) async {
          sends++;
          onSending();
          return BitcoinLegTicket(
              quoteId: 'q_btc',
              sats: plan.sats,
              estimatedOutUsd: plan.targetUsd,
              minOutUsd: plan.targetUsd);
        },
        watcher: ({required DateTime since}) => _Landed(),
        dollarsNow: () => 0,
        freshDollars: () async => 0,
        planDirect: ({
          required OneBalanceVenue venue,
          required double fundUsd,
          required double addUsd,
          required double dollarsUsd,
          required BitcoinLegPlan via,
          required String ownVenue,
          required int directMaxSats,
        }) async {
          planned.add((venue, ownVenue));
          return const DirectBitcoinPlan.viaDollars(
              DirectBitcoinReason.costlier);
        },
        sendDirect: ({
          required OneBalanceVenue venue,
          required String ownVenue,
          required String ownSpark,
          required int sats,
          required double targetUsd,
          required SettlementStepUpHook stepUp,
          required void Function() onSending,
        }) async {
          directSends++;
          throw StateError('the direct leg was not chosen');
        },
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

const _outcomes = [
  PolymarketOutcome(name: 'Yes', price: 0.5, tokenId: 'yes-token'),
  PolymarketOutcome(name: 'No', price: 0.5, tokenId: 'no-token'),
];

late _Env _env;
late _Funder _funder;

class _StoredFunded extends FundedOrdersNotifier {
  _StoredFunded(this.records);
  final List<FundedOrderRecord> records;
  @override
  List<FundedOrderRecord> build() => records;
}

/// On demand: the locked slip saying OK and Sal's placing toast written
/// as PNGs, light and dark (`--dart-define=OK_TOAST_RENDER_OUT=<dir>`).
const _renderOut = String.fromEnvironment('OK_TOAST_RENDER_OUT');
final _shot = GlobalKey();

/// The market the standing orders are on, as Gamma reads it by its slug.
const _eventSlug = 'will-it-rain';
const _event = PolymarketEvent(
  id: 'e-rain',
  slug: _eventSlug,
  title: 'Will it rain?',
  volume: 1000,
  liquidity: 1000,
  category: 'other',
  conditionId: 'c-rain',
  outcomes: _outcomes,
);

Future<void> _pumpSlip(WidgetTester tester,
    {bool knownEmpty = false,
    List<FundedOrderRecord>? funded,
    StandingOrderStore? standingStore,
    bool dark = false}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  installShellBar();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      if (funded != null)
        fundedOrdersProvider.overrideWith(() => _StoredFunded(funded)),
      slipKnownEmptySourcesProvider.overrideWith((_) => () async => knownEmpty),
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
      // $0 in Investments: no Dollars, no venue cash anywhere.
      usdBalanceProvider.overrideWithValue(0),
      polymarketFeeTermsProvider
          .overrideWith((ref, _) async => PolymarketFeeTerms.worstCase),
      polymarketBetControllerProvider.overrideWith(_Controller.new),
      polymarketMarketWindowReaderProvider.overrideWithValue((_) async => null),
      sparkSelfAddressProvider.overrideWith((_) async => _ownSpark),
      venueCashPullerProvider.overrideWith((_) => VenueCashPuller(
          sources: const [], readDollars: () => 0, minimumUsd: (_) async => 1)),
      bitcoinLegEnvProvider.overrideWith((_) => _env.env),
      orderFundingControllerProvider.overrideWithValue(OrderFundingController(
          funderFor: (_) => _funder, dollarsUsd: () => 0)),
      if (standingStore != null)
        standingOrderStoreProvider.overrideWithValue(standingStore),
      polymarketEventDetailsProvider.overrideWith(
          (ref, slug) async => slug == _eventSlug ? _event : null),
    ],
    // The bar over the slip is the slip's button (shell_bar_harness.dart).
    child: standingStore != null
        ? _sheetApp(dark: dark)
        : shellBarApp(
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
  ));
  await _frames(tester);
  if (standingStore != null) {
    // The slip as the app opens it: a modal sheet over a page, the bar
    // its button, Sal's toasts on the root overlay.
    await tester.tap(find.byKey(const ValueKey('open-slip')));
    await _frames(tester);
  }
}

/// The app with the slip opened as the bottom modal sheet it is (tap
/// outside to leave, no drag), on the root navigator.
Widget _sheetApp({bool dark = false}) => shellBarApp(
      navigatorKey: kuteRootNavigatorKey,
      dark: dark,
      wrap: (_, child) => RepaintBoundary(key: _shot, child: child),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              key: const ValueKey('open-slip'),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                isDismissible: true,
                enableDrag: false,
                backgroundColor: Colors.transparent,
                builder: (_) => const BetSlipSheet(
                    marketQuestion: 'Will it rain?',
                    outcomes: _outcomes,
                    initialAmountUsd: null),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

/// The standing orders' store without disk: the records in memory, the
/// secrets in [FakeSecretStore].
class _MemoryStandingStore extends StandingOrderStore {
  _MemoryStandingStore() : super(secrets: FakeSecretStore());
  final Map<String, StandingOrder> rows = {};
  @override
  Future<List<StandingOrder>> load(String walletId) async =>
      [for (final o in rows.values) if (o.walletId == walletId) o];
  @override
  Future<void> save(StandingOrder order) async => rows[order.id] = order;
  @override
  Future<void> remove(StandingOrder order) async => rows.remove(order.id);
}

/// The open standing order the accept made, as the provider holds it.
StandingOrder _standing(
    {StandingOrderState state = StandingOrderState.funding,
    String token = 'yes-token',
    String side = 'Yes',
    double? movedToPrice}) {
  final at = DateTime.now();
  return StandingOrder(
    id: 'so_test',
    walletId: 'w',
    venue: StandingOrderVenue.predictions,
    marketKey: token,
    marketTitle: 'Will it rain?',
    sideLabel: side,
    eventSlug: _eventSlug,
    movedToPrice: movedToPrice,
    isBuy: true,
    size: 2,
    approvedPrice: 0.5,
    amountUsd: 1,
    orderKind: 'market',
    state: state,
    createdAt: at,
    updatedAt: at,
  );
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

/// The door is the bar's button (the slip declares it through the keyed
/// PolySlipCta): a tap on the door is a tap on the bar.
Future<void> _tapDoor(WidgetTester tester) async {
  expect(_door, findsOneWidget);
  expect(barPrimaryLabel(tester), _cta(tester).label);
  await tapBarPrimary(tester, settle: false);
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(BetSlipSheet)));

void main() {
  late RuntimeCapabilitiesService policy;
  late List<SensitiveIntent> approvals;
  late List<String> sheets;
  late List<String> events;

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
    approvals = [];
    sheets = [];
    events = [];
    TrackingService.debugTrackObserver = (e, _) => events.add(e);
    // The spending bitcoin covers X.
    debugFreshSpendingBitcoin = () async => (sats: 1000000, usdPerBtc: 60000.0);
    debugBitcoinLegEstimate = (sats) async => sats / 1e8 * 60000 * 0.995;
    // The own Predictions deposit the approval binds the direct leg to.
    debugOwnVenueDeposit = (_) async => _pmDeposit;
    // Any sheet the slip might open, recorded: none must open.
    debugShowSlipTopUpSheet = (venue, _) async => sheets.add('top_up');
    debugShowSlipReceiveSheet = (venue, _) async => sheets.add('receive');
    debugShowEmptySlipDepositSheet =
        (venue, _) async => sheets.add('deposit:$venue');
    // The ONE prompt, approved.
    debugPmBetFundingApproval = (intent) async {
      approvals.add(intent);
      return AuthGrantRegistry.instance.issueAutofire(
          kPendingBetAutofireId, intent,
          method: AuthGrantMethod.biometric);
    };
  });

  tearDown(() {
    PredictionsVenueFunder.debugRouteShare = null;
    debugFreshSpendingBitcoin = null;
    debugBitcoinLegEstimate = null;
    debugOwnVenueDeposit = null;
    debugShowSlipTopUpSheet = null;
    debugShowSlipReceiveSheet = null;
    debugShowEmptySlipDepositSheet = null;
    debugPmBetFundingApproval = null;
    TrackingService.debugTrackObserver = null;
    AuthGrantRegistry.instance.cancelAutofire(kPendingBetAutofireId);
    FundedOrdersNotifier.persist = true;
    RuntimeCapabilitiesService.debugInstance = null;
    AffiliateService.debugSessionToken = null;
  });

  Future<void> release(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    policy.dispose();
    // Past the autofire grant's own 30-minute life.
    await tester.pump(const Duration(minutes: 31));
  }

  testWidgets('an old ready record adds no message above the bet button',
      (tester) async {
    expect(await policy.refresh(), isTrue);
    final now = DateTime.now();
    await _pumpSlip(tester, funded: [
      FundedOrderRecord(
        id: 'old-ready',
        label: const FundedOrderLabel(
            venue: OneBalanceVenue.predictions,
            orderUsd: 5,
            side: 'Yes',
            market: 'Will it rain?',
            marketKey: 'yes-token'),
        stage: FundedOrderStage.ready,
        createdAt: now,
        updatedAt: now,
        addUsd: 6,
      )
    ]);
    expect(find.byType(SlipFundingReadyNote), findsNothing);
    expect(find.textContaining('Tap to place'), findsNothing);
    // Nothing typed: the bet's short name; the tap tops up first.
    expect(_cta(tester).label, 'Place minimum on Yes');
    expect(_cta(tester).enabled, isTrue);
    await release(tester);
  });

  testWidgets(
      'nothing typed, \$0 in Investments, enough bitcoin: "Add" funds the '
      'minimum bet in place under ONE approval, no sheet', (tester) async {
    expect(await policy.refresh(), isTrue);
    await _pumpSlip(tester);
    expect(_door, findsOneWidget);
    // Nothing typed: the bet's short name; the tap adds, then places.
    expect(_cta(tester).label, 'Place minimum on Yes');

    await _tapDoor(tester);
    await _frames(tester, 10);

    // No sheet of any kind: the slip is still the only screen.
    expect(sheets, isEmpty);
    expect(find.byType(DepositSheet), findsNothing);
    expect(events, isNot(contains('slip_top_up_opened')));

    // ONE approval, binding the bet, its move and the Bitcoin leg.
    expect(approvals, hasLength(1));
    expect(approvals.single.action, SensitiveAction.pmBet);
    expect(approvals.single.limits[VenueLimit.fundBtc], isNotNull);
    // The direct Bitcoin → Predictions leg was planned on the own deposit
    // that approval bound, before the route was picked.
    expect(_env.planned, [(OneBalanceVenue.predictions, _pmDeposit)]);
    // Costlier here: the via-Dollars leg went, once; the move followed.
    expect(_env.directSends, 0);
    expect(_env.sends, 1);
    expect(_funder.sent, hasLength(1));

    // The slip took the bet it was sized for: the market's minimum.
    final pending = _container(tester).read(pendingPolymarketBetProvider)!;
    expect(pending.amount, greaterThan(0));
    expect(pending.status, PendingBetStatus.awaitingBalance);

    // The steps, on the slip, under one busy button (the bar, spinning)
    // that says OK and only closes the slip (founder, 10 November 2026,
    // on 2.2.0 (99)).
    expect(
        find.byKey(const ValueKey('bet-slip-funded-progress')), findsOneWidget);
    expect(_cta(tester).isBusy, isTrue);
    expect(barPrimaryBusy(tester), isTrue);
    expect(barPrimaryLabel(tester), 'OK');
    final money = '\$${pending.amount.toStringAsFixed(2)}';
    expect(find.text('Placing $money on Yes'), findsOneWidget);

    // The venue credits it and the autofire places it: never a second
    // prompt.
    final notifier =
        _container(tester).read(pendingPolymarketBetProvider.notifier);
    notifier.updateStatus(PendingBetStatus.placing);
    await _frames(tester, 3);
    notifier.updateStatus(PendingBetStatus.done);
    await _frames(tester, 3);
    final record = _container(tester).read(fundedOrdersProvider).single;
    expect(record.stage, FundedOrderStage.done);
    expect(record.label.orderUsd, pending.amount);
    expect(approvals, hasLength(1));
    await release(tester);
  });
  testWidgets(
      'known zero across all sources opens Predictions deposit and preserves slip',
      (tester) async {
    expect(await policy.refresh(), isTrue);
    debugFreshSpendingBitcoin = () async => (sats: 0, usdPerBtc: 60000.0);
    await _pumpSlip(tester, knownEmpty: true);
    await _tapDoor(tester);
    await _frames(tester, 20);
    expect(sheets, ['deposit:SlipVenue.predictions']);
    expect(find.byType(BetSlipSheet), findsOneWidget);
    expect(approvals, isEmpty);
    expect(_env.sends, 0);
    await release(tester);
  });
  testWidgets('unknown sources never open Predictions contextual deposit',
      (tester) async {
    expect(await policy.refresh(), isTrue);
    debugFreshSpendingBitcoin = () async => (sats: 0, usdPerBtc: 60000.0);
    await _pumpSlip(tester);
    await _tapDoor(tester);
    await _frames(tester, 20);
    expect(sheets, ['receive']);
    expect(approvals, isEmpty);
    await release(tester);
  });

  group('the accepted bet as a standing order', () {
    StandingOrderStore store(String box) => _MemoryStandingStore();

    /// Opens the slip, accepts the minimum funded from bitcoin, and gives
    /// the provider the standing order the accept made.
    Future<ProviderContainer> accept(WidgetTester tester, String box) async {
      expect(await policy.refresh(), isTrue);
      await _pumpSlip(tester, standingStore: store(box));
      await _tapDoor(tester);
      await _frames(tester, 10);
      final c = _container(tester);
      c.read(standingOrdersProvider.notifier).debugReplace([_standing()]);
      await _frames(tester, 2);
      return c;
    }

    testWidgets(
        'the slip stays up, locked as before: the steps, Sal\'s busy button '
        'saying OK the whole way, no "you can leave" line and no toast',
        (tester) async {
      await accept(tester, 'standing_slip_locked');
      // The old locked slip: the keypad folded, the steps in its place.
      expect(find.byType(BetSlipSheet), findsOneWidget);
      expect(find.byKey(const ValueKey('bet-slip-funded-progress')),
          findsOneWidget);
      expect(find.text(r'Placing $1.00 on Yes'), findsOneWidget);
      expect(find.textContaining('You can leave'), findsNothing);
      // The bar's busy button (Sal working on it) is OK, never Cancel.
      expect(
          find.byKey(const ValueKey('bet-slip-standing-ok')), findsOneWidget);
      expect(barPrimaryBusy(tester), isTrue);
      expect(barPrimaryLabel(tester), 'OK');
      expect(barPrimaryEnabled(tester), isTrue);
      expect(find.text('Cancel'), findsNothing);
      // No toast while the slip says it all.
      expect(find.byKey(const ValueKey('sal-toast')), findsNothing);
      // Posted, past the point a cancel could stop it: still OK.
      _container(tester)
          .read(standingOrdersProvider.notifier)
          .debugReplace([_standing(state: StandingOrderState.posting)]);
      await _frames(tester, 2);
      expect(
          find.byKey(const ValueKey('bet-slip-standing-ok')), findsOneWidget);
      expect(barPrimaryLabel(tester), 'OK');
      // Its result known: OK gives way to the slip's own end.
      _container(tester)
          .read(standingOrdersProvider.notifier)
          .debugReplace([_standing(state: StandingOrderState.filled)]);
      await _frames(tester, 2);
      expect(find.byKey(const ValueKey('bet-slip-standing-ok')), findsNothing);
      expect(barPrimaryLabel(tester), isNot('OK'));
      SalToast.debugReset();
      await release(tester);
    });

    testWidgets(
        'leaving never cancels: the haptics stop at once, the order goes on, '
        'and Sal says "Placing your prediction" at the top: no spinner, no '
        'Cancel, closable', (tester) async {
      final c = await accept(tester, 'standing_slip_leave');
      final before = c.read(pendingPolymarketBetProvider)!;
      // Leave it: a tap above the sheet, as when it is idle (its X and
      // back go the same way, through the same lock).
      await tester.tapAt(const Offset(195, 40));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(find.byType(BetSlipSheet), findsOneWidget,
          reason: 'still on its way out');
      // At once, while the sheet is still on its way out: nothing of the
      // slip plays a haptic any more.
      expect(
          tester
              .widget<RubberBandProgress>(
                  find.byKey(const ValueKey('bet-slip-funded-progress')))
              .haptic,
          isFalse);
      for (final steps
          in tester.widgetList<MoneyStepsView>(find.byType(MoneyStepsView))) {
        expect(steps.haptics, isFalse);
      }
      expect(ContinuousHaptics.isRunning(), isFalse);
      await _frames(tester, 10);
      expect(find.byType(BetSlipSheet), findsNothing);
      // The order goes on: nothing cancelled, the bet still queued.
      expect(c.read(standingOrdersProvider).single.state,
          StandingOrderState.funding);
      final after = c.read(pendingPolymarketBetProvider);
      expect(after, isNotNull);
      expect(after!.status, before.status);
      expect(events, isNot(contains('standing_order_cancelled')));
      // Sal at the top: the words and the market, nothing thinking, no
      // Cancel; the X closes it.
      expect(find.byKey(const ValueKey('sal-toast')), findsOneWidget);
      expect(find.text('Placing your prediction'), findsOneWidget);
      expect(find.text('Will it rain?'), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byKey(const ValueKey('sal-toast-mark')), findsNothing);
      expect(find.byKey(const ValueKey('sal-toast-action')), findsNothing);
      expect(find.text('Cancel'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('sal-toast-close')));
      await _frames(tester, 6);
      expect(find.byKey(const ValueKey('sal-toast')), findsNothing);
      // Closed, the order still goes on.
      expect(c.read(standingOrdersProvider).single.state,
          StandingOrderState.funding);
      expect(events, isNot(contains('standing_order_cancelled')));
      SalToast.debugReset();
      StandingOrderToasts.debugReset();
      await release(tester);
    });

    for (final dark in [false, true]) {
      final mode = dark ? 'dark' : 'light';
      testWidgets('render: the locked slip saying OK, then the placing toast '
          '($mode)', (tester) async {
        await tester.runAsync(loadRenderFonts);
        expect(await policy.refresh(), isTrue);
        await _pumpSlip(tester,
            standingStore: store('standing_slip_render'), dark: dark);
        await _tapDoor(tester);
        await _frames(tester, 10);
        _container(tester)
            .read(standingOrdersProvider.notifier)
            .debugReplace([_standing()]);
        await _frames(tester, 6);
        await writeRenderPng(
            tester, _shot, '$_renderOut/slip_ok_prediction_$mode.png');
        // Sal's sheets are not read in the test's fake time: the rig draws
        // him in the toast, as where the sheets cannot be read.
        SalSpriteCache.debugSetManifest(null);
        addTearDown(SalSpriteCache.debugReset);
        await tapBarPrimary(tester, settle: false);
        await _frames(tester, 10);
        expect(find.text('Placing your prediction'), findsOneWidget);
        await writeRenderPng(
            tester, _shot, '$_renderOut/toast_placing_prediction_$mode.png');
        SalToast.debugReset();
        StandingOrderToasts.debugReset();
        await release(tester);
      }, skip: _renderOut.isEmpty);
    }

    testWidgets(
        'OK on Sal\'s button closes the slip exactly as leaving does: the '
        'order goes on, nothing cancelled, the placing toast at the top',
        (tester) async {
      final c = await accept(tester, 'standing_slip_ok');
      await tapBarPrimary(tester, settle: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      // The haptics stop at once.
      expect(ContinuousHaptics.isRunning(), isFalse);
      await _frames(tester, 10);
      expect(find.byType(BetSlipSheet), findsNothing);
      expect(c.read(standingOrdersProvider).single.state,
          StandingOrderState.funding);
      expect(c.read(pendingPolymarketBetProvider), isNotNull);
      expect(events, isNot(contains('standing_order_cancelled')));
      expect(find.text('Placing your prediction'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byKey(const ValueKey('sal-toast-action')), findsNothing);
      SalToast.debugReset();
      StandingOrderToasts.debugReset();
      await release(tester);
    });

    testWidgets(
        'a tap on the placing toast opens the same slip again, locked on its '
        'order as it was left (green, the steps, the OK, its haptics running '
        'again), never a journey sheet or a Cancel; leaving stops the '
        'haptics again; it goes once its order is placed', (tester) async {
      final c = await accept(tester, 'standing_slip_reopen');
      final sheetsBefore = events.where((e) => e == 'polymarket_bet_slip_opened').length;
      await tapBarPrimary(tester, settle: false);
      await _frames(tester, 10);
      expect(find.byType(BetSlipSheet), findsNothing);
      expect(find.text('Placing your prediction'), findsOneWidget);
      // The toast's tap (not its X).
      await tester.tap(find.text('Placing your prediction'));
      await _frames(tester, 10);
      expect(find.byType(BetSlipSheet), findsOneWidget);
      expect(find.text('Cancel'), findsNothing);
      // The haptics run again, exactly as on the slip after its accept:
      // the band's pull and the steps' taps.
      expect(
          tester
              .widget<RubberBandProgress>(
                  find.byKey(const ValueKey('bet-slip-funded-progress')))
              .haptic,
          isTrue);
      for (final steps
          in tester.widgetList<MoneyStepsView>(find.byType(MoneyStepsView))) {
        expect(steps.haptics, isTrue);
      }
      expect(ContinuousHaptics.isRunning(), isTrue);
      // Green: the side's colour, as the slip colours a Yes.
      expect(
          tester
              .widget<PolySlipCta>(
                  find.byKey(const ValueKey('bet-slip-standing-ok')))
              .color,
          AppColors.marketUp);
      // The toast is gone while the slip is up.
      expect(find.byKey(const ValueKey('sal-toast')), findsNothing);
      // Locked as before: the keypad folded, the steps, Sal's busy OK.
      expect(find.byKey(const ValueKey('bet-slip-funded-progress')),
          findsOneWidget);
      expect(find.text(r'Placing $1.00 on Yes'), findsOneWidget);
      expect(
          find.byKey(const ValueKey('bet-slip-standing-ok')), findsOneWidget);
      expect(barPrimaryLabel(tester), 'OK');
      expect(barPrimaryBusy(tester), isTrue);
      // Bound to the same order, no new slip counted.
      expect(tester.widget<BetSlipSheet>(find.byType(BetSlipSheet))
          .standingEndedBefore, isEmpty);
      expect(events.where((e) => e == 'polymarket_bet_slip_opened').length,
          sheetsBefore);
      // OK leaves it again: the haptics stop at once, the placing toast
      // comes back, one.
      await tapBarPrimary(tester, settle: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(ContinuousHaptics.isRunning(), isFalse);
      await _frames(tester, 10);
      expect(find.byType(BetSlipSheet), findsNothing);
      expect(find.byType(SalToast), findsOneWidget);
      expect(find.text('Placing your prediction'), findsOneWidget);
      // Open again, then its order fills: the slip goes, Sal says it.
      await tester.tap(find.text('Placing your prediction'));
      await _frames(tester, 10);
      expect(find.byType(BetSlipSheet), findsOneWidget);
      c
          .read(standingOrdersProvider.notifier)
          .debugReplace([_standing(state: StandingOrderState.filled)]);
      await _frames(tester, 10);
      expect(find.byType(BetSlipSheet), findsNothing);
      expect(find.text('Placing your prediction'), findsNothing);
      expect(c.read(standingOrdersProvider).single.state,
          StandingOrderState.filled);
      expect(events, isNot(contains('standing_order_cancelled')));
      SalToast.debugReset();
      StandingOrderToasts.debugReset();
      await release(tester);
    });

    /// What a tap on the order opens, from anywhere (the toast, the
    /// Overview's card, the Activity row): the one way back.
    Future<void> reopen(WidgetTester tester) async {
      unawaited(StandingOrderSlips.reopen(
          tester.element(find.byKey(const ValueKey('open-slip'))),
          id: 'so_test'));
      await _frames(tester, 10);
    }

    testWidgets(
        'a fresh app (nothing handed over, the order accepted before a '
        'restart): the slip is rebuilt from the order\'s record, the market '
        'read again by its slug: locked on it, green, the steps, OK, the '
        'haptics running; leaving stops them', (tester) async {
      final c = await accept(tester, 'standing_slip_fresh');
      await tapBarPrimary(tester, settle: false);
      await _frames(tester, 10);
      expect(find.byType(BetSlipSheet), findsNothing);
      expect(ContinuousHaptics.isRunning(), isFalse);
      // The app restarted: no slip kept, the toast gone.
      StandingOrderSlips.debugReset();
      SalToast.debugReset();
      StandingOrderToasts.debugReset();
      await _frames(tester, 4);
      final opened =
          events.where((e) => e == 'polymarket_bet_slip_opened').length;
      await reopen(tester);
      expect(find.byType(BetSlipSheet), findsOneWidget);
      final slip = tester.widget<BetSlipSheet>(find.byType(BetSlipSheet));
      // Rebuilt (not the slip that was left): the market as Gamma lists
      // it, the side the order bought, its stake.
      expect(slip.event, same(_event));
      expect(slip.source, 'standing_order');
      expect(slip.outcomes, _event.outcomes);
      expect(slip.initialOutcomeIndex, 0);
      expect(slip.initialAmountUsd, 1);
      expect(slip.standingEndedBefore, isEmpty);
      expect(find.text('Cancel'), findsNothing);
      expect(find.byKey(const ValueKey('bet-slip-funded-progress')),
          findsOneWidget);
      expect(find.text(r'Placing $1.00 on Yes'), findsOneWidget);
      expect(
          find.byKey(const ValueKey('bet-slip-standing-ok')), findsOneWidget);
      expect(barPrimaryLabel(tester), 'OK');
      expect(
          tester
              .widget<PolySlipCta>(
                  find.byKey(const ValueKey('bet-slip-standing-ok')))
              .color,
          AppColors.marketUp);
      expect(ContinuousHaptics.isRunning(), isTrue);
      // Nothing new counted: it is the same slip.
      expect(events.where((e) => e == 'polymarket_bet_slip_opened').length,
          opened);
      // A second tap while it is up opens nothing over it.
      await reopen(tester);
      expect(find.byType(BetSlipSheet), findsOneWidget);
      // OK leaves it: the haptics stop, the order goes on.
      await tapBarPrimary(tester, settle: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(ContinuousHaptics.isRunning(), isFalse);
      await _frames(tester, 10);
      expect(find.byType(BetSlipSheet), findsNothing);
      expect(c.read(standingOrdersProvider).single.state,
          StandingOrderState.funding);
      expect(events, isNot(contains('standing_order_cancelled')));
      SalToast.debugReset();
      StandingOrderToasts.debugReset();
      StandingOrderSlips.debugReset();
      await release(tester);
    });

    testWidgets(
        'a No rebuilt from its record is red: the side the order bought on '
        'its market, locked, OK, no Cancel', (tester) async {
      expect(await policy.refresh(), isTrue);
      await _pumpSlip(tester, standingStore: store('standing_slip_no'));
      // The slip the test opened is put away: only the order is left.
      Navigator.of(tester.element(find.byType(BetSlipSheet))).pop();
      await _frames(tester, 6);
      final c = ProviderScope.containerOf(
          tester.element(find.byKey(const ValueKey('open-slip'))));
      c.read(standingOrdersProvider.notifier).debugReplace(
          [_standing(state: StandingOrderState.posting, token: 'no-token',
              side: 'No')]);
      await _frames(tester, 2);
      await reopen(tester);
      final slip = tester.widget<BetSlipSheet>(find.byType(BetSlipSheet));
      expect(slip.initialOutcomeIndex, 1);
      expect(slip.standingEndedBefore, isEmpty);
      expect(barPrimaryLabel(tester), 'OK');
      expect(barPrimaryBusy(tester), isTrue);
      expect(find.text('Cancel'), findsNothing);
      expect(
          tester
              .widget<PolySlipCta>(
                  find.byKey(const ValueKey('bet-slip-standing-ok')))
              .color,
          AppColors.marketDown);
      StandingOrderSlips.debugReset();
      await release(tester);
    });

    // Founder, 12 November 2026, on 2.2.0 (110): a funded bet on a live
    // game, its money moved, showed the slip with the keypad, the amount,
    // "Payout if you win $4.83" (the stake) and an OK: "got stuck here at
    // placing".
    testWidgets(
        'locked on its order with no money journey to show: the keypad '
        'folded, the order\'s figure paying its own shares, the placing '
        'line, OK; never the amount editor', (tester) async {
      expect(await policy.refresh(), isTrue);
      await _pumpSlip(tester, standingStore: store('standing_slip_no_journey'));
      Navigator.of(tester.element(find.byType(BetSlipSheet))).pop();
      await _frames(tester, 6);
      final c = ProviderScope.containerOf(
          tester.element(find.byKey(const ValueKey('open-slip'))));
      // $1 at 50c: its signed order buys 2 shares, $2 if it wins.
      c
          .read(standingOrdersProvider.notifier)
          .debugReplace([_standing(state: StandingOrderState.posting)]);
      await _frames(tester, 2);
      await reopen(tester);
      expect(find.byType(BetSlipSheet), findsOneWidget);
      expect(find.byType(AmountKeypad), findsNothing);
      expect(find.byKey(const ValueKey('bet-slip-payout-tile')), findsNothing);
      expect(find.byKey(const ValueKey('slip-order-figure')), findsOneWidget);
      expect(find.text(r'Yes · pays $2.00 if you win'), findsOneWidget);
      expect(find.byKey(const ValueKey('bet-slip-standing-placing')),
          findsOneWidget);
      expect(find.text(r'Placing $1.00 on Yes'), findsOneWidget);
      expect(find.textContaining('Minimum'), findsNothing);
      expect(barPrimaryLabel(tester), 'OK');
      expect(barPrimaryBusy(tester), isTrue);
      // Filled for more shares than it signed for (a better price): the
      // figure is what it bought.
      c.read(standingOrdersProvider.notifier).debugReplace([
        _standing(state: StandingOrderState.posted)
            .copyWith(filledSize: 2.4)
      ]);
      await _frames(tester, 2);
      expect(find.text(r'Yes · pays $2.40 if you win'), findsOneWidget);
      StandingOrderSlips.debugReset();
      await release(tester);
    });

    testWidgets(
        'a reopened slip goes on every end with nothing on it to show: not '
        'placed, cancelled, the price past the approval, its record gone; '
        'never left saying "Placing"', (tester) async {
      expect(await policy.refresh(), isTrue);
      await _pumpSlip(tester, standingStore: store('standing_slip_ends'));
      Navigator.of(tester.element(find.byType(BetSlipSheet))).pop();
      await _frames(tester, 6);
      final c = ProviderScope.containerOf(
          tester.element(find.byKey(const ValueKey('open-slip'))));
      final standing = c.read(standingOrdersProvider.notifier);
      for (final end in <List<StandingOrder>>[
        [_standing(state: StandingOrderState.failed)],
        [_standing(state: StandingOrderState.cancelled)],
        [_standing(state: StandingOrderState.needsApproval)],
        const [],
      ]) {
        standing.debugReplace([_standing(state: StandingOrderState.posted)]);
        await _frames(tester, 2);
        await reopen(tester);
        expect(find.byType(BetSlipSheet), findsOneWidget);
        expect(barPrimaryLabel(tester), 'OK');
        standing.debugReplace(end);
        await _frames(tester, 10);
        expect(find.byType(BetSlipSheet), findsNothing,
            reason: '${end.map((o) => o.state)}');
      }
      StandingOrderSlips.debugReset();
      await release(tester);
    });

    testWidgets(
        'the price moved past the approval: a tap on the order is the '
        'approval, the slip at the new price, unlocked, its own Confirm; '
        'the standing order ends there, quietly', (tester) async {
      expect(await policy.refresh(), isTrue);
      await _pumpSlip(tester, standingStore: store('standing_slip_moved'));
      Navigator.of(tester.element(find.byType(BetSlipSheet))).pop();
      await _frames(tester, 6);
      final c = ProviderScope.containerOf(
          tester.element(find.byKey(const ValueKey('open-slip'))));
      c.read(standingOrdersProvider.notifier).debugReplace([
        _standing(
            state: StandingOrderState.needsApproval, movedToPrice: 0.6)
      ]);
      await _frames(tester, 2);
      await reopen(tester);
      expect(find.byType(BetSlipSheet), findsOneWidget);
      final slip = tester.widget<BetSlipSheet>(find.byType(BetSlipSheet));
      expect(slip.standingEndedBefore, isNull);
      expect(slip.initialAmountUsd, 1);
      expect(find.byKey(const ValueKey('bet-slip-standing-ok')), findsNothing);
      expect(find.text('Cancel'), findsNothing);
      final order = c.read(standingOrdersProvider).single;
      expect(order.state, StandingOrderState.failed);
      expect(order.failureCode, 'price_moved');
      StandingOrderSlips.debugReset();
      await release(tester);
    });
  });
}
