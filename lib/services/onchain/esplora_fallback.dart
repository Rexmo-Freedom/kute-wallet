// lib/services/onchain/esplora_fallback.dart
//
// The bitcoin wallets sync through one node chosen in Settings. When that
// node cannot be reached (a VPN exit it refuses, an outage), every
// hardware, watch-only and bitcoin wallet stops syncing with no way out
// but changing the setting by hand. This remembers such a failure for a
// while and answers the next public host instead, so the session
// providers rebuild against it and the next sync goes through.

import 'package:flutter/foundation.dart';

import 'package:kute/services/onchain/native_onchain_service.dart'
    show OnchainEndpoint;

class EsploraFallback extends ChangeNotifier {
  EsploraFallback._();
  static final EsploraFallback instance = EsploraFallback._();

  /// How long the alternate host is used before the configured one is
  /// tried again.
  static const holdFor = Duration(minutes: 15);

  /// The public hosts the app knows, in the order they stand in for each
  /// other. Electrum servers come first because their client times out;
  /// the Esplora ones are last resorts. Every Electrum host here serves
  /// a CA-signed certificate (the native client validates them), and
  /// BlueWallet answers on 443 for networks that block Electrum's ports.
  static const ring = [
    OnchainEndpoint.defaultMainnet,
    'electrum.bullbitcoin.com:50002',
    'electrum.acinq.co:50002',
    'electrum2.bluewallet.io:443',
    'electrum.hodlister.co:50002',
    'https://mempool.space/api',
    'https://blockstream.info/api',
  ];

  String? _failedUrl;
  DateTime? _until;

  static String _key(String url) =>
      url.trim().replaceFirst(RegExp(r'^ssl://'), '').replaceFirst(RegExp(r'/+$'), '');

  /// The next public host after [url], or null when [url] is a custom
  /// node the app knows no stand-in for.
  static String? alternate(String url) {
    final key = _key(url);
    final index = key.isEmpty ? 0 : ring.indexOf(key);
    if (index < 0) return null;
    return ring[(index + 1) % ring.length];
  }

  /// Error codes from the native session that mean the host, not the
  /// wallet, is the problem. A timeout is deliberately not one: the
  /// native request is still running and closing the session would wait
  /// on it while refusing every other request for the wallet.
  static bool isNetworkFailure(String code) => code == 'network';

  /// The host to open sessions on for the configured [url] right now.
  String effectiveUrl(String url) {
    final until = _until;
    if (_failedUrl == url.trim() &&
        until != null &&
        DateTime.now().isBefore(until)) {
      return alternate(url) ?? url;
    }
    return url;
  }

  /// Records that [url] could not be reached; listeners rebuild.
  void markNetworkFailure(String url) {
    final alt = alternate(url);
    if (alt == null) return;
    _failedUrl = url.trim();
    _until = DateTime.now().add(holdFor);
    if (kDebugMode) {
      debugPrint('[onchain] $url unreachable; syncing through $alt for '
          '${holdFor.inMinutes} minutes');
    }
    notifyListeners();
  }

  @visibleForTesting
  void resetForTest() {
    _failedUrl = null;
    _until = null;
  }
}
