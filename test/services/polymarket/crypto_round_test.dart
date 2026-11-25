// A crypto Up-or-Down round read off its event, where its tap leads, how
// its list is ordered and how its card writes it.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_provider.dart'
    show kCryptoPredictAssets;
import 'package:kute/screens/polymarket/components/market_card.dart';
import 'package:kute/screens/polymarket/components/poly_browse_bar.dart';
import 'package:kute/services/polymarket/crypto_round.dart';
import 'package:kute/services/polymarket/market_card_shape.dart';
import 'package:kute/theme/app_theme.dart';

final _assets = [for (final c in kCryptoPredictAssets) c.asset];

Future<void> _pump(WidgetTester tester, Widget card) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        theme: ThemeData(
          splashFactory: NoSplash.splashFactory,
          fontFamily: 'Inter',
          extensions: [AppColorsExtension.light()],
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(children: [card]),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  setUpAll(initializeDateFormatting);

  group('the round an event is', () {
    test('a 15-minute round names its asset, window and start', () {
      final round = polyCryptoRoundOf('btc-updown-15m-1791152100')!;
      expect(round.asset, 'btc');
      expect(round.window, const Duration(minutes: 15));
      expect(round.start, DateTime.utc(2026, 10, 4, 22, 15));
      expect(round.end, DateTime.utc(2026, 10, 4, 22, 30));
      expect(round.inPlayAt(DateTime.utc(2026, 10, 4, 22, 20)), isTrue);
      expect(round.inPlayAt(DateTime.utc(2026, 10, 4, 22, 30)), isFalse);
      expect(round.inPlayAt(DateTime.utc(2026, 10, 4, 22, 14)), isFalse);
    });

    test('five minutes and four hours', () {
      expect(polyCryptoRoundOf('eth-updown-5m-1791152100')!.window,
          const Duration(minutes: 5));
      final four = polyCryptoRoundOf('doge-updown-4h-1791144000')!;
      expect(four.window, const Duration(hours: 4));
      expect(four.end, DateTime.utc(2026, 10, 5));
    });

    test('an hourly round is the hour before its end', () {
      final round = polyCryptoRoundOf(
          'bitcoin-up-or-down-october-4-2026-6pm-et',
          endDate: DateTime.utc(2026, 10, 4, 23))!;
      expect(round.asset, 'bitcoin');
      expect(round.window, const Duration(hours: 1));
      expect(round.start, DateTime.utc(2026, 10, 4, 22));
      // Without its end there is no window to give.
      expect(polyCryptoRoundOf('bitcoin-up-or-down-october-4-2026-6pm-et'),
          isNull);
    });

    test('the daily market and everything else are not rounds', () {
      for (final slug in [
        'bitcoin-up-or-down-on-october-5-2026',
        'what-price-will-bitcoin-hit-on-october-4-2026',
        'bitcoin-above-on-october-4-6pm-et',
        'will-it-rain',
        '',
      ]) {
        expect(polyCryptoRoundOf(slug, endDate: DateTime.utc(2026, 10, 5)),
            isNull,
            reason: slug);
      }
    });

    test('the asset name comes off the title', () {
      expect(
          polyCryptoRoundAssetName(
              'Bitcoin Up or Down - October 4, 10:15PM-10:30PM ET'),
          'Bitcoin');
      expect(
          polyCryptoRoundAssetName('Hyperliquid Up or Down - October 4, 6PM ET'),
          'Hyperliquid');
      expect(polyCryptoRoundAssetName('Bitcoin Up or Down on October 5?'),
          isNull);
    });
  });

  group('where a tap leads', () {
    test('only a five-minute round of a known asset opens the round sheet',
        () {
      expect(polyOpensRoundSheet('btc-updown-5m-1791152100', _assets), isTrue);
      expect(polyOpensRoundSheet('ETH-updown-5m-1791152100', _assets), isTrue);
      // The shell a five-minute tile opens before its round is read.
      expect(polyOpensRoundSheet('sol-updown-5m', _assets), isTrue);
    });

    test('a 15-minute card opens its own market, not the 5-minute round', () {
      for (final slug in [
        'btc-updown-15m-1791152100',
        'btc-updown-4h-1791144000',
        'bitcoin-up-or-down-october-4-2026-6pm-et',
        'bitcoin-up-or-down-on-october-5-2026',
        // Five minutes, but not an asset the round sheet draws.
        'doge-updown-5m-1791152100',
        'hype-updown-5m-1791152100',
      ]) {
        expect(polyOpensRoundSheet(slug, _assets), isFalse, reason: slug);
      }
    });
  });

  group('the order of a window list', () {
    test('15 Min, 1 Hour and 4 Hours read the rounds soonest to end first',
        () {
      for (final (sub, tag) in [('15m', '15M'), ('1h', '1H'), ('4h', '4H')]) {
        final params = polyFeedSourceParams(
            PolyFeedQuery(pill: PolyPill.crypto, sub: sub));
        expect(params, hasLength(1));
        final p = params.single;
        expect(p['tag_slug'], tag);
        expect(p['order'], 'endDate', reason: sub);
        expect(p['ascending'], 'true');
        expect(p['closed'], 'false');
        // From now on, to the minute: rounds that ended are not read.
        final from = DateTime.parse(p['end_date_min']!);
        expect(from.second, 0);
        expect(DateTime.now().toUtc().difference(from).inSeconds,
            inInclusiveRange(0, 120));
      }
    });

    test('the other Crypto lists read the most traded first', () {
      final weekly = polyFeedSourceParams(
              const PolyFeedQuery(pill: PolyPill.crypto, sub: 'weekly'))
          .single;
      expect(weekly['order'], 'volume24hr');
      expect(weekly.containsKey('end_date_min'), isFalse);
    });
  });

  group('how a round is written', () {
    test('the other side is what the leader leaves of 100', () {
      expect(polyCardOtherSideChance(0.505), '49.5%');
      expect(polyCardChance(0.505), '50.5%');
      expect(polyCardOtherSideChance(0.5149), '48.5%');
      expect(polyCardChance(0.5149), '51.5%');
      expect(polyCardOtherSideChance(0.93), '7%');
      expect(polyCardOtherSideChance(0.5), '50%');
      expect(polyCardOtherSideChance(0.999), '<1%');
      expect(polyCardOtherSideChance(1), '0%');
    });

    test('the window reads as the Crypto row names it', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(polyRoundWindowLabel(l10n, const Duration(minutes: 15)), '15 Min');
      expect(polyRoundWindowLabel(l10n, const Duration(hours: 1)), '1 Hour');
      expect(polyRoundWindowLabel(l10n, const Duration(hours: 4)), '4 Hours');
      expect(polyRoundWindowLabel(l10n, const Duration(minutes: 30)), '30m');
    });

    test('the round time is the local clock, with the day when not today',
        () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final start = DateTime(2026, 10, 4, 22, 15);
      final end = DateTime(2026, 10, 4, 22, 30);
      // (The locale's clock writes a narrow space before PM.)
      expect(polyRoundTimes(start, end, l10n, now: DateTime(2026, 10, 4, 9)),
          matches(RegExp(r'^10:15\sPM – 10:30\sPM$')));
      expect(polyRoundTimes(start, end, l10n, now: DateTime(2026, 10, 3, 9)),
          matches(RegExp(r'^Oct 4, 10:15\sPM – 10:30\sPM$')));
    });

    testWidgets('the card: leader first, sides adding to 100, the round time',
        (tester) async {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day, 22, 15);
      final end = start.add(const Duration(minutes: 15));
      await _pump(
        tester,
        MarketCard(
          title: 'Bitcoin · 15 Min',
          outcomes: const [
            PolymarketOutcome(name: 'Up', price: 0.4962, tokenId: 'up'),
            PolymarketOutcome(name: 'Down', price: 0.5049, tokenId: 'down'),
          ],
          volume: 157,
          category: 'crypto',
          endDate: end,
          round: (start: start, end: end),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Bitcoin · 15 Min'), findsOneWidget);
      // Down leads at 50.5; Up is what is left, 49.5 (not its own 49.6).
      expect(find.text('50.5%'), findsOneWidget);
      expect(find.text('49.5%'), findsOneWidget);
      expect(find.text('49.6%'), findsNothing);
      expect(tester.getTopLeft(find.text('Down')).dy,
          lessThan(tester.getTopLeft(find.text('Up')).dy));
      // The meta line starts with the round's time, not a date.
      expect(find.textContaining(RegExp(r'^10:15\sPM – 10:30\sPM')),
          findsOneWidget);
    });
  });

  test('polyIsCryptoUpDown5m: 5-minute crypto rounds only', () {
    expect(polyIsCryptoUpDown5m('btc-updown-5m-1791152100'), isTrue);
    expect(polyIsCryptoUpDown5m('ETH-updown-5m-1791152100'), isTrue);
    expect(polyIsCryptoUpDown5m('btc-updown-15m-1791152100'), isFalse);
    expect(polyIsCryptoUpDown5m('btc-updown-4h-1791144000'), isFalse);
    expect(polyIsCryptoUpDown5m('bitcoin-up-or-down-october-4-2026-6pm-et'),
        isFalse);
    expect(polyIsCryptoUpDown5m('will-it-rain'), isFalse);
    expect(polyIsCryptoUpDown5m(null), isFalse);
    expect(kCryptoUpDown5mKind, 'crypto_updown_5m');
  });

  group('the clock the rounds run on (Gamma, read 8 November 2026)', () {
    int epoch(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

    test('four hours: 12 AM, 4 AM, 8 AM, 12 PM, 4 PM, 8 PM New York time',
        () {
      // Standard time. Listed by Gamma at 17:28Z on 8 November 2026:
      // `btc-updown-4h-1794157200` (17:00Z, "12:00PM-4:00PM ET", live, Up
      // 47¢), `eth-updown-4h-1794157200`; `btc-updown-4h-1794153600`
      // (16:00Z, the UTC multiple) does not exist, nor 12:00Z, 14:00Z or
      // 15:00Z. The day's others: 1794099600 (01:00Z), 1794114000 (05:00Z),
      // 1794128400 (09:00Z), 1794142800 (13:00Z), 1794171600 (21:00Z).
      final at = DateTime.utc(2026, 11, 8, 17, 23);
      expect(polyRoundStartAt(at, 240), 1794157200);
      expect(polyCryptoRoundSlug('BTC', 240, polyRoundStartAt(at, 240)),
          'btc-updown-4h-1794157200');
      expect(polyCryptoRoundSlug('ETH', 240, polyRoundStartAt(at, 240)),
          'eth-updown-4h-1794157200');
      expect(polyRoundStartAt(DateTime.utc(2026, 11, 8, 20, 59), 240),
          1794157200);
      expect(polyRoundStartAt(DateTime.utc(2026, 11, 8, 21), 240), 1794171600);
      expect(polyRoundStartAt(DateTime.utc(2026, 11, 8, 1, 30), 240),
          1794099600);
      expect(polyRoundStartAt(DateTime.utc(2026, 11, 8, 0, 30), 240),
          epoch(DateTime.utc(2026, 11, 7, 21)));
      // Daylight time. Listed by Gamma for 25 October 2026:
      // `btc-updown-4h-1792929600` (12:00Z, "8:00AM-12:00PM ET") and
      // `btc-updown-4h-1792944000` (16:00Z, "12:00PM-4:00PM ET"); nothing
      // at 13:00Z or 17:00Z.
      expect(polyRoundStartAt(DateTime.utc(2026, 10, 25, 13, 10), 240),
          1792929600);
      expect(polyRoundStartAt(DateTime.utc(2026, 10, 25, 17, 23), 240),
          1792944000);
      expect(
          polyCryptoRoundSlug(
              'btc', 240, polyRoundStartAt(DateTime.utc(2026, 10, 25, 17), 240)),
          'btc-updown-4h-1792944000');
    });

    test('five and fifteen minutes divide the hour: UTC multiples', () {
      // Listed by Gamma at 17:29Z on 8 November 2026:
      // `btc-updown-15m-1794158100` (17:15Z, live, Up 78.5¢) and
      // `btc-updown-5m-1794158700` (17:25Z, live), ETH, SOL and XRP alike.
      final at = DateTime.utc(2026, 11, 8, 17, 29, 39);
      expect(polyCryptoRoundSlug('BTC', 15, polyRoundStartAt(at, 15)),
          'btc-updown-15m-1794158100');
      expect(polyCryptoRoundSlug('sol', 15, polyRoundStartAt(at, 15)),
          'sol-updown-15m-1794158100');
      expect(polyCryptoRoundSlug('BTC', 5, polyRoundStartAt(at, 5)),
          'btc-updown-5m-1794158700');
      expect(polyCryptoRoundSlug('ETH', 5, polyRoundStartAt(at, 5)),
          'eth-updown-5m-1794158700');
      // The next ones, as the strip names them.
      expect(polyCryptoRoundSlug('BTC', 15, polyRoundStartAt(at, 15) + 900),
          'btc-updown-15m-1794159000');
    });

    test('the hour: the New York clock in the slug, standard time now', () {
      // Listed by Gamma at 17:29Z on 8 November 2026:
      // `bitcoin-up-or-down-november-8-2026-12pm-et` (endDate 18:00Z, live,
      // Up 24.5¢) and `…-1pm-et` (endDate 19:00Z); `ethereum-`, `solana-`
      // and `xrp-up-or-down-…` the same. `btc-updown-1h-1794157200` does
      // not exist.
      final at = DateTime.utc(2026, 11, 8, 17, 29);
      expect(polyRoundStartAt(at, 60), 1794157200);
      expect(polyCryptoRoundSlug('BTC', 60, 1794157200),
          'bitcoin-up-or-down-november-8-2026-12pm-et');
      expect(polyCryptoRoundSlug('ETH', 60, 1794157200),
          'ethereum-up-or-down-november-8-2026-12pm-et');
      expect(polyCryptoRoundSlug('XRP', 60, 1794157200 + 3600),
          'xrp-up-or-down-november-8-2026-1pm-et');
      // Daylight time: 25 October 2026, `bitcoin-up-or-down-october-25-
      // 2026-1pm-et` ended 18:00Z, so 17:00Z was 1 PM EDT.
      expect(polyCryptoRoundSlug('BTC', 60, epoch(DateTime.utc(2026, 10, 25, 17))),
          'bitcoin-up-or-down-october-25-2026-1pm-et');
      // The night the clocks went back (1 November 2026, 2 AM EDT = 06:00Z):
      // the app writes the hour as the clock then read it; Gamma listed no
      // `…-november-1-2026-12am-et` or `-1am-et` at all, `-2am-et` (ending
      // 08:00Z) and `-3am-et` on, and no four-hour round between 00:00Z
      // (`…-4h-1793491200`, "October 31, 8:00PM-12:00AM ET") and 09:00Z
      // (`…-4h-1793523600`, "November 1, 4:00AM-8:00AM ET"). A card then
      // has no event and says so.
      expect(polyCryptoRoundSlug('BTC', 60, epoch(DateTime.utc(2026, 11, 1, 7))),
          'bitcoin-up-or-down-november-1-2026-2am-et');
      expect(polyCryptoRoundSlug('BTC', 60, epoch(DateTime.utc(2026, 11, 1, 3))),
          'bitcoin-up-or-down-october-31-2026-11pm-et');
      expect(polyRoundStartAt(DateTime.utc(2026, 11, 1, 9, 30), 240),
          1793523600);
      expect(polyRoundStartAt(DateTime.utc(2026, 11, 1, 2, 30), 240),
          1793491200);
    });

    test('the model writes the same windows, back by whole windows', () {
      final now = DateTime.now();
      for (final minutes in [5, 15, 60, 240]) {
        final start = polyRoundStartAt(now, minutes);
        expect(PolymarketModel.cryptoWindowSlug('btc', minutes),
            polyCryptoRoundSlug('btc', minutes, start),
            reason: '$minutes');
        expect(PolymarketModel.cryptoWindowSlug('btc', minutes, windowsBack: 1),
            polyCryptoRoundSlug('btc', minutes, start - minutes * 60),
            reason: '$minutes back one');
      }
    });
  });
}
