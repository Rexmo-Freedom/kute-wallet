// The Predictions list's BTC up-or-down card is compact and calm (founder,
// 1 November 2026: the full card stood ~600 px over the list, then less
// clutter): one header row (logo, "BTC up or down · 5m", the countdown as
// quiet text), the price with one word of state ("above target" in
// green), and the Up / Down soft pills with their odds. No chart, no
// target line or price, no past rounds. The market page keeps the full
// card.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_provider.dart';
import 'package:kute/screens/home/components/btc_predict_chart.dart';
import 'package:kute/screens/polymarket/polymarket_screen.dart';
import 'package:kute/services/polymarket/crypto_window_results.dart';
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
    ];

Widget compactCardApp({bool dark = false}) => ProviderScope(
      overrides: compactCardOverrides(),
      child: ScreenUtilInit(
        designSize: const Size(430, 932),
        builder: (_, __) => MaterialApp(
          theme: ThemeData(
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
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('compact: about 145 px, the round in three lines, no chart',
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
    expect(h, inInclusiveRange(120, 170));
    expect(find.text('BTC up or down · 5m'), findsOneWidget);
    // The countdown: quiet text with a dot, no pill.
    final countdown = find.byKey(const ValueKey('crypto-round-countdown'));
    expect(countdown, findsOneWidget);
    expect(find.text('● 02:34', findRichText: true), findsOneWidget);
    final c = AppColorsExtension.light();
    expect(tester.widget<Text>(countdown).style?.color, c.textSecondary);
    // The price's state in a word, in its colour; no delta, no target.
    final state = find.byKey(const ValueKey('crypto-round-state'));
    expect(tester.widget<Text>(state).data, 'above target');
    expect(tester.widget<Text>(state).style?.color, AppColors.marketUp);
    expect(find.textContaining('Target'), findsNothing);
    expect(find.textContaining('▲'), findsNothing);
    // No chart, no target line, no past rounds.
    expect(find.byType(BtcPredictChart), findsNothing);
    expect(find.byKey(const ValueKey('crypto-round-past-dots')), findsNothing);
    // Up and Down: soft pills, the side's colour at 12% behind its text.
    final up = find.byKey(const ValueKey('crypto-round-up'));
    final down = find.byKey(const ValueKey('crypto-round-down'));
    expect(tester.getSize(up).height, 40);
    expect(tester.getSize(down).height, 40);
    final upText =
        find.descendant(of: up, matching: find.text('Up'));
    expect(upText, findsOneWidget);
    expect(tester.widget<Text>(upText).style?.color, AppColors.marketUp);
    expect(
        find.descendant(of: down, matching: find.text('Down')), findsOneWidget);
    BoxDecoration fill(Finder pill) => tester
        .widget<Container>(
            find.descendant(of: pill, matching: find.byType(Container)).first)
        .decoration! as BoxDecoration;
    expect(fill(up).color, AppColors.marketUp.withValues(alpha: 0.12));
    expect(fill(down).color, AppColors.marketDown.withValues(alpha: 0.12));
    expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 31));
  });
}
