// Chart audit: draws the app's real chart screens from live market data
// and writes each as a PNG, so the charts can be looked at without a
// phone. Not part of the normal suite: it reads the public Polymarket and
// Hyperliquid APIs and the Kute backend's feed and game timelines, so it
// only runs when asked:
//
//   flutter test test/audit/chart_audit_test.dart \
//     --dart-define=CHART_AUDIT=true \
//     --dart-define=CHART_AUDIT_OUT=/tmp/kute_chart_audit
//
// Add --dart-define=CHART_AUDIT_ONLY="04 " to draw the cases whose name
// contains that text (the number and a space picks one case).
//
// What it writes under the output folder, and nothing into the repository:
//   *.png          one image per case, range and theme
//   cases.log      which markets each case picked today
//   problems.log   layout overflows, thrown builds, cases with no example
//   requests.log   every request the app's own code made
//   fixtures/      each answer, one JSON file per request; an identical
//                  request within fifteen minutes is answered from there
//
// How it works: the real screens are pumped under the app's themes with
// the app's fonts, and the app's own providers and models read the
// network through one recorded HTTP client. Only the sockets (live
// prices, live scores, candles) and the account are replaced: a chart
// shows what its REST reads give it, and a position, where one is drawn,
// is made up around the market's real price and says so in its case.
//
// What it cannot show: network images (logos, crests, portraits), live
// socket ticks, animation, and how a real device rasterises. Text a
// widget measures itself with no font family (the rolling digits on the
// buy buttons and headline prices) is spaced for the test binding's block
// font, so those digits sit too far apart here and not on a phone.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart' show sha1;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:kute/l10n/l10n.dart';
import 'package:kute/models/hyperliquid_market.dart';
import 'package:kute/providers/chart_drawings_provider.dart';
import 'package:kute/providers/hyperliquid_account_provider.dart';
import 'package:kute/providers/hyperliquid_insights_provider.dart';
import 'package:kute/providers/hyperliquid_live_prices_provider.dart';
import 'package:kute/providers/hyperliquid_markets_provider.dart';
import 'package:kute/providers/hyperliquid_sats_pnl_provider.dart';
import 'package:kute/providers/hyperliquid_trading_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_chart_intervals.dart';
import 'package:kute/screens/hyperliquid/components/hl_charts.dart';
import 'package:kute/screens/hyperliquid/components/hl_position_detail_sheet.dart';
import 'package:kute/screens/hyperliquid/market_detail_sheet.dart';
import 'package:kute/services/hyperliquid/hyperliquid_websocket.dart';
import 'package:kute/services/hyperliquid/insights/hl_flow_signals.dart';
import 'package:kute/models/polymarket_model.dart';
import 'package:kute/models/settings_model.dart';
import 'package:kute/providers/polymarket_trading_provider.dart';
import 'package:kute/providers/portfolio_performance_provider.dart';
import 'package:kute/providers/settings_provider.dart';
import 'package:kute/screens/hyperliquid/components/hl_market_card.dart';
import 'package:kute/screens/portfolio/portfolio_statistics.dart';
import 'package:kute/services/portfolio/portfolio_performance_service.dart';

import 'package:kute/providers/advisor_provider.dart' show aiEnabledProvider;
import 'package:kute/providers/polymarket_browse_provider.dart';
import 'package:kute/providers/polymarket_live_prices_provider.dart';
import 'package:kute/providers/polymarket_sports_provider.dart';
import 'package:kute/screens/polymarket/components/live_game.dart';
import 'package:kute/screens/polymarket/components/market_card.dart';
import 'package:kute/screens/polymarket/components/market_chart.dart';
import 'package:kute/screens/polymarket/components/position_detail_sheet.dart';
import 'package:kute/screens/polymarket/market_detail_sheet.dart';
import 'package:kute/screens/shared/kute_skeleton.dart';
import 'package:kute/theme/app_theme.dart';

const _enabled = bool.fromEnvironment('CHART_AUDIT');
const _outDefine = String.fromEnvironment('CHART_AUDIT_OUT');

/// Only the cases whose name contains this are drawn (all when empty).
const _only = String.fromEnvironment('CHART_AUDIT_ONLY');
const _backend = String.fromEnvironment('CHART_AUDIT_BACKEND',
    defaultValue: 'https://backend.kutewallet.com');

final String _out = _outDefine.isNotEmpty
    ? _outDefine
    : '${Directory.systemTemp.path}/kute_chart_audit';

// ───────────────────────────── recorded HTTP ─────────────────────────────

class _RealHttp extends HttpOverrides {}

/// Answers a request from `<out>/fixtures` when the same one was made
/// before, else from the network (and keeps the answer).
class _Recorder extends http.BaseClient {
  _Recorder(this.dir)
      : _real = HttpOverrides.runWithHttpOverrides(
            () => IOClient(HttpClient()
              ..connectionTimeout = const Duration(seconds: 15)),
            _RealHttp());

  final Directory dir;
  final http.Client _real;
  int inFlight = 0;
  final List<String> log = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = request is http.Request ? request.body : '';
    final id = '${request.method} ${request.url} $body';
    final file = File(
        '${dir.path}/${request.url.host}_${sha1.convert(utf8.encode(id))}.json');
    int status;
    String text;
    if (file.existsSync()) {
      final saved = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      status = saved['status'] as int;
      text = saved['body'] as String;
    } else {
      inFlight++;
      try {
        // On the real event loop, whatever zone asked. Errors are turned
        // into a value there: a future's error does not cross zones.
        final answer = await Zone.root.run(() async {
          Object? last;
          for (var attempt = 0; attempt < 3; attempt++) {
            try {
              final copy = http.Request(request.method, request.url)
                ..headers.addAll(request.headers);
              if (request is http.Request) copy.bodyBytes = request.bodyBytes;
              final r = await http.Response.fromStream(await _real
                  .send(copy)
                  .timeout(const Duration(seconds: 25)));
              return (
                r.statusCode,
                utf8.decode(r.bodyBytes, allowMalformed: true)
              );
            } catch (e) {
              last = e;
              await Future<void>.delayed(const Duration(milliseconds: 400));
            }
          }
          return (599, '$last');
        });
        status = answer.$1;
        text = answer.$2;
        if (status == 200) {
          file.writeAsStringSync(jsonEncode({
            'request': id,
            'at': DateTime.now().toUtc().toIso8601String(),
            'status': status,
            'body': text,
          }));
        } else {
          log.add('FAILED $id: $text');
        }
      } finally {
        inFlight--;
      }
    }
    log.add('$status ${request.method} ${request.url}');
    return http.StreamedResponse(
      Stream.value(utf8.encode(text)),
      status,
      request: request,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );
  }
}

late final _Recorder _http;

/// Runs [body] on the real event loop with the recorded client in place.
Future<T> _real<T>(WidgetTester tester, Future<T> Function() body) async {
  final out = await tester
      .runAsync(() => http.runWithClient(body, () => _http));
  return out as T;
}

// ───────────────────────────── drawing ─────────────────────────────

const _phone = Size(393, 852);

/// Taller than a phone, to see what sits under the chart in one image.
const _tall = Size(393, 1400);
const _shotKey = ValueKey('chart-audit-shot');

class _NoPriceSocket extends LivePriceNotifier {
  _NoPriceSocket(this.live);
  final bool live;
  @override
  LivePriceState build() => LivePriceState(live: live);
  @override
  void acquire() {}
  @override
  void release() {}
  @override
  void pause() {}
  @override
  void resume() {}
  @override
  void subscribeTokens(List<String> tokenIds) {}
  @override
  void addTokens(List<String> tokenIds, {bool pin = true}) {}
  @override
  void registerCardTokens(List<String> tokenIds) {}
  @override
  void unregisterCardTokens(List<String> tokenIds) {}
  @override
  void removeTokens(List<String> tokenIds) {}
  @override
  void unsubscribeAll() {}
}

class _NoScoreSocket extends SportsLiveNotifier {
  @override
  Map<String, SportsMatchUpdate> build() => const {};
  @override
  void connect() {}
}

List<Override> _polyOverrides({
  bool live = true,
  List<PolymarketPosition> positions = const [],
}) =>
    [
      livePriceProvider.overrideWith(() => _NoPriceSocket(live)),
      sportsLiveProvider.overrideWith(_NoScoreSocket.new),
      polymarketActivePositionsProvider.overrideWithValue(positions),
      polymarketClaimablePositionsProvider.overrideWithValue(const []),
      aiEnabledProvider.overrideWith((ref) async => false),
    ];

Future<void> _show(
  WidgetTester tester,
  Widget child, {
  required bool dark,
  List<Override> overrides = const [],
  Size size = _phone,
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  // A fresh scope each time: nothing carried over from the last case.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(ProviderScope(
    key: UniqueKey(),
    overrides: overrides,
    child: ScreenUtilInit(
      designSize: const Size(430, 932),
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dark ? buildDarkTheme() : buildLightTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RepaintBoundary(key: _shotKey, child: child),
      ),
    ),
  ));
  await _settle(tester);
}

/// Lets the reads the widgets started answer, then the entry animations
/// finish.
Future<void> _settle(WidgetTester tester) async {
  var calm = 0;
  for (var i = 0; i < 400 && calm < 6; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 70)));
    await tester.pump(const Duration(milliseconds: 40));
    calm = _http.inFlight == 0 ? calm + 1 : 0;
  }
  // A large answer is decoded on another isolate, which the request count
  // does not see: wait while a chart is still its placeholder.
  for (var i = 0;
      i < 80 && find.byType(SkeletonLineChart).evaluate().isNotEmpty;
      i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 40));
  }
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

final List<String> _problems = [];

/// A layout overflow or a thrown build is a finding, not a reason to stop.
/// The image cache's missing plugins are neither.
void _drain(WidgetTester tester, String name) {
  for (Object? e = tester.takeException();
      e != null;
      e = tester.takeException()) {
    final text = '$e'.split('\n').first;
    if (text.contains('databaseFactory') ||
        text.contains('MissingPluginException') ||
        text.contains('Multiple exceptions')) {
      continue;
    }
    _problems.add('$name: $text');
  }
}

Future<void> _shot(WidgetTester tester, String name) async {
  _drain(tester, name);
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_shotKey));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_out/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  });
  // ignore: avoid_print
  print('AUDIT wrote $name.png');
}

/// Taps a range pill of the Predictions chart ("1H", "1D", "ALL").
/// False when the chart does not offer that range (a finished game has no
/// LIVE or 1H).
Future<bool> _range(WidgetTester tester, String label) async {
  final pill = find.text(label);
  if (pill.evaluate().isEmpty) {
    _notes.add('no "$label" range pill offered');
    return false;
  }
  await tester.tap(pill.first, warnIfMissed: false);
  await _settle(tester);
  return true;
}

/// What each case drew, for the report.
final List<String> _notes = [];
final Map<String, String> _liveSlugs = {};

void _note(String label, PolymarketEvent e) {
  final line = '$label: ${e.slug} (${e.outcomes.length} outcomes, '
      'volume ${e.volume.round()}, score ${e.score}, period ${e.period})';
  _notes.add(line);
  // ignore: avoid_print
  print('AUDIT $line');
}

/// Gamma rows as Gamma sends them, for picking today's examples.
Future<List<Map<String, dynamic>>> _gamma(
        WidgetTester tester, Map<String, String> params, int limit) =>
    _real(
        tester,
        () async => (await PolymarketModel.readGammaKeysetPage('events', params,
                limit: limit, direct: true))
            .rows);

/// One event through the read the app's own sheets use.
Future<PolymarketEvent?> _event(WidgetTester tester, String slug) =>
    _real(tester, () async {
      final model = PolymarketModel();
      try {
        return await model.getEventDetailsBySlug(slug);
      } finally {
        model.dispose();
      }
    });

/// A long press on the chart: the crosshair, the scale and the readout.
Future<void> _scrub(WidgetTester tester, String name,
    {Type chart = MarketChart, double at = 0.42}) async {
  final found = find.byType(chart);
  if (found.evaluate().isEmpty) {
    _problems.add('$name: no chart to press');
    return;
  }
  final rect = tester.getRect(found.first);
  final gesture = await tester.startGesture(
      Offset(rect.left + rect.width * at, rect.top + rect.height * 0.45));
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pump(const Duration(milliseconds: 400));
  await _shot(tester, name);
  await gesture.up();
  await tester.pump(const Duration(milliseconds: 400));
}

// ───────────────────────────── Investing ─────────────────────────────

class _HlPrices extends HlLivePricesNotifier {
  _HlPrices(this.mids);
  final Map<String, double> mids;
  @override
  HlLivePriceState build() => HlLivePriceState(mids: mids);
  @override
  void watchCoins(List<String> coins, {Map<String, String>? wire}) {}
  @override
  void focus(String coin, {String? wire}) {}
  @override
  void unfocus(String coin) {}
  @override
  void acquire() {}
  @override
  void release() {}
}

class _PmLoading extends PolymarketTradingNotifier {
  @override
  Future<PolymarketTradingState> build() =>
      Completer<PolymarketTradingState>().future;
}

class _HlLayout extends HlChartLayoutNotifier {
  _HlLayout(this.layout);
  final HlChartLayout layout;
  @override
  HlChartLayout build() => layout;
}

class _HlPrefs extends ChartPreferencesNotifier {
  _HlPrefs(this.layers);
  final Set<String> layers;
  @override
  ChartPreferences build(String arg) => ChartPreferences(indicators: layers);
}

class _HlTrading extends HyperliquidTradingNotifier {
  _HlTrading(this.orders, this.positions);
  final List<HlOpenOrder> orders;
  final List<HlPerpPosition> positions;
  @override
  Future<HyperliquidTradingState> build() async => HyperliquidTradingState(
        isInitialized: true,
        openOrders: orders,
        positions: positions,
      );
}

List<Override> _hlOverrides(
  List<HlMarket> markets, {
  required String style,
  required String interval,
  Set<String> layers = const {'vol'},
  List<HlPerpPosition> positions = const [],
  List<HlOpenOrder> orders = const [],
  List<HlBigTrade> bigTrades = const [],
}) =>
    [
      hyperliquidLivePricesProvider.overrideWith(() => _HlPrices({
            for (final m in markets)
              m.coin: m.midPx > 0 ? m.midPx : m.markPx,
          })),
      hlChartLayoutProvider.overrideWith(
          () => _HlLayout(HlChartLayout(style: style, interval: interval))),
      hlChartPreferencesProvider.overrideWith(() => _HlPrefs(layers)),
      hyperliquidTradingProvider
          .overrideWith(() => _HlTrading(orders, positions)),
      hyperliquidPerpPositionsProvider.overrideWith((_) => positions),
      hyperliquidSpotBalancesProvider.overrideWith((_) => const []),
      hyperliquidActivityFillsProvider.overrideWith((_) => const []),
      hyperliquidTradeFlowProvider.overrideWith(
          (ref, coin) => Stream.value(HlTradeFlowState(bigTrades: bigTrades))),
      aiEnabledProvider.overrideWith((ref) async => false),
    ];

List<HlMarket> _hl = const [];

/// Every Investing market, through the app's own catalogue providers.
Future<List<HlMarket>> _hlMarkets(WidgetTester tester) async {
  if (_hl.isNotEmpty) return _hl;
  return _hl = await _real(tester, () async {
    final box = ProviderContainer();
    try {
      final perps = await box.read(hyperliquidPerpMarketsProvider.future);
      final spots = await box.read(hyperliquidSpotMarketsProvider.future);
      return [...perps, ...spots];
    } finally {
      box.dispose();
    }
  });
}

void _noteHl(String label, HlMarket m) {
  final line = '$label: ${m.coin} (${m.kind.name}, wire ${m.wireCoin}, '
      'dex "${m.dex}", 24h volume ${m.dayNtlVlm.round()}, '
      'low liquidity ${m.isLowLiquidity})';
  _notes.add(line);
  // ignore: avoid_print
  print('AUDIT $line');
}

void _case(String name, Future<void> Function(WidgetTester tester) body) {
  testWidgets(name, (tester) async {
    // Its own error zone: the image cache's missing plugins fail in the
    // background and are not what is being looked at.
    final done = Completer<void>();
    runZonedGuarded(() async {
      try {
        await http.runWithClient(() => body(tester), () => _http);
      } catch (error) {
        _problems.add('$name: stopped by ${'$error'.split('\n').first}');
      } finally {
        done.complete();
      }
    }, (error, stack) {
      final text = '$error'.split('\n').first;
      // Local stores and plugins that do not exist in a test.
      if (text.contains('databaseFactory') ||
          text.contains('MissingPluginException') ||
          text.contains('HiveError') ||
          // A read that answered after its screen was taken down.
          text.contains('after `dispose` was called')) {
        return;
      }
      _problems.add('$name: uncaught $text');
    });
    await done.future;
    // Tear the tree down inside the test so its timers go with it.
    await tester.pumpWidget(const SizedBox.shrink());
    // Sockets that could not open give up on timers of their own.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(seconds: 10));
    }
    _drain(tester, name);
  },
      skip: _only.isNotEmpty && !name.contains(_only),
      timeout: const Timeout(Duration(minutes: 15)));
}

// ───────────────────────────── cases ─────────────────────────────

List<PolymarketEvent> _top = const [];

/// Gamma's most traded events of the day, read once.
Future<List<PolymarketEvent>> _topEvents(WidgetTester tester) async {
  if (_top.isNotEmpty) return _top;
  return _top = await _real(tester, () async {
    final model = PolymarketModel();
    try {
      return await model.listEvents(limit: 60, order: 'volume24hr');
    } finally {
      model.dispose();
    }
  });
}

bool _isRound(PolymarketEvent e) =>
    RegExp(r'-(5|15)m-|updown|up-or-down').hasMatch(e.slug);
bool _isGame(PolymarketEvent e) => e.gameId != null || e.metadataGameId != null;

void main() {
  if (!_enabled) {
    test('chart audit', () {},
        skip: 'on demand: --dart-define=CHART_AUDIT=true');
    return;
  }

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    Directory('$_out/fixtures').createSync(recursive: true);
    // An answer older than a quarter of an hour is no longer what the
    // market looks like: it is read again.
    for (final f in Directory('$_out/fixtures').listSync().whereType<File>()) {
      if (DateTime.now().difference(f.lastModifiedSync()) >
          const Duration(minutes: 15)) {
        f.deleteSync();
      }
    }
    _http = _Recorder(Directory('$_out/fixtures'));
    GoogleFonts.config.allowRuntimeFetching = false;
    // The feed and the game timelines come through the Kute backend, as
    // they do in the app.
    dotenv.loadFromString(envString: 'BACKEND=$_backend');
    // The app's text face, under the family name the theme asks for, and
    // every icon font the bundle carries.
    // Text painted with no family at all (chart tags and scales) is the
    // system face on a phone; here it is Inter too, in place of the test
    // binding's block font.
    for (final family in [GoogleFonts.inter().fontFamily!, 'FlutterTest']) {
      final inter = FontLoader(family);
      for (final f in ['Regular', 'SemiBold', 'Bold']) {
        inter.addFont(rootBundle.load('lib/assets/fonts/Inter-$f.ttf'));
      }
      await inter.load();
    }
    // The app's local stores, in a folder of their own.
    Hive.init('$_out/hive');
    // The image cache asks for a directory; there is none here.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => '$_out/cache');
    final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json'))
        as List<dynamic>;
    for (final entry in manifest.cast<Map<String, dynamic>>()) {
      final loader = FontLoader(entry['family'] as String);
      for (final font in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
  });

  tearDownAll(() {
    File('$_out/requests.log').writeAsStringSync(_http.log.join('\n'));
    File('$_out/problems.log').writeAsStringSync(_problems.join('\n'));
    File('$_out/cases.log')
        .writeAsStringSync(_notes.join('\n'), mode: FileMode.append);
    // ignore: avoid_print
    print('AUDIT problems:\n${_problems.join('\n')}');
  });

  _case('01 yes-no market', (tester) async {
    final events = await _topEvents(tester);
    final event = events.firstWhere(
        (e) => e.isBinary && !_isGame(e) && !_isRound(e) && e.volume > 500000);
    _note('01', event);
    for (final dark in [false, true]) {
      final theme = dark ? 'dark' : 'light';
      await _show(tester, MarketDetailSheet(event: event),
          dark: dark, overrides: _polyOverrides());
      await _shot(tester, '01_yesno_ALL_$theme');
      await _scrub(tester, '01_yesno_ALL_scrub_$theme');
      await _range(tester, '1D');
      await _shot(tester, '01_yesno_1D_$theme');
      await _range(tester, '1H');
      await _shot(tester, '01_yesno_1H_$theme');
    }
  });

  _case('02 many outcomes', (tester) async {
    final events = await _topEvents(tester);
    final event = events.firstWhere((e) =>
        !e.isBinary && !_isGame(e) && !_isRound(e) && e.outcomes.length >= 10);
    _note('02', event);
    for (final dark in [false, true]) {
      final theme = dark ? 'dark' : 'light';
      await _show(tester, MarketDetailSheet(event: event),
          dark: dark, overrides: _polyOverrides(), size: _tall);
      await _shot(tester, '02_many_ALL_$theme');
      if (!dark) await _scrub(tester, '02_many_ALL_scrub_$theme');
      await _range(tester, '1D');
      await _shot(tester, '02_many_1D_$theme');
    }
  });

  _case('03 young many outcomes', (tester) async {
    final rows = await _gamma(tester, {
      'closed': 'false',
      'order': 'startDate',
      'ascending': 'false',
      'volume_min': '300',
    }, 100);
    final now = DateTime.now();
    final young = [
      for (final r in rows)
        if ((r['markets'] as List? ?? const []).length >= 4 &&
            r['gameId'] == null &&
            !RegExp(r'updown|up-or-down').hasMatch('${r['slug']}') &&
            now.difference(DateTime.tryParse('${r['startDate']}') ?? now) <
                const Duration(hours: 30))
          '${r['slug']}'
    ];
    if (young.isEmpty) {
      _problems.add('03: no many-outcome event under 30 hours old today');
      return;
    }
    var n = 0;
    for (final slug in young.take(2)) {
      final event = await _event(tester, slug);
      if (event == null) continue;
      n++;
      _note('03', event);
      await _show(tester, MarketDetailSheet(event: event),
          dark: false, overrides: _polyOverrides(), size: _tall);
      await _shot(tester, '03_young_${n}_ALL_light');
      await _range(tester, '1D');
      await _shot(tester, '03_young_${n}_1D_light');
    }
  });

  _case('04 live games', (tester) async {
    final rows = await _gamma(tester, {
      'closed': 'false',
      'live': 'true',
      'order': 'volume24hr',
      'ascending': 'false',
    }, 100);
    final main = RegExp(r'^[a-z0-9]+-[a-z0-9]+-[a-z0-9]+-\d{4}-\d{2}-\d{2}$');
    List<String> tagsOf(Map<String, dynamic> r) => [
          for (final t in (r['tags'] as List? ?? const []))
            '${(t as Map)['slug']}'
        ];
    String? pick(bool Function(List<String> tags) want) {
      for (final r in rows) {
        if (r['ended'] == true || !main.hasMatch('${r['slug']}')) continue;
        // Gamma flags a game live before kickoff: one with a score.
        if ('${r['score'] ?? ''}'.isEmpty) continue;
        if (want(tagsOf(r))) return '${r['slug']}';
      }
      return null;
    }

    final picks = <String, String?>{
      'twoway': pick((t) =>
          t.any((x) => const {'nfl', 'nba', 'mlb', 'nhl', 'cfb'}.contains(x))),
      'soccer': pick((t) => t.contains('soccer')),
      'esports': pick((t) => t.contains('esports')),
      'tennis': pick((t) => t.contains('tennis')),
    };
    for (final entry in picks.entries) {
      final slug = entry.value;
      if (slug == null) {
        _problems.add('04: no live ${entry.key} game right now');
        continue;
      }
      final event = await _event(tester, slug);
      if (event == null) continue;
      _note('04 ${entry.key}', event);
      _liveSlugs[entry.key] = slug;
      for (final dark in [false, if (entry.key == 'twoway') true]) {
        await _show(tester, MarketDetailSheet(event: event),
            dark: dark, overrides: _polyOverrides(), size: _tall);
        await _shot(
            tester, '04_live_${entry.key}_${dark ? 'dark' : 'light'}');
        if (!dark) await _scrub(tester, '04_live_${entry.key}_scrub_light');
      }
    }
  });

  // What a range pill does to the window and the scale: the opening view,
  // then each range in turn, then the opening range again.
  _case('16 range changes', (tester) async {
    final main = RegExp(r'^[a-z0-9]+-[a-z0-9]+-[a-z0-9]+-\d{4}-\d{2}-\d{2}$');
    final live = await _gamma(tester, {
      'closed': 'false',
      'live': 'true',
      'order': 'volume24hr',
      'ascending': 'false',
    }, 100);
    String? liveSlug;
    for (final r in live) {
      final tags = [
        for (final t in (r['tags'] as List? ?? const [])) '${(t as Map)['slug']}'
      ];
      if (r['ended'] != true &&
          '${r['score'] ?? ''}'.isNotEmpty &&
          main.hasMatch('${r['slug']}') &&
          tags.any((x) => const {'nfl', 'nba', 'mlb', 'nhl'}.contains(x))) {
        liveSlug = '${r['slug']}';
        break;
      }
    }
    String? doneSlug;
    for (final tag in ['nfl', 'mlb', 'nhl']) {
      final rows = await _gamma(tester, {
        'closed': 'false',
        'tag_slug': tag,
        'order': 'volume24hr',
        'ascending': 'false',
      }, 60);
      for (final r in rows) {
        if (r['ended'] == true && main.hasMatch('${r['slug']}')) {
          doneSlug = '${r['slug']}';
          break;
        }
      }
      if (doneSlug != null) break;
    }
    Future<void> walk(String label, PolymarketEvent event, bool live) async {
      _note('16 $label', event);
      await _show(tester, MarketDetailSheet(event: event),
          dark: false, overrides: _polyOverrides(live: live));
      await _shot(tester, '16_${label}_0_open');
      var n = 0;
      for (final range in ['1H', '6H', '1D', '1W', 'ALL', '6H', '1D']) {
        n++;
        if (await _range(tester, range)) {
          await _shot(tester, '16_${label}_${n}_$range');
        }
      }
    }

    if (liveSlug == null) {
      _problems.add('16: no live two-sided game right now');
    } else {
      final event = await _event(tester, liveSlug);
      if (event != null) await walk('live_game', event, true);
    }
    if (doneSlug == null) {
      _problems.add('16: no game that just finished');
    } else {
      final event = await _event(tester, doneSlug);
      if (event != null) await walk('finished_game', event, false);
    }
    final events = await _topEvents(tester);
    final market = events.firstWhere((e) =>
        e.isBinary &&
        !_isGame(e) &&
        !_isRound(e) &&
        e.volume > 500000 &&
        e.yesPrice > 0.1 &&
        e.yesPrice < 0.9);
    await walk('market', market, true);
    final many = events.firstWhere((e) =>
        !e.isBinary && !_isGame(e) && !_isRound(e) && e.outcomes.length >= 4);
    await walk('many', many, true);
  });

  _case('05 finished game', (tester) async {
    final main = RegExp(r'^[a-z0-9]+-[a-z0-9]+-[a-z0-9]+-\d{4}-\d{2}-\d{2}$');
    String? slug;
    String? kind;
    for (final tag in ['nfl', 'mlb', 'nba', 'nhl', 'soccer']) {
      final rows = await _gamma(tester, {
        'closed': 'false',
        'tag_slug': tag,
        'order': 'volume24hr',
        'ascending': 'false',
      }, 60);
      for (final r in rows) {
        if (r['ended'] == true && main.hasMatch('${r['slug']}')) {
          slug = '${r['slug']}';
          kind = tag;
          break;
        }
      }
      if (slug != null) break;
    }
    if (slug == null) {
      _problems.add('05: no game that just finished on Gamma right now');
      return;
    }
    final event = await _event(tester, slug);
    if (event == null) return;
    _note('05 $kind', event);
    for (final dark in [false, true]) {
      await _show(tester, MarketDetailSheet(event: event),
          dark: dark, overrides: _polyOverrides(live: false), size: _tall);
      await _shot(tester, '05_finished_${dark ? 'dark' : 'light'}');
    }
    await _scrub(tester, '05_finished_scrub_dark');
  });

  _case('06 crypto rounds', (tester) async {
    for (final minutes in [5, 15]) {
      PolymarketEvent? event;
      for (var back = 0; back < 3 && event == null; back++) {
        event = await _event(tester,
            PolymarketModel.cryptoWindowSlug('btc', minutes, windowsBack: back));
      }
      if (event == null) {
        _problems.add('06: no BTC $minutes-minute round on Gamma');
        continue;
      }
      _note('06 ${minutes}m', event);
      for (final dark in [false, true]) {
        final theme = dark ? 'dark' : 'light';
        await _show(
          tester,
          minutes == 5
              ? FiveMinMarketDetailSheet(event: event)
              : MarketDetailSheet(event: event),
          dark: dark,
          overrides: _polyOverrides(),
        );
        await _shot(tester, '06_round_${minutes}m_$theme');
        if (minutes == 15 && !dark) {
          await _range(tester, '1H');
          await _shot(tester, '06_round_15m_1H_$theme');
          await _range(tester, 'ALL');
          await _shot(tester, '06_round_15m_ALL_$theme');
        }
      }
    }
  });

  _case('07 open positions', (tester) async {
    // No account is read: the position is made up around the market's
    // real price (bought a fifth under it), to draw the "Bought" tick on
    // the position screen's chance bar and the line on the market sheet.
    final events = await _topEvents(tester);
    final market = events.firstWhere(
        (e) => e.isBinary && !_isGame(e) && !_isRound(e) && e.volume > 500000 &&
            e.yesPrice > 0.15 && e.yesPrice < 0.85);
    _note('07 yes-no', market);
    PolymarketPosition held(PolymarketEvent e, String outcome, String token,
        double price) {
      final avg = (price * 0.8 * 100).roundToDouble() / 100;
      return PolymarketPosition(
        marketId: e.conditionId,
        marketQuestion: e.title,
        outcome: outcome,
        size: 120,
        avgPrice: avg,
        currentPrice: price,
        pnl: (price - avg) * 120,
        pnlPercent: (price - avg) / avg * 100,
        isResolved: false,
        tokenId: token,
        eventSlug: e.slug,
      );
    }

    final yesNo = held(market, 'Yes', market.yesTokenId!, market.yesPrice);
    for (final dark in [false, true]) {
      await _show(tester, PositionDetailSheet(position: yesNo),
          dark: dark,
          overrides: _polyOverrides(positions: [yesNo]),
          size: _tall);
      await _shot(tester, '07_position_yesno_${dark ? 'dark' : 'light'}');
    }
    // The same market's own sheet draws the "Bought" line on its chart.
    await _show(tester, MarketDetailSheet(event: market),
        dark: false, overrides: _polyOverrides(positions: [yesNo]));
    await _shot(tester, '07_position_yesno_market_sheet_light');

    // A game: the side of its winner market.
    final rows = await _gamma(tester, {
      'closed': 'false',
      'live': 'true',
      'order': 'volume24hr',
      'ascending': 'false',
    }, 100);
    final main = RegExp(r'^[a-z0-9]+-[a-z0-9]+-[a-z0-9]+-\d{4}-\d{2}-\d{2}$');
    for (final r in rows) {
      if (r['ended'] == true || !main.hasMatch('${r['slug']}')) continue;
      Map<String, dynamic>? winner;
      for (final m in (r['markets'] as List).cast<Map<String, dynamic>>()) {
        if (m['sportsMarketType'] == 'moneyline') winner = m;
      }
      if (winner == null) continue;
      final names = (jsonDecode('${winner['outcomes']}') as List).cast<String>();
      final tokens =
          (jsonDecode('${winner['clobTokenIds']}') as List).cast<String>();
      final prices = [
        for (final p in jsonDecode('${winner['outcomePrices']}') as List)
          double.parse('$p')
      ];
      if (names.length != 2 || names.contains('Yes')) continue;
      final side = prices[0] >= prices[1] ? 0 : 1;
      if (prices[side] > 0.93) continue;
      final event = await _event(tester, '${r['slug']}');
      if (event == null) continue;
      _note('07 game', event);
      final position = PolymarketPosition(
        marketId: '${winner['conditionId']}',
        marketQuestion: event.title,
        outcome: names[side],
        size: 80,
        avgPrice: ((prices[side] * 0.8) * 100).roundToDouble() / 100,
        currentPrice: prices[side],
        pnl: prices[side] * 0.2 * 80,
        pnlPercent: 25,
        isResolved: false,
        tokenId: tokens[side],
        eventSlug: event.slug,
      );
      for (final dark in [false, true]) {
        await _show(tester, PositionDetailSheet(position: position),
            dark: dark,
            overrides: _polyOverrides(positions: [position]),
            size: _tall);
        await _shot(tester, '07_position_game_${dark ? 'dark' : 'light'}');
      }
      await _show(tester, MarketDetailSheet(event: event),
          dark: false,
          overrides: _polyOverrides(positions: [position]),
          size: _tall);
      await _shot(tester, '07_position_game_market_sheet_light');
      return;
    }
    _problems.add('07: no live two-sided game to hold a side of');
  });

  _case('08 thin market', (tester) async {
    final rows = await _gamma(tester, {
      'closed': 'false',
      'order': 'volume',
      'ascending': 'true',
      'volume_min': '150',
      'end_date_min': DateTime.now()
          .toUtc()
          .add(const Duration(days: 7))
          .toIso8601String(),
    }, 80);
    final now = DateTime.now();
    var n = 0;
    for (final r in rows) {
      if ((r['markets'] as List? ?? const []).length != 1 ||
          r['gameId'] != null ||
          now.difference(DateTime.tryParse('${r['startDate']}') ?? now) <
              const Duration(days: 10)) {
        continue;
      }
      final event = await _event(tester, '${r['slug']}');
      if (event == null || !event.isBinary) continue;
      n++;
      _note('08', event);
      await _show(tester, MarketDetailSheet(event: event),
          dark: n == 2, overrides: _polyOverrides());
      final theme = n == 2 ? 'dark' : 'light';
      await _shot(tester, '08_thin_${n}_ALL_$theme');
      await _range(tester, '1W');
      await _shot(tester, '08_thin_${n}_1W_$theme');
      await _range(tester, '1D');
      await _shot(tester, '08_thin_${n}_1D_$theme');
      if (n == 2) break;
    }
    if (n == 0) _problems.add('08: no thin yes/no market found');
  });

  _case('14 predictions cards', (tester) async {
    final events = await _topEvents(tester);
    final rows = await _gamma(tester, {
      'closed': 'false',
      'live': 'true',
      'order': 'volume24hr',
      'ascending': 'false',
    }, 100);
    final main = RegExp(r'^[a-z0-9]+-[a-z0-9]+-[a-z0-9]+-\d{4}-\d{2}-\d{2}$');
    final games = <PolymarketEvent>[];
    for (final r in rows) {
      if (games.length == 3) break;
      if (!main.hasMatch('${r['slug']}')) continue;
      final e = await _event(tester, '${r['slug']}');
      if (e != null) games.add(e);
    }
    final shown = [
      ...events.where((e) => e.isBinary && !_isGame(e) && !_isRound(e)).take(2),
      ...events
          .where((e) => !e.isBinary && !_isGame(e) && !_isRound(e))
          .take(2),
      ...games,
    ];
    for (final e in shown) {
      _note('14', e);
    }
    for (final dark in [false, true]) {
      await _show(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(children: [
              for (final e in shown)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: MarketCard(
                    title: e.title,
                    imageUrl: e.imageUrl,
                    outcomes: e.outcomes,
                    volume: e.volume,
                    volume24hr: e.volume24hr,
                    category: e.category,
                    startDate: e.startDate,
                    gameStart: e.gameStart,
                    endDate: e.endDate,
                    active: e.active,
                    closed: e.closed,
                    ended: e.ended,
                    liveGame:
                        e.isSportsCategory ? PolyLiveGame.of(e, null) : null,
                    teams: e.teams,
                    slug: e.slug,
                    gameId: e.gameId,
                    hasLivestream: e.hasLivestream,
                    dayMove: e.oneDayPriceChange,
                  ),
                ),
            ]),
          ),
        ),
        dark: dark,
        overrides: _polyOverrides(),
        size: const Size(393, 1700),
      );
      await _shot(tester, '14_cards_predictions_${dark ? 'dark' : 'light'}');
    }
  });

  // ─────────────────────────── Investing ───────────────────────────

  Future<void> market(
    WidgetTester tester,
    HlMarket m,
    String name, {
    required String style,
    required String interval,
    bool dark = false,
    Set<String> layers = const {'vol'},
    List<HlPerpPosition> positions = const [],
    List<HlOpenOrder> orders = const [],
    List<HlBigTrade> bigTrades = const [],
    Size size = _phone,
  }) async {
    await _show(
      tester,
      HlMarketDetailSheet(market: m),
      dark: dark,
      size: size,
      overrides: _hlOverrides(
        [m],
        style: style,
        interval: interval,
        layers: layers,
        positions: positions,
        orders: orders,
        bigTrades: bigTrades,
      ),
    );
    await _shot(tester, name);
  }

  _case('09 BTC perp', (tester) async {
    final all = await _hlMarkets(tester);
    final btc = all.firstWhere((m) => m.coin == 'BTC' && !m.isSpot);
    _noteHl('09', btc);
    for (final dark in [false, true]) {
      final theme = dark ? 'dark' : 'light';
      await market(tester, btc, '09_btc_5m_line_$theme',
          style: 'area', interval: '5m', dark: dark);
      if (!dark) {
        await _scrub(tester, '09_btc_5m_line_scrub_$theme',
            chart: HlCandlestickChart);
      }
      await market(tester, btc, '09_btc_5m_candles_$theme',
          style: 'candles', interval: '5m', dark: dark);
      await market(tester, btc, '09_btc_1d_candles_$theme',
          style: 'candles', interval: '1d', dark: dark);
    }
    await market(tester, btc, '09_btc_1d_line_light',
        style: 'area', interval: '1d');
  });

  _case('10 thin spot', (tester) async {
    final all = await _hlMarkets(tester);
    final spots = all.where((m) => m.isSpot && m.isLowLiquidity).toList()
      ..sort((a, b) => b.dayNtlVlm.compareTo(a.dayNtlVlm));
    final picked = [
      ...all.where((m) => m.isSpot && m.coin.toUpperCase().contains('GOOGL')),
      ...spots,
    ].take(2).toList();
    if (picked.isEmpty) {
      _problems.add('10: no low-liquidity spot market today');
      return;
    }
    var n = 0;
    for (final m in picked) {
      n++;
      _noteHl('10', m);
      // As it opens: the saved layout is the app's default (1h candles).
      await market(tester, m, '10_thin_spot_${n}_open_light',
          style: 'candles', interval: '1h');
      await market(tester, m, '10_thin_spot_${n}_open_line_dark',
          style: 'area', interval: '1h', dark: true);
      // The person picks 5m themselves.
      await _show(tester, HlMarketDetailSheet(market: m),
          dark: false,
          overrides: _hlOverrides([m], style: 'candles', interval: '1h'));
      await _range(tester, '5m');
      await _shot(tester, '10_thin_spot_${n}_forced_5m_light');
    }
  });

  _case('11 stock perp and index', (tester) async {
    final all = await _hlMarkets(tester);
    final perps = all.where((m) => !m.isSpot && m.dex.isNotEmpty).toList();
    final picks = <String, HlMarket?>{
      'stock': perps
          .where((m) => m.coin.toUpperCase().contains('TSLA'))
          .firstOrNull,
      'index': perps
          .where((m) => RegExp(r'XYZ100|SPX|SP500|NDX|US500|USTECH')
              .hasMatch(m.coin.toUpperCase()))
          .firstOrNull,
    };
    for (final e in picks.entries) {
      final m = e.value;
      if (m == null) {
        _problems.add('11: no ${e.key} perp found');
        continue;
      }
      _noteHl('11 ${e.key}', m);
      await market(tester, m, '11_${e.key}_open_candles_light',
          style: 'candles', interval: '1h');
      await market(tester, m, '11_${e.key}_5m_line_dark',
          style: 'area', interval: '5m', dark: true);
      await market(tester, m, '11_${e.key}_1d_candles_light',
          style: 'candles', interval: '1d');
    }
  });

  _case('12 position lines', (tester) async {
    // No account is read: a long opened 1.5% under today's price, with
    // its liquidation, a take-profit and a stop, to draw the lines.
    final all = await _hlMarkets(tester);
    final btc = all.firstWhere((m) => m.coin == 'BTC' && !m.isSpot);
    final px = btc.midPx > 0 ? btc.midPx : btc.markPx;
    double r(double v) => (v / 10).roundToDouble() * 10;
    final position = HlPerpPosition(
      coin: btc.wireCoin,
      szi: 0.05,
      entryPx: r(px * 0.985),
      positionValue: px * 0.05,
      unrealizedPnl: px * 0.015 * 0.05,
      returnOnEquity: 0.075,
      liquidationPx: r(px * 0.93),
      marginUsed: px * 0.05 / 5,
      leverageType: 'isolated',
      leverageValue: 5,
      maxLeverage: btc.maxLeverage,
      fundingSinceOpen: 0.42,
    );
    HlOpenOrder trigger(int oid, String type, double at) => HlOpenOrder(
          coin: btc.wireCoin,
          oid: oid,
          isBuy: false,
          limitPx: at,
          sz: 0.05,
          origSz: 0.05,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          cloid: null,
          reduceOnly: true,
          orderType: type,
          isTrigger: true,
          triggerPx: at,
          isPositionTpsl: true,
        );
    final orders = [
      trigger(1, 'Take Profit Market', r(px * 1.02)),
      trigger(2, 'Stop Market', r(px * 0.975)),
    ];
    // Lines that sit close together: a stop just under the entry.
    final tight = [
      trigger(1, 'Take Profit Market', r(px * 0.99)),
      trigger(2, 'Stop Market', r(px * 0.982)),
    ];
    for (final dark in [false, true]) {
      final theme = dark ? 'dark' : 'light';
      await market(tester, btc, '12_position_market_sheet_1h_$theme',
          style: 'candles',
          interval: '1h',
          dark: dark,
          positions: [position],
          orders: orders);
      await _show(
        tester,
        HlPositionDetailSheet(position: position, market: btc),
        dark: dark,
        size: _tall,
        overrides: _hlOverrides([btc],
            style: 'candles',
            interval: '1h',
            positions: [position],
            orders: orders),
      );
      await _shot(tester, '12_position_sheet_$theme');
    }
    await market(tester, btc, '12_position_market_sheet_5m_tight_light',
        style: 'area',
        interval: '5m',
        positions: [position],
        orders: tight);
  });

  _case('13 layers', (tester) async {
    final all = await _hlMarkets(tester);
    final btc = all.firstWhere((m) => m.coin == 'BTC' && !m.isSpot);
    // The app builds its big trades from the live trade stream; here the
    // venue's recent trades go through the same accumulator.
    final big = await _real(tester, () async {
      final resp = await http.post(
        Uri.parse('https://api.hyperliquid.xyz/info'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'type': 'recentTrades', 'coin': btc.wireCoin}),
      );
      final flow = HlTradeFlow();
      final trades = [
        for (final t in (jsonDecode(resp.body) as List))
          HlTrade.fromJson((t as Map).cast<String, dynamic>())
      ]..sort((a, b) => a.time.compareTo(b.time));
      trades.forEach(flow.add);
      return flow.bigTrades;
    });
    _notes.add('13: ${big.length} big trades among the venue\'s recent ones');
    const layers = {
      'vol',
      kHlLayerBigTrades,
      kHlLayerFunding,
      kHlLayerOi,
      kHlLayerCrowd,
      kHlLayerMacro,
    };
    for (final dark in [false, true]) {
      final theme = dark ? 'dark' : 'light';
      await market(tester, btc, '13_layers_1h_candles_$theme',
          style: 'candles',
          interval: '1h',
          dark: dark,
          layers: layers,
          bigTrades: big);
    }
    await market(tester, btc, '13_layers_5m_line_light',
        style: 'area', interval: '5m', layers: layers, bigTrades: big);
    await market(tester, btc, '13_layers_1d_candles_light',
        style: 'candles', interval: '1d', layers: layers, bigTrades: big);
    await market(tester, btc, '13_layers_4h_candles_dark',
        style: 'candles',
        interval: '4h',
        dark: true,
        layers: layers,
        bigTrades: big);
  });

  _case('15 investing cards', (tester) async {
    final all = await _hlMarkets(tester);
    HlMarket? named(String coin, {required bool spot}) => all
        .where((m) => m.coin.toUpperCase() == coin && m.isSpot == spot)
        .firstOrNull;
    final thin = all.where((m) => m.isLowLiquidity).toList()
      ..sort((a, b) => b.dayNtlVlm.compareTo(a.dayNtlVlm));
    final shown = <HlMarket>[
      ...[
        named('BTC', spot: false),
        named('ETH', spot: false),
        named('TSLA', spot: false),
        named('XYZ100', spot: false),
        named('HYPE', spot: true),
        named('GOOGL', spot: true),
      ].whereType<HlMarket>(),
      ...thin.take(3),
    ];
    for (final m in shown) {
      _noteHl('15', m);
    }
    for (final dark in [false, true]) {
      await _show(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(children: [
              for (final m in shown)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: HlMarketCard(market: m, onTap: () {}),
                ),
            ]),
          ),
        ),
        dark: dark,
        overrides:
            _hlOverrides(shown, style: 'candles', interval: '1h'),
        size: const Size(393, 1300),
      );
      await _shot(tester, '15_cards_investing_${dark ? 'dark' : 'light'}');
    }
  });

  _case('17 portfolio statistics', (tester) async {
    // No account of the user's is read. The profit-and-loss series are
    // public ones, through the app's own reader: the top account of
    // Polymarket's monthly leaderboard, and Hyperliquid's HLP vault.
    final leader = await _real(tester, () async {
      final resp = await http.get(Uri.parse(
          'https://data-api.polymarket.com/v2/leaderboard?time_period=month&sort_by=PNL&limit=1'));
      final rows = (jsonDecode(resp.body) as Map)['data'] as List;
      return '${rows.first['user_id']}';
    });
    const hlp = '0xdfc24b077bc1425ad1dea75bcb6f8158e10df303';
    final settings = settingsProvider.overrideWith((_) => SettingsModel(Settings(
        currency: 'USD',
        language: 'en',
        btcFormat: 'sats',
        backup: false,
        biometricsEnabled: false,
        bitcoinElectrumNode: '',
        nodeType: '',
        reviewDone: true,
        balancePrivacy: 0)));
    for (final venue in PortfolioPerformanceVenue.values) {
      final address =
          venue == PortfolioPerformanceVenue.predictions ? leader : hlp;
      for (final dark in [false, true]) {
        final theme = dark ? 'dark' : 'light';
        await _show(
          tester,
          Scaffold(body: PortfolioStatistics(venue: venue)),
          dark: dark,
          overrides: [
            settings,
            livePriceProvider.overrideWith(() => _NoPriceSocket(false)),
            polymarketTradingProvider.overrideWith(_PmLoading.new),
            hyperliquidTradingProvider
                .overrideWith(() => _HlTrading(const [], const [])),
            portfolioPerformanceProvider(
                    PortfolioPerformanceRequest(venue: venue))
                .overrideWith((ref) {
              final service = PortfolioPerformanceService(client: _http);
              return venue == PortfolioPerformanceVenue.predictions
                  ? service.polymarket(address)
                  : service.hyperliquid(address);
            }),
          ],
        );
        await _shot(tester, '17_statistics_${venue.name}_$theme');
      }
    }
  });
}
