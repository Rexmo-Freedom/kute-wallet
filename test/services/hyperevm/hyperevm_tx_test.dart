import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/services/hyperevm/hyperevm_bridge.dart';
import 'package:kute/services/hyperevm/hyperevm_constants.dart';
import 'package:kute/services/hyperevm/hyperevm_tx.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';
import 'package:kute/services/hyperliquid/hyperliquid_signing.dart';
import 'package:pointycastle/digests/keccak.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show EthPrivateKey;
import 'package:web3dart/web3dart.dart' as w3;

final _key = EthPrivateKey.fromHex(
    '0123456789012345678901234567890101234567890123456789012345678901');
const _deposit = '0x3333333333333333333333333333333333333333';

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

Uint8List _bytes(String hex) {
  final h = hex.startsWith('0x') ? hex.substring(2) : hex;
  return Uint8List.fromList([
    for (var i = 0; i < h.length; i += 2) int.parse(h.substring(i, i + 2), radix: 16)
  ]);
}

String _recover(Uint8List digest, BigInt r, BigInt s, int v) =>
    '0x${_hex(w3.publicKeyToAddress(w3.ecRecover(digest, w3.MsgSignature(r, s, v))))}';

/// Minimal RLP decoder for the test: byte strings and lists.
(Object, int) _rlp(Uint8List data, int at) {
  final b = data[at];
  if (b < 0x80) return (Uint8List.fromList([b]), at + 1);
  if (b < 0xb8) {
    final len = b - 0x80;
    return (Uint8List.sublistView(data, at + 1, at + 1 + len), at + 1 + len);
  }
  if (b < 0xc0) {
    final ll = b - 0xb7;
    var len = 0;
    for (var i = 0; i < ll; i++) {
      len = (len << 8) | data[at + 1 + i];
    }
    final start = at + 1 + ll;
    return (Uint8List.sublistView(data, start, start + len), start + len);
  }
  int len;
  int start;
  if (b < 0xf8) {
    len = b - 0xc0;
    start = at + 1;
  } else {
    final ll = b - 0xf7;
    len = 0;
    for (var i = 0; i < ll; i++) {
      len = (len << 8) | data[at + 1 + i];
    }
    start = at + 1 + ll;
  }
  final items = <Object>[];
  var p = start;
  while (p < start + len) {
    final (item, next) = _rlp(data, p);
    items.add(item);
    p = next;
  }
  return (items, start + len);
}

BigInt _int(Object o) {
  final b = o as Uint8List;
  return b.isEmpty ? BigInt.zero : BigInt.parse(_hex(b), radix: 16);
}

void main() {
  test('the locally computed USDC domain equals the on-chain separator', () {
    expect('0x${_hex(hyperEvmUsdcDomainSeparator())}',
        HyperEvmChain.usdcDomainSeparator);
  });

  test('USDC transfers never go to the CoreDepositWallet or a system address',
      () {
    for (final bad in [
      HyperEvmChain.coreDepositWallet,
      HyperEvmChain.coreDepositWallet.toLowerCase(),
      HyperEvmChain.usdcSystemAddress,
      HyperEvmChain.hypeSystemAddress,
    ]) {
      expect(() => usdcTransferData(to: bad, amountMicros: BigInt.one),
          throwsA(isA<HyperEvmTxRefused>()));
    }
    expect(() => usdcTransferData(to: _deposit, amountMicros: BigInt.zero),
        throwsA(isA<HyperEvmTxRefused>()));
    final data = usdcTransferData(to: _deposit, amountMicros: BigInt.from(5));
    expect(data.substring(0, 10), '0xa9059cbb');
    expect(data.length, 10 + 128);
    expect(data.substring(10 + 24, 10 + 64), _deposit.substring(2));
    expect(BigInt.parse(data.substring(74), radix: 16), BigInt.from(5));
  });

  test('depositWithAuth carries an authorization the account itself signed',
      () async {
    final nonce = Uint8List.fromList(List.generate(32, (i) => i));
    final data = await depositWithAuthData(
      key: _key,
      amountMicros: BigInt.from(12345678),
      validAfter: BigInt.zero,
      validBefore: BigInt.from(1800000000),
      nonce: nonce,
      destinationDex: HyperEvmChain.spotDex,
    );
    expect(data.substring(0, 10), '0xea031649');
    final words = [
      for (var i = 10; i < data.length; i += 64) data.substring(i, i + 64)
    ];
    expect(words.length, 8);
    expect(BigInt.parse(words[0], radix: 16), BigInt.from(12345678));
    expect(BigInt.parse(words[1], radix: 16), BigInt.zero);
    expect(BigInt.parse(words[2], radix: 16), BigInt.from(1800000000));
    expect(words[3], _hex(nonce));
    expect(BigInt.parse(words[7], radix: 16), BigInt.from(0xFFFFFFFF));
    final digest = receiveWithAuthorizationDigest(
      from: _key.address.hexEip55,
      to: HyperEvmChain.coreDepositWallet,
      value: BigInt.from(12345678),
      validAfter: BigInt.zero,
      validBefore: BigInt.from(1800000000),
      nonce: nonce,
    );
    expect(
        _recover(digest, BigInt.parse(words[5], radix: 16),
            BigInt.parse(words[6], radix: 16), int.parse(words[4], radix: 16)),
        _key.address.hexEip55.toLowerCase());
    await expectLater(
        depositWithAuthData(
            key: _key,
            amountMicros: BigInt.one,
            validAfter: BigInt.zero,
            validBefore: BigInt.one,
            nonce: nonce,
            destinationDex: 7),
        throwsA(isA<HyperEvmTxRefused>()));
  });

  test('a signed transaction is type 2 on chain 999 from the account', () async {
    final data = usdcTransferData(to: _deposit, amountMicros: BigInt.from(9));
    final signed = await signHyperEvmTx(
      key: _key,
      to: HyperEvmChain.usdc,
      data: data,
      nonce: 7,
      gasLimit: BigInt.from(78000),
      maxFeePerGasWei: BigInt.from(300000000),
    );
    final raw = _bytes(signed.raw);
    expect(raw[0], 0x02);
    final (decoded, end) = _rlp(raw, 1);
    expect(end, raw.length);
    final f = decoded as List<Object>;
    expect(f.length, 12);
    expect(_int(f[0]), BigInt.from(999));
    expect(_int(f[1]), BigInt.from(7));
    expect(_int(f[2]), BigInt.zero);
    expect(_int(f[3]), BigInt.from(300000000));
    expect(_int(f[4]), BigInt.from(78000));
    expect('0x${_hex(f[5] as Uint8List)}', HyperEvmChain.usdc.toLowerCase());
    expect(_int(f[6]), BigInt.zero);
    expect('0x${_hex(f[7] as Uint8List)}', data);
    // The digest over the fields asserted above, built independently.
    final unsigned = Uint8List.fromList([
      0x02,
      ...w3.encode(<Object>[
        BigInt.from(999),
        BigInt.from(7),
        BigInt.zero,
        BigInt.from(300000000),
        BigInt.from(78000),
        _bytes(HyperEvmChain.usdc),
        BigInt.zero,
        _bytes(data),
        <Object>[],
      ])
    ]);
    final digest = KeccakDigest(256).process(unsigned);
    expect(
        _recover(digest, _int(f[10]), _int(f[11]), _int(f[9]).toInt() + 27),
        _key.address.hexEip55.toLowerCase());
    expect(signed.hash,
        '0x${_hex(KeccakDigest(256).process(raw))}');
    expect(signed.nonce, 7);
  });

  test('the CoreDepositWallet only ever receives deposit calls', () async {
    await expectLater(
        signHyperEvmTx(
          key: _key,
          to: HyperEvmChain.coreDepositWallet,
          data: '0xa9059cbb',
          nonce: 0,
          gasLimit: BigInt.from(21000),
          maxFeePerGasWei: BigInt.one,
        ),
        throwsA(isA<HyperEvmTxRefused>()));
  });

  test('HyperCore amounts are floored to the side that receives them', () {
    expect(hyperCoreAmountWire(BigInt.from(1234567891), decimals: 6),
        '12.345678');
    expect(hyperCoreAmountWire(BigInt.from(1234567891), decimals: 8),
        '12.34567891');
    expect(hyperCoreAmountWire(BigInt.from(100), decimals: 6), '0.000001');
    expect(() => hyperCoreAmountWire(BigInt.from(99), decimals: 6),
        throwsArgumentError);
  });

  test('fees: twice the price with a floor, 30% gas headroom', () {
    expect(hyperEvmMaxFeePerGas(BigInt.from(150000000)),
        BigInt.from(300000000));
    expect(hyperEvmMaxFeePerGas(BigInt.from(10)), BigInt.from(100000000));
    expect(hyperEvmGasLimit(BigInt.from(100000)), BigInt.from(130000));
  });

  group('sendAsset to HyperEVM', () {
    test('signs the SDK field list, to the system address, nonce first',
        () async {
      var persisted = false;
      var posts = 0;
      final client = MockClient((request) async {
        posts++;
        expect(persisted, isTrue);
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final action = body['action'] as Map<String, dynamic>;
        expect(action['type'], 'sendAsset');
        expect(action['destination'], HyperEvmChain.usdcSystemAddress);
        expect(action['sourceDex'], '');
        expect(action['destinationDex'], 'spot');
        expect(action['token'], HyperCoreTokens.usdc);
        expect(action['amount'], '12.5');
        expect(action['fromSubAccount'], '');
        expect(action['nonce'], body['nonce']);
        expect(action['hyperliquidChain'], 'Mainnet');
        final digest = userSignedActionDigest(
          primaryType: 'HyperliquidTransaction:SendAsset',
          fields: const [
            (name: 'hyperliquidChain', type: 'string'),
            (name: 'destination', type: 'string'),
            (name: 'sourceDex', type: 'string'),
            (name: 'destinationDex', type: 'string'),
            (name: 'token', type: 'string'),
            (name: 'amount', type: 'string'),
            (name: 'fromSubAccount', type: 'string'),
            (name: 'nonce', type: 'uint64'),
          ],
          message: action,
        );
        final sig = body['signature'] as Map<String, dynamic>;
        expect(
            _recover(
                digest,
                BigInt.parse((sig['r'] as String).substring(2), radix: 16),
                BigInt.parse((sig['s'] as String).substring(2), radix: 16),
                sig['v'] as int),
            _key.address.hexEip55.toLowerCase());
        return http.Response('{"status":"ok","response":{"type":"default"}}', 200);
      });
      addTearDown(client.close);
      final exchange = HyperliquidExchangeService(
          credentials: _key,
          walletAddress: _key.address.hexEip55,
          httpClient: client,
          allowNonceRetry: false,
          onBeforePost: (_) async => persisted = true);
      final nonce = await exchange.sendAssetToEvm(
          token: HyperCoreTokens.usdc, amount: '12.5', sourceDex: '');
      expect(nonce, greaterThan(0));
      expect(posts, 1);
    });

    test('refuses other tokens, HYPE from perpetuals and sub-micro USDC',
        () async {
      final exchange = HyperliquidExchangeService(
          credentials: _key,
          walletAddress: _key.address.hexEip55,
          httpClient: MockClient((_) async => throw StateError('no POST')));
      for (final call in [
        () => exchange.sendAssetToEvm(
            token: 'PURR:0x1', amount: '1', sourceDex: 'spot'),
        () => exchange.sendAssetToEvm(
            token: HyperCoreTokens.hype, amount: '1', sourceDex: ''),
        () => exchange.sendAssetToEvm(
            token: HyperCoreTokens.usdc, amount: '1.0000001', sourceDex: ''),
        () => exchange.sendAssetToEvm(
            token: HyperCoreTokens.usdc, amount: '1', sourceDex: 'xyz'),
      ]) {
        await expectLater(call(), throwsArgumentError);
      }
    });

    test('a rejection (an account mode that disables it) is never retried',
        () async {
      var posts = 0;
      final exchange = HyperliquidExchangeService(
          credentials: _key,
          walletAddress: _key.address.hexEip55,
          allowNonceRetry: false,
          httpClient: MockClient((_) async {
            posts++;
            return http.Response(
                jsonEncode({
                  'status': 'err',
                  'response': 'Action disabled when unified account is active'
                }),
                200);
          }));
      await expectLater(
          exchange.sendAssetToEvm(
              token: HyperCoreTokens.usdc, amount: '1', sourceDex: 'spot'),
          throwsA(isA<HyperliquidRejectedException>()));
      expect(posts, 1);
    });
  });

  test('account mode: unified and portfolio margin share one balance', () {
    expect(HyperCoreAccountMode.fromAbstraction('unifiedAccount'),
        HyperCoreAccountMode.unified);
    expect(HyperCoreAccountMode.fromAbstraction('portfolioMargin'),
        HyperCoreAccountMode.unified);
    for (final other in ['default', 'disabled', 'dexAbstraction', null, 3]) {
      expect(HyperCoreAccountMode.fromAbstraction(other),
          HyperCoreAccountMode.standard);
    }
  });
}
