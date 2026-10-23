// A venue balance that could not be read is UNKNOWN, never $0.00:
//   * Predictions: every Polygon server failing made the model answer its
//     cache, 0 on a fresh model, and the account read it as a known $0.00
//     (and saved it). The model now throws, and the readers keep the last
//     balance read, dimmed, never counting the 0 into a total;
//   * Investing: a failed first account read still marked the trading
//     state initialized with zeros. It stays uninitialized until a real
//     snapshot lands, which initializes it;
//   * the totals built on them (the Investments header, the Portfolio's
//     venue figures) treat the venue as not known.
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/models/hyperliquid_model.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/investment_balances_provider.dart';
import 'package:kute/providers/polymarket_combos_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/swap_orders_provider.dart';
import 'package:kute/providers/unified_balances_provider.dart';
import 'package:kute/screens/portfolio/open_investments_screen.dart'
    show InvestmentsProduct;

import '../helpers/fake_swap_orders.dart';

const _owner = '0x1111111111111111111111111111111111111111';
const _hlAddress = '0x2222222222222222222222222222222222222222';

Settings _settings() => Settings(
      currency: 'USD',
      language: 'en',
      btcFormat: 'sats',
      backup: false,
      biometricsEnabled: false,
      bitcoinElectrumNode: 'x',
      nodeType: 'x',
      reviewDone: true,
      activeWalletId: 'spend',
      wallets: [
        WalletConfig(id: 'spend', name: 'Spending', sparkEnabled: true)
      ],
    );

/// The Predictions account as the test sets it.
class _Pm extends PolymarketTradingNotifier {
  _Pm(this.value);
  final PolymarketTradingState value;
  @override
  Future<PolymarketTradingState> build() async => value;
}

/// The Investing account read: fails until [land] hands it a snapshot.
class _FlakyAccount extends HlAccountNotifier {
  @override
  Future<HlAccountSnapshot> build() async =>
      throw http.ClientException('hyperliquid down');
  void land(HlAccountSnapshot snap) => state = AsyncData(snap);
}

class _Model extends Fake implements HyperliquidModel {
  @override
  Future<List<HlOpenOrder>> getOpenOrders(String address,
          {Iterable<String> dexes = const []}) async =>
      const [];
  @override
  Future<List<HlFill>> getUserFills(String address) async => const [];
}

void main() {
  group('Predictions model', () {
    test('every server failing on a fresh model is unknown, never 0',
        () async {
      final model = PolymarketModel()
        ..debugRpcClient =
            MockClient((_) async => http.Response('bad gateway', 502));
      await expectLater(model.getOnChainUsdcBalance(_owner),
          throwsA(isA<PolymarketBalanceUnavailable>()));
      await expectLater(model.getOnChainStablesBreakdown(_owner),
          throwsA(isA<PolymarketBalanceUnavailable>()));
    });

    test('a read that succeeded with 0 is a real 0', () async {
      final model = PolymarketModel()
        ..debugRpcClient = MockClient((request) async {
          final batch = jsonDecode(request.body) as List;
          return http.Response(
              jsonEncode([
                for (final call in batch.cast<Map<String, dynamic>>())
                  {'jsonrpc': '2.0', 'id': call['id'], 'result': '0x'},
              ]),
              200);
        });
      expect(await model.getOnChainUsdcBalance(_owner), 0);
    });
  });

  group('Predictions readers', () {
    const unread = PolymarketTradingState(
      isAuthenticated: true,
      walletAddress: _owner,
      proxyWalletAddress: _owner,
      balanceKnown: false,
    );

    test('a cash read that failed gives no Available and no total', () {
      final b = polymarketInvestmentBalances(state: unread, orders: const []);
      expect(b.available, isNull);
      expect(b.total, isNull);
      expect(b.committed, isNull);
      // A real $0.00 still reads as one.
      final zero = polymarketInvestmentBalances(
          state: unread.copyWith(balanceKnown: true), orders: const []);
      expect(zero.available, 0);
      expect(zero.total, 0);
    });

    ProviderContainer container(PolymarketTradingState pm,
        {double lastKnown = 9.75}) {
      final c = ProviderContainer(overrides: [
        settingsProvider.overrideWith((ref) => SettingsModel(_settings())),
        polymarketTradingProvider.overrideWith(() => _Pm(pm)),
        polymarketBalanceProvider.overrideWithValue(lastKnown),
        polymarketCombosValueProvider.overrideWithValue(0),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test(
        'the Investments total keeps the last balance read, marked not '
        'known, instead of counting a 0', () async {
      final c = container(unread);
      c.listen(unifiedVenueBalancesProvider, (_, __) {});
      await c.read(polymarketTradingProvider.future);
      final v = c.read(unifiedVenueBalancesProvider);
      expect(v.readyInPredictionsUsd, 9.75);
      expect(v.predictionsKnown, isFalse,
          reason: 'the header shows it dimmed (stale), not as final');
      final header = c.read(investmentBalancesProvider(
          InvestmentsProduct.predictions));
      expect(header.total, isNull,
          reason: "the header falls back to the last known total, dimmed");
    });

    test('a read that succeeded counts as known', () async {
      final c = container(unread.copyWith(balanceKnown: true, usdcBalance: 4));
      c.listen(unifiedVenueBalancesProvider, (_, __) {});
      await c.read(polymarketTradingProvider.future);
      final v = c.read(unifiedVenueBalancesProvider);
      expect(v.readyInPredictionsUsd, 4);
      expect(v.predictionsKnown, isTrue);
    });
  });

  group('Investing', () {
    test(
        'a failed first account read is unknown, not an initialized \$0.00; '
        'the first snapshot that lands initializes it', () async {
      final c = ProviderContainer(overrides: [
        settingsProvider.overrideWith((ref) => SettingsModel(_settings())),
        hyperliquidAddressProvider.overrideWith((_) async => _hlAddress),
        hyperliquidAccountProvider.overrideWith(_FlakyAccount.new),
        hyperliquidTradingModelProvider.overrideWithValue(_Model()),
        swapOrdersProvider.overrideWith((_) => FakeSwapOrders()),
        // Predictions out of the way (no account).
        polymarketTradingProvider.overrideWith(
            () => _Pm(const PolymarketTradingState(balanceKnown: false))),
        polymarketBalanceProvider.overrideWithValue(0),
        polymarketCombosValueProvider.overrideWithValue(0),
      ]);
      addTearDown(c.dispose);
      c.read(hyperliquidProvisionedProvider.notifier).state = true;
      c.listen(hyperliquidTradingProvider, (_, __) {});
      c.listen(unifiedVenueBalancesProvider, (_, __) {});

      final first = await c.read(hyperliquidTradingProvider.future);
      expect(first.isInitialized, isFalse);
      expect(first.walletAddress, _hlAddress);
      expect(c.read(unifiedVenueBalancesProvider).investingKnown, isFalse);
      expect(
          c.read(investmentBalancesProvider(InvestmentsProduct.trading)).total,
          isNull);

      // The account provider's retry (or a refresh) lands a snapshot.
      (c.read(hyperliquidAccountProvider.notifier) as _FlakyAccount)
          .land(const HlAccountSnapshot(
        accountValue: 0,
        withdrawable: 7.5,
        totalMarginUsed: 0,
        positions: [],
        spotBalances: [],
      ));
      await Future<void>.delayed(Duration.zero);
      final landed = c.read(hyperliquidTradingProvider).valueOrNull!;
      expect(landed.isInitialized, isTrue);
      expect(landed.withdrawable, 7.5);
      final v = c.read(unifiedVenueBalancesProvider);
      expect(v.investingKnown, isTrue);
      expect(v.readyInInvestingUsd, 7.5);
    });
  });
}
