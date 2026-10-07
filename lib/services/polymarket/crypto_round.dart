// lib/services/polymarket/crypto_round.dart
//
// A crypto Up-or-Down round as Polymarket names it: which asset, how long
// the window is and when it runs, read off the event's own slug (and its
// end, for the hourly rounds, whose slug carries no time stamp). Pure:
// the list, the card and the tap routing all read the same answer.

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
