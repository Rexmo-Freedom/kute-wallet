// The generic EIP-712 encoder must hash exactly like every existing
// hand-rolled builder (Wallet hardening Phase 3, plan B3). Two independent
// proofs per builder where the builder hashes are private:
//   1. a software signature from the builder recovers over the GENERIC
//      digest to the key's address;
//   2. the external path's runtime equality check passes (it throws
//      EvmTypedDataMismatchException before the signer on any drift).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/constants/polymarket_constants.dart';
import 'package:kute/services/hardware/eip712_typed_data.dart';
import 'package:kute/services/hardware/evm_signer.dart';
import 'package:kute/services/hardware/evm_signing_request.dart';
import 'package:kute/services/hardware/signing_clarity.dart';
import 'package:kute/services/hyperliquid/hyperliquid_signing.dart';
import 'package:kute/services/polymarket/deposit_wallet_batch_signer.dart';
import 'package:kute/services/polymarket_onboarding_service.dart';
import 'package:kute/services/polymarket_order_v2.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show EthPrivateKey, EthSignature;

const _keyHex =
    '0x0123456789012345678901234567890101234567890123456789012345678901';

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// First 65 bytes of a 0x signature (plain or POLY_1271 wire layout).
EthSignature _sig(String hex) {
  final clean = hex.substring(2, 2 + 130);
  return EthSignature(
    BigInt.parse(clean.substring(0, 64), radix: 16),
    BigInt.parse(clean.substring(64, 128), radix: 16),
    int.parse(clean.substring(128, 130), radix: 16),
  );
}

void main() {
  final key = EthPrivateKey.fromHex(_keyHex);
  final address = key.address.hexEip55;

  /// An external signer that signs whatever full typed data it receives
  /// and records the request.
  EvmExternalSigner capture(List<EvmSigningRequest> seen) => EvmExternalSigner(
        address: address,
        sign: (request) {
          seen.add(request);
          return key.signToSignature(request.digest);
        },
      );

  group('Hyperliquid', () {
    final fieldsByType = {
      withdrawPrimaryType: withdrawSignTypes,
      usdClassTransferPrimaryType: usdClassTransferSignTypes,
      approveBuilderFeePrimaryType: approveBuilderFeeSignTypes,
    };
    final messages = {
      withdrawPrimaryType: {
        'hyperliquidChain': 'Mainnet',
        'destination': '0x5e9ee1089755c3435139848e47e6635505d5a13a',
        'amount': '100.5',
        'time': 1700000000000,
      },
      usdClassTransferPrimaryType: {
        'hyperliquidChain': 'Testnet',
        'amount': '10.5',
        'toPerp': true,
        'nonce': 1700000000001,
      },
      approveBuilderFeePrimaryType: {
        'hyperliquidChain': 'Mainnet',
        'maxFeeRate': '0.01%',
        'builder': '0x${'ab' * 20}',
        'nonce': 1700000000002,
      },
    };

    for (final primaryType in fieldsByType.keys) {
      for (final chainId in [0x66eee, 42161]) {
        test('$primaryType on chain $chainId', () {
          final builder = userSignedActionHashes(
            primaryType: primaryType,
            fields: fieldsByType[primaryType]!,
            message: messages[primaryType]!,
            signatureChainId: chainId,
          );
          final generic = userSignedActionTypedData(
            primaryType: primaryType,
            fields: fieldsByType[primaryType]!,
            message: {...messages[primaryType]!, 'type': 'ignored'},
            signatureChainId: chainId,
          );
          expect(_hex(generic.domainSeparator), _hex(builder.domain));
          expect(_hex(generic.structHash), _hex(builder.message));
        });
      }
    }

    test('Agent (L1 phantom agent) on both networks', () {
      final connectionId = actionHash(
          action: buildCancelAction([(assetId: 0, oid: 1)]), nonce: 1234);
      for (final isMainnet in [true, false]) {
        final builder =
            l1ActionHashes(connectionId: connectionId, isMainnet: isMainnet);
        final generic =
            l1ActionTypedData(connectionId: connectionId, isMainnet: isMainnet);
        expect(_hex(generic.domainSeparator), _hex(builder.domain));
        expect(_hex(generic.structHash), _hex(builder.message));
      }
    });

    test('external path forwards 0xa4b1 and passes the runtime check',
        () async {
      final seen = <EvmSigningRequest>[];
      final action = buildUsdClassTransferAction(
          amount: '10.5', toPerp: true, nonce: 1700000000000);
      await signUserSignedAction(
        externalSigner: capture(seen),
        action: action,
        fields: usdClassTransferSignTypes,
        primaryType: usdClassTransferPrimaryType,
        isMainnet: true,
        signatureChainId: 42161,
      );
      expect(action['signatureChainId'], '0xa4b1');
      final request = seen.single as Eip712Request;
      expect(request.kind, LedgerActionKind.hlUsdClassTransfer);
      expect(request.data.domain['chainId'], 42161);
    });
  });

  group('Polymarket orders and ClobAuth', () {
    const exchange = '0xE111180000d2663C0091e4f400237545B87B996B';
    OrderStructV2 order({required String signer, required int sigType}) =>
        OrderStructV2(
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

    test('Order (sigType 0)', () async {
      final o = order(signer: address, sigType: 0);
      final wire = await signOrderV2(
          order: o, credentials: key, verifyingContract: exchange);
      final digest =
          orderV2TypedData(order: o, verifyingContract: exchange).digest;
      expect(sameEvmAddress(recoverSignerAddress(digest, _sig(wire))!, address),
          isTrue);

      final seen = <EvmSigningRequest>[];
      await signOrderV2(
          order: o, externalSigner: capture(seen), verifyingContract: exchange);
      expect(seen.single.kind, LedgerActionKind.pmOrderEoa);
    });

    test('TypedDataSign<Order> (sigType 3)', () async {
      final o = order(signer: '0x${'34' * 20}', sigType: 3);
      final wire = await signOrderV2Poly1271(
          order: o, credentials: key, verifyingContract: exchange);
      final digest =
          orderV2Poly1271TypedData(order: o, verifyingContract: exchange)
              .digest;
      expect(sameEvmAddress(recoverSignerAddress(digest, _sig(wire))!, address),
          isTrue);

      final seen = <EvmSigningRequest>[];
      await signOrderV2Poly1271(
          order: o, externalSigner: capture(seen), verifyingContract: exchange);
      final request = seen.single as Eip712Request;
      expect(request.kind, LedgerActionKind.pmOrder);
      expect(request.data.encodeType('TypedDataSign'),
          'TypedDataSign(Order contents,string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)'
          'Order(uint256 salt,address maker,address signer,uint256 tokenId,uint256 makerAmount,uint256 takerAmount,uint8 side,uint8 signatureType,uint256 timestamp,bytes32 metadata,bytes32 builder)');
    });

    test('ClobAuth (EOA)', () async {
      final wire = await signClobAuthEoa(
          credentials: key, address: address, timestamp: 1700000000, nonce: 0);
      final digest = clobAuthEoaTypedData(
              address: address, timestamp: 1700000000, nonce: 0)
          .digest;
      expect(sameEvmAddress(recoverSignerAddress(digest, _sig(wire))!, address),
          isTrue);

      final seen = <EvmSigningRequest>[];
      await signClobAuthEoa(
          externalSigner: capture(seen),
          address: address,
          timestamp: 1700000000,
          nonce: 0);
      expect(seen.single.kind, LedgerActionKind.pmClobAuth);
    });

    test('TypedDataSign<ClobAuth> (deposit wallet)', () async {
      final safe = '0x${'56' * 20}';
      final wire = await signClobAuthPoly1271(
          credentials: key, safeAddress: safe, timestamp: 1700000000, nonce: 7);
      final digest = clobAuthPoly1271TypedData(
              safeAddress: safe, timestamp: 1700000000, nonce: 7)
          .digest;
      expect(sameEvmAddress(recoverSignerAddress(digest, _sig(wire))!, address),
          isTrue);

      final seen = <EvmSigningRequest>[];
      await signClobAuthPoly1271(
          externalSigner: capture(seen),
          safeAddress: safe,
          timestamp: 1700000000,
          nonce: 7);
      expect(seen.single.kind, LedgerActionKind.pmClobAuth);
    });
  });

  group('DepositWallet Batch', () {
    final service = PolymarketOnboardingService();
    const wallet = '0x9aBc000000000000000000000000000000000001';
    DepositWalletCall call(int i) => (
          target: '0x${(i + 1).toRadixString(16).padLeft(2, '0') * 20}',
          value: BigInt.from(i),
          data: i.isEven ? '0x095ea7b3${'00' * 32 * (i + 1)}' : '',
        );

    for (final count in [1, 2, 5]) {
      test('$count call(s)', () {
        final calls = [for (var i = 0; i < count; i++) call(i)];
        final builder = service.debugDepositWalletBatchHashes(
          walletAddress: wallet,
          nonce: BigInt.from(42),
          deadline: BigInt.from(1800000000),
          calls: calls,
        );
        final generic = depositWalletBatchTypedData(
          walletAddress: wallet,
          nonce: BigInt.from(42),
          deadline: BigInt.from(1800000000),
          calls: calls,
        );
        expect(_hex(generic.domainSeparator), _hex(builder.domain));
        expect(_hex(generic.structHash), _hex(builder.message));
      });
    }

    test('external batch signer passes the runtime check', () async {
      final calls = [call(0), call(1)];
      final hashes = service.debugDepositWalletBatchHashes(
        walletAddress: wallet,
        nonce: BigInt.one,
        deadline: BigInt.two,
        calls: calls,
      );
      final seen = <EvmSigningRequest>[];
      final signer = ExternalDepositWalletBatchSigner(capture(seen));
      await signer.signBatch(
        domain: hashes.domain,
        message: hashes.message,
        kind: LedgerActionKind.pmDepositWalletBatch,
        typedData: () => depositWalletBatchTypedData(
          walletAddress: wallet,
          nonce: BigInt.one,
          deadline: BigInt.two,
          calls: calls,
        ),
      );
      expect((seen.single as Eip712Request).data.primaryType, 'Batch');

      // A drifted payload is refused before the signer is called.
      await expectLater(
        signer.signBatch(
          domain: hashes.domain,
          message: hashes.message,
          kind: LedgerActionKind.pmDepositWalletBatch,
          typedData: () => depositWalletBatchTypedData(
            walletAddress: wallet,
            nonce: BigInt.from(2),
            deadline: BigInt.two,
            calls: calls,
          ),
        ),
        throwsA(isA<EvmTypedDataMismatchException>()),
      );
      expect(seen.length, 1);
    });
  });

  test('typed data fixtures stay unmodifiable', () {
    final td = l1ActionTypedData(connectionId: Uint8List(32), isMainnet: true);
    expect(() => td.types['Agent']!.add(const Eip712Field('x', 'uint8')),
        throwsUnsupportedError);
  });
}
