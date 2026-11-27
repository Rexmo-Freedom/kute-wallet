// The Predictions Advanced pages with a limit set (the audit before the
// owner switches `trading.advanced` on):
//   * the buy page: the limit price seeds on the market's tick (a 53.5¢ mid
//     seeds 53¢), its steps stay on it, a tick that arrives later re-seeds
//     an untouched price and says a hand-set one off it (the button shut),
//     the minimum stake at 28¢ buys 5.00 shares (never the 4.99 that
//     1.40 / 0.28 floored to), the order's rows (Limit, Until canceled) and
//     this market's resting orders on the page;
//   * the sell page: the price seeds on the tick, the venue's 5-share
//     minimum and the shares held in resting sells are said in red with
//     the button shut, Max sells what is free;
//   * the receipt rows of a resting buy and where a placed limit leaves the
//     navigator (P7, also in test/render/wide_predictions_render_test.dart).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/generated/app_localizations_en.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/advisor_provider.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_cost_basis_provider.dart';
import 'package:kute/providers/polymarket_limit_terms_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_open_orders_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider;
import 'package:kute/screens/polymarket/components/bet_slip_sheet.dart';
import 'package:kute/screens/polymarket/components/sell_sheet.dart';
import 'package:kute/screens/polymarket/market_detail_sheet.dart';
import 'package:kute/screens/shared/amount_keypad_panel.dart';
import 'package:kute/screens/shared/kute_back_button.dart';
import 'package:kute/services/one_balance/predictions_venue_funder.dart'
    show PredictionsVenueFunder;
import 'package:kute/services/runtime_capabilities_service.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/theme/app_theme.dart';
import 'package:money2/money2.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart' show Order;

import '../../helpers/fake_swap_orders.dart';
import '../../helpers/runtime_policy_fixture.dart';
import '../../helpers/shell_bar_harness.dart';

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
  _Trading(this.orders);
  final List<Order> orders;
  @override
  Future<void> refresh() async {}
  @override
  Future<PolymarketTradingState> build() async =>
      PolymarketTradingState(usdcBalance: 100, openOrders: orders);
}

class _Currency extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _Currency() : super(CurrencyState({'USD': Fixed.fromInt(100)}));
  @override
  Future<void> updateRates() async {}
}

class _NoCostBasis extends StateNotifier<Map<String, double>>
    implements PolymarketCostBasisNotifier {
  _NoCostBasis() : super(const {});
  @override
  Future<void> addCost(String tokenId, double paidUsdc) async {}
  @override
  Future<void> reset(String tokenId) async {}
  @override
  Future<void> scaleByRemaining(
      String tokenId, double fractionRemaining) async {}
  @override
  double? costFor(String tokenId) => null;
}

/// The market's limit terms as the test sets them, changeable mid-test.
final _terms = StateProvider<PolymarketLimitTerms>(
    (ref) => const PolymarketLimitTerms(tick: 0.01, minShares: 5));

Order _order(String token, String side, double size,
        {double price = 0.4, double matched = 0}) =>
    Order(
      id: 'o-$token-$side-$size',
      market: 'c1',
      assetId: token,
      owner: 'x',
      side: side,
      price: '$price',
      originalSize: '$size',
      sizeMatched: '$matched',
      outcome: 'Yes',
    );

SettingsModel _settings() => SettingsModel(Settings(
  currency: 'USD',
  language: 'en',
  btcFormat: 'sats',
  backup: false,
  biometricsEnabled: false,
  bitcoinElectrumNode: '',
  nodeType: '',
  reviewDone: true,
));

List<Override> _overrides(List<Order> orders) => [
      settingsProvider.overrideWith((ref) => _settings()),
      polymarketTradingProvider.overrideWith(() => _Trading(orders)),
      swapOrdersProvider.overrideWith((ref) => FakeSwapOrders()),
      livePriceProvider.overrideWith(_Prices.new),
      polymarketOpenOrdersProvider.overrideWith((ref) => Stream.value(orders)),
      aiEnabledProvider.overrideWith((ref) async => false),
      usdBalanceProvider.overrideWithValue(0),
      currencyProvider.overrideWith((ref) => _Currency()),
      polymarketCostBasisProvider.overrideWith((ref) => _NoCostBasis()),
      polymarketLimitTermsProvider
          .overrideWith((ref, _) async => ref.watch(_terms)),
    ];

Future<RuntimeCapabilitiesService> _allow() async {
  AffiliateService.debugSessionToken = 'test-session';
  final policy = runtimePolicyFixture();
  RuntimeCapabilitiesService.debugInstance = policy;
  expect(await policy.refresh(), isTrue);
  return policy;
}

Future<void> _release(
    WidgetTester tester, RuntimeCapabilitiesService policy) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
  policy.dispose();
  RuntimeCapabilitiesService.debugInstance = null;
  AffiliateService.debugSessionToken = null;
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<ProviderContainer> _pumpSlip(WidgetTester tester,
    {required double price, List<Order> orders = const []}) async {
  _phone(tester);
  installShellBar();
  await tester.pumpWidget(ProviderScope(
    overrides: _overrides(orders),
    child: shellBarApp(
      home: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Align(
          alignment: Alignment.bottomCenter,
          child: BetSlipSheet(
            marketQuestion: 'Will it rain?',
            outcomes: [
              PolymarketOutcome(
                  name: 'Yes',
                  price: price,
                  tokenId: 'yes-t',
                  conditionId: 'c1'),
              PolymarketOutcome(
                  name: 'No',
                  price: 1 - price,
                  tokenId: 'no-t',
                  conditionId: 'c1'),
            ],
            initialAmountUsd: 10,
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(
      tester.element(find.byType(BetSlipSheet).first));
}

Future<void> _openLimit(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('slip-advanced-button')));
  await tester.pumpAndSettle();
  expect(find.text('Advanced prediction'), findsOneWidget);
  await tester.ensureVisible(find.text('Limit'));
  await tester.tap(find.text('Limit'));
  await tester.pumpAndSettle();
}

String _limitPrice(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;

Future<void> _step(WidgetTester tester, IconData icon) async {
  await tester.ensureVisible(find.byIcon(icon).last);
  await tester.tap(find.byIcon(icon).last);
  await tester.pumpAndSettle();
}

PolymarketPosition _position({double size = 10, double price = 0.535}) =>
    PolymarketPosition(
      marketId: 'c1',
      marketQuestion: 'Will it rain?',
      outcome: 'Yes',
      size: size,
      avgPrice: 0.4,
      currentPrice: price,
      pnl: 0,
      pnlPercent: 0,
      isResolved: false,
      tokenId: 'yes-t',
    );

Future<void> _pumpSell(WidgetTester tester,
    {List<Order> orders = const [], double size = 10}) async {
  _phone(tester);
  installShellBar();
  await tester.pumpWidget(ProviderScope(
    overrides: _overrides(orders),
    child: shellBarApp(
      theme: ThemeData(
        splashFactory: NoSplash.splashFactory,
        extensions: [AppColorsExtension.light()],
      ),
      home: Scaffold(
          body: SellSheet(
              position: _position(size: size), startWithLimit: true)),
    ),
  ));
  // The trading state lands, then the Advanced page opens on the limit.
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

Future<void> _typeSellAmount(WidgetTester tester, String amount) async {
  await tester.enterText(find.byType(TextField), amount);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    PredictionsVenueFunder.debugRouteShare = (_) async => 0;
  });
  tearDown(() => PredictionsVenueFunder.debugRouteShare = null);

  group('the Advanced buy page, a limit', () {
    testWidgets('P1: a 53.5¢ mid seeds 53¢; the steps stay on the tick',
        (tester) async {
      final policy = await _allow();
      await _pumpSlip(tester, price: 0.535);
      await _openLimit(tester);
      expect(_limitPrice(tester, 'bet-slip-limit-price'), '53¢');
      await _step(tester, Icons.add_rounded);
      expect(_limitPrice(tester, 'bet-slip-limit-price'), '54¢');
      await _step(tester, Icons.remove_rounded);
      await _step(tester, Icons.remove_rounded);
      expect(_limitPrice(tester, 'bet-slip-limit-price'), '52¢');
      expect(find.byKey(const ValueKey('bet-slip-limit-issue')), findsNothing);
      expect(find.textContaining(r'Place $10.00 limit at 52'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _release(tester, policy);
    });

    testWidgets(
        'P1: the tick arriving re-seeds an untouched price; a price set '
        'by hand off it is said in red and shuts the button', (tester) async {
      final policy = await _allow();
      final container = await _pumpSlip(tester, price: 0.535);
      container.read(_terms.notifier).state =
          const PolymarketLimitTerms(tick: 0.1, minShares: 5);
      await tester.pumpAndSettle();
      await _openLimit(tester);
      // A 10¢ market: the seed at or under the mid on its tick.
      expect(_limitPrice(tester, 'bet-slip-limit-price'), '50¢');
      await _step(tester, Icons.add_rounded);
      expect(_limitPrice(tester, 'bet-slip-limit-price'), '60¢');
      // Back to a 1¢ market, then a hand step to 61¢, then 10¢ again.
      container.read(_terms.notifier).state =
          const PolymarketLimitTerms(tick: 0.01, minShares: 5);
      await tester.pumpAndSettle();
      await _step(tester, Icons.add_rounded);
      expect(_limitPrice(tester, 'bet-slip-limit-price'), '61¢');
      container.read(_terms.notifier).state =
          const PolymarketLimitTerms(tick: 0.1, minShares: 5);
      await tester.pumpAndSettle();
      expect(_limitPrice(tester, 'bet-slip-limit-price'), '61¢');
      expect(find.text('Pick a price in steps of 10¢.'), findsOneWidget);
      final issue =
          tester.widget<Text>(find.byKey(const ValueKey('bet-slip-limit-issue')));
      expect(issue.style?.color, AppColors.error);
      expect(find.byKey(const ValueKey('bet-slip-limit-shut')), findsOneWidget);
      // One step puts it back on the tick and opens the button.
      await _step(tester, Icons.add_rounded);
      expect(_limitPrice(tester, 'bet-slip-limit-price'), '70¢');
      expect(find.byKey(const ValueKey('bet-slip-limit-issue')), findsNothing);
      expect(find.byKey(const ValueKey('bet-slip-limit-shut')), findsNothing);
      expect(tester.takeException(), isNull);
      await _release(tester, policy);
    });

    testWidgets(
        'P2: at 28¢ the minimum is \$1.40, which buys 5.00 shares; a cent '
        'under is said in red with the shares', (tester) async {
      final policy = await _allow();
      await _pumpSlip(tester, price: 0.28);
      await _openLimit(tester);
      expect(_limitPrice(tester, 'bet-slip-limit-price'), '28¢');
      await tester.enterText(find.byType(TextField), '1.40');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('bet-slip-minimum-warning')),
          findsNothing);
      expect(find.textContaining(r'Place $1.40 limit at 28'), findsOneWidget);
      // The shares the order signs: 5.00, never 4.99.
      await tester.ensureVisible(find.text('Details'));
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(find.text('5.00'), findsOneWidget);
      expect(find.text('4.99'), findsNothing);
      // The order's rows: what it is and how long it stands.
      expect(find.text('Order type'), findsOneWidget);
      expect(find.text('Limit'), findsWidgets);
      expect(find.text('Until canceled'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '1.39');
      await tester.pumpAndSettle();
      final warning = tester.widget<Text>(
          find.byKey(const ValueKey('bet-slip-minimum-warning')));
      expect(warning.data,
          r'Minimum is $1.40. The smallest order here is 5 shares.');
      expect(warning.style?.color, AppColors.error);
      // The button offers the minimum stake instead of the bet.
      expect(find.text(r'Minimum $1.40'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _release(tester, policy);
    });

    testWidgets('this market\'s resting orders are listed on the page',
        (tester) async {
      final policy = await _allow();
      await _pumpSlip(tester,
          price: 0.5,
          orders: [
            _order('yes-t', 'BUY', 25, price: 0.42),
            _order('elsewhere', 'BUY', 9),
          ]);
      await _openLimit(tester);
      final listed = find.byKey(const ValueKey('poly-market-orders'));
      await tester.ensureVisible(listed);
      expect(listed, findsOneWidget);
      expect(find.byKey(const ValueKey('market-order-o-yes-t-BUY-25.0')),
          findsOneWidget);
      expect(
          find.byKey(const ValueKey('market-order-o-elsewhere-BUY-9.0')),
          findsNothing);
      expect(find.text('Cancel'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _release(tester, policy);
    });
  });

  group('the Advanced sell page, a limit', () {
    testWidgets('P1: the price seeds on the tick, at or over the market',
        (tester) async {
      final policy = await _allow();
      await _pumpSell(tester);
      expect(find.text('Advanced sale'), findsOneWidget);
      expect(_limitPrice(tester, 'sell-advanced-limit-price'), '54¢');
      await _step(tester, Icons.add_rounded);
      expect(_limitPrice(tester, 'sell-advanced-limit-price'), '55¢');
      await _step(tester, Icons.remove_rounded);
      await _step(tester, Icons.remove_rounded);
      expect(_limitPrice(tester, 'sell-advanced-limit-price'), '53¢');
      expect(tester.takeException(), isNull);
      await _release(tester, policy);
    });

    testWidgets('P3: under the 5-share minimum is said in red, button shut',
        (tester) async {
      final policy = await _allow();
      await _pumpSell(tester);
      // $2.00 at 54¢ is 3.70 shares.
      await _typeSellAmount(tester, '2');
      expect(find.text('The smallest order here is 5 shares.'), findsOneWidget);
      final issue = tester
          .widget<Text>(find.byKey(const ValueKey('sell-advanced-issue')));
      expect(issue.style?.color, AppColors.error);
      expect(find.textContaining('Sell at 54¢'), findsNothing);
      // $3.00 is 5.55 shares: the sale.
      await _typeSellAmount(tester, '3');
      expect(find.byKey(const ValueKey('sell-advanced-issue')), findsNothing);
      expect(find.text('Sell at 54¢ · limit'), findsOneWidget);
      // Its rows.
      await tester.ensureVisible(find.text('Details'));
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(find.text('Order type'), findsOneWidget);
      expect(find.text('Until canceled'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _release(tester, policy);
    });

    testWidgets(
        'P4: shares in resting sells are stated and not offered again; Max '
        'on the sheet sells what is free', (tester) async {
      final policy = await _allow();
      await _pumpSell(tester, size: 10, orders: [
        _order('yes-t', 'SELL', 6, price: 0.7),
        _order('yes-t', 'BUY', 3),
      ]);
      expect(find.textContaining('6.00 shares in open orders'), findsWidgets);
      // 4 free shares at 54¢: $2.16 of them. $3.00 asks 5.55.
      await _typeSellAmount(tester, '3');
      expect(
          find.text('Only 4.00 shares are free to sell. The rest are in your '
              'open orders.'),
          findsOneWidget);
      expect(find.textContaining('Sell at 54¢'), findsNothing);
      // Under the minimum too once it fits: 4 free shares can never make
      // a 5-share order, so the sale stays shut.
      await _typeSellAmount(tester, '2.16');
      expect(find.text('The smallest order here is 5 shares.'), findsOneWidget);
      // Back on the sheet, Max is the free shares, not the position.
      await tester.tap(find.byType(KuteBackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Use maximum'));
      await tester.pumpAndSettle();
      expect(
          tester.widget<BigAmountDisplay>(find.byType(BigAmountDisplay))
              .amountText,
          '2.16');
      expect(find.textContaining('6.00 shares in open orders'), findsWidgets);
      expect(tester.takeException(), isNull);
      await _release(tester, policy);
    });
  });

  group('a plain market sale (Advanced off), no resting sells', () {
    testWidgets(
        'Max on a fractional position sells every share and reports a whole '
        'sale, exactly as before', (tester) async {
      final events = <(String, Map<String, Object>?)>[];
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
      addTearDown(() => TrackingService.debugTrackObserver = null);
      final policy = await _allow();
      _phone(tester);
      installShellBar();
      await tester.pumpWidget(ProviderScope(
        overrides: _overrides(const []),
        child: shellBarApp(
          theme: ThemeData(
            splashFactory: NoSplash.splashFactory,
            extensions: [AppColorsExtension.light()],
          ),
          home: Scaffold(
              body: SellSheet(position: _position(size: 18.6049, price: 0.15))),
        ),
      ));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(find.bySemanticsLabel('Use maximum'));
      await tester.pump();
      expect(find.byKey(const ValueKey('poly-sell-issue')), findsNothing);
      expect(find.textContaining('in open orders'), findsNothing);
      // The step event carries what is entered: the whole position.
      await tester.tap(find.byKey(const ValueKey('slip-advanced-button')));
      await tester.pumpAndSettle();
      final step = events
          .where((e) =>
              e.$1 == 'polymarket_sell_step' && e.$2?['step'] == 'advanced')
          .single
          .$2!;
      expect(step['sell_scope'], 'all');
      expect(step['pct_of_position'], 100);
      expect(step['shares'], 18.6049);
      expect(tester.takeException(), isNull);
      await _release(tester, policy);
    });
  });

  group('after the order', () {
    test('a resting buy\'s receipt says what it is and what it holds', () {
      final l10n = AppLocalizationsEn();
      final rows = betSlipRestingRows(l10n,
          price: 0.28, shares: 5, money: (v) => '\$${v.toStringAsFixed(2)}');
      expect(rows, {
        'Order type': 'Limit',
        'Limit price': '28%',
        'Shares': '5.00',
        'Duration': 'Until canceled',
        'Reserved': r'$1.40',
      });
    });

    testWidgets(
        'P7: a limit placed over a slip in place keeps the market page; on '
        'a phone the market sheet closes with the slip', (tester) async {
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
          navigatorKey: key, home: const Scaffold(body: Text('home'))));
      Future<void> stack() async {
        key.currentState!.push(MaterialPageRoute<void>(
            settings: const RouteSettings(name: MarketDetailSheet.routeName),
            builder: (_) => const Scaffold(body: Text('market'))));
        key.currentState!.push(MaterialPageRoute<void>(
            settings: const RouteSettings(name: BetSlipSheet.routeName),
            builder: (_) => const Scaffold(body: Text('advanced'))));
        await tester.pumpAndSettle();
      }

      await stack();
      popBetSlipRoutes(key.currentState!, keepMarketPage: true);
      await tester.pumpAndSettle();
      expect(find.text('market'), findsOneWidget);
      expect(find.text('advanced'), findsNothing);
      key.currentState!.pop();
      await tester.pumpAndSettle();
      await stack();
      popBetSlipRoutes(key.currentState!, keepMarketPage: false);
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
      expect(find.text('market'), findsNothing);
    });
  });
}
