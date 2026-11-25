// Founder report, 11 November 2026 (build 107): "why are we going through
// Bitcoin → Dollars and then to Invest every time now?". The backend's
// fees went live that day: Bitcoin → Dollars (usdb_swap_deposit) 1%,
// Bitcoin → Investing (venue_deposit) 1%, Bitcoin → Predictions 1%, own
// Dollars → own Investing/Predictions (investments_internal) 0.
//
// The backend's `/estimate` (internal/proxy/orchestra.go GetEstimate)
// strips the app fee from what it asks the provider and says so:
// `X-Kute-Estimate-Includes-App-Fee: false` and `X-Kute-App-Fee-Bps` set
// to the route's live rate. The direct estimate took that 1% out, the
// via-Dollars leg's estimate did not, so the chain read ~1% cheaper than
// it is and every Bitcoin-funded order went `costlier` → via Dollars.
//
// These tests run the real sizing and estimate reads against a fake
// backend that answers exactly as GetEstimate does, and check that both
// routes are priced on the same, complete basis.

import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/helpers/orchestra_router.dart';
import 'package:kute/models/affiliate_model.dart';
import 'package:kute/models/orchestra_model.dart';
import 'package:kute/models/currency_conversions.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/currency_conversions_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart'
    show hyperliquidAddressProvider;
import 'package:kute/services/api/orchestra_api.dart';
import 'package:kute/services/one_balance/bitcoin_funded_order.dart';
import 'package:kute/services/one_balance/bitcoin_to_dollars_leg.dart';
import 'package:kute/services/one_balance/bitcoin_to_venue_leg.dart';
import 'package:kute/services/one_balance/hyperliquid_move_rail.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/services/one_balance/predictions_venue_funder.dart';

import 'package:money2/money2.dart';

import '../../helpers/fake_network.dart';

class _CurrencyNotifier extends StateNotifier<CurrencyState>
    implements CurrencyNotifier {
  // $100,000 per bitcoin.
  _CurrencyNotifier()
      : super(CurrencyState({
          'USD': Fixed.fromInt(100),
          'BTC': Fixed.parse('0.00001', decimalDigits: 8),
        }));
  @override
  Future<void> updateRates() async {}
}

ProviderContainer _container() => ProviderContainer(overrides: [
      hyperliquidAddressProvider.overrideWith((ref) async => _hlAccount),
      settingsProvider.overrideWith((ref) => SettingsModel(Settings(
            currency: 'USD',
            language: 'en',
            btcFormat: 'sats',
            backup: false,
            balancePrivacy: 0,
            biometricsEnabled: false,
            bitcoinElectrumNode: 'localhost',
            nodeType: 'Blockstream',
            reviewDone: false,
          ))),
      currencyProvider.overrideWith((ref) => _CurrencyNotifier()),
    ]);

const _usdPerBtc = 100000.0;
const _hlAccount = '0x00000000000000000000000000000000000000a1';
const _pmWallet = '0x00000000000000000000000000000000000000b2';

/// The live fee rows (backend policy, 11 November 2026), in bps.
const _bitcoinToDollarsBps = 100; // usdb_swap_deposit
const _bitcoinToVenueBps = 100; // venue_deposit / predictions_deposit
const _insideBps = 0; // investments_internal
const _dollarsOutBps = 100; // usdb send to someone else's address

/// The provider's own pricing per route (no Kute fee in it): a share it
/// keeps and a flat cost in dollars.
({double share, double flatUsd}) _providerCost(String from, String to) =>
    switch ((from, to)) {
      ('spark:BTC', 'spark:USDB') => (share: 0.004, flatUsd: 0.0),
      ('spark:BTC', 'hypercore:USDC') => (share: 0.004, flatUsd: 0.01),
      ('spark:BTC', 'polygon:USDC.e') => (share: 0.004, flatUsd: 0.01),
      ('spark:USDB', 'hypercore:USDC') => (share: 0.001, flatUsd: 0.01),
      ('spark:USDB', 'polygon:USDC.e') => (share: 0.002, flatUsd: 0.01),
      _ => throw StateError('no route $from → $to'),
    };

/// GET /api/v1/orchestra/estimate as the backend answers it: the
/// provider's output WITHOUT the app fee, the live rate in the headers.
http.Response _estimate(http.Request request, List<String> seen) {
  final q = request.url.queryParameters;
  final from = '${q['sourceChain']}:${q['sourceAsset']}';
  final to = '${q['destinationChain']}:${q['destinationAsset']}';
  final recipient = q['recipientAddress'];
  seen.add('$from→$to${recipient == null ? '' : ' @own'}');
  final inUsd = q['sourceAsset'] == 'BTC'
      ? int.parse(q['amount']!) / 1e8 * _usdPerBtc
      : orchestraAmountToDouble(q['amount']!, q['sourceAsset']!,
          chain: q['sourceChain']);
  final cost = _providerCost(from, to);
  final out = inUsd * (1 - cost.share) - cost.flatUsd;
  // OrchestraPurpose + the inside-Investments check on recipientAddress.
  final bps = q['sourceAsset'] == 'BTC'
      ? (q['destinationAsset'] == 'USDB'
          ? _bitcoinToDollarsBps
          : _bitcoinToVenueBps)
      : (recipient == _hlAccount || recipient == _pmWallet)
          ? _insideBps
          : _dollarsOutBps;
  return http.Response(
    jsonEncode({
      'estimatedOut': doubleToOrchestraAmount(out, q['destinationAsset']!,
          chain: q['destinationChain']),
      'feeBps': 0,
      'feeAmount': '0',
      'route': [from, to],
    }),
    200,
    headers: {
      'content-type': 'application/json',
      'x-kute-fee-policy-revision': '7',
      'x-kute-estimate-includes-app-fee': 'false',
      'x-kute-app-fee-mode': 'fixed',
      'x-kute-app-fee-bps': '$bps',
      'x-kute-referral-discount-bps': '0',
    },
  );
}

void main() {
  setUpAll(() {
    dotenv.loadFromString(envString: 'BACKEND=https://backend.test');
  });
  setUp(() {
    AffiliateService.debugSessionToken = 'test-session';
    debugFreshSpendingBitcoin =
        () async => (sats: 1000000, usdPerBtc: _usdPerBtc);
  });
  tearDown(() {
    AffiliateService.debugSessionToken = null;
    debugFreshSpendingBitcoin = null;
  });

  /// The planner as `BitcoinLegEnv.live` runs it for an order of
  /// [fundUsd] from Bitcoin alone (no Dollars, no other venue cash),
  /// every read on the fake backend.
  Future<(DirectBitcoinPlan, BitcoinLegPlan, List<String>)> decide(
      OneBalanceVenue venue, double fundUsd) async {
    final seen = <String>[];
    final c = _container();
    addTearDown(c.dispose);
    return withFakeNetwork(() async {
      final sizing = await sizeBitcoinLegFor(c.read, dollarsShortUsd: fundUsd);
      final via = sizing.plan!;
      final rail = HyperCoreMoveRail(c.read, limits: (_) async => null);
      final ownVenue =
          venue == OneBalanceVenue.investing ? _hlAccount : _pmWallet;
      final plan = await planDirectBitcoinLeg(
        fundUsd: fundUsd,
        addUsd: via.targetUsd,
        dollarsUsd: 0,
        via: via,
        availableSats: 1000000,
        directMaxSats: directMaxSatsFor(via),
        venueArriving: (usd) async {
          if (venue == OneBalanceVenue.investing) {
            return (await rail.estimate(usd: usd, deposit: true)).arrivingUsd;
          }
          // Dollars → Predictions as PredictionsVenueFunder reads it.
          final est = (await OrchestraService.getEstimate(
            sourceChain: 'spark',
            sourceAsset: 'USDB',
            destinationChain: 'polygon',
            destinationAsset: 'USDC.e',
            amount: doubleToOrchestraAmount(usd, 'USDB', chain: 'spark'),
            recipientAddress: _pmWallet,
          ))
              .data!;
          final share = PredictionsVenueFunder.routeShareFrom(est,
              sentUsd: usd,
              arrivingUsd: orchestraAmountToDouble(est.estimatedOut, 'USDC.e',
                  chain: 'polygon'))!;
          return usd * (1 - share);
        },
        directOutUsd: (sats) =>
            directBitcoinEstimate(venue, sats, ownVenue: ownVenue),
        directMinimumUsd: () async => 1,
        dollarsMinimumUsd: 1,
      );
      return (plan, via, seen);
    }, () => MockClient((r) async => _estimate(r, seen)));
  }

  for (final venue in OneBalanceVenue.values) {
    for (final usd in [10.0, 25.0, 50.0]) {
      test(
          '${venue.name} \$$usd from Bitcoin alone: equal Kute fees on both '
          'routes, the direct leg wins', () async {
        final (plan, via, seen) = await decide(venue, usd);
        expect(plan.direct, isTrue,
            reason: 'got ${plan.reason}: direct ${plan.directCostUsd} '
                'vs via ${plan.viaCostUsd}');
        expect(plan.decision, DirectBitcoinDecision.notCostlier);
        // The via chain costs its 1% Bitcoin → Dollars fee too: its sats
        // land the target only after Kute's fee comes out.
        final viaLands = via.sats / 1e8 * _usdPerBtc * (1 - 0.004) * 0.99;
        expect(viaLands, greaterThanOrEqualTo(via.targetUsd - 1e-6));
        // Both priced: the direct leg is no dearer, and the chain's second
        // hop (its provider cost) is what the direct leg saves.
        expect(plan.costDiffUsd!, lessThanOrEqualTo(0));
        // The approval's direct cap holds the direct leg with its 1%.
        expect(plan.sats, lessThanOrEqualTo(directMaxSatsFor(via)));
        expect(seen, contains('spark:BTC→spark:USDB'));
      });
    }
  }

  test(
      'a direct route genuinely dearer than the chain beyond the tolerance '
      'still goes via Dollars', () async {
    // The same reads, but the direct route's provider keeps 2% more.
    final seen = <String>[];
    final c = _container();
    addTearDown(c.dispose);
    final plan = await withFakeNetwork(() async {
      final via = (await sizeBitcoinLegFor(c.read, dollarsShortUsd: 25)).plan!;
      final rail = HyperCoreMoveRail(c.read, limits: (_) async => null);
      return planDirectBitcoinLeg(
        fundUsd: 25,
        addUsd: via.targetUsd,
        dollarsUsd: 0,
        via: via,
        availableSats: 1000000,
        directMaxSats: directMaxSatsFor(via),
        venueArriving: (usd) async =>
            (await rail.estimate(usd: usd, deposit: true)).arrivingUsd,
        directOutUsd: (sats) async =>
            (await directBitcoinEstimate(OneBalanceVenue.investing, sats,
                ownVenue: _hlAccount))! *
            0.98,
        directMinimumUsd: () async => 1,
        dollarsMinimumUsd: 1,
      );
    }, () => MockClient((r) async => _estimate(r, seen)));
    expect(plan.direct, isFalse);
    expect(plan.reason, DirectBitcoinReason.costlier);
  });

  test('the Bitcoin → Dollars estimate is read net of the Kute fee it reports',
      () async {
    final seen = <String>[];
    final c = _container();
    addTearDown(c.dispose);
    final spread = await withFakeNetwork(
        () => bitcoinLegSpreadEstimate(
            (sats: 1000000, usdPerBtc: _usdPerBtc), 25),
        () => MockClient((r) async => _estimate(r, seen)));
    // The provider's 0.4% and Kute's 1% on what is left.
    expect(spread, closeTo(1 - (1 - 0.004) * 0.99, 1e-6));
  });

  test(
      'the Dollars → Investing hop is read net of the Kute fee it reports '
      '(none between own accounts, 1% to anyone else)', () async {
    final c = _container();
    addTearDown(c.dispose);
    Future<double> arriving(int bps) => HyperCoreMoveRail(c.read,
        limits: (_) async => null,
        estimate: (route, amount, recipient) async => OrchestraEstimate(
              estimatedOut:
                  doubleToOrchestraAmount(24.96, 'USDC', chain: 'hypercore'),
              feeAmount: '0',
              feeBps: 0,
              route: const [],
              kuteAppFeeBps: bps,
              estimateIncludesAppFee: false,
            )).estimate(usd: 25, deposit: true).then((q) => q.arrivingUsd);
    expect(await arriving(_insideBps), closeTo(24.96, 1e-6));
    expect(await arriving(_dollarsOutBps), closeTo(24.96 * 0.99, 1e-6));
  });
}
