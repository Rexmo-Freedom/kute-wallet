// Signing parity between the phone (Dart VM) and the web build (dart2js).
//
// Every expected value here is fixed: the Python SDK vectors (embedded from
// fixtures/hl_vectors.json) and goldens captured from the VM run of the
// phone path, which works against the live exchange. The file uses no
// dart:io, so the SAME assertions run in both places:
//
//   flutter test test/services/web_signing_parity_test.dart
//   flutter test --platform chrome test/services/web_signing_parity_test.dart
//
// A single differing byte in a packed action or a hash means a signature
// that recovers to another address, which the exchange refuses.
//
// TEST-ONLY KEYS: [_sdkKey] is the Python SDK's public example key and
// [_testKey] was generated for this file. Neither controls anything; never
// fund them.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/hyperliquid/hyperliquid_msgpack.dart';
import 'package:kute/services/hyperliquid/hyperliquid_rounding.dart';
import 'package:kute/services/hyperliquid/hyperliquid_signing.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show EthPrivateKey;
import 'package:web3dart/web3dart.dart'
    show MsgSignature, ecRecover, publicKeyToAddress;

import 'fixtures/hl_vectors_embedded.dart';
import 'hyperliquid_test_actions.dart';

const _sdkKey =
    '0x0123456789012345678901234567890101234567890123456789012345678901';

/// Generated for this test only (2026-11-25). Controls nothing.
const _testKey =
    '0x3d09455d999be666fa8173e12fb3f6546a5a170151da3f82e3c66aea8583a324';

/// A millisecond nonce of today's size (above 2^32, like every real one).
const _nonce = 1764072000123;

/// An order id of today's size (above 2^32, like every real one).
const _bigOid = 46728193441;

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

String _recover(Uint8List digest, Map<String, dynamic> sig) {
  final pub = ecRecover(
    digest,
    MsgSignature(
      BigInt.parse((sig['r'] as String).substring(2), radix: 16),
      BigInt.parse((sig['s'] as String).substring(2), radix: 16),
      sig['v'] as int,
    ),
  );
  return '0x${_hex(publicKeyToAddress(pub))}';
}

/// The founder's case and its neighbours, built through the production
/// builders with fixed inputs.
Map<String, Map<String, dynamic>> _modernL1Actions() => {
      // Close a short at market: an IOC buy, reduce-only, with a cloid and
      // the builder fee, exactly the shape closePosition sends.
      'close_short_ioc_reduce_only': buildOrderAction(
        orders: [
          HlOrderWire(
            assetId: 110023,
            isBuy: true,
            px: slippagePrice(
                referencePx: 181.37,
                isBuy: true,
                slippage: 0.05,
                szDecimals: 3,
                isSpot: false),
            sz: roundSize(1.234, 3),
            reduceOnly: true,
            orderType: limitOrderType('Ioc'),
            cloid: '0x9f86d081884c7d659a2feaa0c55ad015',
          ),
        ],
        builder: const HlBuilderFee(address: kHlTestBuilder, feeTenthsBp: 25),
      ),
      'limit_gtc': buildOrderAction(orders: [
        HlOrderWire(
          assetId: 0,
          isBuy: false,
          px: roundPrice(97123.4, szDecimals: 5, isSpot: false),
          sz: roundSize(0.00123, 5),
          reduceOnly: false,
          orderType: limitOrderType('Gtc'),
        ),
      ]),
      'cancel_big_oid': buildCancelAction([(assetId: 110023, oid: _bigOid)]),
      'modify_big_oid': buildModifyAction(
        oid: _bigOid,
        order: HlOrderWire(
          assetId: 4,
          isBuy: true,
          px: '3012.5',
          sz: '0.5',
          reduceOnly: false,
          orderType: limitOrderType('Alo'),
        ),
      ),
      'update_leverage':
          buildUpdateLeverageAction(assetId: 110023, isCross: false, leverage: 3),
      'isolated_margin_remove':
          buildUpdateIsolatedMarginAction(assetId: 110023, ntli: -12500000),
      'twap_order': buildTwapOrderAction(
          assetId: 1,
          isBuy: false,
          sizeWire: '2.5',
          reduceOnly: true,
          minutes: 30,
          randomize: false),
      'twap_cancel': buildTwapCancelAction(assetId: 1, twapId: 4294967297),
    };

void main() {
  final vectors = jsonDecode(kHlVectorsJson) as Map<String, dynamic>;
  final sdkSigner = (vectors['signer'] as String).toLowerCase();
  final sdkCredentials = EthPrivateKey.fromHex(_sdkKey);
  final testCredentials = EthPrivateKey.fromHex(_testKey);

  group('Python SDK vectors', () {
    test('msgpack scalars', () {
      for (final raw in (vectors['msgpack'] as Map)['scalars'] as List) {
        final e = raw as Map<String, dynamic>;
        var v = e['value'];
        if (v is num && v is! int) v = v.toInt();
        if (v is double) v = v.toInt();
        expect(_hex(packMsgpack(v)), e['hex'], reason: 'value $v');
      }
    });

    test('floatToWire', () {
      for (final raw in vectors['floatToWire'] as List) {
        final e = raw as Map<String, dynamic>;
        expect(floatToWire((e['value'] as num).toDouble()), e['wire']);
      }
    });

    final actions = buildHlTestActions();
    for (final raw in vectors['l1Actions'] as List) {
      final e = raw as Map<String, dynamic>;
      final name = e['name'] as String;
      test('L1 $name: msgpack, connectionId, digests, signer', () async {
        final action = actions[
            name.replaceFirst('_vault', '').replaceFirst('_expires', '')]!;
        expect(_hex(packMsgpack(action)), e['msgpackHex']);
        final connectionId = actionHash(
          action: action,
          nonce: e['nonce'] as int,
          vaultAddress: e['vaultAddress'] as String?,
          expiresAfter: e['expiresAfter'] as int?,
        );
        expect(_hex(connectionId), e['connectionIdHex']);
        for (final (isMainnet, net) in [(true, 'mainnet'), (false, 'testnet')]) {
          final digest =
              l1ActionDigest(connectionId: connectionId, isMainnet: isMainnet);
          expect(_hex(digest), e['digest_$net']);
          expect(_recover(digest, e['pythonSig_$net'] as Map<String, dynamic>),
              sdkSigner);
          final ours = await signL1Action(
            credentials: sdkCredentials,
            action: action,
            nonce: e['nonce'] as int,
            vaultAddress: e['vaultAddress'] as String?,
            expiresAfter: e['expiresAfter'] as int?,
            isMainnet: isMainnet,
          );
          expect(_recover(digest, ours.toJson()), sdkSigner);
        }
      });
    }

    final fieldsByType = {
      withdrawPrimaryType: withdrawSignTypes,
      usdClassTransferPrimaryType: usdClassTransferSignTypes,
      approveBuilderFeePrimaryType: approveBuilderFeeSignTypes,
    };
    for (final raw in vectors['userSignedActions'] as List) {
      final e = raw as Map<String, dynamic>;
      test('user-signed ${e['name']}: digest, signer', () {
        final digest = userSignedActionDigest(
          primaryType: e['primaryType'] as String,
          fields: fieldsByType[e['primaryType']]!,
          message: Map<String, dynamic>.from(e['action'] as Map),
          signatureChainId: 0x66eee,
        );
        expect(_hex(digest), e['digest']);
        expect(_recover(digest, e['pythonSig'] as Map<String, dynamic>),
            sdkSigner);
      });
    }
  });

  group('VM goldens at today\'s nonce and order-id sizes', () {
    final signer = testCredentials.address.hexEip55.toLowerCase();

    test('the test key is the expected address', () {
      expect(signer, _goldens['signer']);
    });

    test('the nonce suffix is 8 big-endian bytes', () {
      // msgpack(nil) ++ nonce ++ 0x00: the nonce bytes are bytes 1..8.
      final packed = packMsgpack(_nonce);
      expect(_hex(packed), 'cf0000019abae28a7b');
    });

    _modernL1Actions().forEach((name, action) {
      test('L1 $name', () async {
        final g = _goldens[name] as Map<String, Object>;
        expect(_hex(packMsgpack(action)), g['msgpack']);
        final connectionId = actionHash(action: action, nonce: _nonce);
        expect(_hex(connectionId), g['connectionId']);
        final digest =
            l1ActionDigest(connectionId: connectionId, isMainnet: true);
        expect(_hex(digest), g['digest']);
        final sig = await signL1Action(
            credentials: testCredentials,
            action: action,
            nonce: _nonce,
            isMainnet: true);
        expect(sig.toJson(), g['sig']);
        expect(_recover(digest, sig.toJson()), signer);
      });
    });

    test('L1 close with expiresAfter', () {
      final action = _modernL1Actions()['close_short_ioc_reduce_only']!;
      final connectionId = actionHash(
          action: action, nonce: _nonce, expiresAfter: _nonce + 60000);
      expect(_hex(connectionId), _goldens['close_expires_connectionId']);
    });

    Map<String, ({Map<String, dynamic> action, List<HlTypedField> fields, String type})>
        userSigned() => {
              'withdraw3': (
                action: buildWithdraw3Action(
                    destination: '0x5e9ee1089755c3435139848e47e6635505d5a13a',
                    amount: '25.5',
                    time: _nonce),
                fields: withdrawSignTypes,
                type: withdrawPrimaryType,
              ),
              'usd_send': (
                action: buildUsdSendAction(
                    destination: '0x5e9ee1089755c3435139848e47e6635505d5a13a',
                    amount: '3',
                    time: _nonce),
                fields: usdSendSignTypes,
                type: usdSendPrimaryType,
              ),
              'spot_send': (
                action: buildSpotSendAction(
                    destination: '0x5e9ee1089755c3435139848e47e6635505d5a13a',
                    token: 'USDC:0x6d1e7cde53ba9467b783cb7c530ce054',
                    amount: '7.25',
                    time: _nonce),
                fields: spotSendSignTypes,
                type: spotSendPrimaryType,
              ),
              'usd_class_transfer': (
                action: buildUsdClassTransferAction(
                    amount: '10.5', toPerp: false, nonce: _nonce),
                fields: usdClassTransferSignTypes,
                type: usdClassTransferPrimaryType,
              ),
              'approve_builder_fee': (
                action: buildApproveBuilderFeeAction(
                    builder: kHlTestBuilder.toLowerCase(),
                    maxFeeRate: '0.025%',
                    nonce: _nonce),
                fields: approveBuilderFeeSignTypes,
                type: approveBuilderFeePrimaryType,
              ),
              'send_to_evm_with_data': (
                action: buildSendToEvmWithDataAction(
                    token: 'USDC',
                    amount: '42.123456',
                    sourceDex: '',
                    destinationRecipient:
                        '0x5e9ee1089755c3435139848e47e6635505d5a13a',
                    destinationChainId: 3,
                    gasLimit: 200000,
                    nonce: _nonce),
                fields: sendToEvmWithDataSignTypes,
                type: sendToEvmWithDataPrimaryType,
              ),
            };

    userSigned().forEach((name, u) {
      test('user-signed $name', () async {
        final g = _goldens[name] as Map<String, Object>;
        final sig = await signUserSignedAction(
          credentials: testCredentials,
          action: u.action,
          fields: u.fields,
          primaryType: u.type,
          isMainnet: true,
        );
        final digest = userSignedActionDigest(
            primaryType: u.type, fields: u.fields, message: u.action);
        expect(_hex(digest), g['digest']);
        expect(sig.toJson(), g['sig']);
        expect(_recover(digest, sig.toJson()), signer);
        // The POSTed JSON carries the same integers, never "1.0".
        expect(jsonEncode(u.action), g['json']);
      });
    });
  });
}

/// Captured from the VM (the phone path) before the web fix.
const Map<String, Object> _goldens = {
  'approve_builder_fee': {'digest': 'eb844527c6d91ec2fbec650775739cb5bb873c7dc0cba5184587fdb58179a2a5', 'sig': {'r': '0x33d3f1f8604ee19644894cd5ddbc1e4370e92e1ece58999931c265aebcf57026', 's': '0xae56d3da00c4d2448969357276e1cdb5db72800113048182aeb92e8cc6e46a1', 'v': 27}, 'json': r'{"maxFeeRate":"0.025%","builder":"0x8c967e73e6b15087c42a10d344cff4c96d877f1d","nonce":1764072000123,"type":"approveBuilderFee","signatureChainId":"0xa4b1","hyperliquidChain":"Mainnet"}'},
  'cancel_big_oid': {'msgpack': '82a474797065a663616e63656ca763616e63656c739182a161ce0001adc7a16fcf0000000ae137a5a1', 'connectionId': '55578d08f059d47ec5ac567de5b08df065c36078a29d43d1a750cad51b97d947', 'digest': '1a4cbbd04263177c0e208cd39a01bd35c7429c7a31f906b255d09b32ac8716de', 'sig': {'r': '0x71910e7e8d0e78c8dc2b383af6af73dee77d8857889b7284e329701194be69e4', 's': '0x68fc6d4997abe29c5597b6964a17c2f7fbf0ba0b5c7aa9deef5f131eb9fc6fed', 'v': 28}},
  'close_expires_connectionId': '285e16f6ea563a30ede3db66424e1220fbd363a2268e30989c7caeac7efdee79',
  'close_short_ioc_reduce_only': {'msgpack': '84a474797065a56f72646572a66f72646572739187a161ce0001adc7a162c3a170a63139302e3434a173a5312e323334a172c3a17481a56c696d697481a3746966a3496f63a163d92230783966383664303831383834633764363539613266656161306335356164303135a867726f7570696e67a26e61a76275696c64657282a162d92a307838633936376537336536623135303837633432613130643334346366663463393664383737663164a16619', 'connectionId': 'c6b7ec1f543a303bc1b8464936a78206358eac7373b59e5b8f37fc52c241407b', 'digest': 'a5163151de0eea4abbc14f0078543ce453c18c364c9f9151dbdb723789e92121', 'sig': {'r': '0xfda6fd1027e9ccab18cc52aaf215a51ed4838f839bde9aac58d10feb89deed70', 's': '0x248f139db635bb36e604dd95ec4f3338398c4e0c483881dc6b8c643abd58615c', 'v': 27}},
  'isolated_margin_remove': {'msgpack': '84a474797065b475706461746549736f6c617465644d617267696ea56173736574ce0001adc7a56973427579c3a46e746c69d2ff4143e0', 'connectionId': 'feebc119d418b66011814613873c61f1299884b78ee16568df9dd275d9f7428a', 'digest': 'c4a330b7169d70449c9ef32048f5a48f5163a9fca650d5f0b42cb608b751625e', 'sig': {'r': '0xed308a328d1332a5b2f0ddeca7d73881ea10f77cfe2690415bd52a69a9805c59', 's': '0x5e3310c9729b6b3c18c7b17b98aadcae3e20090df81cff4ee8bede97c1a652a9', 'v': 27}},
  'limit_gtc': {'msgpack': '83a474797065a56f72646572a66f72646572739186a16100a162c2a170a53937313233a173a7302e3030313233a172c2a17481a56c696d697481a3746966a3477463a867726f7570696e67a26e61', 'connectionId': '63804dca20756feb7530b0a69ea995f7707280e24ecce6a9884bd05902338eac', 'digest': '6c2df7b33d656276836e649b476b6668fbd4e9640fc060e8c210e51c7a3e853d', 'sig': {'r': '0x8b905ae80a90e154691e8837eba1a2691fcaf0cb533c9ba2cc1a80642806ec63', 's': '0x189ea48da632acfe15ac0a7abb90676b90087a21b17cbb75e375a6b24a742110', 'v': 28}},
  'modify_big_oid': {'msgpack': '83a474797065a66d6f64696679a36f6964cf0000000ae137a5a1a56f7264657286a16104a162c3a170a6333031322e35a173a3302e35a172c2a17481a56c696d697481a3746966a3416c6f', 'connectionId': 'd957fd91e3c53b812e1fbf9c58cf52d2bf4428108663eed5941ebf6aea90ff53', 'digest': 'c3d3cc35b8c9e75b7a05b38d4c5557248d59a1a5d501a7634cec0fcb6ac4e4ba', 'sig': {'r': '0xcba42aed57b4d55100b8763c5b3730cf55223affd45250f81dbc5abecb12d0ce', 's': '0x5e1a829c760470e3e598b3ce01b75928a0eafc6dbb4c9411bd692ef3ee7b8037', 'v': 27}},
  'send_to_evm_with_data': {'digest': 'f42968d3c6d52efd53770e510423c72ce7aca4438a58459952bbac952e0dfa89', 'sig': {'r': '0x399c79539854e14437d2eb8f9c09c5843ba47b66422ae645c107e39749745f22', 's': '0x4a62555796e37918099149ee2a32a9fd61757fe7095452613eb094b3aaf2eccc', 'v': 27}, 'json': r'{"type":"sendToEvmWithData","token":"USDC","amount":"42.123456","sourceDex":"","destinationRecipient":"0x5e9ee1089755c3435139848e47e6635505d5a13a","addressEncoding":"hex","destinationChainId":3,"gasLimit":200000,"data":"0x","nonce":1764072000123,"signatureChainId":"0xa4b1","hyperliquidChain":"Mainnet"}'},
  'signer': '0xe013a1fc0e722b0b5d477d0fec7501cab935bedf',
  'spot_send': {'digest': '37c353c2ba9dcf3d2bd6b1ac9adb51310c9fa3c36c13b6303ab6fee3b354124c', 'sig': {'r': '0x28843e6c79416bf0e3ae2eb3107d64ef6a5b1ffc3cc89a4d540584704bd2fb4', 's': '0x37cdb9905614fc1a98a54b760c34132b2e5fe7352c05fe2ed88364f686330eaa', 'v': 27}, 'json': r'{"destination":"0x5e9ee1089755c3435139848e47e6635505d5a13a","amount":"7.25","token":"USDC:0x6d1e7cde53ba9467b783cb7c530ce054","time":1764072000123,"type":"spotSend","signatureChainId":"0xa4b1","hyperliquidChain":"Mainnet"}'},
  'twap_cancel': {'msgpack': '83a474797065aa7477617043616e63656ca16101a174cf0000000100000001', 'connectionId': '17392c0daecb5214955bc379cc497855b5abe2a13f89e03423ccd266cf2c17b2', 'digest': '30e0c7958f2a2998ccc9ced6afd3922c8d334fc8b2695511f056db5593bb977e', 'sig': {'r': '0xb23954e609b6a090c6fabb1e5a8964ecef94b8d5a7338b405cd76f1061691726', 's': '0x65ff0d7595e0956fd41caddf329ce212b5e6eb594695498056dc57122259b20c', 'v': 27}},
  'twap_order': {'msgpack': '82a474797065a9747761704f72646572a47477617086a16101a162c2a173a3322e35a172c3a16d1ea174c2', 'connectionId': 'c05a4dbd62f76b8e25b41582a0eba1675f34cdd4c8c656b1150ac268d554f602', 'digest': 'fdf2ef93f96a1ebce1ba6a6da43c2e7ca6eac4e2697bdb429b425a8a472fbfab', 'sig': {'r': '0x302bf1381c6a2682adc6c972ff8e08550d6a86e95354e5bba33efcf9ff2b5406', 's': '0x5d23616d1c8014212a85049a11d576803fa22391c4c9c1604bacc957835163c7', 'v': 27}},
  'update_leverage': {'msgpack': '84a474797065ae7570646174654c65766572616765a56173736574ce0001adc7a7697343726f7373c2a86c6576657261676503', 'connectionId': '1a63a9dca1dc8896630e4df5a7ec64660591d9a9d8864a2a984fee909f4b189d', 'digest': '88a28ffa1d0aa19c1a2723d0f26a5a1d7156b99bcabbfb9f16bef589dbbf7315', 'sig': {'r': '0x2160f56bc3324f07222f657e1cc8d764fb086203e6cd4b3acffd113aa5f383d9', 's': '0x5288a6f2d81ae946a943f22f284338bc0e503a0070d55c0258c24df244ecf3e8', 'v': 28}},
  'usd_class_transfer': {'digest': '4d537517ff39139931bede0a5b937500ffe3ed89270909a63bc9f47d919cfe8b', 'sig': {'r': '0x190f7f8183d73e78b4bd7a59cf81b8eaa7e92e5a337f8c992b880143f5b5f6f6', 's': '0x2c5bfa85e93b9e1f4a3a37455522b15e6166887adb235b91fb0d33fb6d4c4bc7', 'v': 28}, 'json': r'{"type":"usdClassTransfer","amount":"10.5","toPerp":false,"nonce":1764072000123,"signatureChainId":"0xa4b1","hyperliquidChain":"Mainnet"}'},
  'usd_send': {'digest': 'abb35d5654eabae401969989570b4336beece01a5676f87cc6e1a7fd28c13476', 'sig': {'r': '0x76ae5c14f0682890c24050925ac4f47d6c52743c26083ee6d75573c827903d0a', 's': '0x2e900b72f973b4f9d1880ac2c7a1145037ae837b6a2480f998918cb68747172e', 'v': 27}, 'json': r'{"destination":"0x5e9ee1089755c3435139848e47e6635505d5a13a","amount":"3","time":1764072000123,"type":"usdSend","signatureChainId":"0xa4b1","hyperliquidChain":"Mainnet"}'},
  'withdraw3': {'digest': 'fec5e91b38a0c54a298a63ae6dc2d6531a7c5fbfe4d3f9bfefc5620f17777119', 'sig': {'r': '0x76f8ff90f15227202d33ba1659713362bb5c44e5f7ea841b1d936b2d82f58981', 's': '0x6a95a3228572b4776b958fd9a7fc7ba6564ddd8484c6972a748762875a5ded69', 'v': 27}, 'json': r'{"destination":"0x5e9ee1089755c3435139848e47e6635505d5a13a","amount":"25.5","time":1764072000123,"type":"withdraw3","signatureChainId":"0xa4b1","hyperliquidChain":"Mainnet"}'},
};
