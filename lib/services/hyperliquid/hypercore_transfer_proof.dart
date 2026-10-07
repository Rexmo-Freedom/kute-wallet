import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:kute/constants/hyperliquid_constants.dart';
import 'package:kute/services/security/address_guard.dart';

// Orchestra identifies its native HyperCore route with a zero placeholder.
// Legacy spot signatures require the canonical spotMeta token ID; current
// Flashnet funding uses perpetuals USDC via usdSend.
const orchestraHypercoreUsdcId = '0x00000000000000000000000000000000';
const hypercoreUsdcTokenId = '0x6d1e7cde53ba9467b783cb7c530ce054'; // gitleaks:allow (public HyperCore token id)
const hypercoreUsdcToken = 'USDC:$hypercoreUsdcTokenId';

bool isCanonicalHypercoreUsdcMetadata(Object? response) {
  if (response is! Map || response['tokens'] is! List) return false;
  final usdc = (response['tokens'] as List)
      .whereType<Map>()
      .where((token) => token['name'] == 'USDC')
      .toList();
  return usdc.length == 1 &&
      usdc.single['tokenId'] == hypercoreUsdcTokenId &&
      usdc.single['index'] == 0 &&
      usdc.single['weiDecimals'] == 8 &&
      usdc.single['isCanonical'] == true;
}

/// Checks the protocol identity independently of Orchestra's route catalog,
/// before signing. An unexpected or unavailable identity stops the transfer.
Future<void> verifyHypercoreUsdcMetadata({http.Client? client}) async {
  final response = await _hypercorePublicPost(
      HyperliquidConstants.infoUri, {'type': 'spotMeta'},
      client: client);
  if (!isCanonicalHypercoreUsdcMetadata(response)) {
    throw StateError('Native USDC token identity could not be verified.');
  }
}

Future<Object?> _hypercorePublicPost(Uri uri, Map<String, Object> value,
    {http.Client? client}) async {
  final body = jsonEncode(value);
  final response = await (client == null
          ? http.post(uri,
              headers: {'content-type': 'application/json'}, body: body)
          : client.post(uri,
              headers: {'content-type': 'application/json'}, body: body))
      .timeout(const Duration(seconds: 12));
  if (response.statusCode != 200) {
    throw StateError('Native transfer lookup unavailable');
  }
  return jsonDecode(response.body);
}

String hypercoreUsdcWire(BigInt units) {
  if (units <= BigInt.zero) throw ArgumentError.value(units, 'units');
  final digits = units.toString().padLeft(9, '0');
  return '${digits.substring(0, digits.length - 8)}.${digits.substring(digits.length - 8)}';
}

/// Orchestra quotes use eight-decimal units; perpetual USDC transfers use
/// six. Reject dust instead of changing the approved deposit amount.
String hypercorePerpUsdcWire(BigInt units) {
  if (units <= BigInt.zero || units % BigInt.from(100) != BigInt.zero) {
    throw ArgumentError('Perpetual USDC amount must have at most six decimals');
  }
  final wire = hypercoreUsdcWire(units);
  return wire.substring(0, wire.length - 2);
}

bool usesHypercorePerpFunding(String? routeVersion) => const {
      'hypercore_to_spark_perps_v2',
      'hypercore_to_spark_usd_perps_v2',
      'hypercore_to_ledger_btc_perps_v2',
    }.contains(routeVersion);

BigInt? _units(Object? value) {
  final text = value?.toString() ?? '';
  if (!RegExp(r'^\d+(?:\.\d{1,8})?$').hasMatch(text)) return null;
  final parts = text.split('.');
  return BigInt.tryParse(
      parts.first + (parts.length == 1 ? '' : parts[1]).padRight(8, '0'));
}

/// Matches native spot cash only. Ambiguous, differently timed or differently
/// directed transfers are never accepted as proof for this operation.
String? matchHypercoreSpotTransfer({
  required Iterable<dynamic> updates,
  required String source,
  required String destination,
  required BigInt amountBaseUnits,
  required int nonce,
  int timeWindowMs = 120000,
}) {
  final matches = <String>{};
  for (final update in updates) {
    if (update is! Map) continue;
    final time = update['time'];
    final hash = update['hash'];
    final delta = update['delta'];
    if (time is! num ||
        time < nonce ||
        time > nonce + timeWindowMs ||
        hash is! String ||
        !RegExp(r'^0x[0-9a-fA-F]{64}$').hasMatch(hash) ||
        delta is! Map ||
        delta['type'] != 'spotTransfer') {
      continue;
    }
    final token = delta['token'];
    if (token != 'USDC' && token != hypercoreUsdcToken) continue;
    if (!sameEvmAddress('${delta['user']}', source) ||
        !sameEvmAddress('${delta['destination']}', destination) ||
        _units(delta['amount']) != amountBaseUnits) {
      continue;
    }
    matches.add(hash);
  }
  return matches.length == 1 ? matches.single : null;
}

/// Confirms the exact signed action, including its nonce. Ledger event time
/// is block time, which can be earlier than a device clock's signing time.
bool verifyHypercoreSpotTransferDetails({
  required Object? response,
  required String hash,
  required String source,
  required String destination,
  required BigInt amountBaseUnits,
  required int nonce,
}) {
  if (response is! Map || response['type'] != 'txDetails') return false;
  final tx = response['tx'];
  if (tx is! Map ||
      !tx.containsKey('error') ||
      tx['error'] != null ||
      tx['hash'] != hash ||
      !sameEvmAddress('${tx['user']}', source)) {
    return false;
  }
  final action = tx['action'];
  return action is Map &&
      action['type'] == 'spotSend' &&
      action['time'] == nonce &&
      action['token'] == hypercoreUsdcToken &&
      sameEvmAddress('${action['destination']}', destination) &&
      _units(action['amount']) == amountBaseUnits;
}

/// Explorer `txDetails` is undocumented, so it is only a best-effort
/// cross-check on top of the documented `userNonFundingLedgerUpdates`
/// proof: an answer in the known shape that contradicts the transfer
/// rejects the candidate (false); an unreachable explorer or an unknown
/// shape leaves the ledger match standing (null). Exposed for tests.
Future<bool?> explorerVerdict(
    Future<Object?> Function() read, bool Function(Object? response) verify) async {
  Object? response;
  try {
    response = await read();
  } catch (_) {
    return null;
  }
  if (response is! Map || response['type'] != 'txDetails') return null;
  final tx = response['tx'];
  if (tx is! Map || !tx.containsKey('error')) return null;
  return verify(response);
}

Uri get _explorerUri => Uri.parse(HyperliquidConstants.isMainnet
    ? 'https://rpc.hyperliquid.xyz/explorer'
    : 'https://rpc.hyperliquid-testnet.xyz/explorer');

Future<String?> readHypercoreSpotTransferHash({
  required String source,
  required String destination,
  required BigInt amountBaseUnits,
  required int nonce,
  http.Client? client,
}) async {
  Future<Object?> post(Uri uri, Map<String, Object> value) =>
      _hypercorePublicPost(uri, value, client: client);

  const clockBufferMs = 120000;
  final data = await post(HyperliquidConstants.infoUri, {
    'type': 'userNonFundingLedgerUpdates',
    'user': source,
    'startTime': nonce - clockBufferMs,
    'endTime': nonce + clockBufferMs,
  });
  if (data is! List) {
    throw const FormatException('Invalid native transfer history');
  }
  final confirmed = <String>{};
  for (final row in data) {
    // Offset only the event-time window (block time can trail the signing
    // clock). The ledger row is the documented proof; the explorer read
    // below can only veto it when it answers in the known shape.
    final hash = matchHypercoreSpotTransfer(
        updates: [row],
        source: source,
        destination: destination,
        amountBaseUnits: amountBaseUnits,
        nonce: nonce - clockBufferMs,
        timeWindowMs: clockBufferMs * 2);
    if (hash == null) continue;
    final verdict = await explorerVerdict(
        () => post(_explorerUri, {'type': 'txDetails', 'hash': hash}),
        (details) => verifyHypercoreSpotTransferDetails(
            response: details,
            hash: hash,
            source: source,
            destination: destination,
            amountBaseUnits: amountBaseUnits,
            nonce: nonce));
    if (verdict != false) confirmed.add(hash);
  }
  return confirmed.length == 1 ? confirmed.single : null;
}

/// Matches native perpetuals USDC only. Ambiguous, differently timed or differently
/// directed transfers are never accepted as proof for this operation.
String? matchHypercorePerpTransfer({
  required Iterable<dynamic> updates,
  required String source,
  required String destination,
  required BigInt amountBaseUnits,
  required int nonce,
  int timeWindowMs = 120000,
}) {
  final matches = <String>{};
  for (final update in updates) {
    if (update is! Map) continue;
    final time = update['time'];
    final hash = update['hash'];
    final delta = update['delta'];
    if (time is! num ||
        time < nonce ||
        time > nonce + timeWindowMs ||
        hash is! String ||
        !RegExp(r'^0x[0-9a-fA-F]{64}$').hasMatch(hash) ||
        delta is! Map ||
        delta['type'] != 'internalTransfer') {
      continue;
    }
    if (!sameEvmAddress('${delta['user']}', source) ||
        !sameEvmAddress('${delta['destination']}', destination) ||
        _units(delta['usdc']) != amountBaseUnits) {
      continue;
    }
    matches.add(hash);
  }
  return matches.length == 1 ? matches.single : null;
}

/// Confirms the exact signed action, including its nonce. Ledger event time
/// is block time, which can be earlier than a device clock's signing time.
bool verifyHypercorePerpTransferDetails({
  required Object? response,
  required String hash,
  required String source,
  required String destination,
  required BigInt amountBaseUnits,
  required int nonce,
}) {
  if (response is! Map || response['type'] != 'txDetails') return false;
  final tx = response['tx'];
  if (tx is! Map ||
      !tx.containsKey('error') ||
      tx['error'] != null ||
      tx['hash'] != hash ||
      !sameEvmAddress('${tx['user']}', source)) {
    return false;
  }
  final action = tx['action'];
  return action is Map &&
      action['type'] == 'usdSend' &&
      action['time'] == nonce &&
      sameEvmAddress('${action['destination']}', destination) &&
      _units(action['amount']) == amountBaseUnits;
}

Future<String?> readHypercorePerpTransferHash({
  required String source,
  required String destination,
  required BigInt amountBaseUnits,
  required int nonce,
  http.Client? client,
}) async {
  Future<Object?> post(Uri uri, Map<String, Object> value) =>
      _hypercorePublicPost(uri, value, client: client);

  const clockBufferMs = 120000;
  final data = await post(HyperliquidConstants.infoUri, {
    'type': 'userNonFundingLedgerUpdates',
    'user': source,
    'startTime': nonce - clockBufferMs,
    'endTime': nonce + clockBufferMs,
  });
  if (data is! List) {
    throw const FormatException('Invalid native transfer history');
  }
  final confirmed = <String>{};
  for (final row in data) {
    // Offset only the event-time window (block time can trail the signing
    // clock). The ledger row is the documented proof; the explorer read
    // below can only veto it when it answers in the known shape.
    final hash = matchHypercorePerpTransfer(
        updates: [row],
        source: source,
        destination: destination,
        amountBaseUnits: amountBaseUnits,
        nonce: nonce - clockBufferMs,
        timeWindowMs: clockBufferMs * 2);
    if (hash == null) continue;
    final verdict = await explorerVerdict(
        () => post(_explorerUri, {'type': 'txDetails', 'hash': hash}),
        (details) => verifyHypercorePerpTransferDetails(
            response: details,
            hash: hash,
            source: source,
            destination: destination,
            amountBaseUnits: amountBaseUnits,
            nonce: nonce));
    if (verdict != false) confirmed.add(hash);
  }
  return confirmed.length == 1 ? confirmed.single : null;
}
