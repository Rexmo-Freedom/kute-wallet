// The Bitcoin → Investments Move sheet a slip opens with nothing typed
// carries the order the slip was sized for (founder, 14 October 2026:
// "open the btc sheet and then go back and start automatically the
// investment if user adds"). The review names it in one line; an add that
// covers it hands this sheet's Bitcoin leg to the slip, whose ONE approval
// binds the leg and the order (this sheet asks nothing of its own); a
// declined approval moves nothing; a smaller add is this sheet's own move,
// with no order.

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
import 'package:kute/helpers/orchestra_router.dart';
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
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider;
import 'package:kute/screens/home/components/deposit_sheet.dart';
import 'package:kute/screens/shared/amount_keypad_panel.dart'
    show AmountKeypad;
import 'package:kute/screens/shared/custom_button.dart';
import 'package:kute/services/http/shared_http_client.dart';
import 'package:kute/services/one_balance/bitcoin_funded_order.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/venue_cash_source.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart' show Fixed;

import '../../helpers/runtime_policy_fixture.dart';

const _usdPerBtc = 100000.0;
const _balanceSats = 100000; // $100.00 at the sample price.
const String _ownSpark = 'spark1self';
const _followOn = r'Then places $1.00 on Yes';

/// Orchestra's price sample: a flat route.
MockClient _orchestra() => MockClient((request) async {
      if (!request.url.path.endsWith('/estimate')) {
        return http.Response('{}', 404);
      }
      final asset = request.url.queryParameters['destinationAsset']!;
      final chain = request.url.queryParameters['destinationChain']!;
      final sats = int.tryParse(request.url.queryParameters['amount'] ?? '') ??
          _balanceSats;
      final out =
          doubleToOrchestraAmount(sats / 1e8 * _usdPerBtc, asset, chain: chain);
      return http.Response(
          jsonEncode({'estimatedOut': out, 'feeAmount': '0', 'feeBps': 0}),
          200);
    });

class _Currency extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _Currency()
      : super(CurrencyState({'USD': Fixed.fromInt(_usdPerBtc.round())}));

  @override
  Future<void> updateRates() async {}
}

class _Trading extends PolymarketTradingNotifier {
  @override
  Future<PolymarketTradingState> build() async => PolymarketTradingState(
      walletAddress: '0xeoa', proxyWalletAddress: '0xproxy');
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

/// The slip's side of the attachment, as the test answers it.
class _Slip {
  _Slip(this.answer);
  final MoveSheetOrderStart Function(MoveSheetLeg leg) answer;
  final legs = <MoveSheetLeg>[];
  final added = <double>[];

  MoveSheetOrder get order => MoveSheetOrder(
        venue: OneBalanceVenue.predictions,
        addUsd: 5,
        orderUsd: 1,
        followOn: _followOn,
        start: (leg) async {
          legs.add(leg);
          return answer(leg);
        },
        addedOnly: added.add,
      );
}

/// Opens the Bitcoin → Investments door prefilled with X = $5, carrying
/// [slip]'s order. The spending SDK never answers: the sheet's own move,
/// once started, parks in flight.
Future<ProviderContainer> _open(WidgetTester tester, _Slip slip) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(overrides: [
    settingsProvider.overrideWith((_) => _Settings()),
    currencyProvider.overrideWith((_) => _Currency()),
    polymarketTradingProvider.overrideWith(_Trading.new),
    polymarketBalanceProvider.overrideWith((_) => 0),
    sparkBitcoinBalanceProvider.overrideWith((ref) async => BigInt.from(ref
            .watch(walletBalanceCacheProvider)['spending']
            ?.sparkBitcoinbalance ??
        0)),
    breezSDKProvider
        .overrideWith((_) => Completer<BreezSdkSpark>().future),
    usdBalanceProvider.overrideWith((_) => 0),
    sparkSelfAddressProvider.overrideWith((_) async => _ownSpark),
    venueCashPullerProvider.overrideWith((_) => VenueCashPuller(
        sources: const [], readDollars: () => 0, minimumUsd: (_) async => 1)),
  ]);
  container.read(walletBalanceCacheProvider.notifier).setBalance('spending',
      WalletBalance(onChainBtcBalance: 0, sparkBitcoinbalance: _balanceSats));
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
          home: DepositSheet(
            lockedSide: MoveLockedSide.depositToUsd,
            initialTargetUsd: 5,
            attachedOrder: slip.order,
          ),
        ),
      ),
    )),
    _orchestra,
  );
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return container;
}

Future<void> _frames(WidgetTester tester, [int n = 10]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _type(WidgetTester tester, String amount) async {
  final pad = find.byType(AmountKeypad);
  final backspace =
      find.descendant(of: pad, matching: find.byIcon(Icons.backspace_rounded));
  for (var i = 0; i < 8; i++) {
    await tester.tap(backspace);
    await tester.pump();
  }
  for (final key in amount.split('')) {
    await tester.tap(find.descendant(of: pad, matching: find.text(key)));
    await tester.pump();
  }
  await _frames(tester);
}

Future<void> _close(WidgetTester tester, ProviderContainer container) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpWidget(const SizedBox());
  container.dispose();
  await tester.pump(const Duration(minutes: 3));
}

Finder get _cta => find.byType(AppButton).last;
Finder get _line => find.byKey(const ValueKey('move-sheet-follow-on'));

void main() {
  late List<(String, Map<String, Object?>?)> events;

  setUpAll(() {
    dotenv.loadFromString(envString: 'BACKEND=https://backend.test');
    GoogleFonts.config.allowRuntimeFetching = false;
  });
  setUp(() {
    AffiliateService.debugSessionToken = 'test-session';
    RuntimeCapabilitiesService.debugInstance = runtimePolicyFixture();
    events = [];
    TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
  });
  tearDown(() {
    RuntimeCapabilitiesService.debugInstance?.dispose();
    RuntimeCapabilitiesService.debugInstance = null;
    AffiliateService.debugSessionToken = null;
    SharedHttpClient.debugOverride = null;
    TrackingService.debugTrackObserver = null;
  });

  testWidgets(
      'the review names what follows in one line, only while the add '
      'covers it', (tester) async {
    final slip = _Slip((_) => const MoveSheetOrderStart.declined());
    final container = await _open(tester, slip);
    expect(_line, findsOneWidget);
    expect(find.text(_followOn), findsOneWidget);
    // More than X: still the order.
    await _type(tester, '8');
    expect(_line, findsOneWidget);
    // Less than X: the add alone.
    await _type(tester, '2');
    expect(_line, findsNothing);
    await _close(tester, container);
  });

  testWidgets(
      "confirming hands the sheet's leg to the slip, whose approval was "
      'declined: nothing is sent, the sheet stays', (tester) async {
    final slip = _Slip((_) => const MoveSheetOrderStart.declined());
    final container = await _open(tester, slip);
    await tester.tap(_cta);
    await _frames(tester);
    // The slip got the leg once: what the person confirmed, the sats it
    // takes, and the most the one approval lets leave (within the wallet).
    expect(slip.legs, hasLength(1));
    final plan = slip.legs.single.plan;
    expect(plan.targetUsd, closeTo(5, 0.001));
    expect(plan.dollarsShortUsd, 5);
    expect(plan.sats, greaterThan(0));
    expect(plan.maxSats, greaterThanOrEqualTo(plan.sats));
    expect(plan.maxSats, lessThanOrEqualTo(_balanceSats));
    // Declined: nothing quoted or sent, no add on its own either.
    expect(events.map((e) => e.$1), isNot(contains('convert_success')));
    expect(slip.added, isEmpty);
    expect(find.byType(DepositSheet), findsOneWidget);
    expect(tester.widget<AppButton>(_cta).isLoading, isFalse);
    // The move's events carry the attached order, exact.
    final initiated = events.where((e) => e.$1 == 'move_initiated').single.$2!;
    expect(initiated['attached_order_usd'], 1.0);
    expect(initiated.values.whereType<String>().where((v) => v.contains('spark')),
        isEmpty);
    await _close(tester, container);
  });

  testWidgets("the order refused before any approval: the slip's reason, "
      'nothing sent', (tester) async {
    final slip = _Slip(
        (_) => const MoveSheetOrderStart.refused('This round has closed.'));
    final container = await _open(tester, slip);
    await tester.tap(_cta);
    await _frames(tester);
    expect(slip.legs, hasLength(1));
    expect(find.text('This round has closed.'), findsOneWidget);
    expect(find.byType(DepositSheet), findsOneWidget);
    expect(events.map((e) => e.$1), isNot(contains('convert_success')));
    await _close(tester, container);
  });

  testWidgets(
      'the chain stopped before the bitcoin left: the sheet says so and '
      'stays', (tester) async {
    final slip = _Slip((_) => MoveSheetOrderStart.started(BitcoinFundedRun(
        'fo_1', Future.value(BitcoinFundedEnd.notSent))));
    final container = await _open(tester, slip);
    await tester.tap(_cta);
    await _frames(tester);
    expect(slip.legs, hasLength(1));
    expect(find.byType(DepositSheet), findsOneWidget);
    expect(tester.widget<AppButton>(_cta).isLoading, isFalse);
    final l10n =
        AppLocalizations.of(tester.element(find.byType(DepositSheet)));
    expect(find.text(l10n.moveFailure), findsOneWidget);
    await _close(tester, container);
  });

  testWidgets(
      "a smaller add is the sheet's own move: the slip's order is never "
      'started', (tester) async {
    final slip = _Slip((_) => const MoveSheetOrderStart.declined());
    final container = await _open(tester, slip);
    await _type(tester, '2');
    await tester.tap(_cta);
    await _frames(tester);
    // The sheet's own move runs (parked on the spending SDK here); the
    // order is not handed anything.
    expect(slip.legs, isEmpty);
    final initiated = events.where((e) => e.$1 == 'move_initiated').single.$2!;
    expect(initiated['attached_order_usd'], 1.0);
    await _close(tester, container);
  });
}
