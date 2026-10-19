// The one-time receive of another coin (onetime_receive.dart): which
// networks are offered and what each quote is refunded to, the source
// amount a USD amount is worth, the Activity row a quote writes and the
// Activity it shows in, and how long a quote's row keeps being watched.

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/helpers/orchestra_legacy_status_rules.dart';
import 'package:kute/helpers/swap_activity.dart';
import 'package:kute/models/orchestra_model.dart';
import 'package:kute/models/orchestra_route_limits.dart';
import 'package:kute/models/orchestra_routes_model.dart';
import 'package:kute/models/swap_order_model.dart';
import 'package:kute/models/transactions_model.dart';
import 'package:kute/screens/shared/transactions_builder.dart';
import 'package:kute/services/api/orchestra_api.dart';
import 'package:kute/services/orchestra/onetime_receive.dart';
import 'package:kute/services/orchestra/orchestra_quote_guard.dart';
import 'package:kute/services/security/wallet_guard_exception.dart';

const _spark =
    'spark1pgss93sy072yrmtad5cy2srwjhq8ekzuw78yhr808jn6htqfh9w8p8h9mfwlv9';
const _ownEvm = '0x52908400098527886e0f7030069857d2e4169ee7';
const _evmDeposit = '0x1111111111111111111111111111111111111111';
const _solanaDeposit = '7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU';

OrchestraReceiveOption _option(String chain, String asset,
        {int decimals = 6}) =>
    OrchestraReceiveOption(
      assetCode: asset,
      displayName: asset,
      displaySymbol: asset,
      chain: chain,
      chainDisplayName: chain,
      decimals: decimals,
      reusableAddress: false,
    );

OrchestraQuoteRequest _request(OrchestraReceiveOption option,
        {String destination = 'USDB', String? ownEvm = _ownEvm}) =>
    OneTimeReceive.request(
      option: option,
      destinationAsset: destination,
      amountBaseUnits: BigInt.from(25000000),
      recipient: _spark,
      ownSpark: _spark,
      ownEvm: ownEvm,
    );

VerifiedOrchestraQuote _verify(OrchestraQuoteRequest request,
    {String deposit = _evmDeposit, String? echoedRefund}) {
  final now = DateTime.now();
  return verifyOrchestraQuote(
    request,
    OrchestraQuote.fromJson({
      'quoteId': 'q_1',
      'depositAddress': deposit,
      'amountIn': request.amountBaseUnits.toString(),
      'estimatedOut': request.destinationAsset == 'BTC' ? '41000' : '24800000',
      'feeAmount': '0',
      'feeBps': 10,
      'route': <String>[],
      'expiresAt':
          now.add(const Duration(minutes: 2)).toUtc().toIso8601String(),
      if (echoedRefund != null) 'refundAddress': echoedRefund,
    }),
    now: now,
    bounds: OrchestraQuoteBounds.forSource(request.sourceChain,
        inputValueInOutputUnits: null),
    mainnet: true,
  );
}

List<String> _ledger(List<SwapOrder> rows, {required bool onlyUsdb}) => [
      for (final tx in assembleActivityRows(
        [
          for (final r in rows)
            SwapOrderTransaction(
              id: r.id,
              timestamp: DateTime.fromMillisecondsSinceEpoch(r.timestamp),
              details: r,
              isConfirmed: false,
            ),
        ],
        ownAddresses: const {},
        isHardwareOrWatchOnly: false,
        onlyUsdb: onlyUsdb,
        classify: classifySwapActivity,
      ))
        tx.id,
    ];

void main() {
  group('networks and refunds', () {
    test('EVM networks are offered and refunded to the own EVM address', () {
      expect(oneTimeReceiveOffered('base'), isTrue);
      expect(oneTimeReceiveOwnRefund('ethereum'), isTrue);
      final request = _request(_option('base', 'USDC'));
      expect(request.refundAddress, _ownEvm);
      expect(request.refundOptional, isFalse);
      expect(request.recipientKind, RecipientKind.ownSpark);
      expect(request.recipientAddress, _spark);
      expect(request.ownAddress, _spark);
      expect(request.destinationChain, 'spark');
      expect(request.destinationAsset, 'USDB');
      expect(
          _request(_option('base', 'USDC'), destination: 'BTC')
              .destinationAsset,
          'BTC');
    });

    test('an EVM source with no own EVM address, or a foreign one, is refused',
        () {
      expect(
          () => _request(_option('base', 'USDC'), ownEvm: null),
          throwsA(isA<WalletGuardException>().having((e) => e.reason, 'reason',
              WalletGuardReason.ownAddressUnavailable)));
      expect(
          () => _request(_option('base', 'USDC'), ownEvm: _solanaDeposit),
          throwsA(isA<WalletGuardException>().having(
              (e) => e.reason, 'reason', WalletGuardReason.refundNotOwn)));
    });

    test('Solana and Tron carry no refund address, and the guard takes it', () {
      for (final chain in ['solana', 'tron']) {
        expect(oneTimeReceiveOffered(chain), isTrue);
        expect(oneTimeReceiveRefundOptional(chain), isTrue);
        final request = _request(_option(chain, 'USDC'), ownEvm: _ownEvm);
        expect(request.refundAddress, isEmpty);
        expect(request.refundOptional, isTrue);
      }
      final verified =
          _verify(_request(_option('solana', 'USDC')), deposit: _solanaDeposit);
      expect(verified.request.refundAddress, isEmpty);
      // An echoed refund the app never asked for is a mismatch.
      expect(
          () => _verify(_request(_option('solana', 'USDC')),
              deposit: _solanaDeposit, echoedRefund: _solanaDeposit),
          throwsA(isA<WalletGuardException>()));
    });

    test('sends keep the refund requirement', () async {
      final send = OrchestraQuoteRequest(
        sourceChain: 'spark',
        sourceAsset: 'BTC',
        destinationChain: 'base',
        destinationAsset: 'USDC',
        amountBaseUnits: BigInt.from(1000),
        recipientAddress: _evmDeposit,
        refundAddress: '',
        recipientKind: RecipientKind.external,
      );
      expect(send.refundOptional, isFalse);
      final result = await OrchestraService.createQuote(
        sourceChain: 'spark',
        sourceAsset: 'BTC',
        destinationChain: 'base',
        destinationAsset: 'USDC',
        amount: '1000',
        recipientAddress: _evmDeposit,
        refundAddress: '',
      );
      expect(result.isSuccess, isFalse);
    });

    test('other networks are not offered', () {
      for (final chain in [
        'bitcoin',
        'litecoin',
        'zcash',
        'ton',
        'xrp',
        'hypercore',
        'spark',
        'lightning'
      ]) {
        expect(oneTimeReceiveOffered(chain), isFalse, reason: chain);
      }
      expect(() => _request(_option('litecoin', 'LTC')),
          throwsA(isA<WalletGuardException>()));
    });
  });

  group('source amount for a USD amount', () {
    test('dollar coins at par', () {
      expect(
          oneTimeSourceUnits(
              asset: 'USDC', decimals: 6, usdCents: 1234, usdPerBtc: 60000),
          BigInt.from(12340000));
      expect(
          oneTimeSourceUnits(
              asset: 'USDT', decimals: 18, usdCents: 100, usdPerBtc: 0),
          BigInt.parse('1000000000000000000'));
    });

    test('bitcoin coins at the local price', () {
      expect(
          oneTimeSourceUnits(
              asset: 'WBTC', decimals: 8, usdCents: 6000, usdPerBtc: 60000),
          BigInt.from(100000));
      expect(
          oneTimeSourceUnits(
              asset: 'CBBTC', decimals: 8, usdCents: 6000, usdPerBtc: 0),
          isNull);
    });

    test('anything else at the route price from its limits, else none', () {
      const limits = OrchestraRouteLimits(
        exactInMinBaseUnits: null,
        exactInMaxBaseUnits: null,
      );
      expect(
          oneTimeSourceUnits(
              asset: 'ETH',
              decimals: 18,
              usdCents: 5000,
              usdPerBtc: 60000,
              limits: limits),
          isNull);
      // $3,000 an ether: the max bound, 10 ETH, is $30,000.
      final priced = OrchestraRouteLimits(
        exactInMaxBaseUnits: BigInt.parse('10000000000000000000'),
        exactInMaxUsdCents: 3000000,
      );
      expect(
          oneTimeSourceUnits(
              asset: 'ETH',
              decimals: 18,
              usdCents: 3000,
              usdPerBtc: 60000,
              limits: priced),
          BigInt.parse('10000000000000000'));
    });

    test('the largest order is the smaller stated maximum', () {
      expect(oneTimeMaxUsdCents(null), isNull);
      expect(
          oneTimeMaxUsdCents(const OrchestraRouteLimits(
              orderMaxUsdCents: 500000, exactInMaxUsdCents: 200000)),
          200000);
    });
  });

  group('the Activity row', () {
    SwapOrder row(String chain, String asset, String destination) =>
        OneTimeReceive.row(
          option: _option(chain, asset),
          destinationAsset: destination,
          verified: _verify(
              _request(_option(chain, asset), destination: destination),
              deposit: chain == 'solana' ? _solanaDeposit : _evmDeposit),
          walletId: 'spending',
          now: DateTime.now(),
        );

    test('a receive waiting for its deposit, under the quote id', () {
      final r = row('base', 'USDC', 'USDB');
      expect(r.id, 'q_1');
      expect(r.status, 'wait');
      expect(r.coinTo, 'USDB');
      expect(r.networkTo, 'SPARK');
      expect(r.depositAmount, '25');
      expect(r.withdrawalAmount, '24.8');
      expect(r.purchaseSource, 'crypto_receive');
      expect(r.activityDirection, 'receive');
      expect(r.refundAddress, _ownEvm);
      expect(r.expiresAt, isNotNull);
      expect(r.shouldPollOrchestra, isTrue);
      expect(isOneTimeReceiveQuoteRow(r), isTrue);
      expect(isOneTimeReceiveQuoteRow(r.copyWith(id: 'ord_1')), isFalse);
    });

    test(
        'spark:BTC shows in the Bitcoin Activity, spark:USDB in the '
        'Investments Activity, at once', () {
      final bitcoin = row('base', 'USDC', 'BTC').copyWith(id: 'q_btc');
      final dollars = row('base', 'USDC', 'USDB').copyWith(id: 'q_usd');
      final dollarsFromEth = OneTimeReceive.row(
        option: _option('ethereum', 'ETH', decimals: 18),
        destinationAsset: 'USDB',
        verified: _verify(OneTimeReceive.request(
          option: _option('ethereum', 'ETH', decimals: 18),
          destinationAsset: 'USDB',
          amountBaseUnits: BigInt.from(25000000),
          recipient: _spark,
          ownSpark: _spark,
          ownEvm: _ownEvm,
        )),
        walletId: 'spending',
        now: DateTime.now(),
      ).copyWith(id: 'q_eth');
      final rows = [bitcoin, dollars, dollarsFromEth];
      expect(_ledger(rows, onlyUsdb: false), ['q_btc']);
      expect(
          _ledger(rows, onlyUsdb: true), unorderedEquals(['q_usd', 'q_eth']));
    });

    test('the row keeps being asked about for a day past its quote', () {
      final r = row('base', 'USDC', 'USDB');
      final expiry = DateTime.fromMillisecondsSinceEpoch(r.expiresAt!);
      expect(legacyQuoteClosesAt(r), expiry.add(const Duration(hours: 24)));
      final quote = r.copyWith(purchaseSource: 'other');
      expect(legacyQuoteClosesAt(quote), expiry.add(kLegacyQuoteNotFoundGrace));
      expect(
          legacyStatusReadAction(
              row: r,
              read: OrchestraStatusReadKind.notFound,
              now: expiry.add(const Duration(hours: 2))),
          LegacyStatusReadAction.keep);
      expect(
          legacyStatusReadAction(
              row: r,
              read: OrchestraStatusReadKind.notFound,
              now: expiry.add(const Duration(hours: 25))),
          LegacyStatusReadAction.markExpired);
    });
  });
}
