// Both order slips' one decision for "Add $X to Investments"
// (decideSlipFunding): the spending bitcoin funds X whenever it covers it,
// read fresh when the app's own figures are not in yet (a first tap right
// after opening the app), sized on the route's real spread rather than a
// blanket margin, never more sats than the wallet holds. Only bitcoin that
// genuinely does not cover X says "insufficient" (the slip then opens the
// Investments Receive sheet); no price at all says "unavailable".
//
// Also the slips' "Available" figure: the whole spendable Investments
// (the venue's own cash plus Dollars and the other venue's reachable
// cash), and the Max search over it.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/usd_account_provider.dart'
    show usdBalanceProvider;
import 'package:kute/screens/shared/slip_shortfall.dart'
    show slipAvailableUsd, slipMaxFundableUsd;
import 'package:kute/services/one_balance/bitcoin_funded_order.dart';
import 'package:kute/services/one_balance/bitcoin_to_dollars_leg.dart';
import 'package:kute/services/one_balance/investments_spendable.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/venue_cash_source.dart'
    show kVenuePullEta;
import 'package:money2/money2.dart';

/// No BTC rate loaded yet: the rates value 1 BTC at about $1.
class _Currency extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  _Currency() : super(CurrencyState({'USD': Fixed.fromInt(100)}));
  @override
  Future<void> updateRates() async {}
}

ProviderContainer _container({double dollars = 0}) {
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
        ))),
    currencyProvider.overrideWith((ref) => _Currency()),
    usdBalanceProvider.overrideWithValue(dollars),
  ]);
  addTearDown(container.dispose);
  return container;
}

const _usdPerBtc = 60000.0;

/// Sats worth [usd] at [_usdPerBtc].
int _satsFor(double usd) => (usd / _usdPerBtc * 1e8).round();

void main() {
  late int freshReads;

  setUp(() {
    freshReads = 0;
    // The route keeps 0.5%.
    debugBitcoinLegEstimate = (sats) async => sats / 1e8 * _usdPerBtc * 0.995;
  });

  tearDown(() {
    debugFreshSpendingBitcoin = null;
    debugBitcoinLegEstimate = null;
  });

  void freshWallet(int sats, {double usdPerBtc = _usdPerBtc}) {
    debugFreshSpendingBitcoin = () async {
      freshReads++;
      return (sats: sats, usdPerBtc: usdPerBtc);
    };
  }

  group('decideSlipFunding', () {
    test(
        'a first tap with the balance and price still loading reads them '
        'fresh and funds X from bitcoin', () async {
      // The app holds no bitcoin figure and no usable price yet.
      final c = _container();
      expect(cachedSpendingBitcoin(c.read).sats, 0);
      expect(cachedSpendingBitcoin(c.read).usdPerBtc, 0);
      freshWallet(_satsFor(60));
      final decision = await decideSlipFunding(c.read, addUsd: 6.42);
      expect(freshReads, 1);
      expect(decision.route, SlipFundingRoute.bitcoin);
      expect(decision.addUsd, 6.42);
      final plan = decision.plan!;
      // Exactly X lands; nothing on top.
      expect(plan.targetUsd, 6.42);
      expect(plan.maxSats, lessThanOrEqualTo(_satsFor(60)));
    });

    test('bitcoin worth 1.01x X still funds it: no blanket margin', () async {
      final c = _container();
      // $10.10 of bitcoin for an X of $10: the old 1.04x check (and the
      // 3% fallback spread) refused this; the route's own 0.5% does not.
      final sats = _satsFor(10.10);
      freshWallet(sats);
      final decision = await decideSlipFunding(c.read, addUsd: 10);
      expect(decision.route, SlipFundingRoute.bitcoin);
      final plan = decision.plan!;
      // Sized on the route's spread plus the arrival buffer, within the
      // wallet: the grant can never let more sats leave than it holds.
      final perSat = _usdPerBtc * 0.995 / 1e8;
      expect(plan.sats,
          (10 / perSat * 1.003).ceil()); // kArrivalTargetBuffer
      expect(plan.sats, lessThanOrEqualTo(sats));
      expect(plan.maxSats, lessThanOrEqualTo(sats));
      expect(plan.maxSats, greaterThanOrEqualTo(plan.sats));
    });

    test('without the route estimate the fallback spread applies', () async {
      debugBitcoinLegEstimate = (_) async => null;
      final c = _container();
      freshWallet(_satsFor(10.10));
      // 10 / 0.97 = $10.31 of bitcoin needed: $10.10 does not cover it.
      expect((await decideSlipFunding(c.read, addUsd: 10)).route,
          SlipFundingRoute.insufficient);
      freshWallet(_satsFor(10.40));
      expect((await decideSlipFunding(c.read, addUsd: 10)).route,
          SlipFundingRoute.bitcoin);
    });

    test('bitcoin that does not cover X is insufficient, with X', () async {
      final c = _container();
      freshWallet(_satsFor(3));
      final decision = await decideSlipFunding(c.read, addUsd: 6.42);
      expect(decision.route, SlipFundingRoute.insufficient);
      expect(decision.addUsd, 6.42);
      expect(decision.plan, isNull);
    });

    test('no bitcoin at all is insufficient, whatever the price', () async {
      final c = _container();
      freshWallet(0, usdPerBtc: 0);
      final decision = await decideSlipFunding(c.read, addUsd: 2.08);
      expect(decision.route, SlipFundingRoute.insufficient);
      expect(decision.addUsd, 2.08);
    });

    test('no spending wallet to read: insufficient', () async {
      // No seam: the live read finds no spending wallet and touches no SDK.
      final c = _container();
      final decision = await decideSlipFunding(c.read, addUsd: 2.08);
      expect(decision.route, SlipFundingRoute.insufficient);
    });

    test('bitcoin but no usable price even read fresh: unavailable',
        () async {
      final c = _container();
      // The rates' "1 BTC = $1" stand-in is no price.
      freshWallet(_satsFor(60), usdPerBtc: 1);
      final decision = await decideSlipFunding(c.read, addUsd: 6.42);
      expect(decision.route, SlipFundingRoute.unavailable);
      expect(decision.plan, isNull);
    });

    test('a refusal always stands on the fresh read', () async {
      final c = _container();
      freshWallet(_satsFor(3));
      await decideSlipFunding(c.read, addUsd: 6.42);
      expect(freshReads, 1);
    });
  });

  group('the slips\' Available and Max', () {
    test('Available is the venue cash plus the rest of Investments', () {
      // The founder's case: $0.49 of Investing cash, $8.10 in Dollars and
      // the other venue: Available $8.59, not $0.49.
      expect(slipAvailableUsd(venueUsd: 0.49, otherSpendableUsd: 8.10), 8.59);
      expect(slipAvailableUsd(venueUsd: 0.49, otherSpendableUsd: 0), 0.49);
      expect(slipAvailableUsd(venueUsd: -1, otherSpendableUsd: 2.005), 2.0);
    });

    test('the other venues\' spendable leaves the slip\'s own venue out', () {
      final c = _container(dollars: 5);
      c.read(venueCashLastReadProvider.notifier).state = (
        walletId: null,
        candidates: [
          (
            venue: OneBalanceVenue.investing,
            availableUsd: 40.0,
            eta: kVenuePullEta[OneBalanceVenue.investing]!,
            minimumUsd: 1.0,
          ),
          (
            venue: OneBalanceVenue.predictions,
            availableUsd: 20.0,
            eta: kVenuePullEta[OneBalanceVenue.predictions]!,
            minimumUsd: 1.0,
          ),
        ],
      );
      final forInvesting = c.read(
          investmentsSpendableExcludingProvider(OneBalanceVenue.investing));
      expect(forInvesting.dollarsUsd, 5);
      expect(forInvesting.venueCashUsd, 20);
      final forPredictions = c.read(
          investmentsSpendableExcludingProvider(OneBalanceVenue.predictions));
      expect(forPredictions.venueCashUsd, 40);
      // Net of the pull costs, never above the gross.
      expect(forInvesting.maxUsd, lessThanOrEqualTo(25));
      expect(forInvesting.maxUsd, greaterThan(5));
    });

    test('Max is the largest amount the funding check passes', () {
      expect(slipMaxFundableUsd(upperUsd: 10, fits: (a) => a <= 7.345), 7.34);
      expect(slipMaxFundableUsd(upperUsd: 10, fits: (_) => true), 10);
      expect(slipMaxFundableUsd(upperUsd: 10, fits: (a) => a <= 0), 0);
      expect(slipMaxFundableUsd(upperUsd: 0, fits: (_) => true), 0);
    });
  });

  test('the leg probe sizes on the fallback spread', () {
    expect(BitcoinLegRules.probeSats(9.7, usdPerBtc: 100000),
        (9.7 / 100000 * 1e8 / 0.97).ceil());
    expect(BitcoinLegRules.probeSats(10, usdPerBtc: 0), 0);
  });
}
