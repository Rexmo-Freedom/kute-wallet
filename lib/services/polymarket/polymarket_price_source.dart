// lib/services/polymarket/polymarket_price_source.dart
//
// The reference-price feed behind the crypto Up/Down cards, as pure
// types and policy so the rules are unit-testable without Riverpod or
// sockets; `CryptoReferencePricesNotifier` drives it.
//
// The feed is Chainlink's 60-second TWAP, which is what Polymarket's
// crypto Up/Down markets resolve on and what polymarket.com plots for
// them, read from PolyBolt (wss://ws-live-v2.polymarket.com/ws, channel
// `price.crypto.twap`). PolyBolt is the only source: Polymarket removes
// the old price topics of its previous live-data socket in late October
// 2026, so there is nothing to fall back to on Polymarket's side.
//
// Rules:
//   * PolyBolt's price channels need CLOB L2 credentials. Without them
//     (no Polymarket account yet, before derivation, a Ledger account)
//     no socket is opened and the cards show their Binance/CoinGecko
//     fallback straight away; the feed connects as soon as credentials
//     appear.
//   * A transient failure (socket closed or errored past the socket's
//     own reconnect budget, a silent feed, an unreachable verifier)
//     reconnects after 2 s, 4 s, ... up to 30 s; any price point resets
//     the count.
//   * A hard failure (credentials refused, policy close 4008) waits
//     [kPmReferenceHardRetryDelay] before trying again, and retries at
//     once when the credentials change.

/// The TWAP lookback every crypto Up/Down market carries today
/// (Gamma `cryptoMarketConfig.twapLookbackSeconds`, BTC/ETH/SOL/XRP 5m
/// and BTC 15m checked October 2026), and the only window PolyBolt
/// serves.
const kCryptoTwapLookbackSeconds = 60;

/// Wait after a hard failure (credentials refused, policy close) before
/// the feed tries again with the same credentials.
const kPmReferenceHardRetryDelay = Duration(seconds: 60);

/// Where the numbers on a crypto Up/Down card come from. [chainlink] is
/// Polymarket's own feed (PolyBolt); the others are the fallbacks used
/// only while that feed is silent or unavailable, never mixed into one
/// series with it.
enum CryptoPriceFeed { chainlink, binance, coingecko }

/// Points for one asset from Polymarket's Chainlink TWAP feed, in
/// Chainlink's own event time. A subscribe answers with a snapshot (the
/// last two minutes, one point a second); live frames carry one point.
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

/// Reconnect timing for the PolyBolt reference-price feed.
class PmReferenceFeedRetry {
  int _failures = 0;

  /// Consecutive failures since the last price point.
  int get failures => _failures;

  /// Records a failure and answers how long to wait before reconnecting:
  /// 2 s, 4 s, ... capped at 30 s for a transient one,
  /// [kPmReferenceHardRetryDelay] for a hard one.
  Duration next({bool hard = false}) {
    _failures += 1;
    if (hard) return kPmReferenceHardRetryDelay;
    return Duration(seconds: (2 * _failures).clamp(2, 30));
  }

  /// A price point arrived: the next failure starts from 2 s again.
  void reset() => _failures = 0;
}
