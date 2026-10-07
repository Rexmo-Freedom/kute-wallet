import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/bitcoin/bitcoin_transaction_review.dart';

String _little(int value, int bytes) => [
      for (var i = 0; i < bytes; i++)
        ((value >> (8 * i)) & 255).toRadixString(16).padLeft(2, '0'),
    ].join();

String _raw({
  int amount = 50000,
  String? destination,
  String? previous,
  int sequence = 0xfffffffd,
  int lockTime = 0,
  int version = 2,
  String signatureScript = '',
  bool witness = false,
}) =>
    '${_little(version, 4)}${witness ? '0001' : ''}01'
    '${previous ?? 'cd' * 32}00000000'
    '${_little(signatureScript.length ~/ 2, 1)}$signatureScript'
    '${_little(sequence, 4)}01${_little(amount, 8)}16'
    '0014${destination ?? 'ab' * 20}'
    '${witness ? '010101' : ''}${_little(lockTime, 4)}';

List<int> _bytes(String hex) => [
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ];

String _psbt(String raw) => base64Encode([
      ..._bytes('70736274ff0100'),
      raw.length ~/ 2,
      ..._bytes(raw),
      0,
      0,
      0,
    ]);

void main() {
  final reviewed = _psbt(_raw());

  test('serialized PSBT must pay exactly the displayed recipient and amount',
      () {
    const recipient = 'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4';
    final payment =
        _psbt(_raw(destination: '751e76e8199196d454941c45d1b3a323f1433bd6'));
    expect(
        reviewedBitcoinSummaryMatches(
            reviewedPsbt: payment,
            recipient: recipient,
            amountSats: 50000,
            mainnet: true),
        isTrue);
    for (final summary in [
      (recipient: recipient, amount: 49999),
      (recipient: '1BoatSLRHtKNngkdXEeobR76b53LETtpyT', amount: 50000),
      (recipient: '', amount: 50000),
      (recipient: recipient, amount: 0),
    ]) {
      expect(
          reviewedBitcoinSummaryMatches(
              reviewedPsbt: payment,
              recipient: summary.recipient,
              amountSats: summary.amount,
              mainnet: true),
          isFalse);
    }
  });

  for (final witness in [false, true]) {
    test('accepts matching ${witness ? 'segwit' : 'legacy'} signed raw tx', () {
      final signed =
          _raw(witness: witness, signatureScript: witness ? '' : '0101');
      for (final payload in [signed, base64Encode(_bytes(signed))]) {
        expect(
            signedBitcoinTransactionMatches(
                reviewedPsbt: reviewed, signedData: payload),
            isTrue);
      }
    });
  }

  test('accepts a signed PSBT preserving the reviewed unsigned transaction',
      () {
    expect(
        signedBitcoinTransactionMatches(
            reviewedPsbt: reviewed, signedData: _psbt(_raw())),
        isTrue);
  });

  final attacks = {
    'destination': _raw(destination: 'ef' * 20),
    'amount': _raw(amount: 49999),
    'input': _raw(previous: '12' * 32),
    'sequence': _raw(sequence: 1),
    'locktime': _raw(lockTime: 500000),
    'version': _raw(version: 1),
  };
  for (final attack in attacks.entries) {
    test('rejects changed ${attack.key} in both raw and PSBT imports', () {
      for (final payload in [attack.value, _psbt(attack.value)]) {
        expect(
            signedBitcoinTransactionMatches(
                reviewedPsbt: reviewed, signedData: payload),
            isFalse);
      }
    });
  }

  for (final payload in [
    '',
    '%%%invalid',
    '00',
    'cHNidP8A',
    base64Encode(_bytes('70736274ff0100fdffff00'))
  ]) {
    test('rejects malformed or unverifiable import $payload', () {
      expect(
          signedBitcoinTransactionMatches(
              reviewedPsbt: reviewed, signedData: payload),
          isFalse);
    });
  }

  test('a corrupt reviewed PSBT never authorizes broadcasting', () {
    expect(
        signedBitcoinTransactionMatches(
            reviewedPsbt: 'cHNidP8A', signedData: _raw()),
        isFalse);
  });
}
