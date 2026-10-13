// Buy bitcoin from Investments: the From row shows what Investments can
// spend (Dollars plus the venue cash the engine reaches) on the first
// frame, from the last known values, with no loading state; Max is what
// the engine's plan covers; the venues are read again in the background
// and the figure follows. Past what Dollars hold the venue cash in reach
// counts, the purchase asks its ONE approval before any venue cash
// moves (declined: nothing moves), the legs then go under it (straight to
// Bitcoin where the venue offers it, home to Dollars otherwise), and when
// what comes home has not landed in time the purchase stops and says so
// (nothing is bought).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/orchestra_router.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/balance_model.dart';
import 'package:kute/models/breez/sdk_instance.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/breez_config_provider.dart';
import 'package:kute/providers/breez_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/spark_address_provider.dart';
import 'package:kute/screens/home/components/deposit_sheet.dart';
import 'package:kute/screens/shared/amount_keypad_panel.dart'
    show AmountKeypad, BigAmountDisplay;
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/services/funding/spark_hypercore_funding_service.dart';
import 'package:kute/services/http/shared_http_client.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider;
import 'package:kute/services/one_balance/investments_spendable.dart';
import 'package:kute/services/one_balance/multi_source_move.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/venue_cash_source.dart';
import 'package:kute/services/one_balance/venue_funder.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart' show Fixed;

import '../../helpers/runtime_policy_fixture.dart';

const _usdPerBtc = 100000.0;
const _balanceSats = 100000; // $100.00 at the sample price.
const _insufficient = 'Insufficient balance';

/// The Orchestra price sample for 100,000 sats at [usdPerBtc], in the
/// destination asset's own base units, answered after [delay].
MockClient _orchestra(
        {double usdPerBtc = _usdPerBtc, Duration delay = Duration.zero}) =>
    MockClient((request) async {
      if (!request.url.path.endsWith('/estimate')) {
        return http.Response('{}', 404);
      }
      await Future<void>.delayed(delay);
      final asset = request.url.queryParameters['destinationAsset']!;
      final chain = request.url.queryParameters['destinationChain']!;
      final out = doubleToOrchestraAmount(_balanceSats / 1e8 * usdPerBtc, asset,
          chain: chain);
      return http.Response(
          jsonEncode({'estimatedOut': out, 'feeAmount': '0', 'feeBps': 0}),
          200);
    });

/// The app-wide price, without the Hive box behind the real notifier.
/// [btc] carries the cached BTC/USD rate the currency cache keeps.
class _Currency extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _Currency({bool btc = false})
      : super(CurrencyState({
          'USD': Fixed.fromInt(_usdPerBtc.round()),
          if (btc) 'BTC': Fixed.fromNum(1 / _usdPerBtc, decimalDigits: 16),
        }));

  @override
  Future<void> updateRates() async {}
}

/// The Predictions account, awake, with its deposit wallet known.
class _Trading extends PolymarketTradingNotifier {
  @override
  Future<PolymarketTradingState> build() async => PolymarketTradingState(
      walletAddress: '0xeoa', proxyWalletAddress: '0xproxy');
}

/// The native Investing route, open.
class _Hypercore extends SparkHypercoreFundingService {
  _Hypercore(super.read);

  @override
  Future<void> ensureAvailable({required bool deposit}) async {}
}

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
          wallets: [WalletConfig(id: 'spending', name: 'Spending')],
          activeWalletId: 'spending',
        ));
}

/// Opens the sheet on [side] with [_balanceSats] in spending Bitcoin.
/// The spending SDK never answers, so a move that is started parks in
/// flight with the sheet's own processing state up: nothing can leave,
/// and the test decides when the balance it is spending drops.
///
/// [sdk] stands in for the spending SDK; left alone it never answers.
Future<ProviderContainer> _open(WidgetTester tester, MoveLockedSide side,
    {MockClient Function() orchestra = _orchestra,
    Completer<BreezSdkSpark>? sdk,
    bool cachedRate = false,
    VenueCashLastRead? lastRead,
    bool settle = true}) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(overrides: [
    settingsProvider.overrideWith((_) => _Settings()),
    currencyProvider.overrideWith((_) => _Currency(btc: cachedRate)),
    polymarketTradingProvider.overrideWith(_Trading.new),
    polymarketBalanceProvider.overrideWith((_) => 0),
    sparkHypercoreFundingServiceProvider
        .overrideWith((ref) => _Hypercore(ref.read)),
    sparkBitcoinBalanceProvider.overrideWith((ref) async => BigInt.from(ref
            .watch(walletBalanceCacheProvider)['spending']
            ?.sparkBitcoinbalance ??
        0)),
    breezSDKProvider
        .overrideWith((_) => (sdk ?? Completer<BreezSdkSpark>()).future),
    usdBalanceProvider.overrideWith((_) => _dollars),
    sparkSelfAddressProvider.overrideWith((_) async => _ownSpark),
    venueCashPullerProvider.overrideWith((_) => _puller!),
  ]);
  _setBalance(container, _balanceSats);
  if (lastRead != null) {
    container.read(venueCashLastReadProvider.notifier).state = lastRead;
  }
  // The price sample is read over the shared keep-alive client, which
  // `runWithClient` cannot reach; it answers from the same fake until the
  // test's tearDown clears it.
  SharedHttpClient.debugOverride = orchestra();
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
          home: DepositSheet(lockedSide: side),
        ),
      ),
    )),
    orchestra,
  );
  if (!settle) return container;
  // The price sample lands.
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return container;
}

void _setBalance(ProviderContainer container, int sats) =>
    container.read(walletBalanceCacheProvider.notifier).setBalance('spending',
        WalletBalance(onChainBtcBalance: 0, sparkBitcoinbalance: sats));

double _dollars = 10;
const String _ownSpark = 'spark1self';
VenueCashPuller? _puller;

/// The one approval, as the person answers it: every prompt is recorded
/// with what had moved by then; [approve] false declines.
class _Approvals {
  _Approvals(this.moved, {this.approve = true});

  /// How much venue cash had moved, read when the prompt shows.
  final int Function() moved;
  final bool approve;
  final prompts = <SensitiveIntent>[];
  final movedAtPrompt = <int>[];
  final grants = <AuthGrant>[];

  Future<AuthGrant?> call(SensitiveIntent intent) async {
    prompts.add(intent);
    movedAtPrompt.add(moved());
    if (!approve) return null;
    final grant =
        AuthGrants.issue(intent, method: AuthGrantMethod.biometric);
    grants.add(grant);
    return grant;
  }
}

/// Predictions cash with the direct cash-out to Bitcoin, recording each
/// leg and the authorization it ran under.
class _DirectVenue extends _Venue implements DirectVenueCashSource {
  _DirectVenue(super.available);

  final directs = <({double usd, MoveAuthorization auth})>[];

  @override
  bool canPullTo(VenueCashDestination destination) =>
      destination == VenueCashDestination.bitcoin;

  @override
  Future<VenueMoveResult> pullTo(VenueCashDestination destination, double usd,
      {required String purpose, required MoveAuthorization auth}) async {
    directs.add((usd: usd, auth: auth));
    return VenueMoveResult(
        quoteId: 'q-direct',
        operationId: 'op-direct',
        sentUsd: usd,
        arrivingUsdEstimate: usd * 0.99);
  }
}

/// Predictions cash whose read waits on [gate]: the venue read still on
/// its way while the sheet is already up.
class _SlowVenue extends _Venue {
  _SlowVenue(super.available);

  final gate = Completer<void>();

  @override
  Future<double> availableUsd() async {
    await gate.future;
    return available;
  }
}

/// The engine's last read: Predictions and Investing cash, for the
/// spending wallet.
VenueCashLastRead _read({double predictions = 0, double investing = 0}) => (
      walletId: 'spending',
      candidates: [
        if (predictions > 0)
          (
            venue: OneBalanceVenue.predictions,
            availableUsd: predictions,
            eta: kVenuePullEta[OneBalanceVenue.predictions]!,
            minimumUsd: 1.0,
          ),
        if (investing > 0)
          (
            venue: OneBalanceVenue.investing,
            availableUsd: investing,
            eta: kVenuePullEta[OneBalanceVenue.investing]!,
            minimumUsd: 5.0,
          ),
      ],
    );

/// The From row's figure, as the route card prints it.
Finder _shown(String usd) => find.text('\$$usd');

BigAmountDisplay _big(WidgetTester tester) =>
    tester.widget<BigAmountDisplay>(find.byType(BigAmountDisplay));

/// Predictions cash the test sets, recording each pull.
class _Venue implements VenueCashSource {
  _Venue(this.available);

  @override
  OneBalanceVenue get venue => OneBalanceVenue.predictions;
  double available;
  final pulls = <double>[];

  @override
  Duration get estimatedArrival => kVenuePullEta[venue]!;

  @override
  Future<double> availableUsd() async => available;

  @override
  Future<VenueMoveResult> pull(double usd, {required String purpose}) async {
    pulls.add(usd);
    return VenueMoveResult(
        quoteId: 'q', sentUsd: usd, arrivingUsdEstimate: usd * 0.99);
  }
}

Future<void> _close(WidgetTester tester, ProviderContainer container) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpWidget(const SizedBox());
  container.dispose();
  await tester.pump(const Duration(minutes: 3));
}

Finder get _cta => find.byType(AppButton).last;

void main() {
  setUpAll(() {
    dotenv.loadFromString(envString: 'BACKEND=https://backend.test');
    GoogleFonts.config.allowRuntimeFetching = false;
  });
  setUp(() {
    AffiliateService.debugSessionToken = 'test-session';
    RuntimeCapabilitiesService.debugInstance = runtimePolicyFixture();
    _dollars = 10;
    MultiSourceMoveStore.reset();
    DirectRouteRefusals.reset();
  });
  tearDown(() {
    debugBuyBitcoinApproval = null;
    RuntimeCapabilitiesService.debugInstance?.dispose();
    RuntimeCapabilitiesService.debugInstance = null;
    AffiliateService.debugSessionToken = null;
    SharedHttpClient.debugOverride = null;
    TrackingService.debugTrackObserver = null;
    _puller = null;
  });

  testWidgets(
      'Dollars → Bitcoin past Dollars: venue cash is in reach, the '
      'shortfall is pulled first, and a pull still on its way stops the '
      'purchase honestly', (tester) async {
    final events = <String>[];
    TrackingService.debugTrackObserver = (e, _) => events.add(e);
    final venue = _Venue(100);
    final approvals = _Approvals(() => venue.pulls.length);
    debugBuyBitcoinApproval = approvals.call;
    var now = DateTime(2026, 10, 13, 12);
    _puller = VenueCashPuller(
      sources: [venue],
      readDollars: () => _dollars,
      minimumUsd: (_) async => 1,
      clock: () => now,
      sleep: (d) async => now = now.add(d),
    );
    final container = await _open(tester, MoveLockedSide.depositFromFiat);
    // $30 against $10 of Dollars and $60 of reach.
    for (final key in ['3', '0']) {
      await tester.tap(find.text(key).last);
      await tester.pump();
    }
    expect(find.text(_insufficient), findsNothing);
    expect(tester.widget<AppButton>(_cta).onPressed, isNotNull);

    await tester.tap(_cta);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    // One approval, asked before anything moved, for the whole purchase.
    expect(approvals.prompts, hasLength(1));
    expect(approvals.movedAtPrompt, [0]);
    expect(approvals.prompts.single.action, SensitiveAction.moveTransfer);
    expect(approvals.prompts.single.destination, _ownSpark);
    // No leg of this venue can go straight to Bitcoin: none is bound.
    expect(approvals.prompts.single.limits[VenueLimit.directLegs], isNull);
    // 20 missing: 20 / 0.98 → $20.41 from Predictions, once.
    expect(venue.pulls, [20.41]);
    // Stopped before the purchase: its approval goes with it.
    expect(approvals.grants.single.revoked, isTrue);
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(
        find.text('${l10n.oneBalanceComingBack(r'$20.41', l10n.predictions)}'
            '\n${l10n.activityBitcoinAddedPending}'),
        findsOneWidget);
    expect(events, contains('predictions_cash_pulled'));
    expect(events, isNot(contains('convert_success')));
    expect(tester.widget<AppButton>(_cta).isLoading, isFalse);
    await _close(tester, container);
  });

  testWidgets(
      'Buy Bitcoin with every leg straight to Bitcoin: ONE prompt, before '
      'anything moves, and the legs run under it', (tester) async {
    // Dollars under the onward minimum are left alone: the venue covers
    // the whole purchase straight to Bitcoin.
    _dollars = 0.5;
    final events = <String>[];
    TrackingService.debugTrackObserver = (e, _) => events.add(e);
    final venue = _DirectVenue(100);
    final approvals =
        _Approvals(() => venue.pulls.length + venue.directs.length);
    debugBuyBitcoinApproval = approvals.call;
    var now = DateTime(2026, 10, 13, 12);
    _puller = VenueCashPuller(
      sources: [venue],
      readDollars: () => _dollars,
      minimumUsd: (_) async => 1,
      clock: () => now,
      sleep: (d) async => now = now.add(d),
    );
    final container = await _open(tester, MoveLockedSide.depositFromFiat);
    for (final key in ['3', '0']) {
      await tester.tap(find.text(key).last);
      await tester.pump();
    }
    await tester.tap(_cta);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(approvals.prompts, hasLength(1), reason: 'one prompt, no second');
    expect(approvals.movedAtPrompt, [0], reason: 'nothing before approval');
    final intent = approvals.prompts.single;
    expect(intent.action, SensitiveAction.moveTransfer);
    expect(intent.destination, _ownSpark);
    // The approval binds the leg's cap and the total.
    expect(intent.limits[VenueLimit.directLegs], {
      'to': 'bitcoin',
      'legs': {'predictions': '30620000'},
      'total': '30620000',
    });
    expect(venue.pulls, isEmpty, reason: 'never home first');
    final leg = venue.directs.single;
    expect(leg.usd, 30.62);
    expect(leg.auth, isA<ApprovedLegAuthorization>());
    expect((leg.auth as ApprovedLegAuthorization).grant,
        same(approvals.grants.single));
    expect(events, contains('predictions_cash_pulled'));
    // Every dollar went straight to Bitcoin: nothing to buy from Dollars,
    // and the approval ends there.
    expect(events, isNot(contains('convert_success')));
    expect(approvals.grants.single.revoked, isTrue);
    await _close(tester, container);
  });

  testWidgets('declining the one prompt moves nothing at all',
      (tester) async {
    final events = <String>[];
    TrackingService.debugTrackObserver = (e, _) => events.add(e);
    final venue = _DirectVenue(100);
    final approvals = _Approvals(
        () => venue.pulls.length + venue.directs.length,
        approve: false);
    debugBuyBitcoinApproval = approvals.call;
    var now = DateTime(2026, 10, 13, 12);
    _puller = VenueCashPuller(
      sources: [venue],
      readDollars: () => _dollars,
      minimumUsd: (_) async => 1,
      clock: () => now,
      sleep: (d) async => now = now.add(d),
    );
    final container = await _open(tester, MoveLockedSide.depositFromFiat);
    for (final key in ['3', '0']) {
      await tester.tap(find.text(key).last);
      await tester.pump();
    }
    await tester.tap(_cta);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(approvals.prompts, hasLength(1));
    expect(venue.directs, isEmpty);
    expect(venue.pulls, isEmpty);
    expect(MultiSourceMoveStore.all(), isEmpty);
    expect(events.where((e) => e.endsWith('_cash_pulled')), isEmpty);
    expect(events, isNot(contains('multi_source_move_started')));
    // Back to the amount, quietly: no error, no spinner.
    expect(tester.widget<AppButton>(_cta).isLoading, isFalse);
    expect(find.text(_insufficient), findsNothing);
    await _close(tester, container);
  });

  testWidgets(
      'Buy Bitcoin from Investments: Dollars plus venue cash and the price '
      'are on the very first frame, from the last known values, with no '
      'loading state; the fresh venue read updates the figure in place',
      (tester) async {
    final venue = _SlowVenue(70);
    _puller = VenueCashPuller(
      sources: [venue],
      readDollars: () => _dollars,
      minimumUsd: (_) async => 1,
    );
    // The route's own price sample is slow; the cached price stands in.
    final container = await _open(tester, MoveLockedSide.depositFromFiat,
        orchestra: () => _orchestra(delay: const Duration(seconds: 5)),
        cachedRate: true,
        lastRead: _read(predictions: 60, investing: 40),
        settle: false);
    // First frame: $10 of Dollars + $60 + $40 of venue cash, under the
    // Investments name, no "Updating balance", no skeleton.
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(_shown('110.00'), findsOneWidget);
    expect(find.text(l10n.assetDollars), findsWidgets);
    expect(find.text('Updating balance'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(_big(tester).loading, isFalse);

    // The venues answer: Predictions now holds $70 and Investing nothing.
    venue.gate.complete();
    await tester.pump();
    await tester.pump();
    expect(_shown('80.00'), findsOneWidget);
    expect(_shown('110.00'), findsNothing);
    expect(_big(tester).loading, isFalse);
    await tester.pump(const Duration(seconds: 6));
    await _close(tester, container);
  });

  testWidgets(
      'cold start: nothing cached shows Dollars at once, then folds venue '
      'cash in when the read lands', (tester) async {
    final venue = _SlowVenue(100);
    _puller = VenueCashPuller(
      sources: [venue],
      readDollars: () => _dollars,
      minimumUsd: (_) async => 1,
    );
    final container = await _open(tester, MoveLockedSide.depositFromFiat,
        settle: false);
    expect(_shown('10.00'), findsOneWidget);
    expect(find.text('Updating balance'), findsNothing);
    venue.gate.complete();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(_shown('110.00'), findsOneWidget);
    expect(container.read(venueCashLastReadProvider), isNotNull,
        reason: 'the read is kept for the next screen');
    await _close(tester, container);
  });

  testWidgets(
      'no Dollars but venue cash cached: the door still opens on '
      'Investments with what it can spend', (tester) async {
    _dollars = 0;
    _puller = VenueCashPuller(
      sources: [_SlowVenue(60)],
      readDollars: () => _dollars,
      minimumUsd: (_) async => 1,
    );
    final container = await _open(tester, MoveLockedSide.depositFromFiat,
        lastRead: _read(predictions: 60), settle: false);
    expect(_shown('60.00'), findsOneWidget);
    expect(find.text('Cash App'), findsNothing);
    await _close(tester, container);
  });

  testWidgets(
      'Max is what the engine plan covers; between Dollars and the total '
      'is no "insufficient", above the total is', (tester) async {
    final venue = _Venue(100);
    _puller = VenueCashPuller(
      sources: [venue],
      readDollars: () => _dollars,
      minimumUsd: (_) async => 1,
    );
    final container = await _open(tester, MoveLockedSide.depositFromFiat);
    // $10 of Dollars and $100 of Predictions cash: $110 to spend.
    expect(_shown('110.00'), findsOneWidget);

    // Max (the figure is the Max): $100 less its 2% planned cost.
    await tester.tap(_shown('110.00'));
    await tester.pump();
    expect(_big(tester).amountText, '108.00');
    expect(find.text(_insufficient), findsNothing);
    expect(tester.widget<AppButton>(_cta).onPressed, isNotNull);
    final plan = await _puller!
        .plan(neededUsd: 108, destination: VenueCashDestination.bitcoin);
    expect(plan.covers, isTrue);
    expect(plan.pulls.single.usd, 100);

    // $60: past Dollars, inside the total.
    void typeAmount(String v) =>
        tester.widget<AmountKeypad>(find.byType(AmountKeypad)).onChanged(v);
    typeAmount('60');
    await tester.pump();
    expect(_big(tester).amountText, '60');
    expect(find.text(_insufficient), findsNothing);
    expect(tester.widget<AppButton>(_cta).onPressed, isNotNull);

    // $600: above the total.
    typeAmount('600');
    await tester.pump();
    expect(find.text(_insufficient), findsWidgets);
    await _close(tester, container);
  });
}
