// lib/services/hyperliquid/hyperliquid_signing.dart
//
// Hyperliquid /exchange signing — local implementation, mirroring the
// official hyperliquid-python-sdk (signing.py), which is the canonical
// reference for byte layouts. Two distinct schemes:
//
// 1. L1 actions (order, cancel, updateLeverage, …):
//      connectionId = keccak256( msgpack(action)
//                                ++ nonce as 8-byte big-endian
//                                ++ 0x00                      (no vault)
//                                   | 0x01 ++ vault address   (vault)
//                                [++ 0x00 ++ expiresAfter 8B BE] )
//      then EIP-712-sign the "phantom agent"
//        Agent(string source, bytes32 connectionId)
//        source = 'a' mainnet | 'b' testnet
//      under domain {name: 'Exchange', version: '1', chainId: 1337,
//      verifyingContract: 0x0}. chainId 1337 is constant on BOTH networks.
//
// 2. User-signed actions (withdraw3, usdClassTransfer, approveBuilderFee,
//    usdSend): plain EIP-712 over the action's payload fields under domain
//    {name: 'HyperliquidSignTransaction', version: '1',
//     chainId: signatureChainId, verifyingContract: 0x0}. signatureChainId
//    is the chain the wallet signs on — Arbitrum 0xa4b1 per the docs (the
//    Python SDK still hardcodes 0x66eee; its vectors pin that explicitly);
//    `hyperliquidChain` ('Mainnet'|'Testnet') is what scopes the signature.
//
// Msgpack field order is part of the signature — every action map here MUST
// list keys exactly as the Python SDK does, and every new action type must
// land together with a byte known-answer test (see
// test/services/hyperliquid_signing_test.dart).
//
// EIP-712 helpers are duplicated from polymarket_order_v2.dart on purpose:
// they are ~60 stable lines and sharing them would couple two independently
// audited signing paths.

import 'dart:convert';
import 'package:kute/services/hardware/eip712_typed_data.dart';
import 'package:kute/services/hardware/evm_signer.dart';
import 'package:kute/services/hardware/signing_clarity.dart';
import 'dart:typed_data';

import 'package:kute/constants/hyperliquid_constants.dart';
import 'package:kute/services/hyperliquid/hyperliquid_msgpack.dart';
import 'package:pointycastle/digests/keccak.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show EthPrivateKey, EthSignature;

// ──────────────────────────── signature wire ───────────────────────────

class HlSignature {
  final BigInt r;
  final BigInt s;
  final int v; // 27 | 28

  const HlSignature({required this.r, required this.s, required this.v});

  factory HlSignature.fromEthSignature(EthSignature sig) =>
      HlSignature(r: sig.r, s: sig.s, v: sig.v);

  /// Wire shape for POST /exchange. Minimal (unpadded) hex, matching the
  /// Python SDK's `to_hex(int)`.
  Map<String, dynamic> toJson() => {
        'r': '0x${r.toRadixString(16)}',
        's': '0x${s.toRadixString(16)}',
        'v': v,
      };
}

// ───────────────────────────── L1 actions ──────────────────────────────

/// The `connectionId` committed to by an L1-action signature.
Uint8List actionHash({
  required Map<String, dynamic> action,
  required int nonce,
  String? vaultAddress,
  int? expiresAfter,
}) {
  final data = BytesBuilder(copy: false)
    ..add(packMsgpack(action))
    ..add(_be8(nonce));
  if (vaultAddress == null) {
    data.addByte(0x00);
  } else {
    data.addByte(0x01);
    data.add(_addressBytes(vaultAddress));
  }
  if (expiresAfter != null) {
    data.addByte(0x00);
    data.add(_be8(expiresAfter));
  }
  return _keccak256(data.toBytes());
}

/// Final 0x1901 EIP-712 digest of the phantom agent for [connectionId].
Eip712Hashes l1ActionHashes({
  required Uint8List connectionId,
  required bool isMainnet,
}) {
  final domainSep = _hashDomain(
    name: 'Exchange',
    version: '1',
    chainId: HyperliquidConstants.l1ChainId,
    verifyingContract: _zeroAddress,
  );
  final typeHash = _keccak256(
      utf8.encode('Agent(string source,bytes32 connectionId)'));
  final structHash = _keccak256(Uint8List.fromList([
    ...typeHash,
    ..._keccak256(utf8.encode(isMainnet ? 'a' : 'b')),
    ...connectionId,
  ]));
  return Eip712Hashes(domainSep, structHash);
}

/// Full typed data for the phantom agent. Hashes equal [l1ActionHashes]
/// (pinned by test/services/hardware/typed_data_equivalence_test.dart).
Eip712TypedData l1ActionTypedData({
  required Uint8List connectionId,
  required bool isMainnet,
}) =>
    Eip712TypedData(
      types: const {
        kEip712DomainType: kEip712DomainFields,
        'Agent': [
          Eip712Field('source', 'string'),
          Eip712Field('connectionId', 'bytes32'),
        ],
      },
      primaryType: 'Agent',
      domain: {
        'name': 'Exchange',
        'version': '1',
        'chainId': HyperliquidConstants.l1ChainId,
        'verifyingContract': _zeroAddress,
      },
      message: {
        'source': isMainnet ? 'a' : 'b',
        'connectionId': Uint8List.fromList(connectionId),
      },
    );

Future<HlSignature> signL1Action({
  EthPrivateKey? credentials,
  EvmExternalSigner? externalSigner,
  required Map<String, dynamic> action,
  required int nonce,
  String? vaultAddress,
  int? expiresAfter,
  required bool isMainnet,
}) async {
  final connectionId = actionHash(
    action: action,
    nonce: nonce,
    vaultAddress: vaultAddress,
    expiresAfter: expiresAfter,
  );
  final hashes =
      l1ActionHashes(connectionId: connectionId, isMainnet: isMainnet);
  return HlSignature.fromEthSignature(await signTypedDataHashes(
      domain: hashes.domain,
      message: hashes.message,
      kind: hyperliquidL1ActionKind(action),
      typedData: () =>
          l1ActionTypedData(connectionId: connectionId, isMainnet: isMainnet),
      credentials: credentials,
      externalSigner: externalSigner));
}

// ─────────────────────────── user-signed actions ───────────────────────

typedef HlTypedField = ({String name, String type});

/// Payload type lists — names, types AND order exactly per the Python SDK.
const List<HlTypedField> withdrawSignTypes = [
  (name: 'hyperliquidChain', type: 'string'),
  (name: 'destination', type: 'string'),
  (name: 'amount', type: 'string'),
  (name: 'time', type: 'uint64'),
];
const List<HlTypedField> usdSendSignTypes = withdrawSignTypes;
const List<HlTypedField> spotSendSignTypes = [
  (name: 'hyperliquidChain', type: 'string'),
  (name: 'destination', type: 'string'),
  (name: 'token', type: 'string'),
  (name: 'amount', type: 'string'),
  (name: 'time', type: 'uint64'),
];
const List<HlTypedField> usdClassTransferSignTypes = [
  (name: 'hyperliquidChain', type: 'string'),
  (name: 'amount', type: 'string'),
  (name: 'toPerp', type: 'bool'),
  (name: 'nonce', type: 'uint64'),
];
const List<HlTypedField> approveBuilderFeeSignTypes = [
  (name: 'hyperliquidChain', type: 'string'),
  (name: 'maxFeeRate', type: 'string'),
  (name: 'builder', type: 'address'),
  (name: 'nonce', type: 'uint64'),
];

const String withdrawPrimaryType = 'HyperliquidTransaction:Withdraw';
const String usdSendPrimaryType = 'HyperliquidTransaction:UsdSend';
const String spotSendPrimaryType = 'HyperliquidTransaction:SpotSend';
const String usdClassTransferPrimaryType =
    'HyperliquidTransaction:UsdClassTransfer';
const String approveBuilderFeePrimaryType =
    'HyperliquidTransaction:ApproveBuilderFee';

/// Final 0x1901 digest for a user-signed action. [message] must already
/// contain every field listed in [fields] (including `hyperliquidChain`).
Eip712Hashes userSignedActionHashes({
  required String primaryType,
  required List<HlTypedField> fields,
  required Map<String, dynamic> message,
  int signatureChainId = HyperliquidConstants.signatureChainId,
}) {
  final domainSep = _hashDomain(
    name: 'HyperliquidSignTransaction',
    version: '1',
    chainId: signatureChainId,
    verifyingContract: _zeroAddress,
  );

  final typeString = '$primaryType('
      '${fields.map((f) => '${f.type} ${f.name}').join(',')})';
  final encoded = BytesBuilder(copy: false)
    ..add(_keccak256(utf8.encode(typeString)));
  for (final f in fields) {
    final value = message[f.name];
    if (value == null) {
      throw ArgumentError('user-signed action missing field ${f.name}');
    }
    switch (f.type) {
      case 'string':
        encoded.add(_keccak256(utf8.encode(value as String)));
      case 'uint64':
        encoded.add(_encodeUint(BigInt.from(value as int)));
      case 'bool':
        encoded.add(_encodeUint((value as bool) ? BigInt.one : BigInt.zero));
      case 'address':
        encoded.add(_encodeAddressPadded(value as String));
      default:
        throw ArgumentError('unsupported EIP-712 field type ${f.type}');
    }
  }
  return Eip712Hashes(domainSep, _keccak256(encoded.toBytes()));
}

/// Full typed data for a user-signed action. Hashes equal
/// [userSignedActionHashes]; only the listed [fields] are signed, so the
/// POSTed `type` and `signatureChainId` keys are left out of the message.
Eip712TypedData userSignedActionTypedData({
  required String primaryType,
  required List<HlTypedField> fields,
  required Map<String, dynamic> message,
  int signatureChainId = HyperliquidConstants.signatureChainId,
}) =>
    Eip712TypedData(
      types: {
        kEip712DomainType: kEip712DomainFields,
        primaryType: [for (final f in fields) Eip712Field(f.name, f.type)],
      },
      primaryType: primaryType,
      domain: {
        'name': 'HyperliquidSignTransaction',
        'version': '1',
        'chainId': signatureChainId,
        'verifyingContract': _zeroAddress,
      },
      message: {for (final f in fields) f.name: message[f.name]},
    );

/// Signs a user-signed action, augmenting [action] in place with the
/// `signatureChainId` and `hyperliquidChain` fields exactly like the Python
/// SDK — the caller must POST the same (augmented) map it passed in.
///
/// [signatureChainId] defaults to Arbitrum (0xa4b1) for every account; it
/// only changes the domain chainId and the POSTed hex field. The SDK
/// known-answer tests pass the SDK's 0x66eee explicitly.
Future<HlSignature> signUserSignedAction({
  EthPrivateKey? credentials,
  EvmExternalSigner? externalSigner,
  required Map<String, dynamic> action,
  required List<HlTypedField> fields,
  required String primaryType,
  required bool isMainnet,
  int signatureChainId = HyperliquidConstants.signatureChainId,
}) async {
  action['signatureChainId'] = '0x${signatureChainId.toRadixString(16)}';
  action['hyperliquidChain'] = isMainnet ? 'Mainnet' : 'Testnet';
  final hashes = userSignedActionHashes(
    primaryType: primaryType,
    fields: fields,
    message: action,
    signatureChainId: signatureChainId,
  );
  return HlSignature.fromEthSignature(await signTypedDataHashes(
      domain: hashes.domain,
      message: hashes.message,
      kind: hyperliquidUserSignedKind(primaryType),
      typedData: () => userSignedActionTypedData(
          primaryType: primaryType,
          fields: fields,
          message: action,
          signatureChainId: signatureChainId),
      credentials: credentials,
      externalSigner: externalSigner));
}

// ───────────────────────── action map builders ─────────────────────────
// Key order in these maps is load-bearing (msgpack — see header). Do not
// reorder, and add a KAT for every new builder.

class HlBuilderFee {
  final String address;
  final int feeTenthsBp;
  const HlBuilderFee({required this.address, required this.feeTenthsBp});
}

class HlOrderWire {
  final int assetId;
  final bool isBuy;
  final String px;
  final String sz;
  final bool reduceOnly;
  final Map<String, dynamic> orderType; // limitOrderType / triggerOrderType
  final String? cloid; // 16-byte 0x hex

  const HlOrderWire({
    required this.assetId,
    required this.isBuy,
    required this.px,
    required this.sz,
    required this.reduceOnly,
    required this.orderType,
    this.cloid,
  });

  Map<String, dynamic> toWire() => {
        'a': assetId,
        'b': isBuy,
        'p': px,
        's': sz,
        'r': reduceOnly,
        't': orderType,
        if (cloid != null) 'c': cloid,
      };
}

/// tif ∈ {'Gtc', 'Ioc', 'Alo'}.
Map<String, dynamic> limitOrderType(String tif) => {
      'limit': {'tif': tif},
    };

/// tpsl ∈ {'tp', 'sl'}. [triggerPx] must already be wire-rounded.
Map<String, dynamic> triggerOrderType({
  required bool isMarket,
  required String triggerPx,
  required String tpsl,
}) =>
    {
      'trigger': {
        'isMarket': isMarket,
        'triggerPx': triggerPx,
        'tpsl': tpsl,
      },
    };

Map<String, dynamic> buildOrderAction({
  required List<HlOrderWire> orders,
  String grouping = 'na',
  HlBuilderFee? builder,
}) =>
    {
      'type': 'order',
      'orders': [for (final o in orders) o.toWire()],
      'grouping': _validGrouping(grouping),
      if (builder != null)
        'builder': {
          'b': builder.address.toLowerCase(),
          'f': builder.feeTenthsBp,
        },
    };

String _validGrouping(String grouping) {
  const allowed = {'na', 'normalTpsl', 'positionTpsl'};
  if (!allowed.contains(grouping)) {
    throw ArgumentError('invalid order grouping: $grouping');
  }
  return grouping;
}

/// Replace a resting order in place. The venue keeps the order's position
/// in its books semantics as a modify, not a cancel plus a fresh place, so
/// a moved limit can never briefly exist twice and double fill.
/// https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint
Map<String, dynamic> buildModifyAction({
  required int oid,
  required HlOrderWire order,
}) =>
    {
      'type': 'modify',
      'oid': oid,
      'order': order.toWire(),
    };

Map<String, dynamic> buildCancelAction(
        List<({int assetId, int oid})> cancels) =>
    {
      'type': 'cancel',
      'cancels': [
        for (final c in cancels) {'a': c.assetId, 'o': c.oid},
      ],
    };

Map<String, dynamic> buildCancelByCloidAction(
        List<({int assetId, String cloid})> cancels) =>
    {
      'type': 'cancelByCloid',
      'cancels': [
        for (final c in cancels) {'asset': c.assetId, 'cloid': c.cloid},
      ],
    };

Map<String, dynamic> buildUpdateLeverageAction({
  required int assetId,
  required bool isCross,
  required int leverage,
}) =>
    {
      'type': 'updateLeverage',
      'asset': assetId,
      'isCross': isCross,
      'leverage': leverage,
    };

/// Add (positive) or remove (negative) isolated margin on a position.
/// [ntli] is the notional in USDC base units (amount × 1e6, int) — matches
/// the Python SDK's float_to_usd_int. `isBuy` is always true per the SDK.
Map<String, dynamic> buildUpdateIsolatedMarginAction({
  required int assetId,
  required int ntli,
}) =>
    {
      'type': 'updateIsolatedMargin',
      'asset': assetId,
      'isBuy': true,
      'ntli': ntli,
    };

/// User-signed action maps (order here is for the POSTed JSON only — the
/// EIP-712 struct is built from the typed-field lists above).
Map<String, dynamic> buildUsdSendAction({
  required String destination,
  required String amount,
  required int time,
}) => {
  'destination': destination,
  'amount': amount,
  'time': time,
  'type': 'usdSend',
};

Map<String, dynamic> buildSpotSendAction({
  required String destination,
  required String token,
  required String amount,
  required int time,
}) => {
  'destination': destination,
  'amount': amount,
  'token': token,
  'time': time,
  'type': 'spotSend',
};

Map<String, dynamic> buildWithdraw3Action({
  required String destination,
  required String amount,
  required int time,
}) =>
    {
      'destination': destination,
      'amount': amount,
      'time': time,
      'type': 'withdraw3',
    };

/// A TWAP order (`twapOrder`) — the exchange slices [sizeWire] into
/// sub-orders spread over [minutes] and executes them itself. Signed as an
/// L1 action (same path as `order`/`cancel`: signL1Action → _submitL1Action).
///
/// Wire shape verified against the official Hyperliquid docs (exchange-
/// endpoint → "twapOrder": "a is asset, b is isBuy, s is size, r is
/// reduceOnly, m is minutes, t is randomize") and a worked sign_l1_action
/// example. NOTE: hyperliquid-python-sdk master ships NO twap helper (0
/// hits for "twap"), so the docs — not the SDK — are the canonical
/// reference here. The key order below IS the documented (canonical
/// msgpack) order; do not reorder. [sizeWire] must already be a
/// floatToWire string; [minutes] ∈ 1..1440.
Map<String, dynamic> buildTwapOrderAction({
  required int assetId,
  required bool isBuy,
  required String sizeWire,
  required bool reduceOnly,
  required int minutes,
  required bool randomize,
}) =>
    {
      'type': 'twapOrder',
      'twap': {
        'a': assetId,
        'b': isBuy,
        's': sizeWire,
        'r': reduceOnly,
        'm': minutes,
        't': randomize,
      },
    };

/// Cancels a running TWAP (`twapCancel`). Docs shape: `a` is asset,
/// `t` is the twapId the `twapOrder` response returned. L1-signed like
/// every other trade action; key order is the documented canonical one.
Map<String, dynamic> buildTwapCancelAction({
  required int assetId,
  required int twapId,
}) =>
    {
      'type': 'twapCancel',
      'a': assetId,
      't': twapId,
    };

Map<String, dynamic> buildUsdClassTransferAction({
  required String amount,
  required bool toPerp,
  required int nonce,
}) =>
    {
      'type': 'usdClassTransfer',
      'amount': amount,
      'toPerp': toPerp,
      'nonce': nonce,
    };

Map<String, dynamic> buildApproveBuilderFeeAction({
  required String builder,
  required String maxFeeRate,
  required int nonce,
}) =>
    {
      'maxFeeRate': maxFeeRate,
      'builder': builder,
      'nonce': nonce,
      'type': 'approveBuilderFee',
    };

/// Names the account's referrer (`setReferrer`). L1-signed by the account's
/// own key, key order as Exchange.set_referrer builds it in the Python SDK
/// (pinned by the `set_referrer` vector in fixtures/hl_vectors.json).
Map<String, dynamic> buildSetReferrerAction({required String code}) => {
      'type': 'setReferrer',
      'code': code,
    };

// ──────────────────────────── EIP-712 internals ────────────────────────

const String _zeroAddress = '0x0000000000000000000000000000000000000000';

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
    ..._encodeAddressPadded(verifyingContract),
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

/// 20-byte address left-padded to a 32-byte EIP-712 word.
Uint8List _encodeAddressPadded(String address) {
  final bytes = Uint8List(32);
  bytes.setRange(12, 32, _addressBytes(address));
  return bytes;
}

/// Raw 20 bytes of an 0x address (used unpadded in actionHash vault suffix).
Uint8List _addressBytes(String address) {
  final clean = address.replaceFirst('0x', '');
  if (clean.length != 40) {
    throw ArgumentError(
        'Address must be 20 bytes (40 hex chars), got ${clean.length}');
  }
  final bytes = Uint8List(20);
  for (var i = 0; i < 20; i++) {
    bytes[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return bytes;
}

Uint8List _be8(int value) {
  final bytes = Uint8List(8);
  var v = value;
  for (var i = 7; i >= 0; i--) {
    bytes[i] = v & 0xff;
    v >>= 8;
  }
  return bytes;
}

class Eip712Hashes {
  final Uint8List domain;
  final Uint8List message;
  Eip712Hashes(this.domain, this.message);
  Uint8List get digest => typedDataDigest(domain, message);
}

Uint8List l1ActionDigest({required Uint8List connectionId, required bool isMainnet}) =>
    l1ActionHashes(connectionId: connectionId, isMainnet: isMainnet).digest;
Uint8List userSignedActionDigest({required String primaryType,
  required List<HlTypedField> fields, required Map<String, dynamic> message,
  int signatureChainId = HyperliquidConstants.signatureChainId}) =>
    userSignedActionHashes(primaryType: primaryType, fields: fields,
      message: message, signatureChainId: signatureChainId).digest;
