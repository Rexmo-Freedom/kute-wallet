// Gating audit (fw36): the slips the trade row's doors open (Invest /
// Short on Investing, Yes / No on Predictions; also the claim screen's
// "Place the prediction" and search results), read against a real
// backend policy under the four ways it withholds new positions. The slip
// always opens (markets stay browsable) and its one button says why:
//
//   * a swap country block, cascaded to the venue: the backend's regions
//     over the one VPN sentence, and the button is "Check connection";
//   * a platform block, the switch off, coming soon: Kute's sentence for
//     the reason, and the button cannot place;
//   * a spot Sell is an exit (`hyperliquid.close`): no refusal at all.
//
// The round Sal button on the slips is fw37's (send mode) and is not
// asserted here.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_orderbook_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_open_orders_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider;
import 'package:kute/screens/hyperliquid/components/order_slip_sheet.dart';
import 'package:kute/screens/polymarket/components/bet_slip_sheet.dart';
import 'package:kute/screens/polymarket/components/slip_chrome.dart';
import 'package:kute/screens/shared/capability_block_note.dart';
import 'package:kute/services/investment_provider_availability.dart';
import 'package:kute/services/one_balance/predictions_venue_funder.dart';
import 'package:kute/services/polymarket/polymarket_category_gate.dart';
import 'package:kute/services/polymarket/polymarket_fee_terms.dart';
import 'package:kute/services/region_freshness.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:money2/money2.dart';

import '../helpers/fake_swap_orders.dart';
import '../helpers/shell_bar_harness.dart';
import 'market_gating_fixtures.dart';

class _HlPrices extends HlLivePricesNotifier {
  @override
  HlLivePriceState build() => const HlLivePriceState(mids: {'BTC': 60000});
  @override
  void acquire() {}
  @override
  void release() {}
  @override
  void watchCoins(List<String> coins, {Map<String, String>? wire}) {}
}

class _PmPrices extends LivePriceNotifier {
  @override
  LivePriceState build() => const LivePriceState();
  @override
  void acquire() {}
  @override
  void release() {}
  @override
  void addTokens(List<String> tokenIds, {bool pin = true}) {}
}

class _PmTrading extends PolymarketTradingNotifier {
  @override
  Future<PolymarketTradingState> build() async =>
      const PolymarketTradingState(usdcBalance: 100);
}

class _Currency extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _Currency() : super(CurrencyState({'USD': Fixed.fromInt(1)}));
  @override
  Future<void> updateRates() async {}
}

class _Account extends HlAccountNotifier {
  @override
  Future<HlAccountSnapshot> build() async => const HlAccountSnapshot(
        accountValue: 500,
        withdrawable: 500,
        totalMarginUsed: 0,
        positions: [],
        spotBalances: [],
      );
}

const _perp = HlMarket(
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

const _spot = HlMarket(
  coin: 'HYPE',
  wireCoin: '@107',
  assetId: 10107,
  kind: HlMarketKind.spot,
  szDecimals: 2,
  maxLeverage: 1,
  onlyIsolated: false,
  markPx: 40,
  midPx: 40,
  prevDayPx: 40,
  dayNtlVlm: 0,
);

const _outcomes = [
  PolymarketOutcome(name: 'Yes', price: 0.5, tokenId: 'yes-token'),
  PolymarketOutcome(name: 'No', price: 0.5, tokenId: 'no-token'),
];

Settings get _settings => Settings(
      currency: 'USD',
      language: 'en',
      btcFormat: 'sats',
      backup: false,
      biometricsEnabled: false,
      bitcoinElectrumNode: '',
      nodeType: 'Blockstream',
      reviewDone: true,
    );

Future<void> _frames(WidgetTester tester, [int n = 10]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pump(WidgetTester tester, RuntimeCapabilitiesService policy,
    Widget slip, List<Override> overrides) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  installShellBar();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      settingsProvider.overrideWith((_) => SettingsModel(_settings)),
      swapOrdersProvider.overrideWith((_) => FakeSwapOrders()),
      aiEnabledProvider.overrideWith((_) async => false),
      currencyProvider.overrideWith((_) => _Currency()),
      runtimeCapabilitiesProvider.overrideWithValue(policy),
      usdBalanceProvider.overrideWith((_) => 0),
      ...overrides,
    ],
    child: shellBarApp(
      home: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Align(alignment: Alignment.bottomCenter, child: slip),
      ),
    ),
  ));
  await _frames(tester);
}

final _hlOverrides = <Override>[
  hyperliquidLivePricesProvider.overrideWith(_HlPrices.new),
  hyperliquidAccountProvider.overrideWith(_Account.new),
  hyperliquidAddressProvider.overrideWith((_) async => null),
  hyperliquidOrderbookProvider
      .overrideWith((_, __) => Stream.value(const HlOrderBookState())),
];

final _pmOverrides = <Override>[
  polymarketTradingProvider.overrideWith(_PmTrading.new),
  livePriceProvider.overrideWith(_PmPrices.new),
  polymarketOpenOrdersProvider
      .overrideWith((ref) => Stream.value(const <Order>[])),
  polymarketFeeTermsProvider
      .overrideWith((ref, _) async => PolymarketFeeTerms.worstCase),
];

Finder _note(String text) => find.widgetWithText(CapabilityBlockNote, text);

/// Takes the slip down, then the policy with its expiry timers (the
/// slip's fresh read schedules one inside the test's fake clock).
Future<void> _release(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  // The market terms box's open timeout (market_terms_store.dart) runs out.
  await tester.pump(const Duration(seconds: 6));
  uninstallMarketGatingPolicy();
}

void main() {
  late InvestmentProviderAvailability venues;

  setUpAll(() {
    Hive.init(Directory.systemTemp.createTempSync('gating-slips').path);
  });

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    PredictionsVenueFunder.debugRouteShare = (_) async => 0;
    // The venues' own location answers: open, so only Kute's policy speaks.
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
      }) {},
    );
    RegionFreshness.debugVenues = venues;
  });

  tearDown(() {
    PredictionsVenueFunder.debugRouteShare = null;
    RegionFreshness.debugVenues = null;
    venues.dispose();
    uninstallMarketGatingPolicy();
  });

  group('the Investing order slip (Invest / Short)', () {
    for (final how in MarketDenial.values) {
      testWidgets('${how.label}: the slip opens and says why it cannot place',
          (tester) async {
        final policy = (await tester.runAsync(() =>
            installMarketGatingPolicy(how, targets: {'hyperliquid.trade'})))!;
        await _pump(
            tester,
            policy,
            const HlOrderSlipSheet(
                market: _perp, initialIsLong: true, initialUsd: 50),
            _hlOverrides);
        expect(_note(how.message), findsOneWidget);
        expect(find.textContaining('use a VPN'), findsNothing);
        if (how == MarketDenial.swapCountryBlock) {
          expect(barPrimaryLabel(tester), 'Check connection');
          expect(barPrimaryEnabled(tester), isTrue);
        } else {
          expect(barPrimaryLabel(tester), isNot('Check connection'));
          expect(barPrimaryEnabled(tester), isFalse);
        }
        await _release(tester);
      });
    }

    testWidgets(
        'below the venue minimum under a block: the button only writes the '
        'minimum, nothing is placed (issue for fw37: it should be disabled '
        'like the trade button)', (tester) async {
      final policy = (await tester.runAsync(() => installMarketGatingPolicy(
          MarketDenial.masterOff,
          targets: {'hyperliquid.trade'})))!;
      await _pump(
          tester,
          policy,
          const HlOrderSlipSheet(
              market: _perp, initialIsLong: true, initialUsd: 10),
          _hlOverrides);
      expect(_note(MarketDenial.masterOff.message), findsOneWidget);
      expect(barPrimaryLabel(tester), startsWith('Minimum'));
      await tapBarPrimary(tester, settle: false);
      await _frames(tester);
      // The minimum is written; the order button that follows is shut.
      expect(barPrimaryLabel(tester), isNot(startsWith('Minimum')));
      expect(barPrimaryEnabled(tester), isFalse);
      expect(_note(MarketDenial.masterOff.message), findsOneWidget);
      await _release(tester);
    });

    testWidgets(
        'swap country block: a spot Sell is an exit, no refusal on the slip',
        (tester) async {
      final policy = (await tester.runAsync(
          () => installMarketGatingPolicy(MarketDenial.swapCountryBlock)))!;
      await _pump(
          tester,
          policy,
          const HlOrderSlipSheet(market: _spot, initialIsLong: false),
          _hlOverrides);
      expect(_note(MarketDenial.swapCountryBlock.message), findsNothing);
      expect(barPrimaryLabel(tester), isNot('Check connection'));
      expect(policy.allows('hyperliquid.close'), isTrue);
      await _release(tester);
    });
  });

  group('the Predictions bet slip (Yes / No)', () {
    PolySlipCta cta(WidgetTester tester) =>
        tester.widget<PolySlipCta>(find.byType(PolySlipCta));

    for (final how in MarketDenial.values) {
      testWidgets('${how.label}: the slip opens and says why it cannot place',
          (tester) async {
        final policy = (await tester.runAsync(() =>
            installMarketGatingPolicy(how, targets: {'polymarket.trade'})))!;
        await _pump(
            tester,
            policy,
            const BetSlipSheet(
                marketQuestion: 'Will it rain?',
                marketSlug: 'will-it-rain',
                outcomes: _outcomes,
                initialAmountUsd: 10),
            _pmOverrides);
        expect(_note(how.message), findsOneWidget);
        if (how == MarketDenial.swapCountryBlock) {
          expect(cta(tester).label, 'Check connection');
          expect(cta(tester).enabled, isTrue);
        } else {
          expect(cta(tester).label, isNot('Check connection'));
          expect(cta(tester).enabled, isFalse);
        }
        await _release(tester);
      });
    }

    for (final how in MarketDenial.values
        .where((h) => h != MarketDenial.swapCountryBlock)) {
      testWidgets(
          '${how.label} on sports: a sports slip says so, trading itself '
          'allowed', (tester) async {
        final policy = (await tester.runAsync(() => installMarketGatingPolicy(
            how,
            targets: {kPolymarketSportsCapability})))!;
        expect(policy.allows('polymarket.trade'), isTrue);
        await _pump(
            tester,
            policy,
            const BetSlipSheet(
                marketQuestion: 'Lakers vs. Celtics',
                marketSlug: 'nba-lal-bos-2026-11-08',
                outcomes: _outcomes,
                marketCategory: 'sports',
                initialAmountUsd: 10),
            _pmOverrides);
        expect(_note(how.message), findsOneWidget);
        expect(cta(tester).enabled, isFalse);
        await _release(tester);
      });
    }
  });
}
