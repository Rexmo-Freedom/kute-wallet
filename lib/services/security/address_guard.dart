// lib/services/security/address_guard.dart
//
// Pure address-format checks shared by every funding guard. No network,
// no Riverpod, no widgets: callers pass plain strings and get plain
// answers, so the same rules hold in providers, services and tests.

import 'dart:typed_data';
import 'dart:convert';

import 'package:crypto/crypto.dart' show sha256;
import 'package:pointycastle/digests/keccak.dart';

/// Result of checking an address against the format its chain uses.
enum AddressFormatMatch {
  ok,
  mismatch,

  /// No local rule exists for the chain. Payment paths treat this as a
  /// rejection; cache re-verification leaves the entry as it is.
  unverifiable,
}

/// Orchestra chain slugs whose addresses are 20-byte EVM hex.
const Set<String> kEvmAddressChains = {
  // Flashnet's Avalanche and Sei routes use C-Chain and Sei EVM,
  // respectively, not their separate bech32 address families.
  'arc',
  'avalanche',
  'ethereum',
  'arbitrum',
  'optimism',
  'base',
  'polygon',
  'bsc',
  'hyperevm',
  'hypercore',
  'plasma',
  'monad',
  'robinhood',
  'sei',
  'tempo',
};

final RegExp _evmHex = RegExp(r'^0x[0-9a-fA-F]{40}$');

/// Strict EVM address: `0x` plus 40 hex characters. Mixed-case input must
/// also carry a valid EIP-55 checksum; all-lowercase and all-uppercase
/// hex carry no checksum and are accepted as is.
bool isEvmAddress(String address) {
  if (!_evmHex.hasMatch(address)) return false;
  final hex = address.substring(2);
  final isUniformCase = hex == hex.toLowerCase() || hex == hex.toUpperCase();
  if (isUniformCase) return true;
  return _eip55(hex) == hex;
}

/// EIP-55 mixed-case checksum encoding of 40 hex characters.
String _eip55(String hex) {
  final lower = hex.toLowerCase();
  final hash = KeccakDigest(256).process(Uint8List.fromList(lower.codeUnits));
  final out = StringBuffer();
  for (var i = 0; i < lower.length; i++) {
    final nibble = (hash[i >> 1] >> (i.isEven ? 4 : 0)) & 0x0f;
    out.write(nibble >= 8 ? lower[i].toUpperCase() : lower[i]);
  }
  return out.toString();
}

/// Case-insensitive equality of two well-formed EVM addresses.
bool sameEvmAddress(String a, String b) =>
    isEvmAddress(a) && isEvmAddress(b) && a.toLowerCase() == b.toLowerCase();

// ─────────────────────────────── bech32 ───────────────────────────────

enum Bech32Encoding { bech32, bech32m }

class Bech32Decoded {
  const Bech32Decoded(this.hrp, this.data, this.encoding);

  /// Lowercased human-readable part.
  final String hrp;

  /// 5-bit data values without the 6-symbol checksum.
  final List<int> data;
  final Bech32Encoding encoding;
}

const String _bech32Charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';
const int _bech32Const = 1;
const int _bech32mConst = 0x2bc830a3;

int _bech32Polymod(List<int> values) {
  const generator = [
    0x3b6a57b2,
    0x26508e6d,
    0x1ea119fa,
    0x3d4233dd,
    0x2a1462b3
  ];
  var chk = 1;
  for (final v in values) {
    final top = chk >> 25;
    chk = ((chk & 0x1ffffff) << 5) ^ v;
    for (var i = 0; i < 5; i++) {
      if (((top >> i) & 1) == 1) chk ^= generator[i];
    }
  }
  return chk;
}

List<int> _hrpExpand(String hrp) => [
      for (final c in hrp.codeUnits) c >> 5,
      0,
      for (final c in hrp.codeUnits) c & 31,
    ];

/// BIP-173 / BIP-350 decode with full checksum verification. Returns null
/// for any malformed input. [maxLength] is 90 for Bitcoin segwit
/// addresses; Spark addresses are longer and pass a larger limit.
Bech32Decoded? decodeBech32(String input, {int maxLength = 90}) {
  if (input.length > maxLength) return null;
  var hasLower = false;
  var hasUpper = false;
  for (final c in input.codeUnits) {
    if (c < 33 || c > 126) return null;
    if (c >= 0x61 && c <= 0x7a) hasLower = true;
    if (c >= 0x41 && c <= 0x5a) hasUpper = true;
  }
  if (hasLower && hasUpper) return null;
  final lower = input.toLowerCase();
  final pos = lower.lastIndexOf('1');
  if (pos < 1 || pos + 7 > lower.length) return null;
  final hrp = lower.substring(0, pos);
  final values = <int>[];
  for (var i = pos + 1; i < lower.length; i++) {
    final v = _bech32Charset.indexOf(lower[i]);
    if (v < 0) return null;
    values.add(v);
  }
  final Bech32Encoding encoding;
  switch (_bech32Polymod([..._hrpExpand(hrp), ...values])) {
    case _bech32Const:
      encoding = Bech32Encoding.bech32;
    case _bech32mConst:
      encoding = Bech32Encoding.bech32m;
    default:
      return null;
  }
  return Bech32Decoded(
      hrp, List.unmodifiable(values.sublist(0, values.length - 6)), encoding);
}

List<int>? _convertBits(List<int> data, int from, int to, {required bool pad}) {
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
  if (pad) {
    if (bits > 0) out.add((acc << (to - bits)) & maxV);
  } else if (bits >= from || ((acc << (to - bits)) & maxV) != 0) {
    return null;
  }
  return out;
}

// ─────────────────────────────── Spark ───────────────────────────────

enum _SparkNetwork { mainnet, testnet, regtest, signet }

/// Spark address HRPs, current and legacy spellings (spark-sdk
/// crates/spark/src/address/mod.rs).
const Map<String, _SparkNetwork> _sparkHrps = {
  'spark': _SparkNetwork.mainnet,
  'sp': _SparkNetwork.mainnet,
  'sparkt': _SparkNetwork.testnet,
  'spt': _SparkNetwork.testnet,
  'sparkrt': _SparkNetwork.regtest,
  'sprt': _SparkNetwork.regtest,
  'sparks': _SparkNetwork.signet,
  'sps': _SparkNetwork.signet,
};

({_SparkNetwork network, List<int> payload})? _decodeSpark(String address) {
  final decoded = decodeBech32(address, maxLength: 1023);
  if (decoded == null || decoded.encoding != Bech32Encoding.bech32m) {
    return null;
  }
  final network = _sparkHrps[decoded.hrp];
  if (network == null) return null;
  final payload = _convertBits(decoded.data, 5, 8, pad: false);
  // Protobuf SparkAddress: field 1 is the 33-byte compressed identity key.
  if (payload == null ||
      payload.length < 35 ||
      payload[0] != 0x0a ||
      payload[1] != 0x21 ||
      (payload[2] != 0x02 && payload[2] != 0x03)) {
    return null;
  }
  return (network: network, payload: payload);
}

/// Full bech32m Spark address check. Mainnet accepts `spark` and `sp`;
/// otherwise only the regtest HRPs `sparkrt` and `sprt` are accepted.
bool isSparkAddress(String address, {required bool mainnet}) {
  final decoded = _decodeSpark(address);
  if (decoded == null) return false;
  return decoded.network ==
      (mainnet ? _SparkNetwork.mainnet : _SparkNetwork.regtest);
}

/// Equality after decoding, so `sp1…` and `spark1…` spellings of the same
/// address match. Undecodable input never matches.
bool sameSparkAddress(String a, String b) {
  final da = _decodeSpark(a);
  final db = _decodeSpark(b);
  if (da == null || db == null || da.network != db.network) return false;
  if (da.payload.length != db.payload.length) return false;
  for (var i = 0; i < da.payload.length; i++) {
    if (da.payload[i] != db.payload[i]) return false;
  }
  return true;
}

// ────────────────────────────── base58 ──────────────────────────────

const String _base58Alphabet =
    '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

Uint8List? _base58Decode(String input, {String alphabet = _base58Alphabet}) {
  if (input.isEmpty) return null;
  var value = BigInt.zero;
  final radix = BigInt.from(58);
  for (final ch in input.split('')) {
    final digit = alphabet.indexOf(ch);
    if (digit < 0) return null;
    value = value * radix + BigInt.from(digit);
  }
  final body = <int>[];
  while (value > BigInt.zero) {
    body.add((value & BigInt.from(0xff)).toInt());
    value = value >> 8;
  }
  var leadingZeros = 0;
  while (leadingZeros < input.length && input[leadingZeros] == alphabet[0]) {
    leadingZeros++;
  }
  return Uint8List.fromList(
      [...List.filled(leadingZeros, 0), ...body.reversed]);
}

/// Base58Check payload (version byte included), or null on a bad checksum.
Uint8List? _base58CheckDecode(String input,
    {String alphabet = _base58Alphabet}) {
  if (input.isEmpty || input.length > 128) return null;
  final raw = _base58Decode(input, alphabet: alphabet);
  if (raw == null || raw.length < 5) return null;
  final payload = raw.sublist(0, raw.length - 4);
  final checksum = sha256.convert(sha256.convert(payload).bytes).bytes;
  for (var i = 0; i < 4; i++) {
    if (raw[raw.length - 4 + i] != checksum[i]) return null;
  }
  return payload;
}

// ────────────────────────────── chains ──────────────────────────────

bool _isBitcoinAddress(String address, {required bool mainnet}) {
  final segwit = decodeBech32(address);
  if (segwit != null) {
    final hrpOk = mainnet
        ? segwit.hrp == 'bc'
        : (segwit.hrp == 'tb' || segwit.hrp == 'bcrt');
    if (!hrpOk || segwit.data.isEmpty) return false;
    final version = segwit.data.first;
    if (version > 16) return false;
    final program = _convertBits(segwit.data.sublist(1), 5, 8, pad: false);
    if (program == null || program.length < 2 || program.length > 40) {
      return false;
    }
    if (version == 0) {
      return segwit.encoding == Bech32Encoding.bech32 &&
          (program.length == 20 || program.length == 32);
    }
    return segwit.encoding == Bech32Encoding.bech32m;
  }
  final legacy = _base58CheckDecode(address);
  if (legacy == null || legacy.length != 21) return false;
  final version = legacy.first;
  return mainnet
      ? (version == 0x00 || version == 0x05)
      : (version == 0x6f || version == 0xc4);
}

bool _isTronAddress(String address) {
  if (!address.startsWith('T')) return false;
  final payload = _base58CheckDecode(address);
  return payload != null && payload.length == 21 && payload.first == 0x41;
}

bool _isSolanaAddress(String address) {
  if (address.length < 32 || address.length > 44) return false;
  final raw = _base58Decode(address);
  return raw != null && raw.length == 32;
}

// Mainnet transparent destinations only. Shielded/unified Zcash and Litecoin
// MWEB addresses require a separate provider contract and are not accepted.
bool _isLitecoinAddress(String address, {required bool mainnet}) {
  final segwit = decodeBech32(address);
  if (segwit != null) {
    if (segwit.hrp != (mainnet ? 'ltc' : 'tltc') || segwit.data.isEmpty) {
      return false;
    }
    final version = segwit.data.first;
    final program = _convertBits(segwit.data.sublist(1), 5, 8, pad: false);
    if (version > 16 ||
        program == null ||
        program.length < 2 ||
        program.length > 40) {
      return false;
    }
    return version == 0
        ? segwit.encoding == Bech32Encoding.bech32 &&
            (program.length == 20 || program.length == 32)
        : segwit.encoding == Bech32Encoding.bech32m;
  }
  final payload = _base58CheckDecode(address);
  if (payload == null || payload.length != 21) return false;
  // Refuse the old Bitcoin-looking P2SH prefix: explicit Litecoin prefixes
  // avoid accidentally authorizing a pasted Bitcoin address on this network.
  return mainnet
      ? {0x30, 0x32}.contains(payload[0])
      : {0x6f, 0x3a}.contains(payload[0]);
}

bool _isZcashAddress(String address, {required bool mainnet}) {
  final payload = _base58CheckDecode(address);
  if (payload == null || payload.length != 22) return false;
  final prefix = (payload[0] << 8) | payload[1];
  return mainnet
      ? {0x1cb8, 0x1cbd}.contains(prefix)
      : {0x1d25, 0x1cba}.contains(prefix);
}

bool _isXrpAddress(String address) {
  if (!address.startsWith('r') || address.length > 35) return false;
  final payload = _base58CheckDecode(address,
      alphabet: 'rpshnaf39wBUDNEGHJKLM4PQRST7VWXYZ2bcdeCg65jkm8oFqi1tuvAxyz');
  return payload != null && payload.length == 21 && payload.first == 0;
}

bool _isTonAddress(String address, {required bool mainnet}) {
  // Friendly addresses include both a checksum and network flag (TEP-2).
  // Raw addresses cannot distinguish testnet and are deliberately excluded.
  if (address.length != 48) return false;
  try {
    final bytes =
        base64.decode(address.replaceAll('-', '+').replaceAll('_', '/'));
    if (bytes.length != 36 ||
        !{0x11, 0x51}.contains(bytes[0] & 0x7f) ||
        (mainnet && (bytes[0] & 0x80) != 0) ||
        !{0, 255}.contains(bytes[1])) {
      return false;
    }
    var crc = 0;
    for (final byte in bytes.take(34)) {
      crc ^= byte << 8;
      for (var bit = 0; bit < 8; bit++) {
        crc = ((crc << 1) ^ ((crc & 0x8000) != 0 ? 0x1021 : 0)) & 0xffff;
      }
    }
    return bytes[34] == crc >> 8 && bytes[35] == (crc & 255);
  } on FormatException {
    return false;
  }
}

/// Address family for picker filtering. Final authorization always checks the
/// selected chain with [formatMatchesChain], never just this classification.
String orchestraAddressFamily(String raw) {
  final address = raw.trim();
  if (isEvmAddress(address)) return 'evm';
  for (final chain in [
    'spark',
    'tron',
    'xrp',
    'bitcoin',
    'litecoin',
    'zcash',
    'ton',
    'solana'
  ]) {
    if (formatMatchesChain(chain, address, mainnet: true) ==
        AddressFormatMatch.ok) {
      return chain;
    }
  }
  return 'unknown';
}

/// Checks [address] against the format [chain] uses. Chains without a
/// local rule answer [AddressFormatMatch.unverifiable].
AddressFormatMatch formatMatchesChain(
  String chain,
  String address, {
  required bool mainnet,
}) {
  final slug = chain.trim().toLowerCase();
  final bool matches;
  if (slug == 'spark') {
    matches = isSparkAddress(address, mainnet: mainnet);
  } else if (kEvmAddressChains.contains(slug)) {
    matches = isEvmAddress(address);
  } else if (slug == 'bitcoin' || slug == 'btc') {
    matches = _isBitcoinAddress(address, mainnet: mainnet);
  } else if (slug == 'tron') {
    matches = _isTronAddress(address);
  } else if (slug == 'litecoin') {
    matches = _isLitecoinAddress(address, mainnet: mainnet);
  } else if (slug == 'zcash') {
    matches = _isZcashAddress(address, mainnet: mainnet);
  } else if (slug == 'xrp') {
    matches = _isXrpAddress(address);
  } else if (slug == 'ton') {
    matches = _isTonAddress(address, mainnet: mainnet);
  } else if (slug == 'solana') {
    matches = _isSolanaAddress(address);
  } else {
    return AddressFormatMatch.unverifiable;
  }
  return matches ? AddressFormatMatch.ok : AddressFormatMatch.mismatch;
}
