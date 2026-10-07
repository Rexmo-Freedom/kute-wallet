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

    testWidgets('the card: leader first, sides adding to 100, time in footer',
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
      // The footer is the round's time, not a date.
      expect(find.textContaining(RegExp(r'^10:15\sPM – 10:30\sPM$')),
          findsOneWidget);
    });
  });
}
