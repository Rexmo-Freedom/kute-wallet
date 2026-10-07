import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/hardware/evm_signing_request.dart';
import 'package:kute/services/hardware/ledger/ledger_device_session.dart';
import 'package:kute/services/hardware/ledger/ledger_evm_signer.dart';
import 'package:kute/services/hardware/ledger/ledger_failure.dart';
import 'package:kute/services/hardware/signing_clarity.dart';
import 'package:kute/services/hyperliquid/hyperliquid_signing.dart';
import 'package:kute/services/polymarket/deposit_wallet_batch_signer.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show EthPrivateKey;

import '../../../mocks/fake_ledger_eth_device.dart';

const _keyHex =
    '0x0123456789012345678901234567890101234567890123456789012345678901';
final _key = EthPrivateKey.fromHex(_keyHex);
final _address = _key.address.hexEip55;

Matcher _failure(LedgerFailureCode code) =>
    isA<LedgerFailure>().having((f) => f.code, 'code', code);

Eip712Request _transfer({String? signer}) {
  final action = buildUsdClassTransferAction(
      amount: '10.5', toPerp: true, nonce: 1700000000000)
    ..['hyperliquidChain'] = 'Mainnet';
  return Eip712Request(
    userSignedActionTypedData(
      primaryType: usdClassTransferPrimaryType,
      fields: usdClassTransferSignTypes,
      message: action,
      signatureChainId: 42161,
    ),
    signer ?? _address,
    LedgerActionKind.hlUsdClassTransfer,
  );
}

({FakeLedgerEthDevice device, LedgerEvmSigner signer}) _setup({
  String app = 'BOLOS',
  LedgerActionGate? gate,
}) {
  final device = FakeLedgerEthDevice(key: _key, runningApp: app);
  final session = LedgerDeviceSession(
    connection: device.connection,
    appPollInterval: Duration.zero,
    appPollAttempts: 5,
    delay: (_) async {},
  );
  return (
    device: device,
    signer:
        LedgerEvmSigner(session: session, pairedAddress: _address, gate: gate),
  );
}

bool _noHashMode(FakeLedgerEthDevice device) =>
    !device.hashModeRequested &&
    device.frames.every((f) => !(f[1] == 0x0C && f[3] == 0x00));

void main() {
  test('happy path: full EIP-712, verified account, recovered signature',
      () async {
    final s = _setup();
    final steps = <LedgerSignStep>[];
    s.signer.steps.listen(steps.add);
    final request = _transfer();

    final sig = await s.signer.sign(request);
    await Future<void>.delayed(Duration.zero);

    expect(recoverSignerAddress(request.digest, sig), _address.toLowerCase());
    expect(s.device.lastTypedData!.digest, request.digest);
    expect(s.device.prompts, 1);
    expect(_noHashMode(s.device), isTrue);
    expect(steps, [
      LedgerSignStep.openingApp,
      LedgerSignStep.checkingAppVersion,
      LedgerSignStep.checkingAccount,
      LedgerSignStep.sendingPayload,
      LedgerSignStep.awaitingApproval,
      LedgerSignStep.verifyingSignature,
      LedgerSignStep.signed,
    ]);
  });

  test('end to end through signUserSignedAction with chain 0xa4b1', () async {
    final s = _setup();
    final action = buildUsdClassTransferAction(
        amount: '3', toPerp: false, nonce: 1700000000123);
    final sig = await signUserSignedAction(
      externalSigner: s.signer.externalSigner,
      action: action,
      fields: usdClassTransferSignTypes,
      primaryType: usdClassTransferPrimaryType,
      isMainnet: true,
      signatureChainId: 42161,
    );
    expect(action['signatureChainId'], '0xa4b1');
    final digest = userSignedActionDigest(
      primaryType: usdClassTransferPrimaryType,
      fields: usdClassTransferSignTypes,
      message: action,
      signatureChainId: 42161,
    );
    expect(s.device.lastTypedData!.digest, digest);
    expect(s.device.prompts, 1);
    expect(sig.v, anyOf(27, 28));
  });

  test('a DepositWallet batch with chunked calldata round-trips', () async {
    final s = _setup();
    final calls = <DepositWalletCall>[
      (
        target: '0x${'11' * 20}',
        value: BigInt.zero,
        data: '0x095ea7b3${'ab' * 300}',
      ),
      (target: '0x${'22' * 20}', value: BigInt.from(7), data: '0x'),
    ];
    final request = Eip712Request(
      depositWalletBatchTypedData(
        walletAddress: '0x${'33' * 20}',
        nonce: BigInt.from(9),
        deadline: BigInt.from(1800000000),
        calls: calls,
      ),
      _address,
      LedgerActionKind.pmDepositWalletBatch,
    );
    final sig = await s.signer.sign(request);
    expect(recoverSignerAddress(request.digest, sig), _address.toLowerCase());
    expect(s.device.frames.any((f) => f[1] == 0x1C && f[2] == 0x01), isTrue);
  });

  test('rejection on the device (0x6985 and 0x6982)', () async {
    for (final sw in [0x6985, 0x6982]) {
      final s = _setup();
      s.device.signStatus = sw;
      await expectLater(s.signer.sign(_transfer()),
          throwsA(_failure(LedgerFailureCode.rejected)));
      expect(s.device.prompts, 1);
    }
  });

  test('a locked device', () async {
    final s = _setup();
    s.device.statusForEverything = 0x5515;
    await expectLater(s.signer.sign(_transfer()),
        throwsA(_failure(LedgerFailureCode.locked)));
  });

  test('wrong app open, then switch to Ethereum and sign', () async {
    final s = _setup(app: 'Bitcoin');
    final sig = await s.signer.sign(_transfer());
    expect(sig, isNotNull);
    expect(s.device.frames.take(2).map((f) => f[1]), [0x01, 0xA7]);
    expect(s.device.runningApp, 'Ethereum');
  });

  test('an Ethereum app below 1.9.19 is unsupported before any payload',
      () async {
    final s = _setup();
    s.device.ethVersion = [1, 9, 18];
    await expectLater(s.signer.sign(_transfer()),
        throwsA(_failure(LedgerFailureCode.unsupportedAppVersion)));
    expect(s.device.frames.where((f) => f[1] == 0x1A), isEmpty);
    expect(s.device.prompts, 0);
  });

  test('0x6d00 inside the Ethereum app is an unsupported version', () async {
    final s = _setup();
    s.device.definitionStatus = 0x6d00;
    await expectLater(s.signer.sign(_transfer()),
        throwsA(_failure(LedgerFailureCode.unsupportedAppVersion)));
    expect(s.device.prompts, 0);
  });

  test('0x6a84 gives payloadTooLarge', () async {
    final s = _setup();
    s.device.implementationStatus = 0x6a84;
    await expectLater(s.signer.sign(_transfer()),
        throwsA(_failure(LedgerFailureCode.payloadTooLarge)));
  });

  test('a device account that is not the paired address is wrongDevice',
      () async {
    final s = _setup();
    s.device.reportedAddress = '0x${'ab' * 20}';
    await expectLater(s.signer.sign(_transfer()),
        throwsA(_failure(LedgerFailureCode.wrongDevice)));
    expect(s.device.prompts, 0);
    expect(s.device.frames.where((f) => f[1] == 0x1A), isEmpty);
  });

  test('a tampered signature is wrongSigner', () async {
    final s = _setup();
    s.device.tamperSignature = true;
    await expectLater(s.signer.sign(_transfer()),
        throwsA(_failure(LedgerFailureCode.wrongSigner)));
  });

  test('a disconnect after the sign frame is disconnected with no signature',
      () async {
    final s = _setup();
    s.device.disconnectOnSign = true;
    await expectLater(s.signer.sign(_transfer()),
        throwsA(_failure(LedgerFailureCode.disconnected)));
    expect(s.device.prompts, 1);
  });

  test('a double call is busy and prompts once', () async {
    final s = _setup();
    final hold = Completer<void>();
    s.device.holdSign = hold;
    final first = s.signer.sign(_transfer());
    for (var i = 0; i < 100 && s.device.prompts == 0; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(s.device.prompts, 1);
    await expectLater(
        s.signer.sign(_transfer()), throwsA(_failure(LedgerFailureCode.busy)));
    hold.complete();
    await first;
    expect(s.device.prompts, 1);
  });

  test('a blocked kind never reaches the device', () async {
    final s = _setup(
      gate: (kind) =>
          isLedgerActionAllowed(kind, opaqueHyperliquidEnabled: false),
    );
    final request = Eip712Request(
      l1ActionTypedData(connectionId: Uint8List(32), isMainnet: true),
      _address,
      LedgerActionKind.hlOrder,
    );
    await expectLater(
        s.signer.sign(request), throwsA(isA<LedgerActionBlockedException>()));
    expect(s.device.frames, isEmpty);
  });

  test('a request for another address never reaches the device', () async {
    final s = _setup();
    await expectLater(s.signer.sign(_transfer(signer: '0x${'cd' * 20}')),
        throwsA(_failure(LedgerFailureCode.wrongSigner)));
    expect(s.device.frames, isEmpty);
  });

  test('EVM transactions are refused before the device', () async {
    final s = _setup(gate: (_) => true);
    await expectLater(
      s.signer.sign(EvmTransactionRequest(Uint8List.fromList([1, 2, 3]), 137,
          _address, LedgerActionKind.pmWithdrawal)),
      throwsUnsupportedError,
    );
    expect(s.device.frames, isEmpty);
  });

  test('personal messages use E0 08 and never hash mode', () async {
    final s = _setup(gate: (_) => true);
    final message = Uint8List.fromList(utf8.encode('a' * 400));
    final request = PersonalMessageRequest(
        message, _address, LedgerActionKind.personalMessage);
    final sig = await s.signer.sign(request);
    expect(recoverSignerAddress(request.digest, sig), _address.toLowerCase());
    expect(s.device.lastPersonalMessage, message);
    expect(s.device.frames.where((f) => f[1] == 0x08).length, 2);
    expect(_noHashMode(s.device), isTrue);
  });
}
