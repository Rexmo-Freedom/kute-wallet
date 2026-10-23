// Render harness for the top of the Portfolio: the balance row (Dollars,
// Investing, Predictions) with Rebalance under it, the statistics row
// (open P&L, amount at stake, open positions) and the same figures inside
// a Ledger's Statistics card, at 390 x 844, light and dark, at text scale
// 1.0 and 1.3, in the app's real themes and Inter. Writes PNGs.
//
// Inter is registered under the theme's family names only, never as the
// test font, so a widget that measures text without the theme's family
// (and so in another font) shows it here as it would on a device.
//
// Not part of the normal suite; it only runs when asked:
//
//   fvm flutter test test/audit/portfolio_tiles_render_test.dart \
//     --dart-define=PORTFOLIO_TILES_OUT=/tmp/portfolio-tiles

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/generated/app_localizations.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/one_balance_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/providers/venue_sweeper_provider.dart';
import 'package:kute/screens/portfolio/portfolio_balance_breakdown.dart';
import 'package:kute/screens/portfolio/portfolio_figure_tiles.dart';
import 'package:kute/services/one_balance/one_balance_state.dart';
import 'package:kute/theme/app_theme.dart';

import 'package:polybrainz_polymarket/polybrainz_polymarket.dart' show Order;

import '../helpers/portfolio_overrides.dart';

const _out = String.fromEnvironment('PORTFOLIO_TILES_OUT');
const _key = ValueKey('shot');
const _dpr = 3.0;
const _size = Size(390, 844);

class _Sweeper extends VenueSweeperNotifier {
  static VenueSweeperState initial = const VenueSweeperState(
      movable: {OneBalanceVenue.predictions: 2.77},
      held: {OneBalanceVenue.predictions: 2.77});

  @override
  VenueSweeperState build() => initial;

  @override
  Future<void> preview() async {}

  @override
  Future<void> trigger(String reason, {OneBalanceVenue? venue}) async {}
}

/// Long amounts, and a venue with a note: the widest the row gets.
const _long = OneBalanceState(
  dollarsUsd: 123456.78,
  investedUsd: 1111111.11,
  investedByVenue: {
    OneBalanceVenue.investing: 987654.32,
    OneBalanceVenue.predictions: 123456.79,
  },
  investingKnown: true,
  predictionsKnown: true,
  venueCash: {OneBalanceVenue.investing: 45678.9},
  waiting: {OneBalanceVenue.predictions: 0.5},
);

/// Predictions with a resting BUY reserving 10 x 0.40 = \$4.00.
class _PolyOrders extends PolymarketTradingNotifier {
  @override
  Future<PolymarketTradingState> build() async => PolymarketTradingState(
          isAuthenticated: true,
          usdcBalance: 10,
          openOrders: [
            Order(
                id: 'o',
                market: 'm',
                assetId: 'a',
                owner: 'k',
                side: 'BUY',
                price: '0.40',
                originalSize: '10',
                sizeMatched: '0',
                outcome: 'Yes'),
          ]);

  @override
  Future<void> refresh() async {}
}

const _state = OneBalanceState(
  dollarsUsd: 42.5,
  investedUsd: 605,
  investedByVenue: {
    OneBalanceVenue.investing: 600,
    OneBalanceVenue.predictions: 5,
  },
  investingKnown: true,
  predictionsKnown: true,
  venueCash: {
    OneBalanceVenue.investing: 6.54,
    OneBalanceVenue.predictions: 2.77,
  },
);

Widget _stats(BuildContext context, {bool boxed = true}) => PortfolioTileRow(
      boxed: boxed,
      children: [
        for (final (label, figure, color) in [
          ('Open P&L', r'+$12.50', AppColors.marketUp),
          ('Amount at stake', r'$605.00', context.colors.textPrimary),
          ('Open positions', '4', context.colors.textPrimary),
        ])
          PortfolioTile(children: [
            PortfolioTileStat(
                label: label,
                figure: PortfolioTileFigure(figure, color: color)),
          ]),
      ],
    );

Future<ui.Image> _shoot(WidgetTester tester, bool dark,
    {OneBalanceState state = _state, bool orders = false}) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(ProviderScope(
    overrides: [
      ...portfolioOverrides(),
      settingsProvider.overrideWith((_) => SettingsModel(Settings(
          currency: 'USD',
          language: 'en',
          btcFormat: 'sats',
          backup: false,
          biometricsEnabled: false,
          bitcoinElectrumNode: '',
          nodeType: '',
          reviewDone: true))),
      oneBalanceProvider.overrideWith((ref) => state),
      venueSweeperProvider.overrideWith(_Sweeper.new),
      if (orders) polymarketTradingProvider.overrideWith(_PolyOrders.new),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dark ? buildDarkTheme() : buildLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RepaintBoundary(
          key: _key,
          child: Builder(
            builder: (context) => Scaffold(
              backgroundColor: context.colors.background,
              body: SafeArea(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 16.h),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const PortfolioBalanceBreakdown(
                          trading: true, predictions: true),
                      SizedBox(height: 24.h),
                      _stats(context),
                      SizedBox(height: 24.h),
                      // A Ledger's Statistics: the row inside its card.
                      DecoratedBox(
                        decoration: AppDecorations.card(context),
                        child: Padding(
                          padding: EdgeInsets.all(16.w),
                          child: _stats(context, boxed: false),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  ));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  for (final key in ['portfolio-balance-row', 'portfolio-balance-dollars']) {
    final f = find.byKey(ValueKey(key));
    if (f.evaluate().isNotEmpty) {
      debugPrint('$key: ${tester.getSize(f)}');
    }
  }
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_key));
  return (await tester.runAsync(() => boundary.toImage(pixelRatio: _dpr)))!;
}

Future<void> _png(WidgetTester tester, ui.Image image, String name) =>
    tester.runAsync(() async {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$_out/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    });

void main() {
  if (_out.isEmpty) {
    test('portfolio tiles render', () {},
        skip: 'on demand: --dart-define=PORTFOLIO_TILES_OUT=<dir>');
    return;
  }

  setUpAll(() async {
    Directory(_out).createSync(recursive: true);
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final family in [GoogleFonts.inter().fontFamily!, 'Inter']) {
      final inter = FontLoader(family);
      for (final f in ['Regular', 'SemiBold', 'Bold']) {
        inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
      }
      await inter.load();
    }
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets('Portfolio top at text scale $scale, light and dark',
        (tester) async {
      tester.view.devicePixelRatio = _dpr;
      tester.view.physicalSize = _size * _dpr;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      for (final dark in [false, true]) {
        final img = await _shoot(tester, dark);
        await _png(tester, img,
            'portfolio_tiles_${dark ? 'dark' : 'light'}_${scale == 1 ? '1.0' : '1.3'}');
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('long amounts and a note at 375 pt, text scale 1.3',
      (tester) async {
    tester.view.devicePixelRatio = _dpr;
    tester.view.physicalSize = const Size(375, 812) * _dpr;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    _Sweeper.initial = const VenueSweeperState(
        belowMinimum: {OneBalanceVenue.predictions: 0.5});
    addTearDown(() => _Sweeper.initial = const VenueSweeperState());
    for (final dark in [false, true]) {
      final img = await _shoot(tester, dark, state: _long, orders: true);
      await _png(
          tester, img, 'portfolio_tiles_long_${dark ? 'dark' : 'light'}');
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
