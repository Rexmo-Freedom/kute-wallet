// A look by eye at the Dollars header with open positions (fw193; founder,
// 13 November 2026: the balance opens the Portfolio and carries the open
// positions' P&L), light and dark, on a 390-wide phone and on a 320-wide
// one at 1.5x text, written only when asked: DOLLARS_HEADER_RENDER=<dir>.
//   DOLLARS_HEADER_RENDER=<dir> flutter test \
//     test/render/dollars_balance_header_render_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/models/hyperliquid_market.dart' show HlPerpPosition;
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/screens/shared/kute_pill_tabs.dart';
import 'package:kute/screens/shared/open_once.dart';
import 'package:kute/screens/usd/usd_account_screen.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/theme/app_theme.dart';

import '../helpers/portfolio_overrides.dart' show PortfolioTestTrading;
import '../screens/usd/investments_harness.dart';

final _dir = Platform.environment['DOLLARS_HEADER_RENDER'];

class _NoLive extends LivePriceNotifier {
  @override
  LivePriceState build() => const LivePriceState(live: false, prices: {});
  @override
  void acquire() {}
  @override
  void release() {}
  @override
  void pause() {}
  @override
  void resume() {}
}

Future<void> _fonts(WidgetTester tester) => tester.runAsync(() async {
      for (final family in [GoogleFonts.inter().fontFamily!, 'Inter']) {
        final inter = FontLoader(family);
        for (final f in ['Regular', 'SemiBold', 'Bold']) {
          inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
        }
        await inter.load();
      }
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    });

/// The top of the screen, down to the pills, as a PNG.
Future<void> _shoot(WidgetTester tester, String name) async {
  final pills = tester.getRect(find.byType(KutePillTabs).first);
  await tester.runAsync(() async {
    final view = tester.binding.renderViews.first;
    final layer = view.debugLayer! as OffsetLayer;
    final image = await layer.toImage(
        Rect.fromLTWH(0, 0, view.size.width, pills.bottom + 16),
        pixelRatio: 3);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_dir!).createSync(recursive: true);
    File('$_dir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    OpenOnce.reset();
  });

  for (final (label, size, scale) in [
    ('390', const Size(390, 844), 1.0),
    ('320x1.5', const Size(320, 900), 1.5),
  ]) {
    for (final dark in [false, true]) {
      for (final up in [true, false]) {
        final mode = dark ? 'dark' : 'light';
        final dir = up ? 'up' : 'down';
        testWidgets('render: $label $mode $dir', skip: _dir == null,
            (tester) async {
          await _fonts(tester);
          await pumpInvestments(tester,
              size: size,
              dark: dark,
              textScale: scale,
              // The app's own theme and the Material the shell gives the
              // page.
              child: Theme(
                data: (dark ? buildDarkTheme() : buildLightTheme()).copyWith(
                    textTheme: (dark ? buildDarkTheme() : buildLightTheme())
                        .textTheme
                        .apply(fontFamily: 'Inter')),
                child: const Scaffold(body: UsdAccountScreen()),
              ),
              balance: const OneBalanceState(
                  dollarsUsd: 5.93,
                  investedUsd: 20.97,
                  investingKnown: true,
                  predictionsKnown: true),
              overrides: [
                livePriceProvider.overrideWith(_NoLive.new),
                polymarketActivePositionsProvider.overrideWith((_) => [
                      PolymarketPosition(
                          marketId: 'c-fed',
                          marketQuestion: 'Fed decision in December?',
                          outcome: 'Yes',
                          size: 20,
                          avgPrice: 0.42,
                          currentPrice: up ? 0.47 : 0.36,
                          pnl: 0,
                          pnlPercent: 0,
                          isResolved: false,
                          tokenId: 'tok-fed'),
                    ]),
                hyperliquidTradingProvider.overrideWith(() =>
                    PortfolioTestTrading(HyperliquidTradingState(
                        isInitialized: true,
                        positions: [
                          HlPerpPosition(
                              coin: 'BTC',
                              szi: 0.001,
                              entryPx: 100000,
                              positionValue: up ? 100.25 : 99.6,
                              unrealizedPnl: up ? 0.25 : -0.4,
                              returnOnEquity: 0,
                              liquidationPx: null,
                              marginUsed: 12.57,
                              leverageType: 'cross',
                              leverageValue: 8,
                              maxLeverage: 40),
                        ]))),
              ]);
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(tester.takeException(), isNull);
          await _shoot(tester, 'dollars_header_${label}_${mode}_$dir');
          await unmountInvestments(tester);
        });
      }
    }
  }
}
