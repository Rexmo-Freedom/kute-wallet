import 'dart:async';
import 'dart:ui' show Color;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/active_shell_tab_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart'
    show polymarketTradingProvider;
import 'package:kute/services/binance_btc_live_feed.dart';
import 'package:kute/services/polymarket/polybolt_price_socket.dart';
import 'package:kute/services/polymarket/polymarket_price_source.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _sentinel = Object();

class BtcPriceSnapshot {
  final DateTime timestamp;
  final double price;
  const BtcPriceSnapshot({required this.timestamp, required this.price});
}

/// The CLOB L2 credential trio when the signed-in hot account has
/// derived one (same credentials the CLOB user channel authenticates
/// with). Null for users without a Polymarket account, before
/// derivation, and for Ledger accounts (whose credentials never enter
/// the trading provider's client). PolyBolt's price channels accept
/// nothing else.
PolyBoltCredentials? _polyBoltCredentialsFor(Ref ref) {
  try {
    final creds = ref
        .read(polymarketTradingProvider.notifier)
        .clobClient
        ?.clob
        .auth
        ?.credentials;
    if (creds == null) return null;
    final out = PolyBoltCredentials(
      apiKey: creds.apiKey,
      secret: creds.secret,
      passphrase: creds.passphrase,
    );
    return out.isComplete ? out : null;
  } catch (_) {
    return null;
  }
}

/// The crypto Up-or-Down window on screen, in minutes. Every crypto
/// market card follows it, so 5m and 15m never mix on one screen.
final cryptoPredictWindowProvider = StateProvider<int>((_) => 5);

/// The windows Polymarket runs for [asset] today, asked of Polymarket
/// once per session. The chips on the Predictions screen show exactly
/// these, so a window the venue stops publishing disappears with it.
final cryptoPredictWindowsProvider =
    FutureProvider.family<List<int>, String>((ref, asset) async {
  final model = PolymarketModel();
  try {
    return await model.discoverCryptoWindows(asset);
  } finally {
    model.dispose();
  }
});

class CryptoAssetConfig {
  final String asset;
  /// Ticker the reference-price feed is keyed on
  /// (PolyBolt symbol via [polyBoltSymbolForAsset], `BTC` → `btcusd`).
  final String priceSymbol;
  final String displayName;
  final String logoPath;
  final bool isSvg;
  /// Brand color used for the asset icon disc, the "Current" price
  /// text and the countdown pill accent so the banner reads as that
  /// asset's color (not always BTC orange).
  final Color brandColor;

  const CryptoAssetConfig({
    required this.asset,
    required this.priceSymbol,
    required this.displayName,
    required this.logoPath,
    required this.brandColor,
    this.isSvg = true,
  });
}

const kCryptoPredictAssets = [
  CryptoAssetConfig(
    asset: 'BTC',
    priceSymbol: 'BTC',
    displayName: 'Bitcoin',
    logoPath: 'lib/assets/bitcoin-logo.png',
    isSvg: false,
    brandColor: Color(0xFFF7931A),
  ),
  CryptoAssetConfig(
    asset: 'ETH',
    priceSymbol: 'ETH',
    displayName: 'Ethereum',
    logoPath: 'lib/assets/eth.svg',
    brandColor: Color(0xFF627EEA),
  ),
  CryptoAssetConfig(
    asset: 'SOL',
    priceSymbol: 'SOL',
    displayName: 'Solana',
    logoPath: 'lib/assets/sol.svg',
    brandColor: Color(0xFF14F195),
  ),
  CryptoAssetConfig(
    asset: 'XRP',
    priceSymbol: 'XRP',
    displayName: 'XRP',
    logoPath: 'lib/assets/xrp-xrp-logo.svg',
    brandColor: Color(0xFF25A768),
  ),
];

class CryptoPredictState {
  final String asset;

  /// Last point of [priceHistory]: Polymarket's Chainlink 60-second TWAP,
  /// the number polymarket.com shows as the current price.
  final double? currentPrice;

  /// Polymarket's own price to beat for the window (see
  /// [_CryptoPriceFeed._resolveStrike] for the sources, in order).
  final double? priceToBeat;
  final Btc5MinEvent? event;

  /// One feed only, never a blend: Polymarket's Chainlink TWAP, or the
  /// whole series from [feed] while that is silent.
  final List<BtcPriceSnapshot> priceHistory;
  final int secondsRemaining;

  /// Where [currentPrice] and [priceHistory] come from right now.
  final CryptoPriceFeed feed;

  const CryptoPredictState({
    required this.asset,
    this.currentPrice,
    this.priceToBeat,
    this.event,
    this.priceHistory = const [],
    this.secondsRemaining = 300,
    this.feed = CryptoPriceFeed.chainlink,
  });

  double get upPct => (event?.upPrice ?? 0.50) * 100;
  double get downPct => (event?.downPrice ?? 0.50) * 100;

  String get countdownText {
    final m = secondsRemaining ~/ 60;
    final s = secondsRemaining % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  CryptoPredictState copyWith({
    double? currentPrice,
    Object? priceToBeat = _sentinel,
    Btc5MinEvent? event,
    List<BtcPriceSnapshot>? priceHistory,
    int? secondsRemaining,
    CryptoPriceFeed? feed,
  }) {
    return CryptoPredictState(
      asset: asset,
      currentPrice: currentPrice ?? this.currentPrice,
      priceToBeat: priceToBeat == _sentinel
          ? this.priceToBeat
          : priceToBeat as double?,
      event: event ?? this.event,
      priceHistory: priceHistory ?? this.priceHistory,
      secondsRemaining: secondsRemaining ?? this.secondsRemaining,
      feed: feed ?? this.feed,
    );
  }
}

/// Maps the asset symbol to a CoinGecko coin id for the
/// last-resort fallback. Only the four assets we currently surface on
/// the 5-min Up/Down card are listed; unknown symbols return null
/// (the fallback simply no-ops in that case).
String? _coingeckoIdForAsset(String asset) {
  switch (asset.toUpperCase()) {
    case 'BTC':
      return 'bitcoin';
    case 'ETH':
      return 'ethereum';
    case 'SOL':
      return 'solana';
    case 'XRP':
      return 'ripple';
    default:
      return null;
  }
}


/// How long Polymarket's Chainlink feed may stay silent before a card
/// falls back. The Chainlink TWAP series posts one point per symbol per
/// second, about 1.4 s behind, and the worst gap measured was 3 s
/// (October 2026, same series PolyBolt carries): five
/// seconds without a point is a stalled or dead feed rather than a slow
/// one, and the hand-over still lands before the chart visibly freezes.
const kChainlinkStaleAfter = Duration(seconds: 5);

/// What the shared layer holds: Polymarket's Chainlink 60-second TWAP
/// per asset, timestamped in Chainlink's event time.
class CryptoReferencePrices {
  /// Oldest first, the last twenty minutes at most.
  final Map<String, List<BtcPriceSnapshot>> series;

  /// Wall-clock arrival of each asset's last point.
  final Map<String, DateTime> receivedAt;

  /// When the current socket was opened; null while nothing on screen
  /// needs the feed (Predictions not the active tab and no card open
  /// elsewhere), in which case cards neither stream nor fall back.
  final DateTime? connectedAt;

  /// True while the feed is wanted but cannot open: PolyBolt's price
  /// channels need CLOB credentials and the active account has none
  /// (no Polymarket account yet, before derivation, a Ledger account).
  /// Cards fall back at once instead of waiting [kChainlinkStaleAfter].
  final bool awaitingCredentials;

  const CryptoReferencePrices({
    this.series = const {},
    this.receivedAt = const {},
    this.connectedAt,
    this.awaitingCredentials = false,
  });

  bool get streaming => connectedAt != null;

  List<BtcPriceSnapshot> seriesFor(String asset) => series[asset] ?? const [];

  /// True while [asset] ticked within [kChainlinkStaleAfter].
  bool isLive(String asset, DateTime now) {
    final at = receivedAt[asset];
    return streaming &&
        at != null &&
        now.difference(at) <= kChainlinkStaleAfter &&
        seriesFor(asset).isNotEmpty;
  }

  /// When [asset] last showed life: its last point, or the socket opening
  /// when that is later (a reconnect gets a fresh grace period).
  DateTime? lastSignOfLife(String asset) {
    final at = receivedAt[asset];
    final open = connectedAt;
    if (at == null) return open;
    if (open == null) return at;
    return at.isAfter(open) ? at : open;
  }

  CryptoReferencePrices copyWith({
    Map<String, List<BtcPriceSnapshot>>? series,
    Map<String, DateTime>? receivedAt,
    Object? connectedAt = _sentinel,
    bool? awaitingCredentials,
  }) {
    return CryptoReferencePrices(
      series: series ?? this.series,
      receivedAt: receivedAt ?? this.receivedAt,
      connectedAt: connectedAt == _sentinel
          ? this.connectedAt
          : connectedAt as DateTime?,
      awaitingCredentials: awaitingCredentials ?? this.awaitingCredentials,
    );
  }
}

/// Crypto Up/Down banners on screen right now, counted by the banner
/// itself while its tickers run (`TickerMode`: a hidden shell branch has
/// them off). Lets the shared feed stream for a banner shown outside the
/// Predictions tab — a Ledger wallet's detail screen, the 5-minute sheet
/// opened from search — and only then.
final cryptoCardsOnScreenProvider = StateProvider<int>((_) => 0);

/// True while the shared feed should stream: Predictions is the active
/// tab, or a banner is on screen elsewhere. A bool, so the shared layer
/// reopens its socket only when this flips, not on every tab or count
/// change.
final _cryptoFeedWantedProvider = Provider.autoDispose<bool>((ref) =>
    ref.watch(activeShellTabProvider) == ActiveNavTab.predictions ||
    ref.watch(cryptoCardsOnScreenProvider) > 0);

/// Reads the CLOB credentials PolyBolt authenticates with, at the moment
/// of the call (see [_polyBoltCredentialsFor]). A provider so tests can
/// hand the shared layer credentials without a trading account.
final pmReferenceCredentialsProvider =
    Provider<PolyBoltCredentials? Function()>(
        (ref) => () => _polyBoltCredentialsFor(ref));

/// The socket the shared layer's [PolyBoltPriceSocket] opens; null for
/// the real WebSocket. Tests override it with an in-memory transport.
final pmReferenceTransportProvider =
    Provider<PolyBoltTransportFactory?>((_) => null);

/// Shared Chainlink price layer for every crypto Up/Down card.
///
/// Polymarket's crypto Up/Down markets resolve on Chainlink's 60-second
/// TWAP (Gamma `resolutionSource` …/btc-usd-twap-60s-streams), and
/// polymarket.com's event page plots exactly that series and shows its
/// last point as the current price. This layer reads the same series
/// for every asset in [kCryptoPredictAssets] over ONE PolyBolt socket,
/// channel `price.crypto.twap` (window 60). A subscribe answers with
/// the last two minutes, which seeds the charts, then one point per
/// symbol per second.
///
/// PolyBolt is the only source (see `polymarket_price_source.dart`). Its
/// price channels need CLOB credentials: without them no socket opens,
/// [CryptoReferencePrices.awaitingCredentials] is set, and the socket
/// opens within a second of credentials appearing (checked every
/// second, as is a change of credentials). An error, close or silence
/// past [kChainlinkStaleAfter] reconnects per [PmReferenceFeedRetry].
/// Cards switch to Binance/CoinGecko on their own while their asset is
/// silent or the feed is awaiting credentials (see [_CryptoPriceFeed]);
/// nothing here ever mixes those in.
///
/// Streams only while Predictions is the active tab or a banner is on
/// screen elsewhere ([cryptoCardsOnScreenProvider]); otherwise the
/// socket is closed (build re-runs) and the last series is kept for an
/// instant repaint on return.
class CryptoReferencePricesNotifier
    extends AutoDisposeNotifier<CryptoReferencePrices> {
  StreamSubscription<PmReferencePriceFrame>? _wsSub;
  Timer? _watchdog;
  Timer? _reconnectTimer;
  CryptoReferencePrices _last = const CryptoReferencePrices();
  DateTime? _lastFrameAt;
  PmReferenceFeedRetry _retry = PmReferenceFeedRetry();

  /// API key of the credentials the open (or last failed) socket used;
  /// null while awaiting credentials. A different key from
  /// [_credentials] means the account changed: reconnect at once.
  String? _apiKeyInUse;

  /// Bumped on every connect and teardown so callbacks from an older
  /// socket are ignored.
  int _gen = 0;

  /// History kept per asset: a fifteen-minute window plus slack.
  static const _keep = Duration(minutes: 20);

  PolyBoltCredentials? _credentials() =>
      ref.read(pmReferenceCredentialsProvider)();

  @override
  CryptoReferencePrices build() {
    // Rebuilds when streaming is wanted or not: only while Predictions is
    // the active tab (mirrors the CLOB socket's applyShellTabLivePolicy),
    // or while a banner is on screen elsewhere.
    final wanted = ref.watch(_cryptoFeedWantedProvider);
    _retry = PmReferenceFeedRetry();
    _lastFrameAt = null;
    _apiKeyInUse = null;
    ref.onDispose(() {
      _gen += 1;
      _wsSub?.cancel();
      _wsSub = null;
      _watchdog?.cancel();
      _watchdog = null;
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
    });
    if (!wanted) {
      _last = _last.copyWith(connectedAt: null, awaitingCredentials: false);
      return _last;
    }
    _connect(emit: false);
    _watchdog = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    return _last;
  }

  /// Opens PolyBolt with the current credentials, or records that the
  /// feed is awaiting them. [emit] is false only inside build, where the
  /// returned state carries the new values instead.
  void _connect({bool emit = true}) {
    _gen += 1;
    final gen = _gen;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _wsSub?.cancel();
    _wsSub = null;
    final creds = _credentials();
    if (creds == null) {
      _apiKeyInUse = null;
      if (!_last.awaitingCredentials) {
        debugPrint('[pm-prices] polybolt waiting for CLOB credentials');
      }
      _last = _last.copyWith(
          connectedAt: DateTime.now(), awaitingCredentials: true);
      if (emit) state = _last;
      return;
    }
    _apiKeyInUse = creds.apiKey;
    _last = _last.copyWith(
        connectedAt: DateTime.now(), awaitingCredentials: false);
    if (emit) state = _last;
    final symbolByAsset = <String, String>{
      for (final cfg in kCryptoPredictAssets)
        cfg.asset: polyBoltSymbolForAsset(cfg.priceSymbol),
    };
    // The TWAP channel, not the spot one: spot is not the series the
    // markets resolve on, while Chainlink's 60-second TWAP is (and is
    // what polymarket.com plots).
    final socket = PolyBoltPriceSocket(
      credentials: _credentials,
      channel: kPolyBoltCryptoTwapChannel,
      transportFactory: ref.read(pmReferenceTransportProvider),
    );
    debugPrint('[pm-prices] source=polybolt channel=${socket.channel} '
        'symbols=${symbolByAsset.values.join(',')}');
    _wsSub = socket.framesByAsset(symbolByAsset).listen(
      (frame) {
        if (gen == _gen) _apply(frame);
      },
      onError: (Object e) {
        if (gen == _gen) {
          _scheduleReconnect('$e', hard: PolyBoltPriceSocket.isHardFailure(e));
        }
      },
      onDone: () {
        if (gen == _gen) _scheduleReconnect('stream closed');
      },
    );
  }

  /// Reopens PolyBolt after [PmReferenceFeedRetry.next]; a credential
  /// change cuts the wait short (see [_tick]).
  void _scheduleReconnect(String why, {bool hard = false}) {
    if (_reconnectTimer?.isActive ?? false) return;
    _gen += 1;
    _wsSub?.cancel();
    _wsSub = null;
    final delay = _retry.next(hard: hard);
    debugPrint('[pm-prices] polybolt $why → reconnect in ${delay.inSeconds}s');
    _reconnectTimer = Timer(delay, _connect);
  }

  /// Once a second: follow the credentials, and replace a socket that
  /// stayed silent past [kChainlinkStaleAfter].
  void _tick() {
    final key = _credentials()?.apiKey;
    if (key != _apiKeyInUse) {
      // Credentials appeared, changed (account switch) or went away.
      debugPrint('[pm-prices] polybolt credentials '
          '${key == null ? 'gone' : 'changed'} → reconnect');
      _retry.reset();
      _connect();
      return;
    }
    if (key == null) return; // awaiting credentials, nothing to watch
    final opened = _last.connectedAt;
    if (opened == null) return;
    if (_reconnectTimer?.isActive ?? false) return;
    final last = _lastFrameAt;
    final since = last != null && last.isAfter(opened) ? last : opened;
    if (DateTime.now().difference(since) <= kChainlinkStaleAfter) return;
    _scheduleReconnect('silent');
  }

  void _apply(PmReferencePriceFrame frame) {
    if (frame.points.isEmpty) return;
    final now = DateTime.now();
    _lastFrameAt = now;
    _retry.reset();
    final old = _last.series[frame.asset] ?? const <BtcPriceSnapshot>[];
    final incoming = [
      for (final p in frame.points) BtcPriceSnapshot(timestamp: p.t, price: p.p),
    ];
    List<BtcPriceSnapshot> next;
    if (old.isNotEmpty &&
        !frame.isSnapshot &&
        incoming.first.timestamp.isAfter(old.last.timestamp)) {
      next = [...old, ...incoming];
    } else {
      // Snapshot, or a point at/before the newest one: merge by
      // timestamp, the newer frame winning.
      final byMs = <int, BtcPriceSnapshot>{
        for (final p in old) p.timestamp.millisecondsSinceEpoch: p,
        for (final p in incoming) p.timestamp.millisecondsSinceEpoch: p,
      };
      next = byMs.values.toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    }
    final horizon = next.last.timestamp.subtract(_keep);
    final firstKept = next.indexWhere((p) => !p.timestamp.isBefore(horizon));
    if (firstKept > 0) next = next.sublist(firstKept);
    _last = _last.copyWith(
      series: {..._last.series, frame.asset: next},
      receivedAt: {..._last.receivedAt, frame.asset: now},
    );
    state = _last;
  }
}

final cryptoReferencePricesProvider = NotifierProvider.autoDispose<
    CryptoReferencePricesNotifier, CryptoReferencePrices>(
  CryptoReferencePricesNotifier.new,
);

/// The price side of a crypto Up/Down card, shared by
/// [CryptoPredictNotifier] and [CryptoPredictAtWindowNotifier].
///
/// * Current price and chart: Polymarket's Chainlink TWAP from
///   [cryptoReferencePricesProvider], copied as is.
/// * When that asset has been silent for [kChainlinkStaleAfter] while
///   the feed is supposed to stream, or at once while the feed awaits
///   CLOB credentials (a card that is off screen neither streams nor
///   falls back), the WHOLE series switches to Binance
///   (1 s klines to seed, then the BTC trade socket or a 2 s klines
///   poll), or to CoinGecko when Binance does not answer either. The
///   first Chainlink point after that switches the whole series back.
/// * Price to beat: see [_resolveStrike].
mixin _CryptoPriceFeed<A>
    on AutoDisposeFamilyAsyncNotifier<CryptoPredictState, A> {
  PolymarketModel? get _model;
  CryptoAssetConfig get _config;
  int get _minutes;

  bool _feedDisposed = false;
  CryptoPriceFeed _feed = CryptoPriceFeed.chainlink;
  List<BtcPriceSnapshot>? _shownSeries;

  // Fallback plumbing. [_fallbackGen] invalidates in-flight answers
  // after every switch.
  int _fallbackGen = 0;
  StreamSubscription<double>? _binanceSub;
  Timer? _fallbackPoll;

  // Price to beat for [_strikeSlug]; [_strikeExact] once it came from
  // Polymarket (Gamma, the TWAP point at the window open, or the site's
  // own open price).
  String? _strikeSlug;
  bool _strikeExact = false;
  DateTime? _openPriceAskedAt;
  bool _openPriceInFlight = false;

  /// Call once from build().
  void _startPriceFeed() {
    _feedDisposed = false;
    _feed = CryptoPriceFeed.chainlink;
    _shownSeries = null;
    _strikeSlug = null;
    _strikeExact = false;
    _openPriceAskedAt = null;
    _openPriceInFlight = false;
    ref.onDispose(() {
      _feedDisposed = true;
      _stopFallback();
    });
    ref.listen<CryptoReferencePrices>(
        cryptoReferencePricesProvider, (_, __) => _syncPriceFeed());
    // Paint from whatever the shared layer already holds (another card
    // may have warmed it) once the initial state is in.
    Timer.run(_syncPriceFeed);
  }

  /// Applies the shared layer to this card. Runs on every shared update
  /// and once a second from the countdown, which is what notices a
  /// silent feed.
  void _syncPriceFeed() {
    if (_feedDisposed) return;
    final prev = state.asData?.value;
    if (prev == null) return;
    final now = DateTime.now();
    final shared = ref.read(cryptoReferencePricesProvider);
    final asset = _config.asset;
    if (shared.isLive(asset, now)) {
      final series = shared.seriesFor(asset);
      final returning = _feed != CryptoPriceFeed.chainlink;
      if (returning) {
        _stopFallback();
        _feed = CryptoPriceFeed.chainlink;
        debugPrint('[pm-prices] $asset back on chainlink');
      }
      if (returning || !identical(series, _shownSeries)) {
        _shownSeries = series;
        state = AsyncData(prev.copyWith(
          currentPrice: series.last.price,
          priceHistory: _recent(series),
          feed: CryptoPriceFeed.chainlink,
        ));
      }
    } else if (!shared.streaming) {
      // Off screen: no feed, no fallback; keep the last numbers until
      // the feed is back (then the next live point repaints).
      if (_feed != CryptoPriceFeed.chainlink) {
        _stopFallback();
        _feed = CryptoPriceFeed.chainlink;
        _shownSeries = null;
      }
    } else if (_feed == CryptoPriceFeed.chainlink) {
      // No credentials for PolyBolt: nothing will arrive, fall back now.
      final since = shared.lastSignOfLife(asset);
      if (shared.awaitingCredentials ||
          (since != null && now.difference(since) > kChainlinkStaleAfter)) {
        _startFallback();
      }
    }
    _resolveStrike();
  }

  /// The trailing window plus a minute, newest last.
  List<BtcPriceSnapshot> _recent(List<BtcPriceSnapshot> series) {
    if (series.isEmpty) return series;
    final horizon =
        series.last.timestamp.subtract(Duration(minutes: _minutes + 1));
    var first = series.indexWhere((p) => !p.timestamp.isBefore(horizon));
    if (first < 0) first = series.length;
    if (series.length - first > 2000) first = series.length - 2000;
    return first == 0 ? series : series.sublist(first);
  }

  void _startFallback() {
    final model = _model;
    if (model == null) return;
    _stopFallback();
    final gen = _fallbackGen;
    final asset = _config.asset;
    // Provisional until the seed says which feed answered; the chart
    // keeps the last Chainlink line until the new series replaces it.
    _feed = CryptoPriceFeed.binance;
    debugPrint('[pm-prices] $asset chainlink silent for '
        '>${kChainlinkStaleAfter.inSeconds}s → fallback');
    model
        .fetchRecentSpotPrices(asset, _coingeckoIdForAsset(asset))
        .then((seed) {
      if (_feedDisposed || gen != _fallbackGen) return;
      final feed = seed.points.isEmpty ? CryptoPriceFeed.binance : seed.feed;
      _feed = feed;
      final history = _recent([
        for (final p in seed.points) BtcPriceSnapshot(timestamp: p.t, price: p.p),
      ]);
      final prev = state.asData?.value;
      if (prev != null) {
        state = AsyncData(prev.copyWith(
          priceHistory: history,
          currentPrice: history.isNotEmpty ? history.last.price : null,
          feed: feed,
        ));
      }
      _startFallbackLive(feed, gen);
      _resolveStrike();
    });
  }

  void _startFallbackLive(CryptoPriceFeed feed, int gen) {
    final model = _model;
    if (model == null) return;
    final asset = _config.asset;
    if (feed == CryptoPriceFeed.coingecko) {
      final id = _coingeckoIdForAsset(asset);
      if (id == null) return;
      // 10 s per card keeps even four cards under the free tier's
      // ~30 requests a minute.
      _fallbackPoll = Timer.periodic(const Duration(seconds: 10), (_) async {
        final prices = await model.fetchCoingeckoSpotUsdMulti([id]);
        final p = prices[id];
        if (p != null) {
          _appendFallback([BtcPriceSnapshot(timestamp: DateTime.now(), price: p)],
              gen);
        }
      });
      return;
    }
    if (asset == 'BTC') {
      _binanceSub = BinanceBtcLiveFeed.instance.subscribe().listen(
        (p) => _addFallbackTick(p, gen),
        onError: (_) {},
      );
      return;
    }
    _fallbackPoll = Timer.periodic(const Duration(seconds: 2), (_) async {
      final points = await model.fetchBinanceRecentPrices(asset, seconds: 5);
      _appendFallback([
        for (final p in points) BtcPriceSnapshot(timestamp: p.t, price: p.p),
      ], gen);
    });
  }

  /// The BTC trade socket ticks up to ten times a second; the chart
  /// appends at a steady four a second (latest price held and committed
  /// on a timer) so the line advances evenly.
  static const _tickCadence = Duration(milliseconds: 250);
  double? _pendingPrice;
  Timer? _tickTimer;

  void _addFallbackTick(double price, int gen) {
    _pendingPrice = price;
    _tickTimer ??= Timer(_tickCadence, () {
      _tickTimer = null;
      final pending = _pendingPrice;
      _pendingPrice = null;
      if (pending != null) {
        _appendFallback(
            [BtcPriceSnapshot(timestamp: DateTime.now(), price: pending)], gen);
      }
    });
  }

  void _appendFallback(List<BtcPriceSnapshot> points, int gen) {
    if (_feedDisposed || gen != _fallbackGen) return;
    final prev = state.asData?.value;
    if (prev == null || points.isEmpty) return;
    final last = prev.priceHistory.isNotEmpty
        ? prev.priceHistory.last.timestamp
        : null;
    final fresh = [
      for (final p in points)
        if (last == null || p.timestamp.isAfter(last)) p,
    ];
    if (fresh.isEmpty) return;
    final history = _recent([...prev.priceHistory, ...fresh]);
    state = AsyncData(prev.copyWith(
      priceHistory: history,
      currentPrice: history.last.price,
    ));
  }

  void _stopFallback() {
    _fallbackGen += 1;
    _fallbackPoll?.cancel();
    _fallbackPoll = null;
    _tickTimer?.cancel();
    _tickTimer = null;
    _pendingPrice = null;
    if (_binanceSub != null) {
      _binanceSub?.cancel();
      _binanceSub = null;
      // The shared Binance feed idle-closes 30 s after its last listener.
      BinanceBtcLiveFeed.instance.release();
    }
  }

  /// Price to beat, from Polymarket first, in this order:
  ///   1. Gamma `eventMetadata.priceToBeat` (on the event, when Gamma
  ///      already has it);
  ///   2. the Chainlink TWAP point stamped exactly at the window open,
  ///      from the shared stream (this IS Polymarket's open price;
  ///      verified equal for BTC/ETH/SOL/XRP, and it arrives seconds
  ///      before the site's endpoint answers);
  ///   3. polymarket.com's own open price
  ///      ([PolymarketModel.fetchCryptoWindowOpenPrice]), asked every
  ///      3 s until it answers — this covers a card opened mid-window,
  ///      when the stream's snapshot no longer reaches the open.
  /// In the first ten seconds of a window on a live stream, 3 and the
  /// stand-in wait: the exact point is about to arrive. Otherwise, until
  /// one of those lands, the shown series' point nearest the open (within
  /// 20 s) stands in. An upcoming window has no price to beat.
  void _resolveStrike() {
    if (_feedDisposed) return;
    final prev = state.asData?.value;
    final ev = prev?.event;
    if (prev == null || ev == null) return;
    if (_strikeSlug != ev.slug) {
      _strikeSlug = ev.slug;
      _strikeExact = false;
      _openPriceAskedAt = null;
    }
    if (_strikeExact) return;
    final start = ev.windowStartTime;
    var exact = ev.priceToBeat;
    if (exact == null && start != null) {
      exact = _pointAt(
          ref.read(cryptoReferencePricesProvider).seriesFor(_config.asset),
          start);
    }
    if (exact != null) {
      _strikeExact = true;
      if (prev.priceToBeat != exact) {
        state = AsyncData(prev.copyWith(priceToBeat: exact));
      }
      return;
    }
    final now = DateTime.now();
    if (start == null || start.isAfter(now)) return;
    // Right after the open, a live stream delivers the exact point within
    // a couple of seconds (the site's endpoint lags it): wait for it
    // rather than ask polymarket.com or flash a stand-in.
    if (now.difference(start) < const Duration(seconds: 10) &&
        ref.read(cryptoReferencePricesProvider).isLive(_config.asset, now)) {
      return;
    }
    _askOpenPrice(ev.slug, start);
    if (prev.priceToBeat == null) {
      final near = _priceNearWindowStart(prev.priceHistory, ev);
      if (near != null) state = AsyncData(prev.copyWith(priceToBeat: near));
    }
  }

  void _askOpenPrice(String slug, DateTime start) {
    final model = _model;
    if (model == null || _openPriceInFlight) return;
    final now = DateTime.now();
    final asked = _openPriceAskedAt;
    if (asked != null && now.difference(asked) < const Duration(seconds: 3)) {
      return;
    }
    _openPriceInFlight = true;
    _openPriceAskedAt = now;
    model
        .fetchCryptoWindowOpenPrice(
            asset: _config.asset, windowStart: start, minutes: _minutes)
        .then((open) {
      _openPriceInFlight = false;
      if (_feedDisposed || open == null || _strikeExact) return;
      final cur = state.asData?.value;
      if (cur == null || cur.event?.slug != slug || _strikeSlug != slug) {
        return;
      }
      _strikeExact = true;
      state = AsyncData(cur.copyWith(priceToBeat: open));
    });
  }

  /// The point stamped at [start] (TWAP points sit on whole seconds, as
  /// does every window open), allowing half a second either way.
  static double? _pointAt(List<BtcPriceSnapshot> series, DateTime start) {
    for (var i = series.length - 1; i >= 0; i--) {
      final d = series[i].timestamp.difference(start).inMilliseconds;
      if (d.abs() <= 500) return series[i].price;
      if (d < -500) break;
    }
    return null;
  }

  /// The recorded price nearest the event's slug-derived window open,
  /// or null when history doesn't reach within 20 s of it.
  static double? _priceNearWindowStart(
      List<BtcPriceSnapshot> history, Btc5MinEvent? event) {
    final start = event?.windowStartTime;
    if (start == null || history.isEmpty) return null;
    if (history.first.timestamp
        .isAfter(start.add(const Duration(seconds: 20)))) {
      return null;
    }
    var best = history.first;
    var bestDelta = best.timestamp.difference(start).abs();
    for (final snap in history) {
      final d = snap.timestamp.difference(start).abs();
      if (d < bestDelta) {
        best = snap;
        bestDelta = d;
      }
    }
    if (bestDelta > const Duration(seconds: 20)) return null;
    return best.price;
  }
}

class CryptoPredictNotifier
    extends AutoDisposeFamilyAsyncNotifier<CryptoPredictState, String>
    with _CryptoPriceFeed<String> {
  @override
  PolymarketModel? _model;

  /// The window this notifier tracks, from [cryptoPredictWindowProvider].
  @override
  int _minutes = 5;
  Timer? _countdownTimer;
  Timer? _marketTimer;

  @override
  CryptoAssetConfig get _config =>
      kCryptoPredictAssets.firstWhere((c) => c.asset == arg,
          orElse: () => CryptoAssetConfig(
                asset: arg,
                priceSymbol: arg,
                displayName: arg,
                logoPath: '',
                brandColor: const Color(0xFFF7931A),
              ));

  @override
  Future<CryptoPredictState> build(String arg) async {
    _model = PolymarketModel();
    final config = _config;

    ref.onDispose(() {
      _countdownTimer?.cancel();
      _marketTimer?.cancel();
      _model?.dispose();
    });

    // #167 — Return state synchronously and race all async tasks in
    // parallel: awaiting the Gamma event before yielding initial state
    // caused a "Loading prices…" hang of up to ~2 minutes on slow
    // networks. The chart paints on the shared Chainlink snapshot (well
    // under a second) and the Gamma event slots in via `_refreshMarket`.
    _minutes = ref.watch(cryptoPredictWindowProvider);
    _startPriceFeed();
    _startCountdown();
    // ignore: unawaited_futures
    _refreshMarket(config);

    _marketTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _refreshMarket(config);
    });

    return CryptoPredictState(
      asset: config.asset,
      currentPrice: null,
      priceToBeat: null,
      event: null,
      priceHistory: const [],
      secondsRemaining: _minutes * 60,
    );
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final prev = state.asData?.value;
      if (prev == null) return;

      final remaining = prev.event?.secondsRemaining ?? 0;
      if (remaining <= 0) _refreshMarket(_config);
      state = AsyncData(prev.copyWith(secondsRemaining: remaining));
      _syncPriceFeed();
    });
  }

  Future<void> _refreshMarket(CryptoAssetConfig config) async {
    try {
      final event = await _model!
          .getCryptoUpdown5MinEvent(config.asset, minutes: _minutes);
      final prev = state.asData?.value;
      if (prev == null || event == null) return;

      // #167 — Distinguish the FIRST landing (prev.event == null) from
      // a true window rollover.
      final isFirstLand = prev.event == null;
      final isNewWindow = !isFirstLand && prev.event?.slug != event.slug;

      // KEEP priceHistory across the rollover: snapshots are timestamped
      // and both the trim and the painter's own windowing discard old
      // points. priceToBeat resets so the new window gets its own.
      state = AsyncData(prev.copyWith(
        event: event,
        secondsRemaining: event.secondsRemaining,
        priceToBeat: isNewWindow ? null : prev.priceToBeat,
      ));
      _resolveStrike();
    } catch (_) {}
  }
}

final cryptoPredictProvider = AutoDisposeAsyncNotifierProvider.family<
    CryptoPredictNotifier, CryptoPredictState, String>(
  () => CryptoPredictNotifier(),
);

/// Family key for [cryptoPredictAtWindowProvider]. `epochSeconds` is the
/// 300-second-aligned window-start in UTC seconds — the same value used
/// in the Polymarket slug pattern `<asset>-updown-5m-<epoch>`. When
/// `epochSeconds` is null the provider falls back to the current
/// rolling window (same behavior as [cryptoPredictProvider]).
typedef CryptoPredictWindowKey = ({String asset, int? epochSeconds});

/// #163 — Window-scoped variant of [CryptoPredictNotifier]. The Instant
/// tab's pill strip lets the user pre-stage a bet on a *specific*
/// upcoming 5-minute window; this notifier loads exactly that window
/// instead of the current rolling slug. The live price is the same
/// shared Chainlink feed (the spot price is window-agnostic); an
/// upcoming window has no price to beat until it opens.
class CryptoPredictAtWindowNotifier extends AutoDisposeFamilyAsyncNotifier<
        CryptoPredictState, CryptoPredictWindowKey>
    with _CryptoPriceFeed<CryptoPredictWindowKey> {
  @override
  PolymarketModel? _model;
  Timer? _countdownTimer;
  Timer? _marketTimer;

  /// Window-scoped markets are the five-minute ones.
  @override
  int get _minutes => 5;

  @override
  CryptoAssetConfig get _config =>
      kCryptoPredictAssets.firstWhere((c) => c.asset == arg.asset,
          orElse: () => CryptoAssetConfig(
                asset: arg.asset,
                priceSymbol: arg.asset,
                displayName: arg.asset,
                logoPath: '',
                brandColor: const Color(0xFFF7931A),
              ));

  @override
  Future<CryptoPredictState> build(CryptoPredictWindowKey arg) async {
    _model = PolymarketModel();
    final config = _config;

    ref.onDispose(() {
      _countdownTimer?.cancel();
      _marketTimer?.cancel();
      _model?.dispose();
    });

    // #167 — Return synchronously; race all async loaders in parallel.
    // See [CryptoPredictNotifier.build].
    _startPriceFeed();
    _startCountdown();
    // Background fetch of the (possibly future) window event.
    // ignore: unawaited_futures
    _refreshMarket(config);

    // Only poll for live event updates when watching the current
    // window. Future windows don't move until they go live, so polling
    // them every 10s would just spam Gamma for no UI change.
    if (arg.epochSeconds == null || _isCurrentOrPastWindow(arg.epochSeconds!)) {
      _marketTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        _refreshMarket(config);
      });
    }

    return CryptoPredictState(
      asset: config.asset,
      currentPrice: null,
      priceToBeat: null,
      event: null,
      priceHistory: const [],
      secondsRemaining: 300,
    );
  }

  bool _isCurrentOrPastWindow(int epochSeconds) {
    final nowEpoch =
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final currentWindow = (nowEpoch ~/ 300) * 300;
    return epochSeconds <= currentWindow;
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final prev = state.asData?.value;
      if (prev == null) return;

      final remaining = prev.event?.secondsRemaining ?? 0;
      if (remaining <= 0 && (arg.epochSeconds == null)) {
        _refreshMarket(_config);
      }
      state = AsyncData(prev.copyWith(secondsRemaining: remaining));
      _syncPriceFeed();
    });
  }

  Future<void> _refreshMarket(CryptoAssetConfig config) async {
    try {
      final event = await _model!.getCryptoUpdown5MinEvent(
        config.asset,
        targetWindowEpoch: arg.epochSeconds,
      );
      final prev = state.asData?.value;
      if (prev == null || event == null) return;

      // #167 — see [CryptoPredictNotifier._refreshMarket].
      final isFirstLand = prev.event == null;
      final isNewWindow = !isFirstLand && prev.event?.slug != event.slug;

      state = AsyncData(prev.copyWith(
        event: event,
        secondsRemaining: event.secondsRemaining,
        priceToBeat: isNewWindow ? null : prev.priceToBeat,
      ));
      _resolveStrike();
    } catch (_) {}
  }
}

final cryptoPredictAtWindowProvider = AutoDisposeAsyncNotifierProvider.family<
    CryptoPredictAtWindowNotifier, CryptoPredictState, CryptoPredictWindowKey>(
  () => CryptoPredictAtWindowNotifier(),
);
