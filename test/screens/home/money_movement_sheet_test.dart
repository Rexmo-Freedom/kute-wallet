// Move money (the Portfolio's button): the purchase sheet with both ends
// editable. These pump the real sheet against fakes only and hold it to
// the founder's rules: picking a route never sends; every account pair
// runs on its own rail from the selected account alone (or is disabled);
// what is sent is the typed amount even when a balance moves before the
// tap; the spending wallet is pinned across every await; a declined
// approval resets quietly; a stop that proves nothing left offers Retry,
// and a send whose outcome is unknown locks the sheet on Activity.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_ce/hive.dart' show Box;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/orchestra_router.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/balance_model.dart';
import 'package:kute/models/breez/sdk_instance.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/orchestra_routes_model.dart'
    show
        OrchestraCatalogSource,
        OrchestraRoutesCatalog,
        RouteUnavailableReason;
import 'package:kute/models/settings_model.dart';
import 'package:kute/models/settlement_operation.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/breez_config_provider.dart';
import 'package:kute/providers/breez_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/orchestra_supported_routes_provider.dart'
    show OrchestraSupportedRoutesNotifier, orchestraSupportedRoutesProvider;
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/spark_address_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider, usdSdkBalanceProvider;
import 'package:kute/screens/home/components/deposit_sheet.dart';
import 'package:kute/screens/shared/amount_keypad_panel.dart'
    show BigAmountDisplay;
import 'package:kute/screens/shared/money_movement_sheet.dart';
import 'package:kute/services/funding/hot_settlement.dart';
import 'package:kute/services/funding/settlement_funding_outcome.dart'
    show SettlementFundingRefused;
import 'package:kute/services/funding/settlement_runner.dart';
import 'package:kute/services/funding/settlement_store.dart';
import 'package:kute/services/funding/spark_hypercore_funding_service.dart';
import 'package:kute/services/http/shared_http_client.dart';
import 'package:kute/services/polymarket_onboarding_service.dart'
    show PolymarketReadException;
import 'package:kute/services/hyperliquid/cctp_withdrawal.dart';
import 'package:kute/services/hyperliquid/hypercore_activation_fee.dart'
    show HypercoreBalanceShortfall;
import 'package:kute/services/one_balance/bitcoin_to_dollars_leg.dart'
    show BitcoinLegSent;
import 'package:kute/services/one_balance/dollars_to_bitcoin_minimum.dart';
import 'package:kute/screens/receive/bitcoin_receive_options.dart'
    show kBitcoinReceiveDollarsSource;
import 'package:kute/screens/usd/usd_withdraw_screen.dart'
    show kUsdWithdrawBitcoinRowSource;
import 'package:kute/services/one_balance/buy_bitcoin_fanout.dart'
    show BitcoinPurchaseFanout, bitcoinPurchaseFanoutProvider;
import 'package:kute/services/one_balance/dollars_to_bitcoin_purchase.dart'
    show DollarsToBitcoinSent;
import 'package:kute/services/one_balance/investments_spendable.dart'
    show investmentsSpendable, venueCashLastReadProvider;
import 'package:kute/services/one_balance/multi_source_move.dart'
    show MultiSourceMoveStore;
import 'package:kute/services/one_balance/one_balance_state.dart'
    show OneBalanceVenue;
import 'package:kute/services/one_balance/pending_bitcoin_purchase.dart'
    show
        BitcoinPurchaseFinisher,
        PendingBitcoinPurchaseStore,
        bitcoinPurchaseFinisherProvider;
import 'package:kute/services/one_balance/venue_cash_source.dart'
    show
        VenueCashCandidate,
        VenueCashPuller,
        VenueCashSource,
        kVenuePullEta,
        planDollarsShortfall,
        venueCashPullerProvider;
import 'package:kute/services/one_balance/venue_funder.dart'
    show VenueMoveResult;
import 'package:kute/services/orchestra/orchestra_quote_gate.dart'
    show OrchestraQuoteFailure;
import 'package:kute/models/orchestra_route_limits.dart';
import 'package:kute/services/orchestra/standing_deposit_store.dart'
    show InvestingWithdrawalDestination;
import 'package:kute/services/investment_provider_availability.dart';
import 'package:kute/services/region_freshness.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart' show Fixed;

import '../../helpers/runtime_policy_fixture.dart';
import '../../helpers/kute_bar_test_support.dart';
import '../../gating_audit/market_gating_fixtures.dart';

const _usdPerBtc = 100000.0;
const _ownSpark =
    'spark1pgss93sy072yrmtad5cy2srwjhq8ekzuw78yhr808jn6htqfh9w8p8h9mfwlv9';
const _hlAccount = '0x1111111111111111111111111111111111111111';
const _pmWallet = '0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359';
const _changed = 'The details changed. Review again before approving.';
const _unknownCopy = "We couldn't confirm whether your transfer left. "
    "We're checking and won't send it again.";

const _b = MoneyMovementAccount.bitcoin;
const _d = MoneyMovementAccount.dollars;
const _i = MoneyMovementAccount.investing;
const _p = MoneyMovementAccount.predictions;

// ─── fakes ──────────────────────────────────────────────────────────

/// Every estimate the sheet asks for, and a flat price for it.
final _estimates = <Map<String, String>>[];
MockClient _orchestra() => MockClient((request) async {
      if (!request.url.path.endsWith('/estimate')) {
        return http.Response('{}', 404);
      }
      final q = request.url.queryParameters;
      _estimates.add(Map.of(q));
      final asset = q['destinationAsset']!;
      final chain = q['destinationChain']!;
      final source = q['sourceAsset']!;
      final input = orchestraAmountToDouble(q['amount'] ?? '0', source,
          chain: q['sourceChain']!);
      final usd = source == 'BTC' ? input * _usdPerBtc : input;
      final out = doubleToOrchestraAmount(
          asset == 'BTC' ? usd / _usdPerBtc : usd, asset,
          chain: chain);
      return http.Response(
          jsonEncode({'estimatedOut': out, 'feeAmount': '0', 'feeBps': 0}),
          200);
    });

class _Currency extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _Currency()
      : super(CurrencyState({
          'USD': Fixed.fromInt(_usdPerBtc.round()),
          'BTC': Fixed.fromNum(1 / _usdPerBtc, decimalDigits: 16),
        }));

  @override
  Future<void> updateRates() async {}
}

/// Two hot wallets: the spending one and another the person can switch to.
class _Settings extends SettingsModel {
  _Settings()
      : super(Settings(
          currency: 'USD',
          language: 'en',
          btcFormat: 'sats',
          backup: false,
          biometricsEnabled: false,
          bitcoinElectrumNode: '',
          nodeType: 'Blockstream',
          reviewDone: true,
          wallets: [
            WalletConfig(id: 'spending', name: 'Spending'),
            WalletConfig(id: 'other', name: 'Other'),
          ],
          activeWalletId: 'spending',
        ));
}

/// The Predictions account. [deposit] stands in for the account start
/// when the live state has no deposit wallet yet.
class _Trading extends PolymarketTradingNotifier {
  @override
  Future<PolymarketTradingState> build() async => PolymarketTradingState(
      walletAddress: '0xeoa',
      proxyWalletAddress: _proxyKnown ? _pmWallet : null,
      usdcBalance: 20);

  @override
  Future<String?> depositAddress({Duration timeout = Duration.zero}) =>
      _deposit?.future ?? Future.value(_pmWallet);

  @override
  Future<BigInt> spendableMicroUsdc() async {
    final failure = _readFailure;
    if (failure != null) throw failure;
    return BigInt.from((_predictions * 1e6).round());
  }

  @override
  Future<BigInt> payableMicroUsdc(double amount) async {
    final failure = _readFailure;
    if (failure != null) throw failure;
    return BigInt.from((amount * 1e6).round());
  }

  /// The watch that converts a delivered deposit: started by every rail
  /// into Predictions.
  @override
  void wrapIncomingUsdcEToPusd({
    Duration timeout = const Duration(minutes: 8),
    Duration interval = const Duration(seconds: 4),
    Duration lateInterval = const Duration(seconds: 15),
  }) {
    _arrivalWatches++;
  }

  /// The account's one-time setup, asked for before a move leaves
  /// Predictions. Done, unless [_setupFailure] says it cannot finish.
  @override
  Future<void> enableTrading({
    void Function(String status)? onProgress,
    bool force = false,
  }) async {
    _setupAsked++;
    final failure = _setupFailure;
    if (failure != null) throw failure;
  }
}

bool _proxyKnown = true;
Completer<String?>? _deposit;
Object? _setupFailure;
int _setupAsked = 0;

/// What the live balance read throws, when it cannot be read.
Object? _readFailure;
int _arrivalWatches = 0;
double _predictions = 20;
double _dollars = 20;

class _Account extends HlAccountNotifier {
  @override
  Future<HlAccountSnapshot> build() async => HlAccountSnapshot(
      accountValue: _investing,
      withdrawable: _investing,
      totalMarginUsed: 0,
      positions: const [],
      spotBalances: const []);
}

double _investing = 20;

/// The approval prompt: records each intent, approves unless told not
/// to, and can run something while it is up (a wallet switch).
class _Approvals {
  final intents = <SensitiveIntent>[];
  bool approve = true;
  void Function()? whileUp;

  Future<AuthGrant?> call(SensitiveIntent intent) async {
    intents.add(intent);
    whileUp?.call();
    if (!approve) return null;
    return AuthGrants.issue(intent, method: AuthGrantMethod.biometric);
  }
}

late _Approvals _approvals;

/// The step-up intent a rail hands its hook once it holds a quote.
SettlementAuthorizationIntent _intent(SettlementFlow flow, String route,
        {String walletId = 'spending'}) =>
    SettlementAuthorizationIntent(
      flow: flow,
      walletId: walletId,
      destination: 'own|v1',
      routeLabel: route,
      amountIn: BigInt.from(1000),
      minReceive: BigInt.one,
      maxFeeBps: 100,
    );

/// The settlement runner: records each plan, asks its approval, then does
/// what the test scripts (in flight by default: nothing returns).
class _Runner extends SettlementRunner {
  _Runner()
      : super(store: SettlementStore(box: _NoBox(), quarantine: _NoBox()));

  final plans = <SettlementPlan>[];

  /// Runs after an approved step-up; null parks the move in flight.
  Future<SettlementRunResult> Function(SettlementPlan plan)? afterApproval;

  @override
  Future<SettlementRunResult> run(SettlementPlan plan) async {
    plans.add(plan);
    final hook = plan.stepUp;
    if (hook != null &&
        !await hook(
            _intent(plan.flow, plan.route.label, walletId: plan.walletId))) {
      throw const SettlementStopped(SettlementStopReason.declined);
    }
    final then = afterApproval;
    if (then != null) return then(plan);
    return Completer<SettlementRunResult>().future;
  }
}

class _NoBox implements Box<String> {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('no store in this test');
}

/// The native HyperCore routes: records each deposit and withdrawal and
/// asks its approval as the real service does; then parks in flight
/// unless [refusal] is thrown where Orchestra's quote would refuse.
class _Hypercore extends SparkHypercoreFundingService {
  _Hypercore(super.read);

  final deposits = <({SparkFundingAsset asset, BigInt amount})>[];
  final withdrawals = <({double usd, SparkFundingAsset destination})>[];

  /// Native withdrawals straight to the own Predictions account.
  final toPredictions = <double>[];
  Object? refusal;

  @override
  Future<void> ensureAvailable({required bool deposit}) async {}

  @override
  Future<DirectHypercoreResult> depositFromSpark({
    required SparkFundingAsset asset,
    required BigInt amountBaseUnits,
    double? amountUsd,
    void Function()? onFundingStarted,
    SettlementStepUpHook? stepUp,
    bool registerInBackground = false,
    String purpose = 'manual_move',
  }) async {
    deposits.add((asset: asset, amount: amountBaseUnits));
    if (!await stepUp!(
        _intent(SettlementFlow.sparkToInvestingDirect, 'spark>hypercore'))) {
      throw const SettlementStopped(SettlementStopReason.declined);
    }
    onFundingStarted?.call();
    return Completer<DirectHypercoreResult>().future;
  }

  @override
  Future<DirectHypercoreResult> withdrawToSpark({
    required double usd,
    SparkFundingAsset destination = SparkFundingAsset.bitcoin,
    required SettlementStepUpHook stepUp,
    bool registerInBackground = false,
    String purpose = 'manual_move',
  }) async {
    withdrawals.add((usd: usd, destination: destination));
    final r = refusal;
    if (r != null) throw r;
    if (!await stepUp(_intent(
        destination.sparkWithdrawFlow, destination.sparkWithdrawRoute.label))) {
      throw const SettlementStopped(SettlementStopReason.declined);
    }
    return Completer<DirectHypercoreResult>().future;
  }

  @override
  Future<DirectHypercoreResult> withdrawToPredictions({
    required double usd,
    required SettlementStepUpHook stepUp,
    bool registerInBackground = false,
    String purpose = 'manual_move',
  }) async {
    toPredictions.add(usd);
    final r = refusal;
    if (r != null) throw r;
    if (!await stepUp(_intent(SettlementFlow.investingToPredictionsDirect,
        kHypercoreToPredictionsRoute.label))) {
      throw const SettlementStopped(SettlementStopReason.declined);
    }
    return Completer<DirectHypercoreResult>().future;
  }
}

/// Circle CCTP out of HyperCore: records each move, asks its approval,
/// then answers what the test scripts (in flight by default).
class _Cctp implements HypercoreCctpWithdrawal {
  final moves = <({InvestingWithdrawalDestination destination, double usd})>[];
  CctpWithdrawalResult? result;

  /// Thrown after the approval, as the service's send stops do.
  Object? error;

  @override
  Future<CctpWithdrawalResult> withdrawTo({
    required InvestingWithdrawalDestination destination,
    required double usd,
    required SettlementStepUpHook stepUp,
    String purpose = 'manual_move',
  }) async {
    moves.add((destination: destination, usd: usd));
    if (!await stepUp(
        _intent(cctpFlowFor(destination), cctpRouteFor(destination).label))) {
      throw const SettlementStopped(SettlementStopReason.declined);
    }
    final failure = error;
    if (failure != null) throw failure;
    final scripted = result;
    if (scripted != null) return scripted;
    return Completer<CctpWithdrawalResult>().future;
  }

  @override
  Future<CctpWithdrawalResult> withdrawToDollars({
    required double usd,
    required SettlementStepUpHook stepUp,
    String purpose = 'manual_move',
  }) =>
      withdrawTo(
          destination: InvestingWithdrawalDestination.dollars,
          usd: usd,
          stepUp: stepUp,
          purpose: purpose);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A route catalogue held as given: no Hive, no network.
class _Routes extends OrchestraSupportedRoutesNotifier {
  _Routes(OrchestraRoutesCatalog catalog) {
    state = catalog;
  }

  @override
  Future<void> init() async {}

  @override
  Future<bool> refresh() async => false;
}

/// A live catalogue row. Lists no destinations: a pair it names is missing.
Map<String, dynamic> _row(String chain, String asset, {int decimals = 6}) => {
      'id': '$chain:$asset',
      'chain': chain,
      'asset': asset,
      'decimals': decimals,
      'route': {'to': [], 'fixedTo': [], 'exactOutTo': []},
    };

/// Bitcoin → Dollars, the shared leg's seam: records the dollars it was
/// sized for and parks in flight.
final _btcToDollars = <double>[];

late _Runner _runner;
late _Hypercore _hypercore;
late _Cctp _cctp;
final _events = <(String, Map<String, Object>?)>[];
final _nav = GlobalKey<NavigatorState>();

Map<String, Object> _last(String event) =>
    _events.lastWhere((e) => e.$1 == event).$2 ?? const {};

Iterable<Map<String, Object>> _all(String event) =>
    _events.where((e) => e.$1 == event).map((e) => e.$2 ?? const {});

/// Every rail call so far, for "nothing else was asked to pay".
int get _railCalls =>
    _runner.plans.length +
    _hypercore.deposits.length +
    _hypercore.withdrawals.length +
    _hypercore.toPredictions.length +
    _cctp.moves.length +
    _btcToDollars.length;

/// Venue cash the test sets, recording each pull home to Dollars (fw46).
class _VenueCash implements VenueCashSource {
  _VenueCash(this.venue);

  @override
  final OneBalanceVenue venue;
  double available = 0;
  final pulls = <double>[];

  @override
  Duration get estimatedArrival => kVenuePullEta[venue]!;

  @override
  Future<double> availableUsd() async => available;

  @override
  Future<VenueMoveResult> pull(double usd, {required String purpose}) async {
    pulls.add(usd);
    return VenueMoveResult(
        quoteId: 'q-${venue.name}',
        sentUsd: usd,
        arrivingUsdEstimate: usd * 0.99);
  }
}

/// Each venue's route minimum, as the engine reads it here.
double _venueMinimum(OneBalanceVenue venue) =>
    venue == OneBalanceVenue.investing ? 5 : 1;

/// The venues' free cash as the engine reads it: [p] on Predictions, [i]
/// on Investing.
List<VenueCashCandidate> _venueCash({double p = 0, double i = 0}) => [
      if (p > 0)
        (
          venue: OneBalanceVenue.predictions,
          availableUsd: p,
          eta: kVenuePullEta[OneBalanceVenue.predictions]!,
          minimumUsd: _venueMinimum(OneBalanceVenue.predictions),
        ),
      if (i > 0)
        (
          venue: OneBalanceVenue.investing,
          availableUsd: i,
          eta: kVenuePullEta[OneBalanceVenue.investing]!,
          minimumUsd: _venueMinimum(OneBalanceVenue.investing),
        ),
    ];

// ─── harness ────────────────────────────────────────────────────────

Future<ProviderContainer> _open(WidgetTester tester, MoneyMovementRoute route,
    {Completer<String?>? hlAddress,
    OrchestraRoutesCatalog? catalog,
    bool pinned = false,
    double? initialTargetUsd,
    List<Override> overrides = const [],
    String? ownMoveEntrySource}) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  // Handed out inside the test's clock, so awaiting it runs with the test.
  HotSettlement.debugRunner = _runner;
  final container = ProviderContainer(overrides: [
    settingsProvider.overrideWith((_) => _Settings()),
    currencyProvider.overrideWith((_) => _Currency()),
    polymarketTradingProvider.overrideWith(_Trading.new),
    polymarketBalanceProvider.overrideWith((_) => _predictions),
    hyperliquidAccountProvider.overrideWith(_Account.new),
    hyperliquidAddressProvider
        .overrideWith((_) => hlAddress?.future ?? Future.value(_hlAccount)),
    sparkHypercoreFundingServiceProvider
        .overrideWith((ref) => _hypercore = _Hypercore(ref.read)),
    hypercoreCctpWithdrawalProvider.overrideWithValue(_cctp),
    sparkBitcoinBalanceProvider.overrideWith((ref) async => BigInt.from(ref
            .watch(walletBalanceCacheProvider)['spending']
            ?.sparkBitcoinbalance ??
        0)),
    breezSDKProvider.overrideWith((_) => Completer<BreezSdkSpark>().future),
    usdBalanceProvider.overrideWith((_) => _dollars),
    usdSdkBalanceProvider.overrideWith((_) => Stream.value(_dollars)),
    sparkSelfAddressProvider.overrideWith((_) async => _ownSpark),
    dollarsToBitcoinMinimumProvider
        .overrideWith((_) => DollarsToBitcoinMinimum(fetch: (_) async => null)),
    if (catalog != null)
      orchestraSupportedRoutesProvider.overrideWith((_) => _Routes(catalog)),
    ...overrides,
  ]);
  _setSats(container, 20000); // $20.00 at the sample price.
  SharedHttpClient.debugOverride = _orchestra();
  await http.runWithClient(
    () => tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          // The shell bar over the page, as app_widget.dart mounts it: the
          // sheet's button is the bar (kute_bar_test_support.dart).
          builder: withKuteShellBar,
          theme:
              buildLightTheme().copyWith(splashFactory: NoSplash.splashFactory),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          navigatorKey: _nav,
          home: const Scaffold(body: Text('Portfolio')),
        ),
      ),
    )),
    _orchestra,
  );
  // An own-account door's own call (showOwnMoneyMove), or the Portfolio's.
  final entrySource = ownMoveEntrySource;
  unawaited(entrySource != null
      ? showOwnMoneyMove(_nav.currentContext!,
          from: route.from, entrySource: entrySource)
      : showMoneyMovementSheet(_nav.currentContext!,
          initialSource: route.from,
          initialDestination: route.to,
          pinned: pinned,
          initialTargetUsd: initialTargetUsd));
  await _frames(tester, 12);
  container.read(sparkHypercoreFundingServiceProvider);
  return container;
}

void _setSats(ProviderContainer container, int sats) =>
    container.read(walletBalanceCacheProvider.notifier).setBalance('spending',
        WalletBalance(onChainBtcBalance: 0, sparkBitcoinbalance: sats));

Future<void> _frames(WidgetTester tester, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _type(WidgetTester tester, String amount) async {
  for (final key in amount.split('')) {
    await tester.tap(find.text(key).last);
    await tester.pump();
  }
  await _frames(tester, 4);
}

Finder get _cta => kuteBarPrimary;
KuteBarPrimaryProbe _button(WidgetTester tester) =>
    kuteBarPrimaryProbe(tester);

Future<void> _confirm(WidgetTester tester) async {
  await tester.tap(_cta);
  await _frames(tester);
}

Future<void> _close(WidgetTester tester, ProviderContainer container) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpWidget(const SizedBox());
  container.dispose();
  // The policy's refresh timers.
  await tester.pump(const Duration(minutes: 3));
}

void main() {
  setUpAll(() {
    dotenv.loadFromString(envString: 'BACKEND=https://backend.test');
    GoogleFonts.config.allowRuntimeFetching = false;
  });
  setUp(() {
    AffiliateService.debugSessionToken = 'test-session';
    RuntimeCapabilitiesService.debugInstance = runtimePolicyFixture();
    _runner = _Runner();
    _cctp = _Cctp();
    _approvals = _Approvals();
    debugMoveApproval = _approvals.call;
    _btcToDollars.clear();
    debugBitcoinToDollarsSend = ({required approxUsd, required onSending}) {
      _btcToDollars.add(approxUsd);
      onSending();
      return Completer<BitcoinLegSent>().future;
    };
    _estimates.clear();
    _events.clear();
    TrackingService.debugTrackObserver = (e, p) => _events.add((e, p));
    _proxyKnown = true;
    _setupFailure = null;
    _setupAsked = 0;
    _readFailure = null;
    _arrivalWatches = 0;
    _deposit = null;
    _predictions = 20;
    _dollars = 20;
    _investing = 20;
  });
  tearDown(() {
    HotSettlement.debugRunner = null;
    debugMoveApproval = null;
    debugBitcoinToDollarsSend = null;
    TrackingService.debugTrackObserver = null;
    RuntimeCapabilitiesService.debugInstance?.dispose();
    RuntimeCapabilitiesService.debugInstance = null;
    AffiliateService.debugSessionToken = null;
    SharedHttpClient.debugOverride = null;
  });

  testWidgets(
      'choosing accounts never sends: the pickers and the flip only change '
      'the route, tracked with from, to and reversed', (tester) async {
    final c = await _open(tester, const MoneyMovementRoute(_d, _b));
    expect(find.byKey(const ValueKey('money-movement-sheet')), findsOneWidget);
    expect(_last('move_sheet_opened')['entry_source'], 'portfolio');
    expect(_last('move_sheet_opened')['surface'], 'money_movement');

    // From: Predictions, in the sheet's own picker chrome.
    await tester.tap(find.text('Dollars').first);
    await _frames(tester);
    expect(find.text('Move from'), findsOneWidget);
    expect(find.text('SELECTED'), findsOneWidget);
    await tester
        .tap(find.byKey(const ValueKey('movement-account-predictions')));
    await _frames(tester);
    expect(
        _last('move_direction_changed'), containsPair('from', 'predictions'));
    expect(_last('move_direction_changed')['to'], 'bitcoin');
    expect(_last('move_direction_changed')['reversed'], false);

    // The flip.
    await tester.tap(find.byIcon(Icons.swap_vert_rounded));
    await _frames(tester);
    expect(_last('move_direction_changed')['from'], 'bitcoin');
    expect(_last('move_direction_changed')['to'], 'predictions');
    expect(_last('move_direction_changed')['reversed'], true);

    await _type(tester, '5');
    expect(_railCalls, 0);
    expect(_approvals.intents, isEmpty);
    await _close(tester, c);
  });

  testWidgets(
      'an own-account door pins the route: Dollars to Bitcoin, each end by '
      'its account\'s name, "Move money" over "Move \$5", no pickers, no '
      'flip, and the move still runs', (tester) async {
    final c = await _open(tester, const MoneyMovementRoute(_d, _b),
        pinned: true);
    expect(find.text('Dollars'), findsOneWidget);
    expect(find.text('Investments'), findsNothing);
    expect(find.text('Bitcoin'), findsOneWidget);
    expect(find.text('Move money'), findsOneWidget);
    expect(find.textContaining('Swap'), findsNothing);
    expect(find.textContaining('Buy'), findsNothing);
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);
    expect(find.byIcon(Icons.swap_vert_rounded), findsNothing);
    // Tapping an end picks nothing.
    await tester.tap(find.text('Dollars').first);
    await _frames(tester);
    expect(find.text('Move from'), findsNothing);
    await _type(tester, '5');
    expect(_button(tester).text, r'Move $5');
    await _confirm(tester);
    expect(_railCalls, 1);
    await _close(tester, c);
  });

  testWidgets(
      'the Goals nudge\'s door: Bitcoin to Dollars, pinned, the dollars it '
      'asked for filled in once the price is up', (tester) async {
    final c = await _open(tester, const MoneyMovementRoute(_b, _d),
        pinned: true, initialTargetUsd: 5);
    expect(find.text('Move money'), findsOneWidget);
    expect(find.byIcon(Icons.swap_vert_rounded), findsNothing);
    expect(_button(tester).text, r'Move $5');
    await _close(tester, c);
  });

  group('every pair runs on its own rail, from the selected account only', () {
    for (final route in MoneyMovementRoute.offered) {
      testWidgets('$route', (tester) async {
        final c = await _open(tester, route);
        await _type(tester, '5');
        expect(_button(tester).onPressed, isNotNull,
            reason: 'a \$5 move of a \$20 balance');
        await _confirm(tester);
        final plan = moneyMovementPlanFor(route);

        // One rail, one approval, for the spending wallet.
        expect(_railCalls, 1, reason: 'nothing else was asked to pay');
        expect(_approvals.intents,
            hasLength(route == const MoneyMovementRoute(_b, _d) ? 0 : 1));
        for (final intent in _approvals.intents) {
          expect(intent.walletId, 'spending');
        }
        switch (plan.rail) {
          case MoneyMovementRail.orchestra:
            if (route == const MoneyMovementRoute(_b, _d)) {
              // The shared Bitcoin → Dollars leg, sized by the typed $5.
              expect(_btcToDollars.single, closeTo(5, 0.001));
            } else if (route.to == _i && route.from != _p) {
              // Into Investing: the native deposit, in the source's own
              // units (sats, or six-decimal dollars).
              final deposit = _hypercore.deposits.single;
              expect(
                  deposit.asset,
                  route.from == _b
                      ? SparkFundingAsset.bitcoin
                      : SparkFundingAsset.dollars);
              expect(deposit.amount,
                  route.from == _b ? BigInt.from(5000) : BigInt.from(5000000));
            } else {
              final run = _runner.plans.single;
              expect(run.flow, plan.flow);
              expect(run.route.label, plan.quoteRoute.label);
              expect(run.sourceAccount, plan.source);
              expect(run.destinationAccount, plan.destination);
              expect(run.walletId, 'spending');
              expect(run.amountUsd, closeTo(5, 0.001));
            }
          case MoneyMovementRail.hypercoreNativeThenCctp:
            if (route.to == _p) {
              // Native HyperCore straight to the own Predictions account.
              expect(_hypercore.toPredictions.single, 5);
              expect(_cctp.moves, isEmpty);
              break;
            }
            final w = _hypercore.withdrawals.single;
            expect(w.usd, 5);
            expect(
                w.destination,
                route.to == _d
                    ? SparkFundingAsset.dollars
                    : SparkFundingAsset.bitcoin);
          case MoneyMovementRail.cctp:
            final m = _cctp.moves.single;
            expect(m.destination, InvestingWithdrawalDestination.predictions);
            expect(m.usd, 5);
        }
        // Submitted with the route's analytics.
        final submitted = _last('move_submitted');
        expect(submitted['surface'], 'money_movement');
        expect(submitted['from'], route.from.name);
        expect(submitted['to'], route.to.name);
        expect(submitted['route'], plan.railCode);
        expect(submitted['amount_usd'], closeTo(5, 0.001));
        // In flight: the sheet holds, nothing can be edited.
        expect(_button(tester).isLoading, isTrue);
        await _close(tester, c);
      });
    }
  });

  testWidgets(
      'a dollar balance that grows before the tap still sends the typed '
      'amount, never the share it was of the old balance', (tester) async {
    final c = await _open(tester, const MoneyMovementRoute(_d, _p));
    await _type(tester, '10');
    _dollars = 30;
    c.invalidate(usdBalanceProvider);
    await _frames(tester);
    await _confirm(tester);
    expect(_runner.plans.single.amountUsd, 10);
    await _close(tester, c);
  });

  testWidgets(
      'a bitcoin balance that grows before the tap still sends the sats the '
      'typed dollars buy', (tester) async {
    final c = await _open(tester, const MoneyMovementRoute(_b, _i));
    await _type(tester, '10');
    _setSats(c, 30000);
    await _frames(tester);
    await _confirm(tester);
    expect(_hypercore.deposits.single.amount, BigInt.from(10000));
    await _close(tester, c);
  });

  testWidgets(
      'the plain Buy dollars door sends the typed amount after the balance '
      'grew too (the stale share was its bug as well)', (tester) async {
    final c = await _open(tester, const MoneyMovementRoute(_d, _b));
    // Close the movement sheet and open the legacy door on the same
    // providers.
    _nav.currentState!.pop();
    await _frames(tester);
    unawaited(_nav.currentState!.push(MaterialPageRoute<void>(
        builder: (_) =>
            const DepositSheet(lockedSide: MoveLockedSide.depositToUsd))));
    await _frames(tester, 12);
    await _type(tester, '10');
    _setSats(c, 30000);
    await _frames(tester);
    await _confirm(tester);
    expect(_btcToDollars.single, closeTo(10, 0.001));
    await _close(tester, c);
  });

  testWidgets(
      'only the selected account pays: more than Dollars hold is refused, '
      'never topped up from another balance', (tester) async {
    _dollars = 3;
    final c = await _open(tester, const MoneyMovementRoute(_d, _b));
    await _type(tester, '5');
    expect(find.text('Insufficient balance'), findsWidgets);
    expect(_button(tester).onPressed, isNull);
    await tester.tap(_cta, warnIfMissed: false);
    await _frames(tester);
    expect(_railCalls, 0);
    await _close(tester, c);
  });

  testWidgets(
      'locked before the first await: a slow Predictions account takes one '
      'tap, and neither a second tap nor the route can change meanwhile',
      (tester) async {
    _proxyKnown = false;
    _deposit = Completer<String?>();
    final c = await _open(tester, const MoneyMovementRoute(_d, _p));
    await _type(tester, '5');
    await tester.tap(_cta);
    await tester.pump();
    expect(_button(tester).isLoading, isTrue);
    await tester.tap(_cta, warnIfMissed: false);
    await tester.tap(find.byIcon(Icons.swap_vert_rounded), warnIfMissed: false);
    await tester.tap(find.text('9').last, warnIfMissed: false);
    await _frames(tester);
    expect(
        tester
            .widget<BigAmountDisplay>(find.byType(BigAmountDisplay))
            .amountText,
        '5');
    _deposit!.complete(_pmWallet);
    await _frames(tester);
    expect(_runner.plans, hasLength(1));
    expect(_runner.plans.single.route.label, 'spark_usdb>polygon_usdc.e');
    await _close(tester, c);
  });

  testWidgets(
      'a wallet switch while an address is read stops the move before it '
      'reaches any rail, and says what changed', (tester) async {
    final address = Completer<String?>();
    final c = await _open(tester, const MoneyMovementRoute(_i, _b),
        hlAddress: address);
    await _type(tester, '5');
    await tester.tap(_cta);
    await tester.pump();
    final settings = c.read(settingsProvider.notifier);
    settings.state = settings.state.copyWith(activeWalletId: 'other');
    address.complete(_hlAccount);
    await _frames(tester);
    expect(_hypercore.withdrawals, isEmpty);
    expect(_approvals.intents, isEmpty);
    expect(find.text(_changed), findsWidgets);
    expect(_button(tester).onPressed, isNull);
    expect(_last('move_failed')['reason'], 'wallet_changed');
    // Back on the spending wallet: a fresh Retry, nothing sent before.
    settings.state = settings.state.copyWith(activeWalletId: 'spending');
    await _frames(tester);
    expect(_button(tester).text, 'Retry');
    await _close(tester, c);
  });

  testWidgets(
      'a wallet switch while the approval is up revokes it: nothing is '
      'funded', (tester) async {
    final c = await _open(tester, const MoneyMovementRoute(_p, _b));
    await _type(tester, '5');
    final settings = c.read(settingsProvider.notifier);
    _approvals.whileUp =
        () => settings.state = settings.state.copyWith(activeWalletId: 'other');
    await _confirm(tester);
    expect(_approvals.intents, hasLength(1));
    expect(_runner.plans, hasLength(1));
    expect(find.text(_changed), findsWidgets);
    expect(_last('move_failed')['reason'], 'wallet_changed');
    expect(_last('move_failed')['locked'], false);
    await _close(tester, c);
  });

  testWidgets('a declined approval resets quietly: no error, no Retry',
      (tester) async {
    final c = await _open(tester, const MoneyMovementRoute(_d, _i));
    await _type(tester, '5');
    _approvals.approve = false;
    await _confirm(tester);
    expect(_hypercore.deposits, hasLength(1));
    expect(_button(tester).isLoading, isFalse);
    expect(_button(tester).text, isNot('Retry'));
    expect(_button(tester).onPressed, isNotNull);
    expect(_last('move_failed')['reason'], 'approval_declined');
    await _close(tester, c);
  });

  testWidgets(
      'a stop that proves nothing left offers Retry, which asks again and is '
      'tracked as a retry', (tester) async {
    final c = await _open(tester, const MoneyMovementRoute(_p, _b));
    await _type(tester, '5');
    _runner.afterApproval = (_) async =>
        throw const SettlementStopped(SettlementStopReason.quoteExpired);
    await _confirm(tester);
    expect(_button(tester).text, 'Retry');
    expect(_button(tester).onPressed, isNotNull);
    expect(_last('move_failed')['reason'], 'not_sent');
    expect(_last('move_failed')['locked'], false);
    _runner.afterApproval = null;
    await _confirm(tester);
    expect(_runner.plans, hasLength(2));
    expect(_approvals.intents, hasLength(2));
    expect(_last('move_submitted')['retried'], true);
    await _close(tester, c);
  });

  testWidgets(
      'a Predictions move asks for the account setup first; a setup that '
      'cannot read Polygon stops it before any quote, named, with Retry',
      (tester) async {
    final c = await _open(tester, const MoneyMovementRoute(_p, _b));
    await _type(tester, '5');
    _setupFailure =
        const PolymarketReadException('eth_getCode: no Polygon RPC answered');
    await _confirm(tester);
    expect(_setupAsked, 1);
    expect(_runner.plans, isEmpty, reason: 'nothing was quoted or sent');
    expect(
        find.text("Predictions couldn't be reached right now. Nothing was "
            'sent. Check your connection and try again.'),
        findsOneWidget);
    expect(_button(tester).text, 'Retry');
    expect(_last('move_failed')['reason'], 'not_sent');
    // The read works again: the same tap goes through.
    _setupFailure = null;
    await _confirm(tester);
    expect(_setupAsked, 2);
    expect(_runner.plans, hasLength(1));
    await _close(tester, c);
  });

  testWidgets(
      'a live balance that cannot be read stops a Predictions move before '
      'the quote, as unreachable, never as insufficient', (tester) async {
    final c = await _open(tester, const MoneyMovementRoute(_p, _b));
    await _type(tester, '5');
    _readFailure =
        const PolymarketReadException('eth_call: no Polygon RPC answered');
    await _confirm(tester);
    expect(_runner.plans, isEmpty, reason: 'nothing was quoted or sent');
    expect(
        find.text("Predictions couldn't be reached right now. Nothing was "
            'sent. Check your connection and try again.'),
        findsOneWidget);
    expect(find.text('Insufficient balance'), findsNothing);
    expect(_button(tester).text, 'Retry');
    _readFailure = null;
    await _confirm(tester);
    expect(_runner.plans, hasLength(1));
    await _close(tester, c);
  });

  testWidgets(
      'an unknown outcome locks the move: no second send, no edits, and the '
      'button opens Activity', (tester) async {
    final c = await _open(tester, const MoneyMovementRoute(_p, _b));
    await _type(tester, '5');
    _runner.afterApproval =
        (_) async => throw const SettlementFundingUnknown('op', 'timeout');
    await _confirm(tester);
    expect(find.text(_unknownCopy), findsOneWidget);
    expect(_button(tester).text, 'Activity');
    final failed = _last('move_failed');
    expect(failed['reason'], 'unknown_outcome');
    expect(failed['locked'], true);
    expect(failed['surface'], 'money_movement');
    // No edits.
    await tester.tap(find.text('9').last, warnIfMissed: false);
    await tester.tap(find.byIcon(Icons.swap_vert_rounded), warnIfMissed: false);
    await _frames(tester);
    expect(
        tester
            .widget<BigAmountDisplay>(find.byType(BigAmountDisplay))
            .amountText,
        '5');
    // The button opens Activity; the move is never sent again.
    await tester.tap(_cta);
    await tester.pump();
    expect(_last('activity_history_opened')['entry_source'],
        'money_movement_lock');
    expect(_runner.plans, hasLength(1));
    tester.takeException();
    await _close(tester, c);
    tester.takeException();
  });

  testWidgets(
      'Investing → Bitcoin: native first; a refused route goes by CCTP to '
      'the same destination, tracked with route cctp', (tester) async {
    final c = await _open(tester, const MoneyMovementRoute(_i, _b));
    await _type(tester, '5');
    _hypercore.refusal = OrchestraQuoteFailure(
        'HyperCore source routes require independent deposit verification '
        'and are unavailable',
        routeError: RouteQuoteError(
            RouteQuoteErrorCode.fromCode('unsupported_route')!));
    await _confirm(tester);
    expect(_hypercore.withdrawals.single.usd, 5);
    expect(
        _cctp.moves.single.destination, InvestingWithdrawalDestination.bitcoin);
    expect(_approvals.intents, hasLength(1));
    await _close(tester, c);
  });

  testWidgets(
      'Investing → Bitcoin: a stop that is not a route refusal never opens '
      'CCTP', (tester) async {
    final c = await _open(tester, const MoneyMovementRoute(_i, _b));
    await _type(tester, '5');
    _hypercore.refusal = const HypercoreFundingUnavailable(
        HypercoreFundingUnavailableReason.paused);
    await _confirm(tester);
    expect(_cctp.moves, isEmpty);
    expect(_button(tester).text, 'Retry');
    await _close(tester, c);
  });

  testWidgets(
      'Investing → Predictions: native first; a refused route goes by CCTP '
      'to Predictions, closes the sheet and is tracked with route cctp',
      (tester) async {
    _cctp.result = CctpWithdrawalResult(
        operationId: 'op',
        sentUsd: 5,
        arrivingUsdEstimate: 4.8,
        registration: Completer<String?>().future);
    final c = await _open(tester, const MoneyMovementRoute(_i, _p));
    await _type(tester, '5');
    _hypercore.refusal = const SettlementStopped(
        SettlementStopReason.routeUnavailable,
        routeReason: RouteUnavailableReason.pairMissing);
    await _confirm(tester);
    await _frames(tester, 20);
    expect(_hypercore.toPredictions.single, 5);
    expect(_cctp.moves.single.destination,
        InvestingWithdrawalDestination.predictions);
    expect(_cctp.moves.single.usd, 5);
    expect(_approvals.intents, hasLength(1));
    // The CCTP arrival converts to pUSD like any other deposit.
    expect(_arrivalWatches, 1);
    expect(find.byKey(const ValueKey('money-movement-sheet')), findsNothing);
    final completed = _last('move_completed');
    expect(completed['route'], 'cctp');
    expect(completed['surface'], 'money_movement');
    expect(completed['ms'], isA<int>());
    expect(_last('hyperliquid_withdraw_step')['step'], 'cctp_fallback');
    final submitted = _last('hyperliquid_withdraw_submitted');
    expect(submitted['route'], 'cctp');
    expect(submitted['destination'], 'predictions');
    expect(_all('hyperliquid_withdraw_initiated'), hasLength(1));
    tester.takeException();
    await _close(tester, c);
  });

  testWidgets(
      'Investing → Predictions: Flashnet\'s unsupported_route opens CCTP too',
      (tester) async {
    final c = await _open(tester, const MoneyMovementRoute(_i, _p));
    await _type(tester, '5');
    _hypercore.refusal = OrchestraQuoteFailure(
        'HyperCore source routes require independent deposit verification '
        'and are unavailable',
        routeError: RouteQuoteError(
            RouteQuoteErrorCode.fromCode('unsupported_route')!));
    await _confirm(tester);
    expect(_hypercore.toPredictions.single, 5);
    expect(_cctp.moves.single.destination,
        InvestingWithdrawalDestination.predictions);
    await _close(tester, c);
  });

  testWidgets(
      'Investing → Predictions by CCTP: a cash shortfall found after the '
      'approval is a proven stop with Retry, never the unknown-outcome lock',
      (tester) async {
    final c = await _open(tester, const MoneyMovementRoute(_i, _p));
    await _type(tester, '5');
    _hypercore.refusal = const SettlementStopped(
        SettlementStopReason.routeUnavailable,
        routeReason: RouteUnavailableReason.pairMissing);
    // Perpetuals came up a cent short between the read and the burn: the
    // send refused before the POST, with the approval already given.
    _cctp.error = SettlementFundingRefused(HypercoreBalanceShortfall());
    await _confirm(tester);
    await _frames(tester, 20);
    expect(_cctp.moves.single.destination,
        InvestingWithdrawalDestination.predictions);
    expect(_approvals.intents, hasLength(1));
    expect(find.text('Insufficient balance'), findsWidgets);
    expect(find.text(_unknownCopy), findsNothing);
    expect(_button(tester).text, 'Retry');
    expect(_button(tester).onPressed, isNotNull);
    final failed = _last('move_failed');
    expect(failed['reason'], 'not_sent');
    expect(failed['locked'], false);
    expect(failed['error_category'], 'insufficient_funds');
    final withdrawFailed = _last('hyperliquid_withdraw_failed');
    expect(withdrawFailed['reason'], 'insufficient_funds');
    expect(withdrawFailed['route'], 'cctp');
    // Edits are open again: the amount can change for the Retry.
    await tester.tap(find.text('1').last);
    await _frames(tester, 4);
    expect(
        tester
            .widget<BigAmountDisplay>(find.byType(BigAmountDisplay))
            .amountText,
        '51');
    await _close(tester, c);
  });

  testWidgets(
      'Investing → Predictions: a policy denial, a decline or an expiry on '
      'the native route never opens CCTP', (tester) async {
    final denial = capabilityDenialFromResponse(403,
        '{"error":"feature_unavailable","capability":"polymarket.deposit",'
        '"reason":"country_blocked"}')!;
    for (final refusal in <Object>[
      OrchestraQuoteFailure('unsupported_route', denial: denial),
      const SettlementStopped(SettlementStopReason.quoteExpired),
      const HypercoreFundingUnavailable(
          HypercoreFundingUnavailableReason.paused),
    ]) {
      _cctp = _Cctp();
      final c = await _open(tester, const MoneyMovementRoute(_i, _p));
      await _type(tester, '5');
      _hypercore.refusal = refusal;
      await _confirm(tester);
      expect(_hypercore.toPredictions.single, 5, reason: '$refusal');
      expect(_cctp.moves, isEmpty, reason: '$refusal');
      expect(_last('hyperliquid_withdraw_failed')['route'], 'direct');
      await _close(tester, c);
    }
    // A declined approval on the native route: quiet, and no CCTP.
    _cctp = _Cctp();
    final c = await _open(tester, const MoneyMovementRoute(_i, _p));
    await _type(tester, '5');
    _approvals.approve = false;
    await _confirm(tester);
    expect(_hypercore.toPredictions.single, 5);
    expect(_cctp.moves, isEmpty);
    expect(_last('move_failed')['reason'], 'approval_declined');
    await _close(tester, c);
  });

  group('the fee line prices the route that runs', () {
    testWidgets(
        'Investing → Predictions prices its native route, to the own '
        'Predictions account', (tester) async {
      final c = await _open(tester, const MoneyMovementRoute(_i, _p));
      await _type(tester, '5');
      await _frames(tester, 12);
      final asked = _estimates.where((q) =>
          q['sourceChain'] == 'hypercore' &&
          q['sourceAsset'] == 'USDC' &&
          q['destinationChain'] == 'polygon' &&
          q['destinationAsset'] == 'USDC.e');
      expect(asked, isNotEmpty);
      expect(asked.last['amount'], '500000000');
      expect(asked.last['recipientAddress'], _pmWallet);
      expect(find.textContaining('Included in the amount you receive'),
          findsNothing);
      await _close(tester, c);
    });

    testWidgets(
        'Investing → Predictions on a live catalogue without the pair (the '
        'move runs on CCTP) shows no Orchestra estimate for itself',
        (tester) async {
      final c = await _open(tester, const MoneyMovementRoute(_i, _p),
          catalog: OrchestraRoutesCatalog.fromJson({
            'assets': [
              _row('hypercore', 'USDC', decimals: 8),
              _row('polygon', 'USDC.e'),
              _row('spark', 'BTC', decimals: 8),
            ],
          }, source: OrchestraCatalogSource.live, fetchedAt: DateTime.now()));
      await _type(tester, '5');
      await _frames(tester, 12);
      expect(find.textContaining('Included in the amount you receive'),
          findsOneWidget);
      expect(
          _estimates.where((q) =>
              q['sourceChain'] == 'hypercore' &&
              q['destinationChain'] == 'polygon'),
          isEmpty);
      await _close(tester, c);
    });

    testWidgets(
        'out of Predictions only Bitcoin is offered: asked for Investing, '
        'the sheet opens on Bitcoin, prices that route and the picker '
        'lists no other door', (tester) async {
      final c = await _open(tester, const MoneyMovementRoute(_p, _i));
      await _type(tester, '5');
      await _frames(tester, 12);
      expect(
          _estimates.where((q) =>
              q['sourceChain'] == 'polygon' && q['destinationChain'] == 'hypercore'),
          isEmpty);
      final asked = _estimates.where((q) =>
          q['sourceChain'] == 'polygon' &&
          q['sourceAsset'] == 'USDC.e' &&
          q['destinationChain'] == 'spark' &&
          q['destinationAsset'] == 'BTC');
      expect(asked, isNotEmpty);
      expect(asked.last['amount'], '5000000');
      // The destination picker: Bitcoin, already selected, and nothing else.
      await tester.tap(find.text('Bitcoin').first);
      await _frames(tester);
      expect(find.text('Move to'), findsOneWidget);
      expect(find.byKey(const ValueKey('movement-account-bitcoin')),
          findsOneWidget);
      expect(find.text('SELECTED'), findsOneWidget);
      expect(find.byKey(const ValueKey('movement-account-dollars')),
          findsNothing);
      expect(find.byKey(const ValueKey('movement-account-investing')),
          findsNothing);
      expect(find.byKey(const ValueKey('movement-account-predictions')),
          findsNothing);
      await tester.tap(find.byKey(const ValueKey('movement-account-bitcoin')),
          warnIfMissed: false);
      await _frames(tester);
      // Picking Predictions as the source while Dollars is the destination
      // brings its one door along: the route becomes Predictions → Bitcoin.
      await _close(tester, c);
      final c2 = await _open(tester, const MoneyMovementRoute(_i, _d));
      await tester.tap(find.text('Investing').first);
      await _frames(tester);
      await tester
          .tap(find.byKey(const ValueKey('movement-account-predictions')));
      await _frames(tester);
      expect(_last('move_direction_changed')['from'], 'predictions');
      expect(_last('move_direction_changed')['to'], 'bitcoin');
      await _close(tester, c2);
    });

    testWidgets('Bitcoin → Predictions prices sats on its own route',
        (tester) async {
      final c = await _open(tester, const MoneyMovementRoute(_b, _p));
      await _type(tester, '5');
      await _frames(tester, 12);
      final asked = _estimates.where((q) =>
          q['sourceChain'] == 'spark' &&
          q['sourceAsset'] == 'BTC' &&
          q['destinationChain'] == 'polygon' &&
          q['amount'] == '5000');
      expect(asked, isNotEmpty);
      await _close(tester, c);
    });
  });

  testWidgets('Max and the quick chips are tracked with the surface',
      (tester) async {
    final c = await _open(tester, const MoneyMovementRoute(_p, _b));
    await tester.tap(find.text('Max').last);
    await _frames(tester);
    final tap = _last('move_amount_percent_tapped');
    expect(tap['chip'], 'max');
    expect(tap['surface'], 'money_movement');
    expect(_all('move_amount_percent_tapped'), hasLength(1));
    await _close(tester, c);
  });

  group('a route the policy withholds says so, as Predictions does', () {
    const regionCopy =
        "This feature is restricted in the region your internet connection "
        "appears to be in. If this isn't where you are, check your VPN "
        'settings.';
    const moveFailure =
        'The move could not be completed. Check its status before trying '
        'again.';
    late Set<String> blocked;
    late InvestmentProviderAvailability venues;

    setUp(() {
      blocked = {'hyperliquid.deposit'};
      RuntimeCapabilitiesService.debugInstance?.dispose();
      RuntimeCapabilitiesService.debugInstance = runtimePolicyFixture(
          blocked: blocked,
          reasons: const {
            'hyperliquid.deposit': 'country_blocked',
            'polymarket.deposit': 'country_blocked',
          });
      venues = InvestmentProviderAvailability(
        client: MockClient((request) async => request.url.host ==
                'api.hyperliquid.xyz'
            ? http.Response(
                '{"acceptedTerms":true,"userAllowed":true,"restrictions":"n"}',
                200)
            : http.Response('{"blocked":false}', 200)),
        report: ({
          required String venue,
          required String trigger,
          required bool changed,
          required String result,
        }) {},
      );
      RegionFreshness.debugVenues = venues;
    });
    tearDown(() {
      RegionFreshness.debugVenues = null;
      venues.dispose();
    });

    Finder restricted() =>
        find.byKey(const ValueKey('money-movement-restricted'));

    testWidgets(
        'Dollars → Investing with hyperliquid.deposit withheld: the region '
        'copy in place of the fee line, no estimate, no move, and the '
        'button is Check connection, never Retry', (tester) async {
      final c = await _open(tester, const MoneyMovementRoute(_d, _i));
      await _type(tester, '10');
      await _frames(tester, 12);
      expect(restricted(), findsOneWidget);
      expect(find.text(regionCopy), findsOneWidget);
      expect(find.text(moveFailure), findsNothing);
      expect(find.textContaining('Estimate unavailable'), findsNothing);
      expect(_button(tester).text, 'Check connection');
      expect(_button(tester).text, isNot('Retry'));
      expect(
          _estimates.where((q) => q['destinationChain'] == 'hypercore'),
          isEmpty,
          reason: 'a withheld route asks for no estimate');
      expect(_last('hyperliquid_geoblocked_shown'), isNotNull);

      // Still restricted after the check: nothing is sent, the copy stays.
      await tester.tap(_cta);
      await _frames(tester, 12);
      expect(_railCalls, 0);
      expect(_approvals.intents, isEmpty);
      expect(find.text(regionCopy), findsOneWidget);
      expect(_button(tester).text, 'Check connection');

      // The policy gives it back (a VPN change): Check connection lifts it
      // without reopening, and the button is the move again.
      blocked.clear();
      await tester.tap(_cta);
      await _frames(tester, 12);
      expect(restricted(), findsNothing);
      // The person's own money moves: "Move $10", never "Buy".
      expect(_button(tester).text, r'Move $10');
      await _confirm(tester);
      expect(_hypercore.deposits, hasLength(1));
      await _close(tester, c);
    });

    testWidgets(
        'Investing → Dollars still moves while only the deposit is withheld',
        (tester) async {
      final c = await _open(tester, const MoneyMovementRoute(_i, _d));
      await _type(tester, '5');
      expect(restricted(), findsNothing);
      expect(_button(tester).onPressed, isNotNull);
      await _confirm(tester);
      expect(_hypercore.withdrawals.single.usd, 5);
      await _close(tester, c);
    });

    testWidgets(
        'Investing → Predictions with polymarket.deposit withheld: restricted '
        'before the tap, no CCTP move', (tester) async {
      blocked
        ..clear()
        ..add('polymarket.deposit');
      final c = await _open(tester, const MoneyMovementRoute(_i, _p));
      await _type(tester, '2');
      await _frames(tester, 12);
      expect(find.text(regionCopy), findsOneWidget);
      expect(find.textContaining("This transfer isn't available"), findsNothing);
      expect(_button(tester).text, 'Check connection');
      await tester.tap(_cta);
      await _frames(tester, 12);
      expect(_cctp.moves, isEmpty);
      expect(_railCalls, 0);
      await _close(tester, c);
    });

    testWidgets(
        "a withheld route that isn't a region refusal disables the button",
        (tester) async {
      RuntimeCapabilitiesService.debugInstance?.dispose();
      RuntimeCapabilitiesService.debugInstance =
          runtimePolicyFixture(blocked: {'hyperliquid.deposit'});
      final c = await _open(tester, const MoneyMovementRoute(_d, _i));
      await _type(tester, '10');
      await _frames(tester, 12);
      expect(restricted(), findsOneWidget);
      expect(
          find.text('This feature is currently unavailable in Kute.'),
          findsOneWidget);
      expect(_button(tester).onPressed, isNull);
      expect(_button(tester).text, isNot('Retry'));
      expect(_last('feature_unavailable_shown')['capability'],
          'hyperliquid.deposit');
      await _close(tester, c);
    });

    testWidgets(
        "the backend's 403 policy denial of the quote reads as the "
        'restriction, never moveFailure, tracked as restricted',
        (tester) async {
      blocked.clear();
      final c = await _open(tester, const MoneyMovementRoute(_d, _p));
      await _type(tester, '5');
      _runner.afterApproval = (_) async => throw OrchestraQuoteFailure(
          'feature_unavailable',
          denial: capabilityDenialFromResponse(
              403,
              jsonEncode({
                'error': 'feature_unavailable',
                'capability': 'polymarket.deposit',
                'reason': 'country_blocked',
                'revision': 7,
              })));
      await _confirm(tester);
      await _frames(tester, 6);
      expect(find.text(moveFailure), findsNothing);
      expect(find.text(regionCopy), findsOneWidget);
      expect(_button(tester).text, 'Check connection');
      final failed = _last('move_failed');
      expect(failed['error_category'], 'restricted');
      expect(failed['reason'], 'restricted');
      expect(failed['capability'], 'polymarket.deposit');
      await _close(tester, c);
    });
  });

  // Gating audit (fw36, v2.2): the Send chips and Receive cards that open
  // this sheet pinned, read against a real backend policy. "To Dollars"
  // (Bitcoin Send) and "From your Bitcoin" (Dollars Receive) are a swap:
  // a swap block stops them, a region block naming its regions over the
  // one VPN sentence. "To your Bitcoin" (Dollars Send) and "From your
  // Dollars" (Bitcoin Receive or swap) are an exit: a COUNTRY block on
  // the swap master never stops them (the backend exempts the route from
  // country rules); the master off, a platform rule or coming soon still
  // does, exactly as the backend's operation guard refuses it then.
  group('Send chips and Receive cards under a backend block (fw36)', () {
    late InvestmentProviderAvailability venues;

    setUp(() {
      venues = InvestmentProviderAvailability(
        client: MockClient((request) async => request.url.host ==
                'api.hyperliquid.xyz'
            ? http.Response(
                '{"acceptedTerms":true,"userAllowed":true,"restrictions":"n"}',
                200)
            : http.Response('{"blocked":false}', 200)),
        report: ({
          required String venue,
          required String trigger,
          required bool changed,
          required String result,
        }) {},
      );
      RegionFreshness.debugVenues = venues;
    });
    tearDown(() {
      RegionFreshness.debugVenues = null;
      venues.dispose();
    });

    Future<void> install(WidgetTester tester, MarketDenial how,
        {Set<String> targets = const {}}) async {
      RuntimeCapabilitiesService.debugInstance?.dispose();
      RuntimeCapabilitiesService.debugInstance = null;
      await tester
          .runAsync(() => installMarketGatingPolicy(how, targets: targets));
    }

    Finder restricted() =>
        find.byKey(const ValueKey('money-movement-restricted'));

    testWidgets(
        'swap country block: To Dollars / From your Bitcoin (Bitcoin → '
        'Dollars) names the regions over the VPN sentence, Check '
        'connection, nothing sent', (tester) async {
      await install(tester, MarketDenial.swapCountryBlock);
      final c =
          await _open(tester, const MoneyMovementRoute(_b, _d), pinned: true);
      await _type(tester, '5');
      await _frames(tester, 12);
      expect(restricted(), findsOneWidget);
      expect(
          find.text('$kGatingNamedTitle\n$kGatingVpnSentence'), findsOneWidget);
      expect(find.textContaining('use a VPN'), findsNothing);
      expect(_button(tester).text, 'Check connection');
      await tester.tap(_cta);
      await _frames(tester, 12);
      expect(_btcToDollars, isEmpty);
      expect(_railCalls, 0);
      await _close(tester, c);
    });

    testWidgets(
        'swap country block: To your Bitcoin / From your Dollars (Dollars → '
        'Bitcoin) is an exit and moves', (tester) async {
      await install(tester, MarketDenial.swapCountryBlock);
      final c =
          await _open(tester, const MoneyMovementRoute(_d, _b), pinned: true);
      await _type(tester, '5');
      await _frames(tester, 12);
      expect(restricted(), findsNothing);
      expect(_button(tester).onPressed, isNotNull);
      await _confirm(tester);
      expect(_railCalls, 1);
      await _close(tester, c);
    });

    testWidgets(
        'swap country block: Investing → Bitcoin (the withdrawal door) '
        'still moves', (tester) async {
      await install(tester, MarketDenial.swapCountryBlock);
      final c =
          await _open(tester, const MoneyMovementRoute(_i, _b), pinned: true);
      await _type(tester, '5');
      await _frames(tester, 12);
      expect(restricted(), findsNothing);
      await _confirm(tester);
      expect(_hypercore.withdrawals.single.usd, 5);
      await _close(tester, c);
    });

    for (final how in [
      MarketDenial.masterOff,
      MarketDenial.platform,
      MarketDenial.comingSoon,
    ]) {
      testWidgets(
          '${how.label} on the swap master: Bitcoin → Dollars and Dollars → '
          'Bitcoin both say why, the button cannot move', (tester) async {
        await install(tester, how, targets: {kSwapMaster});
        for (final route in const [
          MoneyMovementRoute(_b, _d),
          MoneyMovementRoute(_d, _b),
        ]) {
          final c = await _open(tester, route, pinned: true);
          await _type(tester, '5');
          await _frames(tester, 12);
          expect(restricted(), findsOneWidget, reason: '$route');
          expect(find.text(how.message), findsOneWidget, reason: '$route');
          expect(_button(tester).onPressed, isNull, reason: '$route');
          expect(_button(tester).text, isNot('Check connection'));
          expect(_railCalls, 0);
          expect(_btcToDollars, isEmpty);
          await _close(tester, c);
        }
      });
    }
  });

  // ─── fw46: the own-account doors spend all the dollar money ─────────
  //
  // Founder, 7 November 2026: "from your Dollars should and must be all
  // the available balances, not just the Dollars balance, it is the same
  // behaviour we had before on Investments buy Bitcoin". Both Dollars →
  // Bitcoin doors (the Bitcoin Receive's "From your Dollars", the Dollars
  // Send's "To your Bitcoin") open this one pinned move by the same call
  // (showOwnMoneyMove): its From row and Max are Dollars plus the venue
  // cash in reach, and it pays Dollars first, then the venues, under one
  // approval, as the Investments' Buy bitcoin did. The Portfolio's
  // unpinned Move money still spends only the account picked.
  group(
      'From your Dollars and To your Bitcoin spend all the dollar money, '
      "as the Investments' Buy bitcoin (fw46)", () {
    late _VenueCash predictions;
    late _VenueCash investing;
    late List<double> initialBuys;
    late List<double> finished;
    late bool finisherStopped;

    setUp(() {
      predictions = _VenueCash(OneBalanceVenue.predictions);
      investing = _VenueCash(OneBalanceVenue.investing);
      initialBuys = [];
      finished = [];
      finisherStopped = false;
      MultiSourceMoveStore.reset();
      PendingBitcoinPurchaseStore.reset();
    });

    /// The venues holding [p] (Predictions) and [i] (Investing), as the
    /// engine last read them and as they answer now, with the sheet's
    /// puller over them, the multi-source purchase's Dollars leg and the
    /// background finisher recorded instead of sent.
    List<Override> venues({double p = 0, double i = 0}) {
      predictions.available = p;
      investing.available = i;
      final puller = VenueCashPuller(
        walletId: () => 'spending',
        sources: [predictions, investing],
        readDollars: () => _dollars,
        minimumUsd: (venue) async => _venueMinimum(venue),
      );
      return [
        venueCashPullerProvider.overrideWith((_) => puller),
        venueCashLastReadProvider.overrideWith(
            (_) => (walletId: 'spending', candidates: _venueCash(p: p, i: i))),
        bitcoinPurchaseFanoutProvider.overrideWith((_) => BitcoinPurchaseFanout(
                buy: (usd, grant, id, onFunding) async {
              initialBuys.add(usd);
              onFunding();
              _dollars -= usd;
              return DollarsToBitcoinSent(
                  sentUsd: usd, registered: true, operationId: 'initial_$id');
            })),
        bitcoinPurchaseFinisherProvider.overrideWith((_) =>
            BitcoinPurchaseFinisher(
              readDollars: () => _dollars,
              buy: (usd, stepUp, {required moveId, required onFunding}) async {
                finished.add(usd);
                onFunding();
              },
              sleep: (_) async {
                if (finisherStopped) throw StateError('test over');
                await Future<void>.delayed(const Duration(milliseconds: 100));
              },
            )),
      ];
    }

    Future<void> done(WidgetTester tester, ProviderContainer c) async {
      finisherStopped = true;
      await _close(tester, c);
    }

    for (final (door, source) in [
      ('From your Dollars', kBitcoinReceiveDollarsSource),
      ('To your Bitcoin', kUsdWithdrawBitcoinRowSource),
    ]) {
      testWidgets(
          '$door: the From row and Max are Dollars plus the venue cash in '
          'reach (net of the move costs), and an amount past Dollars is '
          'not insufficient', (tester) async {
        _dollars = 10;
        final c = await _open(tester, const MoneyMovementRoute(_d, _b),
            overrides: venues(p: 60), ownMoveEntrySource: source);
        expect(_last('move_sheet_opened')['entry_source'], source);
        expect(find.text('Move money'), findsOneWidget);
        // $10 of Dollars and $60 of Predictions cash: 10 + 60 x 0.98, the
        // figure the engine's plan covers, the card's figure too.
        final reach = investmentsSpendable(
                dollarsUsd: 10, sources: _venueCash(p: 60))
            .maxUsd;
        expect(reach, closeTo(68.80, 1e-9));
        expect(find.text(r'$68.80'), findsOneWidget);
        expect(find.text(r'$10.00'), findsNothing);

        await tester.tap(find.text('Max').last);
        await _frames(tester);
        expect(_button(tester).text, r'Move $68.80');
        expect(find.text('Insufficient balance'), findsNothing);
        expect(_button(tester).onPressed, isNotNull);
        expect(_railCalls, 0);
        await done(tester, c);
      });
    }

    testWidgets(
        'it pays as the Investments\' Buy bitcoin did: one approval before '
        'anything moves, Dollars first in full, then Predictions, then '
        'Investing for the rest; the sheet closes once every leg is '
        'submitted and the rest is bought as it lands', (tester) async {
      _dollars = 10;
      final c = await _open(tester, const MoneyMovementRoute(_d, _b),
          overrides: venues(p: 15, i: 40),
          ownMoveEntrySource: kBitcoinReceiveDollarsSource);
      await _type(tester, '40');
      expect(find.text('Insufficient balance'), findsNothing);
      expect(_button(tester).text, r'Move $40');
      await _confirm(tester);
      await _frames(tester, 8);

      // One approval, for the whole purchase into the own Bitcoin, asked
      // before any venue cash moved.
      expect(_approvals.intents, hasLength(1));
      expect(_approvals.intents.single.action, SensitiveAction.moveTransfer);
      expect(_approvals.intents.single.destination, _ownSpark);
      // The plan the Investments' Buy bitcoin always made: Dollars first,
      // then the venues fastest first, each only for what is missing.
      final plan = planDollarsShortfall(
          neededUsd: 40, dollarsUsd: 10, sources: _venueCash(p: 15, i: 40));
      expect(plan.pulls.map((leg) => leg.venue),
          [OneBalanceVenue.predictions, OneBalanceVenue.investing]);
      expect(initialBuys, [10], reason: 'Dollars first, in full');
      expect(
          predictions.pulls, [plan.pullFrom(OneBalanceVenue.predictions)!.usd]);
      expect(predictions.pulls, [15]);
      expect(investing.pulls, [plan.pullFrom(OneBalanceVenue.investing)!.usd]);
      // No single-source purchase ran beside it.
      expect(_runner.plans, isEmpty);
      // One move, its Activity row, with the Dollars leg on it.
      final move = MultiSourceMoveStore.all().single;
      expect(move.isParallelPurchase, isTrue);
      expect(move.initialDollarsSentUsd, 10);
      // Submitted: the band snaps and the sheet is gone; the rest is
      // bought once it lands.
      await tester.pump(const Duration(milliseconds: 600));
      await _frames(tester);
      expect(find.byKey(const ValueKey('money-movement-sheet')), findsNothing);
      final completed = _last('move_completed');
      expect(completed['outcome'], 'purchase_queued');
      expect(completed['surface'], 'money_movement');
      expect(completed['from'], 'dollars');
      expect(completed['to'], 'bitcoin');
      expect(_last('move_submitted')['amount_usd'], closeTo(40, 1e-9));
      await done(tester, c);
    });

    testWidgets(
        'a venue whose withdraw a platform rule withholds is left out: not '
        'in the From row, no leg from it, the other venue covers the rest',
        (tester) async {
      RuntimeCapabilitiesService.debugInstance?.dispose();
      RuntimeCapabilitiesService.debugInstance = null;
      await tester.runAsync(() => installMarketGatingPolicy(
          MarketDenial.platform,
          targets: {'polymarket.withdraw'}));
      _dollars = 10;
      final c = await _open(tester, const MoneyMovementRoute(_d, _b),
          overrides: venues(p: 60, i: 40),
          ownMoveEntrySource: kUsdWithdrawBitcoinRowSource);
      // 10 + 40 x 0.98 - 0.30: Investing only.
      expect(find.text(r'$48.90'), findsOneWidget);
      await _type(tester, '30');
      await _confirm(tester);
      await _frames(tester, 8);
      expect(predictions.pulls, isEmpty);
      expect(investing.pulls, [
        planDollarsShortfall(
                neededUsd: 30, dollarsUsd: 10, sources: _venueCash(i: 40))
            .pullFrom(OneBalanceVenue.investing)!
            .usd
      ]);
      expect(initialBuys, [10]);
      await done(tester, c);
    });

    testWidgets(
        'with Dollars enough it buys from Dollars alone, as before: no '
        'venue leg, no venue approval', (tester) async {
      _dollars = 10;
      final c = await _open(tester, const MoneyMovementRoute(_d, _b),
          overrides: venues(p: 60),
          ownMoveEntrySource: kBitcoinReceiveDollarsSource);
      await _type(tester, '5');
      await _confirm(tester);
      expect(predictions.pulls, isEmpty);
      expect(initialBuys, isEmpty);
      // The single purchase from Dollars, on its own rail.
      expect(_runner.plans.single.flow, SettlementFlow.moveDollarsToBtc);
      expect(_runner.plans.single.amountUsd, closeTo(5, 1e-9));
      await done(tester, c);
    });

    testWidgets(
        "the Portfolio's Move money (unpinned) still spends only the "
        'account picked: Dollars alone, and past it is insufficient',
        (tester) async {
      _dollars = 10;
      final c = await _open(tester, const MoneyMovementRoute(_d, _b),
          overrides: venues(p: 60));
      expect(find.text(r'$10.00'), findsOneWidget);
      expect(find.text(r'$68.80'), findsNothing);
      await _type(tester, '30');
      expect(find.text('Insufficient balance'), findsOneWidget);
      expect(_button(tester).onPressed, isNull);
      expect(predictions.pulls, isEmpty);
      expect(_approvals.intents, isEmpty);
      await done(tester, c);
    });
  });
}
