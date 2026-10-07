import 'dart:convert';
import 'package:kute/models/onchain_types.dart';
import 'package:kute/services/bitcoin/ledger_btc_send_service.dart';
import 'package:kute/services/onchain/native_onchain_service.dart';

/// Reads the one output paying the reviewed destination. A missing or
/// ambiguous output cannot be used to display or authorize a payment.
int reviewedBitcoinRecipientSats(Psbt psbt, String address,
    {bool mainnet = true}) {
  final script = bitcoinScriptPubKeyHex(address, mainnet: mainnet);
  final tx = psbt.extractTx();
  if (script == null || !tx.hasInputOutputDetails) {
    throw const OnchainException('invalid_transaction');
  }
  final outputs = tx
      .output()
      .where(
          (output) => output.scriptPubkey.toLowerCase() == script.toLowerCase())
      .toList();
  if (outputs.length != 1 || outputs.single.value.toSat() <= 0) {
    throw const OnchainException('review_changed');
  }
  return outputs.single.value.toSat();
}

/// Checks the serialized transaction against the summary shown by an external
/// signing screen, including callers that do not have native PSBT metadata.
bool reviewedBitcoinSummaryMatches({
  required String reviewedPsbt,
  required String recipient,
  required int amountSats,
  required bool mainnet,
}) {
  try {
    if (amountSats <= 0) return false;
    final script = bitcoinScriptPubKeyHex(recipient, mainnet: mainnet);
    final unsigned = _unsignedTransaction(base64Decode(reviewedPsbt));
    if (script == null || unsigned == null) return false;
    final transaction = parseRawBitcoinTransaction(_hex(unsigned));
    if (transaction == null) return false;
    final outputs = transaction.outputs
        .where((output) => output.scriptHex == script)
        .toList();
    return outputs.length == 1 && outputs.single.sats == amountSats;
  } catch (_) {
    return false;
  }
}

/// Accepts a signed PSBT or raw transaction only when it preserves every
/// reviewed input, output, amount, sequence, version and locktime.
/// Signatures and witness data may change. Unreadable imports fail closed.
bool signedBitcoinTransactionMatches({
  required String reviewedPsbt,
  required String signedData,
}) {
  try {
    final original = _unsignedTransaction(base64Decode(reviewedPsbt));
    if (original == null) return false;
    final clean = signedData.trim().replaceAll(RegExp(r'\s+'), '');
    final signedBytes = clean.isNotEmpty &&
            clean.length.isEven &&
            RegExp(r'^[0-9a-fA-F]+$').hasMatch(clean)
        ? [
            for (var i = 0; i < clean.length; i += 2)
              int.parse(clean.substring(i, i + 2), radix: 16)
          ]
        : base64Decode(clean);
    final imported =
        _isPsbt(signedBytes) ? _unsignedTransaction(signedBytes) : signedBytes;
    if (imported == null) return false;
    final before = parseRawBitcoinTransaction(_hex(original));
    final after = parseRawBitcoinTransaction(_hex(imported));
    if (before == null ||
        after == null ||
        before.version != after.version ||
        before.lockTime != after.lockTime ||
        before.inputs.length != after.inputs.length ||
        before.outputs.length != after.outputs.length) {
      return false;
    }
    for (var i = 0; i < before.inputs.length; i++) {
      if (before.inputs[i].txid != after.inputs[i].txid ||
          before.inputs[i].vout != after.inputs[i].vout ||
          before.sequences[i] != after.sequences[i]) {
        return false;
      }
    }
    for (var i = 0; i < before.outputs.length; i++) {
      if (before.outputs[i].sats != after.outputs[i].sats ||
          before.outputs[i].scriptHex != after.outputs[i].scriptHex) {
        return false;
      }
    }
    return true;
  } catch (_) {
    return false;
  }
}

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

bool _isPsbt(List<int> bytes) =>
    bytes.length >= 5 &&
    bytes[0] == 0x70 &&
    bytes[1] == 0x73 &&
    bytes[2] == 0x62 &&
    bytes[3] == 0x74 &&
    bytes[4] == 0xff;

List<int>? _unsignedTransaction(List<int> bytes) {
  if (!_isPsbt(bytes)) return null;
  var position = 5;
  int compactSize() {
    if (position >= bytes.length) throw const FormatException();
    final first = bytes[position++];
    if (first < 0xfd) return first;
    final width = first == 0xfd
        ? 2
        : first == 0xfe
            ? 4
            : 8;
    if (position + width > bytes.length) throw const FormatException();
    var value = 0;
    for (var i = 0; i < width; i++) {
      value |= bytes[position++] << (8 * i);
    }
    if (value < 0 || value > bytes.length) throw const FormatException();
    return value;
  }

  List<int>? transaction;
  while (position < bytes.length) {
    final keyLength = compactSize();
    if (keyLength == 0) return transaction;
    if (position + keyLength > bytes.length) return null;
    final unsigned = keyLength == 1 && bytes[position] == 0;
    position += keyLength;
    final valueLength = compactSize();
    if (position + valueLength > bytes.length) return null;
    if (unsigned) {
      if (transaction != null) return null;
      transaction = bytes.sublist(position, position + valueLength);
    }
    position += valueLength;
  }
  return null;
}
