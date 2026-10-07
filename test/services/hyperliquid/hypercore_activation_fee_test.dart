import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/helpers/auth_grant.dart';
import 'package:kute/helpers/venue_intents.dart';
import 'package:kute/models/settlement_operation.dart';
import 'package:kute/services/funding/settlement_runner.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/services/hyperliquid/hypercore_activation_fee.dart';
import 'package:kute/services/hyperliquid/hypercore_cash.dart';
import 'package:kute/services/hyperliquid/hypercore_transfer_proof.dart';

const _destination = '0x2222222222222222222222222222222222222222';

void main() {
  test('all-in budget re-quotes with activation included before funding',
      () async {
    final amounts = <BigInt>[];
    final budget = BigInt.from(1700000000);
    final result = await quoteHypercoreBudget<String>(
      budget: budget,
      request: (amount, attempt) async {
        amounts.add(amount);
        return HypercoreBudgetQuote(
            value: 'quote-$attempt',
            amount: amount,
            activationFee: hypercoreAccountActivationFee);
      },
    );
    expect(amounts, [budget, budget - hypercoreAccountActivationFee]);
    expect(result.value, 'quote-1');
    expect(result.amount + result.activationFee, budget);
  });

  test('active destinations use the full budget with no activation charge',
      () async {
    final budget = BigInt.from(1700000000);
    final result = await quoteHypercoreBudget<String>(
        budget: budget,
        request: (amount, attempt) async {
          expect(attempt, 0);
          return HypercoreBudgetQuote(
              value: 'active', amount: amount, activationFee: BigInt.zero);
        });
    expect(result.amount, budget);
  });

  test('replacement destinations are checked and fee oscillation stops',
      () async {
    var calls = 0;
    await expectLater(
        quoteHypercoreBudget<String>(
            budget: BigInt.from(1700000000),
            request: (amount, attempt) async {
              calls++;
              return HypercoreBudgetQuote(
                  value: '$attempt',
                  amount: amount,
                  activationFee: attempt.isEven
                      ? hypercoreAccountActivationFee
                      : BigInt.zero);
            }),
        throwsA(isA<HypercoreActivationFeeChanged>()));
    expect(calls, 3);
  });

  test(
      'a quote cannot change the transfer amount or consume the whole budget as fee',
      () async {
    final budget = hypercoreAccountActivationFee;
    await expectLater(
        quoteHypercoreBudget<String>(
            budget: budget,
            request: (amount, _) async => HypercoreBudgetQuote(
                value: 'too-small',
                amount: amount,
                activationFee: hypercoreAccountActivationFee)),
        throwsA(isA<HypercoreActivationFeeBalanceRequired>()));
    await expectLater(
        quoteHypercoreBudget<String>(
            budget: budget,
            request: (amount, _) async => HypercoreBudgetQuote(
                value: 'mismatch',
                amount: amount + BigInt.one,
                activationFee: BigInt.zero)),
        throwsStateError);
  });

  test('perpetuals withdrawal moves only available spot cash and reserves fees',
      () {
    expect(
        hypercorePerpShortfall(
            requiredBaseUnits: BigInt.from(390000000),
            perpAvailable: 2.9,
            spotAvailable: 1,
            activationFeeBaseUnits: hypercoreAccountActivationFee),
        BigInt.from(100000000));
    expect(
        () => hypercorePerpShortfall(
            requiredBaseUnits: BigInt.from(390000000),
            perpAvailable: 2.9,
            spotAvailable: 0,
            activationFeeBaseUnits: hypercoreAccountActivationFee),
        throwsA(isA<HypercoreActivationFeeBalanceRequired>()));
  });
  test('perpetuals quote drops sub-micro dust before asking provider',
      () async {
    final result = await quoteHypercoreBudget<String>(
        budget: BigInt.from(1605000001),
        request: (amount, _) async {
          expect(amount, BigInt.from(1605000000));
          return HypercoreBudgetQuote(
              value: 'quote', amount: amount, activationFee: BigInt.zero);
        });
    expect(hypercorePerpUsdcWire(result.amount), '16.050000');
  });

  test('only documented ordinary account roles establish the fee', () {
    expect(hypercoreActivationFeeForRole({'role': 'missing'}),
        BigInt.from(100000000));
    expect(hypercoreActivationFeeForRole({'role': 'user'}), BigInt.zero);
    for (final response in [
      null,
      [],
      {},
      {'role': 'agent'},
      {'role': 'vault'},
      {'role': 'subAccount'},
      {'role': 'futureRole'},
    ]) {
      expect(() => hypercoreActivationFeeForRole(response),
          throwsA(isA<HypercoreActivationFeeUnavailable>()));
    }
  });

  test('fee lookup binds the exact destination and fails closed', () async {
    final client = MockClient((request) async {
      expect(request.url.scheme, 'https');
      expect(request.url.host, 'api.hyperliquid.xyz');
      expect(
          jsonDecode(request.body), {'type': 'userRole', 'user': _destination});
      return http.Response('{"role":"missing"}', 200);
    });
    addTearDown(client.close);
    expect(await readHypercoreActivationFee(_destination, client: client),
        hypercoreAccountActivationFee);

    for (final response in [
      http.Response('{"role":"user"}', 503),
      http.Response('not JSON', 200),
      http.Response('{}', 200),
    ]) {
      final invalid = MockClient((_) async => response);
      addTearDown(invalid.close);
      await expectLater(
          readHypercoreActivationFee(_destination, client: invalid),
          throwsA(isA<HypercoreActivationFeeUnavailable>()));
    }
    final offline =
        MockClient((_) async => throw http.ClientException('offline'));
    addTearDown(offline.close);
    await expectLater(readHypercoreActivationFee(_destination, client: offline),
        throwsA(isA<HypercoreActivationFeeUnavailable>()));
  });

  test('reserve adds the fee without changing the exact quote wire amount', () {
    final amount = BigInt.from(290000000);
    final reserve = hypercoreTransferReserve(
      amountBaseUnits: amount,
      currentFeeBaseUnits: hypercoreAccountActivationFee,
      reviewedFeeBaseUnits: hypercoreAccountActivationFee,
    );
    expect(reserve, BigInt.from(390000000));
    expect(hypercoreUsdcWire(amount), '2.90000000');
    expect(
        () => hypercoreSpotShortfall(
            requiredBaseUnits: reserve, spotAvailable: 2.9, perpAvailable: 0),
        throwsStateError);
    expect(
        () => hypercoreSpotShortfall(
            requiredBaseUnits: reserve,
            spotAvailable: 2.9,
            perpAvailable: 0,
            activationFeeBaseUnits: hypercoreAccountActivationFee),
        throwsA(isA<HypercoreActivationFeeBalanceRequired>()));
    expect(
        hypercoreSpotShortfall(
            requiredBaseUnits: reserve, spotAvailable: 2.9, perpAvailable: 1),
        BigInt.from(100000000));
  });

  test('an increased fee is rejected and a reduced fee does not enlarge send',
      () {
    final amount = BigInt.from(290000000);
    expect(
        () => hypercoreTransferReserve(
            amountBaseUnits: amount,
            currentFeeBaseUnits: hypercoreAccountActivationFee,
            reviewedFeeBaseUnits: BigInt.zero),
        throwsA(isA<HypercoreActivationFeeChanged>()));
    expect(
        hypercoreTransferReserve(
            amountBaseUnits: amount,
            currentFeeBaseUnits: BigInt.zero,
            reviewedFeeBaseUnits: hypercoreAccountActivationFee),
        amount);
  });

  test('internal moves round up to six decimals and reject unusable balances',
      () {
    expect(
        hypercoreSpotShortfall(
            requiredBaseUnits: BigInt.from(101),
            spotAvailable: 0,
            perpAvailable: 0.000002),
        BigInt.from(200));
    for (final available in [double.nan, double.infinity, -1.0]) {
      expect(
          () => hypercoreSpotShortfall(
              requiredBaseUnits: BigInt.one,
              spotAvailable: available,
              perpAvailable: 1),
          throwsStateError);
    }
    expect(
        () => hypercoreSpotShortfall(
            requiredBaseUnits: BigInt.from(101),
            spotAvailable: 0,
            perpAvailable: 0.00000199),
        throwsStateError);
  });

  test('source fee is bound in approval and cannot be overridden by extras',
      () {
    SensitiveIntent intent(BigInt fee,
            {Map<String, Object?> extras = const {}}) =>
        OrchestraGrants.settlement(
          SettlementAuthorizationIntent(
            flow: SettlementFlow.investingToSparkDirect,
            walletId: 'wallet',
            destination: 'recipient|hypercore_to_spark_v1',
            routeLabel: 'hypercore:USDC → spark:BTC',
            amountIn: BigInt.from(290000000),
            minReceive: BigInt.from(1000),
            maxFeeBps: 100,
            sourceFeeBaseUnits: fee,
            sourceFeeAsset: 'USDC',
          ),
          action: SensitiveAction.venueWithdraw,
          asset: 'USDC',
          limits: extras,
        );
    final free = intent(BigInt.zero);
    final activation = intent(hypercoreAccountActivationFee);
    expect(free.digest, isNot(activation.digest));
    expect(activation.amountMax, BigInt.from(290000000));
    expect(activation.limits['sourceFeeBaseUnits'], '100000000');
    expect(
        intent(hypercoreAccountActivationFee,
                extras: {'sourceFeeBaseUnits': '0', 'sourceFeeAsset': 'BTC'})
            .digest,
        activation.digest);
  });

  group('100% withdrawal leaves nothing on HyperCore', () {
    test('a usdSend charges the sender nothing on top, activated or not',
        () async {
      expect(await hypercoreUsdSendSenderFee(_destination), BigInt.zero);
      await expectLater(hypercoreUsdSendSenderFee('not-an-address'),
          throwsA(isA<HypercoreActivationFeeUnavailable>()));
    });

    test('the whole balance is quoted once, floored only to the usdSend unit',
        () async {
      // 12.345678 perpetuals + 0.12345678 spot, as the drain reads them.
      final budget = hypercoreUsdcBaseUnits(12.345678 + 0.12345678);
      expect(budget, BigInt.from(1246913478));
      final amounts = <BigInt>[];
      final result = await quoteHypercoreBudget<String>(
          budget: budget,
          request: (amount, attempt) async {
            amounts.add(amount);
            return HypercoreBudgetQuote(
                value: 'q',
                amount: amount,
                activationFee: await hypercoreUsdSendSenderFee(_destination));
          });
      expect(amounts, [BigInt.from(1246913400)]);
      expect(result.activationFee, BigInt.zero);
      // Only spot dust below the six-decimal transfer unit can remain.
      expect(budget - result.amount, BigInt.from(78));
    });

    test('dollar figures convert without a floating-point shortfall', () {
      expect(hypercoreUsdcBaseUnits(0.29), BigInt.from(29000000));
      expect(hypercoreUsdcBaseUnits(12.345678), BigInt.from(1234567800));
      expect(hypercoreUsdcBaseUnits(1.1), BigInt.from(110000000));
      expect(hypercoreUsdcBaseUnits(0), BigInt.zero);
      expect(hypercoreUsdcBaseUnits(double.nan), BigInt.zero);
    });
  });

  group('Max out of Investing', () {
    // What the native send checks before signing, on the amount Max
    // asks for: the quote budget's six-decimal floor, then the shortfall
    // spot must cover in the default perpetuals account.
    BigInt maxPassesSendChecks(double perp, List<HlSpotBalance> spot) {
      final usd = hypercoreSendableUsdc(perp, spot);
      final budget = hypercoreUsdcBaseUnits(usd);
      final amount = (budget ~/ BigInt.from(100)) * BigInt.from(100);
      expect(amount, budget, reason: 'Max is whole micro-dollars already');
      hypercorePerpShortfall(
          requiredBaseUnits: amount,
          activationFeeBaseUnits: BigInt.zero,
          spotAvailable: hypercoreAvailableUsdc(0, spot),
          perpAvailable: perp);
      return amount;
    }

    test('a balance whose double sits under its decimal is not one unit short',
        () {
      // 19.99 is 19.98999999...; floored it read 1998999999 units and
      // the whole balance asked spot for a micro-dollar it did not have.
      expect(
          hypercorePerpShortfall(
              requiredBaseUnits: hypercoreUsdcBaseUnits(19.99),
              spotAvailable: 0,
              perpAvailable: 19.99),
          BigInt.zero);
      expect(
          hypercorePerpShortfall(
              requiredBaseUnits: hypercoreUsdcBaseUnits(23.746789),
              spotAvailable: 0.29,
              perpAvailable: 23.456789),
          BigInt.from(29000000));
      // A real shortfall still stops, as a StateError like before.
      expect(
          () => hypercorePerpShortfall(
              requiredBaseUnits: hypercoreUsdcBaseUnits(20),
              spotAvailable: 0,
              perpAvailable: 19.99),
          throwsA(isA<HypercoreBalanceShortfall>()
              .having((e) => e, 'is a StateError', isA<StateError>())));
    });

    test('sends every whole micro-dollar and never more than the balance', () {
      expect(maxPassesSendChecks(19.99, const []), BigInt.from(1999000000));
      expect(
          maxPassesSendChecks(23.456789,
              const [HlSpotBalance(coin: 'USDC', total: 0.29, hold: 0)]),
          BigInt.from(2374678900));
      // Spot dust under a micro-dollar stays; a held part is not spent.
      expect(
          maxPassesSendChecks(23.456789, const [
            HlSpotBalance(coin: 'USDC', total: 0.12345678, hold: 0.1)
          ]),
          BigInt.from(2348024500));
      expect(hypercoreSendableUsdc(0, const []), 0);
      expect(hypercoreSendableUsdc(double.nan, const []), 0);
    });

    test('every cent balance from \$1 to \$100, with and without spot', () {
      for (var cents = 100; cents <= 10000; cents++) {
        final perp = double.parse(
            '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}');
        for (final spot in [
          const <HlSpotBalance>[],
          // Spot prints eight decimals.
          [
            HlSpotBalance(
                coin: 'USDC',
                total: double.parse((perp / 7).toStringAsFixed(8)),
                hold: 0)
          ],
          [HlSpotBalance(coin: 'USDC', total: (cents % 97) / 100, hold: 0)],
        ]) {
          final max = hypercoreSendableUsdc(perp, spot);
          expect(
              hypercoreUsdcBaseUnits(max) <=
                  hypercoreBalanceBaseUnits(hypercoreAvailableUsdc(perp, spot)),
              isTrue);
          maxPassesSendChecks(perp, spot);
        }
      }
    });
  });
}
