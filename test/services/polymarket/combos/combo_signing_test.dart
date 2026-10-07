// Polymarket Combos: the Exchange v3 requester order a deposit wallet signs.
//
// The digests below were computed independently of this code (Python,
// pycryptodome keccak) from the typed data and the
// `wrapDepositWalletSignature` algorithm published at
// docs.polymarket.com/trading/combos/requesters.md. The docs give no
// signature vector, so the signature itself is checked by recovering the
// fixture key's address from the wrapped digest.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/constants/polymarket_constants.dart';
import 'package:kute/services/hardware/evm_signing_request.dart';
import 'package:kute/services/polymarket/combos/combo_models.dart';
import 'package:kute/services/polymarket/combos/combo_order.dart';
import 'package:kute/services/polymarket_order_v2.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show EthPrivateKey, EthSignature;

const _keyHex =
    '0x0123456789012345678901234567890101234567890123456789012345678901';
const _address = '0x42187A0F42088287EbFE8c20BB7adF111e93c381';
const _wallet = '0x3434343434343434343434343434343434343434';
const _comboYes =
    '1395948005049969436883083514886051318828509168730104056302494071274545872896';

const _orderType =
    'Order(uint256 salt,address maker,address signer,uint256 tokenId,'
    'uint256 makerAmount,uint256 takerAmount,uint8 side,uint8 signatureType,'
    'uint256 timestamp,bytes32 metadata,bytes32 builder)';

// Independent vectors (see header).
const _appDomainSep =
    '466c63910185bbd55e8679264200c4e0abdcbb0c6264eb3d41d13326022e095b';
const _contentsHash =
    '7cc6a8e9b138c1e13b4f15de369acbaaff6f48e665e9e10d9cc16f8728331630';
const _wrappedDigest =
    '93f2e1fca3fd2f126cf2e54c2c8acdd1a038bdf01e344e8e5608ebaae4a4f33d';
const _orderHash =
    '524649bc6c63b7407529ad4557cf7d63005fb7a820f6965b8416a2ea4604cb70';

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

Uint8List _bytes(String hex) => Uint8List.fromList([
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);

EthSignature _sig(String hex130) => EthSignature(
      BigInt.parse(hex130.substring(0, 64), radix: 16),
      BigInt.parse(hex130.substring(64, 128), radix: 16),
      int.parse(hex130.substring(128, 130), radix: 16),
    );

ComboQuote _quote({ComboDirection direction = ComboDirection.buy}) =>
    ComboQuote(
      rfqId: 'rfq_1',
      quoteId: 'quote_1',
      direction: direction,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(1773890763000),
      comboConditionId: '0x03',
      yesPositionId: _comboYes,
      legPositionIds: const [],
      requestedE6: BigInt.from(1000000),
      blendedPriceE6: BigInt.from(500000),
      makerAmountE6: BigInt.from(966191),
      takerAmountE6: BigInt.from(1932381),
      totalRequiredE6: BigInt.from(1000000),
      netReceiveE6: BigInt.from(1932381),
    );

void main() {
  final key = EthPrivateKey.fromHex(_keyHex);
  // 2026-03-19T03:26:00Z, the docs' example window.
  final now = DateTime.fromMillisecondsSinceEpoch(1773890760123);

  test('fixture key address', () {
    expect(key.address.hexEip55, _address);
  });

  test('the requester order: v3 fields, timestamp in SECONDS, zero builder',
      () {
    final order = buildComboOrder(
      quote: _quote(),
      depositWallet: _wallet,
      salt: BigInt.parse('1122334455667788', radix: 16),
      now: now,
    );
    // Seconds, not the CLOB V2 order's milliseconds.
    expect(order.timestamp, BigInt.from(1773890760));
    expect(order.timestamp, BigInt.from(now.millisecondsSinceEpoch ~/ 1000));
    expect(order.builder, PolymarketConstants.bytes32Zero);
    expect(order.metadata, PolymarketConstants.bytes32Zero);
    expect(order.maker, _wallet);
    expect(order.signer, _wallet);
    expect(order.signatureType, 3);
    expect(order.side, 0);
    expect(order.tokenId, _comboYes);
    expect(order.makerAmount, BigInt.from(966191));
    expect(order.takerAmount, BigInt.from(1932381));

    final sell = buildComboOrder(
        quote: _quote(direction: ComboDirection.sell),
        depositWallet: _wallet,
        now: now);
    expect(sell.side, 1);
  });

  test('EIP-712 hashes of the v3 order match the independent vectors', () {
    final order = buildComboOrder(
      quote: _quote(),
      depositWallet: _wallet,
      salt: BigInt.parse('1122334455667788', radix: 16),
      now: now,
    );
    final wrapped = orderV2Poly1271TypedData(
      order: order,
      verifyingContract: PolymarketConstants.comboExchangeV3Address,
      domainVersion: PolymarketConstants.comboExchangeEip712DomainVersion,
    );
    expect(wrapped.domain['version'], '3');
    expect(wrapped.domain['name'], 'Polymarket CTF Exchange');
    expect(wrapped.message['verifyingContract'], _wallet);
    expect(wrapped.message['name'], 'DepositWallet');
    expect(_hex(wrapped.digest), _wrappedDigest);

    final bare = orderV2TypedData(
      order: order,
      verifyingContract: PolymarketConstants.comboExchangeV3Address,
      domainVersion: '3',
    );
    expect(_hex(bare.digest), _orderHash);

    // The CLOB domain ("2") must produce a different digest, and Exchange
    // v3's own domain is what the typed data defaults to.
    final v2 = orderV2Poly1271TypedData(
        order: order,
        verifyingContract: PolymarketConstants.comboExchangeV3Address,
        domainVersion: '2');
    expect(_hex(v2.digest), isNot(_wrappedDigest));
    final byDefault = orderV2Poly1271TypedData(
        order: order,
        verifyingContract: PolymarketConstants.comboExchangeV3Address);
    expect(_hex(byDefault.digest), _wrappedDigest);
  });

  test('ERC-7739 wire signature: layout, trailer and recovery', () async {
    final order = buildComboOrder(
      quote: _quote(),
      depositWallet: _wallet,
      salt: BigInt.parse('1122334455667788', radix: 16),
      now: now,
    );
    final signed = await signComboOrder(order: order, credentials: key);
    final wire = signed['signature'] as String;
    final typeHex = _hex(utf8.encode(_orderType));
    expect(wire.length, 2 + 130 + 64 + 64 + typeHex.length + 4);
    final inner = wire.substring(2, 132);
    expect(wire.substring(132, 196), _appDomainSep);
    expect(wire.substring(196, 260), _contentsHash);
    expect(wire.substring(260), '${typeHex}00ba');
    expect(recoverSignerAddress(_bytes(_wrappedDigest), _sig(inner)),
        _address.toLowerCase());

    // The accept body's signed_order: every order field plus the signature.
    expect(signed['timestamp'], '1773890760');
    expect(signed['salt'], BigInt.parse('1122334455667788', radix: 16)
        .toString());
    expect(signed['builder'], PolymarketConstants.bytes32Zero);
    expect(signed['side'], 0);
    expect(signed['signatureType'], 3);
    expect(signed['makerAmount'], '966191');
    expect(signed['takerAmount'], '1932381');
    final body = jsonDecode(
        comboAcceptBody(quoteId: 'quote_1', signedOrder: signed)) as Map;
    expect(body['quote_id'], 'quote_1');
    expect((body['signed_order'] as Map)['signature'], wire);
  });

  test('refuses to sign for anything but a deposit wallet', () async {
    final order = OrderStructV2(
      salt: BigInt.one,
      maker: _wallet,
      signer: _address,
      tokenId: _comboYes,
      makerAmount: BigInt.one,
      takerAmount: BigInt.two,
      side: 0,
      signatureType: 3,
      timestamp: BigInt.one,
      metadata: PolymarketConstants.bytes32Zero,
      builder: PolymarketConstants.bytes32Zero,
    );
    expect(() => signComboOrder(order: order, credentials: key),
        throwsA(isA<ComboQuoteMismatch>()));
  });

  test('salts are random 64-bit values', () {
    final a = comboOrderSalt();
    final b = comboOrderSalt();
    expect(a, isNot(b));
    expect(a.bitLength, lessThanOrEqualTo(64));
  });
}
