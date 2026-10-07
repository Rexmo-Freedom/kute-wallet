// lib/services/polymarket/combos/combo_service.dart
//
// Polymarket Combos (parlays) for the hot Predictions account: eligibility,
// the RFQ quote → sign → accept → poll flow, and the Data API reads.
//
// Flow (docs.polymarket.com/trading/combos/requesters.md):
//   1. POST /requests (BUY: pUSD budget incl. fees; SELL: shares). The
//      gateway runs a ~400 ms maker competition and answers with the best
//      quote and `expires_at` (the acceptance window is a few seconds), or
//      HTTP 200 `FAILED` with NO_QUOTES. 15 creates per minute per wallet.
//   2. Sign the Exchange v3 order for the quote (combo_order.dart).
//   3. POST /requests/{rfq_id}/accept. EXECUTING is not a fill; a maker can
//      still decline on last look.
//   4. Poll GET /requests/{rfq_id} until FILLED/CONFIRMED or a terminal
//      FAILED/EXPIRED/CANCELED. A local timeout is not a failure.
//
// Transport is one interface (combo_transport.dart) so moving to the
// Builder Gateway later is a new transport, not a new flow.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:kute/constants/polymarket_constants.dart';
import 'package:kute/services/polymarket/combos/combo_ids.dart';
import 'package:kute/services/polymarket/combos/combo_models.dart';
import 'package:kute/services/polymarket/combos/combo_order.dart';
import 'package:kute/services/polymarket/combos/combo_transport.dart';
import 'package:polybrainz_polymarket/polybrainz_polymarket.dart'
    show EthPrivateKey;

/// Gamma's combo eligibility for one market (condition).
class ComboEligibility {
  const ComboEligibility({
    required this.status,
    required this.positionIds,
    this.clobTokenIds = const [],
    this.outcomes = const [],
  });

  /// `enabled`, `pending` or `disabled` (Gamma `comboStatus`).
  final String status;

  /// Positions Framework ids, aligned with [outcomes]: `[0]` YES, `[1]` NO.
  /// NOT the CLOB token ids.
  final List<String> positionIds;
  final List<String> clobTokenIds;
  final List<String> outcomes;

  bool get enabled => status == 'enabled' && positionIds.length >= 2;

  /// The combo leg id for [outcomeName] ('Yes' / 'No'), by Gamma's own
  /// outcome order. Null when the market does not name that outcome.
  String? positionIdFor(String outcomeName) {
    final want = outcomeName.toLowerCase();
    for (var i = 0; i < outcomes.length && i < positionIds.length; i++) {
      if (outcomes[i].toLowerCase() == want) return positionIds[i];
    }
    if (outcomes.isEmpty && positionIds.length >= 2) {
      if (want == 'yes') return positionIds[0];
      if (want == 'no') return positionIds[1];
    }
    return null;
  }
}

/// Where an accepted combo stands.
enum ComboFillState { filled, failed, pending }

class ComboAcceptOutcome {
  const ComboAcceptOutcome({
    required this.state,
    required this.rfqId,
    this.txHash,
    this.errorCode,
  });

  final ComboFillState state;
  final String rfqId;
  final String? txHash;

  /// Polymarket's code for a failure (e.g. a last-look decline).
  final String? errorCode;
}

/// What the combo flow needs from the hot Predictions account. Built by
/// `PolymarketTradingNotifier.comboAccount()` after the same readiness an
/// order takes; the signing key never leaves this object.
class PolymarketComboAccount {
  PolymarketComboAccount({
    required this.walletId,
    required this.eoaAddress,
    required this.depositWallet,
    required String privateKey,
    required this.transport,
    required bool Function() isCurrent,
    required EthPrivateKey Function(String privateKey) credentials,
  })  : _privateKey = privateKey,
        _isCurrent = isCurrent,
        _credentials = credentials;

  final String walletId;
  final String eoaAddress;
  final String depositWallet;
  final PolymarketComboTransport transport;
  final String _privateKey;
  final bool Function() _isCurrent;
  final EthPrivateKey Function(String) _credentials;

  bool get isCurrent => _isCurrent();

  void ensureCurrent() {
    if (!_isCurrent()) {
      throw StateError('The selected Predictions account changed.');
    }
  }

  EthPrivateKey signingCredentials() => _credentials(_privateKey);

  /// For the deposit-wallet batch signer only (approvals, claim).
  String get batchSigningKey => _privateKey;
}

class PolymarketComboService {
  PolymarketComboService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const _gamma = 'gamma-api.polymarket.com';
  static const _dataApi = 'data-api.polymarket.com';

  /// Gamma `comboStatus` + `positionIds` for [conditionIds] (CTF condition
  /// ids, as the bet legs carry them). Missing entries mean Gamma had no
  /// market. Throws on a network failure.
  Future<Map<String, ComboEligibility>> fetchEligibility(
      Iterable<String> conditionIds) async {
    final ids = {
      for (final c in conditionIds)
        if (c.trim().isNotEmpty) c.trim().toLowerCase()
    }.toList();
    final out = <String, ComboEligibility>{};
    for (var i = 0; i < ids.length; i += 20) {
      final batch = ids.skip(i).take(20).toList();
      final uri = Uri.https(_gamma, '/markets', {
        'condition_ids': batch,
        'limit': '${batch.length}',
      });
      final res = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        throw http.ClientException('gamma ${res.statusCode}', uri);
      }
      final decoded = jsonDecode(res.body);
      if (decoded is! List) continue;
      for (final m in decoded.whereType<Map<String, dynamic>>()) {
        final cond = '${m['conditionId'] ?? ''}'.toLowerCase();
        if (cond.isEmpty) continue;
        out[cond] = ComboEligibility(
          status: '${m['comboStatus'] ?? 'disabled'}'.toLowerCase(),
          positionIds: _stringList(m['positionIds']),
          clobTokenIds: _stringList(m['clobTokenIds']),
          outcomes: _stringList(m['outcomes']),
        );
      }
    }
    return out;
  }

  /// CLOB token ids (by outcome index) of Gamma markets [marketIds], for
  /// the legs' price histories (the estimate chart).
  Future<Map<String, List<String>>> fetchClobTokens(
      Iterable<String> marketIds) async {
    final ids = marketIds.where((e) => e.isNotEmpty).toSet().toList();
    final out = <String, List<String>>{};
    for (var i = 0; i < ids.length; i += 20) {
      final batch = ids.skip(i).take(20).toList();
      final uri = Uri.https(
          _gamma, '/markets', {'id': batch, 'limit': '${batch.length}'});
      final res = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) continue;
      final decoded = jsonDecode(res.body);
      if (decoded is! List) continue;
      for (final m in decoded.whereType<Map<String, dynamic>>()) {
        out['${m['id']}'] = _stringList(m['clobTokenIds']);
      }
    }
    return out;
  }

  /// Creates an RFQ. Returns the winning quote (checked against the
  /// request, see [parseComboCreateResponse]) or the no-quote outcome.
  /// Throws [ComboRfqException] on a non-200 answer.
  Future<ComboRfqResult> requestQuote({
    required PolymarketComboTransport transport,
    required String depositWallet,
    required List<String> legPositionIds,
    required ComboDirection direction,
    required BigInt sizeE6,
  }) async {
    final legs = ComboIds.canonicalLegs(legPositionIds);
    if (sizeE6 <= BigInt.zero) throw ArgumentError('size must be positive');
    final body = comboRequestBody(
      depositWallet: depositWallet,
      legPositionIds: legs,
      direction: direction,
      sizeE6: sizeE6,
    );
    final res = await transport.createRequest(body);
    if (res.statusCode != 200) throw comboRfqError(res);
    return parseComboCreateResponse(
      res.json,
      legPositionIds: legs,
      direction: direction,
      sizeE6: sizeE6,
    );
  }

  /// Signs [quote] for [account] and accepts it, then waits for a durable
  /// outcome up to [wait]. A pending result is not a failure: keep the
  /// rfq id and poll again with [status].
  Future<ComboAcceptOutcome> acceptQuote({
    required PolymarketComboAccount account,
    required ComboQuote quote,
    Duration wait = const Duration(seconds: 45),
    Future<void> Function()? beforeAccept,
  }) async {
    account.ensureCurrent();
    final transport = account.transport;
    final builder = transport.attributesBuilder
        ? (quote.builderCode ?? PolymarketConstants.bytes32Zero)
        : PolymarketConstants.bytes32Zero;
    if (!transport.attributesBuilder &&
        builder != PolymarketConstants.bytes32Zero) {
      throw const ComboQuoteMismatch('builder');
    }
    final order = buildComboOrder(
      quote: quote,
      depositWallet: account.depositWallet,
      builder: builder,
    );
    final signed = await signComboOrder(
        order: order, credentials: account.signingCredentials());
    final body = comboAcceptBody(quoteId: quote.quoteId, signedOrder: signed);
    account.ensureCurrent();
    if (!quote.expiresAt.isAfter(DateTime.now())) {
      // Nothing was sent: the window closed while signing.
      throw const ComboRfqException(409, 'EXPIRED_RFQ');
    }
    // Journaled before the POST: from here only the rfq id recovers it.
    await beforeAccept?.call();
    account.ensureCurrent();

    ComboHttpResponse? res;
    Object? lastError;
    // The same authenticated acceptance never executes twice, so one
    // retry after a transport failure is safe while the window is open.
    for (var attempt = 0; attempt < 2 && res == null; attempt++) {
      try {
        final r = await transport.accept(quote.rfqId, body);
        if (r.statusCode >= 500 &&
            attempt == 0 &&
            quote.expiresAt.isAfter(DateTime.now())) {
          lastError = comboRfqError(r);
          continue;
        }
        res = r;
      } on TimeoutException catch (e) {
        lastError = e;
      } on http.ClientException catch (e) {
        lastError = e;
      }
    }
    if (res == null) {
      // Unknown: the acceptance may have reached the gateway. The rfq id
      // is the recovery key.
      final polled = await _pollQuietly(transport, quote.rfqId, wait);
      return polled ??
          ComboAcceptOutcome(
              state: ComboFillState.pending,
              rfqId: quote.rfqId,
              errorCode: lastError is ComboRfqException
                  ? lastError.code
                  : null);
    }
    if (res.statusCode != 200) throw comboRfqError(res);
    final first = ComboRfqStatus.fromJson(res.json);
    if (first.isTerminal) return _outcome(quote.rfqId, first);
    return await _pollQuietly(transport, quote.rfqId, wait) ??
        ComboAcceptOutcome(state: ComboFillState.pending, rfqId: quote.rfqId);
  }

  /// One status read. Throws [ComboRfqException] on a non-200 answer.
  Future<ComboRfqStatus> status(
      PolymarketComboTransport transport, String rfqId) async {
    final res = await transport.status(rfqId);
    if (res.statusCode != 200) throw comboRfqError(res);
    return ComboRfqStatus.fromJson(res.json);
  }

  /// Polls until a terminal state or [wait] runs out (null then).
  Future<ComboAcceptOutcome?> _pollQuietly(
      PolymarketComboTransport transport, String rfqId, Duration wait) async {
    final deadline = DateTime.now().add(wait);
    var delay = const Duration(milliseconds: 600);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(delay);
      try {
        final s = await status(transport, rfqId);
        if (s.isTerminal) return _outcome(rfqId, s);
      } on ComboRfqException catch (e) {
        // 409 before the acceptance registered: keep polling.
        if (e.httpStatus == 404) {
          return ComboAcceptOutcome(
              state: ComboFillState.failed, rfqId: rfqId, errorCode: e.code);
        }
      } catch (_) {
        // Transport hiccup: the next poll decides.
      }
      if (delay < const Duration(seconds: 2)) delay *= 2;
    }
    return null;
  }

  ComboAcceptOutcome _outcome(String rfqId, ComboRfqStatus s) =>
      ComboAcceptOutcome(
        state: s.isFilled ? ComboFillState.filled : ComboFillState.failed,
        rfqId: rfqId,
        txHash: s.txHash,
        errorCode: s.errorCode ?? (s.isFilled ? null : s.status),
      );

  /// Combos [depositWallet] holds (`/v2/positions/combos`, held listing),
  /// YES side only, up to [maxPages] pages of 100. Throws on failure.
  Future<List<ComboPosition>> fetchPositions(String depositWallet,
      {int maxPages = 3}) async {
    final out = <ComboPosition>[];
    String? cursor;
    for (var page = 0; page < maxPages; page++) {
      final uri = Uri.https(_dataApi, '/v2/positions/combos', {
        'user': depositWallet,
        if (cursor == null) 'limit': '100',
        if (cursor != null) 'cursor': cursor,
      });
      final res = await _client.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        throw http.ClientException('combos ${res.statusCode}', uri);
      }
      final decoded = jsonDecode(res.body);
      final rows = decoded is Map ? decoded['data'] : null;
      if (rows is List) {
        for (final r in rows.whereType<Map<String, dynamic>>()) {
          final p = ComboPosition.fromJson(r);
          if (p.isYes && p.positionId.isNotEmpty) out.add(p);
        }
      }
      final pag = decoded is Map ? decoded['pagination'] : null;
      final next = pag is Map ? pag['next_cursor'] : null;
      if (next is! String || next.isEmpty) break;
      cursor = next;
    }
    return out;
  }

  /// The latest combo lifecycle events of [depositWallet]. Throws on
  /// failure.
  Future<List<ComboActivity>> fetchActivity(String depositWallet,
      {int limit = 100}) async {
    final uri = Uri.https(_dataApi, '/v2/activity/combos',
        {'user': depositWallet, 'limit': '$limit'});
    final res = await _client.get(uri).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      throw http.ClientException('combo activity ${res.statusCode}', uri);
    }
    final decoded = jsonDecode(res.body);
    final rows = decoded is Map ? decoded['data'] : null;
    if (rows is! List) return const [];
    return rows
        .whereType<Map<String, dynamic>>()
        .map(ComboActivity.fromJson)
        .toList();
  }

  static List<String> _stringList(dynamic v) {
    dynamic list = v;
    if (v is String && v.trim().startsWith('[')) {
      try {
        list = jsonDecode(v);
      } catch (_) {
        return const [];
      }
    }
    if (list is! List) return const [];
    return [for (final e in list) '$e'];
  }
}
