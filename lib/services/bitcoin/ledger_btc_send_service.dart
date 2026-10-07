// lib/services/bitcoin/ledger_btc_send_service.dart
//
// Ledger Bitcoin send for funding routes (Wallet hardening Phase 4,
// P4.10). Copied, not moved, from two places so the live screens stay
// untouched until wiring:
//   - PSBT build: `confirm_send.dart` `_handleHardwareSigning`
//   - Ledger sign and broadcast: `watch_only_screen.dart`
//     `_handleLedgerSigning` and `_onBroadcast`
//
// Differences from the originals, on purpose:
//   - The wallet ID is pinned explicitly. BDK is resolved through
//     `bitcoinModelForWalletProvider(walletId)`, never through
//     `bdkScopeWalletIdProvider` or the active wallet.
//   - Funding sends require a stored master fingerprint. The device
//     fingerprint gate in `LedgerService.signPsbt` then always runs.
//   - The unsigned PSBT must pay the destination exactly once with the
//     exact amount; that output index is the deposit vout.
//   - The raw transaction the Ledger returns is parsed and must spend the
//     same inputs and pay the same outputs as the reviewed PSBT, and its
//     txid is computed locally so a caller can persist it BEFORE the
//     broadcast.
//   - No retry loop. One device prompt per call; a failure is typed.
//
// No private key, mnemonic or phone signer exists on this path.

import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kute/models/bitcoin_model.dart';
import 'package:kute/models/onchain_types.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/wallet_scoped_bitcoin_config_provider.dart';
import 'package:kute/services/background_sync_service.dart';
import 'package:kute/services/hardware/ledger/ledger_failure.dart';
import 'package:kute/services/hardware/ledger/ledger_operation_scope.dart';
import 'package:kute/services/ledger_service.dart';
import 'package:kute/services/security/address_guard.dart';

/// Signs a base64 PSBTv0 on the connected Ledger and returns the signed
/// raw transaction hex. Throws [LedgerFailure] on any device failure.
typedef LedgerPsbtSignFn = Future<String> Function(
  String psbtBase64, {
  required String? scriptType,
  required String expectedFingerprint,
});

/// Displays the receive address at [addressIndex] on the Ledger and
/// returns what the device derived. Throws [LedgerFailure] on failure.
typedef LedgerAddressDisplayFn = Future<String> Function({
  required String? scriptType,
  required int addressIndex,
});

/// BDK model for exactly this wallet ID.
typedef LedgerBitcoinModelResolver = Future<BitcoinModel> Function(
    String walletId);

enum LedgerBtcSendError {
  notLedger('not_ledger'),
  missingFingerprint('missing_fingerprint'),
  walletChanged('wallet_changed'),
  destinationFormat('destination_format'),
  invalidAmount('invalid_amount'),
  depositOutputMissing('deposit_output_missing'),
  psbtDetailsUnavailable('psbt_details_unavailable'),
  feeUnavailable('fee_unavailable'),
  signedTxMismatch('signed_tx_mismatch'),
  addressMismatch('address_mismatch'),

  /// F4: an earlier funding's outcome is unknown and no transaction that
  /// spends one of its inputs could be built. Refused before any prompt.
  mustSpendUnavailable('must_spend_unavailable');

  const LedgerBtcSendError(this.code);

  /// Analytics value. Never carries amounts, addresses or ids.
  final String code;
}

class LedgerBtcSendException implements Exception {
  const LedgerBtcSendException(this.error);

  final LedgerBtcSendError error;

  @override
  String toString() => 'LedgerBtcSendException(${error.code})';
}

/// A receive address of one Ledger wallet that the device displayed and
/// that equals the address the app resolved. Only
/// [LedgerBtcSendService.verifyReceiveAddress] constructs one, so holding
/// it means the check ran for [walletId].
class LedgerVerifiedBtcAddress {
  const LedgerVerifiedBtcAddress._({
    required this.walletId,
    required this.address,
    required this.index,
    required this.verifiedAt,
  });

  final String walletId;
  final String address;
  final int index;
  final DateTime verifiedAt;
}

class LedgerBtcOutput {
  const LedgerBtcOutput(this.sats, this.scriptHex);

  final int sats;

  /// Lowercase hex.
  final String scriptHex;
}

class LedgerBtcOutpoint {
  const LedgerBtcOutpoint(this.txid, this.vout);

  /// Display order (big endian) lowercase hex.
  final String txid;
  final int vout;
}

/// An unsigned PSBT for one Ledger wallet that pays [destination] exactly
/// [amountSats] at output [depositVout].
class LedgerBtcPreparedSend {
  const LedgerBtcPreparedSend._({
    required this.walletId,
    required this.scriptType,
    required this.expectedFingerprint,
    required this.destination,
    required this.amountSats,
    required this.feeSats,
    required this.depositVout,
    required this.psbtBase64,
    required this.inputs,
    required this.outputs,
  });

  final String walletId;
  final String? scriptType;
  final String expectedFingerprint;
  final String destination;
  final int amountSats;
  final int feeSats;
  final int depositVout;
  final String psbtBase64;
  final List<LedgerBtcOutpoint> inputs;
  final List<LedgerBtcOutput> outputs;
}

/// The device-signed raw transaction for a [LedgerBtcPreparedSend]. Not
/// yet broadcast.
class LedgerBtcSignedSend {
  const LedgerBtcSignedSend._({
    required this.prepared,
    required this.rawTxHex,
    required this.txid,
  });

  final LedgerBtcPreparedSend prepared;
  final String rawTxHex;

  /// Computed locally from [rawTxHex] (display order, lowercase).
  final String txid;

  int get vout => prepared.depositVout;
}

class LedgerBtcSendService {
  LedgerBtcSendService({
    required LedgerBitcoinModelResolver modelFor,
    required LedgerPsbtSignFn signPsbt,
    required LedgerAddressDisplayFn displayAddress,
    DateTime Function()? clock,
    void Function(String walletId)? onBroadcast,
  })  : _modelFor = modelFor,
        _signPsbt = signPsbt,
        _displayAddress = displayAddress,
        _clock = clock ?? DateTime.now,
        _onBroadcast = onBroadcast;

  /// Adapter over the app's [LedgerService], which reports failures
  /// through its state instead of throwing. [lastFailure] reads that
  /// state.
  factory LedgerBtcSendService.fromLedgerService({
    required LedgerService ledger,
    required LedgerFailure? Function() lastFailure,
    required LedgerBitcoinModelResolver modelFor,
    void Function(String walletId)? onBroadcast,
  }) {
    LedgerFailure failure() =>
        lastFailure() ?? const LedgerFailure(LedgerFailureCode.unknown);
    return LedgerBtcSendService(
      modelFor: modelFor,
      onBroadcast: onBroadcast,
      signPsbt: (psbt,
          {required scriptType, required expectedFingerprint}) async {
        final raw = await ledger.signPsbt(
          psbt,
          scriptType: scriptType,
          expectedFingerprint: expectedFingerprint,
        );
        if (raw == null || raw.isEmpty) throw failure();
        return raw;
      },
      displayAddress: ({required scriptType, required addressIndex}) async {
        final shown = await ledger.verifyReceiveAddress(
          scriptType: scriptType,
          addressIndex: addressIndex,
        );
        if (shown == null || shown.isEmpty) throw failure();
        return shown;
      },
    );
  }

  final LedgerBitcoinModelResolver _modelFor;
  final LedgerPsbtSignFn _signPsbt;
  final LedgerAddressDisplayFn _displayAddress;
  final DateTime Function() _clock;

  /// Told the wallet id after each successful broadcast, outside the
  /// Ledger operation, so the app can re-scan that wallet: BDK counts an
  /// unconfirmed send only once a sync sees it in the mempool.
  final void Function(String walletId)? _onBroadcast;

  // ─────────────────────────── receive address ───────────────────────────

  /// Shows [address] (index [index]) on the Ledger. The device-derived
  /// address must equal [address]. One device confirmation.
  Future<LedgerVerifiedBtcAddress> verifyReceiveAddress({
    required WalletConfig wallet,
    required String address,
    required int index,
  }) =>
      LedgerOperationScope.run(wallet.id, () async {
    if (!wallet.isLedger) {
      throw const LedgerBtcSendException(LedgerBtcSendError.notLedger);
    }
    final expected = address.trim();
    if (expected.isEmpty || index < 0) {
      throw const LedgerBtcSendException(LedgerBtcSendError.addressMismatch);
    }
    final shown = await _displayAddress(
      scriptType: wallet.scriptType,
      addressIndex: index,
    );
    if (shown.trim().toLowerCase() != expected.toLowerCase()) {
      throw const LedgerBtcSendException(LedgerBtcSendError.addressMismatch);
    }
    return LedgerVerifiedBtcAddress._(
      walletId: wallet.id,
      address: expected,
      index: index,
      verifiedAt: _clock(),
    );
  });

  // ─────────────────────────────── build ────────────────────────────────

  /// Builds the unsigned PSBT for [wallet] paying [destination]. No device
  /// prompt.
  ///
  /// [mustSpendOutpoints] (Phase 5 plan B7, F4) holds one group of
  /// outpoints (`txid:vout`) per earlier funding whose outcome is unknown.
  /// The PSBT must spend at least one outpoint of every group, so the new
  /// transaction and each earlier one conflict and at most one confirms.
  /// When normal coin selection does not already do that, the build is
  /// repeated with the first build's inputs plus one outpoint per missing
  /// group (the native builder then spends exactly those). No build that
  /// conflicts throws [LedgerBtcSendError.mustSpendUnavailable].
  Future<LedgerBtcPreparedSend> prepare({
    required WalletConfig wallet,
    required String destination,
    required int amountSats,
    required double feeRateSatVb,
    List<OutPoint>? selectedUtxos,
    List<List<String>> mustSpendOutpoints = const [],
  }) =>
      LedgerOperationScope.run(wallet.id, () async {
    if (!wallet.isLedger) {
      throw const LedgerBtcSendException(LedgerBtcSendError.notLedger);
    }
    final fingerprint = wallet.masterFingerprint?.trim().toLowerCase() ?? '';
    if (fingerprint.isEmpty) {
      throw const LedgerBtcSendException(
          LedgerBtcSendError.missingFingerprint);
    }
    if (amountSats <= 0) {
      throw const LedgerBtcSendException(LedgerBtcSendError.invalidAmount);
    }

    final model = await _modelFor(wallet.id);
    if (model.config.walletId != wallet.id) {
      throw const LedgerBtcSendException(LedgerBtcSendError.walletChanged);
    }
    final mainnet = model.config.network == Network.bitcoin;
    final to = destination.trim();
    if (formatMatchesChain('bitcoin', to, mainnet: mainnet) !=
        AddressFormatMatch.ok) {
      throw const LedgerBtcSendException(LedgerBtcSendError.destinationFormat);
    }
    final script = bitcoinScriptPubKeyHex(to, mainnet: mainnet);
    if (script == null) {
      throw const LedgerBtcSendException(LedgerBtcSendError.destinationFormat);
    }

    Future<Psbt> build(List<OutPoint>? utxos) =>
        model.buildBitcoinTransaction(TransactionBuilder(
          amountSats,
          to,
          feeRateSatVb,
          selectedUtxos: utxos != null && utxos.isNotEmpty ? utxos : null,
        ));

    final groups = parseMustSpendOutpoints(mustSpendOutpoints);
    var psbt = await build(selectedUtxos);
    if (groups.isNotEmpty) {
      if (!psbt.extractTx().hasInputOutputDetails) {
        throw const LedgerBtcSendException(
            LedgerBtcSendError.psbtDetailsUnavailable);
      }
      if (!spendsEveryGroup(_inputsOf(psbt), groups)) {
        psbt = await _buildConflicting(
          build: build,
          base: [...?selectedUtxos, ..._outPointsOf(psbt)],
          groups: groups,
        );
      }
    }

    // The resolver is keyed by wallet ID, so this cannot follow a scope
    // change; the re-check guards against a resolver that does.
    final after = await _modelFor(wallet.id);
    if (after.config.walletId != wallet.id) {
      throw const LedgerBtcSendException(LedgerBtcSendError.walletChanged);
    }

    final tx = psbt.extractTx();
    if (!tx.hasInputOutputDetails) {
      throw const LedgerBtcSendException(
          LedgerBtcSendError.psbtDetailsUnavailable);
    }
    if (groups.isNotEmpty && !spendsEveryGroup(_inputsOf(psbt), groups)) {
      throw const LedgerBtcSendException(
          LedgerBtcSendError.mustSpendUnavailable);
    }
    final outputs = [
      for (final o in tx.output())
        LedgerBtcOutput(o.value.toSat(), o.scriptPubkey.toLowerCase()),
    ];
    final matches = <int>[
      for (var i = 0; i < outputs.length; i++)
        if (outputs[i].scriptHex == script && outputs[i].sats == amountSats) i,
    ];
    if (matches.length != 1) {
      throw const LedgerBtcSendException(
          LedgerBtcSendError.depositOutputMissing);
    }
    final int fee;
    try {
      fee = psbt.fee();
    } catch (_) {
      throw const LedgerBtcSendException(LedgerBtcSendError.feeUnavailable);
    }

    return LedgerBtcPreparedSend._(
      walletId: wallet.id,
      scriptType: wallet.scriptType,
      expectedFingerprint: fingerprint,
      destination: to,
      amountSats: amountSats,
      feeSats: fee,
      depositVout: matches.single,
      psbtBase64: psbt.serialize(),
      inputs: _inputsOf(psbt),
      outputs: List.unmodifiable(outputs),
    );
  });

  static List<LedgerBtcOutpoint> _inputsOf(Psbt psbt) => [
        for (final i in psbt.extractTx().input())
          LedgerBtcOutpoint(i.previousOutput.txid.toString().toLowerCase(),
              i.previousOutput.vout),
      ];

  static List<OutPoint> _outPointsOf(Psbt psbt) => [
        for (final i in psbt.extractTx().input()) i.previousOutput,
      ];

  /// F4 rebuild: adds one outpoint per group the base selection misses,
  /// trying each outpoint of a group in turn. An outpoint the wallet no
  /// longer holds (already spent) fails to build and the next one is
  /// tried.
  Future<Psbt> _buildConflicting({
    required Future<Psbt> Function(List<OutPoint>? utxos) build,
    required List<OutPoint> base,
    required List<List<LedgerBtcOutpoint>> groups,
  }) async {
    final chosen = <OutPoint>[...base];
    List<LedgerBtcOutpoint> chosenInputs() => [
          for (final o in chosen) LedgerBtcOutpoint(o.txid.toString(), o.vout),
        ];
    Psbt? last;
    for (final group in groups) {
      // Covered by the base selection or by an outpoint added for an
      // earlier group (two unresolved fundings can share an input).
      if (spendsEveryGroup(chosenInputs(), [group])) continue;
      Psbt? built;
      for (final candidate in group) {
        final OutPoint point;
        try {
          point = OutPoint(
              txid: Txid.fromString(hex: candidate.txid), vout: candidate.vout);
        } catch (_) {
          continue;
        }
        if (chosen.contains(point)) continue;
        try {
          built = await build([...chosen, point]);
          chosen.add(point);
          break;
        } catch (_) {
          // Not spendable by this wallet any more; try the next outpoint.
        }
      }
      if (built == null) {
        throw const LedgerBtcSendException(
            LedgerBtcSendError.mustSpendUnavailable);
      }
      last = built;
    }
    if (last == null) {
      throw const LedgerBtcSendException(
          LedgerBtcSendError.mustSpendUnavailable);
    }
    return last;
  }

  // ─────────────────────────────── sign ─────────────────────────────────

  /// One Ledger prompt: the device shows the outputs, amounts and fee. The
  /// fingerprint gate runs before the PSBT reaches the device. Nothing is
  /// broadcast.
  Future<LedgerBtcSignedSend> sign(LedgerBtcPreparedSend prepared) =>
      LedgerOperationScope.run(prepared.walletId, () async {
    final raw = await _signPsbt(
      prepared.psbtBase64,
      scriptType: prepared.scriptType,
      expectedFingerprint: prepared.expectedFingerprint,
    );
    final parsed = parseRawBitcoinTransaction(raw);
    if (parsed == null || !_samePayment(prepared, parsed)) {
      throw const LedgerBtcSendException(LedgerBtcSendError.signedTxMismatch);
    }
    return LedgerBtcSignedSend._(
      prepared: prepared,
      rawTxHex: raw.trim().toLowerCase(),
      txid: parsed.txid,
    );
  });

  static bool _samePayment(
      LedgerBtcPreparedSend prepared, ParsedBitcoinTransaction signed) {
    if (prepared.inputs.length != signed.inputs.length ||
        prepared.outputs.length != signed.outputs.length) {
      return false;
    }
    for (var i = 0; i < prepared.inputs.length; i++) {
      if (prepared.inputs[i].txid != signed.inputs[i].txid ||
          prepared.inputs[i].vout != signed.inputs[i].vout) {
        return false;
      }
    }
    for (var i = 0; i < prepared.outputs.length; i++) {
      if (prepared.outputs[i].sats != signed.outputs[i].sats ||
          prepared.outputs[i].scriptHex != signed.outputs[i].scriptHex) {
        return false;
      }
    }
    return true;
  }

  // ───────────────────────────── broadcast ──────────────────────────────

  /// Broadcasts through the pinned wallet's BDK session and returns the
  /// txid the node reported. Callers persist their operation before this.
  Future<String> broadcast(LedgerBtcSignedSend signed) async {
    final walletId = signed.prepared.walletId;
    final txid = await LedgerOperationScope.run(walletId, () async {
      final model = await _modelFor(walletId);
      if (model.config.walletId != walletId) {
        throw const LedgerBtcSendException(LedgerBtcSendError.walletChanged);
      }
      final txid = await model.broadcastSignedTransaction(signed.rawTxHex);
      return txid.trim().toLowerCase();
    });
    try {
      _onBroadcast?.call(walletId);
    } catch (_) {
      // Display refresh only; the broadcast stands.
    }
    return txid;
  }
}

/// App wiring: the global Ledger service and the wallet-ID-keyed BDK
/// model. Never the active or scoped wallet.
final ledgerBtcSendServiceProvider = Provider<LedgerBtcSendService>((ref) {
  return LedgerBtcSendService.fromLedgerService(
    ledger: ref.read(ledgerServiceProvider.notifier),
    lastFailure: () => ref.read(ledgerServiceProvider).failure,
    modelFor: (walletId) =>
        ref.read(bitcoinModelForWalletProvider(walletId).future),
    onBroadcast: (walletId) => unawaited(BackgroundSyncService()
        .scanBdkScope(source: 'ledger_send', walletId: walletId)
        .catchError((_) {})),
  );
});

// ─────────────────────────── F4 outpoints ───────────────────────────────

/// Parses `txid:vout` groups. Malformed entries and empty groups are
/// dropped.
List<List<LedgerBtcOutpoint>> parseMustSpendOutpoints(
    List<List<String>> groups) {
  final out = <List<LedgerBtcOutpoint>>[];
  for (final group in groups) {
    final parsed = <LedgerBtcOutpoint>[];
    for (final entry in group) {
      final at = entry.lastIndexOf(':');
      if (at <= 0) continue;
      final txid = entry.substring(0, at).trim().toLowerCase();
      final vout = int.tryParse(entry.substring(at + 1).trim());
      if (vout == null ||
          vout < 0 ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(txid)) {
        continue;
      }
      parsed.add(LedgerBtcOutpoint(txid, vout));
    }
    if (parsed.isNotEmpty) out.add(parsed);
  }
  return out;
}

/// Whether [inputs] spend at least one outpoint of every group.
bool spendsEveryGroup(
    List<LedgerBtcOutpoint> inputs, List<List<LedgerBtcOutpoint>> groups) {
  bool spent(LedgerBtcOutpoint o) => inputs.any(
      (i) => i.txid.toLowerCase() == o.txid.toLowerCase() && i.vout == o.vout);
  return groups.every((group) => group.any(spent));
}

// ─────────────────────────── raw transaction ────────────────────────────

class ParsedBitcoinTransaction {
  const ParsedBitcoinTransaction({
    required this.txid,
    required this.inputs,
    required this.outputs,
    required this.version,
    required this.lockTime,
    required this.sequences,
  });

  final String txid;
  final List<LedgerBtcOutpoint> inputs;
  final List<LedgerBtcOutput> outputs;
  final int version;
  final int lockTime;
  final List<int> sequences;
}

Uint8List? _hexBytes(String input) {
  final clean = input.trim();
  if (clean.isEmpty ||
      clean.length.isOdd ||
      !RegExp(r'^[0-9a-fA-F]+$').hasMatch(clean)) {
    return null;
  }
  final out = Uint8List(clean.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String _toHex(List<int> bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

/// Parses a serialized Bitcoin transaction (legacy or segwit). Returns null
/// on any malformed input. The txid is computed from the non-witness
/// serialization.
ParsedBitcoinTransaction? parseRawBitcoinTransaction(String rawHex) {
  final bytes = _hexBytes(rawHex);
  if (bytes == null || bytes.length < 10) return null;
  var pos = 0;

  int? readVarInt() {
    if (pos >= bytes.length) return null;
    final first = bytes[pos++];
    int width;
    if (first < 0xfd) return first;
    if (first == 0xfd) {
      width = 2;
    } else if (first == 0xfe) {
      width = 4;
    } else {
      width = 8;
    }
    if (pos + width > bytes.length) return null;
    var value = 0;
    for (var i = 0; i < width; i++) {
      value |= bytes[pos + i] << (8 * i);
    }
    pos += width;
    return value;
  }

  bool skip(int n) {
    if (n < 0 || pos + n > bytes.length) return false;
    pos += n;
    return true;
  }

  try {
    if (!skip(4)) return null; // version
    var segwit = false;
    if (pos + 1 < bytes.length && bytes[pos] == 0x00 && bytes[pos + 1] == 0x01) {
      segwit = true;
      pos += 2;
    }
    final bodyStart = pos;
    final inCount = readVarInt();
    if (inCount == null || inCount == 0 || inCount > 100000) return null;
    final inputs = <LedgerBtcOutpoint>[];
    final sequences = <int>[];
    for (var i = 0; i < inCount; i++) {
      if (pos + 36 > bytes.length) return null;
      final txidLe = bytes.sublist(pos, pos + 32);
      final vout = bytes[pos + 32] |
          (bytes[pos + 33] << 8) |
          (bytes[pos + 34] << 16) |
          (bytes[pos + 35] << 24);
      pos += 36;
      final scriptLen = readVarInt();
      if (scriptLen == null || !skip(scriptLen) || pos + 4 > bytes.length) {
        return null;
      }
      sequences.add(ByteData.sublistView(bytes, pos, pos + 4)
          .getUint32(0, Endian.little));
      pos += 4;
      inputs.add(LedgerBtcOutpoint(_toHex(txidLe.reversed.toList()), vout));
    }
    final outCount = readVarInt();
    if (outCount == null || outCount == 0 || outCount > 100000) return null;
    final outputs = <LedgerBtcOutput>[];
    for (var i = 0; i < outCount; i++) {
      if (pos + 8 > bytes.length) return null;
      var value = 0;
      for (var b = 0; b < 8; b++) {
        value |= bytes[pos + b] << (8 * b);
      }
      pos += 8;
      final scriptLen = readVarInt();
      if (scriptLen == null || pos + scriptLen > bytes.length) return null;
      outputs.add(
          LedgerBtcOutput(value, _toHex(bytes.sublist(pos, pos + scriptLen))));
      pos += scriptLen;
    }
    final bodyEnd = pos;
    if (segwit) {
      for (var i = 0; i < inCount; i++) {
        final items = readVarInt();
        if (items == null) return null;
        for (var j = 0; j < items; j++) {
          final len = readVarInt();
          if (len == null || !skip(len)) return null;
        }
      }
    }
    if (pos + 4 != bytes.length) return null; // locktime, then the end
    final stripped = <int>[
      ...bytes.sublist(0, 4),
      ...bytes.sublist(bodyStart, bodyEnd),
      ...bytes.sublist(pos, pos + 4),
    ];
    final hash = sha256.convert(sha256.convert(stripped).bytes).bytes;
    return ParsedBitcoinTransaction(
      txid: _toHex(hash.reversed.toList()),
      inputs: List.unmodifiable(inputs),
      outputs: List.unmodifiable(outputs),
      version: ByteData.sublistView(bytes, 0, 4).getUint32(0, Endian.little),
      lockTime: ByteData.sublistView(bytes, pos, pos + 4)
          .getUint32(0, Endian.little),
      sequences: List.unmodifiable(sequences),
    );
  } catch (_) {
    return null;
  }
}

// ──────────────────────────── scriptPubKey ──────────────────────────────

List<int>? _convertBits(List<int> data, int from, int to) {
  var acc = 0;
  var bits = 0;
  final out = <int>[];
  final maxV = (1 << to) - 1;
  for (final v in data) {
    if (v < 0 || (v >> from) != 0) return null;
    acc = (acc << from) | v;
    bits += from;
    while (bits >= to) {
      bits -= to;
      out.add((acc >> bits) & maxV);
    }
  }
  if (bits >= from || ((acc << (to - bits)) & maxV) != 0) return null;
  return out;
}

const String _base58Alphabet =
    '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

List<int>? _base58CheckPayload(String input) {
  if (input.isEmpty) return null;
  var value = BigInt.zero;
  final radix = BigInt.from(58);
  for (final ch in input.split('')) {
    final digit = _base58Alphabet.indexOf(ch);
    if (digit < 0) return null;
    value = value * radix + BigInt.from(digit);
  }
  final body = <int>[];
  while (value > BigInt.zero) {
    body.add((value & BigInt.from(0xff)).toInt());
    value = value >> 8;
  }
  var zeros = 0;
  while (zeros < input.length && input[zeros] == '1') {
    zeros++;
  }
  final raw = [...List.filled(zeros, 0), ...body.reversed];
  if (raw.length < 5) return null;
  final payload = raw.sublist(0, raw.length - 4);
  final check = sha256.convert(sha256.convert(payload).bytes).bytes;
  for (var i = 0; i < 4; i++) {
    if (raw[raw.length - 4 + i] != check[i]) return null;
  }
  return payload;
}

/// Lowercase hex scriptPubKey for a Bitcoin address, or null when the
/// address is malformed or on the wrong network.
String? bitcoinScriptPubKeyHex(String address, {required bool mainnet}) {
  final a = address.trim();
  if (formatMatchesChain('bitcoin', a, mainnet: mainnet) !=
      AddressFormatMatch.ok) {
    return null;
  }
  final segwit = decodeBech32(a);
  if (segwit != null) {
    if (segwit.data.isEmpty) return null;
    final version = segwit.data.first;
    final program = _convertBits(segwit.data.sublist(1), 5, 8);
    if (program == null || program.length < 2 || program.length > 40) {
      return null;
    }
    final op = version == 0 ? 0x00 : 0x50 + version;
    return _toHex([op, program.length, ...program]);
  }
  final payload = _base58CheckPayload(a);
  if (payload == null || payload.length != 21) return null;
  final hash = payload.sublist(1);
  switch (payload.first) {
    case 0x00:
    case 0x6f:
      return _toHex([0x76, 0xa9, 0x14, ...hash, 0x88, 0xac]);
    case 0x05:
    case 0xc4:
      return _toHex([0xa9, 0x14, ...hash, 0x87]);
    default:
      return null;
  }
}
