// "Check connection" on the bet slip (founder decision, October 2026): a
// region refusal makes the slip's one button "Check connection", never a
// dead one. A tap asks the venues and Kute's policy again; allowed now,
// the refusal goes and the button is the bet, ready to place; still
// restricted, the refusal stays with a soft failure tap.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_open_orders_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider;
import 'package:kute/screens/polymarket/components/bet_slip_sheet.dart';
import 'package:kute/screens/polymarket/components/slip_chrome.dart';
import 'package:kute/screens/shared/capability_block_note.dart';
import 'package:kute/services/continuous_haptics.dart';
import 'package:kute/services/investment_provider_availability.dart';
import 'package:kute/services/kute_haptics.dart';
import 'package:kute/services/one_balance/predictions_venue_funder.dart';
import 'package:kute/services/polymarket/polymarket_fee_terms.dart';
import 'package:kute/services/region_freshness.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/runtime_policy_snapshot_store.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart';

import '../../helpers/fake_swap_orders.dart';

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
      const PolymarketTradingState(usdcBalance: 100);
}

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

const _regionSentence =
    'This feature is restricted in the region your internet connection '
    'appears to be in. If this isn\'t where you are, check your VPN '
    'settings.';

void main() {
  late bool blocked;
  late List<String> triggers;
  late List<ContinuousHapticsCall> haptics;
  late RuntimeCapabilitiesService policy;
  late InvestmentProviderAvailability venues;

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    PredictionsVenueFunder.debugRouteShare = (_) async => 0;
    AffiliateService.debugSessionToken = 'test-session';
    blocked = true;
    triggers = [];
    haptics = ContinuousHaptics.debugLog = [];
    KuteHaptics.debugReset();
    KuteHaptics.debugForeground = () => true;
    // Kute places the connection by where it appears to be: a region
    // denial for new predictions while [blocked].
    policy = RuntimeCapabilitiesService.forTesting(
      client: MockClient((_) async {
        final now = DateTime.now().toUtc();
        return http.Response(
            jsonEncode({
              'schemaVersion': 1,
              'revision': 1,
              'evaluatedAt': now.toIso8601String(),
              'expiresAt':
                  now.add(const Duration(minutes: 2)).toIso8601String(),
              'capabilities': {
                for (final id in [
                  'polymarket.deposit',
                  'polymarket.close',
                  'polymarket.sports',
                  'polymarket.politics',
                  'polymarket.withdraw',
                  'trading.advanced',
                ])
                  id: {'allowed': true},
                'polymarket.trade': blocked
                    ? {'allowed': false, 'reason': 'country_blocked'}
                    : {'allowed': true},
              },
            }),
            200);
      }),
      baseUrl: () => 'https://policy.test',
      sessionToken: () => AffiliateService.sessionToken,
      store: MemoryRuntimePolicySnapshotStore(),
    );
    RuntimeCapabilitiesService.debugInstance = policy;
    venues = InvestmentProviderAvailability(
      client: MockClient(
          (request) async => request.url.host == 'api.hyperliquid.xyz'
              ? http.Response(
                  jsonEncode({
                    'acceptedTerms': true,
                    'userAllowed': true,
                    'restrictions': 'n',
                  }),
                  200)
              : http.Response(jsonEncode({'blocked': false}), 200)),
      report: ({
        required String venue,
        required String trigger,
        required bool changed,
        required String result,
      }) =>
          triggers.add('$venue:$trigger'),
    );
    RegionFreshness.debugVenues = venues;
  });

  tearDown(() {
    PredictionsVenueFunder.debugRouteShare = null;
    AffiliateService.debugSessionToken = null;
    RuntimeCapabilitiesService.debugInstance = null;
    RegionFreshness.debugVenues = null;
    ContinuousHaptics.debugLog = null;
    ContinuousHaptics.debugReset();
    KuteHaptics.debugReset();
    venues.dispose();
  });

  Future<void> frames(WidgetTester tester, [int n = 10]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpSlip(WidgetTester tester) async {
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
    await frames(tester);
  }

  PolySlipCta cta(WidgetTester tester) =>
      tester.widget<PolySlipCta>(find.byType(PolySlipCta));

  Future<void> release(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    policy.dispose();
  }

  Future<void> tapCheck(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('bet-slip-check-connection')));
    await frames(tester, 20);
  }

  testWidgets('a region refusal: the button is "Check connection", live',
      (tester) async {
    expect(await policy.refresh(), isTrue);
    await pumpSlip(tester);
    expect(find.widgetWithText(CapabilityBlockNote, _regionSentence),
        findsOneWidget);
    expect(find.byKey(const ValueKey('bet-slip-check-connection')),
        findsOneWidget);
    expect(cta(tester).label, 'Check connection');
    expect(cta(tester).enabled, isTrue);
    await release(tester);
  });

  testWidgets('now allowed: the refusal lifts and the bet is ready to place',
      (tester) async {
    expect(await policy.refresh(), isTrue);
    await pumpSlip(tester);
    // Another server in the same VPN app: no path change, so the person
    // taps.
    blocked = false;
    await tapCheck(tester);

    expect(
        find.byKey(const ValueKey('bet-slip-check-connection')), findsNothing);
    expect(find.byType(CapabilityBlockNote), findsNothing);
    expect(cta(tester).label, r'Place $10.00 on Yes');
    expect(cta(tester).enabled, isTrue);
    expect(policy.allows('polymarket.trade'), isTrue);
    // Both venues asked live, reported as a manual check.
    expect(triggers, containsAll(['polymarket:manual', 'hyperliquid:manual']));
    expect(haptics.where((c) => c.method == 'softTap'), isEmpty);
    await release(tester);
  });

  testWidgets('still restricted: the refusal stays, with a failure tap',
      (tester) async {
    expect(await policy.refresh(), isTrue);
    await pumpSlip(tester);
    await tapCheck(tester);

    expect(find.widgetWithText(CapabilityBlockNote, _regionSentence),
        findsOneWidget);
    expect(cta(tester).label, 'Check connection');
    expect(cta(tester).enabled, isTrue);
    expect(cta(tester).isBusy, isFalse);
    expect(haptics.where((c) => c.method == 'softTap'), hasLength(1));

    // The VPN changes again: the next tap lifts it.
    blocked = false;
    await tapCheck(tester);
    expect(cta(tester).label, r'Place $10.00 on Yes');
    await release(tester);
  });
}
