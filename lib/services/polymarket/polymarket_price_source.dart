// lib/services/polymarket/polymarket_price_source.dart
//
// Which reference-price feed the 5-minute Up/Down surface reads from.
// Pure policy so the selection rules are unit-testable without Riverpod
// or sockets; `CryptoReferencePricesNotifier` drives it.
//
// Both sources carry the SAME series: Chainlink's 60-second TWAP, which
// is what Polymarket's crypto Up/Down markets resolve on and what
// polymarket.com plots for them (RTDS topic `crypto_prices_twap_sixty`,
// PolyBolt channel `price.crypto.twap`). Verified live October 2026.
//
// Rules:
//   * PolyBolt (wss://ws-live-v2.polymarket.com/ws) needs CLOB L2
//     credentials, so it is preferred only when the app has them.
//   * When PolyBolt fails (auth refused, reconnect budget exhausted,
//     policy close) we fall back to the deprecated RTDS socket for the
//     rest of this session and do not flap back.
//   * Without credentials — every user with no Polymarket account —
//     RTDS is used, so nothing is lost until Polymarket removes the old
//     topics.

enum PmPriceSource { polyBolt, rtds }

/// The TWAP lookback every crypto Up/Down market carries today
/// (Gamma `cryptoMarketConfig.twapLookbackSeconds`, BTC/ETH/SOL/XRP 5m
/// and BTC 15m checked October 2026), and the only window PolyBolt
/// serves.
const kCryptoTwapLookbackSeconds = 60;

/// Where the numbers on a crypto Up/Down card come from. [chainlink] is
/// Polymarket's own feed (either [PmPriceSource]); the others are the
/// fallbacks used only while that feed is silent, never mixed into one
/// series with it.
enum CryptoPriceFeed { chainlink, binance, coingecko }

/// Points for one asset from Polymarket's Chainlink TWAP feed, in
/// Chainlink's own event time. A subscribe answers with a snapshot (the
/// last minute or two, one point a second); live frames carry one point.
class PmReferencePriceFrame {
  /// The app's asset key, e.g. `BTC`.
  final String asset;

  /// Oldest first.
  final List<({DateTime t, double p})> points;
  final bool isSnapshot;

  const PmReferencePriceFrame({
    required this.asset,
    required this.points,
    this.isSnapshot = false,
  });
}

class PmPriceSourcePolicy {
  bool _polyBoltFailed = false;
  PmPriceSource? _active;

  /// Set once PolyBolt errored; sticky for the life of the policy.
  bool get polyBoltFailed => _polyBoltFailed;

  /// The source currently connected, or null before the first connect.
  PmPriceSource? get active => _active;

  /// Which source to connect given the current credential state.
  PmPriceSource select({required bool hasClobCredentials}) =>
      hasClobCredentials && !_polyBoltFailed
          ? PmPriceSource.polyBolt
          : PmPriceSource.rtds;

  /// Records the source that was actually connected.
  void markActive(PmPriceSource source) => _active = source;

  /// PolyBolt errored or closed: remember it and answer the source to
  /// fall back to.
  PmPriceSource markPolyBoltFailed() {
    _polyBoltFailed = true;
    return PmPriceSource.rtds;
  }

  /// True when credentials became available while RTDS is serving and
  /// PolyBolt has not failed this session — i.e. we should upgrade.
  bool shouldUpgrade({required bool hasClobCredentials}) =>
      hasClobCredentials &&
      !_polyBoltFailed &&
      _active == PmPriceSource.rtds;
}
