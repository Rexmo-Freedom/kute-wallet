/// Venue-reported cumulative profit and loss. Values are USD, not account
/// equity, deposits, withdrawals, or a reconstruction from recent fills.
enum PortfolioPerformanceVenue { trading, predictions }

class PortfolioPerformanceRequest {
  const PortfolioPerformanceRequest({required this.venue, this.walletId});
  final PortfolioPerformanceVenue venue;

  /// Null means the spending account. A non-null ID is an exact Ledger scope;
  /// an unavailable Ledger identity must never fall back to the spending one.
  final String? walletId;

  @override
  bool operator ==(Object other) =>
      other is PortfolioPerformanceRequest &&
      venue == other.venue &&
      walletId == other.walletId;
  @override
  int get hashCode => Object.hash(venue, walletId);
}

class PortfolioPnlPoint {
  const PortfolioPnlPoint(
      {required this.timestamp,
      required this.pnlUsd,
      this.realizedPnlUsd,
      this.openPnlUsd});
  final DateTime timestamp;
  final double pnlUsd;
  final double? realizedPnlUsd;
  final double? openPnlUsd;
}

class PortfolioPerformance {
  const PortfolioPerformance(
      {required this.points,
      required this.sourceLabel,
      required this.basisLabel,
      required this.coverageLabel,
      this.totalPnlUsd,
      this.realizedPnlUsd,
      this.openPnlUsd,
      this.asOf,
      this.otherPnlUsd,
      this.predictions});

  /// Actual published observations, sorted chronologically. Empty means the
  /// venue has published no observations; failures are AsyncError instead.
  final List<PortfolioPnlPoint> points;
  final double? totalPnlUsd;
  final double? realizedPnlUsd;
  final double? openPnlUsd;
  final String sourceLabel;
  final String basisLabel;
  final String coverageLabel;
  final DateTime? asOf;

  /// Polymarket only: the part of the series' last economic P&L that no
  /// position row carries (LP and combo results, rebates, rewards, yield).
  /// Held at its last published value when the P&L is rebuilt from the
  /// positions.
  final double? otherPnlUsd;

  /// Polymarket only: every position of the account, open and closed, as
  /// the Data API reports it. The current P&L and the range statistics
  /// are computed from these; null where the venue has none (Investing).
  final PredictionsBook? predictions;

  /// Change between the last published observations on consecutive UTC dates.
  /// The first date has no invented zero baseline. Dates without observations
  /// are not filled in, and changes spanning those gaps are not called daily.
  /// The latest observation may describe a day that is still in progress.
  List<PortfolioPnlPoint> get dailyPnl => dailyPortfolioPnl(points);

  /// Polymarket's P&L series is a daily snapshot: for most accounts its
  /// last point is the state at 00:00 UTC, so a prediction sold, claimed
  /// or resolved since then is missing from it for up to a day. The
  /// current figures are rebuilt here from [predictions], with Polymarket's
  /// own accounting (its v2 economic P&L), and appended as the last point:
  ///
  /// * realised: every position's realised P&L (sells and claims, fees
  ///   included) plus resolved positions not yet claimed, at their payout
  ///   (the series counts those as settled too), plus [otherPnlUsd];
  /// * open: each live position at [livePrices] (its last Data API price
  ///   where there is none) against its entry cost.
  ///
  /// Where the position list could not be read whole, the series' own
  /// realised figure stands in, plus the positions opened after it.
  PortfolioPerformance withLivePredictions(Map<String, double> livePrices,
      {DateTime? at}) {
    final book = predictions;
    if (book == null) return this;
    var realized = 0.0;
    var open = 0.0;
    final since = asOf;
    if (book.complete) {
      for (final r in book.records) {
        realized += r.decidedPnlUsd ?? r.realizedPnlUsd;
      }
      realized += otherPnlUsd ?? 0;
    } else {
      realized = realizedPnlUsd ?? 0;
      for (final r in book.records) {
        final entered = r.firstEntryAt;
        if (since != null && (entered == null || !entered.isAfter(since))) {
          continue;
        }
        realized += r.decidedPnlUsd ?? r.realizedPnlUsd;
      }
    }
    for (final r in book.records) {
      if (!r.open || r.redeemable) continue;
      final live = livePrices[r.tokenId];
      final price = live != null && live.isFinite ? live : r.currentPrice;
      open += price * r.size - r.entryCostUsd;
    }
    return withNow(openPnlUsd: open, realizedPnlUsd: realized, at: at);
  }

  /// The line to draw for the last [range] (null: all time) and what it
  /// gained over it. The line starts at the P&L the account had when the
  /// range began: the last observation at or before that moment, or zero
  /// when the account is younger than the range (both venues' series start
  /// with the account). Its last point is the latest observation, which is
  /// the headline.
  PortfolioRangeView rangeView(Duration? range) {
    if (points.isEmpty) return const PortfolioRangeView(points: []);
    final last = points.last;
    final PortfolioPnlPoint baseline;
    final List<PortfolioPnlPoint> drawn;
    if (range == null) {
      final first = points.first;
      if (first.pnlUsd == 0) {
        baseline = first;
        drawn = points;
      } else {
        baseline = PortfolioPnlPoint(
            timestamp: first.timestamp.subtract(const Duration(days: 1)),
            pnlUsd: 0,
            realizedPnlUsd: last.realizedPnlUsd == null ? null : 0,
            openPnlUsd: last.openPnlUsd == null ? null : 0);
        drawn = [baseline, ...points];
      }
    } else {
      final start = last.timestamp.subtract(range);
      PortfolioPnlPoint? prior;
      for (final p in points) {
        if (p.timestamp.isAfter(start)) break;
        prior = p;
      }
      baseline = PortfolioPnlPoint(
          timestamp: start,
          pnlUsd: prior?.pnlUsd ?? 0,
          realizedPnlUsd: prior == null
              ? (last.realizedPnlUsd == null ? null : 0)
              : prior.realizedPnlUsd,
          openPnlUsd: prior == null
              ? (last.openPnlUsd == null ? null : 0)
              : prior.openPnlUsd);
      drawn = [
        baseline,
        ...points.where((p) => p.timestamp.isAfter(start)),
      ];
    }
    return PortfolioRangeView(
      points: List.unmodifiable(drawn),
      start: range == null ? null : baseline.timestamp,
      changeUsd: last.pnlUsd - baseline.pnlUsd,
      realizedChangeUsd:
          last.realizedPnlUsd == null || baseline.realizedPnlUsd == null
              ? null
              : last.realizedPnlUsd! - baseline.realizedPnlUsd!,
    );
  }

  /// The same history with one more observation at [at] (now by default)
  /// carrying what the account is worth this moment: [openPnlUsd] from the
  /// live positions and [realizedPnlUsd] from what has settled. The venue's
  /// series is bucketed by day and lags the positions by up to a day, so
  /// without this the headline never matched the positions on screen.
  PortfolioPerformance withNow({
    required double openPnlUsd,
    required double realizedPnlUsd,
    DateTime? at,
  }) {
    final when = (at ?? DateTime.now()).toUtc();
    final total = realizedPnlUsd + openPnlUsd;
    final now = PortfolioPnlPoint(
        timestamp: when,
        pnlUsd: total,
        realizedPnlUsd: realizedPnlUsd,
        openPnlUsd: openPnlUsd);
    final kept = points.where((p) => p.timestamp.isBefore(when)).toList();
    return PortfolioPerformance(
        points: List.unmodifiable([...kept, now]),
        sourceLabel: sourceLabel,
        basisLabel: basisLabel,
        coverageLabel: coverageLabel,
        totalPnlUsd: total,
        realizedPnlUsd: realizedPnlUsd,
        openPnlUsd: openPnlUsd,
        asOf: when,
        otherPnlUsd: otherPnlUsd,
        predictions: predictions);
  }

  /// The same performance carrying [book] (and the series' non-position
  /// P&L, [other]).
  PortfolioPerformance withPredictions(PredictionsBook book,
          {double? other}) =>
      PortfolioPerformance(
          points: points,
          sourceLabel: sourceLabel,
          basisLabel: basisLabel,
          coverageLabel: coverageLabel,
          totalPnlUsd: totalPnlUsd,
          realizedPnlUsd: realizedPnlUsd,
          openPnlUsd: openPnlUsd,
          asOf: asOf,
          otherPnlUsd: other ?? otherPnlUsd,
          predictions: book);
}

/// What [PortfolioPerformance.rangeView] draws: the line from the range's
/// start to the latest observation, and the change over it.
class PortfolioRangeView {
  const PortfolioRangeView(
      {required this.points,
      this.start,
      this.changeUsd,
      this.realizedChangeUsd});
  final List<PortfolioPnlPoint> points;

  /// Null for all time.
  final DateTime? start;
  final double? changeUsd;
  final double? realizedChangeUsd;
}

/// One Polymarket position (one outcome token), open or closed, from the
/// Data API's `/v2/positions`. Amounts are USDC.
class PredictionRecord {
  const PredictionRecord({
    required this.tokenId,
    required this.open,
    required this.redeemable,
    required this.size,
    required this.totalSize,
    required this.avgPrice,
    required this.entryCostUsd,
    required this.currentPrice,
    required this.realizedPnlUsd,
    required this.unrealizedPnlUsd,
    this.firstEntryAt,
    this.lastEventAt,
    this.conditionId = '',
    this.title = '',
    this.slug = '',
    this.eventSlug = '',
    this.outcome = '',
    this.icon = '',
  });

  final String tokenId;

  /// The market the outcome token belongs to (empty when the read did not
  /// say): what the Statistics tab's category split looks the market up by.
  final String conditionId;

  /// The market's question, its slug, its event's slug, the outcome held
  /// and the market's image, as the Data API row names them (empty when
  /// it did not): what the Statistics drill-down lists and groups by.
  final String title;
  final String slug;
  final String eventSlug;
  final String outcome;
  final String icon;

  /// Listed under `status=OPEN`: still held, live or resolved-unclaimed.
  final bool open;

  /// Resolved and waiting to be claimed: its outcome is decided.
  final bool redeemable;
  final double size;

  /// Every share ever bought.
  final double totalSize;
  final double avgPrice;

  /// What the shares still held cost.
  final double entryCostUsd;
  final double currentPrice;
  final double realizedPnlUsd;
  final double unrealizedPnlUsd;
  final DateTime? firstEntryAt;
  final DateTime? lastEventAt;

  /// What was put on this prediction: every share bought at its average
  /// price.
  double get stakeUsd => totalSize * avgPrice;

  /// The final result of a decided prediction (closed, or resolved and
  /// waiting to be claimed); null while it can still move.
  double? get decidedPnlUsd {
    if (!open) return realizedPnlUsd;
    if (redeemable) return realizedPnlUsd + unrealizedPnlUsd;
    return null;
  }
}

/// Every position of a Polymarket account. [complete] is false when the
/// list was cut at the read limit; [coversFrom] is then the oldest exit it
/// still holds, and statistics reaching back before it are unknown.
class PredictionsBook {
  const PredictionsBook(
      {required this.records, this.complete = true, this.coversFrom});
  final List<PredictionRecord> records;
  final bool complete;
  final DateTime? coversFrom;

  /// The predictions made since [since] (all of them when null) and what
  /// was put on them. Null when the list does not reach back that far.
  PredictionRangeStats? statsSince(DateTime? since) {
    if (!complete) {
      final from = coversFrom;
      if (since == null || from == null || since.isBefore(from)) return null;
    }
    bool inRange(DateTime? at) =>
        since == null || (at != null && !at.isBefore(since));
    var count = 0;
    var staked = 0.0;
    for (final r in records) {
      if (inRange(r.firstEntryAt)) {
        count++;
        staked += r.stakeUsd;
      }
    }
    return PredictionRangeStats(count: count, stakedUsd: staked);
  }
}

class PredictionRangeStats {
  const PredictionRangeStats({required this.count, required this.stakedUsd});
  final int count;
  final double stakedUsd;
}

List<PortfolioPnlPoint> dailyPortfolioPnl(
    Iterable<PortfolioPnlPoint> observations) {
  final sorted = observations.toList()
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  final daily = <DateTime, PortfolioPnlPoint>{};
  for (final point in sorted) {
    if (!point.pnlUsd.isFinite ||
        (point.realizedPnlUsd != null && !point.realizedPnlUsd!.isFinite) ||
        (point.openPnlUsd != null && !point.openPnlUsd!.isFinite)) {
      throw const FormatException('Invalid P&L observation');
    }
    final utc = point.timestamp.toUtc();
    daily[DateTime.utc(utc.year, utc.month, utc.day)] = point;
  }
  final result = <PortfolioPnlPoint>[];
  MapEntry<DateTime, PortfolioPnlPoint>? previous;
  for (final entry in daily.entries) {
    final prior = previous;
    if (prior != null && entry.key.difference(prior.key).inDays == 1) {
      result.add(PortfolioPnlPoint(
        timestamp: entry.value.timestamp,
        pnlUsd: _pnlDifference(entry.value.pnlUsd, prior.value.pnlUsd)!,
        realizedPnlUsd: _pnlDifference(
            entry.value.realizedPnlUsd, prior.value.realizedPnlUsd),
        openPnlUsd:
            _pnlDifference(entry.value.openPnlUsd, prior.value.openPnlUsd),
      ));
    }
    previous = entry;
  }
  return List.unmodifiable(result);
}

double? _pnlDifference(double? current, double? previous) {
  if (current == null || previous == null) return null;
  final difference = current - previous;
  if (!difference.isFinite) {
    throw const FormatException('Invalid P&L change');
  }
  return difference;
}

/// Distinct from an empty, successfully read history and a transport failure.
class PortfolioPerformanceUnavailable implements Exception {
  const PortfolioPerformanceUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}
