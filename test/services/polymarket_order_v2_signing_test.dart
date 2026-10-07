// First Polymarket signing tests (Wallet hardening Phase 3, P3.4).
//
// Fixed-key known answers. The pinned digests and signatures were produced
// by this implementation; no independent reference signer is available in
// this environment. They are still anchored: the generic encoder that
// hashes them is checked against the EIP-712 specification vectors
// (eip712_typed_data_test.dart) and against every hand-rolled builder
// (typed_data_equivalence_test.dart), and every signature must recover to
// the key's address. Any drift in field order, types, domain or wire layout
// breaks these pins.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/constants/polymarket_constants.dart';
import 'package:kute/services/hardware/evm_signing_request.dart';
import 'package:kute/services/polymarket_order_v2.dart';
import 'package:pointycastle/digests/keccak.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show EthPrivateKey, EthSignature;

const _keyHex =
    '0x0123456789012345678901234567890101234567890123456789012345678901';
const _address = '0x42187A0F42088287EbFE8c20BB7adF111e93c381';
const _exchange = '0xE111180000d2663C0091e4f400237545B87B996B';
const _safe = '0x3434343434343434343434343434343434343434';

const _orderType =
    'Order(uint256 salt,address maker,address signer,uint256 tokenId,'
    'uint256 makerAmount,uint256 takerAmount,uint8 side,uint8 signatureType,'
    'uint256 timestamp,bytes32 metadata,bytes32 builder)';

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

OrderStructV2 _order(String signer, int sigType) => OrderStructV2(
      salt: BigInt.parse('479249096354'),
      maker: signer,
      signer: signer,
      tokenId:
          '71321045679252212594626385532706912750332728571942532289631379312455583992563',
      makerAmount: BigInt.from(5000000),
      takerAmount: BigInt.from(10000000),
      side: 1,
      signatureType: sigType,
      timestamp: BigInt.from(1700000000000),
      metadata: PolymarketConstants.bytes32Zero,
      builder: '0x${'ab' * 32}',
    );

void main() {
  final key = EthPrivateKey.fromHex(_keyHex);

  test('fixture key address', () {
    expect(key.address.hexEip55, _address);
  });

  test('sigType 0: known digest and signature', () async {
    final order = _order(_address, 0);
    const digest =
        '75f57ab9fc7d43f1e5a5b960dfcefc3d21c943a63ba3cdf7b6bcff3a98160155';
    const signature =
        '0x232d4cac4242fc254831995debf0daf3227cff2da19eb4226248764edf7c5748'
        '74d229add46c11ec4e0e8789d7c4e38664e80ef4744a64e18232dab159fc6de41c';

    expect(
        _hex(orderV2TypedData(order: order, verifyingContract: _exchange)
            .digest),
        digest);
    final wire = await signOrderV2(
        order: order, credentials: key, verifyingContract: _exchange);
    expect(wire, signature);
    expect(wire.length, 2 + 130);
    expect(recoverSignerAddress(_bytes(digest), _sig(wire.substring(2))),
        _address.toLowerCase());
  });

  test('sigType 3: POLY_1271 wire layout and known values', () async {
    final order = _order(_safe, 3);
    const wrappedDigest =
        'f740cfe5914b2660e3d5965c603de9b17700f0e6a4c53a5ee69f032d237e5173';
    const exchangeOrderHash =
        '887650adec8294667057e2a242db71daf8f5904b0e42637f0b164b8b13dc650b';
    const innerSig =
        '7143efcdf7ce91672b287fd0c34204fbef7579e0049a2ecc595fe8277c0f1b72'
        '7050bb4ab73cdd1142215410a229578b56b7616025c288727213b64dcc365099'
        '1b';
    const appDomainSep =
        '3264e159346253e26a64e00b69032db0e7d32f94628de3e6eecb50304d7af3d2';
    const contentsHash =
        '57ddf1fd65a641f7740a2c3bf01c7169f436de1992101b616118241fbcca334e';

    expect(
        _hex(orderV2Poly1271TypedData(order: order, verifyingContract: _exchange)
            .digest),
        wrappedDigest);
    expect(
        _hex(orderV2TypedData(order: order, verifyingContract: _exchange)
            .digest),
        exchangeOrderHash);

    final wire = await signOrderV2Poly1271(
        order: order, credentials: key, verifyingContract: _exchange);
    final typeHex = _hex(utf8.encode(_orderType));
    expect(utf8.encode(_orderType).length, 0xba);
    expect(wire, '0x$innerSig$appDomainSep$contentsHash${typeHex}00ba');
    expect(wire.length, 2 + 130 + 64 + 64 + typeHex.length + 4);

    // innerSig(65) signs the TypedDataSign<Order> digest.
    expect(recoverSignerAddress(_bytes(wrappedDigest), _sig(innerSig)),
        _address.toLowerCase());

    // The order ID the CLOB reports is keccak(0x1901 | appDomainSep |
    // contentsHash): the Exchange-domain Order hash, not the digest the
    // device signs.
    final orderId = KeccakDigest(256).process(Uint8List.fromList(
        [0x19, 0x01, ..._bytes(appDomainSep), ..._bytes(contentsHash)]));
    expect(_hex(orderId), exchangeOrderHash);
    expect(exchangeOrderHash, isNot(wrappedDigest));
  });
}
