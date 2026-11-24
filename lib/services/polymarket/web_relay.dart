// Polymarket reads whose hosts send no CORS headers, so a browser cannot
// make them: the crypto rounds' open/close price
// (polymarket.com/api/crypto/crypto-price) and the site views the
// Predictions home reads (api.defi.polymarket.com/internal/view/...).
//
// On web they go through the backend's read-only relay
// (`/api/v1/web/relay/pm/...`), which forwards only these fixed paths.
// Phones keep calling Polymarket directly, with the very same URL as
// before. Nothing account-specific and no order ever goes through it.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:kute/providers/polymarket_site_order.dart'
    show kPolySiteGateway;

const String kPolyCryptoPriceUrl =
    'https://polymarket.com/api/crypto/crypto-price';
const String kWebRelayPath = '/api/v1/web/relay/pm';
const String _kSiteViewPrefix = '/internal/view/';

String _backend() => dotenv.env['BACKEND'] ?? '';

/// The crypto round price URL for [query].
Uri polyCryptoPriceUri(Map<String, String> query,
    {bool web = kIsWeb, String Function() backend = _backend}) {
  final base =
      web ? '${backend()}$kWebRelayPath/crypto-price' : kPolyCryptoPriceUrl;
  return Uri.parse(base).replace(queryParameters: query);
}

/// The URL of one polymarket.com site view ([path] starts with
/// `/internal/view/`).
Uri polySiteViewUri(String path,
    {Map<String, String>? query,
    bool web = kIsWeb,
    String Function() backend = _backend}) {
  if (web && path.startsWith(_kSiteViewPrefix)) {
    return Uri.parse('${backend()}$kWebRelayPath/site/'
            '${path.substring(_kSiteViewPrefix.length)}')
        .replace(queryParameters: query);
  }
  return Uri.parse('$kPolySiteGateway$path').replace(queryParameters: query);
}
