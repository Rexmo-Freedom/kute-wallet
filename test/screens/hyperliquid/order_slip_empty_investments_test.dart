// An empty Investments balance takes the same path as a partly funded one
// (founder, 15 October 2026): nothing typed on a hot Investing ticket
// whose Investments hold $0, with enough spending bitcoin, "Add $X to
// Investments" is the order itself at the market's minimum, funded in
// place under ONE approval with the steps on the ticket. No deposit sheet
// is ever pushed, and the direct Bitcoin → Investing leg is planned
// before the chain picks its route. The bet slip does the same
// (bet_slip_empty_investments_test).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/services/standing_orders/standing_orders_provider.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/auth_grant_registry.dart';
import 'package:kute/helpers/root_navigator.dart' show kuteRootNavigatorKey;
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/settings_model.dart';
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
import 'package:kute/screens/home/components/deposit_sheet.dart'
    show DepositSheet;
import 'package:kute/screens/hyperliquid/components/order_slip_sheet.dart';
import 'package:kute/screens/shared/amount_keypad_panel.dart';
import 'package:kute/screens/shared/sal_sprite.dart' show SalSpriteCache;
import 'package:kute/screens/shared/sal_toast.dart' show SalToast;
import 'package:kute/screens/shared/rubber_band_progress.dart'
    show RubberBandProgress;
import 'package:kute/screens/shared/standing_order_slips.dart'
    show StandingOrderSlips;
import 'package:kute/services/continuous_haptics.dart';
import 'package:kute/screens/shared/standing_order_toasts.dart'
    show StandingOrderToasts;
import 'package:kute/screens/shared/slip_shortfall.dart';
import 'package:kute/services/funding/settlement_runner.dart'
    show SettlementStepUpHook;
import 'package:kute/services/one_balance/bitcoin_funded_order.dart';
import 'package:kute/services/one_balance/empty_slip_sources.dart';
import 'package:kute/services/one_balance/bitcoin_to_dollars_leg.dart';
import 'package:kute/services/one_balance/bitcoin_to_venue_leg.dart';
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/services/one_balance/hyperliquid_move_rail.dart';
import 'package:kute/services/one_balance/one_balance_state.dart'
    show OneBalanceVenue;
import 'package:kute/services/one_balance/order_funding.dart';
import 'package:kute/services/one_balance/venue_cash_source.dart';
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:money2/money2.dart';

import '../../helpers/fake_hyperliquid_move_rail.dart';
import '../../helpers/render_png.dart';
import '../../helpers/fake_swap_orders.dart';
import '../../helpers/shell_bar_harness.dart';
import '../../helpers/runtime_policy_fixture.dart';

const _ownSpark =
    'spark1pgss93sy072yrmtad5cy2srwjhq8ekzuw78yhr808jn6htqfh9w8p8h9mfwlv9';
const _hlAccount = '0x2222222222222222222222222222222222222222';

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
  _Currency()
      : super(CurrencyState({
          'USD': Fixed.fromInt(1),
          // $1 is €0.92: a stray conversion shows in the figures.
          'EUR': Fixed.parse('0.92'),
        }));
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

/// The Investing account holds nothing.
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

/// The wallet behind the ticket's own runner: the direct leg is planned
/// on the own Investing account the approval bound (and found costlier
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
      const DollarsLanded(byStatus: true, freshDollarsUsd: 100);
}

late _Env _env;
late _Funder _funder;

/// On demand: the locked ticket saying OK and Sal's placing toast written
/// as PNGs, light and dark (`--dart-define=OK_TOAST_RENDER_OUT=<dir>`).
const _renderOut = String.fromEnvironment('OK_TOAST_RENDER_OUT');
final _shot = GlobalKey();

Future<void> _pumpSlip(WidgetTester tester, FakeHyperliquidMoveRail rail,
    {bool knownEmpty = false,
    String currency = 'USD',
    bool sheet = false,
    bool dark = false}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  installShellBar();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      slipKnownEmptySourcesProvider.overrideWith((_) => () async => knownEmpty),
      settingsProvider.overrideWith((_) => SettingsModel(Settings(
            currency: currency,
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
      // $0 in Investments: no Dollars, no venue cash anywhere.
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
      // The venue's markets, for a ticket rebuilt from an order's record.
      standingHlMarketsProvider.overrideWithValue(
          ({required bool spot}) async => spot ? const [] : const [_market]),
    ],
    // The bar over the slip is the slip's button (shell_bar_harness.dart).
    child: sheet
        // The ticket as the app opens it: a modal sheet over a page on the
        // root navigator, Sal's toasts on the root overlay.
        ? shellBarApp(
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
                      builder: (_) => const HlOrderSlipSheet(
                          market: _market, initialIsLong: true),
                    ),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          )
        : shellBarApp(
            home: const Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: HlOrderSlipSheet(market: _market, initialIsLong: true),
              ),
            ),
          ),
  ));
  await _frames(tester);
  if (sheet) {
    await tester.tap(find.byKey(const ValueKey('open-slip')));
    await _frames(tester);
  }
}

Future<void> _frames(WidgetTester tester, [int n = 10]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}


ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(HlOrderSlipSheet)));

void main() {
  late FakeHyperliquidMoveRail rail;
  late List<SensitiveIntent> approvals;
  late List<String> sheets;
  late List<String> events;
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
    approvals = [];
    sheets = [];
    events = [];
    TrackingService.debugTrackObserver = (e, _) => events.add(e);
    // The spending bitcoin covers X.
    debugFreshSpendingBitcoin = () async => (sats: 1000000, usdPerBtc: 60000.0);
    debugBitcoinLegEstimate = (sats) async => sats / 1e8 * 60000 * 0.995;
    // The own Investing account the approval binds the direct leg to.
    debugOwnVenueDeposit = (_) async => _hlAccount;
    // Any sheet the ticket might open, recorded: none must open.
    debugShowHlDollarsDeposit = (side, _) async => sheets.add('dollars');
    debugShowSlipTopUpSheet = (venue, _) async => sheets.add('top_up');
    debugShowSlipReceiveSheet = (venue, _) async => sheets.add('receive');
    debugShowEmptySlipDepositSheet = (venue, _) async => sheets.add('deposit:$venue');
    // The ONE prompt, approved.
    debugHlOrderFundingApproval = (intent) async {
      approvals.add(intent);
      return AuthGrantRegistry.instance.issueAutofire(
          kPendingHlOrderAutofireId, intent,
          method: AuthGrantMethod.biometric);
    };
  });

  tearDown(() {
    debugFreshSpendingBitcoin = null;
    debugBitcoinLegEstimate = null;
    debugOwnVenueDeposit = null;
    debugShowHlDollarsDeposit = null;
    debugShowSlipTopUpSheet = null;
    debugShowSlipReceiveSheet = null;
    debugShowEmptySlipDepositSheet = null;
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
    // Past the autofire grant's own 30-minute life.
    await tester.pump(const Duration(minutes: 31));
  }

  // Euros in Settings change nothing on the money path (founder, 8 November
  // 2026): what is typed is what the order carries, in dollars.
  testWidgets(
      'euros in Settings: typing 20 is a \$20 order, on screen, in the one '
      'approval and in the order the venue call is made from', (tester) async {
    await _pumpSlip(tester, rail, currency: 'EUR');
    // The rate is live, and far from 1: nothing below is a coincidence.
    expect(
        _container(tester)
            .read(selectedCurrencyProviderFromUSD('EUR'))
            .toDouble(),
        0.92);
    final pad = find.byType(AmountKeypad);
    for (final key in ['2', '0']) {
      await tester.tap(find.descendant(of: pad, matching: find.text(key)));
      await tester.pump();
    }
    await _frames(tester, 3);
    final hero = tester.widget<BigAmountDisplay>(find.byType(BigAmountDisplay));
    expect(hero.prefix, r'$');
    expect(hero.amountText, '20');
    expect(hero.conversionLabel, isNull);
    expect(barPrimaryLabel(tester), contains(r'$20.00'));
    expect(find.textContaining('€'), findsNothing);

    await tapBarPrimary(tester, settle: false);
    await _frames(tester, 20);

    expect(approvals, hasLength(1));
    // 20 USD in the intent's 6 decimals, never 20 / 0.92.
    expect(approvals.single.amountMax, IntentUnits.usd(20));
    expect(approvals.single.limits[VenueLimit.sizeUnit], 'usd');
    final pending = _container(tester).read(pendingHyperliquidOrderProvider)!;
    expect(pending.marginUsd, 20.0);
    expect(find.textContaining('€'), findsNothing);
    AuthGrantRegistry.instance.cancelAutofire(kPendingHlOrderAutofireId);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'nothing typed, \$0 in Investments, enough bitcoin: "Add" funds the '
      'minimum order in place under ONE approval, no sheet', (tester) async {
    await _pumpSlip(tester, rail);
    // Nothing typed: the order's short name; the tap adds, then places.
    expect(barPrimaryLabel(tester), 'Long minimum on BTC');

    await tapBarPrimary(tester, settle: false);
    await _frames(tester, 20);

    // No sheet of any kind: the ticket is still the only screen.
    expect(sheets, isEmpty);
    expect(find.byType(DepositSheet), findsNothing);
    expect(events, isNot(contains('slip_top_up_opened')));
    expect(events.where((e) => e == 'order_funding_requested'), hasLength(1));
    expect(events.where((e) => e == 'order_funding_started'), hasLength(1));

    // ONE approval, binding the order, its move and the Bitcoin leg.
    expect(approvals, hasLength(1));
    expect(approvals.single.action, SensitiveAction.hlOrder);
    expect(approvals.single.limits[VenueLimit.fundBtc], isNotNull);
    // The direct Bitcoin → Investing leg was planned on the own account
    // that approval bound, before the route was picked.
    expect(_env.planned, [(OneBalanceVenue.investing, _hlAccount)]);
    // Costlier here: the via-Dollars leg went, once; the move followed.
    expect(_env.directSends, 0);
    expect(_env.sends, 1);
    expect(_funder.sent, hasLength(1));

    // The ticket took the order it was sized for: the market's minimum.
    final pending = _container(tester).read(pendingHyperliquidOrderProvider)!;
    expect(pending.marginUsd, greaterThan(0));
    expect(pending.fundingSource, 'bitcoin');

    // The steps, on the ticket, under one busy button: the ticket stays
    // up after the accept, locked as before, with no placing toast and no
    // "you can leave" line.
    expect(find.byKey(const ValueKey('order-slip-funded-progress')),
        findsOneWidget);
    expect(barPrimaryBusy(tester), isTrue);
    expect(find.byKey(const ValueKey('sal-toast')), findsNothing);
    expect(find.textContaining('You can leave'), findsNothing);
    // While its order is on its way the busy button (Sal working on it)
    // says OK and takes the tap, which only closes the ticket (founder,
    // 10 November 2026, on 2.2.0 (99)): from the accept, before the
    // record exists, and on record, posted or not.
    expect(barPrimaryLabel(tester), 'OK');
    expect(barPrimaryEnabled(tester), isTrue);
    final standing = _container(tester).read(standingOrdersProvider.notifier);
    final keep = _container(tester).read(standingOrdersProvider);
    final at = DateTime.now();
    standing.debugReplace([
      StandingOrder(
        id: 'so_hl',
        walletId: 'w',
        venue: StandingOrderVenue.investing,
        marketKey: 'BTC',
        marketTitle: 'BTC · Perp',
        sideLabel: 'long',
        isBuy: true,
        size: 1,
        approvedPrice: 60000,
        amountUsd: 10,
        orderKind: 'market',
        state: StandingOrderState.funded,
        createdAt: at,
        updatedAt: at,
      ),
    ]);
    await _frames(tester, 2);
    expect(barPrimaryBusy(tester), isTrue);
    expect(barPrimaryLabel(tester), 'OK');
    expect(barPrimaryEnabled(tester), isTrue);
    expect(find.text('Cancel'), findsNothing);
    standing.debugReplace([
      standing.byId('so_hl')!.copyWith(state: StandingOrderState.posting),
    ]);
    await _frames(tester, 2);
    expect(barPrimaryLabel(tester), 'OK');
    // Its result known: OK gives way to the ticket's own end.
    standing.debugReplace([
      standing.byId('so_hl')!.copyWith(state: StandingOrderState.failed),
    ]);
    await _frames(tester, 2);
    expect(barPrimaryLabel(tester), isNot('OK'));
    standing.debugReplace(keep);
    await _frames(tester, 2);

    // The venue credits it and the autofire places it: never a second
    // prompt.
    final notifier =
        _container(tester).read(pendingHyperliquidOrderProvider.notifier);
    notifier.updateStatus(PendingHlOrderStatus.placing);
    await _frames(tester, 3);
    notifier.updateStatus(PendingHlOrderStatus.done);
    await _frames(tester, 3);
    final record = _container(tester).read(fundedOrdersProvider).single;
    expect(record.stage, FundedOrderStage.done);
    expect(approvals, hasLength(1));
    await release(tester);
  });
  testWidgets(
      'OK on Sal\'s button closes the ticket as leaving does: the order goes '
      'on, nothing cancelled, and Sal says "Placing your investment" at the '
      'top with no spinner and no Cancel', (tester) async {
    await _pumpSlip(tester, rail, sheet: true);
    await tapBarPrimary(tester, settle: false);
    await _frames(tester, 20);
    expect(barPrimaryLabel(tester), 'OK');
    final c = _container(tester);
    final before = c.read(pendingHyperliquidOrderProvider)!;
    await tapBarPrimary(tester, settle: false);
    await _frames(tester, 10);
    expect(find.byType(HlOrderSlipSheet), findsNothing);
    // The order goes on: nothing cancelled.
    final after = c.read(pendingHyperliquidOrderProvider);
    expect(after, isNotNull);
    expect(after!.status, before.status);
    expect(events, isNot(contains('standing_order_cancelled')));
    // Sal at the top: the words and the order, nothing thinking, no
    // Cancel; the X closes it.
    expect(find.byKey(const ValueKey('sal-toast')), findsOneWidget);
    expect(find.text('Placing your investment'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byKey(const ValueKey('sal-toast-mark')), findsNothing);
    expect(find.byKey(const ValueKey('sal-toast-action')), findsNothing);
    expect(find.byKey(const ValueKey('sal-toast-close')), findsOneWidget);
    SalToast.debugReset();
    StandingOrderToasts.debugReset();
    await release(tester);
  });
  testWidgets(
      'a tap on the placing toast opens the same ticket again, locked on its '
      'order as it was left (the steps, the OK, its haptics running again), '
      'never a journey sheet or a Cancel; leaving stops the haptics; it goes '
      'once its order is placed', (tester) async {
    await _pumpSlip(tester, rail, sheet: true);
    await tapBarPrimary(tester, settle: false);
    await _frames(tester, 20);
    expect(barPrimaryLabel(tester), 'OK');
    final c = _container(tester);
    final standing = c.read(standingOrdersProvider.notifier);
    final keep = c.read(standingOrdersProvider);
    final at = DateTime.now();
    final order = StandingOrder(
      id: 'so_hl',
      walletId: 'w',
      venue: StandingOrderVenue.investing,
      marketKey: 'BTC',
      marketTitle: 'BTC · Perp',
      sideLabel: 'long',
      isBuy: true,
      size: 1,
      approvedPrice: 60000,
      amountUsd: 10,
      orderKind: 'market',
      state: StandingOrderState.funded,
      createdAt: at,
      updatedAt: at,
    );
    standing.debugReplace([...keep, order]);
    await _frames(tester, 2);
    await tapBarPrimary(tester, settle: false);
    await _frames(tester, 10);
    expect(find.byType(HlOrderSlipSheet), findsNothing);
    expect(find.text('Placing your investment'), findsOneWidget);
    // The toast's tap (not its X).
    await tester.tap(find.text('Placing your investment'));
    await _frames(tester, 10);
    expect(find.byType(HlOrderSlipSheet), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
    expect(find.byKey(const ValueKey('sal-toast')), findsNothing);
    // The haptics run again, as on the ticket after its accept.
    expect(
        tester
            .widget<RubberBandProgress>(
                find.byKey(const ValueKey('order-slip-funded-progress')))
            .haptic,
        isTrue);
    expect(ContinuousHaptics.isRunning(), isTrue);
    // Locked as before: the steps, Sal's busy OK, on the same side.
    final reopened =
        tester.widget<HlOrderSlipSheet>(find.byType(HlOrderSlipSheet));
    expect(reopened.standingEndedBefore, isNotNull);
    expect(reopened.standingEndedBefore, isNot(contains('so_hl')));
    expect(reopened.initialIsLong, isTrue);
    expect(find.byKey(const ValueKey('order-slip-funded-progress')),
        findsOneWidget);
    expect(barPrimaryLabel(tester), 'OK');
    expect(barPrimaryBusy(tester), isTrue);
    // OK leaves it: the haptics stop at once; the toast opens it again.
    await tapBarPrimary(tester, settle: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(ContinuousHaptics.isRunning(), isFalse);
    await _frames(tester, 10);
    expect(find.byType(HlOrderSlipSheet), findsNothing);
    await tester.tap(find.text('Placing your investment'));
    await _frames(tester, 10);
    expect(find.byType(HlOrderSlipSheet), findsOneWidget);
    expect(ContinuousHaptics.isRunning(), isTrue);
    // Its order fills: the ticket goes, nothing cancelled.
    standing.debugReplace([
      for (final o in c.read(standingOrdersProvider))
        o.id == 'so_hl' ? o.copyWith(state: StandingOrderState.filled) : o,
    ]);
    await _frames(tester, 10);
    expect(find.byType(HlOrderSlipSheet), findsNothing);
    expect(events, isNot(contains('standing_order_cancelled')));
    SalToast.debugReset();
    StandingOrderToasts.debugReset();
    StandingOrderSlips.debugReset();
    await release(tester);
  });

  StandingOrder hlOrder({required bool isLong, required StandingOrderState state}) {
    final at = DateTime.now();
    return StandingOrder(
      id: 'so_hl',
      walletId: 'w1',
      venue: StandingOrderVenue.investing,
      marketKey: 'BTC',
      marketTitle: 'BTC · Perp',
      sideLabel: isLong ? 'long' : 'short',
      isBuy: isLong,
      size: 10,
      approvedPrice: 60000,
      amountUsd: 10,
      orderKind: 'market',
      state: state,
      createdAt: at,
      updatedAt: at,
      marketKind: 'perp',
      positionCoin: 'BTC',
    );
  }

  Future<void> reopenHl(WidgetTester tester) async {
    unawaited(StandingOrderSlips.reopen(
        tester.element(find.byKey(const ValueKey('open-slip'))),
        id: 'so_hl'));
    await _frames(tester, 10);
  }

  testWidgets(
      'a fresh app (nothing handed over): the ticket is rebuilt from the '
      'order\'s record, on the very market it was approved on: locked, '
      'Long, the steps, OK, the haptics running; leaving stops them',
      (tester) async {
    await _pumpSlip(tester, rail, sheet: true);
    await tapBarPrimary(tester, settle: false);
    await _frames(tester, 20);
    final c = _container(tester);
    final standing = c.read(standingOrdersProvider.notifier);
    standing.debugReplace([
      ...c.read(standingOrdersProvider),
      hlOrder(isLong: true, state: StandingOrderState.funded),
    ]);
    await _frames(tester, 2);
    await tapBarPrimary(tester, settle: false);
    await _frames(tester, 10);
    expect(find.byType(HlOrderSlipSheet), findsNothing);
    // The app restarted: no ticket kept, the toast gone.
    StandingOrderSlips.debugReset();
    SalToast.debugReset();
    StandingOrderToasts.debugReset();
    await _frames(tester, 4);
    await reopenHl(tester);
    expect(find.byType(HlOrderSlipSheet), findsOneWidget);
    final ticket =
        tester.widget<HlOrderSlipSheet>(find.byType(HlOrderSlipSheet));
    expect(ticket.source, 'standing_order');
    expect(ticket.market.coin, 'BTC');
    expect(ticket.initialIsLong, isTrue);
    expect(ticket.initialUsd, 10);
    expect(ticket.standingEndedBefore, isNot(contains('so_hl')));
    expect(find.text('Cancel'), findsNothing);
    expect(find.byKey(const ValueKey('order-slip-funded-progress')),
        findsOneWidget);
    expect(barPrimaryLabel(tester), 'OK');
    expect(barPrimaryBusy(tester), isTrue);
    expect(ContinuousHaptics.isRunning(), isTrue);
    await tapBarPrimary(tester, settle: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(ContinuousHaptics.isRunning(), isFalse);
    await _frames(tester, 10);
    expect(find.byType(HlOrderSlipSheet), findsNothing);
    expect(events, isNot(contains('standing_order_cancelled')));
    SalToast.debugReset();
    StandingOrderToasts.debugReset();
    StandingOrderSlips.debugReset();
    await release(tester);
  });

  testWidgets(
      'a Short rebuilt from its record opens the ticket on Short (red), '
      'locked, OK, no Cancel', (tester) async {
    await _pumpSlip(tester, rail, sheet: true);
    Navigator.of(tester.element(find.byType(HlOrderSlipSheet))).pop();
    await _frames(tester, 6);
    final c = ProviderScope.containerOf(
        tester.element(find.byKey(const ValueKey('open-slip'))));
    c.read(standingOrdersProvider.notifier).debugReplace(
        [hlOrder(isLong: false, state: StandingOrderState.posting)]);
    await _frames(tester, 2);
    await reopenHl(tester);
    final ticket =
        tester.widget<HlOrderSlipSheet>(find.byType(HlOrderSlipSheet));
    expect(ticket.initialIsLong, isFalse);
    expect(ticket.standingEndedBefore, isEmpty);
    expect(barPrimaryLabel(tester), 'OK');
    expect(barPrimaryBusy(tester), isTrue);
    expect(find.text('Cancel'), findsNothing);
    StandingOrderSlips.debugReset();
    await release(tester);
  });
  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets('render: the locked ticket saying OK, then the placing toast '
        '($mode)', (tester) async {
      await tester.runAsync(loadRenderFonts);
      await _pumpSlip(tester, rail, sheet: true, dark: dark);
      await tapBarPrimary(tester, settle: false);
      await _frames(tester, 20);
      await writeRenderPng(
          tester, _shot, '$_renderOut/ticket_ok_investment_$mode.png');
      // Sal's sheets are not read in the test's fake time: the rig draws
      // him in the toast, as where the sheets cannot be read.
      SalSpriteCache.debugSetManifest(null);
      addTearDown(SalSpriteCache.debugReset);
      await tapBarPrimary(tester, settle: false);
      await _frames(tester, 10);
      expect(find.text('Placing your investment'), findsOneWidget);
      await writeRenderPng(
          tester, _shot, '$_renderOut/toast_placing_investment_$mode.png');
      SalToast.debugReset();
      StandingOrderToasts.debugReset();
      await release(tester);
    }, skip: _renderOut.isEmpty);
  }

  testWidgets('known zero across all sources opens Investing deposit and preserves slip',
      (tester) async {
    debugFreshSpendingBitcoin = () async => (sats: 0, usdPerBtc: 60000.0);
    await _pumpSlip(tester, rail, knownEmpty: true);
    await tapBarPrimary(tester, settle: false);
    await _frames(tester, 20);
    expect(sheets, ['deposit:SlipVenue.investing']);
    expect(find.byType(HlOrderSlipSheet), findsOneWidget);
    expect(approvals, isEmpty);
    expect(_env.sends, 0);
    await release(tester);
  });
  testWidgets('unknown sources never open the contextual deposit', (tester) async {
    debugFreshSpendingBitcoin = () async => (sats: 0, usdPerBtc: 60000.0);
    await _pumpSlip(tester, rail);
    await tapBarPrimary(tester, settle: false);
    await _frames(tester, 20);
    expect(sheets, ['receive']);
    expect(approvals, isEmpty);
    await release(tester);
  });
}
