import 'package:flutter_test/flutter_test.dart';
import 'package:kute/models/onchain_types.dart';

final _txid = 'a' * 64;
final _blockHash = 'b' * 64;

Map<String, Object?> _position({bool confirmed = true}) => {
      'height': confirmed ? 900000 : null,
      'confirmationTime': confirmed ? 1750000000 : null,
      'blockHash': confirmed ? _blockHash : null,
      'lastSeen': confirmed ? null : 1750000001,
    };

Map<String, Object?> _summary() => {
      'txid': _txid,
      'vsize': 141,
      'inputCount': 1,
      'outputCount': 2,
      'rawHex': '',
      'inputs': [
        {
          'previousOutput': {'txid': 'c' * 64, 'vout': 3}
        },
      ],
      'outputs': [
        {'value': 4000, 'scriptPubkey': '0014${'ab' * 20}'},
        {'value': 5000, 'scriptPubkey': '0014${'cd' * 20}'},
      ],
    };

Map<String, Object?> _transaction() => {
      'txid': _txid,
      'sent': 10000,
      'received': 5000,
      'fee': 1000,
      'feeRate': 1000 / 141,
      'balanceDelta': -5000,
      'chainPosition': _position(),
      'tx': _summary(),
    };

Map<String, Object?> _utxo() => {
      'outpoint': {'txid': _txid, 'vout': 1},
      'txout': {'value': 5000, 'scriptPubkey': '0014${'cd' * 20}'},
      'keychain': 'internal',
      'isSpent': false,
      'derivationIndex': 18,
      'chainPosition': _position(),
    };

Map<String, Object?> _balance() => {
      'confirmed': 5000,
      'trustedPending': 100,
      'untrustedPending': 200,
      'immature': 300,
      'total': 5600,
      'spendable': 5100,
    };

Map<String, Object?> _snapshot() => {
      'balance': _balance(),
      'transactions': [_transaction()],
      'utxos': [_utxo()],
    };

void main() {
  group('native on-chain snapshots', () {
    test('preserves exact sats, confirmed history and coin-control identity',
        () {
      final snapshot = OnchainSnapshot.fromMap(_snapshot());
      expect(snapshot.balance.total.toSat(), 5600);
      expect(snapshot.balance.spendable.toSat(), 5100);
      final tx = snapshot.transactions.single;
      expect(tx.txid.toString(), _txid);
      expect(tx.balanceDelta, -5000);
      expect(tx.fee!.toSat(), 1000);
      final position = tx.chainPosition as ConfirmedChainPosition;
      expect(position.confirmationBlockTime.blockId.height, 900000);
      expect(
          position.confirmationBlockTime.blockId.hash.toString(), _blockHash);
      expect(position.confirmationBlockTime.confirmationTime, 1750000000);
      final coin = snapshot.utxos.single;
      expect(coin.outpoint, OutPoint.fromMap({'txid': _txid, 'vout': 1}));
      expect(coin.txout.value.toSat(), 5000);
      expect(coin.keychain, KeychainKind.internal);
      expect(coin.derivationIndex, 18);
      expect(
          OnchainSnapshot.fromMap(snapshot.toMap()).toMap(), snapshot.toMap());
    });

    test('keeps full transaction flow data and freezes collection contents',
        () {
      final source = _snapshot();
      final snapshot = OnchainSnapshot.fromMap(source);
      final tx = snapshot.transactions.single.tx;
      expect(tx.hasInputOutputDetails, isTrue);
      expect(tx.input().single.previousOutput.vout, 3);
      expect(tx.output().map((o) => o.value.toSat()), [4000, 5000]);
      expect(tx.inputCount, 1);
      expect(tx.outputCount, 2);
      expect(tx.vsize(), 141);
      (source['transactions'] as List).clear();
      expect(snapshot.transactions, hasLength(1));
      expect(() => snapshot.transactions.clear(), throwsUnsupportedError);
      expect(() => snapshot.utxos.clear(), throwsUnsupportedError);
      expect(() => tx.input().clear(), throwsUnsupportedError);
      expect(() => tx.output().clear(), throwsUnsupportedError);
    });

    test(
        'count-only summary does not invent transaction inputs or output values',
        () {
      final data = _summary()
        ..remove('inputs')
        ..remove('outputs');
      final tx = Transaction.fromMap(data);
      expect(tx.hasInputOutputDetails, isFalse);
      expect(tx.inputCount, 1);
      expect(tx.outputCount, 2);
      expect(tx.input(), isEmpty);
      expect(tx.output(), isEmpty);
    });

    test('represents unconfirmed and unknown-fee data without fabricated zeros',
        () {
      final tx = TxDetails.fromMap(_transaction()
        ..['chainPosition'] = _position(confirmed: false)
        ..['fee'] = null
        ..['feeRate'] = null);
      expect(tx.fee, isNull);
      expect(tx.feeRate, isNull);
      expect(
          (tx.chainPosition as UnconfirmedChainPosition).lastSeen, 1750000001);
    });

    test('rejects missing snapshot sections instead of an empty wallet', () {
      for (final key in ['balance', 'transactions', 'utxos']) {
        expect(() => OnchainSnapshot.fromMap(_snapshot()..remove(key)),
            throwsFormatException);
      }
      expect(() => OnchainSnapshot.fromMap(null), throwsFormatException);
      expect(
          () => OnchainSnapshot.fromMap({'balance': 0}), throwsFormatException);
    });

    test('rejects wrong scalar types, negative sats and inconsistent balances',
        () {
      for (final bad in <Object?>['5000', 5000.0, -1, null, true]) {
        expect(() => Balance.fromMap(_balance()..['confirmed'] = bad),
            throwsFormatException);
      }
      expect(() => Balance.fromMap(_balance()..['total'] = 0),
          throwsFormatException);
      expect(() => Balance.fromMap(_balance()..['spendable'] = 999999),
          throwsFormatException);
    });

    test('rejects partial or malformed confirmations', () {
      expect(() => ChainPosition.fromMap(_position()..['height'] = null),
          throwsFormatException);
      expect(
          () => ChainPosition.fromMap(_position()..['confirmationTime'] = -1),
          throwsFormatException);
      expect(() => ChainPosition.fromMap(_position()..['blockHash'] = 'oops'),
          throwsFormatException);
      expect(
          () => ChainPosition.fromMap(
              _position(confirmed: false)..['blockHash'] = _blockHash),
          throwsFormatException);
    });

    test('rejects mismatched tx identities, counters and nonfinite fee rates',
        () {
      expect(() => TxDetails.fromMap(_transaction()..['txid'] = 'd' * 64),
          throwsFormatException);
      expect(() => TxDetails.fromMap(_transaction()..['balanceDelta'] = 5000),
          throwsFormatException);
      expect(() => Transaction.fromMap(_summary()..['inputCount'] = 2),
          throwsFormatException);
      for (final rate in [double.nan, double.infinity, -1]) {
        expect(() => TxDetails.fromMap(_transaction()..['feeRate'] = rate),
            throwsFormatException);
      }
    });

    test('rejects invalid outpoints, script hex and keychain categories', () {
      expect(() => OutPoint.fromMap({'txid': 'a', 'vout': 0}),
          throwsFormatException);
      expect(() => OutPoint.fromMap({'txid': _txid, 'vout': -1}),
          throwsFormatException);
      expect(() => OutPoint.fromMap({'txid': _txid, 'vout': 0x100000000}),
          throwsFormatException);
      expect(() => TxOut.fromMap({'value': 1, 'scriptPubkey': 'a'}),
          throwsFormatException);
      expect(() => LocalOutput.fromMap(_utxo()..['keychain'] = 'other'),
          throwsFormatException);
      expect(() => LocalOutput.fromMap(_utxo()..['isSpent'] = 0),
          throwsFormatException);
    });

    test('does not expose response values in parse errors', () {
      const sensitiveValue = 'do-not-include-wallet-data';
      try {
        TxDetails.fromMap(_transaction()..['txid'] = sensitiveValue);
        fail('Expected malformed response rejection');
      } on FormatException catch (error) {
        expect(error.toString(), isNot(contains(sensitiveValue)));
      }
    });
  });

  group('native PSBT results', () {
    Map<String, Object?> result() => {
          'psbt': 'cHNidP8A',
          'feeSats': 1000,
          'tx': _summary(),
          'signed': false,
        };

    test('retains serialized PSBT and actual fee with transaction metadata',
        () {
      final psbt = Psbt.fromMap(result());
      expect(psbt.serialize(), 'cHNidP8A');
      expect(psbt.fee(), 1000);
      expect(psbt.signed, isFalse);
      expect(psbt.extractTx().computeTxid().toString(), _txid);
      expect(Psbt.fromMap(psbt.toMap()).serialize(), psbt.serialize());
    });

    test(
        'missing fee stays unknown and cannot be mistaken for a free transaction',
        () {
      final psbt = Psbt.fromMap(result()..['feeSats'] = null);
      expect(psbt.feeSats, isNull);
      expect(psbt.fee, throwsStateError);
    });

    test('rejects malformed base64, missing PSBT magic and invalid sign status',
        () {
      for (final malformed in ['not base64', 'aGVsbG8=', '']) {
        expect(() => Psbt.fromMap(result()..['psbt'] = malformed),
            throwsFormatException);
      }
      expect(() => Psbt.fromMap(result()..['signed'] = 'true'),
          throwsFormatException);
    });
  });
}
