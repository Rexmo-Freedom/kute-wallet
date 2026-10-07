// lib/services/polymarket/market_protocol.dart
//
// Polymarket Protocol V2 markets (docs.polymarket.com/migrate/polymarket-v2).
//
// Every Gamma market carries a `version`. The app reads both kinds:
//
//   version | outcome ids          | ledger          | exchange   | domain
//   "v1"    | clobTokenIds (JSON   | Conditional     | E111 / e222 | "2"
//           |  text of decimals)   |  Tokens (CTF)   | (negRisk)  |
//   "v2"    | positionIds (array   | PositionManager | ExchangeV3 | "3"
//           |  of decimals)        |                 | (one, for  |
//           |                      |                 |  binary and|
//           |                      |                 |  neg-risk) |
//
// The ids are chosen by `version`, never by which field is present: v1
// markets also list `positionIds` (their legs for combos), and v2 markets
// may still list `clobTokenIds`. A missing version is a v1 market; any
// other value is a protocol this build does not know, and such a market
// gets no tradeable ids at all (shown, never signed for).
//
// At signing time the protocol is read from the order's token id itself,
// as `@polymarket/client` does (`isV2PositionId`): a V2 position id has
// its module (1 binary, 2 neg-risk, 3 combinatorial) in the top byte and
// 64 reserved bits (40..103) at zero, while a CTF token id is a keccak
// hash. So a V2 order can only be signed for ExchangeV3 under domain "3",
// and a CTF order only for the two CTF exchanges under domain "2",
// whichever path built it ([PolyOrderVenue.forToken], asserted again in
// the signer).
//
// Regular CLOB V2 orders keep the CTFExchangeV2 struct, millisecond
// timestamps and the existing POST /order body (the SDK's
// `createUnsignedOrder` uses Date.now() for both); only the RFQ combo
// order uses seconds.

import 'dart:convert';

import 'package:flutter/foundation.dart' show kReleaseMode, visibleForTesting;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:kute/constants/polymarket_constants.dart';
import 'package:kute/services/runtime_capabilities_service.dart';

enum PolyProtocol {
  /// CTF market (`version` "v1" or absent): `clobTokenIds`, Exchange V2.
  v1,

  /// Polymarket Protocol V2 market: `positionIds`, ExchangeV3.
  v2,

  /// A `version` this build does not know: shown, never traded.
  unsupported;

  /// The categorical value analytics carries (`market_protocol`).
  String get wire => switch (this) {
        PolyProtocol.v1 => 'v1',
        PolyProtocol.v2 => 'v2',
        PolyProtocol.unsupported => 'unsupported',
      };
}

/// Thrown before anything is signed for a V2 market this account cannot
/// trade now: the `polymarket.protocol_v2` switch is off, or the account
/// is a Ledger (V2 stays view-only there for now). English on purpose;
/// screens show the existing "unavailable" copy.
class PolymarketProtocolUnavailable implements Exception {
  const PolymarketProtocolUnavailable(this.reason);

  /// `switched_off` | `hardware` | `unsupported`.
  final String reason;

  @override
  String toString() => 'Polymarket protocol unavailable: $reason';
}

/// Thrown by the signer when an order's exchange or domain does not match
/// the protocol of its token id. Nothing is signed.
class PolymarketOrderVenueMismatch implements Exception {
  const PolymarketOrderVenueMismatch(this.detail);
  final String detail;

  @override
  String toString() => 'Polymarket order venue mismatch: $detail';
}

/// Where an order for one token id is signed.
class PolyOrderVenue {
  const PolyOrderVenue._(this.protocol, this.exchange, this.domainVersion);

  final PolyProtocol protocol;

  /// The EIP-712 verifying contract.
  final String exchange;

  /// The EIP-712 domain version ("2" CTF, "3" ExchangeV3).
  final String domainVersion;

  bool get isV2 => protocol == PolyProtocol.v2;

  /// The venue for [tokenId]: ExchangeV3 / "3" for a V2 position id, else
  /// the CTF exchange for [negRisk] / "2". `negRisk` does not choose the
  /// V2 exchange: binary and neg-risk V2 markets share ExchangeV3.
  static PolyOrderVenue forToken(String tokenId, {required bool negRisk}) {
    if (PolyMarketProtocol.isV2PositionId(tokenId)) {
      return const PolyOrderVenue._(
          PolyProtocol.v2,
          PolymarketConstants.comboExchangeV3Address,
          PolymarketConstants.comboExchangeEip712DomainVersion);
    }
    return PolyOrderVenue._(
        PolyProtocol.v1,
        negRisk
            ? PolymarketConstants.negRiskExchangeAddress
            : PolymarketConstants.exchangeAddress,
        PolymarketConstants.exchangeEip712DomainVersion);
  }

  /// Throws [PolymarketOrderVenueMismatch] unless ([verifyingContract],
  /// [domainVersion]) is a venue [tokenId]'s protocol signs for.
  static void assertMatches({
    required String tokenId,
    required String verifyingContract,
    required String domainVersion,
  }) {
    final contract = verifyingContract.toLowerCase();
    if (PolyMarketProtocol.isV2PositionId(tokenId)) {
      if (contract !=
              PolymarketConstants.comboExchangeV3Address.toLowerCase() ||
          domainVersion !=
              PolymarketConstants.comboExchangeEip712DomainVersion) {
        throw const PolymarketOrderVenueMismatch(
            'V2 position signed outside ExchangeV3 / domain 3');
      }
      return;
    }
    final ctfExchanges = {
      PolymarketConstants.exchangeAddress.toLowerCase(),
      PolymarketConstants.negRiskExchangeAddress.toLowerCase(),
    };
    if (!ctfExchanges.contains(contract) ||
        domainVersion != PolymarketConstants.exchangeEip712DomainVersion) {
      throw const PolymarketOrderVenueMismatch(
          'CTF token signed outside the CTF exchanges / domain 2');
    }
  }
}

abstract final class PolyMarketProtocol {
  /// Runtime kill switch for trading V2 markets. Enabled by default in the
  /// backend policy; off falls back to view-only V2 markets (V1 trading
  /// and V2 claims are untouched).
  static const String capability = 'polymarket.protocol_v2';

  static const int _moduleBinary = 1;
  static const int _moduleNegRisk = 2;
  static const int _moduleCombinatorial = 3;
  static final BigInt _maxUint256 = (BigInt.one << 256) - BigInt.one;
  static final BigInt _reservedMask = ((BigInt.one << 64) - BigInt.one) << 40;

  /// The protocol of a Gamma market JSON row.
  static PolyProtocol of(Map<String, dynamic> market) {
    if (debugTreatsAsV2(market)) return PolyProtocol.v2;
    final raw = market['version'];
    if (raw == null) return PolyProtocol.v1;
    final v = '$raw'.trim().toLowerCase();
    if (v.isEmpty || v == 'v1') return PolyProtocol.v1;
    if (v == 'v2') return PolyProtocol.v2;
    return PolyProtocol.unsupported;
  }

  /// The tradeable outcome ids of a Gamma market, in `outcomes` order:
  /// `positionIds` for V2, `clobTokenIds` for V1, none for an unknown
  /// version. A V2 id that is not a decimal string makes the whole list
  /// empty (the docs: reject non-decimal ids).
  static List<String> outcomeIds(Map<String, dynamic> market) {
    return switch (of(market)) {
      PolyProtocol.v1 => _ids(market['clobTokenIds'], decimalOnly: false),
      PolyProtocol.v2 => _ids(market['positionIds'], decimalOnly: true),
      PolyProtocol.unsupported => const [],
    };
  }

  /// [market] with `clobTokenIds` holding the ids to trade, for the
  /// readers that only know that key (the SDK's `Market.fromJson`, the
  /// game lines). A V1 market comes back unchanged.
  static Map<String, dynamic> withTradingIds(Map<String, dynamic> market) {
    if (of(market) == PolyProtocol.v1) return market;
    return {...market, 'clobTokenIds': jsonEncode(outcomeIds(market))};
  }

  /// [event] with every nested market passed through [withTradingIds].
  /// Twin markets (a V1 and a V2 market with the same title in one event)
  /// are reduced to one first ([withoutTwins]).
  static Map<String, dynamic> eventWithTradingIds(Map<String, dynamic> event) {
    final raw = event['markets'];
    if (raw is! List) return event;
    final markets = withoutTwins(raw);
    var changed = markets.length != raw.length;
    final out = [
      for (final m in markets)
        if (m is Map<String, dynamic>)
          (() {
            final n = withTradingIds(m);
            if (!identical(n, m)) changed = true;
            return n;
          })()
        else
          m,
    ];
    return changed ? {...event, 'markets': out} : event;
  }

  /// [markets] (one event's Gamma markets) with V1/V2 twins reduced to
  /// one: when a V1 and a V2 market carry the same `groupItemTitle` (else
  /// `question`), only the one to trade stays, the V2 market while it
  /// accepts orders and V2 trading is on, else the V1 one. Order is kept.
  /// Positions are unaffected: a holding in the dropped twin still shows,
  /// sells and claims by its own token id.
  static List<dynamic> withoutTwins(List<dynamic> markets) {
    String? key(dynamic m) {
      if (m is! Map<String, dynamic>) return null;
      final title = '${m['groupItemTitle'] ?? ''}'.trim().isNotEmpty
          ? '${m['groupItemTitle']}'
          : '${m['question'] ?? ''}';
      final k = title.trim().toLowerCase();
      return k.isEmpty ? null : k;
    }

    final byKey = <String, List<Map<String, dynamic>>>{};
    for (final m in markets) {
      final k = key(m);
      if (k != null) (byKey[k] ??= []).add(m as Map<String, dynamic>);
    }
    final drop = <Map<String, dynamic>>{};
    for (final group in byKey.values) {
      final v1 = group.where((m) => of(m) == PolyProtocol.v1).toList();
      final v2 = group.where((m) => of(m) == PolyProtocol.v2).toList();
      if (v1.isEmpty || v2.isEmpty) continue;
      final v2Live = tradingEnabled &&
          v2.any((m) =>
              m['acceptingOrders'] != false &&
              m['closed'] != true &&
              m['active'] != false);
      drop.addAll(v2Live ? v1 : v2);
    }
    if (drop.isEmpty) return markets;
    return [
      for (final m in markets)
        if (!drop.any((d) => identical(d, m))) m,
    ];
  }

  /// Whether [id] is a Protocol V2 position id: module 1–3 in the top
  /// byte and the 64 reserved bits clear. A CTF token id (a keccak hash)
  /// is not.
  static bool isV2PositionId(String id) {
    final v = BigInt.tryParse(id.trim());
    if (v == null || v.isNegative || v > _maxUint256) return false;
    final module = (v >> 248).toInt();
    if (module != _moduleBinary &&
        module != _moduleNegRisk &&
        module != _moduleCombinatorial) {
      return false;
    }
    return v & _reservedMask == BigInt.zero;
  }

  /// The CLOB `asset_type` for a conditional balance of [tokenId].
  static String conditionalAssetType(String tokenId) =>
      isV2PositionId(tokenId) ? 'CONDITIONAL-V2' : 'CONDITIONAL';

  /// A V2 condition id, as Gamma and the Data API may carry it: 31 bytes
  /// (62 hex), or 32 bytes right-padded with a zero outcome byte. Returns
  /// the 31-byte form (0x + 62 lowercase hex), or null for a CTF
  /// condition id.
  static String? v2ConditionId(String conditionId) {
    final clean = conditionId.trim().toLowerCase().replaceFirst('0x', '');
    if (!RegExp(r'^[0-9a-f]+$').hasMatch(clean)) return null;
    if (clean.length == 62) {
      final asPosition = BigInt.parse('${clean}00', radix: 16);
      return isV2PositionId(asPosition.toString()) ? '0x$clean' : null;
    }
    if (clean.length == 64 && clean.endsWith('00')) {
      final v = BigInt.parse(clean, radix: 16);
      return isV2PositionId(v.toString())
          ? '0x${clean.substring(0, 62)}'
          : null;
    }
    return null;
  }

  /// The 31-byte condition id and outcome index of a V2 position id
  /// (`conditionId = bytes31(positionId >> 8)`, `outcome = positionId & 0xff`).
  static ({String conditionId, int outcomeIndex}) splitV2(String positionId) {
    if (!isV2PositionId(positionId)) {
      throw ArgumentError('not a V2 position id');
    }
    final hex =
        BigInt.parse(positionId.trim()).toRadixString(16).padLeft(64, '0');
    final outcome = int.parse(hex.substring(62), radix: 16);
    if (outcome > 1) throw ArgumentError('not a YES/NO position');
    return (conditionId: '0x${hex.substring(0, 62)}', outcomeIndex: outcome);
  }

  /// The V2 position id of [outcomeIndex] (0 YES, 1 NO) under a 31-byte
  /// [conditionId31].
  static String v2PositionId(String conditionId31, int outcomeIndex) {
    final clean = conditionId31.toLowerCase().replaceFirst('0x', '');
    if (clean.length != 62 || (outcomeIndex != 0 && outcomeIndex != 1)) {
      throw ArgumentError('bad V2 condition or outcome');
    }
    return BigInt.parse(
            '$clean${outcomeIndex.toRadixString(16).padLeft(2, '0')}',
            radix: 16)
        .toString();
  }

  /// Whether V2 trading is switched on now. Gating is emergency-only: a
  /// policy that does not list the switch yet (a backend from before it)
  /// leaves V2 on; only an explicit denial turns it off.
  static bool get tradingEnabled {
    if (_workerTradingEnabled case final enabled?) return enabled;
    final d = RuntimeCapabilitiesService.instance.decision(capability);
    if (d.allowed && !d.comingSoon) return true;
    return d.reason == 'unknown_capability';
  }

  // ── Parsing in a worker isolate ─────────────────────────────────────
  //
  // A worker isolate starts with empty statics: no runtime policy and no
  // `.env`. A Gamma list parsed there must still drop V1/V2 twins and
  // read debug V2 markets the way the app isolate would, so the parse
  // carries these two switches in with it.

  static bool? _workerTradingEnabled;

  /// What a market parse reads from this isolate, for [adoptWorkerState]
  /// in the worker.
  static ({bool tradingEnabled, Set<String> debugV2Ids}) workerState() => (
        tradingEnabled: tradingEnabled,
        debugV2Ids: kReleaseMode
            ? const <String>{}
            : debugV2MarketIdsOverride ?? (_debugIds ??= _readDebugIds()),
      );

  /// Called first in a worker isolate, with [workerState] of the app
  /// isolate.
  static void adoptWorkerState(
      ({bool tradingEnabled, Set<String> debugV2Ids}) state) {
    _workerTradingEnabled = state.tradingEnabled;
    debugV2MarketIdsOverride = state.debugV2Ids;
  }

  /// Throws [PolymarketProtocolUnavailable] when an order for [tokenId]
  /// may not be signed now. V1 tokens always pass.
  static void ensureSignable(String tokenId, {bool hardware = false}) {
    if (!isV2PositionId(tokenId)) return;
    if (hardware) throw const PolymarketProtocolUnavailable('hardware');
    if (!tradingEnabled) {
      throw const PolymarketProtocolUnavailable('switched_off');
    }
  }

  /// The categorical protocol of a token id, for analytics.
  static String wireForToken(String tokenId) =>
      isV2PositionId(tokenId) ? 'v2' : 'v1';

  // ── Debug: route chosen markets through the V2 path ────────────────
  //
  // No V2 market is live yet. A debug build may name Gamma market ids in
  // `.env` (`PM_DEBUG_V2_MARKETS=123,456`) to have them read as V2: their
  // `positionIds` become the traded ids, so the slip, the book reads and
  // the ExchangeV3 signing run end to end (the CLOB decides whether it
  // takes the order). A release build never reads the key.

  @visibleForTesting
  static Set<String>? debugV2MarketIdsOverride;

  static Set<String>? _debugIds;

  static bool debugTreatsAsV2(Map<String, dynamic> market) {
    if (kReleaseMode) return false;
    final ids = debugV2MarketIdsOverride ?? (_debugIds ??= _readDebugIds());
    if (ids.isEmpty || market['positionIds'] == null) return false;
    final id = market['id']?.toString();
    return id != null && ids.contains(id);
  }

  static Set<String> _readDebugIds() {
    try {
      if (!dotenv.isInitialized) return const {};
      final raw = dotenv.env['PM_DEBUG_V2_MARKETS'] ?? '';
      return {
        for (final s in raw.split(','))
          if (s.trim().isNotEmpty) s.trim(),
      };
    } catch (_) {
      return const {};
    }
  }

  /// The ids in [v] (a list or its JSON text). V2 ids must all be
  /// decimal (else none are returned); V1 ids are read as before.
  static List<String> _ids(dynamic v, {required bool decimalOnly}) {
    if (v == null) return const [];
    dynamic parsed = v;
    if (v is String) {
      try {
        parsed = jsonDecode(v);
      } catch (_) {
        return const [];
      }
    }
    if (parsed is! List) return const [];
    final out = <String>[];
    for (final e in parsed) {
      final s = '$e'.trim();
      if (decimalOnly && !RegExp(r'^[0-9]+$').hasMatch(s)) return const [];
      out.add(decimalOnly ? s : '$e');
    }
    return out;
  }
}
