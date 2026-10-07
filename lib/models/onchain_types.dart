import 'dart:convert';

enum Network { bitcoin, testnet, testnet4, signet, regtest }

/// Immutable, process-local snapshots from the native on-chain wallet owner.
/// These objects never contain native pointers or perform wallet operations.
class Amount {
  final int _sats;
  const Amount._(this._sats);

  factory Amount.fromSat({required int sat}) =>
      Amount._(_unsigned(sat, 'amount'));

  int toSat() => _sats;

  @override
  bool operator ==(Object other) => other is Amount && other._sats == _sats;
  @override
  int get hashCode => _sats.hashCode;
}

class Txid {
  final String _hex;
  const Txid._(this._hex);

  factory Txid.fromString({required String hex}) => Txid._(_hash(hex, 'txid'));

  @override
  String toString() => _hex;
  @override
  bool operator ==(Object other) => other is Txid && other._hex == _hex;
  @override
  int get hashCode => _hex.hashCode;
}

class BlockHash {
  final String _hex;
  const BlockHash._(this._hex);
  factory BlockHash.fromString({required String hex}) =>
      BlockHash._(_hash(hex, 'blockHash', allowEmpty: true));
  @override
  String toString() => _hex;
}

class FeeRate {
  final double _satVb;
  const FeeRate._(this._satVb);
  factory FeeRate.fromSatPerVb({required num satVb}) =>
      FeeRate._(_rate(satVb, 'feeRate'));
  double asSatPerVb() => _satVb;
  int asSatPerVbCeil() => _satVb.ceil();
  int asSatPerVbFloor() => _satVb.floor();
}

class Balance {
  final Amount confirmed;
  final Amount trustedPending;
  final Amount untrustedPending;
  final Amount immature;
  final Amount total;
  final Amount spendable;

  const Balance(
      {required this.confirmed,
      required this.trustedPending,
      required this.untrustedPending,
      required this.immature,
      required this.total,
      required this.spendable});

  factory Balance.fromMap(Object? value) {
    final m = _record(value, 'balance');
    final result = Balance(
      confirmed: _amount(m, 'confirmed'),
      trustedPending: _amount(m, 'trustedPending'),
      untrustedPending: _amount(m, 'untrustedPending'),
      immature: _amount(m, 'immature'),
      total: _amount(m, 'total'),
      spendable: _amount(m, 'spendable'),
    );
    if (result.total.toSat() !=
            result.confirmed.toSat() +
                result.trustedPending.toSat() +
                result.untrustedPending.toSat() +
                result.immature.toSat() ||
        result.spendable.toSat() !=
            result.confirmed.toSat() + result.trustedPending.toSat()) {
      throw const FormatException('Invalid on-chain balance totals');
    }
    return result;
  }

  Map<String, Object?> toMap() => {
        'confirmed': confirmed.toSat(),
        'trustedPending': trustedPending.toSat(),
        'untrustedPending': untrustedPending.toSat(),
        'immature': immature.toSat(),
        'total': total.toSat(),
        'spendable': spendable.toSat(),
      };
}

class BlockId {
  final int height;
  final BlockHash hash;
  const BlockId({required this.height, required this.hash});
}

class ConfirmationBlockTime {
  final BlockId blockId;
  final int confirmationTime;
  const ConfirmationBlockTime(
      {required this.blockId, required this.confirmationTime});
}

sealed class ChainPosition {
  const ChainPosition();

  factory ChainPosition.fromMap(Object? value) {
    final m = _record(value, 'chainPosition');
    final height = _optionalInt(m, 'height');
    final time = _optionalInt(m, 'confirmationTime');
    final lastSeen = _optionalInt(m, 'lastSeen');
    final hash = m['blockHash'];
    if (height != null && time != null) {
      if (lastSeen != null) _unsigned(lastSeen, 'lastSeen');
      return ConfirmedChainPosition(
          confirmationBlockTime: ConfirmationBlockTime(
        blockId: BlockId(
            height: _unsigned(height, 'height'),
            hash: BlockHash.fromString(
                hex: hash == null
                    ? ''
                    : _string(hash, 'blockHash', allowEmpty: true))),
        confirmationTime: _unsigned(time, 'confirmationTime'),
      ));
    }
    if (height != null || time != null || (hash != null && hash != '')) {
      throw const FormatException('Invalid on-chain confirmation position');
    }
    return UnconfirmedChainPosition(
        lastSeen: lastSeen == null ? null : _unsigned(lastSeen, 'lastSeen'));
  }

  Map<String, Object?> toMap();
}

class ConfirmedChainPosition extends ChainPosition {
  final ConfirmationBlockTime confirmationBlockTime;
  const ConfirmedChainPosition({required this.confirmationBlockTime});
  @override
  Map<String, Object?> toMap() => {
        'height': confirmationBlockTime.blockId.height,
        'confirmationTime': confirmationBlockTime.confirmationTime,
        'blockHash': confirmationBlockTime.blockId.hash.toString(),
        'lastSeen': null,
      };
}

class UnconfirmedChainPosition extends ChainPosition {
  final int? lastSeen;
  const UnconfirmedChainPosition({this.lastSeen});
  @override
  Map<String, Object?> toMap() => {
        'height': null,
        'confirmationTime': null,
        'blockHash': null,
        'lastSeen': lastSeen,
      };
}

class OutPoint {
  final Txid txid;
  final int vout;
  const OutPoint({required this.txid, required this.vout});
  factory OutPoint.fromMap(Object? value) {
    final m = _record(value, 'outpoint');
    return OutPoint(
        txid: Txid.fromString(hex: _string(m['txid'], 'txid')),
        vout: _unsigned(m['vout'], 'vout', max: 0xffffffff));
  }
  Map<String, Object?> toMap() => {'txid': txid.toString(), 'vout': vout};
  @override
  bool operator ==(Object other) =>
      other is OutPoint && other.txid == txid && other.vout == vout;
  @override
  int get hashCode => Object.hash(txid, vout);
}

class TxOut {
  final Amount value;
  final String scriptPubkey;
  const TxOut({required this.value, required this.scriptPubkey});
  factory TxOut.fromMap(Object? value) {
    final m = _record(value, 'txout');
    return TxOut(
        value: _amount(m, 'value'),
        scriptPubkey:
            _hex(m['scriptPubkey'], 'scriptPubkey', allowEmpty: true));
  }
  Map<String, Object?> toMap() =>
      {'value': value.toSat(), 'scriptPubkey': scriptPubkey};
}

class TxIn {
  final OutPoint previousOutput;
  final int? sequence;
  const TxIn({required this.previousOutput, this.sequence});
  factory TxIn.fromMap(Object? value) {
    final m = _record(value, 'input');
    return TxIn(
        previousOutput: OutPoint.fromMap(m['previousOutput']),
        sequence: m['sequence'] == null
            ? null
            : _unsigned(m['sequence'], 'sequence', max: 0xffffffff));
  }
  Map<String, Object?> toMap() => {
        'previousOutput': previousOutput.toMap(),
        if (sequence != null) 'sequence': sequence
      };
}

enum KeychainKind { external_, internal }

class LocalOutput {
  final OutPoint outpoint;
  final TxOut txout;
  final KeychainKind keychain;
  final bool isSpent;
  final int derivationIndex;
  final ChainPosition chainPosition;
  const LocalOutput(
      {required this.outpoint,
      required this.txout,
      required this.keychain,
      required this.isSpent,
      required this.derivationIndex,
      required this.chainPosition});
  factory LocalOutput.fromMap(Object? value) {
    final m = _record(value, 'utxo');
    final keychain = switch (m['keychain']) {
      'external' => KeychainKind.external_,
      'internal' => KeychainKind.internal,
      _ => throw const FormatException('Invalid on-chain keychain'),
    };
    return LocalOutput(
        outpoint: OutPoint.fromMap(m['outpoint']),
        txout: TxOut.fromMap(m['txout']),
        keychain: keychain,
        isSpent: _bool(m['isSpent'], 'isSpent'),
        derivationIndex:
            _unsigned(m['derivationIndex'], 'derivationIndex', max: 0x7fffffff),
        chainPosition: ChainPosition.fromMap(m['chainPosition']));
  }
  Map<String, Object?> toMap() => {
        'outpoint': outpoint.toMap(),
        'txout': txout.toMap(),
        'keychain':
            keychain == KeychainKind.external_ ? 'external' : 'internal',
        'isSpent': isSpent,
        'derivationIndex': derivationIndex,
        'chainPosition': chainPosition.toMap(),
      };
}

class Address {
  final String _value;
  const Address(this._value);
  @override
  String toString() => _value;
}

class AddressInfo {
  final Address address;
  final int index;
  const AddressInfo({required this.address, required this.index});
  factory AddressInfo.fromMap(Object? value) {
    final m = _record(value, 'address');
    return AddressInfo(
        address: Address(_string(m['address'], 'address')),
        index: _unsigned(m['index'], 'index', max: 0x7fffffff));
  }
  Map<String, Object?> toMap() =>
      {'address': address.toString(), 'index': index};
}

/// Transaction metadata, not a native transaction or a signing capability.
class Transaction {
  final Txid txid;
  final int virtualSize;
  final int inputCount;
  final int outputCount;
  final String rawHex;
  final int? transactionVersion;
  final List<TxIn>? _inputs;
  final List<TxOut>? _outputs;
  Transaction(
      {required this.txid,
      required this.virtualSize,
      required this.inputCount,
      required this.outputCount,
      this.rawHex = '',
      this.transactionVersion,
      List<TxIn>? inputs,
      List<TxOut>? outputs})
      : _inputs = inputs == null ? null : List.unmodifiable(inputs),
        _outputs = outputs == null ? null : List.unmodifiable(outputs);

  factory Transaction.fromMap(Object? value) {
    final m = _record(value, 'tx');
    final inputs = m['inputs'] == null
        ? null
        : _list(m['inputs'], 'inputs').map(TxIn.fromMap).toList();
    final outputs = m['outputs'] == null
        ? null
        : _list(m['outputs'], 'outputs').map(TxOut.fromMap).toList();
    final inputCount = _unsigned(m['inputCount'], 'inputCount', max: 1000000);
    final outputCount =
        _unsigned(m['outputCount'], 'outputCount', max: 1000000);
    if ((inputs != null && inputs.length != inputCount) ||
        (outputs != null && outputs.length != outputCount)) {
      throw const FormatException('Invalid on-chain transaction counts');
    }
    return Transaction(
        txid: Txid.fromString(hex: _string(m['txid'], 'txid')),
        virtualSize: _unsigned(m['vsize'], 'vsize', max: 4000000),
        inputCount: inputCount,
        outputCount: outputCount,
        transactionVersion: _optionalInt(m, 'version'),
        rawHex: m['rawHex'] == null
            ? ''
            : _hex(m['rawHex'], 'rawHex', allowEmpty: true),
        inputs: inputs,
        outputs: outputs);
  }

  int vsize() => virtualSize;
  int version() =>
      transactionVersion ??
      (throw StateError('Transaction version unavailable'));
  Txid computeTxid() => txid;
  bool get hasInputOutputDetails => _inputs != null && _outputs != null;
  List<TxIn> input() => _inputs ?? const [];
  List<TxOut> output() => _outputs ?? const [];
  Map<String, Object?> toMap() => {
        'txid': txid.toString(),
        'vsize': virtualSize,
        'inputCount': inputCount,
        'outputCount': outputCount,
        'rawHex': rawHex,
        if (transactionVersion != null) 'version': transactionVersion,
        if (_inputs != null) 'inputs': _inputs.map((i) => i.toMap()).toList(),
        if (_outputs != null)
          'outputs': _outputs.map((o) => o.toMap()).toList(),
      };
}

class TxDetails {
  final Txid txid;
  final Amount sent;
  final Amount received;
  final Amount? fee;
  final FeeRate? feeRate;
  final int balanceDelta;
  final ChainPosition chainPosition;
  final Transaction tx;
  const TxDetails(
      {required this.txid,
      required this.sent,
      required this.received,
      required this.fee,
      required this.feeRate,
      required this.balanceDelta,
      required this.chainPosition,
      required this.tx});
  factory TxDetails.fromMap(Object? value) {
    final m = _record(value, 'transaction');
    final txid = Txid.fromString(hex: _string(m['txid'], 'txid'));
    final tx = Transaction.fromMap(m['tx']);
    if (tx.txid != txid) {
      throw const FormatException('Invalid on-chain transaction identity');
    }
    final sent = _amount(m, 'sent');
    final received = _amount(m, 'received');
    final delta = _integer(m['balanceDelta'], 'balanceDelta');
    if (delta != received.toSat() - sent.toSat()) {
      throw const FormatException('Invalid on-chain transaction balance delta');
    }
    return TxDetails(
        txid: txid,
        sent: sent,
        received: received,
        fee: m['fee'] == null ? null : _amount(m, 'fee'),
        feeRate: m['feeRate'] == null
            ? null
            : FeeRate._(_rate(m['feeRate'], 'feeRate')),
        balanceDelta: delta,
        chainPosition: ChainPosition.fromMap(m['chainPosition']),
        tx: tx);
  }
  Map<String, Object?> toMap() => {
        'txid': txid.toString(),
        'sent': sent.toSat(),
        'received': received.toSat(),
        'fee': fee?.toSat(),
        'feeRate': feeRate?.asSatPerVb(),
        'balanceDelta': balanceDelta,
        'chainPosition': chainPosition.toMap(),
        'tx': tx.toMap(),
      };
}

class Psbt {
  final String _base64;
  final int? feeSats;
  final Transaction tx;
  final bool? signed;
  const Psbt._(this._base64, this.feeSats, this.tx, this.signed);
  factory Psbt.fromMap(Object? value) {
    final m = _record(value, 'psbt');
    final encoded = _string(m['psbt'], 'psbt');
    try {
      final bytes = base64.decode(encoded);
      if (bytes.length < 5 ||
          bytes[0] != 0x70 ||
          bytes[1] != 0x73 ||
          bytes[2] != 0x62 ||
          bytes[3] != 0x74 ||
          bytes[4] != 0xff) {
        throw const FormatException();
      }
    } on FormatException {
      throw const FormatException('Invalid on-chain PSBT encoding');
    }
    return Psbt._(
        encoded,
        m['feeSats'] == null ? null : _unsigned(m['feeSats'], 'feeSats'),
        Transaction.fromMap(m['tx']),
        m['signed'] == null ? null : _bool(m['signed'], 'signed'));
  }
  String serialize() => _base64;
  int fee() => feeSats ?? (throw StateError('On-chain PSBT fee unavailable'));
  Transaction extractTx() => tx;
  Map<String, Object?> toMap() => {
        'psbt': _base64,
        'feeSats': feeSats,
        'tx': tx.toMap(),
        if (signed != null) 'signed': signed
      };
}

class OnchainSnapshot {
  final Balance balance;
  final List<TxDetails> transactions;
  final List<LocalOutput> utxos;
  OnchainSnapshot(
      {required this.balance,
      required List<TxDetails> transactions,
      required List<LocalOutput> utxos})
      : transactions = List.unmodifiable(transactions),
        utxos = List.unmodifiable(utxos);
  factory OnchainSnapshot.fromMap(Object? value) {
    final m = _record(value, 'snapshot');
    return OnchainSnapshot(
        balance: Balance.fromMap(m['balance']),
        transactions: _list(m['transactions'], 'transactions')
            .map(TxDetails.fromMap)
            .toList(),
        utxos: _list(m['utxos'], 'utxos').map(LocalOutput.fromMap).toList());
  }
  Map<String, Object?> toMap() => {
        'balance': balance.toMap(),
        'transactions': transactions.map((tx) => tx.toMap()).toList(),
        'utxos': utxos.map((u) => u.toMap()).toList()
      };
}

Map<String, Object?> _record(Object? value, String field) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw FormatException('Invalid on-chain $field record');
  }
  return Map<String, Object?>.from(value);
}

List<Object?> _list(Object? value, String field) {
  if (value is! List) throw FormatException('Invalid on-chain $field list');
  return value;
}

String _string(Object? value, String field, {bool allowEmpty = false}) {
  if (value is! String || (!allowEmpty && value.isEmpty)) {
    throw FormatException('Invalid on-chain $field string');
  }
  return value;
}

int _integer(Object? value, String field) {
  if (value is! int ||
      value < -0x7fffffffffffffff ||
      value > 0x7fffffffffffffff) {
    throw FormatException('Invalid on-chain $field integer');
  }
  return value;
}

int _unsigned(Object? value, String field, {int max = 0x7fffffffffffffff}) {
  final result = _integer(value, field);
  if (result < 0 || result > max) {
    throw FormatException('Invalid on-chain $field range');
  }
  return result;
}

Amount _amount(Map<String, Object?> value, String field) =>
    Amount._(_unsigned(value[field], field));

bool _bool(Object? value, String field) {
  if (value is! bool) throw FormatException('Invalid on-chain $field boolean');
  return value;
}

int? _optionalInt(Map<String, Object?> value, String field) =>
    value[field] == null ? null : _integer(value[field], field);

double _rate(Object? value, String field) {
  if (value is! num || !value.isFinite || value < 0) {
    throw FormatException('Invalid on-chain $field rate');
  }
  return value.toDouble();
}

String _hex(Object? value, String field, {bool allowEmpty = false}) {
  final text = _string(value, field, allowEmpty: allowEmpty);
  if (text.length.isOdd || !RegExp(r'^[0-9a-fA-F]*$').hasMatch(text)) {
    throw FormatException('Invalid on-chain $field encoding');
  }
  return text.toLowerCase();
}

String _hash(String value, String field, {bool allowEmpty = false}) {
  final text = _hex(value, field, allowEmpty: allowEmpty);
  if (text.length != 64 && !(allowEmpty && text.isEmpty)) {
    throw FormatException('Invalid on-chain $field length');
  }
  return text;
}
