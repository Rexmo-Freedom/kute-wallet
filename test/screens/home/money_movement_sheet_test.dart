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
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/screens/shared/money_movement_sheet.dart';
import 'package:kute/services/funding/hot_settlement.dart';
import 'package:kute/services/funding/settlement_runner.dart';
import 'package:kute/services/funding/settlement_store.dart';
import 'package:kute/services/funding/spark_hypercore_funding_service.dart';
import 'package:kute/services/http/shared_http_client.dart';
import 'package:kute/services/hyperliquid/cctp_withdrawal.dart';
import 'package:kute/services/one_balance/bitcoin_to_dollars_leg.dart'
    show BitcoinLegSent;
import 'package:kute/services/one_balance/dollars_to_bitcoin_minimum.dart';
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
  Future<BigInt> spendableMicroUsdc() async =>
      BigInt.from((_predictions * 1e6).round());

  @override
  Future<BigInt> payableMicroUsdc(double amount) async =>
      BigInt.from((amount * 1e6).round());
}

bool _proxyKnown = true;
Completer<String?>? _deposit;
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

// ─── harness ────────────────────────────────────────────────────────

Future<ProviderContainer> _open(WidgetTester tester, MoneyMovementRoute route,
    {Completer<String?>? hlAddress, OrchestraRoutesCatalog? catalog}) async {
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
  ]);
  _setSats(container, 20000); // $20.00 at the sample price.
  SharedHttpClient.debugOverride = _orchestra();
  await http.runWithClient(
    () => tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
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
  unawaited(showMoneyMovementSheet(_nav.currentContext!,
      initialSource: route.from, initialDestination: route.to));
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

Finder get _cta => find.byType(AppButton).last;
AppButton _button(WidgetTester tester) => tester.widget<AppButton>(_cta);

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

  group('every pair runs on its own rail, from the selected account only', () {
    for (final route in MoneyMovementRoute.all) {
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
    final c = await _open(tester, const MoneyMovementRoute(_p, _d));
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
      'an unknown outcome locks the move: no second send, no edits, and the '
      'button opens Activity', (tester) async {
    final c = await _open(tester, const MoneyMovementRoute(_p, _i));
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
        'Predictions → Investing asks for its own route, to the own '
        'Investing account', (tester) async {
      final c = await _open(tester, const MoneyMovementRoute(_p, _i));
      await _type(tester, '5');
      await _frames(tester, 12);
      final asked = _estimates.where((q) =>
          q['sourceChain'] == 'polygon' &&
          q['sourceAsset'] == 'USDC.e' &&
          q['destinationChain'] == 'hypercore' &&
          q['destinationAsset'] == 'USDC');
      expect(asked, isNotEmpty);
      expect(asked.last['amount'], '5000000');
      await _close(tester, c);
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
    final c = await _open(tester, const MoneyMovementRoute(_p, _d));
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
        "appears to be in. If that isn't where you are, check your network "
        'or VPN settings and try again.';
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
      expect(_button(tester).text, r'Move money $10');
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
}
