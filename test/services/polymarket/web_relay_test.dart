import 'package:flutter_test/flutter_test.dart';
import 'package:kute/services/polymarket/web_relay.dart';

void main() {
  String backend() => 'https://backend.kutewallet.com';
  const query = {
    'symbol': 'BTC',
    'eventStartTime': '2026-11-24T10:00:00Z',
    'variant': 'fiveminute',
    'endDate': '2026-11-24T10:05:00Z',
    'twapEnabled': 'true',
    'twapLookbackSeconds': '60',
  };

  test('phones call Polymarket directly, exactly as before', () {
    expect(
      polyCryptoPriceUri(query, web: false, backend: backend),
      Uri.parse('https://polymarket.com/api/crypto/crypto-price')
          .replace(queryParameters: query),
    );
    expect(
      polySiteViewUri('/internal/view/home', web: false, backend: backend)
          .toString(),
      'https://api.defi.polymarket.com/internal/view/home',
    );
    expect(
      polySiteViewUri('/internal/view/feed',
              query: {'cursor': 'a+b/='}, web: false, backend: backend)
          .toString(),
      Uri.parse('https://api.defi.polymarket.com/internal/view/feed')
          .replace(queryParameters: {'cursor': 'a+b/='}).toString(),
    );
  });

  test('web goes through the backend relay with the same query', () {
    final price = polyCryptoPriceUri(query, web: true, backend: backend);
    expect(price.origin, 'https://backend.kutewallet.com');
    expect(price.path, '/api/v1/web/relay/pm/crypto-price');
    expect(price.queryParameters, query);
    for (final (path, relayed) in [
      ('/internal/view/home', '/api/v1/web/relay/pm/site/home'),
      ('/internal/view/feed', '/api/v1/web/relay/pm/site/feed'),
      ('/internal/view/category/crypto',
          '/api/v1/web/relay/pm/site/category/crypto'),
      ('/internal/view/sports/chess', '/api/v1/web/relay/pm/site/sports/chess'),
    ]) {
      final uri = polySiteViewUri(path, web: true, backend: backend);
      expect(uri.origin, 'https://backend.kutewallet.com');
      expect(uri.path, relayed);
      expect(uri.hasQuery, isFalse);
    }
    expect(
      polySiteViewUri('/internal/view/feed',
              query: {'cursor': 'abc'}, web: true, backend: backend)
          .queryParameters,
      {'cursor': 'abc'},
    );
  });
}
