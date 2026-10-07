import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/hardware/evm_signer.dart';
import 'package:kute/services/hardware/evm_signing_request.dart';
import 'package:kute/services/hardware/ledger/ledger_failure.dart';
import 'package:kute/services/hardware/signing_clarity.dart';
import 'package:kute/services/hyperliquid/hyperliquid_signing.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart';

void main() {
  final key = EthPrivateKey.fromHex('01'.padLeft(64, '0'));
  final other = EthPrivateKey.fromHex('02'.padLeft(64, '0'));

  Map<String, dynamic> withdraw([String amount = '10']) => {
        ...buildWithdraw3Action(
            destination: key.address.hexEip55, amount: amount, time: 1234),
        'hyperliquidChain': 'Mainnet',
      };

  test('rejects ambiguous and missing signing authority', () async {
    final domain = Uint8List(32);
    final message = Uint8List(32);
    await expectLater(
        signTypedDataHashes(
            domain: domain, message: message, kind: LedgerActionKind.hlWithdraw3),
        throwsStateError);
    await expectLater(
        signTypedDataHashes(
          domain: domain,
          message: message,
          kind: LedgerActionKind.hlWithdraw3,
          credentials: key,
          externalSigner: EvmExternalSigner(
              address: key.address.hexEip55,
              sign: (r) => key.signToSignature(r.digest)),
        ),
        throwsStateError);
  });

  test('an external signer without full typed data is refused', () async {
    var prompts = 0;
    final hashes = userSignedActionHashes(
        primaryType: withdrawPrimaryType,
        fields: withdrawSignTypes,
        message: withdraw());
    await expectLater(
      signTypedDataHashes(
        domain: hashes.domain,
        message: hashes.message,
        kind: LedgerActionKind.hlWithdraw3,
        externalSigner: EvmExternalSigner(
            address: key.address.hexEip55,
            sign: (r) {
              prompts++;
              return key.signToSignature(r.digest);
            }),
      ),
      throwsStateError,
    );
    expect(prompts, 0);
  });

  test('a digest mismatch throws before the signer is called', () async {
    var prompts = 0;
    final hashes = userSignedActionHashes(
        primaryType: withdrawPrimaryType,
        fields: withdrawSignTypes,
        message: withdraw('10'));
    await expectLater(
      signTypedDataHashes(
        domain: hashes.domain,
        message: hashes.message,
        kind: LedgerActionKind.hlWithdraw3,
        typedData: () => userSignedActionTypedData(
            primaryType: withdrawPrimaryType,
            fields: withdrawSignTypes,
            message: withdraw('11')),
        externalSigner: EvmExternalSigner(
            address: key.address.hexEip55,
            sign: (r) {
              prompts++;
              return key.signToSignature(r.digest);
            }),
      ),
      throwsA(isA<EvmTypedDataMismatchException>()),
    );
    expect(prompts, 0);
  });

  test('a signature that recovers to another address is wrongSigner',
      () async {
    await expectLater(
      signUserSignedAction(
        action: buildWithdraw3Action(
            destination: key.address.hexEip55, amount: '10', time: 1234),
        fields: withdrawSignTypes,
        primaryType: withdrawPrimaryType,
        isMainnet: true,
        externalSigner: EvmExternalSigner(
            address: key.address.hexEip55,
            sign: (r) => other.signToSignature(r.digest)),
      ),
      throwsA(isA<LedgerFailure>()
          .having((f) => f.code, 'code', LedgerFailureCode.wrongSigner)),
    );
  });

  test('hardware receives full typed data for the Hyperliquid owner action',
      () async {
    final seen = <EvmSigningRequest>[];
    final action = buildWithdraw3Action(
        destination: key.address.hexEip55, amount: '10', time: 1234);
    final signature = await signUserSignedAction(
        action: action,
        fields: withdrawSignTypes,
        primaryType: withdrawPrimaryType,
        isMainnet: true,
        externalSigner: EvmExternalSigner(
            address: key.address.hexEip55,
            sign: (request) {
              seen.add(request);
              return key.signToSignature(request.digest);
            }));
    final request = seen.single as Eip712Request;
    expect(request.kind, LedgerActionKind.hlWithdraw3);
    expect(request.expectedSigner, key.address.hexEip55);
    expect(
        request.data.digest,
        userSignedActionDigest(
            primaryType: withdrawPrimaryType,
            fields: withdrawSignTypes,
            message: action));
    final expected = await signUserSignedAction(
        credentials: key,
        action: Map.of(action),
        fields: withdrawSignTypes,
        primaryType: withdrawPrimaryType,
        isMainnet: true);
    expect(signature.toJson(), expected.toJson());
  });

  test('hardware denial propagates with no software key fallback', () async {
    var prompts = 0;
    await expectLater(
        signL1Action(
            action: buildCancelAction([(assetId: 0, oid: 1)]),
            nonce: 1234,
            isMainnet: true,
            externalSigner: EvmExternalSigner(
                address: key.address.hexEip55,
                sign: (request) async {
                  prompts++;
                  expect(request.kind, LedgerActionKind.hlCancel);
                  throw const LedgerFailure(LedgerFailureCode.rejected);
                })),
        throwsA(isA<LedgerFailure>()
            .having((f) => f.code, 'code', LedgerFailureCode.rejected)));
    expect(prompts, 1);
  });
}
