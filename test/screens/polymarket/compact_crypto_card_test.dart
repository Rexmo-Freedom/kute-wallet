// The Predictions list's BTC up-or-down card is compact (founder, 1
// November 2026: the full card stood ~600 px over the list): one header
// row (logo, "BTC up or down · 5m", past rounds as dots, the countdown
// pill), the price row (price, its move against the target, the target),
// a 54 px sparkline (no in-chart "Target" badge: the target is printed
// above it) and the Up / Down pills (44) with their odds, about 200 px in
// all (founder, 2 November 2026: bigger still). The buttons are soft
// tinted fills in the market colour with squared ~14 px corners (not full
// pills), coloured text, the side then its chance, no arrow; a tap opens the slip on that side. The market
// page keeps the full card.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/polymarket_provider.dart';
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
    expect(h, inInclusiveRange(185, 215));
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
    // Soft tinted pills: the market colour at 12% behind coloured text,
    // no arrows.
    for (final (pill, color) in [
      (up, AppColors.marketUp),
      (down, AppColors.marketDown),
    ]) {
      final box = tester.widget<Container>(find
          .descendant(of: pill, matching: find.byType(Container))
          .first);
      final deco = box.decoration! as BoxDecoration;
      expect(deco.color, color.withValues(alpha: 0.12));
      // The more squared buttons: a rounded rectangle (~14 px corners),
      // not a full pill.
      final radius = (deco.borderRadius! as BorderRadius).topLeft.x;
      expect(radius, inInclusiveRange(12, 16));
      expect(radius, lessThan(tester.getSize(pill).height / 2));
      final label = tester.widget<Text>(find
          .descendant(of: pill, matching: find.text(pill == up ? 'Up' : 'Down')));
      expect(label.style!.color, color);
    }
    expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing);
    expect(find.byIcon(Icons.arrow_downward_rounded), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 31));
  });
}
