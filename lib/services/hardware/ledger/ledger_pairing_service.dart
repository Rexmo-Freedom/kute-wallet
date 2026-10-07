// lib/services/hardware/ledger/ledger_pairing_service.dart
//
// Pairs a Ledger Bitcoin account with the Ethereum address the user
// confirms on the device (Wallet hardening Phase 3, plan B7 and O6).
//
// In one serialized device session:
//   1. Bitcoin app: read the master fingerprint. It must equal the stored
//      `masterFingerprint` when one exists.
//   2. Ethereum app: read the app configuration and enforce the minimum
//      version (O13, floor 1.9.19).
//   3. Get the address WITH display; the user compares and approves on
//      the device. The returned public key must hash to that address.
//   4. Bitcoin app again: the fingerprint must equal the one from step 1.
//      The session only ever reconnects to the same device ID.
//   5. Only then persist the EIP-55 address, path and timestamp.
// Any failure or mismatch writes nothing.
//
// Limits: this is procedural, not a cryptographic proof that both apps
// share one seed. It catches a wrong device or a different passphrase
// during the session. Nothing secret is read or stored.

import 'dart:convert';
import 'dart:typed_data';

import 'package:kute/models/settings_model.dart';
import 'package:kute/services/hardware/evm_signing_request.dart';
import 'package:kute/services/hardware/ledger/eth/eth_address_operation.dart';
import 'package:kute/services/hardware/ledger/eth/eth_apdu_common.dart';
import 'package:kute/services/hardware/ledger/eth/eth_app_config_operation.dart';
import 'package:kute/services/hardware/ledger/ledger_device_session.dart';
import 'package:kute/services/hardware/ledger/ledger_failure.dart';
import 'package:kute/services/hardware/ledger/ledger_os_operations.dart';
import 'package:pointycastle/digests/keccak.dart';
import 'package:web3dart/web3dart.dart' show publicKeyToAddress;

/// Bitcoin app GET_MASTER_FINGERPRINT (E1 05 00 00, no data). Response:
/// the 4-byte fingerprint.
LedgerApdu bitcoinMasterFingerprintApdu() => LedgerApdu(0xE1, 0x05, 0x00, 0x00);

String parseBitcoinFingerprint(Uint8List payload) {
  if (payload.length != 4) {
    throw const FormatException('Unexpected fingerprint length');
  }
  return payload.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

enum LedgerPairingStep {
  openingBitcoinApp,
  checkingFingerprint,
  openingEthereumApp,
  checkingAppVersion,
  awaitingAddressApproval,
  recheckingFingerprint,
  saving,
  done,
}

/// The public identity a successful pairing produces.
class LedgerEvmIdentity {
  const LedgerEvmIdentity({
    required this.walletId,
    required this.address,
    required this.derivationPath,
    required this.verifiedAtMs,
    required this.deviceFingerprint,
  });

  final String walletId;

  /// EIP-55 checksummed.
  final String address;
  final String derivationPath;
  final int verifiedAtMs;

  /// The fingerprint read on the device; returned for display and never
  /// written back to the wallet.
  final String deviceFingerprint;
}

typedef LedgerIdentityPersist = Future<void> Function(
    LedgerEvmIdentity identity);

class LedgerPairingService {
  LedgerPairingService({
    required this.session,
    required LedgerIdentityPersist persist,
    this.minimumAppVersion = kLedgerEthMinimumAppVersion,
    DateTime Function()? clock,
  })  : _persist = persist,
        _clock = clock ?? DateTime.now;

  final LedgerDeviceSession session;
  final LedgerSemver minimumAppVersion;
  final LedgerIdentityPersist _persist;
  final DateTime Function() _clock;

  /// [onAddressPreview] receives the checksummed address read WITHOUT a
  /// device prompt, right before the prompting read, so the screen can
  /// show it while the device asks for approval. The prompting read is
  /// still the one that is checked and stored; a preview that differs
  /// from the approved address fails as `wrongDevice`.
  Future<LedgerEvmIdentity> verifyEthereumIdentity(
    WalletConfig wallet, {
    void Function(LedgerPairingStep step)? onStep,
    void Function(String address)? onAddressPreview,
  }) async {
    if (!wallet.isLedger) {
      throw ArgumentError('Only a Ledger wallet can pair an Ethereum address');
    }
    const path = kLedgerEvmDerivationPath; // O5: index 0 only
    final stored = wallet.masterFingerprint?.trim().toLowerCase();
    final hasStored = stored != null && stored.isNotEmpty;

    final result = await session.run((scope) async {
      Future<String> fingerprint() async =>
          parseBitcoinFingerprint(await scope.send(bitcoinMasterFingerprintApdu()));

      onStep?.call(LedgerPairingStep.openingBitcoinApp);
      await scope.ensureApp(LedgerAppId.bitcoin);
      onStep?.call(LedgerPairingStep.checkingFingerprint);
      final before = await fingerprint();
      if (hasStored && before != stored) {
        throw const LedgerFailure(LedgerFailureCode.wrongDevice);
      }

      onStep?.call(LedgerPairingStep.openingEthereumApp);
      await scope.ensureApp(LedgerAppId.ethereum);
      onStep?.call(LedgerPairingStep.checkingAppVersion);
      final config = parseEthAppConfig(await scope.send(ethAppConfigApdu()));
      if (!config.supports(minimumAppVersion)) {
        throw const LedgerFailure(LedgerFailureCode.unsupportedAppVersion,
            app: LedgerAppId.ethereum);
      }

      // Silent read first so the phone can show the address the device is
      // about to display. Nothing is stored from this read.
      String? preview;
      if (onAddressPreview != null) {
        preview = _checkedAddress(parseEthAddressResponse(
            await scope.send(ethGetAddressApdu(path: path, display: false))));
        onAddressPreview(preview);
      }

      onStep?.call(LedgerPairingStep.awaitingAddressApproval);
      final response = parseEthAddressResponse(await scope.send(
          ethGetAddressApdu(path: path, display: true),
          prompts: true));
      final address = _checkedAddress(response);
      if (preview != null && !sameEvmAddress(preview, address)) {
        throw const LedgerFailure(LedgerFailureCode.wrongDevice);
      }

      onStep?.call(LedgerPairingStep.recheckingFingerprint);
      await scope.ensureApp(LedgerAppId.bitcoin);
      final after = await fingerprint();
      if (after != before) {
        throw const LedgerFailure(LedgerFailureCode.wrongDevice);
      }
      if (scope.connection.device.id != session.deviceId) {
        throw const LedgerFailure(LedgerFailureCode.wrongDevice);
      }
      return (address: address, fingerprint: after);
    });

    final identity = LedgerEvmIdentity(
      walletId: wallet.id,
      address: result.address,
      derivationPath: path,
      verifiedAtMs: _clock().millisecondsSinceEpoch,
      deviceFingerprint: result.fingerprint,
    );
    onStep?.call(LedgerPairingStep.saving);
    await _persist(identity);
    onStep?.call(LedgerPairingStep.done);
    return identity;
  }

  /// The address the device displayed, checksummed, after checking its
  /// public key hashes to it.
  static String _checkedAddress(EthAddressResponse response) {
    final pub = response.publicKey;
    if (pub.length != 65 || pub[0] != 0x04) {
      throw const LedgerFailure(LedgerFailureCode.wrongDevice);
    }
    final derived = publicKeyToAddress(Uint8List.fromList(pub.sublist(1)));
    final derivedHex =
        '0x${derived.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
    if (!sameEvmAddress(derivedHex, response.address)) {
      throw const LedgerFailure(LedgerFailureCode.wrongDevice);
    }
    return toEip55Address(response.address);
  }
}

/// EIP-55 mixed-case checksum encoding of a 0x address.
String toEip55Address(String address) {
  if (!RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(address)) {
    throw ArgumentError('Not a 0x address');
  }
  final lower = address.substring(2).toLowerCase();
  final hash = KeccakDigest(256).process(Uint8List.fromList(ascii.encode(lower)));
  final out = StringBuffer('0x');
  for (var i = 0; i < 40; i++) {
    final nibble = (hash[i ~/ 2] >> (i.isEven ? 4 : 0)) & 0x0f;
    out.write(nibble >= 8 ? lower[i].toUpperCase() : lower[i]);
  }
  return out.toString();
}
