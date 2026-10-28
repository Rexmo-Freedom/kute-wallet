// "Check connection" on the order ticket (founder decision, October 2026):
// a region refusal makes the ticket's one button "Check connection", never
// a dead one. A tap asks the venues and Kute's policy again; allowed now,
// the refusal goes and the button is the order, ready to place; still
// restricted, the refusal stays with a soft failure tap.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_orderbook_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/providers/usd_account_provider.dart';
import 'package:kute/screens/hyperliquid/components/order_slip_sheet.dart';
import 'package:kute/screens/shared/custom_button.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/screens/shared/capability_block_note.dart';
import 'package:kute/services/continuous_haptics.dart';
import 'package:kute/services/investment_provider_availability.dart';
import 'package:kute/services/kute_haptics.dart';
import 'package:kute/services/region_freshness.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart';

import '../../helpers/fake_swap_orders.dart';

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

/// Kute's policy, placing the connection where the test says: a region
/// denial for new positions while [blocked].
class _Policy extends Fake implements RuntimeCapabilitiesService {
  bool blocked = true;
  static const _region =
      CapabilityDecision(allowed: false, reason: 'country_blocked');
  @override
  CapabilityDecision decision(String id) => blocked && id == 'hyperliquid.trade'
      ? _region
      : const CapabilityDecision(allowed: true);
  @override
  bool allows(String id) => decision(id).allowed;
  @override
  String? blockReason(String id) =>
      decision(id).allowed ? null : decision(id).message;
  @override
  Future<void> ensureAllAllowed(Iterable<String> ids,
      {Duration maxAge = Duration.zero}) async {
    for (final id in ids) {
      if (!decision(id).allowed) {
        throw CapabilityUnavailableException(id, decision(id));
      }
    }
  }

  @override
  Future<bool> networkChanged() async => true;
  @override
  int? get maxLeverage => null;
  @override
  int offeredLeverage(int venueMax) => venueMax;
}

/// The Investing account, answered when the test says so.
class _Account extends HlAccountNotifier {
  _Account(this.answer);
  final Future<HlAccountSnapshot> answer;
  @override
  Future<HlAccountSnapshot> build() => answer;
}

HlAccountSnapshot _snapshot(double withdrawable) => HlAccountSnapshot(
      accountValue: withdrawable,
      withdrawable: withdrawable,
      totalMarginUsed: 0,
      positions: const [],
      spotBalances: const [],
    );

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

Future<void> _pumpSlip(WidgetTester tester, Future<HlAccountSnapshot> account,
    _Policy policy) async {
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
          ))),
      hyperliquidLivePricesProvider.overrideWith(_LivePrices.new),
      hyperliquidAccountProvider.overrideWith(() => _Account(account)),
      swapOrdersProvider.overrideWith((_) => FakeSwapOrders()),
      hyperliquidAddressProvider.overrideWith((_) async => null),
      hyperliquidOrderbookProvider
          .overrideWith((_, __) => Stream.value(const HlOrderBookState())),
      aiEnabledProvider.overrideWith((_) async => false),
      currencyProvider.overrideWith((_) => _Currency()),
      runtimeCapabilitiesProvider.overrideWithValue(policy),
      usdBalanceProvider.overrideWith((_) => 0),
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

/// The loading dots animate for as long as they wait: pump, never settle.
Future<void> _frames(WidgetTester tester, [int n = 10]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

AppButton _button(WidgetTester tester) =>
    tester.widget<AppButton>(find.byType(AppButton));

const _regionSentence =
    'This feature is restricted in the region your internet connection '
    'appears to be in. If this isn\'t where you are, check your VPN '
    'settings.';

void main() {
  late _Policy policy;
  late List<String> triggers;
  late List<ContinuousHapticsCall> haptics;
  late InvestmentProviderAvailability venues;

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    policy = _Policy();
    RuntimeCapabilitiesService.debugInstance = policy;
    triggers = [];
    haptics = ContinuousHaptics.debugLog = [];
    KuteHaptics.debugReset();
    KuteHaptics.debugForeground = () => true;
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
      }) =>
          triggers.add('$venue:$trigger'),
    );
    RegionFreshness.debugVenues = venues;
  });

  tearDown(() {
    RuntimeCapabilitiesService.debugInstance = null;
    RegionFreshness.debugVenues = null;
    ContinuousHaptics.debugLog = null;
    ContinuousHaptics.debugReset();
    KuteHaptics.debugReset();
    venues.dispose();
  });

  Future<void> tapCheck(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(AppButton, 'Check connection'));
    await _frames(tester, 20);
  }

  testWidgets('a region refusal: the button is "Check connection", live',
      (tester) async {
    await _pumpSlip(tester, Future.value(_snapshot(500)), policy);
    expect(find.widgetWithText(CapabilityBlockNote, _regionSentence),
        findsOneWidget);
    expect(_button(tester).text, 'Check connection');
    expect(_button(tester).onPressed, isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('now allowed: the refusal lifts and the order is ready',
      (tester) async {
    await _pumpSlip(tester, Future.value(_snapshot(500)), policy);
    policy.blocked = false;
    await tapCheck(tester);
    expect(find.byType(CapabilityBlockNote), findsNothing);
    expect(_button(tester).text, startsWith('Long '));
    expect(_button(tester).onPressed, isNotNull);
    expect(triggers, containsAll(['polymarket:manual', 'hyperliquid:manual']));
    expect(haptics.where((c) => c.method == 'softTap'), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('still restricted: the refusal stays, with a failure tap',
      (tester) async {
    await _pumpSlip(tester, Future.value(_snapshot(500)), policy);
    await tapCheck(tester);
    expect(find.widgetWithText(CapabilityBlockNote, _regionSentence),
        findsOneWidget);
    expect(_button(tester).text, 'Check connection');
    expect(_button(tester).isLoading, isFalse);
    expect(_button(tester).onPressed, isNotNull);
    expect(haptics.where((c) => c.method == 'softTap'), hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
