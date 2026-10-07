// Chance bar render harness: draws the Predictions open-position screen
// (position_detail_sheet.dart) with its chance bar for a few made-up
// positions, in light and dark, and writes each as a PNG. Nothing reads
// the network.
//
// Not part of the normal suite; it only runs when asked:
//
//   fvm flutter test test/audit/position_chance_bar_render_test.dart \
//     --dart-define=CHANCE_BAR_RENDER=true \
//     --dart-define=CHANCE_BAR_RENDER_OUT=/tmp/kute_chance_bar
//
// The cases: a 5-minute round held on Down at 7.5% bought at 54¢, a Yes at
// 62% bought at 40¢, a game's team at 64% bought at 42¢, and a won Yes.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/providers/advisor_provider.dart' show aiEnabledProvider;
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_cost_basis_provider.dart';
import 'package:kute/providers/polymarket_game_timeline_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_sats_pnl_provider.dart'
    show predictionUsdCostProvider;
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/screens/polymarket/components/position_detail_sheet.dart';
import 'package:kute/theme/app_theme.dart';

const _enabled = bool.fromEnvironment('CHANCE_BAR_RENDER');
const _outDefine = String.fromEnvironment('CHANCE_BAR_RENDER_OUT');

final String _out = _outDefine.isNotEmpty
    ? _outDefine
    : '${Directory.systemTemp.path}/kute_chance_bar';

const _phone = Size(393, 852);
const _shotKey = ValueKey('chance-bar-render-shot');

class _NoGames extends SportsLiveNotifier {
  @override
  Map<String, SportsMatchUpdate> build() => const {};
  @override
  void connect() {}
}

class _NoTimeline extends PolyGameTimelineNotifier {
  @override
  PolyGameTimeline build(String arg) => PolyGameTimeline.empty;
}

class _Prices extends LivePriceNotifier {
  @override
  LivePriceState build() => const LivePriceState();
}

/// No account: the Claim button reads an empty trading state.
class _NoTrading extends PolymarketTradingNotifier {
  @override
  Future<PolymarketTradingState> build() async =>
      const PolymarketTradingState();
}

class _NoCostBasis extends StateNotifier<Map<String, double>>
    implements PolymarketCostBasisNotifier {
  _NoCostBasis() : super(const {});
  @override
  Future<void> addCost(String tokenId, double paidUsdc) async {}
  @override
  Future<void> reset(String tokenId) async {}
  @override
  Future<void> scaleByRemaining(
      String tokenId, double fractionRemaining) async {}
  @override
  double? costFor(String tokenId) => null;
}

const _home =
    PolymarketTeam(name: 'Broncos', abbreviation: 'den', ordering: 'home');
const _away =
    PolymarketTeam(name: '49ers', abbreviation: 'sf', ordering: 'away');

final _game = PolymarketEvent(
  id: 'e1',
  slug: 'nfl-sf-den',
  title: '49ers vs. Broncos',
  volume: 1000,
  liquidity: 1000,
  category: 'sports',
  conditionId: 'c1',
  outcomes: const [
    PolymarketOutcome(name: '49ers', price: 0.64, tokenId: 'sf'),
    PolymarketOutcome(name: 'Broncos', price: 0.36, tokenId: 'den'),
  ],
  gameId: 77,
  teams: const [_home, _away],
);

Future<void> _show(WidgetTester tester, PolymarketPosition position,
    {required bool dark, PolymarketEvent? event}) async {
  tester.view.physicalSize = _phone * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const SizedBox.shrink());
  final slug = position.eventSlug;
  await tester.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: [
      polymarketClaimablePositionsProvider.overrideWithValue(const []),
      polymarketActivePositionsProvider.overrideWithValue(const []),
      livePriceProvider.overrideWith(_Prices.new),
      sportsLiveProvider.overrideWith(_NoGames.new),
      polyGameTimelineProvider.overrideWith(_NoTimeline.new),
      aiEnabledProvider.overrideWith((ref) async => true),
      polymarketCostBasisProvider.overrideWith((ref) => _NoCostBasis()),
      predictionUsdCostProvider.overrideWith((ref, id) async => null),
      polymarketTradingProvider.overrideWith(_NoTrading.new),
      if (slug != null)
        polymarketEventDetailsProvider(slug).overrideWith((ref) async => event),
    ],
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dark ? buildDarkTheme() : buildLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RepaintBoundary(
          key: _shotKey,
          child: PositionDetailSheet(position: position),
        ),
      ),
    ),
  ));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _shot(WidgetTester tester, String name) async {
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_shotKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_out/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  });
  // ignore: avoid_print
  print('RENDER wrote $name.png');
}

void main() {
  if (!_enabled) {
    test('chance bar render', () {},
        skip: 'on demand: --dart-define=CHANCE_BAR_RENDER=true');
    return;
  }

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    Directory(_out).createSync(recursive: true);
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final family in [
      GoogleFonts.inter().fontFamily!,
      'Inter',
      'FlutterTest'
    ]) {
      final inter = FontLoader(family);
      for (final f in ['Regular', 'SemiBold', 'Bold']) {
        inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
      }
      await inter.load();
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => '$_out/cache');
    final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json'))
        as List<dynamic>;
    for (final entry in manifest.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final font
          in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
  });

  // A 5-minute round that ends in 1:50.
  final roundStart = DateTime.now()
          .subtract(const Duration(minutes: 3, seconds: 10))
          .millisecondsSinceEpoch ~/
      1000;

  final cases = <(String, PolymarketPosition, PolymarketEvent?)>[
    (
      'down_7.5_bought_54',
      PolymarketPosition(
        marketId: 'c-round',
        marketQuestion: 'Bitcoin Up or Down - 5 minutes',
        outcome: 'Down',
        size: 4.58,
        avgPrice: 0.54,
        currentPrice: 0.075,
        pnl: -2.13,
        pnlPercent: -86.1,
        isResolved: false,
        tokenId: 'down',
        eventSlug: 'btc-updown-5m-$roundStart',
        endDateStr: DateTime.fromMillisecondsSinceEpoch(
                (roundStart + 300) * 1000,
                isUtc: true)
            .toIso8601String(),
      ),
      null,
    ),
    (
      'yes_62_bought_40',
      PolymarketPosition(
        marketId: 'c-fed',
        marketQuestion: 'Will the Fed cut rates in December?',
        outcome: 'Yes',
        size: 25,
        avgPrice: 0.40,
        currentPrice: 0.62,
        pnl: 5.5,
        pnlPercent: 55,
        isResolved: false,
        tokenId: 'fed-yes',
        eventSlug: 'fed-december',
        endDateStr: DateTime.now()
            .add(const Duration(days: 60))
            .toUtc()
            .toIso8601String(),
      ),
      null,
    ),
    (
      'game_49ers_64_bought_42',
      const PolymarketPosition(
        marketId: 'c1',
        marketQuestion: '49ers vs. Broncos',
        outcome: '49ers',
        size: 120,
        avgPrice: 0.42,
        currentPrice: 0.64,
        pnl: 26.4,
        pnlPercent: 52.4,
        isResolved: false,
        tokenId: 'sf',
        eventSlug: 'nfl-sf-den',
      ),
      _game,
    ),
    (
      'won_yes_bought_40',
      const PolymarketPosition(
        marketId: 'c-won',
        marketQuestion: 'Will Bitcoin close above \$100k on Friday?',
        outcome: 'Yes',
        size: 25,
        avgPrice: 0.40,
        currentPrice: 1,
        pnl: 15,
        pnlPercent: 150,
        isResolved: true,
        won: true,
        tokenId: 'won-yes',
      ),
      null,
    ),
  ];

  for (final (name, position, event) in cases) {
    for (final dark in [false, true]) {
      final id = '${name}_${dark ? 'dark' : 'light'}';
      testWidgets(id, (tester) async {
        await _show(tester, position, dark: dark, event: event);
        await _shot(tester, id);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 8));
      });
    }
  }
}
