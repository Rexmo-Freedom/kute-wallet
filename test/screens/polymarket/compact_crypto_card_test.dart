// The Predictions list's BTC up-or-down card is compact (founder, 1
// November 2026: the full card stood ~600 px over the list): one header
// row (logo, "BTC up or down · 5m", past rounds as dots, the countdown
// pill), the price row (price, its move against the target, the target),
// a 54 px sparkline (no in-chart "Target" badge: the target is printed
// above it) and the Up / Down pills (44) with their odds, about 200 px in
// all (founder, 2 November 2026: bigger still), and under the sparkline the
// strip of rounds that picks which one the buttons bet on (the past rounds
// as dots move into it; founder on build 2.2.0 (101): "we also don't have
// the 'next' tab"), about 250 px with it. The buttons keep their
// squared ~14 px corners (not full pills) and wear the market page's solid
// Yes / No fill (founder, 2 November 2026: "put them back at the darker
// colours"): the market colour with its faint top highlight, white text
// (the side then its chance, no arrow) and, in light mode, the same quiet
// glow. A tap opens the slip on that side. The market page keeps the full
// card.
// Partway through a window the buttons roll to the next one:
// crypto_next_round_card_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/crypto_live_odds_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_provider.dart';
import 'package:kute/screens/polymarket/polymarket_screen.dart';
import 'package:kute/screens/shared/market_pair_button.dart';
import 'package:kute/services/polymarket/crypto_window_results.dart';
import 'package:kute/services/polymarket/current_round.dart';
import 'package:kute/theme/app_theme.dart';

final _start = DateTime.utc(2026, 11, 1, 12, 0);

class _Round extends CryptoPredictNotifier {
  @override
  Future<CryptoPredictState> build(String arg) async => CryptoPredictState(
        asset: arg,
        currentPrice: 77812.4,
        priceToBeat: 77775,
        secondsRemaining: 154,
        priceHistory: [
          for (var i = 0; i < 30; i++)
            BtcPriceSnapshot(
                timestamp: _start.add(Duration(seconds: i * 5)),
                price: 77775 + (i % 7) * 6.0 - 12 + i),
        ],
        event: Btc5MinEvent(
          slug: 'btc-updown-5m-${_start.millisecondsSinceEpoch ~/ 1000}',
          title: 'Bitcoin Up or Down',
          windowStartTime: _start,
          endDate: _start.add(const Duration(minutes: 5)),
          upPrice: 0.62,
          downPrice: 0.38,
          upTokenId: 'up',
          downTokenId: 'down',
        ),
      );
}

List<Override> compactCardOverrides() => [
      cryptoPredictProvider.overrideWith(_Round.new),
      cryptoRecentResultsProvider.overrideWith((ref, key) async => const [
            CryptoWindowResult(1, true),
            CryptoWindowResult(2, false),
            CryptoWindowResult(3, true),
            CryptoWindowResult(4, null),
          ]),
      cryptoOddsClockProvider.overrideWithValue(
          () => _start.add(const Duration(seconds: 146))),
      polyRoundWindowReaderProvider
          .overrideWithValue((asset, start, minutes) async => null),
      polymarketActivePositionsProvider.overrideWithValue(const []),
    ];

Widget compactCardApp({bool dark = false}) => ProviderScope(
      overrides: compactCardOverrides(),
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          theme: ThemeData(
              brightness: dark ? Brightness.dark : Brightness.light,
              fontFamily: 'Inter',
              extensions: [
                dark ? AppColorsExtension.dark() : AppColorsExtension.light()
              ]),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.topCenter,
                child: CryptoPredictBanner(
                  config: kCryptoPredictAssets.first,
                  compact: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  // Inter, as on a phone: the price row and the strip of rounds lay
  // themselves out by the width of their words (the target goes under the
  // price, the dots leave the strip, only where they would not fit).
  setUpAll(() async {
    final inter = FontLoader('Inter');
    for (final f in ['Regular', 'SemiBold', 'Bold']) {
      inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
    }
    await inter.load();
  });
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('compact: about 200 px, every piece of the round on it',
      (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(compactCardApp());
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final card = find.byKey(const ValueKey('crypto-round-compact'));
    expect(card, findsOneWidget);
    final h = tester.getSize(card).height;
    expect(h, inInclusiveRange(235, 265));
    expect(find.byKey(const ValueKey('crypto-round-strip')), findsOneWidget);
    expect(find.text('BTC up or down · 5m'), findsOneWidget);
    expect(find.byKey(const ValueKey('crypto-round-countdown')), findsOneWidget);
    expect(find.text('02:34'), findsOneWidget);
    expect(find.byKey(const ValueKey('crypto-round-past-dots')), findsOneWidget);
    expect(find.text(r'Target $77,775'), findsOneWidget);
    expect(find.textContaining('▲'), findsOneWidget);
    final up = find.byKey(const ValueKey('crypto-round-up'));
    final down = find.byKey(const ValueKey('crypto-round-down'));
    expect(tester.getSize(up).height, 44);
    expect(tester.getSize(down).height, 44);
    expect(find.descendant(of: up, matching: find.text('Up')), findsOneWidget);
    expect(
        find.descendant(of: down, matching: find.text('Down')), findsOneWidget);
    // Solid buttons: the market page's Yes / No fill and glow exactly,
    // white text, no arrows.
    for (final (pill, color) in [
      (up, AppColors.marketUp),
      (down, AppColors.marketDown),
    ]) {
      final box = tester.widget<Container>(find
          .descendant(of: pill, matching: find.byType(Container))
          .first);
      final deco = box.decoration! as BoxDecoration;
      final page = marketPairDecoration(color, glow: true);
      expect(deco.color, color);
      expect(deco.gradient, page.gradient);
      expect(deco.boxShadow, page.boxShadow);
      // The more squared buttons: a rounded rectangle (~14 px corners),
      // not a full pill.
      final radius = (deco.borderRadius! as BorderRadius).topLeft.x;
      expect(radius, inInclusiveRange(12, 16));
      expect(radius, lessThan(tester.getSize(pill).height / 2));
      // Every glyph on it, the side and the rolling chance, is white.
      final glyphs = find.descendant(of: pill, matching: find.byType(RichText));
      expect(glyphs, findsWidgets);
      for (final g in tester.widgetList<RichText>(glyphs)) {
        expect(g.text.style?.color, Colors.white);
      }
      expect(find.descendant(of: pill, matching: find.textContaining('%')),
          findsWidgets);
      // Side then chance, on one line.
      expect(
          tester.getCenter(find.descendant(
                  of: pill, matching: find.text(pill == up ? 'Up' : 'Down'))).dy,
          closeTo(tester.getCenter(pill).dy, 1));
    }
    expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing);
    expect(find.byIcon(Icons.arrow_downward_rounded), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 31));
  });

  testWidgets('dark: the same solid buttons, no glow', (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(compactCardApp(dark: true));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    for (final (key, color) in [
      ('crypto-round-up', AppColors.marketUp),
      ('crypto-round-down', AppColors.marketDown),
    ]) {
      final pill = find.byKey(ValueKey(key));
      expect(tester.getSize(pill).height, 44);
      final deco = tester
          .widget<Container>(
              find.descendant(of: pill, matching: find.byType(Container)).first)
          .decoration! as BoxDecoration;
      expect(deco.color, color);
      expect(deco.gradient, marketPairDecoration(color).gradient);
      expect(deco.boxShadow, isNull);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 31));
  });
}
