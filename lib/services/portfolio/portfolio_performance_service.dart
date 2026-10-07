import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:kute/constants/hyperliquid_constants.dart';
import 'package:kute/models/portfolio_performance.dart';

/// Public, read-only history. No wallet credentials, signing, or order readers.
class PortfolioPerformanceService {
  PortfolioPerformanceService({http.Client? client})
      : _client = client ?? http.Client();
  final http.Client _client;
  void close() => _client.close();

  Future<PortfolioPerformance> hyperliquid(String address) async {
    final user = _address(address);
    final response = await _client
        .post(
          HyperliquidConstants.infoUri,
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'type': 'portfolio', 'user': user}),
        )
        .timeout(const Duration(seconds: 15));
    _requireSuccess(response);
    return parseHyperliquidPerformance(jsonDecode(response.body));
  }

  /// The P&L series plus every position of the account: the series is a
  /// daily snapshot, so the current figures and the range statistics are
  /// computed from the positions (see
  /// [PortfolioPerformance.withLivePredictions]).
  Future<PortfolioPerformance> polymarket(String address) async {
    final user = _address(address);
    final uri = Uri.https('data-api.polymarket.com', '/v2/user-pnl',
        {'user': user, 'interval': 'max', 'fidelity': '1d'});
    final results = await Future.wait([
      _client.get(uri).timeout(const Duration(seconds: 15)),
      _positionPages(user, 'OPEN'),
      _positionPages(user, 'CLOSED'),
    ]);
    final response = results[0] as http.Response;
    _requireSuccess(response);
    final series = parsePolymarketPerformance(jsonDecode(response.body),
        expectedAddress: user);
    final open = results[1] as _PositionPages;
    final closed = results[2] as _PositionPages;
    return series.withPredictions(PredictionsBook(
      records: List.unmodifiable([...open.records, ...closed.records]),
      complete: open.complete && closed.complete,
      coversFrom: closed.complete ? null : closed.oldestEvent,
    ));
  }

  /// One status of `/v2/positions`, newest first, following its cursor up
  /// to [kPolymarketPositionPages] pages.
  Future<_PositionPages> _positionPages(String user, String status) async {
    final records = <PredictionRecord>[];
    String? cursor;
    for (var page = 0; page < kPolymarketPositionPages; page++) {
      final uri = Uri.https('data-api.polymarket.com', '/v2/positions', {
        'user': user,
        'status': status,
        'limit': '$kPolymarketPositionPageSize',
        'sort_by': 'TIMESTAMP',
        'sort_direction': 'DESC',
        // Every position, however small: the default floor hides dust
        // whose P&L still counts.
        if (status == 'OPEN') ...{
          'filter_type': 'TOKENS',
          'filter_amount': '0',
        },
        if (cursor != null) 'cursor': cursor,
      });
      final response =
          await _client.get(uri).timeout(const Duration(seconds: 15));
      _requireSuccess(response);
      final next = parsePolymarketPositionsPage(jsonDecode(response.body),
          expectedAddress: user, open: status == 'OPEN');
      records.addAll(next.records);
      cursor = next.cursor;
      if (cursor == null) {
        return _PositionPages(records, complete: true);
      }
    }
    return _PositionPages(records, complete: false);
  }
}

/// A page of 500 rows, ten pages a status: 5,000 closed predictions are read
/// whole; beyond that the statistics say so instead of guessing.
const kPolymarketPositionPageSize = 500;
const kPolymarketPositionPages = 10;

class _PositionPages {
  _PositionPages(this.records, {required this.complete});
  final List<PredictionRecord> records;
  final bool complete;

  DateTime? get oldestEvent {
    DateTime? oldest;
    for (final r in records) {
      final at = r.lastEventAt;
      if (at != null && (oldest == null || at.isBefore(oldest))) oldest = at;
    }
    return oldest;
  }
}

/// One `/v2/positions` page: its rows and the cursor of the next page (null
/// on the last).
({List<PredictionRecord> records, String? cursor}) parsePolymarketPositionsPage(
    Object? json,
    {required String expectedAddress,
    required bool open}) {
  if (json is! Map || json['data'] is! List) {
    throw const FormatException('Invalid Polymarket positions');
  }
  final records = <PredictionRecord>[];
  for (final row in json['data'] as List) {
    if (row is! Map) throw const FormatException('Invalid position');
    final wallet = row['proxy_wallet'];
    if (wallet is String &&
        wallet.toLowerCase() != expectedAddress.toLowerCase()) {
      throw const FormatException('Positions do not match the wallet');
    }
    DateTime? at(Object? value) {
      final seconds = value is num ? value : num.tryParse('${value ?? ''}');
      if (seconds == null || seconds <= 0 || !seconds.isFinite) return null;
      return DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round(),
          isUtc: true);
    }

    records.add(PredictionRecord(
      tokenId: '${row['token_id'] ?? ''}',
      conditionId: '${row['condition_id'] ?? ''}'.toLowerCase(),
      open: open,
      redeemable: row['redeemable'] == true,
      size: _number(row['current_size']),
      totalSize: _number(row['total_size']),
      avgPrice: _number(row['avg_price']),
      entryCostUsd: _number(row['entry_cost_usdc']),
      currentPrice: _number(row['current_price']),
      realizedPnlUsd: _number(row['realized_pnl']),
      unrealizedPnlUsd: _number(row['unrealized_pnl']),
      firstEntryAt: at(row['first_entry_at']),
      lastEventAt: at(row['last_event_at']),
      title: '${row['title'] ?? ''}'.trim(),
      slug: '${row['slug'] ?? ''}'.trim(),
      eventSlug: '${row['event_slug'] ?? ''}'.trim(),
      outcome: '${row['outcome'] ?? ''}'.trim(),
      icon: '${row['icon'] ?? ''}'.trim(),
    ));
  }
  final pagination = json['pagination'];
  final cursor = pagination is Map ? pagination['next_cursor'] : null;
  final more = pagination is Map && pagination['has_more'] == true;
  return (
    records: records,
    cursor: more && cursor is String && cursor.isNotEmpty ? cursor : null
  );
}

String _address(String value) {
  if (!RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(value)) {
    throw const PortfolioPerformanceUnavailable(
        'Wallet address is unavailable');
  }
  return value.toLowerCase();
}

void _requireSuccess(http.Response response) {
  if (response.statusCode != 200) {
    // Avoid embedding wallet addresses or entire remote bodies in exceptions.
    throw http.ClientException(
        'Performance history could not load (${response.statusCode})');
  }
}

double _number(Object? value) {
  final parsed = value is num
      ? value.toDouble()
      : value is String
          ? double.tryParse(value)
          : null;
  if (parsed == null || !parsed.isFinite) {
    throw const FormatException('Invalid P&L value');
  }
  return parsed;
}

double? _optionalNumber(Object? value) => value == null ? null : _number(value);

DateTime _timestamp(Object? value, {required bool milliseconds}) {
  final parsed = _number(value);
  if (parsed <= 0 || parsed != parsed.truncateToDouble()) {
    throw const FormatException('Invalid P&L observation timestamp');
  }
  // Hyperliquid documents milliseconds. Polymarket uses Unix timestamps;
  // accept an explicitly millisecond-sized timestamp without losing precision.
  final millis =
      milliseconds || parsed >= 1000000000000 ? parsed : parsed * 1000;
  if (millis > 8640000000000000) {
    throw const FormatException('Invalid timestamp');
  }
  return DateTime.fromMillisecondsSinceEpoch(millis.toInt(), isUtc: true);
}

List<PortfolioPnlPoint> _ordered(Iterable<PortfolioPnlPoint> points) {
  final unique = <DateTime, PortfolioPnlPoint>{};
  for (final point in points) {
    final previous = unique[point.timestamp];
    if (previous != null &&
        (previous.pnlUsd != point.pnlUsd ||
            previous.realizedPnlUsd != point.realizedPnlUsd ||
            previous.openPnlUsd != point.openPnlUsd)) {
      throw const FormatException('Conflicting P&L observations');
    }
    unique[point.timestamp] = point;
  }
  return List.unmodifiable(unique.values.toList()
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp)));
}

PortfolioPerformance _result(List<PortfolioPnlPoint> points,
    {required String source,
    required String basis,
    required String coverage,
    double? other}) {
  final latest = points.isEmpty ? null : points.last;
  return PortfolioPerformance(
      points: points,
      sourceLabel: source,
      basisLabel: basis,
      coverageLabel: coverage,
      totalPnlUsd: latest?.pnlUsd,
      realizedPnlUsd: latest?.realizedPnlUsd,
      openPnlUsd: latest?.openPnlUsd,
      asOf: latest?.timestamp,
      otherPnlUsd: other);
}

/// Official `portfolio` response: consume ONLY pnlHistory (allTime, with the
/// week and month samples lifted onto it), never accountValueHistory (it
/// moves with deposits and withdrawals) or a sum of the capped userFills
/// response.
/// https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/info-endpoint
PortfolioPerformance parseHyperliquidPerformance(Object? json) {
  if (json is! List) throw const FormatException('Invalid Hyperliquid history');
  if (json.isEmpty) {
    return _result(const [],
        source: 'Hyperliquid',
        basis: 'Reported account P&L',
        coverage: 'No published observations');
  }
  final windows = <String, Object?>{};
  for (final item in json) {
    if (item is List && item.length == 2 && item.first is String) {
      if (item.first == 'allTime' && item.last is! Map) {
        throw const FormatException('Invalid portfolio series');
      }
      if (item.last is Map) {
        windows[item.first as String] = (item.last as Map)['pnlHistory'];
      }
    }
  }
  final history = windows['allTime'];
  if (history is! List) {
    throw const FormatException('All-time P&L history missing');
  }
  List<PortfolioPnlPoint> read(List rows) => _ordered(rows.map((row) {
        if (row is! List || row.length != 2) {
          throw const FormatException('Invalid Hyperliquid P&L observation');
        }
        return PortfolioPnlPoint(
            timestamp: _timestamp(row[0], milliseconds: true),
            pnlUsd: _number(row[1]));
      }));
  var points = read(history);
  // The all-time series is sampled about once a week, too coarse for the
  // 7D and 1M lines. The week and month series are sampled every few
  // hours and start at zero; ending on the same sample as the all-time
  // one, each is lifted onto it by the difference of their last values.
  if (points.isNotEmpty) {
    final byTime = {for (final p in points) p.timestamp: p};
    for (final name in const ['week', 'month']) {
      final rows = windows[name];
      if (rows is! List || rows.isEmpty) continue;
      final window = read(rows);
      if (window.isEmpty || window.last.timestamp != points.last.timestamp) {
        continue;
      }
      final offset = points.last.pnlUsd - window.last.pnlUsd;
      for (final p in window) {
        byTime.putIfAbsent(
            p.timestamp,
            () => PortfolioPnlPoint(
                timestamp: p.timestamp, pnlUsd: p.pnlUsd + offset));
      }
    }
    points = List.unmodifiable(byTime.values.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp)));
  }
  return _result(points,
      source: 'Hyperliquid',
      basis: 'Reported account P&L',
      coverage: 'All time · venue samples');
}

/// Official v2 API supplies cumulative P&L components in its data envelope.
/// Use economic_pnl directly: cash flows are separate fields, not profit.
/// https://docs.polymarket.com/api-reference/wallet/get-a-users-pnl-series
PortfolioPerformance parsePolymarketPerformance(Object? json,
    {required String expectedAddress}) {
  if (json is! Map || !json.containsKey('data')) {
    throw const FormatException('Invalid Polymarket P&L history');
  }
  final data = json['data'];
  if (data == null) {
    return _result(const [],
        source: 'Polymarket',
        basis: 'Economic P&L',
        coverage: 'No published observations');
  }
  if (data is! Map ||
      data['points'] is! List ||
      data['proxy_wallet'] is! String ||
      (data['proxy_wallet'] as String).toLowerCase() !=
          expectedAddress.toLowerCase()) {
    throw const FormatException(
        'P&L history does not match the requested wallet');
  }
  final interval = data['interval'];
  if (interval != 'max' && interval != 'all') {
    throw const FormatException('All-time Polymarket history was not returned');
  }
  final rows = data['points'] as List;
  final points = _ordered(rows.map((row) {
    if (row is! Map) {
      throw const FormatException('Invalid Polymarket P&L observation');
    }
    return PortfolioPnlPoint(
      timestamp: _timestamp(row['timestamp'], milliseconds: false),
      pnlUsd: _number(row['economic_pnl']),
      // Settled P&L is realised P&L plus rebates, rewards and yield, so
      // realised and open add up to the economic P&L.
      realizedPnlUsd:
          _optionalNumber(row['settled_pnl'] ?? row['realized_pnl']),
      openPnlUsd: _optionalNumber(row['unrealized_pnl']),
    );
  }));
  // What no position row carries: economic P&L less market P&L, realised
  // and open (LP and combo results, rebates, rewards, yield).
  double? other;
  Map? latest;
  for (final row in rows) {
    if (row is Map &&
        (latest == null ||
            _number(row['timestamp']) > _number(latest['timestamp']))) {
      latest = row;
    }
  }
  if (latest != null) {
    final market = _optionalNumber(
        latest['realized_market_pnl'] ?? latest['realized_pnl']);
    final unrealized = _optionalNumber(latest['unrealized_pnl']);
    if (market != null && unrealized != null) {
      other = _number(latest['economic_pnl']) - market - unrealized;
    }
  }
  return _result(points,
      source: 'Polymarket',
      basis: 'Economic P&L',
      coverage: data['fidelity'] == '1d'
          ? 'All time · daily observations'
          : 'All time · venue observations',
      other: other);
}
