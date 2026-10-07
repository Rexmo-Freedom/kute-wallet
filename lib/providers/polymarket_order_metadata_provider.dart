import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:kute/providers/polymarket_open_orders_provider.dart';

/// Public market identity only; no balances or account data are stored here.
class PolymarketOrderMetadata {
  final String title;
  final String imageUrl;

  const PolymarketOrderMetadata({required this.title, required this.imageUrl});
}

/// Public market identity independent of any spending-wallet order session.
final polymarketMarketMetadataProvider = FutureProvider.autoDispose
    .family<PolymarketOrderMetadata?, String>((ref, id) async {
  final client = http.Client();
  ref.onDispose(client.close);
  return (await loadPolymarketOrderMetadata([id], client: client))[id];
});

/// Stable set identity prevents the eight-second order poll from fetching the
/// same artwork metadata again when only price/fill amounts have changed.
final _orderMarketKeyProvider = Provider.autoDispose<String>((ref) {
  final ids = (ref.watch(polymarketOpenOrdersProvider).valueOrNull ?? const [])
      .map((order) => order.market.trim())
      .where((id) => id.isNotEmpty)
      .toSet()
      .toList()
    ..sort();
  return ids.join(',');
});

final polymarketOrderMetadataProvider =
    FutureProvider.autoDispose<Map<String, PolymarketOrderMetadata>>(
        (ref) async {
  final key = ref.watch(_orderMarketKeyProvider);
  if (key.isEmpty) return const {};
  final client = http.Client();
  ref.onDispose(client.close);
  return loadPolymarketOrderMetadata(key.split(','), client: client);
});

/// Resolve title/artwork in serial batches of 25, rather than issuing a request
/// for each row. Ignore unrelated results if an upstream filter is ignored.
/// Uses the keyset list (`{"markets": [...]}`, limit up to 100) in place of
/// the deprecated offset-paged `/markets`; a batch never exceeds one page.
/// https://docs.polymarket.com/api-reference/markets/list-markets-keyset-pagination
Future<Map<String, PolymarketOrderMetadata>> loadPolymarketOrderMetadata(
  Iterable<String> conditionIds, {
  required http.Client client,
}) async {
  final ids = conditionIds
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toSet()
      .toList();
  final result = <String, PolymarketOrderMetadata>{};
  for (var offset = 0; offset < ids.length; offset += 25) {
    final batch = ids.skip(offset).take(25).toList();
    final uri = Uri.https('gamma-api.polymarket.com', '/markets/keyset', {
      'condition_ids': batch,
      'limit': '${batch.length}',
    });
    final response = await client.get(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw http.ClientException('Market artwork could not load', uri);
    }
    final decoded = jsonDecode(response.body);
    final body = decoded is Map<String, dynamic> ? decoded['markets'] : null;
    if (body is! List) throw const FormatException('Expected market list');
    for (final item in body.whereType<Map<String, dynamic>>()) {
      final id = item['conditionId']?.toString() ?? '';
      if (!batch.contains(id)) continue;
      final icon = item['icon']?.toString().trim() ?? '';
      result[id] = PolymarketOrderMetadata(
        title: item['question']?.toString().trim() ?? '',
        imageUrl:
            icon.isNotEmpty ? icon : item['image']?.toString().trim() ?? '',
      );
    }
  }
  return result;
}
