// Where a 5-minute card's buttons bet: this window for its first two
// minutes, then the next one once it has real prices, never before and
// never on an old or invented price (crypto_next_round.dart). The window's
// name and the `window` analytics values are read off the slug.

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/screens/polymarket/components/round_window_label.dart';
import 'package:kute/services/one_balance/funded_orders.dart';
import 'package:kute/services/polymarket/crypto_next_round.dart';
import 'package:kute/services/polymarket/crypto_round.dart';
import 'package:kute/services/polymarket_clob_websocket.dart';
import 'package:kute/services/tracking_service.dart';
import 'package:kute/services/venue_analytics.dart';

final _start = DateTime.utc(2026, 11, 8, 12, 0);
int _epoch(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;
final _round = PolyCryptoRound(
    asset: 'btc', window: const Duration(minutes: 5), start: _start);
final _nextStart = _start.add(const Duration(minutes: 5));

Btc5MinEvent _next({
  bool active = true,
  bool closed = false,
  bool accepting = true,
  String? up = 'next-up',
  String? down = 'next-down',
  DateTime? start,
}) {
  final s = start ?? _nextStart;
  return Btc5MinEvent(
    slug: 'btc-updown-5m-${_epoch(s)}',
    title: 'Bitcoin Up or Down',
    windowStartTime: s,
    endDate: s.add(const Duration(minutes: 5)),
    upPrice: 0.5,
    downPrice: 0.5,
    upTokenId: up,
    downTokenId: down,
    active: active,
    closed: closed,
    acceptingOrders: accepting,
  );
}

PolymarketLiveBook? _book(String id, {List<double> bids = const [], List<double> asks = const []}) {
  final books = PolymarketLiveBooks.instance;
  books.debugSeed(PolymarketBookMessage(
    assetId: id,
    market: 'm',
    timestamp: 0,
    hash: '',
    bids: [for (final p in bids) PolymarketOrderSummary(price: p, size: 100)],
    asks: [for (final p in asks) PolymarketOrderSummary(price: p, size: 100)],
  ));
  return books.latest(id);
}

void main() {
  setUp(PolymarketLiveBooks.instance.reset);
  tearDown(PolymarketLiveBooks.instance.reset);

  PolyNextRoundButtons? at(
    DateTime now, {
    PolyCryptoRound? round,
    Btc5MinEvent? next,
    bool noNext = false,
    PolymarketLiveBook? up,
    PolymarketLiveBook? down,
    bool noBooks = false,
  }) =>
      polyNextRoundButtons(
        round: round ?? _round,
        next: noNext ? null : next ?? _next(),
        upBook: noBooks
            ? null
            : up ?? _book('next-up', bids: [0.50], asks: [0.51]),
        downBook: noBooks
            ? null
            : down ?? _book('next-down', bids: [0.49], asks: [0.50]),
        now: now,
      );

  group('the moment', () {
    test('before the constant: this window, at it: the next', () {
      final moment = _start.add(kCryptoRoundButtonsStayFor);
      expect(at(moment.subtract(const Duration(seconds: 1))), isNull);
      final rolled = at(moment)!;
      expect(rolled.up, closeTo(0.505, 1e-9));
      expect(rolled.start, _nextStart);
      expect(rolled.event.upTokenId, 'next-up');
    });

    test('the two minutes are one constant', () {
      expect(kCryptoRoundButtonsStayFor, const Duration(minutes: 2));
    });

    test('past the window\'s end it holds: never back to a finished window',
        () {
      expect(at(_nextStart.add(const Duration(seconds: 2))), isNotNull);
    });

    test('the next window is read a little before the moment, not earlier',
        () {
      final moment = _start.add(kCryptoRoundButtonsStayFor);
      expect(
          polyNextRoundWanted(
              _round, moment.subtract(kCryptoNextRoundReadAhead)),
          isTrue);
      expect(
          polyNextRoundWanted(_round,
              moment.subtract(kCryptoNextRoundReadAhead + const Duration(seconds: 1))),
          isFalse);
    });

    test('a 15-minute window and no window never roll', () {
      final fifteen = PolyCryptoRound(
          asset: 'btc', window: const Duration(minutes: 15), start: _start);
      final late = _start.add(const Duration(minutes: 13));
      expect(polyNextRoundWanted(fifteen, late), isFalse);
      expect(polyNextRoundWanted(null, late), isFalse);
      expect(at(late, round: fifteen), isNull);
    });
  });

  group('no real prices: stays on this window', () {
    final late = _start.add(const Duration(minutes: 4, seconds: 55));

    test('not listed', () => expect(at(late, noNext: true), isNull));
    test('no book at all', () => expect(at(late, noBooks: true), isNull));

    test('not taking orders, closed, inactive or missing a token', () {
      for (final next in [
        _next(accepting: false),
        _next(closed: true),
        _next(active: false),
        _next(up: null),
        _next(down: ''),
      ]) {
        expect(at(late, next: next), isNull);
      }
    });

    test('some other window', () {
      expect(
          at(late, next: _next(start: _nextStart.add(const Duration(minutes: 5)))),
          isNull);
    });

    test('a one-sided book is no price (no invented midpoint)', () {
      expect(at(late, up: _book('next-up', asks: [0.51])), isNull);
      expect(at(late, up: _book('next-up', bids: [0.50])), isNull);
    });

    test('a book wider than 10¢ is no price: 1¢/99¢ never reads 50%', () {
      expect(at(late, up: _book('next-up', bids: [0.01], asks: [0.99])), isNull);
      expect(at(late, down: _book('next-down', bids: [0.20], asks: [0.40])),
          isNull);
    });

    test('exactly 10¢ wide still is one', () {
      expect(at(late, up: _book('next-up', bids: [0.45], asks: [0.55])),
          isNotNull);
    });

    test('Gamma\'s own 50/50 alone never rolls the buttons', () {
      expect(at(late, next: _next(), noBooks: true), isNull);
    });
  });

  group('analytics', () {
    const slug = 'btc-updown-5m-1794139200'; // 2026-11-08 12:00 UTC
    final start = DateTime.fromMillisecondsSinceEpoch(1794139200 * 1000,
        isUtc: true);

    test('next until it starts, current after it', () {
      expect(polyRoundWindowParam(slug, start.subtract(const Duration(seconds: 1))),
          'next');
      expect(polyRoundWindowParam(slug, start), 'current');
      expect(polyRoundWindowParam('will-it-rain', start), isNull);
      expect(polyRoundWindowParam('btc-updown-15m-1794139200', start), isNull);
    });

    test('exact seconds to the end, the window kept as given', () {
      final at = start.add(const Duration(seconds: 37));
      expect(polyRoundWindowParams(slug, at: at),
          {'window': 'current', 'seconds_to_window_end': 263});
      expect(polyRoundWindowParams(slug, window: 'next', at: at),
          {'window': 'next', 'seconds_to_window_end': 263});
      expect(polyRoundWindowParams(null, at: at), isEmpty);
      expect(polyRoundWindowParams('will-it-rain', at: at), isEmpty);
    });
  });

  group('the order\'s outcome events', () {
    const slug = 'btc-updown-5m-1794139200';
    late List<(String, Map<String, Object>?)> events;
    setUp(() {
      events = [];
      TrackingService.debugTrackObserver = (e, p) => events.add((e, p));
    });
    tearDown(() {
      TrackingService.debugTrackObserver = null;
      VenueAnalytics.unstage('pm', 'tok');
    });

    test('placed and failed carry the window the slip opened on and the '
        'exact seconds to its end', () {
      VenueAnalytics.stage('pm', 'tok', {'window': 'next'});
      TrackingService.polymarketBetPlaced(
        marketId: 'tok',
        outcome: 'buy',
        amount: 5,
        price: 0.5,
        shares: 10,
        marketSlug: slug,
        logAffiliateEvent: false,
      );
      TrackingService.polymarketBetFailed(
          marketId: 'tok', reason: 'x', marketSlug: slug);
      for (final name in ['polymarket_bet_placed', 'polymarket_bet_failed']) {
        final p = events.singleWhere((e) => e.$1 == name).$2!;
        expect(p['window'], 'next', reason: name);
        expect(p['seconds_to_window_end'], isA<int>(), reason: name);
      }
    });

    test('nothing on any other market', () {
      TrackingService.polymarketBetPlaced(
        marketId: 'tok',
        outcome: 'buy',
        amount: 5,
        price: 0.5,
        shares: 10,
        marketSlug: 'will-it-rain',
        logAffiliateEvent: false,
      );
      final p = events.singleWhere((e) => e.$1 == 'polymarket_bet_placed').$2!;
      expect(p.containsKey('window'), isFalse);
      expect(p.containsKey('seconds_to_window_end'), isFalse);
    });
  });

  group('the window\'s name', () {
    setUpAll(() async {
      await initializeDateFormatting();
    });
    // 12:00 UTC on this slug; the clock is the phone's zone.
    const slug = 'btc-updown-5m-1794139200';
    final local = DateTime.fromMillisecondsSinceEpoch(1794139200 * 1000,
            isUtc: true)
        .toLocal();
    String h12(DateTime t) =>
        '${t.hour % 12 == 0 ? 12 : t.hour % 12}:${t.minute.toString().padLeft(2, '0')}';
    String h24(DateTime t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final end = local.add(const Duration(minutes: 5));

    test('English: the clock without AM or PM, in the phone\'s zone', () {
      expect(polyRoundWindowName(l10nForLanguage('en'), slug),
          'BTC up or down · ${h12(local)}\u2060–\u2060${h12(end)}');
    });

    test('the phone\'s 24-hour setting wins', () {
      expect(polyRoundWindowName(l10nForLanguage('en'), slug, use24h: true),
          'BTC up or down · ${h24(local)}\u2060–\u2060${h24(end)}');
    });

    test('a 24-hour language reads 24 hours, in its own words', () {
      expect(polyRoundWindowName(l10nForLanguage('de'), slug),
          'BTC hoch oder runter · ${h24(local)}\u2060–\u2060${h24(end)}');
    });

    test('the range never breaks: a line holds it whole, in every language',
        () {
      for (final code in languageNativeNames.keys) {
        final l10n = l10nForLanguage(code);
        for (final use24h in [false, true]) {
          final name = polyRoundWindowName(l10n, slug, use24h: use24h)!;
          final from = name.indexOf(RegExp(r'\d'), name.indexOf(' · '));
          final range = name.substring(from);
          expect(range, contains('\u2060–\u2060'), reason: code);
          // Nothing in a clock to break at either: never a plain space
          // (Bulgarian's "12:00 ч." holds with a no-break one), no AM or PM.
          expect(range, isNot(contains(' ')), reason: code);
          expect(range, isNot(contains(RegExp('[AP]M'))), reason: code);
          const style = TextStyle(fontSize: 10);
          TextPainter lay(String text, double width) => TextPainter(
              text: TextSpan(text: text, style: style),
              textDirection: TextDirection.ltr)
            ..layout(maxWidth: width);
          final whole = lay(range, double.infinity).width.ceilToDouble() + 1;
          final full = lay(name, double.infinity).width.ceilToDouble();
          // Every width that can hold the range: the line break, if any,
          // comes before the range and never inside it.
          for (var w = whole; w <= full; w += 3) {
            final painter = lay(name, w);
            final line = painter.getLineBoundary(TextPosition(offset: from));
            expect(line.end, greaterThanOrEqualTo(name.length),
                reason: '$code at $w: "$name"');
            painter.dispose();
          }
        }
      }
    });

    test('the joiners are not counted on a funded order\'s one line', () {
      final name = polyRoundWindowName(l10nForLanguage('it'), slug)!;
      final short = FundedOrderLabel.shortName(name);
      expect(short, isNot(contains('\u2060')));
      expect(short, name.replaceAll('\u2060', ''));
    });

    test('every language has the two strings, placeholders kept', () {
      for (final code in languageNativeNames.keys) {
        final l10n = l10nForLanguage(code);
        expect(l10n.predictNextWindow('7:20'), contains('7:20'), reason: code);
        final name = l10n.predictRoundWindow('BTC', '7:20', '7:25');
        expect(name, contains('BTC'), reason: code);
        expect(name, contains('7:20–7:25'), reason: code);
      }
    });

    test('never a share-card word: no "bet" in either string', () {
      for (final code in languageNativeNames.keys) {
        final l10n = l10nForLanguage(code);
        expect(l10n.predictRoundWindow('BTC', '7:20', '7:25').toLowerCase(),
            isNot(contains('bet')), reason: code);
      }
    });

    test('only a 5-minute round has one', () {
      final l10n = l10nForLanguage('en');
      expect(polyRoundWindowName(l10n, 'btc-updown-15m-1794139200'), isNull);
      expect(polyRoundWindowName(l10n, 'will-it-rain'), isNull);
      expect(polyRoundWindowName(l10n, null), isNull);
    });
  });
}
