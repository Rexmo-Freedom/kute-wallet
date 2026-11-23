/// Pure-Dart BC-UR (single and multi-part, fountain-coded) that runs on
/// web. A port of the parts of `bc_ur_dart` 0.1.29's `UR` the app uses
/// (lib/src/ur.dart, fragment.dart, byte_words.dart, crc32.dart), with
/// Xoshiro256** done on [BigInt] so it needs no 64-bit integers. Frames
/// are the same as `bc_ur_dart` produces and accepts. See ur.dart.
library;

import 'dart:math' show max, min;
import 'dart:typed_data';

import 'package:cbor/cbor.dart';
import 'package:crypto/crypto.dart' as crypto;

class UR {
  String _type = '';
  String get type => _type;

  Uint8List _payload = Uint8List(0);
  Uint8List get payload => _payload;

  final _Seq _seq = _Seq(0, 0);

  bool get isComplete => _payload.isNotEmpty;

  /// Min and max fragment length for [next].
  int minLength;
  int maxLength;

  int _expectedMessageLength = 0;
  int _expectedChecksum = 0;
  int _expectedFragmentLength = 0;
  int _seqNum = 0;

  final List<int> _expectedPartIndexes = [];
  List<int> get expectedPartIndexes => _expectedPartIndexes;

  final List<int> _receivedPartIndexes = [];
  List<int> get receivedPartIndexes => _receivedPartIndexes;

  final List<_Fragment> _mixedParts = [];
  final List<_Fragment> _queuedParts = [];
  final List<_Fragment> _simpleParts = [];
  final List<Uint8List> _fragments = [];

  UR({String type = '', Uint8List? payload, this.minLength = 10, this.maxLength = 100}) {
    _type = type;
    _payload = payload ?? Uint8List(0);
  }

  /// The whole payload as one UR string.
  String encode() => 'ur:$type/${_ByteWords.encode(payload)}'.toUpperCase();

  /// The next animated frame. A payload that fits in [maxLength] returns
  /// [encode]; a longer one returns fountain-coded fragments.
  String next() {
    if (_fragments.isEmpty) _partition();
    if (_fragments.length <= 1) return encode();

    _seqNum = (_seqNum % _Fragment.maxUint32) + 1;
    final crc = _crc32(payload);
    final indexes = _chooseFragments(_seqNum, _fragments.length, crc);
    var mixed = List<int>.filled(_fragments.first.length, 0);
    for (final i in indexes) {
      mixed = _xor(_fragments[i], mixed);
    }
    final fragment = _Fragment(
      type: type,
      seq: _Seq(_seqNum, _fragments.length),
      messageLength: payload.length,
      checksum: crc,
      part: Uint8List.fromList(mixed),
      indexes: indexes,
    );
    return fragment.encode();
  }

  /// Reads one scanned frame. Returns true once the payload is complete.
  bool read(String value) {
    if (isComplete) return false;

    final _Decoded ur;
    try {
      ur = _Decoded.parse(value);
    } on FormatException {
      return false;
    }

    if (!ur.seq.isFragment) {
      if (_type.isNotEmpty) return false;
      _type = ur.type;
      _payload = ur.payload;
      return true;
    }

    final _Fragment fragment;
    try {
      fragment = _Fragment.fromDecoded(ur);
    } on FormatException {
      return false;
    }
    if (!_check(fragment) || fragment.seq != ur.seq) return false;

    _queuedParts.add(fragment);
    while (!isComplete && _queuedParts.isNotEmpty) {
      final part = _queuedParts.removeAt(0);
      part.isSimple ? _processSimplePart(part) : _processMixedPart(part);
    }
    return isComplete;
  }

  void reset() => _resetReadState();

  bool _check(_Fragment ur) {
    if (_type.isNotEmpty) {
      return _type == ur.type &&
          _seq.length == ur.seq.length &&
          _expectedMessageLength == ur.messageLength &&
          _expectedChecksum == ur.checksum &&
          _expectedFragmentLength == ur.part.length;
    }
    _type = ur.type;
    _seq.length = ur.seq.length;
    _expectedMessageLength = ur.messageLength;
    _expectedChecksum = ur.checksum;
    _expectedFragmentLength = ur.part.length;
    _expectedPartIndexes
      ..clear()
      ..addAll(List.generate(ur.seq.length, (i) => i));
    return true;
  }

  void _processSimplePart(_Fragment fragment) {
    final fragmentIndex = fragment.indexes.first;
    if (_receivedPartIndexes.contains(fragmentIndex)) return;

    _simpleParts.add(fragment);
    _receivedPartIndexes.add(fragmentIndex);

    if (_arraysEqual(_receivedPartIndexes, _expectedPartIndexes)) {
      _simpleParts.sort((a, b) => a.indexes[0] - b.indexes[0]);
      final builder = BytesBuilder(copy: false);
      for (final part in _simpleParts) {
        builder.add(part.part);
      }
      final message =
          builder.takeBytes().sublist(0, _expectedMessageLength);
      if (_crc32(message) != _expectedChecksum) {
        _resetReadState();
        return;
      }
      _payload = message;
    } else {
      _reduceMixedBy(fragment);
    }
  }

  void _processMixedPart(_Fragment fragment) {
    if (_mixedParts.any((e) => _arraysEqual(e.indexes, fragment.indexes))) {
      return;
    }
    final simple = [fragment, ..._simpleParts].reduce(_reducePartByPart);
    final part = [simple, ..._mixedParts].reduce(_reducePartByPart);
    if (part.isSimple) {
      _queuedParts.add(part);
    } else {
      _reduceMixedBy(part);
      _mixedParts.add(part);
    }
  }

  void _reduceMixedBy(_Fragment fragment) {
    final newMixed = <_Fragment>[];
    for (final item in _mixedParts) {
      final ur = _reducePartByPart(item, fragment);
      ur.isSimple ? _queuedParts.add(ur) : newMixed.add(ur);
    }
    _mixedParts
      ..clear()
      ..addAll(newMixed);
  }

  _Fragment _reducePartByPart(_Fragment a, _Fragment b) {
    if (!b.indexes.every((e) => a.indexes.contains(e))) return a;
    final newIndexes = a.indexes.where((e) => !b.indexes.contains(e)).toList();
    final newLength = max(a.part.length, b.part.length);
    final newPart = Uint8List(newLength);
    for (var i = 0; i < newLength; i++) {
      newPart[i] = a.part[i] ^ b.part[i];
    }
    return _Fragment(
      type: a.type,
      seq: _Seq(a.seq.num, a.seq.length),
      messageLength: a.messageLength,
      checksum: a.checksum,
      part: newPart,
      indexes: newIndexes,
    );
  }

  void _resetReadState() {
    _type = '';
    _payload = Uint8List(0);
    _seq
      ..num = 0
      ..length = 0;
    _expectedMessageLength = 0;
    _expectedChecksum = 0;
    _expectedFragmentLength = 0;
    _expectedPartIndexes.clear();
    _receivedPartIndexes.clear();
    _mixedParts.clear();
    _queuedParts.clear();
    _simpleParts.clear();
  }

  void _partition() {
    final length = _fragmentLength();
    _fragments.clear();
    for (var offset = 0; offset < payload.length; offset += length) {
      final end = min(offset + length, payload.length);
      final item = Uint8List(length);
      item.setRange(0, end - offset, payload, offset);
      _fragments.add(item);
    }
  }

  int _fragmentLength() {
    if (maxLength < minLength || maxLength <= 0 || minLength <= 0) {
      throw ArgumentError('Invalid UR fragment length bounds');
    }
    final maxCount = (payload.length / minLength).ceil();
    var length = 0;
    for (var count = 1; count <= maxCount; count++) {
      length = (payload.length / count).ceil();
      if (length <= maxLength) break;
    }
    return length;
  }
}

class _Seq {
  int num;
  int length;
  _Seq(this.num, this.length);

  bool get isFragment => length > 0 && num > 0;

  static _Seq parse(String value) {
    final parts = value.split('-');
    if (parts.length != 2) return _Seq(0, 0);
    final n = int.tryParse(parts[0]);
    final l = int.tryParse(parts[1]);
    if (n == null || l == null || n <= 0 || l <= 0) {
      throw FormatException('Invalid UR sequence', value);
    }
    return _Seq(n, l);
  }

  @override
  bool operator ==(Object other) =>
      other is _Seq && num == other.num && length == other.length;

  @override
  int get hashCode => num + length;

  @override
  String toString() => '$num-$length';
}

final RegExp _urExp = RegExp(r'^ur:([a-z0-9-]+)(/(\d+-\d+)){0,1}/([a-z]+)$');

class _Decoded {
  final String type;
  final _Seq seq;
  final Uint8List payload;
  final String input;
  _Decoded(this.type, this.seq, this.payload, this.input);

  static _Decoded parse(String value) {
    final m = _urExp.firstMatch(value.toLowerCase());
    if (m == null) throw FormatException('Invalid UR', value);
    return _Decoded(m.group(1)!, _Seq.parse(m.group(3) ?? ''),
        _ByteWords.decode(m.group(4)!), value);
  }
}

class _Fragment {
  static const int maxUint32 = 0xffffffff;
  static const int maxSeqLength = 0x10000;

  final String type;
  final _Seq seq;
  final int messageLength;
  final int checksum;
  final Uint8List part;
  final List<int> indexes;

  _Fragment({
    required this.type,
    required this.seq,
    required this.messageLength,
    required this.checksum,
    required this.part,
    required this.indexes,
  });

  bool get isSimple => indexes.length == 1;

  static _Fragment fromDecoded(_Decoded ur) {
    final CborValue data;
    try {
      data = cbor.decode(ur.payload);
    } catch (_) {
      throw FormatException('Invalid UR fragment', ur.input);
    }
    if (data is! CborList ||
        data.length != 5 ||
        data[0] is! CborInt ||
        data[1] is! CborInt ||
        data[2] is! CborInt ||
        data[3] is! CborInt ||
        data[4] is! CborBytes) {
      throw FormatException('Invalid UR fragment', ur.input);
    }
    final seqNum = (data[0] as CborInt).toInt();
    final seqLength = (data[1] as CborInt).toInt();
    final messageLength = (data[2] as CborInt).toInt();
    final checksum = (data[3] as CborInt).toInt();
    final part = Uint8List.fromList((data[4] as CborBytes).bytes);
    if (seqNum <= 0 ||
        seqNum > maxUint32 ||
        seqLength <= 0 ||
        seqLength > maxSeqLength ||
        messageLength <= 0 ||
        checksum < 0 ||
        checksum > maxUint32 ||
        part.isEmpty ||
        messageLength <= (seqLength - 1) * part.length ||
        messageLength > seqLength * part.length) {
      throw FormatException('Invalid UR sequence', ur.input);
    }
    return _Fragment(
      type: ur.type,
      seq: _Seq(seqNum, seqLength),
      messageLength: messageLength,
      checksum: checksum,
      part: part,
      indexes: _chooseFragments(seqNum, seqLength, checksum),
    );
  }

  String encode() {
    final body = cbor.encode(CborList([
      CborSmallInt(seq.num),
      CborSmallInt(seq.length),
      CborSmallInt(messageLength),
      CborSmallInt(checksum),
      CborBytes(part),
    ]));
    return 'ur:$type/$seq/${_ByteWords.encode(Uint8List.fromList(body))}'
        .toUpperCase();
  }
}

/// Fountain-code fragment choice (BC-UR "chooseFragments"): the first
/// [seqLength] frames are the plain fragments in order, later frames mix a
/// degree-weighted random subset seeded from sha256(seqNum || checksum).
List<int> _chooseFragments(int seqNum, int seqLength, int checksum) {
  if (seqNum <= seqLength) return [seqNum - 1];

  final seed = crypto.sha256
      .convert([..._uint32BE(seqNum), ..._uint32BE(checksum)]).bytes;
  final rng = _Xoshiro256ss(seed);

  final degreeProbabilities = List.generate(seqLength, (i) => 1 / (i + 1));
  final sum = degreeProbabilities.reduce((a, b) => a + b);
  final scaled =
      degreeProbabilities.map((p) => (p * seqLength) / sum).toList();

  final prob = List.filled(seqLength, 0.0);
  final alias = List.filled(seqLength, 0);
  final small = <int>[];
  final large = <int>[];
  for (var i = seqLength - 1; i >= 0; i--) {
    scaled[i] < 1 ? small.add(i) : large.add(i);
  }
  while (small.isNotEmpty && large.isNotEmpty) {
    final less = small.removeLast();
    final more = large.removeLast();
    prob[less] = scaled[less];
    alias[less] = more;
    scaled[more] = (scaled[more] + scaled[less]) - 1;
    scaled[more] < 1 ? small.add(more) : large.add(more);
  }
  while (large.isNotEmpty) {
    prob[large.removeLast()] = 1;
  }
  while (small.isNotEmpty) {
    prob[small.removeLast()] = 1;
  }

  final c = (rng.nextDouble() * prob.length).floor();
  final degree = ((rng.nextDouble() < prob[c]) ? c : alias[c]) + 1;

  final remaining = List.generate(seqLength, (i) => i);
  final result = <int>[];
  while (remaining.isNotEmpty) {
    final index = (rng.nextDouble() * remaining.length).floor();
    result.add(remaining.removeAt(index));
  }
  return result.sublist(0, degree);
}

List<int> _uint32BE(int v) =>
    [(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff];

/// xoshiro256** 1.0 on [BigInt] (mod 2^64), seeded with four big-endian
/// 64-bit words; `nextDouble` = (next >>> 11) * 2^-53, as in `xrandom`.
class _Xoshiro256ss {
  static final BigInt _mask = (BigInt.one << 64) - BigInt.one;
  static final BigInt _five = BigInt.from(5);
  static final BigInt _nine = BigInt.from(9);
  static const double _z = 1.1102230246251565e-16; // 2^-53

  late BigInt _s0, _s1, _s2, _s3;

  _Xoshiro256ss(List<int> seed) {
    BigInt word(int o) {
      var r = BigInt.zero;
      for (var i = 0; i < 8; i++) {
        r = (r << 8) | BigInt.from(seed[o + i]);
      }
      return r;
    }

    _s0 = word(0);
    _s1 = word(8);
    _s2 = word(16);
    _s3 = word(24);
  }

  static BigInt _rotl(BigInt x, int k) =>
      ((x << k) | (x >> (64 - k))) & _mask;

  BigInt _next() {
    final result = (_rotl((_s1 * _five) & _mask, 7) * _nine) & _mask;
    final t = (_s1 << 17) & _mask;
    _s2 ^= _s0;
    _s3 ^= _s1;
    _s1 ^= _s2;
    _s0 ^= _s3;
    _s2 ^= t;
    _s3 = _rotl(_s3, 45);
    return result;
  }

  double nextDouble() => (_next() >> 11).toDouble() * _z;
}

bool _arraysEqual(List a, List b) =>
    a.length == b.length && a.every((e) => b.contains(e));

List<int> _xor(List<int> a, List<int> b) {
  final length = max(a.length, b.length);
  final result = List.filled(length, 0);
  for (var i = 0; i < length; i++) {
    result[i] = a[i] ^ b[i];
  }
  return result;
}

const String _byteWords =
    'ableacidalsoapexaquaarchatomauntawayaxisbackbaldbarnbeltbetabiasbluebodybragbrewbulbbuzzcalmcashcatschefcityclawcodecolacookcostcruxcurlcuspcyandarkdatadaysdelidicedietdoordowndrawdropdrumdulldutyeacheasyechoedgeepicevenexamexiteyesfactfairfernfigsfilmfishfizzflapflewfluxfoxyfreefrogfuelfundgalagamegeargemsgiftgirlglowgoodgraygrimgurugushgyrohalfhanghardhawkheathelphighhillholyhopehornhutsicedideaidleinchinkyintoirisironitemjadejazzjoinjoltjowljudojugsjumpjunkjurykeepkenokeptkeyskickkilnkingkitekiwiknoblamblavalazyleaflegsliarlimplionlistlogoloudloveluaulucklungmainmanymathmazememomenumeowmildmintmissmonknailnavyneednewsnextnoonnotenumbobeyoboeomitonyxopenovalowlspaidpartpeckplaypluspoempoolposepuffpumapurrquadquizraceramprealredorichroadrockroofrubyruinrunsrustsafesagascarsetssilkskewslotsoapsolosongstubsurfswantacotasktaxitenttiedtimetinytoiltombtoystriptunatwinuglyundouniturgeuservastveryvetovialvibeviewvisavoidvowswallwandwarmwaspwavewaxywebswhatwhenwhizwolfworkyankyawnyellyogayurtzapszerozestzinczonezoom';

/// Minimal bytewords (first and last letter of each word) with a CRC32
/// suffix.
class _ByteWords {
  static final RegExp _minimal = RegExp(r'^[a-z]+$');
  static List<int>? _table;

  static List<int> get _lookUp {
    final cached = _table;
    if (cached != null) return cached;
    final t = List.filled(26 * 26, -1);
    for (var i = 0; i < 256; i++) {
      final x = _byteWords.codeUnitAt(i * 4) - 0x61;
      final y = _byteWords.codeUnitAt(i * 4 + 3) - 0x61;
      t[y * 26 + x] = i;
    }
    return _table = t;
  }

  static String encode(Uint8List data) {
    final crc = _crc32(data);
    final buf = [...data, ..._uint32BE(crc)];
    final msg = StringBuffer();
    for (final b in buf) {
      msg
        ..writeCharCode(_byteWords.codeUnitAt(b * 4))
        ..writeCharCode(_byteWords.codeUnitAt(b * 4 + 3));
    }
    return msg.toString();
  }

  static Uint8List decode(String value) {
    final s = value.toLowerCase();
    if (s.length < 8 || s.length.isOdd || !_minimal.hasMatch(s)) {
      throw FormatException('Invalid bytewords', value);
    }
    final bytes = <int>[];
    for (var i = 0; i < s.length; i += 2) {
      final x = s.codeUnitAt(i) - 0x61;
      final y = s.codeUnitAt(i + 1) - 0x61;
      final b = _lookUp[y * 26 + x];
      if (b < 0) throw FormatException('Invalid bytewords', value);
      bytes.add(b);
    }
    final payload = Uint8List.fromList(bytes.sublist(0, bytes.length - 4));
    final c = bytes.sublist(bytes.length - 4);
    final expected = (c[0] << 24 | c[1] << 16 | c[2] << 8 | c[3]) & 0xffffffff;
    if (_crc32(payload) != expected) {
      throw FormatException('Invalid bytewords checksum', value);
    }
    return payload;
  }
}

/// CRC-32 (IEEE 802.3, reflected 0xEDB88320), unsigned.
int _crc32(List<int> data) {
  var crc = 0xffffffff;
  for (final b in data) {
    crc ^= b & 0xff;
    for (var k = 0; k < 8; k++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}
