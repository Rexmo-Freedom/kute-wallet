// `sendToEvmWithData` signing: the first user-signed action with `uint32`
// and `bytes` fields. Three independent proofs:
//   1. the type string is exactly Circle's / Hyperliquid's field list;
//   2. the hand-rolled hashes equal a known-answer vector computed outside
//      this codebase (a stand-alone pure-Python Keccak-256 and EIP-712
//      encoder, run on 2026-10-13) for two real mainnet actions: Circle's
//      form (`USDC`, `data: 0x`, hash 0x3e1e…5f82) and the token-id form
//      with non-empty hook data (hash 0x052f…091d);
//   3. they equal the generic EIP-712 encoder's hashes, and a signature
//      recovers to the signing key over that digest.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kute/services/hyperliquid/hyperliquid_exchange_service.dart';
import 'package:kute/services/hardware/evm_signing_request.dart';
import 'package:kute/services/hyperliquid/hyperliquid_signing.dart';
import 'package:pointycastle/digests/keccak.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show EthPrivateKey, EthSignature;

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List _keccak(List<int> data) =>
    KeccakDigest(256).process(Uint8List.fromList(data));

final _circleForm = <String, dynamic>{
  'hyperliquidChain': 'Mainnet',
  'token': 'USDC',
  'amount': '173',
  'sourceDex': 'spot',
  'destinationRecipient': '0x7578d21940ee6ac4f882b6d5173d26bce62f5136',
  'addressEncoding': 'hex',
  'destinationChainId': 3,
  'gasLimit': 200000,
  'data': '0x',
  'nonce': 1791851727813,
};

final _tokenIdForm = <String, dynamic>{
  'hyperliquidChain': 'Mainnet',
  'token': 'USDC:0x6d1e7cde53ba9467b783cb7c530ce054',
  'amount': '2.0',
  'sourceDex': 'spot',
  'destinationRecipient': '0x0ef190f509044b367521c3304063e30e382df5b1',
  'addressEncoding': 'hex',
  'destinationChainId': 3,
  'gasLimit': 500000,
  'data': '0x636374702d666f7277617264000000000000000000000000000000000000004479'
      'ddd85746b3c2a6ae6a3397259326675247773d000001a132af39ec73c0dea519f122e'
      'ad7bf441dda43c5631b10a1ece3fffbbe8a3ce2dca324a34cb7e8fd1dc0de017b',
  'nonce': 1791851706860,
};

void main() {
  test('type string and type hash are the documented field list', () {
    const typeString = 'HyperliquidTransaction:SendToEvmWithData('
        'string hyperliquidChain,string token,string amount,string sourceDex,'
        'string destinationRecipient,string addressEncoding,'
        'uint32 destinationChainId,uint64 gasLimit,bytes data,uint64 nonce)';
    final built = '$sendToEvmWithDataPrimaryType('
        '${sendToEvmWithDataSignTypes.map((f) => '${f.type} ${f.name}').join(',')})';
    expect(built, typeString);
    expect(_hex(_keccak(utf8.encode(built))),
        '6a99d9af92175da1a2f1ca873b7a35db83d042f3b093578b7b0a2a99c07ba86f');
  });

  test('Circle form (empty data) matches the external vector', () {
    final hashes = userSignedActionHashes(
      primaryType: sendToEvmWithDataPrimaryType,
      fields: sendToEvmWithDataSignTypes,
      message: _circleForm,
      signatureChainId: 0xa4b1,
    );
    expect(_hex(hashes.domain),
        '2f54e643b38c9c2b65cb731aaf11c54f01705ee0cdf45aea16e2ac0a5ce7531a');
    expect(_hex(hashes.message),
        '1ffd46e3f295fb36fa8d40629892ad42dcbe94b152d13bc2a31a4f73caca7e77');
    expect(_hex(hashes.digest),
        '99f5d13645a717b5d9b3c4d7f4d7a20bc25acb384cdbb81f1a0520478d2894a8');
  });

  test('token-id form with hook data matches the external vector', () {
    final hashes = userSignedActionHashes(
      primaryType: sendToEvmWithDataPrimaryType,
      fields: sendToEvmWithDataSignTypes,
      message: _tokenIdForm,
      signatureChainId: 0x3e7,
    );
    expect(_hex(hashes.domain),
        'd32d810d4bfe4771b1d495256b32ddf3ca822f5f457282b00f0447bf6461b749');
    expect(_hex(hashes.message),
        '34aa9927ed83e565267c71f83a1d4773544e2d896047185dce7d5c623f1db87c');
    expect(_hex(hashes.digest),
        '79c612a58e49c1f719092e7cf033f336f5f84b383c189a733d52f6919a131c90');
  });

  test('bytes are hashed, not padded: empty data is keccak("")', () {
    final empty = userSignedActionHashes(
      primaryType: sendToEvmWithDataPrimaryType,
      fields: sendToEvmWithDataSignTypes,
      message: _circleForm,
    );
    final withByte = userSignedActionHashes(
      primaryType: sendToEvmWithDataPrimaryType,
      fields: sendToEvmWithDataSignTypes,
      message: {..._circleForm, 'data': '0x00'},
    );
    expect(_hex(empty.message), isNot(_hex(withByte.message)));
  });

  test('generic encoder agrees on both forms and chains', () {
    for (final message in [_circleForm, _tokenIdForm]) {
      for (final chainId in [0xa4b1, 0x3e7, 0x66eee]) {
        final builder = userSignedActionHashes(
          primaryType: sendToEvmWithDataPrimaryType,
          fields: sendToEvmWithDataSignTypes,
          message: message,
          signatureChainId: chainId,
        );
        final generic = userSignedActionTypedData(
          primaryType: sendToEvmWithDataPrimaryType,
          fields: sendToEvmWithDataSignTypes,
          message: {...message, 'type': 'ignored'},
          signatureChainId: chainId,
        );
        expect(_hex(generic.domainSeparator), _hex(builder.domain));
        expect(_hex(generic.structHash), _hex(builder.message));
      }
    }
  });

  test('uint32 and uint64 reject values that do not fit', () {
    Object? attempt(Map<String, dynamic> m) {
      try {
        userSignedActionHashes(
            primaryType: sendToEvmWithDataPrimaryType,
            fields: sendToEvmWithDataSignTypes,
            message: m);
        return null;
      } catch (e) {
        return e;
      }
    }

    expect(attempt({..._circleForm, 'destinationChainId': 1 << 32}),
        isA<ArgumentError>());
    expect(attempt({..._circleForm, 'destinationChainId': -1}),
        isA<ArgumentError>());
    expect(attempt({..._circleForm, 'data': '0x0'}), isA<ArgumentError>());
    expect(attempt({..._circleForm, 'data': 'zz'}), isA<ArgumentError>());
  });

  test('signs the augmented action; the signature recovers to the key',
      () async {
    final key = EthPrivateKey.fromHex(
        '0x0123456789012345678901234567890101234567890123456789012345678901');
    final action = buildSendToEvmWithDataAction(
      token: 'USDC',
      amount: '5.25',
      sourceDex: '',
      destinationRecipient: '0x${'ab' * 20}',
      destinationChainId: 3,
      gasLimit: 200000,
      nonce: 1791851727813,
    );
    expect(action['data'], '0x');
    expect(action['addressEncoding'], 'hex');
    final sig = await signUserSignedAction(
      credentials: key,
      action: action,
      fields: sendToEvmWithDataSignTypes,
      primaryType: sendToEvmWithDataPrimaryType,
      isMainnet: true,
      signatureChainId: 0xa4b1,
    );
    expect(action['signatureChainId'], '0xa4b1');
    expect(action['hyperliquidChain'], 'Mainnet');
    final digest = userSignedActionDigest(
        primaryType: sendToEvmWithDataPrimaryType,
        fields: sendToEvmWithDataSignTypes,
        message: action,
        signatureChainId: 0xa4b1);
    // The signature the action is POSTed with recovers over the digest.
    final recovered =
        recoverSignerAddress(digest, EthSignature(sig.r, sig.s, sig.v));
    expect(recovered?.toLowerCase(), key.address.hexEip55.toLowerCase());
    expect(sig.v == 27 || sig.v == 28, isTrue);
  });

  group('exchange POST', () {
    final key = EthPrivateKey.fromHex(
        '0x0123456789012345678901234567890101234567890123456789012345678901');
    const target = '0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed';

    test('Circle\'s action shape, the nonce bound before the POST', () async {
      final bodies = <Map<String, dynamic>>[];
      int? boundNonce;
      final client = MockClient((request) async {
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response('{"status":"ok","response":{"type":"default"}}',
            200);
      });
      addTearDown(client.close);
      final exchange = HyperliquidExchangeService(
        credentials: key,
        walletAddress: key.address.hexEip55,
        httpClient: client,
        allowNonceRetry: false,
        onBeforePost: (post) async => boundNonce = post.nonce,
      );
      final nonce = await exchange.sendToEvmWithData(
          destination: target,
          amount: '5.25',
          sourceDex: '',
          destinationDomain: 3,
          gasLimit: 200000,
          token: 'USDC');
      expect(boundNonce, nonce);
      final body = bodies.single;
      expect(body['nonce'], nonce);
      final action = body['action'] as Map<String, dynamic>;
      expect(action, {
        'type': 'sendToEvmWithData',
        'token': 'USDC',
        'amount': '5.25',
        'sourceDex': '',
        'destinationRecipient': target,
        'addressEncoding': 'hex',
        'destinationChainId': 3,
        'gasLimit': 200000,
        'data': '0x',
        'nonce': nonce,
        'signatureChainId': '0xa4b1',
        'hyperliquidChain': 'Mainnet',
      });
      final signature = body['signature'] as Map<String, dynamic>;
      final digest = userSignedActionDigest(
          primaryType: sendToEvmWithDataPrimaryType,
          fields: sendToEvmWithDataSignTypes,
          message: action,
          signatureChainId: 0xa4b1);
      final recovered = recoverSignerAddress(
          digest,
          EthSignature(
              BigInt.parse((signature['r'] as String).substring(2), radix: 16),
              BigInt.parse((signature['s'] as String).substring(2), radix: 16),
              signature['v'] as int));
      expect(recovered?.toLowerCase(), key.address.hexEip55.toLowerCase());
    });

    test('a rejection is never retried with a fresh nonce', () async {
      var posts = 0;
      final client = MockClient((_) async {
        posts++;
        return http.Response(
            jsonEncode({'status': 'err', 'response': 'Invalid nonce'}), 200);
      });
      addTearDown(client.close);
      final exchange = HyperliquidExchangeService(
          credentials: key,
          walletAddress: key.address.hexEip55,
          httpClient: client);
      await expectLater(
          exchange.sendToEvmWithData(
              destination: target,
              amount: '5',
              sourceDex: 'spot',
              destinationDomain: 3,
              gasLimit: 200000,
              token: 'USDC'),
          throwsA(isA<HyperliquidRejectedException>()));
      expect(posts, 1);
    });

    test('nothing is signed for an invalid action', () async {
      final client = MockClient((_) async => fail('no POST'));
      addTearDown(client.close);
      final exchange = HyperliquidExchangeService(
          credentials: key,
          walletAddress: key.address.hexEip55,
          httpClient: client);
      for (final call in <Future<int> Function()>[
        () => exchange.sendToEvmWithData(
            destination: key.address.hexEip55,
            amount: '5',
            sourceDex: '',
            destinationDomain: 3,
            gasLimit: 200000,
            token: 'USDC'),
        () => exchange.sendToEvmWithData(
            destination: target,
            amount: '5.1234567',
            sourceDex: '',
            destinationDomain: 3,
            gasLimit: 200000,
            token: 'USDC'),
        () => exchange.sendToEvmWithData(
            destination: target,
            amount: '5',
            sourceDex: 'other',
            destinationDomain: 3,
            gasLimit: 200000,
            token: 'USDC'),
        () => exchange.sendToEvmWithData(
            destination: target,
            amount: '5',
            sourceDex: '',
            destinationDomain: 3,
            gasLimit: 200000,
            token: 'HYPE'),
      ]) {
        await expectLater(call(), throwsA(isA<ArgumentError>()));
      }
    });
  });
}
