// The order of sources for every funded order (founder decision, 15
// October 2026: "We should always prioritize bitcoin balances and usdb
// balance to fund whatever. Only move from polymarket and hyperliquid and
// between them when there really isn't any balance left ... because those
// swaps are slower"): the venue's own cash, then Dollars, then Bitcoin,
// and the other venue's cash only for what those cannot cover, and only
// that remainder. The same decision for the bet slip, the Investing order
// slip and add margin (decideOrderSources).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/balance_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/services/one_balance/bitcoin_funded_order.dart';
import 'package:kute/services/one_balance/order_funding.dart';
import 'package:money2/money2.dart';

/// No BTC rate loaded in the app's cache: the fresh read gives it.
class _Currency extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _Currency() : super(CurrencyState({'USD': Fixed.fromInt(100)}));
  @override
  Future<void> updateRates() async {}
}

ProviderContainer _container() {
  final container = ProviderContainer(overrides: [
    settingsProvider.overrideWith((ref) => SettingsModel(Settings(
          currency: 'USD',
          language: 'en',
          btcFormat: 'sats',
          backup: false,
          biometricsEnabled: false,
          bitcoinElectrumNode: '',
          nodeType: '',
          reviewDone: true,
          activeWalletId: 'spending',
          wallets: [WalletConfig(id: 'spending', name: 'Spending')],
        ))),
    currencyProvider.overrideWith((ref) => _Currency()),
    sparkWalletInfoFeedProvider.overrideWithValue(const Stream.empty()),
  ]);
  addTearDown(container.dispose);
  return container;
}

const _usdPerBtc = 60000.0;

/// Sats worth [usd] at [_usdPerBtc].
int _satsFor(double usd) => (usd / _usdPerBtc * 1e8).round();

void main() {
  group('planOrderSources (pure)', () {
    test(
        '\$5 Dollars + \$30 Bitcoin + \$5 Predictions, a \$10 Investing '
        'order: Dollars \$5 + Bitcoin \$5, no Predictions leg', () {
      final s = planOrderSources(
          fundUsd: 10, dollarsUsd: 5, bitcoinMaxUsd: 30, otherVenueUsd: 5);
      expect(s.dollarsUsd, 5);
      expect(s.bitcoinUsd, 5);
      expect(s.otherVenueUsd, 0);
      expect(s.otherVenueUsed, isFalse);
      expect(s.covers, isTrue);
    });

    test(
        '\$0 Dollars + \$2 Bitcoin + \$20 Predictions, a \$10 Investing '
        'order: Bitcoin \$2 + Predictions \$8 (the slow leg only for the '
        'rest)', () {
      final s = planOrderSources(
          fundUsd: 10, dollarsUsd: 0, bitcoinMaxUsd: 2, otherVenueUsd: 20);
      expect(s.dollarsUsd, 0);
      expect(s.bitcoinUsd, 2);
      expect(s.otherVenueUsd, 8);
      expect(s.covers, isTrue);
    });

    test(
        'a rest under the Bitcoin minimum folds into Bitcoin, never a slow '
        'venue leg', () {
      // Dollars \$5 of a \$5.40 move: \$0.40 is under the \$1 route
      // minimum; Bitcoin lands \$1 rather than Predictions sending \$0.40.
      final s = planOrderSources(
          fundUsd: 5.40, dollarsUsd: 5, bitcoinMaxUsd: 30, otherVenueUsd: 20);
      expect(s.bitcoinUsd, 1);
      expect(s.otherVenueUsd, 0);
      expect(s.covers, isTrue);
    });

    test(
        'Bitcoin under its own minimum is not taken: the other venue gives '
        'what Dollars lack', () {
      final s = planOrderSources(
          fundUsd: 10, dollarsUsd: 5, bitcoinMaxUsd: 0.6, otherVenueUsd: 20);
      expect(s.bitcoinUsd, 0);
      expect(s.otherVenueUsd, 5);
      expect(s.covers, isTrue);
    });

    test('everything together short: not covered', () {
      final s = planOrderSources(
          fundUsd: 30, dollarsUsd: 5, bitcoinMaxUsd: 2, otherVenueUsd: 5);
      expect(s.bitcoinUsd, 2);
      expect(s.otherVenueUsd, 23);
      expect(s.covers, isFalse);
    });

    test('Dollars cover it: nothing else', () {
      final s = planOrderSources(
          fundUsd: 4, dollarsUsd: 5, bitcoinMaxUsd: 30, otherVenueUsd: 5);
      expect(s.dollarsUsd, 4);
      expect(s.bitcoinUsd, 0);
      expect(s.otherVenueUsd, 0);
    });
  });

  group('decideOrderSources (the slips\' one decision)', () {
    late int estimates;

    setUp(() {
      estimates = 0;
      // The route keeps 0.5%.
      debugBitcoinLegEstimate = (sats) async {
        estimates++;
        return sats / 1e8 * _usdPerBtc * 0.995;
      };
    });

    tearDown(() {
      debugFreshSpendingBitcoin = null;
      debugBitcoinLegEstimate = null;
    });

    void wallet(double usd, {double usdPerBtc = _usdPerBtc}) {
      final sats = _satsFor(usd);
      debugFreshSpendingBitcoin =
          () async => (sats: sats, usdPerBtc: usdPerBtc);
    }

    test(
        'an Investing order, \$5 Dollars + \$30 Bitcoin + \$5 Predictions: '
        'Bitcoin brings the other \$5, Predictions untouched', () async {
      wallet(30);
      final s = await decideOrderSources(_container().read,
          fundUsd: 10, dollarsUsd: 5, otherVenueUsd: 5);
      expect(s.route, OrderSourceRoute.bitcoin);
      expect(s.bitcoinUsd, 5);
      expect(s.otherVenueUsd, 0);
      expect(s.otherVenueUsed, isFalse);
      expect(s.plan!.targetUsd, 5);
    });

    test(
        'the bet slip: a \$10 bet, \$5 Dollars + \$30 Bitcoin + \$6 Investing: '
        'Bitcoin \$5, no Investing leg (the same rule)', () async {
      wallet(30);
      final s = await decideOrderSources(_container().read,
          fundUsd: 10,
          dollarsUsd: 5,
          otherVenueUsd: 6,
          // The bet slip's own word: Dollars + Investing cover it.
          investmentsCover: true);
      expect(s.route, OrderSourceRoute.bitcoin);
      expect(s.bitcoinUsd, 5);
      expect(s.otherVenueUsed, isFalse);
    });

    test(
        '\$0 Dollars + \$2 Bitcoin + \$20 Predictions, a \$10 order: all the '
        'Bitcoin lands, Predictions only the rest', () async {
      wallet(2);
      final s = await decideOrderSources(_container().read,
          fundUsd: 10, dollarsUsd: 0, otherVenueUsd: 20);
      expect(s.route, OrderSourceRoute.bitcoin);
      // \$2 of bitcoin at the route's 0.5%, less the arrival buffer.
      expect(s.bitcoinUsd, 1.98);
      expect(s.otherVenueUsd, 8.02);
      expect(s.bitcoinUsd + s.otherVenueUsd, 10);
      expect(s.plan!.sats, lessThanOrEqualTo(_satsFor(2)));
    });

    test('a rest under the minimum is Bitcoin\'s \$1, no venue leg', () async {
      wallet(30);
      final s = await decideOrderSources(_container().read,
          fundUsd: 5.40, dollarsUsd: 5, otherVenueUsd: 20);
      expect(s.route, OrderSourceRoute.bitcoin);
      expect(s.bitcoinUsd, 1);
      expect(s.otherVenueUsd, 0);
    });

    test('no bitcoin: Dollars and the other venue', () async {
      wallet(0);
      final s = await decideOrderSources(_container().read,
          fundUsd: 10, dollarsUsd: 5, otherVenueUsd: 20);
      expect(s.route, OrderSourceRoute.otherVenue);
      expect(s.otherVenueUsd, 5);
    });

    test('a fresh zero Bitcoin read overrides a stale funded cache', () async {
      wallet(0);
      final c = _container();
      c
          .read(walletBalanceCacheProvider.notifier)
          .updateSparkBitcoinbalance('spending', _satsFor(30));
      // Supply the cached price too: the old path accepted the stale
      // balance without ever consulting the now-zero SDK reading.
      final priced = ProviderContainer(parent: c, overrides: [
        selectedCurrencyProvider('USD')
            .overrideWithValue(Money.fromInt(6000000, isoCode: 'USD')),
      ]);
      addTearDown(priced.dispose);
      expect(cachedSpendingBitcoin(priced.read).sats, _satsFor(30));
      final sources = await decideOrderSources(priced.read,
          fundUsd: 10, dollarsUsd: 0, otherVenueUsd: 20);
      expect(sources.route, OrderSourceRoute.otherVenue);
      expect(sources.bitcoinUsd, 0);
      expect(sources.otherVenueUsd, 10);
    });

    test('nothing covers it: the Receive sheet, for what Investments lack',
        () async {
      wallet(1.5);
      final s = await decideOrderSources(_container().read,
          fundUsd: 30, dollarsUsd: 5, otherVenueUsd: 5);
      expect(s.route, OrderSourceRoute.insufficient);
      expect(s.missingUsd, 20);
    });

    test(
        'no bitcoin price: the other venue when it covers, else nothing '
        'moves', () async {
      wallet(30, usdPerBtc: 0);
      final covered = await decideOrderSources(_container().read,
          fundUsd: 10, dollarsUsd: 5, otherVenueUsd: 20);
      expect(covered.route, OrderSourceRoute.otherVenue);
      final short = await decideOrderSources(_container().read,
          fundUsd: 10, dollarsUsd: 5, otherVenueUsd: 1);
      expect(short.route, OrderSourceRoute.unavailable);
    });

    test('an "Add" tap whose X no longer covers it moves nothing', () async {
      wallet(30);
      final s = await decideOrderSources(_container().read,
          fundUsd: 12, dollarsUsd: 5, otherVenueUsd: 5, shownAddUsd: 1);
      expect(s.route, OrderSourceRoute.addChanged);
      expect(s.missingUsd, 2);
      expect(estimates, 0);
    });
  });
}
