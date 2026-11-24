// The full-page forms on a laptop (round three; founder, 25 November 2026:
// "it must be all occupying full screen when we can"). The tickets'
// Advanced pages (order, close, trailing stop) open as the shared panel at
// a page's height over the dimmed page, their button inside the panel; the
// Portfolio Builder spans the window, its picks, amounts and review as a
// grid of the existing cards, its total and button under them on one axis.
// Checked for stretch at every EXPANDED size; shot when asked:
// DESK_FULL_RENDER=<dir>.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/platform/kute_wide_frames.dart';
import 'package:kute/providers/advisor_provider.dart' show aiEnabledProvider;
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_orderbook_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/screens/hyperliquid/components/close_position_sheet.dart';
import 'package:kute/screens/hyperliquid/components/order_slip_sheet.dart';
import 'package:kute/screens/hyperliquid/components/trailing_stop_sheet.dart';
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/screens/shared/portfolio_builder/builder_legs_provider.dart';
import 'package:kute/screens/shared/portfolio_builder/portfolio_builder_screen.dart';
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart';

import '../helpers/fake_swap_orders.dart';
import 'desk_full_support.dart';

class _LivePrices extends HlLivePricesNotifier {
  @override
  HlLivePriceState build() =>
      const HlLivePriceState(mids: {'BTC': 66000, 'ETH': 3200, 'SOL': 150});
  @override
  void watchCoins(List<String> coins, {Map<String, String>? wire}) {}
  @override
  void focus(String coin, {String? wire}) {}
  @override
  void unfocus(String coin) {}
  @override
  void acquire() {}
  @override
  void release() {}
}

class _Currency extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _Currency() : super(CurrencyState({'USD': Fixed.fromInt(1)}));
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
  bool allows(String id) => true;
  @override
  Future<void> ensureAllowed(String id,
      {Duration maxAge = Duration.zero}) async {}
  @override
  Future<void> ensureAllAllowed(Iterable<String> ids,
      {Duration maxAge = Duration.zero}) async {}
  @override
  int? get maxLeverage => null;
  @override
  int offeredLeverage(int venueMax) => venueMax;
}

HlMarket _perp(String coin, double px, {int sz = 4}) => HlMarket(
      coin: coin,
      wireCoin: coin,
      assetId: 0,
      kind: HlMarketKind.perp,
      szDecimals: sz,
      maxLeverage: 40,
      onlyIsolated: false,
      markPx: px,
      midPx: px,
      prevDayPx: px * 0.98,
      dayNtlVlm: 1e9,
    );

final _btc = _perp('BTC', 66000, sz: 5);

const _position = HlPerpPosition(
  coin: 'BTC',
  szi: 0.05,
  entryPx: 64000,
  positionValue: 3300,
  unrealizedPnl: 100,
  returnOnEquity: 0.15,
  liquidationPx: 58000,
  marginUsed: 660,
  leverageType: 'isolated',
  leverageValue: 5,
  maxLeverage: 40,
  fundingSinceOpen: 1.25,
);

Settings _settings() => Settings(
      wallets: [WalletConfig(id: 'w1', name: 'Spending')],
      activeWalletId: 'w1',
      currency: 'USD',
      language: 'en',
      btcFormat: 'sats',
      backup: true,
      biometricsEnabled: false,
      bitcoinElectrumNode: '',
      nodeType: '',
      reviewDone: true,
    );

List<Override> _hlOverrides() => [
      settingsProvider.overrideWith((_) => SettingsModel(_settings())),
      hyperliquidLivePricesProvider.overrideWith(_LivePrices.new),
      hyperliquidWithdrawableProvider.overrideWith((_) => 1250),
      hyperliquidSpotBalancesProvider.overrideWith((_) => []),
      hyperliquidPerpPositionsProvider.overrideWith((_) => const [_position]),
      swapOrdersProvider.overrideWith((_) => FakeSwapOrders()),
      hyperliquidAddressProvider.overrideWith((_) async => null),
      hyperliquidOrderbookProvider
          .overrideWith((_, __) => Stream.value(const HlOrderBookState())),
      aiEnabledProvider.overrideWith((_) async => false),
      currencyProvider.overrideWith((_) => _Currency()),
      runtimeCapabilitiesProvider.overrideWithValue(_Allowed()),
    ];

PolymarketEvent _event(String id, String title, double yes) => PolymarketEvent(
        id: id,
        slug: id,
        title: title,
        volume: 2500000,
        liquidity: 100000,
        category: 'politics',
        conditionId: '$id-c',
        outcomes: [
          PolymarketOutcome(name: 'Yes', price: yes, tokenId: '$id-y'),
          PolymarketOutcome(name: 'No', price: 1 - yes, tokenId: '$id-n'),
        ]);

final _events = [
  _event('fed', 'Fed cuts rates in December?', .62),
  _event('rain', 'Will it rain in London tomorrow?', .41),
  _event('btc', 'Bitcoin above \$100k on December 31?', .27),
  _event('nba', 'Lakers win the NBA Finals?', .08),
  _event('ai', 'OpenAI announces a new model this year?', .83),
  _event('gdp', 'US GDP growth above 2% in Q4?', .55),
];

List<Override> _builderOverrides() => [
      runtimeCapabilitiesProvider.overrideWithValue(_Allowed()),
      polymarketEventsProvider('breaking').overrideWith((_) async => _events),
      polymarketEventsProvider('crypto').overrideWith((_) async => []),
      polymarketBalanceProvider.overrideWithValue(250),
      hyperliquidBrowseUniverseProvider.overrideWithValue(AsyncData([
        _btc,
        _perp('ETH', 3200),
        _perp('SOL', 150, sz: 2),
      ])),
      hyperliquidWithdrawableProvider.overrideWithValue(250),
      hyperliquidSpotBalancesProvider.overrideWithValue([]),
    ];

/// A plain page under the panel, its door a button.
Widget _host(void Function(BuildContext, WidgetRef) open) =>
    Consumer(builder: (context, ref, _) {
      return Scaffold(
        backgroundColor: context.colors.background,
        body: Center(
          child: TextButton(
              onPressed: () => open(context, ref), child: const Text('Open')),
        ),
      );
    });

/// The trailing stop's switch sits in a tinted box (a ListTile debug note
/// on every build, not this test's subject).
Future<void> _quiet(Future<void> Function() body) async {
  final original = FlutterError.onError;
  FlutterError.onError = (details) {
    if ('${details.exception}'
        .contains('ListTile background color or ink splashes')) {
      return;
    }
    original?.call(details);
  };
  try {
    await body();
  } finally {
    FlutterError.onError = original;
  }
}

final _barButton = find.byKey(const ValueKey('kute-bar-primary-button'));

typedef _Shot = Future<void> Function(
    WidgetTester tester, Size size, bool dark);

Future<void> _openFromHost(WidgetTester tester, Size size, bool dark,
    void Function(BuildContext, WidgetRef) open) async {
  await pumpDeskPage(tester,
      size: size,
      dark: dark,
      mode: KuteWideMode.own,
      page: _host(open),
      overrides: _hlOverrides());
  await tester.tap(find.text('Open'));
  await deskFullFrames(tester, 20);
}

final Map<String, _Shot> _pages = {
  'order_advanced': (tester, size, dark) async {
    await pumpDeskPage(tester,
        size: size,
        dark: dark,
        mode: KuteWideMode.own,
        page: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            // The slip at a phone's width under the panel, as the
            // market page's pane holds it.
            child: SizedBox(
                width: 430,
                child: HlOrderSlipSheet(market: _btc, initialIsLong: true)),
          ),
        ),
        overrides: _hlOverrides());
    await tester.tap(find.byKey(const ValueKey('slip-advanced-button')));
    await deskFullFrames(tester, 20);
  },
  'close_advanced': (tester, size, dark) => _openFromHost(
      tester,
      size,
      dark,
      (context, ref) => HlClosePositionSheet.showProtect(context, ref,
          position: _position, market: _btc)),
  'trailing_stop': (tester, size, dark) => _openFromHost(
      tester,
      size,
      dark,
      (context, ref) => HlTrailingStopSheet.show(context,
          market: _btc,
          size: 0.05,
          isBuy: false,
          reduceOnly: true,
          leverage: 5,
          isCross: false,
          walletId: 'w1',
          ledger: false)),
  'builder_pick': (tester, size, dark) async {
    await pumpDeskPage(tester,
        size: size,
        dark: dark,
        page: const PortfolioBuilderScreen(pool: BuilderPool.predictions),
        overrides: _builderOverrides());
    for (final i in [0, 2, 4]) {
      await tester.tap(find.text(_events[i].title));
      await tester.pump();
    }
    await deskFullFrames(tester);
  },
  'builder_amounts': (tester, size, dark) async {
    await pumpDeskPage(tester,
        size: size,
        dark: dark,
        page: const PortfolioBuilderScreen(pool: BuilderPool.trading),
        overrides: _builderOverrides());
    for (final name in ['Bitcoin', 'Ethereum', 'Solana']) {
      final f = find.text(name);
      if (f.evaluate().isNotEmpty) await tester.tap(f.first);
    }
    await deskFullFrames(tester, 4);
    await tester.tap(_barButton);
    await deskFullFrames(tester);
  },
  'builder_review': (tester, size, dark) async {
    await pumpDeskPage(tester,
        size: size,
        dark: dark,
        page: const PortfolioBuilderScreen(pool: BuilderPool.trading),
        overrides: _builderOverrides());
    for (final name in ['Bitcoin', 'Ethereum', 'Solana']) {
      final f = find.text(name);
      if (f.evaluate().isNotEmpty) await tester.tap(f.first);
    }
    await deskFullFrames(tester, 4);
    await tester.tap(_barButton);
    await deskFullFrames(tester, 4);
    final scope = ProviderScope.containerOf(
        tester.element(find.byType(PortfolioBuilderScreen)));
    final legs = scope.read(builderTradeLegsProvider.notifier);
    for (final (key, usd) in [('BTC|perp', 40.0), ('ETH|perp', 25.0)]) {
      legs.setAmount(key, usd);
    }
    for (final l in scope.read(builderTradeLegsProvider)) {
      if (l.amountUsd <= 0) legs.setAmount(l.key, 15);
    }
    await deskFullFrames(tester, 4);
    await tester.tap(_barButton);
    await deskFullFrames(tester);
  },
};

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    TrackingService.setDisabled(true);
    OpenOnce.reset();
    RuntimeCapabilitiesService.debugInstance = _Allowed();
  });
  tearDown(() => RuntimeCapabilitiesService.debugInstance = null);

  for (final (label, size) in deskFullExpanded) {
    for (final MapEntry(key: name, value: open) in _pages.entries) {
      testWidgets('$name at $label: nothing stretched', (tester) async {
        await _quiet(() async {
          await open(tester, size, false);
          expect(tester.takeException(), isNull);
          if (name.startsWith('builder')) {
            expectDeskNothingStretched(tester, maxCard: kuteWideColumnMax);
          } else {
            // The panel: its card is the sheet's width, a phone column.
            expect(
                find.byKey(const ValueKey('kute-dialog-card')), findsOneWidget);
            expect(
                find.byKey(const ValueKey('kute-dialog-close')), findsNothing);
            expect(find.byKey(const ValueKey('kute-dialog-primary')),
                findsOneWidget);
            expectDeskNothingStretched(tester, maxCard: kuteWideColumnMax);
          }
          await deskFullEnd(tester);
        });
      });
    }
  }

  for (final (label, size) in [...deskFullExpanded, ...deskFullNarrow]) {
    for (final dark in [false, true]) {
      final mode = dark ? 'dark' : 'light';
      for (final MapEntry(key: name, value: open) in _pages.entries) {
        testWidgets('render: $name $label $mode', skip: deskFullDir == null,
            (tester) async {
          await _quiet(() async {
            await deskFullAssets(tester);
            await open(tester, size, dark);
            await deskFullShoot(tester, '${name}_${label}_$mode');
            await deskFullEnd(tester);
          });
        });
      }
    }
  }
}
