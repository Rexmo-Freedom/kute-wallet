// lib/services/polymarket/crypto_round.dart
//
// A crypto Up-or-Down round as Polymarket names it: which asset, how long
// the window is and when it runs, read off the event's own slug (and its
// end, for the hourly rounds, whose slug carries no time stamp), and the
// slug written back from an asset, a length and a start, for every length
// the app shows (5m, 15m, 1h, 4h). Pure: the list, the card, the Instant
// screen's strip and the tap routing all read the same answer.
//
// Slugs, checked against Gamma on 8 November 2026 (read-only):
//   * `btc-updown-5m-1794153900`, `btc-updown-15m-1794153600`: the asset's
//     ticker, the length in minutes, the start in UTC seconds;
//   * `eth-updown-4h-1794157200`: four hours write `4h`, never `240m`;
//   * `bitcoin-up-or-down-november-8-2026-1pm-et`: the hourly rounds carry
//     the asset's NAME and the start hour on the New York clock
//     (`eventStartTime` 18:00Z = 1 PM EST), no epoch. The app writes them
//     from the clock too ([polyCryptoRoundSlug]): Eastern Time is UTC-4
//     from the second Sunday of March at 2 AM to the first Sunday of
//     November at 2 AM, UTC-5 otherwise (US law since 2007).

/// One round of a crypto Up-or-Down series.
class PolyCryptoRound {
  /// The asset as the slug writes it, lower case (`btc`, `bitcoin`).
  final String asset;
  final Duration window;
  final DateTime start;

  const PolyCryptoRound({
    required this.asset,
    required this.window,
    required this.start,
  });

  DateTime get end => start.add(window);

  /// Whether the round is running at [now].
  bool inPlayAt(DateTime now) => !now.isBefore(start) && now.isBefore(end);
}

final RegExp _kWindowSlug = RegExp(r'^([a-z0-9]+)-updown-(\d+)(m|h)-(\d{9,})$');

/// `bitcoin-up-or-down-october-4-2026-6pm-et`: an hourly round.
final RegExp _kHourlySlug = RegExp(
    r'^([a-z0-9]+)-up-or-down-[a-z]+-\d{1,2}-(?:\d{4}-)?\d{1,2}(?:am|pm)-et$');

/// The round the event with this [slug] is, or null when it is not one.
/// `btc-updown-15m-1791152100` and `btc-updown-4h-1791144000` name their
/// window and start; an hourly round is the hour before its [endDate].
/// The daily "Up or Down on October 5?" markets are not rounds: they have
/// no window to show.
PolyCryptoRound? polyCryptoRoundOf(String slug, {DateTime? endDate}) {
  final s = slug.trim().toLowerCase();
  final m = _kWindowSlug.firstMatch(s);
  if (m != null) {
    final n = int.parse(m.group(2)!);
    final epoch = int.parse(m.group(4)!);
    if (n <= 0) return null;
    return PolyCryptoRound(
      asset: m.group(1)!,
      window: m.group(3) == 'h' ? Duration(hours: n) : Duration(minutes: n),
      start: DateTime.fromMillisecondsSinceEpoch(epoch * 1000, isUtc: true),
    );
  }
  final h = _kHourlySlug.firstMatch(s);
  if (h != null && endDate != null) {
    const window = Duration(hours: 1);
    return PolyCryptoRound(
      asset: h.group(1)!,
      window: window,
      start: endDate.toUtc().subtract(window),
    );
  }
  return null;
}

/// The ticker of a round's slug asset: `btc-updown-15m-…` writes the
/// ticker, the hourly `bitcoin-up-or-down-…` the name.
String polyRoundTicker(String slugAsset) =>
    switch (slugAsset.trim().toLowerCase()) {
      'bitcoin' => 'BTC',
      'ethereum' => 'ETH',
      'solana' => 'SOL',
      'dogecoin' => 'DOGE',
      'hyperliquid' => 'HYPE',
      final other => other.toUpperCase(),
    };

/// The asset as an hourly round's slug writes it: the coin's name for the
/// ones Polymarket names, the ticker for the rest (`xrp`, `bnb`, `hype`).
String polyRoundSlugName(String asset) => switch (polyRoundTicker(asset)) {
      'BTC' => 'bitcoin',
      'ETH' => 'ethereum',
      'SOL' => 'solana',
      'DOGE' => 'dogecoin',
      final other => other.toLowerCase(),
    };

const List<String> _kMonths = [
  'january',
  'february',
  'march',
  'april',
  'may',
  'june',
  'july',
  'august',
  'september',
  'october',
  'november',
  'december',
];

/// New York's offset from UTC in hours at [utc]: -4 under daylight time
/// (second Sunday of March 2 AM to first Sunday of November 2 AM), -5
/// otherwise.
int polyEasternOffsetHours(DateTime utc) {
  final t = utc.toUtc();
  DateTime nthSunday(int month, int n) {
    final first = DateTime.utc(t.year, month, 1);
    final toSunday = (DateTime.sunday - first.weekday) % 7;
    return DateTime.utc(t.year, month, 1 + toSunday + 7 * (n - 1));
  }

  // 2 AM EST is 07:00Z; 2 AM EDT is 06:00Z.
  final start = nthSunday(3, 2).add(const Duration(hours: 7));
  final end = nthSunday(11, 1).add(const Duration(hours: 6));
  return !t.isBefore(start) && t.isBefore(end) ? -4 : -5;
}

/// The slug of the round of [asset] (ticker or slug name, any case) that
/// is [minutes] long and starts at [startEpoch] (UTC seconds), as Gamma
/// names it (see the file header).
String polyCryptoRoundSlug(String asset, int minutes, int startEpoch) {
  if (minutes == 60) {
    final utc =
        DateTime.fromMillisecondsSinceEpoch(startEpoch * 1000, isUtc: true);
    final et = utc.add(Duration(hours: polyEasternOffsetHours(utc)));
    final hour = et.hour % 12 == 0 ? 12 : et.hour % 12;
    final half = et.hour < 12 ? 'am' : 'pm';
    return '${polyRoundSlugName(asset)}-up-or-down-${_kMonths[et.month - 1]}-'
        '${et.day}-${et.year}-$hour$half-et';
  }
  final ticker = polyRoundTicker(asset).toLowerCase();
  final length = minutes % 60 == 0 ? '${minutes ~/ 60}h' : '${minutes}m';
  return '$ticker-updown-$length-$startEpoch';
}

/// The start (UTC seconds) of the [minutes]-long round that holds [now]:
/// rounds start on every multiple of their length on the clock.
int polyRoundStartAt(DateTime now, int minutes) {
  final span = minutes * 60;
  return now.toUtc().millisecondsSinceEpoch ~/ 1000 ~/ span * span;
}

final RegExp _kFiveMinuteSlug = RegExp(r'^([a-z0-9]+)-updown-5m(?:-|$)');

/// Whether the event with this [slug] opens on the live round sheet
/// instead of the market sheet. The round sheet draws the five-minute
/// round in play of one of [assets] (the app's own list, any case) and
/// nothing else: a 15-minute, hourly, 4-hour or daily market, and a
/// five-minute one of an asset the sheet does not know, open as the
/// market they are.
bool polyOpensRoundSheet(String slug, Iterable<String> assets) {
  final m = _kFiveMinuteSlug.firstMatch(slug.trim().toLowerCase());
  if (m == null) return false;
  final asset = m.group(1)!;
  return assets.any((a) => a.toLowerCase() == asset);
}

final RegExp _kUpDownTitle =
    RegExp(r'^(.+?)\s+Up or Down\s+-\s+', caseSensitive: false);

/// The asset's name off a round's title ("Bitcoin Up or Down - October 4,
/// 10:15PM-10:30PM ET" gives "Bitcoin"); null when the title is not
/// written that way.
String? polyCryptoRoundAssetName(String title) =>
    _kUpDownTitle.firstMatch(title.trim())?.group(1)?.trim();

/// The `market_kind` analytics value of a 5-minute crypto Up or Down round.
const String kCryptoUpDown5mKind = 'crypto_updown_5m';

/// Whether the event with this [slug] is a 5-minute crypto Up or Down
/// round (`btc-updown-5m-1791152100`, any asset). 15-minute, hourly,
/// 4-hour and daily rounds are not.
bool polyIsCryptoUpDown5m(String? slug) {
  if (slug == null || slug.isEmpty) return false;
  return polyCryptoRoundOf(slug)?.window == const Duration(minutes: 5);
}

/// The `window` value on the slip and order events: `next` for a 5-minute
/// window still to start at [at], `current` for one in play; null for
/// anything else.
String? polyRoundWindowParam(String? slug, DateTime at) {
  if (!polyIsCryptoUpDown5m(slug)) return null;
  return polyCryptoRoundOf(slug!)!.start.isAfter(at) ? 'next' : 'current';
}

/// `window` ([window], else read off [slug] at [at]) and the exact
/// `seconds_to_window_end` for a 5-minute window; empty for anything else.
Map<String, Object> polyRoundWindowParams(String? slug,
    {String? window, required DateTime at}) {
  if (!polyIsCryptoUpDown5m(slug)) return const {};
  final shown = window ?? polyRoundWindowParam(slug, at)!;
  return {
    'window': shown,
    'seconds_to_window_end':
        polyCryptoRoundOf(slug!)!.end.difference(at).inSeconds,
  };
}
