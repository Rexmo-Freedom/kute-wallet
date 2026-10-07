// Polymarket V2 order signing — local implementation, no polybrainz_polymarket
// dependency for the order path.
//
// V2 Order struct (EIP-712 typed data):
//   Order(
//     uint256 salt,
//     address maker,
//     address signer,
//     uint256 tokenId,
//     uint256 makerAmount,
//     uint256 takerAmount,
//     uint8 side,
//     uint8 signatureType,
//     uint256 timestamp,
//     bytes32 metadata,
//     bytes32 builder
//   )
//
// V2 EIP-712 Domain:
//   name             = "Polymarket CTF Exchange"
//   version          = "2"   (V1 used "1")
//   chainId          = 137
//   verifyingContract = V2 Exchange or V2 NegRisk Exchange
//
// Removed in V2: taker, expiration, nonce, feeRateBps
// Added in V2:   timestamp (ms), metadata (bytes32), builder (bytes32)
//
// Fees are now computed at match time by the protocol, not embedded in the
// signed order.
//
// ────────────────────────────────────────────────────────────────────────
// POLY_1271 (signatureType = 3) — deposit wallet flow
// ────────────────────────────────────────────────────────────────────────
// Polymarket V2 migrated all Safe ("deposit wallet") orders from
// POLY_GNOSIS_SAFE (sigType=2, signer=EOA, raw ECDSA) to POLY_1271
// (sigType=3, signer=Safe, ERC-7739-wrapped EIP-1271 signature). The CLOB
// now rejects any Safe order signed the old way with
//   "maker address not allowed, please use the deposit wallet flow".
//
// Construction mirrors clob-client-v2's `exchangeOrderBuilderV2.ts`:
//   1. Inner sign — EOA EIP-712-signs the TypedDataSign struct:
//        Domain   = Polymarket CTF Exchange v2  (verifyingContract = Exchange)
//        PrimaryType = TypedDataSign(
//                        Order contents,
//                        string name,
//                        string version,
//                        uint256 chainId,
//                        address verifyingContract,
//                        bytes32 salt)
//        Values   = { contents: Order, name: "DepositWallet", version: "1",
//                     chainId: 137, verifyingContract: Safe, salt: 0 }
//   2. Wire encoding (concatenation):
//        innerSig(65) || appDomainSep(32) || contentsHash(32)
//          || contentsType(utf8 bytes) || uint16BE(contentsTypeLen)
//      where appDomainSep is the Polymarket Exchange domain separator
//      and contentsHash is the EIP-712 hash of the Order struct.
//   3. When Polymarket validates: it calls Safe.isValidSignature(orderHash,
//      signature) per ERC-1271/7739. The Safe's owner key is the EOA, so
//      ecrecover on the inner signature confirms ownership.

import 'dart:convert';
import 'package:kute/services/hardware/eip712_typed_data.dart';
import 'package:kute/services/hardware/evm_signer.dart';
import 'package:kute/services/hardware/signing_clarity.dart';
import 'dart:typed_data';

import 'package:kute/constants/polymarket_constants.dart';
import 'package:pointycastle/digests/keccak.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show EthPrivateKey, EthSignature;

class OrderStructV2 {
  final BigInt salt;
  final String maker;
  final String signer;
  final String tokenId;
  final BigInt makerAmount;
  final BigInt takerAmount;
  final int side; // 0 = buy, 1 = sell
  final int signatureType; // 0 = EOA, 2 = GNOSIS_SAFE
  final BigInt timestamp; // milliseconds since epoch
  final String metadata; // 32-byte hex (0x-prefixed), default 0x000…0
  final String builder; // 32-byte hex (0x-prefixed), builder code

  const OrderStructV2({
    required this.salt,
    required this.maker,
    required this.signer,
    required this.tokenId,
    required this.makerAmount,
    required this.takerAmount,
    required this.side,
    required this.signatureType,
    required this.timestamp,
    required this.metadata,
    required this.builder,
  });

  /// JSON shape submitted to CLOB POST /order alongside the signature.
  Map<String, dynamic> toJson() => {
        'salt': salt.toString(),
        'maker': maker,
        'signer': signer,
        'tokenId': tokenId,
        'makerAmount': makerAmount.toString(),
        'takerAmount': takerAmount.toString(),
        'side': side,
        'signatureType': signatureType,
        'timestamp': timestamp.toString(),
        'metadata': metadata,
        'builder': builder,
      };

  /// Implied price helper (mirrors V1 OrderStruct.price for analytics).
  double get price {
    if (takerAmount == BigInt.zero || makerAmount == BigInt.zero) return 0;
    return side == 0
        ? makerAmount.toDouble() / takerAmount.toDouble()
        : takerAmount.toDouble() / makerAmount.toDouble();
  }
}

class SignedOrderV2 {
  final OrderStructV2 order;
  final String signature; // 0x{r}{s}{v}, 65 bytes hex

  const SignedOrderV2({required this.order, required this.signature});
}

/// EIP-712 sign a V2 order. Returns 0x-prefixed 65-byte hex signature.
///
/// Use this for sigType ∈ {EOA(0), POLY_PROXY(1), POLY_GNOSIS_SAFE(2)}.
/// For POLY_1271(3) — deposit wallets / Safe — use [signOrderV2Poly1271]
/// instead; the wire format is a concatenation, not a raw 65-byte sig.
Future<String> signOrderV2({
  required OrderStructV2 order,
  EthPrivateKey? credentials,
  EvmExternalSigner? externalSigner,
  required String verifyingContract,
  int chainId = PolymarketConstants.polygonChainId,
}) async {
  final domainSeparator = _hashDomain(
    name: 'Polymarket CTF Exchange',
    version: PolymarketConstants.exchangeEip712DomainVersion, // "2"
    chainId: chainId,
    verifyingContract: verifyingContract,
  );
  final structHash = _hashOrderStruct(order);

  // EIP-712 digest: keccak256(0x1901 ++ domainSeparator ++ structHash)

  final sig = await signTypedDataHashes(
      domain: domainSeparator,
      message: structHash,
      kind: LedgerActionKind.pmOrderEoa,
      typedData: () => orderV2TypedData(
          order: order, verifyingContract: verifyingContract, chainId: chainId),
      credentials: credentials,
      externalSigner: externalSigner);
  return _encodeSignature(sig);
}

// ──────────── Full typed data (Wallet hardening Phase 3) ────────────
// Each builder below hashes equal to the hand-rolled builder next to it
// (pinned by test/services/hardware/typed_data_equivalence_test.dart and
// re-checked at runtime on the external signing path).

const List<Eip712Field> _orderFields = [
  Eip712Field('salt', 'uint256'),
  Eip712Field('maker', 'address'),
  Eip712Field('signer', 'address'),
  Eip712Field('tokenId', 'uint256'),
  Eip712Field('makerAmount', 'uint256'),
  Eip712Field('takerAmount', 'uint256'),
  Eip712Field('side', 'uint8'),
  Eip712Field('signatureType', 'uint8'),
  Eip712Field('timestamp', 'uint256'),
  Eip712Field('metadata', 'bytes32'),
  Eip712Field('builder', 'bytes32'),
];

List<Eip712Field> _typedDataSignFields(String contentsType) => [
      Eip712Field('contents', contentsType),
      const Eip712Field('name', 'string'),
      const Eip712Field('version', 'string'),
      const Eip712Field('chainId', 'uint256'),
      const Eip712Field('verifyingContract', 'address'),
      const Eip712Field('salt', 'bytes32'),
    ];

const List<Eip712Field> _clobAuthDomainFields = [
  Eip712Field('name', 'string'),
  Eip712Field('version', 'string'),
  Eip712Field('chainId', 'uint256'),
];

const List<Eip712Field> _clobAuthFields = [
  Eip712Field('address', 'address'),
  Eip712Field('timestamp', 'string'),
  Eip712Field('nonce', 'uint256'),
  Eip712Field('message', 'string'),
];

Map<String, Object?> _exchangeDomain(String verifyingContract, int chainId,
        [String version = PolymarketConstants.exchangeEip712DomainVersion]) =>
    {
      'name': 'Polymarket CTF Exchange',
      'version': version,
      'chainId': chainId,
      'verifyingContract': verifyingContract,
    };

Map<String, Object?> _orderMessage(OrderStructV2 o) => {
      'salt': o.salt,
      'maker': o.maker,
      'signer': o.signer,
      'tokenId': o.tokenId,
      'makerAmount': o.makerAmount,
      'takerAmount': o.takerAmount,
      'side': o.side,
      'signatureType': o.signatureType,
      'timestamp': o.timestamp,
      'metadata': o.metadata,
      'builder': o.builder,
    };

Map<String, Object?> _clobAuthMessage(
        String address, int timestamp, int nonce) =>
    {
      'address': address,
      'timestamp': timestamp.toString(),
      'nonce': nonce,
      'message': _clobAuthMsg,
    };

/// Bare V2 Order under the Exchange domain (sigType 0, 1 or 2). Its digest
/// is also the Exchange-domain order hash the CLOB reports as `orderID`.
///
/// [domainVersion] is "2" for the CLOB; combos sign the same struct under
/// Exchange v3 ("3", see `polymarket/combos/combo_order.dart`).
Eip712TypedData orderV2TypedData({
  required OrderStructV2 order,
  required String verifyingContract,
  int chainId = PolymarketConstants.polygonChainId,
  String domainVersion = PolymarketConstants.exchangeEip712DomainVersion,
}) =>
    Eip712TypedData(
      types: const {
        kEip712DomainType: kEip712DomainFields,
        'Order': _orderFields,
      },
      primaryType: 'Order',
      domain: _exchangeDomain(verifyingContract, chainId, domainVersion),
      message: _orderMessage(order),
    );

/// `TypedDataSign<Order>` under the Exchange domain (sigType 3).
Eip712TypedData orderV2Poly1271TypedData({
  required OrderStructV2 order,
  required String verifyingContract,
  int chainId = PolymarketConstants.polygonChainId,
  String domainVersion = PolymarketConstants.exchangeEip712DomainVersion,
}) =>
    Eip712TypedData(
      types: {
        kEip712DomainType: kEip712DomainFields,
        'TypedDataSign': _typedDataSignFields('Order'),
        'Order': _orderFields,
      },
      primaryType: 'TypedDataSign',
      domain: _exchangeDomain(verifyingContract, chainId, domainVersion),
      message: {
        'contents': _orderMessage(order),
        'name': PolymarketConstants.depositWalletDomainName,
        'version': PolymarketConstants.depositWalletDomainVersion,
        'chainId': chainId,
        'verifyingContract': order.signer,
        'salt': PolymarketConstants.bytes32Zero,
      },
    );

/// ClobAuth under the three-field ClobAuthDomain (EOA).
Eip712TypedData clobAuthEoaTypedData({
  required String address,
  required int timestamp,
  required int nonce,
  int chainId = PolymarketConstants.polygonChainId,
}) =>
    Eip712TypedData(
      types: const {
        kEip712DomainType: _clobAuthDomainFields,
        'ClobAuth': _clobAuthFields,
      },
      primaryType: 'ClobAuth',
      domain: {'name': 'ClobAuthDomain', 'version': '1', 'chainId': chainId},
      message: _clobAuthMessage(address, timestamp, nonce),
    );

/// `TypedDataSign<ClobAuth>` under the ClobAuthDomain (deposit wallet).
Eip712TypedData clobAuthPoly1271TypedData({
  required String safeAddress,
  required int timestamp,
  required int nonce,
  int chainId = PolymarketConstants.polygonChainId,
}) =>
    Eip712TypedData(
      types: {
        kEip712DomainType: _clobAuthDomainFields,
        'TypedDataSign': _typedDataSignFields('ClobAuth'),
        'ClobAuth': _clobAuthFields,
      },
      primaryType: 'TypedDataSign',
      domain: {'name': 'ClobAuthDomain', 'version': '1', 'chainId': chainId},
      message: {
        'contents': _clobAuthMessage(safeAddress, timestamp, nonce),
        'name': PolymarketConstants.depositWalletDomainName,
        'version': PolymarketConstants.depositWalletDomainVersion,
        'chainId': chainId,
        'verifyingContract': safeAddress,
        'salt': PolymarketConstants.bytes32Zero,
      },
    );

/// POLY_1271 signing for V2 deposit-wallet orders (sigType = 3).
///
/// Mirrors clob-client-v2's `exchangeOrderBuilderV2.ts buildOrderSignature`
/// for the POLY_1271 branch. The EOA owner of the Safe signs an ERC-7739-
/// wrapped (TypedDataSign) hash; the wire signature is the concatenation
/// of innerSig + the data needed for Safe.isValidSignature() to reconstruct
/// the wrapped hash on-chain.
///
/// Returns the 0x-prefixed wire signature ready to drop into `order.signature`.
///
/// [domainVersion] defaults to the CLOB's "2". Combos pass "3" with the
/// Exchange v3 contract: the wrapping is identical (docs.polymarket.com
/// /trading/combos/requesters, `wrapDepositWalletSignature`).
Future<String> signOrderV2Poly1271({
  required OrderStructV2 order,
  EthPrivateKey? credentials,
  EvmExternalSigner? externalSigner,
  required String verifyingContract, // Polymarket Exchange (V2 or NegRisk V2)
  int chainId = PolymarketConstants.polygonChainId,
  String domainVersion = PolymarketConstants.exchangeEip712DomainVersion,
}) async {
  // 1. Exchange domain separator — same one buildOrderHash uses.
  final appDomainSep = _hashDomain(
    name: 'Polymarket CTF Exchange',
    version: domainVersion, // "2" (CLOB) or "3" (combos)
    chainId: chainId,
    verifyingContract: verifyingContract,
  );

  // 2. Hash of the bare Order struct (the `contents` field of TypedDataSign).
  final contentsHash = _hashOrderStruct(order);

  // 3. TypedDataSign struct hash, primaryType = TypedDataSign.
  //    EIP-712 typehash includes the referenced Order type definition:
  //      TypedDataSign(Order contents,…)Order(…)
  const typedDataSignType =
      'TypedDataSign(Order contents,string name,string version,'
      'uint256 chainId,address verifyingContract,bytes32 salt)'
      '$_orderTypeString';
  final typedDataSignTypeHash = _keccak256(utf8.encode(typedDataSignType));

  final structHash = _keccak256(Uint8List.fromList([
    ...typedDataSignTypeHash,
    ...contentsHash,
    ..._keccak256(utf8.encode('DepositWallet')), // name
    ..._keccak256(utf8.encode('1')), // version
    ..._encodeUint(BigInt.from(chainId)),
    ..._encodeAddress(order.signer), // verifyingContract = Safe
    ..._encodeBytes32(PolymarketConstants.bytes32Zero), // salt
  ]));

  // 4. EIP-712 digest under the same Exchange domain.

  // 5. EOA signs the digest.
  final innerSig = await signTypedDataHashes(
      domain: appDomainSep,
      message: structHash,
      kind: LedgerActionKind.pmOrder,
      typedData: () => orderV2Poly1271TypedData(
          order: order,
          verifyingContract: verifyingContract,
          chainId: chainId,
          domainVersion: domainVersion),
      credentials: credentials,
      externalSigner: externalSigner);
  final innerSigHex = _encodeSignature(innerSig).substring(2); // strip 0x

  // 6. Wire encoding:
  //      innerSig(65) || appDomainSep(32) || contentsHash(32)
  //        || contentsType(utf8) || uint16BE(contentsTypeLen)
  final contentsTypeBytes = utf8.encode(_orderTypeString);
  final contentsTypeHex = contentsTypeBytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  final lenHex = contentsTypeBytes.length.toRadixString(16).padLeft(4, '0');
  final appDomainSepHex = appDomainSep
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  final contentsHashHex = contentsHash
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();

  return '0x$innerSigHex$appDomainSepHex$contentsHashHex'
      '$contentsTypeHex$lenHex';
}

/// The exact Order type string used in both the V2 order EIP-712 hash and
/// the trailing `contentsType` field of the POLY_1271 wire signature.
/// Kept as a top-level constant so the two consumers can't drift.
const _orderTypeString =
    'Order(uint256 salt,address maker,address signer,uint256 tokenId,'
    'uint256 makerAmount,uint256 takerAmount,uint8 side,uint8 signatureType,'
    'uint256 timestamp,bytes32 metadata,bytes32 builder)';

// ──────────────────────────────────────────────────────────────────────
// L1 (CLOB API key creation) — POLY_1271 wrapping for deposit wallets
// ──────────────────────────────────────────────────────────────────────
// When the user trades from a Safe, we MUST create the CLOB API key bound
// to the Safe address (not the EOA). Otherwise every subsequent order
// rejects with "the order signer address has to be the address of the API
// KEY" because order.signer == Safe but the API key's recorded owner is
// the EOA.
//
// Polymarket's `createApiKey` accepts an L1-signed typed data of:
//   ClobAuth(address address,string timestamp,uint256 nonce,string message)
// under the ClobAuthDomain (name="ClobAuthDomain", version="1", chainId).
// The CLOB looks up the signer:
//   - If POLY_ADDRESS is an EOA  → ecrecover the typed-data hash
//   - If POLY_ADDRESS is a Safe  → eth_call Safe.isValidSignature(hash, sig)
//
// For the Safe path the signature has to be in the ERC-7739 / TypedDataSign
// wrapped form (same wire layout as the order POLY_1271 signature). This is
// the gap the Polymarket SDKs themselves haven't implemented — issue
// `clob-client-v2#65` / `py-clob-client-v2#70`. We implement it here.

const _clobAuthTypeString =
    'ClobAuth(address address,string timestamp,uint256 nonce,string message)';
const _clobAuthMsg = 'This message attests that I control the given wallet';

/// Hash the ClobAuthDomain — note this domain has NO verifyingContract,
/// so the EIP712Domain typehash is the 3-field variant.
Uint8List _hashClobAuthDomain({required int chainId}) {
  final typeHash = _keccak256(utf8.encode(
    'EIP712Domain(string name,string version,uint256 chainId)',
  ));
  return _keccak256(Uint8List.fromList([
    ...typeHash,
    ..._keccak256(utf8.encode('ClobAuthDomain')),
    ..._keccak256(utf8.encode('1')),
    ..._encodeUint(BigInt.from(chainId)),
  ]));
}

Uint8List _hashClobAuthStruct({
  required String address,
  required int timestamp,
  required int nonce,
}) {
  final typeHash = _keccak256(utf8.encode(_clobAuthTypeString));
  return _keccak256(Uint8List.fromList([
    ...typeHash,
    ..._encodeAddress(address),
    ..._keccak256(utf8.encode(timestamp.toString())),
    ..._encodeUint(BigInt.from(nonce)),
    ..._keccak256(utf8.encode(_clobAuthMsg)),
  ]));
}

/// L1 ClobAuth signature for an **EOA** wallet (no Safe). Standard EIP-712.
/// Returns 0x-prefixed 65-byte hex.
Future<String> signClobAuthEoa({
  EthPrivateKey? credentials,
  EvmExternalSigner? externalSigner,
  required String address,
  required int timestamp,
  required int nonce,
  int chainId = PolymarketConstants.polygonChainId,
}) async {
  final domainSep = _hashClobAuthDomain(chainId: chainId);
  final structHash = _hashClobAuthStruct(
    address: address,
    timestamp: timestamp,
    nonce: nonce,
  );
  final sig = await signTypedDataHashes(
      domain: domainSep,
      message: structHash,
      kind: LedgerActionKind.pmClobAuth,
      typedData: () => clobAuthEoaTypedData(
          address: address,
          timestamp: timestamp,
          nonce: nonce,
          chainId: chainId),
      credentials: credentials,
      externalSigner: externalSigner);
  return _encodeSignature(sig);
}

/// L1 ClobAuth signature for a **deposit wallet** (Safe). Builds the
/// ERC-7739 / TypedDataSign wrapper so the CLOB can verify the signature
/// by calling `Safe.isValidSignature` on the deployed Safe contract.
///
/// [safeAddress] is the deposit wallet address; the EOA private key
/// signs the wrapped hash to prove Safe ownership.
///
/// Returns the 0x-prefixed concatenated wire signature, same layout as
/// the order POLY_1271 path:
///   innerSig(65) || appDomainSep(32) || contentsHash(32)
///     || contentsType(utf8) || uint16BE(contentsTypeLen)
Future<String> signClobAuthPoly1271({
  EthPrivateKey? credentials,
  EvmExternalSigner? externalSigner,
  required String safeAddress,
  required int timestamp,
  required int nonce,
  int chainId = PolymarketConstants.polygonChainId,
}) async {
  // 1. ClobAuthDomain separator (the "appDomainSep" in the wire trailer).
  final appDomainSep = _hashClobAuthDomain(chainId: chainId);

  // 2. Inner ClobAuth struct hash — `address` field must be the Safe
  //    since that's what the CLOB compares against POLY_ADDRESS.
  final contentsHash = _hashClobAuthStruct(
    address: safeAddress,
    timestamp: timestamp,
    nonce: nonce,
  );

  // 3. TypedDataSign struct hash. Typehash includes the nested ClobAuth
  //    type definition, per EIP-712 rules for referenced types.
  const typedDataSignType =
      'TypedDataSign(ClobAuth contents,string name,string version,'
      'uint256 chainId,address verifyingContract,bytes32 salt)'
      '$_clobAuthTypeString';
  final typedDataSignTypeHash = _keccak256(utf8.encode(typedDataSignType));

  final structHash = _keccak256(Uint8List.fromList([
    ...typedDataSignTypeHash,
    ...contentsHash,
    ..._keccak256(utf8.encode('DepositWallet')), // name
    ..._keccak256(utf8.encode('1')), // version
    ..._encodeUint(BigInt.from(chainId)),
    ..._encodeAddress(safeAddress), // verifyingContract = Safe
    ..._encodeBytes32(PolymarketConstants.bytes32Zero), // salt
  ]));

  // 4. Final digest under the ClobAuthDomain (outer domain).

  // 5. EOA owner signs.
  final innerSig = await signTypedDataHashes(
      domain: appDomainSep,
      message: structHash,
      kind: LedgerActionKind.pmClobAuth,
      typedData: () => clobAuthPoly1271TypedData(
          safeAddress: safeAddress,
          timestamp: timestamp,
          nonce: nonce,
          chainId: chainId),
      credentials: credentials,
      externalSigner: externalSigner);
  final innerSigHex = _encodeSignature(innerSig).substring(2); // strip 0x

  // 6. Wire encoding.
  final contentsTypeBytes = utf8.encode(_clobAuthTypeString);
  final contentsTypeHex = contentsTypeBytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  final lenHex = contentsTypeBytes.length.toRadixString(16).padLeft(4, '0');
  final appDomainSepHex = appDomainSep
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  final contentsHashHex = contentsHash
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();

  return '0x$innerSigHex$appDomainSepHex$contentsHashHex'
      '$contentsTypeHex$lenHex';
}

// ──────────── EIP-712 internals ────────────

Uint8List _hashDomain({
  required String name,
  required String version,
  required int chainId,
  required String verifyingContract,
}) {
  final typeHash = _keccak256(utf8.encode(
    'EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)',
  ));
  return _keccak256(Uint8List.fromList([
    ...typeHash,
    ..._keccak256(utf8.encode(name)),
    ..._keccak256(utf8.encode(version)),
    ..._encodeUint(BigInt.from(chainId)),
    ..._encodeAddress(verifyingContract),
  ]));
}

Uint8List _hashOrderStruct(OrderStructV2 o) {
  final typeHash = _keccak256(utf8.encode(_orderTypeString));
  return _keccak256(Uint8List.fromList([
    ...typeHash,
    ..._encodeUint(o.salt),
    ..._encodeAddress(o.maker),
    ..._encodeAddress(o.signer),
    ..._encodeUint(BigInt.parse(o.tokenId)),
    ..._encodeUint(o.makerAmount),
    ..._encodeUint(o.takerAmount),
    ..._encodeUint(BigInt.from(o.side)),
    ..._encodeUint(BigInt.from(o.signatureType)),
    ..._encodeUint(o.timestamp),
    ..._encodeBytes32(o.metadata),
    ..._encodeBytes32(o.builder),
  ]));
}

Uint8List _keccak256(List<int> data) {
  return KeccakDigest(256).process(Uint8List.fromList(data));
}

Uint8List _encodeUint(BigInt value) {
  final bytes = Uint8List(32);
  var temp = value;
  for (var i = 31; i >= 0; i--) {
    bytes[i] = (temp & BigInt.from(0xff)).toInt();
    temp = temp >> 8;
  }
  return bytes;
}

Uint8List _encodeAddress(String address) {
  final bytes = Uint8List(32);
  final clean = address.replaceFirst('0x', '');
  if (clean.length != 40) {
    // Log only the length — the raw address shouldn't survive into
    // an unhandled-exception path that lands in Crashlytics.
    throw ArgumentError(
        'Address must be 20 bytes (40 hex chars), got ${clean.length}');
  }
  for (var i = 0; i < 20; i++) {
    bytes[12 + i] =
        int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return bytes;
}

/// Decode a 32-byte hex string (with or without 0x prefix) into 32 bytes.
Uint8List _encodeBytes32(String hex) {
  final clean = hex.replaceFirst('0x', '');
  if (clean.length != 64) {
    throw ArgumentError(
        'bytes32 must be 32 bytes (64 hex chars), got ${clean.length}');
  }
  final bytes = Uint8List(32);
  for (var i = 0; i < 32; i++) {
    bytes[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return bytes;
}

String _encodeSignature(EthSignature sig) {
  // EthSignature.toHex() returns 0x-prefixed 65-byte hex (r||s||v).
  return sig.toHex();
}
