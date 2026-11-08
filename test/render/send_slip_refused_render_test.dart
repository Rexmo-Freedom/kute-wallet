// A look by eye at a slip in SEND MODE refused here (founder, 8 November
// 2026, over the Unavailable sheet on the What step's gift: "only on the
// last screen, the bet slip, show this error"): the bet slip and the order
// slip opened from the gift search, the market's trade refused by the
// backend. For a region, the slip's own reason over its one button, "Check
// connection"; for any other refusal, the reason over the send, disabled.
// Light and dark, on a 390 pt phone. Every frame lays out without an
// overflow; the PNGs are written only when asked:
//
//   SEND_SLIP_REFUSED_RENDER=<dir> flutter test \
//     test/render/send_slip_refused_render_test.dart

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/affiliate_model.dart';
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
import 'package:kute/providers/usd_account_provider.dart';
import 'package:kute/screens/hyperliquid/components/order_slip_sheet.dart';
import 'package:kute/screens/polymarket/components/bet_slip_sheet.dart';
import 'package:kute/screens/share/send_pick_session.dart';
import 'package:kute/screens/share/slip_share.dart';
import 'package:kute/screens/shared/capability_block_note.dart';
import 'package:kute/services/investment_provider_availability.dart';
import 'package:kute/services/polymarket/polymarket_fee_terms.dart';
import 'package:kute/services/region_freshness.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:money2/money2.dart';

import '../helpers/fake_swap_orders.dart';
import '../helpers/runtime_policy_fixture.dart';
import '../helpers/shell_bar_harness.dart';
import '../screens/share/cards/share_card_test_fonts.dart';

final _dir = Platform.environment['SEND_SLIP_REFUSED_RENDER'];

class _PolyPrices extends LivePriceNotifier {
  @override
  LivePriceState build() => const LivePriceState();
  @override
  void acquire() {}
  @override
  void release() {}
  @override
  void addTokens(List<String> tokenIds, {bool pin = true}) {}
}

class _PolyTrading extends PolymarketTradingNotifier {
  @override
  Future<PolymarketTradingState> build() async =>
      const PolymarketTradingState(usdcBalance: 100);
}

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

class _HlAccount extends HlAccountNotifier {
  @override
  Future<HlAccountSnapshot> build() async => const HlAccountSnapshot(
        accountValue: 500,
        withdrawable: 500,
        totalMarginUsed: 0,
        positions: [],
        spotBalances: [],
      );
}

class _Currency extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _Currency() : super(CurrencyState({'USD': Fixed.fromInt(1)}));
  @override
  Future<void> updateRates() async {}
}

const _outcomes = [
  PolymarketOutcome(name: 'Yes', price: 0.62, tokenId: 'yes-token'),
  PolymarketOutcome(name: 'No', price: 0.38, tokenId: 'no-token'),
];

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

void main() {
  late InvestmentProviderAvailability venues;

  setUpAll(loadShareCardFonts);

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    AffiliateService.debugSessionToken = 'render-session';
    venues = InvestmentProviderAvailability(
      client: MockClient((request) async => request.url.host ==
              'api.hyperliquid.xyz'
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
    RuntimeCapabilitiesService.debugInstance = null;
    AffiliateService.debugSessionToken = null;
    RegionFreshness.debugVenues = null;
    venues.dispose();
  });

  Future<RuntimeCapabilitiesService> install(
      WidgetTester tester, bool region) async {
    final policy = runtimePolicyFixture(
      blocked: const {'polymarket.trade', 'hyperliquid.trade'},
      reasons: region
          ? const {
              'polymarket.trade': 'country_blocked',
              'hyperliquid.trade': 'country_blocked',
            }
          : const {},
      decorations: const {
        'polymarket.trade': {
          'regions': {'label': 'the places Polymarket restricts'}
        },
        'hyperliquid.trade': {
          'regions': {'label': 'the places Hyperliquid restricts'}
        },
      },
      also: const {'polymarket.browse', 'hyperliquid.browse'},
    );
    RuntimeCapabilitiesService.debugInstance = policy;
    await tester.runAsync(policy.refresh);
    return policy;
  }

  Future<void> capture(WidgetTester tester, String name) async {
    final error = tester.takeException();
    expect(error, isNull, reason: '$name: $error');
    final dir = _dir;
    if (dir == null) return;
    final view = tester.binding.renderViews.first;
    final layer = view.debugLayer! as OffsetLayer;
    await tester.runAsync(() async {
      final image =
          await layer.toImage(Offset.zero & view.size, pixelRatio: 3);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(dir).createSync(recursive: true);
      File('$dir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  }

  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pump(WidgetTester tester, Widget slip,
      {required bool dark,
      required RuntimeCapabilitiesService policy}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    installShellBar();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingsProvider.overrideWith((ref) => SettingsModel(Settings(
              currency: 'USD',
              language: 'en',
              btcFormat: 'sats',
              backup: false,
              biometricsEnabled: false,
              bitcoinElectrumNode: '',
              nodeType: 'Blockstream',
              reviewDone: true,
            ))),
        polymarketTradingProvider.overrideWith(_PolyTrading.new),
        livePriceProvider.overrideWith(_PolyPrices.new),
        polymarketOpenOrdersProvider
            .overrideWith((ref) => Stream.value(const <Order>[])),
        polymarketFeeTermsProvider
            .overrideWith((ref, _) async => PolymarketFeeTerms.worstCase),
        hyperliquidLivePricesProvider.overrideWith(_HlPrices.new),
        hyperliquidAccountProvider.overrideWith(_HlAccount.new),
        hyperliquidAddressProvider.overrideWith((_) async => null),
        hyperliquidOrderbookProvider
            .overrideWith((_, __) => Stream.value(const HlOrderBookState())),
        swapOrdersProvider.overrideWith((ref) => FakeSwapOrders()),
        aiEnabledProvider.overrideWith((ref) async => false),
        currencyProvider.overrideWith((ref) => _Currency()),
        usdBalanceProvider.overrideWith((_) => 0),
        runtimeCapabilitiesProvider.overrideWithValue(policy),
      ],
      child: shellBarApp(
        dark: dark,
        home: Scaffold(
          resizeToAvoidBottomInset: false,
          body: Align(alignment: Alignment.bottomCenter, child: slip),
        ),
      ),
    ));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await frames(tester);
  }

  SendPickSession session() =>
      SendPickSession(entrySource: 'dollar_send', recipientName: 'Ana');

  // Blocked on one venue and not on the other (the founder's case): one
  // policy, an Investing market goes through and a prediction stops at its
  // slip with the message, no link.
  testWidgets(
      'Predictions refused for a region, Investing open: the Investing slip '
      'sends, the prediction\'s slip stops with the message', (tester) async {
    final sends = <SlipSendRoute>[];
    SlipShare.debugRoute = (route, _) => sends.add(route);
    SlipShare.debugOpen = false;
    addTearDown(() {
      SlipShare.debugRoute = null;
      SlipShare.debugOpen = true;
    });
    final policy = runtimePolicyFixture(
      blocked: const {'polymarket.trade'},
      reasons: const {'polymarket.trade': 'country_blocked'},
      decorations: const {
        'polymarket.trade': {
          'regions': {'label': 'the places Polymarket restricts'}
        },
      },
      also: const {'polymarket.browse', 'hyperliquid.browse'},
    );
    RuntimeCapabilitiesService.debugInstance = policy;
    await tester.runAsync(policy.refresh);

    await pump(
        tester,
        HlOrderSlipSheet(
            market: _market,
            initialIsLong: true,
            initialUsd: 25,
            sendPick: session()),
        dark: false,
        policy: policy);
    expect(find.byType(CapabilityBlockNote), findsNothing);
    expect(barPrimaryLabel(tester), r'Send $25 · Long Bitcoin');
    await tester.runAsync(() async {
      await tester.tap(findBarPrimary());
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await frames(tester);
    expect(sends, [SlipSendRoute.pick]);
    sends.clear();
    await tester.pumpWidget(const SizedBox.shrink());
    await frames(tester);

    await pump(
        tester,
        BetSlipSheet(
            marketQuestion: 'Will Bitcoin reach \$150k this year?',
            marketSlug: 'btc-150k',
            outcomes: _outcomes,
            initialAmountUsd: 10,
            sendPick: session()),
        dark: false,
        policy: policy);
    expect(
        find.descendant(
            of: find.byType(CapabilityBlockNote),
            matching: find.textContaining(
                'Not available in the places Polymarket restricts')),
        findsOneWidget);
    expect(barPrimaryLabel(tester), 'Check connection');
    expect(sends, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    policy.dispose();
  });

  for (final dark in [false, true]) {
    final theme = dark ? 'dark' : 'light';
    for (final region in [true, false]) {
      final why = region ? 'region' : 'switch';

      testWidgets('render: bet-slip-send-$why-$theme', (tester) async {
        final policy = await install(tester, region);
        await pump(
            tester,
            BetSlipSheet(
                marketQuestion: 'Will Bitcoin reach \$150k this year?',
                marketSlug: 'btc-150k',
                outcomes: _outcomes,
                initialAmountUsd: 10,
                sendPick: session()),
            dark: dark,
            policy: policy);
        expect(find.byType(CapabilityBlockNote), findsOneWidget);
        expect(barPrimaryLabel(tester),
            region ? 'Check connection' : r'Send $10 · Yes');
        expect(barPrimaryEnabled(tester), region);
        await capture(tester, 'bet-slip-send-$why-$theme');
        await tester.pumpWidget(const SizedBox.shrink());
        policy.dispose();
      });

      testWidgets('render: order-slip-send-$why-$theme', (tester) async {
        final policy = await install(tester, region);
        await pump(
            tester,
            HlOrderSlipSheet(
                market: _market,
                initialIsLong: true,
                initialUsd: 25,
                sendPick: session()),
            dark: dark,
            policy: policy);
        expect(find.byType(CapabilityBlockNote), findsOneWidget);
        expect(barPrimaryLabel(tester),
            region ? 'Check connection' : r'Send $25 · Long Bitcoin');
        expect(barPrimaryEnabled(tester), region);
        await capture(tester, 'order-slip-send-$why-$theme');
        await tester.pumpWidget(const SizedBox.shrink());
        policy.dispose();
      });
    }
  }
}
